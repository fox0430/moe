import std/[strutils, terminal, os, strformat, tables, times, heapqueue, deques,
            options]
import syntax/highlite
import gapbuffer, editorview, ui, unicodeext, highlight, fileutils,
       window, color, settings, statusline, bufferstatus, cursor, tabline,
       backup, messages, commandline, register, platform, commandview, search,
       movement

# Save cursor position when a buffer for a window(file) gets closed.
type LastPosition* = object
  path: seq[Rune]
  line: int
  column: int

type EditorStatus* = object
  bufStatus*: seq[BufferStatus]
  prevBufferIndex*: int
  searchHistory*: seq[seq[Rune]]
  exCommandHistory*: seq[seq[Rune]]
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
  lastPosition*: seq[LastPosition]
  isReadonly*: bool

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

proc changeCurrentBuffer*(status: var EditorStatus, bufferIndex: int) =
  if 0 <= bufferIndex and bufferIndex < status.bufStatus.len:
    currentMainWindowNode.bufferIndex = bufferIndex

    currentMainWindowNode.currentLine = 0
    currentMainWindowNode.currentColumn = 0
    currentMainWindowNode.expandedColumn = 0

    let node = currentMainWindowNode
    for i in 0 ..< status.statusLine.len:
      if status.statusLine[i].windowIndex == node.windowIndex:
        status.statusLine[i].bufferIndex = bufferIndex

proc bufferIndexInCurrentWindow*(status: Editorstatus): int {.inline.} =
  currentMainWindowNode.bufferIndex

proc changeMode*(status: var EditorStatus, mode: Mode) =
  let currentMode = currentBufStatus.mode

  if currentMode != Mode.ex: status.commandLine.erase

  currentBufStatus.prevMode = currentMode
  currentBufStatus.mode = mode

proc changeMode*(bufStatus: var BufferStatus, mode: Mode) {.inline.} =
  bufStatus.prevMode = bufStatus.mode
  bufStatus.mode = mode

# Set current cursor postion to status.lastPosition
proc updateLastCursorPostion*(status: var EditorStatus) {.inline.} =
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
    status.lastPosition.add LastPosition(path: path, line: line, column: column)

proc getLastCursorPostion*(lastPosition: seq[LastPosition],
                           path: seq[Rune]): Option[LastPosition] =

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

proc loadLastPosition*(): seq[LastPosition] =
  let chaheFile = getHomeDir() / ".cache/moe/lastPosition"

  if fileExists(chaheFile):
    let f = open(chaheFile, FileMode.fmRead)
    while not f.endOfFile:
      let line = f.readLine

      if line.len > 0:
        let lineSplit = (line.ru).split(ru ':')
        if lineSplit.len == 3:
          var position = LastPosition(path: lineSplit[0])
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
proc saveLastCursorPosition(lastPosition: seq[LastPosition]) =
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

proc getMainWindowHeight*(settings: EditorSettings, h: int): int =
  let
    tabHeight = if settings.tabLine.enable: 1 else: 0
    statusHeight = if settings.statusLine.enable: 1 else: 0
    commandHeight = if settings.statusLine.merge: 1 else: 0

  result = h - tabHeight - statusHeight - commandHeight

proc resizeMainWindowNode(status: var EditorStatus, height, width: int) =
  let
    tabLineHeight = if status.settings.tabLine.enable: 1 else: 0
    statusLineHeight = if status.settings.statusLine.enable: 1 else: 0
    commandLineHeight = if status.settings.statusLine.merge: 1 else: 0

  const x = 0
  let
    y = tabLineHeight
    h = height - tabLineHeight - statusLineHeight - commandLineHeight
    w = width

  mainWindowNode.resize(y, x, h, w)

proc resize*(status: var EditorStatus, height, width: int) =
  setCursor(false)

  status.resizeMainWindowNode(height, width)

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

        node.view.resize(
          status.bufStatus[bufIndex].buffer,
          adjustedHeight,
          adjustedWidth,
          widthOfLineNum)
        node.view.seekCursor(
          status.bufStatus[bufIndex].buffer,
          node.currentLine,
          node.currentColumn)

        ## Resize status line window
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

          # Update status line info
          status.statusLine[statusLineIndex].bufferIndex =
            node.bufferIndex
          status.statusLine[statusLineIndex].windowIndex =
            node.windowIndex
          inc(statusLineIndex)

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  # Resize status line window
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

  ## Resize tab line window
  if status.settings.tabLine.enable:
    const
      tabLineHeight = 1
      x = 0
      y = 0
    status.tabWindow.resize(tabLineHeight, width, y, x)

  ## Resize command window
  const
    commandWindowHeight = 1
    x = 0
  let y = max(height, 4) - 1
  status.commandLine.resize(y, x, commandWindowHeight, width)

  setCursor(true)

proc highlightPairOfParen(highlight: var Highlight,
                          bufStatus: BufferStatus,
                          windowNode: WindowNode)

proc highlightOtherUsesCurrentWord(highlight: var Highlight,
                                   bufStatus: BufferStatus,
                                   windowNode: WindowNode,
                                   theme: ColorTheme)

proc highlightSelectedArea(highlight: var Highlight,
                           bufStatus: BufferStatus,
                           windowNode: WindowNode)

proc updateHighlight*(highlight: var Highlight,
                      bufStatus: BufferStatus,
                      windowNode: var WindowNode,
                      isSearchHighlight: bool,
                      searchHistory: seq[seq[Rune]],
                      settings: EditorSettings)

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

proc initDebugModeHighlight[T](buffer: T): Highlight

