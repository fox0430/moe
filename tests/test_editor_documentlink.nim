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

## Tests for editor_documentlink.nim

import std/[unittest, options, importutils, json, os]

import ../src/moepkg/[editor, config, config_loader, buffer, lsp_service]
import ../src/moepkg/editor_documentlink
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

suite "editor_documentlink - startLspDocumentLinks":
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

suite "editor_documentlink - requestLspDocumentLinks":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.requestLspDocumentLinks()

    check not result

suite "editor_documentlink - pollLspDocumentLinks":
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

suite "editor_documentlink - pollLspDocumentLinkResolve":
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

suite "editor_documentlink - findDocumentLinkAtCursor":
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

suite "editor_documentlink - cursor rune -> UTF-16 conversion":
  privateAccess(LspService)

  test "Stores UTF-16 column for CJK line (rune index != byte offset)":
    let e = createTestEditor()
    e.lsp.enabled = true

    let path = getTempDir() / "test_doclink_cjk.nim"
    let buf = newTextBuffer("日本語テキスト https://example.com\n", some(path))
    e.state.activeWindow.buffer = buf

    # Advertise documentLink capability so hasDocumentLinkSupport() returns true.
    e.lsp.service.capabilities["nim"] =
      ServerCapabilities(documentLinkProvider: some(newJObject()))

    # Cursor at rune index 8 = 7 CJK runes + 1 space (start of "https").
    e.state.activeWindow.cursor.line = 0
    e.state.activeWindow.cursor.column = 8

    # startDocumentLinkRequest will fail (no worker), but the cursor column is
    # captured before the request is dispatched.
    discard e.startLspDocumentLinks()

    check e.state.lspCache.pendingDocumentLinkCursorLine == 0
    # 7 BMP runes = 7 UTF-16 units, + 1 space = 8. The old code passed the rune
    # index to utf8OffsetToUtf16 as a byte offset and returned 3.
    check e.state.lspCache.pendingDocumentLinkCursorCol == 8

  test "Stores UTF-16 column past an astral (surrogate-pair) rune":
    let e = createTestEditor()
    e.lsp.enabled = true

    let path = getTempDir() / "test_doclink_astral.nim"
    # "😀" is U+1F600 (astral): 1 rune, 4 UTF-8 bytes, 2 UTF-16 code units.
    let buf = newTextBuffer("😀 https://example.com\n", some(path))
    e.state.activeWindow.buffer = buf

    e.lsp.service.capabilities["nim"] =
      ServerCapabilities(documentLinkProvider: some(newJObject()))

    # Cursor at rune index 2 = 1 astral rune + 1 space (start of "https").
    e.state.activeWindow.cursor.line = 0
    e.state.activeWindow.cursor.column = 2

    discard e.startLspDocumentLinks()

    # 1 astral rune = 2 UTF-16 units, + 1 space = 3.
    check e.state.lspCache.pendingDocumentLinkCursorCol == 3

suite "editor_documentlink - mode-hijack guard":
  test "Stale response arriving in Insert does not jump":
    # A link jump would swap the active buffer under an Insert session.
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.mode = EditorMode.Insert
    let reqId = 6161
    e.state.lspCache.pendingDocumentLinkRequestId = reqId
    let bufBefore = e.state.activeWindow.buffer
    privateAccess(LspService)
    let linkJson = %*[
      {
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 5}},
        "target": "file:///tmp/other.nim",
      }
    ]
    e.lsp.service.pendingResponses[reqId] =
      (result: some($linkJson), error: none(string))

    e.pollLspDocumentLinks()

    check e.state.mode == EditorMode.Insert
    check e.state.lspCache.pendingDocumentLinkRequestId == 0
    check e.state.activeWindow.buffer == bufBefore
