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

import std/[unittest, importutils, options, sequtils]
import moepkg/[independentutils, unicodeext]

import moepkg/popupwindow {.all.}

suite "popupwindow: initWindow":
  privateAccess(PopupWindow)

  test "initWindow 1":
    let p = initPopupWindow(
      Position(y: 50, x: 100),
      Size(h: 10, w: 20),
      @[ru"test"])

    check p.window != nil
    check p.position.y == 50
    check p.position.x == 100
    check p.size.h == 10
    check p.size.w == 20
    check p.buffer == @[ru"test"]
    check p.currentLine.isNone

  test "initWindow 2":
    let p = initPopupWindow(
      Position(y: 50, x: 100),
      Size(h: 10, w: 20))

    check p.window != nil
    check p.position.y == 50
    check p.position.x == 100
    check p.size.h == 10
    check p.size.w == 20
    check p.buffer.len == 0
    check p.currentLine.isNone

  test "initWindow 3":
    let p = initPopupWindow()

    check p.window != nil
    check p.position.y == 0
    check p.position.x == 0
    check p.size.h == 1
    check p.size.w == 1
    check p.buffer.len == 0
    check p.currentLine.isNone

suite "popupwindow: resize":
  test "resize 1":
    var p = initPopupWindow()
    p.resize(50, 100)
    check p.size == Size(h: 50, w: 100)

  test "resize 2":
    var p = initPopupWindow()
    p.resize(Size(h: 50, w: 100))
    check p.size == Size(h: 50, w: 100)

suite "popupwindow: move":
  test "move 1":
    var p = initPopupWindow()
    p.move(50, 100)
    check p.position == Position(y: 50, x: 100)

  test "move 2":
    var p = initPopupWindow()
    p.move(Position(y: 50, x: 100))
    check p.position == Position(y: 50, x: 100)

suite "popupwindow: autoMoveAndResize":
  test "autoMoveAndResize 1":
    var p = initPopupWindow(
      Position(y: 1, x: 1),
      Size(h: 10, w: 10),
      @[ru"line1", ru"line2"])

    let
      min = Position(y: 1, x: 1)
      max = Position(y: 100, x: 100)
    p.autoMoveAndResize(min, max)

    check p.position == Position(y: 1, x: 1)
    check p.size == Size(h: 2, w: 5)

  test "autoMoveAndResize 2":
    var p = initPopupWindow(
      Position(y: 1, x: 1),
      Size(h: 1, w: 1),
      @[ru"line1", ru"line2"])

    let
      min = Position(y: 1, x: 1)
      max = Position(y: 100, x: 100)
    p.autoMoveAndResize(min, max)

    check p.position == Position(y: 1, x: 1)
    check p.size == Size(h: 2, w: 5)

  test "autoMoveAndResize 3":
    var p = initPopupWindow(
      Position(y: 99, x: 1),
      Size(h: 2, w: 5),
      @[ru"line1", ru"line2"])

    let
      min = Position(y: 1, x: 1)
      max = Position(y: 100, x: 100)
    p.autoMoveAndResize(min, max)

    check p.position == Position(y: 96, x: 1)
    check p.size == Size(h: 2, w: 5)

  test "autoMoveAndResize 4":
    var p = initPopupWindow(
      Position(y: 1, x: 99),
      Size(h: 2, w: 5),
      @[ru"line1", ru"line2"])

    let
      min = Position(y: 1, x: 1)
      max = Position(y: 100, x: 100)
    p.autoMoveAndResize(min, max)

    check p.position == Position(y: 1, x: 93)
    check p.size == Size(h: 2, w: 5)

  test "autoMoveAndResize 5":
    var p = initPopupWindow(
      Position(y: 99, x: 99),
      Size(h: 2, w: 5),
      @[ru"line1", ru"line2"])

    let
      min = Position(y: 1, x: 1)
      max = Position(y: 100, x: 100)
    p.autoMoveAndResize(min, max)

    check p.position == Position(y: 96, x: 93)
    check p.size == Size(h: 2, w: 5)

suite "popupwindow: update":
  privateAccess(HighlightText)

  test "update 1":
    var p = initPopupWindow(
      Position(y: 1, x: 1),
      Size(h: 2, w: 5),
      @[ru"line1", ru"line2"])

    p.update

  test "update 2":
    var p = initPopupWindow(
      Position(y: 1, x: 1),
      Size(h: 1, w: 5),
      @[ru"line1", ru"line2"])

    p.update

  test "update 3":
    var p = initPopupWindow(
      Position(y: 1, x: 1),
      Size(h: 2, w: 1),
      @[ru"line1", ru"line2"])

    p.update

  test "update 4":
    var p = initPopupWindow(
      Position(y: 1, x: 1),
      Size(h: 5, w: 2),
      toSeq(0..10).mapIt(toRunes($it)))

    p.currentLine = some(5)

    p.update

  test "update 5":
    var p = initPopupWindow(
      Position(y: 1, x: 1),
      Size(h: 5, w: 1),
      toSeq(0..10).mapIt(toRunes($it)))

    p.currentLine = some(5)

    p.update

  test "update 6":
    var p = initPopupWindow(
      Position(y: 1, x: 1),
      Size(h: 5, w: 1),
      toSeq(0..10).mapIt(toRunes($it)))

    p.highlightText = some(HighlightText(text: ru"a"))

    p.update
