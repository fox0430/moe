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

## Tests for editor_reload.nim

import std/[unittest, os, monotimes, options, posix, times, strutils]

import pkg/results

import
  ../src/moepkg/[
    editor, config, config_loader, editor_reload, editor_file, editor_window,
    editor_buffers, editor_substitute, window_manager, modes,
  ]
import ../src/moepkg/types/editor_types
import ../src/moepkg/buffer

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc pastMonoTime(ms: int64): MonoTime =
  getMonoTime() - initDuration(milliseconds = ms)

suite "editor_reload - maybeReloadExternallyModifiedFile":
  test "is a no-op when liveReloadOfFile is disabled":
    var config = newEditorConfig()
    config.standard.liveReloadOfFile = false
    let vr = newValidationResult()
    let e = newEditor(config, vr)
    let path = getTempDir() / "moe_test_reload_disabled.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    sleep(50)
    writeFile(path, "changed on disk")
    e.state.timing.lastFileModCheck = pastMonoTime(5000)
    e.maybeReloadExternallyModifiedFile()
    check e.activeBuffer.getLine(0) == "original"
    check e.state.statusMessage != "File reloaded: " & path

  test "is a no-op during the debounce window":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_debounce.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    sleep(50)
    writeFile(path, "changed on disk")
    let lastCheck = getMonoTime()
    e.state.timing.lastFileModCheck = lastCheck
    e.maybeReloadExternallyModifiedFile()
    check e.state.timing.lastFileModCheck == lastCheck
    check e.activeBuffer.getLine(0) == "original"

  test "does not reload an unmodified buffer":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_unmodified.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    e.state.timing.lastFileModCheck = pastMonoTime(5000)
    e.maybeReloadExternallyModifiedFile()
    check e.activeBuffer.getLine(0) == "original"

  test "reloads an externally modified buffer":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_modified.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    e.activeBuffer.lastFileModTime = some(getTime() - 24.hours)
    writeFile(path, "changed on disk")
    e.state.timing.lastFileModCheck = pastMonoTime(5000)
    e.maybeReloadExternallyModifiedFile()
    check e.activeBuffer.getLine(0) == "changed on disk"
    check e.state.statusMessage == "File reloaded: " & path

  test "warns instead of reloading when the buffer has unsaved changes":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_unsaved.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    discard e.activeBuffer.insert(1, "unsaved")
    e.activeBuffer.lastFileModTime = some(getTime() - 24.hours)
    writeFile(path, "changed on disk")
    e.state.timing.lastFileModCheck = pastMonoTime(5000)
    e.maybeReloadExternallyModifiedFile()
    check e.activeBuffer.getLine(0) == "original"
    check "Warning:" in e.state.statusMessage
    check e.activeBuffer.externalModWarned

  test "waits instead of reloading while an Insert session is open":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_insert.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    # Entering Insert opens the transaction before anything is typed, so the
    # buffer is unmodified and the unsaved-changes branch above does not apply.
    check e.activeBuffer.beginTransaction("Insert mode edit").isOk
    e.activeWindow.mode = EditorMode.Insert
    e.activeBuffer.lastFileModTime = some(getTime() - 24.hours)
    writeFile(path, "changed on disk")
    e.state.timing.lastFileModCheck = pastMonoTime(5000)
    e.maybeReloadExternallyModifiedFile()
    check e.activeBuffer.getLine(0) == "original"
    check e.activeBuffer.inTransaction

    # Once the session ends the next check picks the change up.
    check e.activeBuffer.commitTransaction().isOk
    e.activeWindow.mode = EditorMode.Normal
    e.state.timing.lastFileModCheck = pastMonoTime(5000)
    e.maybeReloadExternallyModifiedFile()
    check e.activeBuffer.getLine(0) == "changed on disk"

