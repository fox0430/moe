#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import ../src/moepkg/gapbuffer {.all.}

suite "GapBuffer - Basic Operations":
  test "newGapBuffer creates empty buffer":
    let gb = newGapBuffer()
    check gb.len == 1
    check gb[0] == ""

  test "newGapBuffer with text":
    let gb = newGapBuffer("hello\nworld")
    check gb.len == 2
    check gb[0] == "hello"
    check gb[1] == "world"

  test "newGapBuffer with trailing newline":
    let gb = newGapBuffer("hello\nworld\n")
    check gb.len == 3
    check gb[0] == "hello"
    check gb[1] == "world"
    check gb[2] == ""

  test "len returns line count":
    let gb = newGapBuffer("line1\nline2\nline3")
    check gb.len == 3

suite "GapBuffer - Line Access":
  test "getLine returns correct line":
    let gb = newGapBuffer("first\nsecond\nthird")
    check gb.getLine(0) == "first"
    check gb.getLine(1) == "second"
    check gb.getLine(2) == "third"

  test "bracket operator returns correct line":
    let gb = newGapBuffer("alpha\nbeta\ngamma")
    check gb[0] == "alpha"
    check gb[1] == "beta"
    check gb[2] == "gamma"

  test "getLine with invalid index returns empty":
    let gb = newGapBuffer("test")
    check gb.getLine(-1) == ""
    check gb.getLine(10) == ""

suite "GapBuffer - Character Access":
  test "charAtLineCol returns correct character":
    let gb = newGapBuffer("hello\nworld")
    check gb.charAtLineCol(0, 0) == 'h'
    check gb.charAtLineCol(0, 4) == 'o'
    check gb.charAtLineCol(1, 0) == 'w'

  test "double bracket operator returns character":
    let gb = newGapBuffer("test\nline")
    check gb[0][0] == 't'
    check gb[0][3] == 't'
    check gb[1][1] == 'i'

  test "charAtLineCol at line end returns newline":
    let gb = newGapBuffer("first\nsecond")
    check gb.charAtLineCol(0, 5) == '\n'

  test "charAtLineCol with invalid index raises error":
    let gb = newGapBuffer("test")
    expect IndexDefect:
      discard gb.charAtLineCol(-1, 0)
    expect IndexDefect:
      discard gb.charAtLineCol(0, 10)

suite "GapBuffer - Insert Text":
  test "insertIntoLine at beginning of line":
    let gb = newGapBuffer("world")
    gb.insertIntoLine(0, 0, "hello ")
    check gb[0] == "hello world"

  test "insertIntoLine in middle of line":
    let gb = newGapBuffer("helloworld")
    gb.insertIntoLine(0, 5, " ")
    check gb[0] == "hello world"

  test "insertIntoLine at end of line":
    let gb = newGapBuffer("hello")
    gb.insertIntoLine(0, 5, " world")
    check gb[0] == "hello world"

  test "insertIntoLine with invalid col raises error":
    let gb = newGapBuffer("world")
    expect IndexDefect:
      gb.insertIntoLine(0, -5, "hello ")
    expect IndexDefect:
      gb.insertIntoLine(0, 100, "hello ")

  test "insertIntoLine handles newlines in text":
    let gb = newGapBuffer("start")
    gb.insertIntoLine(0, 5, "\nmiddle\nend")
    check gb.len == 1 # insertIntoLine doesn't split lines

suite "GapBuffer - Insert Line":
  test "insertLine at beginning":
    let gb = newGapBuffer("second\nthird")
    gb.insertLine(0, "first")
    check gb.len == 3
    check gb[0] == "first"
    check gb[1] == "second"
    check gb[2] == "third"

  test "insertLine in middle":
    let gb = newGapBuffer("first\nthird")
    gb.insertLine(1, "second")
    check gb.len == 3
    check gb[0] == "first"
    check gb[1] == "second"
    check gb[2] == "third"

  test "insertLine at end":
    let gb = newGapBuffer("first\nsecond")
    gb.insertLine(2, "third")
    check gb.len == 3
    check gb[2] == "third"

