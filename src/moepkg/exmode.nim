import std/[sequtils, strutils, os, terminal, times, options]
import syntax/highlite
import editorstatus, ui, normalmode, gapbuffer, fileutils, editorview,
        unicodeext, independentutils, searchutils, highlight, commandview,
        window, movement, color, build, bufferstatus, editor, settings,
        quickrun, messages, commandline, debugmode, platform, commandviewutils

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

proc isStatusLineSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "statusline") == 0

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

proc isMultipleStatusLineSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "multiplestatusline") == 0

proc isBuildOnSaveSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "buildonsave") == 0

proc isShowGitInInactiveSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "showgitinactive") == 0

proc isIgnorecaseSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "ignorecase") == 0

proc isSmartcaseSettingCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 2 and cmpIgnoreCase($command[0], "smartcase") == 0

proc isHighlightCurrentLineSettingCommand(
  command: seq[seq[Rune]]): bool {.inline.} =

  return command.len == 2 and
         cmpIgnoreCase($command[0], "highlightcurrentline") == 0

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
  let prevMode = currentBufStatus.prevMode
  return command.len in {1, 2} and
         cmpIgnoreCase($command[0], "w") == 0 and
         (prevMode == bufferstatus.Mode.normal or
          prevMode == bufferstatus.Mode.config)

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

proc isStartDebugMode(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "debug") == 0

proc isBuildCommand(command: seq[seq[Rune]]): bool {.inline.} =
  return command.len == 1 and cmpIgnoreCase($command[0], "build") == 0

proc startDebugMode(status: var Editorstatus) =
  let bufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[bufferIndex].prevMode)

  # Split window and move to new window
  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  # Add debug mode buffer
  status.addNewBuffer(bufferstatus.Mode.debug)
  status.changeCurrentBuffer(status.bufStatus.high)

  # Initialize debug mode buffer
  status.bufStatus.initDebugModeBuffer(
    mainWindowNode,
    currentMainWindowNode.windowIndex,
    status.settings.debugModeSettings)
  let buffer = currentBufStatus.buffer
  currentMainWindowNode.highlight = buffer.initDebugmodeHighlight

  status.movePrevWindow
  status.changeCurrentBuffer(bufferIndex)

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
  status.changeMode(currentBufStatus.prevMode)
  status.prevBufferIndex = bufferIndex

  if currentBufStatus.mode != bufferstatus.Mode.normal: return
  for bufStatus in status.bufStatus:
    if bufStatus.mode == bufferstatus.Mode.history: return

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer(bufferstatus.Mode.history)
  status.changeCurrentBuffer(status.bufStatus.high)

proc startRecentFileMode(status: var Editorstatus) =
  status.changeMode(currentBufStatus.prevMode)

  # :recent is only supported on Unix or Unix-like (BSD and Linux)
  if not (CURRENT_PLATFORM == Platforms.linux or
          CURRENT_PLATFORM == Platforms.freebsd or
          CURRENT_PLATFORM == Platforms.openbsd): return

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
  status.changeMode(currentBufStatus.prevMode)

  let
    buffer = runQuickRun(currentBufStatus,
                         status.commandLine,
                         status.messageLog,
                         status.settings)

    quickRunBufferIndex = status.bufStatus.getQuickRunBufferIndex(
      currentMainWindowNode)

  if quickRunBufferIndex == -1:
    status.verticalSplitWindow
    status.resize(terminalHeight(), terminalWidth())
    status.moveNextWindow

    status.addNewBuffer
    status.bufStatus[^1].buffer = initGapBuffer(buffer)

    status.changeCurrentBuffer(status.bufStatus.high)

    status.changeMode(bufferstatus.Mode.quickRun)
  else:
    status.bufStatus[quickRunBufferIndex].buffer = initGapBuffer(buffer)

proc staticReadVersionFromConfigFileExample(): string {.compileTime.} =
  staticRead(currentSourcePath.parentDir() / "../../example/moerc.toml")

