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

## Tests for side-by-side diff viewer (GitHub/delta style).

import std/[unittest, strutils, os, times, options]

import pkg/celina

import
  ../src/moepkg/[
    buffer, highlight, color, theme, unicode_utils, backup_manager, editor, config,
    setting_issue, types, editor_window_layout,
  ]
import ../src/moepkg/diff_viewer {.all.}
import ../src/moepkg/command_handlers/diff_viewer_handler
import ../src/moepkg/key_bindings/registry
import ../src/moepkg/editor_render_views
import ../src/moepkg/command_handlers/[handler_result, result_processor]

setThemeColors(DefaultColors)

proc charKey(c: string): KeyCombo =
  KeyCombo(isSpecial: false, char: c, modifiers: {})

proc createTestBuffer(): Buffer =
  result = newBuffer(80, 24)
  result.area = Rect(x: 0, y: 0, width: 80, height: 24)

suite "side-by-side: parseHunkHeader":
  test "Standard hunk header":
    let h = parseHunkHeader("@@ -10,5 +12,7 @@ func")
    check h.ok
    check h.oldStart == 10
    check h.newStart == 12

  test "Single-line hunk without count":
    let h = parseHunkHeader("@@ -0,0 +1 @@")
    check h.ok
    check h.oldStart == 0
    check h.newStart == 1

  test "Non-header returns not ok":
    check parseHunkHeader("--- a/file").ok == false
    check parseHunkHeader(" context").ok == false
    check parseHunkHeader("").ok == false

suite "side-by-side: tokenizeWordsWithPos":
  test "Splits on whitespace with positions":
    let toks = tokenizeWordsWithPos("hello world")
    check toks.len == 2
    check toks[0].text == "hello"
    check toks[0].startCol == 0
    check toks[0].endCol == 5
    check toks[1].text == "world"
    check toks[1].startCol == 6
    check toks[1].endCol == 11

  test "Empty and whitespace-only":
    check tokenizeWordsWithPos("").len == 0
    check tokenizeWordsWithPos("   ").len == 0

suite "side-by-side: computeWordRanges":
  test "Identical lines yield no ranges":
    let (a, b) = computeWordRanges("same line", "same line")
    check a.len == 0
    check b.len == 0

  test "Single word change":
    let (a, b) = computeWordRanges("hello world", "hello nim")
    check a.len == 1
    check b.len == 1
    check a[0].startCol == 6
    check b[0].startCol == 6

  test "Unchanged middle word is kept":
    let (a, b) = computeWordRanges("old foo bar", "new foo baz")
    # "foo" kept, "old"/"new" and "bar"/"baz" marked.
    check a.len == 2
    check b.len == 2

  test "Empty old line marks whole new line":
    let (a, b) = computeWordRanges("", "hello")
    check a.len == 0
    check b.len == 1
    check b[0].startCol == 0
    check b[0].endCol == 5

suite "side-by-side: buildSideBySideRows":
  test "Pairs deleted/added as changed":
    let items = @[
      DiffLine(text: "@@ -1,2 +1,2 @@", kind: dlkHeader),
      DiffLine(text: " ctx", kind: dlkNormal),
      DiffLine(text: "-old line", kind: dlkDeleted),
      DiffLine(text: "+new line", kind: dlkAdded),
    ]
    let rows = buildSideBySideRows(items)
    check rows.len == 3
    check rows[0].kind == sbrHeader
    check rows[1].kind == sbrContext
    check rows[1].leftText == "ctx"
    check rows[1].rightText == "ctx"
    check rows[2].kind == sbrChanged
    check rows[2].leftText == "old line"
    check rows[2].rightText == "new line"
    check rows[2].leftWordRanges.len > 0
    check rows[2].rightWordRanges.len > 0

  test "Unpaired leftovers become filler rows":
    let items = @[
      DiffLine(text: "@@ -1,1 +1,3 @@", kind: dlkHeader),
      DiffLine(text: "-only old", kind: dlkDeleted),
      DiffLine(text: "+new one", kind: dlkAdded),
      DiffLine(text: "+new two", kind: dlkAdded),
    ]
    let rows = buildSideBySideRows(items)
    check rows.len == 3
    check rows[1].kind == sbrChanged
    check rows[2].kind == sbrAdded
    check rows[2].leftText == ""
    check rows[2].rightText == "new two"

  test "Deleted-only block":
    let items = @[
      DiffLine(text: "@@ -1,2 +1,1 @@", kind: dlkHeader),
      DiffLine(text: "-gone", kind: dlkDeleted),
      DiffLine(text: " keep", kind: dlkNormal),
    ]
    let rows = buildSideBySideRows(items)
    check rows[1].kind == sbrDeleted
    check rows[1].rightText == ""
    check rows[2].kind == sbrContext

  test "No differences placeholder":
    let rows =
      buildSideBySideRows(@[DiffLine(text: "(No differences)", kind: dlkNormal)])
    check rows.len == 1
    check rows[0].kind == sbrEmpty

  test "Line numbers follow hunk header":
    let items = @[
      DiffLine(text: "@@ -10,3 +20,3 @@", kind: dlkHeader),
      DiffLine(text: " ctx", kind: dlkNormal),
      DiffLine(text: "-old", kind: dlkDeleted),
      DiffLine(text: "+new", kind: dlkAdded),
    ]
    let rows = buildSideBySideRows(items)
    check rows[1].oldLineNo == 10
    check rows[1].newLineNo == 20
    check rows[2].oldLineNo == 11
    check rows[2].newLineNo == 21

  test "No-newline marker does not split a changed pair":
    let items = @[
      DiffLine(text: "@@ -1,2 +1,2 @@", kind: dlkHeader),
      DiffLine(text: " a", kind: dlkNormal),
      DiffLine(text: "-b", kind: dlkDeleted),
      DiffLine(text: "\\ No newline at end of file", kind: dlkNormal),
      DiffLine(text: "+c", kind: dlkAdded),
      DiffLine(text: "\\ No newline at end of file", kind: dlkNormal),
    ]
    let rows = buildSideBySideRows(items)
    check rows.len == 3
    check rows[2].kind == sbrChanged
    check rows[2].leftText == "b"
    check rows[2].rightText == "c"
    check rows[2].leftWordRanges.len > 0
    check rows[2].rightWordRanges.len > 0
    check rows[2].oldLineNo == 2
    check rows[2].newLineNo == 2

  test "No-newline marker keeps later line numbers aligned":
    let items = @[
      DiffLine(text: "@@ -1,3 +1,3 @@", kind: dlkHeader),
      DiffLine(text: " a", kind: dlkNormal),
      DiffLine(text: "-b", kind: dlkDeleted),
      DiffLine(text: "\\ No newline at end of file", kind: dlkNormal),
      DiffLine(text: "+c", kind: dlkAdded),
      DiffLine(text: "\\ No newline at end of file", kind: dlkNormal),
      DiffLine(text: " d", kind: dlkNormal),
    ]
    let rows = buildSideBySideRows(items)
    check rows.len == 4
    check rows[3].kind == sbrContext
    check rows[3].oldLineNo == 3
    check rows[3].newLineNo == 3

