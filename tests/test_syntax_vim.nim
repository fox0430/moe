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

import std/[unittest, algorithm, sequtils, strutils]

import ../src/moepkg/syntax/[tokenizer, dispatch, syntax_vim]

proc tokens(code: string): seq[tuple[kind: TokenClass, text: string]] =
  ## Tokenize `code` as Vim script and return every non-whitespace token.
  var g: GeneralTokenizer
  g.initGeneralTokenizer(code)
  while true:
    g.getNextToken(langVim)
    if g.kind == gtEof:
      break
    if g.kind != gtWhitespace:
      result.add (g.kind, code[g.start ..< g.start + g.length])

proc kindOf(code, text: string): TokenClass =
  ## Kind of the first token spelled `text`.
  for t in tokens(code):
    if t.text == text:
      return t.kind
  doAssert false, "no token " & text & " in: " & code

proc stateAfter(code: string): VimState =
  var g: GeneralTokenizer
  g.initGeneralTokenizer(code)
  while true:
    g.getNextToken(langVim)
    if g.kind == gtEof:
      break
  g.lang.vim

suite "syntax_vim - keyword tables":
  test "every table is sorted (isKeyword uses a binary search)":
    for table in [
      vimCommands.toSeq, vimModifiers.toSeq, vimMapCommands.toSeq,
      vimExprCommands.toSeq, vimScriptCommands.toSeq, vimBuiltins.toSeq,
      vimBooleans.toSeq, vimSpecialVars.toSeq, vimTypes.toSeq, vimKeyNames.toSeq,
      vimAutocmdEvents.toSeq, vim9Statements.toSeq, vim9InvalidCommands.toSeq,
    ]:
      check table.isSorted

  test "command subsets only hold full command names":
    for table in [
      vimModifiers.toSeq, vimMapCommands.toSeq, vimExprCommands.toSeq,
      vimScriptCommands.toSeq, vim9InvalidCommands.toSeq,
    ]:
      for word in table:
        check word in vimCommands

  test "every abbreviation resolves to its own command":
    for spec in vimCommandSpecs:
      let
        bracket = spec.find('[')
        name = spec.multiReplace(("[", ""), ("]", ""))
        minLen = if bracket < 0: name.len else: bracket
      for n in minLen .. name.len:
        let abbrev = name[0 ..< n]
        if abbrev == name or abbrev notin vimCommands:
          check vimCommand(abbrev) == name
      if minLen > 1:
        check vimCommand(name[0 ..< minLen - 1]) != name

  test "a full name wins over a command it abbreviates":
    check vimCommand("final") == "final"
    check vimCommand("fina") == "finally"
    check vimCommand("py3") == "py3"
    check vimCommand("fin") == "find"

suite "syntax_vim - comments":
  test "a line comment at command position":
    check tokens("\" a comment\nlet x = 1")[0] == (gtComment, "\" a comment")

  test "an indented comment":
    check tokens("  \" indented") == @[(gtComment, "\" indented")]

  test "a spaced `\"` after a value is a trailing comment":
    check tokens("set number \" show numbers") ==
      @[(gtKeyword, "set"), (gtIdentifier, "number"), (gtComment, "\" show numbers")]
    check kindOf("let x = \"a\" \" note", "\" note") == gtComment
    check kindOf("endif \" end", "\" end") == gtComment

  test "a `\"` where an expression starts is a string":
    check tokens("echo \"hi\"") == @[(gtKeyword, "echo"), (gtStringLit, "\"hi\"")]
    check kindOf("let x = \"a\"", "\"a\"") == gtStringLit
    check kindOf("call F(1, \"a\")", "\"a\"") == gtStringLit

  test ":echo and :execute take no trailing comment":
    check tokens("echo \"a\" \"b\"")[^1] == (gtStringLit, "\"b\"")
    check tokens("exe \"x\" \" c")[^1] == (gtStringLit, "\" c")
    check tokens("echo \"a\"\n      \\ \"b\"")[^1] == (gtStringLit, "\"b\"")
    check tokens("call F() \" c")[^1] == (gtComment, "\" c")

  test ":let and :const take a comment before their target, :return does not":
    check tokens("let \" c")[^1] == (gtComment, "\" c")
    check tokens("const \" c")[^1] == (gtComment, "\" c")
    check tokens("return \" c")[^1] == (gtStringLit, "\" c")
    check kindOf("let x[ \"k\"] = 1", "\"k\"") == gtStringLit

  test "a comment after a `|` command separator":
    check tokens("if 1 | \" c") ==
      @[(gtKeyword, "if"), (gtDecNumber, "1"), (gtOperator, "|"), (gtComment, "\" c")]

  test "`||` is an operator, not a separator":
    check kindOf("if a || \"b\"", "\"b\"") == gtStringLit

  test "a spaced `\"` outside an expression is a comment even after an operator":
    for line in [
      "set path+=** \" c", "set listchars=tab:>\\ ,trail:- \" c",
      "set matchpairs+=<:> \" c", "set undodir=~/.vim/undo// \" c", "edit % \" c",
    ]:
      check tokens(line)[^1] == (gtComment, "\" c")

  test "a spaced `\"` after an operator in an expression is a string":
    check kindOf("let x = 1 . \"a\"", "\"a\"") == gtStringLit
    check kindOf("function F(a = \"x\")", "\"x\"") == gtStringLit
    check kindOf("cexpr F( \"x\")", "\"x\"") == gtStringLit
    check kindOf("py3 print( \"x\")", "\"x\"") == gtStringLit

  test "a `\"` in a `:luado` line's code is a string":
    for cmd in ["luado", "perldo", "py3do", "pydo", "pyxdo", "rubydo", "tcldo"]:
      check kindOf(cmd & " return \"x\"", "\"x\"") == gtStringLit

  test "a legacy `#` at command position is `:number`":
    check tokens("# note") == @[(gtKeyword, "#"), (gtIdentifier, "note")]
    check kindOf("#5", "#") == gtKeyword

  test "a legacy `#` mid-command is not a comment":
    check tokens("let x = 1 # y") ==
      @[
        (gtKeyword, "let"),
        (gtIdentifier, "x"),
        (gtOperator, "="),
        (gtDecNumber, "1"),
        (gtOperator, "#"),
        (gtIdentifier, "y"),
      ]

