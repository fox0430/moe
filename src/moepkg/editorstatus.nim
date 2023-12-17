#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[strutils, os, strformat, tables, times, heapqueue, deques, options,
            encodings, math]
import pkg/[results, parsetoml]
import syntax/highlite
import lsp/client
import gapbuffer, editorview, ui, unicodeext, highlight, fileutils,
       windownode, color, settings, statusline, bufferstatus, cursor, tabline,
       backup, messages, commandline, registers, platform, movement,
       autocomplete, suggestionwindow, filermodeutils, debugmodeutils,
       independentutils, viewhighlight, helputils, backupmanagerutils,
       diffviewerutils, messagelog, globalsidebar, build, quickrunutils, git,
       syntaxcheck, theme

type
  LastCursorPosition* = object
    ## Save cursor position when a buffer for a window(file) gets closed.
    path: Runes
    line: int
    column: int

  BackgroundTasks* = object
    build*: seq[BuildProcess]
    quickRun*: seq[QuickRunProcess]
    gitDiff*: seq[GitDiffProcess]
    syntaxCheck*: seq[SyntaxCheckProcess]

  EditorStatus* = ref object
    bufStatus*: seq[BufferStatus]
    filerStatuses: seq[FilerStatus]
    prevBufferIndex*: int
    searchHistory*: seq[Runes]
    exCommandHistory*: seq[Runes]
    registers*: Registers
    settings*: EditorSettings
    mainWindow*: MainWindow
    statusLine*: seq[StatusLine]
    timeConfFileLastReloaded*: DateTime
    currentDir: Runes
    commandLine*: CommandLine
    tabLine*: TabLine
    popupWindow*: Window
    lastOperatingTime*: DateTime
    autoBackupStatus*: AutoBackupStatus
    lastPosition*: seq[LastCursorPosition]
    isReadonly*: bool
    wordDictionary*: WordDictionary
    suggestionWindow*: Option[SuggestionWindow]
    sidebar*: Option[GlobalSidebar]
    colorMode*: ColorMode
    backgroundTasks*: BackgroundTasks
    recodingOperationRegister*: Option[Rune]
    highlightingText*: Option[HighlightingText]

    lspClients*: Table[string, LspClient]
      # key is languageId

const
  TabLineWindowHeight = 1
  StatusLineWindowHeight = 1
  CommandLineWindowHeight = 1

proc initEditorStatus*(): EditorStatus =
  result = EditorStatus(
    currentDir: getCurrentDir().toRunes,
    settings: initEditorSettings(),
    lastOperatingTime: now(),
    autoBackupStatus: initAutoBackupStatus(),
    commandLine: initCommandLine(),
    mainWindow: initMainWindow(),
    statusLine: @[initStatusLine()],
    registers: initRegisters())

template currentBufStatus*: var BufferStatus =
  mixin status
  status.bufStatus[status.bufferIndexInCurrentWindow]

template mainWindow*: var MainWindow =
  mixin status
  status.mainWindow

template currentMainWindowNode*: var WindowNode =
  mixin status
  status.mainWindow.currentMainWindowNode

template mainWindowNode*: var WindowNode =
  mixin status
  status.mainWindow.root

template currentFilerStatus*: var FilerStatus =
  mixin status
  status.filerStatuses[currentBufStatus.filerStatusIndex.get]

template currentLineBuffer*: var Runes =
  mixin status
  currentBufStatus.buffer[currentMainWindowNode.currentLine]

proc changeCurrentBuffer*(
  currentNode: var WindowNode,
  statusLines: var seq[StatusLine],
  bufStatuses: seq[BufferStatus],
  bufferIndex: int) =

    if 0 <= bufferIndex and bufferIndex < bufStatuses.len:
      currentNode.bufferIndex = bufferIndex

      currentNode.currentLine = 0
      currentNode.currentColumn = 0
      currentNode.expandedColumn = 0

proc changeCurrentBuffer*(status: var EditorStatus, bufferIndex: int) =
  changeCurrentBuffer(
    currentMainWindowNode,
    status.statusLine,
    status.bufStatus,
    bufferIndex)

proc bufferIndexInCurrentWindow*(status: EditorStatus): int {.inline.} =
  currentMainWindowNode.bufferIndex

proc changeMode*(status: var EditorStatus, mode: Mode) =
  let currentMode = currentBufStatus.mode

  if currentMode != Mode.ex: status.commandLine.clear

  currentBufStatus.prevMode = currentMode
  currentBufStatus.mode = mode

# Set the current cursor postion to status.lastPosition
proc updateLastCursorPostion*(status: var EditorStatus) =
  for i, p in status.lastPosition:
    if p.path.absolutePath == currentBufStatus.path.absolutePath:
      status.lastPosition[i].line = currentMainWindowNode.currentLine
      status.lastPosition[i].column = currentMainWindowNode.currentColumn
      return

  if currentBufStatus.path.len > 0:
    status.lastPosition.add LastCursorPosition(
      path: currentBufStatus.path.absolutePath,
      line: currentMainWindowNode.currentLine,
      column: currentMainWindowNode.currentColumn)

proc getLastCursorPostion*(
  lastPosition: seq[LastCursorPosition],
  path: Runes): Option[LastCursorPosition] =

    for p in lastPosition:
      if p.path.absolutePath == path.absolutePath:
        return some(p)

proc changeCurrentWin*(status: var EditorStatus, index: int) =
  if index < status.mainWindow.numOfMainWindow and index > 0:
    status.updateLastCursorPostion

    var node = mainWindowNode.searchByWindowIndex(index)
    currentMainWindowNode = node

proc loadExCommandHistory*(limit: int): seq[Runes] =
  let chaheFile = getHomeDir() / ".cache/moe/exCommandHistory"

  if fileExists(chaheFile):
    let f = open(chaheFile, FileMode.fmRead)
    while not f.endOfFile:
      let line = f.readLine
      if line.len > 0:
        result.add ru line

      # Ignore if Limit Exceeded.
      if line.len == limit:
        return

proc loadSearchHistory*(limit: int): seq[Runes] =
  let chaheFile = getHomeDir() / ".cache/moe/searchHistory"

  if fileExists(chaheFile):
    let f = open(chaheFile, FileMode.fmRead)
    while not f.endOfFile:
      let line = f.readLine
      if line.len > 0:
        result.add ru line

      # Ignore if Limit Exceeded.
      if line.len == limit:
        return

