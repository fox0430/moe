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

## CodeLens, DocumentHighlight, and SemanticTokens related procedures

import std/[options, monotimes, tables, json, times, strutils, algorithm]

import pkg/[results, chronos]

import editor_types, logger, highlight, lsp_integration
import lsp/rust_runnable

proc hasCodeLensSupport*(e: Editor): bool =
  ## Check if CodeLens is supported for the current buffer
  if not e.lsp.enabled:
    return false
  let activeBuffer = e.activeBuffer()
  return e.lsp.hasCodeLensSupport(activeBuffer)

proc processCodeLensResponse(
    e: Editor, lenses: seq[CodeLens], gen: int
): Future[void] {.async: (raises: []).} =
  ## Internal: Process code lens response from LSP
  ## `gen` is the response generation captured at spawn time. Because resolving
  ## lenses awaits the LSP, multiple invocations can be in flight at once; only the
  ## latest generation is allowed to write the cache so an older (slower) response
  ## cannot clobber a newer one.
  try:
    let activeBuffer = e.activeBuffer()
    if activeBuffer.filePath.isNone:
      return

    let filePath = activeBuffer.filePath.get

    # Convert to cached items grouped by line (Table for O(1) lookup)
    var itemsByLine: Table[int, seq[CodeLensItem]]
    for lens in lenses:
      var item = CodeLensItem(line: lens.range.start.line)

      if lens.command.isSome:
        let cmd = lens.command.get
        item.title = cmd.title
        item.command = cmd.command
        if cmd.arguments.isSome:
          for arg in cmd.arguments.get:
            item.arguments.add($arg)
      else:
        # Need to resolve
        let resolveResult = await e.lsp.requestCodeLensResolve(activeBuffer, lens)
        if resolveResult.isOk:
          let resolved = resolveResult.get
          if resolved.command.isSome:
            let cmd = resolved.command.get
            item.title = cmd.title
            item.command = cmd.command
            if cmd.arguments.isSome:
              for arg in cmd.arguments.get:
                item.arguments.add($arg)

      if item.title.len > 0:
        # Group by line number
        itemsByLine.mgetOrPut(item.line, @[]).add(item)

    # A newer response has been spawned while we were awaiting resolves; discard
    # this stale result rather than overwriting the newer cache.
    if gen != e.state.lspCache.codeLensResponseGen:
      return

    e.state.lspCache.codeLensCache = CodeLensCache(
      itemsByLine: itemsByLine,
      changeSeq: activeBuffer.changeSeq,
      filePath: filePath,
      isValid: true,
    )
    # Note: the debounce timer is advanced at request initiation in
    # `doUpdateCodeLensCache`, not here. This handler runs async and can be
    # skipped, so it must not be relied on to gate the debounce.
  except CancelledError:
    discard

proc doUpdateCodeLensCache(e: Editor) =
  ## Internal: Start an async CodeLens request (non-blocking)
  ##
  ## Anchor the debounce timer here, at request initiation. The response is
  ## handled asynchronously in `processCodeLensResponse` (via `asyncSpawn`) and
  ## may never reach the stamp at all (cancelled, stale generation, missing
  ## filePath). Stamping only on completion would let the debounce gate in
  ## `updateCodeLensCache` read a stale timestamp on the frame a response
  ## arrives and fire a fresh request on every round-trip. Stamping on
  ## initiation guarantees at most one request per `codeLensUpdateInterval`,
  ## regardless of async completion timing.
  e.state.lspCache.lastCodeLensUpdate = getMonoTime()

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  # Check if CodeLens is supported
  if not e.lsp.hasCodeLensSupport(activeBuffer):
    e.state.lspCache.codeLensCache = CodeLensCache(isValid: false)
    return

  # Start async request
  let reqResult = e.lsp.startCodeLensRequest(activeBuffer)
  if reqResult.isOk:
    e.state.lspCache.pendingCodeLensRequestId = reqResult.get
  else:
    e.state.lspCache.codeLensCache = CodeLensCache(isValid: false)

