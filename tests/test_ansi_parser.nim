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

import std/[unittest, strutils, deques]
import ../src/moepkg/terminal/ansi_parser {.all.}

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

  test "Resize clears wide char main cell when padding is truncated":
    let grid = newTerminalGrid(10, 3)
    grid.processOutput("AB日DE")
    # cells: [0]="A" [1]="B" [2]="日" [3]=padding [4]="D" [5]="E"
    grid.resize(3, 3)
    # col 3 (padding) is truncated, so col 2 (main) must be cleared
    check grid.cells[0][0].ch == "A"
    check grid.cells[0][1].ch == "B"
    check grid.cells[0][2].ch == "" # cleared, not orphaned "日"

  test "Resize preserves intact wide char at right edge":
    let grid = newTerminalGrid(10, 3)
    grid.processOutput("A日")
    # cells: [0]="A" [1]="日" [2]=padding
    grid.resize(3, 3)
    # Both main (col 1) and padding (col 2) are in the new grid — must stay intact
    check grid.cells[0][0].ch == "A"
    check grid.cells[0][1].ch == "日"
    check grid.cells[0][2].widePadding == true

  test "Resize clears main cell when padding is truncated (cols=1)":
    let grid = newTerminalGrid(10, 3)
    grid.processOutput("日B")
    # cells: [0]="日" [1]=padding [2]="B"
    grid.resize(1, 3)
    # col 0 is "日" main cell, its padding at col 1 is truncated
    check grid.cells[0][0].ch == "" # cleared

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

  test "Incomplete UTF-8 sequence buffered across calls":
    let grid = newTerminalGrid(80, 24)
    # "日" = E6 97 A5 (3-byte UTF-8). Send first 2 bytes then the last.
    grid.processOutput("A" & "\xe6\x97")
    check grid.cells[0][0].ch == "A"
    # Incomplete bytes should not produce output
    check grid.cells[0][1].ch == ""
    # Complete the sequence
    grid.processOutput("\xa5B")
    check grid.cells[0][1].ch == "日"
    check grid.cells[0][2].widePadding == true # wide char padding
    check grid.cells[0][3].ch == "B"

  test "Incomplete 4-byte UTF-8 sequence buffered across calls":
    let grid = newTerminalGrid(80, 24)
    # U+1F600 (😀) = F0 9F 98 80 (4-byte UTF-8). Split after 1 byte.
    grid.processOutput("\xf0")
    check grid.cells[0][0].ch == ""
    grid.processOutput("\x9f\x98\x80")
    check grid.cells[0][0].ch == "\xf0\x9f\x98\x80"

  test "Incomplete 2-byte UTF-8 sequence buffered across calls":
    let grid = newTerminalGrid(80, 24)
    # "é" = C3 A9 (2-byte UTF-8). Split after 1 byte.
    grid.processOutput("\xc3")
    check grid.cells[0][0].ch == ""
    grid.processOutput("\xa9")
    check grid.cells[0][0].ch == "é"

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

