#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

## Window and line rendering procedures

import std/[options, strutils, unicode, tables]

import celina_backend as celina

import
  types/editor_types,
  editor_window_layout,
  visible_rows,
  editor_render_helpers,
  render_utils,
  sidebar,
  color,
  unicode_utils,
  search_utils,
  highlight,
  modes,
  colorcode,
  git_conflict,
  style_patch,
  git_cache,
  editor_codelens,
  virtual_text,
  command_line,
  buffer,
  visual_selection,
  visual_block,
  wanted_column
import command_handlers/visual_handler

type
  LineStyleContext* = object
    ## Per-line state used while rendering one buffer line. Values are
    ## computed once at the start of the line (`newLineStyleContext`) and then
    ## read by the per-character style pipeline, replacing what used to be 7+
    ## individually-threaded parameters across getSelectionStyle /
    ## baseStyleWithOverlay / overlayPatchSyntax.
    lineIndex*: int
    bufferId*: BufferId
      ## Buffer being rendered, checked by overlays cached for one buffer at a
      ## time (document highlights). `BufferId(0)` without a buffer.
    lineEnd*: int ## Column just past the line's last character
    isActiveWindow*: bool
    isCursorLine*: bool
    lineConflict*: ConflictMarkerKind
    useTwoColor*: bool
    blockShown*: BlockShown ## What a block selection shows over on this line
    searchRanges*: seq[ColumnRange]
    wordRanges*: seq[ColumnRange]
    colorCodeMatches*: seq[ColorCodeMatch]
    trailingSpaceStart*: int
    lineBg*: Option[ColorValue]
      ## Line-scoped background overlay (Markdown fenced code block). When set,
      ## every cell on this line — including trailing empty cells and any cell
      ## whose syntax segment lacks a bg — inherits this color, so a code block
      ## reads as a uniform stripe rather than only tinted characters. Ranks
      ## below cursor line / cursor column / git conflict / visual selection.

  LinePrecomputed* = object
    ## Per-logical-line values a row is rendered with. The wrap path builds
    ## this once and hands it to every segment call so the O(line) scans in
    ## `newLineStyleContext` / `analyzeIndentation` do not fire per segment.
    indentInfo*: IndentInfo
    lineCtx*: LineStyleContext

template hasSyntaxHighlight(
    e: Editor, buffer: TextBuffer, windowMode: EditorMode
): bool =
  e.showSyntax and not buffer.highlight.isNil and
    (windowMode.isFileEditMode or buffer.language != langNone or buffer.isUtilityBuffer)

proc resolveLineConflict(
    e: Editor, textBuffer: TextBuffer, lineIndex: int
): ConflictMarkerKind =
  ## The line's git-conflict kind, none when the highlight is off.
  if textBuffer != nil and e.config.highlight.gitConflict:
    textBuffer.lineConflictKind(lineIndex)
  else:
    cmkNone

proc resolveLineBg(
    e: Editor, textBuffer: TextBuffer, lineIndex: int
): Option[ColorValue] =
  ## The per-line background overlay (Markdown fenced code block).
  ##
  ## Gated on `e.showSyntax`: without it, character cells fall through the
  ## `hasSyntaxHighlight` branch in `baseStyleWithOverlay` / `syntaxBaseStyle`
  ## and never pick up `lineBg`, so applying it to the trailing fill would
  ## paint an unmatched stripe past the text.
  if not e.showSyntax or textBuffer == nil or not textBuffer.isCodeBlockLine(lineIndex):
    return none(ColorValue)
  let bg = getThemeStyle(EditorColorPairIndex.markdownCodeBlock).bg
  if bg.kind != Default:
    some(bg)
  else:
    none(ColorValue)

proc effectiveSearchSpec(state: EditorState): SearchSpec =
  ## Resolve the search the hlsearch highlight draws, based on overlay state.
  ## - Search overlay: live text being typed, a substring search like / and ?
  ##   An empty prompt means "repeat the last search", so it keeps showing the
  ##   last search's highlights instead of blanking them.
  ## - Command overlay: substitute pattern if present, else last search
  ## - Otherwise: last search
  if state.isSearchOverlay:
    if state.input.search.text.len > 0:
      SearchSpec(pattern: state.input.search.text)
    else:
      state.input.search.last
  elif state.isCommandOverlay:
    let subPattern = extractSubstitutePattern(state.input.commandText)
    if subPattern.len > 0:
      SearchSpec(pattern: subPattern)
    else:
      state.input.search.last
  else:
    state.input.search.last

proc blockShownOn(
    e: Editor, ctx: RenderContext, lineIndex: int, text: string
): BlockShown =
  ## What the window's selection shows over on line `lineIndex` when it is a
  ## block, else nothing.
  if ctx.selection.active and ctx.selection.kind == vskBlock and
      lineIndex in ctx.blockArea.firstLine .. ctx.blockArea.lastLine:
    ctx.blockArea.shownOn(lineIndex, text, e.tabStop)
  else:
    BlockShown()

