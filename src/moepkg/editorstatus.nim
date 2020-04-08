import packages/docutils/highlite, strutils, terminal, os, strformat, tables, times, osproc, heapqueue
import gapbuffer, editorview, ui, cursor, unicodeext, highlight, independentutils, fileutils, undoredostack, window, color, build, workspace

type Platform* = enum
  linux, wsl, mac, other

type Mode* = enum
  normal, insert, visual, visualBlock, replace, ex, filer, search, bufManager, logViewer

type SelectArea* = object
  startLine*: int
  startColumn*: int
  endLine*: int
  endColumn*: int

type Registers* = object
  yankedLines*: seq[seq[Rune]]
  yankedStr*: seq[Rune]

type WorkSpaceSettings = object
  useBar*: bool

type StatusBarSettings* = object
  useBar*: bool
  mode*: bool
  filename*: bool
  chanedMark*: bool
  line*: bool
  column*: bool
  characterEncoding*: bool
  language*: bool
  directory*: bool
  multipleStatusBar*: bool

type TabLineSettings* = object
  useTab*: bool
  allbuffer*: bool

type EditorSettings* = object
  editorColorTheme*: ColorTheme
  statusBar*: StatusBarSettings
  tabLine*: TabLineSettings
  view*: EditorViewSettings
  syntax*: bool
  autoCloseParen*: bool
  autoIndent*: bool
  tabStop*: int
  characterEncoding*: CharacterEncoding # TODO: move to EditorStatus ...?
  defaultCursor*: CursorType
  normalModeCursor*: CursorType
  insertModeCursor*: CursorType
  autoSave*: bool
  autoSaveInterval*: int # minutes
  liveReloadOfConf*: bool
  realtimeSearch*: bool
  popUpWindowInExmode*: bool
  replaceTextHighlight*: bool
  highlightPairOfParen*: bool
  autoDeleteParen*: bool
  smoothScroll*: bool
  smoothScrollSpeed*: int
  highlightOtherUsesCurrentWord*: bool
  systemClipboard*: bool
  highlightFullWidthSpace*: bool
  buildOnSaveSettings*: BuildOnSaveSettings
  workSpace*: WorkSpaceSettings

type BufferStatus* = object
  buffer*: GapBuffer[seq[Rune]]
  highlight*: Highlight
  language*: SourceLanguage
  cursor*: CursorPosition
  selectArea*: SelectArea
  isHighlight*: bool
  filename*: seq[Rune]
  openDir: seq[Rune]
  positionRecord*: Table[int, tuple[line, column, expandedColumn: int]]
  currentLine*: int
  currentColumn*: int
  expandedColumn*: int
  countChange*: int
  cmdLoop*: int
  mode* : Mode
  prevMode* : Mode
  lastSaveTime*: DateTime

type StatusBar = object
  window: Window
  windowIndex: int
  bufferIndex: int

type EditorStatus* = object
  platform*: Platform
  bufStatus*: seq[BufferStatus]
  searchHistory*: seq[seq[Rune]]
  registers*: Registers
  settings*: EditorSettings
  workSpace*: seq[WorkSpace]
  currentWorkSpaceIndex*: int
  timeConfFileLastReloaded*: DateTime
  isSearchHighlight*: bool
  isReplaceTextHighlight*: bool
  currentDir: seq[Rune]
  messageLog*: seq[seq[Rune]]
  debugMode: int
  statusBar*: seq[StatusBar]
  commandWindow*: Window
  tabWindow*: Window
  popUpWindow*: Window
  workSpaceInfoWindow*: Window

proc initPlatform(): Platform =
  if defined linux:
    if execProcess("uname -r").contains("Microsoft"): result = Platform.wsl
    else: result = Platform.linux
  elif defined macosx: result = Platform.mac
  else: result = Platform.other

proc initRegisters(): Registers =
  result.yankedLines = @[]
  result.yankedStr = @[]

proc initTabBarSettings*(): TabLineSettings =
  result.useTab = true

proc initStatusBarSettings*(): StatusBarSettings =
  result.useBar = true
  result.mode = true
  result.filename = true
  result.chanedMark = true
  result.line = true
  result.column = true
  result.characterEncoding = true
  result.language = true
  result.directory = true
  result.multipleStatusBar = true

proc initWorkSpaceSettings(): WorkSpaceSettings =
  result.useBar = false