suite "GapBuffer - Delete Operations":
  test "deleteLine line":
    let gb = newGapBuffer("first\nsecond\nthird")
    gb.deleteLine(1)
    check gb.len == 2
    check gb[0] == "first"
    check gb[1] == "third"

  test "deleteLine first line":
    let gb = newGapBuffer("delete\nkeep")
    gb.deleteLine(0)
    check gb.len == 1
    check gb[0] == "keep"

  test "deleteLine last line":
    let gb = newGapBuffer("keep\ndelete")
    gb.deleteLine(1)
    check gb.len == 1
    check gb[0] == "keep"

  test "deleteAtLineCol single character":
    let gb = newGapBuffer("hello")
    gb.deleteAtLineCol(0, 1, 1)
    check gb[0] == "hllo"

  test "deleteAtLineCol multiple characters":
    let gb = newGapBuffer("hello world")
    gb.deleteAtLineCol(0, 6, 5)
    check gb[0] == "hello "

  test "deleteAtLineCol from start":
    let gb = newGapBuffer("hello")
    gb.deleteAtLineCol(0, 0, 2)
    check gb[0] == "llo"

suite "GapBuffer - Replace Operations":
  test "replaceLine replaces content":
    let gb = newGapBuffer("old\nmiddle\nold")
    gb.replaceLine(0, "new")
    check gb[0] == "new"
    check gb[1] == "middle"

  test "bracket assignment replaces line":
    let gb = newGapBuffer("old\ndata")
    gb[0] = "new"
    check gb[0] == "new"

  test "double bracket assignment replaces character":
    let gb = newGapBuffer("hello")
    var line = gb[0]
    line[0] = 'H'
    gb[0] = line
    check gb[0] == "Hello"

  test "modifyLineContent modifies in place":
    let gb = newGapBuffer("hello")
    gb.modifyLineContent(
      0,
      proc(s: var string) =
        s.add(" world"),
    )
    check gb[0] == "hello world"

suite "GapBuffer - String Conversion":
  test "toString single line":
    let gb = newGapBuffer("test")
    check $gb == "test\n" # Each line ends with newline

  test "toString multiple lines":
    let gb = newGapBuffer("first\nsecond\nthird")
    check $gb == "first\nsecond\nthird\n" # Each line ends with newline

  test "toString empty buffer":
    let gb = newGapBuffer("")
    check $gb == "\n" # Empty buffer has one empty line with newline

suite "GapBuffer - Clear":
  test "clear resets to empty buffer":
    let gb = newGapBuffer("line1\nline2\nline3")
    gb.clear()
    check gb.len == 1
    check gb[0] == ""

suite "GapBuffer - Iterators":
  test "chars iterator":
    let gb = newGapBuffer("ab\ncd")
    var chars: seq[char] = @[]
    for c in gb.chars:
      chars.add(c)
    check chars == @['a', 'b', '\n', 'c', 'd', '\n'] # Each line ends with newline

  test "lines iterator":
    let gb = newGapBuffer("first\nsecond\nthird")
    var lines: seq[string] = @[]
    for line in gb.lines:
      lines.add(line)
    check lines == @["first", "second", "third"]

suite "GapBuffer - Memory Usage":
  test "estimateMemoryUsage returns positive value":
    let gb = newGapBuffer("test\ndata")
    check gb.estimateMemoryUsage() > 0

  test "getGapInfo returns valid info":
    let gb = newGapBuffer("test")
    let info = gb.getGapInfo()
    check info.start >= 0
    check info.size >= 0
    check info.capacity > 0

suite "GapBuffer - Edge Cases":
  test "single empty line":
    let gb = newGapBuffer("")
    check gb.len == 1
    check gb[0] == ""

  test "multiple empty lines":
    let gb = newGapBuffer("\n\n")
    check gb.len == 2 # "\n\n" = 2 empty lines (newline is terminator, not separator)
    check gb[0] == ""
    check gb[1] == ""

  test "insertIntoLine at boundary positions":
    let gb = newGapBuffer("test")
    gb.insertIntoLine(0, 0, "a")
    check gb[0] == "atest"
    gb.insertIntoLine(0, 5, "b")
    check gb[0] == "atestb"

  test "deleteLine with invalid index raises error":
    let gb = newGapBuffer("test")
    expect IndexDefect:
      gb.deleteLine(-1)
    expect IndexDefect:
      gb.deleteLine(10)
    check gb.len == 1

  test "large buffer operations":
    let gb = newGapBuffer()
    for i in 0 ..< 100:
      gb.insertLine(i, "line " & $i)
    check gb.len == 101
    check gb[50] == "line 50"

