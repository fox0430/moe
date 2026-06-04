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

import std/[unittest, strutils, random, math]

import ../src/moepkg/buffer_backends/sqrt_decomp {.all.}

suite "SqrtDecomp - Basic Operations":
  test "newSqrtDecomp creates empty buffer":
    let sd = newSqrtDecomp()
    check sd.len == 1
    check sd[0] == ""

  test "newSqrtDecomp with text":
    let sd = newSqrtDecomp("hello\nworld")
    check sd.len == 2
    check sd[0] == "hello"
    check sd[1] == "world"

  test "newSqrtDecomp with trailing newline":
    let sd = newSqrtDecomp("hello\nworld\n")
    check sd.len == 2
    check sd[0] == "hello"
    check sd[1] == "world"

  test "len returns line count":
    let sd = newSqrtDecomp("line1\nline2\nline3")
    check sd.len == 3

  test "empty string creates single empty line":
    let sd = newSqrtDecomp("")
    check sd.len == 1
    check sd[0] == ""

  test "single newline creates one empty line":
    # "hello\n" -> 1 line: "hello"
    # "\n" -> 1 line: ""
    let sd = newSqrtDecomp("\n")
    check sd.len == 1
    check sd[0] == ""

  test "double newline creates two lines":
    let sd = newSqrtDecomp("\n\n")
    check sd.len == 2
    check sd[0] == ""
    check sd[1] == ""

suite "SqrtDecomp - Line Access":
  test "getLine returns correct line":
    let sd = newSqrtDecomp("hello\nworld\nfoo")
    check sd.getLine(0) == "hello"
    check sd.getLine(1) == "world"
    check sd.getLine(2) == "foo"

  test "getLine with invalid index":
    let sd = newSqrtDecomp("hello")
    check sd.getLine(-1) == ""
    check sd.getLine(1) == ""

  test "bracket operator":
    let sd = newSqrtDecomp("abc\ndef")
    check sd[0] == "abc"
    check sd[1] == "def"

  test "bracket assignment":
    let sd = newSqrtDecomp("abc\ndef")
    sd[0] = "xyz"
    check sd[0] == "xyz"
    check sd[1] == "def"

suite "SqrtDecomp - Character Access":
  test "charAtLineCol basic":
    let sd = newSqrtDecomp("hello\nworld")
    check sd.charAtLineCol(0, 0) == 'h'
    check sd.charAtLineCol(0, 4) == 'o'
    check sd.charAtLineCol(1, 0) == 'w'

  test "charAtLineCol at end of line returns newline":
    let sd = newSqrtDecomp("hello\nworld")
    check sd.charAtLineCol(0, 5) == '\n'

  test "charAt linear index":
    let sd = newSqrtDecomp("ab\ncd")
    check sd.charAt(0) == 'a'
    check sd.charAt(1) == 'b'
    check sd.charAt(2) == '\n'
    check sd.charAt(3) == 'c'
    check sd.charAt(4) == 'd'

suite "SqrtDecomp - Insert Operations":
  test "insertLine at beginning":
    let sd = newSqrtDecomp("world")
    sd.insertLine(0, "hello")
    check sd.len == 2
    check sd[0] == "hello"
    check sd[1] == "world"

  test "insertLine at end":
    let sd = newSqrtDecomp("hello")
    sd.insertLine(1, "world")
    check sd.len == 2
    check sd[0] == "hello"
    check sd[1] == "world"

  test "insertLine in middle":
    let sd = newSqrtDecomp("first\nthird")
    sd.insertLine(1, "second")
    check sd.len == 3
    check sd[0] == "first"
    check sd[1] == "second"
    check sd[2] == "third"

  test "insertIntoLine":
    let sd = newSqrtDecomp("hllo")
    sd.insertIntoLine(0, 1, "e")
    check sd[0] == "hello"

  test "insertIntoLine at beginning":
    let sd = newSqrtDecomp("world")
    sd.insertIntoLine(0, 0, "hello ")
    check sd[0] == "hello world"

  test "insertIntoLine at end":
    let sd = newSqrtDecomp("hello")
    sd.insertIntoLine(0, 5, " world")
    check sd[0] == "hello world"

