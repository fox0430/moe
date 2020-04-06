import strutils, deques, sequtils, os, osproc, random
import editorstatus, editorview, ui, gapbuffer, unicodeext, commandview, undoredostack, window

proc deleteParen*(bufStatus: var BufferStatus, currentChar: Rune) =
  let
    currentLine = bufStatus.currentLine
    currentColumn = bufStatus.currentColumn
    buffer = bufStatus.buffer

  if isOpenParen(currentChar):
    var depth = 1
    let
      openParen = currentChar
      closeParen = correspondingCloseParen(openParen)
    for i in currentLine ..< buffer.len:
      for j in currentColumn ..< buffer[i].len:
        if buffer[i][j] == openParen: inc(depth)
        elif buffer[i][j] == closeParen: dec(depth)
        if depth == 0:
          var line = bufStatus.buffer[i]
          line.delete(j)
          bufStatus.buffer[i] = line
          return
  elif isCloseParen(currentChar):
    var depth = 1
    let
      closeParen = currentChar
      openParen = correspondingOpenParen(closeParen)
    for i in countdown(currentLine, 0):
      let startColumn = if i == currentLine: currentColumn - 1 else: buffer[i].high 
      for j in countdown(startColumn, 0):
        if buffer[i][j] == closeParen: inc(depth)
        elif buffer[i][j] == openParen: dec(depth)
        if depth == 0:
          var line = bufStatus.buffer[i]
          line.delete(j)
          bufStatus.buffer[i] = line
          return

proc deleteCurrentCharacter*(bufStatus: var BufferStatus, autoDeleteParen: bool, currentWin: WindowNode) =
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
    let
      currentChar = bufStatus.buffer[currentLine][currentColumn]
      oldLine = bufStatus.buffer[bufStatus.currentLine]
    var newLine = bufStatus.buffer[bufStatus.currentLine]
    newLine.delete(currentColumn)
    if oldLine != newLine: bufStatus.buffer[currentLine] = newLine

    if autoDeleteParen and currentChar.isParen: bufStatus.deleteParen(currentChar)

    if bufStatus.buffer[currentLine].len < 1:
      bufStatus.currentColumn = 0
      bufStatus.expandedColumn = 0
    elif bufStatus.buffer[currentLine].len > 0 and currentColumn > bufStatus.buffer[currentLine].high and currentMode != Mode.insert:
      bufStatus.currentColumn = bufStatus.buffer[bufStatus.currentLine].len - 1
      bufStatus.expandedColumn = bufStatus.buffer[bufStatus.currentLine].len - 1

  currentWin.view.reload(bufStatus.buffer, currentWin.view.originalLine[0])
  inc(bufStatus.countChange)

proc openBlankLineBelow*(bufStatus: var BufferStatus, currentWin: WindowNode) =
  let
    indent = sequtils.repeat(ru' ', countRepeat(bufStatus.buffer[bufStatus.currentLine], Whitespace, 0))

  bufStatus.buffer.insert(indent, bufStatus.currentLine + 1)
  inc(bufStatus.currentLine)
  bufStatus.currentColumn = indent.len

  currentWin.view.reload(bufStatus.buffer, currentWin.view.originalLine[0])
  inc(bufStatus.countChange)

proc openBlankLineAbove*(bufStatus: var BufferStatus, currentWin: WindowNode) =
  let
    indent = sequtils.repeat(ru' ', countRepeat(bufStatus.buffer[bufStatus.currentLine], Whitespace, 0))

  bufStatus.buffer.insert(indent, bufStatus.currentLine)
  bufStatus.currentColumn = indent.len

  currentWin.view.reload(bufStatus.buffer, currentWin.view.originalLine[0])
  inc(bufStatus.countChange)

