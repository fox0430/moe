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

import std/[unittest, os, options, json, strutils, sequtils, times]

import pkg/results

import
  ../src/moepkg/[
    editor, editor_buffers, editor_window, buffer, backup, config, config_loader,
    emergency, message_log, recovery_format, recovery_index, recovery_store,
  ]
import ../src/moepkg/types/editor_types

when defined(posix):
  from std/posix import getuid, mkfifo

let TestRecoveryDir = getTempDir() / "moe_test_crash_recovery"

proc cleanupTestDir() =
  if dirExists(TestRecoveryDir):
    removeDir(TestRecoveryDir)

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  newEditor(config, vr)

proc testStore(): RecoveryStore =
  ## The store the tests list and discard through.
  newRecoveryStore(TestRecoveryDir)

proc testIndex(): RecoveryIndex =
  ## A running editor's view of the test store.
  newRecoveryIndex(TestRecoveryDir)

proc sessionDirOf(savedPath: string): string =
  ## The session that holds a copy `emergencySaveBuffers` returned.
  savedPath.parentDir.parentDir

proc permissionsAreEnforced(): bool =
  ## False for root: a missing permission bit does not deny access.
  when defined(posix):
    getuid() != 0
  else:
    false

proc saveSession(e: Editor, continuity = ckCrash, detail = ""): seq[string] =
  e.emergencySaveBuffers(continuity, detail, TestRecoveryDir)

var commitCalls = 0
var scratchExistedAtCommit = false
var finalExistedAtCommit = false

proc observeCommit(scratchPath, finalPath: string): bool {.raises: [].} =
  ## Watch the writer's commit step, then commit for real.
  inc commitCalls
  scratchExistedAtCommit = fileExists(scratchPath)
  finalExistedAtCommit = fileExists(finalPath)
  result = renameIntoPlace(scratchPath, finalPath)

var committed: seq[string]
var describedAtCommit: seq[string]
var beforeSecondCommit: proc() {.raises: [].} = nil

proc recordCommit(scratchPath, finalPath: string): bool {.raises: [].} =
  ## Note the order copies are committed in, and what the manifest described
  ## at the time, then commit for real.
  committed.add extractFilename(finalPath)
  if committed.len == 2 and beforeSecondCommit != nil:
    beforeSecondCommit()
  try:
    let manifest = parentDir(parentDir(finalPath)) / MetadataName
    describedAtCommit.add(
      if fileExists(manifest):
        readFile(manifest)
      else:
        ""
    )
  except CatchableError:
    describedAtCommit.add ""
  result = renameIntoPlace(scratchPath, finalPath)

proc rejectCommit(scratchPath, finalPath: string): bool {.raises: [].} =
  ## Fail the commit step, as a filesystem error would.
  discard
  false

proc plantSession(
    name: string,
    savedAt = 1758000000,
    continuity = "crash",
    detail = "",
    files = @[("0000-planted.txt", "/tmp/planted.txt", "preserved")],
) =
  ## Current-shape session: indexed copies under `payload/` and a finished
  ## recovery.json.
  let dir = TestRecoveryDir / name
  createDir(dir / PayloadDirName)
  var entries = newJArray()
  for (copyName, origin, content) in files:
    writeFile(dir / PayloadDirName / copyName, content)
    var entry = newJObject()
    entry["name"] = %copyName
    if origin.len > 0:
      entry["origin"] = %origin
    entries.add entry
  let meta = %*{
    "format": "moe-recovery",
    "version": 3,
    "savedAt": savedAt,
    "continuity": continuity,
    "detail": detail,
    "files": entries,
  }
  writeFile(dir / MetadataName, $meta)

proc plantLegacySession(
    name: string, content = "preserved", originalPath = "/tmp/planted.txt", meta = ""
) =
  ## Pre-format session: a copy at the root and a name-to-origin map.
  let dir = TestRecoveryDir / name
  createDir(dir)
  writeFile(dir / "planted.txt", content)
  writeFile(
    dir / MetadataName,
    if meta.len > 0:
      meta
    else:
      """{"planted.txt":{"originalPath":"""" & originalPath & """"}}""",
  )

proc markEdited(buf: TextBuffer) =
  ## Modified, holding text its file does not: what a preserve is for. A
  ## buffer still holding what it last read is skipped.
  buf.changeSeq = buf.savedSeq + 1
  buf.lastLoadedContent = none(ContentFingerprint)

