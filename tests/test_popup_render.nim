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
