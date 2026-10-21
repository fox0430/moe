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

## Ctrl-T and Ctrl-D in Insert mode, as Vim's: the indent goes to the next or
## previous multiple of 'shiftwidth' and is rebuilt for 'expandtab'. An
## auto-indent they shift still comes off when Insert ends.

import std/[unittest, options]
import pkg/results

import ../src/moepkg/[types, editor, editor_mode, key_bindings]
import ../src/moepkg/handler {.all.}
import vim_like_test_helper

# Measured in Vim 9.2 (`vim -u NONE`, 'shiftwidth', 'tabstop', 'expandtab' and
# 'autoindent' as each case says).
const VimCases = [
  (
    name: "Ctrl-T rounds the indent up to a multiple of 'shiftwidth'",
    lines: @["   abc def", "x"],
    keys: "A<C-t><Escape>",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: true,
    autoIndent: false,
    want: @["    abc def", "x"],
    wantCursor: (0, 10),
  ),
  (
    name: "Ctrl-D rounds the indent down to a multiple of 'shiftwidth'",
    lines: @["     abc def", "x"],
    keys: "A<C-d><Escape>",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: true,
    autoIndent: false,
    want: @["    abc def", "x"],
    wantCursor: (0, 10),
  ),
  (
    name: "Ctrl-T without 'expandtab' builds the indent from tabs and spaces",
    lines: @["        abc def", "x"],
    keys: "A<C-t><Escape>",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: false,
    autoIndent: false,
    want: @["\t    abc def", "x"],
    wantCursor: (0, 11),
  ),
  (
    name: "Ctrl-D without 'expandtab' takes 'shiftwidth' off a tab",
    lines: @["\tabc def", "x"],
    keys: "A<C-d><Escape>",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: false,
    autoIndent: false,
    want: @["    abc def", "x"],
    wantCursor: (0, 10),
  ),
  (
    name: "Ctrl-T with 'expandtab' turns a tab into spaces",
    lines: @["\tabc def", "x"],
    keys: "I<C-t>Y<Escape>",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: true,
    autoIndent: false,
    want: @["            Yabc def", "x"],
    wantCursor: (0, 12),
  ),
  (
    name: "Ctrl-T with no 'shiftwidth' shifts by 'tabstop'",
    lines: @["  abc def", "x"],
    keys: "A<C-t><Escape>",
    shiftWidth: 0,
    tabStop: 4,
    expandTab: true,
    autoIndent: false,
    want: @["    abc def", "x"],
    wantCursor: (0, 10),
  ),
  (
    name: "a cursor in the indent keeps its screen distance, before a tab too",
    lines: @["        abc def", "x"],
    keys: "0li<C-t>Y<Escape>",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: false,
    autoIndent: false,
    want: @["     Y\t    abc def", "x"],
    wantCursor: (0, 5),
  ),
  (
    name: "Ctrl-D removes the indent before Ctrl-U deletes what was typed",
    lines: @["  abc def", "x"],
    keys: "IX<C-d><C-u><Escape>",
    shiftWidth: 2,
    tabStop: 8,
    expandTab: false,
    autoIndent: false,
    want: @["abc def", "x"],
    wantCursor: (0, 0),
  ),
  (
    name: "after Ctrl-T on an auto-indented line, Escape takes the indent off",
    lines: @["    a", "x"],
    keys: "o<C-t><Escape>",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: true,
    autoIndent: true,
    want: @["    a", "", "x"],
    wantCursor: (1, 0),
  ),
  (
    name: "after Ctrl-D on an auto-indented line, Escape takes the indent off",
    lines: @["        a", "x"],
    keys: "o<C-d><Escape>",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: true,
    autoIndent: true,
    want: @["        a", "", "x"],
    wantCursor: (1, 0),
  ),
  (
    name: "Ctrl-T on a line 'autoindent' gave no indent comes off on Escape",
    lines: @["a", "x"],
    keys: "o<C-t><Escape>",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: true,
    autoIndent: true,
    want: @["a", "", "x"],
    wantCursor: (1, 0),
  ),
  (
    name: "and on a line `cc` emptied that had no indent",
    lines: @["abc", "x"],
    keys: "cc<C-t><Escape>",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: true,
    autoIndent: true,
    want: @["", "x"],
    wantCursor: (0, 0),
  ),
  (
    name: "without 'autoindent' the indent Ctrl-T made stays",
    lines: @["a", "x"],
    keys: "o<C-t><Escape>",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: true,
    autoIndent: false,
    want: @["a", "    ", "x"],
    wantCursor: (1, 3),
  ),
  (
    name: "Enter after Ctrl-T takes the auto-indent off the line it leaves",
    lines: @["    a", "x"],
    keys: "o<C-t><Enter>y<Escape>",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: true,
    autoIndent: true,
    want: @["    a", "", "        y", "x"],
    wantCursor: (2, 8),
  ),
  (
    name: "a move after Ctrl-T takes the auto-indent off",
    lines: @["    a", "x"],
    keys: "o<C-t><Up><Escape>",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: true,
    autoIndent: true,
    want: @["    a", "", "x"],
    wantCursor: (0, 4),
  ),
  (
    name: "text typed after Ctrl-T keeps the indent",
    lines: @["    a", "x"],
    keys: "o<C-t>y<Escape>",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: true,
    autoIndent: true,
    want: @["    a", "        y", "x"],
    wantCursor: (1, 8),
  ),
  (
    name: "after Escape takes the auto-indent off, vertical moves aim past it",
    lines: @["    ab cd", "x"],
    keys: "o<Escape>k",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: true,
    autoIndent: true,
    want: @["    ab cd", "", "x"],
    wantCursor: (0, 4),
  ),
  (
    name: "vertical moves aim past the indent Ctrl-T made, after Escape",
    lines: @["    ab cd", "x"],
    keys: "o<C-t><Escape>k",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: true,
    autoIndent: true,
    want: @["    ab cd", "", "x"],
    wantCursor: (0, 8),
  ),
  (
    name: "and after Ctrl-o",
    lines: @["    ab cd", "x"],
    keys: "o<C-t><C-o>k<Escape>",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: true,
    autoIndent: true,
    want: @["    ab cd", "", "x"],
    wantCursor: (0, 7),
  ),
  (
    name: "and after Ctrl-o on a line 'autoindent' gave no indent",
    lines: @["ab cd", "x"],
    keys: "o<C-t><C-o>k<Escape>",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: true,
    autoIndent: true,
    want: @["ab cd", "", "x"],
    wantCursor: (0, 3),
  ),
  (
    name: "once Insert resumes after Ctrl-o, Escape aims at the cursor again",
    lines: @["    ab cd", "x"],
    keys: "o<C-t><C-o>zz<Escape>k",
    shiftWidth: 4,
    tabStop: 8,
    expandTab: true,
    autoIndent: true,
    want: @["    ab cd", "", "x"],
    wantCursor: (0, 0),
  ),
]