suite "side-by-side: file headers vs content":
  test "Content lines starting with --- are not file headers":
    let backupFile = getTempDir() / "moe_sbs_dashes_backup.txt"
    let sourceFile = getTempDir() / "moe_sbs_dashes_source.txt"
    writeFile(backupFile, "-- old comment\nkeep\n")
    writeFile(sourceFile, "-- new comment\nkeep\n")
    defer:
      removeFile(backupFile)
      removeFile(sourceFile)

    let st = initDiffViewerState(sourceFile, backupFile)
    st.ensureSideRows()
    var changed = -1
    for i, row in st.sideRows:
      if row.kind == sbrChanged:
        changed = i
        break
    check changed >= 0
    check st.sideRows[changed].leftText == "-- old comment"
    check st.sideRows[changed].rightText == "-- new comment"

  test "Content lines starting with +++ are not file headers":
    let backupFile = getTempDir() / "moe_sbs_plus_backup.txt"
    let sourceFile = getTempDir() / "moe_sbs_plus_source.txt"
    writeFile(backupFile, "++i;\n")
    writeFile(sourceFile, "++j;\n")
    defer:
      removeFile(backupFile)
      removeFile(sourceFile)

    let st = initDiffViewerState(sourceFile, backupFile)
    st.ensureSideRows()
    var changed = -1
    for i, row in st.sideRows:
      if row.kind == sbrChanged:
        changed = i
        break
    check changed >= 0
    check st.sideRows[changed].leftText == "++i;"
    check st.sideRows[changed].rightText == "++j;"

suite "side-by-side: formatting":
  test "Both panels are padded to fixed width":
    let row = SideBySideRow(
      kind: sbrChanged, leftText: "ab", rightText: "cdef", oldLineNo: 1, newLineNo: 1
    )
    let line = row.formatSideBySideLine(10)
    check line == "ab        " & SideBySideSeparator & "cdef      "

  test "Right panel takes the remaining width":
    let row = SideBySideRow(
      kind: sbrChanged, leftText: "ab", rightText: "cdef", oldLineNo: 1, newLineNo: 1
    )
    let line = row.formatSideBySideLine(10, 11)
    check line == "ab        " & SideBySideSeparator & "cdef       "

  test "Header rows span as-is":
    let row = SideBySideRow(
      kind: sbrHeader, headerText: "@@ -1 +1 @@", oldLineNo: -1, newLineNo: -1
    )
    check row.formatSideBySideLine(10) == "@@ -1 +1 @@"

  test "Truncated panels end with the truncation marker":
    let row = SideBySideRow(
      kind: sbrChanged,
      leftText: "abcdefghij",
      rightText: "klmnopqrst",
      oldLineNo: 1,
      newLineNo: 1,
    )
    let line = row.formatSideBySideLine(5)
    check line ==
      "abcd" & SideTruncationMarker & SideBySideSeparator & "klmn" & SideTruncationMarker
    check line.charDisplayWidth == 5 + SideBySideSeparator.charDisplayWidth + 5

  test "Wide runes truncate on a character boundary and stay padded":
    let row = SideBySideRow(
      kind: sbrChanged,
      leftText: "日本語です",
      rightText: "ab",
      oldLineNo: 1,
      newLineNo: 1,
    )
    let line = row.formatSideBySideLine(5)
    # Two wide runes plus the marker is 5 columns; the third would overflow.
    check line.startsWith("日本" & SideTruncationMarker)
    check line.charDisplayWidth == 5 + SideBySideSeparator.charDisplayWidth + 5

  test "sidePanelWidth splits evenly":
    check sidePanelWidth(80) == 38
    check sidePanelWidth(10) == 10 # clamped minimum

suite "side-by-side: buffer creation":
  test "Creates side-by-side buffer with separator":
    var st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "@@ -1,2 +1,2 @@", kind: dlkHeader),
      DiffLine(text: " ctx", kind: dlkNormal),
      DiffLine(text: "-hello world", kind: dlkDeleted),
      DiffLine(text: "+hello nim", kind: dlkAdded),
    ]
    st.rebuildSideRows()
    st.viewMode = dvmSideBySide
    let buf = st.createSideBySideTextBuffer(80)
    check buf.len == 3
    check SideBySideSeparator in buf.getLine(2)
    check not buf.highlight.isNil

  test "Word highlight uses the changed-word background":
    var st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "@@ -1,1 +1,1 @@", kind: dlkHeader),
      DiffLine(text: "-hello world", kind: dlkDeleted),
      DiffLine(text: "+hello nim", kind: dlkAdded),
    ]
    st.rebuildSideRows()
    st.viewMode = dvmSideBySide
    st.wordHighlight = true
    let buf = st.createSideBySideTextBuffer(80)
    let
      addedWordBg = getThemeStyle(diffViewerAddedWord).bg
      deletedWordBg = getThemeStyle(diffViewerDeletedWord).bg
      addedLineBg = getThemeStyle(diffViewerAddedLineBg).bg
      deletedLineBg = getThemeStyle(diffViewerDeletedLineBg).bg
    # Changed row is index 1. The changed words "world"/"nim" carry the word
    # background; the unchanged "hello" keeps the line background.
    let line = buf.getLine(1)
    let
      sepStart = line.find(SideBySideSeparator) # ASCII prefix: byte == char
      rightStart = sepStart + SideBySideSeparator.charLen
    check buf.highlight.getSegmentBg(1, 6) == some(deletedWordBg)
    check buf.highlight.getSegmentBg(1, 0) == some(deletedLineBg)
    check buf.highlight.getSegmentBg(1, rightStart + 6) == some(addedWordBg)
    check buf.highlight.getSegmentBg(1, rightStart) == some(addedLineBg)

  test "Word highlight off keeps the line background":
    var st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "@@ -1,1 +1,1 @@", kind: dlkHeader),
      DiffLine(text: "-hello world", kind: dlkDeleted),
      DiffLine(text: "+hello nim", kind: dlkAdded),
    ]
    st.rebuildSideRows()
    st.viewMode = dvmSideBySide
    st.wordHighlight = false
    let buf = st.createSideBySideTextBuffer(80)
    let
      addedWordBg = getThemeStyle(diffViewerAddedWord).bg
      deletedWordBg = getThemeStyle(diffViewerDeletedWord).bg
    for col in 0 ..< buf.getLine(1).charLen:
      check buf.highlight.getSegmentBg(1, col) != some(addedWordBg)
      check buf.highlight.getSegmentBg(1, col) != some(deletedWordBg)

  test "Line background spans the whole row":
    var st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "@@ -1,1 +1,1 @@", kind: dlkHeader),
      DiffLine(text: "-hello world", kind: dlkDeleted),
      DiffLine(text: "+hello nim", kind: dlkAdded),
    ]
    st.rebuildSideRows()
    st.viewMode = dvmSideBySide
    st.wordHighlight = false
    let buf = st.createSideBySideTextBuffer(80)
    let
      addedLineBg = getThemeStyle(diffViewerAddedLineBg).bg
      deletedLineBg = getThemeStyle(diffViewerDeletedLineBg).bg
    let line = buf.getLine(1)
    let sepStart = line.find(SideBySideSeparator) # ASCII prefix: byte == char
    # Both panels carry a background up to the text-area edge. The separator
    # spaces follow their side, but the divider itself stays unfilled.
    for col in 0 ..< line.charLen:
      if col == sepStart + 1:
        check buf.highlight.getSegmentBg(1, col).isNone
      else:
        let bg = buf.highlight.getSegmentBg(1, col)
        check bg == some(deletedLineBg) or bg == some(addedLineBg)
    check buf.highlight.getSegmentBg(1, sepStart) == some(deletedLineBg)
    check buf.highlight.getSegmentBg(1, sepStart + 2) == some(addedLineBg)
    check buf.highlight.getSegmentBg(1, line.charLen - 1) == some(addedLineBg)

  test "Narrow width falls back to unified":
    var st = newDiffViewerState()
    st.items = @[DiffLine(text: "+added", kind: dlkAdded)]
    st.rebuildSideRows()
    st.viewMode = dvmSideBySide
    let buf = st.refreshDiffTextBuffer(10)
    check buf.getLine(0) == "+added"
    check SideBySideSeparator notin buf.getLine(0)
    check not st.renderedSideBySide

