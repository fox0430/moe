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

## Rendering helper functions and utilities
##
## This module contains pure functions and utilities for rendering operations
## that don't depend heavily on Editor state. Extracted from editor.nim to
## improve modularity and prepare for additional rendering features.

import std/unicode
import pkg/celina

import types, buffer, unicode_utils, color, modes, sidebar

# Rendering constants
const
  TAB_CHAR* = 0x09.Rune ## Tab character constant
  FULLWIDTH_SPACE* = 0x3000.Rune ## Full-width space character (U+3000)

  TabLineHeight* = 1 ## Height of tab line
  StatusLineReserve* = 1

  # Line number display constants
  LineNumberBase* = 1 # Convert 0-based index to 1-based display
  LineNumberSpacer* = 1 # Space after line number
  LineNumberPadding* = 1 # Padding for alignment
  LineNumberWidthExtra* = 2 # Extra width for line number area (number + spaces)

  InputWrapTabStop* = 1
    ## Tab stop used on the command-line input wrap grid. The row count, the
    ## cursor cell and the wrapped rendering must all use this same value.

# Rendering style getters - dynamically retrieve from theme

proc normalStyle*(): Style =
  ## Get default text style from theme
  getThemeStyle(EditorColorPairIndex.default)

proc visualStyle*(): Style =
  ## Get visual selection style from theme
  getThemeStyle(EditorColorPairIndex.selectArea)

proc searchHighlightStyle*(): Style =
  ## Get search result highlight style from theme
  getThemeStyle(EditorColorPairIndex.searchResult)

proc gitConflictStyle*(): Style =
  ## One-color fallback for git conflict highlighting (used when the
  ## two-color config is disabled).
  getThemeStyle(EditorColorPairIndex.gitConflict)

proc gitConflictMarkerStyle*(): Style =
  ## Style for the marker lines (`<<<<<<<` / `|||||||` / `=======` / `>>>>>>>`).
  getThemeStyle(EditorColorPairIndex.gitConflictMarker)

proc gitConflictOursStyle*(): Style =
  ## Style for the "ours" side of a merge conflict.
  getThemeStyle(EditorColorPairIndex.gitConflictOurs)

proc gitConflictBaseStyle*(): Style =
  ## Style for the base (merged common ancestor) side of a diff3 conflict.
  getThemeStyle(EditorColorPairIndex.gitConflictBase)

proc gitConflictTheirsStyle*(): Style =
  ## Style for the "theirs" side of a merge conflict.
  getThemeStyle(EditorColorPairIndex.gitConflictTheirs)

proc conflictStyleFor*(kind: ConflictMarkerKind, useTwoColor: bool): Style =
  ## Resolve the background style for a conflict line kind.
  if not useTwoColor:
    return gitConflictStyle()
  case kind
  of cmkStartMarker, cmkBaseMarker, cmkSeparator, cmkEndMarker:
    gitConflictMarkerStyle()
  of cmkOurs:
    gitConflictOursStyle()
  of cmkBase:
    gitConflictBaseStyle()
  of cmkTheirs:
    gitConflictTheirsStyle()
  of cmkNone:
    normalStyle()

proc lineNumStyle*(): Style =
  ## Get line number style from theme
  getThemeStyle(EditorColorPairIndex.lineNum)

proc currentLineStyle*(): Style =
  ## Get current line number style from theme (with bold)
  getThemeStyle(EditorColorPairIndex.currentLineNum, {StyleModifier.Bold})

proc separatorStyle*(): Style =
  ## Get separator style (uses line number colors)
  getThemeStyle(EditorColorPairIndex.lineNum)

proc commandStyle*(): Style =
  ## Get command line style from theme (with bold)
  getThemeStyle(EditorColorPairIndex.commandLine, {StyleModifier.Bold})

proc cursorLineHighlightStyle*(): Style =
  ## Get current line background highlight style from theme
  getThemeStyle(EditorColorPairIndex.currentLineBg)

proc cursorColumnHighlightStyle*(): Style =
  ## Get current column background highlight style from theme
  getThemeStyle(EditorColorPairIndex.currentColumnBg)

proc findCharMatchStyle*(): Style =
  ## Get find character match highlight style from theme (f/F/t/T)
  getThemeStyle(EditorColorPairIndex.findCharMatch)

