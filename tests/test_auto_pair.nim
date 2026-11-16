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

## Brackets and quotes typed with `autoCloseParen`: closed as typed, stepped
## over when typed again, as mini.pairs does, and typed again by `.` as Vim
## types a plugin's <C-g>U moves again.

import std/[unittest, options, sequtils]
import pkg/results

import
  ../src/moepkg/
    [auto_pair, buffer, types, editor, editor_mode, key_bindings, completion]
import ../src/moepkg/syntax/tokenizer
import ../src/moepkg/handler {.all.}
import ../src/moepkg/lsp/protocol/types as lspTypes
import vim_like_test_helper

proc press(e: Editor, spec: string) =
  for key in keysOf(spec):
    check e.handleKeyCombo(key)

proc cursorAt(e: Editor): (int, int) =
  (e.activeWindow.cursor.line, e.activeWindow.cursor.column)

proc pairing(lines: seq[string], line, column: int): Editor =
  result = newVimLikeEditor(lines, line, column)
  result.state.autoCloseParen = true

proc typedKinds(e: Editor): seq[TypedInputKind] =
  e.state.editState.insertRecord.typed.mapIt(it.kind)

proc offer(e: Editor, words: openArray[string], prefix: string, selected: bool) =
  let completion = e.handlerManager.insertHandler.completionManager
  completion.menu.entries = @[]
  for word in words:
    completion.menu.entries.add CompletionEntry(
      word: word, matchScore: 100, source: csBuffer
    )
  completion.menu.prefix = prefix
  completion.menu.triggerLine = e.activeWindow.cursor.line
  completion.menu.triggerCol = e.activeWindow.cursor.column - prefix.len
  completion.menu.selectedIndex = 0
  completion.menu.hasSelection = selected
  completion.state = csActive

proc offerSnippet(e: Editor, body: string) =
  ## A snippet that replaces the `xx` at columns 4 to 6 of line 0.
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
          newText: body,
        )
      ),
    )
  ]
  completion.menu.prefix = "xx"
  completion.menu.selectedIndex = 0
  completion.menu.hasSelection = true
  completion.state = csActive

suite "autoPairAction: the characters on either side of the cursor":
  for (line, column, typed, want) in [
    ("", 0, "(", apPair),
    ("", 0, "[", apPair),
    ("", 0, "{", apPair),
    ("", 0, "\"", apPair),
    ("", 0, "'", apPair),
    ("", 0, ")", apInsert),
    ("", 0, "]", apInsert),
    ("", 0, "}", apInsert),
    ("", 0, "x", apNone),
    ("", 0, "()", apNone),
    ("()", 1, ")", apStepOver),
    ("[]", 1, "]", apStepOver),
    ("{}", 1, "}", apStepOver),
    ("\"\"", 1, "\"", apStepOver),
    ("''", 1, "'", apStepOver),
    ("(]", 1, ")", apInsert), # Another closing character on the right
    ("()", 1, "]", apInsert),
    ("x)", 0, ")", apInsert), # Not the character on the right
    ("foo", 0, "(", apPair), # Before a word too
    ("foo", 3, "(", apPair),
    ("\\", 1, "(", apInsert),
    ("\\", 1, "\"", apInsert),
    ("\\)", 1, ")", apInsert),
    ("\"a\\\"", 3, "\"", apInsert), # An escaped quote in a string
    ("\"a\\\\\"", 4, "\"", apStepOver), # An escaped backslash escapes nothing
    ("(\\\\)", 3, ")", apStepOver),
    ("\\\\", 2, "(", apPair),
    ("\\\\\\", 3, "\"", apInsert), # The third one escapes
    ("don", 3, "'", apInsert),
    ("x1", 2, "'", apInsert),
    ("foo_", 4, "'", apInsert),
    ("日本", 2, "'", apInsert), # A word character of more than one byte
    ("a ", 2, "'", apPair),
    ("(", 1, "'", apPair),
    ("don", 3, "\"", apPair), # Only the single quote
    ("don'", 3, "'", apStepOver), # The step over comes first
    ("é", 2, "'", apInsert), # The character a composing one is part of
    ("()\u0301", 1, ")", apStepOver), # A composing character on the right one
    ("a)", 5, ")", apInsert), # Past the end
  ]:
    test line & " at " & $column & " typing " & typed:
      check autoPairAction(line, column, typed, langNone) == want

