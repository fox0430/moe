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

import std/[unittest, options, strutils, sequtils]
import pkg/results
import moepkg/unicodeext

import moepkg/ui {.all.}

suite "parseColorMode":
  test "none":
    check ColorMode.none == "none".parseColorMode.get

  test "c8":
    check ColorMode.c8 == "8".parseColorMode.get

  test "c16":
    check ColorMode.c16 == "16".parseColorMode.get

  test "c256":
    check ColorMode.c256 == "256".parseColorMode.get

  test "c24bit":
    check ColorMode.c24bit == "24bit".parseColorMode.get

suite "parseKey":
  test "ASCII characters":
    block:
      const Buffer = '0'
      check Buffer.toRune == parseKey(@[Buffer.int]).get

    block:
      const Buffer = 'a'
      check Buffer.toRune == parseKey(@[Buffer.int]).get

    block:
      const Buffer = '='
      check Buffer.toRune == parseKey(@[Buffer.int]).get

  test "Special keys":
    block upKey:
      let upKeyBuffer = @[27, 79, 65]
      check parseKey(upKeyBuffer).get.isUpKey

    block downKey:
      let downKeyBuffer = @[27, 79, 66]
      check parseKey(downKeyBuffer).get.isDownKey

    block rightKey:
      let rightKeyBuffer = @[27, 79, 67]
      check parseKey(rightKeyBuffer).get.isRightKey

    block leftKey:
      let leftKeyBuffer = @[27, 79, 68]
      check parseKey(leftKeyBuffer).get.isLeftKey

    block endKey:
      let endKeyBuffer = @[27, 79, 70]
      check parseKey(endKeyBuffer).get.isEndKey

    block homeKey:
      let homeKeyBuffer = @[27, 79, 72]
      check parseKey(homeKeyBuffer).get.isHomeKey

    block insertKey:
      let insertKeyBuffer = @[27, 91, 50, 126]
      check parseKey(insertKeyBuffer).get.isInsertKey

    block deleteKey:
      let deleteKeyBuffer = @[27, 91, 51, 126]
      check parseKey(deleteKeyBuffer).get.isDeleteKey

    block pageUpKey:
      let pageUpKeyBuffer = @[27, 91, 53, 126]
      check parseKey(pageUpKeyBuffer).get.isPageUpKey

    block pageDownKey:
      let pageDownKeyBuffer = @[27, 91, 54, 126]
      check parseKey(pageDownKeyBuffer).get.isPageDownKey

  test "Non ASCII characters":
    block jp:
      const Buffer = "あ"
      check Buffer.toRunes[0] == parseKey(Buffer.mapIt(it.int)).get

    block Emoji:
      const Buffer = "🚀"
      check Buffer.toRunes[0] == parseKey(Buffer.mapIt(it.int)).get
