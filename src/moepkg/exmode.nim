#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[strutils, os, times, options, strformat, logging, tables, sequtils,
            json]

import pkg/results

import syntax/highlite
import lsp/client
import editorstatus, ui, normalmode, gapbuffer, fileutils, editorview,
       unicodeext, independentutils, highlight, windownode, movement, build,
       bufferstatus, editor, settings, quickrunutils, messages, commandline,
       debugmodeutils, platform, commandlineutils, recentfilemode, messagelog,
       buffermanager, viewhighlight, configmode, git, syntaxcheck, exmodeutils,
       logviewerutils

proc startDebugMode(status: var EditorStatus) =
  status.changeMode(currentBufStatus.prevMode)

  # Split window and move to new window
  status.verticalSplitWindow
  status.resize

  # Add the buffer for the debug mode
  let bufferIndex = status.addNewBuffer(bufferstatus.Mode.debug)
  if bufferIndex.isOk:
    # Initialize the debug mode buffer
    status.bufStatus[bufferIndex.get].buffer =
      status.bufStatus.initDebugModeBuffer(
        mainWindowNode,
        currentMainWindowNode.windowIndex,
        status.settings.debugMode).toGapBuffer

    # Link the window and the debug mode buffer.
    var node = status.mainWindow.root.searchByWindowIndex(
    currentMainWindowNode.windowIndex + 1)
    node.bufferIndex = bufferIndex.get

    status.resize

proc openConfigMode(status: var EditorStatus) =
  let bufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[bufferIndex].prevMode)

  status.verticalSplitWindow
  status.resize
  status.moveNextWindow

  discard status.addNewBufferInCurrentWin(bufferstatus.Mode.config)
  status.changeCurrentBuffer(status.bufStatus.high)

  currentBufStatus.buffer = initConfigModeBuffer(status.settings)

  status.resize

proc startBackupManager(status: var EditorStatus) =
  status.changeMode(currentBufStatus.prevMode)

  if not currentBufStatus.isNormalMode: return

  let bufferIndex = status.addNewBuffer(Mode.backup)
  if bufferIndex.isOk:
    status.verticalSplitWindow
    status.resize
    status.moveNextWindow

    status.changeCurrentBuffer(bufferIndex.get)

    status.resize

proc startRecentFileMode(status: var EditorStatus) =
  status.changeMode(currentBufStatus.prevMode)

  # :recent is only supported on Unix or Unix-like (BSD and Linux)
  if not (getPlatform() in {linux, freebsd, openbsd}): return

  let recentUsedXbelPath = getHomeDir() / ".local/share/recently-used.xbel"

  let files = getRecentUsedFiles(recentUsedXbelPath)
  if files.isErr:
    status.commandLine.writeOpenRecentlyUsedXbelError
    return

  status.verticalSplitWindow
  status.resize
  status.moveNextWindow

  discard status.addNewBufferInCurrentWin
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(bufferstatus.Mode.recentFile)

  currentBufStatus.initRecentFileModeBuffer(files.get)

  status.resize

proc runQuickRunCommand(status: var EditorStatus) =
  status.changeMode(currentBufStatus.prevMode)

  let quickRunProcess = startBackgroundQuickRun(
    status.bufStatus[currentMainWindowNode.bufferIndex],
    status.settings)
  if quickRunProcess.isErr:
    status.commandLine.writeError(quickRunProcess.error.toRunes)
    addMessageLog quickRunProcess.error.toRunes
    return

  status.backgroundTasks.quickRun.add quickRunProcess.get

  let index = status.bufStatus.quickRunBufferIndex(quickRunProcess.get.filePath)

  if index.isSome:
    # Overwrite the quickrun buffer.
    status.bufStatus[index.get].buffer = quickRunStartupMessage(
      $status.bufStatus[index.get].path).toRunes.toGapBuffer
  else:
    # Open a new window and add a buffer for this quickrun.
    status.verticalSplitWindow
    status.resize
    status.moveNextWindow

    discard status.addNewBufferInCurrentWin
    status.changeCurrentBuffer(status.bufStatus.high)
    currentBufStatus.path = quickRunProcess.get.filePath.toRunes
    currentBufStatus.buffer[0] =
      quickRunStartupMessage($currentBufStatus.path).toRunes
    status.changeMode(Mode.quickRun)

    status.resize

  status.commandLine.writeRunQuickRunMessage(status.settings.notification)

proc staticReadVersionFromConfigFileExample(): string {.compileTime.} =
  staticRead(currentSourcePath.parentDir() / "../../example/moerc.toml")

proc putConfigFileCommand(status: var EditorStatus) =
  if not dirExists(getHomeDir() / ".config"):
    try:
      createDir(getHomeDir() / ".config")
    except OSError:
      status.commandLine.writePutConfigFileError
      status.changeMode(currentBufStatus.prevMode)
      return

  if not dirExists(getHomeDir() / ".config" / "moe"):
    try:
      createDir(getHomeDir() / ".config" / "moe")
    except OSError:
      status.commandLine.writePutConfigFileError
      status.changeMode(currentBufStatus.prevMode)
      return

  if fileExists(getHomeDir() / ".config" / "moe" / "moerc.toml"):
    status.commandLine.writePutConfigFileAlreadyExistError
    status.changeMode(currentBufStatus.prevMode)
    return

  let path = getHomeDir() / ".config" / "moe" / "moerc.toml"
  const ConfigExample = staticReadVersionFromConfigFileExample()
  writeFile(path, ConfigExample)

  status.changeMode(currentBufStatus.prevMode)