proc updateCodeLensCache*(e: Editor) =
  ## Update the CodeLens cache for the current buffer (with debouncing)
  ## Only updates if enough time has passed since last update and buffer changed
  ## Uses non-blocking async pattern to avoid freezing the UI
  if not e.lsp.enabled or not e.state.display.showCodeLens:
    return

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  let filePath = activeBuffer.filePath.get

  # Check if there's a pending request - try to get response
  if e.state.lspCache.pendingCodeLensRequestId != 0:
    let (status, resultOpt, errorOpt) =
      e.lsp.checkResponse(e.state.lspCache.pendingCodeLensRequestId)
    case status
    of lrsPending:
      # Still waiting for response, don't start a new request
      return
    of lrsSuccess:
      # Got response, process it
      e.state.lspCache.pendingCodeLensRequestId = 0
      if resultOpt.isSome:
        let lenses = parseCodeLensResponse(resultOpt.get)
        inc e.state.lspCache.codeLensResponseGen
        asyncSpawn e.processCodeLensResponse(
          lenses, e.state.lspCache.codeLensResponseGen
        )
      # Continue to check if we need to start a new request (buffer might have changed)
    of lrsError, lrsTimeout:
      # Request failed or timed out, mark cache as valid but empty to prevent retry loop
      logLspDegraded("CodeLens", status, errorOpt.get(""))
      e.state.lspCache.pendingCodeLensRequestId = 0
      e.state.lspCache.codeLensCache = CodeLensCache(
        isValid: true, filePath: filePath, changeSeq: activeBuffer.changeSeq
      )
      e.state.lspCache.lastCodeLensUpdate = getMonoTime()
      return

  # Check if cache is still valid (no changes needed)
  if e.state.lspCache.codeLensCache.isValid and
      e.state.lspCache.codeLensCache.filePath == filePath and
      e.state.lspCache.codeLensCache.changeSeq == activeBuffer.changeSeq:
    return

  # Debounce: check if enough time has passed since last update
  let now = getMonoTime()
  let elapsed = now - e.state.lspCache.lastCodeLensUpdate
  let threshold = initDuration(milliseconds = e.state.lspCache.codeLensUpdateInterval)

  if elapsed >= threshold:
    e.doUpdateCodeLensCache()

proc getCodeLensItemsForLine*(cache: var LspCacheState, line: int): seq[CodeLensItem] =
  ## Get cached CodeLens items for a specific line (O(1) lookup)
  if not cache.codeLensCache.isValid:
    return @[]

  cache.codeLensCache.itemsByLine.getOrDefault(line, @[])

proc getCodeLensItemsForCurrentLine*(e: Editor): seq[CodeLensItem] =
  ## Get cached CodeLens items for the current cursor line
  e.state.lspCache.getCodeLensItemsForLine(e.cursor.line)

proc executeCodeLensItem*(
    e: Editor, item: CodeLensItem
): Future[Result[void, string]] {.async: (raises: [CancelledError]).} =
  ## Execute a cached CodeLens item's command
  try:
    if not e.lsp.enabled:
      return err("LSP is not enabled")

    if item.command.len == 0:
      return err("CodeLens has no command")

    # rust-analyzer run/debug are client-side commands: the server expects the
    # editor (not workspace/executeCommand) to launch the build/test process.
    # Intercept them and queue a terminal command; the main loop opens it.
    if item.command == "rust-analyzer.runSingle" or
        item.command == "rust-analyzer.debugSingle":
      if item.arguments.len == 0:
        return err("Runnable command has no arguments")
      var runnable: JsonNode
      try:
        runnable = parseJson(item.arguments[0])
      except JsonParsingError:
        return err("Failed to parse runnable argument")
      let cmdResult = buildRunnableCommand(
        runnable, debug = item.command == "rust-analyzer.debugSingle"
      )
      if cmdResult.isErr:
        return err(cmdResult.error)
      e.state.pending.terminalCommand = cmdResult.get
      e.state.statusMessage = "Running: " & item.title
      return ok()

    let activeBuffer = e.activeBuffer()

    # Convert arguments back to JsonNode
    var args: seq[JsonNode] = @[]
    for argStr in item.arguments:
      try:
        args.add(parseJson(argStr))
      except JsonParsingError:
        args.add(%argStr)

    let execResult = await e.lsp.requestExecuteCommand(activeBuffer, item.command, args)
    if execResult.isErr:
      return err("Failed to execute command: " & execResult.error)

    e.state.statusMessage = "Executed: " & item.title
    return ok()
  except CancelledError as err:
    raise err
  except Exception as err:
    return err("Failed to execute CodeLens: " & err.msg)

