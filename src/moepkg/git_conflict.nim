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

## Detection and highlighting of git merge conflict markers.
##
## Scans a buffer for conflict markers (`<<<<<<<`, `|||||||`, `=======`,
## `>>>>>>>`), pairs them into `ConflictBlock` values, and applies
## `LineMarkerKind.GitConflict` markers to the affected lines so the
## sidebar and the editor view can render them distinctly.

import std/options

import buffer/[core, markers]

const
  MarkerLen = 7
  DefaultConflictScanIntervalMs* = 500
    ## Default debounce interval for rescanning the active buffer for
    ## conflict markers (milliseconds).

proc isMarkerChar(c: char, want: char): bool {.inline.} =
  c == want

proc hasMarkerPrefix(line: string, ch: char): bool =
  ## True when `line` begins with exactly `MarkerLen` copies of `ch` followed
  ## by end-of-line or whitespace, and nothing else. This matches git's own
  ## emission format and avoids matching lines such as "<<<<<<<<<<<<<<<<<<".
  if line.len < MarkerLen:
    return false
  for i in 0 ..< MarkerLen:
    if not isMarkerChar(line[i], ch):
      return false
  if line.len == MarkerLen:
    return true
  # Reject an 8th consecutive marker char
  if isMarkerChar(line[MarkerLen], ch):
    return false
  # Require whitespace after the marker
  line[MarkerLen] in {' ', '\t'}

proc parseConflictMarkerLine*(line: string): ConflictMarkerKind =
  ## Classify a single line according to the conflict marker it carries, if
  ## any. Returns `cmkNone` for ordinary content lines.
  if line.len == 0:
    return cmkNone
  case line[0]
  of '<':
    if hasMarkerPrefix(line, '<'): cmkStartMarker else: cmkNone
  of '|':
    if hasMarkerPrefix(line, '|'): cmkBaseMarker else: cmkNone
  of '=':
    if hasMarkerPrefix(line, '='): cmkSeparator else: cmkNone
  of '>':
    if hasMarkerPrefix(line, '>'): cmkEndMarker else: cmkNone
  else:
    cmkNone

proc extractConflictLabel*(line: string, prefixLen: int = MarkerLen): string =
  ## Return the trimmed label after a marker (e.g. `HEAD` from
  ## `<<<<<<< HEAD`). Returns an empty string when no label is present.
  if line.len <= prefixLen:
    return ""
  var i = prefixLen
  while i < line.len and line[i] in {' ', '\t'}:
    inc i
  if i >= line.len:
    return ""
  var endIdx = line.len - 1
  while endIdx >= i and line[endIdx] in {' ', '\t', '\r'}:
    dec endIdx
  if endIdx < i:
    return ""
  line[i .. endIdx]

type ScanState = enum
  ssIdle ## Looking for a `<<<<<<<`
  ssOurs ## Inside the "ours" block, before `|||||||` / `=======`
  ssBase ## Inside the diff3 base block (between `|||||||` and `=======`)
  ssTheirs ## Inside the "theirs" block (between `=======` and `>>>>>>>`)

proc scanBufferForConflicts*(buffer: TextBuffer): seq[ConflictBlock] =
  ## Walk the buffer line-by-line and collect every complete conflict block.
  ## Unclosed, orphaned, or nested conflicts are discarded (on nesting, the
  ## inner `<<<<<<<` restarts scanning — the outer block is abandoned).
  result = @[]
  var state = ssIdle
  var cur: ConflictBlock
  cur.baseMarkerLine = none(int)

  for lineIndex in 0 ..< buffer.len:
    let line = buffer.getLine(lineIndex)
    let kind = parseConflictMarkerLine(line)
    case state
    of ssIdle:
      if kind == cmkStartMarker:
        cur = ConflictBlock(
          startLine: lineIndex,
          baseMarkerLine: none(int),
          separatorLine: -1,
          endLine: -1,
          oursLabel: extractConflictLabel(line),
          theirsLabel: "",
        )
        state = ssOurs
    of ssOurs:
      case kind
      of cmkStartMarker:
        # Nested start: restart tracking with the new block
        cur = ConflictBlock(
          startLine: lineIndex,
          baseMarkerLine: none(int),
          separatorLine: -1,
          endLine: -1,
          oursLabel: extractConflictLabel(line),
          theirsLabel: "",
        )
      of cmkBaseMarker:
        cur.baseMarkerLine = some(lineIndex)
        state = ssBase
      of cmkSeparator:
        cur.separatorLine = lineIndex
        state = ssTheirs
      of cmkEndMarker:
        # Missing `=======` → malformed, drop
        state = ssIdle
      else:
        discard
    of ssBase:
      case kind
      of cmkStartMarker:
        cur = ConflictBlock(
          startLine: lineIndex,
          baseMarkerLine: none(int),
          separatorLine: -1,
          endLine: -1,
          oursLabel: extractConflictLabel(line),
          theirsLabel: "",
        )
        state = ssOurs
      of cmkSeparator:
        cur.separatorLine = lineIndex
        state = ssTheirs
      of cmkEndMarker:
        state = ssIdle
      else:
        discard
    of ssTheirs:
      case kind
      of cmkStartMarker:
        cur = ConflictBlock(
          startLine: lineIndex,
          baseMarkerLine: none(int),
          separatorLine: -1,
          endLine: -1,
          oursLabel: extractConflictLabel(line),
          theirsLabel: "",
        )
        state = ssOurs
      of cmkEndMarker:
        cur.endLine = lineIndex
        cur.theirsLabel = extractConflictLabel(line)
        result.add(cur)
        state = ssIdle
      else:
        discard

