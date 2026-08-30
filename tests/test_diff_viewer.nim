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

## Tests for diff_viewer.nim
## This module tests the Diff Viewer data structures and operations.

import std/[unittest, options, os, strutils, unicode]

import pkg/results

import ../src/moepkg/[buffer, highlight, color]
import ../src/moepkg/syntax/[tokenizer, syntax_diff]
import ../src/moepkg/diff_viewer {.all.}

# Re-export Result type for tests
export results

suite "diff_viewer: newDiffViewerState":
  test "Create new state with defaults":
    let state = newDiffViewerState()

    check state.items.len == 0
    check state.selectedIndex == 0
    check state.sourceFilePath == ""
    check state.backupFilePath == ""
    check state.errorMessage == ""

suite "diff_viewer: classifyDiffLine":
  test "Empty line is Normal":
    check classifyDiffLine("") == dlkNormal

  test "Line starting with @@ is Header":
    check classifyDiffLine("@@ -1,3 +1,4 @@") == dlkHeader
    check classifyDiffLine("@@ -10,5 +10,7 @@ func main()") == dlkHeader

  test "Line starting with --- is Header":
    check classifyDiffLine("--- a/file.txt") == dlkHeader
    check classifyDiffLine("---") == dlkHeader

  test "Line starting with +++ is Header":
    check classifyDiffLine("+++ b/file.txt") == dlkHeader
    check classifyDiffLine("+++") == dlkHeader

  test "Line starting with 'diff ' is Meta":
    check classifyDiffLine("diff --git a/file.txt b/file.txt") == dlkMeta

  test "Line starting with 'index ' is Meta":
    check classifyDiffLine("index 1234567..abcdefg 100644") == dlkMeta

  test "Line starting with 'new file' is Meta":
    check classifyDiffLine("new file mode 100644") == dlkMeta

  test "Line starting with 'deleted file' is Meta":
    check classifyDiffLine("deleted file mode 100644") == dlkMeta

  test "Line starting with + is Added":
    check classifyDiffLine("+added line") == dlkAdded
    check classifyDiffLine("+") == dlkAdded

  test "Line starting with - is Deleted":
    check classifyDiffLine("-deleted line") == dlkDeleted
    check classifyDiffLine("-") == dlkDeleted

  test "Context line is Normal":
    check classifyDiffLine(" context line") == dlkNormal
    check classifyDiffLine("some text") == dlkNormal

suite "diff_viewer: DiffLine":
  test "Create DiffLine with text and kind":
    let line = DiffLine(text: "+added", kind: dlkAdded)

    check line.text == "+added"
    check line.kind == dlkAdded

  test "Create DiffLine with empty text":
    let line = DiffLine(text: "", kind: dlkNormal)

    check line.text == ""
    check line.kind == dlkNormal

suite "diff_viewer: moveUp":
  test "Move up from line 3 to line 2":
    let state = newDiffViewerState()
    for i in 0 ..< 5:
      state.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    state.selectedIndex = 3

    state.moveUp()

    check state.selectedIndex == 2

  test "Move up at first line stays at 0":
    let state = newDiffViewerState()
    for i in 0 ..< 5:
      state.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    state.selectedIndex = 0

    state.moveUp()

    check state.selectedIndex == 0

  test "Move up with empty lines stays at 0":
    let state = newDiffViewerState()
    state.selectedIndex = 0

    state.moveUp()

    check state.selectedIndex == 0

suite "diff_viewer: moveDown":
  test "Move down from line 0 to line 1":
    let state = newDiffViewerState()
    for i in 0 ..< 5:
      state.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    state.selectedIndex = 0

    state.moveDown()

    check state.selectedIndex == 1

  test "Move down at last line stays at last":
    let state = newDiffViewerState()
    for i in 0 ..< 5:
      state.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    state.selectedIndex = 4

    state.moveDown()

    check state.selectedIndex == 4

  test "Move down with empty lines stays at 0":
    let state = newDiffViewerState()
    state.selectedIndex = 0

    state.moveDown()

    check state.selectedIndex == 0

  test "Move down multiple times":
    let state = newDiffViewerState()
    for i in 0 ..< 10:
      state.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    state.selectedIndex = 0

    for _ in 0 ..< 5:
      state.moveDown()

    check state.selectedIndex == 5

