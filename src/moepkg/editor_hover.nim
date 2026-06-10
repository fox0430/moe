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

## LSP Hover request / poll orchestration and auto-hover diagnostic display.
## Hover content merges LSP hover information with buffer diagnostics at the
## cursor — the diagnostics-on-hover behavior is treated as part of the hover
## feature, not the diagnostics feature.

import std/[options, monotimes, times]

import editor_types, lsp_integration, hover_popup, buffer

proc startLspHover*(e: Editor): bool =
  ## Start async LSP hover request at current cursor position
  ## Returns true if request was started successfully
  ## Results will be polled by pollLspHover in the tick function
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  if not e.config.lsp.hover.enable:
    e.state.statusMessage = "LSP hover is disabled"
    return false

  # Cancel any pending hover request
  if e.state.lspCache.pendingHoverRequestId != 0:
    e.lsp.cancelRequest(e.state.lspCache.pendingHoverRequestId)
    e.state.lspCache.pendingHoverRequestId = 0

  let activeBuffer = e.activeBuffer()
  let reqResult = e.lsp.startHoverRequest(
    activeBuffer, e.activeWindow.cursor.line, e.activeWindow.cursor.column
  )

  if reqResult.isErr:
    e.state.statusMessage = "LSP hover failed: " & reqResult.error
    return false

  e.state.lspCache.pendingHoverRequestId = reqResult.get
  e.state.lspCache.pendingHoverBufferId = activeBuffer.id
  e.state.lspCache.pendingHoverCursorLine = e.activeWindow.cursor.line
  e.state.lspCache.pendingHoverCursorCol = e.activeWindow.cursor.column
  return true

proc pollLspHover*(e: Editor) =
  ## Poll for pending LSP hover response
  ## This should be called from the main event loop (tick function)
  if not e.lsp.enabled:
    return

  let requestId = e.state.lspCache.pendingHoverRequestId
  if requestId == 0:
    return

  # Check for response (events were already polled at the top of tick())
  let (status, resultOpt, errorOpt) = e.lsp.checkResponse(requestId)

  case status
  of lrsPending:
    discard # Still waiting
  of lrsSuccess:
    e.state.lspCache.pendingHoverRequestId = 0

    # Discard the response if the active buffer changed while waiting: the hover
    # text is for the originating buffer, so merging it with another buffer's
    # diagnostics (or showing it over unrelated content) would be wrong.
    if e.activeBuffer().id != e.state.lspCache.pendingHoverBufferId:
      return

    var hoverText = ""
    if resultOpt.isSome:
      let hoverOpt = parseHoverResponse(resultOpt.get)
      if hoverOpt.isSome:
        hoverText = getHoverText(hoverOpt.get)

    let cursorLine = e.state.lspCache.pendingHoverCursorLine
    let cursorCol = e.state.lspCache.pendingHoverCursorCol
    let diags = e.activeBuffer().getDiagnosticsAt(cursorLine, cursorCol)
    let diagText = formatDiagnosticsForHover(diags)

    var combinedText = ""
    if diagText.len > 0 and hoverText.len > 0:
      combinedText = diagText & "\n\n" & hoverText
    elif diagText.len > 0:
      combinedText = diagText
    else:
      combinedText = hoverText

    if combinedText.len > 0:
      e.state.lspCache.hoverPopup.show(combinedText, cursorLine, cursorCol)
    else:
      e.state.statusMessage = "No hover information available"
  of lrsError:
    e.state.lspCache.pendingHoverRequestId = 0
    if errorOpt.isSome:
      e.state.statusMessage = "LSP hover failed: " & errorOpt.get
  of lrsTimeout:
    e.state.lspCache.pendingHoverRequestId = 0
    e.state.statusMessage = "LSP hover timed out"

proc requestLspHover*(e: Editor): bool =
  ## Request LSP hover information at current cursor position (async)
  ## Returns true if request was started
  ## The hover popup will be shown when the response arrives
  e.startLspHover()

proc maybeAutoHoverDiagnostic*(e: Editor) =
  ## Automatically show diagnostic hover when cursor moves onto a diagnostic.
  ## Called from tick(). Requires Lsp.Diagnostics.autoHover = true.
  if not e.lsp.enabled or not e.config.lsp.diagnostics.enable or
      not e.config.lsp.diagnostics.autoHover:
    return

  # Only in Normal/Visual modes
  if e.state.mode notin {EditorMode.Normal, EditorMode.Visual}:
    return

  let cursorLine = e.activeWindow.cursor.line
  let cursorCol = e.activeWindow.cursor.column

  # Check if cursor position changed since last auto-hover check
  if cursorLine == e.state.lspCache.autoHoverCursorLine and
      cursorCol == e.state.lspCache.autoHoverCursorCol:
    return

  # Cursor moved — update tracked position
  e.state.lspCache.autoHoverCursorLine = cursorLine
  e.state.lspCache.autoHoverCursorCol = cursorCol

  let diags = e.activeBuffer().getDiagnosticsAt(cursorLine, cursorCol)
  if diags.len == 0:
    # Cursor moved off diagnostics — hide popup if it was auto-shown
    if e.state.lspCache.hoverPopup.isActive:
      e.state.lspCache.hoverPopup.hide()
    return

  # Debounce — avoid flooding requests on fast cursor movement
  let now = getMonoTime()
  let elapsed = now - e.state.lspCache.lastAutoHoverUpdate
  if elapsed < initDuration(milliseconds = e.config.lsp.diagnostics.autoHoverDelay):
    # Reset tracked position so next tick retries after debounce expires
    e.state.lspCache.autoHoverCursorLine = -1
    e.state.lspCache.autoHoverCursorCol = -1
    return
  e.state.lspCache.lastAutoHoverUpdate = now

  # Show diagnostic-only popup (no LSP hover request needed)
  let diagText = formatDiagnosticsForHover(diags)
  if diagText.len > 0:
    e.state.lspCache.hoverPopup.show(diagText, cursorLine, cursorCol)
    e.state.lspCache.hoverPopup.isAutoHover = true

proc hideHoverPopup*(cache: var LspCacheState) =
  ## Hide the hover popup
  cache.hoverPopup.hide()

proc hoverPopupScrollDown*(cache: var LspCacheState) =
  ## Scroll hover popup down
  cache.hoverPopup.scrollDown()

proc hoverPopupScrollUp*(cache: var LspCacheState) =
  ## Scroll hover popup up
  cache.hoverPopup.scrollUp()

proc hoverPopupScrollRight*(cache: var LspCacheState) =
  ## Scroll hover popup right
  cache.hoverPopup.scrollRight()

proc hoverPopupScrollLeft*(cache: var LspCacheState) =
  ## Scroll hover popup left
  cache.hoverPopup.scrollLeft()