proc putConfigFileCommand(status: var Editorstatus) =
  if not dirExists(getHomeDir() / ".config"):
    try:
      createDir(getHomeDir() / ".config")
    except OSError:
      status.commandLine.writePutConfigFileError(status.messageLog)
      status.changeMode(currentBufStatus.prevMode)
      return

  if not dirExists(getHomeDir() / ".config" / "moe"):
    try:
      createDir(getHomeDir() / ".config" / "moe")
    except OSError:
      status.commandLine.writePutConfigFileError(status.messageLog)
      status.changeMode(currentBufStatus.prevMode)
      return

  if fileExists(getHomeDir() / ".config" / "moe" / "moerc.toml"):
    status.commandLine.writePutConfigFileAlreadyExistError(status.messageLog)
    status.changeMode(currentBufStatus.prevMode)
    return

  let path = getHomeDir() / ".config" / "moe" / "moerc.toml"
  const configExample = staticReadVersionFromConfigFileExample()
  writeFile(path, configExample)

  status.changeMode(currentBufStatus.prevMode)

proc deleteTrailingSpacesCommand(status: var Editorstatus) =
  currentBufStatus.deleteTrailingSpaces

  status.changeMode(currentBufStatus.prevMode)

proc openHelp(status: var Editorstatus) =
  status.changeMode(currentBufStatus.prevMode)

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(bufferstatus.Mode.help)

proc openMessageLogViewer(status: var Editorstatus) =
  status.changeMode(currentBufStatus.prevMode)

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(bufferstatus.Mode.logviewer)

proc openBufferManager(status: var Editorstatus) =
  status.changeMode(currentBufStatus.prevMode)

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
  if command == ru"dark":
    status.settings.editorColorTheme = ColorTheme.dark
  elif command == ru"light":
    status.settings.editorColorTheme = ColorTheme.light
  elif command == ru"vivid":
    status.settings.editorColorTheme = ColorTheme.vivid
  elif command == ru"config":
    status.settings.editorColorTheme = ColorTheme.config
  elif command == ru"vscode":
    status.settings.editorColorTheme = ColorTheme.vscode

  status.changeTheme
  status.resize(terminalHeight(), terminalWidth())
  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc tabLineSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.tabLine.enable = true
  elif command == ru"off": status.settings.tabLine.enable = false

  status.resize(terminalHeight(), terminalWidth())
  status.commandLine.erase

proc syntaxSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.syntax = true
  elif command == ru"off": status.settings.syntax = false

  let sourceLang = if status.settings.syntax: currentBufStatus.language
                   else: SourceLanguage.langNone

  currentMainWindowNode.highlight = initHighlight($currentBufStatus.buffer,
                                                  status.settings.highlightSettings.reservedWords,
                                                  sourceLang)

  status.commandLine.erase
  status.changeMode(currentBufStatus.prevMode)

proc tabStopSettingCommand(status: var EditorStatus, command: int) =
  status.settings.tabStop = command

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc autoCloseParenSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.autoCloseParen = true
  elif command == ru"off": status.settings.autoCloseParen = false

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc autoIndentSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.autoIndent = true
  elif command == ru"off": status.settings.autoIndent = false

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc indentationLinesSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.view.indentationLines = true
  elif command == ru"off": status.settings.view.indentationLines = false

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc lineNumberSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru "on": status.settings.view.lineNumber = true
  elif command == ru"off": status.settings.view.lineNumber = false

  let
    numberOfDigitsLen = if status.settings.view.lineNumber:
                            numberOfDigits(status.bufStatus[0].buffer.len) - 2
                          else: 0
    useStatusLine = if status.settings.statusLine.enable: 1 else: 0

  currentMainWindowNode.view = initEditorView(
    status.bufStatus[0].buffer,
    terminalHeight() - useStatusLine - 1,
    terminalWidth() - numberOfDigitsLen)

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc statusLineSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.statusLine.enable = true
  elif command == ru"off": status.settings.statusLine.enable = false

  let
    numberOfDigitsLen = if status.settings.view.lineNumber:
                            numberOfDigits(status.bufStatus[0].buffer.len) - 2
                          else: 0
    useStatusLine = if status.settings.statusLine.enable : 1 else: 0

  currentMainWindowNode.view = initEditorView(
    status.bufStatus[0].buffer,
    terminalHeight() - useStatusLine - 1,
    terminalWidth() - numberOfDigitsLen)

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc incrementalSearchSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.incrementalSearch = true
  elif command == ru"off": status.settings.incrementalSearch = false

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc highlightPairOfParenSettigCommand(status: var Editorstatus,
                                       command: seq[Rune]) =

  if command == ru"on": status.settings.highlightSettings.pairOfParen = true
  elif command == ru"off": status.settings.highlightSettings.pairOfParen = false

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc autoDeleteParenSettingCommand(status: var EditorStatus,
                                   command: seq[Rune]) =

  if command == ru"on": status.settings.autoDeleteParen = true
  elif command == ru"off": status.settings.autoDeleteParen = false

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc smoothScrollSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.smoothScroll = true
  elif command == ru"off": status.settings.smoothScroll = false

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc smoothScrollSpeedSettingCommand(status: var Editorstatus, speed: int) =
  if speed > 0: status.settings.smoothScrollSpeed = speed

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc highlightCurrentWordSettingCommand(status: var Editorstatus,
                                        command: seq[Rune]) =

  if command == ru"on": status.settings.highlightSettings.currentWord = true
  if command == ru"off": status.settings.highlightSettings.currentWord = false

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc systemClipboardSettingCommand(status: var Editorstatus,
                                   command: seq[Rune]) =

  if command == ru"on": status.settings.clipboard.enable = true
  elif command == ru"off": status.settings.clipboard.enable = false

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc highlightFullWidthSpaceSettingCommand(status: var Editorstatus,
                                           command: seq[Rune]) =

  if command == ru"on":
    status.settings.highlightSettings.fullWidthSpace = true
  elif command == ru"off":
    status.settings.highlightSettings.fullWidthSpace = false

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc buildOnSaveSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.buildOnSave.enable = true
  elif command == ru"off":
    status.settings.buildOnSave.enable = false

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc turnOffHighlightingCommand(status: var EditorStatus) =
  turnOffHighlighting(status)

  status.commandLine.erase
  status.changeMode(bufferstatus.Mode.normal)

