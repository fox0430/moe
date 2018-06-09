import view
import terminal
import os
import gapbuffer

type Registers* = object
  yankedLine*:   GapBuffer[string]
  yankedStr*:    string

type EditorSettings = object
  autoCloseParen: bool
  autoIndent:     bool 
  tabStop:        int

type EditorStatus* = object
  view*:                   EditorView
  setting:                 EditorSettings
  filename*:               string
  currentDir*:             string
  termHeight*:             int
  termWidth*:              int
  currentLine*:            int
  currentColumn*:          int
  expandePosition*:        int
  mode*:                   int
  cmdLoop*:                int
  numOfChange*:            int
  debugMode*:              int

proc registersInit(): Registers =
  result.yankedLine = initGapBuffer[string]()
  result.yankedStr  = "" 

proc initEditorSettings(): EditorSettings = discard

proc initEditorStatus*(): EditorStatus =
  result.termHeight = terminalHeight()
  result.termWidth  = terminalWidth()
  result.filename   = "No name"
  result.currentDir = getCurrentDir()
  result.setting    = initEditorSettings()
