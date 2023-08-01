#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[strformat, osproc, strutils, terminal]
import pkg/[ncurses, results]
import unicodeext, independentutils

when not defined unitTest:
  import std/[posix, os]

type
  Attribute* = enum
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

  CursorType* = enum
    terminalDefault
    blinkBlock
    noneBlinkBlock
    blinkIbeam
    noneBlinkIbeam

  Window* = ref object
    cursesWindow*: PWindow
    height*, width*: int
    y*, x*: int

  InputState* = enum
    Continue
    Valid
    Invalid
    Cancel

  ColorMode* {.pure.} = enum
    # No color support
    none = 1
    # 8 colors
    c8 = 8
    # 16 colors
    c16 = 16
    # 256 colors
    c256 = 256
    # 24 bit colors (Truecolor)
    c24bit = 16777216

const DefaultColorPair: int16 = 0

var
  # if press ctrl-c key, set true in setControlCHook()
  # TODO: Rename
  pressCtrlC* = false

  terminalSize: Size

proc parseColorMode*(str: string): Result[ColorMode, string] =
  case str:
    of "none":
      return Result[ColorMode, string].ok ColorMode.none
    of "8":
      return Result[ColorMode, string].ok ColorMode.c8
    of "16":
      return Result[ColorMode, string].ok ColorMode.c16
    of "256":
      return Result[ColorMode, string].ok ColorMode.c256
    of "24bit":
      return Result[ColorMode, string].ok ColorMode.c24bit
    else:
      return Result[ColorMode, string].err "Invalid value"

## Get the current terminal size and update.
proc updateTerminalSize*() =
  terminalSize.h = terminalHeight()
  terminalSize.w = terminalWidth()

proc updateTerminalSize*(s: Size) =
  terminalSize.h = s.h
  terminalSize.w = s.w

proc updateTerminalSize*(h, w: int) =
  terminalSize.h = h
  terminalSize.w = w

proc getTerminalSize*(): Size = terminalSize

proc getTerminalHeight*(): int = terminalSize.h

proc getTerminalWidth*(): int = terminalSize.w

proc setBlinkingIbeamCursor*() {.inline.} =
  when not defined unitTest:
    # Don't change when running unit tests
    discard execShellCmd("printf '\e[5 q'")

proc setNoneBlinkingIbeamCursor*() {.inline.} =
  when not defined unitTest:
    # Don't change when running unit tests
    discard execShellCmd("printf '\e[6 q'")

proc setBlinkingBlockCursor*() {.inline.} =
  when not defined unitTest:
    # Don't change when running unit tests
    discard execShellCmd("printf '\e[1 q'")

proc setNoneBlinkingBlockCursor*() {.inline.} =
  when not defined unitTest:
    # Don't change when running unit tests
    discard execShellCmd("printf '\e[2 q'")

proc setTerminalDefaultCursor*() {.inline.} =
  when not defined unitTest:
    # Don't change when running unit tests
    discard execShellCmd("printf '\x1B[0 q'")

proc unhideCursor*() {.inline.} =
  when not defined unitTest:
    # Don't change when running unit tests
    discard execShellCmd("printf '\e[?25h'")

proc changeCursorType*(cursorType: CursorType) =
  case cursorType
    of terminalDefault: setTerminalDefaultCursor()
    of blinkBlock: setBlinkingBlockCursor()
    of noneBlinkBlock: setNoneBlinkingBlockCursor()
    of blinkIbeam: setBlinkingIbeamCursor()
    of noneBlinkIbeam: setNoneBlinkingIbeamCursor()

proc disableControlC*() {.inline.} =
  setControlCHook(proc() {.noconv.} = pressCtrlC = true)

proc restoreTerminalModes*() {.inline.} = reset_prog_mode()

proc saveCurrentTerminalModes*() {.inline.} = def_prog_mode()

proc setCursor*(cursor: bool) =
  if cursor == true: curs_set(1)      ## enable cursor
  elif cursor == false: curs_set(0)   ## disable cursor

proc keyEcho*(keyecho: bool) =
  if keyecho == true: echo()
  elif keyecho == false: noecho()

