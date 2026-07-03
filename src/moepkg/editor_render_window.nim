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

import pkg/celina

import
  types/editor_types,
  editor_window_layout,
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
  status_line,
  editor_codelens
import command_handlers/visual_handler

type
  LineStyleContext* = object
    ## Per-line state used while rendering one buffer line. Values are
    ## computed once at the start of the line and then read by the per-character
    ## style pipeline, replacing what used to be 7+ individually-threaded
    ## parameters across getSelectionStyle / baseStyleWithOverlay / overlayPatchSyntax.
    ##
    ## Two construction paths exist:
    ## - `newLineStyleContext`: full context built once per rendered line. Required
    ##   for `getSelectionStyle` / `renderLineSegmentWithSelection`.
    ## - Manual partial construction: `fillLineBackground` only calls
    ##   `lineFillPatch`, which reads `isCursorLine`, `lineConflict`, and
    ##   `useTwoColor`; the remaining fields can be left at their defaults.
    lineIndex*: int
    isActiveWindow*: bool
    isCursorLine*: bool
    lineConflict*: ConflictMarkerKind
    useTwoColor*: bool
    searchRanges*: seq[ColumnRange]
    wordRanges*: seq[ColumnRange]
    colorCodeMatches*: seq[ColorCodeMatch]
    trailingSpaceStart*: int

  LinePrecomputed* = object
    ## Per-logical-line values reused across wrap segments. The wrap path builds
    ## this once and hands it to every segment call so the O(line) scans in
    ## `newLineStyleContext` / `analyzeIndentation` do not fire per segment.
    fullLine*: string
    indentInfo*: IndentInfo
    lineCtx*: LineStyleContext

template hasSyntaxHighlight(
    e: Editor, buffer: TextBuffer, windowMode: EditorMode
): bool =
  e.state.display.showSyntax and not buffer.highlight.isNil and
    (windowMode.isFileEditMode or buffer.language != langNone or buffer.isUtilityBuffer)

proc resolveLineConflict(
    e: Editor, textBuffer: TextBuffer, lineIndex: int
): ConflictMarkerKind =
  ## Single source of truth for the per-line git-conflict kind. Both
  ## `newLineStyleContext` and `fillLineBackground` go through this so the
  ## "is gitConflict enabled?" guard cannot drift between code paths.
  if textBuffer != nil and e.config.highlight.gitConflict:
    textBuffer.lineConflictKind(lineIndex)
  else:
    cmkNone

proc effectiveSearchPattern(state: EditorState): string =
  ## Resolve the active hlsearch pattern based on overlay state.
  ## - Search overlay: live text being typed
  ## - Command overlay: substitute pattern if present, else last search
  ## - Otherwise: last search
  if state.isSearchOverlay:
    state.input.search.text
  elif state.isCommandOverlay:
    let subPattern = extractSubstitutePattern(state.input.commandText)
    if subPattern.len > 0: subPattern else: state.input.search.lastText
  else:
    state.input.search.lastText

