import strutils, strformat, terminal, deques, sequtils, os, osproc, random
import editorstatus, editorview, cursor, ui, gapbuffer, unicodeext, highlight, fileutils, commandview, undoredostack

proc jumpLine*(status: var EditorStatus, destination: int)
proc keyRight*(bufStatus: var BufferStatus)
proc keyLeft*(bufStatus: var BufferStatus)
proc keyUp*(bufStatus: var BufferStatus)
proc keyDown*(bufStatus: var BufferStatus)
proc replaceCurrentCharacter*(bufStatus: var BufferStatus, autoIndent:bool, character: Rune)

import searchmode, replacemode

proc writeDebugInfo(status: var EditorStatus, str: string = "") =
  status.commandWindow.erase

  status.commandWindow.write(0, 0, "debuf info: ", EditorColorPair.commandBar)
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

proc moveToFirstOfPreviousLine*(bufStatus: var BufferStatus) =
  if bufStatus.currentLine == 0: return
  keyUp(bufStatus)
  moveToFirstOfLine(bufStatus)

proc moveToFirstOfNextLine*(bufStatus: var BufferStatus) =
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
    let oldLine = bufStatus.buffer[bufStatus.currentLine]
    var newLine = bufStatus.buffer[bufStatus.currentLine]
    newLine.insert(bufStatus.buffer[currentLine + 1], currentColumn)
    if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine] = newLine

    bufStatus.buffer.delete(currentLine + 1, currentLine + 1)
  else:
    let oldLine = bufStatus.buffer[bufStatus.currentLine]
    var newLine = bufStatus.buffer[bufStatus.currentLine]
    newLine.delete(currentColumn)
    if oldLine != newLine: bufStatus.buffer[currentLine] = newLine
    
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
      
    if bufStatus.buffer[bufStatus.currentLine].len == 0 or bufStatus.buffer.isFirst(currentLine, currentColumn): break

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

proc scrollScreenBottom(bufStatus: var BufferStatus) =
  if bufStatus.currentLine > bufStatus.view.height:
    let numOfTime = bufStatus.view.height - bufStatus.cursor.y - 2
    for i in 0 ..< numOfTime: scrollUp(bufStatus.view, bufStatus.buffer)

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
  bufStatus.buffer.delete(line, line)

  if bufStatus.buffer.len == 0: bufStatus.buffer.insert(ru"", 0)

  if line < bufStatus.currentLine: dec(bufStatus.currentLine)
  if bufStatus.currentLine >= bufStatus.buffer.len: bufStatus.currentLine = bufStatus.buffer.high
  
  bufStatus.currentColumn = 0
  bufStatus.expandedColumn = 0

  bufStatus.view.reload(bufStatus.buffer, min(bufStatus.view.originalLine[0], bufStatus.buffer.high))
  inc(bufStatus.countChange)

proc deleteWord(bufStatus: var BufferStatus) =
  if bufStatus.buffer.len == 1 and bufStatus.buffer[bufStatus.currentLine].len < 1: return
  elif bufStatus.buffer.len > 1 and bufStatus.buffer[bufStatus.currentLine].len < 1:
    bufStatus.buffer.delete(bufStatus.currentLine, bufStatus.currentLine + 1)
    if bufStatus.currentLine > bufStatus.buffer.high: bufStatus.currentLine = bufStatus.buffer.high
  elif bufStatus.currentColumn == bufStatus.buffer[bufStatus.currentLine].high:
    let oldLine = bufStatus.buffer[bufStatus.currentLine]
    var newLine = bufStatus.buffer[bufStatus.currentLine]
    newLine.delete(bufStatus.currentColumn)
    if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine] = newLine

    if bufStatus.currentColumn > 0: dec(bufStatus.currentColumn)
  else:
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
        if bufStatus.currentColumn >= bufStatus.buffer[bufStatus.currentLine].len: break
        if not isSkipped(bufStatus.buffer[bufStatus.currentLine][bufStatus.currentColumn]): break

    while true:
      if bufStatus.currentColumn > bufStatus.buffer[bufStatus.currentLine].high: break
      let curr = bufStatus.buffer[bufStatus.currentLine][bufStatus.currentColumn]
      if isPunct(curr) or isAlpha(curr) or isDigit(curr): break
      inc(bufStatus.currentColumn)

    let oldLine = bufStatus.buffer[currentLine]
    var newLine = bufStatus.buffer[currentLine]
    for i in currentColumn ..< bufStatus.currentColumn: newLine.delete(currentColumn)
    if oldLine != newLine: bufStatus.buffer[currentLine] = newLine
    bufStatus.expandedColumn = currentColumn
    bufStatus.currentColumn = currentColumn

  bufStatus.view.reload(bufStatus.buffer, min(bufStatus.view.originalLine[0], bufStatus.buffer.high))
  inc(bufStatus.countChange)

