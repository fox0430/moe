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

import std/[unittest, options, tables]

import ../src/moepkg/keybind_config {.all.}
import ../src/moepkg/key_bindings
import ../src/moepkg/modes

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

  test "parse quickrun mode maps to Normal (backward compat)":
    check parseModes("quickrun") == @[EditorMode.Normal]

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
    check modes.len == 21 # All except CommandLine
    check EditorMode.Command notin modes
    check EditorMode.Normal in modes
    check EditorMode.Insert in modes
    check EditorMode.Visual in modes
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
    check parseModes("ALL").len == 21
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

  test "addKeySequenceMapping defaults to noremap":
    let registry = newKeyBindingRegistry()
    registry.addKeySequenceMapping(EditorMode.Insert, "jj", "Escape")

    check registry.runtimeMappings[EditorMode.Insert][^1].noremap

  test "addKeySequenceMapping with noremap = false is recursive":
    let registry = newKeyBindingRegistry()
    registry.addKeySequenceMapping(EditorMode.Normal, "x", "dd", noremap = false)

    let lastMapping = registry.runtimeMappings[EditorMode.Normal][^1]
    check lastMapping.kind == rmkKeySequence
    check not lastMapping.noremap

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
