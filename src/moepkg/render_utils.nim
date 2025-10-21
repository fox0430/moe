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

## Rendering helper functions and utilities
##
## This module contains pure functions and utilities for rendering operations
## that don't depend heavily on Editor state. Extracted from editor.nim to
## improve modularity and prepare for additional rendering features.

import pkg/celina
import std/unicode

import types, buffer, unicode_utils

# Rendering constants
const
  TAB_CHAR* = 0x09.Rune ## Tab character constant

  StatusLineReserve* = 1
  CommandLineReserve* = 1
  StatusAndCommandReserve* = 2

  # Line number display constants
  LineNumberBase* = 1 # Convert 0-based index to 1-based display
  LineNumberSpacer* = 1 # Space after line number
  LineNumberPadding* = 1 # Padding for alignment
  LineNumberWidthExtra* = 2 # Extra width for line number area (number + spaces)

# Rendering styles
let
  normalStyle* =
    Style(fg: ColorValue(kind: Default), bg: ColorValue(kind: Default), modifiers: {})
  visualStyle* = Style(
    fg: ColorValue(kind: Default),
    bg: ColorValue(kind: Indexed, indexed: Color.Blue),
    modifiers: {},
  )
  lineNumStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.BrightBlack),
    bg: ColorValue(kind: Default),
    modifiers: {},
  )
  currentLineStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.Yellow),
    bg: ColorValue(kind: Default),
    modifiers: {StyleModifier.Bold},
  )
  separatorStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.BrightBlack),
    bg: ColorValue(kind: Default),
    modifiers: {},
  )
  commandStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.White),
    bg: ColorValue(kind: Default),
    modifiers: {StyleModifier.Bold},
  )

# Pure utility functions

proc formatLineNumber*(lineIndex: int, width: int): string =
  ## Format a line number string with proper alignment
  align($(lineIndex + LineNumberBase), width - LineNumberPadding) & " "

proc calculateWrapCount*(lineCharLen: int, maxWidth: int): int =
  ## Calculate how many screen lines a logical line will take when wrapped
  if lineCharLen == 0:
    1
  else:
    ((lineCharLen - 1) div maxWidth) + 1

proc clearBuffer*(buffer: var Buffer) =
  ## Clear the entire buffer to prevent rendering artifacts
  let clearStyle =
    Style(fg: ColorValue(kind: Default), bg: ColorValue(kind: Default), modifiers: {})

  for y in 0 ..< buffer.area.height:
    for x in 0 ..< buffer.area.width:
      buffer[x, y] = cell(" ", clearStyle)

# Layout calculation functions

proc calculateLineNumOffset*(buffer: TextBuffer): int =
  ## Calculate line number display offset based on buffer size
  if buffer.len > 0:
    len($buffer.len) + LineNumberSpacer
  else:
    0

proc findMaxBottomY*(windows: seq[EditorWindow]): int =
  ## Find the maximum bottom Y coordinate among all windows
  result = 0
  for window in windows:
    let bottomY = window.viewport.y + window.viewport.height
    if bottomY > result:
      result = bottomY

proc calculateWindowStatusLineY*(window: EditorWindow, isBottomWindow: bool): int =
  ## Calculate Y position for window status line
  ## Bottom windows: place above command line (height - 2)
  ## Non-bottom windows: place at window bottom (height - 1)
  if isBottomWindow:
    window.viewport.y + window.viewport.height - 2
  else:
    window.viewport.y + window.viewport.height - 1

# Display width calculation with tab support

proc displayWidthUpToWithTabs*(text: string, charPos: int, tabStop: int): int =
  ## Calculate the display width from start to charPos, accounting for tab characters
  ## charPos is a character index (not byte position)
  ## Tab characters expand to the next tab stop position
  ##
  ## Note: If tabStop <= 0, it defaults to 1 to prevent division by zero.
  ##       If charPos < 0, returns 0.

  # Guard against invalid inputs without crashing
  if charPos < 0:
    return 0

  let safeTabStop = if tabStop > 0: tabStop else: 1

  result = 0
  var currentChar = 0

  for rune in text.runes:
    if currentChar >= charPos:
      break

    # Handle tab character specially
    if rune == TAB_CHAR:
      # Calculate spaces to next tab stop
      let spacesToNextTab = safeTabStop - (result mod safeTabStop)
      result += spacesToNextTab
    else:
      result += runeWidth(rune)

    currentChar += 1

proc displayWidthWithTabs*(text: string, tabStop: int): int =
  ## Calculate the display width of a string, accounting for tab characters
  ## Tab characters expand to the next tab stop position
  ##
  ## Note: If tabStop <= 0, it defaults to 1 to prevent division by zero.

  let safeTabStop = if tabStop > 0: tabStop else: 1

  result = 0
  for rune in text.runes:
    if rune == TAB_CHAR:
      let spacesToNextTab = safeTabStop - (result mod safeTabStop)
      result += spacesToNextTab
    else:
      result += runeWidth(rune)
