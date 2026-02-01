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

import std/unittest

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
    check calculateWrapCount(0, 80) == 1

  test "line shorter than max width":
    check calculateWrapCount(40, 80) == 1
    check calculateWrapCount(79, 80) == 1

  test "line exactly at max width":
    check calculateWrapCount(80, 80) == 1

  test "line longer than max width":
    check calculateWrapCount(81, 80) == 2
    check calculateWrapCount(160, 80) == 2
    check calculateWrapCount(161, 80) == 3

  test "very long line":
    check calculateWrapCount(320, 80) == 4
    check calculateWrapCount(400, 80) == 5

  test "small max width":
    check calculateWrapCount(10, 5) == 2
    check calculateWrapCount(15, 5) == 3

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
