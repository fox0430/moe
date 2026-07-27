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

import std/[unittest, os, options, strutils, monotimes, times, tables]
import pkg/results
import
  ../src/moepkg/[
    editor, buffer, config, config_loader, config_mode, highlight, window_manager,
    render_utils, lsp_service, lsp_integration, diff_viewer, setting_options,
    editor_init, command_config, command_registry, help_viewer,
  ]
import ../src/moepkg/buffer_backends/gap_buffer
import
  ../src/moepkg/command_handlers/
    [command_mode_handler, handler_result, result_processor]

proc createTestEditor(): Editor =
  ## Create a minimal editor for testing
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

suite "Editor - git cache refresh gating":
  ## The tick must not run a git lookup for a readout the user turned off:
  ## a diff spawns a subprocess and a branch lookup blocks on `git rev-parse`.
  proc editorOnFile(): Editor =
    result = createTestEditor()
    result.activeBuffer.filePath = some(getTempDir() / "moe_no_repo" / "a.txt")
    result.showStatusLine = true

  test "branch is not refreshed when no readout shows it":
    let e = editorOnFile()
    e.showGitDiff = true # gutter only: needs the diff, not the branch
    e.config.statusLine.gitBranchName = false
    e.config.statusLine.setupText = ""

    e.tick()

    check e.state.git.branchEntries.len == 0
    check e.state.git.diffEntries.len == 1

  test "branch is refreshed when the status line shows it":
    let e = editorOnFile()
    e.config.statusLine.gitBranchName = true
    e.config.statusLine.setupText = ""

    e.tick()

    check e.state.git.branchEntries.len == 1

  test "a setupText placeholder is enough to refresh":
    let e = editorOnFile()
    e.showGitDiff = false
    e.config.statusLine.gitBranchName = false
    e.config.statusLine.gitChangedLines = false
    e.config.statusLine.setupText = "{filename} {gitBranch}"

    e.tick()

    check e.state.git.branchEntries.len == 1
    check e.state.git.diffEntries.len == 0

  test "no git lookup at all when every readout is off":
    let e = editorOnFile()
    e.showGitDiff = false
    e.config.statusLine.gitBranchName = false
    e.config.statusLine.gitChangedLines = false
    e.config.statusLine.setupText = ""

    e.tick()

    check e.state.git.branchEntries.len == 0
    check e.state.git.diffEntries.len == 0

suite "Editor - findBufferByPath":
  test "Find buffer by absolute path":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_find_buffer.txt"

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
    let testFile1 = getTempDir() / "moe_test_index1.txt"
    let testFile2 = getTempDir() / "moe_test_index2.txt"

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
    let testFile = getTempDir() / "moe_test_switch.txt"

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
    let testFile = getTempDir() / "moe_test_next.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToBufferByIndex(0)

    e.switchToNextBuffer()
    check e.currentBufferIndex() == 1

  test "Switch to next buffer wraps around":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_wrap.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToBufferByIndex(1) # Last buffer

    e.switchToNextBuffer()
    check e.currentBufferIndex() == 0 # Wraps to first

  test "Switch to prev buffer":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_prev.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToBufferByIndex(1)

    e.switchToPrevBuffer()
    check e.currentBufferIndex() == 0

  test "Switch to prev buffer wraps around":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_prev_wrap.txt"

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
    check e.state.statusMessage == "E88: There is only one buffer"

    e.switchToPrevBuffer()
    check e.state.statusMessage == "E88: There is only one buffer"