suite "SqrtDecomp - Delete Operations":
  test "deleteLine":
    let sd = newSqrtDecomp("hello\nworld\nfoo")
    sd.deleteLine(1)
    check sd.len == 2
    check sd[0] == "hello"
    check sd[1] == "foo"

  test "deleteLine first":
    let sd = newSqrtDecomp("hello\nworld")
    sd.deleteLine(0)
    check sd.len == 1
    check sd[0] == "world"

  test "deleteLine last":
    let sd = newSqrtDecomp("hello\nworld")
    sd.deleteLine(1)
    check sd.len == 1
    check sd[0] == "hello"

  test "deleteAtLineCol single char":
    let sd = newSqrtDecomp("hello")
    sd.deleteAtLineCol(0, 1, 1)
    check sd[0] == "hllo"

  test "deleteAtLineCol multiple chars":
    let sd = newSqrtDecomp("hello world")
    sd.deleteAtLineCol(0, 5, 6)
    check sd[0] == "hello"

  test "deleteAtLineCol across lines":
    let sd = newSqrtDecomp("hello\nworld")
    # Delete from col 3 of line 0, count=4: "lo" + newline + "w" = 4 bytes
    sd.deleteAtLineCol(0, 3, 4)
    check sd.len == 1
    check sd[0] == "helorld"

suite "SqrtDecomp - Replace Operations":
  test "replaceLine":
    let sd = newSqrtDecomp("hello\nworld")
    sd.replaceLine(0, "hi")
    check sd[0] == "hi"
    check sd[1] == "world"

  test "modifyLineContent":
    let sd = newSqrtDecomp("hello")
    sd.modifyLineContent(
      0,
      proc(s: var string) =
        s = s.toUpperAscii(),
    )
    check sd[0] == "HELLO"

suite "SqrtDecomp - String Conversion":
  test "toString basic":
    let sd = newSqrtDecomp("hello\nworld")
    check $sd == "hello\nworld"

  test "toString single line":
    let sd = newSqrtDecomp("hello")
    check $sd == "hello"

  test "toString empty":
    let sd = newSqrtDecomp()
    check $sd == ""

  test "toString trailing newline semantics":
    # "hello\n" -> 1 line "hello", endOfLine managed by TextBuffer
    let sd = newSqrtDecomp("hello\n")
    check $sd == "hello"

  test "toString double newline":
    # "hello\n\n" -> 2 lines: "hello", ""
    # Last line is empty and len > 1, so trailing newline is added
    let sd = newSqrtDecomp("hello\n\n")
    check $sd == "hello\n\n"

  test "toString roundtrip":
    let original = "line1\nline2\nline3"
    let sd = newSqrtDecomp(original)
    check $sd == original

suite "SqrtDecomp - Iterators":
  test "chars iterator":
    let sd = newSqrtDecomp("ab\ncd")
    var result = ""
    for ch in sd.chars:
      result.add(ch)
    check result == "ab\ncd"

  test "lines iterator":
    let sd = newSqrtDecomp("hello\nworld\nfoo")
    var result: seq[string] = @[]
    for line in sd.lines:
      result.add(line)
    check result == @["hello", "world", "foo"]

suite "SqrtDecomp - Linear Index Operations":
  test "indexToLineCol":
    let sd = newSqrtDecomp("ab\ncd\nef")
    check sd.indexToLineCol(0) == (0, 0)
    check sd.indexToLineCol(1) == (0, 1)
    check sd.indexToLineCol(2) == (0, 2) # end of line 0
    check sd.indexToLineCol(3) == (1, 0)
    check sd.indexToLineCol(5) == (1, 2) # end of line 1
    check sd.indexToLineCol(6) == (2, 0)

  test "substring":
    let sd = newSqrtDecomp("hello\nworld")
    check sd.substring(0, 5) == "hello"
    check sd.substring(6, 5) == "world"
    check sd.substring(3, 5) == "lo\nwo"

  test "slice operator":
    let sd = newSqrtDecomp("hello\nworld")
    check sd[0 .. 4] == "hello"
    check sd[6 .. 10] == "world"

  test "insert at linear index":
    let sd = newSqrtDecomp("hllo")
    sd.insert(1, "e")
    check $sd == "hello"

  test "insert with newline at linear index":
    let sd = newSqrtDecomp("helloworld")
    sd.insert(5, "\n")
    check sd.len == 2
    check sd[0] == "hello"
    check sd[1] == "world"

  test "delete at linear index":
    let sd = newSqrtDecomp("hello")
    sd.delete(1, 1)
    check $sd == "hllo"

suite "SqrtDecomp - Unicode/Multibyte":
  test "Japanese text":
    let sd = newSqrtDecomp("こんにちは\n世界")
    check sd.len == 2
    check sd[0] == "こんにちは"
    check sd[1] == "世界"
    check $sd == "こんにちは\n世界"

  test "Emoji text":
    let sd = newSqrtDecomp("Hello 🌍\n🎉 Party")
    check sd.len == 2
    check sd[0] == "Hello 🌍"
    check sd[1] == "🎉 Party"

  test "Mixed ASCII and multibyte":
    let sd = newSqrtDecomp("abc日本語def")
    check sd[0] == "abc日本語def"
    sd.insertIntoLine(0, 3, "XYZ")
    check sd[0] == "abcXYZ日本語def"

