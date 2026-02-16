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

import std/[unittest, os, osproc, strutils, options]

import pkg/results

import ../src/moepkg/buffer
import ../src/moepkg/git_diff {.all.}

suite "GitDiff - parseDiffHunk":
  test "Parse standard hunk header":
    let (startLine, lineCount) = parseDiffHunk("@@ -10,5 +10,7 @@")
    check startLine == 10
    check lineCount == 7

  test "Parse hunk header with single line":
    let (startLine, lineCount) = parseDiffHunk("@@ -1 +1 @@")
    check startLine == 1
    check lineCount == 1

  test "Parse hunk header with added lines only":
    let (startLine, lineCount) = parseDiffHunk("@@ -0,0 +1,3 @@")
    check startLine == 1
    check lineCount == 3

  test "Parse hunk header with zero line count":
    let (startLine, lineCount) = parseDiffHunk("@@ -5,2 +5,0 @@")
    check startLine == 5
    check lineCount == 0

  test "Parse hunk header with context text":
    let (startLine, lineCount) = parseDiffHunk("@@ -1,3 +1,4 @@ func main() {")
    check startLine == 1
    check lineCount == 4

  test "Parse invalid hunk header":
    let (startLine, lineCount) = parseDiffHunk("invalid")
    check startLine == 0
    check lineCount == 0

  test "Parse empty string":
    let (startLine, lineCount) = parseDiffHunk("")
    check startLine == 0
    check lineCount == 0

suite "GitDiff - processDeleteAddPairs":
  test "Convert single delete+add to modified":
    let lines = @[
      GitDiffLine(lineNumber: 5, kind: Deleted), GitDiffLine(lineNumber: 5, kind: Added)
    ]
    let result = processDeleteAddPairs(lines)

    check result.len == 1
    check result[0].lineNumber == 5
    check result[0].kind == Modified

  test "Convert multiple consecutive delete+add pairs to modified":
    let lines = @[
      GitDiffLine(lineNumber: 5, kind: Deleted),
      GitDiffLine(lineNumber: 6, kind: Deleted),
      GitDiffLine(lineNumber: 5, kind: Added),
      GitDiffLine(lineNumber: 6, kind: Added),
    ]
    let result = processDeleteAddPairs(lines)

    check result.len == 2
    check result[0].kind == Modified
    check result[1].kind == Modified

  test "More deletes than adds":
    let lines = @[
      GitDiffLine(lineNumber: 5, kind: Deleted),
      GitDiffLine(lineNumber: 6, kind: Deleted),
      GitDiffLine(lineNumber: 7, kind: Deleted),
      GitDiffLine(lineNumber: 5, kind: Added),
    ]
    let result = processDeleteAddPairs(lines)

    check result.len == 3
    check result[0].kind == Modified
    check result[1].kind == Deleted
    check result[2].kind == Deleted

  test "More adds than deletes":
    let lines = @[
      GitDiffLine(lineNumber: 5, kind: Deleted),
      GitDiffLine(lineNumber: 5, kind: Added),
      GitDiffLine(lineNumber: 6, kind: Added),
      GitDiffLine(lineNumber: 7, kind: Added),
    ]
    let result = processDeleteAddPairs(lines)

    check result.len == 3
    check result[0].kind == Modified
    check result[1].kind == Added
    check result[2].kind == Added

  test "Only deletes":
    let lines = @[
      GitDiffLine(lineNumber: 5, kind: Deleted),
      GitDiffLine(lineNumber: 6, kind: Deleted),
    ]
    let result = processDeleteAddPairs(lines)

    check result.len == 2
    check result[0].kind == Deleted
    check result[1].kind == Deleted

  test "Only adds":
    let lines = @[
      GitDiffLine(lineNumber: 5, kind: Added), GitDiffLine(lineNumber: 6, kind: Added)
    ]
    let result = processDeleteAddPairs(lines)

    check result.len == 2
    check result[0].kind == Added
    check result[1].kind == Added

  test "Empty input":
    let lines: seq[GitDiffLine] = @[]
    let result = processDeleteAddPairs(lines)

    check result.len == 0

  test "Non-consecutive groups":
    let lines = @[
      GitDiffLine(lineNumber: 5, kind: Deleted),
      GitDiffLine(lineNumber: 5, kind: Added),
      GitDiffLine(lineNumber: 10, kind: Deleted),
      GitDiffLine(lineNumber: 10, kind: Added),
    ]
    let result = processDeleteAddPairs(lines)

    check result.len == 2
    check result[0].kind == Modified
    check result[0].lineNumber == 5
    check result[1].kind == Modified
    check result[1].lineNumber == 10

