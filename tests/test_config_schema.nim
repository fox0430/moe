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

import std/[unittest, options, sequtils, strutils]

import ../src/moepkg/config_schema
import ../src/moepkg/config_loader/base

proc texts(cs: seq[ConfigCandidate]): seq[string] =
  cs.mapIt(it.text)

proc labels(cs: seq[ConfigCandidate]): seq[string] =
  cs.mapIt(it.label)

suite "Config schema - derived data":
  test "Sections come from the config type declarations":
    let names = ConfigSchema.mapIt(it.name)
    check "Standard" in names
    check "Highlight" in names
    check "StartUp.FileOpen" in names
    check "Debug.WindowNode" in names
    check "Lsp" in names
    check "Lsp.Completion" in names
    check "Theme" in names
    check "KeyMapping" in names

  test "Keys carry type, description and accepted values":
    let key = findKey("Standard", "colorMode")
    check key.isSome
    check key.get.valueType == cvtEnum
    check key.get.description.len > 0
    check "256" in key.get.values

  test "Bool keys accept true/false":
    let key = findKey("Standard", "number")
    check key.isSome
    check key.get.valueType == cvtBool
    check key.get.values == @["true", "false"]

  test "Theme kinds stay in step with the loader":
    let key = findKey("Theme", "kind")
    check key.isSome
    check key.get.values == @ValidThemeKinds

  test "A hand-loaded section still lists the key it takes":
    let key = findKey("DisabledCommandAliases", "aliases")
    check key.isSome
    check key.get.valueType == cvtStringArray

  test "A string restricted to an option set completes like an enum":
    let key = findKey("Notification", "popupPosition")
    check key.isSome
    check key.get.valueType == cvtEnum
    check key.get.values == @["bottomRight", "topRight", "topLeft", "bottomLeft"]

  test "Open-ended keys have no value list":
    let key = findKey("Theme", "path")
    check key.isSome
    check key.get.values.len == 0

  test "Sub-table descriptions fill the placeholder":
    let key = findKey("Lsp.Completion", "enable")
    check key.isSome
    check key.get.description == "Enable LSP Completion"

  test "Deprecated keys are not offered":
    for s in ConfigSchema:
      for k in s.keys:
        check not k.description.toLowerAscii.startsWith("deprecated")

suite "Config schema - section headers":
  test "Parse a section header":
    check parseSectionHeader("[Standard]") == some("Standard")
    check parseSectionHeader("  [Lsp.Completion]  ") == some("Lsp.Completion")

  test "Non-header lines are not headers":
    check parseSectionHeader("number = true").isNone
    check parseSectionHeader("# [Standard]").isNone
    check parseSectionHeader("").isNone

  test "A trailing comment does not hide a header":
    check parseSectionHeader("[Standard]  # comment") == some("Standard")
    check parseSectionHeader("[Lsp.Completion] # [Other]") == some("Lsp.Completion")

