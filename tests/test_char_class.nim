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

import std/[unittest, unicode]

import ../src/moepkg/[char_class, unicode_utils]

suite "utfClass":
  # Expectations are Vim 9.2's charclass().
  test "classes of Latin-1, by Vim's default 'iskeyword'":
    for (c, class) in [
      (0x00, 1), # A NUL in the text is Vim's line feed
      (0x20, 0),
      (0x09, 0),
      (0xa0, 0),
      ('a'.ord, 2),
      ('_'.ord, 2),
      ('0'.ord, 2),
      ('.'.ord, 1),
      ('\r'.ord, 1),
      (0xb5, 2),
      (0xaa, 1),
      (0xb2, 1), # Superscript two
      (0xd7, 2),
      (0xff, 2),
    ]:
      checkpoint($c)
      check utfClass(Rune(c)) == class

  test "classes from Vim's table above Latin-1":
    for (c, class) in [
      (0x3000, 0), # Ideographic space
      (0x3001, 1), # Ideographic comma
      (0x3005, 1), # Ideographic iteration mark
      (0x3042, 0x3040), # Hiragana
      (0x30ab, 0x30a0), # Katakana
      (0x30fc, 0x30a0), # Katakana prolonged sound mark
      (0x6f22, 0x4e00), # CJK ideograph
      (0xac00, 0xac00), # Hangul syllable
      (0x2070, 0x2070), # Superscript zero
      (0x2081, 0x2080), # Subscript one
      (0x2801, 0x2800), # Braille
      (0xff08, 1), # Fullwidth parenthesis
      (0xff46, 2), # Fullwidth small f
      (0x0430, 2), # Cyrillic small a
    ]:
      checkpoint($c)
      check utfClass(Rune(c)) == class

  test "emoji are a class of their own, before the table":
    for c in [0x1f600, 0x2122, 0x3030]:
      checkpoint($c)
      check utfClass(Rune(c)) == 3

  test "an undecodable byte is classed as the byte":
    check utfClass(invalidByteRune(0xa0)) == 0
    check utfClass(invalidByteRune(0xe3)) == 2
    check utfClass(invalidByteRune(0x85)) == 1

  test "Ctrl-W's mb_get_class reads an undecodable 0xa0 alone, as no blank":
    check mbClass(invalidByteRune(0xa0)) == 1
    check mbClass(invalidByteRune(0xe3)) == 2
    check mbClass(Rune(0xa0)) == 0

suite "composing characters":
  test "Vim's composing characters, not every zero-width one":
    for c in [0x0301, 0x20e3, 0x3099, 0xfe0f, 0xe0100]:
      checkpoint($c)
      check Rune(c).isComposing
    for c in ['a'.ord, 0x00a0, 0x200b, 0x200d, 0x2060, 0xfeff]:
      checkpoint($c)
      check not Rune(c).isComposing

  test "a composing character is part of the one before it":
    let runes = "x❤️\u20e3y".toRunes
    check runes.baseColumn(0) == 0
    check runes.baseColumn(2) == 1
    check runes.baseColumn(3) == 1
    check runes.baseColumn(4) == 4
    check "\u0301x".toRunes.baseColumn(0) == 0
    # Nor does it go with an undecodable byte
    check @[Rune('a'), invalidByteRune(0x85), Rune(0x0301)].baseColumn(2) == 2

suite "Vim's blanks":
  test "VIM_ISWHITE and vim_isspace":
    check Rune('\t').isVimWhite
    check not Rune(0x0b).isVimWhite
    check Rune(0x0b).isVimSpace
    check Rune(0).isVimSpace # A NUL in the text is Vim's line feed
    check not Rune(0x3000).isVimSpace