suite "GapBuffer - Unicode/Multibyte Support":
  test "insertIntoLine with multibyte characters (Japanese)":
    let gb = newGapBuffer("こんにちは")
    # "こんにちは" = 15 bytes (each char is 3 bytes in UTF-8)
    # Insert at byte position 0
    gb.insertIntoLine(0, 0, "ABC")
    check gb[0] == "ABCこんにちは"

    # Insert at byte position 9 (after 3rd character "ん")
    let gb2 = newGapBuffer("こんにちは")
    gb2.insertIntoLine(0, 9, "XYZ")
    check gb2[0] == "こんにXYZちは"

  test "insertIntoLine with emoji (4-byte UTF-8)":
    let gb = newGapBuffer("Hello 🎉 World")
    # 🎉 is 4 bytes, starts at byte position 6
    # Insert before emoji
    gb.insertIntoLine(0, 6, "[")
    check gb[0] == "Hello [🎉 World"

    # Insert after emoji (6 + 4 = 10)
    let gb2 = newGapBuffer("Hello 🎉 World")
    gb2.insertIntoLine(0, 10, "]")
    check gb2[0] == "Hello 🎉] World"

  test "insertIntoLine at end of multibyte line":
    let gb = newGapBuffer("日本語")
    # "日本語" = 9 bytes
    gb.insertIntoLine(0, 9, "です")
    check gb[0] == "日本語です"

  test "deleteAtLineCol with multibyte characters":
    # Delete single Japanese character (3 bytes)
    let gb = newGapBuffer("あいうえお")
    gb.deleteAtLineCol(0, 3, 3) # Delete "い" (bytes 3-5)
    check gb[0] == "あうえお"

    # Delete emoji (4 bytes)
    let gb2 = newGapBuffer("Start 😀 End")
    gb2.deleteAtLineCol(0, 6, 4) # Delete emoji
    check gb2[0] == "Start  End"

  test "deleteAtLineCol across multibyte boundaries":
    # Delete from ASCII through Japanese
    let gb = newGapBuffer("ABC日本語")
    gb.deleteAtLineCol(0, 2, 4) # Delete "C" + "日" (1 + 3 bytes)
    check gb[0] == "AB本語"

  test "charAtLineCol with multibyte characters":
    let gb = newGapBuffer("こんにちは")
    # First byte of "こ" at byte position 0
    # Note: charAtLineCol returns char (single byte), so for multibyte chars
    # it returns the first byte of the UTF-8 sequence
    let firstByte = gb.charAtLineCol(0, 0)
    # For UTF-8, first byte of "こ" should be 0xE3 (227)
    check firstByte.ord >= 0xE0 # UTF-8 3-byte sequence marker

  test "mixed ASCII, Japanese, and emoji":
    let gb = newGapBuffer("Hello世界🌍")
    # Insert at various byte positions
    gb.insertIntoLine(0, 5, " ") # After "Hello"
    check gb[0] == "Hello 世界🌍"

    let gb2 = newGapBuffer("Hello世界🌍")
    gb2.insertIntoLine(0, 11, " ") # After "世界" (5 + 3 + 3)
    check gb2[0] == "Hello世界 🌍"

  test "deleteAtLineCol with mixed multibyte content":
    let gb = newGapBuffer("Test 日本語 🎌 End")
    # Delete "日本語" (9 bytes starting at position 5)
    gb.deleteAtLineCol(0, 5, 9)
    check gb[0] == "Test  🎌 End"

  test "insertIntoLine with invalid byte position in multibyte char":
    # This should raise an error if we try to insert in the middle of a multibyte char
    # However, GapBuffer doesn't validate UTF-8 boundaries (it's byte-level)
    # So this is actually allowed at GapBuffer level, but would corrupt UTF-8
    # Buffer layer should prevent this
    let gb = newGapBuffer("こんにちは")
    # Inserting at byte 1 (middle of "こ") - GapBuffer allows this
    gb.insertIntoLine(0, 1, "X")
    # Result will be corrupted UTF-8, but GapBuffer doesn't care
    # This demonstrates that Buffer layer MUST ensure byte positions are valid

  test "newGapBuffer with multibyte text preserves content":
    let text = "日本語とEnglishと🎌"
    let gb = newGapBuffer(text)
    check $gb == text & "\n" # Each line ends with newline
    check gb.len == 1
    check gb[0] == text

  test "multiple lines with multibyte characters":
    let gb = newGapBuffer("行1\n行2\n行3")
    check gb.len == 3
    check gb[0] == "行1"
    check gb[1] == "行2"
    check gb[2] == "行3"

  test "insertLine with multibyte content":
    let gb = newGapBuffer("First")
    gb.insertLine(1, "日本語の行")
    gb.insertLine(2, "Emoji 🎉 line")
    check gb.len == 3
    check gb[1] == "日本語の行"
    check gb[2] == "Emoji 🎉 line"

  test "deleteLine with multibyte content":
    let gb = newGapBuffer("ASCII\n日本語\nEmoji🎌\nEnd")
    check gb.len == 4
    gb.deleteLine(1) # Delete Japanese line
    check gb.len == 3
    check gb[0] == "ASCII"
    check gb[1] == "Emoji🎌"
    check gb[2] == "End"

  test "replaceLine with multibyte content":
    let gb = newGapBuffer("Old line")
    gb.replaceLine(0, "新しい行 with emoji 🎉")
    check gb[0] == "新しい行 with emoji 🎉"

  test "toString with multibyte multiline content":
    let gb = newGapBuffer("日本語\nEmoji🌍\nMixed混合")
    check $gb == "日本語\nEmoji🌍\nMixed混合\n" # Each line ends with newline

  test "byte length vs character length awareness":
    let gb = newGapBuffer("abc")
    check gb[0].len == 3 # 3 bytes, 3 chars

    let gb2 = newGapBuffer("あいう")
    check gb2[0].len == 9 # 9 bytes, 3 chars

    let gb3 = newGapBuffer("🎉🎌🌍")
    check gb3[0].len == 12 # 12 bytes (4*3), 3 chars

