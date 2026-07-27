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

import std/[unittest, options, importutils, json, os, tables]
from std/strutils import contains

import ../src/moepkg/[editor, config, config_loader, lsp_service, types]
import ../src/moepkg/buffer/core
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

# The old "Stores UTF-16 column ..." integration tests relied on a cache-on-
# failure side effect that no longer exists: `startContextualRequest` skips
# populating `pending[lrfDocumentLink]` when the underlying request errors.
# The pure UTF-16 conversion is still covered by
# `test_lsp_integration.nim` (`runeIndexToUtf16 with ...`).

suite "editor_documentlink - UTF-16 cursor conversion":
  test "pollLspDocumentLinks converts cursor to UTF-16 before matching link":
    # Regression guard for `pollLspDocumentLinks` -> `runeIndexToUtf16` ->
    # `findDocumentLinkAtCursor` wiring. If the conversion is missing, the
    # rune index passed directly to `findDocumentLinkAtCursor` cannot align
    # with an LSP range (UTF-16 code units) past an astral rune.
    let e = createTestEditor()
    let testFile = getTempDir() / "moe_test_doclink_utf16.txt"
    # Astral pile of poo (U+1F4A9) occupies 2 UTF-16 code units. Rune index
    # of 'b' is 2; UTF-16 index of 'b' is 3.
    writeFile(testFile, "\xF0\x9F\x92\xA9ab\n")
    defer:
      removeFile(testFile)
    discard e.editFile(testFile)
    e.lsp.enabled = true
    e.state.mode = EditorMode.Normal
    e.state.activeWindow.cursor = BufferPosition(line: 0, column: 2)
    let reqId = 6162
    let buf = e.activeBuffer
    e.state.lspCache.pending[lrfDocumentLink] = LspRequestContext(
      requestId: reqId,
      feature: lrfDocumentLink,
      bufferId: buf.id,
      contentVersion: buf.contentVersion,
      path: testFile,
      generation: 1,
      cursorLine: -1,
      cursorCol: -1,
      validModes: DocumentLinkValidModes,
      blockedByOverlay: true,
    )
    privateAccess(LspService)
    # Link range [3, 4) in UTF-16 — matches only when the cursor is converted.
    let linkJson = %*[
      {
        "range":
          {"start": {"line": 0, "character": 3}, "end": {"line": 0, "character": 4}},
        "target": "file:///tmp/moe_documentlink_utf16_target.nonexistent",
      }
    ]
    e.lsp.service.pendingResponses[reqId] =
      (result: some($linkJson), error: none(string))

    e.pollLspDocumentLinks()

    # A missing conversion would surface the "No link at cursor position"
    # branch; a working one dispatches to `jumpToDocumentLink`, whose result
    # for a non-existent path is a "Failed to open file" status.
    check "No link at cursor position" notin e.state.statusMessage

suite "editor_documentlink - mode-hijack guard":
  test "Stale response arriving in Insert does not jump":
    # A link jump would swap the active buffer under an Insert session.
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.mode = EditorMode.Insert
    let reqId = 6161
    let buf = e.activeBuffer
    e.state.lspCache.pending[lrfDocumentLink] = LspRequestContext(
      requestId: reqId,
      feature: lrfDocumentLink,
      bufferId: buf.id,
      contentVersion: buf.contentVersion,
      path: "/tmp/x.nim",
      generation: 1,
      cursorLine: 0,
      cursorCol: 0,
      validModes: DocumentLinkValidModes,
      blockedByOverlay: true,
    )
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
    check not e.state.lspCache.pending.hasKey(lrfDocumentLink)
    check e.state.activeWindow.buffer == bufBefore
