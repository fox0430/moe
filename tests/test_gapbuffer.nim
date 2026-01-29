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
    # In the editor design, trailing newlines are NOT stored as empty lines
    # Instead, they're tracked by the endOfLine flag in TextBuffer
    # The buffer stores lines as separators, not terminators
    let gb = newGapBuffer("hello\nworld\n")
    check gb.len == 2 # Two lines: "hello" and "world"
    check gb[0] == "hello"
    check gb[1] == "world"

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
    check $gb == "test" # Last line has no trailing newline

  test "toString multiple lines":
    let gb = newGapBuffer("first\nsecond\nthird")
    check $gb == "first\nsecond\nthird" # Last line has no trailing newline

  test "toString empty buffer":
    let gb = newGapBuffer("")
    check $gb == "" # Empty buffer returns empty string

suite "GapBuffer - Clear":
  test "clear resets to empty buffer":
    let gb = newGapBuffer("line1\nline2\nline3")
    gb.clear()
    check gb.len == 1
    check gb[0] == ""

suite "GapBuffer - Iterators":
  test "chars iterator":
    # POSIX semantics: newlines between lines, no trailing newline for non-empty last line
    let gb = newGapBuffer("ab\ncd")
    var chars: seq[char] = @[]
    for c in gb.chars:
      chars.add(c)
    check chars == @['a', 'b', '\n', 'c', 'd'] # Consistent with $ operator

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
    check $gb == text # Last line has no trailing newline
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
    check $gb == "日本語\nEmoji🌍\nMixed混合" # Last line has no trailing newline

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
    # Empty buffer = 1 empty line, no characters emitted (consistent with $ returning "")
    check charCount == 0

  test "iterate over single character":
    # POSIX semantics: single non-empty line has no trailing newline
    let gb = newGapBuffer("x")
    var chars: seq[char] = @[]
    for ch in gb.chars:
      chars.add(ch)
    check chars == @['x'] # Consistent with $ operator

  test "iterate over lines with empty lines":
    let gb = newGapBuffer("\n\n")
    var lines: seq[string] = @[]
    for line in gb.lines:
      lines.add(line)
    check lines ==
      @["", ""] # "\n\n" = 2 empty lines (newline is terminator, not separator)

# Low-level Linear Index API Tests

suite "GapBuffer - Linear Index Insert":
  test "insert into empty buffer":
    let gb = newGapBuffer()
    check gb.lineCount() == 1
    check gb.getLine(0) == ""

    gb.insert(0, "Hello")
    check gb.lineCount() == 1
    check gb.getLine(0) == "Hello"
    check $gb == "Hello"

  test "insert at beginning of line":
    let gb = newGapBuffer("World")
    gb.insert(0, "Hello ")
    check $gb == "Hello World"
    check gb.getLine(0) == "Hello World"

  test "insert in middle of line":
    let gb = newGapBuffer("HWorld")
    gb.insert(1, "ello ")
    check $gb == "Hello World"

  test "insert at end of line":
    let gb = newGapBuffer("Hello")
    gb.insert(5, " World")
    check $gb == "Hello World"

  test "insert beyond buffer end":
    let gb = newGapBuffer("Hello")
    gb.insert(100, "World")
    # Position is clamped to end, appends to same line
    check gb.lineCount() == 1
    check $gb == "HelloWorld"

  test "insert single newline in empty buffer":
    let gb = newGapBuffer()
    gb.insert(0, "\n")
    check gb.lineCount() == 2
    check gb.getLine(0) == ""
    check gb.getLine(1) == ""

  test "insert single newline at line start":
    let gb = newGapBuffer("Hello")
    gb.insert(0, "\n")
    check gb.lineCount() == 2
    check gb.getLine(0) == ""
    check gb.getLine(1) == "Hello"
    check $gb == "\nHello"

  test "insert single newline in line middle":
    let gb = newGapBuffer("HelloWorld")
    gb.insert(5, "\n")
    check gb.lineCount() == 2
    check gb.getLine(0) == "Hello"
    check gb.getLine(1) == "World"
    check $gb == "Hello\nWorld"

  test "insert multiple consecutive newlines":
    let gb = newGapBuffer("Text")
    gb.insert(4, "\n\n\n")
    check gb.lineCount() == 4
    check gb.getLine(0) == "Text"
    check gb.getLine(1) == ""
    check gb.getLine(2) == ""
    check gb.getLine(3) == ""

  test "insert text with newline at start":
    let gb = newGapBuffer("World")
    gb.insert(0, "Hello\n")
    check gb.lineCount() == 2
    check gb.getLine(0) == "Hello"
    check gb.getLine(1) == "World"
    check $gb == "Hello\nWorld"

  test "insert multi-line text":
    let gb = newGapBuffer("Start")
    gb.insert(5, "\nLine1\nLine2\nLine3")
    check gb.lineCount() == 4
    check gb.getLine(0) == "Start"
    check gb.getLine(1) == "Line1"
    check gb.getLine(2) == "Line2"
    check gb.getLine(3) == "Line3"

  test "insert multi-line text in middle of line":
    let gb = newGapBuffer("StartEnd")
    gb.insert(5, "\nMiddle\n")
    check gb.lineCount() == 3
    check gb.getLine(0) == "Start"
    check gb.getLine(1) == "Middle"
    check gb.getLine(2) == "End"
    check $gb == "Start\nMiddle\nEnd"

  test "sequential insertions":
    let gb = newGapBuffer()

    gb.insert(0, "A")
    check $gb == "A"

    gb.insert(1, "B")
    check $gb == "AB"

    gb.insert(2, "\n")
    check gb.lineCount() == 2

    gb.insert(3, "C")
    check $gb == "AB\nC"

    gb.insert(4, "D")
    check $gb == "AB\nCD"

  test "insert character method":
    let gb = newGapBuffer()
    gb.insert(0, 'H')
    gb.insert(1, 'i')
    check $gb == "Hi"

  test "insert preserves content after gap":
    let gb = newGapBuffer("Line1\nLine2\nLine3")
    # Insert in first line, should preserve lines 2 and 3
    gb.insert(3, "XXX")
    check gb.lineCount() == 3
    check gb.getLine(0) == "LinXXXe1"
    check gb.getLine(1) == "Line2"
    check gb.getLine(2) == "Line3"

  test "insert with newline preserves suffix":
    let gb = newGapBuffer("HelloWorld")
    gb.insert(5, "\n")
    check gb.getLine(0) == "Hello"
    check gb.getLine(1) == "World"
    # Verify by char access
    check gb.charAt(0) == 'H'
    check gb.charAt(5) == '\n'
    check gb.charAt(6) == 'W'

  test "empty string insertion does nothing":
    let gb = newGapBuffer("Test")
    gb.insert(2, "")
    check $gb == "Test"
    check gb.lineCount() == 1

