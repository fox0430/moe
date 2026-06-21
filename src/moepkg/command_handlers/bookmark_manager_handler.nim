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
    bmState: BookmarkManagerState, viewportHeight: int, keyCombo: KeyCombo
): BookmarkManagerResult =
  ## Handle a key press in Bookmark Manager mode

  # Ctrl-k / Ctrl-j switch windows; the editor handles them. Cancel any pending
  # 'gg' first, since this early return bypasses handleListNavKey (the only place
  # that would otherwise clear waitingForG).
  if not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
      (keyCombo.char == "k" or keyCombo.char == "j"):
    bmState.waitingForG = false
    return BookmarkManagerResult(kind: bkmrUnhandled)

  case bmState.handleListNavKey(viewportHeight, keyCombo)
  of lvaConsumed:
    return BookmarkManagerResult(kind: bkmrHandled)
  of lvaQuitKey, lvaEscape:
    return BookmarkManagerResult(kind: bkmrQuit)
  of lvaEnterCommand:
    return BookmarkManagerResult(kind: bkmrEnterCommand)
  of lvaSelect:
    # Jump to the selected bookmark
    let entry = bmState.getSelectedItem()
    if entry.isSome:
      return BookmarkManagerResult(
        kind: bkmrJumpToBookmark,
        jumpBufferIndex: entry.get.bufferIndex,
        jumpLine: entry.get.line,
      )
    return BookmarkManagerResult(kind: bkmrHandled)
  of lvaUnhandled:
    discard # fall through to bookmark-manager-specific keys

  if not keyCombo.isSpecial and keyCombo.char == "D":
    let entry = bmState.getSelectedItem()
    if entry.isSome:
      return BookmarkManagerResult(
        kind: bkmrDeleteBookmark, deleteEntryIndex: bmState.selectedIndex
      )
    return BookmarkManagerResult(kind: bkmrHandled)

  return BookmarkManagerResult(kind: bkmrUnhandled)