proc initSyntaxHighlight(windowNode: var WindowNode,
                         bufStatus: var seq[BufferStatus],
                         reservedWords: seq[ReservedWord],
                         isSyntaxHighlight: bool) =

  # int is buffer index
  var updatedHighlights: seq[(int, Highlight)]
  for index, buf in bufStatus:
    if buf.isUpdate:
      if isDebugMode(buf.mode, buf.prevMode):
        let h = buf.buffer.initDebugmodeHighlight
        updatedHighlights.add((index, h))
      elif not isFilerMode(buf.mode, buf.prevMode) and
           not isHistoryManagerMode(buf.mode, buf.prevMode) and
           not isDiffViewerMode(buf.mode, buf.prevMode) and
           not isConfigMode(buf.mode, buf.prevMode):
        let
          lang = if isSyntaxHighlight: buf.language
                 else: SourceLanguage.langNone
          h = ($buf.buffer).initHighlight(reservedWords, lang)

        updatedHighlights.add((index, h))

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

proc isLogViewerMode(mode, prevMode: Mode): bool {.inline.} =
  (mode == logViewer) or (mode == ex and prevMode == logViewer)

proc updateLogViewer(bufStatus: var BufferStatus,
                     node: var WindowNode,
                     messageLog: seq[seq[Rune]]) =

  bufStatus.buffer = initGapBuffer(@[ru""])
  for i in 0 ..< messageLog.len:
    bufStatus.buffer.insert(messageLog[i], i)

  const EMPTY_RESERVEDWORD: seq[ReservedWord] = @[]

  node.highlight = initHighlight(
      $bufStatus.buffer,
      EMPTY_RESERVEDWORD,
      SourceLanguage.langNone)

proc updateDebugModeBuffer(status: var EditorStatus)

proc update*(status: var EditorStatus) =
  setCursor(false)

  if status.settings.tabLine.enable:
    status.tabWindow.writeTabLineBuffer(
      status.bufStatus,
      status.bufferIndexInCurrentWindow,
      status.mainWindow.mainWindowNode,
      status.settings.tabline.allBuffer)

  status.updateDebugModeBuffer

  mainWindowNode.initSyntaxHighlight(
    status.bufStatus,
    status.settings.highlightSettings.reservedWords,
    status.settings.syntax)

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
        let
          bufStatus = status.bufStatus[node.bufferIndex]
          currentMode = bufStatus.mode
          prevMode = bufStatus.prevMode

        if bufStatus.buffer.high < node.currentLine:
          node.currentLine = bufStatus.buffer.high
        if not isInsertMode(currentMode) and
           not isReplaceMode(currentMode) and
           not isConfigMode(currentMode, prevMode) and
           bufStatus.buffer[node.currentLine].len > 0 and
           bufStatus.buffer[node.currentLine].high < node.currentColumn:
          node.currentColumn = bufStatus.buffer[node.currentLine].high

        node.view.reload(bufStatus.buffer,
                         min(node.view.originalLine[0],
                         bufStatus.buffer.high))

        let
          currentWindowIndex = currentMainWindowNode.windowIndex
          isCurrentMainWin = if node.windowIndex == currentWindowIndex: true
                             else: false
          settings = status.settings

        # node.highlight is not directly change here for performance.
        var highlight = node.highlight

        ## Update highlight
        ## TODO: Refactor and fix
        if not isFilerMode(currentMode, prevMode) and
           not isHistoryManagerMode(currentMode, prevMode) and
           not isDiffViewerMode(currentMode, prevMode) and
           not isConfigMode(currentMode, prevMode):

          if isLogViewerMode(currentMode, prevMode):
            status.bufStatus[node.bufferIndex].updateLogViewer(node, status.messageLog)
          else:
            highlight.updateHighlight(
              bufStatus,
              node,
              status.isSearchHighlight,
              status.searchHistory,
              settings)

        let
          startSelectedLine = bufStatus.selectArea.startLine
          endSelectedLine = bufStatus.selectArea.endLine

        node.view.seekCursor(bufStatus.buffer,
                             node.currentLine,
                             node.currentColumn)

        node.view.update(node.window.get,
                         status.settings.view,
                         isCurrentMainWin,
                         currentMode,
                         prevMode,
                         bufStatus.buffer,
                         highlight,
                         status.settings.editorColorTheme,
                         node.currentLine,
                         startSelectedLine,
                         endSelectedLine,
                         currentLineColorPair)

        if isCurrentMainWin:
          node.cursor.update(node.view, node.currentLine, node.currentColumn)

        node.refreshWindow

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  let
    currentMode = currentBufStatus.mode
    prevMode = currentBufStatus.prevMode
  if (currentMode != Mode.filer) and
     not (currentMode == Mode.ex and
     prevMode == Mode.filer):
    let
      y = currentMainWindowNode.cursor.y
      x = currentMainWindowNode.view.widthOfLineNum + currentMainWindowNode.cursor.x
    currentMainWindowNode.window.get.moveCursor(y, x)

  if status.settings.statusLine.enable: status.updateStatusLine

  status.commandLine.updateCommandLineView

  setCursor(true)

proc addNewBuffer*(status: var EditorStatus, filename: string, mode: Mode)

# Update currentLine and currentColumn from status.lastPosition
proc restoreCursorPostion*(node: var WindowNode,
                           bufStatus: BufferStatus,
                           lastPosition: seq[LastPosition]) =

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

  let
    mode = currentBufStatus.mode
    prevMode = currentBufStatus.prevMode
  if isFilerMode(mode, prevMode):
    status.bufStatus.add(currentBufStatus)
    currentBufStatus.changeMode(Mode.filer)
    currentMainWindowNode.bufferIndex = status.bufStatus.high

  status.statusLine.add(initStatusLine())

  status.resize(terminalHeight(), terminalWidth())

  var newNode = mainWindowNode.searchByWindowIndex(currentMainWindowNode.windowIndex + 1)
  newNode.restoreCursorPostion(currentBufStatus, status.lastPosition)