suite "GapBuffer - Linear Index Delete":
  test "delete single character from line":
    let gb = newGapBuffer("Hello")
    gb.delete(1, 1) # Delete 'e'
    check $gb == "Hllo"
    check gb.lineCount() == 1

  test "delete from beginning of line":
    let gb = newGapBuffer("Hello")
    gb.delete(0, 2) # Delete "He"
    check $gb == "llo"

  test "delete from end of line":
    let gb = newGapBuffer("Hello")
    gb.delete(3, 2) # Delete "lo"
    check $gb == "Hel"

  test "delete entire line content":
    let gb = newGapBuffer("Hello")
    gb.delete(0, 5)
    check $gb == ""
    check gb.lineCount() == 1 # Line still exists but empty

  test "delete newline character":
    let gb = newGapBuffer("Hello\nWorld")
    check gb.lineCount() == 2

    gb.delete(5, 1) # Delete the newline
    check $gb == "HelloWorld"
    check gb.lineCount() == 1

  test "delete across two lines":
    let gb = newGapBuffer("Hello\nWorld")
    gb.delete(3, 5) # Delete "lo\nWo"
    check $gb == "Helrld"
    check gb.lineCount() == 1

  test "delete entire first line including newline":
    let gb = newGapBuffer("Line1\nLine2\nLine3")
    gb.delete(0, 6) # Delete "Line1\n"
    check $gb == "Line2\nLine3"
    check gb.lineCount() == 2
    check gb.getLine(0) == "Line2"

  test "delete middle line completely":
    let gb = newGapBuffer("Line1\nLine2\nLine3")
    gb.delete(6, 6) # Delete "Line2\n"
    check $gb == "Line1\nLine3"
    check gb.lineCount() == 2

  test "delete across three lines":
    let gb = newGapBuffer("Line1\nLine2\nLine3")
    gb.delete(3, 11) # Delete "e1\nLine2\nLi"
    check $gb == "Linne3"
    check gb.lineCount() == 1

  test "delete from middle to end":
    let gb = newGapBuffer("Hello\nWorld\nTest")
    gb.delete(7, 100) # Delete from 'o' in World to end
    check $gb == "Hello\nW"
    check gb.lineCount() == 2

  test "delete beyond buffer does nothing extra":
    let gb = newGapBuffer("Test")
    gb.delete(2, 100) # Delete from position 2 to end
    check $gb == "Te"

  test "delete with count 0 does nothing":
    let gb = newGapBuffer("Hello")
    gb.delete(2, 0)
    check $gb == "Hello"

  test "delete with negative count does nothing":
    let gb = newGapBuffer("Hello")
    gb.delete(2, -5)
    check $gb == "Hello"

  test "delete from invalid position does nothing":
    let gb = newGapBuffer("Hello")
    gb.delete(100, 5)
    check $gb == "Hello"

  test "delete empty lines":
    let gb = newGapBuffer("A\n\nB")
    check gb.lineCount() == 3

    gb.delete(2, 1) # Delete second newline
    check $gb == "A\nB"
    check gb.lineCount() == 2

  test "sequential deletes":
    let gb = newGapBuffer("ABCDEF")

    gb.delete(2, 1) # Delete 'C' -> "ABDEF"
    check $gb == "ABDEF"

    gb.delete(2, 1) # Delete 'D' -> "ABEF"
    check $gb == "ABEF"

    gb.delete(1, 2) # Delete 'BE' -> "AF"
    check $gb == "AF"

  test "delete and insert combination":
    let gb = newGapBuffer("Hello World")

    gb.delete(5, 6) # Delete " World" -> "Hello"
    check $gb == "Hello"

    gb.insert(5, "\nNim") # Insert newline and "Nim"
    check $gb == "Hello\nNim"
    check gb.lineCount() == 2

  test "delete preserves content before and after":
    let gb = newGapBuffer("AAA\nBBB\nCCC\nDDD")

    gb.delete(8, 4) # Delete "CCC\n"
    check gb.lineCount() == 3
    check gb.getLine(0) == "AAA"
    check gb.getLine(1) == "BBB"
    check gb.getLine(2) == "DDD"

  test "delete entire buffer except last line":
    let gb = newGapBuffer("A\nB\nC")
    gb.delete(0, 4) # Delete "A\nB\n"
    check $gb == "C"
    check gb.lineCount() == 1

  test "delete in empty buffer does nothing":
    let gb = newGapBuffer()
    gb.delete(0, 5)
    check gb.lineCount() == 1
    check $gb == ""

  test "delete single char with charAt verification":
    let gb = newGapBuffer("ABCDE")
    check gb.charAt(2) == 'C'

    gb.delete(2, 1)
    check gb.charAt(2) == 'D'
    check $gb == "ABDE"

  test "delete newline merges lines correctly":
    let gb = newGapBuffer("First\nSecond")
    let origLineCount = gb.lineCount()
    check origLineCount == 2

    gb.delete(5, 1) # Delete newline at position 5
    check gb.lineCount() == 1
    check gb.getLine(0) == "FirstSecond"

