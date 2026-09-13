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

## `replaceLines` swaps a span of lines for another as a single change, where
## the same edit used to be one insert or delete per line, so the tests here pin
## both the shape of the recorded change and its per-line reference sequence.

import std/[deques, options, random, sequtils, strutils, unittest]

import pkg/results

import ../src/moepkg/buffer
import ../src/moepkg/buffer/fold

proc bufferOf(lines: varargs[string]): TextBuffer =
  newTextBuffer(lines.toSeq.join("\n"))

proc bufferOf(backend: BufferBackend, lines: seq[string]): TextBuffer =
  newTextBuffer(lines.join("\n"), backend = backend)

proc contents(b: TextBuffer): seq[string] =
  for i in 0 ..< b.len:
    result.add b[i]

proc markers(b: TextBuffer): seq[Option[LineMarkerKind]] =
  for i in 0 ..< b.len:
    result.add b.getLineMarker(i)

proc bookmarkLines(b: TextBuffer): seq[int] =
  for i in 0 ..< b.len:
    if b.hasBookmark(i):
      result.add i

proc state(b: TextBuffer): auto =
  ## Everything a caller can observe of a buffer after an edit.
  (
    contents: b.contents,
    markers: b.markers,
    bookmarks: b.bookmarkLines,
    folds: b.foldState.folds,
    modified: b.modifiedLines,
  )

