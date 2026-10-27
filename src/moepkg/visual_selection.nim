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

## Visual selection.
##
## A window's selection is derived from its anchor, cursor and mode instead of
## being stored, so it cannot outlive the mode, lag the cursor or point into
## another buffer. Entering Visual from another mode puts the anchor on the
## cursor, in the mode setter so that every entry path does it; leaving it is a
## mode change (`leaveVisual`), and it ends when the window loses the focus or
## `:` is typed, so only the focused window ever holds an anchor. The anchor
## is not remapped through edits, so an edit the user did not make there (a
## server's `workspace/applyEdit`) can shift the text under it.
##
## A closed fold either end is in is covered whole as each command ends
## (`coverClosedFolds`), so what the window shows is what a command acts on.

import std/options

import types, modes, wanted_column
import buffer/[core, fold]

export visualKind, visualMode

proc visualSelection*(win: EditorWindow): VisualSelection =
  ## The window's selection; inactive outside the Visual modes.
  if not win.mode.isVisualAllMode:
    return VisualSelection(start: win.cursor, current: win.cursor)
  VisualSelection(
    start: win.clampedAnchor,
    current: win.cursor,
    active: true,
    kind: win.mode.visualKind,
    extendsToLineEnd: win.preferredColumn == LineEnd,
  )

proc selectVisualRange*(state: EditorState, anchor, focus: BufferPosition) =
  ## Select from `anchor` to `focus`, which the cursor moves to. The window must
  ## already be in Visual: entering it would reset the anchor. The selection no
  ## longer follows the line end `$` took it to.
  state.activeWindow.visualAnchor = anchor
  state.cursor = focus
  state.preferredColumn = -1

proc enterVisual*(
    state: EditorState, kind: VisualSelectionKind, anchor, focus: BufferPosition
) =
  ## Switch to the Visual mode of `kind` and select `anchor`..`focus`.
  if not state.mode.isVisualAllMode:
    state.previousMode = state.mode
  state.mode = kind.visualMode
  state.selectVisualRange(anchor, focus)

proc coveredEnds*(
    buffer: TextBuffer, first, last: BufferPosition
): tuple[first, last: BufferPosition] =
  ## `first`..`last` with a closed fold either end is in covered whole: the
  ## start to its first line's start, the end past its last line's end, as
  ## Vim's foldAdjustVisual.
  result = (first, last)
  if buffer.isNil or buffer.len == 0:
    return
  let firstFold = buffer.foldState.getCollapsedFoldAt(first.line)
  if firstFold.isSome:
    result.first = BufferPosition(line: firstFold.get.startLine, column: 0)
  let lastFold = buffer.foldState.getCollapsedFoldAt(last.line)
  if lastFold.isSome:
    let line = min(lastFold.get.endLine, buffer.len - 1)
    result.last = BufferPosition(line: line, column: buffer.getLineLen(line))

proc coveredSelection*(win: EditorWindow): VisualSelection =
  ## The window's selection with a closed fold either end is in covered whole.
  result = win.visualSelection
  if not result.active:
    return
  let anchorFirst = result.start <= result.current
  let (first, last) =
    if anchorFirst:
      win.buffer.coveredEnds(result.start, result.current)
    else:
      win.buffer.coveredEnds(result.current, result.start)
  if anchorFirst:
    (result.start, result.current) = (first, last)
  else:
    (result.start, result.current) = (last, first)

proc coverClosedFolds*(state: EditorState) =
  ## Move the selection's ends to cover a closed fold either end is in, as
  ## Vim's foldAdjustVisual does after each command. The column vertical moves
  ## want stays.
  let win = state.activeWindow
  let covered = win.coveredSelection
  if not covered.active:
    return
  if covered.start != win.clampedAnchor:
    win.visualAnchor = covered.start
  state.scrollCursor(covered.current)

proc operandSelection*(state: EditorState): VisualSelection =
  ## The selection an operator acts on: covered, as a fold may have closed
  ## since the last command ended.
  state.activeWindow.coveredSelection
