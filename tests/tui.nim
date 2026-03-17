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

import std/[unittest, options, sequtils, posix]

import pkg/[results, ncurses, chronos]

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

suite "parseMouseEvent":
  test "Valid mouse button 1 press event":
    let input = "\e[<0;10;20M"
    check parseMouseEvent(input) == true
    let event = getLastMouseEvent()
    check event.isSome
    check event.get.x == 9 # 0-based
    check event.get.y == 19 # 0-based
    check event.get.bstate == mmask_t(MouseButton1Pressed)

  test "Valid mouse button 1 release event":
    let input = "\e[<0;10;20m"
    check parseMouseEvent(input) == true
    let event = getLastMouseEvent()
    check event.isSome
    check event.get.x == 9
    check event.get.y == 19
    check event.get.bstate == mmask_t(MouseButton1Released)

  test "Valid mouse button 2 press event":
    let input = "\e[<1;5;15M"
    check parseMouseEvent(input) == true
    let event = getLastMouseEvent()
    check event.isSome
    check event.get.x == 4
    check event.get.y == 14
    check event.get.bstate == mmask_t(MouseButton2Pressed)

  test "Valid mouse button 2 release event":
    let input = "\e[<1;5;15m"
    check parseMouseEvent(input) == true
    let event = getLastMouseEvent()
    check event.isSome
    check event.get.x == 4
    check event.get.y == 14
    check event.get.bstate == mmask_t(MouseButton2Released)

  test "Valid mouse button 3 press event":
    let input = "\e[<2;30;40M"
    check parseMouseEvent(input) == true
    let event = getLastMouseEvent()
    check event.isSome
    check event.get.x == 29
    check event.get.y == 39
    check event.get.bstate == mmask_t(MouseButton3Pressed)

  test "Valid mouse button 3 release event":
    let input = "\e[<2;30;40m"
    check parseMouseEvent(input) == true
    let event = getLastMouseEvent()
    check event.isSome
    check event.get.x == 29
    check event.get.y == 39
    check event.get.bstate == mmask_t(MouseButton3Released)

  test "Valid mouse event at origin (1,1)":
    let input = "\e[<0;1;1M"
    check parseMouseEvent(input) == true
    let event = getLastMouseEvent()
    check event.isSome
    check event.get.x == 0
    check event.get.y == 0

  test "Invalid format: missing start sequence":
    let input = "[<0;10;20M"
    check parseMouseEvent(input) == false

  test "Invalid format: wrong start sequence":
    let input = "\e[0;10;20M"
    check parseMouseEvent(input) == false

  test "Invalid format: missing end character":
    let input = "\e[<0;10;20"
    check parseMouseEvent(input) == false

  test "Invalid format: wrong end character":
    let input = "\e[<0;10;20X"
    check parseMouseEvent(input) == false

  test "Invalid format: too few parts":
    let input = "\e[<0;10M"
    check parseMouseEvent(input) == false

  test "Invalid format: too many parts":
    let input = "\e[<0;10;20;30M"
    check parseMouseEvent(input) == false

  test "Invalid format: non-numeric button":
    let input = "\e[<x;10;20M"
    check parseMouseEvent(input) == false

  test "Invalid format: non-numeric x coordinate":
    let input = "\e[<0;x;20M"
    check parseMouseEvent(input) == false

  test "Invalid format: non-numeric y coordinate":
    let input = "\e[<0;10;yM"
    check parseMouseEvent(input) == false

  test "Invalid format: empty string":
    let input = ""
    check parseMouseEvent(input) == false

  test "Button with modifier (drag): button 4 (mod 4 = 0)":
    let input = "\e[<4;10;20M"
    check parseMouseEvent(input) == true
    let event = getLastMouseEvent()
    check event.isSome
    check event.get.bstate == mmask_t(MouseButton1Pressed)

  test "Button with modifier (drag): button 5 (mod 4 = 1)":
    let input = "\e[<5;10;20M"
    check parseMouseEvent(input) == true
    let event = getLastMouseEvent()
    check event.isSome
    check event.get.bstate == mmask_t(MouseButton2Pressed)

  test "Scroll up (button code 64)":
    let input = "\e[<64;10;20M"
    check parseMouseEvent(input) == true
    let event = getLastMouseEvent()
    check event.isSome
    check event.get.bstate == mmask_t(MouseButton4Pressed)
    check event.get.x == 9
    check event.get.y == 19

  test "Scroll down (button code 65)":
    let input = "\e[<65;10;20M"
    check parseMouseEvent(input) == true
    let event = getLastMouseEvent()
    check event.isSome
    check event.get.bstate == mmask_t(MouseButton5Pressed)
    check event.get.x == 9
    check event.get.y == 19

suite "pollAsync":
  test "Timeout when no data available":
    proc runTest(): Future[int] {.async.} =
      var pipeFds: array[2, cint]
      doAssert pipe(pipeFds) == 0

      let readFd = pipeFds[0]
      let writeFd = pipeFds[1]

      let res = await pollAsync(readFd, timeout = 50)

      discard close(readFd)
      discard close(writeFd)
      return res

    check waitFor(runTest()) == 0

  test "Ready when data available":
    proc runTest(): Future[int] {.async.} =
      var pipeFds: array[2, cint]
      doAssert pipe(pipeFds) == 0

      let readFd = pipeFds[0]
      let writeFd = pipeFds[1]

      let data = 'x'
      discard write(writeFd, data.unsafeAddr, 1)

      let res = await pollAsync(readFd, timeout = 1000)

      discard close(readFd)
      discard close(writeFd)
      return res

    check waitFor(runTest()) > 0
