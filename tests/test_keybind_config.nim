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

import std/[unittest, options, os, tables, strutils]

import ../src/moepkg/keybind_config {.all.}
import ../src/moepkg/key_bindings
import ../src/moepkg/modes
import ../src/moepkg/types
import ../src/moepkg/config_loader

suite "KeybindConfig - parseModes":
  test "parse normal mode":
    check parseModes("normal") == @[EditorMode.Normal]

  test "parse insert mode":
    check parseModes("insert") == @[EditorMode.Insert]

  test "parse visual mode":
    check parseModes("visual") == @[EditorMode.Visual]

  test "parse visualline mode":
    check parseModes("visualline") == @[EditorMode.VisualLine]

  test "parse visualblock mode":
    check parseModes("visualblock") == @[EditorMode.VisualBlock]

  test "parse replace mode":
    check parseModes("replace") == @[EditorMode.Replace]

  test "parse command mode":
    check parseModes("command") == @[EditorMode.Command]

  test "parse filer mode":
    check parseModes("filer") == @[EditorMode.Filer]

  test "parse quickrun mode":
    check parseModes("quickrun") == @[EditorMode.QuickRun]

  test "parse logviewer mode":
    check parseModes("logviewer") == @[EditorMode.LogViewer]

  test "parse help mode":
    check parseModes("help") == @[EditorMode.Help]

  test "parse buffermanager mode":
    check parseModes("buffermanager") == @[EditorMode.BufferManager]

  test "parse backupmanager mode":
    check parseModes("backupmanager") == @[EditorMode.BackupManager]

  test "parse diffviewer mode":
    check parseModes("diffviewer") == @[EditorMode.DiffViewer]

  test "parse recentfile mode":
    check parseModes("recentfile") == @[EditorMode.RecentFile]

  test "parse debug mode":
    check parseModes("debug") == @[EditorMode.Debug]

  test "parse config mode":
    check parseModes("config") == @[EditorMode.Config]

  test "parse references mode":
    check parseModes("references") == @[EditorMode.References]

  test "parse documentsymbol mode":
    check parseModes("documentsymbol") == @[EditorMode.DocumentSymbol]

  test "parse callhierarchy mode":
    check parseModes("callhierarchy") == @[EditorMode.CallHierarchy]

  test "parse terminal mode":
    check parseModes("terminal") == @[EditorMode.Terminal]

  test "parse all meta mode":
    let modes = parseModes("all")
    check modes.len == 22 # All except CommandLine
    check EditorMode.Command notin modes
    check EditorMode.Normal in modes
    check EditorMode.Insert in modes
    check EditorMode.Visual in modes
    check EditorMode.QuickRun in modes
    check EditorMode.Terminal in modes

  test "parse visualall meta mode":
    let modes = parseModes("visualall")
    check modes.len == 3
    check EditorMode.Visual in modes
    check EditorMode.VisualLine in modes
    check EditorMode.VisualBlock in modes

  test "parse mode is case insensitive":
    check parseModes("NORMAL") == @[EditorMode.Normal]
    check parseModes("Normal") == @[EditorMode.Normal]
    check parseModes("INSERT") == @[EditorMode.Insert]
    check parseModes("ALL").len == 22
    check parseModes("VisualAll").len == 3

  test "parse unknown mode returns empty seq":
    check parseModes("unknown").len == 0
    check parseModes("").len == 0

suite "KeybindConfig - parseOverlay":
  test "parse command overlay":
    check parseOverlay("command").isSome
    check parseOverlay("command").get == okCommand

  test "parse search overlay":
    check parseOverlay("search").isSome
    check parseOverlay("search").get == okSearch

  test "parse rename overlay":
    check parseOverlay("rename").isSome
    check parseOverlay("rename").get == okRename

  test "parse overlay is case insensitive":
    check parseOverlay("COMMAND").isSome
    check parseOverlay("COMMAND").get == okCommand
    check parseOverlay("Command").isSome
    check parseOverlay("Command").get == okCommand
    check parseOverlay("SEARCH").isSome
    check parseOverlay("SEARCH").get == okSearch
    check parseOverlay("RENAME").isSome
    check parseOverlay("RENAME").get == okRename

  test "parse unknown overlay returns none":
    check parseOverlay("unknown").isNone
    check parseOverlay("normal").isNone
    check parseOverlay("insert").isNone
    check parseOverlay("").isNone

