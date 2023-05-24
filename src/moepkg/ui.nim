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
import pkg/ncurses
import unicodeext, color, independentutils

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

var
  # if press ctrl-c key, set true in setControlCHook()
  # TODO: Rename
  pressCtrlC* = false

  terminalSize: Size

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

proc setBkinkingIbeamCursor*() {.inline.} =
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
    of blinkIbeam: setBkinkingIbeamCursor()
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
    # Set the current terminal size.
    updateTerminalSize()

    discard setlocale(LC_ALL, "")   # enable UTF-8

    initscr()   ## start terminal control
    cbreak()    ## enable cbreak mode
    nonl()      ## exit new line mode and improve move cursor performance
    setCursor(true)

    if can_change_color():
      ## default is dark
      setCursesColor(colorThemeTable[colorTheme.dark])

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

proc initWindow*(rect: Rect, color: EditorColorPair): Window {.inline.} =
  initWindow(rect.h, rect.w, rect.y, rect.x, color)

proc attrSet*(win: var Window, color: EditorColorPair | int16) {.inline.} =
  win.cursesWindow.wattrSet(A_COLOR, color.cshort, nil)

proc attrOn*(win: var Window, attribute: Attribute) {.inline.} =
  win.cursesWindow.wattron(cint(attribute))

proc attrOff*(win: var Window, attribute: Attribute) {.inline.} =
  win.cursesWindow.wattroff(cint(attribute))

proc attrOff*(win: var Window, colorPair: EditorColorPair | int16) {.inline.} =
  win.cursesWindow.wattroff(colorPair.cshort)

proc write*(
  win: var Window,
  y, x: int,
  str: string,
  color: int16 = EditorColorPair.defaultChar.int16,
  storeX: bool = true) =

    when not defined unitTest:
      # Not write when running unit tests
      win.attrSet(color.cshort)
      win.cursesWindow.mvwaddstr(y.cint, x.cint, str)
      win.attrOff(color.cshort)

      if storeX:
        # WARNING: If `storeX` is true, this procedure will change the window position.
        # Should we remove the default parameter?
        win.y = y
        win.x = x + str.toRunes.width

proc write*(
  win: var Window,
  y, x: int,
  str: string,
  color: EditorColorPair = EditorColorPair.defaultChar,
  storeX: bool = true) {.inline.} =

    win.write(y, x, str, color.int16, storeX)

proc write*(
  win: var Window,
  y, x: int,
  runes: Runes,
  color: int16 = EditorColorPair.defaultChar.int16,
  storeX: bool = true) {.inline.} =

    win.write(y, x, $runes, color, storeX)

proc write*(
  win: var Window,
  y, x: int,
  runes: Runes,
  color: EditorColorPair = EditorColorPair.defaultChar,
  storeX: bool = true) =

    win.write(y, x, $runes, color, storeX)

proc append*(
  win: var Window,
  str: string,
  color: EditorColorPair = EditorColorPair.defaultChar) =

    when not defined unitTest:
      # Not write when running unit tests
      win.attrSet(color.cshort)
      win.cursesWindow.mvwaddstr(win.y.cint, win.x.cint, str)
      win.attrOff(color.cshort)

      win.x += str.toRunes.width

proc append*(
  win: var Window,
  runes: Runes,
  color: EditorColorPair = EditorColorPair.defaultChar) {.inline.} =

    win.append($runes, color)

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
