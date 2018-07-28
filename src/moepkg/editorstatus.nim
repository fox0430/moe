import terminal, os, strformat
import gapbuffer, editorview, ui, cursor, unicodeext

type Mode* = enum
  normal, insert, ex, filer, quit

type Registers* = object
  yankedLines*:   seq[seq[Rune]]
  yankedStr*:    string

type EditorSettings = object
  autoCloseParen*: bool
  autoIndent*:     bool 
  tabStop*:        int

type EditorStatus* = object
  buffer*: GapBuffer[seq[Rune]]
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
  result.yankedStr = "" 

proc initEditorSettings(): EditorSettings =
  result.autoCloseParen = true
  result.autoIndent = true
  result.tabStop = 2

proc initEditorStatus*(): EditorStatus =
  result.filename = nil
  result.currentDir = getCurrentDir().toRunes
  result.registers = initRegisters()
  result.settings = initEditorSettings()
  result.mode = Mode.normal
  result.prevMode= Mode.normal

  result.mainWindow = initWindow(terminalHeight()-2, terminalWidth(), 0, 0)
  result.statusWindow = initWindow(1, terminalWidth(), terminalHeight()-2, 0, ui.ColorPair.blackGreen)
  result.commandWindow = initWindow(1, terminalWidth(), terminalHeight()-1, 0)

proc writeStatusBar*(status: var EditorStatus) =
  status.statusWindow.erase

  if status.mode == Mode.filer:
    status.statusWindow.write(0, 0, u8" FILER ", ui.ColorPair.blackWhite)
    status.statusWindow.append(u8" ", ui.ColorPair.blackGreen)
    status.statusWindow.append(getCurrentDir().toRunes, ui.ColorPair.blackGreen)
    status.statusWindow.refresh
    return

  status.statusWindow.write(0, 0,  if status.mode == Mode.normal: u8" NORMAL " else: u8" INSERT ", ui.ColorPair.blackWhite)
  status.statusWindow.append(u8" ", ui.ColorPair.blackGreen)
  if status.filename != nil and status.filename[0..1] == u8"./":
    status.statusWindow.append(status.filename[2..status.filename.len], ui.ColorPair.blackGreen)
  else:
    status.statusWindow.append(if status.filename != nil: status.filename else: u8"No name", ui.ColorPair.blackGreen)
  if status.countChange > 0:  status.statusWindow.append(u8" [+]", ui.ColorPair.blackGreen)

  status.statusWindow.write(0, terminalWidth()-20, toRunes(fmt"{status.currentLine+1}/{status.buffer.len}"), ui.Colorpair.blackGreen)
  status.statusWindow.append(toRunes(fmt" {status.currentColumn}/{status.buffer[status.currentLine].len}"), ui.ColorPair.blackGreen)
  status.statusWindow.refresh

proc resize*(status: var EditorStatus) =
  resize(status.mainWindow, terminalHeight()-2, terminalWidth(), 0, 0)
  resize(status.statusWindow, 1, terminalWidth(), terminalHeight()-2, 0)
  resize(status.commandWindow, 1, terminalWidth(), terminalHeight()-1, 0)
  
  if status.mode != Mode.filer:
    status.view.resize(status.buffer, terminalHeight()-2, terminalWidth()-status.view.widthOfLineNum-1, status.view.widthOfLineNum)
    status.view.seekCursor(status.buffer, status.currentLine, status.currentColumn)

  writeStatusBar(status)

