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

import tokenizer

const
  SymChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}
  JsonKeywords = ["false", "null", "true"]

proc jsonNextToken*(g: var GeneralTokenizer) =
  ## Enhanced JSON tokenizer with improved name and variable highlighting

  var pos = g.pos
  g.start = g.pos
  if g.state == gtLongStringLit:
    if g.buf[pos] == '\0':
      g.kind = gtEof
    else:
      g.kind = gtLongStringLit
    while g.kind != gtEof:
      case g.buf[pos]
      of '\0':
        break
      of '\"':
        inc(pos)
        if g.buf[pos] == '\"' and g.buf[pos + 1] == '\"' and g.buf[pos + 2] != '\"':
          inc(pos, 2)
          g.state = gtNone
          break
      else:
        inc(pos)
    g.length = pos - g.pos
    g.pos = pos
    return
  elif g.state in {gtStringLit, gtKey}:
    if g.buf[pos] == '\\':
      g.kind = gtEscapeSequence
      inc(pos)
      case g.buf[pos]
      of '\0':
        g.state = gtNone
      else:
        inc(pos)
    else:
      g.kind = g.state
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
        else:
          inc(pos)
  else:
    case g.buf[pos]
    of ' ', '\x09' .. '\x0D':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\x09' .. '\x0D'}:
        inc(pos)
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var id = ""
      while g.buf[pos] in SymChars:
        add(id, g.buf[pos])
        inc(pos)
      if isKeyword(JsonKeywords, id) >= 0:
        g.kind = gtKeyword
      else:
        g.kind = gtIdentifier
    of '0' .. '9':
      pos = generalNumber(g, pos)
      if g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
        inc(pos)
    of '"':
      inc(pos)
      # Check if this string is a key (followed by a colon)
      var isKey = false
      var tempPos = pos
      # Skip to end of string to check if it's followed by colon
      while tempPos < g.buf.len and g.buf[tempPos] != '\0':
        case g.buf[tempPos]
        of '"':
          inc(tempPos)
          # Skip whitespace after closing quote
          while tempPos < g.buf.len and g.buf[tempPos] in {' ', '\t', '\n', '\r'}:
            inc(tempPos)
          # Check if next non-whitespace character is colon
          if tempPos < g.buf.len and g.buf[tempPos] == ':':
            isKey = true
          break
        of '\\':
          inc(tempPos, 2) # Skip escape sequence
        else:
          inc(tempPos)

      if (g.buf[pos] == '\"') and (g.buf[pos + 1] == '\"'):
        inc(pos, 2)
        g.kind = gtLongStringLit
        while true:
          case g.buf[pos]
          of '\0':
            g.state = gtLongStringLit
            break
          of '\"':
            inc(pos)
            if g.buf[pos] == '\"' and g.buf[pos + 1] == '\"' and g.buf[pos + 2] != '\"':
              inc(pos, 2)
              break
          else:
            inc(pos)
      else:
        # Set kind based on whether this is a key or value
        if isKey:
          g.kind = gtKey
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
          else:
            inc(pos)
    of '{', '}', '[', ']':
      inc(pos)
      g.kind = gtPunctuation
    of ':':
      inc(pos)
      g.kind = gtOperator
    of ',':
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
    assert false, "produced an empty token"
  g.pos = pos
