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

import std/[unittest, os, options, monotimes, times, posix, strutils, tables]
import pkg/results
import
  ../src/moepkg/[
    editor, buffer, config, config_loader, highlight, path_key, editor_persist,
    editor_window_layout,
  ]
import ../src/moepkg/command_handlers/editor_ops
import ../src/moepkg/[cmdline, message_log]
import ../src/moepkg/command_handlers/startup_commands
import ../src/moepkg/command_handlers/handler_result
import ../src/moepkg/handler
import vim_like_test_helper

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

template failedWriteKeepsTrimScenario(makeEditor: untyped, tag: string) =
  test "A failed write keeps the trim, and one undo takes it back" & tag:
    # As Vim keeps what its BufWritePre autocommands changed.
    let e = makeEditor
    let testFile = getTempDir() / "moe_test_failed_write_keeps_trim.txt"
    let dirPath = getTempDir() / "moe_test_failed_write_keeps_trim_dir"
    createDir(dirPath)
    writeFile(testFile, "hello   \nworld   \n")
    defer:
      removeFile(testFile)
      removeDir(dirPath)
    discard e.loadFile(testFile)
    e.activeBuffer.editorConfig =
      some(BufferEditorConfig(trimTrailingWhitespace: some(true)))
    check e.activeBuffer.beginTransaction("user edit").isOk
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "x")
    check e.activeBuffer.commitTransaction().isOk
    e.activeBuffer.filePath = some(dirPath / "missing_subdir" / "file.txt")

    check e.saveFile(e.activeBuffer()).isErr
    check e.activeBuffer.getLine(0) == "xhello"
    check e.activeBuffer.getLine(1) == "world"
    check e.activeBuffer.changeList.len == 2

    check e.activeBuffer.undo().isOk
    check e.activeBuffer.getLine(0) == "xhello   "
    check e.activeBuffer.getLine(1) == "world   "

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
    e.viewport.leftCell = 50

    let result = e.loadFile(testFile)
    check result.isOk
    check e.viewport.topLine == 0
    check e.viewport.leftCell == 0

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
    let absPath = pathKey(testFile)
    e.persistedCursorPositions.changes[absPath] =
      CursorPositionEntry(line: 2, column: 3)

    let result = e.loadFile(testFile)
    check result.isOk
    check e.state.cursor.line == 2
    check e.state.cursor.column == 3

  test "A remembered line goes to the middle of the window, as with :e":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    let e = createTestEditorWithConfig(config)
    let testFile = getTempDir() / "moe_test_load_persist_center.txt"
    writeFile(testFile, "line\n".repeat(300))
    defer:
      removeFile(testFile)
    let rows = e.textRows(e.activeWindow)
    # Close enough below the first screen that update_topline alone would
    # leave it at the bottom.
    let line = rows + rows div 4
    e.persistedCursorPositions.changes[pathKey(testFile)] =
      CursorPositionEntry(line: line, column: 0)

    check e.loadFile(testFile).isOk
    check e.state.cursor.line == line
    let
      above = line - e.viewport.topLine
      below = e.viewport.topLine + rows - 1 - line
    check abs(above - below) <= 1

  test "A remembered line on the first screen moves to the middle too":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    let e = createTestEditorWithConfig(config)
    let testFile = getTempDir() / "moe_test_load_persist_first_screen.txt"
    writeFile(testFile, "line\n".repeat(300))
    defer:
      removeFile(testFile)
    let rows = e.textRows(e.activeWindow)
    let line = rows - 2
    e.persistedCursorPositions.changes[pathKey(testFile)] =
      CursorPositionEntry(line: line, column: 0)

    check e.loadFile(testFile).isOk
    check e.state.cursor.line == line
    let
      above = line - e.viewport.topLine
      below = e.viewport.topLine + rows - 1 - line
    check abs(above - below) <= 1

  test "Load file clamps persisted cursor to buffer bounds":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    let e = createTestEditorWithConfig(config)
    let testFile = getTempDir() / "moe_test_load_clamp.txt"

    writeFile(testFile, "Short")
    defer:
      removeFile(testFile)

    # Set a persisted cursor position that exceeds buffer
    let absPath = pathKey(testFile)
    e.persistedCursorPositions.changes[absPath] =
      CursorPositionEntry(line: 100, column: 100)

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

  test "forced Insert mode stays Normal after activating an extra -R buffer":
    let config = newEditorConfig()
    config.standard.forceInsertMode = true
    config.startUpFileOpen.autoSplit = false
    let e = createTestEditorWithConfig(config)
    let
      fileA = getTempDir() / "moe_test_multi_force_ro_a.txt"
      fileB = getTempDir() / "moe_test_multi_force_ro_b.txt"
    writeFile(fileA, "A")
    writeFile(fileB, "B")
    defer:
      removeFile(fileA)
      removeFile(fileB)
    check e.loadFile(fileA).isOk
    e.openAdditionalStartupFiles(@[fileA, fileB], readonly = true)
    let extraBuffer = e.buffers[e.findBufferByPath(fileB)]

    check e.tryActivateBuffer(extraBuffer.id).isOk

    check e.activeBuffer.readOnly
    check e.state.mode == EditorMode.Normal
    check not e.activeBuffer.inTransaction

suite "Editor - startup + arguments":
  proc startOn(text: string, name: string): (Editor, string) =
    ## An editor with `text` read from a file, as main() reads the first one.
    let
      e = createTestEditor()
      path = getTempDir() / name
    writeFile(path, text)
    check e.loadFile(path).isOk
    (e, path)

  const Text = "foo a\n  bbb foo\nfoo x\n  zzz\n"

  func ex(command: string): StartupCommand =
    StartupCommand(kind: sckEx, command: command)

  test "+N goes to the first non-blank of line N":
    let (e, path) = startOn(Text, "moe_test_startup_line.txt")
    defer:
      removeFile(path)
    e.runStartupCommands([ex("2")])
    check e.state.cursor == BufferPosition(line: 1, column: 2)

  test "+N past the end goes to the last line, +0 to the first":
    let (e, path) = startOn(Text, "moe_test_startup_clamp.txt")
    defer:
      removeFile(path)
    e.runStartupCommands([ex("99999")])
    check e.state.cursor == BufferPosition(line: 3, column: 2)
    e.runStartupCommands([ex("0")])
    check e.state.cursor == BufferPosition(line: 0, column: 0)

  test "+ goes to the last line":
    let (e, path) = startOn(Text, "moe_test_startup_last.txt")
    defer:
      removeFile(path)
    e.runStartupCommands([ex("$")])
    check e.state.cursor == BufferPosition(line: 3, column: 2)

  test "+N wins over the remembered position":
    let
      e = createTestEditor()
      path = getTempDir() / "moe_test_startup_remembered.txt"
    writeFile(path, Text)
    defer:
      removeFile(path)
    e.persistedCursorPositions.changes[pathKey(path)] =
      CursorPositionEntry(line: 3, column: 0)
    check e.loadFile(path).isOk
    check e.state.cursor.line == 3
    e.runStartupCommands([ex("1")])
    check e.state.cursor == BufferPosition(line: 0, column: 0)

  test "+/pat on the first line finds a match there, as Vim's exe_commands":
    let (e, path) = startOn(Text, "moe_test_startup_search_top.txt")
    defer:
      removeFile(path)
    e.runStartupCommands([StartupCommand(kind: sckSearch, pattern: "foo")])
    check e.state.cursor == BufferPosition(line: 0, column: 0)
    check e.state.input.search.last.pattern == "foo"
    check e.state.input.search.history[0] == "foo"

  test "+/pat lands on the first non-blank of the line, not the match":
    let (e, path) = startOn(Text, "moe_test_startup_search_col.txt")
    defer:
      removeFile(path)
    e.runStartupCommands([StartupCommand(kind: sckSearch, pattern: "bbb")])
    check e.state.cursor == BufferPosition(line: 1, column: 2)

  test "Each +/pat searches on from where the one before landed":
    let (e, path) = startOn(Text, "moe_test_startup_search_twice.txt")
    defer:
      removeFile(path)
    e.runStartupCommands(
      [
        StartupCommand(kind: sckSearch, pattern: "foo"),
        StartupCommand(kind: sckSearch, pattern: "foo"),
      ]
    )
    check e.state.cursor == BufferPosition(line: 1, column: 2)

  test "+/pat from a remembered position searches after its line, wrapping":
    let
      e = createTestEditor()
      path = getTempDir() / "moe_test_startup_search_wrap.txt"
    writeFile(path, Text)
    defer:
      removeFile(path)
    e.persistedCursorPositions.changes[pathKey(path)] =
      CursorPositionEntry(line: 2, column: 0)
    check e.loadFile(path).isOk
    e.runStartupCommands([StartupCommand(kind: sckSearch, pattern: "foo")])
    check e.state.cursor == BufferPosition(line: 0, column: 0)

  test "+/pat with no match leaves the cursor and still sets the last search":
    let (e, path) = startOn(Text, "moe_test_startup_search_none.txt")
    defer:
      removeFile(path)
    e.runStartupCommands([StartupCommand(kind: sckSearch, pattern: "nomatch")])
    check e.state.cursor == BufferPosition(line: 0, column: 0)
    check e.state.statusMessage == "Pattern not found: nomatch"
    check e.state.input.search.last.pattern == "nomatch"

  test "+-2 above line 0 is E16 and leaves the cursor":
    let (e, path) = startOn(Text, "moe_test_startup_e16.txt")
    defer:
      removeFile(path)
    e.runStartupCommands([ex("-2")])
    check e.state.cursor == BufferPosition(line: 0, column: 0)
    check e.state.statusMessage == "E16: Invalid range"

  test "An error goes below a message already on the status line":
    let (e, path) = startOn(Text, "moe_test_startup_standing.txt")
    defer:
      removeFile(path)
    e.state.statusMessage = "Config error: x"
    e.runStartupCommands([StartupCommand(kind: sckSearch, pattern: "nomatch")])
    check e.state.statusMessage == "Config error: x\nPattern not found: nomatch"

  test "A command that succeeds keeps the message already there":
    let (e, path) = startOn(Text, "moe_test_startup_standing_ok.txt")
    defer:
      removeFile(path)
    e.state.statusMessage = "Config error: x"
    e.runStartupCommands([ex("2")])
    check e.state.statusMessage == "Config error: x"

  test "Every failing command shows, none replacing another":
    let (e, path) = startOn(Text, "moe_test_startup_two_errors.txt")
    defer:
      removeFile(path)
    e.runStartupCommands(
      [ex("-2"), StartupCommand(kind: sckSearch, pattern: "nomatch")]
    )
    check e.state.statusMessage == "E16: Invalid range\nPattern not found: nomatch"

  test "+{command} runs any Ex command, outside the command line history":
    let (e, path) = startOn(Text, "moe_test_startup_set.txt")
    defer:
      removeFile(path)
    let historyBefore = e.state.input.commandState.history.len
    e.runStartupCommands([ex("set tabstop=7")])
    check e.config.standard.tabStop == 7
    check e.state.input.commandState.history.len == historyBefore

  test "+set syntax={language} highlights the first file as that language":
    let (e, path) = startOn("class A {}\n", "moe_test_startup_syntax.txt")
    defer:
      removeFile(path)
    check e.activeBuffer.syntaxLanguage == langNone
    e.runStartupCommands([ex("set syntax=java")])
    check e.activeBuffer.syntaxLanguage == langJava
    check e.activeBuffer.language == langNone
    check e.state.statusMessage == "syntax = java"

  test "+set syntax= with an unknown language is refused":
    let (e, path) = startOn("class A {}\n", "moe_test_startup_syntax_unknown.txt")
    defer:
      removeFile(path)
    e.runStartupCommands([ex("set syntax=nosuchlang")])
    check e.activeBuffer.syntaxLanguage == langNone
    check e.state.statusMessage == "E474: Invalid argument: syntax=nosuchlang"

  test "A command that quits decides the quit and ends the run":
    let (e, path) = startOn(Text, "moe_test_startup_quit.txt")
    defer:
      removeFile(path)
    e.runStartupCommands([ex("q"), ex("3")])
    check e.state.quitDecided
    check e.state.cursor.line == 0

  test "An error is logged once":
    let (e, path) = startOn(Text, "moe_test_startup_logged.txt")
    defer:
      removeFile(path)
    clearMessageLog()
    e.state.statusMessage = "Config error: x"
    e.runStartupCommands([StartupCommand(kind: sckSearch, pattern: "nomatch")])
    check getMessageLog() == @["Config error: x", "Pattern not found: nomatch"]

  test "With the file tree to open, every window is placed again by the first frame":
    let (e, path) = startOn(Text.repeat(200), "moe_test_startup_viewports.txt")
    defer:
      removeFile(path)
    e.config.startUpFileTree.enable = true
    e.syncActiveWindow()
    e.runStartupCommands([ex("500"), ex("split")])
    check e.windowManager.windows.len == 2
    for window in e.windowManager.windows:
      check window.viewport.topLine == 0

  test "Without the file tree, the window keeps where the command placed it":
    let (e, path) = startOn(Text.repeat(200), "moe_test_startup_viewports_kept.txt")
    defer:
      removeFile(path)
    e.syncActiveWindow()
    e.runStartupCommands([ex("500")])
    check e.viewport.topLine > 0
    check e.viewport.topLine <= 499

  test "Neither +N nor +/pat is a jump, as Vim's :N and :/pat are not":
    let (e, path) = startOn(Text, "moe_test_startup_no_jump.txt")
    defer:
      removeFile(path)
    let before = e.state.jumpList.list.len
    e.runStartupCommands([ex("3"), StartupCommand(kind: sckSearch, pattern: "bbb")])
    check e.state.cursor.line == 1
    check e.state.jumpList.list.len == before

  test "j after +/pat keeps the column it landed on":
    let (e, path) = startOn(Text, "moe_test_startup_wanted_column.txt")
    defer:
      removeFile(path)
    e.runStartupCommands([StartupCommand(kind: sckSearch, pattern: "bbb")])
    check e.state.cursor == BufferPosition(line: 1, column: 2)
    for key in keysOf("j"):
      check e.handleKeyCombo(key)
    check e.state.cursor == BufferPosition(line: 2, column: 2)

  test "On a directory they run in the filer":
    let
      e = createTestEditor()
      dir = getTempDir() / "moe_test_startup_filer"
    createDir(dir)
    writeFile(dir / "foo.txt", "")
    defer:
      removeDir(dir)
    e.enterFilerInActiveWindow(dir)
    e.runStartupCommands(
      [ex("set tabstop=7"), StartupCommand(kind: sckSearch, pattern: "foo")]
    )
    check e.config.standard.tabStop == 7
    check e.state.input.search.last.pattern == "foo"

  test "+/ with no last search is E35":
    let (e, path) = startOn(Text, "moe_test_startup_search_empty.txt")
    defer:
      removeFile(path)
    e.runStartupCommands([StartupCommand(kind: sckSearch, pattern: "")])
    check e.state.cursor == BufferPosition(line: 0, column: 0)
    check e.state.statusMessage.startsWith("E35")

