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

proc handleVisualMoveLeft*(ctx: CommandContext): Result[(), string] =
  ## Move left in visual mode and update selection
  visualMoveLeft(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor # Sync ctx.cursor from state
  Result[(), string].ok ()

proc handleVisualMoveRight*(ctx: CommandContext): Result[(), string] =
  ## Move right in visual mode and update selection
  visualMoveRight(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor # Sync ctx.cursor from state
  Result[(), string].ok ()

proc handleVisualMoveUp*(ctx: CommandContext): Result[(), string] =
  ## Move up in visual mode and update selection
  visualMoveUp(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor # Sync ctx.cursor from state
  Result[(), string].ok ()

proc handleVisualMoveDown*(ctx: CommandContext): Result[(), string] =
  ## Move down in visual mode and update selection
  visualMoveDown(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor # Sync ctx.cursor from state
  Result[(), string].ok ()

proc handleVisualDelete*(ctx: CommandContext): Result[(), string] =
  ## Delete visual selection
  visualDelete(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualYank*(ctx: CommandContext): Result[(), string] =
  ## Yank (copy) visual selection
  visualYank(ctx.buffer, ctx.state)
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

proc handleVisualMoveHome*(ctx: CommandContext): Result[(), string] =
  ## Move to beginning of line in visual mode
  visualMoveHome(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveEnd*(ctx: CommandContext): Result[(), string] =
  ## Move to end of line in visual mode
  visualMoveEnd(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveFirstNonBlank*(ctx: CommandContext): Result[(), string] =
  ## Move to first non-blank character in visual mode
  visualMoveFirstNonBlank(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveFirstLine*(ctx: CommandContext): Result[(), string] =
  ## Move to first line in visual mode
  visualMoveFirstLine(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveLastLine*(
    ctx: CommandContext, count: int = 0
): Result[(), string] =
  ## Move to last line (or specific line number) in visual mode
  visualMoveLastLine(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveWord*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Move to next word in visual mode
  visualMoveWord(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveWordBack*(
    ctx: CommandContext, count: int = 1
): Result[(), string] =
  ## Move to previous word in visual mode
  visualMoveWordBack(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveWordEnd*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Move to end of word in visual mode
  visualMoveWordEnd(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveWordEndBackward*(
    ctx: CommandContext, count: int = 1
): Result[(), string] =
  ## Move to end of previous word in visual mode
  visualMoveWordEndBackward(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveParagraphForward*(
    ctx: CommandContext, count: int = 1
): Result[(), string] =
  ## Move to next paragraph in visual mode
  visualMoveParagraphForward(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveParagraphBackward*(
    ctx: CommandContext, count: int = 1
): Result[(), string] =
  ## Move to previous paragraph in visual mode
  visualMoveParagraphBackward(ctx.buffer, ctx.state, count)
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
  visualChange(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualSwapSelection*(ctx: CommandContext): Result[(), string] =
  ## Swap cursor between start and end of selection
  visualSwapSelection(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualPaste*(ctx: CommandContext): Result[(), string] =
  ## Paste over selection
  result = visualPaste(ctx.buffer, ctx.state, ctx.clipboardConfig)
  ctx.cursor = ctx.state.cursor

proc registerVisualCommands*(registry: CommandRegistry) =
  ## Register all 28 visual mode commands.

  # Visual mode movement commands
  registry.register(
    builtin(bcVisualMoveLeft),
    "Visual Move Left",
    "Move left and update visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualMoveLeft(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualMoveRight),
    "Visual Move Right",
    "Move right and update visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualMoveRight(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualMoveUp),
    "Visual Move Up",
    "Move up and update visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualMoveUp(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualMoveDown),
    "Visual Move Down",
    "Move down and update visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualMoveDown(ctx),
    0,
    0,
  )

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
    builtin(bcVisualMoveHome),
    "Visual Move Home",
    "Move to beginning of line in visual mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualMoveHome(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualMoveEnd),
    "Visual Move End",
    "Move to end of line in visual mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualMoveEnd(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualMoveFirstNonBlank),
    "Visual Move First Non-Blank",
    "Move to first non-blank character in visual mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualMoveFirstNonBlank(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualMoveFirstLine),
    "Visual Move First Line",
    "Move to first line in visual mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualMoveFirstLine(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualMoveLastLine),
    "Visual Move Last Line",
    "Move to last line (or specific line number) in visual mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 0)
      handleVisualMoveLastLine(ctx, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualMoveWord),
    "Visual Move Word",
    "Move to next word in visual mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualMoveWord(ctx, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualMoveWordBack),
    "Visual Move Word Back",
    "Move to previous word in visual mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualMoveWordBack(ctx, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualMoveWordEnd),
    "Visual Move Word End",
    "Move to end of word in visual mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualMoveWordEnd(ctx, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualMoveWordEndBackward),
    "Visual Move Word End Backward",
    "Move to end of previous word in visual mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualMoveWordEndBackward(ctx, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualMoveParagraphForward),
    "Visual Move Paragraph Forward",
    "Move to next paragraph in visual mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualMoveParagraphForward(ctx, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualMoveParagraphBackward),
    "Visual Move Paragraph Backward",
    "Move to previous paragraph in visual mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualMoveParagraphBackward(ctx, count),
    0,
    1,
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
    "Paste over selection (p/P command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualPaste(ctx),
    0,
    0,
  )
