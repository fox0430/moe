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

import std/[unittest, options, tables]

import ../src/moepkg/[buffer, types, config, modes, registers]
import ../src/moepkg/syntax/tokenizer
import ../src/moepkg/command_handlers/[insert_commands, smart_indent]

proc createSmartIndentState(): EditorState =
  ## Minimal EditorState with autoIndent + smartIndent + 2-space expandTab.
  let window = EditorWindow(
    cursor: BufferPosition(line: 0, column: 0),
    mode: EditorMode.Insert,
    previousMode: EditorMode.Normal,
    preferredColumn: -1,
    screenCursor: CursorPosition(x: 0, y: 0),
  )
  let cfg = newEditorConfig()
  cfg.standard.autoIndent = true
  cfg.standard.smartIndent = true
  cfg.standard.tabStop = 2
  cfg.standard.expandTab = true
  EditorState(
    activeWindow: window,
    display: DisplaySettings(),
    config: cfg,
    windowDisplay: WindowDisplayState(viewportReservedLines: 2),
    pendingInput: PendingInputState(
      macroState: MacroState(
        isRecording: false,
        register: '\0',
        recordedKeys: @[],
        registers: initTable[char, seq[string]](),
        lastRegister: none(char),
        waitingForRegister: false,
        commandType: "",
        pendingCount: 0,
        playbackDepth: 0,
      )
    ),
    registers: initRegisters(),
  )

proc newNimBuffer(text: string): TextBuffer =
  result = newTextBuffer()
  result.language = SourceLanguage.langNim
  discard result.insertText(BufferPosition(line: 0, column: 0), text)

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

suite "smart_indent - extraIndentForNewline (Nim, positive)":
  test "Standalone 'var' triggers extra indent":
    check extraIndentForNewline("var", SourceLanguage.langNim, "  ") == "  "

  test "Standalone 'let' triggers":
    check extraIndentForNewline("let", SourceLanguage.langNim, "  ") == "  "

  test "Standalone 'const' triggers":
    check extraIndentForNewline("const", SourceLanguage.langNim, "  ") == "  "

  test "Standalone 'type' triggers":
    check extraIndentForNewline("type", SourceLanguage.langNim, "  ") == "  "

  test "Indented standalone 'var' still triggers":
    check extraIndentForNewline("    var", SourceLanguage.langNim, "  ") == "  "

  test "'var' with trailing comment still triggers":
    check extraIndentForNewline("var # group", SourceLanguage.langNim, "  ") == "  "

  test "Trailing 'or' triggers":
    check extraIndentForNewline("if a or", SourceLanguage.langNim, "  ") == "  "

  test "Trailing 'and' triggers":
    check extraIndentForNewline("if a and", SourceLanguage.langNim, "  ") == "  "

  test "Trailing 'object' triggers":
    check extraIndentForNewline("type Foo = object", SourceLanguage.langNim, "  ") ==
      "  "

  test "Trailing 'ref object' triggers (object at end)":
    check extraIndentForNewline("type Foo = ref object", SourceLanguage.langNim, "  ") ==
      "  "

  test "Trailing 'tuple' triggers":
    check extraIndentForNewline("type T = tuple", SourceLanguage.langNim, "  ") == "  "

  test "Trailing 'enum' triggers":
    check extraIndentForNewline("type E = enum", SourceLanguage.langNim, "  ") == "  "

  test "Trailing '=' (proc definition) triggers":
    check extraIndentForNewline("proc foo() =", SourceLanguage.langNim, "  ") == "  "

  test "Trailing '=' with whitespace triggers":
    check extraIndentForNewline("proc foo() =   ", SourceLanguage.langNim, "  ") == "  "

  test "Trailing ':' on 'if' triggers":
    check extraIndentForNewline("if x:", SourceLanguage.langNim, "  ") == "  "

  test "Trailing ':' on 'while' triggers":
    check extraIndentForNewline("while cond:", SourceLanguage.langNim, "  ") == "  "

  test "Trailing ':' on 'for' triggers":
    check extraIndentForNewline("for i in 0 ..< 10:", SourceLanguage.langNim, "  ") ==
      "  "

  test "Trailing ':' on 'else' triggers":
    check extraIndentForNewline("else:", SourceLanguage.langNim, "  ") == "  "

  test "Trailing ':' on 'of' clause triggers":
    check extraIndentForNewline("of Foo:", SourceLanguage.langNim, "  ") == "  "

  test "Trailing ':' on 'try' triggers":
    check extraIndentForNewline("try:", SourceLanguage.langNim, "  ") == "  "

  test "Trailing ':' on 'block' triggers":
    check extraIndentForNewline("block named:", SourceLanguage.langNim, "  ") == "  "

  test "Trailing ':' with whitespace triggers":
    check extraIndentForNewline("if x:  ", SourceLanguage.langNim, "  ") == "  "

  test "Unclosed '(' triggers":
    check extraIndentForNewline("echo foo(", SourceLanguage.langNim, "  ") == "  "

  test "Unclosed '[' triggers":
    check extraIndentForNewline("let a = [", SourceLanguage.langNim, "  ") == "  "

  test "Unclosed '{' triggers":
    check extraIndentForNewline("let t = {", SourceLanguage.langNim, "  ") == "  "

  test "Nested unclosed brackets still give exactly one step":
    check extraIndentForNewline("foo(bar([", SourceLanguage.langNim, "  ") == "  "

  test "Custom indent unit (tab) is honored":
    check extraIndentForNewline("var", SourceLanguage.langNim, "\t") == "\t"

