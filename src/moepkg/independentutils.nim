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

import std/[strutils, random]

type
  Position* = object
    y*: int
    x*: int

  WindowPosition* = Position

  Size* = object
    h*: int
    w*: int

  WindowSize* = Size

  Rect* = object
    x*: int
    y*: int
    h*: int
    w*: int

  WindowRect* = Rect

  Range* = object
    first*: int
    last*: int

  SelectedArea* = object
    startLine*: int
    startColumn*: int
    endLine*: int
    endColumn*: int

  BufferPosition* = object
    line*: int
    column*: int

  BufferRange* = object
    first*: BufferPosition
    last*: BufferPosition

  BufferLocation* = object
    path*: string
    range*: BufferRange

proc numberOfDigits*(x: int): int {.inline.} = x.intToStr.len

proc normalizeHex*(s: string): string =
  var count = 0
  for ch in s:
    if ch == '0':
      count.inc
    else:
      break

  result = s[count .. ^1]

proc isInt*(str: string): bool =
  try:
    discard str.parseInt
    return true
  except CatchableError:
    discard

proc genDelimiterStr*(buffer: string): string =
  while true:
    for _ in 0 .. 10: add(result, char(rand(int('A') .. int('Z'))))
    if buffer != result: break

proc isEmpty*[T](s: seq[T]): bool {.inline.} = s.len == 0

proc isEmpty*(s: string): bool {.inline.} = s.len == 0

proc dec*(n: var Natural) {.inline.} = n -= 1

proc inc*(n: var Natural) {.inline.} = n += 1