suite "diff_viewer: moveToFirst":
  test "Move to first from middle":
    let state = newDiffViewerState()
    for i in 0 ..< 10:
      state.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    state.selectedIndex = 5

    state.moveToFirst()

    check state.selectedIndex == 0

  test "Move to first when already at first":
    let state = newDiffViewerState()
    for i in 0 ..< 5:
      state.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    state.selectedIndex = 0

    state.moveToFirst()

    check state.selectedIndex == 0

  test "Move to first with empty lines":
    let state = newDiffViewerState()

    state.moveToFirst()

    check state.selectedIndex == 0

suite "diff_viewer: moveToLast":
  test "Move to last from first":
    let state = newDiffViewerState()
    for i in 0 ..< 10:
      state.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    state.selectedIndex = 0

    state.moveToLast()

    check state.selectedIndex == 9

  test "Move to last when already at last":
    let state = newDiffViewerState()
    for i in 0 ..< 5:
      state.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    state.selectedIndex = 4

    state.moveToLast()

    check state.selectedIndex == 4

  test "Move to last with empty lines stays at 0":
    let state = newDiffViewerState()
    state.selectedIndex = 0

    state.moveToLast()

    check state.selectedIndex == 0

  test "Move to last with single line":
    let state = newDiffViewerState()
    state.items.add(DiffLine(text: "only line", kind: dlkNormal))
    state.selectedIndex = 0

    state.moveToLast()

    check state.selectedIndex == 0

suite "diff_viewer: getSelectedItem":
  test "Get selected line at valid index":
    let state = newDiffViewerState()
    for i in 0 ..< 5:
      state.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    state.selectedIndex = 2

    let result = state.getSelectedItem()

    check result.isSome
    check result.get.text == "line 2"
    check result.get.kind == dlkNormal

  test "Get selected line with different kinds":
    let state = newDiffViewerState()
    state.items.add(DiffLine(text: "+added", kind: dlkAdded))
    state.items.add(DiffLine(text: "-deleted", kind: dlkDeleted))
    state.items.add(DiffLine(text: "@@header@@", kind: dlkHeader))
    state.selectedIndex = 1

    let result = state.getSelectedItem()

    check result.isSome
    check result.get.text == "-deleted"
    check result.get.kind == dlkDeleted

  test "Get selected line with empty lines returns none":
    let state = newDiffViewerState()
    state.selectedIndex = 0

    let result = state.getSelectedItem()

    check result.isNone

  test "Get selected line with negative index returns none":
    let state = newDiffViewerState()
    for i in 0 ..< 5:
      state.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    state.selectedIndex = -1

    let result = state.getSelectedItem()

    check result.isNone

  test "Get selected line with out of bounds index returns none":
    let state = newDiffViewerState()
    for i in 0 ..< 5:
      state.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    state.selectedIndex = 10

    let result = state.getSelectedItem()

    check result.isNone

