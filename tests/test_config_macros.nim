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

import std/[unittest, macros, options, sequtils, sets, strutils, tables]

import pkg/parsetoml

import ../src/moepkg/[config_macros, config, config_schema, help_description]
import ../tools/gen_config_docs
import ../src/moepkg/config_loader {.all.}

# Sample annotated type — proves the pragma vocabulary parses and is reflectable
# via `hasCustomPragma` / `getCustomPragmaVal`.
type
  SampleEnum* = enum
    seA = "a"
    seB = "b"
    seC = "c"

  SampleSection* {.cfgSection: "Sample".} = object
    flag* {.cfg.}: bool
    count* {.cfg, cfgMin: 0, cfgMax: 10.}: int
    note* {.cfg, cfgUiName: "Note (label)".}: string
    choice* {.cfg, cfgEnum: ["c", "a"].}: SampleEnum
    conditional* {.cfg, cfgVisible: alwaysVisible.}: bool
    mode* {.cfg, cfgEnumStrings: ["x", "y"].}: string
    legacy* {.cfgSkip.}: bool

# `cfgVisible` stores the predicate identifier verbatim; the descriptor macro
# is what eventually wraps it as `proc(c: EditorConfig): bool {.noSideEffect.}`.
# Since this file never runs that macro, the predicate signature is not
# checked here — a `SampleSection`-taking proc is fine for pragma reflection.
proc alwaysVisible*(_: SampleSection): bool {.noSideEffect.} =
  true

suite "config_macros: pragma vocabulary":
  test "cfgSection attaches to the type":
    check hasCustomPragma(SampleSection, cfgSection)
    check getCustomPragmaVal(SampleSection, cfgSection) == "Sample"

  test "cfg attaches to a field":
    var s: SampleSection
    check hasCustomPragma(s.flag, cfg)
    check hasCustomPragma(s.count, cfg)
    check hasCustomPragma(s.note, cfg)

  test "cfgSkip excludes a field":
    var s: SampleSection
    check hasCustomPragma(s.legacy, cfgSkip)
    check not hasCustomPragma(s.flag, cfgSkip)

  test "cfgUiName carries a UI label":
    var s: SampleSection
    check hasCustomPragma(s.note, cfgUiName)
    check getCustomPragmaVal(s.note, cfgUiName) == "Note (label)"

  test "cfgEnum attaches an override option list":
    var s: SampleSection
    check hasCustomPragma(s.choice, cfgEnum)

  test "cfgVisible attaches a predicate identifier":
    var s: SampleSection
    check hasCustomPragma(s.conditional, cfgVisible)

  test "cfgEnumStrings attaches a fixed option list":
    var s: SampleSection
    check hasCustomPragma(s.mode, cfgEnumStrings)

# Exercise generateConfigLoader against a mini section so a regression in the
# macro surfaces here, isolated from the full EditorConfig wiring.
type MiniSection {.cfgSection: "Mini".} = object
  flag {.cfg.}: bool
  count {.cfg, cfgMin: 0, cfgMax: 10.}: int
  label {.cfg.}: string
  mode {.cfg, cfgEnumStrings: ["x", "y"].}: string

proc loadMini(t: TomlTableRef, c: var MiniSection, vr: var ValidationResult) =
  generateConfigLoader(t, c, vr, MiniSection)

proc tomlTable(s: string): TomlTableRef =
  parsetoml.parseString(s).getTable

suite "config_macros: generateConfigLoader":
  test "loads bool, int, string fields":
    let t = tomlTable("flag = true\ncount = 5\nlabel = \"hello\"\nmode = \"x\"\n")
    var c: MiniSection
    var vr = newValidationResult()
    loadMini(t, c, vr)
    check c.flag
    check c.count == 5
    check c.label == "hello"
    check c.mode == "x"
    check not vr.hasErrors

  test "applies cfgMin / cfgMax bounds":
    let t = tomlTable("count = 99\n")
    var c: MiniSection
    var vr = newValidationResult()
    loadMini(t, c, vr)
    check vr.hasErrors
    check c.count == 0 # out-of-range -> field is not assigned

  test "flags unknown keys":
    let t = tomlTable("flag = true\nbogus = 1\n")
    var c: MiniSection
    var vr = newValidationResult()
    loadMini(t, c, vr)
    var sawUnknown = false
    for e in vr.errors:
      if e.kind == sikUnknownKey and "bogus" in e.name:
        sawUnknown = true
    check sawUnknown

  test "cfgEnumStrings accepts in-set values":
    let t = tomlTable("mode = \"y\"\n")
    var c: MiniSection
    var vr = newValidationResult()
    loadMini(t, c, vr)
    check c.mode == "y"
    check not vr.hasErrors

  test "cfgEnumStrings rejects an out-of-set value and keeps the default":
    # A refused value keeps the default, as in every other load helper.
    let t = tomlTable("mode = \"bogus\"\n")
    var c = MiniSection(mode: "y")
    var vr = newValidationResult()
    loadMini(t, c, vr)
    check vr.errors.anyIt(it.name == "Mini.mode" and it.val == "bogus")
    check c.mode == "y"

# Exercise the serializer against a section covering every supported field type,
# then prove its output round-trips back through generateConfigLoader.
type SerEnum = enum
  seX = "x"
  seY = "y"

type SerSection {.cfgSection: "Ser".} = object
  flag {.cfg.}: bool
  count {.cfg.}: int
  ratio {.cfg.}: float
  label {.cfg.}: string
  choice {.cfg.}: SerEnum
  tags {.cfg.}: seq[string]
  maybe {.cfg.}: Option[string]
  renamed {.cfg, cfgKey: "Renamed".}: bool

