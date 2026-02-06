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

import ../src/moepkg/render_utils {.all.}
import ../src/moepkg/buffer
import ../src/moepkg/types

suite "formatLineNumber":
  # formatLineNumber uses: align($(lineIndex + 1), width - 1) & " "
  # So width 3 means: align to 2 chars + trailing space
  test "single digit line number":
    # Line index 0 should display as "1"
    check formatLineNumber(0, 3) == " 1 " # align("1", 2) = " 1", then add " "
    check formatLineNumber(4, 3) == " 5 "

  test "multi digit line number":
    check formatLineNumber(9, 4) == " 10 " # align("10", 3) = " 10"
    check formatLineNumber(99, 5) == " 100 " # align("100", 4) = " 100"
    check formatLineNumber(999, 6) == " 1000 " # align("1000", 5) = " 1000"

  test "alignment with larger width":
    # Width 5 means align to 4 chars + 1 space
    check formatLineNumber(0, 5) == "   1 "
    check formatLineNumber(9, 5) == "  10 "
    check formatLineNumber(99, 5) == " 100 "

  test "edge case - zero index":
    check formatLineNumber(0, 2) == "1 " # align("1", 1) = "1", then add " "

suite "calculateWrapCount":
  test "empty line":
    check calculateWrapCount("", 80, 4) == 1

  test "line shorter than max width":
    check calculateWrapCount("a".repeat(40), 80, 4) == 1
    check calculateWrapCount("a".repeat(79), 80, 4) == 1

  test "line exactly at max width":
    check calculateWrapCount("a".repeat(80), 80, 4) == 1

  test "line longer than max width":
    check calculateWrapCount("a".repeat(81), 80, 4) == 2
    check calculateWrapCount("a".repeat(160), 80, 4) == 2
    check calculateWrapCount("a".repeat(161), 80, 4) == 3

  test "very long line":
    check calculateWrapCount("a".repeat(320), 80, 4) == 4
    check calculateWrapCount("a".repeat(400), 80, 4) == 5

  test "small max width":
    check calculateWrapCount("a".repeat(10), 5, 4) == 2
    check calculateWrapCount("a".repeat(15), 5, 4) == 3

  test "line with tabs":
    # Tab at start of 10-col line: tab takes 4 cols, leaves 6 cols for text
    # "\thello" = 4 + 5 = 9 cols, fits in 10
    check calculateWrapCount("\thello", 10, 4) == 1
    # "\thelloworld" = 4 + 10 = 14 cols, wraps at 10
    check calculateWrapCount("\thelloworld", 10, 4) == 2

  test "line with wide characters":
    # Each CJK character is 2 display columns
    # 5 CJK chars = 10 cols, fits in 10
    check calculateWrapCount("あいうえお", 10, 4) == 1
    # 6 CJK chars = 12 cols, wraps at 10
    check calculateWrapCount("あいうえおか", 10, 4) == 2

suite "displayWidthSubstrWithTabs":
  test "ASCII only - fits in maxWidth":
    let (chars, width) = displayWidthSubstrWithTabs("hello", 0, 10, 4)
    check chars == 5
    check width == 5

  test "ASCII only - exceeds maxWidth":
    let (chars, width) = displayWidthSubstrWithTabs("hello world", 0, 5, 4)
    check chars == 5
    check width == 5

  test "startChar offset":
    # "world" starting from char 6
    let (chars, width) = displayWidthSubstrWithTabs("hello world", 6, 10, 4)
    check chars == 5 # "world"
    check width == 5

  test "tab at segment start":
    # Tab at position 0 expands to 4 columns (tabStop=4)
    let (chars, width) = displayWidthSubstrWithTabs("\thello", 0, 10, 4)
    check chars == 6 # tab + "hello" = 4+5=9 cols, fits in 10
    check width == 9

  test "tab at segment start - tight fit":
    let (chars, width) = displayWidthSubstrWithTabs("\thello", 0, 4, 4)
    check chars == 1 # only the tab fits (4 cols == maxWidth)
    check width == 4

  test "tab expansion relative to segment start":
    # When starting mid-line, tab expansion is relative to segment start
    # "ab\tcd" starting from char 2 (the tab): tab at col 0 of segment = 4 cols
    let (chars, width) = displayWidthSubstrWithTabs("ab\tcd", 2, 10, 4)
    check chars == 3 # tab + "cd" = 4+2=6 cols
    check width == 6

  test "wide characters":
    # Each CJK char is 2 cols; maxWidth=5 fits 2 chars (4 cols), not 3 (6 cols)
    let (chars, width) = displayWidthSubstrWithTabs("あいう", 0, 5, 4)
    check chars == 2
    check width == 4

  test "wide character at boundary":
    # maxWidth=5, "aaaa" = 4 cols, next is "あ" (2 cols) => 6 > 5, won't fit
    let (chars, width) = displayWidthSubstrWithTabs("aaaaあ", 0, 5, 4)
    check chars == 4
    check width == 4

  test "empty string":
    let (chars, width) = displayWidthSubstrWithTabs("", 0, 10, 4)
    check chars == 0
    check width == 0

  test "maxWidth zero or one":
    # Single ASCII char fits in width 1
    let (chars, width) = displayWidthSubstrWithTabs("a", 0, 1, 4)
    check chars == 1
    check width == 1

  test "tab with tabStop 8":
    let (chars, width) = displayWidthSubstrWithTabs("\thello", 0, 10, 8)
    check chars == 3 # tab(8) + "he" = 10
    check width == 10