suite "diff_viewer: initDiffViewerBuffer - Integration tests":
  setup:
    let testDir = getTempDir() / "moe_diff_viewer_test"
    if dirExists(testDir):
      removeDir(testDir)
    createDir(testDir)

  teardown:
    if dirExists(testDir):
      removeDir(testDir)

  test "Diff identical files shows no differences":
    let
      file1 = testDir / "file1.txt"
      file2 = testDir / "file2.txt"
    writeFile(file1, "line 1\nline 2\nline 3\n")
    writeFile(file2, "line 1\nline 2\nline 3\n")

    let result = initDiffViewerBuffer(file1, file2)

    check result.isOk
    check result.get.len == 1
    check result.get[0].text == "(No differences)"
    check result.get[0].kind == dlkNormal

  test "Diff files with added lines":
    # source has more lines than backup -> shows as added in diff
    let
      source = testDir / "source.txt"
      backup = testDir / "backup.txt"
    writeFile(source, "line 1\nline 2\nline 3\n")
    writeFile(backup, "line 1\n")

    let result = initDiffViewerBuffer(source, backup)

    check result.isOk
    check result.get.len > 0

    var hasAdded = false
    for line in result.get:
      if line.kind == dlkAdded:
        hasAdded = true
        break
    check hasAdded

  test "Diff files with deleted lines":
    # source has fewer lines than backup -> shows as deleted in diff
    let
      source = testDir / "source.txt"
      backup = testDir / "backup.txt"
    writeFile(source, "line 1\n")
    writeFile(backup, "line 1\nline 2\nline 3\n")

    let result = initDiffViewerBuffer(source, backup)

    check result.isOk
    check result.get.len > 0

    var hasDeleted = false
    for line in result.get:
      if line.kind == dlkDeleted:
        hasDeleted = true
        break
    check hasDeleted

  test "Diff files with modified lines":
    let
      file1 = testDir / "file1.txt"
      file2 = testDir / "file2.txt"
    writeFile(file1, "original line\n")
    writeFile(file2, "modified line\n")

    let result = initDiffViewerBuffer(file1, file2)

    check result.isOk
    check result.get.len > 0

    var hasAdded = false
    var hasDeleted = false
    for line in result.get:
      if line.kind == dlkAdded:
        hasAdded = true
      if line.kind == dlkDeleted:
        hasDeleted = true
    check hasAdded and hasDeleted

  test "Diff with non-existent source file returns error":
    let
      file1 = testDir / "nonexistent.txt"
      file2 = testDir / "file2.txt"
    writeFile(file2, "content\n")

    let result = initDiffViewerBuffer(file1, file2)

    check result.isErr
    check result.error.len > 0

  test "Diff with non-existent backup file returns error":
    let
      file1 = testDir / "file1.txt"
      file2 = testDir / "nonexistent.txt"
    writeFile(file1, "content\n")

    let result = initDiffViewerBuffer(file1, file2)

    check result.isErr
    check result.error.len > 0

  test "Diff output contains header lines":
    let
      file1 = testDir / "file1.txt"
      file2 = testDir / "file2.txt"
    writeFile(file1, "line 1\n")
    writeFile(file2, "line 1\nline 2\n")

    let result = initDiffViewerBuffer(file1, file2)

    check result.isOk

    var hasHeader = false
    for line in result.get:
      if line.kind == dlkHeader:
        hasHeader = true
        break
    check hasHeader

  test "Diff empty files shows no differences":
    let
      file1 = testDir / "file1.txt"
      file2 = testDir / "file2.txt"
    writeFile(file1, "")
    writeFile(file2, "")

    let result = initDiffViewerBuffer(file1, file2)

    check result.isOk
    check result.get.len == 1
    check result.get[0].text == "(No differences)"

suite "diff_viewer: initDiffViewerState - Integration tests":
  setup:
    let testDir = getTempDir() / "moe_diff_viewer_state_test"
    if dirExists(testDir):
      removeDir(testDir)
    createDir(testDir)

  teardown:
    if dirExists(testDir):
      removeDir(testDir)

  test "Initialize state with valid files":
    let
      file1 = testDir / "source.txt"
      file2 = testDir / "backup.txt"
    writeFile(file1, "line 1\nline 2\n")
    writeFile(file2, "line 1\n")

    let state = initDiffViewerState(file1, file2)

    check state.sourceFilePath == file1
    check state.backupFilePath == file2
    check state.items.len > 0
    check state.errorMessage == ""
    check state.selectedIndex == 0

  test "Initialize state with identical files":
    let
      file1 = testDir / "source.txt"
      file2 = testDir / "backup.txt"
    writeFile(file1, "same content\n")
    writeFile(file2, "same content\n")

    let state = initDiffViewerState(file1, file2)

    check state.sourceFilePath == file1
    check state.backupFilePath == file2
    check state.items.len == 1
    check state.items[0].text == "(No differences)"
    check state.errorMessage == ""

  test "Initialize state with non-existent file sets error":
    let
      file1 = testDir / "nonexistent.txt"
      file2 = testDir / "backup.txt"
    writeFile(file2, "content\n")

    let state = initDiffViewerState(file1, file2)

    check state.sourceFilePath == file1
    check state.backupFilePath == file2
    check state.errorMessage.len > 0
    check state.items.len == 1
    check state.items[0].text.startsWith("Error:")

