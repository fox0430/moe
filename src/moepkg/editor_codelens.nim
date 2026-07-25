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

import std/[options, monotimes, tables, json, times, algorithm]

import pkg/[results, chronos]

import
  types/editor_types,
  logger,
  highlight,
  lsp_integration,
  unicode_utils,
  lsp_request_context
import lsp/rust_runnable

proc hasCodeLensSupport*(e: Editor): bool =
  ## Check if CodeLens is supported for the current buffer
  if not e.lsp.enabled:
    return false
  let activeBuffer = e.activeBuffer()
  return e.lsp.hasCodeLensSupport(activeBuffer)

proc processCodeLensResponse(
    e: Editor, lenses: seq[CodeLens], gen: int, reqContentVersion: int
): Future[void] {.async: (raises: []).} =
  ## Internal: Process code lens response from LSP
  ## `gen` is the response generation captured at spawn time. Because resolving
  ## lenses awaits the LSP, multiple invocations can be in flight at once; only the
  ## latest generation is allowed to write the cache so an older (slower) response
  ## cannot clobber a newer one.
  ## `reqContentVersion` is the buffer contentVersion at spawn time; if the
  ## buffer advanced in flight the response is stale and must be dropped.
  try:
    let activeBuffer = e.activeBuffer()
    if activeBuffer.filePath.isNone:
      return

    let filePath = activeBuffer.filePath.get

    # Stale-response guard: reject if the buffer content advanced between spawn
    # and handler execution (an edit, undo, reload, etc.).
    if reqContentVersion != activeBuffer.contentVersion:
      return

    # Resolve support is queried lazily and memoized for this response: servers
    # like rust-analyzer inline every command, so the (Table + JSON) capability
    # lookup is skipped entirely there. Not cached across responses on purpose —
    # capabilities can change via dynamic (un)registration, and every other
    # has*Support check is likewise recomputed each cycle.
    var resolveSupported = none(bool)

    # Convert to cached items grouped by line (Table for O(1) lookup)
    var itemsByLine: Table[int, seq[CodeLensItem]]
    for lens in lenses:
      # LSP character positions are UTF-16; convert to a rune index because the
      # end-of-line renderer orders items by rune-based column. Mirrors
      # processInlayHintResponse.
      let line = lens.range.start.line
      let lineText =
        if line >= 0 and line < activeBuffer.len:
          activeBuffer.getLine(line)
        else:
          ""
      let col = utf16ToRuneIndex(lineText, lens.range.start.character)
      var item = CodeLensItem(line: line, column: col)

      if lens.command.isSome:
        let cmd = lens.command.get
        item.title = cmd.title
        item.command = cmd.command
        if cmd.arguments.isSome:
          for arg in cmd.arguments.get:
            item.arguments.add($arg)
      else:
        # Command not inlined: resolve it, but only when the server advertises
        # codeLens/resolve. Without this gate a server that emits command-less
        # lenses but does not implement resolve would get a rejected request per
        # lens. A lens left command-less here stays title-less and is dropped by
        # the `item.title.len > 0` filter below.
        if resolveSupported.isNone:
          # The capability lookup reads a Table and can raise KeyError; this proc
          # is raises:[], so guard it (treat a lookup failure as "no support").
          try:
            resolveSupported = some(e.lsp.hasCodeLensResolveSupport(activeBuffer))
          except KeyError:
            resolveSupported = some(false)
        if resolveSupported.get:
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

    # End-of-line rendering concatenates items left-to-right, so sort each line
    # by column. sort is a stable merge sort, so the server order is kept among
    # lenses sharing a column. Mirrors processInlayHintResponse.
    for items in itemsByLine.mvalues:
      items.sort(
        proc(a, b: CodeLensItem): int =
          cmp(a.column, b.column)
      )

    # A newer response has landed while we were awaiting resolves; discard
    # this stale result rather than overwriting the newer cache. Only
    # response-processing bumps featureGeneration — request-start no longer
    # does, so an in-tick follow-up request cannot invalidate us.
    if gen != e.state.lspCache.featureGeneration[lrfCodeLens]:
      return

    e.state.lspCache.codeLensPoll.rejectStreak = 0
    e.state.lspCache.codeLensCache = CodeLensCache(
      itemsByLine: itemsByLine,
      contentVersion: activeBuffer.contentVersion,
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
  ## initiation guarantees at most one request per `codeLensPoll.interval`,
  ## regardless of async completion timing.
  e.state.lspCache.codeLensPoll.lastUpdate = getMonoTime()

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  # Check if CodeLens is supported
  if not e.lsp.hasCodeLensSupport(activeBuffer):
    e.state.lspCache.codeLensCache = CodeLensCache(isValid: false)
    return

  let ctxRes = e.startContextualRequest(
    lrfCodeLens,
    proc(): Result[int, string] =
      e.lsp.startCodeLensRequest(activeBuffer),
    # Background cache: it feeds the buffer painted under an overlay, so an
    # open overlay must not drop the response.
    blockedByOverlay = false,
  )
  if ctxRes.isErr:
    e.state.lspCache.codeLensCache = CodeLensCache(isValid: false)

proc updateCodeLensCache*(e: Editor) =
  ## Update the CodeLens cache for the current buffer (with debouncing)
  ## Only updates if enough time has passed since last update and buffer changed
  ## Uses non-blocking async pattern to avoid freezing the UI
  if not e.lsp.enabled or not e.showCodeLens:
    return

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  let filePath = activeBuffer.filePath.get
  var poll = addr e.state.lspCache.codeLensPoll

  # The guard drops cross-buffer / stale-edit responses before the async
  # resolver is spawned — otherwise lenses computed against buffer A would get
  # stamped into buffer B's cache after a mid-flight `:b B`.
  e.pollDebouncedLspResponse(lrfCodeLens, poll, "CodeLens"):
    if resultOpt.isSome:
      let lenses = parseCodeLensResponse(resultOpt.get)
      # Bump generation so a slower async spawn is dropped if superseded.
      e.state.lspCache.featureGeneration[lrfCodeLens].inc
      let gen = e.state.lspCache.featureGeneration[lrfCodeLens]
      asyncSpawn e.processCodeLensResponse(lenses, gen, ctx.contentVersion)
    # Fall through to check whether a new request is needed (the buffer may
    # have changed while this one was in flight).
  do:
    # Mark the cache valid but empty to prevent a retry loop.
    e.state.lspCache.codeLensCache = CodeLensCache(
      isValid: true, filePath: filePath, contentVersion: activeBuffer.contentVersion
    )
    return

  # Check if cache is still valid (no changes needed)
  if e.state.lspCache.codeLensCache.isValid and
      e.state.lspCache.codeLensCache.filePath == filePath and
      e.state.lspCache.codeLensCache.contentVersion == activeBuffer.contentVersion:
    return

  # Debounce with exponential backoff on the reject streak.
  let now = getMonoTime()
  let elapsed = now - poll.lastUpdate
  if elapsed >= poll[].debounceThreshold():
    e.doUpdateCodeLensCache()

proc getCodeLensItemsForLine*(cache: var LspCacheState, line: int): seq[CodeLensItem] =
  ## Get cached CodeLens items for a specific line (O(1) lookup)
  if not cache.codeLensCache.isValid:
    return @[]

  cache.codeLensCache.itemsByLine.getOrDefault(line, @[])

proc getCodeLensItemsForCurrentLine*(e: Editor): seq[CodeLensItem] =
  ## Get cached CodeLens items for the current cursor line.
  ## Returns @[] when the cache belongs to a different buffer (post buffer-switch
  ## staleness): the cache is line-keyed, so without this gate the previous
  ## file's lenses could surface on the new buffer. Mirrors the filePath gate in
  ## buildVirtualTextProviders.
  let cache = e.state.lspCache.codeLensCache
  if not cache.isValid or some(cache.filePath) != e.activeBuffer().filePath:
    return @[]
  e.state.lspCache.getCodeLensItemsForLine(e.cursor.line)

proc codeLensVirtualTextProvider*(e: Editor): VirtualTextProvider =
  ## Adapter: expose the cached code lenses as end-of-line virtual text. The
  ## returned closure reads the cache lazily at render time via
  ## getCodeLensItemsForLine (which yields nothing when the cache is invalid).
  ## Feature enablement and buffer ownership are gated once, in
  ## buildVirtualTextProviders. Mirrors inlayHintVirtualTextProvider, but uses a
  ## higher priority so lenses render to the right of inlay hints.
  result = proc(line: int): seq[VirtualText] {.closure, gcsafe, raises: [].} =
    for item in e.state.lspCache.getCodeLensItemsForLine(line):
      if item.title.len == 0:
        continue
      result.add VirtualText(
        line: line,
        column: item.column,
        placement: vtpEndOfLine,
        priority: 10,
        chunks: @[
          VirtualTextChunk(text: " " & item.title, color: EditorColorPairIndex.codeLens)
        ],
      )

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
      e.state.pending.add PendingAsyncOp(
        kind: paoTerminalCommand, command: cmdResult.get
      )
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

proc invalidateCodeLensCache*(lsp: LspIntegration, cache: var LspCacheState) =
  ## Invalidate the CodeLens cache (call when buffer changes significantly).
  ## Also cancels any in-flight request so a late response cannot revive the
  ## cache after the invalidation.
  cache.codeLensCache.isValid = false
  cancelPendingRequest(lsp, cache, lrfCodeLens)

# Document Highlight support
proc invalidateDocumentHighlightCache*(lsp: LspIntegration, cache: var LspCacheState) =
  ## Invalidate the Document Highlight cache and cancel any in-flight request.
  cache.documentHighlightCache.isValid = false
  cache.documentHighlightCache.itemsByLine.clear()
  cancelPendingRequest(lsp, cache, lrfDocumentHighlight)

proc processDocumentHighlightResponse(e: Editor, highlights: seq[DocumentHighlight]) =
  ## Internal: Process document highlights from LSP response.
  ## Updates the debounce timer (including on reject) so a persistently
  ## failing server does not busy-loop on every render frame.
  e.state.lspCache.documentHighlightPoll.lastUpdate = getMonoTime()

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
    contentVersion: activeBuffer.contentVersion,
    isValid: true,
  )
  e.state.lspCache.documentHighlightPoll.rejectStreak = 0

