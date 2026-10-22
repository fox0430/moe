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

## `p`, `P`, `gp` and `gP` in Normal and Visual mode, and after Ctrl-o in
## Insert mode, as Vim's do_put: where the text goes, where the cursor lands,
## what a count does and where undo puts the cursor back.

import std/[options, strutils, unittest]

import pkg/results

import ../src/moepkg/[types, editor, registers]
import ../src/moepkg/handler {.all.}
import vim_like_test_helper

# Measured in Vim 9.2 (`vim -u NONE`), with the unnamed register set by
# setreg() before the keys.
const VimCases = [
  (
    name: "p puts text within a line after the cursor and lands on its last character",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (0, 3),
    setup: "",
    keys: "p",
    register: "XY",
    linewise: false,
    want: @["abc XYdef", "  ghi", "", "jkl mno", "pq"],
    wantCursor: (0, 5),
    wantUnnamed: "XY",
    checksUnnamed: true,
  ),
  (
    name: "P lands on the last character it put",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (1, 2),
    setup: "",
    keys: "P",
    register: "日本",
    linewise: false,
    want: @["abc def", "  日本ghi", "", "jkl mno", "pq"],
    wantCursor: (1, 3),
    wantUnnamed: "日本",
    checksUnnamed: true,
  ),
  (
    name: "a count puts the text that many times and lands on the last character",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (0, 6),
    setup: "",
    keys: "3p",
    register: "XY",
    linewise: false,
    want: @["abc defXYXYXY", "  ghi", "", "jkl mno", "pq"],
    wantCursor: (0, 12),
    wantUnnamed: "XY",
    checksUnnamed: true,
  ),
  (
    name: "`.` puts again after the last character the put landed on",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (0, 0),
    setup: "",
    keys: "p.",
    register: "XY",
    linewise: false,
    want: @["aXYXYbc def", "  ghi", "", "jkl mno", "pq"],
    wantCursor: (0, 4),
    wantUnnamed: "XY",
    checksUnnamed: true,
  ),
  (
    name: "p puts text across lines after the cursor and lands on its start",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (0, 3),
    setup: "",
    keys: "p",
    register: "XY\nZW",
    linewise: false,
    want: @["abc XY", "ZWdef", "  ghi", "", "jkl mno", "pq"],
    wantCursor: (0, 4),
    wantUnnamed: "XY\nZW",
    checksUnnamed: true,
  ),
  (
    name: "gp lands after text across lines",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (0, 3),
    setup: "",
    keys: "gp",
    register: "XY\nZW",
    linewise: false,
    want: @["abc XY", "ZWdef", "  ghi", "", "jkl mno", "pq"],
    wantCursor: (1, 2),
    wantUnnamed: "XY\nZW",
    checksUnnamed: true,
  ),
  (
    name: "a count puts lines in their order",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (0, 3),
    setup: "",
    keys: "3p",
    register: "L1\n  L2\n",
    linewise: true,
    want: @[
      "abc def", "L1", "  L2", "L1", "  L2", "L1", "  L2", "  ghi", "", "jkl mno", "pq"
    ],
    wantCursor: (1, 0),
    wantUnnamed: "L1\n  L2\n",
    checksUnnamed: true,
  ),
  (
    name: "gp with a count lands below all the lines",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (0, 3),
    setup: "",
    keys: "3gp",
    register: "L1\nL2\n",
    linewise: true,
    want: @["abc def", "L1", "L2", "L1", "L2", "L1", "L2", "  ghi", "", "jkl mno", "pq"],
    wantCursor: (7, 0),
    wantUnnamed: "L1\nL2\n",
    checksUnnamed: true,
  ),
  (
    name: "P puts lines above and lands on the first one's first non-blank",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (3, 4),
    setup: "",
    keys: "2P",
    register: "  LL\n",
    linewise: true,
    want: @["abc def", "  ghi", "", "  LL", "  LL", "jkl mno", "pq"],
    wantCursor: (3, 2),
    wantUnnamed: "  LL\n",
    checksUnnamed: true,
  ),
  (
    name: "lines go below a closed fold, the cursor on the first one",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (1, 0),
    setup: "jVjzfgg",
    keys: "2p",
    register: "  LL\n",
    linewise: true,
    want: @["abc def", "  ghi", "", "  LL", "  LL", "jkl mno", "pq"],
    wantCursor: (3, 2),
    wantUnnamed: "  LL\n",
    checksUnnamed: true,
  ),
  (
    name: "undo after a put goes back where the cursor was",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (0, 3),
    setup: "",
    keys: "pu",
    register: "XY",
    linewise: false,
    want: @["abc def", "  ghi", "", "jkl mno", "pq"],
    wantCursor: (0, 3),
    wantUnnamed: "XY",
    checksUnnamed: true,
  ),
  (
    name: "undo after a put of lines goes back where the cursor was",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (1, 2),
    setup: "",
    keys: "3pu",
    register: "  LL\n",
    linewise: true,
    want: @["abc def", "  ghi", "", "jkl mno", "pq"],
    wantCursor: (1, 2),
    wantUnnamed: "  LL\n",
    checksUnnamed: true,
  ),
  (
    name: "Ctrl-o p resumes Insert after the text",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (0, 3),
    setup: "",
    keys: "i<C-o>pX",
    register: "XY",
    linewise: false,
    want: @["abc XYXdef", "  ghi", "", "jkl mno", "pq"],
    wantCursor: (0, 6),
    wantUnnamed: "XY",
    checksUnnamed: true,
  ),
  (
    name: "Ctrl-o p at the end of a line resumes after the text",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (4, 1),
    setup: "",
    keys: "A<C-o>pX",
    register: "XY",
    linewise: false,
    want: @["abc def", "  ghi", "", "jkl mno", "pqXYX"],
    wantCursor: (4, 4),
    wantUnnamed: "XY",
    checksUnnamed: true,
  ),
  (
    name: "Ctrl-o gP resumes Insert past the end of the last line put",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (2, 0),
    setup: "",
    keys: "i<C-o>gPX",
    register: "XY\nZW",
    linewise: false,
    want: @["abc def", "  ghi", "XY", "ZWX", "jkl mno", "pq"],
    wantCursor: (3, 2),
    wantUnnamed: "XY\nZW",
    checksUnnamed: true,
  ),
  (
    name: "Visual p lands on the last character it put",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (0, 3),
    setup: "",
    keys: "vlp",
    register: "XY",
    linewise: false,
    want: @["abcXYef", "  ghi", "", "jkl mno", "pq"],
    wantCursor: (0, 4),
    wantUnnamed: " d",
    checksUnnamed: true,
  ),
  (
    name: "Visual p takes a count",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (1, 2),
    setup: "",
    keys: "vl2p",
    register: "XY",
    linewise: false,
    want: @["abc def", "  XYXYi", "", "jkl mno", "pq"],
    wantCursor: (1, 5),
    wantUnnamed: "gh",
    checksUnnamed: true,
  ),
  (
    name: "Visual p over lines takes a count",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (0, 0),
    setup: "",
    keys: "Vj2p",
    register: "L1\nL2\n",
    linewise: true,
    want: @["L1", "L2", "L1", "L2", "", "jkl mno", "pq"],
    wantCursor: (0, 0),
    wantUnnamed: "abc def\n  ghi\n",
    checksUnnamed: true,
  ),
  (
    name: "Visual p splits the line for lines over characters",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (0, 3),
    setup: "",
    keys: "vlp",
    register: "  LL\n",
    linewise: true,
    want: @["abc", "  LL", "ef", "  ghi", "", "jkl mno", "pq"],
    wantCursor: (1, 2),
    wantUnnamed: " d",
    checksUnnamed: true,
  ),
  (
    name: "Visual p over every line leaves no empty line",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (0, 0),
    setup: "",
    keys: "ggVGp",
    register: "L1\nL2\n",
    linewise: true,
    want: @["L1", "L2"],
    wantCursor: (0, 0),
    wantUnnamed: "abc def\n  ghi\n\njkl mno\npq\n",
    checksUnnamed: true,
  ),
  (
    name: "Visual p over a block puts text within a line into each line",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (0, 0),
    setup: "",
    keys: "<C-v>jlp",
    register: "XY",
    linewise: false,
    want: @["XYc def", "XYghi", "", "jkl mno", "pq"],
    wantCursor: (0, 1),
    wantUnnamed: "",
    checksUnnamed: false,
  ),
  (
    name: "Visual p over a block passes over lines too short for it",
    lines: @["abcdef", "ab", "", "abcdefgh", "abc"],
    cursor: (0, 3),
    setup: "",
    keys: "<C-v>jjjlp",
    register: "XY",
    linewise: false,
    want: @["abcXYf", "ab", "", "abcXYfgh", "abc"],
    wantCursor: (0, 4),
    wantUnnamed: "",
    checksUnnamed: false,
  ),
  (
    name: "gp over a block lands after the text on its first line",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (0, 3),
    setup: "",
    keys: "<C-v>jlgp",
    register: "XY",
    linewise: false,
    want: @["abcXYef", "  gXY", "", "jkl mno", "pq"],
    wantCursor: (0, 5),
    wantUnnamed: "",
    checksUnnamed: false,
  ),
  (
    name: "Visual p over a block puts lines below the line the cursor ended on",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (1, 2),
    setup: "",
    keys: "<C-v>klp",
    register: "L1\n",
    linewise: true,
    want: @["abdef", "L1", "  i", "", "jkl mno", "pq"],
    wantCursor: (1, 0),
    wantUnnamed: "",
    checksUnnamed: false,
  ),
  (
    name: "undo after Visual p over a block goes back to its top left",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (0, 3),
    setup: "",
    keys: "<C-v>jlpu",
    register: "XY",
    linewise: false,
    want: @["abc def", "  ghi", "", "jkl mno", "pq"],
    wantCursor: (0, 3),
    wantUnnamed: "",
    checksUnnamed: false,
  ),
  (
    name: "undo after Visual p over lines selected upward keeps the cursor's column",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (1, 2),
    setup: "",
    keys: "Vkpu",
    register: "XY",
    linewise: false,
    want: @["abc def", "  ghi", "", "jkl mno", "pq"],
    wantCursor: (0, 2),
    wantUnnamed: "abc def\n  ghi\n",
    checksUnnamed: true,
  ),
  (
    name: "undo after Visual p over lines selected downward goes to the line start",
    lines: @["abc def", "  ghi", "", "jkl mno", "pq"],
    cursor: (1, 2),
    setup: "",
    keys: "Vjpu",
    register: "XY",
    linewise: false,
    want: @["abc def", "  ghi", "", "jkl mno", "pq"],
    wantCursor: (1, 0),
    wantUnnamed: "  ghi\n\n",
    checksUnnamed: true,
  ),
  (
    name: "Visual p on the only, empty line keeps the register",
    lines: @[""],
    cursor: (0, 0),
    setup: "",
    keys: "vp",
    register: "XY",
    linewise: false,
    want: @["XY"],
    wantCursor: (0, 1),
    wantUnnamed: "XY",
    checksUnnamed: true,
  ),
]