suite "Editor - switchToFirstBuffer and switchToLastBuffer":
  test "Switch to first buffer":
    let e = createTestEditor()
    let testFile1 = getTempDir() / "moe_test_first1.txt"
    let testFile2 = getTempDir() / "moe_test_first2.txt"

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
    let testFile1 = getTempDir() / "moe_test_last1.txt"
    let testFile2 = getTempDir() / "moe_test_last2.txt"

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
    let testFile = getTempDir() / "moe_test_already_first.txt"

    writeFile(testFile, "content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToBufferByIndex(0)

    e.switchToFirstBuffer()
    check e.state.statusMessage == "Already at first buffer"

  test "Already at last buffer message":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_already_last.txt"

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
    let testFile = getTempDir() / "moe_test_switch_num.txt"

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
    let testFile = getTempDir() / "moe_test_switch_name.txt"

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
    let testFile = getTempDir() / "moe_test_switch_partial.txt"

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
    let testFile = getTempDir() / "moe_test_edit_existing.txt"

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
    let testFile = getTempDir() / "moe_test_edit_new.txt"

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
    let testFile = getTempDir() / "moe_test_new_lang.nim"

    if fileExists(testFile):
      removeFile(testFile)

    let result = e.editFile(testFile)
    check result.isOk
    check e.activeBuffer().language == SourceLanguage.langNim

  test "Edit new file detects language for various extensions":
    let e = createTestEditor()

    let cases = [
      (getTempDir() / "moe_test_new.py", SourceLanguage.langPython),
      (getTempDir() / "moe_test_new.rs", SourceLanguage.langRust),
      (getTempDir() / "moe_test_new.js", SourceLanguage.langJavaScript),
      (getTempDir() / "moe_test_new.ts", SourceLanguage.langTypeScript),
      (getTempDir() / "moe_test_new.c", SourceLanguage.langC),
      (getTempDir() / "moe_test_new.cpp", SourceLanguage.langCpp),
      (getTempDir() / "moe_test_new.md", SourceLanguage.langMarkdown),
      (getTempDir() / "moe_test_new.sh", SourceLanguage.langShell),
    ]

    for (path, expectedLang) in cases:
      if fileExists(path):
        removeFile(path)
      let r = e.editFile(path)
      check r.isOk
      check e.activeBuffer().language == expectedLang

  test "Edit new file with unknown extension has langNone":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_new.xyz"

    if fileExists(testFile):
      removeFile(testFile)

    let result = e.editFile(testFile)
    check result.isOk
    check e.activeBuffer().language == SourceLanguage.langNone

  test "Edit existing file also detects language":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_existing_lang.nim"

    writeFile(testFile, "echo \"hello\"")
    defer:
      removeFile(testFile)

    let result = e.editFile(testFile)
    check result.isOk
    check e.activeBuffer().language == SourceLanguage.langNim

  test "Switch to existing buffer if already loaded":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_edit_switch.txt"

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

suite "Editor - reloadCurrentFile cursor clamp":
  test "Clamps cursor line when the file shrank on disk":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_clamp_shrink.txt"
    writeFile(path, "line1\nline2\nline3\nline4\nline5")
    defer:
      removeFile(path)

    check e.editFile(path).isOk
    # Park the cursor near the old end, then shrink the file to a single line.
    e.cursor = BufferPosition(line: 4, column: 3)
    writeFile(path, "x")

    check e.reloadCurrentFile().isOk
    check e.activeBuffer().len == 1
    # Without the clamp the cursor would dangle at line 4 (>= buf.len).
    check e.cursor.line == 0
    check e.cursor.column == 0

  test "Clamps a dangling column when its line got shorter":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_clamp_col.txt"
    writeFile(path, "abcdefghij")
    defer:
      removeFile(path)

    check e.editFile(path).isOk
    e.cursor = BufferPosition(line: 0, column: 8)
    writeFile(path, "ab")

    check e.reloadCurrentFile().isOk
    check e.cursor.line == 0
    # Normal-mode clamp keeps the cursor on the last character, not past it.
    check e.cursor.column == 1

  test "Reload picks up .editorconfig edits (removed keys clear overrides)":
    let e = createTestEditor()
    let testDir = getTempDir() / "moe_test_reload_editorconfig"
    let path = testDir / "sample.py"
    createDir(testDir)
    defer:
      removeDir(testDir)

    writeFile(
      testDir / ".editorconfig",
      """
root = true

[*.py]
indent_style = space
indent_size = 4
""",
    )
    writeFile(path, "print('hi')\n")

    check e.editFile(path).isOk
    check e.activeBuffer.editorConfig.isSome
    check e.activeBuffer.editorConfig.get.expandTab == some(true)
    check e.state.shiftWidth == 4

    # Drop the matching section so a reload should discard the overrides.
    writeFile(
      testDir / ".editorconfig",
      """
root = true

[*.nim]
indent_style = space
""",
    )

    check e.reloadCurrentFile().isOk
    check e.activeBuffer.editorConfig.isNone
    check e.state.shiftWidth == e.config.standard.shiftWidth

suite "Editor - Display toggle functions":
  test "Toggle status line visibility":
    let e = createTestEditor()

    let initial = e.state.showStatusLine
    e.toggleStatusLine()
    check e.state.showStatusLine == not initial

    e.toggleStatusLine()
    check e.state.showStatusLine == initial

  test "Set status line visibility":
    let e = createTestEditor()

    e.setStatusLineVisible(false)
    check e.state.showStatusLine == false

    e.setStatusLineVisible(true)
    check e.state.showStatusLine == true

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

    let initial = e.state.lineWrap
    e.toggleLineWrap()
    check e.state.lineWrap == not initial

  test "Set line wrap":
    let e = createTestEditor()

    e.setLineWrap(false)
    check e.state.lineWrap == false

    e.setLineWrap(true)
    check e.state.lineWrap == true

  test "Toggle multi status line":
    let e = createTestEditor()

    let initial = e.state.multiStatusLine
    e.toggleMultiStatusLine()
    check e.state.multiStatusLine == not initial

  test "Toggle sidebar visibility":
    let e = createTestEditor()

    let initial = e.state.showSidebar
    e.toggleSidebar()
    check e.state.showSidebar == not initial

  test "Toggle syntax checker visibility":
    let e = createTestEditor()

    let initial = e.state.showSyntaxChecker
    e.toggleSyntaxChecker()
    check e.state.showSyntaxChecker == not initial

suite "Editor - Substitute preview":
  test "Start substitute preview":
    let e = createTestEditor()

    check e.state.ui.substitutePreview.isActive == false

    e.startSubstitutePreview()
    check e.state.ui.substitutePreview.isActive == true
    check e.state.ui.substitutePreview.originalLines.len >= 0

  test "Cancel substitute preview restores original content":
    let e = createTestEditor()
    let buffer = e.activeBuffer()

    # Insert some content
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    e.startSubstitutePreview()

    # Modify buffer (simulate preview)
    buffer.storage.gapBuffer.replaceLine(0, "Modified")

    e.cancelSubstitutePreview()

    check e.state.ui.substitutePreview.isActive == false
    check buffer.getLine(0) == "Hello World"

  test "Commit substitute preview keeps changes":
    let e = createTestEditor()
    let buffer = e.activeBuffer()

    # Insert some content
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    e.startSubstitutePreview()

    # Modify buffer (simulate preview)
    buffer.storage.gapBuffer.replaceLine(0, "Modified Content")

    e.commitSubstitutePreview()

    check e.state.ui.substitutePreview.isActive == false
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

  test "Start substitute preview captures cursor and viewport":
    let e = createTestEditor()
    let buffer = e.activeBuffer()

    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    e.cursor = BufferPosition(line: 0, column: 3)
    e.activeWindow.viewport.topLine = 2
    e.activeWindow.viewport.leftColumn = 5

    e.startSubstitutePreview()

    check e.state.ui.substitutePreview.originalCursor ==
      BufferPosition(line: 0, column: 3)
    check e.state.ui.substitutePreview.originalTopLine == 2
    check e.state.ui.substitutePreview.originalLeftColumn == 5

  test "Cancel substitute preview restores cursor and viewport":
    let e = createTestEditor()
    let buffer = e.activeBuffer()

    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    e.cursor = BufferPosition(line: 0, column: 2)
    e.activeWindow.viewport.topLine = 0
    e.activeWindow.viewport.leftColumn = 0

    e.startSubstitutePreview()

    # Simulate viewport/cursor moving during preview jump
    e.cursor = BufferPosition(line: 0, column: 0)
    e.activeWindow.viewport.topLine = 10
    e.activeWindow.viewport.leftColumn = 7

    e.cancelSubstitutePreview()

    check e.cursor == BufferPosition(line: 0, column: 2)
    check e.activeWindow.viewport.topLine == 0
    check e.activeWindow.viewport.leftColumn == 0

  test "findFirstSubstituteMatch finds first occurrence across lines":
    let lines = @["aaa", "bbb foo", "ccc foo ddd"]
    let match = findFirstSubstituteMatch(lines, "foo")
    check match.isSome
    check match.get == BufferPosition(line: 1, column: 4)

  test "findFirstSubstituteMatch returns none when pattern absent":
    let lines = @["aaa", "bbb", "ccc"]
    let match = findFirstSubstituteMatch(lines, "zzz")
    check match.isNone

  test "findFirstSubstituteMatch returns none for empty pattern":
    let lines = @["aaa", "bbb"]
    let match = findFirstSubstituteMatch(lines, "")
    check match.isNone

  test "jumpToFirstSubstituteMatch moves cursor to first match":
    let e = createTestEditor()
    let buffer = e.activeBuffer()

    # Build multi-line content
    discard buffer.insertText(
      BufferPosition(line: 0, column: 0), "no match here\nalso nothing\ntarget foo here"
    )

    e.cursor = BufferPosition(line: 0, column: 0)
    e.startSubstitutePreview()

    e.jumpToFirstSubstituteMatch("foo")

    check e.cursor == BufferPosition(line: 2, column: 7)

  test "restoreFromPreview clears last applied state and undoes preview":
    let e = createTestEditor()
    let buffer = e.activeBuffer()

    discard buffer.insertText(BufferPosition(line: 0, column: 0), "foo bar")

    e.startSubstitutePreview()
    e.updateSubstitutePreview("foo", "baz", isGlobalFlag = true)
    check buffer.getLine(0) == "baz bar"

    e.restoreFromPreview()
    check buffer.getLine(0) == "foo bar"
    # lastPattern/lastReplacement must be cleared so the same preview can be
    # re-applied after a restore.
    check e.state.ui.substitutePreview.lastPattern == ""
    check e.state.ui.substitutePreview.lastReplacement == ""

    e.updateSubstitutePreview("foo", "baz", isGlobalFlag = true)
    check buffer.getLine(0) == "baz bar"

  test "jumpToFirstSubstituteMatch restores cursor when no match":
    let e = createTestEditor()
    let buffer = e.activeBuffer()

    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    e.cursor = BufferPosition(line: 0, column: 4)
    e.activeWindow.viewport.topLine = 3
    e.activeWindow.viewport.leftColumn = 2

    e.startSubstitutePreview()

    # Simulate cursor moved elsewhere
    e.cursor = BufferPosition(line: 0, column: 0)
    e.activeWindow.viewport.topLine = 0
    e.activeWindow.viewport.leftColumn = 0

    e.jumpToFirstSubstituteMatch("zzz")

    check e.cursor == BufferPosition(line: 0, column: 4)
    check e.activeWindow.viewport.topLine == 3
    check e.activeWindow.viewport.leftColumn == 2

suite "Editor - newEditor":
  test "Create editor with default config":
    let e = createTestEditor()

    check e.buffers.len == 1
    check e.windowManager.windows.len == 1
    check e.windowManager.activeWindowIndex == 0

  test "Editor has initial empty buffer":
    let e = createTestEditor()

    check e.buffers[0] != nil
    check e.buffers[0].len >= 1

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

suite "Editor - Window bufferIds (per-window tabs)":
  test "Initial window has bufferIds with initial buffer":
    let e = createTestEditor()

    check e.activeWindow.bufferIds.len == 1
    check e.activeWindow.bufferIds[0] == e.buffers[0].id

  test "addBufferToWindowList adds buffer id to window's list":
    let e = createTestEditor()
    let newBuffer = newTextBuffer()
    e.addBuffer(newBuffer)

    e.addBufferToWindowList(newBuffer)

    check e.activeWindow.bufferIds.len == 2
    check e.activeWindow.bufferIds[1] == newBuffer.id

  test "addBufferToWindowList does not add duplicate buffer":
    let e = createTestEditor()
    let existingBuffer = e.buffers[0]

    e.addBufferToWindowList(existingBuffer)

    check e.activeWindow.bufferIds.len == 1

  test "editFile adds buffer to window's bufferIds":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_window_edit.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    check e.activeWindow.bufferIds.len == 2
    check e.activeWindow.bufferIds[1] == e.activeWindow.buffer.id

  test "windowBufferIndex returns correct index":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_window_index.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    check e.windowBufferIndex() == 1

    e.switchToWindowBuffer(0)
    check e.windowBufferIndex() == 0

  test "switchToWindowBuffer switches within window's bufferIds":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_switch_window.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToWindowBuffer(0)

    check e.activeWindow.buffer.id == e.activeWindow.bufferIds[0]

  test "switchToNextBuffer cycles through window's bufferIds":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_next_window.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToWindowBuffer(0)

    e.switchToNextBuffer()
    check e.windowBufferIndex() == 1

    e.switchToNextBuffer()
    check e.windowBufferIndex() == 0 # Wraps around

  test "switchToPrevBuffer cycles through window's bufferIds":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_prev_window.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    e.switchToPrevBuffer()
    check e.windowBufferIndex() == 0

    e.switchToPrevBuffer()
    check e.windowBufferIndex() == 1 # Wraps around

suite "Editor - Window bufferIds with splits":
  test "vsplit creates new window with only current buffer":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_vsplit_buflist.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    # Open file in first window
    discard e.editFile(testFile)
    check e.activeWindow.bufferIds.len == 2

    # Create vsplit
    discard e.vsplit()

    # New window should only have the current buffer
    check e.activeWindow.bufferIds.len == 1

  test "hsplit creates new window with only current buffer":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_hsplit_buflist.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    check e.activeWindow.bufferIds.len == 2

    discard e.hsplit()

    check e.activeWindow.bufferIds.len == 1

  test "Windows have independent bufferIds":
    let e = createTestEditor()
    let testFile1 = getTempDir() / "moe_test_indep1.txt"
    let testFile2 = getTempDir() / "moe_test_indep2.txt"

    writeFile(testFile1, "content1")
    writeFile(testFile2, "content2")
    defer:
      removeFile(testFile1)
      removeFile(testFile2)

    discard e.editFile(testFile1)
    let window1BufferCount = e.activeWindow.bufferIds.len

    discard e.vsplit()
    discard e.editFile(testFile2)

    # Window 2 should have 2 buffer ids now
    check e.activeWindow.bufferIds.len == 2

    # Switch back to window 1 and verify its bufferIds is unchanged
    e.switchToPrevWindow()
    check e.activeWindow.bufferIds.len == window1BufferCount

suite "Editor - enew with window bufferIds":
  test "enew adds new buffer id to window's bufferIds":
    let e = createTestEditor()
    let initialCount = e.activeWindow.bufferIds.len

    discard e.enew()

    check e.activeWindow.bufferIds.len == initialCount + 1
    check e.activeWindow.bufferIds[^1] == e.activeWindow.buffer.id

suite "Editor - switchToFirstBuffer and switchToLastBuffer with bufferIds":
  test "switchToFirstBuffer uses window's bufferIds":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_first_buflist.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    check e.windowBufferIndex() == 1

    e.switchToFirstBuffer()
    check e.windowBufferIndex() == 0

  test "switchToLastBuffer uses window's bufferIds":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_last_buflist.txt"

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
    check e.activeWindow.bufferIds.len == 1

    e.switchToFirstBuffer()
    check "Already at first buffer" in e.state.statusMessage

  test "switchToLastBuffer with single buffer shows message":
    let e = createTestEditor()
    check e.activeWindow.bufferIds.len == 1

    e.switchToLastBuffer()
    check "Already at last buffer" in e.state.statusMessage

suite "Editor - switchToBufferByIndex adds to window bufferIds":
  test "switchToBufferByIndex adds buffer id to window's bufferIds":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_switch_add.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    # Create a split: the new window shows the active buffer (testFile = buffers[1]),
    # not the stale initial buffer.
    discard e.vsplit()
    check e.activeWindow.bufferIds.len == 1
    check e.activeWindow.buffer == e.buffers[1]

    # Switch to buffer index 0 (the initial buffer) - not yet in this window's
    # tab list, so it should be added.
    e.switchToBufferByIndex(0)
    check e.activeWindow.bufferIds.len == 2

  test "switchToBufferByIndex does not duplicate in bufferIds":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_switch_nodup.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    let bufferIdsLen = e.activeWindow.bufferIds.len

    # Switch to same buffer again
    e.switchToBufferByIndex(1)
    check e.activeWindow.bufferIds.len == bufferIdsLen

suite "Editor - Edge cases with single buffer":
  test "switchToNextBuffer with single buffer shows message":
    let e = createTestEditor()
    check e.activeWindow.bufferIds.len == 1

    e.switchToNextBuffer()
    check "E88" in e.state.statusMessage

  test "switchToPrevBuffer with single buffer shows message":
    let e = createTestEditor()
    check e.activeWindow.bufferIds.len == 1

    e.switchToPrevBuffer()
    check "E88" in e.state.statusMessage

suite "Editor - applyConfigSettings syncs display state":
  test "Syncs showLineNumbers from config.standard.number":
    let e = createTestEditor()

    e.config.standard.number = false
    e.applyConfigSettings(e.config)
    check e.state.showLineNumbers == false

    e.config.standard.number = true
    e.applyConfigSettings(e.config)
    check e.state.showLineNumbers == true

  test "Syncs showStatusLine from config.standard.statusLine":
    let e = createTestEditor()

    e.config.standard.statusLine = false
    e.applyConfigSettings(e.config)
    check e.state.showStatusLine == false

    e.config.standard.statusLine = true
    e.applyConfigSettings(e.config)
    check e.state.showStatusLine == true

  test "Syncs tabStop from config.standard.tabStop":
    let e = createTestEditor()

    e.config.standard.tabStop = 8
    e.applyConfigSettings(e.config)
    check e.state.tabStop == 8

    e.config.standard.tabStop = 4
    e.applyConfigSettings(e.config)
    check e.state.tabStop == 4

  test "Syncs showSyntax from config.standard.syntax":
    let e = createTestEditor()

    e.config.standard.syntax = false
    e.applyConfigSettings(e.config)
    check e.state.showSyntax == false

  test "Syncs showDocumentHighlight from config.lsp.documentHighlight.enable":
    let e = createTestEditor()

    e.config.lsp.documentHighlight.enable = false
    e.applyConfigSettings(e.config)
    check e.state.showDocumentHighlight == false

    e.config.lsp.documentHighlight.enable = true
    e.applyConfigSettings(e.config)
    check e.state.showDocumentHighlight == true

  test "Syncs showCodeLens from config.lsp.codeLens.enable":
    let e = createTestEditor()

    e.config.lsp.codeLens.enable = true
    e.applyConfigSettings(e.config)
    check e.state.showCodeLens == true

    e.config.lsp.codeLens.enable = false
    e.applyConfigSettings(e.config)
    check e.state.showCodeLens == false

  test "Syncs showInlayHint from config.lsp.inlayHint.enable":
    let e = createTestEditor()

    e.config.lsp.inlayHint.enable = false
    e.applyConfigSettings(e.config)
    check e.state.showInlayHint == false

    e.config.lsp.inlayHint.enable = true
    e.applyConfigSettings(e.config)
    check e.state.showInlayHint == true

  test "Disabling diagnostics clears stored diagnostics and markers":
    # Diagnostics are server-push, so disabling only stops future updates;
    # the reload path must clear what was already applied.
    let e = createTestEditor()
    let buf = e.activeBuffer()
    buf.setLineMarker(0, LineMarkerKind.SyntaxError)
    buf.diagnostics.add(
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 1,
        severity: bdsError,
        message: "boom",
      )
    )

    e.config.lsp.diagnostics.enable = false
    e.applyConfigSettings(e.config)

    check buf.diagnostics.len == 0
    check buf.getLineMarker(0).isNone

  test "Syncs showIndentationLines from config.standard.indentationLines":
    let e = createTestEditor()

    e.config.standard.indentationLines = true
    e.applyConfigSettings(e.config)
    check e.state.showIndentationLines == true

  test "Syncs showSidebar from config.standard.sidebar":
    let e = createTestEditor()

    e.config.standard.sidebar = true
    e.applyConfigSettings(e.config)
    check e.state.showSidebar == true

  test "Syncs expandTab from config.standard.expandTab":
    let e = createTestEditor()

    e.config.standard.expandTab = false
    e.applyConfigSettings(e.config)
    check e.state.expandTab == false

  test "Syncs autoIndent from config.standard.autoIndent":
    let e = createTestEditor()

    e.config.standard.autoIndent = false
    e.applyConfigSettings(e.config)
    check e.state.autoIndent == false

  test "Syncs autoCloseParen from config.standard.autoCloseParen":
    let e = createTestEditor()

    e.config.standard.autoCloseParen = true
    e.applyConfigSettings(e.config)
    check e.state.autoCloseParen == true

  test "Syncs autoDeleteParen from config.standard.autoDeleteParen":
    let e = createTestEditor()

    e.config.standard.autoDeleteParen = true
    e.applyConfigSettings(e.config)
    check e.state.autoDeleteParen == true

  test "Syncs search settings from config":
    let e = createTestEditor()

    e.config.standard.ignorecase = false
    e.config.standard.smartcase = false
    e.config.standard.incrementalSearch = false
    e.applyConfigSettings(e.config)

    check e.state.input.search.ignorecase == false
    check e.state.input.search.smartcase == false
    check e.state.input.search.incsearch == false

