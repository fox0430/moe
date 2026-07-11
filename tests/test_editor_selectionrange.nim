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

## Tests for editor_selectionrange.nim

import std/[unittest, json, options, importutils]

import
  ../src/moepkg/[
    editor, config, config_loader, buffer, modes, lsp_service, editor_selectionrange,
    types,
  ]

privateAccess(LspService)

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc createTestEditorWithLspDisabled(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)
  result.lsp.enabled = false

suite "editor_selectionrange - startLspSelectionRange":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.startLspSelectionRange()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_selectionrange - requestLspSelectionRange":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspSelectionRange()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

suite "editor_selectionrange - pollLspSelectionRange":
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

  test "Converts UTF-16 positions to rune indexes for surrogate pairs":
    # Regression: before the fix, utf16OffsetToUtf8 (byte offset) was used to
    # set visualSelection and cursor columns, all of which are rune indexes.
    # On a line with a surrogate-pair emoji, the byte offset of 'b' in "a😀b"
    # is 5 while the correct rune index is 2.
    let e = createTestEditor()
    e.lsp.enabled = true

    let buf = e.activeBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a😀b")
    # Rune indexes:  a=0, 😀=1, b=2
    # UTF-16 offsets: a=0, 😀=1..2, b=3
    # Byte offsets:   a=0, 😀=1..4, b=5

    # Mock an LSP selection range response covering 'b'
    let responseJson = %*[
      {
        "range":
          {"start": {"line": 0, "character": 3}, "end": {"line": 0, "character": 4}}
      }
    ]

    let requestId = 1
    e.state.lspCache.pendingSelectionRangeRequestId = requestId
    e.state.lspCache.pendingSelectionRangeBufferId = buf.id
    e.state.lspCache.pendingSelectionRangeContentVersion = buf.contentVersion
    e.lsp.service.activeRequests[requestId] = LspPendingRequest(
      requestId: requestId,
      langId: "",
      methodName: "textDocument/selectionRange",
      startTime: 0.0,
      timeoutMs: 5000,
    )
    e.lsp.service.pendingResponses[requestId] =
      (result: some($responseJson), error: none(string))

    e.pollLspSelectionRange()

    # After fix: columns are rune indexes (2, 3)
    # Old buggy:  columns would be byte offsets (5, 6)
    check e.state.mode == EditorMode.Visual
    check e.state.visualSelection.start == BufferPosition(line: 0, column: 2)
    check e.state.visualSelection.current == BufferPosition(line: 0, column: 3)
    check e.cursor == BufferPosition(line: 0, column: 3)

  test "Discards response when the active buffer changed while waiting":
    let e = createTestEditor()
    e.lsp.enabled = true

    let buf = e.activeBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "foo")

    let responseJson = %*[
      {
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 3}}
      }
    ]

    const reqId = 7
    e.state.lspCache.pendingSelectionRangeRequestId = reqId
    # Simulate a buffer switch: the request was sent for a different buffer.
    e.state.lspCache.pendingSelectionRangeBufferId = BufferId(int(buf.id) + 1)
    e.state.lspCache.pendingSelectionRangeContentVersion = buf.contentVersion
    e.lsp.service.activeRequests[reqId] = LspPendingRequest(
      requestId: reqId,
      langId: "",
      methodName: "textDocument/selectionRange",
      startTime: 0.0,
      timeoutMs: 5000,
    )
    e.lsp.service.pendingResponses[reqId] =
      (result: some($responseJson), error: none(string))

    let modeBefore = e.state.mode
    e.pollLspSelectionRange()

    check e.state.lspCache.pendingSelectionRangeRequestId == 0
    check e.state.mode == modeBefore
    check not e.state.visualSelection.active
    check e.state.lspCache.selectionRangeChain.len == 0

  test "Discards response when the buffer was edited while waiting":
    let e = createTestEditor()
    e.lsp.enabled = true

    let buf = e.activeBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "foo")
    let versionAtRequest = buf.contentVersion

    let responseJson = %*[
      {
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 3}}
      }
    ]

    const reqId = 8
    e.state.lspCache.pendingSelectionRangeRequestId = reqId
    e.state.lspCache.pendingSelectionRangeBufferId = buf.id
    e.state.lspCache.pendingSelectionRangeContentVersion = versionAtRequest
    e.lsp.service.activeRequests[reqId] = LspPendingRequest(
      requestId: reqId,
      langId: "",
      methodName: "textDocument/selectionRange",
      startTime: 0.0,
      timeoutMs: 5000,
    )
    e.lsp.service.pendingResponses[reqId] =
      (result: some($responseJson), error: none(string))

    # Edit in flight: contentVersion advances beyond the snapshot.
    discard buf.insertText(BufferPosition(line: 0, column: 3), "bar")
    check buf.contentVersion != versionAtRequest

    let modeBefore = e.state.mode
    e.pollLspSelectionRange()

    check e.state.lspCache.pendingSelectionRangeRequestId == 0
    check e.state.mode == modeBefore
    check not e.state.visualSelection.active

