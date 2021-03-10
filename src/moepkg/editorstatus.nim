import strutils, terminal, os, strformat, tables, times, osproc, heapqueue,
       deques, times, options
import syntax/highlite
import gapbuffer, editorview, ui, unicodeext, highlight, fileutils,
       undoredostack, window, color, workspace, statusline, settings,
       bufferstatus, cursor, tabline, backup, messages, commandline

type Platform* = enum
  linux, wsl, mac, other

type Registers* = object
  yankedLines*: seq[seq[Rune]]
  yankedStr*: seq[Rune]

# Save cursor position when a buffer for a window(file) gets closed.
type LastPosition* = object
  path: seq[Rune]
  line: int
  column: int

type EditorStatus* = object
  platform*: Platform
  bufStatus*: seq[BufferStatus]
  prevBufferIndex*: int
  searchHistory*: seq[seq[Rune]]
  exCommandHistory*: seq[seq[Rune]]
  normalCommandHistory*: seq[seq[Rune]]
  registers*: Registers
  settings*: EditorSettings
  workSpace*: seq[WorkSpace]
  currentWorkSpaceIndex*: int
  timeConfFileLastReloaded*: DateTime
  currentDir: seq[Rune]
  messageLog*: seq[seq[Rune]]
  commandLine*: CommandLine
  tabWindow*: Window
  popUpWindow*: Window
  workSpaceTabWindow*: Window
  lastOperatingTime*: DateTime
  autoBackupStatus*: AutoBackupStatus
  isSearchHighlight*: bool
  lastPosition*: seq[LastPosition]

proc initPlatform(): Platform =
  if defined linux:
    if execProcess("uname -r").contains("Microsoft"):
      result = Platform.wsl
    else: result = Platform.linux
  elif defined macosx: result = Platform.mac
  else: result = Platform.other

proc initRegisters*(): Registers {.inline.} =
  result.yankedLines = @[]
  result.yankedStr = @[]

proc initEditorStatus*(): EditorStatus =
  result.platform = initPlatform()
  result.currentDir = getCurrentDir().toRunes
  result.registers = initRegisters()
  result.settings = initEditorSettings()
  result.lastOperatingTime = now()
  result.autoBackupStatus = initAutoBackupStatus()
  result.commandLine = initCommandLine()

  # Init workspace line
  if result.settings.workSpace.workSpaceLine:
    const
      h = 1
      w = 1
      t = 0
      l = 0
      color = EditorColorPair.defaultChar
    result.workSpaceTabWindow = initWindow(h, w, t, l, color)

  var newWorkSpace = initWorkSpace()
  result.workSpace = @[newWorkSpace]

  # Init tab line
  if result.settings.tabLine.useTab:
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

template currentWorkSpace*: var WorkSpace =
  mixin status
  status.workSpace[status.currentWorkSpaceIndex]

template currentMainWindowNode*: var WindowNode =
  mixin status
  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

template mainWindowNode*: var WindowNode =
  mixin status
  status.workSpace[status.currentWorkSpaceIndex].mainWindowNode

proc changeCurrentBuffer*(status: var EditorStatus, bufferIndex: int) =
  if 0 <= bufferIndex and bufferIndex < status.bufStatus.len:
    currentMainWindowNode.bufferIndex = bufferIndex

    currentMainWindowNode.currentLine = 0
    currentMainWindowNode.currentColumn = 0
    currentMainWindowNode.expandedColumn = 0

    let node = currentMainWindowNode
    for i in 0 ..< currentWorkSpace.statusLine.len:
      if currentWorkSpace.statusLine[i].windowIndex == node.windowIndex:
        currentWorkSpace.statusLine[i].bufferIndex = bufferIndex

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
  if index < currentWorkSpace.numOfMainWindow and index > 0:
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

proc executeOnExit(settings: EditorSettings) {.inline.} =
  if not settings.disableChangeCursor:
    changeCursorType(settings.defaultCursor)

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
proc saveLastPosition(lastPosition: seq[LastPosition]) =
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
    saveLastPosition(status.lastPosition)

  executeOnExit(status.settings)
  exitUi()
  quit()