suite "side-by-side: syntax highlight":
  test "Keeps syntax colors and uses backgrounds for the diff":
    let backupFile = getTempDir() / "moe_sbs_syntax_backup.py"
    let sourceFile = getTempDir() / "moe_sbs_syntax_source.py"
    writeFile(backupFile, "x = 1\n")
    writeFile(sourceFile, "x = 2\n")
    defer:
      removeFile(backupFile)
      removeFile(sourceFile)

    let st = initDiffViewerState(sourceFile, backupFile, dvmSideBySide, true, 2)
    let buf = st.createSideBySideTextBuffer(80)
    var changed = -1
    for i, row in st.sideRows:
      if row.kind == sbrChanged:
        changed = i
        break
    check changed >= 0

    let line = buf.getLine(changed)
    let rightStart = line.find(SideBySideSeparator) + SideBySideSeparator.charLen
    # "x = 2": '2' is the changed word. Its foreground stays the number
    # syntax color while the background marks the change.
    let
      addedWordBg = getThemeStyle(diffViewerAddedWord).bg
      addedLineBg = getThemeStyle(diffViewerAddedLineBg).bg
    check buf.highlight.getColorPair(changed, rightStart + 4) == decNumber
    check buf.highlight.getSegmentBg(changed, rightStart + 4) == some(addedWordBg)
    check buf.highlight.getSegmentBg(changed, rightStart) == some(addedLineBg)
    # The diff line color is no longer used as a foreground.
    check buf.highlight.getColorPair(changed, rightStart + 4) != diffViewerAddedLine

  test "Unknown language keeps backgrounds with default text":
    let backupFile = getTempDir() / "moe_sbs_plain_backup.txt"
    let sourceFile = getTempDir() / "moe_sbs_plain_source.txt"
    writeFile(backupFile, "old\n")
    writeFile(sourceFile, "new\n")
    defer:
      removeFile(backupFile)
      removeFile(sourceFile)

    let st = initDiffViewerState(sourceFile, backupFile, dvmSideBySide, true, 2)
    let buf = st.createSideBySideTextBuffer(80)
    let addedLineBg = getThemeStyle(diffViewerAddedLineBg).bg
    var changed = -1
    for i, row in st.sideRows:
      if row.kind == sbrChanged:
        changed = i
        break
    check changed >= 0
    let line = buf.getLine(changed)
    let rightStart = line.find(SideBySideSeparator) + SideBySideSeparator.charLen
    check buf.highlight.getColorPair(changed, rightStart) == EditorColorPairIndex.default
    # The whole single-token line is a changed word; the padding past the
    # text keeps the line background.
    check buf.highlight.getSegmentBg(changed, rightStart + 3) == some(addedLineBg)

# Segment-level helpers shared by the highlight suites below.
proc charPos(line, sub: string): int =
  ## Char-column index of `sub` in `line` (`find` returns a byte offset).
  let byteIdx = line.find(sub)
  if byteIdx < 0:
    return -1
  line[0 ..< byteIdx].charLen

proc rowSegments(buf: TextBuffer, row: int): seq[ColorSegment] =
  ## Segments emitted for one output row, in column order.
  for seg in buf.highlight.colorSegments:
    if seg.firstRow == row:
      result.add(seg)

proc checkRowCoverage(buf: TextBuffer, row: int) =
  ## Every cell of the row is covered by exactly one contiguous segment run.
  let
    lineLen = buf.getLine(row).charLen
    segs = rowSegments(buf, row)
  check lineLen > 0
  check segs.len > 0
  check segs[0].firstColumn == 0
  for i in 0 ..< segs.len:
    check segs[i].firstRow == row
    check segs[i].lastRow == row
    check segs[i].firstColumn <= segs[i].lastColumn
    if i > 0:
      check segs[i].firstColumn == segs[i - 1].lastColumn + 1
  check segs[^1].lastColumn == lineLen - 1

