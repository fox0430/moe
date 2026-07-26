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

## Tests for editor_signaturehelp.nim

import std/[unittest, monotimes, times, options, tables, json, importutils]

import ../src/moepkg/[editor, config, config_loader, lsp_service, signature_help]
import ../src/moepkg/editor_signaturehelp
import ../src/moepkg/types/editor_types

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc createTestEditorWithLspDisabled(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)
  result.lsp.enabled = false

suite "editor_signaturehelp - requestSignatureHelpFromLsp":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()
    e.state.mode = EditorMode.Insert

    e.requestSignatureHelpFromLsp()

    check not e.state.lspCache.pending.hasKey(lrfSignatureHelp)

  test "Does nothing when not in Insert mode":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.mode = EditorMode.Normal

    e.requestSignatureHelpFromLsp()

    check not e.state.lspCache.pending.hasKey(lrfSignatureHelp)

  test "Does nothing when outside parens and popup inactive":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.mode = EditorMode.Insert
    # parenDepth defaults to 0 and the manager is inactive -> gated out
    e.requestSignatureHelpFromLsp()

    check not e.state.lspCache.pending.hasKey(lrfSignatureHelp)

  test "Does nothing when signatureHelp.enable is false":
    # Even with an otherwise-eligible state (LSP on, Insert mode, inside parens),
    # the lsp.signatureHelp.enable gate must suppress the request.
    let e = createTestEditor()
    e.lsp.enabled = true
    e.config.lsp.signatureHelp.enable = false
    e.state.mode = EditorMode.Insert
    e.handlerManager.insertHandler.signatureHelpManager.parenDepth = 1

    e.requestSignatureHelpFromLsp()

    check not e.state.lspCache.pending.hasKey(lrfSignatureHelp)

  test "Timed-out response clears pending and invalidates change tracking":
    # A timed-out in-flight request must reset the tracked contentVersion so the
    # next eligible frame can retry instead of being suppressed by change
    # detection.
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.mode = EditorMode.Insert
    e.handlerManager.insertHandler.signatureHelpManager.parenDepth = 1

    const reqId = 4242
    e.state.lspCache.pending[lrfSignatureHelp] = LspRequestContext(
      requestId: reqId,
      feature: lrfSignatureHelp,
      bufferId: e.activeBuffer.id,
      contentVersion: e.activeBuffer.contentVersion,
    )
    e.state.lspCache.signatureHelpPoll.cursorLine = 3
    e.state.lspCache.signatureHelpPoll.cursorColumn = 5
    e.state.lspCache.signatureHelpPoll.contentVersion = 7

    # Inject an already-expired in-flight request so checkResponse -> lrsTimeout
    e.lsp.service.activeRequests[reqId] = LspPendingRequest(
      requestId: reqId,
      langId: "",
      methodName: "textDocument/signatureHelp",
      startTime: 0.0,
      timeoutMs: 1,
    )

    e.requestSignatureHelpFromLsp()

    check not e.state.lspCache.pending.hasKey(lrfSignatureHelp)
    check e.state.lspCache.signatureHelpPoll.contentVersion == -1
    # The failure must bump the backoff counter so retries slow down.
    check e.state.lspCache.signatureHelpPoll.rejectStreak == 1

  test "Successful response shows popup, clears pending and resets backoff":
    # Guards the post-success fall-through: the response is still applied (popup
    # shown), the pending id is cleared, and the failure backoff is reset. The
    # tracked position matches the cursor so the fall-through is gated out by
    # change detection rather than spinning a fresh request.
    privateAccess(LspService)
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.mode = EditorMode.Insert
    let mgr = e.handlerManager.insertHandler.signatureHelpManager
    mgr.parenDepth = 1

    const reqId = 99
    e.state.lspCache.pending[lrfSignatureHelp] = LspRequestContext(
      requestId: reqId,
      feature: lrfSignatureHelp,
      bufferId: e.activeBuffer.id,
      contentVersion: e.activeBuffer.contentVersion,
      validModes: {EditorMode.Insert},
    )
    e.state.lspCache.signatureHelpPoll.rejectStreak = 3
    e.state.lspCache.signatureHelpPoll.cursorLine = e.activeWindow.cursor.line
    e.state.lspCache.signatureHelpPoll.cursorColumn = e.activeWindow.cursor.column
    e.state.lspCache.signatureHelpPoll.contentVersion = e.activeBuffer.contentVersion

    e.lsp.service.pendingResponses[reqId] = (
      result: some(
        $(
          %*{
            "signatures": [{"label": "foo(a: int, b: int)"}],
            "activeSignature": 0,
            "activeParameter": 0,
          }
        )
      ),
      error: none(string),
    )

    e.requestSignatureHelpFromLsp()

    check not e.state.lspCache.pending.hasKey(lrfSignatureHelp)
    check mgr.isActive()
    check e.state.lspCache.signatureHelpPoll.rejectStreak == 0

