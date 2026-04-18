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
import
  ../src/moepkg/
    [editor, buffer, config, config_loader, config_mode, highlight, window_manager]
import ../src/moepkg/command_handlers/command_mode_handler
import ../src/moepkg/buffer_backends/gap_buffer

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

  test "Edit new file detects language from extension":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_new_lang.nim"

    if fileExists(testFile):
      removeFile(testFile)

    let result = e.editFile(testFile)
    check result.isOk
    check e.activeBuffer().language == SourceLanguage.langNim

  test "Edit new file detects language for various extensions":
    let e = createTestEditor()

    let cases = [
      ("/tmp/moe_test_new.py", SourceLanguage.langPython),
      ("/tmp/moe_test_new.rs", SourceLanguage.langRust),
      ("/tmp/moe_test_new.js", SourceLanguage.langJavaScript),
      ("/tmp/moe_test_new.ts", SourceLanguage.langTypeScript),
      ("/tmp/moe_test_new.c", SourceLanguage.langC),
      ("/tmp/moe_test_new.cpp", SourceLanguage.langCpp),
      ("/tmp/moe_test_new.md", SourceLanguage.langMarkdown),
      ("/tmp/moe_test_new.sh", SourceLanguage.langShell),
    ]

    for (path, expectedLang) in cases:
      if fileExists(path):
        removeFile(path)
      let r = e.editFile(path)
      check r.isOk
      check e.activeBuffer().language == expectedLang

  test "Edit new file with unknown extension has langNone":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_new.xyz"

    if fileExists(testFile):
      removeFile(testFile)

    let result = e.editFile(testFile)
    check result.isOk
    check e.activeBuffer().language == SourceLanguage.langNone

  test "Edit existing file also detects language":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_existing_lang.nim"

    writeFile(testFile, "echo \"hello\"")
    defer:
      removeFile(testFile)

    let result = e.editFile(testFile)
    check result.isOk
    check e.activeBuffer().language == SourceLanguage.langNim

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

