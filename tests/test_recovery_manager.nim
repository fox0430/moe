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

import std/[deques, unittest, os, options, sequtils, strutils, tables, times]

when defined(posix):
  from std/posix import getuid, mkfifo

import pkg/results

import
  ../src/moepkg/[
    editor, editor_window, editor_reload, buffer, config, config_loader, emergency,
    message_log, recovery_format, recovery_index, recovery_manager, recovery_notice,
    types, viewer_mode,
  ]
import ../src/moepkg/types/editor_types
import ../src/moepkg/key_bindings
import
  ../src/moepkg/command_handlers/
    [handler_result, recovery_manager_handler, recovery_ops, viewer_ops]

let TestRecoveryDir = getTempDir() / "moe_test_recovery_manager"

proc permissionsAreEnforced(): bool =
  ## False for root: a missing permission bit does not deny access.
  when defined(posix):
    getuid() != 0
  else:
    false

proc cleanupTestDir() =
  if dirExists(TestRecoveryDir):
    removeDir(TestRecoveryDir)

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  newEditor(config, vr)

proc createNoticeEditor(): Editor =
  ## An editor that knows the test recovery directory as it is now, as `main`
  ## points one at the user's.
  result = createTestEditor()
  result.recovery = some(newRecoveryIndex(TestRecoveryDir))

proc preserveModified(e: Editor): seq[string] =
  ## Write every modified buffer of `e` into the test recovery directory.
  e.emergencySaveBuffers(ckCrash, baseDir = TestRecoveryDir)

proc enterRecovery(e: Editor, state: RecoveryManagerState) =
  check e.enterViewerMode(
    EditorMode.RecoveryManager,
    ModeState(kind: mskRecoveryManager, recoveryManager: state),
    state.createRecoveryManagerTextBuffer(),
    vpVSplit,
  ).isOk

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

    let state = initRecoveryManagerState(TestRecoveryDir, fileA, [])
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

    let state = initRecoveryManagerState(TestRecoveryDir, "", [])
    check state.items.len == 2

  test "A path is only worth a column when the list spans files":
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_column.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "edited")
    discard e.preserveModified()

    let entry = initRecoveryManagerState(TestRecoveryDir, file, []).items[0]
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
    let entry = initRecoveryManagerState(TestRecoveryDir, file, []).items[0]
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
    let entry = initRecoveryManagerState(TestRecoveryDir, file, []).items[0]
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

    let state = initRecoveryManagerState(TestRecoveryDir, file, [])
    var reason = ""
    check state.discardEntry(0, reason, [])
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

    let state = initRecoveryManagerState(TestRecoveryDir, fileA, [])
    var reason = ""
    check state.discardEntry(0, reason, [])
    check dirExists(sessionDir)
    check initRecoveryManagerState(TestRecoveryDir, fileB, []).items.len == 1

  test "Discarding a copy leaves what a linked reviewed directory points at alone":
    when defined(posix):
      let e = createTestEditor()
      let file = getTempDir() / "moe_rcm_discard_linked_reviewed.txt"
      let outside = getTempDir() / "moe_rcm_discard_linked_reviewed_target"
      createDir(outside)
      defer:
        removeFile(file)
        removeDir(outside)
      e.openModified(file, "disk", "edited")
      let saved = e.preserveModified()
      require saved.len == 1
      let victim = outside / saved[0].lastPathPart
      writeFile(victim, "not the store's")
      createSymlink(outside, saved[0].parentDir.parentDir / ReviewedDirName)

      let state = initRecoveryManagerState(TestRecoveryDir, file, [])
      var reason = ""
      check state.discardEntry(0, reason, [])
      check fileExists(victim)

  test "Marking a copy does not move a session with no recorded time":
    # Such a session is ordered by its copies, which a mark does not touch.
    let older = TestRecoveryDir / "20260920T000000_5"
    let newer = TestRecoveryDir / "20260920T000000_6"
    for dir in [older, newer]:
      createDir(dir / PayloadDirName)
      writeFile(dir / PayloadDirName / "0000-half.txt", "half written")
    let now = getTime()
    setLastModificationTime(older / PayloadDirName / "0000-half.txt", now - 100.seconds)
    setLastModificationTime(newer / PayloadDirName / "0000-half.txt", now - 50.seconds)
    for dir in [older, newer]:
      setLastModificationTime(dir, now - 200.seconds)

    let store = newRecoveryStore(TestRecoveryDir)
    check store.sessions().mapIt(it.dir) == @[newer, older]
    var reason = ""
    check store.setReviewed(
      older / PayloadDirName / "0000-half.txt", older, true, reason
    )
    check store.sessions().mapIt(it.dir) == @[newer, older]

proc openModifiedBehind(e: Editor, path, diskContent, edited: string): TextBuffer =
  ## Like `openModified`, into a buffer of its own that nothing shows.
  writeFile(path, diskContent)
  result = e.loadOrCreateBuffer(path).get
  check result.replaceAllLines(edited.split('\n')).isOk

suite "recovery manager - restoring":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

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

    let state = initRecoveryManagerState(TestRecoveryDir, file, e.buffers)
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

    let state = initRecoveryManagerState(TestRecoveryDir, file, e.buffers)
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
    let other = createTestEditor()
    let state = initRecoveryManagerState(TestRecoveryDir, "", other.buffers)
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
    other.enterRecovery(initRecoveryManagerState(TestRecoveryDir, "", other.buffers))
    check other.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )
    check other.activeWindow.buffer.filePath == some(file)
    check other.state.statusMessage.contains("Opened")
    # Settled on the spot, so it does not ask for a save.
    check other.state.statusMessage.contains("the file already has it")
    check not other.state.statusMessage.contains("not saved yet")

  test "A copy from an unnamed buffer lands in a new buffer":
    # Text that was never written anywhere is the least replaceable thing a
    # crash preserves, so it cannot be the one kind with nowhere to go.
    let e = createTestEditor()
    check e.activeBuffer().replaceAllLines(["never named"]).isOk
    discard e.preserveModified()

    let other = createTestEditor()
    let state = initRecoveryManagerState(TestRecoveryDir, "", other.buffers)
    check state.items.len == 1
    check state.items[0].originalPath.len == 0

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

    let other = createTestEditor()
    let state = initRecoveryManagerState(TestRecoveryDir, "", other.buffers)
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

    let other = createTestEditor()
    let state = initRecoveryManagerState(TestRecoveryDir, "", other.buffers)
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

    let state = initRecoveryManagerState(TestRecoveryDir, file, e.buffers)
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

    let state = initRecoveryManagerState(TestRecoveryDir, file, e.buffers)
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

    let state = initRecoveryManagerState(TestRecoveryDir, file, e.buffers)
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
    other.enterRecovery(initRecoveryManagerState(TestRecoveryDir, "", other.buffers))
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
    other.enterRecovery(initRecoveryManagerState(TestRecoveryDir, "", other.buffers))
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
    other.enterRecovery(initRecoveryManagerState(TestRecoveryDir, "", other.buffers))
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
    other.enterRecovery(initRecoveryManagerState(TestRecoveryDir, "", other.buffers))
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

    let state = initRecoveryManagerState(TestRecoveryDir, file, e.buffers)
    e.enterRecovery(state)
    check e.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )
    check buf.len == 1
    check sourceWindow.cursor.line == 0

