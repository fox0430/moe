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

import std/[options, strutils]

import pkg/results

import ui, color, unicodeext, independentutils, searchutils

type
  HighlightText = object
    text: Runes
    isIgnorecase, isSmartcase: bool

  PopupWindow* = ref object
    window: Window # Ncurses window
    position*: Position # Absolute position
    size*: Size # Window size
    buffer*: seq[Runes] # contents
    currentLine*: Option[int] # Current line number
    highlightText*: Option[HighlightText] # Change the color of matching texts
    showBorder*: bool # Show/Hide window border

proc initPopupWindow*(
    position: Position, size: Size, buffer: seq[Runes], showBorder: bool = false
): Result[PopupWindow, string] =
  var win = initWindow(
    size.h, size.w, position.y, position.x, EditorColorPairIndex.popUpWindow.ord
  )
  if win.isErr:
    return Result[PopupWindow, string].err win.error

  var p = PopupWindow(
    window: win.get,
    position: position,
    size: size,
    buffer: buffer,
    showBorder: showBorder,
  )

  return Result[PopupWindow, string].ok p

proc initPopupWindow*(
    position: Position, size: Size, showBorder: bool = false
): Result[PopupWindow, string] {.inline.} =
  return initPopupWindow(position, size, @[], showBorder)

proc initPopupWindow*(): Result[PopupWindow, string] {.inline.} =
  return initPopupWindow(Position(y: 0, x: 0), Size(h: 1, w: 1), @[])

proc refresh*(p: var PopupWindow) {.inline.} =
  p.window.refresh

proc noutrefresh*(p: var PopupWindow) {.inline.} =
  p.window.noutrefresh

proc overlay*(p: var PopupWindow, destWin: var Window) {.inline.} =
  overlay(p.window, destWin)

proc overwrite*(p: var PopupWindow, destWin: var Window) {.inline.} =
  overwrite(p.window, destWin)

proc resize*(p: var PopupWindow, h, w: Natural) =
  ## Resize the window in the same position.

  p.size.h = h
  p.size.w = w

  p.window.resize(p.size.h, p.size.w, p.position.y, p.position.x)

proc resize*(p: var PopupWindow, size: Size) {.inline.} =
  p.resize(size.h, size.w)

proc resize*(p: var PopupWindow) {.inline.} =
  p.resize(p.size)

proc move*(p: var PopupWindow, y, x: Natural) =
  ## Move the popup window position.

  p.position.y = y
  p.position.x = x

  p.window.move(p.position.y, p.position.x)

proc move*(p: var PopupWindow, position: Position) {.inline.} =
  p.move(position.y, position.x)

proc move*(p: var PopupWindow) {.inline.} =
  p.window.move(p.position.y, p.position.x)

proc autoMoveAndResize*(p: var PopupWindow, minPosition, maxPosition: Position) =
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

    borderMargin = if p.showBorder: 2 else: 0

  let
    y =
      if isBelow:
        p.position.y
      else:
        max(minPosition.y, aboveHeight - p.buffer.len - borderMargin - 1)
    x =
      if isRight:
        p.position.x
      else:
        max(minPosition.x, leftWidth - bufferMaxLen)

  let
    # If the buffer length is smaller than the displayable area, the
    # buffer length will be maximized.
    h =
      if isBelow:
        min(p.buffer.len + borderMargin, belowHeight - 1)
      else:
        min(p.buffer.len + borderMargin, aboveHeight - 1)
    w =
      if isRight:
        min(bufferMaxLen + borderMargin, rightWidth)
      else:
        min(bufferMaxLen + borderMargin, leftWidth)

  p.resize(Size(h: max(1, h), w: max(1, w)))
  p.move(Position(y: y, x: x))

proc updateHighlightText*(
    p: var PopUpWindow, text: Runes, isIgnorecase, isSmartcase: bool
) {.inline.} =
  p.highlightText = some(
    HighlightText(text: text, isIgnorecase: isIgnorecase, isSmartcase: isSmartcase)
  )

proc clearHighlightText*(p: var PopupWindow) {.inline.} =
  p.highlightText = none(HighlightText)

proc update*(p: var PopupWindow) =
  ## Write a popup window to the UI.
  ##
  ## If buffer is larger than window size, display as much as possible.
  ##
  ## If the number of lines in the buffer is larger than the window height and
  ## the currentline is set, the display range will be automatically adjusted.

  let
    borderMargin = if p.showBorder: 2 else: 0

    startLine =
      if p.currentLine.isSome and p.currentLine.get - p.size.h + borderMargin >= 0:
        if p.showBorder:
          p.currentLine.get - p.size.h + borderMargin + 1
        else:
          p.currentLine.get - p.size.h + 1
      else:
        0

  p.window.erase

  for i in 0 ..< min(p.size.h, p.buffer.len):
    if i + startLine > p.buffer.high:
      break

    template removeMargin(line: Runes): Runes =
      line[1 .. (line.high - 1)]

    const WindowMargin = 2

    let
      line = p.buffer[i + startLine]

      color =
        if p.currentLine.isSome and i + startLine == p.currentLine.get:
          EditorColorPairIndex.popUpWinCurrentLine
        else:
          EditorColorPairIndex.popUpWindow

      highlightPosi =
        if p.highlightText.isSome and line.len > WindowMargin:
          line.removeMargin.search(
            p.highlightText.get.text, p.highlightText.get.isIgnorecase,
            p.highlightText.get.isSmartcase,
          )
        else:
          none(int)

      x =
        if p.showBorder:
          i + 1
        else:
          i

    if highlightPosi.isSome:
      template isHighlight(col, highlightPosi: int, highlightText: Runes): bool =
        j >= highlightPosi and j < highlightPosi + highlightText.len

      for j in 0 .. p.size.w:
        let y =
          if p.showBorder:
            j + 1
          else:
            j

        if j > line.high:
          p.window.write(x, y, ru" ", color.int16, Attribute.normal, false)
        elif isHighlight(j, highlightPosi.get, p.highlightText.get.text):
          # Change color for highlightText
          let highlightColor = EditorColorPairIndex.searchResult
          p.window.write(
            x, y, line[j].toRunes, highlightColor.int16, Attribute.normal, false
          )
        else:
          p.window.write(x, y, line[j].toRunes, color.int16, Attribute.normal, false)
    else:
      let
        y = if p.showBorder: 1 else: 0

        buffer =
          if p.size.w > line.high:
            line & " ".repeat(p.size.w - line.high - y).toRunes
          else:
            line[0 .. p.size.w - y]

      p.window.write(x, y, buffer, color.int16, Attribute.normal, false)

  if p.showBorder:
    p.window.box(0, 0, EditorColorPairIndex.popUpWindow.int16)

  p.noutrefresh

proc close*(p: var PopupWindow) =
  ## Delete the popup window.
  ## Need `status.update` after delete it.

  if p.window != nil:
    p.window.deleteWindow

proc windowPosition*(p: PopupWindow): Position {.inline.} =
  Position(y: p.window.y, x: p.window.x)
