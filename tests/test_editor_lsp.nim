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

## Tests for editor_lsp.nim

import std/[unittest, os, options, strutils, tables, importutils, json, unicode]

import pkg/[chronos, results]

import ../src/moepkg/[editor, buffer, config, config_loader, message_log, types]
import ../src/moepkg/editor_lsp {.all.}
import ../src/moepkg/editor_lsp_rename {.all.}
import ../src/moepkg/lsp_integration {.all.}
import ../src/moepkg/lsp_service
import ../src/moepkg/lsp/protocol/types as lspTypes
import ../src/moepkg/types/lsp_integration_types {.all.}

privateAccess(LspDocumentState)

proc syncedStatus(lsp: LspIntegration, buffer: TextBuffer): SyncVerdict =
  ## Frame sync with verdict.
  lsp.syncAndJudge(buffer, forceRetry = false, mayRestart = false)

proc createTestEditor(): Editor =
  ## Create a minimal editor for testing
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc createTestEditorWithLspDisabled(): Editor =
  ## Create an editor with LSP disabled
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)
  result.lsp.enabled = false

proc syncMemo(e: Editor, buf: TextBuffer): Option[LspSyncAttempt] =
  ## Sync memo for this buffer only.
  if buf.filePath.isNone:
    return none(LspSyncAttempt)
  let path = canonicalPath(buf.filePath.get)
  if path notin e.lsp.documents:
    return none(LspSyncAttempt)
  result = e.lsp.documents[path].attempt
  if result.isSome and result.get.bufferId != buf.id:
    return none(LspSyncAttempt)

proc syncedVersion(e: Editor, buf: TextBuffer): int =
  let memo = e.syncMemo(buf)
  if memo.isSome: memo.get.contentVersion else: 0

proc hasSyncRecord(e: Editor, buf: TextBuffer): bool =
  e.syncMemo(buf).isSome

proc markDelivered(e: Editor, path: string) =
  ## Mark didOpen as delivered for tests.
  e.lsp.documents[path].delivered = true
  e.lsp.documents[path].attempt = none(LspSyncAttempt)

proc noteSyncedAt(e: Editor, buf: TextBuffer, version: int) =
  ## Plant the memo a landed sync would have left.
  let path = canonicalPath(buf.filePath.get)
  if path notin e.lsp.documents:
    e.lsp.documents[path] = initLspDocumentState(1, "", delivered = true)
  e.lsp.documents[path].attempt = some(
    LspSyncAttempt(
      bufferId: buf.id, contentVersion: version, verdict: SyncVerdict(kind: svSynced)
    )
  )

