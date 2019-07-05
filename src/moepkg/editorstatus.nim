import packages/docutils/highlite, strutils, terminal, os, strformat, tables, times
import gapbuffer, editorview, ui, cursor, unicodeext, highlight, independentutils, fileutils, undoredostack

type Mode* = enum
  normal, insert, visual, visualBlock, replace, ex, filer, search, bufManager

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

type TabBarSettings* = object
  useTab*: bool

type EditorSettings* = object
  editorColorTheme*: ColorTheme
  statusBar*: StatusBarSettings
  tabLine*: TabBarSettings
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

type BufferStatus* = object
  buffer*: GapBuffer[seq[Rune]]
  highlight*: Highlight
  view*: EditorView
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

type MainWindowInfo = object
  window*: Window
  bufferIndex*: int

type EditorStatus* = object
  bufStatus*: seq[BufferStatus]
  currentBuffer*: int
  searchHistory*: seq[seq[Rune]]
  registers*: Registers
  settings*: EditorSettings
  currentDir: seq[Rune]
  lastSaveTime: DateTime
  debugMode: int
  currentMainWindow*: int
  mainWindowInfo*: seq[MainWindowInfo]
  statusWindow*: Window
  commandWindow*: Window
  tabWindow*: Window

proc initRegisters(): Registers =
  result.yankedLines = @[]
  result.yankedStr = @[]

proc initTabBarSettings*(): TabBarSettings =
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

proc initEditorStatus*(): EditorStatus =
  result.lastSaveTime = now()
  result.currentDir = getCurrentDir().toRunes
  result.registers = initRegisters()
  result.settings = initEditorSettings()

  let
    useStatusBar = if result.settings.statusBar.useBar: 1 else: 0
    useTab = if result.settings.tabLine.useTab: 1 else: 0

  if result.settings.tabLine.useTab: result.tabWindow = initWindow(1, terminalWidth(), 0, 0)

  result.mainWindowInfo.add(MainWindowInfo(window: initWindow(terminalHeight() - useTab - 1, terminalWidth(), useTab, 0), bufferIndex: 0))
  result.mainWindowInfo[result.mainWindowInfo.high].window.setTimeout()

  if result.settings.statusBar.useBar: result.statusWindow = initWindow(1, terminalWidth(), terminalHeight() - useStatusBar - 1, 0)
  result.commandWindow = initWindow(1, terminalWidth(), terminalHeight() - 1, 0)

proc changeCurrentBuffer*(status: var EditorStatus, bufferIndex: int) =
  if bufferIndex < 0 and status.bufStatus.high < bufferIndex: return
  status.currentBuffer = bufferIndex
  status.mainWindowInfo[status.currentMainWindow].bufferIndex = bufferIndex

proc changeMode*(status: var EditorStatus, mode: Mode) =
  status.bufStatus[status.currentBuffer].prevMode = status.bufStatus[status.currentBuffer].mode
  status.bufStatus[status.currentBuffer].mode = mode

proc changeCurrentWin*(status:var EditorStatus, index: int) =
  if index < status.mainWindowInfo.high and index > 0: status.currentMainWindow = index

proc executeOnExit(settings: EditorSettings) = changeCursorType(settings.defaultCursor)

proc exitEditor*(settings: EditorSettings) =
  executeOnExit(settings)
  exitUi()
  quit()

proc writeStatusBarNormalModeInfo(status: var EditorStatus) =
  let
    color = EditorColorPair.statusBar
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
  let color = EditorColorPair.statusBar
  if status.settings.statusBar.directory: status.statusWindow.append(ru" ", color)
  status.statusWindow.append(getCurrentDir().toRunes, color)
  status.statusWindow.append(ru " ".repeat(terminalWidth() - 5), color)

proc writeStatusBarBufferManagerModeInfo(status: var EditorStatus) =
  let
    color = EditorColorPair.statusBar
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

proc writeStatusBar*(status: var EditorStatus) =
  status.statusWindow.erase
  let
    color = EditorColorPair.statusBarMode
    mode = status.bufStatus[status.currentBuffer].mode
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
    tabWidth = calcTabWidth(status.mainWindowInfo.len)
    defaultColor = EditorColorPair.tab
    currentTabColor = EditorColorPair.currentTab

  status.tabWindow.erase

  for i in 0 ..< status.mainWindowInfo.len:
    let
      color = if status.currentMainWindow == i: currentTabColor else: defaultColor
      currentMode = status.bufStatus[status.mainWindowInfo[i].bufferIndex].mode
      prevMode = status.bufStatus[status.mainWindowInfo[i].bufferIndex].prevMode
      filename = if (currentMode == Mode.filer) or (prevMode == Mode.filer and currentMode == Mode.ex): getCurrentDir() else: $status.bufStatus[status.mainWindowInfo[i].bufferIndex].filename
    status.tabWindow.writeTab(i * tabWidth, tabWidth, filename, color)

  status.tabWindow.refresh