suite "Buffer - replaceLines":
  test "A span is swapped for a longer one":
    let buf = bufferOf("a", "b", "c", "d")
    check buf.replaceLines(1, 2, ["1", "2", "3"]).isOk
    check buf.contents == @["a", "1", "2", "3", "d"]

  test "A span is swapped for a shorter one":
    let buf = bufferOf("a", "b", "c", "d")
    check buf.replaceLines(1, 3, ["1"]).isOk
    check buf.contents == @["a", "1"]

  test "A pure insertion deletes nothing":
    let buf = bufferOf("a", "b")
    check buf.replaceLines(1, 0, ["x", "y"]).isOk
    check buf.contents == @["a", "x", "y", "b"]

  test "A pure deletion inserts nothing":
    let buf = bufferOf("a", "b", "c")
    check buf.replaceLines(0, 2, []).isOk
    check buf.contents == @["c"]

  test "Replacing nothing with nothing is not an edit":
    let buf = bufferOf("a", "b")
    let seqBefore = buf.changeSeq
    check buf.replaceLines(1, 0, []).isOk
    check buf.changeSeq == seqBefore

  test "The whole span is one undo entry, whatever its length":
    let buf = bufferOf("a", "b", "c", "d")
    check buf.replaceLines(0, 4, ["1", "2", "3", "4", "5"]).isOk
    check buf.undoStack.len == 1
    check buf.undoStack.peekLast.kind == ckReplaceLines
    check buf.undo().isOk
    check buf.contents == @["a", "b", "c", "d"]
    check buf.redo().isOk
    check buf.contents == @["1", "2", "3", "4", "5"]

  test "Every rewritten line is marked modified, not just the first":
    let buf = bufferOf("a", "b", "c", "d")
    check buf.replaceLines(1, 2, ["1", "2"]).isOk
    check buf.modifiedLines[1] == lmkModified
    check buf.modifiedLines[2] == lmkModified
    check buf.modifiedLines[0] == lmkUnmodified
    check buf.modifiedLines[3] == lmkUnmodified

  test "keepRows leaves what is attached to the shared rows where it is":
    let buf = bufferOf("a", "b", "c", "d")
    buf.setLineMarker(1, LineMarkerKind.SyntaxError)
    buf.toggleBookmark(1)
    check buf.replaceLines(1, 2, ["B", "C"]).isOk
    check buf.getLineMarker(1) == some(LineMarkerKind.SyntaxError)
    check buf.hasBookmark(1)

  test "Without keepRows the old rows take their attachments with them":
    let buf = bufferOf("a", "b", "c", "d")
    buf.setLineMarker(1, LineMarkerKind.SyntaxError)
    buf.toggleBookmark(1)
    check buf.replaceLines(1, 2, ["B", "C"], keepRows = false).isOk
    check buf.contents == @["a", "B", "C", "d"]
    check buf.markers.allIt(it.isNone)
    check buf.bookmarkLines.len == 0

  test "A marker below the span moves with its line":
    let buf = bufferOf("a", "b", "c")
    buf.setLineMarker(2, LineMarkerKind.SyntaxError)
    check buf.replaceLines(1, 1, ["1", "2"]).isOk
    check buf.getLineMarker(3) == some(LineMarkerKind.SyntaxError)
    check buf.undo().isOk
    check buf.getLineMarker(2) == some(LineMarkerKind.SyntaxError)

  test "Without keepRows a fold reaching into the span is cut back to it":
    # The fold covered lines the span took with it; letting it stretch over the
    # replacement would put it on text it never covered.
    let buf = bufferOf("a", "b", "c", "d", "e")
    check buf.foldState.addFold(1, 3)
    check buf.replaceLines(2, 2, ["1", "2", "3"], keepRows = false).isOk
    check buf.contents == @["a", "b", "1", "2", "3", "e"]
    check buf.foldState.folds[0] ==
      Fold(startLine: 1, endLine: 1, collapsed: true, source: fsManual)

  test "A fold below the span moves with its lines":
    let buf = bufferOf("a", "b", "c", "d", "e")
    check buf.foldState.addFold(3, 4)
    check buf.replaceLines(0, 1, ["1", "2", "3"]).isOk
    check buf.foldState.folds[0].startLine == 5
    check buf.undo().isOk
    check buf.foldState.folds[0].startLine == 3

  test "A read-only buffer is refused":
    let buf = bufferOf("a", "b")
    buf.readOnly = true
    check buf.replaceLines(0, 1, ["x"]).isErr
    check buf.contents == @["a", "b"]

  test "A range the buffer does not hold is refused":
    let buf = bufferOf("a", "b")
    check buf.replaceLines(-1, 1, ["x"]).isErr
    check buf.replaceLines(3, 0, ["x"]).isErr
    check buf.replaceLines(1, 2, ["x"]).isErr
    check buf.replaceLines(0, -1, ["x"]).isErr
    check buf.contents == @["a", "b"]

  test "Emptying the buffer is refused":
    # A buffer always holds at least one line, so a caller that means to clear
    # one asks for a single empty line.
    let buf = bufferOf("a", "b")
    check buf.replaceLines(0, 2, []).isErr
    check buf.contents == @["a", "b"]
    check buf.replaceLines(0, 2, [""]).isOk
    check buf.contents == @[""]

  test "Undo brings back the folds and bookmarks a rewritten span dropped":
    # The rows the span gives up take their folds and bookmarks with them, and
    # the reversed events can only put blank rows back, so undo restores them
    # wholesale. GapBuffer has no snapshot to fall back on.
    let buf = bufferOf(GapBuffer, @["a", "b", "c", "d", "e"])
    buf.toggleBookmark(1)
    check buf.foldState.addFold(2, 3)
    check buf.replaceLines(0, 5, @["1", "2", "3"], keepRows = false).isOk
    check buf.bookmarkLines.len == 0
    check buf.foldState.folds.len == 0
    check buf.undo().isOk
    check buf.contents == @["a", "b", "c", "d", "e"]
    check buf.bookmarkLines == @[1]
    check buf.foldState.folds.len == 1
    check buf.foldState.folds[0].startLine == 2
    check buf.foldState.folds[0].endLine == 3

  test "Undo brings back what a shrinking span dropped off its end":
    # Even with the shared rows kept, the surplus at the end of the span leaves
    # and takes its attachments with it.
    let buf = bufferOf(GapBuffer, @["a", "b", "c", "d"])
    buf.toggleBookmark(3)
    check buf.replaceLines(1, 3, @["B"]).isOk
    check buf.bookmarkLines.len == 0
    check buf.undo().isOk
    check buf.bookmarkLines == @[3]

  test "Undo keeps additions made after an in-place edit":
    # With the rows kept and nothing deleted, the reverse events alone restore
    # the pre-edit state, so the wholesale restore -- which would also wipe
    # folds and bookmarks added after the edit -- is skipped.
    let buf = bufferOf("a", "b", "c", "d")
    check buf.replaceLines(1, 2, ["B", "C"]).isOk
    buf.toggleBookmark(0)
    check buf.foldState.addFold(0, 1)
    check buf.undo().isOk
    check buf.contents == @["a", "b", "c", "d"]
    check buf.bookmarkLines == @[0]
    check buf.foldState.folds.len == 1

  test "Undo keeps additions made after a growing edit":
    let buf = bufferOf("a", "b", "c", "d")
    check buf.replaceLines(1, 2, ["1", "2", "3"]).isOk
    buf.toggleBookmark(0)
    check buf.undo().isOk
    check buf.contents == @["a", "b", "c", "d"]
    check buf.bookmarkLines == @[0]

  test "A line separator in the replacement is refused":
    let buf = bufferOf("a", "b")
    check buf.replaceLines(0, 1, ["x\ny"]).isErr
    check buf.contents == @["a", "b"]

  test "CR is stripped on the way in":
    let buf = bufferOf("a", "b")
    check buf.replaceLines(0, 1, ["x\r"]).isOk
    check buf[0] == "x"