suite "Editor - Config mode changes sync to display via applyConfigSettings":
  test "Config mode toggle number syncs to display":
    let e = createTestEditor()
    let configState = newConfigModeState(e.config)

    # Find the "number" bool item
    for i, item in configState.items:
      if item.kind == cvkBool and item.displayName == "number":
        configState.selectedIndex = i
        break

    let originalDisplay = e.state.showLineNumbers

    # Toggle in config mode (updates EditorConfig)
    configState.toggleBoolValue(e.state)
    check e.config.standard.number == not originalDisplay

    # Simulate what handleEvent now does for config mode
    e.applyConfigSettings(e.config)
    check e.state.showLineNumbers == not originalDisplay

  test "Config mode toggle statusLine syncs to display":
    let e = createTestEditor()
    let configState = newConfigModeState(e.config)

    for i, item in configState.items:
      if item.kind == cvkBool and item.displayName == "statusLine":
        configState.selectedIndex = i
        break

    let original = e.state.showStatusLine

    configState.toggleBoolValue(e.state)
    e.applyConfigSettings(e.config)
    check e.state.showStatusLine == not original

  test "Config mode change tabStop syncs to display":
    let e = createTestEditor()
    let configState = newConfigModeState(e.config)

    for i, item in configState.items:
      if item.kind == cvkInt and item.displayName == "tabStop":
        configState.selectedIndex = i
        break

    let original = e.state.tabStop

    configState.incrementIntValue(e.state)
    e.applyConfigSettings(e.config)
    check e.state.tabStop == original + 1

  test "Config mode toggle syntax syncs to display":
    let e = createTestEditor()
    let configState = newConfigModeState(e.config)

    for i, item in configState.items:
      if item.kind == cvkBool and item.displayName == "syntax":
        configState.selectedIndex = i
        break

    let original = e.state.showSyntax

    configState.toggleBoolValue(e.state)
    e.applyConfigSettings(e.config)
    check e.state.showSyntax == not original

  test "Config mode toggle sidebar syncs to display":
    let e = createTestEditor()
    let configState = newConfigModeState(e.config)

    for i, item in configState.items:
      if item.kind == cvkBool and item.displayName == "sidebar":
        configState.selectedIndex = i
        break

    let original = e.state.showSidebar

    configState.toggleBoolValue(e.state)
    e.applyConfigSettings(e.config)
    check e.state.showSidebar == not original