proc newLineStyleContext*(
    e: Editor,
    textBuffer: TextBuffer,
    lineIndex: int,
    fullLine: string,
    ctx: RenderContext,
): LineStyleContext =
  ## Compute all per-line state needed by the style pipeline in one place.
  # Trailing-space highlighting only fires on non-cursor lines in file-edit mode
  # when enabled (see styleOverrideAt). Skip the whole-line scan when it cannot
  # fire. Don't clip to the cap: trailing whitespace lives at the line *end*,
  # past the cap, so the input must stay the full line.
  let trailingSpaceStart =
    if e.config.highlight.trailingSpaces and ctx.windowMode.isFileEditMode and
        lineIndex != ctx.cursorLine:
      findTrailingSpaceStart(fullLine)
    else:
      high(int) # disabled: `col >= trailingSpaceStart` never matches

  # Bound the color-code scan to the cap: scanLineForColorCodes allocates an
  # O(line) byte->rune map, and past the cap the line is plain text anyway.
  # (Search/current-word ranges stay uncapped: they're functional, not
  # decorative — a match past the cap must still be shown.)
  let colorCodeMatches =
    if e.config.highlight.colorCodeHighlight and ctx.windowMode.isFileEditMode:
      let cap = if textBuffer != nil: textBuffer.maxHighlightLineLength else: 0
      if cap > 0 and fullLine.len > cap:
        scanLineForColorCodes(fullLine.runeSubStr(0, cap))
      else:
        scanLineForColorCodes(fullLine)
    else:
      @[]

  let searchRanges =
    if textBuffer != nil and e.state.input.search.hlsearch and
        not e.state.input.search.hlsearchTempDisabled:
      let searchPattern = e.state.effectiveSearchPattern()
      if searchPattern.len > 0:
        let shouldIgnoreCase = shouldIgnoreCase(
          searchPattern, e.state.input.search.ignorecase, e.state.input.search.smartcase
        )
        textBuffer.findSearchMatchRanges(
          lineIndex, searchPattern, shouldIgnoreCase, e.state.input.search.wholeWord
        )
      else:
        @[]
    else:
      @[]

  let wordRanges =
    if textBuffer != nil and not e.state.isSearchOverlay and e.state.currentWord.len > 0:
      let excludeCol = if lineIndex == ctx.cursorLine: ctx.cursorCol else: -1
      textBuffer.findWordMatchRanges(lineIndex, e.state.currentWord, excludeCol)
    else:
      @[]

  LineStyleContext(
    lineIndex: lineIndex,
    isActiveWindow: ctx.isActiveWindow,
    isCursorLine: lineIndex == ctx.cursorLine,
    lineConflict: e.resolveLineConflict(textBuffer, lineIndex),
    useTwoColor: e.config.highlight.gitConflictTwoColor,
    searchRanges: searchRanges,
    wordRanges: wordRanges,
    colorCodeMatches: colorCodeMatches,
    trailingSpaceStart: trailingSpaceStart,
  )

# Layer predicates
# Each predicate decides whether one style layer fires at a given cell.
# They are pure functions over Editor + (lineCtx and/or pos) — no side
# effects, no style construction. The 4 priority-chain procs below call
# them in order so the priority list reads as a sequence of named checks.

template matchesVisualSelection(
    e: Editor, hasSelection: bool, pos: BufferPosition
): bool =
  hasSelection and e.state.visualSelection.isPositionInSelection(pos)

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
  e.state.display.showCursorLine and lineCtx.isCursorLine

template cursorColumnApplies(e: Editor, displayCol: int, cursorDisplayCol: int): bool =
  e.state.display.showCursorColumn and displayCol >= 0 and displayCol == cursorDisplayCol

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
  let highlightKind = e.state.isPositionInDocumentHighlight(pos)
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
    style.merge(
      e.overlayPatchSyntax(pos, lineCtx, displayCol, cursorDisplayCol, colorPair)
    )
  else:
    let highlightKind = e.state.isPositionInDocumentHighlight(pos)
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