# Measured in Vim 9.2 (`vim -u NONE`, ts=4): a block yanked with `<C-v>`, then put.
const BlockCases = [
  (
    name: "p puts each row on a line of its own at the cell after the cursor",
    lines: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"],
    cursor: (0, 0),
    keys: "<C-v>jlyjjp",
    want: @["abcdef", "ab", "aabbcdef", " ab", "abcdefgh", "abc"],
    wantCursor: (2, 1),
  ),
  (
    name: "P puts the rows at the cursor's cell",
    lines: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"],
    cursor: (0, 0),
    keys: "<C-v>jlyjjP",
    want: @["abcdef", "ab", "ababcdef", "ab", "abcdefgh", "abc"],
    wantCursor: (2, 0),
  ),
  (
    name: "a line too short for the cell is padded with blanks",
    lines: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"],
    cursor: (0, 0),
    keys: "<C-v>jlyjj4|p",
    want: @["abcdef", "ab", "abcdabef", "    ab", "abcdefgh", "abc"],
    wantCursor: (2, 4),
  ),
  (
    name: "a row is padded to the block's width when text follows it",
    lines: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"],
    cursor: (0, 0),
    keys: "5|<C-v>jj7|yggP",
    want: @["ef abcdef", "   ab", "ef abcdef", "", "abcdefgh", "abc"],
    wantCursor: (0, 0),
  ),
  (
    name: "a row that ends its line is not padded",
    lines: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"],
    cursor: (0, 0),
    keys: "5|<C-v>jj7|yjj$p",
    want: @["abcdef", "ab", "abcdefef", "         ", "abcdefef gh", "abc"],
    wantCursor: (2, 6),
  ),
  (
    name: "rows past the end of the buffer go on new lines",
    lines: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"],
    cursor: (0, 0),
    keys: "<C-v>jjlyG$p",
    want: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abcab", "   ab", "   ab"],
    wantCursor: (5, 3),
  ),
  (
    name: "a count puts the rows side by side",
    lines: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"],
    cursor: (0, 0),
    keys: "<C-v>jly3P",
    want: @["ababababcdef", "abababab", "abcdef", "", "abcdefgh", "abc"],
    wantCursor: (0, 0),
  ),
  (
    name: "gp lands after the last row",
    lines: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"],
    cursor: (0, 0),
    keys: "<C-v>jlyjjgp",
    want: @["abcdef", "ab", "aabbcdef", " ab", "abcdefgh", "abc"],
    wantCursor: (3, 2),
  ),
  (
    name: "a block after <C-v>$ is as wide as its widest line",
    lines: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"],
    cursor: (0, 0),
    keys: "<C-v>jj$yggP",
    want: @["abcdefabcdef", "ab    ab", "abcdefabcdef", "", "abcdefgh", "abc"],
    wantCursor: (0, 0),
  ),
  (
    name: "a tab across the cell splits into blanks",
    lines: @["XY", "XY", "abcdef", "a\tb"],
    cursor: (0, 0),
    keys: "<C-v>jlyjj3|P",
    want: @["XY", "XY", "abXYcdef", "a XY  b"],
    wantCursor: (2, 2),
  ),
  (
    name: "a wide character across the cell goes after the row",
    lines: @[
      "日本語テキスト", "abcdefghij", "a日b本c", "ab", "日本", "abcdefghij"
    ],
    cursor: (1, 0),
    keys: "<C-v>jy3|P",
    want: @[
      "日本語テキスト", "abacdefghij", "a a日b本c", "ab", "日本",
      "abcdefghij",
    ],
    wantCursor: (1, 2),
  ),
  (
    name: "tabs in a row count their full width for the padding",
    lines: @["a\tbcdef", "abcdefghij", "ab", "", "\tx\ty", "xy\tz", "abcdefghij"],
    cursor: (4, 0),
    keys: "<C-v>jj3|yggP",
    want:
      @["\ta\tbcdef", "xy\tabcdefghij", "abcdab", "", "\tx\ty", "xy\tz", "abcdefghij"],
    wantCursor: (0, 0),
  ),
  (
    name: "undo goes back to where the cursor was",
    lines: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"],
    cursor: (0, 0),
    keys: "<C-v>jlyjjpu",
    want: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"],
    wantCursor: (2, 0),
  ),
  (
    name: "`.` puts the block again",
    lines: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"],
    cursor: (0, 0),
    keys: "<C-v>jlyjjpj.",
    want: @["abcdef", "ab", "aabbcdef", " aabb", "ababcdefgh", "abc"],
    wantCursor: (3, 2),
  ),
  (
    name: "Visual p over characters puts the block where they were",
    lines: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"],
    cursor: (0, 0),
    keys: "<C-v>jlyjjvlp",
    want: @["abcdef", "ab", "abcdef", "ab", "abcdefgh", "abc"],
    wantCursor: (2, 0),
  ),
  (
    name: "Visual p over lines puts the rows as lines",
    lines: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"],
    cursor: (0, 0),
    keys: "<C-v>jlyjjVp",
    want: @["abcdef", "ab", "ab", "ab", "", "abcdefgh", "abc"],
    wantCursor: (2, 0),
  ),
  (
    name: "Visual p over a block puts the block where it was",
    lines: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"],
    cursor: (0, 0),
    keys: "<C-v>jlyjj<C-v>jlp",
    want: @["abcdef", "ab", "abbcdef", "ab", "abcdefgh", "abc"],
    wantCursor: (2, 0),
  ),
  (
    name: "Ctrl-o p in Insert puts the block and Insert resumes before it",
    lines: @["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"],
    cursor: (0, 0),
    keys: "<C-v>jlyjjA<C-o>pX<Escape>",
    want: @["abcdef", "ab", "abcdefXab", "      ab", "abcdefgh", "abc"],
    wantCursor: (2, 6),
  ),
]