suite "editor_reload - reloadCurrentFile":
  test "returns an error when the buffer has no file path":
    let e = createTestEditor()
    let result = e.reloadCurrentFile()
    check result.isErr
    check "No file name" in result.error

  test "reloads the current file":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_current.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    sleep(50)
    writeFile(path, "reloaded content")
    let result = e.reloadCurrentFile()
    check result.isOk
    check e.activeBuffer.getLine(0) == "reloaded content"
    check e.state.statusMessage == "File reloaded: " & path

  test "does not announce when the caller asked for silence":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_silent.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    sleep(50)
    writeFile(path, "reloaded content")
    e.state.statusMessage = "Saved: " & path
    check e.reloadCurrentFile(announce = false).isOk
    check e.activeBuffer.getLine(0) == "reloaded content"
    check e.state.statusMessage == "Saved: " & path

  test "leaves the cursor of a window on another buffer alone":
    # A reload only replaces one buffer, so a window showing a file it never
    # touched must keep the cursor it had -- including an Insert-mode one
    # resting one past the last character.
    let e = createTestEditor()
    let
      pathA = getTempDir() / "moe_test_reload_clamp_a.txt"
      pathB = getTempDir() / "moe_test_reload_clamp_b.txt"
    writeFile(pathA, "original")
    writeFile(pathB, "abc")
    defer:
      removeFile(pathA)
      removeFile(pathB)
    discard e.loadFile(pathA)

    let bufB = newTextBuffer("")
    check bufB.loadFile(pathB).isOk
    e.addBuffer(bufB)
    check e.hsplitWithBuffer(bufB).isOk
    e.syncActiveWindow()
    e.setMode(EditorMode.Insert)
    # One past the last character: valid in Insert, not in Normal.
    e.cursor = BufferPosition(line: 0, column: 3)

    # Back to the window on file A, in Normal mode, and reload it.
    var activatedA = false
    for i, window in e.windowManager.windows:
      if window.buffer.filePath.isSome and window.buffer.filePath.get == pathA:
        e.windowManager.activateWindow(i)
        activatedA = true
        break
    check activatedA
    e.syncActiveWindow()
    e.setMode(EditorMode.Normal)
    sleep(50)
    writeFile(pathA, "reloaded content")
    check e.reloadCurrentFile().isOk

    var checkedB = false
    for window in e.windowManager.windows:
      if window.buffer == bufB:
        check window.cursor == BufferPosition(line: 0, column: 3)
        checkedB = true
    check checkedB

  test "clamps a second window on the same buffer with its own mode":
    # Both windows show the reloaded buffer, but they are in different modes:
    # clamping the inactive one with the active window's Normal rules would
    # pull its Insert cursor back off the end of the line.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_clamp_same.txt"
    writeFile(path, "abc")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    let buf = e.activeBuffer

    check e.hsplitWithBuffer(buf).isOk
    e.syncActiveWindow()
    e.setMode(EditorMode.Insert)
    # One past the last character: valid in Insert, not in Normal.
    e.cursor = BufferPosition(line: 0, column: 3)
    let insertWindow = e.activeWindow

    var activatedOther = false
    for i, window in e.windowManager.windows:
      if window != insertWindow:
        e.windowManager.activateWindow(i)
        activatedOther = true
        break
    check activatedOther
    e.syncActiveWindow()
    e.setMode(EditorMode.Normal)
    sleep(50)
    # Line 0 keeps its three characters, so column 3 stays valid for Insert and
    # stays invalid for Normal.
    writeFile(path, "abc\nsecond line")
    check e.reloadCurrentFile().isOk

    check insertWindow.cursor == BufferPosition(line: 0, column: 3)