suite "syntax_vim - Vim9 script":
  test "`#` comments and `\"` strings after vim9script":
    check tokens("vim9script\n# c\n\"s\"->len()\nvar x = 1  # t") ==
      @[
        (gtKeyword, "vim9script"),
        (gtComment, "# c"),
        (gtStringLit, "\"s\""),
        (gtOperator, "->"),
        (gtBuiltin, "len"),
        (gtPunctuation, "("),
        (gtPunctuation, ")"),
        (gtKeyword, "var"),
        (gtIdentifier, "x"),
        (gtOperator, "="),
        (gtDecNumber, "1"),
        (gtComment, "# t"),
      ]

  test "a `#` not preceded by a blank is not a comment":
    check kindOf("vim9script\nif a ==# b", "==#") == gtOperator

  test "a :def body is Vim9 in a legacy script":
    let ts = tokens("def F()\n# c\nreturn \"s\"\nenddef\n\" legacy")
    check (gtComment, "# c") in ts
    check (gtStringLit, "\"s\"") in ts
    check ts[^1] == (gtComment, "\" legacy")

  test "a :def without parameters lists functions":
    check tokens("def F\n\" c\nlet x = 1")[2] == (gtComment, "\" c")
    check kindOf("def <SID>F()\n# c\nenddef", "# c") == gtComment
    check kindOf("def F<T>(x: T)\n# c\nenddef", "# c") == gtComment

  test "an unclosed generic does not reach the next line":
    check kindOf("def F<T\n(x)\n\" c", "\" c") == gtComment

  test "a :def without a body opens none":
    check stateAfter("vim9script\ninterface I\n  def F(): number\nendinterface").bodies ==
      ""
    check stateAfter(
      "vim9script\nabstract class A\n  abstract def F(): number\nendclass"
    ).bodies == ""
    check stateAfter("vim9script\ninterface I\nendinterface\ndef G()").bodies == "d"
    check stateAfter("vim9script\nclass A\n  def F()\n  enddef\nendclass").bodies == ""

  test "a :function body is legacy in a Vim9 script":
    let ts = tokens(
      "vim9script\nfunction! F()\n  \" c\n  let x = 1 \" t\nendfunction\n\"s\"->len()"
    )
    check (gtComment, "\" c") in ts
    check (gtComment, "\" t") in ts
    check (gtStringLit, "\"s\"") in ts

  test "a legacy :function takes a blank before `(`, unlike Vim9 and :def":
    check stateAfter("function F (x)").bodies == "f"
    check stateAfter("vim9script\nfunction F()\n  function G (x)").bodies == "ff"
    check stateAfter("vim9script\nfunction G (x)").bodies == ""
    check stateAfter("def H (x)").bodies == ""
    let ts = tokens(
      "vim9script\nfunction Outer()\n  function Inner (x)\n  endfunction\n" &
        "  \" still in Outer\nendfunction"
    )
    check (gtComment, "\" still in Outer") in ts

  test "the innermost body decides the syntax":
    let ts =
      tokens("function F()\n  def G()\n    \"s\"->len()\n  enddef\n  \" c\nendfunction")
    check (gtStringLit, "\"s\"") in ts
    check (gtComment, "\" c") in ts
    check stateAfter("vim9script\nfunction F()\n  def G()\nendfunction").bodies == ""

  test "`legacy` runs one line with legacy syntax":
    check kindOf("vim9script\nlegacy let x = 1 \" c", "\" c") == gtComment
    check kindOf("vim9script\nlegacy let x = 1\n\"s\"->len()", "\"s\"") == gtStringLit
    check stateAfter("vim9script\n{\nlegacy echo 1\necho 2").brackets == "B"
    check kindOf("vim9script\nlegacy g/a/s/b/c/ \" c", "\" c") == gtComment

  test "types are colored in Vim9 only":
    check kindOf("vim9script\nvar s: string", "string") == gtTypeName
    check kindOf("let s = string", "string") == gtIdentifier

  test "interpolated strings":
    check kindOf("vim9script\necho $\"a {b}\"", "$\"a {b}\"") == gtStringLit
    check kindOf("vim9script\necho $'a {b}'", "$'a {b}'") == gtStringLit

  test "an interpolated string's `{expr}` may hold its quote":
    check tokens("vim9script\necho $\"a {x ?? \"w\"} b\" # c")[^2 .. ^1] ==
      @[(gtStringLit, "$\"a {x ?? \"w\"} b\""), (gtComment, "# c")]
    check tokens("vim9script\necho $'it''s {x ?? 'w'} {{b'")[^1] ==
      (gtStringLit, "$'it''s {x ?? 'w'} {{b'")
    check tokens("vim9script\necho $\"a\\t{x ?? \"w\"} b\" # c")[^4 .. ^1] ==
      @[
        (gtStringLit, "$\"a"),
        (gtEscapeSequence, "\\t"),
        (gtStringLit, "{x ?? \"w\"} b\""),
        (gtComment, "# c"),
      ]
    check tokens("vim9script\necho $\"\\e\" .. \"{a ?? \"b\"}\"")[^3 .. ^1] ==
      @[(gtStringLit, "\"{a ?? \""), (gtIdentifier, "b"), (gtStringLit, "\"}\"")]

suite "syntax_vim - Vim9 line continuation":
  test "a line inside brackets continues the expression":
    check tokens("vim9script\nFoo(\n  s,\n  g)")[1 ..^ 1] ==
      @[
        (gtIdentifier, "Foo"),
        (gtPunctuation, "("),
        (gtIdentifier, "s"),
        (gtPunctuation, ","),
        (gtIdentifier, "g"),
        (gtPunctuation, ")"),
      ]
    let ts = tokens("vim9script\nvar l = [\n  e,\n  'x',\n]\necho 1")
    check (gtIdentifier, "e") in ts
    check (gtKeyword, "echo") in ts

  test "a lambda block's lines are commands":
    let ts = tokens("vim9script\ntimer_start(10, (_) => {\n  echo 1\n})\nset ts=2")
    check (gtKeyword, "echo") in ts
    check (gtKeyword, "set") in ts

  test "a `}` in keys or legacy script does not end a block":
    for line in ["nnoremap a :echo {}<CR>", "legacy echo {}", "normal! }"]:
      let code = "vim9script\nF((_) => {\n  " & line & "\n  normal! \"ayy\n})"
      check tokens(code)[^5 .. ^3] ==
        @[(gtKeyword, "normal!"), (gtSpecialVar, "\"a"), (gtIdentifier, "yy")]

  test "a line starting with an operator continues":
    let ts = tokens("vim9script\nvar x = a\n  ->F()\n  .. e\nvar y = c\n  ? s\n  : g")
    for name in ["e", "s", "g"]:
      check (gtIdentifier, name) in ts

  test "a line starting with a comparison or a shift continues":
    for op in [
      "> 3", ">= 3", "< 3", "<= 3", "<< 2", ">> 2", "is l", "isnot l", "is# l",
      "isnot? l",
    ]:
      check kindOf("vim9script\nvar a = x\n  " & op & "\n  .. e", "e") == gtIdentifier
    check kindOf("vim9script\nvar a = x\nis_ok\n  .. e", "e") == gtKeyword

  test "a line starting with an operator continues a statement that starts with a value":
    for start in ["'b'->F()", "&tabstop = a", "$X = a", "@a = a"]:
      check kindOf("vim9script\n" & start & "\n  ? b\n  : y", "y") == gtIdentifier

  test "`++` and `--` start a statement":
    check kindOf("vim9script\nvar x = 1\n++n\necho 1", "echo") == gtKeyword
    check kindOf("vim9script\nvar x = 1\n--n\necho 1", "echo") == gtKeyword
    check kindOf("vim9script\nnnoremap x y\n++n # c", "# c") == gtComment
    check tokens("vim9script\n++n")[1 .. ^1] ==
      @[(gtOperator, "++"), (gtIdentifier, "n")]
    check kindOf("def F()\n  --x\nenddef", "x") == gtIdentifier
    check tokens("vim9script\nF() | ++n")[^1] == (gtIdentifier, "n")
    check kindOf("vim9script\nnnoremap x <ScriptCmd>++g:n<CR>", "g:n") == gtIdentifier

  test "`++` and `--` are a range in legacy script or after `:`":
    check kindOf("++n", "n") == gtKeyword
    check kindOf("vim9script\n:++n", "n") == gtKeyword
    check kindOf("vim9script\n:.,++d", "d") == gtKeyword

  test "a line after a binary operator continues":
    let ts = tokens("vim9script\nvar total = a +\n  n -\n  m\necho 1")
    check (gtIdentifier, "n") in ts
    check (gtIdentifier, "m") in ts
    check (gtKeyword, "echo") in ts

  test "a comment inside a multi-line list":
    check kindOf("vim9script\nvar l = [\n  # c\n  1,\n]", "# c") == gtComment

  test "brackets outside an expression do not continue":
    check kindOf("vim9script\nset cinoptions=(0\necho 1", "echo") == gtKeyword

  test "enddef ends an unclosed expression":
    let ts = tokens("vim9script\ndef F()\n  call(\nenddef\necho 1")
    check (gtKeyword, "enddef") in ts
    check (gtKeyword, "echo") in ts

  test "a statement ends an unclosed expression":
    let ts = tokens("vim9script\nvar x = F(\nif x\n  set nowrap\nendif")
    for word in ["if", "set", "endif"]:
      check (gtKeyword, word) in ts
    check stateAfter("vim9script\nvar x = F(\nvar y = 1").brackets == ""

  test "a statement ends only the brackets inside its block":
    let code = "vim9script\nF((_) => {\n  G(\n  var x = 1\n})\necho 1"
    check kindOf(code, "var") == gtKeyword
    check stateAfter(code).brackets == ""

  test "a dict key is not a statement":
    let ts = tokens("vim9script\nvar d = {\n  if: 1,\n  for: 2,\n}\necho 1")
    check (gtIdentifier, "if") in ts
    check (gtIdentifier, "for") in ts
    check (gtKeyword, "echo") in ts

  test "a user command's arguments do not continue":
    check kindOf("vim9script\nRg foo(\necho 1", "echo") == gtKeyword
    check kindOf("vim9script\nTabularize /=\necho 1", "echo") == gtKeyword
    check kindOf("vim9script\nfilter /(/ ls\necho 1", "echo") == gtKeyword

  test "legacy script needs a backslash":
    check kindOf("call F(\ne", "e") == gtKeyword

  test "generic type arguments":
    check tokens("vim9script\nvar bufs: list<Buffer> = []")[1 ..^ 1] ==
      @[
        (gtKeyword, "var"),
        (gtIdentifier, "bufs"),
        (gtPunctuation, ":"),
        (gtTypeName, "list"),
        (gtPunctuation, "<"),
        (gtIdentifier, "Buffer"),
        (gtPunctuation, ">"),
        (gtOperator, "="),
        (gtPunctuation, "["),
        (gtPunctuation, "]"),
      ]
    check tokens("vim9script\nvar d: list<dict<string>>")[^2 .. ^1] ==
      @[(gtPunctuation, ">"), (gtPunctuation, ">")]
    check kindOf("vim9script\ndef F<T>(x: T): T", "<") == gtPunctuation
    check kindOf("vim9script\nvar l: list<string>\necho 1", "echo") == gtKeyword

  test "key notation in a Vim9 map is not a generic":
    check kindOf("vim9script\nnnoremap [b :bprevious<CR>", "<CR>") == gtSpecialVar
    check kindOf("vim9script\nnnoremap x <Cmd>echo 1<CR>", "<CR>") == gtSpecialVar

  test "generics in a def's parameters and a type alias":
    check kindOf("vim9script\ndef F(d: dict<any>)", "dict") == gtTypeName
    check kindOf("vim9script\ntype Ids = list<number>", "<") == gtPunctuation

  test "a spaced `<` is still a comparison in Vim9":
    check kindOf("vim9script\nif a < b", "<") == gtOperator

