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

proc skipJsonKeyLookahead(
    buf: cstring, start: int, allowComments: bool
): tuple[pos: int, sawColon: bool] =
  ## Scan past whitespace and (when allowComments) `//` / `/* */` comments.
  ## Returns the position landed on and whether it is a `:`.
  var p = start
  while buf[p] != '\0':
    case buf[p]
    of ' ', '\t', '\n', '\r':
      inc(p)
    of '/':
      if not allowComments:
        break
      if buf[p + 1] == '/':
        inc(p, 2)
        while buf[p] notin {'\0', '\n', '\r'}:
          inc(p)
      elif buf[p + 1] == '*':
        inc(p, 2)
        while buf[p] != '\0':
          if buf[p] == '*' and buf[p + 1] == '/':
            inc(p, 2)
            break
          inc(p)
      else:
        break
    else:
      break
  result = (p, buf[p] == ':')

proc jsonLikeNextToken*(g: var GeneralTokenizer, allowComments: bool) =
  ## Tokenizer for JSON, and for JSONC when `allowComments` is true.

  var pos = g.pos
  g.start = g.pos
  if allowComments and g.state == gtLongComment:
    if g.buf[pos] == '\0':
      g.kind = gtEof
    else:
      g.kind = gtLongComment
    while g.kind != gtEof:
      case g.buf[pos]
      of '*':
        inc(pos)
        if g.buf[pos] == '/':
          inc(pos)
          g.state = gtNone
          break
      of '\0':
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
    of ' ', '\t' .. '\r':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\t' .. '\r'}:
        inc(pos)
    of '/':
      if allowComments and g.buf[pos + 1] == '/':
        g.kind = gtComment
        inc(pos, 2)
        while not (g.buf[pos] in {'\0', '\n', '\r'}):
          inc(pos)
      elif allowComments and g.buf[pos + 1] == '*':
        g.kind = gtLongComment
        inc(pos, 2)
        while true:
          case g.buf[pos]
          of '*':
            inc(pos)
            if g.buf[pos] == '/':
              inc(pos)
              g.state = gtNone
              break
          of '\0':
            g.state = gtLongComment
            break
          else:
            inc(pos)
      else:
        g.kind = gtOperator
        while g.buf[pos] in opChars:
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
    of '"':
      inc(pos)
      var isKey = false
      var tempPos = pos
      while g.buf[tempPos] != '\0':
        case g.buf[tempPos]
        of '"':
          inc(tempPos)
          let (after, sawColon) = skipJsonKeyLookahead(g.buf, tempPos, allowComments)
          tempPos = after
          isKey = sawColon
          break
        of '\\':
          inc(tempPos, 2)
        else:
          inc(tempPos)

      if isKey:
        g.kind = gtKey
      else:
        g.kind = gtStringLit
      pos = g.scanStringBody(pos, '\"')
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

proc jsonNextToken*(g: var GeneralTokenizer) =
  jsonLikeNextToken(g, allowComments = false)
