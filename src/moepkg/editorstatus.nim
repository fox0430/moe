import packages/docutils/highlite, strutils, terminal, os, strformat, tables, times, osproc, heapqueue
import gapbuffer, editorview, ui, cursor, unicodeext, highlight, independentutils, fileutils, undoredostack, window

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

type TabLineSettings* = object
  useTab*: bool
  allbuffer*: bool

type EditorSettings* = object
  editorColorTheme*: ColorTheme
  statusBar*: StatusBarSettings
  tabLine*: TabLineSettings
  lineNumber*: bool
  currentLineNumber*: bool
  cursorLine*: bool
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

type EditorStatus* = object
  platform*: Platform
  bufStatus*: seq[BufferStatus]
  currentBuffer*: int
  searchHistory*: seq[seq[Rune]]
  registers*: Registers
  settings*: EditorSettings
  timeConfFileLastReloaded*: DateTime
  isSearchHighlight*: bool
  isReplaceTextHighlight*: bool
  currentDir: seq[Rune]
  messageLog*: seq[seq[Rune]]
  debugMode: int
  mainWindowNode*: WindowNode
  currentMainWindowNode*: WindowNode
  numOfMainWindow*: int
  statusWindow*: Window
  commandWindow*: Window
  tabWindow*: Window
  popUpWindow*: Window

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

proc initEditorSettings*(): EditorSettings =
  result.editorColorTheme = ColorTheme.vivid
  result.statusBar = initStatusBarSettings()
  result.tabLine = initTabBarSettings()
  result.lineNumber = true
  result.currentLineNumber = true
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

proc initEditorStatus*(): EditorStatus =
  result.platform = initPlatform()
  result.currentDir = getCurrentDir().toRunes
  result.registers = initRegisters()
  result.settings = initEditorSettings()

  if result.settings.tabLine.useTab: result.tabWindow = initWindow(1, terminalWidth(), 0, 0, EditorColorPair.defaultChar)
  var rootNode = initWindowNode()
  result.mainWindowNode = rootNode
  result.currentMainWindowNode = rootNode.child[0]
  result.numOfMainWindow = 1

  if result.settings.statusBar.useBar: result.statusWindow = initWindow(1, 1, 1, 1, EditorColorPair.defaultChar)
  result.commandWindow = initWindow(1, terminalWidth(), terminalHeight() - 1, 0, EditorColorPair.defaultChar)

proc changeCurrentBuffer*(status: var EditorStatus, bufferIndex: int) =
  if bufferIndex < 0 and status.bufStatus.high < bufferIndex: return
  status.currentBuffer = bufferIndex
  status.currentMainWindowNode.bufferIndex = bufferIndex

proc changeMode*(status: var EditorStatus, mode: Mode) =
  status.bufStatus[status.currentBuffer].prevMode = status.bufStatus[status.currentBuffer].mode
  status.bufStatus[status.currentBuffer].mode = mode

proc changeCurrentWin*(status:var EditorStatus, index: int) =
  if index < status.numOfMainWindow and index > 0:
    status.currentMainWindowNode = status.mainWindowNode.searchByWindowIndex(index)

proc executeOnExit(settings: EditorSettings) = changeCursorType(settings.defaultCursor)

proc exitEditor*(settings: EditorSettings) =
  executeOnExit(settings)
  exitUi()
  quit()

proc writeStatusBarNormalModeInfo(status: var EditorStatus) =
  let
    color = EditorColorPair.statusBarNormalMode
    currentBuf = status.currentBuffer
    currentMode = status.bufStatus[currentBuf].mode

  status.statusWindow.append(ru" ", color)
  if status.settings.statusBar.filename: status.statusWindow.append(if status.bufStatus[currentBuf].filename.len > 0: status.bufStatus[currentBuf].filename else: ru"No name", color)
  if status.bufStatus[currentBuf].countChange > 0 and status.settings.statusBar.chanedMark: status.statusWindow.append(ru" [+]", color)

  var modeNameLen = 0
  if status.bufStatus[currentBuf].mode == Mode.ex: modeNameLen = 2
  elif currentMode == Mode.normal or currentMode == Mode.insert or currentMode == Mode.visual or currentMode == Mode.visualBlock or currentMode == Mode.replace: modeNameLen = 6
  if terminalWidth() - modeNameLen < 0: return
  status.statusWindow.append(ru " ".repeat(terminalWidth() - modeNameLen), color)

  let
    line = if status.settings.statusBar.line: fmt"{status.bufStatus[currentBuf].currentLine + 1}/{status.bufStatus[currentBuf].buffer.len}" else: ""
    column = if status.settings.statusBar.column: fmt"{status.bufStatus[currentBuf].currentColumn + 1}/{status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine].len}" else: ""
    encoding = if status.settings.statusBar.characterEncoding: $status.settings.characterEncoding else: ""
    language = if status.bufStatus[currentBuf].language == SourceLanguage.langNone: "Plain" else: sourceLanguageToStr[status.bufStatus[currentBuf].language]
    info = fmt"{line} {column} {encoding} {language} "
  status.statusWindow.write(0, terminalWidth() - info.len, info, color)

