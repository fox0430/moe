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

## User-facing fold operations (vim-style manual folding).
## `FoldState` type and the line-shift adjusters (`adjustFoldsAfterInsert` /
## `adjustFoldsAfterDelete`) live in `core.nim` because they are needed by
## `newTextBuffer` and the mutation helpers.

import std/options

import core
import ../unicode_utils

proc addFold*(
    state: var FoldState,
    startLine, endLine: int,
    collapsed: bool = true,
    collapsedText: Option[string] = none(string),
    source: FoldSource = fsManual,
): bool =
  ## Add a new fold. Returns true if successful, false if it conflicts with an
  ## existing fold.
  ## Folds are kept sorted by startLine (outer-first when start lines tie).
  ## Single-line folds (startLine == endLine) are allowed.
  ## Nested and disjoint folds are allowed; only *crossing* (partial overlap)
  ## and exact-duplicate folds are rejected. LSP servers only ever produce
  ## disjoint or properly-nested ranges, but the crossing guard stays for safety.
  ## collapsed: Whether the fold starts collapsed (default: true)
  ## collapsedText: Custom text to display when collapsed (from LSP)
  ## source: Origin of the fold (manual or LSP)
  if startLine > endLine or startLine < 0:
    return false

  for fold in state.folds:
    # Reject an exact duplicate.
    if startLine == fold.startLine and endLine == fold.endLine:
      return false
    let
      disjoint = endLine < fold.startLine or startLine > fold.endLine
      newContainsOld = startLine <= fold.startLine and endLine >= fold.endLine
      oldContainsNew = startLine >= fold.startLine and endLine <= fold.endLine
    # Allow disjoint and proper containment; reject crossing (partial overlap).
    if not (disjoint or newContainsOld or oldContainsNew):
      return false

  # Insert keeping the list sorted by startLine, and outer-first (larger endLine
  # first) when start lines tie, so lookups return the outermost fold first.
  var insertIdx = state.folds.len
  for i, fold in state.folds:
    if startLine < fold.startLine or
        (startLine == fold.startLine and endLine > fold.endLine):
      insertIdx = i
      break

  state.folds.insert(
    Fold(
      startLine: startLine,
      endLine: endLine,
      collapsed: collapsed,
      collapsedText: collapsedText,
      source: source,
    ),
    insertIdx,
  )
  return true

proc foldIndexAt*(state: FoldState, line: int): Option[int] =
  ## Index of the fold containing `line`, if any.
  ## Returning an index (rather than a `ptr Fold`) is safe across mutations
  ## that grow `state.folds` and reallocate its underlying buffer.
  ##
  ## `state.folds` is kept start-line sorted by `addFold` (and the line-shift
  ## adjusters preserve that order), so every line-keyed lookup below stops as
  ## soon as a fold starts past `line`: nothing further can contain it. This
  ## keeps the per-call cost proportional to the cursor position rather than the
  ## total fold count, which matters on the per-frame viewport/cursor walks.
  for i in 0 ..< state.folds.len:
    let fold = state.folds[i]
    if fold.startLine > line:
      break
    if line >= fold.startLine and line <= fold.endLine:
      return some(i)

proc foldIndexAtInnermost*(state: FoldState, line: int): Option[int] =
  ## Index of the innermost fold containing `line`, if any.
  ## Among nested folds covering `line`, returns the one with the largest
  ## startLine (and, on ties, the smallest endLine) — i.e. the tightest fold.
  ## This matches vim's "operate on the innermost fold" behaviour for
  ## open/close/toggle/delete at the cursor.
  var
    best = -1
    bestStart = low(int)
    bestEnd = high(int)
  for i in 0 ..< state.folds.len:
    let fold = state.folds[i]
    if fold.startLine > line:
      break
    if line >= fold.startLine and line <= fold.endLine:
      if fold.startLine > bestStart or
          (fold.startLine == bestStart and fold.endLine < bestEnd):
        best = i
        bestStart = fold.startLine
        bestEnd = fold.endLine
  if best >= 0:
    return some(best)

proc foldIndexAtStartLine*(state: FoldState, line: int): Option[int] =
  ## Index of the fold that starts at `line`, if any.
  for i in 0 ..< state.folds.len:
    if state.folds[i].startLine > line:
      break
    if state.folds[i].startLine == line:
      return some(i)

proc getFoldAt*(state: FoldState, line: int): Option[Fold] =
  ## Get a copy of the fold containing `line` (if any). For read-only use.
  let idx = state.foldIndexAt(line)
  if idx.isSome:
    return some(state.folds[idx.get])

proc getFoldAtStartLine*(state: FoldState, line: int): Option[Fold] =
  ## Get a copy of the fold that starts at `line` (if any). For read-only use.
  let idx = state.foldIndexAtStartLine(line)
  if idx.isSome:
    return some(state.folds[idx.get])

proc isLineInCollapsedFold*(state: FoldState, line: int): bool =
  ## Check if a line is inside a collapsed fold (but not the start line)
  for fold in state.folds:
    if fold.startLine > line:
      break
    if fold.collapsed and line > fold.startLine and line <= fold.endLine:
      return true

