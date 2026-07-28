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

import std/[options, monotimes, tables]

import pkg/results

import types/editor_types, editor_lsp, lsp_integration, hover_popup
import buffer/[core, markers]

const HoverValidModes* =
  {EditorMode.Normal, EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine}

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

  let activeBuffer = e.activeBuffer()

  # Guard against unsupported servers so we report "not supported" immediately
  # instead of issuing a request that only fails after the response timeout.
  if not e.lsp.hasHoverSupport(activeBuffer):
    e.state.statusMessage = "LSP hover is not supported by the language server"
    return false

  let line = e.activeWindow.cursor.line
  let col = e.activeWindow.cursor.column
  let ctxRes = e.startContextualRequest(
    lrfHover,
    proc(): Result[int, string] =
      e.lsp.startHoverRequest(activeBuffer, line, col),
    validModes = HoverValidModes,
    cursor = some(BufferPosition(line: line, column: col)),
  )
  if ctxRes.isErr:
    e.state.statusMessage = "LSP hover failed: " & ctxRes.error
    return false
  return true

proc pollLspHover*(e: Editor) =
  ## Poll for pending LSP hover response
  ## This should be called from the main event loop (tick function)
  e.pollOneShotLspResponse({lrfHover}, "hover"):
    var hoverText = ""
    if resultOpt.isSome:
      let hoverOpt = parseHoverResponse(resultOpt.get)
      if hoverOpt.isSome:
        hoverText = getHoverText(hoverOpt.get)

    let cursorLine = ctx.cursorLine
    let cursorCol = ctx.cursorCol
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

  # Match manual hover: any Normal/Visual variant (Visual/VisualBlock/VisualLine).
  if e.state.mode notin HoverValidModes:
    return

  # Overlay (Command/Search/Rename) preserves base mode; showing a diagnostic
  # popup on top of the overlay would paint over its prompt.
  if e.state.overlay.isSome:
    return

  let cursorLine = e.activeWindow.cursor.line
  let cursorCol = e.activeWindow.cursor.column

  let poll = addr e.state.lspCache.autoHoverPoll
  # The popup is built from local diagnostics, so contentVersion is not part of
  # the change detection; -1 keeps it out of the comparison.
  if not poll[].requestTargetChanged(cursorLine, cursorCol, -1):
    return

  # Cursor moved — update tracked position
  poll.cursorLine = cursorLine
  poll.cursorColumn = cursorCol

  let diags = e.activeBuffer().getDiagnosticsAt(cursorLine, cursorCol)
  if diags.len == 0:
    # Cursor moved off diagnostics — hide popup if it was auto-shown
    if e.state.lspCache.hoverPopup.isActive:
      e.state.lspCache.hoverPopup.hide()
    return

  # Debounce — avoid flooding requests on fast cursor movement
  let now = getMonoTime()
  poll.interval = e.config.lsp.diagnostics.autoHoverDelay
  if not poll[].debounceElapsed(now):
    # Reset tracked position so next tick retries after debounce expires
    poll.cursorLine = -1
    poll.cursorColumn = -1
    return
  poll.lastUpdate = now

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