suite "Startup window - FileTree":
  ## These tests simulate handleStartUpWindows: viewport height is set to
  ## termHeight - CommandLineHeight (reserving the command line row) and
  ## screenSize is synced so no ratio-based resizeWindows runs afterward.

  test "FileTree opens with correct layout":
    let config = newEditorConfig()
    config.startUpFileTree.enable = true
    let e = newEditor(config, newValidationResult())

    const
      termWidth = 120
      termHeight = 40
      viewportHeight = termHeight - CommandLineHeight

    let win = e.activeWindow
    win.viewport.width = termWidth
    win.viewport.height = viewportHeight

    e.toggleFileTree(none(string), e.activeBuffer())

    check e.windowManager.windows.len == 2

    let ftWin = e.windowManager.windows[0]
    let edWin = e.windowManager.windows[1]

    # FileTree window
    check ftWin.mode == EditorMode.FileTree
    check ftWin.viewport.x == 0
    check ftWin.viewport.width == config.fileTree.width
    check ftWin.viewport.height == viewportHeight

    # Editor window fills remaining space
    check edWin.viewport.x == config.fileTree.width + WindowSeparatorWidth
    check edWin.viewport.width ==
      termWidth - config.fileTree.width - WindowSeparatorWidth
    check edWin.viewport.height == viewportHeight

    # No gap between fileTree and editor
    check ftWin.viewport.x + ftWin.viewport.width + WindowSeparatorWidth ==
      edWin.viewport.x

    # Total width covers entire terminal
    check edWin.viewport.x + edWin.viewport.width == termWidth

    # Command line row is reserved (viewport does not extend to last row)
    check ftWin.viewport.y + ftWin.viewport.height < termHeight
    check edWin.viewport.y + edWin.viewport.height < termHeight

  test "FileTree does not open when disabled":
    let config = newEditorConfig()
    config.startUpFileTree.enable = false
    let e = newEditor(config, newValidationResult())

    check e.windowManager.windows.len == 1

  test "startUpWindowsDone flag prevents double execution":
    let config = newEditorConfig()
    config.startUpFileTree.enable = true
    let e = newEditor(config, newValidationResult())

    const
      termWidth = 120
      termHeight = 40
      viewportHeight = termHeight - CommandLineHeight

    let win = e.activeWindow
    win.viewport.width = termWidth
    win.viewport.height = viewportHeight

    e.toggleFileTree(none(string), e.activeBuffer())
    e.state.startUpWindowsDone = true

    # Calling again closes (true toggle), so back to 1 window
    e.toggleFileTree(none(string), e.activeBuffer())
    check e.windowManager.windows.len == 1

  test "FileTree layout with custom width":
    let config = newEditorConfig()
    config.startUpFileTree.enable = true
    config.fileTree.width = 50
    let e = newEditor(config, newValidationResult())

    const
      termWidth = 200
      termHeight = 50
      viewportHeight = termHeight - CommandLineHeight

    let win = e.activeWindow
    win.viewport.width = termWidth
    win.viewport.height = viewportHeight

    e.toggleFileTree(none(string), e.activeBuffer())

    check e.windowManager.windows.len == 2

    let ftWin = e.windowManager.windows[0]
    let edWin = e.windowManager.windows[1]

    check ftWin.viewport.width == 50
    check edWin.viewport.x == 50 + WindowSeparatorWidth
    check edWin.viewport.width == termWidth - 50 - WindowSeparatorWidth

    # No gap
    check edWin.viewport.x + edWin.viewport.width == termWidth

    # Command line row is reserved
    check ftWin.viewport.y + ftWin.viewport.height < termHeight
    check edWin.viewport.y + edWin.viewport.height < termHeight

  test "toggleFileTree closes when already open":
    ## Calling toggleFileTree when fileTree is already open should close it.
    ## Calling a third time should reopen it.
    let config = newEditorConfig()
    let e = newEditor(config, newValidationResult())

    const
      termWidth = 120
      termHeight = 40
      viewportHeight = termHeight - CommandLineHeight

    let win = e.activeWindow
    win.viewport.width = termWidth
    win.viewport.height = viewportHeight

    # 1st call: Open fileTree
    e.toggleFileTree(none(string), e.activeBuffer())
    check e.windowManager.windows.len == 2
    check e.windowManager.windows[0].mode == EditorMode.FileTree

    # 2nd call: Should close
    e.toggleFileTree(none(string), e.activeBuffer())
    check e.windowManager.windows.len == 1

    # 3rd call: Should reopen
    e.toggleFileTree(none(string), e.activeBuffer())
    check e.windowManager.windows.len == 2
    check e.windowManager.windows[0].mode == EditorMode.FileTree

  test "Single window startup reserves command line":
    ## Without fileTree, handleStartUpWindows still reserves the command line.
    let config = newEditorConfig()
    let e = newEditor(config, newValidationResult())

    const
      termWidth = 160
      termHeight = 48
      viewportHeight = termHeight - CommandLineHeight

    let win = e.activeWindow
    win.viewport.width = termWidth
    win.viewport.height = viewportHeight

    check e.windowManager.windows.len == 1
    check win.viewport.height == viewportHeight
    check win.viewport.y + win.viewport.height < termHeight

  test "toggleFileTree with vsplit distributes width to all windows":
    ## When 2 windows exist via vsplit, opening filetree should redistribute
    ## width across all windows, not just shrink the active one.
    let config = newEditorConfig()
    let e = newEditor(config, newValidationResult())

    const
      termWidth = 120
      termHeight = 40
      viewportHeight = termHeight - CommandLineHeight

    let win = e.activeWindow
    win.viewport.width = termWidth
    win.viewport.height = viewportHeight

    # Create a vertical split (2 windows)
    discard e.vsplit()
    check e.windowManager.windows.len == 2

    # Open filetree
    e.toggleFileTree(none(string), e.activeBuffer())
    check e.windowManager.windows.len == 3

    let ftWin = e.windowManager.windows[0]
    let win1 = e.windowManager.windows[1]
    let win2 = e.windowManager.windows[2]

    # FileTree has fixed width
    check ftWin.mode == EditorMode.FileTree
    check ftWin.viewport.width == config.fileTree.width

    # Both editor windows should have equal width
    check win1.viewport.width == win2.viewport.width

    # No gaps: windows are contiguous
    check ftWin.viewport.x + ftWin.viewport.width + WindowSeparatorWidth ==
      win1.viewport.x
    check win1.viewport.x + win1.viewport.width + WindowSeparatorWidth == win2.viewport.x

    # Total width covers entire terminal
    check win2.viewport.x + win2.viewport.width == termWidth

  test "toggleFileTree with multiple vsplits distributes evenly":
    ## With 3 windows via vsplit, filetree should give equal width to all 3.
    let config = newEditorConfig()
    let e = newEditor(config, newValidationResult())

    const
      termWidth = 160
      termHeight = 40
      viewportHeight = termHeight - CommandLineHeight

    let win = e.activeWindow
    win.viewport.width = termWidth
    win.viewport.height = viewportHeight

    # Create 3 editor windows
    discard e.vsplit()
    discard e.vsplit()
    check e.windowManager.windows.len == 3

    # Open filetree
    e.toggleFileTree(none(string), e.activeBuffer())
    check e.windowManager.windows.len == 4

    let ftWin = e.windowManager.windows[0]

    # FileTree has fixed width
    check ftWin.mode == EditorMode.FileTree
    check ftWin.viewport.width == config.fileTree.width

    # All 3 editor windows should have approximately equal width
    # (last window absorbs integer division remainder, so allow diff of 1)
    let edWin1 = e.windowManager.windows[1]
    let edWin2 = e.windowManager.windows[2]
    let edWin3 = e.windowManager.windows[3]
    check edWin1.viewport.width == edWin2.viewport.width
    check abs(edWin2.viewport.width - edWin3.viewport.width) <= 1

    # No gaps between filetree and first editor window
    check ftWin.viewport.x + ftWin.viewport.width + WindowSeparatorWidth ==
      edWin1.viewport.x
    check edWin1.viewport.x + edWin1.viewport.width + WindowSeparatorWidth ==
      edWin2.viewport.x

    # Last window extends to terminal edge (absorbs remainder)
    check edWin3.viewport.x + edWin3.viewport.width == termWidth

  test "toggleFileTree with hsplit spans full height and adjusts all rows":
    ## When windows are split horizontally (sp), filetree should span the full
    ## height and shrink windows in both rows.
    let config = newEditorConfig()
    let e = newEditor(config, newValidationResult())

    const
      termWidth = 120
      termHeight = 40
      viewportHeight = termHeight - CommandLineHeight

    let win = e.activeWindow
    win.viewport.width = termWidth
    win.viewport.height = viewportHeight

    # Create a horizontal split (top and bottom)
    discard e.hsplit()
    check e.windowManager.windows.len == 2

    let topY = e.windowManager.windows[0].viewport.y
    let bottomY = e.windowManager.windows[1].viewport.y
    check topY != bottomY

    # Open filetree
    e.toggleFileTree(none(string), e.activeBuffer())
    check e.windowManager.windows.len == 3

    let ftWin = e.windowManager.windows[0]
    check ftWin.mode == EditorMode.FileTree
    check ftWin.viewport.width == config.fileTree.width

    # FileTree spans full height (top of topmost to bottom of bottommost)
    let topWin = e.windowManager.windows[1]
    let bottomWin = e.windowManager.windows[2]
    check ftWin.viewport.y == min(topWin.viewport.y, bottomWin.viewport.y)
    check ftWin.viewport.height ==
      max(
        topWin.viewport.y + topWin.viewport.height,
        bottomWin.viewport.y + bottomWin.viewport.height,
      ) - ftWin.viewport.y

    # Both editor windows should be shifted right
    check topWin.viewport.x == config.fileTree.width + WindowSeparatorWidth
    check bottomWin.viewport.x == config.fileTree.width + WindowSeparatorWidth

    # Both editor windows fill remaining width
    check topWin.viewport.x + topWin.viewport.width == termWidth
    check bottomWin.viewport.x + bottomWin.viewport.width == termWidth

  test "toggleFileTree with hsplit+vsplit adjusts all windows":
    ## Mixed splits: hsplit then vsplit in top row. FileTree should span full
    ## height and redistribute widths in both rows.
    let config = newEditorConfig()
    let e = newEditor(config, newValidationResult())

    const
      termWidth = 120
      termHeight = 40
      viewportHeight = termHeight - CommandLineHeight

    let win = e.activeWindow
    win.viewport.width = termWidth
    win.viewport.height = viewportHeight

    # hsplit → 2 windows (top, bottom)
    discard e.hsplit()
    check e.windowManager.windows.len == 2

    # vsplit in top window → 3 windows total
    # Make top window active
    e.windowManager.activateWindow(0)
    e.syncActiveWindow()
    discard e.vsplit()
    check e.windowManager.windows.len == 3

    # Open filetree
    e.toggleFileTree(none(string), e.activeBuffer())
    check e.windowManager.windows.len == 4

    let ftWin = e.windowManager.windows[0]
    check ftWin.mode == EditorMode.FileTree
    check ftWin.viewport.width == config.fileTree.width

    # All editor windows should start after filetree
    for i in 1 ..< e.windowManager.windows.len:
      check e.windowManager.windows[i].viewport.x >=
        config.fileTree.width + WindowSeparatorWidth

    # Last window in each row extends to terminal edge
    for i in 1 ..< e.windowManager.windows.len:
      let w = e.windowManager.windows[i]
      # Check that window + anything to its right fills to termWidth
      var isLastInRow = true
      for j in 1 ..< e.windowManager.windows.len:
        if j != i and e.windowManager.windows[j].viewport.y == w.viewport.y and
            e.windowManager.windows[j].viewport.x > w.viewport.x:
          isLastInRow = false
          break
      if isLastInRow:
        check w.viewport.x + w.viewport.width == termWidth