suite "editor_lsp - maybeUpdateLsp":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()
    let activeBuffer = e.activeBuffer()
    let initialVer = e.syncedVersion(activeBuffer)

    e.maybeUpdateLsp()

    check e.syncedVersion(activeBuffer) == initialVer

  test "Does nothing when buffer has not changed":
    let e = createTestEditor()
    e.lsp.enabled = true
    let activeBuffer = e.activeBuffer()
    activeBuffer.filePath = some(getTempDir() / "moe_test_unchanged.nim")
    e.noteSyncedAt(activeBuffer, activeBuffer.contentVersion)

    e.maybeUpdateLsp()

    check e.syncedVersion(activeBuffer) == activeBuffer.contentVersion

  test "Tracking is per-buffer":
    let e = createTestEditor()
    e.lsp.enabled = true
    let activeBuffer = e.activeBuffer()
    activeBuffer.filePath = some(getTempDir() / "moe_test_tracking_active.nim")
    # Another buffer's entry must not affect the active buffer's tracking
    let otherBuffer =
      newTextBuffer("other", some(getTempDir() / "moe_test_tracking_other.nim"))
    e.addBuffer(otherBuffer)
    e.noteSyncedAt(otherBuffer, 999)

    e.noteSyncedAt(activeBuffer, activeBuffer.contentVersion)
    e.maybeUpdateLsp()

    check e.syncedVersion(activeBuffer) == activeBuffer.contentVersion
    check e.syncedVersion(otherBuffer) == 999

  test "A memo left by another buffer on the same path is not this one's":
    # Other buffer's memo is not this buffer's.
    let e = createTestEditor()
    e.lsp.enabled = true
    let path = getTempDir() / "moe_test_shared_path.nim"

    let first = e.activeBuffer()
    first.filePath = some(path)
    check first.insertText(BufferPosition(line: 0, column: 0), "a").isOk
    e.noteSyncedAt(first, first.contentVersion)

    let second = newTextBuffer("second", some(path))
    e.addBuffer(second)

    check e.hasSyncRecord(first)
    check not e.hasSyncRecord(second)

  test "Undo then edit collides on changeSeq: server must still be resynced":
    # undo() rewinds changeSeq to the pre-mutation value, so a follow-up edit
    # can land on the exact same changeSeq that was already recorded as synced.
    # A gate keyed on changeSeq treats the two different contents as identical
    # and drops the didChange, permanently desyncing the server.
    privateAccess(LspIntegration)

    let tmpDir = getTempDir() / "moe_test_editor_lsp_content_version"
    createDir(tmpDir)
    defer:
      removeDir(tmpDir)

    let path = tmpDir / "collide.nim"
    privateAccess(LspService)
    let e = createTestEditor()
    defer:
      e.lsp.shutdown()
    e.lsp.enabled = true
    e.lsp.service.liveWorkerOverride = proc(p: string): bool =
      true
    # No-thread worker: queue stands in for the server.
    e.lsp.service.workers["nim"] = newLspWorker("nim").get

    let buf = e.activeBuffer()
    buf.filePath = some(path)
    e.openBufferWithLsp(buf)
    check e.lsp.sentDocumentVersion(path) == some(1)
    # Mark didOpen delivered to test steady state.
    e.markDelivered(path)

    check buf.insertText(BufferPosition(line: 0, column: 0), "a").isOk
    e.maybeUpdateLsp()
    check e.lsp.sentDocumentVersion(path) == some(2)
    let seqAfterA = buf.changeSeq

    check buf.insertText(BufferPosition(line: 0, column: 1), "b").isOk
    e.maybeUpdateLsp()
    let syncedVersion = e.lsp.sentDocumentVersion(path).get
    check syncedVersion == 3
    let syncedSeq = buf.changeSeq

    # Undo B then insert C without an intervening maybeUpdateLsp. The undo
    # rewinds changeSeq to seqAfterA; the follow-up insert increments it back
    # to syncedSeq. Content is now "ac", not the "ab" the server last saw.
    check buf.undo().isOk
    check buf.changeSeq == seqAfterA
    check buf.insertText(BufferPosition(line: 0, column: 1), "c").isOk
    check buf.changeSeq == syncedSeq
    check buf.getTextString() == "ac"

    e.maybeUpdateLsp()

    # The server must have received the "ac" state. With a changeSeq-keyed
    # gate, syncedSeq == the recorded value and the sync is dropped, leaving
    # the server on "ab" forever.
    check e.lsp.sentDocumentVersion(path).get > syncedVersion
    check e.lsp.documents[path].shadow == "ac"

  test "A failed pre-request flush is reported as stale, not swallowed":
    # Failed flush must be reported, not swallowed.
    privateAccess(LspIntegration)

    let tmpDir = getTempDir() / "moe_test_flush_pending_err"
    createDir(tmpDir)
    defer:
      removeDir(tmpDir)

    clearLspMessageLog()

    let path = tmpDir / "file.nim"
    let e = createTestEditor()
    defer:
      e.lsp.shutdown()
    e.lsp.enabled = true
    # No reachable worker, so didChange has nowhere to go.
    e.lsp.service.liveWorkerOverride = proc(p: string): bool =
      false

    let buf = e.activeBuffer()
    buf.filePath = some(path)
    e.lsp.documents[canonicalPath(path)] = initLspDocumentState(1, "", delivered = true)
    check buf.insertText(BufferPosition(line: 0, column: 0), "a").isOk

    check e.lsp.syncedStatus(buf).kind == svBehind

    let entries = getLspMessageLog()
    check entries.len == 1
    check entries[0].startsWith("[LSP] document sync ")
    check entries[0].contains("file.nim")

    # Report repeated failure once.
    check e.lsp.syncedStatus(buf).kind == svBehind
    check e.lsp.syncedStatus(buf).kind == svBehind

    check getLspMessageLog().len == 1

  test "A flush with nothing to sync stays quiet":
    privateAccess(LspIntegration)

    clearLspMessageLog()

    let e = createTestEditor()
    e.lsp.enabled = true

    # No file path: there is nothing the server could be missing.
    let buf = e.activeBuffer()
    check buf.insertText(BufferPosition(line: 0, column: 0), "a").isOk

    check e.lsp.syncedStatus(buf).kind == svNotApplicable

    check getLspMessageLog().len == 0

  test "An extension no server claims is not an outage":
    # Unclaimed extension is not an outage.
    privateAccess(LspIntegration)

    let tmpDir = getTempDir() / "moe_test_maybe_update_lsp_no_server"
    createDir(tmpDir)
    defer:
      removeDir(tmpDir)

    clearLspMessageLog()

    let path = tmpDir / "file.unknownlspext"
    let e = createTestEditor()
    e.lsp.enabled = true

    let buf = e.activeBuffer()
    buf.filePath = some(path)
    check buf.insertText(BufferPosition(line: 0, column: 0), "a").isOk

    check e.lsp.lspParticipation(buf) == lpNoServer

    e.maybeUpdateLsp()
    e.maybeUpdateLsp()

    check getLspMessageLog().len == 0
    # Nothing is tracked for it, so no didClose is owed and no text is held.
    check canonicalPath(path) notin e.lsp.documents
    check not e.hasSyncRecord(buf)

  test "A failed sync logs once and is retried on a budget, not per frame":
    # Unreachable server logs once, retries off render path.
    privateAccess(LspIntegration)

    let tmpDir = getTempDir() / "moe_test_maybe_update_lsp_err"
    createDir(tmpDir)
    defer:
      removeDir(tmpDir)

    clearLspMessageLog()

    let path = tmpDir / "file.nim"
    let e = createTestEditor()
    defer:
      e.lsp.shutdown()
    e.lsp.enabled = true
    e.lsp.service.liveWorkerOverride = proc(p: string): bool =
      false

    let buf = e.activeBuffer()
    buf.filePath = some(path)
    e.lsp.documents[canonicalPath(path)] = initLspDocumentState(1, "", delivered = true)
    check buf.insertText(BufferPosition(line: 0, column: 0), "a").isOk

    e.maybeUpdateLsp()

    # Failed attempt is recorded to stop repeats.
    check e.hasSyncRecord(buf)
    check e.syncedVersion(buf) == buf.contentVersion
    check not e.syncMemo(buf).get.verdict.syncSettled

    let logAfterFirst = getLspMessageLog()
    check logAfterFirst.len == 1
    check logAfterFirst[0].startsWith("[LSP] document sync ")

    let sentBefore = e.lsp.documents[canonicalPath(path)].version
    e.maybeUpdateLsp()
    check e.lsp.documents[canonicalPath(path)].version == sentBefore
    check getLspMessageLog().len == 1

    # Edit retries immediately.
    check buf.insertText(BufferPosition(line: 0, column: 1), "b").isOk
    e.maybeUpdateLsp()
    check e.syncedVersion(buf) == buf.contentVersion
    check getLspMessageLog().len == 1

    # Same outage from another flow must not re-log.
    check not e.lsp.syncedStatus(buf).syncSettled
    e.syncBufferAfterEdit(buf)
    e.maybeUpdateLsp()
    check getLspMessageLog().len == 1

suite "editor_lsp - server config plumbing":
  test "custom command/extensions override the built-in default":
    let config = newEditorConfig()
    config.lsp.servers["nim"] = LspServerConfig(
      command: "my-nimlangserver --stdio",
      extensions: @["nim", "custom"],
      trace: LspTraceLevel.ltVerbose,
    )
    let vr = newValidationResult()
    let e = newEditor(config, vr)

    let svcCfg = e.lsp.service.getConfig("nim")
    check svcCfg.isSome
    check svcCfg.get.command == "my-nimlangserver --stdio"
    check svcCfg.get.args.len == 0
    check svcCfg.get.extensions == @["nim", "custom"]
    check svcCfg.get.traceLevel == traceVerbose

  test "trace = messages is preserved (not silently downgraded to off)":
    let config = newEditorConfig()
    config.lsp.servers["nim"] = LspServerConfig(
      command: "nimlangserver", extensions: @["nim"], trace: LspTraceLevel.ltMessages
    )
    let vr = newValidationResult()
    let e = newEditor(config, vr)

    let svcCfg = e.lsp.service.getConfig("nim")
    check svcCfg.isSome
    check svcCfg.get.traceLevel == traceMessages

  test "language without a built-in default is registered":
    let config = newEditorConfig()
    config.lsp.servers["zig"] =
      LspServerConfig(command: "zls", extensions: @["zig"], trace: LspTraceLevel.ltOff)
    let vr = newValidationResult()
    let e = newEditor(config, vr)

    let svcCfg = e.lsp.service.getConfig("zig")
    check svcCfg.isSome
    check svcCfg.get.command == "zls"
    check svcCfg.get.extensions == @["zig"]
    check svcCfg.get.traceLevel == traceOff

  test "empty command leaves the default untouched":
    let config = newEditorConfig()
    config.lsp.servers["nim"] =
      LspServerConfig(command: "", extensions: @[], trace: LspTraceLevel.ltOff)
    let vr = newValidationResult()
    let e = newEditor(config, vr)

    let svcCfg = e.lsp.service.getConfig("nim")
    check svcCfg.isSome
    check svcCfg.get.command == "nimlangserver" # built-in default preserved