suite "KeybindConfig - parseCommandType":
  test "parse motion":
    check parseCommandType("motion") == ctMotion

  test "parse action":
    check parseCommandType("action") == ctAction

  test "parse mode_switch":
    check parseCommandType("mode_switch") == ctModeSwitch
    check parseCommandType("modeswitch") == ctModeSwitch

  test "parse overlay_switch":
    check parseCommandType("overlay_switch") == ctOverlaySwitch
    check parseCommandType("overlayswitch") == ctOverlaySwitch

  test "parse text_object":
    check parseCommandType("text_object") == ctTextObject
    check parseCommandType("textobject") == ctTextObject

  test "parse operator":
    check parseCommandType("operator") == ctOperator

  test "parse operator_pending":
    check parseCommandType("operator_pending") == ctOperatorPending
    check parseCommandType("operatorpending") == ctOperatorPending

  test "parse custom":
    check parseCommandType("custom") == ctCustom

  test "parse command type is case insensitive":
    check parseCommandType("MOTION") == ctMotion
    check parseCommandType("Motion") == ctMotion
    check parseCommandType("ACTION") == ctAction
    check parseCommandType("MODE_SWITCH") == ctModeSwitch
    check parseCommandType("OVERLAY_SWITCH") == ctOverlaySwitch

  test "unknown command type defaults to action":
    check parseCommandType("unknown") == ctAction
    check parseCommandType("") == ctAction
    check parseCommandType("invalid") == ctAction

suite "KeybindConfig - addKeybinding":
  test "add keybinding to registry":
    let registry = newKeyBindingRegistry()
    let cmd = Command(
      kind: ctAction,
      name: "test-command",
      description: "Test command",
      commandId: "test.command",
      args: @[],
    )
    registry.addKeybinding(EditorMode.Normal, "C-t", cmd)

    # Check that the binding was added
    check registry.bindings[EditorMode.Normal].len > 0
    let lastBinding = registry.bindings[EditorMode.Normal][^1]
    check lastBinding.command.name == "test-command"
    check lastBinding.command.commandId == "test.command"

  test "add keybinding with special key":
    let registry = newKeyBindingRegistry()
    let cmd = Command(
      kind: ctMotion, name: "move-up", description: "Move cursor up", motion: Motion.Up
    )
    registry.addKeybinding(EditorMode.Normal, "Up", cmd)

    check registry.bindings[EditorMode.Normal].len > 0
    let lastBinding = registry.bindings[EditorMode.Normal][^1]
    check lastBinding.combo.isSpecial
    check lastBinding.combo.special == skUp

  test "add keybinding with invalid key string does nothing":
    let registry = newKeyBindingRegistry()
    let initialCount = registry.bindings[EditorMode.Normal].len
    let cmd = Command(
      kind: ctAction,
      name: "test-command",
      description: "Test command",
      commandId: "test.command",
      args: @[],
    )
    registry.addKeybinding(EditorMode.Normal, "invalid-key-format-xyz", cmd)

    # Should not add binding for invalid key
    check registry.bindings[EditorMode.Normal].len == initialCount

  test "add keybinding to empty mode":
    let registry = KeyBindingRegistry(
      bindings: initTable[EditorMode, seq[KeyBinding]](),
      sequences: initTable[EditorMode, Table[seq[KeyCombo], Command]](),
      commandRegistry: initTable[string, Command](),
      runtimeMappings: initTable[EditorMode, seq[RuntimeKeyMapping]](),
    )
    let cmd = Command(
      kind: ctAction,
      name: "test-command",
      description: "Test command",
      commandId: "test.command",
      args: @[],
    )
    registry.addKeybinding(EditorMode.Insert, "C-s", cmd)

    check registry.bindings.hasKey(EditorMode.Insert)
    check registry.bindings[EditorMode.Insert].len == 1