suite "editor_reload - position state invalidation":
  test "cancels a visual selection and leaves visual mode":
    # The anchor names text the reload dropped, so the selection cannot be
    # re-derived: keeping it would apply the next operator to lines the user
    # never selected.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_visual.txt"
    writeFile(path, "one\ntwo\nthree\nfour")
    defer:
      removeFile(path)
    discard e.loadFile(path)

    e.setMode(EditorMode.VisualLine)
    e.cursor = BufferPosition(line: 3, column: 0)
    e.state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 3, column: 0),
      active: true,
      kind: vskLine,
    )

    sleep(50)
    writeFile(path, "only")
    check e.reloadCurrentFile().isOk

    check not e.state.visualSelection.active
    check e.state.mode == EditorMode.Normal
    check e.cursor == BufferPosition(line: 0, column: 0)

  test "pulls a viewport parked past the new end back into view":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_viewport.txt"
    writeFile(path, "a\nb\nc\nd\ne\nf\ng\nh")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    e.cursor = BufferPosition(line: 7, column: 0)
    e.activeWindow.viewport.topLine = 6

    sleep(50)
    writeFile(path, "a\nb")
    check e.reloadCurrentFile().isOk

    check e.activeWindow.viewport.topLine < e.activeBuffer.len
    check e.cursor == BufferPosition(line: 1, column: 0)

  test "clamps jump list entries naming a line the reload dropped":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_jumplist.txt"
    writeFile(path, "a\nb\nc\nd\ne")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    let buf = e.activeBuffer
    e.state.jumpList.list = @[JumpPosition(bufferId: buf.id, line: 4, column: 0)]

    sleep(50)
    writeFile(path, "a\nb")
    check e.reloadCurrentFile().isOk

    check e.state.jumpList.list[0].line == 1

suite "editor_reload - deferred reload":
  test "owes the reload while an edit group is open and warns once":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_defer.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    e.setMode(EditorMode.Insert)

    sleep(50)
    writeFile(path, "changed on disk")
    e.state.timing.lastFileModCheck = pastMonoTime(5000)
    e.maybeReloadExternallyModifiedFile()

    check e.activeBuffer.getLine(0) == "original"
    check e.activeBuffer.reloadDeferred
    check "changed on disk" in e.state.statusMessage

  test "runs the owed reload on the first poll after the edit group closes":
    # The owed reload bypasses the poll interval: waiting one out would leave
    # the buffer stale for as long as the user kept typing.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_defer_run.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    e.setMode(EditorMode.Insert)

    sleep(50)
    writeFile(path, "changed on disk")
    e.state.timing.lastFileModCheck = pastMonoTime(5000)
    e.maybeReloadExternallyModifiedFile()
    check e.activeBuffer.reloadDeferred

    e.setMode(EditorMode.Normal)
    # No interval has elapsed since the poll above.
    e.state.timing.lastFileModCheck = getMonoTime()
    e.maybeReloadExternallyModifiedFile()

    check e.activeBuffer.getLine(0) == "changed on disk"
    check not e.activeBuffer.reloadDeferred

suite "editor_reload - sweep across buffers":
  test "reloads a buffer that is open but not active":
    # `git checkout` rewrites every open file at once, not just the one under
    # the cursor.
    let e = createTestEditor()
    let
      pathA = getTempDir() / "moe_test_reload_sweep_a.txt"
      pathB = getTempDir() / "moe_test_reload_sweep_b.txt"
    writeFile(pathA, "a original")
    writeFile(pathB, "b original")
    defer:
      removeFile(pathA)
      removeFile(pathB)
    discard e.loadFile(pathA)

    let bufB = newTextBuffer("")
    check bufB.loadFile(pathB).isOk
    e.addBuffer(bufB)

    sleep(50)
    writeFile(pathB, "b changed on disk")
    e.state.timing.lastFileModCheck = pastMonoTime(5000)
    e.maybeReloadExternallyModifiedFile()

    check bufB.getLine(0) == "b changed on disk"
    # The active buffer is untouched, so its status line says nothing.
    check e.activeBuffer.getLine(0) == "a original"
    check e.state.statusMessage != "File reloaded: " & pathB

  test "leaves the buffer alone when the write did not change the bytes":
    # A formatter with nothing to change still moves the mtime. Reloading
    # would drop the undo history for no reason.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_same_bytes.txt"
    writeFile(path, "unchanged")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    let buf = e.activeBuffer

    sleep(50)
    writeFile(path, "unchanged")
    check buf.isExternallyModified()
    e.state.timing.lastFileModCheck = pastMonoTime(5000)
    e.maybeReloadExternallyModifiedFile()

    check buf.getLine(0) == "unchanged"
    check e.state.statusMessage != "File reloaded: " & path
    # Re-baselined, so the next sweep has nothing to report.
    check not buf.isExternallyModified()

