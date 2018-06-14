import terminal, os
import ncurses
import gapbuffer, editorview, ui, cursor

type Mode* = enum
  normal, insert, filer

type Registers* = object
  yankedLine*:   GapBuffer[string]
  yankedStr*:    string

type EditorSettings = object
  autoCloseParen: bool
  autoIndent:     bool 
  tabStop:        int

type EditorStatus* = object
  buffer*: GapBuffer[string]
  view*: EditorView
  cursor*: CursorPosition
  registers: Registers
  settings: EditorSettings
  filename*: string
  currentDir: string
  currentLine*: int
  currentColumn*: int
  expandedColumn*: int
  mode* : Mode
  cmdLoop*: int
  numOfChange: int
  debugMode: int
  mainWindow*: Window
  statusWindow*: Window
  commandWindow*: Window

proc initRegisters(): Registers =
  result.yankedLine = initGapBuffer[string]()
  result.yankedStr = "" 

proc initEditorSettings(): EditorSettings = discard

proc initEditorStatus*(): EditorStatus =
  result.filename = "No name"
  result.currentDir = getCurrentDir()
  result.registers = initRegisters()
  result.settings = initEditorSettings()
  result.mode = Mode.normal

  result.mainWindow = initWindow(terminalHeight()-2, terminalWidth(), 0, 0)
  result.statusWindow = initWindow(1, terminalWidth(), terminalHeight()-2, 0)
  result.commandWindow = initWindow(1, terminalWidth(), terminalHeight()-1, 0)

  discard keypad(result.mainWindow.cursesWindow, true)
  discard keypad(result.statusWindow.cursesWindow, true)
  discard keypad(result.commandWindow.cursesWindow, true)