const DocumentHighlightValidModes* = {EditorMode.Normal, EditorMode.Visual}

proc doUpdateDocumentHighlightCache(e: Editor) =
  ## Internal: Start an async Document Highlight request (non-blocking)
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    invalidateDocumentHighlightCache(e.lsp, e.state.lspCache)
    return

  if not e.lsp.hasDocumentHighlightSupport(activeBuffer):
    # Skip servers that do not advertise documentHighlight support; otherwise we
    # would fire a request every debounce interval that the server can only reject
    # (e.g. nimlangserver, which does not implement textDocument/documentHighlight).
    invalidateDocumentHighlightCache(e.lsp, e.state.lspCache)
    return

  let cursorLine = e.cursor.line
  let cursorCol = e.cursor.column
  let ctxRes = e.startContextualRequest(
    lrfDocumentHighlight,
    proc(): Result[int, string] =
      e.lsp.startDocumentHighlightRequest(activeBuffer, cursorLine, cursorCol),
    validModes = DocumentHighlightValidModes,
    blockedByOverlay = false,
  )
  if ctxRes.isErr:
    invalidateDocumentHighlightCache(e.lsp, e.state.lspCache)

proc updateDocumentHighlightCache*(e: Editor) =
  ## Update the Document Highlight cache (with debouncing)
  ## Called during render to update highlights when cursor moves
  ## Only updates in Normal/Visual modes - cleared in Insert/Replace modes
  ## Uses non-blocking async pattern to avoid freezing the UI
  if not e.lsp.enabled or not e.showDocumentHighlight:
    return

  # In Insert/Replace modes, clear highlights to avoid distraction.
  if e.state.mode in {EditorMode.Insert, EditorMode.Replace}:
    if e.state.lspCache.documentHighlightCache.isValid or
        e.state.lspCache.pending.hasKey(lrfDocumentHighlight):
      invalidateDocumentHighlightCache(e.lsp, e.state.lspCache)
    return

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  var poll = addr e.state.lspCache.documentHighlightPoll

  e.pollDebouncedLspResponse(lrfDocumentHighlight, poll, "Document highlight"):
    if resultOpt.isSome:
      let highlights = parseDocumentHighlightResponse(resultOpt.get)
      e.processDocumentHighlightResponse(highlights)
    # Fall through to check whether a new request is needed (the cursor may
    # have moved while this one was in flight).
  do:
    discard # Failure only advances the backoff; the cache stays as it was

  # Check if cursor position changed
  # (same line and column means no need to update)
  if e.state.lspCache.documentHighlightCache.isValid and
      e.state.lspCache.documentHighlightCache.cursorLine == e.cursor.line and
      e.state.lspCache.documentHighlightCache.cursorColumn == e.cursor.column and
      e.state.lspCache.documentHighlightCache.contentVersion ==
      activeBuffer.contentVersion:
    return

  # Debounce with exponential backoff on the reject streak.
  let now = getMonoTime()
  let elapsed = now - poll.lastUpdate
  if elapsed >= poll[].debounceThreshold():
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

