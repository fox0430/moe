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

import std/[deques, options]
import editorview, gapbuffer, unicodeext, windownode, bufferstatus,
       independentutils, searchutils

template currentLineLen: int = bufStatus.buffer[windowNode.currentLine].len

proc isExpandPosition*(
  bufStatus: BufferStatus,
  windowNode: WindowNode): bool {.inline.} =
    ## Return true if currentColumn is line.high + 1.

    windowNode.currentColumn ==
      bufStatus.buffer[windowNode.currentLine].high + 1

proc keyLeft*(windowNode: var WindowNode) =
  if windowNode.currentColumn == 0: return

  dec(windowNode.currentColumn)
  windowNode.expandedColumn = windowNode.currentColumn

proc keyRight*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  let maxColumn = currentLineLen + (if bufStatus.isExpandableMode: 1 else: 0)
  if windowNode.currentColumn + 1 >= maxColumn: return

  inc(windowNode.currentColumn)
  windowNode.expandedColumn = windowNode.currentColumn

proc keyUp*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  if windowNode.currentLine == 0: return

  dec(windowNode.currentLine)

  let maxColumn = currentLineLen + (if bufStatus.isExpandableMode:0 else: -1)
  windowNode.currentColumn = min(windowNode.expandedColumn, maxColumn)

  if windowNode.currentColumn < 0: windowNode.currentColumn = 0

proc keyDown*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  if windowNode.currentLine + 1 == bufStatus.buffer.len: return

  inc(windowNode.currentLine)

  let maxColumn = currentLineLen + (if bufStatus.isExpandableMode: 0 else: -1)
  windowNode.currentColumn = min(windowNode.expandedColumn, maxColumn)

  if windowNode.currentColumn < 0: windowNode.currentColumn = 0

proc getFirstNonBlankOfLine*(
  bufStatus: BufferStatus,
  windowNode: WindowNode): int =

    if currentLineLen == 0: return 0

    let lineLen = currentLineLen
    while bufStatus.buffer[windowNode.currentLine][result] == ru' ':
      inc(result)
      if result == lineLen: return -1

proc getFirstNonBlankOfLineOrLastColumn*(
  bufStatus: BufferStatus,
  windowNode: WindowNode): int =

    result = bufStatus.getFirstNonBlankOfLine(windowNode)
    if result == -1:
      return currentLineLen - 1

proc getFirstNonBlankOfLineOrFirstColumn*(
  bufStatus  : BufferStatus,
  windowNode : WindowNode): int =

    result = bufStatus.getFirstNonBlankOfLine(windowNode)
    if result == -1: return 0

proc getLastNonBlankOfLine*(
  bufStatus: BufferStatus,
  windowNode: WindowNode): Natural =

    if currentLineLen == 0: return 0

    result = currentLineLen - 1
    while bufStatus.buffer[windowNode.currentLine][result] == ru' ': dec(result)

proc moveToFirstNonBlankOfLine*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode) =

    windowNode.currentColumn = bufStatus.getFirstNonBlankOfLineOrLastColumn(
      windowNode)
    windowNode.expandedColumn = windowNode.currentColumn

proc moveToLastNonBlankOfLine*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode) =

    windowNode.currentColumn = bufStatus.getLastNonBlankOfLine(windowNode)
    windowNode.expandedColumn = windowNode.currentColumn

proc moveToFirstOfLine*(windowNode: var WindowNode) =
  windowNode.currentColumn = 0
  windowNode.expandedColumn = windowNode.currentColumn

proc moveToLastOfLine*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode) =

    let destination =
      if bufStatus.isInsertMode or bufStatus.isVisualMode:
        bufStatus.buffer[windowNode.currentLine].len
      else:
        bufStatus.buffer[windowNode.currentLine].high

    windowNode.currentColumn = max(destination, 0)
    windowNode.expandedColumn = windowNode.currentColumn

proc moveToFirstOfPreviousLine*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode) =

    if windowNode.currentLine == 0: return
    bufStatus.keyUp(windowNode)
    windowNode.moveToFirstOfLine