suite "side-by-side: highlight segments":
  test "Every row covers its columns with contiguous segments":
    var st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "--- backup", kind: dlkHeader),
      DiffLine(text: "+++ source", kind: dlkHeader),
      DiffLine(text: "@@ -1,4 +1,4 @@", kind: dlkHeader),
      DiffLine(text: " ctx", kind: dlkNormal),
      DiffLine(text: "-aaa", kind: dlkDeleted),
      DiffLine(text: "+bbb", kind: dlkAdded),
      DiffLine(text: "+ccc", kind: dlkAdded),
      DiffLine(text: " ddd", kind: dlkNormal),
      DiffLine(text: "-eee", kind: dlkDeleted),
      DiffLine(text: " fff", kind: dlkNormal),
      DiffLine(text: "-ggg", kind: dlkDeleted),
      DiffLine(text: "+hhh", kind: dlkAdded),
    ]
    st.rebuildSideRows()
    st.viewMode = dvmSideBySide
    let buf = st.createSideBySideTextBuffer(80)
    check buf.len == st.sideRows.len
    for row in 0 ..< buf.len:
      checkRowCoverage(buf, row)

  test "Change backgrounds never cross the center divider":
    var st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "@@ -1,1 +1,1 @@", kind: dlkHeader),
      DiffLine(text: "-hello world", kind: dlkDeleted),
      DiffLine(text: "+hello nim", kind: dlkAdded),
    ]
    st.rebuildSideRows()
    st.viewMode = dvmSideBySide
    st.wordHighlight = true
    let buf = st.createSideBySideTextBuffer(80)
    let
      addedLineBg = getThemeStyle(diffViewerAddedLineBg).bg
      deletedLineBg = getThemeStyle(diffViewerDeletedLineBg).bg
      addedWordBg = getThemeStyle(diffViewerAddedWord).bg
      deletedWordBg = getThemeStyle(diffViewerDeletedWord).bg
    let row = 1
    let divider = buf.getLine(row).find(SideBySideSeparator) + 1
    check buf.highlight.getSegmentBg(row, divider).isNone
    # Left of the divider only deleted tints may appear, right of it only
    # added tints.
    for col in 0 ..< divider:
      let bg = buf.highlight.getSegmentBg(row, col)
      check bg != some(addedLineBg)
      check bg != some(addedWordBg)
    for col in divider + 1 ..< buf.getLine(row).charLen:
      let bg = buf.highlight.getSegmentBg(row, col)
      check bg != some(deletedLineBg)
      check bg != some(deletedWordBg)

  test "Added row keeps the divider clear and fills the new side":
    var st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "@@ -1,1 +1,2 @@", kind: dlkHeader),
      DiffLine(text: " ctx", kind: dlkNormal),
      DiffLine(text: "+new", kind: dlkAdded),
    ]
    st.rebuildSideRows()
    st.viewMode = dvmSideBySide
    let buf = st.createSideBySideTextBuffer(80)
    let addedLineBg = getThemeStyle(diffViewerAddedLineBg).bg
    let
      added = 2
      line = buf.getLine(added)
      sepStart = line.find(SideBySideSeparator)
      divider = sepStart + 1
      rightStart = sepStart + SideBySideSeparator.charLen
    check buf.highlight.getColorPair(added, 0) == diffViewerFiller
    check buf.highlight.getSegmentBg(added, divider).isNone
    check buf.highlight.getSegmentBg(added, sepStart) != some(addedLineBg)
    check buf.highlight.getSegmentBg(added, sepStart + 2) == some(addedLineBg)
    for col in rightStart ..< line.charLen:
      check buf.highlight.getSegmentBg(added, col) == some(addedLineBg)
    checkRowCoverage(buf, added)

  test "Deleted row keeps the divider clear and fills the old side":
    var st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "@@ -1,2 +1,1 @@", kind: dlkHeader),
      DiffLine(text: "-gone", kind: dlkDeleted),
      DiffLine(text: " keep", kind: dlkNormal),
    ]
    st.rebuildSideRows()
    st.viewMode = dvmSideBySide
    let buf = st.createSideBySideTextBuffer(80)
    let deletedLineBg = getThemeStyle(diffViewerDeletedLineBg).bg
    let
      deleted = 1
      line = buf.getLine(deleted)
      sepStart = line.find(SideBySideSeparator)
      divider = sepStart + 1
    for col in 0 ..< sepStart:
      check buf.highlight.getSegmentBg(deleted, col) == some(deletedLineBg)
    check buf.highlight.getColorPair(deleted, sepStart + SideBySideSeparator.charLen) ==
      diffViewerFiller
    check buf.highlight.getSegmentBg(deleted, divider).isNone
    checkRowCoverage(buf, deleted)

  test "Context rows keep syntax colors without a diff background":
    let backupFile = getTempDir() / "moe_sbs_ctx_backup.py"
    let sourceFile = getTempDir() / "moe_sbs_ctx_source.py"
    writeFile(backupFile, "keep = 1\nsame = 2\n")
    writeFile(sourceFile, "keep = 9\nsame = 2\n")
    defer:
      removeFile(backupFile)
      removeFile(sourceFile)

    let st = initDiffViewerState(sourceFile, backupFile, dvmSideBySide, true, 2)
    let buf = st.createSideBySideTextBuffer(80)
    let context = buf.len - 1
    check st.sideRows[context].kind == sbrContext
    check buf.highlight.getColorPair(context, 0) == identifier
    for col in 0 ..< buf.getLine(context).charLen:
      check buf.highlight.getSegmentBg(context, col).isNone
    checkRowCoverage(buf, context)

  test "Word ranges alternate with the line background":
    let backupFile = getTempDir() / "moe_sbs_words_backup.py"
    let sourceFile = getTempDir() / "moe_sbs_words_source.py"
    writeFile(backupFile, "a = 1\n")
    writeFile(sourceFile, "b = 2\n")
    defer:
      removeFile(backupFile)
      removeFile(sourceFile)

    let st = initDiffViewerState(sourceFile, backupFile, dvmSideBySide, true, 2)
    let buf = st.createSideBySideTextBuffer(80)
    let
      deletedWordBg = getThemeStyle(diffViewerDeletedWord).bg
      addedWordBg = getThemeStyle(diffViewerAddedWord).bg
      deletedLineBg = getThemeStyle(diffViewerDeletedLineBg).bg
      addedLineBg = getThemeStyle(diffViewerAddedLineBg).bg
    let
      row = 3 # meta, meta, header, changed
      line = buf.getLine(row)
      rightStart = line.find(SideBySideSeparator) + SideBySideSeparator.charLen
    check st.sideRows[row].kind == sbrChanged
    # Unchanged "=" keeps the line tint; the changed identifiers/numbers get
    # the word tint while their syntax foreground is preserved.
    check buf.highlight.getColorPair(row, 0) == identifier
    check buf.highlight.getSegmentBg(row, 0) == some(deletedWordBg)
    check buf.highlight.getSegmentBg(row, 2) == some(deletedLineBg)
    check buf.highlight.getColorPair(row, 4) == decNumber
    check buf.highlight.getSegmentBg(row, 4) == some(deletedWordBg)
    check buf.highlight.getColorPair(row, rightStart) == identifier
    check buf.highlight.getSegmentBg(row, rightStart) == some(addedWordBg)
    check buf.highlight.getSegmentBg(row, rightStart + 2) == some(addedLineBg)
    check buf.highlight.getSegmentBg(row, rightStart + 4) == some(addedWordBg)

  test "Word highlight off leaves only the line background":
    var st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "@@ -1,1 +1,1 @@", kind: dlkHeader),
      DiffLine(text: "-hello world", kind: dlkDeleted),
      DiffLine(text: "+hello nim", kind: dlkAdded),
    ]
    st.rebuildSideRows()
    st.viewMode = dvmSideBySide
    st.wordHighlight = false
    let buf = st.createSideBySideTextBuffer(80)
    let
      addedWordBg = getThemeStyle(diffViewerAddedWord).bg
      deletedWordBg = getThemeStyle(diffViewerDeletedWord).bg
      deletedLineBg = getThemeStyle(diffViewerDeletedLineBg).bg
    for col in 0 ..< buf.getLine(1).charLen:
      let bg = buf.highlight.getSegmentBg(1, col)
      check bg != some(addedWordBg)
      check bg != some(deletedWordBg)
      if col < buf.getLine(1).find(SideBySideSeparator):
        check bg == some(deletedLineBg)
    checkRowCoverage(buf, 1)

  test "Overlong rows still cover the full panel width":
    var st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "@@ -1,1 +1,1 @@", kind: dlkHeader),
      DiffLine(text: "-" & 'a'.repeat(100), kind: dlkDeleted),
      DiffLine(text: "+" & 'b'.repeat(100), kind: dlkAdded),
    ]
    st.rebuildSideRows()
    st.viewMode = dvmSideBySide
    st.wordHighlight = false
    let buf = st.createSideBySideTextBuffer(80)
    let
      addedLineBg = getThemeStyle(diffViewerAddedLineBg).bg
      deletedLineBg = getThemeStyle(diffViewerDeletedLineBg).bg
    let row = 1
    check buf.getLine(row).charDisplayWidth == 80
    checkRowCoverage(buf, row)
    check buf.highlight.getSegmentBg(row, 0) == some(deletedLineBg)
    check buf.highlight.getSegmentBg(row, buf.getLine(row).charLen - 1) ==
      some(addedLineBg)

  test "Wide characters keep contiguous coverage and backgrounds":
    var st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "@@ -1,1 +1,1 @@", kind: dlkHeader),
      DiffLine(text: "-日本語テキスト", kind: dlkDeleted),
      DiffLine(text: "+日本語テスト", kind: dlkAdded),
    ]
    st.rebuildSideRows()
    st.viewMode = dvmSideBySide
    let buf = st.createSideBySideTextBuffer(80)
    let row = 1
    check buf.getLine(row).charDisplayWidth == 80
    checkRowCoverage(buf, row)
    let divider = charPos(buf.getLine(row), SideBySideSeparator) + 1
    check buf.highlight.getSegmentBg(row, divider).isNone

