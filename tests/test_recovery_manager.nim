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

import std/[unittest, os, options, sequtils, strutils]

import pkg/results

import
  ../src/moepkg/[
    editor, editor_window, buffer, config, config_loader, emergency, message_log,
    recovery_format, recovery_store, recovery_manager, types, viewer_mode,
  ]
import ../src/moepkg/types/editor_types
import ../src/moepkg/key_bindings
import
  ../src/moepkg/command_handlers/
    [handler_result, recovery_manager_handler, recovery_ops, viewer_ops]

let TestRecoveryDir = getTempDir() / "moe_test_recovery_manager"

proc cleanupTestDir() =
  if dirExists(TestRecoveryDir):
    removeDir(TestRecoveryDir)

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  newEditor(config, vr)

proc preserveModified(e: Editor): seq[string] =
  ## Write every modified buffer of `e` into the test recovery directory.
  e.emergencySaveBuffers(ckCrash, baseDir = TestRecoveryDir)

proc openModified(e: Editor, path, diskContent, edited: string) =
  ## Put `path` on disk, open it and leave the buffer holding `edited`.
  writeFile(path, diskContent)
  discard e.loadFile(path)
  let buf = e.activeBuffer()
  check buf.replaceAllLines(edited.split('\n')).isOk

suite "recovery manager - what the list is about":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "A file's list holds only that file's preserved work":
    let e = createTestEditor()
    let fileA = getTempDir() / "moe_rcm_a.txt"
    let fileB = getTempDir() / "moe_rcm_b.txt"
    defer:
      removeFile(fileA)
      removeFile(fileB)

    e.openModified(fileA, "disk a", "edited a")
    let bufB = newTextBuffer("edited b", some(fileB))
    writeFile(fileB, "disk b")
    discard e.vsplitWithBuffer(bufB)
    bufB.changeSeq = bufB.savedSeq + 1
    check e.preserveModified().len == 2

    let state = initRecoveryManagerState(TestRecoveryDir, fileA)
    check state.items.len == 1
    check state.items[0].originalPath == fileA

  test "With no file to ask about, the list spans every preserved copy":
    let e = createTestEditor()
    let fileA = getTempDir() / "moe_rcm_all_a.txt"
    let fileB = getTempDir() / "moe_rcm_all_b.txt"
    defer:
      removeFile(fileA)
      removeFile(fileB)

    e.openModified(fileA, "disk a", "edited a")
    let bufB = newTextBuffer("edited b", some(fileB))
    writeFile(fileB, "disk b")
    discard e.vsplitWithBuffer(bufB)
    bufB.changeSeq = bufB.savedSeq + 1
    discard e.preserveModified()

    let state = initRecoveryManagerState(TestRecoveryDir, "")
    check state.items.len == 2

  test "A path is only worth a column when the list spans files":
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_column.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "edited")
    discard e.preserveModified()

    let entry = initRecoveryManagerState(TestRecoveryDir, file).items[0]
    check not entry.formatLine(withPath = false).contains(file)
    check entry.formatLine(withPath = true).contains(file)

suite "recovery manager - what a copy is worth":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "A copy the disk already holds says so":
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_same.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "edited")
    let saved = e.preserveModified()

    # The user saved after the crash: the copy has nothing left to give.
    writeFile(file, readFile(saved[0]))
    let entry = initRecoveryManagerState(TestRecoveryDir, file).items[0]
    check entry.matchesDisk
    check entry.noteFor == "already saved"

  test "A file written after the crash says so":
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_changed.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "edited")
    discard e.preserveModified()

    # A stamp only resolves to the second, so change the size too.
    writeFile(file, "written by someone else after the crash")
    let entry = initRecoveryManagerState(TestRecoveryDir, file).items[0]
    check entry.changedSince
    check entry.noteFor == "file changed since"

