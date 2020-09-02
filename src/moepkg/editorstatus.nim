import strutils, terminal, os, strformat, tables, times, osproc, heapqueue,
       deques, times
import highlite
import gapbuffer, editorview, ui, unicodeext, highlight, fileutils,
       undoredostack, window, color, workspace, statusbar, settings,
       bufferstatus, cursor, tabline, backup, messages

type Platform* = enum
  linux, wsl, mac, other

type Registers* = object
  yankedLines*: seq[seq[Rune]]
  yankedStr*: seq[Rune]

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
  debugMode: int
  commandWindow*: Window
  tabWindow*: Window
  popUpWindow*: Window
  workSpaceTabWindow*: Window
  lastOperatingTime*: DateTime
  autoBackupStatus*: AutoBackupStatus

proc initPlatform(): Platform =
  if defined linux:
    if execProcess("uname -r").contains("Microsoft"):
      result = Platform.wsl
    else: result = Platform.linux
  elif defined macosx: result = Platform.mac
  else: result = Platform.other

proc initRegisters(): Registers =
  result.yankedLines = @[]
  result.yankedStr = @[]

proc initEditorStatus*(): EditorStatus =
  result.platform = initPlatform()
  result.currentDir = getCurrentDir().toRunes
  result.registers = initRegisters()
  result.settings = initEditorSettings()
  result.lastOperatingTime = now()
  result.autoBackupStatus = initAutoBackupStatus()

  if result.settings.workSpace.workSpaceLine:
    const
      h = 1
      t = 0
      l = 0
      color = EditorColorPair.defaultChar
    let
      w = terminalWidth()
    result.workSpaceTabWindow = initWindow(h, w, t, l, color)

  var newWorkSpace = initWorkSpace()
  result.workSpace = @[newWorkSpace]

  if result.settings.tabLine.useTab:
    const
      h = 1
      t = 0
      l = 0
      color = EditorColorPair.defaultChar
    let
      w = terminalWidth()
    result.tabWindow = initWindow(h, w, t, l, color)

  block:
    const
      t = 0
      l = 0
      color = EditorColorPair.defaultChar
    let
      w = terminalWidth()
      h = terminalHeight() - 1
    result.commandWindow = initWindow(h, w, t, l, color)

proc changeCurrentBuffer*(status: var EditorStatus, bufferIndex: int) =
  if 0 <= bufferIndex and bufferIndex < status.bufStatus.len:
    let workspaceIndex = status.currentWorkSpaceIndex
    
    status.workSpace[workspaceIndex].currentMainWindowNode.bufferIndex =
      bufferIndex

    status.workSpace[workspaceIndex].currentMainWindowNode.currentLine = 0
    status.workSpace[workspaceIndex].currentMainWindowNode.currentColumn = 0
    status.workSpace[workspaceIndex].currentMainWindowNode.expandedColumn = 0

    let node = status.workSpace[workspaceIndex].currentMainWindowNode
    for i in 0 ..< status.workSpace[workspaceIndex].statusbar.len:
      if status.workSpace[workspaceIndex].statusbar[i].windowIndex == node.windowIndex:
        status.workSpace[workspaceIndex].statusbar[i].bufferIndex = bufferIndex

proc bufferIndexInCurrentWindow*(status: Editorstatus): int =
  let workspaceIndex = status.currentWorkSpaceIndex
  status.workSpace[workspaceIndex].currentMainWindowNode.bufferIndex

proc changeMode*(status: var EditorStatus, mode: Mode) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].prevMode =
    status.bufStatus[currentBufferIndex].mode
  status.bufStatus[currentBufferIndex].mode = mode

proc changeCurrentWin*(status:var EditorStatus, index: int) =
  let workspaceIndex = status.currentWorkSpaceIndex
  
  if index < status.workSpace[workspaceIndex].numOfMainWindow and index > 0:
    var node =
      status.workSpace[workspaceIndex].mainWindowNode.searchByWindowIndex(index)
    status.workSpace[workspaceIndex].currentMainWindowNode = node

proc executeOnExit(settings: EditorSettings) =
  if not settings.disableChangeCursor:
    changeCursorType(settings.defaultCursor)