suite "side-by-side: toggles":
  test "toggleViewMode flips the requested mode and leaves the remap to refresh":
    var st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "a", kind: dlkNormal),
      DiffLine(text: "b", kind: dlkNormal),
      DiffLine(text: "c", kind: dlkNormal),
    ]
    st.sideRows = @[SideBySideRow(kind: sbrContext, leftText: "a", rightText: "a")]
    st.renderedSideBySide = true
    st.selectedIndex = 2
    st.toggleViewMode()
    check st.isSideBySide
    check st.selectedIndex == 2
    st.toggleViewMode()
    check not st.isSideBySide

  test "refresh clamps the selection to the generated presentation":
    var st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "@@ -1,2 +1,2 @@", kind: dlkHeader),
      DiffLine(text: "-a", kind: dlkDeleted),
      DiffLine(text: "+b", kind: dlkAdded),
      DiffLine(text: "-c", kind: dlkDeleted),
      DiffLine(text: "+d", kind: dlkAdded),
    ]
    st.rebuildSideRows()
    check st.items.len == 5
    check st.sideRows.len == 3
    st.viewMode = dvmSideBySide
    st.selectedIndex = 4
    discard st.refreshDiffTextBuffer(160)
    check st.renderedSideBySide
    check st.selectedIndex == 2
    # A narrow window keeps the unified buffer, so its lower rows stay
    # reachable; the selection maps back to the item that side row 2 showed.
    discard st.refreshDiffTextBuffer(10)
    check not st.renderedSideBySide
    check st.selectedIndex == 3

  test "toggling keeps the selection on the same diff line":
    var st = newDiffViewerState()
    st.items = @[DiffLine(text: "@@ -1,6 +1,6 @@", kind: dlkHeader)]
    for i in 0 .. 2:
      st.items.add DiffLine(text: "-old" & $i, kind: dlkDeleted)
      st.items.add DiffLine(text: "+new" & $i, kind: dlkAdded)
      st.items.add DiffLine(text: " ctx" & $i, kind: dlkNormal)
    st.rebuildSideRows()
    # Each -/+ pair collapses into one row, so the two index spaces differ.
    check st.items.len == 10
    check st.sideRows.len == 7

    st.viewMode = dvmSideBySide
    # Unified row 7 is "-old2"; its side row shows the same content.
    st.selectedIndex = 7
    discard st.refreshDiffTextBuffer(160)
    check st.renderedSideBySide
    check st.sideRows[st.selectedIndex].leftText == "old2"
    # Toggling back lands on the unified line the side row came from.
    st.toggleViewMode()
    discard st.refreshDiffTextBuffer(160)
    check not st.renderedSideBySide
    check st.items[st.selectedIndex].text == "-old2"

  test "a no-newline marker maps to the row before it":
    var st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "@@ -1,2 +1,2 @@", kind: dlkHeader),
      DiffLine(text: " ctx", kind: dlkNormal),
      DiffLine(text: "-a", kind: dlkDeleted),
      DiffLine(text: "\\ No newline at end of file", kind: dlkNormal),
      DiffLine(text: "+b", kind: dlkAdded),
    ]
    st.rebuildSideRows()
    # The marker has no row of its own.
    check st.sideRows.len == 3
    check st.sideRowForItem(3) == st.sideRowForItem(2)
    check st.itemForSideRow(st.sideRowForItem(3)) == 2

  test "toggleWordHighlight flips":
    var st = newDiffViewerState()
    check st.wordHighlight
    st.toggleWordHighlight()
    check not st.wordHighlight

  test "initDiffViewerState honors initial mode":
    let backupFile = getTempDir() / "moe_sbs_init_backup.txt"
    let sourceFile = getTempDir() / "moe_sbs_init_source.txt"
    writeFile(backupFile, "a\n\tX\nb\n")
    writeFile(sourceFile, "a\n\tY\nb\n")
    defer:
      removeFile(backupFile)
      removeFile(sourceFile)

    let st = initDiffViewerState(sourceFile, backupFile, dvmSideBySide, false, 4)
    check st.isSideBySide
    check not st.wordHighlight
    st.ensureSideRows()
    var changed = -1
    for i, row in st.sideRows:
      if row.kind == sbrChanged:
        changed = i
        break
    check changed >= 0
    # tabStop = 4 is applied to both panels.
    check st.sideRows[changed].leftText == "    X"
    check st.sideRows[changed].rightText == "    Y"

suite "side-by-side: handler keys":
  test "s toggles view":
    var st = newDiffViewerState()
    st.items = @[DiffLine(text: "a", kind: dlkNormal)]
    st.sideRows = @[SideBySideRow(kind: sbrContext, leftText: "a", rightText: "a")]
    let r = handleDiffViewerModeKey(st, 24, charKey("s"))
    check r.kind == dvrToggleView
    check st.isSideBySide

  test "w toggles word highlight":
    var st = newDiffViewerState()
    let r = handleDiffViewerModeKey(st, 24, charKey("w"))
    check r.kind == dvrToggleWord
    check not st.wordHighlight

  test "navigation clamps to sideRows in side-by-side mode":
    var st = newDiffViewerState()
    # 10 unified items but only 2 side rows: j must not run past row 1.
    for i in 0 ..< 10:
      st.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    st.sideRows = @[
      SideBySideRow(kind: sbrContext, leftText: "a", rightText: "a"),
      SideBySideRow(kind: sbrContext, leftText: "b", rightText: "b"),
    ]
    st.viewMode = dvmSideBySide
    st.renderedSideBySide = true
    st.selectedIndex = 1
    let r = handleDiffViewerModeKey(st, 24, charKey("j"))
    check r.kind == dvrHandled
    check st.selectedIndex == 1

  test "navigation keeps unified rows reachable after a narrow fallback":
    var st = newDiffViewerState()
    # side-by-side was requested but the narrow buffer is unified: j must be
    # free to reach every unified row, not just the side row count.
    for i in 0 ..< 10:
      st.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    st.sideRows = @[SideBySideRow(kind: sbrContext, leftText: "a", rightText: "a")]
    st.viewMode = dvmSideBySide
    st.renderedSideBySide = false
    st.selectedIndex = 0
    let r = handleDiffViewerModeKey(st, 24, charKey("j"))
    check r.kind == dvrHandled
    check st.selectedIndex == 1

suite "side-by-side: tab expansion":
  test "Leading tab expands position-dependently":
    check expandTabsForDiff("\tfoo", 2) == "  foo"
    check expandTabsForDiff("a\tb", 2) == "a b"
    check expandTabsForDiff("ab\tc", 2) == "ab  c"
    check expandTabsForDiff("a\tb", 4) == "a   b"

  test "Non-positive tabStop coerces to 1":
    check expandTabsForDiff("\ta", 0) == " a"
    check expandTabsForDiff("\ta", -3) == " a"

  test "No tabs leaves text unchanged":
    check expandTabsForDiff("  foo bar", 2) == "  foo bar"
    check expandTabsForDiff("", 2) == ""

  test "Rows contain no tabs and separators align":
    let items = @[
      DiffLine(text: "@@ -1,2 +1,2 @@", kind: dlkHeader),
      DiffLine(text: "-\tfoo", kind: dlkDeleted),
      DiffLine(text: "+\tfoo", kind: dlkAdded),
      DiffLine(text: "   bar", kind: dlkNormal),
    ]
    let rows = buildSideBySideRows(items, 2)
    check rows[1].leftText == "  foo"
    check rows[1].rightText == "  foo"
    check '\t' notin rows[1].leftText
    check rows[2].leftText == "  bar"
    # Same display width on the left panel, so the │ column is stable.
    let leftWidth = sidePanelWidth(80)
    let line1 = rows[1].formatSideBySideLine(leftWidth)
    let tabRow = SideBySideRow(
      kind: sbrContext, leftText: "\tfoo".expandTabsForDiff(2), rightText: "x"
    )
    let spaceRow = SideBySideRow(kind: sbrContext, leftText: "  foo", rightText: "x")
    check tabRow.formatSideBySideLine(leftWidth).find(SideBySideSeparator) ==
      spaceRow.formatSideBySideLine(leftWidth).find(SideBySideSeparator)
    check line1.find(SideBySideSeparator) ==
      spaceRow.formatSideBySideLine(leftWidth).find(SideBySideSeparator)

  test "Word ranges stay within expanded text":
    let items = @[
      DiffLine(text: "@@ -1,1 +1,1 @@", kind: dlkHeader),
      DiffLine(text: "-\told", kind: dlkDeleted),
      DiffLine(text: "+\tnew", kind: dlkAdded),
    ]
    let rows = buildSideBySideRows(items, 2)
    check rows[1].kind == sbrChanged
    for r in rows[1].leftWordRanges:
      check r.endCol <= rows[1].leftText.charLen
    for r in rows[1].rightWordRanges:
      check r.endCol <= rows[1].rightText.charLen

