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

## Bookmark Manager mode command handler
##
## This module handles commands specific to Bookmark Manager mode.
## Allows users to view, jump to, and delete bookmarks across all open buffers.

import std/options

import ../[types, bookmark_manager, key_bindings]
import handler_types
export handler_types

type
  BookmarkManagerResultKind* = enum
    bkmrHandled # Command was handled successfully
    bkmrJumpToBookmark # Enter → jump to selected bookmark
    bkmrDeleteBookmark # D → delete selected bookmark
    bkmrEnterCommand # : → command mode
    bkmrQuit # q/Escape → close
    bkmrUnhandled # Command was not handled
    bkmrError # Error occurred

  BookmarkManagerResult* = object
    case kind*: BookmarkManagerResultKind
    of bkmrJumpToBookmark:
      jumpBufferIndex*: int
      jumpLine*: int
    of bkmrDeleteBookmark:
      deleteEntryIndex*: int
    of bkmrError:
      errorMessage*: string
    else:
      discard

proc handleBookmarkManagerModeKey*(
    handler: SubStateHandler,
    bmState: BookmarkManagerState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): BookmarkManagerResult =
  ## Handle a key press in Bookmark Manager mode

  # Handle 'gg' command (two g presses)
  if handler.waitingForG:
    handler.waitingForG = false
    if not keyCombo.isSpecial and keyCombo.char == "g":
      bmState.selectedIndex = 0
      bmState.topLine = 0
      return BookmarkManagerResult(kind: bkmrHandled)

  # Escape key - quit
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    return BookmarkManagerResult(kind: bkmrQuit)

  # Check for special keys first
  if keyCombo.isSpecial:
    case keyCombo.special
    of skEnter:
      let entry = bmState.getSelectedItem()
      if entry.isSome:
        return BookmarkManagerResult(
          kind: bkmrJumpToBookmark,
          jumpBufferIndex: entry.get.bufferIndex,
          jumpLine: entry.get.line,
        )
      return BookmarkManagerResult(kind: bkmrHandled)
    of skUp:
      bmState.moveUp()
      return BookmarkManagerResult(kind: bkmrHandled)
    of skDown:
      bmState.moveDown()
      return BookmarkManagerResult(kind: bkmrHandled)
    else:
      discard
  else:
    # Check for Ctrl+d (half page down)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "d":
      let halfPage = max(1, viewportHeight div 2)
      for i in 0 ..< halfPage:
        bmState.moveDown()
      return BookmarkManagerResult(kind: bkmrHandled)

    # Check for Ctrl+u (half page up)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "u":
      let halfPage = max(1, viewportHeight div 2)
      for i in 0 ..< halfPage:
        bmState.moveUp()
      return BookmarkManagerResult(kind: bkmrHandled)

    # Check for Ctrl+k (next window)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "k":
      return BookmarkManagerResult(kind: bkmrUnhandled)

    # Check for Ctrl+j (prev window)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "j":
      return BookmarkManagerResult(kind: bkmrUnhandled)

    case keyCombo.char
    of ":":
      return BookmarkManagerResult(kind: bkmrEnterCommand)
    of "q":
      return BookmarkManagerResult(kind: bkmrQuit)
    of "j":
      bmState.moveDown()
      return BookmarkManagerResult(kind: bkmrHandled)
    of "k":
      bmState.moveUp()
      return BookmarkManagerResult(kind: bkmrHandled)
    of "g":
      handler.waitingForG = true
      return BookmarkManagerResult(kind: bkmrHandled)
    of "G":
      bmState.selectedIndex = max(0, bmState.entries.len - 1)
      return BookmarkManagerResult(kind: bkmrHandled)
    of "D":
      let entry = bmState.getSelectedItem()
      if entry.isSome:
        return BookmarkManagerResult(
          kind: bkmrDeleteBookmark, deleteEntryIndex: bmState.selectedIndex
        )
      return BookmarkManagerResult(kind: bkmrHandled)
    else:
      discard

  return BookmarkManagerResult(kind: bkmrUnhandled)
