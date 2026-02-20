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
  DecChars = {'0' .. '9'}
  HexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
  OctChars = {'0' .. '7'}
  BinChars = {'0' .. '1'}
  Operators = {'+', '-'}
  DateChars = {'0' .. '9', 'T', 'z', '-', ':', '.', ' '}
  FloatKeywords = ["inf", "nan"]
  Booleans = ["true", "false"]
  ArrayKeywords = ["true", "false", "inf", "nan"]

proc tomlNumberAndDate(g: var GeneralTokenizer, position: int): int =
  var pos = position

  g.kind = gtDecNumber
  if g.buf[pos] in Operators:
    pos.inc

  if not (g.buf[pos] in DecChars):
    # Check "inf" and "nan"
    var id = ""
    while g.buf[pos] in symChars:
      id.add g.buf[pos]
      pos.inc

    if id in FloatKeywords:
      g.kind = gtFloatNumber
    elif id.len > 0:
      g.kind = gtIdentifier
  else:
    while g.buf[pos] in DecChars:
      pos.inc

    if g.buf[pos] == '.':
      g.kind = gtFloatNumber
      pos.inc
      while g.buf[pos] in DecChars:
        pos.inc
    if g.buf[pos] in {'e', 'E'}:
      g.kind = gtFloatNumber
      pos.inc
      if g.buf[pos] in {'+', '-'}:
        pos.inc
      while g.buf[pos] in DecChars:
        pos.inc
    if g.buf[pos] == '_':
      while g.buf[pos] in DecChars or g.buf[pos] == '_':
        pos.inc
    if g.buf[pos] in {'-', ':'}:
      g.kind = gtDate
      while g.buf[pos] in DateChars:
        pos.inc

  return pos

proc matchKeyword(g: GeneralTokenizer, pos: int, keyword: string): bool =
  ## Check if buffer at pos matches keyword, with bounds checking
  for i, c in keyword:
    if g.buf[pos + i] == '\0' or g.buf[pos + i] != c:
      return false
  return true

proc isKeywordAt(g: GeneralTokenizer, pos: int): bool =
  ## Check if position contains a TOML keyword (true, false, inf, nan)
  for keyword in ArrayKeywords:
    if g.matchKeyword(pos, keyword):
      # Verify it's followed by array delimiter
      var endPos = pos + keyword.len
      while g.buf[endPos] in {' ', '\t'}:
        inc(endPos)
      if g.buf[endPos] in {',', ']'}:
        return true
  return false

proc isArrayElement(g: GeneralTokenizer, pos: int): bool =
  ## Check if content after a quoted string indicates array element (comma)
  ## Table headers end with ] followed by newline/EOF/comment
  var p = pos
  let quote = g.buf[p]
  inc(p) # Skip opening quote
  # Skip string content with bounds checking
  while g.buf[p] notin {'\0', '\n', '\r'} and g.buf[p] != quote:
    if g.buf[p] == '\\' and g.buf[p + 1] != '\0':
      inc(p) # Skip escape character
    inc(p)
  if g.buf[p] == quote:
    inc(p)
    # Skip whitespace (not newlines)
    while g.buf[p] in {' ', '\t'}:
      inc(p)
    # Comma definitely means array
    if g.buf[p] == ',':
      return true
    # ] followed by more content (not newline/EOF/comment) means array
    if g.buf[p] == ']':
      inc(p)
      # For array of tables [[...]], check second ]
      if g.buf[p] == ']':
        inc(p)
      while g.buf[p] in {' ', '\t'}:
        inc(p)
      # Table header ends with newline, EOF, or comment
      if g.buf[p] in {'\n', '\r', '\0', '#'}:
        return false # It's a table header
      return true # It's an array
  return false

proc isTableHeader(g: GeneralTokenizer, position: int): bool =
  var pos = position + 1

  # Skip whitespace
  while g.buf[pos] in {' ', '\t'}:
    inc(pos)

  # [[...]] could be array of tables or nested array
  if g.buf[pos] == '[':
    var pos2 = pos + 1
    while g.buf[pos2] in {' ', '\t'}:
      inc(pos2)
    # Nested array starts with: number, [, ]
    if g.buf[pos2] in DecChars or g.buf[pos2] in {'[', ']'}:
      return false
    # String in nested array or quoted table name
    if g.buf[pos2] in {'"', '\''}:
      if g.isArrayElement(pos2):
        return false # It's a nested array
      return true # It's an array of tables with quoted key
    # Check for keywords (true, false, inf, nan) which indicate array
    if g.isKeywordAt(pos2):
      return false
    # Otherwise it's likely array of tables
    if g.buf[pos2] in {'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF'}:
      return true
    return false

  # Quoted key - could be table header or string array
  if g.buf[pos] in {'"', '\''}:
    if g.isArrayElement(pos):
      return false
    return true

  # Check if it looks like a table name (identifier)
  if g.buf[pos] in {'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF'}:
    # Check for keywords that indicate this is an array, not a table
    if g.isKeywordAt(pos):
      return false
    return true

  return false

