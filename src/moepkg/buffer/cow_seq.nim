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

## Copy-on-write sequence with value semantics.
##
## Behaves like a `seq[T]` but copies share the underlying storage until one
## side mutates, at which point only the mutating side clones. The `=copy` hook
## marks the shared node frozen so a later write through *either* alias clones
## instead of corrupting the other.
##
## Used for undo snapshots of per-line side arrays (e.g. `lineMarkers`): an
## arbitrarily long undo history can hold many snapshots that share one frozen
## array, so capturing a snapshot is O(1) and a clone happens only when the
## array actually changes — not once per edit.

type
  CowSeqNode[T] = ref object
    data: seq[T]
    frozen: bool ## True once referenced by more than one CowSeq; next write clones.

  CowSeq*[T] = object
    node: CowSeqNode[T]

proc `=copy`*[T](dst: var CowSeq[T], src: CowSeq[T]) =
  ## Share `src`'s storage and freeze it so the next write through either alias
  ## clones rather than mutating shared data.
  if dst.node == src.node:
    return
  if src.node != nil:
    src.node.frozen = true
  dst.node = src.node

proc ensureUnique[T](cs: var CowSeq[T]) {.inline.} =
  ## Guarantee `cs` owns an unshared node before mutation.
  if cs.node == nil:
    cs.node = CowSeqNode[T](data: @[], frozen: false)
  elif cs.node.frozen:
    cs.node = CowSeqNode[T](data: cs.node.data, frozen: false)

proc initCowSeq*[T](len: int): CowSeq[T] =
  CowSeq[T](node: CowSeqNode[T](data: newSeq[T](len), frozen: false))

proc initCowSeq*[T](s: sink seq[T]): CowSeq[T] =
  CowSeq[T](node: CowSeqNode[T](data: s, frozen: false))

proc sharesStorage*[T](a, b: CowSeq[T]): bool =
  ## Whether `a` and `b` still share storage, i.e. neither has written since
  ## the copy. Lets a caller verify that a write it expected to be free was.
  a.node == b.node

proc len*[T](cs: CowSeq[T]): int {.inline.} =
  if cs.node == nil: 0 else: cs.node.data.len

proc `[]`*[T](cs: CowSeq[T], i: int): T {.inline.} =
  # Match `len`'s nil handling: a default/cleared CowSeq is an empty seq, so any
  # index raises a catchable IndexDefect instead of dereferencing a nil node.
  if cs.node == nil:
    raise newException(IndexDefect, "index out of bounds: CowSeq is empty")
  cs.node.data[i]

proc `[]=`*[T](cs: var CowSeq[T], i: int, v: T) {.inline.} =
  cs.ensureUnique()
  cs.node.data[i] = v

proc add*[T](cs: var CowSeq[T], v: T) =
  cs.ensureUnique()
  cs.node.data.add(v)

proc setLen*[T](cs: var CowSeq[T], n: int) =
  cs.ensureUnique()
  cs.node.data.setLen(n)

proc insert*[T](cs: var CowSeq[T], v: T, i: int) =
  cs.ensureUnique()
  cs.node.data.insert(v, i)

proc insert*[T](cs: var CowSeq[T], v: T, i, count: int) =
  ## Insert `count` copies of `v` at `i`, moving the tail once; looping the
  ## single-element overload would be quadratic on a whole-span rewrite. An `i`
  ## outside 0..len raises like that overload.
  if count <= 0:
    return
  let oldLen = cs.len
  if i < 0 or i > oldLen:
    raise newException(IndexDefect, "index out of range: " & $i)
  cs.ensureUnique()
  cs.node.data.setLen(oldLen + count)
  for j in countdown(oldLen - 1, i):
    cs.node.data[j + count] = cs.node.data[j]
  for j in 0 ..< count:
    cs.node.data[i + j] = v

proc delete*[T](cs: var CowSeq[T], i: int) =
  cs.ensureUnique()
  cs.node.data.delete(i)

proc delete*[T](cs: var CowSeq[T], i, count: int) =
  ## Drop `count` elements from `i`, moving the tail once. Stops at the end
  ## rather than raising if `count` overruns; an `i` past the end raises like
  ## the single-element overload.
  if count <= 0:
    return
  let oldLen = cs.len
  if i < 0 or i > oldLen:
    raise newException(IndexDefect, "index out of range: " & $i)
  let removable = min(count, oldLen - i)
  if removable <= 0:
    # Nothing to drop: return before `ensureUnique` so a no-op never clones a
    # frozen node shared with an undo snapshot.
    return
  cs.ensureUnique()
  for j in i ..< oldLen - removable:
    cs.node.data[j] = cs.node.data[j + removable]
  cs.node.data.setLen(oldLen - removable)

proc clear*[T](cs: var CowSeq[T]) {.inline.} =
  ## Drop the reference to the (possibly shared) storage, leaving an empty seq.
  ## Cheaper than `setLen(0)` because it never clones a frozen node.
  cs.node = nil