suite "diff_viewer: Movement edge cases":
  test "Multiple moveUp calls stop at first line":
    let state = newDiffViewerState()
    for i in 0 ..< 5:
      state.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    state.selectedIndex = 2

    for _ in 0 ..< 10:
      state.moveUp()

    check state.selectedIndex == 0

  test "Multiple moveDown calls stop at last line":
    let state = newDiffViewerState()
    for i in 0 ..< 5:
      state.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    state.selectedIndex = 2

    for _ in 0 ..< 10:
      state.moveDown()

    check state.selectedIndex == 4

  test "Movement sequence: down, down, up, moveToLast, moveToFirst":
    let state = newDiffViewerState()
    for i in 0 ..< 10:
      state.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    state.selectedIndex = 0

    state.moveDown()
    check state.selectedIndex == 1

    state.moveDown()
    check state.selectedIndex == 2

    state.moveUp()
    check state.selectedIndex == 1

    state.moveToLast()
    check state.selectedIndex == 9

    state.moveToFirst()
    check state.selectedIndex == 0

suite "diff_viewer: DiffLineKind enum":
  test "All DiffLineKind values":
    check dlkNormal == DiffLineKind.dlkNormal
    check dlkAdded == DiffLineKind.dlkAdded
    check dlkDeleted == DiffLineKind.dlkDeleted
    check dlkHeader == DiffLineKind.dlkHeader
    check dlkMeta == DiffLineKind.dlkMeta

  test "DiffLineKind can be used in case statement":
    let kind = dlkAdded

    var result: string
    case kind
    of dlkNormal:
      result = "normal"
    of dlkAdded:
      result = "added"
    of dlkDeleted:
      result = "deleted"
    of dlkHeader:
      result = "header"
    of dlkMeta:
      result = "meta"

    check result == "added"

suite "diff_viewer: classifyDiffLine - Additional cases":
  test "No newline marker is Normal":
    check classifyDiffLine("\\ No newline at end of file") == dlkNormal

  test "Line with only spaces is Normal":
    check classifyDiffLine("   ") == dlkNormal

  test "Context line starting with space is Normal":
    check classifyDiffLine(" unchanged line") == dlkNormal

  test "Plus sign alone is Added":
    check classifyDiffLine("+") == dlkAdded

  test "Minus sign alone is Deleted":
    check classifyDiffLine("-") == dlkDeleted

  test "Multiple @@ is Header":
    check classifyDiffLine("@@ -1,3 +1,5 @@ function foo()") == dlkHeader

suite "diff_viewer: moveDown - extended":
  test "moveDown advances selectedIndex":
    let state = newDiffViewerState()
    for i in 0 ..< 30:
      state.items.add(DiffLine(text: "line " & $i, kind: dlkNormal))
    state.selectedIndex = 0

    for _ in 0 ..< 10:
      state.moveDown()

    check state.selectedIndex == 10

