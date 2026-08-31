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

## Insert mode command implementations
##
## This module provides Insert mode specific command implementations
## that are independent of CommandContext for better testability

import std/[options, strutils, unicode]

import pkg/results

import ../[types, modes, unicode_utils]
import ../buffer/[core, edit]
import smart_indent

proc getLineIndent*(line: string): string =
  ## Extract leading whitespace (spaces and tabs) from a line
  ## Returns the indentation string (empty if no indentation)
  result = ""
  for ch in line:
    if ch == ' ' or ch == '\t':
      result.add(ch)
    else:
      break

proc effectiveShiftWidth*(state: EditorState): int =
  ## Get the effective shift width (for >>/<<, auto-indent)
  ## Returns shiftWidth if > 0, otherwise tabStop (Vim compatible)
  if state.shiftWidth > 0: state.shiftWidth else: state.tabStop

proc effectiveSoftTabStop*(state: EditorState): int =
  ## Get the effective soft tab stop (for Tab/Backspace in insert mode)
  ## Returns softTabStop if > 0, otherwise tabStop (Vim compatible)
  if state.softTabStop > 0: state.softTabStop else: state.tabStop

proc getIndentString*(state: EditorState): string =
  ## Get the indent string to use for auto-indentation (>>/<<)
  ## Uses shiftWidth when set, falls back to tabStop
  if state.expandTab:
    return " ".repeat(effectiveShiftWidth(state))
  else:
    return "\t"

proc insertChar*(buffer: TextBuffer, state: EditorState, ch: char) =
  ## Insert a character at cursor position
  let pos = state.cursor
  let insertResult = buffer.insertText(pos, $ch)
  if insertResult.isErr:
    state.statusMessage = insertResult.error
    return
  # Move cursor right after insertion
  state.cursor.column += 1

proc insertTab*(buffer: TextBuffer, state: EditorState) =
  ## Insert a tab character at cursor position
  let pos = state.cursor
  let insertResult = buffer.insertText(pos, "\t")
  if insertResult.isErr:
    state.statusMessage = insertResult.error
    return
  # Move cursor right after insertion
  state.cursor.column += 1

proc insertBackspace*(buffer: TextBuffer, state: EditorState) =
  ## Handle backspace key in insert mode
  let pos = state.cursor
  if pos.column > 0:
    # Delete the character before the cursor; move the cursor only after the
    # edit succeeds so a failure cannot desync cursor and buffer.
    let deletePos = BufferPosition(line: pos.line, column: pos.column - 1)
    let deleteResult = buffer.deleteChar(deletePos)
    if deleteResult.isErr:
      state.statusMessage = deleteResult.error
      return
    state.cursor.column -= 1
  elif pos.line > 0:
    # At start of line, join with previous line
    let prevLine = buffer.getLine(pos.line - 1)
    let currentLine = buffer.getLine(pos.line)
    let prevLineLen = prevLine.charLen

    # Delete the current line first
    let deleteResult = buffer.deleteLine(pos.line)
    if deleteResult.isErr:
      state.statusMessage = deleteResult.error
      return
    # Append current line content to previous line
    if currentLine.len > 0:
      let insertResult = buffer.insertText(
        BufferPosition(line: pos.line - 1, column: prevLineLen), currentLine
      )
      if insertResult.isErr:
        # The current line is already deleted, so the cursor must still move
        # to the join point to stay in bounds.
        state.statusMessage = insertResult.error

    # Move cursor to the join point
    state.cursor.line -= 1
    state.cursor.column = prevLineLen

proc insertDelete*(buffer: TextBuffer, state: EditorState) =
  ## Handle delete key in insert mode
  let pos = state.cursor
  if pos.line >= 0 and pos.line < buffer.len and
      pos.column >= buffer.getLine(pos.line).charLen:
    # At end of line: nothing to delete (no-op)
    return
  let deleteResult = buffer.deleteChar(pos)
  if deleteResult.isErr:
    state.statusMessage = deleteResult.error