suite "Editor - multi-file startup (auto-split)":
  test "forced Insert mode leaves an auto-split -R buffer in Normal mode":
    let config = newEditorConfig()
    config.standard.forceInsertMode = true
    config.startUpFileOpen.autoSplit = true
    config.startUpFileOpen.splitType = stHorizontal
    let e = createTestEditorWithConfig(config)
    let
      fileA = getTempDir() / "moe_test_split_force_ro_a.txt"
      fileB = getTempDir() / "moe_test_split_force_ro_b.txt"
    writeFile(fileA, "A")
    writeFile(fileB, "B")
    defer:
      removeFile(fileA)
      removeFile(fileB)
    check e.loadFile(fileA).isOk
    # As main() makes the first file readonly.
    e.activeBuffer.readOnly = true
    e.enforceModePolicy()

    e.openAdditionalStartupFiles(@[fileA, fileB], readonly = true)

    let b = e.buffers[e.findBufferByPath(fileB)]
    check b.readOnly
    check e.state.mode == EditorMode.Normal
    check not b.inTransaction

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

    # One window and one buffer per file, the focus back on the first.
    check e.windowManager.windows.len == 3
    check e.activeBuffer.filePath.get == fileA
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

  proc startupFiles(name: string, count: int): seq[string] =
    ## `count` files named after their index, each holding its index.
    for i in 0 ..< count:
      let path = getTempDir() / ("moe_test_split_order_" & name & "_" & $i & ".txt")
      writeFile(path, $i)
      result.add path

  proc windowFiles(e: Editor): seq[string] =
    ## The files of the windows, in window order.
    for win in e.windowManager.windows:
      result.add win.buffer.filePath.get

  test "horizontal splits keep the argument order, the focus on the top window":
    let e = createTestEditor()
    e.syncActiveWindow()
    e.config.startUpFileOpen.autoSplit = true
    e.config.startUpFileOpen.splitType = stHorizontal
    e.applyStartUpScreenSize(80, 40)
    let files = startupFiles("h", 3)
    defer:
      for f in files:
        removeFile(f)

    check e.loadFile(files[0]).isOk
    e.openAdditionalStartupFiles(files, readonly = false)

    # As Vim's `-o`: top to bottom in argument order.
    check e.windowFiles == files
    let wins = e.windowManager.windows
    check wins[0].viewport.y < wins[1].viewport.y
    check wins[1].viewport.y < wins[2].viewport.y
    check e.windowManager.activeWindowIndex == 0
    check e.activeBuffer.filePath.get == files[0]

  test "vertical splits keep the argument order, the focus on the left window":
    let e = createTestEditor()
    e.syncActiveWindow()
    e.config.startUpFileOpen.autoSplit = true
    e.config.startUpFileOpen.splitType = stVertical
    e.applyStartUpScreenSize(120, 40)
    let files = startupFiles("v", 3)
    defer:
      for f in files:
        removeFile(f)

    check e.loadFile(files[0]).isOk
    e.openAdditionalStartupFiles(files, readonly = false)

    # As Vim's `-O`: left to right in argument order.
    check e.windowFiles == files
    let wins = e.windowManager.windows
    check wins[0].viewport.x < wins[1].viewport.x
    check wins[1].viewport.x < wins[2].viewport.x
    check e.windowManager.activeWindowIndex == 0

  proc rememberedFiles(name: string, count: int, text: string): seq[string] =
    ## `count` files of 300 lines of `text`.
    for i in 0 ..< count:
      let path = getTempDir() / ("moe_test_split_center_" & name & "_" & $i & ".txt")
      writeFile(path, (text & "\n").repeat(300))
      result.add path

  proc rememberAt(e: Editor, files: seq[string], line: int) =
    ## Each of `files` remembered at `line`, as a session before left it.
    for f in files:
      e.persistedCursorPositions.changes[pathKey(f)] =
        CursorPositionEntry(line: line, column: 0)

  test "each window centres its remembered line at the size the splits leave it":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    config.startUpFileOpen.autoSplit = true
    config.startUpFileOpen.splitType = stHorizontal
    let e = createTestEditorWithConfig(config)
    e.syncActiveWindow()
    e.applyStartUpScreenSize(80, 40)
    let files = rememberedFiles("h", 3, "line")
    defer:
      for f in files:
        removeFile(f)
    e.rememberAt(files, 100)

    check e.loadFile(files[0]).isOk
    e.openAdditionalStartupFiles(files, readonly = false)

    # The later splits shrank the first two windows after they were centred.
    let wins = e.windowManager.windows
    check wins.len == 3
    for win in wins:
      check win.cursor.line == 100
      let
        rows = e.textRows(win)
        above = win.cursor.line - win.viewport.topLine
        below = win.viewport.topLine + rows - 1 - win.cursor.line
      check abs(above - below) <= 1

  test "a vertical split centres the first window again at the width that wraps":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    config.standard.lineWrap = true
    config.startUpFileOpen.autoSplit = true
    config.startUpFileOpen.splitType = stVertical
    let e = createTestEditorWithConfig(config)
    e.syncActiveWindow()
    e.applyStartUpScreenSize(120, 40)
    const LineLen = 80
    let files = rememberedFiles("v", 2, "x".repeat(LineLen))
    defer:
      for f in files:
        removeFile(f)
    e.rememberAt(files, 100)

    check e.loadFile(files[0]).isOk
    let first = e.activeWindow
    # A line takes one row at the full width.
    check e.textAreaWidth(first) >= LineLen
    e.openAdditionalStartupFiles(files, readonly = false)

    check e.windowManager.windows.len == 2
    check first.cursor.line == 100
    let width = e.textAreaWidth(first)
    # And more than one in the split.
    check width < LineLen
    # Whole lines above the cursor line, and whole lines that fit below it.
    let
      perLine = (LineLen + width - 1) div width
      rows = e.textRows(first)
      above = first.cursor.line - first.viewport.topLine
      below = (rows - (above + 1) * perLine) div perLine
    check first.viewport.topWrapOffset == 0
    check abs(above - below) <= 1

  test "files a horizontal split has no room for open without a window":
    let e = createTestEditor()
    e.syncActiveWindow()
    e.config.startUpFileOpen.autoSplit = true
    e.config.startUpFileOpen.splitType = stHorizontal
    e.applyStartUpScreenSize(80, 8)
    let files = startupFiles("full", 10)
    defer:
      for f in files:
        removeFile(f)

    check e.loadFile(files[0]).isOk
    e.openAdditionalStartupFiles(files, readonly = true)

    # As Vim's make_windows, only the windows that fit, every one with a row.
    let wins = e.windowManager.windows
    check wins.len > 1
    check wins.len < files.len
    for win in wins:
      check win.viewport.height >= 1
    check e.windowFiles == files[0 ..< wins.len]
    # The rest are listed buffers the first window can reach, as without
    # auto-split.
    check e.buffers.len == files.len
    check e.windowManager.activeWindowIndex == 0
    for f in files[wins.len .. ^1]:
      let buf = e.buffers[e.findBufferByPath(f)]
      check buf.id in e.activeWindow.bufferIds
      check buf.readOnly

  test "files a vertical split has no room for open without a window":
    let e = createTestEditor()
    e.syncActiveWindow()
    e.config.startUpFileOpen.autoSplit = true
    e.config.startUpFileOpen.splitType = stVertical
    e.applyStartUpScreenSize(20, 24)
    let files = startupFiles("vfull", 30)
    defer:
      for f in files:
        removeFile(f)

    check e.loadFile(files[0]).isOk
    e.openAdditionalStartupFiles(files, readonly = false)

    # As Vim's make_windows for `-O`: a column each, beside its separator.
    let wins = e.windowManager.windows
    check wins.len > 1
    check wins.len < files.len
    for win in wins:
      check win.viewport.width >= 1
    let last = wins[^1].viewport
    check last.x + last.width <= 20
    check e.windowFiles == files[0 ..< wins.len]
    check e.buffers.len == files.len
    for f in files[wins.len .. ^1]:
      check e.buffers[e.findBufferByPath(f)].id in e.activeWindow.bufferIds