proc getMainWindowHeight*(settings: EditorSettings, h: int): int =
  let
    tabHeight = if settings.tabLine.useTab: 1 else: 0
    statusHeight = if settings.statusLine.enable: 1 else: 0
    workSpaceHeight = if settings.workSpace.workSpaceLine: 1 else: 0
    commandHeight = if settings.statusLine.merge: 1 else: 0

  result = h - tabHeight - statusHeight - workSpaceHeight + commandHeight

proc resizeMainWindowNode(status: var EditorStatus, height, width: int) =
  let
    tabLineHeight = if status.settings.tabLine.useTab: 1 else: 0
    statusLineHeight = if status.settings.statusLine.enable: 1 else: 0
    workSpaceLineHeight = if status.settings.workSpace.workSpaceLine: 1 else: 0
    commandLineHeight = if status.settings.statusLine.merge: 1 else: 0

  const x = 0
  let
    y = tabLineHeight + workSpaceLineHeight
    h = height - tabLineHeight - statusLineHeight - workSpaceLineHeight + commandLineHeight
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
          currentWorkSpace.statusLine[statusLineIndex].window.resize(
            statusLineHeight,
            width,
            y,
            x)
          currentWorkSpace.statusLine[statusLineIndex].window.refresh

          # Update status line info
          currentWorkSpace.statusLine[statusLineIndex].bufferIndex =
            node.bufferIndex
          currentWorkSpace.statusLine[statusLineIndex].windowIndex =
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
    currentWorkSpace.statusLine[0].window.resize(
      statusLineHeight,
      width,
      y,
      x)

  ## Resize work space info window
  if status.settings.workSpace.workSpaceLine:
    const
      workSpaceBarHeight = 1
      x = 0
      y = 0
    status.workSpaceTabWindow.resize(workSpaceBarHeight, width, y, x)

  ## Resize tab line window
  if status.settings.tabLine.useTab:
    const
      tabLineHeight = 1
      x = 0
    let y = if status.settings.workSpace.workSpaceLine: 1 else: 0
    status.tabWindow.resize(tabLineHeight, width, y, x)

  ## Resize command window
  const
    commandWindowHeight = 1
    x = 0
  let y = max(height, 4) - 1
  status.commandLine.resize(y, x, commandWindowHeight, width)

  setCursor(true)

proc highlightPairOfParen(status: var Editorstatus)
proc highlightOtherUsesCurrentWord(status: var Editorstatus)
proc highlightSelectedArea(status: var Editorstatus)
proc updateHighlight*(status: var EditorStatus, windowNode: var WindowNode)

proc updateStatusLine(status: var Editorstatus) =
  if not status.settings.statusLine.multipleStatusLine:
    const isActiveWindow = true
    let index = currentWorkSpace.statusLine[0].bufferIndex
    status.bufStatus[index].writeStatusLine(
      currentWorkSpace.statusLine[0],
      currentMainWindowNode,
      isActiveWindow,
      status.settings)
  else:
    for i in 0 ..< currentWorkSpace.statusLine.len:
      let
        bufferIndex = currentWorkSpace.statusLine[i].bufferIndex
        index = currentWorkSpace.statusLine[i].windowIndex
        node = mainWindowNode.searchByWindowIndex(index)
        currentNode = currentWorkSpace.currentMainWindowNode
        isActiveWindow = index == currentNode.windowIndex
      status.bufStatus[bufferIndex].writeStatusLine(
        currentWorkSpace.statusLine[i],
        node,
        isActiveWindow,
        status.settings)

proc initDebugModeHighlight[T](buffer: T): Highlight

proc initSyntaxHighlight(windowNode: var WindowNode,
                         bufStatus: seq[BufferStatus],
                         reservedWords: seq[ReservedWord],
                         isSyntaxHighlight: bool) =

  var queue = initHeapQueue[WindowNode]()
  for node in windowNode.child: queue.push(node)
  while queue.len > 0:
    for i in  0 ..< queue.len:
      var node = queue.pop
      if node.window.isSome:
        let bufStatus = bufStatus[node.bufferIndex]
        if isDebugMode(bufStatus.mode, bufStatus.prevMode):
          node.highlight = bufStatus.buffer.initDebugmodeHighlight
        elif not isFilerMode(bufStatus.mode, bufStatus.prevMode) and
           not isHistoryManagerMode(bufStatus.mode, bufStatus.prevMode) and
           not isDiffViewerMode(bufStatus.mode, bufStatus.prevMode) and
           not isConfigMode(bufStatus.mode, bufStatus.prevMode):
          let lang = if isSyntaxHighlight: bufStatus.language
                     else: SourceLanguage.langNone
          node.highlight = ($bufStatus.buffer).initHighlight(reservedWords, lang)

      if node.child.len > 0:
        for node in node.child: queue.push(node)

