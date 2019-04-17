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
  language*: SourceLanguage
  cursor*: CursorPosition
  isHighlight*: bool
  filename*: seq[Rune]
  openDir: seq[Rune]
  currentLine*: int
  currentColumn*: int
  expandedColumn*: int
  cmdLoop*: int
  countChange*: int
  prevMode* : Mode
  mode* : Mode

type EditorStatus* = object
  bufStatus*: seq[BufferStatus]
  currentBuffer*: int
  buffer*: GapBuffer[seq[Rune]]
  highlight*: Highlight
  language*: SourceLanguage
  searchHistory*: seq[seq[Rune]]
  view*: seq[EditorView]
  cursor*: CursorPosition
  isHighlight*: bool
  registers*: Registers
  settings*: EditorSettings
  filename*: seq[Rune]
  openDir: seq[Rune]
  currentDir: seq[Rune]
  currentLine*: int
  currentColumn*: int
  expandedColumn*: int
  prevMode* : Mode
  mode* : Mode
  cmdLoop*: int
  countChange*: int
  debugMode: int
  currentMainWindow*: int
  mainWindow*: seq[Window]
  statusWindow*: Window
  commandWindow*: Window
  tabWindow*: Window

import tab

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

proc initEditorStatus*(): EditorStatus =
  result.currentDir = getCurrentDir().toRunes
  result.language = SourceLanguage.langNone
  result.registers = initRegisters()
  result.settings = initEditorSettings()
  result.mode = Mode.normal
  result.prevMode = Mode.normal
  result.isHighlight = true

  let useStatusBar = if result.settings.statusBar.useBar: 1 else: 0
  let useTab = if result.settings.tabLine.useTab: 1 else: 0

  if result.settings.tabLine.useTab: result.tabWindow = initWindow(1, terminalWidth(), 0, 0)
  result.mainWindow.add(initWindow(terminalHeight() - useTab - 1, terminalWidth(), useTab, 0))
  if result.settings.statusBar.useBar: result.statusWindow = initWindow(1, terminalWidth(), terminalHeight() - useStatusBar - 1, 0, result.settings.editorColor.statusBar)
  result.commandWindow = initWindow(1, terminalWidth(), terminalHeight() - 1, 0)

proc changeCurrentBuffer*(status: var EditorStatus, bufferIndex: int) =
  if status.bufStatus.len > 1 and bufferIndex < status.bufStatus.high:
    status.bufStatus[status.currentBuffer].buffer = status.buffer
    status.bufStatus[status.currentBuffer].highlight = status.highlight
    status.bufStatus[status.currentBuffer].language = status.language
    status.bufStatus[status.currentBuffer].cursor = status.cursor
    status.bufStatus[status.currentBuffer].filename = status.filename
    status.bufStatus[status.currentBuffer].openDir = status.openDir
    status.bufStatus[status.currentBuffer].currentLine = status.currentLine
    status.bufStatus[status.currentBuffer].currentColumn = status.currentColumn
    status.bufStatus[status.currentBuffer].expandedColumn = status.expandedColumn
    status.bufStatus[status.currentBuffer].cmdLoop = status.cmdLoop
    status.bufStatus[status.currentBuffer].countChange = status.countChange
    status.bufStatus[status.currentBuffer].mode = status.mode
    status.bufStatus[status.currentBuffer].prevMode = status.mode

  status.buffer = status.bufStatus[bufferIndex].buffer
  status.highlight = status.bufStatus[bufferIndex].highlight
  status.language = status.bufStatus[bufferIndex].language
  status.cursor = status.bufStatus[bufferIndex].cursor
  status.filename = status.bufStatus[bufferIndex].filename
  status.openDir = status.bufStatus[bufferIndex].openDir
  status.currentLine = status.bufStatus[bufferIndex].currentLine
  status.currentColumn = status.bufStatus[bufferIndex].currentColumn
  status.expandedColumn = status.bufStatus[bufferIndex].expandedColumn
  status.cmdLoop = status.bufStatus[bufferIndex].cmdLoop
  status.countChange = status.bufStatus[bufferIndex].countChange
  status.mode = status.bufStatus[bufferIndex].mode
  status.prevMode = status.bufStatus[bufferIndex].prevMode
  status.currentBuffer = bufferIndex

