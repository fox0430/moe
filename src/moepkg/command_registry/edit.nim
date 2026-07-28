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

## Edit operations: operator / text_object / paste / delete / substitute /
## yank / join / case / increment / decrement handlers and registration.

import std/[options, strutils, unicode]

import pkg/results

import ../[types, motion, modes, registers, logger, clipboard, unicode_utils]
import ../buffer/[core, edit, undo]

import core, operator_engine

proc firstNonBlankColumn*(line: seq[Rune]): int =
  ## Return the column of the first non-whitespace character.
  ## If the line is all whitespace, return the last valid column (Vim behavior).
  for i, r in line:
    if not r.isWhiteSpace:
      return i
  if line.len > 0:
    return line.len - 1
  return 0

proc pasteEndPos(startPos: BufferPosition, pasteText: string): BufferPosition =
  ## Position one past the last inserted rune when `pasteText` is inserted at
  ## `startPos`. Splits on '\n' so multi-line paste lands on the final inserted
  ## line instead of treating '\n' as a column-adding rune.
  let nlCount = pasteText.count('\n')
  if nlCount == 0:
    BufferPosition(line: startPos.line, column: startPos.column + pasteText.charLen)
  else:
    let lastSeg = pasteText.substr(pasteText.rfind('\n') + 1)
    BufferPosition(line: startPos.line + nlCount, column: lastSeg.charLen)

proc handlePasteAfter*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Paste text from internal register or system clipboard after cursor (p command)
  ## Mimics Vim's 'p' behavior
  ## count: number of times to paste (default: 1)

  logDebug("paste", "handlePasteAfter called with count=" & $count)
  let actualCount = max(1, count)

  # Get content from register system
  var pasteText: string
  var isFullLine: bool
  var registerEmpty: bool

  if ctx.state.pendingInput.pendingRegister.isSome and
      ctx.state.pendingInput.pendingRegister.get != '\0':
    # User specified a register with "
    let regName = ctx.state.pendingInput.pendingRegister.get
    let reg = ctx.state.registers.getRegister(regName)
    pasteText = reg.getContent()
    isFullLine = reg.isLine
    registerEmpty = reg.isEmpty
    ctx.state.pendingInput.pendingRegister = none(char)
    ctx.state.statusMessage = ""
    logDebug("paste", "Using register '" & $regName & "', length: " & $pasteText.len)
  else:
    # Use unnamed register (most recent yank/delete)
    let reg = ctx.state.registers.getNoNamedRegister()
    pasteText = reg.getContent()
    isFullLine = reg.isLine
    registerEmpty = reg.isEmpty
    logDebug("paste", "Using unnamed register, length: " & $pasteText.len)

  logDebug(
    "paste", "Paste content length: " & $pasteText.len & ", isLine=" & $isFullLine
  )

  # If register is truly empty, try system clipboard (if enabled).
  # A linewise register with a single empty line ([""]) is not empty — it
  # represents one empty line and must not trigger the clipboard fallback.
  if registerEmpty and ctx.clipboardConfig.enable:
    logDebug("paste", "Register empty, trying clipboard")
    let readResult = readFromClipboardSync(ctx.clipboardConfig.tool)
    if readResult.isErr:
      return err(
        "Nothing to paste (register empty and clipboard error: " & readResult.error & ")"
      )

    pasteText = readResult.value
    # Detect if it's a full line from clipboard
    isFullLine = pasteText.len > 0 and pasteText[^1] == '\n'
    logDebug("paste", "Got from clipboard, length: " & $pasteText.len)

  # Linewise paste of an empty line is legitimate (Vim inserts a blank line).
  if pasteText.len == 0 and not isFullLine:
    return err("Nothing to paste")

  # Begin transaction if count > 1 to group all pastes into single undo entry
  if actualCount > 1:
    let txnResult = ctx.buffer.beginTransaction("paste " & $actualCount & " times")
    if txnResult.isErr:
      return err(txnResult.error)

  # Paste count times
  var firstPastedChar: Option[BufferPosition] = none(BufferPosition)
  for i in 1 .. actualCount:
    if isFullLine:
      # Paste on new line below current line (Vim 'p' behavior for linewise yank)
      let currentLine = ctx.buffer.getLine(ctx.cursor.line)
      let pastePos = BufferPosition(line: ctx.cursor.line, column: currentLine.charLen)

      # Insert the paste content
      # Remove trailing newline from pasteText and add newline prefix
      let textToInsert =
        "\n" & pasteText.strip(leading = false, trailing = true, chars = {'\n'})
      let insertResult = ctx.buffer.insertText(pastePos, textToInsert)
      if insertResult.isErr:
        # Rollback transaction on error
        if actualCount > 1:
          discard ctx.buffer.rollbackTransaction()
        return err(insertResult.error)

      # Move cursor to the first non-whitespace character of pasted line
      ctx.cursor.line = ctx.cursor.line + 1
      ctx.cursor.column =
        firstNonBlankColumn(ctx.buffer.getLine(ctx.cursor.line).toRunes())
    else:
      # Paste after cursor position (Vim 'p' behavior for characterwise yank)
      let lineContent = ctx.buffer.getLine(ctx.cursor.line)
      var pastePos = ctx.cursor

      # Move one character right if not at end of line (only for first paste)
      if i == 1 and ctx.cursor.column < lineContent.charLen:
        pastePos.column = ctx.cursor.column + 1

      if firstPastedChar.isNone:
        firstPastedChar = some(pastePos)

      let insertResult = ctx.buffer.insertText(pastePos, pasteText)
      if insertResult.isErr:
        # Rollback transaction on error
        if actualCount > 1:
          discard ctx.buffer.rollbackTransaction()
        return err(insertResult.error)

      # Advance cursor past the inserted text so the next iteration inserts
      # immediately after it. For multi-line paste, land on the final inserted
      # line at column = last-segment charLen (not startCol + total charLen,
      # which would treat '\n' as a column-adding rune).
      let endPos = pasteEndPos(pastePos, pasteText)
      ctx.cursor.line = endPos.line
      ctx.cursor.column = endPos.column

  # Place cursor on the first character of the pasted text
  if not isFullLine and firstPastedChar.isSome:
    ctx.cursor = firstPastedChar.get

  # Commit transaction if we started one
  if actualCount > 1:
    let txnResult = ctx.buffer.commitTransaction()
    if txnResult.isErr:
      return err(txnResult.error)

  # Record this command for repeat (.)
  ctx.state.editState.lastEditCommand =
    some(LastEditCommand(kind: lecPaste, pasteCount: actualCount, pasteBefore: false))

  return Result[(), string].ok ()

proc handlePasteBefore*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Paste text from internal register or system clipboard before cursor (P command)
  ## Mimics Vim's 'P' behavior
  ## count: number of times to paste (default: 1)

  logDebug("paste", "handlePasteBefore called with count=" & $count)
  let actualCount = max(1, count)

  # Get content from register system
  var pasteText: string
  var isFullLine: bool
  var registerEmpty: bool

  if ctx.state.pendingInput.pendingRegister.isSome and
      ctx.state.pendingInput.pendingRegister.get != '\0':
    # User specified a register with "
    let regName = ctx.state.pendingInput.pendingRegister.get
    let reg = ctx.state.registers.getRegister(regName)
    pasteText = reg.getContent()
    isFullLine = reg.isLine
    registerEmpty = reg.isEmpty
    ctx.state.pendingInput.pendingRegister = none(char)
    ctx.state.statusMessage = ""
    logDebug("paste", "Using register '" & $regName & "', length: " & $pasteText.len)
  else:
    # Use unnamed register (most recent yank/delete)
    let reg = ctx.state.registers.getNoNamedRegister()
    pasteText = reg.getContent()
    isFullLine = reg.isLine
    registerEmpty = reg.isEmpty
    logDebug("paste", "Using unnamed register, length: " & $pasteText.len)

  logDebug(
    "paste", "Paste content length: " & $pasteText.len & ", isLine=" & $isFullLine
  )

  # If register is truly empty, try system clipboard (if enabled).
  # A linewise register with a single empty line ([""]) is not empty — it
  # represents one empty line and must not trigger the clipboard fallback.
  if registerEmpty and ctx.clipboardConfig.enable:
    logDebug("paste", "Register empty, trying clipboard")
    let readResult = readFromClipboardSync(ctx.clipboardConfig.tool)
    if readResult.isErr:
      return err(
        "Nothing to paste (register empty and clipboard error: " & readResult.error & ")"
      )

    pasteText = readResult.value
    # Detect if it's a full line from clipboard
    isFullLine = pasteText.len > 0 and pasteText[^1] == '\n'
    logDebug("paste", "Got from clipboard, length: " & $pasteText.len)

  # Linewise paste of an empty line is legitimate (Vim inserts a blank line).
  if pasteText.len == 0 and not isFullLine:
    return err("Nothing to paste")

  # Begin transaction if count > 1 to group all pastes into single undo entry
  if actualCount > 1:
    let txnResult = ctx.buffer.beginTransaction("paste " & $actualCount & " times")
    if txnResult.isErr:
      return err(txnResult.error)

  # Paste count times
  var firstPastedChar: Option[BufferPosition] = none(BufferPosition)
  for i in 1 .. actualCount:
    if isFullLine:
      # Paste on new line above current line (Vim 'P' behavior for linewise yank)
      let pastePos = BufferPosition(line: ctx.cursor.line, column: 0)

      # Insert the paste content
      # Remove trailing newline from pasteText and add newline suffix
      let textToInsert =
        pasteText.strip(leading = false, trailing = true, chars = {'\n'}) & "\n"
      let insertResult = ctx.buffer.insertText(pastePos, textToInsert)
      if insertResult.isErr:
        # Rollback transaction on error
        if actualCount > 1:
          discard ctx.buffer.rollbackTransaction()
        return err(insertResult.error)

      # Move cursor to the first non-whitespace character of pasted line
      ctx.cursor.column =
        firstNonBlankColumn(ctx.buffer.getLine(ctx.cursor.line).toRunes())
    else:
      # Paste at cursor position (Vim 'P' behavior for characterwise yank)
      let pastePos = ctx.cursor

      if firstPastedChar.isNone:
        firstPastedChar = some(pastePos)

      let insertResult = ctx.buffer.insertText(pastePos, pasteText)
      if insertResult.isErr:
        # Rollback transaction on error
        if actualCount > 1:
          discard ctx.buffer.rollbackTransaction()
        return err(insertResult.error)

      # Advance cursor past the inserted text so the next iteration inserts
      # immediately after it. For multi-line paste, land on the final inserted
      # line at column = last-segment charLen (not startCol + total charLen,
      # which would treat '\n' as a column-adding rune).
      let endPos = pasteEndPos(pastePos, pasteText)
      ctx.cursor.line = endPos.line
      ctx.cursor.column = endPos.column

  # Place cursor on the first character of the pasted text
  if not isFullLine and firstPastedChar.isSome:
    ctx.cursor = firstPastedChar.get

  # Commit transaction if we started one
  if actualCount > 1:
    let txnResult = ctx.buffer.commitTransaction()
    if txnResult.isErr:
      return err(txnResult.error)

  # Record this command for repeat (.)
  ctx.state.editState.lastEditCommand =
    some(LastEditCommand(kind: lecPaste, pasteCount: actualCount, pasteBefore: true))

  return Result[(), string].ok ()

