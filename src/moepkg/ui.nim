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
  cursesWindow: ptr window
  top, left, height, width: int

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

proc exitUi*() =
  endwin()

proc initWindow*(height, width, top, left: int ): Window =
  result.top = top
  result.left = left
  result.height = height
  result.width = width
  result.cursesWindow = newwin(height, width, top, left)

proc write*(win: Window, y, x: int, str: string, color: ColorPair = ColorPair.brightWhiteDefault) =
  wattron(win.cursesWindow, cshort(ord(color)))
  mvwprintw(win.cursesWindow, y, x, str)
  
proc erase*(win: Window) =
  werase(win.cursesWindow)

proc refresh*(win: Window) =
  wrefresh(win.cursesWindow)

proc resize*(win: Window, height, width: int) =
  wresize(win.cursesWindow, height, width)