suite "recovery manager - the mark a file carries":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "A file whose work a crash preserved carries the mark":
    let file = getTempDir() / "moe_rcm_mark.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    discard e.loadFile(file)
    check e.owesPreservedWork(e.activeBuffer)

  test "The mark outlasts whatever the status line says next":
    # Every open command writes its own message; a notice raised on the way
    # into the buffer never survived it.
    let file = getTempDir() / "moe_rcm_mark_outlasts.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    discard e.loadFile(file)
    e.state.statusMessage = "Opened: " & file
    check e.owesPreservedWork(e.activeBuffer)

  test "Every file opened carries its own mark, shown or not":
    # One status line cannot name them all; each buffer carries its own.
    let a = getTempDir() / "moe_rcm_mark_a.txt"
    let b = getTempDir() / "moe_rcm_mark_b.txt"
    defer:
      removeFile(a)
      removeFile(b)

    let crashed = createTestEditor()
    crashed.openModified(a, "disk a", "work a")
    discard crashed.openModifiedBehind(b, "disk b", "work b")
    check crashed.preserveModified().len == 2

    let e = createNoticeEditor()
    discard e.loadFile(a)
    check e.loadOrCreateBuffer(b).isOk
    for path in [a, b]:
      let index = e.findBufferByPath(path)
      require index >= 0
      check e.owesPreservedWork(e.buffers[index])

  test "A copy the file already holds carries no mark":
    # Nothing is left to recover, as the list says.
    let file = getTempDir() / "moe_rcm_mark_saved.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    let saved = crashed.preserveModified()
    check saved.len == 1
    writeFile(file, readFile(saved[0]))

    let e = createNoticeEditor()
    discard e.loadFile(file)
    check not e.owesPreservedWork(e.activeBuffer)
    let state = initRecoveryManagerState(e.recovery.get, file, e.buffers)
    require state.items.len == 1
    check state.items[0].noteFor == "already saved"
    # Seen on load, so it is settled for later sessions too.
    check newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "Editing and saving a file that held its copy does not bring the mark back":
    # What was in the file when it was read is what counts, not what the
    # buffer last read.
    let file = getTempDir() / "moe_rcm_mark_saved_edit.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    let saved = crashed.preserveModified()
    check saved.len == 1
    writeFile(file, readFile(saved[0]))

    let e = createNoticeEditor()
    discard e.loadFile(file)
    let buf = e.activeBuffer
    check buf.replaceAllLines(@["the user's own later edit"]).isOk
    check e.saveAllBuffers().failures.len == 0
    check not e.owesPreservedWork(buf)

  test "A file that caught up with its copy settles it when reloaded":
    let file = getTempDir() / "moe_rcm_mark_reload.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    let saved = crashed.preserveModified()
    check saved.len == 1

    let e = createNoticeEditor()
    discard e.loadFile(file)
    let buf = e.activeBuffer
    check e.owesPreservedWork(buf)
    writeFile(file, readFile(saved[0]))
    check buf.reloadFileIfContentChanged().get
    e.finishReload(buf, file, announce = false)
    check not e.owesPreservedWork(buf)

  test "Any read of the file settles a copy it holds, however it is reached":
    # A backup restore reads the file straight into the buffer; no editor-level
    # load or reload is involved.
    let file = getTempDir() / "moe_rcm_mark_any_read.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    let saved = crashed.preserveModified()
    check saved.len == 1

    let e = createNoticeEditor()
    discard e.loadFile(file)
    let buf = e.activeBuffer
    check e.owesPreservedWork(buf)
    writeFile(file, readFile(saved[0]))
    check buf.loadFile(file).isOk
    check not e.owesPreservedWork(buf)

  test "A buffer registered after it read its file settles what the file holds":
    let file = getTempDir() / "moe_rcm_mark_registered_late.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    let saved = crashed.preserveModified()
    check saved.len == 1
    writeFile(file, readFile(saved[0]))

    let e = createNoticeEditor()
    let buf = newTextBuffer("")
    check buf.loadFile(file).isOk
    e.addBuffer(buf)
    check not e.owesPreservedWork(buf)

  test "Saving what a copy holds settles it":
    let file = getTempDir() / "moe_rcm_mark_save_same.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    discard e.loadFile(file)
    let buf = e.activeBuffer
    check e.owesPreservedWork(buf)
    check buf.replaceAllLines(@["work that was never saved"]).isOk
    check e.saveAllBuffers().failures.len == 0
    check not e.owesPreservedWork(buf)

  test "A file that is not there holds no empty copy":
    # Opening a missing path reads nothing, which fingerprints like an empty
    # file.
    let file = getTempDir() / "moe_rcm_mark_empty_gone.txt"
    discard tryRemoveFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "")
    let saved = crashed.preserveModified()
    require saved.len == 1
    require getFileSize(saved[0]) == 0
    removeFile(file)

    let e = createNoticeEditor()
    discard e.loadFile(file)
    require e.activeBuffer.lastLoadedContent.get.size == 0
    check e.owesPreservedWork(e.activeBuffer)
    check not newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "A fingerprint that matches bytes that do not is not enough to mark":
    # The mark is for good, so the bytes decide, not the hash.
    let file = getTempDir() / "moe_rcm_mark_collision.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    let saved = crashed.preserveModified()
    require saved.len == 1

    let e = createNoticeEditor()
    discard e.loadFile(file)
    let buf = e.activeBuffer
    # As if the copy's bytes hashed like the file's.
    e.recovery.get.copyPrints[saved[0]] = CopyPrint(
      size: buf.lastLoadedContent.get.size.int64, print: buf.lastLoadedContent
    )
    for reason in e.recovery.get.noteObserved(buf):
      discard reason
    check e.owesPreservedWork(buf)
    check not newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "A copy that could not be read is read again after a refresh":
    let crashed = createTestEditor()
    let file = getTempDir() / "moe_rcm_mark_unreadable.txt"
    defer:
      removeFile(file)
    crashed.openModified(file, "disk", "work that was never saved")
    let saved = crashed.preserveModified()
    require saved.len == 1

    let index = newRecoveryIndex(TestRecoveryDir)
    index.copyPrints[saved[0]] = CopyPrint(size: -1)
    index.refresh()
    check saved[0] notin index.copyPrints

  test "A copy that is not a regular file is never read":
    # A pipe reports size 0, the size of an empty file; reading it would hang
    # the redraw.
    when defined(posix):
      let file = getTempDir() / "moe_rcm_mark_fifo_copy.txt"
      defer:
        removeFile(file)

      let crashed = createTestEditor()
      crashed.openModified(file, "", "work that was never saved")
      let saved = crashed.preserveModified()
      require saved.len == 1
      removeFile(saved[0])
      require mkfifo(saved[0].cstring, 0o600) == 0

      let e = createNoticeEditor()
      discard e.loadFile(file)
      require e.activeBuffer.lastLoadedContent.get.size == 0
      check e.owesPreservedWork(e.activeBuffer)

  test "A file with nothing preserved carries no mark":
    let file = getTempDir() / "moe_rcm_mark_quiet.txt"
    defer:
      removeFile(file)
    writeFile(file, "disk")

    let e = createNoticeEditor()
    discard e.loadFile(file)
    check not e.owesPreservedWork(e.activeBuffer)

  test "A file replaced by rename since the crash still carries the mark":
    # Most writers save through a temporary file and a rename, which gives the
    # path a new inode; the copy is still that file's.
    let file = getTempDir() / "moe_rcm_renamed.txt"
    let scratch = getTempDir() / "moe_rcm_renamed.txt.tmp"
    defer:
      removeFile(file)
      removeFile(scratch)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    writeFile(scratch, "rewritten by another tool")
    moveFile(scratch, file)

    let e = createNoticeEditor()
    discard e.loadFile(file)
    check e.owesPreservedWork(e.activeBuffer)

  test "A file open under another spelling carries the mark":
    # `pathKey` normalizes but does not resolve links, and "is this the same
    # file?" is the entity.
    when defined(posix):
      let real = getTempDir() / "moe_rcm_symlink_real.txt"
      let link = getTempDir() / "moe_rcm_symlink_link.txt"
      defer:
        removeFile(link)
        removeFile(real)

      let crashed = createTestEditor()
      crashed.openModified(real, "disk", "work that was never saved")
      check crashed.preserveModified().len == 1

      removeFile(link)
      createSymlink(real, link)

      let e = createNoticeEditor()
      discard e.loadFile(link)
      check e.owesPreservedWork(e.activeBuffer)

  test "A copy preserved under another spelling still marks the file":
    # One spelling's copy being in the file says nothing about the other's.
    when defined(posix):
      let real = getTempDir() / "moe_rcm_mark_two_spellings.txt"
      let link = getTempDir() / "moe_rcm_mark_two_spellings_link.txt"
      defer:
        removeFile(link)
        removeFile(real)

      writeFile(real, "disk")
      removeFile(link)
      createSymlink(real, link)

      let first = createTestEditor()
      first.openModified(real, "disk", "work under the real name")
      check first.preserveModified().len == 1
      let second = createTestEditor()
      second.openModified(link, "disk", "work under the link")
      check second.preserveModified().len == 1

      writeFile(real, "work under the real name")
      let e = createNoticeEditor()
      discard e.loadFile(real)
      check e.owesPreservedWork(e.activeBuffer)
      e.noteRecoveryAtStartup()
      check e.state.statusMessage.contains("a file open here")
      check not e.state.statusMessage.contains("not open here")

  test "An editor main did not set up reads no recovery directory":
    # Tests build editors, and one that read the user's cache would pick up
    # whatever a crash left on the machine running them.
    check createTestEditor().recovery.isNone

  test "A crash in another editor shows up at the next :recover":
    # The index is read at startup and when the list opens, not per load.
    let file = getTempDir() / "moe_rcm_other_instance.txt"
    defer:
      removeFile(file)
    writeFile(file, "disk")

    let e = createNoticeEditor()
    discard e.loadFile(file)
    check not e.owesPreservedWork(e.activeBuffer)
    let buf = e.activeBuffer

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    check e.processViewerResult(HandlerResult(kind: hrEnterRecoveryManager))
    check e.owesPreservedWork(buf)

  test "A copy another editor discarded goes once this one fails to touch it":
    # The index is a snapshot, so the mark stays until something re-reads it;
    # a change that finds the copy gone is such a read.
    let file = getTempDir() / "moe_rcm_discarded_elsewhere.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    let saved = crashed.preserveModified()
    check saved.len == 1

    let e = createNoticeEditor()
    discard e.loadFile(file)
    let buf = e.activeBuffer
    check e.owesPreservedWork(buf)

    check newRecoveryStore(TestRecoveryDir).discardSession(saved[0].parentDir.parentDir)
    check e.owesPreservedWork(buf)

    e.enterRecovery(initRecoveryManagerState(e.recovery.get, file, e.buffers))
    check e.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerToggleReviewed, reviewRecoveryIndex: 0)
    )
    check e.state.statusMessage.startsWith("Failed to mark")
    check not e.owesPreservedWork(buf)
    check e.activeWindow.modeState.recoveryManager.items.len == 0

  test "A save that replaces the file's inode keeps the file's copies":
    # A plain save renames a new file into place. Looking for the copies again
    # on every save would stat every origin on the way to the screen.
    when defined(posix):
      let real = getTempDir() / "moe_rcm_mark_inode_real.txt"
      let link = getTempDir() / "moe_rcm_mark_inode_link.txt"
      defer:
        removeFile(link)
        removeFile(real)

      removeFile(link)
      writeFile(real, "disk")
      createSymlink(real, link)
      let crashed = createTestEditor()
      discard crashed.loadFile(link)
      check crashed.activeBuffer.replaceAllLines(@["work that was never saved"]).isOk
      check crashed.preserveModified().len == 1

      let e = createNoticeEditor()
      discard e.loadFile(real)
      let buf = e.activeBuffer
      check e.owesPreservedWork(buf)
      let inodeBefore = buf.fileBaseline.ino

      # Only the entities tie the copy to this file; take one away.
      removeFile(link)
      check buf.insertText(BufferPosition(line: 0, column: 0), ">").isOk
      check e.saveFile(buf).isOk
      check buf.fileBaseline.ino != inodeBefore
      check e.owesPreservedWork(buf)

  test "The list judges an open file by what its buffer last read":
    # A change behind the buffer is not what the buffer would save.
    let file = getTempDir() / "moe_rcm_agree.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    let saved = crashed.preserveModified()
    check saved.len == 1
    writeFile(file, readFile(saved[0]))

    let e = createNoticeEditor()
    discard e.loadFile(file)
    writeFile(file, "someone else wrote this")

    let state = initRecoveryManagerState(e.recovery.get, file, e.buffers)
    require state.items.len == 1
    check state.items[0].matchesDisk