suite "GapBuffer - charAt and charLen":
  test "charLen of empty buffer":
    let gb = newGapBuffer()
    check gb.charLen == 0

  test "charLen of single line":
    let gb = newGapBuffer("Hello")
    check gb.charLen == 5

  test "charLen of multiple lines":
    let gb = newGapBuffer("Hello\nWorld")
    check gb.charLen == 11 # 5 + 1 (newline) + 5

  test "charAt access":
    let gb = newGapBuffer("ABCDE")
    check gb.charAt(0) == 'A'
    check gb.charAt(2) == 'C'
    check gb.charAt(4) == 'E'

  test "charAt at line boundaries":
    let gb = newGapBuffer("AB\nCD")
    # Positions: A(0) B(1) \n(2) C(3) D(4)
    check gb.charAt(0) == 'A'
    check gb.charAt(1) == 'B'
    check gb.charAt(2) == '\n'
    check gb.charAt(3) == 'C'
    check gb.charAt(4) == 'D'

  test "charAt beyond end raises error":
    let gb = newGapBuffer("Test")
    expect(IndexDefect):
      discard gb.charAt(100)

  test "charAt on empty buffer raises error":
    let gb = newGapBuffer()
    expect(IndexDefect):
      discard gb.charAt(0)

suite "GapBuffer - Substring":
  test "substring basic extraction":
    let gb = newGapBuffer("ABCDEFGH")
    check gb.substring(0, 3) == "ABC"
    check gb.substring(3, 3) == "DEF"
    check gb.substring(5, 3) == "FGH"

  test "substring cross-line extraction":
    let gb = newGapBuffer("AB\nCD\nEF")
    # Positions: A(0) B(1) \n(2) C(3) D(4) \n(5) E(6) F(7)
    check gb.substring(1, 4) == "B\nCD"
    check gb.substring(0, 8) == "AB\nCD\nEF"

  test "substring boundary cases":
    let gb = newGapBuffer("Test")
    check gb.substring(0, 0) == ""
    check gb.substring(0, 100) == "Test"
    check gb.substring(100, 5) == ""
    check gb.substring(2, -5) == ""

  test "substring full buffer":
    let gb = newGapBuffer("ABCDE")
    check gb.substring(0, 5) == "ABCDE"

  test "substring partial from start":
    let gb = newGapBuffer("ABCDE")
    check gb.substring(0, 3) == "ABC"

  test "substring partial from end":
    let gb = newGapBuffer("ABCDE")
    check gb.substring(2, 3) == "CDE"

  test "substring beyond end":
    let gb = newGapBuffer("ABCDE")
    check gb.substring(3, 100) == "DE"

  test "substring start beyond end":
    let gb = newGapBuffer("ABCDE")
    check gb.substring(100, 5) == ""