proc changeMode*(status: var EditorStatus, mode: Mode) =
  status.prevMode = status.mode
  status.mode = mode

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
  let color = status.settings.editorColor.statusBar
  status.statusWindow.append(ru" ", color)
  if status.settings.statusBar.filename: status.statusWindow.append(if status.filename.len > 0: status.filename else: ru"No name", color)
  if status.countChange > 0 and status.settings.statusBar.chanedMark: status.statusWindow.append(ru" [+]", color)

  var modeNameLen = 0
  if status.mode == Mode.ex: modeNameLen = 2
  elif status.mode == Mode.normal or status.mode == Mode.insert or status.mode == Mode.visual or status.mode == Mode.replace: modeNameLen = 6
  if terminalWidth() - modeNameLen < 0: return
  status.statusWindow.append(ru " ".repeat(terminalWidth() - modeNameLen), color)

  let
    line = if status.settings.statusBar.line: fmt"{status.currentLine+1}/{status.buffer.len}" else: ""
    column = if status.settings.statusBar.column: fmt"{status.currentColumn + 1}/{status.buffer[status.currentLine].len}" else: ""
    encoding = if status.settings.statusBar.characterEncoding: $status.settings.characterEncoding else: ""
    language = if status.language == SourceLanguage.langNone: "Plain" else: sourceLanguageToStr[status.language]
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

  if status.mode == Mode.ex:
    if status.settings.statusBar.mode: status.statusWindow.write(0, 0, ru" EX ", color)
    if status.prevMode == Mode.filer:
      writeStatusBarFilerModeInfo(status)
    else:
      writeStatusBarNormalModeInfo(status)
  elif status.mode == Mode.visual:
    if status.settings.statusBar.mode: status.statusWindow.write(0, 0, ru" VISUAL ", color)
    writeStatusBarNormalModeInfo(status)
  elif status.mode == Mode.replace:
    if status.settings.statusBar.mode: status.statusWindow.write(0, 0, ru" REPLACE ", color)
    writeStatusBarNormalModeInfo(status)
  elif status.mode == Mode.filer:
    if status.settings.statusBar.mode: status.statusWindow.write(0, 0, ru" FILER ", color)
    writeStatusBarFilerModeInfo(status)
  else:
    if status.settings.statusBar.mode:
      status.statusWindow.write(0, 0,  if status.mode == Mode.normal: ru" NORMAL " else: ru" INSERT ", color)
    writeStatusBarNormalModeInfo(status)

  status.statusWindow.refresh

proc resize*(status: var EditorStatus, height, width: int) =

  let totalViewWidth = (proc (views: seq[EditorView]): int =
    result = 0
    for i in 0 ..< views.len:
      result = result + views[i].widthOfLineNum + 4
  )

  for i in 0 ..< status.mainWindow.len:
    let
      adjustedHeight = max(height, 4)
      adjustedWidth = max(int(width / status.view.len), totalViewWidth(status.view))
      useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
      useTab = if status.mode != Mode.filer and status.settings.tabLine.useTab: 1 else: 0

    resize(status.mainWindow[i], adjustedHeight - useStatusBar - useTab - 1, adjustedWidth, useTab, i * int(terminalWidth() / status.mainWindow.len))
    if status.settings.statusBar.useBar: resize(status.statusWindow, 1, terminalWidth(), adjustedHeight - 2, 0)
    if status.mode != Mode.filer and  status.settings.tabLine.useTab: resize(status.tabWindow, 1, terminalWidth(), 0, 0)
    
    if status.mode != Mode.filer:
      let widthOfLineNum = status.view[status.currentMainWindow].widthOfLineNum
      status.view[i].resize(status.buffer, adjustedHeight - useStatusBar - 1, adjustedWidth - widthOfLineNum - 1, widthOfLineNum)
      status.view[i].seekCursor(status.buffer, status.currentLine, status.currentColumn)

    if status.settings.statusBar.useBar: writeStatusBar(status)

    resize(status.commandWindow, 1, terminalWidth(), adjustedHeight - 1, 0)
  status.commandWindow.refresh

  if status.mode != Mode.filer and status.settings.tabLine.useTab: writeTabLine(status)

proc erase*(status: var EditorStatus) =
  erase(status.mainWindow[status.currentMainWindow])
  erase(status.statusWindow)
  erase(status.commandWindow)

