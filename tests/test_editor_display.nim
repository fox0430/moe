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

## Tests for editor_display.nim

import std/[options, tables, unittest]

import ../src/moepkg/[buffer, config, editor, git_cache]

proc createTestEditor(): Editor =
  newEditor(newEditorConfig())

suite "Editor display status queries":
  test "statusModeLabel returns the active editor mode":
    let e = createTestEditor()

    check e.statusModeLabel == "NORMAL"

    e.setMode(EditorMode.Insert)
    check e.statusModeLabel == "INSERT"

  test "statusModeLabel preserves the insert-normal label":
    let e = createTestEditor()
    e.setMode(EditorMode.Normal)
    e.state.insertNormalMode = true

    check e.statusModeLabel == "(insert) NORMAL"

  test "statusModeLabel gives an overlay precedence over the editor mode":
    let e = createTestEditor()
    e.setMode(EditorMode.Insert)
    e.state.overlay = some(OverlayKind.okSearch)

    check e.statusModeLabel == "SEARCH"

  test "currentStatusMessage returns the editor status message":
    let e = createTestEditor()
    e.state.statusMessage = "Saved"

    check e.currentStatusMessage == "Saved"

  test "activeGitStatus returns empty values without cached Git information":
    let e = createTestEditor()

    check e.activeGitStatus == ActiveGitStatus()
    check e.state.git.diffEntries.len == 0
    check e.state.git.branchEntries.len == 0

  test "activeGitStatus returns cached information for the active buffer":
    let
      e = createTestEditor()
      activeBuffer = e.activeBuffer
      key = cast[pointer](activeBuffer)
    e.state.git.diffEntries[key] =
      GitDiffCacheEntry(counts: (added: 3, modified: 2, deleted: 1), populated: true)
    e.state.git.branchEntries[key] =
      GitBranchCacheEntry(name: "feature/native-status", populated: true)

    check e.activeGitStatus ==
      ActiveGitStatus(
        branch: "feature/native-status", added: 3, modified: 2, deleted: 1
      )

  test "activeGitStatus follows the active buffer":
    let
      e = createTestEditor()
      inactiveBuffer = e.activeBuffer
      activeBuffer = newTextBuffer()
    e.state.git.branchEntries[cast[pointer](inactiveBuffer)] =
      GitBranchCacheEntry(name: "inactive", populated: true)
    e.state.git.branchEntries[cast[pointer](activeBuffer)] =
      GitBranchCacheEntry(name: "active", populated: true)
    e.activeWindow.buffer = activeBuffer

    check e.activeGitStatus.branch == "active"
