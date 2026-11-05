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

import std/[unittest, options, importutils, strutils, times]

import pkg/results

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/buffer/search {.all.}
import ../src/moepkg/unicode_utils
import search_test_helper

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

suite "Buffer Search - Edge cases":
  test "Single character buffer":
    let buf = newTextBuffer("a")
    # Start from before the line to find the "a" at column 0
    let result = buf.findNext("a", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 0

    # From column 0 the search wraps back to the only occurrence, as Vim's does
    let result2 = buf.findNext("a", BufferPosition(line: 0, column: 0))
    check result2 == some(BufferPosition(line: 0, column: 0))

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

  test "findWordMatchRanges walks bytes past an undecodable byte":
    # The byte cursor advances by what each character occupies, not by the
    # width the byte would re-encode to: counting the latter ran the cursor
    # past the end of the line and read out of bounds.
    let buf = newTextBuffer("\xFFab cd")
    let ranges = buf.findWordMatchRanges(0, "cd")
    check ranges.len == 1
    check ranges[0].startCol == 4
    check ranges[0].endCol == 6
    # A word run reaching end-of-line is closed against the real byte span.
    check buf.findWordMatchRanges(0, "abcd").len == 0

  test "findWordMatchRanges columns match charLen past a truncated lead byte":
    # 0xE3 advertises three bytes but is followed by 'a' and 'b', so it stands
    # alone as one column. `fastRuneAt` would swallow all three and report the
    # match two columns to the left of where it is drawn.
    let buf = newTextBuffer("\xE3ab cd")
    check buf.getLine(0).charLen == 6
    let ranges = buf.findWordMatchRanges(0, "cd")
    check ranges.len == 1
    check ranges[0].startCol == 4
    check ranges[0].endCol == 6

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

  test "findWordMatchRanges multibyte CJK word - rune columns":
    # '変'/'数' are 3 bytes each; columns must be reported in rune units.
    let buf = newTextBuffer("変数 foo 変数")
    let ranges = buf.findWordMatchRanges(0, "変数")
    check ranges.len == 2
    check ranges[0].startCol == 0
    check ranges[0].endCol == 2
    check ranges[1].startCol == 7
    check ranges[1].endCol == 9

  test "findWordMatchRanges multibyte accented Latin":
    # 'é' is 2 bytes; byte-slice comparison must stay exact across runs.
    let buf = newTextBuffer("café résumé café")
    let ranges = buf.findWordMatchRanges(0, "café")
    check ranges.len == 2
    check ranges[0].startCol == 0
    check ranges[0].endCol == 4
    check ranges[1].startCol == 12
    check ranges[1].endCol == 16

  test "findWordMatchRanges multibyte excludeCol uses rune column":
    let buf = newTextBuffer("café résumé café")
    # excludeCol 13 falls inside the second "café" (rune cols 12..15).
    let ranges = buf.findWordMatchRanges(0, "café", excludeCol = 13)
    check ranges.len == 1
    check ranges[0].startCol == 0
    check ranges[0].endCol == 4

  test "findWordMatchRanges multibyte prefix not a false match":
    # "変" must not match the longer word run "変数".
    let buf = newTextBuffer("変数 変")
    let ranges = buf.findWordMatchRanges(0, "変")
    check ranges.len == 1
    check ranges[0].startCol == 3
    check ranges[0].endCol == 4

suite "Buffer Search - regexPattern":
  privateAccess(RegexPattern)

  test "a valid pattern compiles":
    check regexPattern("hello", false).re.isSome
    check regexPattern("hello", true).re.isSome

  test "an invalid pattern does not":
    check regexPattern("[invalid", false).re.isNone

  test "the last one is kept and shared":
    # Matched line by line, a pattern would otherwise be compiled, or copied
    # out of the cache, for every line.
    let first = regexPattern("test", false)
    check regexPattern("test", false) == first
    check regexPattern("test", true) != first
    check regexPattern("bar", false) != first

  test "a pattern that does not compile is kept too":
    # A pattern still being typed would otherwise be parsed again for every
    # line.
    let first = regexPattern("foo(", false)
    check first.re.isNone
    check regexCache == first
    check regexPattern("foo(", false) == first

  test "an empty pattern matches nothing and leaves the kept one":
    # Compiled, it would match everywhere, and cost the highlight its compiled
    # pattern.
    let
      b = newTextBuffer("foo")
      start = BufferPosition(line: 0, column: 0)
      first = regexPattern("foo", false)
    check b.findSearchMatchRanges(0, "").len == 0
    check b.matchAt(start, "").isNone
    check b.findNext("", start).isNone
    check b.findPrev("", start).isNone
    check firstSubstituteMatch("foo", "", false, smRegex).isNone
    check countSubstituteMatches("foo", "", false, true, smRegex) == 0
    let replaced =
      substituteMatches("foo", "", parseReplacement("x"), false, true, smRegex)
    check replaced.count == 0
    check regexCache == first

  test "a valid pattern compiles after a kept failure":
    check regexPattern("foo(", false).re.isNone
    check regexPattern("foo(", true).re.isNone
    check regexPattern("foo", true).re.isSome
    check regexCache.re.isSome

suite "Buffer Search - Regex findNext":
  test "findNext with character class":
    let buf = newTextBuffer("abc 123 def")
    let result = buf.findNext("\\d+", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 4

  test "findNext with alternation":
    let buf = newTextBuffer("cat and dog")
    let result = buf.findNext("cat|dog", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 0

    let result2 = buf.findNext("cat|dog", result.get)
    check result2.isSome
    check result2.get.column == 8

  test "findNext with dot (any character)":
    let buf = newTextBuffer("abc def")
    let result = buf.findNext("a.c", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 0

  test "findNext with anchored pattern (^)":
    let buf = newTextBuffer("hello world\nhello again")
    let result = buf.findNext("^hello", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.line == 0
    check result.get.column == 0

  test "findNext with anchored pattern ($)":
    let buf = newTextBuffer("hello world\nfoo bar")
    let result = buf.findNext("world$", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.line == 0
    check result.get.column == 6

  test "findNext with quantifier (+)":
    let buf = newTextBuffer("aaa bbb ccc")
    let result = buf.findNext("b+", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 4

  test "findNext with quantifier (*)":
    let buf = newTextBuffer("ac abc abbc")
    let result = buf.findNext("ab*c", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 0 # "ac" matches ab*c

  test "findNext with quantifier (?)":
    let buf = newTextBuffer("color colour")
    let result = buf.findNext("colou?r", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 0

    let result2 = buf.findNext("colou?r", result.get)
    check result2.isSome
    check result2.get.column == 6

  test "findNext with group":
    let buf = newTextBuffer("foobar foobaz")
    let result = buf.findNext("foo(bar|baz)", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 0

    let result2 = buf.findNext("foo(bar|baz)", result.get)
    check result2.isSome
    check result2.get.column == 7

  test "findNext with word boundary (\\b)":
    let buf = newTextBuffer("foobar foo bar")
    let result = buf.findNext("\\bfoo\\b", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 7 # standalone "foo", not "foobar"

  test "findNext with invalid regex returns none":
    let buf = newTextBuffer("hello world")
    let result = buf.findNext("[invalid", BufferPosition(line: 0, column: 0))
    check result.isNone

  test "findNext regex wraps around":
    let buf = newTextBuffer("123 abc 456")
    let result = buf.findNext("\\d+", BufferPosition(line: 0, column: 3))
    check result.isSome
    check result.get.column == 8 # "456"

    # From "456" at col 8, wrap around to "123" at col 0
    let result2 = buf.findNext("\\d+", BufferPosition(line: 0, column: 10))
    check result2.isSome
    check result2.get.column == 0 # wraps to "123"

  test "findNext regex multiline":
    let buf = newTextBuffer("foo 123\nbar 456\nbaz 789")
    let result = buf.findNext("\\d+", BufferPosition(line: 0, column: 3))
    check result.isSome
    check result.get.line == 0
    check result.get.column == 4 # "123" at col 4

suite "Buffer Search - Regex findPrev":
  test "findPrev with character class":
    let buf = newTextBuffer("abc 123 def 456")
    let result = buf.findPrev("\\d+", BufferPosition(line: 0, column: 12))
    check result.isSome
    check result.get.column == 4 # "123"

  test "findPrev with alternation":
    let buf = newTextBuffer("cat and dog")
    let result = buf.findPrev("cat|dog", BufferPosition(line: 0, column: 8))
    check result.isSome
    check result.get.column == 0

  test "findPrev regex wraps around":
    let buf = newTextBuffer("123 abc 456")
    let result = buf.findPrev("\\d+", BufferPosition(line: 0, column: 0))
    check result.isSome
    check result.get.column == 8 # wraps to "456"

  test "findPrev with invalid regex returns none":
    let buf = newTextBuffer("hello world")
    let result = buf.findPrev("[invalid", BufferPosition(line: 0, column: 5))
    check result.isNone

  test "findPrev regex multiline":
    let buf = newTextBuffer("foo 123\nbar 456\nbaz 789")
    let result = buf.findPrev("\\d+", BufferPosition(line: 2, column: 0))
    check result.isSome
    check result.get.line == 1
    check result.get.column == 4

suite "Buffer Search - Regex findSearchMatchRanges":
  test "findSearchMatchRanges with regex":
    let buf = newTextBuffer("abc 123 def 456")
    let ranges = buf.findSearchMatchRanges(0, "\\d+")
    check ranges.len == 2
    check ranges[0].startCol == 4
    check ranges[0].endCol == 7
    check ranges[1].startCol == 12
    check ranges[1].endCol == 15

  test "findSearchMatchRanges variable length matches":
    let buf = newTextBuffer("a ab abc abcd")
    let ranges = buf.findSearchMatchRanges(0, "ab\\w*")
    check ranges.len == 3
    # "ab" at col 2
    check ranges[0].startCol == 2
    check ranges[0].endCol == 4
    # "abc" at col 5
    check ranges[1].startCol == 5
    check ranges[1].endCol == 8
    # "abcd" at col 9
    check ranges[2].startCol == 9
    check ranges[2].endCol == 13

  test "findSearchMatchRanges with character class":
    let buf = newTextBuffer("Hello World 123")
    let ranges = buf.findSearchMatchRanges(0, "[A-Z][a-z]+")
    check ranges.len == 2
    check ranges[0].startCol == 0
    check ranges[0].endCol == 5 # "Hello"
    check ranges[1].startCol == 6
    check ranges[1].endCol == 11 # "World"

  test "findSearchMatchRanges with alternation":
    let buf = newTextBuffer("cat dog bird cat")
    let ranges = buf.findSearchMatchRanges(0, "cat|dog")
    check ranges.len == 3
    check ranges[0].startCol == 0
    check ranges[0].endCol == 3
    check ranges[1].startCol == 4
    check ranges[1].endCol == 7
    check ranges[2].startCol == 13
    check ranges[2].endCol == 16

  test "findSearchMatchRanges with invalid regex":
    let buf = newTextBuffer("hello world")
    let ranges = buf.findSearchMatchRanges(0, "[invalid")
    check ranges.len == 0

  test "findSearchMatchRanges smWord uses literal matching":
    let buf = newTextBuffer("foobar foo bar")
    # "foo" should only match standalone "foo"
    let ranges = buf.findSearchMatchRanges(0, "foo", match = smWord)
    check ranges.len == 1
    check ranges[0].startCol == 7
    check ranges[0].endCol == 10

  test "findSearchMatchRanges smWord ignorecase matches either case":
    let buf = newTextBuffer("Foo foobar FOO")
    let ranges = buf.findSearchMatchRanges(0, "foo", ignorecase = true, match = smWord)
    check ranges.len == 2
    check ranges[0].startCol == 0
    check ranges[1].startCol == 11

  test "findSearchMatchRanges smWord with CJK respects Unicode word boundaries":
    # "日本" appears standalone at col 5 and as a prefix of "日本語" at col 12.
    # Because CJK ideographs are now word characters, the "日本語" occurrence
    # must NOT count as a whole-word match: the trailing '語' extends the word
    # past the search term.
    let buf = newTextBuffer("test 日本 foo 日本語 bar")
    let ranges = buf.findSearchMatchRanges(0, "日本", match = smWord)
    check ranges.len == 1
    check ranges[0].startCol == 5
    check ranges[0].endCol == 7

  test "findSearchMatchRanges smWord matches CJK between non-word boundaries":
    # "日本語" surrounded by ASCII spaces is a complete word.
    let buf = newTextBuffer("abc 日本語 xyz")
    let ranges = buf.findSearchMatchRanges(0, "日本語", match = smWord)
    check ranges.len == 1
    check ranges[0].startCol == 4
    check ranges[0].endCol == 7

  test "findSearchMatchRanges smRegex treats as regex":
    let buf = newTextBuffer("foobar foo bar")
    # "foo" as regex matches "foobar" and "foo"
    let ranges = buf.findSearchMatchRanges(0, "foo", match = smRegex)
    check ranges.len == 2
    check ranges[0].startCol == 0
    check ranges[0].endCol == 3
    check ranges[1].startCol == 7
    check ranges[1].endCol == 10

  test "findSearchMatchRanges regex case insensitive":
    let buf = newTextBuffer("Foo FOO foo")
    let ranges = buf.findSearchMatchRanges(0, "foo", ignorecase = true)
    check ranges.len == 3

  test "findSearchMatchRanges regex with Unicode":
    let buf = newTextBuffer("テスト123テスト456")
    let ranges = buf.findSearchMatchRanges(0, "\\d+")
    check ranges.len == 2
    check ranges[0].startCol == 3
    check ranges[0].endCol == 6
    check ranges[1].startCol == 9
    check ranges[1].endCol == 12

suite "Buffer Search - Regex edge cases":
  test "Escaped special characters treated as literal":
    let buf = newTextBuffer("hello.world foo.bar")
    # Escaped dot matches literal dot
    let result = buf.findNext("hello\\.world", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 0

  test "Unescaped dot matches any character":
    let buf = newTextBuffer("hello world")
    let result = buf.findNext("hello.world", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 0

  test "Special regex chars in search pattern":
    let buf = newTextBuffer("price is $100")
    # Escaped $ matches literal dollar sign
    let result = buf.findNext("\\$\\d+", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 9

  test "Empty match with zero-width pattern doesn't infinite loop":
    let buf = newTextBuffer("abc")
    # Empty string regex or similar patterns that can match zero-width
    let ranges = buf.findSearchMatchRanges(0, "a*")
    # Should not hang; may produce matches at each position
    check ranges.len > 0

  test "Regex with Unicode character classes":
    let buf = newTextBuffer("abc あいう 123")
    let result = buf.findNext("[あ-お]+", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 4

  test "Complex regex pattern":
    let buf = newTextBuffer("foo123bar baz456qux")
    let ranges = buf.findSearchMatchRanges(0, "[a-z]+\\d+[a-z]+")
    check ranges.len == 2
    check ranges[0].startCol == 0
    check ranges[0].endCol == 9 # "foo123bar"
    check ranges[1].startCol == 10
    check ranges[1].endCol == 19 # "baz456qux"

  test "Repeated invalid regex doesn't crash":
    let buf = newTextBuffer("hello world")
    for _ in 0 ..< 10:
      let result = buf.findNext("(unclosed", BufferPosition(line: 0, column: 0))
      check result.isNone

  test "findPrev with zero-width match pattern":
    let buf = newTextBuffer("abc def")
    # \\b is zero-width; findPrev should not infinite loop
    let result = buf.findPrev("\\b", BufferPosition(line: 0, column: 5))
    check result.isSome # Should find a word boundary before position

suite "Buffer Search - invalid UTF-8 lines":
  # Undecodable bytes are replaced with U+FFFD before regex matching, so
  # searches must not crash and character columns must match the editor model
  # (each undecodable byte counts as one character).

  test "findNext on line with leading invalid byte":
    let buf = newTextBuffer("\xFFab cd")
    let result = buf.findNext("cd", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.line == 0
    check result.get.column == 4

  test "findNext dollar anchor on line ending with invalid byte":
    let buf = newTextBuffer("ab\xFF")
    let result = buf.findNext("$", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 3

  test "findNext dollar anchored literal does not match before trailing invalid byte":
    let buf = newTextBuffer("ab\xFF")
    # "b" is not at EOL (the invalid byte occupies the last column)
    let result = buf.findNext("b$", BufferPosition(line: 0, column: -1))
    check result.isNone

  test "findNext caret anchor on line starting with invalid byte":
    let buf = newTextBuffer("\xFFab")
    let result = buf.findNext("^", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 0

  test "findNext caret anchored literal does not match when not at line start":
    let buf = newTextBuffer("\xFFab")
    # "a" is not at the line start (the invalid byte occupies column 0)
    let result = buf.findNext("^a", BufferPosition(line: 0, column: -1))
    check result.isNone

  test "findNext dot spans undecodable byte":
    let buf = newTextBuffer("a\xFFb")
    let result = buf.findNext("a.b", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 0

  test "findNext dollar anchored pattern does not match before trailing invalid byte":
    let buf = newTextBuffer("foo\xFF")
    let result = buf.findNext("foo$", BufferPosition(line: 0, column: -1))
    check result.isNone

  test "findNext dollar anchored pattern matches at end after leading invalid byte":
    let buf = newTextBuffer("\xFFfoo")
    let result = buf.findNext("foo$", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 1

  test "findNext any-char-and-dollar pattern covers trailing invalid byte":
    let buf = newTextBuffer("ab\xFF")
    let result = buf.findNext(".*$", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.column == 0

  test "findNext word boundary at undecodable byte":
    let buf = newTextBuffer("ab\xFFcd")
    let result = buf.findNext("\\b", BufferPosition(line: 0, column: 1))
    check result.isSome
    check result.get.column == 2

  test "findNext across lines with invalid byte":
    let buf = newTextBuffer("ab\xFF\ncd")
    let result = buf.findNext("cd", BufferPosition(line: 0, column: -1))
    check result.isSome
    check result.get.line == 1
    check result.get.column == 0

  test "findPrev on line with leading invalid byte":
    let buf = newTextBuffer("\xFFab cd")
    let result = buf.findPrev("a", BufferPosition(line: 0, column: 3))
    check result.isSome
    check result.get.column == 1

  test "findPrev dollar anchor on line ending with invalid byte":
    let buf = newTextBuffer("ab\xFF")
    let result = buf.findPrev("$", BufferPosition(line: 0, column: 0))
    check result.isSome
    check result.get.column == 3

  test "findSearchMatchRanges spans undecodable byte":
    let buf = newTextBuffer("a\xFFb")
    let ranges = buf.findSearchMatchRanges(0, "a.b")
    check ranges == @[ColumnRange(startCol: 0, endCol: 3)]

  test "findSearchMatchRanges dollar anchored on invalid byte line":
    let buf = newTextBuffer("x\xFFfoo")
    let ranges = buf.findSearchMatchRanges(0, "foo$")
    check ranges == @[ColumnRange(startCol: 2, endCol: 5)]

  test "findSearchMatchRanges any-char-and-dollar on invalid byte line":
    let buf = newTextBuffer("ab\xFF")
    # The trailing zero-width match at EOL is pre-existing behavior
    let ranges = buf.findSearchMatchRanges(0, ".*$")
    check ranges ==
      @[ColumnRange(startCol: 0, endCol: 3), ColumnRange(startCol: 3, endCol: 3)]

  test "findNext wraps around to earlier line with invalid byte":
    let buf = newTextBuffer("\xFFab\ncd")
    let result = buf.findNext("a", BufferPosition(line: 1, column: 0))
    check result.isSome
    check result.get.line == 0
    check result.get.column == 1

  test "findNext wraps within same line with invalid byte":
    let buf = newTextBuffer("a\xFFb")
    let result = buf.findNext("a", BufferPosition(line: 0, column: 2))
    check result.isSome
    check result.get.line == 0
    check result.get.column == 0

  test "findPrev searches earlier line with invalid byte":
    let buf = newTextBuffer("\xFFab\ncd")
    let result = buf.findPrev("a", BufferPosition(line: 1, column: 1))
    check result.isSome
    check result.get.line == 0
    check result.get.column == 1

suite "Buffer search - whole word":
  test "findNext smWord skips substring matches":
    let buf = newTextBuffer("targeted\ntarget\n")
    let result =
      buf.findNext("target", BufferPosition(line: 0, column: -1), match = smWord)
    check result.isSome
    check result.get == BufferPosition(line: 1, column: 0)

  test "findNext smWord wraps around":
    let buf = newTextBuffer("target\ntargeted\n")
    let result =
      buf.findNext("target", BufferPosition(line: 1, column: 0), match = smWord)
    check result.isSome
    check result.get == BufferPosition(line: 0, column: 0)

  test "findNext smWord finds a later match on the same line":
    let buf = newTextBuffer("target targeted target\n")
    let result =
      buf.findNext("target", BufferPosition(line: 0, column: 0), match = smWord)
    check result.isSome
    check result.get == BufferPosition(line: 0, column: 16)

  test "findNext smWord matches literally, not as a regex":
    let buf = newTextBuffer("axb\na.b\n")
    let result =
      buf.findNext("a.b", BufferPosition(line: 0, column: -1), match = smWord)
    check result.isSome
    check result.get == BufferPosition(line: 1, column: 0)

  test "findNext smWord returns none when only substrings match":
    let buf = newTextBuffer("targeted\nretarget\n")
    let result =
      buf.findNext("target", BufferPosition(line: 0, column: -1), match = smWord)
    check result.isNone

  test "findPrev smWord skips substring matches":
    let buf = newTextBuffer("target\ntargeted\n")
    let result =
      buf.findPrev("target", BufferPosition(line: 1, column: 8), match = smWord)
    check result.isSome
    check result.get == BufferPosition(line: 0, column: 0)

  test "findPrev smWord wraps around":
    let buf = newTextBuffer("targeted\ntarget\n")
    let result =
      buf.findPrev("target", BufferPosition(line: 0, column: 0), match = smWord)
    check result.isSome
    check result.get == BufferPosition(line: 1, column: 0)

  test "findPrev smWord finds an earlier match on the same line":
    let buf = newTextBuffer("target targeted target\n")
    let result =
      buf.findPrev("target", BufferPosition(line: 0, column: 16), match = smWord)
    check result.isSome
    check result.get == BufferPosition(line: 0, column: 0)

  test "smWord bounds a word by a change of class, as Vim's \\< and \\>":
    # `日本` is a word of its own between ASCII letters, as in Vim.
    let buf = newTextBuffer("abc日本def 日本語")
    check buf.findSearchMatchRanges(0, "日本", match = smWord) ==
      @[ColumnRange(startCol: 3, endCol: 5)]
    check buf.findSearchMatchRanges(0, "abc", match = smWord) ==
      @[ColumnRange(startCol: 0, endCol: 3)]

  test "smWord bounds only an end that is a word character":
    # Vim's * puts no \< before punctuation, nor \> after it.
    let buf = newTextBuffer("a->b ->")
    check buf.findSearchMatchRanges(0, "->", match = smWord) ==
      @[ColumnRange(startCol: 1, endCol: 3), ColumnRange(startCol: 5, endCol: 7)]
    check buf.findSearchMatchRanges(0, "->b", match = smWord) ==
      @[ColumnRange(startCol: 1, endCol: 4)]

  test "smLiteral matches inside words and literally":
    let buf = newTextBuffer("foobar foo a.b axb")
    check buf.findSearchMatchRanges(0, "foo", match = smLiteral) ==
      @[ColumnRange(startCol: 0, endCol: 3), ColumnRange(startCol: 7, endCol: 10)]
    check buf.findSearchMatchRanges(0, "a.b", match = smLiteral) ==
      @[ColumnRange(startCol: 11, endCol: 14)]

  test "a literal match does not split a character from its composing ones":
    # `cafe` followed by U+0301 is `café`: Vim does not match `cafe` in it, and
    # U+0301 alone finds the whole `é`.
    let buf = newTextBuffer("café cafe")
    check buf.findSearchMatchRanges(0, "cafe", match = smLiteral) ==
      @[ColumnRange(startCol: 6, endCol: 10)]
    check buf.findSearchMatchRanges(0, "café", match = smWord) ==
      @[ColumnRange(startCol: 0, endCol: 5)]
    check buf.findSearchMatchRanges(0, "\u0301", match = smLiteral) ==
      @[ColumnRange(startCol: 3, endCol: 5)]

  test "a literal match ignores the case of any letter, as Vim's utf_fold":
    let buf = newTextBuffer("Ärger ärger ÄRGER")
    check buf.findSearchMatchRanges(0, "Ärger", ignorecase = true, match = smWord).len ==
      3
    check buf.findSearchMatchRanges(0, "Ärger", match = smWord) ==
      @[ColumnRange(startCol: 0, endCol: 5)]

  test "Vim's \\< and \\> look at the classes of the line's characters":
    # The Kelvin sign folds to `k` but is punctuation, so `\<k\>` skips it as
    # Vim's does, while g* (no bounds) takes it.
    let buf = newTextBuffer("k \u212a k")
    check buf.findSearchMatchRanges(0, "k", ignorecase = true, match = smWord) ==
      @[ColumnRange(startCol: 0, endCol: 1), ColumnRange(startCol: 4, endCol: 5)]
    check buf.findSearchMatchRanges(0, "k", ignorecase = true, match = smLiteral).len ==
      3

  test "literal matches do not overlap, as Vim's search with cpoptions c":
    # Each match is looked for from where the one before ends.
    check newTextBuffer("aaaa").findSearchMatchRanges(0, "aa", match = smLiteral) ==
      @[ColumnRange(startCol: 0, endCol: 2), ColumnRange(startCol: 2, endCol: 4)]
    check newTextBuffer("aaa").findSearchMatchRanges(0, "aa", match = smLiteral) ==
      @[ColumnRange(startCol: 0, endCol: 2)]
    # So n from the match at column 4 skips the one at 5 (Vim's g* then n).
    check newTextBuffer("aaa aaaa\naaaa").findNext(
      "aaa", BufferPosition(line: 0, column: 4), match = smLiteral
    ) == some(BufferPosition(line: 1, column: 0))

suite "Buffer search - the only match":
  # The second round of Vim's searchit takes the start line whole, so a search
  # from the only match finds it again.
  test "findNext finds the only match again":
    let buf = newTextBuffer("foo bar\nbaz")
    let start = BufferPosition(line: 0, column: 0)
    check buf.findNext("foo", start) == some(start)
    check buf.findNext("foo", start, match = smWord) == some(start)

  test "findPrev finds the only match again":
    let buf = newTextBuffer("baz\nbar foo")
    let start = BufferPosition(line: 1, column: 4)
    check buf.findPrev("foo", start) == some(start)
    check buf.findPrev("foo", start, match = smWord) == some(start)

  test "a match before the start on its line still comes first":
    let buf = newTextBuffer("foo foo")
    check buf.findNext("foo", BufferPosition(line: 0, column: 4)) ==
      some(BufferPosition(line: 0, column: 0))
    check buf.findPrev("foo", BufferPosition(line: 0, column: 0)) ==
      some(BufferPosition(line: 0, column: 4))

suite "Buffer search - empty lines and empty matches":
  # Vim's searchit: an empty line has its empty match, and a match at the end
  # of a line counts as on its last character, where the cursor goes.
  test "/^$ finds an empty line":
    let b = newTextBuffer("foo\n\nbar\n\nbaz")
    check b.findNext("^$", BufferPosition(line: 0, column: 1)) ==
      some(BufferPosition(line: 1, column: 0))
    check b.findNext("^\\s*$", BufferPosition(line: 0, column: 0)) ==
      some(BufferPosition(line: 1, column: 0))

  test "/^$ from an empty line goes on to the next one":
    let b = newTextBuffer("foo\n\nbar\n\nbaz")
    check b.findNext("^$", BufferPosition(line: 1, column: 0)) ==
      some(BufferPosition(line: 3, column: 0))
    check b.findNext("^$", BufferPosition(line: 3, column: 0)) ==
      some(BufferPosition(line: 1, column: 0))

  test "?^$ finds an empty line before":
    let b = newTextBuffer("foo\n\nbar\n\nbaz")
    check b.findPrev("^$", BufferPosition(line: 4, column: 2)) ==
      some(BufferPosition(line: 3, column: 0))
    check b.findPrev("^$", BufferPosition(line: 3, column: 0)) ==
      some(BufferPosition(line: 1, column: 0))
    check b.findPrev("^$", BufferPosition(line: 1, column: 0)) ==
      some(BufferPosition(line: 3, column: 0))

  test "the only empty line is found again":
    let b = newTextBuffer("foo\n\nbar")
    let start = BufferPosition(line: 1, column: 0)
    check b.findNext("^$", start) == some(start)
    check b.findPrev("^$", start) == some(start)

  test "/$ moves on from the last character":
    let b = newTextBuffer("abc\nde")
    check b.findNext("$", BufferPosition(line: 0, column: 1)) ==
      some(BufferPosition(line: 0, column: 3))
    check b.findNext("$", BufferPosition(line: 0, column: 2)) ==
      some(BufferPosition(line: 1, column: 2))

  test "/$ moves on from a last character with composing characters":
    # Vim's searchit takes the character under the cursor whole (extra_col).
    let b = newTextBuffer("ae\u0301\u0302\nx")
    check b.findNext("$", BufferPosition(line: 0, column: 0)) ==
      some(BufferPosition(line: 0, column: 4))
    for column in 1 .. 3:
      check b.findNext("$", BufferPosition(line: 0, column: column)) ==
        some(BufferPosition(line: 1, column: 1))

  test "a search forward from a negative column finds the only match on its line":
    let b = newTextBuffer("foo\nbar")
    check b.findNext("foo", BufferPosition(line: 0, column: -1)) ==
      some(BufferPosition(line: 0, column: 0))
    check b.findNext("baz", BufferPosition(line: 0, column: -1)).isNone
    check newTextBuffer("foo").findNext("foo", BufferPosition(line: 0, column: -1)) ==
      some(BufferPosition(line: 0, column: 0))

  test "an empty match at the end of a line leads on to an empty line":
    let b = newTextBuffer("ab\n\ncd")
    check b.findNext("x*", BufferPosition(line: 0, column: 1)) ==
      some(BufferPosition(line: 1, column: 0))
    check b.findPrev("x*", BufferPosition(line: 2, column: 0)) ==
      some(BufferPosition(line: 1, column: 0))
    # Backward, the end of a line is looked at only from its start.
    check b.findPrev("x*", BufferPosition(line: 1, column: 0)) ==
      some(BufferPosition(line: 0, column: 1))

  test "an empty line has its empty match to highlight":
    let b = newTextBuffer("foo\n\nbar")
    check b.findSearchMatchRanges(1, "^$") == @[ColumnRange(startCol: 0, endCol: 0)]
    check b.findSearchMatchRanges(1, "x*") == @[ColumnRange(startCol: 0, endCol: 0)]
    check b.findSearchMatchRanges(1, "foo").len == 0

  test "an empty match steps a character, not a byte":
    check newTextBuffer("éa").findSearchMatchRanges(0, "x*") ==
      @[
        ColumnRange(startCol: 0, endCol: 0),
        ColumnRange(startCol: 1, endCol: 1),
        ColumnRange(startCol: 2, endCol: 2),
      ]

  test "the highlight looks at the end of the line after a match, a search does not":
    # Vim's hlsearch (next_search_hl) tries the end of the line again; searchit
    # stops there.
    let b = newTextBuffer("abc\nabc")
    check b.findSearchMatchRanges(0, "c|$") ==
      @[ColumnRange(startCol: 2, endCol: 3), ColumnRange(startCol: 3, endCol: 3)]
    check b.findNext("c|$", BufferPosition(line: 0, column: 1)) ==
      some(BufferPosition(line: 0, column: 2))
    check b.findNext("c|$", BufferPosition(line: 0, column: 2)) ==
      some(BufferPosition(line: 1, column: 2))

suite "Buffer search - regex matches do not overlap":
  # Vim's searchit with 'cpoptions' c looks for each match where the one before
  # ends, from the start of the line, the matches hlsearch highlights.
  test "n skips a match inside the one under the cursor":
    let b = newTextBuffer("aaaa\naaaa")
    check b.findNext("aa", BufferPosition(line: 0, column: 0)) ==
      some(BufferPosition(line: 0, column: 2))
    check b.findNext("aa", BufferPosition(line: 0, column: 2)) ==
      some(BufferPosition(line: 1, column: 0))

  test "a match counts from the start of the line, not from the cursor":
    let b = newTextBuffer("aaa\naaa")
    check b.findNext("aa", BufferPosition(line: 0, column: 0)) ==
      some(BufferPosition(line: 1, column: 0))
    check b.findPrev("aa", BufferPosition(line: 1, column: 2)) ==
      some(BufferPosition(line: 1, column: 0))
    check b.findPrev("aa", BufferPosition(line: 1, column: 0)) ==
      some(BufferPosition(line: 0, column: 0))

suite "Buffer search - identUnderCursor":
  # Vim's find_ident_under_cursor() for * and #.
  proc ident(text: string, column: int): Option[(int, int)] =
    let r =
      newTextBuffer(text).identUnderCursor(BufferPosition(line: 0, column: column))
    if r.isSome:
      some((r.get.startCol, r.get.endCol))
    else:
      none((int, int))

  test "the keyword under the cursor":
    check ident("foo bar baz", 5) == some((4, 7))
    check ident("foo_bar1 x", 0) == some((0, 8))

  test "the keyword after the cursor on the line":
    check ident("x -> y", 2) == some((5, 6))
    check ident("a.b a.b", 1) == some((2, 3))
    check ident("foo   bar", 4) == some((6, 9))

  test "the non-blank text when no keyword follows":
    check ident("x ->  ", 3) == some((2, 4))
    check ident("foo..", 4) == some((3, 5))

  test "nothing after the cursor but blanks":
    check ident("foo   ", 4).isNone
    check ident("   ", 1).isNone
    check ident("", 0).isNone

  test "a keyword is a run of one class":
    check ident("abc日本def", 3) == some((3, 5))
    check ident("abc日本def", 1) == some((0, 3))
    check ident("日本の 😀x", 0) == some((0, 2))
    check ident("日本の 😀x", 4) == some((4, 5))

  test "a character takes its composing characters":
    check ident("café x", 0) == some((0, 5))
    # On the composing character, as on the character it is part of.
    check ident("ét", 1) == some((0, 3))

suite "matchAt":
  proc at(b: TextBuffer, line, column: int, pattern: string): Option[(int, int)] =
    let r = b.matchAt(BufferPosition(line: line, column: column), pattern)
    if r.isSome:
      some((r.get.startCol, r.get.endCol))
    else:
      none((int, int))

  test "the cursor is on a match a search goes through where it stands in it":
    let b = newTextBuffer("a a a zz qq\n")
    check b.at(0, 0, "a a ") == some((0, 4))
    check b.at(0, 3, "a a ") == some((0, 4))
    # The one at column 2 overlaps it, so no search goes through it.
    check b.at(0, 4, "a a ").isNone

  test "on an empty match where it stands":
    let b = newTextBuffer("foo\n\nbar")
    check b.at(1, 0, "^$") == some((0, 0))
    check b.at(0, 0, "^") == some((0, 0))
    check b.at(0, 1, "^").isNone

  test "on one at the end of the line from the last character too":
    # Where a search puts the cursor on it.
    let b = newTextBuffer("abc\nde")
    check b.at(0, 2, "$") == some((3, 3))
    check b.at(0, 3, "$") == some((3, 3))
    check b.at(0, 1, "$").isNone

  test "on one at the end of the line from each part of the last character":
    let b = newTextBuffer("ae\u0301\u0302\nx")
    for column in 1 .. 3:
      check b.at(0, column, "$") == some((4, 4))
    check b.at(0, 0, "$").isNone

  test "not on the end of the line a search does not go through":
    # Only the highlight looks at the end of the line after a match.
    let b = newTextBuffer("abc")
    check b.at(0, 2, "c|$") == some((2, 3))
    check b.at(0, 3, "c|$").isNone

  test "there is none where no match is":
    let b = newTextBuffer("foo\n")
    check b.at(0, 1, "bar").isNone
    check b.at(3, 0, "foo").isNone
    check b.at(0, 0, "").isNone

suite "substituteMatches":
  # Expectations are Vim 9.2's substitute() with `\\V`.
  const
    Acute = "\u0301"
    Circumflex = "\u0302"

  proc replaced(line, pattern: string, ignorecase = false): string =
    let (lines, count) = line.substituteMatches(
      pattern, parseReplacement("#"), ignorecase, true, smLiteral
    )
    if count > 0:
      lines.join("\n")
    else:
      line

  test "No match leaves nothing to build":
    check "abc".substituteMatches("x", parseReplacement("#"), false, true, smRegex) ==
      (newSeq[string](), 0)

  test "Only the first match unless told":
    check "aXa".substituteMatches("a", parseReplacement("#"), false, false, smRegex) ==
      (@["#Xa"], 1)

  test "A bare character is not one that holds a composing character":
    check replaced("e" & Acute & "x", "e") == "e" & Acute & "x"

  test "A composing character alone finds the character that holds it":
    check replaced("e" & Acute & "x", Acute) == "#x"

  test "A composing character at the start of a line holds nothing":
    check replaced(Acute & "x", Acute) == Acute & "x"

  test "A match takes the composing characters it did not ask for":
    check replaced("e" & Acute & Circumflex & "x", "e" & Acute) == "#x"

  test "Composing characters match in any order":
    check replaced("e" & Circumflex & Acute & "x", "e" & Acute) == "#x"

  test "A composing character the text lacks is no match":
    check replaced("e" & Circumflex, "e" & Acute) == "e" & Circumflex

  test "A character with composing characters does not fold":
    check replaced("e" & Acute, "E" & Acute, ignorecase = true) == "e" & Acute

  test "Case folds as Vim's utf_fold does":
    check replaced("\u03c2 \u03c3 \u03a3", "\u03c3", ignorecase = true) == "# # #"
    check replaced("\u0130 i I", "i", ignorecase = true) == "\u0130 # #"

suite "substituteMatches with Vim's replacement specials":
  # Expectations are Vim 9.2's :s, groups written as nim-regex writes them.
  proc replaced(line, pattern, replacement: string, match = smRegex): string =
    ## The lines it makes, a line break between two.
    let (lines, count) =
      line.substituteMatches(pattern, parseReplacement(replacement), false, true, match)
    if count > 0:
      lines.join("\n")
    else:
      line

  test "& and \\0 are the match, \\& an ampersand":
    check replaced("abc", "b", "[&]") == "a[b]c"
    check replaced("abc", "b", "[\\0]") == "a[b]c"
    check replaced("abc", "b", "[\\&]") == "a[&]c"

  test "The match of a pattern matched as it is":
    check replaced("a.c", ".", "[&]", smLiteral) == "a[.]c"

  test "A group is PCRE's `(...)`; Vim's `\\(` finds a `(`, as the help says":
    check replaced("call (arg)", "(arg)", "[\\1]") == "call ([arg])"
    check replaced("call (arg)", "\\(arg\\)", "x") == "call x"

  test "\\1 to \\9 are the groups":
    check replaced("abc", "(b)(c)", "[\\2\\1]") == "a[cb]"
    check replaced("foo bar", "(fo+)", "[\\1]") == "[foo] bar"

  test "A group that is unset or missing is empty":
    check replaced("abc", "(x)?b", "[\\1]") == "a[]c"
    check replaced("abc", "b", "[\\1]") == "a[]c"
    check replaced("abc", "b", "[\\9]") == "a[]c"

  test "A backslash takes any other character as it is":
    check replaced("abc", "b", "[\\x]") == "a[x]c"
    check replaced("abc", "b", "[\\\\]") == "a[\\]c"
    check replaced("abc", "b", "[\\~]") == "a[~]c"
    check replaced("abc", "b", "[\\t]") == "a[\t]c"

  test "\\u and \\l change the next character":
    check replaced("abc", "b", "\\uxy") == "aXyc"
    check replaced("abc", "abc", "\\u&") == "Abc"
    check replaced("ABC", "ABC", "\\l&") == "aBC"
    check replaced("éb", "é", "\\u&") == "Éb"

  test "\\u waits past an empty group":
    check replaced("abc", "(x)?b", "\\u\\1z") == "aZc"

  test "\\U and \\L last until \\E or \\e":
    check replaced("abc", "abc", "\\Uab\\Ecd") == "ABcd"
    check replaced("abc", "abc", "\\Uab\\ecd") == "ABcd"

  test "A change of one character wins over one of all":
    check replaced("ABC", "ABC", "\\u\\L&") == "Abc"
    check replaced("ABC", "ABC", "\\L\\u&") == "Abc"
    check replaced("ABC", "ABC", "\\l\\U&") == "aBC"
    check replaced("abc", "abc", "\\Ux\\lYw") == "XyW"

  test "\\E also drops a change of one character":
    check replaced("abc", "abc", "\\u\\Ex") == "x"

  test "\\r and a typed CR break the line":
    check "a,b".substituteMatches(",", parseReplacement("\\r"), false, true, smRegex) ==
      (@["a", "b"], 1)
    check replaced("a,b", ",", "\r") == "a\nb"
    check replaced("ab", "b", "[&]\\r[&]") == "a[b]\n[b]"

  test "Every match may break the line, at its ends too":
    check replaced("a,b,c", ",", "\\r") == "a\nb\nc"
    check replaced(",a,", ",", "\\r") == "\na\n"
    check replaced("abc", "b*", "\\r") == "\na\nc"

  test "A line break uses up a change of one character, not one of all":
    check replaced("ab", "b", "\\U\\r") == "a\n"
    check replaced("ab", "b", "\\u\\rx") == "a\nx"
    check replaced("xy", "x", "\\Ua\\rb") == "A\nBy"

  test "A backslash keeps a typed CR from breaking the line":
    # Vim keeps the CR in the line; moe's buffer drops it.
    check replaced("a,b", ",", "\\\r") == "a\rb"

  test "\\n is a NUL, as Vim keeps one in a line":
    check replaced("abc", "b", "x\\nx") == "ax\0xc"

  test "A NUL typed on the command line, a line feed there, is a NUL":
    check replaced("a,b", ",", "\n") == "a\0b"
    check replaced("a,b", ",", "\\\n") == "a\0b"

  test "\\b is Ctrl-H":
    check replaced("x", "x", "a\\bc") == "a\x08c"

  test "Groups after undecodable bytes land on their own bytes":
    check replaced("\xffab\xfeab", "(a)(b)", "\\2\\1") == "\xffba\xfeba"
    check ("\xff" & "x\xfea").firstSubstituteMatch("a", false, smRegex) ==
      some(ColumnRange(startCol: 3, endCol: 4))

  test "A group of an undecodable line keeps its bytes":
    check replaced("\xff" & "foo", "(o+)", "[\\1]") == "\xff" & "f[oo]"

  test "A case change keeps the bytes of an undecodable line":
    check replaced("a\xffb\xc3", ".+", "\\U&") == "A\xffB\xc3"
    check replaced("a\xffb", ".+", "\\L&") == "a\xffb"

  test "An undecodable byte uses up a change of one character":
    # Vim 9.2 also makes the byte Latin-1 and changes it (0xFF to U+0178);
    # moe keeps the byte.
    check replaced("\xff" & "ab", ".+", "\\u&") == "\xff" & "ab"

suite "substituteMatches as the last search matched":
  # Expectations are Vim 9.2's :s with that search's pattern.
  proc replaced(line, pattern: string, match: SearchMatch): string =
    let (lines, count) =
      line.substituteMatches(pattern, parseReplacement("#"), false, true, match)
    if count > 0:
      lines.join("\n")
    else:
      line

  test "A word match leaves the word inside another":
    check replaced("foobar foo", "foo", smWord) == "foobar #"

  test "A regex match goes by the regex":
    check replaced("fao f.o fzo", "f.o", smRegex) == "# # #"
    check replaced("日本語", "本.", smRegex) == "日#"

  test "A regex anchors to the start of the line only":
    check replaced("aaa", "^a", smRegex) == "#aa"

  test "An empty match where the one before ended is skipped":
    check replaced("abc", "b*", smRegex) == "#a#c"
    check replaced("ab", "c*", smRegex) == "#a#b"

  test "The line is done once a match reaches its end":
    check replaced("ab", "b*", smRegex) == "#a#"
    check replaced("aaa", "a*", smRegex) == "#"
    check replaced("abc", "$", smRegex) == "abc#"
    check replaced("", "x*", smRegex) == "#"

  test "An undecodable byte keeps its place":
    check replaced("\xff" & "foo", "o+", smRegex) == "\xff" & "f#"

  test "Only the first match unless told":
    check "abab".substituteMatches("b", parseReplacement("#"), false, false, smRegex) ==
      (@["a#ab"], 1)

suite "substitutions":
  test "Each line is read below the lines the ones before it added":
    let b = newTextBuffer("a,b\nc,d\ne")
    var got: seq[(int, seq[string])]
    for s in b.substitutions(0 .. 2, ",", parseReplacement("\\r"), false, true, smRegex):
      got.add (s.line, s.lines)
      check b.replaceLines(s.line, 1, s.lines).isOk
    check got == @[(0, @["a", "b"]), (2, @["c", "d"])]

  test "A line left as it was does not move the next one":
    let b = newTextBuffer("a,b\nc,d")
    var got: seq[int]
    for s in b.substitutions(0 .. 1, ",", parseReplacement("\\r"), false, true, smRegex):
      got.add s.line
    check got == @[0, 1]

suite "Buffer Search - countMatches":
  const Enough = initDuration(seconds = 60)

  proc at(line, column: int): BufferPosition =
    BufferPosition(line: line, column: column)

  test "counts the matches that start at or before the position, as searchcount()":
    let b = newTextBuffer("foo bar\nbaz\nfoo foo\nqux\nfoo\n")
    check b.countMatches(at(0, 0), "foo", Enough).current == 1
    check b.countMatches(at(2, 0), "foo", Enough).current == 2
    check b.countMatches(at(2, 1), "foo", Enough).current == 2
    check b.countMatches(at(3, 0), "foo", Enough).current == 3
    check b.countMatches(at(4, 2), "foo", Enough).current == 4
    check b.countMatches(at(4, 0), "foo", Enough).total == 4

  test "empty and line-end matches count where n stops, as searchcount() in Vim 9.2":
    let b = newTextBuffer("abc\n\nfoo")
    check b.countMatches(at(0, 1), "x*", Enough) ==
      MatchCount(current: 2, total: 7, complete: true)
    check b.countMatches(at(0, 2), "$", Enough) ==
      MatchCount(current: 0, total: 3, complete: true)
    check b.countMatches(at(1, 0), "$", Enough) ==
      MatchCount(current: 2, total: 3, complete: true)
    check b.countMatches(at(1, 0), "^", Enough) ==
      MatchCount(current: 2, total: 3, complete: true)
    check newTextBuffer("xax").countMatches(at(0, 1), "a*", Enough) ==
      MatchCount(current: 2, total: 3, complete: true)
    check newTextBuffer("aaa\nfoo aaaa").countMatches(at(1, 4), "aa", Enough) ==
      MatchCount(current: 2, total: 3, complete: true)

  test "none has started before the first match":
    let b = newTextBuffer("a foo\n")
    check b.countMatches(at(0, 0), "foo", Enough).current == 0

  test "an edit counts again":
    let b = newTextBuffer("foo foo\n")
    check b.countMatches(at(0, 0), "foo", Enough).total == 2
    check b.replaceLines(1, 0, ["foo"]).isOk
    check b.countMatches(at(0, 0), "foo", Enough).total == 3

  test "another buffer, pattern, case or kind of match counts again":
    let
      first = newTextBuffer("Foo foo\n")
      second = newTextBuffer("foo\n")
    check first.countMatches(at(0, 0), "foo", Enough).total == 1
    check second.countMatches(at(0, 0), "foo", Enough).total == 1
    check first.countMatches(at(0, 0), "o", Enough).total == 4
    check first.countMatches(at(0, 0), "foo", Enough, ignorecase = true).total == 2
    check first.countMatches(at(0, 0), "fo.", Enough, match = smLiteral).total == 0

  test "an empty or invalid pattern has no matches":
    let b = newTextBuffer("foo\n")
    check b.countMatches(at(0, 0), "", Enough) == MatchCount(complete: true)
    check b.countMatches(at(0, 0), "(", Enough) == MatchCount(complete: true)

  test "running out of time leaves the count incomplete, until a later count goes on":
    let b = newTextBuffer("foo\nbar\nfoo\n")
    check not b.countMatches(at(2, 0), "foo", DurationZero).complete
    check b.countMatches(at(2, 0), "foo", Enough) ==
      MatchCount(current: 2, total: 2, complete: true)

  test "each buffer keeps its own count":
    let
      first = newTextBuffer("foo foo\n")
      second = newTextBuffer("foo\n")
    check first.countMatches(at(0, 0), "foo", Enough).total == 2
    check second.countMatches(at(0, 0), "foo", DurationZero).total == 0
    check first.countMatches(at(0, 0), "foo", DurationZero) ==
      MatchCount(current: 1, total: 2, complete: true)

  test "the search before is kept along with the one counted":
    let b = newTextBuffer("foo bar\n")
    check b.countMatches(at(0, 0), "foo", Enough).total == 1
    check b.countMatches(at(0, 0), "b", Enough).total == 1
    check b.countMatches(at(0, 0), "foo", DurationZero).complete
    check b.countMatches(at(0, 0), "ba", Enough).total == 1
    check not b.countMatches(at(0, 0), "b", DurationZero).complete

  test "the count follows the position without counting again":
    let b = newTextBuffer("foo foo\nfoo\n")
    check b.countMatches(at(0, 3), "foo", Enough).current == 1
    check b.countMatches(at(0, 4), "foo", Enough).current == 2
    check b.countMatches(at(1, 0), "foo", Enough).current == 3
    check b.countMatches(at(0, 0), "foo", Enough).current == 1

  test "a count out of time goes on from the match it stopped at":
    for (text, pattern, match) in [
      ("foo foo foo\nfoo\n\nfoofoo", "foo", smRegex),
      ("foo foo foo\nfoo\n\nfoofoo", "foo", smLiteral),
      ("abc\n\nfoo", "x*", smRegex),
      ("abc\n\nfoo", "$", smRegex),
      ("aaaa aa\na", "aa", smRegex),
      ("aaaa aa\na", "aa", smLiteral),
      ("foo foobar foo\u0301 foo", "foo", smWord),
      ("e\u0301e e\u0301", "e", smLiteral),
    ]:
      let
        text = repeat(text & " ", 100)
        whole =
          newTextBuffer(text).countMatches(at(1, 0), pattern, Enough, match = match)
        b = newTextBuffer(text)
      var
        count = b.countMatches(at(1, 0), pattern, DurationZero, match = match)
        calls = 1
      check not count.complete
      while not count.complete and calls < 2000:
        count = b.countMatches(at(1, 0), pattern, DurationZero, match = match)
        calls.inc
      check count == whole

  test "a line with many matches is counted however short the time":
    let b = newTextBuffer(repeat("a,", 1000))
    var
      count = b.countMatches(at(0, 0), ",", DurationZero)
      calls = 1
    while not count.complete and calls < 2000:
      count = b.countMatches(at(0, 0), ",", DurationZero)
      calls.inc
    check count == MatchCount(current: 0, total: 1000, complete: true)

  test "a long line is counted in parts between its matches":
    let line = repeat("a", 20_000) & "b"
    let b = newTextBuffer(line)
    check not b.countMatches(at(0, 0), "b", DurationZero, match = smLiteral).complete
    check b.searchCounts[b.recentSearchCount].place.pos in 1 ..< line.len
    var calls = 1
    while not b.countMatches(at(0, 0), "b", DurationZero, match = smLiteral).complete:
      calls.inc
    check calls > 1

  test "the search being typed does not take the last search's place":
    let b = newTextBuffer("foo bar\n")
    check b.countMatches(at(0, 0), "foo", Enough).total == 1
    let keep = SearchCountKey(pattern: "foo")
    check b.countMatches(at(0, 0), "b", Enough, keep = keep).total == 1
    check b.countMatches(at(0, 0), "ba", Enough, keep = keep).total == 1
    check b.countMatches(at(0, 0), "foo", DurationZero).complete
    check not b.countMatches(at(0, 0), "b", DurationZero).complete

  test "only the same pattern searched the same way is kept":
    let
      b = newTextBuffer("foo bar\n")
      keep = SearchCountKey(pattern: "foo", match: smWord)
    check b.countMatches(at(0, 0), "foo", Enough, match = smWord).total == 1
    check b.countMatches(at(0, 0), "foo", Enough, keep = keep).total == 1
    check b.countMatches(at(0, 0), "foo", DurationZero, match = smWord).complete
    check b.countMatches(at(0, 0), "b", Enough, keep = keep).total == 1
    check b.countMatches(at(0, 0), "foo", DurationZero, match = smWord).complete

  test "the count follows the cursor along a line it has counted":
    let b = newTextBuffer("x foo foo foo\nfoo\n")
    check b.countMatches(at(1, 0), "foo", Enough).total == 4
    check b.countMatches(at(0, 12), "foo", Enough).current == 3
    check b.countMatches(at(0, 0), "foo", DurationZero).current == 0
    check b.countMatches(at(0, 2), "foo", DurationZero).current == 1
    check b.countMatches(at(0, 7), "foo", DurationZero).current == 2
    check b.countMatches(at(0, 12), "foo", DurationZero).current == 3

  test "the cursor's line is walked in parts, only as far as its column":
    let b = newTextBuffer("foo\n" & repeat("a,", 1000))
    check b.countMatches(at(0, 0), ",", Enough).total == 1000
    var
      count = b.countMatches(at(1, 9), ",", DurationZero)
      calls = 1
    while not count.complete and calls < 2000:
      count = b.countMatches(at(1, 9), ",", DurationZero)
      calls.inc
    check count == MatchCount(current: 5, total: 1000, complete: true)
    check b.searchCounts[b.recentSearchCount].atStarts.len == 6
    while not count.complete or count.current != 1000:
      count = b.countMatches(at(1, 1999), ",", DurationZero)
      calls.inc
    check calls < 4000
    check b.searchCounts[b.recentSearchCount].atDone

  test "a regex count keeps the line it walks, valid or not":
    let line = repeat("a,\xff", 1000)
    for (pattern, match) in [(",", smRegex), (",", smLiteral)]:
      let
        whole = newTextBuffer(line).countMatches(at(0, 2000), pattern, Enough, match = match)
        b = newTextBuffer(line)
      var count = b.countMatches(at(0, 2000), pattern, DurationZero, match = match)
      while not count.complete:
        count = b.countMatches(at(0, 2000), pattern, DurationZero, match = match)
      check count == whole
      check whole == MatchCount(current: 667, total: 1000, complete: true)