suite "recovery manager - discarding":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "Discarding the last copy takes the session with it":
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_discard_one.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "edited")
    let saved = e.preserveModified()
    let sessionDir = saved[0].parentDir

    let state = initRecoveryManagerState(TestRecoveryDir, file)
    var reason = ""
    check state.discardEntry(0, reason)
    check state.items.len == 0
    check not dirExists(sessionDir)

  test "Discarding one copy leaves the rest of the session alone":
    let e = createTestEditor()
    let fileA = getTempDir() / "moe_rcm_keep_a.txt"
    let fileB = getTempDir() / "moe_rcm_keep_b.txt"
    defer:
      removeFile(fileA)
      removeFile(fileB)

    e.openModified(fileA, "disk a", "edited a")
    let bufB = newTextBuffer("edited b", some(fileB))
    writeFile(fileB, "disk b")
    discard e.vsplitWithBuffer(bufB)
    bufB.changeSeq = bufB.savedSeq + 1
    let saved = e.preserveModified()
    let sessionDir = saved[0].parentDir

    let state = initRecoveryManagerState(TestRecoveryDir, fileA)
    var reason = ""
    check state.discardEntry(0, reason)
    check dirExists(sessionDir)
    check initRecoveryManagerState(TestRecoveryDir, fileB).items.len == 1

