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

import ../[buffer, types, modes]

proc insertChar*(buffer: TextBuffer, state: EditorState, ch: char) =
  ## Insert a character at cursor position
  let pos = state.cursor
  discard buffer.insertText(pos, $ch)
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
  ## Handle newline insertion
  let pos = state.cursor
  discard buffer.insertText(pos, "\n")
  # Move cursor to start of new line
  state.cursor.line += 1
  state.cursor.column = 0

proc insertLineBelow*(buffer: TextBuffer, state: EditorState) =
  ## Handle 'o' command - insert line below and enter insert mode
  let currentLine = state.cursor.line
  # Move to end of current line
  let lineContent = buffer.getLine(currentLine)
  state.cursor.column = lineContent.charLen
  # Insert newline
  discard buffer.insertText(state.cursor, "\n")
  # Move cursor to new line
  state.cursor.line = currentLine + 1
  state.cursor.column = 0
  # Switch to insert mode
  state.mode = EditorMode.Insert

proc insertLineAbove*(buffer: TextBuffer, state: EditorState) =
  ## Handle 'O' command - insert line above and enter insert mode
  let currentLine = state.cursor.line
  # Move to start of current line
  state.cursor.column = 0
  # Insert newline
  discard buffer.insertText(state.cursor, "\n")
  # Move cursor to the new line (which is the current line)
  state.cursor.line = currentLine
  state.cursor.column = 0
  # Switch to insert mode
  state.mode = EditorMode.Insert

proc insertAppend*(buffer: TextBuffer, state: EditorState) =
  ## Handle 'a' command - move cursor right and enter insert mode
  let lineContent = buffer.getLine(state.cursor.line)
  # Only move right if not at end of line
  if state.cursor.column < lineContent.len:
    state.cursor.column += 1
  # Switch to insert mode
  state.mode = EditorMode.Insert

proc insertAppendEnd*(buffer: TextBuffer, state: EditorState) =
  ## Handle 'A' command - move to end of line and enter insert mode
  let lineContent = buffer.getLine(state.cursor.line)
  state.cursor.column = lineContent.charLen
  # Switch to insert mode
  state.mode = EditorMode.Insert
