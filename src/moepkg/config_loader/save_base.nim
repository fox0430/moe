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

## Shared primitives for TOML config serialization: scalar value formatters
## and theme color rendering used by every per-section `appendXxxToml`.

import std/[options, strformat]

import ../color

proc toTomlBool*(val: bool): string =
  if val: "true" else: "false"

proc escapeTomlBasicString*(val: string): string =
  ## Escape a string for use inside a TOML basic string (double-quoted),
  ## per the TOML spec. Without this, embedding a `"`, `\`, or newline in a
  ## value would produce invalid TOML that can no longer be parsed back.
  for c in val:
    case c
    of '"':
      result.add "\\\""
    of '\\':
      result.add "\\\\"
    of '\b':
      result.add "\\b"
    of '\t':
      result.add "\\t"
    of '\n':
      result.add "\\n"
    of '\f':
      result.add "\\f"
    of '\r':
      result.add "\\r"
    else:
      # Other control characters (U+0000..U+001F except those above, and
      # U+007F) are not allowed literally and must use \uXXXX escapes.
      if c < ' ' or c == '\x7f':
        result.add &"\\u{ord(c):04X}"
      else:
        result.add c

proc toTomlString*(val: string): string =
  "\"" & escapeTomlBasicString(val) & "\""

proc isTomlBareKey*(key: string): bool =
  ## A TOML bare key may only contain A-Za-z0-9_- and must be non-empty.
  if key.len == 0:
    return false
  for c in key:
    if c notin {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '-'}:
      return false
  true

proc toTomlKey*(key: string): string =
  ## Emit a table key, quoting it unless it is a valid TOML bare key. Without
  ## this, keys containing spaces, dots, or other special characters would
  ## produce invalid TOML or be silently reinterpreted as nested tables.
  if isTomlBareKey(key):
    key
  else:
    toTomlString(key)

proc toTomlStringArray*(val: seq[string]): string =
  result = "["
  for i, s in val:
    if i > 0:
      result.add ", "
    result.add toTomlString(s)
  result.add "]"

proc themeColorToTomlValue*(color: ThemeColor): string =
  ## Convert ThemeColor to TOML value string
  if color.rgb.isTermDefaultColor:
    return "\"termDefault\""
  let hexOpt = color.rgb.toHex()
  if hexOpt.isSome:
    return "\"" & hexOpt.get & "\""
  return "\"termDefault\""
