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
      key = activeBuffer.id
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
    e.state.git.branchEntries[inactiveBuffer.id] =
      GitBranchCacheEntry(name: "inactive", populated: true)
    e.state.git.branchEntries[activeBuffer.id] =
      GitBranchCacheEntry(name: "active", populated: true)
    e.activeWindow.buffer = activeBuffer

    check e.activeGitStatus.branch == "active"

suite "editor_display - status line":
  test "toggleStatusLine flips the config flag":
    let e = createTestEditor()
    let before = e.showStatusLine
    e.toggleStatusLine()
    check e.showStatusLine == not before

  test "setStatusLineVisible sets the flag":
    let e = createTestEditor()
    e.setStatusLineVisible(false)
    check e.showStatusLine == false
    e.setStatusLineVisible(true)
    check e.showStatusLine == true

suite "editor_display - line count":
  test "toggleLineCount flips the display flag":
    let e = createTestEditor()
    let before = e.state.display.showLineCount
    e.toggleLineCount()
    check e.state.display.showLineCount == not before

  test "setLineCountVisible sets the display flag":
    let e = createTestEditor()
    e.setLineCountVisible(false)
    check e.state.display.showLineCount == false
    e.setLineCountVisible(true)
    check e.state.display.showLineCount == true

suite "editor_display - line percentage":
  test "toggleLinePercentage flips the display flag":
    let e = createTestEditor()
    let before = e.state.display.showLinePercentage
    e.toggleLinePercentage()
    check e.state.display.showLinePercentage == not before

  test "setLinePercentageVisible sets the display flag":
    let e = createTestEditor()
    e.setLinePercentageVisible(false)
    check e.state.display.showLinePercentage == false
    e.setLinePercentageVisible(true)
    check e.state.display.showLinePercentage == true

suite "editor_display - encoding":
  test "toggleEncoding flips the display flag":
    let e = createTestEditor()
    let before = e.state.display.showEncoding
    e.toggleEncoding()
    check e.state.display.showEncoding == not before

  test "setEncodingVisible sets the display flag":
    let e = createTestEditor()
    e.setEncodingVisible(false)
    check e.state.display.showEncoding == false
    e.setEncodingVisible(true)
    check e.state.display.showEncoding == true

suite "editor_display - line wrap":
  test "toggleLineWrap flips the config flag":
    let e = createTestEditor()
    let before = e.lineWrap
    e.toggleLineWrap()
    check e.lineWrap == not before

  test "setLineWrap sets the config flag":
    let e = createTestEditor()
    e.setLineWrap(false)
    check e.lineWrap == false
    e.setLineWrap(true)
    check e.lineWrap == true

suite "editor_display - multi status line":
  test "toggleMultiStatusLine flips the config flag":
    let e = createTestEditor()
    let before = e.multiStatusLine
    e.toggleMultiStatusLine()
    check e.multiStatusLine == not before

  test "setMultiStatusLine sets the config flag":
    let e = createTestEditor()
    e.setMultiStatusLine(false)
    check e.multiStatusLine == false
    e.setMultiStatusLine(true)
    check e.multiStatusLine == true

suite "editor_display - sidebar":
  test "toggleSidebar flips the config flag":
    let e = createTestEditor()
    let before = e.showSidebar
    e.toggleSidebar()
    check e.showSidebar == not before

  test "setSidebarVisible sets the config flag":
    let e = createTestEditor()
    e.setSidebarVisible(false)
    check e.showSidebar == false
    e.setSidebarVisible(true)
    check e.showSidebar == true

suite "editor_display - git diff":
  test "toggleGitDiff flips the config flag":
    let e = createTestEditor()
    let before = e.showGitDiff
    e.toggleGitDiff()
    check e.showGitDiff == not before

  test "setGitDiffVisible sets the config flag":
    let e = createTestEditor()
    e.setGitDiffVisible(false)
    check e.showGitDiff == false
    e.setGitDiffVisible(true)
    check e.showGitDiff == true

suite "editor_display - syntax checker":
  test "toggleSyntaxChecker flips the config flag":
    let e = createTestEditor()
    let before = e.showSyntaxChecker
    e.toggleSyntaxChecker()
    check e.showSyntaxChecker == not before

  test "setSyntaxCheckerVisible sets the config flag":
    let e = createTestEditor()
    e.setSyntaxCheckerVisible(false)
    check e.showSyntaxChecker == false
    e.setSyntaxCheckerVisible(true)
    check e.showSyntaxChecker == true