proc resetPendingSemanticTokens(cache: var LspCacheState) =
  ## Wipe the semantic-tokens extras (legend/viewport/range) to sentinels.
  ## The pending ctx itself is dropped by the caller.
  cache.semanticTokensPendingExtras = PendingSemanticTokensRequest(
    rangeFirst: -1,
    rangeLast: -1,
    legend: SemanticTokensLegend(tokenTypes: @[], tokenModifiers: @[]),
    viewportTopLine: -1,
    viewportBottomLine: -1,
  )

proc invalidateSemanticTokensCache*(lsp: LspIntegration, cache: var LspCacheState) =
  ## Invalidate the semantic tokens cache, forcing re-request on next update
  cache.semanticTokensCache = SemanticTokensCache(isValid: false)
  cancelPendingRequest(lsp, cache, lrfSemanticTokens)
  resetPendingSemanticTokens(cache)
  # Explicit invalidation (buffer switch, register-capability etc.) is a fresh
  # start; drop the backoff so the next request fires at the normal cadence.
  cache.semanticTokensPoll.rejectStreak = 0

proc processSemanticTokensResponse(e: Editor, resp: JsonNode, ctx: LspRequestContext) =
  ## Build the semantic overlay from a `textDocument/semanticTokens` response
  ## and swap it into the active buffer's Highlight. `ctx` is the request-time
  ## snapshot popped from `lspCache.pending[lrfSemanticTokens]`.

  # Every conclusion bumps `lastUpdate` so a persistent reject (including the
  # transient "no legend" case) is throttled by the debounce interval rather
  # than firing per render frame. Bumped BEFORE the nil-guard so a transient
  # nil highlight cannot busy-loop the LSP request.
  e.state.lspCache.semanticTokensPoll.lastUpdate = getMonoTime()

  let activeBuffer = e.activeBuffer()
  if activeBuffer.isNil or activeBuffer.highlight.isNil:
    return

  let poll = addr e.state.lspCache.semanticTokensPoll
  let extras = addr e.state.lspCache.semanticTokensPendingExtras

  if classifyResponse(e, ctx) != lrsFresh:
    return
  if ctx.path.len == 0 or activeBuffer.filePath.get("") != ctx.path:
    return

  let currentChangeSeq = activeBuffer.changeSeq
  let requestContentVersion = ctx.contentVersion

  let colorTabOpt = e.lsp.getSemanticTypeColorTable(activeBuffer)
  if colorTabOpt.isNone:
    logDebug("editor", "Semantic tokens: no legend available")
    return

  # A dynamic client/registerCapability between request send and now could
  # have swapped the server's legend. The response's tokenType indices refer
  # to the request-time legend; decoding them against a new legend would
  # paint every token with the wrong colour. Compare unconditionally so an
  # empty request-time snapshot (server registered its legend AFTER the
  # request was sent) is rejected against a now-non-empty legend instead of
  # being silently decoded as though it matched.
  let pendingLegend = extras.legend
  if colorTabOpt.get.legend != pendingLegend:
    logLspDegraded(
      "Semantic tokens", "legend changed while request was in flight; dropping response"
    )
    return

  # Capture the buffer so the closure survives the caller's stack frame; the
  # apply loop reads line lengths to split multi-line tokens into per-row
  # entries and reads line text to convert UTF-16 code-unit positions from
  # the LSP response into rune indices for the overlay.
  let buf = activeBuffer
  let lineRuneCount: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
    if row < 0 or row >= buf.len:
      -1
    else:
      buf.getLineLen(row)
  let lineText: LineTextFn = proc(row: int): string {.gcsafe, raises: [].} =
    if row < 0 or row >= buf.len:
      ""
    else:
      buf.getLine(row)

  # Pass the REQUEST-time contentVersion (not the current one). If the buffer
  # advanced in flight, the stamp is older than the current contentVersion,
  # and the next `updateHighlight` will drop the stale overlay via
  # `semanticContentVersion != contentVersion`.
  let outcome = applySemanticTokens(
    activeBuffer.highlight, resp, colorTabOpt.get, requestContentVersion, lineRuneCount,
    extras.rangeFirst, extras.rangeLast, lineText,
  )

  case outcome
  of saoDone:
    discard
  of saoRejectedCap:
    logLspDegraded(
      "Semantic tokens", "token count exceeds cap (" & $MaxSemanticTokens & ")"
    )
    inc poll.rejectStreak
    return
  of saoRejectedMalformed:
    logLspDegraded("Semantic tokens", "malformed response (missing or invalid data)")
    inc poll.rejectStreak
    return
  of saoRejectedNoLegend:
    logDebug("editor", "Semantic tokens: legend not yet available")
    inc poll.rejectStreak
    return

  # Stamp with the current changeSeq / request-time viewport so an edit or
  # scroll in flight does not mark the cache valid for content or a viewport
  # the server never saw. classifyResponse already verified contentVersion
  # hasn't drifted (it bumps on every edit, including no-undo mutators that
  # bypass changeSeq), so current changeSeq == request-time changeSeq here.
  e.state.lspCache.semanticTokensCache = SemanticTokensCache(
    changeSeq: currentChangeSeq,
    filePath: activeBuffer.filePath.get(""),
    isValid: true,
    topLine: extras.viewportTopLine,
    bottomLine: extras.viewportBottomLine,
  )
  poll.rejectStreak = 0

