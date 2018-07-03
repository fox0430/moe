import terminal, os, strformat
import gapbuffer, editorview, ui, cursor

type Mode* = enum
  normal, insert, ex, filer, quit

type Registers* = object
  yankedLines*:   seq[string]
  yankedStr*:    string

type EditorSettings = object
  autoCloseParen*: bool
  autoIndent*:     bool 
  tabStop*:        int

type EditorStatus* = object
  buffer*: GapBuffer[string]
  view*: EditorView
  cursor*: CursorPosition
  registers*: Registers
  settings*: EditorSettings
  filename*: string
  openDir: string
  currentDir: string
  currentLine*: int
  currentColumn*: int
  expandedColumn*: int
  mode* : Mode
  cmdLoop*: int
  countChange*: int
  debugMode: int
  mainWindow*: Window
  statusWindow*: Window
  commandWindow*: Window

proc initRegisters(): Registers =
  result.yankedLines = @[]
  result.yankedStr = "" 

proc initEditorSettings(): EditorSettings =
  result.autoCloseParen = true
  result.autoIndent = true
  result.tabStop = 2

proc initEditorStatus*(): EditorStatus =
  result.filename = "No name"
  result.currentDir = getCurrentDir()
  result.registers = initRegisters()
  result.settings = initEditorSettings()
  result.mode = Mode.normal

  result.mainWindow = initWindow(terminalHeight()-2, terminalWidth(), 0, 0)
  result.statusWindow = initWindow(1, terminalWidth(), terminalHeight()-2, 0, ui.ColorPair.blackGreen)
  result.commandWindow = initWindow(1, terminalWidth(), terminalHeight()-1, 0)

proc writeStatusBar*(status: var EditorStatus) =
  status.statusWindow.erase

  if status.mode == Mode.filer:
    status.statusWindow.write(0, 0, " FILER ", ui.ColorPair.blackWhite)
    status.statusWindow.refresh
    return

  status.statusWindow.write(0, 0,  if status.mode == Mode.normal: " NORMAL " else: " INSERT ", ui.ColorPair.blackWhite)
  status.statusWindow.append(status.filename, ui.ColorPair.blackGreen)
  if status.filename == "No name":  status.statusWindow.append(" [+]", ui.ColorPair.blackGreen)

  status.statusWindow.write(0, terminalWidth()-13, fmt"{status.currentLine+1}/{status.buffer.len}", ui.Colorpair.blackGreen)
  status.statusWindow.write(0, terminalWidth()-6, fmt"{status.currentColumn}/{status.buffer[status.currentLine].len}", ui.ColorPair.blackGreen)
  status.statusWindow.refresh

proc resize*(status: var EditorStatus) =
  resize(status.mainWindow, terminalHeight()-2, terminalWidth(), 0, 0)
  resize(status.statusWindow, 1, terminalWidth(), terminalHeight()-2, 0)
  resize(status.commandWindow, 1, terminalWidth(), terminalHeight()-1, 0)
  
  if status.mode != Mode.filer:
    status.view.resize(status.buffer, terminalHeight()-2, terminalWidth()-status.view.widthOfLineNum-1, status.view.widthOfLineNum)
    status.view.seekCursor(status.buffer, status.currentLine, status.currentColumn)

  writeStatusBar(status)

