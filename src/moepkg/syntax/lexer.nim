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

from flags import
  TokenizerFlag,
  TokenizerFlags

from highlite import
  GeneralTokenizer,
  TokenClass

from lexer/hashlexer import
  lexHashLineComment



#
# Procedures.
#

## Lex a hash character (``#``).
##
## Depending on the respective language's lexing rules, determined by its flags,
## a hash character might either be the introduction of a comment or just a
## punctuation sign.

proc lexHash*(lexer: var GeneralTokenizer, position: int,
    flags: TokenizerFlags): int =
  result = position

  if lexer.buf[result] == '#':
    if hasHashComments in flags:
      lexer.kind = gtComment
      result = lexHashLineComment(lexer, result, flags)
    else:
      lexer.kind = gtPunctuation
      inc result

#[############################################################################]#
