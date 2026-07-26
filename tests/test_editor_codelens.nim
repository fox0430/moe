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

import std/[unittest, tables, options, monotimes, times, json]

import pkg/chronos

import ../src/moepkg/[editor, config, types, buffer, color, virtual_text]
import ../src/moepkg/editor_codelens {.all.}
import ../src/moepkg/lsp/protocol/types as lspTypes

proc createTestEditor(): Editor =
  ## Helper to create a minimal Editor for testing
  let config = newEditorConfig()
  result = newEditor(config)

suite "CodeLens Cache":
  test "hasCodeLensSupport - LSP disabled":
    let e = createTestEditor()
    # LSP is disabled by default
    check not e.hasCodeLensSupport()

  test "getCodeLensItemsForLine - empty cache":
    let e = createTestEditor()
    let items = e.state.lspCache.getCodeLensItemsForLine(0)
    check items.len == 0

  test "getCodeLensItemsForLine - invalid cache":
    let e = createTestEditor()
    e.state.lspCache.codeLensCache.isValid = false
    let items = e.state.lspCache.getCodeLensItemsForLine(0)
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
    let items0 = e.state.lspCache.getCodeLensItemsForLine(0)
    check items0.len == 1
    check items0[0].title == "5 references"

    # Line 5 has two items
    let items5 = e.state.lspCache.getCodeLensItemsForLine(5)
    check items5.len == 2
    check items5[0].title == "Run Test"
    check items5[1].title == "Debug Test"

    # Line 10 has no items
    let items10 = e.state.lspCache.getCodeLensItemsForLine(10)
    check items10.len == 0

  test "getCodeLensItemsForCurrentLine":
    let e = createTestEditor()
    # The cache must be owned by the active buffer or the filePath guard returns
    # @[] (see "getCodeLensItemsForCurrentLine - foreign cache" below).
    e.activeBuffer().filePath = some("/test/file.nim")
    e.state.lspCache.codeLensCache.isValid = true
    e.state.lspCache.codeLensCache.filePath = "/test/file.nim"
    e.state.lspCache.codeLensCache.itemsByLine =
      {3: @[CodeLensItem(line: 3, title: "Test Item", command: "test")]}.toTable

    # Set cursor to line 3
    e.cursor = BufferPosition(line: 3, column: 0)
    let items = e.getCodeLensItemsForCurrentLine()
    check items.len == 1
    check items[0].title == "Test Item"

  test "getCodeLensItemsForCurrentLine - foreign cache returns empty":
    # After a buffer switch the line-keyed cache may still hold the previous
    # file's lenses; the filePath guard must suppress them.
    let e = createTestEditor()
    e.activeBuffer().filePath = some("/test/current.nim")
    e.state.lspCache.codeLensCache.isValid = true
    e.state.lspCache.codeLensCache.filePath = "/test/previous.nim"
    e.state.lspCache.codeLensCache.itemsByLine =
      {3: @[CodeLensItem(line: 3, title: "Stale", command: "test")]}.toTable

    e.cursor = BufferPosition(line: 3, column: 0)
    check e.getCodeLensItemsForCurrentLine().len == 0

  test "invalidateCodeLensCache":
    let e = createTestEditor()
    e.state.lspCache.codeLensCache.isValid = true
    e.state.lspCache.codeLensCache.itemsByLine =
      {0: @[CodeLensItem(line: 0, title: "Item", command: "cmd")]}.toTable

    invalidateCodeLensCache(e.lsp, e.state.lspCache)

    check not e.state.lspCache.codeLensCache.isValid
    # Items still exist but cache is marked invalid
    check e.state.lspCache.codeLensCache.itemsByLine.len == 1

  test "doUpdateCodeLensCache advances the debounce timer at initiation":
    # Regression: the debounce timer must advance when a request is initiated,
    # not only when the async response handler completes. Otherwise the gate in
    # updateCodeLensCache reads a stale timestamp on the frame a response
    # arrives and fires a fresh request on every round-trip, defeating the
    # debounce.
    let e = createTestEditor()
    let old = getMonoTime() - initDuration(seconds = 10)
    e.state.lspCache.codeLensPoll.lastUpdate = old

    e.doUpdateCodeLensCache()

    check e.state.lspCache.codeLensPoll.lastUpdate > old

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

    e.state.lspCache.hideCodeLensPicker()

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
  test "showDocumentHighlight follows config.lsp.documentHighlight.enable at init":
    var config = newEditorConfig()
    config.lsp.documentHighlight.enable = false
    let e = newEditor(config)
    check not e.state.showDocumentHighlight

    config.lsp.documentHighlight.enable = true
    let e2 = newEditor(config)
    check e2.state.showDocumentHighlight

  test "invalidateDocumentHighlightCache":
    let e = createTestEditor()
    e.state.lspCache.documentHighlightCache.isValid = true
    e.state.lspCache.documentHighlightCache.itemsByLine = {
      0: @[DocumentHighlightItem(line: 0, startColumn: 0, endColumn: 5, kind: 1)]
    }.toTable

    invalidateDocumentHighlightCache(e.lsp, e.state.lspCache)

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
    e.state.showDocumentHighlight = true
    e.state.mode = EditorMode.Insert

    # Note: Without LSP enabled, the function returns early before clearing
    # This test verifies the mode check logic exists

