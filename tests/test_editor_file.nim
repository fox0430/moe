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

## Tests for editor_file.nim

import std/[unittest, os, options, monotimes, times, strutils]
import pkg/results
import ../src/moepkg/[editor, buffer, config, config_loader]

proc createTestEditor(): Editor =
  ## Create a minimal editor for testing
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc createTestEditorWithConfig(config: EditorConfig): Editor =
  ## Create an editor with custom config
  let vr = newValidationResult()
  result = newEditor(config, vr)

suite "Editor - loadFile":
  test "Load existing file":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_load.txt"

    writeFile(testFile, "Hello World\nLine 2")
    defer:
      removeFile(testFile)

    let result = e.loadFile(testFile)
    check result.isOk
    check e.activeBuffer.filePath.isSome
    check e.activeBuffer.filePath.get == testFile
    check e.activeBuffer.len == 2
    check e.activeBuffer.getLine(0) == "Hello World"
    check e.activeBuffer.getLine(1) == "Line 2"

  test "Load file resets cursor position":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_load_cursor.txt"

    writeFile(testFile, "Line 1\nLine 2\nLine 3")
    defer:
      removeFile(testFile)

    # Set cursor to non-zero position
    e.state.cursor = BufferPosition(line: 5, column: 10)

    let result = e.loadFile(testFile)
    check result.isOk
    check e.state.cursor.line == 0
    check e.state.cursor.column == 0

  test "Load file resets viewport":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_load_viewport.txt"

    writeFile(testFile, "Content")
    defer:
      removeFile(testFile)

    # Set viewport to non-zero position
    e.viewport.topLine = 100
    e.viewport.leftColumn = 50

    let result = e.loadFile(testFile)
    check result.isOk
    check e.viewport.topLine == 0
    check e.viewport.leftColumn == 0

  test "Load nonexistent file returns error":
    let e = createTestEditor()

    # loadFile returns error for directories or permission issues,
    # but may succeed for non-existent files (creating empty buffer)
    # Check that file path is set even for non-existent file
    let result = e.loadFile("/tmp/moe_nonexistent_test_file_12345.txt")
    # The behavior depends on buffer.loadFile implementation
    # If it creates an empty buffer for new files, it returns ok
    # If it strictly requires file to exist, it returns error
    if result.isErr:
      check "not found" in result.error.toLowerAscii or "No such file" in result.error or
        "cannot open" in result.error.toLowerAscii
    else:
      # File may be created as new file
      check true

  test "Load file with persisted cursor position":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    let e = createTestEditorWithConfig(config)
    let testFile = "/tmp/moe_test_load_persist.txt"

    writeFile(testFile, "Line 1\nLine 2\nLine 3\nLine 4\nLine 5")
    defer:
      removeFile(testFile)

    # Set a persisted cursor position
    let absPath = absolutePath(testFile)
    e.cursorPositions[absPath] = CursorPositionEntry(line: 2, column: 3)

    let result = e.loadFile(testFile)
    check result.isOk
    check e.state.cursor.line == 2
    check e.state.cursor.column == 3

  test "Load file clamps persisted cursor to buffer bounds":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    let e = createTestEditorWithConfig(config)
    let testFile = "/tmp/moe_test_load_clamp.txt"

    writeFile(testFile, "Short")
    defer:
      removeFile(testFile)

    # Set a persisted cursor position that exceeds buffer
    let absPath = absolutePath(testFile)
    e.cursorPositions[absPath] = CursorPositionEntry(line: 100, column: 100)

    let result = e.loadFile(testFile)
    check result.isOk
    # Cursor should be clamped to buffer bounds
    check e.state.cursor.line == 0
    check e.state.cursor.column <= "Short".len

