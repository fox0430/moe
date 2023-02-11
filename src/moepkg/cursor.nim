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

import std/[deques, strformat]
import editorview, unicodeext

type CursorPosition* = object
  y*, x*: int

proc findCursorPosition*(view: EditorView,
                         line, column: int): tuple[success: bool, y, x: int] =

  for y in 0..view.height-1:
    if view.originalLine[y] != line: continue
    if view.start[y] <= column and column < view.start[y]+view.length[y]:
      let x = if view.start[y] == column: 0
              else: width(view.lines[y][0 .. column-view.start[y]-1])
      return (true, y, x)
    if (y == view.height-1 or view.originalLine[y] != view.originalLine[y+1]) and
        view.start[y]+view.length[y] == column:
      var cursorY, cursorX: int
      cursorY = y
      cursorX = if view.start[y] == column: 0
                else: width(view.lines[y][0 .. column-view.start[y]-1])
      if cursorX == view.width:
        inc(cursorY)
        cursorX = 0
      return (true, cursorY, cursorX)

proc updatePosition(cursor: var CursorPosition,
                    view: EditorView,
                    line, column: int) =
  var success: bool
  let mess = fmt"Failed to update cursorPosition: (y, x) = ({line}, {column}), originalLine = {view.originalLine}, start = {view.start}, length = {view.length}, lines = {view.lines}, height = {view.height}, width = {view.width}"
  (success, cursor.y, cursor.x) = findCursorPosition(view, line, column)
  doAssert(success, mess)

proc update*(cursor: var CursorPosition, view: EditorView, line, column: int) {.inline.} =
  cursor.updatePosition(view, line, column)