proc initEditorSettings*(): EditorSettings =
  result.editorColorTheme = ColorTheme.vivid
  result.statusBar = initStatusBarSettings()
  result.tabLine = initTabBarSettings()
  result.view = initEditorViewSettings()
  result.syntax = true
  result.autoCloseParen = true
  result.autoIndent = true
  result.tabStop = 2
  result.defaultCursor = CursorType.blockMode   # Terminal default curosr shape
  result.normalModeCursor = CursorType.blockMode
  result.insertModeCursor = CursorType.ibeamMode
  result.autoSaveInterval = 5
  result.realtimeSearch = true
  result.popUpWindowInExmode = true
  result.replaceTextHighlight = true
  result.highlightPairOfParen = true
  result.autoDeleteParen = true
  result.smoothScroll = true
  result.smoothScrollSpeed = 17
  result.highlightOtherUsesCurrentWord = true
  result.systemClipboard = true
  result.highlightFullWidthSpace = true
  result.buildOnSaveSettings = BuildOnSaveSettings()
  result.workSpace= initWorkSpaceSettings()

proc initStatusBar*(): StatusBar = result.window = initWindow(1, 1, 1, 1, EditorColorPair.defaultChar)

proc initEditorStatus*(): EditorStatus =
  result.platform = initPlatform()
  result.currentDir = getCurrentDir().toRunes
  result.registers = initRegisters()
  result.settings = initEditorSettings()

  if result.settings.workSpace.useBar: result.workSpaceInfoWindow = initWindow(1, terminalWidth(), 0, 0, EditorColorPair.defaultChar)
  var newWorkSpace = initWorkSpace()
  result.workSpace = @[newWorkSpace]

  if result.settings.tabLine.useTab: result.tabWindow = initWindow(1, terminalWidth(), 0, 0, EditorColorPair.defaultChar)

  if result.settings.statusBar.useBar: result.statusBar = @[initStatusBar()]

  result.commandWindow = initWindow(1, terminalWidth(), terminalHeight() - 1, 0, EditorColorPair.defaultChar)

proc changeCurrentBuffer*(status: var EditorStatus, bufferIndex: int) =
  if 0 <= bufferIndex and bufferIndex < status.bufStatus.len:
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex = bufferIndex

proc bufferIndexInCurrentWindow*(status: Editorstatus): int = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex

proc changeMode*(status: var EditorStatus, mode: Mode) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].prevMode = status.bufStatus[currentBufferIndex].mode
  status.bufStatus[currentBufferIndex].mode = mode

proc changeCurrentWin*(status:var EditorStatus, index: int) =
  if index < status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow and index > 0:
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode = status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.searchByWindowIndex(index)

proc executeOnExit(settings: EditorSettings) = changeCursorType(settings.defaultCursor)

proc exitEditor*(settings: EditorSettings) =
  executeOnExit(settings)
  exitUi()
  quit()

proc writeWorkSpaceInfoWindow(status: var Editorstatus) =
  status.workSpaceInfoWindow.erase
  let
    width = status.workSpaceInfoWindow.width
    currentWorkSpaceIndexStr = $status.currentWorkSpaceIndex
    str = if int(width mod 2) == 0: " ".repeat(int(width / 2 - 1)) & currentWorkSpaceIndexStr & " ".repeat(int(width / 2)) else: " ".repeat(int(width / 2)) & currentWorkSpaceIndexStr & " ".repeat(int(width / 2))

  status.workSpaceInfoWindow.write(0, 0, str, EditorColorPair.statusBarNormalMode)
  status.workSpaceInfoWindow.refresh

proc writeStatusBarNormalModeInfo(status: var EditorStatus, statusBarIndex: int) =
  let
    bufferIndex = if status.settings.statusBar.multipleStatusBar: status.statusBar[statusBarIndex].bufferIndex else: status.bufferIndexInCurrentWindow
    color = EditorColorPair.statusBarNormalMode
    currentMode = status.bufStatus[bufferIndex].mode
    statusBarWidth = status.statusBar[statusBarIndex].window.width

  status.statusBar[statusBarIndex].window.append(ru" ", color)

  if status.settings.statusBar.filename:
    let filename = if status.bufStatus[bufferIndex].filename.len > 0: status.bufStatus[bufferIndex].filename else: ru"No name"
    status.statusBar[statusBarIndex].window.append(filename, color)

  if status.bufStatus[bufferIndex].countChange > 0 and status.settings.statusBar.chanedMark: status.statusBar[statusBarIndex].window.append(ru" [+]", color)

  var modeNameLen = 0
  if status.bufStatus[bufferIndex].mode == Mode.ex: modeNameLen = 2
  elif currentMode == Mode.normal or currentMode == Mode.insert or currentMode == Mode.visual or currentMode == Mode.visualBlock or currentMode == Mode.replace: modeNameLen = 6
  if statusBarWidth - modeNameLen < 0: return
  status.statusBar[statusBarIndex].window.append(ru " ".repeat(statusBarWidth - modeNameLen), color)

  let
    line = if status.settings.statusBar.line: fmt"{status.bufStatus[bufferIndex].currentLine + 1}/{status.bufStatus[bufferIndex].buffer.len}" else: ""
    column = if status.settings.statusBar.column: fmt"{status.bufStatus[bufferIndex].currentColumn + 1}/{status.bufStatus[bufferIndex].buffer[status.bufStatus[bufferIndex].currentLine].len}" else: ""
    encoding = if status.settings.statusBar.characterEncoding: $status.settings.characterEncoding else: ""
    language = if status.bufStatus[bufferIndex].language == SourceLanguage.langNone: "Plain" else: sourceLanguageToStr[status.bufStatus[bufferIndex].language]
    info = fmt"{line} {column} {encoding} {language} "
  status.statusBar[statusBarIndex].window.write(0, statusBarWidth - info.len, info, color)

