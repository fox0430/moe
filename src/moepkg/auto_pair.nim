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

## What a bracket or quote typed in Insert does with `autoCloseParen`, judged
## by the characters on either side of the cursor alone, as mini.pairs does.

import std/[unicode, strutils]

import unicode_utils, char_class
import syntax/tokenizer

type AutoPairAction* = enum
  apNone ## Not a character pairs are made of
  apInsert ## One of them, put in as typed
  apPair ## Put in with its closing character, the cursor between
  apStepOver ## The same character is after the cursor: step over it

proc isPairChar*(typed: string): bool =
  ## Whether `typed` is one of the characters pairs are made of.
  typed.len == 1 and (typed[0].isOpeningParen or typed[0].isClosingParen)

proc isEscaped(runes: openArray[Rune], column: int): bool =
  ## Whether an odd number of backslashes runs up to `column`: the last one
  ## escapes what is typed there, while `\\` is a backslash escaped.
  if column > runes.len:
    return false
  var start = column
  while start > 0 and runes[start - 1] == Rune('\\'):
    dec start
  (column - start) mod 2 == 1

proc asciiLower(r: Rune): char =
  ## The lowercase of an ASCII character, NUL for any other.
  if r.int < 0x80: r.char.toLowerAscii else: '\0'

proc isPythonStringPrefix(runes: openArray[Rune], column: int): bool =
  ## Whether the word that ends at `column` is a whole string prefix of
  ## Python, in either case (`f`, `Rb`), and not a word ending in one (`if`).
  # A prefix is two characters at most, so a longer word stops at three.
  var start = column
  while start > 0 and column - start < 3 and utfClass(runes[start - 1]) >= 2:
    dec start
  case column - start
  of 1:
    runes[start].asciiLower in {'r', 'u', 'f', 't', 'b'}
  of 2:
    # `r` with one of `f`, `t`, `b`, in either order
    {runes[start].asciiLower, runes[start + 1].asciiLower} in
      [{'r', 'f'}, {'r', 't'}, {'r', 'b'}]
  else:
    false

proc autoPairAction*(
    line: string, column: int, typed: string, language: SourceLanguage
): AutoPairAction =
  ## What typing `typed` at `column` of `line` does. After a backslash it goes
  ## in as typed, so `\"` can be typed in a string, but not after `\\`. A
  ## quote after a word character goes in as typed (`don't`), unless the word
  ## is a string prefix in Python (`f'`).
  if not typed.isPairChar:
    return apNone
  let c = typed[0]
  let runes = line.toCharRunes
  if runes.isEscaped(column):
    return apInsert
  # A NUL stands for nothing on the left; it is no word character.
  let left =
    if column > 0 and column <= runes.len:
      runes[runes.baseColumn(column - 1)]
    else:
      Rune(0)
  if c.isClosingParen and column < runes.len and runes[column] == Rune(c):
    return apStepOver
  if c.isOpeningParen:
    if c == '\'' and utfClass(left) >= 2 and
        not (language == langPython and runes.isPythonStringPrefix(column)):
      return apInsert
    return apPair
  apInsert

proc insertedText*(action: AutoPairAction, typed: string): string =
  ## What goes in for `typed`: with its closing character for a pair.
  if action == apPair:
    typed & $getClosingChar(typed[0])
  else:
    typed

proc stepRight*(line: string, column: int): int =
  ## The column past the character at `column` and the composing characters
  ## on it, as Vim's <Right> goes.
  line.toCharRunes.nextCharColumn(column)
