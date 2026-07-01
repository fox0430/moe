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

## Tests for log_viewer.nim
## This module tests the Log Viewer state management functionality.

import std/[os, times, unittest]

import pkg/results

import ../src/moepkg/log_viewer

suite "log_viewer: LogContentKind":
  test "lckEditor enum value":
    check lckEditor == LogContentKind.lckEditor

  test "lckLsp enum value":
    check lckLsp == LogContentKind.lckLsp

  test "Enum values are distinct":
    check lckEditor != lckLsp

suite "log_viewer: newLogViewerState":
  test "Create with default kind (lckEditor)":
    let state = newLogViewerState()

    check state != nil
    check state.contentKind == lckEditor

  test "Create with lckEditor kind":
    let state = newLogViewerState(lckEditor)

    check state != nil
    check state.contentKind == lckEditor

  test "Create with lckLsp kind":
    let state = newLogViewerState(lckLsp)

    check state != nil
    check state.contentKind == lckLsp

suite "log_viewer: LogViewerState fields":
  test "contentKind is readable":
    let state = newLogViewerState(lckLsp)

    check state.contentKind == lckLsp

  test "contentKind is writable":
    let state = newLogViewerState(lckEditor)

    state.contentKind = lckLsp

    check state.contentKind == lckLsp

  test "Multiple states are independent":
    let
      state1 = newLogViewerState(lckEditor)
      state2 = newLogViewerState(lckLsp)

    check state1.contentKind == lckEditor
    check state2.contentKind == lckLsp

    state1.contentKind = lckLsp

    check state1.contentKind == lckLsp
    check state2.contentKind == lckLsp

suite "log_viewer: logViewerSaveFileName":
  let sampleAt = dateTime(2026, mJan, 1, 15, 30, 45, 0, utc())

  test "editor kind uses `editor` prefix and timestamp":
    check logViewerSaveFileName(lckEditor, sampleAt) == "moe-editor-20260101-153045.log"

  test "lsp kind uses `lsp` prefix":
    check logViewerSaveFileName(lckLsp, sampleAt) == "moe-lsp-20260101-153045.log"

  test "zero-pads month/day/time":
    let padded = dateTime(2026, mMar, 9, 4, 5, 6, 0, utc())
    check logViewerSaveFileName(lckEditor, padded) == "moe-editor-20260309-040506.log"

suite "log_viewer: saveLogViewerContentToFile":
  test "writes content to the given path and returns Ok":
    let path = getTempDir() / "moe_test_log_save_ok.log"
    removeFile(path)
    defer:
      removeFile(path)

    let r = saveLogViewerContentToFile("hello\nworld\n", path)

    check r.isOk
    check fileExists(path)
    check readFile(path) == "hello\nworld\n"

  test "overwrites an existing file":
    let path = getTempDir() / "moe_test_log_save_overwrite.log"
    writeFile(path, "stale")
    defer:
      removeFile(path)

    let r = saveLogViewerContentToFile("fresh", path)

    check r.isOk
    check readFile(path) == "fresh"

  test "returns Err when the target directory does not exist":
    let path = getTempDir() / "moe_test_missing_dir_xyz_123" / "moe_test_log.log"

    let r = saveLogViewerContentToFile("data", path)

    check r.isErr
    check not fileExists(path)
