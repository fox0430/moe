import ncurses
import posix
import system
import os

type editorStatus = object
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
  discard setLocale(LC_ALL, "")
  initscr()
  cbreak()
  curs_set(1)

proc exitCurses() =
  endwin()
  quit()
  
if isMainModule:
  startCurses()
