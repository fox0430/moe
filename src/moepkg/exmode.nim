import sequtils, strutils, os, terminal, strformat, deques
import editorstatus, ui, normalmode, gapbuffer, fileutils, editorview, unicodeext, independentutils, searchmode, highlight, commandview

type
  replaceCommandInfo = tuple[searhWord: seq[Rune], replaceWord: seq[Rune]]

proc parseReplaceCommand(command: seq[Rune]): replaceCommandInfo =
  var numOfSlash = 0
  for i in 0 .. command.high:
    if command[i] == '/': numOfSlash.inc
  if numOfSlash == 0: return

  var searchWord = ru""
  var startReplaceWordIndex = 0
  for i in 0 .. command.high:
    if command[i] == '/':
      startReplaceWordIndex = i + 1
      break
    searchWord.add(command[i])
  if searchWord.len == 0: return

  var replaceWord = ru""
  for i in startReplaceWordIndex .. command.high:
    if command[i] == '/':
      break
    replaceWord.add(command[i])
  
  return (searhWord: searchWord, replaceWord: replaceWord)

proc isJumpCommand(status: EditorStatus, command: seq[seq[Rune]]): bool =
  return command.len == 1 and isDigit(command[0]) and status.prevMode == Mode.normal

proc isEditCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"e"

proc isWriteCommand(status: EditorStatus, command: seq[seq[Rune]]): bool =
  return command.len in {1, 2} and command[0] == ru"w" and status.prevMode == Mode.normal

proc isQuitCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"q"

proc isWriteAndQuitCommand(status: EditorStatus, command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"wq" and status.prevMode == Mode.normal

proc isForceQuitCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"q!"

proc isShellCommand(command: seq[seq[Rune]]): bool =
  return command.len >= 1 and command[0][0] == ru'!'

proc isReplaceCommand(command: seq[seq[Rune]]): bool =
  return command.len >= 1  and command[0].len > 4 and command[0][0 .. 2] == ru"%s/"

proc jumpCommand(status: var EditorStatus, line: int) =
  jumpLine(status, line)
  status.changeMode(Mode.normal)

proc editCommand(status: var EditorStatus, filename: seq[Rune]) =
  if status.countChange != 0:
    writeNoWriteError(status.commandWindow)
    status.changeMode(Mode.normal)
    return

  if existsDir($filename):
    setCurrentDir($filename)
    status.changeMode(Mode.filer)
  else:
    status = initEditorStatus()
    status.filename = filename
    status.language = detectLanguage($filename)
    if existsFile($status.filename):
      try:
        let textAndEncoding = openFile(status.filename)
        status.buffer = textAndEncoding.text.toGapBuffer
        status.settings.characterEncoding = textAndEncoding.encoding
      except IOError:
        #writeFileOpenErrorMessage(status.commandWindow, status.filename)
        status.buffer = newFile()
    else:
      status.buffer = newFile()

    let numberOfDigitsLen = if status.settings.lineNumber: numberOfDigits(status.buffer.len) - 2 else: 0
    let useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    status.updateHighlight
    status.view = initEditorView(status.buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numberOfDigitsLen)

proc writeCommand(status: var EditorStatus, filename: seq[Rune]) =
  if filename.len == 0:
    status.commandWindow.erase
    status.commandWindow.write(0, 0, "Error: No file name", ColorPair.redDefault)
    status.commandWindow.refresh
    status.changeMode(Mode.normal)
    return

  try:
    saveFile(filename, status.buffer.toRunes, status.settings.characterEncoding)
    status.filename = filename
    status.countChange = 0
  except IOError:
    writeSaveError(status.commandWindow)

  status.changeMode(Mode.normal)

proc quitCommand(status: var EditorStatus) =
  if status.countChange == 0: status.changeMode(Mode.quit)
  else:
    writeNoWriteError(status.commandWindow)
    status.changeMode(Mode.normal)

proc writeAndQuitCommand(status: var EditorStatus) =
  try:
    saveFile(status.filename, status.buffer.toRunes, status.settings.characterEncoding)
    status.changeMode(Mode.quit)
  except IOError:
    writeSaveError(status.commandWindow)
    status.changeMode(Mode.normal)

proc forceQuitCommand(status: var EditorStatus) =
  status.changeMode(Mode.quit)

proc shellCommand(status: var EditorStatus, shellCommand: string) =
  saveCurrentTerminalModes()
  exitUi()

  discard execShellCmd(shellCommand)
  discard execShellCmd("printf \"\nPress Enter\"")
  discard execShellCmd("read _")

  restoreTerminalModes()
  status.commandWindow.erase
  status.commandWindow.refresh

proc replaceBuffer(status: var EditorStatus, command: seq[Rune]) =

  let replaceInfo = parseReplaceCommand(command)

  if replaceInfo.searhWord == ru"'\n'" and status.buffer.len > 1:
    let
      startLine = 0
      endLine = status.buffer.high

    for i in 0 .. status.buffer.high - 2:
      status.buffer[startLine].insert(replaceInfo.replaceWord, status.buffer[startLine].len)
      for j in 0 .. status.buffer[startLine + 1].high:
        status.buffer[startLine].insert(status.buffer[startLine + 1][j], status.buffer[startLine].len)
      status.buffer.delete(startLine + 1, startLine + 2)
  else:
    for i in 0 .. status.buffer.high:
      let searchResult = searchBuffer(status, replaceInfo.searhWord)
      if searchResult.line > -1:
        status.buffer[searchResult.line].delete(searchResult.column, searchResult.column + replaceInfo.searhWord.high)
        status.buffer[searchResult.line].insert(replaceInfo.replaceWord, searchResult.column)

  inc(status.countChange)
  status.changeMode(status.prevMode)

proc exModeCommand(status: var EditorStatus, command: seq[seq[Rune]]) =
  if isJumpCommand(status, command):
    var line = ($command[0]).parseInt-1
    if line < 0: line = 0
    if line >= status.buffer.len: line = status.buffer.high
    jumpCommand(status, line)
  elif isEditCommand(command):
    editCommand(status, command[1].normalizePath)
  elif isWriteCommand(status, command):
    writeCommand(status, if command.len < 2: status.filename else: command[1])
  elif isQuitCommand(command):
    quitCommand(status)
  elif isWriteAndQuitCommand(status, command):
    writeAndQuitCommand(status)
  elif isForceQuitCommand(command):
    forceQuitCommand(status)
  elif isShellCommand(command):
    shellCommand(status, command.join(" ").substr(1))
  elif isReplaceCommand(command):
    replaceBuffer(status, command[0][3 .. command[0].high])
  else:
    status.changeMode(status.prevMode)

proc exMode*(status: var EditorStatus) =
  let command = getCommand(status, ":")
  exModeCommand(status, command)
