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

#
# Resources.
#

from flags import
  flagsMarkdown

from highlite import
  GeneralTokenizer,
  TokenClass

from lexer import
  lexBacktick,
  lexDash,
  lexHash,
  lexSharp,
  lexSymbol,
  lexWhitespace



#
# Procedures.
#

## The lexing logic for Markdown.
proc markdownNextToken*(lexer: var GeneralTokenizer) =
  var position = lexer.pos
  lexer.start = lexer.pos

  case lexer.buf[position]
  of '\0':
    lexer.kind = gtEof
  of '`':
    position = lexer.lexBacktick(position, flagsMarkdown)
  of '-':
    position = lexer.lexDash(position, flagsMarkdown)
  of '#':
    position = lexer.lexHash(position, flagsMarkdown)
  of '<':
    position = lexer.lexSharp(position, flagsMarkdown)
  of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
    position = lexer.lexSymbol(position)
  of ' ', '\t' .. '\r':
    position = lexer.lexWhitespace(position)
  of '(', ')', '[', ']', '{', '}', ':', ',', ';', '.', '/', '\'', '\"':
    lexer.kind = gtPunctuation
    inc position
  else:
    lexer.kind = gtNone
    inc position

  lexer.length = position - lexer.pos

  if lexer.kind != gtEof and lexer.length <= 0:
    assert false, "markdownNextToken: produced an empty token"

  lexer.pos = position

#[############################################################################]#
