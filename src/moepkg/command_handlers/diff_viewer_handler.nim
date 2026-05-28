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

  # Handle 'gg' command (two g presses)
  if dvState.waitingForG:
    dvState.waitingForG = false
    if not keyCombo.isSpecial and keyCombo.char == "g":
      dvState.moveToFirst()
      return DiffViewerResult(kind: dvrHandled)
    # If not 'g', fall through to normal handling

  # Escape key - quit diff viewer
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    return DiffViewerResult(kind: dvrQuit)

  # Check for special keys first
  if keyCombo.isSpecial:
    case keyCombo.special
    of skUp:
      dvState.moveUp()
      return DiffViewerResult(kind: dvrHandled)
    of skDown:
      dvState.moveDown()
      return DiffViewerResult(kind: dvrHandled)
    else:
      discard
  else:
    # Character keys
    # Check for Ctrl+d (half page down)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "d":
      let halfPage = max(1, viewportHeight div 2)
      for i in 0 ..< halfPage:
        dvState.moveDown()
      return DiffViewerResult(kind: dvrHandled)

    # Check for Ctrl+u (half page up)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "u":
      let halfPage = max(1, viewportHeight div 2)
      for i in 0 ..< halfPage:
        dvState.moveUp()
      return DiffViewerResult(kind: dvrHandled)

    case keyCombo.char
    of ":":
      return DiffViewerResult(kind: dvrEnterCommand)
    of "q":
      return DiffViewerResult(kind: dvrQuit)
    of "j":
      dvState.moveDown()
      return DiffViewerResult(kind: dvrHandled)
    of "k":
      dvState.moveUp()
      return DiffViewerResult(kind: dvrHandled)
    of "g":
      # Start waiting for second 'g'
      dvState.waitingForG = true
      return DiffViewerResult(kind: dvrHandled)
    of "G":
      dvState.moveToLast()
      return DiffViewerResult(kind: dvrHandled)
    else:
      discard

  return DiffViewerResult(kind: dvrUnhandled)