suite "TerminalGrid - Wide (CJK) character support":
  test "Wide character advances cursor by 2 columns":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("日")
    check grid.cursorCol == 2
    check grid.cursorRow == 0
    check grid.cells[0][0].ch == "日"
    check grid.cells[0][0].widePadding == false
    check grid.cells[0][1].widePadding == true

  test "Multiple wide characters":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("日本語")
    check grid.cursorCol == 6
    check grid.cells[0][0].ch == "日"
    check grid.cells[0][1].widePadding == true
    check grid.cells[0][2].ch == "本"
    check grid.cells[0][3].widePadding == true
    check grid.cells[0][4].ch == "語"
    check grid.cells[0][5].widePadding == true

  test "Wide character wraps when it doesn't fit at end of line":
    # Grid is 5 cols wide. After 4 narrow chars, only 1 col remains.
    # A wide char (2 cols) should wrap to next line.
    let grid = newTerminalGrid(5, 3)
    grid.processOutput("ABCD日")
    # "ABCD" fills cols 0-3, col 4 is blank (padded), "日" wraps to row 1
    check grid.cells[0][0].ch == "A"
    check grid.cells[0][3].ch == "D"
    check grid.cells[0][4].ch == "" # padding space before wrap
    check grid.cells[1][0].ch == "日"
    check grid.cells[1][1].widePadding == true
    check grid.cursorRow == 1
    check grid.cursorCol == 2

  test "Overwrite narrow char onto wide char clears padding":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("日")
    # Overwrite the wide char at col 0 with 'A'
    grid.processOutput("\x1b[1;1H") # Move to row 1, col 1 (0-based: 0,0)
    grid.processOutput("A")
    check grid.cells[0][0].ch == "A"
    check grid.cells[0][0].widePadding == false
    check grid.cells[0][1].widePadding == false # padding cleared
    check grid.cells[0][1].ch == "" # default empty

  test "Overwrite onto padding cell clears the wide char main cell":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("日")
    # Move to col 1 (the padding cell) and write 'X'
    grid.processOutput("\x1b[1;2H") # row 1, col 2 (0-based: 0,1)
    grid.processOutput("X")
    check grid.cells[0][0].ch == "" # main cell cleared
    check grid.cells[0][0].widePadding == false
    check grid.cells[0][1].ch == "X"
    check grid.cells[0][1].widePadding == false

  test "toPlainText does not duplicate wide characters":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("日本")
    let text = grid.toPlainText()
    check text == "日本"

  test "toPlainText with mixed narrow and wide chars":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("A日B本C")
    let text = grid.toPlainText()
    check text == "A日B本C"

  test "Erase in line (K) respects wide char boundary at start":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("日B")
    # Move to col 1 (padding of "日") and erase to end of line
    grid.processOutput("\x1b[1;2H") # 0-based: row 0, col 1
    grid.processOutput("\x1b[0K")
    # The wide char at col 0 should also be cleared since we erased from its padding
    check grid.cells[0][0].ch == ""
    check grid.cells[0][0].widePadding == false
    check grid.cells[0][1].ch == ""

  test "Erase in line (K) respects wide char boundary at end":
    let grid = newTerminalGrid(10, 3)
    grid.processOutput("AB日DE")
    # Erase from start of line to col 2 (which is the main cell of "日")
    grid.processOutput("\x1b[1;3H") # 0-based: row 0, col 2
    grid.processOutput("\x1b[1K") # Erase from beginning to cursor
    check grid.cells[0][0].ch == "" # erased
    check grid.cells[0][1].ch == "" # erased
    check grid.cells[0][2].ch == "" # erased (was "日")
    # The padding at col 3 should also be cleared
    check grid.cells[0][3].ch == "" # padding cleared
    check grid.cells[0][3].widePadding == false

  test "Erase K mode 1 does not damage wide char outside erase range":
    # Regression: cleanWideCharBoundary must not split a wide char
    # that is entirely outside the erase range.
    let grid = newTerminalGrid(10, 3)
    grid.processOutput("A日B")
    # cells: [0]="A", [1]="日", [2]=padding, [3]="B"
    # Erase from beginning to cursor at col 0
    grid.processOutput("\x1b[1;1H") # 0-based: row 0, col 0
    grid.processOutput("\x1b[1K")
    check grid.cells[0][0].ch == "" # erased
    # Wide char at col 1 must remain intact
    check grid.cells[0][1].ch == "日"
    check grid.cells[0][2].widePadding == true
    check grid.cells[0][3].ch == "B"

  test "Insert character at wide char padding splits correctly":
    let grid = newTerminalGrid(10, 3)
    grid.processOutput("日BC")
    # cells: [0]="日" [1]=padding [2]="B" [3]="C"
    # Insert 1 blank at col 1 (the padding cell)
    grid.processOutput("\x1b[1;2H") # 0-based: row 0, col 1
    grid.processOutput("\x1b[1@") # Insert 1 character
    # The wide char at col 0 should be cleaned up
    check grid.cells[0][0].ch == "" # main cell cleared
    check grid.cells[0][0].widePadding == false
    check grid.cells[0][1].ch == "" # inserted blank
    check grid.cells[0][1].widePadding == false

  test "Insert character pushes wide char off right edge":
    let grid = newTerminalGrid(6, 3)
    grid.processOutput("AB日CD")
    # cells: [0]="A" [1]="B" [2]="日" [3]=padding [4]="C" [5]="D"
    # Insert 1 blank at col 0. Rightmost cell "D" is pushed off.
    grid.processOutput("\x1b[1;1H")
    grid.processOutput("\x1b[1@")
    check grid.cells[0][0].ch == "" # inserted blank
    check grid.cells[0][1].ch == "A"
    check grid.cells[0][2].ch == "B"
    check grid.cells[0][3].ch == "日"
    check grid.cells[0][4].widePadding == true
    check grid.cells[0][5].ch == "C" # "D" pushed off

  test "Insert character at right edge of wide char cleans up pushed-off padding":
    let grid = newTerminalGrid(5, 3)
    grid.processOutput("A日BC")
    # cells: [0]="A" [1]="日" [2]=padding [3]="B" [4]="C"
    # Insert 1 blank at col 3. "C" at col 4 is pushed off.
    # But also check: col 5 (cols-n=4) boundary.
    grid.processOutput("\x1b[1;1H")
    grid.processOutput("\x1b[2@") # Insert 2 blanks at col 0
    # pushEdge = 5-2 = 3. cell[3] is "B" (not padding). No split.
    # Shift: cells shift right by 2. [0]=blank [1]=blank [2]="A" [3]="日" [4]=padding
    check grid.cells[0][0].ch == "" # inserted
    check grid.cells[0][1].ch == "" # inserted
    check grid.cells[0][2].ch == "A"
    check grid.cells[0][3].ch == "日"
    check grid.cells[0][4].widePadding == true

  test "Wide chars in scrollback are handled correctly in toPlainText":
    let grid = newTerminalGrid(10, 3)
    # Fill lines to push "日本" into scrollback
    grid.processOutput("日本\r\nLine2\r\nLine3\r\nLine4")
    let text = grid.toPlainText()
    check "日本" in text

