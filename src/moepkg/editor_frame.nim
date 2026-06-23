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

## Per-frame pipeline for the editor: background processing (`tick`: LSP, file
## watching, config reload, autosave, notifications), per-frame state
## advancement (`updateForFrame`: animation, highlight, viewport/layout), and a
## read-only draw (`draw` / `render`, main content + overlay popups). Also the
## debug-buffer refresher, notification routing, and editor shutdown.

import std/[options, strutils, monotimes, times]

import
  types/editor_types,
  editor_reload,
  editor_config_reload,
  editor_file,
  editor_lsp,
  editor_codelens,
  editor_selectionrange,
  editor_documentsymbol,
  editor_documentlink,
  editor_signaturehelp,
  editor_hover,
  editor_callhierarchy,
  editor_navigation,
  editor_render

import
  status_line, render_utils, logger, message_log, debug_viewer, completion,
  signature_help, hover_popup, unicode_utils, motion

proc shutdown*(e: Editor) =
  ## Shutdown editor and clean up resources (including LSP servers)
  e.lsp.shutdown()

proc maybeUpdateDebugBuffer*(e: Editor) =
  ## Update debug buffer content periodically if it's displayed in a window
  ## This provides auto-refresh functionality for the debug viewer
  if e.state.windowDisplay.debugBuffer == nil:
    return

  # Check if the debug buffer is still displayed in a window
  var foundWindow: EditorWindow = nil
  for window in e.windowManager.windows:
    if window.buffer == e.state.windowDisplay.debugBuffer:
      foundWindow = window
      break

  if foundWindow == nil:
    # Debug buffer is no longer displayed, clear the reference
    e.state.windowDisplay.debugBuffer = nil
    return

  # Check if enough time has passed since last update
  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastDebugUpdate
  let threshold = initDuration(milliseconds = e.state.timing.debugUpdateInterval)

  if elapsed < threshold:
    return

  # Generate fresh debug info based on config settings
  var debugLines: seq[string] = @[]
  let debugConfig = e.config.debug

  for i, window in e.windowManager.windows:
    generateWindowInfo(
      debugLines,
      i,
      i == e.windowManager.activeWindowIndex,
      e.bufferIndexById(window.buffer.id),
      window.viewport.x,
      window.viewport.y,
      window.viewport.width,
      window.viewport.height,
      window.viewport.topLine,
      window.viewport.leftColumn,
      window.cursor.line,
      window.cursor.column,
      debugConfig.windowNode.enable,
    )

  for i, buf in e.buffers:
    generateBufferInfo(
      debugLines,
      i,
      buf.filePath,
      buf.isModified,
      buf.readOnly,
      $buf.language,
      $buf.encoding,
      buf.len,
      buf.changeSeq,
      debugConfig.bufferStatus.enable,
    )

  generateEditorStateInfo(
    debugLines, e.state.mode, e.state.previousMode, e.activeWindow.cursor.line,
    e.cursor.column, e.state.input.commandText, e.state.statusMessage,
    debugConfig.editorView.enable,
  )

  generateSearchInfo(
    debugLines,
    e.state.input.search.text,
    e.state.input.search.lastText,
    $e.state.input.search.direction,
    e.state.input.search.history.len,
    e.state.input.search.ignorecase,
    e.state.input.search.smartcase,
    e.state.input.search.incsearch,
    e.state.input.search.hlsearch,
    debugConfig.search.enable,
  )

  generateDisplayInfo(
    debugLines, e.state.display.showStatusLine, e.state.display.multiStatusLine,
    e.state.display.showLineNumbers, e.state.display.showCursorLine,
    e.state.display.showSyntax, e.state.display.showIndentationLines,
    e.state.display.showSidebar, e.state.display.scrollbarWidth,
    e.state.display.showModifiedLines, e.state.display.lineWrap,
    e.state.display.tabStop, debugConfig.editorView.enable,
  )

  generateMacroInfo(
    debugLines, e.state.macroState.isRecording, e.state.macroState.register,
    e.state.macroState.registers.len, e.state.macroState.playbackDepth,
    debugConfig.macroState.enable,
  )

  generateVisualInfo(
    debugLines,
    e.state.visualSelection.active,
    $e.state.visualSelection.kind,
    e.state.visualSelection.start.line,
    e.state.visualSelection.start.column,
    e.state.visualSelection.current.line,
    e.state.visualSelection.current.column,
    debugConfig.visual.enable,
  )

  generateJumpListInfo(
    debugLines, e.state.jumpList.list.len, e.state.jumpList.index,
    debugConfig.jumpList.enable,
  )

  generateLspInfo(
    debugLines, e.state.lspCache.codeLensCache.itemsByLine.len,
    e.state.lspCache.locations.isSome, e.state.lspCache.codeLensCache.isValid,
    debugConfig.lsp.enable,
  )

  # Update debug viewer state and create new buffer
  if foundWindow.modeState.kind == mskDebug:
    let debugState = foundWindow.modeState.debug
    debugState.lines = debugLines
    let newDebugBuffer = debugState.createDebugTextBuffer()

    # Preserve scroll position
    let savedTopLine = foundWindow.viewport.topLine
    let savedLeftColumn = foundWindow.viewport.leftColumn

    # Replace buffer in the window
    foundWindow.buffer = newDebugBuffer

    # Restore scroll position (clamped to valid range)
    foundWindow.viewport.topLine = min(savedTopLine, max(0, newDebugBuffer.len - 1))
    foundWindow.viewport.leftColumn = savedLeftColumn

    # Update the reference in state
    e.state.windowDisplay.debugBuffer = newDebugBuffer
  e.state.timing.lastDebugUpdate = now

