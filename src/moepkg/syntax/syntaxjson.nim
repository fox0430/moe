#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import highlite

const
  NumberChars = {'0'..'9'}
  SymChars = {'A'..'Z', 'a'..'z', '0'..'9', '_', '\x80'..'\xFF'}
  JsonKeywords = ["false", "null", "true"]

proc jsonNextToken*(g: var GeneralTokenizer) =
  ## jsonNextToken is Incomplete

  var pos = g.pos
  g.start = g.pos
  if g.state == gtStringLit:
    if g.buf[pos] == '\\':
      g.kind = gtEscapeSequence
      inc(pos)
      case g.buf[pos]
      of '\0':
        g.state = gtNone
      else: inc(pos)
    else:
      g.kind = gtStringLit
      while true:
        case g.buf[pos]
        of '\\':
          break
        of '\0', '\r', '\n':
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
    of 'a'..'z', 'A'..'Z', '_', '\x80'..'\xFF':
      var id = ""
      while g.buf[pos] in symChars:
        add(id, g.buf[pos])
        inc(pos)
      if isKeyword(JsonKeywords, id) >= 0: g.kind = gtKeyword
      else: g.kind = gtIdentifier
    of '0'..'9':
      pos = generalNumber(g, pos)
      if g.buf[pos] in {'A'..'Z', 'a'..'z'}: inc(pos)
    of '"':
      inc(pos)
      if (g.buf[pos] == '\"') and (g.buf[pos + 1] == '\"'):
        inc(pos, 2)
        g.kind = gtLongStringLit
        while true:
          case g.buf[pos]
          of '\0':
            break
          of '\"':
            inc(pos)
            if g.buf[pos] == '\"' and g.buf[pos+1] == '\"' and
               g.buf[pos+2] != '\"':
              inc(pos, 2)
              break
          else: inc(pos)
      else:
        g.kind = gtStringLit
        while true:
          case g.buf[pos]
          of '\0', '\r', '\n':
            break
          of '\"':
            inc(pos)
            break
          of '\\':
            g.state = g.kind
            break
          else: inc(pos)
    of '{', '}', '[', ']':
      inc(pos)
      g.kind = gtPunctuation
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
    assert false, "produced an empty token"
  g.pos = pos
