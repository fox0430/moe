import strutils, sequtils, os, osproc, random
import editorstatus, ui, gapbuffer, unicodeext, commandview, undoredostack,
       window, bufferstatus, movement

proc deleteParen*(bufStatus: var BufferStatus,
                  windowNode: WindowNode,
                  currentChar: Rune) =
  let
    currentLine = windowNode.currentLine
    currentColumn = windowNode.currentColumn
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
      let startColumn = if i == currentLine: currentColumn - 1
                        else: buffer[i].high 
      for j in countdown(startColumn, 0):
        if buffer[i][j] == closeParen: inc(depth)
        elif buffer[i][j] == openParen: dec(depth)
        if depth == 0:
          var line = bufStatus.buffer[i]
          line.delete(j)
          bufStatus.buffer[i] = line
          return

proc deleteCurrentCharacter*(bufStatus: var BufferStatus,
                             windowNode: WindowNode,
                             autoDeleteParen: bool) =
  let
    currentLine = windowNode.currentLine
    currentColumn = windowNode.currentColumn
    currentMode = bufStatus.mode

  if currentLine >= bufStatus.buffer.high and
     currentColumn > bufStatus.buffer[currentLine].high: return 

  if currentColumn == bufStatus.buffer[currentLine].len:
    let oldLine = bufStatus.buffer[windowNode.currentLine]
    var newLine = bufStatus.buffer[windowNode.currentLine]
    newLine.insert(bufStatus.buffer[currentLine + 1], currentColumn)
    if oldLine != newLine:
      bufStatus.buffer[windowNode.currentLine] = newLine

    bufStatus.buffer.delete(currentLine + 1, currentLine + 1)
  else:
    let
      currentChar = bufStatus.buffer[currentLine][currentColumn]
      oldLine = bufStatus.buffer[windowNode.currentLine]
    var newLine = bufStatus.buffer[windowNode.currentLine]
    newLine.delete(currentColumn)
    if oldLine != newLine: bufStatus.buffer[currentLine] = newLine

    if autoDeleteParen and currentChar.isParen:
      bufStatus.deleteParen(windowNode, currentChar)

    if bufStatus.buffer[currentLine].len < 1:
      windowNode.currentColumn = 0
      windowNode.expandedColumn = 0
    elif bufStatus.buffer[currentLine].len > 0 and
         currentColumn > bufStatus.buffer[currentLine].high and
         currentMode != Mode.insert:
      windowNode.currentColumn = bufStatus.buffer[windowNode.currentLine].len - 1
      windowNode.expandedColumn = bufStatus.buffer[windowNode.currentLine].len - 1

  inc(bufStatus.countChange)

proc openBlankLineBelow*(bufStatus: var BufferStatus, windowNode: WindowNode) =
  let
    indent = sequtils.repeat(ru' ',
                             countRepeat(bufStatus.buffer[windowNode.currentLine],
                             Whitespace,
                             0))

  bufStatus.buffer.insert(indent, windowNode.currentLine + 1)
  inc(windowNode.currentLine)
  windowNode.currentColumn = indent.len

  inc(bufStatus.countChange)

proc openBlankLineAbove*(bufStatus: var BufferStatus, windowNode: WindowNode) =
  let
    indent = sequtils.repeat(ru' ',
                             countRepeat(bufStatus.buffer[windowNode.currentLine],
                             Whitespace,
                             0))

  bufStatus.buffer.insert(indent, windowNode.currentLine)
  windowNode.currentColumn = indent.len

  inc(bufStatus.countChange)

proc deleteLine*(bufStatus: var BufferStatus,
                 windowNode: WindowNode,
                 line: int) =
                 
  bufStatus.buffer.delete(line, line)

  if bufStatus.buffer.len == 0: bufStatus.buffer.insert(ru"", 0)

  if line < windowNode.currentLine: dec(windowNode.currentLine)
  if windowNode.currentLine >= bufStatus.buffer.len:
    windowNode.currentLine = bufStatus.buffer.high
  
  windowNode.currentColumn = 0
  windowNode.expandedColumn = 0

  inc(bufStatus.countChange)

