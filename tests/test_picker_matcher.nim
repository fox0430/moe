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

import std/[unittest, json, os, options, algorithm]
from std/unicode import runes, add

import ../src/moepkg/picker/matcher {.all.}

const FixturePath = currentSourcePath.parentDir / "picker_matcher_fixture.json"

proc matchPos(query, key: string): (Option[int], seq[int]) =
  var
    mt: FuzzyMatcher
    positions: seq[int]
  let score = mt.fuzzyMatchPos(initFuzzyPattern(query), key, positions)
  (score, positions)

proc order(query: string, keys: openArray[string]): seq[string] =
  for r in initFuzzyPattern(query).fuzzyFilter(keys):
    result.add keys[r.index]

proc head(s: string, count: int): string =
  ## The first `count` runes of `s`.
  var n = 0
  for r in s.runes:
    if n == count:
      break
    result.add r
    inc n

proc vimReadsRightByte(key: string, firstPos: int): bool =
  ## Whether the character at `firstPos` starts at byte `firstPos`, where
  ## Vim's tie-break (a character index used as a byte offset) reads the
  ## right byte.
  key.byteOfChar(firstPos) == firstPos

suite "picker/matcher: Vim's matchfuzzypos()":
  # tools/gen_matchfuzzypos_fixture.vim writes the fixture with Vim 9.2.
  let fixture = parseFile(FixturePath)

  for ci, c in fixture["cases"].elems:
    let
      setName = c["set"].getStr
      query = c["query"].getStr
    var keys: seq[string]
    for k in fixture["sets"][setName]:
      keys.add k.getStr

    test "case " & $ci & " (" & setName & "): " & query.head(20):
      let ours = initFuzzyPattern(query).fuzzyFilter(keys)
      var vim: seq[tuple[index, score: int, positions: seq[int]]]
      for m in c["matches"]:
        var positions: seq[int]
        for p in m[2]:
          positions.add p.getInt
        vim.add (m[0].getInt, m[1].getInt, positions)

      check ours.len == vim.len

      for v in vim:
        let (score, positions) = matchPos(query, keys[v.index])
        check score == some(v.score)
        check positions == v.positions

      # Ties keep Vim's order unless its tie-break reads a wrong byte.
      if ours.len == vim.len:
        var i = 0
        while i < vim.len:
          var j = i
          while j < vim.len and vim[j].score == vim[i].score:
            inc j
          var
            oursGroup: seq[int]
            vimGroup: seq[int]
            exactBytes = true
          for k in i ..< j:
            oursGroup.add ours[k].index
            vimGroup.add vim[k].index
            check ours[k].score == vim[k].score
            if not keys[vim[k].index].vimReadsRightByte(vim[k].positions[0]):
              exactBytes = false
          if exactBytes:
            check oursGroup == vimGroup
          else:
            check oursGroup.sorted == vimGroup.sorted
          i = j

suite "picker/matcher: query":
  test "Empty and blank queries have no word and match nothing":
    for q in ["", " ", "\t", "  \t "]:
      check initFuzzyPattern(q).isEmpty
      check matchPos(q, "foo")[0].isNone

  test "Words are split at spaces and tabs only":
    check not initFuzzyPattern("　").isEmpty
    check matchPos("foo\tbar", "bar foo")[0].isSome

suite "picker/matcher: case":
  test "A lower case letter matches either case, an upper case one itself":
    check matchPos("fooBar", "FooBar")[0] == some(FuzzyScoreMax)
    check matchPos("fooBar", "fooBar")[0] == some(FuzzyScoreMax)
    check matchPos("fooBar", "foobar")[0].isNone
    check matchPos("Äbc", "ÄBC")[0].isSome
    check matchPos("Äbc", "äbc")[0].isNone

  test "Scores and positions ignore case":
    check matchPos("AB", "abAB")[1] == @[0, 1]

suite "picker/matcher: score":
  test "The first character of a candidate scores as after a slash":
    check matchPos("a", "ab")[0] == some(895)

  test "Only a word character gets a bonus":
    check matchPos("-", "ab/-")[0] == some(-15)
    check matchPos("_", "ab/_")[0] == some(885)
    check matchPos("a", "x\tab")[0] == some(-15)
    check matchPos("a", "x ab")[0] == some(785)

  test "Backtracking compares the scores as Vim's doubles do":
    check matchPos("a", "x BxaBAa")[1] == @[6]

  test "Word scores add up and saturate in the order of the query":
    check matchPos("ab a", "ab")[0] == some(FuzzyScoreMax)
    check matchPos("ab/- -", "ab/-")[0] == some(2147483632)
    check matchPos("ab/- ab/- -", "ab/-")[0] == some(2147483632)
    check matchPos("- ab/- ab/-", "ab/-")[0] == some(FuzzyScoreMax)

  test "Words may share a position":
    check matchPos("o o", "foo")[1] == @[2, 2]

suite "picker/matcher: characters":
  test "Composing characters are part of the one before":
    check matchPos("a", "éxa")[1] == @[2]
    check matchPos("e", "éxa") == (some(890), @[0])
    check matchPos("é", "e")[0] == some(FuzzyScoreMax)
    check matchPos("é", "é")[0].isNone

  test "A lam and an alef are two characters, unlike Vim":
    # Vim with 'arabicshape' joins them into one character
    check matchPos("x", "لاx") == (some(-10), @[2])
    check matchPos("ا", "لا")[0].isSome

  test "A word may start with a composing character, unlike Vim's positions":
    # Vim lists the positions in a second pass over the query, where the
    # composing character is part of the blank before it, and stops one short
    check matchPos(" ́b", "́b")[1] == @[0, 1]
    check matchPos(" ️́́", "️́́")[1] == @[0]

  test "Only the first 1024 characters are matched":
    var key = ""
    for _ in 0 ..< 1024:
      key.add "あ"
    check matchPos("z", key & "z")[0].isNone
    check matchPos("z", key[0 ..< key.len - "あ".len] & "z")[1] == @[1023]

  test "Rune columns of character positions":
    check fuzzyRuneColumns("éxa", [2, 0]) == @[3, 0]
    check fuzzyRuneColumns("日本", [1]) == @[1]

  test "Byte of a character, -1 past the last":
    check "éxa".byteOfChar(1) == 3
    check "éxa".byteOfChar(3) == -1
    check "".byteOfChar(0) == -1

suite "picker/matcher: order":
  test "Equal scores put the query followed literally first":
    check order("foo", ["FOO", "foo"]) == @["foo", "FOO"]
    check order("foo", ["a-FOO", "a-foo"]) == @["a-foo", "a-FOO"]

  test "The literal match is found by byte, unlike Vim":
    # Vim reads the character index of the first match as a byte offset and
    # keeps these in the source order.
    check order("foo", ["é-FOO", "é-foo"]) == @["é-foo", "é-FOO"]

  test "Otherwise the source order":
    check order("a", ["xa", "ya"]) == @["xa", "ya"]