suite "SqrtDecomp - Block Rebalancing":
  test "split on large insert":
    let sd = newSqrtDecomp()
    # Insert more than MAX_BLOCK_SIZE lines to trigger splits
    for i in 0 ..< 2000:
      sd.insertLine(i, "line " & $i)
    # Delete the initial empty line
    sd.deleteLine(sd.len - 1)

    check sd.len == 2000
    let info = sd.getBlockInfo()
    check info.blockCount > 1

    # Verify content integrity
    for i in 0 ..< 2000:
      check sd[i] == "line " & $i

  test "merge on large delete":
    # Create buffer with many lines
    var text = ""
    for i in 0 ..< 500:
      text.add("line " & $i & "\n")
    text.add("last")
    let sd = newSqrtDecomp(text)
    check sd.len == 501

    # Delete most lines
    for i in countdown(499, 1):
      sd.deleteLine(i)

    check sd.len == 2
    check sd[0] == "line 0"
    check sd[1] == "last"

  test "block structure stays Theta(sqrt n) under mixed insert/delete stress":
    # Locks in the "true sqrt-decomposition" guarantee: across a long run of
    # mixed edits the block COUNT (and hence block size) stays at Theta(sqrt n),
    # rather than drifting toward O(n) blocks. The delete branch uses cross-block
    # multi-line deletes, which exercise the under-full merge at BOTH ends of a
    # splice; without that the block count would creep above the band between
    # rebalances. Also asserts the global charLen cache stays exact after every
    # op (guards the per-block cachedCharLen bookkeeping the backend relies on).
    proc recomputedCharLen(sd: SqrtDecomp): int =
      for ln in sd.lines:
        result += ln.len
      if sd.lineCount > 1:
        result += sd.lineCount - 1

    var r = initRand(20240604)
    let sd = newSqrtDecomp()
    for i in 0 ..< 2000:
      sd.insertLine(sd.lineCount, "line" & $i)

    for step in 0 ..< 1500:
      let n = sd.lineCount
      case r.rand(0 .. 3)
      of 0, 1:
        if n > 64:
          # Cross-block multi-line delete (spans a block boundary for large counts)
          let ls = sd.findLineStart(r.rand(0 ..< n - 1))
          sd.delete(ls, r.rand(1 .. 40))
        else:
          sd.insertLine(n, "refill" & $step)
      else:
        # Multi-line insert to add lines back and keep n in a healthy range
        let idx = r.rand(0 .. sd.charLen)
        sd.insert(idx, "a\nbb\nccc")

      # The charLen cache must match a from-scratch recomputation every step.
      check sd.charLen == sd.recomputedCharLen

      let info = sd.getBlockInfo()
      check info.totalLines == sd.lineCount
      # Theta(sqrt n) band, checked only where the asymptotics are clean. The
      # bounds are deliberately loose (observed ratio ~0.4..1.4) so they never
      # flake, but still catch an O(n)-blocks regression or a broken split/merge.
      if sd.lineCount >= 256:
        let s = sqrt(sd.lineCount.float)
        check info.blockCount.float <= 3.0 * s + 8.0 # not too many blocks
        check info.blockCount.float >= s / 8.0 # not too few (split is working)

suite "SqrtDecomp - Edge Cases":
  test "empty line operations":
    let sd = newSqrtDecomp("")
    check sd.len == 1
    check sd[0] == ""
    sd.insertIntoLine(0, 0, "hello")
    check sd[0] == "hello"

  test "boundary positions":
    let sd = newSqrtDecomp("abc\ndef\nghi")
    # Delete at end of line
    sd.deleteAtLineCol(0, 2, 1)
    check sd[0] == "ab"
    check sd.len == 3

  test "clear and reuse":
    let sd = newSqrtDecomp("hello\nworld")
    sd.clear()
    check sd.len == 1
    check sd[0] == ""
    sd.insertIntoLine(0, 0, "new")
    check sd[0] == "new"

  test "single char lines":
    let sd = newSqrtDecomp("a\nb\nc")
    check sd.len == 3
    check $sd == "a\nb\nc"

  test "estimateMemoryUsage":
    let sd = newSqrtDecomp("hello\nworld")
    check sd.estimateMemoryUsage() > 0

