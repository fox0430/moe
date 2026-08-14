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

## Tests for pending_input.nim

import std/[unittest, options]

import ../src/moepkg/[types, modes]
import ../src/moepkg/key_bindings {.all.}
import ../src/moepkg/pending_input {.all.}

proc newTestState(): tuple[pi: PendingInputState, registry: KeyBindingRegistry] =
  (pi: PendingInputState(), registry: newKeyBindingRegistry())

proc startSequence(registry: KeyBindingRegistry) =
  let cmd = Command(
    name: "seq-cmd", description: "Test", kind: ctMotion, motion: Motion.FirstLine
  )
  registry.registerCommand(cmd)
  let seq = @[toKeyCombo('g'), toKeyCombo('g')]
  registry.bindSequence(EditorMode.Normal, seq, cmd)
  discard registry.processKey(EditorMode.Normal, toKeyCombo('g'))

suite "PendingInputState - isActive":
  test "isActive is false with nothing pending":
    let (pi, registry) = newTestState()
    check isActive(pi, registry) == false

  test "isActive with waitingForRegister":
    var (pi, registry) = newTestState()
    pi.macroState.waitingForRegister = true
    check isActive(pi, registry) == true

  test "isActive with pendingOperator":
    var (pi, registry) = newTestState()
    pi.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete, operatorCount: 1, startPos: BufferPosition()
      )
    )
    check isActive(pi, registry) == true

  test "isActive with pendingTextObject":
    var (pi, registry) = newTestState()
    pi.pendingTextObject = some(PendingTextObject(modifier: tomInner))
    check isActive(pi, registry) == true

  test "isActive with pendingRegister":
    var (pi, registry) = newTestState()
    pi.pendingRegister = some('a')
    check isActive(pi, registry) == true

  test "isActive with pendingCommand":
    var (pi, registry) = newTestState()
    pi.pendingCommand = PendingWindowCmd
    check isActive(pi, registry) == true

  test "isActive with an active registry sequence":
    var (pi, registry) = newTestState()
    startSequence(registry)
    check isActive(pi, registry) == true

suite "PendingInputState - cancelAll":
  test "cancelAll returns false when nothing is pending":
    var (pi, registry) = newTestState()
    check cancelAll(pi, registry) == false

  test "cancelAll clears waitingForRegister and related fields":
    var (pi, registry) = newTestState()
    pi.macroState.waitingForRegister = true
    pi.macroState.commandType = "record"
    pi.macroState.pendingCount = 3
    check cancelAll(pi, registry) == true
    check pi.macroState.waitingForRegister == false
    check pi.macroState.commandType == ""
    check pi.macroState.pendingCount == 0

  test "cancelAll clears pendingOperator":
    var (pi, registry) = newTestState()
    pi.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete, operatorCount: 1, startPos: BufferPosition()
      )
    )
    check cancelAll(pi, registry) == true
    check pi.pendingOperator.isNone

  test "cancelAll clears pendingTextObject":
    var (pi, registry) = newTestState()
    pi.pendingTextObject = some(PendingTextObject(modifier: tomInner))
    check cancelAll(pi, registry) == true
    check pi.pendingTextObject.isNone

  test "cancelAll clears pendingRegister":
    var (pi, registry) = newTestState()
    pi.pendingRegister = some('a')
    check cancelAll(pi, registry) == true
    check pi.pendingRegister.isNone

  test "cancelAll clears pendingCommand":
    var (pi, registry) = newTestState()
    pi.pendingCommand = PendingWindowCmd
    check cancelAll(pi, registry) == true
    check pi.pendingCommand == PendingNone

  test "cancelAll clears an active registry sequence":
    var (pi, registry) = newTestState()
    startSequence(registry)
    check cancelAll(pi, registry) == true
    check registry.hasActiveSequence() == false

  test "cancelAll clears everything at once":
    var (pi, registry) = newTestState()
    pi.macroState.waitingForRegister = true
    pi.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete, operatorCount: 1, startPos: BufferPosition()
      )
    )
    pi.pendingTextObject = some(PendingTextObject(modifier: tomInner))
    pi.pendingRegister = some('a')
    pi.pendingCommand = PendingWindowCmd
    startSequence(registry)
    check cancelAll(pi, registry) == true
    check isActive(pi, registry) == false