suite "side-by-side: toggle routing and repaint":
  proc createTestEditor(): Editor =
    newEditor(newEditorConfig(), newValidationResult())

  proc bufferHasSeparator(buf: TextBuffer): bool =
    for i in 0 ..< buf.len:
      if SideBySideSeparator in buf.getLine(i):
        return true
    false

  proc hasWordBackground(buf: TextBuffer, colorIndex: EditorColorPairIndex): bool =
    let expected = getThemeStyle(colorIndex).bg
    for i in 0 ..< buf.len:
      for col in 0 ..< buf.getLine(i).charLen:
        if buf.highlight.getSegmentBg(i, col) == some(expected):
          return true
    false

  proc setupDiffViewer(e: Editor, width: int): DiffViewerState =
    ## Install an open (already repainted) diff viewer in the active window.
    let win = e.activeWindow
    win.viewport.width = width
    win.mode = EditorMode.DiffViewer
    e.setMode(EditorMode.DiffViewer)
    let backupFile = getTempDir() / "moe_sbs_route_backup.txt"
    let sourceFile = getTempDir() / "moe_sbs_route_source.txt"
    writeFile(backupFile, "a\n\tX\nb\n")
    writeFile(sourceFile, "a\n\tY\nb\n")
    result = initDiffViewerState(sourceFile, backupFile)
    win.modeState = ModeState(kind: mskDiffViewer, diffViewer: result)
    win.buffer = result.refreshDiffTextBuffer(
      e.textAreaWidthForRows(win, max(result.items.len, result.sideRows.len))
    )
    defer:
      removeFile(backupFile)
      removeFile(sourceFile)

  test "s routes through processResult and repaints in side-by-side":
    let e = createTestEditor()
    let st = e.setupDiffViewer(160)
    let win = e.activeWindow
    check not bufferHasSeparator(win.buffer)

    let r = handleDiffViewerModeKey(st, 24, charKey("s"))
    check r.kind == dvrToggleView
    discard
      e.processResult(HandlerResult(kind: hrDiffViewerToggleView), e.activeBuffer())

    check st.renderedSideBySide
    check win.cursor.line == st.selectedIndex
    check bufferHasSeparator(win.buffer)
    check e.state.statusMessage == "Diff: side-by-side"

  test "narrow s falls back to unified and reports both widths":
    let e = createTestEditor()
    let st = e.setupDiffViewer(40)
    let win = e.activeWindow

    let r = handleDiffViewerModeKey(st, 24, charKey("s"))
    check r.kind == dvrToggleView
    discard
      e.processResult(HandlerResult(kind: hrDiffViewerToggleView), e.activeBuffer())

    check not st.renderedSideBySide
    check not bufferHasSeparator(win.buffer)
    check e.state.statusMessage ==
      "Diff: unified (side-by-side needs " & $SideBySideMinWidth & " columns, have " &
      $e.diffViewerTextWidth(win, st) & ")"

  test "resize rebuilds the buffer when the text width changes":
    let e = createTestEditor()
    let st = e.setupDiffViewer(160)
    let win = e.activeWindow
    var buffer = createTestBuffer()

    let r = handleDiffViewerModeKey(st, 24, charKey("s"))
    check r.kind == dvrToggleView
    discard
      e.processResult(HandlerResult(kind: hrDiffViewerToggleView), e.activeBuffer())
    check st.renderedSideBySide
    check bufferHasSeparator(win.buffer)

    # Narrowing must fall back to unified without a toggle or new key event.
    win.viewport.width = 40
    e.advanceLayoutForFrame(buffer, false)
    check not st.renderedSideBySide
    check not bufferHasSeparator(win.buffer)

    # Widening restores the requested side-by-side view.
    win.viewport.width = 160
    e.advanceLayoutForFrame(buffer, false)
    check st.renderedSideBySide
    check bufferHasSeparator(win.buffer)

  test "An 80-column terminal is wide enough for two columns":
    # The threshold is measured against the text area, so the line-number
    # gutter must not push the most common terminal size below it.
    let e = createTestEditor()
    let st = e.setupDiffViewer(80)

    let r = handleDiffViewerModeKey(st, 24, charKey("s"))
    check r.kind == dvrToggleView
    discard
      e.processResult(HandlerResult(kind: hrDiffViewerToggleView), e.activeBuffer())

    check st.renderedSideBySide
    check bufferHasSeparator(e.activeWindow.buffer)
    check e.state.statusMessage == "Diff: side-by-side"

  test "textAreaWidthForRows excludes the projected gutter":
    let e = createTestEditor()
    let win = e.activeWindow
    win.modeState = ModeState(kind: mskDiffViewer, diffViewer: newDiffViewerState())
    win.viewport.width = 100

    e.showLineNumbers = true
    # Gutter = digits(row count) + 1 spacer; the diff viewer has no sidebar.
    check e.textAreaWidthForRows(win, 6) == 98
    check e.textAreaWidthForRows(win, 150) == 96
    check e.textAreaWidthForRows(win, 0) == 100

    e.showLineNumbers = false
    check e.textAreaWidthForRows(win, 150) == 100

  test "diffViewerTextWidth follows the effective presentation's row count":
    let e = createTestEditor()
    let win = e.activeWindow
    win.viewport.width = 160
    e.showLineNumbers = true

    var st = newDiffViewerState()
    # 11 unified rows but only 3 side rows: the gutters differ (2 vs 1 digit),
    # so sizing with items.len would leave the rightmost column uncovered.
    for i in 0 ..< 11:
      st.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    st.sideRows = @[
      SideBySideRow(kind: sbrContext, leftText: "a", rightText: "a"),
      SideBySideRow(kind: sbrContext, leftText: "b", rightText: "b"),
      SideBySideRow(kind: sbrContext, leftText: "c", rightText: "c"),
    ]
    check e.textAreaWidthForRows(win, 3) != e.textAreaWidthForRows(win, 11)

    st.viewMode = dvmSideBySide
    check e.diffViewerTextWidth(win, st) == e.textAreaWidthForRows(win, 3)

    st.viewMode = dvmUnified
    check e.diffViewerTextWidth(win, st) == e.textAreaWidthForRows(win, 11)

    # Side-by-side requested but too narrow for two columns: the unified row
    # count sizes the fallback buffer.
    st.viewMode = dvmSideBySide
    win.viewport.width = 40
    check e.diffViewerTextWidth(win, st) == e.textAreaWidthForRows(win, 11)

  test "diffViewerTextWidth builds the side rows before measuring them":
    let e = createTestEditor()
    let win = e.activeWindow
    win.viewport.width = 160
    e.showLineNumbers = true

    var st = newDiffViewerState()
    st.items.add(DiffLine(text: "@@ -1,11 +1,11 @@", kind: dlkHeader))
    for i in 0 ..< 11:
      st.items.add(DiffLine(text: " line " & $i, kind: dlkNormal))
    st.viewMode = dvmSideBySide
    # The rows are built lazily, so the first side-by-side sizing happens with
    # an empty `sideRows`: measuring it as one row shrinks the gutter and makes
    # the buffer wider than the text area, clipping the rightmost column.
    check st.sideRows.len == 0

    let textWidth = e.diffViewerTextWidth(win, st)
    check st.sideRows.len == 12
    check textWidth == e.textAreaWidthForRows(win, 12)
    check textWidth != e.textAreaWidthForRows(win, 1)

    # The very first generated buffer already fits the text area exactly.
    # Row 0 is the hunk header, which spans as-is; row 1 is the first
    # two-column row.
    let buf = st.refreshDiffTextBuffer(textWidth)
    check st.renderedSideBySide
    check buf.getLine(1).charDisplayWidth == e.textAreaWidthForRows(
      win, st.sideRows.len
    )

  test "side-by-side buffer fills the effective text width":
    let e = createTestEditor()
    let win = e.activeWindow
    win.viewport.width = 160
    e.showLineNumbers = true
    var st = newDiffViewerState()
    for i in 0 ..< 11:
      st.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    st.sideRows = @[
      SideBySideRow(kind: sbrContext, leftText: "a", rightText: "a"),
      SideBySideRow(kind: sbrContext, leftText: "b", rightText: "b"),
      SideBySideRow(kind: sbrContext, leftText: "c", rightText: "c"),
    ]
    st.viewMode = dvmSideBySide
    let textWidth = e.diffViewerTextWidth(win, st)
    let buf = st.refreshDiffTextBuffer(textWidth)
    check st.renderedSideBySide
    # The row spans the whole text area the renderer will give this buffer, so
    # no default-background column remains at the right edge.
    check buf.getLine(0).charDisplayWidth == e.textAreaWidthForRows(
      win, st.sideRows.len
    )

  test "w routes through processResult and repaints word highlight":
    let e = createTestEditor()
    let st = e.setupDiffViewer(160)
    let win = e.activeWindow
    st.viewMode = dvmSideBySide
    win.buffer = st.refreshDiffTextBuffer(
      e.textAreaWidthForRows(win, max(st.items.len, st.sideRows.len))
    )
    check st.wordHighlight
    check hasWordBackground(win.buffer, EditorColorPairIndex.diffViewerAddedWord)

    let r = handleDiffViewerModeKey(st, 24, charKey("w"))
    check r.kind == dvrToggleWord
    discard
      e.processResult(HandlerResult(kind: hrDiffViewerToggleWord), e.activeBuffer())
    check not st.wordHighlight
    check e.state.statusMessage == "Diff: word highlight off"
    check not hasWordBackground(win.buffer, EditorColorPairIndex.diffViewerAddedWord)

    discard handleDiffViewerModeKey(st, 24, charKey("w"))
    discard
      e.processResult(HandlerResult(kind: hrDiffViewerToggleWord), e.activeBuffer())
    check st.wordHighlight
    check e.state.statusMessage == "Diff: word highlight on"
    check hasWordBackground(win.buffer, EditorColorPairIndex.diffViewerAddedWord)

  test "backup diff viewer honors [DiffViewer] config and tabStop":
    let e = createTestEditor()
    let win = e.activeWindow
    win.viewport.width = 160
    e.tabStop = 4
    e.config.diffViewer.sideBySide = true
    e.config.diffViewer.wordHighlight = false

    let sourceFile = getTempDir() / "moe_sbs_cfg_source.txt"
    let backupFile = getTempDir() / "moe_sbs_cfg_backup.txt"
    writeFile(backupFile, "a\n\tX\nb\n")
    writeFile(sourceFile, "a\n\tY\nb\n")
    defer:
      removeFile(backupFile)
      removeFile(sourceFile)

    var bkState = newBackupManagerState()
    bkState.sourceFilePath = sourceFile
    let ts = dateTime(2025, mJan, 1, 0, 0, 0, zone = utc())
    bkState.items.add(
      BackupEntry(filename: "backup", timestamp: ts, fullPath: backupFile)
    )
    win.modeState = ModeState(kind: mskBackupManager, backupManager: bkState)
    win.mode = EditorMode.BackupManager
    e.setMode(EditorMode.BackupManager)

    discard e.processResult(
      HandlerResult(kind: hrBackupManagerOpenDiff, diffBackupIndex: 0), e.activeBuffer()
    )

    check win.modeState.kind == mskDiffViewer
    let dvState = win.modeState.diffViewer
    check dvState.isSideBySide
    check not dvState.wordHighlight
    check dvState.renderedSideBySide
    check bufferHasSeparator(win.buffer)
    var changed = -1
    for i, row in dvState.sideRows:
      if row.kind == sbrChanged:
        changed = i
        break
    check changed >= 0
    # tabStop = 4 reaches the side-by-side rows through the config wiring.
    check dvState.sideRows[changed].leftText == "    X"
    check dvState.sideRows[changed].rightText == "    Y"

