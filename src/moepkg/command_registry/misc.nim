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

## Mode / insert / quickrun / search / git navigation handlers and registration.

import std/[options, strutils]

import pkg/results

import
  ../[types, buffer, motion, modes, git_conflict, unicode_utils, search_ops, fold_open]
import ../command_handlers/[insert_commands, normal_commands]

import core, insert_entry

## Command handler wrappers (delegate to mode-specific command modules)

proc handleModeSwitch*(
    ctx: CommandContext, targetMode: EditorMode
): Result[(), string] =
  ## Handle switching between editor modes
  if targetMode == EditorMode.Insert and ctx.buffer.readOnly:
    ctx.state.statusMessage = "Buffer is read-only"
    return ok(())
  switchMode(ctx.state, targetMode, ctx.keyBindingRegistry)
  Result[(), string].ok ()

proc handleInsertChar*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Handle character insertion in insert mode
  if args.len != 1 or args[0].len != 1:
    return err("Insert character requires exactly one character")
  insertChar(ctx.buffer, ctx.state, args[0][0])
  Result[(), string].ok ()

proc handleBackspace*(ctx: CommandContext): Result[(), string] =
  ## Handle backspace key in insert mode
  insertBackspace(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleDelete*(ctx: CommandContext): Result[(), string] =
  ## Handle delete key in insert mode
  insertDelete(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleNewline*(ctx: CommandContext): Result[(), string] =
  ## Handle newline insertion
  insertNewline(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleQuickRun*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Run current buffer (\r command)
  ## Sets requestQuickRun flag which is handled by the main event loop
  ctx.state.requestQuickRun = true
  return ok(())

proc jumpCursorToLine*(ctx: CommandContext, line: int) =
  ## Record a jump, move the cursor to `line` at column 0, and refresh the
  ## viewport. Shared by commands that jump to non-adjacent lines (git change
  ## hunks, conflict blocks).
  recordJump(ctx.state)
  ctx.cursor = BufferPosition(line: line, column: 0)
  ctx.motionController.viewportManager.updateViewport(ctx.state, ctx.buffer, ctx.cursor)

proc findMatchContainingCursor*(
    buffer: TextBuffer,
    searchText: string,
    cursorPos: BufferPosition,
    ignorecase: bool,
    match: SearchMatch,
): Option[BufferPosition] =
  ## Return start position of a match that contains the cursor, if any.
  ## Uses findSearchMatchRanges for regex-aware match detection.
  let ranges =
    buffer.findSearchMatchRanges(cursorPos.line, searchText, ignorecase, match)
  for r in ranges:
    if (cursorPos.column >= r.startCol and cursorPos.column < r.endCol) or
        (r.startCol == r.endCol and cursorPos.column == r.startCol):
      return some(BufferPosition(line: cursorPos.line, column: r.startCol))
  return none(BufferPosition)

proc getMatchEndCol*(
    buffer: TextBuffer,
    searchText: string,
    matchStart: BufferPosition,
    ignorecase: bool,
    match: SearchMatch,
): int =
  ## Get the end column (inclusive) of a match starting at matchStart.
  let ranges =
    buffer.findSearchMatchRanges(matchStart.line, searchText, ignorecase, match)
  for r in ranges:
    if r.startCol == matchStart.column:
      return r.endCol - 1
  # Fallback: use search text char length
  return matchStart.column + searchText.charLen - 1

proc gnArea*(match: (BufferPosition, BufferPosition), forward: bool): VisualArea =
  ## The Visual area gn/gN select over `match`: like Vim's current_search, the
  ## cursor ends at the end of the match for gn and at its start for gN.
  let (first, last) = match
  if forward:
    VisualArea(start: first, cursor: last, kind: vskChar)
  else:
    VisualArea(start: last, cursor: first, kind: vskChar)

proc findGnMatch*(
    buffer: TextBuffer, state: EditorState, forward: bool, count: int
): Result[(BufferPosition, BufferPosition), string] =
  ## gn/gN: the match the cursor is in, or the next one (the one before for
  ## gN), and the `count`-th counting that one, by its first and last
  ## character. A zero-width match takes the character it stands at, the line
  ## break at the end of a line, as Vim's gn selects it.
  let spec = state.input.search.last
  let searchText = spec.pattern
  if searchText.len == 0:
    return err("E35: No previous regular expression")
  let ignoreCase = state.input.search.ignoresCase(spec)
  state.input.search.hlsearchTempDisabled = false

  # gn goes forward and gN backward, as in Vim: not the way the last search went
  let direction = if forward: Forward else: Backward
  proc step(pos: BufferPosition): Option[BufferPosition] =
    buffer.findMatch(spec, pos, ignoreCase, direction)

  var match =
    findMatchContainingCursor(buffer, searchText, state.cursor, ignoreCase, spec.match)
  if match.isNone:
    match = step(state.cursor)
  if match.isNone:
    return err("Pattern not found: " & searchText)

  let pos = stepMatches(match.get, count, step)
  let endCol = getMatchEndCol(buffer, searchText, pos, ignoreCase, spec.match)
  ok((pos, BufferPosition(line: pos.line, column: max(pos.column, endCol))))

proc registerMiscCommands*(registry: CommandRegistry) =
  ## Register mode/insert/quickrun/search/git navigation/motion.match.bracket
  ## commands.

  # QuickRun command
  registry.register(
    builtin(bcQuickRun), "QuickRun", "Run current buffer (\\r)", handleQuickRun, 0, 0
  )

  # Mode switching commands
  registry.register(
    builtin(bcModeNormal),
    "Normal Mode",
    "Switch to normal mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleModeSwitch(ctx, EditorMode.Normal),
    0,
    0,
  )

  registry.register(
    builtin(bcModeInsert),
    "Insert Mode",
    "Switch to insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleModeSwitch(ctx, EditorMode.Insert),
    0,
    0,
  )

  registry.register(
    builtin(bcModeCommand),
    "Command Mode",
    "Switch to command mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      ctx.state.enterCommandOverlay()
      ok(()),
    0,
    0,
  )

  # Insert mode character insertion
  registry.register(
    builtin(bcInsertChar),
    "Insert Character",
    "Insert a character at cursor position",
    handleInsertChar,
    1,
    1,
  )

  # Insert mode backspace
  registry.register(
    builtin(bcInsertBackspace),
    "Backspace",
    "Delete character before cursor",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleBackspace(ctx),
    0,
    0,
  )

  # Insert mode delete
  registry.register(
    builtin(bcInsertDelete),
    "Delete",
    "Delete character at cursor, or join the next line at the end",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleDelete(ctx),
    0,
    0,
  )

  # Insert mode newline
  registry.register(
    builtin(bcInsertNewline),
    "Insert Newline",
    "Insert a newline at cursor position",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleNewline(ctx),
    0,
    0,
  )

  # Insert new line below and switch to insert mode (o command)
  registry.register(
    builtin(bcInsertLineBelow),
    "Insert Line Below",
    "Insert new line below current line and switch to insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      ctx.handleInsertAt(ieOpenBelow, parseCount(args)),
    0,
    1,
  )

  # Insert new line above and switch to insert mode (O command)
  registry.register(
    builtin(bcInsertLineAbove),
    "Insert Line Above",
    "Insert new line above current line and switch to insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      ctx.handleInsertAt(ieOpenAbove, parseCount(args)),
    0,
    1,
  )

  # Append command (a) - move cursor right and enter insert mode
  registry.register(
    builtin(bcInsertAppend),
    "Append",
    "Move cursor right and enter insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      ctx.handleInsertAt(ieAppend, parseCount(args)),
    0,
    1,
  )

  # Insert at first non-blank (I)
  registry.register(
    builtin(bcInsertFirstNonBlank),
    "Insert at First Non-blank",
    "Move to the first non-blank character and enter insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      ctx.handleInsertAt(ieInsertNonBlank, parseCount(args)),
    0,
    1,
  )

  # Append at line end (A) - move to end of line and enter insert mode
  registry.register(
    builtin(bcInsertAppendEnd),
    "Append at End",
    "Move to end of line and enter insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      ctx.handleInsertAt(ieAppendEnd, parseCount(args)),
    0,
    1,
  )

  proc moveToMatch(
      ctx: CommandContext, match: Result[BufferPosition, string]
  ): Result[(), string] =
    ## Move the cursor to the match a search found.
    if match.isErr:
      return err(match.error)
    ctx.cursor = match.get
    ctx.state.openCursorFolds()
    ctx.motionController.viewportManager.updateViewport(
      ctx.state, ctx.buffer, match.get
    )
    ok(())

  proc findLastSearch(
      ctx: CommandContext, reverse: bool, count: int
  ): Result[BufferPosition, string] =
    ## n, or N when `reverse`, which jump from where the cursor was. They repeat
    ## the last search, how it matches included, so they land only on the
    ## matches the highlighter draws.
    result = ctx.state.searchLast(ctx.buffer, ctx.cursor, reverse, count)
    if result.isOk:
      recordJump(ctx.state)

  proc searchTarget(
      findMatch: proc(ctx: CommandContext, count: int): Result[BufferPosition, string]
  ): TargetFinder =
    ## A search as a motion: an operator takes up to the match, not including
    ## it (`dn`; `2dn` and `d2n` to the second match).
    proc(
        ctx: CommandContext, op: PendingOperator, count: int, countGiven: bool
    ): Result[Option[MotionTarget], string] =
      ok(some(op.searchMatchTarget(?findMatch(ctx, count))))

  proc findNextMatch(ctx: CommandContext, count: int): Result[BufferPosition, string] =
    ctx.findLastSearch(reverse = false, count)

  proc findPrevMatch(ctx: CommandContext, count: int): Result[BufferPosition, string] =
    ctx.findLastSearch(reverse = true, count)

  # Search navigation commands
  registry.register(
    custom("search.next"),
    "Search Next",
    "Repeat the last search",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      ctx.moveToMatch(ctx.findNextMatch(parseCount(args))),
    0,
    1,
  )
  registry.registerTarget("search.next", searchTarget(findNextMatch))

  registry.register(
    custom("search.prev"),
    "Search Previous",
    "Repeat the last search the other way",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      ctx.moveToMatch(ctx.findPrevMatch(parseCount(args))),
    0,
    1,
  )
  registry.registerTarget("search.prev", searchTarget(findPrevMatch))

  # Git change navigation commands
  registry.register(
    custom("navigate.git.next"),
    "Next Git Change",
    "Jump to next git change hunk",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let nextLine = ctx.buffer.findNextGitChange(ctx.cursor.line)
      if nextLine.isSome:
        jumpCursorToLine(ctx, nextLine.get)
        return Result[(), string].ok ()
      else:
        ctx.state.statusMessage = "No more git changes"
        return err("No more git changes"),
    0,
    0,
  )

  registry.register(
    custom("navigate.git.prev"),
    "Previous Git Change",
    "Jump to previous git change hunk",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let prevLine = ctx.buffer.findPrevGitChange(ctx.cursor.line)
      if prevLine.isSome:
        jumpCursorToLine(ctx, prevLine.get)
        return Result[(), string].ok ()
      else:
        ctx.state.statusMessage = "No more git changes"
        return err("No more git changes"),
    0,
    0,
  )

  # Git merge conflict block navigation commands
  registry.register(
    custom("navigate.conflict.next"),
    "Next Git Conflict",
    "Jump to next git merge conflict block",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let nxt = ctx.buffer.findNextConflict(ctx.cursor.line)
      if nxt.isSome:
        jumpCursorToLine(ctx, nxt.get.startLine)
        return Result[(), string].ok ()
      else:
        ctx.state.statusMessage = "No more git conflicts"
        return err("No more git conflicts"),
    0,
    0,
  )

  registry.register(
    custom("navigate.conflict.prev"),
    "Previous Git Conflict",
    "Jump to previous git merge conflict block",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let prv = ctx.buffer.findPrevConflict(ctx.cursor.line)
      if prv.isSome:
        jumpCursorToLine(ctx, prv.get.startLine)
        return Result[(), string].ok ()
      else:
        ctx.state.statusMessage = "No more git conflicts"
        return err("No more git conflicts"),
    0,
    0,
  )

  proc findIdentUnderCursor(
      ctx: CommandContext, forward, bounded: bool, count: int
  ): Result[BufferPosition, string] =
    ## * and # (`bounded`), g* and g#, which jump from where the cursor was.
    result = ctx.state.searchIdent(ctx.buffer, ctx.cursor, forward, bounded, count)
    if result.isOk:
      recordJump(ctx.state)

  proc registerIdentSearch(
      commandId, name, description: string, forward, bounded: bool
  ) =
    ## Register a search for the text under the cursor, as a motion too (`d*`).
    proc find(ctx: CommandContext, count: int): Result[BufferPosition, string] =
      ctx.findIdentUnderCursor(forward, bounded, count)

    registry.register(
      custom(commandId),
      name,
      description,
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        ctx.moveToMatch(ctx.find(parseCount(args))),
      0,
      1,
    )
    registry.registerTarget(commandId, searchTarget(find))

  registerIdentSearch(
    "search.word.forward",
    "Search Word Forward",
    "Search for word under cursor forward (*)",
    forward = true,
    bounded = true,
  )
  registerIdentSearch(
    "search.word.backward",
    "Search Word Backward",
    "Search for word under cursor backward (#)",
    forward = false,
    bounded = true,
  )
  registerIdentSearch(
    "search.word.forward.partial",
    "Search Word Forward Partial",
    "Search for word under cursor forward, also inside words (g*)",
    forward = true,
    bounded = false,
  )
  registerIdentSearch(
    "search.word.backward.partial",
    "Search Word Backward Partial",
    "Search for word under cursor backward, also inside words (g#)",
    forward = false,
    bounded = false,
  )

  proc matchTarget(forward: bool): TargetFinder =
    ## gn/gN as a motion: an operator takes the match the cursor is in or the
    ## next one, the `count`-th counting that one (`d2gn`), as the Visual area
    ## Vim's gn makes.
    proc(
        ctx: CommandContext, op: PendingOperator, count: int, countGiven: bool
    ): Result[Option[MotionTarget], string] =
      let match = ?findGnMatch(ctx.buffer, ctx.state, forward, count)
      let (first, last) = match
      recordJump(ctx.state)
      # Like Vim, the match is the Visual area the operator worked on, for
      # `gv`, kept before the operator runs and whether or not it succeeds.
      ctx.buffer.lastVisual = some(gnArea(match, forward))
      ok(
        some(
          MotionTarget(start: first, finish: last, motionType: mtInclusive, area: true)
        )
      )

  registry.registerTarget("search.next.select", matchTarget(forward = true))
  registry.registerTarget("search.prev.select", matchTarget(forward = false))
