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

## Buffer Manager mode command handler
##
## This module handles commands specific to Buffer Manager mode.
## Allows users to view and switch between open buffers.

import std/options

import ../[types, buffer_manager, key_bindings]
import handler_types
export handler_types

type
  BufferManagerResultKind* = enum
    bmrHandled # Command was handled successfully
    bmrSelectBuffer # Select and switch to a buffer
    bmrDeleteBuffer # Delete the selected buffer
    bmrEnterCommand # Enter command mode
    bmrQuit # Close buffer manager and return to previous mode
    bmrUnhandled # Command was not handled
    bmrError # Error occurred

  BufferManagerResult* = object
    case kind*: BufferManagerResultKind
    of bmrSelectBuffer:
      bufferIndex*: int
    of bmrDeleteBuffer:
      deleteBufferIndex*: int
    of bmrError:
      errorMessage*: string
    else:
      discard

proc handleBufferManagerModeKey*(
    bmState: BufferManagerState, viewportHeight: int, keyCombo: KeyCombo
): BufferManagerResult =
  ## Handle a key press in Buffer Manager mode
  ##
  ## Returns a BufferManagerResult indicating what action should be taken

  # Ctrl-k / Ctrl-j switch windows; the editor handles them. Cancel any pending
  # 'gg' first, since this early return bypasses handleListNavKey (the only place
  # that would otherwise clear waitingForG).
  if not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
      (keyCombo.char == "k" or keyCombo.char == "j"):
    bmState.waitingForG = false
    return BufferManagerResult(kind: bmrUnhandled)

  case bmState.handleListNavKey(viewportHeight, keyCombo)
  of lvaConsumed:
    return BufferManagerResult(kind: bmrHandled)
  of lvaQuitKey, lvaEscape:
    return BufferManagerResult(kind: bmrQuit)
  of lvaEnterCommand:
    return BufferManagerResult(kind: bmrEnterCommand)
  of lvaSelect:
    # Select and switch to the buffer
    let entry = bmState.getSelectedItem()
    if entry.isSome:
      return BufferManagerResult(kind: bmrSelectBuffer, bufferIndex: entry.get.index)
    return BufferManagerResult(kind: bmrHandled)
  of lvaUnhandled:
    discard # fall through to buffer-manager-specific keys

  if not keyCombo.isSpecial:
    case keyCombo.char
    of "o":
      # Open the selected buffer (same as Enter for now)
      let entry = bmState.getSelectedItem()
      if entry.isSome:
        return BufferManagerResult(kind: bmrSelectBuffer, bufferIndex: entry.get.index)
      return BufferManagerResult(kind: bmrHandled)
    of "D":
      # Delete the selected buffer
      let entry = bmState.getSelectedItem()
      if entry.isSome:
        return
          BufferManagerResult(kind: bmrDeleteBuffer, deleteBufferIndex: entry.get.index)
      return BufferManagerResult(kind: bmrHandled)
    else:
      discard

  return BufferManagerResult(kind: bmrUnhandled)