suite "emergency - emergencySaveBuffers":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "Save modified buffer":
    let e = createTestEditor()

    let testFile = getTempDir() / "moe_test_emergency.txt"
    writeFile(testFile, "original content")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)
    let buf = e.activeBuffer()
    markEdited(buf)

    let savedPaths = saveSession(e)
    check savedPaths.len == 1

    let savedContent = readFile(savedPaths[0])
    check savedContent.contains("original content")

    let recoveryDir = sessionDirOf(savedPaths[0])
    let metadataPath = recoveryDir / MetadataName
    check fileExists(metadataPath)
    check not fileExists(recoveryDir / "recovery.json.tmp")

    # The copy sits under the reserved payload directory, committed under its
    # final name: no scratch name is left behind.
    check savedPaths[0].parentDir.lastPathPart == PayloadDirName
    check not fileExists(savedPaths[0].parentDir / ("." & savedPaths[0].lastPathPart))

    let metadata = parseJson(readFile(metadataPath))
    check metadata["format"].getStr == "moe-recovery"
    check metadata["version"].getInt == 3
    check metadata["continuity"].getStr == "crash"
    check metadata["savedAt"].getInt > 0
    check metadata["files"].len == 1
    check metadata["files"][0]["name"].getStr == extractFilename(savedPaths[0])
    check metadata["files"][0]["origin"].getStr == testFile

  test "A copy is committed from its scratch name, not written in place":
    let e = createTestEditor()

    let testFile = getTempDir() / "moe_test_emergency_commit.txt"
    writeFile(testFile, "original content")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)
    let buf = e.activeBuffer()
    markEdited(buf)

    commitCalls = 0
    scratchExistedAtCommit = false
    finalExistedAtCommit = false

    let savedPaths = e.emergencySaveBuffers(ckCrash, "", TestRecoveryDir, observeCommit)
    check savedPaths.len == 1
    check commitCalls == 1
    # At commit time the complete bytes sat beside the final name, which did
    # not exist yet. Writing the final name first would break both checks.
    check scratchExistedAtCommit
    check not finalExistedAtCommit
    check readFile(savedPaths[0]).contains("original content")

  test "A copy that cannot be committed leaves nothing behind":
    let e = createTestEditor()

    let testFile = getTempDir() / "moe_test_emergency_nocommit.txt"
    writeFile(testFile, "original content")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)
    let buf = e.activeBuffer()
    markEdited(buf)

    let savedPaths = e.emergencySaveBuffers(ckCrash, "", TestRecoveryDir, rejectCommit)
    check savedPaths.len == 0
    # The failed copy is not offered, and the empty session goes away with the
    # scratch instead of lingering.
    check testStore().sessions().len == 0
    check toSeq(walkDirRec(TestRecoveryDir)).len == 0

  test "Skip unmodified buffer":
    let e = createTestEditor()

    let testFile = getTempDir() / "moe_test_emergency_unmod.txt"
    writeFile(testFile, "unmodified content")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)

    check saveSession(e).len == 0

  test "Skip a modified buffer that still holds what it last read":
    # Typed away and back: nothing in it the file lacks, so a copy would only
    # be announced with nothing to offer.
    let e = createTestEditor()

    let testFile = getTempDir() / "moe_test_emergency_same.txt"
    writeFile(testFile, "same content")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)
    let buf = e.activeBuffer()
    check buf.replaceAllLines(@["other content"]).isOk
    check buf.replaceAllLines(@["same content"]).isOk
    check buf.isModified

    check saveSession(e).len == 0

  test "Save a buffer holding what it last read once the file is gone":
    # The buffer is the only place that text is left.
    let e = createTestEditor()

    let testFile = getTempDir() / "moe_test_emergency_same_gone.txt"
    writeFile(testFile, "same content")

    discard e.loadFile(testFile)
    let buf = e.activeBuffer()
    check buf.replaceAllLines(@["other content"]).isOk
    check buf.replaceAllLines(@["same content"]).isOk
    removeFile(testFile)

    let savedPaths = saveSession(e)
    check savedPaths.len == 1
    check readFile(savedPaths[0]) == "same content"

  test "Save a buffer holding what it last read once the file changed":
    let e = createTestEditor()

    let testFile = getTempDir() / "moe_test_emergency_same_changed.txt"
    writeFile(testFile, "same content")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)
    let buf = e.activeBuffer()
    check buf.replaceAllLines(@["other content"]).isOk
    check buf.replaceAllLines(@["same content"]).isOk
    writeFile(testFile, "rewritten elsewhere")

    check saveSession(e).len == 1

  test "A buffer holding what it last read has its file read only after the others are saved":
    # Its file may sit on a mount that never answers; the real work comes
    # first, described in the manifest.
    let e = createTestEditor()

    let sameFile = getTempDir() / "moe_test_emergency_order_same.txt"
    let editedFile = getTempDir() / "moe_test_emergency_order_edited.txt"
    writeFile(sameFile, "same content")
    writeFile(editedFile, "disk")
    defer:
      removeFile(sameFile)
      removeFile(editedFile)

    discard e.loadFile(sameFile)
    let same = e.activeBuffer()
    check same.replaceAllLines(@["other content"]).isOk
    check same.replaceAllLines(@["same content"]).isOk
    writeFile(sameFile, "rewritten elsewhere")

    let edited = newTextBuffer("edited", some(editedFile))
    discard e.vsplitWithBuffer(edited)
    markEdited(edited)

    committed.setLen 0
    describedAtCommit.setLen 0
    let savedPaths =
      e.emergencySaveBuffers(ckCrash, "", TestRecoveryDir, commit = recordCommit)
    check savedPaths.len == 2
    require committed.len == 2
    check committed[0].contains("order_edited")
    check committed[1].contains("order_same")
    check describedAtCommit[0].len == 0
    check describedAtCommit[1].contains(committed[0])
    let manifest = parseJson(readFile(sessionDirOf(savedPaths[0]) / MetadataName))
    check manifest["files"].len == 2

  test "No file a buffer came from is looked at before every copy is written":
    # A stamp taken between copies would be of a file that may never answer.
    let e = createTestEditor()

    let firstFile = getTempDir() / "moe_test_emergency_stamp_first.txt"
    let secondFile = getTempDir() / "moe_test_emergency_stamp_second.txt"
    writeFile(firstFile, "disk")
    writeFile(secondFile, "disk")
    defer:
      removeFile(firstFile)
      removeFile(secondFile)

    for path in [firstFile, secondFile]:
      let buf = newTextBuffer("edited", some(path))
      discard e.vsplitWithBuffer(buf)
      markEdited(buf)

    let grown = "grown by the time the last copy landed"
    committed.setLen 0
    describedAtCommit.setLen 0
    beforeSecondCommit = proc() {.raises: [].} =
      try:
        writeFile(firstFile, grown)
      except CatchableError:
        discard
    defer:
      beforeSecondCommit = nil
    let savedPaths =
      e.emergencySaveBuffers(ckCrash, "", TestRecoveryDir, commit = recordCommit)
    check savedPaths.len == 2
    check describedAtCommit[1].len == 0
    let manifest = parseJson(readFile(sessionDirOf(savedPaths[0]) / MetadataName))
    var sizes: seq[int]
    for entry in manifest["files"]:
      if entry["origin"].getStr.endsWith("stamp_first.txt"):
        sizes.add entry[ManifestOriginSizeKey].getInt
    check sizes == @[grown.len]

  test "Files are stamped only once the buffers holding what they last read are checked":
    # A stamp is detail; a file that never answers must not keep work unsaved.
    let e = createTestEditor()

    let editedFile = getTempDir() / "moe_test_emergency_late_stamp_edited.txt"
    let sameFile = getTempDir() / "moe_test_emergency_late_stamp_same.txt"
    writeFile(editedFile, "disk")
    defer:
      removeFile(editedFile)
      removeFile(sameFile)

    let edited = newTextBuffer("edited", some(editedFile))
    discard e.vsplitWithBuffer(edited)
    markEdited(edited)

    writeFile(sameFile, "same content")
    let same = newTextBuffer("", some(sameFile))
    discard e.vsplitWithBuffer(same)
    check same.loadFile(sameFile).isOk
    check same.replaceAllLines(@["other"]).isOk
    check same.replaceAllLines(@["same content"]).isOk
    writeFile(sameFile, "rewritten elsewhere")

    let grown = "grown by the time the last copy landed"
    committed.setLen 0
    describedAtCommit.setLen 0
    beforeSecondCommit = proc() {.raises: [].} =
      try:
        writeFile(editedFile, grown)
      except CatchableError:
        discard
    defer:
      beforeSecondCommit = nil
    let savedPaths =
      e.emergencySaveBuffers(ckCrash, "", TestRecoveryDir, commit = recordCommit)
    require savedPaths.len == 2
    check committed[1].contains("late_stamp_same")
    let manifest = parseJson(readFile(sessionDirOf(savedPaths[0]) / MetadataName))
    var sizes: seq[int]
    for entry in manifest["files"]:
      if entry["origin"].getStr.endsWith("late_stamp_edited.txt"):
        sizes.add entry[ManifestOriginSizeKey].getInt
    check sizes == @[grown.len]

  test "Each copy of a buffer holding what it last read is described before the next is written":
    let e = createTestEditor()

    let firstFile = getTempDir() / "moe_test_emergency_describe_first.txt"
    let secondFile = getTempDir() / "moe_test_emergency_describe_second.txt"
    defer:
      removeFile(firstFile)
      removeFile(secondFile)

    for (path, target) in [(firstFile, "first"), (secondFile, "second")]:
      writeFile(path, target)
      let buf = newTextBuffer("", some(path))
      discard e.vsplitWithBuffer(buf)
      check buf.loadFile(path).isOk
      check buf.replaceAllLines(@["other"]).isOk
      check buf.replaceAllLines(@[target]).isOk
      writeFile(path, "rewritten elsewhere")

    committed.setLen 0
    describedAtCommit.setLen 0
    let savedPaths =
      e.emergencySaveBuffers(ckCrash, "", TestRecoveryDir, commit = recordCommit)
    check savedPaths.len == 2
    require committed.len == 2
    check describedAtCommit[1].contains(committed[0])

  test "A buffer whose path is a pipe is preserved without reading it":
    # Reading a pipe nobody writes to would hang the dying process.
    when defined(posix):
      let e = createTestEditor()
      let fifo = getTempDir() / "moe_test_emergency_fifo"
      discard tryRemoveFile(fifo)
      require mkfifo(fifo.cstring, 0o600) == 0
      defer:
        removeFile(fifo)

      let buf = newTextBuffer("", some(fifo))
      discard e.vsplitWithBuffer(buf)
      buf.changeSeq = buf.savedSeq + 1
      # Zero bytes, the size a pipe reports, and what it last read.
      buf.endOfLine = false
      require buf.getFileContent().len == 0
      buf.lastLoadedContent = some(fingerprint(""))

      check saveSession(e).len == 1

  test "Save buffer without file path":
    let e = createTestEditor()

    let buf = e.activeBuffer()
    markEdited(buf)

    let savedPaths = saveSession(e)
    check savedPaths.len == 1
    check extractFilename(savedPaths[0]) == "0000-untitled"

    let metadata = parseJson(readFile(sessionDirOf(savedPaths[0]) / MetadataName))
    check not metadata["files"][0].hasKey("origin")

  test "Save multiple modified buffers":
    let e = createTestEditor()

    let testFile1 = getTempDir() / "moe_test_emergency_multi1.txt"
    let testFile2 = getTempDir() / "moe_test_emergency_multi2.txt"
    writeFile(testFile1, "content 1")
    writeFile(testFile2, "content 2")
    defer:
      removeFile(testFile1)
      removeFile(testFile2)

    discard e.loadFile(testFile1)
    markEdited(e.activeBuffer())

    let buf2 = newTextBuffer("content 2", some(testFile2))
    discard e.vsplitWithBuffer(buf2)
    markEdited(buf2)

    let savedPaths = saveSession(e)
    check savedPaths.len == 2

    let metadata = parseJson(readFile(sessionDirOf(savedPaths[0]) / MetadataName))
    check metadata["files"].len == 2

    let names = savedPaths.mapIt(extractFilename(it))
    check names.anyIt(it == "0000-moe_test_emergency_multi1.txt")
    check names.anyIt(it == "0001-moe_test_emergency_multi2.txt")

  test "Deduplicate same buffer in multiple windows":
    let e = createTestEditor()

    let testFile = getTempDir() / "moe_test_emergency_dedup.txt"
    writeFile(testFile, "shared content")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)
    let sharedBuf = e.activeBuffer()
    markEdited(sharedBuf)

    # Split with same buffer
    discard e.vsplitWithBuffer(sharedBuf)

    check saveSession(e).len == 1

  test "Handle duplicate filenames from different paths":
    let e = createTestEditor()

    let dir1 = getTempDir() / "moe_test_dup_dir1"
    let dir2 = getTempDir() / "moe_test_dup_dir2"
    createDir(dir1)
    createDir(dir2)
    let file1 = dir1 / "same.txt"
    let file2 = dir2 / "same.txt"
    writeFile(file1, "from dir1")
    writeFile(file2, "from dir2")
    defer:
      removeDir(dir1)
      removeDir(dir2)

    discard e.loadFile(file1)
    markEdited(e.activeBuffer())

    let buf2 = newTextBuffer("from dir2", some(file2))
    discard e.vsplitWithBuffer(buf2)
    markEdited(buf2)

    let savedPaths = saveSession(e)
    check savedPaths.len == 2

    let metadata = parseJson(readFile(sessionDirOf(savedPaths[0]) / MetadataName))
    var recorded: seq[string]
    for entry in metadata["files"]:
      recorded.add entry["origin"].getStr
    check file1 in recorded
    check file2 in recorded

  test "Mixed modified and unmodified buffers":
    let e = createTestEditor()

    let testFile1 = getTempDir() / "moe_test_emergency_mix1.txt"
    let testFile2 = getTempDir() / "moe_test_emergency_mix2.txt"
    writeFile(testFile1, "modified content")
    writeFile(testFile2, "unmodified content")
    defer:
      removeFile(testFile1)
      removeFile(testFile2)

    discard e.loadFile(testFile1)
    markEdited(e.activeBuffer())

    let buf2 = newTextBuffer("unmodified content", some(testFile2))
    discard e.vsplitWithBuffer(buf2)
    # buf2 is NOT modified

    let savedPaths = saveSession(e)
    check savedPaths.len == 1

    let filename = extractFilename(savedPaths[0])
    check filename == "0000-" & extractFilename(testFile1)

  test "Save modified buffer in background tab of same window":
    # Regression: emergency save previously iterated only windowManager.windows,
    # missing modified buffers that live in a window's per-window tab list
    # (bufferIds) but are not the currently-displayed .buffer.
    let e = createTestEditor()

    let testFileFg = getTempDir() / "moe_test_emergency_fg.txt"
    let testFileBg = getTempDir() / "moe_test_emergency_bg.txt"
    writeFile(testFileFg, "foreground content")
    writeFile(testFileBg, "background content")
    defer:
      removeFile(testFileFg)
      removeFile(testFileBg)

    discard e.loadFile(testFileFg)
    let fgBuf = e.activeBuffer()
    markEdited(fgBuf)

    # Register a second buffer in e.buffers and the same window's tab list
    # WITHOUT activating it, so it stays a background tab (not window.buffer).
    let bgBuf = newTextBuffer("background content", some(testFileBg))
    e.addBuffer(bgBuf)
    e.addBufferToWindowList(bgBuf)
    markEdited(bgBuf)

    check e.activeWindow.buffer == fgBuf
    check bgBuf.id in e.activeWindow.bufferIds

    let savedPaths = saveSession(e)
    check savedPaths.len == 2

    let filenames = savedPaths.mapIt(extractFilename(it))
    check filenames.anyIt(it == "0000-" & extractFilename(testFileFg))
    check filenames.anyIt(it == "0001-" & extractFilename(testFileBg))

  test "Save modified buffer not attached to any window":
    # Regression: a buffer that lives in e.buffers but no window currently
    # displays it (or has it in its tab list) must still be crash-saved.
    let e = createTestEditor()

    let testFile = getTempDir() / "moe_test_emergency_orphan.txt"
    writeFile(testFile, "orphan content")
    defer:
      removeFile(testFile)

    let orphan = newTextBuffer("orphan content", some(testFile))
    e.addBuffer(orphan)
    markEdited(orphan)

    check e.activeWindow.buffer != orphan
    check orphan.id notin e.activeWindow.bufferIds

    let savedPaths = saveSession(e)
    check savedPaths.anyIt(extractFilename(it) == "0000-" & extractFilename(testFile))

  test "No modified buffers removes empty directory":
    let e = createTestEditor()
    # Default buffer is not modified

    let savedPaths = saveSession(e)
    check savedPaths.len == 0

    # The timestamped subdirectory should have been cleaned up
    if dirExists(TestRecoveryDir):
      var subdirCount = 0
      for _ in walkDirs(TestRecoveryDir / "*"):
        inc subdirCount
      check subdirCount == 0

  test "Continuity and detail are recorded as given":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    markEdited(buf)

    let saved = e.emergencySaveBuffers(ckSignal, "SIGTERM", TestRecoveryDir)
    require saved.len == 1

    let metadata = parseJson(readFile(sessionDirOf(saved[0]) / MetadataName))
    check metadata["continuity"].getStr == "signal"
    check metadata["detail"].getStr == "SIGTERM"

  test "A caller that cannot say what happened records unknown":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    markEdited(buf)

    let saved = e.emergencySaveBuffers(ckUnknown, "", TestRecoveryDir)
    require saved.len == 1

    check parseJson(readFile(sessionDirOf(saved[0]) / MetadataName))["continuity"].getStr ==
      "unknown"

  test "A long exception message is kept bounded":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    markEdited(buf)

    let saved = e.emergencySaveBuffers(ckCrash, "x".repeat(10_000), TestRecoveryDir)
    require saved.len == 1

    check parseJson(readFile(sessionDirOf(saved[0]) / MetadataName))["detail"].getStr.len ==
      4096

  test "A file the user called recovery.json is not the metadata":
    let e = createTestEditor()

    let testFile = getTempDir() / "recovery.json"
    writeFile(testFile, "the user's own recovery.json")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)
    let buf = e.activeBuffer()
    markEdited(buf)

    let saved = saveSession(e)
    require saved.len == 1
    check extractFilename(saved[0]) == "0000-recovery.json"
    check readFile(saved[0]) == "the user's own recovery.json"

    let sessions = testStore().sessions()
    require sessions.len == 1
    require sessions[0].files.len == 1
    check sessions[0].files[0].origin.get == testFile

  test "A name at the filesystem's limit still preserves":
    let e = createTestEditor()

    let dir = getTempDir() / "moe_test_emergency_longname"
    createDir(dir)
    defer:
      removeDir(dir)
    let testFile = dir / ("n".repeat(250) & ".txt")
    var writable = true
    try:
      writeFile(testFile, "long name content")
    except CatchableError:
      writable = false
    if not writable:
      skip()
    else:
      discard e.loadFile(testFile)
      let buf = e.activeBuffer()
      markEdited(buf)

      let saved = saveSession(e)
      require saved.len == 1
      check extractFilename(saved[0]).len <= 250
      check readFile(saved[0]) == "long name content"

  test "A multi-byte name is cut at a character boundary":
    let e = createTestEditor()

    let dir = getTempDir() / "moe_test_emergency_multibyte"
    createDir(dir)
    defer:
      removeDir(dir)
    # 3 bytes per character, so a byte-wise cut at 80 would split one.
    let testFile = dir / ("あ".repeat(60) & ".txt")
    writeFile(testFile, "multibyte name")

    discard e.loadFile(testFile)
    let buf = e.activeBuffer()
    markEdited(buf)

    let saved = saveSession(e)
    require saved.len == 1
    let name = extractFilename(saved[0])
    check name.len <= 5 + MaxPayloadBaseLen
    check name.endsWith("あ")
    check readFile(saved[0]) == "multibyte name"

  test "A file stamped beyond 2262 still preserves":
    let e = createTestEditor()

    let testFile = getTempDir() / "moe_test_emergency_future.txt"
    writeFile(testFile, "original content")
    defer:
      removeFile(testFile)
    # A mtime whose nanoseconds do not fit in an int64.
    setLastModificationTime(testFile, initTime(10413792000'i64, 0))

    discard e.loadFile(testFile)
    let buf = e.activeBuffer()
    markEdited(buf)

    let saved = saveSession(e)
    require saved.len == 1

    # The stamp is left unrecorded; the copy and its size still are.
    let metadata = parseFile(sessionDirOf(saved[0]) / MetadataName)
    check metadata["files"][0]["name"].getStr == extractFilename(saved[0])
    check not metadata["files"][0].hasKey("originMtimeNs")
    check metadata["files"][0]["originSize"].getInt == "original content".len

suite "emergency - directory identity":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "The session directory carries the pid, not the timestamp alone":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    markEdited(buf)
    let saved = saveSession(e)
    require saved.len == 1

    check sessionDirOf(saved[0]).lastPathPart.endsWith("_" & $getCurrentProcessId())

  test "A session that saved nothing leaves a filled directory alone":
    # Regression: an empty preserve used to remove another session's directory.
    let first = createTestEditor()
    let firstBuf = first.activeBuffer()
    markEdited(firstBuf)
    let saved = saveSession(first)
    require saved.len == 1

    let second = createTestEditor()
    discard saveSession(second)

    check fileExists(saved[0])
    check testStore().sessions().len == 1

  test "A second preserve from the same process still preserves":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    markEdited(buf)

    let first = saveSession(e)
    require first.len == 1

    let second = saveSession(e)
    check second.len == 1
    check second[0].parentDir != first[0].parentDir
    check fileExists(first[0])
    check fileExists(second[0])

suite "emergency - recovery metadata paths":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "A buffer opened by a relative path is recorded absolutely":
    let e = createTestEditor()

    let dir = getTempDir() / "moe_test_emergency_relative"
    createDir(dir)
    defer:
      removeDir(dir)
    writeFile(dir / "same.txt", "original content")

    let previousDir = getCurrentDir()
    setCurrentDir(dir)
    defer:
      setCurrentDir(previousDir)

    discard e.loadFile("same.txt")
    let buf = e.activeBuffer()
    markEdited(buf)

    let savedPaths = saveSession(e)
    check savedPaths.len == 1

    let metadata = parseFile(sessionDirOf(savedPaths[0]) / MetadataName)
    check metadata["files"][0]["origin"].getStr == dir / "same.txt"

suite "emergency - sessions":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "Nothing to report when the directory is missing or empty":
    check testStore().sessions().len == 0
    createDir(TestRecoveryDir)
    check testStore().sessions().len == 0

  test "The newest session is the one that recorded the latest time":
    # Directory names are not time order; savedAt is.
    plantSession(
      "20260919T000000_1",
      savedAt = 1_700_000_000,
      files = @[("0000-planted.txt", "/tmp/old.txt", "old")],
    )
    plantSession(
      "20260918T000000_2",
      savedAt = 1_700_000_900,
      files = @[("0000-planted.txt", "/tmp/new.txt", "new")],
    )

    let sessions = testStore().sessions()
    require sessions.len == 2
    check sessions[0].files[0].origin.get == "/tmp/new.txt"
    check sessions[1].files[0].origin.get == "/tmp/old.txt"

  test "What a session preserved comes back":
    plantSession("20260918T000000_1", continuity = "signal", detail = "TERM")

    let sessions = testStore().sessions()
    require sessions.len == 1
    check sessions[0].manifest == msRead
    check sessions[0].listed
    check sessions[0].continuity == ckSignal
    check sessions[0].detail == "TERM"
    check sessions[0].savedAt.get.toUnix == 1758000000
    check sessions[0].files[0].origin.get == "/tmp/planted.txt"
    check readFile(sessions[0].files[0].path) == "preserved"

  test "A preserve that died before the manifest is still read":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir / PayloadDirName)
    writeFile(dir / PayloadDirName / "0000-half.txt", "half written")

    let sessions = testStore().sessions()
    require sessions.len == 1
    check sessions[0].manifest == msAbsent
    check sessions[0].listed
    check sessions[0].continuity == ckUnknown
    check sessions[0].savedAt.isNone
    require sessions[0].files.len == 1
    check sessions[0].files[0].origin.isNone
    check readFile(sessions[0].files[0].path) == "half written"

  test "A scratch name left behind is not a copy":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir / PayloadDirName)
    writeFile(dir / PayloadDirName / ".0000-half.txt", "half written")
    writeFile(dir / PayloadDirName / "0001-done.txt", "done")

    let sessions = testStore().sessions()
    require sessions.len == 1
    require sessions[0].files.len == 1
    check sessions[0].files[0].path.lastPathPart == "0001-done.txt"

  test "A link under payload is not a copy":
    let target = getTempDir() / "moe_test_payload_link_target"
    writeFile(target, "someone else's bytes")
    defer:
      removeFile(target)
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir / PayloadDirName)
    createSymlink(target, dir / PayloadDirName / "0000-link.txt")

    check testStore().sessions().len == 0

  test "A copy the manifest does not name is still offered":
    plantSession("20260918T000000_1")
    writeFile(
      TestRecoveryDir / "20260918T000000_1" / PayloadDirName / "0001-extra.txt", "extra"
    )

    let sessions = testStore().sessions()
    require sessions.len == 1
    check sessions[0].files.len == 2

  test "An index past four digits is still a copy":
    # The writer pads the index to a minimum width, so a session with more
    # than 9999 modified buffers writes longer names. The grammar is digits
    # and a dash, not exactly four digits.
    check isPayloadFileName(payloadFileName(0, "x"))
    check isPayloadFileName(payloadFileName(10000, "x"))
    check not isPayloadFileName("10000x")
    check not isPayloadFileName("10000-")

    plantSession(
      "20260918T000000_1", files = @[("10000-planted.txt", "/tmp/planted.txt", "big")]
    )
    let sessions = testStore().sessions()
    require sessions.len == 1
    require sessions[0].files.len == 1
    check sessions[0].files[0].path.lastPathPart == "10000-planted.txt"
    check sessions[0].files[0].origin.get == "/tmp/planted.txt"

  test "The metadata name a legacy manifest claims is not a copy":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir)
    writeFile(
      dir / MetadataName, """{"recovery.json":{"originalPath":"/tmp/user-made.json"}}"""
    )

    check testStore().sessions().len == 0

  test "A manifest version this reader does not know is not interpreted":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir / PayloadDirName)
    writeFile(dir / PayloadDirName / "0000-planted.txt", "preserved")
    writeFile(
      dir / MetadataName,
      """{"format":"moe-recovery","version":99,"savedAt":123,"continuity":"signal",""" &
        """"files":[{"name":"0000-planted.txt","origin":"/tmp/planted.txt"}]}""",
    )

    let sessions = testStore().sessions()
    require sessions.len == 1
    check sessions[0].manifest == msUnreadable
    require sessions[0].files.len == 1
    check sessions[0].files[0].origin.isNone
    check sessions[0].savedAt.isNone
    check sessions[0].continuity == ckUnknown
    check readFile(sessions[0].files[0].path) == "preserved"

  test "A session that reported no continuity reads as unknown":
    plantSession("20260918T000000_1", continuity = "something else")
    let sessions = testStore().sessions()
    require sessions.len == 1
    check sessions[0].continuity == ckUnknown

  test "A directory that cannot be listed is not reported as empty":
    when defined(posix):
      if not permissionsAreEnforced():
        skip()
      else:
        let dir = TestRecoveryDir / "20260918T000000_1"
        createDir(dir / PayloadDirName)
        writeFile(dir / PayloadDirName / "0000-planted.txt", "preserved")
        setFilePermissions(dir / PayloadDirName, {})
        defer:
          setFilePermissions(
            dir / PayloadDirName, {fpUserRead, fpUserWrite, fpUserExec}
          )

        let sessions = testStore().sessions()
        require sessions.len == 1
        check not sessions[0].listed
        check sessions[0].files.len == 0

  test "A session holding only metadata is not offered":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir / PayloadDirName)
    writeFile(dir / MetadataName, "{}")
    check testStore().sessions().len == 0

  test "Files survive metadata that cannot be read":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir / PayloadDirName)
    writeFile(dir / PayloadDirName / "0000-planted.txt", "preserved")
    writeFile(dir / MetadataName, "{ this is not json")

    let sessions = testStore().sessions()
    require sessions.len == 1
    check sessions[0].manifest == msUnreadable
    check sessions[0].files.len == 1
    check sessions[0].files[0].origin.isNone
    check readFile(sessions[0].files[0].path) == "preserved"

  test "The manifest's temporary name is not a copy":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir)
    writeFile(dir / "0000-planted.txt", "preserved")
    writeFile(dir / "recovery.json.tmp", "{ half written")

    let sessions = testStore().sessions()
    require sessions.len == 1
    check sessions[0].manifest == msAbsent
    require sessions[0].files.len == 1
    check sessions[0].files[0].path.lastPathPart == "0000-planted.txt"

  test "A name the filesystem hides comes back":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir)
    writeFile(dir / "0000-.env", "SECRET=1")
    writeFile(dir / MetadataName, "{ not json")

    let sessions = testStore().sessions()
    require sessions.len == 1
    require sessions[0].files.len == 1
    check sessions[0].files[0].path.lastPathPart == "0000-.env"

  test "An entry naming a file outside the session is not followed":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir)
    writeFile(dir / "0000-planted.txt", "preserved")
    writeFile(
      dir / MetadataName,
      """{"0000-planted.txt":{"originalPath":"/tmp/planted.txt"},""" &
        """"../escape.txt":{"originalPath":"/etc/passwd"}}""",
    )
    writeFile(TestRecoveryDir / "escape.txt", "not ours")

    let sessions = testStore().sessions()
    require sessions.len == 1
    require sessions[0].files.len == 1
    check sessions[0].files[0].path.lastPathPart == "0000-planted.txt"
    check sessions[0].files[0].origin.get == "/tmp/planted.txt"

  test "An entry naming a copy that is not there is skipped":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir / PayloadDirName)
    writeFile(dir / PayloadDirName / "0000-planted.txt", "preserved")
    writeFile(
      dir / MetadataName,
      """{"format":"moe-recovery","version":3,"files":[""" &
        """{"name":"0001-missing.txt","origin":"/tmp/missing.txt"},""" &
        """{"name":"0000-planted.txt","origin":"/tmp/planted.txt"}]}""",
    )

    let sessions = testStore().sessions()
    require sessions.len == 1
    require sessions[0].files.len == 1
    check sessions[0].files[0].path.lastPathPart == "0000-planted.txt"
    check sessions[0].files[0].origin.get == "/tmp/planted.txt"

  test "A manifest written before the format was versioned still reads":
    plantLegacySession(
      "20260918T000000_1", meta = """{"planted.txt":{"originalPath":"/tmp/v0.txt"}}"""
    )

    let sessions = testStore().sessions()
    require sessions.len == 1
    check sessions[0].manifest == msRead
    check sessions[0].files[0].origin.get == "/tmp/v0.txt"
    check sessions[0].continuity == ckUnknown
    check sessions[0].savedAt.isNone

  test "A manifest shape this reader does not know only costs the origins":
    plantLegacySession(
      "20260918T000000_1",
      meta = (
        """{"version":1,"cause":"signal","detail":"TERM","savedAt":1758000000,""" &
        """"files":{"planted.txt":{"originalPath":"/tmp/planted.txt"}}}"""
      ),
    )

    let sessions = testStore().sessions()
    require sessions.len == 1
    require sessions[0].files.len == 1
    check sessions[0].files[0].origin.isNone
    check readFile(sessions[0].files[0].path) == "preserved"
    check sessions[0].continuity == ckUnknown
    check sessions[0].savedAt.isNone

