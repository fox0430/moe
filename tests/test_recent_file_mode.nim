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

import std/[unittest, os, options]
import pkg/results
import ../src/moepkg/recent_file_mode

suite "RecentFileMode - State creation":
  test "newRecentFileModeState creates empty state":
    let state = newRecentFileModeState()
    check state.files.len == 0
    check state.selectedIndex == 0
    check state.topLine == 0

  test "len returns 0 for empty state":
    let state = newRecentFileModeState()
    check state.len == 0

  test "isEmpty returns true for empty state":
    let state = newRecentFileModeState()
    check state.isEmpty == true

  test "isEmpty returns false when files exist":
    let state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/file.txt")
    check state.isEmpty == false

  test "len returns correct count":
    let state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/file1.txt")
    state.files.add RecentFileEntry(path: "/file2.txt")
    check state.len == 2

  test "getRecentUsedXbelPath returns correct path":
    let path = getRecentUsedXbelPath()
    check path == getHomeDir() / ".local/share/recently-used.xbel"

suite "RecentFileMode - XBEL parsing":
  setup:
    let testDir = getTempDir() / "moe_recentfile_test"
    createDir(testDir)

  teardown:
    removeDir(testDir)

  test "getRecentUsedFiles returns empty seq for non-existent file":
    let result = getRecentUsedFiles("/non/existent/file.xbel")
    check result.isOk
    check result.get.len == 0

  test "getRecentUsedFiles parses valid xbel file":
    let xbelPath = testDir / "test.xbel"
    let xbelContent = """<?xml version="1.0" encoding="UTF-8"?>
<xbel version="1.0">
  <bookmark href="file:///home/user/file1.txt" added="2024-01-01T00:00:00Z">
    <info><metadata owner="test"/></info>
  </bookmark>
  <bookmark href="file:///home/user/file2.nim" added="2024-01-02T00:00:00Z">
    <info><metadata owner="test"/></info>
  </bookmark>
</xbel>"""
    writeFile(xbelPath, xbelContent)

    let result = getRecentUsedFiles(xbelPath)
    check result.isOk
    let files = result.get
    check files.len == 2
    check files[0] == "/home/user/file1.txt"
    check files[1] == "/home/user/file2.nim"

  test "getRecentUsedFiles decodes URL-encoded paths":
    let xbelPath = testDir / "test_encoded.xbel"
    let xbelContent = """<?xml version="1.0" encoding="UTF-8"?>
<xbel version="1.0">
  <bookmark href="file:///home/user/My%20Documents/file%20with%20spaces.txt" added="2024-01-01T00:00:00Z">
    <info><metadata owner="test"/></info>
  </bookmark>
</xbel>"""
    writeFile(xbelPath, xbelContent)

    let result = getRecentUsedFiles(xbelPath)
    check result.isOk
    let files = result.get
    check files.len == 1
    check files[0] == "/home/user/My Documents/file with spaces.txt"

  test "getRecentUsedFiles returns empty seq for xbel without bookmarks":
    let xbelPath = testDir / "empty.xbel"
    let xbelContent = """<?xml version="1.0" encoding="UTF-8"?>
<xbel version="1.0">
</xbel>"""
    writeFile(xbelPath, xbelContent)

    let result = getRecentUsedFiles(xbelPath)
    check result.isOk
    check result.get.len == 0

  test "getRecentUsedFiles handles malformed xbel with missing end quote":
    let xbelPath = testDir / "malformed.xbel"
    let xbelContent = """<?xml version="1.0" encoding="UTF-8"?>
<xbel version="1.0">
  <bookmark href="file:///home/user/file1.txt" added="2024-01-01T00:00:00Z">
  </bookmark>
  <bookmark href="file:///home/user/incomplete_no_end_quote
</xbel>"""
    writeFile(xbelPath, xbelContent)

    let result = getRecentUsedFiles(xbelPath)
    check result.isOk
    let files = result.get
    check files.len == 1
    check files[0] == "/home/user/file1.txt"

  test "getRecentUsedFiles handles xbel with non-file URIs":
    let xbelPath = testDir / "mixed.xbel"
    let xbelContent = """<?xml version="1.0" encoding="UTF-8"?>
<xbel version="1.0">
  <bookmark href="https://example.com" added="2024-01-01T00:00:00Z">
  </bookmark>
  <bookmark href="file:///home/user/file.txt" added="2024-01-02T00:00:00Z">
  </bookmark>
</xbel>"""
    writeFile(xbelPath, xbelContent)

    let result = getRecentUsedFiles(xbelPath)
    check result.isOk
    let files = result.get
    check files.len == 1
    check files[0] == "/home/user/file.txt"

suite "RecentFileMode - Selection":
  test "getSelectedItem returns none for empty state":
    let state = newRecentFileModeState()
    check state.getSelectedItem.isNone

  test "getSelectedItem returns selected file path":
    let state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/path/to/file1.txt")
    state.files.add RecentFileEntry(path: "/path/to/file2.txt")
    state.selectedIndex = 1

    let selected = state.getSelectedItem
    check selected.isSome
    check selected.get == "/path/to/file2.txt"

  test "getSelectedItem returns none for out of range index":
    let state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/path/to/file.txt")
    state.selectedIndex = 5

    check state.getSelectedItem.isNone