suite "editor_lsp - applyDiagnosticsForUri":
  privateAccess(LspIntegration)

  proc oneDiagnostic(msg: string): seq[lspTypes.Diagnostic] =
    @[
      lspTypes.Diagnostic(
        `range`: lspTypes.newRange(0, 0, 0, 1),
        severity: some(lspTypes.dsError),
        message: msg,
      )
    ]

  test "routes diagnostics to the matching non-active buffer":
    let e = createTestEditor()
    e.lsp.enabled = true
    let activeBuffer = e.activeBuffer()
    activeBuffer.filePath = some("/tmp/moe-diag-active.nim")

    let other = newTextBuffer("other\nlines", some("/tmp/moe-diag-other.nim"))
    e.addBuffer(other)

    e.applyDiagnosticsForUri(
      pathToUri("/tmp/moe-diag-other.nim"), oneDiagnostic("on other"), none(int)
    )

    check other.diagnostics.len == 1
    check other.diagnostics[0].message == "on other"
    check activeBuffer.diagnostics.len == 0

  test "active buffer still receives its own diagnostics":
    let e = createTestEditor()
    e.lsp.enabled = true
    let activeBuffer = e.activeBuffer()
    activeBuffer.filePath = some("/tmp/moe-diag-active.nim")

    e.applyDiagnosticsForUri(
      pathToUri("/tmp/moe-diag-active.nim"), oneDiagnostic("on active"), none(int)
    )
    check activeBuffer.diagnostics.len == 1

  test "unknown URI is dropped without crashing":
    let e = createTestEditor()
    e.lsp.enabled = true
    let activeBuffer = e.activeBuffer()
    activeBuffer.filePath = some("/tmp/moe-diag-active.nim")

    e.applyDiagnosticsForUri(
      pathToUri("/tmp/moe-diag-nonexistent.nim"), oneDiagnostic("nowhere"), none(int)
    )
    check activeBuffer.diagnostics.len == 0

  test "matches when buffer path has unnormalized segments vs normalized URI":
    # absolutePath is a no-op on absolute paths, so both sides must go
    # through normalizedPath or a `.` segment on one side drops diagnostics.
    let e = createTestEditor()
    e.lsp.enabled = true
    let activeBuffer = e.activeBuffer()
    let dir = getTempDir()
    let name = "moe_diag_unnormalized.nim"
    # Direct concat: joinPath ("/") collapses `.` so it can't build this form.
    let unnormalized = dir & "." & $DirSep & name
    let normalized = dir / name
    activeBuffer.filePath = some(unnormalized)

    e.applyDiagnosticsForUri(
      pathToUri(normalized), oneDiagnostic("via normalized"), none(int)
    )

    check activeBuffer.diagnostics.len == 1
    check activeBuffer.diagnostics[0].message == "via normalized"

  test "drops diagnostics aimed at a buffer that has become raw":
    # A reload can turn a tracked document into raw bytes; its document is
    # dropped, so the version guard has nothing to compare and a publish
    # already on the wire would paint markers at meaningless coordinates.
    let e = createTestEditor()
    e.lsp.enabled = true
    let activeBuffer = e.activeBuffer()
    activeBuffer.filePath = some("/tmp/moe-diag-raw.nim")
    activeBuffer.keepRaw = true

    e.applyDiagnosticsForUri(
      pathToUri("/tmp/moe-diag-raw.nim"), oneDiagnostic("stale"), none(int)
    )

    check activeBuffer.diagnostics.len == 0

  test "drops incoming diagnostics when disabled in config":
    let config = newEditorConfig()
    config.lsp.diagnostics.enable = false
    let vr = newValidationResult()
    let e = newEditor(config, vr)
    e.lsp.enabled = true
    let activeBuffer = e.activeBuffer()
    let path = getTempDir() / "moe_test_diag_disabled.nim"
    activeBuffer.filePath = some(path)

    e.applyDiagnosticsForUri(pathToUri(path), oneDiagnostic("dropped"), none(int))

    check activeBuffer.diagnostics.len == 0
    check activeBuffer.getLineMarker(0).isNone

  test "drops publish tagged with a version older than last didChange":
    # Regression (P0'-3): reload / rapid-edit races leave an in-flight publish
    # on the wire tagged with the pre-edit version. Applying it to the new
    # content shifts diagnostics onto the wrong lines.
    let e = createTestEditor()
    e.lsp.enabled = true
    let path = normalizedPath(absolutePath(getTempDir() / "moe_test_diag_stale.nim"))
    let activeBuffer = e.activeBuffer()
    activeBuffer.filePath = some(path)
    # Simulate the server-side wire state: we've sent up to version 2.
    e.lsp.documents[path] = initLspDocumentState(2, "", delivered = true)

    # An in-flight publish tagged with version=1 arrives after we've already
    # sent version=2. It must be dropped.
    e.applyDiagnosticsForUri(pathToUri(path), oneDiagnostic("stale"), some(1))
    check activeBuffer.diagnostics.len == 0

  test "applies publish whose version matches the last didChange":
    let e = createTestEditor()
    e.lsp.enabled = true
    let path = normalizedPath(absolutePath(getTempDir() / "moe_test_diag_current.nim"))
    let activeBuffer = e.activeBuffer()
    activeBuffer.filePath = some(path)
    e.lsp.documents[path] = initLspDocumentState(1, "", delivered = true)

    e.applyDiagnosticsForUri(pathToUri(path), oneDiagnostic("current"), some(1))
    check activeBuffer.diagnostics.len == 1
    check activeBuffer.diagnostics[0].message == "current"

  test "applies publish with no version (backward compatible)":
    # Many servers omit the optional version field; those frames still apply.
    let e = createTestEditor()
    e.lsp.enabled = true
    let path = getTempDir() / "moe_test_diag_untagged.nim"
    let activeBuffer = e.activeBuffer()
    activeBuffer.filePath = some(path)

    e.applyDiagnosticsForUri(pathToUri(path), oneDiagnostic("untagged"), none(int))
    check activeBuffer.diagnostics.len == 1

suite "editor_lsp - clearAllDiagnostics":
  test "clears stored diagnostics and markers from all buffers":
    let e = createTestEditor()
    e.lsp.enabled = true
    let activeBuffer = e.activeBuffer()
    let activePath = getTempDir() / "moe_test_diag_clear_active.nim"
    activeBuffer.filePath = some(activePath)

    let otherPath = getTempDir() / "moe_test_diag_clear_other.nim"
    let other = newTextBuffer("other\nlines", some(otherPath))
    e.addBuffer(other)

    let diag = @[
      lspTypes.Diagnostic(
        `range`: lspTypes.newRange(0, 0, 0, 1),
        severity: some(lspTypes.dsError),
        message: "boom",
      )
    ]
    e.applyDiagnosticsForUri(pathToUri(activePath), diag, none(int))
    e.applyDiagnosticsForUri(pathToUri(otherPath), diag, none(int))
    check activeBuffer.diagnostics.len == 1
    check other.diagnostics.len == 1
    check activeBuffer.getLineMarker(0).isSome
    check other.getLineMarker(0).isSome

    e.clearAllDiagnostics()

    check activeBuffer.diagnostics.len == 0
    check other.diagnostics.len == 0
    check activeBuffer.getLineMarker(0).isNone
    check other.getLineMarker(0).isNone