suite "GapBuffer - Slice Operator":
  test "slice basic access":
    let gb = newGapBuffer("ABCDEFGH")
    check gb[0 .. 2] == "ABC"
    check gb[3 .. 5] == "DEF"
    check gb[6 .. 7] == "GH"

  test "slice with newlines":
    let gb = newGapBuffer("AB\nCD")
    # Positions: A(0) B(1) \n(2) C(3) D(4)
    check gb[0 .. 1] == "AB"
    check gb[1 .. 3] == "B\nC"
    check gb[2 .. 4] == "\nCD"

  test "slice edge cases":
    let gb = newGapBuffer("Test")
    check gb[0 .. 0] == "T"
    check gb[3 .. 3] == "t"
    check gb[5 .. 10] == "" # Start beyond end

suite "GapBuffer - indexToLineCol":
  test "indexToLineCol single line":
    let gb = newGapBuffer("Hello")
    check gb.indexToLineCol(0) == (0, 0)
    check gb.indexToLineCol(2) == (0, 2)
    check gb.indexToLineCol(5) == (0, 5) # End of line

  test "indexToLineCol multiple lines":
    let gb = newGapBuffer("AB\nCD")
    # Positions: A(0) B(1) \n(2) C(3) D(4)
    check gb.indexToLineCol(0) == (0, 0) # 'A'
    check gb.indexToLineCol(1) == (0, 1) # 'B'
    check gb.indexToLineCol(2) == (0, 2) # newline position
    check gb.indexToLineCol(3) == (1, 0) # 'C'
    check gb.indexToLineCol(4) == (1, 1) # 'D'

  test "indexToLineCol negative index":
    let gb = newGapBuffer("Test")
    check gb.indexToLineCol(-1) == (-1, -1)

suite "GapBuffer - findLineStart":
  test "findLineStart single line":
    let gb = newGapBuffer("Hello")
    check gb.findLineStart(0) == 0

  test "findLineStart multiple lines":
    let gb = newGapBuffer("Hello\nWorld\nTest")
    check gb.findLineStart(0) == 0
    check gb.findLineStart(1) == 6 # After "Hello\n"
    check gb.findLineStart(2) == 12 # After "Hello\nWorld\n"

  test "findLineStart invalid line":
    let gb = newGapBuffer("Test")
    check gb.findLineStart(-1) == -1
    check gb.findLineStart(100) == -1

suite "GapBuffer - Gap Management (Low-level)":
  test "gap expansion on many insertions":
    let gb = newGapBuffer()
    let initialGapInfo = gb.getGapInfo()

    # Insert many lines to force gap expansion
    for i in 0 ..< 100:
      gb.insertLine(i, "Line " & $i)

    let finalGapInfo = gb.getGapInfo()

    # Verify all lines are intact
    check gb.lineCount() == 101 # 100 inserted + 1 initial
    for i in 0 ..< 100:
      check gb.getLine(i) == "Line " & $i

  test "content integrity after gap moves":
    let gb = newGapBuffer("Line1\nLine2\nLine3\nLine4\nLine5")

    # Insert at different positions to force gap movement
    gb.insert(0, "A") # Gap moves to line 0
    gb.insert(gb.charLen, "Z") # Gap moves to end

    # Verify content is still correct
    check gb.getLine(0) == "ALine1"
    check gb.getLine(4) == "Line5Z"

  test "alternating insert positions":
    let gb = newGapBuffer("AAAA\nBBBB\nCCCC")

    # Insert at first line
    gb.insert(2, "1")
    check gb.getLine(0) == "AA1AA"

    # Insert at last line (line number is gb.lineCount - 1)
    let lastLineStart = gb.findLineStart(gb.lineCount - 1)
    gb.insert(lastLineStart + 2, "2")
    check gb.getLine(2) == "CC2CC"

    # Insert at middle line (line 1)
    let middleLineStart = gb.findLineStart(1)
    gb.insert(middleLineStart + 2, "3")
    check gb.getLine(1) == "BB3BB"

  test "large buffer with many operations":
    let gb = newGapBuffer()

    # Build a large buffer
    for i in 0 ..< 500:
      gb.insert(gb.charLen, "X")
      if i mod 10 == 0:
        gb.insert(gb.charLen, "\n")

    # Verify structure
    let lineCount = gb.lineCount()
    check lineCount > 1

    # Delete from various positions
    gb.delete(0, 10)
    gb.delete(100, 10)
    gb.delete(200, 10)

    # Insert again
    gb.insert(50, "TEST")

    # Verify buffer is still usable
    let text = $gb
    check text.find("TEST") != -1
    check text.find("X") != -1

  test "gap remains functional after resize":
    let gb = newGapBuffer()

    # Small operations
    for i in 0 ..< 10:
      gb.insertLine(i, "Small" & $i)

    check gb.lineCount() == 11

    # Large expansion
    for i in 10 ..< 200:
      gb.insertLine(i, "Large" & $i)

    check gb.lineCount() == 201

    # Verify random access still works
    check gb.getLine(5) == "Small5"
    check gb.getLine(50) == "Large50"
    check gb.getLine(150) == "Large150"

  test "rapid insert/delete cycles":
    let gb = newGapBuffer("Base")

    for cycle in 0 ..< 50:
      gb.insert(2, "XY")
      gb.delete(2, 2)

    # Should return to original state
    check $gb == "Base"