suite "recovery manager - settling a restored copy":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  proc reviewedHolding(content: string): Option[bool] =
    ## Whether the copy holding `content` is marked reviewed on disk.
    for session in newRecoveryStore(TestRecoveryDir).sessions():
      for f in session.files:
        if readFile(f.path) == content:
          return some(f.reviewed)

  proc restoreInto(e: Editor, file: string) =
    e.enterRecovery(initRecoveryManagerState(e.recovery.get, file, e.buffers))
    check e.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )

  test "Restoring takes the mark off while the buffer holds the work":
    let file = getTempDir() / "moe_rcm_settle_restore.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.restoreInto(file)
    check e.activeBuffer.filePath == some(file)
    check e.activeBuffer.isModified
    check not e.owesPreservedWork(e.activeBuffer)

  test "The list says a restored copy is not saved yet":
    let file = getTempDir() / "moe_rcm_settle_note.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.restoreInto(file)
    let state = initRecoveryManagerState(e.recovery.get, file, e.buffers)
    require state.items.len == 1
    check state.items[0].noteFor == "restored, not saved yet"

  test "A restore that is not saved leaves the copy owed to later sessions":
    # Until the save, the buffer is the only other place the work is; if this
    # editor dies without preserving it, the copy is all that is left.
    let file = getTempDir() / "moe_rcm_settle_later.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.restoreInto(file)
    check not newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

    let later = createNoticeEditor()
    discard later.loadFile(file)
    check later.owesPreservedWork(later.activeBuffer)

  test "Saving the restored buffer settles the copy for later sessions":
    # A restored buffer differs from its copy as soon as it is edited, so
    # comparing bytes would keep announcing it.
    let file = getTempDir() / "moe_rcm_settle_save.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.restoreInto(file)
    let buf = e.activeBuffer
    check buf.replaceAllLines(@["work that was never saved, and then some"]).isOk
    check e.saveAllBuffers().failures.len == 0
    check not e.owesPreservedWork(buf)

    let later = createNoticeEditor()
    discard later.loadFile(file)
    check not later.owesPreservedWork(later.activeBuffer)
    # Settled, not gone: the list still offers it.
    let files = newRecoveryStore(TestRecoveryDir).sessions()[0].files
    check files.len == 1
    check files[0].reviewed

  test "Saving one restored copy leaves the file's other copies owed":
    # Only the restored copy's work reached the file; the other may hold work
    # nothing else has.
    let file = getTempDir() / "moe_rcm_settle_siblings.txt"
    defer:
      removeFile(file)

    let first = createTestEditor()
    first.openModified(file, "disk", "older work")
    check first.preserveModified().len == 1
    let second = createTestEditor()
    second.openModified(file, "disk", "newer work")
    check second.preserveModified().len == 1

    let e = createNoticeEditor()
    e.restoreInto(file)
    let buf = e.activeBuffer
    check buf.getLine(0) == "newer work"
    check e.owesPreservedWork(buf)
    check e.saveAllBuffers().failures.len == 0
    check e.owesPreservedWork(buf)
    check reviewedHolding("newer work") == some(true)
    check reviewedHolding("older work") == some(false)

  test "Restoring a copy the file already has leaves the file's other copies owed":
    # Looking at one copy is not choosing it over the others.
    let file = getTempDir() / "moe_rcm_settle_siblings_on_disk.txt"
    defer:
      removeFile(file)

    let first = createTestEditor()
    first.openModified(file, "disk", "work only this copy has")
    check first.preserveModified().len == 1
    let second = createTestEditor()
    second.openModified(file, "disk", "what the file has now")
    let saved = second.preserveModified()
    check saved.len == 1
    writeFile(file, readFile(saved[0]))

    let e = createNoticeEditor()
    e.restoreInto(file)
    check e.state.statusMessage.contains("the file already has it")
    check e.owesPreservedWork(e.activeBuffer)
    check reviewedHolding("work only this copy has") == some(false)

  test "Undoing the restore brings the mark back":
    let file = getTempDir() / "moe_rcm_settle_undo.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.restoreInto(file)
    let buf = e.activeBuffer
    check buf.undo().isOk
    check not buf.isModified
    check e.owesPreservedWork(buf)

  test "Saving after undoing the restore leaves the copy owed":
    # The buffer is saved, but what it holds is the file, not the copy.
    let file = getTempDir() / "moe_rcm_settle_undo_save.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.restoreInto(file)
    let buf = e.activeBuffer
    check buf.undo().isOk
    check e.saveFile(buf).isOk
    check readFile(file) == "disk"
    check e.owesPreservedWork(buf)
    check not newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "Editing after undoing the restore still owes the copy":
    # The buffer is modified again, but not by the restore.
    let file = getTempDir() / "moe_rcm_settle_undo_edit.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.restoreInto(file)
    let buf = e.activeBuffer
    check buf.undo().isOk
    check buf.insertText(BufferPosition(line: 0, column: 0), ">").isOk
    check buf.isModified
    check e.owesPreservedWork(buf)
    check e.saveFile(buf).isOk
    check not newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "Redoing the restore holds the copy back again, and saving settles it":
    let file = getTempDir() / "moe_rcm_settle_redo.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.restoreInto(file)
    let buf = e.activeBuffer
    check buf.undo().isOk
    check buf.redo().isOk
    check not e.owesPreservedWork(buf)
    check e.saveFile(buf).isOk
    check newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "Saving after reloading the restored buffer leaves the copy owed":
    let file = getTempDir() / "moe_rcm_settle_reload.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.restoreInto(file)
    let buf = e.activeBuffer
    check e.reloadCurrentFile(announce = false).isOk
    check e.owesPreservedWork(buf)
    check e.saveFile(buf).isOk
    check not newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "Edits on top of the restore keep it, and saving settles the copy":
    let file = getTempDir() / "moe_rcm_settle_edit_on_top.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.restoreInto(file)
    let buf = e.activeBuffer
    check buf.insertText(BufferPosition(line: 0, column: 0), ">").isOk
    check not e.owesPreservedWork(buf)
    check e.saveFile(buf).isOk
    check newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "Closing the restored buffer unsaved brings the mark back":
    let file = getTempDir() / "moe_rcm_settle_close.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.restoreInto(file)
    let restored = e.activeBuffer
    discard e.removeBufferAt(e.bufferIndexById(restored.id))
    let reopened = e.loadOrCreateBuffer(file)
    require reopened.isOk
    check reopened.get.id != restored.id
    check e.owesPreservedWork(reopened.get)

  test "Saving after another editor discarded the restored copy says nothing":
    # The copy is gone, so there is nothing left to announce or to mark.
    let file = getTempDir() / "moe_rcm_settle_discarded.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.restoreInto(file)
    let buf = e.activeBuffer
    let session = newRecoveryStore(TestRecoveryDir).sessions()[0]
    check newRecoveryStore(TestRecoveryDir).discardCopy(
      session.files[0].path, session.dir
    )

    let before = getMessageLog().len
    check e.saveFile(buf).isOk
    check not getMessageLog()[before ..^ 1].anyIt(it.contains("still announced"))
    check not e.owesPreservedWork(buf)

  proc restoreAt(e: Editor, file: string, index: int) =
    e.enterRecovery(initRecoveryManagerState(e.recovery.get, file, e.buffers))
    check e.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: index)
    )

  proc preserveTwice(file: string) =
    ## Two sessions, each preserving different work of `file`.
    for work in ["work A", "work B"]:
      let crashed = createTestEditor()
      crashed.openModified(file, "disk", work)
      check crashed.preserveModified().len == 1

  test "A restore replaced by another one is owed again, and saving leaves it":
    let file = getTempDir() / "moe_rcm_settle_replaced.txt"
    defer:
      removeFile(file)
    preserveTwice(file)

    let e = createNoticeEditor()
    e.restoreAt(file, 0)
    let buf = e.activeBuffer
    let first = buf.getLine(0)
    e.restoreAt(file, 1)
    let second = buf.getLine(0)
    require first != second
    check e.owesPreservedWork(buf)

    check e.saveFile(buf).isOk
    check readFile(file) == second
    check reviewedHolding(second) == some(true)
    check reviewedHolding(first) == some(false)
    check e.owesPreservedWork(buf)

  test "Undoing the later restore holds the earlier one back again":
    let file = getTempDir() / "moe_rcm_settle_replaced_undo.txt"
    defer:
      removeFile(file)
    preserveTwice(file)

    let e = createNoticeEditor()
    e.restoreAt(file, 0)
    let buf = e.activeBuffer
    let first = buf.getLine(0)
    e.restoreAt(file, 1)
    let second = buf.getLine(0)
    check buf.undo().isOk
    check buf.getLine(0) == first

    check e.saveFile(buf).isOk
    check reviewedHolding(first) == some(true)
    check reviewedHolding(second) == some(false)

  test "Restoring another copy lets the earlier one go, even onto its own text":
    # Picking the other copy says which work the buffer is meant to hold, and
    # the text the edits left is not the earlier copy's.
    let file = getTempDir() / "moe_rcm_settle_later_noop.txt"
    defer:
      removeFile(file)
    preserveTwice(file)

    let e = createNoticeEditor()
    e.restoreAt(file, 0)
    let buf = e.activeBuffer
    let first = buf.getLine(0)
    let second = if first == "work A": "work B" else: "work A"
    check buf.replaceAllLines(@[second]).isOk
    e.restoreAt(file, 1)
    check buf.getLine(0) == second

    check e.saveFile(buf).isOk
    check reviewedHolding(second) == some(true)
    check reviewedHolding(first) == some(false)
    check e.owesPreservedWork(buf)

  test "Restoring the same copy again keeps the restore it replaced let go":
    let file = getTempDir() / "moe_rcm_settle_restore_again.txt"
    defer:
      removeFile(file)
    preserveTwice(file)

    let e = createNoticeEditor()
    e.restoreAt(file, 1)
    let buf = e.activeBuffer
    let first = buf.getLine(0)
    e.restoreAt(file, 0)
    let second = buf.getLine(0)
    require first != second
    e.restoreAt(file, 0)
    check e.owesPreservedWork(buf)

    check e.saveFile(buf).isOk
    check reviewedHolding(second) == some(true)
    check reviewedHolding(first) == some(false)
    check e.owesPreservedWork(buf)

  test "Restoring a saved copy again keeps the restore it replaced let go":
    let file = getTempDir() / "moe_rcm_settle_restore_saved_again.txt"
    defer:
      removeFile(file)
    preserveTwice(file)

    let e = createNoticeEditor()
    e.restoreAt(file, 1)
    let buf = e.activeBuffer
    let first = buf.getLine(0)
    e.restoreAt(file, 0)
    let second = buf.getLine(0)
    require first != second
    check e.saveFile(buf).isOk
    e.restoreAt(file, 0)
    check buf.insertText(BufferPosition(line: 0, column: 0), ">").isOk

    check e.saveFile(buf).isOk
    check reviewedHolding(first) == some(false)
    check e.owesPreservedWork(buf)

  test "A restore outlives a refresh that could not read its session":
    if not permissionsAreEnforced():
      skip()
    else:
      let file = getTempDir() / "moe_rcm_settle_unreadable.txt"
      defer:
        removeFile(file)

      let crashed = createTestEditor()
      crashed.openModified(file, "disk", "work that was never saved")
      check crashed.preserveModified().len == 1

      let e = createNoticeEditor()
      e.restoreInto(file)
      let buf = e.activeBuffer
      let payload = newRecoveryStore(TestRecoveryDir).sessions()[0].dir / PayloadDirName
      setFilePermissions(payload, {})
      e.recovery.get.refresh()
      setFilePermissions(payload, {fpUserRead, fpUserWrite, fpUserExec})
      e.recovery.get.refresh()
      check not e.owesPreservedWork(buf)

      check e.saveFile(buf).isOk
      check newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "Saving the restored buffer as another file leaves the copy owed":
    # The file the copy came from still lacks the work.
    let file = getTempDir() / "moe_rcm_settle_save_as.txt"
    let other = getTempDir() / "moe_rcm_settle_save_as_other.txt"
    defer:
      removeFile(file)
      removeFile(other)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.restoreInto(file)
    check e.saveFile(e.activeBuffer, some(other)).isOk
    check readFile(file) == "disk"
    check not newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

    let reopened = e.loadOrCreateBuffer(file)
    require reopened.isOk
    check e.owesPreservedWork(reopened.get)

    let later = createNoticeEditor()
    discard later.loadFile(file)
    check later.owesPreservedWork(later.activeBuffer)

  proc openHolding(e: Editor, file, content: string) =
    ## Open `file` clean, holding `content`.
    writeFile(file, content)
    discard e.loadFile(file)
    check not e.activeBuffer.isModified

  proc takeBackMarks(e: Editor) =
    ## Unmark every copy: opening a file that holds one settles it, and the
    ## test is about what happens to the file after that.
    for session in newRecoveryStore(TestRecoveryDir).sessions():
      for f in session.files:
        var reason = ""
        check e.recovery.get.setReviewed(f.path, session.dir, false, reason)

  test "Restoring a saved copy again after its file changed holds it back until saved":
    let file = getTempDir() / "moe_rcm_settle_restore_again_changed.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.restoreInto(file)
    let buf = e.activeBuffer
    check e.saveFile(buf).isOk
    check reviewedHolding("work that was never saved") == some(true)

    e.takeBackMarks()
    writeFile(file, "rewritten elsewhere")
    e.restoreInto(file)
    check buf.getLine(0) == "work that was never saved"
    check not e.owesPreservedWork(buf)

  test "A restore into a clean buffer whose file holds the copy settles it":
    let file = getTempDir() / "moe_rcm_settle_clean.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.openHolding(file, "work that was never saved")
    e.restoreInto(file)
    check not e.activeBuffer.isModified
    check newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "A restore into a clean buffer whose file is gone does not settle the copy":
    # Clean means the buffer matches what it last read, not what is there now.
    let file = getTempDir() / "moe_rcm_settle_clean_gone.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.openHolding(file, "work that was never saved")
    e.takeBackMarks()
    removeFile(file)
    e.restoreInto(file)
    check not newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed
    # Held back like any restore until saved, not settled.
    check not e.owesPreservedWork(e.activeBuffer)
    check e.recovery.get.restoring(
      newRecoveryStore(TestRecoveryDir).sessions()[0].files[0], e.buffers
    )

  test "A restore into a clean buffer whose file changed does not settle the copy":
    let file = getTempDir() / "moe_rcm_settle_clean_changed.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.openHolding(file, "work that was never saved")
    e.takeBackMarks()
    writeFile(file, "rewritten elsewhere")
    e.restoreInto(file)
    check not newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed
    # Held back like any restore until saved, not settled.
    check not e.owesPreservedWork(e.activeBuffer)
    check e.recovery.get.restoring(
      newRecoveryStore(TestRecoveryDir).sessions()[0].files[0], e.buffers
    )

  test "A restore that changed nothing into a buffer with no history settles once saved":
    # No undo entry names the restore, so the buffer's text as it was is what
    # holds it.
    let file = getTempDir() / "moe_rcm_settle_noop_save.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.openHolding(file, "work that was never saved")
    writeFile(file, "rewritten elsewhere")
    let buf = e.activeBuffer
    e.restoreInto(file)
    check not e.owesPreservedWork(buf)
    check e.saveFile(buf, force = true).isOk
    check readFile(file) == "work that was never saved"
    check newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed
    check not e.owesPreservedWork(buf)

  test "Edits on top of a restore that changed nothing keep it":
    # The same rule as for a restore that left an undo entry: the edits are
    # the user's, made on the restored text.
    let file = getTempDir() / "moe_rcm_settle_noop_edit.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.openHolding(file, "work that was never saved")
    writeFile(file, "rewritten elsewhere")
    let buf = e.activeBuffer
    e.restoreInto(file)
    check buf.insertText(BufferPosition(line: 0, column: 0), ">").isOk
    check not e.owesPreservedWork(buf)
    check e.saveFile(buf, force = true).isOk
    check newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "A reload that lands as an edit lets go of a restore that changed nothing":
    let file = getTempDir() / "moe_rcm_settle_noop_reload.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.openHolding(file, "work that was never saved")
    e.takeBackMarks()
    writeFile(file, "rewritten elsewhere")
    let buf = e.activeBuffer
    e.restoreInto(file)
    check not buf.isModified
    check buf.reloadFileIfContentChanged().get
    check buf.undoStack.len == 1
    check e.owesPreservedWork(buf)
    check e.saveFile(buf, force = true).isOk
    check not newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "A reload over a restore that named an earlier change lets it go, and undoing the reload holds it again":
    # The restore changed nothing, so it is named by the change already on top.
    # A reload pushed above that change leaves it applied.
    let file = getTempDir() / "moe_rcm_settle_named_reload.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.openHolding(file, "ork that was never saved")
    let buf = e.activeBuffer
    check buf.insertText(BufferPosition(line: 0, column: 0), "w").isOk
    check e.saveFile(buf).isOk
    # Saving the copy's text settled it; take that back so the restore below is
    # what decides.
    e.takeBackMarks()
    writeFile(file, "rewritten elsewhere")
    e.restoreInto(file)
    check buf.undoStack.len == 1
    check not e.owesPreservedWork(buf)

    check buf.reloadFileIfContentChanged().get
    check e.owesPreservedWork(buf)
    check buf.undo().isOk
    check not e.owesPreservedWork(buf)
    check buf.redo().isOk
    check e.saveFile(buf, force = true).isOk
    check not newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "A save that could not mark the copy marks it on the next save":
    let file = getTempDir() / "moe_rcm_settle_mark_retry.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.restoreInto(file)
    let buf = e.activeBuffer
    let session = newRecoveryStore(TestRecoveryDir).sessions()[0]
    let blocker = session.dir / ReviewedDirName
    # A link there is refused, so the mark cannot be written.
    createSymlink(getTempDir(), blocker)
    check e.saveFile(buf).isOk
    check not newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

    removeFile(blocker)
    check e.saveFile(buf).isOk
    check newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed
    check not e.owesPreservedWork(buf)