proc parseSerEnum(s: string): SerEnum =
  parseEnum[SerEnum](s)

const ValidSerEnums = ["x", "y"]

# Wrap the all-field-types section in an outer type so the serializer is
# exercised through the same generateSectionSerializers dispatch production uses.
type SerOuter = object
  ser: SerSection

proc serializeSer(lines: var seq[string], cfg: SerSection) =
  let o = SerOuter(ser: cfg)
  generateSectionSerializers(lines, o, SerOuter)

proc loadSer(t: TomlTableRef, c: var SerSection, vr: var ValidationResult) =
  generateConfigLoader(t, c, vr, SerSection)

suite "config_macros: section serializer field-type coverage":
  test "emits header, typed lines, and trailing blank":
    var cfg = SerSection(
      flag: true,
      count: 7,
      ratio: 1.5,
      label: "hi",
      choice: seY,
      tags: @["a", "b"],
      maybe: none(string),
      renamed: true,
    )
    var lines: seq[string]
    serializeSer(lines, cfg)
    check lines[0] == "[Ser]"
    check "flag = true" in lines
    check "count = 7" in lines
    check "ratio = 1.5" in lines
    check "label = \"hi\"" in lines
    check "choice = \"y\"" in lines
    check "tags = [\"a\", \"b\"]" in lines
    check "Renamed = true" in lines # cfgKey override applied
    check lines[^1] == "" # trailing blank separator

  test "omits Option[string] when none, emits when some":
    block:
      var lines: seq[string]
      serializeSer(lines, SerSection(maybe: none(string)))
      check not lines.anyIt(it.startsWith("maybe = "))
    block:
      var lines: seq[string]
      serializeSer(lines, SerSection(maybe: some("val")))
      check "maybe = \"val\"" in lines

  test "empty seq[string] still emitted as []":
    var lines: seq[string]
    serializeSer(lines, SerSection(tags: @[]))
    check "tags = []" in lines

  test "serializer output round-trips through the loader":
    var original = SerSection(
      flag: true,
      count: 42,
      ratio: 3.25,
      label: "round trip",
      choice: seY,
      tags: @["one", "two"],
      maybe: some("present"),
      renamed: true,
    )
    var lines: seq[string]
    serializeSer(lines, original)
    # Drop the "[Ser]" header and blank line; the loader takes the table body.
    let body = lines[1 ..< lines.len].join("\n")
    var loaded: SerSection
    var vr = newValidationResult()
    loadSer(tomlTable(body), loaded, vr)
    check not vr.hasErrors
    check loaded == original

# A conditional key: the serializer writes it only for the shape it belongs to,
# and the loader rejects it on any other.
type WwSection {.cfgSection: "Ww".} = object
  flag {.cfg, cfgDocDescription: "Whether the note applies".}: bool
  note {.cfg, cfgOnlyWhen(wwShowsNote, "flag is true"), cfgDocDescription: "A note".}:
    string

proc wwShowsNote(v: WwSection): bool =
  v.flag

# The same, with the conditional key declared *before* what its predicate
# reads. The checks run after the whole object has loaded, so the declaration
# order must not matter.
type WwReordered {.cfgSection: "Ww".} = object
  note {.
    cfg, cfgOnlyWhen(wwReorderedShowsNote, "flag is true"), cfgDocDescription: "A note"
  .}: string
  flag {.cfg.}: bool

proc wwReorderedShowsNote(v: WwReordered): bool =
  v.flag

proc loadWwReordered(t: TomlTableRef, c: var WwReordered, vr: var ValidationResult) =
  generateConfigLoader(t, c, vr, WwReordered)

type WwOuter = object
  ww: WwSection

proc serializeWw(lines: var seq[string], cfg: WwSection) =
  let o = WwOuter(ww: cfg)
  generateSectionSerializers(lines, o, WwOuter)

proc loadWw(t: TomlTableRef, c: var WwSection, vr: var ValidationResult) =
  generateConfigLoader(t, c, vr, WwSection)

suite "config_macros: cfgOnlyWhen":
  test "emits the key only when the predicate holds":
    block:
      var lines: seq[string]
      serializeWw(lines, WwSection(flag: true, note: "hi"))
      check "note = \"hi\"" in lines
    block:
      var lines: seq[string]
      serializeWw(lines, WwSection(flag: false, note: "hi"))
      check "flag = false" in lines
      check not lines.anyIt(it.startsWith("note = "))

  test "a file saved without the key loads back":
    var lines: seq[string]
    serializeWw(lines, WwSection(flag: false, note: "hi"))
    let body = lines[1 ..< lines.len].join("\n")
    var loaded: WwSection
    var vr = newValidationResult()
    loadWw(tomlTable(body), loaded, vr)
    check not vr.hasErrors
    check loaded.flag == false
    check loaded.note == ""

  test "the loader rejects the key on an object the serializer would not write it for":
    # Rejected rather than silently ignored.
    var loaded: WwSection
    var vr = newValidationResult()
    loadWw(tomlTable("flag = false\nnote = \"hi\"\n"), loaded, vr)
    check vr.hasErrors
    check vr.errors.anyIt(it.name == "Ww.note" and "flag is true" in it.expected)
    # A rejected value does not stay in the field.
    check loaded.note == ""

  test "the loader accepts the key when the predicate holds":
    var loaded: WwSection
    var vr = newValidationResult()
    loadWw(tomlTable("flag = true\nnote = \"hi\"\n"), loaded, vr)
    check not vr.hasErrors
    check loaded.note == "hi"

  test "the condition reaches the schema, so completion need not guess":
    # The loader refuses the key on the wrong object and the serializer omits
    # it, so the schema has to carry the condition too.
    var schema: seq[ConfigSchemaSection]
    generateConfigSchema(schema, WwOuter)
    let note = schema.filterIt(it.name == "Ww")[0].keys.filterIt(it.name == "note")
    check note.len == 1
    check note[0].condition == "only when flag is true"
    let flag = schema.filterIt(it.name == "Ww")[0].keys.filterIt(it.name == "flag")
    check flag[0].condition == ""

  test "the condition reaches the docs next to the key it qualifies":
    let table = generateSectionMarkdown(WwOuter(ww: WwSection()), ww, WwSection)
    check "| note |" in table
    check "(only when flag is true)" in table

  test "the verdict does not depend on which field is declared first":
    block:
      var loaded: WwReordered
      var vr = newValidationResult()
      loadWwReordered(tomlTable("flag = true\nnote = \"hi\"\n"), loaded, vr)
      check not vr.hasErrors
      check loaded.note == "hi"
    block:
      var loaded: WwReordered
      var vr = newValidationResult()
      loadWwReordered(tomlTable("flag = false\nnote = \"hi\"\n"), loaded, vr)
      check vr.errors.anyIt(it.name == "Ww.note" and "flag is true" in it.expected)
      check loaded.note == ""

