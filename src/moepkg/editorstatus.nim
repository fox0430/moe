import packages/docutils/highlite, strutils, terminal, os, strformat
import gapbuffer, editorview, ui, cursor, unicodeext, highlight, independentutils, fileutils
type Mode* = enum
  normal, insert, visual, replace, ex, filer, search, quit

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
  color*: Colorpair
  currentTabColor*: Colorpair

type EditorSettings* = object
  editorColorTheme*: ColorTheme
  editorColor*: EditorColor
  statusBar*: StatusBarSettings
  tabLine*: TabBarSettings
  lineNumber*: bool
  syntax*: bool
  autoCloseParen*: bool
  autoIndent*: bool 
  tabStop*: int
  characterEncoding*: CharacterEncoding # TODO: move to EditorStatus ...?
  defaultCursor*: CursorType
  normalModeCursor*: CursorType
  insertModeCursor*: CursorType

type BufferStatus* = object
  buffer*: GapBuffer[seq[Rune]]
  highlight*: Highlight
  view*: EditorView
  language*: SourceLanguage
  cursor*: CursorPosition
  isHighlight*: bool
  filename*: seq[Rune]
  openDir: seq[Rune]
  currentLine*: int
  currentColumn*: int
  expandedColumn*: int
  countChange*: int
  cmdLoop*: int
  mode* : Mode
  prevMode* : Mode

type EditorStatus* = object
  bufStatus*: seq[BufferStatus]
  currentBuffer*: int
  searchHistory*: seq[seq[Rune]]
  registers*: Registers
  settings*: EditorSettings
  currentDir: seq[Rune]
  debugMode: int
  displayBuffer*: seq[int]
  currentMainWindow*: int
  mainWindow*: seq[Window]
  statusWindow*: Window
  commandWindow*: Window
  tabWindow*: Window

proc initEditorColorTheme(): EditorColor =
 ## vivid theme
 result.editor = Colorpair.brightWhiteDefauLt
 result.lineNum = Colorpair.grayDefault
 result.currentLineNum = Colorpair.pinkDefault
 result.statusBar = Colorpair.blackPink
 result.statusBarMode = Colorpair.blackWhite
 result.tab = Colorpair.brightWhiteDefault
 result.currentTab = Colorpair.blackPink
 result.commandBar = Colorpair.brightWhiteDefault
 result.errorMessage = Colorpair.redDefault

proc initRegisters(): Registers =
  result.yankedLines = @[]
  result.yankedStr = @[]

proc initTabBarSettings*(): TabBarSettings =
  result.useTab = true
  result.color = brightWhiteDefault
  result.currentTabColor = blackPink

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
  result.syntax = true
  result.autoCloseParen = true
  result.autoIndent = true
  result.tabStop = 2
  result.defaultCursor = CursorType.blockMode   # Terminal default curosr shape
  result.normalModeCursor = CursorType.blockMode
  result.insertModeCursor = CursorType.ibeamMode

proc initBufferStatus*(): BufferStatus =
  result.language = SourceLanguage.langNone
  result.isHighlight = true
  result.mode = Mode.normal
  result.prevMode = Mode.normal
  result.filename = ru"new-file-name"

proc initEditorStatus*(): EditorStatus =
  result.bufStatus = @[initBufferStatus()]
  result.currentDir = getCurrentDir().toRunes
  result.registers = initRegisters()
  result.settings = initEditorSettings()
  result.displayBuffer = @[]

  let useStatusBar = if result.settings.statusBar.useBar: 1 else: 0
  let useTab = if result.settings.tabLine.useTab: 1 else: 0

  if result.settings.tabLine.useTab: result.tabWindow = initWindow(1, terminalWidth(), 0, 0)
  result.mainWindow.add(initWindow(terminalHeight() - useTab - 1, terminalWidth(), useTab, 0))
  if result.settings.statusBar.useBar: result.statusWindow = initWindow(1, terminalWidth(), terminalHeight() - useStatusBar - 1, 0, result.settings.editorColor.statusBar)
  result.commandWindow = initWindow(1, terminalWidth(), terminalHeight() - 1, 0)