suite "recovery manager - the startup count":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "Work preserved from an unnamed buffer is announced":
    # No file can ever carry the mark for a copy with no origin.
    let crashed = createTestEditor()
    check crashed.activeBuffer().replaceAllLines(@["text that lives nowhere else"]).isOk
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.noteRecoveryAtStartup()
    check e.state.statusMessage.contains("an unnamed buffer")
    check e.state.statusMessage.contains(":recover!")

  test "Work preserved for a file the startup did not open is announced":
    let file = getTempDir() / "moe_rcm_elsewhere.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.noteRecoveryAtStartup()
    check e.state.statusMessage.contains("a file not open here")

  test "Open files are counted, so none of them goes unmentioned":
    # Only the shown buffer's mark is on screen; the others need the count.
    let a = getTempDir() / "moe_rcm_count_a.txt"
    let b = getTempDir() / "moe_rcm_count_b.txt"
    defer:
      removeFile(a)
      removeFile(b)

    let crashed = createTestEditor()
    crashed.openModified(a, "disk a", "work a")
    discard crashed.openModifiedBehind(b, "disk b", "work b")
    check crashed.preserveModified().len == 2

    let e = createNoticeEditor()
    discard e.loadFile(a)
    check e.loadOrCreateBuffer(b).isOk
    e.noteRecoveryAtStartup()
    check e.state.statusMessage.contains("2 files open here")
    check not e.state.statusMessage.contains("not open here")

  test "A file open under another spelling is not counted as elsewhere":
    when defined(posix):
      let real = getTempDir() / "moe_rcm_count_real.txt"
      let link = getTempDir() / "moe_rcm_count_link.txt"
      defer:
        removeFile(link)
        removeFile(real)

      let crashed = createTestEditor()
      crashed.openModified(real, "disk", "work that was never saved")
      check crashed.preserveModified().len == 1
      removeFile(link)
      createSymlink(real, link)

      let e = createNoticeEditor()
      discard e.loadFile(link)
      e.noteRecoveryAtStartup()
      check e.state.statusMessage.contains("a file open here")
      check not e.state.statusMessage.contains("not open here")

  test "A copy a file not open already holds is not counted":
    let file = getTempDir() / "moe_rcm_count_held.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    let saved = crashed.preserveModified()
    check saved.len == 1
    writeFile(file, readFile(saved[0]))

    let e = createNoticeEditor()
    e.noteRecoveryAtStartup()
    check e.state.statusMessage.len == 0
    check newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "A copy of a file that caught up before the crash is not counted":
    # The buffer was out of step with its file, so the file kept the stamp
    # the copy records while already holding the copy's bytes.
    let file = getTempDir() / "moe_rcm_count_caught_up.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    writeFile(file, crashed.activeBuffer.getFileContent())
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.noteRecoveryAtStartup()
    check e.state.statusMessage.len == 0
    check newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "A reviewed copy is not counted":
    let crashed = createTestEditor()
    check crashed.activeBuffer().replaceAllLines(@["text that lives nowhere else"]).isOk
    check crashed.preserveModified().len == 1
    let session = newRecoveryStore(TestRecoveryDir).sessions()[0]
    var reason = ""
    check newRecoveryStore(TestRecoveryDir).setReviewed(
      session.files[0].path, session.dir, true, reason
    )

    let e = createNoticeEditor()
    e.noteRecoveryAtStartup()
    check e.state.statusMessage.len == 0

  test "Nothing preserved stays quiet":
    let e = createNoticeEditor()
    e.noteRecoveryAtStartup()
    check e.state.statusMessage.len == 0

  test "A count the status line already has a message for goes below it":
    # A config error owns the status line from startup, and the preserved
    # copy would otherwise age out unmentioned.
    let crashed = createTestEditor()
    check crashed.activeBuffer().replaceAllLines(@["text that lives nowhere else"]).isOk
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.state.statusMessage = "Config error: something else spoke first"
    let before = getMessageLog().len
    e.noteRecoveryAtStartup()
    # Both, the error first: an entry in the log alone is never seen.
    let lines = e.state.statusMessage.split('\n')
    check lines.len == 2
    check lines[0] == "Config error: something else spoke first"
    check lines[1].contains(":recover!")
    check getMessageLog()[before ..^ 1].anyIt(it.contains(":recover!"))
    check not getMessageLog()[before ..^ 1].anyIt(it.contains("Config error"))

  test "A session that died before its manifest holds no unnamed buffers":
    # Without the manifest nothing records where a copy came from, which is
    # not the same as a buffer that had no file.
    let dir = TestRecoveryDir / "20260920T000000_2"
    createDir(dir / PayloadDirName)
    writeFile(dir / PayloadDirName / "0000-a.txt", "work a")
    writeFile(dir / PayloadDirName / "0001-b.txt", "work b")

    let e = createNoticeEditor()
    e.noteRecoveryAtStartup()
    check not e.state.statusMessage.contains("unnamed")
    check e.state.statusMessage.contains("2 buffers whose files were not recorded")

  test "A directory that cannot be read claims no preserved work":
    # Nothing is known about what is inside, and `:recover!` could not show it.
    when defined(posix):
      if not permissionsAreEnforced():
        skip()
      else:
        createDir(TestRecoveryDir)
        setFilePermissions(TestRecoveryDir, {})
        defer:
          setFilePermissions(TestRecoveryDir, {fpUserRead, fpUserWrite, fpUserExec})

        let e = createNoticeEditor()
        e.noteRecoveryAtStartup()
        check e.state.statusMessage.contains("Could not read")
        check not e.state.statusMessage.contains("preserved")

  test "A directory that cannot be read again keeps what was last read":
    # The work is still preserved; an empty list and no marks would say not.
    when defined(posix):
      if not permissionsAreEnforced():
        skip()
      else:
        let file = getTempDir() / "moe_rcm_unreadable_later.txt"
        defer:
          removeFile(file)

        let crashed = createTestEditor()
        crashed.openModified(file, "disk", "work that was never saved")
        check crashed.preserveModified().len == 1

        let e = createNoticeEditor()
        discard e.loadFile(file)
        let buf = e.activeBuffer
        check e.owesPreservedWork(buf)

        setFilePermissions(TestRecoveryDir, {})
        defer:
          setFilePermissions(TestRecoveryDir, {fpUserRead, fpUserWrite, fpUserExec})
        let state = initRecoveryManagerState(e.recovery.get, file, e.buffers)
        state.refresh(e.buffers)
        check state.items.len == 1
        check e.owesPreservedWork(buf)
        check state.createRecoveryManagerTextBuffer()[0].contains("could not read")

  test "A session whose payload cannot be listed is reported as unread":
    when defined(posix):
      if not permissionsAreEnforced():
        skip()
      else:
        let dir = TestRecoveryDir / "20260920T000000_1"
        createDir(dir / PayloadDirName)
        writeFile(dir / PayloadDirName / "0000-planted.txt", "preserved")
        setFilePermissions(dir / PayloadDirName, {})
        defer:
          setFilePermissions(
            dir / PayloadDirName, {fpUserRead, fpUserWrite, fpUserExec}
          )

        let e = createNoticeEditor()
        e.noteRecoveryAtStartup()
        check e.state.statusMessage.contains("could not be read")

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

    let entry = initRecoveryManagerState(TestRecoveryDir, file, []).items[0]
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

    let entry = initRecoveryManagerState(TestRecoveryDir, file, []).items[0]
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

    let entry = initRecoveryManagerState(TestRecoveryDir, file, []).items[0]
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

    let state = initRecoveryManagerState(TestRecoveryDir, "", [])
    require state.items.len == 1
    check not state.items[0].formatLine(withPath = true).contains("\n")
    check state.createRecoveryManagerTextBuffer().len == 2

