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

## Tests for motion.nim

import std/[unittest, strutils, options, sequtils]

import pkg/results

import ../src/moepkg/[unicode_utils, types, modes]
import ../src/moepkg/buffer/[core, fold]
import ../src/moepkg/motion {.all.}
import ../src/moepkg/visible_rows

proc move(
    executor: MotionExecutor,
    pos: CursorPosition,
    motion: Motion,
    count = 1,
    targetChar = "",
): CursorPosition =
  executor.calculateNewPosition(
    pos, MotionCommand(motion: motion, count: count, targetChar: targetChar)
  )

suite "TillChar Motion":
  test "tillChar moves to correct position":
    # Setup: "abcxyz"
    let buffer = newTextBuffer("abcxyz")
    let executor = newMotionExecutor(buffer)

    # Start at 'a' (column 0), find 'x' (column 3)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.move(currentPos, Motion.TillChar, 1, "x")

    check result.y == 0
    check result.x == 2 # Should be at 'c', which is column 2

  test "findChar moves to correct position":
    # Setup: "abcxyz"
    let buffer = newTextBuffer("abcxyz")
    let executor = newMotionExecutor(buffer)

    # Start at 'a' (column 0), find 'x' (column 3)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.move(currentPos, Motion.FindChar, 1, "x")

    check result.y == 0
    check result.x == 3 # Should be at 'x', which is column 3

suite "OperatorRange":
  test "extractRangeText for TillChar range":
    # Setup: "abcxyz"
    let buffer = newTextBuffer("abcxyz")

    # An inclusive range
    let range = OperatorRange(
      start: BufferPosition(line: 0, column: 0),
      endPos: BufferPosition(line: 0, column: 2),
      isLinewise: false,
    )

    let text = extractRangeText(buffer, range)

    check text == "abc"

suite "Basic Motion - Left/Right":
  test "moveLeft from middle of line":
    let buffer = newTextBuffer("hello")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 3, y: 0)
    let result = executor.moveLeft(currentPos, 1)
    check result.x == 2
    check result.y == 0

  test "moveLeft with count":
    let buffer = newTextBuffer("hello")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 4, y: 0)
    let result = executor.moveLeft(currentPos, 3)
    check result.x == 1

  test "moveLeft at beginning of line":
    let buffer = newTextBuffer("hello")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveLeft(currentPos, 1)
    check result.x == 0

  test "moveRight from beginning":
    let buffer = newTextBuffer("hello")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveRight(currentPos, 1)
    check result.x == 1

  test "moveRight with count":
    let buffer = newTextBuffer("hello")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveRight(currentPos, 3)
    check result.x == 3

  test "moveRight at end of line":
    let buffer = newTextBuffer("hello")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 4, y: 0)
    let result = executor.moveRight(currentPos, 1)
    check result.x == 4 # Should stay at last character

suite "Backspace Motion - whichwrap b":
  test "Backspace at column 0 wraps to previous line end":
    let buffer = newTextBuffer("abc\ndef")
    let executor = newMotionExecutor(buffer)
    let result = executor.move(CursorPosition(x: 0, y: 1), Motion.Backspace, 1)
    check result == CursorPosition(x: 2, y: 0)

  test "Backspace within line moves left":
    let buffer = newTextBuffer("abc\ndef")
    let executor = newMotionExecutor(buffer)
    let result = executor.move(CursorPosition(x: 2, y: 0), Motion.Backspace, 1)
    check result == CursorPosition(x: 1, y: 0)

  test "Backspace at first line stays":
    let buffer = newTextBuffer("abc\ndef")
    let executor = newMotionExecutor(buffer)
    let result = executor.move(CursorPosition(x: 0, y: 0), Motion.Backspace, 1)
    check result == CursorPosition(x: 0, y: 0)

  test "Backspace with count wraps across lines":
    let buffer = newTextBuffer("abc\ndef")
    let executor = newMotionExecutor(buffer)
    let result = executor.move(CursorPosition(x: 1, y: 1), Motion.Backspace, 2)
    check result == CursorPosition(x: 2, y: 0)

  test "Backspace from empty line wraps to previous line end":
    let buffer = newTextBuffer("abc\n\ndef")
    let executor = newMotionExecutor(buffer)
    let result = executor.move(CursorPosition(x: 0, y: 1), Motion.Backspace, 1)
    check result == CursorPosition(x: 2, y: 0)

  test "Backspace in Visual mode wraps past line end":
    let buffer = newTextBuffer("abc\ndef")
    let executor = newMotionExecutor(buffer)
    let result = executor.calculateNewPosition(
      CursorPosition(x: 0, y: 1),
      MotionCommand(motion: Motion.Backspace, count: 1),
      mode = EditorMode.Visual,
    )
    check result == CursorPosition(x: 3, y: 0)

  test "Left at column 0 does not wrap":
    let buffer = newTextBuffer("abc\ndef")
    let executor = newMotionExecutor(buffer)
    let result = executor.move(CursorPosition(x: 0, y: 1), Motion.Left, 1)
    check result == CursorPosition(x: 0, y: 1)

  test "Backspace with operator wraps":
    let buffer = newTextBuffer("abc\ndef")
    let executor = newMotionExecutor(buffer)
    let landing = executor.landMotion(
      CursorPosition(x: 0, y: 1),
      MotionCommand(motion: Motion.Backspace, count: 1),
      operator = some(OpDelete),
    )
    check landing.pos == BufferPosition(line: 0, column: 2)
    check landing.motionType == mtExclusive
    check not landing.failed

suite "Basic Motion - Up/Down":
  test "moveDown from first line":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveDown(currentPos, 1)
    check result.y == 1

  test "moveDown with count":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveDown(currentPos, 2)
    check result.y == 2

  test "moveDown at last line":
    let buffer = newTextBuffer("line1\nline2")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 1)
    let result = executor.moveDown(currentPos, 1)
    check result.y == 1 # Should stay at last line

  test "moveUp from second line":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 2)
    let result = executor.moveUp(currentPos, 1)
    check result.y == 1

  test "moveUp with count":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 3)
    let result = executor.moveUp(currentPos, 2)
    check result.y == 1

  test "moveUp at first line":
    let buffer = newTextBuffer("line1\nline2")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveUp(currentPos, 1)
    check result.y == 0 # Should stay at first line

suite "Line Motion":
  test "moveHome moves to column 0":
    let buffer = newTextBuffer("  hello")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 5, y: 0)
    let result = executor.moveHome(currentPos)
    check result.x == 0

  test "moveFirstNonBlank skips whitespace":
    let buffer = newTextBuffer("  hello")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveFirstNonBlank(currentPos)
    check result.x == 2 # First non-whitespace is 'h'

  test "moveFirstNonBlank with tabs":
    let buffer = newTextBuffer("\t\thello")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveFirstNonBlank(currentPos)
    check result.x == 2

  test "moveEnd moves to last character":
    let buffer = newTextBuffer("hello")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveEnd(currentPos)
    check result.x == 4 # Last character 'o' is at index 4

  test "moveLastNonBlank with trailing spaces":
    let buffer = newTextBuffer("hello   ")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveLastNonBlank(currentPos)
    check result.x == 4 # Last non-whitespace 'o' is at index 4

