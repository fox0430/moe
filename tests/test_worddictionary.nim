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

import std/[unittest, critbits]

import ../src/moepkg/syntax/highlite
import ../src/moepkg/worddictionary

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
    d.add("abc")

    check d.contains("abc")

  test "Add duplicate":
    var d: WordDictionary
    d.add("abc")
    d.add("abc")

    check d.contains("abc")
    check d["abc"] == 0

suite "worddictionary: incUsage":
  test "Basic":
    var d: WordDictionary
    d["abc"] = 0

    for i in 0 .. 1:
      d.incUsage("abc")
    check d["abc"] == 2

suite "worddictionary: collect":
  test "Basic":
    var d: WordDictionary
    d["abb"] = 0
    d["abc"] = 0
    d["add"] = 0

    # When usage counts are equal, order is reverse alphabetical (due to reversed sort)
    check d.collect("a") == @["add", "abc", "abb"]
    check d.collect("ab") == @["abc", "abb"]
    check d.collect("abc") == @["abc"]

  test "With inc - sorted by usage":
    var d: WordDictionary
    d["abb"] = 2
    d["abc"] = 1
    d["add"] = 0

    check d.collect("a") == @["abb", "abc", "add"]
    check d.collect("ab") == @["abb", "abc"]
    check d.collect("abb") == @["abb"]

  test "Not found":
    var d: WordDictionary
    d["abb"] = 0
    d["abc"] = 0
    d["add"] = 0

    check d.collect("x").len == 0

suite "worddictionary: enumerateWords":
  test "Basic":
    var r: seq[string]
    for w in enumerateWords("abc def,ghi\n  jkl m no"):
      r.add w

    check r == @["abc", "def", "ghi", "jkl", "no"]

  test "Single character words filtered":
    var r: seq[string]
    for w in enumerateWords("a b c ab"):
      r.add w

    check r == @["ab"]

  test "Numbers in words":
    var r: seq[string]
    for w in enumerateWords("abc123 def456"):
      r.add w

    check r == @["abc123", "def456"]

  test "Underscore in words":
    var r: seq[string]
    for w in enumerateWords("my_var another_one"):
      r.add w

    check r == @["my_var", "another_one"]

  test "Word must start with letter":
    var r: seq[string]
    for w in enumerateWords("123abc _var normal"):
      r.add w

    # 123 is skipped as it starts with a digit, but abc is collected
    # _ is skipped as it's not a letter, but var is collected
    # normal is collected
    check r == @["abc", "var", "normal"]

suite "worddictionary: update":
  test "Basic":
    var d: WordDictionary
    const
      Text = "abc def,ghi\n  jkl m no"
      Exclude = "no"
    d.update(Text, Exclude, langNone)

    check d.contains("abc")
    check d.contains("def")
    check d.contains("ghi")
    check d.contains("jkl")
    check not d.contains("no") # excluded
    check not d.contains("m") # too short

  test "From multiple buffers":
    var d: WordDictionary

    let buffers = @["abc def", "ghi jkl"]
    d.update(buffers, "", langNone)

    check d.contains("abc")
    check d.contains("def")
    check d.contains("ghi")
    check d.contains("jkl")

  test "Inc and update again":
    var d: WordDictionary
    d.update("abc def,ghi\n  jkl m no", "no", langNone)

    d.incUsage("abc")
    d.incUsage("ghi")

    d.update("abc def,ghi\n  jkl m nop qr", "qr", langNone)

    check d["abc"] == 1
    check d["ghi"] == 1
    check d["def"] == 0
    check d["jkl"] == 0
    check d.contains("nop")
    check not d.contains("qr")

  test "With Nim keywords":
    var d: WordDictionary

    d.update("myvar", "", langNim)

    # Check that some Nim keywords are added
    check d.contains("proc")
    check d.contains("func")
    check d.contains("var")
    check d.contains("let")
    check d.contains("const")
    check d.contains("if")
    check d.contains("else")
    check d.contains("true")
    check d.contains("false")

  test "With C keywords":
    var d: WordDictionary

    d.update("myvar", "", langC)

    check d.contains("int")
    check d.contains("void")
    check d.contains("return")
    check d.contains("if")
    check d.contains("else")
    check d.contains("for")
    check d.contains("while")

suite "worddictionary: clear":
  test "Basic":
    var d: WordDictionary
    d["abc"] = 0
    d["def"] = 0

    check d.len == 2

    d.clear()

    check d.len == 0
    check not d.contains("abc")
    check not d.contains("def")

suite "worddictionary: getLanguageKeywords":
  test "C":
    let keywords = getLanguageKeywords(langC)
    check keywords.len > 0
    check "int" in keywords
    check "void" in keywords

  test "Nim":
    let keywords = getLanguageKeywords(langNim)
    check keywords.len > 0
    check "proc" in keywords
    check "func" in keywords
    check "true" in keywords # Boolean

  test "Python":
    let keywords = getLanguageKeywords(langPython)
    check keywords.len > 0
    check "def" in keywords
    check "class" in keywords

  test "Rust":
    let keywords = getLanguageKeywords(langRust)
    check keywords.len > 0
    check "fn" in keywords
    check "let" in keywords
    check "String" in keywords # Builtin

  test "TypeScript":
    let keywords = getLanguageKeywords(langTypeScript)
    check keywords.len > 0
    check "async" in keywords
    check "await" in keywords
    check "interface" in keywords

  test "Shell":
    let keywords = getLanguageKeywords(langShell)
    check keywords.len > 0
    check "if" in keywords
    check "then" in keywords
    check "fi" in keywords

  test "None language":
    let keywords = getLanguageKeywords(langNone)
    check keywords.len == 0
