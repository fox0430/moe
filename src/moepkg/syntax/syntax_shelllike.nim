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

## Shared tokenizer for the POSIX-shell family. Bash/sh, Zsh and Fish differ only
## in a handful of lexing rules, so they are tokenized by a single
## `shellLikeNextToken` selected with a `ShellDialect`. `syntax_shell`,
## `syntax_zsh` and `syntax_fish` are thin wrappers over this module.

import flags, tokenizer, lexer

type ShellDialect* = enum
  sdShell ## Bash / POSIX sh
  sdZsh
  sdFish

const shellKeywords* = [
  "[", "]", "alias", "bg", "bind", "break", "builtin", "case", "cd", "chdir", "command",
  "compgen", "complete", "continue", "declare", "dirs", "disown", "do", "done", "echo",
  "elif", "else", "enable", "esac", "eval", "exec", "exit", "export", "fc", "fg", "fi",
  "for", "function", "getopts", "hash", "help", "history", "if", "in", "jobs", "kill",
  "let", "local", "login", "logout", "newgrp", "popd", "print", "printf", "pushd",
  "pwd", "read", "readonly", "return", "select", "set", "shift", "shopt", "source",
  "stop", "suspend", "test", "then", "time", "times", "trap", "type", "typeset",
  "ulimit", "umask", "unalias", "unset", "until", "wait", "whence", "while", "{", "}",
]

const zshKeywords* = [
  "[", "]", "alias", "autoload", "bg", "bind", "bindkey", "break", "builtin", "case",
  "cd", "chdir", "command", "compdef", "compgen", "compinit", "complete", "continue",
  "declare", "dirs", "disown", "do", "done", "echo", "elif", "else", "emulate",
  "enable", "esac", "eval", "exec", "exit", "export", "false", "fc", "fg", "fi",
  "float", "for", "fpath", "function", "getopts", "hash", "help", "history", "if", "in",
  "integer", "jobs", "kill", "let", "local", "login", "logout", "newgrp", "nocorrect",
  "noglob", "popd", "print", "printf", "pushd", "pushln", "pwd", "r", "read",
  "readonly", "return", "select", "set", "setopt", "shift", "shopt", "source", "stop",
  "suspend", "test", "then", "time", "times", "trap", "true", "type", "typeset",
  "ulimit", "umask", "unalias", "unset", "unsetopt", "until", "vared", "wait", "whence",
  "which", "while", "zcompile", "zle", "zmodload", "zparseopts", "zsh", "zstyle", "{",
  "}",
]

const fishKeywords* = [
  "abbr", "alias", "and", "argparse", "begin", "bind", "break", "builtin", "case", "cd",
  "command", "complete", "contains", "continue", "count", "echo", "else", "emit", "end",
  "eval", "exec", "exit", "false", "for", "function", "functions", "history", "if",
  "in", "math", "not", "or", "printf", "read", "return", "set", "set_color", "source",
  "status", "string", "switch", "test", "time", "true", "type", "while",
]

proc isShellLikeKeyword(dialect: ShellDialect, id: string): bool =
  case dialect
  of sdShell:
    isKeyword(shellKeywords, id) >= 0
  of sdZsh:
    isKeyword(zshKeywords, id) >= 0
  of sdFish:
    isKeyword(fishKeywords, id) >= 0

proc inArithmetic(g: GeneralTokenizer): bool =
  ## Inside arithmetic, and not in a command substitution or a `${ }`
  ## expansion within it.
  for i in countdown(g.lang.shell.contexts.high, 0):
    case g.lang.shell.contexts[i]
    of 'a', '[':
      return true
    of '(', '`', 'e':
      return false
    else:
      discard
  false