proc writeStatusBarFilerModeInfo(status: var EditorStatus) =
  let color = EditorColorPair.statusBarFilerMode
  if status.settings.statusBar.directory: status.statusWindow.append(ru" ", color)
  status.statusWindow.append(getCurrentDir().toRunes, color)
  status.statusWindow.append(ru " ".repeat(terminalWidth() - 5), color)

proc writeStatusBarBufferManagerModeInfo(status: var EditorStatus) =
  let
    color = EditorColorPair.statusBarNormalMode
    info = fmt"{status.bufStatus[status.currentBuffer].currentLine + 1}/{status.bufStatus.len - 1}"
  status.statusWindow.append(ru " ".repeat(terminalWidth() - " BUFFER ".len), color)
  status.statusWindow.write(0, terminalWidth() - info.len - 1, info, color)

proc setModeStr(mode: Mode): string =
  case mode:
  of Mode.insert: result = " INSERT "
  of Mode.visual, Mode.visualBlock: result = " VISUAL "
  of Mode.replace: result = " REPLACE "
  of Mode.filer: result = " FILER "
  of Mode.bufManager: result = " BUFFER "
  of Mode.ex: result = " EX "
  else: result = " NORMAL "

proc setModeStrColor(mode: Mode): EditorColorPair =
  case mode
    of Mode.insert: return EditorColorPair.statusBarModeInsertMode
    of Mode.visual: return EditorColorPair.statusBarModeVisualMode
    of Mode.replace: return EditorColorPair.statusBarModeReplaceMode
    of Mode.filer: return EditorColorPair.statusBarModeFilerMode
    of Mode.ex: return EditorColorPair.statusBarModeExMode
    else: return EditorColorPair.statusBarModeNormalMode

proc writeStatusBar*(status: var EditorStatus) =
  status.statusWindow.erase
  let
    mode = status.bufStatus[status.currentBuffer].mode
    color = setModeStrColor(mode)
    modeStr = setModeStr(status.bufStatus[status.currentBuffer].mode)

  if status.settings.statusBar.mode: status.statusWindow.write(0, 0, modeStr, color)

  if mode == Mode.ex and status.bufStatus[status.currentBuffer].prevMode == Mode.filer: writeStatusBarFilerModeInfo(status)
  elif mode == Mode.ex: writeStatusBarNormalModeInfo(status)
  elif mode == Mode.visual or mode == Mode.visualBlock: writeStatusBarNormalModeInfo(status)
  elif mode == Mode.replace: writeStatusBarNormalModeInfo(status)
  elif mode == Mode.filer: writeStatusBarFilerModeInfo(status)
  elif mode == Mode.bufManager: writeStatusBarBufferManagerModeInfo(status)
  else: writeStatusBarNormalModeInfo(status)

  status.statusWindow.refresh

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
    currentWindowBuffer = status.currentMainWindowNode.bufferIndex

  status.tabWindow.erase

  if isAllBuffer:
    ## Display all buffer
    for index, bufStatus in status.bufStatus:
      let
        color = if currentWindowBuffer == index: currentTabColor else: defaultColor
        currentMode = bufStatus.mode
        prevMode = bufStatus.prevMode
        filename = if (currentMode == Mode.filer) or (prevMode == Mode.filer and currentMode == Mode.ex): getCurrentDir() else: $bufStatus.filename
        tabWidth = status.bufStatus.len.calcTabWidth
      status.tabWindow.writeTab(index * tabWidth, tabWidth, filename, color)
  else:
    ## Displays only the buffer currently displayed in the window
    let allBufferIndex = status.mainWindowNode.getAllBufferIndex
    for index, bufIndex in allBufferIndex:
      let
        color = if currentWindowBuffer == bufIndex: currentTabColor else: defaultColor
        bufStatus = status.bufStatus[bufIndex]
        currentMode = bufStatus.mode
        prevMode = bufStatus.prevMode
        filename = if (currentMode == Mode.filer) or (prevMode == Mode.filer and currentMode == Mode.ex): getCurrentDir() else: $bufStatus.filename
        tabWidth = status.numOfMainWindow.calcTabWidth
      status.tabWindow.writeTab(index * tabWidth, tabWidth, filename, color)

  status.tabWindow.refresh