suite "editor_reload - external change detection":
  test "detects a write that moved the mtime backwards":
    # A restore from backup or a checkout of an older revision replaces the
    # contents with an older timestamp.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_older_mtime.txt"
    writeFile(path, "current")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    let buf = e.activeBuffer

    writeFile(path, "restored from an older copy")
    setLastModificationTime(path, getTime() - initDuration(hours = 1))
    check buf.isExternallyModified()

  test "detects a same-mtime write through the size":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_same_mtime.txt"
    writeFile(path, "short")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    let buf = e.activeBuffer
    let stamp = buf.lastFileModTime.get

    # Two writes inside the filesystem's timestamp granularity look alike.
    writeFile(path, "a good deal longer than before")
    setLastModificationTime(path, stamp)
    check buf.isExternallyModified()

suite "editor_reload - maybeUpdateConflicts":
  test "is a no-op when the buffer has not changed":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_conflicts.txt"
    writeFile(path, "line 1\nline 2")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    e.state.timing.lastConflictScanSeq = e.activeBuffer.changeSeq
    e.state.timing.lastConflictScan = pastMonoTime(5000)
    e.maybeUpdateConflicts()
    check e.activeBuffer.changeSeq == e.state.timing.lastConflictScanSeq

  test "rescans after the buffer changes":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_conflicts2.txt"
    writeFile(path, "line 1\nline 2")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    e.state.timing.lastConflictScanSeq = e.activeBuffer.changeSeq
    let staleScan = pastMonoTime(5000)
    e.state.timing.lastConflictScan = staleScan
    discard e.activeBuffer.insert(1, "new line")
    e.maybeUpdateConflicts()
    check e.state.timing.lastConflictScanSeq == e.activeBuffer.changeSeq
    check e.state.timing.lastConflictScan > staleScan

suite "editor_reload - content replacement drives invalidation":
  test "a bare loadFile on a registered buffer invalidates its window":
    # The backup-restore shape: the contents are replaced by a plain
    # `buf.loadFile`, with nothing calling finishReload afterwards.
    let e = createTestEditor()
    let
      pathA = getTempDir() / "moe_test_replace_hook_a.txt"
      pathB = getTempDir() / "moe_test_replace_hook_b.txt"
    writeFile(pathA, "original")
    writeFile(pathB, "one\ntwo\nthree\nfour\nfive")
    defer:
      removeFile(pathA)
      removeFile(pathB)
    discard e.loadFile(pathA)

    let bufB = newTextBuffer("")
    check bufB.loadFile(pathB).isOk
    e.addBuffer(bufB)
    check e.hsplitWithBuffer(bufB).isOk
    e.syncActiveWindow()
    e.cursor = BufferPosition(line: 4, column: 3)
    e.viewport.topLine = 4

    writeFile(pathB, "short")
    check bufB.loadFile(pathB).isOk

    var checkedB = false
    for window in e.windowManager.windows:
      if window.buffer == bufB:
        check window.cursor == BufferPosition(line: 0, column: 3)
        check window.viewport.topLine == 0
        checkedB = true
    check checkedB

  test "a bare loadFile drops a pointer gesture anchored in that buffer":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_replace_hook_pointer.txt"
    writeFile(path, "one\ntwo\nthree")
    defer:
      removeFile(path)
    discard e.loadFile(path)

    e.state.pointerSelection.active = true
    e.state.pointerSelection.bufferId = e.activeBuffer.id
    e.state.pointerSelection.anchorFirst = BufferPosition(line: 2, column: 0)

    writeFile(path, "one")
    check e.activeBuffer.loadFile(path).isOk

    check not e.state.pointerSelection.active

