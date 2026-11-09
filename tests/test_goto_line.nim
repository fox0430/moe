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

## Where `:N` leaves the cursor: on the first non-blank, as Vim's do_one_cmd.

import std/unittest

import ../src/moepkg/[types, editor]
import ../src/moepkg/handler {.all.}
import vim_like_test_helper

proc press(e: Editor, spec: string) =
  for key in keysOf(spec):
    discard e.handleKeyCombo(key)

proc cursorAt(e: Editor): (int, int) =
  (e.activeWindow.cursor.line, e.activeWindow.cursor.column)

suite ":N goes to the first non-blank of the line, as in Vim":
  # Measured in Vim 9.2 (`vim --clean`, 'startofline' on), typed.
  const Lines = @["a", "    bbbb", "  c", "      dddd", "e"]
  for (cursor, keys, wantCursor) in [
    ((0, 0), ":2<Enter>", (1, 4)),
    ((0, 0), "$:2<Enter>j", (2, 2)),
    ((0, 0), "$:2<Enter>jj", (3, 4)),
    ((3, 8), ":0<Enter>", (0, 0)),
    ((3, 8), ":.-3<Enter>", (0, 0)),
    ((3, 8), ":.-2<Enter>", (1, 4)),
    ((0, 0), ":$<Enter>", (4, 0)),
    ((0, 0), ":99<Enter>", (4, 0)),
    ((0, 0), ":-1<Enter>", (0, 0)),
  ]:
    test keys & " from " & $cursor:
      let e = newVimLikeEditor(Lines, cursor[0], cursor[1])
      e.press(keys)
      check e.cursorAt == wantCursor

  test "an address above the first line is E16 and leaves the cursor":
    let e = newVimLikeEditor(Lines, 2, 2)
    e.press(":-5<Enter>")
    check e.cursorAt == (2, 2)
    check e.state.statusMessage == "E16: Invalid range"

  test "it marks no jump":
    let e = newVimLikeEditor(Lines, 3, 8)
    e.press(":2<Enter>")
    check e.state.jumpList.list.len == 0