proc exitEditor*(settings: EditorSettings) =
  executeOnExit(settings)
  exitUi()
  quit()

proc resizeMainWindowNode(status: var EditorStatus, height, width: int) =
  let
    useTab = if status.settings.tabLine.useTab: 1 else: 0
    useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    useWorkSpaceBar = if status.settings.workSpace.workSpaceLine: 1 else: 0
    workspaceIndex = status.currentWorkSpaceIndex

  const x = 0
  let
    y = useTab + useWorkSpaceBar
    h = height - useTab - useStatusBar - useWorkSpaceBar
    w = width
  status.workSpace[workspaceIndex].mainWindowNode.resize(y, x, h, w)

proc resize*(status: var EditorStatus, height, width: int) =
  setCursor(false)

  status.resizeMainWindowNode(height, width)

  let workspaceIndex = status.currentWorkSpaceIndex
  const statusBarHeight = 1
  var
    statusBarIndex = 0
    queue = initHeapQueue[WindowNode]()
  for node in status.workSpace[workspaceIndex].mainWindowNode.child:
    queue.push(node)
  while queue.len > 0:
    let queueLength = queue.len
    for i in  0 ..< queueLength:
      let node = queue.pop
      if node.window != nil:
        let
          bufIndex = node.bufferIndex
          widthOfLineNum = node.view.widthOfLineNum
          adjustedHeight = max(node.h - statusBarHeight, 4)
          adjustedWidth = max(node.w - widthOfLineNum - 1, 4)

        node.view.resize(status.bufStatus[bufIndex].buffer,
                         adjustedHeight,
                         adjustedWidth,
                         widthOfLineNum)
        node.view.seekCursor(status.bufStatus[bufIndex].buffer,
                             node.currentLine,
                             node.currentColumn)

        ## Resize status bar window
        const height = 1
        let
          width = if node.x > 0 and
                     node.parent.splitType == SplitType.vertical:node.w - 1
                  else: node.w
          y = node.y + adjustedHeight
          x = if node.x > 0 and
                 node.parent.splitType == SplitType.vertical: node.x + 1
              else: node.x
        status.workSpace[workspaceIndex].statusBar[statusBarIndex].window.resize(
          height,
          width,
          y,
          x)
        status.workSpace[workspaceIndex].statusBar[statusBarIndex].window.refresh

        # Update status bar info
        status.workSpace[workspaceIndex].statusbar[statusBarIndex].bufferIndex =
          node.bufferIndex
        status.workSpace[workspaceIndex].statusbar[statusBarIndex].windowIndex =
          node.windowIndex
        inc(statusBarIndex)

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  ## Resize status bar window
  if status.settings.statusBar.useBar and
     not status.settings.statusBar.multipleStatusBar:
    const
      statusBarHeight = 1
      x = 0
    let 
      y = max(height, 4) - 2
    status.workSpace[workspaceIndex].statusBar[0].window.resize(
      statusBarHeight,
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
  status.commandWindow.resize(commandWindowHeight, width, y, x)
  status.commandWindow.refresh

  setCursor(true)

proc highlightPairOfParen(status: var Editorstatus)
proc highlightOtherUsesCurrentWord(status: var Editorstatus)
proc highlightSelectedArea(status: var Editorstatus)
proc updateHighlight*(status: var EditorStatus, windowNode: var WindowNode)

proc updateStatusBar(status: var Editorstatus) =
  let workspaceIndex = status.currentWorkSpaceIndex

  if not status.settings.statusBar.multipleStatusBar:
    const isActiveWindow = true
    let index = status.workSpace[workspaceIndex].statusBar[0].bufferIndex
    status.bufStatus[index].writeStatusBar(
      status.workSpace[workspaceIndex].statusBar[0],
      status.workspace[workspaceIndex].currentMainWindowNode,
      isActiveWindow,
      status.settings)
  else:
    for i in 0 ..< status.workSpace[workspaceIndex].statusBar.len:
      let
        bufferIndex = status.workSpace[workspaceIndex].statusBar[i].bufferIndex
        index = status.workSpace[workspaceIndex].statusBar[i].windowIndex
        windowNode =
          status.workspace[workspaceIndex].mainWindowNode.searchByWindowIndex(index)
        isActiveWindow = index == status.workSpace[workspaceIndex].currentMainWindowNode.index
      status.bufStatus[bufferIndex].writeStatusBar(
        status.workSpace[workspaceIndex].statusBar[i],
        windowNode,
        isActiveWindow,
        status.settings)

proc initSyntaxHighlight(windowNode: var WindowNode,
                         bufStatus: seq[BufferStatus],
                         reservedWords: seq[ReservedWord],
                         isSyntaxHighlight: bool) =
                         
  var queue = initHeapQueue[WindowNode]()
  for node in windowNode.child: queue.push(node)
  while queue.len > 0:
    for i in  0 ..< queue.len:
      var node = queue.pop
      if node.window != nil:
        let bufStatus = bufStatus[node.bufferIndex]
        if not isFilerMode(bufStatus.mode, bufStatus.prevMode) and
           not isHistoryManagerMode(bufStatus.mode, bufStatus.prevMode) and
           not isDiffViewerMode(bufStatus.mode, bufStatus.prevMode) and
           not isConfigMode(bufStatus.mode, bufStatus.prevMode):
          let lang = if isSyntaxHighlight: bufStatus.language
                     else: SourceLanguage.langNone
          node.highlight = ($bufStatus.buffer).initHighlight(reservedWords, lang)

      if node.child.len > 0:
        for node in node.child: queue.push(node)

proc isLogViewerMode(mode, prevMode: Mode): bool =
  (mode == logViewer) or (mode == ex and prevMode == logViewer)

proc updateLogViewer(status: var Editorstatus, bufferIndex: int) =
  status.bufStatus[bufferIndex].buffer = initGapBuffer(@[ru""])
  for i in 0 ..< status.messageLog.len:
    status.bufStatus[bufferIndex].buffer.insert(status.messageLog[i], i)

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
      status.workspace[status.currentWorkSpaceIndex],
      status.settings.tabline.allBuffer)

  let workspaceIndex = status.currentWorkSpaceIndex

  status.workspace[workspaceIndex].mainWindowNode.initSyntaxHighlight(
    status.bufStatus,
    status.settings.reservedWords,
    status.settings.syntax)

  var queue = initHeapQueue[WindowNode]()
  for node in status.workSpace[workspaceIndex].mainWindowNode.child:
    queue.push(node)
  while queue.len > 0:
    for i in  0 ..< queue.len:
      var node = queue.pop
      if node.window != nil:
        let bufStatus = status.bufStatus[node.bufferIndex]

        let
          currentMode = bufStatus.mode
          prevMode = bufStatus.prevMode

        if bufStatus.buffer.high < node.currentLine:
          node.currentLine = bufStatus.buffer.high
        if currentMode != Mode.insert and
           currentMode != Mode.replace and
           bufStatus.buffer[node.currentLine].len > 0 and
           bufStatus.buffer[node.currentLine].high < node.currentColumn:
          node.currentColumn = bufStatus.buffer[node.currentLine].high

        node.view.reload(bufStatus.buffer,
                         min(node.view.originalLine[0],
                         bufStatus.buffer.high))

        let
          currentWindowIndex =
            status.workSpace[workspaceIndex].currentMainWindowNode.windowIndex
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
            if status.settings.highlightOtherUsesCurrentWord:
              status.highlightOtherUsesCurrentWord
            if isVisualMode:
              status.highlightSelectedArea
            if status.settings.highlightPairOfParen:
              status.highlightPairOfParen

          status.updateHighlight(node)

        let
          startSelectedLine = bufStatus.selectArea.startLine
          endSelectedLine = bufStatus.selectArea.endLine

        node.view.seekCursor(bufStatus.buffer,
                             node.currentLine,
                             node.currentColumn)

        node.view.update(node.window,
                         status.settings.view,
                         isCurrentMainWin,
                         currentMode,
                         prevMode,
                         bufStatus.buffer,
                         node.highlight,
                         node.currentLine,
                         startSelectedLine,
                         endSelectedLine)

        if isCurrentMainWin:
          node.cursor.update(node.view, node.currentLine, node.currentColumn)

        node.window.refresh

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  var currentMainWindowNode =
    status.workSpace[workspaceIndex].currentMainWindowNode
  let
    currentMode = status.bufStatus[currentMainWindowNode.bufferIndex].mode
    prevMode = status.bufStatus[currentMainWindowNode.bufferIndex].prevMode
  if (currentMode != Mode.filer) and
     not (currentMode == Mode.ex and
     prevMode == Mode.filer):
    let
      y = currentMainWindowNode.cursor.y
      x = currentMainWindowNode.view.widthOfLineNum + currentMainWindowNode.cursor.x
    currentMainWindowNode.window.moveCursor(y, x)

  if status.settings.statusBar.useBar: status.updateStatusBar

  setCursor(true)