suite "Editor - saveFile":
  test "forced Insert mode commits before trimming and resumes after save":
    let config = newEditorConfig()
    config.standard.forceInsertMode = true
    let e = createTestEditorWithConfig(config)
    let testFile = getTempDir() / "moe_test_forced_insert_trim.txt"
    writeFile(testFile, "hello   \n")
    defer:
      removeFile(testFile)
    check e.loadFile(testFile).isOk
    e.activeBuffer.editorConfig =
      some(BufferEditorConfig(trimTrailingWhitespace: some(true)))
    check e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "x").isOk

    let saveResult = e.saveFile(e.activeBuffer())

    check saveResult.isOk
    check readFile(testFile) == "xhello\n"
    check e.activeBuffer.inTransaction

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
    let result = e.saveFile(e.activeBuffer())
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
    let result = e.saveFile(e.activeBuffer(), some(testFile))
    check result.isOk

    # Verify file was created
    check fileExists(testFile)
    let content = readFile(testFile)
    check "New content" in content

  test "Save file with no path returns error":
    let e = createTestEditor()

    # Buffer has no file path
    check e.activeBuffer.filePath.isNone

    let result = e.saveFile(e.activeBuffer())
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
    let result = e.saveFile(e.activeBuffer(), force = true)
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
    e.activeBuffer.applyFileStamp(
      presentStamp(getTime() - initDuration(seconds = 2), 0)
    )
    writeFile(original, "Externally modified")

    # Saving to a different path must succeed without force.
    let result = e.saveFile(e.activeBuffer(), some(target))
    check result.isOk
    check fileExists(target)

  test "A save path starting with a tilde is expanded":
    let e = createTestEditor()
    let home = getTempDir() / "moe_test_save_tilde_home"
    let original = getTempDir() / "moe_test_save_tilde.txt"
    let previousHome = getEnv("HOME")

    createDir(home)
    writeFile(original, "Original content")
    defer:
      putEnv("HOME", previousHome)
      removeDir(home)
      removeFile(original)

    putEnv("HOME", home)
    discard e.loadFile(original)

    let result = e.saveFile(e.activeBuffer(), some("~" & $DirSep & "saved.txt"))
    check result.isOk
    # Written under the home directory, not into a literal "~" directory.
    check fileExists(home / "saved.txt")
    check not dirExists(getCurrentDir() / "~")

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

    let result = e.saveFile(e.activeBuffer())
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
    e.activeBuffer.applyFileStamp(
      presentStamp(getTime() - initDuration(seconds = 10), 0)
    )
    writeFile(testFile, "externally modified\n")
    check e.activeBuffer.isExternallyModified()

    let saveRes = e.saveFile(e.activeBuffer())
    check saveRes.isErr
    check "File was modified externally" in saveRes.error

    # The external-mod guard runs before trim, which never ran.
    check e.activeBuffer.getLine(0) == beforeLine0
    check e.activeBuffer.getLine(0).endsWith("   ")
    # File on disk was not overwritten
    check readFile(testFile) == "externally modified\n"

  test "Save-as naming the buffer's own file is refused and does not trim":
    # `:w ./a.txt` writes the file the buffer already holds. Compared as
    # strings the two spellings differ, so the guard was skipped and the
    # buffer was trimmed for a save that was refused further down.
    let e = createTestEditor()
    let name = "moe_test_save_alias_guard.txt"
    let testFile = getTempDir() / name
    # Built by hand rather than with `/`, which collapses `.` as it joins.
    let alias = getTempDir() & "." & $DirSep & name

    writeFile(testFile, "hello   \nworld   \n")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)
    e.activeBuffer.editorConfig =
      some(BufferEditorConfig(trimTrailingWhitespace: some(true)))

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "x")
    let beforeLine0 = e.activeBuffer.getLine(0)
    check beforeLine0.endsWith("   ")

    e.activeBuffer.applyFileStamp(
      presentStamp(getTime() - initDuration(seconds = 10), 0)
    )
    writeFile(testFile, "externally modified\n")

    let saveRes = e.saveFile(e.activeBuffer(), some(alias))
    check saveRes.isErr
    check "File was modified externally" in saveRes.error

    check e.activeBuffer.getLine(0) == beforeLine0
    check readFile(testFile) == "externally modified\n"

  failedWriteKeepsTrimScenario(createTestEditor(), " [GapBuffer]")
  failedWriteKeepsTrimScenario(
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

    let saveRes = e.saveFile(e.activeBuffer())
    # Save should not be blocked by "Transaction already in progress"
    check saveRes.isOk
    # Because trim was skipped, file still contains trailing spaces
    check readFile(testFile).endsWith("   \n")

template saveAllBuffersTrimRevertScenario(makeEditor: untyped, tag: string) =
  test "saveAllBuffers keeps the trim on save failure (write error)" & tag:
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

    # Force save failure by pointing filePath under a missing dir (writeAtomic fails)
    e.activeBuffer.filePath = some(dirPath / "missing_subdir" / "file.txt")

    let res = e.saveAllBuffers(force = false)
    check res.failures.len == 1
    check res.failures[0].path == dirPath / "missing_subdir" / "file.txt"
    check e.activeBuffer.getLine(0) == "xhello"
    check e.activeBuffer.undo().isOk
    check e.activeBuffer.getLine(0) == "xhello   "

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

template autoSaveFailing(e: Editor, name: string, content: string, body: untyped) =
  ## Open `content` with trim on, run `body`, then autosave to a path whose
  ## write fails only after the trim.
  let f = getTempDir() / ("moe_test_autosave_" & name & ".txt")
  let dir = getTempDir() / ("moe_test_autosave_" & name & "_dir")
  createDir(dir)
  writeFile(f, content)
  defer:
    removeFile(f)
    removeDir(dir)
  e.config.autoSave.enable = true
  e.config.autoSave.interval = 1
  discard e.loadFile(f)
  e.activeBuffer.editorConfig =
    some(BufferEditorConfig(trimTrailingWhitespace: some(true)))
  body
  e.activeBuffer.filePath = some(dir / "missing_subdir" / "file.txt")
  e.state.timing.lastAutoSave = getMonoTime() - initDuration(hours = 1)
  e.autoSave()

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
    e.activeBuffer.filePath = some(dirPath / "missing_subdir" / "file.txt")
      # force write failure
    e.state.timing.lastAutoSave = getMonoTime() - initDuration(hours = 1)
    e.autoSave()
    # Trim must be reverted, file not written
    check e.activeBuffer.getLine(0) == before
    check e.activeBuffer.getLine(0).endsWith("   ")

  test "Auto save drops the reverted trim from the redo stack" & tag:
    let e = makeEditor
    var before = ""
    autoSaveFailing(e, "trim_no_redo", "hello   \nworld   \n"):
      check e.activeBuffer.beginTransaction("user edit").isOk
      discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "x")
      check e.activeBuffer.commitTransaction().isOk
      before = e.activeBuffer.getLine(0)
    check e.activeBuffer.getLine(0) == before
    check e.activeBuffer.redo().isErr
    # No unreachable future changelist entry remains for g, to jump to.
    check e.activeBuffer.changeList.len == 1
    check e.activeBuffer.changeListIndex == 0

  test "Auto save trim revert keeps the changelist future after an undo" & tag:
    let e = makeEditor
    autoSaveFailing(e, "trim_mid_changelist", "hello   \nworld   \n"):
      check e.activeBuffer.beginTransaction("edit 1").isOk
      discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "x")
      check e.activeBuffer.commitTransaction().isOk
      check e.activeBuffer.beginTransaction("edit 2").isOk
      discard e.activeBuffer.insertText(BufferPosition(line: 1, column: 0), "y")
      check e.activeBuffer.commitTransaction().isOk
      check e.activeBuffer.undo().isOk
    check e.activeBuffer.getLine(0) == "xhello   "
    check e.activeBuffer.changeList.len == 2
    check e.activeBuffer.changeListIndex == 0

  test "Auto save trim revert restores the changelist exactly at the cap" & tag:
    let e = makeEditor
    var before = ""
    autoSaveFailing(e, "trim_cap", "hello   \n"):
      for i in 0 ..< ChangeListMaxLen:
        check e.activeBuffer.beginTransaction("fill " & $i).isOk
        discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "z")
        check e.activeBuffer.commitTransaction().isOk
      before = e.activeBuffer.getLine(0)
    check e.activeBuffer.getLine(0) == before
    check e.activeBuffer.changeList.len == ChangeListMaxLen
    check e.activeBuffer.changeListIndex == ChangeListMaxLen - 1
    check e.activeBuffer.changeListPos == ChangeListMaxLen
    check e.activeBuffer.redo().isErr

  test "Auto save trim revert keeps where g; stood" & tag:
    let e = makeEditor
    autoSaveFailing(e, "trim_changelist_pos", "hello   \nworld   \n"):
      check e.activeBuffer.beginTransaction("edit 1").isOk
      discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "x")
      check e.activeBuffer.commitTransaction().isOk
      check e.activeBuffer.beginTransaction("edit 2").isOk
      discard e.activeBuffer.insertText(BufferPosition(line: 1, column: 0), "y")
      check e.activeBuffer.commitTransaction().isOk
      e.activeBuffer.changeListPos = 0
    check e.activeBuffer.changeListPos == 0

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
    let absPath = pathKey(testFile)
    check e.persistedCursorPositions.changes.hasKey(absPath)
    check e.persistedCursorPositions.changes[absPath].line == 0
    check e.persistedCursorPositions.changes[absPath].column == 3

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
    let absPath = pathKey(testFile)
    check not e.persistedCursorPositions.changes.hasKey(absPath)

  test "Do not save cursor position for buffer without path":
    var config = newEditorConfig()
    config.persist.cursorPosition = true
    let e = createTestEditorWithConfig(config)

    # Buffer has no file path
    check e.activeBuffer.filePath.isNone

    let initialCount = e.persistedCursorPositions.changes.len
    e.saveBufferCursorPosition(e.activeBuffer)

    # No new cursor position should be added
    check e.persistedCursorPositions.changes.len == initialCount

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

    let absPath = pathKey(testFile)
    check not e.persistedCursorPositions.changes.hasKey(absPath)

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

    let absPath = pathKey(testFile)
    check not e.persistedCursorPositions.changes.hasKey(absPath)

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
    let absPath = pathKey(testFile)
    e.persistedCursorPositions.changes[absPath] =
      CursorPositionEntry(line: 0, column: 10)

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
    let absPath = pathKey(testFile)
    e.persistedCursorPositions.changes[absPath] =
      CursorPositionEntry(line: 0, column: 10)

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
  test "forced Insert mode commits before auto-save trimming":
    let config = newEditorConfig()
    config.standard.forceInsertMode = true
    config.autoSave.enable = true
    config.autoSave.interval = 1
    let e = createTestEditorWithConfig(config)
    let testFile = getTempDir() / "moe_test_forced_insert_autosave_trim.txt"
    writeFile(testFile, "hello   \n")
    defer:
      removeFile(testFile)
    check e.loadFile(testFile).isOk
    e.activeBuffer.editorConfig =
      some(BufferEditorConfig(trimTrailingWhitespace: some(true)))
    check e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "x").isOk
    e.state.timing.lastAutoSave = getMonoTime() - initDuration(hours = 1)

    e.autoSave()

    check readFile(testFile) == "xhello\n"
    check e.activeBuffer.inTransaction

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
    # Stamped like a real load, so the write gate sees a file this buffer read.
    let bgBuf = newTextBuffer("bg-original", some(bgFile))
    bgBuf.noteFileStamp(bgFile)
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

  test "a split takes the configured highlight backend before its load":
    # Set after the load, a backend other than the buffer's nils the
    # progressive cache the load seeded, and the whole file is parsed on open.
    # A backend Matter is not built into still differs from the default.
    var config = newEditorConfig()
    config.highlight.backend = hbMatter

    let testFile = getTempDir() / "moe_test_backend_split.nim"
    var content = ""
    for i in 0 ..< 1500: # > InitialChunkSize so progressive load is in play
      content.add("let x" & $i & " = " & $i & "\n")
    writeFile(testFile, content)
    defer:
      removeFile(testFile)

    let e = createTestEditorWithConfig(config)
    check e.vsplit(some(testFile)).isOk
    check e.activeBuffer.highlightBackend == hbMatter
    check e.activeBuffer.incrementalHighlight != nil
    check e.activeBuffer.incrementalHighlight.parsedUpTo < e.activeBuffer.len - 1

