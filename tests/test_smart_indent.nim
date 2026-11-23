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

## Tests for smart_indent.nim and its integration into insert_commands.

import std/[unittest, options, strutils, tables]

import pkg/results

import ../src/moepkg/[buffer, types, config, modes, registers]
import ../src/moepkg/buffer/highlight
import ../src/moepkg/highlight as syntaxHighlight
import ../src/moepkg/syntax/tokenizer
import ../src/moepkg/command_handlers/insert_commands
import ../src/moepkg/command_handlers/smart_indent {.all.}

proc createSmartIndentState(): EditorState =
  ## Minimal EditorState with autoIndent + smartIndent + 2-space expandTab.
  let window = EditorWindow(
    cursor: BufferPosition(line: 0, column: 0),
    mode: EditorMode.Insert,
    previousMode: EditorMode.Normal,
    screenCursor: CursorPosition(x: 0, y: 0),
  )
  let cfg = newEditorConfig()
  cfg.standard.autoIndent = true
  cfg.standard.smartIndent = true
  cfg.standard.tabStop = 2
  cfg.standard.expandTab = true
  EditorState(
    activeWindow: window,
    config: cfg,
    windowDisplay: WindowDisplayState(viewportReservedLines: 2),
    pendingInput: PendingInputState(
      macroState: MacroState(
        registers: initTable[char, seq[string]](),
        lastRegister: none(char),
        playbackDepth: 0,
      )
    ),
    registers: initRegisters(),
  )

proc newNimBuffer(text: string): TextBuffer =
  result = newTextBuffer()
  result.language = SourceLanguage.langNim
  discard result.insertText(BufferPosition(line: 0, column: 0), text)

proc newBufferIn(language: SourceLanguage, text: string): TextBuffer =
  result = newTextBuffer()
  result.language = language
  discard result.insertText(BufferPosition(line: 0, column: 0), text)

const Cursor = "‸"

proc highlighted(language: SourceLanguage, text: string): TextBuffer =
  result = newBufferIn(language, text)
  result.updateHighlight()

proc enterAt(language: SourceLanguage, text: string): NewLineIndent =
  ## `enterIndent` for Enter at `Cursor` in `text`, with the highlight built.
  let
    at = text.find(Cursor)
    line = text[0 ..< at].count('\n')
    split = at - (text.rfind('\n', last = at - 1) + 1)
  highlighted(language, text.replace(Cursor, "")).enterIndent(line, split)

proc indentStep(line: string, language: SourceLanguage, carried = ""): int =
  enterAt(language, line & Cursor & carried).steps

proc aboveDeeper(language: SourceLanguage, text: string, line: int): bool =
  highlighted(language, text).opensAboveDeeper(line)

suite "smart_indent - stripNimCodeOnly":
  test "Plain code is unchanged":
    check stripNimCodeOnly("var") == "var"

  test "Trailing comment is removed":
    check stripNimCodeOnly("var # group") == "var "

  test "String literal content is replaced with 'x' (quotes become spaces)":
    check stripNimCodeOnly("echo \"or\"") == "echo  xx "

  test "Escaped quote inside string becomes 'xx'":
    check stripNimCodeOnly("echo \"a\\\"or\"") == "echo  xxxxx "

  test "Char literal content is replaced with 'x'":
    check stripNimCodeOnly("let c = 'or'") == "let c =  xx "

  test "Triple-quote disables stripping (returns empty)":
    check stripNimCodeOnly("let s = \"\"\" foo") == ""

  test "Hash inside string is not treated as comment":
    check stripNimCodeOnly("echo \"a#b\" + 1") == "echo  xxx  + 1"

  test "Backtick identifier content is replaced with 'x'":
    check stripNimCodeOnly("let `or` = 1") == "let  xx  = 1"

  test "Hash inside backtick is not treated as comment":
    check stripNimCodeOnly("let `a#b` = 1") == "let  xxx  = 1"

