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

## Tests for the window a background command writes its output into, shared by
## builds, QuickRun and `showOutput` hooks.

import std/[unittest, options]

import ../src/moepkg/[editor, config, editor_window, window_manager, types]
import ../src/moepkg/types/editor_types
import ../src/moepkg/editor_command_output
import ../src/moepkg/command_handlers/[handler_result, result_processor]

proc testEditor(): Editor =
  newEditor(newEditorConfig())

proc outputWindowCount(e: Editor): int =
  for window in e.windowManager.windows:
    if window.buffer.id == e.state.commandOutputBufferId:
      result.inc

proc run(e: Editor, r: HandlerResult) =
  discard e.processResult(r, e.activeBuffer())

proc replaceOutput(e: Editor, output: seq[string], keepFocus: bool) =
  ## Run a command that replaces the current output and check the previous
  ## buffer left the registry: `outputWindowCount` counts views, not buffers.
  let previous = e.state.commandOutputBufferId
  let count = e.buffers.len
  e.showCommandOutput(output, keepFocus)
  if previous != BufferId(0):
    check e.bufferById(previous).isNone
    check e.buffers.len == count

proc focus(e: Editor, win: EditorWindow) =
  for i, w in e.windowManager.windows:
    if w == win:
      e.windowManager.activateWindow(i)
  e.syncActiveWindow()

proc coverOutputWithBufferManager(
    e: Editor
): tuple[user, output: EditorWindow, listing: TextBuffer] =
  ## Show an output, cover its window with `:ls`, and go back to the user's
  ## window.
  let user = e.activeWindow
  e.showCommandOutput(@["first"], keepFocus = false)
  let output = e.activeWindow
  e.run(HandlerResult(kind: hrEnterBufferManager))
  require output.viewerEntry.isSome
  let listing = output.buffer
  e.focus(user)
  (user, output, listing)

suite "Background command output":
  test "A command the user did not start keeps the focus and the mode":
    let e = testEditor()
    let userWindow = e.activeWindow
    e.setMode(EditorMode.Insert)

    e.showCommandOutput(@["built"], keepFocus = true)

    check e.windowManager.windows.len == 2
    check e.activeWindow == userWindow
    check e.state.mode == EditorMode.Insert

  test "A command the user asked for moves the focus to its output":
    let e = testEditor()
    let userWindow = e.activeWindow

    e.showCommandOutput(@["ran"], keepFocus = false)

    check e.windowManager.windows.len == 2
    check e.activeWindow != userWindow
    check e.activeWindow.buffer.id == e.state.commandOutputBufferId
    check e.activeWindow.buffer.getLine(0) == "ran"

  test "A later command replaces the output instead of splitting again":
    let e = testEditor()
    e.showCommandOutput(@["first"], keepFocus = true)
    let windowCount = e.windowManager.windows.len

    e.replaceOutput(@["second"], keepFocus = true)

    check e.windowManager.windows.len == windowCount
    check e.outputWindowCount == 1
    for window in e.windowManager.windows:
      if window.buffer.id == e.state.commandOutputBufferId:
        check window.buffer.getLine(0) == "second"

  test "A later command reopens the output window after it was closed":
    let e = testEditor()
    e.showCommandOutput(@["first"], keepFocus = false)
    let stale = e.state.commandOutputBufferId
    discard e.closeWindow()
    require e.windowManager.windows.len == 1
    # The buffer outlives the window; the next command must still replace it.
    require e.bufferById(stale).isSome

    e.replaceOutput(@["second"], keepFocus = false)

    check e.windowManager.windows.len == 2
    check e.outputWindowCount == 1
    check e.activeWindow.buffer.id == e.state.commandOutputBufferId
    check e.activeWindow.buffer.getLine(0) == "second"

  test "A build and a QuickRun share the one output window":
    let e = testEditor()
    e.showCommandOutput(@["build output"], keepFocus = true)
    let afterBuild = e.windowManager.windows.len

    e.showCommandOutput(@["quickrun output"], keepFocus = false)

    check e.windowManager.windows.len == afterBuild
    check e.outputWindowCount == 1

  test "Reusing the window still moves the focus for a command the user asked for":
    let e = testEditor()
    # The first run leaves the window open with the focus elsewhere, so the
    # second reuses it.
    e.showCommandOutput(@["first"], keepFocus = true)
    let userWindow = e.activeWindow

    e.showCommandOutput(@["second"], keepFocus = false)

    check e.activeWindow != userWindow
    check e.activeWindow.buffer.id == e.state.commandOutputBufferId
    check e.activeWindow.buffer.getLine(0) == "second"

  test "Reusing the window still keeps the focus for one the user did not":
    let e = testEditor()
    e.showCommandOutput(@["first"], keepFocus = false)
    let outputWindow = e.activeWindow

    e.showCommandOutput(@["second"], keepFocus = true)

    check e.activeWindow == outputWindow

  test "Putting the output on screen is reported":
    let e = testEditor()
    check e.showCommandOutput(@["output"], keepFocus = false)

  test "The output buffer is read only":
    let e = testEditor()
    e.showCommandOutput(@["output"], keepFocus = false)
    check e.activeWindow.buffer.readOnly

  test "Several lines are shown as several lines":
    let e = testEditor()
    e.showCommandOutput(@["one", "two"], keepFocus = false)
    check e.activeWindow.buffer.getLine(1) == "two"