suite "Editor - :set ignorecase/smartcase/incsearch survive Config-mode re-apply":
  # Regression: bsoIgnoreCase/SmartCase/IncSearch used to write only the
  # `state.input.search` mirror; applyConfigSettings (run on every Config-mode
  # keystroke via pendingApply) then rolled the mirror back to the unchanged
  # `config.standard.*`, so the toggle silently vanished.
  test "hrSetBoolOption(bsoIgnoreCase) updates config, survives re-apply":
    let e = createTestEditor()
    e.config.standard.ignorecase = false
    e.state.input.search.ignorecase = false

    let r =
      HandlerResult(kind: hrSetBoolOption, boolOption: bsoIgnoreCase, boolValue: true)
    discard e.processResult(r, e.activeBuffer())
    check e.config.standard.ignorecase
    check e.state.input.search.ignorecase

    e.applyConfigSettings(e.config)
    check e.state.input.search.ignorecase

  test "hrSetBoolOption(bsoSmartCase) updates config, survives re-apply":
    let e = createTestEditor()
    e.config.standard.smartcase = false
    e.state.input.search.smartcase = false

    let r =
      HandlerResult(kind: hrSetBoolOption, boolOption: bsoSmartCase, boolValue: true)
    discard e.processResult(r, e.activeBuffer())
    check e.config.standard.smartcase
    check e.state.input.search.smartcase

    e.applyConfigSettings(e.config)
    check e.state.input.search.smartcase

  test "hrSetBoolOption(bsoIncSearch) updates config, survives re-apply":
    let e = createTestEditor()
    e.config.standard.incrementalSearch = false
    e.state.input.search.incsearch = false

    let r =
      HandlerResult(kind: hrSetBoolOption, boolOption: bsoIncSearch, boolValue: true)
    discard e.processResult(r, e.activeBuffer())
    check e.config.standard.incrementalSearch
    check e.state.input.search.incsearch

    e.applyConfigSettings(e.config)
    check e.state.input.search.incsearch

suite "Startup window - FileTree":
  ## These tests simulate handleStartUpWindows: viewport height is set to
  ## termHeight - steadyBottomAreaHeight() (reserving the command line row) and
  ## screenSize is synced so no ratio-based resizeWindows runs afterward.

  test "FileTree opens with correct layout":
    let config = newEditorConfig()
    config.startUpFileTree.enable = true
    let e = newEditor(config, newValidationResult())

    const
      termWidth = 120
      termHeight = 40
      viewportHeight = termHeight - steadyBottomAreaHeight()

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
      viewportHeight = termHeight - steadyBottomAreaHeight()

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
      viewportHeight = termHeight - steadyBottomAreaHeight()

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
      viewportHeight = termHeight - steadyBottomAreaHeight()

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
      viewportHeight = termHeight - steadyBottomAreaHeight()

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
      viewportHeight = termHeight - steadyBottomAreaHeight()

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
      viewportHeight = termHeight - steadyBottomAreaHeight()

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
      viewportHeight = termHeight - steadyBottomAreaHeight()

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
      viewportHeight = termHeight - steadyBottomAreaHeight()

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

suite "Editor - tickLsp timed-out request cleanup":
  test "tick sweeps an abandoned timed-out request":
    let e = createTestEditor()

    # A request whose consumer stopped polling: already past its timeout and
    # never reclaimed via checkResponse/cancelRequest.
    e.lsp.service.activeRequests[42] =
      LspPendingRequest(requestId: 42, langId: "nim", startTime: 0.0, timeoutMs: 1)

    # The throttle timestamp is reset to "now" at construction, so a tick this
    # instant would be within the 1s window. Backdate it so the sweep fires.
    e.state.timing.lastLspCleanup = getMonoTime() - initDuration(seconds = 2)

    e.tick()

    check 42 notin e.lsp.service.activeRequests
    check not e.lsp.service.hasPendingRequests()

  test "tick leaves a fresh request that has not timed out":
    let e = createTestEditor()

    # A long-lived request that is nowhere near its timeout yet.
    e.lsp.service.activeRequests[7] = LspPendingRequest(
      requestId: 7, langId: "nim", startTime: epochTime(), timeoutMs: 60_000
    )
    e.state.timing.lastLspCleanup = getMonoTime() - initDuration(seconds = 2)

    e.tick()

    check 7 in e.lsp.service.activeRequests

  test "tick within the throttle window does not sweep yet":
    let e = createTestEditor()

    e.lsp.service.activeRequests[99] =
      LspPendingRequest(requestId: 99, langId: "nim", startTime: 0.0, timeoutMs: 1)
    # lastLspCleanup stays at its construction time (~now), so the throttle
    # gate should skip the sweep on this tick.

    e.tick()

    check 99 in e.lsp.service.activeRequests

suite "Editor - openFileInNewRightWindow":
  proc setupLoneFileTree(termWidth: int = 120, termHeight: int = 40): Editor =
    ## Set up an editor where the FileTree is the only window.
    let config = newEditorConfig()
    let e = newEditor(config, newValidationResult())

    let viewportHeight = termHeight - steadyBottomAreaHeight()
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

    let testFile = getTempDir() / "moe_test_open_right.txt"
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

    # Per-window bufferIds contains only the new buffer
    check newWin.bufferIds.len == 1
    check newWin.bufferIds[0] == newWin.buffer.id

  test "reuses existing buffer when file is already loaded":
    let e = setupLoneFileTree()

    let testFile = getTempDir() / "moe_test_open_right_reuse.txt"
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

    let newPath = getTempDir() / "moe_test_open_right_new_file_does_not_exist.txt"
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

    let r = e.openFileInNewRightWindow(getTempDir() / "moe_test_open_right_not_ft.txt")
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

    let testFile = getTempDir() / "moe_test_open_right_nospace.txt"
    writeFile(testFile, "nospace")
    defer:
      removeFile(testFile)

    let r = e.openFileInNewRightWindow(testFile)
    check r.isErr
    check e.windowManager.windows.len == 1

suite "Editor - BufferId":
  test "BufferId is unique across newly created buffers":
    let e = createTestEditor()
    let initialId = e.buffers[0].id

    let testFile = getTempDir() / "moe_test_bufferid_unique.txt"
    writeFile(testFile, "x")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    check e.buffers.len == 2
    check e.buffers[1].id != initialId

  test "bufferById returns Some for live buffer":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    let opt = e.bufferById(buf.id)
    check opt.isSome
    check opt.get == buf

  test "bufferById returns None for unknown id":
    let e = createTestEditor()
    let opt = e.bufferById(BufferId(99999))
    check opt.isNone

  test "bufferIndexById returns -1 for unknown id":
    let e = createTestEditor()
    check e.bufferIndexById(BufferId(99999)) == -1

suite "Editor - Per-window :bnext / :bprev wrapping":
  test ":bnext wraps around at end of window tab list":
    let e = createTestEditor()
    let f1 = getTempDir() / "moe_test_bnext_wrap1.txt"
    let f2 = getTempDir() / "moe_test_bnext_wrap2.txt"
    writeFile(f1, "1")
    writeFile(f2, "2")
    defer:
      removeFile(f1)
      removeFile(f2)

    discard e.editFile(f1)
    discard e.editFile(f2)
    # Currently on f2 (index 2); :bnext should wrap to index 0
    e.switchToNextBuffer()
    check e.currentBufferIndex() == 0

  test ":bprev wraps around at beginning of window tab list":
    let e = createTestEditor()
    let f1 = getTempDir() / "moe_test_bprev_wrap1.txt"
    writeFile(f1, "1")
    defer:
      removeFile(f1)

    discard e.editFile(f1)
    # Currently on f1 (index 1); switch to index 0, then bprev wraps to last
    e.switchToBufferByIndex(0)
    e.switchToPrevBuffer()
    check e.currentBufferIndex() == 1

  test ":bnext wraps to first tab when active buffer isn't in tab list":
    # Regression: when windowBufferIndex() returns -1 (active buffer not
    # registered in this window's tabs), switchToNextBuffer used to land on
    # index 1 because the wrap formula did `(max(-1,0)+1) mod len`. The fix
    # now jumps to index 0, mirroring switchToPrevBuffer's wrap-to-last.
    let e = createTestEditor()
    let f1 = getTempDir() / "moe_test_bnext_orphan1.txt"
    let f2 = getTempDir() / "moe_test_bnext_orphan2.txt"
    writeFile(f1, "1")
    writeFile(f2, "2")
    defer:
      removeFile(f1)
      removeFile(f2)

    discard e.editFile(f1)
    discard e.editFile(f2)
    # Force the "orphan" state: window has f1 and f2 as tabs but active
    # buffer is the initial textBuffer (not in bufferIds).
    e.activeWindow.bufferIds = @[e.buffers[1].id, e.buffers[2].id]
    e.activeWindow.buffer = e.buffers[0]
    check e.windowBufferIndex() == -1

    e.switchToNextBuffer()
    check e.activeWindow.buffer.id == e.buffers[1].id # first tab, not second

  test ":bprev wraps to last tab when active buffer isn't in tab list":
    let e = createTestEditor()
    let f1 = getTempDir() / "moe_test_bprev_orphan1.txt"
    let f2 = getTempDir() / "moe_test_bprev_orphan2.txt"
    writeFile(f1, "1")
    writeFile(f2, "2")
    defer:
      removeFile(f1)
      removeFile(f2)

    discard e.editFile(f1)
    discard e.editFile(f2)
    e.activeWindow.bufferIds = @[e.buffers[1].id, e.buffers[2].id]
    e.activeWindow.buffer = e.buffers[0]
    check e.windowBufferIndex() == -1

    e.switchToPrevBuffer()
    check e.activeWindow.buffer.id == e.buffers[2].id # last tab