# Single-source section registry: a mini "outer" type standing in for
# EditorConfig, used to exercise the whole-config dispatch macros in isolation.
type
  AlphaSection {.cfgSection: "Alpha".} = object
    on {.cfg.}: bool
    size {.cfg.}: int

  BetaSection {.cfgSection: "Beta".} = object
    name {.cfg.}: string

  # Nested section: its cfgSection name contains a dot, so it must be treated as
  # living under a parent table ([Mini.Gamma] under [Mini]) — excluded from the
  # top-level names and the auto loader dispatch, but still serialized flat.
  GammaNested {.cfgSection: "Mini.Gamma".} = object
    flag {.cfg.}: bool

  MiniOuter = object
    alpha: AlphaSection
    beta: BetaSection
    gamma: GammaNested # nested (dotted) section -> not a top-level table
    notASection: int # no {.cfgSection.} -> must be ignored by the walk

proc saveOuter(lines: var seq[string], o: MiniOuter) =
  generateSectionSerializers(lines, o, MiniOuter)

proc loadOuter(toml: TomlTableRef, o: var MiniOuter, vr: var ValidationResult) =
  generateSectionLoaders(toml, o, vr, MiniOuter)

const MiniSectionNames = generateSimpleSectionNames(MiniOuter)

# A section whose field type the macros cannot handle, used for negative tests.
type
  BadSection {.cfgSection: "Bad".} = object
    weird {.cfg.}: seq[int]

  BadOuter = object
    bad: BadSection

suite "config_macros: single-source section registry":
  test "generateSimpleSectionNames lists only flat {.cfgSection.} fields":
    # Gamma is nested ("Mini.Gamma"), so it is excluded structurally — no
    # hand-kept list. notASection has no {.cfgSection.} so it is ignored.
    check MiniSectionNames == ["Alpha", "Beta"]
    check "Mini.Gamma" notin MiniSectionNames

  test "loader + serializer dispatch round-trip the whole outer type":
    var original = MiniOuter(
      alpha: AlphaSection(on: true, size: 9), beta: BetaSection(name: "hello")
    )
    var lines: seq[string]
    saveOuter(lines, original)
    # Output carries both section headers, in field-declaration order.
    check "[Alpha]" in lines
    check "[Beta]" in lines
    check lines.find("[Alpha]") < lines.find("[Beta]")

    var loaded: MiniOuter
    var vr = newValidationResult()
    loadOuter(tomlTable(lines.join("\n")), loaded, vr)
    check not vr.hasErrors
    check loaded == original

  test "serializer dispatch rejects an unsupported field type at compile time":
    check not compiles(
      (
        block:
          var lines: seq[string]
          var o: BadOuter
          generateSectionSerializers(lines, o, BadOuter)
      )
    )

  test "loader dispatch rejects an unsupported field type at compile time":
    check not compiles(
      (
        block:
          var o: BadOuter
          var vr = newValidationResult()
          generateSectionLoaders(tomlTable(""), o, vr, BadOuter)
      )
    )

  test "nested (dotted) section is serialized flat but skipped by names + loader":
    # Nested-ness is derived from the dot in the cfgSection name, with no
    # hand-kept registry: the serializer emits [Mini.Gamma], while the name list
    # and the loader dispatch (which leaves nested sections to the hand-written
    # parent path) both skip it.
    check "Mini.Gamma" notin MiniSectionNames
    var lines: seq[string]
    saveOuter(lines, MiniOuter(gamma: GammaNested(flag: true)))
    check "[Mini.Gamma]" in lines
    check "flag = true" in lines

    var loaded: MiniOuter
    var vr = newValidationResult()
    loadOuter(tomlTable(lines.join("\n")), loaded, vr)
    check not vr.hasErrors
    check not loaded.gamma.flag # not loaded by the auto dispatch

# Exercise `cfgDeprecated`: the loader still assigns the value (keeping old
# configs working), records a deprecation notice, and the serializer skips
# the field so it fades out on the next save.
type DeprSection {.cfgSection: "Depr".} = object
  keep {.cfg.}: bool
  gone {.cfg, cfgDeprecated: "use keep instead".}: bool

proc loadDepr(t: TomlTableRef, c: var DeprSection, vr: var ValidationResult) =
  generateConfigLoader(t, c, vr, DeprSection)

type DeprOuter = object
  depr: DeprSection