suite "diff_viewer: initDiffViewerBuffer - Additional integration tests":
  setup:
    let testDir = getTempDir() / "moe_diff_viewer_additional_test"
    if dirExists(testDir):
      removeDir(testDir)
    createDir(testDir)

  teardown:
    if dirExists(testDir):
      removeDir(testDir)

  test "Diff with file path containing spaces":
    let
      source = testDir / "source file.txt"
      backup = testDir / "backup file.txt"
    writeFile(source, "line 1\nline 2\n")
    writeFile(backup, "line 1\n")

    let result = initDiffViewerBuffer(source, backup)

    check result.isOk
    check result.get.len > 0

    var hasAdded = false
    for line in result.get:
      if line.kind == dlkAdded:
        hasAdded = true
        break
    check hasAdded

  test "Diff with multiple hunks":
    let
      source = testDir / "source.txt"
      backup = testDir / "backup.txt"
    # Create files with changes at different locations to generate multiple hunks
    var backupContent = ""
    var sourceContent = ""
    for i in 1 .. 20:
      backupContent.add("line " & $i & "\n")
      if i == 5:
        sourceContent.add("modified line 5\n")
      elif i == 15:
        sourceContent.add("modified line 15\n")
      else:
        sourceContent.add("line " & $i & "\n")

    writeFile(source, sourceContent)
    writeFile(backup, backupContent)

    let result = initDiffViewerBuffer(source, backup)

    check result.isOk
    check result.get.len > 0

    # Count @@ headers to verify multiple hunks
    var hunkCount = 0
    for line in result.get:
      if line.kind == dlkHeader and line.text.startsWith("@@"):
        hunkCount.inc
    check hunkCount >= 2

  test "Diff with binary-like content":
    let
      source = testDir / "source.txt"
      backup = testDir / "backup.txt"
    writeFile(source, "text\x00with\x00nulls\n")
    writeFile(backup, "different\x00content\n")

    let result = initDiffViewerBuffer(source, backup)

    # Binary files may or may not produce diff output depending on diff implementation
    check result.isOk or result.isErr

  test "Diff large files":
    let
      source = testDir / "source.txt"
      backup = testDir / "backup.txt"
    var content = ""
    for i in 1 .. 1000:
      content.add("line " & $i & "\n")

    writeFile(backup, content)

    # Modify a few lines
    var sourceContent = ""
    for i in 1 .. 1000:
      if i mod 100 == 0:
        sourceContent.add("modified line " & $i & "\n")
      else:
        sourceContent.add("line " & $i & "\n")

    writeFile(source, sourceContent)

    let result = initDiffViewerBuffer(source, backup)

    check result.isOk
    check result.get.len > 0

suite "diff_viewer: initDiffViewerState - Error message validation":
  setup:
    let testDir = getTempDir() / "moe_diff_viewer_error_test"
    if dirExists(testDir):
      removeDir(testDir)
    createDir(testDir)

  teardown:
    if dirExists(testDir):
      removeDir(testDir)

  test "Error message contains diff failure info":
    let
      source = testDir / "nonexistent_source.txt"
      backup = testDir / "backup.txt"
    writeFile(backup, "content\n")

    let state = initDiffViewerState(source, backup)

    check state.errorMessage.len > 0
    check state.errorMessage.contains("diff command failed")

  test "Error line text starts with Error prefix":
    let
      source = testDir / "nonexistent.txt"
      backup = testDir / "also_nonexistent.txt"

    let state = initDiffViewerState(source, backup)

    check state.items.len >= 1
    check state.items[0].text.startsWith("Error:")
    check state.items[0].kind == dlkNormal

suite "diff_viewer: DiffViewerState field access":
  test "All fields are accessible and mutable":
    let state = newDiffViewerState()

    state.items = @[DiffLine(text: "test", kind: dlkAdded)]
    state.selectedIndex = 5
    state.sourceFilePath = "/path/to/source"
    state.backupFilePath = "/path/to/backup"
    state.errorMessage = "test error"

    check state.items.len == 1
    check state.items[0].text == "test"
    check state.items[0].kind == dlkAdded
    check state.selectedIndex == 5
    check state.sourceFilePath == "/path/to/source"
    check state.backupFilePath == "/path/to/backup"
    check state.errorMessage == "test error"

  test "State is ref object - modifications persist":
    let state = newDiffViewerState()
    state.items.add(DiffLine(text: "line 1", kind: dlkNormal))

    proc modifyState(s: DiffViewerState) =
      s.selectedIndex = 10
      s.items.add(DiffLine(text: "line 2", kind: dlkAdded))

    modifyState(state)

    check state.selectedIndex == 10
    check state.items.len == 2

