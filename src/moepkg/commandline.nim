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
import ui, unicodeext, color, independentutils, editorview, highlight
import lsp/client

type
  CommandLine* = object
    buffer*: Runes ## The prompt doesn't include in the buffer.
    prompt: Runes ## The prompt show before the buffer.
    bufferPosition: Position ## the buffer position
    color*: EditorColorPairIndex
    window*: Window ## Ncurses window
    view*: EditorView ## Comand line view
    isUpdate: bool ## Update flag
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

proc initCommandLine*(): CommandLine =
  # Init the command line window
  const
    Color = EditorColorPairIndex.default.int16
    H = 1
    W = 1
    Y = 1
    X = 0
  result.window = initWindow(H, W, Y, X, Color)
  result.color = EditorColorPairIndex.commandLine

  result.buffer = ru""

  result.view = initEditorView(@[result.buffer], H, W)
  result.view.config.isHighlightCurrentLine = false

proc calcWindowaHeight*(commandLine: CommandLine, newWinHeight: int = -1): int =
  if newWinHeight == -1 and commandLine.w < 1:
    return 1

  let winHeight = if newWinHeight > -1: newWinHeight else: commandLine.w
  return
    int(max(1.0, ceil((commandLine.prompt.len + commandLine.buffer.len) / winHeight)))

proc resize*(commandLine: var CommandLine, y, x, h, w: int) =
  commandLine.window.resize(h, w, y, x)

  let buffer = @[commandLine.prompt & commandline.buffer]

  const
    WidthOfLineNum = 1
    TopLine = 0
  commandLine.view.resize(buffer, h, w, WidthOfLineNum)
  commandLine.view.reload(buffer, TopLine)

  commandLine.isUpdate = true

  commandLine.y = y
  commandLine.x = x
  commandLine.h = h
  commandLine.w = w

proc erase*(commandLine: var CommandLine) {.inline.} =
  commandLine.window.erase

proc update*(commandLine: var CommandLine) =
  ## Update the command line view and window.

  let buffer = @[commandLine.prompt & commandLine.buffer]

  var highlight = initCommandLineHighlight(buffer, commandLine.color)

  # Reload Editorview. This is not the actual terminal view.
  commandLine.view.reload(buffer, 0)

  commandLine.erase

  const CurrentLine = 0
  let windowPosition = Position(x: 0, y: 0)
  var currentLineColorPair = 0
  commandLine.view.update(
    commandLine.window, buffer, highlight, windowPosition, CurrentLine,
    currentLineColorPair,
  )

  commandLine.window.noutrefresh

  commandLine.isUpdate = false

proc refreshWindow*(commandLine: CommandLine) {.inline.} =
  commandLine.window.refresh

proc clear*(commandLine: var CommandLine) =
  commandLine.buffer = "".toRunes
  commandLine.prompt = "".toRunes
  commandLine.bufferPosition.x = 0
  commandLine.bufferPosition.y = 0
  commandLine.color = EditorColorPairIndex.commandLine
  commandLine.isUpdate = true

proc clearPrompt*(commandLine: var CommandLine) {.inline.} =
  commandLine.prompt = "".toRunes
  commandLine.isUpdate = true

proc moveLeft*(commandLine: var CommandLine) {.inline.} =
  if commandLine.bufferPosition.x > 0:
    commandLine.bufferPosition.x.dec
    commandLine.isUpdate = true

proc moveRight*(commandLine: var CommandLine) {.inline.} =
  if commandLine.bufferPosition.x < commandLine.buffer.len:
    commandLine.bufferPosition.x.inc
    commandLine.isUpdate = true

proc moveTop*(commandLine: var CommandLine) {.inline.} =
  commandLine.bufferPosition.x = 0
  commandLine.isUpdate = true

proc moveEnd*(commandLine: var CommandLine) {.inline.} =
  commandLine.bufferPosition.x = commandLine.buffer.len
  commandLine.isUpdate = true

proc deleteChar*(commandLine: var CommandLine) =
  ## Remove a character before the cursor and move to left.

  if commandLine.bufferPosition.x > 0:
    commandLine.bufferPosition.x.dec
    commandLine.buffer.delete(commandLine.bufferPosition.x)
    commandLine.isUpdate = true

proc deleteCurrentChar*(commandLine: var CommandLine) =
  if commandLine.buffer.high >= commandLine.bufferPosition.x:
    commandLine.buffer.delete(commandLine.bufferPosition.x)
    commandLine.isUpdate = true

proc delete*(commandLine: var CommandLine, slice: Slice) {.inline.} =
  commandLine.buffer.delete(slice)
  commandLine.isUpdate = true

proc insert*(commandLine: var CommandLine, r: Rune, pos: int) =
  ## Insert a character to the command line buffer and move to Right.

  commandLine.buffer.insert(r, pos)
  if commandLine.bufferPosition.x < commandLine.buffer.len:
    commandLine.bufferPosition.x.inc
    commandLine.isUpdate = true

