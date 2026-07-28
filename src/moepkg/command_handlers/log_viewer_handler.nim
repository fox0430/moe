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

## Log viewer mode command handler
##
## This module handles commands specific to Log Viewer mode.
## The log viewer displays editor messages and LSP logs in a read-only buffer.
## Navigation uses normal cursor/buffer operations.

import std/[options, unicode]

import ../[types, key_bindings, search_utils]
import ../buffer/[core, search]
import handler_types
export handler_types

proc isWhitespace(r: Rune): bool =
  let c = r.int32
  c == ' '.ord or c == '\t'.ord or c == '\n'.ord or c == '\r'.ord

type
  LogViewerResultKind* = enum
    lvrHandled # Command was handled successfully
    lvrEnterCommand # Enter command mode
    lvrEnterSearchForward # Enter search mode (forward)
    lvrEnterSearchBackward # Enter search mode (backward)
    lvrEnterVisual # Enter Visual mode (v / V / Ctrl-v) for selection + yank
    lvrQuit # Close log viewer and return to previous mode
    lvrRefresh # Refresh log content
    lvrUnhandled # Command was not handled (delegate to normal mode)
    lvrError # Error occurred

  LogViewerResult* = object
    case kind*: LogViewerResultKind
    of lvrEnterVisual:
      visualKind*: VisualSelectionKind
    of lvrError:
      errorMessage*: string
    else:
      discard