proc newLineStyleContext*(
    e: Editor,
    textBuffer: TextBuffer,
    lineIndex: int,
    fullLine: string,
    ctx: RenderContext,
    drawsText = true,
): LineStyleContext =
  ## Compute all per-line state needed by the style pipeline in one place.
  ## For a row that draws none of the line's characters (`drawsText` false),
  ## their overlays (trailing spaces, color codes, search, current word) are
  ## left empty without scanning the line.
  result = LineStyleContext(
    lineIndex: lineIndex,
    lineEnd: fullLine.charLen,
    blockShown: e.blockShownOn(ctx, lineIndex, fullLine),
    bufferId:
      if textBuffer != nil:
        textBuffer.id
      else:
        BufferId(0),
    isActiveWindow: ctx.isActiveWindow,
    isCursorLine: lineIndex == ctx.cursorLine,
    lineConflict: e.resolveLineConflict(textBuffer, lineIndex),
    useTwoColor: e.config.highlight.gitConflictTwoColor,
    trailingSpaceStart: high(int), # disabled: `col >= trailingSpaceStart` never matches
    lineBg: resolveLineBg(e, textBuffer, lineIndex),
  )
  if not drawsText:
    return

  # Trailing-space highlighting fires in file-edit mode when enabled (see
  # styleOverrideAt). Skip the whole-line scan when it cannot fire. Don't clip
  # to the cap: trailing whitespace lives at the line *end*, past the cap, so
  # the input must stay the full line.
  if e.config.highlight.trailingSpaces and ctx.windowMode.isFileEditMode:
    result.trailingSpaceStart = findTrailingSpaceStart(fullLine)

  # Bound the color-code scan to the cap: scanLineForColorCodes allocates an
  # O(line) byte->rune map, and past the cap the line is plain text anyway.
  # (Search/current-word ranges stay uncapped: they're functional, not
  # decorative — a match past the cap must still be shown.)
  if e.config.highlight.colorCodeHighlight and ctx.windowMode.isFileEditMode:
    let cap = if textBuffer != nil: textBuffer.maxHighlightLineLength else: 0
    result.colorCodeMatches =
      if cap > 0 and fullLine.len > cap:
        scanLineForColorCodes(fullLine.charSubStr(0, cap))
      else:
        scanLineForColorCodes(fullLine)

  if textBuffer != nil and e.state.input.search.hlsearch and
      not e.state.input.search.hlsearchTempDisabled:
    let spec = e.state.effectiveSearchSpec()
    if spec.pattern.len > 0:
      let shouldIgnoreCase = shouldIgnoreCase(
        spec.pattern, e.state.input.search.ignorecase, e.state.input.search.smartcase
      )
      result.searchRanges = textBuffer.findSearchMatchRanges(
        lineIndex, spec.pattern, shouldIgnoreCase, spec.wholeWord
      )

  if textBuffer != nil and not e.state.isSearchOverlay and e.state.currentWord.len > 0:
    let excludeCol = if lineIndex == ctx.cursorLine: ctx.cursorCol else: -1
    result.wordRanges =
      textBuffer.findWordMatchRanges(lineIndex, e.state.currentWord, excludeCol)

proc linePrecomputed(
    e: Editor,
    textBuffer: TextBuffer,
    lineIndex: int,
    line: string,
    ctx: RenderContext,
    drawsText = true,
): LinePrecomputed =
  ## The values for rendering `line`. A row that draws none of its characters
  ## (`drawsText` false) skips the scans they need.
  LinePrecomputed(
    indentInfo:
      if drawsText:
        analyzeIndentation(line)
      else:
        IndentInfo(),
    lineCtx: e.newLineStyleContext(textBuffer, lineIndex, line, ctx, drawsText),
  )

# Layer predicates
# Each predicate decides whether one style layer fires at a given cell.
# They are pure functions over Editor + (lineCtx and/or pos) — no side
# effects, no style construction. The 4 priority-chain procs below call
# them in order so the priority list reads as a sequence of named checks.

template matchesSnippetStop(
    e: Editor, lineCtx: LineStyleContext, pos: BufferPosition
): bool =
  ## The pending (still selected) default range of the active snippet
  ## tabstop. Anchored to the active window's session; defaults are
  ## single-line so only the stop's own line is painted. The bounds check
  ## short-circuits before the indexed access, so an out-of-range index is
  ## never dereferenced.
  lineCtx.isActiveWindow and e.state.snippetSession.active and
    e.state.snippetSession.defaultPending and
    e.state.snippetSession.index < e.state.snippetSession.stops.len and (
    block:
      let stop = e.state.snippetSession.stops[e.state.snippetSession.index]
      stop.pos.line == pos.line and pos.column >= stop.pos.column and
        pos.column < stop.pos.column + stop.len
  )

template matchesMatchingParen(
    e: Editor, lineCtx: LineStyleContext, pos: BufferPosition
): bool =
  # `matchingParenPos` is derived from the active window's cursor, so the
  # highlight must only be drawn in the active window — other windows may
  # show an unrelated buffer at the same line/column.
  lineCtx.isActiveWindow and e.state.matchingParenPos.isSome and
    e.state.matchingParenPos.get.line == pos.line and
    e.state.matchingParenPos.get.column == pos.column

template matchesFindCharMatch(
    e: Editor, lineCtx: LineStyleContext, pos: BufferPosition
): bool =
  # Like matchingParen, f/F/t/T match candidates are anchored to the active
  # window's cursor line; never paint them in inactive windows.
  lineCtx.isActiveWindow and e.config.highlight.findCharHighlight and
    e.state.ui.findCharMatches.len > 0 and pos.line == e.state.ui.findCharMatchLine and
    pos.column in e.state.ui.findCharMatches

template matchesCurrentWord(
    e: Editor, lineCtx: LineStyleContext, pos: BufferPosition
): bool =
  not e.state.isSearchOverlay and lineCtx.wordRanges.isColumnInRanges(pos.column)

template matchesSearchHighlight(lineCtx: LineStyleContext, pos: BufferPosition): bool =
  lineCtx.searchRanges.isColumnInRanges(pos.column)

template gitConflictApplies(lineCtx: LineStyleContext): bool =
  lineCtx.lineConflict != cmkNone

template cursorLineApplies(e: Editor, lineCtx: LineStyleContext): bool =
  e.showCursorLine and lineCtx.isCursorLine

template cursorColumnApplies(e: Editor, displayCol: int, cursorDisplayCol: int): bool =
  e.showCursorColumn and displayCol >= 0 and displayCol == cursorDisplayCol

proc overlayPatchSyntax(
    e: Editor,
    pos: BufferPosition,
    lineCtx: LineStyleContext,
    displayCol: int,
    cursorDisplayCol: int,
    colorPair: EditorColorPairIndex,
): StylePatch =
  ## Background overlay for the syntax-highlighted code path. Syntax fg and
  ## modifiers are preserved; only the bg may be overridden.
  ## Priority: documentHighlight > gitConflict > cursorLine > cursorColumn.
  let highlightKind = e.state.isPositionInDocumentHighlight(lineCtx.bufferId, pos)
  if highlightKind.isSome:
    return bgOnly(getDocumentHighlightStyle(highlightKind.get).bg)
  if lineCtx.gitConflictApplies:
    return bgOnly(conflictStyleFor(lineCtx.lineConflict, lineCtx.useTwoColor).bg)
  # `searchResult` colorPair already paints the bg; suppress cursorLine/Column
  # so the search hit stays visible.
  if colorPair != EditorColorPairIndex.searchResult:
    if e.cursorLineApplies(lineCtx):
      return bgOnly(cursorLineHighlightStyle().bg)
    if e.cursorColumnApplies(displayCol, cursorDisplayCol):
      return bgOnly(cursorColumnHighlightStyle().bg)
  noPatch

