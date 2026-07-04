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

## URI/URL detection and external program launching utilities.
## Used by the `gf` command to open URIs under the cursor.

import std/[options, osproc, sequtils, strutils, unicode, uri]

const
  UriSchemes* = ["https://", "http://", "file://", "mailto:", "ftp://", "ssh://"]

  # Characters that terminate a URI (all ASCII).
  UriBreakChars =
    Whitespace + {'<', '>', '"', '`', '[', ']', '{', '}', '|', '\\', '^', '\''}

  # Trailing characters that are usually punctuation, not part of the URI.
  TrailingPunctuation = {'.', ',', ';', ':', '!', '?'}

proc isUriBreakRune(r: Rune): bool =
  let c = r.int32
  if c > 127:
    return false
  return char(c) in UriBreakChars

proc stripTrailingPunctuation(runes: seq[Rune]): seq[Rune] =
  ## Remove trailing punctuation that is likely not part of the URI.
  ## Handle balanced parentheses (common in Wikipedia URLs).
  result = runes
  while result.len > 0:
    let last = result[^1]
    if last == Rune(')'):
      if result.count(Rune(')')) > result.count(Rune('(')):
        result.setLen(result.len - 1)
      else:
        break
    elif last == Rune(']'):
      if result.count(Rune(']')) > result.count(Rune('[')):
        result.setLen(result.len - 1)
      else:
        break
    elif last.int32 < 128 and char(last.int32) in TrailingPunctuation:
      result.setLen(result.len - 1)
    else:
      break

proc findSchemeAtRune(runes: seq[Rune], pos: int): int =
  ## Check if any URI scheme starts at the given rune position.
  ## Returns the length (in runes) of the scheme if found, -1 otherwise.
  ## Since URI schemes are ASCII, rune length == byte length.
  for scheme in UriSchemes:
    if pos + scheme.len <= runes.len:
      var matches = true
      for j in 0 ..< scheme.len:
        let r = runes[pos + j]
        if r.int32 > 127 or char(r.int32).toLowerAscii != scheme[j]:
          matches = false
          break
      if matches:
        return scheme.len
  return -1

type UriMatch* = tuple[start, finish: int, uri: string]

proc findAllUris*(line: string, maxRunes: int = 0): seq[UriMatch] =
  ## Find all URIs in a line of text.
  ## Returns a sequence of (start rune column, end rune column, uri string).
  ## Positions are Unicode character (rune) indices.
  ##
  ## `maxRunes > 0` bounds the scan to the first `maxRunes` runes (matching the
  ## syntax-highlight cap); URIs past the cap aren't highlighted anyway, and one
  ## straddling it is underlined only up to it. `runeSubStr` scans at most
  ## `maxRunes` runes, keeping the cost O(cap).
  let runes =
    if maxRunes > 0 and line.len > maxRunes:
      line.runeSubStr(0, maxRunes).toRunes
    else:
      line.toRunes
  var pos = 0
  while pos < runes.len:
    let schemeLen = findSchemeAtRune(runes, pos)
    if schemeLen < 0:
      inc pos
      continue

    # Found a scheme. Now scan forward for the URI body.
    let uriStart = pos
    var uriEnd = pos + schemeLen
    while uriEnd < runes.len and not runes[uriEnd].isUriBreakRune:
      inc uriEnd
    dec uriEnd # uriEnd is now the last rune index

    if uriEnd < uriStart + schemeLen:
      # Scheme only, no body
      pos = uriStart + schemeLen
      continue

    let rawRunes = runes[uriStart .. uriEnd]
    let strippedRunes = stripTrailingPunctuation(rawRunes)
    let uri = $strippedRunes
    let finish = uriStart + strippedRunes.len - 1
    result.add((start: uriStart, finish: finish, uri: uri))
    pos = uriEnd + 1

proc extractUriAtPosition*(line: string, column: int): Option[string] =
  ## Extract the URI at the given cursor column (rune index), if any.
  for m in findAllUris(line):
    if column >= m.start and column <= m.finish:
      return some(m.uri)
  return none(string)

proc extractFilePathAtPosition*(line: string, column: int): Option[string] =
  ## Extract a file path at the given cursor column (rune index).
  ## Recognizes absolute paths (/...) and relative paths (./..., ../).
  let runes = line.toRunes
  if column >= runes.len:
    return none(string)

  let pathBreakChars =
    Whitespace + {'<', '>', '"', '`', '[', ']', '{', '}', '(', ')', '\''}

  proc isPathBreak(r: Rune): bool =
    let c = r.int32
    if c > 127:
      return false
    return char(c) in pathBreakChars

  # Find the start of the path: scan backward from cursor
  var start = column
  while start > 0 and not runes[start - 1].isPathBreak:
    dec start

  # Find the end of the path: scan forward from cursor
  var finish = column
  while finish < runes.len - 1 and not runes[finish + 1].isPathBreak:
    inc finish

  if finish < start:
    return none(string)

  let path = $runes[start .. finish]

  # Must look like a file path
  if path.startsWith("/") or path.startsWith("./") or path.startsWith("../") or
      path.startsWith("~"):
    return some(path)

  return none(string)

proc isLocalFileUri*(uri: string): bool =
  ## Returns true if the URI uses the file:// scheme.
  uri.startsWith("file://")

proc isExternalUri*(uri: string): bool =
  ## Returns true if the URI uses an external scheme (http, https, mailto, etc).
  uri.startsWith("http://") or uri.startsWith("https://") or uri.startsWith("mailto:") or
    uri.startsWith("ftp://") or uri.startsWith("ssh://")

proc fileUriToPath*(uri: string): string =
  ## Convert a file:// URI to a local file path, percent-decoding it.
  if uri.startsWith("file://"):
    return decodeUrl(uri[7 ..^ 1], decodePlus = false)
  return uri

proc openExternalUri*(uri: string): bool =
  ## Open an external URI using the platform's default handler.
  ## Returns true if the command was launched successfully.
  ## The process is fire-and-forget (non-blocking).
  let cmd = when defined(macosx): "open" else: "xdg-open"

  try:
    let p = startProcess(cmd, args = @[uri], options = {poUsePath})
    p.close()
    return true
  except OSError:
    return false
