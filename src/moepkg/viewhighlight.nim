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
       unicodeext, editorview, searchutils, settings, movement, ui, syntaxcheck,
       git, theme

proc initBufferPosition(
  n: WindowNode): BufferPosition {.inline.} =
    BufferPosition(line: n.currentLine, column: n.currentColumn)

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
  bufStatus: BufferStatus,
  windowNode: WindowNode) =

    if bufStatus.buffer.len == 0: return

    if bufStatus.buffer.len == 1 and bufStatus.buffer[0].len < 1: return

    if bufStatus.isExpandPosition(windowNode) or
       bufStatus.buffer[windowNode.currentLine].len < 1: return

    let
      currentPosition = windowNode.bufferPosition
      rune = bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn]

    if isOpenParen(rune):
      # Search only in the displayed range on the view.

      if windowNode.currentLine == bufStatus.buffer.high and
         windowNode.currentColumn == bufStatus.buffer[windowNode.currentLine].high:
           return

      let
        # TODO: Add bufStatus.next or gapbuffer.next and replace with it.
        firstPositionLine =
          if currentPosition.column + 1 < bufStatus.buffer[currentPosition.line].len:
            currentPosition.line
          else:
            currentPosition.line + 1
        firstPositionColumn =
          if firstPositionLine == currentPosition.line: currentPosition.column + 1
          else:
            if bufStatus.buffer[firstPositionLine].high >= 0:
              bufStatus.buffer[firstPositionLine].high
            else:
              0
        firstPosition = BufferPosition(
          line: firstPositionLine,
          column: firstPositionColumn)

        lastPositionLine =
          if windowNode.view.originalLine[^1] >= 0:
            windowNode.view.originalLine[^1]
          else:
            bufStatus.buffer.high
        lastPositionColumn =
          if bufStatus.buffer[lastPositionLine].high >= 0:
            bufStatus.buffer[lastPositionLine].high
          else:
            0
        lastPosition = BufferPosition(
          line: lastPositionLine,
          column: lastPositionColumn)

        range = BufferRange(
          first: firstPosition,
          last: lastPosition)

      let correspondParenPosition = bufStatus.matchingParenPair(range, rune)
      if correspondParenPosition.isSome:
        highlight.overwrite(ColorSegment(
          firstRow: correspondParenPosition.get.line,
          firstColumn: correspondParenPosition.get.column,
          lastRow: correspondParenPosition.get.line,
          lastColumn: correspondParenPosition.get.column,
          color: EditorColorPairIndex.parenPair))
    elif isCloseParen(rune):
      # Search only in the displayed range on the view.
      # TODO: Add bufStatus.prev or gapbuffer.prev and replace with it.
      let
        firstPositionLine =
          if currentPosition.column > 0: currentPosition.line
          elif currentPosition.line == 0: 0
          else: currentPosition.line - 1
        firstPositionColumn =
          if currentPosition.column == 0:
            0
          elif firstPositionLine == currentPosition.line:
            currentPosition.column - 1
          else:
            if bufStatus.buffer[firstPositionLine].high >= 0:
              bufStatus.buffer[firstPositionLine].high
            else:
              0
        firstPosition = BufferPosition(
          line: firstPositionLine,
          column: firstPositionColumn)

        lastPositionLine =
          if windowNode.view.originalLine[0] >= 0:
            windowNode.view.originalLine[0]
          else:
            0
        lastPosition = BufferPosition(
          line: lastPositionLine,
          column: 0)

        range = BufferRange(
          first: firstPosition,
          last: lastPosition)

      let correspondParenPosition = bufStatus.matchingParenPair(range, rune)
      if correspondParenPosition.isSome:
        highlight.overwrite(ColorSegment(
          firstRow: correspondParenPosition.get.line,
          firstColumn: correspondParenPosition.get.column,
          lastRow: correspondParenPosition.get.line,
          lastColumn: correspondParenPosition.get.column,
          color: EditorColorPairIndex.parenPair))