proc resize*(status: var EditorStatus, height, width: int) =
  setCursor(false)
  let
    useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    useTab = if status.settings.tabLine.useTab: 1 else: 0

  status.mainWindowNode.resize(useTab, 0, height - useStatusBar - useTab - 1, width)

  var queue = initHeapQueue[WindowNode]()
  for node in status.mainWindowNode.child: queue.push(node)
  while queue.len > 0:
    let queueLength = queue.len
    for i in  0 ..< queueLength:
      let node = queue.pop
      if node.window != nil:
        let
          bufIndex = node.bufferIndex
          widthOfLineNum = node.view.widthOfLineNum
          blankLine = if node.parent.splitType == SplitType.horaizontal and i < queueLength - 1: 1 else: 0
          adjustedHeight = max(node.h - blankLine, 4)
          adjustedWidth = max(node.w - widthOfLineNum - 1, 4)

        node.view.resize(status.bufStatus[bufIndex].buffer, adjustedHeight, adjustedWidth, widthOfLineNum)
        node.view.seekCursor(status.bufStatus[bufIndex].buffer, status.bufStatus[bufIndex].currentLine, status.bufStatus[bufIndex].currentColumn)

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  let adjustedHeight = max(height, 4)
  if status.settings.statusBar.useBar: status.statusWindow.resize(1, width, adjustedHeight - 2, 0)
  if status.settings.tabLine.useTab: status.tabWindow.resize(1, width, 0, 0)

  if status.settings.statusBar.useBar: writeStatusBar(status)

  status.commandWindow.resize(1, width, adjustedHeight - 1, 0)
  status.commandWindow.refresh

  if status.settings.tabLine.useTab: status.writeTabLine
  setCursor(true)

proc highlightPairOfParen(status: var Editorstatus)
proc highlightOtherUsesCurrentWord*(status: var Editorstatus)

proc update*(status: var EditorStatus) =
  setCursor(false)
  if status.settings.statusBar.useBar: status.writeStatusBar()

  if status.settings.highlightPairOfParen: status.highlightPairOfParen
  status.highlightOtherUsesCurrentWord

  var queue = initHeapQueue[WindowNode]()
  for node in status.mainWindowNode.child: queue.push(node)
  while queue.len > 0:
    for i in  0 ..< queue.len:
      let node = queue.pop
      if node.window != nil:
        let
          bufIndex = node.bufferIndex
          isCurrentMainWin = if node.windowIndex == status.currentMainWindowNode.windowIndex: true else: false
          isLineNumber = status.settings.lineNumber
          isCurrentLineNumber = status.settings.currentLineNumber
          isCursorLine = status.settings.cursorLine
          isVisualMode = if status.bufStatus[bufIndex].mode == Mode.visual or status.bufStatus[bufIndex].mode == Mode.visualBlock: true else: false
          startSelectedLine = status.bufStatus[bufIndex].selectArea.startLine
          endSelectedLine = status.bufStatus[bufIndex].selectArea.endLine

        node.view.seekCursor(status.bufStatus[bufIndex].buffer, status.bufStatus[bufIndex].currentLine, status.bufStatus[bufIndex].currentColumn)
        node.view.update(node.window, isLineNumber, isCurrentLineNumber, isCursorLine, isCurrentMainWin, isVisualMode, status.bufStatus[bufIndex].buffer, status.bufStatus[bufIndex].highlight, status.bufStatus[bufIndex].currentLine, startSelectedLine, endSelectedLine)

        if isCurrentMainWin:
          status.bufStatus[bufIndex].cursor.update(node.view, status.bufStatus[bufIndex].currentLine, status.bufStatus[bufIndex].currentColumn)

        node.window.refresh

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  let bufIndex = status.currentMainWindowNode.bufferIndex
  status.currentMainWindowNode.window.moveCursor(status.bufStatus[bufIndex].cursor.y, status.currentMainWindowNode.view.widthOfLineNum + status.bufStatus[bufIndex].cursor.x)
  setCursor(true)

proc verticalSplitWindow*(status: var EditorStatus) =
  let buffer = status.bufStatus[status.currentBuffer].buffer
  status.currentMainWindowNode = status.currentMainWindowNode.verticalSplit(buffer)
  inc(status.numOfMainWindow)

proc horizontalSplitWindow*(status: var Editorstatus) =
  let buffer = status.bufStatus[status.currentBuffer].buffer
  status.currentMainWindowNode = status.currentMainWindowNode.horizontalSplit(buffer)
  inc(status.numOfMainWindow)