suite "GitDiff - parseDiffOutput":
  test "Parse simple added lines":
    let output = """diff --git a/test.txt b/test.txt
index 1234567..abcdefg 100644
--- a/test.txt
+++ b/test.txt
@@ -1,0 +1,2 @@
+line 1
+line 2
"""
    let diffInfo = parseDiffOutput(output)

    check diffInfo.lines.len == 2
    check diffInfo.lines[0].lineNumber == 0
    check diffInfo.lines[0].kind == Added
    check diffInfo.lines[1].lineNumber == 1
    check diffInfo.lines[1].kind == Added

  test "Parse deleted lines":
    let output = """@@ -1,2 +1,0 @@
-deleted line 1
-deleted line 2
"""
    let diffInfo = parseDiffOutput(output)

    check diffInfo.lines.len == 2
    check diffInfo.lines[0].kind == Deleted
    check diffInfo.lines[1].kind == Deleted

  test "Parse modified lines (delete+add)":
    let output = """@@ -5,1 +5,1 @@
-old line
+new line
"""
    let diffInfo = parseDiffOutput(output)

    check diffInfo.lines.len == 1
    check diffInfo.lines[0].kind == Modified
    check diffInfo.lines[0].lineNumber == 4

  test "Parse multiple hunks":
    let output = """@@ -1,1 +1,1 @@
-old first
+new first
@@ -10,1 +10,1 @@
-old tenth
+new tenth
"""
    let diffInfo = parseDiffOutput(output)

    check diffInfo.lines.len == 2
    check diffInfo.lines[0].kind == Modified
    check diffInfo.lines[0].lineNumber == 0
    check diffInfo.lines[1].kind == Modified
    check diffInfo.lines[1].lineNumber == 9

  test "Parse with context lines":
    let output = """@@ -2,3 +2,4 @@
 context line
-deleted
+added 1
+added 2
 context line
"""
    let diffInfo = parseDiffOutput(output)

    check diffInfo.lines.len == 2
    check diffInfo.lines[0].kind == Modified
    check diffInfo.lines[1].kind == Added

  test "Parse empty diff":
    let diffInfo = parseDiffOutput("")

    check diffInfo.lines.len == 0

  test "Parse diff with no newline marker":
    let output = """@@ -1,1 +1,1 @@
-old
+new
\ No newline at end of file
"""
    let diffInfo = parseDiffOutput(output)

    check diffInfo.lines.len == 1
    check diffInfo.lines[0].kind == Modified

suite "GitDiff - calculateRelativePath":
  test "Absolute path within git root":
    let result =
      calculateRelativePath("/home/user/repo/src/file.nim", "/home/user/repo")
    check result == "src/file.nim"

  test "Absolute path at git root":
    let result = calculateRelativePath("/home/user/repo/file.nim", "/home/user/repo")
    check result == "file.nim"

  test "Relative path":
    let result = calculateRelativePath("src/file.nim", "/home/user/repo")
    check result == "src/file.nim"

  test "Absolute path outside git root":
    let result = calculateRelativePath("/other/path/file.nim", "/home/user/repo")
    check result == "file.nim"