suite "KeybindConfig - loadKeybindingsFromToml":
  test "load keybindings from non-existent file does nothing":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml("/nonexistent/path/keybindings.toml", vr)

    # Should not crash and bindings should remain unchanged
    check registry.bindings[EditorMode.Normal].len == initialCount
    check not vr.hasErrors

  test "load action keybinding from toml":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-q"
command_type = "action"
command = "file.quit"
"""
    let testPath = getTempDir() / "test_keybind_action.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    check registry.bindings[EditorMode.Normal].len == initialCount + 1
    let lastBinding = registry.bindings[EditorMode.Normal][^1]
    check lastBinding.command.kind == ctAction
    check lastBinding.command.commandId == "file.quit"

  test "load mode switch keybinding from toml":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "insert"
key = "C-n"
command_type = "mode_switch"
target_mode = "normal"
"""
    let testPath = getTempDir() / "test_keybind_modeswitch.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Insert].len
    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    check registry.bindings[EditorMode.Insert].len == initialCount + 1
    let lastBinding = registry.bindings[EditorMode.Insert][^1]
    check lastBinding.command.kind == ctModeSwitch
    check lastBinding.command.targetMode == EditorMode.Normal

  test "load overlay switch keybinding from toml":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-f"
command_type = "overlay_switch"
target_overlay = "search"
"""
    let testPath = getTempDir() / "test_keybind_overlay.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    check registry.bindings[EditorMode.Normal].len == initialCount + 1
    let lastBinding = registry.bindings[EditorMode.Normal][^1]
    check lastBinding.command.kind == ctOverlaySwitch
    check lastBinding.command.targetOverlay == okSearch

  test "load keybinding with args from toml":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-p"
command_type = "custom"
command = "custom.command"
args = ["arg1", "arg2"]
"""
    let testPath = getTempDir() / "test_keybind_args.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    check registry.bindings[EditorMode.Normal].len == initialCount + 1
    let lastBinding = registry.bindings[EditorMode.Normal][^1]
    check lastBinding.command.kind == ctCustom
    check lastBinding.command.commandId == "custom.command"
    check lastBinding.command.args == @["arg1", "arg2"]

  test "load multiple keybindings from toml":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-a"
command_type = "action"
command = "select.all"

[[keybinding]]
mode = "normal"
key = "C-b"
command_type = "action"
command = "buffer.switch"
"""
    let testPath = getTempDir() / "test_keybind_multiple.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    check registry.bindings[EditorMode.Normal].len == initialCount + 2

  test "skip keybinding with missing mode":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
key = "C-x"
command_type = "action"
command = "test.command"
"""
    let testPath = getTempDir() / "test_keybind_nomode.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath, vr)

    # Should skip invalid binding
    check registry.bindings[EditorMode.Normal].len == initialCount

  test "skip keybinding with missing key":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
command_type = "action"
command = "test.command"
"""
    let testPath = getTempDir() / "test_keybind_nokey.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath, vr)

    # Should skip invalid binding
    check registry.bindings[EditorMode.Normal].len == initialCount

  test "skip keybinding with invalid mode":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "invalid_mode"
key = "C-x"
command_type = "action"
command = "test.command"
"""
    let testPath = getTempDir() / "test_keybind_badmode.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath, vr)

    # Should skip invalid binding
    check registry.bindings[EditorMode.Normal].len == initialCount

  test "default command type to action when not specified":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-z"
command = "undo"
"""
    let testPath = getTempDir() / "test_keybind_default_type.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    check registry.bindings[EditorMode.Normal].len == initialCount + 1
    let lastBinding = registry.bindings[EditorMode.Normal][^1]
    check lastBinding.command.kind == ctAction

  test "skip toml with no keybinding array":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[settings]
name = "test"
"""
    let testPath = getTempDir() / "test_keybind_no_array.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath, vr)

    # Should not crash and bindings should remain unchanged
    check not vr.hasErrors
    check registry.bindings[EditorMode.Normal].len == initialCount

