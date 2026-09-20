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

import
  ../src/moepkg/[
    editor, editor_buffers, editor_window, buffer, backup, config, config_loader,
    emergency, message_log, recovery_format, recovery_store,
  ]
import ../src/moepkg/types/editor_types

when defined(posix):
  from std/posix import getuid

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
    buf.changeSeq = buf.savedSeq + 1 # Mark as modified

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
    buf.changeSeq = buf.savedSeq + 1 # Mark as modified

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
    buf.changeSeq = buf.savedSeq + 1 # Mark as modified

    let savedPaths = e.emergencySaveBuffers(ckCrash, "", TestRecoveryDir, rejectCommit)
    check savedPaths.len == 0
    # The failed copy is not offered, and the empty session goes away with the
    # scratch instead of lingering.
    check not testStore().hasPreservedCopies()
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

  test "Save buffer without file path":
    let e = createTestEditor()

    let buf = e.activeBuffer()
    buf.changeSeq = buf.savedSeq + 1 # Mark as modified

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
    e.activeBuffer().changeSeq = e.activeBuffer().savedSeq + 1

    let buf2 = newTextBuffer("content 2", some(testFile2))
    discard e.vsplitWithBuffer(buf2)
    buf2.changeSeq = buf2.savedSeq + 1

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
    sharedBuf.changeSeq = sharedBuf.savedSeq + 1

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
    e.activeBuffer().changeSeq = e.activeBuffer().savedSeq + 1

    let buf2 = newTextBuffer("from dir2", some(file2))
    discard e.vsplitWithBuffer(buf2)
    buf2.changeSeq = buf2.savedSeq + 1

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
    e.activeBuffer().changeSeq = e.activeBuffer().savedSeq + 1

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
    fgBuf.changeSeq = fgBuf.savedSeq + 1

    # Register a second buffer in e.buffers and the same window's tab list
    # WITHOUT activating it, so it stays a background tab (not window.buffer).
    let bgBuf = newTextBuffer("background content", some(testFileBg))
    e.addBuffer(bgBuf)
    e.addBufferToWindowList(bgBuf)
    bgBuf.changeSeq = bgBuf.savedSeq + 1

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
    orphan.changeSeq = orphan.savedSeq + 1

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
    buf.changeSeq = buf.savedSeq + 1

    let saved = e.emergencySaveBuffers(ckSignal, "SIGTERM", TestRecoveryDir)
    require saved.len == 1

    let metadata = parseJson(readFile(sessionDirOf(saved[0]) / MetadataName))
    check metadata["continuity"].getStr == "signal"
    check metadata["detail"].getStr == "SIGTERM"

  test "A caller that cannot say what happened records unknown":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    buf.changeSeq = buf.savedSeq + 1

    let saved = e.emergencySaveBuffers(ckUnknown, "", TestRecoveryDir)
    require saved.len == 1

    check parseJson(readFile(sessionDirOf(saved[0]) / MetadataName))["continuity"].getStr ==
      "unknown"

  test "A long exception message is kept bounded":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    buf.changeSeq = buf.savedSeq + 1

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
    buf.changeSeq = buf.savedSeq + 1

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
      buf.changeSeq = buf.savedSeq + 1

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
    buf.changeSeq = buf.savedSeq + 1

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
    buf.changeSeq = buf.savedSeq + 1

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
    buf.changeSeq = buf.savedSeq + 1
    let saved = saveSession(e)
    require saved.len == 1

    check sessionDirOf(saved[0]).lastPathPart.endsWith("_" & $getCurrentProcessId())

  test "A session that saved nothing leaves a filled directory alone":
    # Regression: an empty preserve used to remove another session's directory.
    let first = createTestEditor()
    let firstBuf = first.activeBuffer()
    firstBuf.changeSeq = firstBuf.savedSeq + 1
    let saved = saveSession(first)
    require saved.len == 1

    let second = createTestEditor()
    discard saveSession(second)

    check fileExists(saved[0])
    check testStore().sessions().len == 1

  test "A second preserve from the same process still preserves":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    buf.changeSeq = buf.savedSeq + 1

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
    buf.changeSeq = buf.savedSeq + 1

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
    check sessions[0].complete
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
    check not sessions[0].complete
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
    check not testStore().hasPreservedCopies()

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
    check not testStore().hasPreservedCopies()

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
    check sessions[0].complete
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
        check testStore().hasPreservedCopies()

  test "A session holding only metadata is not offered":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir / PayloadDirName)
    writeFile(dir / MetadataName, "{}")
    check testStore().sessions().len == 0
    check not testStore().hasPreservedCopies()

  test "Files survive metadata that cannot be read":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir / PayloadDirName)
    writeFile(dir / PayloadDirName / "0000-planted.txt", "preserved")
    writeFile(dir / MetadataName, "{ this is not json")

    let sessions = testStore().sessions()
    require sessions.len == 1
    check sessions[0].complete
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
    check not sessions[0].complete
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
    check sessions[0].complete
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

    let copies = testStore().copiesOf("/tmp/wanted.txt")
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

    check testStore().copiesOf("wanted.txt").len == 1
    check testStore().copiesOf("./wanted.txt").len == 1

  test "An unnamed buffer answers for no file":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    buf.changeSeq = buf.savedSeq + 1
    require saveSession(e).len == 1

    check testStore().copiesOf("").len == 0
    check testStore().copiesOf("/tmp/anything.txt").len == 0

