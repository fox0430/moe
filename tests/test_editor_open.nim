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

## Tests for editor_open.nim

import std/[unittest, os, options, strutils]

import pkg/results

import
  ../src/moepkg/
    [editor, config, config_loader, types, editor_open, window_manager, editor_window]
import ../src/moepkg/command_handlers/[handler_result, result_processor]
import ../src/moepkg/command_handlers/editor_ops
import ../src/moepkg/editor_window_state

proc createTestEditor(): Editor =
  newEditor(newEditorConfig(), newValidationResult())

proc tempFile(name, content: string): string =
  result = getTempDir() / name
  writeFile(result, content)

proc makeUnreadable(path: string): bool =
  ## Take away read permission; false when the file is still readable (root).
  setFilePermissions(path, {fpUserWrite})
  try:
    discard readFile(path)
    false
  except CatchableError:
    true

func outcome(o: OpenOutcome): Result[OpenOutcome, string] =
  ok(o)

func at(line, column: int, unit: ColumnUnit = cuChar): Option[TargetPosition] =
  some(TargetPosition(line: line, column: column, unit: unit))

suite "editor_open - jumpToFile":
  test "without a position, lands where :e would and records the jump":
    let e = createTestEditor()
    let a = tempFile("moe_test_open_remembered_a.txt", "0\n1\n2\n3\n")
    let b = tempFile("moe_test_open_remembered_b.txt", "b\n")
    defer:
      removeFile(a)
      removeFile(b)
    check e.editFile(a).isOk
    e.cursor = BufferPosition(line: 2, column: 0)
    check e.editFile(b).isOk
    let origin = e.jumpOrigin()

    check e.jumpToFile(a) == outcome(ooOpened)

    check e.activeBuffer().filePath == some(a)
    check e.cursor.line == 2
    check e.state.jumpList.list[^1] == origin

  test "without a position, the file shown already stays as it is":
    let e = createTestEditor()
    let a = tempFile("moe_test_open_stay.txt", "0\n1\n")
    defer:
      removeFile(a)
    check e.editFile(a).isOk
    e.cursor = BufferPosition(line: 1, column: 0)
    let jumps = e.state.jumpList.list.len

    check e.jumpToFile(a) == outcome(ooStayed)

    check e.cursor == BufferPosition(line: 1, column: 0)
    check e.state.jumpList.list.len == jumps

  test "a split of the file shown already records no jump, as Vim's :sb":
    let e = createTestEditor()
    let a = tempFile("moe_test_open_stay_split.txt", "0\n1\n")
    defer:
      removeFile(a)
    check e.editFile(a).isOk
    let original = e.activeWindow
    let windows = e.windowManager.windows.len
    let jumps = e.state.jumpList.list.len

    check e.jumpToFile(a, placement = vpVSplit) == outcome(ooStayed)

    check e.windowManager.windows.len == windows + 1
    check e.activeWindow != original
    check e.activeBuffer() == original.buffer
    check e.state.jumpList.list.len == jumps

  test "a character column is taken as it is, a UTF-16 one is converted":
    let e = createTestEditor()
    # The emoji is one character but two UTF-16 code units.
    let a = tempFile("moe_test_open_columns.txt", "\u{1F600}ab\n")
    defer:
      removeFile(a)
    check e.editFile(a).isOk

    check e.jumpToFile(a, at(0, 2)) == outcome(ooMoved)
    check e.cursor.column == 2
    check e.jumpToFile(a, at(0, 2, cuUtf16)) == outcome(ooMoved)
    check e.cursor.column == 1

  test "a horizontal split opens above the window, on the file":
    let e = createTestEditor()
    let a = tempFile("moe_test_open_hsplit_a.txt", "a\n")
    let b = tempFile("moe_test_open_hsplit_b.txt", "0\n1\n")
    defer:
      removeFile(a)
      removeFile(b)
    check e.editFile(a).isOk
    let original = e.activeWindow
    let windows = e.windowManager.windows.len

    check e.jumpToFile(b, at(1, 0), vpHSplit) == outcome(ooOpened)

    check e.windowManager.windows.len == windows + 1
    check original.buffer.filePath == some(a)
    check e.activeBuffer().filePath == some(b)
    check e.cursor.line == 1
    check e.activeWindow.viewport.y < original.viewport.y

  test "the opened file joins the window's tab list, as with :e":
    let e = createTestEditor()
    let a = tempFile("moe_test_open_tabs_a.txt", "a\n")
    let b = tempFile("moe_test_open_tabs_b.txt", "b\n")
    defer:
      removeFile(a)
      removeFile(b)
    check e.editFile(a).isOk

    check e.jumpToFile(b, at(0, 0)) == outcome(ooOpened)

    check e.activeBuffer().id in e.activeWindow.bufferIds

  test "a file that cannot be read closes the split made for it":
    let e = createTestEditor()
    let a = tempFile("moe_test_open_fail_a.txt", "a\n")
    let bad = tempFile("moe_test_open_fail_bad.txt", "bad\n")
    defer:
      setFilePermissions(bad, {fpUserRead, fpUserWrite})
      removeFile(a)
      removeFile(bad)
    if not makeUnreadable(bad):
      # Running as root: there is no way to fail the load here.
      skip()
    else:
      check e.editFile(a).isOk
      let original = e.activeWindow
      let windows = e.windowManager.windows.len
      let buffers = e.buffers.len
      let jumps = e.state.jumpList.list.len

      let jumped = e.jumpToFile(bad, at(0, 0), vpVSplit)

      check jumped.isErr
      check jumped.error.startsWith("Failed to open file: ")
      check e.windowManager.windows.len == windows
      check e.activeWindow == original
      check e.buffers.len == buffers
      check e.state.jumpList.list.len == jumps

