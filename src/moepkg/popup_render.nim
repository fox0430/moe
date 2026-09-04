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
##
## The `place*` procs return a `PopupRect` for each placement pattern used by
## the popups. They share the `PopupRect` / `Screen` types so call sites agree
## on geometry and bottom-reserve semantics.

import std/unicode

import celina_backend as celina

import unicode_utils

type
  PopupRect* = object
    x*, y*, width*, height*: int

  Screen* = object
    ## Terminal geometry seen by placement helpers.
    ## `bottomReserve` is the number of rows at the bottom the popup must not
    ## cross (grown command-line / status area, plus any padding row).
    width*, height*, bottomReserve*: int

  PopupCorner* = enum
    pcTopLeft
    pcTopRight
    pcBottomLeft
    pcBottomRight

proc initScreen*(width, height: int, bottomReserve: int = 0): Screen =
  Screen(width: width, height: height, bottomReserve: bottomReserve)

proc clampXToScreen(preferredX, width, screenWidth: int): int =
  ## Keep preferredX but shift left if the popup would overflow the right edge.
  ## Never returns a negative value even if width > screenWidth.
  result = preferredX
  if result + width > screenWidth:
    result = max(0, screenWidth - width)

proc placeBelowCursor*(
    cursorX, cursorY, width, height: int, screen: Screen
): PopupRect =
  ## Popup below the cursor; falls back to above if the below placement would
  ## cross `screen.bottomReserve`. The fallback y is clamped to 0 so an
  ## oversized popup starts at the top instead of drifting off-screen.
  ## X is clamped so the popup stays inside the right edge.
  let x = clampXToScreen(cursorX, width, screen.width)
  var y = cursorY + 1
  if y + height > screen.height - screen.bottomReserve:
    y = cursorY - height
    if y < 0:
      y = 0
  PopupRect(x: x, y: y, width: width, height: height)

proc placeAboveCursor*(
    cursorX, cursorY, width, height: int, screen: Screen
): PopupRect =
  ## Popup above the cursor; falls back to below if the above placement would
  ## start above the top of the screen. If the fallback also crosses
  ## `screen.bottomReserve`, y is clamped upward so the popup's bottom row
  ## sits directly above the reserved area (or to 0 if the popup is taller
  ## than the space above the reserve, in which case it overlaps the reserve
  ## from the top).
  ## X is clamped so the popup stays inside the right edge.
  let x = clampXToScreen(cursorX, width, screen.width)
  var y = cursorY - height
  if y < 0:
    y = cursorY + 1
  if y + height > screen.height - screen.bottomReserve:
    y = max(0, screen.height - screen.bottomReserve - height)
  PopupRect(x: x, y: y, width: width, height: height)

proc placeAboveReserve*(preferredX, width, height: int, screen: Screen): PopupRect =
  ## Popup pinned so its bottom row sits directly above the reserved bottom
  ## area (top row at `screen.height - screen.bottomReserve - height`).
  ## X is clamped so the popup stays inside the right edge; y is clamped to 0.
  let x = clampXToScreen(preferredX, width, screen.width)
  let y = max(0, screen.height - screen.bottomReserve - height)
  PopupRect(x: x, y: y, width: width, height: height)

proc placeBesidePopup*(
    other: PopupRect, width, height: int, screen: Screen, yOffset: int = 0
): PopupRect =
  ## Popup placed to the right of `other`; falls back to the left side, then
  ## to the right screen edge if neither side fits. Y starts at
  ## `other.y + yOffset` (never above `other.y`) and is clamped upward if it
  ## would cross `screen.bottomReserve`.
  let rightX = other.x + other.width
  let x =
    if rightX + width <= screen.width:
      rightX
    else:
      let leftX = other.x - width
      if leftX >= 0:
        leftX
      else:
        max(0, screen.width - width)

  var y = max(other.y, other.y + yOffset)
  if y + height > screen.height - screen.bottomReserve:
    y = max(0, screen.height - screen.bottomReserve - height)
  PopupRect(x: x, y: y, width: width, height: height)

proc placeCorner*(
    corner: PopupCorner, width, height: int, screen: Screen, stackOffset: int = 0
): PopupRect =
  ## Popup pinned to one of the four screen corners. `stackOffset` shifts the
  ## popup along the vertical axis to make room for earlier popups in a stack
  ## (grows downward from top corners, upward from bottom corners).
  ## For bottom corners the top row sits at
  ## `screen.height - screen.bottomReserve - height - stackOffset`; callers
  ## that want a padding gap between the popup and the reserved area should
  ## include that row in `bottomReserve`.
  var x, y: int
  case corner
  of pcTopLeft:
    x = 0
    y = stackOffset
  of pcTopRight:
    x = screen.width - width
    y = stackOffset
  of pcBottomLeft:
    x = 0
    y = screen.height - screen.bottomReserve - height - stackOffset
  of pcBottomRight:
    x = screen.width - width
    y = screen.height - screen.bottomReserve - height - stackOffset
  x = max(0, x)
  y = max(0, y)
  PopupRect(x: x, y: y, width: width, height: height)

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
