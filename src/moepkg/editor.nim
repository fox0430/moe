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

import pkg/[celina, results]

import buffer, cursor

type
  EditorState* = ref object
    cursor*: CursorPosition

  Editor* = ref object
    textBuffer*: TextBuffer
    state*: EditorState

proc newEditor*(): Editor =
  Editor(textBuffer: newTextBuffer(), state: EditorState())

proc loadFile*(editor: Editor, path: string): Result[(), string] =
  let r = editor.textBuffer.loadFile(path)
  if r.isErr:
    return err r.error

  editor.state.cursor = CursorPosition(line: 0, column: 0)
  return ok(())

proc render*(e: Editor, buffer: var Buffer) =
  for i in 0 .. e.textBuffer.len:
    buffer.setString(0, i, e.textBuffer.getLine(i))