proc resize*(status: var EditorStatus, height, width: int) =
  setCursor(false)
  let
    adjustedHeight = max(height, 4)
    useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    useTab = if status.settings.tabLine.useTab: 1 else: 0

  for i in 0 ..< status.mainWindowInfo.len:
    let
      bufIndex = status.mainWindowInfo[i].bufferIndex
      beginX = i * int(terminalWidth() / status.mainWindowInfo.len)
      widthOfLineNum = status.bufStatus[bufIndex].view.widthOfLineNum
      adjustedWidth = max(int(width / status.mainWindowInfo.len), widthOfLineNum + 4)

    status.mainWindowInfo[i].window.resize(adjustedHeight - useStatusBar - useTab - 1, adjustedWidth, useTab, beginX)

    if status.settings.statusBar.useBar: resize(status.statusWindow, 1, terminalWidth(), adjustedHeight - 2, 0)
    if status.settings.tabLine.useTab: resize(status.tabWindow, 1, terminalWidth(), 0, 0)

    status.bufStatus[bufIndex].view.resize(status.bufStatus[bufIndex].buffer, adjustedHeight - useStatusBar - useTab - 1, adjustedWidth - widthOfLineNum - 1, widthOfLineNum)
    status.bufStatus[bufIndex].view.seekCursor(status.bufStatus[bufIndex].buffer, status.bufStatus[bufIndex].currentLine, status.bufStatus[bufIndex].currentColumn)

  if status.settings.statusBar.useBar: writeStatusBar(status)

  resize(status.commandWindow, 1, terminalWidth(), adjustedHeight - 1, 0)
  status.commandWindow.refresh

  if status.settings.tabLine.useTab: writeTabLine(status)
  setCursor(true)

proc update*(status: var EditorStatus) =
  setCursor(false)
  if status.settings.statusBar.useBar: writeStatusBar(status)

  for i in 0 ..< status.mainWindowInfo.len:
    let
      bufIndex = status.mainWindowInfo[i].bufferIndex
      isCurrentMainWin = if i == status.currentMainWindow: true else: false
      isLineNumber = status.settings.lineNumber
      isCurrentLineNumber = status.settings.currentLineNumber
      isCursorLine = status.settings.cursorLine
      isVisualMode = if status.bufStatus[bufIndex].mode == Mode.visual or status.bufStatus[bufIndex].mode == Mode.visualBlock: true else: false
      startSelectedLine = status.bufStatus[bufIndex].selectArea.startLine
      endSelectedLine = status.bufStatus[bufIndex].selectArea.endLine

    status.bufStatus[bufIndex].view.seekCursor(status.bufStatus[bufIndex].buffer, status.bufStatus[bufIndex].currentLine, status.bufStatus[bufIndex].currentColumn)
    status.bufStatus[bufIndex].view.update(status.mainWindowInfo[i].window, isLineNumber, isCurrentLineNumber, isCursorLine, isCurrentMainWin, isVisualMode, status.bufStatus[bufIndex].buffer, status.bufStatus[bufIndex].highlight, status.bufStatus[bufIndex].currentLine, startSelectedLine, endSelectedLine)

    status.bufStatus[bufIndex].cursor.update(status.bufStatus[bufIndex].view, status.bufStatus[bufIndex].currentLine, status.bufStatus[bufIndex].currentColumn)

    status.mainWindowInfo[i].window.refresh

  status.mainWindowInfo[status.currentMainWindow].window.moveCursor(status.bufStatus[status.currentBuffer].cursor.y, status.bufStatus[status.currentBuffer].view.widthOfLineNum + status.bufStatus[status.currentBuffer].cursor.x)
  setCursor(true)

proc splitWindow*(status: var EditorStatus) =
  let useTab = if status.settings.tabLine.useTab: 1 else: 0
  status.mainWindowInfo.insert(MainWindowInfo(window: initWindow(terminalHeight() - useTab - 1, int(terminalWidth() / status.mainWindowInfo.len), useTab, int(terminalWidth() / status.mainWindowInfo.len)), bufferIndex: status.currentBuffer), status.currentMainWindow)
  status.mainWindowInfo[status.currentMainWindow + 1].window.setTimeout()

  status.update

proc closeWindow*(status: var EditorStatus, index: int) =
  if index < 0 or index > status.mainWindowInfo.high: return

  status.mainWindowInfo.delete(index)
  if status.mainWindowInfo.len > 0:
    status.currentMainWindow = if index > status.mainWindowInfo.high: status.mainWindowInfo.high else: index
    status.currentBuffer = status.mainWindowInfo[status.currentMainWindow].bufferIndex