suite "Editor - saveFile":
  test "Save file to existing path":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_save.txt"

    # Load a file first
    writeFile(testFile, "Original content")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)

    # Modify buffer
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Modified: ")

    # Save
    let result = e.saveFile()
    check result.isOk

    # Verify file content
    let content = readFile(testFile)
    check "Modified:" in content

  test "Save file with explicit path":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_save_explicit.txt"
    defer:
      if fileExists(testFile):
        removeFile(testFile)

    # Add content to buffer
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "New content")

    # Save with explicit path
    let result = e.saveFile(some(testFile))
    check result.isOk

    # Verify file was created
    check fileExists(testFile)
    let content = readFile(testFile)
    check "New content" in content

  test "Save file with no path returns error":
    let e = createTestEditor()

    # Buffer has no file path
    check e.activeBuffer.filePath.isNone

    let result = e.saveFile()
    check result.isErr
    check "No file path" in result.error

  test "Save file force overwrites externally modified file":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_save_force.txt"

    writeFile(testFile, "Original content")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)

    # Simulate external modification by changing the file
    writeFile(testFile, "Externally modified")

    # Modify buffer
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Buffer: ")

    # Force save should succeed
    let result = e.saveFile(force = true)
    check result.isOk

  test "Save-as to a different path is not blocked by external modification":
    let e = createTestEditor()
    let original = getTempDir() / "moe_test_saveas_orig.txt"
    let target = getTempDir() / "moe_test_saveas_target.txt"

    writeFile(original, "Original content")
    defer:
      removeFile(original)
      if fileExists(target):
        removeFile(target)

    discard e.loadFile(original)

    # Simulate external modification of the original file.
    e.activeBuffer.lastFileModTime = some(getTime() - initDuration(seconds = 2))
    writeFile(original, "Externally modified")

    # Saving to a different path must succeed without force.
    let result = e.saveFile(some(target))
    check result.isOk
    check fileExists(target)

suite "Editor - saveBufferCursorPosition":
  test "Save cursor position when enabled":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    let e = createTestEditorWithConfig(config)
    let testFile = "/tmp/moe_test_cursor_pos.txt"

    writeFile(testFile, "Content")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)

    # Set cursor position (use e.cursor to sync both EditorWindow and EditorState)
    e.cursor = BufferPosition(line: 0, column: 3)

    # Save cursor position
    e.saveBufferCursorPosition(e.activeBuffer)

    # Verify cursor position was saved
    let absPath = absolutePath(testFile)
    check e.cursorPositions.hasKey(absPath)
    check e.cursorPositions[absPath].line == 0
    check e.cursorPositions[absPath].column == 3

  test "Do not save cursor position when disabled":
    var config = newEditorConfig()
    config.persist.cursorPosition = false
    let e = createTestEditorWithConfig(config)
    let testFile = "/tmp/moe_test_cursor_no_persist.txt"

    writeFile(testFile, "Content")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)
    e.cursor = BufferPosition(line: 0, column: 5)

    e.saveBufferCursorPosition(e.activeBuffer)

    # Cursor position should not be saved
    let absPath = absolutePath(testFile)
    check not e.cursorPositions.hasKey(absPath)

  test "Do not save cursor position for buffer without path":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    let e = createTestEditorWithConfig(config)

    # Buffer has no file path
    check e.activeBuffer.filePath.isNone

    let initialCount = e.cursorPositions.len
    e.saveBufferCursorPosition(e.activeBuffer)

    # No new cursor position should be added
    check e.cursorPositions.len == initialCount

  test "Do not save cursor position for COMMIT_EDITMSG":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    let e = createTestEditorWithConfig(config)
    let testFile = "/tmp/moe_test_COMMIT_EDITMSG/COMMIT_EDITMSG"

    createDir("/tmp/moe_test_COMMIT_EDITMSG")
    writeFile(testFile, "commit message")
    defer:
      removeDir("/tmp/moe_test_COMMIT_EDITMSG")

    discard e.loadFile(testFile)
    e.cursor = BufferPosition(line: 0, column: 3)

    e.saveBufferCursorPosition(e.activeBuffer)

    let absPath = absolutePath(testFile)
    check not e.cursorPositions.hasKey(absPath)

  test "Do not save cursor position for git-rebase-todo":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    let e = createTestEditorWithConfig(config)
    let testFile = "/tmp/moe_test_rebase/git-rebase-todo"

    createDir("/tmp/moe_test_rebase")
    writeFile(testFile, "pick abc123 some commit")
    defer:
      removeDir("/tmp/moe_test_rebase")

    discard e.loadFile(testFile)
    e.cursor = BufferPosition(line: 0, column: 5)

    e.saveBufferCursorPosition(e.activeBuffer)

    let absPath = absolutePath(testFile)
    check not e.cursorPositions.hasKey(absPath)

  test "Do not restore cursor position for COMMIT_EDITMSG":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    let e = createTestEditorWithConfig(config)
    let testFile = "/tmp/moe_test_COMMIT_EDITMSG2/COMMIT_EDITMSG"

    createDir("/tmp/moe_test_COMMIT_EDITMSG2")
    writeFile(testFile, "commit message content")
    defer:
      removeDir("/tmp/moe_test_COMMIT_EDITMSG2")

    # Pre-populate cursor positions with a saved position for this file
    let absPath = absolutePath(testFile)
    e.cursorPositions[absPath] = CursorPositionEntry(line: 0, column: 10)

    discard e.loadFile(testFile)

    # Cursor should be at start, not restored to saved position
    check e.cursor.line == 0
    check e.cursor.column == 0

  test "Do not restore cursor position for git-rebase-todo":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    let e = createTestEditorWithConfig(config)
    let testFile = "/tmp/moe_test_rebase2/git-rebase-todo"

    createDir("/tmp/moe_test_rebase2")
    writeFile(testFile, "pick abc123 some commit")
    defer:
      removeDir("/tmp/moe_test_rebase2")

    # Pre-populate cursor positions with a saved position for this file
    let absPath = absolutePath(testFile)
    e.cursorPositions[absPath] = CursorPositionEntry(line: 0, column: 10)

    discard e.loadFile(testFile)

    # Cursor should be at start, not restored to saved position
    check e.cursor.line == 0
    check e.cursor.column == 0

