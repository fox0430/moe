import ncurses
import posix
import os
import system
import moepkg/view

type Color = enum
  default     = -1,
  black       = 0,
  red         = 1,
  green       = 2,
  yellow      = 3,
  blue        = 4,
  magenta     = 5,
  cyan        = 6,
  white       = 7,
  lightBlue   = 14
  brightGreen = 85,
  brightWhite = 231,
  gray        = 245,

type EditorSettings = object
  autoCloseParen: bool
  autoIndent:     bool 
  tabStop:        int

type EditorStatus = object
  view:                   EditorView
  setting:                EditorSettings
  filename:               string
  currentDir:             string
  currentLine:            int
  currentColumn:          int
  expandePosition:        int
  mode:                   int
  cmdLoop:                int
  numOfChange:            int
  debugMode:              int

proc setCursesColor() =
  start_color()   # enable color
  use_default_colors()    # set terminal default color

  init_pair(1, ord(Color.black) , ord(Color.green))   # char is black, bg is green
  init_pair(2, ord(Color.black), ord(Color.brightWhite))
  init_pair(3, ord(Color.gray), ord(Color.default))
  init_pair(4, ord(Color.red), ord(Color.default))
  init_pair(5, ord(Color.green), ord(Color.black))
  init_pair(6, ord(Color.brightWhite), ord(Color.default))
  init_pair(7, ord(Color.brightGreen), ord(Color.default))
  init_pair(8, ord(Color.lightBlue), ord(Color.default))

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

proc initEditorSettings(): EditorSettings = discard

proc initEditorStatus(): EditorStatus =
  result.filename = "No name"
  result.currentDir = getCurrentDir()
  result.setting = initEditorSettings()

if isMainModule:
  var status = initEditorStatus()

  echo status
  echo status.setting
  if paramCount() == 0:
    quit()
  else:
    status.filename = os.commandLineParams()[0]
    quit()