proc deleteCharacterUntilEndOfLine(bufStatus: var BufferStatus) =
  let
    currentLine = bufStatus.currentLine
    startColumn = bufStatus.currentColumn
  for i in startColumn ..< bufStatus.buffer[currentLine].len: deleteCurrentCharacter(bufStatus)

proc deleteCharacterBeginningOfLine(bufStatus: var BufferStatus) =
  let beforColumn = bufStatus.currentColumn
  bufStatus.currentColumn = 0
  bufStatus.expandedColumn = 0
  for i in 0 ..< beforColumn: deleteCurrentCharacter(bufStatus)

proc genDelimiterStr(buffer: string): string =
  while true:
    for _ in .. 10: add(result, char(rand(int('A') .. int('z'))))
    if buffer != result: break

proc sendToClipboad*(registers: Registers, platform: Platform) =
  let buffer = if registers.yankedStr.len > 0: $registers.yankedStr else: $registers.yankedLines
  let delimiterStr = genDelimiterStr(buffer)
  case platform
    of linux:
      ## Check if X server is running
      let (output, exitCode) = execCmdEx("xset q")
      if exitCode == 0: discard execShellCmd("xclip <<" & delimiterStr & "\n" & buffer & "\n"  & delimiterStr & "\n")
    of wsl: discard execShellCmd("clip.exe <<" & delimiterStr & "\n" & buffer & "\n"  & delimiterStr & "\n")
    of mac: discard execShellCmd("pbcopy <<" & delimiterStr & "\n" & buffer & "\n"  & delimiterStr & "\n")
    else: discard

proc yankLines(status: var EditorStatus, first, last: int) =
  status.registers.yankedStr = @[]
  status.registers.yankedLines = @[]
  for i in first .. last: status.registers.yankedLines.add(status.bufStatus[status.currentBuffer].buffer[i])

  status.commandWindow.writeMessageYankedLine(status.registers.yankedLines.len, status.messageLog)

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

  status.registers.sendToClipboad(status.platform)

  status.commandWindow.writeMessageYankedCharactor(status.registers.yankedStr.len, status.messageLog)

proc yankWord(status: var Editorstatus, loop: int) =
  status.registers.yankedLines = @[]
  status.registers.yankedStr = @[]

  let
    currentBuf = status.currentBuffer
    line = status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine]
  var startColumn = status.bufStatus[currentBuf].currentColumn

  for i in 0 ..< loop:
    if line.len < 1:
      status.registers.yankedLines = @[ru""]
      return
    if isPunct(line[startColumn]):
      status.registers.yankedStr.add(line[startColumn])
      return

    for j in startColumn ..< line.len:
      let rune = line[j]
      if isWhiteSpace(rune):
        for k in j ..< line.len:
          if isWhiteSpace(line[k]):status.registers.yankedStr.add(rune)
          else:
            startColumn = k
            break
        break
      elif not isAlpha(rune) or isPunct(rune) or isDigit(rune):
        startColumn = j
        break
      else: status.registers.yankedStr.add(rune)

proc pasteString(status: var EditorStatus) =
  let index = status.currentBuffer

  let oldLine = status.bufStatus[index].buffer[status.bufStatus[index].currentLine]
  var newLine = status.bufStatus[index].buffer[status.bufStatus[index].currentLine]
  newLine.insert(status.registers.yankedStr, status.bufStatus[index].currentColumn)
  if oldLine != newLine: status.bufStatus[index].buffer[status.bufStatus[index].currentLine] = newLine

  status.bufStatus[status.currentBuffer].currentColumn += status.registers.yankedStr.high - 1

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
    let oldLine = bufStatus.buffer[bufStatus.currentLine]
    var newLine = bufStatus.buffer[bufStatus.currentLine]
    newLine[bufStatus.currentColumn] = character
    if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine] = newLine

    bufStatus.view.reload(bufStatus.buffer, bufStatus.view.originalLine[0])
    inc(bufStatus.countChange)