proc highlightOtherUsesCurrentWord(
  highlight: var Highlight,
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  theme: ColorTheme,
  colorMode: ColorMode) =
    # Highlighting other uses of the current word under the cursor

    let line = bufStatus.buffer[windowNode.currentLine]

    if line.len < 1 or
       windowNode.currentColumn > line.high or
       (line[windowNode.currentColumn] != '_' and
       unicodeext.isPunct(line[windowNode.currentColumn])) or
       line[windowNode.currentColumn].isSpace: return
    var
      startCol = windowNode.currentColumn
      endCol = windowNode.currentColumn

    # Set start col
    for i in countdown(windowNode.currentColumn - 1, 0):
      if (line[i] != '_' and unicodeext.isPunct(line[i])) or line[i].isSpace:
        break
      else: startCol.dec

    # Set end col
    for i in windowNode.currentColumn ..< line.len:
      if (line[i] != '_' and unicodeext.isPunct(line[i])) or line[i].isSpace:
        break
      else: endCol.inc

    let highlightWord = line[startCol ..< endCol]

    let
      range = windowNode.view.rangeOfOriginalLineInView
      startLine = range.first
      endLine =
        if bufStatus.buffer.len > range.last + 1: range.last + 2
        elif bufStatus.buffer.len > range.last: range.last + 1
        else: range.last

    # TODO: Remove isWordAtCursor
    proc isWordAtCursor(currentLine, i, j: int): bool =
      i == currentLine and (j >= startCol and j <= endCol)

    for i in startLine ..< endLine:
      let line = bufStatus.buffer[i]
      for j in 0 .. (line.len - highlightWord.len):
        let endCol = j + highlightWord.len
        if line[j ..< endCol] == highlightWord:
          ## TODO: Refactor
          if j == 0 or
             (j > 0 and
             ((line[j - 1] != '_' and
             unicodeext.isPunct(line[j - 1])) or
             line[j - 1].isSpace)):
            if (j == (line.len - highlightWord.len)) or
               ((line[j + highlightWord.len] != '_' and
               unicodeext.isPunct(line[j + highlightWord.len])) or
               line[j + highlightWord.len].isSpace):

              if not isWordAtCursor(windowNode.currentLine, i, j):
                # Do not highlight current word on the cursor.
                # Init colors for current words.
                let
                  originalEditorColorPairIndex = highlight.getColorPair(i, j)
                  originalColorPair = ColorThemeTable[theme][originalEditorColorPairIndex]
                # TODO: Return `Result` type.
                discard EditorColorPairIndex.currentWord.initColorPair(
                  colorMode,
                  originalColorPair.foreground,
                  ColorThemeTable[theme][EditorColorPairIndex.currentWord].background)

                highlight.overwrite(
                  ColorSegment(
                    firstRow: i,
                    firstColumn: j,
                    lastRow: i,
                    lastColumn: j + highlightWord.high,
                    color: EditorColorPairIndex.currentWord))

proc highlightTrailingSpaces(
  highlight: var Highlight,
  bufStatus: BufferStatus,
  windowNode: WindowNode) =

    # TODO: Fix condition
    if bufStatus.isConfigMode or
       bufStatus.isDebugMode: return

    let
      currentLine = windowNode.currentLine
      range = windowNode.view.rangeOfOriginalLineInView
      buffer = bufStatus.buffer
      startLine = range.first
      endLine =
        if buffer.len > range.last + 1: range.last + 2
        elif buffer.len > range.last: range.last + 1
        else: range.last

    var colorSegments: seq[ColorSegment] = @[]
    for i in startLine ..< endLine:
      let line = buffer[i]
      if line.len > 0 and i != currentLine:
        var countSpaces = 0
        for j in countdown(line.high, 0):
          if line[j] == ru' ': inc countSpaces
          else: break

        if countSpaces > 0:
          let firstColumn = line.len - countSpaces
          colorSegments.add(ColorSegment(
            firstRow: i,
            firstColumn: firstColumn,
            lastRow: i,
            lastColumn: line.high,
            color: EditorColorPairIndex.highlightTrailingSpaces))

    for colorSegment in colorSegments:
      highlight.overwrite(colorSegment)

proc highlightFullWidthSpace(
  highlight: var Highlight,
  windowNode: WindowNode,
  bufferInView: GapBuffer[Runes],
  range: Range) =

    const
      FullWidthSpace = ru"　"
      Ignorecase = false
      Smartcase = false
    let allOccurrence = bufferInView.searchAllOccurrence(
      FullWidthSpace,
      Ignorecase,
      Smartcase)

    for pos in allOccurrence:
      let colorSegment = ColorSegment(
        firstRow: range.first + pos.line,
        firstColumn: pos.column,
        lastRow: range.first + pos.line,
        lastColumn: pos.column,
        color: EditorColorPairIndex.highlightFullWidthSpace)
      highlight.overwrite(colorSegment)

