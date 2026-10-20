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

## What `.`, `[count]i` and Ctrl-A type again: the keys typed in Insert mode,
## after the command that entered it, as Vim's redo buffer holds them.

import std/[unittest, options, strutils, tables]

import ../src/moepkg/[buffer, types, registers, editor, key_bindings, completion]
import ../src/moepkg/handler {.all.}
import ../src/moepkg/lsp/protocol/types as lspTypes
import vim_like_test_helper

proc press(e: Editor, spec: string) =
  for key in keysOf(spec):
    check e.handleKeyCombo(key)

proc cursorAt(e: Editor): (int, int) =
  (e.activeWindow.cursor.line, e.activeWindow.cursor.column)

const VimCases = [
  (
    name: "i repeats at the cursor",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "ifoo<Escape>j0.",
    want: @["one footwo three", "foofour five six", "seven eight nine"],
    wantCursor: (1, 2),
  ),
  (
    name: "a repeats after the cursor",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "aX<Escape>j.",
    want: @["one tXwo three", "four fXive six", "seven eight nine"],
    wantCursor: (1, 6),
  ),
  (
    name: "A repeats at the line end",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "AX<Escape>j.",
    want: @["one two threeX", "four five sixX", "seven eight nine"],
    wantCursor: (1, 13),
  ),
  (
    name: "I repeats at the first non-blank",
    lines: @["  abc", "  def", "ghi"],
    cursor: (0, 4),
    keys: "IX<Escape>j$.",
    want: @["  Xabc", "  Xdef", "ghi"],
    wantCursor: (1, 2),
  ),
  (
    name: "o opens a line below",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "oX<Escape>j.",
    want: @["one two three", "X", "four five six", "X", "seven eight nine"],
    wantCursor: (3, 0),
  ),
  (
    name: "O opens a line above",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "OX<Escape>j.",
    want: @["X", "X", "one two three", "four five six", "seven eight nine"],
    wantCursor: (1, 0),
  ),
  (
    name: "typing over lines",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "ifoo<Enter>bar<Escape>j0.",
    want: @["one foo", "bartwo three", "foo", "barfour five six", "seven eight nine"],
    wantCursor: (3, 2),
  ),
  (
    name: "cw changes the word there",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "cwX<Escape>w.",
    want: @["one X X", "four five six", "seven eight nine"],
    wantCursor: (0, 6),
  ),
  (
    name: "2cw changes two words there",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "2cwX<Escape>w.",
    want: @["one X", "X six", "seven eight nine"],
    wantCursor: (1, 0),
  ),
  (
    name: "a count to . replaces the change's",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "cwX<Escape>w3.",
    want: @["one X X six", "seven eight nine"],
    wantCursor: (0, 6),
  ),
  (
    name: "s substitutes there",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "sX<Escape>w.",
    want: @["one Xwo Xhree", "four five six", "seven eight nine"],
    wantCursor: (0, 8),
  ),
  (
    name: "S substitutes the line",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "SX<Escape>j.",
    want: @["X", "X", "seven eight nine"],
    wantCursor: (1, 0),
  ),
  (
    name: "cc changes the line",
    lines: @["  abc", "  def", "ghi"],
    cursor: (0, 4),
    keys: "ccX<Escape>j.",
    want: @["X", "X", "ghi"],
    wantCursor: (1, 0),
  ),
  (
    name: "C changes to the end",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "CX<Escape>j.",
    want: @["one X", "fourX", "seven eight nine"],
    wantCursor: (1, 4),
  ),
  (
    name: "Backspace is typed again",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "AXY<Backspace><Escape>j.",
    want: @["one two threeX", "four five sixX", "seven eight nine"],
    wantCursor: (1, 13),
  ),
  (
    name: "a line join is typed again",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (1, 0),
    keys: "i<Backspace>X<Escape>j0.",
    want: @["one two threeXfour five sixXseven eight nine"],
    wantCursor: (0, 27),
  ),
  (
    name: "Delete is typed again",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "i<Delete>X<Escape>j0.",
    want: @["one Xwo three", "Xour five six", "seven eight nine"],
    wantCursor: (1, 0),
  ),
  (
    name: "typing after a move is all . types",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "ifoo<Left>bar<Escape>j0.",
    want: @["one fobarotwo three", "barfour five six", "seven eight nine"],
    wantCursor: (1, 2),
  ),
  (
    name: "a move then Escape keeps the record",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "ifoo<Left><Escape>j0.",
    want: @["one footwo three", "foofour five six", "seven eight nine"],
    wantCursor: (1, 2),
  ),
  (
    name: "typing after a move does not delete again",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "cwfoo<Left>bar<Escape>w.",
    want: @["one fobaro barthree", "four five six", "seven eight nine"],
    wantCursor: (0, 13),
  ),
  (
    name: "Backspace after a move is all . types",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "jAXY<Down><Home><Backspace><Escape>j.",
    want: @["one two three", "four five sixYseven eight nine"],
    wantCursor: (1, 12),
  ),
  (
    name: "End ends the record where the cursor stays",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "AX<End>Y<Escape>j0.",
    want: @["one two threeXY", "Yfour five six", "seven eight nine"],
    wantCursor: (1, 0),
  ),
  (
    name: "an empty insert is what . repeats",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "ifoo<Escape>i<Escape>j.",
    want: @["one footwo three", "four five six", "seven eight nine"],
    wantCursor: (1, 4),
  ),
  (
    name: "3i types it three times",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "3ifoo<Escape>",
    want: @["one foofoofootwo three", "four five six", "seven eight nine"],
    wantCursor: (0, 12),
  ),
  (
    name: "3i's count is repeated by .",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "3ifoo<Escape>j.",
    want: @["one foofoofootwo three", "four five sifoofoofoox", "seven eight nine"],
    wantCursor: (1, 20),
  ),
  (
    name: "a count to . replaces 3i's",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "3ifoo<Escape>j2.",
    want: @["one foofoofootwo three", "four five sifoofoox", "seven eight nine"],
    wantCursor: (1, 17),
  ),
  (
    name: "a count to . repeats an insert",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "ifoo<Escape>3.",
    want: @["one fofoofoofoootwo three", "four five six", "seven eight nine"],
    wantCursor: (0, 14),
  ),
  (
    name: "3o opens three lines",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "3ofoo<Escape>",
    want: @["one two three", "foo", "foo", "foo", "four five six", "seven eight nine"],
    wantCursor: (3, 2),
  ),
  (
    name: "3O opens three lines above",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "3Ofoo<Escape>",
    want: @["foo", "foo", "foo", "one two three", "four five six", "seven eight nine"],
    wantCursor: (2, 2),
  ),
  (
    name: "2o repeats a line break too",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "2ofoo<Enter>bar<Escape>",
    want: @[
      "one two three", "foo", "bar", "foo", "bar", "four five six", "seven eight nine"
    ],
    wantCursor: (4, 2),
  ),
  (
    name: "2i repeats a line break",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "2iX<Enter>Y<Escape>",
    want: @["one X", "YX", "Ytwo three", "four five six", "seven eight nine"],
    wantCursor: (2, 0),
  ),
  (
    name: "a move drops the count",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "3ifoo<Left>bar<Escape>",
    want: @["one fobarotwo three", "four five six", "seven eight nine"],
    wantCursor: (0, 8),
  ),
  (
    name: "a move and Escape drop the count",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "3ifoo<Left><Escape>",
    want: @["one footwo three", "four five six", "seven eight nine"],
    wantCursor: (0, 5),
  ),
  (
    name: "3A appends three times",
    lines: @["  abc", "  def", "ghi"],
    cursor: (0, 0),
    keys: "3AX<Escape>",
    want: @["  abcXXX", "  def", "ghi"],
    wantCursor: (0, 7),
  ),
  (
    name: "3I inserts three times at the first non-blank",
    lines: @["  abc", "  def", "ghi"],
    cursor: (0, 4),
    keys: "3IX<Escape>",
    want: @["  XXXabc", "  def", "ghi"],
    wantCursor: (0, 4),
  ),
  (
    name: "Ctrl-A types the last insert after dd",
    lines: @["one", "two", "three"],
    cursor: (0, 0),
    keys: "ifoo<Escape>0ddi<C-a><Escape>",
    want: @["footwo", "three"],
    wantCursor: (0, 2),
  ),
  (
    name: "Ctrl-A types the keys after a move",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "ifoo<Left>bar<Escape>i<C-a><Escape>",
    want: @["one fobabarrotwo three", "four five six", "seven eight nine"],
    wantCursor: (0, 10),
  ),
  (
    name: "Ctrl-A after cw types what was typed",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "cwfoo<Escape>i<C-a><Escape>",
    want: @["one fofooo three", "four five six", "seven eight nine"],
    wantCursor: (0, 8),
  ),
  (
    name: ". repeats what Ctrl-A typed",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "ifoo<Escape>i<C-a>bar<Escape>j0.",
    want: @["one fofoobarotwo three", "foobarfour five six", "seven eight nine"],
    wantCursor: (1, 5),
  ),
  (
    name: "Ctrl-@ types it and leaves",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "ifoo<Escape>j0i<C-@>",
    want: @["one footwo three", "foofour five six", "seven eight nine"],
    wantCursor: (1, 2),
  ),
  (
    name: "Ctrl-@ after o is what . repeats",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "ifoo<Escape>o<C-@>j.",
    want: @["one footwo three", "foo", "four five six", "foo", "seven eight nine"],
    wantCursor: (3, 2),
  ),
  (
    name: "typing after Ctrl-o is all . types",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "ifoo<C-o>lbar<Escape>j0.",
    want: @["one footbarwo three", "barfour five six", "seven eight nine"],
    wantCursor: (1, 2),
  ),
  (
    name: "nothing typed after Ctrl-o keeps the record",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "ifoo<C-o>l<Escape>j0.",
    want: @["one footwo three", "foofour five six", "seven eight nine"],
    wantCursor: (1, 2),
  ),
  (
    name: "a change Ctrl-o runs is what . repeats",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "ifoo<C-o>x<Escape>j0.",
    want: @["one foowo three", "our five six", "seven eight nine"],
    wantCursor: (1, 0),
  ),
  (
    name: "Ctrl-o drops the count",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 4),
    keys: "3ifoo<C-o>l<Escape>",
    want: @["one footwo three", "four five six", "seven eight nine"],
    wantCursor: (0, 7),
  ),
  (
    name: "Ctrl-y types the character above",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (1, 0),
    keys: "i<C-y><C-y><Escape>j0.",
    want: @["one two three", "onfour five six", "onseven eight nine"],
    wantCursor: (2, 1),
  ),
  (
    name: "Ctrl-e types the character below",
    lines: @["one two three", "four five six", "seven eight nine"],
    cursor: (0, 0),
    keys: "i<C-e><Escape>j0.",
    want: @["fone two three", "ffour five six", "seven eight nine"],
    wantCursor: (1, 0),
  ),
]

