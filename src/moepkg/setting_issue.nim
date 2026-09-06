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

## Settings moe was given and did not apply. Shared by every producer
## (`moerc.toml`, `.editorconfig`, LSP server settings), so this module is kept
## free of dependencies.

import std/sequtils

type
  SettingIssueKind* = enum
    sikInvalidValue ## Known key with an invalid value
    sikUnknownKey ## Unknown key in a section
    sikDeprecated
      ## Known key still accepted for backward compatibility. The `expected`
      ## field carries the human-readable deprecation message (typically the
      ## recommended replacement).
    sikUnsupported
      ## Known key with a value that is valid but unimplemented. The `expected`
      ## field says what moe does instead.

  SettingIssue* = object
    ## One setting that was not applied. Holds the facts only; the wording
    ## belongs to whoever reports it.
    kind*: SettingIssueKind # Default = sikInvalidValue
    name*: string # The key the issue is about
    val*: string # The value as a string, empty when the issue is not about one
    expected*: string # Description of expected value

  ValidationResult* = object ## Result of validating a configuration table
    errors*: seq[SettingIssue]

proc sameSetting*(a, b: SettingIssue): bool =
  ## Whether two issues are about the same setting, to tell an already reported
  ## issue from a new one. `expected` is left out so that rephrasing a reason
  ## does not make an old issue look new.
  a.kind == b.kind and a.name == b.name and a.val == b.val

proc newValidationResult*(): ValidationResult =
  ValidationResult(errors: @[])

proc addError*(vr: var ValidationResult, name, val, expected: string) =
  vr.errors.add(
    SettingIssue(kind: sikInvalidValue, name: name, val: val, expected: expected)
  )

proc addUnknownKey*(vr: var ValidationResult, name: string) =
  vr.errors.add(SettingIssue(kind: sikUnknownKey, name: name))

proc addDeprecated*(vr: var ValidationResult, name, msg: string) =
  ## Record that a deprecated key was present in the loaded TOML. The value is
  ## still loaded; `msg` typically points at the replacement.
  vr.errors.add(SettingIssue(kind: sikDeprecated, name: name, expected: msg))

proc hasErrors*(vr: ValidationResult): bool =
  ## True if any *actual* validation error is present. Deprecation notices
  ## (`sikDeprecated`) are excluded because the loader still accepts the value;
  ## surface those separately via `hasDeprecations`.
  vr.errors.anyIt(it.kind != sikDeprecated)

proc hasDeprecations*(vr: ValidationResult): bool =
  ## True if any deprecation notice was recorded.
  vr.errors.anyIt(it.kind == sikDeprecated)

const MaxValueInMessage = 60
  ## A value in a message only has to be recognizable. Some are whole tables
  ## (an LSP settings block), and the status line has little room.

proc shortVal(val: string): string =
  if val.len <= MaxValueInMessage:
    val
  else:
    val[0 ..< MaxValueInMessage] & "..."

proc toMessage*(item: SettingIssue): string =
  ## Convert a SettingIssue to a human-readable message
  case item.kind
  of sikInvalidValue:
    "Invalid value for '" & item.name & "': got '" & item.val.shortVal & "', expected " &
      item.expected
  of sikUnknownKey:
    "Unknown key: '" & item.name & "'"
  of sikUnsupported:
    "Unsupported value for '" & item.name & "': got '" & item.val.shortVal & "'" &
      (if item.expected.len > 0: ", " & item.expected else: "")
  of sikDeprecated:
    if item.expected.len > 0:
      "Deprecated key '" & item.name & "': " & item.expected
    else:
      "Deprecated key '" & item.name & "'"

proc toErrorMessages*(vr: ValidationResult): seq[string] =
  ## Convert *actual* validation errors to human-readable messages. Deprecation
  ## notices are excluded — use `toDeprecationMessages` for those.
  var r: seq[string] = @[]
  for e in vr.errors:
    if e.kind != sikDeprecated:
      r.add e.toMessage
  r

proc toDeprecationMessages*(vr: ValidationResult): seq[string] =
  ## Convert recorded deprecation notices to human-readable messages.
  var r: seq[string] = @[]
  for e in vr.errors:
    if e.kind == sikDeprecated:
      r.add e.toMessage
  r