proc doUpdateSemanticTokensCache(e: Editor) =
  ## Internal: Start an async semantic tokens request (non-blocking)
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    invalidateSemanticTokensCache(e.lsp, e.state.lspCache)
    return

  # Request semantic tokens for visible range (with margin)
  let (topLine, bottomLine) = e.viewportRequestRange()

  let langIdOpt = e.lsp.service.getLanguageIdFromPath(activeBuffer.filePath.get)
  let isRangeReq =
    langIdOpt.isSome and e.lsp.service.hasSemanticTokensRangeSupport(langIdOpt.get)

  # Snapshot the legend at request-send time. If the server dynamically
  # re-registers with a different legend, the response's tokenType indices
  # still refer to THIS snapshot; processSemanticTokensResponse rejects on
  # mismatch instead of decoding against a different legend.
  let requestLegend =
    if langIdOpt.isSome:
      e.lsp.service.getSemanticTokensLegend(langIdOpt.get).get(
        SemanticTokensLegend(tokenTypes: @[], tokenModifiers: @[])
      )
    else:
      SemanticTokensLegend(tokenTypes: @[], tokenModifiers: @[])

  let ctxRes = e.startContextualRequest(
    lrfSemanticTokens,
    proc(): Result[int, string] =
      e.lsp.startSemanticTokensRequest(activeBuffer, topLine, bottomLine),
    blockedByOverlay = false,
  )
  if ctxRes.isOk:
    # Refresh the semantic-tokens-specific extras alongside the pending ctx.
    let extras = addr e.state.lspCache.semanticTokensPendingExtras
    extras.legend = requestLegend
    # Stamp the cache-validity check with the SAME `topLine`/`bottomLine`
    # the server was asked for (which already includes the +/-10-line
    # margin from `viewportRequestRange`). Using raw
    # `viewport.topLine + viewport.height` would spuriously invalidate the
    # cache on any small scroll even though the overlay covers the
    # scrolled-into rows from the margin.
    extras.viewportTopLine = topLine
    extras.viewportBottomLine = bottomLine
    if isRangeReq:
      extras.rangeFirst = topLine
      extras.rangeLast = bottomLine
    else:
      extras.rangeFirst = -1
      extras.rangeLast = -1
  else:
    logDebug("editor", "Semantic tokens request failed: " & ctxRes.error)
    invalidateSemanticTokensCache(e.lsp, e.state.lspCache)