proc noteHeredoc(g: var GeneralTokenizer, position: int) =
  ## Take the end marker of the heredoc a `<<` at `position` opens, as the
  ## shell reads it: quotes and backslashes removed. A `<<<` here-string opens
  ## none, nor does a `<<` in arithmetic, where it is a shift.
  if g.inArithmetic or g.buf[position] != '<' or g.buf[position + 1] != '<' or
      g.buf[position + 2] == '<':
    return
  var p = position + 2
  let tabs = g.buf[p] == '-'
  if tabs:
    inc(p)
  while g.buf[p] in {' ', '\t'}:
    inc(p)
  # In a backquoted substitution, a backquote ends it and the marker.
  let stops =
    wsChars + {'\0', ';', '|', '&', '<', '>', '(', ')'} +
    (if '`' in g.lang.shell.contexts: {'`'} else: {})
  var
    marker = ""
    quoted = false
  while g.buf[p] notin stops:
    case g.buf[p]
    of '\'', '"':
      quoted = true
      let quote = g.buf[p]
      inc(p)
      while g.buf[p] notin {quote, '\0', '\n', '\r'}:
        marker.add g.buf[p]
        inc(p)
      if g.buf[p] == quote:
        inc(p)
    of '\\':
      inc(p)
      if g.buf[p] == '\r' and g.buf[p + 1] == '\n':
        # A `\` line continuation joins the marker with the next line.
        inc(p, 2)
      elif g.buf[p] == '\n':
        inc(p)
      elif g.buf[p] != '\0':
        marker.add g.buf[p]
        inc(p)
    else:
      marker.add g.buf[p]
      inc(p)
  # An empty quoted marker ends the body at its first empty line.
  if marker.len > 0 or quoted:
    g.lang.shell.heredocMarker = (if tabs: "-" else: "=") & marker

proc heredocLine(g: var GeneralTokenizer, position: int): int =
  ## A line of a heredoc's body from its start at `position`, with its line
  ## break; or its end marker, which closes the heredoc.
  result = position
  if g.buf[result] == '\0':
    g.kind = gtEof
    return
  var lineEnd = result
  while g.buf[lineEnd] notin {'\0', '\n'}:
    inc(lineEnd)
  var
    first = result
    last = lineEnd
  if g.lang.markdown.inCodeBlock:
    # A Markdown code block's lines are indented to its fence.
    var col = 0
    while col < g.lang.markdown.fenceBaseCol and g.buf[first] in {' ', '\t'}:
      col =
        if g.buf[first] == '\t':
          (col div 4 + 1) * 4
        else:
          col + 1
      inc(first)
  if g.lang.shell.heredocMarker[0] == '-':
    while g.buf[first] == '\t':
      inc(first)
  if last > first and g.buf[last - 1] == '\r':
    dec(last)
  let marker = g.lang.shell.heredocMarker[1 ..^ 1]
  var ends = last - first >= marker.len
  for i in 0 ..< marker.len:
    if not ends:
      break
    ends = g.buf[first + i] == marker[i]
  let markerEnd = first + marker.len
  if ends and markerEnd < last and marker.len == 0:
    ends = false
  elif ends and markerEnd < last:
    # In a command substitution, the substitution's end may follow the marker.
    let contexts = g.lang.shell.contexts
    ends =
      (g.buf[markerEnd] == ')' and '(' in contexts) or
      (g.buf[markerEnd] == '`' and '`' in contexts)
  if ends:
    g.kind = gtKeyword
    g.state = gtNone
    g.lang.shell.heredocMarker = ""
    result = markerEnd
    if result == position:
      # The empty line that ends an empty marker's body.
      result =
        if g.buf[lineEnd] == '\n':
          lineEnd + 1
        else:
          lineEnd
  else:
    g.kind = gtLongStringLit
    result =
      if g.buf[lineEnd] == '\n':
        lineEnd + 1
      else:
        lineEnd

const StringContexts = {'"', '\'', '$'}

proc inString(g: GeneralTokenizer): bool =
  let contexts = g.lang.shell.contexts
  contexts.len > 0 and contexts[^1] in StringContexts

proc inSubstitution(g: GeneralTokenizer): bool =
  ## Inside a command or parameter substitution, where parentheses, braces and
  ## backquotes are tracked.
  let contexts = g.lang.shell.contexts
  contexts.len > 0 and contexts[^1] notin StringContexts

