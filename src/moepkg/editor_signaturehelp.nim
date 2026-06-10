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

## LSP Signature Help request / poll orchestration
##
## The UI side (popup rendering, manager state) lives in signature_help.nim.
## This module owns the editor-side request lifecycle that drives it.

import std/[options, monotimes, times]

import editor_types, lsp_integration, signature_help

proc shouldRequestSignatureHelp*(
    sigHelp: SignatureHelpRequestState,
    cursorLine, cursorColumn, changeSeq: int,
    now: MonoTime,
): bool =
  ## Decide whether to fire a new auto signature help request.
  ## Returns false when nothing changed since the last request (change detection)
  ## or when still inside the debounce window. On consecutive failures the window
  ## widens (exponential backoff, capped at 16x) so a persistently failing server
  ## is retried at a slower cadence instead of every base interval. Pure so it
  ## can be unit-tested without driving a live LSP server.
  if sigHelp.cursorLine == cursorLine and sigHelp.cursorColumn == cursorColumn and
      sigHelp.changeSeq == changeSeq:
    return false
  let backoff = 1'i64 shl min(sigHelp.consecutiveErrors, 4) # 1, 2, 4, 8, 16
  now - sigHelp.lastUpdate >= initDuration(milliseconds = sigHelp.interval * backoff)

proc requestSignatureHelpFromLsp*(e: Editor) =
  ## Request signature help from LSP if in insert mode with paren depth > 0
  ## Uses non-blocking async pattern to avoid freezing the UI
  if not e.lsp.enabled:
    return

  if not e.config.lsp.signatureHelp.enable:
    return

  if e.state.mode != EditorMode.Insert:
    return

  let sigHelpMgr = e.handlerManager.insertHandler.signatureHelpManager
  if sigHelpMgr.parenDepth == 0 and not sigHelpMgr.isActive():
    return

  let activeBuffer = e.activeBuffer()

  # Check if there's a pending request - try to get response
  if e.state.lspCache.pendingSignatureHelpRequestId != 0:
    let (status, resultOpt, errorOpt) =
      e.lsp.checkResponse(e.state.lspCache.pendingSignatureHelpRequestId)
    case status
    of lrsPending:
      # Still waiting for response, don't start a new request
      return
    of lrsSuccess:
      # Got response, process it
      e.state.lspCache.pendingSignatureHelpRequestId = 0
      e.state.lspCache.signatureHelp.consecutiveErrors = 0
      if resultOpt.isSome:
        let sigHelpOpt = parseSignatureHelpResponse(resultOpt.get)
        if sigHelpOpt.isSome:
          sigHelpMgr.show(
            sigHelpOpt.get, e.activeWindow.cursor.line, e.activeWindow.cursor.column
          )
        else:
          if sigHelpMgr.parenDepth == 0:
            sigHelpMgr.hide()
      # Fall through to re-check below; change detection prevents re-requesting
      # the same position, so this won't spin on an idle cursor.
    of lrsError, lrsTimeout:
      # Request failed or timed out. Invalidate tracking so the next eligible
      # frame retries instead of being suppressed by change detection, and bump
      # the failure counter so the retry cadence backs off (see
      # shouldRequestSignatureHelp). Log only the first failure of a streak so a
      # persistently failing server does not flood the LSP log on every retry.
      if e.state.lspCache.signatureHelp.consecutiveErrors == 0:
        logLspDegraded("Signature help", status, errorOpt.get(""))
      e.state.lspCache.pendingSignatureHelpRequestId = 0
      e.state.lspCache.signatureHelp.changeSeq = -1
      inc e.state.lspCache.signatureHelp.consecutiveErrors
      return

  # Skip re-requesting when nothing changed (change detection) or while still
  # inside the debounce window. Without this the success branch above would
  # re-request every poll cycle while the cursor sits inside parens.
  let now = getMonoTime()
  if not shouldRequestSignatureHelp(
    e.state.lspCache.signatureHelp, e.activeWindow.cursor.line,
    e.activeWindow.cursor.column, activeBuffer.changeSeq, now,
  ):
    return

  if not e.lsp.hasSignatureHelpSupport(activeBuffer):
    # Gate new requests on server capability. Placed here (not earlier) so a
    # pending response is still drained above even when the server lacks the
    # capability; only the fresh request is suppressed.
    return

  # Start a new request and record the position it was issued for.
  let reqResult = e.lsp.startSignatureHelpRequest(
    activeBuffer, e.activeWindow.cursor.line, e.activeWindow.cursor.column
  )
  if reqResult.isOk:
    e.state.lspCache.pendingSignatureHelpRequestId = reqResult.get
    e.state.lspCache.signatureHelp.cursorLine = e.activeWindow.cursor.line
    e.state.lspCache.signatureHelp.cursorColumn = e.activeWindow.cursor.column
    e.state.lspCache.signatureHelp.changeSeq = activeBuffer.changeSeq
    e.state.lspCache.signatureHelp.lastUpdate = now