proc deleteWord*(bufStatus: var BufferStatus, windowNode: WindowNode) =
  if bufStatus.buffer.len == 1 and
     bufStatus.buffer[windowNode.currentLine].len < 1: return
  elif bufStatus.buffer.len > 1 and
       bufStatus.buffer[windowNode.currentLine].len < 1:
    bufStatus.buffer.delete(windowNode.currentLine, windowNode.currentLine + 1)
    if windowNode.currentLine > bufStatus.buffer.high:
      windowNode.currentLine = bufStatus.buffer.high
  elif windowNode.currentColumn == bufStatus.buffer[windowNode.currentLine].high:
    let oldLine = bufStatus.buffer[windowNode.currentLine]
    var newLine = bufStatus.buffer[windowNode.currentLine]
    newLine.delete(windowNode.currentColumn)
    if oldLine != newLine: bufStatus.buffer[windowNode.currentLine] = newLine

    if windowNode.currentColumn > 0: dec(windowNode.currentColumn)
  else:
    let
      currentLine = windowNode.currentLine
      currentColumn = windowNode.currentColumn
      startWith = if bufStatus.buffer[currentLine].len == 0: ru'\n'
                  else: bufStatus.buffer[currentLine][currentColumn]
      isSkipped = if unicodeext.isPunct(startWith): unicodeext.isPunct elif
                     unicodeext.isAlpha(startWith): unicodeext.isAlpha elif
                     unicodeext.isDigit(startWith): unicodeext.isDigit
                  else: nil

    if isSkipped == nil:
      (windowNode.currentLine, windowNode.currentColumn) =
        bufStatus.buffer.next(currentLine, currentColumn)
    else:
      while true:
        inc(windowNode.currentColumn)
        if windowNode.currentColumn >= bufStatus.buffer[windowNode.currentLine].len:
          break
        if not isSkipped(bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn]):
          break

    while true:
      if windowNode.currentColumn > bufStatus.buffer[windowNode.currentLine].high:
        break
      let curr =
        bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn]
      if isPunct(curr) or isAlpha(curr) or isDigit(curr): break
      inc(windowNode.currentColumn)

    let oldLine = bufStatus.buffer[currentLine]
    var newLine = bufStatus.buffer[currentLine]
    for i in currentColumn ..< windowNode.currentColumn:
      newLine.delete(currentColumn)
    if oldLine != newLine: bufStatus.buffer[currentLine] = newLine
    windowNode.expandedColumn = currentColumn
    windowNode.currentColumn = currentColumn

  inc(bufStatus.countChange)

proc deleteCharacterUntilEndOfLine*(bufStatus: var BufferStatus,
                                    autoDeleteParen: bool,
                                    windowNode: WindowNode) =
                                    
  let
    currentLine = windowNode.currentLine
    startColumn = windowNode.currentColumn
  for i in startColumn ..< bufStatus.buffer[currentLine].len:
    bufStatus.deleteCurrentCharacter(windowNode, autoDeleteParen)

proc deleteCharacterBeginningOfLine*(bufStatus: var BufferStatus,
                                     autoDeleteParen: bool,
                                     windowNode: WindowNode) =
                                     
  let beforColumn = windowNode.currentColumn
  windowNode.currentColumn = 0
  windowNode.expandedColumn = 0
  for i in 0 ..< beforColumn:
    bufStatus.deleteCurrentCharacter(windowNode, autoDeleteParen)

proc deleteCharactersOfLine*(bufStatus: var BufferStatus,
                             autoDeleteParen: bool,
                             windowNode: WindowNode) =
                             
  let
    currentLine = windowNode.currentLine
    firstNonBlank = getFirstNonBlankOfLineOrFirstColumn(bufStatus, windowNode)
  windowNode.currentColumn = firstNonBlank
  windowNode.expandedColumn = firstNonBlank
  for _ in firstNonBlank ..< bufStatus.buffer[currentLine].len:
    bufStatus.deleteCurrentCharacter(windowNode, autoDeleteParen)

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
      if exitCode == 0:
        let cmd = "xclip -r <<" & "'" & delimiterStr & "'" & "\n" & buffer & "\n" & delimiterStr & "\n"
        discard execShellCmd(cmd)
    of wsl:
      let cmd = "clip.exe <<" & "'" & delimiterStr & "'" & "\n" & buffer & "\n"  & delimiterStr & "\n"
      discard execShellCmd(cmd)
    of mac:
      let cmd = "pbcopy <<" & "'" & delimiterStr & "'" & "\n" & buffer & "\n"  & delimiterStr & "\n"
      discard execShellCmd(cmd)
    else: discard

proc yankLines*(status: var EditorStatus, first, last: int) =
  status.registers.yankedStr = @[]
  status.registers.yankedLines = @[]

  let currentBufferIndex = status.bufferIndexInCurrentWindow

  for i in first .. last:
    status.registers.yankedLines.add(status.bufStatus[currentBufferIndex].buffer[i])

  status.commandWindow.writeMessageYankedLine(status.registers.yankedLines.len, status.messageLog)