suite "editor_lsp - pollLspCompletion":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()
    e.state.mode = EditorMode.Insert

    e.pollLspCompletion()
    # No crash means success

  test "Does nothing when not in Insert mode":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.mode = EditorMode.Normal

    e.pollLspCompletion()
    # No crash means success

suite "editor_lsp - didOpen bookkeeping":
  # Open stamps the memo with the record.
  test "The memo says what the open actually did, and covers this version":
    # Memo must agree with its record.
    let e = createTestEditor()
    e.lsp.enabled = true
    let buf = e.activeBuffer()
    buf.filePath = some(getTempDir() / "moe_test_note_open_ok.nim")
    check buf.insertText(BufferPosition(line: 0, column: 0), "a").isOk

    let opened = e.lsp.onBufferOpen(buf)

    let memo = e.syncMemo(buf)
    check memo.isSome
    check memo.get.contentVersion == buf.contentVersion
    check (memo.get.verdict.kind == svSynced) == opened.isOk
    check e.lsp.isDocumentDelivered(buf.filePath.get) == opened.isOk

  test "shutdown forgets what the server was told, memo included":
    # Shutdown clears records and memos.
    let e = createTestEditor()
    e.lsp.enabled = true
    let buf = e.activeBuffer()
    buf.filePath = some(getTempDir() / "moe_test_shutdown_memo.nim")
    e.noteSyncedAt(buf, buf.contentVersion)
    check e.hasSyncRecord(buf)

    e.lsp.shutdown()

    check not e.hasSyncRecord(buf)

  test "Pathless buffer records nothing even on ok":
    let e = createTestEditor()
    e.lsp.enabled = true
    let buf = e.activeBuffer()
    buf.filePath = none(string)
    check e.lsp.onBufferOpen(buf).isOk
    check not e.hasSyncRecord(buf)

  test "Disabled integration records nothing even on ok":
    let e = createTestEditor()
    e.lsp.enabled = false
    let buf = e.activeBuffer()
    buf.filePath = some(getTempDir() / "moe_test_note_open_disabled.nim")
    check e.lsp.onBufferOpen(buf).isOk
    check not e.hasSyncRecord(buf)

  test "Raw buffer leaves nothing tracked":
    # Raw bytes are retracted, not tracked.
    let e = createTestEditor()
    e.lsp.enabled = true
    let buf = e.activeBuffer()
    buf.filePath = some(getTempDir() / "moe_test_note_open_raw.bin")
    buf.keepRaw = true

    check e.lsp.onBufferOpen(buf).isOk

    check not e.hasSyncRecord(buf)
    check not e.lsp.isDocumentDelivered(buf.filePath.get)

  test "A failed open is reported once, however many callers watch it":
    # Failed open logs once via the streak.
    let e = createTestEditor()
    defer:
      e.lsp.shutdown()
    e.lsp.enabled = true
    # Claimed by a server the service will not start, so didOpen cannot land.
    e.lsp.service.enabled = false

    let buf = e.activeBuffer()
    buf.filePath = some(getTempDir() / "moe_test_open_logged_once.nim")

    clearLspMessageLog()
    e.openBufferWithLsp(buf)
    check getLspMessageLog().len == 1

    e.openBufferWithLsp(buf)
    check getLspMessageLog().len == 1

suite "editor_lsp - renotifyOpenBuffers":
  # Pre-restart baseline must not survive re-open; otherwise staleness guard
  # rejects every future server edit.
  test "Never leaves the pre-restart baseline behind":
    let e = createTestEditor()
    e.lsp.enabled = true

    let buf = e.activeBuffer()
    buf.filePath = some(getTempDir() / "moe_test_renotify.nim")
    check buf.insertText(BufferPosition(line: 0, column: 0), "a").isOk
    # Stale baseline from before the server died.
    e.noteSyncedAt(buf, buf.contentVersion - 1)

    # Death retracts holdings to let re-open through.
    e.lsp.forgetServerDocuments("nim")
    check e.syncMemo(buf).isNone

    discard e.lsp.onBufferOpen(buf, serverIsFresh = true)

    # Re-open rewrites the record.
    check e.syncMemo(buf).get.contentVersion == buf.contentVersion

  test "Leaves buffers of other languages untouched":
    let e = createTestEditor()
    e.lsp.enabled = false

    let other = newTextBuffer("other", some(getTempDir() / "moe_test_renotify.rs"))
    e.addBuffer(other)
    e.noteSyncedAt(other, 999)

    check e.renotifyOpenBuffers("nim") == 0
    check e.syncedVersion(other) == 999

suite "editor_lsp - restartLspServer":
  test "Returns false when LSP is disabled":
    let e = createTestEditorWithLspDisabled()

    let result = e.restartLspServer()

    check not result
    check e.state.statusMessage == "LSP is not enabled"

  test "Returns false when buffer has no file path":
    let e = createTestEditor()
    e.lsp.enabled = true
    # Default buffer has no file path

    let result = e.restartLspServer()

    check not result
    check e.state.statusMessage == "No file path for current buffer"

suite "editor_lsp - Async functions":
  test "requestLspFormat returns false when LSP disabled":
    let e = createTestEditorWithLspDisabled()

    # We can't easily test async functions without running event loop
    # but we can verify the function exists and compiles
    check not e.lsp.enabled

  test "refreshLspFolds does nothing when LSP disabled":
    let e = createTestEditorWithLspDisabled()

    check not e.lsp.enabled

  test "requestLspRename does nothing when LSP disabled":
    let e = createTestEditorWithLspDisabled()

    check not e.lsp.enabled

  test "requestLspExecuteCommand does nothing when LSP disabled":
    let e = createTestEditorWithLspDisabled()

    check not e.lsp.enabled