proc writeStatusBarFilerModeInfo(status: var EditorStatus, statusBarIndex: int) =
  let
    color = EditorColorPair.statusBarFilerMode
    statusBarWidth = status.statusBar[statusBarIndex].window.width

  if status.settings.statusBar.directory: status.statusBar[statusBarIndex].window.append(ru" ", color)
  status.statusBar[statusBarIndex].window.append(getCurrentDir().toRunes, color)
  status.statusBar[statusBarIndex].window.append(ru " ".repeat(statusBarWidth - 5), color)

proc writeStatusBarBufferManagerModeInfo(status: var EditorStatus, statusBarIndex: int) =
  let
    bufferIndex = if status.settings.statusBar.multipleStatusBar: status.statusBar[statusBarIndex].bufferIndex else: status.bufferIndexInCurrentWindow
    color = EditorColorPair.statusBarNormalMode
    info = fmt"{status.bufStatus[bufferIndex].currentLine + 1}/{status.bufStatus.len - 1}"
    statusBarWidth = status.statusBar[statusBarIndex].window.width

  status.statusBar[statusBarIndex].window.append(ru " ".repeat(statusBarWidth - " BUFFER ".len), color)
  status.statusBar[statusBarIndex].window.write(0, statusBarWidth - info.len - 1, info, color)

proc writeStatusLogViewerModeInfo(status: var EditorStatus, statusBarIndex: int) =
  let
    bufferIndex = if status.settings.statusBar.multipleStatusBar: status.statusBar[statusBarIndex].bufferIndex else: status.bufferIndexInCurrentWindow
    color = EditorColorPair.statusBarNormalMode
    info = fmt"{status.bufStatus[bufferIndex].currentLine + 1}/{status.bufStatus.len - 1}"
    statusBarWidth = status.statusBar[statusBarIndex].window.width

  status.statusBar[statusBarIndex].window.append(ru " ".repeat(statusBarWidth - " LOG ".len), color)
  status.statusBar[statusBarIndex].window.write(0, statusBarWidth - info.len - 1, info, color)

proc setModeStr(mode: Mode): string =
  case mode:
  of Mode.insert: result = " INSERT "
  of Mode.visual, Mode.visualBlock: result = " VISUAL "
  of Mode.replace: result = " REPLACE "
  of Mode.filer: result = " FILER "
  of Mode.bufManager: result = " BUFFER "
  of Mode.ex: result = " EX "
  of Mode.logViewer: result = " LOG "
  else: result = " NORMAL "

proc setModeStrColor(mode: Mode): EditorColorPair =
  case mode
    of Mode.insert: return EditorColorPair.statusBarModeInsertMode
    of Mode.visual: return EditorColorPair.statusBarModeVisualMode
    of Mode.replace: return EditorColorPair.statusBarModeReplaceMode
    of Mode.filer: return EditorColorPair.statusBarModeFilerMode
    of Mode.ex: return EditorColorPair.statusBarModeExMode
    else: return EditorColorPair.statusBarModeNormalMode

proc writeStatusBar*(status: var EditorStatus, statusBarIndex: int) =
  status.statusBar[statusBarIndex].window.erase

  if statusBarIndex > 0 and not status.settings.statusBar.multipleStatusBar: return

  let
    bufferIndex = if status.settings.statusBar.multipleStatusBar: status.statusBar[statusBarIndex].bufferIndex else: status.bufferIndexInCurrentWindow
    currentMode = status.bufStatus[bufferIndex].mode
    prevMode = status.bufStatus[bufferIndex].prevMode
    color = setModeStrColor(currentMode)
    modeStr = setModeStr(currentMode)

  ## Write current mode
  if status.settings.statusBar.mode: status.statusBar[statusBarIndex].window.write(0, 0, modeStr, color)

  if currentMode == Mode.ex and prevMode == Mode.filer: status.writeStatusBarFilerModeInfo(statusBarIndex)
  elif currentMode == Mode.ex: status.writeStatusBarNormalModeInfo(statusBarIndex)
  elif currentMode == Mode.visual or currentMode == Mode.visualBlock: status.writeStatusBarNormalModeInfo(statusBarIndex)
  elif currentMode == Mode.replace: status.writeStatusBarNormalModeInfo(statusBarIndex)
  elif currentMode == Mode.filer: status.writeStatusBarFilerModeInfo(statusBarIndex)
  elif currentMode == Mode.bufManager: status.writeStatusBarBufferManagerModeInfo(statusBarIndex)
  elif currentMode == Mode.logViewer: status.writeStatusLogViewerModeInfo(statusBarIndex)
  else: writeStatusBarNormalModeInfo(status, statusBarIndex)

  status.statusBar[statusBarIndex].window.refresh

