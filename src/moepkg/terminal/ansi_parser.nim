#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

## ANSI escape sequence parser and terminal grid for terminal emulation.
## Implements a VT100/xterm state machine to process PTY output and
## maintain a 2D grid of styled cells.

import std/strutils

type
  ColorKind* = enum
    ckDefault
    ckIndexed # SGR 30-37, 90-97, 38;5;N (0-255)
    ckRgb # SGR 38;2;r;g;b

  TerminalColor* = object
    case kind*: ColorKind
    of ckDefault:
      discard
    of ckIndexed:
      index*: uint8
    of ckRgb:
      r*, g*, b*: uint8

  TerminalAttr* = enum
    taBold
    taDim
    taItalic
    taUnderline
    taBlink
    taReverse
    taStrikethrough

  TerminalCell* = object
    ch*: string # UTF-8 character (empty = space)
    fg*: TerminalColor # Foreground color
    bg*: TerminalColor # Background color
    attrs*: set[TerminalAttr]

  AnsiParserState* = enum
    apsNormal # Normal text processing
    apsEscape # Got ESC (\x1b)
    apsCsi # Got ESC [ (Control Sequence Introducer)
    apsOsc # Got ESC ] (Operating System Command)
    apsStringSeq # Consuming DCS/APC/PM/SOS string until ST

  TerminalGrid* = ref object
    cells*: seq[seq[TerminalCell]] # [row][col]
    cols*: int
    rows*: int
    cursorRow*: int
    cursorCol*: int
    cursorVisible*: bool
    # Scrollback
    scrollbackBuffer*: seq[seq[TerminalCell]]
    maxScrollback*: int
    # Current SGR state
    currentFg*: TerminalColor
    currentBg*: TerminalColor
    currentAttrs*: set[TerminalAttr]
    # Parser state
    parserState*: AnsiParserState
    escapeBuffer*: string
    # Flags
    needsRedraw*: bool
    title*: string

const DefaultMaxScrollback* = 10000

proc defaultColor*(): TerminalColor =
  TerminalColor(kind: ckDefault)

proc indexedColor*(idx: uint8): TerminalColor =
  TerminalColor(kind: ckIndexed, index: idx)

proc rgbColor*(r, g, b: uint8): TerminalColor =
  TerminalColor(kind: ckRgb, r: r, g: g, b: b)

proc defaultCell*(): TerminalCell =
  TerminalCell(ch: "", fg: defaultColor(), bg: defaultColor(), attrs: {})

proc newRow(cols: int): seq[TerminalCell] =
  result = newSeq[TerminalCell](cols)
  for i in 0 ..< cols:
    result[i] = defaultCell()

proc newTerminalGrid*(cols, rows: int): TerminalGrid =
  result = TerminalGrid(
    cols: cols,
    rows: rows,
    cursorRow: 0,
    cursorCol: 0,
    cursorVisible: true,
    scrollbackBuffer: @[],
    maxScrollback: DefaultMaxScrollback,
    currentFg: defaultColor(),
    currentBg: defaultColor(),
    currentAttrs: {},
    parserState: apsNormal,
    escapeBuffer: "",
    needsRedraw: false,
    title: "",
  )
  result.cells = newSeq[seq[TerminalCell]](rows)
  for i in 0 ..< rows:
    result.cells[i] = newRow(cols)

proc resize*(grid: TerminalGrid, cols, rows: int) =
  ## Resize the grid, preserving content where possible.
  let
    oldRows = grid.rows
    oldCols = grid.cols

  # Create new cells grid
  var newCells = newSeq[seq[TerminalCell]](rows)
  for r in 0 ..< rows:
    newCells[r] = newRow(cols)
    if r < oldRows:
      for c in 0 ..< min(cols, oldCols):
        newCells[r][c] = grid.cells[r][c]

  grid.cells = newCells
  grid.cols = cols
  grid.rows = rows

  # Clamp cursor
  grid.cursorRow = min(grid.cursorRow, rows - 1)
  grid.cursorCol = min(grid.cursorCol, cols - 1)
  grid.needsRedraw = true