proc baseStyleWithOverlay(
    e: Editor,
    buffer: TextBuffer,
    pos: BufferPosition,
    windowMode: EditorMode,
    displayCol: int,
    cursorDisplayCol: int,
    lineCtx: LineStyleContext,
): Style =
  ## Compute base style (syntax highlight + document highlight / cursor line/column overlay).
  if e.hasSyntaxHighlight(buffer, windowMode):
    let colorPair = buffer.highlight.getColorPair(pos.line, pos.column)
    var style = colorIndexToStyle(colorPair)
    style.modifiers =
      style.modifiers + buffer.highlight.getSegmentModifiers(pos.line, pos.column)
    let segBg = buffer.highlight.getSegmentBg(pos.line, pos.column)
    if segBg.isSome:
      style = style.merge(bgOnly(segBg.get))
    elif lineCtx.lineBg.isSome:
      # Fence tokens (```) and the language-name keyword carry no segment bg,
      # so without this the fence line reads as un-tinted islands inside the
      # block's stripe. Overlays below (cursorLine / gitConflict / …) still
      # win via `overlayPatchSyntax`.
      style = style.merge(bgOnly(lineCtx.lineBg.get))
    style.merge(
      e.overlayPatchSyntax(pos, lineCtx, displayCol, cursorDisplayCol, colorPair)
    )
  else:
    let highlightKind = e.state.isPositionInDocumentHighlight(lineCtx.bufferId, pos)
    if highlightKind.isSome:
      getDocumentHighlightStyle(highlightKind.get)
    elif lineCtx.gitConflictApplies:
      conflictStyleFor(lineCtx.lineConflict, lineCtx.useTwoColor)
    elif e.cursorLineApplies(lineCtx):
      cursorLineHighlightStyle()
    elif e.cursorColumnApplies(displayCol, cursorDisplayCol):
      cursorColumnHighlightStyle()
    else:
      normalStyle()

proc showsSelected(
    lineCtx: LineStyleContext, selection: VisualSelection, pos: BufferPosition
): bool =
  ## Whether `selection` shows over character `pos` of the line. A block
  ## covers screen cells, which `shownOn` worked out for the line.
  if selection.kind == vskBlock:
    selection.active and pos.column in lineCtx.blockShown.columns
  else:
    selection.isPositionInSelection(pos)

proc showsPastText(
    lineCtx: LineStyleContext, selection: VisualSelection, column: int
): bool =
  ## Whether `selection` shows over the cell after a row's text, as Vim draws
  ## it, the cell standing for `column` at or past the line's end: the line
  ## break when the row shows the line's end, else (scrolled sideways past it)
  ## where the row starts. A character or line selection shows when it covers
  ## `column`, but one starting at or past the line's end takes just the line
  ## break (Vim's `tocol = fromcol + 1` for a start on the NUL). A block shows
  ## only over the line break on its first or last line when it starts there.
  let
    line = lineCtx.lineIndex
    atLineEnd = column == lineCtx.lineEnd
  if selection.kind == vskBlock:
    atLineEnd and lineCtx.blockShown.lineEnd
  else:
    let first = selection.getSelectionRange().start
    selection.isPositionInSelection(BufferPosition(line: line, column: column)) and (
      atLineEnd or selection.kind == vskLine or first.line != line or
      first.column < lineCtx.lineEnd
    )

proc getSelectionStyle*(
    e: Editor,
    buffer: TextBuffer,
    selection: VisualSelection,
    pos: BufferPosition,
    cursorCol: int,
    windowMode: EditorMode,
    lineCtx: LineStyleContext,
    displayCol: int = -1,
    cursorDisplayCol: int = -1,
): Style =
  ## Get the appropriate style for a character based on selection state and syntax.
  ## Priority: visualSelection > snippetTabStop > matchingParen > findCharMatch >
  ## currentWord > searchHighlight > baseStyleWithOverlay.
  # Keep the original foreground (syntax highlight) for bg-only overlays.
  template syntaxBaseStyle(): Style =
    if e.hasSyntaxHighlight(buffer, windowMode):
      let colorPair = buffer.highlight.getColorPair(pos.line, pos.column)
      var s = colorIndexToStyle(colorPair)
      s.modifiers =
        s.modifiers + buffer.highlight.getSegmentModifiers(pos.line, pos.column)
      let segBg = buffer.highlight.getSegmentBg(pos.line, pos.column)
      if segBg.isSome:
        s = s.merge(bgOnly(segBg.get))
      elif lineCtx.lineBg.isSome:
        s = s.merge(bgOnly(lineCtx.lineBg.get))
      s
    else:
      normalStyle()

  if lineCtx.showsSelected(selection, pos):
    syntaxBaseStyle().merge(bgOnly(visualStyle().bg))
  elif e.matchesSnippetStop(lineCtx, pos):
    syntaxBaseStyle().merge(bgOnly(snippetTabStopStyle().bg))
  elif e.matchesMatchingParen(lineCtx, pos):
    parenPairStyle()
  elif e.matchesFindCharMatch(lineCtx, pos):
    findCharMatchStyle()
  elif e.matchesCurrentWord(lineCtx, pos):
    currentWordStyle()
  elif lineCtx.matchesSearchHighlight(pos):
    searchHighlightStyle()
  else:
    e.baseStyleWithOverlay(
      buffer, pos, windowMode, displayCol, cursorDisplayCol, lineCtx
    )

proc shouldShowIndentationGuide*(
    e: Editor, indentInfo: IndentInfo, displayX: int, charIdx: int
): bool =
  ## Check if an indentation guide should be shown at this position
  ## Uses cached indentInfo to avoid O(n²) performance
  ## displayX: the display column position (accounting for tabs)
  ## charIdx: the character index in the line
  if not e.showIndentationLines:
    return false

  # Don't show indentation guides in utility buffers (jumplist, log, etc.)
  if e.activeBuffer().isUtilityBuffer:
    return false

  # Only show guides at indent levels (multiples of tabStop)
  if displayX mod e.tabStop != 0:
    return false

  # Don't show on column 0
  if displayX == 0:
    return false

  # Check if this position is within leading whitespace
  if charIdx < 0:
    return false

  # Use cached indentation info: O(1) instead of O(n)
  # Show guide only if we're within leading whitespace and line has content
  return indentInfo.hasContent and charIdx <= indentInfo.leadingWhitespaceEnd