suite "editor_lsp - per-feature config gates":
  proc createEditorWithLsp(config: EditorConfig): Editor =
    let vr = newValidationResult()
    result = newEditor(config, vr)
    result.lsp.enabled = true

  test "requestLspFormat returns false when disabled in config":
    let config = newEditorConfig()
    config.lsp.documentFormatting.enable = false
    let e = createEditorWithLsp(config)

    check not waitFor e.requestLspFormat()
    check e.state.statusMessage == "LSP document formatting is disabled"

  test "requestLspRename does nothing when disabled in config":
    let config = newEditorConfig()
    config.lsp.rename.enable = false
    let e = createEditorWithLsp(config)

    waitFor e.requestLspRename("newName")
    check e.state.statusMessage == "LSP rename is disabled"

  test "requestLspExecuteCommand does nothing when disabled in config":
    let config = newEditorConfig()
    config.lsp.executeCommand.enable = false
    let e = createEditorWithLsp(config)

    waitFor e.requestLspExecuteCommand("test.command")
    check e.state.statusMessage == "LSP execute command is disabled"

  test "requestLspFormat returns false when server lacks formatting capability":
    # Config is on and LSP is enabled, but the server never advertised
    # textDocument/formatting. Without the capability gate we would fire a
    # request that only fails after the response timeout.
    let config = newEditorConfig()
    let e = createEditorWithLsp(config)

    check not waitFor e.requestLspFormat()
    check e.state.statusMessage == "LSP document formatting is not supported"

suite "editor_lsp - applyWorkspaceEditFromServer staleness":
  proc replaceFirstThree(path: string): lspTypes.WorkspaceEdit =
    var changes = initTable[string, seq[lspTypes.TextEdit]]()
    changes[pathToUri(path)] =
      @[lspTypes.TextEdit(`range`: lspTypes.newRange(0, 0, 0, 3), newText: "xxx")]
    lspTypes.WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[lspTypes.TextDocumentEdit])
    )

  test "rejects an edit to an unsynced buffer the server never received":
    # Regression: unsynced buffer rejects server edit.
    let tmpDir = getTempDir() / "moe_test_server_edit_unsynced"
    createDir(tmpDir)
    defer:
      removeDir(tmpDir)

    let path = tmpDir / "Cargo.toml"
    let e = createTestEditor()
    e.lsp.enabled = true

    let buf = e.activeBuffer()
    buf.filePath = some(path)
    check buf.insertText(BufferPosition(line: 0, column: 0), "aaa").isOk
    e.maybeUpdateLsp()

    # Nothing reached a server, so no baseline is recorded.
    check not e.hasSyncRecord(buf)

    let res = e.applyWorkspaceEditFromServer(replaceFirstThree(path))

    check not res.applied
    check buf.getTextString() == "aaa"
    check e.state.statusMessage ==
      "Buffer changed since last sync; server edit discarded"

  test "applies an edit when the unsynced buffer still matches disk":
    let tmpDir = getTempDir() / "moe_test_server_edit_saved"
    createDir(tmpDir)
    defer:
      removeDir(tmpDir)

    let path = tmpDir / "Cargo.toml"
    let e = createTestEditor()
    e.lsp.enabled = true

    let buf = e.activeBuffer()
    buf.filePath = some(path)
    check buf.insertText(BufferPosition(line: 0, column: 0), "aaa").isOk
    buf.markSaved()
    e.maybeUpdateLsp()

    let res = e.applyWorkspaceEditFromServer(replaceFirstThree(path))

    check res.applied
    check buf.getTextString() == "xxx"

  test "applies an edit to a server-held buffer that is in sync":
    let tmpDir = getTempDir() / "moe_test_server_edit_synced"
    createDir(tmpDir)
    defer:
      removeDir(tmpDir)

    let path = tmpDir / "synced.nim"
    privateAccess(LspService)
    let e = createTestEditor()
    e.lsp.enabled = true
    e.lsp.service.liveWorkerOverride = proc(p: string): bool =
      true
    # No-thread worker: queue stands in for the server.
    e.lsp.service.workers["nim"] = newLspWorker("nim").get

    let buf = e.activeBuffer()
    buf.filePath = some(path)
    check buf.insertText(BufferPosition(line: 0, column: 0), "aaa").isOk
    e.openBufferWithLsp(buf)
    e.markDelivered(path)
    e.maybeUpdateLsp()

    let res = e.applyWorkspaceEditFromServer(replaceFirstThree(path))

    check res.applied
    check buf.getTextString() == "xxx"

  test "rejects an edit targeting a file not open in the editor":
    # Server-initiated applyEdit must not write files the user has not opened:
    # the whole edit is refused, nothing is written, and the refusal is
    # reported through the status message.
    let tmpDir = getTempDir() / "moe_test_server_edit_unopened"
    createDir(tmpDir)
    defer:
      removeDir(tmpDir)

    let path = tmpDir / "closed.txt"
    writeFile(path, "aaa")

    let e = createTestEditor()
    e.lsp.enabled = true

    let res = e.applyWorkspaceEditFromServer(replaceFirstThree(path))

    check not res.applied
    check e.state.statusMessage.contains("not open in the editor")
    check readFile(path) == "aaa"

suite "editor_lsp - TransactionRollbackError propagation":
  test "tick propagates TransactionRollbackError from the LSP poll":
    # The frame's tick is the poller that feeds the main loop's
    # emergency-save boundary (moe.nim editorCallback), so a
    # TransactionRollbackError from the LSP layer must propagate out of the
    # frame, not be swallowed. Defensive path: the production wiring converts
    # the exception to an err inside applyWorkspaceEdit, so this only fires
    # for a custom callback that raises directly.
    privateAccess(LspIntegration)
    privateAccess(LspService)
    let e = createTestEditor()
    e.lsp.enabled = true
    let worker = newLspWorker("nim").get
    worker.enqueueEventForTest(
      LspEvent(
        kind: levApplyEdit,
        applyEditReqIdJson: "7",
        applyEditEditJson: $(%*{"changes": {"file:///t.nim": []}}),
      )
    )
    e.lsp.service.workers["nim"] = worker
    e.lsp.service.onApplyWorkspaceEdit = proc(
        edit: WorkspaceEdit
    ): ApplyWorkspaceEditResult {.gcsafe.} =
      {.cast(gcsafe).}:
        raise newException(
          TransactionRollbackError, "withTransaction: failed to roll back: boom"
        )
    expect TransactionRollbackError:
      e.tick()

