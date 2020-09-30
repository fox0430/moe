import sequtils, strutils, os, terminal, highlite, times, strformat, osproc,
       posix
import editorstatus, ui, normalmode, gapbuffer, fileutils, editorview,
        unicodeext, independentutils, search, highlight, commandview,
        window, movement, color, build, bufferstatus, editor,
        settings, quickrun, messages, commandline

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

proc isForceWriteAndQuitCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "wq!") == 0

proc isForceWriteCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "w!") == 0

proc isPutConfigFileCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "putconfigfile") == 0

proc isDeleteTrailingSpacesCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and
         cmpIgnoreCase($command[0], "deletetrailingspaces") == 0

proc isOpenHelpCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "help") == 0

proc isOpenMessageLogViweer(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "log") == 0

proc isOpenBufferManager(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "buf") == 0

proc isChangeCursorLineCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "cursorline") == 0

proc isListAllBufferCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "ls") == 0

proc isWriteAndQuitAllBufferCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "wqa") == 0

proc isForceAllBufferQuitCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "qa!") == 0

proc isAllBufferQuitCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "qa") == 0

proc isVerticalSplitWindowCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "vs") == 0

proc isHorizontalSplitWindowCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "sv") == 0

proc isFilerIconSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "icon") == 0

proc isLiveReloadOfConfSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "livereload") == 0

proc isChangeThemeSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "theme") == 0

proc isTabLineSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "tab") == 0

proc isSyntaxSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "syntax") == 0

proc isTabStopSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and
         cmpIgnoreCase($command[0], "tabstop") == 0 and
         isDigit(command[1])

proc isAutoCloseParenSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "paren") == 0

proc isAutoIndentSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "indent") == 0

proc isIndentationLinesSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "indentationlines") == 0

proc isLineNumberSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "linenum") == 0

proc isStatusBarSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "statusbar") == 0

proc isIncrementalSearchSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "incrementalsearch") == 0

proc isHighlightPairOfParenSettigCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "highlightparen") == 0

proc isAutoDeleteParenSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "deleteparen") == 0

proc isSmoothScrollSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "smoothscroll") == 0

proc isSmoothScrollSpeedSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and
         cmpIgnoreCase($command[0], "scrollspeed") == 0 and
         isDigit(command[1])

proc isHighlightCurrentWordSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "highlightcurrentword") == 0

proc isSystemClipboardSettingCommand(command: seq[seq[RUne]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "clipboard") == 0

proc isHighlightFullWidthSpaceSettingCommand(command: seq[seq[RUne]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "highlightfullspace") == 0

proc isMultipleStatusBarSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "multiplestatusbar") == 0

proc isBuildOnSaveSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "buildonsave") == 0

proc isShowGitInInactiveSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "showgitinactive") == 0

proc isIgnorecaseSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "ignorecase") == 0

proc isSmartcaseSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "smartcase") == 0

proc isTurnOffHighlightingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "noh") == 0

proc isDeleteCurrentBufferStatusCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "bd") == 0

proc isDeleteBufferStatusCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and
         cmpIgnoreCase($command[0], "bd") == 0 and
         isDigit(command[1])

proc isChangeFirstBufferCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "bfirst") == 0

proc isChangeLastBufferCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "blast") == 0

proc isOpenBufferByNumber(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and
         cmpIgnoreCase($command[0], "b") == 0 and
         isDigit(command[1])

proc isChangeNextBufferCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "bnext") == 0

proc isChangePreveBufferCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "bprev") == 0

proc isJumpCommand(status: EditorStatus, command: seq[seq[Rune]]): bool =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    prevMode = status.bufStatus[currentBufferIndex].prevMode
  return command.len == 1 and
         isDigit(command[0]) and
         (prevMode == bufferstatus.Mode.normal or
         prevMode == bufferstatus.Mode.logviewer)

proc isEditCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "e") == 0