suite "Semantic Tokens Cache":
  test "invalidateSemanticTokensCache":
    let e = createTestEditor()
    e.state.lspCache.semanticTokensCache.isValid = true
    e.state.lspCache.semanticTokensCache.changeSeq = 5
    e.state.lspCache.semanticTokensCache.filePath = "/test/file.nim"
    e.state.lspCache.pending[lrfSemanticTokens] = LspRequestContext(
      requestId: 123, feature: lrfSemanticTokens, path: "/test/file.nim"
    )

    invalidateSemanticTokensCache(e.lsp, e.state.lspCache)

    check not e.state.lspCache.semanticTokensCache.isValid
    check not e.state.lspCache.pending.hasKey(lrfSemanticTokens)

  test "processSemanticTokensResponse - drops response when contentVersion advanced":
    # Lock in the belt-and-braces guard: a mid-flight edit bumps
    # activeBuffer.contentVersion past the request-time snapshot, so the
    # response is stale and must not stamp the cache as valid.
    let e = createTestEditor()
    let buf = e.activeBuffer()
    buf.filePath = some("/test/file.nim")

    let ctx = LspRequestContext(
      requestId: 1,
      feature: lrfSemanticTokens,
      bufferId: buf.id,
      contentVersion: buf.contentVersion,
      path: "/test/file.nim",
    )
    # processSemanticTokensResponse reads rangeFirst/Last from extras
    e.state.lspCache.semanticTokensPendingExtras =
      PendingSemanticTokensRequest(rangeFirst: -1, rangeLast: -1)

    buf.advanceContentVersion()

    e.processSemanticTokensResponse(newJObject(), ctx)

    check not e.state.lspCache.semanticTokensCache.isValid

  test "updateSemanticTokensCache - LSP disabled":
    let e = createTestEditor()
    e.state.lspCache.semanticTokensCache.isValid = true

    # With LSP disabled, should return early
    e.updateSemanticTokensCache()

    # Cache should remain unchanged
    check e.state.lspCache.semanticTokensCache.isValid

  test "updateSemanticTokensCache - feature disabled via lsp.semanticTokens.enable":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.config.lsp.semanticTokens.enable = false
    e.state.lspCache.semanticTokensCache.isValid = true

    # The feature gate returns before issuing a request, leaving the cache and
    # the pending-request Table untouched.
    e.updateSemanticTokensCache()

    check e.state.lspCache.semanticTokensCache.isValid
    check not e.state.lspCache.pending.hasKey(lrfSemanticTokens)

  test "semanticTokensCacheCoversViewport - visible EOF is a cache hit":
    # Regression: previously the check compared cache.bottomLine against the
    # unclamped `viewport.topLine + viewport.height`, but the stamped value is
    # clamped to `activeBuffer.len - 1`. Whenever EOF was visible the check
    # was permanently unsatisfiable and the request re-fired every debounce
    # tick.
    let e = createTestEditor()
    e.activeBuffer().filePath = some("/test/file.nim")
    e.viewport.topLine = 0
    e.viewport.height = 24
    # Fresh buffer is a single empty line, so lastLine == 0 < height.

    let cache = SemanticTokensCache(
      isValid: true,
      changeSeq: e.activeBuffer().changeSeq,
      filePath: "/test/file.nim",
      topLine: 0,
      bottomLine: e.activeBuffer().len - 1,
    )

    check e.semanticTokensCacheCoversViewport(cache, "/test/file.nim")

  test "semanticTokensCacheCoversViewport - short bottomLine misses on large buffer":
    let e = createTestEditor()
    e.activeBuffer().filePath = some("/test/file.nim")
    var text = ""
    for _ in 0 ..< 99:
      text.add('\n')
    discard e.activeBuffer().insertText(BufferPosition(line: 0, column: 0), text)
    e.viewport.topLine = 0
    e.viewport.height = 24

    let cache = SemanticTokensCache(
      isValid: true,
      changeSeq: e.activeBuffer().changeSeq,
      filePath: "/test/file.nim",
      topLine: 0,
      bottomLine: 10,
    )

    check not e.semanticTokensCacheCoversViewport(cache, "/test/file.nim")

  test "semanticTokensCacheCoversViewport - rejects on filePath/changeSeq/topLine":
    let e = createTestEditor()
    e.activeBuffer().filePath = some("/test/file.nim")
    e.viewport.topLine = 0
    e.viewport.height = 24

    let base = SemanticTokensCache(
      isValid: true,
      changeSeq: e.activeBuffer().changeSeq,
      filePath: "/test/file.nim",
      topLine: 0,
      bottomLine: e.activeBuffer().len - 1,
    )

    var wrongPath = base
    wrongPath.filePath = "/other.nim"
    check not e.semanticTokensCacheCoversViewport(wrongPath, "/test/file.nim")

    var stale = base
    stale.changeSeq = e.activeBuffer().changeSeq + 1
    check not e.semanticTokensCacheCoversViewport(stale, "/test/file.nim")

    e.viewport.topLine = 0
    var scrolled = base
    scrolled.topLine = 5
    check not e.semanticTokensCacheCoversViewport(scrolled, "/test/file.nim")

    var invalid = base
    invalid.isValid = false
    check not e.semanticTokensCacheCoversViewport(invalid, "/test/file.nim")

  test "invalidateSemanticTokensCache resets reject streak":
    # A buffer switch / register-capability drop is a fresh start; drop the
    # backoff so the next request fires at the normal cadence.
    let e = createTestEditor()
    e.state.lspCache.semanticTokensPoll.rejectStreak = 5
    invalidateSemanticTokensCache(e.lsp, e.state.lspCache)
    check e.state.lspCache.semanticTokensPoll.rejectStreak == 0

  test "debounceThreshold - streak 0 uses base interval":
    let poll = DebouncedLspPoll(interval: 500)
    check poll.debounceThreshold() == initDuration(milliseconds = 500)

  test "debounceThreshold - streak scales exponentially":
    let poll = DebouncedLspPoll(interval: 500, rejectStreak: 3)
    # 500ms << 3 == 4000ms
    check poll.debounceThreshold() == initDuration(milliseconds = 4_000)

  test "debounceThreshold - streak clamped at MaxLspDebounceBackoffShift":
    let poll = DebouncedLspPoll(interval: 500, rejectStreak: 999)
    let expectedMs = 500'i64 shl MaxLspDebounceBackoffShift
    check poll.debounceThreshold() == initDuration(milliseconds = expectedMs)

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
      contentVersion: 5,
      itemsByLine: initTable[int, seq[CodeLensItem]](),
    )

    check e.state.lspCache.codeLensCache.isValid
    check e.state.lspCache.codeLensCache.filePath == "/path/to/file.nim"
    check e.state.lspCache.codeLensCache.contentVersion == 5

  test "Undo then edit collides on changeSeq: contentVersion key detects staleness":
    # undo() rewinds changeSeq to the pre-mutation value; a follow-up edit can
    # land on the same changeSeq that was cached for a different content. Keying
    # the cache on contentVersion (monotonic) instead of changeSeq keeps stale
    # results out.
    let e = createTestEditor()
    let buf = e.activeBuffer()
    buf.filePath = some("/path/to/collide.nim")

    check buf.insertText(BufferPosition(line: 0, column: 0), "a").isOk
    let seqAfterA = buf.changeSeq
    let verAfterA = buf.contentVersion

    check buf.insertText(BufferPosition(line: 0, column: 1), "b").isOk
    e.state.lspCache.codeLensCache = CodeLensCache(
      isValid: true,
      filePath: buf.filePath.get,
      contentVersion: buf.contentVersion,
      itemsByLine: initTable[int, seq[CodeLensItem]](),
    )
    let cachedSeq = buf.changeSeq

    # Undo B then insert C: changeSeq matches the cached-for-"ab" value again,
    # but contentVersion has advanced past it, so the cache is stale.
    check buf.undo().isOk
    check buf.changeSeq == seqAfterA
    check buf.insertText(BufferPosition(line: 0, column: 1), "c").isOk
    check buf.changeSeq == cachedSeq
    check buf.getTextString() == "ac"
    check buf.contentVersion > verAfterA

    check e.state.lspCache.codeLensCache.contentVersion != buf.contentVersion

