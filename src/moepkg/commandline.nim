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

import std/[sequtils, options, math]
import ui, unicodeext, color, independentutils, editorview, highlight, cursor
import lsp/client

type
  CommandLine* = ref object
    buffer*: Runes ## The prompt doesn't include in the buffer.
    prompt: Runes ## The prompt show before the buffer.
    bufferPosition: int ## The buffer position.
    cursor: CursorPosition
    color*: EditorColorPairIndex
    window*: Window ## Ncurses window
    view*: EditorView ## Command line view
    isUpdate*: bool ## Update flag
    y*, x*, h*, w*: int ## Window position and window size

  CommandLinePrompt* {.pure.} = enum
    ex = ":"
    searchForward = "/"
    searchBackward = "?"
    documentSymbol = "#"

proc initCommandLineHighlight(
    buffer: seq[Runes], color: EditorColorPairIndex
): Highlight =
  ## TODO: Move to highlight module?

  if buffer.len > 0:
    return initHighlight(buffer, color)

proc initCommandLine*(): Result[CommandLine, string] =
  var c = CommandLine()

  # Init the command line window
  const
    Color = EditorColorPairIndex.default.int16
    H = 1
    W = 1
    Y = 1
    X = 0

  var win = initWindow(H, W, Y, X, Color)
  if win.isErr:
    return Result[CommandLine, string].err win.error

  c.window = win.get
  c.color = EditorColorPairIndex.commandLine

  c.buffer = ru""

  c.view = initEditorView(@[c.buffer], H, W)
  c.view.config.isHighlightCurrentLine = false

  return Result[CommandLine, string].ok c

proc calcWindowaHeight*(commandLine: CommandLine, newWinHeight: int = -1): int =
  if newWinHeight == -1 and commandLine.w < 1:
    return 1

  let winHeight = if newWinHeight > -1: newWinHeight else: commandLine.w
  return
    int(max(1.0, ceil((commandLine.prompt.len + commandLine.buffer.len) / winHeight)))

proc resize*(c: CommandLine, y, x, h, w: int) =
  c.window.resize(h, w, y, x)

  let buffer = @[c.prompt & c.buffer]

  const
    WidthOfLineNum = 1
    TopLine = 0
  c.view.resize(buffer, h, w, WidthOfLineNum)
  c.view.reload(buffer, TopLine)

  c.isUpdate = true

  c.y = y
  c.x = x
  c.h = h
  c.w = w

proc erase*(c: CommandLine) {.inline.} =
  c.window.erase

template isEmpty(b: seq[Runes]): bool =
  b.len == 0 or (b.len == 1 and b[0].len == 0)

template moveCursor(c: CommandLine) =
  c.window.moveCursor(c.cursor.y, c.cursor.x + 1)

proc update*(c: CommandLine) =
  ## Update the command line view and window.

  # EditorView require 2d array.
  let buffer = @[c.prompt & c.buffer]

  var highlight = initCommandLineHighlight(buffer, c.color)

  const
    CurrentLine = 0
    TopLine = 0

  # Reload Editorview. This is not the actual terminal view.
  c.view.reload(buffer, TopLine)

  c.erase

  let windowPosition = Position(x: 0, y: 0)
  var currentLineColorPair = 0
  c.view.update(
    c.window, buffer, highlight, windowPosition, CurrentLine, currentLineColorPair
  )

  if not buffer.isEmpty:
    c.cursor.update(c.view, CurrentLine, c.bufferPosition)
    c.moveCursor

  c.window.noutrefresh

  c.isUpdate = false

proc refreshWindow*(commandLine: CommandLine) {.inline.} =
  commandLine.window.refresh

proc clear*(c: CommandLine) =
  c.buffer = "".toRunes
  c.prompt = "".toRunes
  c.bufferPosition = 0
  c.color = EditorColorPairIndex.commandLine
  c.isUpdate = true

proc clearPrompt*(c: CommandLine) {.inline.} =
  c.prompt = "".toRunes
  c.isUpdate = true

proc moveLeft*(c: CommandLine) {.inline.} =
  if c.bufferPosition > 0:
    c.bufferPosition.dec
    c.isUpdate = true

proc moveRight*(c: CommandLine) {.inline.} =
  if c.bufferPosition < c.buffer.len:
    c.bufferPosition.inc
    c.isUpdate = true

proc moveTop*(c: CommandLine) {.inline.} =
  c.bufferPosition = 0
  c.isUpdate = true

proc moveEnd*(c: CommandLine) {.inline.} =
  c.bufferPosition = c.buffer.len
  c.isUpdate = true

