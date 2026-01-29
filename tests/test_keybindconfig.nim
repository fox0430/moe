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

import ../src/moepkg/keybindconfig {.all.}
import ../src/moepkg/keybindings
import ../src/moepkg/modes
import ../src/moepkg/types

suite "KeybindConfig - parseMode":
  test "parse normal mode":
    check parseMode("normal").isSome
    check parseMode("normal").get == EditorMode.Normal

  test "parse insert mode":
    check parseMode("insert").isSome
    check parseMode("insert").get == EditorMode.Insert

  test "parse visual mode":
    check parseMode("visual").isSome
    check parseMode("visual").get == EditorMode.Visual

  test "parse replace mode":
    check parseMode("replace").isSome
    check parseMode("replace").get == EditorMode.Replace

  test "parse mode is case insensitive":
    check parseMode("NORMAL").isSome
    check parseMode("NORMAL").get == EditorMode.Normal
    check parseMode("Normal").isSome
    check parseMode("Normal").get == EditorMode.Normal
    check parseMode("INSERT").isSome
    check parseMode("INSERT").get == EditorMode.Insert

  test "parse unknown mode returns none":
    check parseMode("unknown").isNone
    check parseMode("command").isNone
    check parseMode("search").isNone
    check parseMode("").isNone

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
    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml("/nonexistent/path/keybindings.toml")

    # Should not crash and bindings should remain unchanged
    check registry.bindings[EditorMode.Normal].len == initialCount

  test "load action keybinding from toml":
    let registry = newKeyBindingRegistry()
    let tomlContent =
      """
[[keybinding]]
mode = "normal"
key = "C-q"
command_type = "action"
command = "file.quit"
"""
    let testPath = "/tmp/test_keybind_action.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath)

    check registry.bindings[EditorMode.Normal].len == initialCount + 1
    let lastBinding = registry.bindings[EditorMode.Normal][^1]
    check lastBinding.command.kind == ctAction
    check lastBinding.command.commandId == "file.quit"

  test "load mode switch keybinding from toml":
    let registry = newKeyBindingRegistry()
    let tomlContent =
      """
[[keybinding]]
mode = "insert"
key = "C-n"
command_type = "mode_switch"
target_mode = "normal"
"""
    let testPath = "/tmp/test_keybind_modeswitch.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Insert].len
    registry.loadKeybindingsFromToml(testPath)

    check registry.bindings[EditorMode.Insert].len == initialCount + 1
    let lastBinding = registry.bindings[EditorMode.Insert][^1]
    check lastBinding.command.kind == ctModeSwitch
    check lastBinding.command.targetMode == EditorMode.Normal

  test "load overlay switch keybinding from toml":
    let registry = newKeyBindingRegistry()
    let tomlContent =
      """
[[keybinding]]
mode = "normal"
key = "C-f"
command_type = "overlay_switch"
target_overlay = "search"
"""
    let testPath = "/tmp/test_keybind_overlay.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath)

    check registry.bindings[EditorMode.Normal].len == initialCount + 1
    let lastBinding = registry.bindings[EditorMode.Normal][^1]
    check lastBinding.command.kind == ctOverlaySwitch
    check lastBinding.command.targetOverlay == okSearch

  test "load keybinding with args from toml":
    let registry = newKeyBindingRegistry()
    let tomlContent =
      """
[[keybinding]]
mode = "normal"
key = "C-p"
command_type = "custom"
command = "custom.command"
args = ["arg1", "arg2"]
"""
    let testPath = "/tmp/test_keybind_args.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath)

    check registry.bindings[EditorMode.Normal].len == initialCount + 1
    let lastBinding = registry.bindings[EditorMode.Normal][^1]
    check lastBinding.command.kind == ctCustom
    check lastBinding.command.commandId == "custom.command"
    check lastBinding.command.args == @["arg1", "arg2"]

  test "load multiple keybindings from toml":
    let registry = newKeyBindingRegistry()
    let tomlContent =
      """
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
    let testPath = "/tmp/test_keybind_multiple.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath)

    check registry.bindings[EditorMode.Normal].len == initialCount + 2

  test "skip keybinding with missing mode":
    let registry = newKeyBindingRegistry()
    let tomlContent =
      """
[[keybinding]]
key = "C-x"
command_type = "action"
command = "test.command"
"""
    let testPath = "/tmp/test_keybind_nomode.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath)

    # Should skip invalid binding
    check registry.bindings[EditorMode.Normal].len == initialCount

  test "skip keybinding with missing key":
    let registry = newKeyBindingRegistry()
    let tomlContent =
      """
[[keybinding]]
mode = "normal"
command_type = "action"
command = "test.command"
"""
    let testPath = "/tmp/test_keybind_nokey.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath)

    # Should skip invalid binding
    check registry.bindings[EditorMode.Normal].len == initialCount

  test "skip keybinding with invalid mode":
    let registry = newKeyBindingRegistry()
    let tomlContent =
      """
[[keybinding]]
mode = "invalid_mode"
key = "C-x"
command_type = "action"
command = "test.command"
"""
    let testPath = "/tmp/test_keybind_badmode.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath)

    # Should skip invalid binding
    check registry.bindings[EditorMode.Normal].len == initialCount

  test "default command type to action when not specified":
    let registry = newKeyBindingRegistry()
    let tomlContent =
      """
[[keybinding]]
mode = "normal"
key = "C-z"
command = "undo"
"""
    let testPath = "/tmp/test_keybind_default_type.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath)

    check registry.bindings[EditorMode.Normal].len == initialCount + 1
    let lastBinding = registry.bindings[EditorMode.Normal][^1]
    check lastBinding.command.kind == ctAction

  test "skip toml with no keybinding array":
    let registry = newKeyBindingRegistry()
    let tomlContent =
      """
[settings]
name = "test"
"""
    let testPath = "/tmp/test_keybind_no_array.toml"
    writeFile(testPath, tomlContent)
    defer:
      removeFile(testPath)

    let initialCount = registry.bindings[EditorMode.Normal].len
    registry.loadKeybindingsFromToml(testPath)

    # Should not crash and bindings should remain unchanged
    check registry.bindings[EditorMode.Normal].len == initialCount

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
