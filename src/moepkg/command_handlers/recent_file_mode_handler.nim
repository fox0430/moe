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

## Recent File Mode handler
##
## This module handles key input for Recent File selection mode.
## Supported keys:
## - j/Down: Move selection down
## - k/Up: Move selection up
## - h/l/Left/Right/Backspace: No-op (for vim compatibility)
## - G: Move to last file
## - gg: Move to first file
## - Enter: Open selected file
## - : Enter command mode

import std/options

import ../[modes, key_bindings, recent_file_mode]
import handler_types
export handler_types

type
  RecentFileModeResultKind* = enum
    rfmrHandled # Key was handled
    rfmrOpenFile # Open selected file
    rfmrEnterCommand # Enter command mode
    rfmrUnhandled # Key was not handled
    rfmrError # Error occurred

  RecentFileModeResult* = object
    case kind*: RecentFileModeResultKind
    of rfmrOpenFile:
      filePath*: string
    of rfmrError:
      errorMessage*: string
    of rfmrHandled, rfmrEnterCommand, rfmrUnhandled:
      discard
    modeTransition*: Option[EditorMode]
    overlayTransition*: Option[OverlayKind]

proc handleRecentFileModeKey*(
    state: RecentFileModeState, viewportHeight: int, keyCombo: KeyCombo
): RecentFileModeResult =
  ## Handle a key press in Recent File mode

  # Shared list navigation (gg/G/j/k/Up/Down/Ctrl-d/Ctrl-u).
  case state.handleListNavKey(viewportHeight, keyCombo)
  of lvaConsumed:
    return RecentFileModeResult(kind: rfmrHandled, modeTransition: none(EditorMode))
  of lvaQuitKey, lvaEscape:
    # Recent file mode has no quit key of its own; q/Escape are passed through.
    return RecentFileModeResult(kind: rfmrUnhandled, modeTransition: none(EditorMode))
  of lvaEnterCommand:
    return
      RecentFileModeResult(kind: rfmrEnterCommand, overlayTransition: some(okCommand))
  of lvaSelect:
    let selectedFile = state.getSelectedPath()
    if selectedFile.isSome:
      return RecentFileModeResult(
        kind: rfmrOpenFile,
        filePath: selectedFile.get,
        modeTransition: some(EditorMode.Normal),
      )
    else:
      return RecentFileModeResult(
        kind: rfmrError,
        errorMessage: "No file selected",
        modeTransition: none(EditorMode),
      )
  of lvaUnhandled:
    discard # fall through to recent-file-specific keys

  # h/l/Left/Right/Backspace are no-ops for vim compatibility.
  if keyCombo.isSpecial:
    case keyCombo.special
    of skLeft, skRight, skBackspace:
      return RecentFileModeResult(kind: rfmrHandled, modeTransition: none(EditorMode))
    else:
      return RecentFileModeResult(kind: rfmrUnhandled, modeTransition: none(EditorMode))

  case keyCombo.char
  of "h", "l":
    return RecentFileModeResult(kind: rfmrHandled, modeTransition: none(EditorMode))
  else:
    return RecentFileModeResult(kind: rfmrUnhandled, modeTransition: none(EditorMode))