proc isOpenInHorizontalSplitWindowCommand(command: seq[seq[Rune]]): bool =
  return command.len > 0 and
         command.len < 3 and
         cmpIgnoreCase($command[0], "sp") == 0

proc isOpenInVerticalSplitWindowCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "vs") == 0

proc isWriteCommand(status: EditorStatus, command: seq[seq[Rune]]): bool =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  return command.len in {1, 2} and
         cmpIgnoreCase($command[0], "w") == 0 and
         status.bufStatus[currentBufferIndex].prevMode == bufferstatus.Mode.normal

proc isQuitCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "q") == 0

proc isWriteAndQuitCommand(status: EditorStatus, command: seq[seq[Rune]]): bool =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  return command.len == 1 and
         cmpIgnoreCase($command[0], "wq") == 0 and
         status.bufStatus[currentBufferIndex].prevMode == bufferstatus.Mode.normal

proc isForceQuitCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "q!") == 0

proc isShellCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len >= 1 and command[0][0] == ru'!'

proc isReplaceCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len >= 1 and
         command[0].len > 4 and
         command[0][0 .. 2] == ru"%s/"

proc isWorkspaceListCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "lsw") == 0

proc isCreateWorkSpaceCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "cws") == 0

proc isDeleteCurrentWorkSpaceCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "dws") == 0

proc isChangeCurrentWorkSpace(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and
         cmpIgnoreCase($command[0], "ws") == 0 and
         isDigit(command[1])

proc isCreateNewEmptyBufferCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "ene") == 0

proc isNewEmptyBufferInSplitWindowHorizontally(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "new") == 0

proc isNewEmptyBufferInSplitWindowVertically(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "vnew") == 0

proc isQuickRunCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and
         (cmpIgnoreCase($command[0], "run") == 0 or command[0] == ru"Q")

proc isRecentFileModeCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "recent") == 0

proc isHistoryManagerCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "history") == 0

proc isStartConfigMode(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "conf") == 0

proc startConfigMode(status: var Editorstatus) =
  let bufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[bufferIndex].prevMode)

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer(bufferstatus.Mode.config)
  status.changeCurrentBuffer(status.bufStatus.high)

proc startHistoryManager(status: var Editorstatus) =
  let bufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[bufferIndex].prevMode)
  status.prevBufferIndex = bufferIndex

  if status.bufStatus[bufferIndex].mode != bufferstatus.Mode.normal: return
  for bufStatus in status.bufStatus:
    if bufStatus.mode == bufferstatus.Mode.history: return

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer(bufferstatus.Mode.history)
  status.changeCurrentBuffer(status.bufStatus.high)