proc semanticTokensCacheCoversViewport(
    e: Editor, cache: SemanticTokensCache, path: string
): bool =
  ## RHS is clamped to EOF to mirror `viewportRequestRange`. Without the clamp
  ## a visible EOF (short buffer, or `G` scrolled to end) makes this check
  ## permanently unsatisfiable and re-fires the request every debounce tick.
  let activeBuffer = e.activeBuffer()
  let viewportBottom = min(e.viewport.topLine + e.viewport.height, activeBuffer.len - 1)
  cache.isValid and cache.changeSeq == activeBuffer.changeSeq and cache.filePath == path and
    cache.topLine <= e.viewport.topLine and cache.bottomLine >= viewportBottom

proc updateSemanticTokensCache*(e: Editor) =
  ## Update the semantic tokens cache (with debouncing)
  ## Called during render to update LSP-based syntax highlighting
  ## Uses non-blocking async pattern to avoid freezing the UI
  if not e.lsp.enabled:
    return

  if not e.config.lsp.semanticTokens.enable:
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

  let poll = addr e.state.lspCache.semanticTokensPoll

  # Pending request from a different buffer (e.g. user switched buffers
  # mid-flight): cancel so we don't block behind an unrelated response.
  if e.state.lspCache.pending.hasKey(lrfSemanticTokens) and
      e.state.lspCache.pending[lrfSemanticTokens].path.len > 0 and
      e.state.lspCache.pending[lrfSemanticTokens].path != path:
    invalidateSemanticTokensCache(e.lsp, e.state.lspCache)

  # Check if there's a pending request - try to get response
  if e.state.lspCache.pending.hasKey(lrfSemanticTokens):
    let ctx = e.state.lspCache.pending[lrfSemanticTokens]
    let (status, resultOpt, errorOpt) = e.lsp.checkResponse(ctx.requestId)
    case status
    of lrsPending:
      # Still waiting for response, don't start a new request
      return
    of lrsSuccess:
      # ctx is on the stack; drop the pending entry now so a raise in the
      # processor cannot leave a zombie id behind.
      e.state.lspCache.pending.del(lrfSemanticTokens)
      try:
        if resultOpt.isSome and resultOpt.get.kind != JNull:
          e.processSemanticTokensResponse(resultOpt.get, ctx)
        else:
          # Null result: debounce the retry so a persistently null-answering
          # server does not fire per render frame.
          poll.lastUpdate = getMonoTime()
          inc poll.rejectStreak
      finally:
        resetPendingSemanticTokens(e.state.lspCache)
    of lrsError, lrsTimeout:
      logLspDegraded("Semantic tokens", status, errorOpt.get(""))
      e.state.lspCache.pending.del(lrfSemanticTokens)
      resetPendingSemanticTokens(e.state.lspCache)
      poll.lastUpdate = getMonoTime()
      inc poll.rejectStreak

  if e.semanticTokensCacheCoversViewport(e.state.lspCache.semanticTokensCache, path):
    return

  # Debounce with exponential backoff on the reject streak.
  let now = getMonoTime()
  let elapsed = now - poll.lastUpdate
  if elapsed >= poll[].debounceThreshold():
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
  cancelPendingRequest(lsp, cache, lrfInlayHint)

