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
## What the window shows is `visualSelection(win)`; what a command acts on is
## `operandSelection`, which covers closed folds whole.

import types, modes
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
  )

proc selectVisualRange*(state: EditorState, anchor, focus: BufferPosition) =
  ## Select from `anchor` to `focus`, which the cursor moves to. The window must
  ## already be in Visual: entering it would reset the anchor.
  state.activeWindow.visualAnchor = anchor
  state.cursor = focus

proc enterVisual*(
    state: EditorState, kind: VisualSelectionKind, anchor, focus: BufferPosition
) =
  ## Switch to the Visual mode of `kind` and select `anchor`..`focus`.
  if not state.mode.isVisualAllMode:
    state.previousMode = state.mode
  state.mode = kind.visualMode
  state.selectVisualRange(anchor, focus)

proc operandSelection*(win: EditorWindow, buffer: TextBuffer): VisualSelection =
  ## The selection an operator acts on. A closed fold either end lies in is
  ## covered whole, and a whole fold is whole lines, so the selection becomes
  ## linewise. The window's own selection is left alone.
  result = win.visualSelection
  if not result.active:
    return
  let
    lo = min(result.start.line, result.current.line)
    hi = max(result.start.line, result.current.line)
  if not buffer.foldState.endsInCollapsedFold(lo, hi):
    return
  let snapped = buffer.foldState.snapRangeToFolds(lo, hi)
  result.kind = vskLine
  result.start = BufferPosition(line: snapped.startLine, column: 0)
  result.current = BufferPosition(line: snapped.endLine, column: 0)

proc operandSelection*(state: EditorState, buffer: TextBuffer): VisualSelection =
  state.activeWindow.operandSelection(buffer)
