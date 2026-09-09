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

## Tests for LspRequestContext / classifyResponse (docs §10 Phase A).

import std/[options, os, tables, unittest]
from std/strutils import contains
import std/importutils

import pkg/results

import ../src/moepkg/[editor, config, config_loader, modes, types]
import ../src/moepkg/buffer/core
import ../src/moepkg/buffer
import ../src/moepkg/editor_lsp
import ../src/moepkg/lsp_integration {.all.}

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc makeCtx(
    bufId: BufferId,
    contentVersion: int,
    validModes: set[EditorMode] = {},
    isItemDriven: bool = false,
    blockedByOverlay: bool = false,
): LspRequestContext =
  LspRequestContext(
    requestId: 1,
    feature: lrfHover,
    bufferId: bufId,
    contentVersion: contentVersion,
    path: getTempDir() / "dummy.nim",
    generation: 1,
    cursorLine: -1,
    cursorCol: -1,
    validModes: validModes,
    isItemDriven: isItemDriven,
    blockedByOverlay: blockedByOverlay,
  )

suite "classifyResponse":
  test "lrsFresh when buffer/version match and no mode restriction":
    let e = createTestEditor()
    let buf = e.activeBuffer
    let ctx = makeCtx(buf.id, buf.contentVersion)

    check classifyResponse(e, ctx) == lrsFresh

  test "lrsStale when contentVersion drifted since send":
    let e = createTestEditor()
    let buf = e.activeBuffer
    let ctx = makeCtx(buf.id, buf.contentVersion - 1)

    check classifyResponse(e, ctx) == lrsStale

  test "lrsGone when bufferId is not in the buffer index":
    let e = createTestEditor()
    # BufferId(0) is the reserved unassigned sentinel; genBufferId starts at 1,
    # so this id can never be a live buffer.
    let ctx = makeCtx(BufferId(0), 0)

    check classifyResponse(e, ctx) == lrsGone

  test "lrsHijack when current mode is outside validModes":
    let e = createTestEditor()
    let buf = e.activeBuffer
    # New editor is in Normal; require Insert -> mode drift.
    let ctx = makeCtx(buf.id, buf.contentVersion, validModes = {EditorMode.Insert})

    check classifyResponse(e, ctx) == lrsHijack

  test "lrsFresh when current mode is inside validModes":
    let e = createTestEditor()
    let buf = e.activeBuffer
    let ctx = makeCtx(buf.id, buf.contentVersion, validModes = {EditorMode.Normal})

    check classifyResponse(e, ctx) == lrsFresh

  test "gone takes precedence over stale":
    let e = createTestEditor()
    # Unknown buffer + mismatched version -> still classified as gone.
    let ctx = makeCtx(BufferId(0), 999)

    check classifyResponse(e, ctx) == lrsGone

  test "stale takes precedence over hijack":
    let e = createTestEditor()
    let buf = e.activeBuffer
    let ctx = makeCtx(buf.id, buf.contentVersion - 1, validModes = {EditorMode.Insert})

    check classifyResponse(e, ctx) == lrsStale

  test "Item-driven ctx: bypasses buffer/version guard, still honors validModes":
    let e = createTestEditor()
    # Stale contentVersion + unknown bufferId, but isItemDriven=true → lrsFresh.
    let ctx =
      makeCtx(BufferId(0), -1, validModes = {EditorMode.Normal}, isItemDriven = true)
    check classifyResponse(e, ctx) == lrsFresh

    # Mode outside validModes → lrsHijack even for item-driven.
    let ctxHijack =
      makeCtx(BufferId(0), -1, validModes = {EditorMode.Insert}, isItemDriven = true)
    check classifyResponse(e, ctxHijack) == lrsHijack

  test "lrsGone when the active buffer switched to a different open buffer":
    # Regression: the pre-refactor per-feature guard compared active.filePath
    # to the pending path. classifyResponse must reject the mid-flight
    # buffer-switch case, otherwise A's response would be applied against B.
    let e = createTestEditor()
    let origin = e.activeBuffer
    # Open a second buffer and make it active.
    let other = newTextBuffer("", some(getTempDir() / "other.nim"))
    e.addBuffer(other)
    e.activeWindow.buffer = other
    check e.activeBuffer.id != origin.id

    # ctx points at the still-open origin buffer but is no longer the active.
    let ctx = makeCtx(origin.id, origin.contentVersion)

    check classifyResponse(e, ctx) == lrsGone

suite "classifyResponse - overlay dimension":
  test "lrsOverlay when an overlay is active and the ctx is overlay-blocked":
    # Overlays leave e.state.mode intact, so validModes cannot catch them.
    let e = createTestEditor()
    let buf = e.activeBuffer
    let ctx = makeCtx(buf.id, buf.contentVersion, blockedByOverlay = true)
    check classifyResponse(e, ctx) == lrsFresh

    e.state.enterCommandOverlay()
    check classifyResponse(e, ctx) == lrsOverlay

  test "Background-cache ctx (blockedByOverlay=false) still applies under an overlay":
    # Caches feed the buffer painted beneath the overlay, so they must not drop.
    let e = createTestEditor()
    let buf = e.activeBuffer
    e.state.enterCommandOverlay()
    let ctx = makeCtx(buf.id, buf.contentVersion, blockedByOverlay = false)

    check classifyResponse(e, ctx) == lrsFresh

  test "Overlay outranks the item-driven bypass":
    # Item-driven contexts skip the buffer/version guard, but a goto/call
    # hierarchy response would still hijack the overlay's prompt.
    let e = createTestEditor()
    e.state.enterCommandOverlay()
    let ctx = makeCtx(BufferId(0), -1, isItemDriven = true, blockedByOverlay = true)

    check classifyResponse(e, ctx) == lrsOverlay

