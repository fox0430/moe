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

## Shared primitives for the TOML config loader: validation result types,
## enum parsers, scalar load helpers, and the constants the
## `generateConfigLoader` macro expands against.
##
## All identifiers the macro generates calls to (`loadBool`/`loadInt`/...,
## `checkUnknownKeys`, `fullKey`, `addError`, the `parseXxx`/`ValidXxxs`
## pairs) MUST be exported from this module so per-section loader modules
## can resolve them at macro-expansion time.

import std/[os, options, tables, strutils, sequtils]

import pkg/parsetoml

import ../config

# Configuration validation types and utilities

type
  InvalidItemKind* = enum
    iikInvalidValue ## Known key with an invalid value
    iikUnknownKey ## Unknown key in a section
    iikDeprecated
      ## Known key still accepted for backward compatibility. The `expected`
      ## field carries the human-readable deprecation message (typically the
      ## recommended replacement).

  InvalidItem* = object ## Represents a validation error for a configuration item
    kind*: InvalidItemKind # Default = iikInvalidValue
    name*: string # The key name that has an invalid value
    val*: string # The invalid value as a string
    expected*: string # Description of expected value

  ValidationResult* = object ## Result of validating a configuration table
    errors*: seq[InvalidItem]

const
  themeColorExpected* = "string color (\"#RRGGBB\" hex or \"termDefault\")"
  themeInlineTableExpected* = "inline table { fg = \"...\", bg = \"...\" }"

proc newValidationResult*(): ValidationResult =
  ValidationResult(errors: @[])

proc addError*(vr: var ValidationResult, name, val, expected: string) =
  vr.errors.add(
    InvalidItem(kind: iikInvalidValue, name: name, val: val, expected: expected)
  )

proc addUnknownKey*(vr: var ValidationResult, name: string) =
  vr.errors.add(InvalidItem(kind: iikUnknownKey, name: name))

proc addDeprecated*(vr: var ValidationResult, name, msg: string) =
  ## Record that a deprecated key was present in the loaded TOML. The key was
  ## still accepted (its value is loaded); `msg` is the human-readable notice
  ## typically pointing at the replacement.
  vr.errors.add(InvalidItem(kind: iikDeprecated, name: name, expected: msg))

proc hasErrors*(vr: ValidationResult): bool =
  ## True if any *actual* validation error is present. Deprecation notices
  ## (`iikDeprecated`) are excluded because the loader still accepts the value;
  ## surface those separately via `hasDeprecations`.
  vr.errors.anyIt(it.kind != iikDeprecated)

proc hasDeprecations*(vr: ValidationResult): bool =
  ## True if any deprecation notice was recorded.
  vr.errors.anyIt(it.kind == iikDeprecated)

proc toErrorMessage*(item: InvalidItem): string =
  ## Convert an InvalidItem to a human-readable error message
  case item.kind
  of iikInvalidValue:
    "Invalid value for '" & item.name & "': got '" & item.val & "', expected " &
      item.expected
  of iikUnknownKey:
    "Unknown key: '" & item.name & "'"
  of iikDeprecated:
    if item.expected.len > 0:
      "Deprecated key '" & item.name & "': " & item.expected
    else:
      "Deprecated key '" & item.name & "'"

proc toErrorMessages*(vr: ValidationResult): seq[string] =
  ## Convert *actual* validation errors to human-readable messages. Deprecation
  ## notices are excluded — use `toDeprecationMessages` for those.
  var r: seq[string] = @[]
  for e in vr.errors:
    if e.kind != iikDeprecated:
      r.add e.toErrorMessage
  r

proc toDeprecationMessages*(vr: ValidationResult): seq[string] =
  ## Convert recorded deprecation notices to human-readable messages.
  var r: seq[string] = @[]
  for e in vr.errors:
    if e.kind == iikDeprecated:
      r.add e.toErrorMessage
  r

proc parseColorMode*(s: string): ColorMode =
  case s
  of "8": cm8color
  of "16": cm16color
  of "256": cm256color
  of "24bit": cm24bit
  of "none": cmNone
  else: cm24bit

proc parseCursorType*(s: string): CursorType =
  case s
  of "terminalDefault": ctTerminalDefault
  of "blinkBlock": ctBlinkBlock
  of "blinkIbeam": ctBlinkIbeam
  of "nonBlinkBlock": ctNonBlinkBlock
  of "nonBlinkIbeam": ctNonBlinkIbeam
  else: ctTerminalDefault

