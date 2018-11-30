import terminal, os, strformat
import gapbuffer, editorview, ui, cursor, unicodeext

type Mode* = enum
  normal, insert, ex, filer, search, quit

type Registers* = object
  yankedLines*: seq[seq[Rune]]
  yankedStr*: seq[Rune]

type EditorSettings* = object
  autoCloseParen*: bool
  autoIndent*: bool 
  tabStop*: int
  characterEncoding*: CharacterEncoding # TODO: move to EditorStatus ...?

type EditorStatus* = object
  buffer*: GapBuffer[seq[Rune]]
  searchHistory*: seq[seq[Rune]]
  view*: EditorView
  cursor*: CursorPosition
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
  mainWindow*: Window
  statusWindow*: Window
  commandWindow*: Window

proc initRegisters(): Registers =
  result.yankedLines = @[]
  result.yankedStr = @[]

proc initEditorSettings*(): EditorSettings =
  result.autoCloseParen = true
  result.autoIndent = true
  result.tabStop = 2

proc initEditorStatus*(): EditorStatus =
  result.currentDir = getCurrentDir().toRunes
  result.registers = initRegisters()
  result.settings = initEditorSettings()
  result.mode = Mode.normal
  result.prevMode = Mode.normal

  result.mainWindow = initWindow(terminalHeight()-2, terminalWidth(), 0, 0)
  result.statusWindow = initWindow(1, terminalWidth(), terminalHeight()-2, 0, ui.ColorPair.blackGreen)
  result.commandWindow = initWindow(1, terminalWidth(), terminalHeight()-1, 0)

proc writeStatusBar*(status: var EditorStatus) =
  status.statusWindow.erase

  if status.mode == Mode.filer:
    status.statusWindow.write(0, 0, ru" FILER ", ui.ColorPair.blackWhite)
    status.statusWindow.append(ru" ", ui.ColorPair.blackGreen)
    status.statusWindow.append(getCurrentDir().toRunes, ui.ColorPair.blackGreen)
    status.statusWindow.refresh
    return

  status.statusWindow.write(0, 0,  if status.mode == Mode.normal: ru" NORMAL " else: ru" INSERT ", ui.ColorPair.blackWhite)
  status.statusWindow.append(ru" ", ui.ColorPair.blackGreen)
  status.statusWindow.append(if status.filename.len > 0: status.filename else: ru"No name", ui.ColorPair.blackGreen)
  if status.countChange > 0:  status.statusWindow.append(ru" [+]", ui.ColorPair.blackGreen)

  let
    line = fmt"{status.currentLine+1}/{status.buffer.len}"
    column = fmt"{status.currentColumn}/{status.buffer[status.currentLine].len}"
    encoding = $status.settings.characterEncoding
    info = fmt"{line} {column} {encoding} "
  status.statusWindow.write(0, terminalWidth()-info.len, info, ui.Colorpair.blackGreen)
  status.statusWindow.refresh

proc resize*(status: var EditorStatus, height, width: int) =
  let
    adjustedHeight = max(height, 4)
    adjustedWidth = max(width, status.view.widthOfLineNum+4)
 
  resize(status.mainWindow, adjustedHeight-2, adjustedWidth, 0, 0)
  resize(status.statusWindow, 1, adjustedWidth, adjustedHeight-2, 0)
  resize(status.commandWindow, 1, adjustedWidth, adjustedHeight-1, 0)
  
  if status.mode != Mode.filer:
    status.view.resize(status.buffer, adjustedHeight-2, adjustedWidth-status.view.widthOfLineNum-1, status.view.widthOfLineNum)
    status.view.seekCursor(status.buffer, status.currentLine, status.currentColumn)

  writeStatusBar(status)

proc erase*(status: var EditorStatus) =
  erase(status.mainWindow)
  erase(status.statusWindow)
  erase(status.commandWindow)

proc update*(status: var EditorStatus) =
  setCursor(false)
  writeStatusBar(status)
  status.view.seekCursor(status.buffer, status.currentLine, status.currentColumn)
  status.view.update(status.mainWindow, status.buffer, status.currentLine)
  status.cursor.update(status.view, status.currentLine, status.currentColumn)
  status.mainWindow.write(status.cursor.y, status.view.widthOfLineNum+status.cursor.x, "")
  status.mainWindow.refresh
  setCursor(true)

proc changeMode*(status: var EditorStatus, mode: Mode) =
  status.prevMode = status.mode
  status.mode = mode
