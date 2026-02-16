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

import std/[unittest, strutils]
import ../src/moepkg/terminal/ansi_parser

suite "TerminalGrid - Creation":
  test "newTerminalGrid creates grid with correct dimensions":
    let grid = newTerminalGrid(80, 24)
    check grid.cols == 80
    check grid.rows == 24
    check grid.cells.len == 24
    check grid.cells[0].len == 80
    check grid.cursorRow == 0
    check grid.cursorCol == 0
    check grid.cursorVisible == true

  test "newTerminalGrid initializes cells with spaces":
    let grid = newTerminalGrid(10, 5)
    for row in 0 ..< 5:
      for col in 0 ..< 10:
        check grid.cells[row][col].ch == ""
        check grid.cells[row][col].fg.kind == ckDefault
        check grid.cells[row][col].bg.kind == ckDefault

suite "TerminalGrid - Plain text processing":
  test "Process simple ASCII text":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("Hello")
    check grid.cells[0][0].ch == "H"
    check grid.cells[0][1].ch == "e"
    check grid.cells[0][2].ch == "l"
    check grid.cells[0][3].ch == "l"
    check grid.cells[0][4].ch == "o"
    check grid.cursorCol == 5
    check grid.cursorRow == 0

  test "Process text with newline":
    let grid = newTerminalGrid(80, 24)
    # LF only moves cursor down (does not return to column 0)
    grid.processOutput("Hello\nWorld")
    check grid.cells[0][0].ch == "H"
    check grid.cells[1][5].ch == "W" # Column stays at 5 after LF
    check grid.cursorRow == 1
    check grid.cursorCol == 10

  test "Process carriage return moves cursor to column 0":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("Hello\rWorld")
    # "World" should overwrite "Hello"
    check grid.cells[0][0].ch == "W"
    check grid.cells[0][1].ch == "o"
    check grid.cells[0][2].ch == "r"
    check grid.cells[0][3].ch == "l"
    check grid.cells[0][4].ch == "d"
    check grid.cursorRow == 0

  test "Text wrapping at end of line":
    let grid = newTerminalGrid(5, 3)
    grid.processOutput("ABCDEFGH")
    check grid.cells[0][0].ch == "A"
    check grid.cells[0][4].ch == "E"
    check grid.cells[1][0].ch == "F"
    check grid.cells[1][2].ch == "H"

  test "Scrolling when reaching bottom":
    let grid = newTerminalGrid(10, 3)
    grid.processOutput("Line1\r\nLine2\r\nLine3\r\nLine4")
    # After scrolling, Line1 should be gone, Line2/3/4 visible
    check grid.cells[0][0].ch == "L"
    check grid.cells[2][0].ch == "L"
    check grid.cursorRow == 2

