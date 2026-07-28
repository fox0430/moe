#=====================================================
#Nim -- a Compiler for Nim. https://nim-lang.org/
#
#Copyright (C) 2006-2020 Andreas Rumpf. All rights reserved.
#
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in
#all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#THE SOFTWARE.
#
#[ MIT license: http://www.opensource.org/licenses/mit-license.php ]#
#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Source highlighter for programming or markup languages.
## Currently only few languages are supported, other languages may be added.
## The interface supports one language nested in another.
##
## **Note:** Import ``packages/docutils/highlite`` to use this module
##
## You can use this to build your own syntax highlighting, check this example:
##
## .. code::nim
##   let code = """for x in $int.high: echo x.ord mod 2 == 0"""
##   var toknizr: GeneralTokenizer
##   initGeneralTokenizer(toknizr, code)
##   while true:
##     getNextToken(toknizr, langNim)
##     case toknizr.kind
##     of gtEof: break  # End Of File (or string)
##     of gtWhitespace:
##       echo gtWhitespace # Maybe you want "visible" whitespaces?.
##       echo substr(code, toknizr.start, toknizr.length + toknizr.start - 1)
##     of gtOperator:
##       echo gtOperator # Maybe you want Operators to use a specific color?.
##       echo substr(code, toknizr.start, toknizr.length + toknizr.start - 1)
##     # of gtSomeSymbol: syntaxHighlight("Comic Sans", "bold", "99px", "pink")
##     else:
##       echo toknizr.kind # All the kinds of tokens can be processed here.
##       echo substr(code, toknizr.start, toknizr.length + toknizr.start - 1)
##
## The proc ``getSourceLanguage`` can get the language ``enum`` from a string:
##
## .. code::nim
##   for l in ["C", "c++", "jAvA", "Nim", "c#"]: echo getSourceLanguage(l)
##

import std/[strutils, algorithm]

type
  TokenClass* = enum
    gtEof
    gtNone
    gtWhitespace
    gtDecNumber
    gtBinNumber
    gtHexNumber
    gtOctNumber
    gtFloatNumber
    gtIdentifier
    gtKeyword
    gtStringLit
    gtLongStringLit
    gtCharLit
    gtEscapeSequence # escape sequence like \xff
    gtOperator
    gtPunctuation
    gtComment
    gtLongComment
    gtDocComment
    gtDocLongComment
    gtRegularExpression
    gtTagStart
    gtTagEnd
    gtKey
    gtValue
    gtRawData
    gtCData
    gtAssembler
    gtPreprocessor
    gtDirective
    gtCommand
    gtRule
    gtHyperlink
    gtLabel
    gtReference
    gtOther
    gtBoolean
    gtSpecialVar
    gtBuiltin
    gtFunctionName
    gtTypeName
    gtPragma
    gtTable
    gtDate
    gtLogError
    gtLogWarning
    gtLogInfo
    gtLogUuid

  JsLikeState* = object ## Shared JS/TS/JSX/TSX tokenizer state.
    templateLiteralDepth*: int
    braceDepthStack*: seq[int]
    inJsxMode*: bool
    jsxTagDepth*: int
    commentDepth*: int

  HtmlState* = object
    inComment*: bool
    inScript*: bool
    inStyle*: bool

  AstroState* = object
    inFrontmatter*: bool
    firstLine*: bool

  YamlState* = object
    isKey*: bool

  MarkdownState* = object
    ## Per-line transient `inIndentedCode` lives on `GeneralTokenizer`, not here.
    inCodeBlock*: bool
    inMathMode*: bool
    inDisplayMath*: bool
    inFrontmatter*: bool
    firstLine*: bool
    codeBlockLang*: SourceLanguage

  LatexState* = object
    inMathMode*: bool
    inDisplayMath*: bool

  RustState* = object
    commentDepth*: int
    rawStringHashCount*: int
    inByteString*: bool
    inRawString*: bool
    attrBracketDepth*: int

  CommitState* = object
    subjectSeen*: bool

  LispState* = object
    commentDepth*: int

  HaskellState* = object
    commentDepth*: int

  PythonState* = object
    commentDepth*: int

  LuaState* = object
    longBracketLevel*: int
      ## `=` count of the long bracket currently open (`[[` is 0, `[==[` is 2).
      ## Only meaningful while `state` is `gtLongComment`/`gtLongStringLit`.
    stringQuote*: char
      ## Quote that opened the single-line string parked on a backslash escape.

  LangState* = object
    ## Per-language tokenizer state, captured/restored as a whole record.
    ## 8-aligned members first, then bool-only, to minimise padding.
    jslike*: JsLikeState
    rust*: RustState
    lisp*: LispState
    haskell*: HaskellState
    python*: PythonState
    lua*: LuaState
    html*: HtmlState
    astro*: AstroState
    yaml*: YamlState
    markdown*: MarkdownState
    latex*: LatexState
    commit*: CommitState

  GeneralTokenizer* = object of RootObj
    kind*: TokenClass
    start*, length*: int
    buf*: cstring
    pos*: int
    state*: TokenClass
    lang*: LangState
    mdInIndentedCode*: bool
      ## Per-line transient: set while consuming a markdown line's leading
      ## indent, cleared at content start. Kept off `lang` so it is not
      ## persisted at line boundaries (would emit an empty token on resume).

  SourceLanguage* = enum
    langNone
    langAstro
    langC
    langCommitEditMsg
    langCpp
    langCsharp
    langDiff
    langDockerfile
    langFish
    langGitRebaseTodo
    langGitignore
    langGo
    langHaskell
    langHtml
    langHyprland
    langJava
    langJavaScript
    langJsx
    langLatex
    langLisp
    langLog
    langLua
    langMarkdown
    langNim
    langPython
    langRust
    langShell
    langTcl
    langToml
    langYaml
    langJson
    langJsonc
    langTypeScript
    langTsx
    langXml
    langZsh

