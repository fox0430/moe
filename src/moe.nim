import ncurses
import posix
import os
import system

const COLOR_DEFAULT: int16 = -1   # default terminal color
const BRIGHT_WHITE: int16 = 231
const BRIGHT_GREEN: int16 = 85
const GRAY: int16 = 245
const LIGHT_BLUE: int16 = 14

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

proc setCursesColor() =
  start_color()   # enable color
  use_default_colors()    # set terminal default color

  init_pair(1, COLOR_BLACK , COLOR_GREEN)   # char is black, bg is green
  init_pair(2, COLOR_BLACK, BRIGHT_WHITE)
  init_pair(3, GRAY, COLOR_DEFAULT)
  init_pair(4, COLOR_RED, COLOR_DEFAULT)
  init_pair(5, COLOR_GREEN, COLOR_BLACK)
  init_pair(6, BRIGHT_WHITE, COLOR_DEFAULT)
  init_pair(7, BRIGHT_GREEN, COLOR_DEFAULT)
  init_pair(8, LIGHT_BLUE, COLOR_DEFAULT)

proc startCurses() =
  discard setLocale(LC_ALL, "")   # enable UTF-8
  initscr()   # start terminal control
  cbreak()    # enable cbreak mode
  curs_set(1) # set cursor

  var color_check: bool = can_change_color()
  if color_check != true:
    setCursesColor()

  erase()

proc exitCurses() =
  endwin()

proc EditorStatusInit(): EditorStatus =
  result.filename = "No name"
  result.currentDir = getCurrentDir()
  result.currentLine = 0
  result.positionInCurrentLine = 0
  result.expandePosition = 0
  result.mode = 0
  result.cmdLoop = 0
  result.filename = "No name"
  result.numOfChange = 0
  result.debugMode = 0

if isMainModule:
  var status = EditorStatus()
  status = EditorStatusInit()
  echo status
  if paramCount() == 0:
    quit()
  else:
    status.filename = os.commandLineParams()[0]
    quit()
