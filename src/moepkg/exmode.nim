import sequtils, strutils, os, terminal, highlite, times
import editorstatus, ui, normalmode, gapbuffer, fileutils, editorview,
        unicodeext, independentutils, search, highlight, commandview,
        window, movement, color, build, bufferstatus, editor,
        settings, quickrun, messages

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

proc isPutConfigFileCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "putconfigfile"

proc isDeleteTrailingSpacesCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "deletetrailingspaces"

proc isOpenHelpCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "help"

proc isOpenMessageLogViweer(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "log"

proc isOpenBufferManager(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "buf"

proc isChangeCursorLineCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "cursorline"

proc isListAllBufferCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "ls"

proc isWriteAndQuitAllBufferCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "wqa"

proc isForceAllBufferQuitCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "qa!"

proc isAllBufferQuitCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "qa"

proc isVerticalSplitWindowCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "vs"

proc isHorizontalSplitWindowCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "sv"

proc isFilerIconSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "icon"

proc isLiveReloadOfConfSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "livereload"

proc isChangeThemeSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "theme"

proc isTabLineSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "tab"

proc isSyntaxSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "syntax"

proc isTabStopSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "tabstop" and isDigit(command[1])

proc isAutoCloseParenSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "paren"

proc isAutoIndentSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "indent"

proc isIndentationLinesSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "indentationlines"

proc isLineNumberSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "linenum"

proc isStatusBarSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "statusbar"

proc isIncrementalSearchSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "incrementalsearch"

proc isHighlightPairOfParenSettigCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "highlightparen"

proc isAutoDeleteParenSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "deleteparen"

proc isSmoothScrollSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "smoothscroll"

proc isSmoothScrollSpeedSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "scrollspeed" and isDigit(command[1])

proc isHighlightCurrentWordSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "highlightcurrentword"

proc isSystemClipboardSettingCommand(command: seq[seq[RUne]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "clipboard"

proc isHighlightFullWidthSpaceSettingCommand(command: seq[seq[RUne]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "highlightfullspace"

proc isMultipleStatusBarSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "multiplestatusbar"

proc isBuildOnSaveSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "buildonsave"

proc isShowGitInInactiveSettingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "showgitinactive"

proc isTurnOffHighlightingCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "noh"

proc isDeleteCurrentBufferStatusCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "bd"

proc isDeleteBufferStatusCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "bd" and isDigit(command[1])

proc isChangeFirstBufferCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "bfirst"

proc isChangeLastBufferCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "blast"

proc isOpenBufferByNumber(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "b" and isDigit(command[1])

proc isChangeNextBufferCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "bnext"

proc isChangePreveBufferCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "bprev"

proc isJumpCommand(status: EditorStatus, command: seq[seq[Rune]]): bool =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    prevMode = status.bufStatus[currentBufferIndex].prevMode
  return command.len == 1 and
         isDigit(command[0]) and
         (prevMode == Mode.normal or
         prevMode == Mode.logviewer)

proc isEditCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"e"

proc isOpenInHorizontalSplitWindowCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len > 0 and command.len < 3 and cmd == "sp"

proc isOpenInVerticalSplitWindowCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"vs"

proc isWriteCommand(status: EditorStatus, command: seq[seq[Rune]]): bool =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    cmd = toLowerAscii($command[0])
  return command.len in {1, 2} and
         cmd == "w" and
         status.bufStatus[currentBufferIndex].prevMode == Mode.normal

proc isQuitCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"q"

proc isWriteAndQuitCommand(status: EditorStatus, command: seq[seq[Rune]]): bool =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    cmd = toLowerAscii($command[0])
  return command.len == 1 and
         cmd == "wq" and
         status.bufStatus[currentBufferIndex].prevMode == Mode.normal

proc isForceQuitCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "q!"

proc isShellCommand(command: seq[seq[Rune]]): bool =
  return command.len >= 1 and command[0][0] == ru'!'

proc isReplaceCommand(command: seq[seq[Rune]]): bool =
  return command.len >= 1  and command[0].len > 4 and command[0][0 .. 2] == ru"%s/"

proc isWorkspaceListCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "lsw"

proc isCreateWorkSpaceCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "cws"

proc isDeleteCurrentWorkSpaceCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "dws"

proc isChangeCurrentWorkSpace(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 2 and cmd == "ws" and isDigit(command[1])

proc isCreateNewEmptyBufferCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "ene"

proc isNewEmptyBufferInSplitWindowHorizontally(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "new"

proc isNewEmptyBufferInSplitWindowVertically(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "vnew"

proc isQuickRunCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and (cmd == "run" or command[0] == ru"Q")

proc isRecentFileModeCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "recent"

proc isHistoryManagerCommand(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "history"

proc isStartConfigMode(command: seq[seq[Rune]]): bool =
  let cmd = toLowerAscii($command[0])
  return command.len == 1 and cmd == "conf"

proc startConfigMode(status: var Editorstatus) =
  let bufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[bufferIndex].prevMode)

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer(Mode.config)
  status.changeCurrentBuffer(status.bufStatus.high)

proc startHistoryManager(status: var Editorstatus) =
  let bufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[bufferIndex].prevMode)
  status.prevBufferIndex = bufferIndex

  if status.bufStatus[bufferIndex].mode != Mode.normal: return
  for bufStatus in status.bufStatus:
    if bufStatus.mode == Mode.history: return

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer(Mode.history)
  status.changeCurrentBuffer(status.bufStatus.high)

proc startRecentFileMode(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  # :recent is only supported on GNU/Linux
  if status.platform != Platform.linux: return

  if not existsFile(getHomeDir() / ".local/share/recently-used.xbel"):
    status.commandWindow.writeOpenRecentlyUsedXbelError(status.messageLog)
    return

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer("")
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(Mode.recentFile)

proc runQuickRunCommand(status: var Editorstatus) =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    windowNode = status.workspace[workspaceIndex].currentMainWindowNode

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  let
    buffer = runQuickRun(status.bufStatus[windowNode.bufferIndex],
                         status.commandwindow,
                         status.messageLog,
                         status.settings)

    workspace = status.workspace[workspaceIndex]
    quickRunWindowIndex = status.bufStatus.getQuickRunBufferIndex(workspace)

  if quickRunWindowIndex == -1:
    status.verticalSplitWindow
    status.resize(terminalHeight(), terminalWidth())
    status.moveNextWindow

    status.addNewBuffer("")
    status.bufStatus[^1].buffer = initGapBuffer(buffer)

    status.changeCurrentBuffer(status.bufStatus.high)

    status.changeMode(Mode.quickRun)
  else:
    status.bufStatus[quickRunWindowIndex].buffer = initGapBuffer(buffer)

proc staticReadVersionFromConfigFileExample(): string {.compileTime.} =
  staticRead(currentSourcePath.parentDir() / "../../example/moerc.toml")

proc putConfigFileCommand(status: var Editorstatus) =
  let
    homeDir = getHomeDir()
    currentBufferIndex = status.bufferIndexInCurrentWindow

  if not existsDir(homeDir / ".config"):
    try: createDir(homeDir / ".config")
    except OSError:
      status.commandWindow.writePutConfigFileError(status.messageLog)
      status.changeMode(status.bufStatus[currentBufferIndex].prevMode)
      return
  if not existsDir(homeDir / ".config" / "moe"):
    try: createDir(homeDir / ".config" / "moe")
    except OSError:
      status.commandWindow.writePutConfigFileError(status.messageLog)
      status.changeMode(status.bufStatus[currentBufferIndex].prevMode)
      return

  if existsFile(getHomeDir() / ".config" / "moe" / "moerc.toml"):
    status.commandWindow.writePutConfigFileAlreadyExistError(status.messageLog)
    status.changeMode(status.bufStatus[currentBufferIndex].prevMode)
    return

  let path = homeDir / ".config" / "moe" / "moerc.toml"
  const configExample = staticReadVersionFromConfigFileExample()
  writeFile(path, configExample)

  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc deleteTrailingSpacesCommand(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].deleteTrailingSpaces

  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc openHelp(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer("")
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(Mode.help)

proc openMessageLogViewer(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer("")
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(Mode.logviewer)

proc openBufferManager(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer("")
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(Mode.bufManager)

proc changeCursorLineCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on" : status.settings.view.cursorLine = true
  elif command == ru"off": status.settings.view.cursorLine = false

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc verticalSplitWindowCommand(status: var EditorStatus) =
  status.verticalSplitWindow

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc horizontalSplitWindowCommand(status: var Editorstatus) =
  status.horizontalSplitWindow

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc filerIconSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru "on": status.settings.filerSettings.showIcons = true
  elif command == ru"off": status.settings.filerSettings.showIcons = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc liveReloadOfConfSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru "on": status.settings.liveReloadOfConf = true
  elif command == ru"off": status.settings.liveReloadOfConf = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc changeThemeSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"dark": status.settings.editorColorTheme = ColorTheme.dark
  elif command == ru"light": status.settings.editorColorTheme = ColorTheme.light
  elif command == ru"vivid": status.settings.editorColorTheme = ColorTheme.vivid
  elif command == ru"config": status.settings.editorColorTheme = ColorTheme.config
  elif command == ru"vscode": status.settings.editorColorTheme = ColorTheme.vscode

  status.changeTheme
  status.resize(terminalHeight(), terminalWidth())
  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc tabLineSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.tabLine.useTab = true
  elif command == ru"off": status.settings.tabLine.useTab = false

  status.resize(terminalHeight(), terminalWidth())
  status.commandWindow.erase

proc syntaxSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.syntax = true
  elif command == ru"off": status.settings.syntax = false

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  let sourceLang = if status.settings.syntax:
                     status.bufStatus[currentBufferIndex].language
                   else: SourceLanguage.langNone

  let workspaceIndex = status.currentWorkSpaceIndex
  status.workSpace[workspaceIndex].currentMainWindowNode.highlight =
    initHighlight($status.bufStatus[currentBufferIndex].buffer,
                  status.settings.reservedWords,
                  sourceLang)

  status.commandWindow.erase
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc tabStopSettingCommand(status: var EditorStatus, command: int) =
  status.settings.tabStop = command

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc autoCloseParenSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.autoCloseParen = true
  elif command == ru"off": status.settings.autoCloseParen = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc autoIndentSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.autoIndent = true
  elif command == ru"off": status.settings.autoIndent = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc indentationLinesSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.view.indentationLines = true
  elif command == ru"off": status.settings.view.indentationLines = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc lineNumberSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru "on": status.settings.view.lineNumber = true
  elif command == ru"off": status.settings.view.lineNumber = false

  let numberOfDigitsLen = if status.settings.view.lineNumber:
                            numberOfDigits(status.bufStatus[0].buffer.len) - 2
                          else: 0
  let useStatusBar = if status.settings.statusBar.enable: 1 else: 0
  let workspaceIndex = status.currentWorkSpaceIndex

  status.workSpace[workspaceIndex].currentMainWindowNode.view =
    initEditorView(status.bufStatus[0].buffer,
                   terminalHeight() - useStatusBar - 1,
                   terminalWidth() - numberOfDigitsLen)

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc statusBarSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.statusBar.enable = true
  elif command == ru"off": status.settings.statusBar.enable = false

  let numberOfDigitsLen = if status.settings.view.lineNumber:
                            numberOfDigits(status.bufStatus[0].buffer.len) - 2
                          else: 0
  let useStatusBar = if status.settings.statusBar.enable : 1 else: 0
  let workspaceIndex = status.currentWorkSpaceIndex

  status.workSpace[workspaceIndex].currentMainWindowNode.view =
    initEditorView(status.bufStatus[0].buffer,
                   terminalHeight() - useStatusBar - 1,
                   terminalWidth() - numberOfDigitsLen)

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc incrementalSearchSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  exitUi()
  echo "ok"
  if command == ru"on": status.settings.incrementalSearch = true
  elif command == ru"off": status.settings.incrementalSearch = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc highlightPairOfParenSettigCommand(status: var Editorstatus,
                                       command: seq[Rune]) =

  if command == ru"on": status.settings.highlightPairOfParen = true
  elif command == ru"off": status.settings.highlightPairOfParen = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc autoDeleteParenSettingCommand(status: var EditorStatus,
                                   command: seq[Rune]) =

  if command == ru"on": status.settings.autoDeleteParen = true
  elif command == ru"off": status.settings.autoDeleteParen = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc smoothScrollSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.smoothScroll = true
  elif command == ru"off": status.settings.smoothScroll = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc smoothScrollSpeedSettingCommand(status: var Editorstatus, speed: int) =
  if speed > 0: status.settings.smoothScrollSpeed = speed

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc highlightCurrentWordSettingCommand(status: var Editorstatus,
                                        command: seq[Rune]) =

  if command == ru"on": status.settings.highlightOtherUsesCurrentWord = true
  if command == ru"off": status.settings.highlightOtherUsesCurrentWord = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc systemClipboardSettingCommand(status: var Editorstatus,
                                   command: seq[Rune]) =

  if command == ru"on": status.settings.systemClipboard = true
  elif command == ru"off": status.settings.systemClipboard = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc highlightFullWidthSpaceSettingCommand(status: var Editorstatus,
                                           command: seq[Rune]) =

  if command == ru"on": status.settings.highlightFullWidthSpace = true
  elif command == ru"off": status.settings.highlightFullWidthSpace = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc buildOnSaveSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.buildOnSave.enable = true
  elif command == ru"off":
    status.settings.buildOnSave.enable = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc turnOffHighlightingCommand(status: var EditorStatus) =
  turnOffHighlighting(status)

  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc multipleStatusBarSettingCommand(status: var Editorstatus,
                                     command: seq[Rune]) =

  if command == ru"on": status.settings.statusBar.multipleStatusBar = true
  elif command == ru"off": status.settings.statusBar.multipleStatusBar = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc showGitInInactiveSettingCommand(status: var EditorStatus,
                                     command: seq[Rune]) =

  if command == ru"on": status.settings.statusBar.showGitInactive = true
  elif command == ru"off": status.settings.statusBar.showGitInactive = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc deleteBufferStatusCommand(status: var EditorStatus, index: int) =
  if index < 0 or index > status.bufStatus.high:
    status.commandWindow.writeNoBufferDeletedError(status.messageLog)
    status.changeMode(Mode.normal)
    return

  status.bufStatus.delete(index)

  if status.bufStatus.len == 0: addNewBuffer(status, "")
  elif status.bufferIndexInCurrentWindow > status.bufStatus.high:
    let workspaceIndex = status.currentWorkSpaceIndex
    status.workSpace[workspaceIndex].currentMainWindowNode.bufferIndex =
      status.bufStatus.high

  if status.bufStatus[status.bufferIndexInCurrentWindow].mode == Mode.ex:
    let prevMode = status.bufStatus[status.bufferIndexInCurrentWindow].prevMode
    status.changeMode(prevMode)
  else:
    status.commandWindow.erase
    status.changeMode(status.bufStatus[status.bufferIndexInCurrentWindow].mode)

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
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if currentBufferIndex == status.bufStatus.high: return

  changeCurrentBuffer(status, currentBufferIndex + 1)
  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc changePreveBufferCommand(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if currentBufferIndex < 1: return

  changeCurrentBuffer(status, currentBufferIndex - 1)

  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc jumpCommand(status: var EditorStatus, line: int) =
  jumpLine(status, line)

  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc editCommand(status: var EditorStatus, filename: seq[Rune]) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  let workspaceIndex = status.currentWorkSpaceIndex
  if status.bufStatus[currentBufferIndex].countChange > 0 and
     countReferencedWindow(status.workSpace[workspaceIndex].mainWindowNode,
                           currentBufferIndex) == 1:
    status.commandWindow.writeNoWriteError(status.messageLog)
  else:
    if existsDir($filename):
      try: setCurrentDir($filename)
      except OSError:
        status.commandWindow.writeFileOpenError($filename, status.messageLog)
        status.addNewBuffer("")
      status.bufStatus.add(BufferStatus(mode: Mode.filer, lastSaveTime: now()))
    else: status.addNewBuffer($filename)

    status.changeCurrentBuffer(status.bufStatus.high)

proc openInHorizontalSplitWindow(status: var Editorstatus, filename: seq[Rune]) =
  status.horizontalSplitWindow
  status.resize(terminalHeight(), terminalWidth())

  status.editCommand(filename)

proc openInVerticalSplitWindowCommand(status: var Editorstatus, filename: seq[Rune]) =
  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())

  status.editCommand(filename)

proc execCmdResultToMessageLog*(output: TaintedString,
                                messageLog: var seq[seq[Rune]])=

  var line = ""
  for ch in output:
    if ch == '\n':
      messageLog.add(line.toRunes)
      line = ""
    else: line.add(ch)

proc buildOnSave(status: var Editorstatus) =
  status.commandWindow.writeMessageBuildOnSave(status.settings.notificationSettings,
                                               status.messageLog)

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    filename = status.bufStatus[currentBufferIndex].path
    workspaceRoot = status.settings.buildOnSave.workspaceRoot
    command = status.settings.buildOnSave.command
    language = status.bufStatus[currentBufferIndex].language
    cmdResult = build(filename, workspaceRoot, command, language)

  cmdResult.output.execCmdResultToMessageLog(status.messageLog)

  if cmdResult.exitCode != 0:
    status.commandWindow.writeMessageFailedBuildOnSave(status.messageLog)
  else:
    status.commandWindow.writeMessageSuccessBuildOnSave(status.settings.notificationSettings,
                                                        status.messageLog)

proc checkAndCreateDir(cmdWin: var Window,
                       messageLog: var seq[seq[Rune]],
                       filename: seq[Rune]): bool =

  ## Not include directory
  if not filename.contains(ru"/"): return true

  let pathSplit = splitPath($filename)

  result = true
  if not existsDir(pathSplit.head):
    let isCreateDir = cmdWin.askCreateDirPrompt(messageLog, pathSplit.head)
    if isCreateDir:
      try: createDir(pathSplit.head)
      except OSError: result = false

proc writeCommand(status: var EditorStatus, filename: seq[Rune]) =
  if filename.len == 0:
    status.commandWindow.writeNoFileNameError(status.messageLog)
    status.changeMode(Mode.normal)
    return

  ## Ask if you want to create a directory that does not exist
  if not status.commandWindow.checkAndCreateDir(status.messageLog, filename):
    status.changeMode(Mode.normal)
    status.commandWindow.writeSaveError(status.messageLog)
    return

  try:
    let currentBufferIndex = status.bufferIndexInCurrentWindow
    saveFile(filename,
             status.bufStatus[currentBufferIndex].buffer.toRunes,
             status.bufStatus[currentBufferIndex].characterEncoding)
    let
      workspaceIndex = status.currentWorkSpaceIndex
      bufferIndex = status.workSpace[workspaceIndex].currentMainWindowNode.bufferIndex

    if status.bufStatus[bufferIndex].path != filename:
      status.bufStatus[bufferIndex].path = filename
      status.bufStatus[bufferIndex].language = detectLanguage($filename)

    status.bufStatus[currentBufferIndex].countChange = 0

    if status.settings.buildOnSave.enable: status.buildOnSave
    else:
      status.commandWindow.writeMessageSaveFile(filename,
                                                status.settings.notificationSettings,
                                                status.messageLog)

  except IOError:
    status.commandWindow.writeSaveError(status.messageLog)

  status.changeMode(Mode.normal)

proc quitCommand(status: var EditorStatus) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    workspaceIndex = status.currentWorkSpaceIndex
  if status.bufStatus[currentBufferIndex].prevMode != Mode.normal:
    status.deleteBuffer(currentBufferIndex)
  else:
    if status.bufStatus[currentBufferIndex].countChange == 0 or
       status.workSpace[workspaceIndex].mainWindowNode.countReferencedWindow(currentBufferIndex) > 1:
      status.closeWindow(status.workSpace[workspaceIndex].currentMainWindowNode)
    else:
      status.commandWindow.writeNoWriteError(status.messageLog)

proc writeAndQuitCommand(status: var EditorStatus) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    workspaceIndex = status.currentWorkSpaceIndex
    filename = status.bufStatus[currentBufferIndex].path

  ## Ask if you want to create a directory that does not exist
  if not status.commandWindow.checkAndCreateDir(status.messageLog, filename):
    status.changeMode(Mode.normal)
    status.commandWindow.writeSaveError(status.messageLog)
    return

  try:
    status.bufStatus[currentBufferIndex].countChange = 0
    saveFile(filename,
             status.bufStatus[currentBufferIndex].buffer.toRunes,
             status.bufStatus[currentBufferIndex].characterEncoding)

    status.closeWindow(status.workSpace[workspaceIndex].currentMainWindowNode)
  except IOError:
    status.commandWindow.writeSaveError(status.messageLog)

  status.changeMode(Mode.normal)

proc forceQuitCommand(status: var EditorStatus) =
  let workspaceIndex = status.currentWorkSpaceIndex
  status.closeWindow(status.workSpace[workspaceIndex].currentMainWindowNode)
  status.changeMode(Mode.normal)

proc allBufferQuitCommand(status: var EditorStatus) =
  let workspaceIndex = status.currentWorkSpaceIndex
  for i in 0 ..< status.workSpace[workspaceIndex].numOfMainWindow:
    let node = status.workSpace[workspaceIndex].mainWindowNode.searchByWindowIndex(i)
    if status.bufStatus[node.bufferIndex].countChange > 0:
      status.commandWindow.writeNoWriteError(status.messageLog)
      status.changeMode(Mode.normal)
      return

  exitEditor(status.settings)

proc forceAllBufferQuitCommand(status: var EditorStatus) = exitEditor(status.settings)

proc writeAndQuitAllBufferCommand(status: var Editorstatus) =
  for bufStatus in status.bufStatus:
    let filename = bufStatus.path
    ## Ask if you want to create a directory that does not exist
    if not status.commandWindow.checkAndCreateDir(status.messageLog, filename):
      status.changeMode(Mode.normal)
      status.commandWindow.writeSaveError(status.messageLog)
      return

    try:
      saveFile(filename,
               bufStatus.buffer.toRunes,
               bufStatus.characterEncoding)
    except IOError:
      status.commandWindow.writeSaveError(status.messageLog)
      status.changeMode(Mode.normal)
      return

  exitEditor(status.settings)

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
  let workspaceIndex = status.currentWorkSpaceIndex
  let swapCurrentBufferIndex =
    status.workSpace[workspaceIndex].currentMainWindowNode.bufferIndex
  status.addNewBuffer("")
  status.changeCurrentBuffer(status.bufStatus.high)

  for i in 0 ..< status.bufStatus.high:
    var line = ru""
    let
      currentMode = status.bufStatus[i].mode
      prevMode = status.bufStatus[i].prevMode
    if currentMode == Mode.filer or
       (currentMode == Mode.ex and
       prevMode == Mode.filer): line = getCurrentDir().toRunes
    else:
      let filename = status.bufStatus[i].path
      line = filename & ru"  line " & ($status.bufStatus[i].buffer.len).toRunes

    let currentBufferIndex =
      status.workSpace[workspaceIndex].currentMainWindowNode.bufferIndex
    if i == 0: status.bufStatus[currentBufferIndex].buffer[0] = line
    else: status.bufStatus[currentBufferIndex].buffer.insert(line, i)

  let
    useStatusBar = if status.settings.statusBar.enable: 1 else: 0
    useTab = if status.settings.tabLine.useTab: 1 else: 0
    swapCurrentLineNumStting = status.settings.view.currentLineNumber
    currentBufferIndex =
      status.workSpace[workspaceIndex].currentMainWindowNode.bufferIndex

  status.settings.view.currentLineNumber = false
  status.workSpace[workspaceIndex].currentMainWindowNode.view =
    status.bufStatus[currentBufferIndex].buffer.initEditorView(terminalHeight() - useStatusBar - useTab - 1,
                                                               terminalWidth())
  status.workSpace[workspaceIndex].currentMainWindowNode.currentLine = 0

  status.updatehighlight(status.workspace[workspaceIndex].currentMainWindowNode)

  while true:
    status.update
    setCursor(false)
    let key = getKey(status.workSpace[workspaceIndex].currentMainWindowNode.window)
    if isResizekey(key): status.resize(terminalHeight(), terminalWidth())
    elif key.int == 0: discard
    else: break

  status.settings.view.currentLineNumber = swapCurrentLineNumStting
  status.changeCurrentBuffer(swapCurrentBufferIndex)
  status.deleteBufferStatusCommand(status.bufStatus.high)

  status.commandWindow.erase
  status.commandWindow.refresh
proc replaceBuffer(status: var EditorStatus, command: seq[Rune]) =
  let
    replaceInfo = parseReplaceCommand(command)
    currentBufferIndex = status.bufferIndexInCurrentWindow

  if replaceInfo.searhWord == ru"'\n'" and status.bufStatus[currentBufferIndex].buffer.len > 1:
    let startLine = 0

    for i in 0 .. status.bufStatus[currentBufferIndex].buffer.high - 2:
      let oldLine = status.bufStatus[currentBufferIndex].buffer[startLine]
      var newLine = status.bufStatus[currentBufferIndex].buffer[startLine]
      newLine.insert(replaceInfo.replaceWord,
                     status.bufStatus[currentBufferIndex].buffer[startLine].len)
      for j in 0 .. status.bufStatus[currentBufferIndex].buffer[startLine + 1].high:
        newLine.insert(status.bufStatus[currentBufferIndex].buffer[startLine + 1][j],
                       status.bufStatus[currentBufferIndex].buffer[startLine].len)
      if oldLine != newLine:
        status.bufStatus[currentBufferIndex].buffer[startLine] = newLine

      status.bufStatus[currentBufferIndex].buffer.delete(startLine + 1,
                                                         startLine + 1)
  else:
    for i in 0 .. status.bufStatus[currentBufferIndex].buffer.high:
      let searchResult = searchBuffer(status, replaceInfo.searhWord)
      if searchResult.line > -1:
        let oldLine = status.bufStatus[currentBufferIndex].buffer[searchResult.line]
        var newLine = status.bufStatus[currentBufferIndex].buffer[searchResult.line]
        newLine.delete(searchResult.column,
                       searchResult.column + replaceInfo.searhWord.high)
        newLine.insert(replaceInfo.replaceWord, searchResult.column)
        if oldLine != newLine:
          status.bufStatus[currentBufferIndex].buffer[searchResult.line] = newLine

  inc(status.bufStatus[currentBufferIndex].countChange)
  status.commandWindow.erase
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc createWrokSpaceCommand(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  status.createWrokSpace

proc workspaceListCommand(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  var buffer = "workspaces: "
  for i in 0 ..< status.workspace.len:
    if i == status.currentWorkSpaceIndex:
      buffer &= "*" & $i & " "
    else:
      buffer &= $i & " "

  status.commandwindow.writeWorkspaceList(buffer)

proc changeCurrentWorkSpaceCommand(status: var Editorstatus, index: int) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  status.changeCurrentWorkSpace(index)

proc deleteCurrentWorkSpaceCommand*(status: var Editorstatus) =
  let index = status.currentWorkSpaceIndex
  if 0 <= index and index < status.workSpace.len:
    for i in 0 ..< status.workSpace[index].numOfMainWindow:
      let node =
        status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.searchByWindowIndex(i)
      ## Check if buffer has changed
      if status.bufStatus[node.bufferIndex].countChange > 0:
        status.commandWindow.writeNoWriteError(status.messageLog)
        status.changeMode(Mode.normal)
        return

    status.deleteWorkSpace(index)

proc createNewEmptyBufferCommand*(status: var Editorstatus) =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    currentBufferIndex = status.bufferIndexInCurrentWindow

  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  if status.bufStatus[currentBufferIndex].countChange == 0 or
     status.workSpace[workspaceIndex].mainWindowNode.countReferencedWindow(currentBufferIndex) > 1:
    status.addNewBuffer("")
    status.changeCurrentBuffer(status.bufStatus.high)
  else:
    status.commandWindow.writeNoWriteError(status.messageLog)

proc newEmptyBufferInSplitWindowHorizontally*(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  status.horizontalSplitWindow
  status.resize(terminalHeight(), terminalWidth())

  status.addNewBuffer("")

  status.changeCurrentBuffer(status.bufStatus.high)

proc newEmptyBufferInSplitWindowVertically*(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())

  status.addNewBuffer("")

  status.changeCurrentBuffer(status.bufStatus.high)

proc exModeCommand*(status: var EditorStatus, command: seq[seq[Rune]]) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  if command.len == 0 or command[0].len == 0:
    status.changeMode(status.bufStatus[currentBufferIndex].prevMode)
  elif isJumpCommand(status, command):
    var line = ($command[0]).parseInt - 1
    if line < 0: line = 0
    if line >= status.bufStatus[currentBufferIndex].buffer.len:
      line = status.bufStatus[currentBufferIndex].buffer.high
    jumpCommand(status, line)
  elif isEditCommand(command):
    editCommand(status, command[1].normalizePath)
  elif isOpenInHorizontalSplitWindowCommand(command):
    let path = if command.len == 2:
      command[1].normalizePath
    else: status.bufStatus[currentBufferIndex].path
    status.openInHorizontalSplitWindow(path)
  elif isOpenInVerticalSplitWindowCommand(command):
    status.openInVerticalSplitWindowCommand(command[1])
  elif isWriteCommand(status, command):
    writeCommand(status, if command.len < 2:
      status.bufStatus[currentBufferIndex].path else: command[1])
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
  elif isOpenBufferByNumber(command):
    opneBufferByNumberCommand(status, ($command[1]).parseInt)
  elif isChangeFirstBufferCommand(command):
    changeFirstBufferCommand(status)
  elif isChangeLastBufferCommand(command):
    changeLastBufferCommand(status)
  elif isDeleteBufferStatusCommand(command):
    deleteBufferStatusCommand(status, ($command[1]).parseInt)
  elif isDeleteCurrentBufferStatusCommand(command):
    deleteBufferStatusCommand(status, currentBufferIndex)
  elif isTurnOffHighlightingCommand(command):
    turnOffHighlightingCommand(status)
  elif isTabLineSettingCommand(command):
    tabLineSettingCommand(status, command[1])
  elif isStatusBarSettingCommand(command):
    statusBarSettingCommand(status, command[1])
  elif isLineNumberSettingCommand(command):
    lineNumberSettingCommand(status, command[1])
  elif isIndentationLinesSettingCommand(command):
    indentationLinesSettingCommand(status, command[1])
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
  elif isIncrementalSearchSettingCommand(command):
    incrementalSearchSettingCommand(status, command[1])
  elif isOpenMessageLogViweer(command):
    openMessageLogViewer(status)
  elif isHighlightPairOfParenSettigCommand(command):
    highlightPairOfParenSettigCommand(status, command[1])
  elif isAutoDeleteParenSettingCommand(command):
    autoDeleteParenSettingCommand(status, command[1])
  elif isSmoothScrollSettingCommand(command):
    smoothScrollSettingCommand(status, command[1])
  elif isSmoothScrollSpeedSettingCommand(command):
    smoothScrollSpeedSettingCommand(status, ($command[1]).parseInt)
  elif isHighlightCurrentWordSettingCommand(command):
    highlightCurrentWordSettingCommand(status, command[1])
  elif isSystemClipboardSettingCommand(command):
    systemClipboardSettingCommand(status, command[1])
  elif isHighlightFullWidthSpaceSettingCommand(command):
    highlightFullWidthSpaceSettingCommand(status, command[1])
  elif isMultipleStatusBarSettingCommand(command):
    multipleStatusBarSettingCommand(status, command[1])
  elif isBuildOnSaveSettingCommand(command):
    buildOnSaveSettingCommand(status, command[1])
  elif isCreateWorkSpaceCommand(command):
    createWrokSpaceCommand(status)
  elif isChangeCurrentWorkSpace(command):
    changeCurrentWorkSpaceCommand(status, ($command[1]).parseInt)
  elif isDeleteCurrentWorkSpaceCommand(command):
    deleteCurrentWorkSpaceCommand(status)
  elif isOpenHelpCommand(command):
    status.openHelp
  elif isCreateNewEmptyBufferCommand(command):
    status.createNewEmptyBufferCommand
  elif isNewEmptyBufferInSplitWindowHorizontally(command):
    status.newEmptyBufferInSplitWindowHorizontally
  elif isNewEmptyBufferInSplitWindowVertically(command):
    status.newEmptyBufferInSplitWindowVertically
  elif isFilerIconSettingCommand(command):
    status.filerIconSettingCommand(command[1])
  elif isDeleteTrailingSpacesCommand(command):
    status.deleteTrailingSpacesCommand
  elif isPutConfigFileCommand(command):
    status.putConfigFileCommand
  elif isShowGitInInactiveSettingCommand(command):
    status.showGitInInactiveSettingCommand(command[1])
  elif isQuickRunCommand(command):
    status.runQuickRunCommand
  elif isRecentFileModeCommand(command):
    status.startRecentFileMode
  elif isWorkspaceListCommand(command):
    status.workspaceListCommand
  elif isHistoryManagerCommand(command):
    status.startHistoryManager
  elif isStartConfigMode(command):
    status.startConfigMode
  else:
    status.commandWindow.writeNotEditorCommandError(command, status.messageLog)
    status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc exMode*(status: var EditorStatus) =
  const
    prompt = ":"
    isSearch = false
  var
    command = ru""
    exitInput = false
    cancelInput = false
    isSuggest = true
    isReplaceCommand = false

  status.exCommandHistory.add(ru"")

  let workspaceIndex = status.currentWorkSpaceIndex

  status.update

  while exitInput == false:
    let returnWord = status.getKeyOnceAndWriteCommandView(prompt,
                                                          command,
                                                          isSuggest,
                                                          isSearch)

    command = returnWord[0]
    exitInput = returnWord[1]
    cancelInput = returnWord[2]

    if command.len > 3 and command.startsWith(ru"%s/"):
      isReplaceCommand = true
      status.searchHistory.add(ru"")

    if cancelInput or exitInput: break
    elif isReplaceCommand and status.settings.replaceTextHighlight:
      var keyword = ru""
      for i in 3 ..< command.len :
          if command[i] == ru'/': break
          keyword.add(command[i])
      status.searchHistory[status.searchHistory.high] = keyword
      let bufferIndex =
        status.workSpace[workspaceIndex].currentMainWindowNode.bufferIndex
      status.bufStatus[bufferIndex].isSearchHighlight = true

      status.jumpToSearchForwardResults(keyword)
    else:
      if command.len > 0:
        status.exCommandHistory[status.exCommandHistory.high] = command
        if isReplaceCommand:
          isReplaceCommand = false
          status.searchHistory.delete(status.searchHistory.high)

    status.updatehighlight(status.workspace[workspaceIndex].currentMainWindowNode)
    status.resize(terminalHeight(), terminalWidth())
    status.update

  if status.exCommandHistory[status.exCommandHistory.high] == ru"":
    status.exCommandHistory.delete(status.exCommandHistory.high)

  if isReplaceCommand: status.searchHistory.delete(status.searchHistory.high)

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.updatehighlight(status.workspace[workspaceIndex].currentMainWindowNode)

  if cancelInput:
    status.commandWindow.erase
    status.changeMode(status.bufStatus[currentBufferIndex].prevMode)
  else:
    status.bufStatus[currentBufferIndex].buffer.beginNewSuitIfNeeded
    status.bufStatus[currentBufferIndex].tryRecordCurrentPosition(status.workSpace[workspaceIndex].currentMainWindowNode)

    status.exModeCommand(splitCommand($command))