proc invalidateCodeLensCache*(cache: var LspCacheState) =
  ## Invalidate the CodeLens cache (call when buffer changes significantly)
  cache.codeLensCache.isValid = false

# Document Highlight support
proc invalidateDocumentHighlightCache*(cache: var LspCacheState) =
  ## Invalidate the Document Highlight cache
  cache.documentHighlightCache.isValid = false
  cache.documentHighlightCache.itemsByLine.clear()

proc processDocumentHighlightResponse(e: Editor, highlights: seq[DocumentHighlight]) =
  ## Internal: Process document highlights from LSP response
  let activeBuffer = e.activeBuffer()

  # Convert LSP DocumentHighlight to our cached format
  # Handle multi-line highlights by creating an item for each line
  # Group by line for O(1) lookup during rendering
  # Note: LSP character positions are UTF-16, convert to UTF-8 byte offsets
  var itemsByLine: Table[int, seq[DocumentHighlightItem]]
  for highlight in highlights:
    let kind =
      if highlight.kind.isSome:
        highlight.kind.get.int
      else:
        1 # Default to Text

    let startLine = highlight.range.start.line
    let endLine = highlight.range.`end`.line

    if startLine == endLine:
      # Single line highlight - convert UTF-16 to rune index. The renderer
      # compares these against BufferPosition.column (a rune index), so byte
      # offsets would misplace the highlight on multibyte lines.
      let lineText =
        if startLine >= 0 and startLine < activeBuffer.len:
          activeBuffer.getLine(startLine)
        else:
          ""
      let startCol = utf16ToRuneIndex(lineText, highlight.range.start.character)
      let endCol = utf16ToRuneIndex(lineText, highlight.range.`end`.character)
      let item = DocumentHighlightItem(
        line: startLine, startColumn: startCol, endColumn: endCol, kind: kind
      )
      if startLine notin itemsByLine:
        itemsByLine[startLine] = @[]
      itemsByLine[startLine].add(item)
    else:
      # Multi-line highlight: create an item for each line
      for line in startLine .. endLine:
        let lineText =
          if line >= 0 and line < activeBuffer.len:
            activeBuffer.getLine(line)
          else:
            ""
        let startCol =
          if line == startLine:
            utf16ToRuneIndex(lineText, highlight.range.start.character)
          else:
            0
        # For end column, use a large value for middle lines
        # (will be clamped during rendering)
        let endCol =
          if line == endLine:
            utf16ToRuneIndex(lineText, highlight.range.`end`.character)
          else:
            int.high
        let item = DocumentHighlightItem(
          line: line, startColumn: startCol, endColumn: endCol, kind: kind
        )
        if line notin itemsByLine:
          itemsByLine[line] = @[]
        itemsByLine[line].add(item)

  e.state.lspCache.documentHighlightCache = DocumentHighlightCache(
    itemsByLine: itemsByLine,
    cursorLine: e.cursor.line,
    cursorColumn: e.cursor.column,
    changeSeq: activeBuffer.changeSeq,
    isValid: true,
  )
  e.state.lspCache.lastDocumentHighlightUpdate = getMonoTime()

proc doUpdateDocumentHighlightCache(e: Editor) =
  ## Internal: Start an async Document Highlight request (non-blocking)
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    e.state.lspCache.invalidateDocumentHighlightCache()
    return

  # Start async request
  let reqResult =
    e.lsp.startDocumentHighlightRequest(activeBuffer, e.cursor.line, e.cursor.column)
  if reqResult.isOk:
    e.state.lspCache.pendingDocumentHighlightRequestId = reqResult.get
  else:
    e.state.lspCache.invalidateDocumentHighlightCache()

