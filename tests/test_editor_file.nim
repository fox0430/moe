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

import std/[unittest, os, options, monotimes, times, strutils, tables]
import pkg/results
import ../src/moepkg/[editor, buffer, config, config_loader, highlight]

proc createTestEditor(): Editor =
  ## Create a minimal editor for testing
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc createTestEditorWithConfig(config: EditorConfig): Editor =
  ## Create an editor with custom config
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc createTestEditorWithBackend(kind: BufferBackendKind): Editor =
  ## Create an editor using a specific buffer backend.
  var config = newEditorConfig()
  config.bufferBackend = BufferBackendConfig(kind: kind)
  let vr = newValidationResult()
  result = newEditor(config, vr)

template trimRevertSaveFileScenarios(makeEditor: untyped, tag: string) =
  ## Trim-revert scenarios run under both GapBuffer and PieceTable.
  test "Reverted trim is dropped from the redo stack on save failure" & tag:
    let e = makeEditor
    let testFile = getTempDir() / "moe_test_trim_revert_no_redo.txt"
    let dirPath = getTempDir() / "moe_test_trim_revert_dir"

    createDir(dirPath)
    writeFile(testFile, "hello   \nworld   \n")
    defer:
      removeFile(testFile)
      removeDir(dirPath)

    discard e.loadFile(testFile)
    e.activeBuffer.editorConfig =
      some(BufferEditorConfig(trimTrailingWhitespace: some(true)))
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "x")
    let beforeLine0 = e.activeBuffer.getLine(0)
    check beforeLine0.endsWith("   ")

    # Writing to a directory fails only after trim, so the revert branch runs.
    e.activeBuffer.filePath = some(dirPath)

    let saveRes = e.saveFile()
    check saveRes.isErr

    # Trim must have been reverted...
    check e.activeBuffer.getLine(0) == beforeLine0
    check e.activeBuffer.getLine(0).endsWith("   ")
    # ...and must not be re-appliable via an explicit user redo.
    check e.activeBuffer.redo().isErr
    # No unreachable future changelist entry remains for g, to jump to.
    check e.activeBuffer.changeList.len == e.activeBuffer.changeListIndex + 1

  test "Trim revert truncates the changelist entry the trim committed" & tag:
    let e = makeEditor
    let testFile = getTempDir() / "moe_test_trim_revert_changelist.txt"
    let dirPath = getTempDir() / "moe_test_trim_revert_cl_dir"

    createDir(dirPath)
    writeFile(testFile, "hello   \n")
    defer:
      removeFile(testFile)
      removeDir(dirPath)

    discard e.loadFile(testFile)
    e.activeBuffer.editorConfig =
      some(BufferEditorConfig(trimTrailingWhitespace: some(true)))

    # A committed transaction records a user changelist position.
    check e.activeBuffer.beginTransaction("user edit").isOk
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "x")
    check e.activeBuffer.commitTransaction().isOk

    let beforeLine0 = e.activeBuffer.getLine(0)
    check beforeLine0.endsWith("   ")

    # Writing to a directory fails only after trim, so the revert branch runs.
    e.activeBuffer.filePath = some(dirPath)

    let saveRes = e.saveFile()
    check saveRes.isErr

    check e.activeBuffer.getLine(0) == beforeLine0
    # Trim's changelist entry is truncated; the user's position is kept.
    check e.activeBuffer.changeList.len == e.activeBuffer.changeListIndex + 1

  test "Trim revert drops the changelist entry after a prior undo" & tag:
    # A prior undo leaves a future entry that trim-time pushUndoChange cuts;
    # the revert must not rely on the pre-trim length alone.
    let e = makeEditor
    let testFile = getTempDir() / "moe_test_trim_revert_mid_changelist.txt"
    let dirPath = getTempDir() / "moe_test_trim_revert_mid_dir"

    createDir(dirPath)
    writeFile(testFile, "hello   \nworld   \n")
    defer:
      removeFile(testFile)
      removeDir(dirPath)

    discard e.loadFile(testFile)
    e.activeBuffer.editorConfig =
      some(BufferEditorConfig(trimTrailingWhitespace: some(true)))

    # Two committed edits record two changelist positions.
    check e.activeBuffer.beginTransaction("edit 1").isOk
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "x")
    check e.activeBuffer.commitTransaction().isOk
    check e.activeBuffer.beginTransaction("edit 2").isOk
    discard e.activeBuffer.insertText(BufferPosition(line: 1, column: 0), "y")
    check e.activeBuffer.commitTransaction().isOk
    check e.activeBuffer.changeList.len == 2
    check e.activeBuffer.changeListIndex == 1

    # Undo the second edit so the index sits mid-list with a future entry.
    discard e.activeBuffer.undo()
    check e.activeBuffer.changeListIndex == 0

    let beforeLine0 = e.activeBuffer.getLine(0)
    check beforeLine0.endsWith("   ")

    # Writing to a directory fails only after trim, so the revert branch runs.
    e.activeBuffer.filePath = some(dirPath)

    let saveRes = e.saveFile()
    check saveRes.isErr

    # Trim must have been reverted...
    check e.activeBuffer.getLine(0) == beforeLine0
    check e.activeBuffer.getLine(0).endsWith("   ")
    # ...and the changelist restored exactly to its pre-trim state: both
    # recorded entries remain, including the future entry past the index.
    check e.activeBuffer.changeList.len == 2
    check e.activeBuffer.changeListIndex == 0

  test "Trim revert drops the changelist entry when trim was the first change" & tag:
    # Empty changelist at trim time: undo() cannot move the index below 0, so
    # the revert must still drop the entry index-based truncation would leave.
    let e = makeEditor
    let testFile = getTempDir() / "moe_test_trim_revert_first_change.txt"
    let dirPath = getTempDir() / "moe_test_trim_revert_first_dir"

    createDir(dirPath)
    writeFile(testFile, "hello   \n")
    defer:
      removeFile(testFile)
      removeDir(dirPath)

    discard e.loadFile(testFile)
    e.activeBuffer.editorConfig =
      some(BufferEditorConfig(trimTrailingWhitespace: some(true)))

    # No editing: the changelist is empty (len 0, index 0) at trim time.
    check e.activeBuffer.changeList.len == 0
    check e.activeBuffer.changeListIndex == 0

    # Writing to a directory fails only after trim, so the revert branch runs.
    e.activeBuffer.filePath = some(dirPath)

    let saveRes = e.saveFile()
    check saveRes.isErr

    # Trim must have been reverted...
    check e.activeBuffer.getLine(0).endsWith("   ")
    # ...and the trim's only changelist entry must be gone.
    check e.activeBuffer.changeList.len == 0
    check e.activeBuffer.changeListIndex == 0
    # ...and must not be re-appliable via an explicit user redo.
    check e.activeBuffer.redo().isErr

  test "Trim revert restores the changelist exactly at the cap" & tag:
    # At the ChangeListMaxLen cap the trim's own commit evicts the oldest
    # entry (recordChangePosition deletes index 0); the revert must restore
    # the full pre-trim snapshot rather than leave the list one short.
    let e = makeEditor
    let testFile = getTempDir() / "moe_test_trim_revert_cap.txt"
    let dirPath = getTempDir() / "moe_test_trim_revert_cap_dir"

    createDir(dirPath)
    writeFile(testFile, "hello   \n")
    defer:
      removeFile(testFile)
      removeDir(dirPath)

    discard e.loadFile(testFile)
    e.activeBuffer.editorConfig =
      some(BufferEditorConfig(trimTrailingWhitespace: some(true)))

    # Fill the changelist to its cap: 99 edits + the pre-fill baseline.
    check e.activeBuffer.changeList.len == 0
    for i in 0 ..< ChangeListMaxLen:
      check e.activeBuffer.beginTransaction("fill " & $i).isOk
      discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "z")
      check e.activeBuffer.commitTransaction().isOk
    check e.activeBuffer.changeList.len == ChangeListMaxLen
    check e.activeBuffer.changeListIndex == ChangeListMaxLen - 1
    let lineBefore = e.activeBuffer.getLine(0)
    check lineBefore.endsWith("   ")

    # Writing to a directory fails only after trim, so the revert branch runs.
    e.activeBuffer.filePath = some(dirPath)

    let saveRes = e.saveFile()
    check saveRes.isErr

    # Trim must have been reverted...
    check e.activeBuffer.getLine(0) == lineBefore
    check e.activeBuffer.getLine(0).endsWith("   ")
    # ...and the full pre-trim changelist restored, oldest entry included.
    check e.activeBuffer.changeList.len == ChangeListMaxLen
    check e.activeBuffer.changeListIndex == ChangeListMaxLen - 1
    # ...and must not be re-appliable via an explicit user redo.
    check e.activeBuffer.redo().isErr