proc invalidateAllLspCaches*(e: Editor) =
  ## Drop the persistent overlay caches (SemanticTokens, InlayHint,
  ## DocumentHighlight, CodeLens) and cancel their in-flight requests. Use after
  ## buffer identity changes (loadFile, reload, LSP restart) so a pre-swap
  ## response cannot paint stale coords onto the fresh buffer. Other features
  ## have no such overlay and are guarded by `classifyResponse`.
  invalidateSemanticTokensCache(e.lsp, e.state.lspCache)
  invalidateInlayHintCache(e.lsp, e.state.lspCache)
  invalidateDocumentHighlightCache(e.lsp, e.state.lspCache)
  invalidateCodeLensCache(e.lsp, e.state.lspCache)

proc processInlayHintResponse(e: Editor, hints: seq[InlayHint]) =
  ## Internal: convert an inlay hint response into the cached, per-line format.
  ## Updates the debounce timer (including on reject) so a persistently
  ## failing server does not busy-loop on every render frame.
  e.state.lspCache.inlayHintPoll.lastUpdate = getMonoTime()

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
  e.state.lspCache.inlayHintPoll.rejectStreak = 0

proc doUpdateInlayHintCache(e: Editor) =
  ## Internal: Start an async inlay hint request for the visible range (non-blocking)
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    invalidateInlayHintCache(e.lsp, e.state.lspCache)
    return

  # Request the visible range with a small margin (matches semantic tokens).
  let (topLine, bottomLine) = e.viewportRequestRange()

  let ctxRes = e.startContextualRequest(
    lrfInlayHint,
    proc(): Result[int, string] =
      e.lsp.startInlayHintRequest(activeBuffer, topLine, bottomLine),
    blockedByOverlay = false,
  )
  if ctxRes.isErr:
    invalidateInlayHintCache(e.lsp, e.state.lspCache)

