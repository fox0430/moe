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

## Backup Manager mode command handler
##
## This module handles commands specific to Backup Manager mode.
## Allows users to view, restore, and delete backup files.
##
## Key bindings:
## - j/Down: Move selection down
## - k/Up: Move selection up
## - gg: Go to first entry
## - G: Go to last entry
## - R: Restore selected backup
## - D: Delete selected backup
## - r: Refresh backup list
## - Enter: Open diff viewer
## - q/Esc: Close backup manager
## - :: Enter command mode

import std/options

import ../[types, backup_manager, key_bindings]

type
  BackupManagerResultKind* = enum
    bkmrHandled # Command was handled successfully
    bkmrRestore # Restore the selected backup
    bkmrDelete # Delete the selected backup
    bkmrOpenDiff # Open diff viewer for selected backup
    bkmrRefresh # Refresh the backup list
    bkmrEnterCommand # Enter command mode
    bkmrQuit # Close backup manager and return to previous mode
    bkmrUnhandled # Command was not handled
    bkmrError # Error occurred

  BackupManagerResult* = object
    case kind*: BackupManagerResultKind
    of bkmrRestore:
      restoreIndex*: int
    of bkmrDelete:
      deleteIndex*: int
    of bkmrOpenDiff:
      diffIndex*: int
    of bkmrError:
      errorMessage*: string
    else:
      discard

  BackupManagerHandler* = ref object
    ## Handler for Backup Manager mode specific commands
    waitingForG*: bool # Waiting for second 'g' for 'gg' command

proc newBackupManagerHandler*(): BackupManagerHandler =
  ## Create a new Backup Manager mode handler
  BackupManagerHandler(waitingForG: false)

proc handleBackupManagerModeKey*(
    handler: BackupManagerHandler,
    bkState: BackupManagerState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): BackupManagerResult =
  ## Handle a key press in Backup Manager mode
  ##
  ## Returns a BackupManagerResult indicating what action should be taken

  # Handle 'gg' command (two g presses)
  if handler.waitingForG:
    handler.waitingForG = false
    if not keyCombo.isSpecial and keyCombo.char == "g":
      bkState.moveToFirst()
      return BackupManagerResult(kind: bkmrHandled)
    # If not 'g', fall through to normal handling

  # Escape key - quit backup manager
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    return BackupManagerResult(kind: bkmrQuit)

  # Check for special keys first
  if keyCombo.isSpecial:
    case keyCombo.special
    of skEnter:
      # Open diff viewer for selected backup
      let entry = bkState.getSelectedEntry()
      if entry.isSome:
        return BackupManagerResult(kind: bkmrOpenDiff, diffIndex: bkState.selectedIndex)
      return BackupManagerResult(kind: bkmrHandled)
    of skUp:
      bkState.moveUp()
      return BackupManagerResult(kind: bkmrHandled)
    of skDown:
      bkState.moveDown()
      return BackupManagerResult(kind: bkmrHandled)
    else:
      discard
  else:
    # Character keys
    # Check for Ctrl+d (half page down)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "d":
      let halfPage = max(1, viewportHeight div 2)
      for i in 0 ..< halfPage:
        bkState.moveDown()
      return BackupManagerResult(kind: bkmrHandled)

    # Check for Ctrl+u (half page up)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "u":
      let halfPage = max(1, viewportHeight div 2)
      for i in 0 ..< halfPage:
        bkState.moveUp()
      return BackupManagerResult(kind: bkmrHandled)

    # Check for Ctrl+k (next window)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "k":
      # This will be handled by the editor to switch windows
      return BackupManagerResult(kind: bkmrUnhandled)

    # Check for Ctrl+j (prev window)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "j":
      # This will be handled by the editor to switch windows
      return BackupManagerResult(kind: bkmrUnhandled)

    case keyCombo.char
    of ":":
      return BackupManagerResult(kind: bkmrEnterCommand)
    of "q":
      return BackupManagerResult(kind: bkmrQuit)
    of "j":
      bkState.moveDown()
      return BackupManagerResult(kind: bkmrHandled)
    of "k":
      bkState.moveUp()
      return BackupManagerResult(kind: bkmrHandled)
    of "g":
      # Start waiting for second 'g'
      handler.waitingForG = true
      return BackupManagerResult(kind: bkmrHandled)
    of "G":
      bkState.moveToLast()
      return BackupManagerResult(kind: bkmrHandled)
    of "R":
      # Restore the selected backup
      let entry = bkState.getSelectedEntry()
      if entry.isSome:
        return
          BackupManagerResult(kind: bkmrRestore, restoreIndex: bkState.selectedIndex)
      return BackupManagerResult(kind: bkmrHandled)
    of "D":
      # Delete the selected backup
      let entry = bkState.getSelectedEntry()
      if entry.isSome:
        return BackupManagerResult(kind: bkmrDelete, deleteIndex: bkState.selectedIndex)
      return BackupManagerResult(kind: bkmrHandled)
    of "r":
      # Refresh backup list
      return BackupManagerResult(kind: bkmrRefresh)
    else:
      discard

  return BackupManagerResult(kind: bkmrUnhandled)