proc multipleStatusLineSettingCommand(status: var Editorstatus,
                                     command: seq[Rune]) =

  if command == ru"on": status.settings.statusLine.multipleStatusLine = true
  elif command == ru"off": status.settings.statusLine.multipleStatusLine = false

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc showGitInInactiveSettingCommand(status: var EditorStatus,
                                     command: seq[Rune]) =

  if command == ru"on": status.settings.statusLine.showGitInactive = true
  elif command == ru"off": status.settings.statusLine.showGitInactive = false

  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc ignorecaseSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru "on": status.settings.ignorecase = true
  elif command == ru "off": status.settings.ignorecase = false

  status.changeMode(currentBufStatus.prevMode)

proc smartcaseSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru "on": status.settings.smartcase = true
  elif command == ru "off": status.settings.smartcase = false

  status.changeMode(currentBufStatus.prevMode)

proc highlightCurrentLineSettingCommand(status: var EditorStatus,
                                        command: seq[Rune]) =

  if command == ru "on": status.settings.view.highlightCurrentLine = true
  elif command == ru "off": status.settings.view.highlightCurrentLine  = false

  status.changeMode(currentBufStatus.prevMode)

proc deleteBufferStatusCommand(status: var EditorStatus, index: int) =
  if index < 0 or index > status.bufStatus.high:
    status.commandLine.writeNoBufferDeletedError(status.messageLog)
    status.changeMode(bufferstatus.Mode.normal)
    return

  status.bufStatus.delete(index)

  if status.bufStatus.len == 0: status.addNewBuffer
  elif status.bufferIndexInCurrentWindow > status.bufStatus.high:
    currentMainWindowNode.bufferIndex = status.bufStatus.high

  if currentBufStatus.mode == bufferstatus.Mode.ex:
    let prevMode = currentBufStatus.prevMode
    status.changeMode(prevMode)
  else:
    status.commandLine.erase
    status.changeMode(currentBufStatus.mode)

proc changeFirstBufferCommand(status: var EditorStatus) =
  changeCurrentBuffer(status, 0)

  status.commandLine.erase
  status.changeMode(bufferstatus.Mode.normal)

proc changeLastBufferCommand(status: var EditorStatus) =
  status.changeCurrentBuffer(status.bufStatus.high)

  status.commandLine.erase
  status.changeMode(bufferstatus.Mode.normal)

proc opneBufferByNumberCommand(status: var EditorStatus, number: int) =
  if number < 0 or number > status.bufStatus.high: return

  status.changeCurrentBuffer(number)
  status.commandline.erase
  status.changeMode(bufferstatus.Mode.normal)

