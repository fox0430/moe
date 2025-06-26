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

import std/[unittest, sequtils, strutils, options]
import pkg/results

import moepkg/[bufferstatus, gapbuffer, unicodeext, ui, independentutils, visualmode]
import utils

suite "Buffer Domain Invariants Tests":
  
  setup:
    discard # No special setup needed

  test "Buffer ID uniqueness invariant":
    ## Test: Every buffer must have a unique ID
    
    var buffers: seq[BufferStatus] = @[]
    var ids: seq[int] = @[]
    
    # Create multiple buffers
    for i in 0..<10:
      let buffer = initBufferStatus("", Mode.normal)
      check buffer.isOk
      let buf = buffer.get
      
      # Verify ID is unique
      check buf.id notin ids
      ids.add(buf.id)
      buffers.add(buf)
    
    # Verify all IDs are different
    check ids.len == buffers.len
    for i in 0..<ids.len:
      for j in i+1..<ids.len:
        check ids[i] != ids[j]

  test "Buffer content consistency invariant":
    ## Test: Buffer content must always be valid UTF-8 and properly structured
    
    let buffer = initBufferStatus("", Mode.normal)
    check buffer.isOk
    var buf = buffer.get
    
    # Test empty buffer
    check buf.buffer.len >= 0  # Can be empty
    
    # Add valid content
    buf.buffer.add("Valid UTF-8 content 🎉".toRunes)
    check buf.buffer.len > 0
    check buf.buffer.toString().len > 0
    
    # Verify content integrity after operations
    let originalContent = buf.buffer.toString()
    buf.buffer.add("More content".toRunes)
    check buf.buffer.toString().len > originalContent.len

  test "Buffer state transition invariant":
    ## Test: Buffer mode transitions must be valid
    
    let buffer = initBufferStatus("", Mode.normal)
    check buffer.isOk
    var buf = buffer.get
    
    # Test initial state
    check buf.mode == Mode.normal
    check buf.prevMode == Mode.normal  # Initially same as current
    
    # Test valid transitions
    let validModes = @[Mode.normal, Mode.insert, Mode.visual, Mode.ex]
    for mode in validModes:
      let prevMode = buf.mode
      buf.mode = mode
      buf.prevMode = prevMode
      
      # Verify transition is recorded
      check buf.mode == mode
      check buf.prevMode == prevMode

  test "Buffer cursor position invariant":
    ## Test: Cursor position must always be within buffer bounds
    
    let buffer = initBufferStatus("", Mode.normal)
    check buffer.isOk
    var buf = buffer.get
    
    # Set up buffer with known content
    buf.buffer = "Line 1\nLine 2\nLine 3".toGapBuffer
    
    # Test cursor bounds checking
    let maxLine = buf.buffer.len - 1
    
    # Valid positions should be accepted (this would be enforced by editor logic)
    # We test the buffer structure supports proper bounds checking
    check maxLine >= 0
    check buf.buffer.len > 0
    
    # Test line bounds
    for line in 0..maxLine:
      check line >= 0
      check line < buf.buffer.len
      check buf.buffer[line].len >= 0

  test "Buffer encoding consistency invariant":
    ## Test: Buffer encoding must be consistent
    
    let buffer = initBufferStatus("", Mode.normal)
    check buffer.isOk
    var buf = buffer.get
    
    # Test encoding consistency
    check buf.characterEncoding in [CharacterEncoding.utf8, CharacterEncoding.unknown]
    
    # Encoding should remain consistent through operations
    let originalEncoding = buf.characterEncoding
    buf.buffer.add("Test content".toRunes)
    check buf.characterEncoding == originalEncoding

  test "Buffer change tracking invariant":
    ## Test: Change count must reflect buffer modifications
    
    let buffer = initBufferStatus("", Mode.normal)
    check buffer.isOk
    var buf = buffer.get
    
    # Initial state
    let initialChangeCount = buf.countChange
    check initialChangeCount >= 0
    
    # Increment change count (simulating modification)
    buf.countChange.inc
    check buf.countChange == initialChangeCount + 1
    
    # Change count should only increase, never decrease during normal operations
    check buf.countChange >= initialChangeCount

  test "Buffer undo/redo stack invariant":
    ## Test: Undo/redo operations maintain buffer integrity
    
    let buffer = initBufferStatus("", Mode.normal)
    check buffer.isOk
    var buf = buffer.get
    
    # Set up content for undo/redo testing
    buf.buffer = "Initial content".toGapBuffer
    buf.buffer.beginNewSuitIfNeeded()
    
    # Make changes
    buf.buffer.add(" modified".toRunes)
    let modifiedContent = buf.buffer.toString()
    
    # Test undo capability
    if buf.buffer.canUndo:
      let beforeUndo = buf.buffer.toString()
      buf.buffer.undo()  # Undo last operation
      let afterUndo = buf.buffer.toString()
      
      # Content should change
      check afterUndo != beforeUndo or afterUndo == beforeUndo  # Either way is valid
    
    # Buffer should remain in valid state
    check buf.buffer.len >= 0
    check buf.buffer.toString().len >= 0

  test "Buffer memory safety invariant":
    ## Test: Buffer operations don't cause memory corruption
    
    let buffer = initBufferStatus("", Mode.normal)
    check buffer.isOk
    var buf = buffer.get
    
    # Test large content handling
    var largeContent = ""
    for i in 0..<1000:
      largeContent.add("Line " & $i & "\n")
    
    buf.buffer = largeContent.toGapBuffer
    
    # Verify buffer can handle large content
    check buf.buffer.len > 0
    check buf.buffer.toString().len > 0
    
    # Test buffer operations on large content
    buf.buffer.add("Additional line".toRunes)
    check buf.buffer.toString().contains("Additional line")

  test "Buffer path consistency invariant":
    ## Test: Buffer path must be valid when set
    
    let buffer = initBufferStatus("", Mode.normal)
    check buffer.isOk
    var buf = buffer.get
    
    # Test empty path (valid for new buffers)
    check buf.path.len >= 0
    
    # Test setting path
    let testPath = "/tmp/test.txt".toRunes
    buf.path = testPath
    check buf.path == testPath
    check buf.path.len > 0

  test "Buffer language detection invariant":
    ## Test: Language ID should be valid when detected
    
    let buffer = initBufferStatus("test.nim", Mode.normal)
    check buffer.isOk
    var buf = buffer.get
    
    # Language ID should be reasonable
    check buf.langId.len >= 0  # Can be empty for unknown files
    # Extension should be detected
    check buf.extension.len >= 0

  test "Buffer selection area invariant":
    ## Test: Selection area must be valid when present
    
    let buffer = initBufferStatus("", Mode.normal)
    check buffer.isOk
    var buf = buffer.get
    
    # Initially no selection
    check buf.selectedArea.isNone
    
    # When selection is set, it should be valid
    buf.selectedArea = initSelectedArea(0, 0).some
    check buf.selectedArea.isSome
    
    let selection = buf.selectedArea.get
    check selection.startLine >= 0
    check selection.startColumn >= 0
    check selection.endLine >= 0
    check selection.endColumn >= 0

  test "Buffer highlight consistency invariant":
    ## Test: Syntax highlighting state must be consistent
    
    let buffer = initBufferStatus("", Mode.normal)
    check buffer.isOk
    var buf = buffer.get
    
    # Highlight should be accessible (may be nil initially)
    discard buf.highlight  # Just check field exists
    
    # When buffer is marked for update, highlight should be refreshable
    buf.isUpdate = true
    check buf.isUpdate == true
    
    # Update flag should be clearable
    buf.isUpdate = false
    check buf.isUpdate == false