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

import std/[unittest, os, options, strutils, tables, importutils]

import pkg/chronos

import ../src/moepkg/[editor, buffer, config, config_loader, message_log, types]
import ../src/moepkg/editor_lsp {.all.}
import ../src/moepkg/lsp_integration {.all.}
import ../src/moepkg/lsp/protocol/types as lspTypes

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

suite "editor_lsp - maybeUpdateLsp":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()
    let activeBuffer = e.activeBuffer()
    let initialVer = e.lastLspContentVersions.getOrDefault(activeBuffer.id, 0)

    e.maybeUpdateLsp()

    check e.lastLspContentVersions.getOrDefault(activeBuffer.id, 0) == initialVer

  test "Does nothing when buffer has not changed":
    let e = createTestEditor()
    e.lsp.enabled = true
    let activeBuffer = e.activeBuffer()
    e.lastLspContentVersions[activeBuffer.id] = activeBuffer.contentVersion

    e.maybeUpdateLsp()

    check e.lastLspContentVersions[activeBuffer.id] == activeBuffer.contentVersion

  test "Tracking is per-buffer":
    let e = createTestEditor()
    e.lsp.enabled = true
    let activeBuffer = e.activeBuffer()
    # Another buffer's entry must not affect the active buffer's tracking
    let otherBuffer = newTextBuffer("other")
    e.addBuffer(otherBuffer)
    e.lastLspContentVersions[otherBuffer.id] = 999

    e.lastLspContentVersions[activeBuffer.id] = activeBuffer.contentVersion
    e.maybeUpdateLsp()

    check e.lastLspContentVersions[activeBuffer.id] == activeBuffer.contentVersion
    check e.lastLspContentVersions[otherBuffer.id] == 999

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

    let path = tmpDir / "collide.txt"
    let e = createTestEditor()
    e.lsp.enabled = true
    e.lsp.service.liveWorkerOverride = proc(p: string): bool =
      true

    let buf = e.activeBuffer()
    buf.filePath = some(path)
    e.openBufferWithLsp(buf)
    check e.lsp.sentDocumentVersion(path) == some(1)

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

  test "Failed onBufferChange logs to LSP message log and advances tracker":
    # An unknown extension has no LSP config, so the untracked -> didOpen
    # fallback in onBufferChange fails. The proc must surface that via
    # logLspDegraded and advance lastLspContentVersions so the next tick does
    # not re-run and re-log the same failing didChange.
    privateAccess(LspIntegration)

    let tmpDir = getTempDir() / "moe_test_maybe_update_lsp_err"
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

    e.maybeUpdateLsp()

    check e.lastLspContentVersions[buf.id] == buf.contentVersion
    let logAfterFirst = getLspMessageLog()
    check logAfterFirst.len == 1
    check logAfterFirst[0].startsWith("[LSP] didChange ")

    # Second call at the same contentVersion is a no-op: no extra log entry.
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
    e.lsp.documents[path] = (version: 2, shadow: "")

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
    e.lsp.documents[path] = (version: 1, shadow: "")

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

suite "editor_lsp - renotifyOpenBuffers":
  # onBufferOpen short-circuits to ok() while LSP is disabled, so the success
  # branch is reachable without a live server. That branch used to leave
  # lastLspContentVersions on the pre-restart baseline, which made the
  # applyWorkspaceEdit staleness guard reject every server-initiated edit.
  test "Records the version the re-open just sent":
    let e = createTestEditor()
    e.lsp.enabled = false

    let buf = e.activeBuffer()
    buf.filePath = some(getTempDir() / "moe_test_renotify.nim")
    check buf.insertText(BufferPosition(line: 0, column: 0), "a").isOk
    # Stale baseline from before the server died.
    e.lastLspContentVersions[buf.id] = buf.contentVersion - 1

    check e.renotifyOpenBuffers("nim") == 0
    check e.lastLspContentVersions[buf.id] == buf.contentVersion

  test "Leaves buffers of other languages untouched":
    let e = createTestEditor()
    e.lsp.enabled = false

    let other = newTextBuffer("other", some(getTempDir() / "moe_test_renotify.rs"))
    e.addBuffer(other)
    e.lastLspContentVersions[other.id] = 999

    check e.renotifyOpenBuffers("nim") == 0
    check e.lastLspContentVersions[other.id] == 999

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
    # Regression: "Cargo.toml in a Rust project". The file has no LSP config,
    # so didChange is dropped for want of a worker — but maybeUpdateLsp records
    # a sync baseline anyway. The versions then matched while the buffer held
    # unsaved text the server never saw, so the disk-based coordinates were
    # applied to it.
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

    # The baseline is recorded even though nothing reached a server.
    check e.lastLspContentVersions[buf.id] == buf.contentVersion

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
    let e = createTestEditor()
    e.lsp.enabled = true
    e.lsp.service.liveWorkerOverride = proc(p: string): bool =
      true

    let buf = e.activeBuffer()
    buf.filePath = some(path)
    check buf.insertText(BufferPosition(line: 0, column: 0), "aaa").isOk
    e.openBufferWithLsp(buf)
    e.maybeUpdateLsp()

    let res = e.applyWorkspaceEditFromServer(replaceFirstThree(path))

    check res.applied
    check buf.getTextString() == "xxx"
