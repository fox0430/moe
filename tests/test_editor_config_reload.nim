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

## Tests for editor_config_reload.nim

import std/[unittest, os, monotimes, times]

import pkg/results

import
  ../src/moepkg/
    [editor, config, config_loader, editor_config_reload, lsp_integration, types]
import ../src/moepkg/types/editor_types
import config_test_helper

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc pastMonoTime(ms: int64): MonoTime =
  getMonoTime() - initDuration(milliseconds = ms)

suite "editor_config_reload - applyConfigSettings":
  test "updates search settings":
    let e = createTestEditor()
    var newConfig = newEditorConfig()
    newConfig.standard.ignorecase = false
    newConfig.standard.smartcase = false
    newConfig.standard.incrementalSearch = false
    e.applyConfigSettings(newConfig)
    check e.state.input.search.ignorecase == false
    check e.state.input.search.smartcase == false
    check e.state.input.search.incsearch == false

  test "updates the git diff refresh interval":
    let e = createTestEditor()
    var newConfig = newEditorConfig()
    newConfig.git.updateInterval = 4321
    e.applyConfigSettings(newConfig)
    check e.state.timing.gitDiffUpdateInterval == 4321

  test "updates the clipboard tool":
    let e = createTestEditor()
    var newConfig = newEditorConfig()
    newConfig.clipboard.enable = true
    newConfig.clipboard.tool = cbtWlClipboard
    e.applyConfigSettings(newConfig)
    check e.state.registers.clipboardTool == some(cbtWlClipboard)

  test "does not touch the clipboard tool when clipboard is disabled":
    let e = createTestEditor()
    var newConfig = newEditorConfig()
    newConfig.clipboard.enable = false
    newConfig.clipboard.tool = cbtXsel
    let before = e.state.registers.clipboardTool
    e.applyConfigSettings(newConfig)
    check e.state.registers.clipboardTool == before

  test "applies highlight config to all buffers":
    let e = createTestEditor()
    var newConfig = newEditorConfig()
    newConfig.highlight.reservedWord = @["FIXME"]
    e.applyConfigSettings(newConfig)
    for buf in e.buffers:
      check buf.reservedWords.len == 1
      check buf.reservedWords[0].word == "FIXME"

  test "updates the notification popup settings":
    let e = createTestEditor()
    var newConfig = newEditorConfig()
    newConfig.notification.popupTimeoutMs = 500
    newConfig.notification.popupMaxVisible = 3
    newConfig.notification.popupPosition = "topLeft"
    e.applyConfigSettings(newConfig)
    check e.state.notificationPopup.timeoutMs == 500
    check e.state.notificationPopup.maxVisible == 3
    check e.state.notificationPopup.position == nppTopLeft

  test "stores the new config in state":
    let e = createTestEditor()
    var newConfig = newEditorConfig()
    newConfig.standard.number = false
    e.applyConfigSettings(newConfig)
    check e.config.standard.number == false

  test "disables LSP servers at runtime":
    let e = createTestEditor()
    e.lsp.setEnabled(true)
    var newConfig = newEditorConfig()
    newConfig.lsp.enable = false
    e.applyConfigSettings(newConfig)
    check e.lsp.isEnabled() == false

suite "editor_config_reload - maybeReloadConfig":
  test "is a no-op when liveReloadOfConf is disabled":
    var config = newEditorConfig()
    config.standard.liveReloadOfConf = false
    let vr = newValidationResult()
    let e = newEditor(config, vr)
    e.state.timing.lastConfigCheck = pastMonoTime(5000)
    e.maybeReloadConfig()
    check e.state.statusMessage != "Configuration reloaded"

  test "is a no-op during the debounce window":
    let e = createTestEditor()
    e.config.standard.liveReloadOfConf = true
    let lastCheck = getMonoTime()
    e.state.timing.lastConfigCheck = lastCheck
    e.maybeReloadConfig()
    check e.state.timing.lastConfigCheck == lastCheck
    check e.state.statusMessage != "Configuration reloaded"

  test "reloads the config when the file is modified":
    withTempHome(tmpDir):
      let configDir = tmpDir / ".config" / "moe"
      createDir(configDir)
      writeFile(configDir / "moerc.toml", "[Standard]\nnumber = false\n")
      var config = newEditorConfig()
      config.standard.liveReloadOfConf = true
      let vr = newValidationResult()
      let e = newEditor(config, vr)
      e.state.timing.lastConfigCheck = pastMonoTime(3000)
      e.state.timing.lastConfigModTime = times.Time()
      e.maybeReloadConfig()
      check e.state.statusMessage == "Configuration reloaded"
      check e.config.standard.number == false
      e.state.statusMessage = ""
      e.state.timing.lastConfigCheck = pastMonoTime(3000)
      e.maybeReloadConfig()
      check e.state.statusMessage != "Configuration reloaded"