proc indentationLineStyle*(): Style =
  ## Get indentation guide style from theme
  getThemeStyle(EditorColorPairIndex.indentationLine)

proc foldStyle*(): Style =
  ## Get folding line style from theme
  getThemeStyle(EditorColorPairIndex.foldingLine)

proc scrollbarThumbStyle*(): Style =
  ## Get scrollbar thumb (handle) style from theme — solid block
  getThemeStyle(EditorColorPairIndex.scrollBarThumb)

proc scrollbarTrackStyle*(): Style =
  ## Get scrollbar track (background) style from theme
  getThemeStyle(EditorColorPairIndex.scrollBarTrack)

proc fullWidthSpaceStyle*(): Style =
  ## Get full-width space highlight style from theme
  getThemeStyle(EditorColorPairIndex.highlightFullWidthSpace)

proc trailingSpacesStyle*(): Style =
  ## Get trailing spaces highlight style from theme
  getThemeStyle(EditorColorPairIndex.highlightTrailingSpaces)

proc parenPairStyle*(): Style =
  ## Get matching parenthesis pair highlight style from theme
  getThemeStyle(EditorColorPairIndex.parenPair)

proc currentWordStyle*(): Style =
  ## Get current word highlight style from theme
  getThemeStyle(EditorColorPairIndex.currentWord)

proc snippetTabStopStyle*(): Style =
  ## Get active snippet tabstop placeholder style from theme
  getThemeStyle(EditorColorPairIndex.snippetTabStop)

# Document Highlight styles (LSP textDocument/documentHighlight)
proc documentHighlightTextStyle*(): Style =
  ## Style for generic text occurrence (DocumentHighlightKind.Text)
  getThemeStyle(EditorColorPairIndex.documentHighlightText)

proc documentHighlightReadStyle*(): Style =
  ## Style for read-access of a symbol (DocumentHighlightKind.Read)
  getThemeStyle(EditorColorPairIndex.documentHighlightRead)

proc documentHighlightWriteStyle*(): Style =
  ## Style for write-access of a symbol (DocumentHighlightKind.Write)
  getThemeStyle(EditorColorPairIndex.documentHighlightWrite)

# Pure utility functions

proc formatLineNumber*(lineIndex: int, width: int): string =
  ## Format a line number string with proper alignment
  align($(lineIndex + LineNumberBase), width - LineNumberPadding) & " "

proc formatRelativeLineNumber*(lineIndex: int, cursorLine: int, width: int): string =
  ## Format a relative line number string. Current line shows absolute number.
  let num =
    if lineIndex == cursorLine:
      lineIndex + LineNumberBase
    else:
      abs(lineIndex - cursorLine)
  align($num, width - LineNumberPadding) & " "

func tabAdvance*(currentWidth, tabStop: int): int {.inline.} =
  ## Spaces a tab character occupies when placed at column `currentWidth`,
  ## i.e. the distance to the next tab stop. `tabStop <= 0` is coerced to 1
  ## to prevent division by zero; the single place encoding that guard.
  let safeTabStop = if tabStop > 0: tabStop else: 1
  safeTabStop - (currentWidth mod safeTabStop)

func startsNewWrapSegment*(segmentWidth, runeWidth, maxWidth: int): bool {.inline.} =
  ## Canonical wrap-boundary rule shared by every wrap walker
  ## (calculateWrapCount, cursorWrapPosition, displayWidthSubstrFromByte):
  ## a rune starts a new segment when the current segment is non-empty and
  ## the rune does not fit. Keeping a single definition guarantees the
  ## reserved height, the cursor cell and the drawn segments stay on the
  ## same grid.
  segmentWidth > 0 and segmentWidth + runeWidth > maxWidth

proc displayWidthSubstrWithTabs*(
    text: string, startChar: int, maxWidth: int, tabStop: int
): (int, int) =
  ## Calculate how many characters from startChar fit within maxWidth display columns,
  ## accounting for tab characters expanded relative to the segment start.
  ## Returns (charCount, actualDisplayWidth)
  var
    currentChar = 0
    currentWidth = 0
    charCount = 0

  for rune in text.runes:
    if currentChar < startChar:
      currentChar += 1
      continue

    let w =
      if rune == TAB_CHAR:
        tabAdvance(currentWidth, tabStop)
      else:
        runeWidth(rune)

    if currentWidth + w > maxWidth:
      break

    currentWidth += w
    charCount += 1
    currentChar += 1

  return (charCount, currentWidth)