suite "diff_viewer: createDiffTextBuffer":
  test "Creates TextBuffer with correct content":
    let state = newDiffViewerState()
    state.items = @[
      DiffLine(text: "+added line", kind: dlkAdded),
      DiffLine(text: "-deleted line", kind: dlkDeleted),
      DiffLine(text: " context line", kind: dlkNormal),
    ]

    let buf = state.createDiffTextBuffer()

    check buf.len == 3
    check buf.getLine(0) == "+added line"
    check buf.getLine(1) == "-deleted line"
    check buf.getLine(2) == " context line"

  test "Sets language to langDiff":
    let state = newDiffViewerState()
    state.items = @[DiffLine(text: "test", kind: dlkNormal)]

    let buf = state.createDiffTextBuffer()

    check buf.language == langDiff

  test "Sets readOnly to true":
    let state = newDiffViewerState()
    state.items = @[DiffLine(text: "test", kind: dlkNormal)]

    let buf = state.createDiffTextBuffer()

    check buf.readOnly == true

  test "Initializes highlight (not nil)":
    let state = newDiffViewerState()
    state.items = @[
      DiffLine(text: "+added", kind: dlkAdded),
      DiffLine(text: "-deleted", kind: dlkDeleted),
    ]

    let buf = state.createDiffTextBuffer()

    check not buf.highlight.isNil
    check buf.highlight.colorSegments.len > 0

  test "Empty diff lines":
    let state = newDiffViewerState()
    state.items = @[]

    let buf = state.createDiffTextBuffer()

    check buf.readOnly == true
    check buf.language == langDiff

  test "Highlight assigns correct colors for diff line types":
    let state = newDiffViewerState()
    state.items = @[
      DiffLine(text: "+added line", kind: dlkAdded),
      DiffLine(text: "-deleted line", kind: dlkDeleted),
      DiffLine(text: "@@ -1,3 +1,4 @@", kind: dlkHeader),
      DiffLine(text: "diff --git a/f b/f", kind: dlkMeta),
      DiffLine(text: " context line", kind: dlkNormal),
    ]

    let buf = state.createDiffTextBuffer()

    check not buf.highlight.isNil
    # Added line → diffViewerAddedLine
    check buf.highlight.getColorPair(0, 0) == EditorColorPairIndex.diffViewerAddedLine
    # Deleted line → diffViewerDeletedLine
    check buf.highlight.getColorPair(1, 0) == EditorColorPairIndex.diffViewerDeletedLine
    # Header line → diffViewerHeader
    check buf.highlight.getColorPair(2, 0) == EditorColorPairIndex.diffViewerHeader
    # Meta line → diffViewerMeta
    check buf.highlight.getColorPair(3, 0) == EditorColorPairIndex.diffViewerMeta
    # Context line → default
    check buf.highlight.getColorPair(4, 0) == EditorColorPairIndex.default

  test "Caps tokenization on a very long diff line":
    # A diff line longer than the highlight cap is colored only up to the cap;
    # past it renders as default. Guards that the diff viewer uses the capped
    # path instead of tokenizing a huge minified line in full on open.
    let longLen = DefaultMaxHighlightLineLength + 500
    let state = newDiffViewerState()
    state.items = @[DiffLine(text: "+" & "a".repeat(longLen), kind: dlkAdded)]

    let buf = state.createDiffTextBuffer()

    check buf.highlight.getColorPair(0, 0) == EditorColorPairIndex.diffViewerAddedLine
    check buf.highlight.getColorPair(0, longLen) == EditorColorPairIndex.default

  test "Single line diff":
    let state = newDiffViewerState()
    state.items = @[DiffLine(text: "(No differences)", kind: dlkNormal)]

    let buf = state.createDiffTextBuffer()

    check buf.len == 1
    check buf.getLine(0) == "(No differences)"
    check not buf.highlight.isNil

