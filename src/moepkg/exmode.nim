import sequtils, strutils, os, terminal, strformat, deques
import editorstatus, ui, normalmode, gapbuffer, fileutils, editorview, unicodeext, independentutils, searchmode, highlight, commandview, mainview

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

proc isTabLineSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"tab"
  
proc isSyntaxSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"syntax"

proc isTabStopSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"tabstop" and isDigit(command[1])

proc isAutoCloseParenSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"paren"

proc isAutoIndentSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"indent"

proc isLineNumberSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"linenum"

proc isStatusBarSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"statusbar"

proc isTurnOffHighlightingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"noh"

proc isDeleteCurrentBufferStatusCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"bd"

proc isDeleteBufferStatusCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"bd" and isDigit(command[1])

proc isBufferListCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"ls"

proc isChangeFirstBufferCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"bfirst"

proc isChangeLastBufferCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"blast"

proc isOpneBufferByNumber(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"b" and isDigit(command[1])

proc isChangeNextBufferCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"bnext"

proc isChangePreveBufferCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"bprev"

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

proc tabLineSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.tabLine.useTab = true
  elif command == ru"off": status.settings.tabLine.useTab = false

  status.resize(terminalHeight(), terminalWidth())

## DOES NOT WORKS ##
proc syntaxSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.syntax = true
  elif command == ru"off": status.settings.syntax = false

  status.changeMode(status.prevMode)

proc tabStopSettingCommand(status: var EditorStatus, command: int) =
  status.settings.tabStop = command

  status.changeMode(status.prevMode)

proc autoCloseParenSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.autoCloseParen = true
  elif command == ru"off": status.settings.autoCloseParen = false

  status.changeMode(status.prevMode)

proc autoIndentSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.autoIndent = true
  elif command == ru"off": status.settings.autoIndent = false

  status.changeMode(status.prevMode)

proc lineNumberSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru "on": status.settings.lineNumber = true
  elif command == ru"off": status.settings.lineNumber = false

  let numberOfDigitsLen = if status.settings.lineNumber: numberOfDigits(status.bufStatus[0].buffer.len) - 2 else: 0
  let useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
  status.view = initEditorView(status.bufStatus[0].buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numberOfDigitsLen)

  status.changeMode(status.prevMode)

proc statusBarSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.statusBar.useBar = true
  elif command == ru"off": status.settings.statusBar.useBar = false

  let numberOfDigitsLen = if status.settings.lineNumber: numberOfDigits(status.bufStatus[0].buffer.len) - 2 else: 0
  let useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
  status.view = initEditorView(status.bufStatus[0].buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numberOfDigitsLen)

  status.changeMode(status.prevMode)

proc turnOffHighlightingCommand(status: var EditorStatus) =
  turnOffHighlighting(status)
  status.changeMode(Mode.normal)

proc deleteBufferStatusCommand(status: var EditorStatus, index: int) =
  if index < 0 and index > status.bufStatus.high: return 

  status.bufStatus.delete(index)

  if status.bufStatus.len == 0:
    status.bufStatus.add(BufferStatus(filename: ru""))
    status.bufStatus[0].buffer = newFile()
    status.bufStatus[0].highlight = initHighlight($status.bufStatus[0].buffer, status.bufStatus[0].language)
    let numberOfDigitsLen = if status.settings.lineNumber: numberOfDigits(status.bufStatus[0].buffer.len) - 2 else: 0
    let useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    status.bufStatus[0].view = initEditorView(status.bufStatus[0].buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numberOfDigitsLen)
    changeCurrentBuffer(status, 0)
  elif index == status.currentBuffer:
    dec(status.currentBuffer)
    if status.bufStatus.high < index:
      changeCurrentBuffer(status, index - 1)
    else: changeCurrentBuffer(status, index)
  elif index < status.currentBuffer:
    dec(status.currentBuffer)

  status.changeMode(Mode.normal)

proc bufferListCommand(status: var EditorStatus) =
  bufferListView(status)
  discard getKey(status.mainWindow)
  status.changeMode(Mode.normal)

proc changeFirstBufferCommand(status: var EditorStatus) =
  changeCurrentBuffer(status, 0)
  status.changeMode(Mode.normal)

proc changeLastBufferCommand(status: var EditorStatus) =
  changeCurrentBuffer(status, status.bufStatus.high)
  status.changeMode(Mode.normal)

proc opneBufferByNumberCommand(status: var EditorStatus, number: int) =
  if number < 0 or number > status.bufStatus.high: return

  changeCurrentBuffer(status, number)
  status.changeMode(Mode.normal)

proc changeNextBufferCommand(status: var EditorStatus) =
  if status.currentBuffer == status.bufStatus.high: return

  changeCurrentBuffer(status, status.currentBuffer + 1)
  status.changeMode(Mode.normal)

proc changePreveBufferCommand(status: var EditorStatus) =
  if status.currentBuffer < 1: return

  changeCurrentBuffer(status, status.currentBuffer - 1)
  status.changeMode(Mode.normal)

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
    status.bufStatus.add(BufferStatus(filename: filename))
    status.bufStatus[status.bufStatus.high].language = detectLanguage($filename)
    if existsFile($filename):
      try:
        let textAndEncoding = openFile(filename)
        status.bufStatus[status.bufStatus.high].buffer = textAndEncoding.text.toGapBuffer
        status.settings.characterEncoding = textAndEncoding.encoding
      except IOError:
        #writeFileOpenErrorMessage(status.commandWindow, status.filename)
        status.bufStatus[status.bufStatus.high].buffer = newFile()
    else:
      status.bufStatus[status.bufStatus.high].buffer = newFile()

    let numberOfDigitsLen = if status.settings.lineNumber: numberOfDigits(status.bufStatus[status.bufStatus.high].buffer.len) - 2 else: 0
    let useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    status.bufStatus[status.bufStatus.high].highlight = initHighlight($status.bufStatus[status.bufStatus.high].buffer, status.bufStatus[status.bufStatus.high].language)
    status.updateHighlight
    status.bufStatus[status.bufStatus.high].view = initEditorView(status.bufStatus[status.bufStatus.high].buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numberOfDigitsLen)

    changeCurrentBuffer(status, status.bufStatus.high)
    status.changeMode(Mode.normal)

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
  if command[0].len == 0:
    status.changeMode(status.prevMode)
  elif isJumpCommand(status, command):
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
  elif isChangeNextBufferCommand(command):
    changeNextBufferCommand(status)
  elif isChangePreveBufferCommand(command):
    changePreveBufferCommand(status)
  elif isOpneBufferByNumber(command):
    opneBufferByNumberCommand(status, ($command[1]).parseInt)
  elif isChangeFirstBufferCommand(command):
    changeFirstBufferCommand(status)
  elif isChangeLastBufferCommand(command):
    changeLastBufferCommand(status)
  elif isBufferListCommand(command):
    bufferListCommand(status)
  elif isDeleteBufferStatusCommand(command):
    deleteBufferStatusCommand(status, ($command[1]).parseInt)
  elif isDeleteCurrentBufferStatusCommand(command):
    deleteBufferStatusCommand(status, status.currentBuffer)
  elif isTurnOffHighlightingCommand(command):
    turnOffHighlightingCommand(status)
  elif isTabLineSettingCommand(command):
    tabLineSettingCommand(status, command[1])
  elif isStatusBarSettingCommand(command):
    statusBarSettingCommand(status, command[1])
  elif isLineNumberSettingCommand(command):
    lineNumberSettingCommand(status, command[1])
  elif isAutoIndentSettingCommand(command):
    autoIndentSettingCommand(status, command[1])
  elif isAutoCloseParenSettingCommand(command):
    autoCloseParenSettingCommand(status, command[1])
  elif isTabStopSettingCommand(command):
    tabStopSettingCommand(status, ($command[1]).parseInt)
  elif isSyntaxSettingCommand(command):
    syntaxSettingCommand(status, command[1])
  else:
    status.changeMode(status.prevMode)

proc exMode*(status: var EditorStatus) =
  let command = getCommand(status, ":")
  exModeCommand(status, command)
