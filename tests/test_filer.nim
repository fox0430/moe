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

import std/[unittest, os, times, options, strutils]
import ../src/moepkg/filer {.all.}
import ../src/moepkg/[buffer, highlight, color]

suite "Filer - FileEntry":
  test "isDirectory returns true for directory":
    let entry = FileEntry(
      name: "testdir",
      kind: fekDirectory,
      size: 0,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekDirectory,
    )
    check entry.isDirectory == true
    check entry.isFile == false

  test "isDirectory returns true for symlink to directory":
    let entry = FileEntry(
      name: "linkdir",
      kind: fekSymlink,
      size: 0,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekDirectory,
    )
    check entry.isDirectory == true
    check entry.isFile == false

  test "isFile returns true for file":
    let entry = FileEntry(
      name: "testfile.txt",
      kind: fekFile,
      size: 100,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekFile,
    )
    check entry.isFile == true
    check entry.isDirectory == false

  test "isFile returns true for symlink to file":
    let entry = FileEntry(
      name: "linkfile",
      kind: fekSymlink,
      size: 0,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekFile,
    )
    check entry.isFile == true
    check entry.isDirectory == false

suite "Filer - FilerState creation":
  setup:
    let testDir = getTempDir() / "moe_filer_test"
    createDir(testDir)

  teardown:
    removeDir(testDir)

  test "newFilerState creates state with correct path":
    let state = newFilerState(testDir)
    check state.currentPath == absolutePath(testDir)
    check state.selectedIndex == 0
    check state.showHidden == true

suite "Filer - Directory navigation":
  setup:
    let testDir = getTempDir() / "moe_filer_test"
    createDir(testDir)
    createDir(testDir / "subdir1")
    createDir(testDir / "subdir2")
    writeFile(testDir / "file1.txt", "content1")
    writeFile(testDir / "file2.txt", "content2")

  teardown:
    removeDir(testDir)

  test "refresh loads directory contents":
    let state = newFilerState(testDir)
    # Should have ".." plus 2 subdirs and 2 files
    check state.entries.len == 5
    check state.entries[0].name == ".."

  test "enterDirectory changes current path":
    let state = newFilerState(testDir)
    let subdir = testDir / "subdir1"
    check state.enterDirectory(subdir) == true
    check state.currentPath == absolutePath(subdir)
    check state.selectedIndex == 0

  test "enterDirectory returns false for non-existent directory":
    let state = newFilerState(testDir)
    check state.enterDirectory("/nonexistent/path") == false
    check state.currentPath == absolutePath(testDir)

  test "goToParent moves to parent directory":
    let state = newFilerState(testDir / "subdir1")
    check state.goToParent() == true
    check state.currentPath == absolutePath(testDir)

  test "goToParent selects the directory we came from":
    let state = newFilerState(testDir / "subdir1")
    discard state.goToParent()
    let selected = state.getSelectedEntry()
    check selected.isSome
    check selected.get.name == "subdir1"

suite "Filer - Selection movement":
  setup:
    let testDir = getTempDir() / "moe_filer_test"
    createDir(testDir)
    writeFile(testDir / "a.txt", "")
    writeFile(testDir / "b.txt", "")
    writeFile(testDir / "c.txt", "")

  teardown:
    removeDir(testDir)

  test "moveDown increases selectedIndex":
    let state = newFilerState(testDir)
    check state.selectedIndex == 0
    state.moveDown()
    check state.selectedIndex == 1

  test "moveDown stops at last entry":
    let state = newFilerState(testDir)
    # Move beyond the list
    for i in 0 .. 10:
      state.moveDown()
    check state.selectedIndex == state.entries.len - 1

  test "moveUp decreases selectedIndex":
    let state = newFilerState(testDir)
    state.selectedIndex = 2
    state.moveUp()
    check state.selectedIndex == 1

  test "moveUp stops at first entry":
    let state = newFilerState(testDir)
    state.moveUp()
    check state.selectedIndex == 0

  test "moveToFirst moves to first entry":
    let state = newFilerState(testDir)
    state.selectedIndex = 3
    state.moveToFirst()
    check state.selectedIndex == 0

  test "moveToLast moves to last entry":
    let state = newFilerState(testDir)
    state.moveToLast()
    check state.selectedIndex == state.entries.len - 1

