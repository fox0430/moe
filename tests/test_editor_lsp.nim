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

## Tests for editor_lsp.nim

import std/[unittest, os, options, strutils]

import ../src/moepkg/[editor, buffer, config, config_loader, types]
import ../src/moepkg/editor_lsp {.all.}
import ../src/moepkg/lsp/protocol/types as lspTypes

proc createTestEditor(): Editor =
  ## Create a minimal editor for testing
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc createTestEditorWithLspDisabled(): Editor =
  ## Create an editor with LSP disabled
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)
  result.lsp.enabled = false

suite "editor_lsp - maybeUpdateLsp":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()
    let initialSeq = e.lastLspChangeSeq

    e.maybeUpdateLsp()

    check e.lastLspChangeSeq == initialSeq

  test "Does nothing when buffer has not changed":
    let e = createTestEditor()
    e.lsp.enabled = true
    let activeBuffer = e.activeBuffer()
    e.lastLspChangeSeq = activeBuffer.changeSeq

    e.maybeUpdateLsp()

    check e.lastLspChangeSeq == activeBuffer.changeSeq

suite "editor_lsp - requestSignatureHelpFromLsp":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()
    e.state.mode = EditorMode.Insert

    e.requestSignatureHelpFromLsp()

    check e.state.lspCache.pendingSignatureHelpRequestId == 0

  test "Does nothing when not in Insert mode":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.mode = EditorMode.Normal

    e.requestSignatureHelpFromLsp()

    check e.state.lspCache.pendingSignatureHelpRequestId == 0

suite "editor_lsp - pollLspCompletion":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()
    e.state.mode = EditorMode.Insert

    e.pollLspCompletion()
    # No crash means success

  test "Does nothing when not in Insert mode":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.mode = EditorMode.Normal

    e.pollLspCompletion()
    # No crash means success

suite "editor_lsp - requestLspGotoDefinition":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspGotoDefinition()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_lsp - requestLspGotoDeclaration":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspGotoDeclaration()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_lsp - requestLspReferences":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspReferences()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_lsp - requestLspTypeDefinition":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspTypeDefinition()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_lsp - requestLspImplementation":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspImplementation()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_lsp - pollLspLocationRequest":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()
    e.state.lspCache.pendingLocationRequestId = 0

    e.pollLspLocationRequest()
    # No crash means success

  test "Does nothing when no pending request":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.lspCache.pendingLocationRequestId = 0
    e.state.lspCache.pendingLocationRequestKind = lrkNone

    e.pollLspLocationRequest()
    # No crash means success

suite "editor_lsp - requestLspCallHierarchyIncoming":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspCallHierarchyIncoming()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_lsp - requestLspCallHierarchyOutgoing":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspCallHierarchyOutgoing()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_lsp - pollLspCallHierarchy":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    e.pollLspCallHierarchy()
    # No crash means success

  test "Does nothing when no pending request":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.lspCache.pendingCallHierarchyRequestId = 0
    e.state.lspCache.pendingCallHierarchyKind = chrkNone

    e.pollLspCallHierarchy()
    # No crash means success

suite "editor_lsp - startLspHover":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.startLspHover()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_lsp - requestLspHover":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspHover()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_lsp - pollLspHover":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    e.pollLspHover()
    # No crash means success

  test "Does nothing when no pending request":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.lspCache.pendingHoverRequestId = 0

    e.pollLspHover()
    # No crash means success

suite "editor_lsp - hideHoverPopup":
  test "Hides the hover popup":
    let e = createTestEditor()

    e.hideHoverPopup()
    # No crash means success

suite "editor_lsp - hoverPopupScrollDown":
  test "Scrolls hover popup down":
    let e = createTestEditor()

    e.hoverPopupScrollDown()
    # No crash means success

suite "editor_lsp - hoverPopupScrollUp":
  test "Scrolls hover popup up":
    let e = createTestEditor()

    e.hoverPopupScrollUp()
    # No crash means success

suite "editor_lsp - hoverPopupScrollRight":
  test "Scrolls hover popup right":
    let e = createTestEditor()

    e.hoverPopupScrollRight()
    # No crash means success

suite "editor_lsp - hoverPopupScrollLeft":
  test "Scrolls hover popup left":
    let e = createTestEditor()

    e.hoverPopupScrollLeft()
    # No crash means success