suite "editor_selectionrange - config gate":
  test "startLspSelectionRange returns false when disabled in config":
    let config = newEditorConfig()
    config.lsp.selectionRange.enable = false
    let vr = newValidationResult()
    let e = newEditor(config, vr)
    e.lsp.enabled = true

    check not e.startLspSelectionRange()
    check e.state.statusMessage == "LSP selection range is disabled"

suite "editor_selectionrange - chain expansion":
  proc seedResponse(e: Editor, requestId: int, responseJson: JsonNode) =
    let buf = e.activeBuffer()
    e.state.lspCache.pendingSelectionRangeRequestId = requestId
    e.state.lspCache.pendingSelectionRangeBufferId = buf.id
    e.state.lspCache.pendingSelectionRangeContentVersion = buf.contentVersion
    e.lsp.service.activeRequests[requestId] = LspPendingRequest(
      requestId: requestId,
      langId: "",
      methodName: "textDocument/selectionRange",
      startTime: 0.0,
      timeoutMs: 5000,
    )
    e.lsp.service.pendingResponses[requestId] =
      (result: some($responseJson), error: none(string))

  test "Repeated requests walk the parent chain outward, then stop":
    let e = createTestEditor()
    e.lsp.enabled = true

    let buf = e.activeBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "foo(bar)")

    # innermost = "bar" (4..7), parent = "foo(bar)" (0..8)
    let responseJson = %*[
      {
        "range":
          {"start": {"line": 0, "character": 4}, "end": {"line": 0, "character": 7}},
        "parent": {
          "range":
            {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 8}}
        },
      }
    ]
    e.seedResponse(1, responseJson)

    # First poll selects the innermost range.
    e.pollLspSelectionRange()
    check e.state.mode == EditorMode.Visual
    check e.state.visualSelection.start == BufferPosition(line: 0, column: 4)
    check e.state.visualSelection.current == BufferPosition(line: 0, column: 7)
    check e.state.lspCache.selectionRangeIndex == 0
    check e.state.lspCache.selectionRangeChain.len == 2

    # Second request expands to the parent without contacting the server.
    check e.requestLspSelectionRange()
    check e.state.lspCache.pendingSelectionRangeRequestId == 0
    check e.state.lspCache.selectionRangeIndex == 1
    check e.state.visualSelection.start == BufferPosition(line: 0, column: 0)
    check e.state.visualSelection.current == BufferPosition(line: 0, column: 8)

    # Third request stops at the outermost level (no change, no new request).
    check e.requestLspSelectionRange()
    check e.state.lspCache.pendingSelectionRangeRequestId == 0
    check e.state.lspCache.selectionRangeIndex == 1
    check e.state.visualSelection.start == BufferPosition(line: 0, column: 0)
    check e.state.visualSelection.current == BufferPosition(line: 0, column: 8)

  test "Selection moved off the chain triggers a fresh request":
    let e = createTestEditor()
    e.lsp.enabled = true

    let buf = e.activeBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "foo(bar)")

    let responseJson = %*[
      {
        "range":
          {"start": {"line": 0, "character": 4}, "end": {"line": 0, "character": 7}},
        "parent": {
          "range":
            {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 8}}
        },
      }
    ]
    e.seedResponse(1, responseJson)
    e.pollLspSelectionRange()
    check e.state.lspCache.selectionRangeIndex == 0

    # Simulate the user adjusting the selection by hand: it no longer matches
    # the cached chain level. The next request takes the fresh-request path
    # (which fails here since no real server is attached) and must abandon the
    # stale chain rather than expanding it.
    e.state.visualSelection.current = BufferPosition(line: 0, column: 5)
    discard e.requestLspSelectionRange()
    check e.state.lspCache.selectionRangeChain.len == 0
    check e.state.lspCache.selectionRangeIndex == 0