proc horizontalSplitWindow*(status: var Editorstatus) =
  status.updateLastCursorPostion

  let buffer = currentBufStatus.buffer
  currentMainWindowNode = currentMainWindowNode.horizontalSplit(buffer)
  inc(status.mainWindow.numOfMainWindow)

  let
    mode = currentBufStatus.mode
    prevMode = currentBufStatus.prevMode
  if isFilerMode(mode, prevMode):
    status.bufStatus.add(currentBufStatus)
    currentBufStatus.changeMode(Mode.filer)
    currentMainWindowNode.bufferIndex = status.bufStatus.high

  status.statusLine.add(initStatusLine())

  status.resize(terminalHeight(), terminalWidth())

  var newNode = mainWindowNode.searchByWindowIndex(currentMainWindowNode.windowIndex + 1)
  newNode.restoreCursorPostion(currentBufStatus, status.lastPosition)

proc closeWindow*(status: var EditorStatus,
                  node: WindowNode,
                  height, width: int) =

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

  status.resize(height, width)

  let
    numOfMainWindow = status.mainWindow.numOfMainWindow
    newCurrentWinIndex = if deleteWindowIndex > numOfMainWindow - 1:
                           status.mainWindow.numOfMainWindow - 1
                         else: deleteWindowIndex

  let node = mainWindowNode.searchByWindowIndex(newCurrentWinIndex)
  status.mainWindow.currentMainWindowNode = node

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

proc writePopUpWindow*(popUpWindow: var Window,
                       h, w, y, x: int,
                       terminalHeight, terminalWidth: int,
                       currentLine: int,
                       buffer: seq[seq[Rune]]) =
  # TODO: Probably, the parameter `y` means the bottom of the window,
  #       but it should change to the top of the window for consistency.

  popUpWindow.erase

  # Pop up window position
  let
    actualY = y.clamp(0, terminalHeight - 1 - h)
    actualX = x.clamp(0, terminalWidth - w)

  popUpWindow.resize(h, w, actualY, actualX)

  let startLine = if currentLine == -1: 0
                  elif currentLine - h + 1 > 0: currentLine - h + 1
                  else: 0
  for i in 0 ..< h:
    if currentLine != -1 and i + startLine == currentLine:
      let color = EditorColorPair.popUpWinCurrentLine
      popUpWindow.write(i, 1, buffer[i + startLine], color, false)
    else:
      let color = EditorColorPair.popUpWindow
      popUpWindow.write(i, 1, buffer[i + startLine], color, false)

  popUpWindow.refresh

proc deletePopUpWindow*(status: var Editorstatus) =
  if status.popUpWindow != nil:
    status.popUpWindow.deleteWindow
    status.update

proc addNewBuffer*(status: var EditorStatus, filename: string, mode: Mode) =

  let path = if isFilerMode(mode): ru absolutePath(filename) else: ru filename

  status.bufStatus.add(initBufferStatus(path, mode))

  let index = status.bufStatus.high

  status.bufStatus[index].isReadonly = status.isReadonly

  if mode == Mode.filer:
    status.bufStatus[index].buffer = initGapBuffer(@[ru ""])
  else:
    if not fileExists(filename):
      status.bufStatus[index].buffer = newFile()
    else:
      try:
        let textAndEncoding = openFile(filename.toRunes)
        status.bufStatus[index].buffer = textAndEncoding.text.toGapBuffer
        status.bufStatus[index].characterEncoding = textAndEncoding.encoding
      except IOError:
        status.commandLine.writeFileOpenError(filename, status.messageLog)
        return

    if filename != "":
      status.bufStatus[index].language = detectLanguage(filename)

  let buffer = status.bufStatus[index].buffer
  currentMainWindowNode.view = buffer.initEditorView(1, 1)

  status.changeCurrentBuffer(index)

proc addNewBuffer*(status: var EditorStatus, mode: Mode) {.inline.} =
  status.addNewBuffer("", mode)

proc addNewBuffer*(status: var EditorStatus, filename: string) {.inline.} =
  status.addNewBuffer(filename, Mode.normal)

proc addNewBuffer*(status: var EditorStatus) {.inline.} =
  status.addNewBuffer("")

proc deleteBuffer*(status: var Editorstatus, deleteIndex,
                   terminalHeight, terminalWidth: int) =
  let beforeWindowIndex = currentMainWindowNode.windowIndex

  var queue = initHeapQueue[WindowNode]()
  for node in mainWindowNode.child:
    queue.push(node)
  while queue.len > 0:
    for i in 0 ..< queue.len:
      let node = queue.pop
      if node.bufferIndex == deleteIndex:
        status.closeWindow(node, terminalHeight, terminalWidth)

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  status.resize(terminalHeight, terminalWidth)

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

proc eventLoopTask*(status: var Editorstatus)

proc initSelectedAreaColorSegment(startLine, startColumn: int): ColorSegment =
  result.firstRow = startLine
  result.firstColumn = startColumn
  result.lastRow = startLine
  result.lastColumn = startColumn
  result.color = EditorColorPair.visualMode