suite "Filer - Hidden files":
  setup:
    let testDir = getTempDir() / "moe_filer_test"
    createDir(testDir)
    writeFile(testDir / "visible.txt", "")
    writeFile(testDir / ".hidden", "")

  teardown:
    removeDir(testDir)

  test "hidden files are shown by default":
    let state = newFilerState(testDir)
    check state.showHidden == true
    # Should have "..", ".hidden", and "visible.txt"
    check state.entries.len == 3
    var hasHidden = false
    for entry in state.entries:
      if entry.name == ".hidden":
        hasHidden = true
    check hasHidden == true

  test "toggleHidden hides hidden files":
    let state = newFilerState(testDir)
    state.toggleHidden()
    check state.showHidden == false
    # Should have ".." and "visible.txt" only
    check state.entries.len == 2
    var hasHidden = false
    for entry in state.entries:
      if entry.name == ".hidden":
        hasHidden = true
    check hasHidden == false

  test "toggleHidden can show again":
    let state = newFilerState(testDir)
    state.toggleHidden()
    state.toggleHidden()
    check state.showHidden == true
    check state.entries.len == 3

suite "Filer - Selection queries":
  setup:
    let testDir = getTempDir() / "moe_filer_test"
    createDir(testDir)
    writeFile(testDir / "test.txt", "content")

  teardown:
    removeDir(testDir)

  test "getSelectedEntry returns current entry":
    let state = newFilerState(testDir)
    state.selectedIndex = 1 # Select test.txt
    let entry = state.getSelectedEntry()
    check entry.isSome
    check entry.get.name == "test.txt"

  test "getSelectedEntry returns none for invalid index":
    let state = newFilerState(testDir)
    state.selectedIndex = 100
    let entry = state.getSelectedEntry()
    check entry.isNone

  test "getSelectedPath returns full path":
    let state = newFilerState(testDir)
    state.selectedIndex = 1
    let path = state.getSelectedPath()
    check path.isSome
    check path.get == absolutePath(testDir) / "test.txt"

  test "getSelectedPath returns parent for ..":
    let state = newFilerState(testDir)
    state.selectedIndex = 0 # Select ".."
    let path = state.getSelectedPath()
    check path.isSome
    check path.get == parentDir(absolutePath(testDir))

suite "Filer - Viewport":
  setup:
    let testDir = getTempDir() / "moe_filer_test"
    createDir(testDir)
    for i in 0 ..< 20:
      writeFile(testDir / ("file" & $i & ".txt"), "")

  teardown:
    removeDir(testDir)

  test "halfPageDown moves selection":
    let state = newFilerState(testDir)
    state.selectedIndex = 0
    state.halfPageDown(20, 3)
    check state.selectedIndex > 0

  test "halfPageUp moves selection":
    let state = newFilerState(testDir)
    state.selectedIndex = 15
    state.halfPageUp(20, 3)
    check state.selectedIndex < 15

suite "Filer - File deletion":
  setup:
    let testDir = getTempDir() / "moe_filer_test"
    createDir(testDir)
    writeFile(testDir / "deleteme.txt", "content")
    createDir(testDir / "deletedir")
    writeFile(testDir / "deletedir" / "inner.txt", "inner")

  teardown:
    removeDir(testDir)

  test "deleteSelected deletes file":
    let state = newFilerState(testDir)
    # Find deleteme.txt
    for i, entry in state.entries:
      if entry.name == "deleteme.txt":
        state.selectedIndex = i
        break
    let (success, path, error) = state.deleteSelected()
    check success == true
    check path.endsWith("deleteme.txt")
    check error == ""
    check fileExists(testDir / "deleteme.txt") == false

  test "deleteSelected deletes directory recursively":
    let state = newFilerState(testDir)
    # Find deletedir
    for i, entry in state.entries:
      if entry.name == "deletedir":
        state.selectedIndex = i
        break
    let (success, path, error) = state.deleteSelected()
    check success == true
    check path.endsWith("deletedir")
    check error == ""
    check dirExists(testDir / "deletedir") == false

  test "deleteSelected cannot delete ..":
    let state = newFilerState(testDir)
    state.selectedIndex = 0 # ".."
    let (success, path, error) = state.deleteSelected()
    check success == false
    check path == ""
    check error == "Cannot delete parent directory reference"