proc scrollUp(grid: TerminalGrid) =
  ## Scroll the grid up by one line: top line goes to scrollback,
  ## new blank line at bottom.
  if grid.rows == 0:
    return

  # Push top line to scrollback
  grid.scrollbackBuffer.add(grid.cells[0])
  if grid.scrollbackBuffer.len > grid.maxScrollback:
    grid.scrollbackBuffer.delete(0)

  # Shift rows up
  for r in 0 ..< grid.rows - 1:
    grid.cells[r] = grid.cells[r + 1]

  # New blank line at bottom
  grid.cells[grid.rows - 1] = newRow(grid.cols)

proc putChar(grid: TerminalGrid, ch: string) =
  ## Place a character at the current cursor position, advancing the cursor.
  if grid.cursorRow < 0 or grid.cursorRow >= grid.rows:
    return

  # Wrap if at right edge
  if grid.cursorCol >= grid.cols:
    grid.cursorCol = 0
    grid.cursorRow += 1
    if grid.cursorRow >= grid.rows:
      grid.scrollUp()
      grid.cursorRow = grid.rows - 1

  grid.cells[grid.cursorRow][grid.cursorCol] = TerminalCell(
    ch: ch, fg: grid.currentFg, bg: grid.currentBg, attrs: grid.currentAttrs
  )
  grid.cursorCol += 1

proc parseCsiParams(s: string): seq[int] =
  ## Parse CSI parameter string "1;2;3" into sequence of ints.
  ## Empty or missing params default to 0.
  result = @[]
  if s.len == 0:
    return
  for part in s.split(';'):
    if part.len == 0:
      result.add(0)
    else:
      try:
        result.add(parseInt(part))
      except ValueError:
        result.add(0)

proc applySgr(grid: TerminalGrid, params: seq[int]) =
  ## Apply SGR (Select Graphic Rendition) parameters.
  var i = 0
  let p =
    if params.len == 0:
      @[0]
    else:
      params

  while i < p.len:
    let code = p[i]
    case code
    of 0:
      # Reset
      grid.currentFg = defaultColor()
      grid.currentBg = defaultColor()
      grid.currentAttrs = {}
    of 1:
      grid.currentAttrs.incl(taBold)
    of 2:
      grid.currentAttrs.incl(taDim)
    of 3:
      grid.currentAttrs.incl(taItalic)
    of 4:
      grid.currentAttrs.incl(taUnderline)
    of 5:
      grid.currentAttrs.incl(taBlink)
    of 7:
      grid.currentAttrs.incl(taReverse)
    of 9:
      grid.currentAttrs.incl(taStrikethrough)
    of 22:
      grid.currentAttrs.excl(taBold)
      grid.currentAttrs.excl(taDim)
    of 23:
      grid.currentAttrs.excl(taItalic)
    of 24:
      grid.currentAttrs.excl(taUnderline)
    of 25:
      grid.currentAttrs.excl(taBlink)
    of 27:
      grid.currentAttrs.excl(taReverse)
    of 29:
      grid.currentAttrs.excl(taStrikethrough)
    of 30 .. 37:
      grid.currentFg = indexedColor(uint8(code - 30))
    of 38:
      # Extended foreground: 38;5;N or 38;2;r;g;b
      if i + 1 < p.len:
        if p[i + 1] == 5 and i + 2 < p.len:
          grid.currentFg = indexedColor(uint8(p[i + 2]))
          i += 2
        elif p[i + 1] == 2 and i + 4 < p.len:
          grid.currentFg = rgbColor(uint8(p[i + 2]), uint8(p[i + 3]), uint8(p[i + 4]))
          i += 4
    of 39:
      grid.currentFg = defaultColor()
    of 40 .. 47:
      grid.currentBg = indexedColor(uint8(code - 40))
    of 48:
      # Extended background: 48;5;N or 48;2;r;g;b
      if i + 1 < p.len:
        if p[i + 1] == 5 and i + 2 < p.len:
          grid.currentBg = indexedColor(uint8(p[i + 2]))
          i += 2
        elif p[i + 1] == 2 and i + 4 < p.len:
          grid.currentBg = rgbColor(uint8(p[i + 2]), uint8(p[i + 3]), uint8(p[i + 4]))
          i += 4
    of 49:
      grid.currentBg = defaultColor()
    of 90 .. 97:
      grid.currentFg = indexedColor(uint8(code - 90 + 8))
    of 100 .. 107:
      grid.currentBg = indexedColor(uint8(code - 100 + 8))
    else:
      discard
    i += 1