suite "smart_indent - indentStep (Nim, positive)":
  test "Standalone 'var' triggers extra indent":
    check indentStep("var", SourceLanguage.langNim) == 1

  test "Standalone 'let' triggers":
    check indentStep("let", SourceLanguage.langNim) == 1

  test "Standalone 'const' triggers":
    check indentStep("const", SourceLanguage.langNim) == 1

  test "Standalone 'type' triggers":
    check indentStep("type", SourceLanguage.langNim) == 1

  test "Indented standalone 'var' still triggers":
    check indentStep("    var", SourceLanguage.langNim) == 1

  test "'var' with trailing comment still triggers":
    check indentStep("var # group", SourceLanguage.langNim) == 1

  test "Trailing 'or' triggers":
    check indentStep("if a or", SourceLanguage.langNim) == 1

  test "Trailing 'and' triggers":
    check indentStep("if a and", SourceLanguage.langNim) == 1

  test "Trailing 'object' triggers":
    check indentStep("type Foo = object", SourceLanguage.langNim) == 1

  test "Trailing 'ref object' triggers (object at end)":
    check indentStep("type Foo = ref object", SourceLanguage.langNim) == 1

  test "Trailing 'tuple' triggers":
    check indentStep("type T = tuple", SourceLanguage.langNim) == 1

  test "Trailing 'enum' triggers":
    check indentStep("type E = enum", SourceLanguage.langNim) == 1

  test "Trailing '=' (proc definition) triggers":
    check indentStep("proc foo() =", SourceLanguage.langNim) == 1

  test "Trailing '=' with whitespace triggers":
    check indentStep("proc foo() =   ", SourceLanguage.langNim) == 1

  test "Trailing ':' on 'if' triggers":
    check indentStep("if x:", SourceLanguage.langNim) == 1

  test "Trailing ':' on 'while' triggers":
    check indentStep("while cond:", SourceLanguage.langNim) == 1

  test "Trailing ':' on 'for' triggers":
    check indentStep("for i in 0 ..< 10:", SourceLanguage.langNim) == 1

  test "Trailing ':' on 'else' triggers":
    check indentStep("else:", SourceLanguage.langNim) == 1

  test "Trailing ':' on 'of' clause triggers":
    check indentStep("of Foo:", SourceLanguage.langNim) == 1

  test "Trailing ':' on 'try' triggers":
    check indentStep("try:", SourceLanguage.langNim) == 1

  test "Trailing ':' on 'block' triggers":
    check indentStep("block named:", SourceLanguage.langNim) == 1

  test "Trailing ':' with whitespace triggers":
    check indentStep("if x:  ", SourceLanguage.langNim) == 1

  test "Unclosed '(' triggers":
    check indentStep("echo foo(", SourceLanguage.langNim) == 1

  test "Unclosed '[' triggers":
    check indentStep("let a = [", SourceLanguage.langNim) == 1

  test "Unclosed '{' triggers":
    check indentStep("let t = {", SourceLanguage.langNim) == 1

  test "Nested unclosed brackets trigger":
    check indentStep("foo(bar([", SourceLanguage.langNim) == 1

  test "A carried closer right after an opener still triggers":
    check indentStep("foo(", SourceLanguage.langNim, ")") == 1