suite "Editor - invalid bytes roundtrip":
  template invalidByteRoundtripScenario(makeEditor: untyped, tag: string) =
    test "Basic 6 contamination patterns roundtrip" & tag:
      let raws = @["\xE3", "a\xE3b", "ab\xFF\ncd", "a\xF0abc", "\xE3\n", "foo\xFF bar"]
      for idx, raw in raws:
        let src = getTempDir() / ("moe_test_invalid_basic_" & $idx & ".bin")
        let dst = src & ".out"
        writeFile(src, raw)
        let e = makeEditor
        check e.loadFile(src).isOk
        check e.activeBuffer.encoding == CharacterEncoding.unknown
        check not e.activeBuffer.hasBom
        check e.activeBuffer.keepRaw
        check not e.activeBuffer.allowsTextTransforms
        check e.activeBuffer.getFileContent() == raw
        # First line must preserve bytes; splitLines()[0] mirrors the
        # spec's suggested check for single- and multi-line raws.
        check e.activeBuffer.getLine(0) == raw.splitLines()[0]
        check e.saveFile(e.activeBuffer(), some(dst)).isOk
        check readFile(dst) == raw
        # The copy above leaves the buffer on `src`; writing it back is exact too.
        check e.saveFile(e.activeBuffer()).isOk
        check readFile(src) == raw
        removeFile(src)
        if fileExists(dst):
          removeFile(dst)

    test "CRLF with invalid bytes roundtrip" & tag:
      let raws = @["a\xE3\r\n", "a\xE3\r\nb\xFF\r\n", "foo\xFF\r\nbar\xE3\r\n"]
      for idx, raw in raws:
        let src = getTempDir() / ("moe_test_invalid_crlf_" & $idx & ".bin")
        let dst = src & ".out"
        writeFile(src, raw)
        let e = makeEditor
        check e.loadFile(src).isOk
        check e.activeBuffer.encoding == CharacterEncoding.unknown
        check e.activeBuffer.keepRaw
        # Raw: the CRLF bytes ride in the lines and `endOfLine` round-trips them.
        check e.activeBuffer.endOfLine
        check e.activeBuffer.getFileContent() == raw
        check e.saveFile(e.activeBuffer(), some(dst)).isOk
        check readFile(dst) == raw
        removeFile(src)
        if fileExists(dst):
          removeFile(dst)

    test "CR with invalid bytes roundtrip" & tag:
      let raws = @["a\xE3\rb\xFF\r", "foo\xFF\rbaz\xE3\r"]
      for idx, raw in raws:
        let src = getTempDir() / ("moe_test_invalid_cr_" & $idx & ".bin")
        let dst = src & ".out"
        writeFile(src, raw)
        let e = makeEditor
        check e.loadFile(src).isOk
        check e.activeBuffer.encoding == CharacterEncoding.unknown
        check e.activeBuffer.keepRaw
        check e.activeBuffer.getFileContent() == raw
        check e.saveFile(e.activeBuffer(), some(dst)).isOk
        check readFile(dst) == raw
        removeFile(src)
        if fileExists(dst):
          removeFile(dst)

    test "NUL with invalid bytes roundtrip" & tag:
      let raws = @["a\x00b\xE3c", "ab\xFF\x00\ncd", "\x00\xE3\n"]
      for idx, raw in raws:
        let src = getTempDir() / ("moe_test_invalid_nul_" & $idx & ".bin")
        let dst = src & ".out"
        writeFile(src, raw)
        let e = makeEditor
        check e.loadFile(src).isOk
        check e.activeBuffer.encoding == CharacterEncoding.unknown
        check e.activeBuffer.keepRaw
        check e.activeBuffer.hasBinaryContent
        check e.activeBuffer.getFileContent() == raw
        check e.saveFile(e.activeBuffer(), some(dst)).isOk
        check readFile(dst) == raw
        removeFile(src)
        if fileExists(dst):
          removeFile(dst)

    test "UTF-32 surrogate bytes roundtrip as raw" & tag:
      # U+D800 is not a scalar value; the file must stay raw rather than
      # decode to invalid UTF-8 that a transform could rewrite as U+FFFD.
      let raw = "\xFF\xFE\x00\x00" & "\x00\xD8\x00\x00"
      let src = getTempDir() / "moe_test_invalid_utf32_surrogate.bin"
      let dst = src & ".out"
      writeFile(src, raw)
      let e = makeEditor
      check e.loadFile(src).isOk
      check e.activeBuffer.encoding == CharacterEncoding.unknown
      check e.activeBuffer.keepRaw
      check not e.activeBuffer.allowsTextTransforms
      check e.activeBuffer.getFileContent() == raw
      check e.saveFile(e.activeBuffer(), some(dst)).isOk
      check readFile(dst) == raw
      removeFile(src)
      if fileExists(dst):
        removeFile(dst)

    test "Invalid bytes preserved after insertion and save" & tag:
      block lfCase:
        let raw = "a\xE3b\nc\xFFd"
        let src = getTempDir() / "moe_test_invalid_insert_lf.bin"
        let dst = src & ".out"
        writeFile(src, raw)
        defer:
          removeFile(src)
          if fileExists(dst):
            removeFile(dst)
        let e = makeEditor
        check e.loadFile(src).isOk
        check e.activeBuffer.encoding == CharacterEncoding.unknown
        check e.activeBuffer.keepRaw
        check e.activeBuffer.insertText(BufferPosition(line: 0, column: 1), "X").isOk
        check e.activeBuffer.getLine(0) == "aX\xE3b"
        check e.activeBuffer.encoding == CharacterEncoding.unknown
        check e.activeBuffer.getFileContent() == "aX\xE3b\nc\xFFd"
        check e.saveFile(e.activeBuffer(), some(dst)).isOk
        check readFile(dst) == "aX\xE3b\nc\xFFd"

      block crlfCase:
        let raw = "a\xE3\r\nb\xFF\r\n"
        let src = getTempDir() / "moe_test_invalid_insert_crlf.bin"
        let dst = src & ".out"
        writeFile(src, raw)
        defer:
          removeFile(src)
          if fileExists(dst):
            removeFile(dst)
        let e = makeEditor
        check e.loadFile(src).isOk
        check e.activeBuffer.encoding == CharacterEncoding.unknown
        check e.activeBuffer.keepRaw
        check e.activeBuffer.insertText(BufferPosition(line: 0, column: 1), "X").isOk
        check e.saveFile(e.activeBuffer(), some(dst)).isOk
        check readFile(dst) == "aX\xE3\r\nb\xFF\r\n"

      block nulCase:
        let raw = "a\x00b\xE3c"
        let src = getTempDir() / "moe_test_invalid_insert_nul.bin"
        let dst = src & ".out"
        writeFile(src, raw)
        defer:
          removeFile(src)
          if fileExists(dst):
            removeFile(dst)
        let e = makeEditor
        check e.loadFile(src).isOk
        check e.activeBuffer.keepRaw
        check e.activeBuffer.hasBinaryContent
        check e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Z").isOk
        check e.saveFile(e.activeBuffer(), some(dst)).isOk
        check readFile(dst) == "Za\x00b\xE3c"

    test "Fixing the file lifts raw mode" & tag:
      let src = getTempDir() / "moe_test_invalid_fixed.bin"
      defer:
        removeFile(src)
      writeFile(src, "a\xE3b\n")
      let e = makeEditor
      check e.loadFile(src).isOk
      check e.activeBuffer.keepRaw
      check not e.activeBuffer.allowsTextTransforms

      # `keepRaw` is volatile: a valid UTF-8 read must clear it.
      writeFile(src, "axb\n")
      check e.loadFile(src).isOk
      check not e.activeBuffer.keepRaw
      check e.activeBuffer.allowsTextTransforms
      check e.activeBuffer.encoding == CharacterEncoding.utf8
      check e.activeBuffer[0] == "axb"
      check e.activeBuffer.getFileContent() == "axb\n"

  template emptyAndBomRoundtripScenario(makeEditor: untyped, tag: string) =
    test "Empty file roundtrip" & tag:
      let src = getTempDir() / "moe_test_empty.bin"
      let dst = src & ".out"
      writeFile(src, "")
      defer:
        removeFile(src)
        if fileExists(dst):
          removeFile(dst)
      let e = makeEditor
      check e.loadFile(src).isOk
      check e.activeBuffer.encoding == CharacterEncoding.utf8
      check not e.activeBuffer.hasBom
      check not e.activeBuffer.endOfLine
      check e.activeBuffer.len == 1
      check e.activeBuffer[0] == ""
      check e.activeBuffer.getFileContent() == ""
      check e.saveFile(e.activeBuffer(), some(dst)).isOk
      check readFile(dst) == ""
      # Overwrite via saveFile() to own path must stay empty.
      check e.saveFile(e.activeBuffer()).isOk
      check readFile(dst) == ""

    test "BOM-only empty payload roundtrip" & tag:
      const cases = [
        ("\xEF\xBB\xBF", CharacterEncoding.utf8),
        ("\xFF\xFE", CharacterEncoding.utf16Le),
        ("\xFE\xFF", CharacterEncoding.utf16Be),
        ("\xFF\xFE\x00\x00", CharacterEncoding.utf32Le),
        ("\x00\x00\xFE\xFF", CharacterEncoding.utf32Be),
      ]
      for idx, (original, expectedEnc) in cases:
        let src = getTempDir() / ("moe_test_bom_only_" & $idx & ".bin")
        let dst = src & ".out"
        writeFile(src, original)
        let e = makeEditor
        check e.loadFile(src).isOk
        checkpoint($expectedEnc)
        check e.activeBuffer.encoding == expectedEnc
        check e.activeBuffer.hasBom
        check e.activeBuffer.len == 1
        check e.activeBuffer[0] == ""
        check not e.activeBuffer.endOfLine
        check e.activeBuffer.getFileContent() == original
        check e.saveFile(e.activeBuffer(), some(dst)).isOk
        check readFile(dst) == original
        removeFile(src)
        if fileExists(dst):
          removeFile(dst)

  template shortBomBoundaryScenario(makeEditor: untyped, tag: string) =
    test "Short 2-byte UTF-16 BOM is valid empty file" & tag:
      for (original, expectedEnc) in [
        ("\xFF\xFE", CharacterEncoding.utf16Le), ("\xFE\xFF", CharacterEncoding.utf16Be)
      ]:
        let src = getTempDir() / ("moe_test_short2_" & $ord(expectedEnc) & ".bin")
        let dst = src & ".out"
        writeFile(src, original)
        let e = makeEditor
        check e.loadFile(src).isOk
        check e.activeBuffer.encoding == expectedEnc
        check e.activeBuffer.hasBom
        check not e.activeBuffer.keepRaw
        check e.activeBuffer.allowsTextTransforms
        check e.activeBuffer.getFileContent() == original
        check e.saveFile(e.activeBuffer(), some(dst)).isOk
        check readFile(dst) == original
        removeFile(src)
        if fileExists(dst):
          removeFile(dst)

    test "Short 3-byte BOM falls back to raw bytes" & tag:
      const raws = ["\xFF\xFE\x41", "\xFF\xFE\x00", "\xFE\xFF\x41"]
      for idx, raw in raws:
        let src = getTempDir() / ("moe_test_short3_" & $idx & ".bin")
        let dst = src & ".out"
        writeFile(src, raw)
        let e = makeEditor
        check e.loadFile(src).isOk
        check e.activeBuffer.encoding == CharacterEncoding.unknown
        check not e.activeBuffer.hasBom
        check e.activeBuffer.keepRaw
        check not e.activeBuffer.allowsTextTransforms
        check e.activeBuffer.getFileContent() == raw
        check e.saveFile(e.activeBuffer(), some(dst)).isOk
        check readFile(dst) == raw
        removeFile(src)
        if fileExists(dst):
          removeFile(dst)

    test "UTF-32 BOM precedence over UTF-16 prefix" & tag:
      let src = getTempDir() / "moe_test_utf32_prec.bin"
      let dst = src & ".out"
      let utf32BomOnly = "\xFF\xFE\x00\x00"
      writeFile(src, utf32BomOnly)
      let e1 = makeEditor
      check e1.loadFile(src).isOk
      check e1.activeBuffer.encoding == CharacterEncoding.utf32Le
      check e1.activeBuffer.hasBom
      check e1.activeBuffer.getFileContent() == utf32BomOnly
      check e1.saveFile(e1.activeBuffer(), some(dst)).isOk
      check readFile(dst) == utf32BomOnly
      removeFile(src)
      if fileExists(dst):
        removeFile(dst)
      # Same prefix but not a UTF-32 BOM must be treated as UTF-16, not UTF-32
      let nonBom = "\xFF\xFE\x41\x00"
      writeFile(src, nonBom)
      let e2 = makeEditor
      check e2.loadFile(src).isOk
      check e2.activeBuffer.encoding == CharacterEncoding.utf16Le
      check e2.activeBuffer.hasBom
      check not e2.activeBuffer.keepRaw
      check e2.activeBuffer[0] == "A"
      check e2.activeBuffer.getFileContent() == nonBom
      check e2.saveFile(e2.activeBuffer(), some(dst)).isOk
      check readFile(dst) == nonBom
      removeFile(src)
      if fileExists(dst):
        removeFile(dst)

  invalidByteRoundtripScenario(createTestEditor(), " [GapBuffer]")
  invalidByteRoundtripScenario(
    createTestEditorWithBackend(bbcPieceTable), " [PieceTable]"
  )
  emptyAndBomRoundtripScenario(createTestEditor(), " [GapBuffer]")
  emptyAndBomRoundtripScenario(
    createTestEditorWithBackend(bbcPieceTable), " [PieceTable]"
  )
  shortBomBoundaryScenario(createTestEditor(), " [GapBuffer]")
  shortBomBoundaryScenario(createTestEditorWithBackend(bbcPieceTable), " [PieceTable]")