proc verticalSplitWindow*(status: var EditorStatus) =
  let 
    currentBufferIndex = status.bufferIndexInCurrentWindow
    buffer = status.bufStatus[currentBufferIndex].buffer
    workspaceIndex = status.currentWorkSpaceIndex

  status.workSpace[workspaceIndex].currentMainWindowNode =
    status.workSpace[workspaceIndex].currentMainWindowNode.verticalSplit(buffer)
  inc(status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow)

  status.workSpace[workspaceIndex].statusBar.add(initStatusBar())

proc horizontalSplitWindow*(status: var Editorstatus) =
  let 
    currentBufferIndex = status.bufferIndexInCurrentWindow
    buffer = status.bufStatus[currentBufferIndex].buffer
    workspaceIndex = status.currentWorkSpaceIndex

  status.workSpace[workspaceIndex].currentMainWindowNode =
    status.workSpace[workspaceIndex].currentMainWindowNode.horizontalSplit(buffer)
  inc(status.workSpace[workspaceIndex].numOfMainWindow)

  status.workSpace[workspaceIndex].statusBar.add(initStatusBar())

proc deleteWorkSpace*(status: var Editorstatus, index: int)
proc closeWindow*(status: var EditorStatus, node: WindowNode) =
  let workspaceIndex = status.currentWorkSpaceIndex

  if status.workSpace.len == 1 and
     status.workSpace[workspaceIndex].numOfMainWindow == 1:
    exitEditor(status.settings)

  let deleteWindowIndex = node.windowIndex
  var parent = node.parent

  if status.workspace[workspaceIndex].numOfMainWindow == 1:
    status.deleteWorkSpace(workspaceIndex)
  elif parent.child.len == 1:
    if status.settings.statusBar.multipleStatusBar:
      let statusBarHigh = status.workSpace[workspaceIndex].statusBar.high
      status.workSpace[workspaceIndex].statusBar.delete(statusBarHigh)

    parent.parent.child.delete(parent.index)
    dec(status.workSpace[workspaceIndex].numOfMainWindow)

    status.resize(terminalHeight(), terminalWidth())

    let newCurrentWinIndex =
      if deleteWindowIndex > status.workSpace[workspaceIndex].numOfMainWindow - 1:
        status.workSpace[workspaceIndex].numOfMainWindow - 1
      else: deleteWindowIndex
    var node =
      status.workSpace[workspaceIndex].mainWindowNode.searchByWindowIndex(newCurrentWinIndex)
    status.workSpace[workspaceIndex].currentMainWindowNode = node
  else:
    if status.settings.statusBar.multipleStatusBar:
      let statusBarHigh = status.workSpace[workspaceIndex].statusBar.high
      status.workSpace[workspaceIndex].statusBar.delete(statusBarHigh)

    parent.child.delete(node.index)
    dec(status.workSpace[workspaceIndex].numOfMainWindow)

    status.resize(terminalHeight(), terminalWidth())

    let newCurrentWinIndex =
      if deleteWindowIndex > status.workSpace[workspaceIndex].numOfMainWindow - 1:
        status.workSpace[workspaceIndex].numOfMainWindow - 1
      else: deleteWindowIndex

    var node =
      status.workSpace[workspaceIndex].mainWindowNode.searchByWindowIndex(newCurrentWinIndex)
    status.workSpace[workspaceIndex].currentMainWindowNode = node

