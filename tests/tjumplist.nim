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

import std/[unittest, options, strformat]

import moepkg/[independentutils, unicodeext]

import moepkg/jumplist {.all.}

suite "jumplist: initJumpList":
  test "Basic":
    check initJumpList()[] == JumpList(currentPosition: 0, history: @[])[]

suite "jumplist: add":
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

    check l[] ==
      JumpList(
        currentPosition: 2,
        history: @[
          JumpInfo(
            bufferId: 0,
            path: ru"text0.txt",
            position: BufferPosition(line: 0, column: 0),
          ),
          JumpInfo(
            bufferId: 1,
            path: ru"text1.txt",
            position: BufferPosition(line: 1, column: 1),
          ),
        ],
      )[]

  test "Basic 2":
    for i in 0 .. 1:
      let
        bufferId = i
        line = i
        column = i
        path = fmt"text{i}.txt"
      l.add(bufferId, path.toRunes, BufferPosition(line: i, column: i))

    check l[] ==
      JumpList(
        currentPosition: 2,
        history: @[
          JumpInfo(
            bufferId: 0,
            path: ru"text0.txt",
            position: BufferPosition(line: 0, column: 0),
          ),
          JumpInfo(
            bufferId: 1,
            path: ru"text1.txt",
            position: BufferPosition(line: 1, column: 1),
          ),
        ],
      )[]

suite "jumplist: jumpBack":
  test "Basic":
    var l = JumpList(
      currentPosition: 2,
      history: @[
        JumpInfo(
          bufferId: 0, path: ru"text0.txt", position: BufferPosition(line: 0, column: 0)
        ),
        JumpInfo(
          bufferId: 0, path: ru"text1.txt", position: BufferPosition(line: 1, column: 1)
        ),
      ],
    )

    block:
      check l.jumpBack ==
        some(
          JumpInfo(
            bufferId: 0,
            path: ru"text1.txt",
            position: BufferPosition(line: 1, column: 1),
          )
        )
      check l[] ==
        JumpList(
          currentPosition: 1,
          history: @[
            JumpInfo(
              bufferId: 0,
              path: ru"text0.txt",
              position: BufferPosition(line: 0, column: 0),
            ),
            JumpInfo(
              bufferId: 0,
              path: ru"text1.txt",
              position: BufferPosition(line: 1, column: 1),
            ),
          ],
        )[]

    block:
      check l.jumpBack ==
        some(
          JumpInfo(
            bufferId: 0,
            path: ru"text0.txt",
            position: BufferPosition(line: 0, column: 0),
          )
        )
      check l[] ==
        JumpList(
          currentPosition: 0,
          history: @[
            JumpInfo(
              bufferId: 0,
              path: ru"text0.txt",
              position: BufferPosition(line: 0, column: 0),
            ),
            JumpInfo(
              bufferId: 0,
              path: ru"text1.txt",
              position: BufferPosition(line: 1, column: 1),
            ),
          ],
        )[]

    block:
      # No effect
      check l.jumpBack ==
        some(
          JumpInfo(
            bufferId: 0,
            path: ru"text0.txt",
            position: BufferPosition(line: 0, column: 0),
          )
        )
      check l[] ==
        JumpList(
          currentPosition: 0,
          history: @[
            JumpInfo(
              bufferId: 0,
              path: ru"text0.txt",
              position: BufferPosition(line: 0, column: 0),
            ),
            JumpInfo(
              bufferId: 0,
              path: ru"text1.txt",
              position: BufferPosition(line: 1, column: 1),
            ),
          ],
        )[]

suite "jumplist: jumpFoward":
  test "Basic":
    var l = JumpList(
      currentPosition: 0,
      history: @[
        JumpInfo(
          bufferId: 0, path: ru"text0.txt", position: BufferPosition(line: 0, column: 0)
        ),
        JumpInfo(
          bufferId: 0, path: ru"text1.txt", position: BufferPosition(line: 1, column: 1)
        ),
      ],
    )

    block:
      check l.jumpFoward ==
        some(
          JumpInfo(
            bufferId: 0,
            path: ru"text0.txt",
            position: BufferPosition(line: 0, column: 0),
          )
        )
      check l[] ==
        JumpList(
          currentPosition: 1,
          history: @[
            JumpInfo(
              bufferId: 0,
              path: ru"text0.txt",
              position: BufferPosition(line: 0, column: 0),
            ),
            JumpInfo(
              bufferId: 0,
              path: ru"text1.txt",
              position: BufferPosition(line: 1, column: 1),
            ),
          ],
        )[]

    block:
      # No effect
      check l.jumpFoward ==
        some(
          JumpInfo(
            bufferId: 0,
            path: ru"text1.txt",
            position: BufferPosition(line: 1, column: 1),
          )
        )
      check l[] ==
        JumpList(
          currentPosition: 1,
          history: @[
            JumpInfo(
              bufferId: 0,
              path: ru"text0.txt",
              position: BufferPosition(line: 0, column: 0),
            ),
            JumpInfo(
              bufferId: 0,
              path: ru"text1.txt",
              position: BufferPosition(line: 1, column: 1),
            ),
          ],
        )[]