proc tomlTable(g: var GeneralTokenizer, position: int): int =
  var pos = position

  g.kind = gtTable

  while not (g.buf[pos] in {'\n', '\r', '\0', '['}):
    inc(pos)

  if g.buf[pos] == '[':
    # Array of table
    var countClose = 0
    while not (g.buf[pos] in {'\n', '\r', '\0'} or countClose == 2):
      inc(pos)
      if g.buf[pos] == ']':
        countClose.inc

    if countClose == 2:
      pos.inc

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
          # \xNN - 2 hex digits
          inc(pos)
          for _ in 0 ..< 2:
            if g.buf[pos] in HexChars:
              inc(pos)
        of 'u':
          # \uXXXX - 4 hex digits
          inc(pos)
          for _ in 0 ..< 4:
            if g.buf[pos] in HexChars:
              inc(pos)
        of 'U':
          # \UXXXXXXXX - 8 hex digits
          inc(pos)
          for _ in 0 ..< 8:
            if g.buf[pos] in HexChars:
              inc(pos)
        of DecChars:
          while g.buf[pos] in DecChars:
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
  elif g.state == gtLongStringLit:
    # Continuation of multiline """ or ''' string
    if g.buf[pos] == '\0':
      g.kind = gtEof
    else:
      g.kind = gtLongStringLit
    while g.kind != gtEof:
      case g.buf[pos]
      of '\0':
        break
      of '\"':
        if g.buf[pos + 1] == '\"' and g.buf[pos + 2] == '\"':
          inc(pos, 3)
          g.state = gtNone
          break
        else:
          inc(pos)
      of '\'':
        if g.buf[pos + 1] == '\'' and g.buf[pos + 2] == '\'':
          inc(pos, 3)
          g.state = gtNone
          break
        else:
          inc(pos)
      of '\\':
        inc(pos)
        if g.buf[pos] != '\0':
          inc(pos)
      else:
        inc(pos)
  else:
    case g.buf[pos]
    of ' ', '\x09' .. '\x0D':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\x09' .. '\x0D'}:
        inc(pos)
    of '#':
      pos = g.lexHash(pos, flagsToml)
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var id = ""
      while g.buf[pos] in symChars:
        add(id, g.buf[pos])
        inc(pos)
      if id in Booleans:
        g.kind = gtBoolean
      elif id in ["inf", "nan"]:
        g.kind = gtFloatNumber
      else:
        g.kind = gtIdentifier
    of '0':
      g.kind = gtDecNumber
      inc(pos)
      case g.buf[pos]
      of 'b', 'B':
        inc(pos)
        while g.buf[pos] in BinChars:
          inc(pos)
        if g.buf[pos] in Letters:
          inc(pos)
      of 'x', 'X':
        inc(pos)
        while g.buf[pos] in HexChars:
          inc(pos)
        if g.buf[pos] in Letters:
          inc(pos)
      of 'o', 'O':
        inc(pos)
        while g.buf[pos] in OctChars:
          inc(pos)
        if g.buf[pos] in Letters:
          inc(pos)
      else:
        pos = tomlNumberAndDate(g, pos)
        if g.buf[pos] in Letters:
          inc(pos)
    of '1' .. '9', '+', '-':
      pos = tomlNumberAndDate(g, pos)
      if g.buf[pos] in Letters:
        inc(pos)
    of '[':
      if g.isTableHeader(pos):
        pos = tomlTable(g, pos)
      else:
        g.kind = gtPunctuation
        inc(pos)
    of '\"':
      inc(pos)
      # Check for multiline string """
      if g.buf[pos] == '\"' and g.buf[pos + 1] == '\"':
        g.kind = gtLongStringLit
        inc(pos, 2)
        while true:
          case g.buf[pos]
          of '\0':
            g.state = gtLongStringLit
            break
          of '\"':
            if g.buf[pos + 1] == '\"' and g.buf[pos + 2] == '\"':
              inc(pos, 3)
              break
            else:
              inc(pos)
          of '\\':
            inc(pos)
            if g.buf[pos] != '\0':
              inc(pos)
          else:
            inc(pos)
      else:
        g.kind = gtStringLit
        # Single-line basic string
        while true:
          case g.buf[pos]
          of '\0', '\x0D', '\x0A':
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
      inc(pos)
      # Check for multiline literal string '''
      if g.buf[pos] == '\'' and g.buf[pos + 1] == '\'':
        g.kind = gtLongStringLit
        inc(pos, 2)
        while true:
          case g.buf[pos]
          of '\0':
            g.state = gtLongStringLit
            break
          of '\'':
            if g.buf[pos + 1] == '\'' and g.buf[pos + 2] == '\'':
              inc(pos, 3)
              break
            else:
              inc(pos)
          else:
            inc(pos)
      else:
        g.kind = gtStringLit
        # Single-line literal string - no escape processing
        while true:
          case g.buf[pos]
          of '\0', '\x0D', '\x0A':
            break
          of '\'':
            inc(pos)
            break
          else:
            inc(pos)
    of ']', ',', '{', '}':
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
    assert false, "tomlToken: produced an empty token"
  g.pos = pos
