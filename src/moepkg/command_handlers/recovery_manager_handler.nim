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

## Recovery Manager mode command handler.

import std/options

import ../[types, recovery_manager, key_bindings]
import handler_types
export handler_types

type
  RecoveryManagerResultKind* = enum
    rcmrHandled
    rcmrRestore ## Restore the selected copy into the buffer
    rcmrToggleReviewed ## Mark the selected copy dealt with, or not
    rcmrDiscard
    rcmrArmDiscard ## Ask before discarding the selected copy
    rcmrRefresh
    rcmrEnterCommand
    rcmrUnhandled

  RecoveryManagerResult* = object
    case kind*: RecoveryManagerResultKind
    of rcmrRestore:
      restoreIndex*: int
    of rcmrToggleReviewed:
      reviewIndex*: int
    of rcmrDiscard, rcmrArmDiscard:
      discardIndex*: int
    else:
      discard

proc handleRecoveryManagerModeKey*(
    rcState: RecoveryManagerState, viewportHeight: int, keyCombo: KeyCombo
): RecoveryManagerResult =
  ## Handle a key press in Recovery Manager mode

  # Any key but a second `D` cancels the arm.
  let armed = rcState.armedDiscardIndex
  rcState.armedDiscardIndex = none(int)

  # Ctrl-k / Ctrl-j switch windows; the editor handles them. This early return
  # bypasses handleListNavKey, so clear any pending 'gg' here.
  if not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
      (keyCombo.char == "k" or keyCombo.char == "j"):
    rcState.waitingForG = false
    return RecoveryManagerResult(kind: rcmrUnhandled)

  case rcState.handleListNavKey(viewportHeight, keyCombo)
  of lvaConsumed:
    return RecoveryManagerResult(kind: rcmrHandled)
  of lvaQuitKey, lvaEscape:
    # As in the other managers: the router owns leaving.
    return RecoveryManagerResult(kind: rcmrUnhandled)
  of lvaEnterCommand:
    return RecoveryManagerResult(kind: rcmrEnterCommand)
  of lvaSelect:
    # Enter only looks at the highlighted row; a restore replaces the whole
    # buffer, so it asks for `R`, as in the backup manager.
    return RecoveryManagerResult(kind: rcmrHandled)
  of lvaUnhandled:
    discard # Fall through to recovery-manager-specific keys

  if not keyCombo.isSpecial:
    case keyCombo.char
    of "R":
      if rcState.getSelectedItem().isSome:
        return
          RecoveryManagerResult(kind: rcmrRestore, restoreIndex: rcState.selectedIndex)
      return RecoveryManagerResult(kind: rcmrHandled)
    of "x":
      # No confirmation: it only stops the notice, and `x` takes it back.
      if rcState.getSelectedItem().isSome:
        return RecoveryManagerResult(
          kind: rcmrToggleReviewed, reviewIndex: rcState.selectedIndex
        )
      return RecoveryManagerResult(kind: rcmrHandled)
    of "D":
      if rcState.getSelectedItem().isSome:
        if armed == some(rcState.selectedIndex):
          return RecoveryManagerResult(
            kind: rcmrDiscard, discardIndex: rcState.selectedIndex
          )
        rcState.armedDiscardIndex = some(rcState.selectedIndex)
        return RecoveryManagerResult(
          kind: rcmrArmDiscard, discardIndex: rcState.selectedIndex
        )
      return RecoveryManagerResult(kind: rcmrHandled)
    of "r":
      return RecoveryManagerResult(kind: rcmrRefresh)
    else:
      discard

  return RecoveryManagerResult(kind: rcmrUnhandled)
