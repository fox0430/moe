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

import std/[unittest, os, strutils, options, json, importutils, tables]

import ../src/moepkg/[editor, config, config_loader, types, lsp_service]
import ../src/moepkg/buffer/core
import ../src/moepkg/callhierarchy_viewer
import ../src/moepkg/editor_callhierarchy {.all.}
import ../src/moepkg/lsp/protocol/types as lspTypes

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc makeCallHierarchyItem(
    name, uri: string, line, col: int
): lspTypes.CallHierarchyItem =
  ## Helper to create a CallHierarchyItem for testing
  result.name = name
  result.kind = skFunction
  result.uri = uri
  result.range = lspTypes.Range(
    start: lspTypes.Position(line: line, character: col),
    `end`: lspTypes.Position(line: line, character: col + name.len),
  )
  result.selectionRange = result.range

proc dummyRangeJson(): JsonNode =
  %*{"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 1}}

proc incomingCallsResponseJson(items: seq[lspTypes.CallHierarchyItem]): JsonNode =
  ## Build a callHierarchy/incomingCalls wire response: an array of
  ## {from: <item>, fromRanges: [...]} objects.
  result = newJArray()
  for it in items:
    result.add(%*{"from": it.toJson, "fromRanges": [dummyRangeJson()]})

proc outgoingCallsResponseJson(items: seq[lspTypes.CallHierarchyItem]): JsonNode =
  ## Build a callHierarchy/outgoingCalls wire response: an array of
  ## {to: <item>, fromRanges: [...]} objects.
  result = newJArray()
  for it in items:
    result.add(%*{"to": it.toJson, "fromRanges": [dummyRangeJson()]})

proc injectLspResponse(e: Editor, requestId: int, resp: JsonNode) =
  ## Simulate a server response arriving for `requestId`. Uses privateAccess to
  ## reach the service's private `pendingResponses` table (no production seam).
  privateAccess(LspService)
  e.lsp.service.pendingResponses[requestId] = (result: some($resp), error: none(string))

proc injectPending(e: Editor, feature: LspRequestFeature, requestId: int) =
  ## Seed lspCache.pending as if startContextualRequest just fired. Skips the
  ## real request path (no worker in these tests) but keeps classifyResponse
  ## consistent by pinning buffer/version to the active buffer.
  let buf = e.activeBuffer
  e.state.lspCache.pending[feature] = LspRequestContext(
    requestId: requestId,
    feature: feature,
    bufferId: buf.id,
    contentVersion: buf.contentVersion,
    path: "/tmp/x.nim",
    generation: 1,
    cursorLine: -1,
    cursorCol: -1,
    validModes: {}, # any mode; callhierarchy has its own inline guard
    blockedByOverlay: true,
  )

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

    e.pollLspCallHierarchy()
    # No crash means success

  test "Incoming-calls response enters CallHierarchy mode":
    # Final-stage cascade: a chrkIncomingCalls response is parsed and shown in
    # the viewer. No worker is needed here (this stage starts no new request).
    let e = createTestEditor()
    e.lsp.enabled = true
    let reqId = 4242
    e.injectPending(lrfCallHierarchyIncoming, reqId)
    let items = @[makeCallHierarchyItem("caller", "file:///x.nim", 2, 0)]
    e.injectLspResponse(reqId, incomingCallsResponseJson(items))

    e.pollLspCallHierarchy()

    check e.state.mode == EditorMode.CallHierarchy
    check e.activeWindow.modeState.kind == mskCallHierarchy
    check e.activeWindow.modeState.callHierarchy.viewKind == chvkIncoming
    check e.activeWindow.modeState.callHierarchy.items.len == 1
    check e.activeWindow.modeState.callHierarchy.items[0].name == "caller"
    check e.state.statusMessage == "1 incoming call found"
    # Pending state is cleared after the cascade completes.
    check not e.state.lspCache.pending.hasKey(lrfCallHierarchyIncoming)

  test "Outgoing-calls response enters CallHierarchy mode":
    let e = createTestEditor()
    e.lsp.enabled = true
    let reqId = 4343
    e.injectPending(lrfCallHierarchyOutgoing, reqId)
    let items = @[
      makeCallHierarchyItem("calleeA", "file:///x.nim", 5, 0),
      makeCallHierarchyItem("calleeB", "file:///y.nim", 9, 2),
    ]
    e.injectLspResponse(reqId, outgoingCallsResponseJson(items))

    e.pollLspCallHierarchy()

    check e.state.mode == EditorMode.CallHierarchy
    check e.activeWindow.modeState.callHierarchy.viewKind == chvkOutgoing
    check e.activeWindow.modeState.callHierarchy.items.len == 2
    check e.state.statusMessage == "2 outgoing calls found"

  test "Empty incoming-calls response stays out of CallHierarchy mode":
    let e = createTestEditor()
    e.lsp.enabled = true
    let startMode = e.state.mode
    let reqId = 4444
    e.injectPending(lrfCallHierarchyIncoming, reqId)
    e.injectLspResponse(reqId, newJArray())

    e.pollLspCallHierarchy()

    check e.state.mode == startMode
    check e.state.statusMessage == "No incoming calls found"
    check not e.state.lspCache.pending.hasKey(lrfCallHierarchyIncoming)

  test "Empty prepare response reports no callable symbol":
    # First-stage prepare with an empty result: no second-stage request is
    # started, so this needs only response injection (no worker).
    let e = createTestEditor()
    e.lsp.enabled = true
    let prepareId = 7003
    e.injectPending(lrfCallHierarchyPrepareIncoming, prepareId)
    e.injectLspResponse(prepareId, newJArray())

    e.pollLspCallHierarchy()

    check e.state.statusMessage == "No callable symbol at cursor"
    check not e.state.lspCache.pending.hasKey(lrfCallHierarchyPrepareIncoming)
    check e.state.mode != EditorMode.CallHierarchy

suite "editor_callhierarchy - overlay guard":
  test "Response arriving while a Command overlay is active is dropped":
    # An overlay keeps the base mode, so validModes cannot catch it; entering
    # CallHierarchy mode here would tear down the overlay's prompt.
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.enterCommandOverlay()
    let startMode = e.state.mode
    let reqId = 4545
    e.injectPending(lrfCallHierarchyIncoming, reqId)
    let items = @[makeCallHierarchyItem("caller", "file:///x.nim", 2, 0)]
    e.injectLspResponse(reqId, incomingCallsResponseJson(items))

    e.pollLspCallHierarchy()

    check e.state.mode == startMode
    check e.state.mode != EditorMode.CallHierarchy
    check not e.state.lspCache.pending.hasKey(lrfCallHierarchyIncoming)

suite "editor_callhierarchy - enterCallHierarchyMode":
  test "Fresh entry saves originalBuffer and previousMode":
    let e = createTestEditor()
    let startMode = e.state.mode
    let items = @[makeCallHierarchyItem("foo", "file:///test.nim", 0, 0)]

    e.enterCallHierarchyMode(items, chvkIncoming)

    check e.state.mode == EditorMode.CallHierarchy
    check e.activeWindow.modeState.kind == mskCallHierarchy
    check e.activeWindow.modeState.callHierarchy.viewKind == chvkIncoming
    check e.state.previousMode == startMode
    check e.activeWindow.originalBuffer != nil
    check e.state.statusMessage == "1 incoming call found"

  test "Switching Incoming -> Outgoing preserves originalBuffer and previousMode":
    let e = createTestEditor()
    let startMode = e.state.mode
    let items = @[makeCallHierarchyItem("foo", "file:///test.nim", 0, 0)]

    e.enterCallHierarchyMode(items, chvkIncoming)
    let savedOriginal = e.activeWindow.originalBuffer

    e.enterCallHierarchyMode(items, chvkOutgoing)

    # originalBuffer must NOT be re-saved on the second entry: the previous
    # CallHierarchy original is still live, and overwriting it would lose the
    # real buffer (and emit a saveOriginalBuffer warning).
    check e.activeWindow.originalBuffer == savedOriginal
    check e.state.previousMode == startMode
    check e.activeWindow.modeState.callHierarchy.viewKind == chvkOutgoing
    check e.state.statusMessage == "1 outgoing call found"

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

  test "Routes via item.uri, not the active buffer":
    # Regression: in the viewer the active buffer is a synthetic, path-less
    # buffer, and the target item may live in a different file. The worker must
    # be resolved from item.uri. Point the item at an extension with no
    # configured LSP server: the request then fails with a path-specific
    # "No LSP support" error referencing item.uri's path, proving the routing
    # came from item.uri (the old code failed with "Buffer has no file path").
    let e = createTestEditor()
    e.lsp.enabled = true
    let item = makeCallHierarchyItem("foo", "file:///tmp/x.unknownlang", 0, 0)

    discard e.requestCallHierarchyIncomingForItem(item)

    check not e.state.statusMessage.contains("Buffer has no file path")
    check e.state.statusMessage.contains("No LSP support for file")
    check e.state.statusMessage.contains("x.unknownlang")

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

  test "Routes via item.uri, not the active buffer":
    # See the incoming counterpart: item.uri (not the active buffer) drives
    # worker resolution, evidenced by the path-specific "No LSP support" error.
    let e = createTestEditor()
    e.lsp.enabled = true
    let item = makeCallHierarchyItem("foo", "file:///tmp/x.unknownlang", 0, 0)

    discard e.requestCallHierarchyOutgoingForItem(item)

    check not e.state.statusMessage.contains("Buffer has no file path")
    check e.state.statusMessage.contains("No LSP support for file")
    check e.state.statusMessage.contains("x.unknownlang")

suite "editor_callhierarchy - jumpToCallHierarchyItem":
  test "Jumps to item location in same file":
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_call_hierarchy.txt"

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

suite "editor_callhierarchy - config gate":
  test "Incoming calls returns false when disabled in config":
    let config = newEditorConfig()
    config.lsp.callHierarchy.enable = false
    let vr = newValidationResult()
    let e = newEditor(config, vr)
    e.lsp.enabled = true

    check not e.requestLspCallHierarchyIncoming()
    check e.state.statusMessage == "LSP call hierarchy is disabled"

  test "Outgoing calls returns false when disabled in config":
    let config = newEditorConfig()
    config.lsp.callHierarchy.enable = false
    let vr = newValidationResult()
    let e = newEditor(config, vr)
    e.lsp.enabled = true

    check not e.requestLspCallHierarchyOutgoing()
    check e.state.statusMessage == "LSP call hierarchy is disabled"

suite "editor_callhierarchy - mode-hijack guard":
  test "Stale incoming response arriving in Insert does not switch to CallHierarchy":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.mode = EditorMode.Insert
    let reqId = 8181
    e.injectPending(lrfCallHierarchyIncoming, reqId)
    let items = @[makeCallHierarchyItem("caller", "file:///x.nim", 2, 0)]
    e.injectLspResponse(reqId, incomingCallsResponseJson(items))

    e.pollLspCallHierarchy()

    check e.state.mode == EditorMode.Insert
    check not e.state.lspCache.pending.hasKey(lrfCallHierarchyIncoming)

  test "Incoming response arriving during CallHierarchy re-entry is applied":
    # Toggling Incoming <-> Outgoing from inside the viewer must still work:
    # here state.mode is already CallHierarchy when the response lands. This
    # is the item-driven flow (storeItemDrivenPending), which sets path = ""
    # so classifyResponse's buffer/version guard is skipped.
    let e = createTestEditor()
    e.lsp.enabled = true
    let seedItems = @[makeCallHierarchyItem("seed", "file:///seed.nim", 0, 0)]
    e.enterCallHierarchyMode(seedItems, chvkOutgoing)
    check e.state.mode == EditorMode.CallHierarchy

    let reqId = 8282
    let buf = e.activeBuffer
    e.state.lspCache.pending[lrfCallHierarchyIncoming] = LspRequestContext(
      requestId: reqId,
      feature: lrfCallHierarchyIncoming,
      bufferId: buf.id,
      contentVersion: buf.contentVersion,
      path: "",
      generation: 1,
      cursorLine: -1,
      cursorCol: -1,
      validModes: {},
      isItemDriven: true,
    )
    let items = @[makeCallHierarchyItem("caller", "file:///x.nim", 2, 0)]
    e.injectLspResponse(reqId, incomingCallsResponseJson(items))

    e.pollLspCallHierarchy()

    check e.state.mode == EditorMode.CallHierarchy
    check e.activeWindow.modeState.callHierarchy.viewKind == chvkIncoming

suite "editor_callhierarchy - buffer/version guard":
  test "Stale 2-stage response (contentVersion drift) is dropped":
    # A 2-stage request (path != "") whose buffer was edited after the request
    # was sent must be dropped by classifyResponse rather than entering the
    # viewer with stale data.
    let e = createTestEditor()
    e.lsp.enabled = true
    let reqId = 9090
    e.injectPending(lrfCallHierarchyIncoming, reqId)
    # Simulate an edit after the request was sent.
    e.activeBuffer.contentVersion.inc
    let items = @[makeCallHierarchyItem("caller", "file:///x.nim", 2, 0)]
    e.injectLspResponse(reqId, incomingCallsResponseJson(items))

    e.pollLspCallHierarchy()

    check e.state.mode != EditorMode.CallHierarchy
    check not e.state.lspCache.pending.hasKey(lrfCallHierarchyIncoming)

  test "Item-driven response (isItemDriven=true) bypasses the buffer/version guard":
    # Item-driven requests (storeItemDrivenPending) target item.uri rather
    # than the active buffer; classifyResponse honours ctx.isItemDriven and
    # skips the buffer/version guard, so a contentVersion drift on the active
    # buffer does not drop the response.
    let e = createTestEditor()
    e.lsp.enabled = true
    let reqId = 9191
    let buf = e.activeBuffer
    e.state.lspCache.pending[lrfCallHierarchyIncoming] = LspRequestContext(
      requestId: reqId,
      feature: lrfCallHierarchyIncoming,
      bufferId: buf.id,
      contentVersion: buf.contentVersion,
      path: "",
      generation: 1,
      cursorLine: -1,
      cursorCol: -1,
      validModes: {},
      isItemDriven: true,
    )
    # Simulate an edit on the active buffer after the request was sent.
    e.activeBuffer.contentVersion.inc
    let items = @[makeCallHierarchyItem("caller", "file:///x.nim", 2, 0)]
    e.injectLspResponse(reqId, incomingCallsResponseJson(items))

    e.pollLspCallHierarchy()

    # The response is applied despite the contentVersion drift because the
    # item-driven path bypasses classifyResponse.
    check e.state.mode == EditorMode.CallHierarchy
    check e.activeWindow.modeState.callHierarchy.viewKind == chvkIncoming