suite "smart_indent - indentStep (negative)":
  test "Plain identifier ending in 'or' (coordinator) does not trigger":
    check indentStep("let coordinator", SourceLanguage.langNim) == 0

  test "Plain identifier ending in 'and' does not trigger":
    check indentStep("let brand", SourceLanguage.langNim) == 0

  test "'==' at end does not trigger":
    check indentStep("if a ==", SourceLanguage.langNim) == 0

  test "'!=' at end does not trigger":
    check indentStep("if a !=", SourceLanguage.langNim) == 0

  test "'<=' at end does not trigger":
    check indentStep("if a <=", SourceLanguage.langNim) == 0

  test "'>=' at end does not trigger":
    check indentStep("if a >=", SourceLanguage.langNim) == 0

  test "'+=' at end does not trigger":
    check indentStep("x +=", SourceLanguage.langNim) == 0

  test "'-=' at end does not trigger":
    check indentStep("x -=", SourceLanguage.langNim) == 0

  test "'*=' at end does not trigger":
    check indentStep("x *=", SourceLanguage.langNim) == 0

  test "'/=' at end does not trigger":
    check indentStep("x /=", SourceLanguage.langNim) == 0

  test "'%=' at end does not trigger":
    check indentStep("x %=", SourceLanguage.langNim) == 0

  test "'&=' at end does not trigger":
    check indentStep("x &=", SourceLanguage.langNim) == 0

  test "Backtick identifier 'or' does not trigger":
    check indentStep("let `or` = 1", SourceLanguage.langNim) == 0

  test "Backtick identifier as last token does not trigger":
    check indentStep("let x = `or`", SourceLanguage.langNim) == 0

  test "'::' at end does not trigger":
    check indentStep("foo::", SourceLanguage.langNim) == 0

  test "Comment ':' does not trigger":
    check indentStep("x = 1  # if x:", SourceLanguage.langNim) == 0

  test "String ':' does not trigger":
    check indentStep("echo \"if x:\"", SourceLanguage.langNim) == 0

  test "'var' followed by name does not trigger":
    check indentStep("var x: int", SourceLanguage.langNim) == 0

  test "String containing 'or' does not trigger":
    check indentStep("echo \"or\"", SourceLanguage.langNim) == 0

  test "String 'object' does not trigger":
    check indentStep("let s = \"object\"", SourceLanguage.langNim) == 0

  test "Comment 'var' does not trigger":
    check indentStep("# var", SourceLanguage.langNim) == 0

  test "Trailing comment 'let' does not trigger":
    check indentStep("x = 1  # let", SourceLanguage.langNim) == 0

  test "Triple-quoted line does not trigger":
    check indentStep("let s = \"\"\" foo", SourceLanguage.langNim) == 0

  test "Balanced brackets do not trigger":
    check indentStep("foo()", SourceLanguage.langNim) == 0

  test "A carried closer after other text does not trigger":
    check indentStep("foo(a", SourceLanguage.langNim, "  )") == 0

  test "Empty line does not trigger":
    check indentStep("", SourceLanguage.langNim) == 0

  test "Non-Nim language never triggers (langNone)":
    check indentStep("var", SourceLanguage.langNone) == 0

  test "Nim keywords do not trigger in another language (langC)":
    check indentStep("var", SourceLanguage.langC) == 0

