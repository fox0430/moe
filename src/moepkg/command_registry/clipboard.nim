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

import pkg/results

import ../[types, clipboard_backend, registers, visual_selection]
import ../buffer/edit
import ../command_handlers/visual_commands

import core

proc copySelection(ctx: CommandContext, sel: VisualSelection): Result[(), string] =
  ## Copy `sel` to the system clipboard.
  if not sel.active:
    return err("No text selected")

  let selectedText = getVisualSelectionText(ctx.buffer, sel)
  if selectedText.len == 0 and sel.kind == vskChar:
    return err("No text selected")

  # Write synchronously so a following put reads the copied content.
  let writeResult = writeToClipboardSync(ctx.clipboardConfig.tool, selectedText)
  if writeResult.isErr:
    return err(writeResult.error)

  # Sync the unnamed register so the put keeps the linewise/characterwise type.
  let isLine = sel.kind == vskLine
  ctx.state.registers.markClipboardWritten(selectedText, isLine, writeResult.get)

  return Result[(), string].ok ()

proc handleClipboardCopy*(ctx: CommandContext): Result[(), string] =
  ## Copy selected text to system clipboard
  if not ctx.clipboardConfig.enable:
    return err("Clipboard integration is disabled")

  copySelection(ctx, ctx.state.operandSelection(ctx.buffer))

proc handleClipboardPaste*(ctx: CommandContext): Result[(), string] =
  ## Paste text from system clipboard at cursor position
  if not ctx.clipboardConfig.enable:
    return err("Clipboard integration is disabled")

  # Read from clipboard
  let readResult = readFromClipboardSync(ctx.clipboardConfig.tool)
  if readResult.isErr:
    return err(readResult.error)

  let clipboardText = readResult.value
  if clipboardText.len == 0:
    return Result[(), string].ok () # Nothing to paste

  # Insert text at cursor position
  let insertResult = ctx.buffer.insertText(ctx.cursor, clipboardText)
  if insertResult.isErr:
    return err(insertResult.error)

  # Update cursor position to end of pasted text
  # Note: For simplicity, we'll keep cursor at original position for now
  # A more sophisticated implementation would move cursor to end of paste

  return Result[(), string].ok ()

proc handleClipboardCut*(ctx: CommandContext): Result[(), string] =
  ## Cut selected text to system clipboard (copy + delete)
  if not ctx.clipboardConfig.enable:
    return err("Clipboard integration is disabled")

  # Both halves act on one operand, so a cut removes what it copied.
  let sel = ctx.state.operandSelection(ctx.buffer)
  # Copy first; a copy failure must not cancel the delete half.
  let copyResult = copySelection(ctx, sel)
  visualDelete(ctx.buffer, ctx.state, sel)

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
    "Paste text from system clipboard",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleClipboardPaste(ctx),
    0,
    0,
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