suite "Editor - lspForcePopup":
  test "lspForcePopup routes all messages to popup with correct levels":
    let e = createTestEditor()
    e.config.notification.lspForcePopup = true

    # Simulate LSP messages via pendingMessages
    e.lsp.pendingMessages.add("[LSP Error] nim: something failed")
    e.lsp.pendingMessages.add("[LSP Warning] nim: deprecation notice")
    e.lsp.pendingMessages.add("[LSP Info] nim: server ready")
    e.lsp.pendingMessages.add("[LSP Log] nim: trace data")

    e.tick()

    check e.state.notificationPopup.queue.len == 4
    check e.state.notificationPopup.queue[0].level == nlError
    check e.state.notificationPopup.queue[1].level == nlWarning
    check e.state.notificationPopup.queue[2].level == nlInfo
    check e.state.notificationPopup.queue[3].level == nlInfo

  test "lspForcePopup disabled falls back to normal notify":
    let e = createTestEditor()
    e.config.notification.lspForcePopup = false
    e.config.notification.screenNotifications = true
    e.config.notification.lspScreenNotify = true
    e.config.notification.popupNotifications = false

    e.lsp.pendingMessages.add("[LSP Error] nim: something failed")

    e.tick()

    # Should go to statusMessage, not popup
    check e.state.notificationPopup.queue.len == 0
    check e.state.statusMessage == "[LSP Error] nim: something failed"

