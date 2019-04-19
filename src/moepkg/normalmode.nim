import strutils, strformat, terminal, deques, sequtils
import editorstatus, editorview, cursor, ui, gapbuffer, unicodeext, highlight

proc jumpLine*(status: var EditorStatus, destination: int)
proc keyRight*(status: var EditorStatus)
proc keyLeft*(status: var EditorStatus)
proc keyUp*(status: var EditorStatus)
proc keyDown*(status: var EditorStatus)
proc replaceCurrentCharacter*(status: var EditorStatus, character: Rune)

import searchmode, replacemode


proc writeDebugInfo(status: var EditorStatus, str: string = "") =
  status.commandWindow.erase

  status.commandWindow.write(0, 0, ru"debuf info: ")
  status.commandWindow.append(fmt"currentLine: {status.bufStatus[status.currentBuffer].currentLine}, currentColumn: {status.bufStatus[status.currentBuffer].currentColumn}")
  status.commandWindow.append(fmt", cursor.y: {status.bufStatus[status.currentBuffer].cursor.y}, cursor.x: {status.bufStatus[status.currentBuffer].cursor.x}")
  status.commandWindow.append(fmt", {str}")

  status.commandWindow.refresh

proc keyLeft*(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].currentColumn == 0: return

  dec(status.bufStatus[status.currentBuffer].currentColumn)
  status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].currentColumn

proc keyRight*(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].currentColumn+1 >= status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentMainWindow].currentLine].len + (if status.bufStatus[status.currentBuffer].mode == Mode.insert: 1 else: 0): return

  inc(status.bufStatus[status.currentBuffer].currentColumn)
  status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].currentColumn

proc keyUp*(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].currentLine == 0: return

  dec(status.bufStatus[status.currentBuffer].currentLine)
  let maxColumn = status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len-1+(if status.bufStatus[status.currentBuffer].mode == Mode.insert: 1 else: 0)
  status.bufStatus[status.currentBuffer].currentColumn = min(status.bufStatus[status.currentBuffer].expandedColumn, maxColumn)
  if status.bufStatus[status.currentBuffer].currentColumn < 0: status.bufStatus[status.currentBuffer].currentColumn = 0

proc keyDown*(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].currentLine+1 == status.bufStatus[status.currentBuffer].buffer.len: return

  inc(status.bufStatus[status.currentBuffer].currentLine)
  let maxColumn = status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len-1+(if status.bufStatus[status.currentBuffer].mode == Mode.insert: 1 else: 0)
  status.bufStatus[status.currentBuffer].currentColumn = min(status.bufStatus[status.currentBuffer].expandedColumn, maxColumn)
  if status.bufStatus[status.currentBuffer].currentColumn < 0: status.bufStatus[status.currentBuffer].currentColumn = 0

proc moveToFirstNonBlankOfLine*(status: var EditorStatus) =
  status.bufStatus[status.currentBuffer].currentColumn = 0
  while status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine][status.bufStatus[status.currentBuffer].currentColumn] == ru' ': inc(status.bufStatus[status.currentBuffer].currentColumn)
  status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].currentColumn

proc moveToFirstOfLine*(status: var EditorStatus) =
  status.bufStatus[status.currentBuffer].currentColumn = 0
  status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].currentColumn

proc moveToLastOfLine*(status: var EditorStatus) =
  status.bufStatus[status.currentBuffer].currentColumn = max(status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len-1, 0)
  status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].currentColumn

proc moveToFirstOfPreviousLine(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].currentLine == 0: return
  keyUp(status)
  moveToFirstOfLine(status)

proc moveToFirstOfNextLine(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].currentLine+1 == status.bufStatus[status.currentBuffer].buffer.len: return
  keyDown(status)
  moveToFirstOfLine(status)

proc deleteCurrentCharacter*(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].currentLine >= status.bufStatus[status.currentBuffer].buffer.high and status.bufStatus[status.currentBuffer].currentColumn > status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].high: return 

  if status.bufStatus[status.currentBuffer].currentColumn == status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len:
    status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].insert(status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine + 1], status.bufStatus[status.currentBuffer].currentColumn)
    status.bufStatus[status.currentBuffer].buffer.delete(status.bufStatus[status.currentBuffer].currentLine + 1, status.bufStatus[status.currentBuffer].currentLine + 2)
  else:
    status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].delete(status.bufStatus[status.currentBuffer].currentColumn)
    if status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len > 0 and status.bufStatus[status.currentBuffer].currentColumn == status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len and status.bufStatus[status.currentBuffer].mode != Mode.insert:
      status.bufStatus[status.currentBuffer].currentColumn = status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len-1
      status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len-1

  status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, status.bufStatus[status.currentBuffer].view.originalLine[0])
  inc(status.bufStatus[status.currentBuffer].countChange)