proc deleteTrailingSpacesCommand(status: var EditorStatus) =
  ## Delete trailing spaces in the current buffer.

  currentBufStatus.deleteTrailingSpaces

  let lineHigh = currentBufStatus.buffer[currentMainWindowNode.currentLine].high
  if currentMainWindowNode.currentColumn > lineHigh:
    if lineHigh > -1: currentMainWindowNode.currentColumn = lineHigh
    else: currentMainWindowNode.currentColumn = 0

  status.changeMode(currentBufStatus.prevMode)

proc openHelp(status: var EditorStatus) =
  status.changeMode(currentBufStatus.prevMode)

  status.verticalSplitWindow
  status.resize
  status.moveNextWindow

  discard status.addNewBufferInCurrentWin(Mode.help)

  status.resize

proc openEditorLogViewer(status: var EditorStatus) =
  ## Open a new log viewe for editor logs.

  status.changeMode(currentBufStatus.prevMode)

  status.verticalSplitWindow
  status.resize
  status.moveNextWindow

  discard status.addNewBufferInCurrentWin(Mode.logviewer)
  currentBufStatus.logContent = LogContentKind.editor

  status.changeCurrentBuffer(status.bufStatus.high)

  let buf = initEditorLogViewrBuffer()
  currentBufStatus.buffer = buf.toGapBuffer
  currentBufStatus.highlight = buf.initLogViewerHighlight

  status.resize

proc openLspLogViewer(status: var EditorStatus) =
  ## Open a new log viewe for LSP logs.

  let langId = currentBufStatus.langId

  status.changeMode(currentBufStatus.prevMode)

  status.verticalSplitWindow
  status.resize
  status.moveNextWindow

  discard status.addNewBufferInCurrentWin(Mode.logviewer)

  status.changeCurrentBuffer(status.bufStatus.high)

  currentBufStatus.logContent = LogContentKind.lsp
  currentBufStatus.logLspLangId = langId

  status.resize

proc openBufferManager(status: var EditorStatus) =
  status.changeMode(currentBufStatus.prevMode)

  status.verticalSplitWindow
  status.resize
  status.moveNextWindow

  discard status.addNewBufferInCurrentWin
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(bufferstatus.Mode.bufManager)
  currentBufStatus.buffer = status.bufStatus.initBufferManagerBuffer.toGapBuffer
  status.resize

proc changeCursorLineCommand(status: var EditorStatus, command: Runes) =
  if command == ru"on" : status.settings.view.cursorLine = true
  elif command == ru"off": status.settings.view.cursorLine = false

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc verticalSplitWindowCommand(status: var EditorStatus) =
  let prevMode = currentBufStatus.prevMode
  status.verticalSplitWindow
  status.changeMode(prevMode)

proc horizontalSplitWindowCommand(status: var EditorStatus) =
  let prevMode = currentBufStatus.prevMode
  status.horizontalSplitWindow
  status.changeMode(prevMode)

proc filerIconSettingCommand(status: var EditorStatus, command: Runes) =
  if command == ru "on": status.settings.filer.showIcons = true
  elif command == ru"off": status.settings.filer.showIcons = false

  status.commandLine.clear

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc liveReloadOfConfSettingCommand(status: var EditorStatus, command: Runes) =
  if command == ru "on": status.settings.standard.liveReloadOfConf = true
  elif command == ru"off": status.settings.standard.liveReloadOfConf = false

  status.commandLine.clear

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc changeThemeSettingCommand(status: var EditorStatus, command: Runes) =
  case $command:
    of "default":
      status.settings.theme.kind = ColorThemeKind.default
    of "vscode":
      status.settings.theme.kind = ColorThemeKind.vscode
    of "config":
      status.settings.theme.kind = ColorThemeKind.config
    else:
      discard

  let r = status.settings.changeTheme
  # TODO: Add error message
  if r.isOk:
    status.resize
    status.commandLine.clear

    status.changeMode(currentBufStatus.prevMode)

proc tabLineSettingCommand(status: var EditorStatus, command: Runes) =
  if command == ru"on": status.settings.tabLine.enable = true
  elif command == ru"off": status.settings.tabLine.enable = false

  status.resize
  status.commandLine.clear

proc syntaxSettingCommand(status: var EditorStatus, command: Runes) =
  if command == ru"on": status.settings.standard.syntax = true
  elif command == ru"off": status.settings.standard.syntax = false

  let sourceLang = if status.settings.standard.syntax: currentBufStatus.language
                   else: SourceLanguage.langNone

  currentBufStatus.highlight = initHighlight(
    currentBufStatus.buffer.toSeqRunes,
    status.settings.highlight.reservedWords,
    sourceLang)

  status.commandLine.clear
  status.changeMode(currentBufStatus.prevMode)

proc tabStopSettingCommand(status: var EditorStatus, command: int) =
  status.settings.standard.tabStop = command

  status.commandLine.clear

  status.changeMode(currentBufStatus.prevMode)

proc autoCloseParenSettingCommand(status: var EditorStatus, command: Runes) =
  if command == ru"on": status.settings.standard.autoCloseParen = true
  elif command == ru"off": status.settings.standard.autoCloseParen = false

  status.commandLine.clear

  status.changeMode(currentBufStatus.prevMode)