proc insert*(commandLine: var CommandLine, r: Rune) {.inline.} =
  ## Insert text to the command line buffer and move to Right.

  commandLine.insert(r, commandLine.bufferPosition.x)
  commandLine.isUpdate = true

proc insert*(commandLine: var CommandLine, runes: Runes, pos: int) =
  ## Insert text to the command line buffer and move to Right.

  commandLine.buffer.insert(runes, pos)
  if commandLine.bufferPosition.x < commandLine.buffer.len:
    commandLine.bufferPosition.x += runes.len

  commandLine.isUpdate = true

proc insert*(commandLine: var CommandLine, runes: Runes) {.inline.} =
  ## Insert text to the command line buffer and move to Right.

  commandLine.insert(runes, commandLine.bufferPosition.x)
  commandLine.isUpdate = true

proc write*(commandLine: var CommandLine, runes: Runes) =
  ## Clear and show messages.

  commandLine.clear
  commandLine.insert(runes)
  commandLine.isUpdate = true

proc writeError*(commandLine: var CommandLine, runes: Runes) =
  ## Clear and show error messages.

  # TODO: Change color to the error color.
  commandLine.clear
  commandLine.insert(runes)
  commandLine.isUpdate = true

proc writeWarn*(commandLine: var CommandLine, runes: Runes) =
  ## Clear and show warning messages.

  # TODO: Change color to the wanrning color.
  commandLine.clear
  commandLine.insert(runes)
  commandLine.isUpdate = true

proc buffer*(commandLine: CommandLine): Runes {.inline.} =
  ## Return commandLine.buffer

  commandLine.buffer

proc getPrompt*(commandLine: CommandLine): Runes {.inline.} =
  ## Return commandLine.prompt

  commandLine.prompt

proc setPrompt*(
    commandLine: var CommandLine, p: CommandLinePrompt | string
) {.inline.} =
  ## Set a prompt to commandLine.prompt

  commandLine.prompt = toRunes($p)
  commandLine.isUpdate = true

proc setPrompt*(commandLine: var CommandLine, r: Runes) {.inline.} =
  commandLine.setPrompt($r)

proc setColor*(commandLine: var CommandLine, c: EditorColorPairIndex) {.inline.} =
  ## Set a color for command line prompt and buffer.

  commandLine.color = c

proc color*(commandLine: CommandLine): EditorColorPairIndex {.inline.} =
  ## Return commandLine.color

  commandLine.color

proc bufferPosition*(commandLine: CommandLine): Position {.inline.} =
  commandLine.bufferPosition

proc bufferPositionX*(commandLine: CommandLine): int {.inline.} =
  commandLine.bufferPosition.x

proc bufferPositionY*(commandLine: CommandLine): int {.inline.} =
  commandLine.bufferPosition.y

proc setBufferPosition*(commandLine: var CommandLine, pos: Position) {.inline.} =
  commandLine.bufferPosition = pos
  commandLine.isUpdate = true

proc setBufferPositionX*(commandLine: var CommandLine, x: int) {.inline.} =
  commandLine.bufferPosition.x = x
  commandLine.isUpdate = true

proc setBufferPositionY*(commandLine: var CommandLine, y: int) {.inline.} =
  commandLine.bufferPosition.y = y
  commandLine.isUpdate = true

proc cursorPosition*(commandLine: CommandLine): Position {.inline.} =
  commandLine.window.getCursorPosition

proc absCursorPosition*(commandLine: CommandLine): Position {.inline.} =
  commandLine.window.getAbsCursorPosition

proc windowPosition*(commandLine: CommandLine): Position {.inline.} =
  Position(y: commandLine.window.y, x: commandLine.window.x)

proc getKey*(commandLine: var CommandLine): Option[Rune] {.inline.} =
  ## Return a single Key.

  return getKey()

proc getKeyBlocking*(commandLine: var CommandLine): Rune {.inline.} =
  ## Return a single Key.

  return getKeyBlocking()

proc isUpdate*(commandLine: CommandLine): bool {.inline.} =
  commandLine.isUpdate

proc getKeys*(commandLine: var CommandLine, prompt: string): bool =
  ## Get keys and update command line until confirmed or canceled.
  ## Received keys are added to the command line buffer.
  ## Return true if confirmed.
  ##
  ## WARN: Cannot resize windows/views while getting keys.

  commandLine.clear
  commandLine.setPrompt(prompt)

  while true:
    commandLine.update

    var key: Option[Rune]
    while key.isNone:
      key = commandLine.getKey

    if isEnterKey(key.get):
      return true
    elif isEscKey(key.get) or ctrlCPressed:
      commandLine.clear
      return false
    elif isBackspaceKey(key.get):
      commandLine.deleteChar
    elif isDeleteKey(key.get):
      commandLine.deleteCurrentChar
    elif isLeftKey(key.get):
      commandLine.moveLeft
    elif isRightKey(key.get):
      commandLine.moveRight
    elif isHomeKey(key.get):
      commandLine.moveTop
    elif isEndKey(key.get):
      commandLine.moveEnd
    else:
      commandLine.insert(key.get)