suite "syntax_vim - strings":
  test "escapes split a double-quoted string":
    check tokens("echo \"a\\tb\\<C-w>\"") ==
      @[
        (gtKeyword, "echo"),
        (gtStringLit, "\"a"),
        (gtEscapeSequence, "\\t"),
        (gtStringLit, "b"),
        (gtEscapeSequence, "\\<C-w>"),
        (gtStringLit, "\""),
      ]

  test "numeric escapes take a bounded digit run":
    check (gtEscapeSequence, "\\x41") in tokens("echo \"\\x41F\"")
    check (gtEscapeSequence, "\\u00e9") in tokens("echo \"\\u00e9\"")
    check (gtEscapeSequence, "\\101") in tokens("echo \"\\1012\"")

  test "a single-quoted string doubles its quote":
    check kindOf("echo 'it''s' x", "'it''s'") == gtStringLit

  test "strings end at the end of the line":
    check tokens("echo \"open\nlet x") ==
      @[
        (gtKeyword, "echo"),
        (gtStringLit, "\"open"),
        (gtKeyword, "let"),
        (gtIdentifier, "x"),
      ]
    check tokens("echo 'open\nlet x")[1] == (gtStringLit, "'open")

  test "a trailing backslash does not carry the string to the next line":
    check tokens("echo \"a\\\nlet x") ==
      @[
        (gtKeyword, "echo"),
        (gtStringLit, "\"a"),
        (gtEscapeSequence, "\\"),
        (gtKeyword, "let"),
        (gtIdentifier, "x"),
      ]

suite "syntax_vim - commands and identifiers":
  test "a command takes its bang":
    check tokens("function! s:F() abort") ==
      @[
        (gtKeyword, "function!"),
        (gtFunctionName, "s:F"),
        (gtPunctuation, "("),
        (gtPunctuation, ")"),
        (gtKeyword, "abort"),
      ]

  test "a `!=` after a word is not a bang":
    check kindOf("if x!=y", "!=") == gtOperator

  test "function names after def and <SID>":
    check kindOf("def Foo()", "Foo") == gtFunctionName
    check kindOf("fu <SID>Bar()", "Bar") == gtFunctionName

  test "function attributes only on a function line":
    check kindOf("let dict = {}", "dict") == gtIdentifier

  test "abbreviated commands":
    check kindOf("fu F()", "fu") == gtKeyword
    check kindOf("endf", "endf") == gtKeyword
    check kindOf("exe 'x'", "exe") == gtKeyword
    for cmd in ["endfunct", "setlo sw=2", "autoc BufRead", "synt on", "comm! X y"]:
      check tokens(cmd)[0][0] == gtKeyword

  test "any abbreviation of a command takes on its role":
    check kindOf("funct F()", "F") == gtFunctionName
    check kindOf("nnor x \"_d", "\"_") == gtSpecialVar
    check kindOf("inor x y \" z", "\"") == gtNone
    check kindOf("norma \"_x", "\"_") == gtSpecialVar
    check kindOf("exec \"a\"", "\"a\"") == gtStringLit
    check kindOf("su/a/b/", "/a/b/") == gtRegularExpression

  test "commands are recognized at command position only":
    check kindOf("let set = 1", "set") == gtIdentifier
    check kindOf("echo call", "call") == gtIdentifier

  test "commands missing from earlier tables":
    for cmd in [
      "enew", "args", "join", "read x", "file", "find x", "tag x", "badd x", "bfirst",
      "blast", "mark a", "delmarks!", "chdir x", "nmapclear", "change", "append",
      "insert", "last", "t.", "k a", "visual x", "py3file x", "pyf x", "rubyf x",
      "disassemble F", "breakadd func F", "pop", "bNext", "cN", "amenu x y",
      "anoremenu x y",
    ]:
      check tokens(cmd)[0][0] == gtKeyword

  test "a command name that is also a builtin":
    check kindOf("call map(l, 'v:val')", "map") == gtBuiltin
    check kindOf("map x y", "map") == gtKeyword
    check kindOf("if(1)", "if") == gtKeyword
    check tokens("execute(\"normal! gg\")")[0 .. 2] ==
      @[(gtKeyword, "execute"), (gtPunctuation, "("), (gtStringLit, "\"normal! gg\"")]
    check kindOf("eval(\"x\")->add(l)", "eval") == gtKeyword
    check kindOf("vim9script\nexecute(\"normal! gg\")", "execute") == gtBuiltin

  test "a Vim9 assignment to a command name is an expression":
    check kindOf("vim9script\ns = 'x'", "s") == gtIdentifier
    check kindOf("vim9script\nd[k] = 1", "d") == gtIdentifier
    check kindOf("vim9script\nw ->F()", "w") == gtKeyword

  test "a Vim9 command takes a spaced `=` with no operand on its line":
    check tokens("vim9script\nwincmd = # c\nnnoremap x y")[1 .. ^1] ==
      @[
        (gtKeyword, "wincmd"),
        (gtOperator, "="),
        (gtComment, "# c"),
        (gtKeyword, "nnoremap"),
        (gtIdentifier, "x"),
        (gtIdentifier, "y"),
      ]
    check kindOf("vim9script\nautocmd VimResized * wincmd = # c\necho 1", "echo") ==
      gtKeyword
    check kindOf("vim9script\nwincmd = | echo 1", "wincmd") == gtKeyword
    # Not a variable, whose value may follow on the next line.
    check (gtIdentifier, "echo") in tokens("vim9script\nx = # c\n  echo")

  test "Vim9 has no `:append`, `:t`, `:xit` and the like":
    for word in ["a", "c", "i", "k", "o", "t", "x", "mode", "Print"]:
      check kindOf("vim9script\n" & word, word) == gtIdentifier
      check kindOf("def F()\n  " & word & "\nenddef", word) == gtIdentifier
      check kindOf(word, word) == gtKeyword

  test "a Vim9 statement with a call is an expression even after a command name":
    check kindOf("vim9script\nmap(l,\n  e)", "e") == gtIdentifier
    check kindOf("vim9script\nif(1)", "if") == gtIdentifier
    check kindOf("vim9script\nfoo#Bar(\n  e)", "e") == gtIdentifier

  test "a legacy command before a spaced `=` stays a command":
    check tokens("nnoremap = <C-w>=")[0] == (gtKeyword, "nnoremap")
    check tokens("s = 'x'")[0] == (gtKeyword, "s")

  test "a map of the `=` key in Vim9":
    check tokens("vim9script\nnnoremap = <C-w>=")[1] == (gtKeyword, "nnoremap")

  test "modifiers keep command position":
    check tokens("silent! keepjumps normal! gg") ==
      @[
        (gtKeyword, "silent!"),
        (gtKeyword, "keepjumps"),
        (gtKeyword, "normal!"),
        (gtIdentifier, "gg"),
      ]
    check tokens("hide edit foo \" c") ==
      @[
        (gtKeyword, "hide"),
        (gtKeyword, "edit"),
        (gtIdentifier, "foo"),
        (gtComment, "\" c"),
      ]
    check tokens("hid") == @[(gtKeyword, "hid")]

  test "is and isnot take a match-case suffix":
    check kindOf("if a is# b", "is#") == gtKeyword
    check kindOf("if a isnot? b", "isnot?") == gtKeyword
    check kindOf("for x in l", "in") == gtKeyword

  test "is and in outside an expression are words":
    check kindOf("set is \" c", "is") == gtIdentifier
    check kindOf("xnoremap is iw", "is") == gtIdentifier
    check kindOf("onoremap in :<C-u>normal! vi(<CR>", "in") == gtIdentifier
    check kindOf("nnoremap <expr> x a is b ? 1 : 2", "is") == gtKeyword

  test "scoped and autoload names":
    check kindOf("let s:foo = a:0", "s:foo") == gtIdentifier
    check kindOf("let s:foo = a:0", "a:0") == gtIdentifier
    check kindOf("call plug#begin()", "plug#begin") == gtIdentifier

  test "a scope's dictionary alone":
    check tokens("echo get(g:, 'x')")[1 .. 4] ==
      @[
        (gtBuiltin, "get"),
        (gtPunctuation, "("),
        (gtIdentifier, "g:"),
        (gtPunctuation, ","),
      ]
    for (code, scope) in [
      ("echo keys(b:)", "b:"),
      ("echo s:[k]", "s:"),
      ("echo w:->keys()", "w:"),
      ("let d = t:", "t:"),
    ]:
      check (gtIdentifier, scope) in tokens(code)
    # Not an operator, which would continue the expression.
    check kindOf("vim9script\nvar all = g:\necho 1", "echo") == gtKeyword
    check kindOf("vim9script\nvar all = g:  \necho 1", "echo") == gtKeyword

  test "a one-letter dict key or typed name is not a scope":
    check tokens("let d = #{b: 2}")[5 .. 7] ==
      @[(gtIdentifier, "b"), (gtPunctuation, ":"), (gtDecNumber, "2")]
    check tokens("vim9script\nvar s: string")[2 .. 4] ==
      @[(gtIdentifier, "s"), (gtPunctuation, ":"), (gtTypeName, "string")]

  test "v: variables":
    check kindOf("echo v:count", "v:count") == gtSpecialVar
    check kindOf("echo v:true", "v:true") == gtBoolean
    check kindOf("echo v:null", "v:null") == gtBoolean

  test "booleans and special variables":
    check kindOf("return true", "true") == gtBoolean
    check kindOf("return null_list", "null_list") == gtBoolean
    check kindOf("echo this.x", "this") == gtSpecialVar

  test "vim9script makes the rest of the buffer Vim9":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("vim9script\n")
    while true:
      g.getNextToken(langVim)
      if g.kind == gtEof:
        break
    check g.lang.vim.vim9

