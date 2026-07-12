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

## Shared popup drawing primitives.
##
## Both the insert-mode completion popup / documentation panel (`completion`)
## and the command-mode completion popup (`command_completion`) draw a single
## bordered box and clip rune/space runs to it. These helpers hold that common
## logic so the renderers only describe their own column layout.

import std/unicode

import pkg/celina

import unicode_utils

proc drawBorder*(termBuffer: var Buffer, x, y, width, height: int, style: Style) =
  ## Draw a single-cell box border at (x, y) spanning width × height, clipped to
  ## the buffer. The interior (content) area is the (height - 2) rows between the
  ## top and bottom edges. Corners use ┌ ┐ └ ┘ and edges use ─ │.
  if width < 2 or height < 2:
    return

  let
    left = x
    right = x + width - 1
    top = y
    bottom = y + height - 1
    w = termBuffer.area.width
    h = termBuffer.area.height

  template put(cx, cy: int, glyph: string) =
    if cx >= 0 and cx < w and cy >= 0 and cy < h:
      termBuffer[cx, cy] = cell(glyph, style)

  # Top edge
  if top >= 0 and top < h:
    put(left, top, "┌")
    for cx in max(left + 1, 0) ..< min(right, w):
      termBuffer[cx, top] = cell("─", style)
    put(right, top, "┐")

  # Side edges
  for cy in top + 1 ..< bottom:
    put(left, cy, "│")
    put(right, cy, "│")

  # Bottom edge
  if bottom >= 0 and bottom < h:
    put(left, bottom, "└")
    for cx in max(left + 1, 0) ..< min(right, w):
      termBuffer[cx, bottom] = cell("─", style)
    put(right, bottom, "┘")

proc drawClippedRunes*(
    termBuffer: var Buffer, startX, y, limitX: int, text: string, style: Style
): int =
  ## Emit the runes of `text` left-to-right starting at column startX on row y,
  ## stopping before limitX (and the buffer's right edge). Wide characters write
  ## a continuation cell via setRuneCell. Columns left of 0 are skipped (their
  ## width still advances). Returns the next free column. The caller is
  ## responsible for ensuring y is within bounds.
  result = startX
  for r in text.runes:
    let w = runeWidth(r)
    if result + w > limitX or result + w > termBuffer.area.width:
      break
    if result >= 0:
      result += setRuneCell(termBuffer, result, y, r, style)
    else:
      result += w

proc fillCells*(termBuffer: var Buffer, startX, y, limitX: int, style: Style): int =
  ## Fill columns [startX, limitX) on row y with spaces in the given style,
  ## clipped to the buffer. Returns the next column.
  result = startX
  while result < limitX and result < termBuffer.area.width:
    if result >= 0:
      termBuffer[result, y] = cell(" ", style)
    inc result