proc loadLastCursorPosition*(): seq[LastCursorPosition] =
  let chaheFile = getHomeDir() / ".cache/moe/lastPosition"

  if fileExists(chaheFile):
    let f = open(chaheFile, FileMode.fmRead)
    while not f.endOfFile:
      let line = f.readLine

      if line.len > 0:
        let lineSplit = (line.ru).split(ru ':')
        if lineSplit.len == 3:
          var position = LastCursorPosition(path: lineSplit[0])
          try:
            position.line = parseInt($lineSplit[1])
            position.column = parseInt($lineSplit[2])
          except ValueError:
            return

          result.add position

proc executeOnExit(settings: EditorSettings, platform: Platform) {.inline.} =
  if not settings.standard.disableChangeCursor:
    changeCursorType(settings.standard.defaultCursor)

  # Without this, the cursor disappears in Windows terminal
  if platform ==  Platform.wsl:
    showCursor()

# Save Ex command history to the file
proc saveExCommandHistory(history: seq[Runes]) =
  let
    chaheDir = getHomeDir() / ".cache/moe"
    chaheFile = chaheDir / "exCommandHistory"

  createDir(chaheDir)

  var f = open(chaheFile, FileMode.fmWrite)
  defer:
    f.close

  for line in history:
    f.writeLine($line)

# Save the search history to the file
proc saveSearchHistory(history: seq[Runes]) =
  let
    chaheDir = getHomeDir() / ".cache/moe"
    chaheFile = chaheDir / "searchHistory"

  createDir(chaheDir)

  var f = open(chaheFile, FileMode.fmWrite)
  defer:
    f.close

  for line in history:
    f.writeLine($line)

# Save the cursor position to the file
proc saveLastCursorPosition(lastPosition: seq[LastCursorPosition]) =
  let
    chaheDir = getHomeDir() / ".cache/moe"
    chaheFile = chaheDir / "lastPosition"

  createDir(chaheDir)

  var f = open(chaheFile, FileMode.fmWrite)
  defer:
    f.close

  for position in lastPosition:
    f.writeLine(fmt"{$position.path}:{$position.line}:{$position.column}")

proc exitEditor*(status: EditorStatus) =
  if status.settings.persist.exCommand and status.exCommandHistory.len > 0:
    saveExCommandHistory(status.exCommandHistory)

  if status.settings.persist.search and status.searchHistory.len > 0:
    saveSearchHistory(status.searchHistory)

  if status.settings.persist.cursorPosition:
    saveLastCursorPosition(status.lastPosition)

  if dirExists(gitDiffTmpDir()):
    # Cleanup temporary files fot git diff.
    removeDir(gitDiffTmpDir())

  exitUi()

  executeOnExit(status.settings, getPlatform())

  quit()

proc initLsp(
  status: var EditorStatus,
  workspaceRoot, langId: string): Result[(), string] =
    ## Initialize LSP client and server.

    let langId = $status.bufStatus[^1].extension

    if not status.lspClients.contains(langId):
      # Init a LSP client and start a LSP server.
      var c = initLspClient(
        $status.settings.lsp.languages[langId].command)
      if c.isErr:
        status.commandLine.writeLspInitializeError(
          status.settings.lsp.languages[langId].command,
          c.error)
        return Result[(), string].err c.error

      status.lspClients[langId] = c.get

    block:
      # Initialize request
      let err = status.lspClients[langId].initialize(
        status.bufStatus[^1].id,
        initInitializeParams(
          workspaceRoot,
          status.settings.lsp.languages[langId].trace))
      if err.isErr:
        return Result[(), string].err err.error

    block:
      # Initialized notification
      let err = status.lspClients[langId].initialized
      if err.isErr:
        return Result[(), string].err err.error

    block:
      # workspace/didChangeConfiguration notification
      let err = status.lspClients[langId]
        .workspaceDidChangeConfiguration
      if err.isErr:
        return Result[(), string].err err.error

    block:
      # textDocument/diOpen notification
      let err = status.lspClients[langId].textDocumentDidOpen(
        $status.bufStatus[^1].path.absolutePath,
        langId,
        status.bufStatus[^1].buffer.toString)
      if err.isErr:
        status.commandLine.writeLspInitializeError(
          status.settings.lsp.languages[langId].command,
          err.error)

    return Result[(), string].ok ()

proc addFilerStatus*(status: var EditorStatus) {.inline.} =

  ## Add a new FilerStatus and link it to the current bufStatus.

  status.filerStatuses.add initFilerStatus()
  currentBufStatus.filerStatusIndex = some(status.filerStatuses.high)

proc addFilerStatus*(status: var EditorStatus, bufStatusIndex: int) {.inline.} =
  ## Add a new FilerStatus and link it to the bufStatus.

  status.filerStatuses.add initFilerStatus()
  status.bufStatus[bufStatusIndex].filerStatusIndex =
    some(status.filerStatuses.high)

proc addNewBuffer*(
  status: var EditorStatus,
  path: string,
  mode: Mode): Result[int, string] =
    ## Return bufStatus.high after adding a new buffer.

    case mode:
      of Mode.help:
        status.bufStatus.add initBufferStatus(mode).get
        status.bufStatus[^1].buffer = initHelpModeBuffer().toGapBuffer
      of Mode.backup:
        # Get a backup history of the current buffer.
        let sourceFilePath = currentBufStatus.absolutePath
        status.bufStatus.add initBufferStatus(mode).get
        status.bufStatus[^1].buffer = initBackupManagerBuffer(
          status.settings.autoBackup.backupDir,
          sourceFilePath).toGapBuffer
        # Set the source file path to bufStatus.path.
        status.bufStatus[^1].path = sourceFilePath
      of Mode.diff:
        let
          sourceFilePath = $currentBufStatus.path
          baseBackupDir = $status.settings.autoBackup.backupDir
          backupDir = backupDir(baseBackupDir, sourceFilePath)
          backupFilePath = backupDir / $currentLineBuffer
        status.bufStatus.add initBufferStatus(mode).get
        status.bufStatus[^1].buffer = initDiffViewerBuffer(
          sourceFilePath,
          backupFilePath).toGapBuffer
        status.bufStatus[^1].path = backupFilePath.toRunes
      else:
        let b = initBufferStatus(path, mode)
        if b.isOk:
          status.bufStatus.add b.get
        else:
          let errMessage =
            if mode.isFilerMode:
              fmt"Failed to open dir: {path} : {getCurrentExceptionMsg()}"
            else:
              fmt"Failed to open file: {path} {getCurrentExceptionMsg()}"

          status.commandLine.writeError(errMessage.toRunes)
          addMessageLog errMessage
          return Result[int, string].err errMessage

        if status.settings.git.showChangedLine and
           status.bufStatus[^1].isTrackingByGit:
             let gitDiffProcess = startBackgroundGitDiff(
               status.bufStatus[^1].path,
               status.bufStatus[^1].buffer.toRunes,
               status.bufStatus[^1].characterEncoding)
             if gitDiffProcess.isOk:
               status.backgroundTasks.gitDiff.add gitDiffProcess.get
             else:
               status.commandLine.writeGitInfoUpdateError(gitDiffProcess.error)

        if status.settings.lsp.enable:
          let langId = $status.bufStatus[^1].extension

          if langId.len > 0 and
             status.settings.lsp.languages.contains(langId) and
             not status.lspClients.contains($status.bufStatus[^1].extension):
               # Init LSP client and server.
               let langId = $status.bufStatus[^1].extension

               let err = status.initLsp(
                 $status.bufStatus[^1].openDir,
                 langId)
               if err.isOk:
                 status.commandLine.writeLspInitialized(
                   status.settings.lsp.languages[langId].command)
               else:
                 status.commandLine.writeLspInitializeError(
                   status.settings.lsp.languages[langId].command,
                   err.error)

    return Result[int, string].ok status.bufStatus.high