suite "editor_reload - LSP overlay cache scoping":
  proc seedOverlayCaches(e: Editor, bufferId: BufferId) =
    e.state.lspCache.semanticTokensCache =
      SemanticTokensCache(bufferId: bufferId, isValid: true)
    e.state.lspCache.inlayHintCache = InlayHintCache(bufferId: bufferId, isValid: true)
    e.state.lspCache.codeLensCache = CodeLensCache(bufferId: bufferId, isValid: true)
    e.state.lspCache.documentHighlightCache =
      DocumentHighlightCache(bufferId: bufferId, isValid: true)

  proc anyOverlayValid(e: Editor): bool =
    e.state.lspCache.semanticTokensCache.isValid or
      e.state.lspCache.inlayHintCache.isValid or e.state.lspCache.codeLensCache.isValid or
      e.state.lspCache.documentHighlightCache.isValid

  proc allOverlaysValid(e: Editor): bool =
    e.state.lspCache.semanticTokensCache.isValid and
      e.state.lspCache.inlayHintCache.isValid and e.state.lspCache.codeLensCache.isValid and
      e.state.lspCache.documentHighlightCache.isValid

  test "reloading a background buffer keeps the active buffer's overlays":
    let e = createTestEditor()
    let
      pathA = getTempDir() / "moe_test_overlay_scope_a.txt"
      pathB = getTempDir() / "moe_test_overlay_scope_b.txt"
    writeFile(pathA, "active")
    writeFile(pathB, "background")
    defer:
      removeFile(pathA)
      removeFile(pathB)
    discard e.loadFile(pathA)

    let bufB = newTextBuffer("")
    check bufB.loadFile(pathB).isOk
    e.addBuffer(bufB)

    e.seedOverlayCaches(e.activeBuffer.id)
    writeFile(pathB, "background changed")
    check bufB.loadFile(pathB).isOk

    check e.allOverlaysValid()

  test "reloading the buffer the overlays belong to drops them":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_overlay_scope_own.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)
    discard e.loadFile(path)

    e.seedOverlayCaches(e.activeBuffer.id)
    writeFile(path, "changed")
    check e.reloadCurrentFile().isOk

    check not e.anyOverlayValid()

suite "editor_reload - unchanged bytes are recognised after normalization":
  # The load normalizes line endings, so re-serializing the buffer does not
  # reproduce the file it came from. Comparing the two would report a change
  # for every external write, however harmless, and reload a CRLF file on
  # every `touch` — dropping its undo history each time.
  proc reloadIsSkippedFor(content: string, name: string) =
    let e = createTestEditor()
    let path = getTempDir() / name
    writeFile(path, content)
    defer:
      removeFile(path)
    discard e.loadFile(path)
    let buf = e.activeBuffer
    let versionBefore = buf.contentVersion

    sleep(50)
    writeFile(path, content)
    check buf.isExternallyModified()
    e.state.timing.lastFileModCheck = pastMonoTime(5000)
    e.maybeReloadExternallyModifiedFile()

    # An untouched contentVersion is the proof: a reload always advances it.
    check buf.contentVersion == versionBefore
    check not buf.isExternallyModified()

  test "a CRLF file is not reloaded by a rewrite of the same bytes":
    reloadIsSkippedFor("a\r\nb\r\nc\r\n", "moe_test_reload_crlf.txt")

  test "a file without a trailing newline is not reloaded by the same bytes":
    reloadIsSkippedFor("a\nb\nc", "moe_test_reload_noeol.txt")

  test "a file with mixed line endings is not reloaded by the same bytes":
    reloadIsSkippedFor("a\r\nb\nc\r\n", "moe_test_reload_mixed.txt")

  test "a rewrite that does change the bytes still reloads":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_crlf_changed.txt"
    writeFile(path, "a\r\nb\r\n")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    let buf = e.activeBuffer

    sleep(50)
    writeFile(path, "a\r\nb\r\nc\r\n")
    e.state.timing.lastFileModCheck = pastMonoTime(5000)
    e.maybeReloadExternallyModifiedFile()

    check buf.len == 3
    check buf.getLine(2) == "c"