suite "Filer - File info":
  setup:
    let testDir = getTempDir() / "moe_filer_test"
    createDir(testDir)
    writeFile(testDir / "info.txt", "test content")
    createDir(testDir / "infodir")

  teardown:
    removeDir(testDir)

  test "getSelectedInfo returns info for file":
    let state = newFilerState(testDir)
    for i, entry in state.entries:
      if entry.name == "info.txt":
        state.selectedIndex = i
        break
    let info = state.getSelectedInfo()
    check info.contains("info.txt")
    check info.contains("[File]")

  test "getSelectedInfo returns info for directory":
    let state = newFilerState(testDir)
    for i, entry in state.entries:
      if entry.name == "infodir":
        state.selectedIndex = i
        break
    let info = state.getSelectedInfo()
    check info.contains("infodir")
    check info.contains("[Dir]")

  test "getSelectedInfo returns parent directory for ..":
    let state = newFilerState(testDir)
    state.selectedIndex = 0
    let info = state.getSelectedInfo()
    check info == "Parent directory"

suite "Filer - Sorting":
  setup:
    let testDir = getTempDir() / "moe_filer_test"
    createDir(testDir)
    writeFile(testDir / "zebra.txt", "")
    writeFile(testDir / "apple.txt", "")
    createDir(testDir / "zdir")
    createDir(testDir / "adir")

  teardown:
    removeDir(testDir)

  test "directories appear before files":
    let state = newFilerState(testDir)
    # After "..", directories should come first
    var seenFile = false
    for entry in state.entries[1 ..^ 1]:
      if entry.kind == fekFile:
        seenFile = true
      elif entry.kind == fekDirectory and seenFile:
        # Found a directory after a file - fail
        check false

  test "entries are sorted alphabetically within type":
    let state = newFilerState(testDir)
    # Find directories (skip "..")
    var dirs: seq[string] = @[]
    var files: seq[string] = @[]
    for entry in state.entries[1 ..^ 1]:
      if entry.kind == fekDirectory:
        dirs.add(entry.name)
      else:
        files.add(entry.name)
    # Check directories are sorted
    check dirs.len == 2
    check dirs[0].toLowerAscii < dirs[1].toLowerAscii
    # Check files are sorted
    check files.len == 2
    check files[0].toLowerAscii < files[1].toLowerAscii

suite "Filer - Root directory":
  test "root directory has no parent entry":
    let state = newFilerState("/")
    # Root should not have ".." entry
    for entry in state.entries:
      check entry.name != ".."

  test "goToParent returns false at root":
    let state = newFilerState("/")
    check state.goToParent() == false
    check state.currentPath == "/"

suite "Filer - Empty directory":
  setup:
    let testDir = getTempDir() / "moe_filer_test_empty"
    createDir(testDir)

  teardown:
    removeDir(testDir)

  test "empty directory has only parent entry":
    let state = newFilerState(testDir)
    check state.entries.len == 1
    check state.entries[0].name == ".."

  test "moveToLast in empty directory selects parent":
    let state = newFilerState(testDir)
    state.moveToLast()
    check state.selectedIndex == 0
    check state.entries[state.selectedIndex].name == ".."

