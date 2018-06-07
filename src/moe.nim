import ncurses
import posix
import os
import system

type editorStatus = object
  filename:               string
  currentDir:             string
  positionInCurrentLine:  int
  expandePosition:        int
  mode:                   int
  cmdLoop:                int
  numOfChange:            int
  debugMode:              int

if isMainModule:
  var status = editorStatus()
  if paramCount() == 0:
    quit()
  else:
    status.filename = (string)os.commandLineParams()[0]
    quit()