suite "Put, as in Vim":
  for c in VimCases:
    test c.name:
      let e = newVimLikeEditor(c.lines, 0, 0)
      check e.state.registers.setRegister('"', c.register, c.linewise).isOk
      for key in keysOf(c.setup):
        check e.handleKeyCombo(key)
      e.activeWindow.cursor = BufferPosition(line: c.cursor[0], column: c.cursor[1])
      for key in keysOf(c.keys):
        check e.handleKeyCombo(key)
      if e.state.mode == EditorMode.Insert:
        check e.handleKeyCombo(keysOf("<Escape>")[0])
      check e.lines == c.want
      check (e.activeWindow.cursor.line, e.activeWindow.cursor.column) == c.wantCursor
      if c.checksUnnamed:
        check e.state.registers.getRegisterContent('"') == c.wantUnnamed

suite "Put a block, as in Vim":
  for c in BlockCases:
    test c.name:
      let e = newVimLikeEditor(c.lines, c.cursor[0], c.cursor[1], tabStop = 4)
      for key in keysOf(c.keys):
        check e.handleKeyCombo(key)
      if e.state.mode == EditorMode.Insert:
        check e.handleKeyCombo(keysOf("<Escape>")[0])
      check e.lines == c.want
      check (e.activeWindow.cursor.line, e.activeWindow.cursor.column) == c.wantCursor

  test "a block yank keeps a block as wide as the cells it covers":
    # Vim 9.2: getregtype() gives "\x163" after `5|<C-v>jj7|y` and "\x166"
    # after `<C-v>jj$y`.
    for (keys, width) in [("5|<C-v>jj7|y", 3), ("<C-v>jj$y", 6)]:
      let e = newVimLikeEditor(@["abcdef", "ab", "abcdef"], 0, 0, tabStop = 4)
      for key in keysOf(keys):
        check e.handleKeyCombo(key)
      let reg = e.state.registers.getNumberRegister(0)
      check reg.kind == rkBlock
      check reg.width == width

