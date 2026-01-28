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
import ../src/moepkg/filer

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
    check state.showHidden == false
    check state.topLine == 0

  test "newFilerState with previousPath":
    let prevPath = "/some/previous/path"
    let state = newFilerState(testDir, some(prevPath))
    check state.previousPath == some(prevPath)

  test "newFilerState without previousPath":
    let state = newFilerState(testDir)
    check state.previousPath.isNone

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
    state.topLine = 2
    state.moveToFirst()
    check state.selectedIndex == 0
    check state.topLine == 0

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

  test "hidden files are not shown by default":
    let state = newFilerState(testDir)
    check state.showHidden == false
    # Should have ".." and "visible.txt" only
    check state.entries.len == 2
    var hasHidden = false
    for entry in state.entries:
      if entry.name == ".hidden":
        hasHidden = true
    check hasHidden == false

  test "toggleHidden shows hidden files":
    let state = newFilerState(testDir)
    state.toggleHidden()
    check state.showHidden == true
    # Should have "..", ".hidden", and "visible.txt"
    check state.entries.len == 3
    var hasHidden = false
    for entry in state.entries:
      if entry.name == ".hidden":
        hasHidden = true
    check hasHidden == true

  test "toggleHidden can hide again":
    let state = newFilerState(testDir)
    state.toggleHidden()
    state.toggleHidden()
    check state.showHidden == false
    check state.entries.len == 2

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

  test "visibleEntries returns correct slice":
    let state = newFilerState(testDir)
    state.topLine = 5
    let visible = state.visibleEntries(10)
    check visible.len == 10
    check visible[0].name == state.entries[5].name

  test "visibleEntries handles end of list":
    let state = newFilerState(testDir)
    state.topLine = 15
    let visible = state.visibleEntries(10)
    check visible.len == state.entries.len - 15

  test "ensureSelectedVisible scrolls down":
    let state = newFilerState(testDir)
    state.topLine = 0
    state.selectedIndex = 15
    state.ensureSelectedVisible(10, 3)
    check state.topLine > 0

  test "ensureSelectedVisible scrolls up":
    let state = newFilerState(testDir)
    state.topLine = 10
    state.selectedIndex = 5
    state.ensureSelectedVisible(10, 3)
    check state.topLine <= 5

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

  test "visibleEntries returns empty when topLine is beyond entries":
    let state = newFilerState(testDir)
    state.topLine = 100 # Beyond entries
    let visible = state.visibleEntries(10)
    check visible.len == 0

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

suite "Filer - Tilde expansion":
  test "newFilerState expands tilde":
    let state = newFilerState("~")
    check state.currentPath == expandTilde("~")
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