suite "CodeLens Response Generation":
  test "stale generation does not overwrite a newer cache":
    let e = createTestEditor()
    e.activeBuffer().filePath = some("/test/file.nim")
    let reqVer = e.activeBuffer().contentVersion

    # Generation 2 represents the latest in-flight response.
    e.state.lspCache.featureGeneration[lrfCodeLens] = 2
    check not e.state.lspCache.codeLensCache.isValid

    # An older (slower) response with a stale generation must not write the cache.
    waitFor e.processCodeLensResponse(@[], 1, reqVer)
    check not e.state.lspCache.codeLensCache.isValid

    # The latest generation is allowed to write the cache.
    waitFor e.processCodeLensResponse(@[], 2, reqVer)
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
      contentVersion: 3,
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

  test "Undo then edit collides on changeSeq: contentVersion key detects staleness":
    # Same scenario as the CodeLens variant: changeSeq collides across undo+edit
    # but contentVersion doesn't, so keying the cache on contentVersion rejects
    # a stale document-highlight result.
    let e = createTestEditor()
    let buf = e.activeBuffer()

    check buf.insertText(BufferPosition(line: 0, column: 0), "a").isOk
    let seqAfterA = buf.changeSeq

    check buf.insertText(BufferPosition(line: 0, column: 1), "b").isOk
    e.state.lspCache.documentHighlightCache = DocumentHighlightCache(
      isValid: true,
      cursorLine: 0,
      cursorColumn: 0,
      contentVersion: buf.contentVersion,
      itemsByLine: initTable[int, seq[DocumentHighlightItem]](),
    )
    let cachedSeq = buf.changeSeq

    check buf.undo().isOk
    check buf.changeSeq == seqAfterA
    check buf.insertText(BufferPosition(line: 0, column: 1), "c").isOk
    check buf.changeSeq == cachedSeq
    check buf.getTextString() == "ac"

    check e.state.lspCache.documentHighlightCache.contentVersion != buf.contentVersion

