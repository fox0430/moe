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

## Tests for editor_callhierarchy.nim

import std/[unittest, os]

import ../src/moepkg/[editor, config, config_loader, types]
import ../src/moepkg/editor_callhierarchy
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

suite "editor_callhierarchy - requestLspCallHierarchyIncoming":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspCallHierarchyIncoming()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_callhierarchy - requestLspCallHierarchyOutgoing":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspCallHierarchyOutgoing()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_callhierarchy - pollLspCallHierarchy":
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

suite "editor_callhierarchy - requestCallHierarchyIncomingForItem":
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

suite "editor_callhierarchy - requestCallHierarchyOutgoingForItem":
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

suite "editor_callhierarchy - jumpToCallHierarchyItem":
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