suite "Word Motion":
  test "w basic":
    let buffer = newTextBuffer("hello world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.move(currentPos, Motion.WordForward, 1)
    check result.x == 6 # 'w' of "world"

  test "w with symbols":
    let buffer = newTextBuffer("hello,world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.move(currentPos, Motion.WordForward, 1)
    check result.x == 5 # ',' is a separate word

  test "w across lines":
    let buffer = newTextBuffer("hello\nworld")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 3, y: 0)
    let result = executor.move(currentPos, Motion.WordForward, 1)
    check result.y == 1
    check result.x == 0

  test "b basic":
    let buffer = newTextBuffer("hello world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 8, y: 0)
    let result = executor.move(currentPos, Motion.WordBackward, 1)
    check result.x == 6 # Start of "world"

  test "b to previous word":
    let buffer = newTextBuffer("hello world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 6, y: 0)
    let result = executor.move(currentPos, Motion.WordBackward, 1)
    check result.x == 0 # Start of "hello"

  test "e basic":
    let buffer = newTextBuffer("hello world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.move(currentPos, Motion.WordEnd, 1)
    check result.x == 4 # End of "hello"

  test "e to next word end":
    let buffer = newTextBuffer("hello world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 4, y: 0)
    let result = executor.move(currentPos, Motion.WordEnd, 1)
    check result.x == 10 # End of "world"

  test "w with Unicode":
    let buffer = newTextBuffer("hello 日本語 world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.move(currentPos, Motion.WordForward, 1)
    check result.x == 6 # Start of '日本語'

  test "w past Unicode word":
    let buffer = newTextBuffer("hello 日本語 world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 6, y: 0)
    let result = executor.move(currentPos, Motion.WordForward, 1)
    check result.x == 10 # Start of 'world'

  test "b with Unicode":
    let buffer = newTextBuffer("hello 日本語 world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 10, y: 0)
    let result = executor.move(currentPos, Motion.WordBackward, 1)
    check result.x == 6 # Start of '日本語'

  test "e with Unicode":
    let buffer = newTextBuffer("hello 日本語 world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 6, y: 0)
    let result = executor.move(currentPos, Motion.WordEnd, 1)
    check result.x == 8 # End of '日本語'

  test "e crosses a single empty line":
    let buffer = newTextBuffer("foo\n\nbar")
    let executor = newMotionExecutor(buffer)
    let result = executor.move(CursorPosition(x: 2, y: 0), Motion.WordEnd, 1)
    check result.y == 2
    check result.x == 2 # End of "bar"

  test "e crosses multiple empty lines":
    let buffer = newTextBuffer("foo\n\n\n\nbar")
    let executor = newMotionExecutor(buffer)
    let result = executor.move(CursorPosition(x: 2, y: 0), Motion.WordEnd, 1)
    check result.y == 4
    check result.x == 2 # End of "bar"

  test "b stops at an empty line, as in Vim":
    let buffer = newTextBuffer("foo\n\nbar")
    let executor = newMotionExecutor(buffer)
    let result = executor.move(CursorPosition(x: 0, y: 2), Motion.WordBackward, 1)
    check result.y == 1
    check result.x == 0

  test "b goes on past empty lines with a count":
    let buffer = newTextBuffer("foo\n\n\n\nbar")
    let executor = newMotionExecutor(buffer)
    let result = executor.move(CursorPosition(x: 0, y: 4), Motion.WordBackward, 4)
    check result.y == 0
    check result.x == 0 # Start of "foo"

  test "W, B, E and gE take every non-blank as one class":
    let buffer = newTextBuffer("foo.bar(x) baz\n  ,q")
    let executor = newMotionExecutor(buffer)
    for (motion, x, y, expected) in [
      (Motion.WideWordForward, 0, 0, (11, 0)),
      (Motion.WordForward, 0, 0, (3, 0)),
      (Motion.WideWordForward, 11, 0, (2, 1)),
      (Motion.WideWordEnd, 0, 0, (9, 0)),
      (Motion.WordEnd, 0, 0, (2, 0)),
      (Motion.WideWordBackward, 3, 1, (2, 1)),
      (Motion.WideWordBackward, 2, 1, (11, 0)),
      (Motion.WideWordEndBackward, 3, 1, (13, 0)),
      (Motion.WideWordEndBackward, 13, 0, (9, 0)),
    ]:
      let result = executor.move(CursorPosition(x: x, y: y), motion, 1)
      checkpoint($motion & " from " & $(x, y))
      check (result.x, result.y) == expected

  test "the ideographic and no-break spaces are blanks, as in Vim's utf_class":
    let buffer = newTextBuffer("foo　bar baz qux")
    let executor = newMotionExecutor(buffer)
    for (motion, x, expected) in [
      (Motion.WideWordForward, 0, 4),
      (Motion.WordForward, 0, 4),
      (Motion.WideWordEnd, 0, 2),
      (Motion.WordEnd, 2, 6),
      (Motion.WideWordBackward, 8, 4),
      (Motion.WordBackward, 4, 0),
      (Motion.WideWordEndBackward, 8, 6),
      (Motion.WordEndBackward, 4, 2),
    ]:
      let result = executor.move(CursorPosition(x: x, y: 0), motion, 1)
      checkpoint($motion & " from " & $x)
      check (result.x, result.y) == (expected, 0)

  test "w, W, e and E fail when the buffer ends first, but not with an operator":
    # As Vim 9.2, measured by whether a macro stops (moe does not stop one on a
    # failed motion yet); `dW`/`dE` take the last character
    let buffer = newTextBuffer("foo bar")
    let executor = newMotionExecutor(buffer)
    for (motion, x, count, failed) in [
      (Motion.WordForward, 6, 1, true),
      (Motion.WideWordForward, 6, 1, true),
      (Motion.WordEnd, 6, 1, true),
      (Motion.WideWordEnd, 6, 1, true),
      (Motion.WideWordForward, 4, 1, false),
      (Motion.WideWordForward, 0, 3, false),
      (Motion.WideWordEnd, 0, 3, true),
    ]:
      let
        start = CursorPosition(x: x, y: 0)
        cmd = MotionCommand(motion: motion, count: count)
        bare = executor.landMotion(start, cmd)
        operated = executor.landMotion(start, cmd, operator = some(OpDelete))
      checkpoint($motion & " from " & $x & " count " & $count)
      check bare.pos == BufferPosition(line: 0, column: 6)
      check bare.failed == failed
      check not operated.failed

  test "b crosses whitespace-only line":
    let buffer = newTextBuffer("foo\n  \nbar")
    let executor = newMotionExecutor(buffer)
    let result = executor.move(CursorPosition(x: 0, y: 2), Motion.WordBackward, 1)
    check result.y == 0
    check result.x == 0 # Start of "foo"

suite "Find/Till Char Backward":
  test "findCharBackward finds previous occurrence":
    let buffer = newTextBuffer("abcxabc")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 6, y: 0)
    let result = executor.move(currentPos, Motion.FindCharBackward, 1, "a")
    check result.x == 4

  test "findCharBackward with count":
    let buffer = newTextBuffer("abcxabc")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 6, y: 0)
    let result = executor.move(currentPos, Motion.FindCharBackward, 2, "a")
    check result.x == 0

  test "tillCharBackward stops after target":
    let buffer = newTextBuffer("abcxyz")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 5, y: 0)
    let result = executor.move(currentPos, Motion.TillCharBackward, 1, "c")
    check result.x == 3 # One after 'c'

suite "Find/Till Char - Unicode and long lines":
  test "findChar uses character positions past multibyte runes":
    # 日(0) 本(1) x(2) y(3) 語(4) x(5)
    let buffer = newTextBuffer("日本xy語x")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    check executor.move(currentPos, Motion.FindChar, 1, "x").x == 2
    check executor.move(currentPos, Motion.FindChar, 2, "x").x == 5

  test "findCharBackward uses character positions past multibyte runes":
    # x(0) 本(1) x(2) 語(3)
    let buffer = newTextBuffer("x本x語")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 3, y: 0)
    check executor.move(currentPos, Motion.FindCharBackward, 1, "x").x == 2
    check executor.move(currentPos, Motion.FindCharBackward, 2, "x").x == 0

  test "findChar leaves cursor unchanged when target is absent":
    let buffer = newTextBuffer("abcdef")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    check executor.move(currentPos, Motion.FindChar, 1, "z").x == 0

  test "findChar finds target at end of a long line":
    let buffer = newTextBuffer("a".repeat(5000) & "x")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    check executor.move(currentPos, Motion.FindChar, 1, "x").x == 5000

  test "findChar/findCharBackward find a multibyte target rune":
    # 語(0) a(1) 語(2) b(3) 語(4)
    let buffer = newTextBuffer("語a語b語")
    let executor = newMotionExecutor(buffer)
    check executor.move(CursorPosition(x: 0, y: 0), Motion.FindChar, 1, "語").x == 2
    check executor.move(CursorPosition(x: 0, y: 0), Motion.FindChar, 2, "語").x == 4
    check executor.move(CursorPosition(x: 4, y: 0), Motion.FindCharBackward, 1, "語").x ==
      2
    check executor.move(CursorPosition(x: 4, y: 0), Motion.FindCharBackward, 2, "語").x ==
      0

  test "tillChar/tillCharBackward stop adjacent to a target past multibyte runes":
    # a(0) 語(1) b(2) y(3)
    let buffer = newTextBuffer("a語by")
    let executor = newMotionExecutor(buffer)
    check executor.move(CursorPosition(x: 0, y: 0), Motion.TillChar, 1, "y").x == 2
    check executor.move(CursorPosition(x: 3, y: 0), Motion.TillCharBackward, 1, "a").x ==
      1

  test "findChar leaves cursor unchanged for empty or multi-rune targets":
    let buffer = newTextBuffer("abc")
    let executor = newMotionExecutor(buffer)
    let pos = CursorPosition(x: 0, y: 0)
    check executor.move(pos, Motion.FindChar, 1, "").x == 0
    check executor.move(pos, Motion.FindChar, 1, "bc").x == 0
    check executor.move(CursorPosition(x: 2, y: 0), Motion.FindCharBackward, 1, "").x ==
      2
    check executor.move(CursorPosition(x: 2, y: 0), Motion.FindCharBackward, 1, "ab").x ==
      2

suite "Paragraph Motion":
  test "} to blank line":
    let buffer = newTextBuffer("line1\nline2\n\nline4")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.move(currentPos, Motion.ParagraphForward, 1)
    check result.y == 2 # Blank line

  test "{ to blank line":
    let buffer = newTextBuffer("line1\n\nline3\nline4")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 3)
    let result = executor.move(currentPos, Motion.ParagraphBackward, 1)
    check result.y == 1 # Blank line

suite "First/Last Line Motion":
  test "moveFirstLine goes to line 0":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 2, y: 2)
    let result = executor.moveFirstLine(currentPos)
    check result.y == 0
    check result.x == 0

  test "moveLastLine goes to last line":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveLastLine(currentPos)
    check result.y == 2

  test "moveLastLine with count goes to specific line":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveLastLine(currentPos, 2)
    check result.y == 1 # Line 2 (0-indexed)

  test "moveLastLine with count 1 goes to line 1 (1G, not G)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 2)
    let result = executor.moveLastLine(currentPos, 1)
    check result.y == 0

  test "moveFirstLine with count 1 goes to first line (1gg)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 2, y: 2)
    let result = executor.moveFirstLine(currentPos, 1)
    check result.y == 0
    check result.x == 0

  test "moveFirstLine with count goes to specific line":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 2, y: 0)
    let result = executor.moveFirstLine(currentPos, 3)
    check result.y == 2
    check result.x == 0

  test "moveFirstLine with count exceeding buffer clamps to last line":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveFirstLine(currentPos, 99)
    check result.y == 2
    check result.x == 0

  test "gg and G land on the first non-blank (startofline)":
    let buffer = newTextBuffer("  line1\n\tline2\n\n    ")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 2)
    check executor.moveFirstLine(currentPos) == CursorPosition(x: 2, y: 0)
    check executor.moveFirstLine(currentPos, 2) == CursorPosition(x: 1, y: 1)
    check executor.moveLastLine(currentPos, 2) == CursorPosition(x: 1, y: 1)
    check executor.moveLastLine(currentPos, 3) == CursorPosition(x: 0, y: 2)
    # An all-blank line lands on its last character.
    check executor.moveLastLine(currentPos) == CursorPosition(x: 3, y: 3)

  test "FirstLine motion with count lands on counted line":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4\nline5")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 2, y: 4)
    let result = executor.move(currentPos, Motion.FirstLine, 3)
    check result.y == 2
    check result.x == 0

suite "Matching Bracket":
  test "moveToMatchingBracket forward":
    let buffer = newTextBuffer("(hello)")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveToMatchingBracket(currentPos)
    check result.x == 6 # Closing ')'

  test "moveToMatchingBracket backward":
    let buffer = newTextBuffer("(hello)")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 6, y: 0)
    let result = executor.moveToMatchingBracket(currentPos)
    check result.x == 0 # Opening '('

  test "moveToMatchingBracket nested":
    let buffer = newTextBuffer("((inner))")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveToMatchingBracket(currentPos)
    check result.x == 8 # Outer closing ')'

  test "moveToMatchingBracket starts from the next bracket on the line":
    let buffer = newTextBuffer("x [a(b)]")
    let executor = newMotionExecutor(buffer)
    let result = executor.moveToMatchingBracket(CursorPosition(x: 0, y: 0))
    check result.x == 7

  test "moveToMatchingBracket fails when the next bracket has no match":
    let buffer = newTextBuffer("a ) (b)")
    let executor = newMotionExecutor(buffer)
    let result = executor.moveToMatchingBracket(CursorPosition(x: 0, y: 0))
    check result.x == 0

  test "moveToMatchingBracket fails with no bracket after the cursor":
    let buffer = newTextBuffer("(b) c")
    let executor = newMotionExecutor(buffer)
    let result = executor.moveToMatchingBracket(CursorPosition(x: 4, y: 0))
    check result.x == 4

  test "moveToMatchingBracket with braces":
    let buffer = newTextBuffer("{hello}")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveToMatchingBracket(currentPos)
    check result.x == 6

  test "moveToMatchingBracket forward past multibyte runes":
    # ((0) 日(1) 本(2) 語(3) )(4)
    let buffer = newTextBuffer("(日本語)")
    let executor = newMotionExecutor(buffer)
    let result = executor.moveToMatchingBracket(CursorPosition(x: 0, y: 0))
    check result.x == 4

  test "moveToMatchingBracket forward across lines with multibyte runes":
    let buffer = newTextBuffer("(日本\n語x)")
    let executor = newMotionExecutor(buffer)
    let result = executor.moveToMatchingBracket(CursorPosition(x: 0, y: 0)) # the '('
    check result.y == 1
    check result.x == 2

  test "moveToMatchingBracket forward on a long line":
    let buffer = newTextBuffer("(" & "a".repeat(5000) & ")")
    let executor = newMotionExecutor(buffer)
    let result = executor.moveToMatchingBracket(CursorPosition(x: 0, y: 0)) # the '('
    check result.x == 5001

  test "moveToMatchingBracket forward respects nesting depth":
    # ((inner)) : ( 0 ( 1 ... ) 7 ) 8
    let buffer = newTextBuffer("((inner))")
    let executor = newMotionExecutor(buffer)
    check executor.moveToMatchingBracket(CursorPosition(x: 1, y: 0)).x == 7 # inner '('
    check executor.moveToMatchingBracket(CursorPosition(x: 0, y: 0)).x == 8 # outer '('

  test "moveToMatchingBracket backward past multibyte runes":
    # ((0) 日(1) 本(2) 語(3) )(4)
    let buffer = newTextBuffer("(日本語)")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 4, y: 0)
    let result = executor.moveToMatchingBracket(currentPos)
    check result.x == 0

  test "moveToMatchingBracket backward across lines with multibyte runes":
    let buffer = newTextBuffer("(日本\n語x)")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 2, y: 1) # the ')'
    let result = executor.moveToMatchingBracket(currentPos)
    check result.y == 0
    check result.x == 0

  test "moveToMatchingBracket backward on a long line":
    let buffer = newTextBuffer("(" & "a".repeat(5000) & ")")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 5001, y: 0) # the ')'
    let result = executor.moveToMatchingBracket(currentPos)
    check result.x == 0

  test "moveToMatchingBracket backward respects nesting depth":
    # ((inner)) : ( 0 ( 1 ... ) 7 ) 8
    let buffer = newTextBuffer("((inner))")
    let executor = newMotionExecutor(buffer)
    check executor.moveToMatchingBracket(CursorPosition(x: 7, y: 0)).x == 1 # inner ')'
    check executor.moveToMatchingBracket(CursorPosition(x: 8, y: 0)).x == 0 # outer ')'

  test "moveToMatchingBracket backward across lines respects nesting":
    let buffer = newTextBuffer("(a\n(b)\nc)")
    let executor = newMotionExecutor(buffer)
    # outer ')' at line 2 col 1 -> matching '(' at line 0 col 0
    let result = executor.moveToMatchingBracket(CursorPosition(x: 1, y: 2))
    check result.y == 0
    check result.x == 0

  test "moveToMatchingBracket leaves cursor unchanged when unbalanced":
    let buffer = newTextBuffer("abc)")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 3, y: 0) # ')' with no opening '('
    let result = executor.moveToMatchingBracket(currentPos)
    check result.y == 0
    check result.x == 3