suite "Yanking nothing, as in Vim":
  test "a yank of an empty range keeps the empty text":
    # Vim 9.2: `yl` on an empty line and `yi(` on `()` set "0 and the unnamed
    # register to "", while `dl` there leaves them.
    for (line, column, keys) in [("", 0, "yl"), ("x()y", 1, "yi(")]:
      let e = newVimLikeEditor(@[line, "second"], 0, column)
      check e.state.registers.setRegister('"', "Q", false).isOk
      for key in keysOf(keys):
        check e.handleKeyCombo(key)
      check e.state.registers.getNumberRegister(0).getLines() == @[""]
      check e.state.registers.getNoNamedRegister().getLines() == @[""]
    let e = newVimLikeEditor(@["", "second"], 0, 0)
    check e.state.registers.setRegister('"', "Q", false).isOk
    for key in keysOf("dl"):
      check e.handleKeyCombo(key)
    check e.state.registers.getNoNamedRegister().getContent() == "Q"

  test "a block delete within an empty line leaves the registers, `c` writes":
    # Vim 9.2: `<C-v>d` on the empty middle line keeps "Q"; `<C-v>c` sets the
    # unnamed register to an empty block one cell wide.
    let e = newVimLikeEditor(@["abc", "", "def"], 1, 0)
    check e.state.registers.setRegister('"', "Q", false).isOk
    for key in keysOf("<C-v>d"):
      check e.handleKeyCombo(key)
    check e.state.registers.getNoNamedRegister().getContent() == "Q"
    for key in keysOf("<C-v>c<Escape>"):
      check e.handleKeyCombo(key)
    let reg = e.state.registers.getNoNamedRegister()
    check reg.kind == rkBlock
    check reg.width == 1
    check reg.getLines() == @[""]

  test "a put of what an empty yank left puts nothing, and quietly":
    # Vim 9.2: after `"ayl` on an empty line, `"ap` changes nothing and gives
    # no error; a register never written is E353.
    let e = newVimLikeEditor(@["abc", "", "def"], 1, 0)
    for key in keysOf("\"aylk\"ap"):
      check e.handleKeyCombo(key)
    check e.lines == @["abc", "", "def"]
    check e.state.statusMessage == ""
    for key in keysOf("\"bp"):
      discard e.handleKeyCombo(key)
    check e.state.statusMessage == "E353: Nothing in register b"

  test "a change over an empty region leaves the registers":
    # Vim 9.2: `vc` on the empty last line keeps "KEEP" (oap->empty), while
    # `<C-v>c` there writes an empty block.
    let e = newVimLikeEditor(@["abc", ""], 1, 0)
    check e.state.registers.setRegister('"', "KEEP", false).isOk
    for key in keysOf("vcX<Escape>"):
      check e.handleKeyCombo(key)
    check e.lines == @["abc", "X"]
    check e.state.registers.getNoNamedRegister().getContent() == "KEEP"

  test "a block added to an empty yank goes on as characters":
    # Vim 9.2, from the empty line: `"ayl<C-v>jl"AyG"ap`.
    let e = newVimLikeEditor(@["abcdef", "ab", "abcdef", "", "abcdefgh", "abc"], 3, 0)
    for key in keysOf("\"ayl<C-v>jl\"AyG\"ap"):
      check e.handleKeyCombo(key)
    check e.lines == @["abcdef", "ab", "abcdef", "", "abcdefgh", "a", "abbc"]
    check (e.activeWindow.cursor.line, e.activeWindow.cursor.column) == (5, 0)