suite "SqrtDecomp - Error Handling":
  test "insertLine at invalid negative index":
    let sd = newSqrtDecomp("hello")
    expect IndexDefect:
      sd.insertLine(-1, "bad")

  test "insertLine at index beyond len":
    let sd = newSqrtDecomp("hello")
    expect IndexDefect:
      sd.insertLine(5, "bad")

  test "deleteLine at invalid index":
    let sd = newSqrtDecomp("hello")
    expect IndexDefect:
      sd.deleteLine(1)

  test "deleteLine at negative index":
    let sd = newSqrtDecomp("hello")
    expect IndexDefect:
      sd.deleteLine(-1)

  test "replaceLine at invalid index":
    let sd = newSqrtDecomp("hello")
    expect IndexDefect:
      sd.replaceLine(1, "bad")

  test "modifyLineContent at invalid index":
    let sd = newSqrtDecomp("hello")
    expect IndexDefect:
      sd.modifyLineContent(
        1,
        proc(s: var string) =
          s = "bad",
      )

  test "insertIntoLine at invalid line":
    let sd = newSqrtDecomp("hello")
    expect IndexDefect:
      sd.insertIntoLine(1, 0, "bad")

  test "insertIntoLine at invalid column":
    let sd = newSqrtDecomp("hello")
    expect IndexDefect:
      sd.insertIntoLine(0, 10, "bad")

  test "deleteAtLineCol at invalid line":
    let sd = newSqrtDecomp("hello")
    expect IndexDefect:
      sd.deleteAtLineCol(1, 0, 1)

  test "deleteAtLineCol with invalid count":
    let sd = newSqrtDecomp("hello")
    expect IndexDefect:
      sd.deleteAtLineCol(0, 0, 0)

  test "deleteAtLineCol with negative count":
    let sd = newSqrtDecomp("hello")
    expect IndexDefect:
      sd.deleteAtLineCol(0, 0, -1)

  test "bracket assignment out of bounds":
    let sd = newSqrtDecomp("hello")
    expect IndexDefect:
      sd[5] = "bad"

  test "charAtLineCol at invalid line":
    let sd = newSqrtDecomp("hello")
    expect IndexDefect:
      discard sd.charAtLineCol(1, 0)

  test "charAtLineCol at invalid column":
    let sd = newSqrtDecomp("hello")
    expect IndexDefect:
      discard sd.charAtLineCol(0, 10)

  test "charAt at negative index":
    let sd = newSqrtDecomp("hello")
    expect IndexDefect:
      discard sd.charAt(-1)

  test "charAt beyond end":
    let sd = newSqrtDecomp("hello")
    expect IndexDefect:
      discard sd.charAt(5)

suite "SqrtDecomp - Linear Index Insert Extended":
  test "insert char overload":
    let sd = newSqrtDecomp("hllo")
    sd.insert(1, 'e')
    check $sd == "hello"

  test "insert empty string does nothing":
    let sd = newSqrtDecomp("hello")
    sd.insert(2, "")
    check $sd == "hello"

  test "insert at beginning":
    let sd = newSqrtDecomp("world")
    sd.insert(0, "hello ")
    check $sd == "hello world"

  test "insert at end of buffer":
    let sd = newSqrtDecomp("hello")
    sd.insert(5, " world")
    check $sd == "hello world"

  test "insert single newline in empty buffer":
    let sd = newSqrtDecomp("")
    sd.insert(0, "\n")
    check sd.len == 2
    check sd[0] == ""
    check sd[1] == ""

  test "insert single newline at line start":
    let sd = newSqrtDecomp("hello")
    sd.insert(0, "\n")
    check sd.len == 2
    check sd[0] == ""
    check sd[1] == "hello"

  test "insert single newline in line middle":
    let sd = newSqrtDecomp("helloworld")
    sd.insert(5, "\n")
    check sd.len == 2
    check sd[0] == "hello"
    check sd[1] == "world"

  test "insert multiple consecutive newlines":
    let sd = newSqrtDecomp("hello")
    sd.insert(5, "\n\n\n")
    check sd.len == 4
    check sd[0] == "hello"
    check sd[1] == ""
    check sd[2] == ""
    check sd[3] == ""

  test "insert multi-line text":
    let sd = newSqrtDecomp("start end")
    sd.insert(6, "a\nb\nc ")
    check sd.len == 3
    check sd[0] == "start a"
    check sd[1] == "b"
    check sd[2] == "c end"

  test "insert multi-line text in middle of line":
    let sd = newSqrtDecomp("abcdef")
    sd.insert(3, "X\nY\nZ")
    check sd.len == 3
    check sd[0] == "abcX"
    check sd[1] == "Y"
    check sd[2] == "Zdef"

  test "insert text with newline at start":
    let sd = newSqrtDecomp("world")
    sd.insert(0, "hello\n")
    check sd.len == 2
    check sd[0] == "hello"
    check sd[1] == "world"

  test "sequential insertions":
    let sd = newSqrtDecomp("")
    sd.insert(0, "c")
    sd.insert(0, "b")
    sd.insert(0, "a")
    check $sd == "abc"

  test "insert preserves content after":
    let sd = newSqrtDecomp("hello world")
    sd.insert(5, "\n")
    check sd.len == 2
    check sd[0] == "hello"
    check sd[1] == " world"

  test "insert at negative index does nothing":
    let sd = newSqrtDecomp("hello")
    sd.insert(-1, "x")
    check $sd == "hello"