proc inExpansion(g: GeneralTokenizer): bool =
  ## Directly inside a `${ }` parameter expansion, where no command starts.
  let contexts = g.lang.shell.contexts
  contexts.len > 0 and contexts[^1] == 'e'

proc popContext(g: var GeneralTokenizer) =
  g.lang.shell.contexts.setLen(g.lang.shell.contexts.len - 1)
  g.state = if g.inString: gtStringLit else: gtNone

proc closeContext(g: var GeneralTokenizer, openers, leftOpen: set[char]): bool =
  ## Close the innermost context in `openers`, with any `leftOpen` ones above
  ## it, which end with it.
  let contexts = g.lang.shell.contexts
  var i = contexts.high
  while i >= 0 and contexts[i] in leftOpen:
    dec(i)
  if i < 0 or contexts[i] notin openers:
    return false
  g.lang.shell.contexts.setLen(i + 1)
  g.popContext()
  true

proc atCommandStart(g: GeneralTokenizer, position: int): bool =
  ## Whether a word at `position` is where a command starts.
  var p = position
  while p > 0 and g.buf[p - 1] in {' ', '\t'}:
    dec(p)
  if p == 0 or g.buf[p - 1] in {'\n', '\r', ';', '&', '|', '(', ')', '{', '`', '!'}:
    return true
  var word = ""
  while p > 0 and g.buf[p - 1] in {'a' .. 'z'}:
    dec(p)
    word.insert($g.buf[p])
  (p == 0 or g.buf[p - 1] in wsChars + {';', '&', '|', '(', '{', '`'}) and
    word in ["then", "do", "else", "elif", "if", "while", "until"]

proc skipRune(g: GeneralTokenizer, position: int): int =
  ## Past the character at `position`, a whole UTF-8 sequence.
  result = position + 1
  while g.buf[result] in {'\x80' .. '\xBF'}:
    inc(result)

proc isEscaped(g: GeneralTokenizer, position: int): bool =
  ## Whether an odd run of backslashes comes right before `position`.
  var p = position
  while p > 0 and g.buf[p - 1] == '\\':
    dec(p)
  (position - p) mod 2 == 1

proc quotedPart(g: var GeneralTokenizer, position: int): int =
  ## A piece of the Bash/Zsh string the innermost context opened, from
  ## `position`: up to its closing quote, an escape, the start of a command
  ## substitution, or a line break, after which the string goes on.
  const hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
  result = position
  g.kind = gtStringLit
  g.state = gtStringLit
  let
    quote = g.lang.shell.contexts[^1]
    closing = if quote == '"': '"' else: '\''
  while true:
    let c = g.buf[result]
    if c == '\0':
      if result == g.start:
        g.kind = gtEof
      return
    elif c == '\n':
      return result + 1
    elif c == closing:
      g.popContext()
      return result + 1
    elif quote == '"' and (c == '`' or (c == '$' and g.buf[result + 1] in {'(', '{'})):
      if result > g.start:
        return
      g.kind = gtOperator
      g.state = gtNone
      if c == '`':
        g.lang.shell.contexts.add '`'
        return result + 1
      if g.buf[result + 1] == '{':
        g.lang.shell.contexts.add 'e'
        return result + 2
      g.lang.shell.contexts.add '('
      if g.buf[result + 2] == '(':
        # `$((`: arithmetic inside the substitution.
        g.lang.shell.contexts.add 'a'
        return result + 3
      return result + 2
    elif c == '\\' and quote == '$':
      if result > g.start:
        return
      g.kind = gtEscapeSequence
      inc(result)
      case g.buf[result]
      of 'x', 'X':
        inc(result)
        if g.buf[result] in hexChars:
          inc(result)
        if g.buf[result] in hexChars:
          inc(result)
      of '0' .. '7':
        while g.buf[result] in {'0' .. '7'}:
          inc(result)
      of 'u', 'U':
        let digits = if g.buf[result] == 'u': 4 else: 8
        inc(result)
        for _ in 1 .. digits:
          if g.buf[result] notin hexChars:
            break
          inc(result)
      of 'c':
        # `\cX`: a control character, named by the character after it.
        inc(result)
        if g.buf[result] notin {'\0', '\n', '\r', '\''}:
          result = g.skipRune(result)
      of '\0':
        discard
      else:
        result = g.skipRune(result)
      return
    elif c == '\\' and quote == '"' and
        g.buf[result + 1] in {'$', '`', '"', '\\', '\r', '\n'}:
      # Only these are escapes in a double quoted string.
      if result > g.start:
        return
      g.kind = gtEscapeSequence
      inc(result, 2)
      if g.buf[result - 1] == '\r' and g.buf[result] == '\n':
        inc(result)
      return
    elif c == '\\' and quote == '"' and g.buf[result + 1] != '\0':
      inc(result, 2)
    else:
      inc(result)

