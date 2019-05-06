import strutils, strformat, terminal, deques, sequtils, math
import editorstatus, editorview, cursor, ui, gapbuffer, unicodeext, highlight, fileutils, commandview

proc jumpLine*(status: var EditorStatus, destination: int)
proc keyRight*(bufStatus: var BufferStatus)
proc keyLeft*(bufStatus: var BufferStatus)
proc keyUp*(bufStatus: var BufferStatus)
proc keyDown*(bufStatus: var BufferStatus)
proc replaceCurrentCharacter*(bufStatus: var BufferStatus, autoIndent:bool, character: Rune)

import searchmode, replacemode

proc writeDebugInfo(status: var EditorStatus, str: string = "") =
  status.commandWindow.erase

  status.commandWindow.write(0, 0, ru"debuf info: ")
  status.commandWindow.append(fmt"currentLine: {status.bufStatus[status.currentBuffer].currentLine}, currentColumn: {status.bufStatus[status.currentBuffer].currentColumn}")
  status.commandWindow.append(fmt", cursor.y: {status.bufStatus[status.currentBuffer].cursor.y}, cursor.x: {status.bufStatus[status.currentBuffer].cursor.x}")
  status.commandWindow.append(fmt", {str}")

  status.commandWindow.refresh

proc keyLeft*(bufStatus: var BufferStatus) =
  if bufStatus.currentColumn == 0: return

  dec(bufStatus.currentColumn)
  bufStatus.expandedColumn = bufStatus.currentColumn

proc keyRight*(bufStatus: var BufferStatus) =
  if bufStatus.currentColumn + 1 >= bufStatus.buffer[bufStatus.currentLine].len + (if bufStatus.mode == Mode.insert: 1 else: 0): return
  inc(bufStatus.currentColumn)
  bufStatus.expandedColumn = bufStatus.currentColumn

proc keyUp*(bufStatus: var BufferStatus) =
  if bufStatus.currentLine == 0: return

  dec(bufStatus.currentLine)
  let maxColumn = bufStatus.buffer[bufStatus.currentLine].len - 1 + (if bufStatus.mode == Mode.insert: 1 else: 0)
  bufStatus.currentColumn = min(bufStatus.expandedColumn, maxColumn)

  if bufStatus.currentColumn < 0: bufStatus.currentColumn = 0

proc keyDown*(bufStatus: var BufferStatus) =
  if bufStatus.currentLine+1 == bufStatus.buffer.len: return

  inc(bufStatus.currentLine)
  let maxColumn = bufStatus.buffer[bufStatus.currentLine].len - 1 + (if bufStatus.mode == Mode.insert: 1 else: 0)

  bufStatus.currentColumn = min(bufStatus.expandedColumn, maxColumn)
  if bufStatus.currentColumn < 0: bufStatus.currentColumn = 0

proc moveToFirstNonBlankOfLine*(bufStatus: var BufferStatus) =
  bufStatus.currentColumn = 0
  while bufStatus.buffer[bufStatus.currentLine][bufStatus.currentColumn] == ru' ':
    inc(bufStatus.currentColumn)
  bufStatus.expandedColumn = bufStatus.currentColumn

proc moveToFirstOfLine*(bufStatus: var BufferStatus) =
  bufStatus.currentColumn = 0
  bufStatus.expandedColumn = bufStatus.currentColumn

proc moveToLastOfLine*(bufStatus: var BufferStatus) =
  bufStatus.currentColumn = max(bufStatus.buffer[bufStatus.currentLine].len - 1, 0)
  bufStatus.expandedColumn = bufStatus.currentColumn

proc moveToFirstOfPreviousLine(bufStatus: var BufferStatus) =
  if bufStatus.currentLine == 0: return
  keyUp(bufStatus)
  moveToFirstOfLine(bufStatus)

proc moveToFirstOfNextLine(bufStatus: var BufferStatus) =
  if bufStatus.currentLine + 1 == bufStatus.buffer.len: return
  keyDown(bufStatus)
  moveToFirstOfLine(bufStatus)

proc deleteCurrentCharacter*(bufStatus: var BufferStatus) =
  let
    currentLine = bufStatus.currentLine
    currentColumn = bufStatus.currentColumn
    currentMode = bufStatus.mode

  if currentLine >= bufStatus.buffer.high and currentColumn > bufStatus.buffer[currentLine].high: return 

  if currentColumn == bufStatus.buffer[currentLine].len:
    bufStatus.buffer[currentLine].insert(bufStatus.buffer[currentLine + 1], currentColumn)
    bufStatus.buffer.delete(currentLine + 1, currentLine + 2)
  else:
    bufStatus.buffer[currentLine].delete(currentColumn)
    if bufStatus.buffer[currentLine].len > 0 and currentColumn == bufStatus.buffer[currentLine].len and currentMode != Mode.insert:
      bufStatus.currentColumn = bufStatus.buffer[bufStatus.currentLine].len-1
      bufStatus.expandedColumn = bufStatus.buffer[bufStatus.currentLine].len-1

  bufStatus.view.reload(bufStatus.buffer, bufStatus.view.originalLine[0])
  inc(bufStatus.countChange)

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

