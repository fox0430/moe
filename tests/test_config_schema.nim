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

import std/[algorithm, unittest, options, sequtils, strutils]

import ../src/moepkg/[config_schema, config_loader]
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

suite "Config schema - drift against the loader":
  ## The hand-written parts of the schema (Theme, DisabledCommandAliases, the
  ## caller-keyed tables) cannot follow the loader on their own, so compare
  ## them here: a section or key added to the loader must fail these until it
  ## is offered by the completion too.

  test "Top-level sections match the ones the loader accepts":
    var top: seq[string] = @[]
    for s in ConfigSchema:
      let name = s.name.split('.')[0]
      if name notin top:
        top.add name
    check top.sorted == (@KnownTopLevelSections).sorted

  test "[StartUp] sub-tables match the ones the loader accepts":
    var offered: seq[string] = @[]
    for s in ConfigSchema:
      let parts = s.name.split('.')
      if parts.len == 2 and parts[0] == "StartUp" and parts[1] notin offered:
        offered.add parts[1]
    check offered.sorted == (@StartUpSubSectionNames).sorted

  test "[Theme] keys match the loader":
    let sec = findSection("Theme")
    check sec.isSome
    check sec.get.keys.mapIt(it.name).sorted == (@ThemeConfigKeys).sorted

  test "[DisabledCommandAliases] keys match the loader":
    let sec = findSection("DisabledCommandAliases")
    check sec.isSome
    check sec.get.keys.mapIt(it.name).sorted == (@DisabledCommandAliasesKeys).sorted

suite "Config schema - section headers":
  test "Parse a section header":
    check parseSectionHeader("[Standard]") == some(("Standard", false))
    check parseSectionHeader("  [Lsp.Completion]  ") == some(("Lsp.Completion", false))

  test "Non-header lines are not headers":
    check parseSectionHeader("number = true").isNone
    check parseSectionHeader("# [Standard]").isNone
    check parseSectionHeader("").isNone

  test "A trailing comment does not hide a header":
    check parseSectionHeader("[Standard]  # comment") == some(("Standard", false))
    check parseSectionHeader("[Lsp.Completion] # [Other]") ==
      some(("Lsp.Completion", false))

  test "An element of a multi-line array is not a header":
    check parseSectionHeader("""  ["a", "b"]""").isNone
    check parseSectionHeader("  ['a']").isNone
    check parseSectionHeader("  [1, 2]").isNone

  test "An array-of-tables header names its section and reports its form":
    check parseSectionHeader("[[Hook.entries]]") == some(("Hook.entries", true))
    # The inner brackets sit against the outer ones; `[ [x] ]` is no header.
    check parseSectionHeader("[ [Hook] ]").isNone
    check parseSectionHeader("  [[ Hook.entries ]]  # c") == some(
      ("Hook.entries", true)
    )

  test "A header names a section only in the bracket form the schema declares":
    # `[X]` and `[[X]]` are different tables to the loader.
    check sectionForHeader("Standard", false) == "Standard"
    check sectionForHeader("Standard", true) == ""
    # A name the schema does not know is left alone: it may be a dynamic
    # keyspace like `[Lsp.python]`.
    check sectionForHeader("Lsp.python", false) == "Lsp.python"

  test "A known header closes an open array":
    check isKnownSectionHeader("Standard")
    check isKnownSectionHeader("Lsp.Completion")

  test "A dynamic child of a known parent closes an open array":
    check isKnownSectionHeader("Lsp.python")

  test "An unknown name or array element does not close an array":
    check not isKnownSectionHeader("NoSuchSection")
    check not isKnownSectionHeader("1")