proc addIndent*(bufStatus: var BufferStatus, tabStop: int) =
  let oldLine = bufStatus.buffer[bufStatus.currentLine]
  var newLine = bufStatus.buffer[bufStatus.currentLine]
  newLine.insert(newSeqWith(tabStop, ru' '))
  if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine] = newLine

  bufStatus.view.reload(bufStatus.buffer, bufStatus.view.originalLine[0])
  inc(bufStatus.countChange)

proc deleteIndent*(bufStatus: var BufferStatus, tabStop: int) =
  if bufStatus.buffer.len == 0: return

  if bufStatus.buffer[bufStatus.currentLine][0] == ru' ':
    for i in 0 ..< tabStop:
      if bufStatus.buffer.len == 0 or bufStatus.buffer[bufStatus.currentLine][0] != ru' ': break
      let oldLine = bufStatus.buffer[bufStatus.currentLine]
      var newLine = bufStatus.buffer[bufStatus.currentLine]
      newLine.delete(0, 0)
      if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine] = newLine
  bufStatus.view.reload(bufStatus.buffer, bufStatus.view.originalLine[0])
  inc(bufStatus.countChange)

proc joinLine(bufStatus: var BufferStatus) =
  if bufStatus.currentLine == bufStatus.buffer.len - 1 or bufStatus.buffer[bufStatus.currentLine + 1].len < 1:
    return

  let oldLine = bufStatus.buffer[bufStatus.currentLine]
  var newLine = bufStatus.buffer[bufStatus.currentLine]
  newLine.add(bufStatus.buffer[bufStatus.currentLine + 1])
  if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine] = newLine

  bufStatus.buffer.delete(bufStatus.currentLine + 1, bufStatus.currentLine + 1)

  bufStatus.view.reload(bufStatus.buffer, min(bufStatus.view.originalLine[0], bufStatus.buffer.high))
  inc(bufStatus.countChange)

proc searchOneCharactorToEndOfLine(bufStatus: var BufferStatus, rune: Rune) =
  let line = bufStatus.buffer[bufStatus.currentLine]

  if line.len < 1 or isEscKey(rune) or (bufStatus.currentColumn == line.high): return

  for col in bufStatus.currentColumn + 1 ..< line.len:
    if line[col] == rune:
      bufStatus.currentColumn = col
      break

proc searchOneCharactorToBeginOfLine(bufStatus: var BufferStatus, rune: Rune) =
  let line = bufStatus.buffer[bufStatus.currentLine]

  if line.len < 1 or isEscKey(rune) or (bufStatus.currentColumn == 0): return

  for col in countdown(bufStatus.currentColumn - 1, 0):
    if line[col] == rune:
      bufStatus.currentColumn = col
      break