suite "SqrtDecomp - Linear Index Delete Extended":
  test "delete single character from line":
    let sd = newSqrtDecomp("hello")
    sd.delete(0, 1)
    check $sd == "ello"

  test "delete from end of line":
    let sd = newSqrtDecomp("hello")
    sd.delete(4, 1)
    check $sd == "hell"

  test "delete entire line content":
    let sd = newSqrtDecomp("hello")
    sd.delete(0, 5)
    check $sd == ""
    check sd.len == 1

  test "delete newline character merges lines":
    let sd = newSqrtDecomp("hello\nworld")
    # Delete newline at index 5
    sd.delete(5, 1)
    check sd.len == 1
    check $sd == "helloworld"

  test "delete across two lines":
    let sd = newSqrtDecomp("hello\nworld")
    # Delete "lo\nwo" = 5 chars starting at index 3
    sd.delete(3, 5)
    check sd.len == 1
    check $sd == "helrld"

  test "delete across three lines":
    let sd = newSqrtDecomp("aaa\nbbb\nccc")
    # Indices: a(0)a(1)a(2)\n(3)b(4)b(5)b(6)\n(7)c(8)c(9)c(10)
    # Delete from index 2, 8 chars = positions 2..9 = "a\nbbb\ncc"
    sd.delete(2, 8)
    check sd.len == 1
    check $sd == "aac"

  test "delete entire first line including newline":
    let sd = newSqrtDecomp("hello\nworld")
    sd.delete(0, 6)
    check sd.len == 1
    check $sd == "world"

  test "delete middle line completely":
    let sd = newSqrtDecomp("aaa\nbbb\nccc")
    # "bbb\n" = 4 chars starting at index 4
    sd.delete(4, 4)
    check sd.len == 2
    check sd[0] == "aaa"
    check sd[1] == "ccc"

  test "delete from middle to end":
    let sd = newSqrtDecomp("hello\nworld")
    sd.delete(3, 100)
    check sd.len == 1
    check sd[0] == "hel"

  test "delete with count 0 does nothing":
    let sd = newSqrtDecomp("hello")
    sd.delete(2, 0)
    check $sd == "hello"

  test "delete with negative count does nothing":
    let sd = newSqrtDecomp("hello")
    sd.delete(2, -1)
    check $sd == "hello"

  test "delete from invalid position does nothing":
    let sd = newSqrtDecomp("hello")
    sd.delete(-1, 1)
    check $sd == "hello"

  test "delete empty lines":
    let sd = newSqrtDecomp("\n\n\n")
    # 3 lines: "", "", ""
    # charLen = 2 (two newlines between 3 lines)
    sd.delete(0, 1) # delete first newline
    check sd.len == 2

  test "sequential deletes":
    let sd = newSqrtDecomp("abcdef")
    sd.delete(0, 1) # "bcdef"
    sd.delete(0, 1) # "cdef"
    sd.delete(0, 1) # "def"
    check $sd == "def"

  test "delete and insert combination":
    let sd = newSqrtDecomp("hello world")
    sd.delete(5, 1) # "helloworld"
    sd.insert(5, "_") # "hello_world"
    check $sd == "hello_world"

  test "delete in empty buffer does nothing":
    let sd = newSqrtDecomp("")
    sd.delete(0, 1)
    check sd.len == 1
    check sd[0] == ""

