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

## Visual mode command handlers and registration.

import pkg/results

import ../types
import ../command_handlers/visual_commands

import core

## Visual mode command handlers (wrappers for visual_commands functions)

proc handleVisualDelete*(ctx: CommandContext): Result[(), string] =
  ## Delete visual selection
  visualDelete(ctx.buffer, ctx.state, ctx.register)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualYank*(ctx: CommandContext): Result[(), string] =
  ## Yank (copy) visual selection
  visualYank(ctx.buffer, ctx.state, ctx.register)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualIndent*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Indent visual selection
  visualIndent(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualDedent*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Dedent visual selection
  visualDedent(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualLowercase*(ctx: CommandContext): Result[(), string] =
  ## Convert visual selection to lowercase
  visualLowercase(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualUppercase*(ctx: CommandContext): Result[(), string] =
  ## Convert visual selection to uppercase
  visualUppercase(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualToggleCase*(ctx: CommandContext): Result[(), string] =
  ## Toggle case of visual selection
  visualToggleCase(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualJoinLines*(ctx: CommandContext): Result[(), string] =
  ## Join lines in visual selection
  visualJoinLines(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualToInsertMode*(ctx: CommandContext): Result[(), string] =
  ## Switch from visual mode to insert mode
  visualToInsertMode(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualBlockAppend*(ctx: CommandContext): Result[(), string] =
  ## Append after visual block selection (A command)
  visualBlockAppend(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualChange*(ctx: CommandContext): Result[(), string] =
  ## Delete selection and enter insert mode
  visualChange(ctx.buffer, ctx.state, ctx.register)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualSwapSelection*(ctx: CommandContext): Result[(), string] =
  ## Swap cursor between start and end of selection
  visualSwapSelection(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualPaste*(
    ctx: CommandContext, cursorAfter: bool = false, before = false
): Result[(), string] =
  ## Paste over selection (p). `cursorAfter` is gp/gP, `before` is P/gP; P also
  ## keeps the registers.
  result = visualPaste(
    ctx.buffer,
    ctx.state,
    ctx.clipboardConfig,
    cursorAfter,
    ctx.register,
    keepRegisters = before and not cursorAfter,
    before = before,
  )
  ctx.cursor = ctx.state.cursor

proc handleVisualReselect*(ctx: CommandContext): Result[(), string] =
  ## Swap the selection with the last Visual area (gv in Visual mode)
  let r = reselectVisual(ctx.buffer, ctx.state)
  if r.isErr:
    return Result[(), string].err r.error
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc registerVisualCommands*(registry: CommandRegistry) =
  ## Register all 17 visual mode commands.

  registry.register(
    builtin(bcVisualDelete),
    "Visual Delete",
    "Delete visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualDelete(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualYank),
    "Visual Yank",
    "Yank (copy) visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualYank(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualIndent),
    "Visual Indent",
    "Indent visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualIndent(ctx, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualDedent),
    "Visual Dedent",
    "Dedent visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualDedent(ctx, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualLowercase),
    "Visual Lowercase",
    "Convert visual selection to lowercase",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualLowercase(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualUppercase),
    "Visual Uppercase",
    "Convert visual selection to uppercase",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualUppercase(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualToggleCase),
    "Visual Toggle Case",
    "Toggle case of visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualToggleCase(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualJoinLines),
    "Visual Join Lines",
    "Join lines in visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualJoinLines(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualToInsertMode),
    "Visual To Insert Mode",
    "Switch from visual mode to insert mode (I command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualToInsertMode(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualBlockAppend),
    "Visual Block Append",
    "Append after visual block selection (A command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualBlockAppend(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualChange),
    "Visual Change",
    "Delete selection and enter insert mode (c command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualChange(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualSwapSelection),
    "Visual Swap Selection",
    "Swap cursor between start and end of selection (o command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualSwapSelection(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualPaste),
    "Visual Paste",
    "Paste over selection (p command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualPaste(ctx),
    0,
    0,
  )

  registry.register(
    custom("visual.paste.before"),
    "Visual Paste Before",
    "Paste over selection, keeping the registers (P command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualPaste(ctx, before = true),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualReselect),
    "Visual Reselect",
    "Exchange the selection with the previous visual area (gv command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualReselect(ctx),
    0,
    0,
  )

  registry.register(
    custom("visual.paste.end"),
    "Visual Paste End",
    "Paste over selection and leave cursor after pasted text (gp)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualPaste(ctx, cursorAfter = true),
    0,
    0,
  )

  registry.register(
    custom("visual.paste.before.end"),
    "Visual Paste Before End",
    "Paste over selection and leave cursor after pasted text (gP)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualPaste(ctx, cursorAfter = true, before = true),
    0,
    0,
  )