suite "Text Objects - Word":
  test "findWordBoundaries inner word":
    let buffer = newTextBuffer("hello world")
    let cursor = BufferPosition(line: 0, column: 2)
    let result = findWordBoundaries(buffer, cursor, inner = true)
    check result.isOk
    let range = result.get
    check range.start.column == 0
    check range.endPos.column == 4 # 'hello' is columns 0-4

  test "findWordBoundaries around word":
    let buffer = newTextBuffer("hello world")
    let cursor = BufferPosition(line: 0, column: 2)
    let result = findWordBoundaries(buffer, cursor, inner = false)
    check result.isOk
    let range = result.get
    check range.start.column == 0
    check range.endPos.column == 5 # 'hello ' including trailing space

  test "findWordBoundaries inner word - Unicode (Japanese)":
    let buffer = newTextBuffer("hello 日本語 world")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findWordBoundaries(buffer, cursor, inner = true)
    check result.isOk
    let range = result.get
    check range.start.column == 6
    check range.endPos.column == 8 # 日本語 is columns 6-8

  test "findWordBoundaries around word - Unicode (Japanese)":
    let buffer = newTextBuffer("hello 日本語 world")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findWordBoundaries(buffer, cursor, inner = false)
    check result.isOk
    let range = result.get
    check range.start.column == 6
    check range.endPos.column == 9 # 日本語 + trailing space

  test "findWordBoundaries inner on symbol":
    let buffer = newTextBuffer("hello ++ world")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findWordBoundaries(buffer, cursor, inner = true)
    check result.isOk
    let range = result.get
    check range.start.column == 6
    check range.endPos.column == 7 # ++ is columns 6-7

  test "findWordBoundaries around on symbol":
    let buffer = newTextBuffer("hello ++ world")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findWordBoundaries(buffer, cursor, inner = false)
    check result.isOk
    let range = result.get
    check range.start.column == 6
    check range.endPos.column == 8 # ++ + trailing space

  test "findWordBoundaries inner on whitespace":
    let buffer = newTextBuffer("hello   world")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findWordBoundaries(buffer, cursor, inner = true)
    check result.isOk
    let range = result.get
    check range.start.column == 5
    check range.endPos.column == 7 # spaces at columns 5-7

  test "findWordBoundaries around on whitespace":
    let buffer = newTextBuffer("hello   world")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findWordBoundaries(buffer, cursor, inner = false)
    check result.isOk
    let range = result.get
    check range.start.column == 5
    check range.endPos.column == 12 # spaces + 'world'

  test "findWordBoundaries aw cross-line from trailing whitespace":
    let buffer = newTextBuffer("hello   \nworld")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findWordBoundaries(buffer, cursor, inner = false)
    check result.isOk
    let range = result.get
    check range.start.line == 0
    check range.start.column == 5
    check range.endPos.line == 1
    check range.endPos.column == 4 # 'world' on next line

  test "findWordBoundaries iw on whitespace stays on same line":
    let buffer = newTextBuffer("hello   \nworld")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findWordBoundaries(buffer, cursor, inner = true)
    check result.isOk
    let range = result.get
    check range.start.line == 0
    check range.endPos.line == 0 # stays on same line

  test "findWideWordBoundaries inner on whitespace":
    let buffer = newTextBuffer("hello   world")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findWideWordBoundaries(buffer, cursor, inner = true)
    check result.isOk
    let range = result.get
    check range.start.column == 5
    check range.endPos.column == 7

  test "findWideWordBoundaries aW cross-line from trailing whitespace":
    let buffer = newTextBuffer("hello   \nworld")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findWideWordBoundaries(buffer, cursor, inner = false)
    check result.isOk
    let range = result.get
    check range.start.line == 0
    check range.start.column == 5
    check range.endPos.line == 1
    check range.endPos.column == 4

  test "findWordBoundaries aw at end of line (no trailing space) uses leading":
    let buffer = newTextBuffer("hello world")
    let cursor = BufferPosition(line: 0, column: 7)
    let result = findWordBoundaries(buffer, cursor, inner = false)
    check result.isOk
    let range = result.get
    check range.start.column == 5 # Leading space included
    check range.endPos.column == 10 # 'world' ends at 10

  test "findWordBoundaries aw cross-line skips empty lines":
    let buffer = newTextBuffer("hello   \n\nworld")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findWordBoundaries(buffer, cursor, inner = false)
    check result.isOk
    let range = result.get
    check range.start.line == 0
    check range.start.column == 5
    check range.endPos.line == 2
    check range.endPos.column == 4 # 'world' on line 2

  test "findWideWordBoundaries aW cross-line skips empty lines":
    let buffer = newTextBuffer("hello   \n\nworld")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findWideWordBoundaries(buffer, cursor, inner = false)
    check result.isOk
    let range = result.get
    check range.start.line == 0
    check range.start.column == 5
    check range.endPos.line == 2
    check range.endPos.column == 4

  test "findWordBoundaries aw on trailing whitespace with no word ahead fails":
    # Vim's "daw" on trailing whitespace at end of buffer is a no-op: there is
    # no word to anchor the surrounding whitespace, so the object fails.
    let buffer = newTextBuffer("word   ")
    let cursor = BufferPosition(line: 0, column: 5)
    let result = findWordBoundaries(buffer, cursor, inner = false)
    check result.isErr

  test "findWordBoundaries aw on whitespace-only line fails":
    let buffer = newTextBuffer("    ")
    let cursor = BufferPosition(line: 0, column: 1)
    let result = findWordBoundaries(buffer, cursor, inner = false)
    check result.isErr

  test "findWideWordBoundaries aW on trailing whitespace with no word ahead fails":
    let buffer = newTextBuffer("word   ")
    let cursor = BufferPosition(line: 0, column: 5)
    let result = findWideWordBoundaries(buffer, cursor, inner = false)
    check result.isErr

  test "findWordBoundaries iw on trailing whitespace still selects the run":
    # Unlike "aw", "iw" on whitespace selects just the whitespace run.
    let buffer = newTextBuffer("word   ")
    let cursor = BufferPosition(line: 0, column: 5)
    let result = findWordBoundaries(buffer, cursor, inner = true)
    check result.isOk
    let range = result.get
    check range.start.column == 4
    check range.endPos.column == 6