proc changeCurrentBuffer*(status: var EditorStatus, bufferIndex: int) =
  if bufferIndex < 0 and status.bufStatus.high < bufferIndex: return
  status.currentBuffer = bufferIndex
  status.displayBuffer[status.currentMainWindow] = status.currentBuffer

proc changeMode*(status: var EditorStatus, mode: Mode) =
  status.bufStatus[status.currentBuffer].prevMode = status.bufStatus[status.currentBuffer].mode
  status.bufStatus[status.currentBuffer].mode = mode

proc changeTheme*(status: var EditorStatus) =
  if status.settings.editorColorTheme == ColorTheme.dark:
    status.settings.editorColor.editor = Colorpair.brightWhiteDefauLt
    status.settings.editorColor.lineNum = Colorpair.grayDefault
    status.settings.editorColor.currentLineNum = Colorpair.cyanDefault
    status.settings.editorColor.statusBar = Colorpair.brightWhiteBlue
    status.settings.editorColor.statusBarMode = Colorpair.blackWhite
    status.settings.editorColor.tab = Colorpair.brightWhiteDefault
    status.settings.editorColor.currentTab = Colorpair.brightWhiteBlue
    status.settings.editorColor.commandBar = Colorpair.brightWhiteDefault
    status.settings.editorColor.errorMessage = Colorpair.redDefault
  elif status.settings.editorColorTheme == ColorTheme.light:
    status.settings.editorColor.editor = Colorpair.blackDefault
    status.settings.editorColor.lineNum = Colorpair.grayDefault
    status.settings.editorColor.currentLineNum = Colorpair.blackDefault
    status.settings.editorColor.statusBar = Colorpair.cyanGray
    status.settings.editorColor.statusBarMode = Colorpair.whiteCyan
    status.settings.editorColor.tab = Colorpair.cyanGray
    status.settings.editorColor.currentTab = Colorpair.whiteCyan
    status.settings.editorColor.commandBar = Colorpair.blackDefault
    status.settings.editorColor.errorMessage = Colorpair.redDefault
  elif status.settings.editorColorTheme == ColorTheme.vivid:
    status.settings.editorColor.editor = Colorpair.brightWhiteDefauLt
    status.settings.editorColor.lineNum = Colorpair.grayDefault
    status.settings.editorColor.currentLineNum = Colorpair.pinkDefault
    status.settings.editorColor.statusBar = Colorpair.blackPink
    status.settings.editorColor.statusBarMode = Colorpair.blackWhite
    status.settings.editorColor.tab = Colorpair.brightWhiteDefault
    status.settings.editorColor.currentTab = Colorpair.blackPink
    status.settings.editorColor.commandBar = Colorpair.brightWhiteDefault
    status.settings.editorColor.errorMessage = Colorpair.redDefault

proc changeCurrentWin*(status:var EditorStatus, index: int) =
  if index < status.mainWindow.high and index > 0: status.currentMainWindow = index

proc executeOnExit*(settings: EditorSettings) =
  changeCursorType(settings.defaultCursor)

proc writeStatusBarNormalModeInfo(status: var EditorStatus) =
  let
    color = status.settings.editorColor.statusBar
    currentBuf = status.currentBuffer
    currentMode = status.bufStatus[currentBuf].mode

  status.statusWindow.append(ru" ", color)
  if status.settings.statusBar.filename: status.statusWindow.append(if status.bufStatus[currentBuf].filename.len > 0: status.bufStatus[currentBuf].filename else: ru"No name", color)
  if status.bufStatus[currentBuf].countChange > 0 and status.settings.statusBar.chanedMark: status.statusWindow.append(ru" [+]", color)

  var modeNameLen = 0
  if status.bufStatus[currentBuf].mode == Mode.ex: modeNameLen = 2
  elif currentMode == Mode.normal or currentMode == Mode.insert or currentMode == Mode.visual or currentMode == Mode.replace: modeNameLen = 6
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
  let color = status.settings.editorColor.statusBar
  if status.settings.statusBar.directory: status.statusWindow.append(ru" ", color)
  status.statusWindow.append(getCurrentDir().toRunes, color)
  status.statusWindow.append(ru " ".repeat(terminalWidth() - 5), color)

