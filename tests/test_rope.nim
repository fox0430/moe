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

import ../src/moepkg/buffer_backends/rope {.all.}

suite "Rope - Basic Operations":
  test "newRope creates empty buffer":
    let r = newRope()
    check r.len == 1
    check r[0] == ""

  test "newRope with text":
    let r = newRope("hello\nworld")
    check r.len == 2
    check r[0] == "hello"
    check r[1] == "world"

  test "newRope with trailing newline":
    let r = newRope("hello\nworld\n")
    check r.len == 2
    check r[0] == "hello"
    check r[1] == "world"

  test "len returns line count":
    let r = newRope("line1\nline2\nline3")
    check r.len == 3

  test "empty string creates single empty line":
    let r = newRope("")
    check r.len == 1
    check r[0] == ""

  test "single newline creates one empty line":
    let r = newRope("\n")
    check r.len == 1
    check r[0] == ""

  test "double newline creates two lines":
    let r = newRope("\n\n")
    check r.len == 2
    check r[0] == ""
    check r[1] == ""

suite "Rope - Line Access":
  test "getLine returns correct line":
    let r = newRope("hello\nworld\nfoo")
    check r.getLine(0) == "hello"
    check r.getLine(1) == "world"
    check r.getLine(2) == "foo"

  test "getLine with invalid index":
    let r = newRope("hello")
    check r.getLine(-1) == ""
    check r.getLine(1) == ""

  test "bracket operator":
    let r = newRope("abc\ndef")
    check r[0] == "abc"
    check r[1] == "def"

  test "bracket assignment":
    let r = newRope("abc\ndef")
    r[0] = "xyz"
    check r[0] == "xyz"
    check r[1] == "def"

suite "Rope - Character Access":
  test "charAtLineCol basic":
    let r = newRope("hello\nworld")
    check r.charAtLineCol(0, 0) == 'h'
    check r.charAtLineCol(0, 4) == 'o'
    check r.charAtLineCol(1, 0) == 'w'

  test "charAtLineCol at end of line returns newline":
    let r = newRope("hello\nworld")
    check r.charAtLineCol(0, 5) == '\n'

  test "charAt linear index":
    let r = newRope("ab\ncd")
    check r.charAt(0) == 'a'
    check r.charAt(1) == 'b'
    check r.charAt(2) == '\n'
    check r.charAt(3) == 'c'
    check r.charAt(4) == 'd'

suite "Rope - Line Insert":
  test "insertLine at beginning":
    let r = newRope("world")
    r.insertLine(0, "hello")
    check r.len == 2
    check r[0] == "hello"
    check r[1] == "world"

  test "insertLine at end":
    let r = newRope("hello")
    r.insertLine(1, "world")
    check r.len == 2
    check r[0] == "hello"
    check r[1] == "world"

  test "insertLine in middle":
    let r = newRope("hello\nworld")
    r.insertLine(1, "middle")
    check r.len == 3
    check r[0] == "hello"
    check r[1] == "middle"
    check r[2] == "world"

suite "Rope - Line Delete":
  test "deleteLine first":
    let r = newRope("hello\nworld")
    r.deleteLine(0)
    check r.len == 1
    check r[0] == "world"

  test "deleteLine last":
    let r = newRope("hello\nworld")
    r.deleteLine(1)
    check r.len == 1
    check r[0] == "hello"

  test "deleteLine middle":
    let r = newRope("a\nb\nc")
    r.deleteLine(1)
    check r.len == 2
    check r[0] == "a"
    check r[1] == "c"

  test "deleteLine only line":
    let r = newRope("hello")
    r.deleteLine(0)
    check r.len == 0

suite "Rope - Insert Into Line":
  test "insertIntoLine at beginning":
    let r = newRope("world")
    r.insertIntoLine(0, 0, "hello ")
    check r[0] == "hello world"

  test "insertIntoLine at end":
    let r = newRope("hello")
    r.insertIntoLine(0, 5, " world")
    check r[0] == "hello world"

  test "insertIntoLine in middle":
    let r = newRope("hllo")
    r.insertIntoLine(0, 1, "e")
    check r[0] == "hello"

suite "Rope - Delete At Line Col":
  test "deleteAtLineCol single char":
    let r = newRope("hello")
    r.deleteAtLineCol(0, 0, 1)
    check r[0] == "ello"

  test "deleteAtLineCol multiple chars":
    let r = newRope("hello world")
    r.deleteAtLineCol(0, 5, 6)
    check r[0] == "hello"

  test "deleteAtLineCol cross line":
    let r = newRope("hello\nworld")
    r.deleteAtLineCol(0, 3, 5)
    check r.len == 1
    check r[0] == "helrld"

suite "Rope - Linear Index Insert":
  test "insert text without newline":
    let r = newRope("hllo")
    r.insert(1, "e")
    check r[0] == "hello"

  test "insert text with newline":
    let r = newRope("helloworld")
    r.insert(5, "\n")
    check r.len == 2
    check r[0] == "hello"
    check r[1] == "world"

  test "insert char":
    let r = newRope("hllo")
    r.insert(1, 'e')
    check r[0] == "hello"

