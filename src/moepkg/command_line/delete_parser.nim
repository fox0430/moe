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

## Delete (:d) command parser with optional line range.

import std/strutils

type DeleteParseResult* = object ## Result of parsing a delete command
  isValid*: bool # Whether this is a valid delete command
  isGlobal*: bool # Whether the % prefix is present (all lines)
  hasRange*: bool # Whether a line range is specified (e.g., 1,10)
  startLine*: int # Start line (1-based, 0 means current line)
  endLine*: int # End line (1-based, 0 means current line)

proc parseDeleteCommand*(commandText: string): DeleteParseResult =
  ## Parse a delete command and extract range information
  ## Supports formats:
  ##   :d - delete current line
  ##   :%d - delete all lines
  ##   :1,10d - delete lines 1 to 10
  ##   :.,10d - delete from current line to line 10
  ##   :1,.d - delete from line 1 to current line
  result = DeleteParseResult(isValid: false)

  if commandText.len < 1:
    return

  # Remove leading ":"
  let cmd =
    if commandText[0] == ':':
      commandText[1 ..^ 1]
    else:
      commandText

  if cmd.len == 0:
    return

  # Check for simple :d
  if cmd == "d":
    result.isValid = true
    return

  # Check for :%d
  if cmd == "%d":
    result.isValid = true
    result.isGlobal = true
    return

  # Try to parse range: number/dot, comma, number/dot, then d
  var i = 0
  var foundComma = false
  var startStr = ""
  var endStr = ""

  # Parse first part of range (before comma)
  while i < cmd.len:
    let c = cmd[i]
    if c == ',':
      foundComma = true
      i.inc
      break
    elif c == 'd' and i + 1 == cmd.len:
      # Single line range (e.g., "5d")
      break
    elif c in {'0' .. '9', '.'}:
      startStr.add(c)
      i.inc
    else:
      return # Invalid character in range

  if not foundComma and startStr.len > 0 and i < cmd.len and cmd[i] == 'd' and
      i + 1 == cmd.len:
    # Single line: "5d"
    result.isValid = true
    result.hasRange = true
    if startStr == ".":
      result.startLine = 0 # 0 means current line
      result.endLine = 0
    else:
      try:
        let lineNum = parseInt(startStr)
        if lineNum < 1:
          result.isValid = false
          return
        result.startLine = lineNum
        result.endLine = lineNum
      except ValueError:
        return
  elif foundComma:
    # Parse second part of range (after comma)
    while i < cmd.len:
      let c = cmd[i]
      if c == 'd' and i + 1 == cmd.len:
        break
      elif c in {'0' .. '9', '.'}:
        endStr.add(c)
        i.inc
      else:
        return # Invalid character in range

    if i < cmd.len and cmd[i] == 'd' and i + 1 == cmd.len:
      result.isValid = true
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