suite "syntax_vim - special tokens":
  test "options":
    check kindOf("let &tabstop = 4", "&tabstop") == gtPreprocessor
    check kindOf("let &l:sw = 2", "&l:sw") == gtPreprocessor
    check kindOf("if a && b", "&&") == gtOperator

  test "environment variables":
    check kindOf("let p = $HOME", "$HOME") == gtPreprocessor

  test "a syntax cluster is not a register":
    check tokens("syn match Foo /x/ contains=@Spell,@No_Spell2")[^3 .. ^1] ==
      @[(gtSpecialVar, "@Spell"), (gtPunctuation, ","), (gtSpecialVar, "@No_Spell2")]
    check kindOf("syn include @Lua syntax/lua.vim", "@Lua") == gtSpecialVar
    # Keys run a register and go on: `@q` then `j`.
    check tokens("normal! @qj")[1 .. ^1] == @[(gtSpecialVar, "@q"), (gtIdentifier, "j")]
    check tokens("nnoremap Q @qj")[^2 .. ^1] ==
      @[(gtSpecialVar, "@q"), (gtIdentifier, "j")]

  test "registers":
    check kindOf("let @a = ''", "@a") == gtSpecialVar
    check tokens("echo @\" .. x") ==
      @[
        (gtKeyword, "echo"),
        (gtSpecialVar, "@\""),
        (gtOperator, ".."),
        (gtIdentifier, "x"),
      ]

  test "key notation":
    for key in ["<CR>", "<C-w>", "<leader>", "<F12>", "<S-Tab>", "<C-]>", "<Plug>"]:
      check kindOf("nnoremap x " & key, key) == gtSpecialVar

  test "click counts, keypad, character codes and other keys":
    for key in [
      "<2-LeftMouse>", "<S-4-RightMouse>", "<kEnter>", "<k0>", "<kPlus>", "<Char-65>",
      "<Char-0x41>", "<Char-0101>", "<Char-0b1000001>", "<S-Char-114>", "<Ignore>",
      "<RightDrag>", "<X1Mouse>", "<MiddleRelease>", "<FocusGained>", "<register>",
    ]:
      check tokens("nnoremap " & key & " x")[1] == (gtSpecialVar, key)
    # Neither Vim nor Neovim knows these.
    for code in ["<5-LeftMouse>", "<Char-x>", "<Char-0x>", "<EOL>"]:
      check tokens("nnoremap " & code & " x")[1] == (gtOperator, "<")

  test "a `<` that is not key notation is an operator":
    check tokens("if a<b") ==
      @[(gtKeyword, "if"), (gtIdentifier, "a"), (gtOperator, "<"), (gtIdentifier, "b")]
    check kindOf("let x = a <foo> b", "<") == gtOperator

  test "hex colors":
    check kindOf("hi Comment guifg=#808080", "#808080") == gtHexNumber
    check kindOf("hi Comment guifg=#808080", "=") == gtOperator

  test "a line continuation":
    check tokens("let l = [\n  \\ \"a\",\n  \\ ]") ==
      @[
        (gtKeyword, "let"),
        (gtIdentifier, "l"),
        (gtOperator, "="),
        (gtPunctuation, "["),
        (gtSpecialVar, "\\"),
        (gtStringLit, "\"a\""),
        (gtPunctuation, ","),
        (gtSpecialVar, "\\"),
        (gtPunctuation, "]"),
      ]

  test "a backslash mid-line escapes one character":
    check kindOf("set stl=%f\\ %m", "\\ ") == gtEscapeSequence