suite "SqrtDecomp - charLen and charAt Extended":
  test "charLen of empty buffer":
    let sd = newSqrtDecomp("")
    check sd.charLen == 0

  test "charLen of single line":
    let sd = newSqrtDecomp("hello")
    check sd.charLen == 5

  test "charLen of multiple lines":
    let sd = newSqrtDecomp("abc\ndef\nghi")
    # 3 + 1 + 3 + 1 + 3 = 11
    check sd.charLen == 11

  test "charLen with empty lines":
    let sd = newSqrtDecomp("\n\n")
    # 2 lines: "", ""; charLen = 1 (one newline between)
    check sd.charLen == 1

  test "charLen after insertLine":
    let sd = newSqrtDecomp("abc")
    check sd.charLen == 3
    sd.insertLine(1, "def")
    # "abc\ndef" = 7
    check sd.charLen == 7

  test "charLen after deleteLine":
    let sd = newSqrtDecomp("abc\ndef")
    check sd.charLen == 7
    sd.deleteLine(1)
    check sd.charLen == 3

  test "charLen after insertIntoLine":
    let sd = newSqrtDecomp("abc")
    sd.insertIntoLine(0, 3, "def")
    check sd.charLen == 6

  test "charAt at line boundaries":
    let sd = newSqrtDecomp("ab\ncd\nef")
    check sd.charAt(2) == '\n' # end of line 0
    check sd.charAt(3) == 'c' # start of line 1
    check sd.charAt(5) == '\n' # end of line 1
    check sd.charAt(6) == 'e' # start of line 2

  test "charAt on empty buffer":
    let sd = newSqrtDecomp("")
    expect IndexDefect:
      discard sd.charAt(0)

  test "charAt on single char":
    let sd = newSqrtDecomp("x")
    check sd.charAt(0) == 'x'
    expect IndexDefect:
      discard sd.charAt(1)

suite "SqrtDecomp - findLineStart and findLineEnd":
  test "findLineStart single line":
    let sd = newSqrtDecomp("hello")
    check sd.findLineStart(0) == 0

  test "findLineStart multiple lines":
    let sd = newSqrtDecomp("abc\ndef\nghi")
    check sd.findLineStart(0) == 0
    check sd.findLineStart(1) == 4
    check sd.findLineStart(2) == 8

  test "findLineStart invalid line":
    let sd = newSqrtDecomp("hello")
    check sd.findLineStart(-1) == -1
    check sd.findLineStart(1) == -1

  test "findLineStart with empty lines":
    let sd = newSqrtDecomp("a\n\nb")
    check sd.findLineStart(0) == 0
    check sd.findLineStart(1) == 2
    check sd.findLineStart(2) == 3

  test "findLineEnd single line":
    let sd = newSqrtDecomp("hello")
    check sd.findLineEnd(0) == 4

  test "findLineEnd multiple lines":
    let sd = newSqrtDecomp("abc\ndef\nghi")
    check sd.findLineEnd(0) == 2
    check sd.findLineEnd(1) == 6
    check sd.findLineEnd(2) == 10

  test "findLineEnd empty line":
    let sd = newSqrtDecomp("a\n\nb")
    # Empty line: findLineStart(1) = 2, lineLen = 0, so 2 + 0 - 1 = 1
    check sd.findLineEnd(1) == 1

  test "findLineEnd invalid line":
    let sd = newSqrtDecomp("hello")
    check sd.findLineEnd(-1) == -1
    check sd.findLineEnd(1) == -1

  test "findLineEnd empty buffer":
    let sd = newSqrtDecomp("")
    check sd.findLineEnd(0) == -1 # empty line: 0 + 0 - 1 = -1

suite "SqrtDecomp - Multi-line Deletion Extended":
  test "deleteAtLineCol spanning three lines":
    let sd = newSqrtDecomp("aaa\nbbb\nccc\nddd")
    # Delete "a\nbbb\nccc\nd" from (0, 2): "a" + "\n" + "bbb" + "\n" + "ccc" + "\n" + "d" = 11
    sd.deleteAtLineCol(0, 2, 11)
    check sd.len == 1
    check sd[0] == "aadd"

  test "deleteAtLineCol from line start to next line end":
    let sd = newSqrtDecomp("hello\nworld")
    # Delete "hello\n" = 6 bytes
    sd.deleteAtLineCol(0, 0, 6)
    check sd.len == 1
    check sd[0] == "world"

  test "deleteAtLineCol to end of buffer":
    let sd = newSqrtDecomp("aaa\nbbb\nccc")
    # Delete from (1, 0) to end: "bbb\nccc" = 7 bytes
    sd.deleteAtLineCol(1, 0, 100)
    check sd.len == 2
    check sd[0] == "aaa"
    check sd[1] == ""

  test "deleteAtLineCol entire buffer":
    let sd = newSqrtDecomp("hello\nworld")
    sd.deleteAtLineCol(0, 0, 100)
    check sd.len == 1
    check sd[0] == ""

  test "deleteAtLineCol with empty lines":
    let sd = newSqrtDecomp("a\n\n\nb")
    # Delete "\n\n" from (0, 1): 2 newlines = 2 bytes
    sd.deleteAtLineCol(0, 1, 2)
    check sd.len == 2
    check sd[0] == "a"
    check sd[1] == "b"

  test "deleteAtLineCol single newline":
    let sd = newSqrtDecomp("hello\nworld")
    sd.deleteAtLineCol(0, 5, 1) # delete newline
    check sd.len == 1
    check sd[0] == "helloworld"

  test "deleteAtLineCol multibyte across lines":
    let sd = newSqrtDecomp("あいう\nえおか")
    # "あ" = 3 bytes, "い" = 3 bytes, "う" = 3 bytes
    # Delete "う\nえ" from (0, 6): 3 + 1 + 3 = 7 bytes
    sd.deleteAtLineCol(0, 6, 7)
    check sd.len == 1
    check sd[0] == "あいおか"