proc overwriteColorSegmentBlock[T](highlight: var Highlight,
                                   area: SelectArea,
                                   buffer: T) =

  var
    startLine = area.startLine
    endLine = area.endLine
    startColumn = area.startColumn
    endColumn = area.endColumn
  if startLine > endLine: swap(startLine, endLine)
  if startColumn > endColumn: swap(startColumn, endColumn)

  for i in startLine .. endLine:
    let colorSegment = ColorSegment(firstRow: i,
                                    firstColumn: startColumn,
                                    lastRow: i,
                                    lastColumn: min(endColumn, buffer[i].high),
                                    color: EditorColorPair.visualMode)
    highlight = highlight.overwrite(colorSegment)

proc highlightSelectedArea(highlight: var Highlight,
                           bufStatus: BufferStatus,
                           windowNode: WindowNode) =

  let area = bufStatus.selectArea

  var colorSegment = initSelectedAreaColorSegment(
    windowNode.currentLine,
    windowNode.currentColumn)

  if area.startLine == area.endLine:
    colorSegment.firstRow = area.startLine
    colorSegment.lastRow = area.endLine
    if area.startColumn < area.endColumn:
      colorSegment.firstColumn = area.startColumn
      colorSegment.lastColumn = area.endColumn
    else:
      colorSegment.firstColumn = area.endColumn
      colorSegment.lastColumn = area.startColumn
  elif area.startLine < area.endLine:
    colorSegment.firstRow = area.startLine
    colorSegment.lastRow = area.endLine
    colorSegment.firstColumn = area.startColumn
    colorSegment.lastColumn = area.endColumn
  else:
    colorSegment.firstRow = area.endLine
    colorSegment.lastRow = area.startLine
    colorSegment.firstColumn = area.endColumn
    colorSegment.lastColumn = area.startColumn

  let
    currentMode = bufStatus.mode
    prevMode = bufStatus.prevMode

  if (currentMode == Mode.visual) or
     (currentMode == Mode.ex and
     prevMode == Mode.visual):
    highlight = highlight.overwrite(colorSegment)
  elif (currentMode == Mode.visualBlock) or
       (currentMode == Mode.ex and
       prevMode == Mode.visualBlock):
    highlight.overwriteColorSegmentBlock(
      bufStatus.selectArea,
      bufStatus.buffer)

proc highlightPairOfParen(highlight: var Highlight,
                          bufStatus: BufferStatus,
                          windowNode: WindowNode) =

  let
    buffer = bufStatus.buffer
    currentLine = windowNode.currentLine
    currentColumn = if windowNode.currentColumn > buffer[currentLine].high:
                      buffer[currentLine].high
                    else: windowNode.currentColumn

  if buffer[currentLine].len < 1 or
     (buffer[currentLine][currentColumn] == ru'"') or
     (buffer[currentLine][currentColumn] == ru'\''): return

  if isOpenParen(buffer[currentLine][currentColumn]):
    var depth = 0
    let
      openParen = buffer[currentLine][currentColumn]
      closeParen = correspondingCloseParen(openParen)
    for i in currentLine ..< buffer.len:
      let startColumn = if i == currentLine: currentColumn else: 0
      for j in startColumn ..< buffer[i].len:
        if buffer[i][j] == openParen: inc(depth)
        elif buffer[i][j] == closeParen: dec(depth)
        if depth == 0:
          let
            color = EditorColorPair.parenText
            colorSegment = ColorSegment(firstRow: i,
                                        firstColumn: j,
                                        lastRow: i,
                                        lastColumn: j,
                                        color: color)
          highlight = highlight.overwrite(colorSegment)
          return

  elif isCloseParen(buffer[currentLine][currentColumn]):
    var depth = 0
    let
      closeParen = buffer[currentLine][currentColumn]
      openParen = correspondingOpenParen(closeParen)
    for i in countdown(currentLine, 0):
      let startColumn = if i == currentLine: currentColumn else: buffer[i].high
      for j in countdown(startColumn, 0):
        if buffer[i].len < 1: break
        if buffer[i][j] == closeParen: inc(depth)
        elif buffer[i][j] == openParen: dec(depth)
        if depth == 0:
          let
            color = EditorColorPair.parenText
            colorSegment = ColorSegment(firstRow: i,
                                        firstColumn: j,
                                        lastRow: i,
                                        lastColumn: j,
                                        color: color)
          highlight = highlight.overwrite(colorSegment)
          return

