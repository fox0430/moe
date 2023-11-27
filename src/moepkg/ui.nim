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

import std/[strformat, osproc, strutils, terminal, options, tables, posix]
import pkg/[ncurses, results]
import unicodeext, independentutils

when not defined unitTest:
  import std/os

type
  Attribute* {.pure.} = enum
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
    horizontal = A_HORIZONTAL
    left = A_LEFT
    low = A_LOW
    right = A_RIGHT
    top = A_TOP
    vertical = A_VERTICAL

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
    none = 1
      # No color support
    c8 = 8
      # 8 colors
    c16 = 16
      # 16 colors
    c256 = 256
      # 256 colors
    c24bit = 16777216
      # 24 bit colors (True color)

  Key* = Rune

const
  DefaultColorPair*: int16 = 0

  SIGWINCH: int = 28
    # SIGWINCH signal

  TabKey        = 9
  EnterKey*     = 10
  EscKey*       = 27 # or Ctrl-[
  BackSpaceKey* = 127

  CtrlA* = 1
  CtrlB* = 2
  CtrlC* = 3
  CtrlD* = 4
  CtrlE* = 5
  CtrlF* = 6
  CtrlG* = 7
  CtrlH* = 8
  CtrlI* = 9 # or Tab
  CtrlJ* = 10
  CtrlK* = 11
  CtrlL* = 12
  CtrlM* = 13 # or Enter
  CtrlN* = 14
  CtrlO* = 15
  CtrlP* = 16
  CtrlQ* = 17
  CtrlR* = 18
  CtrlS* = 19
  CtrlT* = 20
  CtrlU* = 21
  CtrlV* = 22
  CtrlW* = 23
  CtrlX* = 24
  CtrlY* = 25
  CtrlZ* = 26

  ShiftTab* = 353

  ResizeKey*           = 1001
  UpKey*               = 1002
  DownKey*             = 1003
  RightKey*            = 1004
  LeftKey*             = 1005
  EndKey*              = 1006
  HomeKey*             = 1007
  InsertKey*           = 1008
  DeleteKey*           = 1009
  PageUpKey*           = 1010
  PageDownKey*         = 1011
  PasteKey*            = 1012
  BracketedPasteStart* = 1013
  BracketedPasteEnd*   = 1014

  KeySequences = {
    UpKey:       @["\eOA", "\e[A"],
    DownKey:     @["\eOB", "\e[B"],
    RightKey:    @["\eOC", "\e[C"],
    LeftKey:     @["\eOD", "\e[D"],

    EndKey:      @["\e[4~", "\e[8~", "\eOF", "\e[F"],
    HomeKey:     @["\e[1~", "\e[7~", "\eOH", "\e[H"],
    InsertKey:   @["\e[2~"],
    DeleteKey:   @["\e[3~"],
    PageUpKey:   @["\e[5~"],
    PageDownKey: @["\e[6~"],

    BracketedPasteStart: @["\e[200~"],
    BracketedPasteEnd: @["\e[201~"]
  }.toTable

var
  ctrlCPressed* = false
    # Set true if Ctrl-c key is pressed.

  terminalResized* = false
    # Set true if the terminal size is resized.

  pasteBuffer*: seq[Runes]

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

proc showCursor*() {.inline.} =
  when not defined unitTest:
    # Don't change when running unit tests
    discard execShellCmd("printf '\e[?25h'")

proc hideCursor*() {.inline.} =
  when not defined unitTest:
    # Don't change when running unit tests
    discard execShellCmd("printf '\e[?25l'")

proc changeCursorType*(cursorType: CursorType) =
  case cursorType
    of terminalDefault: setTerminalDefaultCursor()
    of blinkBlock: setBlinkingBlockCursor()
    of noneBlinkBlock: setNoneBlinkingBlockCursor()
    of blinkIbeam: setBlinkingIbeamCursor()
    of noneBlinkIbeam: setNoneBlinkingIbeamCursor()

