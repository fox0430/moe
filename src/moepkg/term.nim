import std/[terminal, assertions, strutils, os, strformat]
import illwill
export illwill.Key, illwill.showCursor, illwill.hideCursor

type
  CursorPosition* = tuple[x, y: int]

  # Hex color code
  ColorCode* = array[6, char]

  ColorPair* = tuple[fg, bg: ColorCode]

  TermWindow* = object
    tb: TerminalBuffer
    x: int
    y: int
    w: int
    h: int
    buffer: seq[string]
    isCurosr: bool
    colorPair: ColorPair
    cursorPosition: CursorPosition

proc exitUi*() {.noconv.} =
  illwillDeinit()
  showCursor()

proc startUi*() =
  illwillInit(fullscreen = true)
  setControlCHook(exitUi)

proc initColorCode*(str: string): ColorCode =
  assert(str.len == 6)

  var code: ColorCode
  for i, c in str:
    code[i] = c

  return code

proc initColorPair*(fgColorStr, bgColorStr: string): ColorPair {.inline.} =
  result = (
    fg: initColorCode(fgColorStr),
    bg: initColorCode(bgColorStr))

proc initWindow*(x, y, w, h: int): TermWindow =
  let
    fgStr = "ffffff"
    # TODO: Fix to the terminal default color?.
    bgStr = "000000"

  result = TermWindow(
    tb: newTerminalBuffer(terminalWidth(), terminalHeight()),
    x: x,
    y: y,
    w: w,
    h: h,
    colorPair: initColorPair(fgStr, bgStr),
    buffer: newSeq[string](h))

  for i in 0 ..< h:
    result.buffer[i] = " ".repeat(w)

proc hexStrToIntStr(hexStr: string): string =
  result = $(fromHex[int](hexStr))

proc setTerminalBackgroundColor*(code: ColorCode) =
  let
    r = hexStrToIntStr(code[0] & code[1])
    g = hexStrToIntStr(code[2] & code[3])
    b = hexStrToIntStr(code[4] & code[5])

  let cmd = """printf "\x1b[48;2;""" & fmt("{$r};{$g};{$b}") & """m""""
  if execShellCmd(cmd) != 0:
    exitUi()
    echo fmt "Error: Failed to set the terminal color: (r: {$r}, g: {$g}, b: {$b})"
    quit(1)

proc setTerminalForegroundColor*(code: ColorCode) =
  let
    r = hexStrToIntStr(code[0] & code[1])
    g = hexStrToIntStr(code[2] & code[3])
    b = hexStrToIntStr(code[4] & code[5])

  let cmd = """printf "\x1b[38;2;""" & fmt("{$r};{$g};{$b}") & """m""""
  if execShellCmd(cmd) != 0:
    exitUi()
    echo fmt "Error: Failed to set the terminal color: (r: {$r}, g: {$g}, b: {$b})"
    quit(1)

proc resetTerminalOutPut*() {.inline.} =
  if execShellCmd("""printf "\x1b[0m\n"""")  != 0:
    exitUi()
    echo fmt "Error: Failed to reset terminal output."
    quit(1)

proc update(win: var TermWindow) =
  var bufIndex = 0
  for y in win.y ..< win.y + win.h:
    win.tb.write(win.x, win.y + y, win.buffer[bufIndex])
    bufIndex.inc

  win.tb.display

proc write*(win: var TermWindow, x, y: int, buf: string) =
  assert(x >= 0 and x <= win.x + win.w and y >= 0 and y <= win.y + win.h)

  var bufIndex = 0
  for i in x ..< min(win.w, buf.len):
    win.buffer[y][i] = buf[bufIndex]
    bufIndex.inc

  win.update

proc append*(win: var TermWindow, str: string) =
  let line = win.cursorPosition.y
  win.buffer[line] &= str
  win.cursorPosition.x = win.buffer[line].len

  win.update

proc erase*(win: var TermWindow) =
  for i in 0 ..< win.h:
    win.buffer[i] = " ".repeat(win.w)

  win.cursorPosition.x = 0
  win.cursorPosition.y = 0

  win.update

proc move*(win: var TermWindow, x, y: int) =
  assert(x >= 0 and y >= 0)

  win.x = x
  win.y = y

  eraseScreen()
  win.update

proc resize*(win: var TermWindow, w, h: int) =
  assert(w >= 0 and h >= 0)

  win.w = w
  win.h = h

  eraseScreen()
  win.update

proc moveCursor*(win: var TermWindow) =
  win.tb.setCursorPos(win.cursorPosition.x, win.cursorPosition.y)

proc moveCursor*(win: var TermWindow, x, y: int) =
  assert(x >= 0 and x <= win.w and y >= 0 and y <= win.h)

  win.cursorPosition.x = x
  win.cursorPosition.y = y
  win.tb.setCursorPos(win.cursorPosition.x, win.cursorPosition.y)

proc getKey*(win: var TermWindow): Key =
  win.moveCursor
  result = getKey()
