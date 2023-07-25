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

import std/[unittest, strutils, importutils]
import moepkg/[unicodeext, gapbuffer, editorstatus, bufferstatus, ui]
import pkg/ncurses

import moepkg/helputils {.all.}
import moepkg/help {.all.}
import moepkg/commandline {.all.}

let CONTROL_J = 10
let CONTROL_K = 11

proc initHelpMode(): EditorStatus =
  result = initEditorStatus()

  let path = ""
  result.addNewBufferInCurrentWin(path, Mode.help)
  result.resize

suite "initHelpModeBuffer":
  test "initHelpModeBuffer":
    let
      buffer = initHelpModeBuffer().toGapBuffer
      help = Helpsentences.splitLines

    for i in 0 ..< buffer.len:
      check $buffer[i] == help[i]

suite "isHelpCommand":
  test "valid commands":
    let commands = @[
      @[CONTROL_J.Rune],
      @[CONTROL_K.Rune],
      ":".toRunes,
      "k".toRunes, @[KEY_UP.Rune],
      "j".toRunes, @[KEY_DOWN.Rune],
      "h".toRunes, @[KEY_LEFT.Rune], @[KEY_BACKSPACE.Rune],
      "l".toRunes, @[KEY_RIGHT.Rune],
      "0".toRunes, @[KEY_HOME.Rune],
      "$".toRunes, @[KEY_END.Rune],
      "G".toRunes,
      "gg".toRunes
    ]

    for c in commands:
      check isHelpCommand(c) == InputState.Valid

  test "continue commands":
    let commands = @["g".toRunes]

    for c in commands:
      check isHelpCommand(c) == InputState.Continue

  test "invalid commands":
    let commands = @[@[999.Rune]]

    for c in commands:
      check isHelpCommand(c) == InputState.Invalid

suite "execHelpCommand":
  test "':' key":
    # Change mode to ex

    var status = initHelpMode()

    let key = ":".toRunes
    status.execHelpCommand(key)

    check currentBufStatus.isExmode
    check status.commandLine.buffer.len == 0

    privateAccess(status.commandLine.type)
    check status.commandLine.prompt == ExModePrompt.toRunes

  test "'j' key":
    # Move to the below line

    var status = initHelpMode()

    let key = "j".toRunes
    status.execHelpCommand(key)

    check currentMainWindowNode.currentLine == 1

  test "'k' key":
    # Move to the above line

    var status = initHelpMode()

    currentMainWindowNode.currentLine = 1

    let key = "k".toRunes
    status.execHelpCommand(key)

    check currentMainWindowNode.currentLine == 0

  test "'l' key":
    # Move to the right

    var status = initHelpMode()

    let key = "l".toRunes
    status.execHelpCommand(key)

    check currentMainWindowNode.currentColumn == 1

  test "'h' key":
    # Move to the left

    var status = initHelpMode()

    currentMainWindowNode.currentColumn = 1

    let key = "h".toRunes
    status.execHelpCommand(key)

    check currentMainWindowNode.currentColumn == 0

  test "'0' key":
    # Move to top of the line

    var status = initHelpMode()

    currentMainWindowNode.currentColumn = 1

    let key = "0".toRunes
    status.execHelpCommand(key)

    check currentMainWindowNode.currentColumn == 0

  test "'$' key":
    # Move to last of the line

    var status = initHelpMode()

    currentMainWindowNode.currentColumn = 1

    let key = "$".toRunes
    status.execHelpCommand(key)

    check currentMainWindowNode.currentColumn == currentBufStatus.buffer[0].high

  test "'G' key":
    # Move to the last line of the buffer

    var status = initHelpMode()

    let key = "G".toRunes
    status.execHelpCommand(key)

    check currentMainWindowNode.currentLine == currentBufStatus.buffer.high

  test "gg key":
    # Move to the first line of the buffer

    var status = initHelpMode()

    currentMainWindowNode.currentLine = currentBufStatus.buffer.high

    let key = "gg".toRunes
    status.execHelpCommand(key)

    check currentMainWindowNode.currentLine == 0