proc updateDocumentHighlightCache*(e: Editor) =
  ## Update the Document Highlight cache (with debouncing)
  ## Called during render to update highlights when cursor moves
  ## Only updates in Normal/Visual modes - cleared in Insert/Replace modes
  ## Uses non-blocking async pattern to avoid freezing the UI
  if not e.lsp.enabled or not e.state.display.showDocumentHighlight:
    return

  # In Insert/Replace modes, clear highlights to avoid distraction
  if e.state.mode in {EditorMode.Insert, EditorMode.Replace}:
    if e.state.lspCache.documentHighlightCache.isValid:
      e.state.lspCache.invalidateDocumentHighlightCache()
    if e.state.lspCache.pendingDocumentHighlightRequestId != 0:
      e.lsp.cancelRequest(e.state.lspCache.pendingDocumentHighlightRequestId)
      e.state.lspCache.pendingDocumentHighlightRequestId = 0
    return

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  # Check if there's a pending request - try to get response
  if e.state.lspCache.pendingDocumentHighlightRequestId != 0:
    let (status, resultOpt, errorOpt) =
      e.lsp.checkResponse(e.state.lspCache.pendingDocumentHighlightRequestId)
    case status
    of lrsPending:
      # Still waiting for response, don't start a new request
      return
    of lrsSuccess:
      # Got response, process it
      e.state.lspCache.pendingDocumentHighlightRequestId = 0
      if resultOpt.isSome:
        let highlights = parseDocumentHighlightResponse(resultOpt.get)
        e.processDocumentHighlightResponse(highlights)
      # Continue to check if we need to start a new request (cursor might have moved)
    of lrsError, lrsTimeout:
      # Request failed or timed out, clear and continue
      logLspDegraded("Document highlight", status, errorOpt.get(""))
      e.state.lspCache.pendingDocumentHighlightRequestId = 0

  # Check if cursor position changed
  # (same line and column means no need to update)
  if e.state.lspCache.documentHighlightCache.isValid and
      e.state.lspCache.documentHighlightCache.cursorLine == e.cursor.line and
      e.state.lspCache.documentHighlightCache.cursorColumn == e.cursor.column and
      e.state.lspCache.documentHighlightCache.changeSeq == activeBuffer.changeSeq:
    return

  # Debounce - only update if enough time has passed since last update
  let now = getMonoTime()
  let elapsed = now - e.state.lspCache.lastDocumentHighlightUpdate
  let threshold =
    initDuration(milliseconds = e.state.lspCache.documentHighlightUpdateInterval)
  if elapsed >= threshold:
    e.doUpdateDocumentHighlightCache()

# Semantic Tokens (LSP-based syntax highlighting)

proc viewportRequestRange(e: Editor): (int, int) =
  ## Visible line range plus a small margin, shared by viewport-scoped LSP
  ## requests (semantic tokens, inlay hints). Clamped to the buffer end so the
  ## request range and the cache-coverage check stay in sync.
  let lastLine = e.activeBuffer().len - 1
  let topLine = max(0, e.viewport.topLine - 10)
  let bottomLine = min(e.viewport.topLine + e.viewport.height + 10, lastLine)
  (topLine, bottomLine)

proc invalidateSemanticTokensCache*(lsp: LspIntegration, cache: var LspCacheState) =
  ## Invalidate the semantic tokens cache, forcing re-request on next update
  cache.semanticTokensCache = SemanticTokensCache(isValid: false)
  if cache.pendingSemanticTokensRequestId != 0:
    lsp.cancelRequest(cache.pendingSemanticTokensRequestId)
    cache.pendingSemanticTokensRequestId = 0