proc processCsi(grid: TerminalGrid, buf: string) =
  ## Process a CSI sequence: ESC [ <params> <final byte>
  ## buf contains everything after "ESC [" including the final byte.
  if buf.len == 0:
    return

  let finalByte = buf[^1]
  let paramStr = buf[0 ..< buf.len - 1]

  # Handle private mode sequences (ESC [ ? ...)
  if paramStr.len > 0 and paramStr[0] == '?':
    let privParams = parseCsiParams(paramStr[1 .. ^1])
    case finalByte
    of 'h':
      # Set mode
      for p in privParams:
        case p
        of 25:
          grid.cursorVisible = true
        else:
          discard
    of 'l':
      # Reset mode
      for p in privParams:
        case p
        of 25:
          grid.cursorVisible = false
        else:
          discard
    else:
      discard
    return

  let params = parseCsiParams(paramStr)

  case finalByte
  of 'm':
    # SGR - Select Graphic Rendition
    grid.applySgr(params)
  of 'A':
    # Cursor Up
    let n =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    grid.cursorRow = max(0, grid.cursorRow - n)
  of 'B':
    # Cursor Down
    let n =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    grid.cursorRow = min(grid.rows - 1, grid.cursorRow + n)
  of 'C':
    # Cursor Forward
    let n =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    grid.cursorCol = min(grid.cols - 1, grid.cursorCol + n)
  of 'D':
    # Cursor Back
    let n =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    grid.cursorCol = max(0, grid.cursorCol - n)
  of 'H', 'f':
    # Cursor Position
    let
      row =
        if params.len > 0 and params[0] > 0:
          params[0] - 1
        else:
          0
      col =
        if params.len > 1 and params[1] > 0:
          params[1] - 1
        else:
          0
    grid.cursorRow = clamp(row, 0, grid.rows - 1)
    grid.cursorCol = clamp(col, 0, grid.cols - 1)
  of 'J':
    # Erase in Display
    let mode =
      if params.len > 0:
        params[0]
      else:
        0
    case mode
    of 0:
      # Erase from cursor to end of screen
      for c in grid.cursorCol ..< grid.cols:
        grid.cells[grid.cursorRow][c] = defaultCell()
      for r in grid.cursorRow + 1 ..< grid.rows:
        grid.cells[r] = newRow(grid.cols)
    of 1:
      # Erase from beginning of screen to cursor
      for r in 0 ..< grid.cursorRow:
        grid.cells[r] = newRow(grid.cols)
      for c in 0 .. grid.cursorCol:
        if c < grid.cols:
          grid.cells[grid.cursorRow][c] = defaultCell()
    of 2, 3:
      # Erase entire screen
      for r in 0 ..< grid.rows:
        grid.cells[r] = newRow(grid.cols)
    else:
      discard
  of 'K':
    # Erase in Line
    let mode =
      if params.len > 0:
        params[0]
      else:
        0
    case mode
    of 0:
      # Erase from cursor to end of line
      for c in grid.cursorCol ..< grid.cols:
        grid.cells[grid.cursorRow][c] = defaultCell()
    of 1:
      # Erase from beginning of line to cursor
      for c in 0 .. min(grid.cursorCol, grid.cols - 1):
        grid.cells[grid.cursorRow][c] = defaultCell()
    of 2:
      # Erase entire line
      grid.cells[grid.cursorRow] = newRow(grid.cols)
    else:
      discard
  of 'S':
    # Scroll Up
    let n =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    for _ in 0 ..< n:
      grid.scrollUp()
  of 'T':
    # Scroll Down
    let n =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    for _ in 0 ..< n:
      if grid.rows > 0:
        # Shift rows down, insert blank at top
        for r in countdown(grid.rows - 1, 1):
          grid.cells[r] = grid.cells[r - 1]
        grid.cells[0] = newRow(grid.cols)
  of 'd':
    # Vertical Position Absolute
    let row =
      if params.len > 0 and params[0] > 0:
        params[0] - 1
      else:
        0
    grid.cursorRow = clamp(row, 0, grid.rows - 1)
  of 'G':
    # Cursor Character Absolute
    let col =
      if params.len > 0 and params[0] > 0:
        params[0] - 1
      else:
        0
    grid.cursorCol = clamp(col, 0, grid.cols - 1)
  of 'E':
    # Cursor Next Line
    let n =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    grid.cursorRow = min(grid.rows - 1, grid.cursorRow + n)
    grid.cursorCol = 0
  of 'F':
    # Cursor Previous Line
    let n =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    grid.cursorRow = max(0, grid.cursorRow - n)
    grid.cursorCol = 0
  of 'X':
    # Erase Character
    let n =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    for c in grid.cursorCol ..< min(grid.cursorCol + n, grid.cols):
      grid.cells[grid.cursorRow][c] = defaultCell()
  of 'P':
    # Delete Character
    let n =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    let row = grid.cursorRow
    for c in grid.cursorCol ..< grid.cols - n:
      if c + n < grid.cols:
        grid.cells[row][c] = grid.cells[row][c + n]
    for c in max(grid.cursorCol, grid.cols - n) ..< grid.cols:
      grid.cells[row][c] = defaultCell()
  of '@':
    # Insert Character (shift right)
    let n =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    let row = grid.cursorRow
    for c in countdown(grid.cols - 1, grid.cursorCol + n):
      grid.cells[row][c] = grid.cells[row][c - n]
    for c in grid.cursorCol ..< min(grid.cursorCol + n, grid.cols):
      grid.cells[row][c] = defaultCell()
  of 'L':
    # Insert Line
    let n =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    for _ in 0 ..< n:
      if grid.cursorRow < grid.rows:
        for r in countdown(grid.rows - 1, grid.cursorRow + 1):
          grid.cells[r] = grid.cells[r - 1]
        grid.cells[grid.cursorRow] = newRow(grid.cols)
  of 'M':
    # Delete Line
    let n =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    for _ in 0 ..< n:
      if grid.cursorRow < grid.rows:
        for r in grid.cursorRow ..< grid.rows - 1:
          grid.cells[r] = grid.cells[r + 1]
        grid.cells[grid.rows - 1] = newRow(grid.cols)
  of 'r':
    # Set Scrolling Region (DECSTSR) - simplified: just reset cursor
    grid.cursorRow = 0
    grid.cursorCol = 0
  else:
    discard