suite "GapBuffer - Edge Cases (Low-level)":
  test "empty buffer operations":
    let gb = newGapBuffer()

    # charAt on empty buffer should fail (no characters)
    expect(IndexDefect):
      discard gb.charAt(0)

    # getLine on empty returns empty string
    check gb.getLine(0) == ""

    # String conversion
    check $gb == ""

    # Length
    check gb.charLen == 0 # No actual characters
    check gb.lineCount() == 1 # One empty line

  test "single character buffer":
    let gb = newGapBuffer("A")

    check gb.len == 1
    check gb.charAt(0) == 'A'
    check $gb == "A"

    # Delete it
    gb.delete(0, 1)
    check $gb == ""

  test "buffer with only newlines":
    let gb = newGapBuffer("\n\n\n")

    # Trailing newline is line terminator, not separator
    # So "\n\n\n" = 3 empty lines (each terminated by newline)
    check gb.lineCount() == 3
    for i in 0 ..< 3:
      check gb.getLine(i) == ""

  test "very long line":
    var longText = ""
    for i in 0 ..< 10000:
      longText.add('X')

    let gb = newGapBuffer(longText)
    check gb.lineCount() == 1
    check gb.getLine(0).len == 10000
    check gb.charLen == 10000

  test "many empty lines":
    let gb = newGapBuffer()
    for i in 0 ..< 1000:
      gb.insertLine(i, "")

    check gb.lineCount() == 1001 # 1000 + initial
    for i in 0 ..< 1000:
      check gb.getLine(i) == ""

  test "boundary insert at every position":
    let gb = newGapBuffer("ABC")

    # Insert at each position
    gb.insert(0, "0") # "0ABC"
    gb.insert(2, "1") # "0A1BC"
    gb.insert(5, "2") # "0A1BC2"

    check $gb == "0A1BC2"

  test "boundary delete at boundaries":
    let gb = newGapBuffer("ABCDEF")

    # Delete from start
    gb.delete(0, 1)
    check $gb == "BCDEF"

    # Delete from current end
    gb.delete(4, 1)
    check $gb == "BCDE"

  test "zero-length operations":
    let gb = newGapBuffer("Test")

    # Insert zero-length string
    gb.insert(2, "")
    check $gb == "Test"

    # Delete zero count
    gb.delete(2, 0)
    check $gb == "Test"

  test "out of bounds access":
    let gb = newGapBuffer("Test")

    # charAt beyond (but within last line's virtual newline might succeed)
    # Position 4 is the virtual newline, 5+ should fail
    expect(IndexDefect):
      discard gb.charAt(100)

    # getLine beyond
    check gb.getLine(100) == ""

    # delete beyond does partial delete
    gb.delete(2, 100)
    check $gb == "Te"

  test "insert then immediate delete":
    let gb = newGapBuffer("Base")

    let originalLen = gb.len
    gb.insert(2, "XYZ")
    gb.delete(2, 3)

    check gb.len == originalLen
    check $gb == "Base"

  test "substring consistency with charAt":
    let gb = newGapBuffer("ABCDEFGH")

    for start in 0 .. 7:
      for length in 1 .. 3:
        let sub = gb.substring(start, length)
        for i in 0 ..< sub.len:
          if start + i < gb.charLen:
            check sub[i] == gb.charAt(start + i)

  test "line iterator on edge cases":
    # Empty buffer
    let gb1 = newGapBuffer()
    var count1 = 0
    for line in gb1.lines():
      inc count1
    check count1 == 1

    # Single line
    let gb2 = newGapBuffer("Test")
    var lines2: seq[string] = @[]
    for line in gb2.lines():
      lines2.add(line)
    check lines2.len == 1

  test "character iterator completeness":
    # POSIX semantics: "A\nB\n" = 2 lines "A" and "B" (trailing newline is terminator)
    # chars() iterator is consistent with $ operator
    let text = "A\nB\n"
    let gb = newGapBuffer(text)

    var reconstructed = ""
    for ch in gb.chars():
      reconstructed.add(ch)

    # Trailing newline is not preserved (POSIX terminator semantics)
    check reconstructed == "A\nB"
    check reconstructed == $gb

