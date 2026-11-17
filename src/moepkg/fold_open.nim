## When a closed fold opens at the cursor: Vim's default 'foldopen', where a
## command a typed key runs with no operator waiting opens the folds it takes
## the cursor into, and Insert and Replace, which open the cursor line's fold
## when they begin and when text is typed.

import std/options

import types, modes
import buffer/[core, fold]

proc opensFolds*(state: EditorState): bool =
  state.keyTyped and state.pendingInput.pendingOperator.isNone

proc openFoldsAt(state: EditorState, buffer: TextBuffer, line: int) =
  if buffer.foldState.openFoldsInRange(line, line):
    state.activeWindow.noteFoldOpened()

func typedJoin*(state: EditorState, join: FoldJoin): FoldJoin =
  ## `join` while typing, as Vim's foldMarkAdjust joins only in Insert.
  if state.mode in {EditorMode.Insert, EditorMode.Replace}: join else: fjNone

proc anchorEdits*(state: EditorState, buffer: TextBuffer) =
  buffer.editAnchor = some(EditAnchor(line: state.cursor.line))

proc dropEditAnchor*(buffer: TextBuffer) =
  buffer.editAnchor = none(EditAnchor)

proc anchorUnkeyedEdits*(state: EditorState, buffer: TextBuffer): bool =
  ## Anchor the edits made in Insert or Replace to the active window's buffer
  ## with no key's anchor, as a script's, so `openFoldsOfEdits` opens their folds as a key's; true when it
  ## did.
  if buffer.editAnchor.isNone and buffer == state.activeWindow.buffer and
      state.mode in {EditorMode.Insert, EditorMode.Replace}:
    state.anchorEdits(buffer)
    return true

proc openFoldsOfEdits*(state: EditorState, buffer: TextBuffer) =
  ## When the buffer changed since `anchorEdits`, open the closed folds on the
  ## line the cursor was on, moved with the text, and on the cursor line, as
  ## Vim's edit() does when text is typed in Insert or Replace: so a split
  ## opens the fold of the line split, but an edit away from the cursor none.
  let anchor = buffer.editAnchor
  buffer.dropEditAnchor()
  if anchor.isSome and anchor.get.edited:
    if anchor.get.line >= 0:
      state.openFoldsAt(buffer, anchor.get.line)
    state.openFoldsAt(buffer, state.cursor.line)

proc openCursorLineFolds*(state: EditorState, buffer: TextBuffer) =
  state.openFoldsAt(buffer, state.cursor.line)

proc openCursorLineFolds*(state: EditorState) =
  state.openCursorLineFolds(state.activeWindow.buffer)

proc openCursorFolds*(state: EditorState) =
  ## Open the closed folds the cursor is in, as Vim's foldOpenCursor, when
  ## `opensFolds`.
  if state.opensFolds:
    state.openCursorLineFolds()

proc openFoldsForTypingMotion*(state: EditorState, buffer: TextBuffer, motion: Motion) =
  ## Insert and Replace open the fold on a sideways move, 'foldopen' hor, which
  ## covers FirstLine and LastLine as it does Vim's <C-Home> and <C-End>.
  const Sideways = {
    Motion.Left, Motion.Right, Motion.Home, Motion.End, Motion.WordForward,
    Motion.WordBackward, Motion.WideWordForward, Motion.WideWordBackward,
    Motion.FirstLine, Motion.LastLine,
  }
  if motion in Sideways and state.opensFolds:
    state.openCursorLineFolds(buffer)
