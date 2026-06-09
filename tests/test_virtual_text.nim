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

import std/[unittest, tables]

import ../src/moepkg/[virtual_text, color]

proc chunk(text: string, color = EditorColorPairIndex.inlayHint): VirtualTextChunk =
  VirtualTextChunk(text: text, color: color)

proc endOfLineProvider(items: seq[VirtualText]): VirtualTextProvider =
  result = proc(line: int): seq[VirtualText] {.closure, gcsafe, raises: [].} =
    for it in items:
      if it.line == line:
        result.add it

suite "virtual_text - totalWidth":
  test "ascii sums to length":
    check totalWidth(@[chunk("abc")]) == 3

  test "wide characters count as two":
    check totalWidth(@[chunk("あい")]) == 4

  test "multiple chunks add up":
    check totalWidth(@[chunk("ab"), chunk("あ")]) == 4

suite "virtual_text - collectVirtualText":
  test "empty providers yield empty line":
    let vt = collectVirtualText([], 0)
    check vt.isEmpty

  test "provider returning nothing for a line yields empty":
    let p = endOfLineProvider(
      @[VirtualText(line: 5, placement: vtpEndOfLine, chunks: @[chunk("x")])]
    )
    let vt = collectVirtualText([p], 0)
    check vt.isEmpty

  test "end-of-line chunks are collected":
    let p = endOfLineProvider(
      @[VirtualText(line: 0, placement: vtpEndOfLine, chunks: @[chunk(": int")])]
    )
    let vt = collectVirtualText([p], 0)
    check not vt.isEmpty
    check vt.endOfLine.len == 1
    check vt.endOfLine[0].text == ": int"

  test "priority orders end-of-line chunks ascending":
    let items = @[
      VirtualText(
        line: 0, placement: vtpEndOfLine, priority: 100, chunks: @[chunk("blame")]
      ),
      VirtualText(
        line: 0, placement: vtpEndOfLine, priority: 0, chunks: @[chunk("hint")]
      ),
      VirtualText(
        line: 0, placement: vtpEndOfLine, priority: 10, chunks: @[chunk("diag")]
      ),
    ]
    let vt = collectVirtualText([endOfLineProvider(items)], 0)
    check vt.endOfLine.len == 3
    check vt.endOfLine[0].text == "hint"
    check vt.endOfLine[1].text == "diag"
    check vt.endOfLine[2].text == "blame"

  test "equal priority keeps provider order (stable sort)":
    let a = endOfLineProvider(
      @[
        VirtualText(
          line: 0, placement: vtpEndOfLine, priority: 0, chunks: @[chunk("a")]
        )
      ]
    )
    let b = endOfLineProvider(
      @[
        VirtualText(
          line: 0, placement: vtpEndOfLine, priority: 0, chunks: @[chunk("b")]
        )
      ]
    )
    let vt = collectVirtualText([a, b], 0)
    check vt.endOfLine.len == 2
    check vt.endOfLine[0].text == "a"
    check vt.endOfLine[1].text == "b"

  test "inline placement is grouped by column":
    let items = @[
      VirtualText(line: 0, column: 5, placement: vtpInline, chunks: @[chunk("x")]),
      VirtualText(line: 0, column: 5, placement: vtpInline, chunks: @[chunk("y")]),
      VirtualText(line: 0, column: 2, placement: vtpInline, chunks: @[chunk("z")]),
    ]
    let vt = collectVirtualText([endOfLineProvider(items)], 0)
    check vt.inlineByColumn[5].len == 2
    check vt.inlineByColumn[2].len == 1
    check vt.endOfLine.len == 0

  test "nil provider in the list is skipped":
    var nilProvider: VirtualTextProvider = nil
    let p = endOfLineProvider(
      @[VirtualText(line: 0, placement: vtpEndOfLine, chunks: @[chunk("ok")])]
    )
    let vt = collectVirtualText([nilProvider, p], 0)
    check vt.endOfLine.len == 1

suite "virtual_text - inlineWidthBefore":
  test "sums only inline widths before the column":
    let items = @[
      VirtualText(line: 0, column: 2, placement: vtpInline, chunks: @[chunk("ab")]),
      VirtualText(line: 0, column: 8, placement: vtpInline, chunks: @[chunk("cd")]),
    ]
    let vt = collectVirtualText([endOfLineProvider(items)], 0)
    check vt.inlineWidthBefore(5) == 2
    check vt.inlineWidthBefore(10) == 4
    check vt.inlineWidthBefore(0) == 0