suite "Background command output - window covered by a viewer":
  test "The covered window moves its tab to the new output":
    let e = testEditor()
    let (_, output, _) = e.coverOutputWithBufferManager()

    e.replaceOutput(@["second"], keepFocus = true)

    check output.viewerEntry.isSome
    check output.tabBufferId == e.state.commandOutputBufferId
    check e.bufferById(output.tabBufferId).isSome

  test "Leaving the viewer shows the new output":
    let e = testEditor()
    let (_, output, _) = e.coverOutputWithBufferManager()
    e.showCommandOutput(@["second"], keepFocus = true)

    e.focus(output)
    e.run(HandlerResult(kind: hrBufferManagerQuit))

    check output.viewerEntry.isNone
    check output.buffer.id == e.state.commandOutputBufferId
    check output.buffer.getLine(0) == "second"

  test "Splitting the covered window registers no listing":
    let e = testEditor()
    let (_, output, listing) = e.coverOutputWithBufferManager()
    e.showCommandOutput(@["second"], keepFocus = true)

    e.focus(output)
    e.run(HandlerResult(kind: hrVSplit))

    check e.bufferById(listing.id).isNone
    check e.activeWindow.tabBufferId == e.state.commandOutputBufferId

  test "The viewer is left alone and the output opens in a window of its own":
    let e = testEditor()
    let (user, output, listing) = e.coverOutputWithBufferManager()
    let windowCount = e.windowManager.windows.len

    e.showCommandOutput(@["second"], keepFocus = true)

    check e.windowManager.windows.len == windowCount + 1
    check e.activeWindow == user
    check output.buffer == listing
    check e.outputWindowCount == 1

  test "A command the user asked for moves the focus to the new window":
    let e = testEditor()
    let (_, output, _) = e.coverOutputWithBufferManager()

    e.showCommandOutput(@["second"], keepFocus = false)

    check e.activeWindow != output
    check e.activeWindow.buffer.id == e.state.commandOutputBufferId
    check e.activeWindow.buffer.getLine(0) == "second"
    check e.state.mode == EditorMode.Normal

  test "A viewer that opens in a split leaves the output window to be reused":
    let e = testEditor()
    e.showCommandOutput(@["first"], keepFocus = false)
    let output = e.activeWindow
    e.run(HandlerResult(kind: hrEnterHelpViewer))
    let viewer = e.activeWindow
    require viewer != output
    require viewer.tabBufferId == output.tabBufferId
    let windowCount = e.windowManager.windows.len

    e.showCommandOutput(@["second"], keepFocus = false)

    check e.windowManager.windows.len == windowCount
    check e.activeWindow == output
    check output.buffer.getLine(0) == "second"
    check viewer.viewerEntry.isSome
    check viewer.tabBufferId == e.state.commandOutputBufferId
    check e.outputWindowCount == 1

  test "A later command reuses the window the earlier one opened under a viewer":
    let e = testEditor()
    let (user, output, _) = e.coverOutputWithBufferManager()
    e.showCommandOutput(@["second"], keepFocus = true)
    let windowCount = e.windowManager.windows.len

    e.replaceOutput(@["third"], keepFocus = true)

    check e.windowManager.windows.len == windowCount
    check output.viewerEntry.isSome
    check output.tabBufferId == e.state.commandOutputBufferId
    check e.outputWindowCount == 1
    check e.activeWindow == user