proc update*(status: var EditorStatus) =
  setCursor(false)
  if status.settings.statusBar.useBar: writeStatusBar(status)

  for i in 0 ..< status.mainWindow.len:
    if i == status.currentMainWindow:
      status.view[status.currentMainWindow].seekCursor(status.buffer, status.currentLine, status.currentColumn)
      status.view[status.currentMainWindow].update(status.mainWindow[status.currentMainWindow], status.settings.lineNumber, status.buffer, status.highlight, status.settings.editorColor, status.currentLine)
      status.cursor.update(status.view[i], status.currentLine, status.currentColumn)
      status.mainWindow[i].write(status.cursor.y, status.view[i].widthOfLineNum + status.cursor.x, "")
      status.mainWindow[i].refresh
    else:
      status.view[i].seekCursor(status.bufStatus[i].buffer, status.bufStatus[i].currentLine, status.bufStatus[i].currentColumn)
      status.view[i].update(status.mainWindow[i], status.settings.lineNumber, status.bufStatus[i].buffer, status.bufStatus[i].highlight, status.settings.editorColor, status.bufStatus[i].currentLine)
      status.cursor.update(status.view[i], status.bufStatus[i].currentLine, status.bufStatus[i].currentColumn)
      status.mainWindow[i].write(status.bufStatus[i].cursor.y, status.view[i].widthOfLineNum + status.bufStatus[i].cursor.x, "")
      status.mainWindow[i].refresh
  setCursor(true)

proc update*(status: var EditorStatus, index: int) =
  setCursor(false)
  if status.settings.statusBar.useBar: writeStatusBar(status)
  status.view[index].seekCursor(status.bufStatus[index].buffer, status.bufStatus[index].currentLine, status.bufStatus[index].currentColumn)
  status.view[index].update(status.mainWindow[index], status.settings.lineNumber, status.bufStatus[index].buffer, status.bufStatus[index].highlight, status.settings.editorColor, status.bufStatus[index].currentLine)
  status.cursor.update(status.view[index], status.bufStatus[index].currentLine, status.bufStatus[index].currentColumn)
  status.mainWindow[index].write(status.bufStatus[index].cursor.y, status.view[index].widthOfLineNum + status.bufStatus[index].cursor.x, "")
  status.mainWindow[index].refresh
  setCursor(true)

proc clearWin*(status: var EditorStatus) =
  for i in 0 ..< status.mainWindow.len:
    status.mainWindow[i].erase

proc updateHighlight*(status: var EditorStatus)

from searchmode import searchAllOccurrence

proc updateHighlight*(status: var EditorStatus) =

  status.highlight = initHighlight($status.buffer, if status.settings.syntax: status.language else: SourceLanguage.langNone, status.settings.editorColor.editor)

  # highlight search results
  if status.isHighlight and status.searchHistory.len > 0:
    let keyword = status.searchHistory[^1]
    let allOccurrence = searchAllOccurrence(status.buffer, keyword)
    for pos in allOccurrence:
      let colorSegment = ColorSegment(firstRow: pos.line, firstColumn: pos.column, lastRow: pos.line, lastColumn: pos.column+keyword.high, color: defaultMagenta)
      status.highlight = status.highlight.overwrite(colorSegment)

proc moveWin*(status: var EditorStatus) = status.currentMainWindow = if status.currentMainWindow == 0: 1 else: 0

proc splitWin*(status: var EditorStatus) =
  let
    numberOfDigitsLen = if status.settings.lineNumber: numberOfDigits(status.bufStatus[0].buffer.len) - 2 else: 0
    useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    useTab = if status.mode != Mode.filer and status.settings.tabLine.useTab: 1 else: 0

  status.bufStatus.add(BufferStatus(filename: ru""))
  status.bufStatus[status.bufStatus.high].language = detectLanguage("")
  status.bufStatus[status.bufStatus.high].buffer = newFile()

  status.view.add(initEditorView(status.bufStatus[status.bufStatus.high].buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numberOfDigitsLen))
  status.mainWindow.add(initWindow(terminalHeight() - useTab - 1, int(terminalWidth() / status.mainWindow.len), useTab, int(terminalWidth() / status.mainWindow.len)))

  status.update