proc charOverridePatch(
    e: Editor, ctx: RenderContext, lineCtx: LineStyleContext, rune: Rune, col: int
): StylePatch =
  ## Per-character style overrides applied on top of the resolved base style.
  ## Priority (later wins): fullWidthSpace < trailingSpaces < colorCode.
  ## Returns `noPatch` when no override fires.
  var patch = noPatch
  if rune == FULLWIDTH_SPACE and e.config.highlight.fullWidthSpace and
      ctx.windowMode.isFileEditMode:
    patch = full(fullWidthSpaceStyle())
  if e.config.highlight.trailingSpaces and col >= lineCtx.trailingSpaceStart and
      ctx.windowMode.isFileEditMode and
      (rune == ' '.Rune or rune == TAB_CHAR or rune == FULLWIDTH_SPACE):
    patch = full(trailingSpacesStyle())
  for ccm in lineCtx.colorCodeMatches:
    if col >= ccm.startCol and col <= ccm.endCol:
      patch = full(ccm.style)
      break
  patch

proc lineFillPatch(
    e: Editor,
    lineCtx: LineStyleContext,
    displayX: int,
    cursorDisplayCol: int,
    inVisualSelection: bool,
): StylePatch =
  ## Style of a cell past the line's text: the fill and the end-of-line
  ## virtual text. Priority: visualSelection > gitConflict > cursorLine >
  ## cursorColumn > lineBg > none. Returns `noPatch` when the cell should keep
  ## `normalStyle()`.
  if inVisualSelection:
    return full(visualStyle())
  if lineCtx.gitConflictApplies:
    return full(conflictStyleFor(lineCtx.lineConflict, lineCtx.useTwoColor))
  if e.cursorLineApplies(lineCtx):
    return full(cursorLineHighlightStyle())
  if e.cursorColumnApplies(displayX, cursorDisplayCol):
    return full(cursorColumnHighlightStyle())
  if lineCtx.lineBg.isSome:
    return bgOnly(lineCtx.lineBg.get)
  noPatch

proc appendEndOfLineVirtualText(
    e: Editor,
    buffer: var Buffer,
    ctx: RenderContext,
    lineCtx: LineStyleContext,
    startDisplayX, screenX, screenY: int,
): int =
  ## Collect end-of-line virtual text for `lineCtx.lineIndex` from the providers
  ## in `ctx` and draw it starting at `startDisplayX` (the display column just
  ## past the line's last real rune). Clipped at `ctx.windowRightEdge`. Returns
  ## the display column just past the drawn text (== `startDisplayX` when empty).
  ##
  ## Each cell keeps the chunk's foreground color but takes the line-fill
  ## background overlay (cursor line / cursor column / git conflict) so the
  ## virtual text shares the same background as the trailing fill — otherwise the
  ## current-line highlight stops at the real text and skips the hint.
  result = startDisplayX
  if ctx.virtualTextProviders.len == 0:
    return
  let vt = collectVirtualText(ctx.virtualTextProviders, lineCtx.lineIndex)
  if vt.endOfLine.len == 0:
    return
  for chunk in vt.endOfLine:
    let baseStyle = colorIndexToStyle(chunk.color)
    for (rune, _) in chunk.text.chars:
      let cellRune = sanitizeCellRune(rune)
      let w = runeWidth(cellRune)
      if w == 0:
        # Zero-width rune: fold into the preceding base cell, no advance. Skip
        # a leading mark whose base would be the real text, not virtual text.
        if result > startDisplayX:
          foldZeroWidthRune(buffer, screenX + result, screenY, cellRune)
        continue
      if screenX + result + w > ctx.windowRightEdge:
        return result
      let bgPatch = e.lineFillPatch(
        lineCtx, result, ctx.cursorDisplayCol, inVisualSelection = false
      )
      let style =
        if bgPatch.bg.isSome:
          baseStyle.merge(bgOnly(bgPatch.bg.get))
        else:
          baseStyle
      buffer.setCell(screenX + result, screenY, cellRune, w, style)
      result += w

