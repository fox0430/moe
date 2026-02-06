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

## Tests for editor.nim

import std/[unittest, os, options, strutils]
import pkg/results
import ../src/moepkg/[editor, buffer, config, config_loader, config_mode, gap_buffer]

proc createTestEditor(): Editor =
  ## Create a minimal editor for testing
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

suite "Editor - findBufferByPath":
  test "Find buffer by absolute path":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_find_buffer.txt"

    # Create a test file
    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    # Load the file
    let result = e.editFile(testFile)
    check result.isOk

    # Find the buffer by path
    let index = e.findBufferByPath(testFile)
    check index >= 0
    check e.buffers[index].filePath.isSome
    check e.buffers[index].filePath.get == testFile

  test "Return -1 when buffer not found":
    let e = createTestEditor()
    let index = e.findBufferByPath("/nonexistent/path/file.txt")
    check index == -1

suite "Editor - currentBufferIndex":
  test "Returns index of active buffer":
    let e = createTestEditor()

    # Initial buffer should be at index 0
    let index = e.currentBufferIndex()
    check index == 0

  test "Returns correct index after adding buffers":
    let e = createTestEditor()
    let testFile1 = "/tmp/moe_test_index1.txt"
    let testFile2 = "/tmp/moe_test_index2.txt"

    writeFile(testFile1, "content1")
    writeFile(testFile2, "content2")
    defer:
      removeFile(testFile1)
      removeFile(testFile2)

    discard e.editFile(testFile1)
    discard e.editFile(testFile2)

    # After editFile, we should be at the last buffer
    let index = e.currentBufferIndex()
    check index == e.buffers.len - 1

suite "Editor - switchToBufferByIndex":
  test "Switch to valid buffer index":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_switch.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    # Switch to first buffer (index 0)
    e.switchToBufferByIndex(0)
    check e.currentBufferIndex() == 0

    # Switch to second buffer (index 1)
    e.switchToBufferByIndex(1)
    check e.currentBufferIndex() == 1

  test "Ignore invalid buffer index (negative)":
    let e = createTestEditor()
    let originalIndex = e.currentBufferIndex()

    e.switchToBufferByIndex(-1)
    check e.currentBufferIndex() == originalIndex

  test "Ignore invalid buffer index (out of bounds)":
    let e = createTestEditor()
    let originalIndex = e.currentBufferIndex()

    e.switchToBufferByIndex(999)
    check e.currentBufferIndex() == originalIndex

suite "Editor - switchToNextBuffer and switchToPrevBuffer":
  test "Switch to next buffer":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_next.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToBufferByIndex(0)

    e.switchToNextBuffer()
    check e.currentBufferIndex() == 1

  test "Switch to next buffer wraps around":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_wrap.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToBufferByIndex(1) # Last buffer

    e.switchToNextBuffer()
    check e.currentBufferIndex() == 0 # Wraps to first

  test "Switch to prev buffer":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_prev.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToBufferByIndex(1)

    e.switchToPrevBuffer()
    check e.currentBufferIndex() == 0

  test "Switch to prev buffer wraps around":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_prev_wrap.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToBufferByIndex(0) # First buffer

    e.switchToPrevBuffer()
    check e.currentBufferIndex() == 1 # Wraps to last

  test "No switch when only one buffer":
    let e = createTestEditor()

    e.switchToNextBuffer()
    check e.state.statusMessage == "No more buffers"

    e.switchToPrevBuffer()
    check e.state.statusMessage == "No more buffers"