proc moveToFirstLine*(status: var EditorStatus) = jumpLine(status, 0)

proc moveToLastLine*(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].cmdLoop > 1: jumpLine(status, status.bufStatus[status.currentBuffer].cmdLoop - 1)
  else: jumpLine(status, status.bufStatus[status.currentBuffer].buffer.len - 1)

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

proc moveToForwardWord*(bufStatus: var BufferStatus) =
  let
    currentLine = bufStatus.currentLine
    currentColumn = bufStatus.currentColumn
    startWith = if bufStatus.buffer[currentLine].len == 0: ru'\n' else: bufStatus.buffer[currentLine][currentColumn]
    isSkipped = if unicodeext.isPunct(startWith): unicodeext.isPunct elif unicodeext.isAlpha(startWith): unicodeext.isAlpha elif unicodeext.isDigit(startWith): unicodeext.isDigit else: nil

  if isSkipped == nil:
    (bufStatus.currentLine, bufStatus.currentColumn) = bufStatus.buffer.next(currentLine, currentColumn)
  else:
    while true:
      inc(bufStatus.currentColumn)
      if bufStatus.currentColumn >= bufStatus.buffer[bufStatus.currentLine].len:
        inc(bufStatus.currentLine)
        bufStatus.currentColumn = 0
        break
      if not isSkipped(bufStatus.buffer[bufStatus.currentLine][bufStatus.currentColumn]): break

  while true:
    if bufStatus.currentLine >= bufStatus.buffer.len:
      bufStatus.currentLine = bufStatus.buffer.len-1
      bufStatus.currentColumn = bufStatus.buffer[bufStatus.buffer.high].high
      if bufStatus.currentColumn == -1: bufStatus.currentColumn = 0
      break

    if bufStatus.buffer[bufStatus.currentLine].len == 0: break
    if bufStatus.currentColumn == bufStatus.buffer[bufStatus.currentLine].len:
      inc(bufStatus.currentLine)
      bufStatus.currentColumn = 0
      continue

    let curr = bufStatus.buffer[bufStatus.currentLine][bufStatus.currentColumn]
    if isPunct(curr) or isAlpha(curr) or isDigit(curr): break
    inc(bufStatus.currentColumn)

  bufStatus.expandedColumn = bufStatus.currentColumn

proc moveToBackwardWord*(bufStatus: var BufferStatus) =
  if bufStatus.buffer.isFirst(bufStatus.currentLine, bufStatus.currentColumn): return

  while true:
    (bufStatus.currentLine, bufStatus.currentColumn) = bufStatus.buffer.prev(bufStatus.currentLine, bufStatus.currentColumn)
    let
      currentLine = bufStatus.currentLine
      currentColumn = bufStatus.currentColumn
      
    if bufStatus.buffer.len == 0 or bufStatus.buffer.isFirst(currentLine, currentColumn): break

    let curr = bufStatus.buffer[currentLine][currentColumn]
    if unicodeext.isSpace(curr): continue

    if bufStatus.currentColumn == 0: break

    let
      (backLine, backColumn) = bufStatus.buffer.prev(currentLine, currentColumn)
      back = bufStatus.buffer[backLine][backColumn]

    let
      currType = if isAlpha(curr): 1 elif isDigit(curr): 2 elif isPunct(curr): 3 else: 0
      backType = if isAlpha(back): 1 elif isDigit(back): 2 elif isPunct(back): 3 else: 0
    if currType != backType: break

  bufStatus.expandedColumn = bufStatus.currentColumn

