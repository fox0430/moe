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

import std/options
import ui, color, unicodeext, independentutils

type
  PopupWindow* = ref object
    window: Window
      # Ncurses window
    position*: Position
      # Absolute position
    size*: Size
      # Window size
    buffer*: seq[Runes]
      # contents
    currentLine*: Option[int]
      # Current line number

proc initPopupWindow*(
  position: Position,
  size: Size,
  buffer: seq[Runes]): PopupWindow {.inline.} =

    PopupWindow(
      window: initWindow(
        size.h,
        size.w,
        position.y,
        position.x,
        EditorColorPairIndex.popUpWindow.ord),
      position: position,
      size: size,
      buffer: buffer)

proc initPopupWindow*(position: Position, size: Size): PopupWindow {.inline.} =
  initPopupWindow(position, size, @[])

proc initPopupWindow*(): PopupWindow {.inline.} =
  initPopupWindow(Position(y: 0, x: 0), Size(h: 1, w: 1), @[])

proc refresh*(p: var PopupWindow) {.inline.} =
  p.window.refresh

proc resize*(p: var PopupWindow, h, w: Natural) =
  ## Resize the window in the same position.

  p.size.h = h
  p.size.w = w

  p.window.resize(p.size.h, p.size.w, p.position.y, p.position.x)

proc resize*(p: var PopupWindow, size: Size) {.inline.} =
  p.resize(size.h, size.w)

proc move*(p: var PopupWindow, y, x: Natural) =
  ## Move the popup window position.

  p.position.y = y
  p.position.x = x

  p.window.move(p.position.y, p.position.x)

proc move*(p: var PopupWindow, position: Position) {.inline.} =
  p.move(position.y, position.x)

proc autoMoveAndResize*(
  p: var PopupWindow,
  minPosition, maxPosition: Position) =
    ## Automatically move and resize the popup window to the best position
    ## within the range.
    ##
    ## If the display range is small, display as much as possible.
    ##
    ## Priority is given to the below and right side of the current position.
    ##
    ## Window size and position are determined from current window position,
    ## displayable area, and buffer size.

    let
      bufferMaxLen = p.buffer.maxLen

      aboveHeight = max(0, p.position.y - minPosition.y)
      belowHeight = max(0, maxPosition.y - p.position.y)
      rightWidth = max(0, maxPosition.x - p.position.x)
      leftWidth = max(0, p.position.x - minPosition.x)

      # If true, display the window below the current `p.position.y`.
      isBelow = p.buffer.len < belowHeight or belowHeight > aboveHeight
      # If true, display the window right the current `p.position.x`.
      isRight = bufferMaxLen < rightWidth or rightWidth > leftWidth

    let
      y =
        if isBelow: p.position.y
        else: max(minPosition.y, aboveHeight - p.buffer.len)
      x =
        if isRight: p.position.x
        else: max(minPosition.x, leftWidth - bufferMaxLen)

      # If the buffer length is smaller than the displayable area, the
      # buffer length will be maximized.

      h =
        if isBelow: min(p.buffer.len, belowHeight)
        else: min(p.buffer.len, aboveHeight)
      w =
        if isRight: min(bufferMaxLen, rightWidth)
        else: min(bufferMaxLen, leftWidth)

    p.resize(Size(h: max(1, h), w: max(1, w)))
    p.move(Position(y: y, x: x))

proc update*(p: var PopupWindow) =
  ## Write popup window to the UI.
  ##
  ## If buffer is larger than window size, display as much as possible.
  ##
  ## If the number of lines in the buffer is larger than the window height and
  ## the currentline is set, the display range will be automatically adjusted.

  let startLine =
    if p.currentLine.isSome and p.currentLine.get - p.size.h >= 0:
      p.currentLine.get - p.size.h + 1
    else:
      0

  p.window.erase

  for i in 0 ..< min(p.size.h, p.buffer.len):
    let
      line = p.buffer[i + startLine]
      color =
        if p.currentLine.isSome and i + startLine == p.currentLine.get:
          EditorColorPairIndex.popUpWinCurrentLine
        else:
          EditorColorPairIndex.popUpWindow

    p.window.write(
      i,
      0,
      line[0 .. min(line.high, p.size.w)],
      color.int16,
      Attribute.normal,
      false)

  p.refresh

proc close*(p: var PopupWindow) =
  ## Delete the popup window.
  ## Need `status.update` after delete it.

  if p.window != nil:
    p.window.deleteWindow
