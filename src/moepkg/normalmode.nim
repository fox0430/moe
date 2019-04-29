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
  let
    currentColumn = status.bufStatus[status.currentBuffer].currentColumn
    currentLine = status.bufStatus[status.currentBuffer].currentLine
    currentMode = status.bufStatus[status.currentBuffer].mode

  if currentColumn + 1 >= status.bufStatus[status.currentBuffer].buffer[currentLine].len + (if currentMode == Mode.insert: 1 else: 0): return

  inc(status.bufStatus[status.currentBuffer].currentColumn)
  status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].currentColumn

proc keyUp*(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].currentLine == 0: return

  dec(status.bufStatus[status.currentBuffer].currentLine)
  let
    currentLine = status.bufStatus[status.currentBuffer].currentLine
    maxColumn = status.bufStatus[status.currentBuffer].buffer[currentLine].len - 1 + (if status.bufStatus[status.currentBuffer].mode == Mode.insert: 1 else: 0)

  status.bufStatus[status.currentBuffer].currentColumn = min(status.bufStatus[status.currentBuffer].expandedColumn, maxColumn)
  if status.bufStatus[status.currentBuffer].currentColumn < 0: status.bufStatus[status.currentBuffer].currentColumn = 0

proc keyDown*(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].currentLine+1 == status.bufStatus[status.currentBuffer].buffer.len: return

  inc(status.bufStatus[status.currentBuffer].currentLine)
  let
    currentLine = status.bufStatus[status.currentBuffer].currentLine
    maxColumn = status.bufStatus[status.currentBuffer].buffer[currentLine].len - 1 + (if status.bufStatus[status.currentBuffer].mode == Mode.insert: 1 else: 0)

  status.bufStatus[status.currentBuffer].currentColumn = min(status.bufStatus[status.currentBuffer].expandedColumn, maxColumn)
  if status.bufStatus[status.currentBuffer].currentColumn < 0: status.bufStatus[status.currentBuffer].currentColumn = 0

proc moveToFirstNonBlankOfLine*(status: var EditorStatus) =
  status.bufStatus[status.currentBuffer].currentColumn = 0
  while status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine][status.bufStatus[status.currentBuffer].currentColumn] == ru' ':
    inc(status.bufStatus[status.currentBuffer].currentColumn)
  status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].currentColumn

proc moveToFirstOfLine*(status: var EditorStatus) =
  status.bufStatus[status.currentBuffer].currentColumn = 0
  status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].currentColumn

proc moveToLastOfLine*(status: var EditorStatus) =
  status.bufStatus[status.currentBuffer].currentColumn = max(status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len - 1, 0)
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
  let
    currentLine = status.bufStatus[status.currentBuffer].currentLine
    currentColumn = status.bufStatus[status.currentBuffer].currentColumn
    currentMode = status.bufStatus[status.currentBuffer].mode
    index = status.currentBuffer

  if currentLine >= status.bufStatus[index].buffer.high and currentColumn > status.bufStatus[index].buffer[currentLine].high: return 

  if currentColumn == status.bufStatus[index].buffer[currentLine].len:
    status.bufStatus[index].buffer[currentLine].insert(status.bufStatus[index].buffer[currentLine + 1], currentColumn)
    status.bufStatus[index].buffer.delete(currentLine + 1, currentLine + 2)
  else:
    status.bufStatus[index].buffer[currentLine].delete(currentColumn)
    if status.bufStatus[index].buffer[currentLine].len > 0 and currentColumn == status.bufStatus[index].buffer[currentLine].len and currentMode != Mode.insert:
      status.bufStatus[index].currentColumn = status.bufStatus[index].buffer[status.bufStatus[index].currentLine].len-1
      status.bufStatus[index].expandedColumn = status.bufStatus[index].buffer[status.bufStatus[index].currentLine].len-1

  status.bufStatus[index].view.reload(status.bufStatus[index].buffer, status.bufStatus[index].view.originalLine[0])
  inc(status.bufStatus[index].countChange)