proc jumpLine*(status: var EditorStatus, destination: int) =
  let currentLine = status.bufStatus[status.currentBuffer].currentLine
  status.bufStatus[status.currentBuffer].currentLine = destination
  status.bufStatus[status.currentBuffer].currentColumn = 0
  status.bufStatus[status.currentBuffer].expandedColumn = 0
  if not (status.bufStatus[status.currentBuffer].view.originalLine[0] <= destination and (status.bufStatus[status.currentBuffer].view.originalLine[status.bufStatus[status.currentBuffer].view.height - 1] == -1 or destination <= status.bufStatus[status.currentBuffer].view.originalLine[status.bufStatus[status.currentBuffer].view.height - 1])):
    var startOfPrintedLines = 0
    if destination > status.bufStatus[status.currentBuffer].buffer.len - 1 - status.mainWindow[status.currentMainWindow].height - 1:
      startOfPrintedLines = status.bufStatus[status.currentBuffer].buffer.len - 1 - status.mainWindow[status.currentMainWindow].height - 1
    else:
      startOfPrintedLines = max(destination - (currentLine - status.bufStatus[status.currentBuffer].view.originalLine[0]), 0)
    status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, startOfPrintedLines)

proc moveToFirstLine*(status: var EditorStatus) =
  jumpLine(status, 0)

proc moveToLastLine*(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].cmdLoop > 1:
    jumpLine(status, status.bufStatus[status.currentBuffer].cmdLoop - 1)
  else:
    jumpLine(status, status.bufStatus[status.currentBuffer].buffer.len-1)

proc pageUp*(status: var EditorStatus) =
  let destination = max(status.bufStatus[status.currentBuffer].currentLine - status.bufStatus[status.currentBuffer].view.height, 0)
  jumpLine(status, destination)

proc pageDown*(status: var EditorStatus) =
  let destination = min(status.bufStatus[status.currentBuffer].currentLine + status.bufStatus[status.currentBuffer].view.height, status.bufStatus[status.currentBuffer].buffer.len - 1)
  let currentLine = status.bufStatus[status.currentBuffer].currentLine
  status.bufStatus[status.currentBuffer].currentLine = destination
  status.bufStatus[status.currentBuffer].currentColumn = 0
  status.bufStatus[status.currentBuffer].expandedColumn = 0
  if not (status.bufStatus[status.currentBuffer].view.originalLine[0] <= destination and (status.bufStatus[status.currentBuffer].view.originalLine[status.bufStatus[status.currentBuffer].view.height - 1] == -1 or destination <= status.bufStatus[status.currentBuffer].view.originalLine[status.bufStatus[status.currentBuffer].view.height - 1])):
    let startOfPrintedLines = max(destination - (currentLine - status.bufStatus[status.currentBuffer].view.originalLine[0]), 0)
    status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, startOfPrintedLines)

proc moveToForwardWord*(status: var EditorStatus) =
  let
    startWith = if status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len == 0: ru'\n' else: status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine][status.bufStatus[status.currentBuffer].currentColumn]
    isSkipped = if unicodeext.isPunct(startWith): unicodeext.isPunct elif unicodeext.isAlpha(startWith): unicodeext.isAlpha elif unicodeext.isDigit(startWith): unicodeext.isDigit else: nil

  if isSkipped == nil:
    (status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn) = status.bufStatus[status.currentBuffer].buffer.next(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  else:
    while true:
      inc(status.bufStatus[status.currentBuffer].currentColumn)
      if status.bufStatus[status.currentBuffer].currentColumn >= status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len:
        inc(status.bufStatus[status.currentBuffer].currentLine)
        status.bufStatus[status.currentBuffer].currentColumn = 0
        break
      if not isSkipped(status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine][status.bufStatus[status.currentBuffer].currentColumn]): break

  while true:
    if status.bufStatus[status.currentBuffer].currentLine >= status.bufStatus[status.currentBuffer].buffer.len:
      status.bufStatus[status.currentBuffer].currentLine = status.bufStatus[status.currentBuffer].buffer.len-1
      status.bufStatus[status.currentBuffer].currentColumn = status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].buffer.high].high
      if status.bufStatus[status.currentBuffer].currentColumn == -1: status.bufStatus[status.currentBuffer].currentColumn = 0
      break

    if status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len == 0: break
    if status.bufStatus[status.currentBuffer].currentColumn == status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len:
      inc(status.bufStatus[status.currentBuffer].currentLine)
      status.bufStatus[status.currentBuffer].currentColumn = 0
      continue

    let curr = status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine][status.bufStatus[status.currentBuffer].currentColumn]
    if isPunct(curr) or isAlpha(curr) or isDigit(curr): break
    inc(status.bufStatus[status.currentBuffer].currentColumn)

  status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].currentColumn