proc updateInlayHintCache*(e: Editor) =
  ## Update the inlay hint cache (with debouncing)
  ## Called from tickLsp. Uses non-blocking async pattern to avoid freezing the UI.
  if not e.lsp.enabled or not e.showInlayHint:
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

  var poll = addr e.state.lspCache.inlayHintPoll

  e.pollDebouncedLspResponse(lrfInlayHint, poll, "Inlay hint"):
    if resultOpt.isSome and resultOpt.get.kind != JNull:
      e.processInlayHintResponse(parseInlayHintResponse(resultOpt.get))
  do:
    discard # Failure only advances the backoff; the cache stays as it was

  # Check if cache is still valid and covers the current viewport
  let cache = e.state.lspCache.inlayHintCache
  if cache.isValid and cache.changeSeq == activeBuffer.changeSeq and
      cache.filePath == path and cache.topLine <= e.viewport.topLine and
      cache.bottomLine >= e.viewport.topLine + e.viewport.height:
    return

  # Debounce with exponential backoff on the reject streak.
  let now = getMonoTime()
  let elapsed = now - poll.lastUpdate
  if elapsed >= poll[].debounceThreshold():
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
  if e.showInlayHint:
    # The cache is keyed by file but read per line number, so right after a
    # buffer switch (before the highlightChanged invalidation in updateForFrame
    # runs) it can still hold the previous file's hints. Gate on the owning
    # file once per frame instead of per line.
    let cache = e.state.lspCache.inlayHintCache
    if cache.isValid and some(cache.filePath) == e.activeBuffer().filePath:
      result.add e.inlayHintVirtualTextProvider()

  if e.showCodeLens:
    # Same per-file gate as inlay hints: the cache is line-keyed, so right after
    # a buffer switch it can still hold the previous file's lenses. Gate on the
    # owning file once per frame instead of per line.
    let cache = e.state.lspCache.codeLensCache
    if cache.isValid and some(cache.filePath) == e.activeBuffer().filePath:
      result.add e.codeLensVirtualTextProvider()

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

    # No force-update here: doUpdateCodeLensCache only *starts* an async request
    # whose response lands frames later via the updateCodeLensCache polling path,
    # so reading the cache right after would see stale data anyway (and the new
    # request would orphan any in-flight poll request by overwriting its id).
    # While showCodeLens is on the cache is kept fresh by that polling, which now
    # also feeds the inline renderer, so the explicit refresh is unnecessary.
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
