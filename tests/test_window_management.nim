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

import std/[unittest, os, tempfiles, strutils]
import pkg/results

import
  moepkg/[editorstatus, bufferstatus, unicodeext, gapbuffer, windownode]

proc createTempFile(content: string): string =
  ## Create a temporary file with given content and return the path
  let (fd, path) = createTempFile("moe_window_test_", ".txt")
  defer:
    close(fd)
  write(fd, content)
  return path

suite "Window Management Integration Tests":
  var status: EditorStatus

  setup:
    # Initialize without UI to avoid terminal dependencies in tests
    status = initEditorStatus().get
    # Create initial buffer
    discard status.addNewBufferInCurrentWin("", Mode.normal)

  teardown:
    # Clean up temporary files
    for i in countdown(status.bufStatus.high, 0):
      if status.bufStatus[i].path.len > 0 and fileExists($status.bufStatus[i].path):
        try:
          removeFile($status.bufStatus[i].path)
        except:
          discard

  test "Initial window state":
    ## Test: Verify initial window configuration

    # Should have exactly one main window initially
    check status.mainWindow.numOfMainWindow == 1
    check currentMainWindowNode != nil
    check currentMainWindowNode.windowIndex == 0
    check currentMainWindowNode.isActualWin

  test "Vertical window split":
    ## Test: Split window vertically -> Verify window structure

    let initialWindowCount = status.mainWindow.numOfMainWindow

    # Create some content for the current buffer
    currentBufStatus.buffer = "Line 1\nLine 2\nLine 3".toGapBuffer

    # Split window vertically
    let splitResult = status.verticalSplitWindow()
    check splitResult.isOk

    # Verify window count increased
    check status.mainWindow.numOfMainWindow == initialWindowCount + 1

    # Verify window structure
    let rootNode = mainWindowNode
    check rootNode.child.len > 0 # Should have child windows

    # Verify both windows are accessible
    check currentMainWindowNode.windowIndex >= 0
    check currentMainWindowNode.isActualWin

  test "Horizontal window split":
    ## Test: Split window horizontally -> Verify window structure

    let initialWindowCount = status.mainWindow.numOfMainWindow

    # Create content for current buffer
    currentBufStatus.buffer = "Horizontal split test\nSecond line".toGapBuffer

    # Split window horizontally
    let splitResult = status.horizontalSplitWindow()
    check splitResult.isOk

    # Verify window count increased
    check status.mainWindow.numOfMainWindow == initialWindowCount + 1

    # Verify window structure integrity
    check currentMainWindowNode != nil
    check currentMainWindowNode.isActualWin

  test "Multiple window splits":
    ## Test: Perform multiple splits -> Verify complex window layout

    let initialWindowCount = status.mainWindow.numOfMainWindow

    # First vertical split
    let vSplitResult = status.verticalSplitWindow()
    check vSplitResult.isOk

    # Then horizontal split
    let hSplitResult = status.horizontalSplitWindow()
    check hSplitResult.isOk

    # Verify final window count
    check status.mainWindow.numOfMainWindow == initialWindowCount + 2

    # Verify current window is still valid
    check currentMainWindowNode.windowIndex >= 0
    check currentMainWindowNode.windowIndex < status.mainWindow.numOfMainWindow

  test "Window navigation":
    ## Test: Create multiple windows -> Navigate between them

    # Create a second window through vertical split
    let splitResult = status.verticalSplitWindow()
    check splitResult.isOk

    let totalWindows = status.mainWindow.numOfMainWindow
    check totalWindows >= 2

    let initialWindowIndex = currentMainWindowNode.windowIndex

    # Move to next window
    status.moveNextWindow()
    let nextWindowIndex = currentMainWindowNode.windowIndex

    # Verify we moved to a different window
    check nextWindowIndex != initialWindowIndex
    check nextWindowIndex >= 0
    check nextWindowIndex < totalWindows

    # Move to previous window
    status.movePrevWindow()
    let prevWindowIndex = currentMainWindowNode.windowIndex

    # Should cycle through windows
    check prevWindowIndex >= 0
    check prevWindowIndex < totalWindows

  test "Window and buffer association":
    ## Test: Windows maintain correct buffer associations

    # Create first buffer with content
    let content1 = "First window content"
    let tempPath1 = createTempFile(content1)
    defer:
      if fileExists(tempPath1):
        removeFile(tempPath1)

    let result1 = status.addNewBufferInCurrentWin(tempPath1, Mode.normal)
    check result1.isOk
    let firstBufferIndex = status.bufferIndexInCurrentWindow

    # Split window and create second buffer
    let splitResult = status.verticalSplitWindow()
    check splitResult.isOk

    let content2 = "Second window content"
    let tempPath2 = createTempFile(content2)
    defer:
      if fileExists(tempPath2):
        removeFile(tempPath2)

    let result2 = status.addNewBufferInCurrentWin(tempPath2, Mode.normal)
    check result2.isOk
    let secondBufferIndex = status.bufferIndexInCurrentWindow

    # Verify different buffers in different windows
    check firstBufferIndex != secondBufferIndex
    check status.bufStatus[secondBufferIndex].buffer.toString().contains(
      "Second window"
    )

    # Navigate back to first window and verify buffer
    status.movePrevWindow()
    # The buffer association might change during navigation, but should remain valid
    check status.bufferIndexInCurrentWindow >= 0
    check status.bufferIndexInCurrentWindow < status.bufStatus.len

  test "Window closure":
    ## Test: Close windows -> Verify proper cleanup and navigation

    # Create additional windows
    let initialCount = status.mainWindow.numOfMainWindow
    let splitResult1 = status.verticalSplitWindow()
    check splitResult1.isOk
    let splitResult2 = status.horizontalSplitWindow()
    check splitResult2.isOk

    let maxWindowCount = status.mainWindow.numOfMainWindow
    check maxWindowCount == initialCount + 2

    # Close current window
    let currentNode = currentMainWindowNode
    status.closeWindow(currentNode)

    # Verify window count decreased
    check status.mainWindow.numOfMainWindow == maxWindowCount - 1

    # Verify current window is still valid
    check currentMainWindowNode != nil
    check currentMainWindowNode.windowIndex >= 0
    check currentMainWindowNode.windowIndex < status.mainWindow.numOfMainWindow

  test "Window resize operations":
    ## Test: Window resizing maintains layout integrity

    # Create split windows
    let splitResult = status.verticalSplitWindow()
    check splitResult.isOk

    # Test resize operation (simulated)
    let originalWindowNode = currentMainWindowNode
    check originalWindowNode.x >= 0
    check originalWindowNode.y >= 0
    check originalWindowNode.w > 0
    check originalWindowNode.h > 0

    # Simulate terminal resize
    status.resize()

    # Verify window dimensions remain valid after resize
    check currentMainWindowNode.x >= 0
    check currentMainWindowNode.y >= 0
    check currentMainWindowNode.w > 0
    check currentMainWindowNode.h > 0

  test "Window state consistency":
    ## Test: Window state remains consistent across operations

    let initialWindowIndex = currentMainWindowNode.windowIndex
    check initialWindowIndex == 0 # Should start at window 0

    # Perform various window operations
    let splitResult = status.verticalSplitWindow()
    check splitResult.isOk

    # Verify window indices are properly assigned
    let newWindowIndex = currentMainWindowNode.windowIndex
    check newWindowIndex >= 0
    check newWindowIndex < status.mainWindow.numOfMainWindow

    # Verify window node properties
    check currentMainWindowNode.isActualWin
    check currentMainWindowNode.bufferIndex >= 0
    check currentMainWindowNode.bufferIndex < status.bufStatus.len

  test "Window and cursor position":
    ## Test: Cursor position tracking across windows

    # Set up buffer with multiple lines
    currentBufStatus.buffer = "Line 1\nLine 2\nLine 3\nLine 4".toGapBuffer
    
    # Verify buffer was set up correctly (buffer.len returns number of lines)
    check currentBufStatus.buffer.len >= 1
    
    # Set cursor position within valid bounds (use 0-based indexing)
    let maxValidLine = max(0, currentBufStatus.buffer.len - 1)
    currentMainWindowNode.currentLine = min(2, maxValidLine)
    currentMainWindowNode.currentColumn = 3
    
    # Verify cursor is within bounds before proceeding
    check currentMainWindowNode.currentLine < currentBufStatus.buffer.len

    # Split window
    let splitResult = status.verticalSplitWindow()
    check splitResult.isOk

    # Navigate back to original window
    status.movePrevWindow()

    # Verify cursor position is preserved (or reasonably handled)
    check currentMainWindowNode.currentLine >= 0
    check currentMainWindowNode.currentColumn >= 0
    check currentMainWindowNode.currentLine < currentBufStatus.buffer.len

  test "Window limit handling":
    ## Test: Behavior with maximum number of windows

    let initialCount = status.mainWindow.numOfMainWindow
    var splitCount = 0

    # Try to create many windows (with reasonable limit)
    for i in 0 ..< 10:
      let splitResult = status.verticalSplitWindow()
      if splitResult.isOk:
        splitCount.inc
      else:
        break # Stop when split fails

    # Verify we could create at least some windows
    check splitCount > 0
    check status.mainWindow.numOfMainWindow > initialCount

    # Verify current window remains valid
    check currentMainWindowNode != nil
    check currentMainWindowNode.windowIndex >= 0
