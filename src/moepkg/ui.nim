import posix, strformat, osproc, strutils
from os import execShellCmd
import ncurses
import unicodetext, color

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
  blinkBlock = 0
  noneBlinkBlock = 1
  blinkIbeam = 2
  noneBlinkIbeam = 3

type Window* = ref object
  cursesWindow*: PWindow
  height*, width*: int
  y*, x*: int

proc setBkinkingIbeamCursor*() {.inline.} = discard execShellCmd("printf \"\x1b[\x35 q\"")

proc setNoneBlinkingIbeamCursor*() {.inline.} = discard execShellCmd("printf '\\033[6 q'")

proc setBlinkingBlockCursor*() {.inline.} = discard execShellCmd("printf '\e[0 q'")

proc setNoneBlinkingBlockCursor*() {.inline.} = discard execShellCmd("printf '\x1b[\x32 q'")

proc changeCursorType*(cursorType: CursorType) =
  case cursorType
  of blinkBlock: setBlinkingBlockCursor()
  of noneBlinkBlock: setNoneBlinkingBlockCursor()
  of blinkIbeam: setBkinkingIbeamCursor()
  of noneBlinkIbeam: setNoneBlinkingIbeamCursor()

proc disableControlC*() {.inline.} = setControlCHook(proc() {.noconv.} = discard)

proc restoreTerminalModes*() {.inline.} = reset_prog_mode()

proc saveCurrentTerminalModes*() {.inline.} = def_prog_mode()

proc setCursor*(cursor: bool) =
  if cursor == true: curs_set(1)      ## enable cursor
  elif cursor == false: curs_set(0)   ## disable cursor

proc keyEcho*(keyecho: bool) =
  if keyecho == true: echo()
  elif keyecho == false: noecho()

proc setTimeout*(win: var Window) {.inline.} = win.cursesWindow.wtimeout(cint(1000)) # 500mm sec

proc setTimeout*(win: var Window, time: int) {.inline.} = win.cursesWindow.wtimeout(cint(time))

# Check how many colors are supported on the terminal
proc checkColorSupportedTerminal*(): int =
  let (output, exitCode) = execCmdEx("tput colors")

  if exitCode == 0:
    result = (output[0 ..< output.high]).parseInt
  else:
    result = -1

proc startUi*() =
  # Not start when running unit tests
  when not defined unitTest:
    discard setLocale(LC_ALL, "")   # enable UTF-8

    initscr()   ## start terminal control
    cbreak()    ## enable cbreak mode
    nonl();     ## exit new line mode and improve move cursor performance
    setCursor(true)

    if can_change_color():
      ## default is dark
      setCursesColor(ColorThemeTable[ColorTheme.dark])

    erase()
    keyEcho(false)
    set_escdelay(25)

proc exitUi*() {.inline.} = endwin()

proc initWindow*(height, width, y, x: int, color: EditorColorPair): Window =
  result = Window()
  result.y = y
  result.x = x
  result.height = height
  result.width = width
  result.cursesWindow = newwin(cint(height), cint(width), cint(y), cint(x))
  keypad(result.cursesWindow, true)
  discard wbkgd(result.cursesWindow, ncurses.COLOR_PAIR(color))

proc write*(win: var Window,
            y, x: int,
            str: string,
            color: EditorColorPair = EditorColorPair.defaultChar,
            storeX: bool = true) =
  # WARNING: If `storeX` is true, this procedure will change the window position. Should we remove the default parameter?
  #
  # Not write when running unit tests
  when not defined unitTest:
    win.cursesWindow.wattron(cint(ncurses.COLOR_PAIR(ord(color))))
    mvwaddstr(win.cursesWindow, cint(y), cint(x), str)

    if storeX:
      win.y = y
      win.x = x+str.toRunes.width

proc write*(win: var Window,
            y, x: int,
            str: string,
            color: int,
            storeX: bool = true) =
  # WARNING: If `storeX` is true, this procedure will change the window position. Should we remove the default parameter?
  #
  # Not write when running unit tests
  when not defined unitTest:
    win.cursesWindow.wattron(cint(ncurses.COLOR_PAIR(ord(color))))
    mvwaddstr(win.cursesWindow, cint(y), cint(x), str)

    if storeX:
      win.y = y
      win.x = x+str.toRunes.width

proc write*(win: var Window,
            y, x: int,
            str: seq[Rune],
            color: EditorColorPair = EditorColorPair.defaultChar,
            storeX: bool = true) =
  # WARNING: If `storeX` is true, this procedure will change the window position. Should we remove the default parameter?
  #
  # Not write when running unit tests
  when not defined unitTest:
    write(win, y, x, $str, color, false)

    if storeX:
      win.y = y
      win.x = x+str.width

proc append*(win: var Window,
              str: string,
              color: EditorColorPair = EditorColorPair.defaultChar) =

  # Not write when running unit tests
  when not defined unitTest:
    win.cursesWindow.wattron(cint(ncurses.COLOR_PAIR(ord(color))))
    mvwaddstr(win.cursesWindow, cint(win.y), cint(win.x), $str)

    win.x += str.toRunes.width