suite "GapBuffer - String Conversion Extended":
  test "string conversion empty buffer":
    let gb = newGapBuffer()
    check $gb == ""

  test "string conversion single line":
    let gb = newGapBuffer("Hello")
    check $gb == "Hello"

  test "string conversion multiple lines":
    let gb = newGapBuffer("Line1\nLine2\nLine3")
    check $gb == "Line1\nLine2\nLine3"

  test "string conversion empty lines":
    let gb = newGapBuffer("\n\n")
    check $gb == "\n\n"

  test "chars iterator empty buffer":
    let gb = newGapBuffer()
    var chars: seq[char] = @[]
    for ch in gb.chars():
      chars.add(ch)
    check chars.len == 0

  test "chars iterator single line":
    let gb = newGapBuffer("ABC")
    var chars: seq[char] = @[]
    for ch in gb.chars():
      chars.add(ch)
    check chars == @['A', 'B', 'C']

  test "chars iterator multiple lines":
    let gb = newGapBuffer("AB\nCD")
    var chars: seq[char] = @[]
    for ch in gb.chars():
      chars.add(ch)
    check chars == @['A', 'B', '\n', 'C', 'D']

  test "chars iterator reconstruction":
    let text = "Hello\nWorld\n!"
    let gb = newGapBuffer(text)
    var reconstructed = ""
    for ch in gb.chars():
      reconstructed.add(ch)
    check reconstructed == text

  test "lines iterator empty buffer":
    let gb = newGapBuffer()
    var lines: seq[string] = @[]
    for line in gb.lines():
      lines.add(line)
    check lines == @[""]

  test "lines iterator single line":
    let gb = newGapBuffer("Test")
    var lines: seq[string] = @[]
    for line in gb.lines():
      lines.add(line)
    check lines == @["Test"]

  test "lines iterator multiple lines":
    let gb = newGapBuffer("Line1\nLine2\nLine3")
    var lines: seq[string] = @[]
    for line in gb.lines():
      lines.add(line)
    check lines == @["Line1", "Line2", "Line3"]

  test "lines iterator empty lines":
    # POSIX semantics: "\n\n" = 2 empty lines (each \n terminates a line)
    let gb = newGapBuffer("\n\n")
    var lines: seq[string] = @[]
    for line in gb.lines():
      lines.add(line)
    check lines == @["", ""]

  test "string conversion after modifications":
    let gb = newGapBuffer("Initial")
    gb.insert(0, "Pre")
    check $gb == "PreInitial"

    gb.insert(gb.charLen, "Post")
    check $gb == "PreInitialPost"

    gb.delete(3, 7)
    check $gb == "PrePost"

  test "iterator consistency after modifications":
    let gb = newGapBuffer("AB\nCD")
    gb.insert(2, "X") # "ABX\nCD"

    var chars: seq[char] = @[]
    for ch in gb.chars():
      chars.add(ch)
    check chars == @['A', 'B', 'X', '\n', 'C', 'D']

    var lines: seq[string] = @[]
    for line in gb.lines():
      lines.add(line)
    check lines == @["ABX", "CD"]

  test "string conversion with Unicode":
    let gb = newGapBuffer("Hello 世界 🌍")
    let result = $gb
    check result == "Hello 世界 🌍"

  test "chars iterator with Unicode":
    let gb = newGapBuffer("日本")
    var result = ""
    for ch in gb.chars():
      result.add(ch)
    check result == "日本"

# Additional API Tests