suite "RecentFileMode - Navigation":
  test "moveUp decreases selectedIndex":
    let state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/file1.txt")
    state.files.add RecentFileEntry(path: "/file2.txt")
    state.files.add RecentFileEntry(path: "/file3.txt")
    state.selectedIndex = 2

    state.moveUp()
    check state.selectedIndex == 1

    state.moveUp()
    check state.selectedIndex == 0

  test "moveUp does nothing at index 0":
    let state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/file1.txt")
    state.files.add RecentFileEntry(path: "/file2.txt")
    state.selectedIndex = 0

    state.moveUp()
    check state.selectedIndex == 0

  test "moveUp does nothing on empty state":
    let state = newRecentFileModeState()
    state.moveUp()
    check state.selectedIndex == 0

  test "moveDown increases selectedIndex":
    let state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/file1.txt")
    state.files.add RecentFileEntry(path: "/file2.txt")
    state.files.add RecentFileEntry(path: "/file3.txt")
    state.selectedIndex = 0

    state.moveDown()
    check state.selectedIndex == 1

    state.moveDown()
    check state.selectedIndex == 2

  test "moveDown does nothing at last index":
    let state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/file1.txt")
    state.files.add RecentFileEntry(path: "/file2.txt")
    state.selectedIndex = 1

    state.moveDown()
    check state.selectedIndex == 1

  test "moveDown does nothing on empty state":
    let state = newRecentFileModeState()
    state.moveDown()
    check state.selectedIndex == 0

  test "moveToFirst sets selectedIndex to 0":
    let state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/file1.txt")
    state.files.add RecentFileEntry(path: "/file2.txt")
    state.files.add RecentFileEntry(path: "/file3.txt")
    state.selectedIndex = 2

    state.moveToFirst()
    check state.selectedIndex == 0

  test "moveToLast sets selectedIndex to last":
    let state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/file1.txt")
    state.files.add RecentFileEntry(path: "/file2.txt")
    state.files.add RecentFileEntry(path: "/file3.txt")
    state.selectedIndex = 0

    state.moveToLast()
    check state.selectedIndex == 2

  test "moveToLast does nothing on empty state":
    let state = newRecentFileModeState()
    state.moveToLast()
    check state.selectedIndex == 0

suite "RecentFileMode - Viewport":
  test "ensureSelectedVisible scrolls up when selection above viewport":
    let state = newRecentFileModeState()
    for i in 0 ..< 10:
      state.files.add RecentFileEntry(path: "/file" & $i & ".txt")
    state.topLine = 5
    state.selectedIndex = 2

    state.ensureSelectedVisible(5)
    check state.topLine == 2

  test "ensureSelectedVisible scrolls down when selection below viewport":
    let state = newRecentFileModeState()
    for i in 0 ..< 10:
      state.files.add RecentFileEntry(path: "/file" & $i & ".txt")
    state.topLine = 0
    state.selectedIndex = 7

    state.ensureSelectedVisible(5)
    check state.topLine == 3

  test "ensureSelectedVisible does not change when selection is visible":
    let state = newRecentFileModeState()
    for i in 0 ..< 10:
      state.files.add RecentFileEntry(path: "/file" & $i & ".txt")
    state.topLine = 2
    state.selectedIndex = 4

    state.ensureSelectedVisible(5)
    check state.topLine == 2

  test "getVisibleFiles returns correct slice":
    let state = newRecentFileModeState()
    for i in 0 ..< 10:
      state.files.add RecentFileEntry(path: "/file" & $i & ".txt")
    state.topLine = 3

    let visible = state.getVisibleFiles(4)
    check visible.len == 4
    check visible[0].path == "/file3.txt"
    check visible[3].path == "/file6.txt"

  test "getVisibleFiles handles viewport larger than remaining files":
    let state = newRecentFileModeState()
    for i in 0 ..< 5:
      state.files.add RecentFileEntry(path: "/file" & $i & ".txt")
    state.topLine = 3

    let visible = state.getVisibleFiles(10)
    check visible.len == 2
    check visible[0].path == "/file3.txt"
    check visible[1].path == "/file4.txt"

  test "getVisibleFiles returns empty for empty state":
    let state = newRecentFileModeState()
    let visible = state.getVisibleFiles(5)
    check visible.len == 0

  test "getVisibleFiles returns empty when topLine beyond files":
    let state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/file.txt")
    state.topLine = 5

    let visible = state.getVisibleFiles(5)
    check visible.len == 0

suite "RecentFileMode - File existence":
  setup:
    let testDir = getTempDir() / "moe_recentfile_exist_test"
    createDir(testDir)

  teardown:
    removeDir(testDir)

  test "selectedFileExists returns false for empty state":
    let state = newRecentFileModeState()
    check state.selectedFileExists == false

  test "selectedFileExists returns true when file exists":
    let testFile = testDir / "existing.txt"
    writeFile(testFile, "test content")

    let state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: testFile)

    check state.selectedFileExists == true

  test "selectedFileExists returns false when file does not exist":
    let state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: testDir / "nonexistent.txt")

    check state.selectedFileExists == false

suite "RecentFileMode - loadRecentFiles":
  test "loadRecentFiles handles system xbel file":
    let state = newRecentFileModeState()
    let result = state.loadRecentFiles()

    check result.isOk
    check state.selectedIndex == 0
    check state.topLine == 0

  test "loadRecentFiles resets state on success":
    let state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/old/file.txt")
    state.selectedIndex = 5
    state.topLine = 3

    let result = state.loadRecentFiles()

    let xbelPath = getRecentUsedXbelPath()
    if fileExists(xbelPath):
      check result.isOk
      check state.selectedIndex == 0
      check state.topLine == 0