proc addNewBuffer*(status: var EditorStatus, mode: Mode): Result[int, string] =
  const Path = ""
  return status.addNewBuffer(Path, mode)

proc addNewBufferInCurrentWin*(
  status: var EditorStatus,
  path: string,
  mode: Mode): Result[(), string] =
    ## Add a new buffer and change the current buffer to it and init an editor
    ## view.

    let index = status.addNewBuffer(path, mode)
    if index.isErr:
      return Result[(), string].err fmt"Failed to add new buffer: {index.error}"

    status.changeCurrentBuffer(index.get)

    currentMainWindowNode.view = currentBufStatus.buffer.initEditorView(1, 1)
    if status.settings.view.sidebar:
      currentMainWindowNode.view.initSidebar

    if mode.isFilerMode:
      status.addFilerStatus

    currentBufStatus.isReadonly = status.isReadonly

    return Result[(), string].ok ()

proc addNewBufferInCurrentWin*(
  status: var EditorStatus,
  mode: Mode): Result[(), string] {.inline.} =
    status.addNewBufferInCurrentWin("", mode)

proc addNewBufferInCurrentWin*(
  status: var EditorStatus,
  filename: string): Result[(), string] {.inline.} =
    status.addNewBufferInCurrentWin(filename, Mode.normal)

proc addNewBufferInCurrentWin*(
  status: var EditorStatus): Result[(), string] {.inline.} =
    const Path = ""
    status.addNewBufferInCurrentWin(Path)

proc resizeMainWindowNode(status: var EditorStatus, terminalSize: Size) =
  let
    height = terminalSize.h
    tabLineHeight =
      if status.settings.tabLine.enable: TabLineWindowHeight
      else: 0
    statusLineHeight =
      if status.settings.statusLine.enable: StatusLineWindowHeight
      else: 0
    commandLineHeight =
      if status.settings.statusLine.merge: CommandLineWindowHeight
      else: 0
    sidebarWidth =
      if status.sidebar.isSome: status.sidebar.get.w
      else: 0
    width =
      if status.sidebar.isSome: terminalSize.w - sidebarWidth
      else: terminalSize.w

    y = tabLineHeight
    x =
      if status.sidebar.isSome: sidebarWidth
      else: 0
    h = height - tabLineHeight - statusLineHeight - commandLineHeight
    w = width

  mainWindowNode.resize(Position(y: y, x: x), Size(h: h, w: w))

proc resize*(status: var EditorStatus) =
  ## Reszie all windows to ui.terminalSize.

  if currentBufStatus.isCursor:
    # Disable the cursor while updating views.
    hideCursor()

  # Get the current terminal from ui.terminalSize.
  let terminalSize = getTerminalSize()

  status.resizeMainWindowNode(terminalSize)

  let
    terminalHeight = terminalSize.h
    terminalWidth = terminalSize.w

  const StatusLineHeight = 1
  var
    statusLineIndex = 0
    queue = initHeapQueue[WindowNode]()

  for node in mainWindowNode.child:
    queue.push(node)
  while queue.len > 0:
    let queueLength = queue.len
    for i in  0 ..< queueLength:
      let node = queue.pop
      if node.window.isSome:
        let
          bufIndex = node.bufferIndex
          widthOfLineNum = node.view.widthOfLineNum
          h = node.h - StatusLineHeight
          sidebarWidth =
            if node.view.sidebar.isSome: 2
            else: 2
          adjustedHeight = max(h, 4)
          adjustedWidth = max(node.w - widthOfLineNum - sidebarWidth, 4)

        # Resize EditorView.
        node.view.resize(
          status.bufStatus[bufIndex].buffer,
          adjustedHeight,
          adjustedWidth,
          widthOfLineNum)

        if status.bufStatus[bufIndex].isCursor:
          node.view.seekCursor(
            status.bufStatus[bufIndex].buffer,
            node.currentLine,
            node.currentColumn)

        # Resize multiple status line.
        let
          isMergeStatusLine = status.settings.statusLine.merge
          enableStatusLine = status.settings.statusLine.enable
          mode = status.bufStatus[bufIndex].mode
        if enableStatusLine and
           (not isMergeStatusLine or (isMergeStatusLine and mode != Mode.ex)):
             const StatusLineHeight = 1
             let
               width = node.w
               y = node.y + adjustedHeight
               x = node.x
             status.statusLine[statusLineIndex].window.resize(
               StatusLineHeight,
               width,
               y,
               x)
             status.statusLine[statusLineIndex].window.refresh

             # Update status line info.
             status.statusLine[statusLineIndex].bufferIndex =
               node.bufferIndex
             status.statusLine[statusLineIndex].windowIndex =
               node.windowIndex
             inc(statusLineIndex)

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  # Resize single status line.
  if status.settings.statusLine.enable and
     not status.settings.statusLine.multipleStatusLine:
    const
      StatusLineHeight = 1
      X = 0
    let
      y =
        max(terminalHeight, 4) -
        1 -
        (if status.settings.statusLine.merge: 0 else: 1)
      w =
        if status.sidebar.isSome: mainWindowNode.w
        else: terminalWidth
    status.statusLine[0].window.resize(StatusLineHeight, w, y, X)

  if status.settings.tabLine.enable:
    # Resize the tabline.
    status.tabLine.update(
      status.bufStatus,
      status.bufferIndexInCurrentWindow,
      status.settings.tabLine.allBuffer)

  # Resize the sidebar
  if status.sidebar.isSome:
    let rect = Rect(
      x: 0,
      y: 0,
      h: terminalHeight - CommandLineWindowHeight,
      w: terminalWidth - mainWindowNode.w)
    status.sidebar.get.resize(rect)

  # Resize command line.
  const X = 0
  let y = max(terminalHeight, 4) - 1
  status.commandLine.resize(y, X, CommandLineWindowHeight, terminalWidth)

  if currentBufStatus.isCursor:
    showCursor()

