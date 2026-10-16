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

## Backspace, Ctrl-W, Ctrl-U and Delete in Insert mode, as Vim's: Ctrl-W and
## Ctrl-U stop once where the typed text starts, and the keys join lines at a
## line's start or end ('backspace' is "indent,eol,start").

import std/[unittest, options, strutils]

import ../src/moepkg/[buffer, types, registers, editor, config, key_bindings]
import ../src/moepkg/handler {.all.}

proc newVimLikeEditor(
    lines: seq[string], line, column: int, autoIndent, expandTab: bool
): Editor =
  ## An editor typing as `vim -u NONE` with `shiftwidth=2` does.
  var config = newEditorConfig()
  config.standard.autoIndent = autoIndent
  config.standard.autoCloseParen = false
  config.standard.autoDeleteParen = false
  config.standard.expandTab = expandTab
  config.standard.tabStop = 8
  config.standard.shiftWidth = 2
  result = newEditor(config)
  # newEditor's registers reach the system clipboard.
  result.state.registers = initRegisters()
  let buffer = newTextBuffer(lines.join("\n") & "\n")
  result.windowManager.windows[0].setTab(buffer)
  result.windowManager.windows[0].bufferIds = @[buffer.id]
  result.windowManager.windows[0].viewport =
    ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
  result.motionController.bindToWindow(result.activeWindow)
  result.state.mode = EditorMode.Normal
  result.activeWindow.cursor = BufferPosition(line: line, column: column)

proc keysOf(spec: string): seq[KeyCombo] =
  ## `<Name>` is one key (`<Escape>`, `<C-u>`), any other character a key.
  var i = 0
  while i < spec.len:
    if spec[i] == '<':
      let close = spec.find('>', i)
      result.add parseKeyCombo(spec[i + 1 ..< close]).get
      i = close + 1
    else:
      result.add KeyCombo(isSpecial: false, char: $spec[i])
      inc i

proc lines(e: Editor): seq[string] =
  for i in 0 ..< e.activeBuffer.len:
    result.add e.activeBuffer.getLine(i)