proc writeStatusBar*(status: var EditorStatus) =
  status.statusWindow.erase
  let color = status.settings.editorColor.statusBarMode

  if status.bufStatus[status.currentBuffer].mode == Mode.ex:
    if status.settings.statusBar.mode: status.statusWindow.write(0, 0, ru" EX ", color)
    if status.bufStatus[status.currentBuffer].prevMode == Mode.filer:
      writeStatusBarFilerModeInfo(status)
    else:
      writeStatusBarNormalModeInfo(status)
  elif status.bufStatus[status.currentBuffer].mode == Mode.visual:
    if status.settings.statusBar.mode: status.statusWindow.write(0, 0, ru" VISUAL ", color)
    writeStatusBarNormalModeInfo(status)
  elif status.bufStatus[status.currentBuffer].mode == Mode.replace:
    if status.settings.statusBar.mode: status.statusWindow.write(0, 0, ru" REPLACE ", color)
    writeStatusBarNormalModeInfo(status)
  elif status.bufStatus[status.currentBuffer].mode == Mode.filer:
    if status.settings.statusBar.mode: status.statusWindow.write(0, 0, ru" FILER ", color)
    writeStatusBarFilerModeInfo(status)
  else:
    if status.settings.statusBar.mode:
      status.statusWindow.write(0, 0,  if status.bufStatus[status.currentBuffer].mode == Mode.normal: ru" NORMAL " else: ru" INSERT ", color)
    writeStatusBarNormalModeInfo(status)

  status.statusWindow.refresh

import tab

proc resize*(status: var EditorStatus, height, width: int) =
  let 
    adjustedHeight = max(height, 4)
    useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    useTab = if status.bufStatus[status.currentBuffer].mode != Mode.filer and status.settings.tabLine.useTab: 1 else: 0

  for i in 0 ..< status.displayBuffer.len:
    let
      bufIndex = status.displayBuffer[i]
      beginX = i * int(terminalWidth() / status.mainWindow.len)
      widthOfLineNum = status.bufStatus[bufIndex].view.widthOfLineNum
      adjustedWidth = max(int(width / status.mainWindow.len), widthOfLineNum + 4)

    status.mainWindow[i].resize(adjustedHeight - useStatusBar - useTab - 1, adjustedWidth, useTab, beginX)

    if status.settings.statusBar.useBar: resize(status.statusWindow, 1, terminalWidth(), adjustedHeight - 2, 0)
    if status.bufStatus[status.currentBuffer].mode != Mode.filer and  status.settings.tabLine.useTab: resize(status.tabWindow, 1, terminalWidth(), 0, 0)
    
    if status.bufStatus[status.currentBuffer].mode != Mode.filer:
      status.bufStatus[bufIndex].view.resize(status.bufStatus[bufIndex].buffer, adjustedHeight - useStatusBar - 1, adjustedWidth - widthOfLineNum - 1, widthOfLineNum)
      status.bufStatus[bufIndex].view.seekCursor(status.bufStatus[bufIndex].buffer, status.bufStatus[bufIndex].currentLine, status.bufStatus[bufIndex].currentColumn)

  if status.settings.statusBar.useBar: writeStatusBar(status)

  resize(status.commandWindow, 1, terminalWidth(), adjustedHeight - 1, 0)
  status.commandWindow.refresh

  if status.bufStatus[status.currentBuffer].mode != Mode.filer and status.settings.tabLine.useTab: writeTabLine(status)

proc erase*(status: var EditorStatus) =
  erase(status.mainWindow[status.currentMainWindow])
  erase(status.statusWindow)
  erase(status.commandWindow)

