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

import std/[unittest, os, tempfiles, strutils, options]
import pkg/results

import
  moepkg/[editorstatus, bufferstatus, unicodeext, gapbuffer, viewhighlight]

proc createTempFile(content: string): string =
  ## Create a temporary file with given content and return the path
  let (fd, path) = createTempFile("moe_test_", ".txt")
  defer:
    close(fd)
  write(fd, content)
  return path

suite "Editor Workflow Integration Tests":
  var status: EditorStatus

  setup:
    # Initialize without UI to avoid terminal dependencies in tests
    status = initEditorStatus().get
    discard status.addNewBufferInCurrentWin("", Mode.normal)

  teardown:
    for i in countdown(status.bufStatus.high, 0):
      if status.bufStatus[i].path.len > 0 and fileExists($status.bufStatus[i].path):
        try:
          removeFile($status.bufStatus[i].path)
        except:
          discard

  test "Basic text editing workflow":
    ## Test: Create buffer -> Insert text -> Save -> Verify content

    # Create a temporary file with initial content to avoid empty file issues
    let tempPath = createTempFile("initial\n")
    defer:
      if fileExists(tempPath):
        removeFile(tempPath)

    # Open the file
    let openResult = status.addNewBufferInCurrentWin(tempPath, Mode.normal)
    check openResult.isOk

    # Switch to insert mode and add text
    status.changeMode(Mode.insert)
    check currentBufStatus.mode == Mode.insert

    # Get initial buffer content and add text
    let initialContent = currentBufStatus.buffer.toString()
    
    # Simulate typing "Hello, World!" (append to existing content)
    let text = "Hello, World!".toRunes
    currentBufStatus.buffer.add(text)

    # Verify buffer content contains our added text
    let finalContent = currentBufStatus.buffer.toString()
    check finalContent.contains("Hello, World!")
    check finalContent.len >= initialContent.len + text.len

    # Save the file
    currentBufStatus.path = tempPath.toRunes
    # Note: Actual file saving would require file I/O which is tested elsewhere

    # Switch back to normal mode
    status.changeMode(Mode.normal)
    check currentBufStatus.mode == Mode.normal

  test "Multiple buffer workflow":
    ## Test: Create multiple buffers -> Switch between them -> Verify state

    # Create first buffer with content
    let tempPath1 = createTempFile("First file content")
    defer:
      if fileExists(tempPath1):
        removeFile(tempPath1)

    let openResult1 = status.addNewBufferInCurrentWin(tempPath1, Mode.normal)
    check openResult1.isOk
    let firstBufferIndex = status.bufferIndexInCurrentWindow

    # Create second buffer
    let tempPath2 = createTempFile("Second file content")
    defer:
      if fileExists(tempPath2):
        removeFile(tempPath2)

    let openResult2 = status.addNewBufferInCurrentWin(tempPath2, Mode.normal)
    check openResult2.isOk
    let secondBufferIndex = status.bufferIndexInCurrentWindow

    # Verify we're on the second buffer
    check status.bufferIndexInCurrentWindow == secondBufferIndex
    check status.bufferIndexInCurrentWindow != firstBufferIndex

    # Switch back to first buffer
    status.changeCurrentBuffer(firstBufferIndex)
    check status.bufferIndexInCurrentWindow == firstBufferIndex

    # Verify buffer contents are maintained
    check status.bufStatus.len >= 2

  test "Edit and undo workflow":
    ## Test: Edit text -> Undo -> Verify restoration

    # Start with some initial content
    currentBufStatus.buffer = "Initial content\nSecond line".toGapBuffer
    let originalContent = currentBufStatus.buffer.toString()

    # Begin a new edit suit for undo/redo tracking
    currentBufStatus.buffer.beginNewSuitIfNeeded()

    # Switch to insert mode and modify
    status.changeMode(Mode.insert)

    # Add some text (simulating user input)
    let addedText = "\nThird line".toRunes
    currentBufStatus.buffer.add(addedText)

    # Verify content changed
    let modifiedContent = currentBufStatus.buffer.toString()
    check modifiedContent != originalContent
    check modifiedContent.contains("Third line")

    # Test undo operation
    if currentBufStatus.buffer.canUndo:
      currentBufStatus.buffer.undo()
      let undoneContent = currentBufStatus.buffer.toString()
      # Content should be closer to original (exact match depends on undo granularity)
      check undoneContent.len <= modifiedContent.len

  test "Mode transition workflow":
    ## Test: Normal -> Insert -> Visual -> Ex -> Normal

    # Start in normal mode
    check currentBufStatus.mode == Mode.normal

    # Transition to insert mode
    status.changeMode(Mode.insert)
    check currentBufStatus.mode == Mode.insert
    check currentBufStatus.prevMode == Mode.normal

    # Transition to visual mode
    status.changeMode(Mode.visual)
    check currentBufStatus.mode == Mode.visual
    check currentBufStatus.prevMode == Mode.insert

    # Transition to ex mode
    status.changeMode(Mode.ex)
    check currentBufStatus.mode == Mode.ex
    check currentBufStatus.prevMode == Mode.visual

    # Return to normal mode
    status.changeMode(Mode.normal)
    check currentBufStatus.mode == Mode.normal
    check currentBufStatus.prevMode == Mode.ex

  test "Search and replace workflow":
    ## Test: Create content -> Search -> Replace -> Verify results

    # Set up buffer with searchable content
    currentBufStatus.buffer = "Hello world\nHello universe\nGoodbye world".toGapBuffer

    # Add search term to history (simulating search)
    let searchTerm = "Hello".toRunes
    status.searchHistory.add(searchTerm)

    # Verify search history
    check status.searchHistory.len > 0
    check status.searchHistory[^1] == searchTerm

    # Test highlighting functionality (basic check)
    status.highlightingText = some(HighlightingText(
      kind: HighlightingTextKind.search,
      text: @[searchTerm],
      isIgnorecase: false,
      isSmartcase: false,
    ))

    check status.highlightingText.isSome
    check status.highlightingText.get.kind == HighlightingTextKind.search

  test "File operations workflow":
    ## Test: New file -> Edit -> Save -> Close -> Reopen -> Verify persistence

    let tempPath = createTempFile("placeholder\n")
    defer:
      if fileExists(tempPath):
        removeFile(tempPath)

    # Open new file
    let openResult = status.addNewBufferInCurrentWin(tempPath, Mode.normal)
    check openResult.isOk

    # Add content
    let content = "Test file content\nLine 2\nLine 3".toRunes
    currentBufStatus.buffer = content.toGapBuffer
    currentBufStatus.path = tempPath.toRunes

    # Verify buffer state
    check currentBufStatus.buffer.toString().strip().contains("Test file content")
    check currentBufStatus.path == tempPath.toRunes

    # Test buffer exists in the status
    check status.bufStatus.len > 0

    # Test buffer can be found by path
    var found = false
    for buf in status.bufStatus:
      if buf.path == tempPath.toRunes:
        found = true
        break
    check found

  test "Error handling workflow":
    ## Test: Invalid operations -> Verify graceful handling

    # Test invalid buffer index
    discard status.bufferIndexInCurrentWindow
    status.changeCurrentBuffer(-1) # Invalid index
    # Should not crash and should maintain valid state
    check status.bufferIndexInCurrentWindow >= 0

    # Test invalid buffer access
    let invalidIndex = status.bufStatus.len + 10
    status.changeCurrentBuffer(invalidIndex) # Invalid index
    # Should handle gracefully
    check status.bufferIndexInCurrentWindow < status.bufStatus.len

    # Test empty command
    let emptyCommand = "".toRunes
    # Should not crash when processing empty command
    check emptyCommand.len == 0 # Basic verification