suite "GapBuffer - Multi-line Deletion":
  test "deleteAtLineCol across two lines (single char + newline)":
    let gb = newGapBuffer("Hello\nWorld")
    # Delete "o" + newline (position 4, count 2)
    gb.deleteAtLineCol(0, 4, 2)
    check gb.len == 1
    check gb[0] == "HellWorld"

  test "deleteAtLineCol across two lines (multiple chars + newline)":
    let gb = newGapBuffer("First\nSecond")
    # Delete "rst" + newline + "Se" (position 2, count 6)
    gb.deleteAtLineCol(0, 2, 6)
    check gb.len == 1
    check gb[0] == "Ficond"

  test "deleteAtLineCol from middle to middle of next line":
    let gb = newGapBuffer("Line1\nLine2\nLine3")
    # Delete from "ne1" + newline + "L" (5 bytes: "ne1"=3, \n=1, "L"=1)
    gb.deleteAtLineCol(0, 2, 5)
    check gb.len == 2
    check gb[0] == "Liine2"
    check gb[1] == "Line3"

  test "deleteAtLineCol spanning three lines":
    let gb = newGapBuffer("AAA\nBBB\nCCC\nDDD")
    # Delete from middle of line 0 to middle of line 2
    # "AA" + newline + "BBB" + newline + "C" = 2 + 1 + 3 + 1 + 1 = 8
    gb.deleteAtLineCol(0, 1, 8)
    check gb.len == 2
    check gb[0] == "ACC"
    check gb[1] == "DDD"

  test "deleteAtLineCol from line start to next line end":
    let gb = newGapBuffer("First\nSecond\nThird")
    # Delete entire first line + newline + entire second line + newline
    # "First" (5) + \n (1) + "Second" (6) + \n (1) = 13
    gb.deleteAtLineCol(0, 0, 13)
    check gb.len == 1
    check gb[0] == "Third"

  test "deleteAtLineCol to end of buffer":
    let gb = newGapBuffer("Line1\nLine2\nLine3")
    # Delete from middle of line 0 to end
    gb.deleteAtLineCol(0, 2, 100) # Count exceeds available
    check gb.len == 1
    check gb[0] == "Li"

  test "deleteAtLineCol entire buffer":
    let gb = newGapBuffer("A\nB\nC")
    # Delete everything
    gb.deleteAtLineCol(0, 0, 100)
    check gb.len == 1
    check gb[0] == ""

  test "deleteAtLineCol with empty lines":
    let gb = newGapBuffer("\n\nContent")
    # Delete two empty lines
    gb.deleteAtLineCol(0, 0, 2)
    check gb.len == 1
    check gb[0] == "Content"

  test "deleteAtLineCol multibyte across lines":
    let gb = newGapBuffer("日本\n語文")
    # Delete "本" (3 bytes) + newline (1) + "語" (3) = 7 bytes
    gb.deleteAtLineCol(0, 3, 7)
    check gb.len == 1
    check gb[0] == "日文"