proc closeWindow*(status: var EditorStatus, node: WindowNode) =
  if status.numOfMainWindow == 1: exitEditor(status.settings)

  let deleteWindowIndex = node.windowIndex
  var parent = node.parent

  if parent.child.len == 1:
    parent.parent.child.delete(parent.index)
    dec(status.numOfMainWindow)

    status.resize(terminalHeight(), terminalWidth())

    let newCurrentWinIndex = if deleteWindowIndex > status.numOfMainWindow - 1: status.numOfMainWindow - 1 else: deleteWindowIndex
    status.currentMainWindowNode = status.mainWindowNode.searchByWindowIndex(newCurrentWinIndex)
  else:
    parent.child.delete(node.index)
    dec(status.numOfMainWindow)

    status.resize(terminalHeight(), terminalWidth())

    let newCurrentWinIndex = if deleteWindowIndex > status.numOfMainWindow - 1: status.numOfMainWindow - 1 else: deleteWindowIndex
    status.currentMainWindowNode = status.mainWindowNode.searchByWindowIndex(newCurrentWinIndex)

proc moveCurrentMainWindow*(status: var EditorStatus, index: int) =
  if index < 0 or status.numOfMainWindow <= index: return

  status.currentMainWindowNode = status.mainWindowNode.searchByWindowIndex(index)
  status.changeCurrentBuffer(status.currentMainWindowNode.bufferIndex)
  if status.settings.tabLine.useTab: status.writeTabLine

proc moveNextWindow*(status: var EditorStatus) = status.moveCurrentMainWindow(status.currentMainWindowNode.windowIndex + 1)

proc movePrevWindow*(status: var EditorStatus) = status.moveCurrentMainWindow(status.currentMainWindowNode.windowIndex - 1)

proc writePopUpWindow*(status: var Editorstatus, x, y, currentLine: var int,  buffer: seq[seq[Rune]]) =
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

  for i in 0 ..< h:
    let startLine = if currentLine - h + 1 > 0: currentLine - h + 1 else: 0
    if i + startLine == currentLine: status.popUpWindow.write(i, 1, buffer[i + startLine], EditorColorPair.popUpWinCurrentLine)
    else: status.popUpWindow.write(i, 1, buffer[i + startLine], EditorColorPair.popUpWindow)

  status.popUpWindow.refresh

proc deletePopUpWindow*(status: var Editorstatus) =
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

  status.currentMainWindowNode.view = initEditorView(status.bufStatus[index].buffer, terminalHeight(), terminalWidth())

  status.changeCurrentBuffer(index)
  status.changeMode(Mode.normal)

proc deleteBuffer*(status: var Editorstatus, deleteIndex: int) =
  let beforeWindowIndex = status.currentMainWindowNode.windowIndex

  var queue = initHeapQueue[WindowNode]()
  for node in status.mainWindowNode.child: queue.push(node)
  while queue.len > 0:
    for i in 0 ..< queue.len:
      let node = queue.pop
      if node.bufferIndex == deleteIndex: status.closeWindow(node)

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  status.resize(terminalHeight(), terminalWidth())

  status.bufStatus.delete(deleteIndex)

  queue = initHeapQueue[WindowNode]()
  for node in status.mainWindowNode.child: queue.push(node)
  while queue.len > 0:
    for i in 0 ..< queue.len:
      var node = queue.pop
      if node.bufferIndex > deleteIndex: dec(node.bufferIndex)

      if node.child.len > 0:
        for node in node.child: queue.push(node)

  if status.currentBuffer > status.bufStatus.high: status.currentBuffer = status.bufStatus.high

  let afterWindowIndex = if beforeWindowIndex > status.numOfMainWindow - 1: status.numOfMainWindow - 1 else: beforeWindowIndex
  status.currentMainWindowNode = status.mainWindowNode.searchByWindowIndex(afterWindowIndex)

proc tryRecordCurrentPosition*(bufStatus: var BufferStatus) =
  bufStatus.positionRecord[bufStatus.buffer.lastSuitId] = (bufStatus.currentLine, bufStatus.currentColumn, bufStatus.expandedColumn)

proc revertPosition*(bufStatus: var BufferStatus, id: int) =
  doAssert(bufStatus.positionRecord.contains(id), fmt"The id not recorded was requested. [bufStatus.positionRecord = {bufStatus.positionRecord}, id = {id}]")

  bufStatus.currentLine = bufStatus.positionRecord[id].line
  bufStatus.currentColumn = bufStatus.positionRecord[id].column
  bufStatus.expandedColumn = bufStatus.positionRecord[id].expandedColumn

