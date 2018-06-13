import terminal
import os
import gapbuffer
import editorview

type Registers* = object
  yankedLine*:   GapBuffer[string]
  yankedStr*:    string

type EditorSettings = object
  autoCloseParen: bool
  autoIndent:     bool 
  tabStop:        int

type EditorStatus* = object
  buffer*: GapBuffer[string]
  view:                   EditorView
  settings:                EditorSettings
  filename*:               string
  currentDir:             string
  currentLine:            int
  currentColumn:          int
  expandedColumn:        int
  mode:                   int
  cmdLoop:                int
  numOfChange:            int
  debugMode:              int

proc registersInit(): Registers =
  result.yankedLine = initGapBuffer[string]()
  result.yankedStr  = "" 

proc initEditorSettings(): EditorSettings = discard

proc initEditorStatus*(): EditorStatus =
  result.filename   = "No name"
  result.currentDir = getCurrentDir()
