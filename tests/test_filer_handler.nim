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

import std/[unittest, os, strutils]
import ../src/moepkg/[filer, key_bindings]
import ../src/moepkg/command_handlers/filer_handler

suite "FilerHandler - Handler creation":
  test "newFilerHandler creates handler with waitingForG false":
    let handler = newFilerHandler()
    check handler.waitingForG == false

suite "FilerHandler - Escape key":
  setup:
    let testDir = getTempDir() / "moe_filer_handler_test"
    createDir(testDir)
    writeFile(testDir / "file.txt", "content")

  teardown:
    removeDir(testDir)

  test "Escape key returns frHandled":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    let key = toSpecialKeyCombo(skEscape)
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled

suite "FilerHandler - Navigation keys":
  setup:
    let testDir = getTempDir() / "moe_filer_handler_test"
    createDir(testDir)
    writeFile(testDir / "file1.txt", "")
    writeFile(testDir / "file2.txt", "")
    writeFile(testDir / "file3.txt", "")

  teardown:
    removeDir(testDir)

  test "j key moves down":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    let initialIndex = state.selectedIndex
    let key = toKeyCombo('j')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled
    check state.selectedIndex == initialIndex + 1

  test "k key moves up":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    state.selectedIndex = 2
    let key = toKeyCombo('k')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled
    check state.selectedIndex == 1

  test "Down arrow moves down":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    let initialIndex = state.selectedIndex
    let key = toSpecialKeyCombo(skDown)
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled
    check state.selectedIndex == initialIndex + 1

  test "Up arrow moves up":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    state.selectedIndex = 2
    let key = toSpecialKeyCombo(skUp)
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled
    check state.selectedIndex == 1

  test "G moves to last entry":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    let key = toKeyCombo('G')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled
    check state.selectedIndex == state.entries.len - 1

  test "gg moves to first entry":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    state.selectedIndex = 3

    # First 'g'
    let key1 = toKeyCombo('g')
    let result1 = handler.handleFilerModeKey(state, 20, key1)
    check result1.kind == frHandled
    check handler.waitingForG == true

    # Second 'g'
    let key2 = toKeyCombo('g')
    let result2 = handler.handleFilerModeKey(state, 20, key2)
    check result2.kind == frHandled
    check handler.waitingForG == false
    check state.selectedIndex == 0

  test "g followed by non-g key cancels gg sequence":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    state.selectedIndex = 0

    # First 'g'
    let key1 = toKeyCombo('g')
    discard handler.handleFilerModeKey(state, 20, key1)
    check handler.waitingForG == true

    # Press 'j' instead of 'g' - should move down
    let key2 = toKeyCombo('j')
    let result = handler.handleFilerModeKey(state, 20, key2)
    check handler.waitingForG == false
    check result.kind == frHandled
    check state.selectedIndex == 1

suite "FilerHandler - Page navigation":
  setup:
    let testDir = getTempDir() / "moe_filer_handler_test"
    createDir(testDir)
    for i in 0 ..< 30:
      writeFile(testDir / ("file" & $i & ".txt"), "")

  teardown:
    removeDir(testDir)

  test "Ctrl+d moves half page down":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    state.selectedIndex = 0
    var key = toKeyCombo('d', ctrl = true)
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled
    check state.selectedIndex > 0

  test "Ctrl+u moves half page up":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    state.selectedIndex = 15
    var key = toKeyCombo('u', ctrl = true)
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled
    check state.selectedIndex < 15

suite "FilerHandler - Enter and l key (file/directory open)":
  setup:
    let testDir = getTempDir() / "moe_filer_handler_test"
    createDir(testDir)
    createDir(testDir / "subdir")
    writeFile(testDir / "file.txt", "content")

  teardown:
    removeDir(testDir)

  test "Enter on directory returns frOpenDirectory":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find subdir
    for i, entry in state.entries:
      if entry.name == "subdir":
        state.selectedIndex = i
        break
    let key = toSpecialKeyCombo(skEnter)
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frOpenDirectory
    check result.dirPath.endsWith("subdir")

  test "Enter on file returns frOpenFile":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find file.txt
    for i, entry in state.entries:
      if entry.name == "file.txt":
        state.selectedIndex = i
        break
    let key = toSpecialKeyCombo(skEnter)
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frOpenFile
    check result.filePath.endsWith("file.txt")

  test "l on directory returns frOpenDirectory":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find subdir
    for i, entry in state.entries:
      if entry.name == "subdir":
        state.selectedIndex = i
        break
    let key = toKeyCombo('l')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frOpenDirectory
    check result.dirPath.endsWith("subdir")

  test "l on file returns frOpenFile":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find file.txt
    for i, entry in state.entries:
      if entry.name == "file.txt":
        state.selectedIndex = i
        break
    let key = toKeyCombo('l')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frOpenFile
    check result.filePath.endsWith("file.txt")

  test "Enter on .. returns frOpenDirectory with parent path":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    state.selectedIndex = 0 # ".."
    let key = toSpecialKeyCombo(skEnter)
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frOpenDirectory
    check result.dirPath == parentDir(absolutePath(testDir))

