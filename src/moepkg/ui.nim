import std/[osproc, termios, strutils, os, terminal, strformat, options, logging, posix]
import pkg/termtools
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

type
  Key* = int

const
  NONE_KEY* = '\0'.ru

  CTRL_A* = 1.ru
  CTRL_B* = 2.ru
  CTRL_C* = 3.ru
  CTRL_D* = 4.ru
  CTRL_E* = 5.ru
  CTRL_F* = 6.ru
  CTRL_G* = 7.ru
  CTRL_H* = 8.ru
  CTRL_I* = 9.ru
  CTRL_J* = 10.ru
  CTRL_K* = 11.ru
  CTRL_L* = 12.ru
  CTRL_M* = 13.ru
  CTRL_N* = 14.ru
  CTRL_O* = 15.ru
  CTRL_P* = 16.ru
  CTRL_Q* = 17.ru
  CTRL_R* = 18.ru
  CTRL_S* = 19.ru
  CTRL_T* = 20.ru
  CTRL_U* = 21.ru
  CTRL_V* = 22.ru
  CTRL_W* = 23.ru
  CTRL_X* = 24.ru
  CTRL_Y* = 25.ru
  CTRL_Z* = 26.ru

  KEY_TAB* = 9.ru
  KEY_ENTER* = 13.ru
  KEY_ESC* = 27.ru
  KEY_BACKSPACE* = 127.ru

  KEY_DOWN* = 1000.ru
  KEY_UP* = 1001.ru
  KEY_RIGHT* = 1002.ru
  KEY_LEFT* = 1003.ru

  KEY_HOME* = 1004.ru
  KEY_END* = 1005.ru
  KEY_DELETE* = 1006.ru

  KEY_PAGEUP* = 1007.ru
  KEY_PAGEDOWN* = 1008.ru

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
  orig_termios*: Termios
  pressCtrlC* = false
  isResizedWindow* = false

  displayBuffer*: seq[string]

const
  SIGWINCH = cint(28)

# SIGWINCH will be sent when the terminal emulator is resized on the X11.
onSignal(SIGWINCH):
  isResizedWindow = true

proc setBkinkingIbeamCursor*() =
  stdout.write("""\e[5 q""")
  stdout.flushFile

proc setNoneBlinkingIbeamCursor*() =
  stdout.write("""\e[6 q""")
  stdout.flushFile

proc setBlinkingBlockCursor*() =
  stdout.write("""\e[1 q""")
  stdout.flushFile

proc setNoneBlinkingBlockCursor*() =
  stdout.write("""\e[2 q""")
  stdout.flushFile

proc unhideCursor*() =
  stdout.write("""\e[?25h""")
  stdout.flushFile

proc changeCursorType*(cursorType: CursorType) =
  case cursorType
    of blinkBlock: setBlinkingBlockCursor()
    of noneBlinkBlock: setNoneBlinkingBlockCursor()
    of blinkIbeam: setBkinkingIbeamCursor()
    of noneBlinkIbeam: setNoneBlinkingIbeamCursor()

proc enableRawMode*() =
  discard tcgetattr(STDIN_FILENO, addr(orig_termios))

  var raw = orig_termios
  raw.c_iflag = raw.c_iflag and not (IXON)
  raw.c_iflag = raw.c_iflag and not (ICRNL or IXON)
  raw.c_oflag = raw.c_oflag and not (OPOST)
  raw.c_lflag = raw.c_lflag and not (ECHO or IEXTEN)
  raw.c_cc[VMIN] = char(0);
  raw.c_cc[VTIME] = char(0.1);

  discard tcsetattr(STDIN_FILENO, TCSAFLUSH, addr(raw))

proc disableRawMode*() =
  discard tcsetattr(STDIN_FILENO, TCSAFLUSH, addr(orig_termios))

# if press ctrl-c key, set true in setControlCHook()
proc disableControlC*() {.inline.} =
  setControlCHook(proc() {.noconv.} = pressCtrlC = true)

#proc restoreTerminalModes*() {.inline.} = reset_prog_mode()
#
#proc saveCurrentTerminalModes*() {.inline.} = def_prog_mode()

proc setCursor*(cursor: bool) =
  if cursor:
    showCursor()
  else:
    hideCursor()

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

proc exitUi*() {.noconv.} =
  disableRawMode()
  terminal.eraseScreen()
  showCursor()

proc startUi*() =
  setControlCHook(exitUi)
  enableRawMode()

# Reset the terminal color.
proc resetColor() =
  stdout.write("""\033[0m""")
  stdout.flushFile

# Clear displayBuffer and screen.
proc eraseScreen*() =
  displayBuffer = @[]
  terminal.eraseScreen()

proc write*(x, y: int, buf: string) =
  # Don't write when running unit tests
  when not defined unitTest:
    #applyColorPair(color)
    setCursorPos(x, y)
    stdout.write(buf)

# TODO: Fix append
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

# TODO: Fix append
proc append*(win: var Window,
            runes: seq[Rune],
            color: EditorColorPair) =

  # Not write when running unit tests
  when not defined unitTest:
    discard
    #win.cursesWindow.append($runes)
    #append(win, $str, color)

# Write displayBuffer to the screen.
proc display*() =
  for i, l in displayBuffer:
    write(0, i, l)