proc autoIndentSettingCommand(status: var EditorStatus, command: Runes) =
  if command == ru"on": status.settings.standard.autoIndent = true
  elif command == ru"off": status.settings.standard.autoIndent = false

  status.commandLine.clear

  status.changeMode(currentBufStatus.prevMode)

proc indentationLinesSettingCommand(status: var EditorStatus, command: Runes) =
  if command == ru"on": status.settings.view.indentationLines = true
  elif command == ru"off": status.settings.view.indentationLines = false

  status.commandLine.clear

  status.changeMode(currentBufStatus.prevMode)

proc lineNumberSettingCommand(status: var EditorStatus, command: Runes) =
  if command == ru "on": status.settings.view.lineNumber = true
  elif command == ru"off": status.settings.view.lineNumber = false

  let
    numberOfDigitsLen =
      if status.settings.view.lineNumber:
        numberOfDigits(status.bufStatus[0].buffer.len) - 2
      else:
        0
    useStatusLine = if status.settings.statusLine.enable: 1 else: 0

  currentMainWindowNode.view = initEditorView(
    status.bufStatus[0].buffer,
    getTerminalHeight() - useStatusLine - 1,
    getTerminalWidth() - numberOfDigitsLen)

  status.commandLine.clear

  status.changeMode(currentBufStatus.prevMode)

proc statusLineSettingCommand(status: var EditorStatus, command: Runes) =
  if command == ru"on": status.settings.statusLine.enable = true
  elif command == ru"off": status.settings.statusLine.enable = false

  let
    numberOfDigitsLen =
      if status.settings.view.lineNumber:
        numberOfDigits(status.bufStatus[0].buffer.len) - 2
      else:
        0
    useStatusLine = if status.settings.statusLine.enable : 1 else: 0

  currentMainWindowNode.view = initEditorView(
    status.bufStatus[0].buffer,
    getTerminalHeight() - useStatusLine - 1,
    getTerminalWidth() - numberOfDigitsLen)

  status.commandLine.clear

  status.changeMode(currentBufStatus.prevMode)

proc incrementalSearchSettingCommand(status: var EditorStatus, command: Runes) =
  if command == ru"on": status.settings.standard.incrementalSearch = true
  elif command == ru"off": status.settings.standard.incrementalSearch = false

  status.commandLine.clear

  status.changeMode(currentBufStatus.prevMode)

proc highlightPairOfParenSettingCommand(
  status: var EditorStatus,
  command: Runes) =

    if command == ru"on": status.settings.highlight.pairOfParen = true
    elif command == ru"off": status.settings.highlight.pairOfParen = false

    status.commandLine.clear

    status.changeMode(currentBufStatus.prevMode)

proc autoDeleteParenSettingCommand(
  status: var EditorStatus,
  command: Runes) =

    if command == ru"on": status.settings.standard.autoDeleteParen = true
    elif command == ru"off": status.settings.standard.autoDeleteParen = false

    status.commandLine.clear

    status.changeMode(currentBufStatus.prevMode)

proc smoothScrollSettingCommand(status: var EditorStatus, command: Runes) =
  if command == ru"on": status.settings.smoothScroll.enable = true
  elif command == ru"off": status.settings.smoothScroll.enable = false

  status.commandLine.clear

  status.changeMode(currentBufStatus.prevMode)

proc smoothScrollMaxDelaySettingCommand(status: var EditorStatus, delay: int) =
  if delay > 0: status.settings.smoothScroll.maxDelay = delay
  status.commandLine.clear
  status.changeMode(currentBufStatus.prevMode)

proc smoothScrollMinDelaySettingCommand(status: var EditorStatus, delay: int) =
  if delay > 0: status.settings.smoothScroll.minDelay = delay
  status.commandLine.clear
  status.changeMode(currentBufStatus.prevMode)

proc highlightCurrentWordSettingCommand(
  status: var EditorStatus,
  command: Runes) =

    if command == ru"on": status.settings.highlight.currentWord = true
    if command == ru"off": status.settings.highlight.currentWord = false

    status.commandLine.clear

    status.changeMode(currentBufStatus.prevMode)

proc systemClipboardSettingCommand(
  status: var EditorStatus,
  command: Runes) =

    if command == ru"on": status.settings.clipboard.enable = true
    elif command == ru"off": status.settings.clipboard.enable = false

    status.commandLine.clear

    status.changeMode(currentBufStatus.prevMode)

proc highlightFullWidthSpaceSettingCommand(
  status: var EditorStatus,
  command: Runes) =

    if command == ru"on":
      status.settings.highlight.fullWidthSpace = true
    elif command == ru"off":
      status.settings.highlight.fullWidthSpace = false

    status.commandLine.clear

    status.changeMode(currentBufStatus.prevMode)

proc buildOnSaveSettingCommand(status: var EditorStatus, command: Runes) =
  if command == ru"on": status.settings.buildOnSave.enable = true
  elif command == ru"off":
    status.settings.buildOnSave.enable = false

  status.commandLine.clear

  status.changeMode(currentBufStatus.prevMode)

proc turnOffHighlightingCommand(status: var EditorStatus) =
  turnOffHighlighting(status)

  status.commandLine.clear
  status.changeMode(bufferstatus.Mode.normal)

