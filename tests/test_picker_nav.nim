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

import std/unittest
import ../src/moepkg/picker/nav

suite "picker/nav - pickerMoveUp":
  test "decrements when selectedIndex > 0":
    var idx = 3
    pickerMoveUp(idx)
    check idx == 2

  test "no-op at index 0":
    var idx = 0
    pickerMoveUp(idx)
    check idx == 0

  test "no-op at negative index (defensive)":
    var idx = -1
    pickerMoveUp(idx)
    check idx == -1

suite "picker/nav - pickerMoveDown":
  test "increments when below last":
    var idx = 0
    pickerMoveDown(idx, 5)
    check idx == 1

  test "no-op at last index":
    var idx = 4
    pickerMoveDown(idx, 5)
    check idx == 4

  test "no-op when itemCount is 0":
    var idx = 0
    pickerMoveDown(idx, 0)
    check idx == 0

  test "no-op when itemCount is 1 and at last":
    var idx = 0
    pickerMoveDown(idx, 1)
    check idx == 0

suite "picker/nav - pickerMoveToFirst":
  test "sets to 0 from non-zero":
    var idx = 7
    pickerMoveToFirst(idx)
    check idx == 0

  test "stays at 0":
    var idx = 0
    pickerMoveToFirst(idx)
    check idx == 0

suite "picker/nav - pickerMoveToLast":
  test "sets to itemCount - 1":
    var idx = 0
    pickerMoveToLast(idx, 5)
    check idx == 4

  test "sets to 0 when itemCount is 0":
    var idx = 3
    pickerMoveToLast(idx, 0)
    check idx == 0

  test "sets to 0 when itemCount is 1":
    var idx = 0
    pickerMoveToLast(idx, 1)
    check idx == 0

suite "picker/nav - pickerHalfPageUp":
  test "moves up by half of viewportHeight":
    var idx = 10
    pickerHalfPageUp(idx, 6)
    check idx == 7

  test "clamps to 0 when result would be negative":
    var idx = 2
    pickerHalfPageUp(idx, 10)
    check idx == 0

  test "zero viewportHeight no-op":
    var idx = 5
    pickerHalfPageUp(idx, 0)
    check idx == 5

suite "picker/nav - pickerHalfPageDown":
  test "moves down by half of viewportHeight":
    var idx = 0
    pickerHalfPageDown(idx, 20, 6)
    check idx == 3

  test "clamps to itemCount - 1":
    var idx = 18
    pickerHalfPageDown(idx, 20, 10)
    check idx == 19

  test "no-op when itemCount is 0":
    var idx = 0
    pickerHalfPageDown(idx, 0, 10)
    check idx == 0

suite "picker/nav - pickerEnsureVisible":
  test "scrolls up when selectedIndex < topLine":
    var topLine = 5
    pickerEnsureVisible(2, topLine, 10)
    check topLine == 2

  test "scrolls down when selectedIndex past viewport":
    var topLine = 0
    pickerEnsureVisible(12, topLine, 10)
    check topLine == 3 # 12 - 10 + 1

  test "no-op when in viewport":
    var topLine = 5
    pickerEnsureVisible(8, topLine, 10)
    check topLine == 5

  test "no-op when selectedIndex equals topLine":
    var topLine = 5
    pickerEnsureVisible(5, topLine, 10)
    check topLine == 5

  test "selectedIndex at last visible row stays put":
    var topLine = 0
    pickerEnsureVisible(9, topLine, 10) # rows 0..9 visible
    check topLine == 0

  test "zero viewportHeight does not infinite-loop":
    var topLine = 0
    pickerEnsureVisible(5, topLine, 0)
    check topLine == 0

  test "clamps topLine to 0 if it would be negative":
    var topLine = -1
    pickerEnsureVisible(0, topLine, 10)
    check topLine == 0