suite "KeybindConfig - loadKeybindingsFromToml error reporting":
  test "report error for invalid TOML":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
this is not valid toml {{{
"""
    let testPath = getTempDir() / "test_keybind_invalid_toml.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    check vr.errors.len == 1
    check "keybindings" in vr.errors[0].name

  test "report error for invalid mode":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "invalid_mode"
key = "C-x"
command_type = "action"
command = "test.command"
"""
    let testPath = getTempDir() / "test_keybind_err_mode.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    check vr.errors.len == 1
    check "mode" in vr.errors[0].name
    check "invalid_mode" in vr.errors[0].val

  test "report error for missing mode":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
key = "C-x"
command_type = "action"
command = "test.command"
"""
    let testPath = getTempDir() / "test_keybind_err_nomode.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    check vr.errors.len == 1
    check "mode" in vr.errors[0].name
    check "(missing)" in vr.errors[0].val

  test "report error for missing key":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
command_type = "action"
command = "test.command"
"""
    let testPath = getTempDir() / "test_keybind_err_nokey.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    check vr.errors.len == 1
    check "key" in vr.errors[0].name
    check "(missing)" in vr.errors[0].val

  test "report error for missing command":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-x"
command_type = "action"
"""
    let testPath = getTempDir() / "test_keybind_err_nocmd.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    check vr.errors.len == 1
    check "command" in vr.errors[0].name

  test "report error for missing target_mode":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-x"
command_type = "mode_switch"
"""
    let testPath = getTempDir() / "test_keybind_err_notargetmode.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    check vr.errors.len == 1
    check "target_mode" in vr.errors[0].name
    check "(missing)" in vr.errors[0].val

  test "report error for invalid target_mode":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-x"
command_type = "mode_switch"
target_mode = "badmode"
"""
    let testPath = getTempDir() / "test_keybind_err_badtargetmode.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    check vr.errors.len == 1
    check "target_mode" in vr.errors[0].name
    check "badmode" in vr.errors[0].val

  test "report error for missing target_overlay":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-x"
command_type = "overlay_switch"
"""
    let testPath = getTempDir() / "test_keybind_err_notargetoverlay.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    check vr.errors.len == 1
    check "target_overlay" in vr.errors[0].name
    check "(missing)" in vr.errors[0].val

  test "report error for invalid target_overlay":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-x"
command_type = "overlay_switch"
target_overlay = "badoverlay"
"""
    let testPath = getTempDir() / "test_keybind_err_badtargetoverlay.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    check vr.errors.len == 1
    check "target_overlay" in vr.errors[0].name
    check "badoverlay" in vr.errors[0].val

  test "report error for unsupported command_type (motion)":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-x"
command_type = "motion"
"""
    let testPath = getTempDir() / "test_keybind_err_motion.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    check vr.errors.len == 1
    check "command_type" in vr.errors[0].name
    check "motion" in vr.errors[0].val

  test "collect multiple errors from multiple entries":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "bad_mode"
key = "C-a"
command_type = "action"
command = "test.a"

[[keybinding]]
mode = "normal"
key = "C-b"
command_type = "action"

[[keybinding]]
mode = "normal"
key = "C-c"
command_type = "mode_switch"
target_mode = "bad_target"
"""
    let testPath = getTempDir() / "test_keybind_err_multi.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    check vr.errors.len == 3

  test "valid and invalid entries mixed - valid ones still load":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-a"
command_type = "action"
command = "test.valid"

[[keybinding]]
mode = "bad_mode"
key = "C-b"
command_type = "action"
command = "test.invalid"

[[keybinding]]
mode = "normal"
key = "C-c"
command_type = "action"
command = "test.valid2"
"""
    let testPath = getTempDir() / "test_keybind_err_mixed.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath, vr)

    # 1 error for the bad_mode entry
    check vr.hasErrors
    check vr.errors.len == 1
    # 2 valid entries should have been loaded
    check registry.bindings[EditorMode.Normal].len == initialCount + 2

suite "KeybindConfig - getKeybindingsPath":
  test "getKeybindingsPath returns a path ending with keybindings.toml":
    let path = getKeybindingsPath()
    check path.endsWith("keybindings.toml")

  test "getKeybindingsPath returns path in moe config directory":
    let path = getKeybindingsPath()
    check path.contains("moe")

suite "KeybindConfig - Undo/Redo keybindings":
  test "Undo command is registered":
    let keyRegistry = newKeyBindingRegistry()
    keyRegistry.setupDefaultBindings()

    check keyRegistry.commandRegistry.hasKey("undo")
    let undoCmd = keyRegistry.commandRegistry["undo"]
    check undoCmd.name == "undo"
    check undoCmd.kind == ctAction
    check undoCmd.commandId == "edit.undo"

  test "Redo command is registered":
    let keyRegistry = newKeyBindingRegistry()
    keyRegistry.setupDefaultBindings()

    check keyRegistry.commandRegistry.hasKey("redo")
    let redoCmd = keyRegistry.commandRegistry["redo"]
    check redoCmd.name == "redo"
    check redoCmd.kind == ctAction
    check redoCmd.commandId == "edit.redo"

  test "Undo keybinding 'u' is registered for Normal mode":
    let keyRegistry = newKeyBindingRegistry()
    keyRegistry.setupDefaultBindings()

    let uKey = toKeyCombo('u')
    let binding = keyRegistry.findBinding(EditorMode.Normal, uKey)
    check binding.isSome
    check binding.get.name == "undo"

  test "Redo keybinding 'Ctrl-r' is registered for Normal mode":
    let keyRegistry = newKeyBindingRegistry()
    keyRegistry.setupDefaultBindings()

    let ctrlR = toKeyCombo('r', ctrl = true)
    let binding = keyRegistry.findBinding(EditorMode.Normal, ctrlR)
    check binding.isSome
    check binding.get.name == "redo"

suite "KeybindConfig - resolves command name via commandRegistry":
  test "registered alias preserves real commandId (bnext -> exec.cmdline.bnext)":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    registry.setupDefaultBindings()

    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "J"
command_type = "action"
command = "bnext"
"""
    let testPath = getTempDir() / "test_keybind_bnext.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    let jKey = toKeyCombo('J')
    let binding = registry.findBinding(EditorMode.Normal, jKey)
    check binding.isSome
    check binding.get.name == "bnext"
    check binding.get.commandId == "exec.cmdline.bnext"

  test "registered alias preserves real commandId (bprev -> exec.cmdline.bprev)":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    registry.setupDefaultBindings()

    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "K"
command_type = "action"
command = "bprev"
"""
    let testPath = getTempDir() / "test_keybind_bprev.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    let kKey = toKeyCombo('K')
    let binding = registry.findBinding(EditorMode.Normal, kKey)
    check binding.isSome
    check binding.get.commandId == "exec.cmdline.bprev"

  test "args from toml override registered command args":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    registry.setupDefaultBindings()

    # "bnext" is registered with args=@[]; verify TOML args win.
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-q"
command_type = "action"
command = "bnext"
args = ["one", "two"]
"""
    let testPath = getTempDir() / "test_keybind_args_override.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    let combo = toKeyCombo('q', ctrl = true)
    let binding = registry.findBinding(EditorMode.Normal, combo)
    check binding.isSome
    check binding.get.commandId == "exec.cmdline.bnext"
    check binding.get.args == @["one", "two"]

  test "unknown command name produces validation error":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    registry.setupDefaultBindings()

    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-y"
command_type = "action"
command = "no.such.command"
"""
    let testPath = getTempDir() / "test_keybind_unknown.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    let combo = toKeyCombo('y', ctrl = true)
    check registry.findBinding(EditorMode.Normal, combo).isNone

  test "command_type mismatch with registered command produces error":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    registry.setupDefaultBindings()

    # "find-char" is registered as ctOperatorPending, not ctAction
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-y"
command_type = "action"
command = "find-char"
"""
    let testPath = getTempDir() / "test_keybind_kind_mismatch.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    let combo = toKeyCombo('y', ctrl = true)
    check registry.findBinding(EditorMode.Normal, combo).isNone

  test "kind mismatch without explicit command_type reports default (#2597)":
    # Regression: omitting command_type used to make the kind-mismatch branch
    # access binding["command_type"] and raise KeyError. The error should
    # surface as a validation error instead.
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    registry.setupDefaultBindings()

    # "find-char" is ctOperatorPending; no command_type defaults to ctAction.
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-y"
command = "find-char"
"""
    let testPath = getTempDir() / "test_keybind_kind_mismatch_default.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    let combo = toKeyCombo('y', ctrl = true)
    check registry.findBinding(EditorMode.Normal, combo).isNone

  test "default command_type=action binds registered ctAction command (#2597)":
    # Positive counterpart to the previous test: when command_type is omitted
    # and the registered Command kind matches the default (ctAction), the
    # binding should be added without errors.
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    registry.setupDefaultBindings()

    # "save" is registered as ctAction in setupDefaultBindings.
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-s"
command = "save"
"""
    let testPath = getTempDir() / "test_keybind_default_action.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    let combo = toKeyCombo('s', ctrl = true)
    let binding = registry.findBinding(EditorMode.Normal, combo)
    check binding.isSome
    check binding.get.name == "save"
    check binding.get.commandId == "file.save"

suite "KeybindConfig - loadDefaultKeybindings":
  test "Does not crash":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    registry.setupDefaultBindings()
    registry.loadDefaultKeybindings(vr)

  test "Existing bindings are preserved":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    registry.setupDefaultBindings()
    let countBefore = registry.bindings[EditorMode.Normal].len
    registry.loadDefaultKeybindings(vr)
    # Existing bindings should still be present (count >= before)
    check registry.bindings[EditorMode.Normal].len >= countBefore

suite "KeybindConfig - multi-key sequences":
  test "space-separated key sequence registers in sequences table":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "g d"
command_type = "action"
command = "goto.definition"
"""
    let testPath = getTempDir() / "test_keybind_multikey.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    # Multi-key sequence should be in sequences table, not bindings
    check registry.sequences[EditorMode.Normal].len > 0

  test "modifier plus key sequence registers in sequences table":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-w n"
command_type = "action"
command = "window.new"
"""
    let testPath = getTempDir() / "test_keybind_modseq.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    check registry.sequences[EditorMode.Normal].len > 0

  test "invalid key string reports error":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-invalid-xyz"
command_type = "action"
command = "test.command"
"""
    let testPath = getTempDir() / "test_keybind_badkey.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    check vr.errors.len == 1
    check "key" in vr.errors[0].name

suite "KeybindConfig - command existence check":
  test "nonexistent command reports error after setupDefaultBindings":
    let registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-x"
command_type = "action"
command = "nonexistent-command"
"""
    let testPath = getTempDir() / "test_keybind_nocmd_exist.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    check vr.errors.len == 1
    check "command" in vr.errors[0].name
    check "nonexistent-command" in vr.errors[0].val

  test "existing command loads without error after setupDefaultBindings":
    let registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-x"
command_type = "action"
command = "undo"
"""
    let testPath = getTempDir() / "test_keybind_cmd_exist.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors

suite "KeybindConfig - all mode binding":
  test "mode all registers to all modes except CommandLine":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "all"
key = "C-q"
command_type = "action"
command = "quit"
"""
    let testPath = getTempDir() / "test_keybind_allmode.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    # Should be registered in all modes except CommandLine
    for mode in EditorMode:
      if mode == EditorMode.Command:
        check registry.bindings[mode].len == 0
      else:
        check registry.bindings[mode].len > 0

suite "KeybindConfig - key_sequence mapping":
  test "load key_sequence keybinding from toml":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "insert"
key = "jj"
command_type = "key_sequence"
target_keys = "Escape"
"""
    let testPath = getTempDir() / "test_keybind_keyseq.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    # key_sequence should be in runtimeMappings only, not in bindings/sequences
    check registry.runtimeMappings[EditorMode.Insert].len > 0
    let lastMapping = registry.runtimeMappings[EditorMode.Insert][^1]
    check lastMapping.kind == rmkKeySequence
    check lastMapping.triggerStr == "jj"
    check lastMapping.targetStr == "Escape"
    check lastMapping.targetKeys.len == 1

  test "load key_sequence with multi-key target":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-a"
command_type = "key_sequence"
target_keys = "g g"
"""
    let testPath = getTempDir() / "test_keybind_keyseq_multi.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    check registry.runtimeMappings[EditorMode.Normal].len > 0
    let lastMapping = registry.runtimeMappings[EditorMode.Normal][^1]
    check lastMapping.kind == rmkKeySequence
    check lastMapping.targetKeys.len == 2

  test "key_sequence does not register in bindings table":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "insert"
key = "C-a"
command_type = "key_sequence"
target_keys = "Escape"
"""
    let testPath = getTempDir() / "test_keybind_keyseq_nobind.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Insert].len
    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    # Should NOT be in bindings table
    check registry.bindings[EditorMode.Insert].len == initialCount

  test "key_sequence with all mode registers to all modes except CommandLine":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "all"
key = "C-a"
command_type = "key_sequence"
target_keys = "Escape"
"""
    let testPath = getTempDir() / "test_keybind_keyseq_all.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    for mode in EditorMode:
      if mode == EditorMode.Command:
        check not registry.runtimeMappings.hasKey(mode) or
          registry.runtimeMappings[mode].len == 0
      else:
        check registry.runtimeMappings[mode].len > 0

  test "report error for missing target_keys":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "insert"
key = "jj"
command_type = "key_sequence"
"""
    let testPath = getTempDir() / "test_keybind_keyseq_notarget.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    check vr.errors.len == 1
    check "target_keys" in vr.errors[0].name
    check "(missing)" in vr.errors[0].val

  test "report error for invalid target_keys":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "insert"
key = "jj"
command_type = "key_sequence"
target_keys = "C-invalid-xyz"
"""
    let testPath = getTempDir() / "test_keybind_keyseq_badtarget.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check vr.hasErrors
    check vr.errors.len == 1
    check "target_keys" in vr.errors[0].name

  test "keysequence variant (no underscore) also works":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "insert"
key = "jj"
command_type = "keysequence"
target_keys = "Escape"
"""
    let testPath = getTempDir() / "test_keybind_keyseq_nounderscore.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    check registry.runtimeMappings[EditorMode.Insert].len > 0
    let lastMapping = registry.runtimeMappings[EditorMode.Insert][^1]
    check lastMapping.kind == rmkKeySequence

  test "key_sequence command_type is case insensitive":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "insert"
key = "jj"
command_type = "KEY_SEQUENCE"
target_keys = "Escape"
"""
    let testPath = getTempDir() / "test_keybind_keyseq_case.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    check registry.runtimeMappings[EditorMode.Insert].len > 0
    let lastMapping = registry.runtimeMappings[EditorMode.Insert][^1]
    check lastMapping.kind == rmkKeySequence

  test "key_sequence with multi-key trigger":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "g g"
command_type = "key_sequence"
target_keys = "C-a"
"""
    let testPath = getTempDir() / "test_keybind_keyseq_multitrigger.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    check registry.runtimeMappings[EditorMode.Normal].len > 0
    let lastMapping = registry.runtimeMappings[EditorMode.Normal][^1]
    check lastMapping.kind == rmkKeySequence
    check lastMapping.triggerKeys.len == 2
    check lastMapping.targetKeys.len == 1

  test "key_sequence does not register in sequences table":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "g g"
command_type = "key_sequence"
target_keys = "Escape"
"""
    let testPath = getTempDir() / "test_keybind_keyseq_noseq.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialSeqCount =
      if registry.sequences.hasKey(EditorMode.Normal):
        registry.sequences[EditorMode.Normal].len
      else:
        0
    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    let seqCount =
      if registry.sequences.hasKey(EditorMode.Normal):
        registry.sequences[EditorMode.Normal].len
      else:
        0
    check seqCount == initialSeqCount

  test "key_sequence mixed with action entries":
    let registry = newKeyBindingRegistry()
    var vr = newValidationResult()
    let tomlContent = """
[[keybinding]]
mode = "normal"
key = "C-s"
command = "save"

[[keybinding]]
mode = "insert"
key = "jj"
command_type = "key_sequence"
target_keys = "Escape"

[[keybinding]]
mode = "normal"
key = "C-q"
command = "quit-force"
"""
    let testPath = getTempDir() / "test_keybind_keyseq_mixed.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialNormalCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath, vr)

    check not vr.hasErrors
    # 2 action bindings in normal mode
    check registry.bindings[EditorMode.Normal].len == initialNormalCount + 2
    # 1 key_sequence in insert mode runtimeMappings
    check registry.runtimeMappings[EditorMode.Insert].len > 0
    check registry.runtimeMappings[EditorMode.Insert][^1].kind == rmkKeySequence

suite "KeybindConfig - addKeySequenceMapping":
  test "addKeySequenceMapping registers in runtimeMappings":
    let registry = newKeyBindingRegistry()
    registry.addKeySequenceMapping(EditorMode.Insert, "jj", "Escape")

    check registry.runtimeMappings[EditorMode.Insert].len > 0
    let lastMapping = registry.runtimeMappings[EditorMode.Insert][^1]
    check lastMapping.kind == rmkKeySequence
    check lastMapping.triggerStr == "jj"
    check lastMapping.targetStr == "Escape"
    check lastMapping.targetKeys.len == 1

  test "addKeySequenceMapping does not register in bindings":
    let registry = newKeyBindingRegistry()
    let initialCount = registry.bindings[EditorMode.Insert].len
    registry.addKeySequenceMapping(EditorMode.Insert, "jj", "Escape")

    check registry.bindings[EditorMode.Insert].len == initialCount

  test "addKeySequenceMapping with invalid trigger does nothing":
    let registry = newKeyBindingRegistry()
    registry.addKeySequenceMapping(EditorMode.Insert, "C-invalid-xyz", "Escape")

    check not registry.runtimeMappings.hasKey(EditorMode.Insert) or
      registry.runtimeMappings[EditorMode.Insert].len == 0

  test "addKeySequenceMapping with invalid target does nothing":
    let registry = newKeyBindingRegistry()
    registry.addKeySequenceMapping(EditorMode.Insert, "jj", "C-invalid-xyz")

    check not registry.runtimeMappings.hasKey(EditorMode.Insert) or
      registry.runtimeMappings[EditorMode.Insert].len == 0

suite "KeybindConfig - runtimeMappings":
  test "addKeybinding registers in runtimeMappings":
    let registry = newKeyBindingRegistry()
    let cmd = Command(
      kind: ctAction,
      name: "test-command",
      description: "Test command",
      commandId: "test.command",
      args: @[],
    )
    registry.addKeybinding(EditorMode.Normal, "C-t", cmd)

    check registry.runtimeMappings[EditorMode.Normal].len > 0
    let lastMapping = registry.runtimeMappings[EditorMode.Normal][^1]
    check lastMapping.kind == rmkCommand
    check lastMapping.commandName == "test-command"
    check lastMapping.triggerStr == "C-t"

  test "addKeybinding multi-key registers in runtimeMappings":
    let registry = newKeyBindingRegistry()
    let cmd = Command(
      kind: ctAction,
      name: "goto-def",
      description: "Go to definition",
      commandId: "goto.definition",
      args: @[],
    )
    registry.addKeybinding(EditorMode.Normal, "g d", cmd)

    check registry.runtimeMappings[EditorMode.Normal].len > 0
    let lastMapping = registry.runtimeMappings[EditorMode.Normal][^1]
    check lastMapping.kind == rmkCommand
    check lastMapping.commandName == "goto-def"
    check lastMapping.triggerStr == "g d"
    check lastMapping.triggerKeys.len == 2
