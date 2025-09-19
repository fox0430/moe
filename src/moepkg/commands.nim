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

import std/strutils

import types, buffer, motion

type CommandExecutor* = ref object
  motionController*: MotionController
  buffer*: buffer.TextBuffer
  state*: EditorState
  viewport*: ViewPort

proc newCommandExecutor*(
    buffer: buffer.TextBuffer, state: EditorState, viewport: ViewPort
): CommandExecutor =
  CommandExecutor(
    motionController: newMotionController(buffer, state, viewport),
    buffer: buffer,
    state: state,
    viewport: viewport,
  )

proc execute*(e: CommandExecutor, command: string): bool =
  ## Execute a command string

  # Handle single character motion commands
  const repeatCount = 0
  if command.len == 1:
    let success = e.motionController.executeMotionKey(command[0], repeatCount)
    if success:
      e.state.command = ""
      return true

  # Handle motion: prefixed commands (from key bindings)
  if command.startsWith("motion:"):
    let motionType = command[7 ..^ 1]
    var motion: Motion
    case motionType
    of "left":
      motion = Motion.Left
    of "right":
      motion = Motion.Right
    of "up":
      motion = Motion.Up
    of "down":
      motion = Motion.Down
    of "pageup":
      motion = Motion.PageUp
    of "pagedown":
      motion = Motion.PageDown
    else:
      return false

    let cmd = MotionCommand(motion: motion, count: 1)
    let success = e.motionController.executeMotion(cmd)
    if success:
      e.state.command = ""
    return success

  # Unknown command
  return false

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
  discard exec.motionController.executeMotion(cmd)