proc moveCurrentMainWindow*(status: var EditorStatus, index: int) =
  if index < 0 or status.mainWindowInfo.high < index: return

  status.currentMainWindow = index
  changeCurrentBuffer(status, status.mainWindowInfo[index].bufferIndex)
  if status.settings.tabLine.useTab: writeTabLine(status)

proc moveNextWindow*(status: var EditorStatus) = moveCurrentMainWindow(status, status.currentMainWindow + 1)

proc movePrevWindow*(status: var EditorStatus) = moveCurrentMainWindow(status, status.currentMainWindow - 1)

proc countReferencedWindow*(mainWins: seq[MainWindowInfo], bufferIndex: int): int =
  result = 0
  for i in 0 ..< mainWins.len:
    if mainWins[i].bufferIndex == bufferIndex: result.inc

proc addNewBuffer*(status:var EditorStatus, filename: string)
from commandview import writeFileOpenError

proc addNewBuffer*(status:var EditorStatus, filename: string) =
  status.bufStatus.add(BufferStatus(filename: filename.toRunes))
  let index = status.bufStatus.high

  if existsFile(filename) == false: status.bufStatus[index].buffer = newFile()
  else:
    try:
      let textAndEncoding = openFile(filename.toRunes)
      status.bufStatus[index].buffer = textAndEncoding.text.toGapBuffer
      status.settings.characterEncoding = textAndEncoding.encoding
    except IOError:
      status.commandWindow.writeFileOpenError(filename)
      return

  if filename != "": status.bufStatus[index].language = detectLanguage(filename)
  let lang = if status.settings.syntax: status.bufStatus[index].language else: SourceLanguage.langNone
  status.bufStatus[index].highlight = initHighlight($status.bufStatus[index].buffer, lang)

  let
    numberOfDigitsLen = if status.settings.lineNumber: numberOfDigits(status.bufStatus[index].buffer.len) - 2 else: 0
    useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    useTab = if status.settings.tabLine.useTab: 1 else: 0
  status.bufStatus[index].view = initEditorView(status.bufStatus[index].buffer, terminalHeight() - useStatusBar - useTab - 1, terminalWidth() - numberOfDigitsLen)

  status.changeCurrentBuffer(index)
  status.changeMode(Mode.normal)

proc tryRecordCurrentPosition*(bufStatus: var BufferStatus) =
  bufStatus.positionRecord[bufStatus.buffer.lastSuitId] = (bufStatus.currentLine, bufStatus.currentColumn, bufStatus.expandedColumn)

proc revertPosition*(bufStatus: var BufferStatus, id: int) =
  doAssert(bufStatus.positionRecord.contains(id), fmt"The id not recorded was requested. [bufStatus.positionRecord = {bufStatus.positionRecord}, id = {id}]")

  bufStatus.currentLine = bufStatus.positionRecord[id].line
  bufStatus.currentColumn = bufStatus.positionRecord[id].column
  bufStatus.expandedColumn = bufStatus.positionRecord[id].expandedColumn

proc updateHighlight*(status: var EditorStatus)
proc autoSave*(status: var Editorstatus)

from searchmode import searchAllOccurrence
proc updateHighlight*(status: var EditorStatus) =
  let
    currentBuf = status.currentBuffer
    syntax = status.settings.syntax

  status.bufStatus[currentBuf].highlight = initHighlight($status.bufStatus[currentBuf].buffer, if syntax: status.bufStatus[currentBuf].language else: SourceLanguage.langNone)

  # highlight search results
  if status.bufStatus[status.currentBuffer].isHighlight and status.searchHistory.len > 0:
    let
      keyword = status.searchHistory[^1]
      allOccurrence = searchAllOccurrence(status.bufStatus[currentBuf].buffer, keyword)
    for pos in allOccurrence:
      let colorSegment = ColorSegment(firstRow: pos.line, firstColumn: pos.column, lastRow: pos.line, lastColumn: pos.column+keyword.high, color: EditorColorPair.searchResult)
      status.bufStatus[currentBuf].highlight = status.bufStatus[currentBuf].highlight.overwrite(colorSegment)

proc changeTheme*(status: var EditorStatus) =
  setCursesColor(ColorThemeTable[status.settings.editorColorTheme])
  if status.settings.editorColorTheme == ColorTheme.light: status.updateHighlight

from commandview import writeMessageAutoSave
proc autoSave(status: var Editorstatus) =
  if not status.settings.autoSave: return

  if now() > status.lastSaveTime + status.settings.autoSaveInterval.minutes:
    let bufStatus = status.bufStatus[status.currentBuffer]
    saveFile(bufStatus.filename, bufStatus.buffer.toRunes, status.settings.characterEncoding)
    status.commandWindow.writeMessageAutoSave(bufStatus.filename)
    status.lastSaveTime = now()
