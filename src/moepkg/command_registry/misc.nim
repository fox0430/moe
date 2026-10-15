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

import std/[options, strutils, unicode]

import pkg/results

import
  ../[
    types, buffer, motion, modes, search_utils, git_conflict, render_utils,
    unicode_utils,
  ]
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
  let viewportOffset = viewportOffsetFor(ctx.buffer, ctx.state)
  ctx.motionController.viewportManager.updateViewport(
    CursorPosition(x: 0, y: line),
    ctx.buffer.len,
    ctx.state.showStatusLine,
    ctx.state.motionReservedLines(),
    ctx.state.effectiveLineWrap(),
    ctx.buffer,
    viewportOffset,
    ctx.state.tabStop,
  )

proc findMatchContainingCursor*(
    buffer: TextBuffer,
    searchText: string,
    cursorPos: BufferPosition,
    ignorecase: bool,
    wholeWord: bool,
): Option[BufferPosition] =
  ## Return start position of a match that contains the cursor, if any.
  ## Uses findSearchMatchRanges for regex-aware match detection.
  let ranges =
    buffer.findSearchMatchRanges(cursorPos.line, searchText, ignorecase, wholeWord)
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
    wholeWord: bool,
): int =
  ## Get the end column (inclusive) of a match starting at matchStart.
  let ranges =
    buffer.findSearchMatchRanges(matchStart.line, searchText, ignorecase, wholeWord)
  for r in ranges:
    if r.startCol == matchStart.column:
      return r.endCol - 1
  # Fallback: use search text char length
  return matchStart.column + searchText.charLen - 1

proc stepMatches(
    first: BufferPosition,
    count: int,
    step: proc(pos: BufferPosition): Option[BufferPosition],
): BufferPosition =
  ## The match `count - 1` on from `first`, `step` finding each next one. The
  ## search wraps around, so once round the matches only what is left over the
  ## cycle matters (`999999n` does not search a million times), and a match
  ## with no other to go to is the one found again.
  result = first
  var
    left = count - 1
    taken = 0
  while left > 0:
    let next = step(result)
    if next.isNone:
      break
    result = next.get
    left -= 1
    taken += 1
    if result == first:
      left = left mod taken