suite "recovery manager - widening the list":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "`:recover!` reaches a copy no file can ask about":
    let file = getTempDir() / "moe_rcm_widen.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "edited")
    let scratch = newTextBuffer()
    crashed.addBuffer(scratch)
    check scratch.replaceAllLines(@["never named"]).isOk
    check crashed.preserveModified().len == 2

    let e = createNoticeEditor()
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
    check crashed.preserveModified().len == 2

    let e = createNoticeEditor()
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
    check crashed.preserveModified().len == 2

    let e = createNoticeEditor()
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
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    discard e.loadFile(file)
    check e.processViewerResult(HandlerResult(kind: hrEnterRecoveryManager))
    check e.activeWindow.modeState.recoveryManager.items.len == 1

    # Stands in for the other editor: the copy goes, this list does not know.
    let gone = e.activeWindow.modeState.recoveryManager.items[0]
    var reason = ""
    check newRecoveryStore(TestRecoveryDir).discardCopy(
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
    initRecoveryManagerState(TestRecoveryDir, file, [])

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

suite "recovery manager - setting a copy aside":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  proc toggle(e: Editor) =
    check e.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerToggleReviewed, reviewRecoveryIndex: 0)
    )

  test "x asks to toggle the selected copy":
    let e = createTestEditor()
    let file = getTempDir() / "moe_rcm_x_key.txt"
    defer:
      removeFile(file)
    e.openModified(file, "disk", "edited")
    discard e.preserveModified()

    let state = initRecoveryManagerState(TestRecoveryDir, file, [])
    let r = state.handleRecoveryManagerModeKey(10, toKeyCombo('x'))
    check r.kind == rcmrToggleReviewed
    check r.reviewIndex == 0

  test "x on an empty list does nothing":
    let state = initRecoveryManagerState(TestRecoveryDir, "", [])
    check state.handleRecoveryManagerModeKey(10, toKeyCombo('x')).kind == rcmrHandled

  test "A copy set aside loses its mark but stays listed":
    let file = getTempDir() / "moe_rcm_set_aside.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    discard e.loadFile(file)
    let buf = e.activeBuffer
    check e.owesPreservedWork(buf)

    e.enterRecovery(initRecoveryManagerState(e.recovery.get, file, e.buffers))
    e.toggle()
    check not e.owesPreservedWork(buf)
    let state = e.activeWindow.modeState.recoveryManager
    require state.items.len == 1
    check state.items[0].reviewed
    check state.items[0].noteFor == "reviewed"
    check e.state.statusMessage.contains("no longer announced")

    # A later session reads the mark from disk.
    let later = createNoticeEditor()
    discard later.loadFile(file)
    check not later.owesPreservedWork(later.activeBuffer)

  test "x again brings the mark back":
    let file = getTempDir() / "moe_rcm_set_aside_undo.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    discard e.loadFile(file)
    let buf = e.activeBuffer
    e.enterRecovery(initRecoveryManagerState(e.recovery.get, file, e.buffers))
    e.toggle()
    e.toggle()
    check e.owesPreservedWork(buf)
    check not e.activeWindow.modeState.recoveryManager.items[0].reviewed

  test "x on a restored copy not saved yet does not claim it is announced":
    # The restore holds it back until the buffer is saved, mark or no mark.
    let file = getTempDir() / "moe_rcm_set_aside_restored.txt"
    defer:
      removeFile(file)

    let crashed = createTestEditor()
    crashed.openModified(file, "disk", "work that was never saved")
    check crashed.preserveModified().len == 1

    let e = createNoticeEditor()
    e.enterRecovery(initRecoveryManagerState(e.recovery.get, file, e.buffers))
    check e.processRecoveryResult(
      HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
    )
    let buf = e.activeBuffer
    e.enterRecovery(initRecoveryManagerState(e.recovery.get, file, e.buffers))
    e.toggle()
    e.toggle()
    check not e.owesPreservedWork(buf)
    check not e.state.statusMessage.contains("announced again")
    check e.state.statusMessage.contains("not saved yet")

  test "A session with no manifest carries the mark too":
    # The mark is a file of its own, so it needs nothing from the manifest.
    let dir = TestRecoveryDir / "20260920T000000_3"
    createDir(dir / PayloadDirName)
    writeFile(dir / PayloadDirName / "0000-half.txt", "half written")

    let e = createNoticeEditor()
    e.enterRecovery(initRecoveryManagerState(e.recovery.get, "", e.buffers))
    e.toggle()
    check e.state.statusMessage.contains("no longer announced")
    check e.activeWindow.modeState.recoveryManager.items[0].reviewed

    let later = createNoticeEditor()
    later.noteRecoveryAtStartup()
    check later.state.statusMessage.len == 0

  test "A restore that could not mark its copy does not say the file has it":
    when defined(posix):
      if not permissionsAreEnforced():
        skip()
      else:
        let file = getTempDir() / "moe_rcm_mark_restore_unwritable.txt"
        defer:
          removeFile(file)

        let crashed = createTestEditor()
        crashed.openModified(file, "disk", "work that was never saved")
        let saved = crashed.preserveModified()
        require saved.len == 1
        let sessionDir = saved[0].parentDir.parentDir

        let e = createNoticeEditor()
        setFilePermissions(sessionDir, {fpUserRead, fpUserExec})
        defer:
          setFilePermissions(sessionDir, {fpUserRead, fpUserWrite, fpUserExec})
        # Not open yet, so the restore opens it and says so.
        writeFile(file, readFile(saved[0]))
        e.enterRecovery(initRecoveryManagerState(e.recovery.get, file, e.buffers))
        check e.processRecoveryResult(
          HandlerResult(kind: hrRecoveryManagerRestore, restoreRecoveryIndex: 0)
        )
        check e.state.statusMessage.contains("Opened")
        # The file has it; only the mark is missing.
        check e.state.statusMessage.contains("could not be marked")
        check not e.state.statusMessage.contains("not saved yet")
        check not newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "Marks behind a linked reviewed directory are not read":
    when defined(posix):
      let file = getTempDir() / "moe_rcm_mark_linked_reviewed.txt"
      let outside = getTempDir() / "moe_rcm_mark_linked_reviewed_target"
      createDir(outside)
      defer:
        removeFile(file)
        removeDir(outside)

      let crashed = createTestEditor()
      crashed.openModified(file, "disk", "work that was never saved")
      let saved = crashed.preserveModified()
      require saved.len == 1
      writeFile(outside / saved[0].lastPathPart, "")
      createSymlink(outside, saved[0].parentDir.parentDir / ReviewedDirName)

      check not newRecoveryStore(TestRecoveryDir).sessions()[0].files[0].reviewed

  test "A mark that cannot be written leaves the row as it was":
    when defined(posix):
      if not permissionsAreEnforced():
        skip()
      else:
        let dir = TestRecoveryDir / "20260920T000000_4"
        createDir(dir / PayloadDirName)
        writeFile(dir / PayloadDirName / "0000-half.txt", "half written")

        let e = createNoticeEditor()
        e.enterRecovery(initRecoveryManagerState(e.recovery.get, "", e.buffers))
        setFilePermissions(dir, {fpUserRead, fpUserExec})
        defer:
          setFilePermissions(dir, {fpUserRead, fpUserWrite, fpUserExec})
        e.toggle()
        check e.state.statusMessage.contains("Failed to mark")
        check not e.activeWindow.modeState.recoveryManager.items[0].reviewed