suite "emergency - asking about one file":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "The newest copy of a file comes first":
    plantSession(
      "20260917T000000_1",
      savedAt = 1_700_000_000,
      files = @[("0000-planted.txt", "/tmp/wanted.txt", "old")],
    )
    plantSession(
      "20260918T000000_2",
      savedAt = 1_700_000_900,
      files = @[("0000-planted.txt", "/tmp/wanted.txt", "new")],
    )
    plantSession(
      "20260918T000000_3",
      savedAt = 1_700_001_000,
      files = @[("0000-planted.txt", "/tmp/other.txt", "other")],
    )

    let copies = testIndex().copiesOf("/tmp/wanted.txt")
    check copies.len == 2
    check readFile(copies[0].file.path) == "new"
    check readFile(copies[1].file.path) == "old"

  test "How the path was spelled does not matter":
    let dir = getTempDir() / "moe_test_emergency_spelling"
    createDir(dir)
    defer:
      removeDir(dir)
    let testFile = dir / "wanted.txt"
    writeFile(testFile, "on disk")
    plantSession("20260918T000000_1", files = @[("0000-planted.txt", testFile, "kept")])

    let previousDir = getCurrentDir()
    setCurrentDir(dir)
    defer:
      setCurrentDir(previousDir)

    check testIndex().copiesOf("wanted.txt").len == 1
    check testIndex().copiesOf("./wanted.txt").len == 1

  test "An unnamed buffer answers for no file":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    markEdited(buf)
    require saveSession(e).len == 1

    check testIndex().copiesOf("").len == 0
    check testIndex().copiesOf("/tmp/anything.txt").len == 0