proc processSemanticTokensResponse(e: Editor, resp: JsonNode) =
  ## Process semantic tokens response and apply to buffer's highlight
  let activeBuffer = e.activeBuffer()
  if activeBuffer.isNil or activeBuffer.highlight.isNil:
    return

  let legendOpt = e.lsp.getSemanticTokensLegend(activeBuffer)
  if legendOpt.isNone:
    logDebug("editor", "Semantic tokens: no legend available")
    return

  # Parse and apply semantic tokens
  let tokens = parseSemanticTokens(resp)
  applySemanticTokens(activeBuffer.highlight, tokens, legendOpt.get)

  # Mark cache as valid
  e.state.lspCache.semanticTokensCache = SemanticTokensCache(
    changeSeq: activeBuffer.changeSeq,
    filePath: activeBuffer.filePath.get(""),
    isValid: true,
    topLine: e.viewport.topLine,
    bottomLine: e.viewport.topLine + e.viewport.height,
  )
  e.state.lspCache.lastSemanticTokensUpdate = getMonoTime()

proc doUpdateSemanticTokensCache(e: Editor) =
  ## Internal: Start an async semantic tokens request (non-blocking)
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    invalidateSemanticTokensCache(e.lsp, e.state.lspCache)
    return

  # Request semantic tokens for visible range (with margin)
  let (topLine, bottomLine) = e.viewportRequestRange()

  # Start async request
  let reqResult = e.lsp.startSemanticTokensRequest(activeBuffer, topLine, bottomLine)
  if reqResult.isOk:
    e.state.lspCache.pendingSemanticTokensRequestId = reqResult.get
  else:
    logDebug("editor", "Semantic tokens request failed: " & reqResult.error)
    invalidateSemanticTokensCache(e.lsp, e.state.lspCache)

proc updateSemanticTokensCache*(e: Editor) =
  ## Update the semantic tokens cache (with debouncing)
  ## Called during render to update LSP-based syntax highlighting
  ## Uses non-blocking async pattern to avoid freezing the UI
  if not e.lsp.enabled:
    return

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  let path = activeBuffer.filePath.get
  let langIdOpt = e.lsp.service.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return

  # Check if semantic tokens is supported
  if not e.lsp.service.hasSemanticTokensSupport(langIdOpt.get):
    return

  # Check if there's a pending request - try to get response
  if e.state.lspCache.pendingSemanticTokensRequestId != 0:
    let (status, resultOpt, errorOpt) =
      e.lsp.checkResponse(e.state.lspCache.pendingSemanticTokensRequestId)
    case status
    of lrsPending:
      # Still waiting for response, don't start a new request
      return
    of lrsSuccess:
      # Got response, process it
      e.state.lspCache.pendingSemanticTokensRequestId = 0
      if resultOpt.isSome and resultOpt.get.kind != JNull:
        e.processSemanticTokensResponse(resultOpt.get)
      # Continue to check if we need to start a new request
    of lrsError, lrsTimeout:
      # Request failed or timed out, clear and continue
      logLspDegraded("Semantic tokens", status, errorOpt.get(""))
      e.state.lspCache.pendingSemanticTokensRequestId = 0

  # Check if cache is still valid
  let cache = e.state.lspCache.semanticTokensCache
  if cache.isValid and cache.changeSeq == activeBuffer.changeSeq and
      cache.filePath == path and cache.topLine <= e.viewport.topLine and
      cache.bottomLine >= e.viewport.topLine + e.viewport.height:
    # Cache is valid and covers current viewport
    return

  # Debounce - only update if enough time has passed since last update
  let now = getMonoTime()
  let elapsed = now - e.state.lspCache.lastSemanticTokensUpdate
  let threshold =
    initDuration(milliseconds = e.state.lspCache.semanticTokensUpdateInterval)
  if elapsed >= threshold:
    e.doUpdateSemanticTokensCache()

# Inlay Hints
#
# Follows the SemanticTokens pattern: viewport-range request + debounce +
# viewport/changeSeq/filePath cache invalidation. Unlike CodeLens there is no
# resolve round-trip and no async spawn, so the cache write is synchronous and a
# response-generation counter is unnecessary.

proc hasInlayHintSupport*(e: Editor): bool =
  ## Check if inlay hints are supported for the current buffer
  if not e.lsp.enabled:
    return false
  e.lsp.hasInlayHintSupport(e.activeBuffer())

