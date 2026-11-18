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
import handler_types
export handler_types

type
  HelpViewerResultKind* = enum
    hvrHandled # Command was handled successfully
    hvrEnterCommand # Enter command mode
    hvrEnterSearch # Enter search mode (forward)
    hvrEnterSearchBackward # Enter search mode (backward)
    hvrRepeatSearch # n, or N when `reverse`
    hvrClearSearchHighlight # Clear search highlight (double-Escape)
    hvrQuit # Close help viewer and return to previous mode
    hvrUnhandled # Command was not handled
    hvrError # Error occurred

  HelpViewerResult* = object
    case kind*: HelpViewerResultKind
    of hvrError:
      errorMessage*: string
    of hvrRepeatSearch:
      reverse*: bool
    else:
      discard

proc handleHelpViewerModeKey*(
    helpState: HelpViewerState, viewportHeight: int, keyCombo: KeyCombo
): HelpViewerResult =
  ## Handle a key press in Help Viewer mode
  ##
  ## Returns a HelpViewerResult indicating what action should be taken

  # Escape is taken before the shared handler: here it means "clear the search
  # highlight on the second press", not the shared `lvaEscape` = quit.
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    helpState.waitingForG = false
    if helpState.lastKeyWasEscape:
      helpState.lastKeyWasEscape = false
      return HelpViewerResult(kind: hvrClearSearchHighlight)
    helpState.lastKeyWasEscape = true
    return HelpViewerResult(kind: hvrHandled)

  helpState.lastKeyWasEscape = false

  case helpState.handleListNavKey(viewportHeight, keyCombo)
  of lvaConsumed, lvaEscape:
    return HelpViewerResult(kind: hvrHandled)
  of lvaQuitKey:
    return HelpViewerResult(kind: hvrQuit)
  of lvaEnterCommand:
    return HelpViewerResult(kind: hvrEnterCommand)
  of lvaSelect, lvaUnhandled:
    # Help has no selectable action; Enter falls through so caller-level
    # bindings still reach the router.
    discard

  if keyCombo.isSpecial:
    return HelpViewerResult(kind: hvrUnhandled)

  case keyCombo.char
  of "/":
    return HelpViewerResult(kind: hvrEnterSearch)
  of "?":
    return HelpViewerResult(kind: hvrEnterSearchBackward)
  of "n", "N":
    return HelpViewerResult(kind: hvrRepeatSearch, reverse: keyCombo.char == "N")
  of "}":
    helpState.moveToNextSection()
    return HelpViewerResult(kind: hvrHandled)
  of "{":
    helpState.moveToPreviousSection()
    return HelpViewerResult(kind: hvrHandled)
  else:
    return HelpViewerResult(kind: hvrUnhandled)