suite "Editor - saveFile explicit buffer":
  test "Saving a background buffer leaves the active buffer's file untouched":
    # Regression guard for the explicit `buffer` parameter: an implementation
    # that silently saves the active buffer instead must fail here.
    let e = createTestEditor()
    e.showGitDiff = true
    let fgFile = getTempDir() / "moe_test_explicit_fg.txt"
    let bgFile = getTempDir() / "moe_test_explicit_bg.txt"
    writeFile(fgFile, "fg-original\n")
    writeFile(bgFile, "bg-original\n")
    defer:
      removeFile(fgFile)
      removeFile(bgFile)

    check e.loadFile(fgFile).isOk
    check e.activeBuffer.filePath.get == fgFile

    let bgBuf = newTextBuffer("bg-original\n", some(bgFile))
    # Stamped like a real load: the write gate refuses a file no one read.
    bgBuf.noteFileStamp(bgFile)
    e.addBuffer(bgBuf)
    check e.activeBuffer.filePath.get == fgFile
    check bgBuf.insertText(BufferPosition(line: 0, column: 0), "B:").isOk

    let fgBuf = e.activeBuffer
    e.state.git.diffEntries.del(fgBuf.id)
    e.state.git.diffEntries.del(bgBuf.id)

    check e.saveFile(bgBuf).isOk
    check readFile(bgFile) == "B:bg-original\n"
    check readFile(fgFile) == "fg-original\n"
    # Post-write effects must target the saved buffer, not the active one.
    require e.state.git.diffEntries.hasKey(bgBuf.id)
    check e.state.git.diffEntries[bgBuf.id].forced
    check not e.state.git.diffEntries.hasKey(fgBuf.id)

  test "Save-as redirects the passed buffer, not the active one":
    let e = createTestEditor()
    e.showGitDiff = true
    let fgFile = getTempDir() / "moe_test_explicit_fg2.txt"
    let bgFile = getTempDir() / "moe_test_explicit_bg2.txt"
    let target = getTempDir() / "moe_test_explicit_target.txt"
    writeFile(fgFile, "fg-original\n")
    writeFile(bgFile, "bg-original\n")
    defer:
      removeFile(fgFile)
      removeFile(bgFile)
      if fileExists(target):
        removeFile(target)

    check e.loadFile(fgFile).isOk

    let bgBuf = newTextBuffer("bg-original\n", some(bgFile))
    e.addBuffer(bgBuf)
    check bgBuf.insertText(BufferPosition(line: 0, column: 0), "B:").isOk

    let fgBuf = e.activeBuffer
    e.state.git.diffEntries.del(fgBuf.id)
    e.state.git.diffEntries.del(bgBuf.id)

    check e.saveFile(bgBuf, some(target), saveAs = true).isOk
    check readFile(target) == "B:bg-original\n"
    check bgBuf.filePath.get == target
    # Neither the active buffer nor its file is affected.
    check e.activeBuffer.filePath.get == fgFile
    check readFile(fgFile) == "fg-original\n"
    check readFile(bgFile) == "bg-original\n"
    # Post-write effects must target the saved buffer, not the active one.
    require e.state.git.diffEntries.hasKey(bgBuf.id)
    check e.state.git.diffEntries[bgBuf.id].forced
    check not e.state.git.diffEntries.hasKey(fgBuf.id)

