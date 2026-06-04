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

import std/[strutils, deques, unicode]

import ../unicode_utils

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
    widePadding*: bool # Second cell of a wide (CJK) character

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
    scrollbackBuffer*: Deque[seq[TerminalCell]]
    maxScrollback*: int
    # Current SGR state
    currentFg*: TerminalColor
    currentBg*: TerminalColor
    currentAttrs*: set[TerminalAttr]
    # Parser state
    parserState*: AnsiParserState
    escapeBuffer*: string
    utf8Buffer*: string # Incomplete UTF-8 bytes from previous read
    # Responses to write back to PTY (e.g. DA1, DA2, DSR replies)
    pendingResponses*: seq[string]
    # Alternate screen buffer (DEC private modes 47/1047/1049)
    altScreenActive*: bool
    inactiveCells: seq[seq[TerminalCell]] # The other screen buffer while one is active
    # Scrolling region (DECSTBM), 0-based inclusive
    scrollTop*: int
    scrollBottom*: int
    # Saved cursor/SGR state (DECSC/DECRC via ESC 7/8, modes 1048/1049)
    savedCursorRow*: int
    savedCursorCol*: int
    savedFg*: TerminalColor
    savedBg*: TerminalColor
    savedAttrs*: set[TerminalAttr]
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

proc charDisplayWidth(ch: string): int =
  ## Return the display width of a UTF-8 character (1 for narrow, 2 for wide/CJK).
  if ch.len == 0:
    return 1
  runeWidth(ch.runeAt(0))

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
    scrollbackBuffer: initDeque[seq[TerminalCell]](),
    maxScrollback: DefaultMaxScrollback,
    currentFg: defaultColor(),
    currentBg: defaultColor(),
    currentAttrs: {},
    parserState: apsNormal,
    escapeBuffer: "",
    pendingResponses: @[],
    altScreenActive: false,
    inactiveCells: @[],
    scrollTop: 0,
    scrollBottom: rows - 1,
    needsRedraw: false,
    title: "",
  )
  result.cells = newSeq[seq[TerminalCell]](rows)
  for i in 0 ..< rows:
    result.cells[i] = newRow(cols)

proc resizeCells(
    old: seq[seq[TerminalCell]], oldCols, oldRows, cols, rows: int
): seq[seq[TerminalCell]] =
  ## Resize a single cell grid, preserving content where possible.
  result = newSeq[seq[TerminalCell]](rows)
  for r in 0 ..< rows:
    result[r] = newRow(cols)
    if r < oldRows:
      for c in 0 ..< min(cols, oldCols):
        result[r][c] = old[r][c]
      # Clean up wide char split at the new right edge:
      # If the cell just past the boundary (old col `cols`) was a padding cell,
      # its main cell at cols-1 has lost its padding — clear it.
      if cols < oldCols and cols > 0 and old[r][cols].widePadding:
        result[r][cols - 1] = defaultCell()

proc resize*(grid: TerminalGrid, cols, rows: int) =
  ## Resize the grid, preserving content where possible.
  let
    oldRows = grid.rows
    oldCols = grid.cols

  grid.cells = resizeCells(grid.cells, oldCols, oldRows, cols, rows)
  # Keep the saved (inactive) screen buffer in sync so restoring it after an
  # alternate-screen exit doesn't index out of bounds at the new size.
  if grid.inactiveCells.len > 0:
    grid.inactiveCells = resizeCells(grid.inactiveCells, oldCols, oldRows, cols, rows)

  grid.cols = cols
  grid.rows = rows

  # Resizing resets the scrolling region to the full screen (xterm behavior).
  grid.scrollTop = 0
  grid.scrollBottom = rows - 1

  # Clamp cursors (live and saved) to the new bounds
  grid.cursorRow = min(grid.cursorRow, rows - 1)
  grid.cursorCol = min(grid.cursorCol, cols - 1)
  grid.savedCursorRow = clamp(grid.savedCursorRow, 0, rows - 1)
  grid.savedCursorCol = clamp(grid.savedCursorCol, 0, cols - 1)
  grid.needsRedraw = true

proc blankCells(cols, rows: int): seq[seq[TerminalCell]] =
  result = newSeq[seq[TerminalCell]](rows)
  for r in 0 ..< rows:
    result[r] = newRow(cols)