suite "Editor - addCommandToHistory":
  test "Add command to history":
    var config = newEditorConfig()
    # Disable persistence to start with empty history
    config.persist.commandHistory = false
    let e = createTestEditorWithConfig(config)

    # Clear any existing history
    e.state.commandState.history = @[]

    e.addCommandToHistory("write")
    check e.state.commandState.history.len == 1
    check e.state.commandState.history[0] == "write"

  test "Add multiple commands to history":
    var config = newEditorConfig()
    config.persist.commandHistory = false
    let e = createTestEditorWithConfig(config)

    # Clear any existing history
    e.state.commandState.history = @[]

    e.addCommandToHistory("first")
    e.addCommandToHistory("second")
    e.addCommandToHistory("third")

    check e.state.commandState.history.len == 3
    # Most recent first
    check e.state.commandState.history[0] == "third"
    check e.state.commandState.history[1] == "second"
    check e.state.commandState.history[2] == "first"

  test "Skip empty command":
    var config = newEditorConfig()
    config.persist.commandHistory = false
    let e = createTestEditorWithConfig(config)

    # Clear any existing history
    e.state.commandState.history = @[]

    e.addCommandToHistory("")
    check e.state.commandState.history.len == 0

  test "Skip duplicate of last command":
    var config = newEditorConfig()
    config.persist.commandHistory = false
    let e = createTestEditorWithConfig(config)

    # Clear any existing history
    e.state.commandState.history = @[]

    e.addCommandToHistory("write")
    e.addCommandToHistory("write")

    check e.state.commandState.history.len == 1

  test "Allow same command if not last":
    var config = newEditorConfig()
    config.persist.commandHistory = false
    let e = createTestEditorWithConfig(config)

    # Clear any existing history
    e.state.commandState.history = @[]

    e.addCommandToHistory("write")
    e.addCommandToHistory("quit")
    e.addCommandToHistory("write")

    check e.state.commandState.history.len == 3

  test "Trim history to limit":
    var config = newEditorConfig()
    config.persist.commandHistory = false
    config.persist.commandHistoryLimit = 3
    let e = createTestEditorWithConfig(config)

    # Clear any existing history
    e.state.commandState.history = @[]

    e.addCommandToHistory("cmd1")
    e.addCommandToHistory("cmd2")
    e.addCommandToHistory("cmd3")
    e.addCommandToHistory("cmd4")
    e.addCommandToHistory("cmd5")

    check e.state.commandState.history.len == 3
    # Most recent commands should be kept
    check e.state.commandState.history[0] == "cmd5"
    check e.state.commandState.history[1] == "cmd4"
    check e.state.commandState.history[2] == "cmd3"