proc moveToForwardEndOfWord*(bufStatus: var BufferStatus) =
  let
    currentLine = bufStatus.currentLine
    currentColumn = bufStatus.currentColumn
    startWith = if bufStatus.buffer[currentLine].len == 0: ru'\n' else: bufStatus.buffer[currentLine][currentColumn]
    isSkipped = if unicodeext.isPunct(startWith): unicodeext.isPunct elif unicodeext.isAlpha(startWith): unicodeext.isAlpha elif unicodeext.isDigit(startWith): unicodeext.isDigit else: nil

  if isSkipped == nil:
    (bufStatus.currentLine, bufStatus.currentColumn) = bufStatus.buffer.next(currentLine, currentColumn)
  else:
    while true:
      inc(bufStatus.currentColumn)
      if bufStatus.currentColumn == bufStatus.buffer[bufStatus.currentLine].len - 1: break
      if bufStatus.currentColumn >= bufStatus.buffer[bufStatus.currentLine].len:
        inc(bufStatus.currentLine)
        bufStatus.currentColumn = 0
        break
      if not isSkipped(bufStatus.buffer[bufStatus.currentLine][bufStatus.currentColumn + 1]): break

  while true:
    if bufStatus.currentLine >= bufStatus.buffer.len:
      bufStatus.currentLine = bufStatus.buffer.len - 1
      bufStatus.currentColumn = bufStatus.buffer[bufStatus.buffer.high].high
      if bufStatus.currentColumn == -1: bufStatus.currentColumn = 0
      break

    if bufStatus.buffer[bufStatus.currentLine].len == 0: break
    if bufStatus.currentColumn == bufStatus.buffer[bufStatus.currentLine].len:
      inc(bufStatus.currentLine)
      bufStatus.currentColumn = 0
      continue

    let curr = bufStatus.buffer[bufStatus.currentLine][bufStatus.currentColumn]
    if isPunct(curr) or isAlpha(curr) or isDigit(curr): break
    inc(bufStatus.currentColumn)

  bufStatus.expandedColumn = bufStatus.currentColumn

proc moveCenterScreen(bufStatus: var BufferStatus) =
  if bufStatus.currentLine > int(bufStatus.view.height / 2):
    if bufStatus.cursor.y > int(bufStatus.view.height / 2):
      let startOfPrintedLines = bufStatus.cursor.y - int(bufStatus.view.height / 2)
      bufStatus.view.reload(bufStatus.buffer, bufStatus.view.originalLine[startOfPrintedLines])
    else:
      let numOfTime = int(bufStatus.view.height / 2) - bufStatus.cursor.y
      for i in 0 ..< numOfTime: scrollUp(bufStatus.view, bufStatus.buffer)

proc scrollScreenTop(bufStatus: var BufferStatus) = bufStatus.view.reload(bufStatus.buffer, bufStatus.view.originalLine[bufStatus.cursor.y])

proc openBlankLineBelow(bufStatus: var BufferStatus) =
  let indent = sequtils.repeat(ru' ', countRepeat(bufStatus.buffer[bufStatus.currentLine], Whitespace, 0))

  bufStatus.buffer.insert(indent, bufStatus.currentLine+1)
  inc(bufStatus.currentLine)
  bufStatus.currentColumn = indent.len

  bufStatus.view.reload(bufStatus.buffer, bufStatus.view.originalLine[0])
  inc(bufStatus.countChange)

proc openBlankLineAbove(bufStatus: var BufferStatus) =
  let indent = sequtils.repeat(ru' ', countRepeat(bufStatus.buffer[bufStatus.currentLine], Whitespace, 0))

  bufStatus.buffer.insert(indent, bufStatus.currentLine)
  bufStatus.currentColumn = indent.len

  bufStatus.view.reload(bufStatus.buffer, bufStatus.view.originalLine[0])
  inc(bufStatus.countChange)

proc deleteLine(bufStatus: var BufferStatus, line: int) =
  bufStatus.buffer.delete(line, line + 1)

  if bufStatus.buffer.len == 0: bufStatus.buffer.insert(ru"", 0)

  if line < bufStatus.currentLine: dec(bufStatus.currentLine)
  if bufStatus.currentLine >= bufStatus.buffer.len: bufStatus.currentLine = bufStatus.buffer.high
  
  bufStatus.currentColumn = 0
  bufStatus.expandedColumn = 0

  bufStatus.view.reload(bufStatus.buffer, min(bufStatus.view.originalLine[0], bufStatus.buffer.high))
  inc(bufStatus.countChange)

proc yankLines(status: var EditorStatus, first, last: int) =
  status.registers.yankedStr = @[]
  status.registers.yankedLines = @[]
  for i in first .. last: status.registers.yankedLines.add(status.bufStatus[status.currentBuffer].buffer[i])

  # TODO: Refator
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

  # TODO: Refator
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

from insertmode import keyEnter

proc replaceCurrentCharacter*(bufStatus: var BufferStatus, autoIndent: bool, character: Rune) =
  if isEnterKey(character):
    deleteCurrentCharacter(bufStatus)
    keyEnter(bufStatus, autoIndent)
  else:
    bufStatus.buffer[bufStatus.currentLine][bufStatus.currentColumn] = character
    bufStatus.view.reload(bufStatus.buffer, bufStatus.view.originalLine[0])
    inc(bufStatus.countChange)