suite "FilerHandler - Split open (v and h keys)":
  setup:
    let testDir = getTempDir() / "moe_filer_handler_test"
    createDir(testDir)
    createDir(testDir / "subdir")
    writeFile(testDir / "file.txt", "content")

  teardown:
    removeDir(testDir)

  test "v on file returns frOpenFileVSplit":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find file.txt
    for i, entry in state.entries:
      if entry.name == "file.txt":
        state.selectedIndex = i
        break
    let key = toKeyCombo('v')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frOpenFileVSplit
    check result.filePath.endsWith("file.txt")

  test "v on directory returns frHandled":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find subdir
    for i, entry in state.entries:
      if entry.name == "subdir":
        state.selectedIndex = i
        break
    let key = toKeyCombo('v')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled

  test "h on file returns frOpenFileHSplit":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find file.txt
    for i, entry in state.entries:
      if entry.name == "file.txt":
        state.selectedIndex = i
        break
    let key = toKeyCombo('h')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frOpenFileHSplit
    check result.filePath.endsWith("file.txt")

  test "h on directory returns frHandled":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find subdir
    for i, entry in state.entries:
      if entry.name == "subdir":
        state.selectedIndex = i
        break
    let key = toKeyCombo('h')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled

suite "FilerHandler - Toggle hidden (. key)":
  setup:
    let testDir = getTempDir() / "moe_filer_handler_test"
    createDir(testDir)
    writeFile(testDir / "visible.txt", "")
    writeFile(testDir / ".hidden", "")

  teardown:
    removeDir(testDir)

  test ". toggles hidden files visibility":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    check state.showHidden == false
    let initialLen = state.entries.len

    let key = toKeyCombo('.')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled
    check state.showHidden == true
    check state.entries.len > initialLen

suite "FilerHandler - Delete (D key)":
  setup:
    let testDir = getTempDir() / "moe_filer_handler_test"
    createDir(testDir)
    writeFile(testDir / "deleteme.txt", "content")

  teardown:
    removeDir(testDir)

  test "D on file returns frDeleteFile":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find deleteme.txt
    for i, entry in state.entries:
      if entry.name == "deleteme.txt":
        state.selectedIndex = i
        break
    let key = toKeyCombo('D')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frDeleteFile
    check result.deletePath.endsWith("deleteme.txt")

  test "D on .. returns frHandled":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    state.selectedIndex = 0 # ".."
    let key = toKeyCombo('D')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled

suite "FilerHandler - File info (i key)":
  setup:
    let testDir = getTempDir() / "moe_filer_handler_test"
    createDir(testDir)
    writeFile(testDir / "info.txt", "content")

  teardown:
    removeDir(testDir)

  test "i returns frShowInfo with file info":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find info.txt
    for i, entry in state.entries:
      if entry.name == "info.txt":
        state.selectedIndex = i
        break
    let key = toKeyCombo('i')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frShowInfo
    check result.fileInfo.contains("info.txt")

suite "FilerHandler - Command mode (: key)":
  setup:
    let testDir = getTempDir() / "moe_filer_handler_test"
    createDir(testDir)

  teardown:
    removeDir(testDir)

  test ": returns frEnterCommand":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    let key = toKeyCombo(':')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frEnterCommand

suite "FilerHandler - Unhandled keys":
  setup:
    let testDir = getTempDir() / "moe_filer_handler_test"
    createDir(testDir)

  teardown:
    removeDir(testDir)

  test "Unhandled key returns frUnhandled":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    let key = toKeyCombo('z') # Not a bound key
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frUnhandled

  test "Unhandled special key returns frUnhandled":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    let key = toSpecialKeyCombo(skPageUp) # Not bound in filer
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frUnhandled