proc setTimeout*(win: var Window, time: int = 100) {.inline.} =
  win.cursesWindow.wtimeout(cint(time))

## Check how many colors are supported on the terminal and return ColorMode.
## Check "$COLORTERM" first, then check "tput colors" if it fails.
## Return ColorMode.None if unknown color support.
proc checkColorSupportedTerminal*(): ColorMode =
  result = ColorMode.none

  block checkColorTerm:
    let cmdResult = execCmdEx("echo $COLORTERM")
    if cmdResult.exitCode == 0:
      var output = cmdResult.output
      output.stripLineEnd
      if output == "truecolor":
        return ColorMode.c24bit

  block checkTput:
    let cmdResult = execCmdEx("tput colors")
    if cmdResult.exitCode == 0:
      var output = cmdResult.output
      output.stripLineEnd

      var num: int
      try:
        num = output.parseInt
      except ValueError:
        return ColorMode.none

      case num:
        of 8: return ColorMode.c8
        of 16: return ColorMode.c16
        of 256: return ColorMode.c256
        else: return ColorMode.none

proc startUi*() =
  # Not start when running unit tests
  when not defined unitTest:
    # Set the current terminal size.
    updateTerminalSize()

    discard setlocale(LC_ALL, "")   # enable UTF-8

    initscr()   ## start terminal control
    cbreak()    ## enable cbreak mode
    nonl()      ## exit new line mode and improve move cursor performance
    setCursor(true)

    if can_change_color():
      # Enable Ncurses color
      startColor()

      # Set terminal default color
      useDefaultColors()

    erase()
    keyEcho(false)
    set_escdelay(25)

proc exitUi*() {.inline.} = endwin()

proc toNcursesColor(element: int16): int16 =
  ## Converts a color element (0 ~ 255) to a value for Ncurses (0 ~ 1000).
  ## The accuracy is not perfect.

  when not defined(release):
    # TODO: Return an error?
    doAssert(element >= 0 and element <= 255, fmt"Invalid value: `{element}`")

  return int16(element.float * (1000.0 / 255.0) + 0.5)

proc initNcursesColor*(color, red, green, blue: int16): Result[(), string] =
  let
    r = red.toNcursesColor
    g = green.toNcursesColor
    b = blue.toNcursesColor

  when not defined(release):
    # TODO: Return an error?
    doAssert(r >= 0, fmt"Invalid value: (r: `{r}`)")
    doAssert(g >= 0, fmt"Invalid value: (g: `{g}`)")
    doAssert(b >= 0, fmt"Invalid value: (b: `{b}`)")

  when not defined unitTest:
    # Not start when running unit tests
    let exitCode = initColor(color.cshort, r.cshort, g.cshort, b.cshort)
    if 0 != exitCode:
      return Result[(), string].err fmt"Init Ncurses color failed: (r: {r}, g: {g}, b: {b}): Exit code: {exitCode}"

  return Result[(), string].ok ()

proc initNcursesColorPair*(pair, fg, bg: int): Result[(), string] =
  when not defined(release):
    # TODO: Return an error?
    # 0 is reserved by Ncurses.
    doAssert(pair > 0, fmt"Cannot use `{pair}` in Ncurses color pair")

  when not defined unitTest:
    # Not start when running unit tests
    let exitCode = initExtendedPair(pair.cint, fg.cint, bg.cint)
    if 0 != exitCode:
      let msg = fmt"Init Ncurses color pair failed: (pair: {pair}, fg: {fg}, bg: {bg}): Exit code: {exitCode}"
      return Result[(), string].err msg

  return Result[(), string].ok ()

proc initWindow*(height, width, y, x: int, color: int16): Window =
  result = Window()
  result.y = y
  result.x = x
  result.height = height
  result.width = width
  result.cursesWindow = newwin(cint(height), cint(width), cint(y), cint(x))
  result.cursesWindow.keypad(true)
  result.cursesWindow.wbkgd(ncurses.COLOR_PAIR(color))

proc initWindow*(rect: Rect, color: int16): Window {.inline.} =
  initWindow(rect.h, rect.w, rect.y, rect.x, color)