suite "syntax_vim - mappings":
  test "registers in a map's keys":
    check tokens("xnoremap p \"_dP") ==
      @[
        (gtKeyword, "xnoremap"),
        (gtIdentifier, "p"),
        (gtSpecialVar, "\"_"),
        (gtIdentifier, "dP"),
      ]

  test "a `\"` in a map's rhs is not a comment":
    check kindOf("nnoremap x y \" z", "\"") == gtNone

  test "a `:cmd` in a map's rhs is a command":
    check tokens("nnoremap <leader>x :call F(\"a\")<CR>\"_x") ==
      @[
        (gtKeyword, "nnoremap"),
        (gtSpecialVar, "<leader>"),
        (gtIdentifier, "x"),
        (gtPunctuation, ":"),
        (gtKeyword, "call"),
        (gtIdentifier, "F"),
        (gtPunctuation, "("),
        (gtStringLit, "\"a\""),
        (gtPunctuation, ")"),
        (gtSpecialVar, "<CR>"),
        (gtSpecialVar, "\"_"),
        (gtIdentifier, "x"),
      ]

  test "an operator character does not take the `<` of a key after it":
    check tokens("nnoremap x :!python3 %<CR>\"_x")[^4 .. ^1] ==
      @[
        (gtOperator, "%"),
        (gtSpecialVar, "<CR>"),
        (gtSpecialVar, "\"_"),
        (gtIdentifier, "x"),
      ]
    check kindOf("nnoremap x :e .<CR>", "<CR>") == gtSpecialVar
    check tokens("inoremap <C-x> <C-r>=<C-r>\"<CR>")[3 .. 4] ==
      @[(gtOperator, "="), (gtSpecialVar, "<C-r>")]

  test "`:normal` keys take a `|`":
    check kindOf("normal! 0|x", "x") == gtIdentifier
    check kindOf("nnoremap a 0|x", "x") == gtKeyword

  test "a `$` in keys is the motion":
    check kindOf("nnoremap Y y$h", "$") == gtOperator
    check kindOf("normal! $h", "$") == gtOperator
    check kindOf("nnoremap x :e $HOME<CR>", "$HOME") == gtPreprocessor

  test "a comment in a map's `:cmd` ends with the command line":
    let ts = tokens("nnoremap x :e foo \" c<CR>\"_x")
    check (gtComment, "\" c") in ts
    check (gtSpecialVar, "<CR>") in ts
    check (gtSpecialVar, "\"_") in ts
    check kindOf("nnoremap x :e foo \" a \\| b<CR>x", "\" a \\| b") == gtComment
    check tokens("nnoremap x :e foo \" c | echo 1")[^2] == (gtKeyword, "echo")

  test "`\\|` and <Bar> separate commands in a map's `:cmd`":
    for bar in ["\\|", "<Bar>"]:
      let ts = tokens("nnoremap x :w " & bar & " echo \"done\"<CR>")
      check (gtKeyword, "echo") in ts
      check (gtStringLit, "\"done\"") in ts
    check kindOf("nnoremap x 0\\|w", "w") == gtIdentifier
    check kindOf("nnoremap x :!ls \\| w<CR>", "w") == gtIdentifier

  test "a map's command line is legacy script in Vim9":
    let ts = tokens("vim9script\nnnoremap x :call F() \" c<CR>\"_x")
    check (gtComment, "\" c") in ts
    check (gtSpecialVar, "<CR>") in ts
    check (gtSpecialVar, "\"_") in ts
    check kindOf("vim9script\nnnoremap x :w \\| \" c<CR>", "\" c") == gtComment
    check kindOf("vim9script\nnnoremap x <Cmd>let g:a = 1 \" c<CR>", "\" c") == gtComment
    check kindOf("vim9script\nnnoremap x <ScriptCmd>F() # c<CR>", "# c") == gtComment
    check kindOf("vim9script\nnnoremap x :w<CR> | # c", "# c") == gtComment

  test "a heredoc in typed keys opens none":
    for line in [
      "nnoremap x :let a =<< END<CR>", "nnoremap x <Cmd>lua << EOF<CR>",
      "nnoremap x :echo 1 \\| let a =<< END<CR>", "nnoremap x :g/a/let b =<< END<CR>",
      "nnoremap x :autocmd BufRead * let a =<< END<CR>", "normal! :let x =<< END",
      "normal! :g/a/let b =<< END", "normal! :echo 1 | let a =<< END",
      "vim9script\nnnoremap x <ScriptCmd>var a =<< END<CR>",
    ]:
      check stateAfter(line).heredocMarker == ""
      check tokens(line & "\necho \"s\"")[^2 .. ^1] ==
        @[(gtKeyword, "echo"), (gtStringLit, "\"s\"")]

  test "commands in typed keys open no body and keep the file's syntax":
    check stateAfter("nnoremap x :function F()<CR>").bodies == ""
    check stateAfter("normal! :function F()").bodies == ""
    check stateAfter("function F()\nnnoremap x :endfunction<CR>").bodies == "f"
    check stateAfter("vim9script\ndef F()\nnnoremap x <ScriptCmd>enddef<CR>").bodies ==
      "d"
    check not stateAfter("nnoremap x :vim9script<CR>").vim9
    check not stateAfter("nnoremap x :interface I<CR>").inInterface
    check kindOf("vim9script\nnnoremap x :function F()<CR>\n# c", "# c") == gtComment
    check kindOf("nnoremap x :vim9script<CR>\n\" c", "\" c") == gtComment

  test "a command a map's `:cmd` wraps returns to keys at <CR>":
    check kindOf("nnoremap x :autocmd BufRead * echo 1<CR>\"_x", "\"_") == gtSpecialVar
    check kindOf("nnoremap x :command! F echo 1<CR>\"_x", "\"_") == gtSpecialVar

  test "a key that leaves a map's `:cmd` ends :autocmd's or :command's arguments":
    for rhs in [
      ":autocmd<CR>", ":command<CR>", ":command -bang<CR>", ":au BufRead<Esc>"
    ]:
      check tokens("nnoremap x " & rhs & "\"_dd")[^2 .. ^1] ==
        @[(gtSpecialVar, "\"_"), (gtIdentifier, "dd")]
    check tokens("nnoremap x :au BufRead<CR>")[^2 .. ^1] ==
      @[(gtTypeName, "BufRead"), (gtSpecialVar, "<CR>")]
    check kindOf("nnoremap x :au BufRead *<Bar>echo 1<CR>", "echo") == gtKeyword
    check tokens("nnoremap x :command -complete=customlist,<SID>C F echo<CR>")[4 .. 5] ==
      @[(gtSpecialVar, "-complete=customlist,<SID>C"), (gtFunctionName, "F")]

  test "<CR> drops what a map's `:cmd` set":
    check kindOf("vim9script\nnnoremap x :echo 1<CR>\n  # c\n  \\ \"ayy", "\"a") ==
      gtSpecialVar

  test "brackets in typed keys do not span lines":
    check kindOf("vim9script\nnormal! :call F(\necho 1", "echo") == gtKeyword
    check stateAfter("vim9script\nnnoremap x <ScriptCmd>if 1 {<CR>").brackets == ""

  test "after <Esc> too":
    check kindOf("inoremap jj <Esc>:w<CR>", "w") == gtKeyword

  test "<Esc> leaves a map's `:cmd` for its keys":
    check tokens("nnoremap x :echo 1<Esc>\"_dd")[^3 .. ^1] ==
      @[(gtSpecialVar, "<Esc>"), (gtSpecialVar, "\"_"), (gtIdentifier, "dd")]
    check kindOf("nnoremap x :!ls<Esc>\"_x", "\"_") == gtSpecialVar
    check kindOf("nnoremap x :e foo \" c<Esc>\"_x", "\"_") == gtSpecialVar

  test "<Cmd> starts a command":
    check kindOf("nnoremap x <Cmd>echo \"a\"<CR>", "echo") == gtKeyword
    check kindOf("nnoremap x <Cmd>echo \"a\"<CR>", "\"a\"") == gtStringLit

  test "an <expr> map's rhs is an expression":
    check tokens("inoremap <expr> <CR> pumvisible() ? \"\\<C-y>\" : \"\\<CR>\"") ==
      @[
        (gtKeyword, "inoremap"),
        (gtSpecialVar, "<expr>"),
        (gtSpecialVar, "<CR>"),
        (gtBuiltin, "pumvisible"),
        (gtPunctuation, "("),
        (gtPunctuation, ")"),
        (gtOperator, "?"),
        (gtStringLit, "\""),
        (gtEscapeSequence, "\\<C-y>"),
        (gtStringLit, "\""),
        (gtPunctuation, ":"),
        (gtStringLit, "\""),
        (gtEscapeSequence, "\\<CR>"),
        (gtStringLit, "\""),
      ]

  test "a dict's `:` does not start a command":
    check kindOf("let d = {'a': \"b\"}", "\"b\"") == gtStringLit

  test "a ternary's or a slice's `:` does not start a command":
    check tokens("let x = c ? a :b \" c")[^2 .. ^1] ==
      @[(gtIdentifier, "b"), (gtComment, "\" c")]
    check kindOf("let y = x[i :j]", "j") == gtIdentifier

  test "keys after a map's `:` edit the command line":
    check tokens("nnoremap x :<C-u>call Foo(\"a\")<CR>\"_x") ==
      @[
        (gtKeyword, "nnoremap"),
        (gtIdentifier, "x"),
        (gtPunctuation, ":"),
        (gtSpecialVar, "<C-u>"),
        (gtKeyword, "call"),
        (gtIdentifier, "Foo"),
        (gtPunctuation, "("),
        (gtStringLit, "\"a\""),
        (gtPunctuation, ")"),
        (gtSpecialVar, "<CR>"),
        (gtSpecialVar, "\"_"),
        (gtIdentifier, "x"),
      ]

  test "a range after a map's `:` starts its command line":
    for rhs in [":1,3d", ":.,$d", ":+3d", ":-1d", ":$d", ":,$d", ":.;+2d"]:
      check kindOf("nnoremap x " & rhs & "<CR>", "d") == gtKeyword
      check kindOf("vim9script\nnnoremap x " & rhs & "<CR>", "d") == gtKeyword
    check kindOf("normal! :1,3d", "d") == gtKeyword
    check tokens("nnoremap : ;")[^1] == (gtPunctuation, ";")

  test "an <expr> map's rhs may start with a string":
    check kindOf("inoremap <expr> <C-j> \"\\<C-n>\"", "\"") == gtStringLit
    check kindOf("nnoremap <expr> n \"Nn\"[v:searchforward]", "\"Nn\"") == gtStringLit

  test "an <expr> map's lhs is keys":
    check tokens("inoremap <expr> \" Pair('\"')")[2 .. ^1] ==
      @[
        (gtNone, "\""),
        (gtIdentifier, "Pair"),
        (gtPunctuation, "("),
        (gtStringLit, "'\"'"),
        (gtPunctuation, ")"),
      ]
    check tokens("inoremap <expr> ' getline('.')")[2 .. 4] ==
      @[(gtNone, "'"), (gtBuiltin, "getline"), (gtPunctuation, "(")]
    for map in [
      "nnoremap <expr> <silent> x \"a\"", "nnoremap <expr><silent> x \"a\"",
      "nnoremap <expr>x \"a\"", "nnoremap <expr>\n      \\ x \"a\"",
    ]:
      check tokens(map)[^2 .. ^1] == @[(gtIdentifier, "x"), (gtStringLit, "\"a\"")]

  test "a continued line where a command is expected starts one":
    let ts =
      tokens("command! Foo\n      \\ if 1 |\n      \\   echo \"x\" |\n      \\ endif")
    for name in ["if", "echo", "endif"]:
      check (gtKeyword, name) in ts
    check (gtStringLit, "\"x\"") in ts
    check kindOf("silent!\n      \\ call F()", "call") == gtKeyword
    check kindOf("windo\n      \\ set nowrap", "set") == gtKeyword

  test "a continued map keeps its flags":
    check tokens("nnoremap <silent> x\n      \\ :call Foo()<CR>\"_x")[^2] ==
      (gtSpecialVar, "\"_")
    check kindOf("function! F()\n      \\ abort", "abort") == gtKeyword
    check kindOf("function!\n      \\ F()", "F") == gtFunctionName

  test "a comment line between continued lines":
    check tokens("nnoremap x\n      \"\\ c\n      \\ \"ayy")[2 .. ^1] ==
      @[
        (gtComment, "\"\\ c"),
        (gtSpecialVar, "\\"),
        (gtSpecialVar, "\"a"),
        (gtIdentifier, "yy"),
      ]
    check kindOf("vim9script\nnnoremap x\n  # c\n  \\ \"ayy", "\"a") == gtSpecialVar