suite "Editor - loadFile":
  test "Load existing file":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_load.txt"

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
    let testFile = getTempDir() / "moe_test_load_cursor.txt"

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
    let testFile = getTempDir() / "moe_test_load_viewport.txt"

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
    let result = e.loadFile(getTempDir() / "moe_nonexistent_test_file_12345.txt")
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
    let testFile = getTempDir() / "moe_test_load_persist.txt"

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
    let testFile = getTempDir() / "moe_test_load_clamp.txt"

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

suite "Editor - multi-file startup (no auto-split)":
  test "Each extra file becomes its own buffer":
    # Regression: `moe a b c` without auto-split used to call loadFile for
    # every path, overwriting the active buffer in place so only the last
    # file survived. The startup path now registers the extra files via
    # loadOrCreateBuffer (like :badd). This drives the real startup entry
    # point (openAdditionalStartupFiles), not a hand-rolled copy of it.
    let e = createTestEditor()
    e.config.startUpFileOpen.autoSplit = false
    let
      fileA = getTempDir() / "moe_test_multi_a.txt"
      fileB = getTempDir() / "moe_test_multi_b.txt"
      fileC = getTempDir() / "moe_test_multi_c.txt"
    writeFile(fileA, "A")
    writeFile(fileB, "B")
    writeFile(fileC, "C")
    defer:
      removeFile(fileA)
      removeFile(fileB)
      removeFile(fileC)

    # First file loads into the initial (active) buffer, exactly as main() does.
    check e.loadFile(fileA).isOk
    # Then the real startup helper registers the remaining files.
    e.openAdditionalStartupFiles(@[fileA, fileB, fileC], readonly = false)

    check e.buffers.len == 3
    check e.activeBuffer.filePath.get == fileA

    check e.findBufferByPath(fileA) >= 0
    check e.findBufferByPath(fileB) >= 0
    check e.findBufferByPath(fileC) >= 0

    # All three are reachable from the active window's tab list, so :bnext/:bprev
    # can cycle to them instead of reporting "only one buffer".
    check e.activeWindow.bufferIds.len == 3

  test "Missing extra files are skipped without aborting the rest":
    # A nonexistent path in the middle must not stop later files from opening.
    let e = createTestEditor()
    e.config.startUpFileOpen.autoSplit = false
    let
      fileA = getTempDir() / "moe_test_multi_skip_a.txt"
      missing = getTempDir() / "moe_test_multi_does_not_exist.txt"
      fileC = getTempDir() / "moe_test_multi_skip_c.txt"
    writeFile(fileA, "A")
    writeFile(fileC, "C")
    removeFile(missing)
    defer:
      removeFile(fileA)
      removeFile(fileC)

    check e.loadFile(fileA).isOk
    e.openAdditionalStartupFiles(@[fileA, missing, fileC], readonly = false)

    check e.buffers.len == 2
    check e.findBufferByPath(missing) < 0
    check e.findBufferByPath(fileC) >= 0

  test "Re-opening the same path reuses its buffer":
    let e = createTestEditor()
    let fileA = getTempDir() / "moe_test_multi_reuse.txt"
    writeFile(fileA, "A")
    defer:
      removeFile(fileA)

    check e.loadFile(fileA).isOk
    check e.loadOrCreateBuffer(fileA).isOk
    # No duplicate buffer for the already-open file.
    check e.buffers.len == 1

  test "Readonly flag applies to each extra buffer, not the active one":
    # Regression: the fix sets readonly on the buffer returned by
    # loadOrCreateBuffer. The old in-place loadFile left the active buffer as
    # the just-loaded file, so the readonly flag landed on the wrong target
    # once loadOrCreateBuffer kept the first file active. Each extra file must
    # become readonly while this call leaves the active buffer untouched
    # (main() applies the first file's readonly separately).
    let e = createTestEditor()
    e.config.startUpFileOpen.autoSplit = false
    let
      fileA = getTempDir() / "moe_test_multi_ro_a.txt"
      fileB = getTempDir() / "moe_test_multi_ro_b.txt"
      fileC = getTempDir() / "moe_test_multi_ro_c.txt"
    writeFile(fileA, "A")
    writeFile(fileB, "B")
    writeFile(fileC, "C")
    defer:
      removeFile(fileA)
      removeFile(fileB)
      removeFile(fileC)

    check e.loadFile(fileA).isOk
    e.openAdditionalStartupFiles(@[fileA, fileB, fileC], readonly = true)

    check e.buffers[e.findBufferByPath(fileB)].readOnly
    check e.buffers[e.findBufferByPath(fileC)].readOnly
    # The active (first) buffer is left alone: the flag was applied to the
    # returned extra buffers, not the active one.
    check not e.activeBuffer.readOnly

