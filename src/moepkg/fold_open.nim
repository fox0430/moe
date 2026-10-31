## Vim's default 'foldopen': a command a typed key runs with no operator
## waiting opens the closed folds it takes the cursor into.

import std/options

import types
import buffer/[core, fold]

proc opensFolds*(state: EditorState): bool =
  state.keyTyped and state.pendingInput.pendingOperator.isNone

proc openCursorFolds*(state: EditorState) =
  ## Open the closed folds the cursor is in, as Vim's foldOpenCursor, when
  ## `opensFolds`.
  if state.opensFolds:
    let line = state.cursor.line
    if state.activeWindow.buffer.foldState.openFoldsInRange(line, line):
      state.activeWindow.noteFoldOpened()
