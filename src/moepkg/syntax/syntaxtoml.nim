#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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
import highlite, flags, lexer

const
  DecChars = {'0'..'9'}
  HexChars = {'0'..'9', 'A'..'F', 'a'..'f'}
  OctChars = {'0'..'7'}
  BinChars = {'0'..'1'}
  Operators = {'+', '-'}
  DateChars = {'0'..'9', 'T', 'z', '-', ':', '.', ' '}
  InfStr = "inf"
  NanStr = "nan"
  Booleans = ["true", "false"]

proc tomlNumberAndDate(g: var GeneralTokenizer, position: int): int =
  var pos = position

  g.kind = gtDecNumber
  if g.buf[pos] in Operators: pos.inc

  if not (g.buf[pos] in DecChars):
    # Check "inf" and "nan"
    var id = ""
    while g.buf[pos] in symChars:
      id.add g.buf[pos]
      pos.inc

    if id in [InfStr, NanStr]:
      g.kind = gtFloatNumber
    else:
      g.kind = gtIdentifier
  else:
    while g.buf[pos] in DecChars: pos.inc

    if g.buf[pos] == '.':
      g.kind = gtFloatNumber
      pos.inc
      while g.buf[pos] in DecChars: pos.inc
    if g.buf[pos] in {'e', 'E'}:
      g.kind = gtFloatNumber
      pos.inc
      if g.buf[pos] in {'+', '-'}: pos.inc
      while g.buf[pos] in DecChars: pos.inc
    if g.buf[pos] == '_':
      while g.buf[pos] in DecChars or g.buf[pos] == '_': pos.inc
    if g.buf[pos] in {'-', ':'}:
      g.kind = gtDate
      while g.buf[pos] in DateChars: pos.inc

  return pos

proc tomlNextToken*(g: var GeneralTokenizer) =
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
          of 'x', 'X':
            inc(pos)
            if g.buf[pos] in HexChars: inc(pos)
          of Digits:
            while g.buf[pos] in Digits: inc(pos)
          of '\0':
            g.state = gtNone
          else: inc(pos)
          break
        of '\0', '\x0D', '\x0A':
          g.state = gtNone
          break
        of '\"':
          inc(pos)
          g.state = gtNone
          break
        else: inc(pos)
  else:
    case g.buf[pos]
      of ' ', '\x09'..'\x0D':
        g.kind = gtWhitespace
        while g.buf[pos] in {' ', '\x09'..'\x0D'}: inc(pos)
      of '#':
        pos = g.lexHash(pos, flagsToml)
      of 'a'..'z', 'A'..'Z', '_', '\x80'..'\xFF':
        var id = ""
        while g.buf[pos] in symChars:
          add(id, g.buf[pos])
          inc(pos)
        if id in Booleans: g.kind = gtBoolean
        elif id in [InfStr, NanStr]: g.kind = gtFloatNumber
        else: g.kind = gtIdentifier
      of '0':
        inc(pos)
        case g.buf[pos]
        of 'b', 'B':
          inc(pos)
          while g.buf[pos] in BinChars: inc(pos)
          if g.buf[pos] in Letters: inc(pos)
        of 'x', 'X':
          inc(pos)
          while g.buf[pos] in HexChars: inc(pos)
          if g.buf[pos] in Letters: inc(pos)
        of '0'..'7':
          inc(pos)
          while g.buf[pos] in OctChars: inc(pos)
          if g.buf[pos] in Letters: inc(pos)
        else:
          pos = tomlNumberAndDate(g, pos)
          if g.buf[pos] in Letters: inc(pos)
      of '1'..'9', '+', '-':
        pos = tomlNumberAndDate(g, pos)
        if g.buf[pos] in Letters: inc(pos)
      of '[':
        g.kind = gtTable
        while g.buf[pos] != ']' and not (g.buf[pos] in Newlines): inc(pos)
        if g.buf[pos] == ']': inc(pos)
      of '\"', '\'':
        inc(pos)
        g.kind = gtStringLit
        while true:
          case g.buf[pos]
          of '\0':
            break
          of '\"', '\'':
            inc(pos)
            break
          of '\\':
            g.state = g.kind
            break
          else: inc(pos)
      of '\0':
        g.kind = gtEof
      else:
        if g.buf[pos] in opChars:
          g.kind = gtOperator
          while g.buf[pos] in opChars: inc(pos)
        else:
          inc(pos)
          g.kind = gtNone

  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "tomlToken: produced an empty token"
  g.pos = pos
