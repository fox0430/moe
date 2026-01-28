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

import std/options

import pkg/results

import types, buffer, motion, commandregistry, keybindings, config

type CommandExecutor* = ref object
  motionController*: MotionController
  buffer*: buffer.TextBuffer
  state*: EditorState
  viewport*: ViewPort
  commandRegistry*: CommandRegistry
  keyBindingRegistry*: KeyBindingRegistry
  clipboardConfig*: ClipboardConfig
  notificationConfig*: NotificationConfig

proc newCommandExecutor*(
    buffer: buffer.TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    clipboardConfig: ClipboardConfig = ClipboardConfig(enable: false, tool: cbtXclip),
    notificationConfig: NotificationConfig = NotificationConfig(),
    commandRegistry: Option[CommandRegistry] = none(CommandRegistry),
    keyBindingRegistry: Option[KeyBindingRegistry] = none(KeyBindingRegistry),
): CommandExecutor =
  let cmdReg =
    if commandRegistry.isSome:
      commandRegistry.get
    else:
      newCommandRegistry()
  let keyReg =
    if keyBindingRegistry.isSome:
      keyBindingRegistry.get
    else:
      newKeyBindingRegistry()

  # Register built-in commands if using new registry
  if commandRegistry.isNone:
    cmdReg.registerBuiltinCommands

  # Setup default key bindings if using new registry
  if keyBindingRegistry.isNone:
    keyReg.setupDefaultBindings

  CommandExecutor(
    motionController: newMotionController(buffer, state, viewport),
    buffer: buffer,
    state: state,
    viewport: viewport,
    commandRegistry: cmdReg,
    keyBindingRegistry: keyReg,
    clipboardConfig: clipboardConfig,
    notificationConfig: notificationConfig,
  )

proc execute*(e: CommandExecutor, command: string): Result[(), string] =
  ## Execute a command string through the command registry

  # Create command context
  let ctx = CommandContext(
    buffer: e.buffer,
    state: e.state,
    viewport: e.viewport,
    motionController: e.motionController,
    keyBindingRegistry: nil, # Not available in this context
    clipboardConfig: e.clipboardConfig,
    notificationConfig: e.notificationConfig,
  )

  # Execute through command registry (handles both commands and aliases)
  let r = e.commandRegistry.execute(ctx, command)
  if r.isOk:
    # Clear command buffer on success
    e.state.command = ""

  return r

proc executeKeybinding*(
    e: CommandExecutor, binding: keybindings.Command
): Result[(), string] =
  ## Execute a keybinding command
  let ctx = CommandContext(
    buffer: e.buffer,
    state: e.state,
    viewport: e.viewport,
    motionController: e.motionController,
    keyBindingRegistry: nil, # Not available in this context
    clipboardConfig: e.clipboardConfig,
    notificationConfig: e.notificationConfig,
  )

  return e.commandRegistry.executeCommand(ctx, binding)

# Compatibility methods for existing code
proc clampCursor*(exec: CommandExecutor) =
  ## Compatibility wrapper - cursor is now managed by motion system
  discard

proc updateViewport*(exec: CommandExecutor) =
  ## Compatibility wrapper - viewport is now managed by motion system
  discard

proc executeMotion*(exec: CommandExecutor, motion: Motion, count: int = 1) =
  ## Compatibility wrapper for direct motion execution
  let cmd = MotionCommand(motion: motion, count: count)
  let r = exec.motionController.executeMotion(cmd, exec.state.cursor)
  if r.isOk:
    exec.state.cursor = r.value
