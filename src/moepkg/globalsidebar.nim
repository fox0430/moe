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

## A sidebar is a window that displays side to the main window.

import std/sequtils
import ui, unicodeext, highlight, color, independentutils

type
  GlobalSidebar* = object
    highlight*: Highlight
    window: Window
    terminalBuffer: seq[Runes]

## Return the window position of x.
proc x*(sidebar: GlobalSidebar): int {.inline.} = sidebar.window.x

## Return the window position of x.
proc y*(sidebar: GlobalSidebar): int {.inline.} = sidebar.window.y

## Return the window height.
proc height*(sidebar: GlobalSidebar): int {.inline.} = sidebar.window.height

## Return the window height.
proc h*(sidebar: GlobalSidebar): int {.inline.} = sidebar.window.height

## Return the window width.
proc width*(sidebar: GlobalSidebar): int {.inline.} = sidebar.window.width

## Return the window width.
proc w*(sidebar: GlobalSidebar): int {.inline.} = sidebar.window.width

## Return the sidebar window size.
proc size*(sidebar: GlobalSidebar): Size {.inline.} =
  Size(h: sidebar.h, w: sidebar.w)

## Return the sidebar window position.
proc position*(sidebar: GlobalSidebar): Position {.inline.} =
  Position(y: sidebar.y, x: sidebar.x)

## Return the sidebar window rect.
proc rect*(sidebar: GlobalSidebar): Rect {.inline.} =
  Rect(y: sidebar.y, x: sidebar.x, h: sidebar.h, w: sidebar.w)

## Init the terminal buffer.
## Pad the size of the `size` with spaces.
proc initTerminalBuffer(sidebar: var GlobalSidebar) {.inline.} =
  sidebar.terminalBuffer = sidebar.h.newSeqWith(ru" ".repeat(sidebar.w))

proc initGlobalSidebar*(rect: Rect): GlobalSidebar =
  when not defined(release):
    assert rect.y >= 0 and rect.x >= 0 and rect.h > 0 and rect.w > 0

  result.window = initWindow(rect, EditorColorPairIndex.default.ord)

  result.initTerminalBuffer

  result.highlight = Highlight(
    colorSegments: @[
      ColorSegment(
        firstRow: 0,
        firstColumn: 0,
        lastRow: result.terminalBuffer.high,
        lastColumn: result.terminalBuffer[0].high,
        color: EditorColorPairIndex.default)])

proc initGlobalSidebar*(): GlobalSidebar {.inline.} =
  result.window = initWindow(
    Rect(h: 1, w: 0, y: 0, x: 0),
    EditorColorPairIndex.default.ord)

  result.initTerminalBuffer

  result.highlight = Highlight(
    colorSegments: @[
      ColorSegment(
        firstRow: 0,
        firstColumn: 0,
        lastRow: 1,
        lastColumn: 1,
        color: EditorColorPairIndex.default)])

## Init the sidebar highlight
proc initHighlight*(sidebar: var GlobalSidebar) =
  sidebar.highlight = Highlight(
    colorSegments: @[
      ColorSegment(
        firstRow: 0,
        lastRow: sidebar.terminalBuffer.high,
        firstColumn: 0,
        lastColumn: sidebar.terminalBuffer[0].high,
        color: EditorColorPairIndex.default)])

## Write a buffer to the terminalBuffer
## Cut off the buffer if longer than the window sieze.
proc write*(
  sidebar: var GlobalSidebar,
  startPosition: Position,
  buffer: Runes,
  color: EditorColorPairIndex = EditorColorPairIndex.default) {.inline.} =

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
        color: color))

## Write a buffer to the terminal (ui).
proc write(sidebar: var GlobalSidebar) =
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

## Refresh the ncurses window for the sidebar.
proc refresh(sidebar: GlobalSidebar) {.inline.} = sidebar.window.refresh

## Write buffer to the terminal and refresh.
proc update*(sidebar: var GlobalSidebar) =
  sidebar.write
  sidebar.refresh

## Resize the sidebar window
proc resize*(sidebar: var GlobalSidebar, size: Size) {.inline.} =
  sidebar.window.resize(size)

## Resize the sidebar window
proc resize*(sidebar: var GlobalSidebar, rect: Rect) {.inline.} =
  sidebar.window.resize(rect)

## Move the sidebar window
proc move*(sidebar: var GlobalSidebar, position: Position) {.inline.} =
  sidebar.window.move(position)

## Clear the terminal buffer.
proc clear*(sidebar: var GlobalSidebar) {.inline.} = sidebar.initTerminalBuffer