suite "Filer - Symlinks":
  setup:
    let testDir = getTempDir() / "moe_filer_test_symlink"
    createDir(testDir)
    writeFile(testDir / "realfile.txt", "content")
    createDir(testDir / "realdir")
    createSymlink(testDir / "realfile.txt", testDir / "linktofile")
    createSymlink(testDir / "realdir", testDir / "linktodir")

  teardown:
    removeDir(testDir)

  test "symlink to file is detected":
    let state = newFilerState(testDir)
    var found = false
    for entry in state.entries:
      if entry.name == "linktofile":
        found = true
        check entry.kind == fekSymlink
        check entry.targetKind == fekFile
        check entry.isFile == true
        check entry.isDirectory == false
    check found == true

  test "symlink to directory is detected":
    let state = newFilerState(testDir)
    var found = false
    for entry in state.entries:
      if entry.name == "linktodir":
        found = true
        check entry.kind == fekSymlink
        check entry.targetKind == fekDirectory
        check entry.isDirectory == true
        check entry.isFile == false
    check found == true

  test "getSelectedInfo shows symlink to file":
    let state = newFilerState(testDir)
    for i, entry in state.entries:
      if entry.name == "linktofile":
        state.selectedIndex = i
        break
    let info = state.getSelectedInfo()
    check info.contains("linktofile")
    check info.contains("[Symlink->File]")

  test "getSelectedInfo shows symlink to directory":
    let state = newFilerState(testDir)
    for i, entry in state.entries:
      if entry.name == "linktodir":
        state.selectedIndex = i
        break
    let info = state.getSelectedInfo()
    check info.contains("linktodir")
    check info.contains("[Symlink->Dir]")

  test "deleteSelected deletes symlink":
    let state = newFilerState(testDir)
    for i, entry in state.entries:
      if entry.name == "linktofile":
        state.selectedIndex = i
        break
    let (success, _, error) = state.deleteSelected()
    check success == true
    check error == ""
    check symlinkExists(testDir / "linktofile") == false
    # Original file should still exist
    check fileExists(testDir / "realfile.txt") == true

suite "Filer - Executable files":
  setup:
    let testDir = getTempDir() / "moe_filer_test_exec"
    createDir(testDir)
    writeFile(testDir / "script.sh", "#!/bin/bash\necho hello")
    setFilePermissions(testDir / "script.sh", {fpUserRead, fpUserWrite, fpUserExec})
    writeFile(testDir / "normal.txt", "content")

  teardown:
    removeDir(testDir)

  test "executable file is detected":
    let state = newFilerState(testDir)
    var foundExec = false
    var foundNormal = false
    for entry in state.entries:
      if entry.name == "script.sh":
        foundExec = true
        check entry.isExecutable == true
      if entry.name == "normal.txt":
        foundNormal = true
        check entry.isExecutable == false
    check foundExec == true
    check foundNormal == true

  test "getSelectedInfo shows executable flag":
    let state = newFilerState(testDir)
    for i, entry in state.entries:
      if entry.name == "script.sh":
        state.selectedIndex = i
        break
    let info = state.getSelectedInfo()
    check info.contains("[x]")

suite "Filer - Selection edge cases":
  setup:
    let testDir = getTempDir() / "moe_filer_test_edge"
    createDir(testDir)
    writeFile(testDir / "file.txt", "content")

  teardown:
    removeDir(testDir)

  test "deleteSelected returns error when no selection":
    let state = newFilerState(testDir)
    state.selectedIndex = 100 # Invalid index
    let (success, path, error) = state.deleteSelected()
    check success == false
    check path == ""
    check error == "No file selected"

  test "getSelectedInfo returns message when no selection":
    let state = newFilerState(testDir)
    state.selectedIndex = 100 # Invalid index
    let info = state.getSelectedInfo()
    check info == "No file selected"

  test "getSelectedPath returns none when no selection":
    let state = newFilerState(testDir)
    state.selectedIndex = 100
    let path = state.getSelectedPath()
    check path.isNone

suite "Filer - Viewport edge cases":
  setup:
    let testDir = getTempDir() / "moe_filer_test_viewport"
    createDir(testDir)
    for i in 0 ..< 5:
      writeFile(testDir / ("file" & $i & ".txt"), "")

  teardown:
    removeDir(testDir)

  test "halfPageDown stops at last entry":
    let state = newFilerState(testDir)
    state.selectedIndex = state.entries.len - 2
    state.halfPageDown(20, 3)
    check state.selectedIndex == state.entries.len - 1

  test "halfPageUp stops at first entry":
    let state = newFilerState(testDir)
    state.selectedIndex = 1
    state.halfPageUp(20, 3)
    check state.selectedIndex == 0

