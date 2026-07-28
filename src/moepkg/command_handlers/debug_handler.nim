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

## Debug mode handler
##
## This module handles key events in Debug mode.

import ../[key_bindings, debug_viewer]
import handler_types
export handler_types

type
  DebugViewerResultKind* = enum
    dvrHandled # Command was handled successfully
    dvrQuit # Close the debug viewer
    dvrEnterCommand # Enter command mode
    dvrUnhandled # Command was not handled
    dvrError # Error occurred

  DebugViewerResult* = object
    case kind*: DebugViewerResultKind
    of dvrError:
      errorMessage*: string
    else:
      discard

proc handleDebugModeKey*(
    debugState: DebugViewerState, viewportHeight: int, keyCombo: KeyCombo
): DebugViewerResult =
  ## Handle key press in Debug mode
  ##
  ## Key bindings:
  ## - j, Down: Scroll down
  ## - k, Up: Scroll up
  ## - g, Home: Go to top
  ## - G, End: Go to bottom
  ## - Ctrl+d: Page down
  ## - Ctrl+u: Page up
  ## - q: Close the viewer
  ## - :: Enter command mode

  # Handle special keys
  if keyCombo.isSpecial:
    case keyCombo.special
    of skEscape:
      # ESC does nothing in debug mode (use q to quit)
      return DebugViewerResult(kind: dvrHandled)
    of skDown:
      debugState.moveDown()
      return DebugViewerResult(kind: dvrHandled)
    of skUp:
      debugState.moveUp()
      return DebugViewerResult(kind: dvrHandled)
    of skHome:
      debugState.moveToFirst()
      return DebugViewerResult(kind: dvrHandled)
    of skEnd:
      debugState.moveToLast()
      return DebugViewerResult(kind: dvrHandled)
    of skPageDown:
      debugState.pageDown(viewportHeight)
      return DebugViewerResult(kind: dvrHandled)
    of skPageUp:
      debugState.pageUp(viewportHeight)
      return DebugViewerResult(kind: dvrHandled)
    else:
      return DebugViewerResult(kind: dvrHandled)

  # Handle character keys
  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    case keyCombo.char
    of "j":
      debugState.moveDown()
      return DebugViewerResult(kind: dvrHandled)
    of "k":
      debugState.moveUp()
      return DebugViewerResult(kind: dvrHandled)
    of "g":
      debugState.moveToFirst()
      return DebugViewerResult(kind: dvrHandled)
    of "G":
      debugState.moveToLast()
      return DebugViewerResult(kind: dvrHandled)
    of "q":
      return DebugViewerResult(kind: dvrQuit)
    of ":":
      return DebugViewerResult(kind: dvrEnterCommand)
    else:
      return DebugViewerResult(kind: dvrHandled)

  # Handle Ctrl+d and Ctrl+u
  if not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers:
    case keyCombo.char
    of "d":
      debugState.pageDown(viewportHeight)
      return DebugViewerResult(kind: dvrHandled)
    of "u":
      debugState.pageUp(viewportHeight)
      return DebugViewerResult(kind: dvrHandled)
    else:
      return DebugViewerResult(kind: dvrHandled)

  return DebugViewerResult(kind: dvrHandled)
