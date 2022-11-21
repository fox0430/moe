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
# Type declarations.
#

type
  ## The flags to control the behaviour of the highlighting lexer.
  ##
  ## Each language has different lexing requirements regarding certain aspects.
  ## These details can be summarised by a flag representing the necessity to
  ## respect a certain convention.

  TokenizerFlag* = enum
    hasCurlyDashComments,
    hasCurlyDashPipeComments,
    hasDoubleDashCaretComments,
    hasDoubleHashBracketComments,
    hasDoubleHashComments,
    hasHashBracketComments,
    hasHashComments,
    hasNestedComments,
    hasPreprocessor,
    hasShebang,



  ## The set of rules applying for a given language.
  ##
  ## For each language, a set of lexing rules can be formulated in order to
  ## instruct the lexer appropriately.

  TokenizerFlags* = set[TokenizerFlag]



#
# Global variables.
#

const
  ## The lexing rules for Nim.
  flagsNim*: TokenizerFlags = { hasDoubleHashBracketComments
                              , hasDoubleHashComments
                              , hasHashBracketComments
                              , hasHashComments
                              }

  ## The lexing rules for Python.
  flagsPython*: TokenizerFlags = { hasDoubleHashComments
                                 , hasHashComments
                                 , hasShebang
                                 }

  ## The lexing rules for YAML.
  flagsYaml*: TokenizerFlags = { hasHashComments
                               }

#[############################################################################]#