proc attrSet*(win: var Window, color: int16) {.inline.} =
  win.cursesWindow.wattrSet(A_COLOR, color.cshort, nil)

proc attrOn*(win: var Window, attribute: Attribute) {.inline.} =
  win.cursesWindow.wattron(cint(attribute))

proc attrOn*(win: var Window, colorPair: int16) {.inline.} =
  win.cursesWindow.wattron(colorPair.cshort)

proc attrOff*(win: var Window, attribute: Attribute) {.inline.} =
  win.cursesWindow.wattroff(cint(attribute))

proc attrOff*(win: var Window, colorPair:  int16) {.inline.} =
  win.cursesWindow.wattroff(colorPair.cshort)

proc write*(
  win: var Window,
  y, x: int,
  str: string,
  color: int16 = DefaultColorPair,
  attribute: Attribute = Attribute.normal,
  storeX: bool = true) =

    when not defined unitTest:
      # Not write when running unit tests
      win.attrSet(color)
      win.attrOn(attribute)

      win.cursesWindow.mvwaddstr(y.cint, x.cint, str)

      win.attrOff(attribute)
      win.attrOff(color)

      if storeX:
        # WARNING: If `storeX` is true, this procedure will change the window position.
        # Should we remove the default parameter?
        win.y = y
        win.x = x + str.toRunes.width

proc write*(
  win: var Window,
  y, x: int,
  runes: Runes,
  color:  int16 = DefaultColorPair,
  attribute: Attribute = Attribute.normal,
  storeX: bool = true) {.inline.} =

    win.write(y, x, $runes, color, attribute, storeX)

proc erase*(win: var Window) =
  werase(win.cursesWindow)

proc refresh*(win: Window) {.inline.} = wrefresh(win.cursesWindow)

proc move*(win: Window, y, x: int) =
  mvwin(win.cursesWindow, cint(y), cint(x))

  win.y = y
  win.x = x

proc move*(win: Window, position: Position) {.inline.} =
  move(win, position.y, position.x)

proc resize*(win: var Window, height, width: int) =
  wresize(win.cursesWindow, cint(height), cint(width))

  win.height = height
  win.width = width

proc resize*(win: var Window, size: Size) {.inline.} =
  resize(win, size.h, size.w)

proc resize*(win: var Window, height, width, y, x: int) =
  win.resize(height, width)
  win.move(y, x)

  win.y = y
  win.x = x

proc resize*(win: var Window, position: Position, size: Size) {.inline.} =
  win.resize(size.h, size.w, position.y, position.x)

proc resize*(win: var Window, rect: Rect) {.inline.} =
  win.resize(rect.h, rect.w, rect.y, rect.x)

proc moveCursor*(win: Window, y, x: int) {.inline.} =
  wmove(win.cursesWindow, cint(y), cint(x))

proc deleteWindow*(win: var Window) {.inline.} = delwin(win.cursesWindow)

const ERR_KEY* = Rune(ERR)
const KEY_ESC* = 27
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
    len = 0

  block getfirst:
    let key = wgetch(win.cursesWindow)

    if Rune(key) == ERR_KEY:
      return ERR_KEY
    if not (key <= 0x7F or (0xC2 <= key and key <= 0xF0) or key == 0xF3):
      return Rune(key)

    s.add(char(key))
    len = numberOfBytes(char(key))

  for i in 0 ..< len-1: s.add(char(wgetch(win.cursesWindow)))

  let runes = toRunes(s)
  doAssert(runes.len == 1, fmt"runes length shoud be 1.")
  return runes[0]

proc isEscKey*(key: Rune): bool {.inline.} = key == KEY_ESC
proc isEscKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == KEY_ESC

proc isResizeKey*(key: Rune): bool {.inline.} = key == KEY_RESIZE
proc isResizeKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == KEY_RESIZE

proc isDownKey*(key: Rune): bool {.inline.} = key == KEY_DOWN
proc isDownKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == KEY_DOWN

proc isUpKey*(key: Rune): bool {.inline.} = key == KEY_UP
proc isUpKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == KEY_UP

