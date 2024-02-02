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

import std/[unittest, critbits, sequtils]

import moepkg/syntax/highlite
import moepkg/unicodeext

import moepkg/worddictionary {.all.}

suite "worddictionary: contains":
  test "Basic":
    var d: WordDictionary
    d["abc"] = 0
    d["def"] = 0
    d["ghi"] = 0

    check d.contains("abc")
    check d.contains("def")
    check d.contains("ghi")

  test "Not found":
    var d: WordDictionary
    d["abc"] = 0
    d["def"] = 0
    d["ghi"] = 0

    check not d.contains("xyz")

suite "worddictionary: add":
  test "Basic":
    var d: WordDictionary
    d.add(ru"abc")

    check d.contains("abc")

suite "worddictionary: inc":
  test "Basic":
    var d: WordDictionary
    d["abc"] = 0

    for i in 0 .. 1: d.inc("abc")
    check d["abc"] == 2

suite "worddictionary: collect":
  test "Basic":
    var d: WordDictionary
    d["abb"] = 0
    d["abc"] = 0
    d["add"] = 0

    check d.collect(ru"a") == @["add", "abc", "abb"].toSeqRunes
    check d.collect(ru"ab") == @["abc", "abb"].toSeqRunes
    check d.collect(ru"abc") == @["abc"].toSeqRunes

  test "With inc":
    var d: WordDictionary
    d["abb"] = 2
    d["abc"] = 1
    d["add"] = 0

    check d.collect(ru"a") == @["abb", "abc", "add"].toSeqRunes
    check d.collect(ru"ab") == @["abb", "abc"].toSeqRunes
    check d.collect(ru"abb") == @["abb"].toSeqRunes

  test "Not found":
    var d: WordDictionary
    d["abb"] = 0
    d["abc"] = 0
    d["add"] = 0

    check d.collect(ru"x").len == 0

suite "worddictionary: enumerateWords":
  test "Basic":
    var r: seq[Runes]
    for w in enumerateWords("abc def,ghi\n  jkl m no".toRunes): r.add w

    check r == @["abc", "def", "ghi", "jkl", "no"].toSeqRunes

suite "worddictionary: update":
  test "Basic":
    var d: WordDictionary
    const
      Text = "abc def,ghi\n  jkl m no".toRunes
      Exclude = ru"no"
    d.update(Text, Exclude, SourceLanguage.langNone)
    check d.pairs.toSeq == @[
      (key: "", val: 0),
      (key: "abc", val: 0),
      (key: "def", val: 0),
      (key: "ghi", val: 0),
      (key: "jkl", val: 0),
    ]

  test "Basic 2":
    var d: WordDictionary

    const Buffer = @["abc def", "ghi jkl"].toSeqRunes
    d.update(Buffer, ru"", SourceLanguage.langNone)

    check d.pairs.toSeq == @[
      (key: "", val: 0),
      (key: "abc", val: 0),
      (key: "def", val: 0),
      (key: "ghi", val: 0),
      (key: "jkl", val: 0),
    ]

  test "Inc and again":
    var d: WordDictionary
    block:
      const
        Text = "abc def,ghi\n  jkl m no".toRunes
        Exclude = ru"no"
      d.update(Text, Exclude, SourceLanguage.langNone)

    d.inc("abc")
    d.inc("ghi")

    block:
      const
        Text = "abc def,ghi\n  jkl m nop qr".toRunes
        Exclude = ru"qr"
      d.update(Text, Exclude, SourceLanguage.langNone)

    check d.pairs.toSeq == @[
      (key: "", val: 0),
      (key: "abc", val: 1),
      (key: "def", val: 0),
      (key: "ghi", val: 1),
      (key: "jkl", val: 0),
      (key: "nop", val: 0)
    ]