suite "GapBuffer - findLineEnd":
  test "findLineEnd single line":
    let gb = newGapBuffer("Hello")
    # Line 0: "Hello" (positions 0-4)
    # findLineEnd returns position of last char (before newline)
    check gb.findLineEnd(0) == 4

  test "findLineEnd multiple lines":
    let gb = newGapBuffer("Hello\nWorld\nTest")
    # Line 0: "Hello" (positions 0-4), ends at 4
    # Line 1: "World" (positions 6-10), ends at 10
    # Line 2: "Test" (positions 12-15), ends at 15
    check gb.findLineEnd(0) == 4
    check gb.findLineEnd(1) == 10
    check gb.findLineEnd(2) == 15

  test "findLineEnd empty line":
    let gb = newGapBuffer("A\n\nB")
    # Line 0: "A" (position 0), ends at 0
    # Line 1: "" (empty), ends at 1 (position 2 is start, len is 0, so 2 + 0 - 1 = 1)
    # Line 2: "B" (position 3), ends at 3
    check gb.findLineEnd(0) == 0
    check gb.findLineEnd(1) == 1 # Empty line: lineStart(1)=2, lineLen=0, so 2+0-1=1
    check gb.findLineEnd(2) == 3

  test "findLineEnd invalid line":
    let gb = newGapBuffer("Test")
    check gb.findLineEnd(-1) == -1
    check gb.findLineEnd(100) == -1

  test "findLineEnd empty buffer":
    let gb = newGapBuffer()
    # Empty buffer has one empty line
    check gb.findLineEnd(0) == -1 # lineStart(0)=0, lineLen=0, so 0+0-1=-1

suite "GapBuffer - Character Modification":
  test "modify character via line replacement":
    let gb = newGapBuffer("Hello")
    var line = gb[0]
    line[0] = 'J'
    gb[0] = line
    check gb[0] == "Jello"

  test "modify character in middle":
    let gb = newGapBuffer("Hello")
    var line = gb[0]
    line[2] = 'X'
    gb[0] = line
    check gb[0] == "HeXlo"

  test "modify character at end":
    let gb = newGapBuffer("Hello")
    var line = gb[0]
    line[4] = '!'
    gb[0] = line
    check gb[0] == "Hell!"

  test "modify characters in multiple lines":
    let gb = newGapBuffer("ABC\nDEF")
    var line0 = gb[0]
    line0[1] = 'X'
    gb[0] = line0

    var line1 = gb[1]
    line1[1] = 'Y'
    gb[1] = line1

    check gb[0] == "AXC"
    check gb[1] == "DYF"

  test "modifyLineContent for character change":
    let gb = newGapBuffer("Hello")
    gb.modifyLineContent(
      0,
      proc(s: var string) =
        s[0] = 'J',
    )
    check gb[0] == "Jello"

  test "modifyLineContent for multiple changes":
    let gb = newGapBuffer("abcde")
    gb.modifyLineContent(
      0,
      proc(s: var string) =
        s[0] = 'A'
        s[2] = 'C'
        s[4] = 'E',
    )
    check gb[0] == "AbCdE"

suite "GapBuffer - Stress Tests":
  test "many sequential insertions and deletions":
    let gb = newGapBuffer()

    # Insert 1000 lines
    for i in 0 ..< 1000:
      gb.insertLine(i, "Line " & $i)

    check gb.lineCount() == 1001

    # Delete half
    for i in 0 ..< 500:
      gb.deleteLine(0)

    check gb.lineCount() == 501

    # Verify remaining content
    check gb.getLine(0) == "Line 500"

  test "alternating operations at different positions":
    let gb = newGapBuffer("AAAA\nBBBB\nCCCC\nDDDD")

    # Operations that force gap movement
    for i in 0 ..< 50:
      gb.insert(0, "X") # Insert at start
      gb.insert(gb.charLen, "Y") # Insert at end
      if i mod 5 == 0:
        gb.delete(gb.charLen div 2, 1) # Delete from middle

    # Verify buffer is still consistent
    check gb.lineCount() >= 1
    let text = $gb
    check text.len > 0

  test "rapid insert at same position":
    let gb = newGapBuffer("Base")

    for i in 0 ..< 500:
      gb.insert(2, "X")

    check gb.getLine(0).len == 504 # "Ba" + 500 'X' + "se"

  test "delete entire buffer repeatedly":
    let gb = newGapBuffer()

    for round in 0 ..< 10:
      # Fill buffer
      for i in 0 ..< 100:
        gb.insertLine(i, "Line " & $i)

      # Delete all
      while gb.lineCount() > 1:
        gb.deleteLine(0)

      check gb.lineCount() == 1

  test "mixed line and character operations":
    let gb = newGapBuffer()

    for i in 0 ..< 100:
      gb.insertLine(gb.lineCount(), "Line" & $i)
      gb.insert(gb.charLen, "!")
      if i mod 3 == 0:
        gb.insertIntoLine(i, 0, ">>")

    check gb.lineCount() > 100