suite "editor_reload - every position naming the buffer survives a shrink":
  test "nothing is left pointing past the new end":
    # A net over the individual cases: whatever position-keyed state the editor
    # grows, a reload to a shorter file must leave none of it out of range.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_shrink_all.txt"
    writeFile(path, "aaaa\nbbbb\ncccc\ndddd\neeee\nffff")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    let buf = e.activeBuffer

    e.cursor = BufferPosition(line: 5, column: 3)
    e.state.preferredColumn = 3
    e.activeWindow.viewport.topLine = 4
    e.state.matchingParenPos = some(BufferPosition(line: 5, column: 2))
    e.state.input.search.startPos = BufferPosition(line: 5, column: 0)
    e.state.jumpList.list = @[
      JumpPosition(bufferId: buf.id, line: 5, column: 3),
      JumpPosition(bufferId: buf.id, line: 0, column: 0),
    ]

    sleep(50)
    writeFile(path, "a")
    check e.reloadCurrentFile().isOk

    check buf.len == 1
    for window in e.windowManager.windows:
      if window.buffer == buf:
        check window.cursor.line < buf.len
        check window.cursor.column <= buf.getLine(window.cursor.line).len
        check window.preferredColumn <= buf.getLine(window.cursor.line).len
        check window.viewport.topLine < buf.len
    check e.state.matchingParenPos.isNone
    check e.state.input.search.startPos.line < buf.len
    for jump in e.state.jumpList.list:
      check jump.line < buf.len

suite "editor_reload - a failed load leaves no half-registered buffer":
  test "the buffer is unregistered again when the load fails":
    when defined(posix):
      if getuid() != 0:
        let e = createTestEditor()
        let path = getTempDir() / "moe_test_reload_unreadable.txt"
        writeFile(path, "secret")
        setFilePermissions(path, {})
        defer:
          setFilePermissions(path, {fpUserRead, fpUserWrite})
          removeFile(path)

        let countBefore = e.buffers.len
        check e.loadOrCreateBuffer(path).isErr
        check e.buffers.len == countBefore
        check e.findBufferByPath(path) < 0

suite "editor_window - opening a file in a split":
  test "the split buffer is registered and fully initialised":
    # The load moved out of the window manager and now goes through
    # `vsplitWithBuffer` with an already-registered buffer. That path exists to
    # show buffers the editor must NOT re-initialise, so this guards against
    # the delegation skipping the freshly loaded file's setup.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_split_registered.txt"
    writeFile(path, "a\nb\nc")
    defer:
      removeFile(path)

    let windowsBefore = e.windowManager.windows.len
    check e.vsplit(some(path)).isOk

    check e.windowManager.windows.len == windowsBefore + 1
    check e.findBufferByPath(path) >= 0
    let splitBuf = e.activeBuffer
    check splitBuf.filePath == some(path)
    check splitBuf.len == 3
    check e.activeWindow.buffer == splitBuf
    # `initLoadedBuffer` ran: conflict scanning is part of it, and a file with
    # no markers must come back with none rather than an unscanned buffer.
    check splitBuf.conflictBlocks.len == 0

  test "a split on an unreadable file leaves no buffer behind":
    # The buffer is registered before the load now, so a failed load has to
    # unregister it again.
    when defined(posix):
      if getuid() != 0:
        let e = createTestEditor()
        let path = getTempDir() / "moe_test_split_unreadable.txt"
        writeFile(path, "secret")
        setFilePermissions(path, {})
        defer:
          setFilePermissions(path, {fpUserRead, fpUserWrite})
          removeFile(path)

        let countBefore = e.buffers.len
        let windowsBefore = e.windowManager.windows.len
        check e.vsplit(some(path)).isErr
        check e.buffers.len == countBefore
        check e.windowManager.windows.len == windowsBefore