suite "emergency - whether the file already has a copy":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  proc preserveModified(
      path, content: string
  ): tuple[index: RecoveryIndex, copy: PreservedCopy] =
    let e = createTestEditor()
    discard e.loadFile(path)
    let buf = e.activeBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), content)
    require saveSession(e).len == 1
    let index = testIndex()
    let copies = index.copiesOf(path)
    require copies.len == 1
    (index: index, copy: copies[0])

  test "A copy the disk already holds is not worth a prompt":
    let dir = getTempDir() / "moe_test_emergency_same"
    createDir(dir)
    defer:
      removeDir(dir)
    let testFile = dir / "f.txt"
    writeFile(testFile, "original\n")

    let (index, copy) = preserveModified(testFile, "edited ")
    check not index.holds(copy.file, [])

    writeFile(testFile, readFile(copy.file.path))
    check index.holds(copy.file, [])

  test "A file written after the crash is decided by its content":
    let dir = getTempDir() / "moe_test_emergency_moved"
    createDir(dir)
    defer:
      removeDir(dir)
    let testFile = dir / "f.txt"
    writeFile(testFile, "original\n")

    let (index, copy) = preserveModified(testFile, "edited ")

    writeFile(testFile, "someone else wrote this\n")
    check not index.holds(copy.file, [])

    writeFile(testFile, readFile(copy.file.path))
    check index.holds(copy.file, [])

  test "A session that recorded no stamp is compared by content":
    let dir = getTempDir() / "moe_test_emergency_nostamp"
    createDir(dir)
    defer:
      removeDir(dir)
    let testFile = dir / "f.txt"
    writeFile(testFile, "preserved")
    plantLegacySession(
      "20260918T000000_1", content = "preserved", originalPath = testFile
    )

    let index = testIndex()
    let copies = index.copiesOf(testFile)
    require copies.len == 1
    check copies[0].file.originStamp.mtime.isNone
    check index.holds(copies[0].file, [])

    writeFile(testFile, "something else entirely")
    check not index.holds(copies[0].file, [])

  test "A copy from an unnamed buffer belongs to no file":
    plantSession("20260918T000000_1", files = @[("0000-untitled", "", "preserved")])
    let index = testIndex()
    check index.copiesOf("/tmp/anything.txt").len == 0

    require index.sessions.len == 1
    let unnamed = index.sessions[0].files[0]
    check not index.holds(unnamed, [])
    check index.owed(unnamed, [])

  test "A file the crash was the end of holds nothing":
    let dir = getTempDir() / "moe_test_emergency_gone"
    createDir(dir)
    defer:
      removeDir(dir)
    let testFile = dir / "f.txt"
    writeFile(testFile, "original\n")

    let (index, copy) = preserveModified(testFile, "edited ")
    removeFile(testFile)
    check not index.holds(copy.file, [])
    check index.owed(copy.file, [])

  test "A copy discarded since the last read is gone at the next":
    let dir = getTempDir() / "moe_test_emergency_nocopy"
    createDir(dir)
    defer:
      removeDir(dir)
    let testFile = dir / "f.txt"
    writeFile(testFile, "original\n")

    let (index, copy) = preserveModified(testFile, "edited ")
    removeFile(copy.file.path)
    index.refresh()
    check index.copiesOf(testFile).len == 0