suite "`.`, [count]i and Ctrl-A type the keys again, as in Vim":
  # Expected buffers and cursors are measured in Vim 9.2 (`vim -u NONE`,
  # noautoindent, backspace=indent,eol,start).
  for c in VimCases:
    test c.name & ": " & c.keys:
      let e = newVimLikeEditor(c.lines, c.cursor[0], c.cursor[1])
      e.press(c.keys)
      check e.state.mode == EditorMode.Normal
      check e.lines == c.want
      check e.cursorAt == c.wantCursor

suite "what else Insert mode types again":
  test "a paste is put in again as it came, with no indent added":
    let e = newVimLikeEditor(@["  one", "  two"], 0, 0)
    e.state.autoIndent = true
    e.press("A")
    check e.handlePaste("x\ny")
    e.press("<Escape>j.")
    check e.lines == @["  onex", "y", "  twox", "y"]

  test "a completion is put in again by its text":
    let e = newVimLikeEditor(@["foobar", "", ""], 1, 0)
    e.press("ifo<C-n><Tab><Escape>j0.")
    check e.lines == @["foobar", "foobar", "foobar"]

  test "the count of [count]i is typed before an Insert mapping's command":
    let e = newVimLikeEditor(@[""], 0, 0)
    check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Insert, "K", "bnext") == ""
    e.press("3ixK")
    check e.state.mode == EditorMode.Normal
    check e.lines == @["xxx"]

  test "a repeat is one undo step, the count's repeats with it":
    let e = newVimLikeEditor(@["abc"], 0, 0)
    e.press("3ix<Escape>0.")
    check e.lines == @["xxxxxxabc"]
    e.press("u")
    check e.lines == @["xxxabc"]
    e.press("u")
    check e.lines == @["abc"]

  test "a repeat onto a closed fold opens it to type there":
    let e = newVimLikeEditor(@["tail", "aaa", "bbb", "ccc"], 0, 0)
    check e.activeBuffer.foldState.addFold(1, 3, collapsed = true)
    e.press("iX<Escape>j0.")
    check e.lines[1] == "Xaaa"
    check not e.activeBuffer.foldState.folds[0].collapsed

  test "a macro records `.`, not the keys it types":
    let e = newVimLikeEditor(@["abc", "def"], 0, 0)
    e.press("iX<Escape>qaj0.q")
    check e.state.pendingInput.macroState.registers['a'] == @["j", "0", "."]

  test "keys an Insert mapping types are typed again, unmapped":
    let e = newVimLikeEditor(@["abc", "def"], 0, 0)
    check e.keyBindingRegistry.addRuntimeMapping(
      EditorMode.Insert, ",,", "xy", noremap = true
    ) == ""
    check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Insert, "x", "Q") == ""
    e.press("i,,<Escape>j0.")
    check e.lines == @["xyabc", "xydef"]

  test "Ctrl-A types the keys it repeats into what `.` repeats":
    let e = newVimLikeEditor(@["abc", "def", "ghi"], 0, 0)
    e.press("i(<Escape>ji<C-a>)<Escape>j0.")
    check e.lines == @["(abc", "()def", "()ghi"]

  test "a change repeats into the register it named, as in Vim":
    for (keys, want, wantRegister) in [
      ("\"acwX<Escape>w.", @["X X three", "four five six"], "two"),
      ("\"asX<Escape>w.", @["Xne Xwo three", "four five six"], "t"),
      ("\"aSX<Escape>j.", @["X", "X"], "four five six\n"),
    ]:
      let e = newVimLikeEditor(@["one two three", "four five six"], 0, 0)
      e.press(keys)
      check e.lines == want
      check e.state.registers.getRegisterContent('a') == wantRegister
      check e.state.registers.getRegisterContent('"') == wantRegister

  test "cgn and `.` change the next matches, as in Vim":
    let e = newVimLikeEditor(@["foo bar foo baz", "x foo y foo"], 0, 0)
    e.press("/foo<Enter>cgnX<Escape>..")
    check e.lines == @["foo bar X baz", "x X y X"]
    check e.cursorAt == (1, 6)

  test "C and D keep the top line they start from, as the operators do":
    for keys in ["Cx<Escape>", "2Cx<Escape>", "Cx<Escape>j0.", "D"]:
      var lines: seq[string]
      for i in 0 ..< 1000:
        lines.add "word word"
      let e = newVimLikeEditor(lines, 0, 0)
      e.press("dw")
      e.activeWindow.viewport.topLine = 500
      e.activeWindow.cursor = BufferPosition(line: 510, column: 0)
      e.press(keys)
      check e.activeWindow.viewport.topLine == 500