suite "GapBuffer - Gap Management & Resize":
  test "gap position after sequential insertions":
    let gb = newGapBuffer()
    for i in 0 ..< 5:
      gb.insertLine(i, "line " & $i)
    let info = gb.getGapInfo()
    # After sequential insertions, gap moves to insertion point + 1
    # After inserting at position i, gap is at i+1
    # Last insertion was at position 4, so gap should be at 5
    check info.start == 5

  test "gap position after insertions at beginning":
    let gb = newGapBuffer("initial")
    for i in 0 ..< 5:
      gb.insertLine(0, "line " & $i)
    let info = gb.getGapInfo()
    # After insertions at position 0, gap moves to 0, then after insert it's at 1
    # Since we keep inserting at 0, gap alternates but ends at 1
    check info.start == 1

  test "gap position after mixed insertions":
    let gb = newGapBuffer()
    gb.insertLine(0, "first")
    gb.insertLine(1, "second")
    gb.insertLine(1, "middle") # Insert in middle
    let info = gb.getGapInfo()
    # Gap should be at last insertion point
    check info.start == 2

  test "ensure gap resize on large insertion":
    let gb = newGapBuffer()
    let initialInfo = gb.getGapInfo()
    let initialCapacity = initialInfo.capacity

    # Insert enough lines to trigger resize
    for i in 0 ..< (initialCapacity + 10):
      gb.insertLine(i, "line " & $i)

    let finalInfo = gb.getGapInfo()
    check finalInfo.capacity > initialCapacity

  test "gap size maintained after deletions":
    let gb = newGapBuffer()
    for i in 0 ..< 50:
      gb.insertLine(i, "line " & $i)

    let beforeInfo = gb.getGapInfo()

    # Delete some lines
    for i in 0 ..< 10:
      gb.deleteLine(0)

    let afterInfo = gb.getGapInfo()
    # Gap size should increase after deletions
    check afterInfo.size >= beforeInfo.size + 10

  test "alternating insert/delete maintains consistency":
    let gb = newGapBuffer("initial")
    for i in 0 ..< 20:
      gb.insertLine(0, "line " & $i)
      if i mod 2 == 0 and gb.len > 1:
        gb.deleteLine(1)

    # Check buffer is still consistent
    check gb.len > 0
    for i in 0 ..< gb.len:
      discard gb[i] # Should not crash

