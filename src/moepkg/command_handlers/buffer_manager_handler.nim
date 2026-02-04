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

  BufferManagerHandler* = ref object
    ## Handler for Buffer Manager mode specific commands
    waitingForG*: bool # Waiting for second 'g' for 'gg' command

proc newBufferManagerHandler*(): BufferManagerHandler =
  ## Create a new Buffer Manager mode handler
  BufferManagerHandler(waitingForG: false)

proc handleBufferManagerModeKey*(
    handler: BufferManagerHandler,
    bmState: BufferManagerState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): BufferManagerResult =
  ## Handle a key press in Buffer Manager mode
  ##
  ## Returns a BufferManagerResult indicating what action should be taken

  # Handle 'gg' command (two g presses)
  if handler.waitingForG:
    handler.waitingForG = false
    if not keyCombo.isSpecial and keyCombo.char == "g":
      bmState.selectedIndex = 0
      bmState.topLine = 0
      return BufferManagerResult(kind: bmrHandled)
    # If not 'g', fall through to normal handling

  # Escape key - quit buffer manager
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    return BufferManagerResult(kind: bmrQuit)

  # Check for special keys first
  if keyCombo.isSpecial:
    case keyCombo.special
    of skEnter:
      # Select the buffer
      let entry = bmState.getSelectedEntry()
      if entry.isSome:
        return BufferManagerResult(kind: bmrSelectBuffer, bufferIndex: entry.get.index)
      return BufferManagerResult(kind: bmrHandled)
    of skUp:
      bmState.moveUp()
      return BufferManagerResult(kind: bmrHandled)
    of skDown:
      bmState.moveDown()
      return BufferManagerResult(kind: bmrHandled)
    else:
      discard
  else:
    # Character keys
    # Check for Ctrl+d (half page down)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "d":
      let halfPage = max(1, viewportHeight div 2)
      for i in 0 ..< halfPage:
        bmState.moveDown()
      return BufferManagerResult(kind: bmrHandled)

    # Check for Ctrl+u (half page up)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "u":
      let halfPage = max(1, viewportHeight div 2)
      for i in 0 ..< halfPage:
        bmState.moveUp()
      return BufferManagerResult(kind: bmrHandled)

    # Check for Ctrl+k (next window)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "k":
      # This will be handled by the editor to switch windows
      return BufferManagerResult(kind: bmrUnhandled)

    # Check for Ctrl+j (prev window)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "j":
      # This will be handled by the editor to switch windows
      return BufferManagerResult(kind: bmrUnhandled)

    case keyCombo.char
    of ":":
      return BufferManagerResult(kind: bmrEnterCommand)
    of "q":
      return BufferManagerResult(kind: bmrQuit)
    of "j":
      bmState.moveDown()
      return BufferManagerResult(kind: bmrHandled)
    of "k":
      bmState.moveUp()
      return BufferManagerResult(kind: bmrHandled)
    of "g":
      # Start waiting for second 'g'
      handler.waitingForG = true
      return BufferManagerResult(kind: bmrHandled)
    of "G":
      bmState.selectedIndex = max(0, bmState.entries.len - 1)
      return BufferManagerResult(kind: bmrHandled)
    of "o":
      # Open in new window (same as Enter for now)
      let entry = bmState.getSelectedEntry()
      if entry.isSome:
        return BufferManagerResult(kind: bmrSelectBuffer, bufferIndex: entry.get.index)
      return BufferManagerResult(kind: bmrHandled)
    of "D":
      # Delete the selected buffer
      let entry = bmState.getSelectedEntry()
      if entry.isSome:
        return
          BufferManagerResult(kind: bmrDeleteBuffer, deleteBufferIndex: entry.get.index)
      return BufferManagerResult(kind: bmrHandled)
    else:
      discard

  return BufferManagerResult(kind: bmrUnhandled)
