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

## Unit tests for CowSeq: value semantics with copy-on-write sharing.
## The critical invariant is that a copy never observes a later mutation of the
## original (no aliasing), even though copies share storage until written.

import std/unittest

import ../src/moepkg/buffer/cow_seq

suite "CowSeq basics":
  test "initCowSeq with length is zero-filled":
    let cs = initCowSeq[int](3)
    check cs.len == 3
    check cs[0] == 0
    check cs[1] == 0
    check cs[2] == 0

  test "initCowSeq from seq adopts contents":
    let cs = initCowSeq(@[1, 2, 3])
    check cs.len == 3
    check cs[0] == 1
    check cs[2] == 3

  test "index assignment":
    var cs = initCowSeq[int](2)
    cs[0] = 10
    cs[1] = 20
    check cs[0] == 10
    check cs[1] == 20

  test "add / setLen / insert / delete":
    var cs = initCowSeq[int](0)
    cs.add(1)
    cs.add(3)
    cs.insert(2, 1)
    check cs.len == 3
    check cs[0] == 1
    check cs[1] == 2
    check cs[2] == 3
    cs.delete(1)
    check cs.len == 2
    check cs[1] == 3
    cs.setLen(1)
    check cs.len == 1

  test "len of default (nil node) CowSeq is zero":
    var cs: CowSeq[int]
    check cs.len == 0
    cs.add(5) # mutation on a nil-node value must allocate, not crash
    check cs.len == 1
    check cs[0] == 5

  test "indexing a default (nil node) CowSeq raises IndexDefect, not segfault":
    var cs: CowSeq[int]
    expect IndexDefect:
      discard cs[0]

suite "CowSeq copy-on-write semantics":
  test "copy does not observe later write to original":
    var a = initCowSeq(@[1, 2, 3])
    let b = a
    a[0] = 99
    check a[0] == 99
    check b[0] == 1 # b must be unaffected

  test "copy does not observe later write to the copy":
    let a = initCowSeq(@[1, 2, 3])
    var b = a
    b[2] = 99
    check b[2] == 99
    check a[2] == 3

  test "structural mutations on a copy do not affect the original":
    var a = initCowSeq(@[1, 2, 3])
    var b = a
    b.add(4)
    b.delete(0)
    check a.len == 3
    check a[0] == 1
    check b.len == 3
    check b[0] == 2

  test "chained copies are each independent":
    var a = initCowSeq(@[0, 0])
    var b = a
    a[0] = 1
    var c = b
    b[0] = 2
    c[0] = 3
    check a[0] == 1
    check b[0] == 2
    check c[0] == 3

  test "writing twice after a copy clones only once (still correct)":
    var a = initCowSeq(@[1, 2, 3])
    let snapshot = a
    a[0] = 10
    a[1] = 20 # second write hits the already-unique node
    check a[0] == 10
    check a[1] == 20
    check snapshot[0] == 1
    check snapshot[1] == 2

  test "clear leaves prior copy intact":
    var a = initCowSeq(@[1, 2, 3])
    let b = a
    a.clear()
    check a.len == 0
    check b.len == 3
    check b[0] == 1

  test "setLen grow after a copy clones instead of mutating the shared node":
    # ensureMarkersSize grows lineMarkers via setLen after a snapshot copy froze
    # the node; the grow must clone, leaving the snapshot's length/contents intact.
    var a = initCowSeq(@[1, 2, 3])
    let snapshot = a
    a.setLen(5)
    check a.len == 5
    check a[0] == 1
    check a[3] == 0 # grown slots default-filled
    check a[4] == 0
    check snapshot.len == 3 # snapshot must not see the grow
    check snapshot[2] == 3

  test "insert after a copy clones instead of mutating the shared node":
    var a = initCowSeq(@[1, 2, 3])
    let snapshot = a
    a.insert(99, 1)
    check a.len == 4
    check a[1] == 99
    check snapshot.len == 3
    check snapshot[1] == 2

suite "CowSeq bulk splice":
  ## The per-line side arrays shift by a whole hunk at a time, so the bulk
  ## overloads have to agree with a loop over the single-element ones.
  proc toSeq(cs: CowSeq[int]): seq[int] =
    for i in 0 ..< cs.len:
      result.add cs[i]

  test "insert of n copies matches n single inserts":
    for i in 0 .. 4:
      for count in 0 .. 3:
        var bulk = initCowSeq(@[0, 1, 2, 3])
        var oneByOne = initCowSeq(@[0, 1, 2, 3])
        bulk.insert(9, i, count)
        for _ in 0 ..< count:
          oneByOne.insert(9, i)
        check bulk.toSeq == oneByOne.toSeq

  test "delete of n matches n single deletes":
    for i in 0 .. 4:
      for count in 0 .. 3:
        var bulk = initCowSeq(@[0, 1, 2, 3])
        var oneByOne = initCowSeq(@[0, 1, 2, 3])
        bulk.delete(i, count)
        for _ in 0 ..< min(count, 4 - i):
          oneByOne.delete(i)
        check bulk.toSeq == oneByOne.toSeq

  test "delete past the end stops there instead of raising":
    var cs = initCowSeq(@[0, 1, 2])
    cs.delete(1, 99)
    check cs.toSeq == @[0]

  test "a zero count is a no-op":
    var cs = initCowSeq(@[0, 1, 2])
    cs.insert(9, 1, 0)
    cs.delete(1, 0)
    check cs.toSeq == @[0, 1, 2]

  test "a delete with nothing to drop leaves the shared node alone":
    # `shiftPerLineArray` deletes at the end of a shorter array on purpose, so
    # a no-op delete is a normal event: it must not clone a node an undo
    # snapshot shares, which is the whole point of the type.
    var cs = initCowSeq(@[0, 1, 2])
    let snapshot = cs
    cs.delete(3, 2)
    check cs.sharesStorage(snapshot)
    check cs.toSeq == @[0, 1, 2]

  test "an index past the end raises like the single-element overload":
    # The single-element `delete` and `insert` delegate to seq, which raises
    # IndexDefect out of range; the bulk overloads must not silently swallow
    # it. Deleting from the very end is a no-op, not an error.
    var cs = initCowSeq(@[0, 1, 2])
    expect IndexDefect:
      cs.delete(5, 2)
    expect IndexDefect:
      cs.insert(9, 5, 2)
    expect IndexDefect:
      cs.insert(9, -1, 2)
    check cs.toSeq == @[0, 1, 2]

  test "bulk writes after a copy clone instead of mutating the shared node":
    var a = initCowSeq(@[1, 2, 3])
    let afterInsert = a
    a.insert(9, 1, 2)
    check a.toSeq == @[1, 9, 9, 2, 3]
    check afterInsert.toSeq == @[1, 2, 3]

    var b = initCowSeq(@[1, 2, 3])
    let afterDelete = b
    b.delete(0, 2)
    check b.toSeq == @[3]
    check afterDelete.toSeq == @[1, 2, 3]