proc insertNewline*(buffer: TextBuffer, state: EditorState) =
  ## Handle newline insertion with optional auto-indentation
  let pos = state.cursor

  # Get current line content for indent detection
  let currentLineText = buffer.getLine(pos.line)

  # Split bracket pair onto three lines when cursor sits between () [] {}
  if state.bracketSplit != bsmDisable and pos.column > 0 and
      pos.column < currentLineText.charLen and
      isAdjacentBracketPair(currentLineText, pos.column - 1):
    let indented = state.bracketSplit == bsmIndent
    # Raw buffer: copied indent is unintended edit.
    let baseIndent =
      if state.autoIndent and buffer.allowsTextTransforms:
        getLineIndent(currentLineText)
      else:
        ""
    let middleIndent =
      if indented:
        baseIndent & getIndentString(state)
      else:
        ""
    let closeIndent = if indented: baseIndent else: ""
    let textToInsert = "\n" & middleIndent & "\n" & closeIndent
    let insertResult = buffer.insertText(pos, textToInsert)
    if insertResult.isErr:
      state.statusMessage = insertResult.error
      return
    state.cursor.line += 1
    state.cursor.column = middleIndent.charLen
    # Register the middle line for auto-indent cleanup on Esc — if the user
    # leaves Insert mode without typing anything, the whitespace we just
    # inserted is removed (the bracket pair itself stays intact).
    if middleIndent.len > 0:
      state.editState.autoIndentedLine =
        some((line: state.cursor.line, indent: middleIndent))
    else:
      state.editState.autoIndentedLine = none(tuple[line: int, indent: string])
    return

  # Prepare the text to insert (newline + optional indent as single operation)
  var textToInsert = "\n"
  var indentLen = 0
  var newLineIndent = ""

  # Auto-indent skipped for raw buffers.
  if state.autoIndent and buffer.allowsTextTransforms:
    # Get the indentation from the current line
    let baseIndent = getLineIndent(currentLineText)
    let extraIndent =
      if state.smartIndent:
        extraIndentForNewline(currentLineText, buffer.language, getIndentString(state))
      else:
        ""
    newLineIndent = baseIndent & extraIndent

    if newLineIndent.len > 0:
      # Combine newline and indent into single insertion
      textToInsert = "\n" & newLineIndent
      indentLen = newLineIndent.len

  # Insert newline (and indent if any) as a single undo-able operation
  let insertResult = buffer.insertText(pos, textToInsert)
  if insertResult.isErr:
    state.statusMessage = insertResult.error
    return

  # Move cursor to start of new line (after indent if any)
  state.cursor.line += 1
  state.cursor.column = indentLen

  if indentLen > 0:
    state.editState.autoIndentedLine =
      some((line: state.cursor.line, indent: newLineIndent))
  else:
    state.editState.autoIndentedLine = none(tuple[line: int, indent: string])

proc insertLineBelow*(buffer: TextBuffer, state: EditorState): Result[(), string] =
  ## Handle 'o' command - insert line below and enter insert mode with auto-indent
  let currentLine = state.cursor.line
  let lineContent = buffer.getLine(currentLine)

  let insertPos = BufferPosition(line: currentLine, column: lineContent.charLen)

  var textToInsert = "\n"
  var indentLen = 0
  var newLineIndent = ""

  # Auto-indent skipped for raw buffers.
  if state.autoIndent and buffer.allowsTextTransforms:
    let baseIndent = getLineIndent(lineContent)
    let extraIndent =
      if state.smartIndent:
        extraIndentForNewline(lineContent, buffer.language, getIndentString(state))
      else:
        ""
    newLineIndent = baseIndent & extraIndent

    if newLineIndent.len > 0:
      textToInsert = "\n" & newLineIndent
      indentLen = newLineIndent.len

  let insertResult = buffer.insertText(insertPos, textToInsert)
  if insertResult.isErr:
    return err(insertResult.error)

  state.cursor.line = currentLine + 1
  state.cursor.column = indentLen

  if indentLen > 0:
    state.editState.autoIndentedLine =
      some((line: currentLine + 1, indent: newLineIndent))
  else:
    state.editState.autoIndentedLine = none(tuple[line: int, indent: string])

  state.mode = EditorMode.Insert
  ok(())

proc insertLineAbove*(buffer: TextBuffer, state: EditorState): Result[(), string] =
  ## Handle 'O' command - insert line above and enter insert mode with auto-indent
  let currentLine = state.cursor.line
  let lineContent = buffer.getLine(currentLine)

  # Use "indent\n" (not "\nindent") — inserting "\nindent" at column 0 would
  # concatenate the indent with the original line content.
  var textToInsert = "\n"
  var indentLen = 0

  # Auto-indent skipped for raw buffers.
  if state.autoIndent and buffer.allowsTextTransforms:
    let indent = getLineIndent(lineContent)
    if indent.len > 0:
      textToInsert = indent & "\n"
      indentLen = indent.len

  let insertResult =
    buffer.insertText(BufferPosition(line: currentLine, column: 0), textToInsert)
  if insertResult.isErr:
    return err(insertResult.error)

  state.cursor.line = currentLine
  state.cursor.column = indentLen

  if indentLen > 0:
    state.editState.autoIndentedLine =
      some((line: currentLine, indent: getLineIndent(lineContent)))
  else:
    state.editState.autoIndentedLine = none(tuple[line: int, indent: string])

  state.mode = EditorMode.Insert
  ok(())

