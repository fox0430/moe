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

import std/[options, osproc, strutils]

const
  UriSchemes* = ["https://", "http://", "file://", "mailto:", "ftp://", "ssh://"]

  # Characters that terminate a URI.
  UriBreakChars =
    Whitespace + {'<', '>', '"', '`', '[', ']', '{', '}', '|', '\\', '^', '\''}

  # Trailing characters that are usually punctuation, not part of the URI.
  TrailingPunctuation = {'.', ',', ';', ':', '!', '?'}

proc stripTrailingPunctuation(uri: string): string =
  ## Remove trailing punctuation that is likely not part of the URI.
  ## Handle balanced parentheses (common in Wikipedia URLs).
  result = uri
  while result.len > 0:
    let last = result[^1]
    if last == ')':
      # Only strip if parentheses are unbalanced
      if result.count(')') > result.count('('):
        result = result[0 ..< result.len - 1]
      else:
        break
    elif last == ']':
      if result.count(']') > result.count('['):
        result = result[0 ..< result.len - 1]
      else:
        break
    elif last in TrailingPunctuation:
      result = result[0 ..< result.len - 1]
    else:
      break

proc findSchemeAt(line: string, pos: int): int =
  ## Check if any URI scheme starts at the given position.
  ## Returns the length of the scheme if found, -1 otherwise.
  for scheme in UriSchemes:
    if pos + scheme.len <= line.len and
        line[pos ..< pos + scheme.len].toLowerAscii() == scheme:
      return scheme.len
  return -1

type UriMatch* = tuple[start, finish: int, uri: string]

proc findAllUris*(line: string): seq[UriMatch] =
  ## Find all URIs in a line of text.
  ## Returns a sequence of (start column, end column, uri string).
  var pos = 0
  while pos < line.len:
    let schemeLen = findSchemeAt(line, pos)
    if schemeLen < 0:
      inc pos
      continue

    # Found a scheme. Now scan forward for the URI body.
    let uriStart = pos
    var uriEnd = pos + schemeLen
    while uriEnd < line.len and line[uriEnd] notin UriBreakChars:
      inc uriEnd
    dec uriEnd # uriEnd is now the last character index

    if uriEnd < uriStart + schemeLen:
      # Scheme only, no body
      pos = uriStart + schemeLen
      continue

    let raw = line[uriStart .. uriEnd]
    let uri = stripTrailingPunctuation(raw)
    let finish = uriStart + uri.len - 1
    result.add((start: uriStart, finish: finish, uri: uri))
    pos = uriEnd + 1

proc extractUriAtPosition*(line: string, column: int): Option[string] =
  ## Extract the URI at the given cursor column position, if any.
  for m in findAllUris(line):
    if column >= m.start and column <= m.finish:
      return some(m.uri)
  return none(string)

proc extractFilePathAtPosition*(line: string, column: int): Option[string] =
  ## Extract a file path at the given cursor column position.
  ## Recognizes absolute paths (/...) and relative paths (./..., ../).
  if column >= line.len:
    return none(string)

  let pathBreakChars =
    Whitespace + {'<', '>', '"', '`', '[', ']', '{', '}', '(', ')', '\''}

  # Find the start of the path: scan backward from cursor
  var start = column
  while start > 0 and line[start - 1] notin pathBreakChars:
    dec start

  # Find the end of the path: scan forward from cursor
  var finish = column
  while finish < line.len - 1 and line[finish + 1] notin pathBreakChars:
    inc finish

  if finish < start:
    return none(string)

  let path = line[start .. finish]

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
  ## Convert a file:// URI to a local file path.
  if uri.startsWith("file://"):
    return uri[7 ..^ 1]
  return uri

proc openExternalUri*(uri: string): bool =
  ## Open an external URI using the platform's default handler.
  ## Returns true if the command was launched successfully.
  ## The process is fire-and-forget (non-blocking).
  let cmd = when defined(macosx): "open" else: "xdg-open"

  try:
    discard startProcess(cmd, args = @[uri], options = {poUsePath})
    return true
  except OSError:
    return false