suite "GitDiff - countGitChangedLines":
  test "Count all types of changes":
    let diffInfo = GitDiffInfo(
      lines: @[
        GitDiffLine(lineNumber: 0, kind: Added),
        GitDiffLine(lineNumber: 1, kind: Added),
        GitDiffLine(lineNumber: 5, kind: Modified),
        GitDiffLine(lineNumber: 10, kind: Deleted),
        GitDiffLine(lineNumber: 11, kind: Deleted),
        GitDiffLine(lineNumber: 12, kind: Deleted),
      ]
    )

    let (added, modified, deleted) = countGitChangedLines(diffInfo)

    check added == 2
    check modified == 1
    check deleted == 3

  test "Count empty diff":
    let diffInfo = GitDiffInfo(lines: @[])

    let (added, modified, deleted) = countGitChangedLines(diffInfo)

    check added == 0
    check modified == 0
    check deleted == 0

  test "Count only added":
    let diffInfo = GitDiffInfo(
      lines: @[
        GitDiffLine(lineNumber: 0, kind: Added), GitDiffLine(lineNumber: 1, kind: Added)
      ]
    )

    let (added, modified, deleted) = countGitChangedLines(diffInfo)

    check added == 2
    check modified == 0
    check deleted == 0

suite "GitDiff - applyGitDiffToBuffer":
  test "Apply diff to buffer sets markers":
    let buf = newTextBuffer()
    discard buf.insertText(
      BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3\nLine 4\nLine 5"
    )

    let diffInfo = GitDiffInfo(
      lines: @[
        GitDiffLine(lineNumber: 0, kind: Added),
        GitDiffLine(lineNumber: 2, kind: Modified),
        GitDiffLine(lineNumber: 4, kind: Deleted),
      ]
    )

    buf.applyGitDiffToBuffer(diffInfo)

    check buf.getLineMarker(0) == some(GitAdded)
    check buf.getLineMarker(1) == none(SidebarItemKind)
    check buf.getLineMarker(2) == some(GitChanged)
    check buf.getLineMarker(3) == none(SidebarItemKind)
    check buf.getLineMarker(4) == some(GitDeleted)

  test "Apply empty diff clears markers":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2")
    buf.setLineMarker(0, GitAdded)
    buf.setLineMarker(1, GitChanged)

    let diffInfo = GitDiffInfo(lines: @[])

    buf.applyGitDiffToBuffer(diffInfo)

    check buf.getLineMarker(0) == none(SidebarItemKind)
    check buf.getLineMarker(1) == none(SidebarItemKind)

  test "Apply diff ignores out of bounds lines":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2")

    let diffInfo = GitDiffInfo(
      lines: @[
        GitDiffLine(lineNumber: 0, kind: Added),
        GitDiffLine(lineNumber: 10, kind: Modified),
        GitDiffLine(lineNumber: -1, kind: Deleted),
      ]
    )

    buf.applyGitDiffToBuffer(diffInfo)

    check buf.getLineMarker(0) == some(GitAdded)
    check buf.getLineMarker(1) == none(SidebarItemKind)

suite "GitDiff - getGitDiff":
  test "Non-existent file returns error":
    let result = getGitDiff("/nonexistent/path/file.txt")

    check result.isErr
    check result.error.contains("does not exist")

suite "GitDiff - getGitDiffFromBuffer":
  test "Buffer without file path returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "test")

    let result = getGitDiffFromBuffer(buf)

    check result.isErr
    check result.error == "Buffer has no associated file path"

suite "GitDiff - getGitBranch":
  test "Non-existent file returns error":
    let result = getGitBranch("/nonexistent/path/file.txt")

    check result.isErr
    check result.error.contains("does not exist")

suite "GitDiff - startGitDiffAsync":
  test "Non-existent file returns error":
    let result = startGitDiffAsync("/nonexistent/path/file.txt")

    check result.isErr
    check result.error.contains("does not exist")

suite "GitDiff - startGitDiffFromBufferAsync":
  test "Buffer without file path returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "test")

    let result = startGitDiffFromBufferAsync(buf)

    check result.isErr
    check result.error == "Buffer has no associated file path"