proc scrollUp(grid: TerminalGrid) =
  ## Scroll the scrolling region up by one line, inserting a blank line at the
  ## bottom of the region. The displaced top line is pushed to scrollback only
  ## when the region spans the full screen on the primary buffer; region scrolls
  ## and the alternate screen never touch the scrollback.
  if grid.rows == 0:
    return

  if grid.scrollTop == 0 and grid.scrollBottom == grid.rows - 1 and
      not grid.altScreenActive:
    grid.scrollbackBuffer.addLast(grid.cells[grid.scrollTop])
    if grid.scrollbackBuffer.len > grid.maxScrollback:
      grid.scrollbackBuffer.shrink(fromFirst = 1)

  for r in grid.scrollTop ..< grid.scrollBottom:
    grid.cells[r] = grid.cells[r + 1]
  grid.cells[grid.scrollBottom] = newRow(grid.cols)

proc scrollDown(grid: TerminalGrid) =
  ## Scroll the scrolling region down by one line, inserting a blank line at the
  ## top of the region. Never pushes to scrollback.
  if grid.rows == 0:
    return
  for r in countdown(grid.scrollBottom, grid.scrollTop + 1):
    grid.cells[r] = grid.cells[r - 1]
  grid.cells[grid.scrollTop] = newRow(grid.cols)

proc lineFeed(grid: TerminalGrid) =
  ## Move the cursor down one line, scrolling the region when at the bottom
  ## margin. Only the row changes; the column is preserved by the caller.
  if grid.cursorRow == grid.scrollBottom:
    grid.scrollUp()
  elif grid.cursorRow < grid.rows - 1:
    grid.cursorRow += 1

proc saveCursor(grid: TerminalGrid) =
  ## DECSC: save cursor position and SGR state (ESC 7, modes 1048/1049).
  grid.savedCursorRow = grid.cursorRow
  grid.savedCursorCol = grid.cursorCol
  grid.savedFg = grid.currentFg
  grid.savedBg = grid.currentBg
  grid.savedAttrs = grid.currentAttrs

proc restoreCursor(grid: TerminalGrid) =
  ## DECRC: restore cursor position and SGR state (ESC 8, modes 1048/1049).
  grid.cursorRow = clamp(grid.savedCursorRow, 0, grid.rows - 1)
  grid.cursorCol = clamp(grid.savedCursorCol, 0, grid.cols - 1)
  grid.currentFg = grid.savedFg
  grid.currentBg = grid.savedBg
  grid.currentAttrs = grid.savedAttrs

proc enterAltScreen(grid: TerminalGrid) =
  ## Switch to the alternate screen buffer (DEC private modes 47/1047/1049).
  ## The primary buffer is saved aside and the alternate buffer starts blank.
  if grid.altScreenActive:
    return
  grid.inactiveCells = grid.cells
  grid.cells = blankCells(grid.cols, grid.rows)
  grid.altScreenActive = true
  grid.scrollTop = 0
  grid.scrollBottom = grid.rows - 1
  grid.needsRedraw = true

proc exitAltScreen(grid: TerminalGrid) =
  ## Switch back to the primary screen buffer, restoring its saved contents.
  if not grid.altScreenActive:
    return
  grid.cells = grid.inactiveCells
  grid.inactiveCells = @[]
  grid.altScreenActive = false
  grid.scrollTop = 0
  grid.scrollBottom = grid.rows - 1
  grid.needsRedraw = true

proc putChar(grid: TerminalGrid, ch: string) =
  ## Place a character at the current cursor position, advancing the cursor.
  ## Wide (CJK) characters occupy two cells: the character cell + a padding cell.
  if grid.cursorRow < 0 or grid.cursorRow >= grid.rows:
    return

  let width = charDisplayWidth(ch)

  # Wrap if at right edge
  if grid.cursorCol >= grid.cols:
    grid.cursorCol = 0
    grid.lineFeed()

  # Wide character that doesn't fit on this line — pad the remaining cell and wrap
  if width == 2 and grid.cursorCol + 1 >= grid.cols:
    # Fill the last cell with a space and wrap
    grid.cells[grid.cursorRow][grid.cursorCol] = defaultCell()
    grid.cursorCol = 0
    grid.lineFeed()

  let col = grid.cursorCol
  let row = grid.cursorRow

  # If overwriting onto a padding cell, clear the wide char's main cell
  if grid.cells[row][col].widePadding and col > 0:
    grid.cells[row][col - 1] = defaultCell()

  # If overwriting a wide char's main cell, clear its padding cell
  if not grid.cells[row][col].widePadding and col + 1 < grid.cols and
      grid.cells[row][col + 1].widePadding:
    grid.cells[row][col + 1] = defaultCell()

  grid.cells[row][col] = TerminalCell(
    ch: ch, fg: grid.currentFg, bg: grid.currentBg, attrs: grid.currentAttrs
  )

  if width == 2 and col + 1 < grid.cols:
    # If the padding cell is a wide char's main cell, clear its padding too
    if col + 2 < grid.cols and grid.cells[row][col + 2].widePadding:
      grid.cells[row][col + 2] = defaultCell()
    grid.cells[row][col + 1] = TerminalCell(
      ch: "",
      fg: grid.currentFg,
      bg: grid.currentBg,
      attrs: grid.currentAttrs,
      widePadding: true,
    )

  grid.cursorCol += width