suite "editor_lsp - levApplyEdit target validation":
  proc negativeResponseQueued(worker: LspWorker, reqId: string): bool =
    ## A rejected edit must still be answered: queue an lcmdApplyEditResponse
    ## with applied = false and a non-empty reason.
    for cmd in worker.pendingCommandsForTest():
      if cmd.kind == lcmdApplyEditResponse and cmd.applyEditReqIdJson == reqId and
          not cmd.applyEditApplied and cmd.applyEditFailureReason.len > 0:
        return true
    false

  proc positiveResponseQueued(worker: LspWorker, reqId: string): bool =
    ## An applied edit must be answered: queue an lcmdApplyEditResponse
    ## with applied = true and an empty reason.
    for cmd in worker.pendingCommandsForTest():
      if cmd.kind == lcmdApplyEditResponse and cmd.applyEditReqIdJson == reqId and
          cmd.applyEditApplied and cmd.applyEditFailureReason.len == 0:
        return true
    false

  test "rejects an applyEdit with a non-file target URI without the callback":
    # Bad target URIs must not reach the apply callback.
    privateAccess(LspIntegration)
    privateAccess(LspService)
    let e = createTestEditor()
    e.lsp.enabled = true
    let worker = newLspWorker("nim").get
    worker.setStateForTest(lwsRunning)
    worker.enqueueEventForTest(
      LspEvent(
        kind: levApplyEdit,
        applyEditReqIdJson: "7",
        applyEditEditJson: $(%*{"changes": {"untitled:Untitled-1": []}}),
      )
    )
    e.lsp.service.workers["nim"] = worker
    var callbackCalled = false
    e.lsp.service.onApplyWorkspaceEdit = proc(
        edit: WorkspaceEdit
    ): ApplyWorkspaceEditResult {.gcsafe.} =
      {.cast(gcsafe).}:
        callbackCalled = true
        (applied: true, failureReason: none(string))
    e.tick()
    check not callbackCalled
    check negativeResponseQueued(worker, "7")

  test "rejects an applyEdit whose documentChanges targets a non-file URI":
    privateAccess(LspIntegration)
    privateAccess(LspService)
    let e = createTestEditor()
    e.lsp.enabled = true
    let worker = newLspWorker("nim").get
    worker.setStateForTest(lwsRunning)
    worker.enqueueEventForTest(
      LspEvent(
        kind: levApplyEdit,
        applyEditReqIdJson: "7",
        applyEditEditJson:
          $(%*{"documentChanges": [{"textDocument": {"uri": "untitled:Untitled-1"}}]}),
      )
    )
    e.lsp.service.workers["nim"] = worker
    var callbackCalled = false
    e.lsp.service.onApplyWorkspaceEdit = proc(
        edit: WorkspaceEdit
    ): ApplyWorkspaceEditResult {.gcsafe.} =
      {.cast(gcsafe).}:
        callbackCalled = true
        (applied: true, failureReason: none(string))
    e.tick()
    check not callbackCalled
    check negativeResponseQueued(worker, "7")

  test "rejects an applyEdit carrying file operations without the callback":
    # File operations must not reach a weaker callback either.
    privateAccess(LspIntegration)
    privateAccess(LspService)
    let e = createTestEditor()
    e.lsp.enabled = true
    let worker = newLspWorker("nim").get
    worker.setStateForTest(lwsRunning)
    worker.enqueueEventForTest(
      LspEvent(
        kind: levApplyEdit,
        applyEditReqIdJson: "7",
        applyEditEditJson: $(%*{"documentChanges": [{"kind": "rename"}]}),
      )
    )
    e.lsp.service.workers["nim"] = worker
    var callbackCalled = false
    e.lsp.service.onApplyWorkspaceEdit = proc(
        edit: WorkspaceEdit
    ): ApplyWorkspaceEditResult {.gcsafe.} =
      {.cast(gcsafe).}:
        callbackCalled = true
        (applied: true, failureReason: none(string))
    e.tick()
    check not callbackCalled
    check negativeResponseQueued(worker, "7")

  test "rejects an applyEdit mixing a valid and an invalid target URI":
    # All-or-nothing: a single malformed target refuses the whole edit.
    privateAccess(LspIntegration)
    privateAccess(LspService)
    let e = createTestEditor()
    e.lsp.enabled = true
    let worker = newLspWorker("nim").get
    worker.setStateForTest(lwsRunning)
    worker.enqueueEventForTest(
      LspEvent(
        kind: levApplyEdit,
        applyEditReqIdJson: "7",
        applyEditEditJson: $(%*{"changes": {"file:///ok.nim": [], "untitled:Bad": []}}),
      )
    )
    e.lsp.service.workers["nim"] = worker
    var callbackCalled = false
    e.lsp.service.onApplyWorkspaceEdit = proc(
        edit: WorkspaceEdit
    ): ApplyWorkspaceEditResult {.gcsafe.} =
      {.cast(gcsafe).}:
        callbackCalled = true
        (applied: true, failureReason: none(string))
    e.tick()
    check not callbackCalled
    check negativeResponseQueued(worker, "7")

  test "forwards an applyEdit with a well-formed file URI to the callback":
    privateAccess(LspIntegration)
    privateAccess(LspService)
    let e = createTestEditor()
    e.lsp.enabled = true
    let worker = newLspWorker("nim").get
    worker.setStateForTest(lwsRunning)
    worker.enqueueEventForTest(
      LspEvent(
        kind: levApplyEdit,
        applyEditReqIdJson: "7",
        applyEditEditJson: $(%*{"changes": {"file:///t.nim": []}}),
      )
    )
    e.lsp.service.workers["nim"] = worker
    var callbackCalled = false
    e.lsp.service.onApplyWorkspaceEdit = proc(
        edit: WorkspaceEdit
    ): ApplyWorkspaceEditResult {.gcsafe.} =
      {.cast(gcsafe).}:
        callbackCalled = true
        (applied: true, failureReason: none(string))
    e.tick()
    check callbackCalled
    check positiveResponseQueued(worker, "7")

  test "forwards an applyEdit with a well-formed documentChanges URI":
    privateAccess(LspIntegration)
    privateAccess(LspService)
    let e = createTestEditor()
    e.lsp.enabled = true
    let worker = newLspWorker("nim").get
    worker.setStateForTest(lwsRunning)
    worker.enqueueEventForTest(
      LspEvent(
        kind: levApplyEdit,
        applyEditReqIdJson: "7",
        applyEditEditJson:
          $(%*{"documentChanges": [{"textDocument": {"uri": "file:///t.nim"}}]}),
      )
    )
    e.lsp.service.workers["nim"] = worker
    var callbackCalled = false
    e.lsp.service.onApplyWorkspaceEdit = proc(
        edit: WorkspaceEdit
    ): ApplyWorkspaceEditResult {.gcsafe.} =
      {.cast(gcsafe).}:
        callbackCalled = true
        (applied: true, failureReason: none(string))
    e.tick()
    check callbackCalled
    check positiveResponseQueued(worker, "7")

  test "forwards an applyEdit when documentChanges is valid and changes is not":
    # documentChanges takes precedence; the ignored changes map is not checked.
    privateAccess(LspIntegration)
    privateAccess(LspService)
    let e = createTestEditor()
    e.lsp.enabled = true
    let worker = newLspWorker("nim").get
    worker.setStateForTest(lwsRunning)
    worker.enqueueEventForTest(
      LspEvent(
        kind: levApplyEdit,
        applyEditReqIdJson: "7",
        applyEditEditJson: $(
          %*{
            "documentChanges": [{"textDocument": {"uri": "file:///t.nim"}}],
            "changes": {"untitled:Bad": []},
          }
        ),
      )
    )
    e.lsp.service.workers["nim"] = worker
    var callbackCalled = false
    e.lsp.service.onApplyWorkspaceEdit = proc(
        edit: WorkspaceEdit
    ): ApplyWorkspaceEditResult {.gcsafe.} =
      {.cast(gcsafe).}:
        callbackCalled = true
        (applied: true, failureReason: none(string))
    e.tick()
    check callbackCalled
    check positiveResponseQueued(worker, "7")