suite "SqrtDecomp - Unicode Extended":
  test "insertIntoLine with multibyte characters":
    let sd = newSqrtDecomp("あいう")
    # Insert "X" after "あ" (byte position 3)
    sd.insertIntoLine(0, 3, "X")
    check sd[0] == "あXいう"

  test "insertIntoLine with emoji":
    let sd = newSqrtDecomp("Hello World")
    sd.insertIntoLine(0, 5, " 🌍")
    check sd[0] == "Hello 🌍 World"

  test "deleteAtLineCol with multibyte characters":
    let sd = newSqrtDecomp("あいうえお")
    # Delete "い" at byte position 3, length 3 bytes
    sd.deleteAtLineCol(0, 3, 3)
    check sd[0] == "あうえお"

  test "deleteAtLineCol across multibyte boundaries":
    let sd = newSqrtDecomp("あいう\nえおか")
    # Delete from byte 0, "あいう\n" = 9 + 1 = 10 bytes
    sd.deleteAtLineCol(0, 0, 10)
    check sd.len == 1
    check sd[0] == "えおか"

  test "charAtLineCol with multibyte":
    let sd = newSqrtDecomp("aあb")
    check sd.charAtLineCol(0, 0) == 'a'
    # "あ" starts at byte 1, is 3 bytes (0xe3, 0x81, 0x82)
    check sd.charAtLineCol(0, 1) == '\xe3'
    check sd.charAtLineCol(0, 4) == 'b'

  test "substring with multibyte":
    let sd = newSqrtDecomp("あいう\nえおか")
    # "あ" = bytes 0-2, "い" = bytes 3-5
    check sd.substring(0, 3) == "あ"
    check sd.substring(3, 3) == "い"

  test "replaceLine with multibyte":
    let sd = newSqrtDecomp("hello\nworld")
    sd.replaceLine(0, "こんにちは")
    check sd[0] == "こんにちは"
    check sd[1] == "world"

  test "multiple lines with multibyte":
    let sd = newSqrtDecomp("日本語\n中文\n한국어\nEmoji 🎉")
    check sd.len == 4
    check sd[0] == "日本語"
    check sd[1] == "中文"
    check sd[2] == "한국어"
    check sd[3] == "Emoji 🎉"
    check $sd == "日本語\n中文\n한국어\nEmoji 🎉"

  test "insertLine with multibyte":
    let sd = newSqrtDecomp("あ\nう")
    sd.insertLine(1, "い")
    check sd.len == 3
    check $sd == "あ\nい\nう"

  test "deleteLine with multibyte":
    let sd = newSqrtDecomp("あ\nい\nう")
    sd.deleteLine(1)
    check sd.len == 2
    check $sd == "あ\nう"

  test "byte length vs character length awareness":
    let sd = newSqrtDecomp("あいう")
    # 3 characters, but 9 bytes
    check sd[0].len == 9
    check sd.charLen == 9

suite "SqrtDecomp - Substring Extended":
  test "substring basic extraction":
    let sd = newSqrtDecomp("hello world")
    check sd.substring(0, 5) == "hello"
    check sd.substring(6, 5) == "world"

  test "substring boundary cases":
    let sd = newSqrtDecomp("hello")
    check sd.substring(0, 0) == ""
    check sd.substring(0, 5) == "hello"

  test "substring full buffer":
    let sd = newSqrtDecomp("abc\ndef")
    check sd.substring(0, 7) == "abc\ndef"

  test "substring from start partial":
    let sd = newSqrtDecomp("abc\ndef\nghi")
    check sd.substring(0, 3) == "abc"

  test "substring from end partial":
    let sd = newSqrtDecomp("abc\ndef\nghi")
    check sd.substring(8, 3) == "ghi"

  test "substring beyond end":
    let sd = newSqrtDecomp("abc")
    check sd.substring(0, 100) == "abc"

  test "substring start beyond end":
    let sd = newSqrtDecomp("abc")
    check sd.substring(100, 5) == ""

  test "substring negative length":
    let sd = newSqrtDecomp("abc")
    check sd.substring(0, -1) == ""

  test "substring cross multiple lines":
    let sd = newSqrtDecomp("aa\nbb\ncc\ndd")
    # Indices: a(0)a(1)\n(2)b(3)b(4)\n(5)c(6)c(7)\n(8)d(9)d(10)
    # From index 1, 8 chars = positions 1..8 = "a\nbb\ncc\n"
    check sd.substring(1, 8) == "a\nbb\ncc\n"