suite "Filer - File size formatting":
  setup:
    let testDir = getTempDir() / "moe_filer_test_size"
    createDir(testDir)

  teardown:
    removeDir(testDir)

  test "small file shows bytes":
    writeFile(testDir / "small.txt", "x".repeat(500))
    let state = newFilerState(testDir)
    for i, entry in state.entries:
      if entry.name == "small.txt":
        state.selectedIndex = i
        break
    let info = state.getSelectedInfo()
    check info.contains(" B")

  test "kilobyte file shows KB":
    writeFile(testDir / "medium.txt", "x".repeat(2048))
    let state = newFilerState(testDir)
    for i, entry in state.entries:
      if entry.name == "medium.txt":
        state.selectedIndex = i
        break
    let info = state.getSelectedInfo()
    check info.contains(" KB")

suite "Filer - Trailing slash normalization":
  test "newFilerState strips trailing slash":
    let state = newFilerState("/tmp/")
    check state.currentPath == "/tmp"

  test "newFilerState preserves root path":
    let state = newFilerState("/")
    check state.currentPath == "/"

  test "enterDirectory strips trailing slash":
    let state = newFilerState("/tmp")
    check state.enterDirectory("/tmp/") == true
    check state.currentPath == "/tmp"

suite "Filer - Tilde expansion":
  test "newFilerState expands tilde":
    let state = newFilerState("~")
    check state.currentPath == normalizedPath(expandTilde("~"))
    check state.currentPath != "~"

suite "Filer - Refresh behavior":
  setup:
    let testDir = getTempDir() / "moe_filer_test_refresh"
    createDir(testDir)
    writeFile(testDir / "initial.txt", "")

  teardown:
    removeDir(testDir)

  test "refresh updates entries when files are added":
    let state = newFilerState(testDir)
    check state.entries.len == 2 # ".." and "initial.txt"

    writeFile(testDir / "new.txt", "")
    state.refresh()

    check state.entries.len == 3

  test "refresh adjusts selectedIndex when it becomes invalid":
    let state = newFilerState(testDir)
    writeFile(testDir / "temp1.txt", "")
    writeFile(testDir / "temp2.txt", "")
    state.refresh()
    state.selectedIndex = state.entries.len - 1

    # Delete files to make selectedIndex invalid
    removeFile(testDir / "temp1.txt")
    removeFile(testDir / "temp2.txt")
    state.refresh()

    check state.selectedIndex < state.entries.len

suite "Filer - pathToIcon":
  test "Directory icon":
    let entry = FileEntry(
      name: "mydir",
      kind: fekDirectory,
      size: 0,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekDirectory,
    )
    check pathToIcon(entry) == "📁 "

  test "Nim file icon":
    let entry = FileEntry(
      name: "main.nim",
      kind: fekFile,
      size: 100,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekFile,
    )
    check pathToIcon(entry) == "👑 "

  test "Executable file icon":
    let entry = FileEntry(
      name: "run",
      kind: fekFile,
      size: 100,
      modified: getTime(),
      isHidden: false,
      isExecutable: true,
      targetKind: fekFile,
    )
    check pathToIcon(entry) == "🏃 "

  test "Dockerfile icon":
    let entry = FileEntry(
      name: "Dockerfile",
      kind: fekFile,
      size: 100,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekFile,
    )
    check pathToIcon(entry) == "🐳 "

  test "Unknown extension icon":
    let entry = FileEntry(
      name: "data.xyz",
      kind: fekFile,
      size: 100,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekFile,
    )
    check pathToIcon(entry) == "📄 "