suite "Editor - bufferIdIndex synchronization":
  test "addBuffer registers the buffer in bufferIdIndex":
    let e = createTestEditor()
    let initialLen = e.buffers.len

    let buf = newTextBuffer()
    e.addBuffer(buf)

    check e.buffers.len == initialLen + 1
    check e.bufferIdIndex.hasKey(buf.id)
    check e.bufferIdIndex[buf.id] == buf

  test "deleteBufferAt drops the buffer from bufferIdIndex":
    let e = createTestEditor()
    let buf = newTextBuffer()
    e.addBuffer(buf)
    let bufId = buf.id
    let idx = e.bufferIndexById(bufId)
    check idx >= 0

    e.deleteBufferAt(idx)

    check not e.bufferIdIndex.hasKey(bufId)
    check e.bufferById(bufId).isNone

  test "newEditor initializes bufferIdIndex with the initial buffer":
    let e = createTestEditor()
    check e.bufferIdIndex.len == e.buffers.len
    check e.bufferIdIndex.hasKey(e.buffers[0].id)
    check e.bufferIdIndex[e.buffers[0].id] == e.buffers[0]

  test "bufferIdIndex stays consistent after editFile + delete cycle":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_bufferIdIndex_cycle.txt"
    writeFile(testFile, "x")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    check e.bufferIdIndex.len == e.buffers.len
    let openedId = e.buffers[1].id
    check e.bufferIdIndex.hasKey(openedId)

    e.deleteBufferAt(1)
    check e.bufferIdIndex.len == e.buffers.len
    check not e.bufferIdIndex.hasKey(openedId)

  test "deleteBufferAt sends LSP didClose so re-open doesn't collide":
    # Regression: :bdelete used to leave the path tracked in lsp.documents,
    # so a later :e <same file> reset version to 1 and duplicated didOpen,
    # causing servers to drop subsequent didChange as stale.
    # `.txt` keeps this test from spawning a real language worker.
    let e = createTestEditor()
    e.lsp.setEnabled(true)
    let testFile = getTempDir() / "moe_test_bdelete_lsp_close.txt"
    writeFile(testFile, "x")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    check e.lsp.sentDocumentVersion(testFile).isSome

    let idx = e.findBufferByPath(testFile)
    check idx >= 0
    e.deleteBufferAt(idx)

    check e.lsp.sentDocumentVersion(testFile).isNone

  test "bufferById returns the same TextBuffer as a linear scan":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_bufferById_match.txt"
    writeFile(testFile, "x")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    for buf in e.buffers:
      let opt = e.bufferById(buf.id)
      check opt.isSome
      check opt.get == buf

suite "Editor - BufferManager delete keeps state.windowDisplay.currentBufferId fresh":
  test "state.windowDisplay.currentBufferId moves off the deleted buffer's id":
    # Regression: hrBufferManagerDeleteBuffer used to leave
    # state.windowDisplay.currentBufferId pointing at the deleted BufferId. The Jump List
    # (Ctrl-o/Ctrl-i) compares against currentBufferId, so a stale value
    # silently mis-routes future jumps.
    let e = createTestEditor()
    let f1 = getTempDir() / "moe_test_bmgrdel_currentid_1.txt"
    let f2 = getTempDir() / "moe_test_bmgrdel_currentid_2.txt"
    writeFile(f1, "1")
    writeFile(f2, "2")
    defer:
      removeFile(f1)
      removeFile(f2)

    discard e.editFile(f1)
    discard e.editFile(f2)
    # e.buffers = [initial, f1, f2], active = f2
    let f2Id = e.buffers[2].id
    e.state.windowDisplay.currentBufferId = f2Id

    let r = HandlerResult(kind: hrBufferManagerDeleteBuffer, deleteBufferIdx: 2)
    discard e.processResult(r, e.activeBuffer())

    check e.bufferById(f2Id).isNone # buffer is gone
    check e.state.windowDisplay.currentBufferId != f2Id # and the anchor moved off it
    check e.bufferById(e.state.windowDisplay.currentBufferId).isSome # to a live buffer

  test "state.windowDisplay.currentBufferId is left alone when a non-current buffer is deleted":
    let e = createTestEditor()
    let f1 = getTempDir() / "moe_test_bmgrdel_unrelated_1.txt"
    let f2 = getTempDir() / "moe_test_bmgrdel_unrelated_2.txt"
    writeFile(f1, "1")
    writeFile(f2, "2")
    defer:
      removeFile(f1)
      removeFile(f2)

    discard e.editFile(f1)
    discard e.editFile(f2)
    let f1Id = e.buffers[1].id
    let f2Id = e.buffers[2].id
    e.state.windowDisplay.currentBufferId = f2Id

    # Delete f1 (index 1), which is NOT the currentBufferId
    let r = HandlerResult(kind: hrBufferManagerDeleteBuffer, deleteBufferIdx: 1)
    discard e.processResult(r, e.activeBuffer())

    check e.bufferById(f1Id).isNone
    check e.state.windowDisplay.currentBufferId == f2Id # unchanged

suite "Editor - :bdelete (deleteCurrentBuffer) keeps the window open":
  test "switches the active window to a survivor when other buffers exist":
    # Regression: :bd used to call closeWindow, closing the window even when
    # other buffers were still in the buffer list.
    let e = createTestEditor()
    let f1 = getTempDir() / "moe_test_bd_multi_1.txt"
    let f2 = getTempDir() / "moe_test_bd_multi_2.txt"
    writeFile(f1, "1")
    writeFile(f2, "2")
    defer:
      removeFile(f1)
      removeFile(f2)

    discard e.editFile(f1)
    discard e.editFile(f2)
    # e.buffers = [initial, f1, f2], active window shows f2
    check e.buffers.len == 3
    let f2Id = e.activeBuffer().id
    let windowCountBefore = e.windowManager.windows.len

    e.deleteCurrentBuffer()

    check e.windowManager.windows.len == windowCountBefore # window stays open
    check e.buffers.len == 2 # f2 removed from the buffer list
    check e.bufferById(f2Id).isNone
    check e.activeBuffer().id != f2Id # active window moved to another buffer

  test "replaces the last buffer with a fresh [No Name] enew buffer":
    let e = createTestEditor()
    # The initial editor has exactly one buffer
    check e.buffers.len == 1
    let originalId = e.activeBuffer().id

    e.deleteCurrentBuffer()

    check e.windowManager.windows.len == 1 # window stays open
    check e.buffers.len == 1 # enew added a replacement
    check e.bufferById(originalId).isNone
    check e.activeBuffer().id != originalId
    check e.activeBuffer().filePath.isNone # [No Name]

  test "leaves other windows showing different buffers untouched":
    let e = createTestEditor()
    let f1 = getTempDir() / "moe_test_bd_otherwin_1.txt"
    let f2 = getTempDir() / "moe_test_bd_otherwin_2.txt"
    writeFile(f1, "1")
    writeFile(f2, "2")
    defer:
      removeFile(f1)
      removeFile(f2)

    discard e.editFile(f1)
    discard e.vsplit() # active becomes a new window
    discard e.editFile(f2) # active window switches to f2
    check e.windowManager.windows.len == 2
    let f2Id = e.activeBuffer().id

    # Find the non-active window; it must not be on f2 for this test to mean
    # anything.
    let activeIdx = e.windowManager.activeWindowIndex
    let otherIdx = if activeIdx == 0: 1 else: 0
    let otherBufferRef = e.windowManager.windows[otherIdx].buffer
    check otherBufferRef.id != f2Id

    e.deleteCurrentBuffer()

    check e.windowManager.windows.len == 2
    check e.bufferById(f2Id).isNone
    check e.windowManager.windows[otherIdx].buffer == otherBufferRef # untouched

  test "switches every window showing the deleted buffer to a survivor":
    let e = createTestEditor()
    let f1 = getTempDir() / "moe_test_bd_shared_1.txt"
    let f2 = getTempDir() / "moe_test_bd_shared_2.txt"
    writeFile(f1, "1")
    writeFile(f2, "2")
    defer:
      removeFile(f1)
      removeFile(f2)

    discard e.editFile(f1)
    discard e.editFile(f2)
    discard e.vsplit()
    discard e.editFile(f2)
    # After this sequence both windows display the same f2 TextBuffer
    # (`editFile` reuses the existing buffer entry by path).
    check e.windowManager.windows.len == 2
    let f2Id = e.activeBuffer().id
    check e.windowManager.windows[0].buffer.id == f2Id
    check e.windowManager.windows[1].buffer.id == f2Id

    e.deleteCurrentBuffer()

    check e.bufferById(f2Id).isNone
    for w in e.windowManager.windows:
      check w.buffer.id != f2Id # every window moved off f2

  test "prunes the deleted buffer's id from every window's bufferIds":
    let e = createTestEditor()
    let f1 = getTempDir() / "moe_test_bd_prune_1.txt"
    let f2 = getTempDir() / "moe_test_bd_prune_2.txt"
    writeFile(f1, "1")
    writeFile(f2, "2")
    defer:
      removeFile(f1)
      removeFile(f2)

    discard e.editFile(f1)
    discard e.editFile(f2)
    let f2Id = e.activeBuffer().id
    check f2Id in e.activeWindow.bufferIds

    e.deleteCurrentBuffer()

    for w in e.windowManager.windows:
      check f2Id notin w.bufferIds

  test "moves state.windowDisplay.currentBufferId off the deleted buffer's id":
    # Mirrors the BufferManager-delete regression: a stale currentBufferId
    # silently mis-routes the Jump List (Ctrl-o/Ctrl-i).
    let e = createTestEditor()
    let f1 = getTempDir() / "moe_test_bd_currentid_1.txt"
    let f2 = getTempDir() / "moe_test_bd_currentid_2.txt"
    writeFile(f1, "1")
    writeFile(f2, "2")
    defer:
      removeFile(f1)
      removeFile(f2)

    discard e.editFile(f1)
    discard e.editFile(f2)
    let f2Id = e.activeBuffer().id
    check e.state.windowDisplay.currentBufferId == f2Id

    e.deleteCurrentBuffer()

    check e.bufferById(f2Id).isNone
    check e.state.windowDisplay.currentBufferId != f2Id
    check e.bufferById(e.state.windowDisplay.currentBufferId).isSome

  test "processResult(hrBufferDelete) routes through deleteCurrentBuffer":
    # Regression: hrBufferDelete used to call closeWindow() directly.
    let e = createTestEditor()
    let f1 = getTempDir() / "moe_test_bd_wired_1.txt"
    let f2 = getTempDir() / "moe_test_bd_wired_2.txt"
    writeFile(f1, "1")
    writeFile(f2, "2")
    defer:
      removeFile(f1)
      removeFile(f2)

    discard e.editFile(f1)
    discard e.editFile(f2)
    let f2Id = e.activeBuffer().id
    let windowCountBefore = e.windowManager.windows.len

    let r = HandlerResult(kind: hrBufferDelete, forceBufferDelete: false)
    discard e.processResult(r, e.activeBuffer())

    check e.windowManager.windows.len == windowCountBefore # window NOT closed
    check e.bufferById(f2Id).isNone
    check e.activeBuffer().id != f2Id