proc deleteChar*(c: CommandLine) =
  ## Remove a character before the cursor and move to left.

  if c.bufferPosition > 0:
    c.bufferPosition.dec
    c.buffer.delete(c.bufferPosition)
    c.isUpdate = true

proc deleteCurrentChar*(c: CommandLine) =
  if c.buffer.high >= c.bufferPosition:
    c.buffer.delete(c.bufferPosition)
    c.isUpdate = true

proc delete*(c: CommandLine, slice: Slice) {.inline.} =
  c.buffer.delete(slice)
  c.isUpdate = true

proc insert*(c: CommandLine, r: Rune, pos: int) =
  ## Insert a character to the command line buffer and move to Right.

  c.buffer.insert(r, pos)
  if c.bufferPosition < c.buffer.len:
    c.bufferPosition.inc
    c.isUpdate = true

proc insert*(c: CommandLine, r: Rune) {.inline.} =
  ## Insert text to the command line buffer and move to Right.

  c.insert(r, c.bufferPosition)
  c.isUpdate = true

proc insert*(c: CommandLine, runes: Runes, pos: int) =
  ## Insert text to the command line buffer and move to Right.

  c.buffer.insert(runes, pos)
  if c.bufferPosition < c.buffer.len:
    c.bufferPosition += runes.len

  c.isUpdate = true

proc insert*(c: CommandLine, runes: Runes) {.inline.} =
  ## Insert text to the command line buffer and move to Right.

  c.insert(runes, c.bufferPosition)
  c.isUpdate = true

proc write*(c: CommandLine, runes: Runes) =
  ## Clear and show messages.

  c.clear
  c.insert(runes)
  c.isUpdate = true

proc writeError*(c: CommandLine, runes: Runes) =
  ## Clear and show error messages.

  # TODO: Change color to the error color.
  c.clear
  c.insert(runes)
  c.isUpdate = true

proc writeWarn*(c: CommandLine, runes: Runes) =
  ## Clear and show warning messages.

  # TODO: Change color to the wanrning color.
  c.clear
  c.insert(runes)
  c.isUpdate = true

proc buffer*(c: CommandLine): Runes {.inline.} =
  ## Return commandLine.buffer

  c.buffer

proc getPrompt*(c: CommandLine): Runes {.inline.} =
  ## Return commandLine.prompt

  c.prompt

proc setPrompt*(c: CommandLine, p: CommandLinePrompt | string) {.inline.} =
  ## Set a prompt to commandLine.prompt

  c.prompt = toRunes($p)
  c.isUpdate = true

proc setPrompt*(c: CommandLine, r: Runes) {.inline.} =
  c.setPrompt($r)

proc setColor*(c: CommandLine, color: EditorColorPairIndex) {.inline.} =
  ## Set a color for command line prompt and buffer.

  c.color = color

proc color*(c: CommandLine): EditorColorPairIndex {.inline.} =
  ## Return commandLine.color

  c.color

proc bufferPosition*(c: CommandLine): int {.inline.} =
  c.bufferPosition

proc setBufferPosition*(c: CommandLine, pos: int) {.inline.} =
  c.bufferPosition = pos
  c.isUpdate = true

proc cursorPosition*(c: CommandLine): Position {.inline.} =
  c.window.getCursorPosition

proc absCursorPosition*(c: CommandLine): Position {.inline.} =
  c.window.getAbsCursorPosition

proc windowPosition*(c: CommandLine): Position {.inline.} =
  Position(y: c.window.y, x: c.window.x)

proc getKey*(c: CommandLine): Option[Rune] {.inline.} =
  ## Return a single Key.

  return getKey()

proc getKeyBlocking*(c: CommandLine): Rune {.inline.} =
  ## Return a single Key.

  return getKeyBlocking()

proc isUpdate*(c: CommandLine): bool {.inline.} =
  c.isUpdate

proc getKeys*(c: CommandLine, prompt: string): bool =
  ## Get keys and update command line until confirmed or canceled.
  ## Received keys are added to the command line buffer.
  ## Return true if confirmed.
  ##
  ## WARN: Cannot resize windows/views while getting keys.

  c.clear
  c.setPrompt(prompt)

  while true:
    c.update

    var key: Option[Rune]
    while key.isNone:
      key = c.getKey

    if isEnterKey(key.get):
      return true
    elif isEscKey(key.get) or ctrlCPressed:
      c.clear
      return false
    elif isBackspaceKey(key.get):
      c.deleteChar
    elif isDeleteKey(key.get):
      c.deleteCurrentChar
    elif isLeftKey(key.get):
      c.moveLeft
    elif isRightKey(key.get):
      c.moveRight
    elif isHomeKey(key.get):
      c.moveTop
    elif isEndKey(key.get):
      c.moveEnd
    else:
      c.insert(key.get)