proc writeTab(tabWin: var Window, start, tabWidth: int, filename: string, color: EditorColorPair) =
  let
    title = if filename == "": "New file" else: filename
    buffer = if filename.len < tabWidth: " " & title & " ".repeat(tabWidth - title.len) else: " " & (title).substr(0, tabWidth - 3) & "~"
  tabWin.write(0, start, buffer, color)

proc writeTabLine*(status: var EditorStatus) =
  let
    isAllBuffer = status.settings.tabLine.allbuffer
    defaultColor = EditorColorPair.tab
    currentTabColor = EditorColorPair.currentTab
    currentWindowBuffer = status.bufferIndexInCurrentWindow

  status.tabWindow.erase

  if isAllBuffer:
    ## Display all buffer
    for index, bufStatus in status.bufStatus:
      let
        color = if currentWindowBuffer == index: currentTabColor else: defaultColor
        currentMode = bufStatus.mode
        prevMode = bufStatus.prevMode
        filename = if (currentMode == Mode.filer) or (prevMode == Mode.filer and currentMode == Mode.ex): getCurrentDir() else: $bufStatus.filename
        tabWidth = status.bufStatus.len.calcTabWidth(terminalWidth())
      status.tabWindow.writeTab(index * tabWidth, tabWidth, filename, color)
  else:
    ## Displays only the buffer currently displayed in the window
    let allBufferIndex = status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.getAllBufferIndex
    for index, bufIndex in allBufferIndex:
      let
        color = if currentWindowBuffer == bufIndex: currentTabColor else: defaultColor
        bufStatus = status.bufStatus[bufIndex]
        currentMode = bufStatus.mode
        prevMode = bufStatus.prevMode
        filename = if (currentMode == Mode.filer) or (prevMode == Mode.filer and currentMode == Mode.ex): getCurrentDir() else: $bufStatus.filename
        tabWidth = status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.getAllBufferIndex.len.calcTabWidth(terminalWidth())
      status.tabWindow.writeTab(index * tabWidth, tabWidth, filename, color)

  status.tabWindow.refresh

proc resize*(status: var EditorStatus, height, width: int) =
  setCursor(false)

  let
    useTab = if status.settings.tabLine.useTab: 1 else: 0
    useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    useWorkSpaceBar = if status.settings.workSpace.useBar: 1 else: 0

  status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.resize(useTab + useWorkSpaceBar, 0, height - useTab - useStatusBar - useWorkSpaceBar, width)

  const statusBarHeight = 1
  var
    statusBarIndex = 0
    queue = initHeapQueue[WindowNode]()
  for node in status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.child: queue.push(node)
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

        node.view.resize(status.bufStatus[bufIndex].buffer, adjustedHeight, adjustedWidth, widthOfLineNum)
        node.view.seekCursor(status.bufStatus[bufIndex].buffer, status.bufStatus[bufIndex].currentLine, status.bufStatus[bufIndex].currentColumn)

        ## Resize status bar window
        const height = 1
        let
          width = if node.x > 0 and node.parent.splitType == SplitType.vertical: node.w - 1 else: node.w
          y = node.y + adjustedHeight
          x = if node.x > 0 and node.parent.splitType == SplitType.vertical: node.x + 1 else: node.x
        status.statusBar[statusBarIndex].window.resize(height, width, y, x)
        status.statusBar[statusBarIndex].window.refresh

        ## Set bufStatus index
        status.statusBar[statusBarIndex].bufferIndex = bufIndex

        inc(statusBarIndex)

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  ## Resize status bar window
  if status.settings.statusBar.useBar and not status.settings.statusBar.multipleStatusBar:
    const
      statusBarHeight = 1
      x = 0
    let 
      y = max(height, 4) - 2
    status.statusBar[0].window.resize(statusBarHeight, width, y, x)

  ## Resize work space info window
  if status.settings.workSpace.useBar:
    const
      workSpaceBarHeight = 1
      x = 0
      y = 0
    status.workSpaceInfoWindow.resize(workSpaceBarHeight, width, y, x)

  ## Resize tab line window
  if status.settings.tabLine.useTab:
    const
      tabLineHeight = 1
      x = 0
    let y = if status.settings.workSpace.useBar: 1 else: 0
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
proc highlightOtherUsesCurrentWord*(status: var Editorstatus)
proc highlightSelectedArea(status: var Editorstatus)
proc updateHighlight*(status: var EditorStatus, bufferIndex: int)

