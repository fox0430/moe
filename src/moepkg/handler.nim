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

import editor, commands, keybindings, commandregistry

proc handleEvent*(e: Editor, event: Event) =
  if event.kind != EventKind.Key:
    return

  # Convert event to key combo
  let keyCombo = eventToKeyCombo(event)
  if keyCombo.isNone:
    return

  # Find binding for current mode
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
