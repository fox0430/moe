#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[sequtils]
import ui, unicodeext, color, independentutils

type
  CommandLine* = object
    # TODO: Add EditorView to CommandLine?

    buffer*: Runes
      ## The prompt doesn't include in the buffer.

    prompt: Runes
      ## The prompt show before the buffer.

    windowPosition: Position
      ## the command line window position.

    bufferPosition: Position
      ## the buffer position

    color: EditorColorPairIndex
      ## TODO: Change type from EditorColorPairIndex to Highlight.

    window*: Window
      ## Ncurses window

    isUpdate: bool
      ## Update flag

const
  ExModePrompt* = ":"
  SearchForwardModePrompt* = "/"
  SearchBackwardModePrompt* = "?"

proc initCommandLine*(): CommandLine =
  result.color = EditorColorPairIndex.default

  # Init the command line window
  const
    t = 0
    l = 0
    color = EditorColorPairIndex.default
  let
    w = getTerminalWidth()
    h = getTerminalHeight() - 1
  result.window = initWindow(h, w, t, l, color.int16)
  result.window.setTimeout()

proc resize*(commandLine: var CommandLine, y, x, h, w: int) {.inline.} =
  commandLine.window.resize(h, w, y, x)
  commandLine.isUpdate = true

proc getDisplayRange(commandLine: CommandLine): tuple[first, last: int] =
  if commandLine.bufferPosition.x > commandLine.window.width:
    result.first = commandLine.bufferPosition.x - commandLine.window.width
    result.last = min(commandLine.buffer.high, commandLine.window.width)
  else:
    result.first = 0
    result.last = commandLine.buffer.high

proc seekCursor*(commandLine: CommandLine): Position {.inline.} =
  ## Return the cursor position.

  Position(
    x: commandLine.prompt.len + commandLine.bufferPosition.x,
    y: commandLine.bufferPosition.y)

proc update*(commandLine: var CommandLine) =
  ## Update the command line view and window.

  let
    range = commandLine.getDisplayRange
    buffer =
      commandLine.prompt &
      commandLine.buffer[range.first .. range.last]

  commandLine.window.erase
  commandLine.window.write(0, 0, buffer, commandLine.color.int16)
  commandLine.window.refresh

  commandLine.isUpdate = false

  let cursorPos = commandLine.seekCursor
  commandLine.window.moveCursor(cursorPos.y, cursorPos.x)

proc clear*(commandLine: var CommandLine) =
  commandLine.buffer = "".toRunes
  commandLine.prompt = "".toRunes
  commandLine.bufferPosition.x = 0
  commandLine.bufferPosition.y = 0
  commandLine.color = EditorColorPairIndex.default
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

proc insert*(commandLine: var CommandLine, r: Rune, pos: int) =
  ## Insert a character to the command line buffer and move to Right.

  commandLine.buffer.insert(r, pos)
  if commandLine.bufferPosition.x < commandLine.buffer.len:
    commandLine.bufferPosition.x.inc
    commandLine.isUpdate = true

proc insert*(commandLine: var CommandLine, r: Rune) {.inline.} =
  ## Insert text to the command line buffer and move to Right.

  commandLine.insert(r, commandLine.bufferPosition.x)

proc insert*(commandLine: var CommandLine, runes: Runes, pos: int) =
  ## Insert text to the command line buffer and move to Right.

  commandLine.buffer.insert(runes, pos)
  if commandLine.bufferPosition.x < commandLine.buffer.len:
    commandLine.bufferPosition.x.inc

proc insert*(commandLine: var CommandLine, runes: Runes) {.inline.} =
  ## Insert text to the command line buffer and move to Right.

  commandLine.insert(runes, commandLine.bufferPosition.x)

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

proc buffer*(commandLine: CommandLine) : Runes {.inline.} =
  ## Return commandLine.buffer

  commandLine.buffer

proc setPrompt*(commandLine: var CommandLine, s: string) {.inline.} =
  ## Set test to commandLine.prompt

  commandLine.prompt = s.toRunes
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

proc setBufferPosition*(
  commandLine: var CommandLine,
  pos: Position) {.inline.} =
    commandLine.bufferPosition = pos
    commandLine.isUpdate = true

proc setBufferPositionX*(commandLine: var CommandLine, x: int) {.inline.} =
  commandLine.bufferPosition.x = x
  commandLine.isUpdate = true

proc setBufferPositionY*(commandLine: var CommandLine, y: int) {.inline.} =
  commandLine.bufferPosition.y = y
  commandLine.isUpdate = true

proc getKey*(commandLine: var CommandLine): Rune {.inline.} =
  ## Return a single Key.

  commandLine.window.getKey

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

    let key = commandLine.getKey

    if isEnterKey(key):
      return true
    elif isEscKey(key) or pressCtrlC:
      commandLine.clear
      return false

    elif isBackspaceKey(key):
      commandLine.deleteChar
    elif isDcKey(key):
      commandLine.deleteCurrentChar

    elif isLeftKey(key):
      commandLine.moveLeft
    elif isRightKey(key):
      commandLine.moveRight
    elif isHomeKey(key):
      commandLine.moveTop
    elif isEndKey(key):
      commandLine.moveEnd

    else:
      commandLine.insert(key)