suite "emergency - discardSession":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "A discarded session is gone for good":
    plantSession("20260918T000000_1")
    let sessions = testStore().sessions()
    require sessions.len == 1

    var reason = ""
    check testStore().discardSession(sessions[0].dir, reason)
    check reason.len == 0
    check testStore().sessions().len == 0

suite "emergency - marking a copy reviewed":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "The mark survives a re-read and can be taken back":
    plantSession(
      "20260918T000000_1",
      files = @[
        ("0000-done.txt", "/tmp/done.txt", "done"),
        ("0001-open.txt", "/tmp/open.txt", "open"),
      ],
    )
    let dir = TestRecoveryDir / "20260918T000000_1"
    let copyPath = dir / PayloadDirName / "0000-done.txt"

    var reason = ""
    check testStore().setReviewed(copyPath, dir, true, reason)
    check reason.len == 0
    var files = testStore().sessions()[0].files
    require files.len == 2
    check files[0].reviewed
    check not files[1].reviewed
    # Only the mark changed: the copy is still there to restore.
    check readFile(copyPath) == "done"
    check files[0].origin == some("/tmp/done.txt")

    check testStore().setReviewed(copyPath, dir, false, reason)
    files = testStore().sessions()[0].files
    check not files[0].reviewed

  test "Marking leaves the manifest as it was":
    # Another editor may be reading or discarding in the same session.
    plantSession("20260918T000000_1")
    let dir = TestRecoveryDir / "20260918T000000_1"
    let before = readFile(dir / MetadataName)
    let copyPath = testStore().sessions()[0].files[0].path

    var reason = ""
    check testStore().setReviewed(copyPath, dir, true, reason)
    check readFile(dir / MetadataName) == before

  test "A session with no manifest carries the mark":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir / PayloadDirName)
    writeFile(dir / PayloadDirName / "0000-half.txt", "half written")

    var reason = ""
    check testStore().setReviewed(
      dir / PayloadDirName / "0000-half.txt", dir, true, reason
    )
    check testStore().sessions()[0].files[0].reviewed

  test "A legacy session carries the mark in its own shape":
    plantLegacySession("20260918T000000_1")
    let dir = TestRecoveryDir / "20260918T000000_1"
    let before = readFile(dir / MetadataName)
    let files = testStore().sessions()[0].files

    var reason = ""
    check testStore().setReviewed(files[0].path, dir, true, reason)
    check readFile(dir / MetadataName) == before
    # The mark is not read back as one more copy.
    let after = testStore().sessions()[0].files
    check after.len == files.len
    check after[0].reviewed

  test "Discarding a copy takes its mark with it":
    plantSession(
      "20260918T000000_1",
      files = @[
        ("0000-done.txt", "/tmp/done.txt", "done"),
        ("0001-open.txt", "/tmp/open.txt", "open"),
      ],
    )
    let dir = TestRecoveryDir / "20260918T000000_1"
    let copyPath = dir / PayloadDirName / "0000-done.txt"
    var reason = ""
    check testStore().setReviewed(copyPath, dir, true, reason)
    check testStore().discardCopy(copyPath, dir, reason)
    check not fileExists(dir / ReviewedDirName / "0000-done.txt")

  test "A linked mark is not written through":
    when defined(posix):
      plantSession("20260918T000000_1")
      let dir = TestRecoveryDir / "20260918T000000_1"
      let copyPath = testStore().sessions()[0].files[0].path
      let victim = getTempDir() / "moe_test_reviewed_victim.txt"
      writeFile(victim, "keep me")
      defer:
        removeFile(victim)
      createDir(dir / ReviewedDirName)
      createSymlink(victim, dir / ReviewedDirName / copyPath.lastPathPart)

      var reason = ""
      check not testStore().setReviewed(copyPath, dir, true, reason)
      check readFile(victim) == "keep me"

  test "A copy outside the store is refused":
    plantSession("20260918T000000_1")
    let outside = getTempDir() / "moe_test_reviewed_outside"
    createDir(outside)
    defer:
      removeDir(outside)

    var reason = ""
    check not testStore().setReviewed(
      outside / "0000-planted.txt", outside, true, reason
    )
    check reason.len > 0

