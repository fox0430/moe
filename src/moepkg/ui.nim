import std/[osproc, strutils, os, terminal, strformat, options, logging, times]
import pkg/illwill
import unicodeext, color

when not defined unitTest:
  import std/posix

#type Attributes* = enum
#  normal = A_NORMAL
#  standout = A_STANDOUT
#  underline = A_UNDERLINE
#  reverse = A_REVERSE
#  blink = A_BLINK
#  dim = A_DIM
#  bold = A_BOLD
#  altcharet = A_ALT_CHARSET
#  invis = A_INVIS
#  protect = A_PROTECT
#  #chartext = A_CHAR_TEXT

type CursorType* = enum
  blinkBlock = 0
  noneBlinkBlock = 1
  blinkIbeam = 2
  noneBlinkIbeam = 3

type Window* = ref object
  #cursesWindow*: TermWindow
  height*, width*: int
  y*, x*: int

var
  tb*: TerminalBuffer

  pressCtrlC* = false
  isResizedWindow* = false

const
  NONE_KEY* = Rune(int(illwill.Key.None))

  SIGWINCH = cint(28)

# SIGWINCH will be sent when the terminal emulator is resized on the X11.
onSignal(SIGWINCH):
  isResizedWindow = true

proc setBkinkingIbeamCursor*() {.inline.} = discard execShellCmd("printf '\e[5 q'")

proc setNoneBlinkingIbeamCursor*() {.inline.} = discard execShellCmd("printf '\e[6 q'")

proc setBlinkingBlockCursor*() {.inline.} = discard execShellCmd("printf '\e[1 q'")

proc setNoneBlinkingBlockCursor*() {.inline.} = discard execShellCmd("printf '\e[2 q'")

proc unhideCursor*() {.inline.} = discard execShellCmd("printf '\e[?25h'")

proc changeCursorType*(cursorType: CursorType) =
  case cursorType
  of blinkBlock: setBlinkingBlockCursor()
  of noneBlinkBlock: setNoneBlinkingBlockCursor()
  of blinkIbeam: setBkinkingIbeamCursor()
  of noneBlinkIbeam: setNoneBlinkingIbeamCursor()

# if press ctrl-c key, set true in setControlCHook()
proc disableControlC*() {.inline.} =
  setControlCHook(proc() {.noconv.} = pressCtrlC = true)

#proc restoreTerminalModes*() {.inline.} = reset_prog_mode()
#
#proc saveCurrentTerminalModes*() {.inline.} = def_prog_mode()

proc setCursor*(cursor: bool) =
  if cursor:
    discard execShellCmd("printf '\e[?25h'")
  else:
    discard execShellCmd("printf '\e[?25l'")

#proc keyEcho*(keyecho: bool) =
#  if keyecho == true: echo()
#  elif keyecho == false: noecho()

proc setTimeout*(win: var Window) =
  discard

proc setTimeout*(win: var Window, time: int) =
  discard

# Check how many colors are supported on the terminal.
proc checkColorSupportedTerminal*(): int =
  let (output, exitCode) = execCmdEx("tput colors")

  if exitCode == 0:
    result = (output[0 ..< output.high]).parseInt
  else:
    result = -1

# Clear the screen.
proc initTerminalBuffer*() =
  tb = newTerminalBuffer(terminalWidth(), terminalHeight())

proc exitUi*() {.noconv.} =
  illwillDeinit()
  showCursor()
  eraseScreen()

proc startUi*() =
  illwillInit(fullscreen = true)
  setControlCHook(exitUi)

# Set the terminal background color.
proc applyBackgroundColor(colorCode: ColorCode) =
  let
    colors = colorCode.toRGBInt
    cmd = """printf "\x1b[48;2;""" & fmt"{colors.r};{colors.g};{colors.b}" & """""m""""
  discard execShellCmd(cmd)

# Set the terminal foreground color.
proc applyForegroundColor(colorCode: ColorCode) =
  let
    colors = colorCode.toRGBInt
    cmd = """printf "\x1b[38;2;""" & fmt"{colors.r};{colors.g};{colors.b}" & """""m""""
  discard execShellCmd(cmd)