suite "GapBuffer - Edge Cases & Stress Tests":
  test "deleteAtLineCol with count = 0":
    let gb = newGapBuffer("test")
    expect IndexDefect:
      gb.deleteAtLineCol(0, 0, 0) # count must be > 0

  test "deleteAtLineCol with negative count":
    let gb = newGapBuffer("test")
    expect IndexDefect:
      gb.deleteAtLineCol(0, 0, -1)

  test "delete from empty line":
    let gb = newGapBuffer("")
    # Empty line has length 0, so col 0 + count 1 will try to delete beyond line
    # This should work but delete nothing or handle gracefully
    # Actually, deleteAtLineCol will try to delete from position 0 with count 1
    # In an empty line (len=0), this should delete the newline to next line if exists
    # But there's only one line, so it will delete nothing or clamp
    gb.deleteAtLineCol(0, 0, 1)
    check gb.len == 1
    check gb[0] == ""

  test "insertIntoLine on empty line":
    let gb = newGapBuffer("")
    gb.insertIntoLine(0, 0, "content")
    check gb[0] == "content"

  test "replaceLine with empty string":
    let gb = newGapBuffer("content")
    gb.replaceLine(0, "")
    check gb[0] == ""

  test "very long line insertion":
    let gb = newGapBuffer()
    let longLine = "x".repeat(10000)
    gb.insertLine(0, longLine)
    check gb[0].len == 10000

  test "many small insertions at same position":
    let gb = newGapBuffer("start")
    for i in 0 ..< 100:
      gb.insertIntoLine(0, 5, "x")
    check gb[0].len == 105 # "start" + 100 'x's

  test "deleteAtLineCol at exact line boundary":
    let gb = newGapBuffer("12345")
    # Delete from position 5 (end of line), should delete newline if multi-line
    let gb2 = newGapBuffer("12345\n67890")
    gb2.deleteAtLineCol(0, 5, 1) # Delete newline
    check gb2.len == 1
    check gb2[0] == "1234567890"

  test "insertLine at every position in sequence":
    let gb = newGapBuffer()
    gb.deleteLine(0) # Remove initial empty line
    gb.insertLine(0, "line0")
    gb.insertLine(0, "line-1") # Insert before
    gb.insertLine(2, "line1") # Insert after
    gb.insertLine(1, "line-0.5") # Insert in middle
    check gb.len == 4
    check gb[0] == "line-1"
    check gb[1] == "line-0.5"
    check gb[2] == "line0"
    check gb[3] == "line1"

  test "stress test: random operations":
    let gb = newGapBuffer()
    # Insert 100 lines
    for i in 0 ..< 100:
      gb.insertLine(i, "line " & $i)

    # Delete every other line
    var i = 0
    while i < gb.len:
      if gb.len > 1:
        gb.deleteLine(i)
      i += 1

    # Insert some more
    for i in 0 ..< 20:
      if gb.len > 0:
        gb.insertLine(min(i, gb.len), "new " & $i)

    # Verify buffer is still consistent
    check gb.len > 0
    discard $gb # Should not crash

suite "GapBuffer - Memory & Performance Characteristics":
  test "memory usage increases with content":
    let gb1 = newGapBuffer()
    let mem1 = gb1.estimateMemoryUsage()

    for i in 0 ..< 100:
      gb1.insertLine(i, "x".repeat(100))

    let mem2 = gb1.estimateMemoryUsage()
    check mem2 > mem1

  test "memory usage after clear is minimal":
    let gb = newGapBuffer()
    for i in 0 ..< 100:
      gb.insertLine(i, "x".repeat(100))

    let memBefore = gb.estimateMemoryUsage()
    gb.clear()
    let memAfter = gb.estimateMemoryUsage()

    # Memory should be significantly reduced (though not to initial due to capacity)
    check memAfter < memBefore
    check gb.len == 1
    check gb[0] == ""

  test "gap info reflects actual buffer state":
    let gb = newGapBuffer()
    let info1 = gb.getGapInfo()
    check info1.start == 1 # After initial empty line
    check info1.capacity >= 16 # MIN_GAP_SIZE

    gb.insertLine(0, "line0")
    let info2 = gb.getGapInfo()
    check info2.start == 1

    gb.insertLine(2, "line2")
    let info3 = gb.getGapInfo()
    check info3.start == 3

suite "GapBuffer - Iterator Edge Cases":
  test "iterate over empty buffer":
    let gb = newGapBuffer("")
    var count = 0
    for line in gb.lines:
      count += 1
    check count == 1 # One empty line

    var charCount = 0
    for ch in gb.chars:
      charCount += 1
    check charCount == 1 # One newline (empty line still has trailing newline)

  test "iterate over single character":
    let gb = newGapBuffer("x")
    var chars: seq[char] = @[]
    for ch in gb.chars:
      chars.add(ch)
    check chars == @['x', '\n'] # Each line ends with newline

  test "iterate over lines with empty lines":
    let gb = newGapBuffer("\n\n")
    var lines: seq[string] = @[]
    for line in gb.lines:
      lines.add(line)
    check lines ==
      @["", ""] # "\n\n" = 2 empty lines (newline is terminator, not separator)
