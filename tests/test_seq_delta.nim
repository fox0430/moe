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

## Unit tests for SeqDelta: a bidirectional positional diff. The round-trip
## invariant (applyUndo . applyRedo == identity, and vice versa) must hold for
## same-length, growing, and shrinking transitions.

import std/unittest

import ../src/moepkg/buffer/seq_delta

proc roundTrip(pre, post: seq[int]) =
  ## A single delta must drive `pre -> post` and `post -> pre`.
  let d = computeDelta(pre, post)

  var fwd = pre
  applyRedo(fwd, d)
  check fwd == post

  var back = post
  applyUndo(back, d)
  check back == pre

suite "SeqDelta round-trip":
  test "same length, single change":
    roundTrip(@[0, 0, 0], @[0, 1, 0])

  test "same length, multiple changes":
    roundTrip(@[1, 2, 3, 4], @[9, 2, 8, 4])

  test "no change":
    roundTrip(@[1, 2, 3], @[1, 2, 3])

  test "grow (append)":
    roundTrip(@[1, 2], @[1, 2, 3, 4])

  test "grow with change in common range":
    roundTrip(@[1, 2], @[5, 2, 3])

  test "shrink (truncate)":
    roundTrip(@[1, 2, 3, 4], @[1, 2])

  test "shrink with change in common range":
    roundTrip(@[1, 2, 3, 4], @[1, 9])

  test "empty to non-empty":
    roundTrip(@[], @[1, 2, 3])

  test "non-empty to empty":
    roundTrip(@[1, 2, 3], @[])

  test "empty to empty":
    roundTrip(@[], @[])

  test "grow where appended values equal default(T) still round-trips":
    # The delta stores default(T) as the old value for appended tail entries.
    # When the appended value itself equals default(T), the resize/guard logic
    # must still produce the correct lengths on undo.
    roundTrip(@[1, 2], @[1, 2, 0, 0])

  test "shrink where dropped values equal default(T) still round-trips":
    # Symmetric case: dropped tail entries whose old value equals default(T)
    # must still be restored on redo (grow direction).
    roundTrip(@[1, 2, 0, 0], @[1, 2])

suite "SeqDelta is bidirectional / reusable":
  test "same delta applied repeatedly stays consistent":
    let pre = @[1, 2, 3]
    let post = @[1, 5, 3, 7]
    let d = computeDelta(pre, post)

    # Simulate undo/redo ping-pong reusing one delta object.
    var arr = pre
    applyRedo(arr, d)
    check arr == post
    applyUndo(arr, d)
    check arr == pre
    applyRedo(arr, d)
    check arr == post

  test "delta stores lengths":
    let d = computeDelta(@[1, 2, 3], @[1, 2])
    check d.oldLen == 3
    check d.newLen == 2

  test "delta records only differing indices":
    let d = computeDelta(@[1, 2, 3], @[1, 9, 3])
    check d.edits.len == 1
    check d.edits[0].idx == 1