proc moveToFirstOfNextLine*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode) =

    if windowNode.currentLine + 1 == bufStatus.buffer.len: return
    bufStatus.keyDown(windowNode)
    windowNode.moveToFirstOfLine

proc jumpLine*(
  bufStatus: BufferStatus,
  windowNode: var WindowNode,
  destination: int) =

    let
      currentLine = windowNode.currentLine
      view = windowNode.view

    windowNode.currentLine = destination
    windowNode.currentColumn = 0
    windowNode.expandedColumn = 0

    if not (view.originalLine[0] <= destination and
       (view.originalLine[view.height - 1] == -1 or
       destination <= view.originalLine[view.height - 1])):
      var startOfPrintedLines = 0
      if destination > bufStatus.buffer.high - windowNode.getHeight - 1:
        startOfPrintedLines = bufStatus.buffer.high - windowNode.getHeight - 1
      else:
        startOfPrintedLines = max(
          destination - (currentLine - windowNode.view.originalLine[0]),
          0)

      windowNode.view.reload(bufStatus.buffer, startOfPrintedLines)

proc findNextBlankLine*(bufStatus: BufferStatus, currentLine: int): int =
  result = -1

  if currentLine < bufStatus.buffer.len - 1:
    var currentLineStartedBlank = bufStatus.buffer[currentLine].len == 0
    for i in countup(currentLine + 1, bufStatus.buffer.len - 1):
      if bufStatus.buffer[i].len == 0:
        if not currentLineStartedBlank:
          return i
      elif currentLineStartedBlank:
        currentLineStartedBlank = false

  return -1

proc findPreviousBlankLine*(bufStatus: BufferStatus, currentLine: int): int =
  result = -1

  if currentLine > 0:
    var currentLineStartedBlank = bufStatus.buffer[currentLine].len == 0
    for i in countdown(currentLine - 1, 0):
      if bufStatus.buffer[i].len == 0:
        if not currentLineStartedBlank:
          return i
      elif currentLineStartedBlank:
        currentLineStartedBlank = false

  return -1

proc moveToNextBlankLine*(bufStatus: BufferStatus, windowNode: var WindowNode) =
  let nextBlankLine = bufStatus.findNextBlankLine(windowNode.currentLine)
  if nextBlankLine >= 0: bufStatus.jumpLine(windowNode, nextBlankLine)

proc moveToPreviousBlankLine*(
  bufStatus: BufferStatus,
  windowNode: var WindowNode) =

    let
      currentLine = windowNode.currentLine
      previousBlankLine = bufStatus.findPreviousBlankLine(currentLine)
    if previousBlankLine >= 0: bufStatus.jumpLine(windowNode, previousBlankLine)

proc moveToFirstLine*(
  bufStatus: BufferStatus,
  windowNode: var WindowNode) {.inline.} =

    const Direction = 0
    bufStatus.jumpLine(windowNode, Direction)

proc moveToLastLine*(bufStatus: BufferStatus, windowNode: var WindowNode) =
  if bufStatus.cmdLoop > 1:
    bufStatus.jumpLine(windowNode, bufStatus.cmdLoop - 1)
  else: bufStatus.jumpLine(windowNode, bufStatus.buffer.high)

proc moveToForwardWord*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode) =

    let
      currentLine = windowNode.currentLine
      currentColumn = windowNode.currentColumn
      startWith =
        if bufStatus.buffer[currentLine].len == 0: ru'\n'
        else: bufStatus.buffer[currentLine][currentColumn]
      isSkipped =
        if unicodeext.isPunct(startWith): unicodeext.isPunct
        elif unicodeext.isAlpha(startWith): unicodeext.isAlpha
        elif unicodeext.isDigit(startWith): unicodeext.isDigit
        else: nil

    if isSkipped == nil:
      (windowNode.currentLine, windowNode.currentColumn) = bufStatus.buffer.next(
        currentLine,
        currentColumn)
    else:
      while true:
        inc(windowNode.currentColumn)
        if windowNode.currentColumn >= bufStatus.buffer[windowNode.currentLine].len:
          inc(windowNode.currentLine)
          windowNode.currentColumn = 0
          break
        if not isSkipped(bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn]): break

    while true:
      if windowNode.currentLine >= bufStatus.buffer.len:
        windowNode.currentLine = bufStatus.buffer.len-1
        windowNode.currentColumn = bufStatus.buffer[bufStatus.buffer.high].high
        if windowNode.currentColumn == -1: windowNode.currentColumn = 0
        break

      if bufStatus.buffer[windowNode.currentLine].len == 0: break
      if windowNode.currentColumn == bufStatus.buffer[windowNode.currentLine].len:
        inc(windowNode.currentLine)
        windowNode.currentColumn = 0
        continue

      let curr = bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn]
      if isPunct(curr) or isAlpha(curr) or isDigit(curr): break
      inc(windowNode.currentColumn)

    windowNode.expandedColumn = windowNode.currentColumn

