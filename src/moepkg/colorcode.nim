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

## Inline color code detection and highlighting
##
## Detects #RRGGBB and #RGB color codes in text and provides styles
## for rendering them with their actual color as background.

import std/[options, hashes, unicode]

import pkg/[celina, results]

import color

type
  ColorCodeMatch* = object
    startCol*: int ## Column of '#'
    endCol*: int ## Column of last hex digit (inclusive)
    style*: Style ## Pre-computed style (bg=detected color, fg=contrast)

  ColorCodeLineCache* = object
    matches*: seq[ColorCodeMatch]
    lineHash*: Hash ## Hash of line content for invalidation

  ColorCodeCache* = object
    lines*: seq[ColorCodeLineCache]

proc isHexChar(c: char): bool {.inline.} =
  c in {'0' .. '9', 'a' .. 'f', 'A' .. 'F'}

proc contrastForeground*(bg: Rgb): Rgb =
  ## Choose black or white foreground for best contrast using W3C luminance formula.
  let luminance = (bg.red.int * 299 + bg.green.int * 587 + bg.blue.int * 114) div 1000
  if luminance > 128:
    Rgb(red: 0, green: 0, blue: 0)
  else:
    Rgb(red: 255, green: 255, blue: 255)

proc colorCodeStyle*(bg: Rgb): Style =
  ## Style for rendering a hex color code: the detected color as background
  ## with a contrasting foreground, matching the normal-mode highlight.
  let fg = contrastForeground(bg)
  Style(fg: fg.toColorValue, bg: bg.toColorValue, modifiers: {})

proc scanLineForColorCodes*(line: string): seq[ColorCodeMatch] =
  ## Scan a line for #RRGGBB and #RGB color codes.
  ## Returns matches with pre-computed styles.
  ## startCol/endCol are in Rune (character) units for use with renderChar.

  # Fast path: a color code requires a '#', so a line without one can hold no
  # match. Bail out before allocating the byteToRune mapping. '#' (0x23) only
  # ever appears as a standalone ASCII byte in UTF-8, so a raw byte scan is
  # safe. This is the common case on the render hot path (most lines have no
  # '#'), so it skips a line-length allocation per visible line, per frame.
  var hasHash = false
  for c in line:
    if c == '#':
      hasHash = true
      break
  if not hasHash:
    return @[]

  # Build a mapping from byte offset to rune index, and collect byte offsets
  # of '#' characters for efficient scanning.
  var
    runeIndex = 0
    byteToRune: seq[int] # byteToRune[byteOffset] = runeIndex
    hashPositions: seq[int] # byte offsets of '#'

  byteToRune.setLen(line.len)
  var byteOff = 0
  for rune in line.runes:
    let runeLen = rune.size
    for j in 0 ..< runeLen:
      if byteOff + j < line.len:
        byteToRune[byteOff + j] = runeIndex
    if rune == '#'.Rune:
      hashPositions.add(byteOff)
    byteOff += runeLen
    runeIndex += 1

  for hashBytePos in hashPositions:
    let i = hashBytePos

    # Check word boundary before '#' (byte-level is fine since hex chars are ASCII)
    if i > 0 and line[i - 1].isHexChar:
      continue

    # Try 6-digit hex first (#RRGGBB)
    if i + 6 < line.len:
      var allHex = true
      for j in 1 .. 6:
        if not line[i + j].isHexChar:
          allHex = false
          break

      if allHex:
        # Check word boundary after last hex digit
        let afterEnd = i + 7
        if afterEnd >= line.len or not line[afterEnd].isHexChar:
          let hexStr = line[i + 1 .. i + 6]
          let rgbResult = hexToRgb(hexStr)
          if rgbResult.isOk:
            result.add ColorCodeMatch(
              startCol: byteToRune[i],
              endCol: byteToRune[i + 6],
              style: colorCodeStyle(rgbResult.get),
            )
            continue

    # Try 3-digit hex (#RGB)
    if i + 3 < line.len:
      var allHex = true
      for j in 1 .. 3:
        if not line[i + j].isHexChar:
          allHex = false
          break

      if allHex:
        # Check word boundary after last hex digit
        let afterEnd = i + 4
        if afterEnd >= line.len or not line[afterEnd].isHexChar:
          # Expand 3-digit to 6-digit: F0A -> FF00AA
          let
            r = line[i + 1]
            g = line[i + 2]
            b = line[i + 3]
            expanded = $r & $r & $g & $g & $b & $b
          let rgbResult = hexToRgb(expanded)
          if rgbResult.isOk:
            result.add ColorCodeMatch(
              startCol: byteToRune[i],
              endCol: byteToRune[i + 3],
              style: colorCodeStyle(rgbResult.get),
            )
            continue

proc getColorCodeStyle*(cache: ColorCodeCache, line, col: int): Option[Style] =
  ## Check if position (line, col) is inside a color code match.
  ## Returns the style if it is.
  if line < 0 or line >= cache.lines.len:
    return none(Style)

  for m in cache.lines[line].matches:
    if col >= m.startCol and col <= m.endCol:
      return some(m.style)

  return none(Style)

proc updateLine*(cache: var ColorCodeCache, lineIdx: int, line: string) =
  ## Update cache for a single line. Only re-scans if content changed (hash match).
  if lineIdx < 0 or lineIdx >= cache.lines.len:
    return

  let h = hash(line)
  if cache.lines[lineIdx].lineHash == h:
    return

  cache.lines[lineIdx].lineHash = h
  cache.lines[lineIdx].matches = scanLineForColorCodes(line)

proc resize*(cache: var ColorCodeCache, lineCount: int) =
  ## Resize cache to match buffer line count.
  cache.lines.setLen(lineCount)

proc initColorCodeCache*(lineCount: int): ColorCodeCache =
  ## Create a new cache with the given number of lines.
  result.lines = newSeq[ColorCodeLineCache](lineCount)

proc updateAll*(
    cache: var ColorCodeCache, getLine: proc(i: int): string, lineCount: int
) =
  ## Rebuild entire cache from scratch.
  cache.resize(lineCount)
  for i in 0 ..< lineCount:
    let line = getLine(i)
    cache.lines[i].lineHash = hash(line)
    cache.lines[i].matches = scanLineForColorCodes(line)
