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

import std/[unittest]

import ../src/moepkg/[editor, config, editor_window, window_manager]
import ../src/moepkg/types/editor_types
import ../src/moepkg/editor_command_output

proc testEditor(): Editor =
  newEditor(newEditorConfig())

proc outputWindowCount(e: Editor): int =
  for window in e.windowManager.windows:
    if window.buffer.id == e.state.commandOutputBufferId:
      result.inc

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

    e.showCommandOutput(@["second"], keepFocus = true)

    check e.windowManager.windows.len == windowCount
    check e.outputWindowCount == 1
    for window in e.windowManager.windows:
      if window.buffer.id == e.state.commandOutputBufferId:
        check window.buffer.getLine(0) == "second"

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