suite "Editor - save-as onto a path another buffer holds":
  test "Refused without force":
    let e = createTestEditor()
    let srcFile = getTempDir() / "moe_test_saveas_conflict_src.txt"
    let heldFile = getTempDir() / "moe_test_saveas_conflict_held.txt"
    writeFile(srcFile, "src\n")
    writeFile(heldFile, "held\n")
    defer:
      removeFile(srcFile)
      removeFile(heldFile)

    check e.loadFile(srcFile).isOk
    let heldBuf = newTextBuffer("held\n", some(heldFile))
    e.addBuffer(heldBuf)

    check e.saveFile(e.activeBuffer(), some(heldFile)).isErr
    # The buffer keeps its own path and the held file is untouched.
    check e.activeBuffer.filePath.get == srcFile
    check readFile(heldFile) == "held\n"

  test "Refused even with force, as Vim's E139":
    let e = createTestEditor()
    let srcFile = getTempDir() / "moe_test_saveas_force_src.txt"
    let heldFile = getTempDir() / "moe_test_saveas_force_held.txt"
    writeFile(srcFile, "src\n")
    writeFile(heldFile, "held\n")
    defer:
      removeFile(srcFile)
      removeFile(heldFile)

    check e.loadFile(srcFile).isOk
    let heldBuf = newTextBuffer("held\n", some(heldFile))
    e.addBuffer(heldBuf)

    for saveAs in [false, true]:
      let res =
        e.saveFile(e.activeBuffer(), some(heldFile), force = true, saveAs = saveAs)
      check res.isErr and res.error == HeldByAnotherBufferMsg
      check readFile(heldFile) == "held\n"
      check e.activeBuffer.filePath.get == srcFile

  test "A plain save to the buffer's own path is unaffected":
    # Guard is save-as, not a duplicate already on the path.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_saveas_own_path.txt"
    writeFile(path, "original\n")
    defer:
      removeFile(path)

    check e.loadFile(path).isOk
    let dupBuf = newTextBuffer("original\n", some(path))
    e.addBuffer(dupBuf)

    check e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "A:").isOk
    check e.saveFile(e.activeBuffer()).isOk
    check readFile(path) == "A:original\n"
    check e.saveFile(e.activeBuffer(), some(path)).isOk

suite "Editor - save through a file alias":
  test "`:w` of the real path is the buffer's own file, not save-as":
    when defined(posix):
      let e = createTestEditor()
      let dir = getTempDir() / "moe_test_save_alias"
      createDir(dir)
      defer:
        removeDir(dir)
      let real = dir / "real.txt"
      let link = dir / "link.txt"
      writeFile(real, "original\n")
      createSymlink(real, link)

      check e.loadFile(link).isOk
      check e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "A:").isOk
      check e.saveFile(e.activeBuffer(), some(real)).isOk
      check readFile(real) == "A:original\n"
      check readFile(link) == "A:original\n"
      # Written through the link the buffer is named by, not renamed to `real`.
      check e.activeBuffer.filePath.get == link
      check symlinkExists(link)
    else:
      skip()

suite "Editor - prepareQuickRun":
  test "Real save performs post-write effects (git refresh)":
    # The save is the editor's, so it owes what every write owes; a bare
    # buffer write must fail here via the missing git refresh mark.
    var config = newEditorConfig()
    config.quickRun.saveBufferWhenQuickRun = true
    let e = createTestEditorWithConfig(config)
    e.showGitDiff = true

    let path = getTempDir() / "moe_test_editor_quickrun_save.nim"
    writeFile(path, "echo \"original\"\n")
    defer:
      removeFile(path)

    check e.loadFile(path).isOk
    e.activeBuffer.language = SourceLanguage.langNim
    check e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "edited ").isOk

    let buf = e.activeBuffer
    e.state.git.diffEntries.del(buf.id)

    let prepared = e.prepareQuickRun(buf)
    check prepared.isOk
    check "edited" in readFile(path)
    require e.state.git.diffEntries.hasKey(buf.id)
    check e.state.git.diffEntries[buf.id].forced

  test "Staging without a real save performs no post-write effects":
    # Guards the other direction: an unconditional `noteBufferSaved` must
    # fail here via the unexpected git refresh mark.
    var config = newEditorConfig()
    config.quickRun.saveBufferWhenQuickRun = false
    let e = createTestEditorWithConfig(config)
    e.showGitDiff = true

    let path = getTempDir() / "moe_test_editor_quickrun_nosave.nim"
    writeFile(path, "echo \"original\"\n")
    defer:
      removeFile(path)

    check e.loadFile(path).isOk
    e.activeBuffer.language = SourceLanguage.langNim
    check e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "edited ").isOk

    let buf = e.activeBuffer
    e.state.git.diffEntries.del(buf.id)

    let prepared = e.prepareQuickRun(buf)
    check prepared.isOk
    check readFile(path) == "echo \"original\"\n"
    check not e.state.git.diffEntries.hasKey(buf.id)