proc moveCurrentMainWindow*(status: var EditorStatus, index: int) =
  let workspaceIndex = status.currentWorkSpaceIndex
  if index < 0 or
     status.workSpace[workspaceIndex].numOfMainWindow <= index: return
 
  var node =
    status.workSpace[workspaceIndex].mainWindowNode.searchByWindowIndex(index)
  status.workSpace[workspaceIndex].currentMainWindowNode = node

proc moveNextWindow*(status: var EditorStatus) =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    index =
      status.workSpace[workspaceIndex].currentMainWindowNode.windowIndex + 1
  status.moveCurrentMainWindow(index)

proc movePrevWindow*(status: var EditorStatus) =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    index =
      status.workSpace[workspaceIndex].currentMainWindowNode.windowIndex - 1
  status.moveCurrentMainWindow(index)

proc writePopUpWindow*(popUpWindow: var Window,
                       h, w, y, x: var int,
                       currentLine: int,
                       buffer: seq[seq[Rune]]) =

  popUpWindow.erase

  # Pop up window position
  if y == terminalHeight() - 1: y = y - h
  if w > terminalHeight() - x: x = terminalHeight() - w

  popUpWindow.resize(h, w, y, x)

  let startLine = if currentLine == -1: 0
                  elif currentLine - h + 1 > 0: currentLine - h + 1
                  else: 0
  for i in 0 ..< h:
    if currentLine != -1 and i + startLine == currentLine:
      let color = EditorColorPair.popUpWinCurrentLine
      popUpWindow.write(i, 1, buffer[i + startLine], color)
    else:
      let color = EditorColorPair.popUpWindow
      popUpWindow.write(i, 1, buffer[i + startLine], color)

  popUpWindow.refresh