suite "Buffer - replaceLines against the per-line sequence":
  ## The bulk change has to land exactly where the insert/delete/replace loop it
  ## replaced did, or a marker, fold or bookmark quietly moves a line.
  proc applyPerLine(
      b: TextBuffer, start, delete: int, lines: seq[string], keepRows: bool
  ) =
    if not keepRows:
      # The old rows leave, then the replacement arrives in their place.
      for _ in 0 ..< delete:
        check b.deleteLine(start).isOk
      for j in 0 ..< lines.len:
        check b.insert(start + j, lines[j]).isOk
    else:
      let overlap = min(delete, lines.len)
      for j in 0 ..< overlap:
        check b.replaceLine(start + j, lines[j]).isOk
      for j in overlap ..< lines.len:
        check b.insert(start + j, lines[j]).isOk
      for _ in overlap ..< delete:
        check b.deleteLine(start + overlap).isOk

  proc decorate(b: TextBuffer, rng: var Rand) =
    for i in 0 ..< b.len:
      case rng.rand(5)
      of 0:
        b.setLineMarker(i, LineMarkerKind.SyntaxError)
      of 1:
        b.toggleBookmark(i)
      of 2:
        if i + 1 < b.len:
          discard b.foldState.addFold(i, i + 1)
      else:
        discard

  test "The two agree on content and on every attachment":
    var rng = initRand(20260914)
    for iteration in 0 ..< 3000:
      let backend = [GapBuffer, SqrtDecomp, Rope, PieceTable][iteration mod 4]
      let
        oldLen = 1 + rng.rand(7)
        start = rng.rand(oldLen)
        delete = rng.rand(oldLen - start)
        keepRows = rng.rand(1) == 0
      var lines: seq[string]
      for i in 0 ..< oldLen:
        lines.add "line " & $i
      var replacement: seq[string]
      for _ in 0 ..< rng.rand(4):
        replacement.add "new " & $rng.rand(100)
      # A buffer always holds at least one line; neither path may empty it.
      if delete == oldLen and replacement.len == 0:
        continue
      # A call that changes nothing records nothing, so there is no undo step
      # to compare.
      if delete == 0 and replacement.len == 0:
        continue
      # Giving the old rows up empties the buffer in the per-line reference
      # when the span is the whole buffer, which no edit API allows.
      if not keepRows and delete == oldLen:
        continue

      let
        bulk = bufferOf(backend, lines)
        perLine = bufferOf(backend, lines)
      var decorateRng = initRand(iteration)
      var perLineRng = initRand(iteration)
      bulk.decorate(decorateRng)
      perLine.decorate(perLineRng)
      let before = bulk.state

      check bulk.replaceLines(start, delete, replacement, keepRows = keepRows).isOk
      perLine.applyPerLine(start, delete, replacement, keepRows)
      check bulk.state == perLine.state
      let afterEdit = bulk.state

      # The whole span comes back as one undo step where the per-line sequence
      # needs one per line, so `undo` is called until each buffer is back.
      check bulk.undo().isOk
      while perLine.undoStack.len > 0:
        check perLine.undo().isOk
      # Undo answers to the buffer as it stood, not to the per-line sequence:
      # a row that left the span took its folds and bookmarks with it, and the
      # per-line deletes cannot bring those back.
      check bulk.state == before
      check (bulk.contents, bulk.markers, bulk.modifiedLines) ==
        (perLine.contents, perLine.markers, perLine.modifiedLines)

      check bulk.redo().isOk
      while perLine.redoStack.len > 0:
        check perLine.redo().isOk
      # The per-line reference never got its folds and bookmarks back, so redo
      # is measured against the edit's own result.
      check bulk.state == afterEdit
      check (bulk.contents, bulk.markers, bulk.modifiedLines) ==
        (perLine.contents, perLine.markers, perLine.modifiedLines)

