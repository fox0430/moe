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

import types, buffer, motion, command_registry, key_bindings, config

type CommandExecutor* = ref object
  motionController*: MotionController
  state*: EditorState
  commandRegistry*: CommandRegistry
  keyBindingRegistry*: KeyBindingRegistry
  clipboardConfig*: ClipboardConfig
  notificationConfig*: NotificationConfig

proc buffer*(e: CommandExecutor): buffer.TextBuffer {.inline.} =
  ## Buffer forwarded to the motion controller (single internal source of truth).
  e.motionController.executor.buffer

proc viewport*(e: CommandExecutor): ViewPort {.inline.} =
  ## Viewport forwarded to the motion controller (single internal source of truth).
  e.motionController.viewportManager.viewport

proc cursor*(e: CommandExecutor): var BufferPosition {.inline.} =
  ## Cursor position forwarded to EditorState (which delegates to activeWindow)
  e.state.cursor

proc `cursor=`*(e: CommandExecutor, pos: BufferPosition) {.inline.} =
  e.state.cursor = pos

proc setBuffer*(e: CommandExecutor, b: buffer.TextBuffer) {.inline.} =
  ## Point the executor's motion controller at `b`. `buffer` derives from this.
  e.motionController.executor.buffer = b

proc bindToWindow*(e: CommandExecutor, win: EditorWindow) =
  ## Bind this executor's motion controller to `win`'s buffer/viewport.
  ## Single place that re-aliases the per-window state the executor caches,
  ## so window switch / split / close / resize only update one method.
  e.setBuffer(win.buffer)
  e.motionController.viewportManager.viewport = win.viewport
  e.motionController.viewportManager.wrapCountCache = win.wrapCountCache

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
    state: state,
    commandRegistry: cmdReg,
    keyBindingRegistry: keyReg,
    clipboardConfig: clipboardConfig,
    notificationConfig: notificationConfig,
  )

proc execute*(e: CommandExecutor, command: string): Result[(), string] =
  ## Execute a command string through the command registry
  let ctx = CommandContext(
    buffer: e.buffer,
    state: e.state,
    viewport: e.viewport,
    motionController: e.motionController,
    keyBindingRegistry: nil,
    clipboardConfig: e.clipboardConfig,
    notificationConfig: e.notificationConfig,
  )

  let r = e.commandRegistry.execute(ctx, command)
  if r.isOk:
    e.state.pendingCommand = PendingNone
    e.state.input.commandText = ""
    e.state.input.commandCursor = 0

  return r

proc executeKeybinding*(
    e: CommandExecutor, binding: key_bindings.Command
): Result[(), string] =
  ## Execute a keybinding command
  let ctx = CommandContext(
    buffer: e.buffer,
    state: e.state,
    viewport: e.viewport,
    motionController: e.motionController,
    keyBindingRegistry: nil,
    clipboardConfig: e.clipboardConfig,
    notificationConfig: e.notificationConfig,
  )

  return e.commandRegistry.executeCommand(ctx, binding)

# Compatibility methods for existing code
proc executeMotion*(exec: CommandExecutor, motion: Motion, count: int = 1) =
  ## Compatibility wrapper for direct motion execution
  let cmd = MotionCommand(motion: motion, count: count)
  let r = exec.motionController.executeMotion(cmd, exec.cursor)
  if r.isOk:
    exec.cursor = r.value