proc multipleStatusLineSettingCommand(
  status: var EditorStatus,
  command: Runes) =

    if command == ru"on":
      status.settings.statusLine.multipleStatusLine = true
    elif command == ru"off":
      status.settings.statusLine.multipleStatusLine = false

    status.commandLine.clear

    status.changeMode(currentBufStatus.prevMode)

proc showGitInInactiveSettingCommand(
  status: var EditorStatus,
  command: Runes) =

    if command == ru"on": status.settings.statusLine.showGitInactive = true
    elif command == ru"off": status.settings.statusLine.showGitInactive = false

    status.commandLine.clear

    status.changeMode(currentBufStatus.prevMode)

proc ignorecaseSettingCommand(status: var EditorStatus, command: Runes) =
  if command == ru "on": status.settings.standard.ignorecase = true
  elif command == ru "off": status.settings.standard.ignorecase = false

  status.changeMode(currentBufStatus.prevMode)

proc smartcaseSettingCommand(status: var EditorStatus, command: Runes) =
  if command == ru "on": status.settings.standard.smartcase = true
  elif command == ru "off": status.settings.standard.smartcase = false

  status.changeMode(currentBufStatus.prevMode)

proc highlightCurrentLineSettingCommand(
  status: var EditorStatus,
  command: Runes) =

    if command == ru "on": status.settings.view.highlightCurrentLine = true
    elif command == ru "off": status.settings.view.highlightCurrentLine  = false

    status.changeMode(currentBufStatus.prevMode)

proc deleteBufferStatusCommand(status: var EditorStatus, index: int) =
  if index < 0 or index > status.bufStatus.high:
    status.commandLine.writeNoBufferDeletedError
    status.changeMode(bufferstatus.Mode.normal)
    return

  status.bufStatus.delete(index)

  if status.bufStatus.len == 0:
    discard status.addNewBufferInCurrentWin
  elif status.bufferIndexInCurrentWindow > status.bufStatus.high:
    currentMainWindowNode.bufferIndex = status.bufStatus.high

  if currentBufStatus.mode == bufferstatus.Mode.ex:
    let prevMode = currentBufStatus.prevMode
    status.changeMode(prevMode)
  else:
    status.commandLine.clear
    status.changeMode(currentBufStatus.mode)

proc changeFirstBufferCommand(status: var EditorStatus) =
  changeCurrentBuffer(status, 0)

  status.commandLine.clear
  status.changeMode(bufferstatus.Mode.normal)

proc changeLastBufferCommand(status: var EditorStatus) =
  status.changeCurrentBuffer(status.bufStatus.high)

  status.commandLine.clear
  status.changeMode(bufferstatus.Mode.normal)

proc openBufferByNumberCommand(status: var EditorStatus, number: int) =
  if number < 0 or number > status.bufStatus.high: return

  status.changeCurrentBuffer(number)
  status.commandLine.clear
  status.changeMode(bufferstatus.Mode.normal)