proc serializeDepr(lines: var seq[string], cfg: DeprSection) =
  let o = DeprOuter(depr: cfg)
  generateSectionSerializers(lines, o, DeprOuter)

suite "config_macros: cfgDeprecated":
  test "loader assigns the value and records a deprecation notice":
    let t = tomlTable("keep = false\ngone = true\n")
    var c: DeprSection
    var vr = newValidationResult()
    loadDepr(t, c, vr)
    check not c.keep
    check c.gone # value still loaded for backward compatibility
    var sawDeprecated = false
    for e in vr.errors:
      if e.kind == sikDeprecated and e.name == "Depr.gone":
        sawDeprecated = true
        check "use keep instead" in e.expected
    check sawDeprecated

  test "loader stays silent when the deprecated key is absent":
    let t = tomlTable("keep = true\n")
    var c: DeprSection
    var vr = newValidationResult()
    loadDepr(t, c, vr)
    check not vr.errors.anyIt(it.kind == sikDeprecated)

  test "deprecated key does not surface as an unknown key":
    let t = tomlTable("gone = true\n")
    var c: DeprSection
    var vr = newValidationResult()
    loadDepr(t, c, vr)
    check not vr.errors.anyIt(it.kind == sikUnknownKey and "gone" in it.name)

  test "serializer skips deprecated fields":
    var cfg = DeprSection(keep: true, gone: true)
    var lines: seq[string]
    serializeDepr(lines, cfg)
    check "keep = true" in lines
    check not lines.anyIt(it.startsWith("gone = "))

  test "toMessage renders the deprecation notice":
    let item =
      SettingIssue(kind: sikDeprecated, name: "Depr.gone", expected: "use keep instead")
    let msg = item.toMessage
    check "Depr.gone" in msg
    check "Deprecated" in msg
    check "use keep instead" in msg

  test "hasErrors excludes deprecation notices":
    let t = tomlTable("gone = true\n")
    var c: DeprSection
    var vr = newValidationResult()
    loadDepr(t, c, vr)
    check vr.hasDeprecations
    check not vr.hasErrors # deprecation alone must not read as an error
    check vr.toErrorMessages.len == 0
    check vr.toDeprecationMessages.len == 1
    check "Depr.gone" in vr.toDeprecationMessages[0]

  test "hasErrors still reports real errors alongside a deprecation":
    # gone is a bool; feed a non-bool so the loader records an actual error,
    # plus the deprecation notice for the key being present.
    let t = tomlTable("gone = \"nope\"\n")
    var c: DeprSection
    var vr = newValidationResult()
    loadDepr(t, c, vr)
    check vr.hasErrors
    check vr.hasDeprecations
    check vr.toErrorMessages.len == 1
    check "Invalid value" in vr.toErrorMessages[0]
    check vr.toDeprecationMessages.len == 1

# Exercise section groups: a parent table whose `{.cfgSubSection.}` fields are
# `[Parent.Child]` sub-tables. Two fields share one type — the case the
# `{.cfgSection.}` type pragma cannot express.
const ElemModes = @["pipe", "none"]
const ElemTags = @["fast", "slow"]

type
  FeatureSub = object
    on {.cfg.}: bool

  WideSub = object
    on {.cfg.}: bool
    extra {.cfg.}: int

  GroupSection {.cfgGroup: "Group".} = object
    top {.cfg.}: bool
    limit {.cfg, cfgMin: 1.}: int
    first {.cfgSubSection: "First".}: FeatureSub
    second {.cfgSubSection: "Second".}: FeatureSub
    wide {.cfgSubSection: "Wide".}: WideSub

proc loadGroup(t: TomlTableRef, c: var GroupSection, vr: var ValidationResult) =
  generateSectionGroupLoader(t, c, vr, GroupSection)

proc saveGroup(lines: var seq[string], cfg: GroupSection) =
  generateSectionGroupSerializer(lines, cfg, GroupSection)