proc jumpLine*(status: var EditorStatus, destination: int) =
  let
    currentLine = status.bufStatus[status.currentBuffer].currentLine
    view = status.bufStatus[status.currentBuffer].view
  status.bufStatus[status.currentBuffer].currentLine = destination
  status.bufStatus[status.currentBuffer].currentColumn = 0
  status.bufStatus[status.currentBuffer].expandedColumn = 0

  if not (view.originalLine[0] <= destination and (view.originalLine[view.height - 1] == -1 or destination <= view.originalLine[view.height - 1])):
    var startOfPrintedLines = 0
    if destination > status.bufStatus[status.currentBuffer].buffer.len - 1 - status.mainWindowInfo[status.currentMainWindow].window.height - 1:
      startOfPrintedLines = status.bufStatus[status.currentBuffer].buffer.len - 1 - status.mainWindowInfo[status.currentMainWindow].window.height - 1
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
  let
    destination = min(status.bufStatus[status.currentBuffer].currentLine + status.bufStatus[status.currentBuffer].view.height, status.bufStatus[status.currentBuffer].buffer.len - 1)
    currentLine = status.bufStatus[status.currentBuffer].currentLine
    view = status.bufStatus[status.currentBuffer].view
  status.bufStatus[status.currentBuffer].currentLine = destination
  status.bufStatus[status.currentBuffer].currentColumn = 0
  status.bufStatus[status.currentBuffer].expandedColumn = 0

  if not (view.originalLine[0] <= destination and (view.originalLine[view.height - 1] == -1 or destination <= view.originalLine[view.height - 1])):
    let startOfPrintedLines = max(destination - (currentLine - status.bufStatus[status.currentBuffer].view.originalLine[0]), 0)
    status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, startOfPrintedLines)

proc moveToForwardWord*(status: var EditorStatus) =
  let
    currentLine = status.bufStatus[status.currentBuffer].currentLine
    currentColumn = status.bufStatus[status.currentBuffer].currentColumn
    index = status.currentBuffer
    startWith = if status.bufStatus[index].buffer[currentLine].len == 0: ru'\n' else: status.bufStatus[index].buffer[currentLine][currentColumn]
    isSkipped = if unicodeext.isPunct(startWith): unicodeext.isPunct elif unicodeext.isAlpha(startWith): unicodeext.isAlpha elif unicodeext.isDigit(startWith): unicodeext.isDigit else: nil

  if isSkipped == nil:
    (status.bufStatus[index].currentLine, status.bufStatus[index].currentColumn) = status.bufStatus[index].buffer.next(currentLine, currentColumn)
  else:
    while true:
      inc(status.bufStatus[status.currentBuffer].currentColumn)
      if status.bufStatus[index].currentColumn >= status.bufStatus[index].buffer[status.bufStatus[index].currentLine].len:
        inc(status.bufStatus[index].currentLine)
        status.bufStatus[index].currentColumn = 0
        break
      if not isSkipped(status.bufStatus[index].buffer[status.bufStatus[index].currentLine][status.bufStatus[index].currentColumn]): break

  while true:
    if status.bufStatus[index].currentLine >= status.bufStatus[index].buffer.len:
      status.bufStatus[index].currentLine = status.bufStatus[index].buffer.len-1
      status.bufStatus[index].currentColumn = status.bufStatus[index].buffer[status.bufStatus[index].buffer.high].high
      if status.bufStatus[index].currentColumn == -1: status.bufStatus[index].currentColumn = 0
      break

    if status.bufStatus[index].buffer[status.bufStatus[index].currentLine].len == 0: break
    if status.bufStatus[index].currentColumn == status.bufStatus[index].buffer[status.bufStatus[index].currentLine].len:
      inc(status.bufStatus[index].currentLine)
      status.bufStatus[index].currentColumn = 0
      continue

    let curr = status.bufStatus[index].buffer[status.bufStatus[index].currentLine][status.bufStatus[index].currentColumn]
    if isPunct(curr) or isAlpha(curr) or isDigit(curr): break
    inc(status.bufStatus[index].currentColumn)

  status.bufStatus[index].expandedColumn = status.bufStatus[index].currentColumn

proc moveToBackwardWord*(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].buffer.isFirst(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn): return

  let index = status.currentBuffer

  while true:
    (status.bufStatus[index].currentLine, status.bufStatus[index].currentColumn) = status.bufStatus[index].buffer.prev(status.bufStatus[index].currentLine, status.bufStatus[index].currentColumn)
    let
      currentLine = status.bufStatus[index].currentLine
      currentColumn = status.bufStatus[index].currentColumn
      
    if status.bufStatus[index].buffer[currentLine].len == 0 or status.bufStatus[index].buffer.isFirst(currentLine, currentColumn): break

    let curr = status.bufStatus[index].buffer[currentLine][currentColumn]
    if unicodeext.isSpace(curr): continue

    if status.bufStatus[status.currentBuffer].currentColumn == 0: break

    let
      (backLine, backColumn) = status.bufStatus[index].buffer.prev(currentLine, currentColumn)
      back = status.bufStatus[status.currentBuffer].buffer[backLine][backColumn]

    let
      currType = if isAlpha(curr): 1 elif isDigit(curr): 2 elif isPunct(curr): 3 else: 0
      backType = if isAlpha(back): 1 elif isDigit(back): 2 elif isPunct(back): 3 else: 0
    if currType != backType: break

  status.bufStatus[index].expandedColumn = status.bufStatus[index].currentColumn