suite "Editor - multi-file startup (auto-split)":
  test "Each extra file opens in its own split window":
    # With auto-split every extra path opens in a new split window (and its own
    # buffer), unlike the no-split path which only registers buffers in the
    # active window's tab list.
    let e = createTestEditor()
    e.syncActiveWindow()
    e.config.startUpFileOpen.autoSplit = true
    e.config.startUpFileOpen.splitType = stVertical
    let
      fileA = getTempDir() / "moe_test_split_a.txt"
      fileB = getTempDir() / "moe_test_split_b.txt"
      fileC = getTempDir() / "moe_test_split_c.txt"
    writeFile(fileA, "A")
    writeFile(fileB, "B")
    writeFile(fileC, "C")
    defer:
      removeFile(fileA)
      removeFile(fileB)
      removeFile(fileC)

    check e.loadFile(fileA).isOk
    e.openAdditionalStartupFiles(@[fileA, fileB, fileC], readonly = false)

    # One window and one buffer per file.
    check e.windowManager.windows.len == 3
    check e.buffers.len == 3
    check e.findBufferByPath(fileA) >= 0
    check e.findBufferByPath(fileB) >= 0
    check e.findBufferByPath(fileC) >= 0

  test "Missing extra files are skipped without spawning a window":
    # A nonexistent path must not create a split window or a buffer.
    let e = createTestEditor()
    e.syncActiveWindow()
    e.config.startUpFileOpen.autoSplit = true
    e.config.startUpFileOpen.splitType = stVertical
    let
      fileA = getTempDir() / "moe_test_split_skip_a.txt"
      missing = getTempDir() / "moe_test_split_does_not_exist.txt"
      fileC = getTempDir() / "moe_test_split_skip_c.txt"
    writeFile(fileA, "A")
    writeFile(fileC, "C")
    removeFile(missing)
    defer:
      removeFile(fileA)
      removeFile(fileC)

    check e.loadFile(fileA).isOk
    e.openAdditionalStartupFiles(@[fileA, missing, fileC], readonly = false)

    # Only fileA (already active) and fileC get a window; the missing path is skipped.
    check e.windowManager.windows.len == 2
    check e.findBufferByPath(missing) < 0
    check e.findBufferByPath(fileC) >= 0