suite "syntax_vim - commands that wrap a command":
  test ":autocmd's event, pattern and command":
    check tokens("autocmd VimEnter * echo \"Welcome\"") ==
      @[
        (gtKeyword, "autocmd"),
        (gtTypeName, "VimEnter"),
        (gtNone, "*"),
        (gtKeyword, "echo"),
        (gtStringLit, "\"Welcome\""),
      ]
    check kindOf("au BufReadPost * exe \"normal! g`\\\"\"", "exe") == gtKeyword

  test ":autocmd with a group, an event list and options":
    check tokens("autocmd MyGroup BufRead,BufNewFile *.vim setlocal sw=2")[0 .. 4] ==
      @[
        (gtKeyword, "autocmd"),
        (gtIdentifier, "MyGroup"),
        (gtTypeName, "BufRead,BufNewFile"),
        (gtNone, "*.vim"),
        (gtKeyword, "setlocal"),
      ]
    check tokens("au BufEnter <buffer> ++once nested echo 1")[2 .. 5] ==
      @[
        (gtSpecialVar, "<buffer>"),
        (gtSpecialVar, "++once"),
        (gtSpecialVar, "nested"),
        (gtKeyword, "echo"),
      ]

  test "event names ignore case":
    check kindOf("au bufread * set ts=2", "bufread") == gtTypeName

  test "a `|` ends :autocmd's arguments":
    check tokens("augroup mine | au! BufRead | augroup END")[^2] ==
      (gtKeyword, "augroup")

  test "a continued :autocmd":
    check kindOf("autocmd BufRead *\n      \\ echo \"x\"", "echo") == gtKeyword

  test ":command's attributes, name and replacement":
    check tokens("command! Hi echo \"hi\"") ==
      @[
        (gtKeyword, "command!"),
        (gtFunctionName, "Hi"),
        (gtKeyword, "echo"),
        (gtStringLit, "\"hi\""),
      ]
    check tokens("com -nargs=1 -bang Foo call F(<q-args>)")[0 .. 4] ==
      @[
        (gtKeyword, "com"),
        (gtSpecialVar, "-nargs=1"),
        (gtSpecialVar, "-bang"),
        (gtFunctionName, "Foo"),
        (gtKeyword, "call"),
      ]

  test "a :windo command":
    check kindOf("windo set nowrap", "set") == gtKeyword
    check kindOf("bufdo update", "update") == gtKeyword

  test "a modifier or range placeholder leaves :command's command to follow":
    check kindOf("command! -nargs=1 Foo <mods> split <args>", "split") == gtKeyword
    let ts = tokens("command! -range=% Foo <line1>,<line2>s/a/b/")
    check (gtKeyword, "s") in ts
    check (gtRegularExpression, "/a/b/") in ts
    check kindOf("command! Foo <args> x", "x") == gtIdentifier

suite "syntax_vim - shell commands":
  test "a shell command takes `\"`":
    check kindOf("!echo \"hi\"", "\"hi\"") == gtStringLit
    check kindOf("w !sudo tee \"%\"", "\"%\"") == gtStringLit
    check kindOf("r !ls \"a\"", "\"a\"") == gtStringLit
    check kindOf("r!ls \"a\"", "\"a\"") == gtStringLit
    check kindOf("'<,'>!sort \"a\"", "\"a\"") == gtStringLit
    check kindOf("silent !ls \"a\"", "\"a\"") == gtStringLit

  test "a shell command takes `|` and `#`":
    check kindOf("!ls | x", "x") == gtIdentifier
    check kindOf("vim9script\n!ls # x", "#") == gtOperator

  test "a comment follows a file name":
    check kindOf("w foo \" c", "\" c") == gtComment
    check kindOf("w! foo \" c", "\" c") == gtComment

  test "a map's shell command ends at <CR>":
    check kindOf("nnoremap x :!echo \"hi\"<CR>", "\"hi\"") == gtStringLit
    check kindOf("nnoremap x :!ls<CR>\"_x", "\"_") == gtSpecialVar
    check kindOf("nnoremap a :!ls|x", "x") == gtKeyword

  test "a script command's code takes `|` and `#`":
    for cmd in ["lua", "python3", "py3", "perl", "ruby", "tcl", "luado", "py3do"]:
      check kindOf(cmd & " x = a | endif", "endif") == gtIdentifier
    check kindOf("vim9script\nlua x = #t", "#") == gtOperator
    check kindOf("nnoremap x :lua f()<Bar>echo 1<CR>\"_x", "echo") == gtIdentifier
    check kindOf("nnoremap x :lua f()<Bar>echo 1<CR>\"_x", "\"_") == gtSpecialVar
    check kindOf("nnoremap x :lua f()<CR> | echo 1", "echo") == gtKeyword