proc pasteLines(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode
  for i in 0 ..< status.registers.yankedLines.len:
    status.bufStatus[currentBufferIndex].buffer.insert(status.registers.yankedLines[i],
                                                       windowNode.currentLine + i + 1)

  inc(status.bufStatus[currentBufferIndex].countChange)

proc yankString*(status: var EditorStatus, length: int) =
  status.registers.yankedLines = @[]
  status.registers.yankedStr = @[]

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  var windowNode =
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode
  for i in windowNode.currentColumn ..< length:
    let r = status.bufStatus[currentBufferIndex].buffer[windowNode.currentLine][i]
    status.registers.yankedStr.add(r)

  if status.settings.systemClipboard: status.registers.sendToClipboad(status.platform)

  block: 
    let strLen = status.registers.yankedStr.len
    status.commandWindow.writeMessageYankedCharactor(strLen, status.messageLog)

proc yankWord*(status: var Editorstatus, loop: int) =
  status.registers.yankedLines = @[]
  status.registers.yankedStr = @[]

  var windowNode =
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    line = status.bufStatus[currentBufferIndex].buffer[windowNode.currentLine]
  var startColumn = windowNode.currentColumn

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
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  var windowNode =
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

  let oldLine =
    status.bufStatus[currentBufferIndex].buffer[windowNode.currentLine]
  var newLine =
    status.bufStatus[currentBufferIndex].buffer[windowNode.currentLine]
  newLine.insert(status.registers.yankedStr, windowNode.currentColumn)
  if oldLine != newLine:
    status.bufStatus[currentBufferIndex].buffer[windowNode.currentLine] = newLine

  windowNode.currentColumn += status.registers.yankedStr.high - 1

  inc(status.bufStatus[currentBufferIndex].countChange)

proc pasteAfterCursor*(status: var EditorStatus) =
  if status.registers.yankedStr.len > 0:
    var windowNode =
      status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode
    windowNode.currentColumn.inc
    pasteString(status)
  elif status.registers.yankedLines.len > 0:
    pasteLines(status)

proc pasteBeforeCursor*(status: var EditorStatus) =
  if status.registers.yankedLines.len > 0:
    pasteLines(status)
  elif status.registers.yankedStr.len > 0:
    pasteString(status)

from insertmode import keyEnter

proc replaceCurrentCharacter*(bufStatus: var BufferStatus,
                              windowNode: WindowNode,
                              autoIndent, autoDeleteParen: bool,
                              character: Rune) =

  if isEnterKey(character):
    bufStatus.deleteCurrentCharacter(windowNode, autoDeleteParen)
    keyEnter(bufStatus, windowNode, autoIndent)
  else:
    let oldLine = bufStatus.buffer[windowNode.currentLine]
    var newLine = bufStatus.buffer[windowNode.currentLine]
    newLine[windowNode.currentColumn] = character
    if oldLine != newLine: bufStatus.buffer[windowNode.currentLine] = newLine

    inc(bufStatus.countChange)

proc addIndent*(bufStatus: var BufferStatus,
                windowNode: WindowNode,
                tabStop: int) =
                
  let oldLine = bufStatus.buffer[windowNode.currentLine]
  var newLine = bufStatus.buffer[windowNode.currentLine]
  newLine.insert(newSeqWith(tabStop, ru' '))
  if oldLine != newLine: bufStatus.buffer[windowNode.currentLine] = newLine

  inc(bufStatus.countChange)

proc deleteIndent*(bufStatus: var BufferStatus,
                   windowNode: WindowNode,
                   tabStop: int) =
                   
  if bufStatus.buffer.len == 0: return

  if bufStatus.buffer[windowNode.currentLine][0] == ru' ':
    for i in 0 ..< tabStop:
      if bufStatus.buffer.len == 0 or
         bufStatus.buffer[windowNode.currentLine][0] != ru' ': break
      let oldLine = bufStatus.buffer[windowNode.currentLine]
      var newLine = bufStatus.buffer[windowNode.currentLine]
      newLine.delete(0, 0)
      if oldLine != newLine: bufStatus.buffer[windowNode.currentLine] = newLine
  inc(bufStatus.countChange)

proc joinLine*(bufStatus: var BufferStatus, windowNode: WindowNode) =
  if windowNode.currentLine == bufStatus.buffer.len - 1 or
     bufStatus.buffer[windowNode.currentLine + 1].len < 1: return

  let oldLine = bufStatus.buffer[windowNode.currentLine]
  var newLine = bufStatus.buffer[windowNode.currentLine]
  newLine.add(bufStatus.buffer[windowNode.currentLine + 1])
  if oldLine != newLine: bufStatus.buffer[windowNode.currentLine] = newLine

  bufStatus.buffer.delete(windowNode.currentLine + 1,
                          windowNode.currentLine + 1)

  inc(bufStatus.countChange)