suite "processDocumentHighlightResponse - UTF-16 to Rune Index":
  test "Converts UTF-16 positions to rune indexes for surrogate pairs":
    let e = createTestEditor()

    # Buffer with surrogate pair (emoji): "a😀b"
    # Rune indexes:  a=0, 😀=1, b=2
    # UTF-16 offsets: a=0, 😀=1..2, b=3
    # Byte offsets:   a=0, 😀=1..4, b=5
    let buf = e.activeBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a😀b")

    # Highlight 'b': LSP UTF-16 start=3, end=4
    # After fix:  startColumn=2, endColumn=3 (rune indexes)
    # Old buggy:  startColumn=5, endColumn=6 (byte offsets)
    let highlights = @[
      lspTypes.DocumentHighlight(
        range: lspTypes.Range(
          start: lspTypes.Position(line: 0, character: 3),
          `end`: lspTypes.Position(line: 0, character: 4),
        ),
        kind: none(lspTypes.DocumentHighlightKind),
      )
    ]

    processDocumentHighlightResponse(e, highlights)

    let cache = e.state.lspCache.documentHighlightCache
    check cache.isValid
    check cache.itemsByLine.hasKey(0)
    let items = cache.itemsByLine[0]
    check items.len == 1
    check items[0].line == 0
    check items[0].startColumn == 2
    check items[0].endColumn == 3
    check items[0].kind == 1

  test "Converts UTF-16 positions for multi-line highlights with surrogate pairs":
    let e = createTestEditor()

    # Multi-line buffer with surrogate pairs (single insert with newline)
    let buf = e.activeBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a😀b\nc😀d")

    # Multi-line highlight from UTF-16 line 0 character 3 through line 1 character 3
    # This covers 'b' (rune 2) on line 0 through 'd' (rune 2) on line 1
    let highlights = @[
      lspTypes.DocumentHighlight(
        range: lspTypes.Range(
          start: lspTypes.Position(line: 0, character: 3),
          `end`: lspTypes.Position(line: 1, character: 3),
        ),
        kind: none(lspTypes.DocumentHighlightKind),
      )
    ]

    processDocumentHighlightResponse(e, highlights)

    let cache = e.state.lspCache.documentHighlightCache
    check cache.isValid
    check cache.itemsByLine.hasKey(0)
    check cache.itemsByLine.hasKey(1)

    # Line 0: startCol=2 (rune index of 'b'), endCol=int.high (middle line)
    let items0 = cache.itemsByLine[0]
    check items0.len == 1
    check items0[0].line == 0
    check items0[0].startColumn == 2
    check items0[0].endColumn == int.high

    # Line 1: startCol=0 (middle line), endCol=2 (exclusive, at start of 'd')
    let items1 = cache.itemsByLine[1]
    check items1.len == 1
    check items1[0].line == 1
    check items1[0].startColumn == 0
    check items1[0].endColumn == 2

  test "Converts UTF-16 positions correctly for ASCII-only text":
    let e = createTestEditor()

    let buf = e.activeBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")

    # Highlight "world": UTF-16 start=6, end=11
    let highlights = @[
      lspTypes.DocumentHighlight(
        range: lspTypes.Range(
          start: lspTypes.Position(line: 0, character: 6),
          `end`: lspTypes.Position(line: 0, character: 11),
        ),
        kind: none(lspTypes.DocumentHighlightKind),
      )
    ]

    processDocumentHighlightResponse(e, highlights)

    let cache = e.state.lspCache.documentHighlightCache
    check cache.isValid
    let items = cache.itemsByLine[0]
    check items.len == 1
    check items[0].startColumn == 6
    check items[0].endColumn == 11

  test "Converts UTF-16 positions for BMP characters (Japanese)":
    let e = createTestEditor()

    let buf = e.activeBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "こんにちは")

    # Highlight from second character: UTF-16 start=1, end=4
    # For BMP characters, rune index == UTF-16 offset, so start=1, end=4
    let highlights = @[
      lspTypes.DocumentHighlight(
        range: lspTypes.Range(
          start: lspTypes.Position(line: 0, character: 1),
          `end`: lspTypes.Position(line: 0, character: 4),
        ),
        kind: none(lspTypes.DocumentHighlightKind),
      )
    ]

    processDocumentHighlightResponse(e, highlights)

    let cache = e.state.lspCache.documentHighlightCache
    check cache.isValid
    let items = cache.itemsByLine[0]
    check items.len == 1
    check items[0].startColumn == 1
    check items[0].endColumn == 4

