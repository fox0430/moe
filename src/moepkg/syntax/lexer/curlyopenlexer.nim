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

from ../flags import
  TokenizerFlag,
  TokenizerFlags

from ../highlite import
  GeneralTokenizer,
  TokenClass



#
# Procedures.
#

## Lex a curly dash preprocessor instruction.
##
## This comment type starts with ``{-#`` and ends with ``#-}``.  Some languages
## allow for nesting.
##
## Languages supporting this type are:
##
## - Haskell

proc lexCurlyDashPreprocessor(lexer: GeneralTokenizer, position: int,
    nested: bool): int =
  var depth = 0
  result = position

  if lexer.buf[result] == '#':
    inc result

    while true:
      case lexer.buf[result]
      of '\0':
        break

      of '#':
        inc result

        if lexer.buf[result] == '-':
          inc result

          if lexer.buf[result] == '}':
            inc result

            if depth == 0:
              break
            elif nested:
              dec depth

      of '{':
        inc result

        if lexer.buf[result] == '-':
          inc result

          if lexer.buf[result] == '#':
            inc result

            if nested:
              inc depth
      else:
        inc result



## Lex a curly dash comment.
##
## This comment type starts with ``{-`` and ends with ``-}``.  Some languages
## allow for nesting.
##
## Languages supporting this type are:
##
## - Haskell

proc lexCurlyDashComment*(lexer: var GeneralTokenizer, position: int,
    flags: TokenizerFlags): int =
  let nested = hasNestedComments in flags
  var depth = 0
  result = position

  if lexer.buf[result] == '-':
    inc result

    if lexer.buf[result] == '#' and hasPreprocessor in flags:
      lexer.kind = gtPreprocessor
      result = lexCurlyDashPreprocessor(lexer, result, nested)
    else:
      if lexer.buf[result] == '|':
        if hasCurlyDashPipeComments in flags:
          lexer.kind = gtStringLit
          inc result

      while true:
        case lexer.buf[result]
        of '\0':
          break

        of '-':
          inc result

          if lexer.buf[result] == '}':
            inc result

            if depth == 0:
              break
            elif nested:
              dec depth

        of '{':
          inc result

          if lexer.buf[result] == '-':
            inc result

            if nested:
              inc depth

        else:
          inc result

#[############################################################################]#