suite "Text Objects - Quoted":
  test "findQuotedBoundaries inner double quote":
    let buffer = newTextBuffer("say \"hello\" world")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findQuotedBoundaries(buffer, cursor, '"', inner = true)
    check result.isOk
    let range = result.get
    check range.start.column == 5
    check range.endPos.column == 9 # 'hello'

  test "findQuotedBoundaries around double quote":
    let buffer = newTextBuffer("say \"hello\" world")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findQuotedBoundaries(buffer, cursor, '"', inner = false)
    check result.isOk
    let range = result.get
    check range.start.column == 4
    check range.endPos.column == 10 # '"hello"'

  test "findQuotedBoundaries single quote":
    let buffer = newTextBuffer("say 'hello' world")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findQuotedBoundaries(buffer, cursor, '\'', inner = true)
    check result.isOk
    let range = result.get
    check range.start.column == 5
    check range.endPos.column == 9

  test "findQuotedBoundaries with multibyte runes inside and outside quotes":
    # Rune columns: 例(0) :(1) sp(2) "(3) あ(4) い(5) う(6) "(7)
    let buffer = newTextBuffer("例: \"あいう\" end")
    let cursor = BufferPosition(line: 0, column: 5)
    let innerRes = findQuotedBoundaries(buffer, cursor, '"', inner = true)
    check innerRes.isOk
    check innerRes.get.start.column == 4
    check innerRes.get.endPos.column == 6
    let aroundRes = findQuotedBoundaries(buffer, cursor, '"', inner = false)
    check aroundRes.isOk
    check aroundRes.get.start.column == 3
    check aroundRes.get.endPos.column == 7

  test "findQuotedBoundaries skips escaped quote":
    # say "a\"b" end -- the middle quote is escaped, so the pair is the outer
    # quotes and the content keeps the escaped quote.
    let buffer = newTextBuffer("say \"a\\\"b\" end")
    let cursor = BufferPosition(line: 0, column: 8) # on 'b'
    let result = findQuotedBoundaries(buffer, cursor, '"', inner = true)
    check result.isOk
    check result.get.start.column == 5
    check result.get.endPos.column == 8

  test "findQuotedBoundaries treats double backslash as not escaping":
    # "a\\" -- the second backslash is itself escaped, so the closing quote
    # is a real delimiter.
    let buffer = newTextBuffer("\"a\\\\\" x")
    let cursor = BufferPosition(line: 0, column: 1)
    let result = findQuotedBoundaries(buffer, cursor, '"', inner = true)
    check result.isOk
    check result.get.start.column == 1
    check result.get.endPos.column == 3

