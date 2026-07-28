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

import ../[types, clipboard]
import ../buffer/edit
import ../command_handlers/visual_commands

import core

proc handleClipboardCopy*(ctx: CommandContext): Result[(), string] =
  ## Copy selected text to system clipboard
  if not ctx.clipboardConfig.enable:
    return err("Clipboard integration is disabled")

  # Get selected text
  let selectedText = getSelectedText(ctx.state, ctx.buffer)
  if selectedText.len == 0:
    return err("No text selected")

  # Write to clipboard (fire-and-forget)
  writeToClipboardAsync(ctx.clipboardConfig.tool, selectedText)

  return Result[(), string].ok ()

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

  # First, copy to clipboard
  let copyResult = handleClipboardCopy(ctx)
  if copyResult.isErr:
    return copyResult

  # Then delete the selection
  if ctx.state.visualSelection.active:
    visualDelete(ctx.buffer, ctx.state)

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
