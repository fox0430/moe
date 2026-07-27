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

## Editor type definitions
## This module contains the core Editor type and related types used across editor modules.

import std/[options, tables]

import ../[types, motion, commands, command_registry, modes, quick_run_utils]
import ../key_bindings except Command
import ../command_handlers/handler_types
import ../buffer/core as buffer_core
import ../command_line/types as command_line_types
import ../key_router/types as key_router_types
import
  background_process_types, persist_types, virtual_text_types, command_config_types,
  config_types, window_manager_types, lsp_integration_types

export
  types, motion, commands, command_registry, modes, handler_types,
  background_process_types, persist_types, virtual_text_types, command_line_types,
  command_config_types, key_router_types, config_types, buffer_core,
  window_manager_types, lsp_integration_types

type
  ScreenSize* = object
    width*, height*: int
    prevWidth*, prevHeight*: int

  Editor* = ref object
    state*: EditorState
    screenSize*: ScreenSize
    motionController*: MotionController
    commandRegistry*: CommandRegistry
    keyBindingRegistry*: KeyBindingRegistry
    keyRouter*: KeyRouter
      ## Single entry point for key-dispatch decisions. Borrows the
      ## accumulator state from `keyBindingRegistry`; a future phase may
      ## move that physical storage into the router itself.
    commandLineParser*: CommandLineParser
    commandConfig*: CommandConfig
    handlerManager*: HandlerManager
    windowManager*: EditorWindowManager
    buffers*: seq[TextBuffer]
    bufferIdIndex*: Table[BufferId, TextBuffer]
      ## O(1) lookup table from BufferId to TextBuffer, kept in sync with
      ## `buffers` via `addBuffer` / `deleteBufferAt`. Treat as derived state —
      ## never mutate directly.
    config*: EditorConfig
    lsp*: LspIntegration
    lastLspContentVersions*: Table[BufferId, int]
      ## Per-buffer contentVersion at the time of the last LSP didChange
      ## notification. contentVersion is monotonic (never rewinds on undo or
      ## reload), so unlike changeSeq it cannot collide across an undo + edit
      ## and mask an unsynced state. Keyed per buffer: a single shared value
      ## would let one buffer's version mask unsynced changes in another.
    cursorPositions*: Table[string, CursorPositionEntry]
    savedBookmarks*: Table[string, seq[int]]
    runningBackgroundProcesses*: seq[BackgroundProcess]
    runningQuickRunProcesses*: seq[QuickRunProcess]
      ## In-flight QuickRun processes, tracked separately from
      ## `runningBackgroundProcesses` because they own temporary files (temp
      ## source + build artifacts) that must be removed on editor exit/crash.
      ## Cleaned up via `cleanupQuickRunProcesses` on shutdown/emergency.
    terminalStates*: Table[BufferId, TerminalState]
      ## Live Terminal sessions keyed by their buffer id. The window's
      ## `modeState` is rebuilt from this table on tab switches so a
      ## terminal can be backgrounded by moving to another tab and resumed
      ## later.

  RenderContext* = object
    ## Context for rendering operations to reduce parameter passing
    cursorLine*: int
    cursorCol*: int
    cursorDisplayCol*: int ## Screen column of cursor (accounting for tabs/wide chars)
    hasSelection*: bool
    selStart*: BufferPosition
    selEnd*: BufferPosition
    windowMode*: EditorMode ## Mode of the window being rendered
    windowRightEdge*: int ## Absolute screen X of window's right edge
    isActiveWindow*: bool ## Whether the window being rendered is the active one
    virtualTextProviders*: seq[VirtualTextProvider]
      ## Feature-agnostic suppliers of virtual text (inlay hints, etc.)

  IndentInfo* = object
    ## Cached indentation analysis for a line to avoid O(n²) performance
    leadingWhitespaceEnd*: int
    hasContent*: bool

# Basic accessor procedures
proc activeWindow*(e: Editor): EditorWindow {.inline.} =
  ## Get the currently active window
  e.windowManager.windows[e.windowManager.activeWindowIndex]

proc activeBuffer*(e: Editor): TextBuffer {.inline.} =
  ## The active window's buffer. Window-derived (we always have at least one
  ## window) so there is no separate cached field that could drift out of sync
  ## after a window switch/split.
  e.activeWindow.buffer

proc viewport*(e: Editor): ViewPort {.inline.} =
  ## The active window's viewport. Window-derived, like `activeBuffer`. Because
  ## `ViewPort` is a `ref object`, the returned handle aliases the active
  ## window's viewport, so mutating fields through it (e.g.
  ## `e.viewport.topLine = 0`) updates the window in place — there is no
  ## separate cached field to keep in sync via `syncActiveWindow`.
  e.activeWindow.viewport

proc bufferById*(e: Editor, id: BufferId): Option[TextBuffer] =
  ## Look up a buffer by its BufferId. O(1) via `bufferIdIndex`.
  if e.bufferIdIndex.hasKey(id):
    some(e.bufferIdIndex[id])
  else:
    none(TextBuffer)