proc deleteLine*(bufStatus: var BufferStatus, currentWin: WindowNode, line: int) =
  bufStatus.buffer.delete(line, line)

  if bufStatus.buffer.len == 0: bufStatus.buffer.insert(ru"", 0)

  if line < bufStatus.currentLine: dec(bufStatus.currentLine)
  if bufStatus.currentLine >= bufStatus.buffer.len: bufStatus.currentLine = bufStatus.buffer.high
  
  bufStatus.currentColumn = 0
  bufStatus.expandedColumn = 0

  currentWin.view.reload(bufStatus.buffer, min(currentWin.view.originalLine[0], bufStatus.buffer.high))
  inc(bufStatus.countChange)

proc deleteWord*(bufStatus: var BufferStatus, currentWin: WindowNode) =
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

  currentWin.view.reload(bufStatus.buffer, min(currentWin.view.originalLine[0], bufStatus.buffer.high))
  inc(bufStatus.countChange)

proc deleteCharacterUntilEndOfLine*(bufStatus: var BufferStatus, autoDeleteParen: bool, currentWin: WindowNode) =
  let
    currentLine = bufStatus.currentLine
    startColumn = bufStatus.currentColumn
  for i in startColumn ..< bufStatus.buffer[currentLine].len: bufStatus.deleteCurrentCharacter(autoDeleteParen, currentWin)

proc deleteCharacterBeginningOfLine*(bufStatus: var BufferStatus, autoDeleteParen: bool, currentWin: WindowNode) =
  let beforColumn = bufStatus.currentColumn
  bufStatus.currentColumn = 0
  bufStatus.expandedColumn = 0
  for i in 0 ..< beforColumn: bufStatus.deleteCurrentCharacter(autoDeleteParen, currentWin)

proc genDelimiterStr(buffer: string): string =
  while true:
    for _ in .. 10: add(result, char(rand(int('A') .. int('Z'))))
    if buffer != result: break

proc sendToClipboad*(registers: Registers, platform: Platform) =
  var buffer = ""
  if registers.yankedStr.len > 0: buffer = $registers.yankedStr
  else:
    for i in 0 ..< registers.yankedLines.len:
      if i == 0: buffer = $registers.yankedLines[0]
      else: buffer &= "\n" & $registers.yankedLines[i]

  if buffer.len < 1: return

  let delimiterStr = genDelimiterStr(buffer)

  case platform
    of linux:
      ## Check if X server is running
      let (output, exitCode) = execCmdEx("xset q")
      if exitCode == 0: discard execShellCmd("xclip -r <<" & "'" & delimiterStr & "'" & "\n" & buffer & "\n" & delimiterStr & "\n")
    of wsl: discard execShellCmd("clip.exe <<" & "'" & delimiterStr & "'" & "\n" & buffer & "\n"  & delimiterStr & "\n")
    of mac: discard execShellCmd("pbcopy <<" & "'" & delimiterStr & "'" & "\n" & buffer & "\n"  & delimiterStr & "\n")
    else: discard

proc yankLines*(status: var EditorStatus, first, last: int) =
  status.registers.yankedStr = @[]
  status.registers.yankedLines = @[]
  for i in first .. last: status.registers.yankedLines.add(status.bufStatus[status.currentBuffer].buffer[i])

  status.commandWindow.writeMessageYankedLine(status.registers.yankedLines.len, status.messageLog)

proc pasteLines(status: var EditorStatus) =
  for i in 0 ..< status.registers.yankedLines.len:
    status.bufStatus[status.currentBuffer].buffer.insert(status.registers.yankedLines[i], status.bufStatus[status.currentBuffer].currentLine + i + 1)

  let index = status.currentBuffer
  status.currentWorkSpace.currentMainWindowNode.view.reload(status.bufStatus[index].buffer, min(status.currentWorkSpace.currentMainWindowNode.view.originalLine[0], status.bufStatus[index].buffer.high))
  inc(status.bufStatus[status.currentBuffer].countChange)

proc yankString*(status: var EditorStatus, length: int) =
  status.registers.yankedLines = @[]
  status.registers.yankedStr = @[]
  for i in status.bufStatus[status.currentBuffer].currentColumn ..< length:
    status.registers.yankedStr.add(status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine][i])

  if status.settings.systemClipboard: status.registers.sendToClipboad(status.platform)

  status.commandWindow.writeMessageYankedCharactor(status.registers.yankedStr.len, status.messageLog)