#proc move*(win: Window, y, x: int) {.inline.} = mvwin(win.cursesWindow, cint(y), cint(x))
#proc move*(win: Window, y, x: int) {.inline.} = win.cursesWindow.move(y, x)

# Move cursor position on the terminal.
proc moveCursor*(x, y: int) {.inline.} =
  setCursorPos(x, y)

#proc deleteWindow*(win: var Window) {.inline.} = delwin(win.cursesWindow)

proc kbhit(): bool =
  var
    tv = Timeval(tv_sec: 0.Time, tv_usec: 0.Suseconds)
    tfs: TFDSet
  FD_ZERO(tfs);
  FD_SET(0, tfs)

  return select(1, tfs.addr, nil, nil, tv.addr) > 0;

proc read(): Rune =
  var c: char
  # TODO: Add error handling?
  discard read(0, c.addr, sizeof(c))
  return c.ru

proc getkey*(): Rune =
  let key = read()
  if key == KEY_ESC and read() == '['.ru:
    case read():
      of 'A'.ru:
        return KEY_UP.Rune
      of 'B'.ru:
        return KEY_DOWN.Rune
      of 'C'.ru:
        return KEY_RIGHT.Rune
      of 'D'.ru:
        return KEY_LEFT.Rune
      of '3'.ru:
        return KEY_DELETE.Rune
      of '5'.ru:
        return KEY_PAGEUP.Rune
      of '6'.ru:
        return KEY_PAGEDOWN.Rune
      of '7'.ru:
        return KEY_HOME.Rune
      of '8'.ru:
        return KEY_END.Rune
      else:
        discard
  else:
    return key

proc isEscKey*(key: Rune): bool {.inline.} =
  key == KEY_ESC

# Escape == Shift-Tab
proc isShiftTab*(key: Rune): bool {.inline.} =
  isEscKey(key)

proc isTabkey*(key: Rune): bool {.inline.} =
  key == KEY_TAB

proc isEnterKey*(key: Rune): bool {.inline.} =
  key == KEY_ENTER

proc isBackspaceKey*(key: Rune): bool {.inline.} =
  key == KEY_BACKSPACE

proc isUpKey*(key: Rune): bool {.inline.} =
  key == KEY_UP
proc isDownKey*(key: Rune): bool {.inline.} =
  key == KEY_DOWN
proc isRightKey*(key: Rune): bool {.inline.} =
  key == KEY_RIGHT
proc isLeftKey*(key: Rune): bool {.inline.} =
  key == KEY_LEFT

proc isHomeKey*(key: Rune): bool {.inline.} =
  key == KEY_HOME
proc isEndKey*(key: Rune): bool {.inline.} =
  key == KEY_END

proc isDeleteKey*(key: Rune): bool {.inline.} =
  key == KEY_DELETE

proc isPageUpKey*(key: Rune): bool {.inline.} =
  key == KEY_PAGEUP
proc isPageDownKey*(key: Rune): bool {.inline.} =
  key == KEY_PAGEDOWN

proc isControlA*(key: Rune): bool {.inline.} =
  key == CTRL_A
proc isControlB*(key: Rune): bool {.inline.} =
  key == CTRL_B
proc isControlC*(key: Rune): bool {.inline.} =
  key == CTRL_C
proc isControlD*(key: Rune): bool {.inline.} =
  key == CTRL_D
proc isControlE*(key: Rune): bool {.inline.} =
  key == CTRL_E
proc isControlF*(key: Rune): bool {.inline.} =
  key == CTRL_F
proc isControlG*(key: Rune): bool {.inline.} =
  key == CTRL_G
proc isControlH*(key: Rune): bool {.inline.} =
  key == CTRL_H
# Tab == Ctrl-I
proc isControlI*(key: Rune): bool {.inline.} =
  isTabkey(key)
proc isControlJ*(key: Rune): bool {.inline.} =
  key == CTRL_J
proc isControlK*(key: Rune): bool {.inline.} =
  key == CTRL_K
proc isControlL*(key: Rune): bool {.inline.} =
  key == CTRL_L
# Enter == Ctrl-M
proc isControlM*(key: Rune): bool {.inline.} =
  isEnterKey(key)
proc isControlN*(key: Rune): bool {.inline.} =
  key == CTRL_N
proc isControlO*(key: Rune): bool {.inline.} =
  key == CTRL_O
proc isControlP*(key: Rune): bool {.inline.} =
  key == CTRL_P
proc isControlQ*(key: Rune): bool {.inline.} =
  key == CTRL_Q
proc isControlR*(key: Rune): bool {.inline.} =
  key == CTRL_R
proc isControlS*(key: Rune): bool {.inline.} =
  key == CTRL_S
proc isControlT*(key: Rune): bool {.inline.} =
  key == CTRL_T
proc isControlU*(key: Rune): bool {.inline.} =
  key == CTRL_U
proc isControlV*(key: Rune): bool {.inline.} =
  key == CTRL_V
proc isControlW*(key: Rune): bool {.inline.} =
  key == CTRL_W
proc isControlX*(key: Rune): bool {.inline.} =
  key == CTRL_X
proc isControlY*(key: Rune): bool {.inline.} =
  key == CTRL_Y
proc isControlZ*(key: Rune): bool {.inline.} =
  key == CTRL_Z

# Ctrl-[ == Enter
proc isControlLeftSquareBracket*(key: Rune): bool {.inline.} =
  isEnterKey(key)