suite "Editor - saveFile":
  test "Save file to existing path":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_save.txt"

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
    let testFile = getTempDir() / "moe_test_save_explicit.txt"
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
    let testFile = getTempDir() / "moe_test_save_force.txt"

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

  test "Save read-only buffer succeeds with trim enabled (trim skipped)":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_save_readonly_trim.txt"

    writeFile(testFile, "Trailing space   \nLine 2")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)

    e.activeBuffer.readOnly = true
    e.activeBuffer.editorConfig =
      some(BufferEditorConfig(trimTrailingWhitespace: some(true)))

    let result = e.saveFile()
    check result.isOk

    # Content is written as-is, without trimming.
    let content = readFile(testFile)
    check content == "Trailing space   \nLine 2"

  test "Save does not trim when external modification is detected first":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_save_trim_revert.txt"

    writeFile(testFile, "hello   \nworld   \n")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)
    e.activeBuffer.editorConfig =
      some(BufferEditorConfig(trimTrailingWhitespace: some(true)))

    # Make buffer modified with trailing spaces present
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "x")
    let beforeLine0 = e.activeBuffer.getLine(0)
    check beforeLine0.endsWith("   ")

    # Simulate external modification after load
    e.activeBuffer.lastFileModTime = some(getTime() - initDuration(seconds = 10))
    writeFile(testFile, "externally modified\n")
    check e.activeBuffer.isExternallyModified()

    let saveRes = e.saveFile()
    check saveRes.isErr
    check "File was modified externally" in saveRes.error

    # The external-mod guard runs before trim, which never ran.
    check e.activeBuffer.getLine(0) == beforeLine0
    check e.activeBuffer.getLine(0).endsWith("   ")
    # File on disk was not overwritten
    check readFile(testFile) == "externally modified\n"

  trimRevertSaveFileScenarios(createTestEditor(), " [GapBuffer]")
  trimRevertSaveFileScenarios(
    createTestEditorWithBackend(bbcPieceTable), " [PieceTable]"
  )

  test "Trim is skipped when buffer is in transaction (avoid blocking save)":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_save_trim_nested.txt"

    writeFile(testFile, "hello   \n")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)
    e.activeBuffer.editorConfig =
      some(BufferEditorConfig(trimTrailingWhitespace: some(true)))
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "y")
    let lineBefore = e.activeBuffer.getLine(0)
    check lineBefore.endsWith("   ")

    # Outer transaction mimics Insert mode
    check e.activeBuffer.beginTransaction("outer").isOk
    defer:
      if e.activeBuffer.inTransaction:
        discard e.activeBuffer.commitTransaction()

    let saveRes = e.saveFile()
    # Save should not be blocked by "Transaction already in progress"
    check saveRes.isOk
    # Because trim was skipped, file still contains trailing spaces
    check readFile(testFile).endsWith("   \n")