proc markReviewed(session, copyName: string, age: Duration) =
  ## Mark a planted copy reviewed, `age` ago.
  let dir = TestRecoveryDir / session
  var reason = ""
  require testStore().setReviewed(dir / PayloadDirName / copyName, dir, true, reason)
  setLastModificationTime(dir / ReviewedDirName / copyName, getTime() - age)

suite "emergency - pruning settled sessions":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "A session reviewed long ago is pruned":
    plantSession("20260918T000000_1")
    markReviewed("20260918T000000_1", "0000-planted.txt", initDuration(days = 15))

    check testStore().pruneSettledSessions() == @[TestRecoveryDir / "20260918T000000_1"]
    check not dirExists(TestRecoveryDir / "20260918T000000_1")

  test "A session reviewed recently is kept":
    plantSession("20260918T000000_1")
    markReviewed("20260918T000000_1", "0000-planted.txt", initDuration(days = 1))

    check testStore().pruneSettledSessions().len == 0
    check testStore().sessions().len == 1

  test "An old session with an unreviewed copy is kept":
    plantSession(
      "20260918T000000_1",
      savedAt = 1000000000,
      files = @[
        ("0000-done.txt", "/tmp/done.txt", "done"),
        ("0001-open.txt", "/tmp/open.txt", "open"),
      ],
    )
    markReviewed("20260918T000000_1", "0000-done.txt", initDuration(days = 15))

    check testStore().pruneSettledSessions().len == 0
    check testStore().sessions()[0].files.len == 2

  test "The latest review decides, not the first":
    plantSession(
      "20260918T000000_1",
      files = @[("0000-a.txt", "/tmp/a.txt", "a"), ("0001-b.txt", "/tmp/b.txt", "b")],
    )
    markReviewed("20260918T000000_1", "0000-a.txt", initDuration(days = 30))
    markReviewed("20260918T000000_1", "0001-b.txt", initDuration(days = 1))

    check testStore().pruneSettledSessions().len == 0

  test "A copy taken back from review keeps its session":
    plantSession("20260918T000000_1")
    let dir = TestRecoveryDir / "20260918T000000_1"
    markReviewed("20260918T000000_1", "0000-planted.txt", initDuration(days = 15))
    var reason = ""
    check testStore().setReviewed(
      dir / PayloadDirName / "0000-planted.txt", dir, false, reason
    )

    check testStore().pruneSettledSessions().len == 0

  test "Only the settled session goes":
    plantSession("20260918T000000_1")
    plantSession("20260918T000000_2")
    markReviewed("20260918T000000_1", "0000-planted.txt", initDuration(days = 15))

    check testStore().pruneSettledSessions().len == 1
    check testStore().sessions().mapIt(it.dir) ==
      @[TestRecoveryDir / "20260918T000000_2"]

  test "An empty session directory is left alone":
    # Possibly a preserve that has not written its first copy yet.
    createDir(TestRecoveryDir / "20260918T000000_1" / PayloadDirName)

    check testStore().pruneSettledSessions().len == 0
    check dirExists(TestRecoveryDir / "20260918T000000_1")

  test "Marks reached through a linked reviewed directory settle nothing":
    when defined(posix):
      plantSession("20260918T000000_1")
      let outside = getTempDir() / "moe_test_prune_linked_reviewed"
      createDir(outside)
      defer:
        removeDir(outside)
      writeFile(outside / "0000-planted.txt", "")
      setLastModificationTime(
        outside / "0000-planted.txt", getTime() - initDuration(days = 15)
      )
      createSymlink(outside, TestRecoveryDir / "20260918T000000_1" / ReviewedDirName)

      check testStore().pruneSettledSessions().len == 0
      check fileExists(outside / "0000-planted.txt")

  test "A mark that is a link settles nothing":
    when defined(posix):
      plantSession("20260918T000000_1")
      let outside = getTempDir() / "moe_test_prune_linked_mark"
      writeFile(outside, "")
      defer:
        removeFile(outside)
      setLastModificationTime(outside, getTime() - initDuration(days = 15))
      let reviewed = TestRecoveryDir / "20260918T000000_1" / ReviewedDirName
      createDir(reviewed)
      createSymlink(outside, reviewed / "0000-planted.txt")

      check testStore().pruneSettledSessions().len == 0
      check dirExists(TestRecoveryDir / "20260918T000000_1")

  test "A linked session directory settles nothing":
    when defined(posix):
      plantSession("20260918T000000_1")
      markReviewed("20260918T000000_1", "0000-planted.txt", initDuration(days = 15))
      let outside = getTempDir() / "moe_test_prune_linked_session"
      moveDir(TestRecoveryDir / "20260918T000000_1", outside)
      defer:
        removeDir(outside)
      createSymlink(outside, TestRecoveryDir / "20260918T000000_1")

      check testStore().pruneSettledSessions().len == 0
      check symlinkExists(TestRecoveryDir / "20260918T000000_1")

  test "A legacy session reviewed long ago is pruned":
    plantLegacySession("20260918T000000_1")
    let dir = TestRecoveryDir / "20260918T000000_1"
    var reason = ""
    require testStore().setReviewed(dir / "planted.txt", dir, true, reason)
    setLastModificationTime(
      dir / ReviewedDirName / "planted.txt", getTime() - initDuration(days = 15)
    )

    check testStore().pruneSettledSessions() == @[dir]

  test "A payload entry this build does not list keeps its session":
    # A copy a newer format names, or a scratch a killed preserve left.
    for extra in ["future-copy", ".0001-scratch.txt"]:
      plantSession("20260918T000000_1")
      let dir = TestRecoveryDir / "20260918T000000_1"
      writeFile(dir / PayloadDirName / extra, "unseen")
      markReviewed("20260918T000000_1", "0000-planted.txt", initDuration(days = 15))

      check testStore().pruneSettledSessions().len == 0
      check fileExists(dir / PayloadDirName / extra)
      removeDir(dir)

  test "A file beside the payload keeps its session":
    plantSession("20260918T000000_1")
    let dir = TestRecoveryDir / "20260918T000000_1"
    writeFile(dir / "stray.txt", "unseen")
    markReviewed("20260918T000000_1", "0000-planted.txt", initDuration(days = 15))

    check testStore().pruneSettledSessions().len == 0
    check fileExists(dir / "stray.txt")

  test "A mark that is a link is not read as a review":
    when defined(posix):
      plantSession("20260918T000000_1")
      let outside = getTempDir() / "moe_test_linked_mark_read"
      writeFile(outside, "")
      defer:
        removeFile(outside)
      let reviewed = TestRecoveryDir / "20260918T000000_1" / ReviewedDirName
      createDir(reviewed)
      createSymlink(outside, reviewed / "0000-planted.txt")

      check not testStore().sessions()[0].files[0].reviewed

  test "Reviewing a copy again restarts its retention":
    plantSession("20260918T000000_1")
    let dir = TestRecoveryDir / "20260918T000000_1"
    markReviewed("20260918T000000_1", "0000-planted.txt", initDuration(days = 15))
    var reason = ""
    check testStore().setReviewed(
      dir / PayloadDirName / "0000-planted.txt", dir, true, reason
    )

    check testStore().pruneSettledSessions().len == 0

  test "A manifest this build cannot read in full keeps its session":
    for meta in [
      """{"format":"moe-recovery","version":""" & $(FormatVersion + 1) &
        ""","files":[{"name":"0000-planted.txt"}]}""",
      """{"format":"another-format","files":[]}""", "{damaged",
    ]:
      plantSession("20260918T000000_1")
      let dir = TestRecoveryDir / "20260918T000000_1"
      writeFile(dir / MetadataName, meta)
      markReviewed("20260918T000000_1", "0000-planted.txt", initDuration(days = 15))

      check testStore().pruneSettledSessions().len == 0
      removeDir(dir)

  test "A formatted manifest without a payload directory keeps its session":
    plantLegacySession(
      "20260918T000000_1",
      meta = """{"format":"moe-recovery","version":""" & $(FormatVersion + 1) & "}",
    )
    let dir = TestRecoveryDir / "20260918T000000_1"
    var reason = ""
    require testStore().setReviewed(dir / "planted.txt", dir, true, reason)
    setLastModificationTime(
      dir / ReviewedDirName / "planted.txt", getTime() - initDuration(days = 15)
    )

    check testStore().pruneSettledSessions().len == 0

  test "A manifest whose file list is damaged keeps its session":
    plantSession("20260918T000000_1")
    let dir = TestRecoveryDir / "20260918T000000_1"
    writeFile(
      dir / MetadataName,
      """{"format":"moe-recovery","version":""" & $FormatVersion & ""","files":"x"}""",
    )
    markReviewed("20260918T000000_1", "0000-planted.txt", initDuration(days = 15))

    check testStore().pruneSettledSessions().len == 0

  test "A legacy copy called format is still a legacy manifest":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir)
    writeFile(dir / "format", "preserved")
    writeFile(dir / MetadataName, """{"format":{"originalPath":"/tmp/format"}}""")
    var reason = ""
    require testStore().setReviewed(dir / "format", dir, true, reason)
    setLastModificationTime(
      dir / ReviewedDirName / "format", getTime() - initDuration(days = 15)
    )

    check testStore().sessions()[0].manifest == msRead
    check testStore().pruneSettledSessions() == @[dir]

  test "A session whose manifest never landed can still be pruned":
    plantSession("20260918T000000_1")
    removeFile(TestRecoveryDir / "20260918T000000_1" / MetadataName)
    markReviewed("20260918T000000_1", "0000-planted.txt", initDuration(days = 15))

    check testStore().pruneSettledSessions().len == 1

  test "A store with no base directory prunes nothing":
    check testStore().pruneSettledSessions().len == 0
    check newRecoveryStore("").pruneSettledSessions().len == 0

