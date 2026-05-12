## Shared test helpers for handler-dispatch tests.

import ../src/moepkg/buffer
import ../src/moepkg/types
import ../src/moepkg/window_manager
import ../src/moepkg/key_bindings
import ../src/moepkg/key_router
from ../src/moepkg/editor_types import Editor

proc createTestEditor*(
    buf: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keyBindingRegistry: KeyBindingRegistry = nil,
): Editor =
  ## Wrap the supplied buffer/state/viewport into a minimal Editor with a
  ## single active window so handler dispatch tests can run against the
  ## Editor-based API.
  ##
  ## `keyBindingRegistry` defaults to a fresh empty registry. Tests that
  ## exercise runtime mappings should pass the manager's own registry here so
  ## the embedded `KeyRouter` sees the same mapping table.
  state.activeWindow.buffer = buf
  let registry =
    if keyBindingRegistry.isNil:
      newKeyBindingRegistry()
    else:
      keyBindingRegistry
  Editor(
    textBuffer: buf,
    state: state,
    viewport: viewport,
    windowManager:
      EditorWindowManager(windows: @[state.activeWindow], activeWindowIndex: 0),
    keyBindingRegistry: registry,
    keyRouter: newKeyRouter(registry, TimeoutPolicy(timeoutlen: 1000, enabled: true)),
  )
