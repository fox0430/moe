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

import std/[options, monotimes, tables]

import pkg/results

import types/editor_types, editor_lsp, lsp_integration, signature_help

const SignatureHelpValidModes* = {EditorMode.Insert}

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
  if e.state.lspCache.pending.hasKey(lrfSignatureHelp):
    let ctx = e.state.lspCache.pending[lrfSignatureHelp]
    let (status, resultOpt, errorOpt) = e.lsp.checkResponse(ctx.requestId)
    case status
    of lrsPending:
      # Still waiting for response, don't start a new request
      return
    of lrsSuccess:
      # Got response, process it
      e.state.lspCache.pending.del(lrfSignatureHelp)
      e.state.lspCache.signatureHelpPoll.rejectStreak = 0
      # Drop stale reply (buffer switched / edited / left Insert). The debounce
      # fields still record the tried position so change detection stays honest.
      if classifyResponse(e, ctx) != lrsFresh:
        return
      if resultOpt.isSome:
        let sigHelpOpt = parseSignatureHelpResponse(resultOpt.get)
        if sigHelpOpt.isSome:
          # Use request-issue position — cursor may have moved while in flight.
          sigHelpMgr.show(sigHelpOpt.get, ctx.cursorLine, ctx.cursorCol)
        else:
          if sigHelpMgr.parenDepth == 0:
            sigHelpMgr.hide()
      # Fall through to re-check below; change detection prevents re-requesting
      # the same position, so this won't spin on an idle cursor.
    of lrsError, lrsTimeout:
      # Request failed or timed out. Invalidate tracking so the next eligible
      # frame retries instead of being suppressed by change detection, and bump
      # the reject streak so the retry cadence backs off (see
      # shouldFireDebouncedPoll). Log only the first failure of a streak so a
      # persistently failing server does not flood the LSP log on every retry.
      if e.state.lspCache.signatureHelpPoll.rejectStreak == 0:
        logLspDegraded("Signature help", status, errorOpt.get(""))
      e.state.lspCache.pending.del(lrfSignatureHelp)
      e.state.lspCache.signatureHelpPoll.contentVersion = -1
      inc e.state.lspCache.signatureHelpPoll.rejectStreak
      return

  # Skip re-requesting when nothing changed (change detection) or while still
  # inside the debounce window. Without this the success branch above would
  # re-request every poll cycle while the cursor sits inside parens.
  let now = getMonoTime()
  if not e.state.lspCache.signatureHelpPoll.shouldFireDebouncedPoll(
    e.activeWindow.cursor.line, e.activeWindow.cursor.column,
    activeBuffer.contentVersion, now,
  ):
    return

  if not e.lsp.hasSignatureHelpSupport(activeBuffer):
    # Gate new requests on server capability. Placed here (not earlier) so a
    # pending response is still drained above even when the server lacks the
    # capability; only the fresh request is suppressed.
    return

  # Start a new request and record the position it was issued for.
  let line = e.activeWindow.cursor.line
  let col = e.activeWindow.cursor.column
  let ctxRes = e.startContextualRequest(
    lrfSignatureHelp,
    proc(): Result[int, string] =
      e.lsp.startSignatureHelpRequest(activeBuffer, line, col),
    validModes = SignatureHelpValidModes,
    cursor = some(BufferPosition(line: line, column: col)),
    ignoreContentVersion = true,
  )
  if ctxRes.isOk:
    e.state.lspCache.signatureHelpPoll.markRequestIssued(
      line, col, activeBuffer.contentVersion, now
    )