proc handleDeleteChar*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Delete character(s) at cursor position (x command)
  ## count: number of characters to delete (default: 1)
  ## With autoDeleteParen enabled, deleting an opening paren also deletes matching closing paren

  logDebug("delete", "handleDeleteChar called with count=" & $count)
  let actualCount = max(1, count)
  let lineContent = ctx.buffer.getLine(ctx.cursor.line)

  # Check if we're at or past the end of the line
  if ctx.cursor.column >= lineContent.charLen:
    return err("Nothing to delete")

  # Auto-delete adjacent paren pairs only (e.g., [] () {} "" '')
  if ctx.state.autoDeleteParen and actualCount == 1:
    let cursorCol = ctx.cursor.column

    try:
      if isAdjacentPair(lineContent, cursorCol):
        let txr = withTransaction(ctx.buffer, "delete paren pair"):
          # Delete opening char, then closing char (now at same position)
          for i in 0 ..< 2:
            let delResult = ctx.buffer.deleteRange(
              BufferPosition(line: ctx.cursor.line, column: cursorCol),
              BufferPosition(line: ctx.cursor.line, column: cursorCol),
            )
            if delResult.isErr:
              return err(delResult.error)
        if txr.isErr:
          return err(txr.error)

        # Both chars were deleted, so both go in the register
        storeDeletedText(
          ctx,
          $lineContent.runeAtPos(cursorCol) & $lineContent.runeAtPos(cursorCol + 1),
          false,
        )

        let updatedLineLen = ctx.buffer.getLine(ctx.cursor.line).charLen
        if updatedLineLen > 0 and ctx.cursor.column >= updatedLineLen:
          ctx.cursor.column = updatedLineLen - 1

        return Result[(), string].ok ()
    except CatchableError:
      discard

  # Normal delete logic
  # Calculate how many characters we can actually delete
  let charsAvailable = lineContent.charLen - ctx.cursor.column
  let charsToDelete = min(actualCount, charsAvailable)

  # Extract the characters to be deleted (for yank register)
  # Get the line content and extract the substring
  let runes = lineContent.toRunes()
  var deletedText = ""
  for i in 0 ..< charsToDelete:
    let runeIdx = ctx.cursor.column + i
    if runeIdx < runes.len:
      deletedText.add($runes[runeIdx])

  if charsToDelete > 1:
    let txr = withTransaction(ctx.buffer, "delete " & $charsToDelete & " chars"):
      for i in 0 ..< charsToDelete:
        let endPos = ctx.cursor
        let delResult = ctx.buffer.deleteRange(ctx.cursor, endPos)
        if delResult.isErr:
          return err(delResult.error)
    if txr.isErr:
      return err(txr.error)
  else:
    let endPos = ctx.cursor
    let delResult = ctx.buffer.deleteRange(ctx.cursor, endPos)
    if delResult.isErr:
      return err(delResult.error)

  # Store in register only after the buffer change succeeded (registers are not
  # covered by the buffer transaction, so a rollback would not undo them)
  storeDeletedText(ctx, deletedText, false)

  ctx.state.editState.lastEditCommand = some(
    LastEditCommand(
      kind: lecDeleteChar, deleteCount: charsToDelete, deleteForward: true
    )
  )

  # Adjust cursor if it's now past the end of the line (Vim behavior)
  let newLineContent = ctx.buffer.getLine(ctx.cursor.line)
  let newLineLen = newLineContent.charLen
  if newLineLen > 0 and ctx.cursor.column >= newLineLen:
    ctx.cursor.column = newLineLen - 1

  return Result[(), string].ok ()

proc handleDeleteCharBefore*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Delete character(s) before cursor position (X command)
  ## count: number of characters to delete (default: 1)
  ## With autoDeleteParen enabled, deleting a closing paren also deletes matching opening paren

  logDebug("delete", "handleDeleteCharBefore called with count=" & $count)
  let actualCount = max(1, count)

  # Check if we're at the beginning of the line
  if ctx.cursor.column == 0:
    return err("Nothing to delete")

  let lineContent = ctx.buffer.getLine(ctx.cursor.line)

  # Auto-delete adjacent paren pairs only (e.g., [] () {} "" '')
  if ctx.state.autoDeleteParen and actualCount == 1:
    let cursorCol = ctx.cursor.column

    try:
      # X deletes char before cursor; check if char at cursorCol-1 and cursorCol form a pair
      if isAdjacentPair(lineContent, cursorCol - 1):
        let txr = withTransaction(ctx.buffer, "delete paren pair"):
          # Delete opening char, then closing char (now at same position)
          for i in 0 ..< 2:
            let delResult = ctx.buffer.deleteRange(
              BufferPosition(line: ctx.cursor.line, column: cursorCol - 1),
              BufferPosition(line: ctx.cursor.line, column: cursorCol - 1),
            )
            if delResult.isErr:
              return err(delResult.error)
        if txr.isErr:
          return err(txr.error)

        # Both chars were deleted, so both go in the register
        storeDeletedText(
          ctx,
          $lineContent.runeAtPos(cursorCol - 1) & $lineContent.runeAtPos(cursorCol),
          false,
        )
        ctx.cursor.column = cursorCol - 1

        return Result[(), string].ok ()
    except CatchableError:
      discard

  # Normal delete logic
  # Calculate how many characters we can actually delete
  let charsAvailable = ctx.cursor.column
  let charsToDelete = min(actualCount, charsAvailable)

  # Calculate the start position for deletion
  let startColumn = ctx.cursor.column - charsToDelete

  # Extract the characters to be deleted (for yank register)
  # Get the line content and extract the substring
  let runes = lineContent.toRunes()
  var deletedText = ""
  for i in 0 ..< charsToDelete:
    let runeIdx = startColumn + i
    if runeIdx < runes.len:
      deletedText.add($runes[runeIdx])

  if charsToDelete > 1:
    let txr = withTransaction(ctx.buffer, "delete " & $charsToDelete & " chars"):
      for i in 0 ..< charsToDelete:
        let startPos = BufferPosition(line: ctx.cursor.line, column: startColumn)
        let endPos = startPos
        let delResult = ctx.buffer.deleteRange(startPos, endPos)
        if delResult.isErr:
          return err(delResult.error)
    if txr.isErr:
      return err(txr.error)
  else:
    let startPos = BufferPosition(line: ctx.cursor.line, column: startColumn)
    let delResult = ctx.buffer.deleteRange(startPos, startPos)
    if delResult.isErr:
      return err(delResult.error)

  # Store in register only after the buffer change succeeded (registers are not
  # covered by the buffer transaction, so a rollback would not undo them)
  storeDeletedText(ctx, deletedText, false)

  # Move cursor to the position where deletion started
  ctx.cursor.column = startColumn

  # Record this command for repeat (.)
  ctx.state.editState.lastEditCommand = some(
    LastEditCommand(
      kind: lecDeleteChar, deleteCount: charsToDelete, deleteForward: false
    )
  )

  return Result[(), string].ok ()