# Highlighting other uses of the current word under the cursor
proc highlightOtherUsesCurrentWord(highlight: var Highlight,
                                   bufStatus: BufferStatus,
                                   windowNode: WindowNode,
                                   theme: ColorTheme) =

  let line = bufStatus.buffer[windowNode.currentLine]

  if line.len < 1 or
     windowNode.currentColumn > line.high or
     (line[windowNode.currentColumn] != '_' and
     unicodeext.isPunct(line[windowNode.currentColumn])) or
     line[windowNode.currentColumn].isSpace: return
  var
    startCol = windowNode.currentColumn
    endCol = windowNode.currentColumn

  # Set start col
  for i in countdown(windowNode.currentColumn - 1, 0):
    if (line[i] != '_' and unicodeext.isPunct(line[i])) or line[i].isSpace:
      break
    else: startCol.dec

  # Set end col
  for i in windowNode.currentColumn ..< line.len:
    if (line[i] != '_' and unicodeext.isPunct(line[i])) or line[i].isSpace:
      break
    else: endCol.inc

  let highlightWord = line[startCol ..< endCol]

  let
    range = windowNode.view.rangeOfOriginalLineInView
    startLine = range[0]
    endLine = if bufStatus.buffer.len > range[1] + 1: range[1] + 2
              elif bufStatus.buffer.len > range[1]: range[1] + 1
              else: range[1]

  proc isWordAtCursor(highlightWordLen, i, j: int): bool =
    result = i == windowNode.currentLine and
             (j >= startCol and j <= endCol)

  for i in startLine ..< endLine:
    let line = bufStatus.buffer[i]
    for j in 0 .. (line.len - highlightWord.len):
      let endCol = j + highlightWord.len
      if line[j ..< endCol] == highlightWord:
        ## TODO: Refactor
        if j == 0 or
           (j > 0 and
           ((line[j - 1] != '_' and
           unicodeext.isPunct(line[j - 1])) or
           line[j - 1].isSpace)):
          if (j == (line.len - highlightWord.len)) or
             ((line[j + highlightWord.len] != '_' and
             unicodeext.isPunct(line[j + highlightWord.len])) or
             line[j + highlightWord.len].isSpace):

            # Do not highlight current word on the cursor
            if not isWordAtCursor(highlightWord.len, i, j):
              # Set color
              let
                originalColorPair =
                  highlight.getColorPair(i, j)
                colors = theme.getColorFromEditorColorPair(originalColorPair)
              setColorPair(EditorColorPair.currentWord,
                           colors[0],
                           ColorThemeTable[theme].currentWordBg)

              let
                color = EditorColorPair.currentWord
                colorSegment = ColorSegment(firstRow: i,
                                            firstColumn: j,
                                            lastRow: i,
                                            lastColumn: j + highlightWord.high,
                                            color: color)
              highlight = highlight.overwrite(colorSegment)

proc highlightTrailingSpaces(highlight: var Highlight,
                             bufStatus: BufferStatus,
                             windowNode: WindowNode) =

  if isConfigMode(bufStatus.mode, bufStatus.prevMode) or
     isDebugMode(bufStatus.mode, bufStatus.prevMode): return

  let
    currentLine = windowNode.currentLine

    color = EditorColorPair.highlightTrailingSpaces

    range = windowNode.view.rangeOfOriginalLineInView
    buffer = bufStatus.buffer
    startLine = range[0]
    endLine = if buffer.len > range[1] + 1: range[1] + 2
              elif buffer.len > range[1]: range[1] + 1
              else: range[1]

  var colorSegments: seq[ColorSegment] = @[]
  for i in startLine ..< endLine:
    let line = buffer[i]
    if line.len > 0 and i != currentLine:
      var countSpaces = 0
      for j in countdown(line.high, 0):
        if line[j] == ru' ': inc countSpaces
        else: break

      if countSpaces > 0:
        let firstColumn = line.len - countSpaces
        colorSegments.add(ColorSegment(firstRow: i,
                                       firstColumn: firstColumn,
                                       lastRow: i,
                                       lastColumn: line.high,
                                       color: color))

  for colorSegment in colorSegments:
    highlight = highlight.overwrite(colorSegment)

# TODO: Move
# Search text in buffer
proc getKeyword*(status: var EditorStatus,
                 prompt: string,
                 isSearch: bool): (seq[Rune], bool) =

  var
    exStatus = initExModeViewStatus(prompt)
    cancelSearch = false
    searchHistoryIndex = status.searchHistory.high

  template setPrevSearchHistory() =
    if searchHistoryIndex > 0:
      exStatus.clearCommandBuffer
      dec searchHistoryIndex
      exStatus.insertCommandBuffer(status.searchHistory[searchHistoryIndex])

  template setNextSearchHistory() =
    if searchHistoryIndex < status.searchHistory.high:
      exStatus.clearCommandBuffer
      inc searchHistoryIndex
      exStatus.insertCommandBuffer(status.searchHistory[searchHistoryIndex])

  while true:
    status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)

    var key = status.commandLine.getKey

    if isEnterKey(key): break
    elif isEscKey(key):
      cancelSearch = true
      break
    elif isResizeKey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.update
    elif isLeftKey(key): status.commandLine.window.moveLeft(exStatus)
    elif isRightkey(key): exStatus.moveRight
    elif isUpKey(key) and isSearch: setPrevSearchHistory()
    elif isDownKey(key) and isSearch: setNextSearchHistory()
    elif isHomeKey(key): exStatus.moveTop
    elif isEndKey(key): exStatus.moveEnd
    elif isBackspaceKey(key): exStatus.deleteCommandBuffer
    elif isDcKey(key): exStatus.deleteCommandBufferCurrentPosition
    else: exStatus.insertCommandBuffer(key)

  return (exStatus.buffer, cancelSearch)

# TODO: Move
proc getCandidatesExCommandOption(status: var Editorstatus,
                                  exStatus: var ExModeViewStatus,
                                  command: string): seq[seq[Rune]] =

  var argList: seq[string] = @[]
  case toLowerAscii($command):
    of "cursorline",
       "highlightparen",
       "indent",
       "linenum",
       "livereload",
       "realtimesearch",
       "statusline",
       "syntax",
       "tabstop",
       "smoothscroll",
       "clipboard",
       "highlightCurrentLine",
       "highlightcurrentword",
       "highlightfullspace",
       "multiplestatusline",
       "buildonsave",
       "indentationlines",
       "icon",
       "showgitinactive",
       "ignorecase",
       "smartcase": argList = @["on", "off"]
    of "theme": argList= @["vivid", "dark", "light", "config", "vscode"]
    of "e",
       "sp",
       "vs",
       "sv": argList = getCandidatesFilePath(exStatus.buffer, command)
    else: discard

  if argList[0] != "":
    let arg = if (splitWhitespace(exStatus.buffer)).len > 1:
                (splitWhitespace(exStatus.buffer))[1]
              else: ru""
    result = @[arg]

  for i in 0 ..< argList.len:
    result.add(argList[i].toRunes)

