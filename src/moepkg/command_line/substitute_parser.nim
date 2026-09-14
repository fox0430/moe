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

## Substitute (:s) command parser and extraction helpers.

import std/strutils

import pkg/results

import range_parser

proc processEscapeSequences*(s: string): string =
  ## Process escape sequences in a string
  ## Converts \n to newline, \t to tab, \\ to backslash, \/ to slash
  var i = 0
  while i < s.len:
    if s[i] == '\\' and i + 1 < s.len:
      case s[i + 1]
      of 'n':
        result.add('\n')
        i += 2
      of 't':
        result.add('\t')
        i += 2
      of '\\':
        result.add('\\')
        i += 2
      of '/':
        result.add('/')
        i += 2
      else:
        result.add(s[i])
        i += 1
    else:
      result.add(s[i])
      i += 1

proc normalizeSubstituteLongForm*(commandText: string): string =
  ## Rewrite the `:substitute/...` long form, or any unambiguous prefix of it
  ## (`:su/`, `:subs/`, ...), to `:s/...`, with or without the leading `:`,
  ## so the existing `s/` paths handle both.
  const Long = "substitute"
  let prefixStart = if commandText.len > 0 and commandText[0] == ':': 1 else: 0
  var nameStart = prefixStart
  while nameStart < commandText.len and commandText[nameStart] in ExRangeChars:
    nameStart.inc
  var nameEnd = nameStart
  while nameEnd < commandText.len and commandText[nameEnd] in {'a' .. 'z'}:
    nameEnd.inc
  let name = commandText[nameStart ..< nameEnd]
  if name.len < 2 or name.len > Long.len or not Long.startsWith(name):
    return commandText
  if nameEnd >= commandText.len or commandText[nameEnd] != '/':
    return commandText
  commandText[0 ..< nameStart] & "s" & commandText[nameEnd ..^ 1]

type SubstituteParseResult* = object ## Result of parsing a substitute command
  isValid*: bool # Whether this is a valid substitute command
  pattern*: string # Search pattern
  replacement*: string # Replacement text
  flags*: string # Flags (e.g., "g" for global within line)
  hasReplacement*: bool # Whether we've reached the replacement section

proc parseSubstituteCommand*(commandText: string): SubstituteParseResult =
  ## Parse a substitute command and extract pattern, replacement, and flags
  ## Supports formats:
  ##   :s/pattern/replacement/flags - current line only
  ##   :%s/pattern/replacement/flags - all lines
  ##   :1,10s/pattern/replacement/flags - lines 1 to 10
  ##   :.,10s/pattern/replacement/flags - current line to line 10
  ##   :1,.s/pattern/replacement/flags - line 1 to current line
  ## Handles escaped slashes properly (including \\/ which is backslash + end delimiter)
  result = SubstituteParseResult(isValid: false)

  if commandText.len < 2:
    return

  let normalized = normalizeSubstituteLongForm(commandText)

  # Remove leading ":"
  let cmd =
    if normalized[0] == ':':
      normalized[1 ..^ 1]
    else:
      normalized

  # The range, then `s` and the `/` opening its pattern.
  let prefix = parseExRangePrefix(cmd).valueOr:
    return
  if not cmd.continuesWith("s/", prefix.rest):
    return
  # The range is skipped, not kept: `parseCommandLine` has already stripped it
  # and it is the copy the executor reads.
  let startIdx = prefix.rest + 2

  result.isValid = true

  # Parse using state machine to properly handle escapes
  type ParseState = enum
    psPattern
    psReplacement
    psFlags

  var state = psPattern
  var escaped = false
  var i = startIdx

  while i < cmd.len:
    let c = cmd[i]

    if escaped:
      # Previous char was backslash - add this char literally (except for special sequences)
      case state
      of psPattern:
        result.pattern.add('\\')
        result.pattern.add(c)
      of psReplacement:
        result.replacement.add('\\')
        result.replacement.add(c)
      of psFlags:
        result.flags.add(c)
      escaped = false
      i += 1
      continue

    if c == '\\':
      escaped = true
      i += 1
      continue

    if c == '/':
      # Unescaped slash - delimiter
      case state
      of psPattern:
        state = psReplacement
        result.hasReplacement = true
      of psReplacement:
        state = psFlags
      of psFlags:
        discard # Ignore extra slashes in flags
      i += 1
      continue

    # Regular character
    case state
    of psPattern:
      result.pattern.add(c)
    of psReplacement:
      result.replacement.add(c)
    of psFlags:
      result.flags.add(c)
    i += 1

  # Handle trailing backslash
  if escaped:
    case state
    of psPattern:
      result.pattern.add('\\')
    of psReplacement:
      result.replacement.add('\\')
    of psFlags:
      result.flags.add('\\')

proc extractSubstitutePattern*(commandText: string): string =
  ## Extract the search pattern from a substitute command
  ## Supports formats like :%s/pattern/replacement/flags or :s/pattern/...
  ## Returns empty string if not a substitute command or pattern is incomplete
  let parsed = parseSubstituteCommand(commandText)
  if parsed.isValid:
    # Return raw pattern without escape processing (for display/matching)
    return parsed.pattern
  return ""

proc extractSubstituteReplacement*(
    commandText: string
): tuple[replacement: string, hasReplacement: bool] =
  ## Extract the replacement text from a substitute command
  ## Returns (replacement, true) if replacement section exists (even if empty)
  ## Returns ("", false) if we haven't reached the replacement section yet
  let parsed = parseSubstituteCommand(commandText)
  if parsed.isValid and parsed.hasReplacement:
    return (parsed.replacement, true)
  return ("", false)

proc extractSubstituteFlags*(commandText: string): string =
  ## Extract the flags from a substitute command
  let parsed = parseSubstituteCommand(commandText)
  if parsed.isValid:
    return parsed.flags
  return ""
