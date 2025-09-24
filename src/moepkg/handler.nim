#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import std/options

import pkg/celina

import editor, commands, keybindings, commandregistry, modes

proc handleEvent*(e: Editor, event: Event) =
  if event.kind != EventKind.Key:
    return

  # Convert event to key combo
  let keyCombo = eventToKeyCombo(event)
  if keyCombo.isNone:
    return

  # Special handling for Insert mode
  if e.state.mode == EditorMode.Insert:
    # Check for mode switch keys first (like Escape)
    let binding = e.keyBindingRegistry.findBinding(e.state.mode, keyCombo.get)
    if binding.isSome:
      # Create command context
      let ctx = CommandContext(
        buffer: e.textBuffer,
        state: e.state,
        viewport: e.viewport,
        motionController: e.executer.motionController,
        keyBindingRegistry: e.keyBindingRegistry,
      )

      # Execute the bound command (e.g., switch to Normal mode)
      discard e.commandRegistry.executeCommand(ctx, binding.get)
      return

    # Handle regular character insertion in Insert mode
    if not keyCombo.get.isSpecial and keyCombo.get.modifiers == {}:
      # Insert the character
      let ctx = CommandContext(
        buffer: e.textBuffer,
        state: e.state,
        viewport: e.viewport,
        motionController: e.executer.motionController,
        keyBindingRegistry: e.keyBindingRegistry,
      )

      # Execute insert character command
      discard e.commandRegistry.execute(ctx, "insert.char", @[$keyCombo.get.char])
      return

    # Handle special keys in Insert mode
    if keyCombo.get.isSpecial:
      let ctx = CommandContext(
        buffer: e.textBuffer,
        state: e.state,
        viewport: e.viewport,
        motionController: e.executer.motionController,
        keyBindingRegistry: e.keyBindingRegistry,
      )

      case keyCombo.get.special
      of skBackspace:
        discard e.commandRegistry.execute(ctx, "insert.backspace")
      of skDelete:
        discard e.commandRegistry.execute(ctx, "insert.delete")
      of skEnter:
        discard e.commandRegistry.execute(ctx, "insert.newline")
      of skLeft:
        discard e.commandRegistry.execute(ctx, "motion.left")
      of skRight:
        discard e.commandRegistry.execute(ctx, "motion.right")
      of skUp:
        discard e.commandRegistry.execute(ctx, "motion.up")
      of skDown:
        discard e.commandRegistry.execute(ctx, "motion.down")
      of skHome:
        discard e.commandRegistry.execute(ctx, "motion.home")
      of skEnd:
        discard e.commandRegistry.execute(ctx, "motion.end")
      of skPageUp:
        discard e.commandRegistry.execute(ctx, "motion.pageup")
      of skPageDown:
        discard e.commandRegistry.execute(ctx, "motion.pagedown")
      else:
        discard # Ignore other special keys in Insert mode for now
      return

  # Normal handling for other modes
  let binding = e.keyBindingRegistry.findBinding(e.state.mode, keyCombo.get)
  if binding.isSome:
    # Create command context
    let ctx = CommandContext(
      buffer: e.textBuffer,
      state: e.state,
      viewport: e.viewport,
      motionController: e.executer.motionController,
      keyBindingRegistry: e.keyBindingRegistry,
    )

    # Execute the bound command
    discard e.commandRegistry.executeCommand(ctx, binding.get)
    return

  # No fallback needed - all keys should be handled through bindings