suite "recovery manager - restoring":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  proc enterRecovery(e: Editor, state: RecoveryManagerState) =
    check e.enterViewerMode(
      EditorMode.RecoveryManager,
      ModeState(kind: mskRecoveryManager, recoveryManager: state),
      state.createRecoveryManagerTextBuffer(),
      vpVSplit,
    ).isOk

  test "Restoring puts the preserved text back in the buffer, unsaved":
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_restore.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "work that was never saved")
    discard e.preserveModified()

    # The session came back with the file as the disk left it.
    let buf = e.activeBuffer()
    check buf.replaceAllLines(["disk"]).isOk
    buf.savedSeq = buf.changeSeq

    let state = initRecoveryManagerState(TestRecoveryDir, file)
    e.enterRecovery(state)
    check e.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )

    check buf.getLine(0) == "work that was never saved"
    check buf.len == 1
    # Restoring is an edit, not a save: the file still holds what it held.
    check readFile(file) == "disk"
    check buf.isModified

  test "Restoring is one undo away":
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_undo.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "preserved")
    discard e.preserveModified()

    let buf = e.activeBuffer()
    check buf.replaceAllLines(["disk"]).isOk

    let state = initRecoveryManagerState(TestRecoveryDir, file)
    e.enterRecovery(state)
    check e.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )
    check buf.getLine(0) == "preserved"

    check buf.undo().isOk
    check buf.getLine(0) == "disk"

  test "A copy whose file is not open opens it":
    # The list is most useful right after the crash, when nothing is open yet.
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_closed.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "preserved")
    discard e.preserveModified()

    # Widen the list, then take the file away from the editor.
    let state = initRecoveryManagerState(TestRecoveryDir, "")
    let other = createTestEditor()
    other.enterRecovery(state)
    check other.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )

    let index = other.findBufferByPath(file)
    check index >= 0
    check other.buffers[index].getLine(0) == "preserved"
    check other.buffers[index].isModified
    check other.state.statusMessage.contains("Opened")
    check readFile(file) == "disk"

  test "A copy that matches the file it opens still says it opened it":
    # The restore put a file in front of the user; a message about the diff
    # would report that nothing happened.
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_same.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "preserved")
    discard e.preserveModified()
    # The file caught up with the copy, so the restore changes no line.
    writeFile(file, "preserved")

    let other = createTestEditor()
    other.enterRecovery(initRecoveryManagerState(TestRecoveryDir, ""))
    check other.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )
    check other.activeWindow.buffer.filePath == some(file)
    check other.state.statusMessage.contains("Opened")

  test "A copy from an unnamed buffer lands in a new buffer":
    # Text that was never written anywhere is the least replaceable thing a
    # crash preserves, so it cannot be the one kind with nowhere to go.
    let e = createTestEditor()
    check e.activeBuffer().replaceAllLines(["never named"]).isOk
    discard e.preserveModified()

    let state = initRecoveryManagerState(TestRecoveryDir, "")
    check state.items.len == 1
    check state.items[0].originalPath.len == 0

    let other = createTestEditor()
    other.enterRecovery(state)
    check other.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )
    check other.activeWindow.buffer.getLine(0) == "never named"
    check other.state.statusMessage.contains("new buffer")

  test "A restore shows what it restored":
    # Restored text is unsaved work that only `u` takes back, so leaving it in a
    # buffer behind the listing is what would let `:wa` write it unseen.
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_shows.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "preserved")
    discard e.preserveModified()

    let state = initRecoveryManagerState(TestRecoveryDir, "")
    let other = createTestEditor()
    other.enterRecovery(state)
    check other.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )

    check other.state.mode != EditorMode.RecoveryManager
    let shown = other.activeWindow.buffer
    check shown.filePath == some(file)
    check shown.getLine(0) == "preserved"
    check shown.id in other.activeWindow.bufferIds

  test "A restore that fails leaves the buffer list as it found it":
    # `replaceAllLines` refuses a raw-bytes buffer, and the file it opened to
    # hold the copy is in no window and holds nothing the user asked for.
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_failed.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "preserved")
    discard e.preserveModified()

    # Take the file away from the editor and leave bytes behind it that no
    # decoding accepts: a UTF-16 BOM over an odd number of bytes.
    writeFile(file, "\xFF\xFEodd")

    let state = initRecoveryManagerState(TestRecoveryDir, "")
    let other = createTestEditor()
    other.enterRecovery(state)
    let before = other.buffers.len
    check other.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )
    check other.state.statusMessage.contains("Failed to restore")
    check other.buffers.len == before
    check other.findBufferByPath(file) < 0

  test "A copy of a CR file comes back as lines, not one run-on line":
    # The copy is written the way a save writes: in the buffer's own line
    # ending, which splitting on \n alone would collapse into one line.
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_cr.txt"
    defer:
      removeFile(file)
    writeFile(file, "one\rtwo\rthree\r")
    discard e.loadFile(file)
    let buf = e.activeBuffer()
    check buf.lineEnding == CR
    check buf.replaceAllLines(["alpha", "beta", "gamma"]).isOk
    discard e.preserveModified()
    check buf.replaceAllLines(["disk"]).isOk

    let state = initRecoveryManagerState(TestRecoveryDir, file)
    e.enterRecovery(state)
    check e.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )
    check buf.len == 3
    check buf.getLine(0) == "alpha"
    check buf.getLine(2) == "gamma"

  test "A copy of a file with a BOM comes back without it":
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_bom.txt"
    defer:
      removeFile(file)
    writeFile(file, "\xEF\xBB\xBFone\n")
    discard e.loadFile(file)
    let buf = e.activeBuffer()
    check buf.hasBom
    check buf.replaceAllLines(["alpha"]).isOk
    discard e.preserveModified()
    check buf.replaceAllLines(["disk"]).isOk

    let state = initRecoveryManagerState(TestRecoveryDir, file)
    e.enterRecovery(state)
    check e.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )
    check buf.getLine(0) == "alpha"

  test "A copy of a UTF-16 file comes back decoded":
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_utf16.txt"
    defer:
      removeFile(file)
    writeFile(file, "\xFF\xFEo\x00n\x00e\x00\n\x00")
    discard e.loadFile(file)
    let buf = e.activeBuffer()
    check buf.encoding == CharacterEncoding.utf16Le
    check buf.getLine(0) == "one"
    check buf.replaceAllLines(["alpha"]).isOk
    discard e.preserveModified()
    check buf.replaceAllLines(["disk"]).isOk

    let state = initRecoveryManagerState(TestRecoveryDir, file)
    e.enterRecovery(state)
    check e.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )
    check buf.len == 1
    check buf.getLine(0) == "alpha"

  test "A copy restored into a file that is gone keeps how it was written":
    # The file a restore opens is the authority for how a save writes it --
    # except when there is no file left, where the copy is the only record.
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_gone_crlf.txt"
    defer:
      removeFile(file)
    writeFile(file, "one\r\ntwo\r\n")
    discard e.loadFile(file)
    let buf = e.activeBuffer()
    check buf.lineEnding == CRLF
    check buf.replaceAllLines(["alpha", "beta"]).isOk
    discard e.preserveModified()
    removeFile(file)

    let other = createTestEditor()
    other.enterRecovery(initRecoveryManagerState(TestRecoveryDir, ""))
    check other.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )
    let restored = other.activeWindow.buffer
    check restored.filePath == some(file)
    check restored.lineEnding == CRLF
    check restored.getFileContent == "alpha\r\nbeta\r\n"

  test "A copy restored into an open buffer whose file is gone keeps how it was written":
    # Same as above, except the path is already open here. The buffer was made
    # after the file went, so it holds the defaults and knows nothing of how
    # the work was written; only the copy does.
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_open_gone_crlf.txt"
    defer:
      removeFile(file)
    writeFile(file, "one\r\ntwo\r\n")
    discard e.loadFile(file)
    let buf = e.activeBuffer()
    check buf.lineEnding == CRLF
    check buf.replaceAllLines(["alpha", "beta"]).isOk
    discard e.preserveModified()
    removeFile(file)

    let other = createTestEditor()
    discard other.loadFile(file)
    check other.activeBuffer().lineEnding == LF
    let existing = other.activeBuffer()
    other.enterRecovery(initRecoveryManagerState(TestRecoveryDir, ""))
    check other.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )
    let restored = other.activeWindow.buffer
    # The restore went into the buffer that was already there.
    check restored == existing
    check restored.filePath == some(file)
    check restored.lineEnding == CRLF
    check restored.getFileContent == "alpha\r\nbeta\r\n"

  test "A restore into unsaved work of its own leaves that work as it was":
    # The shape is set outside the undo entry, so a buffer holding work of its
    # own keeps its own: `u` would bring the lines back under a line ending
    # the user never chose, and the next `:w` would write their work that way.
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_own_work_crlf.txt"
    defer:
      removeFile(file)
    writeFile(file, "one\r\ntwo\r\n")
    discard e.loadFile(file)
    check e.activeBuffer().replaceAllLines(["alpha", "beta"]).isOk
    discard e.preserveModified()
    removeFile(file)

    let other = createTestEditor()
    discard other.loadFile(file)
    let existing = other.activeBuffer()
    check existing.lineEnding == LF
    check existing.replaceAllLines(["my own unsaved work"]).isOk
    other.enterRecovery(initRecoveryManagerState(TestRecoveryDir, ""))
    check other.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )
    check existing.getLine(0) == "alpha"
    check existing.lineEnding == LF

    check existing.undo().isOk
    check existing.getLine(0) == "my own unsaved work"
    check existing.lineEnding == LF
    check not existing.getFileContent.contains("\r")

  test "A copy whose bytes no decoding accepts is refused, not sanitized":
    # A raw-bytes buffer refuses a restore; whether the file it came from is
    # still there must not decide it. Going ahead would turn every byte that
    # did not decode into U+FFFD and report a restore over the only copy left.
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_raw_copy.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "preserved")
    let copies = e.preserveModified()
    check copies.len == 1
    # A UTF-16 BOM over an odd number of bytes: the copy now holds what a raw
    # buffer would have been preserved as.
    writeFile(copies[0], "\xFF\xFEodd")
    removeFile(file)

    let other = createTestEditor()
    other.enterRecovery(initRecoveryManagerState(TestRecoveryDir, ""))
    let before = other.buffers.len
    check other.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )
    check other.state.statusMessage.contains("Failed to restore")
    check other.buffers.len == before

  test "A restore clamps the cursor of the window showing the target":
    # The target is in another split, so nothing else notices that the text
    # its cursor named is gone.
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_clamp.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "preserved")
    discard e.preserveModified()

    let buf = e.activeBuffer()
    var long: seq[string]
    for i in 0 ..< 200:
      long.add "line " & $i
    check buf.replaceAllLines(long).isOk
    let sourceWindow = e.activeWindow
    sourceWindow.cursor = BufferPosition(line: 150, column: 0)

    let state = initRecoveryManagerState(TestRecoveryDir, file)
    e.enterRecovery(state)
    check e.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )
    check buf.len == 1
    check sourceWindow.cursor.line == 0

