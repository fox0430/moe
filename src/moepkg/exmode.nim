import sequtils, strutils, os, terminal, packages/docutils/highlite, times
import editorstatus, ui, normalmode, gapbuffer, fileutils, editorview, unicodeext, independentutils, searchmode, highlight, commandview

type replaceCommandInfo = tuple[searhWord: seq[Rune], replaceWord: seq[Rune]]

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
    if command[i] == '/': break
    replaceWord.add(command[i])

  return (searhWord: searchWord, replaceWord: replaceWord)

proc isOpenMessageLogViweer(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"log"

proc isOpenBufferManager(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"buf"

proc isChangeCursorLineCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"cursorLine"

proc isListAllBufferCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"ls"

proc isWriteAndQuitAllBufferCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"wqa"

proc isForceAllBufferQuitCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"qa!"

proc isAllBufferQuitCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"qa"

proc isVerticalSplitWindowCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"vs"

proc isHorizontalSplitWindowCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"sv"

proc isLiveReloadOfConfSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"livereload"

proc isChangeThemeSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru "theme"

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

proc isRealtimeSearchSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"realtimesearch"

proc isTurnOffHighlightingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"noh"

proc isDeleteCurrentBufferStatusCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"bd"

proc isDeleteBufferStatusCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"bd" and isDigit(command[1])

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
  return command.len == 1 and isDigit(command[0]) and status.bufStatus[status.currentBuffer].prevMode == Mode.normal

proc isEditCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"e"

proc isWriteCommand(status: EditorStatus, command: seq[seq[Rune]]): bool =
  return command.len in {1, 2} and command[0] == ru"w" and status.bufStatus[status.currentBuffer].prevMode == Mode.normal

proc isQuitCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"q"

proc isWriteAndQuitCommand(status: EditorStatus, command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"wq" and status.bufStatus[status.currentBuffer].prevMode == Mode.normal

proc isForceQuitCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"q!"

proc isShellCommand(command: seq[seq[Rune]]): bool =
  return command.len >= 1 and command[0][0] == ru'!'

proc isReplaceCommand(command: seq[seq[Rune]]): bool =
  return command.len >= 1  and command[0].len > 4 and command[0][0 .. 2] == ru"%s/"

proc openMessageMessageLogViewer(status: var Editorstatus) =
  status.changeMode(status.bufStatus[status.currentBuffer].prevMode)
  status.verticalSplitWindow
  status.moveNextWindow
  status.addNewBuffer("")
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(Mode.logviewer)

proc openBufferManager(status: var Editorstatus) =
  status.changeMode(status.bufStatus[status.currentBuffer].prevMode)
  status.verticalSplitWindow
  status.moveNextWindow
  status.addNewBuffer("")
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(Mode.bufManager)

proc changeCursorLineCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on" : status.settings.cursorLine = true 
  elif command == ru"off": status.settings.cursorLine = false
  status.changeMode(status.bufStatus[status.currentBuffer].prevMode)

proc verticalSplitWindowCommand(status: var EditorStatus) =
  status.verticalSplitWindow
  status.changeMode(status.bufStatus[status.currentBuffer].prevMode)

proc horizontalSplitWindowCommand(status: var Editorstatus) =
  status.horizontalSplitWindow
  status.changeMode(status.bufStatus[status.currentBuffer].prevMode)

proc liveReloadOfConfSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru "on": status.settings.liveReloadOfConf = true
  elif command == ru"off": status.settings.liveReloadOfConf = false

  status.commandWindow.erase
  status.changeMode(status.bufStatus[status.currentBuffer].prevMode)

proc changeThemeSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"dark": status.settings.editorColorTheme = ColorTheme.dark
  elif command == ru"light": status.settings.editorColorTheme = ColorTheme.light
  elif command == ru"vivid": status.settings.editorColorTheme = ColorTheme.vivid
  elif command == ru"config": status.settings.editorColorTheme = ColorTheme.config

  changeTheme(status)
  status.resize(terminalHeight(), terminalWidth())
  status.commandWindow.erase
  status.changeMode(status.bufStatus[status.currentBuffer].prevMode)

proc tabLineSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.tabLine.useTab = true
  elif command == ru"off": status.settings.tabLine.useTab = false

  status.resize(terminalHeight(), terminalWidth())
  status.commandWindow.erase

proc syntaxSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.syntax = true
  elif command == ru"off": status.settings.syntax = false

  let sourceLang = if status.settings.syntax: status.bufStatus[status.currentBuffer].language else: SourceLanguage.langNone
  status.bufStatus[status.currentBuffer].highlight = initHighlight($status.bufStatus[status.currentBuffer].buffer, sourceLang)

  status.commandWindow.erase
  status.changeMode(status.bufStatus[status.currentBuffer].prevMode)

proc tabStopSettingCommand(status: var EditorStatus, command: int) =
  status.settings.tabStop = command

  status.commandWindow.erase
  status.changeMode(status.bufStatus[status.currentBuffer].prevMode)

proc autoCloseParenSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.autoCloseParen = true
  elif command == ru"off": status.settings.autoCloseParen = false

  status.commandWindow.erase
  status.changeMode(status.bufStatus[status.currentBuffer].prevMode)

proc autoIndentSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.autoIndent = true
  elif command == ru"off": status.settings.autoIndent = false

  status.commandWindow.erase
  status.changeMode(status.bufStatus[status.currentBuffer].prevMode)

proc lineNumberSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru "on": status.settings.lineNumber = true
  elif command == ru"off": status.settings.lineNumber = false

  let numberOfDigitsLen = if status.settings.lineNumber: numberOfDigits(status.bufStatus[0].buffer.len) - 2 else: 0
  let useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
  status.bufStatus[status.currentBuffer].view = initEditorView(status.bufStatus[0].buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numberOfDigitsLen)

  status.commandWindow.erase
  status.changeMode(status.bufStatus[status.currentBuffer].prevMode)

proc statusBarSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.statusBar.useBar = true
  elif command == ru"off": status.settings.statusBar.useBar = false

  let numberOfDigitsLen = if status.settings.lineNumber: numberOfDigits(status.bufStatus[0].buffer.len) - 2 else: 0
  let useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
  status.bufStatus[status.currentBuffer].view = initEditorView(status.bufStatus[0].buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numberOfDigitsLen)

  status.commandWindow.erase
  status.changeMode(status.bufStatus[status.currentBuffer].prevMode)

proc realtimeSearchSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.realtimeSearch= true
  elif command == ru"off": status.settings.realtimeSearch = false

  status.commandWindow.erase
  status.changeMode(status.bufStatus[status.currentBuffer].prevMode)

proc turnOffHighlightingCommand(status: var EditorStatus) =
  turnOffHighlighting(status)

  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc deleteBufferStatusCommand(status: var EditorStatus, index: int) =
  if index < 0 or index > status.bufStatus.high:
    status.commandWindow.writeNoBufferDeletedError(status.messageLog)
    status.changeMode(Mode.normal)
    return

  status.bufStatus.delete(index)

  if status.bufStatus.len == 0: addNewBuffer(status, "")
  elif index == status.currentBuffer:
    dec(status.currentBuffer)
    if status.bufStatus.high < index: changeCurrentBuffer(status, index - 1)
    else: changeCurrentBuffer(status, index)
  elif index < status.currentBuffer: dec(status.currentBuffer)

  if status.bufStatus[status.currentBuffer].mode == Mode.ex: status.changeMode(status.bufStatus[status.currentBuffer].prevMode)
  else:
    status.commandWindow.erase
    status.changeMode(status.bufStatus[status.currentBuffer].mode)

proc changeFirstBufferCommand(status: var EditorStatus) =
  changeCurrentBuffer(status, 0)

  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc changeLastBufferCommand(status: var EditorStatus) =
  changeCurrentBuffer(status, status.bufStatus.high)

  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc opneBufferByNumberCommand(status: var EditorStatus, number: int) =
  if number < 0 or number > status.bufStatus.high: return

  changeCurrentBuffer(status, number)
  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc changeNextBufferCommand(status: var EditorStatus) =
  if status.currentBuffer == status.bufStatus.high: return

  changeCurrentBuffer(status, status.currentBuffer + 1)
  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc changePreveBufferCommand(status: var EditorStatus) =
  if status.currentBuffer < 1: return

  changeCurrentBuffer(status, status.currentBuffer - 1)

  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc jumpCommand(status: var EditorStatus, line: int) =
  jumpLine(status, line)

  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc editCommand(status: var EditorStatus, filename: seq[Rune]) = discard
#  status.changeMode(Mode.normal)
#
#  if status.bufStatus[status.currentBuffer].countChange > 0 or countReferencedWindow(status.mainWindowInfo, status.currentBuffer) == 0:
#    status.commandWindow.writeNoWriteError(status.messageLog)
#  else:
#    if existsDir($filename):
#      try: setCurrentDir($filename)
#      except OSError:
#        status.commandWindow.writeFileOpenError($filename, status.messageLog)
#        addNewBuffer(status, "")
#      status.bufStatus.add(BufferStatus(mode: Mode.filer, lastSaveTime: now()))
#    else: addNewBuffer(status, $filename)
#
#    changeCurrentBuffer(status, status.bufStatus.high)

proc writeCommand(status: var EditorStatus, filename: seq[Rune]) =
  if filename.len == 0:
    status.commandWindow.writeNoFileNameError(status.messageLog)
    status.changeMode(Mode.normal)
    return

  try:
    saveFile(filename, status.bufStatus[status.currentBuffer].buffer.toRunes, status.settings.characterEncoding)
    let bufferIndex = status.currentMainWindowNode.bufferIndex
    status.bufStatus[bufferIndex].filename = filename
    status.bufStatus[status.currentBuffer].countChange = 0
  except IOError:
    status.commandWindow.writeSaveError(status.messageLog)

  status.commandWindow.writeMessageSaveFile(filename, status.messageLog)
  status.changeMode(Mode.normal)

proc quitCommand(status: var EditorStatus) = discard
#  if status.bufStatus[status.currentBuffer].countChange == 0 or countReferencedWindow(status.mainWindowInfo, status.currentBuffer) > 1:
#    status.closeWindow
#    status.changeMode(Mode.normal)
#  else:
#    status.commandWindow.writeNoWriteError(status.messageLog)
#    status.changeMode(Mode.normal)

proc writeAndQuitCommand(status: var EditorStatus) =
  try:
    status.bufStatus[status.currentBuffer].countChange = 0
    saveFile(status.bufStatus[status.currentBuffer].filename, status.bufStatus[status.currentBuffer].buffer.toRunes, status.settings.characterEncoding)
    status.closeWindow
  except IOError:
    status.commandWindow.writeSaveError(status.messageLog)

  status.changeMode(Mode.normal)

proc forceQuitCommand(status: var EditorStatus) =
  status.closeWindow
  status.changeMode(Mode.normal)

proc allBufferQuitCommand(status: var EditorStatus) = discard
#  for i in 0 ..< status.numOfMainWindow:
#    if status.bufStatus[status.mainWindowInfo[0].bufferIndex].countChange > 0:
#      status.commandWindow.writeNoWriteError(status.messageLog)
#      status.changeMode(Mode.normal)
#      return
#
#  for i in 0 ..< status.mainWindowInfo.len: closeWindow(status, 0)

proc forceAllBufferQuitCommand(status: var EditorStatus) = discard
#  for i in 0 ..< status.mainWindowInfo.len: closeWindow(status, 0)

proc writeAndQuitAllBufferCommand(status: var Editorstatus) = discard
#  for i in 0 ..< status.mainWindowInfo.len:
#    let bufIndex = status.mainWindowInfo[0].bufferIndex
#    try: saveFile(status.bufStatus[bufIndex].filename, status.bufStatus[bufIndex].buffer.toRunes, status.settings.characterEncoding)
#    except IOError:
#      status.commandWindow.writeSaveError(status.messageLog)
#      status.changeMode(Mode.normal)
#      return
#
#    closeWindow(status, i)

proc shellCommand(status: var EditorStatus, shellCommand: string) =
  saveCurrentTerminalModes()
  exitUi()

  discard execShellCmd(shellCommand)
  discard execShellCmd("printf \"\nPress Enter\"")
  discard execShellCmd("read _")

  restoreTerminalModes()
  status.commandWindow.erase
  status.commandWindow.refresh

proc listAllBufferCommand(status: var Editorstatus) =
  let swapCurrentBufferIndex = status.currentBuffer
  status.addNewBuffer("")
  status.changeCurrentBuffer(status.bufStatus.high)

  for i in 0 ..< status.bufStatus.high:
    var line = ru""
    let
      currentMode = status.bufStatus[i].mode
      prevMode = status.bufStatus[i].prevMode
    if currentMode == Mode.filer or (currentMode == Mode.ex and prevMode == Mode.filer): line = getCurrentDir().toRunes
    else: line = status.bufStatus[i].filename & ru"  line " & ($status.bufStatus[i].buffer.len).toRunes

    if i == 0: status.bufStatus[status.currentBuffer].buffer[0] = line
    else: status.bufStatus[status.currentBuffer].buffer.insert(line, i)

  let
    useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    useTab = if status.settings.tabLine.useTab: 1 else: 0
    swapCurrentLineNumStting = status.settings.currentLineNumber
  
  status.settings.currentLineNumber = false
  status.bufStatus[status.currentBuffer].view = initEditorView(status.bufStatus[status.currentBuffer].buffer, terminalHeight() - useStatusBar - useTab - 1, terminalWidth())
  status.bufStatus[status.currentBuffer].currentLine = 0

  status.updateHighlight

  while true:
    status.update
    setCursor(false)
    let key = getKey(status.currentMainWindowNode.window)
    if isResizekey(key): status.resize(terminalHeight(), terminalWidth())
    elif key.int == 0: discard
    else: break

  status.settings.currentLineNumber = swapCurrentLineNumStting
  status.changeCurrentBuffer(swapCurrentBufferIndex)
  status.deleteBufferStatusCommand(status.bufStatus.high)

  status.commandWindow.erase
  status.commandWindow.refresh

proc replaceBuffer(status: var EditorStatus, command: seq[Rune]) =
  let replaceInfo = parseReplaceCommand(command)

  if replaceInfo.searhWord == ru"'\n'" and status.bufStatus[status.currentBuffer].buffer.len > 1:
    let startLine = 0

    for i in 0 .. status.bufStatus[status.currentBuffer].buffer.high - 2:
      let oldLine = status.bufStatus[status.currentBuffer].buffer[startLine]
      var newLine = status.bufStatus[status.currentBuffer].buffer[startLine]
      newLine.insert(replaceInfo.replaceWord, status.bufStatus[status.currentBuffer].buffer[startLine].len)
      for j in 0 .. status.bufStatus[status.currentBuffer].buffer[startLine + 1].high:
        newLine.insert(status.bufStatus[status.currentBuffer].buffer[startLine + 1][j], status.bufStatus[status.currentBuffer].buffer[startLine].len)
      if oldLine != newLine: status.bufStatus[status.currentBuffer].buffer[startLine] = newLine

      status.bufStatus[status.currentBuffer].buffer.delete(startLine + 1, startLine + 1)
  else:
    for i in 0 .. status.bufStatus[status.currentBuffer].buffer.high:
      let searchResult = searchBuffer(status, replaceInfo.searhWord)
      if searchResult.line > -1:
        let oldLine = status.bufStatus[status.currentBuffer].buffer[searchResult.line]
        var newLine = status.bufStatus[status.currentBuffer].buffer[searchResult.line]
        newLine.delete(searchResult.column, searchResult.column + replaceInfo.searhWord.high)
        newLine.insert(replaceInfo.replaceWord, searchResult.column)
        if oldLine != newLine: status.bufStatus[status.currentBuffer].buffer[searchResult.line] = newLine

  inc(status.bufStatus[status.currentBuffer].countChange)
  status.commandWindow.erase
  status.changeMode(status.bufStatus[status.currentBuffer].prevMode)

proc exModeCommand*(status: var EditorStatus, command: seq[seq[Rune]]) =
  if command.len == 0 or command[0].len == 0:
    status.changeMode(status.bufStatus[status.currentBuffer].prevMode)
  elif isJumpCommand(status, command):
    var line = ($command[0]).parseInt-1
    if line < 0: line = 0
    if line >= status.bufStatus[status.currentBuffer].buffer.len: line = status.bufStatus[status.currentBuffer].buffer.high
    jumpCommand(status, line)
  elif isEditCommand(command):
    editCommand(status, command[1].normalizePath)
  elif isWriteCommand(status, command):
    writeCommand(status, if command.len < 2: status.bufStatus[status.currentBuffer].filename else: command[1])
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
  elif isChangeThemeSettingCommand(command):
    changeThemeSettingCommand(status, command[1])
  elif isChangeCursorLineCommand(command):
    changeCursorLineCommand(status, command[1])
  elif isVerticalSplitWindowCommand(command):
    verticalSplitWindowCommand(status)
  elif isHorizontalSplitWindowCommand(command):
    horizontalSplitWindowCommand(status)
  elif isAllBufferQuitCommand(command):
    allBufferQuitCommand(status)
  elif isForceAllBufferQuitCommand(command):
    forceAllBufferQuitCommand(status)
  elif isWriteAndQuitAllBufferCommand(command):
    writeAndQuitAllBufferCommand(status)
  elif isListAllBufferCommand(command):
    listAllBufferCommand(status)
  elif isOpenBufferManager(command):
    openBufferManager(status)
  elif isLiveReloadOfConfSettingCommand(command):
    liveReloadOfConfSettingCommand(status, command[1])
  elif isRealtimeSearchSettingCommand(command):
    realtimeSearchSettingCommand(status, command[1])
  elif isOpenMessageLogViweer(command):
    openMessageMessageLogViewer(status)
  else:
    status.commandWindow.writeNotEditorCommandError(command, status.messageLog)
    status.changeMode(status.bufStatus[status.currentBuffer].prevMode)

proc exMode*(status: var EditorStatus) =
  const prompt = ":"
  var
    command = ru""
    exitInput = false
    cancelInput = false
    isSuggest = true

  status.searchHistory.add(ru"")

  while exitInput == false:
    let returnWord = status.getKeyOnceAndWriteCommandView(prompt, command, isSuggest)

    command = returnWord[0]
    exitInput = returnWord[1]
    cancelInput = returnWord[2]

    if cancelInput or exitInput: break
    elif status.settings.replaceTextHighlight and  command.len > 3 and command.startsWith(ru"%s/"):
      var keyword = ru""
      for i in 3 ..< command.len :
          if command[i] == ru'/': break
          keyword.add(command[i])
      status.searchHistory[status.searchHistory.high] = keyword
      let bufferIndex = status.currentMainWindowNode.bufferIndex
      status.bufStatus[bufferIndex].isHighlight = true
    else:
      let bufferIndex = status.currentMainWindowNode.bufferIndex
      status.bufStatus[bufferIndex].isHighlight = false

    status.updateHighlight
    status.resize(terminalHeight(), terminalWidth())
    status.update

  status.searchHistory.delete(status.searchHistory.high)
  let bufferIndex = status.currentMainWindowNode.bufferIndex
  status.bufStatus[bufferIndex].isHighlight = false
  status.updateHighlight

  if cancelInput:
    status.commandWindow.erase
    status.changeMode(status.bufStatus[status.currentBuffer].prevMode)
  else:
    status.bufStatus[status.currentBuffer].buffer.beginNewSuitIfNeeded
    status.bufStatus[status.currentBuffer].tryRecordCurrentPosition

    exModeCommand(status, splitCommand($command))