const
  ## Characters ending a line.
  eolChars*: set[char] = {'\0', '\n', '\r'}

  ## Line whitespace characters.
  lwsChars*: set[char] = {'\t', ' '}

  ## Common operators.
  opChars*: set[char] = {
    '+', '-', '*', '/', '\\', '<', '>', '!', '?', '^', '.', '|', '=', '%', '&', '$',
    '@', '~', ':',
  }

  ## Characters denoting a symbol.
  symChars*: set[char] = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}

  ## All whitespace characters.
  wsChars*: set[char] = {'\t' .. '\r', ' '}

  ## Display name per language. Keyed by enum member on purpose: a positional
  ## literal only compile-checks the length, so inserting a language mid-enum
  ## would silently shift every later name and misroute `getSourceLanguage`.
  sourceLanguageToStr*: array[SourceLanguage, string] = [
    langNone: "none",
    langAstro: "Astro",
    langC: "C",
    langCommitEditMsg: "COMMIT_EDITMSG",
    langCpp: "C++",
    langCsharp: "C#",
    langDiff: "Diff",
    langDockerfile: "Dockerfile",
    langFish: "Fish",
    langGitRebaseTodo: "git-rebase-todo",
    langGitignore: "gitignore",
    langGo: "Go",
    langHaskell: "Haskell",
    langHtml: "HTML",
    langHyprland: "Hyprland",
    langJava: "Java",
    langJavaScript: "JavaScript",
    langJsx: "JavaScriptReact",
    langLatex: "LaTeX",
    langLisp: "Lisp",
    langLog: "Log",
    langLua: "Lua",
    langMarkdown: "Markdown",
    langNim: "Nim",
    langPython: "Python",
    langRust: "Rust",
    langShell: "Shell",
    langTcl: "Tcl",
    langToml: "Toml",
    langYaml: "Yaml",
    langJson: "Json",
    langJsonc: "Jsonc",
    langTypeScript: "TypeScript",
    langTsx: "TypeScriptReact",
    langXml: "XML",
    langZsh: "Zsh",
  ]

proc getSourceLanguage*(name: string): SourceLanguage =
  for i in countup(succ(low(SourceLanguage)), high(SourceLanguage)):
    if cmpIgnoreStyle(name, sourceLanguageToStr[i]) == 0:
      return i
  case name.toLowerAscii
  of "js": langJavaScript
  of "jsx": langJsx
  of "ts": langTypeScript
  of "tsx": langTsx
  of "py": langPython
  of "rs": langRust
  of "sh", "bash": langShell
  of "yml": langYaml
  of "docker": langDockerfile
  of "md": langMarkdown
  of "cpp", "cxx": langCpp
  of "cs", "csharp": langCsharp
  of "golang": langGo
  of "hs": langHaskell
  of "luau": langLua
  of "tex", "latex": langLatex
  else: langNone

proc defaultLangState*(): LangState =
  ## Initial `LangState` for a fresh tokenizer. Callers seeding a tokenizer at
  ## file line 0 must use this rather than `LangState()`; otherwise
  ## astro/markdown `firstLine` is false and the frontmatter fence is missed.
  LangState(
    astro: AstroState(firstLine: true), markdown: MarkdownState(firstLine: true)
  )

