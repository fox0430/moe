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

import std/[unittest, tables, options, json, importutils]

import ../src/moepkg/[editor, config, types, buffer]
import ../src/moepkg/editor_codelens {.all.}
import ../src/moepkg/lsp_service
import ../src/moepkg/lsp/protocol/types as lspTypes

privateAccess(LspService)

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  result = newEditor(config)

proc inlayHint(line, character: int, label: string, kind = 0): InlayHint =
  result.position = lspTypes.Position(line: line, character: character)
  result.label = %label
  if kind > 0:
    result.kind = toEnum[InlayHintKind](kind)

suite "Inlay Hint Support":
  test "hasInlayHintSupport - LSP disabled":
    let e = createTestEditor()
    check not e.hasInlayHintSupport()

suite "Inlay Hint Cache lookup":
  test "getInlayHintsForLine - empty cache":
    let e = createTestEditor()
    check e.state.lspCache.getInlayHintsForLine(0).len == 0

  test "getInlayHintsForLine - invalid cache returns empty":
    let e = createTestEditor()
    e.state.lspCache.inlayHintCache.isValid = false
    e.state.lspCache.inlayHintCache.itemsByLine =
      {0: @[InlayHintItem(line: 0, label: ": int")]}.toTable
    check e.state.lspCache.getInlayHintsForLine(0).len == 0

  test "getInlayHintsForLine - valid cache with items":
    let e = createTestEditor()
    e.state.lspCache.inlayHintCache.isValid = true
    e.state.lspCache.inlayHintCache.itemsByLine = {
      0: @[InlayHintItem(line: 0, column: 5, label: ": int", kind: 1)],
      3: @[
        InlayHintItem(line: 3, column: 4, label: "a: ", kind: 2),
        InlayHintItem(line: 3, column: 9, label: "b: ", kind: 2),
      ],
    }.toTable

    let items0 = e.state.lspCache.getInlayHintsForLine(0)
    check items0.len == 1
    check items0[0].label == ": int"

    let items3 = e.state.lspCache.getInlayHintsForLine(3)
    check items3.len == 2
    check items3[1].label == "b: "

    check e.state.lspCache.getInlayHintsForLine(10).len == 0

suite "Inlay Hint Cache invalidation":
  test "invalidateInlayHintCache clears validity and pending id":
    let e = createTestEditor()
    e.state.lspCache.inlayHintCache.isValid = true
    e.state.lspCache.inlayHintPoll.pendingRequestId = 42

    invalidateInlayHintCache(e.lsp, e.state.lspCache)

    check not e.state.lspCache.inlayHintCache.isValid
    check e.state.lspCache.inlayHintPoll.pendingRequestId == 0