proc isLogViewerMode(mode, prevMode: Mode): bool {.inline.} =
  (mode == logViewer) or (mode == ex and prevMode == logViewer)

proc updateLogViewer(status: var Editorstatus, bufferIndex: int) =
  status.bufStatus[bufferIndex].buffer = initGapBuffer(@[ru""])
  for i in 0 ..< status.messageLog.len:
    status.bufStatus[bufferIndex].buffer.insert(status.messageLog[i], i)

proc updateDebugModeBuffer(status: var EditorStatus)

proc update*(status: var EditorStatus) =
  setCursor(false)

  if status.settings.workSpace.workSpaceLine:
    status.workSpaceTabWindow.writeTabLineWorkSpace(
      status.workspace.len,
      status.currentWorkSpaceIndex)

  if status.settings.tabLine.useTab:
    status.tabWindow.writeTabLineBuffer(
      status.bufStatus,
      status.bufferIndexInCurrentWindow,
      currentWorkSpace,
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
          isVisualMode = isVisualMode(bufStatus.mode)

        ## Update highlight
        ## TODO: Refactor and fix
        if not isFilerMode(currentMode, prevMode) and
           not isHistoryManagerMode(currentMode, prevMode) and
           not isDiffViewerMode(currentMode, prevMode) and
           not isConfigMode(currentMode, prevMode):

          if isLogViewerMode(currentMode, prevMode):
            status.updateLogViewer(node.bufferIndex)
          elif isCurrentMainWin:
            if status.settings.highlightSettings.currentWord:
              status.highlightOtherUsesCurrentWord
            if isVisualMode:
              status.highlightSelectedArea
            if status.settings.highlightSettings.pairOfParen:
              status.highlightPairOfParen

          status.updateHighlight(node)

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
                         node.highlight,
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

    if posi.column > bufStatus.buffer[node.currentLine].high:
      node.currentColumn = bufStatus.buffer[node.currentLine].high
    else:
      node.currentColumn = posi.column

proc verticalSplitWindow*(status: var EditorStatus) =
  status.updateLastCursorPostion

  # Create the new window
  let buffer = currentBufStatus.buffer
  currentMainWindowNode = currentMainWindowNode.verticalSplit(buffer)
  inc(currentWorkSpace.numOfMainWindow)

  let
    mode = currentBufStatus.mode
    prevMode = currentBufStatus.prevMode
  if isFilerMode(mode, prevMode):
    status.bufStatus.add(currentBufStatus)
    currentBufStatus.changeMode(Mode.filer)
    currentMainWindowNode.bufferIndex = status.bufStatus.high

  currentWorkSpace.statusLine.add(initStatusLine())

  status.resize(terminalHeight(), terminalWidth())

  var newNode = mainWindowNode.searchByWindowIndex(currentMainWindowNode.windowIndex + 1)
  newNode.restoreCursorPostion(currentBufStatus, status.lastPosition)

proc horizontalSplitWindow*(status: var Editorstatus) =
  status.updateLastCursorPostion

  let buffer = currentBufStatus.buffer
  currentMainWindowNode = currentMainWindowNode.horizontalSplit(buffer)
  inc(currentWorkSpace.numOfMainWindow)

  let
    mode = currentBufStatus.mode
    prevMode = currentBufStatus.prevMode
  if isFilerMode(mode, prevMode):
    status.bufStatus.add(currentBufStatus)
    currentBufStatus.changeMode(Mode.filer)
    currentMainWindowNode.bufferIndex = status.bufStatus.high

  currentWorkSpace.statusLine.add(initStatusLine())

  status.resize(terminalHeight(), terminalWidth())

  var newNode = mainWindowNode.searchByWindowIndex(currentMainWindowNode.windowIndex + 1)
  newNode.restoreCursorPostion(currentBufStatus, status.lastPosition)

proc deleteWorkSpace*(status: var Editorstatus, index: int)

proc closeWindow*(status: var EditorStatus,
                  node: WindowNode,
                  height, width: int) =

  if currentBufStatus.mode == Mode.normal:
    status.updateLastCursorPostion

  if status.workSpace.len == 1 and
     currentWorkSpace.numOfMainWindow == 1:
    status.exitEditor

  if currentWorkSpace.numOfMainWindow == 1:
    status.deleteWorkSpace(status.currentWorkSpaceIndex)
  else:
    let deleteWindowIndex = node.windowIndex

    mainWindowNode.deleteWindowNode(deleteWindowIndex)
    dec(currentWorkSpace.numOfMainWindow)

    if status.settings.statusLine.multipleStatusLine:
      let statusLineHigh = currentWorkSpace.statusLine.high
      currentWorkSpace.statusLine.delete(statusLineHigh)

    status.resize(height, width)

    let
      numOfMainWindow = currentWorkSpace.numOfMainWindow
      newCurrentWinIndex = if deleteWindowIndex > numOfMainWindow - 1:
                             currentWorkSpace.numOfMainWindow - 1
                           else: deleteWindowIndex

    let node = mainWindowNode.searchByWindowIndex(newCurrentWinIndex)
    currentWorkSpace.currentMainWindowNode = node

proc moveCurrentMainWindow*(status: var EditorStatus, index: int) =
  if index < 0 or
     currentWorkSpace.numOfMainWindow <= index: return

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

  let path = if mode == Mode.filer: ru absolutePath(filename) else: ru filename

  status.bufStatus.add(initBufferStatus(path, mode))

  let index = status.bufStatus.high

  if mode != Mode.filer:
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

  let afterWindowIndex = if beforeWindowIndex > currentWorkSpace.numOfMainWindow - 1:
                            currentWorkSpace.numOfMainWindow - 1
                         else: beforeWindowIndex
  currentMainWindowNode = mainWindowNode.searchByWindowIndex(afterWindowIndex)

proc createWrokSpace*(status: var Editorstatus) =
  let newWorkSpaceIndex = status.currentWorkSpaceIndex + 1
  var newWorkSpace = initWorkSpace()

  status.workSpace.insert(newWorkSpace, newWorkSpaceIndex)
  status.currentWorkSpaceIndex += 1
  status.addNewBuffer
  currentMainWindowNode.bufferIndex = status.bufStatus.high

proc deleteWorkSpace*(status: var Editorstatus, index: int) =
  if 0 > index and index > status.workSpace.high:
    status.commandLine.writeNotExistWorkspaceError(index, status.messageLog)
  else:
    status.workspace.delete(index)

    if status.workspace.len == 0: status.exitEditor

    if status.currentWorkSpaceIndex > status.workSpace.high:
      status.currentWorkSpaceIndex = status.workSpace.high

proc changeCurrentWorkSpace*(status: var Editorstatus, index: int) =
  if 0 < index and index <= status.workSpace.len:
    status.updateLastCursorPostion

    status.currentWorkSpaceIndex = index - 1
  else:
    status.commandLine.writeNotExistWorkspaceError(index, status.messageLog)

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

proc highlightSelectedArea(status: var Editorstatus) =
  let area = currentBufStatus.selectArea

  var colorSegment = initSelectedAreaColorSegment(
    currentMainWindowNode.currentLine,
    currentMainWindowNode.currentColumn)

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
    currentMode = currentBufStatus.mode
    prevMode = currentBufStatus.prevMode

  if (currentMode == Mode.visual) or
     (currentMode == Mode.ex and
     prevMode == Mode.visual):
    currentMainWindowNode.highlight =
      currentMainWindowNode.highlight.overwrite(colorSegment)
  elif (currentMode == Mode.visualBlock) or
       (currentMode == Mode.ex and
       prevMode == Mode.visualBlock):
    currentMainWindowNode.highlight.overwriteColorSegmentBlock(
      currentBufStatus.selectArea,
      currentBufStatus.buffer)

proc highlightPairOfParen(status: var Editorstatus) =
  let
    buffer = currentBufStatus.buffer
    currentLine = currentMainWindowNode.currentLine
    currentColumn = if currentMainWindowNode.currentColumn > buffer[currentLine].high:
                      buffer[currentLine].high
                    else: currentMainWindowNode.currentColumn

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
          currentMainWindowNode.highlight =
            currentMainWindowNode.highlight.overwrite(colorSegment)
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
          currentMainWindowNode.highlight =
            currentMainWindowNode.highlight.overwrite(colorSegment)
          return

# Highlighting other uses of the current word under the cursor
proc highlightOtherUsesCurrentWord(status: var Editorstatus) =
  let line = currentBufStatus.buffer[currentMainWindowNode.currentLine]

  if line.len < 1 or
     currentMainWindowNode.currentColumn > line.high or
     (line[currentMainWindowNode.currentColumn] != '_' and
     unicodeext.isPunct(line[currentMainWindowNode.currentColumn])) or
     line[currentMainWindowNode.currentColumn].isSpace: return
  var
    startCol = currentMainWindowNode.currentColumn
    endCol = currentMainWindowNode.currentColumn

  # Set start col
  for i in countdown(currentMainWindowNode.currentColumn - 1, 0):
    if (line[i] != '_' and unicodeext.isPunct(line[i])) or line[i].isSpace:
      break
    else: startCol.dec

  # Set end col
  for i in currentMainWindowNode.currentColumn ..< line.len:
    if (line[i] != '_' and unicodeext.isPunct(line[i])) or line[i].isSpace:
      break
    else: endCol.inc

  let highlightWord = line[startCol ..< endCol]

  let
    range = currentMainWindowNode.view.rangeOfOriginalLineInView
    startLine = range[0]
    endLine = if currentBufStatus.buffer.len > range[1] + 1: range[1] + 2
              elif currentBufStatus.buffer.len > range[1]: range[1] + 1
              else: range[1]
    windowNode = currentMainWindowNode

  proc isWordAtCursor(highlightWordLen, i, j: int): bool =
    result = i == windowNode.currentLine and
             (j >= startCol and j <= endCol)

  for i in startLine ..< endLine:
    let line = currentBufStatus.buffer[i]
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
                  currentMainWindowNode.highlight.getColorPair(i, j)
                theme = status.settings.editorColorTheme
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
              currentMainWindowNode.highlight =
                currentMainWindowNode.highlight.overwrite(colorSegment)

proc highlightTrailingSpaces(bufStatus: BufferStatus,
                             windowNode: var WindowNode) =

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
    windowNode.highlight =
      windowNode.highlight.overwrite(colorSegment)

from search import searchAllOccurrence

proc highlightFullWidthSpace(windowNode: var WindowNode,
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
    windowNode.highlight = windowNode.highlight.overwrite(colorSegment)

proc highlightSearchResults(windowNode: var WindowNode,
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
    windowNode.highlight = windowNode.highlight.overwrite(colorSegment)

proc updateHighlight*(status: var EditorStatus, windowNode: var WindowNode) =
  let
    range = windowNode.view.rangeOfOriginalLineInView
    startLine = range[0]
    bufStatus = status.bufStatus[windowNode.bufferIndex]
    endLine = if bufStatus.buffer.len > range[1] + 1: range[1] + 2
              elif bufStatus.buffer.len > range[1]: range[1] + 1
              else: range[1]

  var bufferInView = initGapBuffer[seq[Rune]]()
  for i in startLine ..< endLine: bufferInView.add(bufStatus.buffer[i])

  # highlight trailing spaces
  if status.settings.highlightSettings.trailingSpaces and
     bufStatus.language != SourceLanguage.langMarkDown:
    bufStatus.highlightTrailingSpaces(windowNode)

  # highlight full width space
  if status.settings.highlightSettings.fullWidthSpace:
    windowNode.highlightFullWidthSpace(bufferInView, range)

  # highlight search results
  if status.isSearchHighlight and status.searchHistory.len > 0:
    windowNode.highlightSearchResults(
      bufStatus,
      bufferInView,
      range,
      status.searchHistory[^1],
      status.settings,
      status.isSearchHighlight)

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

from settings import TomlError, loadSettingFile

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
    status.workSpace.len,
    status.currentWorkSpaceIndex,
    status.settings.debugModeSettings)
