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

## Where a picker's parts go on the screen, derived each frame from its size,
## so the drawing, the screen cursor and the list's scroll agree.

import ../unicode_utils

type
  PickerRect* = object
    x*, y*, width*, height*: int

  PickerLayout* = object
    frame*: PickerRect ## The box, its border included
    prompt*: PickerRect ## The query's row, after the `> ` and before the count
    countX*: int
    separatorY*: int
    list*: PickerRect

const
  PickerSizeRatio = 0.8
  PickerMinWidth = 24
  PickerMinHeight = 6
  PromptMark* = "> "

proc pickerLayout*(width, height, bottomReserve: int, countWidth = 0): PickerLayout =
  ## A box in the middle of the screen above the command line and the status
  ## line (`bottomReserve` rows): the prompt on top, the list under it.
  ## `countWidth` is the width of the count the prompt's row ends with.
  let
    room = max(0, height - bottomReserve)
    w = min(width, max(PickerMinWidth, int(width.float * PickerSizeRatio)))
    h = min(room, max(PickerMinHeight, int(room.float * PickerSizeRatio)))
    x = max(0, (width - w) div 2)
    y = max(0, (room - h) div 2)
    innerX = x + 1
    innerWidth = max(0, w - 2)
  result.frame = PickerRect(x: x, y: y, width: w, height: h)
  result.countX = max(innerX, innerX + innerWidth - countWidth - 1)
  let promptX = min(innerX + PromptMark.len, result.countX)
  result.prompt = PickerRect(
    x: promptX, y: y + 1, width: max(0, result.countX - 1 - promptX), height: 1
  )
  result.separatorY = y + 2
  result.list =
    PickerRect(x: innerX, y: y + 3, width: innerWidth, height: max(0, h - 4))

proc shown*(layout: PickerLayout): bool =
  ## Whether the box has room for its border.
  layout.frame.width >= 3 and layout.frame.height >= 3

proc promptScroll*(text: string, cursor, width: int): tuple[skip, cursorX: int] =
  ## The cells of `text` scrolled off the left of a `width` field so its
  ## `cursor` (a character) shows, and where the cursor is in the field.
  let before = text.displayWidthUpTo(cursor)
  let skip = max(0, before - max(0, width - 1))
  (skip, before - skip)
