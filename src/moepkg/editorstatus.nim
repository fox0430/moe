import std/[strutils, os, strformat, tables, times, heapqueue, deques, options,
            encodings]
import syntax/highlite
import gapbuffer, editorview, ui, unicodeext, highlight, fileutils,
       window, color, settings, statusline, bufferstatus, cursor, tabline,
       backup, messages, commandline, register, platform, movement,
       autocomplete, suggestionwindow, filermodeutils, debugmodeutils,
       independentutils, bufferhighlight, helputils

# Save cursor position when a buffer for a window(file) gets closed.
type LastCursorPosition* = object
  path: seq[Rune]
  line: int
  column: int

type EditorStatus* = object
  bufStatus*: seq[BufferStatus]
  filerStatuses: seq[FilerStatus]
  prevBufferIndex*: int
  searchHistory*: seq[Runes]
  exCommandHistory*: seq[Runes]
  normalCommandHistory*: seq[seq[Rune]]
  registers*: Registers
  settings*: EditorSettings
  mainWindow*: MainWindow
  statusLine*: seq[StatusLine]
  timeConfFileLastReloaded*: DateTime
  currentDir: seq[Rune]
  messageLog*: seq[seq[Rune]]
  commandLine*: CommandLine
  tabWindow*: Window
  popUpWindow*: Window
  lastOperatingTime*: DateTime
  autoBackupStatus*: AutoBackupStatus
  isSearchHighlight*: bool
  lastPosition*: seq[LastCursorPosition]
  isReadonly*: bool
  wordDictionary*: WordDictionary
  suggestionWindow*: Option[SuggestionWindow]

proc initEditorStatus*(): EditorStatus =
  result.currentDir = getCurrentDir().toRunes
  result.settings = initEditorSettings()
  result.lastOperatingTime = now()
  result.autoBackupStatus = initAutoBackupStatus()
  result.commandLine = initCommandLine()
  result.mainWindow = initMainWindow()
  result.statusLine = @[initStatusLine()]

  # Init tab line
  if result.settings.tabLine.enable:
    const
      h = 1
      w = 1
      t = 0
      l = 0
      color = EditorColorPair.defaultChar
    result.tabWindow = initWindow(h, w, t, l, color)

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
  status.mainWindow.mainWindowNode

template currentFilerStatus*: var FilerStatus =
  mixin status
  status.filerStatuses[currentBufStatus.filerStatusIndex.get]

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

      # TODO: Remove from here?
      for i in 0 ..< statusLines.len:
        if statusLines[i].windowIndex == currentNode.windowIndex:
          statusLines[i].bufferIndex = bufferIndex

proc changeCurrentBuffer*(status: var EditorStatus, bufferIndex: int) =
  changeCurrentBuffer(
    currentMainWindowNode,
    status.statusLine,
    status.bufStatus,
    bufferIndex)

proc bufferIndexInCurrentWindow*(status: Editorstatus): int {.inline.} =
  currentMainWindowNode.bufferIndex

# TODO: Remove
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
    let
      path = currentBufStatus.path.absolutePath
      line = currentMainWindowNode.currentLine
      column = currentMainWindowNode.currentColumn
    status.lastPosition.add LastCursorPosition(path: path, line: line, column: column)

proc getLastCursorPostion*(lastPosition: seq[LastCursorPosition],
                           path: seq[Rune]): Option[LastCursorPosition] =

  for p in lastPosition:
    if p.path.absolutePath == path.absolutePath:
      return some(p)

proc changeCurrentWin*(status: var EditorStatus, index: int) =
  if index < status.mainWindow.numOfMainWindow and index > 0:
    status.updateLastCursorPostion

    var node = mainWindowNode.searchByWindowIndex(index)
    currentMainWindowNode = node

proc loadExCommandHistory*(): seq[seq[Rune]] =
  let chaheFile = getHomeDir() / ".cache/moe/exCommandHistory"

  if fileExists(chaheFile):
    let f = open(chaheFile, FileMode.fmRead)
    while not f.endOfFile:
      let line = f.readLine
      if line.len > 0:
        result.add ru line