suite "Insert Commands - insertNewline smart indent (Nim)":
  test "Standalone 'var' Enter inserts indented next line":
    let buf = newNimBuffer("var")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 3)

    insertNewline(buf, state)

    check buf.getLine(0) == "var"
    check buf.getLine(1) == "  "
    check state.cursor.line == 1
    check state.cursor.column == 2

  test "Standalone 'let' Enter inserts indented next line":
    let buf = newNimBuffer("let")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 3)

    insertNewline(buf, state)

    check buf.getLine(1) == "  "
    check state.cursor.column == 2

  test "'proc foo() =' Enter inserts indented next line":
    let buf = newNimBuffer("proc foo() =")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 12)

    insertNewline(buf, state)

    check buf.getLine(0) == "proc foo() ="
    check buf.getLine(1) == "  "
    check state.cursor.column == 2

  test "'type Foo = object' Enter inserts indented next line":
    let buf = newNimBuffer("type Foo = object")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 17)

    insertNewline(buf, state)

    check buf.getLine(1) == "  "
    check state.cursor.column == 2

  test "Unclosed '(' Enter inserts indented next line":
    let buf = newNimBuffer("echo foo(")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 9)

    insertNewline(buf, state)

    check buf.getLine(1) == "  "
    check state.cursor.column == 2

  test "Trailing 'or' Enter inserts indented next line":
    let buf = newNimBuffer("if a or")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 7)

    insertNewline(buf, state)

    check buf.getLine(1) == "  "
    check state.cursor.column == 2

  test "'if x:' Enter inserts indented next line":
    let buf = newNimBuffer("if x:")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 5)

    insertNewline(buf, state)

    check buf.getLine(0) == "if x:"
    check buf.getLine(1) == "  "
    check state.cursor.column == 2

  test "'x +=' Enter does NOT add extra indent":
    let buf = newNimBuffer("x +=")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 4)

    insertNewline(buf, state)

    check buf.getLine(1) == ""
    check state.cursor.column == 0

  test "Backtick identifier ending in 'or' does NOT trigger":
    let buf = newNimBuffer("let `or` = 1")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 12)

    insertNewline(buf, state)

    check buf.getLine(1) == ""
    check state.cursor.column == 0

  test "Indented 'var' preserves base + extra indent":
    let buf = newNimBuffer("    var")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 7)

    insertNewline(buf, state)

    check buf.getLine(0) == "    var"
    check buf.getLine(1) == "      "
    check state.cursor.column == 6

  test "String literal does not trigger extra indent":
    let buf = newNimBuffer("echo \"or\"")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 9)

    insertNewline(buf, state)

    check buf.getLine(1) == ""
    check state.cursor.column == 0

  test "'==' does not trigger extra indent":
    let buf = newNimBuffer("if a ==")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 7)

    insertNewline(buf, state)

    check buf.getLine(1) == ""
    check state.cursor.column == 0

  test "smartIndent=false leaves plain autoIndent behavior":
    let buf = newNimBuffer("    var")
    let state = createSmartIndentState()
    state.smartIndent = false
    state.cursor = BufferPosition(line: 0, column: 7)

    insertNewline(buf, state)

    check buf.getLine(1) == "    "
    check state.cursor.column == 4

  test "Non-Nim buffer with smartIndent=true does not trigger":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "var")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 3)

    insertNewline(buf, state)

    check buf.getLine(1) == ""
    check state.cursor.column == 0

  test "autoIndent=false skips extra indent even when smartIndent=true":
    let buf = newNimBuffer("var")
    let state = createSmartIndentState()
    state.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 3)

    insertNewline(buf, state)

    check buf.getLine(1) == ""
    check state.cursor.column == 0

  test "Tab indent unit honored when expandTab=false":
    let buf = newNimBuffer("var")
    let state = createSmartIndentState()
    state.expandTab = false
    state.cursor = BufferPosition(line: 0, column: 3)

    insertNewline(buf, state)

    check buf.getLine(1) == "\t"
    check state.cursor.column == 1

  test "Nested unclosed brackets only add one extra step":
    let buf = newNimBuffer("foo(bar([")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 9)

    insertNewline(buf, state)

    check buf.getLine(1) == "  "
    check state.cursor.column == 2

  test "A split line is indented by the text before the cursor":
    let buf = newNimBuffer("foo(a, b)")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 7)

    insertNewline(buf, state)

    check buf.getLine(0) == "foo(a, "
    check buf.getLine(1) == "  b)"
    check state.cursor.column == 2

  test "A closer carried down right after its opener takes the step":
    let buf = newNimBuffer("foo()")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 4)

    insertNewline(buf, state)

    check buf.getLine(0) == "foo("
    check buf.getLine(1) == "  )"
    check state.cursor.column == 2

  test "A closer carried down after other text stays at the base indent":
    let buf = newNimBuffer("  foo(a  )")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 7)

    insertNewline(buf, state)

    check buf.getLine(0) == "  foo(a"
    check buf.getLine(1) == "  )"
    check state.cursor.column == 2

  test "Inside an outer bracket, a carried closer steps only after its opener":
    let afterOpener = newNimBuffer("foo(bar(), baz")
    let s1 = createSmartIndentState()
    s1.cursor = BufferPosition(line: 0, column: 8)
    insertNewline(afterOpener, s1)
    check afterOpener.getLine(1) == "  ), baz"

    let afterText = newNimBuffer("foo(bar(a), baz")
    let s2 = createSmartIndentState()
    s2.cursor = BufferPosition(line: 0, column: 9)
    insertNewline(afterText, s2)
    check afterText.getLine(0) == "foo(bar(a"
    check afterText.getLine(1) == "), baz"
    check s2.cursor.column == 0

  test "Enter rebuilds the indent 'shiftwidth' columns deeper, as Vim's smartindent":
    let buf = newNimBuffer("    var")
    let state = createSmartIndentState()
    state.expandTab = false
    state.tabStop = 8
    state.shiftWidth = 4
    state.cursor = BufferPosition(line: 0, column: 7)

    insertNewline(buf, state)

    check buf.getLine(1) == "\t"
    check state.cursor == BufferPosition(line: 1, column: 1)

suite "Insert Commands - insertLineBelow smart indent (Nim)":
  test "'o' after 'var' line inserts indented line below":
    let buf = newNimBuffer("var")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 0)

    check insertLineBelow(buf, state).isOk

    check buf.getLine(0) == "var"
    check buf.getLine(1) == "  "
    check state.cursor.line == 1
    check state.cursor.column == 2

  test "'o' after 'proc foo() =' inserts indented line below":
    let buf = newNimBuffer("proc foo() =")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 0)

    check insertLineBelow(buf, state).isOk

    check buf.getLine(1) == "  "
    check state.cursor.column == 2

  test "'o' inside string-only context does not trigger":
    let buf = newNimBuffer("echo \"or\"")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 0)

    check insertLineBelow(buf, state).isOk

    check buf.getLine(1) == ""
    check state.cursor.column == 0

  test "o adds 'shiftwidth' columns, not a tab, as Vim's smartindent":
    let buf = newNimBuffer("var")
    let state = createSmartIndentState()
    state.expandTab = false
    state.tabStop = 8
    state.shiftWidth = 4

    check insertLineBelow(buf, state).isOk

    check buf.getLine(1) == "    "
    check state.cursor == BufferPosition(line: 1, column: 4)