suite "editor_reload - state a reload cannot be run under":
  test "owes the reload while a substitute preview is showing":
    # The preview mutates the buffer without a transaction, without touching
    # `changeSeq` and with the base mode showing, so none of the other edit
    # group tests catch it. Reloading under it would be written back on Esc.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_substitute.txt"
    writeFile(path, "foo\nfoo")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    e.startSubstitutePreview()
    e.updateSubstitutePreview("foo", "bar")
    check not e.activeBuffer.isModified

    sleep(50)
    writeFile(path, "changed on disk")
    e.state.timing.lastFileModCheck = pastMonoTime(5000)
    e.maybeReloadExternallyModifiedFile()

    check e.activeBuffer.reloadDeferred
    check e.activeBuffer.getLine(0) == "bar"

    # Leaving the preview restores the pre-preview text, and only then is the
    # buffer safe to reload.
    e.cancelSubstitutePreview()
    e.state.timing.lastFileModCheck = getMonoTime()
    e.maybeReloadExternallyModifiedFile()
    check e.activeBuffer.getLine(0) == "changed on disk"

  test "drops a preview snapshot when the contents are replaced anyway":
    # `:e!` and a backup restore do not go through the poll sweep, so the
    # snapshot has to be dropped where the replacement lands.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_substitute_forced.txt"
    writeFile(path, "foo")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    e.startSubstitutePreview()

    sleep(50)
    writeFile(path, "changed on disk")
    check e.reloadCurrentFile().isOk

    check not e.state.ui.substitutePreview.isActive
    e.cancelSubstitutePreview()
    check e.activeBuffer.getLine(0) == "changed on disk"

  test "drops an operator waiting for its motion":
    # `d` anchors at the position it was typed on; the next motion would build
    # a range from that anchor into text the reload dropped.
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_pending_operator.txt"
    writeFile(path, "a\nb\nc\nd\ne")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    e.cursor = BufferPosition(line: 4, column: 0)
    e.state.pendingInput.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 4, column: 0),
      )
    )

    sleep(50)
    writeFile(path, "a")
    check e.reloadCurrentFile().isOk

    check e.state.pendingInput.pendingOperator.isNone

  test "cancels the selection of a background window forced out of Visual":
    # The selection is one global: a background window on the reloaded buffer
    # leaves it naming text that is gone, and the accessors read it without
    # ever looking at a mode.
    let e = createTestEditor()
    let
      pathA = getTempDir() / "moe_test_reload_bg_visual_a.txt"
      pathB = getTempDir() / "moe_test_reload_bg_visual_b.txt"
    writeFile(pathA, "one\ntwo\nthree\nfour")
    writeFile(pathB, "b")
    defer:
      removeFile(pathA)
      removeFile(pathB)
    discard e.loadFile(pathA)
    let bufA = e.activeBuffer
    check e.vsplit(some(pathB)).isOk
    check e.activeBuffer != bufA

    var backgroundWindow: EditorWindow
    for window in e.windowManager.windows:
      if window.buffer == bufA:
        backgroundWindow = window
    check not backgroundWindow.isNil
    backgroundWindow.mode = EditorMode.VisualLine
    backgroundWindow.cursor = BufferPosition(line: 3, column: 0)
    e.state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 3, column: 0),
      active: true,
      kind: vskLine,
    )

    sleep(50)
    writeFile(pathA, "only")
    e.state.timing.lastFileModCheck = pastMonoTime(5000)
    e.maybeReloadExternallyModifiedFile()

    check bufA.getLine(0) == "only"
    check backgroundWindow.mode == EditorMode.Normal
    check not e.state.visualSelection.active

  test "clamps a jump list column onto a line that grew shorter":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_reload_jump_column.txt"
    writeFile(path, "aaaaaaaa\nbbbb")
    defer:
      removeFile(path)
    discard e.loadFile(path)
    let buf = e.activeBuffer
    e.state.jumpList.list = @[JumpPosition(bufferId: buf.id, line: 0, column: 7)]

    sleep(50)
    writeFile(path, "a\nbbbb")
    check e.reloadCurrentFile().isOk

    check e.state.jumpList.list[0].line == 0
    check e.state.jumpList.list[0].column < buf.getLine(0).len