suite "SqrtDecomp - Iterator Edge Cases":
  test "iterate over empty buffer":
    let sd = newSqrtDecomp("")
    var count = 0
    for ch in sd.chars:
      inc count
    check count == 0

  test "iterate over single character":
    let sd = newSqrtDecomp("x")
    var result = ""
    for ch in sd.chars:
      result.add(ch)
    check result == "x"

  test "iterate over lines with empty lines":
    let sd = newSqrtDecomp("a\n\nb")
    var result: seq[string] = @[]
    for line in sd.lines:
      result.add(line)
    check result == @["a", "", "b"]

  test "chars iterator consistency with toString":
    let sd = newSqrtDecomp("hello\nworld\nfoo")
    var fromIter = ""
    for ch in sd.chars:
      fromIter.add(ch)
    check fromIter == $sd

  test "lines iterator after modifications":
    let sd = newSqrtDecomp("a\nb\nc")
    sd.deleteLine(1)
    var result: seq[string] = @[]
    for line in sd.lines:
      result.add(line)
    check result == @["a", "c"]

  test "chars iterator after modifications":
    let sd = newSqrtDecomp("abc\ndef")
    sd.insertIntoLine(0, 3, "X")
    var result = ""
    for ch in sd.chars:
      result.add(ch)
    check result == "abcX\ndef"

suite "SqrtDecomp - Stress Tests":
  test "many sequential insertions and deletions":
    let sd = newSqrtDecomp("")
    for i in 0 ..< 1000:
      sd.insertLine(sd.len, "line " & $i)
    # Delete the initial empty line
    sd.deleteLine(0)
    check sd.len == 1000
    for i in 0 ..< 1000:
      check sd[i] == "line " & $i

    # Delete all lines from end
    for i in countdown(999, 1):
      sd.deleteLine(i)
    check sd.len == 1
    check sd[0] == "line 0"

  test "rapid insert at same position":
    let sd = newSqrtDecomp("")
    for i in 0 ..< 500:
      sd.insertIntoLine(0, 0, "x")
    check sd[0].len == 500

  test "alternating operations at different positions":
    let sd = newSqrtDecomp("start\nend")
    for i in 0 ..< 100:
      sd.insertLine(1, "mid " & $i)
    check sd.len == 102
    check sd[0] == "start"
    check sd[sd.len - 1] == "end"

    for i in countdown(100, 1):
      sd.deleteLine(i)
    check sd.len == 2
    check $sd == "start\nend"

  test "delete entire buffer repeatedly":
    let sd = newSqrtDecomp("hello\nworld")
    for _ in 0 ..< 10:
      sd.clear()
      check sd.len == 1
      check sd[0] == ""
      sd.insertIntoLine(0, 0, "hello")
      sd.insertLine(1, "world")
      check sd.len == 2
      check $sd == "hello\nworld"

  test "mixed line and character operations":
    let sd = newSqrtDecomp("aaa\nbbb\nccc")
    sd.insertIntoLine(1, 1, "X") # "aaa\nbXbb\nccc"
    check sd[1] == "bXbb"
    sd.deleteLine(0) # "bXbb\nccc"
    check sd.len == 2
    sd.insertLine(0, "new") # "new\nbXbb\nccc"
    check sd.len == 3
    sd.deleteAtLineCol(1, 1, 1) # "new\nbbb\nccc"
    check sd[1] == "bbb"
    check $sd == "new\nbbb\nccc"

  test "charLen consistency after operations":
    let sd = newSqrtDecomp("abc\ndef\nghi")
    let initial = sd.charLen
    check initial == 11

    sd.insertIntoLine(0, 3, "XYZ")
    check sd.charLen == initial + 3

    sd.deleteAtLineCol(0, 3, 3)
    check sd.charLen == initial

    sd.insertLine(1, "new")
    check sd.charLen == initial + 4 # "new" + newline

    sd.deleteLine(1)
    check sd.charLen == initial

  test "lineCount consistency after operations":
    let sd = newSqrtDecomp("a\nb\nc")
    check sd.len == 3

    sd.insertLine(1, "x")
    check sd.len == 4

    sd.deleteLine(1)
    check sd.len == 3

    sd.deleteAtLineCol(0, 1, 2) # delete "a\n" tail -> merge with b
    # "a" has len 1, col 1 means at end. Delete 2 = newline + "b"
    check sd.len == 2