suite "config_macros: section groups":
  test "generateSectionGroupKeys lists scalars then sub-table names":
    const keys = generateSectionGroupKeys(GroupSection)
    check keys == ["top", "limit", "First", "Second", "Wide"]

  test "loader fills each sub-table independently":
    let t = tomlTable(
      """
top = true
limit = 3

[First]
on = true

[Wide]
on = true
extra = 7
"""
    )
    var c: GroupSection
    var vr = newValidationResult()
    loadGroup(t, c, vr)
    check not vr.hasErrors
    check c.top
    check c.limit == 3
    check c.first.on
    check not c.second.on # absent table keeps its value
    check c.wide.on
    check c.wide.extra == 7

  test "sub-table issues are reported under the dotted section name":
    let t = tomlTable("[First]\ntypo = true\n")
    var c: GroupSection
    var vr = newValidationResult()
    loadGroup(t, c, vr)
    check vr.errors.anyIt(it.kind == sikUnknownKey and it.name == "Group.First.typo")

  test "constraint pragmas apply to the parent table's own keys":
    let t = tomlTable("limit = 0\n")
    var c: GroupSection
    var vr = newValidationResult()
    loadGroup(t, c, vr)
    check vr.hasErrors
    check "Group.limit" in vr.errors[0].name

  test "unknown keys of the parent table are left to the caller":
    ## A group's parent table may also carry a dynamic keyspace (`[Lsp.<lang>]`),
    ## so the macro must not reject leftovers on its own.
    let t = tomlTable("mystery = true\n")
    var c: GroupSection
    var vr = newValidationResult()
    loadGroup(t, c, vr)
    check not vr.hasErrors

  test "serializer emits the parent header then one per sub-table":
    var lines: seq[string]
    saveGroup(lines, GroupSection(top: true, limit: 5, wide: WideSub(extra: 7)))
    check lines.find("[Group]") < lines.find("[Group.First]")
    check lines.find("[Group.First]") < lines.find("[Group.Second]")
    check "[Group.Wide]" in lines
    check "extra = 7" in lines

  test "loader and serializer round-trip the whole group":
    let original = GroupSection(
      top: true,
      limit: 5,
      first: FeatureSub(on: true),
      wide: WideSub(on: true, extra: 7),
    )
    var lines: seq[string]
    saveGroup(lines, original)

    # The serializer writes absolute `[Group...]` headers; the loader is handed
    # the parent table's contents, matching how the config entry point calls it.
    let parsed = tomlTable(lines.join("\n"))["Group"].getTable()

    var loaded: GroupSection
    var vr = newValidationResult()
    loadGroup(parsed, loaded, vr)
    check not vr.hasErrors
    check loaded == original

  test "a field cannot be both a scalar key and a sub-table":
    # Driven through generateSectionGroupKeys on purpose: it neither builds a
    # loader nor a serializer body, so the conflict guard is the only thing
    # that can reject this type.
    check not compiles(
      (
        block:
          type Bad {.cfgGroup: "Bad".} = object
            oops {.cfg, cfgSubSection: "Oops".}: FeatureSub

          const keys = generateSectionGroupKeys(Bad)
      )
    )

  test "two sub-tables cannot claim the same name":
    check not compiles(
      (
        block:
          type Bad {.cfgGroup: "Bad".} = object
            a {.cfgSubSection: "Dup".}: FeatureSub
            b {.cfgSubSection: "Dup".}: FeatureSub

          const keys = generateSectionGroupKeys(Bad)
      )
    )

  test "a sub-table name cannot collide with a scalar key":
    check not compiles(
      (
        block:
          type Bad {.cfgGroup: "Bad".} = object
            Dup {.cfg.}: bool
            b {.cfgSubSection: "Dup".}: FeatureSub

          const keys = generateSectionGroupKeys(Bad)
      )
    )

  test "the guard is reachable from every group macro":
    ## Each macro must validate the pragmas before building its bodies,
    ## otherwise an unrelated "unsupported field type" error masks the guard.
    check not compiles(
      (
        block:
          type Bad {.cfgGroup: "Bad".} = object
            a {.cfgSubSection: "Dup".}: FeatureSub
            b {.cfgSubSection: "Dup".}: FeatureSub

          var lines: seq[string]
          var o: Bad
          generateSectionGroupSerializer(lines, o, Bad)
      )
    )

type
  ArrayElem = object
    name {.cfg, cfgDocDescription: "Name".}: string
    mode {.cfg, cfgEnumStrings: ElemModes, cfgDocDescription: "Mode".}: string = "none"
    tags {.cfg, cfgEnumStrings: ElemTags, cfgDocDescription: "Tags".}: seq[string]

  ArrayGroup {.cfgGroup: "Arr".} = object
    top {.cfg.}: bool
    entries {.
      cfgArrayOfTables: "entries", cfgEntryRules: checkElem, cfgArrayRules: checkElems
    .}: seq[ArrayElem]

proc checkElem(
    t: TomlTableRef, e: var ArrayElem, label: string, vr: var ValidationResult
): bool =
  # Only what a declaration cannot state; everything else comes off `ArrayElem`.
  if not t.hasKey("name"):
    vr.addError(label, "missing 'name' key", "table with 'name'")
    return false
  true

proc checkElems(entries: var seq[ArrayElem], label: string, vr: var ValidationResult) =
  # A rule about the entries together: names identify an entry, so they cannot
  # repeat.
  var seen: HashSet[string]
  var kept: seq[ArrayElem]
  for e in entries:
    if e.name in seen:
      vr.addError(label, e.name, "entry names that do not repeat")
    else:
      seen.incl e.name
      kept.add e
  entries = kept

proc loadArrayGroup(t: TomlTableRef, c: var ArrayGroup, vr: var ValidationResult) =
  generateSectionGroupLoader(t, c, vr, ArrayGroup)

proc saveArrayGroup(lines: var seq[string], cfg: ArrayGroup) =
  generateSectionGroupSerializer(lines, cfg, ArrayGroup)

