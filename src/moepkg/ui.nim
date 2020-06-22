import posix, strformat
from os import execShellCmd
import ncurses
import unicodeext, color

type Attributes* = enum
  normal = A_NORMAL
  standout = A_STANDOUT
  underline = A_UNDERLINE
  reverse = A_REVERSE
  blink = A_BLINK
  dim = A_DIM
  bold = A_BOLD
  altcharet = A_ALT_CHARSET
  invis = A_INVIS
  protect = A_PROTECT
  #chartext = A_CHAR_TEXT

type CursorType* = enum
  blinkBlockMode = 0
  noneBlinkBlockMode = 1
  blinkIbeamMode = 2
  noneBlinkIbeamMode = 3

type Window* = ref object
  cursesWindow*: ptr window
  top, left, height*, width*: int
  y*, x*: int

proc setBkinkingIbeamCursor*() = discard execShellCmd("printf \"\x1b[\x35 q\"")

proc setNoneBlinkingIbeamCursor*() = discard execShellCmd("printf '\\033[6 q'")

proc setBlinkingBlockCursor*() = discard execShellCmd("printf '\e[0 q'")

proc setNoneBlinkingBlockCursor*() = discard execShellCmd("printf '\x1b[\x32 q'")

proc changeCursorType*(cursorType: CursorType) =
  case cursorType
  of blinkBlockMode: setBlinkingBlockCursor()
  of noneBlinkBlockMode: setNoneBlinkingBlockCursor()
  of blinkIbeamMode: setBkinkingIbeamCursor()
  of noneBlinkIbeamMode: setNoneBlinkingIbeamCursor()

proc disableControlC*() = setControlCHook(proc() {.noconv.} = discard)

proc restoreTerminalModes*() = reset_prog_mode()

proc saveCurrentTerminalModes*() = def_prog_mode()

proc setCursor*(cursor: bool) =
  if cursor == true: curs_set(1)      ## enable cursor
  elif cursor == false: curs_set(0)   ## disable cursor

proc keyEcho*(keyecho: bool) =
  if keyecho == true: echo()
  elif keyecho == false: noecho()

proc setTimeout*(win: var Window) = win.cursesWindow.wtimeout(cint(1000)) # 500mm sec

proc setTimeout*(win: var Window, time: int) = win.cursesWindow.wtimeout(cint(time))

proc startUi*() =
  discard setLocale(LC_ALL, "")   # enable UTF-8
  initscr()   ## start terminal control
  cbreak()    ## enable cbreak mode
  nonl();     ## exit new line mode and improve move cursor performance
  setCursor(true)

  if can_change_color():
    ## default is vivid
    setCursesColor(ColorThemeTable[ColorTheme.vivid])

  erase()
  keyEcho(false)
  set_escdelay(25)

proc exitUi*() = endwin()

proc initWindow*(height, width, top, left: int, color: EditorColorPair): Window =
  result = Window()
  result.top = top
  result.left = left
  result.height = height
  result.width = width
  result.cursesWindow = newwin(cint(height), cint(width), cint(top), cint(left))
  keypad(result.cursesWindow, true)
  discard wbkgd(result.cursesWindow, ncurses.COLOR_PAIR(color))

proc write*(win: var Window,
            y, x: int,
            str: string,
            color: EditorColorPair = EditorColorPair.defaultChar,
            storeX: bool = true) =
  
  win.cursesWindow.wattron(cint(ncurses.COLOR_PAIR(ord(color))))
  mvwaddstr(win.cursesWindow, cint(y), cint(x), str)
  if storeX:
    win.y = y
    win.x = x+str.toRunes.width

proc write*(win: var Window,
            y, x: int, str: seq[Rune],
            color: EditorColorPair = EditorColorPair.defaultChar,
            storeX: bool = true) =
  
  write(win, y, x, $str, color, false)
  if storeX:
    win.y = y
    win.x = x+str.width

proc append*(win: var Window,
              str: string,
              color: EditorColorPair = EditorColorPair.defaultChar) =
  
  win.cursesWindow.wattron(cint(ncurses.COLOR_PAIR(ord(color))))
  mvwaddstr(win.cursesWindow, cint(win.y), cint(win.x), $str)
  win.x += str.toRunes.width

proc append*(win: var Window,
            str: seq[Rune],
            color: EditorColorPair = EditorColorPair.defaultChar) =
  
  append(win, $str, color)

proc erase*(win: var Window) =
  werase(win.cursesWindow)
  win.y = 0
  win.x = 0

proc refresh*(win: Window) = wrefresh(win.cursesWindow)

proc move*(win: Window, y, x: int) = mvwin(win.cursesWindow, cint(y), cint(x))

proc resize*(win: var Window, height, width: int) =
  wresize(win.cursesWindow, cint(height), cint(width))

  win.height = height
  win.width = width

proc resize*(win: var Window, height, width, y, x: int) =
  win.resize(height, width)
  win.move(y, x)

  win.top = y
  win.left = x
  win.y = y
  win.x = x

proc attron*(win: var Window, attributes: Attributes) =
  win.cursesWindow.wattron(cint(attributes))

proc attroff*(win: var Window, attributes: Attributes) =
  win.cursesWindow.wattroff(cint(attributes))

proc moveCursor*(win: Window, y, x: int) =
  wmove(win.cursesWindow, cint(y), cint(x))

proc deleteWindow*(win: var Window) = delwin(win.cursesWindow)

const KEY_ESC = 27
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
    if key == -1: return Rune('\0')
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
proc isDcKey*(key: Rune): bool = key == KEY_DC
proc isPageUpKey*(key: Rune): bool = key == KEY_PPAGE or key == 2
proc isPageDownkey*(key: Rune): bool = key == KEY_NPAGE or key == 6
proc isTabkey*(key: Rune): bool = key == ord('\t') or key == 9
proc isControlA*(key: Rune): bool = key == 1
proc isControlX*(key: Rune): bool = key == 24
proc isControlR*(key: Rune): bool = key == 18
proc isControlJ*(key: Rune): bool = int(key) == 10
proc isControlK*(key: Rune): bool = int(key) == 11
proc isControlL*(key: Rune): bool = int(key) == 12
proc isControlU*(key: Rune): bool = int(key) == 21
proc isControlD*(key: Rune): bool = int(key) == 4
proc isControlV*(key: Rune): bool = int(key) == 22
proc isControlH*(key: Rune): bool = int(key) == 263
proc isControlW*(key: Rune): bool = int(key) == 23
proc isControlE*(key: Rune): bool = int(key) == 5
proc isControlY*(key: Rune): bool = int(key) == 25
proc isControlI*(key: Rune): bool = int(key) == 9
proc isControlT*(key: Rune): bool = int(key) == 20
proc isControlSquareBracketsRight*(key: Rune): bool = int(key) == 27  # Ctrl - [
proc isShiftTab*(key: Rune): bool = int(key) == 353
proc isBackspaceKey*(key: Rune): bool =
  key == KEY_BACKSPACE or key == 8 or key == 127
proc isEnterKey*(key: Rune): bool =
  key == KEY_ENTER or key == ord('\n') or key == 13