proc applyConflictsToBuffer*(buffer: TextBuffer, blocks: seq[ConflictBlock]) =
  ## Store the blocks on the buffer and stamp `GitConflict` sidebar markers on
  ## every line inside each block. Orphan marker lines (marker lines that
  ## don't form a complete block, e.g. while the user is mid-edit) also get
  ## the sidebar marker so the visual indicator never vanishes from a
  ## half-resolved conflict.
  ##
  ## Single-pass walk: for each line, decide whether it belongs to a block or
  ## is an orphan marker, then stamp / clear in place. Relies on `blocks`
  ## being sorted by `startLine` (which `scanBufferForConflicts` guarantees).
  buffer.conflictBlocks = blocks
  var blockIdx = 0
  for line in 0 ..< buffer.len:
    while blockIdx < blocks.len and line > blocks[blockIdx].endLine:
      inc blockIdx
    let inBlock =
      blockIdx < blocks.len and line >= blocks[blockIdx].startLine and
      line <= blocks[blockIdx].endLine
    let shouldMark = inBlock or parseConflictMarkerLine(buffer.getLine(line)) != cmkNone
    let existing = buffer.lineMarkers[line]
    if shouldMark:
      buffer.setLineMarker(line, GitConflict)
    elif existing.isSome and existing.get == GitConflict:
      buffer.lineMarkers[line] = none(LineMarkerKind)

proc refreshConflicts*(buffer: TextBuffer) =
  ## Rescan the buffer and reapply conflict markers. Safe to call repeatedly.
  let blocks = scanBufferForConflicts(buffer)
  applyConflictsToBuffer(buffer, blocks)

proc lineConflictKind*(buffer: TextBuffer, line: int): ConflictMarkerKind =
  ## Look up the conflict role of a given line. O(K) over conflict blocks,
  ## which is typically very small. Falls back to a single-line marker check
  ## so that orphan / half-edited markers still render with the marker
  ## background instead of silently losing all decoration.
  for b in buffer.conflictBlocks:
    if line < b.startLine:
      continue
    if line > b.endLine:
      continue
    if line == b.startLine:
      return cmkStartMarker
    if line == b.endLine:
      return cmkEndMarker
    if line == b.separatorLine:
      return cmkSeparator
    if b.baseMarkerLine.isSome:
      let baseLine = b.baseMarkerLine.get
      if line == baseLine:
        return cmkBaseMarker
      if line < baseLine:
        return cmkOurs
      if line < b.separatorLine:
        return cmkBase
      return cmkTheirs
    else:
      if line < b.separatorLine:
        return cmkOurs
      return cmkTheirs
  if line >= 0 and line < buffer.len:
    parseConflictMarkerLine(buffer.getLine(line))
  else:
    cmkNone

proc findNextConflict*(buffer: TextBuffer, fromLine: int): Option[ConflictBlock] =
  ## Return the first conflict block whose start is strictly after `fromLine`.
  for b in buffer.conflictBlocks:
    if b.startLine > fromLine:
      return some(b)
  none(ConflictBlock)

proc findPrevConflict*(buffer: TextBuffer, fromLine: int): Option[ConflictBlock] =
  ## Return the last conflict block whose start is strictly before `fromLine`.
  var found: Option[ConflictBlock] = none(ConflictBlock)
  for b in buffer.conflictBlocks:
    if b.startLine < fromLine:
      found = some(b)
    else:
      break
  found