proc update*(status: var EditorStatus) =
  setCursor(false)

  if status.settings.workSpace.useBar: status.writeWorkSpaceInfoWindow

  if status.settings.tabLine.useTab: status.writeTabLine

  if status.settings.statusBar.useBar:
    for i in 0 ..< status.statusBar.len: status.writeStatusBar(i)

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    currentMode = status.bufStatus[currentBufferIndex].mode
    prevMode = status.bufStatus[currentBufferIndex].prevMode
    isVisualMode = if (currentMode == Mode.visual) or (prevMode == Mode.visual and currentMode == Mode.ex): true else: false
    isVisualBlockMode = if (currentMode == Mode.visualBlock) or (prevMode == Mode.visualBlock and currentMode == Mode.ex): true else: false

  if (currentMode != Mode.filer) or (currentMode == Mode.ex and prevMode == Mode.filer):
    if status.settings.highlightOtherUsesCurrentWord or status.settings.highlightPairOfParen or isVisualMode: status.updateHighlight(currentBufferIndex)
    if status.settings.highlightOtherUsesCurrentWord and currentMode != Mode.filer: status.highlightOtherUsesCurrentWord
    if isVisualMode or isVisualBlockMode: status.highlightSelectedArea
    if status.settings.highlightPairOfParen and currentMode != Mode.filer: status.highlightPairOfParen

  var queue = initHeapQueue[WindowNode]()
  for node in status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.child: queue.push(node)
  while queue.len > 0:
    for i in  0 ..< queue.len:
      let node = queue.pop
      if node.window != nil:
        let
          bufIndex = node.bufferIndex
          isCurrentMainWin = if node.windowIndex == status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.windowIndex: true else: false
          isVisualMode = if status.bufStatus[bufIndex].mode == Mode.visual or status.bufStatus[bufIndex].mode == Mode.visualBlock: true else: false
          startSelectedLine = status.bufStatus[bufIndex].selectArea.startLine
          endSelectedLine = status.bufStatus[bufIndex].selectArea.endLine

        node.view.seekCursor(status.bufStatus[bufIndex].buffer, status.bufStatus[bufIndex].currentLine, status.bufStatus[bufIndex].currentColumn)
        node.view.update(node.window, status.settings.view, isCurrentMainWin, isVisualMode, status.bufStatus[bufIndex].buffer, status.bufStatus[bufIndex].highlight, status.bufStatus[bufIndex].currentLine, startSelectedLine, endSelectedLine)

        if isCurrentMainWin:
          status.bufStatus[bufIndex].cursor.update(node.view, status.bufStatus[bufIndex].currentLine, status.bufStatus[bufIndex].currentColumn)

        node.window.refresh

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  let bufIndex = status.bufferIndexInCurrentWindow
  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window.moveCursor(status.bufStatus[bufIndex].cursor.y, status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view.widthOfLineNum + status.bufStatus[bufIndex].cursor.x)

  status.commandWindow.erase
  status.commandWindow.refresh

  setCursor(true)

proc verticalSplitWindow*(status: var EditorStatus) =
  let 
    currentBufferIndex = status.bufferIndexInCurrentWindow
    buffer = status.bufStatus[currentBufferIndex].buffer
  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.verticalSplit(buffer)
  inc(status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow)

  var statusBar = initStatusBar()
  statusBar.windowIndex = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.windowIndex
  status.statusBar.add(statusBar)

proc horizontalSplitWindow*(status: var Editorstatus) =
  let 
    currentBufferIndex = status.bufferIndexInCurrentWindow
    buffer = status.bufStatus[currentBufferIndex].buffer
  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.horizontalSplit(buffer)
  inc(status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow)

  var statusBar = initStatusBar()
  statusBar.windowIndex = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.windowIndex
  status.statusBar.add(statusBar)

proc closeWindow*(status: var EditorStatus, node: WindowNode) =
  if status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow == 1: exitEditor(status.settings)

  let deleteWindowIndex = node.windowIndex
  var parent = node.parent

  if parent.child.len == 1:
    if status.settings.statusBar.multipleStatusBar: status.statusBar.delete(status.statusBar.high)

    parent.parent.child.delete(parent.index)
    dec(status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow)

    status.resize(terminalHeight(), terminalWidth())

    let newCurrentWinIndex = if deleteWindowIndex > status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow - 1: status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow - 1 else: deleteWindowIndex
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode = status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.searchByWindowIndex(newCurrentWinIndex)
  else:
    if status.settings.statusBar.multipleStatusBar: status.statusBar.delete(status.statusBar.high)

    parent.child.delete(node.index)
    dec(status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow)

    status.resize(terminalHeight(), terminalWidth())

    let newCurrentWinIndex = if deleteWindowIndex > status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow - 1: status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow - 1 else: deleteWindowIndex
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode = status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.searchByWindowIndex(newCurrentWinIndex)