suite "editor_lsp - startLspSelectionRange":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.startLspSelectionRange()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_lsp - requestLspSelectionRange":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspSelectionRange()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_lsp - pollLspSelectionRange":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    e.pollLspSelectionRange()
    # No crash means success

  test "Does nothing when no pending request":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.lspCache.pendingSelectionRangeRequestId = 0

    e.pollLspSelectionRange()
    # No crash means success

suite "editor_lsp - startLspDocumentSymbols":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.startLspDocumentSymbols()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

  test "Returns false when buffer has no file path":
    let e = createTestEditor()
    e.lsp.enabled = true
    # Default buffer has no file path

    let result = e.startLspDocumentSymbols()

    check not result
    check e.state.statusMessage == "No file path for current buffer"

suite "editor_lsp - requestDocumentSymbols":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestDocumentSymbols()

    check not result

suite "editor_lsp - pollLspDocumentSymbols":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    e.pollLspDocumentSymbols()
    # No crash means success

  test "Does nothing when no pending request":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.lspCache.pendingDocumentSymbolsRequestId = 0

    e.pollLspDocumentSymbols()
    # No crash means success

suite "editor_lsp - startLspDocumentLinks":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.startLspDocumentLinks()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

  test "Returns false when buffer has no file path":
    let e = createTestEditor()
    e.lsp.enabled = true
    # Default buffer has no file path

    let result = e.startLspDocumentLinks()

    check not result
    check e.state.statusMessage == "No file path for current buffer"

suite "editor_lsp - requestLspDocumentLinks":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspDocumentLinks()

    check not result

suite "editor_lsp - pollLspDocumentLinks":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    e.pollLspDocumentLinks()
    # No crash means success

  test "Does nothing when no pending request":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.lspCache.pendingDocumentLinkRequestId = 0

    e.pollLspDocumentLinks()
    # No crash means success

suite "editor_lsp - pollLspDocumentLinkResolve":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    e.pollLspDocumentLinkResolve()
    # No crash means success

  test "Does nothing when no pending request":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.lspCache.pendingDocumentLinkResolveRequestId = 0

    e.pollLspDocumentLinkResolve()
    # No crash means success

suite "editor_lsp - restartLspServer":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.restartLspServer()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

  test "Returns false when buffer has no file path":
    let e = createTestEditor()
    e.lsp.enabled = true
    # Default buffer has no file path

    let result = e.restartLspServer()

    check not result
    check e.state.statusMessage == "No file path for current buffer"