suite "Enter on a line with only its auto-indent removes it, as in Vim":
  for (keys, want) in [
    ("o<Enter><Escape>", @["    foo()", "", ""]),
    ("o<Enter>x<Escape>", @["    foo()", "", "    x"]),
    ("o<Enter><Enter><Escape>", @["    foo()", "", "", ""]),
    ("ofoo<Enter><Escape>", @["    foo()", "    foo", ""]),
    ("Ox<Enter><Enter><Escape>", @["    x", "", "", "    foo()"]),
    ("3o<Escape>", @["    foo()", "", "", ""]),
    # Typing on the line keeps its indent, even what is deleted again.
    ("ox<Backspace><Enter><Escape>", @["    foo()", "    ", ""]),
    ("ox<Backspace><Escape>", @["    foo()", "    "]),
  ]:
    test keys:
      let e = newVimLikeEditor(@["    foo()"], 0, 4)
      e.state.autoIndent = true
      e.state.smartIndent = false
      e.press(keys)
      check e.lines == want

suite "Ctrl-A and Ctrl-@ before anything was inserted":
  test "Ctrl-A reports E29 and stays in Insert":
    let e = newVimLikeEditor(@["abc"], 0, 0)
    e.press("i<C-a>")
    check e.state.mode == EditorMode.Insert
    check e.state.statusMessage == "E29: No inserted text yet"
    check e.lines == @["abc"]

  test "Ctrl-@ reports E29 and leaves Insert":
    let e = newVimLikeEditor(@["abc"], 0, 0)
    e.press("i<C-@>")
    check e.state.mode == EditorMode.Normal
    check e.state.statusMessage == "E29: No inserted text yet"

  test "Ctrl-@ with a count reports E29 too":
    let e = newVimLikeEditor(@["abc"], 0, 0)
    e.press("3i<C-@>")
    check e.state.mode == EditorMode.Normal
    check e.state.statusMessage == "E29: No inserted text yet"

  test "an empty insert is something inserted":
    let e = newVimLikeEditor(@["abc"], 0, 0)
    e.press("i<Escape>o<C-a>x<Escape>")
    check e.lines == @["abc", "x"]
    check e.state.statusMessage != "E29: No inserted text yet"

  test "typing over a snippet's default is typed again over it":
    let e = newVimLikeEditor(@["    xx", "    xx"], 0, 0)
    e.press("A")
    let completion = e.handlerManager.insertHandler.completionManager
    completion.menu.entries = @[
      CompletionEntry(
        word: "x",
        matchScore: 100,
        source: csLsp,
        isSnippet: true,
        textEdit: some(
          TextEdit(
            range: Range(
              start: lspTypes.Position(line: 0, character: 4),
              `end`: lspTypes.Position(line: 0, character: 6),
            ),
            newText: "f(${1:arg}, ${2:n})",
          )
        ),
      )
    ]
    completion.menu.prefix = "xx"
    completion.menu.selectedIndex = 0
    completion.menu.hasSelection = true
    completion.state = csActive
    e.press("<Enter>y<Escape>j.")
    check e.lines == @["    f(y, n)", "    f(y, n)"]

