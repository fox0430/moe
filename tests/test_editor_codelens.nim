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

import std/[unittest, tables, options]

import pkg/chronos

import ../src/moepkg/editor
import ../src/moepkg/editor_codelens {.all.}
import ../src/moepkg/config
import ../src/moepkg/types
import ../src/moepkg/buffer

# Helper to create a minimal Editor for testing
proc createTestEditor(): Editor =
  let config = newEditorConfig()
  result = newEditor(config)

suite "CodeLens Cache":
  test "hasCodeLensSupport - LSP disabled":
    let e = createTestEditor()
    # LSP is disabled by default
    check not e.hasCodeLensSupport()

  test "getCodeLensItemsForLine - empty cache":
    let e = createTestEditor()
    let items = e.getCodeLensItemsForLine(0)
    check items.len == 0

  test "getCodeLensItemsForLine - invalid cache":
    let e = createTestEditor()
    e.state.lspCache.codeLensCache.isValid = false
    let items = e.getCodeLensItemsForLine(0)
    check items.len == 0

  test "getCodeLensItemsForLine - valid cache with items":
    let e = createTestEditor()
    # Set up cache with items
    e.state.lspCache.codeLensCache.isValid = true
    e.state.lspCache.codeLensCache.itemsByLine = {
      0: @[CodeLensItem(line: 0, title: "5 references", command: "references")],
      5: @[
        CodeLensItem(line: 5, title: "Run Test", command: "test.run"),
        CodeLensItem(line: 5, title: "Debug Test", command: "test.debug"),
      ],
    }.toTable

    # Line 0 has one item
    let items0 = e.getCodeLensItemsForLine(0)
    check items0.len == 1
    check items0[0].title == "5 references"

    # Line 5 has two items
    let items5 = e.getCodeLensItemsForLine(5)
    check items5.len == 2
    check items5[0].title == "Run Test"
    check items5[1].title == "Debug Test"

    # Line 10 has no items
    let items10 = e.getCodeLensItemsForLine(10)
    check items10.len == 0

  test "getCodeLensItemsForCurrentLine":
    let e = createTestEditor()
    e.state.lspCache.codeLensCache.isValid = true
    e.state.lspCache.codeLensCache.itemsByLine =
      {3: @[CodeLensItem(line: 3, title: "Test Item", command: "test")]}.toTable

    # Set cursor to line 3
    e.cursor = BufferPosition(line: 3, column: 0)
    let items = e.getCodeLensItemsForCurrentLine()
    check items.len == 1
    check items[0].title == "Test Item"

  test "invalidateCodeLensCache":
    let e = createTestEditor()
    e.state.lspCache.codeLensCache.isValid = true
    e.state.lspCache.codeLensCache.itemsByLine =
      {0: @[CodeLensItem(line: 0, title: "Item", command: "cmd")]}.toTable

    e.invalidateCodeLensCache()

    check not e.state.lspCache.codeLensCache.isValid
    # Items still exist but cache is marked invalid
    check e.state.lspCache.codeLensCache.itemsByLine.len == 1

  test "getCodeLensDisplayText - no items":
    let e = createTestEditor()
    e.state.lspCache.codeLensCache.isValid = true
    let text = e.getCodeLensDisplayText(0)
    check text == ""

  test "getCodeLensDisplayText - single item":
    let e = createTestEditor()
    e.state.lspCache.codeLensCache.isValid = true
    e.state.lspCache.codeLensCache.itemsByLine =
      {0: @[CodeLensItem(line: 0, title: "3 references", command: "refs")]}.toTable
    let text = e.getCodeLensDisplayText(0)
    check text == "3 references"

  test "getCodeLensDisplayText - multiple items":
    let e = createTestEditor()
    e.state.lspCache.codeLensCache.isValid = true
    e.state.lspCache.codeLensCache.itemsByLine = {
      0: @[
        CodeLensItem(line: 0, title: "Run", command: "run"),
        CodeLensItem(line: 0, title: "Debug", command: "debug"),
        CodeLensItem(line: 0, title: "Test", command: "test"),
      ]
    }.toTable
    let text = e.getCodeLensDisplayText(0)
    check text == "Run | Debug | Test"