suite "config_macros: arrays of tables":
  test "a present array replaces the field's default":
    let t = tomlTable("[[entries]]\nname = \"a\"\n\n[[entries]]\nname = \"b\"\n")
    var c = ArrayGroup(entries: @[ArrayElem(name: "default")])
    var vr = newValidationResult()
    loadArrayGroup(t, c, vr)
    check not vr.hasErrors
    check c.entries.mapIt(it.name) == @["a", "b"]

  test "an absent array keeps the default":
    let t = tomlTable("top = true\n")
    var c = ArrayGroup(entries: @[ArrayElem(name: "default")])
    var vr = newValidationResult()
    loadArrayGroup(t, c, vr)
    check c.entries.mapIt(it.name) == @["default"]

  test "an entry the loader drops is not added":
    let t = tomlTable("[[entries]]\nname = \"a\"\n\n[[entries]]\nmode = \"pipe\"\n")
    var c: ArrayGroup
    var vr = newValidationResult()
    loadArrayGroup(t, c, vr)
    check c.entries.mapIt(it.name) == @["a"]

  test "a cfgEnumStrings violation is reported and the field keeps its default":
    # An option set rejects; it does not choose a replacement.
    let t = tomlTable("[[entries]]\nname = \"a\"\nmode = \"bogus\"\n")
    var c: ArrayGroup
    var vr = newValidationResult()
    loadArrayGroup(t, c, vr)
    check vr.errors.anyIt(it.name == "Arr.entries[0].mode" and it.val == "bogus")
    check c.entries.len == 1
    check c.entries[0].mode == "none"

  test "a valid cfgEnumStrings passes without errors":
    let t = tomlTable("[[entries]]\nname = \"a\"\nmode = \"pipe\"\n")
    var c: ArrayGroup
    var vr = newValidationResult()
    loadArrayGroup(t, c, vr)
    check not vr.hasErrors
    check c.entries[0].mode == "pipe"

  test "an empty named option set is rejected":
    # A set with no members accepts nothing, so the declaration is a mistake.
    check not compiles(
      (
        block:
          const EmptyModes = @[]

          type EmptyValues {.cfgSection: "Empty".} = object
            mode {.cfg, cfgEnumStrings: EmptyModes.}: string

          var o: EmptyValues
          var vr = newValidationResult()
          generateConfigLoader(tomlTable("mode = \"x\"\n"), o, vr, EmptyValues)
      )
    )

  test "an option set constrains each element of a seq[string]":
    let t = tomlTable("[[entries]]\nname = \"a\"\ntags = [\"fast\", \"bogus\"]\n")
    var c: ArrayGroup
    var vr = newValidationResult()
    loadArrayGroup(t, c, vr)
    check vr.hasErrors
    check vr.errors.anyIt(it.name == "Arr.entries[0].tags[1]" and it.val == "bogus")
    # One key is one value: a rejected element takes the whole array with it
    # and the field keeps its default.
    check c.entries[0].tags.len == 0

  test "an option set is reported once against the value the user wrote":
    # The set is checked on the parsed value, so a wrong-typed value is one
    # error naming what the user typed, not a second one naming the default.
    let t = tomlTable("[[entries]]\nname = \"a\"\nmode = 1\n")
    var c: ArrayGroup
    var vr = newValidationResult()
    loadArrayGroup(t, c, vr)
    check vr.errors.filterIt(it.name == "Arr.entries[0].mode").len == 1
    check vr.errors.anyIt(it.name == "Arr.entries[0].mode" and it.val == "1")
    check c.entries[0].mode == "none"

  test "an option set on a seq is not reported against a default that never loaded":
    # The array case of the same rule: only `tags` itself is reported.
    let t = tomlTable("[[entries]]\nname = \"a\"\ntags = 1\n")
    var c: ArrayGroup
    var vr = newValidationResult()
    loadArrayGroup(t, c, vr)
    check vr.errors.filterIt(it.name.startsWith("Arr.entries[0].tags")).len == 1
    check vr.errors.anyIt(it.name == "Arr.entries[0].tags")

  test "a non-array value for an array field is reported":
    let t = tomlTable("entries = 1\n")
    var c: ArrayGroup
    var vr = newValidationResult()
    loadArrayGroup(t, c, vr)
    check vr.hasErrors

  test "a non-table element is reported and skipped":
    let t = tomlTable("entries = [1]\n")
    var c = ArrayGroup(entries: @[])
    var vr = newValidationResult()
    loadArrayGroup(t, c, vr)
    check vr.hasErrors
    check c.entries.len == 0

  test "a value that is not an array leaves the field alone":
    # A value that is not an array says nothing about the entries, so the
    # default stands.
    let t = tomlTable("entries = 1\n")
    var c = ArrayGroup(entries: @[ArrayElem(name: "default")])
    var vr = newValidationResult()
    loadArrayGroup(t, c, vr)
    check vr.hasErrors
    check vr.errors.anyIt(it.name == "Arr.entries" and it.val == "1")
    check c.entries.mapIt(it.name) == @["default"]

  test "an unknown key in an entry is reported":
    let t = tomlTable("[[entries]]\nname = \"a\"\nbogus = 1\n")
    var c: ArrayGroup
    var vr = newValidationResult()
    loadArrayGroup(t, c, vr)
    check c.entries.mapIt(it.name) == @["a"]
    var sawUnknown = false
    for e in vr.errors:
      if e.kind == sikUnknownKey and "bogus" in e.name:
        sawUnknown = true
    check sawUnknown

  test "the serializer emits one array header per element and round-trips":
    let original = ArrayGroup(
      top: true,
      entries: @[ArrayElem(name: "a", mode: "pipe"), ArrayElem(name: "b", mode: "none")],
    )
    var lines: seq[string]
    saveArrayGroup(lines, original)
    check lines.count("[[Arr.entries]]") == 2
    check "name = \"a\"" in lines
    let parsed = tomlTable(lines.join("\n"))["Arr"].getTable()
    var loaded: ArrayGroup
    var vr = newValidationResult()
    loadArrayGroup(parsed, loaded, vr)
    check not vr.hasErrors
    check loaded == original

  test "the schema reports a named option set as a closed set":
    # A named `{.cfgEnumStrings.}` set must still read as an enum, or the
    # popup and the docs advertise a free-form string.
    var schema: seq[ConfigSchemaSection]
    generateSectionGroupSchema(schema, ArrayGroup)
    let entries = schema.filterIt(it.name == "Arr.entries")
    check entries.len == 1
    check entries[0].isArrayOfTables
    let mode = entries[0].keys.filterIt(it.name == "mode")
    check mode.len == 1
    check mode[0].valueType == cvtEnum
    check mode[0].values == ElemModes
    check mode[0].typeLabel == "string (enum: pipe, none)"

  test "an option set on a seq reads as an array of that set, not a free-form one":
    # The set narrows what goes inside the array, so the shape stays an array
    # while the label and the values say what may go in it.
    var schema: seq[ConfigSchemaSection]
    generateSectionGroupSchema(schema, ArrayGroup)
    let tags =
      schema.filterIt(it.name == "Arr.entries")[0].keys.filterIt(it.name == "tags")
    check tags.len == 1
    check tags[0].valueType == cvtStringArray
    check tags[0].values == ElemTags
    check tags[0].typeLabel == "string array (enum: fast, slow)"

  test "a rule about the entries together runs once, after the per-entry rules":
    let t = tomlTable(
      "[[entries]]\nname = \"a\"\n\n[[entries]]\nname = \"a\"\n\n" &
        "[[entries]]\nname = \"b\"\n"
    )
    var c: ArrayGroup
    var vr = newValidationResult()
    loadArrayGroup(t, c, vr)
    check vr.errors.anyIt(it.name == "Arr.entries" and it.val == "a")
    check c.entries.mapIt(it.name) == @["a", "b"]

  test "a rule about the entries together is rejected without an array to run on":
    check not compiles(
      (
        block:
          type NoArray {.cfgGroup: "NoArray".} = object
            sub {.cfgSubSection: "Sub".}: ArrayElem
            stray {.cfg, cfgArrayRules: checkElems.}: string

          var o: NoArray
          var vr = newValidationResult()
          generateSectionGroupLoader(tomlTable(""), o, vr, NoArray)
      )
    )

  test "a rule about the entries is rejected on a single child table":
    # Without the check the pragma sits on a {.cfgSubSection.} field and no
    # predicate is ever emitted.
    check not compiles(
      (
        block:
          type SubRules {.cfgGroup: "SubRules".} = object
            sub {.cfgSubSection: "Sub", cfgEntryRules: checkElem.}: ArrayElem

          var o: SubRules
          var vr = newValidationResult()
          generateSectionGroupLoader(tomlTable(""), o, vr, SubRules)
      )
    )
    check not compiles(
      (
        block:
          type SubRules {.cfgGroup: "SubRules".} = object
            sub {.cfgSubSection: "Sub", cfgArrayRules: checkElems.}: ArrayElem

          var o: SubRules
          var vr = newValidationResult()
          generateSectionGroupLoader(tomlTable(""), o, vr, SubRules)
      )
    )

  test "a ref element type is rejected":
    # The generated loader declares `var entry: Elem` and writes through it,
    # which for a ref type is nil. The shape walk sees through `ref`, so
    # without this check the declaration compiles and segfaults.
    check not compiles(
      (
        block:
          type RefElem = ref object
            name {.cfg.}: string

          type RefGroup {.cfgGroup: "RefGroup".} = object
            entries {.cfgArrayOfTables: "entries".}: seq[RefElem]

          var o: RefGroup
          var vr = newValidationResult()
          generateSectionGroupLoader(tomlTable(""), o, vr, RefGroup)
      )
    )

  test "a table below a repeated one is rejected":
    # `[Parent.entries.sub]` does not say which element it belongs to.
    check not compiles(
      (
        block:
          type NestedElem = object
            name {.cfg.}: string
            sub {.cfgSubSection: "Sub".}: FeatureSub

          type NestedGroup {.cfgGroup: "NestedGroup".} = object
            entries {.cfgArrayOfTables: "entries".}: seq[NestedElem]

          var o: NestedGroup
          var vr = newValidationResult()
          generateSectionGroupLoader(tomlTable(""), o, vr, NestedGroup)
      )
    )

  test "an array of tables is rejected outside a section group":
    # On a plain `{.cfgSection.}` type the pragma expands to nothing: the
    # field would never load and its table would read as unknown.
    check not compiles(
      (
        block:
          type Bad {.cfgSection: "Bad".} = object
            flag {.cfg.}: bool
            entries {.cfgArrayOfTables: "entries".}: seq[ArrayElem]

          var o: Bad
          var vr = newValidationResult()
          generateConfigLoader(tomlTable("flag = true\n"), o, vr, Bad)
      )
    )

  test "a sub-table is rejected outside a section group":
    check not compiles(
      (
        block:
          type Bad {.cfgSection: "Bad".} = object
            flag {.cfg.}: bool
            sub {.cfgSubSection: "Sub".}: FeatureSub

          var o: Bad
          var vr = newValidationResult()
          generateConfigLoader(tomlTable("flag = true\n"), o, vr, Bad)
      )
    )

  test "a non-object array element is rejected":
    check not compiles(
      (
        block:
          type BadGroup {.cfgGroup: "Bad".} = object
            entries {.cfgArrayOfTables: "entries".}: seq[SampleEnum]

          const keys = generateSectionGroupKeys(BadGroup)
      )
    )

  test "a non-object sub-table is rejected":
    check not compiles(
      (
        block:
          type BadGroup {.cfgGroup: "Bad".} = object
            sub {.cfgSubSection: "Sub".}: SampleEnum

          const keys = generateSectionGroupKeys(BadGroup)
      )
    )

  test "a childless group schema is rejected":
    check not compiles(
      (
        block:
          type EmptyGroup {.cfgGroup: "Empty".} = object
            top {.cfg.}: bool

          var schema: seq[ConfigSchemaSection]
          generateSectionGroupSchema(schema, EmptyGroup)
      )
    )

