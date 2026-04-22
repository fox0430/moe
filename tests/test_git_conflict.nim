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

import std/[unittest, options]

import ../src/moepkg/[buffer, git_conflict]

suite "git_conflict - parseConflictMarkerLine":
  test "detects start marker with label":
    check parseConflictMarkerLine("<<<<<<< HEAD") == cmkStartMarker

  test "detects bare start marker":
    check parseConflictMarkerLine("<<<<<<<") == cmkStartMarker

  test "detects separator":
    check parseConflictMarkerLine("=======") == cmkSeparator

  test "detects end marker":
    check parseConflictMarkerLine(">>>>>>> feature/foo") == cmkEndMarker

  test "detects diff3 base marker":
    check parseConflictMarkerLine("||||||| merged common ancestors") == cmkBaseMarker

  test "rejects 6 char marker":
    check parseConflictMarkerLine("<<<<<< HEAD") == cmkNone

  test "rejects 8 char marker":
    check parseConflictMarkerLine("<<<<<<<< HEAD") == cmkNone

  test "rejects marker with no whitespace after":
    check parseConflictMarkerLine("<<<<<<<X") == cmkNone

  test "rejects indented marker":
    check parseConflictMarkerLine("  <<<<<<< HEAD") == cmkNone

  test "rejects empty line":
    check parseConflictMarkerLine("") == cmkNone

  test "rejects regular content":
    check parseConflictMarkerLine("let x = 1") == cmkNone

suite "git_conflict - extractConflictLabel":
  test "extracts basic label":
    check extractConflictLabel("<<<<<<< HEAD") == "HEAD"

  test "extracts label with spaces":
    check extractConflictLabel(">>>>>>> feature branch") == "feature branch"

  test "returns empty when no label":
    check extractConflictLabel("=======") == ""

  test "trims trailing whitespace":
    check extractConflictLabel("<<<<<<< HEAD   ") == "HEAD"

  test "handles tab after marker":
    check extractConflictLabel("<<<<<<<\tHEAD") == "HEAD"

suite "git_conflict - scanBufferForConflicts":
  test "empty buffer yields no conflicts":
    let buf = newTextBuffer("")
    check scanBufferForConflicts(buf).len == 0

  test "buffer with no markers yields no conflicts":
    let buf = newTextBuffer("line1\nline2\nline3\n")
    check scanBufferForConflicts(buf).len == 0

  test "detects a single 2-way conflict":
    let content = """
line before
<<<<<<< HEAD
ours line 1
ours line 2
=======
theirs line 1
>>>>>>> feature
line after
"""
    let buf = newTextBuffer(content)
    let blocks = scanBufferForConflicts(buf)
    check blocks.len == 1
    check blocks[0].startLine == 1
    check blocks[0].separatorLine == 4
    check blocks[0].endLine == 6
    check blocks[0].baseMarkerLine.isNone
    check blocks[0].oursLabel == "HEAD"
    check blocks[0].theirsLabel == "feature"

  test "detects a diff3 conflict":
    let content = """
<<<<<<< HEAD
ours
||||||| merged common ancestors
base
=======
theirs
>>>>>>> topic
"""
    let buf = newTextBuffer(content)
    let blocks = scanBufferForConflicts(buf)
    check blocks.len == 1
    check blocks[0].baseMarkerLine.isSome
    check blocks[0].baseMarkerLine.get == 2
    check blocks[0].separatorLine == 4
    check blocks[0].endLine == 6

  test "detects multiple conflicts":
    let content = """
<<<<<<< HEAD
a
=======
b
>>>>>>> t1
middle
<<<<<<< HEAD
c
=======
d
>>>>>>> t2
"""
    let buf = newTextBuffer(content)
    let blocks = scanBufferForConflicts(buf)
    check blocks.len == 2
    check blocks[0].startLine == 0
    check blocks[1].startLine == 6

  test "unclosed conflict (no end marker) is discarded":
    let content = """
<<<<<<< HEAD
ours
=======
theirs
"""
    let buf = newTextBuffer(content)
    check scanBufferForConflicts(buf).len == 0

  test "orphan separator is ignored":
    let content = """
some text
=======
more text
"""
    let buf = newTextBuffer(content)
    check scanBufferForConflicts(buf).len == 0

  test "nested start marker restarts the block":
    let content = """
<<<<<<< outer
outer ours
<<<<<<< inner
inner ours
=======
inner theirs
>>>>>>> inner-branch
"""
    let buf = newTextBuffer(content)
    let blocks = scanBufferForConflicts(buf)
    check blocks.len == 1
    check blocks[0].startLine == 2
    check blocks[0].oursLabel == "inner"
    check blocks[0].theirsLabel == "inner-branch"

suite "git_conflict - lineConflictKind":
  setup:
    let content = """
before
<<<<<<< HEAD
ours1
ours2
=======
theirs1
>>>>>>> branch
after
"""
    let buf = newTextBuffer(content)
    applyConflictsToBuffer(buf, scanBufferForConflicts(buf))

  test "returns cmkNone for lines outside any block":
    check lineConflictKind(buf, 0) == cmkNone
    check lineConflictKind(buf, 7) == cmkNone

  test "returns cmkStartMarker for start line":
    check lineConflictKind(buf, 1) == cmkStartMarker

  test "returns cmkOurs for ours range":
    check lineConflictKind(buf, 2) == cmkOurs
    check lineConflictKind(buf, 3) == cmkOurs

  test "returns cmkSeparator for ======= line":
    check lineConflictKind(buf, 4) == cmkSeparator

  test "returns cmkTheirs for theirs range":
    check lineConflictKind(buf, 5) == cmkTheirs

  test "returns cmkEndMarker for end line":
    check lineConflictKind(buf, 6) == cmkEndMarker

