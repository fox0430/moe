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

import flags, tokenizer, lexer

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

proc shellNextToken*(g: var GeneralTokenizer) =
  const
    hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
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
      pos = g.lexHash(pos, flagsShell)
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var id = ""
      while g.buf[pos] in symChars:
        add(id, g.buf[pos])
        inc(pos)
      if isKeyword(shellKeywords, id) >= 0:
        g.kind = gtKeyword
      else:
        g.kind = gtIdentifier
    of '0' .. '9':
      pos = g.scanRadixNumber(pos)
      if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
        inc(pos)
    of '\"':
      inc(pos)
      g.kind = gtStringLit
      # Line-bounded: the resume path also ends the string at EOL, so a
      # multi-line string never becomes one token whose interior line boundary
      # state (gtNone) breaks incremental resume.
      pos = g.scanStringBody(pos, '\"')
    of '\'':
      inc(pos)
      g.kind = gtStringLit
      pos = g.scanStringBody(pos, '\'')
    of '(', ')', ':', ',', ';', '.':
      inc(pos)
      g.kind = gtPunctuation
    of '[', ']', '{', '}':
      inc(pos)
      g.kind = gtKeyword
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
    assert false, "shellNextToken: produced an empty token"
  g.pos = pos
