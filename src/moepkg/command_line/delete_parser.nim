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

import range_parser

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

  if commandText.len == 0:
    return

  # Remove leading ":"
  let cmd =
    if commandText[0] == ':':
      commandText[1 ..^ 1]
    else:
      commandText

  let prefix = parseExRangePrefix(cmd)
  if not prefix.isValid:
    return
  # `d` takes no argument but the range.
  if cmd[prefix.rest ..^ 1] != "d":
    return

  result = DeleteParseResult(
    isValid: true,
    isGlobal: prefix.range.isGlobal,
    hasRange: prefix.range.hasRange,
    startLine: prefix.range.startLine,
    endLine: prefix.range.endLine,
  )