proc moveToForwardEndOfWord*(status: var EditorStatus) =
  let
    currentLine = status.bufStatus[status.currentBuffer].currentLine
    currentColumn = status.bufStatus[status.currentBuffer].currentColumn
    startWith = if status.bufStatus[status.currentBuffer].buffer[currentLine].len == 0: ru'\n' else: status.bufStatus[status.currentBuffer].buffer[currentLine][currentColumn]
    isSkipped = if unicodeext.isPunct(startWith): unicodeext.isPunct elif unicodeext.isAlpha(startWith): unicodeext.isAlpha elif unicodeext.isDigit(startWith): unicodeext.isDigit else: nil

  if isSkipped == nil:
    let index = status.currentBuffer
    (status.bufStatus[index].currentLine, status.bufStatus[index].currentColumn) = status.bufStatus[index].buffer.next(currentLine, currentColumn)
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
  status.bufStatus[status.currentBuffer].buffer.delete(line, line + 1)

  let index = status.currentBuffer

  if status.bufStatus[index].buffer.len == 0: status.bufStatus[index].buffer.insert(ru"", 0)

  if line < status.bufStatus[index].currentLine: dec(status.bufStatus[index].currentLine)
  if status.bufStatus[index].currentLine >= status.bufStatus[index].buffer.len: status.bufStatus[index].currentLine = status.bufStatus[index].buffer.high
  
  status.bufStatus[index].currentColumn = 0
  status.bufStatus[index].expandedColumn = 0

  status.bufStatus[index].view.reload(status.bufStatus[index].buffer, min(status.bufStatus[index].view.originalLine[0], status.bufStatus[index].buffer.high))
  inc(status.bufStatus[index].countChange)

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

  let index = status.currentBuffer
  status.bufStatus[index].view.reload(status.bufStatus[index].buffer, min(status.bufStatus[index].view.originalLine[0], status.bufStatus[index].buffer.high))
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
  let index = status.currentBuffer
  status.bufStatus[index].buffer[status.bufStatus[index].currentLine].insert(status.registers.yankedStr, status.bufStatus[index].currentColumn)
  status.bufStatus[status.currentBuffer].currentColumn += status.registers.yankedStr.high

  status.bufStatus[index].view.reload(status.bufStatus[index].buffer, min(status.bufStatus[index].view.originalLine[0], status.bufStatus[index].buffer.high))
  inc(status.bufStatus[index].countChange)

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

  let index = status.currentBuffer

  if status.bufStatus[index].buffer[status.bufStatus[index].currentLine][0] == ru' ':
    for i in 0 ..< status.settings.tabStop:
      if status.bufStatus[index].buffer.len == 0 or status.bufStatus[index].buffer[status.bufStatus[index].currentLine][0] != ru' ': break
      status.bufStatus[index].buffer[status.bufStatus[index].currentLine].delete(0, 0)
  status.bufStatus[index].view.reload(status.bufStatus[index].buffer, status.bufStatus[index].view.originalLine[0])
  inc(status.bufStatus[index].countChange)

proc joinLine(status: var EditorStatus) =
  let index = status.currentBuffer
  if status.bufStatus[index].currentLine == status.bufStatus[index].buffer.len - 1 or status.bufStatus[index].buffer[status.bufStatus[index].currentLine + 1].len < 1:
    return

  status.bufStatus[index].buffer[status.bufStatus[index].currentLine].add(status.bufStatus[index].buffer[status.bufStatus[index].currentLine + 1])
  status.bufStatus[index].buffer.delete(status.bufStatus[index].currentLine + 1, status.bufStatus[index].currentLine + 2)

  status.bufStatus[index].view.reload(status.bufStatus[index].buffer, min(status.bufStatus[index].view.originalLine[0], status.bufStatus[index].buffer.high))
  inc(status.bufStatus[index].countChange)

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
  status.bufStatus[status.currentBuffer].isHighlight = false
  status.updateHighlight