suite "Put, as in Vim - limits":
  test "a count that makes the text too long is E1240 and puts nothing":
    # Vim 9.2: `999999p` of 3000 characters reports E1240 and leaves the line.
    let e = newVimLikeEditor(@["abc"], 0, 0)
    check e.state.registers.setRegister('"', "x".repeat(3000), false).isOk
    for key in keysOf("999999p"):
      check e.handleKeyCombo(key)
    check e.lines == @["abc"]
    check e.state.statusMessage == "E1240: Resulting text too long"

  test "a count that makes a block's row too long is E1240 and puts nothing":
    let e = newVimLikeEditor(@["abc", "def"], 0, 0)
    e.state.registers.storeYanked(
      none(char), blockRegister(@["x".repeat(3000), "y".repeat(3000)], 3000)
    )
    for key in keysOf("999999p"):
      check e.handleKeyCombo(key)
    check e.lines == @["abc", "def"]
    check e.state.statusMessage == "E1240: Resulting text too long"

  test "a count that makes a block put as lines too long is E1240 too":
    let e = newVimLikeEditor(@["abc", "def"], 0, 0)
    e.state.registers.storeYanked(
      none(char), blockRegister(@["x".repeat(3000), "y".repeat(3000)], 3000)
    )
    for key in keysOf("V999999p"):
      discard e.handleKeyCombo(key)
    check e.lines == @["abc", "def"]
    check e.state.statusMessage == "E1240: Resulting text too long"

  test "a carriage return in a block's row breaks no line and takes no cell":
    let e = newVimLikeEditor(@["abc", "def", "ghi"], 0, 0)
    e.state.registers.storeYanked(none(char), blockRegister(@["x\ry", "zw"], 3))
    for key in keysOf("P"):
      check e.handleKeyCombo(key)
    check e.lines == @["xy abc", "zw def", "ghi"]

  test "a carriage return before a line's break goes with it, as in CRLF":
    let e = newVimLikeEditor(@["abc"], 0, 0)
    check e.state.registers.setRegister('"', "x\r\ny\rz\n", true).isOk
    for key in keysOf("p"):
      check e.handleKeyCombo(key)
    check e.lines == @["abc", "x", "y", "z"]