proc moveCurrentMainWindow*(status: var EditorStatus, index: int) =
  if index < 0 or status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow <= index: return

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.updateHighlight(currentBufferIndex)
  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode = status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.searchByWindowIndex(index)
  status.changeCurrentBuffer(status.bufferIndexInCurrentWindow)
  if status.settings.tabLine.useTab: status.writeTabLine

proc moveNextWindow*(status: var EditorStatus) = status.moveCurrentMainWindow(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.windowIndex + 1)

proc movePrevWindow*(status: var EditorStatus) = status.moveCurrentMainWindow(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.windowIndex - 1)

proc writePopUpWindow*(status: var Editorstatus, x, y: var int, currentLine: int,  buffer: seq[seq[Rune]]) =
  # Pop up window size
  var maxBufferLen = 0
  for runes in buffer:
    if maxBufferLen < runes.len: maxBufferLen = runes.len
  let
    h = if buffer.len > terminalHeight() - 1: terminalHeight() - 1 else: buffer.len
    w = maxBufferLen + 2

  # Pop up window position
  if y == terminalHeight() - 1: y = y - h
  if w > terminalHeight() - x: x = terminalHeight() - w

  status.popUpWindow = initWindow(h, w, y, x, EditorColorPair.popUpWindow)

  let startLine = if currentLine == -1: 0 elif currentLine - h + 1 > 0: currentLine - h + 1 else: 0
  for i in 0 ..< h:
    if currentLine != -1 and i + startLine == currentLine: status.popUpWindow.write(i, 1, buffer[i + startLine], EditorColorPair.popUpWinCurrentLine)
    else: status.popUpWindow.write(i, 1, buffer[i + startLine], EditorColorPair.popUpWindow)

  status.popUpWindow.refresh

proc deletePopUpWindow*(status: var Editorstatus) =
  if status.popUpWindow != nil:
    status.popUpWindow.deleteWindow
    status.update

proc addNewBuffer*(status: var EditorStatus, filename: string)
from commandview import writeFileOpenError

proc addNewBuffer*(status: var EditorStatus, filename: string) =
  status.bufStatus.add(BufferStatus(filename: filename.toRunes, lastSaveTime: now()))
  let index = status.bufStatus.high

  if existsFile(filename) == false: status.bufStatus[index].buffer = newFile()
  else:
    try:
      let textAndEncoding = openFile(filename.toRunes)
      status.bufStatus[index].buffer = textAndEncoding.text.toGapBuffer
      status.settings.characterEncoding = textAndEncoding.encoding
    except IOError:
      status.commandWindow.writeFileOpenError(filename, status.messageLog)
      return

  if filename != "": status.bufStatus[index].language = detectLanguage(filename)
  let lang = if status.settings.syntax: status.bufStatus[index].language else: SourceLanguage.langNone
  status.bufStatus[index].highlight = initHighlight($status.bufStatus[index].buffer, lang)

  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view = initEditorView(status.bufStatus[index].buffer, terminalHeight(), terminalWidth())

  status.changeCurrentBuffer(index)
  status.changeMode(Mode.normal)

proc deleteBuffer*(status: var Editorstatus, deleteIndex: int) =
  let beforeWindowIndex = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.windowIndex

  var queue = initHeapQueue[WindowNode]()
  for node in status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.child: queue.push(node)
  while queue.len > 0:
    for i in 0 ..< queue.len:
      let node = queue.pop
      if node.bufferIndex == deleteIndex: status.closeWindow(node)

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  status.resize(terminalHeight(), terminalWidth())

  status.bufStatus.delete(deleteIndex)

  queue = initHeapQueue[WindowNode]()
  for node in status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.child: queue.push(node)
  while queue.len > 0:
    for i in 0 ..< queue.len:
      var node = queue.pop
      if node.bufferIndex > deleteIndex: dec(node.bufferIndex)

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  let afterWindowIndex = if beforeWindowIndex > status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow - 1: status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow - 1 else: beforeWindowIndex
  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode = status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.searchByWindowIndex(afterWindowIndex)

proc createWrokSpace*(status: var Editorstatus) =
  var newWorkSpace = initWorkSpace()
  status.workSpace.insert(newWorkSpace, status.currentWorkSpaceIndex + 1)
  status.currentWorkSpaceIndex += 1
  status.addNewBuffer("")
  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex = status.bufStatus.high

proc deleteWorkSpace*(status: var Editorstatus, index: int) =
  if 0 <= index and index < status.workSpace.len:
    status.workspace.delete(index)

    if status.workspace.len == 0: status.settings.exitEditor

    if status.currentWorkSpaceIndex > status.workSpace.high: status.currentWorkSpaceIndex = status.workSpace.high