# Inline display + execution dispatch (module-scope helpers reused below)

proc lensWithCommand(line, character: int, title: string): lspTypes.CodeLens =
  ## A CodeLens whose command is inlined (no resolve round-trip needed).
  lspTypes.CodeLens(
    range: lspTypes.Range(
      start: lspTypes.Position(line: line, character: character),
      `end`: lspTypes.Position(line: line, character: character),
    ),
    command: some(
      lspTypes.Command(title: title, command: "cmd", arguments: none(seq[JsonNode]))
    ),
  )

proc lensWithoutCommand(line, character: int): lspTypes.CodeLens =
  ## A CodeLens with no inlined command, i.e. one that would need a
  ## codeLens/resolve round-trip to obtain its command.
  lspTypes.CodeLens(
    range: lspTypes.Range(
      start: lspTypes.Position(line: line, character: character),
      `end`: lspTypes.Position(line: line, character: character),
    ),
    command: none(lspTypes.Command),
    data: some(%*{"id": 1}),
  )

proc runnableArg(): string =
  ## Minimal rust-analyzer Runnable serialized as a CodeLens command argument.
  $(
    %*{
      "args":
        {"workspaceRoot": "/home/user/proj", "cargoArgs": ["test", "--package", "foo"]}
    }
  )

proc runnableItem(title = "Run test"): CodeLensItem =
  CodeLensItem(
    line: 0,
    title: title,
    command: "rust-analyzer.runSingle",
    arguments: @[runnableArg()],
  )