proc renderLineSegmentWithSelection*(
    e: Editor,
    textBuffer: TextBuffer,
    buffer: var Buffer,
    displayLine: string,
    screenX, screenY: int,
    lineIndex: int,
    startColumn: int,
    ctx: RenderContext,
    precomputed: Option[LinePrecomputed] = none(LinePrecomputed),
    startCell, leftCell = 0,
) =
  ## Render a screen row of a line: `displayLine`, the line's text from
  ## column `startColumn`, and the cells after it to the window's right edge.
  ## The row of an empty line, or one scrolled sideways past the text, has an
  ## empty `displayLine`. When `displayLine` reaches the line's end, a
  ## selection over the line break shows in the next cell, and end-of-line
  ## virtual text (inlay hints, etc.) is drawn there before the trailing fill.
  ## `startCell` is the cell `displayLine` starts at, counted from where tabs
  ## are measured, and the row shows the cells from `leftCell` on. As Vim
  ## draws them, a character the left edge cuts shows its remaining cells, a
  ## tab's as blanks and a wide character's as `<`, and a wide character the
  ## right edge cuts shows as `>`. Cells past the right edge are not drawn.
  ## ctx: RenderContext containing cursor position and selection information
  ## precomputed: caller-supplied indentInfo/lineCtx, built from the
  ##   line the caller holds and shared across wrap segments of the same
  ##   logical line. When set, the caller is responsible for having already
  ##   called `updateHighlight`.

  let (indentInfo, lineCtx) =
    if precomputed.isSome:
      (precomputed.get.indentInfo, precomputed.get.lineCtx)
    else:
      # The highlight advancement budget is owned by `updateForFrame`; this
      # per-line path must not advance it further.
      let p = e.linePrecomputed(
        textBuffer,
        lineIndex,
        textBuffer.getLine(lineIndex),
        ctx,
        drawsText = displayLine.len > 0,
      )
      (p.indentInfo, p.lineCtx)

  # Always render character by character to apply syntax highlighting.
  # `displayX` is the cell's column on the row, negative over the cells of a
  # character the left edge cuts; tabs are measured from `leftCell + displayX`.
  var
    displayX = startCell - leftCell
    afterFiller = false

  # Templates capture displayX / screenX / screenY / e / ctx / lineCtx /
  # indentInfo / buffer from the enclosing scope. They are templates rather
  # than procs to avoid closure-capture overhead and to let displayX mutate
  # in place. Modifier union (vs. full replacement) is intentional: syntax
  # modifiers like Bold/Italic are preserved through char overrides.

  template styleAt(selection: VisualSelection, col, cell: int): Style =
    # The style of character `col` drawn on row column `cell`, or -1 to leave
    # the cursor column out.
    e.getSelectionStyle(
      textBuffer,
      selection,
      BufferPosition(line: lineIndex, column: col),
      ctx.cursorCol,
      ctx.windowMode,
      displayCol = cell,
      cursorDisplayCol = ctx.cursorDisplayCol,
      lineCtx = lineCtx,
    )

  template renderTabCell(col: int, style: Style) =
    # Tab expands to N spaces up to the next tab stop. Each expanded cell
    # honors indentation-guide drawing; the spaces themselves use a style
    # that may carry the trailingSpaces override. A block's edge can cut the
    # tab, and Vim draws the cells outside the block unselected. A tab drawn
    # at another width than it takes on the line shows whole. The cursor
    # column shows over the one cell under it, as in Vim, so `style` and
    # `outsideStyle` leave it out.
    let
      spacesToNextTab = tabAdvance(leftCell + displayX, e.tabStop)
      patch = e.charOverridePatch(ctx, lineCtx, TAB_CHAR, col)
      shown = lineCtx.blockShown
      outsideBefore =
        if col == shown.columns.a and spacesToNextTab == shown.firstWidth:
          shown.leadCells
        else:
          0
      outsideAfter =
        if col == shown.columns.b and spacesToNextTab == shown.lastWidth:
          shown.trailCells
        else:
          0
      outsideStyle =
        if outsideBefore + outsideAfter > 0:
          styleAt(VisualSelection(), col, -1)
        else:
          style
    for i in 0 ..< spacesToNextTab:
      let
        outside = i < outsideBefore or i >= spacesToNextTab - outsideAfter
        cellStyle =
          if e.cursorColumnApplies(displayX, ctx.cursorDisplayCol):
            let selection =
              if outside:
                VisualSelection()
              else:
                ctx.selection
            styleAt(selection, col, displayX)
          elif outside:
            outsideStyle
          else:
            style
      if displayX >= 0 and screenX + displayX < ctx.windowRightEdge:
        # No guides in the diff viewer: +/- markers and synthetic
        # side-by-side rows make the leading-whitespace analysis misfire.
        if ctx.windowMode != EditorMode.DiffViewer and
            e.shouldShowIndentationGuide(indentInfo, leftCell + displayX, col):
          let guideStyle = indentationLineStyle().merge(bgOnly(cellStyle.bg))
          buffer.setCell(screenX + displayX, screenY, "│", 1, guideStyle)
        else:
          buffer.setCell(screenX + displayX, screenY, " ", 1, cellStyle.merge(patch))
      displayX += 1

  template renderInvalidByteCell(rune: Rune, col: int, style: Style) =
    # Undecodable bytes are drawn as `<e3>` (the way vim shows them) so the
    # user can see which byte is there, not a replacement character
    # indistinguishable from one the file really holds.
    # The byte's own foreground over the line's background, the way the
    # indentation guide is drawn, so selection and cursor-line stay visible.
    let byteStyle = invalidByteStyle().merge(bgOnly(style.bg))
    for ch in invalidByteText(rune):
      if displayX >= 0 and screenX + displayX < ctx.windowRightEdge:
        buffer.setCell(screenX + displayX, screenY, $ch, 1, byteStyle)
      displayX += 1

  template renderNormalCell(rune: Rune, col: int, style: Style) =
    let cellRune = sanitizeCellRune(rune)
    let width = charWidth(cellRune)
    if width == 0:
      # Zero-width rune (combining mark / ZWJ / variation selector): fold it
      # into the preceding base cell rather than writing a standalone cell the
      # next glyph would overwrite. displayX does not advance. Skip when this
      # cell starts the segment — its base, if any, is on the previous row —
      # or follows a filler standing for a cut base.
      if displayX > 0 and not afterFiller:
        foldZeroWidthRune(buffer, screenX + displayX, screenY, cellRune)
    elif displayX < 0 or screenX + displayX + width > ctx.windowRightEdge:
      # A wide character cut by an edge, drawn dim like the indentation guide.
      # As in Vim, `<` keeps the cell's background and `>` takes none.
      let (filler, fillerStyle) =
        if displayX < 0:
          ("<", indentationLineStyle().merge(bgOnly(style.bg)))
        else:
          (">", indentationLineStyle())
      for x in max(0, displayX) ..< displayX + width:
        if screenX + x < ctx.windowRightEdge:
          buffer.setCell(screenX + x, screenY, filler, 1, fillerStyle)
      displayX += width
      afterFiller = true
    elif cellRune == ' '.Rune and ctx.windowMode != EditorMode.DiffViewer and
        e.shouldShowIndentationGuide(indentInfo, leftCell + displayX, col):
      if screenX + displayX < ctx.windowRightEdge:
        let guideStyle = indentationLineStyle().merge(bgOnly(style.bg))
        buffer.setCell(screenX + displayX, screenY, "│", 1, guideStyle)
      displayX += 1
      afterFiller = false
    else:
      let renderStyle = style.merge(e.charOverridePatch(ctx, lineCtx, cellRune, col))
      if screenX + displayX < ctx.windowRightEdge:
        buffer.setCell(screenX + displayX, screenY, cellRune, width, renderStyle)
      displayX += width
      afterFiller = false

  template renderChar(rune: Rune, col: int, style: Style) =
    if rune == TAB_CHAR:
      renderTabCell(col, style)
      afterFiller = false
    elif rune.isInvalidByteRune:
      renderInvalidByteCell(rune, col, style)
      afterFiller = false
    else:
      renderNormalCell(rune, col, style)

  var col = startColumn
  for (rune, _) in displayLine.chars:
    # A character the left edge cuts takes the style of its first drawn cell,
    # but a tab's cells take the cursor column one by one.
    let
      cell =
        if rune == TAB_CHAR:
          -1
        else:
          max(0, displayX)
      style = styleAt(ctx.selection, col, cell)
    renderChar(rune, col, style)
    col += 1

  # Whether the selection shows over the cell after the text, which virtual
  # text drawn there hides, as in Vim. Past `lineEnd`, the row was scrolled
  # sideways past the line's end and shows nothing of it.
  let
    reachesLineEnd = col == lineCtx.lineEnd
    selectedEndX =
      if col >= lineCtx.lineEnd and lineCtx.showsPastText(ctx.selection, col):
        displayX
      else:
        -1

  # Draw end-of-line virtual text (inlay hints, etc.) after the real text and
  # before the trailing fill, so the running displayX (and thus cursor-column /
  # cursor-line fill alignment) stays correct.
  if reachesLineEnd:
    displayX =
      e.appendEndOfLineVirtualText(buffer, ctx, lineCtx, displayX, screenX, screenY)

  # Fill the rest of the line to the window right edge.
  # Always fill to clear stale content (e.g. old cursor line highlight).
  while screenX + displayX < ctx.windowRightEdge:
    let fillStyle = normalStyle().merge(
        e.lineFillPatch(
          lineCtx,
          displayX,
          ctx.cursorDisplayCol,
          inVisualSelection = displayX == selectedEndX,
        )
      )
    buffer.setCell(screenX + displayX, screenY, " ", 1, fillStyle)
    displayX += 1

