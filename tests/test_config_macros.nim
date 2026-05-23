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

import std/[unittest, macros, strutils, tables]

import pkg/parsetoml

import ../src/moepkg/config_macros
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