proc updateStatusLine(status: var EditorStatus) =
  if not status.settings.statusLine.multipleStatusLine:
    const IsActiveWindow = true
    let index = status.statusLine[0].bufferIndex
    status.statusLine[0].updateStatusLine(
      status.bufStatus[index],
      currentMainWindowNode,
      IsActiveWindow,
      status.settings)
  else:
    for i in 0 ..< status.statusLine.len:
      let
        bufferIndex = status.statusLine[i].bufferIndex
        index = status.statusLine[i].windowIndex
        node = mainWindowNode.searchByWindowIndex(index)
        currentNode = status.mainWindow.currentMainWindowNode
        isActiveWindow = index == currentNode.windowIndex
      status.statusLine[i].updateStatusLine(
        status.bufStatus[bufferIndex],
        node,
        isActiveWindow,
        status.settings)

proc checkBufferStatusUpdate(status: EditorStatus) =
  ## Update syntax highlightings in all buffers.
  ## And send textDocument/didChange to LSP servers.

  var newHighlights: seq[tuple[bufIndex: int, highlight: Highlight]]
  for i in 0 .. status.bufStatus.high:
    template buf: var BufferStatus = status.bufStatus[i]

    # The filer syntax highlight is initialized/updated in filermode module.
    if not buf.isFilerMode and buf.isUpdate:
      let
        lang =
          if not status.settings.standard.syntax: SourceLanguage.langNone
          else: buf.language
        h = initHighlight(
          buf.buffer.toSeqRunes,
          status.settings.highlight.reservedWords, lang)
      newHighlights.add (bufIndex: i, highlight: h)

      buf.version.inc

      if status.lspClients.contains($buf.extension) and
         status.lspClients[$buf.extension].isInitialized and
         buf.version > 1:
           # Send a textDocument/didChange notification to the LSP server.
           discard status.lspClients[$buf.extension].textDocumentDidChange(
             buf.version,
             $buf.path.absolutePath,
             $buf.buffer)

      buf.isUpdate = false

  var queue = initHeapQueue[WindowNode]()
  for node in mainWindowNode.child: queue.push(node)
  while queue.len > 0:
    for i in  0 ..< queue.len:
      var node = queue.pop
      if node.window.isSome:
        for h in newHighlights:
          if h.bufIndex == node.bufferIndex and h.highlight != node.highlight:
            node.highlight = h.highlight

            if status.bufStatus[h.bufIndex].isTrackingByGit:
              status.bufStatus[h.bufIndex].isGitUpdate = true

      if node.child.len > 0:
        for node in node.child: queue.push(node)

proc updateLogViewerBuffer(
  bufStatus: var BufferStatus,
  logs: seq[Runes]) =
  if logs.len > 0 and logs[0].len > 0:
    bufStatus.buffer = logs.toGapBuffer

proc initLogViewerHighlight(buffer: seq[Runes]): Highlight =
  if buffer.len > 0:
    const EmptyReservedWord: seq[ReservedWord] = @[]
    return buffer.initHighlight(EmptyReservedWord, SourceLanguage.langNone)

proc updateSuggestWindow(status: var EditorStatus) =
  let
    mainWindowY =
      if status.settings.tabLine.enable: 1
      else: 0
    mainWindowHeight = status.settings.getMainWindowHeight
    (y, x) = status.suggestionWindow.get.calcSuggestionWindowPosition(
      currentMainWindowNode,
      mainWindowHeight)

  status.suggestionWindow.get.writeSuggestionWindow(
    currentMainWindowNode,
    y, x,
    mainWindowY,
    status.settings.statusLine.enable)

proc updateSelectedArea(b: var BufferStatus, windowNode: var WindowNode) =
  if b.isVisualLineMode:
    let
      currentLine = windowNode.currentLine
      column =
        if b.buffer[currentLine].high > 0: b.buffer[currentLine].high
        else: 0
    b.selectedArea.get.endLine = currentLine
    b.selectedArea.get.endColumn = column
  elif b.isVisualMode:
    # visual or visualBlock
    b.selectedArea.get.endLine = windowNode.currentLine
    b.selectedArea.get.endColumn = windowNode.currentColumn

proc updateCommandLine(status: var EditorStatus) =
  ## Update the command line.

  if currentBufStatus.mode.isEditMode and
     currentBufStatus.syntaxCheckResults.len > 0:
       let message = currentBufStatus.syntaxCheckResults.formatedMessage(
         currentMainWindowNode.currentLine)
       if message.isSome:
          # Write messages for syntax checker reuslts.
         status.commandLine.write message.get
       elif status.commandLine.buffer.isSyntaxCheckFormatedMessage:
         # Clear if messages for other lines are still displayed.
         status.commandLine.clear

  if status.commandLine.isUpdate:
    status.commandLine.update

proc updateEditorViewConfig(view: var EditorView, settings: EditorSettings) =
  ## Update `EditorView.config` based on `EditorSettings`.

  template viewConf: var EditorViewConfig = view.config

  if viewConf.colorMode != settings.standard.colorMode:
    viewConf.colorMode = settings.standard.colorMode

  if viewConf.isCursorLine != settings.view.cursorLine:
    viewConf.isCursorLine = settings.view.cursorLine

  if viewConf.isLineNumber != settings.view.lineNumber:
    viewConf.isLineNumber = settings.view.lineNumber

  if viewConf.isIndentationLines != settings.view.indentationLines:
    viewConf.isIndentationLines = settings.view.indentationLines

  if viewConf.isHighlightCurrentLine != settings.view.highlightCurrentLine:
    viewConf.isHighlightCurrentLine = settings.view.highlightCurrentLine

  if viewConf.isHighlightCurrentLineNumber != settings.view.currentLineNumber:
    viewConf.isHighlightCurrentLineNumber = settings.view.currentLineNumber

  if viewConf.tabStop != settings.standard.tabStop:
    viewConf.tabStop = settings.standard.tabStop