suite "Editor - BackupManager <-> DiffViewer round-trip":
  # Regression: opening a diff from the backup manager overwrote the window's
  # modeState with the DiffViewer variant, and quitting the diff reset it to
  # mskNone instead of restoring the BackupManagerState. The dispatcher then
  # rejected every key in "BackupManager" mode ("state not initialized"),
  # leaving the manager inoperable. Suspending/resuming the mode fixes this.
  test "quitting the diff restores an operable backup manager":
    let e = createTestEditor()
    let sourceFile = getTempDir() / "moe_test_bk_diff_src.txt"
    let backupFile = getTempDir() / "moe_test_bk_diff_bak.txt"
    writeFile(sourceFile, "line1\nline2\n")
    writeFile(backupFile, "line1\nchanged\n")
    defer:
      removeFile(sourceFile)
      removeFile(backupFile)

    let bkState = BackupManagerState(
      items: @[BackupEntry(filename: "bak", timestamp: now(), fullPath: backupFile)],
      selectedIndex: 0,
      sourceFilePath: sourceFile,
    )
    let win = e.activeWindow
    win.mode = EditorMode.BackupManager
    e.setMode(EditorMode.BackupManager)
    win.modeState = ModeState(kind: mskBackupManager, backupManager: bkState)

    # Open the diff for the selected backup.
    discard e.processResult(
      HandlerResult(kind: hrBackupManagerOpenDiff, diffBackupIndex: 0), e.activeBuffer()
    )
    check win.mode == EditorMode.DiffViewer
    check win.modeState.kind == mskDiffViewer

    # Simulate scrolling deep into a long diff: the cursor/viewport sit far past
    # the short backup-list buffer's length.
    win.cursor.line = 50
    win.cursor.column = 3
    win.viewport.topLine = 40
    win.viewport.leftColumn = 5

    # Quit the diff: must land back on the *same* backup manager state. The
    # selectedIndex carried by that state is what places the cursor at render
    # time (syncSelectionCursor), so restoring the exact bkState ref is the
    # meaningful guarantee here; the post-quit `cursor` is a pre-render reset
    # the user never observes. processResult also drops the diff's stale scroll
    # position by resetting the viewport to the top.
    discard e.processResult(HandlerResult(kind: hrDiffViewerQuit), e.activeBuffer())
    check win.mode == EditorMode.BackupManager
    check win.modeState.kind == mskBackupManager
    check win.modeState.backupManager == bkState
    check win.suspendedMode.isNone
    check win.viewport.topLine == 0
    check win.viewport.leftColumn == 0

  test "hrDiffViewerQuit resumes any suspended mode, not just BackupManager":
    # Manually set up a DiffViewer overlay that suspended Filer mode.
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let diffBuf = newTextBuffer("diff")
    win.buffer = diffBuf
    win.originalBuffer = origBuf
    win.mode = EditorMode.DiffViewer
    e.setMode(EditorMode.DiffViewer)
    win.modeState = ModeState(kind: mskDiffViewer, diffViewer: newDiffViewerState())
    win.suspendedMode = some(
      SuspendedMode(
        mode: EditorMode.Filer,
        modeState: ModeState(kind: mskFiler, filer: FilerState()),
      )
    )

    discard e.processResult(HandlerResult(kind: hrDiffViewerQuit), e.activeBuffer())

    check win.mode == EditorMode.Filer
    check win.modeState.kind == mskFiler
    check win.buffer == origBuf
    check win.suspendedMode.isNone

  test "hrDiffViewerQuit falls back to Normal when nothing was suspended":
    # When no mode was suspended, the quit must land on a stateless mode whose
    # modeState is mskNone. It must NOT borrow `previousMode` (a stateful mode
    # there would leave mode and modeState desynced, reviving the original bug).
    let e = createTestEditor()
    let win = e.activeWindow
    let diffBuf = newTextBuffer("diff")
    win.buffer = diffBuf
    win.mode = EditorMode.DiffViewer
    e.setMode(EditorMode.DiffViewer)
    win.modeState = ModeState(kind: mskDiffViewer, diffViewer: newDiffViewerState())
    win.suspendedMode = none(SuspendedMode)
    e.state.previousMode = EditorMode.BufferManager

    discard e.processResult(HandlerResult(kind: hrDiffViewerQuit), e.activeBuffer())

    check win.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.suspendedMode.isNone

suite "Editor - list viewer quit restores origin cursor/viewport":
  # Regression: hrFilerQuit/hrBufferManagerQuit/hrBookmarkManagerQuit
  # used to restore the original buffer but leave the cursor/viewport wherever
  # the viewer had moved them, losing the editing position. Each state now
  # snapshots the origin cursor/viewport on entry and the quit path restores
  # it, mirroring the References/DocumentSymbol/CallHierarchy viewers.
  test "processResult(hrFilerQuit) restores the pre-filer cursor/viewport":
    let e = createTestEditor()
    let f = getTempDir() / "moe_test_filer_quit_restore.txt"
    writeFile(f, "aaaa\nbbbb\ncccc\ndddd\neeee\nffff\ngggg\nhhhh\niiii\njjjj\n")
    defer:
      removeFile(f)

    discard e.editFile(f)
    let win = e.activeWindow
    let origBuf = win.buffer
    win.cursor.line = 5
    win.cursor.column = 2
    win.viewport.topLine = 4
    win.viewport.leftColumn = 3

    discard e.processResult(HandlerResult(kind: hrEnterFiler), e.activeBuffer())
    check win.mode == EditorMode.Filer
    check win.modeState.kind == mskFiler
    check win.cursor.line == 0
    check win.viewport.topLine == 0

    # Simulate navigation inside the filer.
    win.cursor.line = 3
    win.viewport.topLine = 2

    discard e.processResult(HandlerResult(kind: hrFilerQuit), e.activeBuffer())
    check win.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.buffer == origBuf
    check win.cursor.line == 5
    check win.cursor.column == 2
    check win.viewport.topLine == 4
    check win.viewport.leftColumn == 3

  test "processResult(hrBufferManagerQuit) restores the pre-manager cursor/viewport":
    let e = createTestEditor()
    let f = getTempDir() / "moe_test_bm_quit_restore.txt"
    writeFile(f, "aaaa\nbbbb\ncccc\ndddd\neeee\nffff\ngggg\nhhhh\niiii\njjjj\n")
    defer:
      removeFile(f)

    discard e.editFile(f)
    let win = e.activeWindow
    let origBuf = win.buffer
    win.cursor.line = 6
    win.cursor.column = 1
    win.viewport.topLine = 5
    win.viewport.leftColumn = 2

    discard e.processResult(HandlerResult(kind: hrEnterBufferManager), e.activeBuffer())
    check win.mode == EditorMode.BufferManager
    check win.modeState.kind == mskBufferManager
    check win.cursor.line == 0
    check win.viewport.topLine == 0

    # Simulate navigation inside the manager.
    win.cursor.line = 2
    win.viewport.topLine = 1

    discard e.processResult(HandlerResult(kind: hrBufferManagerQuit), e.activeBuffer())
    check win.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.buffer == origBuf
    check win.cursor.line == 6
    check win.cursor.column == 1
    check win.viewport.topLine == 5
    check win.viewport.leftColumn == 2

  test "processResult(hrEnterBufferManager) swaps buffer and preserves origin for quit":
    let e = createTestEditor()
    let f = getTempDir() / "moe_test_bm_mode_transition.txt"
    writeFile(f, "aaaa\nbbbb\ncccc\ndddd\neeee\nffff\ngggg\nhhhh\niiii\njjjj\n")
    defer:
      removeFile(f)

    discard e.editFile(f)
    let win = e.activeWindow
    let origBuf = win.buffer
    win.cursor.line = 5
    win.cursor.column = 2
    win.viewport.topLine = 4
    win.viewport.leftColumn = 3

    discard e.processResult(HandlerResult(kind: hrEnterBufferManager), e.activeBuffer())
    check win.mode == EditorMode.BufferManager
    check win.modeState.kind == mskBufferManager
    check win.buffer != origBuf
    check win.cursor.line == 0
    check win.cursor.column == 0
    check win.viewport.topLine == 0
    check win.viewport.leftColumn == 0

    discard e.processResult(HandlerResult(kind: hrBufferManagerQuit), e.activeBuffer())
    check win.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.buffer == origBuf
    check win.cursor.line == 5
    check win.cursor.column == 2
    check win.viewport.topLine == 4
    check win.viewport.leftColumn == 3

  test "processResult(hrBookmarkManagerQuit) restores the pre-manager cursor/viewport":
    let e = createTestEditor()
    let f = getTempDir() / "moe_test_bkm_quit_restore.txt"
    writeFile(f, "aaaa\nbbbb\ncccc\ndddd\neeee\nffff\ngggg\nhhhh\niiii\njjjj\n")
    defer:
      removeFile(f)

    discard e.editFile(f)
    let win = e.activeWindow
    let origBuf = win.buffer
    win.cursor.line = 7
    win.cursor.column = 3
    win.viewport.topLine = 6
    win.viewport.leftColumn = 1

    discard
      e.processResult(HandlerResult(kind: hrEnterBookmarkManager), e.activeBuffer())
    check win.mode == EditorMode.BookmarkManager
    check win.modeState.kind == mskBookmarkManager
    check win.cursor.line == 0
    check win.viewport.topLine == 0

    # Simulate navigation inside the manager.
    win.cursor.line = 4
    win.viewport.topLine = 3

    discard
      e.processResult(HandlerResult(kind: hrBookmarkManagerQuit), e.activeBuffer())
    check win.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.buffer == origBuf
    check win.cursor.line == 7
    check win.cursor.column == 3
    check win.viewport.topLine == 6
    check win.viewport.leftColumn == 1