proc insertAppend*(buffer: TextBuffer, state: EditorState) =
  ## Handle 'a' command - move cursor right and enter insert mode
  let lineContent = buffer.getLine(state.cursor.line)
  # Only move right if not at end of line
  # Use charLen (character count) not len (byte count) for multibyte character support
  if state.cursor.column < lineContent.charLen:
    state.cursor.column += 1
  # Switch to insert mode
  state.mode = EditorMode.Insert

proc insertAppendEnd*(buffer: TextBuffer, state: EditorState) =
  ## Handle 'A' command - move to end of line and enter insert mode
  let lineContent = buffer.getLine(state.cursor.line)
  state.cursor.column = lineContent.charLen
  # Switch to insert mode
  state.mode = EditorMode.Insert

proc indentLine*(
    buffer: TextBuffer, state: EditorState, count: int = 1
): Result[(), string] =
  ## Indent current line. Refusals returned for caller loop handling.
  if not buffer.allowsTextTransforms:
    return err(rawBytesRejection("indent"))

  let currentLine = state.cursor.line
  if currentLine < 0 or currentLine >= buffer.len:
    return ok(())

  # Get the indent string to add
  let indentStr = getIndentString(state)

  # Build the full indentation to add (count times)
  var fullIndent = ""
  for i in 1 .. count:
    fullIndent.add(indentStr)

  # Insert at the beginning of the line
  let insertPos = BufferPosition(line: currentLine, column: 0)
  let insertResult = buffer.insertText(insertPos, fullIndent)
  if insertResult.isErr:
    return err(insertResult.error)

  # Keep cursor at the same relative position within the line content
  # (move cursor right by the amount of indentation added)
  state.cursor.column += fullIndent.len
  ok(())

proc dedentLine*(
    buffer: TextBuffer, state: EditorState, count: int = 1
): Result[(), string] =
  ## Dedent current line. Refusals returned for caller loop handling.
  if not buffer.allowsTextTransforms:
    return err(rawBytesRejection("dedent"))

  let currentLine = state.cursor.line
  if currentLine < 0 or currentLine >= buffer.len:
    return ok(())

  let lineContent = buffer.getLine(currentLine)
  let currentIndent = getLineIndent(lineContent)

  if currentIndent.len == 0:
    return ok(()) # No indentation to remove

  # Calculate how much to remove
  let indentStr = getIndentString(state)
  let indentWidth = indentStr.len
  let removeCount = min(count * indentWidth, currentIndent.len)

  if removeCount <= 0:
    return ok(())

  # Delete characters from the beginning of the line. Track how many were
  # actually removed so the cursor adjustment stays correct on partial failure.
  var deleted = 0
  var failure = ""
  for i in 1 .. removeCount:
    let deletePos = BufferPosition(line: currentLine, column: 0)
    let deleteResult = buffer.deleteChar(deletePos)
    if deleteResult.isErr:
      failure = deleteResult.error
      break
    inc deleted

  if deleted == 0:
    if failure.len > 0:
      return err(failure)
    return ok(())

  # Adjust cursor position
  # If cursor was in the indentation area, move it to column 0
  # Otherwise, move it left by the amount removed
  if state.cursor.column >= deleted:
    state.cursor.column -= deleted
  else:
    state.cursor.column = 0

  if failure.len > 0:
    return err(failure)
  ok(())

proc isWhitespace(r: Rune): bool =
  ## Check if a character is whitespace
  let c = r.int32
  return c == ' '.ord or c == '\t'.ord or c == '\n'.ord or c == '\r'.ord

