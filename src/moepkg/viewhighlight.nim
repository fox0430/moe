#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[options, deques]
import independentutils, bufferstatus, highlight, color, windownode, gapbuffer,
       unicodeext, editorview, searchutils, settings, ui, syntaxcheck, git,
       theme

type
  BufferInView = ref object
    buffer: seq[Runes]
    originalLineRange: Range
    currentPosition: BufferPosition

proc initBufferPosition(
  n: WindowNode): BufferPosition {.inline.} =

    BufferPosition(line: n.currentLine, column: n.currentColumn)

proc initBufferInView(
  bufStatus: BufferStatus,
  windowNode: WindowNode): BufferInView =
    ## Returns displayed part of the buffer and info.

    let
      range = windowNode.view.rangeOfOriginalLineInView
      firstLine = range.first
      lastLine =
        if range.last > bufStatus.buffer.high: bufStatus.buffer.high
        else: range.last

    return BufferInView(
      buffer: bufStatus.buffer[firstLine .. lastLine],
      originalLineRange: Range(first: firstLine, last: lastLine),
      currentPosition: initBufferPosition(windowNode))

proc currentPositionInView(b: BufferInView): BufferPosition {.inline.} =
  BufferPosition(
    line: b.currentPosition.line - b.originalLineRange.first,
    column: b.currentPosition.column)

proc currentLineInView(b: BufferInView): int {.inline.} =
  b.currentPosition.line - b.originalLineRange.first

proc originalLine(b: BufferInView, line: int): int {.inline.} =
  b.originalLineRange.first + line

proc originalPosition(
  b: BufferInView,
  line, column: int): BufferPosition {.inline.} =

    BufferPosition(
      line: b.originalLine(line),
      column: column)

proc originalPosition(
  b: BufferInView,
  position: BufferPosition): BufferPosition {.inline.} =

    b.originalPosition(position.line, position.column)

proc highlightSelectedArea(
  highlight: var Highlight,
  bufStatus: BufferStatus,
  position: BufferPosition) =

    let area = bufStatus.selectedArea

    var colorSegment = initSelectedAreaColorSegment(
      position,
      EditorColorPairIndex.visualMode)

    if area.startLine == area.endLine:
      colorSegment.firstRow = area.startLine
      colorSegment.lastRow = area.endLine
      if area.startColumn < area.endColumn:
        colorSegment.firstColumn = area.startColumn
        colorSegment.lastColumn = area.endColumn
      else:
        colorSegment.firstColumn = area.endColumn
        colorSegment.lastColumn = area.startColumn
    elif area.startLine < area.endLine:
      colorSegment.firstRow = area.startLine
      colorSegment.lastRow = area.endLine
      colorSegment.firstColumn = area.startColumn
      colorSegment.lastColumn = area.endColumn
    else:
      colorSegment.firstRow = area.endLine
      colorSegment.lastRow = area.startLine
      colorSegment.firstColumn = area.endColumn
      colorSegment.lastColumn = area.startColumn

    if bufStatus.isVisualLineMode:
      colorSegment.firstColumn = 0
      if bufStatus.buffer[colorSegment.lastRow].high >= 0:
        colorSegment.lastColumn = bufStatus.buffer[colorSegment.lastRow].high
      else:
        colorSegment.lastColumn = 0

    if bufStatus.isVisualBlockMode:
      highlight.overwriteColorSegmentBlock(
        bufStatus.selectedArea,
        bufStatus.buffer)
    elif bufStatus.isVisualMode:
      highlight.overwrite(colorSegment)

proc highlightPairOfParen(
  highlight: var Highlight,
  bufferInView: BufferInView) =
    ## Add a highlight for a parenthesis corresponding to the parenthesis on
    ## the cursor.

    template currentLine: int = bufferInView.currentLineInView
    template currentColumn: int = bufferInView.currentPosition.column

    template currentLineBuffer: Runes = bufferInView.buffer[currentLine]

    if currentColumn > currentLineBuffer.high: return

    let
      rune = currentLineBuffer[currentColumn]
      correspondPosition =
        if isOpenParen(rune):
          searchClosingParen(bufferInView.buffer, bufferInView.currentPosition)
        elif isCloseParen(rune):
          searchOpeningParen(bufferInView.buffer, bufferInView.currentPosition)
        else:
          none(SearchResult)

    if correspondPosition.isSome:
      let originalPosition = bufferInView.originalPosition(
        correspondPosition.get.line, correspondPosition.get.column)
      highlight.overwrite(ColorSegment(
        firstRow: originalPosition.line,
        firstColumn: originalPosition.column,
        lastRow: originalPosition.line,
        lastColumn: originalPosition.column,
        color: EditorColorPairIndex.parenPair))