proc changeNextBufferCommand(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if currentBufferIndex == status.bufStatus.high: return

  status.changeCurrentBuffer(currentBufferIndex + 1)
  currentBufStatus.isUpdate = true

  status.commandLine.clear
  status.changeMode(Mode.normal)

proc changePreveBufferCommand(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if currentBufferIndex < 1: return

  status.changeCurrentBuffer(currentBufferIndex - 1)
  currentBufStatus.isUpdate = true

  status.commandLine.clear

  status.changeMode(Mode.normal)

proc jumpCommand(status: var EditorStatus, line: int) =
  currentBufStatus.jumpLine(currentMainWindowNode, line)

  status.commandLine.clear
  status.changeMode(bufferstatus.Mode.normal)

proc editCommand(status: var EditorStatus, path: Runes) =
  status.changeMode(currentBufStatus.prevMode)

  status.updateLastCursorPosition

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if currentBufStatus.countChange > 0 and
    countReferencedWindow(mainWindowNode, currentBufferIndex) == 1:
    status.commandLine.writeNoWriteError
  else:
    # Add bufStatus if not exist.
    var bufferIndex = status.bufStatus.checkBufferExist(path)
    if isNone(bufferIndex):
      if dirExists($path):
        let err = status.addNewBufferInCurrentWin($path, Mode.filer)
        if err.isErr:
          addMessageLog toRunes(fmt"Failed to open dir: {$path}: {err.error}")
          status.commandLine.writeFileOpenError($path)
      else:
        let err = status.addNewBufferInCurrentWin($path)
        if err.isErr:
          addMessageLog toRunes(fmt"Failed to open file: {$path}: {err.error}")
          status.commandLine.writeFileOpenError($path)

      bufferIndex = some(status.bufStatus.high)

    status.changeCurrentBuffer(bufferIndex.get)

    status.resize

    if not isFilerMode(currentBufStatus.mode):
      currentMainWindowNode.restoreCursorPosition(
        currentBufStatus,
        status.lastPosition)

proc openInHorizontalSplitWindow(
  status: var EditorStatus,
  filename: Runes) =
    status.horizontalSplitWindow
    status.resize

    status.editCommand(filename)

proc openInVerticalSplitWindowCommand(
  status: var EditorStatus,
  filename: Runes) =
    status.verticalSplitWindow
    status.resize

    status.editCommand(filename)

proc execCmdResultToMessageLog*(output: string)=
  var line = ""
  for ch in output:
    if ch == '\n':
      addMessageLog line.toRunes
      line = ""
    else: line.add(ch)

proc buildOnSave(status: var EditorStatus) =
  ## Start a background process for the build.

  let buildProcess = startBackgroundBuild(
    currentBufStatus.path,
    currentBufStatus.language,
    status.settings.buildOnSave.workspaceRoot)

  if buildProcess.isErr:
    status.commandLine.writeMessageFailedBuildOnSave(currentBufStatus.path)
  else:
    status.backgroundTasks.build.add buildProcess.get

proc updateChangedLines(status: var EditorStatus) =
  ## Start a background process for the git diff.

  let gitDiffProcess = startBackgroundGitDiff(
    currentBufStatus.path,
    currentBufStatus.buffer.toRunes,
    currentBufStatus.characterEncoding)
  if gitDiffProcess.isOk:
    status.backgroundTasks.gitDiff.add gitDiffProcess.get
  else:
    status.commandLine.writeGitInfoUpdateError(gitDiffProcess.error)

proc checkAndCreateDir(
  commandLine: var CommandLine,
  filename: Runes): bool =

    # Not include directory
    if not filename.contains(ru"/"): return true

    let pathSplit = splitPath($filename)

    result = true
    if not dirExists(pathSplit.head):
      let isCreateDir = commandLine.askCreateDirPrompt(pathSplit.head)
      if isCreateDir:
        try: createDir(pathSplit.head)
        except OSError: result = false

# Write current editor settings to configuration file
proc writeConfigurationFile(status: var EditorStatus) =
  let
    configFileDir = getHomeDir() / ".config/moe/"
    configFilePath = configFileDir & "moerc.toml"

  let buffer = status.settings.genTomlConfigStr

  if fileExists(configFilePath):
    status.commandLine.writePutConfigFileAlreadyExistError
  else:
    try:
      createDir(configFileDir)
    except IOError:
      status.commandLine.writeSaveError

    let r = saveFile(
      configFilePath.toRunes,
      buffer.toRunes, CharacterEncoding.utf8)
    if r.isOk:
      status.commandLine.writePutConfigFile(configFilePath)
    else:
      status.commandLine.writeSaveError

  status.changeMode(currentBufStatus.prevMode)

proc writeCommand(status: var EditorStatus, path: Runes) =
  if isConfigMode(currentBufStatus.mode, currentBufStatus.prevMode):
    status.writeConfigurationFile
  else:
    if path.len == 0:
      status.commandLine.writeNoFileNameError
      status.changeMode(currentBufStatus.prevMode)
      return

    # Check if the file has been overwritten by another application
    if fileExists($path):
      let
        lastSaveTimeOfBuffer = currentBufStatus.lastSaveTime.toTime
        lastModificationTimeOfFile = getLastModificationTime($path)
      if lastModificationTimeOfFile > lastSaveTimeOfBuffer:
        if not status.commandLine.askFileChangedSinceReading:
          # Cancel overwrite
          status.changeMode(currentBufStatus.prevMode)
          status.commandLine.clear
          return

    ## Ask if you want to create a directory that does not exist
    if not status.commandLine.checkAndCreateDir(path):
      status.changeMode(currentBufStatus.prevMode)
      status.commandLine.writeSaveError
      return

    let r = saveFile(
      path,
      currentBufStatus.buffer.toRunes,
      currentBufStatus.characterEncoding)
    if r.isErr:
      status.commandLine.writeSaveError
      return

    if status.lspClients.contains(currentBufStatus.langId):
      # Send textDocument/didSave notify to the LSP server.
      let err = lspClient.textDocumentDidSave(
        currentBufStatus.version,
        $currentBufStatus.path.absolutePath,
        $currentBufStatus.buffer)
      if err.isErr: error fmt"lsp: {err.error}"

    if currentBufStatus.path != path:
      currentBufStatus.path = path
      currentBufStatus.language = detectLanguage($path)

    # Build on save
    if status.settings.buildOnSave.enable:
      status.buildOnSave
      status.commandLine.writeMessageSaveFileAndStartBuild(
        path,
        status.settings.notification)
    else:
      status.commandLine.writeMessageSaveFile(
        path,
        status.settings.notification)

    # Update the changedLines for git diff.
    if status.settings.git.showChangedLine and
       currentBufStatus.isTrackingByGit:
         status.updateChangedLines

    # Update syntax checker reuslts.
    if status.settings.syntaxChecker.enable:
      let syntaxCheckProcess = startBackgroundSyntaxCheck(
        $currentBufStatus.path,
        currentBufStatus.language)
      if syntaxCheckProcess.isOk:
        status.backgroundTasks.syntaxCheck.add syntaxCheckProcess.get
      else:
        status.commandLine.writeSyntaxCheckError(syntaxCheckProcess.error)

    currentBufStatus.countChange = 0
    currentBufStatus.lastSaveTime = now()
    status.changeMode(currentBufStatus.prevMode)

proc forceWriteCommand(status: var EditorStatus, path: Runes) =
  try:
    setFilePermissions($path, {fpUserRead,fpUserWrite})
  except OSError:
    status.commandLine.writeSaveError
    return

  status.writeCommand(path)

proc quitCommand(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  if currentBufStatus.prevMode != bufferstatus.Mode.normal:
    status.deleteBuffer(currentBufferIndex)
  else:
    let
      numberReferenced = mainWindowNode.countReferencedWindow(currentBufferIndex)
      countChange = currentBufStatus.countChange
      canUndo = currentBufStatus.buffer.canUndo
    if (not isNormalMode(currentBufStatus.mode, currentBufStatus.prevMode)) or
       (countChange == 0 or numberReferenced > 1 or not canUndo):

      status.changeMode(currentBufStatus.prevMode)
      status.closeWindow(currentMainWindowNode)
    else:
      status.commandLine.writeNoWriteError
      status.changeMode(currentBufStatus.prevMode)

proc writeAndQuitCommand(status: var EditorStatus) =
  let path = currentBufStatus.path

  # Check if the file has been overwritten by another application
  if fileExists($path):
    let
      lastSaveTimeOfBuffer = currentBufStatus.lastSaveTime.toTime
      lastModificationTimeOfFile = getLastModificationTime($path)
    if lastModificationTimeOfFile > lastSaveTimeOfBuffer:
      if not status.commandLine.askFileChangedSinceReading:
        # Cancel overwrite
        status.changeMode(currentBufStatus.prevMode)
        status.commandLine.clear
        return

  # Ask if you want to create a directory that does not exist
  if not status.commandLine.checkAndCreateDir(path):
    status.changeMode(currentBufStatus.prevMode)
    status.commandLine.writeSaveError
    return

  let r = saveFile(
    path,
    currentBufStatus.buffer.toRunes,
    currentBufStatus.characterEncoding)
  if r.isErr:
    status.commandLine.writeSaveError
    status.changeMode(currentBufStatus.prevMode)
    return

  if status.lspClients.contains(currentBufStatus.langId):
    # Send textDocument/didSave notify to the LSP server.
    let err = lspClient.textDocumentDidSave(
      currentBufStatus.version,
      $currentBufStatus.path.absolutePath,
      $currentBufStatus.buffer)
    if err.isErr: error fmt"lsp: {err.error}"

  status.changeMode(currentBufStatus.prevMode)
  status.closeWindow(currentMainWindowNode)

proc forceWriteAndQuitCommand(status: var EditorStatus) =
  try:
    setFilePermissions($currentBufStatus.path, {fpUserRead,fpUserWrite})
  except OSError:
    status.commandLine.writeSaveError
    return

  discard status.commandLine.getKey

  status.writeAndQuitCommand

proc forceQuitCommand(status: var EditorStatus) =
  status.changeMode(currentBufStatus.prevMode)
  status.closeWindow(currentMainWindowNode)

proc allBufferQuitCommand(status: var EditorStatus) =
  for i in 0 ..< status.mainWindow.numOfMainWindow:
    let
      node = mainWindowNode.searchByWindowIndex(i)
      bufStatus = status.bufStatus[node.bufferIndex]

    if isNormalMode(bufStatus.mode, bufStatus.prevMode) and
       bufStatus.countChange > 0:
      status.commandLine.writeNoWriteError
      status.changeMode(bufferstatus.Mode.normal)
      return

  status.exitEditor

proc forceAllBufferQuitCommand(status: var EditorStatus) {.inline.} =
  status.exitEditor

proc writeAndQuitAllBufferCommand(status: var EditorStatus) =
  for bufStatus in status.bufStatus:
    let path = bufStatus.path

    # Check if the file has been overwritten by another application
    if fileExists($path):
      let
        lastSaveTimeOfBuffer = currentBufStatus.lastSaveTime.toTime
        lastModificationTimeOfFile = getLastModificationTime($path)
      if lastModificationTimeOfFile > lastSaveTimeOfBuffer:
        if not status.commandLine.askFileChangedSinceReading:
          # Cancel overwrite
          status.changeMode(currentBufStatus.prevMode)
          status.commandLine.clear
          return

    # Ask if you want to create a directory that does not exist
    if not status.commandLine.checkAndCreateDir(path):
      status.changeMode(currentBufStatus.prevMode)
      status.commandLine.writeSaveError
      return

    let r =saveFile(
      path,
      bufStatus.buffer.toRunes,
      bufStatus.characterEncoding)
    if r.isOk:
      status.exitEditor
    else:
      status.commandLine.writeSaveError
      status.changeMode(currentBufStatus.prevMode)
      return

# Save buffer, build and open log viewer
proc buildCommand(status: var EditorStatus) =
  # Force enable a build on save temporarily.
  let currentSetting = status.settings.buildOnSave.enable

  status.settings.buildOnSave.enable = true
  status.writeCommand(currentBufStatus.path)

  status.settings.buildOnSave.enable = currentSetting

  status.openEditorLogViewer

proc shellCommand(status: var EditorStatus, shellCommand: string) =
  saveCurrentTerminalModes()
  exitUi()

  discard execShellCmd(shellCommand)
  discard execShellCmd("printf \"\nPress Enter\"")
  discard execShellCmd("read _")

  restoreTerminalModes()
  status.commandLine.clear

  status.changeMode(currentBufStatus.prevMode)

proc backgroundCommand(status: var EditorStatus) =
  saveCurrentTerminalModes()
  exitUi()
  discard execShellCmd("printf \"Press Enter\"")
  discard execShellCmd("read _")
  restoreTerminalModes()
  status.commandLine.clear
  status.changeMode(currentBufStatus.prevMode)

proc manualCommand(status: var EditorStatus, manualInvocationCommand: string) =
  saveCurrentTerminalModes()
  exitUi()

  # TODO:  Configure a default manual page to show on `:man`.
  let exitCode = execShellCmd(manualInvocationCommand)
  restoreTerminalModes()

  if exitCode != 0:
    status.commandLine.writeManualCommandError(manualInvocationCommand)
  else:
    status.commandLine.clear

  status.changeMode(currentBufStatus.prevMode)

proc listAllBufferCommand(status: var EditorStatus) =
  let swapCurrentBufferIndex = currentMainWindowNode.bufferIndex
  discard status.addNewBufferInCurrentWin
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
    getTerminalHeight() - useStatusLine - enable - 1,
    getTerminalWidth())

  currentMainWindowNode.currentLine = 0

  var highlight = currentBufStatus.highlight
  highlight.updateViewHighlight(
    currentBufStatus,
    currentMainWindowNode,
    status.highlightingText,
    status.settings)

  while true:
    status.update
    hideCursor()

    var key: Option[Rune]
    while key.isNone:
      key = getKey(currentMainWindowNode)

    if isResizeKey(key.get): status.resize
    else: break

  status.settings.view.currentLineNumber = swapCurrentLineNumStting
  status.changeCurrentBuffer(swapCurrentBufferIndex)
  status.deleteBufferStatusCommand(status.bufStatus.high)
  status.commandLine.clear

  currentBufStatus.isUpdate = true

proc replaceBuffer*(status: var EditorStatus, replaceInfo: ReplaceCommandInfo) =
  ## Replace runes in the current buffer.

  if replaceInfo.isGlobal:
    # Replace all
    currentBufStatus.replaceAll(
      Range(first: 0, last: currentBufStatus.buffer.high),
      replaceInfo.sub,
      replaceInfo.by)
  else:
    # Replace only the first words in lines.
    currentBufStatus.replaceOnlyFirstWordInLines(
      Range(first: 0, last: currentBufStatus.buffer.high),
      replaceInfo.sub,
      replaceInfo.by)

proc replaceBufferCommand*(
  status: var EditorStatus,
  command: Runes) {.inline.} =
    ## Replace buffer and change to prev mode.

    let replaceInfo = parseReplaceCommand(command)
    if replaceInfo.sub.len > 0 and replaceInfo.by.len > 0:
      status.replaceBuffer(replaceInfo)

      status.commandLine.clear
      status.changeMode(currentBufStatus.prevMode)

proc createNewEmptyBufferCommand*(status: var EditorStatus) =
  status.changeMode(currentBufStatus.prevMode)

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if status.bufStatus[currentBufferIndex].countChange == 0 or
     mainWindowNode.countReferencedWindow(currentBufferIndex) > 1:
    discard status.addNewBufferInCurrentWin
    status.changeCurrentBuffer(status.bufStatus.high)
  else:
    status.commandLine.writeNoWriteError

proc newEmptyBufferInSplitWindowHorizontally*(status: var EditorStatus) =
  status.changeMode(currentBufStatus.prevMode)

  status.horizontalSplitWindow

  discard status.addNewBufferInCurrentWin
  status.changeCurrentBuffer(status.bufStatus.high)

  status.resize

proc newEmptyBufferInSplitWindowVertically*(status: var EditorStatus) =
  status.changeMode(currentBufStatus.prevMode)

  status.verticalSplitWindow

  discard status.addNewBufferInCurrentWin
  status.changeCurrentBuffer(status.bufStatus.high)

  status.resize

proc lspExecuteCommand(status: var EditorStatus, command: seq[Runes]) =
  status.changeMode(currentBufStatus.prevMode)

  if not status.lspClients.contains(currentBufStatus.langId) or
     not lspClient.isInitialized:
       status.commandLine.writeLspExecuteCommandError(
         "lsp: client is not ready")
       return

  if lspClient.capabilities.get.executeCommand.isNone:
    status.commandLine.writeLspExecuteCommandError(
      "lsp: execute command is unavailable")
    return

  let lspCommand = $command[0]

  if lspCommand notin lspClient.capabilities.get.executeCommand.get:
    status.commandLine.writeLspExecuteCommandError("lsp: unknow command")
    return

  let r = lspClient.workspaceExecuteCommand(
    currentBufStatus.id,
    lspCommand,
    %*command[1 .. ^1].mapIt($it))
  if r.isErr:
    status.commandLine.writeLspExecuteCommandError(r.error)

proc lspFoldingRange(status: var EditorStatus) =
  status.changeMode(currentBufStatus.prevMode)

  if not status.lspClients.contains(currentBufStatus.langId) or
     not lspClient.isInitialized:
       status.commandLine.writeLspExecuteCommandError(
         "lsp: client is not ready")
       return

  if not lspClient.capabilities.get.foldingRange:
    status.commandLine.writeLspFoldingRangeError(
      "lsp: folding range is unavailable")
    return

  let r = lspClient.foldingRange(
    currentBufStatus.id,
    $currentBufStatus.absolutePath)
  if r.isErr:
    status.commandLine.writeLspFoldingRangeError(r.error)

proc saveExCommandHistory(
  exCommandHistory: var seq[Runes],
  command: seq[Runes],
  limit: int) =
    ## Save a command to the exCommandHistory.
    ## If the size exceeds the limit, the oldest will be deleted.

    if limit < 1 or command.len == 0: return

    let cmd = command.join(ru" ")

    if exCommandHistory.len == 0:
      exCommandHistory.add cmd
    elif cmpIgnoreCase($cmd, $exCommandHistory[^1]) != 0:
      exCommandHistory.add cmd

      if exCommandHistory.len > limit:
        let
          first = exCommandHistory.len - limit
          last = first + limit - 1
        exCommandHistory = exCommandHistory[first .. last]

proc isExCommandBuffer*(line: Runes): InputState =
  ## It is assumed to receive the raw command line buffer.

  let commandSplit = line.splitExCommandBuffer

  if commandSplit.len == 0:
    return InputState.Continue
  elif isValidExCommand(commandSplit):
    return InputState.Valid
  else:
    return InputState.Invalid

proc exModeCommand*(status: var EditorStatus, command: seq[Runes]) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  status.exCommandHistory.saveExCommandHistory(
    command,
    status.settings.persist.exCommandHistoryLimit)

  if command.len == 0 or command[0].len == 0:
    status.changeMode(currentBufStatus.prevMode)
  elif isJumpCommand(currentBufStatus, command):
    var line = ($command[0]).parseInt - 1
    if line < 0: line = 0
    if line >= currentBufStatus.buffer.len:
      line = currentBufStatus.buffer.high
    jumpCommand(status, line)
  elif isEditCommand(command):
    status.editCommand(command[1].normalizedPath)
  elif isOpenInHorizontalSplitWindowCommand(command):
    let path =
      if command.len == 2: command[1].normalizedPath
      else: status.bufStatus[currentBufferIndex].path
    status.openInHorizontalSplitWindow(path)
  elif isOpenInVerticalSplitWindowCommand(command):
    status.openInVerticalSplitWindowCommand(command[1])
  elif isWriteCommand(currentBufStatus, command):
    let path = if command.len < 2: currentBufStatus.path else: command[1]
    status.writeCommand(path)
  elif isQuitCommand(command):
    status.quitCommand
  elif isWriteAndQuitCommand(currentBufStatus, command):
    status.writeAndQuitCommand
  elif isForceQuitCommand(command):
    status.forceQuitCommand
  elif isShellCommand(command):
    status.shellCommand(command.join(" ").substr(1))
  elif isBackgroundCommand(command):
    status.backgroundCommand
  elif isManualCommand(command):
    status.manualCommand(command.join(" "))
  elif isReplaceCommand(command):
    status.replaceBufferCommand(command[0])
  elif isChangeNextBufferCommand(command):
    status.changeNextBufferCommand
  elif isChangePreveBufferCommand(command):
    status.changePreveBufferCommand
  elif isOpenBufferByNumberCommand(command):
    status.openBufferByNumberCommand(($command[1]).parseInt)
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
  elif isOpenBufferManagerCommand(command):
    status.openBufferManager
  elif isLiveReloadOfConfSettingCommand(command):
    status.liveReloadOfConfSettingCommand(command[1])
  elif isIncrementalSearchSettingCommand(command):
    status.incrementalSearchSettingCommand(command[1])
  elif isOpenEditorLogViewerCommand(command):
    status.openEditorLogViewer
  elif isOpenLspLogViewerCommand(command):
    status.openLspLogViewer
  elif isHighlightPairOfParenSettingCommand(command):
    status.highlightPairOfParenSettingCommand(command[1])
  elif isAutoDeleteParenSettingCommand(command):
    status.autoDeleteParenSettingCommand(command[1])
  elif isSmoothScrollSettingCommand(command):
    status.smoothScrollSettingCommand(command[1])
  elif isSmoothScrollMinDelaySettingCommand(command):
    status.smoothScrollMinDelaySettingCommand(($command[1]).parseInt)
  elif isSmoothScrollMaxDelaySettingCommand(command):
    status.smoothScrollMaxDelaySettingCommand(($command[1]).parseInt)
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
  elif isNewEmptyBufferInSplitWindowHorizontallyCommand(command):
    status.newEmptyBufferInSplitWindowHorizontally
  elif isNewEmptyBufferInSplitWindowVerticallyCommand(command):
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
  elif isBackupManagerCommand(command):
    status.startBackupManager
  elif isStartConfigModeCommand(command):
    status.openConfigMode
  elif isIgnorecaseSettingCommand(command):
    status.ignorecaseSettingCommand(command[1])
  elif isSmartcaseSettingCommand(command):
    status.smartcaseSettingCommand(command[1])
  elif isForceWriteCommand(command):
    status.forceWriteCommand(status.bufStatus[currentBufferIndex].path)
  elif isForceWriteAndQuitCommand(command):
    status.forceWriteAndQuitCommand
  elif isStartDebugModeCommand(command):
    status.startDebugMode
  elif isHighlightCurrentLineSettingCommand(command):
    status.highlightCurrentLineSettingCommand(command[1])
  elif isBuildCommand(command):
    status.buildCommand
  elif isLspExeCommand(command):
    status.lspExecuteCommand(command[1 .. ^1])
  elif isLspFoldingCommand(command):
    status.lspFoldingRange
  else:
    status.commandLine.writeNotEditorCommandError(command)
    status.changeMode(currentBufStatus.prevMode)

proc execExCommand*(status: var EditorStatus, command: Runes) =
  status.exModeCommand(command.splitExCommandBuffer)
