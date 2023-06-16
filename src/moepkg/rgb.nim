#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[strutils, strformat]
import pkg/results

type
  # 0 ~ 255
  # -1 is the terminal default color.
  Rgb* = object
    red*, green*, blue*: int16

  RgbPair* = object
    foreground*, background*: Rgb

const TerminalDefaultRgb* = Rgb(red: -1, green: -1, blue: -1)

proc isTermDefaultColor*(rgb: Rgb): bool {.inline.} =
  rgb == TerminalDefaultRgb

## Parses a hex color value from a string s.
## Examples: "#000000", "ff0000"
proc hexToRgb*(s: string): Result[Rgb, string] =
  if not (s.len == 6 or (s.len == 7 and s.startsWith('#'))):
    return Result[Rgb, string].err "Invalid hex color"

  let hexStr =
    if s.startsWith('#'): s[1 .. 6]
    else: s

  var rgb: Rgb
  try:
    rgb = Rgb(
      red: fromHex[int16](hexStr[0..1]),
      green: fromHex[int16](hexStr[2..3]),
      blue: fromHex[int16](hexStr[4..5]))
  except CatchableError as e:
    return Result[Rgb, string].err fmt"Failed to parse hex color: {$e.msg}"

  return Result[Rgb, string].ok rgb

## Converts from the Rgb to a hex color code with `#`.
## Example: Rgb(red: 0, green: 0, blue: 0) -> "#000000"
proc toHex*(rgb: Rgb): string {.inline.} =
  fmt"#{rgb.red.toHex(2)}{rgb.green.toHex(2)}{rgb.blue.toHex(2)}"

## Return true if valid hex color code.
## '#' is required if `isPrefix` is true.
## Range: 000000 ~ ffffff
proc isHexColor*(s: string, isPrefix: bool = true): bool =
  if (not isPrefix or s.startsWith('#')) and s.len == 7:
    var
      r, g, b: int
    try:
      r = fromHex[int](s[1..2])
      g = fromHex[int](s[3..4])
      b = fromHex[int](s[5..6])
    except ValueError:
      return false

    return (r >= 0 and r <= 255) and
           (g >= 0 and g <= 255) and
           (b >= 0 and b <= 255)

## Return the inverse color.
proc inverseColor*(color: Rgb): Rgb =
  if color.isTermDefaultColor:
    return color

  result.red = abs(color.red - 255)
  result.green = abs(color.green - 255)
  result.blue = abs(color.blue - 255)

# Calculates the difference between two rgb colors
proc calcRGBDifference*(c1: Rgb, c2: Rgb): int {.inline.} =
  abs(c1.red - c2.red) + abs(c1.green - c2.green) + abs(c1.blue - c2.blue)