proc getSelectionStyle*(
    e: Editor,
    buffer: TextBuffer,
    hasSelection: bool,
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
      s
    else:
      normalStyle()

  if e.matchesVisualSelection(hasSelection, pos):
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

proc getVisualSelection*(
    e: Editor, windowMode: EditorMode, windowActive: bool = true
): tuple[hasSelection: bool, selStart, selEnd: BufferPosition] =
  ## Get visual selection range if active
  ## windowMode: The mode of the window being rendered
  ## windowActive: only show selection in active window (default true for compatibility)
  let hasSelection =
    isVisualAllMode(windowMode) and e.state.visualSelection.active and windowActive

  if hasSelection:
    let (start, endPos) = e.state.visualSelection.getSelectionRange()
    result = (hasSelection: true, selStart: start, selEnd: endPos)
  else:
    result = (
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
    )

proc shouldShowIndentationGuide*(
    e: Editor, indentInfo: IndentInfo, displayX: int, charIdx: int
): bool =
  ## Check if an indentation guide should be shown at this position
  ## Uses cached indentInfo to avoid O(n²) performance
  ## displayX: the display column position (accounting for tabs)
  ## charIdx: the character index in the line
  if not e.state.display.showIndentationLines:
    return false

  # Don't show indentation guides in utility buffers (jumplist, log, etc.)
  if e.activeBuffer().isUtilityBuffer:
    return false

  # Only show guides at indent levels (multiples of tabStop)
  if displayX mod e.state.display.tabStop != 0:
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
      ctx.windowMode.isFileEditMode and not lineCtx.isCursorLine and
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
  ## Shared priority chain used by both line-fill paths.
  ## Priority: visualSelection > gitConflict > cursorLine > cursorColumn > none.
  ## Returns `noPatch` when the cell should keep `normalStyle()`.
  if inVisualSelection:
    return full(visualStyle())
  if lineCtx.gitConflictApplies:
    return full(conflictStyleFor(lineCtx.lineConflict, lineCtx.useTwoColor))
  if e.cursorLineApplies(lineCtx):
    return full(cursorLineHighlightStyle())
  if e.cursorColumnApplies(displayX, cursorDisplayCol):
    return full(cursorColumnHighlightStyle())
  noPatch

proc fillLineBackground*(
    e: Editor,
    buffer: var Buffer,
    screenX, screenY: int,
    lineIndex, cursorLine: int,
    windowRightEdge: int,
    cursorDisplayCol: int = -1,
    textBuffer: TextBuffer = nil,
    isEmptyLine: bool = false,
    hasSelection: bool = false,
) =
  ## Fill the rest of the line to the window right edge.
  ## Uses cursor line highlight for the cursor line, normal style otherwise.
  ## When `textBuffer` is provided and the line is inside a git conflict block,
  ## the conflict background takes priority over cursor-line highlight.
  ## When `isEmptyLine` and `hasSelection` are both true and the visual
  ## selection covers (lineIndex, 0), column 0 is rendered with the visual
  ## selection background so that Visual mode is visible on empty lines.
  # Partial LineStyleContext: lineFillPatch only reads isCursorLine,
  # lineConflict, and useTwoColor. The seq/colorcode fields stay at their
  # defaults — lineIndex is set so any future read of it stays correct.
  let lineCtx = LineStyleContext(
    lineIndex: lineIndex,
    isCursorLine: lineIndex == cursorLine,
    lineConflict: e.resolveLineConflict(textBuffer, lineIndex),
    useTwoColor: e.config.highlight.gitConflictTwoColor,
  )
  let selectionAtStart =
    isEmptyLine and hasSelection and
    e.state.visualSelection.isPositionInSelection(
      BufferPosition(line: lineIndex, column: 0)
    )
  var displayX = 0
  while screenX + displayX < windowRightEdge:
    let inVisualSelection = displayX == 0 and selectionAtStart
    let fillStyle = normalStyle().merge(
        e.lineFillPatch(lineCtx, displayX, cursorDisplayCol, inVisualSelection)
      )
    buffer.setCell(screenX + displayX, screenY, " ", 1, fillStyle)
    displayX += 1

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
    for rune in chunk.text.runes:
      let w = runeWidth(rune)
      if w == 0:
        # Zero-width rune: fold into the preceding base cell, no advance. Skip
        # a leading mark whose base would be the real text, not virtual text.
        if result > startDisplayX:
          foldZeroWidthRune(buffer, screenX + result, screenY, rune)
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
      buffer.setCell(screenX + result, screenY, rune, w, style)
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
    useRunes: bool = true,
    appendVirtualText: bool = true,
    precomputed: Option[LinePrecomputed] = none(LinePrecomputed),
) =
  ## Render a line segment with selection highlighting and syntax highlighting
  ## useRunes: true for wrapped mode (character-based), false for byte-based rendering
  ## ctx: RenderContext containing cursor position and selection information
  ## appendVirtualText: when true, end-of-line virtual text (inlay hints, etc.)
  ##   is drawn after the real text and before the trailing fill. In wrapped mode
  ##   the caller passes false for every segment except the last.
  ## precomputed: caller-supplied fullLine/indentInfo/lineCtx shared across wrap
  ##   segments of the same logical line. When set, the caller is responsible
  ##   for having already called `updateHighlight`.

  let (fullLine, indentInfo, lineCtx) =
    if precomputed.isSome:
      let p = precomputed.get
      (p.fullLine, p.indentInfo, p.lineCtx)
    else:
      if e.hasSyntaxHighlight(textBuffer, ctx.windowMode):
        textBuffer.updateHighlight()
      let fl = textBuffer.getLine(lineIndex)
      (
        fl,
        analyzeIndentation(fl),
        e.newLineStyleContext(textBuffer, lineIndex, fl, ctx),
      )

  # Always render character by character to apply syntax highlighting
  var displayX = 0

  # Templates capture displayX / screenX / screenY / e / ctx / lineCtx /
  # indentInfo / buffer from the enclosing scope. They are templates rather
  # than procs to avoid closure-capture overhead and to let displayX mutate
  # in place. Modifier union (vs. full replacement) is intentional: syntax
  # modifiers like Bold/Italic are preserved through char overrides.

  template renderTabCell(col: int, style: Style) =
    # Tab expands to N spaces up to the next tab stop. Each expanded cell
    # honors indentation-guide drawing; the spaces themselves use a style
    # that may carry the trailingSpaces override.
    let spacesToNextTab =
      e.state.display.tabStop - (displayX mod e.state.display.tabStop)
    let tabStyle = style.merge(e.charOverridePatch(ctx, lineCtx, TAB_CHAR, col))
    for i in 0 ..< spacesToNextTab:
      if screenX + displayX < ctx.windowRightEdge:
        if e.shouldShowIndentationGuide(indentInfo, displayX, col):
          buffer.setCell(screenX + displayX, screenY, "│", 1, indentationLineStyle())
        else:
          buffer.setCell(screenX + displayX, screenY, " ", 1, tabStyle)
      displayX += 1

  template renderNormalCell(rune: Rune, col: int, style: Style) =
    let width = runeWidth(rune)
    if width == 0:
      # Zero-width rune (combining mark / ZWJ / variation selector): fold it
      # into the preceding base cell rather than writing a standalone cell the
      # next glyph would overwrite. displayX does not advance. Skip when this
      # cell starts the segment — its base, if any, is on the previous row.
      if displayX > 0:
        foldZeroWidthRune(buffer, screenX + displayX, screenY, rune)
    elif rune == ' '.Rune and e.shouldShowIndentationGuide(indentInfo, displayX, col):
      if screenX + displayX < ctx.windowRightEdge:
        buffer.setCell(screenX + displayX, screenY, "│", 1, indentationLineStyle())
      displayX += 1
    else:
      let renderStyle = style.merge(e.charOverridePatch(ctx, lineCtx, rune, col))
      if screenX + displayX < ctx.windowRightEdge:
        buffer.setCell(screenX + displayX, screenY, rune, width, renderStyle)
      displayX += width

  template renderChar(rune: Rune, col: int, style: Style) =
    if rune == TAB_CHAR:
      renderTabCell(col, style)
    else:
      renderNormalCell(rune, col, style)

  if useRunes:
    # Character-based rendering (for wrapped mode)
    var charIdx = startColumn
    for rune in displayLine.runes:
      let
        pos = BufferPosition(line: lineIndex, column: charIdx)
        style = e.getSelectionStyle(
          textBuffer,
          ctx.hasSelection,
          pos,
          ctx.cursorCol,
          ctx.windowMode,
          displayCol = displayX,
          cursorDisplayCol = ctx.cursorDisplayCol,
          lineCtx = lineCtx,
        )
      renderChar(rune, charIdx, style)
      charIdx += 1
  else:
    # Byte-based rendering (for non-wrapped mode)
    var charIdx = 0
    for rune in displayLine.runes:
      let
        col = startColumn + charIdx
        pos = BufferPosition(line: lineIndex, column: col)
        style = e.getSelectionStyle(
          textBuffer,
          ctx.hasSelection,
          pos,
          ctx.cursorCol,
          ctx.windowMode,
          displayCol = displayX,
          cursorDisplayCol = ctx.cursorDisplayCol,
          lineCtx = lineCtx,
        )
      renderChar(rune, col, style)
      charIdx += 1

  # Draw end-of-line virtual text (inlay hints, etc.) after the real text and
  # before the trailing fill, so the running displayX (and thus cursor-column /
  # cursor-line fill alignment) stays correct.
  if appendVirtualText:
    displayX =
      e.appendEndOfLineVirtualText(buffer, ctx, lineCtx, displayX, screenX, screenY)

  # Fill the rest of the line to the window right edge.
  # Always fill to clear stale content (e.g. old cursor line highlight).
  # Visual selection past the line end is not tracked here (matches prior
  # behavior); add inVisualSelection support to lineFillPatch if needed later.
  while screenX + displayX < ctx.windowRightEdge:
    let fillStyle = normalStyle().merge(
        e.lineFillPatch(
          lineCtx, displayX, ctx.cursorDisplayCol, inVisualSelection = false
        )
      )
    buffer.setCell(screenX + displayX, screenY, " ", 1, fillStyle)
    displayX += 1