proc update*(status: var EditorStatus) =
  ## Update all views, highlighting, cursor, etc.

  # Hide the cursor while updating.
  hideCursor()

  let settings = status.settings

  if settings.tabLine.enable:
    status.tabLine.update(
      status.bufStatus,
      status.bufferIndexInCurrentWindow,
      settings.tabLine.allBuffer)

  for i, buf in status.bufStatus:
    if buf.isFilerMode and buf.filerStatusIndex.isSome:
      let filerIndex = buf.filerStatusIndex.get
      if status.filerStatuses[filerIndex].isUpdatePathList:
        # Update the filer mode buffer.
        status.filerStatuses[filerIndex].updatePathList(buf.path)
        status.bufStatus[i].buffer =
          status.filerStatuses[filerIndex].initFilerBuffer(
            settings.filer.showIcons).toGapBuffer
    elif buf.isLogViewerMode:
      # Update the logviewer mode buffer.
      status.bufStatus[i].updateLogViewerBuffer(getMessageLog())
    elif buf.isDebugMode:
      # Update the debug mode buffer.
      status.bufStatus[i].buffer = status.bufStatus.initDebugModeBuffer(
        status.mainWindow.root,
        currentMainWindowNode.windowIndex,
        status.settings.debugMode).toGapBuffer

  status.checkBufferStatusUpdate

  if currentBufStatus.isVisualMode:
    currentBufStatus.updateSelectedArea(currentMainWindowNode)

  # Set editor Color Pair for current line highlight.
  # New color pairs are set to number larger than the maximum value of EditorColorPiarIndex.
  var currentLineColorPair: int = ord(EditorColorPairIndex.high) + 1

  var queue = initHeapQueue[WindowNode]()
  for node in mainWindowNode.child:
    queue.push(node)
  while queue.len > 0:
    for i in  0 ..< queue.len:
      var node = queue.pop
      if node.window.isSome:
        template b: var BufferStatus = status.bufStatus[node.bufferIndex]

        if b.buffer.high < node.currentLine:
          node.currentLine = b.buffer.high

        # TODO: Remove
        if not b.isInsertMode and
           not b.isReplaceMode and
           not b.isConfigMode and
           not b.isVisualMode and
           b.buffer[node.currentLine].len > 0 and
           b.buffer[node.currentLine].high < node.currentColumn:
             node.currentColumn = b.buffer[node.currentLine].high

        # Reload Editorview. This is not the actual terminal view.
        node.view.reload(
          b.buffer,
          min(node.view.originalLine[0],
          b.buffer.high))

        node.view.seekCursor(b.buffer, node.currentLine, node.currentColumn)

        # NOTE: node.highlight is not directly change here for performance.
        var highlight = node.highlight

        # Update highlights
        if b.isLogViewerMode:
          highlight = initLogViewerHighlight(b.buffer.toSeqRunes)
        elif b.isDiffViewerMode:
          highlight = b.buffer.toRunes.initDiffViewerHighlight
        elif b.isFilerMode and
             status.filerStatuses[b.filerStatusIndex.get].isUpdateView:
               highlight = initFilerHighlight(
                 status.filerStatuses[b.filerStatusIndex.get],
                 b.buffer,
                 node.currentLine)
        elif b.isEditMode:
          highlight.updateViewHighlight(
            b,
            node,
            status.highlightingText,
            settings)

        if node.view.sidebar.isSome:
          # Update the EditorView.Sidebar.buffer

          node.view.clearSidebar

          if settings.git.showChangedLine:
            # Write change lines to the sidebar
            node.view.updateSidebarBufferForChangedLine(
              b.changedLines)

          if status.settings.syntaxChecker.enable:
            # Write syntax checker reuslts to the sidebar
            node.view.updateSidebarBufferForSyntaxChecker(
              b.syntaxCheckResults)

        node.view.updateEditorViewConfig(status.settings)

        block updateTerminalBuffer:
          if node.view.editorMode != b.mode: node.view.editorMode = b.mode

          if b.selectedArea.isSome:
            if node.view.selectedRange.first != b.selectedArea.get.startLine:
              node.view.selectedRange.first = b.selectedArea.get.startLine
            if node.view.selectedRange.last != b.selectedArea.get.endLine:
              node.view.selectedRange.last = b.selectedArea.get.endLine

          node.view.isCurrentWin =
            if node.windowIndex == currentMainWindowNode.windowIndex: true
            else: false

          node.view.update(
            node.window.get,
            b.buffer,
            highlight,
            node.currentLine,
            currentLineColorPair)

        if node.view.isCurrentWin:
          # Update the cursor position.
          node.cursor.update(node.view, node.currentLine, node.currentColumn)

        # Update the terminal view.
        node.refreshWindow

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  # Update the suggestion window
  if status.suggestionWindow.isSome:
    status.updateSuggestWindow

  if not currentBufStatus.isFilerMode:
    let
      y = currentMainWindowNode.cursor.y
      x = currentMainWindowNode.view.sidebarWidth +
          currentMainWindowNode.view.widthOfLineNum +
          currentMainWindowNode.cursor.x
    currentMainWindowNode.window.get.moveCursor(y, x)

  if status.settings.statusLine.enable: status.updateStatusLine

  if status.sidebar.isSome: status.sidebar.get.update

  status.updateCommandLine

  if not currentBufStatus.isCommandLineMode and
     status.recodingOperationRegister.isSome:
       # Always write a message to the command line while recording operations.
       status.commandLine.writeInRecordingOperations(
         status.recodingOperationRegister.get)

  if currentBufStatus.isCursor:
    showCursor()

# Update currentLine and currentColumn from status.lastPosition
proc restoreCursorPostion*(
  node: var WindowNode,
  bufStatus: BufferStatus,
  lastPosition: seq[LastCursorPosition]) =

    let position = lastPosition.getLastCursorPostion(bufStatus.path)

    if isSome(position):
      let posi = position.get
      if posi.line > bufStatus.buffer.high:
        node.currentLine = bufStatus.buffer.high
      else:
        node.currentLine = posi.line

      let currentColumn = bufStatus.buffer[node.currentLine].high
      if posi.column > currentColumn:
        if currentColumn > -1:
          node.currentColumn = bufStatus.buffer[node.currentLine].high
        else:
          node.currentColumn = 0
      else:
        node.currentColumn = posi.column

proc moveCurrentMainWindow*(status: var EditorStatus, index: int) =
  if index < 0 or
     status.mainWindow.numOfMainWindow <= index: return

  status.updateLastCursorPostion

  currentMainWindowNode = mainWindowNode.searchByWindowIndex(index)

proc moveNextWindow*(status: var EditorStatus) {.inline.} =
  status.updateLastCursorPostion

  status.moveCurrentMainWindow(currentMainWindowNode.windowIndex + 1)

proc movePrevWindow*(status: var EditorStatus) {.inline.} =
  status.updateLastCursorPostion

  status.moveCurrentMainWindow(currentMainWindowNode.windowIndex - 1)