proc disableControlC*() {.inline.} =
  setControlCHook(proc() {.noconv.} = ctrlCPressed = true)

proc catchTerminalResize*() {.inline.} =
  onSignal(SIGWINCH.cint): terminalResized = true

proc restoreTerminalModes*() {.inline.} = reset_prog_mode()

proc saveCurrentTerminalModes*() {.inline.} = def_prog_mode()

proc setCursor(cursor: bool) =
  if cursor == true: curs_set(1)      ## enable cursor
  elif cursor == false: curs_set(0)   ## disable cursor

proc keyEcho*(keyecho: bool) =
  if keyecho == true: echo()
  elif keyecho == false: noecho()

proc checkColorSupportedTerminal*(): ColorMode =
  ## Check how many colors are supported on the terminal and return ColorMode.
  ## Check "$COLORTERM" first, then check "tput colors" if it fails.
  ## Return ColorMode.None if unknown color support.

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

proc enableBracketedPasteMode() {.inline.} =
  when not defined unitTest:
      # Don't start when running unit tests
    discard execShellCmd("printf '\x1b[?2004h'")

proc startUi*() =
  # Not start when running unit tests
  when not defined unitTest:
    # Set the current terminal size.
    updateTerminalSize()

    discard setlocale(LC_ALL, "")   # enable UTF-8

    initscr() # Start terminal control
    cbreak() # Enable cbreak mode
    nonl() # Exit new line mode and improve move cursor performance
    setCursor(false) # Hide Ncurses cursor

    if can_change_color():
      # Enable Ncurses color
      startColor()

      # Set terminal default color
      useDefaultColors()

    erase()
    keyEcho(false)
    set_escdelay(25)

    enableBracketedPasteMode()

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

proc overlay*(win, destWin: var Window) {.inline.} =
  overlay(win.cursesWindow, destWin.cursesWindow)

proc overwrite*(win, destWin: var Window) {.inline.} =
  overwrite(win.cursesWindow, destWin.cursesWindow)

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

proc toString(s: seq[int]): string {.inline.} =
  for n in s: result &= n.char

proc isBracketedPaste(s: string): bool {.inline.} =
  template startSeq: string = KeySequences[BracketedPasteStart][0]
  template endSeq: string = KeySequences[BracketedPasteEnd][0]

  s.startsWith(startSeq) and
  s.endsWith(endSeq) and
  s.len > startSeq.len + endSeq.len

proc parseKey(buffer: seq[int]): Option[Rune] =
  if buffer.len == 0: return

  if buffer.len == 1:
    let ch = buffer[0]
    case ch:
      of 0, 29, 30, 31:
        # Ignore
        return none(Rune)
      else:
        return some(ch.toRune)
  else:
    block specialKey:
      var input = ""
      for ch in buffer: input &= ch.char
      for keyCode, sequences in KeySequences.pairs:
        for s in sequences:
          case keyCode:
            of BracketedPasteStart:
              if input.isBracketedPaste:
                let
                  first = KeySequences[BracketedPasteStart][0].len
                  last = input.high - KeySequences[BracketedPasteEnd][0].len
                pasteBuffer = input[first .. last].toRunes.splitLines
                return some(PasteKey.Rune)
            else:
              if s == input: return some(keyCode.Rune)

    block multiByteCharacter:
      let runes = buffer.toString.toRunes
      # The runes length should be 1.
      if runes.len == 1:
        return some(runes[0])

proc kbhit(timeout: int = 10): int =
  ## Check stdin buffer using poll(2).
  ##
  ## poll(2) return POLLERR if it detects a signal.
  ##
  ## `timeout` is milliseconds.

  # Init pollFd.
  var pollFd: TPollfd
  pollFd.addr.zeroMem(sizeof(pollFd))

  # Registers fd and events.
  pollFd.fd = STDIN_FILENO
  pollFd.events = POLLIN or POLLERR

  # Wait stdin.
  const FdLen = 1
  return pollFd.addr.poll(FdLen.Tnfds, timeout)