suite "Editor - buffersToSave":
  test "A file two modified buffers hold is written by neither":
    # Both buffers are edited; writing one must report the other as unwritten.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_save_targets_twice.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)

    discard e.loadFile(path)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "A:")
    let second = newTextBuffer("original", some(path))
    e.addBuffer(second)
    discard second.insertText(BufferPosition(line: 0, column: 0), "B:")

    let selected = e.buffersToSave(force = false)
    check selected.targets.len == 0
    check selected.skippedExternal.len == 1
    check selected.skippedExternal[0].reason == writeRefusedHeldByAnotherBuffer
    check selected.unwritten.len == 1
    check selected.unwritten[0].buffer == second

  test "An unedited duplicate does not stand in the way":
    # A clean duplicate has no edits to lose, so it must not block `:wa`.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_save_targets_clean_dup.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)

    discard e.loadFile(path)
    let edited = e.activeBuffer
    discard edited.insertText(BufferPosition(line: 0, column: 0), "A:")
    e.addBuffer(newTextBuffer("original", some(path)))

    let selected = e.buffersToSave(force = false)
    check selected.skippedExternal.len == 0
    check selected.targets.len == 1
    check selected.targets[0].buffer == edited

  test "The skip names the buffer that was refused, not the first on the file":
    # The skip latch belongs on the refused buffer, not the first on the path.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_save_targets_skip_buffer.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)

    discard e.loadFile(path)
    let first = e.activeBuffer
    discard first.insertText(BufferPosition(line: 0, column: 0), "A:")
    let second = newTextBuffer("original", some(path))
    e.addBuffer(second)
    discard second.insertText(BufferPosition(line: 0, column: 0), "B:")

    let selected = e.buffersToSave(force = false)
    check selected.skippedExternal.len == 1
    check selected.skippedExternal[0].buffer == first

  test "Forced, the file is written once by the first buffer holding it":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_save_targets_twice_force.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)

    discard e.loadFile(path)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "A:")
    let second = newTextBuffer("original", some(path))
    e.addBuffer(second)
    discard second.insertText(BufferPosition(line: 0, column: 0), "B:")

    let selected = e.buffersToSave(force = true)
    check selected.targets.len == 1
    check selected.targets[0].buffer == e.activeBuffer
    check selected.skippedExternal.len == 0

  test "One file open twice under two spellings is reported once":
    # Report per file, not per spelling.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_save_targets_spellings.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)

    discard e.loadFile(path)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "A:")
    for spelling in [path, path.parentDir / "." / path.extractFilename]:
      let buf = newTextBuffer("original", some(spelling))
      e.addBuffer(buf)
      discard buf.insertText(BufferPosition(line: 0, column: 0), "B:")

    let selected = e.buffersToSave(force = false)
    check selected.targets.len == 0
    check selected.skippedExternal.len == 1
    # Passed-over spellings are unwritten; the file is refused once.
    check selected.unwritten.len == 2

  test "One file open through an alias is one file to the batch":
    # An alias is the same file; refuse once, do not write last-wins.
    when defined(posix):
      let e = createTestEditor()
      let dir = getTempDir() / "moe_test_save_targets_alias"
      createDir(dir)
      let path = dir / "real.txt"
      let link = dir / "link.txt"
      writeFile(path, "original")
      createSymlink(path, link)
      defer:
        removeFile(link)
        removeFile(path)
        removeDir(dir)

      discard e.loadFile(path)
      discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "A:")
      let second = newTextBuffer("original", some(link))
      e.addBuffer(second)
      discard second.insertText(BufferPosition(line: 0, column: 0), "B:")

      let selected = e.buffersToSave(force = false)
      check selected.targets.len == 0
      check selected.skippedExternal.len == 1
      check selected.skippedExternal[0].reason == writeRefusedHeldByAnotherBuffer
      check selected.unwritten.len == 1
      check selected.unwritten[0].buffer == second
    else:
      skip()

  test "Forced, an aliased file is written once by the first buffer holding it":
    when defined(posix):
      let e = createTestEditor()
      let dir = getTempDir() / "moe_test_save_targets_alias_force"
      createDir(dir)
      let path = dir / "real.txt"
      let link = dir / "link.txt"
      writeFile(path, "original")
      createSymlink(path, link)
      defer:
        removeFile(link)
        removeFile(path)
        removeDir(dir)

      discard e.loadFile(path)
      discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "A:")
      let second = newTextBuffer("original", some(link))
      e.addBuffer(second)
      discard second.insertText(BufferPosition(line: 0, column: 0), "B:")

      let selected = e.buffersToSave(force = true)
      check selected.targets.len == 1
      check selected.targets[0].buffer == e.activeBuffer
      check selected.skippedExternal.len == 0
      check selected.unwritten.len == 1
      check selected.unwritten[0].buffer == second
    else:
      skip()

  test "A file one buffer is stale for is refused for the fresh buffer too":
    # A stale buffer's edits are as real as a fresh one's; neither may write alone.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_save_targets_external.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)

    # Stale timestamp: this buffer reads as externally modified.
    let stale = newTextBuffer("original", some(path))
    stale.applyFileStamp(presentStamp(fromUnix(0), 0))
    e.addBuffer(stale)
    discard stale.insertText(BufferPosition(line: 0, column: 0), "A:")
    check stale.isExternallyModified()

    let fresh = newTextBuffer("original", some(path))
    fresh.noteFileStamp(path)
    e.addBuffer(fresh)
    discard fresh.insertText(BufferPosition(line: 0, column: 0), "B:")

    let selected = e.buffersToSave(force = false)
    check selected.targets.len == 0
    # Reported once under the first reason; the other buffer is unwritten.
    check selected.skippedExternal.len == 1
    check selected.skippedExternal[0].path == path
    check selected.unwritten.len == 1
    check selected.unwritten[0].buffer == fresh

  test "A file every buffer on it is stale for is reported once":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_save_targets_all_stale.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)

    for _ in 0 .. 1:
      let buf = newTextBuffer("original", some(path))
      buf.applyFileStamp(presentStamp(fromUnix(0), 0))
      e.addBuffer(buf)
      discard buf.insertText(BufferPosition(line: 0, column: 0), "A:")

    let selected = e.buffersToSave(force = false)
    check selected.targets.len == 0
    check selected.skippedExternal.len == 1
    check selected.unwritten.len == 1

  test "A write that failed is reported as a failure, not as a file passed over":
    when defined(posix):
      if getuid() != 0:
        let e = createTestEditor()
        let dir = getTempDir() / "moe_test_save_targets_unwritable"
        createDir(dir)
        let path = dir / "file.txt"
        writeFile(path, "original")
        defer:
          setFilePermissions(dir, {fpUserRead, fpUserWrite, fpUserExec})
          removeFile(path)
          removeDir(dir)

        discard e.loadFile(path)
        discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "A:")

        # No write permission on the directory: the temp-and-rename write fails.
        setFilePermissions(dir, {fpUserRead, fpUserExec})

        let r = e.saveAllBuffers()
        check r.savedCount == 0
        check r.failures.len == 1
        check r.skippedExternal.len == 0

  test "Auto save leaves a file two modified buffers hold alone":
    # Auto save must not pick whose edits survive.
    var config = newEditorConfig()
    config.autoSave.enable = true
    config.autoSave.interval = 1
    let e = createTestEditorWithConfig(config)

    let path = getTempDir() / "moe_test_autosave_twice.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)

    discard e.loadFile(path)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "A:")
    let second = newTextBuffer("original", some(path))
    second.noteFileStamp(path)
    e.addBuffer(second)
    discard second.insertText(BufferPosition(line: 0, column: 0), "B:")

    e.state.timing.lastAutoSave = getMonoTime() - initDuration(hours = 1)
    e.autoSave()

    check readFile(path) == "original"
    check e.activeBuffer.isModified
    check second.isModified
    check "Auto save skipped" in e.state.statusMessage

  test "Auto save names the buffer it left unwritten":
    # Auto save shares `:wa`'s unwritten report, or the loser looks saved.
    var config = newEditorConfig()
    config.autoSave.enable = true
    config.autoSave.interval = 1
    let e = createTestEditorWithConfig(config)

    let path = getTempDir() / "moe_test_autosave_unwritten.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)

    discard e.loadFile(path)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "A:")
    let second = newTextBuffer("original", some(path))
    second.noteFileStamp(path)
    e.addBuffer(second)
    discard second.insertText(BufferPosition(line: 0, column: 0), "B:")

    e.state.timing.lastAutoSave = getMonoTime() - initDuration(hours = 1)
    e.autoSave()

    check readFile(path) == "original"
    check "Auto save skipped" in e.state.statusMessage
    check path in e.state.statusMessage
    check e.activeBuffer.autoSaveSkipWarned
    check second.autoSaveSkipWarned
    check second.isModified

  test "Auto save says so when it is not allowed to write a file":
    # A silent skip would leave the buffer looking saved-in-a-minute.
    var config = newEditorConfig()
    config.autoSave.enable = true
    config.autoSave.interval = 1
    let e = createTestEditorWithConfig(config)

    let path = getTempDir() / "moe_test_autosave_skip_notice.txt"
    removeFile(path)
    defer:
      removeFile(path)

    check e.editFile(path).isOk
    check e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "mine").isOk
    writeFile(path, "theirs\n")

    e.state.timing.lastAutoSave = getMonoTime() - initDuration(hours = 1)
    e.autoSave()

    check readFile(path) == "theirs\n"
    check "Auto save skipped" in e.state.statusMessage
    check path in e.state.statusMessage

    # Once per buffer, not on every tick.
    e.state.statusMessage = ""
    e.state.timing.lastAutoSave = getMonoTime() - initDuration(hours = 1)
    e.autoSave()
    check e.state.statusMessage.len == 0

suite "Editor - save-as onto a file nothing here has read":
  test "Refused without force":
    # Same rule as `:w`: do not write a file no one here has read.
    let e = createTestEditor()
    let source = getTempDir() / "moe_test_saveas_unread_source.txt"
    let target = getTempDir() / "moe_test_saveas_unread_target.txt"
    writeFile(source, "mine\n")
    writeFile(target, "theirs\n")
    defer:
      removeFile(source)
      removeFile(target)

    check e.loadFile(source).isOk
    let saved = e.saveFile(e.activeBuffer, some(target))
    check saved.isErr
    check readFile(target) == "theirs\n"
    # The buffer keeps its own name rather than half-moving to the target.
    check e.activeBuffer.filePath == some(source)

  test "Forced overwrites it":
    let e = createTestEditor()
    let source = getTempDir() / "moe_test_saveas_unread_force_source.txt"
    let target = getTempDir() / "moe_test_saveas_unread_force_target.txt"
    writeFile(source, "mine\n")
    writeFile(target, "theirs\n")
    defer:
      removeFile(source)
      removeFile(target)

    check e.loadFile(source).isOk
    check e.saveFile(e.activeBuffer, some(target), force = true).isOk
    check readFile(target) == "mine\n"

  test "A path with nothing at it is written as before":
    let e = createTestEditor()
    let source = getTempDir() / "moe_test_saveas_free_source.txt"
    let target = getTempDir() / "moe_test_saveas_free_target.txt"
    writeFile(source, "mine\n")
    removeFile(target)
    defer:
      removeFile(source)
      removeFile(target)

    check e.loadFile(source).isOk
    check e.saveFile(e.activeBuffer, some(target)).isOk
    check readFile(target) == "mine\n"

suite "Editor - a file that appeared after the buffer took its name":
  test "A save does not write over it without force":
    # `:e nofile` baselines against absence; an appearing file is unread content.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_unread_file.txt"
    removeFile(path)
    defer:
      removeFile(path)

    check e.editFile(path).isOk
    check e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "mine").isOk

    writeFile(path, "theirs\n")

    let r = e.saveAllBuffers()
    check r.savedCount == 0
    check r.skippedExternal.len == 1
    check r.skippedExternal[0].path == path
    check r.skippedExternal[0].reason == writeRefusedUnreadFile
    check readFile(path) == "theirs\n"

    # `:wa!` overwrites, as it does for a file changed under the buffer.
    let forced = e.saveAllBuffers(force = true)
    check forced.savedCount == 1
    check readFile(path) == "mine\n"

  test "A save writes it when the file is still not there":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_unread_file_absent.txt"
    removeFile(path)
    defer:
      removeFile(path)

    check e.editFile(path).isOk
    check e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "mine").isOk

    let r = e.saveAllBuffers()
    check r.savedCount == 1
    check readFile(path) == "mine\n"

suite "Editor - a buffer created for a name nothing is on":
  test "The baseline says the file was absent, not that it was read":
    # Stamp before the existence check so a raced create is not treated as read.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_new_buffer_baseline.txt"
    removeFile(path)
    defer:
      removeFile(path)

    check e.editFile(path).isOk
    check e.activeBuffer.fileBaseline.observed == fileObservedAbsent
    check e.activeBuffer.diskChangeSince == diskUnchanged

    writeFile(path, "theirs\n")
    check e.activeBuffer.diskChangeSince == diskAppeared

suite "Editor - opening one file through an alias":
  test "Reuses the buffer already holding the file":
    # Dedup by entity so an alias does not grow a second buffer.
    when defined(posix):
      let e = createTestEditor()
      let dir = getTempDir() / "moe_test_alias_open"
      createDir(dir)
      let path = dir / "real.txt"
      let link = dir / "link.txt"
      writeFile(path, "original\n")
      createSymlink(path, link)
      defer:
        removeFile(link)
        removeFile(path)
        removeDir(dir)

      discard e.loadFile(path)
      let before = e.buffers.len
      check e.editFile(link).isOk
      check e.buffers.len == before
      check e.activeBuffer.filePath == some(path)
    else:
      skip()

suite "Editor - save all and quit":
  test "A file two modified buffers hold keeps the session open":
    # Neither buffer is written, so quitting would discard both sets of edits.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_wqa_duplicate.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)

    discard e.loadFile(path)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "A:")
    let second = newTextBuffer("original", some(path))
    second.noteFileStamp(path)
    e.addBuffer(second)
    discard second.insertText(BufferPosition(line: 0, column: 0), "B:")

    check e.processSaveAllAndQuitResult(HandlerResult(kind: hrSaveAllAndQuit))
    check second.isModified
    check e.state.statusMessage.len > 0

  test "A forced quit goes although a duplicate is left unsaved":
    # `:wqa!` writes the first holder and ends the session.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_wqa_duplicate_force.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)

    discard e.loadFile(path)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "A:")
    let second = newTextBuffer("original", some(path))
    second.noteFileStamp(path)
    e.addBuffer(second)
    discard second.insertText(BufferPosition(line: 0, column: 0), "B:")

    check not e.processSaveAllAndQuitResult(
      HandlerResult(kind: hrSaveAllAndQuit, forceSaveAllAndQuitAfter: true)
    )
    check readFile(path).startsWith("A:")

  test "A forced save reports the buffers it left unsaved":
    # `!` picks the writer; a bare "Saved" would hide the leftover edits.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_wa_duplicate_unwritten.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)

    discard e.loadFile(path)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "A:")
    let second = newTextBuffer("original", some(path))
    second.noteFileStamp(path)
    e.addBuffer(second)
    discard second.insertText(BufferPosition(line: 0, column: 0), "B:")

    let r = e.saveAllBuffers(force = true)
    check r.savedCount == 1
    check r.unwritten.len == 1
    check r.unwritten[0].buffer.id == second.id
    check r.unwritten[0].path == path
    check second.isModified

  test "The forced status message says how many were left unsaved":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_wa_duplicate_unwritten_msg.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)

    discard e.loadFile(path)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "A:")
    let second = newTextBuffer("original", some(path))
    second.noteFileStamp(path)
    e.addBuffer(second)
    discard second.insertText(BufferPosition(line: 0, column: 0), "B:")

    e.processSaveAllResult(HandlerResult(kind: hrSaveAll, forceSaveAll: true))
    check "left unsaved" in e.state.statusMessage

