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

import std/[unittest, options]

import moepkg/folding {.all.}

suite "folding: isStartLine":
  test "Empty":
    let r: FoldingRanges = @[]

    check not r.isStartLine(0)

  test "Not found":
    let r = @[FoldingRange(first: 0, last: 1)]

    check not r.isStartLine(2)

  test "Not found 2":
    let r = @[FoldingRange(first: 0, last: 1)]

    check not r.isStartLine(1)

  test "Basic":
    let r = @[FoldingRange(first: 0, last: 1)]

    check r.isStartLine(0)

suite "folding: inRange":
  test "Empty":
    let r: FoldingRanges = @[]

    check not r.inRange(0)

  test "Not found":
    let r = @[FoldingRange(first: 0, last: 1)]

    check not r.inRange(2)

  test "Basic":
    let r = @[FoldingRange(first: 0, last: 1)]

    check r.inRange(0)

  test "Basic 2":
    let r = @[FoldingRange(first: 0, last: 3)]

    check r.inRange(2)


suite "folding: find":
  test "Empty":
    let r: FoldingRanges = @[]
    check r.find(FoldingRange()).isNone

  test "Not found":
    let r = @[
      FoldingRange(first: 0, last: 2),
      FoldingRange(first: 5, last: 6)
    ]

    check r.find(FoldingRange(first: 0, last: 3)).isNone

  test "Not found 2":
    let r = @[
      FoldingRange(first: 0, last: 2),
      FoldingRange(first: 5, last: 6)
    ]

    check r.find(FoldingRange(first: 3, last: 4)).isNone

  test "Basic":
    let r = @[
      FoldingRange(first: 0, last: 2),
      FoldingRange(first: 5, last: 6)
    ]

    check r.find(FoldingRange(first: 5, last: 6)).get == 1

suite "folding: remove with FoldingRange":
  test "Empty":
    var r: FoldingRanges = @[]
    r.remove(FoldingRange())

    check r.len == 0

  test "Not found":
    var r = @[
      FoldingRange(first: 0, last: 2),
      FoldingRange(first: 5, last: 6)
    ]
    r.remove(FoldingRange(first: 0, last: 3))

    check r.len == 2

  test "Not found 2":
    var r = @[
      FoldingRange(first: 0, last: 2),
      FoldingRange(first: 5, last: 6)
    ]
    r.remove(FoldingRange(first: 4, last: 5))

    check r.len == 2

  test "Basic":
    var r = @[
      FoldingRange(first: 0, last: 2),
      FoldingRange(first: 5, last: 6)
    ]
    r.remove(FoldingRange(first: 0, last: 2))

    check r.len == 1

suite "folding: remove with line":
  test "Empty":
    var r: FoldingRanges = @[]
    r.remove(0)

    check r.len == 0

  test "Not found":
    var r = @[
      FoldingRange(first: 0, last: 2),
      FoldingRange(first: 5, last: 6)
    ]
    r.remove(3)

    check r.len == 2

  test "Basic":
    var r = @[
      FoldingRange(first: 0, last: 2),
      FoldingRange(first: 5, last: 6)
    ]
    r.remove(0)

    check r.len == 1

  test "Basic 2":
    var r = @[
      FoldingRange(first: 0, last: 2),
      FoldingRange(first: 5, last: 6)
    ]
    r.remove(1)

    check r.len == 1

suite "folding: add":
  test "Basic":
    var r: FoldingRanges = @[]
    r.add FoldingRange(first: 1, last: 2)

    check r == @[FoldingRange(first: 1, last: 2)]

  test "Basic 2":
    var r = @[
      FoldingRange(first: 2, last: 3),
      FoldingRange(first: 6, last: 7)
    ]

    r.add FoldingRange(first: 4, last: 5)
    check r == @[
      FoldingRange(first: 2, last: 3),
      FoldingRange(first: 4, last: 5),
      FoldingRange(first: 6, last: 7)
    ]

    r.add FoldingRange(first: 10, last: 12)
    check r == @[
      FoldingRange(first: 2, last: 3),
      FoldingRange(first: 4, last: 5),
      FoldingRange(first: 6, last: 7),
      FoldingRange(first: 10, last: 12)
    ]

    r.add FoldingRange(first: 0, last: 1)
    check r == @[
      FoldingRange(first: 0, last: 1),
      FoldingRange(first: 2, last: 3),
      FoldingRange(first: 4, last: 5),
      FoldingRange(first: 6, last: 7),
      FoldingRange(first: 10, last: 12)
    ]

  test "Basic 3":
    var r = @[
      FoldingRange(first: 2, last: 3),
      FoldingRange(first: 6, last: 7)
    ]

    r.add FoldingRange(first: 0, last: 4)
    check r == @[
      FoldingRange(first: 0, last: 4),
      FoldingRange(first: 2, last: 3),
      FoldingRange(first: 6, last: 7)
    ]

  test "Basic 4":
    var r = @[
      FoldingRange(first: 3, last: 4)
    ]

    r.add FoldingRange(first: 0, last: 4)
    check r == @[
      FoldingRange(first: 0, last: 4),
      FoldingRange(first: 3, last: 4)
    ]

  test "Basic 5":
    var r = @[
      FoldingRange(first: 3, last: 4)
    ]

    r.add FoldingRange(first: 0, last: 5)
    check r == @[
      FoldingRange(first: 0, last: 5),
      FoldingRange(first: 3, last: 4)
    ]

  test "Basic 6":
    var r = @[
      FoldingRange(first: 3, last: 4),
      FoldingRange(first: 6, last: 7)
    ]

    r.add FoldingRange(first: 0, last: 8)
    check r == @[
      FoldingRange(first: 0, last: 8),
      FoldingRange(first: 3, last: 4),
      FoldingRange(first: 6, last: 7)
    ]