suite "recovery manager - what a session recorded":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "The recorded detail reaches the row":
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_detail.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "edited")
    discard e.emergencySaveBuffers(ckCrash, "index 5 out of bounds", TestRecoveryDir)

    let entry = initRecoveryManagerState(TestRecoveryDir, file).items[0]
    check entry.detail == "index 5 out of bounds"
    check entry.formatLine(withPath = false).contains("index 5 out of bounds")

  test "A detail that is long or multi-line is cut down to one row":
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_detail_long.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "edited")
    let detail = "first line\n" & "x".repeat(200)
    discard e.emergencySaveBuffers(ckCrash, detail, TestRecoveryDir)

    let entry = initRecoveryManagerState(TestRecoveryDir, file).items[0]
    let line = entry.formatLine(withPath = false)
    check not line.contains("\n")
    check line.len < detail.len

  test "A session that recorded no detail says nothing extra":
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_detail_none.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "edited")
    discard e.preserveModified()

    let entry = initRecoveryManagerState(TestRecoveryDir, file).items[0]
    check entry.shownDetail.len == 0
    check not entry.formatLine(withPath = false).contains(": ")

suite "recovery manager - metadata a row must not trust":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "A control character in the metadata cannot add a row":
    # Detail and file names are free text. A newline reaching the row would
    # shift every row below it out of sync with the selection.
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_sanitize.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "edited")
    discard e.emergencySaveBuffers(ckCrash, "detail\nfake row", TestRecoveryDir)

    let state = initRecoveryManagerState(TestRecoveryDir, "")
    require state.items.len == 1
    check not state.items[0].formatLine(withPath = true).contains("\n")
    check state.createRecoveryManagerTextBuffer().len == 2