proc changeCurrentWorkSpace*(status: var Editorstatus, index: int) =
  if 0 <= index and index < status.workSpace.len: status.currentWorkSpaceIndex = index

proc tryRecordCurrentPosition*(bufStatus: var BufferStatus) =
  bufStatus.positionRecord[bufStatus.buffer.lastSuitId] = (bufStatus.currentLine, bufStatus.currentColumn, bufStatus.expandedColumn)

proc revertPosition*(bufStatus: var BufferStatus, id: int) =
  doAssert(bufStatus.positionRecord.contains(id), fmt"The id not recorded was requested. [bufStatus.positionRecord = {bufStatus.positionRecord}, id = {id}]")

  bufStatus.currentLine = bufStatus.positionRecord[id].line
  bufStatus.currentColumn = bufStatus.positionRecord[id].column
  bufStatus.expandedColumn = bufStatus.positionRecord[id].expandedColumn

proc eventLoopTask*(status: var Editorstatus)

proc initSelectedAreaColorSegment(startLine, startColumn: int): ColorSegment =
  result.firstRow = startLine
  result.firstColumn = startColumn
  result.lastRow = startLine
  result.lastColumn = startColumn
  result.color = EditorColorPair.visualMode

proc overwriteColorSegmentBlock[T](highlight: var Highlight, area: SelectArea, buffer: T) =
  var
    startLine = area.startLine
    endLine = area.endLine
  if startLine > endLine: swap(startLine, endLine)

  for i in startLine .. endLine:
    let colorSegment = ColorSegment(firstRow: i, firstColumn: area.startColumn, lastRow: i, lastColumn: min(area.endColumn, buffer[i].high), color: EditorColorPair.visualMode)
    highlight = highlight.overwrite(colorSegment)

proc highlightSelectedArea(status: var Editorstatus) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    area = status.bufStatus[currentBufferIndex].selectArea

  var colorSegment = initSelectedAreaColorSegment(status.bufStatus[currentBufferIndex].currentLine, status.bufStatus[currentBufferIndex].currentColumn)

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

  if (currentMode == Mode.visual) or (currentMode == Mode.ex and prevMode == Mode.visual):
    status.bufStatus[currentBufferIndex].highlight = status.bufStatus[currentBufferIndex].highlight.overwrite(colorSegment)
  elif (currentMode == Mode.visualBlock) or (currentMode == Mode.ex and prevMode == Mode.visualBlock):
    status.bufStatus[currentBufferIndex].highlight.overwriteColorSegmentBlock(status.bufStatus[currentBufferIndex].selectArea, status.bufStatus[currentBufferIndex].buffer)

proc highlightPairOfParen(status: var Editorstatus) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    buffer = status.bufStatus[currentBufferIndex].buffer
    currentLine = status.bufStatus[currentBufferIndex].currentLine
    currentColumn = if status.bufStatus[currentBufferIndex].currentColumn > buffer[currentLine].high: buffer[currentLine].high else: status.bufStatus[currentBufferIndex].currentColumn

  if buffer[currentLine].len < 1 or (buffer[currentLine][currentColumn] == ru'"') or (buffer[currentLine][currentColumn] == ru'\''): return

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
          let colorSegment = ColorSegment(firstRow: i, firstColumn: j, lastRow: i, lastColumn: j, color: EditorColorPair.parenText)
          status.bufStatus[currentBufferIndex].highlight = status.bufStatus[currentBufferIndex].highlight.overwrite(colorSegment)
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
          let colorSegment = ColorSegment(firstRow: i, firstColumn: j, lastRow: i, lastColumn: j, color: EditorColorPair.parenText)
          status.bufStatus[currentBufferIndex].highlight = status.bufStatus[currentBufferIndex].highlight.overwrite(colorSegment)
          return