suite "screenXToCharIndex":
  test "ASCII at position 0":
    check screenXToCharIndex("hello", 0, 0, 4) == 0

  test "ASCII at position 3":
    check screenXToCharIndex("hello", 0, 3, 4) == 3

  test "past end of string":
    check screenXToCharIndex("hi", 0, 10, 4) == 2

  test "with startChar offset":
    # "world" starting from char 6; displayX=2 => 2 chars into "world"
    check screenXToCharIndex("hello world", 6, 2, 4) == 2

  test "tab character":
    # "\thello": tab expands to 4 cols. displayX=3 is within the tab
    check screenXToCharIndex("\thello", 0, 3, 4) == 0
    # displayX=4 is right after tab, on 'h'
    check screenXToCharIndex("\thello", 0, 4, 4) == 1

  test "wide characters":
    # "あいう": あ=cols 0-1, い=cols 2-3, う=cols 4-5
    check screenXToCharIndex("あいう", 0, 0, 4) == 0
    check screenXToCharIndex("あいう", 0, 1, 4) == 0
    check screenXToCharIndex("あいう", 0, 2, 4) == 1
    check screenXToCharIndex("あいう", 0, 4, 4) == 2

  test "empty string":
    check screenXToCharIndex("", 0, 5, 4) == 0

suite "cursorWrapPosition":
  test "no wrap - cursor in first segment":
    let (wrapLine, col) = cursorWrapPosition("hello", 3, 10, 4)
    check wrapLine == 0
    check col == 3

  test "wrap - cursor in second segment":
    # "abcdefghij" (10 chars), maxWidth=5
    # Segment 0: "abcde" (chars 0-4, 5 cols)
    # Segment 1: "fghij" (chars 5-9, 5 cols)
    let (wrapLine, col) = cursorWrapPosition("abcdefghij", 7, 5, 4)
    check wrapLine == 1
    check col == 2 # 'h' is 2 cols into second segment

  test "cursor at segment boundary":
    # "abcdefghij", maxWidth=5
    # Cursor at char 5 ('f') should be at start of segment 1
    let (wrapLine, col) = cursorWrapPosition("abcdefghij", 5, 5, 4)
    check wrapLine == 1
    check col == 0

  test "cursor at last char of first segment":
    let (wrapLine, col) = cursorWrapPosition("abcdefghij", 4, 5, 4)
    check wrapLine == 0
    check col == 4

  test "wide char at wrap boundary":
    # maxWidth=5: "aaaa" = 4 cols, "あ" (2 cols) doesn't fit => seg0 = "aaaa" (4 cols)
    # seg1 starts at char 4 = "あbc"
    let (wrapLine, col) = cursorWrapPosition("aaaaあbc", 4, 5, 4)
    check wrapLine == 1
    check col == 0 # "あ" is at the start of segment 1

  test "wide char at wrap boundary - col in second segment":
    # seg1 = "あbc": cursor at char 5 ('b') = displayCol 2
    let (wrapLine, col) = cursorWrapPosition("aaaaあbc", 5, 5, 4)
    check wrapLine == 1
    check col == 2

  test "tab causes early wrap":
    # maxWidth=6, "\tabcdefg": tab=4 cols, then "ab"=2 cols fills 6.
    # seg0 = "\tab" (3 chars, 6 cols), seg1 = "cdefg"
    let (wrapLine0, col0) = cursorWrapPosition("\tabcdefg", 1, 6, 4) # 'a' in seg0
    check wrapLine0 == 0
    check col0 == 4 # after tab (4 cols)

    let (wrapLine1, col1) = cursorWrapPosition("\tabcdefg", 3, 6, 4) # 'c' in seg1
    check wrapLine1 == 1
    check col1 == 0

  test "empty string":
    let (wrapLine, col) = cursorWrapPosition("", 0, 10, 4)
    check wrapLine == 0
    check col == 0

  test "single character":
    let (wrapLine, col) = cursorWrapPosition("a", 0, 10, 4)
    check wrapLine == 0
    check col == 0

  test "three segments":
    # 15 chars, maxWidth=5 => 3 segments
    let (wrapLine, col) = cursorWrapPosition("abcdefghijklmno", 12, 5, 4)
    check wrapLine == 2
    check col == 2 # 'm' is at col 2 of segment 2