suite "Insert Commands - smart indent ESC cleanup":
  test "Enter then immediate ESC clears extra indent line":
    let buf = newNimBuffer("var")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 3)

    insertNewline(buf, state)
    # New line is "  ", all of it auto-indent.
    check state.editState.autoIndentedLine.isSome
    check buf.getLine(1) == "  "

    clearAutoIndentIfUnedited(buf, state)

    check buf.getLine(1) == ""
    check state.cursor.column == 0
    check state.editState.autoIndentedLine.isNone

  test "Indented 'var' Enter then ESC clears the whole extra indent":
    let buf = newNimBuffer("    var")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 7)

    insertNewline(buf, state)
    check state.editState.autoIndentedLine.isSome
    check buf.getLine(1) == "      "

    clearAutoIndentIfUnedited(buf, state)

    check buf.getLine(1) == ""

suite "smart_indent - enterIndent (brackets)":
  test "An opener left unclosed indents the next line":
    check indentStep("int f() {", langC) == 1
    check indentStep("foo(a,", langJavaScript) == 1
    check indentStep("let a = [", langRust) == 1
    check indentStep("f() {", langShell) == 1
    check indentStep("g(a,", langPython) == 1

  test "Nested openers still step once":
    check indentStep("foo([", langJavaScript) == 1

  test "Balanced brackets do not indent":
    check indentStep("foo(a, b);", langC) == 0
    check indentStep("}", langC) == 0

  test "A closer carried right after an opener steps in, as Vim's smartindent":
    check enterAt(langC, "int f() {‸}") == (1, -1)
    check enterAt(langJavaScript, "  g(‸)") == (1, -1)
    check enterAt(langJavaScript, "g( ‸ )") == (1, -1)
    check enterAt(langC, "f( /* a */ ‸)") == (1, -1)

  test "A carried closer goes to the line of its opener, as Neovim":
    check enterAt(langJavaScript, "  foo(a, b‸)") == (0, 0)
    check enterAt(langC, "int f() {\n    bar();‸}") == (0, 0)
    check enterAt(langC, "void f() {\n  if (x) {\n    ‸}") == (0, 1)
    check enterAt(langPython, "x = foo(a,\n        b‸)") == (0, 0)
    check enterAt(langJavaScript, "  foo(function () {\n    bar();\n  }‸)") == (0, 0)
    check enterAt(langNim, "proc f() =\n  g(\n    a, b‸)") == (0, 1)

  test "A carried closer matches its own kind of opener":
    check enterAt(langJavaScript, "x = [\n  f(a),\n  b‸]") == (0, 0)

  test "A carried closer with no opener keeps the indent":
    check enterAt(langC, "    bar();‸}") == (0, -1)
    check enterAt(langNim, "let x = ‸)") == (0, -1)

  test "A closer in a string or comment is not carried":
    check enterAt(langNim, "  echo \"(a‸)\"") == (0, -1)
    check enterAt(langNim, "  # call foo(‸)") == (0, -1)
    check enterAt(langC, "    s = \"‸)\";") == (0, -1)

  test "Brackets in strings and comments are not counted":
    check indentStep("puts(\"(\");", langC) == 0
    check indentStep("x = 1; // {", langC) == 0
    check indentStep("echo \"{\"", langShell) == 0
    check indentStep("x = 1  # (", langPython) == 0
    check indentStep("  x = 1  # (", langNim) == 0

  test "Brackets in keys, doc tags and text are not counted":
    check indentStep("  \"key[\": 1,", langJson) == 0
    check indentStep("  /** @param {Object", langJavaScript) == 0
    check indentStep("name: Build (linux", langYaml) == 0
    check indentStep("  <p>See (", langJsx) == 0
    check indentStep("RUN foo (", langDockerfile) == 0

  test "A line inside a long comment or string reads as one":
    check enterAt(langC, "/*\n * Returns (or‸") == (0, -1)
    check enterAt(langPython, "def f():\n    \"\"\"\n    Example: foo(1,‸") == (0, -1)
    check enterAt(langNim, "#[\n  see (‸\n]#") == (0, -1)

  test "Prose and line lists have no rules":
    check indentStep("see (", langNone) == 0
    check indentStep("see (", langMarkdown) == 0
    check indentStep("fix (", langCommitEditMsg) == 0

  test "Markup has no rules":
    check indentStep("This sentence (see", langLatex) == 0
    check indentStep("<p>See (", langHtml) == 0
    check indentStep("<a>See (", langXml) == 0

  test "The file's language decides, not the highlighting":
    let nim = highlighted(langNim, "type")
    nim.syntaxOverride = some(langNone)
    check nim.enterIndent(0, 4).steps == 1
    let tex = highlighted(langLatex, "\\item{")
    tex.syntaxOverride = some(langC)
    check tex.enterIndent(0, 6).steps == 0

