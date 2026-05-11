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

import std/[options, unicode]

import ./core

proc addFold*(
    state: var FoldState,
    startLine, endLine: int,
    collapsed: bool = true,
    collapsedText: Option[string] = none(string),
): bool =
  ## Add a new fold. Returns true if successful, false if overlapping with existing fold.
  ## Folds are kept sorted by startLine. Single-line folds (startLine == endLine) are allowed.
  ## collapsed: Whether the fold starts collapsed (default: true)
  ## collapsedText: Custom text to display when collapsed (from LSP)
  if startLine > endLine or startLine < 0:
    return false

  # Check for overlapping folds
  for fold in state.folds:
    # Check if new fold overlaps with existing fold
    if not (endLine < fold.startLine or startLine > fold.endLine):
      return false

  # Insert in sorted order by startLine
  var insertIdx = state.folds.len
  for i, fold in state.folds:
    if startLine < fold.startLine:
      insertIdx = i
      break

  state.folds.insert(
    Fold(
      startLine: startLine,
      endLine: endLine,
      collapsed: collapsed,
      collapsedText: collapsedText,
    ),
    insertIdx,
  )
  return true

proc foldIndexAt*(state: FoldState, line: int): Option[int] =
  ## Index of the fold containing `line`, if any.
  ## Returning an index (rather than a `ptr Fold`) is safe across mutations
  ## that grow `state.folds` and reallocate its underlying buffer.
  for i in 0 ..< state.folds.len:
    let fold = state.folds[i]
    if line >= fold.startLine and line <= fold.endLine:
      return some(i)
  return none(int)

proc foldIndexAtStartLine*(state: FoldState, line: int): Option[int] =
  ## Index of the fold that starts at `line`, if any.
  for i in 0 ..< state.folds.len:
    if state.folds[i].startLine == line:
      return some(i)
  return none(int)

proc getFoldAt*(state: FoldState, line: int): Option[Fold] =
  ## Get a copy of the fold containing `line` (if any). For read-only use.
  let idx = state.foldIndexAt(line)
  if idx.isSome:
    return some(state.folds[idx.get])
  return none(Fold)

proc getFoldAtStartLine*(state: FoldState, line: int): Option[Fold] =
  ## Get a copy of the fold that starts at `line` (if any). For read-only use.
  let idx = state.foldIndexAtStartLine(line)
  if idx.isSome:
    return some(state.folds[idx.get])
  return none(Fold)

proc isLineInCollapsedFold*(state: FoldState, line: int): bool =
  ## Check if a line is inside a collapsed fold (but not the start line)
  for fold in state.folds:
    if fold.collapsed and line > fold.startLine and line <= fold.endLine:
      return true
  return false

proc getCollapsedFoldAt*(state: FoldState, line: int): Option[Fold] =
  ## Get the collapsed fold that contains this line (for rendering the fold marker)
  for fold in state.folds:
    if fold.collapsed and line >= fold.startLine and line <= fold.endLine:
      return some(fold)
  return none(Fold)

proc openFold*(state: var FoldState, line: int): bool =
  ## Open the fold at the given line. Returns true if a fold was opened.
  let idx = state.foldIndexAt(line)
  if idx.isSome:
    state.folds[idx.get].collapsed = false
    return true
  return false

proc closeFold*(state: var FoldState, line: int): bool =
  ## Close the fold at the given line. Returns true if a fold was closed.
  let idx = state.foldIndexAt(line)
  if idx.isSome:
    state.folds[idx.get].collapsed = true
    return true
  return false

proc toggleFold*(state: var FoldState, line: int): bool =
  ## Toggle the fold at the given line. Returns true if a fold was toggled.
  let idx = state.foldIndexAt(line)
  if idx.isSome:
    state.folds[idx.get].collapsed = not state.folds[idx.get].collapsed
    return true
  return false

proc deleteFold*(state: var FoldState, line: int): bool =
  ## Delete the fold containing the given line. Returns true if a fold was deleted.
  for i in 0 ..< state.folds.len:
    let fold = state.folds[i]
    if line >= fold.startLine and line <= fold.endLine:
      state.folds.delete(i)
      return true
  return false

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
    if fold.collapsed and line >= fold.startLine and line <= fold.endLine:
      return min(fold.endLine + 1, maxLine)
  return line

proc getPrevVisibleLine*(state: FoldState, line: int): int =
  ## Get the previous visible line (skip over collapsed folds)
  ## If line is at the end of a collapsed fold, jump to the start line
  for fold in state.folds:
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
    let firstLine = b.getLine(fold.startLine)
    # Use character-based slicing for UTF-8 safety
    let firstLineCharLen = firstLine.charLen
    let preview =
      if firstLineCharLen > 40:
        firstLine.runeSubStr(0, 40) & "..."
      else:
        firstLine
    result = "+-- " & $lineCount & " lines: " & preview