suite "a count given to `.` replaces the change's own, as in Vim":
  # Measured in Vim 9.2 (`vim -u NONE`).
  for (keys, want, wantCursor) in [
    ("dw3.", @["five six", "a b c", "d e f", "g h i", "j k l"], (0, 0)),
    ("d2w3.", @["six", "a b c", "d e f", "g h i", "j k l"], (0, 0)),
    ("x3.", @["two three four five six", "a b c", "d e f", "g h i", "j k l"], (0, 0)),
    ("dd2.", @["g h i", "j k l"], (0, 0)),
    ("2dd.", @["j k l"], (0, 0)),
    (
      "rx3.",
      @["xxx two three four five six", "a b c", "d e f", "g h i", "j k l"],
      (0, 2),
    ),
    (
      "~3.",
      @["ONE two three four five six", "a b c", "d e f", "g h i", "j k l"],
      (0, 4),
    ),
  ]:
    test keys:
      let e = newVimLikeEditor(
        @["one two three four five six", "a b c", "d e f", "g h i", "j k l"], 0, 0
      )
      e.press(keys)
      check e.lines == want
      check e.cursorAt == wantCursor

  test "yyp2.":
    # Lines only: a counted linewise put leaves the cursor on the last line
    # put, where Vim leaves it on the first (`2p` too).
    let e = newVimLikeEditor(@["one", "a b c"], 0, 0)
    e.press("yyp2.")
    check e.lines == @["one", "one", "one", "one", "a b c"]

  test "the next `.` keeps the count":
    let e = newVimLikeEditor(@["a b c d e f g h"], 0, 0)
    e.press("dw2..")
    check e.lines == @["f g h"]

