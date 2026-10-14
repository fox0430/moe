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

import ../[types, modes, unicode_utils, insert_record]
import ../buffer/[core, edit, undo]
import smart_indent

proc beginInsertModeSession*(
    buffer: TextBuffer, state: EditorState
): Result[bool, string] =
  ## Begin the transaction an Insert session types into, true when it begins
  ## here: an open one belongs to an entry command that edited first (`cw`).
  if buffer.inTransaction:
    return ok(false)
  let begun =
    buffer.beginTransaction("Insert mode edit", cursorPos = some(state.cursor))
  if begun.isErr:
    return err(begun.error)
  ok(true)

proc markAutoIndented(
    buffer: TextBuffer, state: EditorState, line: int, indent: string
) =
  ## Note that Insert indented `line` by itself.
  state.editState.autoIndentedLine =
    if indent.len > 0:
      some(AutoIndentedLine(line: line, version: buffer.contentVersion))
    else:
      none(AutoIndentedLine)

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

proc deleteBeforeCursor*(buffer: TextBuffer, state: EditorState): Result[void, string] =
  ## Backspace in Insert mode: an auto-paired pair, a soft tab stop, a
  ## character, or the line break before the line.
  let pos = state.cursor

  if pos.column > 0:
    if state.autoDeleteParen:
      let currentLine = buffer.getLine(pos.line)

      try:
        # Auto-delete adjacent pairs only: cursor must be between open and close
        # e.g., (|), [|], {|}, "|", '|'
        if isAdjacentPair(currentLine, pos.column - 1):
          # Delete the opening char first; the closing char then shifts into the
          # same column. Move the cursor only after both edits succeed.
          let pairPos = BufferPosition(line: pos.line, column: pos.column - 1)
          let openResult = buffer.deleteChar(pairPos)
          if openResult.isErr:
            return err(openResult.error)
          let closeResult = buffer.deleteChar(pairPos)
          if closeResult.isErr:
            return err(closeResult.error)
          state.cursor.column -= 1
          return ok()
      except IndexDefect, CatchableError:
        # If accessing rune fails, fall through to normal backspace
        discard

    # softTabStop-aware backspace: in leading whitespace, delete back to the
    # previous boundary; elsewhere one character.
    var deleteCount = 1
    if state.expandTab:
      let upToCursor = buffer.getLine(pos.line).charSubStr(0, pos.column)
      var allSpaces = upToCursor.charLen == pos.column
      if allSpaces:
        for (ch, _) in upToCursor.chars:
          if ch != Rune(' ') and ch != Rune('\t'):
            allSpaces = false
            break
      if allSpaces:
        let tabWidth = max(1, effectiveSoftTabStop(state))
        let remainder = pos.column mod tabWidth
        deleteCount = min(if remainder == 0: tabWidth else: remainder, pos.column)
    # Delete from the top down so each position is stable, and move the
    # cursor only after each edit succeeds.
    for i in 0 ..< deleteCount:
      let deletePos = BufferPosition(line: pos.line, column: pos.column - 1 - i)
      let deleteResult = buffer.deleteChar(deletePos)
      if deleteResult.isErr:
        return err(deleteResult.error)
      state.cursor.column -= 1
  elif pos.line > 0:
    # At start of line, join with previous line
    let joinResult = buffer.joinWithNextLine(pos.line - 1)
    if joinResult.isErr:
      return err(joinResult.error)
    state.cursor = joinResult.get

  ok()

proc insertBackspace*(buffer: TextBuffer, state: EditorState) =
  ## Handle backspace key in insert mode
  let r = deleteBeforeCursor(buffer, state)
  if r.isErr:
    state.statusMessage = r.error

proc deleteAtCursor*(buffer: TextBuffer, state: EditorState): Result[void, string] =
  ## Delete in Insert mode; nothing at the end of a line.
  let pos = state.cursor
  if pos.line >= 0 and pos.line < buffer.len and
      pos.column >= buffer.getLine(pos.line).charLen:
    return ok()
  let r = buffer.deleteChar(pos)
  if r.isErr:
    return err(r.error)
  ok()

proc insertDelete*(buffer: TextBuffer, state: EditorState) =
  ## Handle delete key in insert mode
  let r = deleteAtCursor(buffer, state)
  if r.isErr:
    state.statusMessage = r.error

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
    buffer.markAutoIndented(state, state.cursor.line, middleIndent)
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

  # An untouched auto-indent comes off the line Enter leaves; the new line
  # still gets it.
  var at = pos
  if buffer.untouchedAutoIndent(state) == some(pos.line) and
      pos.column == currentLineText.charLen:
    let cleared = buffer.replaceLine(pos.line, "")
    if cleared.isErr:
      state.statusMessage = cleared.error
      return
    at.column = 0

  # Insert newline (and indent if any) as a single undo-able operation
  let insertResult = buffer.insertText(at, textToInsert)
  if insertResult.isErr:
    state.statusMessage = insertResult.error
    return

  # Move cursor to start of new line (after indent if any)
  state.cursor.line += 1
  state.cursor.column = indentLen

  buffer.markAutoIndented(state, state.cursor.line, newLineIndent)

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

  buffer.markAutoIndented(state, currentLine + 1, newLineIndent)

  state.mode = EditorMode.Insert
  ok(())

