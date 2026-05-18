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

type SubstituteParseResult* = object ## Result of parsing a substitute command
  isValid*: bool # Whether this is a valid substitute command
  isGlobal*: bool # Whether the % prefix is present (all lines)
  hasRange*: bool # Whether a line range is specified (e.g., 1,10)
  startLine*: int # Start line (1-based, 0 means current line)
  endLine*: int # End line (1-based, 0 means current line)
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

  # Remove leading ":"
  let cmd =
    if commandText[0] == ':':
      commandText[1 ..^ 1]
    else:
      commandText

  # Check for substitute command patterns
  var startIdx = 0

  # Parse range prefix if present
  # Formats: %, N,M, .,M, N,., .,.
  if cmd.startsWith("%s/"):
    startIdx = 3
    result.isGlobal = true
  elif cmd.startsWith("s/"):
    startIdx = 2
    result.isGlobal = false
  else:
    # Try to parse range: number/dot, comma, number/dot, then s/
    var rangeEnd = 0
    var foundComma = false
    var startStr = ""
    var endStr = ""

    # Parse first part of range (before comma)
    while rangeEnd < cmd.len:
      let c = cmd[rangeEnd]
      if c == ',':
        foundComma = true
        rangeEnd.inc
        break
      elif c == 's' and rangeEnd + 1 < cmd.len and cmd[rangeEnd + 1] == '/':
        # Single line range (e.g., "5s/...")
        break
      elif c in {'0' .. '9', '.'}:
        startStr.add(c)
        rangeEnd.inc
      else:
        return # Invalid character in range

    if not foundComma and startStr.len > 0 and rangeEnd < cmd.len and
        cmd[rangeEnd] == 's' and rangeEnd + 1 < cmd.len and cmd[rangeEnd + 1] == '/':
      # Single line: "5s/..."
      result.hasRange = true
      if startStr == ".":
        result.startLine = 0 # 0 means current line
        result.endLine = 0
      else:
        try:
          let lineNum = parseInt(startStr)
          result.startLine = lineNum
          result.endLine = lineNum
        except ValueError:
          return
      startIdx = rangeEnd + 2
    elif foundComma:
      # Parse second part of range (after comma)
      while rangeEnd < cmd.len:
        let c = cmd[rangeEnd]
        if c == 's' and rangeEnd + 1 < cmd.len and cmd[rangeEnd + 1] == '/':
          break
        elif c in {'0' .. '9', '.'}:
          endStr.add(c)
          rangeEnd.inc
        else:
          return # Invalid character in range

      if rangeEnd < cmd.len and cmd[rangeEnd] == 's' and rangeEnd + 1 < cmd.len and
          cmd[rangeEnd + 1] == '/':
        result.hasRange = true
        # Parse start line
        if startStr == "." or startStr.len == 0:
          result.startLine = 0 # 0 means current line
        else:
          try:
            result.startLine = parseInt(startStr)
          except ValueError:
            return
        # Parse end line
        if endStr == "." or endStr.len == 0:
          result.endLine = 0 # 0 means current line
        else:
          try:
            result.endLine = parseInt(endStr)
          except ValueError:
            return
        startIdx = rangeEnd + 2
      else:
        return # No s/ found after range
    else:
      return # Not a valid substitute command

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