suite "emergency - discardCopy":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "Dropping one copy takes it out of the manifest too":
    plantSession(
      "20260918T000000_1",
      files = @[
        ("0000-keep.txt", "/tmp/keep.txt", "keep"),
        ("0001-drop.txt", "/tmp/drop.txt", "drop"),
      ],
    )

    let dir = TestRecoveryDir / "20260918T000000_1"
    let payloadDir = dir / PayloadDirName
    var reason = ""
    check testStore().discardCopy(payloadDir / "0001-drop.txt", dir, reason)
    check reason.len == 0

    let sessions = testStore().sessions()
    require sessions.len == 1
    check sessions[0].files.len == 1
    check sessions[0].files[0].path.lastPathPart == "0000-keep.txt"
    check fileExists(payloadDir / "0000-keep.txt")
    check not fileExists(payloadDir / "0001-drop.txt")

    let meta = parseFile(dir / MetadataName)
    check meta["files"].len == 1
    check meta["files"][0]["name"].getStr == "0000-keep.txt"

  test "A manifest an older editor wrote is left alone":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir)
    writeFile(dir / "keep.txt", "keep")
    writeFile(dir / "drop.txt", "drop")
    writeFile(
      dir / MetadataName,
      """{"keep.txt":{"originalPath":"/tmp/keep.txt"},""" &
        """"drop.txt":{"originalPath":"/tmp/drop.txt"}}""",
    )

    var reason = ""
    check testStore().discardCopy(dir / "drop.txt", dir, reason)

    let sessions = testStore().sessions()
    require sessions.len == 1
    require sessions[0].files.len == 1
    check sessions[0].files[0].path.lastPathPart == "keep.txt"
    check parseFile(dir / MetadataName).hasKey("drop.txt")

  test "A manifest version this reader does not know is not rewritten":
    plantSession(
      "20260918T000000_1",
      files = @[
        ("0000-keep.txt", "/tmp/keep.txt", "keep"),
        ("0001-drop.txt", "/tmp/drop.txt", "drop"),
      ],
    )
    let dir = TestRecoveryDir / "20260918T000000_1"
    let payloadPath = dir / PayloadDirName / "0001-drop.txt"
    var meta = parseFile(dir / MetadataName)
    meta["version"] = %99
    writeFile(dir / MetadataName, $meta)

    var reason = ""
    check testStore().discardCopy(payloadPath, dir, reason)
    check reason.len == 0
    check not fileExists(payloadPath)
    # The unknown version is left alone rather than rewritten by this reader.
    let after = parseFile(dir / MetadataName)
    check after["version"].getInt == 99
    check after["files"].len == 2

  test "Dropping the last copy takes the session directory with it":
    plantSession("20260918T000000_1")
    let sessions = testStore().sessions()
    require sessions.len == 1
    let dir = sessions[0].dir
    let copyPath = sessions[0].files[0].path

    var reason = ""
    check testStore().discardCopy(copyPath, dir, reason)
    check reason.len == 0
    check testStore().sessions().len == 0
    check not dirExists(dir)

  test "A session that cannot be taken away is not reported as discarded":
    # removeDir can still fail after the copy is gone.
    when defined(posix):
      if not permissionsAreEnforced():
        skip()
      else:
        plantSession("20260918T000000_1")
        let sessions = testStore().sessions()
        require sessions.len == 1
        let dir = sessions[0].dir
        let copyPath = sessions[0].files[0].path

        # Deny write on the parent so removeDir fails after the copy is unlinked.
        setFilePermissions(TestRecoveryDir, {fpUserRead, fpUserExec})
        defer:
          setFilePermissions(TestRecoveryDir, {fpUserRead, fpUserWrite, fpUserExec})

        var reason = ""
        check not testStore().discardCopy(copyPath, dir, reason)
        check reason.len > 0
        check dirExists(dir)
        check testStore().sessions().len == 0

