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

import std/[unittest, strformat]

import pkg/results

import moepkg/[unicodeext, jumplist, editorstatus, bufferstatus, commandline]

import moepkg/jumplistviewer {.all.}

suite "jumplistviewer: calcPositionStrMaxLen":
  setup:
    var l = initJumpList()

  test "Basic":
    l.add(0, ru"", 0, 0)
    check l.history.calcPositionStrMaxLen == (1, 1)

  test "Basic 2":
    l.add(0, ru"", 10, 0)
    check l.history.calcPositionStrMaxLen == (2, 1)

  test "Basic 3":
    l.add(0, ru"", 0, 10)
    check l.history.calcPositionStrMaxLen == (1, 2)

suite "jumplistviewer: initJumpListBuffer":
  setup:
    var l = initJumpList()

  test "Basic":
    for i in 0 .. 1:
      let
        bufferId = i
        line = i
        column = i
        path = fmt"text{i}.txt"
      l.add(bufferId, path.toRunes, line, column)

    check l.initJumpListBuffer ==
      @[" line column path", " 0    0      text0.txt", ">1    1      text1.txt"].toSeqRunes

  test "Basic 2":
    const Path = "text.txt"
    l.add(0, Path.toRunes, 0, 0)
    l.add(0, Path.toRunes, 100000, 0)
    l.add(0, Path.toRunes, 0, 100000)

    check l.initJumpListBuffer ==
      @[
        " line   column path", " 0      0      text.txt", " 100000 0      text.txt",
        ">0      100000 text.txt",
      ].toSeqRunes

  test "Basic 3":
    const Path = "text.txt"
    l.add(0, Path.toRunes, 0, 0)
    l.add(0, Path.toRunes, 1, 0)
    l.add(0, Path.toRunes, 2, 0)
    discard l.jumpBack

    check l.initJumpListBuffer ==
      @[
        " line column path", " 0    0      text.txt", ">1    0      text.txt",
        " 2    0      text.txt",
      ].toSeqRunes

suite "jumplistviewer: execJumpListCommand":
  setup:
    var status = initEditorStatus().get
    assert status.addNewBufferInCurrentWin(Mode.jumpList).isOk

  test "Change to ex mode":
    status.execJumpListCommand(ru":")

    check status.commandline.getPrompt == ru":"
    check status.commandline.buffer.len == 0