suite "TerminalGrid - CSI cursor movement":
  test "Cursor Up (CSI A)":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("Line1\nLine2")
    check grid.cursorRow == 1
    grid.processOutput("\x1b[1A")
    check grid.cursorRow == 0

  test "Cursor Down (CSI B)":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[3B")
    check grid.cursorRow == 3

  test "Cursor Forward (CSI C)":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[5C")
    check grid.cursorCol == 5

  test "Cursor Backward (CSI D)":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("Hello\x1b[3D")
    check grid.cursorCol == 2

  test "Cursor position set (CSI H)":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[5;10H")
    check grid.cursorRow == 4 # 1-based to 0-based
    check grid.cursorCol == 9

  test "Cursor home (CSI H with no params)":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("Hello\n\x1b[H")
    check grid.cursorRow == 0
    check grid.cursorCol == 0

suite "TerminalGrid - CSI erase operations":
  test "Erase from cursor to end of line (CSI 0K)":
    let grid = newTerminalGrid(10, 3)
    grid.processOutput("ABCDEFGHIJ")
    grid.processOutput("\x1b[1;4H") # Move to column 4 (0-based: col 3)
    grid.processOutput("\x1b[0K")
    check grid.cells[0][0].ch == "A"
    check grid.cells[0][1].ch == "B"
    check grid.cells[0][2].ch == "C"
    check grid.cells[0][3].ch == "" # Erased
    check grid.cells[0][9].ch == "" # Erased

  test "Erase from start of line to cursor (CSI 1K)":
    let grid = newTerminalGrid(10, 3)
    grid.processOutput("ABCDEFGHIJ")
    grid.processOutput("\x1b[1;4H") # Move to column 4 (0-based: col 3)
    grid.processOutput("\x1b[1K")
    check grid.cells[0][0].ch == "" # Erased
    check grid.cells[0][1].ch == "" # Erased
    check grid.cells[0][2].ch == "" # Erased
    check grid.cells[0][3].ch == "" # Erased
    check grid.cells[0][4].ch == "E" # Not erased

  test "Erase entire line (CSI 2K)":
    let grid = newTerminalGrid(10, 3)
    grid.processOutput("ABCDEFGHIJ")
    grid.processOutput("\x1b[1;4H")
    grid.processOutput("\x1b[2K")
    for col in 0 ..< 10:
      check grid.cells[0][col].ch == ""

  test "Erase screen from cursor to end (CSI 0J)":
    let grid = newTerminalGrid(5, 3)
    grid.processOutput("AAAAA\r\nBBBBB\r\nCCCCC")
    grid.processOutput("\x1b[2;1H") # Row 2, Col 1 (0-based: row 1, col 0)
    grid.processOutput("\x1b[0J")
    # First row should be untouched
    check grid.cells[0][0].ch == "A"
    # Second and third rows erased
    check grid.cells[1][0].ch == ""
    check grid.cells[2][0].ch == ""

  test "Erase entire screen (CSI 2J)":
    let grid = newTerminalGrid(5, 3)
    grid.processOutput("AAAAA\nBBBBB\nCCCCC")
    grid.processOutput("\x1b[2J")
    for row in 0 ..< 3:
      for col in 0 ..< 5:
        check grid.cells[row][col].ch == ""

suite "TerminalGrid - SGR colors":
  test "Basic foreground color (CSI 31m - red)":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[31mR")
    check grid.cells[0][0].ch == "R"
    check grid.cells[0][0].fg.kind == ckIndexed
    check grid.cells[0][0].fg.index == 1 # Red = index 1

  test "Basic background color (CSI 42m - green bg)":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[42mG")
    check grid.cells[0][0].ch == "G"
    check grid.cells[0][0].bg.kind == ckIndexed
    check grid.cells[0][0].bg.index == 2 # Green = index 2

  test "Reset attributes (CSI 0m)":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[31mR\x1b[0mN")
    check grid.cells[0][0].fg.kind == ckIndexed # Red
    check grid.cells[0][1].fg.kind == ckDefault # Reset

  test "Bold attribute (CSI 1m)":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[1mB")
    check taBold in grid.cells[0][0].attrs

  test "256-color foreground (CSI 38;5;Nm)":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[38;5;200mX")
    check grid.cells[0][0].fg.kind == ckIndexed
    check grid.cells[0][0].fg.index == 200

  test "256-color background (CSI 48;5;Nm)":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[48;5;100mX")
    check grid.cells[0][0].bg.kind == ckIndexed
    check grid.cells[0][0].bg.index == 100

  test "RGB foreground (CSI 38;2;R;G;Bm)":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[38;2;255;128;0mX")
    check grid.cells[0][0].fg.kind == ckRgb
    check grid.cells[0][0].fg.r == 255
    check grid.cells[0][0].fg.g == 128
    check grid.cells[0][0].fg.b == 0

  test "RGB background (CSI 48;2;R;G;Bm)":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[48;2;0;128;255mX")
    check grid.cells[0][0].bg.kind == ckRgb
    check grid.cells[0][0].bg.r == 0
    check grid.cells[0][0].bg.g == 128
    check grid.cells[0][0].bg.b == 255

suite "TerminalGrid - Cursor visibility":
  test "Hide cursor (CSI ?25l)":
    let grid = newTerminalGrid(80, 24)
    check grid.cursorVisible == true
    grid.processOutput("\x1b[?25l")
    check grid.cursorVisible == false

  test "Show cursor (CSI ?25h)":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[?25l")
    check grid.cursorVisible == false
    grid.processOutput("\x1b[?25h")
    check grid.cursorVisible == true

suite "TerminalGrid - Resize":
  test "Resize grid preserves existing content":
    let grid = newTerminalGrid(10, 5)
    grid.processOutput("Hello")
    grid.resize(20, 10)
    check grid.cols == 20
    check grid.rows == 10
    check grid.cells[0][0].ch == "H"
    check grid.cells[0][4].ch == "o"

  test "Resize grid shrinks content":
    let grid = newTerminalGrid(10, 5)
    grid.processOutput("Hello")
    grid.resize(3, 2)
    check grid.cols == 3
    check grid.rows == 2
    check grid.cells[0][0].ch == "H"
    check grid.cells[0][2].ch == "l"

suite "TerminalGrid - toPlainText":
  test "Convert grid to plain text":
    let grid = newTerminalGrid(10, 3)
    grid.processOutput("Hello\nWorld")
    let text = grid.toPlainText()
    check "Hello" in text
    check "World" in text

  test "Trailing empty rows are excluded":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("OnlyOneLine")
    let text = grid.toPlainText()
    # Should contain only the one line, no trailing empty lines
    check text.count('\n') == 0
    check text == "OnlyOneLine"

  test "Trailing spaces on lines are stripped":
    let grid = newTerminalGrid(20, 3)
    grid.processOutput("Hi")
    let text = grid.toPlainText()
    # "Hi" should not have trailing spaces padded to column width
    check text == "Hi"

  test "Intermediate empty rows are preserved":
    let grid = newTerminalGrid(10, 5)
    grid.processOutput("AAA")
    grid.processOutput("\r\n") # Row 1: empty
    grid.processOutput("\r\nBBB") # Row 2: BBB
    let text = grid.toPlainText()
    let lines = text.split('\n')
    check lines.len == 3
    check lines[0] == "AAA"
    check lines[1] == ""
    check lines[2] == "BBB"

  test "Empty grid returns empty string":
    let grid = newTerminalGrid(10, 5)
    let text = grid.toPlainText()
    check text == ""

  test "Scrollback lines are included":
    let grid = newTerminalGrid(10, 3)
    grid.processOutput("Line1\r\nLine2\r\nLine3\r\nLine4")
    # Line1 should have scrolled into scrollback
    let text = grid.toPlainText()
    check "Line1" in text
    check "Line4" in text

  test "Scrollback-only grid (visible grid empty after clear)":
    let grid = newTerminalGrid(10, 3)
    grid.processOutput("AAA\r\nBBB\r\nCCC\r\nDDD")
    # Now clear the screen
    grid.processOutput("\x1b[2J")
    let text = grid.toPlainText()
    # Scrollback should still have the scrolled-off line
    check grid.scrollbackBuffer.len >= 1
    # Visible grid is cleared, so only scrollback content
    check "DDD" notin text or text.count('\n') < 3

suite "TerminalGrid - Tab character":
  test "Tab advances cursor to next tab stop":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("A\tB")
    check grid.cells[0][0].ch == "A"
    # Tab should advance to column 8 (default tab stop)
    check grid.cells[0][8].ch == "B"

suite "TerminalGrid - Incomplete sequences":
  test "Incomplete escape sequence buffered across calls":
    let grid = newTerminalGrid(80, 24)
    # Send partial escape sequence
    grid.processOutput("A\x1b")
    check grid.cells[0][0].ch == "A"
    # Complete the sequence
    grid.processOutput("[31mR")
    check grid.cells[0][1].ch == "R"
    check grid.cells[0][1].fg.kind == ckIndexed

suite "TerminalGrid - Scrollback buffer":
  test "Lines scroll into scrollback buffer":
    let grid = newTerminalGrid(10, 3)
    grid.processOutput("Line1\r\nLine2\r\nLine3\r\nLine4\r\nLine5")
    # Scrollback should contain the lines that scrolled off screen
    check grid.scrollbackBuffer.len >= 1

suite "TerminalGrid - Cursor position tracking (regression)":
  ## Regression tests for cursor position. The grid cursor must track
  ## the terminal cursor position independently — it is used directly for
  ## screen cursor placement in Terminal-Input mode (not window.cursor).

  test "Cursor tracks after simple output":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("Hello")
    check grid.cursorRow == 0
    check grid.cursorCol == 5

  test "Cursor tracks across lines":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("ABC\r\nDEF\r\nGHI")
    check grid.cursorRow == 2
    check grid.cursorCol == 3

  test "Cursor position after CSI H":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("ignored text")
    grid.processOutput("\x1b[10;20H")
    check grid.cursorRow == 9 # 1-based → 0-based
    check grid.cursorCol == 19

  test "Cursor position after CSI movement sequence":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[5;5H") # Move to (4,4)
    check grid.cursorRow == 4
    check grid.cursorCol == 4
    grid.processOutput("\x1b[2B") # Down 2
    check grid.cursorRow == 6
    grid.processOutput("\x1b[3C") # Right 3
    check grid.cursorCol == 7
    grid.processOutput("\x1b[1A") # Up 1
    check grid.cursorRow == 5
    grid.processOutput("\x1b[2D") # Left 2
    check grid.cursorCol == 5

  test "Cursor wraps at right edge on next character":
    let grid = newTerminalGrid(5, 3)
    grid.processOutput("ABCDE")
    # After filling exactly 5 cols, cursor is at col 5 (deferred wrap)
    check grid.cursorRow == 0
    check grid.cursorCol == 5
    # Next character triggers the wrap
    grid.processOutput("F")
    check grid.cursorRow == 1
    check grid.cursorCol == 1 # After writing 'F' at (1,0), col advances to 1

  test "Cursor visibility flag preserved":
    let grid = newTerminalGrid(80, 24)
    check grid.cursorVisible == true
    grid.processOutput("\x1b[?25l") # Hide
    check grid.cursorVisible == false
    grid.processOutput("some output")
    check grid.cursorVisible == false # Must stay hidden
    grid.processOutput("\x1b[?25h") # Show
    check grid.cursorVisible == true