proc notify*(e: Editor, msg: string, level: NotificationLevel = nlInfo) =
  ## Send a notification. Routes to popup or status line based on config.
  if e.config.notification.popupNotifications:
    e.state.notificationPopup.addNotification(msg, level)
  else:
    e.state.statusMessage = msg

proc maybeCleanupTimedOutLspRequests(e: Editor) =
  ## Sweep timed-out LSP requests whose consumer stopped polling (e.g. a
  ## completion request left in flight when Insert mode is exited: the poller
  ## is mode-gated and never calls checkResponse again). Without this, such
  ## requests linger in activeRequests/pendingResponses for the rest of the
  ## session on features that have no cancelRequest reclaim path.
  ##
  ## Throttled to once per second: the sweep only ever removes entries already
  ## past their timeout, and active consumers reclaim their own responses via
  ## checkResponse each frame, so a high-frequency sweep buys nothing.
  ##
  ## Must run after the pollLsp* helpers so an active consumer observes its own
  ## lrsTimeout (and clears its pending id) before the sweep would drop the entry.
  let now = getMonoTime()
  let threshold = initDuration(milliseconds = e.state.timing.lspCleanupInterval)
  if now - e.state.timing.lastLspCleanup < threshold:
    return
  e.state.timing.lastLspCleanup = now

  e.lsp.cleanupTimedOutRequests()

