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

## Tests for editor_documentsymbol.nim

import std/[unittest, options, importutils, json, tables]

import ../src/moepkg/[editor, config, config_loader, lsp_service, types]
import ../src/moepkg/buffer/core
import ../src/moepkg/editor_documentsymbol

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc createTestEditorWithLspDisabled(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)
  result.lsp.enabled = false

suite "editor_documentsymbol - startLspDocumentSymbols":
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

suite "editor_documentsymbol - requestDocumentSymbols":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestDocumentSymbols()

    check not result

suite "editor_documentsymbol - pollLspDocumentSymbols":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    e.pollLspDocumentSymbols()
    # No crash means success

  test "Does nothing when no pending request":
    let e = createTestEditor()
    e.lsp.enabled = true

    e.pollLspDocumentSymbols()
    # No crash means success

suite "editor_documentsymbol - config gate":
  test "startLspDocumentSymbols returns false when disabled in config":
    let config = newEditorConfig()
    config.lsp.documentSymbol.enable = false
    let vr = newValidationResult()
    let e = newEditor(config, vr)
    e.lsp.enabled = true

    check not e.startLspDocumentSymbols()
    check e.state.statusMessage == "LSP document symbol is disabled"

suite "editor_documentsymbol - mode-hijack guard":
  test "Stale response arriving in Insert does not switch to DocumentSymbol":
    # A Symbols request initiated from Normal must not force the viewer if the
    # user has since moved to Insert (or an overlay) - it would hijack input.
    let e = createTestEditor()
    e.lsp.enabled = true
    e.setMode(EditorMode.Insert)
    e.state.mode = EditorMode.Insert
    let reqId = 5151
    let buf = e.activeBuffer
    e.state.lspCache.pending[lrfDocumentSymbol] = LspRequestContext(
      requestId: reqId,
      feature: lrfDocumentSymbol,
      bufferId: buf.id,
      contentVersion: buf.contentVersion,
      path: "/tmp/x.nim",
      generation: 1,
      cursorLine: -1,
      cursorCol: -1,
      validModes: DocumentSymbolValidModes,
      blockedByOverlay: true,
    )
    privateAccess(LspService)
    e.lsp.service.pendingResponses[reqId] =
      (result: some($newJArray()), error: none(string))

    e.pollLspDocumentSymbols()

    check e.state.mode == EditorMode.Insert
    check not e.state.lspCache.pending.hasKey(lrfDocumentSymbol)

suite "editor_documentsymbol - stale-guard":
  test "Response for an edited buffer (contentVersion bumped) is dropped":
    # Phase B regression: classifyResponse now guards on contentVersion, so a
    # response arriving after an edit no longer forces the viewer open on
    # symbols computed from the pre-edit text.
    let e = createTestEditor()
    e.lsp.enabled = true
    let reqId = 5252
    let buf = e.activeBuffer
    e.state.lspCache.pending[lrfDocumentSymbol] = LspRequestContext(
      requestId: reqId,
      feature: lrfDocumentSymbol,
      bufferId: buf.id,
      contentVersion: buf.contentVersion - 1, # older than current => stale
      path: "/tmp/x.nim",
      generation: 1,
      cursorLine: -1,
      cursorCol: -1,
      validModes: DocumentSymbolValidModes,
      blockedByOverlay: true,
    )
    privateAccess(LspService)
    e.lsp.service.pendingResponses[reqId] =
      (result: some($newJArray()), error: none(string))

    e.pollLspDocumentSymbols()

    check e.state.mode != EditorMode.DocumentSymbol
    check not e.state.lspCache.pending.hasKey(lrfDocumentSymbol)
