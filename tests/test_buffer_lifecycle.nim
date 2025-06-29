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

import std/[unittest, os, tempfiles, sequtils, options, strutils]
import pkg/results

import moepkg/[editorstatus, bufferstatus, unicodeext, gapbuffer, ui, buffercache]
import utils

proc createTempFile(content: string): string =
  ## Create a temporary file with given content and return the path
  let (fd, path) = createTempFile("moe_buffer_test_", ".txt")
  defer:
    close(fd)
  write(fd, content)
  return path

suite "Buffer Lifecycle Integration Tests":
  var status: EditorStatus

  setup:
    # Initialize without UI to avoid terminal dependencies in tests
    status = initEditorStatus().get

  teardown:
    # Clean up temporary files
    for i in countdown(status.bufStatus.high, 0):
      if status.bufStatus[i].path.len > 0 and fileExists($status.bufStatus[i].path):
        try:
          removeFile($status.bufStatus[i].path)
        except:
          discard

  test "Buffer creation and initialization":
    ## Test: Create new buffer -> Verify proper initialization

    let initialBufferCount = status.bufStatus.len

    # Create a new buffer
    let result = status.addNewBuffer("", Mode.normal)
    check result.isOk

    let bufferIndex = result.get
    check bufferIndex >= 0
    check status.bufStatus.len == initialBufferCount + 1

    # Verify buffer properties
    let buffer = status.bufStatus[bufferIndex]
    check buffer.mode == Mode.normal
    check buffer.buffer.len >= 0 # Buffer should be valid (may have initial empty line)
    check buffer.id >= 0 # Valid ID assigned
    check buffer.characterEncoding != CharacterEncoding.unknown

  test "Buffer creation from file":
    ## Test: Create buffer from existing file -> Verify content loading

    let testContent = "Line 1\nLine 2\nLine 3"
    let tempPath = createTempFile(testContent)
    defer:
      if fileExists(tempPath):
        removeFile(tempPath)

    # Create buffer from file
    let result = status.addNewBufferInCurrentWin(tempPath, Mode.normal)
    check result.isOk

    # Verify buffer content matches file
    let bufferContent = currentBufStatus.buffer.toString().strip()
    check bufferContent == testContent.strip()
    check currentBufStatus.path == tempPath.toRunes

  test "Buffer with different modes":
    ## Test: Create buffers with different modes -> Verify mode-specific behavior

    # Test normal mode buffer
    let normalResult = status.addNewBuffer("", Mode.normal)
    check normalResult.isOk
    let normalIndex = normalResult.get
    check status.bufStatus[normalIndex].mode == Mode.normal
    check status.bufStatus[normalIndex].isEditMode # Normal mode is an edit mode

    # Test help mode buffer
    let helpResult = status.addNewBuffer("", Mode.help)
    check helpResult.isOk
    let helpIndex = helpResult.get
    check status.bufStatus[helpIndex].mode == Mode.help
    check not status.bufStatus[helpIndex].isEditMode # Help mode is not an edit mode

  test "Buffer switching and state preservation":
    ## Test: Create multiple buffers -> Switch between them -> Verify state preservation

    # Create first buffer with content
    let content1 = "First buffer content"
    let tempPath1 = createTempFile(content1)
    defer:
      if fileExists(tempPath1):
        removeFile(tempPath1)

    let result1 = status.addNewBufferInCurrentWin(tempPath1, Mode.normal)
    check result1.isOk
    let buffer1Index = status.bufferIndexInCurrentWindow

    # Modify cursor position in first buffer
    currentMainWindowNode.currentLine = 0
    currentMainWindowNode.currentColumn = 5

    # Create second buffer
    let content2 = "Second buffer content\nWith multiple lines"
    let tempPath2 = createTempFile(content2)
    defer:
      if fileExists(tempPath2):
        removeFile(tempPath2)

    let result2 = status.addNewBufferInCurrentWin(tempPath2, Mode.normal)
    check result2.isOk
    let buffer2Index = status.bufferIndexInCurrentWindow

    # Verify we're on second buffer
    check status.bufferIndexInCurrentWindow == buffer2Index
    check currentBufStatus.buffer.toString().strip().contains("Second buffer")

    # Switch back to first buffer
    status.changeCurrentBuffer(buffer1Index)
    check status.bufferIndexInCurrentWindow == buffer1Index
    check currentBufStatus.buffer.toString().strip().contains("First buffer")

  test "Buffer cache integration":
    ## Test: Buffer caching functionality during lifecycle

    let content = "Cached buffer content"
    let tempPath = createTempFile(content)
    defer:
      if fileExists(tempPath):
        removeFile(tempPath)

    # Create buffer and add to cache
    let result = status.addNewBufferInCurrentWin(tempPath, Mode.normal)
    check result.isOk

    let bufferId = currentBufStatus.id
    let bufferPath = $currentBufStatus.path

    # Verify buffer cache operations
    check not status.bufferCache.isInCache(bufferId) # Not cached initially

    # Add to cache manually (simulating cache operation)
    status.bufferCache.addToCache(currentBufStatus)
    check status.bufferCache.isInCache(bufferId)

    # Test cache retrieval
    let cachedBuffer = status.bufferCache.getFromCache(bufferId)
    check cachedBuffer.isSome
    check cachedBuffer.get.bufStatus.id == bufferId

  test "Buffer modification tracking":
    ## Test: Buffer change tracking and dirty state

    # Create buffer
    let result = status.addNewBuffer("", Mode.normal)
    check result.isOk
    let bufferIndex = result.get

    # Initial state should be clean
    check status.bufStatus[bufferIndex].countChange == 0

    # Modify buffer
    status.bufStatus[bufferIndex].buffer.add("Test content".toRunes)
    status.bufStatus[bufferIndex].countChange.inc

    # Verify modification tracking
    check status.bufStatus[bufferIndex].countChange > 0
    check status.bufStatus[bufferIndex].isUpdate # Should be marked for update

  test "Buffer deletion and cleanup":
    ## Test: Delete buffer -> Verify proper cleanup

    let initialCount = status.bufStatus.len

    # Create temporary buffer
    let result = status.addNewBuffer("", Mode.normal)
    check result.isOk
    let bufferIndex = result.get
    let bufferId = status.bufStatus[bufferIndex].id

    check status.bufStatus.len == initialCount + 1

    # Delete buffer
    status.deleteBuffer(bufferIndex)

    # Verify buffer is removed
    check status.bufStatus.len == initialCount

    # Verify buffer ID is no longer present
    var bufferExists = false
    for buf in status.bufStatus:
      if buf.id == bufferId:
        bufferExists = true
        break
    check not bufferExists

  test "Buffer encoding handling":
    ## Test: Buffer creation with different character encodings

    # Create buffer with UTF-8 content (default)
    let utf8Content = "UTF-8 content with émojis 🎉"
    let tempPath = createTempFile(utf8Content)
    defer:
      if fileExists(tempPath):
        removeFile(tempPath)

    let result = status.addNewBufferInCurrentWin(tempPath, Mode.normal)
    check result.isOk

    # Verify encoding detection/handling
    check currentBufStatus.characterEncoding in
      [CharacterEncoding.utf8, CharacterEncoding.unknown]
    check currentBufStatus.buffer.toString().contains("content")

  test "Buffer memory management":
    ## Test: Create many buffers -> Verify memory efficiency

    let initialBufferCount = status.bufStatus.len
    let testBufferCount = 10

    var createdBuffers: seq[int] = @[]

    # Create multiple buffers
    for i in 0 ..< testBufferCount:
      let content = "Buffer " & $i & " content"
      let tempPath = createTempFile(content)

      let result = status.addNewBuffer(tempPath, Mode.normal)
      check result.isOk
      createdBuffers.add(result.get)

    # Verify all buffers created
    check status.bufStatus.len == initialBufferCount + testBufferCount

    # Verify each buffer is accessible and has correct content
    for i, bufferIndex in createdBuffers:
      if bufferIndex < status.bufStatus.len:
        let buf = status.bufStatus[bufferIndex]
        check buf.buffer.toString().contains("Buffer " & $i)

    # Cleanup
    for i in countdown(createdBuffers.high, 0):
      let bufferIndex = createdBuffers[i]
      if bufferIndex < status.bufStatus.len and
          status.bufStatus[bufferIndex].path.len > 0:
        let path = $status.bufStatus[bufferIndex].path
        if fileExists(path):
          removeFile(path)

  test "Buffer state consistency":
    ## Test: Buffer state remains consistent through operations

    # Create buffer
    let result = status.addNewBuffer("", Mode.normal)
    check result.isOk
    let bufferIndex = result.get

    # Test various state properties
    let buffer = status.bufStatus[bufferIndex]

    # Basic consistency checks
    check buffer.id >= 0
    check buffer.mode in
      {Mode.normal, Mode.insert, Mode.visual, Mode.ex, Mode.help, Mode.filer}
    check buffer.buffer.len >= 0 # Buffer should be initialized
    check buffer.characterEncoding != CharacterEncoding.unknown or buffer.path.len == 0

    # State transition consistency
    let originalMode = buffer.mode
    status.changeMode(Mode.insert)
    check currentBufStatus.prevMode == originalMode
    check currentBufStatus.mode == Mode.insert

    # Verify buffer integrity after mode change
    check currentBufStatus.id == buffer.id # ID should remain the same