proc parseThemeKind*(s: string): ThemeKind =
  case s
  of "default": tkDefault
  of "config": tkConfig
  of "vscode": tkVscode
  else: tkConfig

proc parseClipboardTool*(s: string): ClipboardTool =
  case s
  of "xsel": cbtXsel
  of "xclip": cbtXclip
  of "wl-clipboard": cbtWlClipboard
  of "win32yank": cbtWin32yank
  of "pbcopy": cbtPbcopy
  else: cbtXsel

proc parseSplitType*(s: string): SplitType =
  case s
  of "horizontal": stHorizontal
  of "vertical": stVertical
  else: stVertical

proc parseLspTraceLevel*(s: string): LspTraceLevel =
  case s
  of "off": ltOff
  of "messages": ltMessages
  of "verbose": ltVerbose
  else: ltOff

proc parseBufferBackendKind*(s: string): BufferBackendKind =
  case s
  of "auto": bbcAuto
  of "gapBuffer": bbcGapBuffer
  of "sqrtDecomp": bbcSqrtDecomp
  of "rope": bbcRope
  of "pieceTable": bbcPieceTable
  else: bbcAuto

proc parseBracketSplitMode*(s: string): BracketSplitMode =
  case s
  of "disable": bsmDisable
  of "noIndent": bsmNoIndent
  of "indent": bsmIndent
  else: bsmDisable

# Integrated load+validate helper functions
# These functions validate and load in one step.
# Invalid values are skipped (keeping defaults) and errors are collected.

proc fullKey*(section, key: string): string {.inline.} =
  if section.len > 0:
    section & "." & key
  else:
    key

proc checkUnknownKeys*(
    table: TomlTableRef,
    validKeys: openArray[string],
    section: string,
    vr: var ValidationResult,
) =
  ## Report unknown keys in a TOML table section.
  for key, _ in table:
    if key notin validKeys:
      vr.addUnknownKey(fullKey(section, key))

proc expectTable*(
    table: TomlTableRef, key: string, vr: var ValidationResult, section: string = ""
): bool =
  ## True when `key` is present and holds a TOML table. A non-table value is
  ## reported as a type error rather than dropped: `getTable` yields an empty
  ## default for a non-table, so such a key would load nothing and, being a
  ## known key, escape the unknown-key check as well.
  if not table.hasKey(key):
    false
  elif table[key].kind == TomlValueKind.Table:
    true
  else:
    vr.addError(fullKey(section, key), $table[key], "table")
    false

proc expectTable*(
    doc: TomlValueRef, key: string, vr: var ValidationResult, section: string = ""
): bool =
  ## Overload for the parsed document, which the whole-config section dispatch
  ## is handed instead of a table.
  expectTable(doc.getTable(), key, vr, section)

proc loadBool*(
    table: TomlTableRef,
    key: string,
    target: var bool,
    vr: var ValidationResult,
    section: string = "",
) =
  ## Load a boolean value if valid. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind == TomlValueKind.Bool:
      target = val.getBool()
    else:
      vr.addError(fullKey(section, key), $val, "boolean (true/false)")

proc loadInt*(
    table: TomlTableRef,
    key: string,
    target: var int,
    vr: var ValidationResult,
    section: string = "",
    minVal: int = int.low,
    maxVal: int = int.high,
) =
  ## Load an integer value if valid and within range. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind != TomlValueKind.Int:
      vr.addError(fullKey(section, key), $val, "integer")
    else:
      let intVal = val.getInt
      if intVal < minVal or intVal > maxVal:
        let rangeDesc =
          if minVal == int.low:
            "integer <= " & $maxVal
          elif maxVal == int.high:
            "integer >= " & $minVal
          else:
            "integer between " & $minVal & " and " & $maxVal
        vr.addError(fullKey(section, key), $intVal, rangeDesc)
      else:
        target = intVal