proc isLeftKey*(key: Rune): bool {.inline.} = key == KEY_LEFT
proc isLeftKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == KEY_LEFT

proc isRightKey*(key: Rune): bool {.inline.} = key == KEY_RIGHT
proc isRightKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == KEY_RIGHT

proc isHomeKey*(key: Rune): bool {.inline.} = key == KEY_HOME
proc isHomeKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == KEY_HOME

proc isEndKey*(key: Rune): bool {.inline.} = key == KEY_END
proc isEndKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == KEY_END

proc isDcKey*(key: Rune): bool {.inline.} = key == KEY_DC
proc isDcKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == KEY_DC

proc isPageUpKey*(key: Rune): bool {.inline.} = key == KEY_PPAGE or key == 2
proc isPageUpKey*(r: Runes): bool {.inline.} =
  r.len == 1 and (r[0] == KEY_PPAGE or r[0] == 2)

proc isPageDownKey*(key: Rune): bool {.inline.} = key == KEY_NPAGE or key == 6
proc isPageDownKey*(r: Runes): bool {.inline.} =
  r.len == 1 and (r[0] == KEY_NPAGE or r[0] == 6)

proc isTabKey*(key: Rune): bool {.inline.} = key == ord('\t') or key == 9
proc isTabKey*(r: Runes): bool {.inline.} =
  r.len == 1 and (r[0] == ord('\t') or r[0] == 9)

proc isControlA*(key: Rune): bool {.inline.} = key == 1
proc isControlA*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 1

proc isControlC*(key: Rune): bool {.inline.} = key == 3
proc isControlC*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 3

proc isControlX*(key: Rune): bool {.inline.} = key == 24
proc isControlX*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 24

proc isControlR*(key: Rune): bool {.inline.} = key == 18
proc isControlR*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 18

proc isControlJ*(key: Rune): bool {.inline.} = key == 10
proc isControlJ*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 10

proc isControlK*(key: Rune): bool {.inline.} = key == 11
proc isControlK*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 11

proc isControlL*(key: Rune): bool {.inline.} = key == 12
proc isControlL*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 12

proc isControlU*(key: Rune): bool {.inline.} = key == 21
proc isControlU*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 21

proc isControlD*(key: Rune): bool {.inline.} = key == 4
proc isControlD*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 4

proc isControlV*(key: Rune): bool {.inline.} = key == 22
proc isControlV*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 22

proc isControlH*(key: Rune): bool {.inline.} = key == 263
proc isControlH*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 263

proc isControlW*(key: Rune): bool {.inline.} = key == 23
proc isControlW*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 23

proc isControlE*(key: Rune): bool {.inline.} = key == 5
proc isControlE*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 5

proc isControlY*(key: Rune): bool {.inline.} = key == 25
proc isControlY*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 25

proc isControlI*(key: Rune): bool {.inline.} = key == 9
proc isControlI*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 9

proc isControlT*(key: Rune): bool {.inline.} = key == 20
proc isControlT*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 20

# Ctrl - [
proc isControlSquareBracketsRight*(key: Rune): bool {.inline.} =
  key == 27
proc isControlSquareBracketsRight*(r: Runes): bool {.inline.} =
  r.len == 1 and r[0] == 27

proc isShiftTab*(key: Rune): bool {.inline.} = key == 353
proc isShiftTab*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == 353

proc isBackspaceKey*(key: Rune): bool {.inline.} =
  key == KEY_BACKSPACE or key == 8 or key == 127
proc isBackspaceKey*(r: Runes): bool {.inline.} =
  r.len == 1 and (r[0] == KEY_BACKSPACE or r[0] == 8 or r[0] == 127)

proc isEnterKey*(key: Rune): bool {.inline.} =
  key == KEY_ENTER or key == ord('\n') or key == 13
proc isEnterKey*(r: Runes): bool {.inline.} =
  r.len == 1 and (r[0] == KEY_ENTER or r[0] == ord('\n') or r[0] == 13)

proc isError*(key: Rune): bool = key == ERR_KEY
proc isError*(r: Runes): bool = r.len == 1 and r[0] == ERR_KEY
