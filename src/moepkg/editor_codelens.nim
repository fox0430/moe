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

# This file is included by editor.nim - do not import directly
# Contains CodeLens, DocumentHighlight, and SemanticTokens related procedures

proc hasCodeLensSupport*(e: Editor): bool =
  ## Check if CodeLens is supported for the current buffer
  if not e.lsp.enabled:
    return false
  let activeBuffer = e.activeBuffer()
  return e.lsp.hasCodeLensSupport(activeBuffer)

proc processCodeLensResponse(e: Editor, lenses: seq[CodeLens]) =
  ## Internal: Process code lens response from LSP
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
      # Need to resolve - this is still blocking but only for lenses that need it
      let resolveResult = e.lsp.requestCodeLensResolve(activeBuffer, lens)
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
      if item.line notin itemsByLine:
        itemsByLine[item.line] = @[]
      itemsByLine[item.line].add(item)

  e.state.lspCache.codeLensCache = CodeLensCache(
    itemsByLine: itemsByLine,
    changeSeq: activeBuffer.changeSeq,
    filePath: filePath,
    isValid: true,
  )

  # Update timestamp after successful update
  e.state.lspCache.lastCodeLensUpdate = getMonoTime()

proc doUpdateCodeLensCache(e: Editor) =
  ## Internal: Start an async CodeLens request (non-blocking)
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
    let (status, resultOpt, _) =
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
        e.processCodeLensResponse(lenses)
      # Continue to check if we need to start a new request (buffer might have changed)
    of lrsError, lrsTimeout:
      # Request failed or timed out, mark cache as valid but empty to prevent retry loop
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

proc getCodeLensItemsForLine*(e: Editor, line: int): seq[CodeLensItem] =
  ## Get cached CodeLens items for a specific line (O(1) lookup)
  if not e.state.lspCache.codeLensCache.isValid:
    return @[]

  e.state.lspCache.codeLensCache.itemsByLine.getOrDefault(line, @[])

proc getCodeLensItemsForCurrentLine*(e: Editor): seq[CodeLensItem] =
  ## Get cached CodeLens items for the current cursor line
  e.getCodeLensItemsForLine(e.state.cursor.line)

proc executeCodeLensItem*(e: Editor, item: CodeLensItem): Result[void, string] =
  ## Execute a cached CodeLens item's command
  if not e.lsp.enabled:
    return err("LSP is not enabled")

  if item.command.len == 0:
    return err("CodeLens has no command")

  let activeBuffer = e.activeBuffer()

  # Convert arguments back to JsonNode
  var args: seq[JsonNode] = @[]
  for argStr in item.arguments:
    try:
      args.add(parseJson(argStr))
    except JsonParsingError:
      args.add(%argStr)

  let execResult = e.lsp.requestExecuteCommand(activeBuffer, item.command, args)
  if execResult.isErr:
    return err("Failed to execute command: " & execResult.error)

  e.state.statusMessage = "Executed: " & item.title
  return ok()

proc invalidateCodeLensCache*(e: Editor) =
  ## Invalidate the CodeLens cache (call when buffer changes significantly)
  e.state.lspCache.codeLensCache.isValid = false

# Document Highlight support
proc invalidateDocumentHighlightCache*(e: Editor) =
  ## Invalidate the Document Highlight cache
  e.state.lspCache.documentHighlightCache.isValid = false
  e.state.lspCache.documentHighlightCache.itemsByLine.clear()

proc processDocumentHighlightResponse(e: Editor, highlights: seq[DocumentHighlight]) =
  ## Internal: Process document highlights from LSP response
  let activeBuffer = e.activeBuffer()

  # Convert LSP DocumentHighlight to our cached format
  # Handle multi-line highlights by creating an item for each line
  # Group by line for O(1) lookup during rendering
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
      # Single line highlight
      let item = DocumentHighlightItem(
        line: startLine,
        startColumn: highlight.range.start.character,
        endColumn: highlight.range.`end`.character,
        kind: kind,
      )
      if startLine notin itemsByLine:
        itemsByLine[startLine] = @[]
      itemsByLine[startLine].add(item)
    else:
      # Multi-line highlight: create an item for each line
      for line in startLine .. endLine:
        let startCol = if line == startLine: highlight.range.start.character else: 0
        # For end column, use a large value for middle/last lines
        # (will be clamped during rendering)
        let endCol = if line == endLine: highlight.range.`end`.character else: int.high
        let item = DocumentHighlightItem(
          line: line, startColumn: startCol, endColumn: endCol, kind: kind
        )
        if line notin itemsByLine:
          itemsByLine[line] = @[]
        itemsByLine[line].add(item)

  e.state.lspCache.documentHighlightCache = DocumentHighlightCache(
    itemsByLine: itemsByLine,
    cursorLine: e.state.cursor.line,
    cursorColumn: e.state.cursor.column,
    changeSeq: activeBuffer.changeSeq,
    isValid: true,
  )
  e.state.lspCache.lastDocumentHighlightUpdate = getMonoTime()

