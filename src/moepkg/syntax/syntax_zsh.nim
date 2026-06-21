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

import flags, tokenizer, lexer

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

proc zshNextToken*(g: var GeneralTokenizer) =
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
      pos = g.lexHash(pos, flagsShell)
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var id = ""
      while g.buf[pos] in symChars:
        add(id, g.buf[pos])
        inc(pos)
      if isKeyword(zshKeywords, id) >= 0:
        g.kind = gtKeyword
      else:
        g.kind = gtIdentifier
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
      of '0' .. '7':
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
    assert false, "zshNextToken: produced an empty token"
  g.pos = pos