proc initGeneralTokenizer*(g: var GeneralTokenizer, buf: string) =
  g.buf = buf
  g.kind = low(TokenClass)
  g.start = 0
  g.length = 0
  g.state = low(TokenClass)
  g.pos = 0
  g.lang = defaultLangState()
  g.mdInIndentedCode = false

proc scanToTerminator*(buf: cstring, pos: var int, t0, t1, t2: char): bool =
  ## Advance `pos` until the 3-byte terminator `t0 t1 t2` (consumed) or the
  ## end of the buffer. Returns true if the terminator was found. Used for
  ## the `-->` / `]]>` scans of HTML/XML comments and CDATA sections.
  ##
  ## NUL-safe without a length check: `buf[pos + 1]` is only read after
  ## `buf[pos]` matched a non-NUL char (so `pos + 1` is at most the NUL
  ## terminator), and `buf[pos + 2]` likewise only after `buf[pos + 1]`
  ## matched. Guarding with `buf.len` instead would be a `strlen` over the
  ## whole buffer — O(n) per call — and turn tokenization quadratic on
  ## terminator-char runs.
  while buf[pos] != '\0':
    if buf[pos] == t0 and buf[pos + 1] == t1 and buf[pos + 2] == t2:
      inc(pos, 3)
      return true
    inc(pos)
  false

template skipEscapedChar*(g: GeneralTokenizer, pos: var int) =
  ## Step over the char that follows an escape backslash, but never past the
  ## NUL terminator or across a newline: a trailing `\` at the end of the
  ## buffer must not push `pos` out of the buffer (out-of-bounds reads and
  ## negative-length tokens downstream), and an escaped newline must stay
  ## line-bounded so the per-line incremental state capture still sees the
  ## boundary.
  if g.buf[pos] notin eolChars:
    inc(pos)

proc generalNumber*(g: var GeneralTokenizer, position: int): int =
  const decChars = {'0' .. '9'}
  var pos = position
  g.kind = gtDecNumber
  while g.buf[pos] in decChars:
    inc(pos)
  if g.buf[pos] == '.':
    g.kind = gtFloatNumber
    inc(pos)
    while g.buf[pos] in decChars:
      inc(pos)
  if g.buf[pos] in {'e', 'E'}:
    g.kind = gtFloatNumber
    inc(pos)
    if g.buf[pos] in {'+', '-'}:
      inc(pos)
    while g.buf[pos] in decChars:
      inc(pos)
  result = pos

proc generalStrLit*(g: var GeneralTokenizer, position: int): int =
  const
    decChars = {'0' .. '9'}
    hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
  var pos = position
  g.kind = gtStringLit
  var c = g.buf[pos]
  inc(pos) # skip " or '
  while true:
    case g.buf[pos]
    of '\0':
      break
    of '\\':
      inc(pos)
      case g.buf[pos]
      of '\0':
        break
      of '0' .. '9':
        while g.buf[pos] in decChars:
          inc(pos)
      of 'x', 'X':
        inc(pos)
        if g.buf[pos] in hexChars:
          inc(pos)
        if g.buf[pos] in hexChars:
          inc(pos)
      else:
        inc(pos, 2)
    else:
      if g.buf[pos] == c:
        inc(pos)
        break
      else:
        inc(pos)
  result = pos

template peek*(g: GeneralTokenizer, pos: int, offset: int = 1): char =
  ## Look ahead `offset` bytes from `pos` without advancing. A replacement for
  ## the raw `g.buf[pos + N]` lookahead scattered across the tokenizers.
  ##
  ## NUL-safe like every other read here: the buffer is NUL-terminated, so an
  ## offset that reaches past the end just yields another `'\0'`. It is the
  ## caller's job not to peek so far ahead that it skips an intervening `'\0'`
  ## — the same contract the inline lookahead already relied on.
  g.buf[pos + offset]

proc scanStringBody*(g: var GeneralTokenizer, position: int, quote: char): int =
  ## Scan the body of a single-line string literal, starting at `position`
  ## (just past the opening `quote`) with `g.kind` already set to the token
  ## class to emit (`gtStringLit`, `gtKey`, ...). Returns the position after the
  ## token. This is the line-bounded, escape-parks variant shared by the C-like,
  ## shell, and JSON tokenizers:
  ##
  ## - the matching `quote` ends and is consumed by the token;
  ## - a line boundary or EOF (`'\0' '\r' '\n'`) ends the token *without*
  ##   consuming the terminator — the string is line-bounded so a multi-line
  ##   string never becomes one token whose interior boundary state breaks the
  ##   incremental tokenizer's per-line resume;
  ## - a backslash parks `g.state = g.kind` and breaks so the next call resumes
  ##   into the language's own escape handling.
  result = position
  while true:
    let c = g.buf[result]
    if c in {'\0', '\r', '\n'}:
      break
    elif c == '\\':
      g.state = g.kind
      break
    elif c == quote:
      inc(result)
      break
    else:
      inc(result)

