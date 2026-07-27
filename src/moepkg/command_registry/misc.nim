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

import ../[types, buffer, motion, modes, search_utils, git_conflict, render_utils]
import ../command_handlers/[insert_commands, normal_commands]

import core

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

proc handleInsertLineBelow*(ctx: CommandContext): Result[(), string] =
  ## Handle 'o' command - insert line below and enter insert mode
  let txnResult = ctx.buffer.beginTransaction("Insert line below")
  if txnResult.isErr:
    return err("Failed to begin transaction: " & txnResult.error)
  insertLineBelow(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleInsertLineAbove*(ctx: CommandContext): Result[(), string] =
  ## Handle 'O' command - insert line above and enter insert mode
  let txnResult = ctx.buffer.beginTransaction("Insert line above")
  if txnResult.isErr:
    return err("Failed to begin transaction: " & txnResult.error)
  insertLineAbove(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleAppend*(ctx: CommandContext): Result[(), string] =
  ## Handle 'a' command - move cursor right and enter insert mode
  insertAppend(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleAppendEnd*(ctx: CommandContext): Result[(), string] =
  ## Handle 'A' command - move to end of line and enter insert mode
  insertAppendEnd(ctx.buffer, ctx.state)
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
    ctx.state.windowDisplay.viewportReservedLines,
    ctx.state.lineWrap,
    ctx.buffer,
    viewportOffset,
    ctx.state.tabStop,
  )

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
      handleInsertLineBelow(ctx),
    0,
    0,
  )

  # Insert new line above and switch to insert mode (O command)
  registry.register(
    builtin(bcInsertLineAbove),
    "Insert Line Above",
    "Insert new line above current line and switch to insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleInsertLineAbove(ctx),
    0,
    0,
  )

  # Append command (a) - move cursor right and enter insert mode
  registry.register(
    builtin(bcInsertAppend),
    "Append",
    "Move cursor right and enter insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleAppend(ctx),
    0,
    0,
  )

  # Append at line end (A) - move to end of line and enter insert mode
  registry.register(
    builtin(bcInsertAppendEnd),
    "Append at End",
    "Move to end of line and enter insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleAppendEnd(ctx),
    0,
    0,
  )

  # Helper proc for executing search and updating cursor/viewport
  # Reduces code duplication between search.next and search.prev
  proc executeSearch(
      ctx: CommandContext,
      searchText: string,
      searchProc: proc(
        b: TextBuffer, text: string, pos: BufferPosition, ignorecase: bool
      ): Option[BufferPosition],
  ): Result[(), string] =
    # Apply smartcase logic
    let shouldIgnoreCase = shouldIgnoreCase(
      searchText, ctx.state.input.search.ignorecase, ctx.state.input.search.smartcase
    )

    # Validate regex
    if compileSearchRegex(searchText, shouldIgnoreCase).isNone:
      ctx.state.statusMessage = "Invalid regex: " & searchText
      return err("Invalid regex")

    # Execute the search (findNext or findPrev)
    let searchResult = searchProc(ctx.buffer, searchText, ctx.cursor, shouldIgnoreCase)

    if searchResult.isSome:
      let newPos = searchResult.get
      ctx.cursor = newPos

      # Update viewport to follow cursor
      let
        lineCount = ctx.buffer.len
        cursorPos = CursorPosition(x: newPos.column, y: newPos.line)
        viewportOffset = viewportOffsetFor(ctx.buffer, ctx.state)

      ctx.motionController.viewportManager.updateViewport(
        cursorPos, lineCount, ctx.state.showStatusLine,
        ctx.state.windowDisplay.viewportReservedLines, ctx.state.lineWrap, ctx.buffer,
        viewportOffset, ctx.state.tabStop,
      )

      ctx.state.statusMessage = "Found: " & searchText
      return Result[(), string].ok ()
    else:
      ctx.state.statusMessage = "Pattern not found: " & searchText
      return err("Pattern not found")

  # Search navigation commands
  registry.register(
    custom("search.next"),
    "Search Next",
    "Find next occurrence of last search",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      if ctx.state.input.search.lastText.len == 0:
        return err("No previous search")

      # Record jump before searching
      recordJump(ctx.state)

      # Re-enable highlight when using n/N
      ctx.state.input.search.hlsearchTempDisabled = false

      return executeSearch(ctx, ctx.state.input.search.lastText, findNext),
    0,
    0,
  )

  registry.register(
    custom("search.prev"),
    "Search Previous",
    "Find previous occurrence of last search",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      if ctx.state.input.search.lastText.len == 0:
        return err("No previous search")

      # Record jump before searching
      recordJump(ctx.state)

      # Re-enable highlight when using n/N
      ctx.state.input.search.hlsearchTempDisabled = false

      return executeSearch(ctx, ctx.state.input.search.lastText, findPrev),
    0,
    0,
  )

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

    let runes = line.toRunes()
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

    # Extract word
    var word = ""
    for i in startCol ..< endCol:
      word.add($runes[i])

    return some(WordInfo(word: word, startCol: startCol, endCol: endCol))

  # Helper proc to check if a rune is a word character
  proc isWordChar(r: Rune): bool =
    let code = int(r)
    r.isAlpha or (code >= ord('0') and code <= ord('9')) or r == Rune('_')

  proc isWholeWordMatch(buffer: TextBuffer, pos: BufferPosition, wordLen: int): bool =
    ## Helper proc to check if a match is at word boundary
    if pos.line < 0 or pos.line >= buffer.len:
      return false

    let line = buffer.getLine(pos.line)
    let runes = line.toRunes()

    # Check bounds
    if pos.column < 0 or pos.column >= runes.len:
      return false

    # Check character before match (must not be word char or at start)
    if pos.column > 0:
      if isWordChar(runes[pos.column - 1]):
        return false

    # Check character after match (must not be word char or at end)
    let endCol = pos.column + wordLen
    if endCol < runes.len:
      if isWordChar(runes[endCol]):
        return false

    return true

  proc findMatchingBracketAtCursor(
      buffer: TextBuffer, cursor: BufferPosition
  ): Result[BufferPosition, string] =
    ## Helper proc to find matching bracket at cursor
    if cursor.line < 0 or cursor.line >= buffer.len:
      return err("Invalid cursor position")

    let line = buffer.getLine(cursor.line)
    if line.len == 0 or cursor.column >= line.charLen:
      return err("No bracket at cursor")

    let runes = line.toRunes()
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

  # * - Search word under cursor forward
  registry.register(
    custom("search.word.forward"),
    "Search Word Forward",
    "Search for word under cursor forward (*)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let wordInfo = getWordInfoUnderCursor(ctx.buffer, ctx.cursor)
      if wordInfo.isNone:
        return err("No word under cursor")

      let info = wordInfo.get
      let wordLen = info.word.runeLen

      # Record jump before searching
      recordJump(ctx.state)

      # Update last search text and set whole word mode
      ctx.state.input.search.lastText = info.word
      ctx.state.input.search.hlsearchTempDisabled = false
      ctx.state.input.search.wholeWord = true

      # Remember original word position to skip it after wrap-around
      let originalWordPos = BufferPosition(line: ctx.cursor.line, column: info.startCol)

      # Search from word end position to skip current word
      var searchPos = BufferPosition(line: ctx.cursor.line, column: info.endCol)
      let ignoreCase = shouldIgnoreCase(
        info.word, ctx.state.input.search.ignorecase, ctx.state.input.search.smartcase
      )
      var wrapped = false

      # Loop until we find a whole word match
      while true:
        let searchResult = findNext(ctx.buffer, info.word, searchPos, ignoreCase)
        if searchResult.isNone:
          ctx.state.statusMessage = "Pattern not found: " & info.word
          return err("Pattern not found")

        let newPos = searchResult.get

        # Check if we've wrapped back to start
        if newPos.line < searchPos.line or
            (newPos.line == searchPos.line and newPos.column < searchPos.column):
          wrapped = true

        # Skip if this is the original word position (after wrap-around)
        if wrapped and newPos.line == originalWordPos.line and
            newPos.column == originalWordPos.column:
          ctx.state.statusMessage = "Pattern not found: " & info.word
          return err("Pattern not found")

        # Check if this is a whole word match
        if isWholeWordMatch(ctx.buffer, newPos, wordLen):
          ctx.cursor = newPos

          # Update viewport to follow cursor
          let
            lineCount = ctx.buffer.len
            cursorPos = CursorPosition(x: newPos.column, y: newPos.line)
            viewportOffset = viewportOffsetFor(ctx.buffer, ctx.state)

          ctx.motionController.viewportManager.updateViewport(
            cursorPos, lineCount, ctx.state.showStatusLine,
            ctx.state.windowDisplay.viewportReservedLines, ctx.state.lineWrap,
            ctx.buffer, viewportOffset, ctx.state.tabStop,
          )

          ctx.state.statusMessage = "Found: " & info.word
          return Result[(), string].ok ()

        # Continue searching from after this match
        searchPos = BufferPosition(line: newPos.line, column: newPos.column + 1)

      # No whole word match found
      ctx.state.statusMessage = "Pattern not found: " & info.word
      return err("Pattern not found"),
    0,
    0,
  )

  # # - Search word under cursor backward
  registry.register(
    custom("search.word.backward"),
    "Search Word Backward",
    "Search for word under cursor backward (#)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let wordInfo = getWordInfoUnderCursor(ctx.buffer, ctx.cursor)
      if wordInfo.isNone:
        return err("No word under cursor")

      let info = wordInfo.get
      let wordLen = info.word.runeLen

      # Record jump before searching
      recordJump(ctx.state)

      # Update last search text and set whole word mode
      ctx.state.input.search.lastText = info.word
      ctx.state.input.search.hlsearchTempDisabled = false
      ctx.state.input.search.wholeWord = true

      # Remember original word position to skip it after wrap-around
      let originalWordPos = BufferPosition(line: ctx.cursor.line, column: info.startCol)

      # Search from word start position to skip current word
      var searchPos = BufferPosition(line: ctx.cursor.line, column: info.startCol)
      let ignoreCase = shouldIgnoreCase(
        info.word, ctx.state.input.search.ignorecase, ctx.state.input.search.smartcase
      )
      var wrapped = false

      # Loop until we find a whole word match
      while true:
        let searchResult = findPrev(ctx.buffer, info.word, searchPos, ignoreCase)
        if searchResult.isNone:
          ctx.state.statusMessage = "Pattern not found: " & info.word
          return err("Pattern not found")

        let newPos = searchResult.get

        # Check if we've wrapped back to start
        if newPos.line > searchPos.line or
            (newPos.line == searchPos.line and newPos.column > searchPos.column):
          wrapped = true

        # Skip if this is the original word position (after wrap-around)
        if wrapped and newPos.line == originalWordPos.line and
            newPos.column == originalWordPos.column:
          ctx.state.statusMessage = "Pattern not found: " & info.word
          return err("Pattern not found")

        # Check if this is a whole word match
        if isWholeWordMatch(ctx.buffer, newPos, wordLen):
          ctx.cursor = newPos

          # Update viewport to follow cursor
          let
            lineCount = ctx.buffer.len
            cursorPos = CursorPosition(x: newPos.column, y: newPos.line)
            viewportOffset = viewportOffsetFor(ctx.buffer, ctx.state)

          ctx.motionController.viewportManager.updateViewport(
            cursorPos, lineCount, ctx.state.showStatusLine,
            ctx.state.windowDisplay.viewportReservedLines, ctx.state.lineWrap,
            ctx.buffer, viewportOffset, ctx.state.tabStop,
          )

          ctx.state.statusMessage = "Found: " & info.word
          return Result[(), string].ok ()

        # Continue searching from before this match
        searchPos = BufferPosition(line: newPos.line, column: newPos.column)

      # No whole word match found
      ctx.state.statusMessage = "Pattern not found: " & info.word
      return err("Pattern not found"),
    0,
    0,
  )
