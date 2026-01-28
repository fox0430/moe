import unittest
import std/[options, tables]

import ../src/moepkg/keybindings
import ../src/moepkg/modes

suite "Undo/Redo keybinding tests":
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
