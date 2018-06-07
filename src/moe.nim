import ncurses
import posix
import os
import system

type EditorStatus = object
  filename:               string
  currentDir:             string
  currentLine:            int
  positionInCurrentLine:  int
  expandePosition:        int
  mode:                   int
  cmdLoop:                int
  numOfChange:            int
  debugMode:              int

proc startCurses() =
  initscr()

proc exitCurses() =
  endwin()

proc EditorStatusInit(status: var EditorStatus) =
  status.currentLine = 0
  status.positionInCurrentLine = 0
  status.expandePosition = 0
  status.mode = 0
  status.cmdLoop = 0
  status.filename = "No name"
  status.numOfChange = 0
  status.debugMode = 0

if isMainModule:
  var status = EditorStatus()
  EditorStatusInit(status)
  if paramCount() == 0:
    quit()
  else:
    status.filename = os.commandLineParams()[0]
    quit()
