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

import ../[types, modes, visual_block]
import ../command_handlers/visual_commands

import core, insert_entry

## Visual mode command handlers (wrappers for visual_commands functions)

proc handleVisualOperator*(
    ctx: CommandContext, op: VisualOperator, count = 1
): Result[(), string] =
  ## Act with `op` over the selection. `.` acts again over an area of the
  ## same size at the cursor, with the same count; a refused operator leaves
  ## what `.` repeats as it was.
  let (sel, area) = ctx.buffer.operandArea(ctx.state)
  if not sel.active:
    return ok(())
  let shape = ctx.buffer.visualShape(sel, area, ctx.state.tabStop)
  # As `c`, a refused operator says so in the status line only.
  if runVisualOperator(ctx.buffer, ctx.state, op, sel, area, count, ctx.register).isOk:
    ctx.recordChange(
      LastEditCommand(
        kind: lecVisualOperator,
        visualOperator: op,
        visualShape: shape,
        visualCount: count,
      )
    )
  Result[(), string].ok ()

proc handleVisualYank*(ctx: CommandContext): Result[(), string] =
  ## Yank (copy) visual selection
  visualYank(ctx.buffer, ctx.state, ctx.register)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc startInsertAtCursor(ctx: CommandContext) =
  # `.` inserts what is typed at the cursor only, where Vim's goes over a block
  # as big.
  if ctx.state.mode == EditorMode.Insert:
    ctx.enterInsert(InsertEntry(kind: ieInsert), 1)

proc handleVisualToInsertMode*(ctx: CommandContext): Result[(), string] =
  ## Switch from visual mode to insert mode
  visualToInsertMode(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  ctx.startInsertAtCursor()
  Result[(), string].ok ()

proc handleVisualBlockAppend*(ctx: CommandContext): Result[(), string] =
  ## Append after visual block selection (A command)
  visualBlockAppend(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  ctx.startInsertAtCursor()
  Result[(), string].ok ()

proc handleVisualChange*(ctx: CommandContext): Result[(), string] =
  ## Delete selection and enter insert mode. `.` changes an area of the same
  ## size at the cursor.
  let
    (sel, area) = ctx.buffer.operandArea(ctx.state)
    shape = ctx.buffer.visualShape(sel, area, ctx.state.tabStop)
  visualChange(ctx.buffer, ctx.state, sel, area, ctx.register)
  ctx.cursor = ctx.state.cursor
  if ctx.state.mode == EditorMode.Insert:
    ctx.enterInsert(InsertEntry(kind: ieVisualChange, shape: shape), 1)
  Result[(), string].ok ()

proc handleVisualSwapSelection*(ctx: CommandContext): Result[(), string] =
  ## Swap cursor between start and end of selection
  visualSwapSelection(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualPaste*(
    ctx: CommandContext, args: seq[string], cursorAfter: bool = false, before = false
): Result[(), string] =
  ## Paste over selection (p) as many times as the count in `args` says.
  ## `cursorAfter` is gp/gP, `before` is P/gP; P also keeps the registers.
  result = visualPaste(
    ctx.buffer,
    ctx.state,
    ctx.clipboardConfig,
    cursorAfter,
    ctx.register,
    keepRegisters = before and not cursorAfter,
    before = before,
    count = parseCount(args, default = 1),
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
      handleVisualOperator(ctx, voDelete),
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
      handleVisualOperator(ctx, voIndent, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualDedent),
    "Visual Dedent",
    "Dedent visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualOperator(ctx, voDedent, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualLowercase),
    "Visual Lowercase",
    "Convert visual selection to lowercase",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualOperator(ctx, voLowerCase),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualUppercase),
    "Visual Uppercase",
    "Convert visual selection to uppercase",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualOperator(ctx, voUpperCase),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualToggleCase),
    "Visual Toggle Case",
    "Toggle case of visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualOperator(ctx, voToggleCase),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualJoinLines),
    "Visual Join Lines",
    "Join lines in visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualOperator(ctx, voJoin),
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
      handleVisualPaste(ctx, args),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("visual.paste.before"),
    "Visual Paste Before",
    "Paste over selection, keeping the registers (P command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualPaste(ctx, args, before = true),
    0,
    1, # Accept optional count argument
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
      handleVisualPaste(ctx, args, cursorAfter = true),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("visual.paste.before.end"),
    "Visual Paste Before End",
    "Paste over selection and leave cursor after pasted text (gP)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualPaste(ctx, args, cursorAfter = true, before = true),
    0,
    1, # Accept optional count argument
  )