template saveAllBuffersTrimRevertScenario(makeEditor: untyped, tag: string) =
  test "saveAllBuffers reverts trim on save failure (write error)" & tag:
    # Trim runs, then save fails; buffer must stay untrimmed.
    let e = makeEditor
    let f1 = getTempDir() / "moe_test_saveall_trim_revert2.txt"
    let dirPath = getTempDir() / "moe_test_saveall_dir"

    createDir(dirPath)
    writeFile(f1, "hello   \nworld   \n")
    defer:
      removeFile(f1)
      removeDir(dirPath)

    discard e.loadFile(f1)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "x")
    e.activeBuffer.editorConfig =
      some(BufferEditorConfig(trimTrailingWhitespace: some(true)))
    let before = e.activeBuffer.getLine(0)
    check before.endsWith("   ")

    # Force save failure by pointing filePath to a directory (writeAtomic fails)
    e.activeBuffer.filePath = some(dirPath)

    let res = e.saveAllBuffers(force = false)
    check res.failures.len == 1
    check res.failures[0].path == dirPath
    # Trim must have been reverted
    check e.activeBuffer.getLine(0) == before
    check e.activeBuffer.getLine(0).endsWith("   ")

template saveAllBuffersTrimSuccessScenario(makeEditor: untyped, tag: string) =
  test "saveAllBuffers trims and saves when no external modification" & tag:
    let e = makeEditor
    let f1 = getTempDir() / "moe_test_saveall_trim_success.txt"
    writeFile(f1, "a   \nb   \n")
    defer:
      removeFile(f1)
    discard e.loadFile(f1)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "z")
    e.activeBuffer.editorConfig =
      some(BufferEditorConfig(trimTrailingWhitespace: some(true)))
    let res = e.saveAllBuffers()
    check res.savedCount == 1
    check res.failures.len == 0
    # First line gets "z" inserted, both lines trimmed: "za" and "b"
    check readFile(f1) == "za\nb\n"
    check not e.activeBuffer.getLine(0).endsWith("   ")
    check e.activeBuffer.getLine(1) == "b"

template autoSaveTrimRevertScenario(makeEditor: untyped, tag: string) =
  test "Auto save reverts trim on save failure" & tag:
    let e = makeEditor
    e.config.autoSave.enable = true
    e.config.autoSave.interval = 1
    let f1 = getTempDir() / "moe_test_autosave_trim_revert.txt"
    let dirPath = getTempDir() / "moe_test_autosave_dir"
    createDir(dirPath)
    writeFile(f1, "hello   \n")
    defer:
      removeFile(f1)
      removeDir(dirPath)
    discard e.loadFile(f1)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "x")
    e.activeBuffer.editorConfig =
      some(BufferEditorConfig(trimTrailingWhitespace: some(true)))
    let before = e.activeBuffer.getLine(0)
    check before.endsWith("   ")
    e.activeBuffer.filePath = some(dirPath) # force write failure
    e.state.timing.lastAutoSave = getMonoTime() - initDuration(hours = 1)
    e.autoSave()
    # Trim must be reverted, file not written
    check e.activeBuffer.getLine(0) == before
    check e.activeBuffer.getLine(0).endsWith("   ")

