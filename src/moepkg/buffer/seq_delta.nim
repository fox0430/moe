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

## Bidirectional positional delta between two seqs.
##
## A `SeqDelta` records, for every index where the two seqs differ (plus the
## tail when lengths differ), both the old and the new value, along with both
## lengths. The same delta therefore drives undo (`applyUndo`) and redo
## (`applyRedo`) — no separate forward/backward objects.
##
## Used to store per-line undo metadata (e.g. `modifiedLines`) for PieceTable
## snapshot undo entries: an entry keeps O(changed lines) instead of a full
## O(lines) copy, so a long undo history does not grow with file size.
##
## Generic over the element type to stay free of buffer-layer imports. A tail
## entry stores `default(T)` in its unused slot (the old value of an added entry,
## or the new value of a dropped one). That placeholder is never written to the
## live array: applyUndo/applyRedo resize first, so the tail index falls outside
## the resized length and the guard skips it.

type
  SeqEdit[T] = tuple[idx: int, oldVal, newVal: T]

  SeqDelta*[T] = object
    oldLen*: int
    newLen*: int
    edits*: seq[SeqEdit[T]]

proc computeDelta*[T](pre, post: seq[T]): SeqDelta[T] =
  ## Build the delta transforming `pre` into `post` (and back).
  result.oldLen = pre.len
  result.newLen = post.len
  let common = min(pre.len, post.len)
  for i in 0 ..< common:
    if pre[i] != post[i]:
      result.edits.add((i, pre[i], post[i]))
  let filler = default(T)
  for i in common ..< pre.len: # present in pre, dropped in post
    result.edits.add((i, pre[i], filler))
  for i in common ..< post.len: # absent in pre, added in post
    result.edits.add((i, filler, post[i]))

proc applyUndo*[T](arr: var seq[T], delta: SeqDelta[T]) =
  ## Transform `arr` (expected to equal the delta's *new* state) back to the
  ## *old* state. Resizing first means out-of-range edits (added tail) are
  ## simply truncated away; the guard handles them.
  arr.setLen(delta.oldLen)
  for e in delta.edits:
    if e.idx < arr.len:
      arr[e.idx] = e.oldVal

proc applyRedo*[T](arr: var seq[T], delta: SeqDelta[T]) =
  ## Transform `arr` (expected to equal the delta's *old* state) forward to the
  ## *new* state. Symmetric inverse of `applyUndo`.
  arr.setLen(delta.newLen)
  for e in delta.edits:
    if e.idx < arr.len:
      arr[e.idx] = e.newVal