suite "GapBuffer - Boundary Conditions":
  test "insert at exact capacity boundary":
    let gb = newGapBuffer()
    let initialInfo = gb.getGapInfo()

    # Fill exactly to initial capacity
    for i in 0 ..< initialInfo.capacity - 1:
      gb.insertLine(i, "L" & $i)

    # One more should trigger resize
    let beforeResize = gb.getGapInfo()
    gb.insertLine(gb.lineCount(), "Overflow")
    let afterResize = gb.getGapInfo()

    check afterResize.capacity > beforeResize.capacity

  test "delete to single line":
    let gb = newGapBuffer("A\nB\nC\nD\nE")
    check gb.lineCount() == 5

    gb.deleteLine(4)
    gb.deleteLine(3)
    gb.deleteLine(2)
    gb.deleteLine(1)

    check gb.lineCount() == 1
    check gb[0] == "A"

  test "operations on single character lines":
    let gb = newGapBuffer("A\nB\nC")

    gb.insertIntoLine(0, 1, "X")
    check gb[0] == "AX"

    gb.deleteAtLineCol(1, 0, 1)
    check gb[1] == ""

    gb[2] = "Z"
    check gb[2] == "Z"

  test "charLen consistency after operations":
    let gb = newGapBuffer("Hello\nWorld")
    let initialLen = gb.charLen
    check initialLen == 11 # "Hello" + "\n" + "World"

    gb.insert(5, "X")
    check gb.charLen == initialLen + 1

    gb.delete(5, 1)
    check gb.charLen == initialLen

  test "lineCount consistency after operations":
    let gb = newGapBuffer("A")
    check gb.lineCount() == 1

    gb.insert(1, "\n")
    check gb.lineCount() == 2

    gb.insert(2, "\n")
    check gb.lineCount() == 3

    gb.delete(1, 1) # Delete first newline
    check gb.lineCount() == 2

suite "GapBuffer - Unicode Extended":
  test "character modification with Unicode context":
    let gb = newGapBuffer("ABC")
    var line = gb[0]
    line[1] = 'X'
    gb[0] = line
    check gb[0] == "AXC"

  test "substring with Unicode":
    let gb = newGapBuffer("Hello世界")
    # ASCII part
    check gb.substring(0, 5) == "Hello"

  test "findLineStart and findLineEnd with Unicode":
    let gb = newGapBuffer("日本語\nEnglish")
    check gb.findLineStart(0) == 0
    check gb.findLineStart(1) == 10 # After "日本語\n" (9 bytes + 1 newline)
    check gb.findLineEnd(0) == 8 # "日本語" is 9 bytes, last char at position 8
    check gb.findLineEnd(1) == 16 # "English" ends at position 16

  test "charLen with various Unicode":
    let gb1 = newGapBuffer("Hello")
    check gb1.charLen == 5

    let gb2 = newGapBuffer("日本語")
    check gb2.charLen == 9 # 3 chars * 3 bytes each

    let gb3 = newGapBuffer("🎉🎌🌍")
    check gb3.charLen == 12 # 3 emojis * 4 bytes each

suite "GapBuffer - Error Handling":
  test "insertLine at invalid negative index":
    let gb = newGapBuffer("Test")
    expect IndexDefect:
      gb.insertLine(-1, "Invalid")

  test "insertLine at index beyond len":
    let gb = newGapBuffer("Test")
    expect IndexDefect:
      gb.insertLine(10, "Invalid")

  test "deleteLine at invalid index":
    let gb = newGapBuffer("Test")
    expect IndexDefect:
      gb.deleteLine(-1)
    expect IndexDefect:
      gb.deleteLine(10)

  test "replaceLine at invalid index":
    let gb = newGapBuffer("Test")
    expect IndexDefect:
      gb.replaceLine(-1, "Invalid")
    expect IndexDefect:
      gb.replaceLine(10, "Invalid")

  test "modifyLineContent at invalid index":
    let gb = newGapBuffer("Test")
    expect IndexDefect:
      gb.modifyLineContent(
        -1,
        proc(s: var string) =
          discard,
      )
    expect IndexDefect:
      gb.modifyLineContent(
        10,
        proc(s: var string) =
          discard,
      )

  test "insertIntoLine at invalid line":
    let gb = newGapBuffer("Test")
    expect IndexDefect:
      gb.insertIntoLine(-1, 0, "X")
    expect IndexDefect:
      gb.insertIntoLine(10, 0, "X")

  test "insertIntoLine at invalid column":
    let gb = newGapBuffer("Test")
    expect IndexDefect:
      gb.insertIntoLine(0, -1, "X")
    expect IndexDefect:
      gb.insertIntoLine(0, 100, "X")

  test "deleteAtLineCol at invalid line":
    let gb = newGapBuffer("Test")
    expect IndexDefect:
      gb.deleteAtLineCol(-1, 0, 1)
    expect IndexDefect:
      gb.deleteAtLineCol(10, 0, 1)

  test "deleteAtLineCol with invalid count":
    let gb = newGapBuffer("Test")
    expect IndexDefect:
      gb.deleteAtLineCol(0, 0, 0)
    expect IndexDefect:
      gb.deleteAtLineCol(0, 0, -1)
