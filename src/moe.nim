import posix
import os
import system
import terminal
import moepkg/ui
import moepkg/editorview
import moepkg/gapbuffer

type EditorSettings = object
  autoCloseParen: bool
  autoIndent:     bool 
  tabStop:        int

type EditorStatus = object
  view:                   EditorView
  setting:                EditorSettings
  filename:               string
  currentDir:             string
  termHeight:             int
  termWidth:              int
  currentLine:            int
  currentColumn:          int
  expandePosition:        int
  mode:                   int
  cmdLoop:                int
  numOfChange:            int
  debugMode:              int

proc initEditorSettings(): EditorSettings = discard

proc initEditorStatus(): EditorStatus =
  result.termHeight = terminalHeight()
  result.termWidth = terminalWidth()
  result.filename = "No name"
  result.currentDir = getCurrentDir()
  result.setting = initEditorSettings()

if isMainModule:
  var status = initEditorStatus()
  var gb = initGapBuffer[string]()

  startUi()
  exitUi()

  if paramCount() == 0:
    quit()
  else:
    status.filename = os.commandLineParams()[0]
    quit()