suite "displayWidthWithTabs":
  test "empty string":
    check displayWidthWithTabs("", 4) == 0

  test "simple text without tabs":
    check displayWidthWithTabs("hello", 4) == 5
    check displayWidthWithTabs("abc", 8) == 3

  test "tab at beginning":
    check displayWidthWithTabs("\t", 4) == 4
    check displayWidthWithTabs("\t", 8) == 8

  test "tab in middle":
    check displayWidthWithTabs("ab\t", 4) == 4 # "ab" = 2, tab fills to 4
    check displayWidthWithTabs("abc\t", 4) == 4 # "abc" = 3, tab fills to 4
    check displayWidthWithTabs("abcd\t", 4) == 8 # "abcd" = 4, tab fills to 8

  test "multiple tabs":
    check displayWidthWithTabs("\t\t", 4) == 8
    check displayWidthWithTabs("a\tb\t", 4) == 8 # "a" = 1, tab to 4, "b" = 5, tab to 8

  test "unicode characters":
    # Full-width characters take 2 columns
    check displayWidthWithTabs("日本", 4) == 4

  test "unicode with tabs":
    check displayWidthWithTabs("日\t", 4) == 4 # "日" = 2, tab fills to 4

  test "tab stop edge cases":
    # When tabStop is 0 or negative, should default to 1
    check displayWidthWithTabs("\t", 0) == 1
    check displayWidthWithTabs("\t", -1) == 1

suite "displayWidthUpToWithTabs":
  test "empty string":
    check displayWidthUpToWithTabs("", 0, 4) == 0

  test "simple text":
    check displayWidthUpToWithTabs("hello", 3, 4) == 3 # "hel"
    check displayWidthUpToWithTabs("hello", 5, 4) == 5

  test "with tab at beginning":
    check displayWidthUpToWithTabs("\thello", 1, 4) == 4 # Just the tab
    check displayWidthUpToWithTabs("\thello", 2, 4) == 5 # Tab + "h"

  test "tab in middle":
    check displayWidthUpToWithTabs("ab\tc", 2, 4) == 2 # "ab"
    check displayWidthUpToWithTabs("ab\tc", 3, 4) == 4 # "ab" + tab
    check displayWidthUpToWithTabs("ab\tc", 4, 4) == 5 # "ab" + tab + "c"

  test "charPos exceeds string length":
    check displayWidthUpToWithTabs("abc", 10, 4) == 3

  test "negative charPos":
    check displayWidthUpToWithTabs("abc", -1, 4) == 0

  test "unicode characters":
    check displayWidthUpToWithTabs("日本語", 2, 4) == 4 # "日本" = 4 columns

  test "tab stop edge cases":
    check displayWidthUpToWithTabs("\t", 1, 0) == 1
    check displayWidthUpToWithTabs("\t", 1, -1) == 1