proc verticalSplitWindow*(status: var EditorStatus) =
  status.updateLastCursorPostion

  # Create the new window
  let buffer = currentBufStatus.buffer
  currentMainWindowNode = currentMainWindowNode.verticalSplit(buffer)
  inc(status.mainWindow.numOfMainWindow)

  if currentBufStatus.isFilerMode:
    # Add a new buffer if the filer mode because need to a new filerStatus.
    let bufSatusIndex = status.addNewBuffer($currentBufStatus.path, Mode.filer)
    if bufSatusIndex.isErr: return
    status.addFilerStatus(bufSatusIndex.get)

    status.statusLine.add(initStatusLine())

    status.resize

    status.moveNextWindow
    currentMainWindowNode.bufferIndex = bufSatusIndex.get
    status.movePrevWindow
  else:
    status.statusLine.add(initStatusLine())
    status.resize

  var newNode = mainWindowNode.searchByWindowIndex(
    currentMainWindowNode.windowIndex + 1)
  newNode.restoreCursorPostion(currentBufStatus, status.lastPosition)

proc horizontalSplitWindow*(status: var EditorStatus) =
  status.updateLastCursorPostion

  let buffer = currentBufStatus.buffer
  currentMainWindowNode = currentMainWindowNode.horizontalSplit(buffer)
  inc(status.mainWindow.numOfMainWindow)

  if currentBufStatus.isFilerMode:
    # Add a new buffer if the filer mode because need to a new filerStatus.
    let bufSatusIndex = status.addNewBuffer($currentBufStatus.path, Mode.filer)
    if bufSatusIndex.isErr: return
    status.addFilerStatus(bufSatusIndex.get)

    status.statusLine.add(initStatusLine())

    status.resize

    status.moveNextWindow
    currentMainWindowNode.bufferIndex = bufSatusIndex.get
    status.movePrevWindow
  else:
    status.statusLine.add(initStatusLine())
    status.resize

  var newNode = mainWindowNode.searchByWindowIndex(
    currentMainWindowNode.windowIndex + 1)
  newNode.restoreCursorPostion(currentBufStatus, status.lastPosition)

proc closeWindow*(status: var EditorStatus, node: WindowNode) =
  if isNormalMode(currentBufStatus.mode, currentBufStatus.prevMode) or
     isFilerMode(currentBufStatus.mode, currentBufStatus.prevMode):
    status.updateLastCursorPostion

  if status.mainWindow.numOfMainWindow == 1:
    status.exitEditor

  let deleteWindowIndex = node.windowIndex

  mainWindowNode.deleteWindowNode(deleteWindowIndex)
  dec(status.mainWindow.numOfMainWindow)

  if status.settings.statusLine.multipleStatusLine:
    let statusLineHigh = status.statusLine.high
    status.statusLine.delete(statusLineHigh)

  status.resize

  let
    numOfMainWindow = status.mainWindow.numOfMainWindow
    newCurrentWinIndex =
      if deleteWindowIndex > numOfMainWindow - 1:
        status.mainWindow.numOfMainWindow - 1
      else:
        deleteWindowIndex

  let node = mainWindowNode.searchByWindowIndex(newCurrentWinIndex)
  status.mainWindow.currentMainWindowNode = node

proc deleteBuffer*(status: var EditorStatus, deleteIndex: int) =
  let beforeWindowIndex = currentMainWindowNode.windowIndex

  let langId = $status.bufStatus[beforeWindowIndex].extension
  if status.lspClients.contains(langId):
    discard status.lspClients[langId].textDocumentDidClose(
      $status.bufStatus[beforeWindowIndex].path.absolutePath)

  var queue = initHeapQueue[WindowNode]()
  for node in mainWindowNode.child:
    queue.push(node)
  while queue.len > 0:
    for i in 0 ..< queue.len:
      let node = queue.pop
      if node.bufferIndex == deleteIndex:
        status.closeWindow(node)

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  status.resize

  status.bufStatus.delete(deleteIndex)

  queue = initHeapQueue[WindowNode]()
  for node in mainWindowNode.child:
    queue.push(node)
  while queue.len > 0:
    for i in 0 ..< queue.len:
      var node = queue.pop
      if node.bufferIndex > deleteIndex: dec(node.bufferIndex)

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  let afterWindowIndex =
    if beforeWindowIndex > status.mainWindow.numOfMainWindow - 1:
      status.mainWindow.numOfMainWindow - 1
    else:
      beforeWindowIndex
  currentMainWindowNode = mainWindowNode.searchByWindowIndex(afterWindowIndex)

proc recordCurrentPosition*(
  bufStatus: var BufferStatus,
  windowNode: WindowNode) {.inline.} =

    bufStatus.positionRecord[bufStatus.buffer.lastSuitId] = (
      windowNode.currentLine,
      windowNode.currentColumn,
      windowNode.expandedColumn)

proc revertPosition*(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  id: int) =

    let mess =
      fmt"The id not recorded was requested. [bufStatus.positionRecord = {bufStatus.positionRecord}, id = {id}]"
    doAssert(bufStatus.positionRecord.contains(id), mess)

    windowNode.currentLine = bufStatus.positionRecord[id].line
    windowNode.currentColumn = bufStatus.positionRecord[id].column
    windowNode.expandedColumn = bufStatus.positionRecord[id].expandedColumn

proc smoothScrollDelays(totalLines, minDelay, maxDelay: int): seq[int] =
  ## Return all delay values for the smooth scrolling.

  if totalLines == 0: return

  let stepSize = 2.0 / float(totalLines)
  var t = 0.0
  for _ in 0 ..< totalLines:
    # Use a quadratic polynomial
    let delay = float(maxDelay) * (1.5 * (t - 0.5)^2 + 0.3)
    result.add int(delay)
    t += stepSize

proc scrollUpNumberOfLines(status: var EditorStatus, numberOfLines: int) =
  let destination = max(currentMainWindowNode.currentLine - numberOfLines, 0)
  jumpLine(currentBufStatus, currentMainWindowNode, destination)

proc smoothScrollUpNumberOfLines(
  status: var EditorStatus,
  numberOfLines: int): Option[Rune] =
    ## Smooth scroll to top lines.
    ## Interrupt scrolling and return a key If a key is pressed while scrolling.

    let
      currentLine = currentMainWindowNode.currentLine
      destination = max(currentMainWindowNode.currentLine - numberOfLines, 0)

      totalLines = currentLine - destination
      delays = smoothScrollDelays(
        totalLines,
        status.settings.smoothScroll.minDelay,
        status.settings.smoothScroll.maxDelay)

    var delayIndex = 0
    for i in countdown(currentLine, destination + 1):
      if i == 0: break

      currentBufStatus.keyUp(currentMainWindowNode)
      status.update

      let key = currentMainWindowNode.getKey(delays[delayIndex])
      if key.isSome:
        return key

      if i > destination + 1: delayIndex.inc