# TODO: Move
proc getSuggestList(status: var Editorstatus,
                    exStatus: var ExModeViewStatus,
                    suggestType: SuggestType): seq[seq[Rune]] =

  if isSuggestTypeExCommand(suggestType):
    result = getCandidatesExCommand(exStatus.buffer)
  elif isSuggestTypeExCommandOption(suggestType):
    let cmd = $(splitWhitespace(exStatus.buffer))[0]
    result = status.getCandidatesExCommandOption(exStatus, cmd)
  else:
    let
      cmd = (splitWhitespace(exStatus.buffer))[0]
      pathList = getCandidatesFilePath(exStatus.buffer, $cmd)
    for path in pathList: result.add(path.ru)

proc calcXWhenSuggestPath(buffer: seq[Rune]): int =
  let
    cmd = (splitWhitespace(buffer))[0]
    inputPath = getInputPath(buffer, cmd)
    positionInInputPath = if inputPath.rfind(ru"/") > 0:
                            inputPath.rfind(ru"/")
                          else:
                            0
  # +2 is pronpt and space
  return cmd.len + 2 + positionInInputPath

proc suggestCommandLine(status: var Editorstatus,
                        exStatus: var ExModeViewStatus,
                        key: var Rune) =

  let
    suggestType = getSuggestType(exStatus.buffer)
    suggestlist = status.getSuggestList(exStatus, suggestType)

  var
    suggestIndex = 0
    # Pop up window initial size/position
    h = 1
    w = 1
    x = 0
    y = terminalHeight() - 1

  let command = if exStatus.buffer.len > 0:
                  (splitWhitespace(exStatus.buffer))[0]
                else: ru""

  if isSuggestTypeFilePath(suggestType):
    x = calcXWhenSuggestPath(exStatus.buffer)
  elif isSuggestTypeExCommandOption(suggestType):
    x = command.len + 1

  var popUpWindow = initWindow(h, w, y, x, EditorColorPair.popUpWindow)

  template updateExModeViewStatus() =
    if isSuggestTypeFilePath(suggestType):
      exStatus.buffer = command & ru" "
      exStatus.currentPosition = command.len + exStatus.prompt.len
      exStatus.cursorX = exStatus.currentPosition
    else:
      exStatus.buffer = ru""
      exStatus.currentPosition = 0
      exStatus.cursorX = 0

  # TODO: I don't know why yet,
  #       but there is a bug which is related to scrolling of the pup-up window.

  while (isTabKey(key) or isShiftTab(key)) and suggestlist.len > 1:
    updateExModeViewStatus()

    if isTabKey(key) and suggestIndex < suggestlist.high: inc(suggestIndex)
    elif isShiftTab(key) and suggestIndex > 0: dec(suggestIndex)
    elif isShiftTab(key) and suggestIndex == 0: suggestIndex = suggestlist.high
    else: suggestIndex = 0

    if status.settings.popUpWindowInExmode:
      let
        currentLine = if suggestIndex == 0: -1 else: suggestIndex - 1
        displayBuffer = initDisplayBuffer(suggestlist, suggestType)
      # Pop up window size
      var (h, w) = displayBuffer.calcPopUpWindowSize

      popUpWindow.writePopUpWindow(h, w, y, x,
                                   terminalHeight(), terminalWidth(),
                                   currentLine,
                                   displayBuffer)

    if isSuggestTypeExCommandOption(suggestType):
      exStatus.insertCommandBuffer(command & ru' ')

    exStatus.insertCommandBuffer(suggestlist[suggestIndex])
    exStatus.cursorX.inc

    status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)

    key = errorKey
    while key == errorKey:
      key = status.commandLine.getKey

    exStatus.cursorX = exStatus.currentPosition + 1

  status.commandLine.window.moveCursor(exStatus.cursorY, exStatus.cursorX)
  if status.settings.popUpWindowInExmode: status.deletePopUpWindow