suite "syntax_vim - patterns and ranges":
  test "a substitute's pattern and replacement":
    check tokens("%s/\"a\"/b/g") ==
      @[
        (gtOperator, "%"),
        (gtKeyword, "s"),
        (gtRegularExpression, "/\"a\"/b/"),
        (gtIdentifier, "g"),
      ]

  test "an escaped delimiter stays in the pattern":
    check kindOf("s/a\\/b/c/", "/a\\/b/c/") == gtRegularExpression

  test "a delimiter inside a collection stays in the pattern":
    check tokens("s/[/]/-/g") ==
      @[(gtKeyword, "s"), (gtRegularExpression, "/[/]/-/"), (gtIdentifier, "g")]
    for pat in [
      "/[^/]/", "/[]/]/", "/[\\]/]/", "/[a-/]/", "/[[:alpha:]/]/", "/[[=a=]/]/",
      "/\\v[/]/", "/\\V\\[/]/",
    ]:
      check tokens("g" & pat & "d") ==
        @[(gtKeyword, "g"), (gtRegularExpression, pat), (gtKeyword, "d")]
    check tokens("syn match Foo \"\\\\[\"\\\\/bfnrt]\" contained")[3 .. ^1] ==
      @[(gtRegularExpression, "\"\\\\[\"\\\\/bfnrt]\""), (gtIdentifier, "contained")]

  test "a `[` that is not a collection":
    # `\V` makes it literal; the replacement has no collections.
    check tokens("g/\\V[/d") ==
      @[(gtKeyword, "g"), (gtRegularExpression, "/\\V[/"), (gtKeyword, "d")]
    check tokens("s/a/[/g") ==
      @[(gtKeyword, "s"), (gtRegularExpression, "/a/[/"), (gtIdentifier, "g")]
    # Vim takes the rest of the line as the pattern of an unclosed one.
    check tokens("s/a[/b/") == @[(gtKeyword, "s"), (gtRegularExpression, "/a[/b/")]

  test "a command follows :g's pattern":
    check tokens("g!/^$/d") ==
      @[(gtKeyword, "g!"), (gtRegularExpression, "/^$/"), (gtKeyword, "d")]

  test "`#`, `:` and `!` delimiters":
    check tokens("s#a#b#g") ==
      @[(gtKeyword, "s"), (gtRegularExpression, "#a#b#"), (gtIdentifier, "g")]
    check tokens("g#pat#d") ==
      @[(gtKeyword, "g"), (gtRegularExpression, "#pat#"), (gtKeyword, "d")]
    check tokens("%s:a:b:g")[1 .. 2] ==
      @[(gtKeyword, "s"), (gtRegularExpression, ":a:b:")]
    check tokens("s!a!b!") == @[(gtKeyword, "s"), (gtRegularExpression, "!a!b!")]

  test ":smagic and :snomagic take a substitute's pattern":
    check tokens("sm/\"/x/g") ==
      @[(gtKeyword, "sm"), (gtRegularExpression, "/\"/x/"), (gtIdentifier, "g")]
    check tokens("sno!a!b!") == @[(gtKeyword, "sno"), (gtRegularExpression, "!a!b!")]
    check tokens("smagic#a#b#") ==
      @[(gtKeyword, "smagic"), (gtRegularExpression, "#a#b#")]

  test ":match's pattern follows its group":
    check tokens("match ErrorMsg /\"/ \" c") ==
      @[
        (gtKeyword, "match"),
        (gtIdentifier, "ErrorMsg"),
        (gtRegularExpression, "/\"/"),
        (gtComment, "\" c"),
      ]
    check kindOf("2match Foo \"x\"", "\"x\"") == gtRegularExpression
    check kindOf("3match Foo /x/", "/x/") == gtRegularExpression
    check kindOf("match none \" c", "\" c") == gtComment
    check kindOf("match \" c", "\" c") == gtComment
    check kindOf("nnoremap x :match Foo /\"/<CR>", "/\"/") == gtRegularExpression

  test ":sort's pattern among its flags":
    check tokens("sort! n /\"/ u \" c") ==
      @[
        (gtKeyword, "sort!"),
        (gtIdentifier, "n"),
        (gtRegularExpression, "/\"/"),
        (gtIdentifier, "u"),
        (gtComment, "\" c"),
      ]
    check kindOf("sort u \" c", "\" c") == gtComment
    check kindOf("'<,'>sort/\\d/", "/\\d/") == gtRegularExpression
    # Vim9 reads a `#` there as a delimiter, not a comment.
    check kindOf("vim9script\nsort # c", "# c") == gtRegularExpression
    check kindOf("nnoremap x :sort<CR>/\"<CR>", "/") == gtOperator

  test ":vimgrep's pattern":
    check tokens("vimgrep /\"/gj %") ==
      @[
        (gtKeyword, "vimgrep"),
        (gtRegularExpression, "/\"/"),
        (gtIdentifier, "gj"),
        (gtOperator, "%"),
      ]
    check kindOf("lvimgrepadd! \"x\" %", "\"x\"") == gtRegularExpression
    check kindOf("lvimgrep foo /x", "/") == gtOperator
    # A key is no delimiter.
    check kindOf("nnoremap x :vimgrep <C-r><C-w> %<CR>", "<C-r>") == gtSpecialVar
    check kindOf("nnoremap x :s<CR>", "<CR>") == gtSpecialVar

  test "Vim9 scoped and autoload names at a statement's start":
    check tokens("vim9script\ng:x = 1")[1] == (gtIdentifier, "g:x")
    check tokens("vim9script\ns#F()")[1] == (gtIdentifier, "s#F")
    check tokens("vim9script\n:g:x:d")[2 .. ^1] ==
      @[(gtKeyword, "g"), (gtRegularExpression, ":x:"), (gtKeyword, "d")]

  test "a scoped name after <ScriptCmd>, a `:g` after <Cmd> or a mark":
    let ts = tokens("vim9script\nnnoremap x <ScriptCmd>g:r = \"a\"<CR>")
    check (gtIdentifier, "g:r") in ts
    check (gtStringLit, "\"a\"") in ts
    check kindOf("vim9script\nnnoremap x <Cmd>g:a:d<CR>", "g") == gtKeyword
    check kindOf("vim9script\n:'<,'>g:a:d", "g") == gtKeyword

  test "a command follows :filter's pattern":
    check tokens("filter /(/ ls") ==
      @[(gtKeyword, "filter"), (gtRegularExpression, "/(/"), (gtKeyword, "ls")]

  test ":syntax match and region patterns":
    check tokens("syntax match Foo /\"x\"/ \" c")[^2 .. ^1] ==
      @[(gtRegularExpression, "/\"x\"/"), (gtComment, "\" c")]
    check tokens("syn match Foo \"pat\" contained \" c")[3 .. ^1] ==
      @[
        (gtRegularExpression, "\"pat\""),
        (gtIdentifier, "contained"),
        (gtComment, "\" c"),
      ]
    check tokens("syn region S start=+\"+ skip=/\\\\\"/ end=+\"+ \" c")[3 .. ^1] ==
      @[
        (gtIdentifier, "start="),
        (gtRegularExpression, "+\"+"),
        (gtIdentifier, "skip="),
        (gtRegularExpression, "/\\\\\"/"),
        (gtIdentifier, "end="),
        (gtRegularExpression, "+\"+"),
        (gtComment, "\" c"),
      ]
    check kindOf("syn sync match Foo grouphere NONE \"x\"", "\"x\"") ==
      gtRegularExpression

  test "a :syntax keyword's words are not subcommands":
    check tokens("syn keyword Foo match region \" c")[^1] == (gtComment, "\" c")

  test ":catch's pattern":
    check kindOf("catch /E\"1/", "/E\"1/") == gtRegularExpression

  test "a spaced `#` after a Vim9 :catch is a comment, which catches all":
    check kindOf("vim9script\ncatch # all", "# all") == gtComment
    check kindOf("vim9script\ncatch #E1#", "#E1#") == gtComment
    check kindOf("vim9script\ncatch /E1/", "/E1/") == gtRegularExpression
    check kindOf("catch #E1#", "#E1#") == gtRegularExpression
    check kindOf("vim9script\nlegacy catch #E1#", "#E1#") == gtRegularExpression
    check kindOf("vim9script\nfilter #ls# ls", "#ls#") == gtRegularExpression

  test "marks in a range":
    check tokens("'<,'>sort") ==
      @[
        (gtSpecialVar, "'<"),
        (gtPunctuation, ","),
        (gtSpecialVar, "'>"),
        (gtKeyword, "sort"),
      ]

  test "a one-character string is not a mark":
    check tokens("'a'") == @[(gtStringLit, "'a'")]

  test "a Vim9 range needs a colon":
    check kindOf("vim9script\n$FOO = 'x'", "$FOO") == gtPreprocessor
    check kindOf("vim9script\n:1,$d", "$") == gtOperator

  test "a line-number range":
    check tokens("1,$d") ==
      @[(gtDecNumber, "1"), (gtPunctuation, ","), (gtOperator, "$"), (gtKeyword, "d")]