proc moveToBackwardWord*(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].buffer.isFirst(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn): return

  while true:
    (status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn) = status.bufStatus[status.currentBuffer].buffer.prev(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    if status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len == 0 or status.bufStatus[status.currentBuffer].buffer.isFirst(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn): break

    let curr = status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine][status.bufStatus[status.currentBuffer].currentColumn]
    if unicodeext.isSpace(curr): continue

    if status.bufStatus[status.currentBuffer].currentColumn == 0: break

    let
      (backLine, backColumn) = status.bufStatus[status.currentBuffer].buffer.prev(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
      back = status.bufStatus[status.currentBuffer].buffer[backLine][backColumn]

    let
      currType = if isAlpha(curr): 1 elif isDigit(curr): 2 elif isPunct(curr): 3 else: 0
      backType = if isAlpha(back): 1 elif isDigit(back): 2 elif isPunct(back): 3 else: 0
    if currType != backType: break

  status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].currentColumn

proc moveToForwardEndOfWord*(status: var EditorStatus) =
  let
    startWith = if status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len == 0: ru'\n' else: status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine][status.bufStatus[status.currentBuffer].currentColumn]
    isSkipped = if unicodeext.isPunct(startWith): unicodeext.isPunct elif unicodeext.isAlpha(startWith): unicodeext.isAlpha elif unicodeext.isDigit(startWith): unicodeext.isDigit else: nil

  if isSkipped == nil:
    (status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn) = status.bufStatus[status.currentBuffer].buffer.next(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  else:
    while true:
      inc(status.bufStatus[status.currentBuffer].currentColumn)
      if status.bufStatus[status.currentBuffer].currentColumn == status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len - 1: break
      if status.bufStatus[status.currentBuffer].currentColumn >= status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len:
        inc(status.bufStatus[status.currentBuffer].currentLine)
        status.bufStatus[status.currentBuffer].currentColumn = 0
        break
      if not isSkipped(status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine][status.bufStatus[status.currentBuffer].currentColumn + 1]): break

  while true:
    if status.bufStatus[status.currentBuffer].currentLine >= status.bufStatus[status.currentBuffer].buffer.len:
      status.bufStatus[status.currentBuffer].currentLine = status.bufStatus[status.currentBuffer].buffer.len - 1
      status.bufStatus[status.currentBuffer].currentColumn = status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].buffer.high].high
      if status.bufStatus[status.currentBuffer].currentColumn == -1: status.bufStatus[status.currentBuffer].currentColumn = 0
      break

    if status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len == 0: break
    if status.bufStatus[status.currentBuffer].currentColumn == status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len:
      inc(status.bufStatus[status.currentBuffer].currentLine)
      status.bufStatus[status.currentBuffer].currentColumn = 0
      continue

    let curr = status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine][status.bufStatus[status.currentBuffer].currentColumn]
    if isPunct(curr) or isAlpha(curr) or isDigit(curr): break
    inc(status.bufStatus[status.currentBuffer].currentColumn)

  status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].currentColumn

proc openBlankLineBelow(status: var EditorStatus) =
  let indent = sequtils.repeat(ru' ', countRepeat(status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine], Whitespace, 0))

  status.bufStatus[status.currentBuffer].buffer.insert(indent, status.bufStatus[status.currentBuffer].currentLine+1)
  inc(status.bufStatus[status.currentBuffer].currentLine)
  status.bufStatus[status.currentBuffer].currentColumn = indent.len

  status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, status.bufStatus[status.currentBuffer].view.originalLine[0])
  inc(status.bufStatus[status.currentBuffer].countChange)