proc handleLogViewerModeKey*(
    logState: LogViewerState,
    buffer: TextBuffer,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): LogViewerResult =
  ## Handle a key press in Log Viewer mode
  ## Uses normal buffer/cursor for navigation (buffer contains actual log content)
  ##
  ## Returns a LogViewerResult indicating what action should be taken

  # Note: LogViewerState is now stored in EditorWindow, not EditorState
  # The state check is done by the caller (handler_manager.nim)

  let
    maxLine = max(0, buffer.len - 1)
    # Calculate actual content height (viewport height minus reserved lines for status/command)
    contentHeight = max(1, viewportHeight - state.windowDisplay.viewportReservedLines)

  # Handle 'gg' command (two g presses)
  if logState.waitingForG:
    logState.waitingForG = false
    if not keyCombo.isSpecial and keyCombo.char == "g":
      state.cursor.line = 0
      state.cursor.column = 0
      return LogViewerResult(kind: lvrHandled)
    # If not 'g', fall through to normal handling

  # Escape - do nothing (stay in LogViewer, like Vim's :help)
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    return LogViewerResult(kind: lvrHandled)

  # Check for special keys first
  if keyCombo.isSpecial:
    case keyCombo.special
    of skUp:
      if state.cursor.line > 0:
        state.cursor.line.dec
      return LogViewerResult(kind: lvrHandled)
    of skDown:
      if state.cursor.line < maxLine:
        state.cursor.line.inc
      return LogViewerResult(kind: lvrHandled)
    of skLeft:
      if state.cursor.column > 0:
        state.cursor.column.dec
      return LogViewerResult(kind: lvrHandled)
    of skRight:
      let lineLen = buffer.getLineLen(state.cursor.line)
      if state.cursor.column < lineLen - 1:
        state.cursor.column.inc
      return LogViewerResult(kind: lvrHandled)
    of skHome:
      state.cursor.column = 0
      return LogViewerResult(kind: lvrHandled)
    of skEnd:
      let lineLen = buffer.getLineLen(state.cursor.line)
      state.cursor.column = max(0, lineLen - 1)
      return LogViewerResult(kind: lvrHandled)
    else:
      discard
  else:
    # Character keys
    # Check for Ctrl+d (half page down)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "d":
      let halfPage = contentHeight div 2
      state.cursor.line = min(maxLine, state.cursor.line + halfPage)
      return LogViewerResult(kind: lvrHandled)

    # Check for Ctrl+u (half page up)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "u":
      let halfPage = contentHeight div 2
      state.cursor.line = max(0, state.cursor.line - halfPage)
      return LogViewerResult(kind: lvrHandled)

    # Check for Ctrl+f (full page down)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "f":
      state.cursor.line = min(maxLine, state.cursor.line + contentHeight)
      return LogViewerResult(kind: lvrHandled)

    # Check for Ctrl+b (full page up)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "b":
      state.cursor.line = max(0, state.cursor.line - contentHeight)
      return LogViewerResult(kind: lvrHandled)

    # Ctrl-v enters VisualBlock mode for column-wise selection.
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "v":
      return LogViewerResult(kind: lvrEnterVisual, visualKind: vskBlock)

    case keyCombo.char
    of ":":
      return LogViewerResult(kind: lvrEnterCommand)
    of "/":
      return LogViewerResult(kind: lvrEnterSearchForward)
    of "?":
      return LogViewerResult(kind: lvrEnterSearchBackward)
    of "v":
      return LogViewerResult(kind: lvrEnterVisual, visualKind: vskChar)
    of "V":
      return LogViewerResult(kind: lvrEnterVisual, visualKind: vskLine)
    of "q":
      return LogViewerResult(kind: lvrQuit)
    of "j":
      if state.cursor.line < maxLine:
        state.cursor.line.inc
      return LogViewerResult(kind: lvrHandled)
    of "k":
      if state.cursor.line > 0:
        state.cursor.line.dec
      return LogViewerResult(kind: lvrHandled)
    of "h":
      if state.cursor.column > 0:
        state.cursor.column.dec
      return LogViewerResult(kind: lvrHandled)
    of "l":
      let lineLen = buffer.getLineLen(state.cursor.line)
      if state.cursor.column < lineLen - 1:
        state.cursor.column.inc
      return LogViewerResult(kind: lvrHandled)
    of "0":
      state.cursor.column = 0
      return LogViewerResult(kind: lvrHandled)
    of "$":
      let lineLen = buffer.getLineLen(state.cursor.line)
      state.cursor.column = max(0, lineLen - 1)
      return LogViewerResult(kind: lvrHandled)
    of "w":
      # Word forward - move to start of next word
      let line = buffer.getLine(state.cursor.line)
      let lineContent =
        if line.len > 0 and line[^1] == '\n':
          line[0 ..< ^1]
        else:
          line
      let runes = lineContent.toRunes()
      var pos = state.cursor.column

      # Skip current word/symbol sequence
      if pos < runes.len:
        let firstCh = runes[pos]
        if isWordChar(firstCh):
          while pos < runes.len and isWordChar(runes[pos]):
            pos += 1
        elif not isWhitespace(firstCh):
          while pos < runes.len and not isWordChar(runes[pos]) and
              not isWhitespace(runes[pos]):
            pos += 1

      # Skip whitespace
      while pos < runes.len and isWhitespace(runes[pos]):
        pos += 1

      # If at end of line, move to next line
      if pos >= runes.len and state.cursor.line < maxLine:
        state.cursor.line += 1
        state.cursor.column = 0
        # Skip leading whitespace on new line
        let nextLine = buffer.getLine(state.cursor.line)
        let nextContent =
          if nextLine.len > 0 and nextLine[^1] == '\n':
            nextLine[0 ..< ^1]
          else:
            nextLine
        let nextRunes = nextContent.toRunes()
        while state.cursor.column < nextRunes.len and
            isWhitespace(nextRunes[state.cursor.column]):
          state.cursor.column += 1
      else:
        state.cursor.column = min(pos, max(0, runes.len - 1))
      return LogViewerResult(kind: lvrHandled)
    of "b":
      # Word backward - move to start of previous word
      var pos = state.cursor.column
      var line = state.cursor.line

      # Move back one position first
      if pos > 0:
        pos -= 1
      elif line > 0:
        line -= 1
        let prevLine = buffer.getLine(line)
        let prevContent =
          if prevLine.len > 0 and prevLine[^1] == '\n':
            prevLine[0 ..< ^1]
          else:
            prevLine
        pos = max(0, prevContent.toRunes().len - 1)

      let lineStr = buffer.getLine(line)
      let lineContent =
        if lineStr.len > 0 and lineStr[^1] == '\n':
          lineStr[0 ..< ^1]
        else:
          lineStr
      let runes = lineContent.toRunes()

      # Skip whitespace backward
      while pos > 0 and pos < runes.len and isWhitespace(runes[pos]):
        pos -= 1

      # Skip word/symbol backward to find start
      if pos >= 0 and pos < runes.len:
        let ch = runes[pos]
        if isWordChar(ch):
          while pos > 0 and isWordChar(runes[pos - 1]):
            pos -= 1
        elif not isWhitespace(ch):
          while pos > 0 and not isWordChar(runes[pos - 1]) and
              not isWhitespace(runes[pos - 1]):
            pos -= 1

      state.cursor.line = line
      state.cursor.column = max(0, pos)
      return LogViewerResult(kind: lvrHandled)
    of "e":
      # Word end - move to end of current/next word
      let line = buffer.getLine(state.cursor.line)
      let lineContent =
        if line.len > 0 and line[^1] == '\n':
          line[0 ..< ^1]
        else:
          line
      let runes = lineContent.toRunes()
      var pos = state.cursor.column

      # Move forward one to get off current position
      if pos < runes.len - 1:
        pos += 1

      # Skip whitespace
      while pos < runes.len and isWhitespace(runes[pos]):
        pos += 1

      # If at end of line, move to next line
      if pos >= runes.len and state.cursor.line < maxLine:
        state.cursor.line += 1
        let nextLine = buffer.getLine(state.cursor.line)
        let nextContent =
          if nextLine.len > 0 and nextLine[^1] == '\n':
            nextLine[0 ..< ^1]
          else:
            nextLine
        let nextRunes = nextContent.toRunes()
        pos = 0
        # Skip leading whitespace
        while pos < nextRunes.len and isWhitespace(nextRunes[pos]):
          pos += 1
        # Find end of word
        if pos < nextRunes.len:
          let ch = nextRunes[pos]
          if isWordChar(ch):
            while pos < nextRunes.len - 1 and isWordChar(nextRunes[pos + 1]):
              pos += 1
          elif not isWhitespace(ch):
            while pos < nextRunes.len - 1 and not isWordChar(nextRunes[pos + 1]) and
                not isWhitespace(nextRunes[pos + 1]):
              pos += 1
        state.cursor.column = pos
      else:
        # Find end of word on current line
        if pos < runes.len:
          let ch = runes[pos]
          if isWordChar(ch):
            while pos < runes.len - 1 and isWordChar(runes[pos + 1]):
              pos += 1
          elif not isWhitespace(ch):
            while pos < runes.len - 1 and not isWordChar(runes[pos + 1]) and
                not isWhitespace(runes[pos + 1]):
              pos += 1
        state.cursor.column = min(pos, max(0, runes.len - 1))
      return LogViewerResult(kind: lvrHandled)
    of "{":
      # Paragraph backward - move to previous blank line
      var line = state.cursor.line
      # Skip current blank lines
      while line > 0 and buffer.getLineLen(line) <= 1:
        line -= 1
      # Find previous blank line
      while line > 0 and buffer.getLineLen(line) > 1:
        line -= 1
      state.cursor.line = line
      state.cursor.column = 0
      return LogViewerResult(kind: lvrHandled)
    of "}":
      # Paragraph forward - move to next blank line
      var line = state.cursor.line
      # Skip current blank lines
      while line < maxLine and buffer.getLineLen(line) <= 1:
        line += 1
      # Find next blank line
      while line < maxLine and buffer.getLineLen(line) > 1:
        line += 1
      state.cursor.line = line
      state.cursor.column = 0
      return LogViewerResult(kind: lvrHandled)
    of "g":
      # Start waiting for second 'g'
      logState.waitingForG = true
      return LogViewerResult(kind: lvrHandled)
    of "G":
      state.cursor.line = maxLine
      state.cursor.column = 0
      return LogViewerResult(kind: lvrHandled)
    of "r":
      # Refresh log content
      return LogViewerResult(kind: lvrRefresh)
    of "n":
      # Search next - find next occurrence of last search
      if state.input.search.lastText.len > 0:
        let ignoreCase = shouldIgnoreCase(
          state.input.search.lastText, state.input.search.ignorecase,
          state.input.search.smartcase,
        )
        let searchResult =
          buffer.findNext(state.input.search.lastText, state.cursor, ignoreCase)
        if searchResult.isSome:
          state.cursor = searchResult.get
        else:
          state.statusMessage = "Pattern not found: " & state.input.search.lastText
      else:
        state.statusMessage = "No previous search"
      return LogViewerResult(kind: lvrHandled)
    of "N":
      # Search prev - find previous occurrence of last search
      if state.input.search.lastText.len > 0:
        let ignoreCase = shouldIgnoreCase(
          state.input.search.lastText, state.input.search.ignorecase,
          state.input.search.smartcase,
        )
        let searchResult =
          buffer.findPrev(state.input.search.lastText, state.cursor, ignoreCase)
        if searchResult.isSome:
          state.cursor = searchResult.get
        else:
          state.statusMessage = "Pattern not found: " & state.input.search.lastText
      else:
        state.statusMessage = "No previous search"
      return LogViewerResult(kind: lvrHandled)
    of "*":
      # Search word forward - search for word under cursor
      let word = buffer.getWordAtPosition(state.cursor)
      if word.len > 0:
        state.input.search.lastText = word
        state.input.search.wholeWord = true
        let ignoreCase = shouldIgnoreCase(
          word, state.input.search.ignorecase, state.input.search.smartcase
        )
        let searchResult = buffer.findNext(word, state.cursor, ignoreCase)
        if searchResult.isSome:
          state.cursor = searchResult.get
        else:
          state.statusMessage = "Pattern not found: " & word
      return LogViewerResult(kind: lvrHandled)
    of "#":
      # Search word backward - search for word under cursor
      let word = buffer.getWordAtPosition(state.cursor)
      if word.len > 0:
        state.input.search.lastText = word
        state.input.search.wholeWord = true
        let ignoreCase = shouldIgnoreCase(
          word, state.input.search.ignorecase, state.input.search.smartcase
        )
        let searchResult = buffer.findPrev(word, state.cursor, ignoreCase)
        if searchResult.isSome:
          state.cursor = searchResult.get
        else:
          state.statusMessage = "Pattern not found: " & word
      return LogViewerResult(kind: lvrHandled)
    else:
      discard

  return LogViewerResult(kind: lvrUnhandled)