suite "side-by-side: rebuild cost":
  test "Side rows are not built until the side-by-side view needs them":
    let backupFile = getTempDir() / "moe_sbs_lazy_backup.txt"
    let sourceFile = getTempDir() / "moe_sbs_lazy_source.txt"
    writeFile(backupFile, "a\nb\n")
    writeFile(sourceFile, "a\nc\n")
    defer:
      removeFile(backupFile)
      removeFile(sourceFile)

    # Unified is the default presentation and never reads the aligned rows,
    # so opening a diff must not pay for the pairing and the word diff.
    let st = initDiffViewerState(sourceFile, backupFile)
    check st.sideRows.len == 0
    discard st.refreshDiffTextBuffer(120)
    check st.sideRows.len == 0

    st.viewMode = dvmSideBySide
    discard st.refreshDiffTextBuffer(120)
    check st.sideRows.len > 0

  test "A resize only rebuilds when it changes what is drawn":
    let st = newDiffViewerState()
    st.items =
      @[DiffLine(text: "-a", kind: dlkDeleted), DiffLine(text: "+b", kind: dlkAdded)]
    discard st.refreshDiffTextBuffer(120)
    check not st.renderedSideBySide
    # The unified buffer does not depend on the width.
    check not st.needsWidthRebuild(60)
    check not st.needsWidthRebuild(200)

    st.viewMode = dvmSideBySide
    discard st.refreshDiffTextBuffer(120)
    check st.renderedSideBySide
    check st.needsWidthRebuild(121)
    # Crossing the fallback threshold switches presentation, so it rebuilds.
    check st.needsWidthRebuild(SideBySideMinWidth - 1)

  test "Word ranges survive a rebuild of the unified buffer":
    let st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "-a b", kind: dlkDeleted), DiffLine(text: "+a c", kind: dlkAdded)
    ]
    discard st.refreshDiffTextBuffer(120)
    let cached = st.unifiedWordRanges
    check cached.len == st.items.len
    check cached[0].len == 1
    discard st.refreshDiffTextBuffer(120)
    check st.unifiedWordRanges == cached

suite "side-by-side: word diff limits":
  test "Caps the word diff on a very long line before tokenizing":
    let
      oldLine = "x " & repeat("ab ", MaxWordDiffLineLength div 2)
      newLine = "y " & repeat("ab ", MaxWordDiffLineLength div 2)
    check oldLine.len > MaxWordDiffLineLength
    let (oldRanges, newRanges) = computeWordRanges(oldLine, newLine)
    # Both sides are marked changed wholesale instead of being tokenized.
    check oldRanges.len == 1
    check oldRanges[0].startCol == 0
    check oldRanges[0].endCol == oldLine.charLen
    check newRanges.len == 1
    check newRanges[0].endCol == newLine.charLen

  test "Skips side syntax highlighting on a file with too many lines":
    let backupFile = getTempDir() / "moe_sbs_bigfile_backup.nim"
    let sourceFile = getTempDir() / "moe_sbs_bigfile_source.nim"
    var lines: seq[string] = @[]
    for i in 0 .. MaxSyntaxHighlightLines:
      lines.add("let x" & $i & " = 0")
    writeFile(backupFile, lines.join("\n") & "\n")
    lines[0] = "let y0 = 1"
    writeFile(sourceFile, lines.join("\n") & "\n")
    defer:
      removeFile(backupFile)
      removeFile(sourceFile)

    let st = initDiffViewerState(sourceFile, backupFile, dvmSideBySide)
    st.ensureSideRows()
    st.ensureSideSyntax()
    for row in st.sideRows:
      check row.leftSyntax.len == 0
      check row.rightSyntax.len == 0