suite "editor_signaturehelp - shouldFireDebouncedPoll":
  # Decision logic for the auto request path: change detection + debounce.
  let t0 = getMonoTime()
  let tracked = DebouncedLspPoll(
    lastUpdate: t0, interval: 100, cursorLine: 5, cursorColumn: 10, contentVersion: 3
  )

  test "Skips when cursor and contentVersion are unchanged (even past debounce)":
    check not shouldFireDebouncedPoll(
      tracked, 5, 10, 3, t0 + initDuration(seconds = 10)
    )

  test "Requests when cursor line changed and debounce elapsed":
    check shouldFireDebouncedPoll(
      tracked, 6, 10, 3, t0 + initDuration(milliseconds = 150)
    )

  test "Requests when cursor column changed and debounce elapsed":
    check shouldFireDebouncedPoll(
      tracked, 5, 11, 3, t0 + initDuration(milliseconds = 150)
    )

  test "Requests when contentVersion changed and debounce elapsed":
    check shouldFireDebouncedPoll(
      tracked, 5, 10, 4, t0 + initDuration(milliseconds = 150)
    )

  test "Suppresses changed position while inside the debounce window":
    check not shouldFireDebouncedPoll(
      tracked, 6, 10, 3, t0 + initDuration(milliseconds = 50)
    )

  test "Fires exactly at the debounce boundary (elapsed == interval)":
    check shouldFireDebouncedPoll(
      tracked, 6, 10, 3, t0 + initDuration(milliseconds = 100)
    )

  test "Invalidated tracking (contentVersion -1) re-requests once debounce elapses":
    let invalidated = DebouncedLspPoll(
      lastUpdate: t0, interval: 100, cursorLine: 5, cursorColumn: 10, contentVersion: -1
    )
    check shouldFireDebouncedPoll(
      invalidated, 5, 10, 3, t0 + initDuration(milliseconds = 150)
    )

  test "Backoff: one prior error doubles the debounce window":
    let onceFailed = DebouncedLspPoll(
      lastUpdate: t0,
      interval: 100,
      cursorLine: 5,
      cursorColumn: 10,
      contentVersion: 3,
      rejectStreak: 1,
    )
    # 150ms would fire at the base interval, but the doubled window suppresses it.
    check not shouldFireDebouncedPoll(
      onceFailed, 6, 10, 3, t0 + initDuration(milliseconds = 150)
    )
    # Fires once the doubled (200ms) window elapses.
    check shouldFireDebouncedPoll(
      onceFailed, 6, 10, 3, t0 + initDuration(milliseconds = 200)
    )

  test "Backoff is capped at 64x the base interval":
    let manyFailed = DebouncedLspPoll(
      lastUpdate: t0,
      interval: 100,
      cursorLine: 5,
      cursorColumn: 10,
      contentVersion: 3,
      rejectStreak: 99,
    )
    # Still suppressed just before the 64x (6400ms) cap ...
    check not shouldFireDebouncedPoll(
      manyFailed, 6, 10, 3, t0 + initDuration(milliseconds = 6399)
    )
    # ... and fires at the cap rather than growing further.
    check shouldFireDebouncedPoll(
      manyFailed, 6, 10, 3, t0 + initDuration(milliseconds = 6400)
    )

  test "Undo-collision on changeSeq: contentVersion advance still fires":
    # After undo() rewinds changeSeq to a previously-tracked value and a new
    # edit lands on that same changeSeq with different content, the tracker
    # (keyed on contentVersion, not changeSeq) must see the change and permit
    # a fresh request. Regression against the pre-fix state where the same
    # numeric key would suppress the request.
    let cursorLine = 5
    let cursorColumn = 10
    let cachedContentVersion = 42
    let debounced = DebouncedLspPoll(
      lastUpdate: t0,
      interval: 100,
      cursorLine: cursorLine,
      cursorColumn: cursorColumn,
      contentVersion: cachedContentVersion,
    )
    # A new contentVersion (post undo+edit) at the same cursor position must
    # not be suppressed by change detection.
    check shouldFireDebouncedPoll(
      debounced,
      cursorLine,
      cursorColumn,
      cachedContentVersion + 1,
      t0 + initDuration(milliseconds = 150),
    )