# TODO: Move
proc getKeyOnceAndWriteCommandView*(
  status: var Editorstatus,
  prompt: string,
  buffer: seq[Rune],
  isSuggest, isSearch : bool): (seq[Rune], bool, bool) =

  var
    exStatus = initExModeViewStatus(prompt)
    exitSearch = false
    cancelSearch = false
    searchHistoryIndex = status.searchHistory.high
    commandHistoryIndex = status.exCommandHistory.high
  for rune in buffer: exStatus.insertCommandBuffer(rune)

  template setPrevSearchHistory() =
    if searchHistoryIndex > 0:
      exStatus.clearCommandBuffer
      dec searchHistoryIndex
      exStatus.insertCommandBuffer(status.searchHistory[searchHistoryIndex])

  template setNextSearchHistory() =
    if searchHistoryIndex < status.searchHistory.high:
      exStatus.clearCommandBuffer
      inc searchHistoryIndex
      exStatus.insertCommandBuffer(status.searchHistory[searchHistoryIndex])

  template setNextCommandHistory() =
    if commandHistoryIndex < status.exCommandHistory.high:
      exStatus.clearCommandBuffer
      inc commandHistoryIndex
      exStatus.insertCommandBuffer(status.exCommandHistory[commandHistoryIndex])

  template setPrevCommandHistory() =
    if commandHistoryIndex > 0:
      exStatus.clearCommandBuffer
      dec commandHistoryIndex
      exStatus.insertCommandBuffer(status.exCommandHistory[commandHistoryIndex])

  while true:
    status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)

    var key = errorKey
    while key == errorKey:
      if not pressCtrlC:
        key = status.commandLine.getKey
      else:
        # Exit command line mode
        pressCtrlC = false

        status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)
        exitSearch = true

        return (exStatus.buffer, exitSearch, cancelSearch)

    # Suggestion mode
    if isTabKey(key) or isShiftTab(key):
      status.suggestCommandLine(exStatus, key)
      if status.settings.popUpWindowInExmode and isEnterKey(key):
        status.commandLine.window.moveCursor(exStatus.cursorY, exStatus.cursorX)

    if isEnterKey(key):
      exitSearch = true
      break
    elif isEscKey(key):
      cancelSearch = true
      break
    elif isResizeKey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.update
    elif isLeftKey(key):
      status.commandLine.window.moveLeft(exStatus)
    elif isRightkey(key):
      exStatus.moveRight
      if status.settings.popUpWindowInExmode:
        status.deletePopUpWindow
        status.update
    elif isUpKey(key):
      if isSearch: setPrevSearchHistory()
      else: setPrevCommandHistory()
    elif isDownKey(key):
      if isSearch: setNextSearchHistory()
      else: setNextCommandHistory()
    elif isHomeKey(key):
      exStatus.moveTop
    elif isEndKey(key):
      exStatus.moveEnd
    elif isBackspaceKey(key):
      exStatus.deleteCommandBuffer
      break
    elif isDcKey(key):
      exStatus.deleteCommandBufferCurrentPosition
      break
    else:
      exStatus.insertCommandBuffer(key)
      break

  status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)
  return (exStatus.buffer, exitSearch, cancelSearch)

# TODO: Move
proc getCommand*(status: var EditorStatus, prompt: string): seq[seq[Rune]] =
  var exStatus = initExModeViewStatus(prompt)
  status.resize(terminalHeight(), terminalWidth())

  while true:
    status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)

    var key = status.commandLine.getKey

    # Suggestion mode
    if isTabKey(key) or isShiftTab(key):
      status.suggestCommandLine(exStatus, key)
      if status.settings.popUpWindowInExmode and isEnterKey(key):
          status.commandLine.window.moveCursor(exStatus.cursorY, exStatus.cursorX)
          key = status.commandLine.getKey

    if isEnterKey(key): break
    elif isEscKey(key):
      status.commandLine.erase
      return @[ru""]
    elif isResizeKey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.update
    elif isLeftKey(key): status.commandLine.window.moveLeft(exStatus)
    elif isRightkey(key): moveRight(exStatus)
    elif isHomeKey(key): moveTop(exStatus)
    elif isEndKey(key): moveEnd(exStatus)
    elif isBackspaceKey(key): deleteCommandBuffer(exStatus)
    elif isDcKey(key): deleteCommandBufferCurrentPosition(exStatus)
    else: insertCommandBuffer(exStatus, key)

  return splitCommand($exStatus.buffer)

# TODO: Move
proc searchFirstOccurrence(status: var EditorStatus) =
  var
    exitSearch = false
    cancelSearch = false
    keyword = ru""

  const
    prompt = "/"
    isSuggest = false
    isSearch = true

  while exitSearch == false:
    let returnWord = status.getKeyOnceAndWriteCommandView(
      prompt,
      keyword,
      isSuggest,
      isSearch)

    keyword = returnWord[0]
    exitSearch = returnWord[1]
    cancelSearch = returnWord[2]

    if exitSearch or cancelSearch: break

  if cancelSearch:
    status.isSearchHighlight = false

  else:
    if keyword.len > 0:
      status.isSearchHighlight = true

      # Save keyword in search history
      status.searchHistory.addSearchHistory(keyword)

      var highlight = currentMainWindowNode.highlight
      highlight.updateHighlight(
        currentBufStatus,
        currentMainWindowNode,
        status.isSearchHighlight,
        status.searchHistory,
        status.settings)

# TODO: Move
proc incrementalSearch(status: var Editorstatus, direction: Direction) =
  let prompt = if direction == Direction.forward: "/" else: "?"

  status.searchHistory.add ru""

  var
    exitSearch = false
    cancelSearch = false

  # For jumpToSearchBackwordResults
  let
    currentLine = currentMainWindowNode.currentLine
    currentColumn = currentMainWindowNode.currentColumn

  while exitSearch == false:
    const
      isSuggest = false
      isSearch = true
    let returnWord = status.getKeyOnceAndWriteCommandView(
      prompt,
      status.searchHistory[^1],
      isSuggest,
      isSearch)

    status.searchHistory[^1] = returnWord[0]
    exitSearch = returnWord[1]
    cancelSearch = returnWord[2]

    if exitSearch or cancelSearch: break

    if status.searchHistory[^1].len > 0:
      let keyword = status.searchHistory[^1]
      status.isSearchHighlight = true

      if direction == Direction.forward:
        currentBufStatus.jumpToSearchForwardResults(
          currentMainWindowNode,
          keyword,
          status.settings.ignorecase,
          status.settings.smartcase)
      else:
        currentMainWindowNode.currentLine = currentLine
        currentMainWindowNode.currentColumn = currentColumn
        currentBufStatus.jumpToSearchBackwordResults(
          currentMainWindowNode,
          keyword,
          status.settings.ignorecase,
          status.settings.smartcase)
    else:
      status.isSearchHighlight = false

    var highlight = currentMainWindowNode.highlight
    highlight.updateHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings)

    status.resize(terminalHeight(), terminalWidth())
    status.update

  if cancelSearch:
    status.searchHistory.delete(status.searchHistory.high)

    status.isSearchHighlight = false

    var highlight = currentMainWindowNode.highlight
    highlight.updateHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings)

    status.commandLine.erase