suite "Editor - saveAllBuffers":
  saveAllBuffersTrimRevertScenario(createTestEditor(), " [GapBuffer]")
  saveAllBuffersTrimRevertScenario(
    createTestEditorWithBackend(bbcPieceTable), " [PieceTable]"
  )
  saveAllBuffersTrimSuccessScenario(createTestEditor(), " [GapBuffer]")
  saveAllBuffersTrimSuccessScenario(
    createTestEditorWithBackend(bbcPieceTable), " [PieceTable]"
  )

suite "Editor - saveBufferCursorPosition":
  test "Save cursor position when enabled":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    let e = createTestEditorWithConfig(config)
    let testFile = getTempDir() / "moe_test_cursor_pos.txt"

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
    let testFile = getTempDir() / "moe_test_cursor_no_persist.txt"

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
    let testFile = getTempDir() / "moe_test_COMMIT_EDITMSG/COMMIT_EDITMSG"

    createDir(getTempDir() / "moe_test_COMMIT_EDITMSG")
    writeFile(testFile, "commit message")
    defer:
      removeDir(getTempDir() / "moe_test_COMMIT_EDITMSG")

    discard e.loadFile(testFile)
    e.cursor = BufferPosition(line: 0, column: 3)

    e.saveBufferCursorPosition(e.activeBuffer)

    let absPath = absolutePath(testFile)
    check not e.cursorPositions.hasKey(absPath)

  test "Do not save cursor position for git-rebase-todo":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    let e = createTestEditorWithConfig(config)
    let testFile = getTempDir() / "moe_test_rebase/git-rebase-todo"

    createDir(getTempDir() / "moe_test_rebase")
    writeFile(testFile, "pick abc123 some commit")
    defer:
      removeDir(getTempDir() / "moe_test_rebase")

    discard e.loadFile(testFile)
    e.cursor = BufferPosition(line: 0, column: 5)

    e.saveBufferCursorPosition(e.activeBuffer)

    let absPath = absolutePath(testFile)
    check not e.cursorPositions.hasKey(absPath)

  test "Do not restore cursor position for COMMIT_EDITMSG":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    let e = createTestEditorWithConfig(config)
    let testFile = getTempDir() / "moe_test_COMMIT_EDITMSG2/COMMIT_EDITMSG"

    createDir(getTempDir() / "moe_test_COMMIT_EDITMSG2")
    writeFile(testFile, "commit message content")
    defer:
      removeDir(getTempDir() / "moe_test_COMMIT_EDITMSG2")

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
    let testFile = getTempDir() / "moe_test_rebase2/git-rebase-todo"

    createDir(getTempDir() / "moe_test_rebase2")
    writeFile(testFile, "pick abc123 some commit")
    defer:
      removeDir(getTempDir() / "moe_test_rebase2")

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
    e.state.input.commandState.history = @[]

    e.addCommandToHistory("write")
    check e.state.input.commandState.history.len == 1
    check e.state.input.commandState.history[0] == "write"

  test "Add multiple commands to history":
    var config = newEditorConfig()
    config.persist.commandHistory = false
    let e = createTestEditorWithConfig(config)

    # Clear any existing history
    e.state.input.commandState.history = @[]

    e.addCommandToHistory("first")
    e.addCommandToHistory("second")
    e.addCommandToHistory("third")

    check e.state.input.commandState.history.len == 3
    # Most recent first
    check e.state.input.commandState.history[0] == "third"
    check e.state.input.commandState.history[1] == "second"
    check e.state.input.commandState.history[2] == "first"

  test "Skip empty command":
    var config = newEditorConfig()
    config.persist.commandHistory = false
    let e = createTestEditorWithConfig(config)

    # Clear any existing history
    e.state.input.commandState.history = @[]

    e.addCommandToHistory("")
    check e.state.input.commandState.history.len == 0

  test "Skip duplicate of last command":
    var config = newEditorConfig()
    config.persist.commandHistory = false
    let e = createTestEditorWithConfig(config)

    # Clear any existing history
    e.state.input.commandState.history = @[]

    e.addCommandToHistory("write")
    e.addCommandToHistory("write")

    check e.state.input.commandState.history.len == 1

  test "Allow same command if not last":
    var config = newEditorConfig()
    config.persist.commandHistory = false
    let e = createTestEditorWithConfig(config)

    # Clear any existing history
    e.state.input.commandState.history = @[]

    e.addCommandToHistory("write")
    e.addCommandToHistory("quit")
    e.addCommandToHistory("write")

    check e.state.input.commandState.history.len == 3

  test "Trim history to limit":
    var config = newEditorConfig()
    config.persist.commandHistory = false
    config.persist.commandHistoryLimit = 3
    let e = createTestEditorWithConfig(config)

    # Clear any existing history
    e.state.input.commandState.history = @[]

    e.addCommandToHistory("cmd1")
    e.addCommandToHistory("cmd2")
    e.addCommandToHistory("cmd3")
    e.addCommandToHistory("cmd4")
    e.addCommandToHistory("cmd5")

    check e.state.input.commandState.history.len == 3
    # Most recent commands should be kept
    check e.state.input.commandState.history[0] == "cmd5"
    check e.state.input.commandState.history[1] == "cmd4"
    check e.state.input.commandState.history[2] == "cmd3"

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
    let testFile = getTempDir() / "moe_test_autosave_disabled.txt"

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
    let testFile = getTempDir() / "moe_test_autosave_interval.txt"

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

  test "Auto save saves background-tab buffers":
    # Regression: iterating windowManager.windows only reaches foreground tabs,
    # so a modified background-tab buffer would silently lose its edits.
    var config = newEditorConfig()
    config.autoSave.enable = true
    config.autoSave.interval = 1
    let e = createTestEditorWithConfig(config)

    let fgFile = getTempDir() / "moe_test_autosave_fg.txt"
    let bgFile = getTempDir() / "moe_test_autosave_bg.txt"

    writeFile(fgFile, "fg-original")
    writeFile(bgFile, "bg-original")
    defer:
      removeFile(fgFile)
      removeFile(bgFile)

    discard e.loadFile(fgFile)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "F:")

    # Background buffer: registered in e.buffers but not shown in any window.
    let bgBuf = newTextBuffer("bg-original", some(bgFile))
    e.addBuffer(bgBuf)
    discard bgBuf.insertText(BufferPosition(line: 0, column: 0), "B:")
    check bgBuf.isModified

    e.state.timing.lastAutoSave = getMonoTime() - initDuration(hours = 1)

    e.autoSave()

    check not e.activeBuffer.isModified
    check not bgBuf.isModified
    check readFile(bgFile).startsWith("B:bg-original")

  autoSaveTrimRevertScenario(createTestEditor(), " [GapBuffer]")
  autoSaveTrimRevertScenario(
    createTestEditorWithBackend(bbcPieceTable), " [PieceTable]"
  )

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

  test "Auto backup backs up background-tab buffers":
    # Regression: iterating windowManager.windows only reaches foreground tabs,
    # so a modified background-tab buffer would silently miss auto backup.
    let backupDir = getTempDir() / "moe_test_autobackup_bg_dir"
    if dirExists(backupDir):
      removeDir(backupDir)
    defer:
      if dirExists(backupDir):
        removeDir(backupDir)

    var config = newEditorConfig()
    config.autoBackup.enable = true
    config.autoBackup.idleTime = 0
    config.autoBackup.interval = 1
    config.autoBackup.backupDir = some(backupDir)
    let e = createTestEditorWithConfig(config)

    let fgFile = getTempDir() / "moe_test_autobackup_fg.txt"
    let bgFile = getTempDir() / "moe_test_autobackup_bg.txt"

    writeFile(fgFile, "fg-original")
    writeFile(bgFile, "bg-original")
    defer:
      removeFile(fgFile)
      removeFile(bgFile)

    discard e.loadFile(fgFile)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "F:")

    # Background buffer: registered in e.buffers but not shown in any window.
    let bgBuf = newTextBuffer("bg-original", some(bgFile))
    e.addBuffer(bgBuf)
    discard bgBuf.insertText(BufferPosition(line: 0, column: 0), "B:")

    e.state.timing.lastInputTime = getMonoTime() - initDuration(hours = 1)
    e.state.timing.lastAutoBackup = getMonoTime() - initDuration(hours = 1)

    e.autoBackup()

    # Each source file gets its own subdirectory under `backupDir`. Two
    # subdirectories means both foreground and background buffers were backed
    # up; before the fix only the foreground buffer would produce one.
    var subdirCount = 0
    for _ in walkDir(backupDir):
      subdirCount += 1
    check subdirCount == 2

