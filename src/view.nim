import ncurses
import terminal

type EditorView = object
  widthOfLineNum: int
  height:         int
  width:          int
  isUpdate:       bool

proc initEditorView(): EditorView =
  result.height = terminalHeight()
  result.width = terminalWidth()