suite "Text Objects - Parenthesis":
  test "currentBlock cursor on close paren":
    let buffer = newTextBuffer("(x)")
    let cursor = BufferPosition(line: 0, column: 2)
    let result = currentBlock(buffer, cursor, '(', ')', inner = true, count = 1)
    check result.isOk
    let range = result.get
    check range.start.column == 1
    check range.endPos.column == 1

  test "currentBlock cursor on close paren around":
    let buffer = newTextBuffer("(x)")
    let cursor = BufferPosition(line: 0, column: 2)
    let result = currentBlock(buffer, cursor, '(', ')', inner = false, count = 1)
    check result.isOk
    let range = result.get
    check range.start.column == 0
    check range.endPos.column == 2

  test "currentBlock cursor on close paren empty":
    let buffer = newTextBuffer("()")
    let cursor = BufferPosition(line: 0, column: 1)
    let result = currentBlock(buffer, cursor, '(', ')', inner = true, count = 1)
    check result.isOk

  test "currentBlock inner":
    let buffer = newTextBuffer("func(arg)")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = currentBlock(buffer, cursor, '(', ')', inner = true, count = 1)
    check result.isOk
    let range = result.get
    check range.start.column == 5
    check range.endPos.column == 7

  test "currentBlock around":
    let buffer = newTextBuffer("func(arg)")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = currentBlock(buffer, cursor, '(', ')', inner = false, count = 1)
    check result.isOk
    let range = result.get
    check range.start.column == 4
    check range.endPos.column == 8

  test "currentBlock multi-line":
    # Close delimiter on its own line: as Vim's current_block, the inner starts
    # on the line after the open one and stops at the close line's start, which
    # an operator then takes as whole lines.
    let buffer = newTextBuffer("func(\n  arg\n)")
    let cursor = BufferPosition(line: 1, column: 2)
    let result = currentBlock(buffer, cursor, '(', ')', inner = true, count = 1)
    check result.isOk
    let range = result.get
    check not range.isEmpty
    check range.exclusive
    check (range.start.line, range.start.column) == (1, 0)
    check (range.endPos.line, range.endPos.column) == (2, 0)

  test "currentBlock with multibyte runes inside and outside":
    # Rune columns: 日(0) 本(1) 語(2) ((3) あ(4) +(5) い(6) )(7) 末(8) 尾(9)
    let buffer = newTextBuffer("日本語(あ+い)末尾")
    let cursor = BufferPosition(line: 0, column: 5)
    let innerRes = currentBlock(buffer, cursor, '(', ')', inner = true, count = 1)
    check innerRes.isOk
    check innerRes.get.start.column == 4
    check innerRes.get.endPos.column == 6
    let aroundRes = currentBlock(buffer, cursor, '(', ')', inner = false, count = 1)
    check aroundRes.isOk
    check aroundRes.get.start.column == 3
    check aroundRes.get.endPos.column == 7

  test "currentBlock skips a closed pair when scanning backward":
    # f(g(x) + y) with the cursor on '+': the backward scan passes over the
    # closed inner pair (x) and must select the outer pair, like vim's i(.
    let buffer = newTextBuffer("f(g(x) + y)")
    let cursor = BufferPosition(line: 0, column: 7)
    let result = currentBlock(buffer, cursor, '(', ')', inner = true, count = 1)
    check result.isOk
    check result.get.start.column == 2
    check result.get.endPos.column == 9

  test "currentBlock selects the innermost enclosing pair":
    let buffer = newTextBuffer("f(g(x))")
    let cursor = BufferPosition(line: 0, column: 4)
    let result = currentBlock(buffer, cursor, '(', ')', inner = true, count = 1)
    check result.isOk
    check result.get.start.column == 4
    check result.get.endPos.column == 4

  test "currentBlock cursor on close paren of the outer nested pair":
    # f(g(x)) with the cursor on the outer ')': the seeded close must match
    # the outer '(', not the inner one.
    let buffer = newTextBuffer("f(g(x))")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = currentBlock(buffer, cursor, '(', ')', inner = false, count = 1)
    check result.isOk
    check result.get.start.column == 1
    check result.get.endPos.column == 6

  test "currentBlock cursor on close paren multi-line":
    let buffer = newTextBuffer("func(\n  arg\n)")
    let cursor = BufferPosition(line: 2, column: 0)
    let innerRes = currentBlock(buffer, cursor, '(', ')', inner = true, count = 1)
    check innerRes.isOk
    check (innerRes.get.start.line, innerRes.get.start.column) == (1, 0)
    check (innerRes.get.endPos.line, innerRes.get.endPos.column) == (2, 0)
    let aroundRes = currentBlock(buffer, cursor, '(', ')', inner = false, count = 1)
    check aroundRes.isOk
    check (aroundRes.get.start.line, aroundRes.get.start.column) == (0, 4)
    check (aroundRes.get.endPos.line, aroundRes.get.endPos.column) == (2, 0)

suite "calculateTextObjectRange":
  test "word text object":
    let buffer = newTextBuffer("hello world")
    let cursor = BufferPosition(line: 0, column: 7)
    let result = calculateTextObjectRange(buffer, cursor, toWord, tomInner)
    check result.isOk
    let range = result.get
    check range.start.column == 6
    check range.endPos.column == 10

  test "double quoted text object":
    let buffer = newTextBuffer("say \"hi\"")
    let cursor = BufferPosition(line: 0, column: 5)
    let result = calculateTextObjectRange(buffer, cursor, toQuotedDouble, tomInner)
    check result.isOk
    let range = result.get
    check range.start.column == 5
    check range.endPos.column == 6

  test "parenthesis text object":
    let buffer = newTextBuffer("(test)")
    let cursor = BufferPosition(line: 0, column: 2)
    let result = calculateTextObjectRange(buffer, cursor, toParenthesis, tomAround)
    check result.isOk
    let range = result.get
    check range.start.column == 0
    check range.endPos.column == 5

  test "empty double quoted string inner is an empty range between quotes":
    # vim's `ci"` on "" still enters Insert mode between the quotes.
    let buffer = newTextBuffer("x \"\" y")
    let cursor = BufferPosition(line: 0, column: 3)
    let result = calculateTextObjectRange(buffer, cursor, toQuotedDouble, tomInner)
    check result.isOk
    let range = result.get
    check range.isEmpty
    check not range.isLinewise
    check (range.start.line, range.start.column) == (0, 3)
    check (range.endPos.line, range.endPos.column) == (0, 3)

  test "empty single quoted string inner is an empty range between quotes":
    let buffer = newTextBuffer("x '' y")
    let cursor = BufferPosition(line: 0, column: 3)
    let result = calculateTextObjectRange(buffer, cursor, toQuotedSingle, tomInner)
    check result.isOk
    let range = result.get
    check range.isEmpty
    check (range.start.line, range.start.column) == (0, 3)
    check (range.endPos.line, range.endPos.column) == (0, 3)

  test "empty parenthesis inner is an empty range between delimiters":
    # vim's `ci(` on () still enters Insert mode between the delimiters.
    let buffer = newTextBuffer("x () y")
    let cursor = BufferPosition(line: 0, column: 2)
    let result = calculateTextObjectRange(buffer, cursor, toParenthesis, tomInner)
    check result.isOk
    let range = result.get
    check range.isEmpty
    check not range.isLinewise
    # Position is the closing delimiter, so typing inserts between ( and ).
    check (range.start.line, range.start.column) == (0, 3)
    check (range.endPos.line, range.endPos.column) == (0, 3)

  test "empty bracket inner is an empty range between delimiters":
    let buffer = newTextBuffer("x [] y")
    let cursor = BufferPosition(line: 0, column: 2)
    let result = calculateTextObjectRange(buffer, cursor, toBracket, tomInner)
    check result.isOk
    let range = result.get
    check range.isEmpty
    check (range.start.line, range.start.column) == (0, 3)
    check (range.endPos.line, range.endPos.column) == (0, 3)

  test "empty brace inner is an empty range between delimiters":
    let buffer = newTextBuffer("x {} y")
    let cursor = BufferPosition(line: 0, column: 2)
    let result = calculateTextObjectRange(buffer, cursor, toBrace, tomInner)
    check result.isOk
    let range = result.get
    check range.isEmpty
    check (range.start.line, range.start.column) == (0, 3)
    check (range.endPos.line, range.endPos.column) == (0, 3)

  test "multi-line paren inner stops at the start of the close line":
    # `(\n  bar\n)`: the close sits at column 0, so the inner runs from the line
    # after the open one up to the close line, exclusive.
    let buffer = newTextBuffer("(\n  bar\n)")
    let cursor = BufferPosition(line: 0, column: 0)
    let result = calculateTextObjectRange(buffer, cursor, toParenthesis, tomInner)
    check result.isOk
    let range = result.get
    check not range.isEmpty
    check range.exclusive
    check (range.start.line, range.start.column) == (1, 0)
    check (range.endPos.line, range.endPos.column) == (2, 0)

  test "multi-line paren inner with empty middle lines stays a valid range":
    let buffer = newTextBuffer("(\n\n)")
    let cursor = BufferPosition(line: 0, column: 0)
    let result = calculateTextObjectRange(buffer, cursor, toParenthesis, tomInner)
    check result.isOk
    let range = result.get
    check not range.isEmpty
    check (range.start.line, range.start.column) == (1, 0)
    check (range.endPos.line, range.endPos.column) == (2, 0)

  test "multi-line paren inner with content not at column 0 is unchanged":
    let buffer = newTextBuffer("(abc\ndef)")
    let cursor = BufferPosition(line: 0, column: 0)
    let result = calculateTextObjectRange(buffer, cursor, toParenthesis, tomInner)
    check result.isOk
    let range = result.get
    check not range.isEmpty
    check (range.start.line, range.start.column) == (0, 1)
    check (range.endPos.line, range.endPos.column) == (1, 2)

  test "multi-line empty paren inner is an empty range at the close delimiter":
    # `(\n)`: only the boundary newline lies between the delimiters, so the range
    # is an empty no-op positioned at the close delimiter (ci( still inserts).
    let buffer = newTextBuffer("(\n)")
    let cursor = BufferPosition(line: 0, column: 0)
    let result = calculateTextObjectRange(buffer, cursor, toParenthesis, tomInner)
    check result.isOk
    let range = result.get
    check range.isEmpty
    check not range.isLinewise
    check (range.start.line, range.start.column) == (1, 0)
    check (range.endPos.line, range.endPos.column) == (1, 0)

  test "multi-line empty brace inner is an empty range at the close delimiter":
    let buffer = newTextBuffer("{\n}")
    let cursor = BufferPosition(line: 0, column: 0)
    let result = calculateTextObjectRange(buffer, cursor, toBrace, tomInner)
    check result.isOk
    let range = result.get
    check range.isEmpty
    check (range.start.line, range.start.column) == (1, 0)
    check (range.endPos.line, range.endPos.column) == (1, 0)