proc handleSubstituteChar*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Substitute character(s) at cursor position (s command)
  ## Deletes character(s) and enters Insert mode
  ## count: number of characters to substitute (default: 1)

  logDebug("substitute", "handleSubstituteChar called with count=" & $count)
  let actualCount = max(1, count)
  let lineContent = ctx.buffer.getLine(ctx.cursor.line)

  # Check if we're at or past the end of the line
  if ctx.cursor.column >= lineContent.charLen:
    # At end of line, just enter insert mode
    ctx.state.mode = EditorMode.Insert
    let transactionResult = ctx.buffer.beginTransaction("Substitute")
    if transactionResult.isErr:
      return err("Failed to begin transaction: " & transactionResult.error)
    ctx.state.statusMessage = "-- INSERT --"
    return Result[(), string].ok ()

  # Calculate how many characters we can actually delete
  let charsAvailable = lineContent.charLen - ctx.cursor.column
  let charsToDelete = min(actualCount, charsAvailable)

  # Extract the characters to be deleted (for yank register)
  let runes = lineContent.toRunes()
  var deletedText = ""
  for i in 0 ..< charsToDelete:
    let runeIdx = ctx.cursor.column + i
    if runeIdx < runes.len:
      deletedText.add($runes[runeIdx])

  # Begin transaction for delete + insert mode (all in one undo unit)
  let txnResult =
    ctx.buffer.beginTransaction("substitute " & $charsToDelete & " char(s)")
  if txnResult.isErr:
    return err(txnResult.error)

  # Delete the characters
  for i in 0 ..< charsToDelete:
    let endPos = ctx.cursor
    let delResult = ctx.buffer.deleteRange(ctx.cursor, endPos)
    if delResult.isErr:
      discard ctx.buffer.rollbackTransaction()
      return err(delResult.error)

  # Store in register only after the buffer change succeeded (registers are not
  # covered by the buffer transaction, so a rollback would not undo them)
  storeDeletedText(ctx, deletedText, false)

  # Enter Insert mode (transaction remains open for insert mode input)
  ctx.state.mode = EditorMode.Insert

  # Record substitute context so Insert mode exit can properly record the command
  ctx.state.editState.substituteContext =
    some(SubstituteContext(kind: skChar, deleteCount: charsToDelete))

  ctx.state.statusMessage = "-- INSERT --"
  return Result[(), string].ok ()

proc handleSubstituteLine*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Substitute line(s) (S command or cc)
  ## Deletes line content and enters Insert mode
  ## count: number of lines to substitute (default: 1)

  logDebug("substitute", "handleSubstituteLine called with count=" & $count)
  let actualCount = max(1, count)
  let startLine = ctx.cursor.line
  let endLine = min(startLine + actualCount - 1, ctx.buffer.len - 1)

  # Extract lines for yank register
  var text = ""
  for lineIdx in startLine .. endLine:
    if lineIdx < ctx.buffer.len:
      let lineContent = ctx.buffer.getLine(lineIdx)
      text.add(lineContent)
      if lineContent.len == 0 or lineContent[^1] != '\n':
        text.add("\n")

  # Get indent from first line (for auto-indent)
  let firstLine = ctx.buffer.getLine(startLine)
  var indent = ""
  for rune in firstLine.toRunes():
    let ch = $rune
    if ch == " " or ch == "\t":
      indent.add(ch)
    else:
      break

  # Begin transaction for all substitute operations (delete + insert mode input)
  let transactionResult = ctx.buffer.beginTransaction("Substitute line")
  if transactionResult.isErr:
    return err("Failed to begin transaction: " & transactionResult.error)

  # Delete all but first line
  for i in 0 ..< (endLine - startLine):
    if startLine + 1 < ctx.buffer.len:
      let deleteResult = ctx.buffer.deleteLine(startLine + 1)
      if deleteResult.isErr:
        discard ctx.buffer.rollbackTransaction()
        return err("Failed to delete line: " & deleteResult.error)

  # Clear the first line but preserve indent
  if startLine < ctx.buffer.len:
    let line = ctx.buffer.getLine(startLine)
    # Delete all characters in the line
    for i in 0 ..< line.charLen:
      let deleteResult = ctx.buffer.deleteRange(
        BufferPosition(line: startLine, column: 0),
        BufferPosition(line: startLine, column: 0),
      )
      if deleteResult.isErr:
        discard ctx.buffer.rollbackTransaction()
        return err("Failed to clear line: " & deleteResult.error)

    # Insert indent if auto-indent is enabled
    if ctx.state.autoIndent and indent.len > 0:
      let insertResult =
        ctx.buffer.insertText(BufferPosition(line: startLine, column: 0), indent)
      if insertResult.isErr:
        discard ctx.buffer.rollbackTransaction()
        return err("Failed to insert indent: " & insertResult.error)

  # Store in register only after the buffer change succeeded (registers are not
  # covered by the buffer transaction, so a rollback would not undo them)
  storeDeletedText(ctx, text, true)

  # Move cursor to beginning of line (after indent)
  ctx.cursor.line = startLine
  ctx.cursor.column = indent.len

  # Enter Insert mode (transaction remains open for insert mode input)
  ctx.state.mode = EditorMode.Insert

  # Record substitute context so Insert mode exit can properly record the command
  let lineCount = endLine - startLine + 1
  ctx.state.editState.substituteContext =
    some(SubstituteContext(kind: skLine, deleteCount: lineCount))

  ctx.state.statusMessage = "-- INSERT --"
  return Result[(), string].ok ()

proc handleToggleCase*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Toggle case of character(s) at cursor position (~ command)
  ## Changes uppercase to lowercase and vice versa, then moves cursor right
  ## count: number of characters to toggle (default: 1)

  logDebug("toggle", "handleToggleCase called with count=" & $count)
  let actualCount = max(1, count)
  let lineContent = ctx.buffer.getLine(ctx.cursor.line)

  # Check if we're at or past the end of the line
  if ctx.cursor.column >= lineContent.charLen:
    return err("Nothing to toggle")

  # Calculate how many characters we can actually toggle
  let charsAvailable = lineContent.charLen - ctx.cursor.column
  let charsToToggle = min(actualCount, charsAvailable)

  let txr = withTransaction(ctx.buffer, "toggle " & $charsToToggle & " char(s)"):
    let runes = lineContent.toRunes()
    for i in 0 ..< charsToToggle:
      let runeIdx = ctx.cursor.column + i
      if runeIdx < runes.len:
        let originalChar = $runes[runeIdx]

        var toggledChar: string
        if originalChar == originalChar.toUpperAscii():
          toggledChar = originalChar.toLowerAscii()
        else:
          toggledChar = originalChar.toUpperAscii()

        if originalChar != toggledChar:
          let pos = BufferPosition(line: ctx.cursor.line, column: ctx.cursor.column + i)

          let delResult = ctx.buffer.deleteRange(pos, pos)
          if delResult.isErr:
            return err(delResult.error)

          let insResult = ctx.buffer.insertText(pos, toggledChar)
          if insResult.isErr:
            return err(insResult.error)
  if txr.isErr:
    return err(txr.error)

  # Move cursor to the right by the number of characters toggled
  ctx.cursor.column += charsToToggle

  # Keep cursor within line bounds (in Normal mode, cursor can't be on newline)
  let finalLineContent = ctx.buffer.getLine(ctx.cursor.line)
  if ctx.cursor.column >= finalLineContent.charLen:
    ctx.cursor.column = max(0, finalLineContent.charLen - 1)

  # Record this command for repeat (.)
  ctx.state.editState.lastEditCommand =
    some(LastEditCommand(kind: lecToggleCase, toggleCaseCount: charsToToggle))

  return Result[(), string].ok ()

proc handleDeleteLine*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Delete current line(s) and store in yank register (dd command)
  ## count: number of lines to delete (default: 1)

  logDebug("delete", "handleDeleteLine called with count=" & $count)
  let actualCount = max(1, count)
  let startLine = ctx.cursor.line
  let endLine = min(startLine + actualCount - 1, ctx.buffer.len - 1)

  # Build text from lines to be deleted (for yank register)
  var deletedText = ""
  for lineIdx in startLine .. endLine:
    if lineIdx < ctx.buffer.len:
      let lineContent = ctx.buffer.getLine(lineIdx)
      deletedText.add(lineContent)
      if lineIdx < endLine or (lineContent.len > 0 and lineContent[^1] != '\n'):
        deletedText.add("\n")

  let txr = withTransaction(ctx.buffer, "Delete " & $actualCount & " line(s)"):
    var brokeEarly = false
    for i in 1 .. actualCount:
      if startLine < ctx.buffer.len:
        if ctx.buffer.len == 1:
          brokeEarly = true
          break
        let delResult = ctx.buffer.deleteLine(startLine)
        if delResult.isErr:
          return err(delResult.error)

    if brokeEarly:
      let lastLine = ctx.buffer.getLine(0)
      if lastLine.len > 0:
        let clearResult = ctx.buffer.deleteRange(
          BufferPosition(line: 0, column: 0),
          BufferPosition(line: 0, column: lastLine.charLen - 1),
        )
        if clearResult.isErr:
          return err(clearResult.error)
  if txr.isErr:
    return err("Transaction failed: " & txr.error)

  # Store in register only after the buffer change succeeded (registers are not
  # covered by the buffer transaction, so a rollback would not undo them)
  storeDeletedText(ctx, deletedText, true)

  # Adjust cursor position if needed
  if ctx.cursor.line >= ctx.buffer.len:
    ctx.cursor.line = max(0, ctx.buffer.len - 1)
  # Preserve column position, clamped to end of new current line
  let newLine = ctx.buffer.getLine(ctx.cursor.line)
  if newLine.charLen > 0:
    ctx.cursor.column = min(ctx.cursor.column, newLine.charLen - 1)
  else:
    ctx.cursor.column = 0

  # Record this command for repeat (.)
  ctx.state.editState.lastEditCommand =
    some(LastEditCommand(kind: lecDeleteLine, deleteLineCount: actualCount))

  # Delete screen notification (controlled by config)
  if ctx.notificationConfig.screenNotifications and
      ctx.notificationConfig.deleteScreenNotify:
    ctx.notify("Deleted " & $actualCount & " line(s)")

  # Delete log notification (controlled by config)
  if ctx.notificationConfig.logNotifications and ctx.notificationConfig.deleteLogNotify:
    logInfo("delete", "Deleted " & $actualCount & " line(s)")

  return Result[(), string].ok ()