suite "smart_indent - opensAboveDeeper":
  test "A line starting with a closer opens a deeper line above":
    check aboveDeeper(langC, "    }", 0)
    check aboveDeeper(langJavaScript, ")", 0)
    check aboveDeeper(langNim, "]", 0)

  test "Other lines do not":
    check not aboveDeeper(langC, "    bar();", 0)
    check not aboveDeeper(langC, "// }", 0)
    check not aboveDeeper(langMarkdown, "}", 0)

  test "The end of a long comment or string is not a closer":
    check not aboveDeeper(langNim, "#[\n  text\n]#", 2)
    check not aboveDeeper(langLua, "--[[\n  text\n]]", 2)
    check not aboveDeeper(langLua, "s = [[\n  text\n]]", 2)

suite "Insert Commands - bracket smart indent":
  test "Enter after an unclosed '{' indents the new line":
    let buf = newBufferIn(langC, "int f() {")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 9)

    insertNewline(buf, state)

    check buf.getLine(1) == "  "
    check state.cursor == BufferPosition(line: 1, column: 2)

  test "Enter before a closer puts it at the opener's line, as Neovim":
    let buf = highlighted(langC, "int f() {\n  bar();}")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 1, column: 8)

    insertNewline(buf, state)

    check buf.getLine(1) == "  bar();"
    check buf.getLine(2) == "}"
    check state.cursor == BufferPosition(line: 2, column: 0)

  test "Enter between brackets steps in, as Vim's smartindent":
    let buf = newBufferIn(langJavaScript, "  g()")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 4)

    insertNewline(buf, state)

    check buf.getLine(1) == "    )"
    check state.cursor == BufferPosition(line: 1, column: 4)

  test "Enter before a closer after arguments keeps the indent":
    let buf = newBufferIn(langJavaScript, "  g(a, b)")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 8)

    insertNewline(buf, state)

    check buf.getLine(1) == "  )"
    check state.cursor == BufferPosition(line: 1, column: 2)

  test "Nim Enter before a closer puts it at the opener's line":
    let buf = highlighted(langNim, "proc f() =\n  g(\n    a, b)")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 2, column: 8)

    insertNewline(buf, state)

    check buf.getLine(2) == "    a, b"
    check buf.getLine(3) == "  )"
    check state.cursor == BufferPosition(line: 3, column: 2)

  test "o after an unclosed '(' indents the new line":
    let buf = newBufferIn(langShell, "f() {")
    let state = createSmartIndentState()

    check insertLineBelow(buf, state).isOk

    check buf.getLine(1) == "  "
    check state.cursor == BufferPosition(line: 1, column: 2)

  test "O on a closer line indents the new line, as Vim's smartindent":
    let buf = newBufferIn(langC, "  }")
    let state = createSmartIndentState()

    check insertLineAbove(buf, state).isOk

    check buf.getLine(0) == "    "
    check buf.getLine(1) == "  }"
    check state.cursor == BufferPosition(line: 0, column: 4)

  test "O on another line keeps its indent":
    let buf = newBufferIn(langC, "  bar();")
    let state = createSmartIndentState()

    check insertLineAbove(buf, state).isOk

    check buf.getLine(0) == "  "

  test "smartIndent=false copies the indent only":
    let buf = newBufferIn(langC, "  }")
    let state = createSmartIndentState()
    state.smartIndent = false

    check insertLineAbove(buf, state).isOk

    check buf.getLine(0) == "  "