suite "config_macros: escapeMdCell":
  test "passes through plain text unchanged":
    check escapeMdCell("hello world") == "hello world"
    check escapeMdCell("") == ""

  test "escapes pipe so the cell cannot terminate":
    check escapeMdCell("a|b") == "a\\|b"
    check escapeMdCell("|") == "\\|"

  test "escapes backslash before pipe escaping (preserves round-trip)":
    check escapeMdCell("a\\b") == "a\\\\b"
    check escapeMdCell("\\|") == "\\\\\\|"

  test "collapses newlines to spaces so the row cannot break":
    check escapeMdCell("a\nb") == "a b"
    check escapeMdCell("a\r\nb") == "a  b"

suite "config_loader: empty option set":
  # A named option set whose length is not compile-time known slips past
  # `optionSetNonEmptyCheck`, so the load site guards against an empty one.
  test "a string key with an empty option set trips the guard":
    let t = tomlTable("mode = \"x\"\n")
    var
      s = ""
      vr = newValidationResult()
    expect AssertionDefect:
      loadEnumString(t, "mode", s, [], vr)

  test "an array key with an empty option set trips the guard":
    let t = tomlTable("modes = [\"x\"]\n")
    var
      s: seq[string] = @[]
      vr = newValidationResult()
    expect AssertionDefect:
      loadEnumStringArray(t, "modes", s, [], vr)

