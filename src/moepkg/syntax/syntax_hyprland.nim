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

import std/strutils

import tokenizer, flags, lexer

const
  HexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
  SymCharsHypr = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '-', '\x80' .. '\xFF'}

  Booleans = ["false", "no", "off", "on", "true", "yes"]

  # Sorted for binary search
  Keywords = [
    "animations", "bezier", "bind", "bindd", "binde", "bindel", "bindl", "bindm",
    "bindr", "env", "exec", "exec-once", "layerrule", "monitor", "plugin", "source",
    "submap", "windowrule", "windowrulev2", "workspace",
  ]

proc isFollowedByBrace(g: GeneralTokenizer, position: int): bool =
  var pos = position
  while g.buf[pos] != '\0' and g.buf[pos] in {' ', '\t'}:
    inc(pos)
  return g.buf[pos] == '{'

proc hyprlandNextToken*(g: var GeneralTokenizer) =
  var pos = g.pos
  g.start = g.pos

  if g.state == gtStringLit:
    g.kind = gtStringLit
    while true:
      case g.buf[pos]
      of '\\':
        g.kind = gtEscapeSequence
        inc(pos)
        case g.buf[pos]
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
    case g.buf[pos]
    of ' ', '\t' .. '\r':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\t' .. '\r'}:
        inc(pos)
    of '#':
      pos = g.lexHash(pos, flagsHyprland)
    of '$':
      g.kind = gtSpecialVar
      inc(pos)
      while g.buf[pos] in SymCharsHypr:
        inc(pos)
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var id = ""
      while g.buf[pos] in SymCharsHypr:
        add(id, g.buf[pos])
        inc(pos)
      if id.toLowerAscii in Booleans:
        g.kind = gtBoolean
      elif isKeyword(Keywords, id) >= 0:
        g.kind = gtKeyword
      elif g.isFollowedByBrace(pos):
        g.kind = gtTable
      else:
        g.kind = gtIdentifier
    of '0':
      g.kind = gtDecNumber
      inc(pos)
      case g.buf[pos]
      of 'x', 'X':
        g.kind = gtHexNumber
        inc(pos)
        while g.buf[pos] in HexChars:
          inc(pos)
      else:
        pos = generalNumber(g, pos)
    of '1' .. '9':
      pos = generalNumber(g, pos)
    of '\"':
      inc(pos)
      g.kind = gtStringLit
      pos = g.scanStringBody(pos, '\"')
    of '=':
      g.kind = gtOperator
      inc(pos)
    of '{', '}', ',':
      g.kind = gtPunctuation
      inc(pos)
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
    assert false, "hyprlandNextToken: produced an empty token"
  g.pos = pos