suite "smart_indent - reading a line where the highlight cannot tell":
  test "rows the highlight has not caught up with are read again":
    # The `(` of `  ( */` is in the comment once a line goes in above, though
    # the stale cache says the line after `/*` is outside it.
    let buf = highlighted(langC, "/*\n  ( */\nint f() {")
    check buf.insertText(BufferPosition(line: 0, column: 0), "\n").isOk
    check buf.getLine(2) == "  ( */"
    check buf.enterIndent(2, buf.getLine(2).len) == (0, -1)
    check buf.enterIndent(3, buf.getLine(3).len) == (1, -1)

  test "a line in a nested comment is read from where the comment opens":
    # Restarting at line 2 would take the depth the comment ended with, and
    # read `]#` as its end.
    check enterAt(langNim, "#[ a\n  #[ b\n  c ]# d (‸\n]#") == (0, -1)
    check enterAt(langRust, "/* a\n  /* b\n  c */ d (‸\n*/") == (0, -1)

  test "a line under another backend's cache is read from the top":
    let buf = highlighted(langPython, "\"\"\"\n  see foo(\n\"\"\"")
    buf.incrementalHighlight.lineStates = initLineStateCache(
      [TokenizerState(backend: hbMatter), TokenizerState(backend: hbMatter)]
    )
    check buf.enterIndent(1, buf.getLine(1).len) == (0, -1)

  test "far down under another backend's cache, a line is read on its own":
    var lines = newSeq[string](1500)
    lines[^1] = "foo("
    let buf = highlighted(langC, lines.join("\n"))
    var states = newSeq[TokenizerState](1500)
    for s in states.mitems:
      s.backend = hbMatter
    buf.incrementalHighlight.lineStates = initLineStateCache(states)
    check buf.enterIndent(1499, 4) == (1, -1)

  test "far from a known state, a line is read on its own":
    var lines = newSeq[string](1500)
    lines[^1] = "foo("
    let buf = newBufferIn(langC, lines.join("\n"))
    check buf.enterIndent(1499, 4) == (1, -1)
    # Not knowing it is in a comment, it reads as code.
    lines[1000] = "/*"
    let commented = newBufferIn(langC, lines.join("\n"))
    check commented.enterIndent(1499, 4) == (1, -1)
    commented.updateHighlight()
    check commented.enterIndent(1499, 4) == (0, -1)

  test "an edit far above, not caught up with yet, is not read through":
    # As a macro edits and opens a line before the next frame.
    var lines = newSeq[string](2000)
    lines[1990] = "int f() {"
    let buf = highlighted(langC, lines.join("\n"))
    check buf.insertText(BufferPosition(line: 10, column: 0), "/*").isOk
    check buf.enterIndent(1990, 9) == (1, -1)

  test "a closer finds its opener far below the last parsed row":
    var lines = newSeq[string](3000)
    lines[2000] = "  if (x) {"
    lines[2999] = "    }"
    let buf = newBufferIn(langC, lines.join("\n"))
    check buf.closerAlignLine(2999, 4) == 2000

  test "rows the initial load has not reached are not known states":
    var lines = newSeq[string](3000)
    let buf = newBufferIn(langC, lines.join("\n"))
    buf.updateHighlight(reparseBudget = 1000)
    check buf.incrementalHighlight.parsedUpTo == 999
    # As a re-parse below the load frontier leaves the band between with
    # default states.
    buf.incrementalHighlight.lineStates.setLen(3000)
    check buf.resumePoint(2500, 1000).isNone
    check buf.resumePoint(1200, 1000).get.line <= 1000

suite "smart_indent - lines past synmaxcol":
  test "nothing past the cap is code, wherever reading starts":
    # The highlight reads `  g(` as code; so does the search for its opener,
    # though it starts above the long line.
    let long = "x".repeat(40) & " /*"
    let buf = newBufferIn(langC, "int f() {\n" & long & "\n  g(\n  )")
    buf.setMaxHighlightLineLength(20)
    buf.updateHighlight()
    check buf.closerAlignLine(3, 2) == 2

suite "smart_indent - Nim keywords after a comment closed on the line":
  test "a block comment closed on the line does not stop the keyword indent":
    check indentStep("proc foo() = #[ note ]#", langNim) == 1
    check indentStep("var #[ x ]#", langNim) == 1

  test "a long string or comment left open does":
    check indentStep("let s = \"\"\"abc", langNim) == 0
    check indentStep("proc foo() = #[ note", langNim) == 0