proc displayWidthSubstrFromByte*(
    text: string, startByte: int, maxWidth: int, tabStop: int
): (int, int, int) =
  ## Calculate segment boundary starting from a byte position.
  ## Returns (charCount, actualDisplayWidth, endBytePosition).
  ## Unlike displayWidthSubstrWithTabs, this starts directly from startByte
  ## instead of scanning from the beginning, avoiding O(startChar) skip overhead.
  var
    bytePos = startByte
    currentWidth = 0
    charCount = 0

  while bytePos < text.len:
    let
      rune = text.runeAt(bytePos)
      runeBytes = runeLenAt(text, bytePos)
      w =
        if rune == TAB_CHAR:
          tabAdvance(currentWidth, tabStop)
        else:
          runeWidth(rune)

    if startsNewWrapSegment(currentWidth, w, maxWidth):
      # Character doesn't fit — return without including it
      return (charCount, currentWidth, bytePos)

    currentWidth += w
    charCount += 1
    bytePos += runeBytes

  return (charCount, currentWidth, bytePos)

proc screenXToCharIndex*(
    text: string, startChar: int, targetDisplayX: int, tabStop: int
): int =
  ## Return the character offset (from startChar) corresponding to targetDisplayX
  ## display columns within a wrap segment starting at startChar.
  ## For multi-column characters (tabs, wide chars), clicking anywhere within the
  ## character's display width selects that character.
  var
    currentChar = 0
    currentWidth = 0
    charOffset = 0

  for rune in text.runes:
    if currentChar < startChar:
      currentChar += 1
      continue

    let w =
      if rune == TAB_CHAR:
        tabAdvance(currentWidth, tabStop)
      else:
        runeWidth(rune)

    # If targetDisplayX falls within this character's range, stop here
    if currentWidth + w > targetDisplayX:
      break

    currentWidth += w
    charOffset += 1
    currentChar += 1

  return charOffset

proc calculateWrapCount*(text: string, maxWidth: int, tabStop: int): int =
  ## Calculate how many screen lines a logical line will take when wrapped.
  ## Uses display width (accounting for tabs and wide characters).
  ## Single-pass O(n) implementation — iterates runes once without re-scanning.
  if text.len == 0:
    return 1
  result = 1
  var segmentWidth = 0

  for rune in text.runes:
    let w =
      if rune == TAB_CHAR:
        tabAdvance(segmentWidth, tabStop)
      else:
        runeWidth(rune)

    if startsNewWrapSegment(segmentWidth, w, maxWidth):
      result += 1
      # Recalculate width in new segment context (tab width depends on position)
      segmentWidth =
        if rune == TAB_CHAR:
          tabAdvance(0, tabStop)
        else:
          w
    else:
      segmentWidth += w

proc ensureFresh*(
    cache: WrapCountCache, buffer: TextBuffer, maxWidth: int, tabStop: int
) =
  ## Validate the cache key against the current frame's
  ## `(buffer, maxWidth, tabStop)` and bump the generation if anything
  ## changed. Hot loops should call this once before entering the loop,
  ## then call `cachedWrapCount` per line.
  if cache.bufferId != buffer.id or cache.bufferContentVersion != buffer.contentVersion or
      cache.viewportWidth != maxWidth or cache.tabStop != tabStop:
    if cache.bufferId != buffer.id:
      # All gens become stale on the gen bump below, so drop the storage
      # entirely instead of keeping shrunk-but-poisoned entries.
      cache.counts.setLen(0)
      cache.gens.setLen(0)
    cache.currentGen.inc
    cache.bufferId = buffer.id
    cache.bufferContentVersion = buffer.contentVersion
    cache.viewportWidth = maxWidth
    cache.tabStop = tabStop

proc cachedWrapCount*(cache: WrapCountCache, buffer: TextBuffer, line: int): int =
  ## Per-line lookup. Caller must have invoked `ensureFresh` first with
  ## the frame's `(maxWidth, tabStop)`; this proc uses the cached values.
  if line >= cache.gens.len:
    let needed = line + 1
    cache.counts.setLen(needed)
    cache.gens.setLen(needed)
  if cache.gens[line] != cache.currentGen:
    cache.counts[line] =
      calculateWrapCount(buffer.getLine(line), cache.viewportWidth, cache.tabStop)
    cache.gens[line] = cache.currentGen
  cache.counts[line]