suite "FilerHandler - Symlink handling":
  setup:
    let testDir = getTempDir() / "moe_filer_handler_test"
    createDir(testDir)
    writeFile(testDir / "realfile.txt", "content")
    createDir(testDir / "realdir")
    createSymlink(testDir / "realfile.txt", testDir / "linktofile")
    createSymlink(testDir / "realdir", testDir / "linktodir")

  teardown:
    removeDir(testDir)

  test "l on symlink to directory returns frOpenDirectory":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find linktodir
    for i, entry in state.entries:
      if entry.name == "linktodir":
        state.selectedIndex = i
        break
    let key = toKeyCombo('l')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frOpenDirectory
    check result.dirPath.endsWith("linktodir")

  test "l on symlink to file returns frOpenFile":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find linktofile
    for i, entry in state.entries:
      if entry.name == "linktofile":
        state.selectedIndex = i
        break
    let key = toKeyCombo('l')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frOpenFile
    check result.filePath.endsWith("linktofile")

  test "v on symlink to file returns frOpenFileVSplit":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find linktofile
    for i, entry in state.entries:
      if entry.name == "linktofile":
        state.selectedIndex = i
        break
    let key = toKeyCombo('v')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frOpenFileVSplit

  test "v on symlink to directory returns frHandled":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find linktodir
    for i, entry in state.entries:
      if entry.name == "linktodir":
        state.selectedIndex = i
        break
    let key = toKeyCombo('v')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled

  test "h on symlink to file returns frOpenFileHSplit":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find linktofile
    for i, entry in state.entries:
      if entry.name == "linktofile":
        state.selectedIndex = i
        break
    let key = toKeyCombo('h')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frOpenFileHSplit

  test "h on symlink to directory returns frHandled":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find linktodir
    for i, entry in state.entries:
      if entry.name == "linktodir":
        state.selectedIndex = i
        break
    let key = toKeyCombo('h')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled

  test "Enter on symlink to directory returns frOpenDirectory":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find linktodir
    for i, entry in state.entries:
      if entry.name == "linktodir":
        state.selectedIndex = i
        break
    let key = toSpecialKeyCombo(skEnter)
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frOpenDirectory

  test "Enter on symlink to file returns frOpenFile":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    # Find linktofile
    for i, entry in state.entries:
      if entry.name == "linktofile":
        state.selectedIndex = i
        break
    let key = toSpecialKeyCombo(skEnter)
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frOpenFile

suite "FilerHandler - Edge cases":
  setup:
    let testDir = getTempDir() / "moe_filer_handler_test_empty"
    createDir(testDir)

  teardown:
    removeDir(testDir)

  test "Enter with no valid selection returns frHandled":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    state.selectedIndex = 100 # Invalid
    let key = toSpecialKeyCombo(skEnter)
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled

  test "l with no valid selection returns frHandled":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    state.selectedIndex = 100 # Invalid
    let key = toKeyCombo('l')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled

  test "v with no valid selection returns frHandled":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    state.selectedIndex = 100 # Invalid
    let key = toKeyCombo('v')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled

  test "D with no valid selection returns frHandled":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    state.selectedIndex = 100 # Invalid
    let key = toKeyCombo('D')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled

  test "h with no valid selection returns frHandled":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)
    state.selectedIndex = 100 # Invalid
    let key = toKeyCombo('h')
    let result = handler.handleFilerModeKey(state, 20, key)
    check result.kind == frHandled

  test "g followed by special key cancels gg and returns frUnhandled":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)

    # First 'g'
    let key1 = toKeyCombo('g')
    discard handler.handleFilerModeKey(state, 20, key1)
    check handler.waitingForG == true

    # Press PageUp (special key) instead of 'g'
    let key2 = toSpecialKeyCombo(skPageUp)
    let result = handler.handleFilerModeKey(state, 20, key2)
    check handler.waitingForG == false
    check result.kind == frUnhandled

  test "g followed by Escape returns frHandled":
    let handler = newFilerHandler()
    let state = newFilerState(testDir)

    # First 'g'
    let key1 = toKeyCombo('g')
    discard handler.handleFilerModeKey(state, 20, key1)
    check handler.waitingForG == true

    # Press Escape - should return handled
    let key2 = toSpecialKeyCombo(skEscape)
    let result = handler.handleFilerModeKey(state, 20, key2)
    check handler.waitingForG == false
    check result.kind == frHandled