proc updateHighlight*(status: var EditorStatus)
proc eventLoopTask*(status: var Editorstatus)

proc highlightPairOfParen(status: var Editorstatus) =
  status.updateHighlight

  let 
    buffer = status.bufStatus[status.currentBuffer].buffer
    currentLine = status.bufStatus[status.currentBuffer].currentLine
    currentColumn = if status.bufStatus[status.currentBuffer].currentColumn > buffer[currentLine].high: buffer[currentLine].high else: status.bufStatus[status.currentBuffer].currentColumn

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
          status.bufStatus[status.currentBuffer].highlight = status.bufStatus[status.currentBuffer].highlight.overwrite(colorSegment)
          return
  elif isCloseParen(buffer[currentLine][currentColumn]):
    var depth = 0
    let
      closeParen = buffer[currentLine][currentColumn]
      openParen = correspondingOpenParen(closeParen)
    for i in countdown(currentLine, 0):
      let startColumn = if i == currentLine: currentColumn else: buffer[currentLine].high
      for j in countdown(startColumn, 0):
        if buffer[i].len < 1: break
        if buffer[i][j] == closeParen: inc(depth)
        elif buffer[i][j] == openParen: dec(depth)
        if depth == 0:
          let colorSegment = ColorSegment(firstRow: i, firstColumn: j, lastRow: i, lastColumn: j, color: EditorColorPair.parenText)
          status.bufStatus[status.currentBuffer].highlight = status.bufStatus[status.currentBuffer].highlight.overwrite(colorSegment)
          return

# Highlighting other uses of the current word under the cursor
proc highlightOtherUsesCurrentWord*(status: var Editorstatus) =
  status.updateHighlight

  let
    bufStatus = status.bufStatus[status.currentBuffer]
    line = bufStatus.buffer[bufStatus.currentLine]

  if line.len < 1 or unicodeext.isPunct(line[bufStatus.currentColumn]) or line[bufStatus.currentColumn].isSpace: return

  var
    startCol = bufStatus.currentColumn
    endCol = bufStatus.currentColumn

  # Set start col
  for i in countdown(bufStatus.currentColumn - 1, 1):
    if unicodeext.isPunct(line[i]) or line[i].isSpace: break
    else: startCol.dec

  # Set end col
  for i in bufStatus.currentColumn ..< line.len:
    if unicodeext.isPunct(line[i]) or line[i].isSpace: break
    else: endCol.inc

  let highlightWord = line[startCol ..< endCol]

  for i in 0 ..< bufStatus.buffer.len:
    let line = bufStatus.buffer[i]
    for j in 0 .. (line.len - highlightWord.len):
      let endCol = j + highlightWord.len
      if line[j ..< endCol] == highlightWord:
        if j == 0 or (j > 0 and (unicodeext.isPunct(line[j - 1]) or line[j - 1].isSpace)):
          if (j == (line.len - highlightWord.len)) or (unicodeext.isPunct(line[j + highlightWord.len]) or line[j + highlightWord.len].isSpace):
            let colorSegment = ColorSegment(firstRow: i, firstColumn: j, lastRow: i, lastColumn: j + highlightWord.high, color: EditorColorPair.parenText)
            status.bufStatus[status.currentBuffer].highlight = status.bufStatus[status.currentBuffer].highlight.overwrite(colorSegment)

from searchmode import searchAllOccurrence
proc updateHighlight*(status: var EditorStatus) =
  let
    currentBuf = status.currentBuffer
    syntax = status.settings.syntax

  if not (status.bufStatus[currentBuf].mode == Mode.ex and status.bufStatus[currentBuf].prevMode == Mode.filer):
    status.bufStatus[currentBuf].highlight = initHighlight($status.bufStatus[currentBuf].buffer, if syntax: status.bufStatus[currentBuf].language else: SourceLanguage.langNone)

  # highlight search results
  if status.bufStatus[status.currentBuffer].isHighlight and status.searchHistory.len > 0:
    let
      keyword = status.searchHistory[^1]
      allOccurrence = searchAllOccurrence(status.bufStatus[currentBuf].buffer, keyword)
      color = if status.isSearchHighlight: EditorColorPair.searchResult else: EditorColorPair.replaceText
    for pos in allOccurrence:
      let colorSegment = ColorSegment(firstRow: pos.line, firstColumn: pos.column, lastRow: pos.line, lastColumn: pos.column+keyword.high, color: color)
      status.bufStatus[currentBuf].highlight = status.bufStatus[currentBuf].highlight.overwrite(colorSegment)

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