suite "Rope - Linear Index Delete":
  test "delete single char":
    let r = newRope("hello")
    r.delete(0)
    check r[0] == "ello"

  test "delete newline":
    let r = newRope("hello\nworld")
    r.delete(5, 1)
    check r.len == 1
    check r[0] == "helloworld"

  test "delete multiple chars":
    let r = newRope("hello world")
    r.delete(5, 6)
    check r[0] == "hello"

suite "Rope - Linear Index":
  test "findLineStart":
    let r = newRope("hello\nworld\nfoo")
    check r.findLineStart(0) == 0
    check r.findLineStart(1) == 6
    check r.findLineStart(2) == 12

  test "findLineEnd":
    let r = newRope("hello\nworld\nfoo")
    check r.findLineEnd(0) == 4
    check r.findLineEnd(1) == 10
    check r.findLineEnd(2) == 14

  test "indexToLineCol":
    let r = newRope("hello\nworld")
    check r.indexToLineCol(0) == (0, 0)
    check r.indexToLineCol(4) == (0, 4)
    check r.indexToLineCol(5) == (0, 5)
    check r.indexToLineCol(6) == (1, 0)
    check r.indexToLineCol(10) == (1, 4)

suite "Rope - Substring":
  test "substring within line":
    let r = newRope("hello world")
    check r.substring(0, 5) == "hello"
    check r.substring(6, 5) == "world"

  test "substring across lines":
    let r = newRope("hello\nworld")
    check r.substring(3, 5) == "lo\nwo"

  test "slice operator":
    let r = newRope("hello world")
    check r[0 .. 4] == "hello"
    check r[6 .. 10] == "world"

suite "Rope - Conversion":
  test "toString basic":
    let r = newRope("hello\nworld")
    check $r == "hello\nworld"

  test "toString with empty last line":
    let r = newRope("hello\n\n")
    check $r == "hello\n\n"

  test "clear":
    let r = newRope("hello\nworld")
    r.clear()
    check r.len == 1
    check r[0] == ""

  test "chars iterator":
    let r = newRope("ab\ncd")
    var s = ""
    for ch in r.chars:
      s.add(ch)
    check s == "ab\ncd"

  test "chars iterator with empty last line":
    let r = newRope("hello\n\n")
    var s = ""
    for ch in r.chars:
      s.add(ch)
    check s == "hello\n\n"
    check s == $r

  test "lines iterator":
    let r = newRope("hello\nworld")
    var result: seq[string] = @[]
    for line in r.lines:
      result.add(line)
    check result == @["hello", "world"]

  test "lines iterator with empty last line":
    let r = newRope("hello\n\n")
    var result: seq[string] = @[]
    for line in r.lines:
      result.add(line)
    check result == @["hello", ""]

  test "lines iterator with single line":
    let r = newRope("hello")
    var result: seq[string] = @[]
    for line in r.lines:
      result.add(line)
    check result == @["hello"]

  test "lines iterator with empty line in middle":
    let r = newRope("a\n\nb")
    var result: seq[string] = @[]
    for line in r.lines:
      result.add(line)
    check result == @["a", "", "b"]

  test "lines iterator with empty rope":
    let r = newRope()
    var result: seq[string] = @[]
    for line in r.lines:
      result.add(line)
    check result == @[""]

  test "lines iterator with two empty lines":
    let r = newRope("\n\n")
    var result: seq[string] = @[]
    for line in r.lines:
      result.add(line)
    check result == @["", ""]

  test "chars iterator with single line":
    let r = newRope("hello")
    var s = ""
    for ch in r.chars:
      s.add(ch)
    check s == "hello"
    check s == $r

  test "chars iterator with empty rope":
    let r = newRope()
    var s = ""
    for ch in r.chars:
      s.add(ch)
    check s == ""
    check s == $r

  test "toString with single line":
    let r = newRope("hello")
    check $r == "hello"

  test "toString with empty rope":
    let r = newRope()
    check $r == ""

suite "Rope - Replace Line":
  test "replaceLine":
    let r = newRope("hello\nworld")
    r.replaceLine(0, "hi")
    check r[0] == "hi"
    check r[1] == "world"

  test "modifyLineContent":
    let r = newRope("hello\nworld")
    r.modifyLineContent(
      0,
      proc(s: var string) =
        s = s.toUpperAscii(),
    )
    check r[0] == "HELLO"
    check r[1] == "world"

suite "Rope - Memory and Info":
  test "estimateMemoryUsage":
    let r = newRope("hello\nworld")
    check r.estimateMemoryUsage() > 0

  test "getTreeInfo":
    let r = newRope("hello\nworld")
    let info = r.getTreeInfo()
    check info.totalBytes > 0
    check info.leafCount >= 1