proc tickLsp(e: Editor) =
  ## Per-frame LSP processing: poll the server, surface its messages, push
  ## buffer changes, then drain all response caches/pollers.
  ##
  ## Ordering within this phase matters: `maybeUpdateLsp` notifies the server of
  ## the latest buffer state, and the `pollLsp*` helpers below read the resulting
  ## responses, so the update must run before the polls.

  # Poll LSP for messages (non-blocking). This is the single per-frame poll:
  # the pollLspXxx helpers below rely on this and must not poll again themselves.
  e.lsp.poll(0)

  # Cleanup stale progress entries (handles missing 'end' notifications)
  e.lsp.cleanupStaleProgress()

  # Update LSP progress display
  let progressOpt = e.lsp.getLatestActiveProgress()
  if progressOpt.isSome:
    e.state.ui.lspProgressText = getProgressText(progressOpt.get)
  else:
    e.state.ui.lspProgressText = ""

  # Display any pending LSP status messages
  let lspMessages = e.lsp.getAndClearMessages()
  if lspMessages.len > 0:
    # Store LSP messages for the log viewer
    addLspMessageLog(lspMessages)
    if e.config.notification.lspForcePopup:
      # Force all LSP messages to popup notifications
      for msg in lspMessages:
        let level =
          if msg.startsWith("[LSP Error]"):
            nlError
          elif msg.startsWith("[LSP Warning]"):
            nlWarning
          else:
            nlInfo
        e.state.notificationPopup.addNotification(msg, level)
    elif e.config.notification.screenNotifications and
        e.config.notification.lspScreenNotify:
      e.notify(lspMessages[^1])
    if e.config.notification.logNotifications and e.config.notification.lspLogNotify:
      for msg in lspMessages:
        logInfo("lsp", msg)

  # Update LSP if buffer was modified
  e.maybeUpdateLsp()

  # Update LSP caches
  e.updateCodeLensCache()
  e.updateDocumentHighlightCache()
  e.updateInlayHintCache()
  # Note: updateSemanticTokensCache is called in updateForFrame after updateHighlight
  e.requestSignatureHelpFromLsp()
  e.pollLspCompletion()
  e.pollLspHover()
  e.maybeAutoHoverDiagnostic()
  e.pollLspLocationRequest()
  e.pollLspCallHierarchy()
  e.pollLspSelectionRange()
  e.pollLspDocumentSymbols()
  e.pollLspDocumentLinks()
  e.pollLspDocumentLinkResolve()

  # Reclaim abandoned (timed-out, no longer polled) requests. Runs last so
  # active consumers process their own responses above before the sweep.
  e.maybeCleanupTimedOutLspRequests()

proc tickFileAndConfig(e: Editor) =
  ## Detect external edits and config changes and reload them.
  ## `maybeReloadExternallyModifiedFile` refreshes the conflict scan state that
  ## `tickGitAndDebug` later consumes, and `maybeReloadConfig` may rewrite
  ## `e.config`, which `tickAutoSave` reads — so this phase must run before both.
  e.maybeReloadExternallyModifiedFile()
  e.maybeReloadConfig()

proc tickGitAndDebug(e: Editor) =
  ## Git and debug updates. The diff subprocess itself is scheduled lazily
  ## from status_line.cachedGitDiffCounts (called during status-line
  ## rendering); here we just consume the most recent diff result for the
  ## sidebar gutter, gated on the user's showGitDiff flag.
  ## Depends on `tickFileAndConfig` having refreshed the conflict scan first.
  if e.state.display.showGitDiff:
    maybeApplyGitMarkers(e.activeBuffer())
  e.maybeUpdateConflicts()
  e.maybeUpdateDebugBuffer()

proc tickAutoSave(e: Editor) =
  ## Auto save/backup. Reads `e.config`, so it must run after
  ## `tickFileAndConfig` has applied any reloaded config.
  e.autoSave()
  e.autoBackup()

proc tickNotifications(e: Editor) =
  ## Dismiss expired popup notifications.
  e.state.notificationPopup.tick()

proc tick*(e: Editor) =
  ## Background processing: LSP, file watching, autosave, etc.
  ## Should be called each frame before rendering.
  ##
  ## Each phase is a self-contained proc; the call order below is significant
  ## (see the per-phase docs for the dependencies between them) and must match
  ## the original sequence.
  e.tickLsp()
  e.tickFileAndConfig()
  e.tickGitAndDebug()
  e.tickAutoSave()
  e.tickNotifications()