proc update*(status: var EditorStatus) =
  setCursor(false)
  if status.settings.statusBar.useBar: writeStatusBar(status)

  for i in 0 ..< status.displayBuffer.len:
    let
      bufIndex = status.displayBuffer[i]
      isCurrentMainWin = if i == status.currentMainWindow: true else: false
    if isCurrentMainWin: status.bufStatus[bufIndex].view.seekCursor(status.bufStatus[bufIndex].buffer, status.bufStatus[bufIndex].currentLine, status.bufStatus[bufIndex].currentColumn)
    status.bufStatus[bufIndex].view.update(status.mainWindow[i], status.settings.lineNumber, isCurrentMainWin, status.bufStatus[bufIndex].buffer, status.bufStatus[bufIndex].highlight, status.settings.editorColor, status.bufStatus[bufIndex].currentLine)

    if isCurrentMainWin: status.bufStatus[bufIndex].cursor.update(status.bufStatus[bufIndex].view, status.bufStatus[bufIndex].currentLine, status.bufStatus[bufIndex].currentColumn)

    status.mainWindow[i].refresh

  status.mainWindow[status.currentMainWindow].moveCursor(status.bufStatus[status.currentBuffer].cursor.y, status.bufStatus[status.currentBuffer].view.widthOfLineNum + status.bufStatus[status.currentBuffer].cursor.x)
  setCursor(true)

proc splitWindow*(status: var EditorStatus) =
  let
    numberOfDigitsLen = if status.settings.lineNumber: numberOfDigits(status.bufStatus[0].buffer.len) - 2 else: 0
    useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    useTab = if status.bufStatus[status.currentBuffer].mode != Mode.filer and status.settings.tabLine.useTab: 1 else: 0

  status.displayBuffer.add(status.currentBuffer)
  status.mainWindow.add(initWindow(terminalHeight() - useTab - 1, int(terminalWidth() / status.mainWindow.len), useTab, int(terminalWidth() / status.mainWindow.len)))

  status.update

proc closeWindow*(status: var EditorStatus, index: int) =
  if index < 0 or index > status.displayBuffer.high or index > status.mainWindow.high: return

  status.mainWindow.delete(index)
  status.displayBuffer.delete(index)
  if status.mainWindow.len > 0:
    status.currentMainWindow = if index > status.mainWindow.high: status.mainWindow.high else: index
    status.currentBuffer = status.displayBuffer[status.currentMainWindow]

proc moveCurrentMainWindow*(status: var EditorStatus, index: int) =
  if index < 0 or status.mainWindow.high < index: return

  status.currentMainWindow = index
  changeCurrentBuffer(status, status.displayBuffer[index])
  if status.bufStatus[status.currentBuffer].mode != Mode.filer and status.settings.tabLine.useTab: writeTabLine(status)

proc updateHighlight*(status: var EditorStatus)

from searchmode import searchAllOccurrence

proc updateHighlight*(status: var EditorStatus) =
  let
    currentBuf = status.currentBuffer
    syntax = status.settings.syntax

  status.bufStatus[currentBuf].highlight = initHighlight($status.bufStatus[currentBuf].buffer, if syntax: status.bufStatus[currentBuf].language else: SourceLanguage.langNone, status.settings.editorColor.editor)

  # highlight search results
  if status.bufStatus[status.currentBuffer].isHighlight and status.searchHistory.len > 0:
    let keyword = status.searchHistory[^1]
    let allOccurrence = searchAllOccurrence(status.bufStatus[currentBuf].buffer, keyword)
    for pos in allOccurrence:
      let colorSegment = ColorSegment(firstRow: pos.line, firstColumn: pos.column, lastRow: pos.line, lastColumn: pos.column+keyword.high, color: defaultMagenta)
      status.bufStatus[currentBuf].highlight = status.bufStatus[currentBuf].highlight.overwrite(colorSegment)