# TODO: Move
proc searchFordwards*(status: var EditorStatus) =
  if status.settings.incrementalSearch:
      status.incrementalSearch(Direction.forward)
  else:
      status.searchFirstOccurrence

# TODO: Move
proc searchBackwards*(status: var EditorStatus) =
  if status.settings.incrementalSearch:
      status.incrementalSearch(Direction.backward)
  else:
      status.searchFirstOccurrence

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
      var key = errorKey
      key = getKey(currentMainWindowNode)
      if key != errorKey: break

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
      var key = errorKey
      key = getKey(currentMainWindowNode)
      if key != errorKey: break

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

proc highlightFullWidthSpace(highlight: var Highlight,
                             windowNode: WindowNode,
                             bufferInView: GapBuffer[seq[Rune]],
                             range: (int, int)) =


  const fullWidthSpace = ru"　"
  let
    ignorecase = false
    smartcase = false
    allOccurrence = bufferInView.searchAllOccurrence(
      fullWidthSpace,
      ignorecase,
      smartcase)
    color = EditorColorPair.highlightFullWidthSpace
  for pos in allOccurrence:
    let colorSegment = ColorSegment(firstRow: range[0] + pos.line,
                                    firstColumn: pos.column,
                                    lastRow: range[0] + pos.line,
                                    lastColumn: pos.column,
                                    color: color)
    highlight = highlight.overwrite(colorSegment)

proc highlightSearchResults(highlight: var Highlight,
                            bufStatus: BufferStatus,
                            bufferInView: GapBuffer[seq[Rune]],
                            range: (int, int),
                            keyword: seq[Rune],
                            settings: EditorSettings,
                            isSearchHighlight: bool) =

  let
    ignorecase = settings.ignorecase
    smartcase = settings.smartcase
    allOccurrence = searchAllOccurrence(
      bufferInView,
      keyword,
      ignorecase,
      smartcase)
    color = if isSearchHighlight: EditorColorPair.searchResult
            else: EditorColorPair.replaceText
  for pos in allOccurrence:
    let colorSegment = ColorSegment(firstRow: range[0] + pos.line,
                                    firstColumn: pos.column,
                                    lastRow: range[0] + pos.line,
                                    lastColumn: pos.column + keyword.high,
                                    color: color)
    highlight = highlight.overwrite(colorSegment)

proc updateHighlight*(highlight: var Highlight,
                      bufStatus: BufferStatus,
                      windowNode: var WindowNode,
                      isSearchHighlight: bool,
                      searchHistory: seq[seq[Rune]],
                      settings: EditorSettings) =

  if settings.highlightSettings.currentWord:
    highlight.highlightOtherUsesCurrentWord(
      bufStatus,
      windowNode,
      settings.editorColorTheme)

  if isVisualMode(bufStatus.mode):
    highlight.highlightSelectedArea(bufStatus, windowNode)

  if settings.highlightSettings.pairOfParen:
    highlight.highlightPairOfParen(bufStatus, windowNode)

  let
    range = windowNode.view.rangeOfOriginalLineInView
    startLine = range[0]
    endLine = if bufStatus.buffer.len > range[1] + 1: range[1] + 2
              elif bufStatus.buffer.len > range[1]: range[1] + 1
              else: range[1]

  var bufferInView = initGapBuffer[seq[Rune]]()
  for i in startLine ..< endLine: bufferInView.add(bufStatus.buffer[i])

  # highlight trailing spaces
  if settings.highlightSettings.trailingSpaces and
     bufStatus.language != SourceLanguage.langMarkDown:
    highlight.highlightTrailingSpaces(bufStatus, windowNode)

  # highlight full width space
  if settings.highlightSettings.fullWidthSpace:
    highlight.highlightFullWidthSpace(windowNode, bufferInView, range)

  # highlight search results
  if isSearchHighlight and searchHistory.len > 0:
    highlight.highlightSearchResults(
      bufStatus,
      bufferInView,
      range,
      searchHistory[^1],
      settings,
      isSearchHighlight)

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
        status.settings.notificationSettings,
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
      status.resize(terminalHeight(), terminalWidth())

  # Automatic backup
  let
    lastBackupTime = status.autoBackupStatus.lastBackupTime
    interval = status.settings.autoBackupSettings.interval
    idleTime = status.settings.autoBackupSettings.idleTime

  if status.settings.autoBackupSettings.enable and
     lastBackupTime + interval.minutes < now() and
     status.lastOperatingTime + idleTime.seconds < now():
    for bufStatus in status.bufStatus:
      let
        mode = bufStatus.mode
        prevMode = bufStatus.prevMode

      if isNormalMode(mode, prevMode) or
         isInsertMode(mode) or
         isVisualMode(mode) or
         isReplaceMode(mode):
        bufStatus.backupBuffer(bufStatus.characterEncoding,
                               status.settings.autoBackupSettings,
                               status.settings.notificationSettings,
                               status.commandLine,
                               status.messageLog)

        status.autoBackupStatus.lastBackupTime = now()

import debugmode

proc initDebugModeHighlight[T](buffer: T): Highlight =
  debugmode.initDebugModeHighlight(buffer)

proc updateDebugModeBuffer(status: var EditorStatus) =
  let debugModeBufferIndex = status.bufStatus.getDebugModeBufferIndex
  if debugModeBufferIndex == -1: return

  status.bufStatus.updateDebugModeBuffer(
    mainWindowNode,
    currentMainWindowNode.windowIndex,
    status.settings.debugModeSettings)