suite "Editor - openFileInNewRightWindow":
  proc setupLoneFileTree(termWidth: int = 120, termHeight: int = 40): Editor =
    ## Set up an editor where the FileTree is the only window.
    let config = newEditorConfig()
    let e = newEditor(config, newValidationResult())

    let viewportHeight = termHeight - CommandLineHeight
    let win = e.activeWindow
    win.viewport.width = termWidth
    win.viewport.height = viewportHeight

    # Open fileTree (creates [FileTree, editor])
    e.toggleFileTree(none(string), e.activeBuffer())
    doAssert e.windowManager.windows.len == 2

    # Close the editor window, leaving only the FileTree
    e.windowManager.activateWindow(1)
    discard e.closeWindow()
    doAssert e.windowManager.windows.len == 1
    doAssert e.activeWindow.mode == EditorMode.FileTree

    return e

  test "opens new window on the right of FileTree":
    const
      termWidth = 120
      termHeight = 40
    let e = setupLoneFileTree(termWidth, termHeight)
    let ftWidth = e.config.fileTree.width

    let testFile = "/tmp/moe_test_open_right.txt"
    writeFile(testFile, "hello right window")
    defer:
      removeFile(testFile)

    let r = e.openFileInNewRightWindow(testFile)
    check r.isOk

    check e.windowManager.windows.len == 2
    let ftWin = e.windowManager.windows[0]
    let newWin = e.windowManager.windows[1]

    check ftWin.mode == EditorMode.FileTree
    check ftWin.viewport.width == ftWidth

    check newWin.mode == EditorMode.Normal
    check newWin.viewport.x == ftWidth + WindowSeparatorWidth
    check newWin.viewport.width == termWidth - ftWidth - WindowSeparatorWidth
    check newWin.viewport.y == ftWin.viewport.y
    check newWin.viewport.height == ftWin.viewport.height

    # No gap; total width covers entire terminal
    check newWin.viewport.x + newWin.viewport.width == termWidth

    # New window is active and contains the loaded file
    check e.windowManager.activeWindowIndex == 1
    check newWin.buffer.filePath.isSome
    check newWin.buffer.filePath.get == testFile

    # Per-window bufferList contains only the new buffer
    check newWin.bufferList.len == 1
    check newWin.bufferList[0] == newWin.buffer

  test "reuses existing buffer when file is already loaded":
    let e = setupLoneFileTree()

    let testFile = "/tmp/moe_test_open_right_reuse.txt"
    writeFile(testFile, "reused")
    defer:
      removeFile(testFile)

    # Pre-load the file into the global buffer list via loadOrCreateBuffer
    # (no window created yet)
    let preloadResult = e.loadOrCreateBuffer(testFile)
    check preloadResult.isOk
    let preloadedBuffer = preloadResult.get
    let bufferCountAfterPreload = e.buffers.len

    # Opening the preloaded file should reuse the buffer, not create a new one
    let r = e.openFileInNewRightWindow(testFile)
    check r.isOk
    check e.buffers.len == bufferCountAfterPreload
    check e.activeWindow.buffer == preloadedBuffer
    check e.activeWindow.buffer.filePath.isSome
    check e.activeWindow.buffer.filePath.get == testFile

  test "creates new file buffer when path does not exist":
    let e = setupLoneFileTree()

    let newPath = "/tmp/moe_test_open_right_new_file_does_not_exist.txt"
    # Ensure it really doesn't exist
    if fileExists(newPath):
      removeFile(newPath)
    defer:
      if fileExists(newPath):
        removeFile(newPath)

    let r = e.openFileInNewRightWindow(newPath)
    check r.isOk

    let newWin = e.windowManager.windows[1]
    check newWin.buffer.filePath.isSome
    check newWin.buffer.filePath.get == newPath

  test "returns error when active window is not FileTree":
    let e = createTestEditor()
    # Default single window is Normal mode
    check e.activeWindow.mode == EditorMode.Normal

    let r = e.openFileInNewRightWindow("/tmp/moe_test_open_right_not_ft.txt")
    check r.isErr
    # Still only one window
    check e.windowManager.windows.len == 1

  test "returns error when there is not enough space":
    # Make the FileTree fill the width such that no room remains for a split
    let e = setupLoneFileTree()
    let ftWin = e.activeWindow
    # Force the filetree's fixed width to equal the full viewport width so
    # there's no space left on the right
    ftWin.fixedWidth = some(ftWin.viewport.width)

    let testFile = "/tmp/moe_test_open_right_nospace.txt"
    writeFile(testFile, "nospace")
    defer:
      removeFile(testFile)

    let r = e.openFileInNewRightWindow(testFile)
    check r.isErr
    check e.windowManager.windows.len == 1