proc loadSearchHistory*(): seq[seq[Rune]] =
  let chaheFile = getHomeDir() / ".cache/moe/searchHistory"

  if fileExists(chaheFile):
    let f = open(chaheFile, FileMode.fmRead)
    while not f.endOfFile:
      let line = f.readLine
      if line.len > 0:
        result.add ru line

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

proc executeOnExit(settings: EditorSettings, platform: Platforms) {.inline.} =
  if not settings.disableChangeCursor:
    changeCursorType(settings.defaultCursor)

  # Without this, the cursor disappears in Windows terminal
  if platform ==  Platforms.wsl:
    unhideCursor()

# Save Ex command history to the file
proc saveExCommandHistory(history: seq[seq[Rune]]) =
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
proc saveSearchHistory(history: seq[seq[Rune]]) =
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

  exitUi()

  executeOnExit(status.settings, CURRENT_PLATFORM)

  quit()

## Add a new FilerStatus and link it to the current bufStatus.
proc addFilerStatus(status: var EditorStatus) {.inline.} =
  status.filerStatuses.add initFilerStatus()
  currentBufStatus.filerStatusIndex = some(status.filerStatuses.high)

## Add a new FilerStatus and link it to the bufStatus.
proc addFilerStatus(status: var EditorStatus, bufStatusIndex: int) {.inline.} =
  status.filerStatuses.add initFilerStatus()
  status.bufStatus[bufStatusIndex].filerStatusIndex =
    some(status.filerStatuses.high)

## Return bufStatus.high after adding a new buffer.
proc addNewBuffer*(
  status: var EditorStatus,
  path: string,
  mode: Mode): Option[int] =

    case mode:
      of Mode.help:
        status.bufStatus.add initBufferStatus(mode)
        status.bufStatus[^1].buffer = initHelpModeBuffer().toGapBuffer
        return some(status.bufStatus.high)
      else:
        try:
          status.bufStatus.add initBufferStatus(path, mode)
        except:
          let errMessage =
            if mode.isFilerMode:
              fmt"Failed to open dir: {path} : {getCurrentExceptionMsg()}"
            else:
              fmt"Failed to open file: {path} {getCurrentExceptionMsg()}"

          status.commandLine.writeError(errMessage.toRunes)
          status.messageLog.add errMessage.toRunes
          return

        return some(status.bufStatus.high)

proc addNewBuffer*(
  status: var EditorStatus,
  mode: Mode): Option[int] {.inline.} =
    const path = ""
    return status.addNewBuffer(path, mode)

## Add a new buffer and change the current buffer to it and init an editor view.
proc addNewBufferInCurrentWin*(
  status: var EditorStatus,
  path: string,
  mode: Mode) =
    let index = status.addNewBuffer(path, mode)
    if index.isNone: return

    status.changeCurrentBuffer(index.get)

    currentMainWindowNode.view = currentBufStatus.buffer.initEditorView(1, 1)

    if mode.isFilerMode:
      status.addFilerStatus

    currentBufStatus.isReadonly = status.isReadonly

proc addNewBufferInCurrentWin*(
  status: var EditorStatus,
  mode: Mode) {.inline.} =
    status.addNewBufferInCurrentWin("", mode)

proc addNewBufferInCurrentWin*(
  status: var EditorStatus,
  filename: string) {.inline.} =
    status.addNewBufferInCurrentWin(filename, Mode.normal)

proc addNewBufferInCurrentWin*(status: var EditorStatus) {.inline.} =
  status.addNewBufferInCurrentWin("")

# TODO: Move to window.nim?
proc getMainWindowHeight*(settings: EditorSettings): int =
  let
    h = getTerminalHeight()
    tabHeight = if settings.tabLine.enable: 1 else: 0
    statusHeight = if settings.statusLine.enable: 1 else: 0
    commandHeight = if settings.statusLine.merge: 1 else: 0

  result = h - tabHeight - statusHeight - commandHeight

