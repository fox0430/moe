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

## A sidebar is a window that displays side to the main window.

import std/sequtils

import pkg/results

import ui, unicodeext, highlight, color, independentutils

type GlobalSidebar* = object
  highlight*: Highlight
  window: Window
  terminalBuffer: seq[Runes]

proc x*(sidebar: GlobalSidebar): int {.inline.} =
  ## Return the window position of x.

  sidebar.window.x

proc y*(sidebar: GlobalSidebar): int {.inline.} =
  ## Return the window position of x.

  sidebar.window.y

proc height*(sidebar: GlobalSidebar): int {.inline.} =
  ## Return the window height.

  sidebar.window.height

proc h*(sidebar: GlobalSidebar): int {.inline.} =
  ## Return the window height.

  sidebar.window.height

proc width*(sidebar: GlobalSidebar): int {.inline.} =
  ## Return the window width.

  sidebar.window.width

proc w*(sidebar: GlobalSidebar): int {.inline.} =
  ## Return the window width.

  sidebar.window.width

proc size*(sidebar: GlobalSidebar): Size {.inline.} =
  ## Return the sidebar window size.

  Size(h: sidebar.h, w: sidebar.w)

proc position*(sidebar: GlobalSidebar): Position {.inline.} =
  ## Return the sidebar window position.

  Position(y: sidebar.y, x: sidebar.x)

proc rect*(sidebar: GlobalSidebar): Rect {.inline.} =
  ## Return the sidebar window rect.

  Rect(y: sidebar.y, x: sidebar.x, h: sidebar.h, w: sidebar.w)

proc initTerminalBuffer(sidebar: var GlobalSidebar) {.inline.} =
  ## Init the terminal buffer.
  ## Pad the size of the `size` with spaces.

  sidebar.terminalBuffer = sidebar.h.newSeqWith(ru" ".repeat(sidebar.w))

proc initGlobalSidebar*(rect: Rect): Result[GlobalSidebar, string] =
  when not defined(release):
    assert rect.y >= 0 and rect.x >= 0 and rect.h > 0 and rect.w > 0

  var win = initWindow(rect, EditorColorPairIndex.default.ord)
  if win.isErr:
    return Result[GlobalSidebar, string].err win.error

  var gs = GlobalSidebar()
  gs.window = win.get

  gs.initTerminalBuffer

  gs.highlight = Highlight(
    colorSegments: @[
      ColorSegment(
        firstRow: 0,
        firstColumn: 0,
        lastRow: gs.terminalBuffer.high,
        lastColumn: gs.terminalBuffer[0].high,
        color: EditorColorPairIndex.default,
      )
    ]
  )

  return Result[GlobalSidebar, string].ok gs

proc initGlobalSidebar*(): Result[GlobalSidebar, string] =
  var win = initWindow(Rect(h: 1, w: 0, y: 0, x: 0), EditorColorPairIndex.default.ord)
  if win.isErr:
    return Result[GlobalSidebar, string].err win.error

  var gs = GlobalSidebar()
  gs.window = win.get

  gs.initTerminalBuffer

  gs.highlight = Highlight(
    colorSegments: @[
      ColorSegment(
        firstRow: 0,
        firstColumn: 0,
        lastRow: 1,
        lastColumn: 1,
        color: EditorColorPairIndex.default,
      )
    ]
  )

  return Result[GlobalSidebar, string].ok gs

proc initHighlight*(sidebar: var GlobalSidebar) =
  ## Init the sidebar highlight

  sidebar.highlight = Highlight(
    colorSegments: @[
      ColorSegment(
        firstRow: 0,
        lastRow: sidebar.terminalBuffer.high,
        firstColumn: 0,
        lastColumn: sidebar.terminalBuffer[0].high,
        color: EditorColorPairIndex.default,
      )
    ]
  )

proc write*(
    sidebar: var GlobalSidebar,
    startPosition: Position,
    buffer: Runes,
    color: EditorColorPairIndex = EditorColorPairIndex.default,
) {.inline.} =
  ## Write a buffer to the terminalBuffer
  ## Cut off the buffer if longer than the window size.

  when not defined(release):
    assert startPosition.y >= 0 and startPosition.x >= 0
    assert startPosition.y <= sidebar.terminalBuffer.high
    assert startPosition.x + buffer.high <= sidebar.terminalBuffer[0].high

  let y = startPosition.y
  for x in startPosition.x .. min(startPosition.x + buffer.high, sidebar.w):
    sidebar.terminalBuffer[y][x] = buffer[x - startPosition.x]

  sidebar.highlight.overwrite(
    ColorSegment(
      firstRow: startPosition.y,
      firstColumn: startPosition.x,
      lastRow: startPosition.y,
      lastColumn: startPosition.x + buffer.high,
      color: color,
    )
  )

proc write(sidebar: var GlobalSidebar) =
  ## Write a buffer to the terminal (ui).

  let buf = sidebar.terminalBuffer
  var
    highlightIndex = 0
    cs = sidebar.highlight[highlightIndex]

  for i in 0 .. buf.high:
    for j in 0 .. buf[i].high:
      if i > cs.lastRow or j > cs.lastColumn:
        highlightIndex.inc
        cs = sidebar.highlight[highlightIndex]

      sidebar.window.write(i, j, $buf[i][j], cs.color.int16)

proc noutrefresh(sidebar: GlobalSidebar) {.inline.} =
  sidebar.window.noutrefresh

proc update*(sidebar: var GlobalSidebar) =
  ## Write buffer to the terminal and refresh (noutrefresh).

  sidebar.write
  sidebar.noutrefresh

proc resize*(sidebar: var GlobalSidebar, size: Size) {.inline.} =
  ## Resize the sidebar window

  sidebar.window.resize(size)

proc resize*(sidebar: var GlobalSidebar, rect: Rect) {.inline.} =
  ## Resize the sidebar window

  sidebar.window.resize(rect)

proc move*(sidebar: var GlobalSidebar, position: Position) {.inline.} =
  ## Move the sidebar window

  sidebar.window.move(position)

proc clear*(sidebar: var GlobalSidebar) {.inline.} =
  ## Clear the terminal buffer.

  sidebar.initTerminalBuffer