proc processOutput*(grid: TerminalGrid, data: string) =
  ## Process raw PTY output through the ANSI parser state machine.
  ## Updates the grid cells, cursor position, and colors.
  var i = 0
  while i < data.len:
    let ch = data[i]

    case grid.parserState
    of apsNormal:
      case ch
      of '\x1b':
        grid.parserState = apsEscape
        grid.escapeBuffer = ""
      of '\r':
        grid.cursorCol = 0
      of '\n':
        grid.cursorRow += 1
        if grid.cursorRow >= grid.rows:
          grid.scrollUp()
          grid.cursorRow = grid.rows - 1
      of '\t':
        # Tab: move to next tab stop (every 8 columns)
        let nextTab = ((grid.cursorCol div 8) + 1) * 8
        grid.cursorCol = min(nextTab, grid.cols - 1)
      of '\b':
        # Backspace
        if grid.cursorCol > 0:
          grid.cursorCol -= 1
      of '\x07':
        # Bell - ignore
        discard
      of '\x00' .. '\x06', '\x0e' .. '\x1a', '\x1c' .. '\x1f':
        # Other control characters - ignore
        discard
      else:
        # Regular character (including multi-byte UTF-8)
        var runeStr: string
        if (ch.ord and 0x80) == 0:
          # ASCII
          runeStr = $ch
        else:
          # Multi-byte UTF-8: determine length and extract
          let byteLen =
            if (ch.ord and 0xE0) == 0xC0:
              2
            elif (ch.ord and 0xF0) == 0xE0:
              3
            elif (ch.ord and 0xF8) == 0xF0:
              4
            else:
              1
          if i + byteLen <= data.len:
            runeStr = data[i ..< i + byteLen]
            i += byteLen - 1 # -1 because the main loop increments
          else:
            runeStr = "?"
        grid.putChar(runeStr)
    of apsEscape:
      case ch
      of '[':
        grid.parserState = apsCsi
        grid.escapeBuffer = ""
      of ']':
        grid.parserState = apsOsc
        grid.escapeBuffer = ""
      of '(':
        # Designate character set - skip next byte
        i += 1
        grid.parserState = apsNormal
      of ')', '*', '+':
        # Designate character set - skip next byte
        i += 1
        grid.parserState = apsNormal
      of 'M':
        # Reverse Index (scroll down)
        if grid.cursorRow == 0:
          # Insert line at top
          for r in countdown(grid.rows - 1, 1):
            grid.cells[r] = grid.cells[r - 1]
          grid.cells[0] = newRow(grid.cols)
        else:
          grid.cursorRow -= 1
        grid.parserState = apsNormal
      of '7':
        # Save cursor - simplified (no-op for now)
        grid.parserState = apsNormal
      of '8':
        # Restore cursor - simplified (no-op for now)
        grid.parserState = apsNormal
      of 'c':
        # Reset terminal
        grid.currentFg = defaultColor()
        grid.currentBg = defaultColor()
        grid.currentAttrs = {}
        grid.cursorRow = 0
        grid.cursorCol = 0
        for r in 0 ..< grid.rows:
          grid.cells[r] = newRow(grid.cols)
        grid.parserState = apsNormal
      of '#':
        # DEC line attribute sequences (e.g., ESC # 8) - skip next byte
        if i + 1 < data.len:
          i += 1
        grid.parserState = apsNormal
      of 'P', '_', '^', 'X':
        # String-type sequences: DCS (P), APC (_), PM (^), SOS (X)
        # Consume everything until ST (ESC \) or BEL
        grid.parserState = apsStringSeq
        grid.escapeBuffer = ""
      of '=', '>':
        # Application / Normal keypad mode - ignore
        grid.parserState = apsNormal
      else:
        # Unknown escape sequence, return to normal
        grid.parserState = apsNormal
    of apsCsi:
      if ch >= '\x40' and ch <= '\x7e':
        # Final byte of CSI sequence
        grid.escapeBuffer.add(ch)
        grid.processCsi(grid.escapeBuffer)
        grid.parserState = apsNormal
      elif ch >= '\x20' and ch <= '\x3f':
        # Parameter or intermediate byte
        grid.escapeBuffer.add(ch)
      else:
        # Invalid CSI sequence, abort
        grid.parserState = apsNormal
    of apsOsc:
      if ch == '\x07' or ch == '\x1b':
        # End of OSC sequence (BEL or ESC)
        # Parse title: "0;title" or "2;title"
        let oscStr = grid.escapeBuffer
        if oscStr.len > 2 and oscStr[1] == ';':
          let oscType = oscStr[0]
          if oscType in {'0', '2'}:
            grid.title = oscStr[2 .. ^1]
        if ch == '\x1b':
          # OSC terminated by ESC \ (ST), skip the backslash
          if i + 1 < data.len and data[i + 1] == '\\':
            i += 1
        grid.parserState = apsNormal
      else:
        grid.escapeBuffer.add(ch)
    of apsStringSeq:
      # Consuming DCS/APC/PM/SOS string until ST (ESC \) or BEL
      if ch == '\x1b':
        # Possible start of ST (ESC \)
        if i + 1 < data.len and data[i + 1] == '\\':
          i += 1 # Skip the backslash
        grid.parserState = apsNormal
      elif ch == '\x07':
        # BEL also terminates string sequences
        grid.parserState = apsNormal
      else:
        # Consume and discard the string content
        discard

    i += 1
  grid.needsRedraw = true

