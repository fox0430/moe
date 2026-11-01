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

## Searches as Normal mode and the viewers run them: the case a search
## ignores, the way it goes, stepping over its matches, the search * and # make
## of the text under the cursor (Vim's nv_ident) and n/N repeating the last one.

import std/options

import pkg/results

import types, buffer, search_utils, unicode_utils

proc ignoresCase*(search: SearchState, spec: SearchSpec): bool =
  ## Whether `spec` ignores case: 'ignorecase', unless 'smartcase' finds an
  ## upper case letter in a typed pattern. Like Vim's no_scs, * and # leave
  ## 'smartcase' out.
  shouldIgnoreCase(
    spec.pattern, search.ignorecase, search.smartcase and spec.match == smRegex
  )

proc findMatch*(
    b: TextBuffer,
    spec: SearchSpec,
    pos: BufferPosition,
    ignoreCase: bool,
    direction = spec.direction,
): Option[BufferPosition] =
  ## The match of `spec` from `pos`, the way `direction` goes: the one `spec`
  ## went unless given.
  if direction == Forward:
    b.findNext(spec.pattern, pos, ignoreCase, spec.match)
  else:
    b.findPrev(spec.pattern, pos, ignoreCase, spec.match)

proc stepMatches*(
    first: BufferPosition,
    count: int,
    step: proc(pos: BufferPosition): Option[BufferPosition],
): BufferPosition =
  ## The match `count - 1` on from `first`, `step` finding each next one. The
  ## search wraps around, so once round the matches only what is left over the
  ## cycle matters (`999999n` does not search a million times), and a match
  ## with no other to go to is the one found again.
  result = first
  var
    left = count - 1
    taken = 0
  while left > 0:
    let next = step(result)
    if next.isNone:
      break
    result = next.get
    left -= 1
    taken += 1
    if result == first:
      left = left mod taken

proc searchIdent*(
    state: EditorState,
    b: TextBuffer,
    pos: BufferPosition,
    forward, bounded: bool,
    count: int,
): Result[BufferPosition, string] =
  ## The `count`-th match of the text under `pos`, made the last search, as
  ## Vim's nv_ident: * and # match it as a word (`bounded`), g* and g# also
  ## inside words. The search starts at the start of the text, so the only
  ## match is found again.
  let found = b.identUnderCursor(pos)
  if found.isNone:
    state.statusMessage = "E348: No string under cursor"
    return err(state.statusMessage)
  let
    ident = found.get
    spec = SearchSpec(
      pattern:
        b.getLine(pos.line).charSubStr(ident.startCol, ident.endCol - ident.startCol),
      match: if bounded: smWord else: smLiteral,
      direction: if forward: Forward else: Backward,
    )
  state.input.search.last = spec
  state.input.search.hlsearchTempDisabled = false

  let ignoreCase = state.input.search.ignoresCase(spec)
  proc step(pos: BufferPosition): Option[BufferPosition] =
    b.findMatch(spec, pos, ignoreCase)

  let first = step(BufferPosition(line: pos.line, column: ident.startCol))
  if first.isNone:
    state.statusMessage = "Pattern not found: " & spec.pattern
    return err("Pattern not found")

  state.statusMessage = "Found: " & spec.pattern
  ok(stepMatches(first.get, count, step))

proc searchLast*(
    state: EditorState, b: TextBuffer, pos: BufferPosition, reverse: bool, count: int
): Result[BufferPosition, string] =
  ## The `count`-th match of the last search from `pos` (n), the other way when
  ## `reverse` (N). As Vim keeps it with the pattern, the way is the one /, ?,
  ## * or # went.
  let spec = state.input.search.last
  if spec.pattern.len == 0:
    state.statusMessage = "E35: No previous regular expression"
    return err(state.statusMessage)

  state.input.search.hlsearchTempDisabled = false

  let ignoreCase = state.input.search.ignoresCase(spec)
  # * and # match literally
  if spec.match == smRegex and compileSearchRegex(spec.pattern, ignoreCase).isNone:
    state.statusMessage = "Invalid regex: " & spec.pattern
    return err("Invalid regex")

  let direction = repeatDirection(spec.direction, reverse)
  proc step(pos: BufferPosition): Option[BufferPosition] =
    b.findMatch(spec, pos, ignoreCase, direction)

  let first = step(pos)
  if first.isNone:
    state.statusMessage = "Pattern not found: " & spec.pattern
    return err("Pattern not found")

  state.statusMessage = "Found: " & spec.pattern
  ok(stepMatches(first.get, count, step))