proc yankWord*(status: var Editorstatus, loop: int) =
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

  status.currentWorkSpace.currentMainWindowNode.view.reload(status.bufStatus[index].buffer, min(status.currentWorkSpace.currentMainWindowNode.view.originalLine[0], status.bufStatus[index].buffer.high))
  inc(status.bufStatus[index].countChange)

proc pasteAfterCursor*(status: var EditorStatus) =
  if status.registers.yankedStr.len > 0:
    status.bufStatus[status.currentBuffer].currentColumn.inc
    pasteString(status)
  elif status.registers.yankedLines.len > 0:
    pasteLines(status)

proc pasteBeforeCursor*(status: var EditorStatus) =
  status.currentWorkSpace.currentMainWindowNode.view.reload(status.bufStatus[status.currentBuffer].buffer, status.currentWorkSpace.currentMainWindowNode.view.originalLine[0])

  if status.registers.yankedLines.len > 0:
    pasteLines(status)
  elif status.registers.yankedStr.len > 0:
    pasteString(status)

from insertmode import keyEnter

proc replaceCurrentCharacter*(bufStatus: var BufferStatus, currentWin: WindowNode, autoIndent: bool, autoDeleteParen: bool, character: Rune) =
  if isEnterKey(character):
    bufStatus.deleteCurrentCharacter(autoDeleteParen, currentWin)
    keyEnter(bufStatus, currentWin, autoIndent)
  else:
    let oldLine = bufStatus.buffer[bufStatus.currentLine]
    var newLine = bufStatus.buffer[bufStatus.currentLine]
    newLine[bufStatus.currentColumn] = character
    if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine] = newLine

    currentWin.view.reload(bufStatus.buffer, currentWin.view.originalLine[0])
    inc(bufStatus.countChange)

proc addIndent*(bufStatus: var BufferStatus, currentWin: WindowNode, tabStop: int) =
  let oldLine = bufStatus.buffer[bufStatus.currentLine]
  var newLine = bufStatus.buffer[bufStatus.currentLine]
  newLine.insert(newSeqWith(tabStop, ru' '))
  if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine] = newLine

  currentWin.view.reload(bufStatus.buffer, currentWin.view.originalLine[0])
  inc(bufStatus.countChange)

proc deleteIndent*(bufStatus: var BufferStatus, currentWin: WindowNode, tabStop: int) =
  if bufStatus.buffer.len == 0: return

  if bufStatus.buffer[bufStatus.currentLine][0] == ru' ':
    for i in 0 ..< tabStop:
      if bufStatus.buffer.len == 0 or bufStatus.buffer[bufStatus.currentLine][0] != ru' ': break
      let oldLine = bufStatus.buffer[bufStatus.currentLine]
      var newLine = bufStatus.buffer[bufStatus.currentLine]
      newLine.delete(0, 0)
      if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine] = newLine
  currentWin.view.reload(bufStatus.buffer, currentWin.view.originalLine[0])
  inc(bufStatus.countChange)

proc joinLine*(bufStatus: var BufferStatus, currentWin: WindowNode) =
  if bufStatus.currentLine == bufStatus.buffer.len - 1 or bufStatus.buffer[bufStatus.currentLine + 1].len < 1:
    return

  let oldLine = bufStatus.buffer[bufStatus.currentLine]
  var newLine = bufStatus.buffer[bufStatus.currentLine]
  newLine.add(bufStatus.buffer[bufStatus.currentLine + 1])
  if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine] = newLine

  bufStatus.buffer.delete(bufStatus.currentLine + 1, bufStatus.currentLine + 1)

  currentWin.view.reload(bufStatus.buffer, min(currentWin.view.originalLine[0], bufStatus.buffer.high))
  inc(bufStatus.countChange)