proc handleYankLine*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Yank (copy) the current line(s) to internal register and optionally to system clipboard
  ## count: number of lines to yank (default: 1)

  logDebug("yank", "handleYankLine called with count=" & $count)
  let actualCount = max(1, count) # Ensure at least 1 line
  logDebug("yank", "actualCount=" & $actualCount)
  let startLine = ctx.cursor.line
  let endLine = min(startLine + actualCount - 1, ctx.buffer.len - 1)

  # Build text from multiple lines
  var yankText = ""
  for lineIdx in startLine .. endLine:
    if lineIdx < ctx.buffer.len:
      let lineContent = ctx.buffer.getLine(lineIdx)
      yankText.add(lineContent)
      # Add newline if not the last line or if the line itself doesn't end with one
      if lineIdx < endLine or (lineContent.len > 0 and lineContent[^1] != '\n'):
        yankText.add("\n")

  # Debug: log the yanked text
  logDebug(
    "yank", "Yanking " & $actualCount & " line(s), total length: " & $yankText.len
  )
  logDebug("yank", "Yanked text: '" & yankText & "'")

  # An empty yankText here means a single empty line was yanked — still valid
  # in Vim (the register holds one blank line, pasteable via p/P).
  # Store in register system (respects pendingRegister)
  storeYankedText(ctx, yankText, true)

  let storedReg = ctx.state.registers.getNoNamedRegister()
  logDebug(
    "yank",
    "Stored in register: '" & storedReg.getContent() & "', isLine=" & $storedReg.isLine,
  )

  # Yank screen notification (controlled by config)
  if ctx.notificationConfig.screenNotifications and
      ctx.notificationConfig.yankScreenNotify:
    ctx.notify("Yanked " & $actualCount & " line(s)")

  # Yank log notification (controlled by config)
  if ctx.notificationConfig.logNotifications and ctx.notificationConfig.yankLogNotify:
    logInfo("yank", "Yanked " & $actualCount & " line(s)")

  return Result[(), string].ok ()

proc handleJoinLines*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Join lines starting from current line (J command)
  ## count: number of additional lines to join (default: 1, meaning join 2 lines total)
  ## Example: count=1 joins current and next line, count=2 joins 3 lines, etc.

  logDebug("join", "handleJoinLines called with count=" & $count)
  let actualCount = max(1, count)

  # Join lines using the buffer's joinLines function
  let joinResult = ctx.buffer.joinLines(ctx.cursor.line, actualCount)
  if joinResult.isErr:
    return err(joinResult.error)

  # Record this command for repeat (.)
  ctx.state.editState.lastEditCommand =
    some(LastEditCommand(kind: lecJoinLines, joinLinesCount: actualCount))

  let totalLines = actualCount + 1
  ctx.state.statusMessage = "Joined " & $totalLines & " line(s)"
  return Result[(), string].ok ()

proc handleShowCharInfo*(ctx: CommandContext): Result[(), string] =
  ## Show ASCII/Unicode value of character under cursor (ga command)
  ## Displays character info in status message

  logDebug("charinfo", "handleShowCharInfo called")
  let lineContent = ctx.buffer.getLine(ctx.cursor.line)

  # Check if cursor is at valid position
  if ctx.cursor.column >= lineContent.charLen:
    ctx.state.statusMessage = "No character under cursor"
    return Result[(), string].ok ()

  # Get the character at cursor position
  let runes = lineContent.toRunes()
  if ctx.cursor.column < runes.len:
    let ch = runes[ctx.cursor.column]
    let codepoint = ch.int32

    # Format the message like Vim: <c>  123,  Hex 7b,  Oct 173
    var msg = "<" & $ch & ">"
    msg &= "  " & $codepoint & ","
    msg &= "  Hex " & toHex(codepoint, 2) & ","
    msg &= "  Oct " & toOct(codepoint, 3)

    ctx.state.statusMessage = msg
  else:
    ctx.state.statusMessage = "No character under cursor"

  return Result[(), string].ok ()

proc handleOperatorYank*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Yank operator - waits for motion (y2w, y$, etc.) or yy for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (yy for yank line)
  if ctx.state.pendingInput.pendingOperator.isSome and
      ctx.state.pendingInput.pendingOperator.get.operatorType == OpYank:
    # Execute line yank
    let startLine = ctx.cursor.line
    let operatorCount = ctx.state.pendingInput.pendingOperator.get.operatorCount
    let endLine = min(startLine + operatorCount - 1, ctx.buffer.len - 1)

    # Extract lines for yank register
    var text = ""
    for lineIdx in startLine .. endLine:
      if lineIdx < ctx.buffer.len:
        let lineContent = ctx.buffer.getLine(lineIdx)
        text.add(lineContent)
        if lineContent.len == 0 or lineContent[^1] != '\n':
          text.add("\n")

    # Store in register system (respects pendingRegister)
    storeYankedText(ctx, text, true)

    # Clear operator state
    ctx.state.pendingInput.pendingOperator = none(PendingOperator)
    let lineCount = endLine - startLine + 1
    # Yank screen notification (controlled by config)
    if ctx.notificationConfig.screenNotifications and
        ctx.notificationConfig.yankScreenNotify:
      ctx.notify("Yanked " & $lineCount & " line(s)")
    # Yank log notification (controlled by config)
    if ctx.notificationConfig.logNotifications and ctx.notificationConfig.yankLogNotify:
      logInfo("yank", "Yanked " & $lineCount & " line(s)")
    return ok(())
  else:
    # Set pending operator for motion
    setPendingOperator(ctx, OpYank, count, "y")
    return ok(())

proc handleOperatorDelete*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Delete operator - waits for motion (d2w, d$, etc.) or dd for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (dd for delete line)
  if ctx.state.pendingInput.pendingOperator.isSome and
      ctx.state.pendingInput.pendingOperator.get.operatorType == OpDelete:
    # Execute line deletion
    let startLine = ctx.cursor.line
    let operatorCount = ctx.state.pendingInput.pendingOperator.get.operatorCount
    let endLine = min(startLine + operatorCount - 1, ctx.buffer.len - 1)
    let lineCount = endLine - startLine + 1

    var text = ""
    for lineIdx in startLine .. endLine:
      if lineIdx < ctx.buffer.len:
        let lineContent = ctx.buffer.getLine(lineIdx)
        text.add(lineContent)
        if lineContent.len == 0 or lineContent[^1] != '\n':
          text.add("\n")

    let txr = withTransaction(ctx.buffer, "Delete " & $lineCount & " line(s)"):
      var brokeEarly = false
      for i in 0 ..< lineCount:
        if startLine < ctx.buffer.len:
          if ctx.buffer.len == 1:
            brokeEarly = true
            break
          let deleteResult = ctx.buffer.deleteLine(startLine)
          if deleteResult.isErr:
            return err("Failed to delete line: " & deleteResult.error)

      if brokeEarly:
        let lastLine = ctx.buffer.getLine(0)
        if lastLine.len > 0:
          let clearResult = ctx.buffer.deleteRange(
            BufferPosition(line: 0, column: 0),
            BufferPosition(line: 0, column: lastLine.charLen - 1),
          )
          if clearResult.isErr:
            return err("Failed to clear last line: " & clearResult.error)
    if txr.isErr:
      return err("Transaction failed: " & txr.error)

    # Store in register only after the buffer change succeeded (registers are not
    # covered by the buffer transaction, so a rollback would not undo them)
    storeDeletedText(ctx, text, true)

    # Move cursor to start line, preserve column position
    ctx.cursor.line = min(startLine, ctx.buffer.len - 1)
    # Preserve column position, clamped to end of new current line
    let newLine = ctx.buffer.getLine(ctx.cursor.line)
    if newLine.charLen > 0:
      ctx.cursor.column = min(ctx.cursor.column, newLine.charLen - 1)
    else:
      ctx.cursor.column = 0

    # Record this command for repeat (.)
    ctx.state.editState.lastEditCommand =
      some(LastEditCommand(kind: lecDeleteLine, deleteLineCount: lineCount))

    # Clear operator state
    ctx.state.pendingInput.pendingOperator = none(PendingOperator)
    # Delete screen notification (controlled by config)
    if ctx.notificationConfig.screenNotifications and
        ctx.notificationConfig.deleteScreenNotify:
      ctx.notify("Deleted " & $lineCount & " line(s)")
    # Delete log notification (controlled by config)
    if ctx.notificationConfig.logNotifications and ctx.notificationConfig.deleteLogNotify:
      logInfo("delete", "Deleted " & $lineCount & " line(s)")
    return ok(())
  else:
    # Set pending operator for motion
    setPendingOperator(ctx, OpDelete, count, "d")
    return ok(())

proc handleOperatorChange*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Change operator - waits for motion (c2w, c$, etc.) or cc for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (cc for change line)
  if ctx.state.pendingInput.pendingOperator.isSome and
      ctx.state.pendingInput.pendingOperator.get.operatorType == OpChange:
    # Execute line change using handleSubstituteLine (same as S command)
    let operatorCount = ctx.state.pendingInput.pendingOperator.get.operatorCount
    # Clear operator state before calling handleSubstituteLine
    ctx.state.pendingInput.pendingOperator = none(PendingOperator)
    return handleSubstituteLine(ctx, operatorCount)
  else:
    # Set pending operator for motion
    setPendingOperator(ctx, OpChange, count, "c")
    return ok(())