# Highlighting other uses of the current word under the cursor
proc highlightOtherUsesCurrentWord*(status: var Editorstatus) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    bufStatus = status.bufStatus[currentBufferIndex]
    line = bufStatus.buffer[bufStatus.currentLine]

  if line.len < 1 or bufStatus.currentColumn > line.high or (line[bufStatus.currentColumn] != '_' and unicodeext.isPunct(line[bufStatus.currentColumn])) or line[bufStatus.currentColumn].isSpace: return

  var
    startCol = bufStatus.currentColumn
    endCol = bufStatus.currentColumn

  # Set start col
  for i in countdown(bufStatus.currentColumn - 1, 0):
    if (line[i] != '_' and unicodeext.isPunct(line[i])) or line[i].isSpace: break
    else: startCol.dec

  # Set end col
  for i in bufStatus.currentColumn ..< line.len:
    if (line[i] != '_' and unicodeext.isPunct(line[i])) or line[i].isSpace: break
    else: endCol.inc

  let highlightWord = line[startCol ..< endCol]

  let
    range = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view.rangeOfOriginalLineInView
    startLine = range[0]
    endLine = if bufStatus.buffer.len > range[1] + 1: range[1] + 2 elif bufStatus.buffer.len > range[1]: range[1] + 1 else: range[1]

  for i in startLine ..< endLine:
    let line = bufStatus.buffer[i]
    for j in 0 .. (line.len - highlightWord.len):
      let endCol = j + highlightWord.len
      if line[j ..< endCol] == highlightWord:
        if j == 0 or (j > 0 and ((line[j - 1] != '_' and unicodeext.isPunct(line[j - 1])) or line[j - 1].isSpace)):
          if (j == (line.len - highlightWord.len)) or ((line[j + highlightWord.len] != '_' and unicodeext.isPunct(line[j + highlightWord.len])) or line[j + highlightWord.len].isSpace):
            # Set color
            let
              currentBufferIndex = status.bufferIndexInCurrentWindow
              originalColorPair = status.bufStatus[currentBufferIndex].highlight.getColorPair(i, j)
              theme = status.settings.editorColorTheme
              colors = theme.getColorFromEditorColorPair(originalColorPair)
            setColorPair(EditorColorPair.currentWord, colors[0], ColorThemeTable[theme].currentWordBg)

            let colorSegment = ColorSegment(firstRow: i, firstColumn: j, lastRow: i, lastColumn: j + highlightWord.high, color: EditorColorPair.currentWord)
            status.bufStatus[currentBufferIndex].highlight = status.bufStatus[currentBufferIndex].highlight.overwrite(colorSegment)

from searchmode import searchAllOccurrence
proc updateHighlight*(status: var EditorStatus, bufferIndex: int) =
  let
    bufStatus = status.bufStatus[bufferIndex]
    syntax = status.settings.syntax

  if (bufStatus.mode == Mode.filer) or (bufStatus.mode == Mode.ex and bufStatus.prevMode == Mode.filer): return

  status.bufStatus[bufferIndex].highlight = initHighlight($bufStatus.buffer, if syntax: bufStatus.language else: SourceLanguage.langNone)

  let
    range = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view.rangeOfOriginalLineInView
    startLine = range[0]
    endLine = if bufStatus.buffer.len > range[1] + 1: range[1] + 2 elif bufStatus.buffer.len > range[1]: range[1] + 1 else: range[1]
  var bufferInView = initGapBuffer[seq[Rune]]()
  for i in startLine ..< endLine: bufferInView.add(bufStatus.buffer[i])

  # highlight full width space
  if status.settings.highlightFullWidthSpace:
    const fullWidthSpace = ru"　"
    let
      allOccurrence = bufferInView.searchAllOccurrence(fullWidthSpace)
      color = EditorColorPair.highlightFullWidthSpace
    for pos in allOccurrence:
      let colorSegment = ColorSegment(firstRow: pos.line, firstColumn: pos.column, lastRow: pos.line, lastColumn: pos.column, color: color)
      status.bufStatus[bufferIndex].highlight = status.bufStatus[bufferIndex].highlight.overwrite(colorSegment)

  # highlight search results
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if status.bufStatus[currentBufferIndex].isHighlight and status.searchHistory.len > 0:
    let
      keyword = status.searchHistory[^1]
      allOccurrence = searchAllOccurrence(bufferInView, keyword)
      color = if status.isSearchHighlight: EditorColorPair.searchResult else: EditorColorPair.replaceText
    for pos in allOccurrence:
      let colorSegment = ColorSegment(firstRow: pos.line, firstColumn: pos.column, lastRow: pos.line, lastColumn: pos.column + keyword.high, color: color)
      status.bufStatus[bufferIndex].highlight = status.bufStatus[bufferIndex].highlight.overwrite(colorSegment)

proc changeTheme*(status: var EditorStatus) = setCursesColor(ColorThemeTable[status.settings.editorColorTheme])

from commandview import writeMessageAutoSave
proc autoSave(status: var Editorstatus) =
  let interval = status.settings.autoSaveInterval.minutes
  for index, bufStatus in status.bufStatus:
    if bufStatus.filename != ru"" and now() > bufStatus.lastSaveTime + interval:
      saveFile(bufStatus.filename, bufStatus.buffer.toRunes, status.settings.characterEncoding)
      status.commandWindow.writeMessageAutoSave(bufStatus.filename, status.messageLog)
      status.bufStatus[index].lastSaveTime = now()

from settings import loadSettingFile
proc eventLoopTask(status: var Editorstatus) =
  if status.settings.autoSave: status.autoSave
  if status.settings.liveReloadOfConf and status.timeConfFileLastReloaded + 1.seconds < now():
    let beforeTheme = status.settings.editorColorTheme
    status.settings.loadSettingFile
    status.timeConfFileLastReloaded = now()
    if beforeTheme != status.settings.editorColorTheme:
      changeTheme(status)
      status.resize(terminalHeight(), terminalWidth())