suite "Config schema - context analysis":
  test "Inside a section header":
    let ctx = analyzeLine("[Sta", 4, "")
    check ctx.kind == cckSection
    check ctx.head == ""

  test "Dotted section header keeps only the parent as head":
    let ctx = analyzeLine("[Lsp.Compl", 10, "")
    check ctx.kind == cckSection
    check ctx.head == "Lsp."

  test "Keys complete inside an array-of-tables section":
    let ctx = analyzeLine("ev", 2, "Hook.entries")
    check ctx.kind == cckKey
    check "event" in candidates(ctx).texts
    check "showOutput" in candidates(ctx).texts

  test "filetype offers the filetype tokens":
    # Without them the only feedback on a misspelled file type is a startup
    # error that names no candidates. The tokens rather than the display names
    # (`C++`, `JavaScriptReact`): they are what `${filetype}` expands to, and
    # what the documentation spells a file type with.
    let ctx = analyzeLine("filetype = [\"", 13, "Hook.entries")
    # Inside an open literal a candidate carries its own closing quote.
    let texts = candidates(ctx).texts
    check "nim\"" in texts
    check "jsx\"" in texts
    # "no language" is what an unmatched file has, not something to write.
    check "none\"" notin texts

  test "An array-of-tables header only offers repeatable sections":
    let ctx = analyzeLine("[[Hook.", 7, "")
    check ctx.kind == cckSection
    check ctx.head == "Hook."
    check ctx.arrayOfTables
    check candidates(ctx).texts == @["entries"]

  test "A single-bracket header never offers an array-of-tables name":
    let ctx = analyzeLine("[Hook.", 6, "")
    check ctx.kind == cckSection
    check not ctx.arrayOfTables
    check "entries" notin candidates(ctx).texts

  test "A space after the bracket keeps the head aligned with the schema":
    let ctx = analyzeLine("[ Lsp.Compl", 11, "")
    check ctx.kind == cckSection
    check ctx.head == "Lsp."
    check "Completion" in candidates(ctx).texts

  test "An adjacent second bracket is an array-of-tables header":
    let ctx = analyzeLine("[[Hook.entr", 11, "")
    check ctx.kind == cckSection
    check ctx.arrayOfTables
    check ctx.head == "Hook."

  test "A gap between the brackets is not an array-of-tables header":
    check analyzeLine("[ [Hook", 7, "").kind == cckNone

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
    # A literal string has no escapes, so the quote after the backslash closes
    # it; in a basic string the backslash would escape the quote.
    check analyzeLine("path = 'a\\' ", 12, "Theme").kind == cckNone
    check analyzeLine("path = \"a\\\" ", 12, "Theme").inQuotes

  test "A value already written completes nothing":
    # The candidate replaces the word before the cursor, so offering one for a
    # finished value would append to it.
    check analyzeLine("colorMode = \"24bit\"", 19, "Standard").kind == cckNone
    check analyzeLine("colorMode = '24bit' ", 20, "Standard").kind == cckNone
    check analyzeLine("filetype = [\"nim\"]", 18, "Hook").kind == cckNone
    # An element closed inside the array does not finish the array itself.
    let ctx = analyzeLine("filetype = [\"nim\", ", 19, "Hook")
    check ctx.kind == cckValue
    check ctx.inArray

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

  test "An array header does not offer single-table sections":
    let single = candidates(analyzeLine("[Lsp.", 5, ""))
    check "Completion" in single.texts
    let arrayed = candidates(analyzeLine("[[Lsp.", 6, ""))
    check "Completion" notin arrayed.texts

  test "An array header offers array-of-tables sections only":
    # No global section is an array of tables yet, so the affirmative side
    # uses a synthetic schema through the same filter.
    let schema = @[
      ConfigSchemaSection(name: "Grp", keys: @[]),
      ConfigSchemaSection(name: "Grp.Single", keys: @[]),
      ConfigSchemaSection(name: "Grp.items", keys: @[], isArrayOfTables: true),
    ]
    check sectionCandidates("Grp.", true, schema).texts == @["items"]
    check sectionCandidates("Grp.", false, schema).texts == @["Single"]

  test "A conditional key carries its condition into the popup":
    # No global key is conditional yet, so the affirmative side uses a
    # synthetic key through the same candidate production.
    let conditional = keyCandidate(
      ConfigSchemaKey(
        name: "io",
        valueType: cvtString,
        typeLabel: "string",
        description: "Where the hook reads input from",
        condition: "only when kind is \"filter\"",
      )
    )
    check conditional.detail == "string, only when kind is \"filter\""
    check "only when kind is \"filter\"" in conditional.documentation
    check "Where the hook reads input from" in conditional.documentation

    let plain = keyCandidate(
      ConfigSchemaKey(
        name: "kind", valueType: cvtString, typeLabel: "string", description: "Kind"
      )
    )
    check plain.detail == "string"
    check plain.documentation == "Kind"

suite "Config schema - array-typed option sets":
  const ArrayKey = ConfigSchemaKey(
    name: "filetype",
    valueType: cvtStringArray,
    typeLabel: "string array (enum: nim, rust)",
    description: "Languages the hook runs for",
    values: @["nim", "rust"],
  )
    # No global key is an option-set array yet, so the shape is covered with a
    # synthetic key through the same candidate production.

  test "A value position outside brackets completes to a one-element array":
    let ctx = analyzeLine("filetype = ", 11, "Hook")
    check ctx.kind == cckValue
    check not ctx.inArray
    check valueCandidatesFor(ArrayKey, ctx).texts == @["[\"nim\"]", "[\"rust\"]"]

  test "A value position inside brackets completes to a bare string":
    let ctx = analyzeLine("filetype = [", 12, "Hook")
    check ctx.kind == cckValue
    check ctx.inArray
    check valueCandidatesFor(ArrayKey, ctx).texts == @["\"nim\"", "\"rust\""]

  test "A literal already open takes the member alone":
    let ctx = analyzeLine("filetype = [\"", 13, "Hook")
    check ctx.inQuotes
    check valueCandidatesFor(ArrayKey, ctx).texts == @["nim\"", "rust\""]

  test "A literal opened without brackets keeps the member alone":
    # The candidate cannot reach back past the opening quote to bracket the
    # value, so the half-written shape stays the user's to finish.
    let ctx = analyzeLine("filetype = \"", 12, "Hook")
    check ctx.inQuotes
    check not ctx.inArray
    check valueCandidatesFor(ArrayKey, ctx).texts == @["nim\"", "rust\""]

  test "A scalar option set is unaffected":
    let ctx = analyzeLine("popupPosition = ", 16, "Notification")
    check valueCandidatesFor(
      ConfigSchemaKey(name: "popupPosition", valueType: cvtEnum, values: @["topLeft"]),
      ctx,
    ).texts == @["\"topLeft\""]

  test "A context that is not a value position answers with nothing":
    # A key or section context must be refused before the `cckValue` fields
    # are read.
    for ctx in [
      analyzeLine("[Hook", 5, ""),
      analyzeLine("  filet", 7, "Hook"),
      analyzeLine("# comment", 9, "Hook"),
    ]:
      check ctx.kind != cckValue
      check valueCandidatesFor(ArrayKey, ctx).len == 0