proc pageUp*(status: var EditorStatus) {.inline.} =
  status.scrollUpNumberOfLines(currentMainWindowNode.view.height)

proc smoothPageUp*(status: var EditorStatus): Option[Rune] {.inline.} =
  status.smoothScrollUpNumberOfLines(currentMainWindowNode.view.height)

proc halfPageUp*(status: var EditorStatus) {.inline.} =
  status.scrollUpNumberOfLines(Natural(currentMainWindowNode.view.height / 2))

proc smoothhalfPageUp*(status: var EditorStatus): Option[Rune] {.inline.} =
  status.smoothScrollUpNumberOfLines(int(currentMainWindowNode.view.height / 2))

proc scrollDownNumberOfLines(status: var EditorStatus, numberOfLines: int) =
  let
    view = currentMainWindowNode.view
    currentLine = currentMainWindowNode.currentLine
    destination = min(
      currentMainWindowNode.currentLine + numberOfLines,
      currentBufStatus.buffer.len - 1)

  currentMainWindowNode.currentLine = destination
  currentMainWindowNode.currentColumn = 0
  currentMainWindowNode.expandedColumn = 0

  if not (view.originalLine[0] <= destination and
     (view.originalLine[view.height - 1] == -1 or
     destination <= view.originalLine[view.height - 1])):
       let
         firstOriginLineInView = currentMainWindowNode.view.originalLine[0]
         startOfPrintedLines = max(
           destination - (currentLine - firstOriginLineInView),
           0)
       currentMainWindowNode.view.reload(
         currentBufStatus.buffer,
         startOfPrintedLines)

proc smoothScrollDownNumberOfLines(
  status: var EditorStatus,
  numberOfLines: int): Option[Rune] =
    ## Smooth scroll to bottom lines.
    ## Interrupt scrolling and return a key If a key is pressed while scrolling.

    let
      currentLine = currentMainWindowNode.currentLine
      destination = min(
        currentMainWindowNode.currentLine + numberOfLines,
        currentBufStatus.buffer.len - 1)

      totalLines = destination - currentLine
      delays = smoothScrollDelays(
        totalLines,
        status.settings.smoothScroll.minDelay,
        status.settings.smoothScroll.maxDelay)

    var delayIndex = 0
    for i in currentLine ..< destination:
      if i == currentBufStatus.buffer.high: break

      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

      let key = currentMainWindowNode.getKey(delays[delayIndex])
      if key.isSome:
        return key

      if i < destination: delayIndex.inc

proc pageDown*(status: var EditorStatus) {.inline.} =
  status.scrollDownNumberOfLines(currentMainWindowNode.view.height)

proc smoothPageDown*(status: var EditorStatus): Option[Rune] {.inline.} =
  status.smoothScrollDownNumberOfLines(currentMainWindowNode.view.height)

proc halfPageDown*(status: var EditorStatus) {.inline.} =
  status.scrollDownNumberOfLines(int(currentMainWindowNode.view.height / 2))

proc smoothHalfPageDown*(status: var EditorStatus): Option[Rune] {.inline.} =
  status.smoothScrollDownNumberOfLines(
    int(currentMainWindowNode.view.height / 2))

proc changeTheme*(s: var EditorSettings): Result[(), string] =
  case s.theme.kind:
    of ColorThemeKind.default:
      s.theme.colors = DefaultColors
    of ColorThemeKind.config:
      let toml = loadThemeFile(s.theme.path)
      if toml.isErr: return Result[(), string].err toml.tryError
      s.theme.colors = toml.get.toThemeColors
    of ColorThemeKind.vscode:
      let colors = loadVSCodeTheme()
      if colors.isErr: return Result[(), string].err colors.error
      s.theme.colors = colors.get

  let r = s.theme.colors.initEditrorColor(s.standard.colorMode)
  if r.isErr: return Result[(), string].err r.error

  return Result[(), string].ok ()

proc autoSave(status: var EditorStatus) =
  let interval = status.settings.autoSave.interval.minutes
  for index, bufStatus in status.bufStatus:
    if bufStatus.path != ru"" and now() > bufStatus.lastSaveTime + interval:
      let r = saveFile(
        bufStatus.path,
        bufStatus.buffer.toRunes,
        bufStatus.characterEncoding)
      if r.isErr:
        addMessageLog fmt"Failed to auto save: {bufStatus.path}: {r.get}"
        .toRunes

      status.commandLine.writeMessageAutoSave(
        bufStatus.path,
        status.settings.notification)
      status.bufStatus[index].lastSaveTime = now()

proc loadConfigurationFile*(status: var EditorStatus) =
  if fileExists(configFilePath()):
    let r = status.settings.loadConfigs()
    if r.isErr:
      status.commandLine.writeInvalidItemInConfigurationFileError(r.error)