suite "Buffer - replaceAllLines records one change per hunk":
  ## The guard against the quadratic rewrite: a hunk that used to cost one
  ## recorded change (and one side-array shift) per line now costs one.
  test "A coarse whole-file rewrite is a single change":
    var lines = newSeq[string](2000)
    for i in 0 ..< lines.len:
      lines[i] = "line " & $i
    let buf = newTextBuffer(lines.join("\n"))
    var replacement = newSeq[string](lines.len)
    for i in 0 ..< lines.len:
      replacement[i] = (if i mod 2 == 0: lines[i] else: "other " & $i)
    let diff = buf.replaceAllLines(replacement, "filter")
    check diff.isOk
    check not diff.get.exact
    let entry = buf.undoStack.peekLast
    check entry.kind == ckTransaction
    check entry.transactionChanges.len == diff.get.hunks.len
    check entry.transactionChanges.allIt(it.kind == ckReplaceLines)

  test "Undo after a whole-file filter brings the folds and bookmarks back":
    # What `:%!filter` does: a rewrite far enough from the buffer to be coarse,
    # so every row is given up, then `u`.
    var lines = newSeq[string](200)
    for i in 0 ..< lines.len:
      lines[i] = "line " & $i
    let buf = newTextBuffer(lines.join("\n"))
    buf.toggleBookmark(10)
    check buf.foldState.addFold(20, 25)
    buf.setLineMarker(30, LineMarkerKind.SyntaxError)

    var replacement = newSeq[string](lines.len)
    for i in 0 ..< lines.len:
      replacement[i] = "other " & $i
    let diff = buf.replaceAllLines(replacement, "filter")
    check diff.isOk
    check diff.get.coarse

    check buf.undo().isOk
    check buf.contents == lines
    check buf.bookmarkLines == @[10]
    check buf.foldState.folds.len == 1
    check buf.foldState.folds[0].startLine == 20
    check buf.getLineMarker(30) == some(LineMarkerKind.SyntaxError)

  test "An exact script is one change per hunk":
    let buf = bufferOf("a", "b", "c", "d", "e")
    let diff = buf.replaceAllLines(["a", "B", "c", "D", "e"])
    check diff.get.exact
    let entry = buf.undoStack.peekLast
    check entry.transactionChanges.len == diff.get.hunks.len
    check entry.transactionChanges.allIt(it.kind == ckReplaceLines)
