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

import std/[os, encodings]
import gapbuffer, unicodeext

proc normalizePath*(path: seq[Rune]): seq[Rune] =
  if path[0] == ru'~':
    if path == ru"~" or path == ru"~/":
      result = getHomeDir().toRunes
    else:
      result = getHomeDir().toRunes & path[2..path.high]
  elif path == ru"./":
    return path
  elif path.len > 1 and path[0 .. 1] == ru"./":
    return path[2 .. path.high]
  else:
    return path

proc openFile*(filename: seq[Rune]):
  tuple[text: seq[Rune], encoding: CharacterEncoding] =

    let
      raw = readFile($filename)
      encoding = detectCharacterEncoding(raw)
      text =  if encoding == CharacterEncoding.unknown or
                 encoding == CharacterEncoding.utf8:
        # If the character encoding is unknown, convert to UTF-8.
        raw.toRunes
      else:
        convert(raw, "UTF-8", $encoding).toRunes
    return (text, encoding)

proc newFile*(): GapBuffer[seq[Rune]] {.inline.} =
  result = initGapBuffer[seq[Rune]]()
  result.add(ru"", false)

proc saveFile*(
  path, runes: seq[Rune],
  encoding: CharacterEncoding) =

    let
      encode =
        if encoding == CharacterEncoding.unknown: CharacterEncoding.utf8
        else: encoding
      buffer = convert($runes, $encode, "UTF-8")
    writeFile($path, buffer)