suite "autoPairAction: a single quote after a Python string prefix":
  for (line, column, language, want) in [
    ("x = f", 5, langPython, apPair),
    ("r", 1, langPython, apPair),
    ("u", 1, langPython, apPair),
    ("b", 1, langPython, apPair),
    ("t", 1, langPython, apPair), # A template string (Python 3.14)
    ("rb", 2, langPython, apPair),
    ("Rb", 2, langPython, apPair),
    ("FR", 2, langPython, apPair),
    ("rt", 2, langPython, apPair),
    ("(f", 2, langPython, apPair),
    ("ur", 2, langPython, apInsert), # No prefix in Python 3
    ("fb", 2, langPython, apInsert),
    ("rr", 2, langPython, apInsert),
    ("if", 2, langPython, apInsert), # A word ending in one
    ("# your", 6, langPython, apInsert),
    ("_f", 2, langPython, apInsert),
    ("f1", 2, langPython, apInsert),
    ("f", 1, langNone, apInsert), # Only in Python
    ("f", 1, langNim, apInsert),
    ("f'", 1, langPython, apStepOver),
  ]:
    test line & " at " & $column & " in " & $language:
      check autoPairAction(line, column, "'", language) == want

# Derived from the rules, the cursor still in Insert.
const TypingCases = [
  (lines: @[""], column: 0, keys: "i()", want: @["()"], cursor: (0, 2)),
  (lines: @[""], column: 0, keys: "i\"\"", want: @["\"\""], cursor: (0, 2)),
  (lines: @[""], column: 0, keys: "i''", want: @["''"], cursor: (0, 2)),
  (lines: @[""], column: 0, keys: "idon't", want: @["don't"], cursor: (0, 5)),
  (lines: @[""], column: 0, keys: "ifoo(bar)", want: @["foo(bar)"], cursor: (0, 8)),
  (lines: @[""], column: 0, keys: "i'abc'", want: @["'abc'"], cursor: (0, 5)),
  (lines: @[""], column: 0, keys: "i(a))", want: @["(a))"], cursor: (0, 4)),
  (lines: @[""], column: 0, keys: "i((x)", want: @["((x))"], cursor: (0, 4)),
  (lines: @[""], column: 0, keys: "ia\\\"", want: @["a\\\""], cursor: (0, 3)),
  (lines: @[""], column: 0, keys: "i\\(", want: @["\\("], cursor: (0, 2)),
  (lines: @[""], column: 0, keys: "i\"a\\\"", want: @["\"a\\\"\""], cursor: (0, 4)),
  (lines: @[""], column: 0, keys: "i\"a\\\\\"", want: @["\"a\\\\\""], cursor: (0, 5)),
  (lines: @[""], column: 0, keys: "i\"\"\"", want: @["\"\"\"\""], cursor: (0, 3)),
  (lines: @["foo"], column: 0, keys: "i(", want: @["()foo"], cursor: (0, 1)),
  (lines: @["[]"], column: 1, keys: "i]", want: @["[]"], cursor: (0, 2)),
  (lines: @["{}"], column: 1, keys: "i}", want: @["{}"], cursor: (0, 2)),
]

suite "a closing character typed before the same one steps over it":
  for c in TypingCases:
    test c.keys & " on " & $c.lines:
      let e = pairing(c.lines, 0, c.column)
      e.press(c.keys)
      check e.state.mode == EditorMode.Insert
      check e.lines == c.want
      check e.cursorAt == c.cursor

suite "a Python string prefix opens a pair":
  for (language, keys, want) in [
    (langPython, "ix = f'{x}'", "x = f'{x}'"),
    (langPython, "ip = rb'\\d+'", "p = rb'\\d+'"),
    (langPython, "i# your'", "# your'"),
    # Elsewhere the prefix's quote goes in as typed, so the last one opens.
    (langNone, "ix = f'{x}'", "x = f'{x}''"),
  ]:
    test keys & " in " & $language:
      let e = pairing(@[""], 0, 0)
      e.activeBuffer.language = language
      e.press(keys)
      check e.lines == @[want]