proc fmtLineNum(
    state: EditorState, lineIndex: int, cursorLine: int, width: int
): string =
  if state.relativeLineNumbers:
    formatRelativeLineNumber(lineIndex, cursorLine, width)
  else:
    formatLineNumber(lineIndex, width)

proc renderWindowLineWrapped*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    lineNumOffset: int,
    ctx: RenderContext,
    screenY: var int,
    lineIndex: var int,
    visibleHeight: int,
    tabLineOffset: int,
    skipSegments: int = 0,
) =
  ## Render a single line with wrapping enabled.
  ## `skipSegments` drops the given number of leading wrap segments without
  ## advancing screenY (they are scrolled off the top, vim-style). Only the
  ## viewport's first logical line ever passes a non-zero value.
  let
    maxScreenY = visibleHeight + tabLineOffset
    line = window.buffer.getLine(lineIndex)
    actualScreenY = window.viewport.y + screenY
    sidebarWidth = e.calculateSidebarWidth(window)
    maxWidth = e.wrapWidth(window, lineNumOffset)
    lineCharLen = line.charLen
    isCurrentLine = (lineIndex == window.cursor.line)
    # Apply currentNumber setting: highlight current line number only if enabled
    lineStyle =
      if isCurrentLine:
        currentLineStyle()
      else:
        lineNumStyle()
    lineNumScreenX = window.viewport.x + sidebarWidth

  if lineCharLen == 0:
    # Don't render if already past visible area
    if screenY >= maxScreenY:
      return
    # Empty line: the line number (if enabled) and the cells after its end
    if lineNumOffset > 0:
      let lineNumStr = e.state.fmtLineNum(lineIndex, window.cursor.line, lineNumOffset)
      if lineNumScreenX + lineNumStr.len <= buffer.area.width:
        buffer.setString(lineNumScreenX, actualScreenY, lineNumStr, lineStyle)
    let textScreenX = window.viewport.x + sidebarWidth + lineNumOffset
    if textScreenX < buffer.area.width:
      e.renderLineSegmentWithSelection(
        window.buffer,
        buffer,
        "",
        textScreenX,
        actualScreenY,
        lineIndex,
        0,
        ctx,
        precomputed = some(
          e.linePrecomputed(window.buffer, lineIndex, line, ctx, drawsText = false)
        ),
      )
    inc screenY
    inc lineIndex
    return

  var
    startCharCol = 0
    startByteCol = 0
    wrapLineCount = 0

  # Don't render if already past visible area
  if screenY >= maxScreenY:
    return

  let tabStop = e.tabStop

  # Build per-logical-line state once so each wrap segment can reuse it.
  # The highlight was already advanced by `updateForFrame` before the draw.
  let precomputed = some(e.linePrecomputed(window.buffer, lineIndex, line, ctx))

  # Skip leading wrap segments scrolled off the top (partial first line). Keep
  # wrapLineCount advancing so the resumed first visible row is treated as a
  # continuation row (blank line number, vim-style) rather than the first wrap.
  var segmentsSkipped = 0
  while segmentsSkipped < skipSegments and startCharCol < lineCharLen:
    let (charCount, _, endBytePos) =
      displayWidthSubstrFromByte(line, startByteCol, maxWidth, tabStop)
    let endCharCol = min(startCharCol + max(1, charCount), lineCharLen)
    startByteCol = if endCharCol >= lineCharLen: line.len else: endBytePos
    startCharCol = endCharCol
    inc wrapLineCount
    inc segmentsSkipped

  while startCharCol < lineCharLen and screenY < maxScreenY:
    # Use byte-position-aware function to avoid O(n) skip per segment
    let
      (charCount, _, endBytePos) =
        displayWidthSubstrFromByte(line, startByteCol, maxWidth, tabStop)
      endCharCol = min(startCharCol + max(1, charCount), lineCharLen)
      actualEndByte = if endCharCol >= lineCharLen: line.len else: endBytePos
      displayLine = line[startByteCol ..< actualEndByte]
      textScreenX = window.viewport.x + sidebarWidth + lineNumOffset
      currentActualScreenY = window.viewport.y + screenY

    # Render line number for first wrap, empty space for others (if enabled)
    if lineNumOffset > 0:
      if wrapLineCount == 0:
        let lineNumStr =
          e.state.fmtLineNum(lineIndex, window.cursor.line, lineNumOffset)
        if lineNumScreenX + lineNumStr.len <= buffer.area.width:
          buffer.setString(lineNumScreenX, currentActualScreenY, lineNumStr, lineStyle)
      else:
        if lineNumScreenX + lineNumOffset <= buffer.area.width:
          let emptyLineNumStr = spaces(lineNumOffset)
          buffer.setString(
            lineNumScreenX, currentActualScreenY, emptyLineNumStr, lineNumStyle()
          )

    if displayLine.len > 0 and textScreenX < buffer.area.width:
      let displayCharCount = endCharCol - startCharCol
      if displayCharCount > 0:
        # Render with selection highlighting if in visual mode.
        # Append end-of-line virtual text only on the final wrap segment.
        e.renderLineSegmentWithSelection(
          window.buffer,
          buffer,
          displayLine,
          textScreenX,
          currentActualScreenY,
          lineIndex,
          startCharCol,
          ctx,
          precomputed = precomputed,
        )

    inc screenY
    inc wrapLineCount
    startCharCol = endCharCol
    startByteCol = actualEndByte

    if screenY >= maxScreenY:
      break

  inc lineIndex

