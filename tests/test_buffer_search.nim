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

import std/[unittest, options]

import ../src/moepkg/buffer {.all.}

suite "Buffer Search - Basic findNext":
  test "findNext finds first occurrence":
    let buf = newTextBuffer("hello world")
    let result = buf.findNext("world", BufferPosition(line: 0, column: 0))
    check result.isSome
    check result.get.line == 0
    check result.get.column == 6

  test "findNext finds occurrence after cursor":
    let buf = newTextBuffer("foo bar foo baz")
    # First search from column 0 - finds first "foo" at column 0
    let result = buf.findNext("foo", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 0

    # Search for next occurrence from first "foo" - should find second "foo"
    let result2 = buf.findNext("foo", result.get)
    check result2.isSome
    check result2.get.column == 8

  test "findNext returns none for non-existent pattern":
    let buf = newTextBuffer("hello world")
    let result = buf.findNext("xyz", BufferPosition(line: 0, column: 0))
    check result.isNone

  test "findNext with empty search text":
    let buf = newTextBuffer("hello world")
    let result = buf.findNext("", BufferPosition(line: 0, column: 0))
    check result.isNone

  test "findNext with empty buffer":
    let buf = newTextBuffer("")
    let result = buf.findNext("test", BufferPosition(line: 0, column: 0))
    check result.isNone

suite "Buffer Search - findNext wrap-around":
  test "findNext wraps around to beginning":
    let buf = newTextBuffer("hello world hello")
    # Start after first "hello"
    let result = buf.findNext("hello", BufferPosition(line: 0, column: 10))
    check result.isSome
    check result.get.column == 12

    # Now wrap around - should find first "hello"
    let result2 = buf.findNext("hello", BufferPosition(line: 0, column: 12))
    check result2.isSome
    check result2.get.column == 0

  test "findNext wraps around multiline":
    let buf = newTextBuffer("first line\nsecond line\nfirst again")
    # Start from second line
    let result = buf.findNext("first", BufferPosition(line: 1, column: 0))
    check result.isSome
    check result.get.line == 2
    check result.get.column == 0

    # Wrap around to first line
    let result2 = buf.findNext("first", BufferPosition(line: 2, column: 0))
    check result2.isSome
    check result2.get.line == 0
    check result2.get.column == 0

suite "Buffer Search - findNext boundary conditions":
  test "findNext with column at line start (column = 0)":
    let buf = newTextBuffer("test test test")
    # From column -1 (before line start), should find first "test" at 0
    let result = buf.findNext("test", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 0

    # From column 0, should find next occurrence at column 5
    let result2 = buf.findNext("test", BufferPosition(line: 0, column: 0))
    check result2.isSome
    check result2.get.column == 5

    # From that position, should find third occurrence at column 10
    let result3 = buf.findNext("test", result2.get)
    check result3.isSome
    check result3.get.column == 10

  test "findNext with column at line end":
    let buf = newTextBuffer("hello world")
    let result = buf.findNext("world", BufferPosition(line: 0, column: 10))
    check result.isSome
    check result.get.column == 6 # Should wrap around and find from beginning

  test "findNext with column beyond line length":
    let buf = newTextBuffer("hello")
    # Column 100 is way beyond line length
    let result = buf.findNext("hello", BufferPosition(line: 0, column: 100))
    check result.isSome
    check result.get.column == 0 # Should wrap around

  test "findNext with negative line number":
    let buf = newTextBuffer("hello world")
    let result = buf.findNext("hello", BufferPosition(line: -1, column: 0))
    check result.isNone # Should return none for invalid position

  test "findNext with line beyond buffer":
    let buf = newTextBuffer("hello world")
    let result = buf.findNext("hello", BufferPosition(line: 100, column: 0))
    check result.isNone # Should return none for invalid position

suite "Buffer Search - Basic findPrev":
  test "findPrev finds previous occurrence":
    let buf = newTextBuffer("foo bar foo baz")
    # Start at second "foo"
    let result = buf.findPrev("foo", BufferPosition(line: 0, column: 8))
    check result.isSome
    check result.get.column == 0

  test "findPrev returns none for non-existent pattern":
    let buf = newTextBuffer("hello world")
    let result = buf.findPrev("xyz", BufferPosition(line: 0, column: 5))
    check result.isNone

  test "findPrev with empty search text":
    let buf = newTextBuffer("hello world")
    let result = buf.findPrev("", BufferPosition(line: 0, column: 5))
    check result.isNone

suite "Buffer Search - findPrev wrap-around":
  test "findPrev wraps around to end":
    let buf = newTextBuffer("hello world hello")
    # Start at first "hello", search backwards
    let result = buf.findPrev("hello", BufferPosition(line: 0, column: 0))
    check result.isSome
    check result.get.column == 12 # Should wrap to last "hello"

  test "findPrev wraps around multiline":
    let buf = newTextBuffer("first line\nsecond line\nfirst again")
    # Start from first line, should wrap to third line
    let result = buf.findPrev("first", BufferPosition(line: 0, column: 0))
    check result.isSome
    check result.get.line == 2
    check result.get.column == 0

suite "Buffer Search - findPrev boundary conditions":
  test "findPrev with column at line start (column = 0)":
    let buf = newTextBuffer("test test test")
    # At first occurrence, should wrap to last
    let result = buf.findPrev("test", BufferPosition(line: 0, column: 0))
    check result.isSome
    check result.get.column == 10 # Last "test"

  test "findPrev with negative line number":
    let buf = newTextBuffer("hello world")
    let result = buf.findPrev("hello", BufferPosition(line: -1, column: 0))
    check result.isNone # Should return none for invalid position

  test "findPrev with line beyond buffer":
    let buf = newTextBuffer("hello world")
    let result = buf.findPrev("hello", BufferPosition(line: 100, column: 0))
    check result.isNone # Should return none for invalid position

suite "Buffer Search - Case sensitivity":
  test "findNext case-sensitive by default":
    let buf = newTextBuffer("Hello HELLO hello")
    let result =
      buf.findNext("hello", BufferPosition(line: 0, column: 0), ignorecase = false)
    check result.isSome
    check result.get.column == 12 # Only lowercase "hello"

  test "findNext case-insensitive":
    let buf = newTextBuffer("Hello HELLO hello")
    # Start from column -1 to include first character
    let result =
      buf.findNext("hello", BufferPosition(line: 0, column: -1), ignorecase = true)
    check result.isSome
    check result.get.column == 0 # First match regardless of case

    # From first match, find second
    let result2 = buf.findNext("hello", result.get, ignorecase = true)
    check result2.isSome
    check result2.get.column == 6 # "HELLO"

  test "findPrev case-insensitive":
    let buf = newTextBuffer("Hello HELLO hello")
    let result =
      buf.findPrev("hello", BufferPosition(line: 0, column: 12), ignorecase = true)
    check result.isSome
    check result.get.column == 6 # "HELLO"

suite "Buffer Search - Unicode support":
  test "findNext with Unicode characters":
    let buf = newTextBuffer("こんにちは 世界 こんにちは")
    let result = buf.findNext("世界", BufferPosition(line: 0, column: 0))
    check result.isSome
    check result.get.column == 6 # After "こんにちは "

  test "findNext Unicode wrap-around":
    let buf = newTextBuffer("日本語 English 日本語")
    let result = buf.findNext("日本語", BufferPosition(line: 0, column: 5))
    check result.isSome
    check result.get.column == 12

    # Wrap around
    let result2 = buf.findNext("日本語", BufferPosition(line: 0, column: 12))
    check result2.isSome
    check result2.get.column == 0

suite "Buffer Search - isPositionInSearchMatch":
  test "isPositionInSearchMatch at match start":
    let buf = newTextBuffer("hello world hello")
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 0), "hello")
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 12), "hello")

  test "isPositionInSearchMatch within match":
    let buf = newTextBuffer("hello world")
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 1), "hello")
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 2), "hello")
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 4), "hello")

  test "isPositionInSearchMatch outside match":
    let buf = newTextBuffer("hello world")
    check not buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 5), "hello")
    check not buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 6), "hello")

  test "isPositionInSearchMatch with invalid position":
    let buf = newTextBuffer("hello world")
    check not buf.isPositionInSearchMatch(BufferPosition(line: -1, column: 0), "hello")
    check not buf.isPositionInSearchMatch(BufferPosition(line: 10, column: 0), "hello")
    check not buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 100), "hello")

  test "isPositionInSearchMatch with empty search pattern":
    let buf = newTextBuffer("hello world hello again")
    # Empty pattern should not match any position
    check not buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 0), "")
    check not buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 6), "")

  test "isPositionInSearchMatch with multiple matches":
    let buf = newTextBuffer("hello world hello again")
    # First "hello" at column 0
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 0), "hello")
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 4), "hello")
    # "world" at column 6
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 6), "world")
    check not buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 5), "world")
    # Second "hello" at column 12
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 12), "hello")
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 16), "hello")

  test "isPositionInSearchMatch with Unicode pattern":
    let buf = newTextBuffer("日本語 世界 日本語")
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 0), "日本語")
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 2), "日本語")
    check not buf.isPositionInSearchMatch(
      BufferPosition(line: 0, column: 3), "日本語"
    )
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 4), "世界")