proc read(fd: int): Option[int] =
  ## Read 1 byte.

  const Size = 1
  var ch: int
  if read(fd.cint, ch.addr, Size) > 0: return some(ch)

proc isSingle(ch: int): bool {.inline.} =
  not (ch <= 0x7F or (0xC2 <= ch and ch <= 0xF0) or ch == 0xF3)

proc getKey*(timeout: int = 100): Option[Rune] =
  ## Non-blocking read from stdin.
  ## timeout is milliseconds.

  let readable = kbhit()
  if readable > 0:
    # Read a char from stdin.

    const
      Fd = STDIN_FILENO
      Size = 1

    let firstCh = Fd.read
    if firstCh.isSome:
      var buffer = @[firstCh.get]

      if firstCh.get.isSingle:
        return parseKey(buffer)
      elif firstCh.get == EscKey:
        const Timeout = 1
        while kbhit(Timeout) > 0:
          let ch = Fd.read
          if ch.isSome: buffer.add ch.get
        return parseKey(buffer)
      else:
        let length = firstCh.get.char.numberOfBytes
        if length > 1:
          for _ in 1 ..< length:
            var ch: int
            if read(Fd, ch.addr, Size) > 0: buffer.add ch
        return parseKey(buffer)
  elif readable < 0:
    # Check signals.
    if ctrlCPressed:
      ctrlCPressed = false
      return some(CtrlC.Rune)
    elif terminalResized:
      terminalResized = false
      return some(ResizeKey.Rune)

proc getKeyBlocking*(): Rune {.inline.} =
  ## Blocking read from stdin.

  const Timeout = -1
  return getKey(Timeout).get

proc isEscKey*(key: Rune): bool {.inline.} = key == EscKey
proc isEscKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == EscKey

proc isResizeKey*(key: Rune): bool {.inline.} = key == ResizeKey
proc isResizeKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == ResizeKey

proc isBracketedPasteStart*(key: Rune): bool {.inline.} =
  key == BracketedPasteStart
proc isBracketedPasteStart*(r: Runes): bool {.inline.} =
  r.len == 1 and r[0].isBracketedPasteStart

proc isBracketedPasteEnd*(key: Rune): bool {.inline.} =
  key == BracketedPasteEnd
proc isBracketedPasteEnd*(r: Runes): bool {.inline.} =
  r.len == 1 and r[0].isBracketedPasteEnd

proc isPasteKey*(key: Rune): bool {.inline.} = key == PasteKey
proc isPasteKey*(r: Runes): bool {.inline.} =  r.len == 1 and r[0] == PasteKey

proc isUpKey*(key: Rune): bool {.inline.} = key == UpKey
proc isUpKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == UpKey

proc isDownKey*(key: Rune): bool {.inline.} = key == DownKey
proc isDownKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == DownKey

proc isRightKey*(key: Rune): bool {.inline.} = key == RightKey
proc isRightKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == RightKey

proc isLeftKey*(key: Rune): bool {.inline.} = key == LeftKey
proc isLeftKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == LeftKey

proc isHomeKey*(key: Rune): bool {.inline.} = key == HomeKey
proc isHomeKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == HomeKey

proc isEndKey*(key: Rune): bool {.inline.} = key == EndKey
proc isEndKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == EndKey

proc isInsertKey*(key: Rune): bool {.inline.} = key == InsertKey
proc isInsertKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == InsertKey

proc isDeleteKey*(key: Rune): bool {.inline.} = key == DeleteKey
proc isDeleteKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == DeleteKey

proc isPageUpKey*(key: Rune): bool {.inline.} = key == PageUpKey
proc isPageUpKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0] == PageUpKey

proc isPageDownKey*(key: Rune): bool {.inline.} = key == PageDownKey
proc isPageDownKey*(r: Runes): bool {.inline.} =
  r.len == 1 and r[0] == PageDownKey