proc highlightCurrentWordElsewhere(
  highlight: var Highlight,
  bufferInView: BufferInView,
  theme: ColorTheme,
  colorMode: ColorMode) =
    ## Add highlights the word on the cursor.
    ## Ignore symbols, spaces and the word on the cursor.

    proc isPunctOrSpace(r: Rune): bool {.inline.} =
       (r != '_' and isPunct(r)) or isSpace(r)

    proc isHighlightWord(line, word: Runes, position: int): bool {.inline.} =
      template beforeRune: Rune = line[position - 1]
      template nextRune: Rune = line[position + word.high + 1]

      # Check around the word.
      line[position .. position + word.high] == word and
      (position == 0 or isPunctOrSpace(beforeRune)) and
      (position + word.high == line.high or isPunctOrSpace(nextRune))

    proc isOnCursor(
      currentWordPosition, position: BufferPosition): bool {.inline.} =
        currentWordPosition == position

    let
      # Get the word on the cursor.
      currentPositionInView = bufferInView.currentPositionInView
      highlightWord = currentWord(
        bufferInView.buffer,
        currentPositionInView)

    if highlightWord.word.len == 0:
      # Empty line or ignore character.
      return

    let highlightWordPositionInView = BufferPosition(
      line: currentPositionInView.line,
      column: highlightWord.position)

    let results = searchAllOccurrence(bufferInView.buffer, highlightWord.word)
    for position in results:
      template line: Runes = bufferInView.buffer[position.line]

      if isHighlightWord(line, highlightWord.word, position.column) and
         not isOnCursor(highlightWordPositionInView, position):
           # Overwrite colors for the current word.
           let
             originalPosition = bufferInView.originalPosition(position)

             originalEditorColorPairIndex = highlight.getColorPair(
               originalPosition.line,
               originalPosition.column)
             originalColorPair =
               ColorThemeTable[theme][originalEditorColorPairIndex]
           discard EditorColorPairIndex.currentWord.initColorPair(
             colorMode,
             originalColorPair.foreground,
             ColorThemeTable[theme][EditorColorPairIndex.currentWord]
             .background)

           highlight.overwrite(
             ColorSegment(
               firstRow: originalPosition.line,
               firstColumn: originalPosition.column,
               lastRow: originalPosition.line,
               lastColumn: originalPosition.column + highlightWord.word.high,
               color: EditorColorPairIndex.currentWord))

proc highlightTrailingSpaces(
  highlight: var Highlight,
  bufferInView: BufferInView) =
    ## Add highlights for spaces at the end of lines. Ignore the current line.

    for i in 0 .. bufferInView.buffer.high:
      template line: Runes = bufferInView.buffer[i]

      if i != bufferInView.currentLineInView and line.len > 0:
        var countSpaces = 0
        for j in countdown(line.high, 0):
          if line[j] == ru' ': countSpaces.inc
          else: break

        if countSpaces > 0:
          let
            originalLine = bufferInView.originalLine(i)
            firstColumn = line.len - countSpaces
          highlight.overwrite(
            ColorSegment(
              firstRow: originalLine,
              firstColumn: firstColumn,
              lastRow: originalLine,
              lastColumn: line.high,
              color: EditorColorPairIndex.highlightTrailingSpaces))

proc highlightFullWidthSpace(
  highlight: var Highlight,
  windowNode: WindowNode,
  bufferInView: BufferInView) =
    ## Add highlights for all full width spaces.

    const FullWidthSpace = ru"　"
    let allOccurrence = searchAllOccurrence(bufferInView.buffer, FullWidthSpace)

    for pos in allOccurrence:
      let colorSegment = ColorSegment(
        firstRow: bufferInView.originalLineRange.first + pos.line,
        firstColumn: pos.column,
        lastRow: bufferInView.originalLineRange.first + pos.line,
        lastColumn: pos.column,
        color: EditorColorPairIndex.highlightFullWidthSpace)
      highlight.overwrite(colorSegment)