suite "Text Objects - Paragraph":
  test "inner paragraph is the non-blank run":
    let buffer = newTextBuffer("aaa\nbbb\n\nccc")
    let cursor = BufferPosition(line: 0, column: 1)
    let result = calculateTextObjectRange(buffer, cursor, toParagraph, tomInner)
    check result.isOk
    let range = result.get
    check range.isLinewise
    check (range.start.line, range.start.column) == (0, 0)
    check (range.endPos.line, range.endPos.column) == (1, 2)

  test "around paragraph includes trailing blank lines":
    let buffer = newTextBuffer("aaa\nbbb\n\nccc")
    let cursor = BufferPosition(line: 0, column: 1)
    let result = calculateTextObjectRange(buffer, cursor, toParagraph, tomAround)
    check result.isOk
    let range = result.get
    check range.isLinewise
    check (range.start.line, range.start.column) == (0, 0)
    check range.endPos.line == 2

  test "around paragraph on a blank line selects the following paragraph":
    let buffer = newTextBuffer("aaa\n\nbbb")
    let cursor = BufferPosition(line: 1, column: 0) # on the blank line
    let result = calculateTextObjectRange(buffer, cursor, toParagraph, tomAround)
    check result.isOk
    let range = result.get
    check range.isLinewise
    check (range.start.line, range.start.column) == (1, 0)
    check (range.endPos.line, range.endPos.column) == (2, 2)

  test "around paragraph on a trailing blank line selects the previous paragraph":
    let buffer = newTextBuffer("aaa\n\n")
    let cursor = BufferPosition(line: 1, column: 0) # on the trailing blank line
    let result = calculateTextObjectRange(buffer, cursor, toParagraph, tomAround)
    check result.isOk
    let range = result.get
    check range.isLinewise
    check (range.start.line, range.start.column) == (0, 0)
    check (range.endPos.line, range.endPos.column) == (1, 0)

suite "Text Objects - Sentence":
  test "inner sentence stops at the period":
    let buffer = newTextBuffer("Hello world. Foo bar! Baz.")
    let cursor = BufferPosition(line: 0, column: 2)
    let result = calculateTextObjectRange(buffer, cursor, toSentence, tomInner)
    check result.isOk
    let range = result.get
    check (range.start.line, range.start.column) == (0, 0)
    check (range.endPos.line, range.endPos.column) == (0, 11)

  test "around sentence keeps trailing space":
    let buffer = newTextBuffer("Hello world. Foo bar! Baz.")
    let cursor = BufferPosition(line: 0, column: 2)
    let result = calculateTextObjectRange(buffer, cursor, toSentence, tomAround)
    check result.isOk
    let range = result.get
    check (range.endPos.line, range.endPos.column) == (0, 12)

  test "sentence spans lines within a paragraph":
    let buffer = newTextBuffer("One two.\nThree four.")
    let cursor = BufferPosition(line: 1, column: 2)
    let result = calculateTextObjectRange(buffer, cursor, toSentence, tomInner)
    check result.isOk
    let range = result.get
    check (range.start.line, range.start.column) == (1, 0)
    check (range.endPos.line, range.endPos.column) == (1, 10)

  test "cursor column past end of line stays on the cursor's line":
    let buffer = newTextBuffer("One.\nTwo.")
    let cursor = BufferPosition(line: 0, column: 5) # past "One." (len 4)
    let result = calculateTextObjectRange(buffer, cursor, toSentence, tomInner)
    check result.isOk
    let range = result.get
    check (range.start.line, range.start.column) == (0, 0)
    check (range.endPos.line, range.endPos.column) == (0, 3)

  test "cursor column past end of last line clamps to last sentence":
    let buffer = newTextBuffer("One.\nTwo.")
    let cursor = BufferPosition(line: 1, column: 5) # past "Two." (len 4)
    let result = calculateTextObjectRange(buffer, cursor, toSentence, tomInner)
    check result.isOk
    let range = result.get
    check (range.start.line, range.start.column) == (1, 0)
    check (range.endPos.line, range.endPos.column) == (1, 3)

  test "inner sentence on inter-sentence whitespace is the whitespace run":
    # vim: `dis` with the cursor on the space deletes only the space (One.Two.)
    let buffer = newTextBuffer("One. Two.")
    let cursor = BufferPosition(line: 0, column: 4) # the space
    let result = calculateTextObjectRange(buffer, cursor, toSentence, tomInner)
    check result.isOk
    let range = result.get
    check (range.start.column, range.endPos.column) == (4, 4)

  test "inner sentence whitespace covers a multi-space run":
    let buffer = newTextBuffer("One.  Two.")
    let cursor = BufferPosition(line: 0, column: 4) # first of two spaces
    let result = calculateTextObjectRange(buffer, cursor, toSentence, tomInner)
    check result.isOk
    let range = result.get
    check (range.start.column, range.endPos.column) == (4, 5)

  test "around sentence on whitespace takes whitespace plus next sentence":
    # vim: `das` on the space deletes " Two." leaving "One."
    let buffer = newTextBuffer("One. Two.")
    let cursor = BufferPosition(line: 0, column: 4)
    let result = calculateTextObjectRange(buffer, cursor, toSentence, tomAround)
    check result.isOk
    let range = result.get
    check (range.start.column, range.endPos.column) == (4, 8)

  test "around last sentence with no trailing whitespace takes leading space":
    # vim: `das` in "Three" deletes " Three." leaving "One. Two."
    let buffer = newTextBuffer("One. Two. Three.")
    let cursor = BufferPosition(line: 0, column: 12) # inside "Three"
    let result = calculateTextObjectRange(buffer, cursor, toSentence, tomAround)
    check result.isOk
    let range = result.get
    check (range.start.column, range.endPos.column) == (9, 15)

  test "inner of the first sentence includes the line's leading indentation":
    # Verified in vim/neovim: `dis` on "   Hello world." deletes the whole line
    # including the leading indentation, so the first sentence's `is` spans from
    # column 0. (Do not "fix" this to exclude the indent -- it matches vim.)
    let buffer = newTextBuffer("   Hello world.")
    let cursor = BufferPosition(line: 0, column: 5) # inside "Hello"
    let result = calculateTextObjectRange(buffer, cursor, toSentence, tomInner)
    check result.isOk
    let range = result.get
    check (range.start.column, range.endPos.column) == (0, 14)