proc fmtLineNum(
    state: EditorState, lineIndex: int, cursorLine: int, width: int
): string =
  if state.display.relativeLineNumbers:
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
    sidebarWidth = e.calculateSidebarWidth(window.mode)
    scrollbarWidth = e.calculateScrollbarWidth(window.mode)
    maxWidth = window.viewport.width - sidebarWidth - scrollbarWidth - lineNumOffset
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
    # Empty line - just render line number (if enabled)
    if lineNumOffset > 0:
      let lineNumStr = e.state.fmtLineNum(lineIndex, window.cursor.line, lineNumOffset)
      if lineNumScreenX + lineNumStr.len <= buffer.area.width:
        buffer.setString(lineNumScreenX, actualScreenY, lineNumStr, lineStyle)
    # Fill with cursor line/column highlight if on cursor line/column
    let textScreenX = window.viewport.x + sidebarWidth + lineNumOffset
    e.fillLineBackground(
      buffer,
      textScreenX,
      actualScreenY,
      lineIndex,
      window.cursor.line,
      window.viewport.x + window.viewport.width,
      cursorDisplayCol = ctx.cursorDisplayCol,
      textBuffer = window.buffer,
      isEmptyLine = true,
      hasSelection = ctx.hasSelection,
    )
    # Empty lines bypass renderLineSegmentWithSelection, so draw any end-of-line
    # virtual text (inlay hints) here too, over the just-filled background.
    # Partial lineCtx: appendEndOfLineVirtualText -> lineFillPatch only reads
    # isCursorLine, lineConflict, and useTwoColor.
    let vtLineCtx = LineStyleContext(
      lineIndex: lineIndex,
      isCursorLine: lineIndex == window.cursor.line,
      lineConflict: e.resolveLineConflict(window.buffer, lineIndex),
      useTwoColor: e.config.highlight.gitConflictTwoColor,
    )
    discard e.appendEndOfLineVirtualText(
      buffer, ctx, vtLineCtx, 0, textScreenX, actualScreenY
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

  let tabStop = e.state.display.tabStop

  # Build per-logical-line state once so each wrap segment can reuse it.
  if e.hasSyntaxHighlight(window.buffer, ctx.windowMode):
    window.buffer.updateHighlight()
  let precomputed = some(
    LinePrecomputed(
      fullLine: line,
      indentInfo: analyzeIndentation(line),
      lineCtx: e.newLineStyleContext(window.buffer, lineIndex, line, ctx),
    )
  )

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
          useRunes = true,
          appendVirtualText = endCharCol >= lineCharLen,
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
    sidebarWidth = e.calculateSidebarWidth(window.mode)
    scrollbarWidth = e.calculateScrollbarWidth(window.mode)
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

  # Render text content
  # Use character-based slicing (not byte-based) for multibyte character support
  let
    displayLine =
      if window.viewport.leftColumn < line.charLen:
        line.runeSubStr(window.viewport.leftColumn)
      else:
        ""
    textScreenX = window.viewport.x + sidebarWidth + lineNumOffset

  if displayLine.len > 0 and textScreenX < buffer.area.width:
    let cellBudget =
      window.viewport.width - sidebarWidth - scrollbarWidth - lineNumOffset
    if cellBudget > 0:
      # Clip by display width, not byte length: take as many runes as fit
      # cellBudget cells (tabs expanded, CJK = 2 cells), like the wrapped path.
      # Slicing by byte count would hide content on multibyte/CJK lines and
      # overflow the edge on tab-heavy lines (the lint_string_len hazard).
      let
        (_, segmentWidth, endByte) = displayWidthSubstrFromByte(
          displayLine, 0, cellBudget, e.state.display.tabStop
        )
        visibleSlice = displayLine[0 ..< endByte]
      if visibleSlice.len > 0:
        # Append end-of-line virtual text only when the whole line is visible
        # (every rune consumed and within budget); otherwise the hint anchor (the
        # line end) is off-screen and would land mid-line. Window-edge clipping
        # alone is not enough — the scrollbar gutter can leave room for a stray rune.
        let lineEndVisible = endByte >= displayLine.len and segmentWidth <= cellBudget
        e.renderLineSegmentWithSelection(
          window.buffer,
          buffer,
          visibleSlice,
          textScreenX,
          actualScreenY,
          lineIndex,
          window.viewport.leftColumn,
          ctx,
          useRunes = false,
          appendVirtualText = lineEndVisible,
        )
  else:
    # Empty line or scrolled past line end - fill to clear stale content
    e.fillLineBackground(
      buffer,
      textScreenX,
      actualScreenY,
      lineIndex,
      window.cursor.line,
      window.viewport.x + window.viewport.width,
      cursorDisplayCol = ctx.cursorDisplayCol,
      textBuffer = window.buffer,
      isEmptyLine = (line.charLen == 0),
      hasSelection = ctx.hasSelection,
    )
    # The text path skips end-of-line virtual text for empty/scrolled-past
    # lines. Draw it here when the line's end column is still on-screen
    # (vtStartCol >= 0); when scrolled horizontally past the line end the
    # anchor is off-screen, so skip it.
    let vtStartCol = line.charLen - window.viewport.leftColumn
    if vtStartCol >= 0:
      # Partial lineCtx: appendEndOfLineVirtualText -> lineFillPatch only reads
      # isCursorLine, lineConflict, and useTwoColor.
      let vtLineCtx = LineStyleContext(
        lineIndex: lineIndex,
        isCursorLine: lineIndex == window.cursor.line,
        lineConflict: e.resolveLineConflict(window.buffer, lineIndex),
        useTwoColor: e.config.highlight.gitConflictTwoColor,
      )
      discard e.appendEndOfLineVirtualText(
        buffer, ctx, vtLineCtx, vtStartCol, textScreenX, actualScreenY
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
    sidebarWidth = e.calculateSidebarWidth(window.mode)
    scrollbarWidth = e.calculateScrollbarWidth(window.mode)
    lineNumScreenX = window.viewport.x + sidebarWidth
    textScreenX = window.viewport.x + sidebarWidth + lineNumOffset
    foldText = window.buffer.formatFoldText(fold)
    windowRightEdge = window.viewport.x + window.viewport.width - scrollbarWidth

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
        foldText.runeSubStr(0, fitChars)
      else:
        foldText
    buffer.setString(textScreenX, actualScreenY, displayText, foldStyle())

proc renderScrollbar*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    visibleHeight: int,
    tabLineOffset: int,
) =
  ## Render a scrollbar on the right edge of the window.
  ## The scrollbar shows the current viewport position within the buffer.
  let
    totalLines = window.buffer.len
    scrollbarWidth = e.calculateScrollbarWidth(window.mode)
    scrollbarStartX = window.viewport.x + window.viewport.width - scrollbarWidth

  if totalLines <= visibleHeight or visibleHeight <= 0 or scrollbarWidth <= 0:
    return

  # Calculate thumb size and position
  let
    thumbSize = max(1, (visibleHeight * visibleHeight) div totalLines)
    maxTopLine = totalLines - visibleHeight
    thumbPos =
      if maxTopLine > 0:
        (window.viewport.topLine * (visibleHeight - thumbSize)) div maxTopLine
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
    if e.state.display.showSidebar:
      # When the git-diff gutter is active for a git-tracked file, it is the
      # authoritative (content-based) change indicator, so suppress the session
      # "modified lines" fallback. Both draw the same `~`/`+` glyphs, and the
      # session markers are history-based — they linger after the buffer is
      # edited back to match HEAD (git diff goes empty but the line stays
      # flagged), making it look like a stuck git marker. For non-git / untracked
      # files the git gutter shows nothing, so the session fallback is kept.
      let showSessionMarkers =
        e.state.display.showModifiedLines and
        not (e.state.display.showGitDiff and isBufferGitTracked(window.buffer))
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

  # Get visual selection range if active
  let (hasSelection, selStart, selEnd) =
    e.getVisualSelection(window.mode, window.active)

  # Compute cursor's display column (accounting for tabs/wide chars and scroll offset)
  let leftCol = if e.state.display.lineWrap: 0 else: window.viewport.leftColumn
  let cursorDisplayCol =
    if window.cursor.line < lineCount:
      let cursorLineText = window.buffer.getLine(window.cursor.line)
      bufferColToDisplayCol(
        cursorLineText, window.cursor.column, e.state.display.tabStop, leftCol
      )
    else:
      window.cursor.column

  # Create render context for this window
  let ctx = RenderContext(
    cursorLine: window.cursor.line,
    cursorCol: window.cursor.column,
    cursorDisplayCol: cursorDisplayCol,
    hasSelection: hasSelection,
    selStart: selStart,
    selEnd: selEnd,
    windowMode: window.mode,
    windowRightEdge: window.viewport.x + window.viewport.width,
    isActiveWindow: isActiveWindow,
    # Virtual text caches (inlay hints, ...) track the active buffer, so only
    # the active window draws them.
    virtualTextProviders:
      if isActiveWindow:
        e.buildVirtualTextProviders()
      else:
        @[],
  )

  var
    screenY = tabLineOffset
    lineIndex = window.viewport.topLine

  while screenY < visibleHeight + tabLineOffset and lineIndex < lineCount:
    # sidebarIndex is 0-based index into sidebar buffer (based on logical line, not screen row)
    let sidebarIndex = lineIndex - window.viewport.topLine

    # Check if this line is inside a collapsed fold (but not the start line)
    if window.buffer.foldState.isLineInCollapsedFold(lineIndex):
      # Skip this line (it's hidden inside a fold)
      inc lineIndex
      continue

    # Check if this line is the start of a collapsed fold
    let foldOpt = window.buffer.foldState.getCollapsedFoldAt(lineIndex)
    if foldOpt.isSome and foldOpt.get.startLine == lineIndex:
      # Render the fold marker
      if maybeSidebar.isSome:
        renderWindowSidebar(buffer, window, maybeSidebar.get, screenY, sidebarIndex, 0)
      e.renderFoldLine(buffer, window, lineNumOffset, screenY, foldOpt.get)
      # Skip to the line after the fold
      lineIndex = foldOpt.get.endLine + 1
      inc screenY
      continue

    # Normal line rendering
    # Render sidebar if enabled
    if maybeSidebar.isSome:
      renderWindowSidebar(buffer, window, maybeSidebar.get, screenY, sidebarIndex, 0)

    if e.state.display.lineWrap:
      # Only the top logical line skips leading wrap segments (sub-line scroll).
      let skipSegments =
        if lineIndex == window.viewport.topLine: window.viewport.topWrapOffset else: 0
      e.renderWindowLineWrapped(
        buffer,
        window,
        lineNumOffset,
        ctx,
        screenY,
        lineIndex,
        visibleHeight,
        tabLineOffset,
        skipSegments = skipSegments,
      )
    else:
      e.renderWindowLineNoWrap(buffer, window, lineNumOffset, ctx, screenY, lineIndex)
      inc screenY
      inc lineIndex

  # Render scrollbar on the right edge if enabled (file editing modes only)
  if e.calculateScrollbarWidth(window.mode) > 0:
    e.renderScrollbar(buffer, window, visibleHeight, tabLineOffset)

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
  elif not e.state.display.multiStatusLine:
    # Horizontal split - draw horizontal separator at window boundary
    # ONLY when using a single status line
    let sepY = window.viewport.y + window.viewport.height
    if sepY < buffer.area.height:
      # Draw separator for the width of this window
      for x in window.viewport.x ..< (window.viewport.x + window.viewport.width):
        if x < buffer.area.width:
          buffer.setString(x, sepY, "─", separatorStyle())
