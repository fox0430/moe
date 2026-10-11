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
## poke individual fields when resetting; cancelAll keeps the list in one place
## for Escape, Ctrl-C and a failed command.

import std/options

import types, key_bindings

proc isActive*(pi: PendingInputState, registry: KeyBindingRegistry): bool =
  ## True iff any pending-input FSM is active.
  pi.pendingOperator.isSome or pi.pendingTextObject.isSome or pi.pendingRegister.isSome or
    pi.pendingCommand != PendingNone or registry.hasActiveSequence()

proc waitsForOperand*(pi: PendingInputState, registry: KeyBindingRegistry): bool =
  ## The next key ends a command already begun: a later key of a sequence
  ## (`gg`, `<C-w>j`) or its argument (f/t/r, a register, a text object), which
  ## Vim reads without mappings. After a count or an operator comes a command
  ## of its own, which mappings may take.
  pi.pendingTextObject.isSome or pi.pendingCommand != PendingNone or
    registry.isWaitingForChar or registry.isMidSequence

proc cancelOperatorPending*(pi: var PendingInputState): bool {.discardable.} =
  ## Drop the operator-pending gesture whole, as Vim's clearop does: the
  ## operator, the text object that is the second half of it, and the register
  ## named for it. Returns true iff an operator or text object was pending.
  var cleared = false
  if pi.pendingOperator.isSome:
    pi.pendingOperator = none(PendingOperator)
    cleared = true
  if pi.pendingTextObject.isSome:
    pi.pendingTextObject = none(PendingTextObject)
    cleared = true
  if cleared:
    pi.pendingRegister = none(char)
  cleared

proc cancelAll*(
    pi: var PendingInputState, registry: KeyBindingRegistry
): bool {.discardable.} =
  ## Reset every pending-input FSM. Returns true iff something was actually
  ## cleared (callers use this for double-Escape UX).
  var cleared = false
  if pi.cancelOperatorPending():
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
