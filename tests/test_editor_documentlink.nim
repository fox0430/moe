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

import std/[unittest, options]

import ../src/moepkg/[editor, config, config_loader]
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
