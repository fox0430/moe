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

## Diff Viewer mode command handler
##
## This module handles commands specific to Diff Viewer mode.
## Allows users to navigate and view diff output.
##
## Key bindings:
## - j/Down: Move selection down
## - k/Up: Move selection up
## - gg: Go to first line
## - G: Go to last line
## - Ctrl+d: Half page down
## - Ctrl+u: Half page up
## - q/Esc: Close diff viewer
## - :: Enter command mode

import ../[diff_viewer, key_bindings]
import handler_types
export handler_types

type
  DiffViewerResultKind* = enum
    dvrHandled # Command was handled successfully
    dvrEnterCommand # Enter command mode
    dvrQuit # Close diff viewer and return to previous mode
    dvrUnhandled # Command was not handled
    dvrError # Error occurred

  DiffViewerResult* = object
    case kind*: DiffViewerResultKind
    of dvrError:
      errorMessage*: string
    else:
      discard

proc handleDiffViewerModeKey*(
    dvState: DiffViewerState, viewportHeight: int, keyCombo: KeyCombo
): DiffViewerResult =
  ## Handle a key press in Diff Viewer mode
  ##
  ## Returns a DiffViewerResult indicating what action should be taken

  case dvState.handleListNavKey(viewportHeight, keyCombo)
  of lvaConsumed:
    DiffViewerResult(kind: dvrHandled)
  of lvaQuitKey, lvaEscape:
    DiffViewerResult(kind: dvrQuit)
  of lvaEnterCommand:
    DiffViewerResult(kind: dvrEnterCommand)
  of lvaSelect, lvaUnhandled:
    # The diff viewer has no selectable action; Enter and other keys are ignored.
    DiffViewerResult(kind: dvrUnhandled)