proc updateForFrame*(e: Editor, buffer: Buffer): bool =
  ## Advance per-frame editor state: smooth-scroll animation, fold cursor pin,
  ## matching-paren / current-word, syntax + semantic highlight, viewport size,
  ## and window layout (viewport scroll, selection-cursor sync, screen cursor).
  ## No drawing — the draw pass (`draw`) is a read-only projection of the state
  ## this produces. Returns true if the viewport was resized.

  # Update smooth scroll animation
  if e.state.windowDisplay.scrollAnimation.active:
    let reservedLines = steadyBottomAreaHeight()
    let bufferLen = e.activeBuffer().len
    let (_, cursorLine) = e.executer.motionController.viewportManager.updateScrollAnimation(
      e.state.windowDisplay.scrollAnimation, e.config.smoothScroll, reservedLines,
      bufferLen,
    )
    e.activeWindow.cursor.line = cursorLine

  # Keep the active cursor off lines hidden inside a collapsed fold. Many cursor
  # moves (search, :N, LSP jumps, mouse clicks, cursor restore on open) bypass
  # the motion clamp; normalize here so the cursor always sits on a visible line.
  # Non-file buffers have no folds, so this is a no-op for them.
  if not e.state.windowDisplay.scrollAnimation.active:
    let buf = e.activeBuffer()
    let collapsedFold = buf.foldState.getCollapsedFoldAt(e.activeWindow.cursor.line)
    if collapsedFold.isSome:
      # Pin the cursor to the fold's start line at column 0 (the fold is a single
      # unit; the cursor must not roam its hidden content).
      e.activeWindow.cursor.line = collapsedFold.get.startLine
      e.activeWindow.cursor.column = 0

  # Update highlight state (skip for debug buffer)
  let isDebugBuffer =
    e.state.windowDisplay.debugBuffer != nil and
    e.activeBuffer() == e.state.windowDisplay.debugBuffer

  if e.config.highlight.pairOfParen and not isDebugBuffer:
    e.state.matchingParenPos = findMatchingParenPosition(e.activeBuffer(), e.cursor)
  else:
    e.state.matchingParenPos = none(BufferPosition)

  if e.config.highlight.currentWord and not isDebugBuffer:
    e.state.currentWord = getWordAtPosition(e.activeBuffer(), e.cursor)
  else:
    e.state.currentWord = ""

  # Update syntax highlight before rendering (so semantic tokens can be applied on top)
  if not isDebugBuffer:
    let activeBuffer = e.activeBuffer()
    var highlightChanged = activeBuffer.highlightNeedsUpdate
    activeBuffer.updateHighlight()
    # Continue progressive initial highlighting if not yet complete
    if activeBuffer.continueInitialHighlight():
      highlightChanged = true
    # Continue progressive URI scanning for all file types
    if activeBuffer.continueUriScan():
      highlightChanged = true
    # If highlight was modified, we need to re-apply semantic tokens
    if highlightChanged:
      invalidateSemanticTokensCache(e.lsp, e.state.lspCache)
      # Inlay hints are keyed by absolute line number and rendered straight from
      # the cache, so an edit (highlightChanged) would otherwise leave stale
      # hints on now-shifted lines until the next debounced response. Drop the
      # cache and cancel any in-flight request, matching semantic tokens.
      invalidateInlayHintCache(e.lsp, e.state.lspCache)
    # Apply semantic tokens after local highlight is ready
    e.updateSemanticTokensCache()

  result = e.updateViewportSize(buffer)
  e.advanceLayoutForFrame(buffer, result)

proc renderMainContent(e: Editor, buffer: var Buffer) =
  ## Paint the main editor view (always uses split view since we always have at
  ## least one window). Read-only.
  e.renderSplitView(buffer)
  e.renderBottomLines(buffer)
  e.renderTempMessages(buffer)