proc getWrapCount*(
    cache: WrapCountCache, buffer: TextBuffer, line: int, maxWidth: int, tabStop: int
): int =
  ## Single-shot memoized `calculateWrapCount`. For tight loops that hit
  ## the same `(maxWidth, tabStop)` repeatedly, prefer
  ## `ensureFresh` + `cachedWrapCount` to skip the per-call key compare.
  cache.ensureFresh(buffer, maxWidth, tabStop)
  cache.cachedWrapCount(buffer, line)

proc clearBuffer*(buffer: var Buffer) =
  ## Clear the entire buffer to prevent rendering artifacts
  ## Uses the theme's default background color for consistent appearance
  let clearStyle = normalStyle()

  for y in 0 ..< buffer.area.height:
    for x in 0 ..< buffer.area.width:
      buffer[x, y] = cell(" ", clearStyle)

# Layout calculation functions

proc calculateLineNumOffset*(buffer: TextBuffer, showLineNumber: bool = true): int =
  ## Calculate line number display offset based on buffer size
  ## If showLineNumber is false, returns 0 (line numbers hidden)
  ## Utility buffers (filer, buffer manager, etc.) never show line numbers
  if not showLineNumber or buffer.isUtilityBuffer:
    return 0
  if buffer.len > 0:
    len($buffer.len) + LineNumberSpacer
  else:
    0

proc sidebarWidthFor*(mode: EditorMode, showSidebar: bool): int {.inline.} =
  ## Mode-gated sidebar width. Sidebar only renders in file-edit modes.
  if mode.isFileEditMode and showSidebar: DefaultSidebarWidth else: 0

proc scrollbarWidthFor*(
    mode: EditorMode, scrollbar: bool, scrollbarWidth: int
): int {.inline.} =
  ## Mode-gated scrollbar width. Scrollbar only renders in file-edit modes.
  if mode.isFileEditMode and scrollbar and scrollbarWidth > 0: scrollbarWidth else: 0

proc sidebarWidthFor*(window: EditorWindow, showSidebar: bool): int =
  ## Sidebar width for a window. Suppressed while the window holds a special
  ## mode state (Filer, Help, ...) even if its transient mode is Visual.
  if window.modeState.kind != mskNone:
    0
  else:
    sidebarWidthFor(window.mode, showSidebar)

proc scrollbarWidthFor*(
    window: EditorWindow, scrollbar: bool, scrollbarWidth: int
): int =
  ## Scrollbar width for a window, gated like `sidebarWidthFor`.
  if window.modeState.kind != mskNone:
    0
  else:
    scrollbarWidthFor(window.mode, scrollbar, scrollbarWidth)

proc viewportOffsetFor*(
    buffer: TextBuffer,
    window: EditorWindow,
    showLineNumbers, showSidebar: bool,
    scrollbar: bool,
    scrollbarWidth: int,
): int =
  ## Single derivation of a window's non-text width: line number + sidebar +
  ## scrollbar.
  calculateLineNumOffset(buffer, showLineNumbers) + sidebarWidthFor(window, showSidebar) +
    scrollbarWidthFor(window, scrollbar, scrollbarWidth)

proc viewportOffsetFor*(buffer: TextBuffer, state: EditorState): int =
  ## Convenience wrapper: pulls every display field the offset needs from
  ## `state`, for the active window.
  viewportOffsetFor(
    buffer, state.activeWindow, state.showLineNumbers, state.showSidebar,
    state.scrollbar, state.scrollbarWidth,
  )

proc textAreaWidthFor*(viewportWidth, viewportOffset: int): int =
  ## Cells a window leaves for text once the gutters are removed.
  max(0, viewportWidth - viewportOffset)

proc wrapWidthFor*(viewportWidth, viewportOffset: int): int =
  ## `textAreaWidthFor` clamped to at least one cell. This is the
  ## `WrapCountCache` key: renderer, screen-cursor, mouse hit-test and viewport
  ## scroll must all key with the same value or the cache serves counts
  ## computed for a different width.
  max(1, textAreaWidthFor(viewportWidth, viewportOffset))

proc findMaxBottomY*(windows: seq[EditorWindow]): int =
  ## Find the maximum bottom Y coordinate among all windows
  result = 0
  for window in windows:
    let bottomY = window.viewport.y + window.viewport.height
    if bottomY > result:
      result = bottomY