suite "recovery manager - widening the list":
  ## `:recover!` goes through `processViewerResult`, which reads the real
  ## recovery directory, so these move HOME as the notice tests do.
  let fakeHome = getTempDir() / "moe_test_recovery_widen_home"
  var realHome: string

  setup:
    realHome = getEnv("HOME")
    removeDir(fakeHome)
    createDir(fakeHome)
    putEnv("HOME", fakeHome)

  teardown:
    putEnv("HOME", realHome)
    removeDir(fakeHome)

  test "`:recover!` reaches a copy no file can ask about":
    let file = getTempDir() / "moe_rcm_widen.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "edited")
    let scratch = newTextBuffer()
    crashed.addBuffer(scratch)
    check scratch.replaceAllLines(@["never named"]).isOk
    check crashed.emergencySaveBuffers(ckCrash).len == 2

    let e = createTestEditor()
    discard e.loadFile(file)
    check e.processViewerResult(
      HandlerResult(kind: hrEnterRecoveryManager, allRecovery: true)
    )
    let state = e.activeWindow.modeState.recoveryManager
    check state.sourceFilePath.len == 0
    check state.items.len == 2

  test "`:recover` from a named buffer stays about that file":
    let file = getTempDir() / "moe_rcm_narrow.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "edited")
    let scratch = newTextBuffer()
    crashed.addBuffer(scratch)
    check scratch.replaceAllLines(@["never named"]).isOk
    check crashed.emergencySaveBuffers(ckCrash).len == 2

    let e = createTestEditor()
    discard e.loadFile(file)
    check e.processViewerResult(HandlerResult(kind: hrEnterRecoveryManager))
    let state = e.activeWindow.modeState.recoveryManager
    check state.sourceFilePath.len > 0
    check state.items.len == 1

  test "`:recover!` widens a list that is already open":
    # Focusing alone would make the `!` a no-op, leaving the unnamed copy
    # unreachable until the split is closed.
    let file = getTempDir() / "moe_rcm_widen_open.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "edited")
    let scratch = newTextBuffer()
    crashed.addBuffer(scratch)
    check scratch.replaceAllLines(@["never named"]).isOk
    check crashed.emergencySaveBuffers(ckCrash).len == 2

    let e = createTestEditor()
    discard e.loadFile(file)
    check e.processViewerResult(HandlerResult(kind: hrEnterRecoveryManager))
    check e.activeWindow.modeState.recoveryManager.items.len == 1

    check e.processViewerResult(
      HandlerResult(kind: hrEnterRecoveryManager, allRecovery: true)
    )
    let widened = e.activeWindow.modeState.recoveryManager
    check widened.sourceFilePath.len == 0
    check widened.items.len == 2
    # The rows the window shows are the widened ones, not the list it replaced.
    check e.activeWindow.buffer.len == widened.items.len + 1

  test "`:recover` in the open list reads it again":
    # Another editor may have discarded a session since the list was built.
    let file = getTempDir() / "moe_rcm_reread.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "edited")
    check crashed.emergencySaveBuffers(ckCrash).len == 1

    let e = createTestEditor()
    discard e.loadFile(file)
    check e.processViewerResult(HandlerResult(kind: hrEnterRecoveryManager))
    check e.activeWindow.modeState.recoveryManager.items.len == 1

    # Stands in for the other editor: the copy goes, this list does not know.
    let gone = e.activeWindow.modeState.recoveryManager.items[0]
    var reason = ""
    check newRecoveryStore(getCrashRecoveryBaseDir()).discardCopy(
      gone.copyPath, gone.sessionDir, reason
    )

    check e.processViewerResult(HandlerResult(kind: hrEnterRecoveryManager))
    let refreshed = e.activeWindow.modeState.recoveryManager
    # Still about the same file, and holding what is there now.
    check refreshed.sourceFilePath.len > 0
    check refreshed.items.len == 0

