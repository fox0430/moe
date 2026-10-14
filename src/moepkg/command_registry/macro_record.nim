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

## `q` as a command, so it resolves like any other key in Normal and Visual
## mode: pending operators, counts and operand waits see it first.

import pkg/results

import ../[types, key_bindings, macro_recording]

import core

const RecordRegister = key_bindings.Command(
  name: "macro-record-register",
  description: "Register a recording goes to",
  kind: ctOperatorPending,
  operatorType: "macro-record",
) ## The operand `q` waits for. Not bindable on its own.

proc handleMacroRecord(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Like Vim's `q`: it is ignored in a running register, stops a recording,
  ## and only otherwise takes a register name.
  if ctx.state.pendingInput.macroState.executingDepth > 0:
    return ok(())
  if ctx.state.pendingInput.macroState.isRecording:
    ctx.state.pendingInput.macroState.stopRecording(
      afterCtrlO = ctx.state.resumesInsert
    )
    return ok(())
  ctx.keyBindingRegistry.awaitOperand(RecordRegister)
  ok(())

proc startMacroRecording*(ctx: CommandContext, register: string): Result[(), string] =
  ## The register operand of `q`.
  if register.len != 1 or register[0] notin {'a' .. 'z'}:
    return err("Invalid register (use a-z)")
  ctx.state.pendingInput.macroState.startRecording(register[0])
  ok(())

proc registerMacroCommands*(registry: CommandRegistry) =
  registry.register(
    custom("macro.record"),
    "Record Macro",
    "Start or stop macro recording (q)",
    handleMacroRecord,
    0,
    0,
  )
