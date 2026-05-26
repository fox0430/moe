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

import std/options

import ../color

proc toTomlBool*(val: bool): string =
  if val: "true" else: "false"

proc toTomlString*(val: string): string =
  "\"" & val & "\""

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