proc calculateWindowStatusLineY*(window: EditorWindow, isBottomWindow: bool): int =
  ## Calculate Y position for window status line
  ## Status line is always at the last row of the window area (y + height - 1)
  ## For bottom windows, the command line overlays the status line when active
  window.viewport.y + window.viewport.height - 1

# Display width calculation with tab support

proc displayWidthUpToWithTabs*(text: string, charPos: int, tabStop: int): int =
  ## Calculate the display width from start to charPos, accounting for tab characters
  ## charPos is a character index (not byte position)
  ## Tab characters expand to the next tab stop position
  ##
  ## Note: If tabStop <= 0, it defaults to 1 to prevent division by zero.
  ##       If charPos < 0, returns 0.

  # Guard against invalid inputs without crashing
  if charPos < 0:
    return 0

  result = 0
  var currentChar = 0

  for rune in text.runes:
    if currentChar >= charPos:
      break

    if rune == TAB_CHAR:
      result += tabAdvance(result, tabStop)
    else:
      result += runeWidth(rune)

    currentChar += 1

proc displayWidthBetweenWithTabs*(
    text: string, startChar, endChar: int, tabStop: int
): int =
  ## Calculate the display width from startChar to endChar, with tabs expanded
  ## relative to startChar. Use this instead of subtracting two
  ## `displayWidthUpToWithTabs` results whenever the text is rendered as a slice
  ## starting at startChar: a tab lands on a different stop when counted from the
  ## slice start than when counted from the line start. Inverse of
  ## `screenXToCharIndex`.
  if endChar <= startChar or startChar < 0:
    return 0

  var currentChar = 0

  for rune in text.runes:
    if currentChar < startChar:
      currentChar += 1
      continue
    if currentChar >= endChar:
      break

    if rune == TAB_CHAR:
      result += tabAdvance(result, tabStop)
    else:
      result += runeWidth(rune)

    currentChar += 1

proc displayWidthWithTabs*(text: string, tabStop: int): int =
  ## Calculate the display width of a string, accounting for tab characters
  ## Tab characters expand to the next tab stop position
  ##
  ## Note: If tabStop <= 0, it defaults to 1 to prevent division by zero.

  result = 0
  for rune in text.runes:
    if rune == TAB_CHAR:
      result += tabAdvance(result, tabStop)
    else:
      result += runeWidth(rune)

proc cursorWrapPosition*(
    text: string, cursorChar: int, maxWidth: int, tabStop: int
): (int, int) =
  ## Calculate which wrap segment the cursor falls in and its display column
  ## within that segment. Returns (wrapLineIndex, displayColumnInSegment).
  ## Single-pass O(n) implementation — iterates runes once without re-scanning.
  if text.len == 0 or cursorChar <= 0:
    return (0, 0)

  var
    segmentWidth = 0
    wrapLine = 0
    charIndex = 0

  for rune in text.runes:
    let w =
      if rune == TAB_CHAR:
        tabAdvance(segmentWidth, tabStop)
      else:
        runeWidth(rune)

    if startsNewWrapSegment(segmentWidth, w, maxWidth):
      wrapLine += 1
      let newW =
        if rune == TAB_CHAR:
          tabAdvance(0, tabStop)
        else:
          w

      # Check if cursor is at (or past) this character
      if charIndex >= cursorChar:
        return (wrapLine, 0)

      segmentWidth = newW
    else:
      # Check if cursor is at (or past) this character
      if charIndex >= cursorChar:
        return (wrapLine, segmentWidth)

      segmentWidth += w

    charIndex += 1

  # Cursor is at or past end of text — return current segment position
  return (wrapLine, segmentWidth)

# Dynamic command-line area height

func steadyBottomAreaHeight*(): int {.inline.} =
  ## Height of the bottom area in the steady state: no overlay active and no
  ## multi-line status message — the single row shared by the status line and
  ## the command line.
  ## This is the documented floor of `bottomAreaHeight`. All PERSISTENT window
  ## geometry (splits, equalization, PTY sizing, scroll fallbacks) must use
  ## this value; transient growth (wrapped input, multi-line messages) must
  ## never be baked into persistent layout.
  1