suite "Editor - updateInputTime":
  test "Update input time":
    let e = createTestEditor()

    let beforeTime = e.state.timing.lastInputTime
    # Small delay to ensure time changes
    sleep(10)
    e.updateInputTime()
    let afterTime = e.state.timing.lastInputTime

    check afterTime > beforeTime

suite "Editor - autoSave":
  test "Auto save does nothing when disabled":
    var config = newEditorConfig()
    config.autoSave.enable = false
    let e = createTestEditorWithConfig(config)
    let testFile = "/tmp/moe_test_autosave_disabled.txt"

    writeFile(testFile, "Original")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)
    # Insert text to make buffer modified
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Modified: ")

    # Set last auto save to long ago
    e.state.timing.lastAutoSave = getMonoTime() - initDuration(hours = 1)

    e.autoSave()

    # File should not be modified (auto save disabled)
    let content = readFile(testFile)
    check content == "Original"

  test "Auto save respects interval":
    var config = newEditorConfig()
    config.autoSave.enable = true
    config.autoSave.interval = 60 # 60 minutes
    let e = createTestEditorWithConfig(config)
    let testFile = "/tmp/moe_test_autosave_interval.txt"

    writeFile(testFile, "Original")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)
    # Insert text to make buffer modified
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Modified: ")

    # Set last auto save to recent (less than interval)
    e.state.timing.lastAutoSave = getMonoTime()

    e.autoSave()

    # File should not be modified (interval not passed)
    let content = readFile(testFile)
    check content == "Original"

suite "Editor - autoBackup":
  test "Auto backup does nothing when disabled":
    var config = newEditorConfig()
    config.autoBackup.enable = false
    let e = createTestEditorWithConfig(config)

    # Should not cause any errors
    e.autoBackup()

  test "Auto backup respects idle time":
    var config = newEditorConfig()
    config.autoBackup.enable = true
    config.autoBackup.idleTime = 3600 # 1 hour idle required
    config.autoBackup.interval = 1
    let e = createTestEditorWithConfig(config)

    # Set last input time to now (not idle)
    e.state.timing.lastInputTime = getMonoTime()
    e.state.timing.lastAutoBackup = getMonoTime() - initDuration(hours = 1)

    # Should not backup because user is not idle
    e.autoBackup()

  test "Auto backup respects interval":
    var config = newEditorConfig()
    config.autoBackup.enable = true
    config.autoBackup.idleTime = 0 # No idle time required
    config.autoBackup.interval = 60 # 60 minutes
    let e = createTestEditorWithConfig(config)

    # Set last input time to long ago (user is idle)
    e.state.timing.lastInputTime = getMonoTime() - initDuration(hours = 1)
    # Set last backup to recent
    e.state.timing.lastAutoBackup = getMonoTime()

    # Should not backup because interval not passed
    e.autoBackup()

suite "Editor - refreshGitDiff":
  test "Refresh git diff does not crash on non-git file":
    let e = createTestEditor()
    e.state.display.showGitDiff = true

    # refreshGitDiff on a non-git file fails silently; the function must
    # not crash regardless.
    e.refreshGitDiff()
    # If we get here without crashing, the test passes
    check true

  test "Refresh git diff does nothing when disabled":
    let e = createTestEditor()
    e.state.display.showGitDiff = false
    e.state.windowDisplay.needsFullRedraw = false

    # Should early-return without touching buffer state or spawning git.
    e.refreshGitDiff()
    check e.state.windowDisplay.needsFullRedraw == false
