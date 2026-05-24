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

## Language-aware smart indentation helpers.
##
## Pure functions only: no buffer/state mutation. Used by Insert mode
## newline handlers when `smartIndent` is enabled. Currently implements
## Nim-only rules.

import std/strutils
import ../syntax/tokenizer

const
  NimContinuationKeywords = ["or", "and", "object", "tuple", "enum"]
  NimBlockDeclKeywords = ["var", "let", "const", "type"]

proc stripNimCodeOnly*(line: string): string =
  ## Return `line` with string literals (`"..."` / `'...'`) and backtick-
  ## quoted identifiers (`` `...` ``) replaced by spaces+`x`s, and any
  ## trailing `# ...` comment removed, so callers can do simple
  ## trailing-token checks without worrying about literals/comments.
  ##
  ## If the line contains a triple-quoted token (`"""`) we cannot determine
  ## from a single line whether we are inside or outside a long string, so
  ## we conservatively return an empty string (which disables all triggers
  ## for that line).
  if line.contains("\"\"\""):
    return ""

  result = newStringOfCap(line.len)
  var i = 0
  while i < line.len:
    let c = line[i]
    case c
    of '"':
      result.add(' ')
      inc i
      while i < line.len:
        let cc = line[i]
        if cc == '\\' and i + 1 < line.len:
          result.add('x')
          result.add('x')
          i += 2
          continue
        if cc == '"':
          result.add(' ')
          inc i
          break
        if cc == '\n':
          break
        result.add('x')
        inc i
    of '\'':
      result.add(' ')
      inc i
      while i < line.len:
        let cc = line[i]
        if cc == '\\' and i + 1 < line.len:
          result.add('x')
          result.add('x')
          i += 2
          continue
        if cc == '\'':
          result.add(' ')
          inc i
          break
        if cc == '\n':
          break
        result.add('x')
        inc i
    of '`':
      # Backtick-quoted identifier (e.g. `` `or` ``). No escape sequences
      # inside, so just consume until the next backtick or newline.
      result.add(' ')
      inc i
      while i < line.len:
        let cc = line[i]
        if cc == '`':
          result.add(' ')
          inc i
          break
        if cc == '\n':
          break
        result.add('x')
        inc i
    of '#':
      break
    else:
      result.add(c)
      inc i

proc isWordChar(c: char): bool {.inline.} =
  c.isAlphaNumeric or c == '_'

proc endsWithKeyword(stripped: string, kw: string): bool =
  ## Whole-word match: `stripped` ends with `kw` and the char before `kw`
  ## (if any) is a non-word character.
  if stripped.len < kw.len:
    return false
  if not stripped.endsWith(kw):
    return false
  let before = stripped.len - kw.len - 1
  if before < 0:
    return true
  return not isWordChar(stripped[before])

proc endsWithSingleEquals(stripped: string): bool =
  ## True when the line ends with a `=` that is not part of a comparison
  ## (`==`, `!=`, `<=`, `>=`) or compound assignment (`+=`, `-=`, `*=`,
  ## `/=`, `%=`, `&=`, `|=`, `^=`, etc). The stripped line is already
  ## free of trailing whitespace by the caller.
  if stripped.len == 0 or stripped[^1] != '=':
    return false
  if stripped.len == 1:
    return true
  # Operator characters per the Nim manual that can combine with `=`.
  const OperatorChars = {
    '=', '+', '-', '*', '/', '<', '>', '@', '$', '~', '&', '%', '|', '!', '?', '^', '.',
    ':', '\\',
  }
  return stripped[^2] notin OperatorChars

proc endsWithBlockColon(stripped: string): bool =
  ## True when the line ends with a single `:` (block opener: if/while/
  ## for/elif/else/of/try/except/finally/block/defer/proc-body, etc.).
  ## Excludes `::` defensively even though it is not Nim syntax.
  if stripped.len == 0 or stripped[^1] != ':':
    return false
  if stripped.len >= 2 and stripped[^2] == ':':
    return false
  return true

proc unclosedBracketDepth(stripped: string): int =
  ## Count `(` + `[` + `{` minus their matching closers across `stripped`.
  ## Negative results are clamped to 0 (defensive — should not normally
  ## happen on a single syntactically-balanced-so-far line).
  var depth = 0
  for c in stripped:
    case c
    of '(', '[', '{':
      inc depth
    of ')', ']', '}':
      if depth > 0:
        dec depth
    else:
      discard
  result = depth

proc nimNeedsExtraIndent(line: string): bool =
  let code = stripNimCodeOnly(line)
  if code.len == 0:
    return false
  let stripped = code.strip(leading = false, trailing = true)
  if stripped.len == 0:
    return false

  let trimmed = stripped.strip()
  for kw in NimBlockDeclKeywords:
    if trimmed == kw:
      return true

  for kw in NimContinuationKeywords:
    if endsWithKeyword(stripped, kw):
      return true

  if endsWithBlockColon(stripped):
    return true

  if endsWithSingleEquals(stripped):
    return true

  if unclosedBracketDepth(stripped) > 0:
    return true

  return false

proc extraIndentForNewline*(
    line: string, language: SourceLanguage, indentUnit: string
): string =
  ## Return the additional indent string to append after the base indent
  ## when Enter is pressed on `line`. Returns `""` when no trigger fires
  ## or the language is unsupported.
  ##
  ## Always returns at most one `indentUnit` regardless of how many
  ## triggers match (e.g. nested unclosed brackets).
  case language
  of langNim:
    if nimNeedsExtraIndent(line):
      return indentUnit
    return ""
  else:
    return ""
