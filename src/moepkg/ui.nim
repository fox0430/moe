import posix, strformat
from os import execShellCmd
import ncurses
import unicodeext


type CursorType* = enum
  blockMode = 0
  ibeamMode = 1

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
  brightWhiteGreen = 9
  cyanDefault = 10
  whiteCyan = 11
  magentaDefault =12
  whiteDefault = 13

type Window* = object
  cursesWindow*: ptr window
  top, left, height*, width*: int
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
  setColorPair(ColorPair.brightWhiteGreen, Color.brightWhite, Color.green)
  setColorPair(ColorPair.cyanDefault, Color.cyan, Color.default)
  setColorPair(ColorPair.whiteCyan, Color.white, Color.cyan)
  setColorPair(ColorPair.magentaDefault, Color.magenta, Color.default)
  setColorPair(ColorPair.whiteDefault, Color.white, Color.default)

proc setIbeamCursor*() =
  discard execShellCmd("printf '\\033[6 q'")

proc setBlockCursor*() =
  discard execShellCmd("printf '\e[0 q'")

proc changeCursorType*(cursorType: CursorType) =
  case cursorType
  of blockMode: setBlockCursor()
  of ibeamMode: setIbeamCursor()

proc disableControlC() =
  setControlCHook(proc() {.noconv.} = discard)

proc restoreTerminalModes*() =
  reset_prog_mode()

proc saveCurrentTerminalModes*() =
  def_prog_mode()

proc setCursor*(cursor: bool) =
  if cursor == true:
    curs_set(1)   # enable cursor
  elif cursor == false:
    curs_set(0)   # disable cursor

proc keyEcho*(keyecho: bool) =
  if keyecho == true:
    echo()
  elif keyecho == false:
    noecho()
    
proc startUi*() =
  disableControlC()
  discard setLocale(LC_ALL, "")   # enable UTF-8
  initscr()   # start terminal control
  cbreak()    # enable cbreak mode
  setCursor(true)

  if can_change_color(): setCursesColor()

  erase()
  keyEcho(false)
  set_escdelay(25)

proc exitUi*() =
  endwin()

proc initWindow*(height, width, top, left: int, color: ColorPair = ColorPair.brightWhiteDefault): Window =
  result.top = top
  result.left = left
  result.height = height
  result.width = width
  result.cursesWindow = newwin(height, width, top, left)
  keypad(result.cursesWindow, true)
  discard wbkgd(result.cursesWindow, ncurses.COLOR_PAIR(color))

proc write*(win: var Window, y, x: int, str: string, color: ColorPair = ColorPair.brightWhiteDefault, storeX: bool = true) =
  win.cursesWindow.wattron(int(ncurses.COLOR_PAIR(ord(color))))
  mvwaddstr(win.cursesWindow, y, x, str)
  if storeX:
    win.y = y
    win.x = x+str.toRunes.width

proc write*(win: var Window, y, x: int, str: seq[Rune], color: ColorPair = ColorPair.brightWhiteDefault, storeX: bool = true) =
  write(win, y, x, $str, color, false)
  if storeX:
    win.y = y
    win.x = x+str.width

proc append*(win: var Window, str: string, color: ColorPair = ColorPair.brightWhiteDefault) =
  win.cursesWindow.wattron(int(ncurses.COLOR_PAIR(ord(color))))
  mvwaddstr(win.cursesWindow, win.y, win.x, $str)
  win.x += str.toRunes.width

proc append*(win: var Window, str: seq[Rune], color: ColorPair = ColorPair.brightWhiteDefault) = append(win, $str, color)
  
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

proc getKey*(win: Window): Rune =
  var
    s = ""
    len: int
  block getfirst:
    let key = wgetch(win.cursesWindow)
    if not (key <= 0x7F or (0xC2 <= key and key <= 0xF0) or key == 0xF3): return Rune(key)
    s.add(char(key))
    len = numberOfBytes(char(key))
  for i in 0 ..< len-1: s.add(char(wgetch(win.cursesWindow)))
  
  let runes = toRunes(s)
  doAssert(runes.len == 1, fmt"runes length shoud be 1.")
  return runes[0]

proc isEscKey*(key: Rune): bool = key == KEY_ESC
proc isResizeKey*(key: Rune): bool = key == KEY_RESIZE
proc isDownKey*(key: Rune): bool = key == KEY_DOWN
proc isUpKey*(key: Rune): bool = key == KEY_UP
proc isLeftKey*(key: Rune): bool = key == KEY_LEFT
proc isRightKey*(key: Rune): bool = key == KEY_RIGHT
proc isHomeKey*(key: Rune): bool = key == KEY_HOME
proc isEndKey*(key: Rune): bool = key == KEY_END
proc isBackspaceKey*(key: Rune): bool = key == KEY_BACKSPACE or key == 8 or key == 127
proc isDcKey*(key: Rune): bool = key == KEY_DC
proc isEnterKey*(key: Rune): bool = key == KEY_ENTER or key == ord('\n')
proc isPageUpKey*(key: Rune): bool = key == KEY_PPAGE or key == 2
proc isPageDownkey*(key: Rune): bool = key == KEY_NPAGE or key == 6