suite "emergency - whether a copy is worth offering":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  proc preserveModified(path, content: string): PreservedCopy =
    let e = createTestEditor()
    discard e.loadFile(path)
    let buf = e.activeBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), content)
    require saveSession(e).len == 1
    let copies = testStore().copiesOf(path)
    require copies.len == 1
    return copies[0]

  test "A copy the disk already holds is not worth a prompt":
    let dir = getTempDir() / "moe_test_emergency_same"
    createDir(dir)
    defer:
      removeDir(dir)
    let testFile = dir / "f.txt"
    writeFile(testFile, "original\n")

    let copy = preserveModified(testFile, "edited ")
    check copy.verdict == cvDiffers

    writeFile(testFile, readFile(copy.file.path))
    check copy.verdict == cvSame

  test "A file the crash left alone is reported as changed":
    let dir = getTempDir() / "moe_test_emergency_untouched"
    createDir(dir)
    defer:
      removeDir(dir)
    let testFile = dir / "f.txt"
    writeFile(testFile, "original\n")

    let copy = preserveModified(testFile, "edited ")
    check copy.verdict == cvDiffers

  test "A file written after the crash is decided by its content":
    let dir = getTempDir() / "moe_test_emergency_moved"
    createDir(dir)
    defer:
      removeDir(dir)
    let testFile = dir / "f.txt"
    writeFile(testFile, "original\n")

    let copy = preserveModified(testFile, "edited ")

    writeFile(testFile, "someone else wrote this\n")
    check copy.verdict == cvDiffers

    writeFile(testFile, readFile(copy.file.path))
    check copy.verdict == cvSame

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

    let copies = testStore().copiesOf(testFile)
    require copies.len == 1
    check copies[0].file.originStamp.mtime.isNone
    check copies[0].verdict == cvSame

    writeFile(testFile, "something else entirely")
    check copies[0].verdict == cvDiffers

  test "The answer says when there is only one file to compare with":
    plantSession("20260918T000000_1", files = @[("0000-untitled", "", "preserved")])
    let copies = testStore().copiesOf("/tmp/anything.txt")
    check copies.len == 0

    let sessions = testStore().sessions()
    require sessions.len == 1
    let unnamed = PreservedCopy(file: sessions[0].files[0], session: sessions[0])
    check unnamed.verdict == cvNoOrigin

  test "A file the crash was the end of is its own answer":
    let dir = getTempDir() / "moe_test_emergency_gone"
    createDir(dir)
    defer:
      removeDir(dir)
    let testFile = dir / "f.txt"
    writeFile(testFile, "original\n")

    let copy = preserveModified(testFile, "edited ")
    removeFile(testFile)
    check copy.verdict == cvOriginalGone

  test "A copy that is gone cannot be compared":
    let dir = getTempDir() / "moe_test_emergency_nocopy"
    createDir(dir)
    defer:
      removeDir(dir)
    let testFile = dir / "f.txt"
    writeFile(testFile, "original\n")

    let copy = preserveModified(testFile, "edited ")
    removeFile(copy.file.path)
    check copy.verdict == cvUnknown

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
    check not testStore().hasPreservedCopies()

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
        check not testStore().hasPreservedCopies()

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
      buf.changeSeq = buf.savedSeq + 1
      let savedPaths = saveSession(e)
      require savedPaths.len == 1

      check getFilePermissions(savedPaths[0].parentDir) ==
        {fpUserRead, fpUserWrite, fpUserExec}
      check getFilePermissions(savedPaths[0]) == {fpUserRead, fpUserWrite}
      check getFilePermissions(sessionDirOf(savedPaths[0]) / MetadataName) ==
        {fpUserRead, fpUserWrite}

