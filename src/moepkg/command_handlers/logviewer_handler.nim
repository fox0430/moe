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

## Log viewer mode command handler
##
## This module handles commands specific to Log Viewer mode.
## The log viewer displays editor messages and LSP logs.

import std/options

import ../[types, keybindings, logviewer]

type
  LogViewerResultKind* = enum
    lvrHandled # Command was handled successfully
    lvrEnterCommand # Enter command mode
    lvrQuit # Close log viewer and return to previous mode
    lvrUnhandled # Command was not handled
    lvrError # Error occurred

  LogViewerResult* = object
    case kind*: LogViewerResultKind
    of lvrError:
      errorMessage*: string
    else:
      discard

  LogViewerHandler* = ref object ## Handler for Log Viewer mode specific commands
    waitingForG*: bool # Waiting for second 'g' for 'gg' command

proc newLogViewerHandler*(): LogViewerHandler =
  ## Create a new Log Viewer mode handler
  LogViewerHandler(waitingForG: false)

proc handleLogViewerModeKey*(
    handler: LogViewerHandler,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): LogViewerResult =
  ## Handle a key press in Log Viewer mode
  ##
  ## Returns a LogViewerResult indicating what action should be taken

  if state.logViewerState.isNone:
    return
      LogViewerResult(kind: lvrError, errorMessage: "Log viewer state not initialized")

  let logState = state.logViewerState.get

  # Handle 'gg' command (two g presses)
  if handler.waitingForG:
    handler.waitingForG = false
    if not keyCombo.isSpecial and keyCombo.char == "g":
      logState.moveToFirst()
      return LogViewerResult(kind: lvrHandled)
    # If not 'g', fall through to normal handling

  # Escape or q to quit
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    return LogViewerResult(kind: lvrQuit)

  # Check for special keys first
  if keyCombo.isSpecial:
    case keyCombo.special
    of skUp:
      logState.moveUp()
      logState.ensureSelectedVisible(viewportHeight)
      return LogViewerResult(kind: lvrHandled)
    of skDown:
      logState.moveDown()
      logState.ensureSelectedVisible(viewportHeight)
      return LogViewerResult(kind: lvrHandled)
    else:
      discard
  else:
    # Character keys
    # Check for Ctrl+d (half page down)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "d":
      logState.halfPageDown(viewportHeight)
      return LogViewerResult(kind: lvrHandled)

    # Check for Ctrl+u (half page up)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "u":
      logState.halfPageUp(viewportHeight)
      return LogViewerResult(kind: lvrHandled)

    case keyCombo.char
    of ":":
      return LogViewerResult(kind: lvrEnterCommand)
    of "q":
      return LogViewerResult(kind: lvrQuit)
    of "j":
      logState.moveDown()
      logState.ensureSelectedVisible(viewportHeight)
      return LogViewerResult(kind: lvrHandled)
    of "k":
      logState.moveUp()
      logState.ensureSelectedVisible(viewportHeight)
      return LogViewerResult(kind: lvrHandled)
    of "g":
      # Start waiting for second 'g'
      handler.waitingForG = true
      return LogViewerResult(kind: lvrHandled)
    of "G":
      logState.moveToLast()
      logState.ensureSelectedVisible(viewportHeight)
      return LogViewerResult(kind: lvrHandled)
    else:
      discard

  return LogViewerResult(kind: lvrUnhandled)