proc invalidateInlayHintCache*(lsp: LspIntegration, cache: var LspCacheState) =
  ## Invalidate the inlay hint cache and cancel any in-flight request
  cache.inlayHintCache = InlayHintCache(isValid: false)
  if cache.pendingInlayHintRequestId != 0:
    lsp.cancelRequest(cache.pendingInlayHintRequestId)
    cache.pendingInlayHintRequestId = 0

proc processInlayHintResponse(e: Editor, hints: seq[InlayHint]) =
  ## Internal: convert an inlay hint response into the cached, per-line format.
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  # Group by line for O(1) lookup during rendering.
  # Note: LSP character positions are UTF-16; convert to rune index because the
  # renderer compares against rune-based buffer columns.
  var itemsByLine: Table[int, seq[InlayHintItem]]
  for hint in hints:
    let line = hint.position.line
    if line < 0 or line >= activeBuffer.len:
      continue
    let lineText = activeBuffer.getLine(line)
    let col = utf16ToRuneIndex(lineText, hint.position.character)
    let label = getInlayHintLabel(hint)
    if label.len == 0:
      continue
    let item = InlayHintItem(
      line: line,
      column: col,
      label: label,
      kind: (if hint.kind.isSome: hint.kind.get.int else: 0),
      paddingLeft: hint.paddingLeft.get(false),
      paddingRight: hint.paddingRight.get(false),
    )
    itemsByLine.mgetOrPut(line, @[]).add(item)

  # LSP does not guarantee the order of InlayHint[], but end-of-line rendering
  # concatenates items left-to-right, so sort each line by column. sort is a
  # stable merge sort, so the server order is kept among hints sharing a column.
  for items in itemsByLine.mvalues:
    items.sort(
      proc(a, b: InlayHintItem): int =
        cmp(a.column, b.column)
    )

  e.state.lspCache.inlayHintCache = InlayHintCache(
    itemsByLine: itemsByLine,
    changeSeq: activeBuffer.changeSeq,
    filePath: activeBuffer.filePath.get,
    topLine: e.viewport.topLine,
    bottomLine: e.viewport.topLine + e.viewport.height,
    isValid: true,
  )
  e.state.lspCache.lastInlayHintUpdate = getMonoTime()

proc doUpdateInlayHintCache(e: Editor) =
  ## Internal: Start an async inlay hint request for the visible range (non-blocking)
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    invalidateInlayHintCache(e.lsp, e.state.lspCache)
    return

  # Request the visible range with a small margin (matches semantic tokens).
  let (topLine, bottomLine) = e.viewportRequestRange()

  let reqResult = e.lsp.startInlayHintRequest(activeBuffer, topLine, bottomLine)
  if reqResult.isOk:
    e.state.lspCache.pendingInlayHintRequestId = reqResult.get
    e.state.lspCache.pendingInlayHintBufferId = activeBuffer.id
  else:
    invalidateInlayHintCache(e.lsp, e.state.lspCache)

proc updateInlayHintCache*(e: Editor) =
  ## Update the inlay hint cache (with debouncing)
  ## Called from tickLsp. Uses non-blocking async pattern to avoid freezing the UI.
  if not e.lsp.enabled or not e.state.display.showInlayHint:
    return

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  let path = activeBuffer.filePath.get
  let langIdOpt = e.lsp.service.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return

  if not e.lsp.service.hasInlayHintSupport(langIdOpt.get):
    return

  # Check if there's a pending request - try to get response
  if e.state.lspCache.pendingInlayHintRequestId != 0:
    let (status, resultOpt, errorOpt) =
      e.lsp.checkResponse(e.state.lspCache.pendingInlayHintRequestId)
    case status
    of lrsPending:
      return
    of lrsSuccess:
      e.state.lspCache.pendingInlayHintRequestId = 0
      # Discard the response if the active buffer changed while in flight:
      # checkResponse routes by request id only, so without this guard file A's
      # hints would be stamped onto (and self-validate against) file B's cache
      # and render inside B. Mirrors the pendingHoverBufferId guard.
      if e.activeBuffer().id != e.state.lspCache.pendingInlayHintBufferId:
        return
      if resultOpt.isSome and resultOpt.get.kind != JNull:
        e.processInlayHintResponse(parseInlayHintResponse(resultOpt.get))
    of lrsError, lrsTimeout:
      logLspDegraded("Inlay hint", status, errorOpt.get(""))
      e.state.lspCache.pendingInlayHintRequestId = 0

  # Check if cache is still valid and covers the current viewport
  let cache = e.state.lspCache.inlayHintCache
  if cache.isValid and cache.changeSeq == activeBuffer.changeSeq and
      cache.filePath == path and cache.topLine <= e.viewport.topLine and
      cache.bottomLine >= e.viewport.topLine + e.viewport.height:
    return

  # Debounce - only update if enough time has passed since last update
  let now = getMonoTime()
  let elapsed = now - e.state.lspCache.lastInlayHintUpdate
  let threshold = initDuration(milliseconds = e.state.lspCache.inlayHintUpdateInterval)
  if elapsed >= threshold:
    e.doUpdateInlayHintCache()