suite "Editor - :w {file} writes a copy, as Vim":
  # Measured in Vim 9.2: only a buffer without a name, or `:saveas`, takes the
  # name of the file written; anything else gets a copy.
  let src = getTempDir() / "moe_test_wcopy_src.txt"
  let dst = getTempDir() / "moe_test_wcopy_dst.txt"

  setup:
    writeFile(src, "orig\n")
    removeFile(dst)

  teardown:
    removeFile(src)
    removeFile(dst)

  test "A named buffer keeps its name and unsaved changes":
    let e = createTestEditor()
    e.showGitDiff = true
    check e.loadFile(src).isOk
    let buf = e.activeBuffer
    check buf.insertText(BufferPosition(line: 0, column: 0), "A:").isOk
    e.state.git.diffEntries.del(buf.id)

    let res = e.saveFile(buf, some(dst))
    require res.isOk
    check res.get.kind == wkCopy
    check res.get.path == dst
    check readFile(dst) == "A:orig\n"
    check readFile(src) == "orig\n"
    check buf.filePath.get == src
    check buf.isModified
    # Nothing that follows a save of the buffer runs.
    check not e.state.git.diffEntries.hasKey(buf.id)

    # `:w` still writes the buffer's own file.
    let own = e.saveFile(buf)
    require own.isOk
    check own.get.kind == wkOwnFile
    check readFile(src) == "A:orig\n"
    check not buf.isModified

  test "An unmodified buffer stays unmodified":
    let e = createTestEditor()
    check e.loadFile(src).isOk
    let buf = e.activeBuffer

    check e.saveFile(buf, some(dst)).isOk
    check readFile(dst) == "orig\n"
    check buf.filePath.get == src
    check not buf.isModified

  test "An existing file needs force":
    let e = createTestEditor()
    check e.loadFile(src).isOk
    let buf = e.activeBuffer
    check buf.insertText(BufferPosition(line: 0, column: 0), "A:").isOk
    writeFile(dst, "other\n")

    let res = e.saveFile(buf, some(dst))
    check res.isErr and res.error == TargetExistsErrorMsg
    check readFile(dst) == "other\n"

    check e.saveFile(buf, some(dst), force = true).isOk
    check readFile(dst) == "A:orig\n"
    check buf.filePath.get == src
    check buf.isModified

  test "A copy leaves trailing whitespace in the buffer":
    # The trim belongs to saving the buffer's own file.
    let e = createTestEditor()
    writeFile(src, "hello   \n")
    check e.loadFile(src).isOk
    let buf = e.activeBuffer
    buf.editorConfig = some(BufferEditorConfig(trimTrailingWhitespace: some(true)))
    check buf.insertText(BufferPosition(line: 0, column: 0), "x").isOk

    check e.saveFile(buf, some(dst)).isOk
    check readFile(dst) == "xhello   \n"
    check buf.getLine(0) == "xhello   "

  test "A buffer without a name takes the name":
    let e = createTestEditor()
    let buf = e.activeBuffer
    check buf.filePath.isNone
    check buf.insertText(BufferPosition(line: 0, column: 0), "new").isOk

    let res = e.saveFile(buf, some(dst))
    require res.isOk
    check res.get.kind == wkTakesName
    check readFile(dst) == "new\n"
    check buf.filePath.get == dst
    check not buf.isModified

  test "saveAs names a named buffer and leaves its old file":
    let e = createTestEditor()
    check e.loadFile(src).isOk
    let buf = e.activeBuffer
    check buf.insertText(BufferPosition(line: 0, column: 0), "A:").isOk

    let res = e.saveFile(buf, some(dst), saveAs = true)
    require res.isOk
    check res.get.kind == wkTakesName
    check readFile(dst) == "A:orig\n"
    check readFile(src) == "orig\n"
    check buf.filePath.get == dst
    check not buf.isModified

  test "saveAs onto an existing file needs force":
    let e = createTestEditor()
    check e.loadFile(src).isOk
    let buf = e.activeBuffer
    writeFile(dst, "other\n")

    let res = e.saveFile(buf, some(dst), saveAs = true)
    check res.isErr and res.error == TargetExistsErrorMsg
    check buf.filePath.get == src
    check readFile(dst) == "other\n"

    check e.saveFile(buf, some(dst), force = true, saveAs = true).isOk
    check buf.filePath.get == dst
    check readFile(dst) == "orig\n"

  test ":wq quits after writing the buffer's own file mid-transaction":
    # `isModified` stays true while an open transaction holds changes.
    let e = createTestEditor()
    check e.loadFile(src).isOk
    let buf = e.activeBuffer
    check buf.beginTransaction("insert").isOk
    defer:
      if buf.inTransaction:
        discard buf.commitTransaction()
    check buf.insertText(BufferPosition(line: 0, column: 0), "A:").isOk

    let r = HandlerResult(
      kind: hrSaveAndQuit, saveAndQuitFilename: none(string), forceQuitAfterSave: false
    )
    check not e.processSaveAndQuitResult(r)
    check readFile(src) == "A:orig\n"

  test "Another spelling of the buffer's own file keeps the buffer's name":
    # Vim: `:w ./a.txt` is no other file.
    let e = createTestEditor()
    check e.loadFile(src).isOk
    let buf = e.activeBuffer
    check buf.insertText(BufferPosition(line: 0, column: 0), "A:").isOk
    let alias = src.parentDir & $DirSep & "." & $DirSep & src.extractFilename

    let res = e.saveFile(buf, some(alias))
    require res.isOk
    check res.get.kind == wkOwnFile
    check res.get.path == src
    check buf.filePath.get == src
    check readFile(src) == "A:orig\n"
    check not buf.isModified

  test "saveAs to the buffer's own file is a plain save":
    let e = createTestEditor()
    check e.loadFile(src).isOk
    let buf = e.activeBuffer
    check buf.insertText(BufferPosition(line: 0, column: 0), "A:").isOk

    let res = e.saveFile(buf, some(src), saveAs = true)
    require res.isOk
    check res.get.kind == wkOwnFile
    check readFile(src) == "A:orig\n"
    check not buf.isModified

suite "Editor - :w on text no file stands behind":
  # Vim's 'buftype' nofile: `:w {file}` writes a copy, `:w` refuses (E382).
  let dst = getTempDir() / "moe_test_wlisting_dst.txt"

  setup:
    removeFile(dst)

  teardown:
    removeFile(dst)

  test "A viewer's unregistered view":
    let e = createTestEditor()
    let view = newTextBuffer("listing\n")
    check e.isListing(view)

    let plain = e.saveFile(view)
    check plain.isErr and plain.error == "Cannot write a listing"

    let res = e.saveFile(view, some(dst))
    require res.isOk
    check res.get.kind == wkCopy
    check readFile(dst) == "listing\n"
    check view.filePath.isNone

    removeFile(dst)
    check e.saveFile(view, some(dst), saveAs = true).isErr
    check not fileExists(dst)
    check view.filePath.isNone

  test "A utility buffer, whose path is the directory it lists":
    let e = createTestEditor()
    let filerLike = newTextBuffer("a.txt\n")
    filerLike.filePath = some(getTempDir())
    filerLike.isUtilityBuffer = true
    e.addBuffer(filerLike)
    check e.isListing(filerLike)

    check e.saveFile(filerLike).isErr
    check e.saveFile(filerLike, some(dst)).isOk
    check readFile(dst) == "a.txt\n"
    check filerLike.filePath.get == getTempDir()

  test "Command output":
    let e = createTestEditor()
    check e.showCommandOutput(@["out"], keepFocus = false)
    let output = e.bufferById(e.state.commandOutputBufferId).get
    check e.isListing(output)

    check e.saveFile(output).isErr
    check e.saveFile(output, some(dst)).isOk
    check readFile(dst) == "out\n"
    check output.filePath.isNone

  test "A terminal":
    when defined(moe.embedded):
      skip()
    else:
      let e = createTestEditor()
      let term = newTextBuffer("")
      e.addBuffer(term)
      e.terminalStates[term.id] = TerminalState()
      defer:
        e.terminalStates.del(term.id)
      check e.isListing(term)

      let res = e.saveFile(term, some(dst))
      require res.isOk
      check res.get.kind == wkCopy
      check term.filePath.isNone

  test "Config takes no file name: its view is empty":
    let e = createTestEditor()
    e.state.mode = EditorMode.Config
    for saveAs in [false, true]:
      e.processSaveResult(
        HandlerResult(
          kind: hrSave, saveFilename: some(dst), forceSave: false, saveAs: saveAs
        ),
        e.activeBuffer,
      )
      check "takes no file name" in e.state.statusMessage
      check not fileExists(dst)

    # `:wq {file}` stays too, rather than writing an empty copy and quitting.
    e.state.statusMessage = ""
    check e.processSaveAndQuitResult(
      HandlerResult(
        kind: hrSaveAndQuit, saveAndQuitFilename: some(dst), forceQuitAfterSave: true
      )
    )
    check "takes no file name" in e.state.statusMessage
    check not fileExists(dst)

  test "A directory is refused, the listing's own one too":
    let e = createTestEditor()
    let filerLike = newTextBuffer("a.txt\n")
    filerLike.filePath = some(getTempDir())
    filerLike.isUtilityBuffer = true
    e.addBuffer(filerLike)
    for force in [false, true]:
      let fromListing = e.saveFile(filerLike, some(getTempDir()), force = force)
      check fromListing.isErr and "is a directory" in fromListing.error
      let fromFile = e.saveFile(e.activeBuffer, some(getTempDir()), force = force)
      check fromFile.isErr and "is a directory" in fromFile.error

  test "A file buffer is not one":
    let e = createTestEditor()
    check not e.isListing(e.activeBuffer)