proc deletePopUpWindow*(status: var Editorstatus) =
  if status.popUpWindow != nil:
    status.popUpWindow.deleteWindow
    status.update


proc addNewBuffer*(status: var EditorStatus, filename: string, mode: Mode) =
  status.bufStatus.add(BufferStatus(path: filename.toRunes,
                                    mode: mode,
                                    lastSaveTime: now()))
  let index = status.bufStatus.high

  if existsFile(filename) == false: status.bufStatus[index].buffer = newFile()
  else:
    try:
      let textAndEncoding = openFile(filename.toRunes)
      status.bufStatus[index].buffer = textAndEncoding.text.toGapBuffer
      status.bufStatus[index].characterEncoding = textAndEncoding.encoding
    except IOError:
      status.commandWindow.writeFileOpenError(filename, status.messageLog)
      return

  if filename != "": status.bufStatus[index].language = detectLanguage(filename)

  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view =
    status.bufStatus[index].buffer.initEditorView(terminalHeight(),
                                                  terminalWidth())

  status.changeCurrentBuffer(index)
  #status.changeMode(Mode.normal)

proc addNewBuffer*(status: var EditorStatus, mode: Mode) =
  status.addNewBuffer("", mode)

proc addNewBuffer*(status: var EditorStatus, filename: string) =
  status.addNewBuffer(filename, Mode.normal)

proc addNewBuffer*(status: var EditorStatus) =
  status.addNewBuffer("")

proc deleteBuffer*(status: var Editorstatus, deleteIndex: int) =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    beforeWindowIndex =
      status.workSpace[workspaceIndex].currentMainWindowNode.windowIndex

  var queue = initHeapQueue[WindowNode]()
  for node in status.workSpace[workspaceIndex].mainWindowNode.child:
    queue.push(node)
  while queue.len > 0:
    for i in 0 ..< queue.len:
      let node = queue.pop
      if node.bufferIndex == deleteIndex: status.closeWindow(node)

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  status.resize(terminalHeight(), terminalWidth())

  status.bufStatus.delete(deleteIndex)

  queue = initHeapQueue[WindowNode]()
  for node in status.workSpace[workspaceIndex].mainWindowNode.child:
    queue.push(node)
  while queue.len > 0:
    for i in 0 ..< queue.len:
      var node = queue.pop
      if node.bufferIndex > deleteIndex: dec(node.bufferIndex)

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  let afterWindowIndex = if beforeWindowIndex > status.workSpace[workspaceIndex].numOfMainWindow - 1:
                            status.workSpace[workspaceIndex].numOfMainWindow - 1
                         else: beforeWindowIndex
  var node = status.workSpace[workspaceIndex].mainWindowNode.searchByWindowIndex(afterWindowIndex)
  status.workSpace[workspaceIndex].currentMainWindowNode = node