proc openBlankLineAbove(status: var EditorStatus) =
  let indent = sequtils.repeat(ru' ', countRepeat(status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine], Whitespace, 0))

  status.bufStatus[status.currentBuffer].buffer.insert(indent, status.bufStatus[status.currentBuffer].currentLine)
  status.bufStatus[status.currentBuffer].currentColumn = indent.len

  status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, status.bufStatus[status.currentBuffer].view.originalLine[0])
  inc(status.bufStatus[status.currentBuffer].countChange)

proc deleteLine(status: var EditorStatus, line: int) =
  status.bufStatus[status.currentBuffer].buffer.delete(line, line+1)

  if status.bufStatus[status.currentBuffer].buffer.len == 0: status.bufStatus[status.currentBuffer].buffer.insert(ru"", 0)

  if line < status.bufStatus[status.currentBuffer].currentLine: dec(status.bufStatus[status.currentBuffer].currentLine)
  if status.bufStatus[status.currentBuffer].currentLine >= status.bufStatus[status.currentBuffer].buffer.len: status.bufStatus[status.currentBuffer].currentLine = status.bufStatus[status.currentBuffer].buffer.high
  
  status.bufStatus[status.currentBuffer].currentColumn = 0
  status.bufStatus[status.currentBuffer].expandedColumn = 0

  status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, min(status.bufStatus[status.currentBuffer].view.originalLine[0], status.bufStatus[status.currentBuffer].buffer.high))
  inc(status.bufStatus[status.currentBuffer].countChange)

proc yankLines(status: var EditorStatus, first, last: int) =
  status.registers.yankedStr = @[]
  status.registers.yankedLines = @[]
  for i in first .. last: status.registers.yankedLines.add(status.bufStatus[status.currentBuffer].buffer[i])

  status.commandWindow.erase
  status.commandwindow.write(0, 0, fmt"{status.registers.yankedLines.len} line yanked")
  status.commandWindow.refresh

proc pasteLines(status: var EditorStatus) =
  for i in 0 ..< status.registers.yankedLines.len:
    status.bufStatus[status.currentBuffer].buffer.insert(status.registers.yankedLines[i], status.bufStatus[status.currentBuffer].currentLine + i + 1)

  status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, min(status.bufStatus[status.currentBuffer].view.originalLine[0], status.bufStatus[status.currentBuffer].buffer.high))
  inc(status.bufStatus[status.currentBuffer].countChange)

proc yankString(status: var EditorStatus, length: int) =
  status.registers.yankedLines = @[]
  status.registers.yankedStr = @[]
  for i in status.bufStatus[status.currentBuffer].currentColumn ..< length:
    status.registers.yankedStr.add(status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine][i])

  status.commandWindow.erase
  status.commandwindow.write(0, 0, fmt"{status.registers.yankedStr.len} character yanked")
  status.commandWindow.refresh

proc pasteString(status: var EditorStatus) =
  status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].insert(status.registers.yankedStr, status.bufStatus[status.currentBuffer].currentColumn)
  status.bufStatus[status.currentBuffer].currentColumn += status.registers.yankedStr.high

  status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, min(status.bufStatus[status.currentBuffer].view.originalLine[0], status.bufStatus[status.currentBuffer].buffer.high))
  inc(status.bufStatus[status.currentBuffer].countChange)

proc pasteAfterCursor(status: var EditorStatus) =
  if status.registers.yankedStr.len > 0:
    status.bufStatus[status.currentBuffer].currentColumn.inc
    pasteString(status)
  elif status.registers.yankedLines.len > 0:
    pasteLines(status)

proc pasteBeforeCursor(status: var EditorStatus) =
  status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, status.bufStatus[status.currentBuffer].view.originalLine[0])

  if status.registers.yankedLines.len > 0:
    pasteLines(status)
  elif status.registers.yankedStr.len > 0:
    pasteString(status)

proc replaceCurrentCharacter*(status: var EditorStatus, character: Rune) =
  status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine][status.bufStatus[status.currentBuffer].currentColumn] = character
  status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, status.bufStatus[status.currentBuffer].view.originalLine[0])
  inc(status.bufStatus[status.currentBuffer].countChange)

proc addIndent*(status: var EditorStatus) =
  status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].insert(newSeqWith(status.settings.tabStop, ru' '))

  status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, status.bufStatus[status.currentBuffer].view.originalLine[0])
  inc(status.bufStatus[status.currentBuffer].countChange)

proc deleteIndent*(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].buffer.len == 0: return

  if status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine][0] == ru' ':
    for i in 0 ..< status.settings.tabStop:
      if status.bufStatus[status.currentBuffer].buffer.len == 0 or status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine][0] != ru' ': break
      status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].delete(0, 0)
  status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, status.bufStatus[status.currentBuffer].view.originalLine[0])
  inc(status.bufStatus[status.currentBuffer].countChange)

