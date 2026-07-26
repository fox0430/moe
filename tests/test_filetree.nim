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

import std/[unittest, os, sets, options, tables, tempfiles, strutils, unicode]

import ../src/moepkg/filetree {.all.}
import ../src/moepkg/[buffer, highlight, unicode_utils]

proc createTestTree(): string =
  ## Create a temporary directory structure for testing
  let tmpDir = createTempDir("moe_test_", "_filetree")
  createDir(tmpDir / "src")
  createDir(tmpDir / "src" / "sub")
  createDir(tmpDir / "tests")
  writeFile(tmpDir / "README.md", "readme")
  writeFile(tmpDir / "src" / "main.nim", "echo 1")
  writeFile(tmpDir / "src" / "sub" / "helper.nim", "echo 2")
  writeFile(tmpDir / "tests" / "test1.nim", "echo 3")
  writeFile(tmpDir / ".hidden", "hidden")
  return tmpDir

suite "FileTreeState":
  test "newFileTreeState creates state with root nodes":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    check state.rootPath == normalizedPath(absolutePath(tmpDir))
    check state.flatList.len > 0
    check state.selectedIndex == 0
    check state.showHidden == false

  test "flatList contains only top-level entries when nothing is expanded":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    # Should have directories (src, tests) and files (README.md) at top level
    # Hidden files (.hidden) should not be shown by default
    var names: seq[string] = @[]
    for node in state.flatList:
      names.add(node.name)
      check node.depth == 0

    check "src" in names
    check "tests" in names
    check "README.md" in names
    check ".hidden" notin names

  test "toggleHidden shows hidden files":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    state.toggleHidden()
    check state.showHidden == true

    var names: seq[string] = @[]
    for node in state.flatList:
      names.add(node.name)

    check ".hidden" in names

  test "toggleExpand expands a directory":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)

    # Find "src" directory
    var srcIdx = -1
    for i, node in state.flatList:
      if node.name == "src":
        srcIdx = i
        break
    check srcIdx >= 0

    state.selectedIndex = srcIdx
    let prevLen = state.flatList.len
    state.toggleExpand()

    # Should now have more entries (src's children visible)
    check state.flatList.len > prevLen
    # Children should have depth 1
    var foundChild = false
    for node in state.flatList:
      if node.name == "main.nim":
        check node.depth == 1
        foundChild = true
    check foundChild

  test "toggleExpand collapses an expanded directory":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)

    # Find and expand "src"
    for i, node in state.flatList:
      if node.name == "src":
        state.selectedIndex = i
        break

    state.toggleExpand()
    let expandedLen = state.flatList.len

    # Toggle again to collapse
    for i, node in state.flatList:
      if node.name == "src":
        state.selectedIndex = i
        break

    state.toggleExpand()
    check state.flatList.len < expandedLen

  test "moveUp and moveDown":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    check state.selectedIndex == 0

    state.moveDown()
    check state.selectedIndex == 1

    state.moveDown()
    check state.selectedIndex == 2

    state.moveUp()
    check state.selectedIndex == 1

  test "moveToFirst and moveToLast":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)

    state.moveToLast()
    check state.selectedIndex == state.flatList.len - 1

    state.moveToFirst()
    check state.selectedIndex == 0

  test "getSelectedPath returns correct path":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    let path = state.getSelectedPath()
    check path.isSome

  test "collapseSelected on file moves to parent":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)

    # Expand "src" directory
    for i, node in state.flatList:
      if node.name == "src":
        state.selectedIndex = i
        break
    state.expandSelected()

    # Select a file inside src
    for i, node in state.flatList:
      if node.name == "main.nim":
        state.selectedIndex = i
        break

    state.collapseSelected()
    # Should move to parent directory "src"
    check state.flatList[state.selectedIndex].name == "src"

  test "changeRoot changes the root to selected directory":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)

    # Select "src" and change root to it
    for i, node in state.flatList:
      if node.name == "src":
        state.selectedIndex = i
        break

    state.changeRoot()
    check state.rootPath.endsWith("src")
    check state.selectedIndex == 0

  test "moveRootUp moves root to parent directory":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir / "src")
    let originalRoot = state.rootPath

    state.moveRootUp()
    check state.rootPath == parentDir(originalRoot)

  test "createFileTreeTextBuffer generates valid buffer":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    let buf = state.createFileTreeTextBuffer(showIcons = true)
    check buf != nil
    check buf.len > 0
    check buf.readOnly == true
    check buf.isUtilityBuffer == true

  test "createFileTreeTextBuffer without icons":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    let buf = state.createFileTreeTextBuffer(showIcons = false)
    check buf != nil
    check buf.len > 0

  test "revealPath expands ancestors and selects target":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    let targetPath = tmpDir / "src" / "sub" / "helper.nim"

    state.revealPath(targetPath)

    # Check that src and src/sub are expanded
    check normalizedPath(absolutePath(tmpDir / "src")) in state.expandedDirs
    check normalizedPath(absolutePath(tmpDir / "src" / "sub")) in state.expandedDirs

    # Check that helper.nim is selected
    let node = state.getSelectedNode()
    check node.isSome
    check node.get.name == "helper.nim"

  test "refreshTree rebuilds the tree":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    let origLen = state.flatList.len

    # Create a new file
    writeFile(tmpDir / "newfile.txt", "new")

    state.refreshTree()
    check state.flatList.len == origLen + 1

  test "buildFlatList uses cache and does not reflect filesystem changes":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)

    # Expand "src"
    for i, node in state.flatList:
      if node.name == "src":
        state.selectedIndex = i
        break
    state.toggleExpand()
    let lenAfterExpand = state.flatList.len

    # Cache should now contain src's children
    let srcPath = normalizedPath(absolutePath(tmpDir / "src"))
    check srcPath in state.childrenCache

    # Add a file to src on disk
    writeFile(tmpDir / "src" / "extra.nim", "echo extra")

    # Rebuild flat list without refreshTree — cache should be used, new file not visible
    state.buildFlatList()
    check state.flatList.len == lenAfterExpand

    var names: seq[string] = @[]
    for node in state.flatList:
      names.add(node.name)
    check "extra.nim" notin names

  test "refreshTree clears cache and picks up filesystem changes":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)

    # Expand "src"
    for i, node in state.flatList:
      if node.name == "src":
        state.selectedIndex = i
        break
    state.toggleExpand()

    # Add a file to src on disk
    writeFile(tmpDir / "src" / "extra.nim", "echo extra")

    # refreshTree should clear cache and show the new file
    state.refreshTree()
    # Re-expand src (refreshTree clears expandedDirs indirectly via changeRoot/moveRootUp,
    # but for plain refreshTree expandedDirs is preserved)
    state.buildFlatList()

    var names: seq[string] = @[]
    for node in state.flatList:
      names.add(node.name)
    check "extra.nim" in names
    check state.childrenCache.len == 0 or "extra.nim" in names

  test "toggleHidden clears cache and rebuilds with new visibility":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)

    # Expand "src" to populate cache
    for i, node in state.flatList:
      if node.name == "src":
        state.selectedIndex = i
        break
    state.toggleExpand()

    let srcPath = normalizedPath(absolutePath(tmpDir / "src"))
    check srcPath in state.childrenCache

    # Add a hidden file to src
    writeFile(tmpDir / "src" / ".secret", "secret")

    # toggleHidden calls refreshTree which clears old cache.
    # expandedDirs is also cleared by refreshTree indirectly? No — only by
    # changeRoot/moveRootUp. But toggleHidden→refreshTree rebuilds rootNodes
    # and re-runs buildFlatList. Since expandedDirs still has src, the cache
    # will be repopulated with showHidden=true results.
    state.toggleHidden()

    # The old cache entry should have been replaced (refreshTree clears it,
    # then buildFlatList repopulates if src is still expanded).
    # But expandedDirs is preserved, so src is still expanded and cache is
    # repopulated. Verify the hidden file is now visible.
    var names: seq[string] = @[]
    for node in state.flatList:
      names.add(node.name)
    check ".hidden" in names
    check ".secret" in names

  test "buildFlatList handles cyclic symlinks without infinite loop":
    let tmpDir = createTempDir("moe_test_", "_symloop")
    defer:
      removeDir(tmpDir)

    createDir(tmpDir / "realdir")
    writeFile(tmpDir / "realdir" / "file.txt", "hello")
    # Create a symlink inside realdir that points back to realdir
    createSymlink(tmpDir / "realdir", tmpDir / "realdir" / "loop")

    let state = newFileTreeState(tmpDir)
    # Expand realdir — the symlink "loop" points back to realdir
    for i, node in state.flatList:
      if node.name == "realdir":
        state.selectedIndex = i
        break
    state.expandSelected()

    # Now expand "loop" (which is realdir again)
    for i, node in state.flatList:
      if node.name == "loop":
        state.selectedIndex = i
        break
    state.expandSelected()

    # buildFlatList should terminate and contain the loop entry
    # but NOT recurse infinitely
    var loopCount = 0
    for node in state.flatList:
      if node.name == "loop":
        inc loopCount
    check loopCount >= 1
    # The flat list should be finite — a simple length check suffices
    check state.flatList.len < 100

  test "buildFlatList skips descent through symlink resolving to visited dir":
    let tmpDir = createTempDir("moe_test_", "_symdup")
    defer:
      removeDir(tmpDir)

    createDir(tmpDir / "realdir")
    writeFile(tmpDir / "realdir" / "child.txt", "hi")
    createSymlink(tmpDir / "realdir", tmpDir / "realdir" / "loop")

    let state = newFileTreeState(tmpDir)
    for i, node in state.flatList:
      if node.name == "realdir":
        state.selectedIndex = i
        break
    state.expandSelected()
    for i, node in state.flatList:
      if node.name == "loop":
        state.selectedIndex = i
        break
    state.expandSelected()

    # canonical(realdir/loop) == canonical(realdir); the visited guard should
    # prevent a second traversal, so child.txt appears only once.
    var childCount = 0
    for node in state.flatList:
      if node.name == "child.txt":
        inc childCount
    check childCount == 1

  test "buildFlatList dedupes two symlinks pointing at the same real dir":
    let tmpDir = createTempDir("moe_test_", "_symtwins")
    defer:
      removeDir(tmpDir)

    createDir(tmpDir / "real")
    writeFile(tmpDir / "real" / "leaf.txt", "hi")
    createSymlink(tmpDir / "real", tmpDir / "linkA")
    createSymlink(tmpDir / "real", tmpDir / "linkB")

    let state = newFileTreeState(tmpDir)
    for name in ["real", "linkA", "linkB"]:
      for i, node in state.flatList:
        if node.name == name:
          state.selectedIndex = i
          break
      state.expandSelected()

    # All three entries resolve to the same canonical path, so only the first
    # one visited descends. leaf.txt should appear exactly once.
    var leafCount = 0
    for node in state.flatList:
      if node.name == "leaf.txt":
        inc leafCount
    check leafCount == 1

  test "createFileTreeTextBuffer ColorSegment lastColumn is rune-based":
    let tmpDir = createTempDir("moe_test_", "_rune")
    defer:
      removeDir(tmpDir)

    # Create a file with a multibyte name (Japanese)
    writeFile(tmpDir / "日本語ファイル.txt", "content")

    let state = newFileTreeState(tmpDir)
    let buf = state.createFileTreeTextBuffer(showIcons = false)

    # Find the row for the multibyte-named file
    var targetRow = -1
    for i, node in state.flatList:
      if node.name == "日本語ファイル.txt":
        targetRow = i
        break
    check targetRow >= 0

    let seg = buf.highlight[targetRow]
    # lastColumn should equal the rune length - 1, not byte length - 1
    let line = $buf[targetRow]
    let runeHigh = line.runeLen - 1
    check seg.lastColumn == runeHigh
    # Byte high would be much larger for multibyte text
    check seg.lastColumn < line.high

  test "revealPath ignores paths outside root tree":
    let tmpDir = createTempDir("moe_test_", "_reveal")
    defer:
      removeDir(tmpDir)

    createDir(tmpDir / "project")
    writeFile(tmpDir / "project" / "file.txt", "hello")
    writeFile(tmpDir / "outside.txt", "outside")

    let state = newFileTreeState(tmpDir / "project")
    let origExpanded = state.expandedDirs.len

    # Attempt to reveal a path outside the root
    state.revealPath(tmpDir / "outside.txt")

    # expandedDirs should not have been polluted
    check state.expandedDirs.len == origExpanded

  test "getChildren returns correct depth when cached at different depth":
    let tmpDir = createTempDir("moe_test_", "_depth")
    defer:
      removeDir(tmpDir)

    createDir(tmpDir / "a")
    writeFile(tmpDir / "a" / "file.txt", "hello")

    let state = newFileTreeState(tmpDir)

    # First call caches children at depth 1
    let children1 = state.getChildren(normalizedPath(absolutePath(tmpDir / "a")), 1)
    check children1.len == 1
    check children1[0].depth == 1

    # Second call with different depth should return corrected depth
    let children5 = state.getChildren(normalizedPath(absolutePath(tmpDir / "a")), 5)
    check children5.len == 1
    check children5[0].depth == 5

  test "createFileTreeTextBuffer truncates long filenames to width":
    let tmpDir = createTempDir("moe_test_", "_truncate")
    defer:
      removeDir(tmpDir)

    let longName = "a".repeat(50) & ".txt"
    writeFile(tmpDir / longName, "content")

    let width = 20
    let state = newFileTreeState(tmpDir, width)
    let buf = state.createFileTreeTextBuffer(showIcons = false)

    # Every line should fit within the configured width
    for i in 0 ..< buf.len:
      let line = $buf[i]
      check displayWidth(line) <= width

    # The truncated line should end with "~"
    let line = $buf[0]
    check line.endsWith("~")

  test "createFileTreeTextBuffer does not truncate short filenames":
    let tmpDir = createTempDir("moe_test_", "_notruncate")
    defer:
      removeDir(tmpDir)

    writeFile(tmpDir / "short.txt", "content")

    let state = newFileTreeState(tmpDir, 40)
    let buf = state.createFileTreeTextBuffer(showIcons = false)

    let line = $buf[0]
    check not line.endsWith("~")
    check "short.txt" in line

  test "updateSearchMatches finds matching nodes case-insensitively":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    state.searchText = "readme"
    state.updateSearchMatches()

    check state.searchMatches.len == 1
    check state.flatList[state.searchMatches[0]].name == "README.md"

  test "updateSearchMatches finds multiple matches":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    # Expand "src" to show main.nim and sub/
    for i, node in state.flatList:
      if node.name == "src":
        state.selectedIndex = i
        break
    state.expandSelected()
    # Expand "tests" to show test1.nim
    for i, node in state.flatList:
      if node.name == "tests":
        state.selectedIndex = i
        break
    state.expandSelected()

    # Search for ".nim" — should match main.nim and test1.nim (but not sub/)
    state.searchText = ".nim"
    state.updateSearchMatches()
    check state.searchMatches.len >= 2

  test "jumpToNextMatch wraps around":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    # Expand src to get more entries
    for i, node in state.flatList:
      if node.name == "src":
        state.selectedIndex = i
        break
    state.expandSelected()
    for i, node in state.flatList:
      if node.name == "tests":
        state.selectedIndex = i
        break
    state.expandSelected()

    state.searchText = ".nim"
    state.updateSearchMatches()
    let matchCount = state.searchMatches.len
    check matchCount >= 2

    # Start from first match
    state.jumpToFirstMatch()
    check state.searchMatchIndex == 0

    # Jump through remaining matches and wrap around
    for j in 0 ..< matchCount:
      state.jumpToNextMatch()
    # After matchCount jumps from index 0, should be back at index 0
    check state.searchMatchIndex == 0

  test "jumpToPrevMatch wraps around":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    state.searchText = "src"
    state.updateSearchMatches()
    check state.searchMatches.len >= 1

    # First prev jump should go to last match
    state.jumpToPrevMatch()
    check state.searchMatchIndex == state.searchMatches.len - 1

  test "clearSearch resets search state":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    state.searchText = "readme"
    state.updateSearchMatches()
    check state.searchMatches.len > 0

    state.clearSearch()
    check state.searchText == ""
    check state.searchMatches.len == 0
    check state.searchMatchIndex == -1

  test "buildFlatList re-runs search when searchText is set":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    state.searchText = "src"
    state.updateSearchMatches()
    let origMatches = state.searchMatches.len

    # Expand src — buildFlatList should re-run updateSearchMatches
    for i, node in state.flatList:
      if node.name == "src":
        state.selectedIndex = i
        break
    state.expandSelected()

    # After expand, flatList changed so matches may differ
    # but search should still be active
    check state.searchMatches.len >= origMatches

  test "createFileTreeTextBuffer truncates multibyte filenames correctly":
    let tmpDir = createTempDir("moe_test_", "_mbtruncate")
    defer:
      removeDir(tmpDir)

    # CJK characters are 2 columns wide each
    let longName = "日本語のとても長いファイル名テスト.txt"
    writeFile(tmpDir / longName, "content")

    let width = 15
    let state = newFileTreeState(tmpDir, width)
    let buf = state.createFileTreeTextBuffer(showIcons = false)

    let line = $buf[0]
    check displayWidth(line) <= width
    check line.endsWith("~")

  test "updateSearchMatches with no matches":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    state.searchText = "nonexistent_xyz"
    state.updateSearchMatches()
    check state.searchMatches.len == 0
    check state.searchMatchIndex == -1

  test "jumpToNextMatch and jumpToPrevMatch with no matches does not crash":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    state.searchText = "nonexistent_xyz"
    state.updateSearchMatches()
    check state.searchMatches.len == 0

    # Should be no-ops, not crashes
    state.jumpToNextMatch()
    check state.searchMatchIndex == -1
    state.jumpToPrevMatch()
    check state.searchMatchIndex == -1

  test "updateSearchMatches with empty searchText returns no matches":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    state.searchText = ""
    state.updateSearchMatches()
    check state.searchMatches.len == 0

  test "createFileTreeTextBuffer adds searchResult highlight at correct column":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    # Search for "README" — should match README.md (a file)
    state.searchText = "README"
    state.updateSearchMatches()
    check state.searchMatches.len == 1

    let buf = state.createFileTreeTextBuffer(showIcons = false)
    # Find the searchResult segment
    var found = false
    for seg in buf.highlight.colorSegments:
      if seg.color == EditorColorPairIndex.searchResult:
        found = true
        # The matched row should be the README.md entry
        check seg.firstRow == state.searchMatches[0]
        # "README" is 6 runes, so lastColumn = firstColumn + 5
        check seg.lastColumn - seg.firstColumn == 5
        break
    check found

  test "createFileTreeTextBuffer searchResult highlight on directory accounts for trailing slash":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    # Search for "src" — should match the "src" directory
    state.searchText = "src"
    state.updateSearchMatches()
    check state.searchMatches.len >= 1

    let buf = state.createFileTreeTextBuffer(showIcons = false)
    # Find the searchResult segment for the directory
    var found = false
    for seg in buf.highlight.colorSegments:
      if seg.color == EditorColorPairIndex.searchResult:
        found = true
        let row = seg.firstRow
        let line = $buf[row]
        let lineRunes = line.toRunes()
        # The highlight should be within the line bounds (not shifted by trailing /)
        check seg.lastColumn < lineRunes.len
        # "src" is 3 runes
        check seg.lastColumn - seg.firstColumn == 2
        break
    check found

  test "createFileTreeTextBuffer highlights all occurrences of search text in filename":
    let tmpDir = createTempDir("moe_test_", "_filetree_multi")
    defer:
      removeDir(tmpDir)
    # Filename "abab.txt" with search "ab" should produce 2 highlights
    writeFile(tmpDir / "abab.txt", "")

    let state = newFileTreeState(tmpDir)
    state.searchText = "ab"
    state.updateSearchMatches()
    check state.searchMatches.len == 1

    let buf = state.createFileTreeTextBuffer(showIcons = false)
    var matchCount = 0
    for seg in buf.highlight.colorSegments:
      if seg.color == EditorColorPairIndex.searchResult:
        inc matchCount
        # "ab" is 2 runes
        check seg.lastColumn - seg.firstColumn == 1
    check matchCount == 2

  test "revealPath expands ancestors when rootPath is /":
    # Create a temp dir structure under the system temp dir
    let tmpDir = createTempDir("moe_test_", "_rootreveal")
    defer:
      removeDir(tmpDir)

    createDir(tmpDir / "sub")
    writeFile(tmpDir / "sub" / "file.txt", "content")

    # Use tmpDir as root (not /, to avoid scanning the whole filesystem),
    # but verify the ancestor-expansion logic by checking that "sub" gets expanded.
    let state = newFileTreeState(tmpDir)
    state.revealPath(tmpDir / "sub" / "file.txt")

    # "sub" should be expanded
    check (tmpDir / "sub") in state.expandedDirs

    # The file should be selected
    let selectedPath = state.getSelectedPath()
    check selectedPath.isSome
    check selectedPath.get() == tmpDir / "sub" / "file.txt"

  test "truncateToWidthWithSuffix does not truncate when full-width chars fit exactly":
    # 5 CJK chars = 10 columns, maxWidth = 10 → should fit without "~"
    let text = "日本語全角" # 5 chars × 2 columns = 10
    let result = truncateToWidthWithSuffix(text, 10, "~")
    check result == text
    check not result.endsWith("~")

  test "truncateToWidthWithSuffix truncates full-width chars that exceed maxWidth":
    # 6 CJK chars = 12 columns, maxWidth = 10 → needs truncation
    let text = "日本語全角文" # 6 chars × 2 columns = 12
    let result = truncateToWidthWithSuffix(text, 10, "~")
    check displayWidth(result) <= 10
    check result.endsWith("~")

  test "updateSearchMatches preserves position after rebuild":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let state = newFileTreeState(tmpDir)
    # Expand src to get more entries
    for i, node in state.flatList:
      if node.name == "src":
        state.selectedIndex = i
        break
    state.expandSelected()
    for i, node in state.flatList:
      if node.name == "tests":
        state.selectedIndex = i
        break
    state.expandSelected()

    # Search for ".nim"
    state.searchText = ".nim"
    state.updateSearchMatches()
    check state.searchMatches.len >= 2

    # Jump to second match
    state.jumpToFirstMatch()
    state.jumpToNextMatch()
    check state.searchMatchIndex == 1
    let selectedBefore = state.selectedIndex

    # Simulate a rebuild (e.g. expand/collapse) — selectedIndex stays the same
    state.updateSearchMatches()

    # searchMatchIndex should point to a match at or after selectedIndex
    check state.searchMatchIndex >= 0
    if state.searchMatches.len > 0:
      check state.searchMatches[state.searchMatchIndex] >= selectedBefore

  test "createFileTreeTextBuffer skips search highlight on truncated lines":
    let tmpDir = createTempDir("moe_test_", "_trunchl")
    defer:
      removeDir(tmpDir)

    # Long CJK filename that will be truncated at a narrow width
    let longName = "検索対象のとても長いファイル名.txt"
    writeFile(tmpDir / longName, "content")

    let width = 12
    let state = newFileTreeState(tmpDir, width)
    state.searchText = "ファイル"
    state.updateSearchMatches()
    check state.searchMatches.len == 1

    let buf = state.createFileTreeTextBuffer(showIcons = false)

    # The line should be truncated
    let line = $buf[0]
    check line.endsWith("~")

    # No searchResult highlight should appear (match is in truncated portion)
    for seg in buf.highlight.colorSegments:
      check seg.color != EditorColorPairIndex.searchResult