proc cleanWideCharBoundary(grid: TerminalGrid, row, col: int) =
  ## Clean up wide character boundaries at an erase edge.
  ## If the cell at (row, col) is a padding cell, clear both it and its main cell.
  ## This handles both start and end boundaries of erase operations:
  ##   - Start boundary: padding at cursorCol → clear the main cell before the range
  ##   - End boundary: padding just past the range → clear the orphaned padding
  ## Note: wide char main cells at the erase start don't need explicit cleanup
  ## because the erase loop or end-boundary check will handle the padding.
  if row < 0 or row >= grid.rows or col < 0 or col >= grid.cols:
    return
  if grid.cells[row][col].widePadding:
    if col > 0:
      grid.cells[row][col - 1] = defaultCell()
    grid.cells[row][col] = defaultCell()

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
        of 47, 1047:
          # Switch to alternate screen (no cursor save)
          grid.enterAltScreen()
        of 1048:
          # Save cursor (DECSC), no buffer switch
          grid.saveCursor()
        of 1049:
          # Save cursor, then switch to (cleared) alternate screen. Skip
          # entirely when already on the alt screen so a redundant 1049h can't
          # overwrite the saved primary cursor with the alt-screen position.
          if not grid.altScreenActive:
            grid.saveCursor()
            grid.enterAltScreen()
        else:
          discard
    of 'l':
      # Reset mode
      for p in privParams:
        case p
        of 25:
          grid.cursorVisible = false
        of 47, 1047:
          # Switch back to primary screen (no cursor restore)
          grid.exitAltScreen()
        of 1048:
          # Restore cursor (DECRC), no buffer switch
          grid.restoreCursor()
        of 1049:
          # Switch back to primary screen, then restore cursor. Skip entirely
          # when not on the alt screen so a redundant 1049l can't clobber the
          # live cursor with a stale saved position.
          if grid.altScreenActive:
            grid.exitAltScreen()
            grid.restoreCursor()
        else:
          discard
    else:
      discard
    return

  # Handle ESC [ > ... c (DA2 - Secondary Device Attributes)
  if paramStr.len > 0 and paramStr[0] == '>':
    if finalByte == 'c':
      # Reply: VT100, firmware version 0, ROM cartridge 0
      grid.pendingResponses.add("\x1b[>0;0;0c")
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
      grid.cleanWideCharBoundary(grid.cursorRow, grid.cursorCol)
      for c in grid.cursorCol ..< grid.cols:
        grid.cells[grid.cursorRow][c] = defaultCell()
      for r in grid.cursorRow + 1 ..< grid.rows:
        grid.cells[r] = newRow(grid.cols)
    of 1:
      # Erase from beginning of screen to cursor
      for r in 0 ..< grid.cursorRow:
        grid.cells[r] = newRow(grid.cols)
      let endCol = min(grid.cursorCol, grid.cols - 1)
      if endCol + 1 < grid.cols:
        grid.cleanWideCharBoundary(grid.cursorRow, endCol + 1)
      for c in 0 .. endCol:
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
      grid.cleanWideCharBoundary(grid.cursorRow, grid.cursorCol)
      for c in grid.cursorCol ..< grid.cols:
        grid.cells[grid.cursorRow][c] = defaultCell()
    of 1:
      # Erase from beginning of line to cursor
      let endCol = min(grid.cursorCol, grid.cols - 1)
      if endCol + 1 < grid.cols:
        grid.cleanWideCharBoundary(grid.cursorRow, endCol + 1)
      for c in 0 .. endCol:
        grid.cells[grid.cursorRow][c] = defaultCell()
    of 2:
      # Erase entire line
      grid.cells[grid.cursorRow] = newRow(grid.cols)
    else:
      discard
  of 'S':
    # Scroll Up - clamp to the region height; scrolling more lines than the
    # region holds just blanks it, so extra passes are pointless.
    let rawN =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    let n = min(rawN, grid.scrollBottom - grid.scrollTop + 1)
    for _ in 0 ..< n:
      grid.scrollUp()
  of 'T':
    # Scroll Down - clamp to the region height; scrolling more lines than the
    # region holds just blanks it, so extra passes are pointless.
    let rawN =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    let n = min(rawN, grid.scrollBottom - grid.scrollTop + 1)
    for _ in 0 ..< n:
      grid.scrollDown()
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
    grid.cleanWideCharBoundary(grid.cursorRow, grid.cursorCol)
    let endCol = min(grid.cursorCol + n, grid.cols)
    if endCol < grid.cols:
      grid.cleanWideCharBoundary(grid.cursorRow, endCol)
    for c in grid.cursorCol ..< endCol:
      grid.cells[grid.cursorRow][c] = defaultCell()
  of 'P':
    # Delete Character
    let n =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    let row = grid.cursorRow
    grid.cleanWideCharBoundary(row, grid.cursorCol)
    let srcStart = grid.cursorCol + n
    if srcStart < grid.cols:
      grid.cleanWideCharBoundary(row, srcStart)
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
    # Clean wide char boundary at insertion point
    grid.cleanWideCharBoundary(row, grid.cursorCol)
    # Clean wide char boundary at the right edge that will be pushed off
    let pushEdge = grid.cols - n
    if pushEdge >= 0 and pushEdge < grid.cols:
      grid.cleanWideCharBoundary(row, pushEdge)
    for c in countdown(grid.cols - 1, grid.cursorCol + n):
      grid.cells[row][c] = grid.cells[row][c - n]
    for c in grid.cursorCol ..< min(grid.cursorCol + n, grid.cols):
      grid.cells[row][c] = defaultCell()
  of 'L':
    # Insert Line - acts only when the cursor is inside the scrolling region;
    # the lower bound is the region bottom margin, not the screen bottom.
    let rawN =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    if grid.cursorRow >= grid.scrollTop and grid.cursorRow <= grid.scrollBottom:
      # Inserting more lines than fit between the cursor and the bottom margin
      # just blanks the rest of the region, so clamp to avoid pointless passes.
      let n = min(rawN, grid.scrollBottom - grid.cursorRow + 1)
      for _ in 0 ..< n:
        for r in countdown(grid.scrollBottom, grid.cursorRow + 1):
          grid.cells[r] = grid.cells[r - 1]
        grid.cells[grid.cursorRow] = newRow(grid.cols)
  of 'M':
    # Delete Line - acts only when the cursor is inside the scrolling region;
    # the lower bound is the region bottom margin, not the screen bottom.
    let rawN =
      if params.len > 0 and params[0] > 0:
        params[0]
      else:
        1
    if grid.cursorRow >= grid.scrollTop and grid.cursorRow <= grid.scrollBottom:
      # Deleting more lines than remain in the region just blanks the rest, so
      # clamp to the region height below the cursor to skip redundant passes.
      let n = min(rawN, grid.scrollBottom - grid.cursorRow + 1)
      for _ in 0 ..< n:
        for r in grid.cursorRow ..< grid.scrollBottom:
          grid.cells[r] = grid.cells[r + 1]
        grid.cells[grid.scrollBottom] = newRow(grid.cols)
  of 'c':
    # DA1 - Primary Device Attributes
    # Reply: VT102 with no options
    grid.pendingResponses.add("\x1b[?6c")
  of 'n':
    # DSR - Device Status Report
    let mode =
      if params.len > 0:
        params[0]
      else:
        0
    case mode
    of 6:
      # CPR - Cursor Position Report (1-based)
      grid.pendingResponses.add(
        "\x1b[" & $(grid.cursorRow + 1) & ";" & $(grid.cursorCol + 1) & "R"
      )
    of 5:
      # Device status: "OK"
      grid.pendingResponses.add("\x1b[0n")
    else:
      discard
  of 'r':
    # DECSTBM - Set Top and Bottom Margins (scrolling region), 1-based params.
    let top =
      if params.len > 0 and params[0] > 0:
        params[0] - 1
      else:
        0
    let bottom =
      if params.len > 1 and params[1] > 0:
        params[1] - 1
      else:
        grid.rows - 1
    if top >= 0 and top < bottom and bottom <= grid.rows - 1:
      grid.scrollTop = top
      grid.scrollBottom = bottom
    else:
      # Invalid region resets to the full screen
      grid.scrollTop = 0
      grid.scrollBottom = grid.rows - 1
    # Cursor moves to the home position (origin mode/DECOM not supported)
    grid.cursorRow = 0
    grid.cursorCol = 0
  else:
    discard

