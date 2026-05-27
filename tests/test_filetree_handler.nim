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

import std/[unittest, os, tempfiles]

import ../src/moepkg/[filetree, key_bindings]
import ../src/moepkg/command_handlers/filetree_handler

proc createTestTree(): string =
  let tmpDir = createTempDir("moe_test_", "_fthandler")
  createDir(tmpDir / "src")
  writeFile(tmpDir / "README.md", "readme")
  writeFile(tmpDir / "src" / "main.nim", "echo 1")
  return tmpDir

proc makeKeyCombo(ch: string): KeyCombo =
  KeyCombo(isSpecial: false, char: ch, modifiers: {})

proc makeCtrlKeyCombo(ch: string): KeyCombo =
  KeyCombo(isSpecial: false, char: ch, modifiers: {kmCtrl})

proc makeSpecialKeyCombo(special: SpecialKey): KeyCombo =
  KeyCombo(isSpecial: true, special: special, fnNum: 0, modifiers: {})

suite "SubStateHandler":
  test "j moves down":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)
    let startIdx = state.selectedIndex

    let result = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("j"))
    check result.kind == ftrHandled
    check state.selectedIndex == startIdx + 1

  test "k moves up":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)
    state.moveDown() # Move to index 1 first

    let result = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("k"))
    check result.kind == ftrHandled
    check state.selectedIndex == 0

  test "o on directory toggles expand":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    # Select "src" directory (should be first entry since dirs come first)
    state.selectedIndex = 0
    let prevLen = state.flatList.len

    let result = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("o"))
    check result.kind == ftrHandled
    # If it was a directory, it should have expanded
    if state.flatList[0].isDirectory:
      check state.flatList.len > prevLen

  test "o on file returns ftrOpenFile":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    # Find a file entry
    for i, node in state.flatList:
      if node.isFile:
        state.selectedIndex = i
        break

    let result = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("o"))
    check result.kind == ftrOpenFile
    check result.filePath.len > 0

  test "l on directory expands but does not collapse":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    # Select a directory
    state.selectedIndex = 0
    check state.flatList[0].isDirectory

    # First l: expand
    let r1 = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("l"))
    check r1.kind == ftrHandled
    let expandedLen = state.flatList.len
    check expandedLen > 1

    # Second l on same directory: should NOT collapse (still expanded)
    state.selectedIndex = 0
    let r2 = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("l"))
    check r2.kind == ftrHandled
    check state.flatList.len == expandedLen

  test "l on file returns ftrOpenFile":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    # Find a file entry
    for i, node in state.flatList:
      if node.isFile:
        state.selectedIndex = i
        break

    let result = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("l"))
    check result.kind == ftrOpenFile
    check result.filePath.len > 0

  test ": returns ftrEnterCommand":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    let result = handler.handleFileTreeModeKey(state, 20, makeKeyCombo(":"))
    check result.kind == ftrEnterCommand

  test "G moves to last":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    let result = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("G"))
    check result.kind == ftrHandled
    check state.selectedIndex == state.flatList.len - 1

  test "gg moves to first":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)
    state.moveToLast()

    # First g
    let r1 = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("g"))
    check r1.kind == ftrHandled

    # Second g
    let r2 = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("g"))
    check r2.kind == ftrHandled
    check state.selectedIndex == 0

  test ". toggles hidden files":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    # Add a hidden file
    writeFile(tmpDir / ".hidden", "hidden")

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    check state.showHidden == false

    let result = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("."))
    check result.kind == ftrHandled
    check state.showHidden == true

  test "Enter on directory expands":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    # Select "src" directory
    state.selectedIndex = 0
    if state.flatList[0].isDirectory:
      let prevLen = state.flatList.len
      let result =
        handler.handleFileTreeModeKey(state, 20, makeSpecialKeyCombo(skEnter))
      check result.kind == ftrHandled
      check state.flatList.len > prevLen

  test "x on expanded directory collapses it":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    # Expand src first
    state.selectedIndex = 0
    if state.flatList[0].isDirectory:
      state.expandSelected()
      let expandedLen = state.flatList.len

      # Now collapse with x
      state.selectedIndex = 0
      let result = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("x"))
      check result.kind == ftrHandled
      check state.flatList.len < expandedLen

  test "/ starts search mode":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    let result = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("/"))
    check result.kind == ftrHandled
    check result.statusMessage == "/"
    check handler.isSearching == true

  test "typing characters during search does incremental matching":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    # Start search
    discard handler.handleFileTreeModeKey(state, 20, makeKeyCombo("/"))

    # Type "R"
    let r1 = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("R"))
    check r1.kind == ftrHandled
    check r1.statusMessage == "/R"
    check state.searchText == "R"
    check state.searchMatches.len >= 1 # README.md should match

    # Type "E"
    let r2 = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("E"))
    check r2.kind == ftrHandled
    check r2.statusMessage == "/RE"
    check state.searchText == "RE"

  test "Enter confirms search":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    # Start search and type
    discard handler.handleFileTreeModeKey(state, 20, makeKeyCombo("/"))
    discard handler.handleFileTreeModeKey(state, 20, makeKeyCombo("s"))
    discard handler.handleFileTreeModeKey(state, 20, makeKeyCombo("r"))
    discard handler.handleFileTreeModeKey(state, 20, makeKeyCombo("c"))

    let result = handler.handleFileTreeModeKey(state, 20, makeSpecialKeyCombo(skEnter))
    check result.kind == ftrHandled
    check handler.isSearching == false
    check state.searchText == "src" # Search text preserved
    check result.statusMessage == "/src"

  test "Escape cancels search":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    # Start search and type
    discard handler.handleFileTreeModeKey(state, 20, makeKeyCombo("/"))
    discard handler.handleFileTreeModeKey(state, 20, makeKeyCombo("x"))

    let result = handler.handleFileTreeModeKey(state, 20, makeSpecialKeyCombo(skEscape))
    check result.kind == ftrHandled
    check handler.isSearching == false
    check state.searchText == "" # Search cleared
    check state.searchMatches.len == 0

  test "n jumps to next match":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    # Set up a search with matches
    state.searchText = "s"
    state.updateSearchMatches()
    # "src" should match
    check state.searchMatches.len >= 1

    let result = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("n"))
    check result.kind == ftrHandled
    check state.searchMatchIndex >= 0

  test "N jumps to previous match":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    # Set up a search with matches
    state.searchText = "s"
    state.updateSearchMatches()
    check state.searchMatches.len >= 1

    let result = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("N"))
    check result.kind == ftrHandled
    check state.searchMatchIndex >= 0

  test "Backspace during search removes last character":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    # Start search and type "ab"
    discard handler.handleFileTreeModeKey(state, 20, makeKeyCombo("/"))
    discard handler.handleFileTreeModeKey(state, 20, makeKeyCombo("a"))
    discard handler.handleFileTreeModeKey(state, 20, makeKeyCombo("b"))
    check handler.searchBuffer == "ab"

    # Backspace
    let result =
      handler.handleFileTreeModeKey(state, 20, makeSpecialKeyCombo(skBackspace))
    check result.kind == ftrHandled
    check handler.searchBuffer == "a"
    check state.searchText == "a"
    check result.statusMessage == "/a"

  test "Backspace on empty search buffer does not crash":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    # Start search (buffer is empty)
    discard handler.handleFileTreeModeKey(state, 20, makeKeyCombo("/"))
    check handler.searchBuffer == ""

    # Backspace on empty buffer
    let result =
      handler.handleFileTreeModeKey(state, 20, makeSpecialKeyCombo(skBackspace))
    check result.kind == ftrHandled
    check handler.searchBuffer == ""
    check result.statusMessage == "/"

  test "Enter confirms search and clears searchBuffer":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    discard handler.handleFileTreeModeKey(state, 20, makeKeyCombo("/"))
    discard handler.handleFileTreeModeKey(state, 20, makeKeyCombo("R"))

    let result = handler.handleFileTreeModeKey(state, 20, makeSpecialKeyCombo(skEnter))
    check result.kind == ftrHandled
    check handler.isSearching == false
    check handler.searchBuffer == ""
    check state.searchText == "R" # searchText preserved in state

  test "g then non-g key cancels gg and processes the key":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    # Press g
    let r1 = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("g"))
    check r1.kind == ftrHandled
    check handler.waitingForG == true

    # Press j instead of g — should cancel gg and move down
    let startIdx = state.selectedIndex
    let r2 = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("j"))
    check r2.kind == ftrHandled
    check handler.waitingForG == false
    check state.selectedIndex == startIdx + 1

  test "Ctrl-w > returns ftrIncreaseWindowWidth":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    discard handler.handleFileTreeModeKey(state, 20, makeCtrlKeyCombo("w"))
    let r = handler.handleFileTreeModeKey(state, 20, makeKeyCombo(">"))
    check r.kind == ftrIncreaseWindowWidth

  test "Ctrl-w < returns ftrDecreaseWindowWidth":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    discard handler.handleFileTreeModeKey(state, 20, makeCtrlKeyCombo("w"))
    let r = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("<"))
    check r.kind == ftrDecreaseWindowWidth

  test "Ctrl-w w returns ftrNextWindow":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    discard handler.handleFileTreeModeKey(state, 20, makeCtrlKeyCombo("w"))
    let r = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("w"))
    check r.kind == ftrNextWindow

  test "Ctrl-w p returns ftrPrevWindow":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    discard handler.handleFileTreeModeKey(state, 20, makeCtrlKeyCombo("w"))
    let r = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("p"))
    check r.kind == ftrPrevWindow

  test "Ctrl-w with unknown key returns ftrUnhandled":
    let tmpDir = createTestTree()
    defer:
      removeDir(tmpDir)

    let handler = newSubStateHandler()
    let state = newFileTreeState(tmpDir)

    discard handler.handleFileTreeModeKey(state, 20, makeCtrlKeyCombo("w"))
    let r = handler.handleFileTreeModeKey(state, 20, makeKeyCombo("z"))
    check r.kind == ftrUnhandled
    check handler.waitingForCtrlW == false