proc highlightSearchResults(
  highlight: var Highlight,
  bufferInView: BufferInView,
  keyword: Runes,
  settings: EditorSettings,
  isSearchHighlight: bool) =

    let
      allOccurrence = searchAllOccurrence(
        bufferInView.buffer,
        keyword,
        settings.ignorecase,
        settings.smartcase)

      color =
        if isSearchHighlight: EditorColorPairIndex.searchResult
        else: EditorColorPairIndex.replaceText

    for pos in allOccurrence:
      let colorSegment = ColorSegment(
        firstRow: bufferInView.originalLineRange.first + pos.line,
        firstColumn: pos.column,
        lastRow: bufferInView.originalLineRange.first + pos.line,
        lastColumn: pos.column + keyword.high,
        color: color)
      highlight.overwrite(colorSegment)

proc highlightSyntaxCheckerReuslts(
  highlight: var Highlight,
  bufferInView: BufferInView,
  syntaxErrors: seq[SyntaxError]) =
    ## Add highlights for syntax checker results.

    proc inRange(b: BufferInView, position: BufferPosition): bool {.inline.} =
      position.line >= b.originalLineRange.first and
      position.line <= b.originalLineRange.last

    for se in syntaxErrors:
      if inRange(bufferInView, se.position):
        let
          originalPosition = bufferInView.originalPosition(se.position)
          color =
            case se.messageType:
              of SyntaxCheckMessageType.info:
                EditorColorPairIndex.syntaxCheckInfo
              of SyntaxCheckMessageType.hint:
                EditorColorPairIndex.syntaxCheckHint
              of SyntaxCheckMessageType.warning:
                EditorColorPairIndex.syntaxCheckWarn
              of SyntaxCheckMessageType.error:
                EditorColorPairIndex.syntaxCheckErr
        highlight.overwrite(ColorSegment(
          firstRow: originalPosition.line,
          firstColumn: originalPosition.column,
          lastRow: originalPosition.line,
          lastColumn: originalPosition.column,
          color: color,
          attribute: Attribute.underline))

proc highlightGitConflicts(
  highlight: var Highlight,
  bufferInView: BufferInView) =
    ## Add highlights for git conflict marker lines.

    proc isHighlightLine(line: Runes): bool {.inline.} =
      line.isGitConflictStartMarker or
      line.isGitConflictDivideMarker or
      line.isGitConflictEndMarker

    for i in 0 .. bufferInView.buffer.high:
      if isHighlightLine(bufferInView.buffer[i]):
        let originalLine = bufferInView.originalLine(i)
        highlight.overwrite(ColorSegment(
          firstRow: originalLine,
          firstColumn: 0,
          lastRow: originalLine,
          lastColumn: bufferInView.buffer[i].high,
          color: EditorColorPairIndex.gitConflict,
          attribute: Attribute.normal))

proc updateViewHighlight*(
  highlight: var Highlight,
  bufStatus: BufferStatus,
  windowNode: var WindowNode,
  isSearchHighlight: bool,
  searchHistory: seq[Runes],
  settings: EditorSettings) =

    let bufferInView = initBufferInView(bufStatus, windowNode)

    if settings.highlight.currentWord:
      highlight.highlightCurrentWordElsewhere(
        bufferInView,
        settings.editorColorTheme,
        settings.colorMode)

    if isVisualMode(bufStatus.mode):
      highlight.highlightSelectedArea(bufStatus, windowNode.initBufferPosition)

    if settings.highlight.pairOfParen:
      highlight.highlightPairOfParen(bufferInView)

    if settings.highlight.trailingSpaces and bufStatus.isEditMode:
      highlight.highlightTrailingSpaces(bufferInView)

    if settings.highlight.fullWidthSpace:
      highlight.highlightFullWidthSpace(windowNode, bufferInView)

    if isSearchHighlight and searchHistory.len > 0:
      highlight.highlightSearchResults(
        bufferInView,
        searchHistory[^1],
        settings,
        isSearchHighlight)

    if bufStatus.syntaxCheckResults.len > 0:
      highlight.highlightSyntaxCheckerReuslts(
        bufferInView,
        bufStatus.syntaxCheckResults)

    highlight.highlightGitConflicts(bufferInView)