suite "`.` after Ctrl-o resumes Insert, as in Vim":
  # Measured in Vim 9.2 (`vim -u NONE`, typed through a terminal). What was
  # typed before Ctrl-o, unless a move ended it, is the change still under
  # way, so `.` repeats the one before it.
  for (keys, lines, want, wantCursor) in [
    ("ifoo<Escape>A<C-o>.X<Escape>", @["abc def"], @["fooabc defoXof"], (0, 11)),
    ("ifoo<Escape>Abar<C-o>.X<Escape>", @["abc def"], @["fooabc defbafoXor"], (0, 14)),
    ("ifoo<Left><C-o>.X<Escape>", @["abc def"], @["fofoXooabc def"], (0, 4)),
    (
      "ifoo<Escape>Abar<Left>baz<C-o>.X<Escape>",
      @["abc def"],
      @["fooabc defbabazrbaXr"],
      (0, 18),
    ),
    (
      "ifoo<Escape>A<C-o>.<C-o>.X<Escape>",
      @["abc def"],
      @["fooabc defofoXoof"],
      (0, 13),
    ),
    ("ifoo<Escape>Abar<C-o>l<Escape>0.", @["abc def"], @["fooabc defbarbar"], (0, 15)),
    (
      "3ifoo<Escape>A<C-o>.X<Escape>",
      @["abc def"],
      @["foofoofooabc defoofoofoXof"],
      (0, 23),
    ),
    ("ifoo<Escape>A<C-o>2.X<Escape>", @["abc def"], @["fooabc defoofoXof"], (0, 14)),
    ("dwjA<C-o>.X<Escape>", @["abc def", "ghi"], @["def", "ghX"], (1, 2)),
    ("dwA<C-o>0<C-o>.X<Escape>", @["abc def ghi"], @["def ghXi"], (0, 6)),
    ("A<C-o>.X<Escape>", @["abc def"], @["abc defX"], (0, 7)),
  ]:
    test keys:
      let e = newVimLikeEditor(lines, 0, 0)
      e.press(keys)
      check e.lines == want
      check e.cursorAt == wantCursor
      check e.state.mode == EditorMode.Normal