proc processOutput*(grid: TerminalGrid, data: string) =
  ## Process raw PTY output through the ANSI parser state machine.
  ## Updates the grid cells, cursor position, and colors.
  var actualData = data
  if grid.utf8Buffer.len > 0:
    actualData = grid.utf8Buffer & data
    grid.utf8Buffer = ""
  var i = 0
  while i < actualData.len:
    let ch = actualData[i]

    case grid.parserState
    of apsNormal:
      case ch
      of '\x1b':
        grid.parserState = apsEscape
        grid.escapeBuffer = ""
      of '\r':
        grid.cursorCol = 0
      of '\n':
        grid.lineFeed()
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
          if i + byteLen <= actualData.len:
            runeStr = actualData[i ..< i + byteLen]
            i += byteLen - 1 # -1 because the main loop increments
          else:
            # Incomplete UTF-8 sequence at end of buffer — save for next read
            grid.utf8Buffer = actualData[i ..< actualData.len]
            grid.needsRedraw = true
            return
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
        # Reverse Index (RI): move up, scrolling the region down at the top margin
        if grid.cursorRow == grid.scrollTop:
          grid.scrollDown()
        elif grid.cursorRow > 0:
          grid.cursorRow -= 1
        grid.parserState = apsNormal
      of '7':
        # DECSC - Save cursor and SGR state
        grid.saveCursor()
        grid.parserState = apsNormal
      of '8':
        # DECRC - Restore cursor and SGR state
        grid.restoreCursor()
        grid.parserState = apsNormal
      of 'c':
        # RIS - Reset terminal to its initial state
        grid.currentFg = defaultColor()
        grid.currentBg = defaultColor()
        grid.currentAttrs = {}
        grid.cursorRow = 0
        grid.cursorCol = 0
        grid.cursorVisible = true
        grid.altScreenActive = false
        grid.inactiveCells = @[]
        grid.scrollTop = 0
        grid.scrollBottom = grid.rows - 1
        # Reset the full saved cursor/SGR state so a later DECRC can't restore
        # stale colors or attributes left over from before the reset.
        grid.savedCursorRow = 0
        grid.savedCursorCol = 0
        grid.savedFg = defaultColor()
        grid.savedBg = defaultColor()
        grid.savedAttrs = {}
        for r in 0 ..< grid.rows:
          grid.cells[r] = newRow(grid.cols)
        grid.parserState = apsNormal
      of '#':
        # DEC line attribute sequences (e.g., ESC # 8) - skip next byte
        if i + 1 < actualData.len:
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
          if i + 1 < actualData.len and actualData[i + 1] == '\\':
            i += 1
        grid.parserState = apsNormal
      else:
        grid.escapeBuffer.add(ch)
    of apsStringSeq:
      # Consuming DCS/APC/PM/SOS string until ST (ESC \) or BEL
      if ch == '\x1b':
        # Possible start of ST (ESC \)
        if i + 1 < actualData.len and actualData[i + 1] == '\\':
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

  # Include scrollback first, but only on the primary screen. While the
  # alternate screen is active the scrollback holds unrelated primary-buffer
  # history, so mixing it into the snapshot would misrepresent what's on screen.
  if not grid.altScreenActive:
    for row in grid.scrollbackBuffer:
      var line = ""
      for cell in row:
        if cell.widePadding:
          continue
        if cell.ch.len > 0:
          line.add(cell.ch)
        else:
          line.add(' ')
      lines.add(stripTrailingSpaces(line))

  # Then current grid (only up to the last row with content)
  var lastNonEmptyRow = -1
  for r in 0 ..< grid.rows:
    for c in 0 ..< grid.cols:
      if grid.cells[r][c].ch.len > 0 and not grid.cells[r][c].widePadding:
        lastNonEmptyRow = r
        break

  if lastNonEmptyRow >= 0:
    for r in 0 .. lastNonEmptyRow:
      var line = ""
      for c in 0 ..< grid.cols:
        let cell = grid.cells[r][c]
        if cell.widePadding:
          continue
        if cell.ch.len > 0:
          line.add(cell.ch)
        else:
          line.add(' ')
      lines.add(stripTrailingSpaces(line))

  if lines.len == 0:
    return ""
  lines.join("\n")
