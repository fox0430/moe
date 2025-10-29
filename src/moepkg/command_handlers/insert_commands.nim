#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import std/strutils
import ../[buffer, types, modes]

proc getLineIndent*(line: string): string =
  ## Extract leading whitespace (spaces and tabs) from a line
  ## Returns the indentation string (empty if no indentation)
  result = ""
  for ch in line:
    if ch == ' ' or ch == '\t':
      result.add(ch)
    else:
      break

proc getIndentString*(state: EditorState): string =
  ## Get the indent string to use for auto-indentation
  ## Returns either a tab or spaces based on expandTab setting
  if state.expandTab:
    return " ".repeat(state.tabStop)
  else:
    return "\t"

proc insertChar*(buffer: TextBuffer, state: EditorState, ch: char) =
  ## Insert a character at cursor position
  let pos = state.cursor
  discard buffer.insertText(pos, $ch)
  # Move cursor right after insertion
  state.cursor.column += 1

proc insertTab*(buffer: TextBuffer, state: EditorState) =
  ## Insert a tab character at cursor position
  let pos = state.cursor
  discard buffer.insertText(pos, "\t")
  # Move cursor right after insertion
  state.cursor.column += 1

proc insertBackspace*(buffer: TextBuffer, state: EditorState) =
  ## Handle backspace key in insert mode
  let pos = state.cursor
  if pos.column > 0:
    # Move cursor back and delete
    state.cursor.column -= 1
    discard buffer.deleteChar(state.cursor)
  elif pos.line > 0:
    # At start of line, join with previous line
    let prevLine = buffer.getLine(pos.line - 1)
    state.cursor.line -= 1
    state.cursor.column = prevLine.charLen
    # Join lines by deleting the newline
    discard buffer.deleteChar(state.cursor)

proc insertDelete*(buffer: TextBuffer, state: EditorState) =
  ## Handle delete key in insert mode
  discard buffer.deleteChar(state.cursor)

proc insertNewline*(buffer: TextBuffer, state: EditorState) =
  ## Handle newline insertion with optional auto-indentation
  let pos = state.cursor

  # Get current line content for indent detection
  let currentLineText = buffer.getLine(pos.line)

  # Prepare the text to insert (newline + optional indent as single operation)
  var textToInsert = "\n"
  var indentLen = 0

  # Apply auto-indent if enabled
  if state.autoIndent:
    # Get the indentation from the current line
    let indent = getLineIndent(currentLineText)

    if indent.len > 0:
      # Combine newline and indent into single insertion
      textToInsert = "\n" & indent
      indentLen = indent.len

  # Insert newline (and indent if any) as a single undo-able operation
  discard buffer.insertText(pos, textToInsert)

  # Move cursor to start of new line (after indent if any)
  state.cursor.line += 1
  state.cursor.column = indentLen

proc insertLineBelow*(buffer: TextBuffer, state: EditorState) =
  ## Handle 'o' command - insert line below and enter insert mode with auto-indent
  let currentLine = state.cursor.line
  # Get current line content for indent detection
  let lineContent = buffer.getLine(currentLine)

  # Move to end of current line
  state.cursor.column = lineContent.charLen

  # Prepare the text to insert (newline + optional indent as single operation)
  var textToInsert = "\n"
  var indentLen = 0

  # Apply auto-indent if enabled
  if state.autoIndent:
    let indent = getLineIndent(lineContent)
    if indent.len > 0:
      textToInsert = "\n" & indent
      indentLen = indent.len

  # Insert newline (and indent if any) as a single undo-able operation
  discard buffer.insertText(state.cursor, textToInsert)

  # Move cursor to new line (after indent if any)
  state.cursor.line = currentLine + 1
  state.cursor.column = indentLen

  # Switch to insert mode
  state.mode = EditorMode.Insert

proc insertLineAbove*(buffer: TextBuffer, state: EditorState) =
  ## Handle 'O' command - insert line above and enter insert mode with auto-indent
  let currentLine = state.cursor.line
  # Get current line content for indent detection
  let lineContent = buffer.getLine(currentLine)

  # Move to start of current line
  state.cursor.column = 0

  # Prepare the text to insert (newline + optional indent as single operation)
  var textToInsert = "\n"
  var indentLen = 0

  # Apply auto-indent if enabled
  if state.autoIndent:
    let indent = getLineIndent(lineContent)
    if indent.len > 0:
      textToInsert = "\n" & indent
      indentLen = indent.len

  # Insert newline (and indent if any) as a single undo-able operation
  discard buffer.insertText(state.cursor, textToInsert)

  # Move cursor to the new line (which is the current line, after indent if any)
  state.cursor.line = currentLine
  state.cursor.column = indentLen

  # Switch to insert mode
  state.mode = EditorMode.Insert

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
