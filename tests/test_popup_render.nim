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

## Tests for popup drawing primitives (drawBorder / drawClippedRunes / fillCells).

import std/unittest

import pkg/celina

import ../src/moepkg/popup_render

suite "popup_render - drawClippedRunes":
  test "ASCII within limit writes every rune and returns end column":
    var buf = newBuffer(20, 3)
    let nextX = drawClippedRunes(buf, 0, 0, 10, "hello", defaultStyle())
    check nextX == 5
    check buf[0, 0].symbol == "h"
    check buf[4, 0].symbol == "o"
    check buf[5, 0].symbol == " "

  test "ASCII stops right before limitX":
    var buf = newBuffer(20, 3)
    let nextX = drawClippedRunes(buf, 0, 0, 3, "abcdef", defaultStyle())
    check nextX == 3
    check buf[0, 0].symbol == "a"
    check buf[1, 0].symbol == "b"
    check buf[2, 0].symbol == "c"
    check buf[3, 0].symbol == " "

  test "Wide rune with room writes base and shadow continuation":
    var buf = newBuffer(20, 3)
    let nextX = drawClippedRunes(buf, 0, 0, 10, "あ", defaultStyle())
    check nextX == 2
    check buf[0, 0].symbol == "あ"
    # Continuation cell of a wide char is empty (shadow).
    check buf[1, 0].isShadow

  test "Wide rune at limitX - 1 is dropped, does not overflow shadow":
    # Regression: the previous clip check ignored runeWidth, so a wide rune
    # landing at result == limitX - 1 would write a shadow cell into column
    # limitX (the popup's right border), corrupting the frame.
    var buf = newBuffer(20, 3)
    # Pre-fill column 10 with the border glyph so we can detect corruption.
    buf[10, 0] = cell("│", defaultStyle())
    let nextX = drawClippedRunes(buf, 9, 0, 10, "あ", defaultStyle())
    check nextX == 9 # rune skipped; caller may pad with spaces
    check buf[9, 0].symbol == " " # unchanged blank cell
    check buf[10, 0].symbol == "│" # border still intact

  test "Wide rune fits exactly at limitX":
    # result + w == limitX should still be allowed (writes into columns
    # limitX - 2 and limitX - 1, both < limitX).
    var buf = newBuffer(20, 3)
    buf[10, 0] = cell("│", defaultStyle())
    let nextX = drawClippedRunes(buf, 8, 0, 10, "あ", defaultStyle())
    check nextX == 10
    check buf[8, 0].symbol == "あ"
    check buf[9, 0].isShadow
    check buf[10, 0].symbol == "│"

  test "Mixed ASCII + CJK stops before overrunning limitX":
    var buf = newBuffer(20, 3)
    buf[6, 0] = cell("│", defaultStyle())
    # "aあb" widths: 1 + 2 + 1 = 4 columns.  With startX=3, limitX=6, only
    # "aあ" fits (3+1+2 = 6 == limitX).  The trailing "b" would fit too
    # (6+1 > 6), so it must be dropped.
    let nextX = drawClippedRunes(buf, 3, 0, 6, "aあb", defaultStyle())
    check nextX == 6
    check buf[3, 0].symbol == "a"
    check buf[4, 0].symbol == "あ"
    check buf[5, 0].isShadow
    check buf[6, 0].symbol == "│"

  test "limitX beyond buffer width falls back to buffer width":
    var buf = newBuffer(5, 3)
    let nextX = drawClippedRunes(buf, 0, 0, 100, "abcdefgh", defaultStyle())
    check nextX == 5
    check buf[0, 0].symbol == "a"
    check buf[4, 0].symbol == "e"

  test "Wide rune at buffer's right edge is dropped":
    var buf = newBuffer(5, 3)
    let nextX = drawClippedRunes(buf, 4, 0, 100, "あ", defaultStyle())
    check nextX == 4 # width 2 would spill past buffer width 5.
    check buf[4, 0].symbol == " "

  test "Negative startX skips runes then resumes writing on-screen":
    var buf = newBuffer(20, 3)
    # startX=-2, "abcd": 'a' at -2 and 'b' at -1 are skipped (result stays
    # < 0 while advancing by width); 'c' writes at 0, 'd' at 1.
    let nextX = drawClippedRunes(buf, -2, 0, 10, "abcd", defaultStyle())
    check nextX == 2
    check buf[0, 0].symbol == "c"
    check buf[1, 0].symbol == "d"

  test "Empty text returns startX unchanged":
    var buf = newBuffer(10, 3)
    check drawClippedRunes(buf, 3, 0, 8, "", defaultStyle()) == 3

  test "limitX at startX writes nothing":
    var buf = newBuffer(10, 3)
    buf[3, 0] = cell("│", defaultStyle())
    let nextX = drawClippedRunes(buf, 3, 0, 3, "abc", defaultStyle())
    check nextX == 3
    check buf[3, 0].symbol == "│"