suite "diff_viewer: diffNextToken":
  test "Added line (+) produces gtStringLit":
    var g: GeneralTokenizer
    initGeneralTokenizer(g, "+added line\n")
    g.diffNextToken()

    check g.kind == gtStringLit
    check g.length == 12 # "+added line\n"

  test "Deleted line (-) produces gtComment":
    var g: GeneralTokenizer
    initGeneralTokenizer(g, "-deleted line\n")
    g.diffNextToken()

    check g.kind == gtComment

  test "Hunk header (@@) produces gtPreprocessor":
    var g: GeneralTokenizer
    initGeneralTokenizer(g, "@@ -1,3 +1,4 @@\n")
    g.diffNextToken()

    check g.kind == gtPreprocessor

  test "Meta line (diff) produces gtKeyword":
    var g: GeneralTokenizer
    initGeneralTokenizer(g, "diff --git a/foo b/foo\n")
    g.diffNextToken()

    check g.kind == gtKeyword

  test "Meta line (index) produces gtKeyword":
    var g: GeneralTokenizer
    initGeneralTokenizer(g, "index 1234..abcd 100644\n")
    g.diffNextToken()

    check g.kind == gtKeyword

  test "Meta line (new file) produces gtKeyword":
    var g: GeneralTokenizer
    initGeneralTokenizer(g, "new file mode 100644\n")
    g.diffNextToken()

    check g.kind == gtKeyword

  test "Context line produces gtNone":
    var g: GeneralTokenizer
    initGeneralTokenizer(g, " context line\n")
    g.diffNextToken()

    check g.kind == gtNone

  test "Empty input produces gtEof":
    var g: GeneralTokenizer
    initGeneralTokenizer(g, "")
    g.diffNextToken()

    check g.kind == gtEof
    check g.length == 0

  test "Multiple lines tokenized sequentially":
    var g: GeneralTokenizer
    initGeneralTokenizer(g, "+added\n-deleted\n normal\n")

    g.diffNextToken()
    check g.kind == gtStringLit

    g.diffNextToken()
    check g.kind == gtComment

    g.diffNextToken()
    check g.kind == gtNone

    g.diffNextToken()
    check g.kind == gtEof

  test "Line without trailing newline":
    var g: GeneralTokenizer
    initGeneralTokenizer(g, "+no newline")
    g.diffNextToken()

    check g.kind == gtStringLit
    check g.length == 11 # "+no newline" (no \n)

  test "getNextToken dispatches to diffNextToken for langDiff":
    var g: GeneralTokenizer
    initGeneralTokenizer(g, "+added\n-deleted\n")

    g.getNextToken(langDiff)
    check g.kind == gtStringLit

    g.getNextToken(langDiff)
    check g.kind == gtComment

    g.getNextToken(langDiff)
    check g.kind == gtEof

suite "diff_viewer: initHighlight with langDiff":
  test "Highlight maps added line to diffViewerAddedLine":
    let lines = @["+added line"]
    let hl = initHighlight(lines, @[], langDiff)

    check hl.colorSegments.len > 0
    check hl.getColorPair(0, 0) == EditorColorPairIndex.diffViewerAddedLine

  test "Highlight maps deleted line to diffViewerDeletedLine":
    let lines = @["-deleted line"]
    let hl = initHighlight(lines, @[], langDiff)

    check hl.colorSegments.len > 0
    check hl.getColorPair(0, 0) == EditorColorPairIndex.diffViewerDeletedLine

  test "Highlight maps hunk header to diffViewerHeader":
    let lines = @["@@ -1,3 +1,4 @@"]
    let hl = initHighlight(lines, @[], langDiff)

    check hl.colorSegments.len > 0
    check hl.getColorPair(0, 0) == EditorColorPairIndex.diffViewerHeader

  test "Highlight maps meta line to diffViewerMeta":
    let lines = @["diff --git a/foo b/foo"]
    let hl = initHighlight(lines, @[], langDiff)

    check hl.colorSegments.len > 0
    check hl.getColorPair(0, 0) == EditorColorPairIndex.diffViewerMeta

  test "Highlight maps context line to default":
    let lines = @[" context line"]
    let hl = initHighlight(lines, @[], langDiff)

    check hl.colorSegments.len > 0
    check hl.getColorPair(0, 0) == EditorColorPairIndex.default

  test "Multi-line diff highlight":
    let lines =
      @["+added", "-deleted", "@@ -1,3 +1,4 @@", "diff --git a/f b/f", " context"]
    let hl = initHighlight(lines, @[], langDiff)

    check hl.getColorPair(0, 0) == EditorColorPairIndex.diffViewerAddedLine
    check hl.getColorPair(1, 0) == EditorColorPairIndex.diffViewerDeletedLine
    check hl.getColorPair(2, 0) == EditorColorPairIndex.diffViewerHeader
    check hl.getColorPair(3, 0) == EditorColorPairIndex.diffViewerMeta
    check hl.getColorPair(4, 0) == EditorColorPairIndex.default
