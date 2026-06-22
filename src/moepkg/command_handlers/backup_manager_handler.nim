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
## - :: Enter command mode

import std/options

import ../[types, backup_manager, key_bindings]
import handler_types
export handler_types

type
  BackupManagerResultKind* = enum
    bkmrHandled # Command was handled successfully
    bkmrRestore # Restore the selected backup
    bkmrDelete # Delete the selected backup
    bkmrOpenDiff # Open diff viewer for selected backup
    bkmrRefresh # Refresh the backup list
    bkmrEnterCommand # Enter command mode
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

proc handleBackupManagerModeKey*(
    bkState: BackupManagerState, viewportHeight: int, keyCombo: KeyCombo
): BackupManagerResult =
  ## Handle a key press in Backup Manager mode
  ##
  ## Returns a BackupManagerResult indicating what action should be taken

  # Ctrl-k / Ctrl-j switch windows; the editor handles them. Cancel any pending
  # 'gg' first, since this early return bypasses handleListNavKey (the only place
  # that would otherwise clear waitingForG).
  if not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
      (keyCombo.char == "k" or keyCombo.char == "j"):
    bkState.waitingForG = false
    return BackupManagerResult(kind: bkmrUnhandled)

  case bkState.handleListNavKey(viewportHeight, keyCombo)
  of lvaConsumed:
    return BackupManagerResult(kind: bkmrHandled)
  of lvaQuitKey, lvaEscape:
    # The backup manager has no quit action; q/Escape are passed through.
    return BackupManagerResult(kind: bkmrUnhandled)
  of lvaEnterCommand:
    return BackupManagerResult(kind: bkmrEnterCommand)
  of lvaSelect:
    # Open the diff viewer for the selected backup
    let entry = bkState.getSelectedItem()
    if entry.isSome:
      return BackupManagerResult(kind: bkmrOpenDiff, diffIndex: bkState.selectedIndex)
    return BackupManagerResult(kind: bkmrHandled)
  of lvaUnhandled:
    discard # fall through to backup-manager-specific keys

  if not keyCombo.isSpecial:
    case keyCombo.char
    of "R":
      # Restore the selected backup
      let entry = bkState.getSelectedItem()
      if entry.isSome:
        return
          BackupManagerResult(kind: bkmrRestore, restoreIndex: bkState.selectedIndex)
      return BackupManagerResult(kind: bkmrHandled)
    of "D":
      # Delete the selected backup
      let entry = bkState.getSelectedItem()
      if entry.isSome:
        return BackupManagerResult(kind: bkmrDelete, deleteIndex: bkState.selectedIndex)
      return BackupManagerResult(kind: bkmrHandled)
    of "r":
      # Refresh backup list
      return BackupManagerResult(kind: bkmrRefresh)
    else:
      discard

  return BackupManagerResult(kind: bkmrUnhandled)
