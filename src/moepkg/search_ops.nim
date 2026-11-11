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
## ignores, the way it goes, stepping over its matches, the search / and ?
## make of what is typed after them, the search * and # make of the text under
## the cursor (Vim's nv_ident) and n/N repeating the last one.

import std/options

import pkg/results

import types, buffer, modes, search_utils, unicode_utils

proc ignoresCase*(search: SearchState, spec: SearchSpec): bool =
  ## Whether `spec` ignores case: 'ignorecase', unless 'smartcase' finds an
  ## upper case letter in a typed pattern. Like Vim's no_scs, * and # leave
  ## 'smartcase' out.
  shouldIgnoreCase(
    spec.pattern, search.ignorecase, search.smartcase and spec.match == smRegex
  )

proc invalidRegex*(search: SearchState, spec: SearchSpec): string =
  ## "Invalid regex: ..." when `spec` is a regex that does not compile, empty
  ## otherwise.
  invalidRegex(spec.pattern, search.ignoresCase(spec), spec.match)

proc findMatch*(
    b: TextBuffer,
    spec: SearchSpec,
    pos: BufferPosition,
    ignoreCase: bool,
    direction = spec.direction,
): Option[LineMatch] =
  ## The match of `spec` from `pos`, the way `direction` goes: the one `spec`
  ## went unless given.
  b.findMatchFrom(spec.pattern, pos, ignoreCase, spec.match, direction)

proc stepMatches*(
    first: LineMatch, count: int, step: proc(pos: BufferPosition): Option[LineMatch]
): LineMatch =
  ## The match `count - 1` on from `first`, `step` finding each next one from
  ## where the one before starts. The search wraps around, so once round the
  ## matches only what is left over the cycle matters (`999999n` does not
  ## search a million times), and a match with no other to go to is the one
  ## found again.
  result = first
  var
    left = count - 1
    taken = 0
  while left > 0:
    let next = step(result.start)
    if next.isNone:
      break
    result = next.get
    left -= 1
    taken += 1
    if result == first:
      left = left mod taken

proc landing*(state: EditorState, b: TextBuffer, match: LineMatch): BufferPosition =
  ## Where the cursor goes on `match`. As Vim's normal_search does with
  ## check_cursor after `/$`, one at the end of a line puts it on the last
  ## character, with an operator waiting too (`d/$`), but not in Visual mode
  ## or after Ctrl-o in Insert mode (restart_edit).
  let
    lineLen = b.getLine(match.line).charLen
    lastColumn =
      if state.resumesInsert:
        lineLen
      else:
        maxCursorColumn(lineLen, state.mode)
  BufferPosition(line: match.line, column: min(match.cols.startCol, lastColumn))

proc findCountedMatch*(
    state: EditorState,
    b: TextBuffer,
    spec: SearchSpec,
    pos: BufferPosition,
    count: int,
    direction = spec.direction,
): Option[LineMatch] =
  ## The `count`-th match of `spec` from `pos`, the way `direction` goes.
  let ignoreCase = state.input.search.ignoresCase(spec)
  proc step(pos: BufferPosition): Option[LineMatch] =
    b.findMatch(spec, pos, ignoreCase, direction)

  let first = step(pos)
  if first.isSome:
    some(stepMatches(first.get, count, step))
  else:
    none(LineMatch)

proc findCounted*(
    state: EditorState,
    b: TextBuffer,
    spec: SearchSpec,
    pos: BufferPosition,
    count: int,
    direction = spec.direction,
): Option[BufferPosition] =
  ## Where the cursor goes on the `count`-th match of `spec` from `pos`, the
  ## way `direction` goes.
  let found = state.findCountedMatch(b, spec, pos, count, direction)
  if found.isSome:
    some(state.landing(b, found.get))
  else:
    none(BufferPosition)

proc addSearchHistory*(state: EditorState, pattern: string) =
  ## Push `pattern` onto the search history, most recent first, dropping an
  ## older duplicate and trimming to the configured limit.
  for i in countdown(state.input.search.history.high, 0):
    if state.input.search.history[i] == pattern:
      state.input.search.history.delete(i)

  state.input.search.history.insert(pattern, 0)

  let historyLimit = state.config.persist.searchHistoryLimit
  if state.input.search.history.len > historyLimit:
    state.input.search.history.setLen(historyLimit)

proc submitSearch*(
    state: EditorState, typed: string, direction: SearchDirection
): Option[SearchSpec] =
  ## Make what was typed after / or ? (`direction`) the last search, as Enter
  ## does. An empty one repeats the last, history entry and how it matches
  ## included (a * search stays one); either goes `direction`, and so does n
  ## after it. None, with E35, when there is nothing to repeat.
  let isRepeat = typed.len == 0
  if isRepeat and state.input.search.last.pattern.len == 0:
    state.statusMessage = "E35: No previous regular expression"
    return none(SearchSpec)
  var spec =
    if isRepeat:
      state.input.search.last
    else:
      SearchSpec(pattern: typed)
  spec.direction = direction
  state.setLastSearch(spec)
  if not isRepeat:
    state.addSearchHistory(typed)
  some(spec)

proc searchSubmitted*(
    state: EditorState, b: TextBuffer, spec: SearchSpec, pos: BufferPosition, count: int
): Option[BufferPosition] =
  ## The `count`-th match of `spec` from `pos`, as Enter after / or ? finds
  ## it, with the message it leaves.
  result = state.findCounted(b, spec, pos, count)
  state.statusMessage =
    if result.isSome:
      "Found: " & spec.pattern
    else:
      let invalid = state.input.search.invalidRegex(spec)
      if invalid.len > 0:
        invalid
      else:
        "Pattern not found: " & spec.pattern

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
  state.setLastSearch(spec)

  let match = state.findCounted(
    b, spec, BufferPosition(line: pos.line, column: ident.startCol), count
  )
  if match.isNone:
    state.statusMessage = "Pattern not found: " & spec.pattern
    return err("Pattern not found")

  state.statusMessage = "Found: " & spec.pattern
  ok(match.get)

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

  state.showSearchMatches()

  let invalid = state.input.search.invalidRegex(spec)
  if invalid.len > 0:
    state.statusMessage = invalid
    return err("Invalid regex")

  let found =
    state.findCounted(b, spec, pos, count, repeatDirection(spec.direction, reverse))
  if found.isNone:
    state.statusMessage = "Pattern not found: " & spec.pattern
    return err("Pattern not found")

  state.statusMessage = "Found: " & spec.pattern
  ok(found.get)