suite "syntax_vim - numbers":
  test "radix prefixes":
    check kindOf("let x = 0x1F", "0x1F") == gtHexNumber
    check kindOf("let x = 0b101", "0b101") == gtBinNumber
    check kindOf("let x = 0o17", "0o17") == gtOctNumber
    check kindOf("let x = 0zFF00.AA", "0zFF00.AA") == gtHexNumber
    check tokens("let x = 0zFF.")[^2 .. ^1] ==
      @[(gtHexNumber, "0zFF"), (gtOperator, ".")]
    check tokens("let x = 0z.")[3] == (gtDecNumber, "0")

  test "floats need digits on both sides of the dot":
    check kindOf("let x = 1.5e-3", "1.5e-3") == gtFloatNumber
    check tokens("echo 1..2") ==
      @[(gtKeyword, "echo"), (gtDecNumber, "1"), (gtOperator, ".."), (gtDecNumber, "2")]

  test "quote separators in Vim9 only":
    check kindOf("vim9script\nvar x = 1'000'000", "1'000'000") == gtDecNumber
    check tokens("let x = 1'0")[3] == (gtDecNumber, "1")
    check tokens("vim9script\nnnoremap a 1'2")[3] == (gtDecNumber, "1")
    check kindOf("vim9script\nvar x = 0xff'ff", "0xff'ff") == gtHexNumber
    check kindOf("vim9script\nvar x = 0b1'0", "0b1'0") == gtBinNumber

  test "a legacy leading zero is octal in an expression or an option":
    check kindOf("let x = 017", "017") == gtOctNumber
    check kindOf("set ts=010", "010") == gtOctNumber
    check kindOf("let x = 019", "019") == gtDecNumber
    check kindOf("let x = 017.5", "017.5") == gtFloatNumber
    check kindOf("vim9script\nvar x = 017", "017") == gtDecNumber
    check kindOf(".,010d", "010") == gtDecNumber
    check kindOf("normal! 017j", "017") == gtDecNumber

  test "a prefix without digits is a plain zero":
    check tokens("echo 0x")[1] == (gtDecNumber, "0")

suite "syntax_vim - heredoc":
  test "a let heredoc body is a string":
    check tokens("  let x =<< trim END\n    a \"b\"\n  END\necho 1") ==
      @[
        (gtKeyword, "let"),
        (gtIdentifier, "x"),
        (gtOperator, "=<<"),
        (gtKeyword, "trim"),
        (gtKeyword, "END"),
        (gtLongStringLit, "a \"b\""),
        (gtKeyword, "END"),
        (gtKeyword, "echo"),
        (gtDecNumber, "1"),
      ]

  test "without trim the marker must start the line":
    check tokens("let x =<< END\n  END\nEND") ==
      @[
        (gtKeyword, "let"),
        (gtIdentifier, "x"),
        (gtOperator, "=<<"),
        (gtKeyword, "END"),
        (gtLongStringLit, "END"),
        (gtKeyword, "END"),
      ]

  test "a trim heredoc's marker takes the :let line's indent or none":
    let body = proc(code: string): seq[string] =
      for t in tokens(code):
        if t.kind == gtLongStringLit:
          result.add t.text
    check body("  let x =<< trim END\n    a\n      END\n    b\n  END\nc") ==
      @["a", "END", "b"]
    check body("let y =<< trim END\n  a\n  END\nb\nEND\nc") == @["a", "END", "b"]
    check body("  let z =<< trim END\n    a\nEND\nc") == @["a"]
    check body("\tlet w =<< trim END\n\t  a\n  END\n\tEND\nc") == @["a", "END"]

  test "a trim heredoc on a continuation line takes the :let line's indent":
    let body = proc(code: string): seq[string] =
      for t in tokens(code):
        if t.kind == gtLongStringLit:
          result.add t.text
    check body("  let x\n        \\ =<< trim END\n    a\n        END\n  END\nc") ==
      @["a", "END"]
    check body("  let x\n  \"\\ c\n        \\ =<< trim END\n    a\n  END\nc") == @["a"]

  test "a script heredoc":
    check tokens("lua << EOF\nprint('x') -- c\nEOF") ==
      @[
        (gtKeyword, "lua"),
        (gtOperator, "<<"),
        (gtKeyword, "EOF"),
        (gtLongStringLit, "print('x') -- c"),
        (gtKeyword, "EOF"),
      ]

  test "a script heredoc's marker defaults to a dot":
    check tokens("python3 <<\nx = 1\n.") ==
      @[
        (gtKeyword, "python3"),
        (gtOperator, "<<"),
        (gtLongStringLit, "x = 1"),
        (gtKeyword, "."),
      ]

  test "`<<` outside a script command is a plain operator":
    check tokens("echo a << b\nlet x")[^2] == (gtKeyword, "let")

  test "a script command's `<<` must come first":
    check tokens("python3 x = 1 << 4\nlet y")[^2] == (gtKeyword, "let")
    check tokens("lua print(1 << 2)\nlet y")[^2] == (gtKeyword, "let")

  test "`=<<` opens a heredoc only after an assignment target":
    check tokens("nnoremap <leader>=<< gg=G\n\" c")[^1] == (gtComment, "\" c")
    check tokens("let x = a =<< b\n\" c")[^1] == (gtComment, "\" c")

  test "Vim9 heredoc assignments":
    check kindOf("vim9script\nvar l: list<string> =<< END\na\nEND", "a") ==
      gtLongStringLit
    check kindOf("vim9script\nl =<< END\na\nEND", "a") == gtLongStringLit
    check kindOf("vim9script\ne =<< END\na\nEND", "a") == gtLongStringLit

  test "a word after the marker is not a heredoc header":
    check tokens("let x =<< END junk\n\" c")[^1] == (gtComment, "\" c")

  test "a comment after the marker":
    for (code, comment) in [
      ("let x =<< END \" c\na\nEND", "\" c"),
      ("lua << EOF \" c\na\nEOF", "\" c"),
      ("vim9script\nvar x =<< END # c\na\nEND", "# c"),
    ]:
      check kindOf(code, comment) == gtComment
      check kindOf(code, "a") == gtLongStringLit
    check kindOf("vim9script\nvar x =<< END \" c\na", "a") == gtIdentifier

  test "a let heredoc's marker cannot start with a lowercase letter":
    check tokens("let x =<< end\nlet y = 1")[4] == (gtKeyword, "let")
    check kindOf("lua << eof\na\neof", "a") == gtLongStringLit

  test "a blank line and an unterminated body":
    check tokens("let x =<< END\n\n\" a\n") ==
      @[
        (gtKeyword, "let"),
        (gtIdentifier, "x"),
        (gtOperator, "=<<"),
        (gtKeyword, "END"),
        (gtLongStringLit, "\" a"),
      ]

suite "syntax_vim - language lookup":
  test "names and aliases":
    for name in ["Vimscript", "vimscript", "vim", "viml", "vim9"]:
      check getSourceLanguage(name) == langVim

  test "filetype token":
    check sourceLanguageToFiletype[langVim] == "vim"