suite "emergency - hasPreservedCopies":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "The default base is the user's cache, with no test override":
    check getCrashRecoveryBaseDir() == expandBackupDir(DefaultCrashRecoveryDir)

  test "Returns false when no recovery directory exists":
    check not testStore().hasPreservedCopies()

  test "Returns true when a recovery file exists":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    buf.changeSeq = buf.savedSeq + 1

    discard saveSession(e)
    check testStore().hasPreservedCopies()

  test "An empty session directory is not recovery files":
    createDir(TestRecoveryDir / "20260918T000000_1")
    check not testStore().hasPreservedCopies()
    check testStore().sessions().len == 0

  test "A session holding only metadata is not recovery files":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir / PayloadDirName)
    writeFile(dir / MetadataName, "{}")
    check not testStore().hasPreservedCopies()
    check testStore().sessions().len == 0

  test "A preserve that died before the manifest is recovery files":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir / PayloadDirName)
    writeFile(dir / PayloadDirName / "0000-half.txt", "half written")
    check testStore().hasPreservedCopies()

  test "A scratch left by a crash is not recovery files":
    let dir = TestRecoveryDir / "20260918T000000_1"
    createDir(dir / PayloadDirName)
    writeFile(dir / PayloadDirName / ".0000-half.txt", "half written")
    check not testStore().hasPreservedCopies()
    check testStore().sessions().len == 0

  test "A base directory that cannot be listed is not reported as empty":
    when defined(posix):
      if not permissionsAreEnforced():
        skip()
      else:
        plantSession("20260918T000000_1")
        require testStore().hasPreservedCopies()

        # Deny everything on the base so the top-level listing fails.
        setFilePermissions(TestRecoveryDir, {})
        defer:
          setFilePermissions(TestRecoveryDir, {fpUserRead, fpUserWrite, fpUserExec})

        check testStore().hasPreservedCopies()

suite "emergency - noteCrashRecovery":
  setup:
    cleanupTestDir()
    clearMessageLog()

  teardown:
    cleanupTestDir()
    clearMessageLog()

  test "Stays quiet when nothing was preserved":
    let e = createTestEditor()
    e.state.setStatusQuiet("")

    e.noteCrashRecovery(TestRecoveryDir)

    check e.state.statusMessage.len == 0
    check getMessageLog().len == 0

  test "Offers preserved copies in the status line and the message log":
    let saver = createTestEditor()
    let buf = saver.activeBuffer()
    buf.changeSeq = buf.savedSeq + 1
    require saveSession(saver).len == 1

    let e = createTestEditor()
    e.state.setStatusQuiet("")
    clearMessageLog()

    e.noteCrashRecovery(TestRecoveryDir)

    let msg = "Crash recovery files found. See " & TestRecoveryDir
    check e.state.statusMessage == msg
    # The `statusMessage=` setter logs; the notice must not log twice.
    check getMessageLog() == @[msg]

  test "Keeps an existing status message but still logs":
    plantSession("20260918T000000_1")

    let e = createTestEditor()
    e.state.setStatusQuiet("standing message")

    e.noteCrashRecovery(TestRecoveryDir)

    let msg = "Crash recovery files found. See " & TestRecoveryDir
    check e.state.statusMessage == "standing message"
    check msg in getMessageLog()

  test "An unlistable base directory is still offered":
    when defined(posix):
      if not permissionsAreEnforced():
        skip()
      else:
        plantSession("20260918T000000_1")
        require testStore().hasPreservedCopies()

        setFilePermissions(TestRecoveryDir, {})
        defer:
          setFilePermissions(TestRecoveryDir, {fpUserRead, fpUserWrite, fpUserExec})

        let e = createTestEditor()
        e.state.setStatusQuiet("")
        clearMessageLog()

        e.noteCrashRecovery(TestRecoveryDir)

        check e.state.statusMessage ==
          "Crash recovery files found. See " & TestRecoveryDir