suite "Text Objects - Tag":
  test "inner tag is the content":
    let buffer = newTextBuffer("<a>hello</a>")
    let cursor = BufferPosition(line: 0, column: 4)
    let result = calculateTextObjectRange(buffer, cursor, toTag, tomInner)
    check result.isOk
    let range = result.get
    check (range.start.column, range.endPos.column) == (3, 7)

  test "around tag includes the tags":
    let buffer = newTextBuffer("<a>hello</a>")
    let cursor = BufferPosition(line: 0, column: 4)
    let result = calculateTextObjectRange(buffer, cursor, toTag, tomAround)
    check result.isOk
    let range = result.get
    check (range.start.column, range.endPos.column) == (0, 11)

  test "nested inner tag picks the innermost":
    let buffer = newTextBuffer("<div><p>x</p></div>")
    let cursor = BufferPosition(line: 0, column: 8)
    let result = calculateTextObjectRange(buffer, cursor, toTag, tomInner)
    check result.isOk
    let range = result.get
    check (range.start.column, range.endPos.column) == (8, 8)

  test "cursor on outer open tag selects outer pair":
    let buffer = newTextBuffer("<div><p>x</p></div>")
    let cursor = BufferPosition(line: 0, column: 2)
    let result = calculateTextObjectRange(buffer, cursor, toTag, tomInner)
    check result.isOk
    let range = result.get
    check (range.start.column, range.endPos.column) == (5, 12)

  test "multi-line inner tag is linewise (content on its own lines)":
    let buffer = newTextBuffer("<div>\n  hi\n</div>")
    let cursor = BufferPosition(line: 1, column: 2)
    let result = calculateTextObjectRange(buffer, cursor, toTag, tomInner)
    check result.isOk
    let range = result.get
    # vim's `it` is linewise here, so `dit` removes the whole content line.
    check range.isLinewise
    check (range.start.line, range.start.column) == (1, 0)
    check (range.endPos.line, range.endPos.column) == (1, 3)

  test "empty tag inner is an empty range between the tags":
    # vim's `cit` on <a></a> still works: an empty (no-op) object positioned
    # right after the open tag's '>', so a change drops into Insert mode there.
    let buffer = newTextBuffer("<a></a>")
    let cursor = BufferPosition(line: 0, column: 1)
    let result = calculateTextObjectRange(buffer, cursor, toTag, tomInner)
    check result.isOk
    let range = result.get
    check range.isEmpty
    check not range.isLinewise
    # Position is the close tag's '<' (one past the open tag's '>').
    check (range.start.line, range.start.column) == (0, 3)
    check (range.endPos.line, range.endPos.column) == (0, 3)

  test "nested empty inner tag picks the innermost empty pair":
    let buffer = newTextBuffer("<div><p></p></div>")
    let cursor = BufferPosition(line: 0, column: 6) # on the inner <p>
    let result = calculateTextObjectRange(buffer, cursor, toTag, tomInner)
    check result.isOk
    let range = result.get
    check range.isEmpty
    # Innermost <p></p>, not <div>: position is the '<' of </p> (column 8).
    check (range.start.line, range.start.column) == (0, 8)
    check (range.endPos.line, range.endPos.column) == (0, 8)

  test "multi-line empty tag inner is an empty range at the closing tag":
    # <a>\n</a>: the inner content is only a newline. vim's `cit` still works,
    # so return an empty (no-op) range positioned at the closing tag's '<'.
    let buffer = newTextBuffer("<a>\n</a>")
    let cursor = BufferPosition(line: 0, column: 1)
    let result = calculateTextObjectRange(buffer, cursor, toTag, tomInner)
    check result.isOk
    let range = result.get
    check range.isEmpty
    check not range.isLinewise
    check (range.start.line, range.start.column) == (1, 0)
    check (range.endPos.line, range.endPos.column) == (1, 0)

  test "multi-line empty tag with blank lines is an empty range":
    let buffer = newTextBuffer("<a>\n\n</a>")
    let cursor = BufferPosition(line: 1, column: 0)
    let result = calculateTextObjectRange(buffer, cursor, toTag, tomInner)
    check result.isOk
    let range = result.get
    check range.isEmpty
    check (range.start.line, range.start.column) == (2, 0)
    check (range.endPos.line, range.endPos.column) == (2, 0)

  test "stray closing tag does not break the enclosing match":
    # An orphan </br> must be ignored, not discard the still-open <div>.
    let buffer = newTextBuffer("<div>a</br>b</div>")
    let cursor = BufferPosition(line: 0, column: 11) # on 'b'
    let result = calculateTextObjectRange(buffer, cursor, toTag, tomInner)
    check result.isOk
    let range = result.get
    # inner of <div>...</div> == "a</br>b" -> cols 5..11
    check (range.start.column, range.endPos.column) == (5, 11)

  test "around tag with a stray closer selects the whole div":
    let buffer = newTextBuffer("<div>a</br>b</div>")
    let cursor = BufferPosition(line: 0, column: 11)
    let result = calculateTextObjectRange(buffer, cursor, toTag, tomAround)
    check result.isOk
    let range = result.get
    check (range.start.column, range.endPos.column) == (0, 17)

  test "less-than in content does not swallow the closing tag":
    # A bare '<' used as a comparison must be treated as a literal, not a
    # comment/directive that skips to the next '>'.
    let buffer = newTextBuffer("<p>a < b here</p>")
    let cursor = BufferPosition(line: 0, column: 5) # inside content
    let result = calculateTextObjectRange(buffer, cursor, toTag, tomInner)
    check result.isOk
    let range = result.get
    # inner of <p>...</p> == "a < b here" -> cols 3..12
    check (range.start.column, range.endPos.column) == (3, 12)

  test "less-than in mixed code/markup content":
    let buffer = newTextBuffer("if a < b: t = \"<x>hi</x>\"")
    let cursor = BufferPosition(line: 0, column: 18) # inside "hi"
    let result = calculateTextObjectRange(buffer, cursor, toTag, tomInner)
    check result.isOk
    let range = result.get
    check (range.start.column, range.endPos.column) == (18, 19)

  test "unterminated quote does not disable tags after it":
    # An unclosed quote must not abort all tag collection; the well-formed tag
    # after it stays selectable.
    let buffer = newTextBuffer("<a title=\"oops>x</a>\n<p>real</p>")
    let cursor = BufferPosition(line: 1, column: 4) # inside "real"
    let result = calculateTextObjectRange(buffer, cursor, toTag, tomInner)
    check result.isOk
    let range = result.get
    check (range.start.line, range.start.column) == (1, 3)
    check (range.endPos.line, range.endPos.column) == (1, 6)

  test "cursor at/past end-of-line still finds a tag that ends the line":
    # A column clamped to (or past) end-of-line must not fall off the closing
    # tag: it/at should still resolve the enclosing pair.
    let buffer = newTextBuffer("<p>hello</p>") # cols 0..11, '>' of </p> at 11
    let result = calculateTextObjectRange(
      buffer, BufferPosition(line: 0, column: 12), toTag, tomInner
    )
    check result.isOk
    let range = result.get
    check (range.start.column, range.endPos.column) == (3, 7)

  test "tag pair beyond the initial scan window is still found":
    # The open/close lie outside the first window centred on the cursor, so this
    # drives the doubling scan; the result must equal a full-buffer scan.
    let buffer = newTextBuffer("<div>\n" & "x\n".repeat(300) & "</div>")
    let cursor = BufferPosition(line: 150, column: 0)
    let around = calculateTextObjectRange(buffer, cursor, toTag, tomAround)
    check around.isOk
    check (around.get.start.line, around.get.start.column) == (0, 0)
    check (around.get.endPos.line, around.get.endPos.column) == (301, 5)
    let inner = calculateTextObjectRange(buffer, cursor, toTag, tomInner)
    check inner.isOk
    check inner.get.isLinewise
    check (inner.get.start.line, inner.get.start.column) == (1, 0)
    check (inner.get.endPos.line, inner.get.endPos.column) == (300, 0)

  test "innermost pair is chosen after the window grows past both pairs":
    # Cursor sits far from every tag, so the window must grow once before any
    # markup is in range; the inner <p> pair, not the outer <div>, must win.
    let buffer = newTextBuffer("<div>\n<p>\n" & "y\n".repeat(600) & "</p>\n</div>")
    let cursor = BufferPosition(line: 301, column: 0)
    let around = calculateTextObjectRange(buffer, cursor, toTag, tomAround)
    check around.isOk
    check (around.get.start.line, around.get.start.column) == (1, 0)
    check (around.get.endPos.line, around.get.endPos.column) == (602, 3)
    let inner = calculateTextObjectRange(buffer, cursor, toTag, tomInner)
    check inner.isOk
    check inner.get.isLinewise
    check (inner.get.start.line, inner.get.start.column) == (2, 0)
    check (inner.get.endPos.line, inner.get.endPos.column) == (601, 0)

  test "counted 2at reaches an outer pair far beyond the inner one":
    # The outer <outer> tags sit >128 lines from the cursor, so the count
    # re-probe must drive the window growth a second time to find them.
    let buffer = newTextBuffer(
      "<outer>\n" & "x\n".repeat(150) & "<inner>\nhi\n</inner>\n" & "y\n".repeat(150) &
        "</outer>"
    )
    let cursor = BufferPosition(line: 152, column: 0) # inside "hi"

    let one = calculateTextObjectRange(buffer, cursor, toTag, tomAround, 1)
    check one.isOk
    check (one.get.start.line, one.get.start.column) == (151, 0)
    check (one.get.endPos.line, one.get.endPos.column) == (153, 7) # '>' of </inner>

    let two = calculateTextObjectRange(buffer, cursor, toTag, tomAround, 2)
    check two.isOk
    check (two.get.start.line, two.get.start.column) == (0, 0)
    check (two.get.endPos.line, two.get.endPos.column) == (304, 7) # '>' of </outer>

    let twoInner = calculateTextObjectRange(buffer, cursor, toTag, tomInner, 2)
    check twoInner.isOk
    check twoInner.get.isLinewise
    check (twoInner.get.start.line, twoInner.get.start.column) == (1, 0)
    check (twoInner.get.endPos.line, twoInner.get.endPos.column) == (303, 0)

  test "wide-rune content maps to absolute columns on a non-zero window offset":
    # The tag sits past the initial radius, so flatToPos must add the window's
    # line offset; the inner range is in rune columns, not bytes.
    let buffer = newTextBuffer("z\n".repeat(200) & "<p>あい</p>")
    let cursor = BufferPosition(line: 200, column: 4) # on 'い'
    let inner = calculateTextObjectRange(buffer, cursor, toTag, tomInner)
    check inner.isOk
    check (inner.get.start.line, inner.get.start.column) == (200, 3)
    check (inner.get.endPos.line, inner.get.endPos.column) == (200, 4)

  test "no enclosing tag in a large buffer fails instead of hanging":
    # Worst case for the windowed scan: the window grows to the whole buffer and
    # must terminate with an error rather than loop.
    let buffer = newTextBuffer("plain text line here\n".repeat(2000))
    let cursor = BufferPosition(line: 1000, column: 3)
    let inner = calculateTextObjectRange(buffer, cursor, toTag, tomInner)
    check inner.isErr

