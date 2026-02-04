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

## Help viewer mode command handler
##
## This module handles commands specific to Help Viewer mode.
## The help viewer displays editor help information.

import ../[key_bindings, help_viewer]

type
  HelpViewerResultKind* = enum
    hvrHandled # Command was handled successfully
    hvrEnterCommand # Enter command mode
    hvrEnterSearch # Enter search mode (forward)
    hvrEnterSearchBackward # Enter search mode (backward)
    hvrQuit # Close help viewer and return to previous mode
    hvrUnhandled # Command was not handled
    hvrError # Error occurred

  HelpViewerResult* = object
    case kind*: HelpViewerResultKind
    of hvrError:
      errorMessage*: string
    else:
      discard

  HelpViewerHandler* = ref object ## Handler for Help Viewer mode specific commands
    waitingForG*: bool # Waiting for second 'g' for 'gg' command

proc newHelpViewerHandler*(): HelpViewerHandler =
  ## Create a new Help Viewer mode handler
  HelpViewerHandler(waitingForG: false)

proc handleHelpViewerModeKey*(
    handler: HelpViewerHandler,
    helpState: HelpViewerState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HelpViewerResult =
  ## Handle a key press in Help Viewer mode
  ##
  ## Returns a HelpViewerResult indicating what action should be taken

  # Handle 'gg' command (two g presses)
  if handler.waitingForG:
    handler.waitingForG = false
    if not keyCombo.isSpecial and keyCombo.char == "g":
      helpState.moveToFirst()
      return HelpViewerResult(kind: hvrHandled)
    else:
      # If not 'g', cancel and discard this input to avoid double processing
      return HelpViewerResult(kind: hvrUnhandled)

  # Check for special keys first
  if keyCombo.isSpecial:
    case keyCombo.special
    of skUp:
      helpState.moveUp()
      helpState.ensureSelectedVisible(viewportHeight)
      return HelpViewerResult(kind: hvrHandled)
    of skDown:
      helpState.moveDown()
      helpState.ensureSelectedVisible(viewportHeight)
      return HelpViewerResult(kind: hvrHandled)
    else:
      discard
  else:
    # Character keys
    # Check for Ctrl+d (half page down)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "d":
      helpState.halfPageDown(viewportHeight)
      return HelpViewerResult(kind: hvrHandled)

    # Check for Ctrl+u (half page up)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "u":
      helpState.halfPageUp(viewportHeight)
      return HelpViewerResult(kind: hvrHandled)

    case keyCombo.char
    of ":":
      return HelpViewerResult(kind: hvrEnterCommand)
    of "/":
      return HelpViewerResult(kind: hvrEnterSearch)
    of "?":
      return HelpViewerResult(kind: hvrEnterSearchBackward)
    of "n":
      # Search forward for next match
      discard helpState.searchForward()
      helpState.ensureSelectedVisible(viewportHeight)
      return HelpViewerResult(kind: hvrHandled)
    of "N":
      # Search backward for previous match
      discard helpState.searchBackward()
      helpState.ensureSelectedVisible(viewportHeight)
      return HelpViewerResult(kind: hvrHandled)
    of "j":
      helpState.moveDown()
      helpState.ensureSelectedVisible(viewportHeight)
      return HelpViewerResult(kind: hvrHandled)
    of "k":
      helpState.moveUp()
      helpState.ensureSelectedVisible(viewportHeight)
      return HelpViewerResult(kind: hvrHandled)
    of "g":
      # Start waiting for second 'g'
      handler.waitingForG = true
      return HelpViewerResult(kind: hvrHandled)
    of "G":
      helpState.moveToLast()
      helpState.ensureSelectedVisible(viewportHeight)
      return HelpViewerResult(kind: hvrHandled)
    else:
      discard

  return HelpViewerResult(kind: hvrUnhandled)