proc renderOverlays(e: Editor, buffer: var Buffer) =
  ## Render overlay popups (completion, signature help, CodeLens picker, hover popup).

  if e.state.mode == EditorMode.Insert:
    let completionMgr = e.handlerManager.insertHandler.completionManager
    if completionMgr.isActive():
      # Anchor the popup to the start of the word being completed, not the
      # current cursor position. This prevents the popup from shifting when
      # cycling through candidates of different lengths.
      let anchorX = e.state.screenCursor.x - displayWidth(completionMgr.menu.prefix)
      # Stay above the (possibly grown) command-line area, plus one padding
      # row — matches the steady-state default of 2
      let bottomReserve = e.state.bottomAreaHeight(buffer.area.width) + 1
      let popupPos = calculatePopupPosition(
        anchorX, e.state.screenCursor.y, buffer.area.width, buffer.area.height,
        completionMgr.menu.entries, completionMgr.menu.maxVisible,
        e.config.autocomplete.windowBorder, bottomReserve,
      )
      renderCompletionPopup(
        buffer, completionMgr.menu, popupPos, e.config.autocomplete.windowBorder
      )

      # Render documentation panel next to completion popup. Anchor it to the
      # highlighted candidate's row (popup border + position within the visible
      # window) so it tracks the selection as you cycle, instead of pinning to
      # the popup's first row.
      if completionMgr.docPanel.visible:
        let borderOffset = if e.config.autocomplete.windowBorder: 1 else: 0
        let selectedRowOffset =
          borderOffset +
          (completionMgr.menu.selectedIndex - completionMgr.menu.scrollOffset)
        let docPos = calculateDocPanelPosition(
          popupPos, buffer.area.width, buffer.area.height, completionMgr.docPanel,
          bottomReserve, selectedRowOffset,
        )
        renderDocPanel(buffer, completionMgr.docPanel, docPos)

    let sigHelpMgr = e.handlerManager.insertHandler.signatureHelpManager
    if sigHelpMgr.isActive():
      let popupPos = calculateSignatureHelpPosition(
        e.state.screenCursor.x, e.state.screenCursor.y, buffer.area.width,
        buffer.area.height, sigHelpMgr.display.signature.len,
      )
      renderSignatureHelpPopup(buffer, sigHelpMgr.display, popupPos, true)

  if e.state.lspCache.codeLensPicker.isActive:
    e.renderCodeLensPicker(buffer)

  # Render hover popup (Normal mode)
  if e.state.lspCache.hoverPopup.isActive():
    let hoverMgr = e.state.lspCache.hoverPopup
    let popupPos = calculateHoverPopupPosition(
      e.state.screenCursor.x, e.state.screenCursor.y, buffer.area.width,
      buffer.area.height, hoverMgr,
    )
    renderHoverPopup(buffer, hoverMgr, popupPos, true)

  # Render notification popups: float above the (possibly grown)
  # command-line area, plus one padding row when the status line is shown
  if e.state.notificationPopup.hasActiveNotifications():
    let bottomReserve =
      e.state.bottomAreaHeight(buffer.area.width) +
      (if e.state.display.showStatusLine: 1 else: 0)
    let rects = e.state.notificationPopup.calculateNotificationPositions(
      buffer.area.width, buffer.area.height, bottomReserve
    )
    for rect in rects:
      renderNotificationPopup(buffer, rect)

proc draw(e: Editor, buffer: var Buffer) =
  ## Read-only projection of editor state onto the render buffer. The only state
  ## writes remaining in the draw are the idempotent, draw-side exceptions of
  ## Config (cursor placement + its own list scroll via ensureSelectedVisible)
  ## and Terminal-Input (cursor from the grid), each inline with its specialized
  ## render; see renderConfig / renderTerminal.
  clearBuffer(buffer)

  # Always use split view rendering - each window renders based on its own mode
  e.renderMainContent(buffer)

  e.renderOverlays(buffer)

proc render*(e: Editor, buffer: var Buffer) =
  ## Main render procedure: background processing (`tick`), per-frame state
  ## advancement (`updateForFrame`), then a read-only draw (`draw`).
  if buffer.area.width <= 0 or buffer.area.height <= 0:
    return

  e.tick()
  discard e.updateForFrame(buffer)
  e.draw(buffer)