suite "side-by-side: word diff budget":
  proc changedItems(pairs: int): seq[DiffLine] =
    result.add(DiffLine(text: "@@ -1,1 +1,1 @@", kind: dlkHeader))
    for i in 0 ..< pairs:
      result.add(DiffLine(text: "-a b" & $i, kind: dlkDeleted))
    for i in 0 ..< pairs:
      result.add(DiffLine(text: "+a c" & $i, kind: dlkAdded))

  test "Word highlight off skips the per-pair word diff":
    let st = newDiffViewerState()
    st.items = changedItems(1)
    st.wordHighlight = false
    st.rebuildSideRows()
    # Row 0 is the hunk header; the changed pair follows.
    check st.sideRows[1].kind == sbrChanged
    check st.sideRows[1].leftWordRanges.len == 0
    check st.sideRows[1].rightWordRanges.len == 0

  test "Turning the word highlight back on rebuilds the rows with ranges":
    let st = newDiffViewerState()
    st.items = changedItems(1)
    st.wordHighlight = false
    st.ensureSideRows()
    check st.sideRows[1].leftWordRanges.len == 0

    st.toggleWordHighlight()
    st.ensureSideRows()
    check st.wordHighlight
    check st.sideRows[1].leftWordRanges.len == 1
    check st.sideRows[1].rightWordRanges.len == 1

    # Turning it off again keeps the rows: the segment builder ignores the
    # ranges, so there is nothing to rebuild.
    let rows = st.sideRows
    st.toggleWordHighlight()
    st.ensureSideRows()
    check st.sideRows == rows

  test "The whole-diff budget stops the per-pair word diff":
    let st = newDiffViewerState()
    st.items = changedItems(MaxWordDiffRows + 1)
    st.rebuildSideRows()
    # One header row plus one row per pair.
    check st.sideRows.len == MaxWordDiffRows + 2
    check st.sideRows[MaxWordDiffRows].leftWordRanges.len == 1
    check st.sideRows[MaxWordDiffRows + 1].kind == sbrChanged
    check st.sideRows[MaxWordDiffRows + 1].leftWordRanges.len == 0

  test "The whole-diff budget also bounds the unified ranges":
    let items = changedItems(MaxWordDiffRows + 1)
    let ranges = computeUnifiedWordRanges(items)
    check ranges.len == items.len
    # Item 0 is the hunk header; the deleted lines follow.
    check ranges[MaxWordDiffRows].len == 1
    check ranges[MaxWordDiffRows + 1].len == 0

suite "side-by-side: row order":
  test "sourceIndex stays non-decreasing when added lines come first":
    # `sideRowForItem` binary-searches on this order. GNU diff emits `-`
    # before `+`, but the builder takes arbitrary items.
    let items = @[
      DiffLine(text: "+x", kind: dlkAdded),
      DiffLine(text: "+z", kind: dlkAdded),
      DiffLine(text: "-y", kind: dlkDeleted),
    ]
    let rows = buildSideBySideRows(items)
    check rows.len == 2
    for i in 1 ..< rows.len:
      check rows[i].sourceIndex >= rows[i - 1].sourceIndex

    # The numbers travel with the rows, so they must be assigned after the
    # reorder, not while emitting.
    var lastOld = 0
    var lastNew = 0
    for row in rows:
      if row.oldLineNo > 0:
        check row.oldLineNo > lastOld
        lastOld = row.oldLineNo
      if row.newLineNo > 0:
        check row.newLineNo > lastNew
        lastNew = row.newLineNo

  test "A line outside any hunk spans both columns":
    # `diff` reports a binary difference as a single line with no hunk header.
    let message = "Binary files a/x.png and b/x.png differ"
    let rows = buildSideBySideRows(@[DiffLine(text: message, kind: dlkNormal)])
    check rows.len == 1
    check rows[0].kind == sbrMeta
    check rows[0].headerText == message
    # Spanning as-is keeps the text whole; two panels would truncate it.
    check rows[0].formatSideBySideLine(MinSidePanelWidth) == message

suite "side-by-side: filler panels":
  test "The filler reaches the divider on an unpaired row":
    var st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "@@ -1,3 +1,3 @@", kind: dlkHeader),
      DiffLine(text: " ctx", kind: dlkNormal),
      DiffLine(text: "+added", kind: dlkAdded),
      DiffLine(text: " ctx2", kind: dlkNormal),
      DiffLine(text: "-deleted", kind: dlkDeleted),
    ]
    st.rebuildSideRows()
    st.viewMode = dvmSideBySide
    let buf = st.createSideBySideTextBuffer(80)
    for row in 0 ..< buf.len:
      checkRowCoverage(buf, row)

    var addedRow = -1
    var deletedRow = -1
    for i, row in st.sideRows:
      if row.kind == sbrAdded:
        addedRow = i
      elif row.kind == sbrDeleted:
        deletedRow = i
    check addedRow >= 0
    check deletedRow >= 0

    let divider = charPos(buf.getLine(addedRow), "│")
    check divider > 0
    # The space between the filler panel and the divider belongs to the panel.
    check buf.highlight.getColorPair(addedRow, divider - 1) ==
      EditorColorPairIndex.diffViewerFiller
    check buf.highlight.getColorPair(deletedRow, divider + 1) ==
      EditorColorPairIndex.diffViewerFiller
    # The divider itself stays unfilled.
    check buf.highlight.getColorPair(addedRow, divider) == EditorColorPairIndex.default

suite "side-by-side: theme changes":
  test "A theme change rebuilds the baked backgrounds":
    let st = newDiffViewerState()
    st.items = @[
      DiffLine(text: "@@ -1,1 +1,1 @@", kind: dlkHeader),
      DiffLine(text: "-a", kind: dlkDeleted),
      DiffLine(text: "+b", kind: dlkAdded),
    ]
    discard st.refreshDiffTextBuffer(120)
    check not st.needsRebuild(120)

    var colors = themeColors
    colors[EditorColorPairIndex.diffViewerAddedLineBg].background =
      ThemeColor(rgb: Rgb(red: 1, green: 2, blue: 3))
    setThemeColors(colors)
    defer:
      setThemeColors(DefaultColors)

    # The segments carry concrete colors, so the width alone cannot tell the
    # buffer is stale.
    check not st.needsWidthRebuild(120)
    check st.needsRebuild(120)

    let buf = st.refreshDiffTextBuffer(120)
    check buf.highlight.getSegmentBg(2, 0) ==
      some(getThemeStyle(EditorColorPairIndex.diffViewerAddedLineBg).bg)
    check not st.needsRebuild(120)

suite "side-by-side: whitespace-only changes":
  test "Re-indentation marks both sides changed":
    let (oldRanges, newRanges) = computeWordRanges("  ", "\t")
    check oldRanges.len == 1
    check oldRanges[0].endCol == 2
    check newRanges.len == 1
    check newRanges[0].endCol == 1

  test "An empty side gets no range":
    let (oldRanges, newRanges) = computeWordRanges("", "x")
    check oldRanges.len == 0
    check newRanges.len == 1