proc checkBackgroundBuild(status: var EditorStatus) =
  var i = 0
  while i < status.backgroundTasks.build.len:
    template p(): var BuildProcess =
      status.backgroundTasks.build[i]

    if p.isRunning:
      i.inc
    else:
      let r = p.result
      if r.isOk:
        addMessageLog r.get.toSeqRunes
        status.commandLine.writeMessageSuccessBuildOnSave(
          p.filePath,
          status.settings.notification)
      else:
        addMessageLog r.error.toRunes
        status.commandLine.writeMessageFailedBuildOnSave(p.filePath)

      # Back to the cursor position to the current main window from the command
      # line window.
      currentMainWindowNode.moveCursor(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      status.backgroundTasks.build.delete i

proc updateQuickRunBuffer(
  bufStatus: var BufferStatus,
  quickRunResult: seq[string]) =

    if quickRunResult.len > bufStatus.buffer.len:
      for i in bufStatus.buffer.len .. quickRunResult.high:
        bufStatus.buffer.add quickRunResult[i].toRunes

      bufStatus.isUpdate = true

proc checkBackgroundQuickRun(status: var EditorStatus) =
  var
    isUpdate = false
    i = 0
  while i < status.backgroundTasks.quickRun.len:
    template p(): var QuickRunProcess =
      status.backgroundTasks.quickRun[i]

    if p.isRunning:
      i.inc
    else:
      let index = status.bufStatus.quickRunBufferIndex(p.filePath)

      if index.isNone:
        p.close
      else:
        let r = p.result
        if r.isOk:
          status.bufStatus[index.get].updateQuickRunBuffer(r.get)
        else:
          status.bufStatus[index.get].updateQuickRunBuffer(@[r.error])

        if not isUpdate and status.bufStatus[index.get].isUpdate:
          isUpdate = true

      status.backgroundTasks.quickRun.delete i

proc checkBackgroundGitDiff(status: var EditorStatus) =
  var i = 0
  while i < status.backgroundTasks.gitDiff.len:
    template p(): var GitDiffProcess =
      status.backgroundTasks.gitDiff[i]

    if p.isRunning:
      i.inc
    else:
      let r = p.result
      if r.isOk:
        let index = status.bufStatus.checkBufferExist(p.filePath)
        if index.isSome:
          let diffs = r.get.parseGitDiffOutput
          if status.bufStatus[index.get].changedLines != diffs:
            status.bufStatus[index.get].updateChangedLines(diffs)

            # The buffer no changed here but need to update the sidebar.
            status.bufStatus[index.get].isUpdate = true

      status.backgroundTasks.gitDiff.delete i

proc checkBackgroundSyntaxCheck(status: var EditorStatus) =
  var i = 0
  while i < status.backgroundTasks.syntaxCheck.len:
    template p(): var SyntaxCheckProcess =
      status.backgroundTasks.syntaxCheck[i]

    if p.isRunning:
      i.inc
    else:
      let r = p.result
      if r.isOk:
        let index = status.bufStatus.checkBufferExist(p.filePath)
        if index.isSome:
          let r = status.bufStatus[index.get].updateSyntaxCheckerResults(r.get)
          if r.isOk:
            # The buffer no changed here but need to update the sidebar.
            status.bufStatus[index.get].isUpdate = true

      status.backgroundTasks.syntaxCheck.delete i

proc checkBackgroundTasks(status: var EditorStatus) =
  ## Check if background processes are finished and if there are finished,
  ## do the next process and delete from `status.backgroundTasks`.

  if status.backgroundTasks.build.len > 0:
    status.checkBackgroundBuild

  if status.backgroundTasks.quickRun.len > 0:
    status.checkBackgroundQuickRun

  if status.backgroundTasks.gitDiff.len > 0:
    status.checkBackgroundGitDiff

  if status.backgroundTasks.syntaxCheck.len > 0:
    status.checkBackgroundSyntaxCheck

proc runBackgroundTasks*(status: var EditorStatus) =
  # BackgroundTasks
  status.checkBackgroundTasks

  # Auto save
  if status.settings.autoSave.enable: status.autoSave

  if status.settings.standard.liveReloadOfConf and
     status.timeConfFileLastReloaded + 1.seconds < now():
       # Live reload of configuration file

       let beforeTheme = status.settings.theme.colors

       status.loadConfigurationFile

       status.timeConfFileLastReloaded = now()
       if beforeTheme != status.settings.theme.colors:
         let r = status.settings.changeTheme
         if r.isErr:
           # Exit the editor if it failed.
           exitUi()
           echo r.error
           raise

         status.resize

  if status.settings.standard.liveReloadOfFile:
    # Live reload of an open file. a current window's buffer only.

    let lastModificationTime = getLastModificationTime($currentBufStatus.path)
    if 0 == currentBufStatus.countChange and
       lastModificationTime > currentBufStatus.lastSaveTime.toTime:
      let
        encoding =
          if currentBufStatus.characterEncoding == CharacterEncoding.unknown:
            CharacterEncoding.utf8
          else:
            currentBufStatus.characterEncoding
        buffer = convert(currentBufStatus.buffer.toString, $encoding, "UTF-8")

      let newTextAndEncoding = openFile(currentBufStatus.path)
      if newTextAndEncoding.isErr:
        addMessageLog fmt"Failed to reload the {currentBufStatus.path}: {newTextAndEncoding.error}"
        .toRunes
      else:
        let newBuffer = convert(
          ($newTextAndEncoding.get.text & "\n"),
          $newTextAndEncoding.get.encoding,
          "UTF-8")

        if buffer != newBuffer:
          if currentBufStatus.countChange > 0:
            # If it was edited with other editors or something.
            status.commandLine.writeBufferChangedWarn(currentBufStatus.path)
          else:
            currentBufStatus.buffer = newTextAndEncoding.get.text.toGapBuffer
            currentBufStatus.characterEncoding = newTextAndEncoding.get.encoding
            currentBufStatus.isUpdate = true

            if currentBufStatus.isTrackingByGit:
              let gitDiffProcess = startBackgroundGitDiff(
                currentBufStatus.path,
                currentBufStatus.buffer.toRunes,
                currentBufStatus.characterEncoding)
              if gitDiffProcess.isOk:
                status.backgroundTasks.gitDiff.add gitDiffProcess.get
              else:
                status.commandLine.writeGitInfoUpdateError(gitDiffProcess.error)

  block automaticBackups:
    let
      lastBackupTime = status.autoBackupStatus.lastBackupTime
      interval = status.settings.autoBackup.interval
      idleTime = status.settings.autoBackup.idleTime

    if status.settings.autoBackup.enable and
       lastBackupTime + interval.minutes < now() and
       status.lastOperatingTime + idleTime.seconds < now():
      for bufStatus in status.bufStatus:
        if isEditMode(bufStatus.mode, bufStatus.prevMode):
          bufStatus.backupBuffer(
            status.settings.autoBackup,
            status.settings.notification,
            status.commandLine)

          status.autoBackupStatus.lastBackupTime = now()

  block updateGitInfo:
    ## Start background tasks for git info updates.

    let
      interval = status.settings.git.updateInterval.milliSeconds
      displayBufIndexes = mainWindowNode.getAllBufferIndex

    if status.lastOperatingTime + interval < now():
      for i, buf in status.bufStatus:
        if displayBufIndexes.contains(i) and buf.isGitUpdate:
          status.bufStatus[i].isGitUpdate = false

          let gitDiffProcess = startBackgroundGitDiff(
            buf.path,
            buf.buffer.toRunes,
            buf.characterEncoding)
          if gitDiffProcess.isOk:
            status.backgroundTasks.gitDiff.add gitDiffProcess.get
          else:
            status.commandLine.writeGitInfoUpdateError(gitDiffProcess.error)

proc getKeyFromMainWindow*(status: var EditorStatus): Rune =
  ## Get a key from the main current window and execute the event loop.

  var key: Option[Rune]
  while key.isNone:
    key = currentMainWindowNode.getKey

    status.runBackgroundTasks
    if status.bufStatus.isUpdate:
      status.update

  return key.get

proc getKeyFromCommandLine*(status: var EditorStatus): Rune =
  ## Get a key from the command line window and execute the event loop.

  var key: Option[Rune]
  while key.isNone:
    key = status.commandLine.getKey

    status.runBackgroundTasks

  return key.get