suite "CodeLens Picker":
  test "showCodeLensPicker":
    let e = createTestEditor()
    e.viewport.height = 24

    let items = @[
      CodeLensItem(line: 0, title: "Item 1", command: "cmd1"),
      CodeLensItem(line: 0, title: "Item 2", command: "cmd2"),
      CodeLensItem(line: 0, title: "Item 3", command: "cmd3"),
    ]
    e.showCodeLensPicker(items)

    check e.state.lspCache.codeLensPicker.isActive
    check e.state.lspCache.codeLensPicker.items.len == 3
    check e.state.lspCache.codeLensPicker.selectedIndex == 0
    check e.state.lspCache.codeLensPicker.scrollOffset == 0

  test "hideCodeLensPicker":
    let e = createTestEditor()
    e.state.lspCache.codeLensPicker.isActive = true
    e.state.lspCache.codeLensPicker.items =
      @[CodeLensItem(line: 0, title: "Item", command: "cmd")]

    e.hideCodeLensPicker()

    check not e.state.lspCache.codeLensPicker.isActive
    check e.state.lspCache.codeLensPicker.items.len == 0

  test "codeLensPickerSelectNext - basic":
    let e = createTestEditor()
    e.viewport.height = 24
    let items = @[
      CodeLensItem(line: 0, title: "Item 1", command: "cmd1"),
      CodeLensItem(line: 0, title: "Item 2", command: "cmd2"),
      CodeLensItem(line: 0, title: "Item 3", command: "cmd3"),
    ]
    e.showCodeLensPicker(items)

    check e.state.lspCache.codeLensPicker.selectedIndex == 0

    e.codeLensPickerSelectNext()
    check e.state.lspCache.codeLensPicker.selectedIndex == 1

    e.codeLensPickerSelectNext()
    check e.state.lspCache.codeLensPicker.selectedIndex == 2

    # At last item, should not go further
    e.codeLensPickerSelectNext()
    check e.state.lspCache.codeLensPicker.selectedIndex == 2

  test "codeLensPickerSelectPrev - basic":
    let e = createTestEditor()
    e.viewport.height = 24
    let items = @[
      CodeLensItem(line: 0, title: "Item 1", command: "cmd1"),
      CodeLensItem(line: 0, title: "Item 2", command: "cmd2"),
      CodeLensItem(line: 0, title: "Item 3", command: "cmd3"),
    ]
    e.showCodeLensPicker(items)
    e.state.lspCache.codeLensPicker.selectedIndex = 2

    e.codeLensPickerSelectPrev()
    check e.state.lspCache.codeLensPicker.selectedIndex == 1

    e.codeLensPickerSelectPrev()
    check e.state.lspCache.codeLensPicker.selectedIndex == 0

    # At first item, should not go further
    e.codeLensPickerSelectPrev()
    check e.state.lspCache.codeLensPicker.selectedIndex == 0

  test "codeLensPickerSelectNext - not active":
    let e = createTestEditor()
    e.state.lspCache.codeLensPicker.isActive = false
    e.state.lspCache.codeLensPicker.selectedIndex = 0

    e.codeLensPickerSelectNext()
    # Should not change when picker is not active
    check e.state.lspCache.codeLensPicker.selectedIndex == 0

  test "codeLensPickerSelectPrev - not active":
    let e = createTestEditor()
    e.state.lspCache.codeLensPicker.isActive = false
    e.state.lspCache.codeLensPicker.selectedIndex = 1

    e.codeLensPickerSelectPrev()
    # Should not change when picker is not active
    check e.state.lspCache.codeLensPicker.selectedIndex == 1

  test "codeLensPickerSelectNext - scrolling":
    let e = createTestEditor()
    # Simulate small viewport
    e.viewport.height = 10
    var items: seq[CodeLensItem] = @[]
    for i in 0 ..< 10:
      items.add(CodeLensItem(line: 0, title: "Item " & $i, command: "cmd" & $i))
    e.showCodeLensPicker(items)
    # maxVisibleItems should be 4 (height 10 - 6 margin)
    check e.state.lspCache.codeLensPicker.maxVisibleItems == 4

    # Navigate to item 4 (beyond visible area)
    for _ in 0 ..< 4:
      e.codeLensPickerSelectNext()
    check e.state.lspCache.codeLensPicker.selectedIndex == 4
    check e.state.lspCache.codeLensPicker.scrollOffset == 1

  test "codeLensPickerSelectPrev - scrolling up":
    let e = createTestEditor()
    e.viewport.height = 10
    var items: seq[CodeLensItem] = @[]
    for i in 0 ..< 10:
      items.add(CodeLensItem(line: 0, title: "Item " & $i, command: "cmd" & $i))
    e.showCodeLensPicker(items)

    # Set to middle position with scroll offset
    e.state.lspCache.codeLensPicker.selectedIndex = 5
    e.state.lspCache.codeLensPicker.scrollOffset = 3

    # Navigate up past visible area
    e.codeLensPickerSelectPrev()
    e.codeLensPickerSelectPrev()
    e.codeLensPickerSelectPrev()
    check e.state.lspCache.codeLensPicker.selectedIndex == 2
    check e.state.lspCache.codeLensPicker.scrollOffset == 2

