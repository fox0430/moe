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

import std/[algorithm, unittest]

import ../src/moepkg/buffer/line_diff

proc apply(old: seq[string], hunks: seq[LineEdit]): seq[string] =
  ## The old text with `hunks` applied.
  result = old
  for i in countdown(hunks.high, 0):
    let hunk = hunks[i]
    result[hunk.start ..< hunk.start + hunk.delete] = hunk.insert

suite "line_diff - diffLines":
  test "Identical texts have no hunks":
    check diffLines(@["a", "b", "c"], @["a", "b", "c"]).hunks.len == 0

  test "Two scattered changes stay two hunks":
    let
      old = @["a", "b", "c", "d", "e", "f", "g"]
      new = @["a", "B", "c", "d", "e", "F", "g"]
      hunks = diffLines(old, new).hunks
    check hunks.len == 2
    check hunks[0].start == 1
    check hunks[0].delete == 1
    check hunks[0].insert == @["B"]
    check hunks[1].start == 5
    check hunks[1].delete == 1
    check hunks[1].insert == @["F"]
    check old.apply(hunks) == new

  test "An untouched line between two changes is left alone":
    # The point of the diff: the coarse span would rewrite "middle" too.
    let
      old = @["head", "x", "middle", "y", "tail"]
      new = @["head", "X", "middle", "Y", "tail"]
      hunks = diffLines(old, new).hunks
    check hunks.len == 2
    for hunk in hunks:
      check hunk.insert != @["middle"]
    check old.apply(hunks) == new

  test "A pure insertion deletes nothing":
    let
      old = @["a", "b"]
      new = @["a", "x", "y", "b"]
      hunks = diffLines(old, new).hunks
    check hunks.len == 1
    check hunks[0].delete == 0
    check hunks[0].start == 1
    check hunks[0].insert == @["x", "y"]
    check old.apply(hunks) == new

  test "A pure deletion inserts nothing":
    let
      old = @["a", "x", "y", "b"]
      new = @["a", "b"]
      hunks = diffLines(old, new).hunks
    check hunks.len == 1
    check hunks[0].start == 1
    check hunks[0].delete == 2
    check hunks[0].insert.len == 0
    check old.apply(hunks) == new

  test "Repeated lines are matched without drifting":
    let
      old = @["x", "x", "x", "a"]
      new = @["x", "x", "x", "x", "a"]
      hunks = diffLines(old, new).hunks
    check old.apply(hunks) == new

  test "Beyond the distance bound one hunk covers everything":
    # Every line has a partner, so the search runs; reversing them puts the
    # answer far past a distance of 4.
    var old: seq[string]
    for i in 0 ..< 40:
      old.add "line" & $i
    let new = block:
      var reversedLines = old
      reversedLines.reverse
      reversedLines
    let diff = diffLines(old, new, maxDistance = 4)
    check not diff.exact
    check diff.hunks.len == 1
    check diff.hunks[0].start == 0
    check diff.hunks[0].delete == 40
    check old.apply(diff.hunks) == new

  test "A reformat of every line round-trips":
    var
      old: seq[string]
      new: seq[string]
    for i in 0 ..< 200:
      old.add "    line " & $i
      new.add "line " & $i
    check old.apply(diffLines(old, new).hunks) == new

  test "Interleaved edits round-trip":
    var
      old: seq[string]
      new: seq[string]
    for i in 0 ..< 100:
      old.add "l" & $i
      if i mod 7 == 0:
        new.add "L" & $i
      elif i mod 11 != 0:
        new.add "l" & $i
      if i mod 13 == 0:
        new.add "extra" & $i
    check old.apply(diffLines(old, new).hunks) == new