suite "Config schema - context analysis":
  test "Inside a section header":
    let ctx = analyzeLine("[Sta", 4, "")
    check ctx.kind == cckSection
    check ctx.head == ""

  test "Dotted section header keeps only the parent as head":
    let ctx = analyzeLine("[Lsp.Compl", 10, "")
    check ctx.kind == cckSection
    check ctx.head == "Lsp."

  test "Key position":
    let ctx = analyzeLine("numb", 4, "Standard")
    check ctx.kind == cckKey
    check ctx.section == "Standard"

  test "Value position":
    let ctx = analyzeLine("colorMode = ", 12, "Standard")
    check ctx.kind == cckValue
    check ctx.key == "colorMode"
    check not ctx.inQuotes

  test "Value position inside a string literal":
    let ctx = analyzeLine("colorMode = \"25", 15, "Standard")
    check ctx.kind == cckValue
    check ctx.inQuotes
    check not ctx.hasClosingQuote

  test "Closing quote already present":
    let ctx = analyzeLine("colorMode = \"25\"", 15, "Standard")
    check ctx.kind == cckValue
    check ctx.inQuotes
    check ctx.hasClosingQuote

  test "Comments complete nothing":
    check analyzeLine("# numb", 6, "Standard").kind == cckNone

  test "A trailing comment completes nothing":
    check analyzeLine("number = true  # numb", 21, "Standard").kind == cckNone
    check analyzeLine("[Sta  # [Sta", 12, "").kind == cckNone

  test "A hash inside a string literal is not a comment":
    let ctx = analyzeLine("path = \"~/a#b", 13, "Theme")
    check ctx.kind == cckValue
    check ctx.inQuotes

  test "A closed section header completes nothing":
    check analyzeLine("[Standard]", 10, "").kind == cckNone
    check analyzeLine("[Standard] ", 11, "").kind == cckNone

  test "An escaped quote does not close the string":
    let ctx = analyzeLine("colorMode = \"25\\\"", 15, "Standard")
    check ctx.kind == cckValue
    check ctx.inQuotes
    check not ctx.hasClosingQuote

  test "Outside a string there is no closing quote to reuse":
    let ctx = analyzeLine("colorMode = 25\"", 14, "Standard")
    check ctx.kind == cckValue
    check not ctx.inQuotes
    check not ctx.hasClosingQuote

  test "Keys outside any section complete nothing":
    check analyzeLine("numb", 4, "").kind == cckNone

  test "A literal string is a string too":
    let ctx = analyzeLine("path = '~/a#b", 13, "Theme")
    check ctx.kind == cckValue
    check ctx.inQuotes
    check ctx.quote == '\''

  test "A quote inside a literal string does not open one":
    let ctx = analyzeLine("colorMode = 'a\"b", 16, "Standard")
    check ctx.kind == cckValue
    check ctx.inQuotes
    check ctx.quote == '\''

  test "A backslash in a literal string is not an escape":
    let ctx = analyzeLine("path = 'a\\' ", 12, "Theme")
    check ctx.kind == cckValue
    check not ctx.inQuotes

  test "An open array swallows the lines below it":
    check analyzeLine("\"reserv", 7, "Highlight", inOpenArray = true).kind == cckNone
    check analyzeLine("numb", 4, "Standard", inOpenArray = true).kind == cckNone

suite "Config schema - multi-line arrays":
  test "A value that opens an array raises the depth":
    check arrayDepthAfter("reservedWord = [", 0) == 1
    check arrayDepthAfter("]", 1) == 0

  test "A one-line value nets zero":
    check arrayDepthAfter("reservedWord = [\"a\", \"b\"]", 0) == 0
    check arrayDepthAfter("[Highlight]", 0) == 0

  test "Brackets inside strings and comments do not count":
    check arrayDepthAfter("reservedWord = [\"a[b\"]", 0) == 0
    check arrayDepthAfter("  \"a\", # ]", 1) == 1

suite "Config schema - candidates":
  test "Section candidates offer the full name":
    let cs = candidates(analyzeLine("[Sta", 4, ""))
    check "Standard" in cs.texts
    check "StartUp.FileOpen" in cs.texts

  test "Dotted section candidates drop the typed parent":
    let cs = candidates(analyzeLine("[Lsp.Compl", 10, ""))
    check "Completion" in cs.texts
    check "Lsp.Completion" in cs.labels
    check not cs.texts.anyIt(it.startsWith("Lsp."))

  test "Key candidates come from the enclosing section":
    let cs = candidates(analyzeLine("numb", 4, "Standard"))
    check "number" in cs.texts
    check cs.anyIt(it.text == "number" and it.detail == "bool")

  test "Enum values are quoted TOML strings":
    let cs = candidates(analyzeLine("colorMode = ", 12, "Standard"))
    check "\"256\"" in cs.texts
    check "256" in cs.labels

  test "Inside quotes the value is bare and closes the string":
    let cs = candidates(analyzeLine("colorMode = \"25", 15, "Standard"))
    check "256\"" in cs.texts

  test "Inside a closed string the value stays bare":
    let cs = candidates(analyzeLine("colorMode = \"25\"", 15, "Standard"))
    check "256" in cs.texts

  test "A literal string is closed with its own quote":
    let cs = candidates(analyzeLine("colorMode = '25", 15, "Standard"))
    check "256'" in cs.texts

  test "Bool values are unquoted":
    let cs = candidates(analyzeLine("number = ", 9, "Standard"))
    check cs.texts == @["true", "false"]

  test "Open-ended values offer nothing":
    check candidates(analyzeLine("path = ", 7, "Theme")).len == 0

  test "Unknown sections and keys offer nothing":
    check candidates(analyzeLine("foo", 3, "NoSuchSection")).len == 0
    check candidates(analyzeLine("noSuchKey = ", 12, "Standard")).len == 0