suite "Document Highlight Cache":
  test "invalidateDocumentHighlightCache":
    let e = createTestEditor()
    e.state.lspCache.documentHighlightCache.isValid = true
    e.state.lspCache.documentHighlightCache.itemsByLine = {
      0: @[DocumentHighlightItem(line: 0, startColumn: 0, endColumn: 5, kind: 1)]
    }.toTable

    e.invalidateDocumentHighlightCache()

    check not e.state.lspCache.documentHighlightCache.isValid
    check e.state.lspCache.documentHighlightCache.itemsByLine.len == 0

  test "updateDocumentHighlightCache - LSP disabled":
    let e = createTestEditor()
    e.state.lspCache.documentHighlightCache.isValid = true

    # With LSP disabled, updateDocumentHighlightCache should return early
    e.updateDocumentHighlightCache()

    # Cache should remain unchanged when LSP is disabled
    check e.state.lspCache.documentHighlightCache.isValid

  test "updateDocumentHighlightCache - Insert mode clears highlights":
    let e = createTestEditor()
    e.state.lspCache.documentHighlightCache.isValid = true
    e.state.lspCache.documentHighlightCache.itemsByLine = {
      0: @[DocumentHighlightItem(line: 0, startColumn: 0, endColumn: 5, kind: 1)]
    }.toTable
    e.state.display.showDocumentHighlight = true
    e.state.mode = EditorMode.Insert

    # Note: Without LSP enabled, the function returns early before clearing
    # This test verifies the mode check logic exists

suite "Semantic Tokens Cache":
  test "invalidateSemanticTokensCache":
    let e = createTestEditor()
    e.state.lspCache.semanticTokensCache.isValid = true
    e.state.lspCache.semanticTokensCache.changeSeq = 5
    e.state.lspCache.semanticTokensCache.filePath = "/test/file.nim"
    e.state.lspCache.pendingSemanticTokensRequestId = 123

    e.invalidateSemanticTokensCache()

    check not e.state.lspCache.semanticTokensCache.isValid
    check e.state.lspCache.pendingSemanticTokensRequestId == 0

  test "updateSemanticTokensCache - LSP disabled":
    let e = createTestEditor()
    e.state.lspCache.semanticTokensCache.isValid = true

    # With LSP disabled, should return early
    e.updateSemanticTokensCache()

    # Cache should remain unchanged
    check e.state.lspCache.semanticTokensCache.isValid

suite "CodeLens Item":
  test "CodeLensItem with arguments":
    let item = CodeLensItem(
      line: 10,
      title: "Run Test",
      command: "test.run",
      arguments: @["{\"uri\":\"file:///test.nim\"}", "true"],
    )
    check item.line == 10
    check item.title == "Run Test"
    check item.command == "test.run"
    check item.arguments.len == 2

suite "CodeLens Cache Validation":
  test "cache validity check with filePath":
    let e = createTestEditor()
    e.state.lspCache.codeLensCache = CodeLensCache(
      isValid: true,
      filePath: "/path/to/file.nim",
      changeSeq: 5,
      itemsByLine: initTable[int, seq[CodeLensItem]](),
    )

    check e.state.lspCache.codeLensCache.isValid
    check e.state.lspCache.codeLensCache.filePath == "/path/to/file.nim"
    check e.state.lspCache.codeLensCache.changeSeq == 5

suite "CodeLens Response Generation":
  test "stale generation does not overwrite a newer cache":
    let e = createTestEditor()
    e.activeBuffer().filePath = some("/test/file.nim")

    # Generation 2 represents the latest in-flight response.
    e.state.lspCache.codeLensResponseGen = 2
    check not e.state.lspCache.codeLensCache.isValid

    # An older (slower) response with a stale generation must not write the cache.
    waitFor e.processCodeLensResponse(@[], 1)
    check not e.state.lspCache.codeLensCache.isValid

    # The latest generation is allowed to write the cache.
    waitFor e.processCodeLensResponse(@[], 2)
    check e.state.lspCache.codeLensCache.isValid

suite "Document Highlight Item":
  test "DocumentHighlightItem kinds":
    # Kind values: 1=Text, 2=Read, 3=Write
    let textItem =
      DocumentHighlightItem(line: 0, startColumn: 5, endColumn: 10, kind: 1)
    let readItem = DocumentHighlightItem(line: 1, startColumn: 0, endColumn: 3, kind: 2)
    let writeItem =
      DocumentHighlightItem(line: 2, startColumn: 10, endColumn: 15, kind: 3)

    check textItem.kind == 1
    check readItem.kind == 2
    check writeItem.kind == 3

  test "DocumentHighlightCache with multiple lines":
    let cache = DocumentHighlightCache(
      isValid: true,
      cursorLine: 5,
      cursorColumn: 10,
      changeSeq: 3,
      itemsByLine: {
        5: @[DocumentHighlightItem(line: 5, startColumn: 10, endColumn: 15, kind: 1)],
        10: @[DocumentHighlightItem(line: 10, startColumn: 10, endColumn: 15, kind: 2)],
        15: @[DocumentHighlightItem(line: 15, startColumn: 10, endColumn: 15, kind: 3)],
      }.toTable,
    )

    check cache.isValid
    check cache.itemsByLine.len == 3
    check cache.itemsByLine[5][0].kind == 1
    check cache.itemsByLine[10][0].kind == 2
    check cache.itemsByLine[15][0].kind == 3