suite "config_loader: option set expectations":
  test "a non-array value for an option-set array reads as a noun phrase":
    let t = tomlTable("modes = \"pipe\"\n")
    var
      s: seq[string] = @[]
      vr = newValidationResult()
    loadEnumStringArray(t, "modes", s, ["pipe", "none"], vr)
    check vr.toErrorMessages.len == 1
    check "array of strings, each one of: pipe, none" in vr.toErrorMessages[0]

type
  DefaultedElem = object
    name {.cfg, cfgDocDescription: "Name".}: string
    enabled {.cfg, cfgDocDescription: "Enabled".}: bool = true
    depth {.cfg, cfgDocDescription: "Depth".}: int = 3
    label {.cfg, cfgDocDescription: "Label".}: string = "auto"

  DefaultedGroup {.cfgGroup: "Def".} = object
    entries {.cfgArrayOfTables: "entries".}: seq[DefaultedElem]

proc loadDefaultedGroup(
    t: TomlTableRef, c: var DefaultedGroup, vr: var ValidationResult
) =
  generateSectionGroupLoader(t, c, vr, DefaultedGroup)

suite "config_macros: array element defaults":
  # An entry is built per table, so the element type's field defaults are the
  # only place its defaults can live.
  test "a key an entry omits keeps the element type's default":
    let t = tomlTable("[[entries]]\nname = \"a\"\n")
    var c: DefaultedGroup
    var vr = newValidationResult()
    loadDefaultedGroup(t, c, vr)
    check not vr.hasErrors
    check c.entries.len == 1
    check c.entries[0] ==
      DefaultedElem(name: "a", enabled: true, depth: 3, label: "auto")

  test "a key an entry writes overrides the default":
    let t = tomlTable("[[entries]]\nname = \"a\"\nenabled = false\ndepth = 0\n")
    var c: DefaultedGroup
    var vr = newValidationResult()
    loadDefaultedGroup(t, c, vr)
    check not vr.hasErrors
    check c.entries[0] ==
      DefaultedElem(name: "a", enabled: false, depth: 0, label: "auto")

  test "one entry's defaults do not leak into the next":
    let t = tomlTable(
      "[[entries]]\nname = \"a\"\nlabel = \"x\"\n\n[[entries]]\nname = \"b\"\n"
    )
    var c: DefaultedGroup
    var vr = newValidationResult()
    loadDefaultedGroup(t, c, vr)
    check c.entries.mapIt(it.label) == @["x", "auto"]

  test "the docs advertise the defaults the loader actually applies":
    # The documented column and a freshly loaded entry read the same
    # declaration.
    let table = generateArrayTableMarkdown(typedesc[DefaultedElem])
    check "| enabled | bool | true |" in table
    check "| depth | integer | 3 |" in table
    check "| label | string | \"auto\" |" in table

type MixedGroup {.cfgGroup: "Mix".} = object
  sub {.cfgSubSection: "Sub".}: FeatureSub
  entries {.cfgArrayOfTables: "entries".}: seq[DefaultedElem]

proc loadMixedGroup(t: TomlTableRef, c: var MixedGroup, vr: var ValidationResult) =
  generateSectionGroupLoader(t, c, vr, MixedGroup)

proc saveMixedGroup(lines: var seq[string], cfg: MixedGroup) =
  generateSectionGroupSerializer(lines, cfg, MixedGroup)

suite "config_macros: an emptied array of tables":
  test "an empty array is written as a key, so the emptied state round-trips":
    # With no `[[Mix.entries]]` blocks, a file silent about the field would
    # load the default back and revive every deleted entry.
    var lines: seq[string]
    saveMixedGroup(lines, MixedGroup(sub: FeatureSub(on: true), entries: @[]))
    check "entries = []" in lines
    let parsed = tomlTable(lines.join("\n"))["Mix"].getTable()
    var loaded = MixedGroup(entries: @[DefaultedElem(name: "default")])
    var vr = newValidationResult()
    loadMixedGroup(parsed, loaded, vr)
    check not vr.hasErrors
    check loaded.entries.len == 0
    check loaded.sub.on

  test "the marker is written into the parent table, not a later sub-table":
    # The array field is declared after the sub-section, so a marker emitted
    # in declaration order would land under `[Mix.Sub]`.
    var lines: seq[string]
    saveMixedGroup(lines, MixedGroup(entries: @[]))
    check lines.find("entries = []") < lines.find("[Mix.Sub]")
    let parsed = tomlTable(lines.join("\n"))
    check parsed["Mix"].getTable().hasKey("entries")
    check not parsed["Mix"]["Sub"].getTable().hasKey("entries")

  test "a non-empty array still writes one header per element and no marker":
    var lines: seq[string]
    saveMixedGroup(lines, MixedGroup(entries: @[DefaultedElem(name: "a")]))
    check "entries = []" notin lines
    check lines.count("[[Mix.entries]]") == 1
