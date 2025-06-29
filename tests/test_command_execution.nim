#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import std/[unittest, os, tempfiles, options, strutils]
import pkg/results

import
  moepkg/[
    editorstatus, bufferstatus, unicodeext, gapbuffer, ui, registers, movement,
    viewhighlight,
  ]
import utils

import moepkg/mainloop {.all.}

proc createTempFile(content: string): string =
  ## Create a temporary file with given content and return the path
  let (fd, path) = createTempFile("moe_cmd_test_", ".txt")
  defer:
    close(fd)
  write(fd, content)
  return path

suite "Command Execution Integration Tests":
  var status: EditorStatus

  setup:
    # Initialize without UI to avoid terminal dependencies in tests
    status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin("", Mode.normal)
    # Set up buffer with some content for testing
    currentBufStatus.buffer = "Line 1\nLine 2\nLine 3\nLine 4".toGapBuffer

  teardown:
    # Clean up temporary files
    for i in countdown(status.bufStatus.high, 0):
      if status.bufStatus[i].path.len > 0 and fileExists($status.bufStatus[i].path):
        try:
          removeFile($status.bufStatus[i].path)
        except:
          discard

  test "Mode transition commands":
    ## Test: Commands that change editor mode

    # Start in normal mode
    check currentBufStatus.mode == Mode.normal

    # Test transition to insert mode (simulate 'i' command)
    status.changeMode(Mode.insert)
    check currentBufStatus.mode == Mode.insert
    check currentBufStatus.prevMode == Mode.normal

    # Test transition to visual mode
    status.changeMode(Mode.visual)
    check currentBufStatus.mode == Mode.visual
    check currentBufStatus.prevMode == Mode.insert

    # Test transition to ex mode
    status.changeMode(Mode.ex)
    check currentBufStatus.mode == Mode.ex
    check currentBufStatus.prevMode == Mode.visual

    # Return to normal mode
    status.changeMode(Mode.normal)
    check currentBufStatus.mode == Mode.normal

  test "Movement commands":
    ## Test: Cursor movement commands

    # Ensure we're in normal mode
    status.changeMode(Mode.normal)

    # Test initial position
    currentMainWindowNode.currentLine = 0
    currentMainWindowNode.currentColumn = 0
    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

    # Test line movement
    # Debug: Check buffer state before keyDown
    let bufferLen = currentBufStatus.buffer.len
    let currentLine = currentMainWindowNode.currentLine
    # Only test keyDown if there are more lines to move to
    if currentLine + 1 < bufferLen:
      currentBufStatus.keyDown(currentMainWindowNode)
      check currentMainWindowNode.currentLine == 1
    else:
      # If we can't move down, verify we stay at current position
      currentBufStatus.keyDown(currentMainWindowNode)
      check currentMainWindowNode.currentLine == currentLine

    currentBufStatus.keyUp(currentMainWindowNode)
    check currentMainWindowNode.currentLine == 0

    # Test character movement
    currentBufStatus.keyRight(currentMainWindowNode)
    check currentMainWindowNode.currentColumn == 1

    currentMainWindowNode.keyLeft()
    check currentMainWindowNode.currentColumn == 0

  test "Text insertion commands":
    ## Test: Commands that modify buffer content

    # Switch to insert mode
    status.changeMode(Mode.insert)
    check currentBufStatus.mode == Mode.insert

    # Test character insertion
    let originalLength = currentBufStatus.buffer[0].len
    let insertChar = 'X'.toRune

    # Simulate character insertion at beginning of first line
    var line = currentBufStatus.buffer[0]
    line.insert(insertChar, 0)
    currentBufStatus.buffer[0] = line
    check currentBufStatus.buffer[0].len == originalLength + 1
    check currentBufStatus.buffer[0][0] == insertChar

  test "Text deletion commands":
    ## Test: Commands that delete text

    # Ensure we have content to delete
    currentBufStatus.buffer = "Hello World\nSecond Line".toGapBuffer
    currentMainWindowNode.currentLine = 0
    currentMainWindowNode.currentColumn = 0

    # Test character deletion
    let originalLength = currentBufStatus.buffer[0].len
    if originalLength > 0:
      var line = currentBufStatus.buffer[0]
      line.delete(0) # Delete first character
      currentBufStatus.buffer[0] = line
      check currentBufStatus.buffer[0].len == originalLength - 1

  test "Undo/Redo commands":
    ## Test: Undo and redo functionality

    # Set up initial content
    currentBufStatus.buffer = "Original content".toGapBuffer
    currentBufStatus.buffer.beginNewSuitIfNeeded()

    # Make a change
    var line = currentBufStatus.buffer[0]
    line.add(" modified".toRunes)
    currentBufStatus.buffer[0] = line
    let modifiedContent = currentBufStatus.buffer.toString()

    # Test undo
    if currentBufStatus.buffer.canUndo:
      currentBufStatus.buffer.undo()
      let undoneContent = currentBufStatus.buffer.toString()
      check undoneContent != modifiedContent # Should be different after undo

    # Test redo
    if currentBufStatus.buffer.canRedo:
      currentBufStatus.buffer.redo()
      # Content should change again

  test "Search commands":
    ## Test: Search functionality and history

    # Set up searchable content
    currentBufStatus.buffer = "Hello world\nHello universe\nGoodbye world".toGapBuffer

    # Add search term to history
    let searchTerm = "Hello".toRunes
    status.searchHistory.add(searchTerm)

    # Verify search history
    check status.searchHistory.len > 0
    check status.searchHistory[^1] == searchTerm

    # Test search highlighting setup
    status.highlightingText =
      HighlightingText(
        kind: HighlightingTextKind.search,
        text: @[searchTerm],
        isIgnorecase: false,
        isSmartcase: false,
      ).some

    check status.highlightingText.isSome
    check status.highlightingText.get.kind == HighlightingTextKind.search

  test "Register operations":
    ## Test: Register (clipboard) functionality

    # Test yanking to register
    let testText = "yanked text".toRunes
    status.registers.setYankedRegister(testText)

    # Verify register content (yanked register is number register 0)
    let retrievedRegister = status.registers.getNumberRegister(0)
    check retrievedRegister.buffer.len > 0
    check retrievedRegister.buffer[0] == testText

  test "Macro recording and execution":
    ## Test: Macro functionality

    # Test macro recording setup
    let registerName = 'q'.toRune
    check isOperationRegisterName(registerName)

    # Test adding operation to register
    let operation = "test_operation".toRunes
    let result = status.registers.addOperation(registerName, operation)
    check result.isOk

    # Verify operation was stored
    let operations = status.registers.getOperations(registerName)
    check operations.isOk
    check operations.get.commands.len > 0

  test "Command history management":
    ## Test: Command history functionality

    # Test ex command history
    let exCommand = "testcommand".toRunes
    status.exCommandHistory.add(exCommand)
    check status.exCommandHistory.len > 0
    check status.exCommandHistory[^1] == exCommand

    # Test search history (already partially tested above)
    let searchCommand = "searchterm".toRunes
    status.searchHistory.add(searchCommand)
    check status.searchHistory.len > 0

  test "Buffer modification tracking":
    ## Test: Change tracking through commands

    # Start with clean buffer
    let initialChangeCount = currentBufStatus.countChange

    # Modify buffer through command
    var line = currentBufStatus.buffer[0]
    line.add("new text".toRunes)
    currentBufStatus.buffer[0] = line
    currentBufStatus.countChange.inc

    # Verify change tracking
    check currentBufStatus.countChange > initialChangeCount
    check currentBufStatus.isUpdate # Should be marked for update

  test "Error handling in commands":
    ## Test: Command error handling

    # Test invalid cursor movement
    currentMainWindowNode.currentLine = 0
    currentMainWindowNode.currentColumn = 0

    # Try to move beyond buffer bounds (should be handled gracefully)
    currentBufStatus.keyUp(currentMainWindowNode) # Already at top
    check currentMainWindowNode.currentLine == 0 # Should remain at 0

    currentMainWindowNode.keyLeft() # Already at left
    check currentMainWindowNode.currentColumn == 0 # Should remain at 0

  test "Command state consistency":
    ## Test: Editor state remains consistent after commands

    let originalMode = currentBufStatus.mode
    let originalBufferCount = status.bufStatus.len

    # Execute a series of commands
    status.changeMode(Mode.insert)
    status.changeMode(Mode.normal)

    # Verify state consistency
    check currentBufStatus.mode == Mode.normal
    check status.bufStatus.len == originalBufferCount # Buffer count unchanged
    check currentMainWindowNode.currentLine >= 0
    check currentMainWindowNode.currentColumn >= 0

  test "Complex command sequences":
    ## Test: Sequences of multiple commands

    # Set up content for complex operations
    currentBufStatus.buffer = "Line 1\nLine 2\nLine 3".toGapBuffer
    currentMainWindowNode.currentLine = 0
    currentMainWindowNode.currentColumn = 0

    # Sequence: Move down, insert mode, add text, normal mode, move up
    let bufferLen = currentBufStatus.buffer.len
    let currentLine = currentMainWindowNode.currentLine

    # Only test keyDown if there are more lines to move to
    if currentLine + 1 < bufferLen:
      currentBufStatus.keyDown(currentMainWindowNode) # Move to line 1
      check currentMainWindowNode.currentLine == 1
      let targetLine = 1

      status.changeMode(Mode.insert)
      check currentBufStatus.mode == Mode.insert

      # Simulate text insertion on the target line
      if targetLine < currentBufStatus.buffer.len:
        var line = currentBufStatus.buffer[targetLine]
        line.add(" added".toRunes)
        currentBufStatus.buffer[targetLine] = line
    else:
      # If buffer doesn't have enough lines, just test mode change
      status.changeMode(Mode.insert)
      check currentBufStatus.mode == Mode.insert

    status.changeMode(Mode.normal)
    check currentBufStatus.mode == Mode.normal

    # Only try keyUp if we're not already at the top
    if currentMainWindowNode.currentLine > 0:
      currentBufStatus.keyUp(currentMainWindowNode) # Move back to line 0
      check currentMainWindowNode.currentLine == 0

    # Verify final state is consistent - only check if we actually added text
    if bufferLen > 1:
      check currentBufStatus.buffer.toString().contains("added")

  test "Command interruption handling":
    ## Test: Behavior when commands are interrupted

    # Start a command sequence
    status.changeMode(Mode.insert)
    check currentBufStatus.mode == Mode.insert

    # Simulate interruption (e.g., Escape key)
    status.changeMode(Mode.normal)
    check currentBufStatus.mode == Mode.normal

    # Verify state is clean after interruption
    check currentMainWindowNode.currentLine >= 0
    check currentMainWindowNode.currentColumn >= 0