suite "Editor - Command mode command alias bridge end-to-end (#2597)":
  # Regression: the `keyMappableCommandModeAliases` bridge in
  # `command_handlers/handler_manager.nim` rewrites a `K = "bdelete"` keymap
  # dispatch into `HandlerResult(kind: hrExecCommand, execCommandText:
  # "bdelete")`. `handleKeyMappingTimeout` then forwards that result to
  # `processResult`, which is supposed to drive the full `:bdelete`
  # command-line parser (so the modified-buffer guard fires). These tests
  # exercise the processResult half of that pipeline with the exact result the
  # bridge produces — guarding both the bridge contract (text == "bdelete")
  # and the command-line parser dispatch wiring.
  test "processResult(hrExecCommand bdelete) deletes a clean buffer":
    let e = createTestEditor()
    let f1 = getTempDir() / "moe_test_bridge_clean_1.txt"
    let f2 = getTempDir() / "moe_test_bridge_clean_2.txt"
    writeFile(f1, "1")
    writeFile(f2, "2")
    defer:
      removeFile(f1)
      removeFile(f2)

    discard e.editFile(f1)
    discard e.editFile(f2)
    let f2Id = e.activeBuffer().id
    let windowCountBefore = e.windowManager.windows.len
    check not e.activeBuffer().isModified

    # The bridge in handler_manager.nim/normal_handler.nim builds exactly this
    # HandlerResult for an alias like "bdelete".
    let r = HandlerResult(
      kind: hrExecCommand, execCommandText: "bdelete", execCommandCount: 1
    )
    discard e.processResult(r, e.activeBuffer())

    check e.windowManager.windows.len == windowCountBefore
    check e.bufferById(f2Id).isNone
    check e.activeBuffer().id != f2Id

  test "processResult(hrExecCommand bdelete) refuses to delete a dirty buffer":
    # The whole reason the bridge routes through `:bdelete` (instead of
    # invoking deleteCurrentBuffer directly) is to inherit the parser-side
    # modified-buffer guard. This test would silently regress to
    # "buffer destroyed despite unsaved edits" if a future refactor short-
    # circuited the command-line parser path.
    let e = createTestEditor()
    let f1 = getTempDir() / "moe_test_bridge_dirty_1.txt"
    let f2 = getTempDir() / "moe_test_bridge_dirty_2.txt"
    writeFile(f1, "1")
    writeFile(f2, "2")
    defer:
      removeFile(f1)
      removeFile(f2)

    discard e.editFile(f1)
    discard e.editFile(f2)
    let f2Id = e.activeBuffer().id
    let bufferCountBefore = e.buffers.len

    # Dirty the active buffer so :bdelete should reject.
    discard e.activeBuffer().insertText(BufferPosition(line: 0, column: 0), "X")
    check e.activeBuffer().isModified

    let r = HandlerResult(
      kind: hrExecCommand, execCommandText: "bdelete", execCommandCount: 1
    )
    discard e.processResult(r, e.activeBuffer())

    check e.bufferById(f2Id).isSome # buffer survived the guard
    check e.activeBuffer().id == f2Id # still focused on the dirty buffer
    check e.buffers.len == bufferCountBefore
    check "No write since last change" in e.state.statusMessage

suite "Editor - :theme routes through config so save/reload stay in sync":
  test ":theme default resets config.theme to tkDefault":
    let e = createTestEditor()
    e.config.theme.kind = tkConfig
    e.config.theme.path = getTempDir() / "moe_test_theme_prev.toml"

    e.applyThemeCommand("default")

    check e.config.theme.kind == tkDefault
    check e.config.theme.path == ""
    check e.state.statusMessage == "Theme changed to: default"

  test ":theme <name> updates config.theme.path to the loaded file":
    let e = createTestEditor()

    let fakeHome = getTempDir() / "moe_test_theme_home"
    let themesDir = fakeHome / ".config" / "moe" / "themes"
    createDir(themesDir)
    let themeFile = themesDir / "mytheme.toml"
    writeFile(
      themeFile,
      """
[Colors]
foreground = "#eeeeee"
background = "#111111"
""",
    )

    let originalHome = getEnv("HOME")
    putEnv("HOME", fakeHome)
    defer:
      putEnv("HOME", originalHome)
      removeDir(fakeHome)

    e.config.theme.kind = tkConfig
    e.config.theme.path = getTempDir() / "moe_test_theme_prev.toml"

    e.applyThemeCommand("mytheme")

    check e.config.theme.kind == tkConfig
    check e.config.theme.path == themeFile
    check e.state.statusMessage == "Theme changed to: mytheme"

  test ":theme <missing> leaves config.theme untouched":
    let e = createTestEditor()

    let fakeHome = getTempDir() / "moe_test_theme_missing_home"
    createDir(fakeHome / ".config" / "moe" / "themes")

    let originalHome = getEnv("HOME")
    putEnv("HOME", fakeHome)
    defer:
      putEnv("HOME", originalHome)
      removeDir(fakeHome)

    let previousPath = getTempDir() / "moe_test_theme_previous.toml"
    e.config.theme.kind = tkConfig
    e.config.theme.path = previousPath

    e.applyThemeCommand("nope")

    check e.config.theme.kind == tkConfig
    check e.config.theme.path == previousPath
    check e.state.statusMessage == "Theme not found: nope"

suite "Editor - processResult(hrSave) actually saves (regression)":
  test "processResult(hrSave) writes modified buffer to disk":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_hSave_regression.txt"
    writeFile(testFile, "original")
    defer:
      removeFile(testFile)

    check e.editFile(testFile).isOk
    discard
      e.activeBuffer().insertText(BufferPosition(line: 0, column: 0), "modified: ")
    check e.activeBuffer().isModified

    let r = HandlerResult(kind: hrSave, saveFilename: none(string), forceSave: false)
    let ok = e.processResult(r, e.activeBuffer())
    check ok

    check readFile(testFile).startsWith("modified: original")
    check not e.activeBuffer().isModified

  test "processResult(hrSave) still returns true when save fails":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_hSave_readonly" / "nested.txt"
    defer:
      removeFile(testFile)
      removeDir(testFile.parentDir)

    createDir(testFile.parentDir)
    writeFile(testFile, "content")
    check e.editFile(testFile).isOk
    discard e.activeBuffer().insertText(BufferPosition(line: 0, column: 0), "X")
    setFilePermissions(testFile, {fpUserRead})
    defer:
      setFilePermissions(testFile, {fpUserRead, fpUserWrite})

    let r = HandlerResult(kind: hrSave, saveFilename: none(string), forceSave: false)
    let ok = e.processResult(r, e.activeBuffer())
    check ok

suite "Editor - processResult(hrSaveAll) actually saves (regression)":
  test "processResult(hrSaveAll) writes every modified buffer to disk":
    let e = createTestEditor()
    let f1 = getTempDir() / "moe_test_hSaveAll_regr_a.txt"
    let f2 = getTempDir() / "moe_test_hSaveAll_regr_b.txt"
    writeFile(f1, "A")
    writeFile(f2, "B")
    defer:
      removeFile(f1)
      removeFile(f2)

    check e.editFile(f1).isOk
    check e.editFile(f2).isOk

    # Dirty the first buffer (active = f2 after second editFile)
    discard e.buffers[1].insertText(BufferPosition(line: 0, column: 0), "modA: ")
    check e.buffers[1].isModified
    # Dirty f2 as well
    discard e.activeBuffer().insertText(BufferPosition(line: 0, column: 0), "modB: ")
    check e.activeBuffer().isModified

    let r = HandlerResult(kind: hrSaveAll, forceSaveAll: false)
    let ok = e.processResult(r, e.activeBuffer())
    check ok

    check readFile(f1) == "modA: A"
    check readFile(f2) == "modB: B"
    check not e.buffers[1].isModified
    check not e.activeBuffer().isModified