suite "popup_render - drawBorder":
  test "Draws corners and edges":
    var buf = newBuffer(20, 5)
    drawBorder(buf, 2, 1, 6, 3, defaultStyle())
    check buf[2, 1].symbol == "┌"
    check buf[7, 1].symbol == "┐"
    check buf[2, 3].symbol == "└"
    check buf[7, 3].symbol == "┘"
    check buf[3, 1].symbol == "─"
    check buf[2, 2].symbol == "│"
    check buf[7, 2].symbol == "│"

  test "Skips when width or height under 2":
    var buf = newBuffer(20, 5)
    drawBorder(buf, 0, 0, 1, 3, defaultStyle())
    drawBorder(buf, 0, 0, 3, 1, defaultStyle())
    check buf[0, 0].symbol == " "

suite "popup_render - fillCells":
  test "Fills range with spaces up to limitX":
    var buf = newBuffer(10, 3)
    buf[5, 0] = cell("X", defaultStyle())
    let nextX = fillCells(buf, 2, 0, 6, defaultStyle())
    check nextX == 6
    check buf[2, 0].symbol == " "
    check buf[5, 0].symbol == " "

  test "Clips at buffer width":
    var buf = newBuffer(4, 2)
    let nextX = fillCells(buf, 0, 0, 100, defaultStyle())
    check nextX == 4

suite "popup_render - placeBelowCursor":
  test "Fits below cursor":
    let s = initScreen(80, 24, bottomReserve = 2)
    let r = placeBelowCursor(5, 3, width = 10, height = 4, screen = s)
    check r == PopupRect(x: 5, y: 4, width: 10, height: 4)

  test "Falls back above when below would cross bottomReserve":
    # cursor near bottom: y=20, height=4, screen 24, reserve 2 -> below top=21,
    # bottom=24 > 22, so fall back to above (y=20-4=16).
    let s = initScreen(80, 24, bottomReserve = 2)
    let r = placeBelowCursor(0, 20, width = 5, height = 4, screen = s)
    check r.y == 16

  test "Fallback above is clamped to 0 for oversized popup":
    let s = initScreen(80, 10, bottomReserve = 2)
    let r = placeBelowCursor(0, 8, width = 5, height = 20, screen = s)
    check r.y == 0

  test "X shifts left when popup overflows right edge":
    let s = initScreen(20, 24)
    let r = placeBelowCursor(15, 0, width = 10, height = 3, screen = s)
    check r.x == 10 # 20 - 10

  test "X clamped to 0 when popup wider than screen":
    let s = initScreen(5, 24)
    let r = placeBelowCursor(3, 0, width = 10, height = 3, screen = s)
    check r.x == 0

suite "popup_render - placeAboveCursor":
  test "Fits above cursor":
    let s = initScreen(80, 24, bottomReserve = 2)
    let r = placeAboveCursor(5, 10, width = 10, height = 4, screen = s)
    check r == PopupRect(x: 5, y: 6, width: 10, height: 4) # 10 - 4

  test "Falls back below when above would start above top":
    # cursorY = 2, height = 5 -> above y = -3 -> fall back to y = 3
    let s = initScreen(80, 24, bottomReserve = 2)
    let r = placeAboveCursor(0, 2, width = 10, height = 5, screen = s)
    check r.y == 3

  test "Fallback below clamped upward if crosses bottomReserve":
    # cursorY = 2 near top, height = 6, screen height 10, reserve 2
    # -> above y = -4 -> below y = 3 -> 3 + 6 = 9 > 10 - 2 = 8
    # -> clamp to max(0, 10 - 2 - 6) = 2
    let s = initScreen(80, 10, bottomReserve = 2)
    let r = placeAboveCursor(0, 2, width = 5, height = 6, screen = s)
    check r.y == 2

  test "Fallback y clamped to 0 for oversized popup":
    let s = initScreen(80, 10, bottomReserve = 2)
    let r = placeAboveCursor(0, 1, width = 5, height = 20, screen = s)
    check r.y == 0

  test "X shifts left when popup overflows right edge":
    let s = initScreen(20, 24, bottomReserve = 2)
    let r = placeAboveCursor(15, 10, width = 10, height = 3, screen = s)
    check r.x == 10