suite "emergency - discarding what leads out of the cache":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "A session reached through a symlink is unlinked, not emptied":
    # removeDir follows the link and deletes the target.
    let target = getTempDir() / "moe_test_symlink_target"
    removeDir(target)
    createDir(target)
    writeFile(target / "not_ours.txt", "someone else's file")
    defer:
      removeDir(target)

    let link = TestRecoveryDir / "20260918T000000_3"
    createDir(TestRecoveryDir)
    createSymlink(target, link)

    var reason = ""
    check testStore().discardSession(link, reason)
    check reason.len == 0
    check not symlinkExists(link)
    check fileExists(target / "not_ours.txt")

  test "A copy reached through a symlinked session is not unlinked":
    # copyPath is outside the cache; unlinking it would take the real file.
    let target = getTempDir() / "moe_test_symlink_copy_target"
    removeDir(target)
    createDir(target)
    writeFile(target / "not_ours.txt", "someone else's file")
    defer:
      removeDir(target)

    let link = TestRecoveryDir / "20260918T000000_4"
    createDir(TestRecoveryDir)
    createSymlink(target, link)

    var reason = ""
    check not testStore().discardCopy(link / "not_ours.txt", link, reason)
    check reason.contains("linked session")
    check fileExists(target / "not_ours.txt")
    check symlinkExists(link)

  test "A copy reached through a linked payload is not unlinked":
    # The session directory is real but its payload directory points outside
    # the cache. Unlinking through it would take the real file.
    let target = getTempDir() / "moe_test_symlink_payload_target"
    removeDir(target)
    createDir(target)
    writeFile(target / "0000-not_ours.txt", "someone else's file")
    defer:
      removeDir(target)

    let dir = TestRecoveryDir / "20260918T000000_5"
    createDir(dir)
    createSymlink(target, dir / PayloadDirName)

    var reason = ""
    check not testStore().discardCopy(
      dir / PayloadDirName / "0000-not_ours.txt", dir, reason
    )
    check reason.contains("linked payload")
    check fileExists(target / "0000-not_ours.txt")
    check symlinkExists(dir / PayloadDirName)

    # The session itself still goes, unlinking the link without following it.
    check testStore().discardSession(dir, reason)
    check not dirExists(dir)
    check fileExists(target / "0000-not_ours.txt")

  test "A copy outside the session directory is not removed":
    plantSession("20260918T000000_1")
    let dir = TestRecoveryDir / "20260918T000000_1"
    let sibling = TestRecoveryDir / "20260918T000000_2"
    createDir(sibling)
    writeFile(sibling / "victim.txt", "someone else's bytes")

    var reason = ""
    check not testStore().discardCopy(
      dir / ".." / "20260918T000000_2" / "victim.txt", dir, reason
    )
    check reason.len > 0
    check not testStore().discardCopy(sibling / "victim.txt", dir, reason)
    check reason.len > 0
    check fileExists(sibling / "victim.txt")
    check fileExists(dir / PayloadDirName / "0000-planted.txt")

  test "A session outside the recovery base is not taken away":
    let outside = getTempDir() / "moe_test_not_a_copy_session"
    removeDir(outside)
    createDir(outside)
    writeFile(outside / "precious.txt", "do not delete")
    defer:
      removeDir(outside)

    var reason = ""
    check not testStore().discardCopy(outside / "precious.txt", outside, reason)
    check reason.len > 0
    check fileExists(outside / "precious.txt")
    check dirExists(outside)

  test "A directory outside the recovery base is not removed":
    let outside = getTempDir() / "moe_test_not_a_session"
    removeDir(outside)
    createDir(outside)
    writeFile(outside / "precious.txt", "do not delete")
    defer:
      removeDir(outside)

    var reason = ""
    check not testStore().discardSession(outside, reason)
    check reason.len > 0
    check fileExists(outside / "precious.txt")

suite "emergency - preserved text is private":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "Only the user can enter the session directory":
    when defined(posix):
      let e = createTestEditor()
      let buf = e.activeBuffer()
      markEdited(buf)
      let savedPaths = saveSession(e)
      require savedPaths.len == 1

      check getFilePermissions(savedPaths[0].parentDir) ==
        {fpUserRead, fpUserWrite, fpUserExec}
      check getFilePermissions(savedPaths[0]) == {fpUserRead, fpUserWrite}
      check getFilePermissions(sessionDirOf(savedPaths[0]) / MetadataName) ==
        {fpUserRead, fpUserWrite}

suite "emergency - listing the store":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "The default base is the user's cache, with no test override":
    check getCrashRecoveryBaseDir() == expandBackupDir(DefaultCrashRecoveryDir)

  test "A missing base directory is an empty listing":
    let listing = testStore().listSessions()
    check listing.listed
    check listing.sessions.len == 0

  test "A preserved copy is listed":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    markEdited(buf)

    discard saveSession(e)
    check testStore().sessions().len == 1

  test "An empty session directory is not listed":
    createDir(TestRecoveryDir / "20260918T000000_1")
    check testStore().sessions().len == 0

  test "A session holding only metadata is not listed":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir / PayloadDirName)
    writeFile(dir / MetadataName, "{}")
    check testStore().sessions().len == 0

  test "A preserve that died before the manifest is listed":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir / PayloadDirName)
    writeFile(dir / PayloadDirName / "0000-half.txt", "half written")
    check testStore().sessions().len == 1

  test "A scratch left by a crash is not listed":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir / PayloadDirName)
    writeFile(dir / PayloadDirName / ".0000-half.txt", "half written")
    check testStore().sessions().len == 0

  test "A base directory that cannot be listed is not reported as empty":
    when defined(posix):
      if not permissionsAreEnforced():
        skip()
      else:
        plantSession("20260918T000000_1")
        require testStore().sessions().len == 1

        # Deny everything on the base so the top-level listing fails.
        setFilePermissions(TestRecoveryDir, {})
        defer:
          setFilePermissions(TestRecoveryDir, {fpUserRead, fpUserWrite, fpUserExec})

        check not testStore().listSessions().listed
