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

import std/[unittest, strutils]

import pkg/results

import ../src/moepkg/types
import ../src/moepkg/buffer/[core, edit]
import ../src/moepkg/motion {.all.}

suite "TillChar Motion":
  test "tillChar moves to correct position":
    # Setup: "abcxyz"
    let buffer = newTextBuffer("abcxyz")
    let executor = newMotionExecutor(buffer)

    # Start at 'a' (column 0), find 'x' (column 3)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.tillChar(currentPos, "x", 1)

    check result.y == 0
    check result.x == 2 # Should be at 'c', which is column 2

  test "findChar moves to correct position":
    # Setup: "abcxyz"
    let buffer = newTextBuffer("abcxyz")
    let executor = newMotionExecutor(buffer)

    # Start at 'a' (column 0), find 'x' (column 3)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.findChar(currentPos, "x", 1)

    check result.y == 0
    check result.x == 3 # Should be at 'x', which is column 3

suite "OperatorRange":
  test "calculateOperatorRange for TillChar":
    # Setup: "abcxyz"
    let buffer = newTextBuffer("abcxyz")

    # Simulate dtx: start at column 0, tillChar moves to column 2
    let startPos = BufferPosition(line: 0, column: 0)
    let endPos = BufferPosition(line: 0, column: 2)

    let range = calculateOperatorRange(buffer, startPos, endPos, Motion.TillChar)

    check range.start.column == 0
    check range.endPos.column == 2

  test "extractRangeText for TillChar range":
    # Setup: "abcxyz"
    let buffer = newTextBuffer("abcxyz")

    # Range from calculateOperatorRange (with inclusive semantics)
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
  test "moveWordForward basic":
    let buffer = newTextBuffer("hello world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveWordForward(currentPos, 1)
    check result.x == 6 # 'w' of "world"

  test "moveWordForward with symbols":
    let buffer = newTextBuffer("hello,world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveWordForward(currentPos, 1)
    check result.x == 5 # ',' is a separate word

  test "moveWordForward across lines":
    let buffer = newTextBuffer("hello\nworld")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 3, y: 0)
    let result = executor.moveWordForward(currentPos, 1)
    check result.y == 1
    check result.x == 0

  test "moveWordBackward basic":
    let buffer = newTextBuffer("hello world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 8, y: 0)
    let result = executor.moveWordBackward(currentPos, 1)
    check result.x == 6 # Start of "world"

  test "moveWordBackward to previous word":
    let buffer = newTextBuffer("hello world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 6, y: 0)
    let result = executor.moveWordBackward(currentPos, 1)
    check result.x == 0 # Start of "hello"

  test "moveWordEnd basic":
    let buffer = newTextBuffer("hello world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveWordEnd(currentPos, 1)
    check result.x == 4 # End of "hello"

  test "moveWordEnd to next word end":
    let buffer = newTextBuffer("hello world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 4, y: 0)
    let result = executor.moveWordEnd(currentPos, 1)
    check result.x == 10 # End of "world"

  test "moveWordForward with Unicode":
    let buffer = newTextBuffer("hello 日本語 world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveWordForward(currentPos, 1)
    check result.x == 6 # Start of '日本語'

  test "moveWordForward past Unicode word":
    let buffer = newTextBuffer("hello 日本語 world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 6, y: 0)
    let result = executor.moveWordForward(currentPos, 1)
    check result.x == 10 # Start of 'world'

  test "moveWordBackward with Unicode":
    let buffer = newTextBuffer("hello 日本語 world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 10, y: 0)
    let result = executor.moveWordBackward(currentPos, 1)
    check result.x == 6 # Start of '日本語'

  test "moveWordEnd with Unicode":
    let buffer = newTextBuffer("hello 日本語 world")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 6, y: 0)
    let result = executor.moveWordEnd(currentPos, 1)
    check result.x == 8 # End of '日本語'

  test "moveWordEnd crosses a single empty line":
    let buffer = newTextBuffer("foo\n\nbar")
    let executor = newMotionExecutor(buffer)
    let result = executor.moveWordEnd(CursorPosition(x: 2, y: 0), 1)
    check result.y == 2
    check result.x == 2 # End of "bar"

  test "moveWordEnd crosses multiple empty lines":
    let buffer = newTextBuffer("foo\n\n\n\nbar")
    let executor = newMotionExecutor(buffer)
    let result = executor.moveWordEnd(CursorPosition(x: 2, y: 0), 1)
    check result.y == 4
    check result.x == 2 # End of "bar"

  test "moveWordBackward crosses a single empty line":
    let buffer = newTextBuffer("foo\n\nbar")
    let executor = newMotionExecutor(buffer)
    let result = executor.moveWordBackward(CursorPosition(x: 0, y: 2), 1)
    check result.y == 0
    check result.x == 0 # Start of "foo"

  test "moveWordBackward crosses multiple empty lines":
    let buffer = newTextBuffer("foo\n\n\n\nbar")
    let executor = newMotionExecutor(buffer)
    let result = executor.moveWordBackward(CursorPosition(x: 0, y: 4), 1)
    check result.y == 0
    check result.x == 0 # Start of "foo"

  test "moveWordBackward crosses whitespace-only line":
    let buffer = newTextBuffer("foo\n  \nbar")
    let executor = newMotionExecutor(buffer)
    let result = executor.moveWordBackward(CursorPosition(x: 0, y: 2), 1)
    check result.y == 0
    check result.x == 0 # Start of "foo"

suite "Find/Till Char Backward":
  test "findCharBackward finds previous occurrence":
    let buffer = newTextBuffer("abcxabc")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 6, y: 0)
    let result = executor.findCharBackward(currentPos, "a", 1)
    check result.x == 4

  test "findCharBackward with count":
    let buffer = newTextBuffer("abcxabc")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 6, y: 0)
    let result = executor.findCharBackward(currentPos, "a", 2)
    check result.x == 0

  test "tillCharBackward stops after target":
    let buffer = newTextBuffer("abcxyz")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 5, y: 0)
    let result = executor.tillCharBackward(currentPos, "c", 1)
    check result.x == 3 # One after 'c'

suite "Find/Till Char - Unicode and long lines":
  test "findChar uses character positions past multibyte runes":
    # 日(0) 本(1) x(2) y(3) 語(4) x(5)
    let buffer = newTextBuffer("日本xy語x")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    check executor.findChar(currentPos, "x", 1).x == 2
    check executor.findChar(currentPos, "x", 2).x == 5

  test "findCharBackward uses character positions past multibyte runes":
    # x(0) 本(1) x(2) 語(3)
    let buffer = newTextBuffer("x本x語")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 3, y: 0)
    check executor.findCharBackward(currentPos, "x", 1).x == 2
    check executor.findCharBackward(currentPos, "x", 2).x == 0

  test "findChar leaves cursor unchanged when target is absent":
    let buffer = newTextBuffer("abcdef")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    check executor.findChar(currentPos, "z", 1).x == 0

  test "findChar finds target at end of a long line":
    let buffer = newTextBuffer("a".repeat(5000) & "x")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    check executor.findChar(currentPos, "x", 1).x == 5000

  test "findChar/findCharBackward find a multibyte target rune":
    # 語(0) a(1) 語(2) b(3) 語(4)
    let buffer = newTextBuffer("語a語b語")
    let executor = newMotionExecutor(buffer)
    check executor.findChar(CursorPosition(x: 0, y: 0), "語", 1).x == 2
    check executor.findChar(CursorPosition(x: 0, y: 0), "語", 2).x == 4
    check executor.findCharBackward(CursorPosition(x: 4, y: 0), "語", 1).x == 2
    check executor.findCharBackward(CursorPosition(x: 4, y: 0), "語", 2).x == 0

  test "tillChar/tillCharBackward stop adjacent to a target past multibyte runes":
    # a(0) 語(1) b(2) y(3)
    let buffer = newTextBuffer("a語by")
    let executor = newMotionExecutor(buffer)
    check executor.tillChar(CursorPosition(x: 0, y: 0), "y", 1).x == 2
    check executor.tillCharBackward(CursorPosition(x: 3, y: 0), "a", 1).x == 1

  test "findChar leaves cursor unchanged for empty or multi-rune targets":
    let buffer = newTextBuffer("abc")
    let executor = newMotionExecutor(buffer)
    let pos = CursorPosition(x: 0, y: 0)
    check executor.findChar(pos, "", 1).x == 0
    check executor.findChar(pos, "bc", 1).x == 0
    check executor.findCharBackward(CursorPosition(x: 2, y: 0), "", 1).x == 2
    check executor.findCharBackward(CursorPosition(x: 2, y: 0), "ab", 1).x == 2

suite "Paragraph Motion":
  test "moveParagraphForward to blank line":
    let buffer = newTextBuffer("line1\nline2\n\nline4")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveParagraphForward(currentPos, 1)
    check result.y == 2 # Blank line

  test "moveParagraphBackward to blank line":
    let buffer = newTextBuffer("line1\n\nline3\nline4")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 3)
    let result = executor.moveParagraphBackward(currentPos, 1)
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

suite "Text Objects - Parenthesis":
  test "findMatchingParen cursor on close paren":
    let buffer = newTextBuffer("(x)")
    let cursor = BufferPosition(line: 0, column: 2)
    let result = findMatchingParen(buffer, cursor, '(', ')', inner = true)
    check result.isOk
    let range = result.get
    check range.start.column == 1
    check range.endPos.column == 1

  test "findMatchingParen cursor on close paren around":
    let buffer = newTextBuffer("(x)")
    let cursor = BufferPosition(line: 0, column: 2)
    let result = findMatchingParen(buffer, cursor, '(', ')', inner = false)
    check result.isOk
    let range = result.get
    check range.start.column == 0
    check range.endPos.column == 2

  test "findMatchingParen cursor on close paren empty":
    let buffer = newTextBuffer("()")
    let cursor = BufferPosition(line: 0, column: 1)
    let result = findMatchingParen(buffer, cursor, '(', ')', inner = true)
    check result.isOk

  test "findMatchingParen inner":
    let buffer = newTextBuffer("func(arg)")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findMatchingParen(buffer, cursor, '(', ')', inner = true)
    check result.isOk
    let range = result.get
    check range.start.column == 5
    check range.endPos.column == 7

  test "findMatchingParen around":
    let buffer = newTextBuffer("func(arg)")
    let cursor = BufferPosition(line: 0, column: 6)
    let result = findMatchingParen(buffer, cursor, '(', ')', inner = false)
    check result.isOk
    let range = result.get
    check range.start.column == 4
    check range.endPos.column == 8

  test "findMatchingParen multi-line":
    # Close delimiter on its own line: the inner ends at the previous line's
    # end-of-content column (just past "  arg") so deleting through it joins the
    # lines and collapses the block to `()` instead of yielding a negative end.
    let buffer = newTextBuffer("func(\n  arg\n)")
    let cursor = BufferPosition(line: 1, column: 2)
    let result = findMatchingParen(buffer, cursor, '(', ')', inner = true)
    check result.isOk
    let range = result.get
    check not range.isEmpty
    check (range.start.line, range.start.column) == (0, 5)
    check (range.endPos.line, range.endPos.column) == (1, 5)

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

  test "multi-line paren inner spans from after open to end of the content line":
    # `(\n  bar\n)`: the close sits at column 0, so the inner ends at the content
    # line's end-of-content column (deleting through it joins the lines). A naive
    # endCol-1 would be -1 and the delete would fail.
    let buffer = newTextBuffer("(\n  bar\n)")
    let cursor = BufferPosition(line: 0, column: 0)
    let result = calculateTextObjectRange(buffer, cursor, toParenthesis, tomInner)
    check result.isOk
    let range = result.get
    check not range.isEmpty
    check not range.isLinewise
    check (range.start.line, range.start.column) == (0, 1)
    # column 5 == charLen("  bar"), i.e. just past the content (the newline).
    check (range.endPos.line, range.endPos.column) == (1, 5)

  test "multi-line paren inner with empty middle lines stays a valid range":
    let buffer = newTextBuffer("(\n\n)")
    let cursor = BufferPosition(line: 0, column: 0)
    let result = calculateTextObjectRange(buffer, cursor, toParenthesis, tomInner)
    check result.isOk
    let range = result.get
    check not range.isEmpty
    check (range.start.line, range.start.column) == (0, 1)
    check (range.endPos.line, range.endPos.column) == (1, 0)

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

suite "Page Motion":
  test "movePageDown":
    let buffer = newTextBuffer("l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.movePageDown(currentPos, 1, 5)
    check result.y == 4 # Moved down by viewport height - 1

  test "movePageUp":
    let buffer = newTextBuffer("l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 8)
    let result = executor.movePageUp(currentPos, 1, 5)
    check result.y == 4 # Moved up by viewport height - 1

  test "moveHalfPageDown":
    let buffer = newTextBuffer("l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.moveHalfPageDown(currentPos, 1, 10)
    check result.y == 4 # Moved down by half of (viewport height - 1)

  test "moveHalfPageUp":
    let buffer = newTextBuffer("l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10")
    let executor = newMotionExecutor(buffer)
    let currentPos = CursorPosition(x: 0, y: 8)
    let result = executor.moveHalfPageUp(currentPos, 1, 10)
    check result.y == 4

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

suite "calculateOperatorRange - linewise motions":
  test "Motion.Down produces linewise range with column 0 start":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let startPos = BufferPosition(line: 0, column: 3)
    let endPos = BufferPosition(line: 1, column: 2)
    let range = calculateOperatorRange(buffer, startPos, endPos, Motion.Down)

    check range.isLinewise == true
    check range.start.line == 0
    check range.start.column == 0
    check range.endPos.line == 1
    # endPos.column extends to full line length
    check range.endPos.column == "line2".len

  test "Motion.Up swaps start/end and produces linewise range":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let startPos = BufferPosition(line: 2, column: 4)
    let endPos = BufferPosition(line: 0, column: 1)
    let range = calculateOperatorRange(buffer, startPos, endPos, Motion.Up)

    check range.isLinewise == true
    check range.start.line == 0
    check range.start.column == 0
    check range.endPos.line == 2

  test "Motion.FirstLine produces linewise range":
    let buffer = newTextBuffer("a\nb\nc")
    let startPos = BufferPosition(line: 2, column: 0)
    let endPos = BufferPosition(line: 0, column: 0)
    let range = calculateOperatorRange(buffer, startPos, endPos, Motion.FirstLine)

    check range.isLinewise == true
    check range.start.line == 0
    check range.endPos.line == 2

  test "Motion.LastLine produces linewise range":
    let buffer = newTextBuffer("a\nb\nc")
    let startPos = BufferPosition(line: 0, column: 0)
    let endPos = BufferPosition(line: 2, column: 0)
    let range = calculateOperatorRange(buffer, startPos, endPos, Motion.LastLine)

    check range.isLinewise == true
    check range.start.line == 0
    check range.endPos.line == 2

  test "Motion.ParagraphForward produces linewise range":
    let buffer = newTextBuffer("para1\n\npara2")
    let startPos = BufferPosition(line: 0, column: 2)
    let endPos = BufferPosition(line: 1, column: 0)
    let range =
      calculateOperatorRange(buffer, startPos, endPos, Motion.ParagraphForward)

    check range.isLinewise == true
    check range.start.column == 0

suite "calculateOperatorRange - exclusive motions":
  test "Motion.Home reduces endPos column by 1 (exclusive)":
    let buffer = newTextBuffer("abcdef")
    let startPos = BufferPosition(line: 0, column: 0)
    let endPos = BufferPosition(line: 0, column: 4)
    let range = calculateOperatorRange(buffer, startPos, endPos, Motion.Home)

    check range.isLinewise == false
    # Exclusive: endPos shifted back by 1
    check range.endPos.column == 3

  test "Motion.FirstNonBlank is exclusive":
    let buffer = newTextBuffer("  abcdef")
    let startPos = BufferPosition(line: 0, column: 0)
    let endPos = BufferPosition(line: 0, column: 5)
    let range = calculateOperatorRange(buffer, startPos, endPos, Motion.FirstNonBlank)

    check range.isLinewise == false
    check range.endPos.column == 4

  test "Motion.Right (l) is exclusive":
    let buffer = newTextBuffer("abcdef")
    let startPos = BufferPosition(line: 0, column: 1)
    let endPos = BufferPosition(line: 0, column: 3)
    let range = calculateOperatorRange(buffer, startPos, endPos, Motion.Right)

    check range.endPos.column == 2

  test "Motion.WordForward stays on starting line when crossing lines":
    # `dw` should not delete the newline; it must clamp to end of start line
    let buffer = newTextBuffer("hello\nworld")
    let startPos = BufferPosition(line: 0, column: 0)
    let endPos = BufferPosition(line: 1, column: 0)
    let range = calculateOperatorRange(buffer, startPos, endPos, Motion.WordForward)

    check range.start.line == 0
    check range.endPos.line == 0
    # Clamped to end of "hello" (last char index)
    check range.endPos.column == "hello".len - 1

suite "calculateOperatorRange - inclusive motions":
  test "Motion.WordEnd does NOT shift endPos (inclusive)":
    let buffer = newTextBuffer("hello world")
    let startPos = BufferPosition(line: 0, column: 0)
    let endPos = BufferPosition(line: 0, column: 4)
    let range = calculateOperatorRange(buffer, startPos, endPos, Motion.WordEnd)

    check range.isLinewise == false
    # Inclusive: endPos preserved
    check range.endPos.column == 4

  test "Motion.TillChar is inclusive (range covers up to target)":
    let buffer = newTextBuffer("abcxyz")
    let startPos = BufferPosition(line: 0, column: 0)
    let endPos = BufferPosition(line: 0, column: 2)
    let range = calculateOperatorRange(buffer, startPos, endPos, Motion.TillChar)

    check range.endPos.column == 2

  test "Motion.FindChar is inclusive":
    let buffer = newTextBuffer("abcxyz")
    let startPos = BufferPosition(line: 0, column: 0)
    let endPos = BufferPosition(line: 0, column: 3)
    let range = calculateOperatorRange(buffer, startPos, endPos, Motion.FindChar)

    check range.endPos.column == 3

suite "Operator motion classifier consistency (Vim parity)":
  test "isLinewiseMotion matches LinewiseMotions set":
    for m in LinewiseMotions:
      check isLinewiseMotion(m)

  test "isExclusiveMotion matches ExclusiveMotions set":
    for m in ExclusiveMotions:
      check isExclusiveMotion(m)

  test "WordEnd is NOT exclusive (Vim parity)":
    check not isExclusiveMotion(Motion.WordEnd)
    check not isExclusiveMotion(Motion.WordEndBackward)

  test "TillChar/FindChar are NOT exclusive (inclusive)":
    check not isExclusiveMotion(Motion.TillChar)
    check not isExclusiveMotion(Motion.FindChar)
    check not isExclusiveMotion(Motion.TillCharBackward)
    check not isExclusiveMotion(Motion.FindCharBackward)

  test "Home/FirstNonBlank are exclusive (Vim parity)":
    check isExclusiveMotion(Motion.Home)
    check isExclusiveMotion(Motion.FirstNonBlank)

  test "Up/Down/FirstLine/LastLine are linewise":
    check isLinewiseMotion(Motion.Up)
    check isLinewiseMotion(Motion.Down)
    check isLinewiseMotion(Motion.FirstLine)
    check isLinewiseMotion(Motion.LastLine)

  test "WordForward is exclusive but NOT linewise":
    check isExclusiveMotion(Motion.WordForward)
    check not isLinewiseMotion(Motion.WordForward)
