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

import std/options

import ../[keybindings, types, debugviewer]

type
  DebugViewerResultKind* = enum
    dvrHandled # Command was handled successfully
    dvrEnterCommand # Enter command mode
    dvrQuit # Close debug viewer and return to previous mode
    dvrUnhandled # Command was not handled
    dvrError # Error occurred

  DebugViewerResult* = object
    case kind*: DebugViewerResultKind
    of dvrError:
      errorMessage*: string
    else:
      discard

  DebugViewerHandler* = ref object ## Handler for Debug Viewer mode specific commands
    discard

proc newDebugViewerHandler*(): DebugViewerHandler =
  ## Create a new Debug Viewer mode handler
  DebugViewerHandler()

proc handleDebugModeKey*(
    state: EditorState, viewportHeight: int, keyCombo: KeyCombo
): DebugViewerResult =
  ## Handle key press in Debug mode
  ##
  ## Key bindings:
  ## - Escape, q: Exit debug mode
  ## - j, Down: Scroll down
  ## - k, Up: Scroll up
  ## - g, Home: Go to top
  ## - G, End: Go to bottom
  ## - Ctrl+d: Page down
  ## - Ctrl+u: Page up
  ## - :: Enter command mode

  if state.debugViewerState.isNone:
    return DebugViewerResult(kind: dvrQuit)

  var debugState = state.debugViewerState.get

  # Handle special keys
  if keyCombo.isSpecial:
    case keyCombo.special
    of skEscape:
      # ESC does nothing in debug mode (use q to quit)
      return DebugViewerResult(kind: dvrHandled)
    of skDown:
      debugState.scrollDown(viewportHeight)
      return DebugViewerResult(kind: dvrHandled)
    of skUp:
      debugState.scrollUp()
      return DebugViewerResult(kind: dvrHandled)
    of skHome:
      debugState.scrollToTop()
      return DebugViewerResult(kind: dvrHandled)
    of skEnd:
      debugState.scrollToBottom(viewportHeight)
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
    of "q":
      return DebugViewerResult(kind: dvrQuit)
    of "j":
      debugState.scrollDown(viewportHeight)
      return DebugViewerResult(kind: dvrHandled)
    of "k":
      debugState.scrollUp()
      return DebugViewerResult(kind: dvrHandled)
    of "g":
      debugState.scrollToTop()
      return DebugViewerResult(kind: dvrHandled)
    of "G":
      debugState.scrollToBottom(viewportHeight)
      return DebugViewerResult(kind: dvrHandled)
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