proc joinLine(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].currentLine == status.bufStatus[status.currentBuffer].buffer.len - 1 or status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine + 1].len < 1:
    return

  status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].add(status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine + 1])
  status.bufStatus[status.currentBuffer].buffer.delete(status.bufStatus[status.currentBuffer].currentLine + 1, status.bufStatus[status.currentBuffer].currentLine + 2)

  status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, min(status.bufStatus[status.currentBuffer].view.originalLine[0], status.bufStatus[status.currentBuffer].buffer.high))
  inc(status.bufStatus[status.currentBuffer].countChange)

proc searchNextOccurrence(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[status.searchHistory.high]
  
  keyRight(status)
  let searchResult = searchBuffer(status, keyword)
  if searchResult.line > -1:
    jumpLine(status, searchResult.line)
    for column in 0 ..< searchResult.column:
      keyRight(status)
  elif searchResult.line == -1:
    keyLeft(status)

proc searchNextOccurrenceReversely(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[status.searchHistory.high]
  
  keyLeft(status)
  let searchResult = searchBufferReversely(status, keyword)
  if searchResult.line > -1:
    jumpLine(status, searchResult.line)
    for column in 0 ..< searchResult.column:
      keyRight(status)
  elif searchResult.line == -1:
    keyRight(status)

proc turnOffHighlighting*(status: var EditorStatus) =
  status.bufStatus[status.currentMainWindow].isHighlight = false
  status.updateHighlight

proc normalCommand(status: var EditorStatus, key: Rune) =
  if status.bufStatus[status.currentBuffer].cmdLoop == 0: status.bufStatus[status.currentBuffer].cmdLoop = 1
  
  if key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
    for i in 0 ..< status.bufStatus[status.currentBuffer].cmdLoop: keyLeft(status)
  elif key == ord('l') or isRightKey(key):
    for i in 0 ..< status.bufStatus[status.currentBuffer].cmdLoop: keyRight(status)
  elif key == ord('k') or isUpKey(key):
    for i in 0 ..< status.bufStatus[status.currentBuffer].cmdLoop: keyUp(status)
  elif key == ord('j') or isDownKey(key) or isEnterKey(key):
    for i in 0 ..< status.bufStatus[status.currentBuffer].cmdLoop: keyDown(status)
  elif key == ord('x') or isDcKey(key):
    yankString(status, min(status.bufStatus[status.currentBuffer].cmdLoop, status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len - status.bufStatus[status.currentBuffer].currentColumn))
    for i in 0 ..< min(status.bufStatus[status.currentBuffer].cmdLoop, status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len - status.bufStatus[status.currentBuffer].currentColumn): deleteCurrentCharacter(status)
  elif key == ord('^'):
    moveToFirstNonBlankOfLine(status)
  elif key == ord('0') or isHomeKey(key):
    moveToFirstOfLine(status)
  elif key == ord('$') or isEndKey(key):
    moveToLastOfLine(status)
  elif key == ord('-'):
    moveToFirstOfPreviousLine(status)
  elif key == ord('+'):
    moveToFirstOfNextLine(status)
  elif key == ord('g'):
    if getKey(status.mainWindow[status.currentMainWindow]) == ord('g'): moveToFirstLine(status)
  elif key == ord('G'):
    moveToLastLine(status)
  elif isPageUpkey(key):
    for i in 0 ..< status.bufStatus[status.currentBuffer].cmdLoop: pageUp(status)
  elif isPageDownKey(key):
    for i in 0 ..< status.bufStatus[status.currentBuffer].cmdLoop: pageDown(status)
  elif key == ord('w'):
    for i in 0 ..< status.bufStatus[status.currentBuffer].cmdLoop: moveToForwardWord(status)
  elif key == ord('b'):
    for i in 0 ..< status.bufStatus[status.currentBuffer].cmdLoop: moveToBackwardWord(status)
  elif key == ord('e'):
    for i in 0 ..< status.bufStatus[status.currentBuffer].cmdLoop: moveToForwardEndOfWord(status)
  elif key == ord('o'):
    for i in 0 ..< status.bufStatus[status.currentBuffer].cmdLoop: openBlankLineBelow(status)
    status.updateHighlight
    status.changeMode(Mode.insert)
  elif key == ord('O'):
    for i in 0 ..< status.bufStatus[status.currentBuffer].cmdLoop: openBlankLineAbove(status)
    status.updateHighlight
    status.changeMode(Mode.insert)
  elif key == ord('d'):
    if getKey(status.mainWindow[status.currentMainWindow]) == ord('d'):
      yankLines(status, status.bufStatus[status.currentBuffer].currentLine, min(status.bufStatus[status.currentBuffer].currentLine+status.bufStatus[status.currentBuffer].cmdLoop - 1, status.bufStatus[status.currentBuffer].buffer.high))
      for i in 0 ..< min(status.bufStatus[status.currentBuffer].cmdLoop, status.bufStatus[status.currentBuffer].buffer.len-status.bufStatus[status.currentBuffer].currentLine): deleteLine(status, status.bufStatus[status.currentBuffer].currentLine)
  elif key == ord('y'):
    if getkey(status.mainWindow[status.currentMainWindow]) == ord('y'): yankLines(status, status.bufStatus[status.currentBuffer].currentLine, min(status.bufStatus[status.currentBuffer].currentLine + status.bufStatus[status.currentBuffer].cmdLoop - 1, status.bufStatus[status.currentBuffer].buffer.high))
  elif key == ord('p'):
    pasteAfterCursor(status)
  elif key == ord('P'):
    pasteBeforeCursor(status)
  elif key == ord('>'):
    for i in 0 ..< status.bufStatus[status.currentBuffer].cmdLoop: addIndent(status)
  elif key == ord('<'):
    for i in 0 ..< status.bufStatus[status.currentBuffer].cmdLoop: deleteIndent(status)
  elif key == ord('J'):
    joinLine(status)
  elif key == ord('r'):
    if status.bufStatus[status.currentBuffer].cmdLoop > status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len - status.bufStatus[status.currentBuffer].currentColumn: return

    let ch = getKey(status.mainWindow[status.currentMainWindow])
    for i in 0 ..< status.bufStatus[status.currentBuffer].cmdLoop:
      if i > 0:
        inc(status.bufStatus[status.currentBuffer].currentColumn)
        status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].currentColumn
      replaceCurrentCharacter(status, ch)
  elif key == ord('n'):
    searchNextOccurrence(status)
  elif key == ord('N'):
    searchNextOccurrenceReversely(status)
  elif key == ord('R'):
    status.changeMode(Mode.replace)
  elif key == ord('i'):
    status.changeMode(Mode.insert)
  elif key == ord('I'):
    status.bufStatus[status.currentBuffer].currentColumn = 0
    status.changeMode(Mode.insert)
  elif key == ord('v'):
    status.changeMode(Mode.visual)
  elif key == ord('a'):
    if status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len > 0: inc(status.bufStatus[status.currentBuffer].currentColumn)
    status.changeMode(Mode.insert)
  elif key == ord('A'):
    status.bufStatus[status.currentBuffer].currentColumn = status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len
    status.changeMode(Mode.insert)
  elif isEscKey(key):
    let key = getKey(status.mainWindow[status.currentMainWindow])
    if isEscKey(key): turnOffHighlighting(status)
  else:
    discard

proc normalMode*(status: var EditorStatus) =
  status.bufStatus[status.currentBuffer].cmdLoop = 0
  status.resize(terminalHeight(), terminalWidth())
  var countChange = 0

  changeCursorType(status.settings.normalModeCursor)

  while status.bufStatus[status.currentBuffer].mode == Mode.normal:
    if status.bufStatus[status.currentBuffer].countChange > countChange:
      status.updateHighlight
      countChange = status.bufStatus[status.currentBuffer].countChange

    status.update

    let key = getKey(status.mainWindow[status.currentMainWindow])

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif key == ord('/'):
      status.changeMode(Mode.search)
    elif key == ord(':'):
      status.changeMode(Mode.ex)
    elif isDigit(key):
      let num = ($key)[0]
      if status.bufStatus[status.currentBuffer].cmdLoop == 0 and num == '0':
        normalCommand(status, key)
        continue

      status.bufStatus[status.currentBuffer].cmdLoop *= 10
      status.bufStatus[status.currentBuffer].cmdLoop += ord(num)-ord('0')
      status.bufStatus[status.currentBuffer].cmdLoop = min(100000, status.bufStatus[status.currentBuffer].cmdLoop)
      continue
    else:
      normalCommand(status, key)
      status.bufStatus[status.currentBuffer].cmdLoop = 0