suite "findTrailingSpaceStart":
  test "empty string":
    check findTrailingSpaceStart("") == 0

  test "no trailing spaces":
    check findTrailingSpaceStart("hello") == 5
    check findTrailingSpaceStart("abc") == 3

  test "trailing regular spaces":
    check findTrailingSpaceStart("hello   ") == 5
    check findTrailingSpaceStart("a ") == 1

  test "trailing tabs":
    check findTrailingSpaceStart("hello\t") == 5
    check findTrailingSpaceStart("hello\t\t") == 5

  test "trailing full-width spaces":
    check findTrailingSpaceStart("hello\u3000") == 5
    check findTrailingSpaceStart("hello\u3000\u3000") == 5

  test "mixed trailing whitespace":
    check findTrailingSpaceStart("hello \t\u3000") == 5

  test "all whitespace":
    check findTrailingSpaceStart("   ") == 0
    check findTrailingSpaceStart("\t\t") == 0
    check findTrailingSpaceStart("\u3000") == 0

  test "internal spaces preserved":
    check findTrailingSpaceStart("hello world") == 11
    check findTrailingSpaceStart("hello world  ") == 11

  test "unicode text":
    check findTrailingSpaceStart("日本語") == 3
    check findTrailingSpaceStart("日本語  ") == 3

proc makeBufferWithLines(count: int): TextBuffer =
  ## Helper to create a buffer with multiple lines
  var content = ""
  for i in 0 ..< count:
    if i > 0:
      content.add("\n")
    content.add("line " & $i)
  newTextBuffer(content)

suite "calculateLineNumOffset":
  test "empty buffer with line numbers":
    # Even empty buffer has 1 line (empty line), so len = 1
    # 1 digit + 1 spacer = 2
    let buf = newTextBuffer()
    check calculateLineNumOffset(buf, true) == 2

  test "empty buffer without line numbers":
    let buf = newTextBuffer()
    check calculateLineNumOffset(buf, false) == 0

  test "buffer with lines - line numbers shown":
    let buf = makeBufferWithLines(10)
    # 10 lines = 2 digits + 1 spacer = 3
    check calculateLineNumOffset(buf, true) == 3

  test "buffer with lines - line numbers hidden":
    let buf = makeBufferWithLines(10)
    check calculateLineNumOffset(buf, false) == 0

  test "buffer with many lines":
    let buf = makeBufferWithLines(100)
    # 100 lines = 3 digits + 1 spacer = 4
    check calculateLineNumOffset(buf, true) == 4

  test "buffer with 1000+ lines":
    let buf = makeBufferWithLines(1000)
    # 1000 lines = 4 digits + 1 spacer = 5
    check calculateLineNumOffset(buf, true) == 5

suite "findMaxBottomY":
  test "empty windows list":
    let windows: seq[EditorWindow] = @[]
    check findMaxBottomY(windows) == 0

  test "single window":
    var buf = newTextBuffer()
    let win = EditorWindow(buffer: buf, viewport: ViewPort(y: 0, height: 20))
    check findMaxBottomY(@[win]) == 20

  test "multiple windows - find max":
    var buf = newTextBuffer()
    let win1 = EditorWindow(buffer: buf, viewport: ViewPort(y: 0, height: 10))
    let win2 = EditorWindow(buffer: buf, viewport: ViewPort(y: 10, height: 15))
    let win3 = EditorWindow(buffer: buf, viewport: ViewPort(y: 0, height: 20))
    check findMaxBottomY(@[win1, win2, win3]) == 25 # win2: 10 + 15 = 25

  test "windows at same position":
    var buf = newTextBuffer()
    let win1 = EditorWindow(buffer: buf, viewport: ViewPort(y: 5, height: 10))
    let win2 = EditorWindow(buffer: buf, viewport: ViewPort(y: 5, height: 12))
    check findMaxBottomY(@[win1, win2]) == 17 # 5 + 12 = 17

suite "calculateWindowStatusLineY":
  test "bottom window":
    var buf = newTextBuffer()
    let win = EditorWindow(buffer: buf, viewport: ViewPort(y: 0, height: 24))
    # Bottom window: y + height - 2
    check calculateWindowStatusLineY(win, true) == 22

  test "non-bottom window":
    var buf = newTextBuffer()
    let win = EditorWindow(buffer: buf, viewport: ViewPort(y: 0, height: 12))
    # Non-bottom window: y + height - 1
    check calculateWindowStatusLineY(win, false) == 11

  test "window with offset":
    var buf = newTextBuffer()
    let win = EditorWindow(buffer: buf, viewport: ViewPort(y: 10, height: 15))
    check calculateWindowStatusLineY(win, true) == 23 # 10 + 15 - 2 = 23
    check calculateWindowStatusLineY(win, false) == 24 # 10 + 15 - 1 = 24