suite "editor_open - the alternate of the window split":
  proc twoFiles(): tuple[e: Editor, a, b: BufferId, other: string] =
    ## `a` shown with no alternate, `b` open as another buffer and a third file.
    let e = createTestEditor()
    let a = e.activeWindow.tabBufferId
    check e.enew().isOk
    let b = e.activeWindow.tabBufferId
    check e.switchToBuffer($a.int)
    e.activeWindow.alternateBufferId = BufferId(0)
    (e, a, b, tempFile("moe_test_open_alternate.txt", "x\n"))

  proc pick(e: Editor, target: PickerTarget, placement: ViewerPlacement) =
    discard e.processResult(
      HandlerResult(
        kind: hrPickerOpen,
        pickerTarget: target,
        pickerPlacement: placement,
        pickerOrigin: e.activeWindow,
      ),
      e.activeBuffer(),
    )

  proc file(path: string): PickerTarget =
    PickerTarget(kind: ptkFile, path: path)

  test "a file picked into a split becomes it":
    for placement in [vpVSplit, vpHSplit]:
      let (e, a, _, other) = twoFiles()
      defer:
        removeFile(other)
      let origin = e.activeWindow
      e.pick(file(other), placement)
      check e.windowManager.windows.len == 2
      check e.activeBuffer().filePath == some(other)
      check origin.alternateBufferId == e.activeWindow.tabBufferId
      check e.activeWindow.alternateBufferId == a

  test "a buffer picked into a split does not":
    let (e, a, b, other) = twoFiles()
    defer:
      removeFile(other)
    let origin = e.activeWindow
    e.pick(PickerTarget(kind: ptkBuffer, buffer: b), vpVSplit)
    check e.windowManager.windows.len == 2
    check e.activeWindow.tabBufferId == b
    check origin.alternateBufferId == BufferId(0)
    check e.activeWindow.alternateBufferId == a

  test "a jump into a split does not":
    let (e, _, _, other) = twoFiles()
    defer:
      removeFile(other)
    let origin = e.activeWindow
    check e.jumpToFile(other, at(0, 0), vpVSplit) == outcome(ooOpened)
    check origin.alternateBufferId == BufferId(0)

  test "a file picked from the sidebar becomes that of the window it serves":
    let (e, _, _, other) = twoFiles()
    defer:
      removeFile(other)
    let served = e.activeWindow
    e.toggleFileTree(none(string), e.activeBuffer())
    e.windowManager.activateWindow(0)
    e.syncActiveWindow()
    let side = e.activeWindow
    check side.isSidebar
    e.pick(file(other), vpVSplit)
    check e.windowManager.windows.len == 3
    check served.alternateBufferId == e.activeWindow.tabBufferId
    check side.alternateBufferId == BufferId(0)

  test "a file picked from a lone sidebar leaves the sidebar none":
    let (e, _, _, other) = twoFiles()
    defer:
      removeFile(other)
    e.toggleFileTree(none(string), e.activeBuffer())
    e.windowManager.activateWindow(1)
    e.syncActiveWindow()
    discard e.closeWindow()
    let side = e.activeWindow
    check side.isSidebar
    check e.windowManager.windows.len == 1
    e.pick(file(other), vpVSplit)
    check e.windowManager.windows.len == 2
    check e.activeBuffer().filePath == some(other)
    check side.alternateBufferId == BufferId(0)

suite "editor_open - opening the path under the cursor":
  test "opens a file URI where :e would":
    let e = createTestEditor()
    let a = tempFile("moe_test_open_uri_a.txt", "0\n1\n2\n")
    let b = tempFile("moe_test_open_uri_b.txt", "b\n")
    defer:
      removeFile(a)
      removeFile(b)
    check e.editFile(a).isOk
    e.cursor = BufferPosition(line: 2, column: 0)
    check e.editFile(b).isOk

    discard e.processResult(
      HandlerResult(kind: hrOpenUri, openUri: "file://" & a), e.activeBuffer()
    )

    check e.activeBuffer().filePath == some(a)
    check e.cursor.line == 2
    check e.state.statusMessage == "Opened: " & a.extractFilename

  test "on the file shown already, says so and moves nothing":
    let e = createTestEditor()
    let a = tempFile("moe_test_open_uri_stay.txt", "0\n1\n")
    defer:
      removeFile(a)
    check e.editFile(a).isOk
    e.cursor = BufferPosition(line: 1, column: 0)
    let jumps = e.state.jumpList.list.len

    discard e.processResult(
      HandlerResult(kind: hrOpenUri, openUri: "file://" & a), e.activeBuffer()
    )

    check e.cursor == BufferPosition(line: 1, column: 0)
    check e.state.jumpList.list.len == jumps
    check e.state.statusMessage == "Already in this file"

  test "a file that cannot be read says why":
    let e = createTestEditor()
    let a = tempFile("moe_test_open_uri_fail_a.txt", "a\n")
    let bad = tempFile("moe_test_open_uri_fail_bad.txt", "bad\n")
    defer:
      setFilePermissions(bad, {fpUserRead, fpUserWrite})
      removeFile(a)
      removeFile(bad)
    if not makeUnreadable(bad):
      # Running as root: there is no way to fail the load here.
      skip()
    else:
      check e.editFile(a).isOk

      discard e.processResult(
        HandlerResult(kind: hrOpenUri, openUri: "file://" & bad), e.activeBuffer()
      )

      check e.activeBuffer().filePath == some(a)
      check e.state.statusMessage.startsWith("Failed to open file: ")
