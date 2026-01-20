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
## - :: Enter command mode
## - Esc: Quit recent file mode
## - Ctrl-K: Move to next window
## - Ctrl-J: Move to previous window

import std/options

import ../[modes, keybindings, recentfilemode]

type
  RecentFileModeResultKind* = enum
    rfmrHandled # Key was handled
    rfmrOpenFile # Open selected file
    rfmrEnterCommand # Enter command mode
    rfmrQuit # Quit recent file mode
    rfmrNextWindow # Move to next window (Ctrl-K)
    rfmrPrevWindow # Move to previous window (Ctrl-J)
    rfmrUnhandled # Key was not handled
    rfmrError # Error occurred

  RecentFileModeResult* = object
    case kind*: RecentFileModeResultKind
    of rfmrOpenFile:
      filePath*: string
    of rfmrError:
      errorMessage*: string
    of rfmrHandled, rfmrEnterCommand, rfmrQuit, rfmrNextWindow, rfmrPrevWindow,
        rfmrUnhandled:
      discard
    modeTransition*: Option[EditorMode]

  RecentFileModeHandler* = ref object
    waitingForG*: bool # Waiting for second 'g' in 'gg' command

proc newRecentFileModeHandler*(): RecentFileModeHandler =
  ## Create a new Recent File mode handler
  RecentFileModeHandler(waitingForG: false)

proc handleRecentFileModeKey*(
    handler: RecentFileModeHandler,
    state: RecentFileModeState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): RecentFileModeResult =
  ## Handle a key press in Recent File mode

  # Handle 'gg' command (second g)
  if handler.waitingForG:
    handler.waitingForG = false
    if not keyCombo.isSpecial and keyCombo.char == "g":
      state.moveToFirst()
      return RecentFileModeResult(kind: rfmrHandled, modeTransition: none(EditorMode))
    # If not 'g', fall through to handle as normal key

  # Handle special keys
  if keyCombo.isSpecial:
    case keyCombo.special
    of skEscape:
      return
        RecentFileModeResult(kind: rfmrQuit, modeTransition: some(EditorMode.Normal))
    of skEnter:
      let selectedFile = state.selectedFile()
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
    of skUp:
      state.moveUp()
      state.adjustViewport(viewportHeight)
      return RecentFileModeResult(kind: rfmrHandled, modeTransition: none(EditorMode))
    of skDown:
      state.moveDown()
      state.adjustViewport(viewportHeight)
      return RecentFileModeResult(kind: rfmrHandled, modeTransition: none(EditorMode))
    of skLeft, skRight, skBackspace:
      # No-op for horizontal movement keys (vim compatibility)
      return RecentFileModeResult(kind: rfmrHandled, modeTransition: none(EditorMode))
    else:
      return RecentFileModeResult(kind: rfmrUnhandled, modeTransition: none(EditorMode))

  # Handle character keys with Ctrl modifier
  if not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers:
    case keyCombo.char
    of "k":
      return
        RecentFileModeResult(kind: rfmrNextWindow, modeTransition: none(EditorMode))
    of "j":
      return
        RecentFileModeResult(kind: rfmrPrevWindow, modeTransition: none(EditorMode))
    else:
      return RecentFileModeResult(kind: rfmrUnhandled, modeTransition: none(EditorMode))

  # Handle character keys without modifiers
  if not keyCombo.isSpecial:
    case keyCombo.char
    of "j":
      state.moveDown()
      state.adjustViewport(viewportHeight)
      return RecentFileModeResult(kind: rfmrHandled, modeTransition: none(EditorMode))
    of "k":
      state.moveUp()
      state.adjustViewport(viewportHeight)
      return RecentFileModeResult(kind: rfmrHandled, modeTransition: none(EditorMode))
    of "G":
      state.moveToLast()
      state.adjustViewport(viewportHeight)
      return RecentFileModeResult(kind: rfmrHandled, modeTransition: none(EditorMode))
    of "g":
      handler.waitingForG = true
      return RecentFileModeResult(kind: rfmrHandled, modeTransition: none(EditorMode))
    of ":":
      return RecentFileModeResult(
        kind: rfmrEnterCommand, modeTransition: some(EditorMode.Command)
      )
    of "h", "l":
      # No-op for horizontal movement keys (vim compatibility)
      return RecentFileModeResult(kind: rfmrHandled, modeTransition: none(EditorMode))
    else:
      return RecentFileModeResult(kind: rfmrUnhandled, modeTransition: none(EditorMode))

  return RecentFileModeResult(kind: rfmrUnhandled, modeTransition: none(EditorMode))
