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

import flags, tokenizer, lexer

const tclKeywords* = [
  "after", "append", "apply", "array", "break", "catch", "cd", "chan", "clock", "close",
  "concat", "continue", "coroutine", "dict", "else", "elseif", "encoding", "eof",
  "error", "eval", "exec", "exit", "expr", "fblocked", "fconfigure", "fcopy", "file",
  "fileevent", "flush", "for", "foreach", "format", "gets", "glob", "global", "if",
  "incr", "info", "interp", "join", "lappend", "lassign", "lindex", "linsert", "list",
  "llength", "lmap", "load", "lrange", "lrepeat", "lreplace", "lreverse", "lsearch",
  "lset", "lsort", "namespace", "open", "package", "pid", "proc", "puts", "pwd", "read",
  "regexp", "regsub", "rename", "return", "scan", "seek", "set", "socket", "source",
  "split", "string", "subst", "switch", "tailcall", "tell", "then", "throw", "time",
  "trace", "try", "unload", "unset", "update", "uplevel", "upvar", "variable", "vwait",
  "while", "yield", "yieldto",
]

proc tclNextToken*(g: var GeneralTokenizer) =
  const
    hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    octChars = {'0' .. '7'}
    binChars = {'0' .. '1'}
    symChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}
  var pos = g.pos
  g.start = g.pos
  if g.state == gtStringLit and g.buf[pos] notin {'\0', '\r', '\n'}:
    g.kind = gtStringLit
    while true:
      case g.buf[pos]
      of '\\':
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
    # A string resume landing directly on EOL/EOF has no content left (an
    # escape consumed up to the newline). The string is line-bounded, so end
    # it: reset to gtNone and tokenize the terminator normally instead of
    # emitting an empty gtStringLit token.
    g.state = gtNone
    case g.buf[pos]
    of ' ', '\t' .. '\r':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\t' .. '\r'}:
        inc(pos)
    of '#':
      pos = g.lexHash(pos, flagsTcl)
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var id = ""
      while g.buf[pos] in symChars:
        add(id, g.buf[pos])
        inc(pos)
      if isKeyword(tclKeywords, id) >= 0:
        g.kind = gtKeyword
      else:
        g.kind = gtIdentifier
    of '$':
      # Variable reference: $name or ${name}
      g.kind = gtSpecialVar
      inc(pos)
      if g.buf[pos] == '{':
        inc(pos)
        # Line-bounded: an unclosed `${` must not swallow newlines into one
        # token whose interior boundary state breaks incremental resume.
        while g.buf[pos] notin {'\0', '}', '\r', '\n'}:
          inc(pos)
        if g.buf[pos] == '}':
          inc(pos)
      else:
        while g.buf[pos] in symChars:
          inc(pos)
    of '0':
      inc(pos)
      case g.buf[pos]
      of 'b', 'B':
        g.kind = gtBinNumber
        inc(pos)
        while g.buf[pos] in binChars:
          inc(pos)
        if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
          inc(pos)
      of 'x', 'X':
        g.kind = gtHexNumber
        inc(pos)
        while g.buf[pos] in hexChars:
          inc(pos)
        if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
          inc(pos)
      of 'o', 'O', '0' .. '7':
        g.kind = gtOctNumber
        inc(pos)
        while g.buf[pos] in octChars:
          inc(pos)
        if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
          inc(pos)
      else:
        pos = generalNumber(g, pos)
        if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
          inc(pos)
    of '1' .. '9':
      pos = generalNumber(g, pos)
      if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
        inc(pos)
    of '\"':
      inc(pos)
      g.kind = gtStringLit
      # Line-bounded: the resume path also ends the string at EOL, so a
      # multi-line string never becomes one token whose interior line boundary
      # state (gtNone) breaks incremental resume.
      pos = g.scanStringBody(pos, '\"')
    of '(', ')', ':', ',', ';', '.':
      inc(pos)
      g.kind = gtPunctuation
    of '[', ']', '{', '}':
      inc(pos)
      g.kind = gtPunctuation
    of '\0':
      g.kind = gtEof
    else:
      if g.buf[pos] in opChars:
        g.kind = gtOperator
        while g.buf[pos] in opChars:
          inc(pos)
      else:
        inc(pos)
        g.kind = gtNone
  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "tclNextToken: produced an empty token"
  g.pos = pos
