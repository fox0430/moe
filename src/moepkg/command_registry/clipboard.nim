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

## Clipboard command handlers (copy/paste/cut).

import std/options

import pkg/results

import ../[types, clipboard_backend, modes, registers, visual_selection]
import ../command_handlers/visual_commands

import core, edit, visual

proc copySelection(ctx: CommandContext, sel: VisualSelection): Result[(), string] =
  ## Copy `sel` to the system clipboard.
  if not sel.active:
    return err("No text selected")

  let selected = ctx.buffer.selectedRegister(sel, ctx.state.tabStop)
  if selected.kind == rkChars and selected.holdsNoText:
    return err("No text selected")

  # Write synchronously so a following put reads the copied content.
  let writeResult =
    writeToClipboardSync(ctx.clipboardConfig.tool, selected.selectionContent)
  if writeResult.isErr:
    return err(writeResult.error)

  # Sync the unnamed register so the put keeps the selection's kind.
  ctx.state.registers.markClipboardWritten(selected, writeResult.get)

  return Result[(), string].ok ()

proc handleClipboardCopy*(ctx: CommandContext): Result[(), string] =
  ## Copy selected text to system clipboard
  if not ctx.clipboardConfig.enable:
    return err("Clipboard integration is disabled")

  copySelection(ctx, ctx.state.operandSelection)

proc handleClipboardPaste*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## `"+P`: put the system clipboard before the cursor, or over the selection
  ## in Visual, as one undo step. A typed register gives way to `+`, as in a
  ## mapping to `"+P`.
  if not ctx.clipboardConfig.enable:
    return err("Clipboard integration is disabled")

  ctx.register = some('+')
  if ctx.state.mode.isVisualAllMode:
    handleVisualPaste(ctx, args, before = true)
  else:
    handlePut(ctx, parseCount(args, default = 1), forward = false)

proc handleClipboardCut*(ctx: CommandContext): Result[(), string] =
  ## Cut selected text to system clipboard (copy + delete)
  if not ctx.clipboardConfig.enable:
    return err("Clipboard integration is disabled")

  # Both halves act on one operand, so a cut removes what it copied.
  let (sel, area) = ctx.buffer.operandArea(ctx.state)
  # Copy first; a copy failure must not cancel the delete half.
  let copyResult = copySelection(ctx, sel)
  discard visualDelete(ctx.buffer, ctx.state, sel, area, ctx.register)

  if copyResult.isErr:
    return copyResult

  return Result[(), string].ok ()

proc registerClipboardCommands*(registry: CommandRegistry) =
  ## Register clipboard commands (copy/paste/cut)
  registry.register(
    builtin(bcEditCopy),
    "Copy",
    "Copy selected text to system clipboard",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleClipboardCopy(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcEditPaste),
    "Paste",
    "Paste the system clipboard before the cursor or over the selection (as \"+P)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleClipboardPaste(ctx, args),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    builtin(bcEditCut),
    "Cut",
    "Cut selected text to system clipboard",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleClipboardCut(ctx),
    0,
    0,
  )