proc addIndent*(bufStatus: var BufferStatus, tabStop: int) =
  bufStatus.buffer[bufStatus.currentLine].insert(newSeqWith(tabStop, ru' '))

  bufStatus.view.reload(bufStatus.buffer, bufStatus.view.originalLine[0])
  inc(bufStatus.countChange)

proc deleteIndent*(bufStatus: var BufferStatus, tabStop: int) =
  if bufStatus.buffer.len == 0: return

  if bufStatus.buffer[bufStatus.currentLine][0] == ru' ':
    for i in 0 ..< tabStop:
      if bufStatus.buffer.len == 0 or bufStatus.buffer[bufStatus.currentLine][0] != ru' ': break
      bufStatus.buffer[bufStatus.currentLine].delete(0, 0)
  bufStatus.view.reload(bufStatus.buffer, bufStatus.view.originalLine[0])
  inc(bufStatus.countChange)

proc joinLine(bufStatus: var BufferStatus) =
  if bufStatus.currentLine == bufStatus.buffer.len - 1 or bufStatus.buffer[bufStatus.currentLine + 1].len < 1:
    return

  bufStatus.buffer[bufStatus.currentLine].add(bufStatus.buffer[bufStatus.currentLine + 1])
  bufStatus.buffer.delete(bufStatus.currentLine + 1, bufStatus.currentLine + 2)

  bufStatus.view.reload(bufStatus.buffer, min(bufStatus.view.originalLine[0], bufStatus.buffer.high))
  inc(bufStatus.countChange)

