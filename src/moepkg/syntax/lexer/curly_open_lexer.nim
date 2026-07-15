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

from ../flags import TokenizerFlag, TokenizerFlags

from ../tokenizer import GeneralTokenizer, TokenClass

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

proc lexCurlyDashPreprocessor(
    lexer: GeneralTokenizer, position: int, nested: bool
): int =
  var depth = 0
  result = position

  if lexer.buf[result] == '#':
    inc result

    while true:
      case lexer.buf[result]
      of '\0', '\r', '\n':
        # Line-bounded: a {-# pragma has no resume state, so stopping at the
        # line boundary keeps the incremental tokenizer in step with a full
        # reparse (which would otherwise run the pragma across the newline).
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

proc lexCurlyDashComment*(
    lexer: var GeneralTokenizer, position: int, flags: TokenizerFlags
): tuple[endPos: int, commentDepth: int] =
  ## `commentDepth` is the residual nesting depth on an unterminated comment
  ## (0 on clean close). The caller persists it into its own language slot.
  let nested = hasNestedComments in flags
  var
    depth = 0
    pos = position

  if lexer.buf[pos] == '-':
    inc pos

    if lexer.buf[pos] == '#' and hasPreprocessor in flags:
      lexer.kind = gtPreprocessor
      pos = lexer.lexCurlyDashPreprocessor(pos, nested)
    else:
      if lexer.buf[pos] == '|':
        if hasCurlyDashPipeComments in flags:
          lexer.kind = gtDocLongComment
          inc pos

      while true:
        case lexer.buf[pos]
        of '\0':
          lexer.state = lexer.kind
          break
        of '-':
          inc pos

          if lexer.buf[pos] == '}':
            inc pos

            if depth == 0:
              break
            elif nested:
              dec depth
        of '{':
          inc pos

          if lexer.buf[pos] == '-':
            inc pos

            if nested:
              inc depth
        else:
          inc pos

  result = (endPos: pos, commentDepth: depth)