proc moveToBackwardWord*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode) =

    if bufStatus.buffer.isFirst(
      windowNode.currentLine,
      windowNode.currentColumn): return

    while true:
      (windowNode.currentLine, windowNode.currentColumn) = bufStatus.buffer.prev(
        windowNode.currentLine,
        windowNode.currentColumn)

      let
        currentLine = windowNode.currentLine
        currentColumn = windowNode.currentColumn

      if currentLineLen == 0 or
         bufStatus.buffer.isFirst(currentLine, currentColumn): break

      let curr = bufStatus.buffer[currentLine][currentColumn]
      if unicodeext.isSpace(curr): continue

      if windowNode.currentColumn == 0: break

      let
        (backLine, backColumn) = bufStatus.buffer.prev(currentLine, currentColumn)
        back = bufStatus.buffer[backLine][backColumn]

      let
        currType = if isAlpha(curr): 1 elif isDigit(curr): 2 elif isPunct(curr): 3 else: 0
        backType = if isAlpha(back): 1 elif isDigit(back): 2 elif isPunct(back): 3 else: 0
      if currType != backType: break

    windowNode.expandedColumn = windowNode.currentColumn

proc moveToForwardEndOfWord*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode) =

    let
      currentLine = windowNode.currentLine
      currentColumn = windowNode.currentColumn
      startWith =
        if bufStatus.buffer[currentLine].len == 0: ru'\n'
        else: bufStatus.buffer[currentLine][currentColumn]
      isSkipped =
        if unicodeext.isPunct(startWith): unicodeext.isPunct
        elif unicodeext.isAlpha(startWith): unicodeext.isAlpha
        elif unicodeext.isDigit(startWith): unicodeext.isDigit
        else: nil

    if isSkipped == nil:
      (windowNode.currentLine, windowNode.currentColumn) = bufStatus.buffer.next(
        currentLine,
        currentColumn)

    else:
      while true:
        inc(windowNode.currentColumn)
        if windowNode.currentColumn == currentLineLen - 1: break
        if windowNode.currentColumn >= currentLineLen:
          inc(windowNode.currentLine)
          windowNode.currentColumn = 0
          break
        let r = bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn + 1]
        if not isSkipped(r): break

    while true:
      if windowNode.currentLine >= bufStatus.buffer.len:
        windowNode.currentLine = bufStatus.buffer.len - 1
        windowNode.currentColumn = bufStatus.buffer[bufStatus.buffer.high].high
        if windowNode.currentColumn == -1: windowNode.currentColumn = 0
        break

      if bufStatus.buffer[windowNode.currentLine].len == 0: break
      if windowNode.currentColumn == currentLineLen:
        inc(windowNode.currentLine)
        windowNode.currentColumn = 0
        continue

      let curr = bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn]
      if isPunct(curr) or isAlpha(curr) or isDigit(curr): break
      inc(windowNode.currentColumn)

    windowNode.expandedColumn = windowNode.currentColumn

proc moveToTopOfScreen*(bufStatus: BufferStatus, windowNode: var WindowNode) =
  ## Move to the top line of the screen.

  if windowNode.currentLine > windowNode.view.originalLine[0]:
    windowNode.currentLine = windowNode.view.originalLine[0]

    if windowNode.currentColumn > 0 and
       windowNode.currentColumn > bufStatus.buffer[windowNode.currentLine].high:
         windowNode.currentColumn = bufStatus.buffer[windowNode.currentLine].high