proc resizeMainWindowNode(status: var EditorStatus, terminalSize: Size) =
  let
    height = terminalSize.h
    width = terminalSize.w
    tabLineHeight = if status.settings.tabLine.enable: 1 else: 0
    statusLineHeight = if status.settings.statusLine.enable: 1 else: 0
    commandLineHeight = if status.settings.statusLine.merge: 1 else: 0

  let
    y = tabLineHeight
    h = height - tabLineHeight - statusLineHeight - commandLineHeight
    w = width

  mainWindowNode.resize(Position(y: y, x: 0), Size(h: h, w: w))

## Reszie all windows to ui.terminalSize.
proc resize*(status: var EditorStatus) =
  setCursor(false)

  # Get the current terminal from ui.terminalSize.
  let terminalSize = getTerminalSize()

  status.resizeMainWindowNode(terminalSize)

  let
    height = terminalSize.h
    width = terminalSize.w

  const statusLineHeight = 1
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
          h = node.h - statusLineHeight
          adjustedHeight = max(h, 4)
          adjustedWidth = max(node.w - widthOfLineNum, 4)

        # Resize main window.
        node.view.resize(
          status.bufStatus[bufIndex].buffer,
          adjustedHeight,
          adjustedWidth,
          widthOfLineNum)

        # TODO: Fix condition
        if not status.bufStatus[bufIndex].isFilerMode:
          node.view.seekCursor(
            status.bufStatus[bufIndex].buffer,
            node.currentLine,
            node.currentColumn)

        ## Resize multiple status line.
        let
          isMergeStatusLine = status.settings.statusLine.merge
          enableStatusLine = status.settings.statusLine.enable
          mode = status.bufStatus[bufIndex].mode
        if enableStatusLine and
           (not isMergeStatusLine or
           (isMergeStatusLine and mode != Mode.ex)):

          const statusLineHeight = 1
          let
            width = node.w
            y = node.y + adjustedHeight
            x = node.x
          status.statusLine[statusLineIndex].window.resize(
            statusLineHeight,
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
      statusLineHeight = 1
      x = 0
    let
      y = max(height, 4) - 1 - (if status.settings.statusLine.merge: 0 else: 1)
    status.statusLine[0].window.resize(
      statusLineHeight,
      width,
      y,
      x)

  ## Resize tab line.
  if status.settings.tabLine.enable:
    const
      tabLineHeight = 1
      x = 0
      y = 0
    status.tabWindow.resize(tabLineHeight, width, y, x)

  ## Resize command line.
  const
    commandWindowHeight = 1
    x = 0
  let y = max(height, 4) - 1
  status.commandLine.resize(y, x, commandWindowHeight, width)

  setCursor(true)

proc updateStatusLine(status: var Editorstatus) =
  if not status.settings.statusLine.multipleStatusLine:
    const isActiveWindow = true
    let index = status.statusLine[0].bufferIndex
    status.bufStatus[index].writeStatusLine(
      status.statusLine[0],
      currentMainWindowNode,
      isActiveWindow,
      status.settings)
  else:
    for i in 0 ..< status.statusLine.len:
      let
        bufferIndex = status.statusLine[i].bufferIndex
        index = status.statusLine[i].windowIndex
        node = mainWindowNode.searchByWindowIndex(index)
        currentNode = status.mainWindow.currentMainWindowNode
        isActiveWindow = index == currentNode.windowIndex
      status.bufStatus[bufferIndex].writeStatusLine(
        status.statusLine[i],
        node,
        isActiveWindow,
        status.settings)

## Init syntax highlightings in all buffers.
proc initSyntaxHighlight(
  windowNode: var WindowNode,
  bufStatus: var seq[BufferStatus],
  reservedWords: seq[ReservedWord],
  isSyntaxHighlight: bool) =

    # int is buffer index
    var updatedHighlights: seq[(int, Highlight)]
    for index, buf in bufStatus:
      # The filer syntax highlight is initialized/updated in filermode module.
      if buf.isUpdate and not isFilerMode(buf.mode, buf.prevMode):
        let
          lang = if isSyntaxHighlight: buf.language
                 else: SourceLanguage.langNone
          h = ($buf.buffer).initHighlight(reservedWords, lang)
        updatedHighlights.add (index, h)
        bufStatus[index].isUpdate = false

    var queue = initHeapQueue[WindowNode]()
    for node in windowNode.child: queue.push(node)
    while queue.len > 0:
      for i in  0 ..< queue.len:
        var node = queue.pop
        if node.window.isSome:
          for h in updatedHighlights:
            if h[0] == node.bufferIndex:
              node.highlight = h[1]

        if node.child.len > 0:
          for node in node.child: queue.push(node)

proc updateLogViewerBuffer(
  bufStatus: var BufferStatus,
  logs: seq[Runes]) =
  if logs.len > 0 and logs[0].len > 0:
    bufStatus.buffer = logs.toGapBuffer

proc updateLogViewerHighlight(buffer: string): Highlight =
  if buffer.len > 0:
    const emptyReservedWord: seq[ReservedWord] = @[]
    return initHighlight(
      buffer,
      emptyReservedWord,
      SourceLanguage.langNone)

# Update all views, highlighting, cursor, etc.
proc update*(status: var EditorStatus) =
  setCursor(false)

  let settings = status.settings

  if settings.tabLine.enable:
    status.tabWindow.writeTabLineBuffer(
      status.bufStatus,
      status.bufferIndexInCurrentWindow,
      status.mainWindow.mainWindowNode,
      settings.tabline.allBuffer)

  for i, buf in status.bufStatus:
    if buf.isFilerMode and buf.filerStatusIndex.isSome:
      let filerIndex = buf.filerStatusIndex.get
      if status.filerStatuses[filerIndex].isUpdatePathList:
        # Update the filer mode buffer.
        status.filerStatuses[filerIndex].updatePathList(buf.path)
        status.bufStatus[i].buffer =
          status.filerStatuses[filerIndex].initFilerBuffer(
            settings.filer.showIcons).toGapBuffer

    if buf.isLogViewerMode:
      # Update the logviewer mode buffer.
      status.bufStatus[i].updateLogViewerBuffer(
        status.messageLog)

    if buf.isDebugMode:
      # Update the debug mode buffer.
      status.bufStatus[i].buffer = status.bufStatus.initDebugModeBuffer(
        status.mainWindow.mainWindowNode,
        currentMainWindowNode.windowIndex,
        status.settings.debugMode).toGapBuffer

  # Init (Update) syntax highlightings.
  mainWindowNode.initSyntaxHighlight(
    status.bufStatus,
    settings.highlight.reservedWords,
    settings.syntax)

  # Set editor Color Pair for current line highlight.
  # New color pairs are set to Number larger than the maximum value of EditorColorPiar.
  var currentLineColorPair = ord(EditorColorPair.high) + 1

  var queue = initHeapQueue[WindowNode]()
  for node in mainWindowNode.child:
    queue.push(node)
  while queue.len > 0:
    for i in  0 ..< queue.len:
      var node = queue.pop
      if node.window.isSome:
        let bufStatus = status.bufStatus[node.bufferIndex]

        if bufStatus.buffer.high < node.currentLine:
          node.currentLine = bufStatus.buffer.high

        # TODO: Refactor
        if not bufStatus.isInsertMode and
           not bufStatus.isReplaceMode and
           not bufStatus.isConfigMode and
           bufStatus.buffer[node.currentLine].len > 0 and
           bufStatus.buffer[node.currentLine].high < node.currentColumn:
             node.currentColumn = bufStatus.buffer[node.currentLine].high

        let
          currentWindowIndex = currentMainWindowNode.windowIndex
          isCurrentMainWin = if node.windowIndex == currentWindowIndex: true
                             else: false

        let buffer = status.bufStatus[node.bufferIndex].buffer

        # Reload Editorview. This is not the actual terminal view.
        node.view.reload(
          buffer,
          min(node.view.originalLine[0],
          bufStatus.buffer.high))

        # NOTE: node.highlight is not directly change here for performance.
        var highlight = node.highlight

        ## Update highlights
        # TODO: Fix condition
        if bufStatus.isLogViewerMode:
          highlight = updateLogViewerHighlight($buffer)
        if bufStatus.isFilerMode and status.filerStatuses[bufStatus.filerStatusIndex.get].isUpdateView:
          highlight = status.filerStatuses[bufStatus.filerStatusIndex.get].initFilerHighlight(
            buffer,
            node.currentLine)
        if bufStatus.isEditMode:
          highlight.updateHighlight(
            bufStatus,
            node,
            status.isSearchHighlight,
            status.searchHistory,
            settings)

        # TODO: Fix condition. Will use a flag.
        if not bufStatus.isFilerMode:
          node.view.seekCursor(
            buffer,
            node.currentLine,
            node.currentColumn)

        block UpdateTerminalBuffer:
          let selectedRange = Range(
            start: bufStatus.selectedArea.startLine,
            `end`: bufStatus.selectedArea.endLine)

          node.view.update(
            node.window.get,
            settings.view,
            isCurrentMainWin,
            bufStatus.isVisualMode,
            bufStatus.isConfigMode,
            buffer,
            highlight,
            settings.editorColorTheme,
            node.currentLine,
            selectedRange,
            currentLineColorPair)

        # TODO: Fix condition. Will use a flag.
        if isCurrentMainWin and not bufStatus.isFilerMode:
          # Update the cursor position.
          node.cursor.update(node.view, node.currentLine, node.currentColumn)

        # Update the terminal view.
        node.refreshWindow

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  if not currentBufStatus.isFilerMode:
    let
      y = currentMainWindowNode.cursor.y
      x = currentMainWindowNode.view.widthOfLineNum + currentMainWindowNode.cursor.x
    currentMainWindowNode.window.get.moveCursor(y, x)

  if status.settings.statusLine.enable: status.updateStatusLine

  status.commandLine.update

  # TODO: Fix condition.
  if not currentBufStatus.mode.isFilerMode:
    setCursor(true)

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

proc verticalSplitWindow*(status: var EditorStatus) =
  status.updateLastCursorPostion

  # Create the new window
  let buffer = currentBufStatus.buffer
  currentMainWindowNode = currentMainWindowNode.verticalSplit(buffer)
  inc(status.mainWindow.numOfMainWindow)

  if currentBufStatus.isFilerMode:
    # Add a new buffer if the filer mode because need to a new filerStatus.
    let bufSatusIndex = status.addNewBuffer($currentBufStatus.path, Mode.filer)
    if bufSatusIndex.isNone: return

    status.addFilerStatus(bufSatusIndex.get)
    currentMainWindowNode.bufferIndex = bufSatusIndex.get

  status.statusLine.add(initStatusLine())

  status.resize

  var newNode = mainWindowNode.searchByWindowIndex(currentMainWindowNode.windowIndex + 1)
  newNode.restoreCursorPostion(currentBufStatus, status.lastPosition)

proc horizontalSplitWindow*(status: var Editorstatus) =
  status.updateLastCursorPostion

  let buffer = currentBufStatus.buffer
  currentMainWindowNode = currentMainWindowNode.horizontalSplit(buffer)
  inc(status.mainWindow.numOfMainWindow)

  if currentBufStatus.isFilerMode:
    # Add a new buffer if the filer mode because need to a new filerStatus.
    let bufSatusIndex = status.addNewBuffer($currentBufStatus.path, Mode.filer)
    if bufSatusIndex.isNone: return

    status.addFilerStatus(bufSatusIndex.get)
    currentMainWindowNode.bufferIndex = bufSatusIndex.get

  status.statusLine.add(initStatusLine())

  status.resize

  var newNode = mainWindowNode.searchByWindowIndex(currentMainWindowNode.windowIndex + 1)
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
    newCurrentWinIndex = if deleteWindowIndex > numOfMainWindow - 1:
                           status.mainWindow.numOfMainWindow - 1
                         else: deleteWindowIndex

  let node = mainWindowNode.searchByWindowIndex(newCurrentWinIndex)
  status.mainWindow.currentMainWindowNode = node

# TODO: Move to window.nim?
proc moveCurrentMainWindow*(status: var EditorStatus, index: int) =
  if index < 0 or
     status.mainWindow.numOfMainWindow <= index: return

  status.updateLastCursorPostion

  currentMainWindowNode = mainWindowNode.searchByWindowIndex(index)

# TODO: Move to window.nim?
proc moveNextWindow*(status: var EditorStatus) {.inline.} =
  status.updateLastCursorPostion

  status.moveCurrentMainWindow(currentMainWindowNode.windowIndex + 1)

# TODO: Move to window.nim?
proc movePrevWindow*(status: var EditorStatus) {.inline.} =
  status.updateLastCursorPostion

  status.moveCurrentMainWindow(currentMainWindowNode.windowIndex - 1)

proc deleteBuffer*(status: var Editorstatus, deleteIndex: int) =
  let beforeWindowIndex = currentMainWindowNode.windowIndex

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

  let afterWindowIndex = if beforeWindowIndex > status.mainWindow.numOfMainWindow - 1:
                            status.mainWindow.numOfMainWindow - 1
                         else: beforeWindowIndex
  currentMainWindowNode = mainWindowNode.searchByWindowIndex(afterWindowIndex)

proc tryRecordCurrentPosition*(bufStatus: var BufferStatus,
                               windowNode: WindowNode) {.inline.} =

  bufStatus.positionRecord[bufStatus.buffer.lastSuitId] = (windowNode.currentLine,
                                                           windowNode.currentColumn,
                                                           windowNode.expandedColumn)

proc revertPosition*(bufStatus: var BufferStatus,
                     windowNode: WindowNode,
                     id: int) =

  let mess = fmt"The id not recorded was requested. [bufStatus.positionRecord = {bufStatus.positionRecord}, id = {id}]"
  doAssert(bufStatus.positionRecord.contains(id), mess)

  windowNode.currentLine = bufStatus.positionRecord[id].line
  windowNode.currentColumn = bufStatus.positionRecord[id].column
  windowNode.expandedColumn = bufStatus.positionRecord[id].expandedColumn

# TODO: Remove
proc eventLoopTask*(status: var Editorstatus)

# TODO: Move
proc scrollUpNumberOfLines(status: var EditorStatus, numberOfLines: Natural) =
  let destination = max(currentMainWindowNode.currentLine - numberOfLines, 0)

  if status.settings.smoothScroll:
    let currentLine = currentMainWindowNode.currentLine
    for i in countdown(currentLine, destination):
      if i == 0: break

      currentBufStatus.keyUp(currentMainWindowNode)
      status.update
      currentMainWindowNode.setTimeout(status.settings.smoothScrollSpeed)
      var key = ERR_KEY
      key = getKey(currentMainWindowNode)
      if key != ERR_KEY: break

    ## Set default time out setting
    currentMainWindowNode.setTimeout

  else:
    currentBufStatus.jumpLine(currentMainWindowNode, destination)

# TODO: Move
proc pageUp*(status: var EditorStatus) =
  status.scrollUpNumberOfLines(currentMainWindowNode.view.height)

# TODO: Move
proc halfPageUp*(status: var EditorStatus) =
  status.scrollUpNumberOfLines(Natural(currentMainWindowNode.view.height / 2))

# TODO: Move
proc scrollDownNumberOfLines(status: var EditorStatus, numberOfLines: Natural) =
  let
    destination = min(currentMainWindowNode.currentLine + numberOfLines,
                      currentBufStatus.buffer.len - 1)
    currentLine = currentMainWindowNode.currentLine

  if status.settings.smoothScroll:
    for i in currentLine ..< destination:
      if i == currentBufStatus.buffer.high: break

      currentBufStatus.keyDown(currentMainWindowNode)
      status.update
      currentMainWindowNode.setTimeout(status.settings.smoothScrollSpeed)
      var key = ERR_KEY
      key = getKey(currentMainWindowNode)
      if key != ERR_KEY: break

    ## Set default time out setting
    currentMainWindowNode.setTimeout

  else:
    let view = currentMainWindowNode.view
    currentMainWindowNode.currentLine = destination
    currentMainWindowNode.currentColumn = 0
    currentMainWindowNode.expandedColumn = 0

    if not (view.originalLine[0] <= destination and
       (view.originalLine[view.height - 1] == -1 or
       destination <= view.originalLine[view.height - 1])):
      let startOfPrintedLines = max(destination - (currentLine - currentMainWindowNode.view.originalLine[0]), 0)
      currentMainWindowNode.view.reload(currentBufStatus.buffer, startOfPrintedLines)

# TODO: Move
proc pageDown*(status: var EditorStatus) =
  status.scrollDownNumberOfLines(currentMainWindowNode.view.height)

# TODO: Move
proc halfPageDown*(status: var EditorStatus) =
  status.scrollDownNumberOfLines(Natural(currentMainWindowNode.view.height / 2))

proc changeTheme*(status: var EditorStatus) =
  if status.settings.editorColorTheme == ColorTheme.vscode:
    status.settings.editorColorTheme = loadVSCodeTheme()

  setCursesColor(ColorThemeTable[status.settings.editorColorTheme])

  if checkColorSupportedTerminal() == 8:
    convertToConsoleEnvironmentColor(status.settings.editorColorTheme)

proc autoSave(status: var Editorstatus) =
  let interval = status.settings.autoSaveInterval.minutes
  for index, bufStatus in status.bufStatus:
    if bufStatus.path != ru"" and now() > bufStatus.lastSaveTime + interval:
      saveFile(bufStatus.path,
               bufStatus.buffer.toRunes,
               bufStatus.characterEncoding)
      status.commandLine.writeMessageAutoSave(
        bufStatus.path,
        status.settings.notification,
        status.messageLog)
      status.bufStatus[index].lastSaveTime = now()

proc loadConfigurationFile*(status: var EditorStatus) =
  status.settings =
    try:
      loadSettingFile()
    except InvalidItemError:
      let invalidItem = getCurrentExceptionMsg()
      status.commandLine.writeInvalidItemInConfigurationFileError(
        invalidItem,
        status.messageLog)
      initEditorSettings()
    except IOError, TomlError:
      let failureCause = getCurrentExceptionMsg()
      status.commandLine.writeFailedToLoadConfigurationFileError(
        failureCause,
        status.messageLog)
      initEditorSettings()

proc eventLoopTask(status: var Editorstatus) =
  # Auto save
  if status.settings.autoSave: status.autoSave

  # Live reload of configuration file
  if status.settings.liveReloadOfConf and
     status.timeConfFileLastReloaded + 1.seconds < now():
    let beforeTheme = status.settings.editorColorTheme

    status.loadConfigurationFile

    status.timeConfFileLastReloaded = now()
    if beforeTheme != status.settings.editorColorTheme:
      changeTheme(status)
      status.resize

  # Live reload of an open file. a current window's buffer only.
  if status.settings.liveReloadOfFile:
    let lastModificationTime = getLastModificationTime($currentBufStatus.path)
    if 0 == currentBufStatus.countChange and
       lastModificationTime > currentBufStatus.lastSaveTime.toTime:
      let
        encoding =
          if currentBufStatus.characterEncoding == CharacterEncoding.unknown:
            CharacterEncoding.utf8
          else:
            currentBufStatus.characterEncoding
        buffer = convert($currentBufStatus.buffer, $encoding, "UTF-8")

        newText = openFile(currentBufStatus.path)
        newBuffer = convert(($newText.text & "\n"), $newText.encoding, "UTF-8")

      # TODO: Show a warning if both are edited.
      if buffer != newBuffer:
        let newTextAndEncoding = openFile(currentBufStatus.path)
        currentBufStatus.buffer = newTextAndEncoding.text.toGapBuffer
        currentBufStatus.characterEncoding = newTextAndEncoding.encoding
        currentBufStatus.isUpdate = true

  # Automatic backup
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
          status.commandLine,
          status.messageLog)

        status.autoBackupStatus.lastBackupTime = now()

# Get a key from the main current window and execute the event loop.
proc getKeyFromMainWindow*(status: var EditorStatus): Rune =
  result = ERR_KEY
  while result == ERR_KEY:
    status.eventLoopTask

    result = currentMainWindowNode.getKey

    if pressCtrlC:
      pressCtrlC = false
      result = Rune(3)

# Get a key from the command line window and execute the event loop.
proc getKeyFromCommandLine*(status: var EditorStatus): Rune =
  result = ERR_KEY
  while result == ERR_KEY:
    status.eventLoopTask

    result = status.commandLine.getKey

    if pressCtrlC:
      pressCtrlC = false
      result = Rune(3)