proc renderWindowLineNoWrap*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    lineNumOffset: int,
    ctx: RenderContext,
    screenY: int,
    lineIndex: int,
) =
  ## Render a single line without wrapping (horizontal scrolling)
  let
    line = window.buffer.getLine(lineIndex)
    actualScreenY = window.viewport.y + screenY
    sidebarWidth = e.calculateSidebarWidth(window)
    isCurrentLine = (lineIndex == window.cursor.line)
    # Apply currentNumber setting: highlight current line number only if enabled
    lineStyle =
      if isCurrentLine:
        currentLineStyle()
      else:
        lineNumStyle()
    lineNumScreenX = window.viewport.x + sidebarWidth

  # Render line number (if enabled)
  if lineNumOffset > 0:
    let lineNumStr = e.state.fmtLineNum(lineIndex, window.cursor.line, lineNumOffset)
    if lineNumScreenX + lineNumStr.len <= buffer.area.width:
      buffer.setString(lineNumScreenX, actualScreenY, lineNumStr, lineStyle)

  let
    textScreenX = window.viewport.x + sidebarWidth + lineNumOffset
    cellBudget = e.textAreaWidth(window, lineNumOffset)
  if textScreenX >= buffer.area.width or cellBudget <= 0:
    return

  # The row shows the line's cells from `leftCell` on, with tabs measured from
  # the line start.
  let
    leftCell = window.viewport.leftCell
    shown = line.shownFrom(leftCell, cellBudget, e.tabStop)
  e.renderLineSegmentWithSelection(
    window.buffer,
    buffer,
    line[shown.startByte ..< shown.endByte],
    textScreenX,
    actualScreenY,
    lineIndex,
    shown.column,
    ctx,
    precomputed = some(
      e.linePrecomputed(
        window.buffer, lineIndex, line, ctx, drawsText = shown.startByte < line.len
      )
    ),
    startCell = shown.cell,
    leftCell = leftCell,
  )

proc renderWindowSidebar*(
    buffer: var Buffer,
    window: EditorWindow,
    sidebar: Sidebar,
    screenY: int,
    sidebarIndex: int,
    sidebarOffset: int,
) =
  ## Render a single line of the sidebar
  ## screenY: screen row offset from window.viewport.y
  ## sidebarIndex: index into sidebar.buffer (0-based, independent of tabLineOffset)
  let actualScreenY = window.viewport.y + screenY

  if sidebarIndex >= 0 and sidebarIndex < sidebar.buffer.len:
    for x in 0 ..< sidebar.width:
      let
        item = sidebar.buffer[sidebarIndex][x]
        screenX = window.viewport.x + sidebarOffset + x
      if screenX < buffer.area.width and actualScreenY < buffer.area.height:
        buffer.setString(screenX, actualScreenY, item.text, item.style)

proc textRightEdge(e: Editor, window: EditorWindow): int =
  ## Absolute screen X of the right edge of the window's text, left of the
  ## scrollbar.
  window.viewport.x + window.viewport.width - e.calculateScrollbarWidth(window)

proc renderFoldLine*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    lineNumOffset: int,
    screenY: int,
    fold: Fold,
) =
  ## Render a collapsed fold marker line (vim-style)
  let
    actualScreenY = window.viewport.y + screenY
    sidebarWidth = e.calculateSidebarWidth(window)
    lineNumScreenX = window.viewport.x + sidebarWidth
    textScreenX = window.viewport.x + sidebarWidth + lineNumOffset
    foldText = window.buffer.formatFoldText(fold)
    windowRightEdge = e.textRightEdge(window)

  # Render line number (if enabled)
  if lineNumOffset > 0:
    let lineNumStr =
      e.state.fmtLineNum(fold.startLine, window.cursor.line, lineNumOffset)
    if lineNumScreenX + lineNumStr.len <= buffer.area.width:
      buffer.setString(lineNumScreenX, actualScreenY, lineNumStr, lineNumStyle())

  # Render fold text
  if textScreenX < buffer.area.width:
    let maxWidth = windowRightEdge - textScreenX
    # Truncate by display width (not bytes or rune count) so multibyte/wide
    # characters are neither split nor allowed to overflow the window edge.
    let displayText =
      if maxWidth <= 0:
        ""
      elif foldText.displayWidth > maxWidth:
        let (fitChars, _) = foldText.displayWidthSubstr(0, maxWidth)
        foldText.charSubStr(0, fitChars)
      else:
        foldText
    buffer.setString(textScreenX, actualScreenY, displayText, foldStyle())

proc rowLayoutOf(e: Editor, window: EditorWindow, lineNumOffset: int): RowLayout =
  ## Row walk context for a window, keyed on the width the renderer wraps at.
  initRowLayout(
    window.buffer,
    window.wrapCountCache,
    e.lineWrap,
    e.wrapWidth(window, lineNumOffset),
    e.tabStop,
  )

proc renderScrollbar*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    visibleHeight: int,
    tabLineOffset: int,
    lineNumOffset: int,
) =
  ## Render a scrollbar on the right edge of the window.
  ## Thumb size/position reflect actual display rows: collapsed folds count as
  ## one marker row and wrapped logical lines count as their wrap segments,
  ## so the thumb tracks what the viewport actually shows.
  let
    scrollbarWidth = e.calculateScrollbarWidth(window)
    scrollbarStartX = window.viewport.x + window.viewport.width - scrollbarWidth

  if visibleHeight <= 0 or scrollbarWidth <= 0:
    return

  let
    rl = e.rowLayoutOf(window, lineNumOffset)
    totalRows = rl.totalRows(window.buffer.len)

  if totalRows <= visibleHeight:
    return

  let
    rowsAbove =
      rl.totalRows(window.viewport.topLine) +
      (if e.lineWrap: window.viewport.topWrapOffset else: 0)
    thumbSize = max(1, (visibleHeight * visibleHeight) div totalRows)
    maxRowsAbove = totalRows - visibleHeight
    thumbPos =
      if maxRowsAbove > 0:
        clamp(
          (rowsAbove * (visibleHeight - thumbSize)) div maxRowsAbove,
          0,
          visibleHeight - thumbSize,
        )
      else:
        0

  for y in 0 ..< visibleHeight:
    let
      screenY = window.viewport.y + tabLineOffset + y
      isThumb = y >= thumbPos and y < thumbPos + thumbSize
      style =
        if isThumb:
          scrollbarThumbStyle()
        else:
          scrollbarTrackStyle()

    for col in 0 ..< scrollbarWidth:
      let screenX = scrollbarStartX + col
      if screenX < buffer.area.width and screenY < buffer.area.height:
        buffer.setCell(screenX, screenY, " ", 1, style)