proc doUpdateDocumentHighlightCache(e: Editor) =
  ## Internal: Start an async Document Highlight request (non-blocking)
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    e.invalidateDocumentHighlightCache()
    return

  # Start async request
  let reqResult = e.lsp.startDocumentHighlightRequest(
    activeBuffer, e.state.cursor.line, e.state.cursor.column
  )
  if reqResult.isOk:
    e.state.lspCache.pendingDocumentHighlightRequestId = reqResult.get
  else:
    e.invalidateDocumentHighlightCache()

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
      e.invalidateDocumentHighlightCache()
    e.state.lspCache.pendingDocumentHighlightRequestId = 0
    return

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  # Check if there's a pending request - try to get response
  if e.state.lspCache.pendingDocumentHighlightRequestId != 0:
    let (status, resultOpt, _) =
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
      e.state.lspCache.pendingDocumentHighlightRequestId = 0

  # Check if cursor position changed
  # (same line and column means no need to update)
  if e.state.lspCache.documentHighlightCache.isValid and
      e.state.lspCache.documentHighlightCache.cursorLine == e.state.cursor.line and
      e.state.lspCache.documentHighlightCache.cursorColumn == e.state.cursor.column and
      e.state.lspCache.documentHighlightCache.changeSeq == activeBuffer.changeSeq:
    return

  # Debounce - only update if enough time has passed since last update
  let now = getMonoTime()
  let elapsed = now - e.state.lspCache.lastDocumentHighlightUpdate
  let threshold =
    initDuration(milliseconds = e.state.lspCache.documentHighlightUpdateInterval)
  if elapsed >= threshold:
    e.doUpdateDocumentHighlightCache()

# =============================================================================
# Semantic Tokens (LSP-based syntax highlighting)
# =============================================================================

proc invalidateSemanticTokensCache*(e: Editor) =
  ## Invalidate the semantic tokens cache, forcing re-request on next update
  e.state.lspCache.semanticTokensCache = SemanticTokensCache(isValid: false)
  e.state.lspCache.pendingSemanticTokensRequestId = 0

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
    e.invalidateSemanticTokensCache()
    return

  # Request semantic tokens for visible range (with margin)
  let topLine = max(0, e.viewport.topLine - 10)
  let bottomLine =
    min(e.viewport.topLine + e.viewport.height + 10, activeBuffer.len - 1)

  # Start async request
  let reqResult = e.lsp.startSemanticTokensRequest(activeBuffer, topLine, bottomLine)
  if reqResult.isOk:
    e.state.lspCache.pendingSemanticTokensRequestId = reqResult.get
  else:
    logDebug("editor", "Semantic tokens request failed: " & reqResult.error)
    e.invalidateSemanticTokensCache()

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
    let (status, resultOpt, _) =
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
      logDebug("editor", "Semantic tokens request failed or timed out")
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

proc getCodeLensDisplayText*(e: Editor, line: int): string =
  ## Get display text for CodeLens on a specific line
  ## Returns empty string if no CodeLens on this line
  let items = e.getCodeLensItemsForLine(line)
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

proc hideCodeLensPicker*(e: Editor) =
  ## Hide the CodeLens picker
  e.state.lspCache.codeLensPicker.isActive = false
  e.state.lspCache.codeLensPicker.items = @[]

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

proc codeLensPickerSelectByNumber*(e: Editor, num: int): bool =
  ## Select and execute CodeLens item by number (1-9)
  ## Returns true if successfully executed
  if not e.state.lspCache.codeLensPicker.isActive or
      e.state.lspCache.codeLensPicker.items.len == 0:
    return false

  let index = num - 1 # Convert 1-based to 0-based index
  if index < 0 or index >= e.state.lspCache.codeLensPicker.items.len:
    return false

  let item = e.state.lspCache.codeLensPicker.items[index]
  e.hideCodeLensPicker()

  let execResult = e.executeCodeLensItem(item)
  if execResult.isErr:
    e.state.statusMessage = execResult.error
    return false

  return true

proc codeLensPickerConfirm*(e: Editor): bool =
  ## Confirm selection and execute the selected CodeLens item
  ## Returns true if successfully executed
  if not e.state.lspCache.codeLensPicker.isActive or
      e.state.lspCache.codeLensPicker.items.len == 0:
    return false

  let item =
    e.state.lspCache.codeLensPicker.items[e.state.lspCache.codeLensPicker.selectedIndex]
  e.hideCodeLensPicker()

  let execResult = e.executeCodeLensItem(item)
  if execResult.isErr:
    e.state.statusMessage = execResult.error
    return false

  return true

proc executeCurrentLineCodeLens*(e: Editor): bool =
  ## Execute CodeLens on current line
  ## If multiple CodeLens items exist, show picker to choose
  ## Returns true if successfully executed (or picker shown)
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  # Force update cache (bypass debouncing for explicit user action)
  if e.state.display.showCodeLens:
    e.doUpdateCodeLensCache()

  if not e.state.lspCache.codeLensCache.isValid:
    e.state.statusMessage = "No CodeLens available"
    return false

  # Get CodeLens items for current line
  let items = e.getCodeLensItemsForCurrentLine()
  if items.len == 0:
    e.state.statusMessage = "No CodeLens on current line"
    return false

  # If only one item, execute directly
  if items.len == 1:
    let execResult = e.executeCodeLensItem(items[0])
    if execResult.isErr:
      e.state.statusMessage = execResult.error
      return false
    return true

  # Multiple items - show picker
  e.showCodeLensPicker(items)
  e.state.statusMessage =
    "Select CodeLens (1-9: select, j/k: navigate, Enter: confirm, Esc: cancel)"
  return true