proc changeNextBufferCommand(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if currentBufferIndex == status.bufStatus.high: return

  status.changeCurrentBuffer(currentBufferIndex + 1)
  status.commandline.erase
  status.changeMode(bufferstatus.Mode.normal)

proc changePreveBufferCommand(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if currentBufferIndex < 1: return

  status.changeCurrentBuffer(currentBufferIndex - 1)

  status.commandLine.erase
  status.changeMode(bufferstatus.Mode.normal)

proc jumpCommand(status: var EditorStatus, line: int) =
  currentBufStatus.jumpLine(currentMainWindowNode, line)

  status.commandLine.erase
  status.changeMode(bufferstatus.Mode.normal)

proc editCommand(status: var EditorStatus, path: seq[Rune]) =
  status.changeMode(currentBufStatus.prevMode)

  status.updateLastCursorPostion

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if currentBufStatus.countChange > 0 and
    countReferencedWindow(mainWindowNode, currentBufferIndex) == 1:
    status.commandLine.writeNoWriteError(status.messageLog)
  else:
    # Add buffer(bufStatus) if not exist.
    var bufferIndex = status.bufStatus.checkBufferExist(path)
    if isNone(bufferIndex):
      if dirExists($path):
        status.addNewBuffer($path, bufferstatus.Mode.filer)
      else:
        status.addNewBuffer($path)

      bufferIndex = some(status.bufStatus.high)

    status.changeCurrentBuffer(bufferIndex.get)

    if not isFilerMode(currentBufStatus.mode):
      currentMainWindowNode.restoreCursorPostion(
        currentBufStatus,
        status.lastPosition)

proc openInHorizontalSplitWindow(status: var Editorstatus, filename: seq[Rune]) =
  status.horizontalSplitWindow
  status.resize(terminalHeight(), terminalWidth())

  status.editCommand(filename)

proc openInVerticalSplitWindowCommand(status: var Editorstatus, filename: seq[Rune]) =
  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())

  status.editCommand(filename)

proc execCmdResultToMessageLog*(output: string,
                                messageLog: var seq[seq[Rune]])=

  var line = ""
  for ch in output:
    if ch == '\n':
      messageLog.add(line.toRunes)
      line = ""
    else: line.add(ch)

proc buildOnSave(status: var Editorstatus) =
  status.commandLine.writeMessageBuildOnSave(
    status.settings.notificationSettings,
    status.messageLog)

  let
    filename = currentBufStatus.path
    workspaceRoot = status.settings.buildOnSave.workspaceRoot
    command = status.settings.buildOnSave.command
    language = currentBufStatus.language
    cmdResult = build(filename, workspaceRoot, command, language)

  cmdResult.output.execCmdResultToMessageLog(status.messageLog)

  if cmdResult.exitCode != 0:
    status.commandLine.writeMessageFailedBuildOnSave(status.messageLog)
  else:
    status.commandLine.writeMessageSuccessBuildOnSave(
      status.settings.notificationSettings,
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

# Write current editor settings to configuration file
proc writeConfigurationFile(status: var EditorStatus) =
  const
    configFileDir = getHomeDir() / ".config/moe/"
    configFilePath = configFileDir & "moerc.toml"

  let buffer = status.settings.generateTomlConfigStr

  if fileExists(configFilePath):
    status.commandLine.writePutConfigFileAlreadyExistError(status.messageLog)
  else:
    try:
      createDir(configFileDir)
      saveFile(configFilePath.toRunes,
               buffer.toRunes,
               CharacterEncoding.utf8)
    except IOError:
      status.commandLine.writeSaveError(status.messageLog)

    status.commandLine.writePutConfigFile(configFilePath, status.messageLog)

  status.changeMode(currentBufStatus.prevMode)

proc writeCommand(status: var EditorStatus, path: seq[Rune]) =
  if isConfigMode(currentBufStatus.mode, currentBufStatus.prevMode):
    status.writeConfigurationFile
  else:
    if path.len == 0:
      status.commandLine.writeNoFileNameError(status.messageLog)
      status.changeMode(currentBufStatus.prevMode)
      return

    # Check if the file has been overwritten by another application
    if fileExists($path):
      let
        lastSaveTimeOfBuffer = currentBufStatus.lastSaveTime.toTime
        lastModificationTimeOfFile = getLastModificationTime($path)
      if lastModificationTimeOfFile > lastSaveTimeOfBuffer:
        if not status.commandLine.askFileChangedSinceReading(status.messageLog):
          # Cancel overwrite
          status.changeMode(currentBufStatus.prevMode)
          status.commandLine.erase
          return

    ## Ask if you want to create a directory that does not exist
    if not status.commandLine.checkAndCreateDir(status.messageLog, path):
      status.changeMode(currentBufStatus.prevMode)
      status.commandLine.writeSaveError(status.messageLog)
      return

    try:
      saveFile(path,
               currentBufStatus.buffer.toRunes,
               currentBufStatus.characterEncoding)
    except IOError:
      status.commandLine.writeSaveError(status.messageLog)

    if currentBufStatus.path != path:
      currentBufStatus.path = path
      currentBufStatus.language = detectLanguage($path)

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

    currentBufStatus.countChange = 0
    currentBufStatus.lastSaveTime = now()
    status.changeMode(currentBufStatus.prevMode)

proc forceWriteCommand(status: var EditorStatus, path: seq[Rune]) =
  try:
    setFilePermissions($path, {fpUserRead,fpUserWrite})
  except OSError:
    status.commandLine.writeSaveError(status.messageLog)
    return

  status.writeCommand(path)

proc quitCommand(status: var EditorStatus, height, width: int) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  if currentBufStatus.prevMode != bufferstatus.Mode.normal:
    status.deleteBuffer(currentBufferIndex, height, width)
  else:
    let
      numberReferenced = mainWindowNode.countReferencedWindow(currentBufferIndex)
      countChange = currentBufStatus.countChange
      canundo = currentBufStatus.buffer.canundo
    if (not isNormalMode(currentBufStatus.mode, currentBufStatus.prevMode)) or
       (countChange == 0 or numberReferenced > 1 or not canundo):

      status.changeMode(currentBufStatus.prevMode)
      status.closeWindow(currentMainWindowNode, height, width)
    else:
      status.commandLine.writeNoWriteError(status.messageLog)
      status.changeMode(currentBufStatus.prevMode)

proc writeAndQuitCommand(status: var EditorStatus, height, width: int) =
  let path = currentBufStatus.path

  # Check if the file has been overwritten by another application
  if fileExists($path):
    let
      lastSaveTimeOfBuffer = currentBufStatus.lastSaveTime.toTime
      lastModificationTimeOfFile = getLastModificationTime($path)
    if lastModificationTimeOfFile > lastSaveTimeOfBuffer:
      if not status.commandLine.askFileChangedSinceReading(status.messageLog):
        # Cancel overwrite
        status.changeMode(currentBufStatus.prevMode)
        status.commandLine.erase
        return

  ## Ask if you want to create a directory that does not exist
  if not status.commandLine.checkAndCreateDir(status.messageLog, path):
    status.changeMode(currentBufStatus.prevMode)
    status.commandLine.writeSaveError(status.messageLog)
    return

  try:
    saveFile(path,
             currentBufStatus.buffer.toRunes,
             currentBufStatus.characterEncoding)
  except IOError:
    status.commandLine.writeSaveError(status.messageLog)
    status.changeMode(currentBufStatus.prevMode)
    return

  status.changeMode(currentBufStatus.prevMode)
  status.closeWindow(currentMainWindowNode, height, width)

proc forceWriteAndQuitCommand(status: var EditorStatus, height, width: int) =
  try:
    setFilePermissions($currentBufStatus.path, {fpUserRead,fpUserWrite})
  except OSError:
    status.commandLine.writeSaveError(status.messageLog)
    return

  discard status.commandLine.getKey

  status.writeAndQuitCommand(height, width)

proc forceQuitCommand(status: var EditorStatus, height, width: int) =
  status.changeMode(currentBufStatus.prevMode)
  status.closeWindow(currentMainWindowNode, height, width)

proc allBufferQuitCommand(status: var EditorStatus) =
  for i in 0 ..< status.mainWindow.numOfMainWindow:
    let
      node = mainWindowNode.searchByWindowIndex(i)
      bufStatus = status.bufStatus[node.bufferIndex]

    if isNormalMode(bufStatus.mode, bufStatus.prevMode) and
       bufStatus.countChange > 0:
      status.commandLine.writeNoWriteError(status.messageLog)
      status.changeMode(bufferstatus.Mode.normal)
      return

  status.exitEditor

proc forceAllBufferQuitCommand(status: var EditorStatus) {.inline.} = status.exitEditor

proc writeAndQuitAllBufferCommand(status: var Editorstatus) =
  for bufStatus in status.bufStatus:
    let path = bufStatus.path

    # Check if the file has been overwritten by another application
    if fileExists($path):
      let
        lastSaveTimeOfBuffer = currentBufStatus.lastSaveTime.toTime
        lastModificationTimeOfFile = getLastModificationTime($path)
      if lastModificationTimeOfFile > lastSaveTimeOfBuffer:
        if not status.commandLine.askFileChangedSinceReading(status.messageLog):
          # Cancel overwrite
          status.changeMode(currentBufStatus.prevMode)
          status.commandLine.erase
          return

    ## Ask if you want to create a directory that does not exist
    if not status.commandLine.checkAndCreateDir(status.messageLog, path):
      status.changeMode(currentBufStatus.prevMode)
      status.commandLine.writeSaveError(status.messageLog)
      return

    try:
      saveFile(path,
               bufStatus.buffer.toRunes,
               bufStatus.characterEncoding)
    except IOError:
      status.commandLine.writeSaveError(status.messageLog)
      status.changeMode(currentBufStatus.prevMode)
      return

  status.exitEditor

# Save buffer, buid and open log viewer
proc buildCommand(status: var Editorstatus) =
  # Force enable a build on save temporarily.
  let currentSetting = status.settings.buildOnSave.enable

  status.settings.buildOnSave.enable = true
  status.writeCommand(currentBufStatus.path)

  status.settings.buildOnSave.enable = currentSetting

  status.openMessageLogViewer

proc shellCommand(status: var EditorStatus, shellCommand: string) =
  saveCurrentTerminalModes()
  exitUi()

  discard execShellCmd(shellCommand)
  discard execShellCmd("printf \"\nPress Enter\"")
  discard execShellCmd("read _")

  restoreTerminalModes()
  status.commandLine.erase

  status.changeMode(currentBufStatus.prevMode)

proc listAllBufferCommand(status: var Editorstatus) =
  let swapCurrentBufferIndex = currentMainWindowNode.bufferIndex
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

    if i == 0: currentBufStatus.buffer[0] = line
    else: currentBufStatus.buffer.insert(line, i)

  let
    useStatusLine = if status.settings.statusLine.enable: 1 else: 0
    enable = if status.settings.tabLine.enable: 1 else: 0
    swapCurrentLineNumStting = status.settings.view.currentLineNumber

  status.settings.view.currentLineNumber = false
  currentMainWindowNode.view = currentBufStatus.buffer.initEditorView(
    terminalHeight() - useStatusLine - enable - 1,
    terminalWidth())

  currentMainWindowNode.currentLine = 0

  var highlight = currentMainWindowNode.highlight
  highlight.updateHighlight(
    currentBufStatus,
    currentMainWindowNode,
    status.isSearchHighlight,
    status.searchHistory,
    status.settings)

  while true:
    status.update
    setCursor(false)
    let key = getKey(currentMainWindowNode)
    if isResizekey(key): status.resize(terminalHeight(), terminalWidth())
    elif key.int == 0: discard
    else: break

  status.settings.view.currentLineNumber = swapCurrentLineNumStting
  status.changeCurrentBuffer(swapCurrentBufferIndex)
  status.deleteBufferStatusCommand(status.bufStatus.high)

  status.commandLine.erase

proc replaceBuffer(status: var EditorStatus, command: seq[Rune]) =
  let replaceInfo = parseReplaceCommand(command)

  if replaceInfo.searhWord == ru"'\n'" and currentBufStatus.buffer.len > 1:
    let startLine = 0

    for i in 0 .. currentBufStatus.buffer.high - 2:
      let oldLine = currentBufStatus.buffer[startLine]
      var newLine = currentBufStatus.buffer[startLine]
      newLine.insert(replaceInfo.replaceWord,
                     currentBufStatus.buffer[startLine].len)
      for j in 0 .. currentBufStatus.buffer[startLine + 1].high:
        newLine.insert(currentBufStatus.buffer[startLine + 1][j],
                       currentBufStatus.buffer[startLine].len)
      if oldLine != newLine:
        currentBufStatus.buffer[startLine] = newLine

      currentBufStatus.buffer.delete(startLine + 1, startLine + 1)
  else:
    let
      ignorecase = status.settings.ignorecase
      smartcase = status.settings.smartcase
    for i in 0 .. currentBufStatus.buffer.high:
      let searchResult = currentBufStatus.searchBuffer(
        currentMainWindowNode, replaceInfo.searhWord, ignorecase, smartcase)
      if searchResult.line > -1:
        let oldLine = currentBufStatus.buffer[searchResult.line]
        var newLine = currentBufStatus.buffer[searchResult.line]

        for _ in searchResult.column .. searchResult.column + replaceInfo.searhWord.high:
          newLine.delete(searchResult.column)

        newLine.insert(replaceInfo.replaceWord, searchResult.column)
        if oldLine != newLine:
          currentBufStatus.buffer[searchResult.line] = newLine

  inc(currentBufStatus.countChange)
  status.commandLine.erase
  status.changeMode(currentBufStatus.prevMode)

proc createNewEmptyBufferCommand*(status: var Editorstatus) =

  status.changeMode(currentBufStatus.prevMode)

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if status.bufStatus[currentBufferIndex].countChange == 0 or
     mainWindowNode.countReferencedWindow(currentBufferIndex) > 1:
    status.addNewBuffer
    status.changeCurrentBuffer(status.bufStatus.high)
  else:
    status.commandLine.writeNoWriteError(status.messageLog)

proc newEmptyBufferInSplitWindowHorizontally*(status: var Editorstatus) =
  status.changeMode(currentBufStatus.prevMode)

  status.horizontalSplitWindow
  status.resize(terminalHeight(), terminalWidth())

  status.addNewBuffer

  status.changeCurrentBuffer(status.bufStatus.high)

proc newEmptyBufferInSplitWindowVertically*(status: var Editorstatus) =
  status.changeMode(currentBufStatus.prevMode)

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())

  status.addNewBuffer

  status.changeCurrentBuffer(status.bufStatus.high)

proc addExCommandHistory(exCommandHistory: var seq[seq[Rune]],
                         command: seq[seq[Rune]]) =

  var cmd = ru ""
  for index, runes in command:
    if index > 0: cmd.add(ru" " & runes)
    else: cmd.add(runes)

  if exCommandHistory.len == 0 or cmd != exCommandHistory[^1]:
    exCommandHistory.add(cmd)

proc exModeCommand*(status: var EditorStatus,
                    command: seq[seq[Rune]],
                    height, width: int) =

  let currentBufferIndex = status.bufferIndexInCurrentWindow

  # Save command history
  status.exCommandHistory.addExCommandHistory(command)

  if command.len == 0 or command[0].len == 0:
    status.changeMode(currentBufStatus.prevMode)
  elif isJumpCommand(status, command):
    var line = ($command[0]).parseInt - 1
    if line < 0: line = 0
    if line >= currentBufStatus.buffer.len:
      line = currentBufStatus.buffer.high
    jumpCommand(status, line)
  elif isEditCommand(command):
    status.editCommand(command[1].normalizePath)
  elif isOpenInHorizontalSplitWindowCommand(command):
    let path = if command.len == 2:
      command[1].normalizePath
    else: status.bufStatus[currentBufferIndex].path
    status.openInHorizontalSplitWindow(path)
  elif isOpenInVerticalSplitWindowCommand(command):
    status.openInVerticalSplitWindowCommand(command[1])
  elif isWriteCommand(status, command):
    let path = if command.len < 2: currentBufStatus.path else: command[1]
    status.writeCommand(path)
  elif isQuitCommand(command):
    status.quitCommand(height, width)
  elif status.isWriteAndQuitCommand(command):
    status.writeAndQuitCommand(height, width)
  elif isForceQuitCommand(command):
    status.forceQuitCommand(height, width)
  elif isShellCommand(command):
    status.shellCommand(command.join(" ").substr(1))
  elif isReplaceCommand(command):
    status.replaceBuffer(command[0][3 .. command[0].high])
  elif isChangeNextBufferCommand(command):
    status.changeNextBufferCommand
  elif isChangePreveBufferCommand(command):
    status.changePreveBufferCommand
  elif isOpenBufferByNumber(command):
    status.opneBufferByNumberCommand(($command[1]).parseInt)
  elif isChangeFirstBufferCommand(command):
    status.changeFirstBufferCommand
  elif isChangeLastBufferCommand(command):
    status.changeLastBufferCommand
  elif isDeleteBufferStatusCommand(command):
    status.deleteBufferStatusCommand(($command[1]).parseInt)
  elif isDeleteCurrentBufferStatusCommand(command):
    status.deleteBufferStatusCommand(currentBufferIndex)
  elif isTurnOffHighlightingCommand(command):
    status.turnOffHighlightingCommand
  elif isTabLineSettingCommand(command):
    status.tabLineSettingCommand(command[1])
  elif isStatusLineSettingCommand(command):
    status.statusLineSettingCommand(command[1])
  elif isLineNumberSettingCommand(command):
    status.lineNumberSettingCommand(command[1])
  elif isIndentationLinesSettingCommand(command):
    status.indentationLinesSettingCommand(command[1])
  elif isAutoIndentSettingCommand(command):
    status.autoIndentSettingCommand(command[1])
  elif isAutoCloseParenSettingCommand(command):
    status.autoCloseParenSettingCommand(command[1])
  elif isTabStopSettingCommand(command):
    status.tabStopSettingCommand(($command[1]).parseInt)
  elif isSyntaxSettingCommand(command):
    status.syntaxSettingCommand(command[1])
  elif isChangeThemeSettingCommand(command):
    status.changeThemeSettingCommand(command[1])
  elif isChangeCursorLineCommand(command):
    status.changeCursorLineCommand(command[1])
  elif isVerticalSplitWindowCommand(command):
    status.verticalSplitWindowCommand
  elif isHorizontalSplitWindowCommand(command):
    status.horizontalSplitWindowCommand
  elif isAllBufferQuitCommand(command):
    status.allBufferQuitCommand
  elif isForceAllBufferQuitCommand(command):
    status.forceAllBufferQuitCommand
  elif isWriteAndQuitAllBufferCommand(command):
    status.writeAndQuitAllBufferCommand
  elif isListAllBufferCommand(command):
    status.listAllBufferCommand
  elif isOpenBufferManager(command):
    status.openBufferManager
  elif isLiveReloadOfConfSettingCommand(command):
    status.liveReloadOfConfSettingCommand(command[1])
  elif isIncrementalSearchSettingCommand(command):
    status.incrementalSearchSettingCommand(command[1])
  elif isOpenMessageLogViweer(command):
    status.openMessageLogViewer
  elif isHighlightPairOfParenSettigCommand(command):
    status.highlightPairOfParenSettigCommand(command[1])
  elif isAutoDeleteParenSettingCommand(command):
    status.autoDeleteParenSettingCommand(command[1])
  elif isSmoothScrollSettingCommand(command):
    status.smoothScrollSettingCommand(command[1])
  elif isSmoothScrollSpeedSettingCommand(command):
    status.smoothScrollSpeedSettingCommand(($command[1]).parseInt)
  elif isHighlightCurrentWordSettingCommand(command):
    status.highlightCurrentWordSettingCommand(command[1])
  elif isSystemClipboardSettingCommand(command):
    status.systemClipboardSettingCommand(command[1])
  elif isHighlightFullWidthSpaceSettingCommand(command):
    status.highlightFullWidthSpaceSettingCommand(command[1])
  elif isMultipleStatusLineSettingCommand(command):
    status.multipleStatusLineSettingCommand(command[1])
  elif isBuildOnSaveSettingCommand(command):
    status.buildOnSaveSettingCommand(command[1])
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
    status.forceWriteAndQuitCommand(height, width)
  elif isStartDebugMode(command):
    status.startDebugMode
  elif isHighlightCurrentLineSettingCommand(command):
    status.highlightCurrentLineSettingCommand(command[1])
  elif isBuildCommand(command):
    status.buildCommand
  else:
    status.commandLine.writeNotEditorCommandError(command, status.messageLog)
    status.changeMode(currentBufStatus.prevMode)

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

  status.update

  var highlight = currentMainWindowNode.highlight

  while exitInput == false:
    let returnWord = status.getKeyOnceAndWriteCommandView(
      prompt,
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
    elif isReplaceCommand and status.settings.highlightSettings.replaceText:
      var keyword = ru""
      for i in 3 ..< command.len :
          if command[i] == ru'/': break
          keyword.add(command[i])
      status.searchHistory[status.searchHistory.high] = keyword
      status.isSearchHighlight = true

      currentBufStatus.jumpToSearchForwardResults(
        currentMainWindowNode,
        keyword,
        status.settings.ignorecase,
        status.settings.smartcase)
    else:
      if command.len > 0:
        if isReplaceCommand:
          isReplaceCommand = false
          status.searchHistory.delete(status.searchHistory.high)

    highlight.updateHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings)

    status.resize(terminalHeight(), terminalWidth())
    status.update

  if isReplaceCommand:
    status.searchHistory.delete(status.searchHistory.high)

    highlight.updateHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings)

  if cancelInput:
    status.commandLine.erase
    status.changeMode(currentBufStatus.prevMode)
  else:
    currentBufStatus.buffer.beginNewSuitIfNeeded
    currentBufStatus.tryRecordCurrentPosition(currentMainWindowNode)

    status.exModeCommand(splitCommand($command),
                         terminalHeight(),
                         terminalWidth())