suite "the count of o and O opens each line after what was typed":
  # Pairs closed as typed leave the cursor before the closing one, so the
  # line goes after them, not where the cursor is.
  for (keys, want) in [
    ("2ofoo(<Escape>", @["abc", "foo()", "foo()", "def"]),
    ("2Ofoo(<Escape>", @["foo()", "foo()", "abc", "def"]),
    ("3ofoo(<Escape>", @["abc", "foo()", "foo()", "foo()", "def"]),
    ("2ofoo(<Enter>bar<Escape>", @["abc", "foo(", "bar)", "foo(", "bar)", "def"]),
    ("ofoo(<Escape>j.", @["abc", "foo()", "def", "foo()"]),
  ]:
    test keys:
      let e = newVimLikeEditor(@["abc", "def"], 0, 0)
      e.state.autoCloseParen = true
      e.press(keys)
      check e.lines == want

suite "a move ends the auto-indent nothing was typed after, as in Vim":
  # Measured in Vim 9.2 (`vim -u NONE`, `set autoindent`, typed through a
  # terminal): moving off the line takes the indent off at once, and moving
  # on it keeps the indent past Escape.
  for (keys, want, wantCursor) in [
    ("o<Up>x<Escape>", @["    xfoo", "", "bar"], (0, 4)),
    ("o<Up><Escape>", @["    foo", "", "bar"], (0, 3)),
    ("o<Up><Down><Escape>", @["    foo", "", "bar"], (1, 0)),
    ("o<Up><Down>x<Escape>", @["    foo", "x", "bar"], (1, 0)),
    ("o<Left><Escape>", @["    foo", "    ", "bar"], (1, 2)),
    ("o<Left><Right>x<Escape>", @["    foo", "    x", "bar"], (1, 4)),
    ("ox<Backspace><Up><Escape>", @["    foo", "    ", "bar"], (0, 3)),
  ]:
    test keys:
      let e = newVimLikeEditor(@["    foo", "bar"], 0, 4)
      e.state.autoIndent = true
      e.state.smartIndent = false
      e.press(keys)
      check e.lines == want
      check e.cursorAt == wantCursor

suite "the indent a linewise change keeps comes off when nothing is typed":
  for (keys, want, wantCursor) in [
    ("cc<Escape>", @["", "  bar", "baz"], (0, 0)),
    ("ccx<Escape>", @["    x", "  bar", "baz"], (0, 4)),
    ("S<Escape>", @["", "  bar", "baz"], (0, 0)),
    ("cj<Escape>", @["", "baz"], (0, 0)),
    ("Vjc<Escape>", @["", "baz"], (0, 0)),
    ("Vjcx<Escape>", @["    x", "baz"], (0, 4)),
  ]:
    test keys:
      let e = newVimLikeEditor(@["    foo", "  bar", "baz"], 0, 4)
      e.state.autoIndent = true
      e.state.smartIndent = false
      e.press(keys)
      check e.lines == want
      check e.cursorAt == wantCursor