func steadyReservedBottom*(isBottomWindow: bool): int {.inline.} =
  ## Steady bottom reserve for a window: the shared status/command row for
  ## bottom windows, nothing for the others. The single place encoding the
  ## `if isBottomWindow: steadyBottomAreaHeight() else: 0` rule.
  if isBottomWindow:
    steadyBottomAreaHeight()
  else:
    0

proc overlayInput*(state: EditorState): tuple[text: string, cursorChar: int] =
  ## Full display text and rune-index cursor position for the active overlay.
  ## Matches the rendering in renderBottomLines: command text includes the
  ## leading ':', search text is prefixed with '/' or '?', rename input is
  ## prefixed with "Rename: " (cursor pinned at the end).
  if state.isCommandOverlay:
    (state.input.commandText, state.input.commandCursor + 1)
  elif state.isSearchOverlay:
    let prompt = if state.input.search.direction == Forward: "/" else: "?"
    (prompt & state.input.search.text, 1 + state.input.search.cursor)
  elif state.isRenameOverlay:
    let prompt = "Rename: " & state.renameState.text
    (prompt, prompt.runeLen)
  else:
    ("", 0)

proc wrappedInputCursor*(
    text: string, cursorChar: int, width: int
): tuple[row, col: int] =
  ## Cursor cell on the wrap grid of an input line. Like Vim, when the cursor
  ## sits exactly at the right edge it overflows to column 0 of the next row.
  let
    safeWidth = max(1, width)
    (row, col) = cursorWrapPosition(text, cursorChar, safeWidth, InputWrapTabStop)
  if col >= safeWidth:
    (row + 1, 0)
  else:
    (row, col)

proc wrappedInputGrid*(
    text: string, cursorChar: int, width: int
): tuple[totalRows, cursorRow, cursorCol: int] =
  ## The full input wrap grid: total rows (including the row holding the
  ## cursor cell, which may extend one row past the text itself) plus the
  ## cursor cell. Compute once and share between the height and the
  ## rendering instead of re-walking the text per consumer.
  let
    safeWidth = max(1, width)
    (row, col) = wrappedInputCursor(text, cursorChar, safeWidth)
    totalRows = max(calculateWrapCount(text, safeWidth, InputWrapTabStop), row + 1)
  (totalRows, row, col)

proc wrappedInputRowCount*(text: string, cursorChar: int, width: int): int =
  ## Number of rows the wrapped input occupies, including the row holding the
  ## cursor cell (which may extend one row past the text itself).
  wrappedInputGrid(text, cursorChar, width).totalRows

proc commandLineAreaHeight*(state: EditorState, width: int): int =
  ## Single source of truth for the dynamic command-line area height
  ## (content rows, excluding the status line):
  ## - command/search/rename overlay: wrapped rows of the input
  ## - otherwise: status message line count
  ## Capped at MaxStatusMessageLines, floor 1 (the bottom row always exists).
  if width <= 0:
    # Uninitialized viewport (e.g. synthetic test editors before first render)
    return steadyBottomAreaHeight()
  if state.hasOverlay:
    let (text, cursorChar) = state.overlayInput()
    min(MaxStatusMessageLines, wrappedInputRowCount(text, cursorChar, width))
  else:
    max(1, state.statusMessageLineCount())

proc bottomAreaHeight*(state: EditorState, width: int): int =
  ## Total number of rows reserved at the bottom of the screen.
  ## When the command-line area is a single row, the status line shares it;
  ## when it grows, the status line is pushed up onto its own extra row.
  let h = state.commandLineAreaHeight(width)
  if h <= 1:
    1
  elif state.showStatusLine:
    h + 1
  else:
    h

proc isWhitespace(rune: Rune): bool =
  ## Check if a rune is a whitespace character (space, tab, full-width space)
  rune == ' '.Rune or rune == TAB_CHAR or rune == FULLWIDTH_SPACE

proc findTrailingSpaceStart*(text: string): int =
  ## Find the character index where trailing spaces start.
  ## Returns the character count (length) if no trailing spaces.
  ## Returns 0 if the entire line is whitespace.
  # Single forward pass tracking the last non-whitespace rune index; avoids
  # materializing the whole line into a `seq[Rune]` (an allocation per visible
  # line per frame on the render hot path).
  var
    idx = 0
    lastNonSpace = -1
  for r in text.runes:
    if not isWhitespace(r):
      lastNonSpace = idx
    inc idx

  # Index after the last non-whitespace rune (0 when empty or all whitespace).
  lastNonSpace + 1