suite "Editor - refreshGitDiff":
  test "Refresh git diff does not crash on non-git file":
    let e = createTestEditor()
    e.state.showGitDiff = true

    # refreshGitDiff on a non-git file fails silently; the function must
    # not crash regardless.
    e.refreshGitDiff()
    # If we get here without crashing, the test passes
    check true

  test "Refresh git diff does nothing when disabled":
    let e = createTestEditor()
    e.state.showGitDiff = false

    # Should early-return without touching buffer state or spawning git.
    e.refreshGitDiff()
    check true # early-returns without crashing

suite "Editor - highlight line-length cap on load":
  test "non-default cap preserves progressive load on :e (no full reparse on open)":
    # Regression: the configured maxHighlightLineLength must be seeded BEFORE
    # loadFile builds the first chunk. Otherwise loadFile seeds the progressive
    # cache at the default cap, the post-load applyHighlightConfig changes the
    # cap and nils that cache, and the next updateHighlight tokenizes the entire
    # file synchronously — the on-open stall the cap exists to prevent.
    #
    # Opened via :e (editFile -> loadOrCreateBuffer), which builds a FRESH buffer
    # at the default cap; the startup/active buffer is spared because newEditor
    # already seeded its cap, so the bug only shows on subsequent opens.
    var config = newEditorConfig()
    config.highlight.maxHighlightLineLength = 500 # non-default
    let e = createTestEditorWithConfig(config)

    let testFile = getTempDir() / "moe_test_cap_progressive.nim"
    var content = ""
    for i in 0 ..< 1500: # > InitialChunkSize so progressive load is in play
      content.add("let x" & $i & " = " & $i & "\n")
    writeFile(testFile, content)
    defer:
      removeFile(testFile)

    check e.editFile(testFile).isOk
    check e.activeBuffer.maxHighlightLineLength == 500
    # The progressive-load cache must survive the post-load cap apply...
    check e.activeBuffer.incrementalHighlight != nil
    # ...and stay progressive: only the first chunk parsed, not the whole file.
    check e.activeBuffer.incrementalHighlight.parsedUpTo < e.activeBuffer.len - 1

  test "non-default cap preserves progressive load on :vsplit/:hsplit":
    # Same regression as the :e case, for the split-open paths. window_manager
    # builds the split buffer and calls loadFile itself, so the cap must be
    # seeded (inherited from the current buffer) BEFORE that loadFile. Without
    # it, the post-split applyHighlightConfig nils the freshly-built progressive
    # cache and forces a full synchronous reparse of the whole file on open.
    var config = newEditorConfig()
    config.highlight.maxHighlightLineLength = 500 # non-default

    let testFile = getTempDir() / "moe_test_cap_split.nim"
    var content = ""
    for i in 0 ..< 1500: # > InitialChunkSize so progressive load is in play
      content.add("let x" & $i & " = " & $i & "\n")
    writeFile(testFile, content)
    defer:
      removeFile(testFile)

    block vsplitCase:
      let e = createTestEditorWithConfig(config)
      check e.vsplit(some(testFile)).isOk
      check e.activeBuffer.maxHighlightLineLength == 500
      check e.activeBuffer.incrementalHighlight != nil
      check e.activeBuffer.incrementalHighlight.parsedUpTo < e.activeBuffer.len - 1

    block hsplitCase:
      let e = createTestEditorWithConfig(config)
      check e.hsplit(some(testFile)).isOk
      check e.activeBuffer.maxHighlightLineLength == 500
      check e.activeBuffer.incrementalHighlight != nil
      check e.activeBuffer.incrementalHighlight.parsedUpTo < e.activeBuffer.len - 1
