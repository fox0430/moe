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
import tokenizer

const
  # Sorted for binary search via isKeyword
  Instructions = [
    "ADD", "ARG", "CMD", "COPY", "CROSS_BUILD", "ENTRYPOINT", "ENV", "EXPOSE", "FROM",
    "HEALTHCHECK", "LABEL", "MAINTAINER", "ONBUILD", "RUN", "SHELL", "STOPSIGNAL",
    "USER", "VOLUME", "WORKDIR",
  ]

  # Secondary keywords (used after instructions)
  SecondaryKeywords = ["AS"]

proc isAtLineStart(g: GeneralTokenizer, pos: int): bool =
  ## Check if pos is at the start of a line (only whitespace before it).
  var p = pos - 1
  while p >= 0 and g.buf[p] in {' ', '\t'}:
    dec(p)
  result = p < 0 or g.buf[p] in {'\n', '\r'}

proc dockerfileNextToken*(g: var GeneralTokenizer) =
  var pos = g.pos
  g.start = pos

  case g.buf[pos]
  of ' ', '\t':
    g.kind = gtWhitespace
    while g.buf[pos] in {' ', '\t'}:
      inc(pos)
  of '\n', '\r':
    g.kind = gtWhitespace
    if g.buf[pos] == '\r' and g.buf[pos + 1] == '\n':
      inc(pos, 2)
    else:
      inc(pos)
  of '#':
    if g.isAtLineStart(pos):
      g.kind = gtComment
      while g.buf[pos] notin {'\0', '\n', '\r'}:
        inc(pos)
    else:
      g.kind = gtNone
      inc(pos)
  of '"':
    g.kind = gtStringLit
    inc(pos)
    while true:
      case g.buf[pos]
      of '\0', '\n', '\r':
        break
      of '\\':
        inc(pos)
        if g.buf[pos] notin {'\0', '\n', '\r'}:
          inc(pos)
      of '"':
        inc(pos)
        break
      else:
        inc(pos)
  of '\'':
    g.kind = gtStringLit
    inc(pos)
    while true:
      case g.buf[pos]
      of '\0', '\n', '\r':
        break
      of '\'':
        inc(pos)
        break
      else:
        inc(pos)
  of '$':
    g.kind = gtBuiltin
    inc(pos)
    if g.buf[pos] == '{':
      inc(pos)
      while g.buf[pos] notin {'\0', '\n', '\r', '}'}:
        inc(pos)
      if g.buf[pos] == '}':
        inc(pos)
    else:
      while g.buf[pos] in symChars:
        inc(pos)
  of '0' .. '9':
    pos = g.generalNumber(pos)
  of '\\':
    # Line continuation
    if g.buf[pos + 1] in {'\n', '\r', '\0'}:
      g.kind = gtOperator
      inc(pos)
    else:
      g.kind = gtNone
      inc(pos)
  of '=':
    g.kind = gtOperator
    inc(pos)
  of '-':
    if g.buf[pos + 1] == '-':
      # --flag (e.g., --from, --chown)
      g.kind = gtPreprocessor
      inc(pos, 2)
      while g.buf[pos] in symChars or g.buf[pos] == '-':
        inc(pos)
    else:
      g.kind = gtNone
      inc(pos)
  of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
    var id = ""
    let startPos = pos
    while g.buf[pos] in symChars:
      id.add(g.buf[pos])
      inc(pos)

    if g.isAtLineStart(startPos) and isKeyword(Instructions, id.toUpperAscii) >= 0:
      g.kind = gtKeyword
    elif isKeyword(SecondaryKeywords, id.toUpperAscii) >= 0:
      g.kind = gtKeyword
    else:
      g.kind = gtIdentifier
  of '[', ']', ',', '{', '}':
    g.kind = gtPunctuation
    inc(pos)
  of ':':
    g.kind = gtOperator
    inc(pos)
  of '\0':
    g.kind = gtEof
  else:
    g.kind = gtNone
    inc(pos)

  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "dockerfileNextToken: produced an empty token"
  g.pos = pos
