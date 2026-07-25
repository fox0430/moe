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

## Shared LSP request-context helpers.

import std/[monotimes, options, tables]

import pkg/results

import types/editor_types, lsp_integration

proc cancelPendingRequest*(
    lsp: LspIntegration, cache: var LspCacheState, feature: LspRequestFeature
) =
  ## Drop the pending ctx for `feature` and cancel the LSP request if in flight.
  ## Cache-scoped so `invalidateXxxCache` can call it without `Editor`.
  if cache.pending.hasKey(feature):
    let ctx = cache.pending[feature]
    if ctx.requestId != 0:
      lsp.cancelRequest(ctx.requestId)
    cache.pending.del(feature)

proc cancelIfPending*(e: Editor, feature: LspRequestFeature) =
  cancelPendingRequest(e.lsp, e.state.lspCache, feature)

proc classifyResponse*(e: Editor, ctx: LspRequestContext): LspResponseState =
  ## Route the response according to whether the world we sent it against
  ## still matches:
  ## - lrsOverlay: an overlay (Command/Search/Rename) owns the screen. Overlays
  ##   leave `e.state.mode` intact, so they slip past validModes; a response
  ##   that pops up, switches mode or jumps would paint over the prompt.
  ##   Checked first so it also covers item-driven contexts.
  ## - lrsGone: origin buffer was closed, OR the active buffer switched away
  ##   (response for buffer A would be applied to now-active buffer B). Every
  ##   response handler down-stream reads `e.activeBuffer`, so a mid-flight
  ##   buffer switch must drop even when the origin buffer is still open.
  ## - lrsStale: origin buffer was edited since the request was sent.
  ## - lrsHijack: current mode is outside the request's validModes set.
  ## Item-driven contexts (ctx.isItemDriven == true) skip the buffer/version
  ## guard entirely — they target an LSP item, not the active buffer — and
  ## report lrsFresh unless a mode-hijack applies. Their callers own the
  ## semantic guard.
  if ctx.blockedByOverlay and e.state.overlay.isSome:
    return lrsOverlay
  if ctx.isItemDriven:
    if ctx.validModes.card > 0 and e.state.mode notin ctx.validModes:
      return lrsHijack
    return lrsFresh
  let bufOpt = e.bufferById(ctx.bufferId)
  if bufOpt.isNone:
    return lrsGone
  if e.activeBuffer.isNil or e.activeBuffer.id != ctx.bufferId:
    return lrsGone
  if not ctx.ignoreContentVersion and bufOpt.get.contentVersion != ctx.contentVersion:
    return lrsStale
  if ctx.validModes.card > 0 and e.state.mode notin ctx.validModes:
    return lrsHijack
  lrsFresh

proc storeContextualRequest*(
    cache: var LspCacheState,
    feature: LspRequestFeature,
    buffer: TextBuffer,
    requestId: int,
    validModes: set[EditorMode] = {},
    cursor: Option[BufferPosition] = none(BufferPosition),
    isItemDriven: bool = false,
    ignoreContentVersion: bool = false,
    blockedByOverlay: bool = true,
): LspRequestContext {.discardable.} =
  ## Cache-scoped ctx builder for call sites without an Editor (insert handler,
  ## item-driven flows). The request must already be in flight; the caller is
  ## responsible for cancelling any prior pending entry for this feature.
  ##
  ## `featureGeneration` is NOT bumped here. The counter's sole consumer is
  ## codeLens' async processCodeLensResponse handler, which needs the bump to
  ## fire only when a newer *response* has been dispatched — not on every
  ## request start. Bumping on start would guarantee the fall-through
  ## `doUpdate` in the same poll cycle invalidates the just-spawned handler,
  ## dropping the response on slow servers. The response-processing site owns
  ## the increment.
  let ctx = LspRequestContext(
    requestId: requestId,
    feature: feature,
    bufferId:
      if buffer.isNil:
        BufferId(0)
      else:
        buffer.id,
    contentVersion: if buffer.isNil: 0 else: buffer.contentVersion,
    path: if buffer.isNil or buffer.filePath.isNone: "" else: buffer.filePath.get,
    generation: cache.featureGeneration[feature],
    cursorLine: if cursor.isSome: cursor.get.line else: -1,
    cursorCol: if cursor.isSome: cursor.get.column else: -1,
    validModes: validModes,
    isItemDriven: isItemDriven,
    ignoreContentVersion: ignoreContentVersion,
    blockedByOverlay: blockedByOverlay,
  )
  cache.pending[feature] = ctx
  ctx