proc searchNextOccurrence(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[status.searchHistory.high]
  
  status.bufStatus[status.currentMainWindow].isHighlight = true
  status.updateHighlight

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
  
  status.bufStatus[status.currentMainWindow].isHighlight = true
  status.updateHighlight

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

proc undo(bufStatus: var BufferStatus) =
  if not bufStatus.buffer.canUndo: return
  bufStatus.buffer.undo
  bufStatus.revertPosition(bufStatus.buffer.lastSuitId)
  if bufStatus.currentColumn == bufStatus.buffer[bufStatus.currentLine].len and bufStatus.currentColumn > 0:
    (bufStatus.currentLine, bufStatus.currentColumn) = bufStatus.buffer.prev(bufStatus.currentLine, bufStatus.currentColumn)
  bufStatus.view.reload(bufStatus.buffer, min(bufStatus.view.originalLine[0], bufStatus.buffer.high))
  inc(bufStatus.countChange)

proc redo(bufStatus: var BufferStatus) =
  if not bufStatus.buffer.canRedo: return
  bufStatus.buffer.redo
  bufStatus.revertPosition(bufStatus.buffer.lastSuitId)
  bufStatus.view.reload(bufStatus.buffer, min(bufStatus.view.originalLine[0], bufStatus.buffer.high))
  inc(bufStatus.countChange)

proc writeFileAndExit(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].filename.len == 0:
    status.commandwindow.writeNoFileNameError(status.messageLog)
    status.changeMode(Mode.normal)
  else:
    try:
      saveFile(status.bufStatus[status.currentBuffer].filename, status.bufStatus[status.currentBuffer].buffer.toRunes, status.settings.characterEncoding)
      closeWindow(status, status.currentMainWindow)
    except IOError:
      status.commandWindow.writeSaveError(status.messageLog)

proc forceExit(status: var Editorstatus) = closeWindow(status, status.currentMainWindow)

proc normalCommand(status: var EditorStatus, key: Rune) =
  if status.bufStatus[status.currentBuffer].cmdLoop == 0: status.bufStatus[status.currentBuffer].cmdLoop = 1

  let
    cmdLoop = status.bufStatus[status.currentBuffer].cmdLoop
    currentBuf = status.currentBuffer

  if isControlK(key):
    moveNextWindow(status)
  elif isControlJ(key):
    movePrevWindow(status)
  elif isControlV(key):
    status.changeMode(Mode.visualBlock)
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
    elif key == ord('b'): scrollScreenBottom(status.bufStatus[status.currentBuffer])
  elif key == ord('o'):
    for i in 0 ..< cmdLoop: openBlankLineBelow(status.bufStatus[status.currentBuffer])
    status.updateHighlight
    status.changeMode(Mode.insert)
  elif key == ord('O'):
    for i in 0 ..< cmdLoop: openBlankLineAbove(status.bufStatus[status.currentBuffer])
    status.updateHighlight
    status.changeMode(Mode.insert)
  elif key == ord('d'):
    let key = getKey(status.mainWindowInfo[status.currentMainWindow].window)
    if key == ord('d'):
      yankLines(status, status.bufStatus[currentBuf].currentLine, min(status.bufStatus[currentBuf].currentLine + cmdLoop - 1, status.bufStatus[currentBuf].buffer.high))
      for i in 0 ..< min(cmdLoop, status.bufStatus[currentBuf].buffer.len - status.bufStatus[currentBuf].currentLine): deleteLine(status.bufStatus[status.currentBuffer], status.bufStatus[currentBuf].currentLine)
    elif key == ord('w'): deleteWord(status.bufStatus[status.currentBuffer])
    elif key == ('$') or isEndKey(key): deleteCharacterUntilEndOfLine(status.bufStatus[status.currentBuffer])
    elif key == ('0') or isHomeKey(key): deleteCharacterBeginningOfLine(status.bufStatus[status.currentBuffer])
  elif key == ord('y'):
    let key = getkey(status.mainWindowInfo[status.currentMainWindow].window)
    if key == ord('y'): yankLines(status, status.bufStatus[currentBuf].currentLine, min(status.bufStatus[currentBuf].currentLine + cmdLoop - 1, status.bufStatus[currentBuf].buffer.high))
    elif key == ord('w'): yankWord(status, cmdLoop)
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
  elif key == ord('f'):
    let key = getKey(status.mainWindowInfo[status.currentMainWindow].window)
    searchOneCharactorToEndOfLine(status.bufStatus[status.currentBuffer], key)
  elif key == ord('F'):
    let key = getKey(status.mainWindowInfo[status.currentMainWindow].window)
    searchOneCharactorToBeginOfLine(status.bufStatus[status.currentBuffer], key)
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
    let lineWidth = status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine].len
    if lineWidth == 0: discard
    elif lineWidth == status.bufStatus[currentBuf].currentColumn: discard
    else: inc(status.bufStatus[currentBuf].currentColumn)
    status.changeMode(Mode.insert)
  elif key == ord('A'):
    status.bufStatus[currentBuf].currentColumn = status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine].len
    status.changeMode(Mode.insert)
  elif key == ord('u'):
    undo(status.bufStatus[status.currentBuffer])
  elif isControlR(key):
    redo(status.bufStatus[status.currentBuffer])
  elif key == ord('Z'):
    let key = getKey(status.mainWindowInfo[status.currentMainWindow].window)
    if  key == ord('Z'): writeFileAndExit(status)
    elif key == ord('Q'): forceExit(status)
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

    var key: Rune = Rune('\0')
    while key == Rune('\0'):
      status.eventLoopTask
      key = getKey(status.mainWindowInfo[status.currentMainWindow].window)

    status.bufStatus[status.currentBuffer].buffer.beginNewSuitIfNeeded
    status.bufStatus[status.currentBuffer].tryRecordCurrentPosition

    if isEscKey(key):
      let keyAfterEsc = getKey(status.mainWindowInfo[status.currentMainWindow].window)
      if isEscKey(key):
        turnOffHighlighting(status)
        continue
      else: key = keyAfterEsc

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