# Measured in Vim 9.2 and Neovim 0.12.6 with mappings shaped as mini.pairs's:
# `( ()<C-g>U<Left>`, an `<expr> )` that steps over a `)` on the right with
# `<C-g>U<Right>`, and an `<expr> '` that judges as mini.pairs's closeopen.
const VimCases = [
  (
    name: "`.` types the pair and the step over again",
    lines: @["", ""],
    cursor: (0, 0),
    keys: "i(x)<Escape>j0.",
    want: @["(x)", "(x)"],
  ),
  (
    name: "Ctrl-U deletes to where Insert started",
    lines: @[""],
    cursor: (0, 0),
    keys: "ifoo(x)y<C-u>",
    want: @[""],
  ),
  (
    name: "a step over does not move where Insert started",
    lines: @["()"],
    cursor: (0, 1),
    keys: "i)y<C-u>",
    want: @["("],
  ),
  (
    name: "a step over is no change, so an arrow after it moves where Ctrl-U stops",
    lines: @["()a"],
    cursor: (0, 1),
    keys: "i)<Right>y<C-u>",
    want: @["()a"],
  ),
  (
    name: "a step over after an arrow is not recorded",
    lines: @["", "ab"],
    cursor: (0, 0),
    keys: "i(x<Left><Right>)y<Escape>j0.",
    want: @["(x)y", "yab"],
  ),
  (
    name: "undo takes the pair and the step over back at once",
    lines: @[""],
    cursor: (0, 0),
    keys: "i(x)<Escape>u",
    want: @[""],
  ),
  (
    name: "the count types the pair again",
    lines: @[""],
    cursor: (0, 0),
    keys: "3i(<Escape>",
    want: @["((()))"],
  ),
  (
    name: "the count types the step over again",
    lines: @[""],
    cursor: (0, 0),
    keys: "3i(x)<Escape>",
    want: @["(x)(x)(x)"],
  ),
  (
    name: "the count of o types the step over again",
    lines: @[""],
    cursor: (0, 0),
    keys: "2o(x)<Escape>",
    want: @["", "(x)", "(x)"],
  ),
  (
    name: "a quote put in as typed is typed again as it is",
    lines: @["don", "a "],
    cursor: (0, 0),
    keys: "A'<Escape>j.",
    want: @["don'", "a '"],
  ),
  (
    name: "a step over Ctrl-A types stays in what `.` repeats",
    lines: @["", ""],
    cursor: (0, 0),
    keys: "i(x)<Escape>jo<C-a>y<Escape>.",
    want: @["(x)", "", "(x)y", "(x)y"],
  ),
  (
    name: "a step over Ctrl-A types at the line end is not recorded",
    lines: @["()", "ab", "cd"],
    cursor: (0, 1),
    keys: "i)<Escape>j$a<C-a>y<Escape>j0.",
    want: @["()", "aby", "cyd"],
  ),
  (
    name: "a step over Ctrl-A types where it can move is recorded",
    lines: @["()", "ab", "cd"],
    cursor: (0, 1),
    keys: "i)<Escape>j0a<C-a>y<Escape>j0.",
    want: @["()", "aby", "cdy"],
  ),
  (
    name: "a step over goes past the composing characters on what it steps over",
    lines: @["()\u0301"],
    cursor: (0, 1),
    keys: "i)z<Escape>",
    want: @["()\u0301z"],
  ),
  (
    name: "`.` steps over the composing characters too",
    lines: @["()", "a)\u0301b"],
    cursor: (0, 1),
    keys: "i)y<Escape>j0l.",
    want: @["()y", "a)\u0301yb"],
  ),
  (
    name: "a Visual-block insert copies the text to every line",
    lines: @["ab", "cd"],
    cursor: (0, 0),
    keys: "<C-v>jI(x)<Escape>",
    want: @["(x)ab", "(x)cd"],
  ),
]

suite "`.`, the count, Ctrl-A, Ctrl-U and undo, as in Vim with a pair plugin":
  for c in VimCases:
    test c.name:
      let e = pairing(c.lines, c.cursor[0], c.cursor[1])
      e.press(c.keys)
      check e.lines == c.want

  test "after an arrow, a step over and Escape, `.` repeats what came before":
    # Vim differs: the <C-g>U<Right> left after its Escape takes the repeat
    # back, so the second line stays `ab` there.
    let e = pairing(@["", "ab"], 0, 0)
    e.press("i(x<Left><Right>)<Escape>j0.")
    check e.lines == @["(x)", "(x)ab"]

