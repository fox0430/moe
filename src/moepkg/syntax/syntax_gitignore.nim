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

proc gitignoreNextToken*(g: var GeneralTokenizer) =
  var pos = g.pos
  g.start = pos

  if g.buf[pos] == '\0':
    g.kind = gtEof
    g.length = 0
    return

  # Newline resets line-start state for the next token
  if g.buf[pos] == '\n':
    g.kind = gtWhitespace
    inc pos
    g.length = pos - g.start
    g.state = gtNone
    g.pos = pos
    return

  let atLineStart = g.state in {gtEof, gtNone}

  # Comment line: '#' must be at the start of a line
  if atLineStart and g.buf[pos] == '#':
    g.kind = gtComment
    while g.buf[pos] notin {'\0', '\n'}:
      inc pos
    g.length = pos - g.start
    g.state = gtComment
    g.pos = pos
    return

  # Negation pattern: '!' at line start
  if atLineStart and g.buf[pos] == '!':
    g.kind = gtOperator
    inc pos
    g.length = pos - g.start
    g.state = gtOperator
    g.pos = pos
    return

  case g.buf[pos]
  of '\\':
    # Escape sequence: \X
    g.kind = gtEscapeSequence
    inc pos
    if g.buf[pos] notin {'\0', '\n'}:
      inc pos
    g.length = pos - g.start
    g.state = gtEscapeSequence
    g.pos = pos
  of '*':
    # '**' is the "anywhere" matcher; emit it as a single token. Plain '*' and
    # any further '*' are emitted separately so each metacharacter is distinct.
    g.kind = gtOperator
    inc pos
    if g.buf[pos] == '*':
      inc pos
    g.length = pos - g.start
    g.state = gtOperator
    g.pos = pos
  of '?':
    g.kind = gtOperator
    inc pos
    g.length = pos - g.start
    g.state = gtOperator
    g.pos = pos
  of '/':
    g.kind = gtPunctuation
    inc pos
    g.length = pos - g.start
    g.state = gtPunctuation
    g.pos = pos
  of '[':
    # Character class
    g.kind = gtRegularExpression
    inc pos
    while g.buf[pos] notin {'\0', '\n', ']'}:
      if g.buf[pos] == '\\' and g.buf[pos + 1] notin {'\0', '\n'}:
        inc pos, 2
      else:
        inc pos
    if g.buf[pos] == ']':
      inc pos
    g.length = pos - g.start
    g.state = gtRegularExpression
    g.pos = pos
  of ' ', '\t':
    g.kind = gtWhitespace
    while g.buf[pos] in {' ', '\t'}:
      inc pos
    g.length = pos - g.start
    g.state = gtWhitespace
    g.pos = pos
  else:
    # Plain pattern text
    g.kind = gtIdentifier
    while g.buf[pos] notin {'\0', '\n', '\\', '*', '?', '/', '[', ' ', '\t'}:
      inc pos
    g.length = pos - g.start
    g.state = gtIdentifier
    g.pos = pos
