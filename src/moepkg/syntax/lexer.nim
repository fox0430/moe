#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 fox0430                                             #
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
  TokenizerFlag,
  TokenizerFlags

from highlite import
  GeneralTokenizer,
  TokenClass,
  symChars,
  wsChars

from lexer/curlyopenlexer import
  lexCurlyDashComment

from lexer/endlexer import
  endLine

from lexer/hashlexer import
  lexHashLineComment



#
# Procedures.
#

## Lex a backtick (`` ` ``).
##
## Depending on the respective language's lexing rules, determined by its flags,
## a backtick can be either the beginning of a special string literal or just a
## punctuation mark.

proc lexBacktick*(lexer: var GeneralTokenizer, position: int,
    flags: TokenizerFlags): int =
  result = position

  if lexer.buf[result] == '`':
    if hasBacktickFramedExpressions in flags:
      lexer.kind = gtSpecialVar
      inc result

      if lexer.buf[result] == '`':
        inc result

        if lexer.buf[result] == '`':
          inc result

          if hasTripleBacktickFramedExpressions in flags:
            while true:
              case lexer.buf[result]
              of '\0':
                break

              of '`':
                inc result

                if lexer.buf[result] == '`':
                  inc result

                  if lexer.buf[result] == '`':
                    inc result
                    break

              else:
                inc result
      else:
        while true:
          case lexer.buf[result]
          of '\0':
            break

          of '`':
            inc result
            break

          else:
            inc result
    else:
      lexer.kind = gtPunctuation
      inc result



## Lex an opening curly bracket (``{``).
##
## Depending on the respective language's lexing rules, determined by its flags,
## an opening curly bracket can be either a punctuation mark or the introduction
## of a nested comment.

proc lexCurlyOpen*(lexer: var GeneralTokenizer, position: int,
    flags: TokenizerFlags): int =
  result = position

  if lexer.buf[result] == '{':
    lexer.kind = gtPunctuation
    inc result

    if lexer.buf[result] == '-':
      if hasCurlyDashComments in flags:
        lexer.kind = gtLongComment
        result = lexer.lexCurlyDashComment(result, flags)



## Lex a dash character (``-``).
##
## Depending on the respective language's lexing rules, determined by its flags,
## a dash character can be either the introduction of a comment, a function, the
## beginning of a preprocessor block, the start of a built-in instruction or
## just a punctuation mark.

proc lexDash*(lexer: var GeneralTokenizer, position: int,
    flags: TokenizerFlags): int =
  result = position

  if lexer.buf[result] == '-':
    if hasDashFunction in flags:
      lexer.kind = gtFunctionName
    elif hasDashPunctuation in flags or lexer.state == gtIdentifier:
      lexer.kind = gtPunctuation
      lexer.state = gtPunctuation
    else:
      lexer.kind = gtBuiltin

    inc result

    if lexer.buf[result] == '-':
      inc result

      if hasDoubleDashCaretComments in flags:
        if hasDoubleDashCaretComments in flags:
          if lexer.buf[result] == ' ':
            lexer.kind = gtComment
            inc result

            if lexer.buf[result] == '^':
              lexer.kind = gtStringLit

            result = lexer.endLine(result)
      elif hasDoubleDashComments in flags:
        lexer.kind = gtComment
        result = lexer.endLine(result)

      if lexer.buf[result] == '-':
        inc result

        if hasTripleDashPreprocessor in flags and lexer.buf[result] != '-':
          if hasPreprocessor in flags:
            lexer.kind = gtPreprocessor
          else:
            lexer.kind = gtStringLit

          while true:
            case lexer.buf[result]
            of '\0':
              break

            of '-':
              inc result

              if lexer.buf[result] == '-':
                inc result

                if lexer.buf[result] == '-':
                  inc result
                  break

            else:
              inc result



## Lex a hash character (``#``).
##
## Depending on the respective language's lexing rules, determined by its flags,
## a hash character might either be the introduction of a comment or just a
## punctuation mark.

proc lexHash*(lexer: var GeneralTokenizer, position: int,
    flags: TokenizerFlags): int =
  result = position

  if lexer.buf[result] == '#':
    if hasHashComments in flags:
      lexer.kind = gtComment
      result = lexer.lexHashLineComment(result, flags)
    elif hasHashHeadings in flags and lexer.state == gtWhitespace:
      lexer.kind = gtBuiltin
      lexer.state = gtBuiltin
      result = lexer.endLine(result)
    else:
      lexer.kind = gtPunctuation
      inc result



## Lex an opening sharp bracket (``<``).
##
## Depending on the respective language's lexing rules, determined by its flags,
## an opening sharp bracket might either be the introduction of a comment, a
## function, an operator or just a punctuation mark.

proc lexSharp*(lexer: var GeneralTokenizer, position: int,
    flags: TokenizerFlags): int =
  let nested = hasNestedComments in flags
  var depth = 0
  result = position

  if lexer.buf[result] == '<':
    if hasSharpFunction in flags:
      lexer.kind = gtFunctionName
    elif hasSharpOperator in flags:
      lexer.kind = gtOperator
    elif hasSharpPunctuation in flags:
      lexer.kind = gtPunctuation
    else:
      lexer.kind = gtBuiltin

    inc result

    if lexer.buf[result] == '!':
      inc result

      if lexer.buf[result] == '-':
        inc result

        if lexer.buf[result] == '-':
          inc result

          if hasSharpBangDoubleDashComments in flags:
            lexer.kind = gtLongComment

            while true:
              case lexer.buf[result]
              of '\0':
                break

              of '<':
                inc result

                if lexer.buf[result] == '!':
                  inc result

                  if lexer.buf[result] == '-':
                    inc result

                    if lexer.buf[result] == '-':
                      inc result

                      if nested:
                        inc depth

              of '-':
                inc result

                if lexer.buf[result] == '-':
                  inc result

                  if lexer.buf[result] == '>':
                    inc result

                    if depth == 0:
                      break
                    elif nested:
                      dec depth

              else:
                inc result



## Lex a symbol.
##
## Symbols consist of alphanumeric characters as well as the underscore and the
## second half of the ASCII table.

proc lexSymbol*(lexer: var GeneralTokenizer, position: int): int =
  var id = ""
  result = position

  if lexer.buf[result] in symChars:
    lexer.kind = gtIdentifier
    lexer.state = gtIdentifier

    while lexer.buf[result] in symChars:
      add id, lexer.buf[result]
      inc result



## Lex all whitespace characters.
##
## Numerous languages either do not care at all for whitespace characters or
## only focus on them for indentation.  Thus, they can be skipped without any
## problems.

proc lexWhitespace*(lexer: var GeneralTokenizer, position: int): int =
  result = position

  if lexer.buf[result] in wsChars:
    lexer.kind = gtWhitespace

    while lexer.buf[result] in wsChars:
      if lexer.buf[result] == '\n':
        lexer.state = gtWhitespace
      else:
        lexer.state = gtNone

      inc result

#[############################################################################]#