suite "what the record takes of a step over":
  test "the pair, the key and the step over":
    let e = pairing(@[""], 0, 0)
    e.press("i(x)")
    check e.typedKinds == @[tiText, tiKey, tiRight]
    let pair = e.state.editState.insertRecord.typed[0]
    check pair.text == "()"
    check pair.cursorAt == 1

  test "a step over leaves where Insert started as it was":
    let e = pairing(@["()"], 0, 1)
    e.press("i")
    let before = e.state.insertStart
    e.press(")")
    check e.state.insertStart == before
    check e.typedKinds == @[tiRight]

  test "a step over after an arrow is not added":
    let e = pairing(@[""], 0, 0)
    e.press("i(x<Left><Right>")
    check not e.state.editState.typing.open
    e.press(")")
    check not e.state.editState.typing.open
    check e.cursorAt == (0, 3)

  test "a step over after a forced Insert boundary starts a new record":
    let e = pairing(@[""], 0, 0)
    e.config.standard.forceInsertMode = true
    e.state.config.standard.forceInsertMode = true
    e.enforceModePolicy()
    e.press("foo(x")
    check e.commitForcedInsertBoundary(restart = false).isOk
    check not e.state.editState.typing.open
    e.press(");")
    check e.lines == @["foo(x);"]
    check e.typedKinds == @[tiRight, tiKey]

  test "a macro judges the keys again where it is played":
    let e = pairing(@["", "x)"], 0, 0)
    e.press("qai(x)<Escape>qj0@a")
    check e.lines == @["(x)", "(x)x)"]

suite "without autoCloseParen":
  test "a closing character goes in before the same one, and `.` types the key":
    let e = newVimLikeEditor(@["()", "()"], 0, 1)
    e.press("i)")
    check e.lines[0] == "())"
    check e.typedKinds == @[tiKey]
    e.press("<Escape>j.")
    check e.lines == @["())", "())"]

suite "completion around a step over":
  test "a step over offers no completion":
    let e = pairing(@["foobar "], 0, 6)
    e.press("A(fo")
    check e.handlerManager.insertHandler.autoTrigger.isSome
    e.press(")")
    check e.lines == @["foobar (fo)"]
    check e.handlerManager.insertHandler.autoTrigger.isNone

  test "a step over ends a completion under way":
    let e = pairing(@["foobar (fo)"], 0, 10)
    e.press("i")
    e.offer(["foobar"], "fo", selected = false)
    e.press(")")
    check e.lines == @["foobar (fo)"]
    check e.cursorAt == (0, 11)
    check not e.handlerManager.insertHandler.completionManager.isActive()

  test "the candidate highlighted is taken before the step over, once for `.`":
    let e = pairing(@["(fo)", "(fo)"], 0, 3)
    e.press("i")
    e.offer(["foobar"], "fo", selected = true)
    e.press(")")
    check e.lines[0] == "(foobar)"
    check e.cursorAt == (0, 8)
    check e.typedKinds == @[tiText, tiRight]
    e.press("<Escape>j.")
    check e.lines == @["(foobar)", "(foobar)"]

suite "a step over in a snippet session":
  test "out of the stop, it ends the session":
    let e = pairing(@["    xx"], 0, 0)
    e.press("A")
    e.offerSnippet("f(${1:arg})$0")
    e.press("<Enter>x)")
    check e.lines == @["    f(x)"]
    check e.cursorAt == (0, 8)
    check not e.state.snippetSession.active
    check e.handlerManager.insertHandler.autoTrigger.isNone
    e.press(";")
    check e.lines == @["    f(x);"]
    check e.state.snippetSession.stops[0] ==
      SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 6), len: 1)

  test "in the stop, the session goes on and the stop covers what was typed":
    let e = pairing(@["    xx"], 0, 0)
    e.press("A")
    e.offerSnippet("f(${1:arg})$0")
    e.press("<Enter>(x)")
    check e.lines == @["    f((x))"]
    check e.cursorAt == (0, 9)
    check e.state.snippetSession.active
    check e.state.snippetSession.stops[0] ==
      SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 6), len: 3)
    check e.handlerManager.insertHandler.autoTrigger.isNone

  test "over a default still selected, it deletes the default first":
    let e = pairing(@["    xx"], 0, 0)
    e.press("A")
    e.offerSnippet("f(${1:arg})$0")
    e.press("<Enter>)")
    check e.lines == @["    f()"]
    check e.cursorAt == (0, 7)
    check not e.state.snippetSession.active
    # The default went, so the text changed.
    check e.handlerManager.insertHandler.autoTrigger.isSome