proc findGnMatch*(
    buffer: TextBuffer, state: EditorState, forward: bool, count: int
): Result[(BufferPosition, BufferPosition), string] =
  ## gn/gN: the match the cursor is in, or the next one (the one before for
  ## gN), and the `count`-th counting that one, by its first and last
  ## character. A zero-width match takes the character it stands at, the line
  ## break at the end of a line, as Vim's gn selects it.
  let searchText = state.input.search.last.pattern
  if searchText.len == 0:
    return err("No previous search")
  let
    ignoreCase = shouldIgnoreCase(
      searchText, state.input.search.ignorecase, state.input.search.smartcase
    )
    wholeWord = state.input.search.last.wholeWord
  state.input.search.hlsearchTempDisabled = false

  proc step(pos: BufferPosition): Option[BufferPosition] =
    if forward:
      findNext(buffer, searchText, pos, ignoreCase, wholeWord)
    else:
      findPrev(buffer, searchText, pos, ignoreCase, wholeWord)

  var match =
    findMatchContainingCursor(buffer, searchText, state.cursor, ignoreCase, wholeWord)
  if match.isNone:
    match = step(state.cursor)
  if match.isNone:
    return err("Pattern not found: " & searchText)

  let pos = stepMatches(match.get, count, step)
  let endCol = getMatchEndCol(buffer, searchText, pos, ignoreCase, wholeWord)
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
    "Delete character at cursor",
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
    ctx.motionController.viewportManager.updateViewport(
      CursorPosition(x: match.get.column, y: match.get.line),
      ctx.buffer.len,
      ctx.state.showStatusLine,
      ctx.state.motionReservedLines(),
      ctx.state.effectiveLineWrap(),
      ctx.buffer,
      viewportOffsetFor(ctx.buffer, ctx.state),
      ctx.state.tabStop,
    )
    ok(())

  proc findLastSearch(
      ctx: CommandContext,
      searchProc: proc(
        b: TextBuffer,
        text: string,
        pos: BufferPosition,
        ignorecase: bool,
        wholeWord: bool,
      ): Option[BufferPosition],
      count: int,
  ): Result[BufferPosition, string] =
    ## The `count`-th match of the last search from the cursor, the way
    ## `searchProc` goes (n/N). They repeat the last search, whole word mode
    ## included, so they land only on the matches the highlighter draws.
    let searchText = ctx.state.input.search.last.pattern
    if searchText.len == 0:
      return err("No previous search")

    # Record jump before searching
    recordJump(ctx.state)

    # Re-enable highlight when using n/N
    ctx.state.input.search.hlsearchTempDisabled = false

    let shouldIgnoreCase = shouldIgnoreCase(
      searchText, ctx.state.input.search.ignorecase, ctx.state.input.search.smartcase
    )

    # Validate regex (whole word patterns are matched literally)
    if not ctx.state.input.search.last.wholeWord and
        compileSearchRegex(searchText, shouldIgnoreCase).isNone:
      ctx.state.statusMessage = "Invalid regex: " & searchText
      return err("Invalid regex")

    let wholeWord = ctx.state.input.search.last.wholeWord
    proc step(pos: BufferPosition): Option[BufferPosition] =
      searchProc(ctx.buffer, searchText, pos, shouldIgnoreCase, wholeWord)

    let found = step(ctx.cursor)
    if found.isNone:
      ctx.state.statusMessage = "Pattern not found: " & searchText
      return err("Pattern not found")

    ctx.state.statusMessage = "Found: " & searchText
    ok(stepMatches(found.get, count, step))

  proc searchTarget(
      findMatch: proc(ctx: CommandContext, count: int): Result[BufferPosition, string]
  ): TargetFinder =
    ## A search as a motion: an operator takes up to the match, not including
    ## it (`dn`; `2dn` and `d2n` to the second match).
    proc(
        ctx: CommandContext, op: PendingOperator, count: int, countGiven: bool
    ): Result[Option[MotionTarget], string] =
      let match = ?findMatch(ctx, count)
      ok(
        some(
          MotionTarget(
            start: op.startPos, finish: match, motionType: mtExclusive, useRegOne: true
          )
        )
      )

  proc findNextMatch(ctx: CommandContext, count: int): Result[BufferPosition, string] =
    ctx.findLastSearch(findNext, count)

  proc findPrevMatch(ctx: CommandContext, count: int): Result[BufferPosition, string] =
    ctx.findLastSearch(findPrev, count)

  # Search navigation commands
  registry.register(
    custom("search.next"),
    "Search Next",
    "Find next occurrence of last search",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      ctx.moveToMatch(ctx.findNextMatch(1)),
    0,
    0,
  )
  registry.registerTarget("search.next", searchTarget(findNextMatch))

  registry.register(
    custom("search.prev"),
    "Search Previous",
    "Find previous occurrence of last search",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      ctx.moveToMatch(ctx.findPrevMatch(1)),
    0,
    0,
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

  # Helper type for word bounds
  type WordInfo = object
    word: string
    startCol: int
    endCol: int

  proc getWordInfoUnderCursor(
      buffer: TextBuffer, cursor: BufferPosition
  ): Option[WordInfo] =
    if cursor.line < 0 or cursor.line >= buffer.len:
      return none(WordInfo)

    let line = buffer.getLine(cursor.line)
    if line.len == 0 or cursor.column >= line.charLen:
      return none(WordInfo)

    let runes = line.toCharRunes()
    if cursor.column >= runes.len:
      return none(WordInfo)

    # Check if cursor is on a word character
    let charAtCursor = $runes[cursor.column]
    if not (charAtCursor[0].isAlphaNumeric or charAtCursor[0] == '_'):
      return none(WordInfo)

    # Find word start
    var startCol = cursor.column
    while startCol > 0:
      let ch = $runes[startCol - 1]
      if not (ch[0].isAlphaNumeric or ch[0] == '_'):
        break
      startCol.dec

    # Find word end
    var endCol = cursor.column
    while endCol < runes.len:
      let ch = $runes[endCol]
      if not (ch[0].isAlphaNumeric or ch[0] == '_'):
        break
      endCol.inc

    # Sliced out of the line rather than re-encoded: a byte that does not decode
    # would come back as the replacement character.
    let word = line.charSubStr(startCol, endCol - startCol)

    return some(WordInfo(word: word, startCol: startCol, endCol: endCol))

  proc findMatchingBracketAtCursor(
      buffer: TextBuffer, cursor: BufferPosition
  ): Result[BufferPosition, string] =
    ## Helper proc to find matching bracket at cursor
    if cursor.line < 0 or cursor.line >= buffer.len:
      return err("Invalid cursor position")

    let line = buffer.getLine(cursor.line)
    if line.len == 0 or cursor.column >= line.charLen:
      return err("No bracket at cursor")

    let runes = line.toCharRunes()
    if cursor.column >= runes.len:
      return err("No bracket at cursor")

    let charAtCursor = ($runes[cursor.column])[0]

    # Define bracket pairs
    const openBrackets = ['(', '[', '{', '<']
    const closeBrackets = [')', ']', '}', '>']

    var openChar, closeChar: char
    var searchForward = false

    # Check if cursor is on a bracket
    if charAtCursor in openBrackets:
      openChar = charAtCursor
      closeChar = closeBrackets[openBrackets.find(charAtCursor)]
      searchForward = true
    elif charAtCursor in closeBrackets:
      closeChar = charAtCursor
      openChar = openBrackets[closeBrackets.find(charAtCursor)]
      searchForward = false
    else:
      return err("No bracket at cursor")

    if searchForward:
      # Search forward for closing bracket
      var depth = 1
      var col = cursor.column + 1
      while col < runes.len:
        let ch = ($runes[col])[0]
        if ch == openChar:
          depth.inc
        elif ch == closeChar:
          depth.dec
          if depth == 0:
            return ok(BufferPosition(line: cursor.line, column: col))
        col.inc
    else:
      # Search backward for opening bracket
      var depth = 1
      var col = cursor.column - 1
      while col >= 0:
        let ch = ($runes[col])[0]
        if ch == closeChar:
          depth.inc
        elif ch == openChar:
          depth.dec
          if depth == 0:
            return ok(BufferPosition(line: cursor.line, column: col))
        col.dec

    return err("No matching bracket found")

  # % - Jump to matching bracket
  registry.register(
    custom("motion.match.bracket"),
    "Match Bracket",
    "Jump to matching bracket (%)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let matchResult = findMatchingBracketAtCursor(ctx.buffer, ctx.cursor)
      if matchResult.isErr:
        return err(matchResult.error)

      # Record jump before moving to matching bracket
      recordJump(ctx.state)

      ctx.cursor = matchResult.value
      return Result[(), string].ok (),
    0,
    0,
  )

  proc findWordUnderCursor(
      ctx: CommandContext, forward: bool, count: int
  ): Result[BufferPosition, string] =
    ## The `count`-th other occurrence of the word under the cursor (* and #),
    ## made the last search.
    let wordInfo = getWordInfoUnderCursor(ctx.buffer, ctx.cursor)
    if wordInfo.isNone:
      return err("No word under cursor")

    let info = wordInfo.get

    # Record jump before searching
    recordJump(ctx.state)

    # * and # search the word under the cursor with word boundaries
    ctx.state.input.search.last = SearchSpec(pattern: info.word, wholeWord: true)
    ctx.state.input.search.hlsearchTempDisabled = false

    let originalWordPos = BufferPosition(line: ctx.cursor.line, column: info.startCol)
    let ignoreCase = shouldIgnoreCase(
      info.word, ctx.state.input.search.ignorecase, ctx.state.input.search.smartcase
    )

    proc step(pos: BufferPosition): Option[BufferPosition] =
      if forward:
        findNext(ctx.buffer, info.word, pos, ignoreCase, true)
      else:
        findPrev(ctx.buffer, info.word, pos, ignoreCase, true)

    # Search from the word's end (forward) or start (backward) to skip it.
    # Wrapping back to the word under the cursor on the first step means it is
    # the only match; a later step may wrap to it (`2d*`).
    let found = step(
      BufferPosition(
        line: ctx.cursor.line, column: if forward: info.endCol else: info.startCol
      )
    )
    if found.isNone or found.get == originalWordPos:
      ctx.state.statusMessage = "Pattern not found: " & info.word
      return err("Pattern not found")

    ctx.state.statusMessage = "Found: " & info.word
    ok(stepMatches(found.get, count, step))

  proc findWordForward(
      ctx: CommandContext, count: int
  ): Result[BufferPosition, string] =
    ctx.findWordUnderCursor(forward = true, count)

  proc findWordBackward(
      ctx: CommandContext, count: int
  ): Result[BufferPosition, string] =
    ctx.findWordUnderCursor(forward = false, count)

  # * - Search word under cursor forward
  registry.register(
    custom("search.word.forward"),
    "Search Word Forward",
    "Search for word under cursor forward (*)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      ctx.moveToMatch(ctx.findWordForward(1)),
    0,
    0,
  )
  registry.registerTarget("search.word.forward", searchTarget(findWordForward))

  # # - Search word under cursor backward
  registry.register(
    custom("search.word.backward"),
    "Search Word Backward",
    "Search for word under cursor backward (#)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      ctx.moveToMatch(ctx.findWordBackward(1)),
    0,
    0,
  )
  registry.registerTarget("search.word.backward", searchTarget(findWordBackward))

  proc matchTarget(forward: bool): TargetFinder =
    ## gn/gN as a motion: an operator takes the match the cursor is in or the
    ## next one, the `count`-th counting that one (`d2gn`), as the Visual area
    ## Vim's gn makes.
    proc(
        ctx: CommandContext, op: PendingOperator, count: int, countGiven: bool
    ): Result[Option[MotionTarget], string] =
      let (first, last) = ?findGnMatch(ctx.buffer, ctx.state, forward, count)
      recordJump(ctx.state)
      # Like Vim, the match is the Visual area the operator worked on, for
      # `gv`, kept before the operator runs and whether or not it succeeds.
      ctx.buffer.lastVisual =
        some(VisualArea(start: first, cursor: last, kind: vskChar))
      ok(
        some(
          MotionTarget(start: first, finish: last, motionType: mtInclusive, area: true)
        )
      )

  registry.registerTarget("search.next.select", matchTarget(forward = true))
  registry.registerTarget("search.prev.select", matchTarget(forward = false))
