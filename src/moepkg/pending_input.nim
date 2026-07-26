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

## Single-entry API for the aggregated pending-input FSMs. Callers must not
## poke individual fields when resetting; use cancelAll to avoid the two-place
## enumeration that plagued the old handleEscapeCancellationKeyCombo path.

import std/options

import types, key_bindings

proc isActive*(pi: PendingInputState, registry: KeyBindingRegistry): bool =
  ## True iff any pending-input FSM is active.
  pi.macroState.waitingForRegister or pi.pendingOperator.isSome or
    pi.pendingTextObject.isSome or pi.pendingRegister.isSome or
    pi.pendingCommand != PendingNone or registry.hasActiveSequence()

proc cancelAll*(
    pi: var PendingInputState, registry: KeyBindingRegistry
): bool {.discardable.} =
  ## Reset every pending-input FSM. Returns true iff something was actually
  ## cleared (callers use this for double-Escape UX).
  var cleared = false
  if pi.macroState.waitingForRegister:
    pi.macroState.waitingForRegister = false
    pi.macroState.commandType = ""
    pi.macroState.pendingCount = 0
    cleared = true
  if pi.pendingOperator.isSome:
    pi.pendingOperator = none(PendingOperator)
    cleared = true
  if pi.pendingTextObject.isSome:
    pi.pendingTextObject = none(PendingTextObject)
    cleared = true
  if pi.pendingRegister.isSome:
    pi.pendingRegister = none(char)
    cleared = true
  if registry.clearAllPending():
    cleared = true
  if pi.pendingCommand != PendingNone:
    pi.pendingCommand = PendingNone
    cleared = true
  cleared