suite "one undo takes back a change and what was typed, as in Vim":
  # Measured in Vim 9.2 (`vim -u NONE`, `set ai`, typed through a terminal).
  for (keys, wantCursor) in [
    ("ccx<Escape>u", (0, 4)),
    ("cbx<Escape>u", (0, 8)),
    ("sx<Escape>u", (0, 9)),
    ("Sx<Escape>u", (0, 4)),
    ("vhcx<Escape>u", (0, 8)),
    ("Vcx<Escape>u", (0, 0)),
  ]:
    test keys:
      let e = newVimLikeEditor(@["    foo bar", "  bar", "baz"], 0, 9)
      e.state.autoIndent = true
      e.state.smartIndent = false
      e.press(keys)
      check e.lines == @["    foo bar", "  bar", "baz"]
      check e.cursorAt == wantCursor

  test "<C-v>jlcx<Escape>u":
    let e = newVimLikeEditor(@["    foo", "  bar", "baz"], 0, 4)
    e.press("<C-v>jlcx<Escape>u")
    check e.lines == @["    foo", "  bar", "baz"]
    check e.cursorAt == (0, 4)

  # Vim puts the cursor on the second line after undoing a change over two
  # lines; the first line, where the change started, is kept here.
  for keys in ["cjx<Escape>u", "2Sx<Escape>u", "Vjc<Escape>u", "Vjcx<Escape>u"]:
    test keys:
      let e = newVimLikeEditor(@["    foo", "  bar", "baz"], 0, 4)
      e.state.autoIndent = true
      e.state.smartIndent = false
      e.press(keys)
      check e.lines == @["    foo", "  bar", "baz"]
      check e.cursorAt[0] == 0

suite "g; goes to where a change was typed, as in Vim":
  # Measured in Vim 9.2 (`vim -u NONE`, `set ai`, typed through a terminal).
  for (keys, wantCursor) in [
    ("ccxyz<Escape>Gg;", (0, 4)),
    ("cc<Escape>Gg;", (0, 0)),
    ("cj<Escape>Gg;", (0, 0)),
    ("2Sxy<Escape>Gg;", (0, 4)),
    ("sxy<Escape>Gg;", (0, 4)),
    ("Vjc<Escape>Gg;", (0, 0)),
    ("Vjcx<Escape>Gg;", (0, 4)),
    ("vlcxy<Escape>Gg;", (0, 4)),
  ]:
    test keys:
      let e = newVimLikeEditor(@["    foo", "  bar", "baz"], 0, 4)
      e.state.autoIndent = true
      e.state.smartIndent = false
      e.press(keys)
      check e.cursorAt == wantCursor

suite "the text Enter carries down, as in Vim":
  # Measured in Vim 9.2 (`vim -u NONE`, typed through a terminal). With
  # autoindent the new line takes the indent of the text before the cursor and
  # drops the blanks it carries. The indent stays untouched until something is
  # typed: Escape or a move keeps it before carried text, and the next Enter
  # takes it off the line it leaves.
  const
    Words = @["  abc def", "  ghi"]
    Deep = @["    abc", "x"]
    Trail = @["  abc   ", "x"]
  for (lines, column, keys, want, wantCursor) in [
    (Words, 6, "i<Enter><Escape>", @["  abc ", "  def", "  ghi"], (1, 1)),
    (Words, 6, "i<Enter><Enter><Escape>", @["  abc ", "", "  def", "  ghi"], (2, 1)),
    (Words, 6, "i<Enter><Enter>Y<Escape>", @["  abc ", "", "  Ydef", "  ghi"], (2, 2)),
    (Words, 6, "iX<Enter><Up><Escape>", @["  abc X", "  def", "  ghi"], (0, 1)),
    (Words, 6, "iX<Enter><Down><Escape>", @["  abc X", "  def", "  ghi"], (2, 1)),
    (Words, 6, "a<Enter><Escape>", @["  abc d", "  ef", "  ghi"], (1, 1)),
    (
      Words,
      6,
      "i<Enter><Left><Enter><Escape>",
      @["  abc ", " ", " def", "  ghi"],
      (2, 0),
    ),
    (Words, 6, "i<Enter><Escape>j.", @["  abc ", "  def", " ", " ghi"], (3, 0)),
    (Words, 5, "i<Enter><Escape>", @["  abc", "  def", "  ghi"], (1, 1)),
    (Deep, 2, "i<Enter><Escape>", @["  ", "  abc", "x"], (1, 1)),
    (Deep, 0, "i<Enter><Escape>", @["", "abc", "x"], (1, 0)),
    (Deep, 2, "i<Enter><Enter><Escape>", @["  ", "", "  abc", "x"], (2, 1)),
    (Trail, 5, "i<Enter><Escape>", @["  abc", "", "x"], (1, 0)),
    (Trail, 5, "i<Enter><Enter><Escape>", @["  abc", "", "", "x"], (2, 0)),
    (Trail, 5, "i<Enter><Up><Escape>", @["  abc", "", "x"], (0, 1)),
    (@["\tabc \tdef", "x"], 4, "i<Enter><Escape>", @["\tabc", "\tdef", "x"], (1, 0)),
    (@["abc def"], 3, "i<Enter><Escape>", @["abc", "def"], (1, 0)),
    (@["    foo", "bar"], 4, "o<Enter><Escape>", @["    foo", "", "", "bar"], (2, 0)),
  ]:
    test keys & " at " & $column & " of " & $lines:
      let e = newVimLikeEditor(lines, 0, column)
      e.state.autoIndent = true
      e.state.smartIndent = false
      e.press(keys)
      check e.lines == want
      check e.cursorAt == wantCursor

  # Without autoindent the blanks go down as they are.
  for (lines, column, want) in [
    (Words, 5, @["  abc", " def", "  ghi"]), (@["abc def"], 3, @["abc", " def"])
  ]:
    test "i<Enter><Escape> at " & $column & " of " & $lines & " without autoindent":
      let e = newVimLikeEditor(lines, 0, column)
      e.press("i<Enter><Escape>")
      check e.lines == want
      check e.cursorAt == (1, 0)