proc highlightSearchResults(
  highlight: var Highlight,
  bufStatus: BufferStatus,
  bufferInView: GapBuffer[Runes],
  range: Range,
  keyword: Runes,
  settings: EditorSettings,
  isSearchHighlight: bool) =

  let
    ignorecase = settings.ignorecase
    smartcase = settings.smartcase
    allOccurrence = searchAllOccurrence(
      bufferInView,
      keyword,
      ignorecase,
      smartcase)

    color =
      if isSearchHighlight: EditorColorPairIndex.searchResult
      else: EditorColorPairIndex.replaceText

  for pos in allOccurrence:
    let colorSegment = ColorSegment(
      firstRow: range.first + pos.line,
      firstColumn: pos.column,
      lastRow: range.first + pos.line,
      lastColumn: pos.column + keyword.high,
      color: color)
    highlight.overwrite(colorSegment)

proc highlightSyntaxCheckerReuslts(
  highlight: var Highlight,
  range: Range,
  syntaxErrors: seq[SyntaxError]) =
    ## Display underline and highlight syntax errors.

    for se in syntaxErrors:
      if se.position.line >= range.first and se.position.line <= range.last:
        let color =
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
          firstRow: se.position.line,
          firstColumn: se.position.column,
          lastRow: se.position.line,
          lastColumn: se.position.column,
          color: color,
          attribute: Attribute.underline))

proc highlightGitConflicts(
  highlight: var Highlight,
  bufStatus: BufferStatus,
  range: Range) =
    ## Highlight Git conflict marker lines.

    for i in range.first .. min(range.last, bufStatus.buffer.high):
      if bufStatus.buffer[i].isGitConflictStartMarker or
         bufStatus.buffer[i].isGitConflictDivideMarker or
         bufStatus.buffer[i].isGitConflictEndMarker:
           highlight.overwrite(ColorSegment(
             firstRow: i,
             firstColumn: 0,
             lastRow: i,
             lastColumn: bufStatus.buffer[i].high,
             color: EditorColorPairIndex.gitConflict,
             attribute: Attribute.normal))

proc updateHighlight*(
  highlight: var Highlight,
  bufStatus: BufferStatus,
  windowNode: var WindowNode,
  isSearchHighlight: bool,
  searchHistory: seq[Runes],
  settings: EditorSettings,
  colorMode: ColorMode) =

    if settings.highlight.currentWord:
      highlight.highlightOtherUsesCurrentWord(
        bufStatus,
        windowNode,
        settings.editorColorTheme,
        colorMode)

    if isVisualMode(bufStatus.mode):
      highlight.highlightSelectedArea(bufStatus, windowNode.initBufferPosition)

    if settings.highlight.pairOfParen:
      highlight.highlightPairOfParen(bufStatus, windowNode)

    let
      range = windowNode.view.rangeOfOriginalLineInView
      startLine = range.first
      endLine =
        if bufStatus.buffer.len > range.last + 1: range.last + 2
        elif bufStatus.buffer.len > range.last: range.last + 1
        else: range.last

    var bufferInView = initGapBuffer[Runes]()
    for i in startLine ..< endLine: bufferInView.add(bufStatus.buffer[i])

    # highlight trailing spaces
    if settings.highlight.trailingSpaces:
      highlight.highlightTrailingSpaces(bufStatus, windowNode)

    # highlight full width space
    if settings.highlight.fullWidthSpace:
      highlight.highlightFullWidthSpace(windowNode, bufferInView, range)

    # highlight search results
    if isSearchHighlight and searchHistory.len > 0:
      highlight.highlightSearchResults(
        bufStatus,
        bufferInView,
        range,
        searchHistory[^1],
        settings,
        isSearchHighlight)

    if bufStatus.syntaxCheckResults.len > 0:
      # Highlight syntax chcker results
      highlight.highlightSyntaxCheckerReuslts(
        range,
        bufStatus.syntaxCheckResults)

    highlight.highlightGitConflicts(bufStatus, range)