proc startRecentFileMode(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  # :recent is only supported on GNU/Linux
  if status.platform != Platform.linux: return

  if not fileExists(getHomeDir() / ".local/share/recently-used.xbel"):
    status.commandLine.writeOpenRecentlyUsedXbelError(status.messageLog)
    return

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(bufferstatus.Mode.recentFile)

proc runQuickRunCommand(status: var Editorstatus) =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    windowNode = status.workspace[workspaceIndex].currentMainWindowNode

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  let
    buffer = runQuickRun(status.bufStatus[windowNode.bufferIndex],
                         status.commandLine,
                         status.messageLog,
                         status.settings)

    workspace = status.workspace[workspaceIndex]
    quickRunWindowIndex = status.bufStatus.getQuickRunBufferIndex(workspace)

  if quickRunWindowIndex == -1:
    status.verticalSplitWindow
    status.resize(terminalHeight(), terminalWidth())
    status.moveNextWindow

    status.addNewBuffer
    status.bufStatus[^1].buffer = initGapBuffer(buffer)

    status.changeCurrentBuffer(status.bufStatus.high)

    status.changeMode(bufferstatus.Mode.quickRun)
  else:
    status.bufStatus[quickRunWindowIndex].buffer = initGapBuffer(buffer)

proc staticReadVersionFromConfigFileExample(): string {.compileTime.} =
  staticRead(currentSourcePath.parentDir() / "../../example/moerc.toml")

proc putConfigFileCommand(status: var Editorstatus) =
  let
    homeDir = getHomeDir()
    currentBufferIndex = status.bufferIndexInCurrentWindow

  if not dirExists(homeDir / ".config"):
    try: createDir(homeDir / ".config")
    except OSError:
      status.commandLine.writePutConfigFileError(status.messageLog)
      status.changeMode(status.bufStatus[currentBufferIndex].prevMode)
      return
  if not dirExists(homeDir / ".config" / "moe"):
    try: createDir(homeDir / ".config" / "moe")
    except OSError:
      status.commandLine.writePutConfigFileError(status.messageLog)
      status.changeMode(status.bufStatus[currentBufferIndex].prevMode)
      return

  if fileExists(getHomeDir() / ".config" / "moe" / "moerc.toml"):
    status.commandLine.writePutConfigFileAlreadyExistError(status.messageLog)
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

  status.addNewBuffer
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(bufferstatus.Mode.help)

proc openMessageLogViewer(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(bufferstatus.Mode.logviewer)

proc openBufferManager(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(bufferstatus.Mode.bufManager)

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

  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc liveReloadOfConfSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru "on": status.settings.liveReloadOfConf = true
  elif command == ru"off": status.settings.liveReloadOfConf = false

  status.commandLine.erase

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
  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc tabLineSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.tabLine.useTab = true
  elif command == ru"off": status.settings.tabLine.useTab = false

  status.resize(terminalHeight(), terminalWidth())
  status.commandLine.erase

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

  status.commandLine.erase
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc tabStopSettingCommand(status: var EditorStatus, command: int) =
  status.settings.tabStop = command

  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc autoCloseParenSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.autoCloseParen = true
  elif command == ru"off": status.settings.autoCloseParen = false

  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc autoIndentSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.autoIndent = true
  elif command == ru"off": status.settings.autoIndent = false

  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc indentationLinesSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.view.indentationLines = true
  elif command == ru"off": status.settings.view.indentationLines = false

  status.commandLine.erase

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

  status.commandLine.erase

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

  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc incrementalSearchSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.incrementalSearch = true
  elif command == ru"off": status.settings.incrementalSearch = false

  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc highlightPairOfParenSettigCommand(status: var Editorstatus,
                                       command: seq[Rune]) =

  if command == ru"on": status.settings.highlightPairOfParen = true
  elif command == ru"off": status.settings.highlightPairOfParen = false

  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc autoDeleteParenSettingCommand(status: var EditorStatus,
                                   command: seq[Rune]) =

  if command == ru"on": status.settings.autoDeleteParen = true
  elif command == ru"off": status.settings.autoDeleteParen = false

  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc smoothScrollSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.smoothScroll = true
  elif command == ru"off": status.settings.smoothScroll = false

  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc smoothScrollSpeedSettingCommand(status: var Editorstatus, speed: int) =
  if speed > 0: status.settings.smoothScrollSpeed = speed

  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc highlightCurrentWordSettingCommand(status: var Editorstatus,
                                        command: seq[Rune]) =

  if command == ru"on": status.settings.highlightOtherUsesCurrentWord = true
  if command == ru"off": status.settings.highlightOtherUsesCurrentWord = false

  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc systemClipboardSettingCommand(status: var Editorstatus,
                                   command: seq[Rune]) =

  if command == ru"on": status.settings.systemClipboard = true
  elif command == ru"off": status.settings.systemClipboard = false

  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc highlightFullWidthSpaceSettingCommand(status: var Editorstatus,
                                           command: seq[Rune]) =

  if command == ru"on": status.settings.highlightFullWidthSpace = true
  elif command == ru"off": status.settings.highlightFullWidthSpace = false

  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc buildOnSaveSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.buildOnSave.enable = true
  elif command == ru"off":
    status.settings.buildOnSave.enable = false

  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc turnOffHighlightingCommand(status: var EditorStatus) =
  turnOffHighlighting(status)

  status.commandLine.erase
  status.changeMode(bufferstatus.Mode.normal)

proc multipleStatusBarSettingCommand(status: var Editorstatus,
                                     command: seq[Rune]) =

  if command == ru"on": status.settings.statusBar.multipleStatusBar = true
  elif command == ru"off": status.settings.statusBar.multipleStatusBar = false

  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc showGitInInactiveSettingCommand(status: var EditorStatus,
                                     command: seq[Rune]) =

  if command == ru"on": status.settings.statusBar.showGitInactive = true
  elif command == ru"off": status.settings.statusBar.showGitInactive = false

  status.commandLine.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc ignorecaseSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru "on": status.settings.ignorecase = true
  elif command == ru "off": status.settings.ignorecase = false

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc smartcaseSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru "on": status.settings.smartcase = true
  elif command == ru "off": status.settings.smartcase = false

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc deleteBufferStatusCommand(status: var EditorStatus, index: int) =
  if index < 0 or index > status.bufStatus.high:
    status.commandLine.writeNoBufferDeletedError(status.messageLog)
    status.changeMode(bufferstatus.Mode.normal)
    return

  status.bufStatus.delete(index)

  if status.bufStatus.len == 0: status.addNewBuffer
  elif status.bufferIndexInCurrentWindow > status.bufStatus.high:
    let workspaceIndex = status.currentWorkSpaceIndex
    status.workSpace[workspaceIndex].currentMainWindowNode.bufferIndex =
      status.bufStatus.high

  let bufferIndex = status.bufferIndexInCurrentWindow
  if status.bufStatus[bufferIndex].mode == bufferstatus.Mode.ex:
    let prevMode = status.bufStatus[bufferIndex].prevMode
    status.changeMode(prevMode)
  else:
    status.commandLine.erase
    status.changeMode(status.bufStatus[bufferIndex].mode)

proc changeFirstBufferCommand(status: var EditorStatus) =
  changeCurrentBuffer(status, 0)

  status.commandLine.erase
  status.changeMode(bufferstatus.Mode.normal)

proc changeLastBufferCommand(status: var EditorStatus) =
  changeCurrentBuffer(status, status.bufStatus.high)

  status.commandLine.erase
  status.changeMode(bufferstatus.Mode.normal)

proc opneBufferByNumberCommand(status: var EditorStatus, number: int) =
  if number < 0 or number > status.bufStatus.high: return

  changeCurrentBuffer(status, number)
  status.commandline.erase
  status.changeMode(bufferstatus.Mode.normal)

proc changeNextBufferCommand(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if currentBufferIndex == status.bufStatus.high: return

  changeCurrentBuffer(status, currentBufferIndex + 1)
  status.commandline.erase
  status.changeMode(bufferstatus.Mode.normal)

proc changePreveBufferCommand(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if currentBufferIndex < 1: return

  changeCurrentBuffer(status, currentBufferIndex - 1)

  status.commandLine.erase
  status.changeMode(bufferstatus.Mode.normal)

proc jumpCommand(status: var EditorStatus, line: int) =
  jumpLine(status, line)

  status.commandLine.erase
  status.changeMode(bufferstatus.Mode.normal)

proc editCommand(status: var EditorStatus, filename: seq[Rune]) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  let workspaceIndex = status.currentWorkSpaceIndex
  if status.bufStatus[currentBufferIndex].countChange > 0 and
     countReferencedWindow(status.workSpace[workspaceIndex].mainWindowNode,
                           currentBufferIndex) == 1:
    status.commandLine.writeNoWriteError(status.messageLog)
  else:
    if dirExists($filename):
      status.addNewBuffer($filename, bufferstatus.Mode.filer)
    else:
      status.addNewBuffer($filename)

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
  status.commandLine.writeMessageBuildOnSave(status.settings.notificationSettings,
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
    status.commandLine.writeMessageFailedBuildOnSave(status.messageLog)
  else:
    status.commandLine.writeMessageSuccessBuildOnSave(status.settings.notificationSettings,
                                                        status.messageLog)

proc checkAndCreateDir(commandLine: var CommandLine,
                       messageLog: var seq[seq[Rune]],
                       filename: seq[Rune]): bool =

  ## Not include directory
  if not filename.contains(ru"/"): return true

  let pathSplit = splitPath($filename)

  result = true
  if not dirExists(pathSplit.head):
    let isCreateDir = commandLine.askCreateDirPrompt(messageLog, pathSplit.head)
    if isCreateDir:
      try: createDir(pathSplit.head)
      except OSError: result = false

proc writeCommand(status: var EditorStatus, path: seq[Rune]) =
  let bufferIndex = status.bufferIndexInCurrentWindow

  if path.len == 0:
    status.commandLine.writeNoFileNameError(status.messageLog)
    status.changeMode(status.bufStatus[bufferIndex].prevMode)
    return

  # Check if the file has been overwritten by another application
  if fileExists($path):
    let
      lastSaveTimeOfBuffer = status.bufStatus[bufferIndex].lastSaveTime.toTime
      lastModificationTimeOfFile = getLastModificationTime($path)
    if lastModificationTimeOfFile > lastSaveTimeOfBuffer:
      if not status.commandLine.askFileChangedSinceReading(status.messageLog):
        # Cancel overwrite
        status.changeMode(status.bufStatus[bufferIndex].prevMode)
        status.commandLine.erase
        return

  ## Ask if you want to create a directory that does not exist
  if not status.commandLine.checkAndCreateDir(status.messageLog, path):
    status.changeMode(status.bufStatus[bufferIndex].prevMode)
    status.commandLine.writeSaveError(status.messageLog)
    return

  try:
    saveFile(path,
             status.bufStatus[bufferIndex].buffer.toRunes,
             status.bufStatus[bufferIndex].characterEncoding)
  except IOError:
    status.commandLine.writeSaveError(status.messageLog)

  if status.bufStatus[bufferIndex].path != path:
    status.bufStatus[bufferIndex].path = path
    status.bufStatus[bufferIndex].language = detectLanguage($path)

  # Build on save
  if status.settings.buildOnSave.enable:
    try:
      status.buildOnSave
    except IOError:
      status.commandLine.writeSaveError(status.messageLog)
  else:
      status.commandLine.writeMessageSaveFile(
        path,
        status.settings.notificationSettings,
        status.messageLog)

  status.bufStatus[bufferIndex].countChange = 0
  status.bufStatus[bufferIndex].lastSaveTime = now()
  status.changeMode(status.bufStatus[bufferIndex].prevMode)

proc forceWriteCommand(status: var EditorStatus, path: seq[Rune]) =
  try:
    setFilePermissions($path, {fpUserRead,fpUserWrite})
  except OSError:
    status.commandLine.writeSaveError(status.messageLog)
    return

  status.writeCommand(path)

proc quitCommand(status: var EditorStatus) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    workspaceIndex = status.currentWorkSpaceIndex
  if status.bufStatus[currentBufferIndex].prevMode != bufferstatus.Mode.normal:
    status.deleteBuffer(currentBufferIndex)
  else:
    let
      node = status.workSpace[workspaceIndex].mainWindowNode
      numberReferenced = node.countReferencedWindow(currentBufferIndex)
      countChange = status.bufStatus[currentBufferIndex].countChange
    if countChange == 0 or numberReferenced > 1:
      status.closeWindow(status.workSpace[workspaceIndex].currentMainWindowNode)
      status.changeMode(status.bufStatus[currentBufferIndex].prevMode)
    else:
      status.commandLine.writeNoWriteError(status.messageLog)
      status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc writeAndQuitCommand(status: var EditorStatus) =
  let
    bufferIndex = status.bufferIndexInCurrentWindow
    workspaceIndex = status.currentWorkSpaceIndex
    path = status.bufStatus[bufferIndex].path

  # Check if the file has been overwritten by another application
  if fileExists($path):
    let
      lastSaveTimeOfBuffer = status.bufStatus[bufferIndex].lastSaveTime.toTime
      lastModificationTimeOfFile = getLastModificationTime($path)
    if lastModificationTimeOfFile > lastSaveTimeOfBuffer:
      if not status.commandLine.askFileChangedSinceReading(status.messageLog):
        # Cancel overwrite
        status.changeMode(status.bufStatus[bufferIndex].prevMode)
        status.commandLine.erase
        return

  ## Ask if you want to create a directory that does not exist
  if not status.commandLine.checkAndCreateDir(status.messageLog, path):
    status.changeMode(status.bufStatus[bufferIndex].prevMode)
    status.commandLine.writeSaveError(status.messageLog)
    return

  try:
    saveFile(path,
             status.bufStatus[bufferIndex].buffer.toRunes,
             status.bufStatus[bufferIndex].characterEncoding)
  except IOError:
    status.commandLine.writeSaveError(status.messageLog)
    status.changeMode(status.bufStatus[bufferIndex].prevMode)
    return

  status.closeWindow(status.workSpace[workspaceIndex].currentMainWindowNode)

  status.changeMode(status.bufStatus[bufferIndex].prevMode)

proc forceWriteAndQuitCommand(status: var EditorStatus) =
  let
    bufferIndex = status.bufferIndexInCurrentWindow
    path = status.bufStatus[bufferIndex].path

  try:
    setFilePermissions($path, {fpUserRead,fpUserWrite})
  except OSError:
    status.commandLine.writeSaveError(status.messageLog)
    return

  discard status.commandLine.getKey()

  status.writeAndQuitCommand

proc forceQuitCommand(status: var EditorStatus) =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    bufferIndex = status.bufferIndexInCurrentWindow
  status.closeWindow(status.workSpace[workspaceIndex].currentMainWindowNode)
  status.changeMode(status.bufStatus[bufferIndex].prevMode)

proc allBufferQuitCommand(status: var EditorStatus) =
  let workspaceIndex = status.currentWorkSpaceIndex
  for i in 0 ..< status.workSpace[workspaceIndex].numOfMainWindow:
    let node = status.workSpace[workspaceIndex].mainWindowNode.searchByWindowIndex(i)

    if status.bufStatus[node.bufferIndex].countChange > 0:
      status.commandLine.writeNoWriteError(status.messageLog)
      status.changeMode(bufferstatus.Mode.normal)
      return

  exitEditor(status.settings)

proc forceAllBufferQuitCommand(status: var EditorStatus) {.inline.} = exitEditor(status.settings)

proc writeAndQuitAllBufferCommand(status: var Editorstatus) =
  let bufferIndex = status.bufferIndexInCurrentWindow

  for bufStatus in status.bufStatus:
    let path = bufStatus.path

    # Check if the file has been overwritten by another application
    if fileExists($path):
      let
        lastSaveTimeOfBuffer = status.bufStatus[bufferIndex].lastSaveTime.toTime
        lastModificationTimeOfFile = getLastModificationTime($path)
      if lastModificationTimeOfFile > lastSaveTimeOfBuffer:
        if not status.commandLine.askFileChangedSinceReading(status.messageLog):
          # Cancel overwrite
          status.changeMode(status.bufStatus[bufferIndex].prevMode)
          status.commandLine.erase
          return

    ## Ask if you want to create a directory that does not exist
    if not status.commandLine.checkAndCreateDir(status.messageLog, path):
      status.changeMode(status.bufStatus[bufferIndex].prevMode)
      status.commandLine.writeSaveError(status.messageLog)
      return

    try:
      saveFile(path,
               bufStatus.buffer.toRunes,
               bufStatus.characterEncoding)
    except IOError:
      status.commandLine.writeSaveError(status.messageLog)
      status.changeMode(status.bufStatus[bufferIndex].prevMode)
      return

  exitEditor(status.settings)

proc shellCommand(status: var EditorStatus, shellCommand: string) =
  saveCurrentTerminalModes()
  exitUi()

  discard execShellCmd(shellCommand)
  discard execShellCmd("printf \"\nPress Enter\"")
  discard execShellCmd("read _")

  restoreTerminalModes()
  status.commandLine.erase

  let bufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[bufferIndex].prevMode)

proc listAllBufferCommand(status: var Editorstatus) =
  let workspaceIndex = status.currentWorkSpaceIndex
  let swapCurrentBufferIndex =
    status.workSpace[workspaceIndex].currentMainWindowNode.bufferIndex
  status.addNewBuffer
  status.changeCurrentBuffer(status.bufStatus.high)

  for i in 0 ..< status.bufStatus.high:
    var line = ru""
    let
      currentMode = status.bufStatus[i].mode
      prevMode = status.bufStatus[i].prevMode
    if currentMode == bufferstatus.Mode.filer or
       (currentMode == bufferstatus.Mode.ex and
       prevMode == bufferstatus.Mode.filer): line = getCurrentDir().toRunes
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

  status.commandLine.erase

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
    let
      ignorecase = status.settings.ignorecase
      smartcase = status.settings.smartcase
    for i in 0 .. status.bufStatus[currentBufferIndex].buffer.high:
      let searchResult = status.searchBuffer(replaceInfo.searhWord, ignorecase, smartcase)
      if searchResult.line > -1:
        let oldLine = status.bufStatus[currentBufferIndex].buffer[searchResult.line]
        var newLine = status.bufStatus[currentBufferIndex].buffer[searchResult.line]
        newLine.delete(searchResult.column,
                       searchResult.column + replaceInfo.searhWord.high)
        newLine.insert(replaceInfo.replaceWord, searchResult.column)
        if oldLine != newLine:
          status.bufStatus[currentBufferIndex].buffer[searchResult.line] = newLine

  inc(status.bufStatus[currentBufferIndex].countChange)
  status.commandLine.erase
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

  status.commandLine.writeWorkspaceList(buffer)

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
        status.commandLine.writeNoWriteError(status.messageLog)
        status.changeMode(bufferstatus.Mode.normal)
        return

    status.deleteWorkSpace(index)

proc createNewEmptyBufferCommand*(status: var Editorstatus) =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    currentBufferIndex = status.bufferIndexInCurrentWindow

  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  if status.bufStatus[currentBufferIndex].countChange == 0 or
     status.workSpace[workspaceIndex].mainWindowNode.countReferencedWindow(currentBufferIndex) > 1:
    status.addNewBuffer
    status.changeCurrentBuffer(status.bufStatus.high)
  else:
    status.commandLine.writeNoWriteError(status.messageLog)

proc newEmptyBufferInSplitWindowHorizontally*(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  status.horizontalSplitWindow
  status.resize(terminalHeight(), terminalWidth())

  status.addNewBuffer

  status.changeCurrentBuffer(status.bufStatus.high)

proc newEmptyBufferInSplitWindowVertically*(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())

  status.addNewBuffer

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
  elif isIgnorecaseSettingCommand(command):
    status.ignorecaseSettingCommand(command[1])
  elif isSmartcaseSettingCommand(command):
    status.smartcaseSettingCommand(command[1])
  elif isForceWriteCommand(command):
    status.forceWriteCommand(status.bufStatus[currentBufferIndex].path)
  elif isForceWriteAndQuitCommand(command):
    status.forceWriteAndQuitCommand
  else:
    status.commandLine.writeNotEditorCommandError(command, status.messageLog)
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
    status.commandLine.erase
    status.changeMode(status.bufStatus[currentBufferIndex].prevMode)
  else:
    status.bufStatus[currentBufferIndex].buffer.beginNewSuitIfNeeded
    status.bufStatus[currentBufferIndex].tryRecordCurrentPosition(status.workSpace[workspaceIndex].currentMainWindowNode)

    status.exModeCommand(splitCommand($command))
