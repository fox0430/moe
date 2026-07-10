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

import std/[unittest, os, options, json, strutils, sequtils]

import
  ../src/moepkg/
    [editor, editor_buffers, editor_window, buffer, config, config_loader, emergency]
import ../src/moepkg/types/editor_types

let TestRecoveryDir = getTempDir() / "moe_test_crash_recovery"

proc cleanupTestDir() =
  if dirExists(TestRecoveryDir):
    removeDir(TestRecoveryDir)

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  newEditor(config, vr)

suite "emergency - emergencySaveBuffers":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "Save modified buffer":
    let e = createTestEditor()

    # Load a file and modify its buffer
    let testFile = getTempDir() / "moe_test_emergency.txt"
    writeFile(testFile, "original content")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)
    let buf = e.activeBuffer()
    buf.changeSeq = buf.savedSeq + 1 # Mark as modified

    let savedPaths = e.emergencySaveBuffers(TestRecoveryDir)
    check savedPaths.len == 1

    let savedContent = readFile(savedPaths[0])
    check savedContent.contains("original content")

    # Check recovery.json exists
    let recoveryDir = savedPaths[0].parentDir
    let metadataPath = recoveryDir / "recovery.json"
    check fileExists(metadataPath)

    let metadata = parseJson(readFile(metadataPath))
    let filename = extractFilename(savedPaths[0])
    check metadata.hasKey(filename)
    check metadata[filename]["originalPath"].getStr == testFile

  test "Skip unmodified buffer":
    let e = createTestEditor()

    let testFile = getTempDir() / "moe_test_emergency_unmod.txt"
    writeFile(testFile, "unmodified content")
    defer:
      removeFile(testFile)

    discard e.loadFile(testFile)
    # Buffer is not modified (changeSeq == savedSeq)

    let savedPaths = e.emergencySaveBuffers(TestRecoveryDir)
    check savedPaths.len == 0

  test "Save buffer without file path":
    let e = createTestEditor()

    # The default buffer has no file path and is not modified
    let buf = e.activeBuffer()
    buf.changeSeq = buf.savedSeq + 1 # Mark as modified

    let savedPaths = e.emergencySaveBuffers(TestRecoveryDir)
    check savedPaths.len == 1

    let filename = extractFilename(savedPaths[0])
    check filename.startsWith("untitled_")

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

    let savedPaths = e.emergencySaveBuffers(TestRecoveryDir)
    check savedPaths.len == 2

    let metadata = parseJson(readFile(savedPaths[0].parentDir / "recovery.json"))
    check metadata.len == 2

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

    let savedPaths = e.emergencySaveBuffers(TestRecoveryDir)
    check savedPaths.len == 1

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

    let savedPaths = e.emergencySaveBuffers(TestRecoveryDir)
    check savedPaths.len == 2

    # One should have the buffer id prefix
    let filenames = savedPaths.mapIt(extractFilename(it))
    check filenames.anyIt(it == "same.txt")
    check filenames.anyIt(it.endsWith("_same.txt"))

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

    let savedPaths = e.emergencySaveBuffers(TestRecoveryDir)
    check savedPaths.len == 1

    let filename = extractFilename(savedPaths[0])
    check filename == extractFilename(testFile1)

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

    let savedPaths = e.emergencySaveBuffers(TestRecoveryDir)
    check savedPaths.len == 2

    let filenames = savedPaths.mapIt(extractFilename(it))
    check filenames.anyIt(it == extractFilename(testFileFg))
    check filenames.anyIt(it == extractFilename(testFileBg))

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

    let savedPaths = e.emergencySaveBuffers(TestRecoveryDir)
    check savedPaths.anyIt(extractFilename(it) == extractFilename(testFile))

  test "No modified buffers removes empty directory":
    let e = createTestEditor()
    # Default buffer is not modified

    let savedPaths = e.emergencySaveBuffers(TestRecoveryDir)
    check savedPaths.len == 0

    # The timestamped subdirectory should have been cleaned up
    if dirExists(TestRecoveryDir):
      var subdirCount = 0
      for _ in walkDirs(TestRecoveryDir / "*"):
        inc subdirCount
      check subdirCount == 0

suite "emergency - hasCrashRecoveryFiles":
  setup:
    cleanupTestDir()

  teardown:
    cleanupTestDir()

  test "Returns false when no recovery directory exists":
    check not hasCrashRecoveryFiles(TestRecoveryDir)

  test "Returns false when base directory is empty":
    createDir(TestRecoveryDir)
    check not hasCrashRecoveryFiles(TestRecoveryDir)

  test "Returns true when recovery files exist":
    let e = createTestEditor()
    let buf = e.activeBuffer()
    buf.changeSeq = buf.savedSeq + 1

    discard e.emergencySaveBuffers(TestRecoveryDir)
    check hasCrashRecoveryFiles(TestRecoveryDir)