proc getInlayHintsForLine*(cache: var LspCacheState, line: int): seq[InlayHintItem] =
  ## Get cached inlay hints for a specific line (O(1) lookup)
  if not cache.inlayHintCache.isValid:
    return @[]
  cache.inlayHintCache.itemsByLine.getOrDefault(line, @[])

proc inlayHintVirtualTextProvider*(e: Editor): VirtualTextProvider =
  ## Adapter: expose the cached inlay hints as end-of-line virtual text. The
  ## returned closure reads the cache lazily at render time via
  ## getInlayHintsForLine (which yields nothing when the cache is invalid).
  ## Feature enablement is gated once, in buildVirtualTextProviders.
  result = proc(line: int): seq[VirtualText] {.closure, gcsafe, raises: [].} =
    for item in e.state.lspCache.getInlayHintsForLine(line):
      var text = " "
      if item.paddingLeft:
        text.add " "
      text.add item.label
      if item.paddingRight:
        text.add " "
      result.add VirtualText(
        line: line,
        column: item.column,
        placement: vtpEndOfLine,
        priority: 0,
        chunks: @[VirtualTextChunk(text: text, color: EditorColorPairIndex.inlayHint)],
      )

proc buildVirtualTextProviders*(e: Editor): seq[VirtualTextProvider] =
  ## Assemble the virtual text providers for the currently enabled features.
  ## New features (inline diagnostics, git blame, ...) push their own provider
  ## here; the renderer stays feature-agnostic.
  if e.state.display.showInlayHint:
    # The cache is keyed by file but read per line number, so right after a
    # buffer switch (before the highlightChanged invalidation in prepareFrame
    # runs) it can still hold the previous file's hints. Gate on the owning
    # file once per frame instead of per line.
    let cache = e.state.lspCache.inlayHintCache
    if cache.isValid and some(cache.filePath) == e.activeBuffer().filePath:
      result.add e.inlayHintVirtualTextProvider()

proc getCodeLensDisplayText*(e: Editor, line: int): string =
  ## Get display text for CodeLens on a specific line
  ## Returns empty string if no CodeLens on this line
  let items = e.state.lspCache.getCodeLensItemsForLine(line)
  if items.len == 0:
    return ""

  var texts: seq[string] = @[]
  for item in items:
    if item.title.len > 0:
      texts.add(item.title)

  return texts.join(" | ")

proc showCodeLensPicker*(e: Editor, items: seq[CodeLensItem]) =
  ## Show the CodeLens picker with the given items
  # Calculate max visible items based on viewport height
  # Reserve space for borders (2) and some margin (4)
  let maxVisible = max(1, e.viewport.height - 6)
  e.state.lspCache.codeLensPicker = CodeLensPicker(
    items: items,
    selectedIndex: 0,
    scrollOffset: 0,
    maxVisibleItems: min(items.len, maxVisible),
    isActive: true,
  )

proc hideCodeLensPicker*(cache: var LspCacheState) =
  ## Hide the CodeLens picker
  cache.codeLensPicker.isActive = false
  cache.codeLensPicker.items = @[]