suite "Editor - switchToFirstBuffer and switchToLastBuffer":
  test "Switch to first buffer":
    let e = createTestEditor()
    let testFile1 = "/tmp/moe_test_first1.txt"
    let testFile2 = "/tmp/moe_test_first2.txt"

    writeFile(testFile1, "content1")
    writeFile(testFile2, "content2")
    defer:
      removeFile(testFile1)
      removeFile(testFile2)

    discard e.editFile(testFile1)
    discard e.editFile(testFile2)

    # Now at last buffer
    check e.currentBufferIndex() == 2

    e.switchToFirstBuffer()
    check e.currentBufferIndex() == 0

  test "Switch to last buffer":
    let e = createTestEditor()
    let testFile1 = "/tmp/moe_test_last1.txt"
    let testFile2 = "/tmp/moe_test_last2.txt"

    writeFile(testFile1, "content1")
    writeFile(testFile2, "content2")
    defer:
      removeFile(testFile1)
      removeFile(testFile2)

    discard e.editFile(testFile1)
    discard e.editFile(testFile2)

    e.switchToBufferByIndex(0)
    check e.currentBufferIndex() == 0

    e.switchToLastBuffer()
    check e.currentBufferIndex() == 2

  test "Already at first buffer message":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_already_first.txt"

    writeFile(testFile, "content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToBufferByIndex(0)

    e.switchToFirstBuffer()
    check e.state.statusMessage == "Already at first buffer"

  test "Already at last buffer message":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_already_last.txt"

    writeFile(testFile, "content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    # Now at last buffer (index 1)

    e.switchToLastBuffer()
    check e.state.statusMessage == "Already at last buffer"

suite "Editor - switchToBuffer":
  test "Switch to buffer by number":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_switch_num.txt"

    writeFile(testFile, "content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToBufferByIndex(0)

    # Buffer numbers are 1-indexed in Vim
    let result = e.switchToBuffer("2")
    check result == true
    check e.currentBufferIndex() == 1

  test "Switch to buffer by filename":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_switch_name.txt"

    writeFile(testFile, "content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToBufferByIndex(0)

    let result = e.switchToBuffer("moe_test_switch_name.txt")
    check result == true
    check e.currentBufferIndex() == 1

  test "Switch to buffer by partial path":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_switch_partial.txt"

    writeFile(testFile, "content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToBufferByIndex(0)

    let result = e.switchToBuffer("moe_test_switch_partial")
    check result == true
    check e.currentBufferIndex() == 1

  test "Error when buffer number does not exist":
    let e = createTestEditor()

    let result = e.switchToBuffer("99")
    check result == false
    check e.state.statusMessage == "E86: Buffer 99 does not exist"

  test "Error when buffer name not found":
    let e = createTestEditor()

    let result = e.switchToBuffer("nonexistent_file.txt")
    check result == false
    check e.state.statusMessage == "E94: No matching buffer for nonexistent_file.txt"

suite "Editor - isBufferShared":
  test "Buffer not shared when in single window":
    let e = createTestEditor()
    let buffer = e.activeBuffer()

    # Initially, buffer is only in one window
    check e.isBufferShared(buffer) == false

  test "Buffer shared when in multiple windows":
    let e = createTestEditor()
    let buffer = e.activeBuffer()

    # Add a second window with the same buffer
    e.windowManager.windows.add(
      EditorWindow(
        buffer: buffer,
        viewport: e.viewport,
        cursor: BufferPosition(line: 0, column: 0),
        active: false,
      )
    )

    check e.isBufferShared(buffer) == true

suite "Editor - editFile":
  test "Edit existing file":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_edit_existing.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    let result = e.editFile(testFile)
    check result.isOk
    check e.buffers.len == 2
    check e.activeBuffer().filePath.isSome
    check e.activeBuffer().filePath.get == testFile

  test "Edit new file (file does not exist)":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_edit_new.txt"

    # Ensure file does not exist
    if fileExists(testFile):
      removeFile(testFile)

    let result = e.editFile(testFile)
    check result.isOk
    check e.buffers.len == 2
    check e.activeBuffer().filePath.isSome
    check e.activeBuffer().filePath.get == testFile

  test "Switch to existing buffer if already loaded":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_edit_switch.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    # Load file first time
    discard e.editFile(testFile)
    check e.buffers.len == 2

    # Switch to first buffer
    e.switchToBufferByIndex(0)
    check e.currentBufferIndex() == 0

    # Edit same file again - should switch to existing buffer, not create new
    discard e.editFile(testFile)
    check e.buffers.len == 2
    check e.currentBufferIndex() == 1

suite "Editor - Display toggle functions":
  test "Toggle status line visibility":
    let e = createTestEditor()

    let initial = e.state.display.showStatusLine
    e.toggleStatusLine()
    check e.state.display.showStatusLine == not initial

    e.toggleStatusLine()
    check e.state.display.showStatusLine == initial

  test "Set status line visibility":
    let e = createTestEditor()

    e.setStatusLineVisible(false)
    check e.state.display.showStatusLine == false

    e.setStatusLineVisible(true)
    check e.state.display.showStatusLine == true

  test "Toggle line count visibility":
    let e = createTestEditor()

    let initial = e.state.display.showLineCount
    e.toggleLineCount()
    check e.state.display.showLineCount == not initial

  test "Toggle line percentage visibility":
    let e = createTestEditor()

    let initial = e.state.display.showLinePercentage
    e.toggleLinePercentage()
    check e.state.display.showLinePercentage == not initial

  test "Toggle encoding visibility":
    let e = createTestEditor()

    let initial = e.state.display.showEncoding
    e.toggleEncoding()
    check e.state.display.showEncoding == not initial

  test "Toggle line wrap":
    let e = createTestEditor()

    let initial = e.state.display.lineWrap
    e.toggleLineWrap()
    check e.state.display.lineWrap == not initial
    check e.state.needsFullRedraw == true

  test "Set line wrap":
    let e = createTestEditor()

    e.setLineWrap(false)
    check e.state.display.lineWrap == false

    e.setLineWrap(true)
    check e.state.display.lineWrap == true

  test "Toggle multi status line":
    let e = createTestEditor()

    let initial = e.state.display.multiStatusLine
    e.toggleMultiStatusLine()
    check e.state.display.multiStatusLine == not initial

  test "Toggle sidebar visibility":
    let e = createTestEditor()

    let initial = e.state.display.showSidebar
    e.toggleSidebar()
    check e.state.display.showSidebar == not initial

  test "Toggle syntax checker visibility":
    let e = createTestEditor()

    let initial = e.state.display.showSyntaxChecker
    e.toggleSyntaxChecker()
    check e.state.display.showSyntaxChecker == not initial

suite "Editor - Substitute preview":
  test "Start substitute preview":
    let e = createTestEditor()

    check e.state.substitutePreview.isActive == false

    e.startSubstitutePreview()
    check e.state.substitutePreview.isActive == true
    check e.state.substitutePreview.originalLines.len >= 0

  test "Cancel substitute preview restores original content":
    let e = createTestEditor()
    let buffer = e.activeBuffer()

    # Insert some content
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    e.startSubstitutePreview()

    # Modify buffer (simulate preview)
    buffer.gapBuffer.replaceLine(0, "Modified")

    e.cancelSubstitutePreview()

    check e.state.substitutePreview.isActive == false
    check buffer.getLine(0) == "Hello World"

  test "Commit substitute preview keeps changes":
    let e = createTestEditor()
    let buffer = e.activeBuffer()

    # Insert some content
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    e.startSubstitutePreview()

    # Modify buffer (simulate preview)
    buffer.gapBuffer.replaceLine(0, "Modified Content")

    e.commitSubstitutePreview()

    check e.state.substitutePreview.isActive == false
    check buffer.getLine(0) == "Modified Content"

  test "Update substitute preview applies pattern replacement":
    let e = createTestEditor()
    let buffer = e.activeBuffer()

    # Insert content with text to replace
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "foo bar foo")

    e.startSubstitutePreview()
    e.updateSubstitutePreview("foo", "baz", isGlobalFlag = true)

    check buffer.getLine(0) == "baz bar baz"

  test "Update substitute preview with non-global flag":
    let e = createTestEditor()
    let buffer = e.activeBuffer()

    # Insert content with text to replace
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "foo bar foo")

    e.startSubstitutePreview()
    e.updateSubstitutePreview("foo", "baz", isGlobalFlag = false)

    # Only first occurrence replaced
    check buffer.getLine(0) == "baz bar foo"

suite "Editor - newEditor":
  test "Create editor with default config":
    let e = createTestEditor()

    check e.buffers.len == 1
    check e.windowManager.windows.len == 1
    check e.windowManager.activeWindowIndex == 0

  test "Editor has initial empty buffer":
    let e = createTestEditor()

    check e.textBuffer != nil
    check e.textBuffer.len >= 1

  test "Editor state is properly initialized":
    let e = createTestEditor()

    check e.state.mode == EditorMode.Normal
    check e.state.cursor.line == 0
    check e.state.cursor.column == 0

  test "Editor with validation errors shows status message":
    let config = newEditorConfig()
    var vr = newValidationResult()
    vr.addError("test", "invalid_value", "valid_value")

    let e = newEditor(config, vr)

    check "Config error" in e.state.statusMessage

suite "Editor - Window bufferList (per-window tabs)":
  test "Initial window has bufferList with initial buffer":
    let e = createTestEditor()

    check e.activeWindow.bufferList.len == 1
    check e.activeWindow.bufferList[0] == e.textBuffer

  test "addBufferToWindowList adds buffer to window's list":
    let e = createTestEditor()
    let newBuffer = newTextBuffer()

    e.addBufferToWindowList(newBuffer)

    check e.activeWindow.bufferList.len == 2
    check e.activeWindow.bufferList[1] == newBuffer

  test "addBufferToWindowList does not add duplicate buffer":
    let e = createTestEditor()
    let existingBuffer = e.textBuffer

    e.addBufferToWindowList(existingBuffer)

    check e.activeWindow.bufferList.len == 1

  test "editFile adds buffer to window's bufferList":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_window_edit.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    check e.activeWindow.bufferList.len == 2
    check e.activeWindow.buffer == e.activeWindow.bufferList[1]

  test "windowBufferIndex returns correct index":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_window_index.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    check e.windowBufferIndex() == 1

    e.switchToWindowBuffer(0)
    check e.windowBufferIndex() == 0

  test "switchToWindowBuffer switches within window's bufferList":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_switch_window.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToWindowBuffer(0)

    check e.activeWindow.buffer == e.activeWindow.bufferList[0]

  test "switchToNextBuffer cycles through window's bufferList":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_next_window.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToWindowBuffer(0)

    e.switchToNextBuffer()
    check e.windowBufferIndex() == 1

    e.switchToNextBuffer()
    check e.windowBufferIndex() == 0 # Wraps around

  test "switchToPrevBuffer cycles through window's bufferList":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_prev_window.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    e.switchToPrevBuffer()
    check e.windowBufferIndex() == 0

    e.switchToPrevBuffer()
    check e.windowBufferIndex() == 1 # Wraps around

suite "Editor - Window bufferList with splits":
  test "vsplit creates new window with only current buffer":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_vsplit_buflist.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    # Open file in first window
    discard e.editFile(testFile)
    check e.activeWindow.bufferList.len == 2

    # Create vsplit
    discard e.vsplit()

    # New window should only have the current buffer
    check e.activeWindow.bufferList.len == 1

  test "hsplit creates new window with only current buffer":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_hsplit_buflist.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    # Open file in first window
    discard e.editFile(testFile)
    check e.activeWindow.bufferList.len == 2

    # Create hsplit
    discard e.hsplit()

    # New window should only have the current buffer
    check e.activeWindow.bufferList.len == 1

  test "Windows have independent bufferLists":
    let e = createTestEditor()
    let testFile1 = "/tmp/moe_test_indep1.txt"
    let testFile2 = "/tmp/moe_test_indep2.txt"

    writeFile(testFile1, "content1")
    writeFile(testFile2, "content2")
    defer:
      removeFile(testFile1)
      removeFile(testFile2)

    # Open file in first window
    discard e.editFile(testFile1)
    let window1BufferCount = e.activeWindow.bufferList.len

    # Create vsplit and open different file
    discard e.vsplit()
    discard e.editFile(testFile2)

    # Window 2 should have 2 buffers now
    let window2 = e.activeWindow
    check window2.bufferList.len == 2

    # Switch back to window 1 and verify its bufferList is unchanged
    e.switchToPrevWindow()
    check e.activeWindow.bufferList.len == window1BufferCount

suite "Editor - enew with window bufferList":
  test "enew adds new buffer to window's bufferList":
    let e = createTestEditor()
    let initialCount = e.activeWindow.bufferList.len

    discard e.enew()

    check e.activeWindow.bufferList.len == initialCount + 1
    check e.activeWindow.buffer == e.activeWindow.bufferList[^1]

suite "Editor - switchToFirstBuffer and switchToLastBuffer with bufferList":
  test "switchToFirstBuffer uses window's bufferList":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_first_buflist.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    check e.windowBufferIndex() == 1

    e.switchToFirstBuffer()
    check e.windowBufferIndex() == 0

  test "switchToLastBuffer uses window's bufferList":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_last_buflist.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToWindowBuffer(0)
    check e.windowBufferIndex() == 0

    e.switchToLastBuffer()
    check e.windowBufferIndex() == 1

  test "switchToFirstBuffer with single buffer shows message":
    let e = createTestEditor()
    check e.activeWindow.bufferList.len == 1

    e.switchToFirstBuffer()
    check "Already at first buffer" in e.state.statusMessage

  test "switchToLastBuffer with single buffer shows message":
    let e = createTestEditor()
    check e.activeWindow.bufferList.len == 1

    e.switchToLastBuffer()
    check "Already at last buffer" in e.state.statusMessage

suite "Editor - switchToBufferByIndex adds to window bufferList":
  test "switchToBufferByIndex adds buffer to window's bufferList":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_switch_add.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    # Add buffer to global list via editFile
    discard e.editFile(testFile)

    # Create a split (new window has e.textBuffer which is the initial buffer)
    # Note: vsplit uses e.textBuffer, not activeWindow.buffer
    discard e.vsplit()
    check e.activeWindow.bufferList.len == 1
    check e.activeWindow.buffer == e.textBuffer # Initial buffer

    # Switch to buffer index 1 (testFile buffer) - should add to window's bufferList
    e.switchToBufferByIndex(1)
    check e.activeWindow.bufferList.len == 2

  test "switchToBufferByIndex does not duplicate in bufferList":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_switch_nodup.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    let bufferListLen = e.activeWindow.bufferList.len

    # Switch to same buffer again
    e.switchToBufferByIndex(1)
    check e.activeWindow.bufferList.len == bufferListLen

suite "Editor - Edge cases with single buffer":
  test "switchToNextBuffer with single buffer shows message":
    let e = createTestEditor()
    check e.activeWindow.bufferList.len == 1

    e.switchToNextBuffer()
    check "No more buffers" in e.state.statusMessage

  test "switchToPrevBuffer with single buffer shows message":
    let e = createTestEditor()
    check e.activeWindow.bufferList.len == 1

    e.switchToPrevBuffer()
    check "No more buffers" in e.state.statusMessage

suite "Editor - applyConfigSettings syncs display state":
  test "Syncs showLineNumbers from config.standard.number":
    let e = createTestEditor()

    e.config.standard.number = false
    e.applyConfigSettings(e.config)
    check e.state.display.showLineNumbers == false

    e.config.standard.number = true
    e.applyConfigSettings(e.config)
    check e.state.display.showLineNumbers == true

  test "Syncs showStatusLine from config.standard.statusLine":
    let e = createTestEditor()

    e.config.standard.statusLine = false
    e.applyConfigSettings(e.config)
    check e.state.display.showStatusLine == false

    e.config.standard.statusLine = true
    e.applyConfigSettings(e.config)
    check e.state.display.showStatusLine == true

  test "Syncs tabStop from config.standard.tabStop":
    let e = createTestEditor()

    e.config.standard.tabStop = 8
    e.applyConfigSettings(e.config)
    check e.state.display.tabStop == 8

    e.config.standard.tabStop = 4
    e.applyConfigSettings(e.config)
    check e.state.display.tabStop == 4

  test "Syncs showSyntax from config.standard.syntax":
    let e = createTestEditor()

    e.config.standard.syntax = false
    e.applyConfigSettings(e.config)
    check e.state.display.showSyntax == false

  test "Syncs showIndentationLines from config.standard.indentationLines":
    let e = createTestEditor()

    e.config.standard.indentationLines = true
    e.applyConfigSettings(e.config)
    check e.state.display.showIndentationLines == true

  test "Syncs showSidebar from config.standard.sidebar":
    let e = createTestEditor()

    e.config.standard.sidebar = true
    e.applyConfigSettings(e.config)
    check e.state.display.showSidebar == true

  test "Syncs expandTab from config.standard.expandTab":
    let e = createTestEditor()

    e.config.standard.expandTab = false
    e.applyConfigSettings(e.config)
    check e.state.display.expandTab == false

  test "Syncs autoIndent from config.standard.autoIndent":
    let e = createTestEditor()

    e.config.standard.autoIndent = false
    e.applyConfigSettings(e.config)
    check e.state.display.autoIndent == false

  test "Syncs autoCloseParen from config.standard.autoCloseParen":
    let e = createTestEditor()

    e.config.standard.autoCloseParen = true
    e.applyConfigSettings(e.config)
    check e.state.display.autoCloseParen == true

  test "Syncs autoDeleteParen from config.standard.autoDeleteParen":
    let e = createTestEditor()

    e.config.standard.autoDeleteParen = true
    e.applyConfigSettings(e.config)
    check e.state.display.autoDeleteParen == true

  test "Syncs search settings from config":
    let e = createTestEditor()

    e.config.standard.ignorecase = false
    e.config.standard.smartcase = false
    e.config.standard.incrementalSearch = false
    e.applyConfigSettings(e.config)

    check e.state.search.ignorecase == false
    check e.state.search.smartcase == false
    check e.state.search.incsearch == false

suite "Editor - Config mode changes sync to display via applyConfigSettings":
  test "Config mode toggle number syncs to display":
    let e = createTestEditor()
    let configState = newConfigModeState(e.config)

    # Find the "number" bool item
    for i, item in configState.items:
      if item.kind == cvkBool and item.displayName == "number":
        configState.selectedIndex = i
        break

    let originalDisplay = e.state.display.showLineNumbers

    # Toggle in config mode (updates EditorConfig)
    configState.toggleBoolValue()
    check e.config.standard.number == not originalDisplay

    # Simulate what handleEvent now does for config mode
    e.applyConfigSettings(e.config)
    check e.state.display.showLineNumbers == not originalDisplay

  test "Config mode toggle statusLine syncs to display":
    let e = createTestEditor()
    let configState = newConfigModeState(e.config)

    for i, item in configState.items:
      if item.kind == cvkBool and item.displayName == "statusLine":
        configState.selectedIndex = i
        break

    let original = e.state.display.showStatusLine

    configState.toggleBoolValue()
    e.applyConfigSettings(e.config)
    check e.state.display.showStatusLine == not original

  test "Config mode change tabStop syncs to display":
    let e = createTestEditor()
    let configState = newConfigModeState(e.config)

    for i, item in configState.items:
      if item.kind == cvkInt and item.displayName == "tabStop":
        configState.selectedIndex = i
        break

    let original = e.state.display.tabStop

    configState.incrementIntValue()
    e.applyConfigSettings(e.config)
    check e.state.display.tabStop == original + 1

  test "Config mode toggle syntax syncs to display":
    let e = createTestEditor()
    let configState = newConfigModeState(e.config)

    for i, item in configState.items:
      if item.kind == cvkBool and item.displayName == "syntax":
        configState.selectedIndex = i
        break

    let original = e.state.display.showSyntax

    configState.toggleBoolValue()
    e.applyConfigSettings(e.config)
    check e.state.display.showSyntax == not original

  test "Config mode toggle sidebar syncs to display":
    let e = createTestEditor()
    let configState = newConfigModeState(e.config)

    for i, item in configState.items:
      if item.kind == cvkBool and item.displayName == "sidebar":
        configState.selectedIndex = i
        break

    let original = e.state.display.showSidebar

    configState.toggleBoolValue()
    e.applyConfigSettings(e.config)
    check e.state.display.showSidebar == not original