proc insertLineAbove*(buffer: TextBuffer, state: EditorState): Result[(), string] =
  ## Handle 'O' command - insert line above and enter insert mode with auto-indent
  let currentLine = state.cursor.line
  let lineContent = buffer.getLine(currentLine)

  # Use "indent\n" (not "\nindent") — inserting "\nindent" at column 0 would
  # concatenate the indent with the original line content.
  var textToInsert = "\n"
  var indent = ""

  # Auto-indent skipped for raw buffers.
  if state.autoIndent and buffer.allowsTextTransforms:
    indent = getLineIndent(lineContent)
    if indent.len > 0:
      textToInsert = indent & "\n"

  let insertResult =
    buffer.insertText(BufferPosition(line: currentLine, column: 0), textToInsert)
  if insertResult.isErr:
    return err(insertResult.error)

  state.cursor.line = currentLine
  state.cursor.column = indent.len

  buffer.markAutoIndented(state, currentLine, indent)

  state.mode = EditorMode.Insert
  ok(())

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

proc stepToAppend*(buffer: TextBuffer, state: EditorState) =
  ## Put the cursor after the character under it, where `a` types.
  if state.cursor.column < buffer.getLine(state.cursor.line).charLen:
    state.cursor.column += 1

proc deleteBetween*(
    buffer: TextBuffer, first, stop: BufferPosition
): Result[void, string] =
  ## Delete from `first` up to `stop`, across lines too: deleteRange's end is
  ## inclusive, and past a line's last character it takes the line break.
  if first == stop:
    return ok()
  let last =
    if stop.column > 0:
      BufferPosition(line: stop.line, column: stop.column - 1)
    else:
      BufferPosition(line: stop.line - 1, column: buffer.getLine(stop.line - 1).charLen)
  let removed = buffer.deleteRange(first, last)
  if removed.isErr:
    return err(removed.error)
  ok()

proc charsBetween*(buffer: TextBuffer, a, b: BufferPosition): int =
  ## Characters from `a` up to `b`, a line break counting as one. 0 when `b`
  ## is not after `a`.
  if b.line < a.line or (b.line == a.line and b.column <= a.column):
    return 0
  if a.line == b.line:
    return b.column - a.column
  result = buffer.getLine(a.line).charLen - a.column + 1
  for line in a.line + 1 ..< b.line:
    result += buffer.getLine(line).charLen + 1
  result += b.column

proc stepChars(buffer: TextBuffer, pos: BufferPosition, n: int): BufferPosition =
  ## The position `n` characters after `pos` (before it when negative), a line
  ## break counting as one, stopping at the ends of the buffer.
  result = pos
  var left = n
  while left > 0:
    let lineLen = buffer.getLine(result.line).charLen
    if result.column + left <= lineLen:
      result.column += left
      left = 0
    elif result.line + 1 < buffer.len:
      left -= lineLen - result.column + 1
      inc result.line
      result.column = 0
    else:
      result.column = lineLen
      left = 0
  while left < 0:
    if result.column + left >= 0:
      result.column += left
      left = 0
    elif result.line > 0:
      left += result.column + 1
      dec result.line
      result.column = buffer.getLine(result.line).charLen
    else:
      result.column = 0
      left = 0

proc typeTextAgain*(
    buffer: TextBuffer, state: EditorState, typed: TypedInput
): Result[void, string] =
  ## Put the text `.` recorded in at the cursor, in place of the characters it
  ## replaced, as it came in: no indent or pair is added.
  let
    first = buffer.stepChars(state.cursor, -typed.removeBefore)
    removed =
      buffer.deleteBetween(first, buffer.stepChars(state.cursor, typed.removeAfter))
  if removed.isErr:
    return removed
  state.cursor = first
  if typed.text.len > 0:
    let inserted = buffer.insertTextEnd(
      first, typed.text, cursorByte = typed.text.charToBytePos(typed.cursorAt)
    )
    if inserted.isErr:
      return err(inserted.error)
    state.cursor = inserted.get.cursor
  ok()

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
  let untouched = buffer.untouchedAutoIndent(state)
  if untouched.isSome:
    let replaceResult = buffer.replaceLine(untouched.get, "")
    if replaceResult.isErr:
      state.statusMessage = replaceResult.error
    elif state.cursor.line == untouched.get:
      state.cursor.column = 0
  state.editState.autoIndentedLine = none(AutoIndentedLine)