suite "what completion and snippets leave for `.`":
  proc offer(e: Editor, words: openArray[string], prefix: string) =
    let completion = e.handlerManager.insertHandler.completionManager
    completion.menu.entries = @[]
    for word in words:
      completion.menu.entries.add CompletionEntry(
        word: word, matchScore: 100, source: csBuffer
      )
    completion.menu.prefix = prefix
    completion.menu.selectedIndex = 0
    completion.menu.hasSelection = false
    completion.state = csActive

  test "cycling through candidates records the last one alone":
    let e = newVimLikeEditor(@["fo", "fo"], 0, 0)
    e.press("A")
    e.offer(["foo", "fob", "fox"], "fo")
    e.press("<Down><Down><Down><Escape>")
    check e.lines[0] == "fox"
    check e.state.editState.insertRecord.typed.len == 1
    e.press("j.")
    check e.lines == @["fox", "fox"]

  test "typing over a snippet default after Tab does not delete at `.`":
    let e = newVimLikeEditor(@["    xx", "abcdef"], 0, 0)
    e.press("A")
    let completion = e.handlerManager.insertHandler.completionManager
    completion.menu.entries = @[
      CompletionEntry(
        word: "x",
        matchScore: 100,
        source: csLsp,
        isSnippet: true,
        textEdit: some(
          TextEdit(
            range: Range(
              start: lspTypes.Position(line: 0, character: 4),
              `end`: lspTypes.Position(line: 0, character: 6),
            ),
            newText: "f(${1:arg}, ${2:len})",
          )
        ),
      )
    ]
    completion.menu.prefix = "xx"
    completion.menu.selectedIndex = 0
    completion.menu.hasSelection = true
    completion.state = csActive
    e.press("<Enter>y<Tab>n<Escape>")
    check e.lines[0] == "    f(y, n)"
    e.activeWindow.cursor = BufferPosition(line: 1, column: 3)
    e.press(".")
    check e.lines == @["    f(y, n)", "abcndef"]

suite "a change no key recorded ends what `.` repeats":
  test "a completion whose other edits went in partly":
    # The import goes in, the edit after it fails, and the completion is
    # aborted: typing again could not do that, so `.` repeats what comes after.
    let e = newVimLikeEditor(@["fo", "zzz", "ab"], 0, 0)
    e.press("A")
    let completion = e.handlerManager.insertHandler.completionManager
    completion.menu.entries = @[
      CompletionEntry(
        word: "foo",
        matchScore: 100,
        source: csLsp,
        additionalTextEdits: some(
          @[
            TextEdit(
              range: Range(
                start: lspTypes.Position(line: 1, character: 0),
                `end`: lspTypes.Position(line: 1, character: 0),
              ),
              newText: "import x\n",
            ),
            TextEdit(
              range: Range(
                start: lspTypes.Position(line: 0, character: 50),
                `end`: lspTypes.Position(line: 0, character: 60),
              ),
              newText: "",
            ),
          ]
        ),
      )
    ]
    completion.menu.prefix = "fo"
    completion.menu.selectedIndex = 0
    completion.menu.hasSelection = true
    completion.state = csActive
    e.press("<Enter>")
    check e.state.statusMessage.endsWith("(completion aborted)")
    check e.lines == @["fo", "import x", "zzz", "ab"]
    e.press("x<Escape>")
    check e.lines[0] == "fox"
    e.activeWindow.cursor = BufferPosition(line: 3, column: 0)
    e.press(".")
    check e.lines[3] == "xab"