proc getCollapsedFoldAt*(state: FoldState, line: int): Option[Fold] =
  ## Get the collapsed fold that contains this line (for rendering the fold marker)
  for fold in state.folds:
    if fold.startLine > line:
      break
    if fold.collapsed and line >= fold.startLine and line <= fold.endLine:
      return some(fold)

proc touchesCollapsedFold*(state: FoldState, startLine, endLine: int): bool =
  ## True when any collapsed fold overlaps the inclusive line range, including
  ## a fold the range already contains whole.
  let
    lo = min(startLine, endLine)
    hi = max(startLine, endLine)
  for fold in state.folds:
    if fold.startLine > hi:
      break
    if fold.collapsed and fold.endLine >= lo:
      return true

proc snapRangeToFolds*(
    state: FoldState, startLine, endLine: int
): tuple[startLine, endLine: int] =
  ## Widen an inclusive line range so every collapsed fold it touches is covered
  ## whole, as vim does. Iterates to a fixed point for nested and chained folds.
  ## Does not modify the fold state.
  var
    lo = min(startLine, endLine)
    hi = max(startLine, endLine)
    changed = true
  while changed:
    changed = false
    for fold in state.folds:
      if fold.startLine > hi:
        break
      if not fold.collapsed or fold.endLine < lo:
        continue
      if fold.startLine < lo:
        lo = fold.startLine
        changed = true
      if fold.endLine > hi:
        hi = fold.endLine
        changed = true
  (lo, hi)

proc openFold*(state: var FoldState, line: int): bool =
  ## Open the innermost fold at the given line. Returns true only when a
  ## collapsed fold was actually opened, so callers can use the result to decide
  ## whether a redraw is needed (an already-open fold is a no-op).
  let idx = state.foldIndexAtInnermost(line)
  if idx.isSome and state.folds[idx.get].collapsed:
    state.folds[idx.get].collapsed = false
    return true

proc closeFold*(state: var FoldState, line: int): bool =
  ## Close the innermost fold at the given line. Returns true only when an open
  ## fold was actually closed, so callers can treat an already-closed fold as a
  ## silent no-op and avoid a needless redraw (mirroring openFold).
  let idx = state.foldIndexAtInnermost(line)
  if idx.isSome and not state.folds[idx.get].collapsed:
    state.folds[idx.get].collapsed = true
    return true

proc toggleFold*(state: var FoldState, line: int): bool =
  ## Toggle the innermost fold at the given line. Returns true if a fold was toggled.
  let idx = state.foldIndexAtInnermost(line)
  if idx.isSome:
    state.folds[idx.get].collapsed = not state.folds[idx.get].collapsed
    return true

proc deleteFold*(state: var FoldState, line: int): bool =
  ## Delete the innermost fold containing the given line.
  ## Returns true if a fold was deleted.
  let idx = state.foldIndexAtInnermost(line)
  if idx.isSome:
    state.folds.delete(idx.get)
    return true

proc openFoldsInRange*(state: var FoldState, startLine, endLine: int): bool =
  ## Open every collapsed fold overlapping the inclusive line range
  ## [min(startLine, endLine), max(startLine, endLine)]. Returns true if any
  ## fold was opened. Used so range edits (visual mode, :s, :d) never modify
  ## lines hidden inside a collapsed fold.
  let
    lo = min(startLine, endLine)
    hi = max(startLine, endLine)
  for i in 0 ..< state.folds.len:
    if state.folds[i].collapsed and
        not (state.folds[i].endLine < lo or state.folds[i].startLine > hi):
      state.folds[i].collapsed = false
      result = true

proc openAllFolds*(state: var FoldState) =
  ## Open all folds
  for i in 0 ..< state.folds.len:
    state.folds[i].collapsed = false

proc closeAllFolds*(state: var FoldState) =
  ## Close all folds
  for i in 0 ..< state.folds.len:
    state.folds[i].collapsed = true

proc deleteAllFolds*(state: var FoldState) =
  ## Delete all folds (zD command)
  state.folds = @[]

proc getNextVisibleLine*(state: FoldState, line: int, maxLine: int): int =
  ## Get the next visible line after a folded region
  ## If line is inside a collapsed fold, skip to the line after the fold
  for fold in state.folds:
    if fold.startLine > line:
      break
    if fold.collapsed and line >= fold.startLine and line <= fold.endLine:
      return min(fold.endLine + 1, maxLine)
  return line

proc getPrevVisibleLine*(state: FoldState, line: int): int =
  ## Get the previous visible line (skip over collapsed folds)
  ## If line is at the end of a collapsed fold, jump to the start line
  for fold in state.folds:
    if fold.startLine > line:
      break
    if fold.collapsed and line > fold.startLine and line <= fold.endLine:
      return fold.startLine
  return line

proc formatFoldText*(b: TextBuffer, fold: Fold): string =
  ## Format the display text for a collapsed fold (vim-style)
  ## Example: "+-- 10 lines: func foo() {...}"
  ## If LSP provided collapsedText, use it instead of generating preview
  let lineCount = fold.endLine - fold.startLine + 1

  # Use LSP-provided collapsedText if available
  if fold.collapsedText.isSome and fold.collapsedText.get.len > 0:
    result = "+-- " & $lineCount & " lines: " & fold.collapsedText.get
  else:
    let preview = b.getLine(fold.startLine).truncateToCharsWithSuffix(40)
    result = "+-- " & $lineCount & " lines: " & preview
