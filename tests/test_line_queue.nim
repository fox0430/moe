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

import std/[strutils, unittest]

import ../src/moepkg/line_queue

proc split(
    chunks: openArray[string], separator = '\n', maxLines = 0, maxLineBytes = 0
): seq[string] =
  ## What the queue holds after `chunks` are read to the end.
  let q = newLineQueue()
  var s = initLineSplitter(separator, maxLines, maxLineBytes)
  for chunk in chunks:
    check s.feed(q, chunk) == chunk.len
  check not s.overLimit
  s.finish(q)
  q.take(high(int))

suite "LineSplitter - where lines end":
  test "The text after the last separator is a line":
    check split(["a\nb\nc"]) == @["a", "b", "c"]

  test "A separator at the end makes no empty line":
    check split(["a\nb\n"]) == @["a", "b"]

  test "An empty line between two is kept":
    check split(["a\n\nb\n"]) == @["a", "", "b"]

  test "No output is no line":
    check split([""]).len == 0

  test "A line split across reads is joined":
    check split(["ab", "c\nd", "e\n"]) == @["abc", "de"]
    check split(["a", "\n", "\nb"]) == @["a", "", "b"]

  test "With NUL as the separator a newline stays inside the line":
    check split(["a b\nc\0d\0"], separator = '\0') == @["a b\nc", "d"]

suite "LineSplitter - bounds":
  test "A long line keeps its start, and the rest of it is dropped":
    check split(["abcdefg\nxy\n"], maxLineBytes = 4) == @["abcd", "xy"]
    check split(["ab", "cdef", "g\nxy"], maxLineBytes = 4) == @["abcd", "xy"]

  test "A cut never leaves part of a character":
    # "あ" and "い" take three bytes each.
    check split(["aあい\n"], maxLineBytes = 4) == @["aあ"]
    check split(["aあい\n"], maxLineBytes = 5) == @["aあ"]
    check split(["aあい\n"], maxLineBytes = 6) == @["aあ"]
    check split(["aあい\n"], maxLineBytes = 7) == @["aあい"]

  test "As many lines as the limit is not past it":
    check split(["a\nb\n"], maxLines = 2) == @["a", "b"]
    check split(["a\nb"], maxLines = 2) == @["a", "b"]

  test "The line past the limit is not queued, and the feed says so":
    let q = newLineQueue()
    var s = initLineSplitter('\n', maxLines = 2)
    check s.feed(q, "a\nb\nc\nd\n") == 4
    check s.overLimit
    check q.take(10) == @["a", "b"]

  test "The first byte past the limit is enough, before its line ends":
    let q = newLineQueue()
    var s = initLineSplitter('\n', maxLines = 2)
    check s.feed(q, "a\nb\n") == 4
    check not s.overLimit
    check s.feed(q, "c") == 0
    check s.overLimit
    check q.take(10) == @["a", "b"]

  test "An empty line past the limit is past it too":
    let q = newLineQueue()
    var s = initLineSplitter('\n', maxLines = 2)
    check s.feed(q, "a\nb\n\n") == 4
    check s.overLimit

suite "LineSplitter - a full queue":
  test "The feed stops at the line that fills the queue, and the rest comes later":
    let q = newLineQueue(capacity = 4)
    var s = initLineSplitter('\n')
    let data = "ab\ncd\nef\ng"
    check s.feed(q, data) == 6
    check q.full
    check q.take(10) == @["ab", "cd"]
    check s.feed(q, data.toOpenArray(6, data.high)) == data.len - 6
    s.finish(q)
    check q.take(10) == @["ef", "g"]

  test "A line that has not ended is taken whole, however little room is left":
    let q = newLineQueue(capacity = 4)
    q.add "ab"
    var s = initLineSplitter('\n', maxLineBytes = 8)
    let long = 'x'.repeat(100)
    check s.feed(q, long) == long.len
    check q.len == 1

suite "LineQueue":
  test "Lines are taken oldest first, up to the number asked":
    let q = newLineQueue()
    q.add "a"
    q.add "b"
    q.add "c"
    check q.take(2) == @["a", "b"]
    check q.len == 1
    check q.take(5) == @["c"]
    check q.take(5).len == 0

  test "Full once the bytes queued reach the capacity":
    let q = newLineQueue(capacity = 6)
    q.add "ab"
    check not q.full
    q.add "cd"
    check q.full
    discard q.take(1)
    check not q.full

  test "A wait for room is woken once takes leave half the capacity, and only once":
    let q = newLineQueue(capacity = 8)
    q.add "abc"
    q.add "def"
    var woken = 0
    q.onRoom(
      proc() =
        inc woken
    )
    check woken == 0
    discard q.take(1)
    check woken == 1
    discard q.take(1)
    check woken == 1

  test "A take that leaves more than half the capacity does not wake it":
    let q = newLineQueue(capacity = 8)
    q.add "a"
    q.add "b"
    q.add "c"
    q.add "d"
    var woken = 0
    q.onRoom(
      proc() =
        inc woken
    )
    discard q.take(1)
    check not q.full
    check woken == 0
    discard q.take(1)
    check woken == 1

  test "A wait for room on a queue with room runs at once":
    let q = newLineQueue(capacity = 100)
    var woken = 0
    q.onRoom(
      proc() =
        inc woken
    )
    check woken == 1
    q.add "a"
    discard q.take(1)
    check woken == 1

  test "A dropped wait is not woken":
    let q = newLineQueue(capacity = 2)
    q.add "ab"
    var woken = 0
    q.onRoom(
      proc() =
        inc woken
    )
    q.onRoom(nil)
    discard q.take(1)
    check woken == 0

  test "Drained once the run has ended and every line is taken":
    let q = newLineQueue()
    q.add "a"
    check not q.drained
    q.ended = true
    check not q.drained
    discard q.take(1)
    check q.drained

suite "cutLines":
  test "Cuts a whole text as a stream of it would be":
    check cutLines("a\n\nb\nc", '\n') == @["a", "", "b", "c"]
    check cutLines("a\n", '\n') == @["a"]
    check cutLines("\n", '\n') == @[""]
    check cutLines("", '\n').len == 0

  test "A long line is kept whole":
    let line = 'x'.repeat(DefaultMaxLineBytes * 2)
    check cutLines(line & "\n", '\n') == @[line]