proc isTabKey*(key: Rune): bool {.inline.} = key == ord('\t') or key == TabKey
proc isTabKey*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isTabKey

proc isCtrlA*(key: Rune): bool {.inline.} = key == CtrlA
proc isCtrlA*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlA

proc isCtrlB*(key: Rune): bool {.inline.} = key == CtrlB
proc isCtrlB*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlB

proc isCtrlC*(key: Rune): bool {.inline.} = key == CtrlC
proc isCtrlC*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlC

proc isCtrlD*(key: Rune): bool {.inline.} = key == CtrlD
proc isCtrlD*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlD

proc isCtrlE*(key: Rune): bool {.inline.} = key == CtrlE
proc isCtrlE*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlE

proc isCtrlF*(key: Rune): bool {.inline.} = key == CtrlF
proc isCtrlF*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlF

proc isCtrlG*(key: Rune): bool {.inline.} = key == CtrlG
proc isCtrlG*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlG

proc isCtrlH*(key: Rune): bool {.inline.} = key == CtrlH
proc isCtrlH*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlH

proc isCtrlI*(key: Rune): bool {.inline.} = key == CtrlI
proc isCtrlI*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlI

proc isCtrlJ*(key: Rune): bool {.inline.} = key == CtrlJ
proc isCtrlJ*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlJ

proc isCtrlK*(key: Rune): bool {.inline.} = key == CtrlK
proc isCtrlK*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlK

proc isCtrlL*(key: Rune): bool {.inline.} = key == CtrlL
proc isCtrlL*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlL

proc isCtrlM*(key: Rune): bool {.inline.} = key == CtrlM
proc isCtrlM*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlM

proc isCtrlN*(key: Rune): bool {.inline.} = key == CtrlN
proc isCtrlN*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlN

proc isCtrlO*(key: Rune): bool {.inline.} = key == CtrlO
proc isCtrlO*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlO

proc isCtrlP*(key: Rune): bool {.inline.} = key == CtrlP
proc isCtrlP*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlP

proc isCtrlQ*(key: Rune): bool {.inline.} = key == CtrlQ
proc isCtrlQ*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlQ

proc isCtrlR*(key: Rune): bool {.inline.} = key == CtrlR
proc isCtrlR*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlR

proc isCtrlS*(key: Rune): bool {.inline.} = key == CtrlS
proc isCtrlS*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlS

proc isCtrlT*(key: Rune): bool {.inline.} = key == CtrlT
proc isCtrlT*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlT

proc isCtrlU*(key: Rune): bool {.inline.} = key == CtrlU
proc isCtrlU*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlU

proc isCtrlV*(key: Rune): bool {.inline.} = key == CtrlV
proc isCtrlV*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlV

proc isCtrlW*(key: Rune): bool {.inline.} = key == CtrlW
proc isCtrlW*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlW

proc isCtrlX*(key: Rune): bool {.inline.} = key == CtrlX
proc isCtrlX*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlA

proc isCtrlY*(key: Rune): bool {.inline.} = key == CtrlX
proc isCtrlY*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlY

proc isCtrlZ*(key: Rune): bool {.inline.} = key == CtrlZ
proc isCtrlZ*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isCtrlZ

proc isShiftTab*(key: Rune): bool {.inline.} = key == ShiftTab
proc isShiftTab*(r: Runes): bool {.inline.} = r.len == 1 and r[0].isShiftTab

proc isBackspaceKey*(key: Rune): bool {.inline.} =
  key == BackSpaceKey or key == 8 or key == 127
proc isBackspaceKey*(r: Runes): bool {.inline.} =
  r.len == 1 and r[0].isBackspaceKey

proc isEnterKey*(key: Rune): bool {.inline.} =
  key == EnterKey or key == ord('\n') or key == 13
proc isEnterKey*(r: Runes): bool {.inline.} =
  r.len == 1 and r[0] == EnterKey or r[0].isEnterKey
