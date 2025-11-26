import unittest
import std/[options, tables]
import pkg/results

import ../src/moepkg/buffer
import ../src/moepkg/cursor
import ../src/moepkg/types
import ../src/moepkg/keybindings
import ../src/moepkg/commandregistry
import ../src/moepkg/commands
import ../src/moepkg/modes

suite "Undo/Redo keybinding tests":
  test "Undo command is registered":
    let keyRegistry = newKeyBindingRegistry()
    keyRegistry.setupDefaultBindings()

    # Check that undo command is registered
    check keyRegistry.commandRegistry.hasKey("undo")
    let undoCmd = keyRegistry.commandRegistry["undo"]
    check undoCmd.name == "undo"
    check undoCmd.kind == ctAction
    check undoCmd.commandId == "edit.undo"

  test "Redo command is registered":
    let keyRegistry = newKeyBindingRegistry()
    keyRegistry.setupDefaultBindings()

    # Check that redo command is registered
    check keyRegistry.commandRegistry.hasKey("redo")
    let redoCmd = keyRegistry.commandRegistry["redo"]
    check redoCmd.name == "redo"
    check redoCmd.kind == ctAction
    check redoCmd.commandId == "edit.redo"

  test "Undo keybinding 'u' is registered for Normal mode":
    let keyRegistry = newKeyBindingRegistry()
    keyRegistry.setupDefaultBindings()

    # Check that 'u' is bound to undo in Normal mode
    let uKey = toKeyCombo('u')
    let binding = keyRegistry.findBinding(EditorMode.Normal, uKey)
    check binding.isSome
    check binding.get.name == "undo"

  test "Redo keybinding 'Ctrl-r' is registered for Normal mode":
    let keyRegistry = newKeyBindingRegistry()
    keyRegistry.setupDefaultBindings()

    # Check that 'Ctrl-r' is bound to redo in Normal mode
    let ctrlR = toKeyCombo('r', ctrl = true)
    let binding = keyRegistry.findBinding(EditorMode.Normal, ctrlR)
    check binding.isSome
    check binding.get.name == "redo"

  test "Buffer undo/redo works directly":
    # Test undo/redo at buffer level (command execution requires complex setup)
    var buf = newTextBuffer("Hello")

    # Make a change
    discard buf.insertText(BufferPosition(line: 0, column: 5), " World")
    check buf.getTextString() == "Hello World"

    # Undo
    let undoResult = buf.undo()
    check undoResult.isOk
    check buf.getTextString() == "Hello"

    # Redo
    let redoResult = buf.redo()
    check redoResult.isOk
    check buf.getTextString() == "Hello World"
