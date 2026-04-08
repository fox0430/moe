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

const fishKeywords* = [
  "abbr", "alias", "and", "argparse", "begin", "bind", "break", "builtin", "case", "cd",
  "command", "complete", "contains", "continue", "count", "echo", "else", "emit", "end",
  "eval", "exec", "exit", "false", "for", "function", "functions", "history", "if",
  "in", "math", "not", "or", "printf", "read", "return", "set", "set_color", "source",
  "status", "string", "switch", "test", "time", "true", "type", "while",
]

proc fishNextToken*(g: var GeneralTokenizer) =
  const
    hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    octChars = {'0' .. '7'}
    binChars = {'0' .. '1'}
    symChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}
  var pos = g.pos
  g.start = g.pos
  if g.state == gtStringLit:
    g.kind = gtStringLit
    while true:
      case g.buf[pos]
      of '\\':
        if pos > g.start:
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
      of '\0', '\x0D', '\x0A':
        g.state = gtNone
        break
      of '\"':
        inc(pos)
        g.state = gtNone
        break
      else:
        inc(pos)
  else:
    case g.buf[pos]
    of ' ', '\x09' .. '\x0D':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\x09' .. '\x0D'}:
        inc(pos)
    of '#':
      pos = g.lexHash(pos, flagsShell)
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var id = ""
      while g.buf[pos] in symChars:
        add(id, g.buf[pos])
        inc(pos)
      if isKeyword(fishKeywords, id) >= 0:
        g.kind = gtKeyword
      else:
        g.kind = gtIdentifier
    of '0':
      inc(pos)
      case g.buf[pos]
      of 'b', 'B':
        inc(pos)
        while g.buf[pos] in binChars:
          inc(pos)
        if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
          inc(pos)
      of 'x', 'X':
        inc(pos)
        while g.buf[pos] in hexChars:
          inc(pos)
        if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
          inc(pos)
      of '0' .. '7':
        inc(pos)
        while g.buf[pos] in octChars:
          inc(pos)
        if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
          inc(pos)
      else:
        pos = generalNumber(g, pos)
        if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
          inc(pos)
      g.kind = gtNone
    of '1' .. '9':
      pos = generalNumber(g, pos)
      if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
        inc(pos)
      g.kind = gtNone
    of '\"':
      inc(pos)
      g.kind = gtStringLit
      while true:
        case g.buf[pos]
        of '\0':
          break
        of '\"':
          inc(pos)
          break
        of '\\':
          g.state = g.kind
          break
        else:
          inc(pos)
    of '\'':
      # Fish single-quoted strings do not support escape sequences.
      inc pos
      g.kind = gtStringLit
      while true:
        case g.buf[pos]
        of '\0':
          break
        of '\'':
          inc pos
          break
        else:
          inc pos
    of '(', ')', ':', ',', ';', '.':
      inc(pos)
      g.kind = gtPunctuation
    of '[', ']', '{', '}':
      inc(pos)
      g.kind = gtPunctuation
    of '$':
      inc(pos)
      if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '_', '\x80' .. '\xFF'}:
        g.kind = gtSpecialVar
        while g.buf[pos] in symChars:
          inc(pos)
      else:
        g.kind = gtOperator
    of '\0':
      g.kind = gtEof
    else:
      if g.buf[pos] in opChars - {'/', '-', '$'}:
        g.kind = gtOperator
        while g.buf[pos] in opChars - {'/', '-', '$'}:
          inc(pos)
      else:
        inc(pos)
        g.kind = gtNone
  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "fishNextToken: produced an empty token"
  g.pos = pos