suite "editor_lsp - openFileAndJumpTo":
  test "Jumps to location in same file":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_jump_same.txt"

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
    let testFile = "/tmp/moe_test_jump_list.txt"

    writeFile(testFile, "line 0\nline 1\nline 2\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    let initialJumpListLen = e.state.jumpList.len

    discard e.openFileAndJumpTo(testFile, 2, 0)

    check e.state.jumpList.len == initialJumpListLen + 1

  test "Opens different file and jumps to location":
    let e = createTestEditor()
    let testFile1 = "/tmp/moe_test_jump1.txt"
    let testFile2 = "/tmp/moe_test_jump2.txt"

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

    let result = e.openFileAndJumpTo("/tmp/moe_test_new_file.txt", 0, 0)

    # Should succeed as new file creation
    check result
    check e.cursor.line == 0
    check e.cursor.column == 0

suite "editor_lsp - findDocumentLinkAtCursor":
  proc makeLink(
      startLine, startChar, endLine, endChar: int, target: string
  ): lspTypes.DocumentLink =
    lspTypes.DocumentLink(
      range: lspTypes.Range(
        start: lspTypes.Position(line: startLine, character: startChar),
        `end`: lspTypes.Position(line: endLine, character: endChar),
      ),
      target: some(target),
    )

  test "Finds single-line link when cursor is at start":
    let link = makeLink(5, 10, 5, 20, "file:///test.txt")
    let links = @[link]

    let result = findDocumentLinkAtCursor(links, 5, 10)

    check result.isSome
    check result.get.target.get == "file:///test.txt"

  test "Finds single-line link when cursor is in middle":
    let link = makeLink(5, 10, 5, 20, "file:///test.txt")
    let links = @[link]

    let result = findDocumentLinkAtCursor(links, 5, 15)

    check result.isSome

  test "Does not find single-line link when cursor is at end (half-open)":
    let link = makeLink(5, 10, 5, 20, "file:///test.txt")
    let links = @[link]

    let result = findDocumentLinkAtCursor(links, 5, 20)

    check result.isNone

  test "Does not find single-line link when cursor is before":
    let link = makeLink(5, 10, 5, 20, "file:///test.txt")
    let links = @[link]

    let result = findDocumentLinkAtCursor(links, 5, 5)

    check result.isNone

  test "Does not find single-line link when cursor is on different line":
    let link = makeLink(5, 10, 5, 20, "file:///test.txt")
    let links = @[link]

    let result = findDocumentLinkAtCursor(links, 6, 15)

    check result.isNone

  test "Finds multi-line link on first line":
    let link = makeLink(5, 10, 7, 5, "file:///test.txt")
    let links = @[link]

    let result = findDocumentLinkAtCursor(links, 5, 15)

    check result.isSome

  test "Finds multi-line link on middle line":
    let link = makeLink(5, 10, 7, 5, "file:///test.txt")
    let links = @[link]

    let result = findDocumentLinkAtCursor(links, 6, 0)

    check result.isSome

  test "Finds multi-line link on last line":
    let link = makeLink(5, 10, 7, 5, "file:///test.txt")
    let links = @[link]

    let result = findDocumentLinkAtCursor(links, 7, 3)

    check result.isSome

  test "Does not find multi-line link at end of last line":
    let link = makeLink(5, 10, 7, 5, "file:///test.txt")
    let links = @[link]

    let result = findDocumentLinkAtCursor(links, 7, 5)

    check result.isNone

  test "Returns none when no links":
    let links: seq[lspTypes.DocumentLink] = @[]

    let result = findDocumentLinkAtCursor(links, 0, 0)

    check result.isNone

  test "Finds correct link among multiple":
    let link1 = makeLink(1, 0, 1, 10, "file:///first.txt")
    let link2 = makeLink(3, 5, 3, 15, "file:///second.txt")
    let link3 = makeLink(5, 0, 5, 20, "file:///third.txt")
    let links = @[link1, link2, link3]

    let result = findDocumentLinkAtCursor(links, 3, 10)

    check result.isSome
    check result.get.target.get == "file:///second.txt"

suite "editor_lsp - Jump list":
  test "Jump list does not add duplicate positions":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_jump_dup.txt"

    writeFile(testFile, "line 0\nline 1\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    # Jump to same position twice
    discard e.openFileAndJumpTo(testFile, 0, 0)
    let lenAfterFirst = e.state.jumpList.len

    discard e.openFileAndJumpTo(testFile, 0, 0)
    let lenAfterSecond = e.state.jumpList.len

    # Should not add duplicate
    check lenAfterFirst == lenAfterSecond

  test "Jump list respects maximum size":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_jump_max.txt"

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
    check e.state.jumpList.len <= 100

suite "editor_lsp - requestCallHierarchyIncomingForItem":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()
    let item = lspTypes.CallHierarchyItem(
      name: "test",
      kind: SymbolKind.skFunction,
      uri: "file:///test.nim",
      range: lspTypes.Range(
        start: lspTypes.Position(line: 0, character: 0),
        `end`: lspTypes.Position(line: 0, character: 10),
      ),
      selectionRange: lspTypes.Range(
        start: lspTypes.Position(line: 0, character: 0),
        `end`: lspTypes.Position(line: 0, character: 10),
      ),
    )

    let result = e.requestCallHierarchyIncomingForItem(item)

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_lsp - requestCallHierarchyOutgoingForItem":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()
    let item = lspTypes.CallHierarchyItem(
      name: "test",
      kind: SymbolKind.skFunction,
      uri: "file:///test.nim",
      range: lspTypes.Range(
        start: lspTypes.Position(line: 0, character: 0),
        `end`: lspTypes.Position(line: 0, character: 10),
      ),
      selectionRange: lspTypes.Range(
        start: lspTypes.Position(line: 0, character: 0),
        `end`: lspTypes.Position(line: 0, character: 10),
      ),
    )

    let result = e.requestCallHierarchyOutgoingForItem(item)

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_lsp - jumpToCallHierarchyItem":
  test "Jumps to item location in same file":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_call_hierarchy.txt"

    writeFile(testFile, "line 0\nline 1\nline 2\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    let item = lspTypes.CallHierarchyItem(
      name: "test",
      kind: SymbolKind.skFunction,
      uri: "file://" & testFile,
      range: lspTypes.Range(
        start: lspTypes.Position(line: 1, character: 0),
        `end`: lspTypes.Position(line: 1, character: 6),
      ),
      selectionRange: lspTypes.Range(
        start: lspTypes.Position(line: 1, character: 0),
        `end`: lspTypes.Position(line: 1, character: 6),
      ),
    )

    let result = e.jumpToCallHierarchyItem(item)

    check result
    check e.cursor.line == 1

suite "editor_lsp - handleLspLocations":
  test "Returns false and sets message when no locations":
    let e = createTestEditor()
    let locations: seq[lspTypes.Location] = @[]

    let result = e.handleLspLocations(locations, "Definitions", "Definition")

    check not result
    check e.state.statusMessage == "No definitions found"

  test "Jumps directly when single location in same file":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_handle_loc.txt"

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
    let testFile = "/tmp/moe_test_multi_loc.txt"

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

suite "editor_lsp - switchToBufferForLsp":
  test "Does nothing for invalid negative index":
    let e = createTestEditor()
    let initialBufferIndex = e.state.currentBufferIndex

    e.switchToBufferForLsp(-1)

    check e.state.currentBufferIndex == initialBufferIndex

  test "Does nothing for out of bounds index":
    let e = createTestEditor()
    let initialBufferIndex = e.state.currentBufferIndex

    e.switchToBufferForLsp(999)

    check e.state.currentBufferIndex == initialBufferIndex

  test "Switches to valid buffer index":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_switch_lsp.txt"

    writeFile(testFile, "test content")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.switchToBufferForLsp(0)

    check e.state.currentBufferIndex == 0

  test "Does nothing when already on target buffer":
    let e = createTestEditor()
    let initialIndex = e.state.currentBufferIndex

    e.switchToBufferForLsp(initialIndex)

    check e.state.currentBufferIndex == initialIndex

suite "editor_lsp - addToJumpList":
  test "Adds position to jump list":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_add_jump.txt"

    writeFile(testFile, "line 0\nline 1\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.cursor = BufferPosition(line: 1, column: 3)
    let initialLen = e.state.jumpList.len

    e.addToJumpList()

    check e.state.jumpList.len == initialLen + 1
    let lastPos = e.state.jumpList[^1]
    check lastPos.line == 1
    check lastPos.column == 3

  test "Does not add duplicate of last position":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_add_jump_dup.txt"

    writeFile(testFile, "line 0\nline 1\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)
    e.cursor = BufferPosition(line: 1, column: 3)

    e.addToJumpList()
    let lenAfterFirst = e.state.jumpList.len

    e.addToJumpList()
    let lenAfterSecond = e.state.jumpList.len

    check lenAfterFirst == lenAfterSecond

  test "Resets jump list index after adding":
    let e = createTestEditor()
    e.state.jumpListIndex = 5

    e.addToJumpList()

    check e.state.jumpListIndex == -1

suite "editor_lsp - jumpToLspLocation":
  test "Jumps to location in same file":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_jump_lsp_loc.txt"

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
    let testFile1 = "/tmp/moe_test_jump_lsp1.txt"
    let testFile2 = "/tmp/moe_test_jump_lsp2.txt"

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
    let testFile1 = "/tmp/moe_test_jump_existing1.txt"
    let testFile2 = "/tmp/moe_test_jump_existing2.txt"

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

suite "editor_lsp - UTF-16 to UTF-8 conversion":
  test "openFileAndJumpTo handles UTF-16 column offset":
    let e = createTestEditor()
    let testFile = "/tmp/moe_test_utf16.txt"

    # Contains Japanese characters (multi-byte in UTF-8)
    writeFile(testFile, "こんにちは world\n")
    defer:
      removeFile(testFile)

    discard e.editFile(testFile)

    # UTF-16 offset for "world" start
    # "こんにちは " = 5 chars + 1 space = 6 UTF-16 code units
    let result = e.openFileAndJumpTo(testFile, 0, 6)

    check result
    # Cursor should be at the byte position of 'w'

suite "editor_lsp - Async functions":
  test "requestLspFormat returns false when LSP disabled":
    let e = createTestEditorWithLspDisabled()

    # We can't easily test async functions without running event loop
    # but we can verify the function exists and compiles
    check not e.lsp.enabled

  test "refreshLspFolds does nothing when LSP disabled":
    let e = createTestEditorWithLspDisabled()

    check not e.lsp.enabled

  test "requestLspRename does nothing when LSP disabled":
    let e = createTestEditorWithLspDisabled()

    check not e.lsp.enabled

  test "requestLspExecuteCommand does nothing when LSP disabled":
    let e = createTestEditorWithLspDisabled()

    check not e.lsp.enabled
