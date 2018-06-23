import ncurses
import posix

type Color* = enum
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

type ColorPair* = enum
  blackGreen = 1
  blackWhite = 2
  grayDefault = 3
  redDefault = 4
  greenBlack  = 5
  brightWhiteDefault = 6
  brightGreenDefault = 7
  lightBlueDefault = 8

type Window* = object
  cursesWindow*: ptr window
  top, left, height, width: int
  y*, x*: int

proc setColorPair(colorPair: ColorPair, character, background: Color) =
  init_pair(cshort(ord(colorPair)), cshort(ord(character)), cshort(ord(background)))

proc setCursesColor() =
  start_color()   # enable color
  use_default_colors()    # set terminal default color

  setColorPair(ColorPair.blackGreen, Color.black, Color.green)
  setColorPair(ColorPair.blackWhite, Color.black, Color.brightWhite)
  setColorPair(ColorPair.grayDefault, Color.gray, Color.default)
  setColorPair(ColorPair.redDefault, Color.red, Color.default)
  setColorPair(ColorPair.greenBlack, Color.green, Color.black)
  setColorPair(ColorPair.brightWhiteDefault, Color.brightWhite, Color.default)
  setColorPair(ColorPair.brightGreenDefault, Color.brightGreen, Color.default)
  setColorPair(ColorPair.lightBlueDefault, Color.lightBlue, Color.default)

proc startUi*() =
  discard setLocale(LC_ALL, "")   # enable UTF-8
  initscr()   # start terminal control
  cbreak()    # enable cbreak mode
  curs_set(1) # set cursor

  if can_change_color(): setCursesColor()

  erase()
  noecho()

proc exitUi*() =
  endwin()

proc initWindow*(height, width, top, left: int ): Window =
  result.top = top
  result.left = left
  result.height = height
  result.width = width
  result.cursesWindow = newwin(height, width, top, left)
  discard keypad(result.cursesWindow, true)

proc write*(win: var Window, y, x: int, str: string, color: ColorPair = ColorPair.brightWhiteDefault) =
  wattron(win.cursesWindow, cshort(ord(color)))
  mvwprintw(win.cursesWindow, y, x, str)
  win.y = y
  win.x = str.len

proc append*(win: var Window, str: string, color: ColorPair = ColorPair.brightWhiteDefault) =
  wattron(win.cursesWindow, cshort(ord(color)))
  mvwprintw(win.cursesWindow, win.y, win.x, str)
  win.x += str.len
  
proc erase*(win: var Window) =
  werase(win.cursesWindow)
  win.y = 0
  win.x = 0

proc refresh*(win: Window) =
  wrefresh(win.cursesWindow)

proc move*(win: Window, y, x: int) =
  mvwin(win.cursesWindow, y, x)

proc resize*(win: Window, height, width: int) =
  wresize(win.cursesWindow, height, width)

proc resize*(win: Window, height, width, y, x: int) =
  win.resize(height, width)
  win.move(y, x)

let KEY_ESC = 27
var KEY_RESIZE {.header: "<ncurses.h>", importc: "KEY_RESIZE".}: int
var KEY_DOWN {.header: "<ncurses.h>", importc: "KEY_DOWN".}: int
var KEY_UP {.header: "<ncurses.h>", importc: "KEY_UP".}: int
var KEY_LEFT {.header: "<ncurses.h>", importc: "KEY_LEFT".}: int
var KEY_RIGHT {.header: "<ncurses.h>", importc: "KEY_RIGHT".}: int
var KEY_HOME {.header: "<ncurses.h>", importc: "KEY_HOME".}: int
var KEY_END {.header: "<ncurses.h>", importc: "KEY_END".}: int
var KEY_BACKSPACE {.header: "<ncurses.h>", importc: "KEY_BACKSPACE".}: int
var KEY_DC {.header: "<ncurses.h>", importc: "KEY_DC".}: int
var KEY_ENTER {.header: "<ncurses.h>", importc: "KEY_ENTER".}: int
var KEY_PPAGE {.header: "<ncurses.h>", importc: "KEY_PPAGE".}: int
var KEY_NPAGE {.header: "<ncurses.h>", importc: "KEY_NPAGE".}: int

proc getKey*(win: Window): int = return wgetch(win.cursesWindow)

proc isEscKey*(key: int): bool = key == KEY_ESC
proc isResizeKey*(key: int): bool = key == KEY_RESIZE
proc isDownKey*(key: int): bool = key == KEY_DOWN
proc isUpKey*(key: int): bool = key == KEY_UP
proc isLeftKey*(key: int): bool = key == KEY_LEFT
proc isRightKey*(key: int): bool = key == KEY_RIGHT
proc isHomeKey*(key: int): bool = key == KEY_HOME
proc isEndKey*(key: int): bool = key == KEY_END
proc isBackspaceKey*(key: int): bool = key == KEY_BACKSPACE or key == 8 or key == 127
proc isDcKey*(key: int): bool = key == KEY_DC
proc isEnterKey*(key: int): bool = key == KEY_ENTER or key == ord('\n')
proc isPageUpKey*(key: int): bool = key == KEY_PPAGE or key == 2
proc isPageDownkey*(key: int): bool = key == KEY_NPAGE or key == 6