suite "GitDiff - Integration tests with git repository":
  setup:
    let testDir = getTempDir() / "moe_git_diff_test"
    if dirExists(testDir):
      removeDir(testDir)
    createDir(testDir)

    discard execCmdEx("git init", workingDir = testDir)
    discard execCmdEx("git config user.email 'test@test.com'", workingDir = testDir)
    discard execCmdEx("git config user.name 'Test'", workingDir = testDir)

  teardown:
    if dirExists(testDir):
      removeDir(testDir)

  test "getGitBranch returns branch name":
    let testFile = testDir / "test.txt"
    writeFile(testFile, "initial content\n")
    discard execCmdEx("git add test.txt", workingDir = testDir)
    discard execCmdEx("git commit -m 'Initial commit'", workingDir = testDir)

    let result = getGitBranch(testFile)

    check result.isOk
    check result.get.len > 0

  test "getGitDiff with no changes":
    let testFile = testDir / "test.txt"
    writeFile(testFile, "initial content\n")
    discard execCmdEx("git add test.txt", workingDir = testDir)
    discard execCmdEx("git commit -m 'Initial commit'", workingDir = testDir)

    let result = getGitDiff(testFile)

    check result.isOk
    check result.get.lines.len == 0

  test "getGitDiff with modified file":
    let testFile = testDir / "test.txt"
    writeFile(testFile, "line 1\nline 2\nline 3\n")
    discard execCmdEx("git add test.txt", workingDir = testDir)
    discard execCmdEx("git commit -m 'Initial commit'", workingDir = testDir)

    writeFile(testFile, "line 1\nmodified line 2\nline 3\n")

    let result = getGitDiff(testFile)

    check result.isOk
    check result.get.lines.len > 0

  test "getGitDiff with added lines":
    let testFile = testDir / "test.txt"
    writeFile(testFile, "line 1\n")
    discard execCmdEx("git add test.txt", workingDir = testDir)
    discard execCmdEx("git commit -m 'Initial commit'", workingDir = testDir)

    writeFile(testFile, "line 1\nline 2\nline 3\n")

    let result = getGitDiff(testFile)

    check result.isOk
    check result.get.lines.len >= 2

  test "getGitDiff with deleted lines":
    let testFile = testDir / "test.txt"
    writeFile(testFile, "line 1\nline 2\nline 3\n")
    discard execCmdEx("git add test.txt", workingDir = testDir)
    discard execCmdEx("git commit -m 'Initial commit'", workingDir = testDir)

    writeFile(testFile, "line 1\n")

    let result = getGitDiff(testFile)

    check result.isOk
    check result.get.lines.len >= 2

  test "getGitDiffFromBuffer with modified buffer":
    let testFile = testDir / "test.txt"
    writeFile(testFile, "line 1\nline 2\nline 3\n")
    discard execCmdEx("git add test.txt", workingDir = testDir)
    discard execCmdEx("git commit -m 'Initial commit'", workingDir = testDir)

    let buf = newTextBuffer()
    let loadResult = buf.loadFile(testFile)
    check loadResult.isOk

    discard buf.deleteRange(
      BufferPosition(line: 1, column: 0), BufferPosition(line: 1, column: 5)
    )
    discard buf.insertText(BufferPosition(line: 1, column: 0), "modified")

    let result = getGitDiffFromBuffer(buf)

    check result.isOk
    check result.get.lines.len > 0

  test "startGitDiffAsync and checkGitDiffComplete":
    let testFile = testDir / "test.txt"
    writeFile(testFile, "line 1\nline 2\n")
    discard execCmdEx("git add test.txt", workingDir = testDir)
    discard execCmdEx("git commit -m 'Initial commit'", workingDir = testDir)

    writeFile(testFile, "line 1\nmodified\n")

    let startResult = startGitDiffAsync(testFile)
    check startResult.isOk

    let diffProc = startResult.get

    var completed = false
    for _ in 0 ..< 100:
      let checkResult = checkGitDiffComplete(diffProc)
      if checkResult.isSome:
        completed = true
        check checkResult.get.isOk
        break
      sleep(10)

    check completed

  test "updateBufferWithGitDiff":
    let testFile = testDir / "test.txt"
    writeFile(testFile, "line 1\nline 2\nline 3\n")
    discard execCmdEx("git add test.txt", workingDir = testDir)
    discard execCmdEx("git commit -m 'Initial commit'", workingDir = testDir)

    writeFile(testFile, "line 1\nmodified\nline 3\nnew line\n")

    let buf = newTextBuffer()
    discard buf.loadFile(testFile)

    let result = updateBufferWithGitDiff(buf, useBuffer = false)

    check result.isOk
