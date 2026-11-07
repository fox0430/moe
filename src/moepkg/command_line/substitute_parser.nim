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

type SubstituteFlags* = object
  global*: bool
  countOnly*: bool # The `n` flag: report the matches, replace nothing
  confirm*: bool # The `c` flag
  ignoreCase*: bool
  trailing*: string # What follows the flags, which Vim refuses (E488)

proc parseSubstituteFlags*(text: string, optionsIgnoreCase = false): SubstituteFlags =
  ## `text` as do_sub reads it: an `&` may start it, flags follow up to the
  ## first character that is no flag, and a `"` ends the command. `g` and `c`
  ## toggle, and the last of `i` and `I` decides the case for this :s alone,
  ## `optionsIgnoreCase` being what it is without them.
  const IgnoredFlags = {'e', 'p', '#', 'l', 'r'}
  result.ignoreCase = optionsIgnoreCase
  var i = if text.len > 0 and text[0] == '&': 1 else: 0
  while i < text.len:
    case text[i]
    of 'g':
      result.global = not result.global
    of 'c':
      result.confirm = not result.confirm
    of 'n':
      result.countOnly = true
    of 'i':
      result.ignoreCase = true
    of 'I':
      result.ignoreCase = false
    of IgnoredFlags:
      discard
    else:
      break
    i.inc
  let rest = text[i ..^ 1].strip
  if not rest.startsWith('"'):
    result.trailing = rest

proc refusal*(flags: SubstituteFlags): string =
  ## Why a :s with `flags` does not run, empty when it does.
  if flags.trailing.len > 0:
    "E488: Trailing characters: " & flags.trailing
  elif flags.confirm and not flags.countOnly:
    "The `c` flag of :s is not supported"
  else:
    ""

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
  range*: ExLineRange # The lines in front of `s`, unresolved

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
  # The executor reads the range `parseCommandLine` stripped, not this copy;
  # the live preview reads this one.
  let startIdx = prefix.rest + 2

  result.isValid = true
  result.range = prefix.range

  # Parse using state machine to properly handle escapes
  type ParseState = enum
    psPattern
    psReplacement

  var state = psPattern
  var escaped = false
  var i = startIdx

  while i < cmd.len:
    let c = cmd[i]

    if escaped:
      # Previous char was backslash - add this char literally (except for special sequences)
      case state
      of psPattern:
        # The pattern is a plain string, in which `\/` and `\\` stand for the
        # character itself.
        if c notin {'/', '\\'}:
          result.pattern.add('\\')
        result.pattern.add(c)
      of psReplacement:
        result.replacement.add('\\')
        result.replacement.add(c)
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
        result.flags = cmd[i + 1 ..^ 1]
        break
      i += 1
      continue

    # Regular character
    case state
    of psPattern:
      result.pattern.add(c)
    of psReplacement:
      result.replacement.add(c)
    i += 1

  # Handle trailing backslash
  if escaped:
    case state
    of psPattern:
      result.pattern.add('\\')
    of psReplacement:
      result.replacement.add('\\')

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
