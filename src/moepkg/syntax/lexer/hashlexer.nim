#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2022 fox0430                                             #
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

from endlexer import
  endLine

from ../flags import
  TokenizerFlag,
  TokenizerFlags

from ../highlite import
  GeneralTokenizer,
  TokenClass,
  eolChars,
  lwsChars



#
# Procedures.
#

## Lex a double hash bracket comment.
##
## This comment type starts with ``##[`` and ends with ``]##``.  Some languages
## allow for nesting.
##
## Languages supporting this type are:
##
## - Nim

proc lexDoubleHashBracketComment(lexer: GeneralTokenizer, position: int,
    nested: bool): int =
  var depth = 0
  result = position

  if lexer.buf[result] == '[':
    inc result

    while true:
      case lexer.buf[result]
      of '\0':
        break

      of '#':
        inc result

        if lexer.buf[result] == '#':
          inc result

          if lexer.buf[result] == '[':
            inc result

            if nested:
              inc depth

      of ']':
        inc result

        if lexer.buf[result] == '#':
          inc result

          if lexer.buf[result] == '#':
            inc result

            if depth == 0:
              break
            elif nested:
              dec depth

      else:
        inc result



## Lex a double hash line comment.
##
## This comment type starts with ``##`` and automatically ends by the end of the
## respective line.
##
## In case this opening token should be followed by an opening square bracket, a
## redirection to the corresponding comment type will take place in case that it
## should be supported by the respective language.
##
## Languages supporting this type are:
##
## - Nim

proc lexDoubleHashLineComment(lexer: GeneralTokenizer, position: int,
    flags: TokenizerFlags): int =
  result = position

  if lexer.buf[result] == '#':
    inc result

    if lexer.buf[result] == '[':
      if hasDoubleHashBracketComments in flags:
        result = lexDoubleHashBracketComment(lexer, result,
          hasNestedComments in flags)
      else:
        result = endLine(lexer, result)
    else:
      result = endLine(lexer, result)



## Lex a hash bracket comment.
##
## This comment type starts with ``#[`` and ends with ``]#``.  Some languages
## allow for nesting.
##
## Languages supporting this type are:
##
## - Nim

proc lexHashBracketComment(lexer: GeneralTokenizer, position: int,
    nested: bool): int =
  var depth = 0
  result = position

  if lexer.buf[result] == '[':
    inc result

    while true:
      case lexer.buf[result]
      of '\0':
        break

      of '#':
        inc result

        if lexer.buf[result] == '[':
          inc result

          if nested:
            inc depth

      of ']':
        inc result

        if lexer.buf[result] == '#':
          inc result

          if depth == 0:
            break
          elif nested:
            dec depth

      else:
        inc result



## Lex a hash line comment.
##
## This function should be the lexing entry point for all languages which have
## comments introduced by a ``#``.  In case that actually another comment type
## is present, the control flow will be redirected appropriately.
##
## Languages supporting this type are:
##
## - Nim
## - Python
## - YAML

proc lexHashLineComment*(lexer: var GeneralTokenizer, position: int,
    flags: TokenizerFlags): int =
  result = position

  if lexer.buf[result] == '#':
    inc result

    case lexer.buf[result]
    of '#':
      if hasDoubleHashComments in flags:
        lexer.kind = gtStringLit
        result = lexDoubleHashLineComment(lexer, result, flags)
      else:
        result = endLine(lexer, result)

    of '[':
      if hasHashBracketComments in flags:
        lexer.kind = gtLongComment
        result = lexHashBracketComment(lexer, result,
          hasNestedComments in flags)
      else:
        result = endLine(lexer, result)

    of '!':
      if hasShebang in flags:
        lexer.kind = gtPreprocessor

      result = endLine(lexer, result)

    else:
      result = endLine(lexer, result)

#[############################################################################]#