#proc moveNextWindow(status: var EditorStatus) = moveCurrentMainWindow(status, status.currentMainWindow + 1)

#proc movePrevWindow(status: var EditorStatus) = moveCurrentMainWindow(status, status.currentMainWindow - 1)

proc normalCommand(status: var EditorStatus, key: Rune) =
  if status.bufStatus[status.currentBuffer].cmdLoop == 0: status.bufStatus[status.currentBuffer].cmdLoop = 1

  let
    cmdLoop = status.bufStatus[status.currentBuffer].cmdLoop
    currentBuf = status.currentBuffer
  
  if key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
    for i in 0 ..< cmdLoop: keyLeft(status)
  elif key == ord('l') or isRightKey(key):
    for i in 0 ..< cmdLoop: keyRight(status)
  elif key == ord('k') or isUpKey(key):
    for i in 0 ..< cmdLoop: keyUp(status)
  elif key == ord('j') or isDownKey(key) or isEnterKey(key):
    for i in 0 ..< cmdLoop: keyDown(status)
  elif key == ord('x') or isDcKey(key):
    yankString(status, min(cmdLoop, status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine].len - status.bufStatus[currentBuf].currentColumn))
    for i in 0 ..< min(cmdLoop, status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine].len - status.bufStatus[currentBuf].currentColumn):
      deleteCurrentCharacter(status)
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
    if getKey(status.mainWindowInfo[status.currentMainWindow].window) == ord('g'): moveToFirstLine(status)
  elif key == ord('G'):
    moveToLastLine(status)
  elif isPageUpkey(key):
    for i in 0 ..< cmdLoop: pageUp(status)
  elif isPageDownKey(key):
    for i in 0 ..< cmdLoop: pageDown(status)
  elif key == ord('w'):
    for i in 0 ..< cmdLoop: moveToForwardWord(status)
  elif key == ord('b'):
    for i in 0 ..< cmdLoop: moveToBackwardWord(status)
  elif key == ord('e'):
    for i in 0 ..< cmdLoop: moveToForwardEndOfWord(status)
  elif key == ord('o'):
    for i in 0 ..< cmdLoop: openBlankLineBelow(status)
    status.updateHighlight
    status.changeMode(Mode.insert)
  elif key == ord('O'):
    for i in 0 ..< cmdLoop: openBlankLineAbove(status)
    status.updateHighlight
    status.changeMode(Mode.insert)
  elif key == ord('d'):
    if getKey(status.mainWindowInfo[status.currentMainWindow].window) == ord('d'):
      yankLines(status, status.bufStatus[currentBuf].currentLine, min(status.bufStatus[currentBuf].currentLine + cmdLoop - 1, status.bufStatus[currentBuf].buffer.high))
      for i in 0 ..< min(cmdLoop, status.bufStatus[currentBuf].buffer.len - status.bufStatus[currentBuf].currentLine):deleteLine(status, status.bufStatus[currentBuf].currentLine)
  elif key == ord('y'):
    if getkey(status.mainWindowInfo[status.currentMainWindow].window) == ord('y'):
      yankLines(status, status.bufStatus[currentBuf].currentLine, min(status.bufStatus[currentBuf].currentLine + cmdLoop - 1, status.bufStatus[currentBuf].buffer.high))
  elif key == ord('p'):
    pasteAfterCursor(status)
  elif key == ord('P'):
    pasteBeforeCursor(status)
  elif key == ord('>'):
    for i in 0 ..< cmdLoop: addIndent(status)
  elif key == ord('<'):
    for i in 0 ..< cmdLoop: deleteIndent(status)
  elif key == ord('J'):
    joinLine(status)
  elif key == ord('r'):
    if cmdLoop > status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine].len - status.bufStatus[currentBuf].currentColumn: return

    let ch = getKey(status.mainWindowInfo[status.currentMainWindow].window)
    for i in 0 ..< cmdLoop:
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
    if status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine].len > 0: inc(status.bufStatus[currentBuf].currentColumn)
    status.changeMode(Mode.insert)
  elif key == ord('A'):
    status.bufStatus[currentBuf].currentColumn = status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine].len
    status.changeMode(Mode.insert)
#[
  elif key == ord('L'):
    moveNextWindow(status)
  elif key == ord('H'):
    movePrevWindow(status)
]#
  elif isEscKey(key):
    let key = getKey(status.mainWindowInfo[status.currentMainWindow].window)
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

    let key = getKey(status.mainWindowInfo[status.currentMainWindow].window)

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