suite "TerminalGrid - Terminal Query Responses":
  test "DA1 (Primary Device Attributes) ESC[c":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[c")
    check grid.pendingResponses.len == 1
    check grid.pendingResponses[0] == "\x1b[?6c"

  test "DA1 with explicit param ESC[0c":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[0c")
    check grid.pendingResponses.len == 1
    check grid.pendingResponses[0] == "\x1b[?6c"

  test "DA2 (Secondary Device Attributes) ESC[>c":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[>c")
    check grid.pendingResponses.len == 1
    check grid.pendingResponses[0] == "\x1b[>0;0;0c"

  test "DSR (Device Status Report) ESC[5n":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[5n")
    check grid.pendingResponses.len == 1
    check grid.pendingResponses[0] == "\x1b[0n"

  test "CPR (Cursor Position Report) ESC[6n":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[6n")
    check grid.pendingResponses.len == 1
    check grid.pendingResponses[0] == "\x1b[1;1R"

  test "CPR after cursor move":
    let grid = newTerminalGrid(80, 24)
    # Move cursor to row 5, col 10 (1-based: 5;10)
    grid.processOutput("\x1b[5;10H\x1b[6n")
    check grid.pendingResponses.len == 1
    check grid.pendingResponses[0] == "\x1b[5;10R"

  test "Multiple queries in one output":
    let grid = newTerminalGrid(80, 24)
    grid.processOutput("\x1b[c\x1b[>c\x1b[6n")
    check grid.pendingResponses.len == 3
    check grid.pendingResponses[0] == "\x1b[?6c"
    check grid.pendingResponses[1] == "\x1b[>0;0;0c"
    check grid.pendingResponses[2] == "\x1b[1;1R"

suite "TerminalGrid - Alternate screen buffer":
  test "1049 enters a blank alt screen and restores the primary on exit":
    let grid = newTerminalGrid(10, 4)
    grid.processOutput("PRIMARY")
    grid.processOutput("\x1b[?1049h")
    check grid.altScreenActive == true
    check grid.cells[0][0].ch == "" # alt starts blank
    grid.processOutput("\x1b[HALT")
    check grid.cells[0][0].ch == "A"
    grid.processOutput("\x1b[?1049l")
    check grid.altScreenActive == false
    check grid.cells[0][0].ch == "P"
    check grid.cells[0][6].ch == "Y"

  test "alternate screen does not pollute scrollback":
    let grid = newTerminalGrid(10, 4)
    grid.processOutput("A\r\nB\r\nC\r\nD\r\nE\r\nF")
    let before = grid.scrollbackBuffer.len
    check before > 0
    grid.processOutput("\x1b[?1049h")
    for _ in 0 ..< 20:
      grid.processOutput("X\r\n")
    check grid.scrollbackBuffer.len == before
    grid.processOutput("\x1b[?1049l")
    check grid.scrollbackBuffer.len == before

  test "redundant 1049h does not destroy the primary buffer":
    let grid = newTerminalGrid(10, 4)
    grid.processOutput("PRIMARY")
    grid.processOutput("\x1b[?1049h\x1b[?1049h")
    grid.processOutput("\x1b[HALT")
    grid.processOutput("\x1b[?1049l")
    check grid.cells[0][0].ch == "P"
    check grid.cells[0][6].ch == "Y"

  test "1049 restores cursor position on exit":
    let grid = newTerminalGrid(20, 10)
    grid.processOutput("\x1b[6;11H")
    check grid.cursorRow == 5
    check grid.cursorCol == 10
    grid.processOutput("\x1b[?1049h")
    grid.processOutput("\x1b[1;1H")
    check grid.cursorRow == 0
    grid.processOutput("\x1b[?1049l")
    check grid.cursorRow == 5
    check grid.cursorCol == 10

  test "redundant 1049h after moving the alt cursor preserves the saved cursor":
    let grid = newTerminalGrid(20, 10)
    grid.processOutput("\x1b[6;11H") # primary cursor at row 5, col 10
    grid.processOutput("\x1b[?1049h") # save (5,10), enter alt
    grid.processOutput("\x1b[1;1H") # move the alt cursor to home
    grid.processOutput("\x1b[?1049h") # redundant: must NOT re-save (0,0)
    grid.processOutput("\x1b[?1049l") # exit, restore
    check grid.cursorRow == 5
    check grid.cursorCol == 10

  test "redundant 1049l on the primary screen does not clobber the cursor":
    let grid = newTerminalGrid(20, 10)
    grid.processOutput("\x1b[6;11H")
    grid.processOutput("\x1b[?1049l") # already primary: must be a no-op
    check grid.cursorRow == 5
    check grid.cursorCol == 10

  test "47 switches buffers without touching the cursor":
    let grid = newTerminalGrid(20, 10)
    grid.processOutput("HELLO\x1b[6;11H")
    grid.processOutput("\x1b[?47h")
    check grid.cells[0][0].ch == "" # alt blank
    grid.processOutput("\x1b[1;1HALT")
    grid.processOutput("\x1b[?47l")
    check grid.cells[0][0].ch == "H" # primary restored
    check grid.cursorRow == 0 # cursor NOT restored
    check grid.cursorCol == 3

  test "1048 saves and restores cursor without switching buffers":
    let grid = newTerminalGrid(20, 10)
    grid.processOutput("\x1b[3;4H")
    grid.processOutput("\x1b[?1048h")
    grid.processOutput("\x1b[8;9H")
    check grid.altScreenActive == false
    grid.processOutput("\x1b[?1048l")
    check grid.cursorRow == 2
    check grid.cursorCol == 3

suite "TerminalGrid - Scrolling region (DECSTBM)":
  test "DECSTBM confines scrolling to the region":
    let grid = newTerminalGrid(10, 6)
    grid.processOutput("R0\r\nR1\r\nR2\r\nR3\r\nR4\r\nR5")
    grid.processOutput("\x1b[2;4r") # region rows 1..3
    grid.processOutput("\x1b[4;1H") # cursor to region bottom (row 3)
    grid.processOutput("\n")
    check grid.cells[0][1].ch == "0" # row 0 untouched
    check grid.cells[4][1].ch == "4" # row 4 untouched
    check grid.cells[5][1].ch == "5" # row 5 untouched
    check grid.cells[1][1].ch == "2" # old R2 scrolled up
    check grid.cells[3][0].ch == "" # blank at region bottom

  test "region scroll does not push to scrollback":
    let grid = newTerminalGrid(10, 6)
    grid.processOutput("\x1b[2;4r")
    grid.processOutput("\x1b[4;1H")
    for _ in 0 ..< 10:
      grid.processOutput("\n")
    check grid.scrollbackBuffer.len == 0

  test "top-anchored partial region does not push to scrollback":
    let grid = newTerminalGrid(10, 6)
    grid.processOutput("\x1b[1;3r") # top=0, bottom=2 (not full height)
    grid.processOutput("\x1b[3;1H")
    for _ in 0 ..< 10:
      grid.processOutput("\n")
    check grid.scrollbackBuffer.len == 0

  test "DECSTBM with no params resets region and scrollback resumes":
    let grid = newTerminalGrid(10, 3)
    grid.processOutput("\x1b[2;3r")
    grid.processOutput("\x1b[r")
    check grid.scrollTop == 0
    check grid.scrollBottom == 2
    grid.processOutput("A\r\nB\r\nC\r\nD")
    check grid.scrollbackBuffer.len >= 1

  test "RI scrolls the region down at the top margin":
    let grid = newTerminalGrid(10, 6)
    grid.processOutput("R0\r\nR1\r\nR2\r\nR3\r\nR4\r\nR5")
    grid.processOutput("\x1b[2;4r") # region 1..3
    grid.processOutput("\x1b[2;1H") # region top (row 1)
    grid.processOutput("\x1bM") # Reverse Index
    check grid.cells[1][0].ch == "" # blank at region top
    check grid.cells[2][1].ch == "1" # old R1 moved down
    check grid.cells[3][1].ch == "2" # old R2 moved down
    check grid.cells[0][1].ch == "0" # row 0 untouched
    check grid.cells[4][1].ch == "4" # row 4 untouched

  test "scroll down (CSI T) respects the region":
    let grid = newTerminalGrid(10, 6)
    grid.processOutput("R0\r\nR1\r\nR2\r\nR3\r\nR4\r\nR5")
    grid.processOutput("\x1b[2;4r")
    grid.processOutput("\x1b[T")
    check grid.cells[1][0].ch == "" # blank at region top
    check grid.cells[2][1].ch == "1"
    check grid.cells[3][1].ch == "2"
    check grid.cells[0][1].ch == "0"
    check grid.cells[4][1].ch == "4"

  test "scroll up/down counts beyond the region just blank it (clamped)":
    let grid = newTerminalGrid(10, 6)
    grid.processOutput("R0\r\nR1\r\nR2\r\nR3\r\nR4\r\nR5")
    grid.processOutput("\x1b[2;4r") # region rows 1..3
    grid.processOutput("\x1b[999S") # scroll up far past the region height
    check grid.cells[1][0].ch == "" # region fully blanked
    check grid.cells[2][0].ch == ""
    check grid.cells[3][0].ch == ""
    check grid.cells[0][1].ch == "0" # rows outside the region untouched
    check grid.cells[4][1].ch == "4"
    check grid.cells[5][1].ch == "5"
    grid.processOutput("\x1b[999T") # scroll down far past the region height
    check grid.cells[1][0].ch == ""
    check grid.cells[2][0].ch == ""
    check grid.cells[3][0].ch == ""
    check grid.cells[0][1].ch == "0"
    check grid.cells[4][1].ch == "4"
    check grid.cells[5][1].ch == "5"
    check grid.scrollbackBuffer.len == 0 # region scroll never touches scrollback

suite "TerminalGrid - Insert/Delete line within region":
  test "insert line uses the region bottom margin":
    let grid = newTerminalGrid(10, 6)
    grid.processOutput("R0\r\nR1\r\nR2\r\nR3\r\nR4\r\nR5")
    grid.processOutput("\x1b[2;4r") # region 1..3
    grid.processOutput("\x1b[3;1H") # row 2 (inside region)
    grid.processOutput("\x1b[L") # insert line
    check grid.cells[2][0].ch == "" # blank inserted
    check grid.cells[3][1].ch == "2" # old R2 pushed to region bottom
    check grid.cells[4][1].ch == "4" # row 4 (below region) untouched
    check grid.cells[1][1].ch == "1" # row 1 untouched

  test "delete line uses the region bottom margin and is a no-op outside":
    let grid = newTerminalGrid(10, 6)
    grid.processOutput("R0\r\nR1\r\nR2\r\nR3\r\nR4\r\nR5")
    grid.processOutput("\x1b[2;4r") # region 1..3
    grid.processOutput("\x1b[2;1H") # row 1 (region top)
    grid.processOutput("\x1b[M") # delete line
    check grid.cells[1][1].ch == "2" # old R2 up
    check grid.cells[2][1].ch == "3" # old R3 up
    check grid.cells[3][0].ch == "" # blank at region bottom
    check grid.cells[4][1].ch == "4" # row 4 untouched
    grid.processOutput("\x1b[6;1H") # row 5 (outside region)
    grid.processOutput("\x1b[M") # no-op
    check grid.cells[5][1].ch == "5"

suite "TerminalGrid - Resize with region and alt screen":
  test "resize resets the scrolling region":
    let grid = newTerminalGrid(10, 6)
    grid.processOutput("\x1b[2;4r")
    check grid.scrollBottom == 3
    grid.resize(20, 8)
    check grid.scrollTop == 0
    check grid.scrollBottom == 7

  test "resize during alt screen keeps primary readable after exit":
    let grid = newTerminalGrid(10, 4)
    grid.processOutput("PRIMARY")
    grid.processOutput("\x1b[?1049h")
    grid.resize(20, 6)
    grid.processOutput("ALT")
    grid.processOutput("\x1b[?1049l")
    check grid.cols == 20
    check grid.rows == 6
    check grid.cells.len == 6
    check grid.cells[0].len == 20
    check grid.cells[0][0].ch == "P"
    check grid.cells[0][6].ch == "Y"

  test "saved cursor is clamped on resize":
    let grid = newTerminalGrid(20, 20)
    grid.processOutput("\x1b[18;18H")
    grid.processOutput("\x1b7") # DECSC
    grid.resize(10, 10)
    grid.processOutput("\x1b8") # DECRC
    check grid.cursorRow >= 0
    check grid.cursorRow <= 9
    check grid.cursorCol >= 0
    check grid.cursorCol <= 9

suite "TerminalGrid - RIS reset completeness":
  test "RIS clears saved cursor/SGR state and restores cursor visibility":
    let grid = newTerminalGrid(20, 10)
    # Move, set bold+red SGR, hide the cursor, then save it all with DECSC
    grid.processOutput("\x1b[5;6H\x1b[1;31m\x1b[?25l")
    grid.processOutput("\x1b7") # DECSC saves cursor + SGR
    check grid.cursorVisible == false
    grid.processOutput("\x1bc") # RIS
    check grid.cursorVisible == true
    check grid.savedCursorRow == 0
    check grid.savedCursorCol == 0
    check grid.savedFg.kind == ckDefault
    check grid.savedBg.kind == ckDefault
    check grid.savedAttrs == {}
    # A later DECRC must not resurrect the pre-reset cursor or SGR state
    grid.processOutput("\x1b[3;4H\x1b8") # move, then DECRC
    check grid.cursorRow == 0
    check grid.cursorCol == 0
    check grid.currentFg.kind == ckDefault
    check grid.currentAttrs == {}

suite "TerminalGrid - toPlainText with alt screen":
  test "alt screen snapshot excludes primary scrollback":
    let grid = newTerminalGrid(10, 3)
    grid.processOutput("L0\r\nL1\r\nL2\r\nL3\r\nL4") # spills into scrollback
    check grid.scrollbackBuffer.len > 0
    grid.processOutput("\x1b[?1049h") # enter alt screen
    grid.processOutput("\x1b[HALTLINE")
    let snap = grid.toPlainText()
    check "ALTLINE" in snap
    check "L0" notin snap # primary scrollback must not bleed through
    grid.processOutput("\x1b[?1049l") # back to primary
    check "L0" in grid.toPlainText() # scrollback visible again

suite "TerminalGrid - Insert/Delete line clamps large counts":
  test "insert line count beyond the region just blanks it":
    let grid = newTerminalGrid(10, 6)
    grid.processOutput("R0\r\nR1\r\nR2\r\nR3\r\nR4\r\nR5")
    grid.processOutput("\x1b[2;4r") # region rows 1..3
    grid.processOutput("\x1b[2;1H") # region top (row 1)
    grid.processOutput("\x1b[999L") # far more lines than the region holds
    check grid.cells[1][0].ch == "" # region fully blanked
    check grid.cells[2][0].ch == ""
    check grid.cells[3][0].ch == ""
    check grid.cells[0][1].ch == "0" # rows outside the region untouched
    check grid.cells[4][1].ch == "4"
    check grid.cells[5][1].ch == "5"

  test "delete line count beyond the region just blanks it":
    let grid = newTerminalGrid(10, 6)
    grid.processOutput("R0\r\nR1\r\nR2\r\nR3\r\nR4\r\nR5")
    grid.processOutput("\x1b[2;4r") # region rows 1..3
    grid.processOutput("\x1b[2;1H") # region top (row 1)
    grid.processOutput("\x1b[999M") # far more lines than the region holds
    check grid.cells[1][0].ch == "" # region fully blanked
    check grid.cells[2][0].ch == ""
    check grid.cells[3][0].ch == ""
    check grid.cells[0][1].ch == "0" # rows outside the region untouched
    check grid.cells[4][1].ch == "4"
    check grid.cells[5][1].ch == "5"

suite "TerminalGrid - OSC sequences":
  test "OSC 0 sets the window title (BEL terminated)":
    let grid = newTerminalGrid(20, 3)
    grid.processOutput("\x1b]0;my title\x07")
    check grid.title == "my title"
    check grid.parserState == apsNormal

  test "OSC 2 sets the window title (ST terminated)":
    let grid = newTerminalGrid(20, 3)
    grid.processOutput("\x1b]2;another\x1b\\")
    check grid.title == "another"
    check grid.parserState == apsNormal

  test "unterminated OSC past the cap aborts to normal and frees the buffer":
    let grid = newTerminalGrid(20, 3)
    # OSC introducer then a flood with no terminator (BEL/ST).
    grid.processOutput("\x1b]0;" & repeat('A', MaxOscLength * 2))
    check grid.parserState == apsNormal
    check grid.escapeBuffer.len == 0 # bounded, not grown to the flood size

  test "oversized OSC does not commit a title":
    let grid = newTerminalGrid(20, 3)
    grid.processOutput("\x1b]0;" & repeat('A', MaxOscLength + 16) & "\x07")
    # Aborted before the terminator, so no title is set; the overflowing byte
    # and tail are processed as normal output rather than the OSC payload.
    check grid.title == ""
    check grid.parserState == apsNormal

  test "the byte that overflows the OSC cap is reprocessed, not dropped":
    let grid = newTerminalGrid(20, 3)
    # Sized so the very last 'A' is the byte that trips the cap. With the buffer
    # holding "0;", MaxOscLength-1 more bytes fill it and trigger on the last.
    grid.processOutput("\x1b]0;" & repeat('A', MaxOscLength - 1))
    check grid.parserState == apsNormal
    check grid.cursorCol == 1 # the overflowing 'A' was painted, not lost
    check grid.cells[0][0].ch == "A"

  test "unterminated OSC stays bounded across PTY reads":
    # The real DoS vector: escapeBuffer/parserState persist across processOutput
    # calls, so a flood split over many reads must stay capped, not accumulate.
    let grid = newTerminalGrid(20, 3)
    grid.processOutput("\x1b]0;") # OSC introducer in its own read
    let chunk = repeat('A', 256)
    var reads = 0
    while grid.parserState == apsOsc and reads < 1000:
      grid.processOutput(chunk) # each read is a separate PTY chunk
      check grid.escapeBuffer.len <= MaxOscLength # never grows past the cap
      inc reads
    check grid.parserState == apsNormal # aborted once the payload crossed the cap
    check grid.escapeBuffer.len == 0

suite "TerminalGrid - CSI sequences":
  test "unterminated CSI past the cap aborts to normal and frees the buffer":
    let grid = newTerminalGrid(20, 3)
    # CSI introducer then a flood of parameter bytes with no final byte.
    grid.processOutput("\x1b[" & repeat(';', MaxCsiLength * 2))
    check grid.parserState == apsNormal
    check grid.escapeBuffer.len == 0 # bounded, not grown to the flood size

  test "a valid CSI still parses after the buffer was capped":
    let grid = newTerminalGrid(20, 3)
    # Flood aborts the first sequence; a following well-formed CSI must work.
    grid.processOutput("\x1b[" & repeat(';', MaxCsiLength * 2) & "\x1b[31m")
    check grid.parserState == apsNormal
    check grid.currentFg.kind == ckIndexed
    check grid.currentFg.index == 1 # SGR 31 -> red

  test "the byte that overflows the CSI cap is reprocessed, not dropped":
    let grid = newTerminalGrid(20, 3)
    # MaxCsiLength bytes fill the buffer; the next ';' trips the cap and, being
    # a printable parameter byte, must land as normal text rather than vanish.
    grid.processOutput("\x1b[" & repeat(';', MaxCsiLength + 1))
    check grid.parserState == apsNormal
    check grid.cursorCol == 1 # the overflowing ';' was painted, not lost
    check grid.cells[0][0].ch == ";"

  test "unterminated CSI stays bounded across PTY reads":
    # Same DoS vector as OSC: a parameter-byte flood split over many reads must
    # stay capped because escapeBuffer/parserState carry over between reads.
    let grid = newTerminalGrid(20, 3)
    grid.processOutput("\x1b[") # CSI introducer in its own read
    let chunk = repeat(';', 256)
    var reads = 0
    while grid.parserState == apsCsi and reads < 1000:
      grid.processOutput(chunk) # each read is a separate PTY chunk
      check grid.escapeBuffer.len <= MaxCsiLength # never grows past the cap
      inc reads
    check grid.parserState == apsNormal # aborted once the payload crossed the cap
    check grid.escapeBuffer.len == 0