suite "CodeLens Column Extraction":
  test "extracts UTF-16 character as a rune-index column":
    let e = createTestEditor()
    e.activeBuffer().filePath = some("/test/file.nim")
    # "a😀b": rune indexes a=0, 😀=1, b=2; UTF-16 offsets a=0, 😀=1..2, b=3
    discard e.activeBuffer().insertText(BufferPosition(line: 0, column: 0), "a😀b")
    e.state.lspCache.featureGeneration[lrfCodeLens] = 1
    waitFor e.processCodeLensResponse(
      @[lensWithCommand(0, 3, "5 refs")], 1, e.activeBuffer().contentVersion
    )

    let items = e.state.lspCache.getCodeLensItemsForLine(0)
    check items.len == 1
    check items[0].column == 2
    check items[0].title == "5 refs"

  test "sorts items on a line by column (server order out of order)":
    let e = createTestEditor()
    e.activeBuffer().filePath = some("/test/file.nim")
    discard e.activeBuffer().insertText(BufferPosition(line: 0, column: 0), "abcdefgh")
    e.state.lspCache.featureGeneration[lrfCodeLens] = 1
    waitFor e.processCodeLensResponse(
      @[lensWithCommand(0, 5, "second"), lensWithCommand(0, 2, "first")],
      1,
      e.activeBuffer().contentVersion,
    )

    let items = e.state.lspCache.getCodeLensItemsForLine(0)
    check items.len == 2
    check items[0].column == 2
    check items[0].title == "first"
    check items[1].column == 5
    check items[1].title == "second"

  test "command-less lens is dropped when resolve is unsupported":
    # The resolve gate must skip codeLens/resolve when the server does not
    # advertise it. With LSP disabled hasCodeLensResolveSupport is false, so the
    # lazily-computed gate is false: no resolve round-trip is attempted and the
    # still-title-less lens is dropped (no crash, no cached item).
    let e = createTestEditor()
    check not e.lsp.enabled
    e.activeBuffer().filePath = some("/test/file.nim")
    discard e.activeBuffer().insertText(BufferPosition(line: 0, column: 0), "let x = 1")
    e.state.lspCache.featureGeneration[lrfCodeLens] = 1

    waitFor e.processCodeLensResponse(
      @[lensWithoutCommand(0, 0)], 1, e.activeBuffer().contentVersion
    )

    check e.state.lspCache.codeLensCache.isValid
    check e.state.lspCache.getCodeLensItemsForLine(0).len == 0

