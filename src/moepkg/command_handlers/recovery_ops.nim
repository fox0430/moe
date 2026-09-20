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

## Recovery manager operations.
##
## The listing is rebuilt rather than edited in place: another editor may have
## discarded a session since it was built.

import ../[editor, message_log, types, recovery_manager]

import handler_result

proc refreshRecoveryView(e: Editor, rcState: RecoveryManagerState) =
  let activeWin = e.activeWindow
  activeWin.setView(rcState.createRecoveryManagerTextBuffer())
  activeWin.cursor.line = min(rcState.selectedIndex + 1, activeWin.buffer.len - 1)
  activeWin.cursor.column = 0

proc processRecoveryResult*(e: Editor, r: HandlerResult): bool =
  ## Handle hrRecoveryManager* kinds. Returns true to continue.
  let activeWin = e.activeWindow
  if activeWin.modeState.kind != mskRecoveryManager:
    return true
  let rcState = activeWin.modeState.recoveryManager

  case r.kind
  of hrRecoveryManagerRefresh:
    rcState.refresh()
    e.refreshRecoveryView(rcState)
    return true
  of hrRecoveryManagerDiscard:
    var discardReason = ""
    if rcState.discardEntry(r.discardRecoveryIndex, discardReason):
      e.state.statusMessage = "Preserved copy discarded"
      e.refreshRecoveryView(rcState)
    else:
      # Carry the filesystem reason; the user cannot see it from here.
      let message =
        if discardReason.len > 0:
          "Failed to discard the preserved copy: " & discardReason
        else:
          "Failed to discard the preserved copy"
      e.state.statusMessage = message
      addMessageLog message
    return true
  else:
    return true