suite "recovery manager - discarding asks first":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  proc listWithOneCopy(): RecoveryManagerState =
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_arm.txt"
    e.openModified(file, "disk", "edited")
    discard e.preserveModified()
    removeFile(file)
    initRecoveryManagerState(TestRecoveryDir, file)

  test "The first D asks and the second one discards":
    let state = listWithOneCopy()
    check state.items.len == 1

    let asked = state.handleRecoveryManagerModeKey(10, toKeyCombo('D'))
    check asked.kind == rcmrArmDiscard
    check fileExists(state.items[0].copyPath)

    let done = state.handleRecoveryManagerModeKey(10, toKeyCombo('D'))
    check done.kind == rcmrDiscard
    check done.discardIndex == 0

  test "Anything in between takes the question back":
    let state = listWithOneCopy()
    check state.handleRecoveryManagerModeKey(10, toKeyCombo('D')).kind == rcmrArmDiscard
    check state.handleRecoveryManagerModeKey(10, toKeyCombo('r')).kind == rcmrRefresh
    # The D after that asks again rather than discarding.
    check state.handleRecoveryManagerModeKey(10, toKeyCombo('D')).kind == rcmrArmDiscard

  test "Enter does not restore; R asks for it":
    # Enter is the key for looking at a row, and a restore replaces the whole
    # buffer it lands in.
    let state = listWithOneCopy()
    let enter = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    check state.handleRecoveryManagerModeKey(10, enter).kind == rcmrHandled
    check state.handleRecoveryManagerModeKey(10, toKeyCombo('R')).kind == rcmrRestore