proc bufferIndexById*(e: Editor, id: BufferId): int =
  ## Get the index of the buffer with the given BufferId in e.buffers.
  ## Returns -1 if not found.
  ## O(1) on miss (early-out via `bufferIdIndex`), O(n) on hit — positions in
  ## `e.buffers` are unstable across deletes so we don't cache them; callers
  ## that only need the buffer ref should use `bufferById` instead.
  if not e.bufferIdIndex.hasKey(id):
    return -1
  for i, buf in e.buffers:
    if buf.id == id:
      return i
  return -1

proc addBuffer*(e: Editor, buf: TextBuffer) =
  ## Append `buf` to `e.buffers` and register it in `bufferIdIndex`.
  ## Use this instead of `e.buffers.add` so the lookup table stays in sync.
  e.buffers.add(buf)
  e.bufferIdIndex[buf.id] = buf

proc deleteBufferAtNoLsp*(e: Editor, idx: int) =
  ## Remove the buffer at `idx` from `e.buffers` and drop it from
  ## `bufferIdIndex`. Use `deleteBufferAt` (in editor_buffers) instead, which
  ## also sends LSP didClose. This raw form is exposed only so the LSP-aware
  ## wrapper can call it without duplicating index/table bookkeeping.
  let buf = e.buffers[idx]
  let id = buf.id
  e.buffers.delete(idx)
  e.bufferIdIndex.del(id)
  e.lastLspContentVersions.del(id)

proc pruneBufferIdFromAllWindows*(e: Editor, id: BufferId) =
  ## Remove `id` from every window's per-window tab list (`bufferIds`).
  ## Call after removing a buffer from `e.buffers` so per-window tabs don't
  ## hold stale references.
  for w in e.windowManager.windows:
    var i = 0
    while i < w.bufferIds.len:
      if w.bufferIds[i] == id:
        w.bufferIds.delete(i)
      else:
        inc i

proc currentMode*(e: Editor): EditorMode {.inline.} =
  ## Get the current mode from the active window
  e.activeWindow.mode

proc cursor*(e: Editor): BufferPosition {.inline.} =
  ## Get the cursor position from the active window
  e.activeWindow.cursor

proc `cursor=`*(e: Editor, pos: BufferPosition) {.inline.} =
  ## Set the cursor position in the active window
  e.activeWindow.cursor = pos

proc setMode*(e: Editor, mode: EditorMode) {.inline.} =
  ## Set the current mode in the active window
  e.activeWindow.mode = mode

# Editor-based config pull-type accessors. State-based ones live in types.nim.

template flag2(name: untyped, T: typedesc, s1, f: untyped) =
  proc name*(e: Editor): T =
    e.state.name

  proc `name=`*(e: Editor, v: T) =
    e.config.s1.f = v

template flag3(name: untyped, T: typedesc, s1, s2, f: untyped) =
  proc name*(e: Editor): T =
    e.state.name

  proc `name=`*(e: Editor, v: T) =
    e.config.s1.s2.f = v

flag2(showTabLine, bool, tabLine, enable)
flag2(showStatusLine, bool, standard, statusLine)
flag2(multiStatusLine, bool, statusLine, multipleStatusLine)
flag2(showLineNumbers, bool, standard, number)
flag2(relativeLineNumbers, bool, standard, relativeNumber)
flag2(showCursorLine, bool, highlight, currentLine)
flag2(showCursorColumn, bool, highlight, currentColumn)
flag2(showSyntax, bool, standard, syntax)
flag2(showIndentationLines, bool, standard, indentationLines)
flag2(showSidebar, bool, standard, sidebar)
flag2(scrollbar, bool, standard, scrollbar)
flag2(scrollbarWidth, int, standard, scrollbarWidth)
flag2(showModifiedLines, bool, standard, showModifiedLines)
flag2(showGitDiff, bool, git, showChangedLine)
flag2(showSyntaxChecker, bool, syntaxChecker, enable)
flag3(showCodeLens, bool, lsp, codeLens, enable)
flag3(showDocumentHighlight, bool, lsp, documentHighlight, enable)
flag3(showInlayHint, bool, lsp, inlayHint, enable)
flag2(lineWrap, bool, standard, lineWrap)
flag2(softTabStop, int, standard, softTabStop)

# tabStop / shiftWidth / expandTab: delegate to EditorState so the per-buffer
# .editorconfig override is updated alongside the global config, matching the
# custom setters in types.nim.
proc tabStop*(e: Editor): int =
  e.state.tabStop

proc `tabStop=`*(e: Editor, v: int) =
  e.state.tabStop = v

proc shiftWidth*(e: Editor): int =
  e.state.shiftWidth

proc `shiftWidth=`*(e: Editor, v: int) =
  e.state.shiftWidth = v

proc expandTab*(e: Editor): bool =
  e.state.expandTab

proc `expandTab=`*(e: Editor, v: bool) =
  e.state.expandTab = v

flag2(autoIndent, bool, standard, autoIndent)
flag2(smartIndent, bool, standard, smartIndent)
flag2(autoCloseParen, bool, standard, autoCloseParen)
flag2(autoDeleteParen, bool, standard, autoDeleteParen)
flag2(bracketSplit, BracketSplitMode, standard, bracketSplit)