proc deleteWordBackward*(buffer: TextBuffer, state: EditorState) =
  ## Delete word before cursor (Ctrl-W in insert mode)
  ## Deletes backward from cursor to start of previous word
  ## At start of line, does nothing (matches Vim behavior)
  let pos = state.cursor

  if pos.column == 0:
    # At start of line, do nothing (Vim behavior)
    return

  # `pos.column` is a buffer column, so the runes must be counted the same way.
  let line = buffer.getLine(pos.line)
  let runes = line.toCharRunes()

  # Clamp column to valid range
  var newCol = min(pos.column, runes.len)

  # Skip whitespace backwards first
  while newCol > 0 and isWhitespace(runes[newCol - 1]):
    newCol -= 1

  # Then skip the word/symbol sequence
  if newCol > 0:
    if isWordChar(runes[newCol - 1]):
      # Skip word characters backwards
      while newCol > 0 and isWordChar(runes[newCol - 1]):
        newCol -= 1
    elif not isWhitespace(runes[newCol - 1]):
      # Skip symbol characters backwards
      while newCol > 0 and not isWordChar(runes[newCol - 1]) and
          not isWhitespace(runes[newCol - 1]):
        newCol -= 1

  # Delete characters from newCol to pos.column. Delete from the top down so
  # each position is stable, and move the cursor only after each edit succeeds
  # so a failure cannot desync cursor and buffer.
  let deleteCount = min(pos.column, runes.len) - newCol
  for i in 0 ..< deleteCount:
    let deletePos = BufferPosition(line: pos.line, column: pos.column - 1 - i)
    let deleteResult = buffer.deleteChar(deletePos)
    if deleteResult.isErr:
      state.statusMessage = deleteResult.error
      return
    state.cursor.column -= 1

proc deleteToLineStart*(buffer: TextBuffer, state: EditorState) =
  ## Delete from cursor to beginning of line (Ctrl-U in insert mode)
  let pos = state.cursor

  if pos.column == 0:
    return # Nothing to delete

  # Get line length to clamp column
  let line = buffer.getLine(pos.line)
  let lineLen = line.charLen

  # Delete all characters from column 0 to cursor position. Repeatedly delete
  # at column 0 (each removal shifts the next character down), and derive the
  # final cursor position from the number of characters actually removed so a
  # failure cannot desync cursor and buffer.
  let deleteCount = min(pos.column, lineLen)
  var deleted = 0
  for _ in 0 ..< deleteCount:
    let deleteResult = buffer.deleteChar(BufferPosition(line: pos.line, column: 0))
    if deleteResult.isErr:
      state.statusMessage = deleteResult.error
      break
    inc deleted

  state.cursor.column = min(max(0, pos.column - deleted), lineLen - deleted)

proc insertCharFromAbove*(buffer: TextBuffer, state: EditorState): bool =
  ## Insert character from the line above at the same column (Ctrl-Y in insert mode)
  ## Returns true if a character was inserted, false otherwise
  let pos = state.cursor

  if pos.line == 0:
    return false # No line above

  let aboveLine = buffer.getLine(pos.line - 1)
  # Strip trailing newline if present
  let lineContent =
    if aboveLine.len > 0 and aboveLine[^1] == '\n':
      aboveLine[0 ..< ^1]
    else:
      aboveLine
  if pos.column >= lineContent.charLen:
    return false # No character at this column in the line above

  # Sliced, not re-encoded: an undecodable byte would widen into the
  # replacement character and copy something the line above lacks.
  let ch = lineContent.charSubStr(pos.column, 1)
  let insertResult = buffer.insertTextEnd(pos, ch)
  if insertResult.isErr:
    state.statusMessage = insertResult.error
    return false
  state.cursor = insertResult.get.cursor
  return true

proc insertCharFromBelow*(buffer: TextBuffer, state: EditorState): bool =
  ## Insert character from the line below at the same column (Ctrl-E in insert mode)
  ## Returns true if a character was inserted, false otherwise
  let pos = state.cursor

  if pos.line >= buffer.len - 1:
    return false # No line below

  let belowLine = buffer.getLine(pos.line + 1)
  # Strip trailing newline if present
  let lineContent =
    if belowLine.len > 0 and belowLine[^1] == '\n':
      belowLine[0 ..< ^1]
    else:
      belowLine
  if pos.column >= lineContent.charLen:
    return false # No character at this column in the line below

  let ch = lineContent.charSubStr(pos.column, 1)
  let insertResult = buffer.insertTextEnd(pos, ch)
  if insertResult.isErr:
    state.statusMessage = insertResult.error
    return false
  state.cursor = insertResult.get.cursor
  return true

proc clearAutoIndentIfUnedited*(buffer: TextBuffer, state: EditorState) =
  ## Remove auto-indent whitespace when leaving Insert mode without editing.
  ## Uses replaceLine (not deleteText) so extractInsertedText ignores the change.
  if state.editState.autoIndentedLine.isSome:
    let (line, indent) = state.editState.autoIndentedLine.get
    if line >= 0 and line < buffer.len:
      let lineContent = buffer.getLine(line)
      if lineContent == indent:
        let replaceResult = buffer.replaceLine(line, "")
        if replaceResult.isErr:
          state.statusMessage = replaceResult.error
        elif state.cursor.line == line:
          state.cursor.column = 0
    state.editState.autoIndentedLine = none(tuple[line: int, indent: string])