suite "git_conflict - lineConflictKind (diff3)":
  setup:
    let content = """
<<<<<<< HEAD
ours
||||||| base
base content
=======
theirs
>>>>>>> topic
"""
    let buf = newTextBuffer(content)
    applyConflictsToBuffer(buf, scanBufferForConflicts(buf))

  test "diff3 base marker line":
    check lineConflictKind(buf, 2) == cmkBaseMarker

  test "diff3 base content line":
    check lineConflictKind(buf, 3) == cmkBase

  test "diff3 ours before base marker":
    check lineConflictKind(buf, 1) == cmkOurs

  test "diff3 theirs after separator":
    check lineConflictKind(buf, 5) == cmkTheirs

suite "git_conflict - applyConflictsToBuffer":
  test "stamps GitConflict marker on every conflict line":
    let content = """
outside
<<<<<<< HEAD
ours
=======
theirs
>>>>>>> branch
outside again
"""
    let buf = newTextBuffer(content)
    applyConflictsToBuffer(buf, scanBufferForConflicts(buf))
    for line in 1 .. 5:
      let m = buf.getLineMarker(line)
      check m.isSome
      check m.get == GitConflict
    check buf.getLineMarker(0).isNone
    check buf.getLineMarker(6).isNone

  test "clears stale GitConflict markers on re-apply":
    let buf = newTextBuffer("line1\nline2\nline3\n")
    buf.setLineMarker(0, GitConflict)
    buf.setLineMarker(1, GitConflict)
    applyConflictsToBuffer(buf, @[])
    check buf.getLineMarker(0).isNone
    check buf.getLineMarker(1).isNone

  test "does not touch unrelated markers":
    let buf = newTextBuffer("line1\nline2\nline3\n")
    buf.setLineMarker(0, GitAdded)
    buf.setLineMarker(1, GitConflict)
    applyConflictsToBuffer(buf, @[])
    check buf.getLineMarker(0).isSome
    check buf.getLineMarker(0).get == GitAdded
    check buf.getLineMarker(1).isNone

suite "git_conflict - orphan marker fallback":
  test "lineConflictKind returns marker kind for orphan start marker":
    let content = """
<<<<<<< HEAD
half-written
"""
    let buf = newTextBuffer(content)
    applyConflictsToBuffer(buf, scanBufferForConflicts(buf))
    check buf.conflictBlocks.len == 0
    check lineConflictKind(buf, 0) == cmkStartMarker
    check lineConflictKind(buf, 1) == cmkNone

  test "lineConflictKind returns marker kind when separator is broken":
    # One char was deleted from '=======' - block parsing fails, but the
    # start and end marker lines should still be highlighted.
    let content = """
<<<<<<< HEAD
ours
======
theirs
>>>>>>> branch
"""
    let buf = newTextBuffer(content)
    applyConflictsToBuffer(buf, scanBufferForConflicts(buf))
    check buf.conflictBlocks.len == 0
    check lineConflictKind(buf, 0) == cmkStartMarker
    check lineConflictKind(buf, 2) == cmkNone
    check lineConflictKind(buf, 4) == cmkEndMarker

  test "applyConflictsToBuffer stamps sidebar marker on orphan markers":
    let content = """
<<<<<<< HEAD
still editing
"""
    let buf = newTextBuffer(content)
    applyConflictsToBuffer(buf, scanBufferForConflicts(buf))
    let m0 = buf.getLineMarker(0)
    check m0.isSome
    check m0.get == GitConflict

  test "later complete block still resolves correctly":
    # First block is broken, second is intact. The second must still give
    # the full 2-color ours/theirs classification.
    let content = """
<<<<<<< A
stale
>>>>>>> A
middle
<<<<<<< B
bours
=======
btheirs
>>>>>>> B
"""
    let buf = newTextBuffer(content)
    applyConflictsToBuffer(buf, scanBufferForConflicts(buf))
    check buf.conflictBlocks.len == 1
    check buf.conflictBlocks[0].startLine == 4
    # Second (valid) block: ours / separator / theirs
    check lineConflictKind(buf, 5) == cmkOurs
    check lineConflictKind(buf, 6) == cmkSeparator
    check lineConflictKind(buf, 7) == cmkTheirs
    # First (broken) block: start/end markers still highlighted via fallback
    check lineConflictKind(buf, 0) == cmkStartMarker
    check lineConflictKind(buf, 2) == cmkEndMarker

suite "git_conflict - navigation":
  setup:
    let content = """
<<<<<<< A
a
=======
b
>>>>>>> B
middle
<<<<<<< C
c
=======
d
>>>>>>> D
"""
    let buf = newTextBuffer(content)
    applyConflictsToBuffer(buf, scanBufferForConflicts(buf))

  test "findNextConflict from before first":
    let nxt = findNextConflict(buf, -1)
    check nxt.isSome
    check nxt.get.startLine == 0

  test "findNextConflict from inside first returns second":
    let nxt = findNextConflict(buf, 2)
    check nxt.isSome
    check nxt.get.startLine == 6

  test "findNextConflict past last returns none":
    check findNextConflict(buf, 20).isNone

  test "findPrevConflict from after second returns second":
    let prv = findPrevConflict(buf, 100)
    check prv.isSome
    check prv.get.startLine == 6

  test "findPrevConflict before first returns none":
    check findPrevConflict(buf, 0).isNone