proc searchNextOccurrence(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[status.searchHistory.high]
  
  keyRight(status.bufStatus[status.currentBuffer])
  let searchResult = searchBuffer(status, keyword)
  if searchResult.line > -1:
    jumpLine(status, searchResult.line)
    for column in 0 ..< searchResult.column: keyRight(status.bufStatus[status.currentBuffer])
  elif searchResult.line == -1:
    keyLeft(status.bufStatus[status.currentBuffer])

proc searchNextOccurrenceReversely(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[status.searchHistory.high]
  
  keyLeft(status.bufStatus[status.currentBuffer])
  let searchResult = searchBufferReversely(status, keyword)
  if searchResult.line > -1:
    jumpLine(status, searchResult.line)
    for column in 0 ..< searchResult.column: keyRight(status.bufStatus[status.currentBuffer])
  elif searchResult.line == -1:
    keyRight(status.bufStatus[status.currentBuffer])

proc turnOffHighlighting*(status: var EditorStatus) =
  status.bufStatus[status.currentBuffer].isHighlight = false
  status.updateHighlight

proc writeFileAndExit(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].filename.len == 0:
    status.commandwindow.writeNoFileNameError(status.settings.editorColor.errorMessage)
    status.changeMode(Mode.normal)
  else:
    try:
      saveFile(status.bufStatus[status.currentBuffer].filename, status.bufStatus[status.currentBuffer].buffer.toRunes, status.settings.characterEncoding)
      closeWindow(status, status.currentMainWindow)
    except IOError:
      writeSaveError(status.commandWindow, status.settings.editorColor.errorMessage)

proc forceExit(status: var Editorstatus) = closeWindow(status, status.currentMainWindow)

proc normalCommand(status: var EditorStatus, key: Rune) =
  if status.bufStatus[status.currentBuffer].cmdLoop == 0: status.bufStatus[status.currentBuffer].cmdLoop = 1

  let
    cmdLoop = status.bufStatus[status.currentBuffer].cmdLoop
    currentBuf = status.currentBuffer

  if isControlL(key):
    moveNextWindow(status)
  elif isControlH(key):
    movePrevWindow(status)
  elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
    for i in 0 ..< cmdLoop: keyLeft(status.bufStatus[status.currentBuffer])
  elif key == ord('l') or isRightKey(key):
    for i in 0 ..< cmdLoop: keyRight(status.bufStatus[status.currentBuffer])
  elif key == ord('k') or isUpKey(key):
    for i in 0 ..< cmdLoop: keyUp(status.bufStatus[status.currentBuffer])
  elif key == ord('j') or isDownKey(key) or isEnterKey(key):
    for i in 0 ..< cmdLoop: keyDown(status.bufStatus[status.currentBuffer])
  elif key == ord('x') or isDcKey(key):
    yankString(status, min(cmdLoop, status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine].len - status.bufStatus[currentBuf].currentColumn))
    for i in 0 ..< min(cmdLoop, status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine].len - status.bufStatus[currentBuf].currentColumn):
      deleteCurrentCharacter(status.bufStatus[status.currentBuffer])
  elif key == ord('^'):
    moveToFirstNonBlankOfLine(status.bufStatus[status.currentBuffer])
  elif key == ord('0') or isHomeKey(key):
    moveToFirstOfLine(status.bufStatus[status.currentBuffer])
  elif key == ord('$') or isEndKey(key):
    moveToLastOfLine(status.bufStatus[status.currentBuffer])
  elif key == ord('-'):
    moveToFirstOfPreviousLine(status.bufStatus[status.currentBuffer])
  elif key == ord('+'):
    moveToFirstOfNextLine(status.bufStatus[status.currentBuffer])
  elif key == ord('g'):
    if getKey(status.mainWindowInfo[status.currentMainWindow].window) == ord('g'): moveToFirstLine(status)
  elif key == ord('G'):
    moveToLastLine(status)
  elif isPageUpkey(key) or isControlU(key):
    for i in 0 ..< cmdLoop: pageUp(status)
  elif isPageDownKey(key): ## Page down and Ctrl - F
    for i in 0 ..< cmdLoop: pageDown(status)
  elif key == ord('w'):
    for i in 0 ..< cmdLoop: moveToForwardWord(status.bufStatus[status.currentBuffer])
  elif key == ord('b'):
    for i in 0 ..< cmdLoop: moveToBackwardWord(status.bufStatus[status.currentBuffer])
  elif key == ord('e'):
    for i in 0 ..< cmdLoop: moveToForwardEndOfWord(status.bufStatus[status.currentBuffer])
  elif key == ord('z'):
    let key = getkey(status.mainWindowInfo[status.currentMainWindow].window)
    if key == ord('.'): moveCenterScreen(status.bufStatus[status.currentBuffer])
    elif key == ord('t'): scrollScreenTop(status.bufStatus[status.currentBuffer])
  elif key == ord('o'):
    for i in 0 ..< cmdLoop: openBlankLineBelow(status.bufStatus[status.currentBuffer])
    status.updateHighlight
    status.changeMode(Mode.insert)
  elif key == ord('O'):
    for i in 0 ..< cmdLoop: openBlankLineAbove(status.bufStatus[status.currentBuffer])
    status.updateHighlight
    status.changeMode(Mode.insert)
  elif key == ord('d'):
    if getKey(status.mainWindowInfo[status.currentMainWindow].window) == ord('d'):
      yankLines(status, status.bufStatus[currentBuf].currentLine, min(status.bufStatus[currentBuf].currentLine + cmdLoop - 1, status.bufStatus[currentBuf].buffer.high))
      for i in 0 ..< min(cmdLoop, status.bufStatus[currentBuf].buffer.len - status.bufStatus[currentBuf].currentLine): deleteLine(status.bufStatus[status.currentBuffer], status.bufStatus[currentBuf].currentLine)
  elif key == ord('y'):
    if getkey(status.mainWindowInfo[status.currentMainWindow].window) == ord('y'):
      yankLines(status, status.bufStatus[currentBuf].currentLine, min(status.bufStatus[currentBuf].currentLine + cmdLoop - 1, status.bufStatus[currentBuf].buffer.high))
  elif key == ord('p'):
    pasteAfterCursor(status)
  elif key == ord('P'):
    pasteBeforeCursor(status)
  elif key == ord('>'):
    for i in 0 ..< cmdLoop: addIndent(status.bufStatus[status.currentBuffer], status.settings.tabStop)
  elif key == ord('<'):
    for i in 0 ..< cmdLoop: deleteIndent(status.bufStatus[status.currentBuffer], status.settings.tabStop)
  elif key == ord('J'):
    joinLine(status.bufStatus[status.currentBuffer])
  elif key == ord('r'):
    if cmdLoop > status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine].len - status.bufStatus[currentBuf].currentColumn: return

    let ch = getKey(status.mainWindowInfo[status.currentMainWindow].window)
    for i in 0 ..< cmdLoop:
      if i > 0:
        inc(status.bufStatus[status.currentBuffer].currentColumn)
        status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].currentColumn
      replaceCurrentCharacter(status.bufStatus[status.currentBuffer], status.settings.autoIndent, ch)
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
  elif key == ord('Z'):
    let key = getKey(status.mainWindowInfo[status.currentMainWindow].window)
    if  key == ord('Z'): writeFileAndExit(status)
    elif key == ord('Q'): forceExit(status)
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

  while status.bufStatus[status.currentBuffer].mode == Mode.normal and status.mainWindowInfo.len > 0:
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