# Reset the terminal color.
proc resetColor() {.inline.} =
  discard execShellCmd("""printf "\x1b[0m\n"""")

# Set the terminal color.
proc applyColorPair(colorPair: ColorPair) =
  # None is the terminal default color.
  if colorPair.fg.isNone or colorPair.bg.isNone:
    resetColor()

  if colorPair.fg.isSome:
    applyForegroundColor(colorPair.fg.get)

  if colorPair.bg.isSome:
    applyBackgroundColor(colorPair.fg.get)

# Display buffer in the terminal buffer.
proc display*() {.inline.} = tb.display

# Write to the terminal buffer.
proc write*(x, y: int, buf: string) {.inline.} =
  # Don't write when running unit tests
  when not defined unitTest:
    tb.write(x, y, buf)

proc write*(x, y: int, buf: seq[Rune]) {.inline.} =
  # Don't write when running unit tests
  when not defined unitTest:
    tb.write(x, y, $buf)

proc write*(x, y: int, buf: string | seq[Rune], color: ColorPair) =
  # Don't write when running unit tests
  when not defined unitTest:
    applyColorPair(color)
    tb.write(x, y, buf)

  # Not start when running unit tests
  #when not defined unitTest:
  #  discard setLocale(LC_ALL, "")   # enable UTF-8

  #  initscr()   ## start terminal control
  #  cbreak()    ## enable cbreak mode
  #  nonl()      ## exit new line mode and improve move cursor performance
  #  setCursor(true)

  #  if can_change_color():
  #    ## default is dark
  #    setCursesColor(ColorThemeTable[ColorTheme.dark])

  #  erase()
  #  keyEcho(false)
  #  set_escdelay(25)

proc initWindow*(height, width, y, x: int, color: EditorColorPair): Window =
  result = Window()
  result.y = y
  result.x = x
  result.height = height
  result.width = width
  #result.cursesWindow = initWindow(x, y,width, height)
  #keypad(result.cursesWindow, true)
  #discard wbkgd(result.cursesWindow, ncurses.COLOR_PAIR(color))

proc append*(win: var Window,
              str: string,
              color: EditorColorPair) =

  # Not write when running unit tests
  when not defined unitTest:
    discard
    #win.cursesWindow.append(str)
    #win.cursesWindow.wattron(cint(ncurses.COLOR_PAIR(ord(color))))
    #mvwaddstr(win.cursesWindow, cint(win.y), cint(win.x), str)

    win.x += str.toRunes.width

proc append*(win: var Window,
            runes: seq[Rune],
            color: EditorColorPair) =

  # Not write when running unit tests
  when not defined unitTest:
    discard
    #win.cursesWindow.append($runes)
    #append(win, $str, color)

proc erase*(win: var Window) =
  discard
  #win.cursesWindow.erase
  #werase(win.cursesWindow)
  win.y = 0
  win.x = 0

#proc refresh*(win: Window) {.inline.} = wrefresh(win.cursesWindow)
proc refresh*(win: Window) = discard

#proc move*(win: Window, y, x: int) {.inline.} = mvwin(win.cursesWindow, cint(y), cint(x))
#proc move*(win: Window, y, x: int) {.inline.} = win.cursesWindow.move(y, x)

proc resize*(win: var Window, height, width: int) =
  #wresize(win.cursesWindow, cint(height), cint(width))

  win.height = height
  win.width = width

proc resize*(win: var Window, height, width, y, x: int) =
  #win.cursesWindow.resize(height, width)
  #win.move(y, x)

  win.y = y
  win.x = x

#proc attron*(win: var Window, attributes: Attributes) {.inline.} =
#  win.cursesWindow.wattron(cint(attributes))
#
#proc attroff*(win: var Window, attributes: Attributes) {.inline.} =
#  win.cursesWindow.wattroff(cint(attributes))

# Move cursor position on the terminal.
proc moveCursor*(x, y: int) =
  let cmd = """printf '\033[""" & $y & ";" & $x & "H'"
  discard execShellCmd(cmd)

#proc deleteWindow*(win: var Window) {.inline.} = delwin(win.cursesWindow)

proc getKey*(): Rune =
  let key = illwill.getKey()
  # Ignore a mouse
  case key
    of  None, Mouse:
      return Rune(-1)
    else:
      return Rune(int(key))

# TODO: Remove
proc getKeyBlock*(): Rune =
  while true:
    let key = illwill.getKey()
    case key
      of  None, Mouse:
        continue
      else:
        return Rune(int(key))

  #let key = win.cursesWindow.getKey
  #return toRunes($key)[0]

#  var
#    s = ""
#    len: int
#  block getfirst:
#    let key = wgetch(win.cursesWindow)
#    if Rune(key) == errorKey: return errorKey
#    if not (key <= 0x7F or (0xC2 <= key and key <= 0xF0) or key == 0xF3): return Rune(key)
#    s.add(char(key))
#    len = numberOfBytes(char(key))
#  for i in 0 ..< len-1: s.add(char(wgetch(win.cursesWindow)))
#
#  let runes = toRunes(s)
#  doAssert(runes.len == 1, fmt"runes length shoud be 1.")
#  return runes[0]

proc isEscKey*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.Escape))
# Escape == Shift-Tab
proc isShiftTab*(key: Rune): bool {.inline.} =
  isEscKey(key)

proc isTabkey*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.Tab))

proc isEnterKey*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.Enter))

proc isBackspaceKey*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.Backspace))

proc isDownKey*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.Down))
proc isUpKey*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.Up))
proc isLeftKey*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.Left))
proc isRightKey*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.Right))

proc isHomeKey*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.Home))
proc isEndKey*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.End))

proc isDeleteKey*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.Delete))

proc isPageUpKey*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.PageUp))
proc isPageDownKey*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.PageDown))

proc isControlA*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlA))
proc isControlB*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlB))
proc isControlC*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlC))
proc isControlD*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlD))
proc isControlE*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlE))
proc isControlF*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlF))
proc isControlG*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlG))
proc isControlH*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlH))
# Tab == Ctrl-I
proc isControlI*(key: Rune): bool {.inline.} =
  isTabkey(key)
proc isControlJ*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlJ))
proc isControlK*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlK))
proc isControlL*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlL))
# Enter == Ctrl-M
proc isControlM*(key: Rune): bool {.inline.} =
  isEnterKey(key)
proc isControlN*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlN))
proc isControlO*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlO))
proc isControlP*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlP))
proc isControlQ*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlQ))
proc isControlR*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlR))
proc isControlS*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlS))
proc isControlT*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlT))
proc isControlU*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlU))
proc isControlV*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlV))
proc isControlW*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlW))
proc isControlX*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlX))
proc isControlY*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlY))
proc isControlZ*(key: Rune): bool {.inline.} =
  key == Rune(int(illwill.Key.CtrlZ))

# Ctrl-[
proc isControlLeftSquareBracket*(key: Rune): bool {.inline.} =
  int(key) == 123