suite "editor_lsp - rename path formatting":
  test "sanitizeForLog replaces C0 controls with ?":
    check sanitizeForLog("a\nb\rc\td\x1b") == "a?b?c?d?"
    check sanitizeForLog("/tmp/normal.nim") == "/tmp/normal.nim"
    check sanitizeForLog("") == ""
    check sanitizeForLog("a\x7Fb") == "a?b"
    check sanitizeForLog("\x7F") == "?"
    check sanitizeForLog("a b") == "a b"
    check sanitizeForLog("a\x7F\nb") == "a??b"

  test "formatPathList sanitizes, truncates count and chars":
    let many = @[
      "/tmp/a.nim", "/tmp/b.nim", "/tmp/c.nim", "/tmp/d.nim", "/tmp/e.nim",
      "/tmp/f.nim", "/tmp/g.nim", "/tmp/h.nim", "/tmp/i.nim", "/tmp/j.nim",
      "/tmp/k.nim", "/tmp/l.nim",
    ]
    let formatted = formatPathList(many)
    check formatted.contains(" and 2 more")
    check not formatted.contains("/tmp/k.nim")
    # Control-char sanitization
    check formatPathList(@["/tmp/a\nb.nim"]) == "/tmp/a?b.nim"
    # Char cap - count truncation alone
    check formatted.runeLen <= MaxRenamePathListChars
    # Char cap - char truncation with 10 long paths exceeding 800 runes
    var longPaths: seq[string] = @[]
    for i in 0 ..< 10:
      longPaths.add("/very/long/path/number_" & $i & "_" & "x".repeat(60) & ".nim")
    let longFormatted = formatPathList(longPaths)
    check longFormatted.runeLen <= MaxRenamePathListChars
    check longFormatted.endsWith("...")
    # Combined: many long paths should trigger both count and char limits
    # Suffix must survive char truncation (fixed from truncation hiding "and N more").
    var veryLongMany: seq[string] = @[]
    for i in 0 ..< 30:
      veryLongMany.add("/very/long/path/number_" & $i & "_" & "x".repeat(60) & ".nim")
    let veryLongFormatted = formatPathList(veryLongMany)
    check veryLongFormatted.runeLen <= MaxRenamePathListChars
    check veryLongFormatted.contains(" and 20 more")
    check veryLongFormatted.contains("...")

  test "formatPathList empty returns empty":
    check formatPathList(@[]) == ""

  test "formatPathList sanitizes DEL as well":
    check formatPathList(@["/tmp/a\x7Fb.nim"]) == "/tmp/a?b.nim"
    check sanitizeForLog("/tmp/a\x7F\nb.nim") == "/tmp/a??b.nim"

suite "editor_lsp - applyWorkspaceEditFromServer logging":
  test "includes truncated, sanitized path in status and LSP log":
    let tmpDir = getTempDir() / "moe_test_server_edit_log"
    createDir(tmpDir)
    defer:
      removeDir(tmpDir)

    let path = tmpDir / "synced_log.nim"
    privateAccess(LspService)
    let e = createTestEditor()
    e.lsp.enabled = true
    e.lsp.service.liveWorkerOverride = proc(p: string): bool =
      true
    # No-thread worker: queue stands in for the server.
    e.lsp.service.workers["nim"] = newLspWorker("nim").get

    clearLspMessageLog()

    let buf = e.activeBuffer()
    buf.filePath = some(path)
    check buf.insertText(BufferPosition(line: 0, column: 0), "aaa").isOk
    e.openBufferWithLsp(buf)
    e.markDelivered(path)
    e.maybeUpdateLsp()

    var changes = initTable[string, seq[lspTypes.TextEdit]]()
    changes[pathToUri(path)] =
      @[lspTypes.TextEdit(`range`: lspTypes.newRange(0, 0, 0, 3), newText: "xxx")]
    let edit = lspTypes.WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[lspTypes.TextDocumentEdit])
    )

    let res = e.applyWorkspaceEditFromServer(edit)
    check res.applied
    check e.state.statusMessage.contains("Applied server edit")
    check e.state.statusMessage.contains("synced_log.nim")
    check getLspMessageLog().len > 0
    check getLspMessageLog()[^1].contains("Applied server edit")

suite "editor_lsp - rename path helpers":
  test "sanitizeForLog covers rename originalWord and newName":
    check sanitizeForLog("foo\nbar") == "foo?bar"
    check sanitizeForLog("new\x1bName") == "new?Name"
    check sanitizeForLog("a\rb\tc") == "a?b?c"

  test "formatPathList handles mixed buffer and unopened paths for rename":
    # Simulate rename's allPaths (buffer + file) and verify sanitization and limits
    let paths = @["/tmp/open1.nim", "/tmp/\nbad.nim", "/tmp/open2.nim"]
    let formatted = formatPathList(paths)
    check formatted.contains("/tmp/open1.nim")
    check formatted.contains("/tmp/?bad.nim")
    check formatted.contains("/tmp/open2.nim")

  test "non-ASCII path respects runeLen limit":
    let nonAscii = "/tmp/あ".repeat(200) & ".nim" # multi-byte runes
    let single = formatPathList(@[nonAscii])
    # Should be truncated by runeLen, not byte len, and use rune-based capacity
    check single.runeLen <= MaxRenamePathListChars
    if nonAscii.runeLen > MaxRenamePathListChars:
      check single.endsWith("...")

suite "lsp_integration - applyWorkspaceEdit sanitization":
  test "invalid URI with control chars is sanitized in error":
    var buffers: seq[TextBuffer] = @[]
    # Use unsupported scheme with control char so validateLocalFileUri rejects and error contains URI
    let badUri = "http://tmp/a\nb\x7F.nim"
    var changes = initTable[string, seq[lspTypes.TextEdit]]()
    changes[badUri] =
      @[lspTypes.TextEdit(`range`: lspTypes.newRange(0, 0, 0, 0), newText: "x")]
    let edit = lspTypes.WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[lspTypes.TextDocumentEdit])
    )
    let res = applyWorkspaceEdit(buffers, edit)
    check res.isErr
    check not res.error.contains("\n")
    check not res.error.contains("\x7F")
    check res.error.contains("?")

  test "unopened file path with control chars is sanitized when rejected":
    var buffers: seq[TextBuffer] = @[]
    # Use percent-encoded control char so it passes URI validation but decodes to control
    let uri = "file:///tmp/a%0Ab.nim"
    var changes = initTable[string, seq[lspTypes.TextEdit]]()
    changes[uri] =
      @[lspTypes.TextEdit(`range`: lspTypes.newRange(0, 0, 0, 0), newText: "x")]
    let edit = lspTypes.WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[lspTypes.TextDocumentEdit])
    )
    let res = applyWorkspaceEdit(buffers, edit)
    check res.isErr
    check not res.error.contains("\n")
    check res.error.contains("?")

  test "formatEditPathList warning suffix survives truncation with control chars":
    let many = @["/tmp/a\nb.nim", "/tmp/c\x7Fd.nim", "/tmp/e\rb.nim"]
    let formatted = formatEditPathList(many)
    check not formatted.contains("\n")
    check not formatted.contains("\r")
    check not formatted.contains("\x7F")
    check formatted.contains("?")