proc loadFloat*(
    table: TomlTableRef,
    key: string,
    target: var float,
    vr: var ValidationResult,
    section: string = "",
    minVal: float = float.low,
    maxVal: float = float.high,
) =
  ## Load a float value if valid and within range. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind != TomlValueKind.Float and val.kind != TomlValueKind.Int:
      vr.addError(fullKey(section, key), $val, "number")
    else:
      let floatVal =
        if val.kind == TomlValueKind.Float:
          val.getFloat
        else:
          float(val.getInt)
      if floatVal < minVal or floatVal > maxVal:
        let rangeDesc =
          if minVal == float.low:
            "number <= " & $maxVal
          elif maxVal == float.high:
            "number >= " & $minVal
          else:
            "number between " & $minVal & " and " & $maxVal
        vr.addError(fullKey(section, key), $floatVal, rangeDesc)
      else:
        target = floatVal

proc loadString*(
    table: TomlTableRef,
    key: string,
    target: var string,
    vr: var ValidationResult,
    section: string = "",
) =
  ## Load a string value if valid. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind == TomlValueKind.String:
      target = val.getStr()
    else:
      vr.addError(fullKey(section, key), $val, "string")

proc loadOptionString*(
    table: TomlTableRef,
    key: string,
    target: var Option[string],
    vr: var ValidationResult,
    section: string = "",
) =
  ## Load an optional string value if valid. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind == TomlValueKind.String:
      target = some(val.getStr())
    else:
      vr.addError(fullKey(section, key), $val, "string")

proc loadStringArray*(
    table: TomlTableRef,
    key: string,
    target: var seq[string],
    vr: var ValidationResult,
    section: string = "",
) =
  ## Load a string array if valid. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind != TomlValueKind.Array:
      vr.addError(fullKey(section, key), $val, "array of strings")
    else:
      var valid = true
      var r: seq[string] = @[]
      for i, item in val.getElems:
        if item.kind != TomlValueKind.String:
          vr.addError(fullKey(section, key) & "[" & $i & "]", $item, "string")
          valid = false
        else:
          r.add(item.getStr())
      if valid:
        target = r

proc loadFilePath*(
    table: TomlTableRef,
    key: string,
    target: var string,
    vr: var ValidationResult,
    section: string = "",
) =
  ## Load a file path if valid and file exists. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind != TomlValueKind.String:
      vr.addError(fullKey(section, key), $val, "string (file path)")
    else:
      let path = val.getStr().expandTilde
      if not fileExists(path):
        vr.addError(fullKey(section, key), val.getStr(), "existing file path")
      else:
        target = val.getStr()

proc loadOptionDirPath*(
    table: TomlTableRef,
    key: string,
    target: var Option[string],
    vr: var ValidationResult,
    section: string = "",
) =
  ## Load an optional directory path if valid and directory exists. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind != TomlValueKind.String:
      vr.addError(fullKey(section, key), $val, "string (directory path)")
    else:
      let path = val.getStr().expandTilde
      if not dirExists(path):
        vr.addError(fullKey(section, key), val.getStr(), "existing directory path")
      else:
        target = some(val.getStr())

proc loadEnum*[T](
    table: TomlTableRef,
    key: string,
    target: var T,
    vr: var ValidationResult,
    section: string = "",
    parseFunc: proc(s: string): T,
    validValues: openArray[string],
) =
  ## Load an enum value if valid. Invalid values are skipped.
  if table.hasKey(key):
    let val = table[key]
    if val.kind != TomlValueKind.String:
      vr.addError(fullKey(section, key), $val, "one of: " & validValues.join(", "))
    else:
      let strVal = val.getStr
      if strVal in validValues:
        target = parseFunc(strVal)
      else:
        vr.addError(fullKey(section, key), strVal, "one of: " & validValues.join(", "))

# Valid enum values for validation
const
  ValidColorModes* = ["8", "16", "256", "24bit", "none"]
  ValidCursorTypes* =
    ["terminalDefault", "blinkBlock", "blinkIbeam", "nonBlinkBlock", "nonBlinkIbeam"]
  ValidThemeKinds* = ["default", "config", "vscode"]
  ValidClipboardTools* = ["xsel", "xclip", "wl-clipboard", "win32yank", "pbcopy"]
  ValidSplitTypes* = ["horizontal", "vertical"]
  ValidLspTraceLevels* = ["off", "messages", "verbose"]
  ValidBufferBackendKinds* = ["auto", "gapBuffer", "sqrtDecomp", "rope", "pieceTable"]
  ValidBracketSplitModes* = ["disable", "noIndent", "indent"]
