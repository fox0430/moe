#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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
import moepkg/syntax/highlite

type
  GT = GeneralTokenizer

proc tokens(code: string): seq[GT] =
  var token = GeneralTokenizer()
  token.initGeneralTokenizer(code)

  while true:
    token.getNextToken(SourceLanguage.langJson)
    if token.kind == gtEof: break
    else:
      result.add token
      # Clear token.buf
      result[^1].buf = ""

suite "syntaxjson: jsonNextToken":
  test "Basic":
    const Code = """
{
  "simple_types": {
    "string": "Hello, World!",
    "number": 42,
    "boolean": true,
    "null": null
  },
  "nested_object": {
    "name": "John Doe",
    "age": 30,
    "address": {
      "street": "123 Main St",
      "city": "Anytown",
      "country": "USA"
    }
  },
  "array": [1, 2, 3, 4, 5],
  "mixed_array": [
    "string",
    42,
    false,
    null,
    { "key": "value" },
    [1, 2, 3]
  ],
  "special_characters": "!@#$%^&*()_+{}[]|\\:;\"'<>,.?/",
  "unicode": "こんにちは、世界！",
  "escaped_characters": "This string has \"quotes\" and a \\ backslash",
  "long_number": 1234567890123456789,
  "scientific_notation": 1.23e-4,
  "empty_structures": {
    "empty_object": {},
    "empty_array": []
  },
  "deep_nesting": {
    "level1": {
      "level2": {
        "level3": {
          "level4": {
            "level5": "Deep nested value"
          }
        }
      }
    }
  }
}
"""

    check tokens(Code) == @[
      GT(kind: gtPunctuation, start: 0, length: 1, buf: "", pos: 1, state: gtEof),
      GT(kind: gtWhitespace, start: 1, length: 3, buf: "", pos: 4, state: gtEof),
      GT(kind: gtStringLit, start: 4, length: 14, buf: "", pos: 18, state: gtEof),
      GT(kind: gtOperator, start: 18, length: 1, buf: "", pos: 19, state: gtEof),
      GT(kind: gtWhitespace, start: 19, length: 1, buf: "", pos: 20, state: gtEof),
      GT(kind: gtPunctuation, start: 20, length: 1, buf: "", pos: 21, state: gtEof),
      GT(kind: gtWhitespace, start: 21, length: 5, buf: "", pos: 26, state: gtEof),
      GT(kind: gtStringLit, start: 26, length: 8, buf: "", pos: 34, state: gtEof),
      GT(kind: gtOperator, start: 34, length: 1, buf: "", pos: 35, state: gtEof),
      GT(kind: gtWhitespace, start: 35, length: 1, buf: "", pos: 36, state: gtEof),
      GT(kind: gtStringLit, start: 36, length: 15, buf: "", pos: 51, state: gtEof),
      GT(kind: gtNone, start: 51, length: 1, buf: "", pos: 52, state: gtEof),
      GT(kind: gtWhitespace, start: 52, length: 5, buf: "", pos: 57, state: gtEof),
      GT(kind: gtStringLit, start: 57, length: 8, buf: "", pos: 65, state: gtEof),
      GT(kind: gtOperator, start: 65, length: 1, buf: "", pos: 66, state: gtEof),
      GT(kind: gtWhitespace, start: 66, length: 1, buf: "", pos: 67, state: gtEof),
      GT(kind: gtDecNumber, start: 67, length: 2, buf: "", pos: 69, state: gtEof),
      GT(kind: gtNone, start: 69, length: 1, buf: "", pos: 70, state: gtEof),
      GT(kind: gtWhitespace, start: 70, length: 5, buf: "", pos: 75, state: gtEof),
      GT(kind: gtStringLit, start: 75, length: 9, buf: "", pos: 84, state: gtEof),
      GT(kind: gtOperator, start: 84, length: 1, buf: "", pos: 85, state: gtEof),
      GT(kind: gtWhitespace, start: 85, length: 1, buf: "", pos: 86, state: gtEof),
      GT(kind: gtKeyword, start: 86, length: 4, buf: "", pos: 90, state: gtEof),
      GT(kind: gtNone, start: 90, length: 1, buf: "", pos: 91, state: gtEof),
      GT(kind: gtWhitespace, start: 91, length: 5, buf: "", pos: 96, state: gtEof),
      GT(kind: gtStringLit, start: 96, length: 6, buf: "", pos: 102, state: gtEof),
      GT(kind: gtOperator, start: 102, length: 1, buf: "", pos: 103, state: gtEof),
      GT(kind: gtWhitespace, start: 103, length: 1, buf: "", pos: 104, state: gtEof),
      GT(kind: gtKeyword, start: 104, length: 4, buf: "", pos: 108, state: gtEof),
      GT(kind: gtWhitespace, start: 108, length: 3, buf: "", pos: 111, state: gtEof),
      GT(kind: gtPunctuation, start: 111, length: 1, buf: "", pos: 112, state: gtEof),
      GT(kind: gtNone, start: 112, length: 1, buf: "", pos: 113, state: gtEof),
      GT(kind: gtWhitespace, start: 113, length: 3, buf: "", pos: 116, state: gtEof),
      GT(kind: gtStringLit, start: 116, length: 15, buf: "", pos: 131, state: gtEof),
      GT(kind: gtOperator, start: 131, length: 1, buf: "", pos: 132, state: gtEof),
      GT(kind: gtWhitespace, start: 132, length: 1, buf: "", pos: 133, state: gtEof),
      GT(kind: gtPunctuation, start: 133, length: 1, buf: "", pos: 134, state: gtEof),
      GT(kind: gtWhitespace, start: 134, length: 5, buf: "", pos: 139, state: gtEof),
      GT(kind: gtStringLit, start: 139, length: 6, buf: "", pos: 145, state: gtEof),
      GT(kind: gtOperator, start: 145, length: 1, buf: "", pos: 146, state: gtEof),
      GT(kind: gtWhitespace, start: 146, length: 1, buf: "", pos: 147, state: gtEof),
      GT(kind: gtStringLit, start: 147, length: 10, buf: "", pos: 157, state: gtEof),
      GT(kind: gtNone, start: 157, length: 1, buf: "", pos: 158, state: gtEof),
      GT(kind: gtWhitespace, start: 158, length: 5, buf: "", pos: 163, state: gtEof),
      GT(kind: gtStringLit, start: 163, length: 5, buf: "", pos: 168, state: gtEof),
      GT(kind: gtOperator, start: 168, length: 1, buf: "", pos: 169, state: gtEof),
      GT(kind: gtWhitespace, start: 169, length: 1, buf: "", pos: 170, state: gtEof),
      GT(kind: gtDecNumber, start: 170, length: 2, buf: "", pos: 172, state: gtEof),
      GT(kind: gtNone, start: 172, length: 1, buf: "", pos: 173, state: gtEof),
      GT(kind: gtWhitespace, start: 173, length: 5, buf: "", pos: 178, state: gtEof),
      GT(kind: gtStringLit, start: 178, length: 9, buf: "", pos: 187, state: gtEof),
      GT(kind: gtOperator, start: 187, length: 1, buf: "", pos: 188, state: gtEof),
      GT(kind: gtWhitespace, start: 188, length: 1, buf: "", pos: 189, state: gtEof),
      GT(kind: gtPunctuation, start: 189, length: 1, buf: "", pos: 190, state: gtEof),
      GT(kind: gtWhitespace, start: 190, length: 7, buf: "", pos: 197, state: gtEof),
      GT(kind: gtStringLit, start: 197, length: 8, buf: "", pos: 205, state: gtEof),
      GT(kind: gtOperator, start: 205, length: 1, buf: "", pos: 206, state: gtEof),
      GT(kind: gtWhitespace, start: 206, length: 1, buf: "", pos: 207, state: gtEof),
      GT(kind: gtStringLit, start: 207, length: 13, buf: "", pos: 220, state: gtEof),
      GT(kind: gtNone, start: 220, length: 1, buf: "", pos: 221, state: gtEof),
      GT(kind: gtWhitespace, start: 221, length: 7, buf: "", pos: 228, state: gtEof),
      GT(kind: gtStringLit, start: 228, length: 6, buf: "", pos: 234, state: gtEof),
      GT(kind: gtOperator, start: 234, length: 1, buf: "", pos: 235, state: gtEof),
      GT(kind: gtWhitespace, start: 235, length: 1, buf: "", pos: 236, state: gtEof),
      GT(kind: gtStringLit, start: 236, length: 9, buf: "", pos: 245, state: gtEof),
      GT(kind: gtNone, start: 245, length: 1, buf: "", pos: 246, state: gtEof),
      GT(kind: gtWhitespace, start: 246, length: 7, buf: "", pos: 253, state: gtEof),
      GT(kind: gtStringLit, start: 253, length: 9, buf: "", pos: 262, state: gtEof),
      GT(kind: gtOperator, start: 262, length: 1, buf: "", pos: 263, state: gtEof),
      GT(kind: gtWhitespace, start: 263, length: 1, buf: "", pos: 264, state: gtEof),
      GT(kind: gtStringLit, start: 264, length: 5, buf: "", pos: 269, state: gtEof),
      GT(kind: gtWhitespace, start: 269, length: 5, buf: "", pos: 274, state: gtEof),
      GT(kind: gtPunctuation, start: 274, length: 1, buf: "", pos: 275, state: gtEof),
      GT(kind: gtWhitespace, start: 275, length: 3, buf: "", pos: 278, state: gtEof),
      GT(kind: gtPunctuation, start: 278, length: 1, buf: "", pos: 279, state: gtEof),
      GT(kind: gtNone, start: 279, length: 1, buf: "", pos: 280, state: gtEof),
      GT(kind: gtWhitespace, start: 280, length: 3, buf: "", pos: 283, state: gtEof),
      GT(kind: gtStringLit, start: 283, length: 7, buf: "", pos: 290, state: gtEof),
      GT(kind: gtOperator, start: 290, length: 1, buf: "", pos: 291, state: gtEof),
      GT(kind: gtWhitespace, start: 291, length: 1, buf: "", pos: 292, state: gtEof),
      GT(kind: gtPunctuation, start: 292, length: 1, buf: "", pos: 293, state: gtEof),
      GT(kind: gtDecNumber, start: 293, length: 1, buf: "", pos: 294, state: gtEof),
      GT(kind: gtNone, start: 294, length: 1, buf: "", pos: 295, state: gtEof),
      GT(kind: gtWhitespace, start: 295, length: 1, buf: "", pos: 296, state: gtEof),
      GT(kind: gtDecNumber, start: 296, length: 1, buf: "", pos: 297, state: gtEof),
      GT(kind: gtNone, start: 297, length: 1, buf: "", pos: 298, state: gtEof),
      GT(kind: gtWhitespace, start: 298, length: 1, buf: "", pos: 299, state: gtEof),
      GT(kind: gtDecNumber, start: 299, length: 1, buf: "", pos: 300, state: gtEof),
      GT(kind: gtNone, start: 300, length: 1, buf: "", pos: 301, state: gtEof),
      GT(kind: gtWhitespace, start: 301, length: 1, buf: "", pos: 302, state: gtEof),
      GT(kind: gtDecNumber, start: 302, length: 1, buf: "", pos: 303, state: gtEof),
      GT(kind: gtNone, start: 303, length: 1, buf: "", pos: 304, state: gtEof),
      GT(kind: gtWhitespace, start: 304, length: 1, buf: "", pos: 305, state: gtEof),
      GT(kind: gtDecNumber, start: 305, length: 1, buf: "", pos: 306, state: gtEof),
      GT(kind: gtPunctuation, start: 306, length: 1, buf: "", pos: 307, state: gtEof),
      GT(kind: gtNone, start: 307, length: 1, buf: "", pos: 308, state: gtEof),
      GT(kind: gtWhitespace, start: 308, length: 3, buf: "", pos: 311, state: gtEof),
      GT(kind: gtStringLit, start: 311, length: 13, buf: "", pos: 324, state: gtEof),
      GT(kind: gtOperator, start: 324, length: 1, buf: "", pos: 325, state: gtEof),
      GT(kind: gtWhitespace, start: 325, length: 1, buf: "", pos: 326, state: gtEof),
      GT(kind: gtPunctuation, start: 326, length: 1, buf: "", pos: 327, state: gtEof),
      GT(kind: gtWhitespace, start: 327, length: 5, buf: "", pos: 332, state: gtEof),
      GT(kind: gtStringLit, start: 332, length: 8, buf: "", pos: 340, state: gtEof),
      GT(kind: gtNone, start: 340, length: 1, buf: "", pos: 341, state: gtEof),
      GT(kind: gtWhitespace, start: 341, length: 5, buf: "", pos: 346, state: gtEof),
      GT(kind: gtDecNumber, start: 346, length: 2, buf: "", pos: 348, state: gtEof),
      GT(kind: gtNone, start: 348, length: 1, buf: "", pos: 349, state: gtEof),
      GT(kind: gtWhitespace, start: 349, length: 5, buf: "", pos: 354, state: gtEof),
      GT(kind: gtKeyword, start: 354, length: 5, buf: "", pos: 359, state: gtEof),
      GT(kind: gtNone, start: 359, length: 1, buf: "", pos: 360, state: gtEof),
      GT(kind: gtWhitespace, start: 360, length: 5, buf: "", pos: 365, state: gtEof),
      GT(kind: gtKeyword, start: 365, length: 4, buf: "", pos: 369, state: gtEof),
      GT(kind: gtNone, start: 369, length: 1, buf: "", pos: 370, state: gtEof),
      GT(kind: gtWhitespace, start: 370, length: 5, buf: "", pos: 375, state: gtEof),
      GT(kind: gtPunctuation, start: 375, length: 1, buf: "", pos: 376, state: gtEof),
      GT(kind: gtWhitespace, start: 376, length: 1, buf: "", pos: 377, state: gtEof),
      GT(kind: gtStringLit, start: 377, length: 5, buf: "", pos: 382, state: gtEof),
      GT(kind: gtOperator, start: 382, length: 1, buf: "", pos: 383, state: gtEof),
      GT(kind: gtWhitespace, start: 383, length: 1, buf: "", pos: 384, state: gtEof),
      GT(kind: gtStringLit, start: 384, length: 7, buf: "", pos: 391, state: gtEof),
      GT(kind: gtWhitespace, start: 391, length: 1, buf: "", pos: 392, state: gtEof),
      GT(kind: gtPunctuation, start: 392, length: 1, buf: "", pos: 393, state: gtEof),
      GT(kind: gtNone, start: 393, length: 1, buf: "", pos: 394, state: gtEof),
      GT(kind: gtWhitespace, start: 394, length: 5, buf: "", pos: 399, state: gtEof),
      GT(kind: gtPunctuation, start: 399, length: 1, buf: "", pos: 400, state: gtEof),
      GT(kind: gtDecNumber, start: 400, length: 1, buf: "", pos: 401, state: gtEof),
      GT(kind: gtNone, start: 401, length: 1, buf: "", pos: 402, state: gtEof),
      GT(kind: gtWhitespace, start: 402, length: 1, buf: "", pos: 403, state: gtEof),
      GT(kind: gtDecNumber, start: 403, length: 1, buf: "", pos: 404, state: gtEof),
      GT(kind: gtNone, start: 404, length: 1, buf: "", pos: 405, state: gtEof),
      GT(kind: gtWhitespace, start: 405, length: 1, buf: "", pos: 406, state: gtEof),
      GT(kind: gtDecNumber, start: 406, length: 1, buf: "", pos: 407, state: gtEof),
      GT(kind: gtPunctuation, start: 407, length: 1, buf: "", pos: 408, state: gtEof),
      GT(kind: gtWhitespace, start: 408, length: 3, buf: "", pos: 411, state: gtEof),
      GT(kind: gtPunctuation, start: 411, length: 1, buf: "", pos: 412, state: gtEof),
      GT(kind: gtNone, start: 412, length: 1, buf: "", pos: 413, state: gtEof),
      GT(kind: gtWhitespace, start: 413, length: 3, buf: "", pos: 416, state: gtEof),
      GT(kind: gtStringLit, start: 416, length: 20, buf: "", pos: 436, state: gtEof),
      GT(kind: gtOperator, start: 436, length: 1, buf: "", pos: 437, state: gtEof),
      GT(kind: gtWhitespace, start: 437, length: 1, buf: "", pos: 438, state: gtEof),
      GT(kind: gtStringLit, start: 438, length: 18, buf: "", pos: 456, state: gtStringLit),
      GT(kind: gtEscapeSequence, start: 456, length: 2, buf: "", pos: 458, state: gtStringLit),
      GT(kind: gtStringLit, start: 458, length: 2, buf: "", pos: 460, state: gtStringLit),
      GT(kind: gtEscapeSequence, start: 460, length: 2, buf: "", pos: 462, state: gtStringLit),
      GT(kind: gtStringLit, start: 462, length: 8, buf: "", pos: 470, state: gtNone),
      GT(kind: gtNone, start: 470, length: 1, buf: "", pos: 471, state: gtNone),
      GT(kind: gtWhitespace, start: 471, length: 3, buf: "", pos: 474, state: gtNone),
      GT(kind: gtStringLit, start: 474, length: 9, buf: "", pos: 483, state: gtNone),
      GT(kind: gtOperator, start: 483, length: 1, buf: "", pos: 484, state: gtNone),
      GT(kind: gtWhitespace, start: 484, length: 1, buf: "", pos: 485, state: gtNone),
      GT(kind: gtStringLit, start: 485, length: 29, buf: "", pos: 514, state: gtNone),
      GT(kind: gtNone, start: 514, length: 1, buf: "", pos: 515, state: gtNone),
      GT(kind: gtWhitespace, start: 515, length: 3, buf: "", pos: 518, state: gtNone),
      GT(kind: gtStringLit, start: 518, length: 20, buf: "", pos: 538, state: gtNone),
      GT(kind: gtOperator, start: 538, length: 1, buf: "", pos: 539, state: gtNone),
      GT(kind: gtWhitespace, start: 539, length: 1, buf: "", pos: 540, state: gtNone),
      GT(kind: gtStringLit, start: 540, length: 17, buf: "", pos: 557, state: gtStringLit),
      GT(kind: gtEscapeSequence, start: 557, length: 2, buf: "", pos: 559, state: gtStringLit),
      GT(kind: gtStringLit, start: 559, length: 6, buf: "", pos: 565, state: gtStringLit),
      GT(kind: gtEscapeSequence, start: 565, length: 2, buf: "", pos: 567, state: gtStringLit),
      GT(kind: gtStringLit, start: 567, length: 7, buf: "", pos: 574, state: gtStringLit),
      GT(kind: gtEscapeSequence, start: 574, length: 2, buf: "", pos: 576, state: gtStringLit),
      GT(kind: gtStringLit, start: 576, length: 11, buf: "", pos: 587, state: gtNone),
      GT(kind: gtNone, start: 587, length: 1, buf: "", pos: 588, state: gtNone),
      GT(kind: gtWhitespace, start: 588, length: 3, buf: "", pos: 591, state: gtNone),
      GT(kind: gtStringLit, start: 591, length: 13, buf: "", pos: 604, state: gtNone),
      GT(kind: gtOperator, start: 604, length: 1, buf: "", pos: 605, state: gtNone),
      GT(kind: gtWhitespace, start: 605, length: 1, buf: "", pos: 606, state: gtNone),
      GT(kind: gtDecNumber, start: 606, length: 19, buf: "", pos: 625, state: gtNone),
      GT(kind: gtNone, start: 625, length: 1, buf: "", pos: 626, state: gtNone),
      GT(kind: gtWhitespace, start: 626, length: 3, buf: "", pos: 629, state: gtNone),
      GT(kind: gtStringLit, start: 629, length: 21, buf: "", pos: 650, state: gtNone),
      GT(kind: gtOperator, start: 650, length: 1, buf: "", pos: 651, state: gtNone),
      GT(kind: gtWhitespace, start: 651, length: 1, buf: "", pos: 652, state: gtNone),
      GT(kind: gtFloatNumber, start: 652, length: 7, buf: "", pos: 659, state: gtNone),
      GT(kind: gtNone, start: 659, length: 1, buf: "", pos: 660, state: gtNone),
      GT(kind: gtWhitespace, start: 660, length: 3, buf: "", pos: 663, state: gtNone),
      GT(kind: gtStringLit, start: 663, length: 18, buf: "", pos: 681, state: gtNone),
      GT(kind: gtOperator, start: 681, length: 1, buf: "", pos: 682, state: gtNone),
      GT(kind: gtWhitespace, start: 682, length: 1, buf: "", pos: 683, state: gtNone),
      GT(kind: gtPunctuation, start: 683, length: 1, buf: "", pos: 684, state: gtNone),
      GT(kind: gtWhitespace, start: 684, length: 5, buf: "", pos: 689, state: gtNone),
      GT(kind: gtStringLit, start: 689, length: 14, buf: "", pos: 703, state: gtNone),
      GT(kind: gtOperator, start: 703, length: 1, buf: "", pos: 704, state: gtNone),
      GT(kind: gtWhitespace, start: 704, length: 1, buf: "", pos: 705, state: gtNone),
      GT(kind: gtPunctuation, start: 705, length: 1, buf: "", pos: 706, state: gtNone),
      GT(kind: gtPunctuation, start: 706, length: 1, buf: "", pos: 707, state: gtNone),
      GT(kind: gtNone, start: 707, length: 1, buf: "", pos: 708, state: gtNone),
      GT(kind: gtWhitespace, start: 708, length: 5, buf: "", pos: 713, state: gtNone),
      GT(kind: gtStringLit, start: 713, length: 13, buf: "", pos: 726, state: gtNone),
      GT(kind: gtOperator, start: 726, length: 1, buf: "", pos: 727, state: gtNone),
      GT(kind: gtWhitespace, start: 727, length: 1, buf: "", pos: 728, state: gtNone),
      GT(kind: gtPunctuation, start: 728, length: 1, buf: "", pos: 729, state: gtNone),
      GT(kind: gtPunctuation, start: 729, length: 1, buf: "", pos: 730, state: gtNone),
      GT(kind: gtWhitespace, start: 730, length: 3, buf: "", pos: 733, state: gtNone),
      GT(kind: gtPunctuation, start: 733, length: 1, buf: "", pos: 734, state: gtNone),
      GT(kind: gtNone, start: 734, length: 1, buf: "", pos: 735, state: gtNone),
      GT(kind: gtWhitespace, start: 735, length: 3, buf: "", pos: 738, state: gtNone),
      GT(kind: gtStringLit, start: 738, length: 14, buf: "", pos: 752, state: gtNone),
      GT(kind: gtOperator, start: 752, length: 1, buf: "", pos: 753, state: gtNone),
      GT(kind: gtWhitespace, start: 753, length: 1, buf: "", pos: 754, state: gtNone),
      GT(kind: gtPunctuation, start: 754, length: 1, buf: "", pos: 755, state: gtNone),
      GT(kind: gtWhitespace, start: 755, length: 5, buf: "", pos: 760, state: gtNone),
      GT(kind: gtStringLit, start: 760, length: 8, buf: "", pos: 768, state: gtNone),
      GT(kind: gtOperator, start: 768, length: 1, buf: "", pos: 769, state: gtNone),
      GT(kind: gtWhitespace, start: 769, length: 1, buf: "", pos: 770, state: gtNone),
      GT(kind: gtPunctuation, start: 770, length: 1, buf: "", pos: 771, state: gtNone),
      GT(kind: gtWhitespace, start: 771, length: 7, buf: "", pos: 778, state: gtNone),
      GT(kind: gtStringLit, start: 778, length: 8, buf: "", pos: 786, state: gtNone),
      GT(kind: gtOperator, start: 786, length: 1, buf: "", pos: 787, state: gtNone),
      GT(kind: gtWhitespace, start: 787, length: 1, buf: "", pos: 788, state: gtNone),
      GT(kind: gtPunctuation, start: 788, length: 1, buf: "", pos: 789, state: gtNone),
      GT(kind: gtWhitespace, start: 789, length: 9, buf: "", pos: 798, state: gtNone),
      GT(kind: gtStringLit, start: 798, length: 8, buf: "", pos: 806, state: gtNone),
      GT(kind: gtOperator, start: 806, length: 1, buf: "", pos: 807, state: gtNone),
      GT(kind: gtWhitespace, start: 807, length: 1, buf: "", pos: 808, state: gtNone),
      GT(kind: gtPunctuation, start: 808, length: 1, buf: "", pos: 809, state: gtNone),
      GT(kind: gtWhitespace, start: 809, length: 11, buf: "", pos: 820, state: gtNone),
      GT(kind: gtStringLit, start: 820, length: 8, buf: "", pos: 828, state: gtNone),
      GT(kind: gtOperator, start: 828, length: 1, buf: "", pos: 829, state: gtNone),
      GT(kind: gtWhitespace, start: 829, length: 1, buf: "", pos: 830, state: gtNone),
      GT(kind: gtPunctuation, start: 830, length: 1, buf: "", pos: 831, state: gtNone),
      GT(kind: gtWhitespace, start: 831, length: 13, buf: "", pos: 844, state: gtNone),
      GT(kind: gtStringLit, start: 844, length: 8, buf: "", pos: 852, state: gtNone),
      GT(kind: gtOperator, start: 852, length: 1, buf: "", pos: 853, state: gtNone),
      GT(kind: gtWhitespace, start: 853, length: 1, buf: "", pos: 854, state: gtNone),
      GT(kind: gtStringLit, start: 854, length: 19, buf: "", pos: 873, state: gtNone),
      GT(kind: gtWhitespace, start: 873, length: 11, buf: "", pos: 884, state: gtNone),
      GT(kind: gtPunctuation, start: 884, length: 1, buf: "", pos: 885, state: gtNone),
      GT(kind: gtWhitespace, start: 885, length: 9, buf: "", pos: 894, state: gtNone),
      GT(kind: gtPunctuation, start: 894, length: 1, buf: "", pos: 895, state: gtNone),
      GT(kind: gtWhitespace, start: 895, length: 7, buf: "", pos: 902, state: gtNone),
      GT(kind: gtPunctuation, start: 902, length: 1, buf: "", pos: 903, state: gtNone),
      GT(kind: gtWhitespace, start: 903, length: 5, buf: "", pos: 908, state: gtNone),
      GT(kind: gtPunctuation, start: 908, length: 1, buf: "", pos: 909, state: gtNone),
      GT(kind: gtWhitespace, start: 909, length: 3, buf: "", pos: 912, state: gtNone),
      GT(kind: gtPunctuation, start: 912, length: 1, buf: "", pos: 913, state: gtNone),
      GT(kind: gtWhitespace, start: 913, length: 1, buf: "", pos: 914, state: gtNone),
      GT(kind: gtPunctuation, start: 914, length: 1, buf: "", pos: 915, state: gtNone),
      GT(kind: gtWhitespace, start: 915, length: 1, buf: "", pos: 916, state: gtNone)
    ]
