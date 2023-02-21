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
  # TODO: Add EditorView to CommandLine?
  CommandLine* = object
    ## The prompt doesn't include in the buffer.
    buffer*: Runes

    ## The prompt show before the buffer.
    prompt: Runes

    ## The command line window position.
    windowPosition: Position

    ## The command line window size
    windowSize: Size

    ## The buffer position
    bufferPosition: Position

    ## The cursor position
    cursorPosition: Position

    # TODO: Change type from EditorColorPair to Highlight.
    color: EditorColorPair

    window*: Window

const
  exModePrompt* = ":"
  searchForwardModePrompt* = "/"
  searchBackwardModePrompt* = "?"

proc initCommandLine*(): CommandLine =
  result.color = EditorColorPair.defaultChar

  # Init the command line window
  const
    y = 0
    x = 0
  let
    w = getTerminalWidth()
    h = getTerminalHeight() - 1
    color = EditorColorPair.defaultChar
  result.window = initWindow(h, w, y, x, color)

  result.windowPosition.x = 0
  result.windowPosition.y = 0
  result.windowSize.h = h
  result.windowSize.w = w

  result.window.setTimeout()

proc resize*(commandLine: var CommandLine, y, x, h, w: int) {.inline.} =
  commandLine.window.resize(h, w, y, x)

  commandLine.windowPosition.y = y
  commandLine.windowPosition.x = x
  commandLine.windowSize.h = h
  commandLine.windowSize.w = w

proc getDisplayRange(commandLine: CommandLine): tuple[first, last: int] =
  if commandLine.bufferPosition.x > commandLine.window.width:
    result.first = commandLine.bufferPosition.x - commandLine.window.width
    result.last = min(commandLine.buffer.high, commandLine.window.width)
  else:
    result.first = 0
    result.last = commandLine.buffer.high

## Search and return the cursor position.
proc seekCursor*(commandLine: CommandLine): Position {.inline.} =
  Position(
    x: commandLine.prompt.len + commandLine.bufferPosition.x,
    y: commandLine.bufferPosition.y)

## Update the cursor position.
proc updateCursorPosition(commandLine: var CommandLine) {.inline.} =
  commandLine.window.moveCursor(
    commandLine.cursorPosition.y,
    commandLine.cursorPosition.x)

# Update the command line view (window).
proc update*(commandLine: var CommandLine) =
  let
    range = commandLine.getDisplayRange
    buffer =
      commandLine.prompt &
      commandLine.buffer[range.first .. range.last]

  commandLine.window.erase
  commandLine.window.write(0, 0, buffer, commandLine.color)
  commandLine.window.refresh

  commandLine.cursorPosition = commandLine.seekCursor
  commandLine.updateCursorPosition

proc clear*(commandLine: var CommandLine) =
  commandLine.buffer = "".toRunes
  commandLine.prompt = "".toRunes
  commandLine.bufferPosition.x = 0
  commandLine.bufferPosition.y = 0
  commandLine.color = EditorColorPair.defaultChar

proc clearPrompt*(commandLine: var CommandLine) {.inline.} =
  commandLine.prompt = "".toRunes

proc moveLeft*(commandLine: var CommandLine) {.inline.} =
  if commandLine.bufferPosition.x > 0:
    commandLine.bufferPosition.x.dec

proc moveRight*(commandLine: var CommandLine) {.inline.} =
  if commandLine.bufferPosition.x < commandLine.buffer.len:
    commandLine.bufferPosition.x.inc

proc moveTop*(commandLine: var CommandLine) {.inline.} =
  commandLine.bufferPosition.x = 0

proc moveEnd*(commandLine: var CommandLine) {.inline.} =
  commandLine.bufferPosition.x = commandLine.buffer.len

## Remove a character before the cursor and move to left.
proc deleteChar*(commandLine: var CommandLine) =
  if commandLine.bufferPosition.x > 0:
    commandLine.bufferPosition.x.dec
    commandLine.buffer.delete(commandLine.bufferPosition.x)

proc deleteCurrentChar*(commandLine: var CommandLine) =
  if commandLine.buffer.high >= commandLine.bufferPosition.x:
    commandLine.buffer.delete(commandLine.bufferPosition.x)

## Insert a character to the command line buffer and move to Right.
proc insert*(commandLine: var CommandLine, r: Rune, pos: int) =
  commandLine.buffer.insert(r, pos)
  if commandLine.bufferPosition.x < commandLine.buffer.len:
    commandLine.bufferPosition.x.inc

## Insert text to the command line buffer and move to Right.
proc insert*(commandLine: var CommandLine, r: Rune) {.inline.} =
  commandLine.insert(r, commandLine.bufferPosition.x)

## Insert text to the command line buffer and move to Right.
proc insert*(commandLine: var CommandLine, runes: Runes, pos: int) =
  commandLine.buffer.insert(runes, pos)
  if commandLine.bufferPosition.x < commandLine.buffer.len:
    commandLine.bufferPosition.x.inc

## Insert text to the command line buffer and move to Right.
proc insert*(commandLine: var CommandLine, runes: Runes) {.inline.} =
  commandLine.insert(runes, commandLine.bufferPosition.x)

## Clear and show messages.
proc write*(commandLine: var CommandLine, runes: Runes) =
  commandLine.clear
  commandLine.insert(runes)
  commandLine.update

## Clear and show error messages.
proc writeError*(commandLine: var CommandLine, runes: Runes) =
  # TODO: Change color to the error color.
  commandLine.clear
  commandLine.insert(runes)
  commandLine.update

## Clear and show warning messages.
proc writeWarn*(commandLine: var CommandLine, runes: Runes) =
  # TODO: Change color to the wanrning color.
  commandLine.clear
  commandLine.insert(runes)
  commandLine.update

## Return commandLine.buffer
proc buffer*(commandLine: CommandLine) : Runes {.inline.} = commandLine.buffer

## Set test to commandLine.prompt
proc setPrompt*(commandLine: var CommandLine, s: string) {.inline.} =
  commandLine.prompt = s.toRunes

proc setPrompt*(commandLine: var CommandLine, r: Runes) {.inline.} =
  commandLine.prompt = r

## Set a color for command line prompt and buffer.
proc setColor*(commandLine: var CommandLine, c: EditorColorPair) {.inline.} =
  commandLine.color = c

## Return commandLine.color
proc color*(commandLine: CommandLine): EditorColorPair {.inline.} =
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

proc setBufferPositionX*(commandLine: var CommandLine, x: int) {.inline.} =
  commandLine.bufferPosition.x = x

proc setBufferPositionY*(commandLine: var CommandLine, y: int) {.inline.} =
  commandLine.bufferPosition.y = y

## Return the command line window position
proc windowPosition*(commandLine: CommandLine): Position {.inline.} =
  commandLine.windowPosition

## Return the command line window size.
proc windowSize*(commandLine: CommandLine): Size {.inline.} =
  commandLine.windowSize

## Return the relative cursor position.
proc cursorPosition*(commandLine: CommandLine): Position {.inline.} =
  commandLine.cursorPosition

## Return a single Key.
proc getKey*(commandLine: var CommandLine): Rune {.inline.} =
  commandLine.window.getKey

## Get keys and update command line until confirmed or canceled.
## Received keys are added to the command line buffer.
## Return true if confirmed.
##
## WARN: Cannot resize windows/views while getting keys.
proc getKeys*(commandLine: var CommandLine, prompt: string): bool =
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
