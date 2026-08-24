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

## Tests for frontend_input.nim

import std/unittest

import ../src/moepkg/frontend_input {.all.}

suite "GridRegion":
  test "initGridRegion keeps non-negative dimensions":
    let region = initGridRegion(1, 2, 3, 4)
    check region.row == 1
    check region.column == 2
    check region.rows == 3
    check region.columns == 4

  test "initGridRegion clamps negative dimensions to 0":
    let region = initGridRegion(-1, -2, -3, -4)
    check region.row == -1
    check region.column == -2
    check region.rows == 0
    check region.columns == 0

suite "PointerInput":
  test "initPointerInput applies defaults":
    let input = initPointerInput(3, 4)
    check input.row == 3
    check input.column == 4
    check input.button == pbPrimary
    check input.action == paPress
    check input.clickCount == 1
    check input.modifiers == {}

  test "initPointerInput with custom values":
    let input = initPointerInput(
      5,
      6,
      button = pbSecondary,
      action = paDrag,
      clickCount = 2,
      modifiers = {kmCtrl, kmShift},
    )
    check input.row == 5
    check input.column == 6
    check input.button == pbSecondary
    check input.action == paDrag
    check input.clickCount == 2
    check input.modifiers == {kmCtrl, kmShift}

suite "ScrollInput":
  test "initScrollInput with positive delta":
    let input = initScrollInput(7, 8, 3)
    check input.row == 7
    check input.column == 8
    check input.deltaPhysicalRows == 3
    check input.modifiers == {}

  test "initScrollInput with negative delta and modifiers":
    let input = initScrollInput(9, 10, -2, modifiers = {kmAlt})
    check input.row == 9
    check input.column == 10
    check input.deltaPhysicalRows == -2
    check input.modifiers == {kmAlt}

suite "ScrollOutcome":
  test "all fields are accessible":
    let outcome = ScrollOutcome(
      handled: true,
      region: initGridRegion(0, 0, 10, 20),
      requestedRows: 3,
      appliedRows: 2,
      viewportPhysicalRowsMoved: 1,
    )
    check outcome.handled
    check outcome.region.rows == 10
    check outcome.requestedRows == 3
    check outcome.appliedRows == 2
    check outcome.viewportPhysicalRowsMoved == 1