proc append*(win: var Window,
            str: seq[Rune],
            color: EditorColorPair = EditorColorPair.defaultChar) =

  # Not write when running unit tests
  when not defined unitTest:
    append(win, $str, color)

proc erase*(win: var Window) =
  werase(win.cursesWindow)
  win.y = 0
  win.x = 0

proc refresh*(win: Window) {.inline.} = wrefresh(win.cursesWindow)

proc move*(win: Window, y, x: int) {.inline.} = mvwin(win.cursesWindow, cint(y), cint(x))

proc resize*(win: var Window, height, width: int) =
  wresize(win.cursesWindow, cint(height), cint(width))

  win.height = height
  win.width = width

proc resize*(win: var Window, height, width, y, x: int) =
  win.resize(height, width)
  win.move(y, x)

  win.y = y
  win.x = x

proc attron*(win: var Window, attributes: Attributes) {.inline.} =
  win.cursesWindow.wattron(cint(attributes))

proc attroff*(win: var Window, attributes: Attributes) {.inline.} =
  win.cursesWindow.wattroff(cint(attributes))

proc moveCursor*(win: Window, y, x: int) {.inline.} =
  wmove(win.cursesWindow, cint(y), cint(x))

proc deleteWindow*(win: var Window) {.inline.} = delwin(win.cursesWindow)

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
const errorKey* = Rune(ERR)

proc getKey*(win: Window): Rune =
  var
    s = ""
    len: int
  block getfirst:
    let key = wgetch(win.cursesWindow)
    if Rune(key) == errorKey: return errorKey
    if not (key <= 0x7F or (0xC2 <= key and key <= 0xF0) or key == 0xF3): return Rune(key)
    s.add(char(key))
    len = numberOfBytes(char(key))
  for i in 0 ..< len-1: s.add(char(wgetch(win.cursesWindow)))

  let runes = toRunes(s)
  doAssert(runes.len == 1, fmt"runes length shoud be 1.")
  return runes[0]

proc isEscKey*(key: Rune): bool {.inline.} = key == KEY_ESC
proc isResizeKey*(key: Rune): bool {.inline.} = key == KEY_RESIZE
proc isDownKey*(key: Rune): bool {.inline.} = key == KEY_DOWN
proc isUpKey*(key: Rune): bool {.inline.} = key == KEY_UP
proc isLeftKey*(key: Rune): bool {.inline.} = key == KEY_LEFT
proc isRightKey*(key: Rune): bool {.inline.} = key == KEY_RIGHT
proc isHomeKey*(key: Rune): bool {.inline.} = key == KEY_HOME
proc isEndKey*(key: Rune): bool {.inline.} = key == KEY_END
proc isDcKey*(key: Rune): bool {.inline.} = key == KEY_DC
proc isPageUpKey*(key: Rune): bool {.inline.} = key == KEY_PPAGE or key == 2
proc isPageDownkey*(key: Rune): bool {.inline.} = key == KEY_NPAGE or key == 6
proc isTabkey*(key: Rune): bool {.inline.} = key == ord('\t') or key == 9
proc isControlA*(key: Rune): bool {.inline.} = key == 1
proc isControlX*(key: Rune): bool {.inline.} = key == 24
proc isControlR*(key: Rune): bool {.inline.} = key == 18
proc isControlJ*(key: Rune): bool {.inline.} = int(key) == 10
proc isControlK*(key: Rune): bool {.inline.} = int(key) == 11
proc isControlL*(key: Rune): bool {.inline.} = int(key) == 12
proc isControlU*(key: Rune): bool {.inline.} = int(key) == 21
proc isControlD*(key: Rune): bool {.inline.} = int(key) == 4
proc isControlV*(key: Rune): bool {.inline.} = int(key) == 22
proc isControlH*(key: Rune): bool {.inline.} = int(key) == 263
proc isControlW*(key: Rune): bool {.inline.} = int(key) == 23
proc isControlE*(key: Rune): bool {.inline.} = int(key) == 5
proc isControlY*(key: Rune): bool {.inline.} = int(key) == 25
proc isControlI*(key: Rune): bool {.inline.} = int(key) == 9
proc isControlT*(key: Rune): bool {.inline.} = int(key) == 20
proc isControlSquareBracketsRight*(key: Rune): bool {.inline.} = int(key) == 27  # Ctrl - [
proc isShiftTab*(key: Rune): bool {.inline.} = int(key) == 353
proc isBackspaceKey*(key: Rune): bool {.inline.} =
  key == KEY_BACKSPACE or key == 8 or key == 127
proc isEnterKey*(key: Rune): bool {.inline.} =
  key == KEY_ENTER or key == ord('\n') or key == 13
proc isError*(key: Rune): bool = key == errorKey