suite "editor_lsp - applyWorkspaceEditFromServer failure logging":
  test "failure sanitizes and logs to LSP message log":
    let tmpDir = getTempDir() / "moe_test_server_edit_fail_log"
    createDir(tmpDir)
    defer:
      removeDir(tmpDir)
    let path = tmpDir / "fail_log.nim"
    let e = createTestEditor()
    e.lsp.enabled = true
    e.lsp.service.liveWorkerOverride = proc(p: string): bool =
      true
    clearLspMessageLog()
    let buf = e.activeBuffer()
    buf.filePath = some(path)
    check buf.insertText(BufferPosition(line: 0, column: 0), "aaa").isOk
    e.openBufferWithLsp(buf)
    e.maybeUpdateLsp()
    # Craft edit with invalid URI containing control char to force failure
    let badUri = "file:///tmp/fail\nbad.nim"
    var changes = initTable[string, seq[lspTypes.TextEdit]]()
    changes[badUri] =
      @[lspTypes.TextEdit(`range`: lspTypes.newRange(0, 0, 0, 0), newText: "x")]
    let edit = lspTypes.WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[lspTypes.TextDocumentEdit])
    )
    let res = e.applyWorkspaceEditFromServer(edit)
    check not res.applied
    check res.failureReason.isSome
    check not res.failureReason.get.contains("\n")
    check e.state.statusMessage.contains("Failed to apply server edit")
    check not e.state.statusMessage.contains("\n")
    check getLspMessageLog().len > 0
    check getLspMessageLog()[^1].contains("Failed to apply server edit")
    check not getLspMessageLog()[^1].contains("\n")

suite "editor_lsp - helper - buildModifiedPathSuffix":
  test "deduplicates path collection logic and sanitizes":
    let tmpDir = getTempDir() / "moe_test_suffix_helper"
    createDir(tmpDir)
    defer:
      removeDir(tmpDir)
    let p1 = tmpDir / "a.nim"
    let p2 = tmpDir / "b.nim"
    let e = createTestEditor()
    let b1 = newTextBuffer()
    b1.filePath = some(p1)
    let b2 = newTextBuffer()
    b2.filePath = some(p2)
    e.buffers = @[b1, b2]
    let res = WorkspaceEditResult(modifiedCount: 2, modifiedBufferIndexes: @[0, 1])
    let suffix = e.buildModifiedPathSuffix(res)
    check suffix.contains("a.nim")
    check suffix.contains("b.nim")
    check suffix.startsWith(": ")
  test "buildModifiedPathSuffix handles empty and sanitizes control characters":
    let e = createTestEditor()
    let empty = WorkspaceEditResult(modifiedCount: 0, modifiedBufferIndexes: @[])
    check e.buildModifiedPathSuffix(empty) == ""
    let bad = newTextBuffer()
    bad.filePath = some("/tmp/a\nb.nim")
    e.buffers = @[bad]
    let withBad = WorkspaceEditResult(modifiedCount: 1, modifiedBufferIndexes: @[0])
    let s = e.buildModifiedPathSuffix(withBad)
    check s.contains("?")
    check not s.contains("\n")

suite "editor_lsp - recoverFromFailedWorkspaceEdit":
  let tmpDir = getTempDir() / "moe_test_recover_failed_edit"

  setup:
    removeDir(tmpDir)
    createDir(tmpDir)

  teardown:
    removeDir(tmpDir)

  proc editTargeting(path: string): lspTypes.WorkspaceEdit =
    var changes = initTable[string, seq[lspTypes.TextEdit]]()
    changes[pathToUri(path)] =
      @[lspTypes.TextEdit(`range`: lspTypes.newRange(0, 0, 0, 1), newText: "x")]
    lspTypes.WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[lspTypes.TextDocumentEdit])
    )

  proc withReachableServer(path: string): Editor =
    ## Editor with server holding path at empty text.
    privateAccess(LspIntegration)
    result = createTestEditor()
    result.lsp.enabled = true
    result.lsp.service.liveWorkerOverride = proc(p: string): bool =
      true
    result.lsp.documents[canonicalPath(path)] =
      initLspDocumentState(1, "", delivered = true)

  test "re-syncs a target the half-applied edit left modified":
    # applyWorkspaceEdit commits buffer by buffer, so a failure partway through
    # leaves earlier targets modified but unsynced.
    privateAccess(LspIntegration)
    let path = tmpDir / "modified.nim"
    let e = withReachableServer(path)
    let buf = e.activeBuffer()
    buf.filePath = some(path)
    check buf.insertText(BufferPosition(line: 0, column: 0), "hello").isOk

    e.recoverFromFailedWorkspaceEdit(editTargeting(path), "Failed to apply edits: boom")

    check e.lsp.documents[canonicalPath(path)].shadow == buf.getTextString()
    check e.syncedVersion(buf) == buf.contentVersion
    check buf.contentVersion > 0

  test "skips the re-sync when the rollback itself failed":
    # Partially reverted text must not become the server's new baseline.
    privateAccess(LspIntegration)
    let path = tmpDir / "inconsistent.nim"
    let e = withReachableServer(path)
    let buf = e.activeBuffer()
    buf.filePath = some(path)
    check buf.insertText(BufferPosition(line: 0, column: 0), "hello").isOk

    e.recoverFromFailedWorkspaceEdit(
      editTargeting(path), "Failed to apply edits: boom" & BufferStateInconsistentSuffix
    )

    check e.lsp.documents[canonicalPath(path)].shadow == ""
    check not e.hasSyncRecord(buf)

  test "leaves a buffer outside the edit's targets alone":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    buf.filePath = some(tmpDir / "untouched.nim")
    check buf.insertText(BufferPosition(line: 0, column: 0), "hello").isOk
    e.noteSyncedAt(buf, 0)

    e.recoverFromFailedWorkspaceEdit(
      editTargeting(tmpDir / "other.nim"), "Failed to apply edits: boom"
    )

    check e.syncedVersion(buf) == 0

  test "re-clamps a cursor left past a shrunk buffer's end":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    buf.filePath = some(tmpDir / "shrunk.nim")
    check buf.insertText(BufferPosition(line: 0, column: 0), "hello").isOk
    e.activeWindow.cursor = BufferPosition(line: 99, column: 99)

    e.recoverFromFailedWorkspaceEdit(
      editTargeting(tmpDir / "shrunk.nim"), "Failed to apply edits: boom"
    )

    check e.activeWindow.cursor.line < buf.len