template pollOneShotLspResponse*(
    e: Editor, features: set[LspRequestFeature], label: string, onFresh: untyped
) =
  ## Shared skeleton for the one-shot (request -> single response -> apply)
  ## pollers driven from tickLsp: pick the pending feature, read its response,
  ## drop it from the pending table and route it through `classifyResponse`.
  ##
  ## `onFresh` runs only for a response that survives the guard and sees the
  ## injected `ctx`, `feature` and `resultOpt`. `features` may hold several
  ## entries for multi-stage flows (goto-*, call hierarchy); the lowest pending
  ## one wins, matching the enum order.
  ##
  ## Errors and timeouts surface as "LSP <label> failed/timed out". Features
  ## needing a different reaction keep their own poller.
  block lspPoll:
    if not e.lsp.enabled:
      break lspPoll

    var feature {.inject.} = low(LspRequestFeature)
    var found = false
    for f in features:
      if e.state.lspCache.pending.hasKey(f):
        feature = f
        found = true
        break
    if not found:
      break lspPoll

    let ctx {.inject.} = e.state.lspCache.pending[feature]

    # Responses were already polled at the top of tick(); this only reads them.
    let response = e.lsp.checkResponse(ctx.requestId)
    let resultOpt {.inject.} = response.result

    case response.status
    of lrsPending:
      discard # Still waiting
    of lrsSuccess:
      e.state.lspCache.pending.del(feature)
      if classifyResponse(e, ctx) != lrsFresh:
        break lspPoll
      onFresh
    of lrsError:
      e.state.lspCache.pending.del(feature)
      if response.error.isSome:
        e.state.statusMessage = "LSP " & label & " failed: " & response.error.get
    of lrsTimeout:
      e.state.lspCache.pending.del(feature)
      e.state.statusMessage = "LSP " & label & " timed out"

template pollDebouncedLspResponse*(
    e: Editor,
    feature: LspRequestFeature,
    poll: ptr DebouncedLspPoll,
    label: string,
    onFresh: untyped,
    onReject: untyped,
) =
  ## Shared skeleton for the debounced cache pollers (code lens, document
  ## highlight, inlay hints): drain a pending response, then fall through to
  ## the caller's own cache-validity check and debounce gate.
  ##
  ## `onFresh` sees the injected `ctx` and `resultOpt` and runs only for a
  ## response that survives `classifyResponse`; `onReject` runs on error or
  ## timeout, after the reject streak and the debounce timer are advanced.
  ##
  ## A still-pending request, or one the guard drops, returns from the calling
  ## proc: no new request may start while one is in flight, and a dropped
  ## response advances the debounce timer so churn (edit, buffer switch) does
  ## not immediately re-fire on the next tick.
  if e.state.lspCache.pending.hasKey(feature):
    let ctx {.inject.} = e.state.lspCache.pending[feature]

    # Responses were already polled at the top of tick(); this only reads them.
    let response = e.lsp.checkResponse(ctx.requestId)
    let resultOpt {.inject.} = response.result

    case response.status
    of lrsPending:
      return # Still waiting; don't start a new request
    of lrsSuccess:
      e.state.lspCache.pending.del(feature)
      if classifyResponse(e, ctx) != lrsFresh:
        poll.lastUpdate = getMonoTime()
        return
      onFresh
    of lrsError, lrsTimeout:
      logLspDegraded(label, response.status, response.error.get(""))
      e.state.lspCache.pending.del(feature)
      inc poll.rejectStreak
      poll.lastUpdate = getMonoTime()
      onReject

proc startContextualRequestOnCache*(
    lsp: LspIntegration,
    cache: var LspCacheState,
    feature: LspRequestFeature,
    buffer: TextBuffer,
    startImpl: proc(): Result[int, string],
    validModes: set[EditorMode] = {},
    cursor: Option[BufferPosition] = none(BufferPosition),
    ignoreContentVersion: bool = false,
    isItemDriven: bool = false,
    blockedByOverlay: bool = true,
): Result[LspRequestContext, string] =
  ## Cache-scoped counterpart of `startContextualRequest` for call sites
  ## without an `Editor` (e.g. insert handler). Preserves the prior pending
  ## entry when `startImpl` errors so a transient failure does not destroy a
  ## good in-flight response.
  # Flush pending didChange first so this request doesn't precede the edit
  # that produced its coordinates on the wire (shared FIFO, per-frame flush).
  if not buffer.isNil:
    lsp.flushPendingBufferChange(buffer)
  let reqRes = startImpl()
  if reqRes.isErr:
    return err(reqRes.error)
  cancelPendingRequest(lsp, cache, feature)
  ok(
    storeContextualRequest(
      cache,
      feature,
      buffer,
      reqRes.get,
      validModes,
      cursor,
      isItemDriven = isItemDriven,
      ignoreContentVersion = ignoreContentVersion,
      blockedByOverlay = blockedByOverlay,
    )
  )

proc startContextualRequest*(
    e: Editor,
    feature: LspRequestFeature,
    startImpl: proc(): Result[int, string],
    validModes: set[EditorMode] = {},
    cursor: Option[BufferPosition] = none(BufferPosition),
    ignoreContentVersion: bool = false,
    isItemDriven: bool = false,
    blockedByOverlay: bool = true,
): Result[LspRequestContext, string] =
  ## Fire the LSP request via `startImpl` and, on success, cancel any prior
  ## pending entry and record the new ctx. On failure the prior in-flight is
  ## preserved — a transient `startImpl` error (worker restart, transport
  ## hiccup) must not destroy a good in-flight response.
  let buf = e.activeBuffer
  if buf.isNil or buf.filePath.isNone:
    return err("no active file")
  startContextualRequestOnCache(
    e.lsp,
    e.state.lspCache,
    feature,
    buf,
    startImpl,
    validModes,
    cursor,
    ignoreContentVersion = ignoreContentVersion,
    isItemDriven = isItemDriven,
    blockedByOverlay = blockedByOverlay,
  )