suite "Filer - createFilerTextBuffer":
  test "Buffer line count equals entries":
    let entries = @[
      FileEntry(
        name: "dir1",
        kind: fekDirectory,
        size: 0,
        modified: getTime(),
        isHidden: false,
        isExecutable: false,
        targetKind: fekDirectory,
      ),
      FileEntry(
        name: "file1.txt",
        kind: fekFile,
        size: 100,
        modified: getTime(),
        isHidden: false,
        isExecutable: false,
        targetKind: fekFile,
      ),
    ]
    let state = FilerState(
      currentPath: "/tmp", entries: entries, selectedIndex: 0, showHidden: false
    )
    let buf = state.createFilerTextBuffer(false)
    check buf.len == entries.len

  test "Buffer with icons enabled":
    let entries = @[
      FileEntry(
        name: "main.nim",
        kind: fekFile,
        size: 100,
        modified: getTime(),
        isHidden: false,
        isExecutable: false,
        targetKind: fekFile,
      )
    ]
    let state = FilerState(
      currentPath: "/tmp", entries: entries, selectedIndex: 0, showHidden: false
    )
    let buf = state.createFilerTextBuffer(true)
    # Line 0 should contain the icon for .nim files
    check buf.getLine(0).contains("👑")

  test "Buffer without icons shows kind markers":
    let entries = @[
      FileEntry(
        name: "mydir",
        kind: fekDirectory,
        size: 0,
        modified: getTime(),
        isHidden: false,
        isExecutable: false,
        targetKind: fekDirectory,
      )
    ]
    let state = FilerState(
      currentPath: "/tmp", entries: entries, selectedIndex: 0, showHidden: false
    )
    let buf = state.createFilerTextBuffer(false)
    check buf.getLine(0).contains("▸")

  test "Buffer is read-only and utility":
    let state =
      FilerState(currentPath: "/tmp", entries: @[], selectedIndex: 0, showHidden: false)
    let buf = state.createFilerTextBuffer(false)
    check buf.readOnly == true
    check buf.isUtilityBuffer == true

  test "Highlight segments count matches entries + 1":
    let entries = @[
      FileEntry(
        name: "dir1",
        kind: fekDirectory,
        size: 0,
        modified: getTime(),
        isHidden: false,
        isExecutable: false,
        targetKind: fekDirectory,
      ),
      FileEntry(
        name: "file.txt",
        kind: fekFile,
        size: 100,
        modified: getTime(),
        isHidden: false,
        isExecutable: false,
        targetKind: fekFile,
      ),
    ]
    let state = FilerState(
      currentPath: "/tmp", entries: entries, selectedIndex: 0, showHidden: false
    )
    let buf = state.createFilerTextBuffer(false)
    check not buf.highlight.isNil
    # 1 per entry
    check buf.highlight.colorSegments.len == entries.len

  test "needsBufferRefresh is set after refresh":
    let state = FilerState(
      currentPath: "/tmp",
      entries: @[],
      selectedIndex: 0,
      showHidden: false,
      needsBufferRefresh: false,
    )
    state.refresh()
    check state.needsBufferRefresh == true

  test "filePath is set to currentPath":
    let state = FilerState(
      currentPath: "/home/user", entries: @[], selectedIndex: 0, showHidden: false
    )
    let buf = state.createFilerTextBuffer(false)
    check buf.filePath.isSome
    check buf.filePath.get == "/home/user"

  test "highlightNeedsUpdate is false":
    let state =
      FilerState(currentPath: "/tmp", entries: @[], selectedIndex: 0, showHidden: false)
    let buf = state.createFilerTextBuffer(false)
    check buf.highlightNeedsUpdate == false

  test "Directory entry line ends with slash":
    let entries = @[
      FileEntry(
        name: "mydir",
        kind: fekDirectory,
        size: 0,
        modified: getTime(),
        isHidden: false,
        isExecutable: false,
        targetKind: fekDirectory,
      )
    ]
    let state = FilerState(
      currentPath: "/tmp", entries: entries, selectedIndex: 0, showHidden: false
    )
    let buf = state.createFilerTextBuffer(false)
    check buf.getLine(0).endsWith("mydir/")

  test "File entry line does not end with slash":
    let entries = @[
      FileEntry(
        name: "file.txt",
        kind: fekFile,
        size: 100,
        modified: getTime(),
        isHidden: false,
        isExecutable: false,
        targetKind: fekFile,
      )
    ]
    let state = FilerState(
      currentPath: "/tmp", entries: entries, selectedIndex: 0, showHidden: false
    )
    let buf = state.createFilerTextBuffer(false)
    check buf.getLine(0).endsWith("file.txt")
    check not buf.getLine(0).endsWith("/")

  test "Symlink entry without icons shows @ marker":
    let entries = @[
      FileEntry(
        name: "link",
        kind: fekSymlink,
        size: 0,
        modified: getTime(),
        isHidden: false,
        isExecutable: false,
        targetKind: fekFile,
      )
    ]
    let state = FilerState(
      currentPath: "/tmp", entries: entries, selectedIndex: 0, showHidden: false
    )
    let buf = state.createFilerTextBuffer(false)
    check buf.getLine(0).contains("@ ")

  test "Directory entry highlight uses filerDirectory color":
    let entries = @[
      FileEntry(
        name: "dir1",
        kind: fekDirectory,
        size: 0,
        modified: getTime(),
        isHidden: false,
        isExecutable: false,
        targetKind: fekDirectory,
      )
    ]
    let state = FilerState(
      currentPath: "/tmp", entries: entries, selectedIndex: 0, showHidden: false
    )
    let buf = state.createFilerTextBuffer(false)
    check buf.highlight.colorSegments[0].color == EditorColorPairIndex.filerDirectory

  test "Symlink-to-file highlight uses filerSymlink color":
    let entries = @[
      FileEntry(
        name: "link",
        kind: fekSymlink,
        size: 0,
        modified: getTime(),
        isHidden: false,
        isExecutable: false,
        targetKind: fekFile,
      )
    ]
    let state = FilerState(
      currentPath: "/tmp", entries: entries, selectedIndex: 0, showHidden: false
    )
    let buf = state.createFilerTextBuffer(false)
    check buf.highlight.colorSegments[0].color == EditorColorPairIndex.filerSymlink

  test "Symlink-to-dir highlight uses filerSymlinkDir color":
    let entries = @[
      FileEntry(
        name: "linkdir",
        kind: fekSymlink,
        size: 0,
        modified: getTime(),
        isHidden: false,
        isExecutable: false,
        targetKind: fekDirectory,
      )
    ]
    let state = FilerState(
      currentPath: "/tmp", entries: entries, selectedIndex: 0, showHidden: false
    )
    let buf = state.createFilerTextBuffer(false)
    check buf.highlight.colorSegments[0].color == EditorColorPairIndex.filerSymlinkDir

  test "Hidden file highlight uses filerHiddenFile color":
    let entries = @[
      FileEntry(
        name: ".hidden",
        kind: fekFile,
        size: 0,
        modified: getTime(),
        isHidden: true,
        isExecutable: false,
        targetKind: fekFile,
      )
    ]
    let state = FilerState(
      currentPath: "/tmp", entries: entries, selectedIndex: 0, showHidden: true
    )
    let buf = state.createFilerTextBuffer(false)
    check buf.highlight.colorSegments[0].color == EditorColorPairIndex.filerHiddenFile

  test "Executable file highlight uses filerExecutable color":
    let entries = @[
      FileEntry(
        name: "run.sh",
        kind: fekFile,
        size: 100,
        modified: getTime(),
        isHidden: false,
        isExecutable: true,
        targetKind: fekFile,
      )
    ]
    let state = FilerState(
      currentPath: "/tmp", entries: entries, selectedIndex: 0, showHidden: false
    )
    let buf = state.createFilerTextBuffer(false)
    check buf.highlight.colorSegments[0].color == EditorColorPairIndex.filerExecutable

  test "Normal file highlight uses default color":
    let entries = @[
      FileEntry(
        name: "normal.txt",
        kind: fekFile,
        size: 100,
        modified: getTime(),
        isHidden: false,
        isExecutable: false,
        targetKind: fekFile,
      )
    ]
    let state = FilerState(
      currentPath: "/tmp", entries: entries, selectedIndex: 0, showHidden: false
    )
    let buf = state.createFilerTextBuffer(false)
    check buf.highlight.colorSegments[0].color == EditorColorPairIndex.default

  test "Symlink to directory shows folder icon with icons enabled":
    let entries = @[
      FileEntry(
        name: "linkdir",
        kind: fekSymlink,
        size: 0,
        modified: getTime(),
        isHidden: false,
        isExecutable: false,
        targetKind: fekDirectory,
      )
    ]
    let state = FilerState(
      currentPath: "/tmp", entries: entries, selectedIndex: 0, showHidden: false
    )
    let buf = state.createFilerTextBuffer(true)
    check buf.getLine(0).contains("📁")

  test "Symlink to directory line ends with slash":
    let entries = @[
      FileEntry(
        name: "linkdir",
        kind: fekSymlink,
        size: 0,
        modified: getTime(),
        isHidden: false,
        isExecutable: false,
        targetKind: fekDirectory,
      )
    ]
    let state = FilerState(
      currentPath: "/tmp", entries: entries, selectedIndex: 0, showHidden: false
    )
    let buf = state.createFilerTextBuffer(false)
    check buf.getLine(0).endsWith("linkdir/")