# Measured in Vim 9.2 (`vim -u NONE`, `set shiftwidth=2`, 'autoindent' and
# 'expandtab' as each case says).
const VimCases = [
  (
    name: "Ctrl-U deletes what was typed and stops where typing started",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "iXY<C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["one two three", "four five six", "seven eight nine"],
    wantCursor: (0, 3),
  ),
  (
    name: "a second Ctrl-U deletes past where typing started",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "iXY<C-u><C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["two three", "four five six", "seven eight nine"],
    wantCursor: (0, 0),
  ),
  (
    name: "once past it, Ctrl-U does not stop there again",
    lines: @["  abc def", "  ghi jkl", "mno"],
    cursor: (0, 6),
    keys: "iXY<C-u><C-u>Z<C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["def", "  ghi jkl", "mno"],
    wantCursor: (0, 0),
  ),
  (
    name: "Ctrl-U right after entering Insert deletes to the line start",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "i<C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["two three", "four five six", "seven eight nine"],
    wantCursor: (0, 0),
  ),
  (
    name: "Ctrl-W stops once where typing started",
    lines: @["  abc def", "  ghi jkl", "mno"],
    cursor: (0, 6),
    keys: "iX Y<C-w><C-w><C-w><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["  def", "  ghi jkl", "mno"],
    wantCursor: (0, 1),
  ),
  (
    name: "Ctrl-W takes punctuation and word characters apart",
    lines: @["foo.bar(baz)", "x"],
    cursor: (0, 8),
    keys: "iX.Y<C-w><C-w><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["foo.bar(Xbaz)", "x"],
    wantCursor: (0, 8),
  ),
  (
    name: "Ctrl-W stops at the start of the typed spaces",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "iXY  <C-w><C-w><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["two three", "four five six", "seven eight nine"],
    wantCursor: (0, 0),
  ),
  (
    name: "after a move left, typing starts again where it is",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "iXY<Left><C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["one Ytwo three", "four five six", "seven eight nine"],
    wantCursor: (0, 3),
  ),
  (
    name: "a move right after typing keeps where Ctrl-U stops",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "iX<Right>Y<C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["one wo three", "four five six", "seven eight nine"],
    wantCursor: (0, 3),
  ),
  (
    name: "past the kept stop, Ctrl-U goes on to the line start",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "iX<Right>Y<C-u><C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["wo three", "four five six", "seven eight nine"],
    wantCursor: (0, 0),
  ),
  (
    name: "typing after a move left starts the typed text there",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "iX<Left><Left>Y<C-u>Z<C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["one Xtwo three", "four five six", "seven eight nine"],
    wantCursor: (0, 2),
  ),
  (
    name: "a move left before typing anything starts the text there",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "i<Left>X<C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["one two three", "four five six", "seven eight nine"],
    wantCursor: (0, 2),
  ),
  (
    name: "Ctrl-U on a line opened by Enter deletes to its start",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "iX<Enter>Y<C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["one X", "two three", "four five six", "seven eight nine"],
    wantCursor: (1, 0),
  ),
  (
    name: "at the start of a line, Ctrl-W joins it to the line above",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "iX<Enter><C-w><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["one Xtwo three", "four five six", "seven eight nine"],
    wantCursor: (0, 4),
  ),
  (
    name: "at the start of a line, Ctrl-U joins it to the line above",
    lines: @["abc", "def"],
    cursor: (1, 0),
    keys: "i<C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["abcdef"],
    wantCursor: (0, 2),
  ),
  (
    name: "joining puts where typing started where the lines meet",
    lines: @["abc", "def"],
    cursor: (1, 0),
    keys: "i<C-u><C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["def"],
    wantCursor: (0, 0),
  ),
  (
    name: "Ctrl-U deletes nothing before the first character",
    lines: @["abc"],
    cursor: (0, 0),
    keys: "i<C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["abc"],
    wantCursor: (0, 0),
  ),
  (
    name: "Ctrl-W deletes nothing before the first character",
    lines: @["abc"],
    cursor: (0, 0),
    keys: "i<C-w><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["abc"],
    wantCursor: (0, 0),
  ),
  (
    name: "Backspace goes past where typing started",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "iXY<Backspace><Backspace><Backspace><C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["two three", "four five six", "seven eight nine"],
    wantCursor: (0, 0),
  ),
  (
    name: "after Backspace joins a line, Ctrl-U stops where the lines met",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (1, 4),
    keys: "I<Backspace><Backspace>XY<C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["one two threXfour five six", "seven eight nine"],
    wantCursor: (0, 12),
  ),
  (
    name: "a stop kept right of where Backspace joins comes back to it",
    lines: @["abc"],
    cursor: (0, 0),
    keys: "Adef<Left><Left>g<Left><Left><Left><Enter><Backspace>XYZ<C-w><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["abcdgef"],
    wantCursor: (0, 1),
  ),
  (
    name: "with autoindent, Ctrl-U keeps the indent",
    lines: @["  abc def", "  ghi jkl", "mno"],
    cursor: (0, 6),
    keys: "oXY<C-u><Escape>",
    autoIndent: true,
    expandTab: false,
    want: @["  abc def", "  ", "  ghi jkl", "mno"],
    wantCursor: (1, 1),
  ),
  (
    name: "with autoindent, a second Ctrl-U deletes the indent",
    lines: @["  abc def", "  ghi jkl", "mno"],
    cursor: (0, 6),
    keys: "oXY<C-u><C-u><Escape>",
    autoIndent: true,
    expandTab: false,
    want: @["  abc def", "", "  ghi jkl", "mno"],
    wantCursor: (1, 0),
  ),
  (
    name: "with autoindent, Ctrl-U keeps the indent of a changed line",
    lines: @["  abc def", "  ghi jkl", "mno"],
    cursor: (0, 6),
    keys: "ccXY<C-u><Escape>",
    autoIndent: true,
    expandTab: false,
    want: @["  ", "  ghi jkl", "mno"],
    wantCursor: (0, 1),
  ),
  (
    name: "on a line `o` opens, typing starts at the line start",
    lines: @["  abc def", "  ghi jkl", "mno"],
    cursor: (0, 6),
    keys: "o z<C-w><C-w>q<Escape>",
    autoIndent: true,
    expandTab: false,
    want: @["  abc def", "q", "  ghi jkl", "mno"],
    wantCursor: (1, 0),
  ),
  (
    name: "on a line `O` opens, typing starts at the line start",
    lines: @["  abc def", "  ghi jkl", "mno"],
    cursor: (0, 6),
    keys: "O  z<C-u><C-u>q<Escape>",
    autoIndent: true,
    expandTab: false,
    want: @["q", "  abc def", "  ghi jkl", "mno"],
    wantCursor: (0, 0),
  ),
  (
    name: "Delete at the end of a line joins the next line",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "AX<End><Delete><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["one two threeXfour five six", "seven eight nine"],
    wantCursor: (0, 13),
  ),
  (
    name: "Delete keeps the indent of the line it joins",
    lines: @["abc", "  def"],
    cursor: (0, 2),
    keys: "A<Delete><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["abc  def"],
    wantCursor: (0, 2),
  ),
  (
    name: "Delete at the end of the last line does nothing",
    lines: @["abc", "def"],
    cursor: (1, 2),
    keys: "A<Delete><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["abc", "def"],
    wantCursor: (1, 2),
  ),
  (
    name: "Ctrl-U after Delete joined stops where typing started",
    lines: @["abc", "def"],
    cursor: (0, 2),
    keys: "AXY<Delete><C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["abcdef"],
    wantCursor: (0, 2),
  ),
  (
    name: "the count types again over the same start",
    lines: @["abc def"],
    cursor: (0, 0),
    keys: "3ifoo<C-u>bar<Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["barabc def"],
    wantCursor: (0, 2),
  ),
  (
    name: "Ctrl-W in the count types again over the same start",
    lines: @["abc def"],
    cursor: (0, 0),
    keys: "3ifoo bar<C-w>baz<Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["foo bazfoo bazfoo bazabc def"],
    wantCursor: (0, 20),
  ),
  (
    name: "after Ctrl-o, typing starts where it is typed",
    lines: @["abc def"],
    cursor: (0, 6),
    keys: "AXY<C-o>hZ<C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["abc defXY"],
    wantCursor: (0, 6),
  ),
  (
    name: "after Ctrl-o, Ctrl-U deletes past where Insert resumed",
    lines: @["abc def"],
    cursor: (0, 4),
    keys: "iXY<C-o>l<C-u><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["ef"],
    wantCursor: (0, 0),
  ),
  (
    name: "after Ctrl-o at the line end, Ctrl-W stops at the last character",
    lines: @["ab cd"],
    cursor: (0, 0),
    keys: "Axy<C-o>l<C-w><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["ab cdx"],
    wantCursor: (0, 5),
  ),
  (
    name: "after Ctrl-o at the line end, typing starts where it is typed",
    lines: @["ab cd"],
    cursor: (0, 0),
    keys: "Axy<C-o>lQ<C-w><Escape>",
    autoIndent: false,
    expandTab: false,
    want: @["ab cdxy"],
    wantCursor: (0, 6),
  ),
  (
    name: "Ctrl-T takes where typing started along with the text",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "iX<C-t><C-u><Escape>",
    autoIndent: false,
    expandTab: true,
    want: @["  one two three", "four five six", "seven eight nine"],
    wantCursor: (0, 5),
  ),
  (
    name: "Ctrl-D takes where typing started along with the text",
    lines: @["  abc def", "  ghi jkl", "mno"],
    cursor: (0, 6),
    keys: "iXY<C-d><C-u><C-u><Escape>",
    autoIndent: false,
    expandTab: true,
    want: @["def", "  ghi jkl", "mno"],
    wantCursor: (0, 0),
  ),
  (
    name: "Ctrl-T with the cursor at the indent starts typing at the line start",
    lines: @["  abc def", "  ghi jkl", "mno"],
    cursor: (0, 2),
    keys: "i<C-t>X<C-u><Escape>",
    autoIndent: false,
    expandTab: true,
    want: @["abc def", "  ghi jkl", "mno"],
    wantCursor: (0, 0),
  ),
  (
    name: "`.` stops Ctrl-W where its insert started",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "iX<C-w>Y<Escape>j.",
    autoIndent: false,
    expandTab: false,
    want: @["one Ytwo three", "fourY five six", "seven eight nine"],
    wantCursor: (1, 4),
  ),
  (
    name: "`.` stops Ctrl-U where its insert started",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "iXY<C-u>Z<Escape>w.",
    autoIndent: false,
    expandTab: false,
    want: @["one Ztwo Zthree", "four five six", "seven eight nine"],
    wantCursor: (0, 9),
  ),
]

suite "Insert Backspace, Ctrl-W, Ctrl-U and Delete, as in Vim":
  for c in VimCases:
    test c.name:
      let e =
        newVimLikeEditor(c.lines, c.cursor[0], c.cursor[1], c.autoIndent, c.expandTab)
      e.state.smartIndent = false
      for key in keysOf(c.keys):
        check e.handleKeyCombo(key)
      check e.lines == c.want
      check (e.activeWindow.cursor.line, e.activeWindow.cursor.column) == c.wantCursor