suite "popup_render - placeAboveReserve":
  test "Popup sits above reserved bottom area":
    let s = initScreen(80, 24, bottomReserve = 3)
    let r = placeAboveReserve(4, width = 10, height = 5, screen = s)
    check r == PopupRect(x: 4, y: 16, width: 10, height: 5) # 24 - 3 - 5

  test "Y clamped to 0 when popup taller than remaining space":
    let s = initScreen(80, 6, bottomReserve = 2)
    let r = placeAboveReserve(0, width = 10, height = 20, screen = s)
    check r.y == 0

  test "X shifted left on right overflow":
    let s = initScreen(20, 24, bottomReserve = 1)
    let r = placeAboveReserve(15, width = 10, height = 4, screen = s)
    check r.x == 10

suite "popup_render - placeBesidePopup":
  test "Prefers right of anchor when it fits":
    let anchor = PopupRect(x: 5, y: 4, width: 10, height: 6)
    let s = initScreen(80, 24, bottomReserve = 2)
    let r = placeBesidePopup(anchor, width = 20, height = 6, screen = s)
    check r.x == 15 # 5 + 10

  test "Falls back to left when right does not fit":
    let anchor = PopupRect(x: 30, y: 4, width: 10, height: 6)
    let s = initScreen(50, 24, bottomReserve = 2)
    let r = placeBesidePopup(anchor, width = 20, height = 6, screen = s)
    check r.x == 10 # 30 - 20

  test "Falls back to clipped right when neither side fits":
    let anchor = PopupRect(x: 5, y: 4, width: 10, height: 6)
    let s = initScreen(20, 24, bottomReserve = 2)
    let r = placeBesidePopup(anchor, width = 30, height = 6, screen = s)
    check r.x == 0 # max(0, 20 - 30)

  test "Y follows selected row offset":
    let anchor = PopupRect(x: 0, y: 4, width: 10, height: 8)
    let s = initScreen(80, 24, bottomReserve = 2)
    let r = placeBesidePopup(anchor, width = 10, height = 6, screen = s, yOffset = 3)
    check r.y == 7

  test "Y never above anchor.y":
    let anchor = PopupRect(x: 0, y: 4, width: 10, height: 8)
    let s = initScreen(80, 24, bottomReserve = 2)
    let r = placeBesidePopup(anchor, width = 10, height = 6, screen = s, yOffset = -5)
    check r.y == 4

  test "Y clamped upward when panel would cross bottomReserve":
    let anchor = PopupRect(x: 0, y: 18, width: 10, height: 4)
    let s = initScreen(80, 24, bottomReserve = 2)
    let r = placeBesidePopup(anchor, width = 10, height = 6, screen = s)
    check r.y == 16 # 24 - 2 - 6

suite "popup_render - placeCorner":
  test "Top-right anchors to right edge":
    let s = initScreen(80, 24)
    let r = placeCorner(pcTopRight, width = 20, height = 3, screen = s)
    check r == PopupRect(x: 60, y: 0, width: 20, height: 3)

  test "Top-left with stack offset":
    let s = initScreen(80, 24)
    let r = placeCorner(pcTopLeft, width = 20, height = 3, screen = s, stackOffset = 4)
    check r == PopupRect(x: 0, y: 4, width: 20, height: 3)

  test "Bottom-right respects bottomReserve":
    let s = initScreen(80, 24, bottomReserve = 2)
    let r = placeCorner(pcBottomRight, width = 20, height = 3, screen = s)
    check r == PopupRect(x: 60, y: 19, width: 20, height: 3) # 24 - 2 - 3

  test "Bottom-left with stack offset grows upward":
    let s = initScreen(80, 24, bottomReserve = 2)
    let r =
      placeCorner(pcBottomLeft, width = 20, height = 3, screen = s, stackOffset = 4)
    check r == PopupRect(x: 0, y: 15, width: 20, height: 3) # 24 - 2 - 3 - 4

  test "Corner clamped to 0 when popup does not fit":
    let s = initScreen(10, 5, bottomReserve = 2)
    let r = placeCorner(pcBottomRight, width = 20, height = 10, screen = s)
    check r.x == 0
    check r.y == 0
