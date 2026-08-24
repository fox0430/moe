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

import std/[unittest, os, monotimes, times, strutils]

import pkg/results

import ../src/moepkg/[editor, config, config_loader, editor_reload, editor_file]
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
