#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import std/[unittest, importutils, options]

import pkg/results

import moepkg/independentutils

import moepkg/bufferstatus {.all.}

suite "setGotoDefinitionSource":
  privateAccess(BufferStatus)

  test "Basic":
    var b = initBufferStatus().get
    let l = BufferLocation(
      path: "/path",
      range: BufferRange(
        first: BufferPosition(line: 0, column: 1),
        last: BufferPosition(line: 0, column: 1),
      ),
    )

    b.setGotoDefinitionSource(l)

    check b.gotoDefinitionSource.get == l

  test "Overwrite":
    var b = initBufferStatus().get

    b.setGotoDefinitionSource(
      BufferLocation(
        path: "/path",
        range: BufferRange(
          first: BufferPosition(line: 0, column: 1),
          last: BufferPosition(line: 0, column: 1),
        ),
      )
    )

    let l = BufferLocation(
      path: "/dir/path/",
      range: BufferRange(
        first: BufferPosition(line: 1, column: 2),
        last: BufferPosition(line: 1, column: 2),
      ),
    )

    b.setGotoDefinitionSource(l)

    check b.gotoDefinitionSource.get == l

suite "getGotoDefinitionSource":
  privateAccess(BufferStatus)

  test "Empty":
    var b = initBufferStatus().get

    check b.getGotoDefinitionSource.isNone

  test "Basic":
    var b = initBufferStatus().get

    let l = BufferLocation(
      path: "/path",
      range: BufferRange(
        first: BufferPosition(line: 0, column: 1),
        last: BufferPosition(line: 0, column: 1),
      ),
    )

    b.gotoDefinitionSource = some(l)

    check b.getGotoDefinitionSource.get == l
    check b.getGotoDefinitionSource.isNone

  test "Peek":
    var b = initBufferStatus().get

    let l = BufferLocation(
      path: "/path",
      range: BufferRange(
        first: BufferPosition(line: 0, column: 1),
        last: BufferPosition(line: 0, column: 1),
      ),
    )

    b.gotoDefinitionSource = some(l)

    check b.getGotoDefinitionSource(clear = false).get == l
    check b.getGotoDefinitionSource.isSome