suite "Filer - pathToIcon additional":
  test "Symlink to directory icon":
    let entry = FileEntry(
      name: "link",
      kind: fekSymlink,
      size: 0,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekDirectory,
    )
    check pathToIcon(entry) == "📁 "

  test "Python file icon":
    let entry = FileEntry(
      name: "script.py",
      kind: fekFile,
      size: 100,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekFile,
    )
    check pathToIcon(entry) == "🐍 "

  test "Rust file icon":
    let entry = FileEntry(
      name: "main.rs",
      kind: fekFile,
      size: 100,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekFile,
    )
    check pathToIcon(entry) == "🦀 "

  test "Go file icon":
    let entry = FileEntry(
      name: "main.go",
      kind: fekFile,
      size: 100,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekFile,
    )
    check pathToIcon(entry) == "🐹 "

  test "Shell script icon":
    let entry = FileEntry(
      name: "build.sh",
      kind: fekFile,
      size: 100,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekFile,
    )
    check pathToIcon(entry) == "🐚 "

  test "Dockerfile variant icon":
    let entry = FileEntry(
      name: "Dockerfile.dev",
      kind: fekFile,
      size: 100,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekFile,
    )
    check pathToIcon(entry) == "🐳 "

  test "No extension file icon":
    let entry = FileEntry(
      name: "Makefile",
      kind: fekFile,
      size: 100,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekFile,
    )
    check pathToIcon(entry) == "📄 "

  test "Lock file icon":
    let entry = FileEntry(
      name: "package.lock",
      kind: fekFile,
      size: 100,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekFile,
    )
    check pathToIcon(entry) == "🔒 "

  test "Nix file icon":
    let entry = FileEntry(
      name: "default.nix",
      kind: fekFile,
      size: 100,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekFile,
    )
    check pathToIcon(entry) == "❄ "

  test "TOML file icon":
    let entry = FileEntry(
      name: "config.toml",
      kind: fekFile,
      size: 100,
      modified: getTime(),
      isHidden: false,
      isExecutable: false,
      targetKind: fekFile,
    )
    check pathToIcon(entry) == "⚙ "

suite "Filer - needsBufferRefresh flag":
  setup:
    let testDir = getTempDir() / "moe_test_refresh_flag"
    createDir(testDir)
    writeFile(testDir / "a.txt", "")
    createDir(testDir / "subdir")

  teardown:
    removeDir(testDir)

  test "enterDirectory sets needsBufferRefresh":
    let state = newFilerState(testDir)
    state.needsBufferRefresh = false
    discard state.enterDirectory(testDir / "subdir")
    check state.needsBufferRefresh == true

  test "goToParent sets needsBufferRefresh":
    let state = newFilerState(testDir / "subdir")
    state.needsBufferRefresh = false
    discard state.goToParent()
    check state.needsBufferRefresh == true

  test "toggleHidden sets needsBufferRefresh":
    let state = newFilerState(testDir)
    state.needsBufferRefresh = false
    state.toggleHidden()
    check state.needsBufferRefresh == true

  test "deleteSelected sets needsBufferRefresh":
    let state = newFilerState(testDir)
    # Select a.txt (skip ".." at index 0)
    for i, e in state.entries:
      if e.name == "a.txt":
        state.selectedIndex = i
        break
    state.needsBufferRefresh = false
    discard state.deleteSelected()
    check state.needsBufferRefresh == true