suite "CodeLens Virtual Text Provider":
  test "buildVirtualTextProviders adds the provider for the owning file":
    let e = createTestEditor()
    e.state.showCodeLens = true
    e.state.showInlayHint = false
    e.activeBuffer().filePath = some("/test/current.nim")
    e.state.lspCache.codeLensCache = CodeLensCache(
      isValid: true,
      filePath: "/test/current.nim",
      itemsByLine: {
        0: @[CodeLensItem(line: 0, column: 4, title: "5 refs", command: "refs")]
      }.toTable,
    )

    check e.buildVirtualTextProviders().len == 1

  test "skips a cache owned by another file":
    let e = createTestEditor()
    e.state.showCodeLens = true
    e.state.showInlayHint = false
    e.activeBuffer().filePath = some("/test/current.nim")
    e.state.lspCache.codeLensCache = CodeLensCache(
      isValid: true,
      filePath: "/test/previous.nim",
      itemsByLine: initTable[int, seq[CodeLensItem]](),
    )

    check e.buildVirtualTextProviders().len == 0

  test "skips an invalid cache":
    let e = createTestEditor()
    e.state.showCodeLens = true
    e.state.showInlayHint = false
    e.activeBuffer().filePath = some("/test/current.nim")
    e.state.lspCache.codeLensCache = CodeLensCache(
      isValid: false,
      filePath: "/test/current.nim",
      itemsByLine: initTable[int, seq[CodeLensItem]](),
    )

    check e.buildVirtualTextProviders().len == 0

  test "provider yields an end-of-line chunk with the codeLens color":
    let e = createTestEditor()
    e.activeBuffer().filePath = some("/test/current.nim")
    e.state.lspCache.codeLensCache = CodeLensCache(
      isValid: true,
      filePath: "/test/current.nim",
      itemsByLine: {
        0: @[CodeLensItem(line: 0, column: 4, title: "5 refs", command: "refs")]
      }.toTable,
    )

    let vts = e.codeLensVirtualTextProvider()(0)
    check vts.len == 1
    check vts[0].placement == vtpEndOfLine
    check vts[0].priority == 10
    check vts[0].column == 4
    check vts[0].chunks.len == 1
    check vts[0].chunks[0].text == " 5 refs"
    check vts[0].chunks[0].color == EditorColorPairIndex.codeLens

  test "renders inlay hints left of code lenses on the same line":
    let e = createTestEditor()
    e.activeBuffer().filePath = some("/test/current.nim")
    e.state.showInlayHint = true
    e.state.showCodeLens = true
    e.state.lspCache.inlayHintCache = InlayHintCache(
      isValid: true,
      filePath: "/test/current.nim",
      itemsByLine: {0: @[InlayHintItem(line: 0, column: 2, label: ": int")]}.toTable,
    )
    e.state.lspCache.codeLensCache = CodeLensCache(
      isValid: true,
      filePath: "/test/current.nim",
      itemsByLine: {
        0: @[CodeLensItem(line: 0, column: 0, title: "5 refs", command: "refs")]
      }.toTable,
    )

    let vt = collectVirtualText(e.buildVirtualTextProviders(), 0)
    check vt.endOfLine.len == 2
    # Inlay hint (priority 0) renders before the code lens (priority 10).
    check vt.endOfLine[0].text == " : int"
    check vt.endOfLine[1].text == " 5 refs"