proc scanRadixNumber*(g: var GeneralTokenizer, position: int): int =
  ## Scan a numeric literal beginning at a digit and set `g.kind`. A leading
  ## `0` followed by `b`/`B`, `x`/`X`, or an octal digit selects
  ## bin/hex/oct and consumes exactly those radix digits; everything else falls
  ## through to `generalNumber` (decimal / float / exponent). Trailing
  ## type-suffix letters are deliberately left in place — callers differ on
  ## whether a suffix is a single letter or a run — so the caller applies its
  ## own suffix policy afterwards. Byte-equivalent to the inline radix dispatch
  ## previously duplicated across the C-like and shell tokenizers.
  const
    hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    octChars = {'0' .. '7'}
    binChars = {'0' .. '1'}
  result = position
  if g.buf[result] == '0':
    case g.peek(result)
    of 'b', 'B':
      g.kind = gtBinNumber
      inc(result, 2)
      while g.buf[result] in binChars:
        inc(result)
      return
    of 'x', 'X':
      g.kind = gtHexNumber
      inc(result, 2)
      while g.buf[result] in hexChars:
        inc(result)
      return
    of '0' .. '7':
      g.kind = gtOctNumber
      inc(result, 2)
      while g.buf[result] in octChars:
        inc(result)
      return
    else:
      discard
  result = generalNumber(g, result)

proc isKeyword*(x: openArray[string], y: string): int =
  binarySearch(x, y)

import
  syntax_astro, syntax_c, syntax_commit_edit_msg, syntax_cpp, syntax_csharp,
  syntax_diff, syntax_dockerfile, syntax_git_rebase_todo, syntax_gitignore, syntax_go,
  syntax_haskell, syntax_html, syntax_java, syntax_javascript, syntax_latex,
  syntax_lisp, syntax_lua, syntax_markdown, syntax_nim, syntax_python, syntax_rust,
  syntax_fish, syntax_hyprland, syntax_shell, syntax_tcl, syntax_yaml, syntax_toml,
  syntax_json, syntax_jsonc, syntax_typescript, syntax_log, syntax_xml, syntax_zsh

proc getNextToken*(g: var GeneralTokenizer, lang: SourceLanguage) =
  let
    startPos = g.pos
    startState = g.state
  case lang
  of langAstro: g.astroNextToken
  of langC: g.cNextToken
  of langCommitEditMsg: g.commitEditMsgNextToken
  of langCpp: g.cppNextToken
  of langCsharp: g.csharpNextToken
  of langDiff: g.diffNextToken
  of langDockerfile: g.dockerfileNextToken
  of langFish: g.fishNextToken
  of langGitRebaseTodo: g.gitRebaseTodoNextToken
  of langGitignore: g.gitignoreNextToken
  of langGo: g.goNextToken
  of langHaskell: g.haskellNextToken
  of langHtml: g.htmlNextToken
  of langHyprland: g.hyprlandNextToken
  of langJava: g.javaNextToken
  of langJavaScript, langJsx: g.javaScriptNextToken
  of langLatex: g.latexNextToken
  of langLisp: g.lispNextToken
  of langLog: g.logNextToken
  of langLua: g.luaNextToken
  of langMarkdown: g.markdownNextToken
  of langNim: g.nimNextToken
  of langPython: g.pythonNextToken
  of langRust: g.rustNextToken
  of langShell: g.shellNextToken
  of langTcl: g.tclNextToken
  of langToml: g.tomlNextToken
  of langYaml: g.yamlNextToken
  of langJson: g.jsonNextToken
  of langJsonc: g.jsoncNextToken
  of langTypeScript, langTsx: g.typescriptNextToken
  of langXml: g.xmlNextToken
  of langZsh: g.zshNextToken
  of langNone: discard

  if g.kind != gtEof and g.pos <= startPos and g.state == startState:
    # Monotonic-advance guard: a non-EOF token must make progress, by consuming
    # input (`pos` advances) or changing `state` (YAML's zero-consume document
    # transitions). When it does neither the tokenizer is stuck; the per-tokenizer
    # `assert` that catches this is compiled out under `-d:danger`, where the
    # consumer loops would spin forever. Force EOF to terminate them.
    g.kind = gtEof