proc toPlainText*(grid: TerminalGrid): string =
  ## Convert the current grid to plain text (no colors).
  ## Useful for creating a TextBuffer snapshot for Terminal-Normal mode.
  var lines: seq[string] = @[]

  proc stripTrailingSpaces(line: string): string =
    var endIdx = line.len
    while endIdx > 0 and line[endIdx - 1] == ' ':
      dec endIdx
    line[0 ..< endIdx]

  # Include scrollback first
  for row in grid.scrollbackBuffer:
    var line = ""
    for cell in row:
      if cell.ch.len > 0:
        line.add(cell.ch)
      else:
        line.add(' ')
    lines.add(stripTrailingSpaces(line))

  # Then current grid (only up to the last row with content)
  var lastNonEmptyRow = -1
  for r in 0 ..< grid.rows:
    for c in 0 ..< grid.cols:
      if grid.cells[r][c].ch.len > 0:
        lastNonEmptyRow = r
        break

  if lastNonEmptyRow >= 0:
    for r in 0 .. lastNonEmptyRow:
      var line = ""
      for c in 0 ..< grid.cols:
        let cell = grid.cells[r][c]
        if cell.ch.len > 0:
          line.add(cell.ch)
        else:
          line.add(' ')
      lines.add(stripTrailingSpaces(line))

  if lines.len == 0:
    return ""
  lines.join("\n")