suite "Buffer Search - Edge cases":
  test "Single character buffer":
    let buf = newTextBuffer("a")
    # Start from before the line to find the "a" at column 0
    let result = buf.findNext("a", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 0

    # From column 0, there's no next occurrence (wraps but doesn't include current position)
    let result2 = buf.findNext("a", BufferPosition(line: 0, column: 0))
    check result2.isNone # No next occurrence in single character buffer

  test "Search pattern longer than line":
    let buf = newTextBuffer("hi")
    let result = buf.findNext("hello", BufferPosition(line: 0, column: 0))
    check result.isNone

  test "Multiple empty lines":
    let buf = newTextBuffer("\n\nhello\n\n")
    let result = buf.findNext("hello", BufferPosition(line: 0, column: 0))
    check result.isSome
    check result.get.line == 2
    check result.get.column == 0

suite "Buffer Search - Error handling":
  test "Very large column number doesn't crash":
    let buf = newTextBuffer("hello world")
    let result = buf.findNext("hello", BufferPosition(line: 0, column: 999999))
    # Should wrap around and find from beginning
    check result.isSome
    check result.get.column == 0

  test "Very large negative column number doesn't crash":
    let buf = newTextBuffer("hello world")
    let result = buf.findNext("hello", BufferPosition(line: 0, column: -999999))
    # Negative column should be clamped to 0 behavior
    check result.isSome
    check result.get.column == 0

  test "findNext handles corrupted position gracefully":
    let buf = newTextBuffer("test\nline\n")
    # Line exists but column is way beyond line length
    let result = buf.findNext("line", BufferPosition(line: 1, column: 1000))
    # Should wrap and find from beginning
    check result.isSome

  test "findPrev handles corrupted position gracefully":
    let buf = newTextBuffer("test\nline\n")
    # Line exists but column is way beyond line length
    let result = buf.findPrev("test", BufferPosition(line: 1, column: 1000))
    check result.isSome
    check result.get.line == 0

  test "isPositionInSearchMatch with empty line":
    let buf = newTextBuffer("hello\n\nworld")
    # Check position in empty line
    check not buf.isPositionInSearchMatch(BufferPosition(line: 1, column: 0), "test")

  test "isPositionInSearchMatch with very long search pattern":
    let buf = newTextBuffer("hi")
    # Search pattern longer than line
    check not buf.isPositionInSearchMatch(
      BufferPosition(line: 0, column: 0), "very long pattern that won't match"
    )

  test "Search in buffer with only newlines":
    let buf = newTextBuffer("\n\n\n")
    let result = buf.findNext("test", BufferPosition(line: 0, column: 0))
    check result.isNone

  test "Search with Unicode boundary issues":
    let buf = newTextBuffer("日本語テスト")
    # Search at various positions to test Unicode handling
    let result1 = buf.findNext("語", BufferPosition(line: 0, column: 0))
    check result1.isSome
    check result1.get.column == 2 # Third character

    # Make sure positions don't cause crashes even if unusual
    let result2 = buf.findNext("日", BufferPosition(line: 0, column: 100))
    check result2.isSome # Should wrap around

  test "Rapid consecutive searches don't accumulate errors":
    let buf = newTextBuffer("foo bar baz foo bar baz")
    var pos = BufferPosition(line: 0, column: -1)
    var firstMatch: BufferPosition
    var count = 0

    # Find all unique occurrences (before wrapping back to first)
    for i in 0 ..< 10:
      let result = buf.findNext("foo", pos)
      if result.isSome:
        let newPos = result.get
        if count == 0:
          firstMatch = newPos
        elif newPos.line == firstMatch.line and newPos.column == firstMatch.column:
          # We've wrapped around to the first match
          break
        pos = newPos
        count += 1
      else:
        break

    check count == 2 # Should find exactly 2 occurrences of "foo"

suite "Buffer Search - findSearchMatchRanges":
  test "findSearchMatchRanges basic":
    let buf = newTextBuffer("hello world hello")
    let ranges = buf.findSearchMatchRanges(0, "hello")
    check ranges.len == 2
    check ranges[0].startCol == 0
    check ranges[0].endCol == 5
    check ranges[1].startCol == 12
    check ranges[1].endCol == 17

  test "findSearchMatchRanges single match":
    let buf = newTextBuffer("hello world")
    let ranges = buf.findSearchMatchRanges(0, "world")
    check ranges.len == 1
    check ranges[0].startCol == 6
    check ranges[0].endCol == 11

  test "findSearchMatchRanges no match":
    let buf = newTextBuffer("hello world")
    let ranges = buf.findSearchMatchRanges(0, "xyz")
    check ranges.len == 0

  test "findSearchMatchRanges empty search":
    let buf = newTextBuffer("hello world")
    let ranges = buf.findSearchMatchRanges(0, "")
    check ranges.len == 0

  test "findSearchMatchRanges invalid line":
    let buf = newTextBuffer("hello")
    check buf.findSearchMatchRanges(-1, "hello").len == 0
    check buf.findSearchMatchRanges(5, "hello").len == 0

  test "findSearchMatchRanges empty line":
    let buf = newTextBuffer("hello\n\nworld")
    let ranges = buf.findSearchMatchRanges(1, "test")
    check ranges.len == 0

  test "findSearchMatchRanges Unicode":
    let buf = newTextBuffer("日本語 世界 日本語")
    let ranges = buf.findSearchMatchRanges(0, "日本語")
    check ranges.len == 2
    check ranges[0].startCol == 0
    check ranges[0].endCol == 3
    # "日本語 世界 日本語" = 3 + 1(space) + 2 + 1(space) + 3 = positions 0-8
    check ranges[1].startCol == 7
    check ranges[1].endCol == 10

  test "findSearchMatchRanges case insensitive":
    let buf = newTextBuffer("Hello HELLO hello")
    let ranges = buf.findSearchMatchRanges(0, "hello", ignorecase = true)
    check ranges.len == 3

suite "Buffer Search - findWordMatchRanges":
  test "findWordMatchRanges basic":
    let buf = newTextBuffer("Hello World Hello")
    let ranges = buf.findWordMatchRanges(0, "Hello")
    check ranges.len == 2
    check ranges[0].startCol == 0
    check ranges[0].endCol == 5
    check ranges[1].startCol == 12
    check ranges[1].endCol == 17

  test "findWordMatchRanges with excludeCol":
    let buf = newTextBuffer("Hello World Hello")
    # Exclude the word at column 0
    let ranges = buf.findWordMatchRanges(0, "Hello", excludeCol = 2)
    check ranges.len == 1
    check ranges[0].startCol == 12
    check ranges[0].endCol == 17

  test "findWordMatchRanges no match":
    let buf = newTextBuffer("Hello World")
    let ranges = buf.findWordMatchRanges(0, "xyz")
    check ranges.len == 0

  test "findWordMatchRanges empty word":
    let buf = newTextBuffer("Hello")
    let ranges = buf.findWordMatchRanges(0, "")
    check ranges.len == 0

  test "findWordMatchRanges invalid line":
    let buf = newTextBuffer("Hello")
    check buf.findWordMatchRanges(-1, "Hello").len == 0
    check buf.findWordMatchRanges(5, "Hello").len == 0

  test "findWordMatchRanges empty line":
    let buf = newTextBuffer("")
    let ranges = buf.findWordMatchRanges(0, "Hello")
    check ranges.len == 0

  test "findWordMatchRanges punctuation separator":
    let buf = newTextBuffer("foo.bar(baz)")
    let ranges = buf.findWordMatchRanges(0, "foo")
    check ranges.len == 1
    check ranges[0].startCol == 0
    check ranges[0].endCol == 3

  test "findWordMatchRanges underscore in word":
    let buf = newTextBuffer("foo_bar baz foo_bar")
    let ranges = buf.findWordMatchRanges(0, "foo_bar")
    check ranges.len == 2

  test "findWordMatchRanges partial match rejected":
    let buf = newTextBuffer("foo_bar baz")
    let ranges = buf.findWordMatchRanges(0, "foo")
    check ranges.len == 0

  test "findWordMatchRanges case sensitive":
    let buf = newTextBuffer("Hello hello")
    let rangesUpper = buf.findWordMatchRanges(0, "Hello")
    check rangesUpper.len == 1
    check rangesUpper[0].startCol == 0
    let rangesLower = buf.findWordMatchRanges(0, "hello")
    check rangesLower.len == 1
    check rangesLower[0].startCol == 6

  test "findWordMatchRanges multiline":
    let buf = newTextBuffer("Hello\nWorld\nHello")
    check buf.findWordMatchRanges(0, "Hello").len == 1
    check buf.findWordMatchRanges(1, "World").len == 1
    check buf.findWordMatchRanges(2, "Hello").len == 1
    check buf.findWordMatchRanges(1, "Hello").len == 0

  test "findWordMatchRanges excludeCol at second word":
    let buf = newTextBuffer("abc def abc")
    # Exclude the word at column 9 (second "abc")
    let ranges = buf.findWordMatchRanges(0, "abc", excludeCol = 9)
    check ranges.len == 1
    check ranges[0].startCol == 0

  test "findWordMatchRanges single char words":
    let buf = newTextBuffer("a b a")
    let ranges = buf.findWordMatchRanges(0, "a")
    check ranges.len == 2
    check ranges[0].startCol == 0
    check ranges[0].endCol == 1
    check ranges[1].startCol == 4
    check ranges[1].endCol == 5