proc subscriptAt(g: GeneralTokenizer, position: int): bool =
  ## Whether the `[` at `position` opens a `name[` subscript, whose index is
  ## arithmetic: right after a name, and closed on its line.
  if position == 0 or g.buf[position - 1] notin {
    'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_'
  }:
    return false
  var
    p = position + 1
    depth = 1
  while g.buf[p] notin {'\0', '\n', '\r'}:
    case g.buf[p]
    of '[':
      inc(depth)
    of ']':
      dec(depth)
      if depth == 0:
        return true
    else:
      discard
    inc(p)
  false

proc shellLikeNextToken*(g: var GeneralTokenizer, dialect: ShellDialect) =
  ## Shared Bash/Zsh/Fish tokenizer. `dialect` selects the rules that differ
  ## between the three: the keyword set, whether numeric literals are highlighted
  ## (Fish does not), the token class of `[` `]` `{` `}` (Fish punctuation vs.
  ## keyword), single-quoted-string escape handling, the `$var` special variable
  ## (Fish only), and which characters start an operator run (Fish excludes
  ## `/`, `-` and `$` so paths and flags stay plain).
  const
    hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    symChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}
  var pos = g.pos
  g.start = g.pos
  if g.state == gtLongStringLit and g.lang.shell.heredocMarker.len == 0:
    # Not a state this lexer leaves, as one carried over from another language.
    g.state = gtNone
  if g.state == gtLongStringLit:
    pos = g.heredocLine(pos)
  elif dialect != sdFish and g.inString:
    pos = g.quotedPart(pos)
  elif g.state == gtStringLit and g.buf[pos] notin {'\0', '\r', '\n'}:
    g.kind = gtStringLit
    while true:
      case g.buf[pos]
      of '\\':
        if dialect == sdFish and pos > g.start:
          # Return accumulated string content first; handle escape next call.
          break
        g.kind = gtEscapeSequence
        inc(pos)
        case g.buf[pos]
        of 'x', 'X':
          inc(pos)
          if g.buf[pos] in hexChars:
            inc(pos)
          if g.buf[pos] in hexChars:
            inc(pos)
        of '0' .. '9':
          while g.buf[pos] in {'0' .. '9'}:
            inc(pos)
        of '\0':
          g.state = gtNone
        else:
          inc(pos)
        break
      of '\0', '\r', '\n':
        g.state = gtNone
        break
      of '\"':
        inc(pos)
        g.state = gtNone
        break
      else:
        inc(pos)
  else:
    # A Fish string resume landing directly on EOL/EOF has no content left
    # (an escape consumed up to the newline). Fish strings are line-bounded,
    # so end it: reset to gtNone and tokenize the terminator normally instead
    # of emitting an empty gtStringLit token.
    g.state = gtNone
    case g.buf[pos]
    of ' ', '\t' .. '\r':
      g.kind = gtWhitespace
      if g.lang.shell.heredocMarker.len > 0:
        # A heredoc's body starts on the next line.
        while g.buf[pos] in {' ', '\t' .. '\r'} - {'\n'}:
          inc(pos)
        if g.buf[pos] == '\n':
          inc(pos)
          g.state = gtLongStringLit
      else:
        while g.buf[pos] in {' ', '\t' .. '\r'}:
          inc(pos)
    of '#':
      # Zsh reads `(#i)` as a glob flag.
      let boundary =
        wsChars + {';', '|', '&', ')', '<', '>'} + (if dialect == sdZsh: {}
        else: {'('})
      let contexts = g.lang.shell.contexts
      # A line break is one even after a `\` continuation, as the line's own
      # state cannot tell.
      if not g.inExpansion and (
        pos == 0 or g.buf[pos - 1] in {'\n', '\r'} or
        (g.buf[pos - 1] in boundary and not g.isEscaped(pos - 1)) or
        # Right after the backquote that opens a substitution.
        (g.buf[pos - 1] == '`' and contexts.len > 0 and contexts[^1] == '`')
      ):
        pos = g.lexHash(pos, flagsShell)
        if '`' in contexts:
          # A backquoted substitution's text ends at its backquote, and so does
          # a comment in it.
          for i in g.start ..< pos:
            if g.buf[i] == '`':
              pos = i
              break
      else:
        # Only a word's first `#` starts a comment: not `$#`, `${#x}` or `10#7`.
        inc(pos)
        g.kind = gtPunctuation
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var id = ""
      while g.buf[pos] in symChars:
        add(id, g.buf[pos])
        inc(pos)
      if isShellLikeKeyword(dialect, id):
        g.kind = gtKeyword
      else:
        g.kind = gtIdentifier
      if dialect != sdFish and g.inSubstitution and not g.inExpansion and
          g.buf[pos] in wsChars + {'\0', ';', '&', '|', ')', '`'}:
        # In a substitution, a `case` pattern's `)` must not close it. Not
        # `case=1`, an assignment.
        if id == "case" and g.atCommandStart(g.start):
          g.lang.shell.contexts.add 'c'
        elif id == "esac" and g.atCommandStart(g.start):
          discard g.closeContext({'c'}, {'{', 'p', 'e'})
    of '0' .. '9':
      pos = g.scanRadixNumber(pos)
      if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
        inc(pos)
      if dialect == sdFish:
        # Fish does not highlight numeric literals; the scan above only advances
        # past the digits.
        g.kind = gtNone
    of '\"', '\'':
      if dialect != sdFish:
        # A string goes on across lines, one token per line, so a line's
        # entering state says it starts inside the string.
        # `$'` opens an ANSI-C string, but not after the `$$` variable.
        var dollars = pos
        while dollars > 0 and g.buf[dollars - 1] == '$':
          dec(dollars)
        var count = pos - dollars
        if count > 0 and g.isEscaped(dollars):
          dec(count)
        g.lang.shell.contexts.add(
          if g.buf[pos] == '\'' and count mod 2 == 1:
            '$'
          else:
            g.buf[pos]
        )
        pos = g.quotedPart(pos + 1)
      elif g.buf[pos] == '\"':
        inc(pos)
        g.kind = gtStringLit
        # Line-bounded: the resume path also ends the string at EOL, so a
        # multi-line string never becomes one token whose interior line boundary
        # state (gtNone) breaks incremental resume.
        pos = g.scanStringBody(pos, '\"')
      else:
        inc(pos)
        g.kind = gtStringLit
        # Fish single-quoted strings do not support escape sequences.
        while true:
          case g.buf[pos]
          of '\0', '\r', '\n':
            break
          of '\'':
            inc(pos)
            break
          else:
            inc(pos)
    of '(', ')', ':', ',', ';', '.':
      if dialect != sdFish:
        # Track `((` / `$((` arithmetic by its parentheses, and command
        # substitutions.
        if g.buf[pos] == '(':
          # `$(`, or a `<(` / `>(` (Zsh: `=(` starting a word) process
          # substitution outside arithmetic.
          let substitution =
            pos > 0 and not g.isEscaped(pos - 1) and (
              g.buf[pos - 1] == '$' or (
                not g.inArithmetic and (
                  g.buf[pos - 1] in {'<', '>'} or (
                    dialect == sdZsh and g.buf[pos - 1] == '=' and
                    (pos == 1 or g.buf[pos - 2] in wsChars + {';', '|', '&', '(', '`'})
                  )
                )
              )
            )
          if substitution:
            g.lang.shell.contexts.add '('
            if g.buf[pos - 1] == '$' and g.buf[pos + 1] == '(':
              # `$((`: arithmetic inside the substitution.
              inc(pos)
              g.lang.shell.contexts.add 'a'
          elif g.inArithmetic or g.buf[pos + 1] == '(':
            g.lang.shell.contexts.add 'a'
          elif g.inSubstitution:
            g.lang.shell.contexts.add 'p'
        elif g.buf[pos] == ')':
          discard g.closeContext({'p', '(', 'a'}, {'{', '['})
      inc(pos)
      g.kind = gtPunctuation
    of '[', ']', '{', '}':
      if dialect != sdFish:
        # `$[ ]` is arithmetic too; brackets inside arithmetic nest with it.
        if g.buf[pos] == '[':
          if g.inArithmetic or
              (pos > 0 and g.buf[pos - 1] == '$' and not g.isEscaped(pos - 1)) or
              g.subscriptAt(pos):
            g.lang.shell.contexts.add '['
        elif g.buf[pos] == ']':
          discard g.closeContext({'['}, {'a'})
        # And `${ }`, whose quotes nest.
        elif g.buf[pos] == '{':
          if pos > 0 and g.buf[pos - 1] == '$' and not g.isEscaped(pos - 1):
            g.lang.shell.contexts.add 'e'
          elif g.inSubstitution and not g.inExpansion:
            g.lang.shell.contexts.add '{'
        elif g.buf[pos] == '}':
          discard g.closeContext({'{', 'e'}, {'p', 'a', '['})
      inc(pos)
      # Fish treats brackets/braces as punctuation; Bash/Zsh list them as
      # keywords (e.g. the `[` test builtin and `{ }` grouping).
      g.kind = if dialect == sdFish: gtPunctuation else: gtKeyword
    of '\0':
      g.kind = gtEof
    else:
      case dialect
      of sdFish:
        if g.buf[pos] == '$':
          inc(pos)
          if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '_', '\x80' .. '\xFF'}:
            g.kind = gtSpecialVar
            while g.buf[pos] in symChars:
              inc(pos)
          else:
            g.kind = gtOperator
        elif g.buf[pos] in opChars - {'/', '-', '$'}:
          g.kind = gtOperator
          while g.buf[pos] in opChars - {'/', '-', '$'}:
            inc(pos)
        else:
          inc(pos)
          g.kind = gtNone
      of sdShell, sdZsh:
        if g.buf[pos] == '\\':
          # A backslash quotes the next character; before a line break it
          # continues the command, so a heredoc's body starts after it.
          g.kind = gtOperator
          inc(pos)
          if g.buf[pos] == '\r' and g.buf[pos + 1] == '\n':
            inc(pos, 2)
          elif g.buf[pos] != '\0':
            pos = g.skipRune(pos)
        elif g.buf[pos] in opChars:
          g.kind = gtOperator
          while g.buf[pos] in opChars - {'\\'}:
            # No command starts in a `${ }` expansion, nor does a heredoc.
            if g.buf[pos] == '<' and (pos == g.start or g.buf[pos - 1] != '<') and
                not g.inExpansion:
              g.noteHeredoc(pos)
            inc(pos)
        else:
          if g.buf[pos] == '`' and not g.closeContext({'`'}, {'{', 'p', 'a', '['}):
            g.lang.shell.contexts.add '`'
          inc(pos)
          g.kind = gtNone
  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "shellLikeNextToken: produced an empty token"
  g.pos = pos