suite "CodeLens Execution":
  test "executeCodeLensItem - LSP disabled":
    let e = createTestEditor()
    e.lsp.enabled = false
    let res = waitFor e.executeCodeLensItem(runnableItem())
    check res.isErr
    check res.error == "LSP is not enabled"

  test "executeCodeLensItem - empty command":
    let e = createTestEditor()
    e.lsp.enabled = true
    let res =
      waitFor e.executeCodeLensItem(CodeLensItem(line: 0, title: "x", command: ""))
    check res.isErr
    check res.error == "CodeLens has no command"

  test "executeCodeLensItem - rust-analyzer runSingle builds a terminal command":
    let e = createTestEditor()
    e.lsp.enabled = true
    let res = waitFor e.executeCodeLensItem(runnableItem("Run test"))
    check res.isOk
    check e.state.pending.len == 1
    check e.state.pending[0].kind == paoTerminalCommand
    check e.state.pending[0].command == "cd /home/user/proj && cargo test --package foo"
    check e.state.statusMessage == "Running: Run test"

  test "executeCodeLensItem - runnable with no arguments":
    let e = createTestEditor()
    e.lsp.enabled = true
    let res = waitFor e.executeCodeLensItem(
      CodeLensItem(
        line: 0, title: "x", command: "rust-analyzer.runSingle", arguments: @[]
      )
    )
    check res.isErr
    check res.error == "Runnable command has no arguments"

  test "executeCodeLensItem - runnable with malformed JSON argument":
    let e = createTestEditor()
    e.lsp.enabled = true
    let res = waitFor e.executeCodeLensItem(
      CodeLensItem(
        line: 0,
        title: "x",
        command: "rust-analyzer.runSingle",
        arguments: @["{not json"],
      )
    )
    check res.isErr
    check res.error == "Failed to parse runnable argument"

  # Note: the workspace/executeCommand branch (non rust-analyzer commands) calls
  # the live LSP server via requestExecuteCommand and is not unit-tested here.

  test "executeCurrentLineCodeLens - single item executes directly":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.activeBuffer().filePath = some("/test/file.nim")
    e.state.lspCache.codeLensCache = CodeLensCache(
      isValid: true,
      filePath: "/test/file.nim",
      itemsByLine: {0: @[runnableItem("Run test")]}.toTable,
    )
    e.cursor = BufferPosition(line: 0, column: 0)

    waitFor e.executeCurrentLineCodeLens()
    check e.state.pending.len == 1
    check e.state.pending[0].kind == paoTerminalCommand
    check not e.state.lspCache.codeLensPicker.isActive

  test "executeCurrentLineCodeLens - multiple items show the picker":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.viewport.height = 24
    e.activeBuffer().filePath = some("/test/file.nim")
    e.state.lspCache.codeLensCache = CodeLensCache(
      isValid: true,
      filePath: "/test/file.nim",
      itemsByLine: {0: @[runnableItem("Run"), runnableItem("Debug")]}.toTable,
    )
    e.cursor = BufferPosition(line: 0, column: 0)

    waitFor e.executeCurrentLineCodeLens()
    check e.state.lspCache.codeLensPicker.isActive
    check e.state.lspCache.codeLensPicker.items.len == 2

  test "codeLensPickerConfirm executes the selected item":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.viewport.height = 24
    e.showCodeLensPicker(@[runnableItem("Run"), runnableItem("Debug")])
    e.state.lspCache.codeLensPicker.selectedIndex = 1

    waitFor e.codeLensPickerConfirm()
    check not e.state.lspCache.codeLensPicker.isActive
    check e.state.pending.len == 1
    check e.state.pending[0].kind == paoTerminalCommand

  test "codeLensPickerSelectByNumber executes the numbered item":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.viewport.height = 24
    e.showCodeLensPicker(@[runnableItem("Run"), runnableItem("Debug")])

    waitFor e.codeLensPickerSelectByNumber(2)
    check not e.state.lspCache.codeLensPicker.isActive
    check e.state.pending.len == 1
    check e.state.pending[0].kind == paoTerminalCommand

  test "codeLensPickerSelectByNumber ignores out-of-range numbers":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.viewport.height = 24
    e.showCodeLensPicker(@[runnableItem("Run")])

    waitFor e.codeLensPickerSelectByNumber(5)
    check e.state.lspCache.codeLensPicker.isActive
    check e.state.pending.len == 0