suite "startContextualRequest - pre-request sync":
  test "A stale document refuses the request instead of asking about text the server lacks":
    # Stale sync refuses; server would answer about unseen text.
    let e = createTestEditor()
    defer:
      e.lsp.shutdown()
    e.lsp.enabled = true

    let buf = e.activeBuffer
    # No reachable worker, so didChange has nowhere to go.
    let path = getTempDir() / "sync_refused.nim"
    e.lsp.service.liveWorkerOverride = proc(p: string): bool =
      false
    buf.filePath = some(path)
    e.lsp.documents[canonicalPath(path)] = initLspDocumentState(1, "", delivered = true)
    check buf.insertText(BufferPosition(line: 0, column: 0), "a").isOk

    var started = false
    let ctxRes = e.startContextualRequest(
      lrfDefinition,
      proc(): Result[int, string] =
        started = true
        ok(1),
    )

    check not started
    check ctxRes.isErr
    # Refusal names the absent server.
    check "no running language server" in ctxRes.error

  test "A decorating feature asks anyway rather than showing nothing":
    # Decorating feature tolerates stale text over showing nothing.
    let e = createTestEditor()
    defer:
      e.lsp.shutdown()
    e.lsp.enabled = true

    let buf = e.activeBuffer
    let path = getTempDir() / "sync_tolerated.nim"
    e.lsp.service.liveWorkerOverride = proc(p: string): bool =
      false
    buf.filePath = some(path)
    e.lsp.documents[canonicalPath(path)] = initLspDocumentState(1, "", delivered = true)
    check buf.insertText(BufferPosition(line: 0, column: 0), "a").isOk

    var started = false
    let ctxRes = e.startContextualRequest(
      lrfSemanticTokens,
      proc(): Result[int, string] =
        started = true
        ok(1),
    )

    check started
    check ctxRes.isOk

  test "A timer-driven request does not respawn a crashed server on start":
    # Timer request must not respawn a crash-looping server.
    privateAccess(LspService)
    let e = createTestEditor()
    defer:
      e.lsp.shutdown()
    e.lsp.enabled = true
    # Service must stay enabled to observe the respawn.
    e.lsp.service.enabled = true

    let buf = e.activeBuffer
    let path = getTempDir() / "no_respawn.nim"
    e.lsp.service.liveWorkerOverride = proc(p: string): bool =
      false
    e.lsp.service.runningWorkerOverride = proc(p: string): bool =
      false
    buf.filePath = some(path)

    let ctxRes = e.startContextualRequest(
      lrfCodeLens,
      proc(): Result[int, string] =
        e.lsp.startCodeLensRequest(buf),
    )

    check ctxRes.isErr
    check "nim" notin e.lsp.service.workers

  test "Every feature is classified, and the destructive ones refuse":
    # Default is safe: wait for the server.
    check lrfDefinition.staleTolerance == lstRefuse
    check lrfReferences.staleTolerance == lstRefuse
    check lrfCompletion.staleTolerance == lstRefuse
    check lrfCompletionResolve.staleTolerance == lstRefuse
    check lrfDocumentSymbol.staleTolerance == lstRefuse
    check lrfSelectionRange.staleTolerance == lstRefuse
    check lrfInlayHint.staleTolerance == lstTolerate
    check lrfCodeLens.staleTolerance == lstTolerate
    check lrfDocumentHighlight.staleTolerance == lstTolerate
    check lrfSemanticTokens.staleTolerance == lstTolerate
    # Popups tolerate stale text.
    check lrfHover.staleTolerance == lstTolerate
    check lrfSignatureHelp.staleTolerance == lstTolerate

  test "A request kind reached without a pending context shares the table":
    # Context-less requests share the same policy.
    check lrfFormatting.staleTolerance == lstRefuse
    check lrfRename.staleTolerance == lstRefuse
    check lrfExecuteCommand.staleTolerance == lstRefuse
    check lrfCodeLensResolve.staleTolerance == lrfCodeLens.staleTolerance
    # Links and folds refuse; they act on stale positions.
    check lrfFoldingRange.staleTolerance == lstRefuse
    check lrfDocumentLink.staleTolerance == lstRefuse
    check lrfDocumentLinkResolve.staleTolerance == lstRefuse
    # Completion refuses; it inserts at server coordinates.
    check lrfCompletion.staleTolerance == lstRefuse

  test "Every LspRequestFeature carries an explicit stale policy":
    # Exhaustive guard for new variants.
    const tolerated = {
      lrfHover, lrfSignatureHelp, lrfCodeLens, lrfCodeLensResolve, lrfInlayHint,
      lrfDocumentHighlight, lrfSemanticTokens,
    }
    var seen = 0
    for feature in LspRequestFeature:
      inc seen
      if feature in tolerated:
        check feature.staleTolerance == lstTolerate
      else:
        check feature.staleTolerance == lstRefuse
    check tolerated.len == 7
    check seen == 26