proc renderWindow*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    lineNumOffset: int,
    isBottomWindow: bool,
    isActiveWindow: bool,
    tabLineOffset: int = 0,
) =
  ## Render a single window with sidebar, line numbers and text content
  ## tabLineOffset: Y offset for rendering (TabLineHeight when tab line is shown)
  let
    lineCount = window.buffer.len
    reservedLines = e.calculateReservedLines(isBottomWindow)

    # Clamp to 0: on a tiny terminal the reserves can exceed the viewport
    visibleHeight = max(0, window.viewport.height - reservedLines - tabLineOffset)

  # Generate sidebar dynamically from buffer markers if enabled
  # Note: sidebar needs visibleHeight rows (screenY goes from tabLineOffset to visibleHeight + tabLineOffset)
  let maybeSidebar =
    if e.showSidebar:
      # When the git-diff gutter is active for a git-tracked file, it is the
      # authoritative (content-based) change indicator, so suppress the session
      # "modified lines" fallback. Both draw the same `~`/`+` glyphs, and the
      # session markers are history-based — they linger after the buffer is
      # edited back to match HEAD (git diff goes empty but the line stays
      # flagged), making it look like a stuck git marker. For non-git / untracked
      # files the git gutter shows nothing, so the session fallback is kept.
      let showSessionMarkers =
        e.showModifiedLines and
        not (e.showGitDiff and e.state.git.isBufferGitTracked(window.buffer))
      some(
        generateSidebarFromBuffer(
          window.buffer,
          window.viewport.topLine,
          visibleHeight,
          modifiedLines = window.buffer.modifiedLines,
          showModifiedLines = showSessionMarkers,
          bookmarks = window.buffer.bookmarks,
        )
      )
    else:
      none(Sidebar)

  # Fold skipping and wrap-segment counting come from the shared row walk, so
  # the painted rows, the screen cursor and the mouse hit-test agree by
  # construction.
  let rl = e.rowLayoutOf(window, lineNumOffset)

  # The cursor's column on its row, where the screen cursor is placed, or -1,
  # which no cell's column matches, when it is scrolled off the left.
  let cursorDisplayCol =
    if window.cursor.line < lineCount:
      let cellX = rl.cursorCell(
        window.cursor.line, window.cursor.column, window.viewport.leftCell,
        window.cursorOnTabEnd,
      ).cellX
      if cellX < 0: -1 else: cellX
    else:
      window.cursor.column

  # Create render context for this window
  let ctx = RenderContext(
    cursorLine: window.cursor.line,
    cursorCol: window.cursor.column,
    cursorDisplayCol: cursorDisplayCol,
    selection: window.visualSelection,
    blockArea:
      if window.mode == EditorMode.VisualBlock:
        window.buffer.blockArea(
          window.visualSelection, e.tabStop, measureWidest = false
        )
      else:
        BlockArea(),
    windowMode: window.mode,
    windowRightEdge: e.textRightEdge(window),
    isActiveWindow: isActiveWindow,
    # Virtual text caches (inlay hints, ...) track the active buffer, so only
    # the active window draws them.
    virtualTextProviders:
      if isActiveWindow:
        e.buildVirtualTextProviders()
      else:
        @[],
  )

  # The frame budget for highlight advancement is owned solely by
  # `updateForFrame`; the draw pass must not advance re-parses, or the
  # per-window charges (N windows x 1000 lines) would bypass the budget.

  for row in rl.visibleLines(
    window.viewport.topLine, window.viewport.topWrapOffset, visibleHeight
  ):
    # sidebarIndex is 0-based index into sidebar buffer (based on logical line, not screen row)
    let
      sidebarIndex = row.line - window.viewport.topLine
      screenY = tabLineOffset + row.startRow

    if maybeSidebar.isSome:
      renderWindowSidebar(buffer, window, maybeSidebar.get, screenY, sidebarIndex, 0)

    if row.fold.isSome:
      e.renderFoldLine(buffer, window, lineNumOffset, screenY, row.fold.get)
    elif e.lineWrap:
      # `renderWindowLineWrapped` advances its own screenY / lineIndex across the
      # segments it paints; the walk owns the next row, so the copies are dropped.
      var
        segScreenY = screenY
        segLine = row.line
      e.renderWindowLineWrapped(
        buffer,
        window,
        lineNumOffset,
        ctx,
        segScreenY,
        segLine,
        visibleHeight,
        tabLineOffset,
        skipSegments = row.skipSegments,
      )
    else:
      e.renderWindowLineNoWrap(buffer, window, lineNumOffset, ctx, screenY, row.line)

  # Render scrollbar on the right edge if enabled (file editing modes only)
  if e.calculateScrollbarWidth(window) > 0:
    e.renderScrollbar(buffer, window, visibleHeight, tabLineOffset, lineNumOffset)

proc renderWindowSeparator*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    nextWindow: EditorWindow,
    isBottomWindow: bool,
) =
  ## Draw separator between adjacent windows (vertical or horizontal)
  # Check if windows are side by side (vertical split) or top/bottom (horizontal split)
  if window.viewport.y == nextWindow.viewport.y:
    # Vertical split - draw vertical separator at window boundary
    let sepX = window.viewport.x + window.viewport.width
    if sepX < buffer.area.width:
      # Calculate separator height using helper
      let
        sepHeight = e.calculateReservedLines(isBottomWindow)
        actualSepHeight = window.viewport.height - sepHeight

      # Draw separator for the content height of this window
      for y in window.viewport.y ..< (window.viewport.y + actualSepHeight):
        if y < buffer.area.height:
          buffer.setString(sepX, y, "│", separatorStyle())
  elif not e.multiStatusLine:
    # Horizontal split - draw horizontal separator at window boundary
    # ONLY when using a single status line
    let sepY = window.viewport.y + window.viewport.height
    if sepY < buffer.area.height:
      # Draw separator for the width of this window
      for x in window.viewport.x ..< (window.viewport.x + window.viewport.width):
        if x < buffer.area.width:
          buffer.setString(x, sepY, "─", separatorStyle())