suite "line_diff - exactness":
  test "A minimal script says so":
    check diffLines(@["a", "b", "c"], @["a", "B", "c"]).exact

  test "Texts that already agree are an exact answer":
    check diffLines(@["a", "b"], @["a", "b"]).exact

  test "A pure insertion or deletion is exact without searching":
    check diffLines(@["a", "b"], @["a", "x", "b"]).exact
    check diffLines(@["a", "x", "b"], @["a", "b"]).exact
    # Nothing is rewritten over anything, so neither is coarse.
    check not diffLines(@["a", "b"], @["a", "x", "b"]).coarse
    check not diffLines(@["a", "x", "b"], @["a", "b"]).coarse

  test "A span that cannot fit under the bound is refused before searching":
    # The lower bound rules it out: half of the lines have no partner, so at
    # least 40 operations are needed and the bound allows 4.
    var
      old: seq[string]
      new: seq[string]
    for i in 0 ..< 40:
      old.add "line" & $i
      new.add (if i mod 2 == 0: "line" & $i else: "other" & $i)
    check not diffLines(old, new, maxDistance = 4).exact
    check diffLines(old, new, maxDistance = 4).coarse

  test "A span sharing no line at all is coarse but still minimal":
    # Nothing can be preserved, so deleting everything and inserting everything
    # is the minimal script: the coarse hunk is the exact answer.
    var
      old: seq[string]
      new: seq[string]
    for i in 0 ..< 40:
      old.add "old" & $i
      new.add "new" & $i
    let diff = diffLines(old, new, maxDistance = 4)
    check diff.exact
    # Minimal, but still a wholesale rewrite of the span: nothing on those
    # lines can be carried across.
    check diff.coarse
    check diff.hunks.len == 1
    check old.apply(diff.hunks) == new

  test "Sharing no line is coarse whether or not the search runs":
    # Same shape as above but small enough for the search to succeed, so the
    # answer comes from Myers rather than from the give-up path. It is still a
    # wholesale rewrite, and the classification must not turn on the size.
    var
      old: seq[string]
      new: seq[string]
    for i in 0 ..< 8:
      old.add "old" & $i
      new.add "new" & $i
    let diff = diffLines(old, new)
    check diff.exact
    check diff.coarse
    check diff.hunks.len == 1
    check old.apply(diff.hunks) == new

  test "Shared lines count towards the bound, so a near match still searches":
    # Same size as above, but only two lines differ: a distance of 4 is enough.
    var
      old: seq[string]
      new: seq[string]
    for i in 0 ..< 40:
      old.add "line" & $i
      new.add (if i == 7 or i == 21: "changed" & $i else: "line" & $i)
    let diff = diffLines(old, new, maxDistance = 4)
    check diff.exact
    check not diff.coarse
    check diff.hunks.len == 2
    check old.apply(diff.hunks) == new

suite "line_diff - bounds":
  test "A file too far from the replacement settles for a coarser answer":
    # Past the distance bound, so inexact: the in-between lines moved.
    var
      old: seq[string]
      new: seq[string]
    for i in 0 ..< 60000:
      old.add "line " & $i
      new.add (if i mod 100 == 0: "changed " & $i else: "line " & $i)
    let diff = diffLines(old, new)
    check not diff.exact
    check old.apply(diff.hunks) == new

  test "A large file with few changes still gets the minimal script":
    # Changes at both ends of the file, so the span between them is everything.
    var
      old: seq[string]
      new: seq[string]
    for i in 0 ..< 50000:
      old.add "line " & $i
      new.add (if i mod 1000 == 0: "changed " & $i else: "line " & $i)
    let diff = diffLines(old, new)
    check diff.exact
    check diff.hunks.len == 50
    check old.apply(diff.hunks) == new

  test "A small file gets the minimal script":
    var
      old: seq[string]
      new: seq[string]
    for i in 0 ..< 2000:
      old.add "line " & $i
      new.add (if i mod 100 == 0: "changed " & $i else: "line " & $i)
    let diff = diffLines(old, new)
    check diff.exact
    check diff.hunks.len == 20
    check old.apply(diff.hunks) == new
