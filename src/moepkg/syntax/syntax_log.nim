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
  AlphaChars = {'A' .. 'Z', 'a' .. 'z', '_'}
  AlphaNumChars = AlphaChars + {'0' .. '9'}

  ErrorLevels = ["CRITICAL", "ERR", "ERROR", "FATAL"]
  WarnLevels = ["WARN", "WARNING"]
  InfoLevels = ["DEBUG", "INFO", "NOTICE", "TRACE"]

  HexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}

template isDigit(c: char): bool =
  c in {'0' .. '9'}

proc tryUuid(g: var GeneralTokenizer, pos: int): int =
  ## Try to parse a UUID (8-4-4-4-12 hex digits) starting at `pos`.
  ## Returns the position after the UUID, or `pos` if no UUID found.
  var p = pos
  # 8 hex digits
  for i in 0 ..< 8:
    if g.buf[p] notin HexChars:
      return pos
    inc p
  if g.buf[p] != '-':
    return pos
  inc p
  # 3 groups of 4 hex digits
  for group in 0 ..< 3:
    for i in 0 ..< 4:
      if g.buf[p] notin HexChars:
        return pos
      inc p
    if g.buf[p] != '-':
      return pos
    inc p
  # 12 hex digits
  for i in 0 ..< 12:
    if g.buf[p] notin HexChars:
      return pos
    inc p
  # Ensure UUID ends (not followed by more hex/alnum)
  if g.buf[p] in AlphaNumChars:
    return pos
  return p

proc tryTimestamp(g: var GeneralTokenizer, pos: int): int =
  ## Try to parse a timestamp starting at `pos`.
  ## Returns the position after the timestamp, or `pos` if no timestamp found.
  ## Recognizes: YYYY-MM-DD, HH:MM:SS, YYYY-MM-DDTHH:MM:SS variants,
  ## and also YYYY/MM/DD.
  var p = pos

  # Need at least YYYY-MM-DD (10 chars) or HH:MM:SS (8 chars)
  # Check for date: YYYY-MM-DD or YYYY/MM/DD
  if g.buf[p].isDigit and g.buf[p + 1].isDigit and g.buf[p + 2].isDigit and
      g.buf[p + 3].isDigit and g.buf[p + 4] in {'-', '/'}:
    # YYYY-MM-DD or YYYY/MM/DD
    let sep = g.buf[p + 4]
    if g.buf[p + 5].isDigit and g.buf[p + 6].isDigit and g.buf[p + 7] == sep and
        g.buf[p + 8].isDigit and g.buf[p + 9].isDigit:
      p += 10
      # Optional time part: T or space followed by HH:MM:SS
      if g.buf[p] in {'T', ' '} and g.buf[p + 1].isDigit and g.buf[p + 2].isDigit and
          g.buf[p + 3] == ':' and g.buf[p + 4].isDigit and g.buf[p + 5].isDigit and
          g.buf[p + 6] == ':' and g.buf[p + 7].isDigit and g.buf[p + 8].isDigit:
        p += 9
        # Optional fractional seconds: .NNN
        if g.buf[p] == '.':
          inc p
          while g.buf[p].isDigit:
            inc p
        # Optional timezone: Z, +HH:MM, -HH:MM
        if g.buf[p] == 'Z':
          inc p
        elif g.buf[p] in {'+', '-'} and g.buf[p + 1].isDigit and g.buf[p + 2].isDigit and
            g.buf[p + 3] == ':' and g.buf[p + 4].isDigit and g.buf[p + 5].isDigit:
          p += 6
      return p

  # Check for time only: HH:MM:SS
  if g.buf[p].isDigit and g.buf[p + 1].isDigit and g.buf[p + 2] == ':' and
      g.buf[p + 3].isDigit and g.buf[p + 4].isDigit and g.buf[p + 5] == ':' and
      g.buf[p + 6].isDigit and g.buf[p + 7].isDigit:
    p += 8
    # Optional fractional seconds
    if g.buf[p] == '.':
      inc p
      while g.buf[p].isDigit:
        inc p
    return p

  return pos

proc logGetKeywordClass(id: string): TokenClass =
  if isKeyword(ErrorLevels, id) >= 0:
    return gtLogError
  if isKeyword(WarnLevels, id) >= 0:
    return gtLogWarning
  if isKeyword(InfoLevels, id) >= 0:
    return gtLogInfo
  return gtIdentifier

proc logNextToken*(g: var GeneralTokenizer) =
  var pos = g.pos
  g.start = pos

  # Handle continued string from previous token
  if g.state == gtStringLit:
    g.kind = gtStringLit
    while true:
      case g.buf[pos]
      of '\0', '\n', '\r':
        g.state = gtNone
        break
      of '\\':
        # Skip escape sequence
        inc pos
        if g.buf[pos] notin {'\0', '\n', '\r'}:
          inc pos
      of '"', '\'':
        inc pos
        g.state = gtNone
        break
      else:
        inc pos
    g.length = pos - g.pos
    g.pos = pos
    return

  case g.buf[pos]
  of '\0':
    g.kind = gtEof
  of ' ', '\t', '\r', '\n':
    g.kind = gtWhitespace
    while g.buf[pos] in {' ', '\t', '\r', '\n'}:
      inc pos
  of '0' .. '9':
    # Try UUID first, then timestamp, then number
    let uuidEnd = g.tryUuid(pos)
    if uuidEnd > pos:
      g.kind = gtLogUuid
      pos = uuidEnd
    else:
      let tsEnd = g.tryTimestamp(pos)
      if tsEnd > pos:
        g.kind = gtDate
        pos = tsEnd
      else:
        # Regular number
        pos = generalNumber(g, pos)
        while g.buf[pos] in {'A' .. 'Z', 'a' .. 'z'}:
          inc pos
  of '[':
    # Bracket expression: [...]
    g.kind = gtPragma
    inc pos
    while g.buf[pos] notin {'\0', '\n', '\r', ']'}:
      inc pos
    if g.buf[pos] == ']':
      inc pos
  of '"', '\'':
    # String literal
    let quote = g.buf[pos]
    inc pos
    g.kind = gtStringLit
    while true:
      case g.buf[pos]
      of '\0', '\n', '\r':
        g.state = gtStringLit
        break
      of '\\':
        inc pos
        if g.buf[pos] notin {'\0', '\n', '\r'}:
          inc pos
      else:
        if g.buf[pos] == quote:
          inc pos
          break
        inc pos
  of 'A' .. 'Z', 'a' .. 'z', '_':
    # Try UUID for hex-letter starts (a-f, A-F)
    let uuidEnd = g.tryUuid(pos)
    if uuidEnd > pos:
      g.kind = gtLogUuid
      pos = uuidEnd
    else:
      # Identifier - check for log level keywords
      var id = ""
      while g.buf[pos] in AlphaNumChars:
        id.add(g.buf[pos])
        inc pos
      g.kind = logGetKeywordClass(id)
  of '=':
    g.kind = gtOperator
    inc pos
  of ':', ',', ';', '(', ')', '{', '}':
    g.kind = gtPunctuation
    inc pos
  else:
    g.kind = gtNone
    inc pos

  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "logNextToken: produced an empty token"
  g.pos = pos
