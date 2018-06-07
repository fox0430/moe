import gapbuffer

type EditorView* = object
  widthOfLineNum: int
  height:         int
  width:          int
  updated:       bool

proc initEditorView(): EditorView = return result