proc handleOperatorOnLines*(
    ctx: CommandContext, operatorType: OperatorType, count: int = 1
): Result[(), string] =
  ## Apply a doubled operator (>>, <<, guu, gUU) to whole lines and record it
  ## for repeat (.)
  ## operatorType: OpIndent, OpOutdent, OpLowerCase or OpUpperCase
  ## count: number of lines (default: 1)

  let
    lineCount = max(1, count)
    startLine = ctx.cursor.line
    endLine = min(startLine + lineCount - 1, ctx.buffer.len - 1)
    range = OperatorRange(
      start: BufferPosition(line: startLine, column: 0),
      endPos: BufferPosition(line: endLine, column: 0),
      isLinewise: true,
    )

  let opResult = executeOperatorOnRange(ctx, operatorType, range, 1)
  if opResult.isErr:
    return opResult

  # Record this command for repeat (.)
  ctx.state.editState.lastEditCommand = some(
    LastEditCommand(
      kind: lecOperatorLines, linesOperator: operatorType, operatorLineCount: lineCount
    )
  )

  return ok(())

proc handleOperatorIndent*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Indent operator - waits for motion (>2w, >$, etc.) or >> for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (>> for indent line)
  if ctx.state.pendingInput.pendingOperator.isSome and
      ctx.state.pendingInput.pendingOperator.get.operatorType == OpIndent:
    # Counts on both halves multiply (2>3> == 6 lines)
    let lineCount =
      ctx.state.pendingInput.pendingOperator.get.operatorCount * max(1, count)
    ctx.state.pendingInput.pendingOperator = none(PendingOperator)
    return handleOperatorOnLines(ctx, OpIndent, lineCount)
  else:
    # Set pending operator for motion
    setPendingOperator(ctx, OpIndent, count, ">")
    return ok(())

proc handleOperatorOutdent*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Outdent operator - waits for motion (<2w, <$, etc.) or << for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (<< for dedent line)
  if ctx.state.pendingInput.pendingOperator.isSome and
      ctx.state.pendingInput.pendingOperator.get.operatorType == OpOutdent:
    # Counts on both halves multiply (2<3< == 6 lines)
    let lineCount =
      ctx.state.pendingInput.pendingOperator.get.operatorCount * max(1, count)
    ctx.state.pendingInput.pendingOperator = none(PendingOperator)
    return handleOperatorOnLines(ctx, OpOutdent, lineCount)
  else:
    # Set pending operator for motion
    setPendingOperator(ctx, OpOutdent, count, "<")
    return ok(())

proc handleOperatorLowerCase*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Lowercase operator - waits for motion (guw, gu$, etc.) or guu/gugu for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (guu / gugu for lowercase line)
  if ctx.state.pendingInput.pendingOperator.isSome and
      ctx.state.pendingInput.pendingOperator.get.operatorType == OpLowerCase:
    # Counts on both halves multiply (2gu3u == 6 lines)
    let lineCount =
      ctx.state.pendingInput.pendingOperator.get.operatorCount * max(1, count)
    ctx.state.pendingInput.pendingOperator = none(PendingOperator)
    return handleOperatorOnLines(ctx, OpLowerCase, lineCount)
  else:
    # Set pending operator for motion
    setPendingOperator(ctx, OpLowerCase, count, "gu")
    return ok(())

proc handleOperatorUpperCase*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Uppercase operator - waits for motion (gUw, gU$, etc.) or gUU/gUgU for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (gUU / gUgU for uppercase line)
  if ctx.state.pendingInput.pendingOperator.isSome and
      ctx.state.pendingInput.pendingOperator.get.operatorType == OpUpperCase:
    # Counts on both halves multiply (2gU3U == 6 lines)
    let lineCount =
      ctx.state.pendingInput.pendingOperator.get.operatorCount * max(1, count)
    ctx.state.pendingInput.pendingOperator = none(PendingOperator)
    return handleOperatorOnLines(ctx, OpUpperCase, lineCount)
  else:
    # Set pending operator for motion
    setPendingOperator(ctx, OpUpperCase, count, "gU")
    return ok(())

## Text object command handlers

proc handleTextObjectInner*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Handle inner text object (iw, i", i(, etc.) or enter Insert mode.
  ## `count` is the [count] prefix; when this resolves to plain `i` it requests
  ## the typed text be replayed (count - 1) more times on Insert-mode exit.

  # Check if we have a pending operator
  if ctx.state.pendingInput.pendingOperator.isSome:
    # We have a pending operator - set text object modifier
    let operatorCount = ctx.state.pendingInput.pendingOperator.get.operatorCount
    ctx.state.pendingInput.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: operatorCount))
    ctx.state.statusMessage =
      $ctx.state.pendingInput.pendingOperator.get.operatorType & "i"
    return ok(())
  elif isVisualAllMode(ctx.state.mode):
    # In Visual mode - set text object modifier for visual selection
    ctx.state.pendingInput.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    return ok(())
  else:
    # No pending operator - enter Insert mode
    if ctx.buffer.readOnly:
      ctx.state.statusMessage = "Buffer is read-only"
      return ok(())
    ctx.state.mode = EditorMode.Insert
    # Begin transaction for insert mode edit (guard for insert-normal mode)
    if not ctx.buffer.inTransaction:
      let transactionResult = ctx.buffer.beginTransaction("Insert mode edit")
      if transactionResult.isErr:
        return err("Failed to begin transaction: " & transactionResult.error)
    # Track the insert origin and [count] so the typed text can be replayed
    # (count - 1) more times when Insert mode is left, matching Vim's [count]i.
    ctx.state.editState.insertModeStartPos = some(ctx.cursor)
    ctx.state.editState.insertReplayCount = max(1, count)
    ctx.state.editState.insertReplayLineEntry = false
    ctx.state.statusMessage = "-- INSERT --"
    return ok(())