suite "Editor - addCommandAlias/removeCommandAlias":
  test "addCommandAlias updates parser, command config, and persisted config":
    let e = createTestEditor()

    check e.addCommandAlias("zz", claQuit).isOk

    check e.commandLineParser.aliases["zz"] == claQuit
    check e.commandConfig.aliases["zz"] == claQuit
    check e.config.commandAliases["zz"].command == "quit"

  test "addCommandAlias normalises the alias to lowercase":
    let e = createTestEditor()

    check e.addCommandAlias("ZZ", claQuit).isOk

    check "zz" in e.commandLineParser.aliases
    check "zz" in e.commandConfig.aliases
    check "zz" in e.config.commandAliases

  test "removeCommandAlias updates parser, command config, and persisted config":
    let e = createTestEditor()

    check e.addCommandAlias("zz", claQuit).isOk
    check e.removeCommandAlias("zz").isOk

    check "zz" notin e.commandLineParser.aliases
    check "zz" notin e.commandConfig.aliases
    check "zz" notin e.config.commandAliases

  test "removeCommandAlias normalises the alias to lowercase":
    let e = createTestEditor()

    check e.addCommandAlias("zz", claQuit).isOk
    check e.removeCommandAlias("ZZ").isOk

    check "zz" notin e.commandLineParser.aliases

  test "removeCommandAlias fails for an unknown alias":
    let e = createTestEditor()

    let r = e.removeCommandAlias("nosuchalias")

    check r.isErr
    check "nosuchalias" in r.error

  test "Removed alias does not revive when another alias is added (regression)":
    let e = createTestEditor()

    check e.addCommandAlias("zz", claQuit).isOk
    check e.removeCommandAlias("zz").isOk
    # Pre-fix, applyToParser re-applied commandConfig.aliases (which still
    # held "zz") and revived the removed alias.
    check e.addCommandAlias("yy", claSaveAndQuit).isOk

    check "zz" notin e.commandLineParser.aliases
    check "yy" in e.commandLineParser.aliases

  test "Added alias survives a save/reload round-trip":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_alias_roundtrip.toml"
    defer:
      removeFile(testFile)

    check e.addCommandAlias("zz", claQuit).isOk
    check saveConfigToToml(e.config, testFile).isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loadedConfig, vr) = loadResult.get
    check not vr.hasErrors
    check loadedConfig.commandAliases["zz"].command == "quit"
    check resolveCommandName(loadedConfig.commandAliases["zz"].command) == some(claQuit)

  test "Removed alias stays removed after a save/reload round-trip":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_alias_remove_roundtrip.toml"
    defer:
      removeFile(testFile)

    check e.addCommandAlias("zz", claQuit).isOk
    check e.removeCommandAlias("zz").isOk
    check saveConfigToToml(e.config, testFile).isOk

    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loadedConfig, _) = loadResult.get
    check "zz" notin loadedConfig.commandAliases

  test "Removing a user-defined alias does not touch disabledCommandAliases":
    let e = createTestEditor()

    check e.addCommandAlias("zz", claQuit).isOk
    check e.removeCommandAlias("zz").isOk

    check e.config.disabledCommandAliases.len == 0

  test "Removing a built-in default alias persists as DisabledCommandAliases":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_alias_disable_default.toml"
    defer:
      removeFile(testFile)

    check "q" in e.commandLineParser.aliases
    check e.removeCommandAlias("q").isOk

    check "q" notin e.commandLineParser.aliases
    check "q" notin e.commandConfig.aliases
    check e.config.disabledCommandAliases == @["q"]

    # The removal survives a save/reload round-trip: a parser built from the
    # reloaded config must not have the default alias back.
    check saveConfigToToml(e.config, testFile).isOk
    let loadResult = loadConfigFromToml(testFile)
    check loadResult.isOk
    let (loadedConfig, vr) = loadResult.get
    check not vr.hasErrors
    check loadedConfig.disabledCommandAliases == @["q"]

    var initVr = newValidationResult()
    let (_, _, cmdConfig, cmdLineParser) = newEditorRegistries(loadedConfig, initVr)
    check "q" notin cmdConfig.aliases
    check "q" notin cmdLineParser.aliases

  test "addCommandAlias lifts a persisted disable of the same name":
    let e = createTestEditor()

    check e.removeCommandAlias("q").isOk
    check e.config.disabledCommandAliases == @["q"]

    check e.addCommandAlias("q", claQuit).isOk

    check e.config.disabledCommandAliases.len == 0
    check "q" in e.config.commandAliases
    check "q" in e.commandLineParser.aliases

  test "Removed default alias does not revive when another alias is added":
    let e = createTestEditor()

    check e.removeCommandAlias("q").isOk
    check e.addCommandAlias("zz", claQuit).isOk

    check "q" notin e.commandLineParser.aliases

suite "Editor - tab/indent setters sync .editorconfig override":
  # Regression: Editor-layer setters used to write only config.standard.*,
  # leaving buf.editorConfig unchanged. Since the getter prefers the override,
  # a write via `e.tabStop = v` was silently overshadowed on read.
  test "tabStop= updates both the config and the buffer override":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    buf.editorConfig = some(BufferEditorConfig(tabStop: some(2)))

    e.tabStop = 8

    check e.config.standard.tabStop == 8
    check buf.editorConfig.get.tabStop == some(8)
    check e.tabStop == 8

  test "shiftWidth= updates both the config and the buffer override":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    buf.editorConfig = some(BufferEditorConfig(shiftWidth: some(2)))

    e.shiftWidth = 8

    check e.config.standard.shiftWidth == 8
    check buf.editorConfig.get.shiftWidth == some(8)
    check e.shiftWidth == 8

  test "expandTab= updates both the config and the buffer override":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    buf.editorConfig = some(BufferEditorConfig(expandTab: some(false)))

    e.expandTab = true

    check e.config.standard.expandTab == true
    check buf.editorConfig.get.expandTab == some(true)
    check e.expandTab == true

suite "Editor - handler CommandContext sees live config after applyConfigSettings":
  # Regression: handlers used to snapshot Clipboard/SmoothScroll/Notification at
  # construction, so applyConfigSettings' ref swap never reached them. Now
  # CommandContext getters pull from state.config directly.
  test "CommandContext.clipboardConfig reflects post-reload clipboard":
    let e = createTestEditor()

    let ctx = CommandContext(state: e.state)
    let originalTool = e.config.clipboard.tool
    check originalTool != cbtXclip

    var newConfig = newEditorConfig()
    newConfig.clipboard = ClipboardConfig(enable: true, tool: cbtXclip)
    e.applyConfigSettings(newConfig)

    check ctx.clipboardConfig.enable == true
    check ctx.clipboardConfig.tool == cbtXclip

  test "CommandContext.smoothScrollConfig reflects post-reload smoothScroll":
    let e = createTestEditor()

    let ctx = CommandContext(state: e.state)

    var newConfig = newEditorConfig()
    newConfig.smoothScroll =
      SmoothScrollConfig(enable: false, friction: 42.0, airDrag: 3.0)
    e.applyConfigSettings(newConfig)

    check ctx.smoothScrollConfig.enable == false
    check ctx.smoothScrollConfig.friction == 42.0
    check ctx.smoothScrollConfig.airDrag == 3.0

  test "CommandContext.notificationConfig reflects post-reload notification":
    let e = createTestEditor()

    let ctx = CommandContext(state: e.state)

    var newConfig = newEditorConfig()
    newConfig.notification.screenNotifications = false
    newConfig.notification.yankScreenNotify = false
    e.applyConfigSettings(newConfig)

    check ctx.notificationConfig.screenNotifications == false
    check ctx.notificationConfig.yankScreenNotify == false

suite "processResult - viewer split window teardown":
  ## hrHelpViewerQuit and its siblings share one teardown path; these cover it
  ## through processResult rather than re-implementing the sequence.

  test "hrHelpViewerQuit closes the split window and discards its buffer":
    let e = createTestEditor()
    let origBuffer = e.activeBuffer
    let initialBufferCount = e.buffers.len

    discard e.processResult(HandlerResult(kind: hrEnterHelpViewer), e.activeBuffer)
    check e.windowManager.windows.len == 2
    check e.state.mode == EditorMode.Help
    let helpBufId = e.activeWindow.buffer.id

    check e.processResult(HandlerResult(kind: hrHelpViewerQuit), e.activeBuffer) == true

    check e.windowManager.windows.len == 1
    check e.buffers.len == initialBufferCount
    check e.bufferIndexById(helpBufId) < 0
    for win in e.windowManager.windows:
      check helpBufId notin win.bufferIds
    check e.state.mode == EditorMode.Normal
    check e.activeWindow.mode == EditorMode.Normal
    check e.activeWindow.buffer == origBuffer

  test "hrHelpViewerQuit on a single window swaps in a usable buffer":
    let e = createTestEditor()
    let initialBufferCount = e.buffers.len

    # Hand-built single-window Help: a split placement recorded on the only
    # window, so the teardown has nothing to fall back to.
    let helpState = newHelpViewerState()
    let activeWin = e.activeWindow
    e.setMode(EditorMode.Help)
    activeWin.mode = EditorMode.Help
    activeWin.modeState = ModeState(kind: mskHelp, help: helpState)
    activeWin.viewerEntry = some(
      ViewerEntry(
        mode: EditorMode.Help,
        placement: vpHSplit,
        returnMode: EditorMode.Normal,
        bufferId: activeWin.buffer.id,
      )
    )

    check e.processResult(HandlerResult(kind: hrHelpViewerQuit), e.activeBuffer) == true

    # No window to fall back to, so the listing is replaced with a fresh empty
    # buffer instead of leaving the user stranded on a read-only view.
    check e.windowManager.windows.len == 1
    check e.buffers.len == initialBufferCount
    check e.state.mode == EditorMode.Normal
    check e.activeWindow.modeState.kind == mskNone
    check e.activeWindow.buffer != nil