suite "Insert Ctrl-T and Ctrl-D, as in Vim":
  for c in VimCases:
    test c.name:
      let e = newVimLikeEditor(
        c.lines,
        0,
        0,
        autoIndent = c.autoIndent,
        expandTab = c.expandTab,
        tabStop = c.tabStop,
        shiftWidth = c.shiftWidth,
      )
      e.state.smartIndent = false
      for key in keysOf(c.keys):
        check e.handleKeyCombo(key)
      check e.lines == c.want
      check (e.activeWindow.cursor.line, e.activeWindow.cursor.column) == c.wantCursor

suite "Insert Ctrl-T and Ctrl-D - an auto-indent a boundary takes off":
  test "Insert goes on aiming at the cursor, not past the indent":
    # Forced Insert commits a Visual-block insert at a save without leaving
    # Insert, so no Escape keeps the column.
    let e = newVimLikeEditor(
      @["    ab", "x"], 0, 6, autoIndent = true, expandTab = true, shiftWidth = 4
    )
    e.state.smartIndent = false
    e.config.standard.forceInsertMode = true
    e.state.config.standard.forceInsertMode = true
    e.enforceModePolicy()
    for key in keysOf("<Enter><C-t>"):
      check e.handleKeyCombo(key)
    e.state.editState.visualBlockInsertContext = some(
      VisualBlockInsertContext(
        startLine: 0, endLine: 0, insertColumn: 6, firstLineLen: 6
      )
    )

    check e.commitForcedInsertBoundary(restart = false).isOk

    check e.state.mode == EditorMode.Insert
    check e.lines == @["    ab", "", "x"]
    check e.activeWindow.cursor == BufferPosition(line: 1, column: 0)
    check e.activeWindow.preferredColumn == -1

suite "keysOf, the keys the Vim cases are written in":
  test "a `<` that starts no key name is a key, as in Vim's `<<Escape>`":
    check keysOf("i<<Escape>") ==
      @[
        KeyCombo(isSpecial: false, char: "i"),
        KeyCombo(isSpecial: false, char: "<"),
        parseKeyCombo("Escape").get,
      ]