proc createWrokSpace*(status: var Editorstatus) =
  let
    newWorkSpaceIndex = status.currentWorkSpaceIndex + 1
  var newWorkSpace = initWorkSpace()

  status.workSpace.insert(newWorkSpace, newWorkSpaceIndex)
  status.currentWorkSpaceIndex += 1
  status.addNewBuffer("")
  status.workSpace[newWorkSpaceIndex].currentMainWindowNode.bufferIndex =
    status.bufStatus.high

proc deleteWorkSpace*(status: var Editorstatus, index: int) =
  if 0 > index and index > status.workSpace.high:
    status.commandwindow.writeNotExistWorkspaceError(index, status.messageLog)
  else:
    status.workspace.delete(index)

    if status.workspace.len == 0: status.settings.exitEditor

    if status.currentWorkSpaceIndex > status.workSpace.high:
      status.currentWorkSpaceIndex = status.workSpace.high

proc changeCurrentWorkSpace*(status: var Editorstatus, index: int) =
  if 0 < index and index <= status.workSpace.len:
    status.currentWorkSpaceIndex = index - 1
  else:
    status.commandwindow.writeNotExistWorkspaceError(index, status.messageLog)

proc tryRecordCurrentPosition*(bufStatus: var BufferStatus, windowNode: WindowNode) =
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
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    area = status.bufStatus[currentBufferIndex].selectArea
    workspaceIndex = status.currentWorkSpaceIndex
    windowNode = status.workspace[workspaceIndex].currentMainWindowNode

  var colorSegment = initSelectedAreaColorSegment(windowNode.currentLine,
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
    currentMode = status.bufStatus[currentBufferIndex].mode
    prevMode = status.bufStatus[currentBufferIndex].prevMode

  if (currentMode == Mode.visual) or
     (currentMode == Mode.ex and
     prevMode == Mode.visual):
    status.workSpace[workspaceIndex].currentMainWindowNode.highlight =
      status.workSpace[workspaceIndex].currentMainWindowNode.highlight.overwrite(colorSegment)
  elif (currentMode == Mode.visualBlock) or
       (currentMode == Mode.ex and
       prevMode == Mode.visualBlock):
    status.workSpace[workspaceIndex].currentMainWindowNode.highlight.overwriteColorSegmentBlock(status.bufStatus[currentBufferIndex].selectArea,
                                                                                                status.bufStatus[currentBufferIndex].buffer)

proc highlightPairOfParen(status: var Editorstatus) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    buffer = status.bufStatus[currentBufferIndex].buffer
    workspaceIndex = status.currentWorkSpaceIndex
    windowNode = status.workspace[workspaceIndex].currentMainWindowNode
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
          status.workSpace[workspaceIndex].currentMainWindowNode.highlight =
            status.workSpace[workspaceIndex].currentMainWindowNode.highlight.overwrite(colorSegment)
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
          status.workSpace[workspaceIndex].currentMainWindowNode.highlight =
            status.workSpace[workspaceIndex].currentMainWindowNode.highlight.overwrite(colorSegment)
          return

# Highlighting other uses of the current word under the cursor
proc highlightOtherUsesCurrentWord(status: var Editorstatus) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    bufStatus = status.bufStatus[currentBufferIndex]
    workspaceIndex = status.currentWorkSpaceIndex
    windowNode = status.workspace[workspaceIndex].currentMainWindowNode
    line = bufStatus.buffer[windowNode.currentLine]

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
    range =
      status.workSpace[workspaceIndex].currentMainWindowNode.view.rangeOfOriginalLineInView
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
                  status.workSpace[workspaceIndex].currentMainWindowNode.highlight.getColorPair(i, j)
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
              status.workSpace[workspaceIndex].currentMainWindowNode.highlight =
                status.workSpace[workspaceIndex].currentMainWindowNode.highlight.overwrite(colorSegment)

proc highlightTrailingSpaces(status: var Editorstatus) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    bufStatus = status.bufStatus[currentBufferIndex]

  if isConfigMode(bufStatus.mode, bufStatus.prevMode): return

  let
    buffer = bufStatus.buffer
    workspaceIndex = status.currentWorkSpaceIndex
    windowNode = status.workspace[workspaceIndex].currentMainWindowNode
    currentLine = windowNode.currentLine

    color = EditorColorPair.highlightTrailingSpaces

    range =
      status.workSpace[workspaceIndex].currentMainWindowNode.view.rangeOfOriginalLineInView
    startLine = range[0]
    endLine = if bufStatus.buffer.len > range[1] + 1: range[1] + 2
              elif bufStatus.buffer.len > range[1]: range[1] + 1
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
    status.workSpace[workspaceIndex].currentMainWindowNode.highlight =
      status.workSpace[workspaceIndex].currentMainWindowNode.highlight.overwrite(colorSegment)

from search import searchAllOccurrence
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
  if status.settings.highlightTrailingSpaces: status.highlightTrailingSpaces

  # highlight full width space
  if status.settings.highlightFullWidthSpace:
    const fullWidthSpace = ru"　"
    let
      allOccurrence = bufferInView.searchAllOccurrence(fullWidthSpace)
      color = EditorColorPair.highlightFullWidthSpace
    for pos in allOccurrence:
      let colorSegment = ColorSegment(firstRow: range[0] + pos.line,
                                      firstColumn: pos.column,
                                      lastRow: range[0] + pos.line,
                                      lastColumn: pos.column,
                                      color: color)
      windowNode.highlight = windowNode.highlight.overwrite(colorSegment)

  # highlight search results
  if bufStatus.isSearchHighlight and status.searchHistory.len > 0:
    let
      keyword = status.searchHistory[^1]
      allOccurrence = searchAllOccurrence(bufferInView, keyword)
      color = if bufStatus.isSearchHighlight: EditorColorPair.searchResult
              else:
                EditorColorPair.replaceText
    for pos in allOccurrence:
      let colorSegment = ColorSegment(firstRow: range[0] + pos.line,
                                      firstColumn: pos.column,
                                      lastRow: range[0] + pos.line,
                                      lastColumn: pos.column + keyword.high,
                                      color: color)
      windowNode.highlight = windowNode.highlight.overwrite(colorSegment)

proc changeTheme*(status: var EditorStatus) =
  setCursesColor(ColorThemeTable[status.settings.editorColorTheme])

proc autoSave(status: var Editorstatus) =
  let interval = status.settings.autoSaveInterval.minutes
  for index, bufStatus in status.bufStatus:
    if bufStatus.path != ru"" and now() > bufStatus.lastSaveTime + interval:
      saveFile(bufStatus.path,
               bufStatus.buffer.toRunes,
               bufStatus.characterEncoding)
      status.commandWindow.writeMessageAutoSave(bufStatus.path,
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
      status.commandwindow.writeInvalidItemInConfigurationFileError(invalidItem, status.messageLog)
      initEditorSettings()
    except IOError, TomlError:
      let failureCause = getCurrentExceptionMsg()
      status.commandwindow.writeFailedToLoadConfigurationFileError(failureCause, status.messageLog)
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
    idolTime = status.settings.autoBackupSettings.idolTime

  if status.settings.autoBackupSettings.enable and
     lastBackupTime + interval.minutes < now() and
     status.lastOperatingTime + idolTime.seconds < now():
    for bufStatus in status.bufStatus:
      let
        mode = bufStatus.mode
        prevMode = bufStatus.prevMode

      if (mode == Mode.normal or
          mode == Mode.insert or
          mode == Mode.visual or
          mode == Mode.visualBlock or
          mode == Mode.replace) or
          (mode == Mode.ex and
          (prevMode == Mode.normal or
           prevMode == Mode.insert or
           prevMode == Mode.visual or
           prevMode == Mode.visualBlock or
           prevMode == Mode.replace)):

        bufStatus.backupBuffer(bufStatus.characterEncoding,
                               status.settings.autoBackupSettings,
                               status.settings.notificationSettings,
                               status.commandwindow,
                               status.messageLog)

        status.autoBackupStatus.lastBackupTime = now()
