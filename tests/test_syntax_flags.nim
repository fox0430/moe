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

import std/unittest

import ../src/moepkg/syntax/flags

suite "flags - Nim flags":
  test "Nim has hash comments":
    check hasHashComments in flagsNim

  test "Nim has double hash comments":
    check hasDoubleHashComments in flagsNim

  test "Nim has hash bracket comments":
    check hasHashBracketComments in flagsNim

  test "Nim has double hash bracket comments":
    check hasDoubleHashBracketComments in flagsNim

  test "Nim has nested comments":
    check hasNestedComments in flagsNim

  test "Nim has sharp operator":
    check hasSharpOperator in flagsNim

  test "Nim does not have shebang":
    check hasShebang notin flagsNim

  test "Nim does not have preprocessor":
    check hasPreprocessor notin flagsNim

suite "flags - Python flags":
  test "Python has hash comments":
    check hasHashComments in flagsPython

  test "Python has double hash comments":
    check hasDoubleHashComments in flagsPython

  test "Python has sharp operator":
    check hasSharpOperator in flagsPython

  test "Python has shebang":
    check hasShebang in flagsPython

  test "Python does not have nested comments":
    check hasNestedComments notin flagsPython

suite "flags - Haskell flags":
  test "Haskell has curly dash comments":
    check hasCurlyDashComments in flagsHaskell

  test "Haskell has curly dash pipe comments":
    check hasCurlyDashPipeComments in flagsHaskell

  test "Haskell has double dash comments":
    check hasDoubleDashComments in flagsHaskell

  test "Haskell has nested comments":
    check hasNestedComments in flagsHaskell

  test "Haskell has preprocessor":
    check hasPreprocessor in flagsHaskell

  test "Haskell has dash function":
    check hasDashFunction in flagsHaskell

  test "Haskell has sharp function":
    check hasSharpFunction in flagsHaskell

suite "flags - Shell flags":
  test "Shell has hash comments":
    check hasHashComments in flagsShell

  test "Shell has shebang":
    check hasShebang in flagsShell

  test "Shell flags has exactly two elements":
    check flagsShell.card == 2

suite "flags - Markdown flags":
  test "Markdown has backtick framed expressions":
    check hasBacktickFramedExpressions in flagsMarkdown

  test "Markdown has hash headings":
    check hasHashHeadings in flagsMarkdown

  test "Markdown has triple backtick framed expressions":
    check hasTripleBacktickFramedExpressions in flagsMarkdown

  test "Markdown has triple dash preprocessor":
    check hasTripleDashPreprocessor in flagsMarkdown

suite "flags - YAML flags":
  test "YAML has hash comments":
    check hasHashComments in flagsYaml

  test "YAML has dash punctuation":
    check hasDashPunctuation in flagsYaml

  test "YAML does not have shebang":
    check hasShebang notin flagsYaml

suite "flags - TOML flags":
  test "TOML has hash comments":
    check hasHashComments in flagsToml

  test "TOML flags has exactly one element":
    check flagsToml.card == 1