proc moveToCenterOfScreen*(bufStatus: BufferStatus, windowNode: var WindowNode) =
  ## Move to the center line of the screen.

  if (bufStatus.buffer.high - windowNode.currentLine) < windowNode.view.height - 1:
    # Move to the middle of visible lines if less than a view bottom.
    let
      medInVisible = int((bufStatus.buffer.high - windowNode.view.originalLine[0]) / 2)
    windowNode.currentLine = windowNode.view.originalLine[0] + medInVisible
  else:
    let
      medOnScreen = int(windowNode.view.originalLine.len / 2)
      dest = windowNode.view.originalLine[medOnScreen]
    if dest > -1 and bufStatus.buffer.high >= dest:
      windowNode.currentLine = dest

proc moveToBottomOfScreen*(bufStatus: BufferStatus, windowNode: var WindowNode) =
  ## Move to the bottom line of the screen.

  if (bufStatus.buffer.high - windowNode.currentLine) < windowNode.view.height - 1:
    # Move to the bottom of visible lines if less than a view bottom.
    let bottomInVisalbe = bufStatus.buffer.high - windowNode.view.originalLine[0]
    windowNode.currentLine = windowNode.view.originalLine[0] + bottomInVisalbe
  else:
    windowNode.currentLine = windowNode.view.originalLine[^1]
    if windowNode.currentColumn > bufStatus.buffer[windowNode.currentLine].high:
      windowNode.currentColumn = bufStatus.buffer[windowNode.currentLine].high

proc scrollScreenTop*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode) {.inline.} =

    windowNode.view.reload(
      bufStatus.buffer,
      windowNode.view.originalLine[windowNode.cursor.y])

proc scrollScreenCenter*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode) =

    if windowNode.currentLine > int(windowNode.view.height / 2):
      if windowNode.cursor.y > int(windowNode.view.height / 2):
        let startOfPrintedLines = windowNode.cursor.y - int(windowNode.view.height / 2)
        windowNode.view.reload(
          bufStatus.buffer,
          windowNode.view.originalLine[startOfPrintedLines])
      else:
        let numOfTime = int(windowNode.view.height / 2) - windowNode.cursor.y
        for i in 0 ..< numOfTime: scrollUp(windowNode.view, bufStatus.buffer)

proc scrollScreenBottom*(bufStatus: var BufferStatus, windowNode: WindowNode) =
  if windowNode.currentLine > windowNode.view.height:
    let numOfTime = windowNode.view.height - windowNode.cursor.y - 2
    for i in 0 ..< numOfTime: windowNode.view.scrollUp(bufStatus.buffer)

proc moveToPairOfParen*(
  bufStatus: BufferStatus,
  windowNode: var WindowNode) =
    ## Move to matching pair of paren. Do nothing If no matching pair exists.

    if bufStatus.isExpandPosition(windowNode): return

    let currentPosition = windowNode.bufferPosition

    let correspondParenPosition = bufStatus.matchingParenPair(currentPosition)
    if correspondParenPosition.isSome:
      windowNode.currentLine = correspondParenPosition.get.line
      windowNode.currentColumn = correspondParenPosition.get.column

proc jumpToSearchForwardResults*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  keyword: Runes,
  isIgnorecase, isSmartcase: bool) =

    let searchResult = bufStatus.searchBuffer(
      windowNode,
      keyword,
      isIgnorecase,
      isSmartcase)

    if searchResult.isSome:
      bufStatus.jumpLine(windowNode, searchResult.get.line)
      for column in 0 ..< searchResult.get.column:
        bufStatus.keyRight(windowNode)

proc jumpToSearchBackwordResults*(
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  keyword: Runes,
  isIgnorecase, isSmartcase: bool) =

    let searchResult = bufStatus.searchBufferReversely(
      windowNode,
      keyword,
      isIgnorecase,
      isSmartcase)

    if searchResult.isSome:
      bufStatus.jumpLine(windowNode, searchResult.get.line)
      for column in 0 ..< searchResult.get.column:
        bufStatus.keyRight(windowNode)
