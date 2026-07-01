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

import std/[unittest, macros, options, sequtils, strutils, tables]

import pkg/parsetoml

import ../src/moepkg/config_macros
import ../src/moepkg/config
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
      if e.kind == iikUnknownKey and "bogus" in e.name:
        sawUnknown = true
    check sawUnknown

  test "cfgEnumStrings accepts in-set values":
    let t = tomlTable("mode = \"y\"\n")
    var c: MiniSection
    var vr = newValidationResult()
    loadMini(t, c, vr)
    check c.mode == "y"
    check not vr.hasErrors

  test "cfgEnumStrings rejects out-of-set value and falls back to first option":
    let t = tomlTable("mode = \"bogus\"\n")
    var c: MiniSection
    var vr = newValidationResult()
    loadMini(t, c, vr)
    check vr.hasErrors
    check c.mode == "x" # first option = fallback default

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
      if e.kind == iikDeprecated and e.name == "Depr.gone":
        sawDeprecated = true
        check "use keep instead" in e.expected
    check sawDeprecated

  test "loader stays silent when the deprecated key is absent":
    let t = tomlTable("keep = true\n")
    var c: DeprSection
    var vr = newValidationResult()
    loadDepr(t, c, vr)
    check not vr.errors.anyIt(it.kind == iikDeprecated)

  test "deprecated key does not surface as an unknown key":
    let t = tomlTable("gone = true\n")
    var c: DeprSection
    var vr = newValidationResult()
    loadDepr(t, c, vr)
    check not vr.errors.anyIt(it.kind == iikUnknownKey and "gone" in it.name)

  test "serializer skips deprecated fields":
    var cfg = DeprSection(keep: true, gone: true)
    var lines: seq[string]
    serializeDepr(lines, cfg)
    check "keep = true" in lines
    check not lines.anyIt(it.startsWith("gone = "))

  test "toErrorMessage renders the deprecation notice":
    let item =
      InvalidItem(kind: iikDeprecated, name: "Depr.gone", expected: "use keep instead")
    let msg = item.toErrorMessage
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

suite "config_macros: escapeMarkdownCell":
  test "passes through plain text unchanged":
    check escapeMarkdownCell("hello world") == "hello world"
    check escapeMarkdownCell("") == ""

  test "escapes pipe so the cell cannot terminate":
    check escapeMarkdownCell("a|b") == "a\\|b"
    check escapeMarkdownCell("|") == "\\|"

  test "escapes backslash before pipe escaping (preserves round-trip)":
    check escapeMarkdownCell("a\\b") == "a\\\\b"
    check escapeMarkdownCell("\\|") == "\\\\\\|"

  test "collapses newlines to spaces so the row cannot break":
    check escapeMarkdownCell("a\nb") == "a b"
    check escapeMarkdownCell("a\r\nb") == "a  b"