suite "smart_indent - extraIndentForNewline (negative)":
  test "Plain identifier ending in 'or' (coordinator) does not trigger":
    check extraIndentForNewline("let coordinator", SourceLanguage.langNim, "  ") == ""

  test "Plain identifier ending in 'and' does not trigger":
    check extraIndentForNewline("let brand", SourceLanguage.langNim, "  ") == ""

  test "'==' at end does not trigger":
    check extraIndentForNewline("if a ==", SourceLanguage.langNim, "  ") == ""

  test "'!=' at end does not trigger":
    check extraIndentForNewline("if a !=", SourceLanguage.langNim, "  ") == ""

  test "'<=' at end does not trigger":
    check extraIndentForNewline("if a <=", SourceLanguage.langNim, "  ") == ""

  test "'>=' at end does not trigger":
    check extraIndentForNewline("if a >=", SourceLanguage.langNim, "  ") == ""

  test "'+=' at end does not trigger":
    check extraIndentForNewline("x +=", SourceLanguage.langNim, "  ") == ""

  test "'-=' at end does not trigger":
    check extraIndentForNewline("x -=", SourceLanguage.langNim, "  ") == ""

  test "'*=' at end does not trigger":
    check extraIndentForNewline("x *=", SourceLanguage.langNim, "  ") == ""

  test "'/=' at end does not trigger":
    check extraIndentForNewline("x /=", SourceLanguage.langNim, "  ") == ""

  test "'%=' at end does not trigger":
    check extraIndentForNewline("x %=", SourceLanguage.langNim, "  ") == ""

  test "'&=' at end does not trigger":
    check extraIndentForNewline("x &=", SourceLanguage.langNim, "  ") == ""

  test "Backtick identifier 'or' does not trigger":
    check extraIndentForNewline("let `or` = 1", SourceLanguage.langNim, "  ") == ""

  test "Backtick identifier as last token does not trigger":
    check extraIndentForNewline("let x = `or`", SourceLanguage.langNim, "  ") == ""

  test "'::' at end does not trigger":
    check extraIndentForNewline("foo::", SourceLanguage.langNim, "  ") == ""

  test "Comment ':' does not trigger":
    check extraIndentForNewline("x = 1  # if x:", SourceLanguage.langNim, "  ") == ""

  test "String ':' does not trigger":
    check extraIndentForNewline("echo \"if x:\"", SourceLanguage.langNim, "  ") == ""

  test "'var' followed by name does not trigger":
    check extraIndentForNewline("var x: int", SourceLanguage.langNim, "  ") == ""

  test "String containing 'or' does not trigger":
    check extraIndentForNewline("echo \"or\"", SourceLanguage.langNim, "  ") == ""

  test "String 'object' does not trigger":
    check extraIndentForNewline("let s = \"object\"", SourceLanguage.langNim, "  ") == ""

  test "Comment 'var' does not trigger":
    check extraIndentForNewline("# var", SourceLanguage.langNim, "  ") == ""

  test "Trailing comment 'let' does not trigger":
    check extraIndentForNewline("x = 1  # let", SourceLanguage.langNim, "  ") == ""

  test "Triple-quoted line does not trigger":
    check extraIndentForNewline("let s = \"\"\" foo", SourceLanguage.langNim, "  ") == ""

  test "Balanced brackets do not trigger":
    check extraIndentForNewline("foo()", SourceLanguage.langNim, "  ") == ""

  test "Empty line does not trigger":
    check extraIndentForNewline("", SourceLanguage.langNim, "  ") == ""

  test "Non-Nim language never triggers (langNone)":
    check extraIndentForNewline("var", SourceLanguage.langNone, "  ") == ""

  test "Non-Nim language never triggers (langC)":
    check extraIndentForNewline("var", SourceLanguage.langC, "  ") == ""

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

suite "Insert Commands - insertLineBelow smart indent (Nim)":
  test "'o' after 'var' line inserts indented line below":
    let buf = newNimBuffer("var")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 0)

    insertLineBelow(buf, state)

    check buf.getLine(0) == "var"
    check buf.getLine(1) == "  "
    check state.cursor.line == 1
    check state.cursor.column == 2

  test "'o' after 'proc foo() =' inserts indented line below":
    let buf = newNimBuffer("proc foo() =")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 0)

    insertLineBelow(buf, state)

    check buf.getLine(1) == "  "
    check state.cursor.column == 2

  test "'o' inside string-only context does not trigger":
    let buf = newNimBuffer("echo \"or\"")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 0)

    insertLineBelow(buf, state)

    check buf.getLine(1) == ""
    check state.cursor.column == 0

suite "Insert Commands - smart indent ESC cleanup":
  test "Enter then immediate ESC clears extra indent line":
    let buf = newNimBuffer("var")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 3)

    insertNewline(buf, state)
    # New line is "  " — autoIndentedLine should hold the full indent.
    check state.editState.autoIndentedLine.isSome
    check state.editState.autoIndentedLine.get.indent == "  "

    clearAutoIndentIfUnedited(buf, state)

    check buf.getLine(1) == ""
    check state.cursor.column == 0
    check state.editState.autoIndentedLine.isNone

  test "Indented 'var' Enter then ESC clears the whole extra indent":
    let buf = newNimBuffer("    var")
    let state = createSmartIndentState()
    state.cursor = BufferPosition(line: 0, column: 7)

    insertNewline(buf, state)
    check state.editState.autoIndentedLine.get.indent == "      "

    clearAutoIndentIfUnedited(buf, state)

    check buf.getLine(1) == ""
