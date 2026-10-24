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

## Number increment/decrement (Ctrl-A / Ctrl-X) on a line of text.

import std/[options, strutils]

type NumberChange* = object
  line*: string ## The line with the number replaced
  numberStart*: int ## Byte index of the replaced number in `line`
  numberEnd*: int ## Byte index just past it

proc numberStartAt*(line: string, byteIdx: int): int =
  ## Where the number under `byteIdx` starts, its `-` included, so that
  ## Normal-mode Ctrl-A changes the whole number. `byteIdx` when not on a digit.
  result = byteIdx
  if result < 0 or result >= line.len or line[result] notin Digits:
    return
  while result > 0 and line[result - 1] in Digits:
    dec result
  if result > 0 and line[result - 1] == '-':
    dec result

proc parseMagnitude(digits: string): tuple[magnitude: uint64, overflow: bool] =
  ## Clamped to high(uint64), as Vim clamps a number too large to hold.
  for c in digits:
    let d = uint64(ord(c) - ord('0'))
    if result.magnitude > (high(uint64) - d) div 10:
      return (high(uint64), true)
    result.magnitude = result.magnitude * 10 + d

proc addSigned(negative: bool, magnitude: uint64, delta: int): (bool, uint64) =
  ## As Vim's do_addsub, the magnitude wraps around as an unsigned number does,
  ## and the sign flips when it wraps.
  let step =
    if delta < 0:
      uint64(-(delta + 1)) + 1
    else:
      uint64(delta)
  var
    neg = negative
    mag: uint64
  if neg == (delta < 0):
    mag = magnitude + step
    if mag < magnitude:
      mag = not mag
      neg = not neg
  else:
    mag = magnitude - step
    if mag > magnitude:
      mag = (not mag) + 1
      neg = not neg
  (neg and mag != 0, mag)

proc formatNumber(negative: bool, magnitude: uint64, oldDigits: string): string =
  ## Keeps the digit count of a zero-padded number, as Vim does.
  var digits = $magnitude
  if oldDigits.len > digits.len and oldDigits[0] == '0':
    digits = '0'.repeat(oldDigits.len - digits.len) & digits
  (if negative: "-" else: "") & digits

proc addToNumber*(line: string, startByte, endByte, delta: int): Option[NumberChange] =
  ## Adds `delta` to the first number found in `line[startByte ..< endByte]`.
  ## Only digits inside the range belong to the number, and a `-` makes it
  ## negative only when it is inside the range too, as with Vim's v_CTRL-A.
  let
    first = max(startByte, 0)
    stop = min(endByte, line.len)
  var i = first
  while i < stop and line[i] notin Digits:
    inc i
  if i >= stop:
    return none(NumberChange)

  let negative = i > first and line[i - 1] == '-'
  var digitsEnd = i
  while digitsEnd < stop and line[digitsEnd] in Digits:
    inc digitsEnd

  let
    oldDigits = line[i ..< digitsEnd]
    parsed = parseMagnitude(oldDigits)
    # Vim adds nothing to a number too large to hold, only clamps it.
    (neg, mag) =
      if parsed.overflow:
        (negative, parsed.magnitude)
      else:
        addSigned(negative, parsed.magnitude, delta)
    numberStart =
      if negative:
        i - 1
      else:
        i
    number = formatNumber(neg, mag, oldDigits)
  some(
    NumberChange(
      line: line[0 ..< numberStart] & number & line[digitsEnd ..^ 1],
      numberStart: numberStart,
      numberEnd: numberStart + number.len,
    )
  )
