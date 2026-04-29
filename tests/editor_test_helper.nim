## Shared test helpers for handler-dispatch tests.

import ../src/moepkg/buffer
import ../src/moepkg/types
import ../src/moepkg/window_manager
from ../src/moepkg/editor_types import Editor

proc createTestEditor*(
    buf: TextBuffer, state: EditorState, viewport: ViewPort
): Editor =
  ## Wrap the supplied buffer/state/viewport into a minimal Editor with a
  ## single active window so handler dispatch tests can run against the
  ## Editor-based API.
  state.activeWindow.buffer = buf
  Editor(
    textBuffer: buf,
    state: state,
    viewport: viewport,
    windowManager:
      EditorWindowManager(windows: @[state.activeWindow], activeWindowIndex: 0),
  )