proc codeLensPickerSelectNext*(e: Editor) =
  ## Move selection down in CodeLens picker
  if not e.state.lspCache.codeLensPicker.isActive:
    return
  if e.state.lspCache.codeLensPicker.selectedIndex <
      e.state.lspCache.codeLensPicker.items.len - 1:
    e.state.lspCache.codeLensPicker.selectedIndex += 1
    # Adjust scroll offset if selection goes below visible area
    let maxVisible = e.state.lspCache.codeLensPicker.maxVisibleItems
    if e.state.lspCache.codeLensPicker.selectedIndex >=
        e.state.lspCache.codeLensPicker.scrollOffset + maxVisible:
      e.state.lspCache.codeLensPicker.scrollOffset =
        e.state.lspCache.codeLensPicker.selectedIndex - maxVisible + 1

proc codeLensPickerSelectPrev*(e: Editor) =
  ## Move selection up in CodeLens picker
  if not e.state.lspCache.codeLensPicker.isActive:
    return
  if e.state.lspCache.codeLensPicker.selectedIndex > 0:
    e.state.lspCache.codeLensPicker.selectedIndex -= 1
    # Adjust scroll offset if selection goes above visible area
    if e.state.lspCache.codeLensPicker.selectedIndex <
        e.state.lspCache.codeLensPicker.scrollOffset:
      e.state.lspCache.codeLensPicker.scrollOffset =
        e.state.lspCache.codeLensPicker.selectedIndex

proc codeLensPickerSelectByNumber*(
    e: Editor, num: int
): Future[void] {.async: (raises: []).} =
  ## Select and execute CodeLens item by number (1-9)
  try:
    if not e.state.lspCache.codeLensPicker.isActive or
        e.state.lspCache.codeLensPicker.items.len == 0:
      return

    let index = num - 1 # Convert 1-based to 0-based index
    if index < 0 or index >= e.state.lspCache.codeLensPicker.items.len:
      return

    let item = e.state.lspCache.codeLensPicker.items[index]
    e.state.lspCache.hideCodeLensPicker()

    let execResult = await e.executeCodeLensItem(item)
    if execResult.isErr:
      e.state.statusMessage = execResult.error
  except CancelledError:
    discard

proc codeLensPickerConfirm*(e: Editor): Future[void] {.async: (raises: []).} =
  ## Confirm selection and execute the selected CodeLens item
  try:
    if not e.state.lspCache.codeLensPicker.isActive or
        e.state.lspCache.codeLensPicker.items.len == 0:
      return

    let item = e.state.lspCache.codeLensPicker.items[
      e.state.lspCache.codeLensPicker.selectedIndex
    ]
    e.state.lspCache.hideCodeLensPicker()

    let execResult = await e.executeCodeLensItem(item)
    if execResult.isErr:
      e.state.statusMessage = execResult.error
  except CancelledError:
    discard

proc executeCurrentLineCodeLens*(e: Editor): Future[void] {.async: (raises: []).} =
  ## Execute CodeLens on current line
  ## If multiple CodeLens items exist, show picker to choose
  try:
    if not e.lsp.enabled:
      e.state.statusMessage = "LSP is not enabled"
      return

    # Force update cache (bypass debouncing for explicit user action)
    if e.state.display.showCodeLens:
      e.doUpdateCodeLensCache()

    if not e.state.lspCache.codeLensCache.isValid:
      e.state.statusMessage = "No CodeLens available"
      return

    # Get CodeLens items for current line
    let items = e.getCodeLensItemsForCurrentLine()
    if items.len == 0:
      e.state.statusMessage = "No CodeLens on current line"
      return

    # If only one item, execute directly
    if items.len == 1:
      let execResult = await e.executeCodeLensItem(items[0])
      if execResult.isErr:
        e.state.statusMessage = execResult.error
      return

    # Multiple items - show picker
    e.showCodeLensPicker(items)
    e.state.statusMessage =
      "Select CodeLens (1-9: select, j/k: navigate, Enter: confirm, Esc: cancel)"
  except CancelledError:
    discard
  except Exception as err:
    e.state.statusMessage = "CodeLens error: " & err.msg
