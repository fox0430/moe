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

## Tests for editor_navigation.nim

import std/[unittest, os, strutils, options, importutils, json, tables]

import ../src/moepkg/[editor, config, config_loader, types, lsp_service]
import ../src/moepkg/buffer/core
import ../src/moepkg/editor_navigation
import ../src/moepkg/lsp/protocol/types as lspTypes

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc createTestEditorWithLspDisabled(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)
  result.lsp.enabled = false

suite "editor_navigation - requestLspGotoDefinition":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspGotoDefinition()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_navigation - requestLspGotoDeclaration":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspGotoDeclaration()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_navigation - requestLspReferences":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspReferences()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_navigation - requestLspTypeDefinition":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspTypeDefinition()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_navigation - requestLspImplementation":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspImplementation()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_navigation - pollLspLocationRequest":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    e.pollLspLocationRequest()
    # No crash means success

  test "Does nothing when no pending request":
    let e = createTestEditor()
    e.lsp.enabled = true

    e.pollLspLocationRequest()
    # No crash means success

suite "editor_navigation - openFileAndJumpTo":
  test "Jumps to location in same file":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_jump_same.txt"

    writeFile(testFile, "line 0\nline 1\nline 2\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    let result = e.openFileAndJumpTo(testFile, 1, 0)

    check result
    check e.cursor.line == 1
    check e.cursor.column == 0

  test "Adds to jump list before jumping":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_jump_list.txt"

    writeFile(testFile, "line 0\nline 1\nline 2\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    let initialJumpListLen = e.state.jumpList.list.len

    discard e.openFileAndJumpTo(testFile, 2, 0)

    check e.state.jumpList.list.len == initialJumpListLen + 1

  test "Opens different file and jumps to location":
    let e = createTestEditor()
    let testFile1 = getTempDir() / "moe_test_jump1.txt"
    let testFile2 = getTempDir() / "moe_test_jump2.txt"

    writeFile(testFile1, "file 1\n")
    writeFile(testFile2, "line 0\nline 1\nline 2\n")
    defer:
      removeFile(testFile1)
      removeFile(testFile2)

    discard e.editFile(testFile1)

    let result = e.openFileAndJumpTo(testFile2, 1, 0)

    check result
    check e.cursor.line == 1

  test "Creates new buffer for nonexistent file":
    # moe treats nonexistent files as new files (no error)
    let e = createTestEditor()

    let result = e.openFileAndJumpTo(getTempDir() / "moe_test_new_file.txt", 0, 0)

    # Should succeed as new file creation
    check result
    check e.cursor.line == 0
    check e.cursor.column == 0

suite "editor_navigation - Jump list":
  test "Jump list does not add duplicate positions":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_jump_dup.txt"

    writeFile(testFile, "line 0\nline 1\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    # Jump to same position twice
    discard e.openFileAndJumpTo(testFile, 0, 0)
    let lenAfterFirst = e.state.jumpList.list.len

    discard e.openFileAndJumpTo(testFile, 0, 0)
    let lenAfterSecond = e.state.jumpList.list.len

    # Should not add duplicate
    check lenAfterFirst == lenAfterSecond

  test "Jump list respects maximum size":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_jump_max.txt"

    var content = ""
    for i in 0 ..< 150:
      content &= "line " & $i & "\n"
    writeFile(testFile, content)
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    # Add many positions to jump list
    for i in 0 ..< 110:
      discard e.openFileAndJumpTo(testFile, i, 0)

    # Jump list should be capped at 100
    check e.state.jumpList.list.len <= 100

suite "editor_navigation - handleLspLocations":
  test "Returns false and sets message when no locations":
    let e = createTestEditor()
    let locations: seq[lspTypes.Location] = @[]

    let result = e.handleLspLocations(locations, "Definitions", "Definition")

    check not result
    check e.state.statusMessage == "No definitions found"

  test "Jumps directly when single location in same file":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_handle_loc.txt"

    writeFile(testFile, "line 0\nline 1\nline 2\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    let loc = lspTypes.Location(
      uri: "file://" & testFile,
      range: lspTypes.Range(
        start: lspTypes.Position(line: 2, character: 0),
        `end`: lspTypes.Position(line: 2, character: 6),
      ),
    )
    let locations = @[loc]

    let result = e.handleLspLocations(locations, "Definitions", "Definition")

    check result
    check e.cursor.line == 2
    check e.state.statusMessage.contains("Definition")

  test "Enters References mode when multiple locations":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_multi_loc.txt"

    writeFile(testFile, "line 0\nline 1\nline 2\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    let loc1 = lspTypes.Location(
      uri: "file://" & testFile,
      range: lspTypes.Range(
        start: lspTypes.Position(line: 0, character: 0),
        `end`: lspTypes.Position(line: 0, character: 6),
      ),
    )
    let loc2 = lspTypes.Location(
      uri: "file://" & testFile,
      range: lspTypes.Range(
        start: lspTypes.Position(line: 2, character: 0),
        `end`: lspTypes.Position(line: 2, character: 6),
      ),
    )
    let locations = @[loc1, loc2]

    let result = e.handleLspLocations(locations, "References", "Reference")

    check result
    check e.state.mode == EditorMode.References
    check e.state.statusMessage.contains("2 references found")

suite "editor_navigation - switchToBufferForLsp":
  test "Does nothing for invalid negative index":
    let e = createTestEditor()
    let initialBufferId = e.state.windowDisplay.currentBufferId

    e.switchToBufferForLsp(-1)

    check e.state.windowDisplay.currentBufferId == initialBufferId

  test "Does nothing for out of bounds index":
    let e = createTestEditor()
    let initialBufferId = e.state.windowDisplay.currentBufferId

    e.switchToBufferForLsp(999)

    check e.state.windowDisplay.currentBufferId == initialBufferId

  test "Switches to valid buffer index":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_switch_lsp.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToBufferForLsp(0)

    check e.state.windowDisplay.currentBufferId == e.buffers[0].id

  test "Does nothing when already on target buffer":
    let e = createTestEditor()
    let initialBufferId = e.state.windowDisplay.currentBufferId
    let initialIndex = e.currentBufferIndex()

    e.switchToBufferForLsp(initialIndex)

    check e.state.windowDisplay.currentBufferId == initialBufferId

suite "editor_navigation - addToJumpList":
  test "Adds position to jump list":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_add_jump.txt"

    writeFile(testFile, "line 0\nline 1\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.cursor = BufferPosition(line: 1, column: 3)
    let initialLen = e.state.jumpList.list.len

    e.addToJumpList()

    check e.state.jumpList.list.len == initialLen + 1
    let lastPos = e.state.jumpList.list[^1]
    check lastPos.line == 1
    check lastPos.column == 3

  test "Does not add duplicate of last position":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_add_jump_dup.txt"

    writeFile(testFile, "line 0\nline 1\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.cursor = BufferPosition(line: 1, column: 3)

    e.addToJumpList()
    let lenAfterFirst = e.state.jumpList.list.len

    e.addToJumpList()
    let lenAfterSecond = e.state.jumpList.list.len

    check lenAfterFirst == lenAfterSecond

  test "Resets jump list index after adding":
    let e = createTestEditor()
    e.state.jumpList.index = 5

    e.addToJumpList()

    check e.state.jumpList.index == -1

suite "editor_navigation - jumpToLspLocation":
  test "Jumps to location in same file":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_jump_lsp_loc.txt"

    writeFile(testFile, "line 0\nline 1\nline 2\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    let loc = lspTypes.Location(
      uri: "file://" & testFile,
      range: lspTypes.Range(
        start: lspTypes.Position(line: 2, character: 3),
        `end`: lspTypes.Position(line: 2, character: 6),
      ),
    )

    let result = e.jumpToLspLocation(loc, "Test")

    check result
    check e.cursor.line == 2
    check e.state.statusMessage.contains("Test")

  test "Opens different file and jumps":
    let e = createTestEditor()
    let testFile1 = getTempDir() / "moe_test_jump_lsp1.txt"
    let testFile2 = getTempDir() / "moe_test_jump_lsp2.txt"

    writeFile(testFile1, "file 1")
    writeFile(testFile2, "line 0\nline 1\nline 2\n")
    defer:
      removeFile(testFile1)
      removeFile(testFile2)

    discard e.editFile(testFile1)

    let loc = lspTypes.Location(
      uri: "file://" & testFile2,
      range: lspTypes.Range(
        start: lspTypes.Position(line: 1, character: 0),
        `end`: lspTypes.Position(line: 1, character: 6),
      ),
    )

    let result = e.jumpToLspLocation(loc, "Definition")

    check result
    check e.cursor.line == 1

  test "Switches to existing buffer instead of reloading":
    let e = createTestEditor()
    let testFile1 = getTempDir() / "moe_test_jump_existing1.txt"
    let testFile2 = getTempDir() / "moe_test_jump_existing2.txt"

    writeFile(testFile1, "file 1")
    writeFile(testFile2, "line 0\nline 1\n")
    defer:
      removeFile(testFile1)
      removeFile(testFile2)

    # Open both files
    discard e.editFile(testFile1)
    discard e.editFile(testFile2)
    let buffersCount = e.buffers.len

    # Switch back to first file
    e.switchToBufferForLsp(0)

    # Jump to second file (should reuse existing buffer)
    let loc = lspTypes.Location(
      uri: "file://" & testFile2,
      range: lspTypes.Range(
        start: lspTypes.Position(line: 1, character: 0),
        `end`: lspTypes.Position(line: 1, character: 6),
      ),
    )

    discard e.jumpToLspLocation(loc, "Test")

    # Should not have added a new buffer
    check e.buffers.len == buffersCount

suite "editor_navigation - relative/absolute path deduplication":
  test "jumpToLspLocation reuses buffer opened with a relative path":
    # Regression: a buffer opened relative ("sub/f.txt") must match the
    # absolute path an LSP server returns, otherwise navigation opens a second
    # buffer for the same file. The duplicate then breaks LSP rename.
    let e = createTestEditor()
    let dir = getTempDir() / "moe_test_relabs"
    createDir(dir / "sub")
    let absPath = dir / "sub" / "f.txt"
    writeFile(absPath, "line 0\nline 1\nline 2\n")
    defer:
      removeDir(dir)

    let prevDir = getCurrentDir()
    setCurrentDir(dir)
    defer:
      setCurrentDir(prevDir)

    # Open with a relative path.
    discard e.editFile("sub/f.txt")
    let buffersCount = e.buffers.len

    # The server reports the same file as an absolute URI.
    let loc = lspTypes.Location(
      uri: "file://" & absPath,
      range: lspTypes.Range(
        start: lspTypes.Position(line: 2, character: 0),
        `end`: lspTypes.Position(line: 2, character: 6),
      ),
    )

    let result = e.jumpToLspLocation(loc, "Definition")

    check result
    check e.cursor.line == 2
    # Must NOT have created a duplicate buffer for the already-open file.
    check e.buffers.len == buffersCount

  test "openFileAndJumpTo reuses buffer opened with a relative path":
    let e = createTestEditor()
    let dir = getTempDir() / "moe_test_relabs2"
    createDir(dir)
    let absPath = dir / "g.txt"
    writeFile(absPath, "a\nb\nc\n")
    defer:
      removeDir(dir)

    let prevDir = getCurrentDir()
    setCurrentDir(dir)
    defer:
      setCurrentDir(prevDir)

    discard e.editFile("g.txt")
    let buffersCount = e.buffers.len

    let result = e.openFileAndJumpTo(absPath, 1, 0)

    check result
    check e.cursor.line == 1
    check e.buffers.len == buffersCount

suite "editor_navigation - UTF-16 to UTF-8 conversion":
  test "openFileAndJumpTo handles UTF-16 column offset":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_utf16.txt"

    # Contains Japanese characters (multi-byte in UTF-8)
    writeFile(testFile, "こんにちは world\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    # UTF-16 offset for "world" start
    # "こんにちは " = 5 chars + 1 space = 6 UTF-16 code units
    let result = e.openFileAndJumpTo(testFile, 0, 6)

    check result
    # Cursor lands on 'w', which is the 6th character (0-based) of the line.
    # The UTF-16 offset (6) and the character column (6) coincide here only
    # because every preceding rune is in the BMP; the conversion still has to
    # walk multi-byte runes to land on the right column.
    check e.cursor.column == 6

suite "editor_navigation - cursor clamping":
  test "Clamps target line to last line when out of bounds":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_clamp_line.txt"

    writeFile(testFile, "line 0\nline 1\nline 2\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    let lastLine = e.activeBuffer().len - 1

    # Request a line far beyond the buffer end
    let result = e.openFileAndJumpTo(testFile, 999, 0)

    check result
    check e.cursor.line == lastLine

  test "Clamps target column to last column when out of bounds":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_clamp_col.txt"

    writeFile(testFile, "abc\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    # Request a column far beyond the line end ("abc" has 3 chars)
    let result = e.openFileAndJumpTo(testFile, 0, 999)

    check result
    check e.cursor.line == 0
    # Clamped to the last character index (charLen - 1 == 2)
    check e.cursor.column == 2

suite "editor_navigation - per-feature config gates":
  proc createEditorWithLsp(config: EditorConfig): Editor =
    let vr = newValidationResult()
    result = newEditor(config, vr)
    result.lsp.enabled = true

  test "Goto definition returns false when disabled in config":
    let config = newEditorConfig()
    config.lsp.definition.enable = false
    let e = createEditorWithLsp(config)

    check not e.requestLspGotoDefinition()
    check e.state.statusMessage == "LSP definition is disabled"

  test "Goto declaration returns false when disabled in config":
    let config = newEditorConfig()
    config.lsp.declaration.enable = false
    let e = createEditorWithLsp(config)

    check not e.requestLspGotoDeclaration()
    check e.state.statusMessage == "LSP declaration is disabled"

  test "Find references returns false when disabled in config":
    let config = newEditorConfig()
    config.lsp.references.enable = false
    let e = createEditorWithLsp(config)

    check not e.requestLspReferences()
    check e.state.statusMessage == "LSP references is disabled"

  test "Goto type definition returns false when disabled in config":
    let config = newEditorConfig()
    config.lsp.typeDefinition.enable = false
    let e = createEditorWithLsp(config)

    check not e.requestLspTypeDefinition()
    check e.state.statusMessage == "LSP type definition is disabled"

  test "Goto implementation returns false when disabled in config":
    let config = newEditorConfig()
    config.lsp.implementation.enable = false
    let e = createEditorWithLsp(config)

    check not e.requestLspImplementation()
    check e.state.statusMessage == "LSP implementation is disabled"

suite "editor_navigation - openWindow option":
  test "jumpToLspLocation does not split when openWindow is false":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_ow_nosplit.txt"

    writeFile(testFile, "line 0\nline 1\nline 2\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    let windowsBefore = e.windowManager.windows.len

    let loc = lspTypes.Location(
      uri: "file://" & testFile,
      range: lspTypes.Range(
        start: lspTypes.Position(line: 2, character: 0),
        `end`: lspTypes.Position(line: 2, character: 6),
      ),
    )

    check e.jumpToLspLocation(loc, "Definition")
    check e.windowManager.windows.len == windowsBefore

  test "jumpToLspLocation opens a new split window when openWindow is true":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_ow_same.txt"

    writeFile(testFile, "line 0\nline 1\nline 2\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    let windowsBefore = e.windowManager.windows.len

    let loc = lspTypes.Location(
      uri: "file://" & testFile,
      range: lspTypes.Range(
        start: lspTypes.Position(line: 2, character: 0),
        `end`: lspTypes.Position(line: 2, character: 6),
      ),
    )

    check e.jumpToLspLocation(loc, "Definition", openWindow = true)
    check e.windowManager.windows.len == windowsBefore + 1
    # The jump lands in the new (active) window
    check e.cursor.line == 2

  test "jumpToLspLocation with openWindow keeps the original window position":
    let e = createTestEditor()
    let testFile1 = getTempDir() / "moe_test_ow_orig1.txt"
    let testFile2 = getTempDir() / "moe_test_ow_orig2.txt"

    writeFile(testFile1, "file 1\nfile 1 line 1\n")
    writeFile(testFile2, "line 0\nline 1\nline 2\n")
    defer:
      removeFile(testFile1)
      removeFile(testFile2)

    discard e.editFile(testFile1)
    e.cursor = BufferPosition(line: 1, column: 0)

    let loc = lspTypes.Location(
      uri: "file://" & testFile2,
      range: lspTypes.Range(
        start: lspTypes.Position(line: 2, character: 0),
        `end`: lspTypes.Position(line: 2, character: 6),
      ),
    )

    check e.jumpToLspLocation(loc, "Definition", openWindow = true)
    check e.windowManager.windows.len == 2
    # Active window shows the jump target
    check e.activeBuffer().filePath.get == testFile2
    check e.cursor.line == 2
    # The other window still shows the original file at its original position
    var foundOriginal = false
    for win in e.windowManager.windows:
      if not win.active:
        check win.buffer.filePath.get == testFile1
        check win.cursor.line == 1
        foundOriginal = true
    check foundOriginal

  test "handleLspLocations passes openWindow for a single location":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_ow_handle.txt"

    writeFile(testFile, "line 0\nline 1\nline 2\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    let windowsBefore = e.windowManager.windows.len

    let loc = lspTypes.Location(
      uri: "file://" & testFile,
      range: lspTypes.Range(
        start: lspTypes.Position(line: 1, character: 0),
        `end`: lspTypes.Position(line: 1, character: 6),
      ),
    )

    check e.handleLspLocations(@[loc], "Definitions", "Definition", openWindow = true)
    check e.windowManager.windows.len == windowsBefore + 1
    check e.cursor.line == 1

  test "handleLspLocations stores openWindow in the References viewer state":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_ow_viewer.txt"

    writeFile(testFile, "line 0\nline 1\nline 2\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    let loc1 = lspTypes.Location(
      uri: "file://" & testFile,
      range: lspTypes.Range(
        start: lspTypes.Position(line: 0, character: 0),
        `end`: lspTypes.Position(line: 0, character: 6),
      ),
    )
    let loc2 = lspTypes.Location(
      uri: "file://" & testFile,
      range: lspTypes.Range(
        start: lspTypes.Position(line: 2, character: 0),
        `end`: lspTypes.Position(line: 2, character: 6),
      ),
    )

    check e.handleLspLocations(
      @[loc1, loc2], "Definitions", "Definition", openWindow = true
    )
    check e.state.mode == EditorMode.References
    check e.activeWindow.modeState.kind == mskReferences
    check e.activeWindow.modeState.references.openWindowOnJump

  test "openFileAndJumpTo opens a new split window when openWindow is true":
    let e = createTestEditor()
    let testFile1 = getTempDir() / "moe_test_ow_open1.txt"
    let testFile2 = getTempDir() / "moe_test_ow_open2.txt"

    writeFile(testFile1, "file 1\n")
    writeFile(testFile2, "line 0\nline 1\nline 2\n")
    defer:
      removeFile(testFile1)
      removeFile(testFile2)

    discard e.editFile(testFile1)
    let windowsBefore = e.windowManager.windows.len

    check e.openFileAndJumpTo(testFile2, 1, 0, openWindow = true)
    check e.windowManager.windows.len == windowsBefore + 1
    check e.activeBuffer().filePath.get == testFile2
    check e.cursor.line == 1

suite "editor_navigation - moveCursorToLspPosition cursor clamping":
  test "Insert mode allows cursor at charLen (append position) when LSP column exceeds line length":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_lsp_clamp_insert.txt"

    writeFile(testFile, "Hello\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.state.mode = EditorMode.Insert

    let loc = lspTypes.Location(
      uri: "file://" & testFile,
      range: lspTypes.Range(
        start: lspTypes.Position(line: 0, character: 100),
        `end`: lspTypes.Position(line: 0, character: 100),
      ),
    )

    let result = e.jumpToLspLocation(loc, "Test")

    check result
    check e.cursor.line == 0
    check e.cursor.column == 5

  test "Normal mode clamps cursor to charLen-1 when LSP column exceeds line length":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_lsp_clamp_normal.txt"

    writeFile(testFile, "Hello\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    # Default is Normal mode

    let loc = lspTypes.Location(
      uri: "file://" & testFile,
      range: lspTypes.Range(
        start: lspTypes.Position(line: 0, character: 100),
        `end`: lspTypes.Position(line: 0, character: 100),
      ),
    )

    let result = e.jumpToLspLocation(loc, "Test")

    check result
    check e.cursor.line == 0
    check e.cursor.column == 4

suite "editor_navigation - mode-hijack guard":
  test "Stale location response arriving in Insert does not jump or enter References":
    # A location response would move the cursor / open a buffer / enter the
    # References viewer - all disruptive if the user is now typing in Insert.
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.mode = EditorMode.Insert
    let reqId = 7171
    let buf = e.activeBuffer
    e.state.lspCache.pending[lrfDefinition] = LspRequestContext(
      requestId: reqId,
      feature: lrfDefinition,
      bufferId: buf.id,
      contentVersion: buf.contentVersion,
      path: "/tmp/x.nim",
      generation: 1,
      cursorLine: -1,
      cursorCol: -1,
      validModes: LocationValidModes,
      blockedByOverlay: true,
    )
    let cursorBefore = e.cursor
    let bufBefore = e.state.activeWindow.buffer
    privateAccess(LspService)
    let locJson = %*[
      {
        "uri": "file:///tmp/x.nim",
        "range":
          {"start": {"line": 3, "character": 0}, "end": {"line": 3, "character": 5}},
      }
    ]
    e.lsp.service.pendingResponses[reqId] =
      (result: some($locJson), error: none(string))

    e.pollLspLocationRequest()

    check e.state.mode == EditorMode.Insert
    check not e.state.lspCache.pending.hasKey(lrfDefinition)
    check e.cursor == cursorBefore
    check e.state.activeWindow.buffer == bufBefore

suite "editor_navigation - overlay guard":
  test "Location response arriving under a Command overlay does not jump":
    # goto-* is item-driven (URI-anchored), so the buffer/version guard is
    # bypassed; only the overlay dimension can stop the jump from tearing down
    # the prompt.
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.enterCommandOverlay()
    let reqId = 7272
    let buf = e.activeBuffer
    e.state.lspCache.pending[lrfDefinition] = LspRequestContext(
      requestId: reqId,
      feature: lrfDefinition,
      bufferId: buf.id,
      contentVersion: buf.contentVersion,
      path: "/tmp/x.nim",
      generation: 1,
      cursorLine: -1,
      cursorCol: -1,
      validModes: LocationValidModes,
      isItemDriven: true,
      blockedByOverlay: true,
    )
    let cursorBefore = e.cursor
    let bufBefore = e.state.activeWindow.buffer
    privateAccess(LspService)
    let locJson = %*[
      {
        "uri": "file:///tmp/x.nim",
        "range":
          {"start": {"line": 3, "character": 0}, "end": {"line": 3, "character": 5}},
      }
    ]
    e.lsp.service.pendingResponses[reqId] =
      (result: some($locJson), error: none(string))

    e.pollLspLocationRequest()

    check e.state.overlay.isSome
    check not e.state.lspCache.pending.hasKey(lrfDefinition)
    check e.cursor == cursorBefore
    check e.state.activeWindow.buffer == bufBefore