suite "Inlay Hint Response processing":
  test "processInlayHintResponse groups hints by line and stamps viewport":
    let e = createTestEditor()
    e.activeBuffer().filePath = some("/test/file.nim")
    discard e.activeBuffer().insertText(BufferPosition(line: 0, column: 0), "let x = 1")

    e.state.lspCache.inlayHintPoll.pendingContentVersion =
      e.activeBuffer().contentVersion
    e.processInlayHintResponse(
      @[inlayHint(0, 5, ": int", 1), inlayHint(0, 5, " extra", 0)]
    )

    check e.state.lspCache.inlayHintCache.isValid
    check e.state.lspCache.inlayHintCache.filePath == "/test/file.nim"
    let items = e.state.lspCache.getInlayHintsForLine(0)
    check items.len == 2
    check items[0].label == ": int"
    check items[0].kind == 1

  test "processInlayHintResponse sorts hints on a line by column":
    let e = createTestEditor()
    e.activeBuffer().filePath = some("/test/file.nim")
    discard e.activeBuffer().insertText(BufferPosition(line: 0, column: 0), "f(a, b)")

    # The server returns them out of column order; end-of-line rendering
    # concatenates left-to-right, so they must come back column-sorted.
    e.state.lspCache.inlayHintPoll.pendingContentVersion =
      e.activeBuffer().contentVersion
    e.processInlayHintResponse(@[inlayHint(0, 5, "b: "), inlayHint(0, 2, "a: ")])

    let items = e.state.lspCache.getInlayHintsForLine(0)
    check items.len == 2
    check items[0].column == 2
    check items[0].label == "a: "
    check items[1].column == 5
    check items[1].label == "b: "

  test "processInlayHintResponse converts UTF-16 character to rune column":
    let e = createTestEditor()
    e.activeBuffer().filePath = some("/test/file.nim")
    # "𐐷" (U+10437) is one rune but two UTF-16 code units.
    discard e.activeBuffer().insertText(BufferPosition(line: 0, column: 0), "𐐷x")

    # A hint at UTF-16 offset 2 sits after the surrogate pair => rune index 1.
    e.state.lspCache.inlayHintPoll.pendingContentVersion =
      e.activeBuffer().contentVersion
    e.processInlayHintResponse(@[inlayHint(0, 2, ": T", 1)])

    let items = e.state.lspCache.getInlayHintsForLine(0)
    check items.len == 1
    check items[0].column == 1

  test "processInlayHintResponse drops hints on out-of-range lines":
    let e = createTestEditor()
    e.activeBuffer().filePath = some("/test/file.nim")
    discard e.activeBuffer().insertText(BufferPosition(line: 0, column: 0), "x")

    e.processInlayHintResponse(@[inlayHint(99, 0, ": int", 1)])

    check e.state.lspCache.getInlayHintsForLine(99).len == 0

  test "processInlayHintResponse skips hints with empty labels":
    let e = createTestEditor()
    e.activeBuffer().filePath = some("/test/file.nim")
    discard e.activeBuffer().insertText(BufferPosition(line: 0, column: 0), "x")

    e.processInlayHintResponse(@[inlayHint(0, 0, "")])

    check e.state.lspCache.getInlayHintsForLine(0).len == 0

  test "updateInlayHintCache caches an in-flight response for the same buffer":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.display.showInlayHint = true
    e.activeBuffer().filePath = some("/test/file.nim")
    discard e.activeBuffer().insertText(BufferPosition(line: 0, column: 0), "let x = 1")
    e.lsp.service.capabilities["nim"] =
      ServerCapabilities(inlayHintProvider: some(newJBool(true)))

    const reqId = 77
    let buf = e.activeBuffer()
    e.lsp.service.pendingResponses[reqId] = (
      result: some($(%*[{"position": {"line": 0, "character": 5}, "label": ": int"}])),
      error: none(string),
    )
    e.state.lspCache.inlayHintPoll.pendingRequestId = reqId
    e.state.lspCache.inlayHintPoll.pendingFilePath = buf.filePath.get("")
    e.state.lspCache.inlayHintPoll.pendingContentVersion = buf.contentVersion

    e.updateInlayHintCache()

    check e.state.lspCache.inlayHintPoll.pendingRequestId == 0
    check e.state.lspCache.inlayHintCache.isValid
    check e.state.lspCache.getInlayHintsForLine(0).len == 1

  test "updateInlayHintCache discards an in-flight response from another buffer":
    # checkResponse routes by request id only, so without the buffer-id guard
    # file A's hints would be stamped onto and render inside file B's cache.
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.display.showInlayHint = true
    e.activeBuffer().filePath = some("/test/file.nim")
    discard e.activeBuffer().insertText(BufferPosition(line: 0, column: 0), "let x = 1")
    e.lsp.service.capabilities["nim"] =
      ServerCapabilities(inlayHintProvider: some(newJBool(true)))

    const reqId = 78
    let buf = e.activeBuffer()
    e.lsp.service.pendingResponses[reqId] = (
      result: some($(%*[{"position": {"line": 0, "character": 5}, "label": ": int"}])),
      error: none(string),
    )
    e.state.lspCache.inlayHintPoll.pendingRequestId = reqId
    # Request was made for a different buffer than the current active one.
    # Simulate by setting pendingFilePath to a different path.
    e.state.lspCache.inlayHintPoll.pendingFilePath = "/other/file.nim"

    e.updateInlayHintCache()

    check e.state.lspCache.inlayHintPoll.pendingRequestId == 0
    check not e.state.lspCache.inlayHintCache.isValid

suite "Virtual text provider gating":
  test "buildVirtualTextProviders skips a cache owned by another file":
    let e = createTestEditor()
    e.state.display.showInlayHint = true
    e.activeBuffer().filePath = some("/test/current.nim")
    e.state.lspCache.inlayHintCache.isValid = true
    e.state.lspCache.inlayHintCache.filePath = "/test/previous.nim"

    check e.buildVirtualTextProviders().len == 0

  test "buildVirtualTextProviders adds the provider for the owning file":
    let e = createTestEditor()
    e.state.display.showInlayHint = true
    e.activeBuffer().filePath = some("/test/current.nim")
    e.state.lspCache.inlayHintCache.isValid = true
    e.state.lspCache.inlayHintCache.filePath = "/test/current.nim"

    check e.buildVirtualTextProviders().len == 1

  test "buildVirtualTextProviders skips an invalid cache":
    let e = createTestEditor()
    e.state.display.showInlayHint = true
    e.activeBuffer().filePath = some("/test/current.nim")
    e.state.lspCache.inlayHintCache.isValid = false
    e.state.lspCache.inlayHintCache.filePath = "/test/current.nim"

    check e.buildVirtualTextProviders().len == 0