suite "deleteRange":
  test "deleteRange single line":
    let buffer = newTextBuffer("hello world")
    let range = OperatorRange(
      start: BufferPosition(line: 0, column: 0),
      endPos: BufferPosition(line: 0, column: 4),
      isLinewise: false,
    )
    let result = deleteRange(buffer, range)
    check result.isOk
    check buffer.getLine(0) == " world"

  test "deleteRange linewise":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let range = OperatorRange(
      start: BufferPosition(line: 1, column: 0),
      endPos: BufferPosition(line: 1, column: 5),
      isLinewise: true,
    )
    let result = deleteRange(buffer, range)
    check result.isOk
    check buffer.len == 2
    check buffer.getLine(0) == "line1"
    check buffer.getLine(1) == "line3"

suite "Next/Previous Line FirstNonBlank":
  test "moveNextLineFirstNonBlank":
    let buffer = newTextBuffer("hello\n  world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 2, y: 0)
    let result = executor.moveNextLineFirstNonBlank(currentPos, 1)
    check result.y == 1
    check result.x == 2 # First non-blank on line 2

  test "movePreviousLineFirstNonBlank":
    let buffer = newTextBuffer("  hello\nworld")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 2, y: 1)
    let result = executor.movePreviousLineFirstNonBlank(currentPos, 1)
    check result.y == 0
    check result.x == 2 # First non-blank on line 1

suite "Motion columns match the buffer's character model":
  test "findChar lands on the column charLen counts":
    # 0xE3 advertises three bytes but 'a' and 'b' follow it, so it stands alone
    # as one column and 'x' is at column 4. `toRunes` folds all three into one
    # rune and would report column 2.
    let buffer = newTextBuffer("\xE3ab x")
    check buffer.getLine(0).charLen == 5
    let executor = newMotionExecutor(buffer)
    check executor.move(CursorPosition(x: 0, y: 0), Motion.FindChar, 1, "x").x == 4

  test "findCharBackward lands on the column charLen counts":
    let buffer = newTextBuffer("\xE3ab x y")
    check buffer.getLine(0).charLen == 7
    let executor = newMotionExecutor(buffer)
    check executor.move(CursorPosition(x: 6, y: 0), Motion.FindCharBackward, 1, "x").x ==
      4

  test "moveLastNonBlank lands on the column charLen counts":
    let buffer = newTextBuffer("\xE3ab z  ")
    check buffer.getLine(0).charLen == 7
    let executor = newMotionExecutor(buffer)
    check executor.moveLastNonBlank(CursorPosition(x: 0, y: 0)).x == 4

suite "ScreenColumn Motion":
  test "moves to the screen column":
    let buffer = newTextBuffer("hello")
    let executor = newMotionExecutor(buffer)
    var rl = initRowLayout(buffer, nil, false, 80, 8)
    let pos = CursorPosition(x: 4, y: 0)
    let first = executor.landMotion(
      pos,
      MotionCommand(motion: Motion.ScreenColumn, count: 1),
      24,
      0,
      1,
      EditorMode.Normal,
      rl,
      0,
      none(OperatorType),
    )
    check first.pos.column == 0
    check first.motionType == mtExclusive
    check not first.failed
    let third = executor.landMotion(
      pos,
      MotionCommand(motion: Motion.ScreenColumn, count: 3),
      24,
      0,
      1,
      EditorMode.Normal,
      rl,
      0,
      none(OperatorType),
    )
    check third.pos.column == 2

  test "a tab occupies its display cells":
    let buffer = newTextBuffer("\thello")
    let executor = newMotionExecutor(buffer)
    var rl = initRowLayout(buffer, nil, false, 80, 8)
    let pos = CursorPosition(x: 0, y: 0)
    let first = executor.landMotion(
      pos,
      MotionCommand(motion: Motion.ScreenColumn, count: 1),
      24,
      0,
      1,
      EditorMode.Normal,
      rl,
      0,
      none(OperatorType),
    )
    check first.pos.column == 0
    let insideTab = executor.landMotion(
      pos,
      MotionCommand(motion: Motion.ScreenColumn, count: 2),
      24,
      0,
      1,
      EditorMode.Normal,
      rl,
      0,
      none(OperatorType),
    )
    check insideTab.pos.column == 0
    let afterTab = executor.landMotion(
      pos,
      MotionCommand(motion: Motion.ScreenColumn, count: 9),
      24,
      0,
      1,
      EditorMode.Normal,
      rl,
      0,
      none(OperatorType),
    )
    check afterTab.pos.column == 1

  test "past the end clamps to the line end":
    let buffer = newTextBuffer("hi")
    let executor = newMotionExecutor(buffer)
    var rl = initRowLayout(buffer, nil, false, 80, 8)
    let pos = CursorPosition(x: 0, y: 0)
    let normal = executor.landMotion(
      pos,
      MotionCommand(motion: Motion.ScreenColumn, count: 10),
      24,
      0,
      1,
      EditorMode.Normal,
      rl,
      0,
      none(OperatorType),
    )
    check normal.pos.column == 1
    let visual = executor.landMotion(
      pos,
      MotionCommand(motion: Motion.ScreenColumn, count: 10),
      24,
      0,
      1,
      EditorMode.Visual,
      rl,
      0,
      none(OperatorType),
    )
    check visual.pos.column == 2

suite "Viewport Motion - H, M and L as Vim's nv_scroll":
  # Where Vim 9.2 puts the cursor in a window 17 rows high and 40 cells wide.
  proc everyThirdLong(): TextBuffer =
    ## Every third line takes three rows, the others one.
    var lines: seq[string]
    for i in 1 .. 60:
      lines.add(
        if i mod 3 == 0:
          "x".repeat(95)
        else:
          "  line " & $i
      )
    newTextBuffer(lines.join("\n"))

  proc plainLines(count: int): TextBuffer =
    newTextBuffer(newSeq[string](count).join("\n"))

  proc land(
      buffer: TextBuffer,
      motion: Motion,
      count = 1,
      top = 0,
      wrap = true,
      operator = none(OperatorType),
  ): BufferPosition =
    newMotionExecutor(buffer)
      .landMotion(
        CursorPosition(x: 0, y: top),
        MotionCommand(motion: motion, count: count),
        viewportHeight = 17,
        viewportTopLine = top,
        reservedLines = 0,
        rowLayout = initRowLayout(buffer, nil, wrap, 40, 8),
        operator = operator,
      ).pos

  test "L goes to the last line shown whole, at its first non-blank":
    let buffer = everyThirdLong()
    check buffer.land(Motion.ViewportLow) == BufferPosition(line: 10, column: 2)
    check buffer.land(Motion.ViewportLow, top = 10) ==
      BufferPosition(line: 19, column: 2)

  test "a count for L and H counts lines, not rows":
    let buffer = everyThirdLong()
    check buffer.land(Motion.ViewportLow, 3).line == 8
    check buffer.land(Motion.ViewportLow, 2, top = 10).line == 18
    check buffer.land(Motion.ViewportHigh) == BufferPosition(line: 0, column: 2)
    check buffer.land(Motion.ViewportHigh, 3).line == 2

  test "M goes half the rows of the lines shown whole down":
    let buffer = everyThirdLong()
    check buffer.land(Motion.ViewportMiddle).line == 5
    check buffer.land(Motion.ViewportMiddle, top = 10).line == 14
    check plainLines(200).land(Motion.ViewportMiddle, wrap = false).line == 8

  test "a count past the window stays in it, but not for an operator":
    let buffer = everyThirdLong()
    check buffer.land(Motion.ViewportHigh, 20).line == 10
    check buffer.land(Motion.ViewportHigh, 20, operator = some(OpDelete)).line == 19
    check plainLines(200).land(Motion.ViewportHigh, 20, wrap = false).line == 16
    check plainLines(200).land(Motion.ViewportLow, 20, wrap = false).line == 0

  test "a closed fold counts as one line":
    let buffer = plainLines(200)
    check buffer.foldState.addFold(4, 19, collapsed = true)
    check buffer.land(Motion.ViewportLow, wrap = false).line == 31
    check buffer.land(Motion.ViewportLow, 5, wrap = false).line == 27
    check buffer.land(Motion.ViewportHigh, 3, wrap = false).line == 2
    check buffer.land(Motion.ViewportHigh, 20, wrap = false).line == 31
    check buffer.land(Motion.ViewportMiddle, wrap = false).line == 23

  test "L onto a closed fold lands on its last line, at its first non-blank":
    # Vim's nv_scroll keeps the line w_botline - 1 names. The cursor manager
    # then puts the cursor on the fold's first line.
    let buffer = newTextBuffer(
      (0 ..< 200).mapIt(" ".repeat((it + 1) mod 4 * 2) & "line").join("\n")
    )
    check buffer.foldState.addFold(16, 21, collapsed = true)
    check buffer.land(Motion.ViewportLow, wrap = false) ==
      BufferPosition(line: 21, column: 4)
    check buffer.land(Motion.ViewportHigh, 17, wrap = false) ==
      BufferPosition(line: 16, column: 2)