proc handleTextObjectAround*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Handle around text object (aw, a", a(, etc.) or enter Append mode.
  ## `count` is the [count] prefix; when this resolves to plain `a` it requests
  ## the typed text be replayed (count - 1) more times on Insert-mode exit.

  # Check if we have a pending operator
  if ctx.state.pendingInput.pendingOperator.isSome:
    # We have a pending operator - set text object modifier
    let operatorCount = ctx.state.pendingInput.pendingOperator.get.operatorCount
    ctx.state.pendingInput.pendingTextObject =
      some(PendingTextObject(modifier: tomAround, operatorCount: operatorCount))
    ctx.state.statusMessage =
      $ctx.state.pendingInput.pendingOperator.get.operatorType & "a"
    return ok(())
  elif isVisualAllMode(ctx.state.mode):
    # In Visual mode - set text object modifier for visual selection
    ctx.state.pendingInput.pendingTextObject =
      some(PendingTextObject(modifier: tomAround, operatorCount: 1))
    return ok(())
  else:
    # No pending operator - enter Append mode (move cursor right, then Insert)
    if ctx.buffer.readOnly:
      ctx.state.statusMessage = "Buffer is read-only"
      return ok(())
    # Move cursor one position to the right if not at end of line
    if ctx.cursor.line < ctx.buffer.len:
      let currentLine = ctx.buffer.getLine(ctx.cursor.line)
      # Use charLen for proper multi-byte character support
      if ctx.cursor.column < currentLine.charLen:
        ctx.cursor.column += 1
    # Enter Insert mode
    ctx.state.mode = EditorMode.Insert
    # Begin transaction for insert mode edit (guard for insert-normal mode)
    if not ctx.buffer.inTransaction:
      let transactionResult = ctx.buffer.beginTransaction("Append mode edit")
      if transactionResult.isErr:
        return err("Failed to begin transaction: " & transactionResult.error)
    # Track the append origin and [count] so the typed text can be replayed
    # (count - 1) more times when Insert mode is left, matching Vim's [count]a.
    ctx.state.editState.insertModeStartPos = some(ctx.cursor)
    ctx.state.editState.insertReplayCount = max(1, count)
    ctx.state.editState.insertReplayLineEntry = false
    ctx.state.statusMessage = "-- INSERT --"
    return ok(())

proc findNumberAtOrAfterColumn*(
    line: string, startCol: int
): tuple[found: bool, startPos: int, endPos: int, value: int] =
  ## Find a number at or after the given column in the line
  ## Returns (found, startPos, endPos, value) where positions are byte indices
  var col = startCol
  let lineLen = line.len

  # Skip to start column
  if col >= lineLen:
    return (false, 0, 0, 0)

  # Skip non-digit characters (but stop at digit or minus sign before digit)
  while col < lineLen:
    if line[col] >= '0' and line[col] <= '9':
      break
    elif line[col] == '-' and col + 1 < lineLen and line[col + 1] >= '0' and
        line[col + 1] <= '9':
      break
    col += 1

  if col >= lineLen:
    return (false, 0, 0, 0)

  # Found start of number
  let startPos = col
  var numStr = ""

  # Handle optional minus sign
  if line[col] == '-':
    numStr.add('-')
    col += 1

  # Collect digits
  while col < lineLen and line[col] >= '0' and line[col] <= '9':
    numStr.add(line[col])
    col += 1

  # Parse the number
  try:
    let value = parseInt(numStr)
    return (true, startPos, col - 1, value)
  except ValueError:
    return (false, 0, 0, 0)

proc handleIncrementNumber*(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## Increment the number at or after cursor (Ctrl-A command)
  if ctx.cursor.line >= ctx.buffer.len:
    return err("Cursor out of bounds")

  let line = ctx.buffer.getLine(ctx.cursor.line)
  let byteCol = charToBytePos(line, ctx.cursor.column)

  # Find number at or after cursor position (byte space)
  let (found, startPos, endPos, value) = findNumberAtOrAfterColumn(line, byteCol)

  if not found:
    return err("No number found")

  # Increment the number (saturate at high(int) to avoid overflow)
  let newValue =
    if value == high(int):
      value
    else:
      value + 1
  let newNumStr = $newValue

  # Replace the number in the line
  let newLine =
    line[0 ..< startPos] & newNumStr &
    (if endPos + 1 < line.len: line[endPos + 1 ..^ 1] else: "")

  let lineIdx = ctx.cursor.line
  let txr = withTransaction(ctx.buffer, "Increment number"):
    let delResult = ctx.buffer.deleteLine(lineIdx)
    if delResult.isErr:
      return err(delResult.error)

    let insResult = ctx.buffer.insert(lineIdx, newLine)
    if insResult.isErr:
      return err(insResult.error)
  if txr.isErr:
    return err(txr.error)

  # Move cursor to start of the number (convert byte pos to char pos)
  ctx.cursor.column = byteToCharPos(newLine, startPos)

  return ok(())

proc handleDecrementNumber*(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## Decrement the number at or after cursor (Ctrl-X command)
  if ctx.cursor.line >= ctx.buffer.len:
    return err("Cursor out of bounds")

  let line = ctx.buffer.getLine(ctx.cursor.line)
  let byteCol = charToBytePos(line, ctx.cursor.column)

  # Find number at or after cursor position (byte space)
  let (found, startPos, endPos, value) = findNumberAtOrAfterColumn(line, byteCol)

  if not found:
    return err("No number found")

  # Decrement the number (saturate at low(int) to avoid overflow)
  let newValue =
    if value == low(int):
      value
    else:
      value - 1
  let newNumStr = $newValue

  # Replace the number in the line
  let newLine =
    line[0 ..< startPos] & newNumStr &
    (if endPos + 1 < line.len: line[endPos + 1 ..^ 1] else: "")

  let lineIdx = ctx.cursor.line
  let txr = withTransaction(ctx.buffer, "Decrement number"):
    let delResult = ctx.buffer.deleteLine(lineIdx)
    if delResult.isErr:
      return err(delResult.error)

    let insResult = ctx.buffer.insert(lineIdx, newLine)
    if insResult.isErr:
      return err(insResult.error)
  if txr.isErr:
    return err(txr.error)

  # Move cursor to start of the number (convert byte pos to char pos)
  ctx.cursor.column = byteToCharPos(newLine, startPos)

  return ok(())

proc registerEditCommands*(registry: CommandRegistry) =
  ## Register all edit-category commands (delete/substitute/paste/yank/operator/text_object/increment).
  # Note: delete.word is now handled by operator+motion system (d+w)
  # The operator.delete handler sets pendingOperator, then Motion.WordForward
  # is executed, and executeOperatorOnRange is called automatically

  registry.register(
    custom("delete.line"),
    "Delete Line",
    "Delete current line(s)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleDeleteLine(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("delete.char"),
    "Delete Character",
    "Delete character(s) at cursor (x command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleDeleteChar(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("delete.char.before"),
    "Delete Character Before",
    "Delete character(s) before cursor (X command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleDeleteCharBefore(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("substitute.char"),
    "Substitute Character",
    "Substitute character(s) at cursor (s command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleSubstituteChar(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("substitute.line"),
    "Substitute Line",
    "Substitute line(s) (S command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleSubstituteLine(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("toggle.case"),
    "Toggle Case",
    "Toggle case of character(s) at cursor (~ command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleToggleCase(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("yank.line"),
    "Yank Line",
    "Yank (copy) current line(s) to clipboard",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleYankLine(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("paste.after"),
    "Paste After",
    "Paste clipboard content after cursor (p command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handlePasteAfter(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("paste.before"),
    "Paste Before",
    "Paste clipboard content before cursor (P command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handlePasteBefore(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("indent.line"),
    "Indent Line",
    "Indent current line (>> command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # Count is a line count, like vim's [count]>>
      handleOperatorOnLines(ctx, OpIndent, parseCount(args, default = 1)),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("dedent.line"),
    "Dedent Line",
    "Dedent current line (<< command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleOperatorOnLines(ctx, OpOutdent, parseCount(args, default = 1)),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("autoindent.line"),
    "Auto Indent Line",
    "Auto indent current line to match previous line (== command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let currentLine = ctx.cursor.line

      # Can't auto indent first line or empty line
      if currentLine == 0:
        return Result[(), string].ok ()

      let lineContent = ctx.buffer.getLine(currentLine)
      if lineContent.len == 0:
        return Result[(), string].ok ()

      # Get previous line indent (leading spaces and tabs)
      let prevLine = ctx.buffer.getLine(currentLine - 1)
      var prevIndent = 0
      for i in 0 ..< prevLine.len:
        if prevLine[i] == ' ' or prevLine[i] == '\t':
          inc prevIndent
        else:
          break

      # Count current line's leading whitespace
      var currentIndent = 0
      for i in 0 ..< lineContent.len:
        if lineContent[i] == ' ' or lineContent[i] == '\t':
          inc currentIndent
        else:
          break

      # No change needed if the indents are identical (compare the whitespace
      # itself, so "\t\t" vs "  " counts as a change)
      if prevLine[0 ..< prevIndent] == lineContent[0 ..< currentIndent]:
        return Result[(), string].ok ()

      # Create new line with correct indent (copied verbatim to keep tabs)
      var newContent = prevLine[0 ..< prevIndent]

      # Add non-whitespace content from current line
      for i in currentIndent ..< lineContent.len:
        newContent.add(lineContent[i])

      let lineStart = BufferPosition(line: currentLine, column: 0)
      let lineEnd = BufferPosition(line: currentLine, column: lineContent.charLen - 1)

      let txr = withTransaction(ctx.buffer, "auto indent line"):
        let delResult = ctx.buffer.deleteRange(lineStart, lineEnd)
        if delResult.isErr:
          return err(delResult.error)

        if newContent.len > 0:
          let insResult = ctx.buffer.insertText(lineStart, newContent)
          if insResult.isErr:
            return err(insResult.error)
      if txr.isErr:
        return err(txr.error)

      # Move cursor to first non-blank character
      ctx.cursor.column = prevIndent

      return Result[(), string].ok (),
    0,
    0, # No arguments
  )

  registry.register(
    custom("join.lines"),
    "Join Lines",
    "Join current line with next line(s) (J command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleJoinLines(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("show.char.info"),
    "Show Character Info",
    "Show ASCII/Unicode value of character under cursor (ga command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleShowCharInfo(ctx),
    0,
    0, # No arguments
  )

  # Note: change.word is now handled by operator+motion system (c+w)
  # The operator.change handler sets pendingOperator, then Motion.WordForward
  # is executed, and executeOperatorOnRange is called automatically

  # Undo/Redo commands
  proc clampCursorToBuffer(ctx: CommandContext) =
    ## Clamp cursor position to valid buffer range (delegates to CursorManager)
    let mgr = ctx.motionController.cursorManager
    let pos = CursorPosition(y: ctx.cursor.line, x: ctx.cursor.column)
    let clamped = mgr.clampPosition(pos, ctx.buffer)
    ctx.cursor = BufferPosition(line: clamped.y, column: clamped.x)

  registry.register(
    builtin(bcEditUndo),
    "Undo",
    "Undo the last change(s)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      var lastCursorPos: Option[BufferPosition] = none(BufferPosition)
      for i in 1 .. count:
        let r = ctx.buffer.undo()
        if r.isErr:
          if i == 1:
            return err(r.error)
          else:
            break # Stop if we can't undo anymore
        lastCursorPos = some(r.value)

      if lastCursorPos.isSome:
        ctx.cursor = lastCursorPos.get
        clampCursorToBuffer(ctx)

      return Result[(), string].ok (),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    builtin(bcEditRedo),
    "Redo",
    "Redo the last undone change(s)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      var lastCursorPos: Option[BufferPosition] = none(BufferPosition)
      for i in 1 .. count:
        let r = ctx.buffer.redo()
        if r.isErr:
          if i == 1:
            return err(r.error)
          else:
            break # Stop if we can't redo anymore
        lastCursorPos = some(r.value)

      if lastCursorPos.isSome:
        ctx.cursor = lastCursorPos.get
        clampCursorToBuffer(ctx)

      return Result[(), string].ok (),
    0,
    1, # Accept optional count argument
  )

  # Increment/Decrement number commands
  registry.register(
    builtin(bcEditIncrementNumber),
    "Increment Number",
    "Increment the number at or after cursor (Ctrl-A)",
    handleIncrementNumber,
    0,
    0,
  )

  registry.register(
    builtin(bcEditDecrementNumber),
    "Decrement Number",
    "Decrement the number at or after cursor (Ctrl-X)",
    handleDecrementNumber,
    0,
    0,
  )

  # Repeat last change command (.)
  registry.register(
    custom("edit.repeat"),
    "Repeat Last Change",
    "Repeat the last change command (. command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # Check if we have a last edit command
      if ctx.state.editState.lastEditCommand.isNone:
        return err("No previous change to repeat")

      let lastCmd = ctx.state.editState.lastEditCommand.get

      case lastCmd.kind
      of lecOperatorMotion:
        # Repeat operator+motion command (e.g., dw, c2w, y$)
        # Create a pending operator
        ctx.state.pendingInput.pendingOperator = some(
          PendingOperator(
            operatorType: lastCmd.operator,
            operatorCount: lastCmd.operatorCount,
            startPos: ctx.cursor,
          )
        )
        # Save viewport position for restoration after operator
        ctx.state.windowDisplay.savedViewportTopLine =
          ctx.motionController.viewportManager.viewport.topLine

        # LastLine with no prefix replays as count=0 (bare G); else combine counts.
        let effectiveCount =
          if lastCmd.motion == Motion.LastLine and not lastCmd.motionHasCount:
            0
          else:
            lastCmd.motionCount * lastCmd.operatorCount

        # f/F/t/T motions need the same no-move / till-adjacency guards as the
        # live df{char}/dt{char} path; without them a repeat whose target is
        # missing from the new cursor position would delete a spurious char.
        if lastCmd.motion in {
          Motion.FindChar, Motion.FindCharBackward, Motion.TillChar,
          Motion.TillCharBackward,
        }:
          ctx.state.pendingInput.pendingOperator = none(PendingOperator)
          let endOpt = findTillOperatorEndPos(
            ctx, lastCmd.motion, lastCmd.targetChar, effectiveCount, ctx.cursor
          )
          if endOpt.isNone:
            # Target not found from here - the repeat is a no-op.
            return ok(())
          return applyOperatorOverMotion(
            ctx, lastCmd.operator, lastCmd.operatorCount, ctx.cursor, endOpt.get,
            lastCmd.motion,
          )

        let motionCmd = MotionCommand(
          motion: lastCmd.motion, targetChar: lastCmd.targetChar, count: effectiveCount
        )
        let r = ctx.motionController.executeMotion(
          motionCmd, ctx.cursor, updateViewport = false
        )
        if r.isErr:
          ctx.state.pendingInput.pendingOperator = none(PendingOperator)
          return err(r.error)

        # Mirrors the live operator+motion no-move guard (dh/dj/dk at boundary).
        if r.value == ctx.cursor and lastCmd.motion in NoMoveNoOpMotions:
          ctx.state.pendingInput.pendingOperator = none(PendingOperator)
          return ok(())

        # Apply the operator over the motion span (shared pipeline).
        let op = ctx.state.pendingInput.pendingOperator.get
        ctx.state.pendingInput.pendingOperator = none(PendingOperator)
        let execResult = applyOperatorOverMotion(
          ctx, op.operatorType, op.operatorCount, ctx.cursor, r.value, lastCmd.motion
        )
        if execResult.isErr:
          return err(execResult.error)

        # Note: We don't update lastEditCommand here because we're repeating the same command
        return ok(())
      of lecDeleteChar:
        # Repeat character deletion (x or X)
        if lastCmd.deleteForward:
          # x command - delete forward
          return handleDeleteChar(ctx, lastCmd.deleteCount)
        else:
          # X command - delete backward
          return handleDeleteCharBefore(ctx, lastCmd.deleteCount)
      of lecDeleteLine:
        # Repeat line deletion (dd)
        return handleDeleteLine(ctx, lastCmd.deleteLineCount)
      of lecPaste:
        # Repeat paste operation (p or P)
        if lastCmd.pasteBefore:
          # P command - paste before
          return handlePasteBefore(ctx, lastCmd.pasteCount)
        else:
          # p command - paste after
          return handlePasteAfter(ctx, lastCmd.pasteCount)
      of lecToggleCase:
        # Repeat toggle case (~)
        return handleToggleCase(ctx, lastCmd.toggleCaseCount)
      of lecSubstitute:
        # Repeat substitute (s/S/cc)
        # Delete + insert the recorded text without entering Insert mode
        case lastCmd.substituteKind
        of skChar:
          # Repeat s command - delete characters then insert text
          let lineContent = ctx.buffer.getLine(ctx.cursor.line)

          # Check if we're at or past the end of the line
          if ctx.cursor.column >= lineContent.charLen:
            # At end of line, just insert text
            let insertResult = ctx.buffer.insertText(ctx.cursor, lastCmd.substituteText)
            if insertResult.isErr:
              return err("Failed to insert text: " & insertResult.error)
          else:
            # Delete characters
            let charsAvailable = lineContent.charLen - ctx.cursor.column
            let charsToDelete = min(lastCmd.substituteCount, charsAvailable)

            let txr = withTransaction(
              ctx.buffer, "substitute " & $charsToDelete & " char(s)"
            ):
              for i in 0 ..< charsToDelete:
                let delResult = ctx.buffer.deleteRange(ctx.cursor, ctx.cursor)
                if delResult.isErr:
                  return err(delResult.error)

              let insertResult =
                ctx.buffer.insertText(ctx.cursor, lastCmd.substituteText)
              if insertResult.isErr:
                return err("Failed to insert text: " & insertResult.error)
            if txr.isErr:
              return err(txr.error)

          # Move cursor to last inserted character (Vim behavior)
          let numNewlines = lastCmd.substituteText.count('\n')
          if numNewlines > 0:
            ctx.cursor.line += numNewlines
            let lines = lastCmd.substituteText.split('\n')
            let lastLine = lines[^1]
            # Position cursor on last character (or at column 0 if empty)
            ctx.cursor.column = max(0, lastLine.charLen - 1)
          else:
            # Single line - move cursor to last inserted character
            ctx.cursor.column += lastCmd.substituteText.charLen
            if ctx.cursor.column > 0:
              ctx.cursor.column -= 1 # Stay on last inserted character

          return ok(())
        of skLine:
          # Repeat S or cc command - delete lines then insert text
          let startLine = ctx.cursor.line
          let endLine = min(startLine + lastCmd.substituteCount - 1, ctx.buffer.len - 1)

          let txr = withTransaction(ctx.buffer, "Substitute line"):
            for i in 0 ..< (endLine - startLine):
              if startLine + 1 < ctx.buffer.len:
                let deleteResult = ctx.buffer.deleteLine(startLine + 1)
                if deleteResult.isErr:
                  return err("Failed to delete line: " & deleteResult.error)

            if startLine < ctx.buffer.len:
              let line = ctx.buffer.getLine(startLine)
              for i in 0 ..< line.charLen:
                let deleteResult = ctx.buffer.deleteRange(
                  BufferPosition(line: startLine, column: 0),
                  BufferPosition(line: startLine, column: 0),
                )
                if deleteResult.isErr:
                  return err("Failed to clear line: " & deleteResult.error)

            let insertResult = ctx.buffer.insertText(
              BufferPosition(line: startLine, column: 0), lastCmd.substituteText
            )
            if insertResult.isErr:
              return err("Failed to insert text: " & insertResult.error)
          if txr.isErr:
            return err("Transaction failed: " & txr.error)

          # Move cursor to last inserted character (Vim behavior)
          let numNewlines = lastCmd.substituteText.count('\n')
          if numNewlines > 0:
            ctx.cursor.line = startLine + numNewlines
            let lines = lastCmd.substituteText.split('\n')
            let lastLine = lines[^1]
            # Position cursor on last character (or at column 0 if empty)
            ctx.cursor.column = max(0, lastLine.charLen - 1)
          else:
            ctx.cursor.line = startLine
            # Position cursor on last character (or at column 0 if empty)
            ctx.cursor.column = max(0, lastCmd.substituteText.charLen - 1)

          return ok(())
      of lecInsertText:
        # Repeat insert text
        let insertResult = ctx.buffer.insertText(ctx.cursor, lastCmd.insertedText)
        if insertResult.isErr:
          return err("Failed to repeat insert: " & insertResult.error)

        # Move cursor to last inserted character (Vim behavior: cursor on last char, not after)
        # Count newlines to handle multi-line insertion
        let numNewlines = lastCmd.insertedText.count('\n')
        if numNewlines > 0:
          # Multi-line insertion - move to last line
          ctx.cursor.line += numNewlines
          let lines = lastCmd.insertedText.split('\n')
          let lastLine = lines[^1]
          # Position cursor on last character (or at column 0 if last line is empty)
          ctx.cursor.column = max(0, lastLine.charLen - 1)
        else:
          # Single line insertion - move cursor to last inserted character
          if lastCmd.insertedText.len > 0:
            ctx.cursor.column += lastCmd.insertedText.charLen
            # Move back one to be on the last character, not after it
            if ctx.cursor.column > 0:
              ctx.cursor.column -= 1
          # If empty string, cursor stays at current position

        return ok(())
      of lecReplaceChar:
        # Repeat replace character (r command)
        let lineContent = ctx.buffer.getLine(ctx.cursor.line)

        # Check if we're at or past the end of the line
        if ctx.cursor.column >= lineContent.charLen:
          return err("Nothing to replace")

        # Calculate how many characters we can actually replace
        let charsAvailable = lineContent.charLen - ctx.cursor.column
        let charsToReplace = min(lastCmd.replaceCount, charsAvailable)

        let txr = withTransaction(ctx.buffer, "replace " & $charsToReplace & " char(s)"):
          for i in 0 ..< charsToReplace:
            let pos =
              BufferPosition(line: ctx.cursor.line, column: ctx.cursor.column + i)
            let delResult = ctx.buffer.deleteRange(pos, pos)
            if delResult.isErr:
              return err(delResult.error)

            let insResult = ctx.buffer.insertText(pos, lastCmd.replaceChar)
            if insResult.isErr:
              return err(insResult.error)
        if txr.isErr:
          return err(txr.error)

        # Move cursor to the last replaced character
        ctx.cursor.column += charsToReplace - 1
        return ok(())
      of lecJoinLines:
        # Repeat join lines (J command)
        return handleJoinLines(ctx, lastCmd.joinLinesCount)
      of lecOperatorLines:
        # Repeat a doubled linewise operator (>> / << / guu / gUU)
        return
          handleOperatorOnLines(ctx, lastCmd.linesOperator, lastCmd.operatorLineCount)
      of lecChangeLine:
        # Note: This case should not be reached anymore as cc now uses lecSubstitute
        # Kept for backwards compatibility if old state exists
        return err("Repeating cc command is not yet implemented (use latest version)"),
    0,
    0,
  )

  # Operator commands (d, c, y) - these wait for motion/text object
  registry.register(
    custom("operator.delete"),
    "Delete Operator",
    "Delete operator - waits for motion (d2w, d$, etc.) or dd for line",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleOperatorDelete(ctx, count),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.change"),
    "Change Operator",
    "Change operator - waits for motion (c2w, c$, etc.) or cc for line",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleOperatorChange(ctx, count),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.yank"),
    "Yank Operator",
    "Yank operator - waits for motion (y2w, y$, etc.) or yy for line",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleOperatorYank(ctx, count),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.indent"),
    "Indent Operator",
    "Indent operator - waits for motion (>w, >$, etc.) or >> for line",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleOperatorIndent(ctx, count),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.outdent"),
    "Outdent Operator",
    "Outdent operator - waits for motion (<w, <$, etc.) or << for line",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleOperatorOutdent(ctx, count),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.lowercase"),
    "Lowercase Operator",
    "Lowercase operator - waits for motion (guw, gu$, etc.)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleOperatorLowerCase(ctx, count),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.uppercase"),
    "Uppercase Operator",
    "Uppercase operator - waits for motion (gUw, gU$, etc.)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleOperatorUpperCase(ctx, count),
    0,
    1, # Accept optional count
  )

  # D - Delete to end of line (equivalent to d$)
  registry.register(
    custom("operator.delete.to.end"),
    "Delete To End Of Line",
    "Delete from cursor to end of line (D command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # Calculate range from cursor to end of line
      let startPos = ctx.cursor
      let line = ctx.buffer.getLine(startPos.line)
      let lineLen = line.charLen

      # Empty line or cursor at/past end: nothing to delete
      if lineLen == 0 or startPos.column >= lineLen:
        return ok(())

      # End at last character (same as d$ / Motion.End)
      let endPos = BufferPosition(line: startPos.line, column: lineLen - 1)

      let range = OperatorRange(start: startPos, endPos: endPos, isLinewise: false)

      # Execute delete operation
      let r = executeOperatorOnRange(ctx, OpDelete, range, 1)
      if r.isOk:
        # Record this command for repeat (.)
        ctx.state.editState.lastEditCommand = some(
          LastEditCommand(
            kind: lecOperatorMotion,
            operator: OpDelete,
            motion: End,
            motionCount: 1,
            operatorCount: 1,
          )
        )
      return r,
    0,
    0,
  )

  # C - Change to end of line (equivalent to c$)
  registry.register(
    custom("operator.change.to.end"),
    "Change To End Of Line",
    "Change from cursor to end of line (C command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # Calculate range from cursor to end of line
      let startPos = ctx.cursor
      let line = ctx.buffer.getLine(startPos.line)
      let lineLen = line.charLen

      # Empty line or cursor at/past end: just enter insert mode without deleting
      if lineLen == 0 or startPos.column >= lineLen:
        ctx.state.mode = EditorMode.Insert
        return ok(())

      # End at last character (same as c$ / Motion.End)
      let endPos = BufferPosition(line: startPos.line, column: lineLen - 1)

      let range = OperatorRange(start: startPos, endPos: endPos, isLinewise: false)

      # Execute change operation
      let r = executeOperatorOnRange(ctx, OpChange, range, 1)
      if r.isOk:
        # Record this command for repeat (.)
        ctx.state.editState.lastEditCommand = some(
          LastEditCommand(
            kind: lecOperatorMotion,
            operator: OpChange,
            motion: End,
            motionCount: 1,
            operatorCount: 1,
          )
        )
      return r,
    0,
    0,
  )

  # Text object commands (i, a) - wait for text object kind
  registry.register(
    custom("textobject.inner"),
    "Inner Text Object",
    "Select inner text object (iw, i\", i(, etc.) or enter Insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # When `i` resolves to Insert mode, args[0] (present for count > 1) carries
      # the [count] prefix for replay; as a text object the count is ignored.
      handleTextObjectInner(ctx, parseCount(args)),
    0,
    1,
  )

  registry.register(
    custom("textobject.around"),
    "Around Text Object",
    "Select around text object (aw, a\", a(, etc.) or enter Append mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleTextObjectAround(ctx, parseCount(args)),
    0,
    1,
  )

  # Text object kind commands (w, ", (, etc.)
  proc registerTextObjectKind(
      reg: CommandRegistry, id: string, name: string, desc: string, kind: TextObjectKind
  ) =
    reg.register(
      custom(id),
      name,
      desc,
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        # Check if we have a pending text object modifier
        if ctx.state.pendingInput.pendingTextObject.isNone:
          # No text object modifier - ignore this key press
          # (In the future, we should fallback to the key's normal function)
          return ok(())

        let textObj = ctx.state.pendingInput.pendingTextObject.get
        ctx.state.pendingInput.pendingTextObject = none(PendingTextObject)

        # Calculate the text object range, extended over the operator count
        # (d2iw, 2dap, d3is, 2dat). textObj.operatorCount already holds the
        # pending operator's count.
        let effectiveCount = max(textObj.operatorCount, 1)
        let rangeResult = calculateTextObjectRange(
          ctx.buffer, ctx.cursor, kind, textObj.modifier, effectiveCount
        )
        if rangeResult.isErr:
          # The object could not be resolved (e.g. dit outside a tag, dis on a
          # blank line). Discard the pending operator too so a following motion
          # is not silently consumed by a still-armed operator (a stray delete).
          # Also drop any pending register prefix (e.g. `"adit`) rather than
          # leaking it into the next command.
          ctx.state.pendingInput.pendingOperator = none(PendingOperator)
          ctx.state.pendingInput.pendingRegister = none(char)
          return err(rangeResult.error)

        let toRange = rangeResult.value

        # Convert TextObjectRange to OperatorRange
        let opRange = OperatorRange(
          start: toRange.start,
          endPos: toRange.endPos,
          isLinewise: toRange.isLinewise,
          isEmpty: toRange.isEmpty,
        )

        # Check if we have a pending operator
        if ctx.state.pendingInput.pendingOperator.isSome:
          let op = ctx.state.pendingInput.pendingOperator.get
          ctx.state.pendingInput.pendingOperator = none(PendingOperator)

          # Execute operator on text object
          return executeOperatorOnRange(ctx, op.operatorType, opRange, op.operatorCount)
        elif isVisualAllMode(ctx.state.mode):
          if toRange.isEmpty:
            # Empty object (e.g. vit on <a></a>): nothing to select, so leave
            # the current selection untouched like vim.
            return ok(())
          # In Visual mode - update selection to text object range
          ctx.state.visualSelection.start = toRange.start
          ctx.state.visualSelection.current = toRange.endPos
          ctx.state.visualSelection.active = true
          ctx.cursor = toRange.endPos
          return ok(())
        else:
          return err("Text objects require an operator or Visual mode"),
      0,
      0,
    )

  # Register text object kinds
  registerTextObjectKind(
    registry, "textobject.word", "Word Text Object", "Word text object (iw/aw)", toWord
  )
  registerTextObjectKind(
    registry, "textobject.wideword", "WORD Text Object",
    "WORD text object - space-separated (iW/aW)", toWideWord,
  )
  registerTextObjectKind(
    registry, "textobject.quote.double", "Double Quote Text Object",
    "Double-quoted string (i\"/a\")", toQuotedDouble,
  )
  registerTextObjectKind(
    registry, "textobject.quote.single", "Single Quote Text Object",
    "Single-quoted string (i'/a')", toQuotedSingle,
  )
  registerTextObjectKind(
    registry, "textobject.quote.backtick", "Backtick Text Object",
    "Backtick string (i`/a`)", toQuotedBacktick,
  )
  registerTextObjectKind(
    registry, "textobject.paren", "Parenthesis Text Object", "Parentheses (i(/a()",
    toParenthesis,
  )
  registerTextObjectKind(
    registry, "textobject.bracket", "Bracket Text Object", "Square brackets (i[/a[)",
    toBracket,
  )
  registerTextObjectKind(
    registry, "textobject.brace", "Brace Text Object", "Curly braces (i{/a{)", toBrace
  )
  registerTextObjectKind(
    registry, "textobject.angle", "Angle Bracket Text Object", "Angle brackets (i</a<)",
    toAngleBracket,
  )
  registerTextObjectKind(
    registry, "textobject.tag", "Tag Text Object", "HTML/XML tag (it/at)", toTag
  )
  registerTextObjectKind(
    registry, "textobject.sentence", "Sentence Text Object", "Sentence (is/as)",
    toSentence,
  )
  registerTextObjectKind(
    registry, "textobject.paragraph", "Paragraph Text Object", "Paragraph (ip/ap)",
    toParagraph,
  )
