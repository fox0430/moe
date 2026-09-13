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

## Line-level diff, for putting a filter's answer back into a buffer. Trimming
## the common head and tail is not enough: one change near the top and one near
## the bottom leave everything between them in the span, and rewriting the span
## would move every marker, fold and bookmark inside it.

import std/[algorithm, tables]

type
  LineEdit* = object
    ## Replace the `delete` lines at `start` with `insert`, indexing the old text.
    ## Hunks are ascending and non-overlapping.
    start*: int
    delete*: int
    insert*: seq[string]

  LineDiff* = object
    ## The hunks that turn one text into another. `exact = false`: the search gave
    ## up before finding a minimal script. `coarse = true`: a hunk covers a whole
    ## differing span, rewriting the lines in it wholesale, so what was attached
    ## to them cannot be carried across.
    hunks*: seq[LineEdit]
    exact*: bool
    coarse*: bool

  ScriptOpKind = enum
    sokMatch
    sokDelete
    sokInsert

  ScriptOp = tuple[kind: ScriptOpKind, oldIdx, newIdx: int]

const
  MaxDiffDistance* = 512
    ## Edit distance past which the diff answers with one hunk over everything.
    ## The recorded trace costs O(D^2) and a rewrite this large preserves nothing.
  MaxDiffWork = 20_000_000
    ## Ceiling on the search, counted as steps spent: a filter runs on the
    ## editor's thread, so a pathological span settles for a coarser answer
    ## rather than a slow one.

proc coarseHunk(
    new: openArray[string], prefix, n, m: int
): seq[LineEdit] {.raises: [].} =
  ## One hunk over the whole differing span.
  if n == 0 and m == 0:
    return @[]
  @[LineEdit(start: prefix, delete: n, insert: @(new[prefix ..< prefix + m]))]

proc backtrack(
    trace: seq[seq[int]], found, prefix, n, m: int
): seq[ScriptOp] {.raises: [].} =
  ## Walk the recorded Myers trace backwards into an edit script, in order.
  var
    ops: seq[ScriptOp]
    x = n
    y = m
  for d in countdown(found, 1):
    let
      vPrev = trace[d - 1]
      k = x - y
      # `k == -d` cannot read k-1, and `k == d` cannot read k+1; between them
      # both neighbours are in range at level d-1.
      useUp =
        k == -d or
        (k != d and vPrev[(k - 1 + d - 1) div 2] < vPrev[(k + 1 + d - 1) div 2])
      prevK =
        if useUp:
          k + 1
        else:
          k - 1
      prevX = vPrev[(prevK + d - 1) div 2]
      prevY = prevX - prevK
    while x > prevX and y > prevY:
      dec x
      dec y
      ops.add (sokMatch, prefix + x, prefix + y)
    if useUp:
      dec y
      ops.add (sokInsert, prefix + x, prefix + y)
    else:
      dec x
      ops.add (sokDelete, prefix + x, prefix + y)
  while x > 0 and y > 0:
    dec x
    dec y
    ops.add (sokMatch, prefix + x, prefix + y)
  ops.reverse
  ops

proc toHunks(new: openArray[string], ops: seq[ScriptOp], prefix: int): seq[LineEdit] =
  ## Group runs of non-matching ops into hunks; `oldPos` places a pure insertion
  ## in the old text.
  var
    hunks: seq[LineEdit]
    idx = 0
    oldPos = prefix
  while idx < ops.len:
    if ops[idx].kind == sokMatch:
      inc oldPos
      inc idx
      continue

    var hunk = LineEdit(start: oldPos, delete: 0, insert: @[])
    while idx < ops.len and ops[idx].kind != sokMatch:
      case ops[idx].kind
      of sokDelete:
        inc hunk.delete
        inc oldPos
      of sokInsert:
        hunk.insert.add new[ops[idx].newIdx]
      of sokMatch:
        discard
      inc idx
    hunks.add hunk
  hunks

proc lowerBoundDistance(
    old, new: openArray[string], prefix, n, m: int
): int {.raises: [].} =
  ## Lowest possible edit distance for the span: every line without a partner
  ## needs an operation of its own. Costs one scan, so it can rule out the Myers
  ## search before its full price is paid.
  var counts = initTable[string, int]()
  for i in 0 ..< n:
    counts.mgetOrPut(old[prefix + i], 0).inc
  var shared = 0
  for j in 0 ..< m:
    let line = new[prefix + j]
    let remaining = counts.getOrDefault(line, 0)
    if remaining > 0:
      counts[line] = remaining - 1
      inc shared
  (n - shared) + (m - shared)

proc diffLines*(old, new: openArray[string], maxDistance = MaxDiffDistance): LineDiff =
  ## The hunks that turn `old` into `new`; empty when they already agree. The
  ## common head and tail are trimmed by scan before the distance is measured.
  let
    oldLen = old.len
    newLen = new.len
  var prefix = 0
  while prefix < oldLen and prefix < newLen and old[prefix] == new[prefix]:
    inc prefix

  var suffix = 0
  while suffix < oldLen - prefix and suffix < newLen - prefix and
      old[oldLen - 1 - suffix] == new[newLen - 1 - suffix]:
    inc suffix

  let
    n = oldLen - suffix - prefix
    m = newLen - suffix - prefix
  # A pure insertion or a pure deletion is already minimal: one side holds
  # nothing in the span, so no line is rewritten over another.
  if n == 0 or m == 0:
    return LineDiff(hunks: coarseHunk(new, prefix, n, m), exact: true, coarse: false)

  let
    maxD = min(n + m, maxDistance)
    lowerBound = lowerBoundDistance(old, new, prefix, n, m)
    # A full-rewrite lower bound means the two sides share no line, so every
    # line in the span is rewritten over an unrelated one however the script is
    # found. Read it here too, so the answer does not turn on whether the span
    # fit under the ceiling.
    sharesNoLine = lowerBound == n + m
  if lowerBound > maxD:
    # No script can be short enough, so the search would only run to the
    # ceiling and throw its answer away. The shared-no-line case makes the
    # coarse hunk minimal too, and it is still a wholesale rewrite either way.
    return
      LineDiff(hunks: coarseHunk(new, prefix, n, m), exact: sharesNoLine, coarse: true)

  let offset = maxD + 1
  var
    v = newSeq[int](2 * maxD + 3)
    trace: seq[seq[int]]
    found = -1
    work = 0
  for d in 0 .. maxD:
    # Only the diagonals k = -d, -d+2, .. d are written, so d+1 slots hold the
    # level; the full-diagonal width belongs to `v`, not to the trace.
    var snapshot = newSeq[int](d + 1)
    for k in countup(-d, d, 2):
      var x =
        if k == -d or (k != d and v[offset + k - 1] < v[offset + k + 1]):
          v[offset + k + 1]
        else:
          v[offset + k - 1] + 1
      var y = x - k
      inc work
      while x < n and y < m and old[prefix + x] == new[prefix + y]:
        inc x
        inc y
        inc work
      v[offset + k] = x
      snapshot[(k + d) div 2] = x
      if x >= n and y >= m:
        found = d
        break
    trace.add snapshot
    if found >= 0:
      break
    if work > MaxDiffWork:
      # Budget spent without reaching the end. The level just finished is
      # abandoned whole, so the trace never holds a partial one.
      break

  if found < 0:
    # Further apart than `maxDistance`, or dearer than the budget.
    return LineDiff(hunks: coarseHunk(new, prefix, n, m), exact: false, coarse: true)

  LineDiff(
    hunks: toHunks(new, backtrack(trace, found, prefix, n, m), prefix),
    exact: true,
    coarse: sharesNoLine,
  )
