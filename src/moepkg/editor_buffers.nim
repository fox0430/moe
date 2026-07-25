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

## Buffer-list management for the editor: the global buffer list, per-window
## tab lists, buffer switching (:b/:bnext/:bprev/...), deletion, terminal
## teardown, and file opening into buffers (:e and friends).

import std/[strutils, strformat, options, os, tables]

import pkg/results

import
  types/editor_types,
  editor_window,
  editor_window_state,
  git_cache,
  editorconfig_helper,
  highlight,
  highlight_config,
  logger,
  buffer,
  window_manager,
  lsp_integration

proc deleteBufferAt*(e: Editor, idx: int) =
  ## Remove the buffer at `idx` from `e.buffers` and drop it from
  ## `bufferIdIndex`. Use this instead of `e.buffers.delete`.
  ## Also sends LSP didClose so a later re-open doesn't collide with stale
  ## server state (no-op for non-file buffers and untracked paths).
  if e.lsp != nil:
    discard e.lsp.onBufferClose(e.buffers[idx])
  e.deleteBufferAtNoLsp(idx)

proc findBufferByPath*(e: Editor, path: string): int =
  ## Find a buffer in the buffer list by its file path
  ## Returns the buffer index (0-based) or -1 if not found
  ## Paths are compared by their normalized absolute form so a buffer opened
  ## under a differently-spelled path (relative, `..` segments, trailing slash)
  ## still matches — mirrors `sameFilePath` used by the navigation paths.
  let normPath = normalizedPath(absolutePath(path))
  for i, buf in e.buffers:
    if buf.filePath.isSome and normalizedPath(absolutePath(buf.filePath.get)) == normPath:
      return i
  return -1

proc addBufferToWindowList*(e: Editor, buffer: TextBuffer) =
  ## Append `buffer.id` to the active window's per-window tab list if absent.
  if buffer.id notin e.activeWindow.bufferIds:
    e.activeWindow.bufferIds.add(buffer.id)

proc applyBufferMode*(e: Editor, buf: TextBuffer) =
  ## Re-derive the active window's mode/modeState from the buffer being
  ## activated. Tab switches reuse this so a Terminal session can be resumed
  ## by selecting its tab. The PTY itself is owned by `e.terminalStates`,
  ## so leaving a Terminal tab never calls `cleanup()`.
  let win = e.activeWindow
  # Drop any prior buffer-swap mode state (Filer, BufferManager, ...) so its
  # `originalBuffer` doesn't leak across the tab switch. Terminal state is
  # owned by `e.terminalStates` and must NOT be cleaned up here — `cleanup()`
  # would kill the PTY of a session the user wants to resume later.
  #
  # `originalBuffer` is nulled before `clearModeState` on purpose: the normal
  # lifecycle restores it into `win.buffer`, but we're explicitly switching
  # to `buf` (a tab pick), so the saved reference would be wrong. Nulling
  # first turns the restore step into a no-op while still letting
  # `clearModeState` run its mode-specific cleanup and reset the variant.
  let wasSpecialMode =
    win.modeState.kind != mskNone and win.modeState.kind != mskTerminal
  if wasSpecialMode:
    win.originalBuffer = nil
    win.clearModeState(win.mode)

  if e.terminalStates.hasKey(buf.id):
    win.modeState = ModeState(kind: mskTerminal, terminal: e.terminalStates[buf.id])
    e.setMode(EditorMode.Terminal)
  elif win.mode == EditorMode.Terminal:
    # Leaving a Terminal tab: clearModeState was skipped above (PTY ownership
    # lives in `terminalStates`), so reset the variant manually here.
    win.modeState = ModeState(kind: mskNone)
    e.setMode(EditorMode.Normal)
  elif wasSpecialMode:
    # clearModeState resets modeState but leaves `win.mode` untouched —
    # explicitly drop it back to Normal so the tab switch doesn't leave the
    # window stuck in Filer/BufferManager/etc.
    e.setMode(EditorMode.Normal)

proc activateBufferInWindow(e: Editor, targetBuffer: TextBuffer) =
  ## Point the active window at `targetBuffer` and reset its viewport/cursor.
  ## No-op when the window is already showing this buffer (preserves position).
  ## Shared tail of switchToBufferByIndex/switchToWindowBuffer — the callers
  ## differ only in how they resolve `targetBuffer`.
  if e.activeWindow.buffer == targetBuffer:
    return

  e.activeWindow.buffer = targetBuffer
  e.activeWindow.cursor = BufferPosition(line: 0, column: 0)
  e.activeWindow.viewport.resetViewportTop()
  e.activeWindow.viewport.leftColumn = 0
  e.applyBufferMode(targetBuffer)

  # syncActiveWindow also updates state.windowDisplay.currentBufferId for the Jump List anchor.
  e.syncActiveWindow()
  e.setActiveWindowScreenCursor(e.activeWindow)

proc switchToBufferByIndex*(e: Editor, index: int) =
  ## Switch the current window to display the buffer at the given index in e.buffers.
  ## Also registers the target buffer in the active window's per-window tab list.
  if index < 0 or index >= e.buffers.len:
    return

  let targetBuffer = e.buffers[index]

  # Register in window-local tab list regardless (so :b <name> from another tab
  # makes the buffer show up in this window's tabs).
  e.addBufferToWindowList(targetBuffer)

  e.activateBufferInWindow(targetBuffer)

proc currentBufferIndex*(e: Editor): int =
  ## Get the position of the active buffer in e.buffers.
  ## Returns -1 if not found.
  e.bufferIndexById(e.activeBuffer().id)

proc windowBufferIndex*(e: Editor): int =
  ## Index of the active buffer inside the active window's tab list.
  ## Returns -1 if the active buffer is not registered with this window.
  let id = e.activeWindow.buffer.id
  for i, bid in e.activeWindow.bufferIds:
    if bid == id:
      return i
  return -1

proc switchToWindowBuffer*(e: Editor, windowIndex: int) =
  ## Switch to a buffer in the active window's tab list by tab position.
  ## Silently drops the call if the entry is stale (buffer was deleted).
  if windowIndex < 0 or windowIndex >= e.activeWindow.bufferIds.len:
    return

  let id = e.activeWindow.bufferIds[windowIndex]
  let bufOpt = e.bufferById(id)
  if bufOpt.isNone:
    # Stale entry — buffer was bdelete'd; drop it.
    e.activeWindow.bufferIds.delete(windowIndex)
    return

  e.activateBufferInWindow(bufOpt.get)

proc closeTerminalBuffer*(e: Editor, bufId: BufferId) =
  ## Tear down a Terminal session: free its PTY, drop the buffer from all
  ## bookkeeping, and move every window that was displaying it to a sibling
  ## tab (or to a fresh No Name buffer when the window has no tabs left).
  ## No-op when `bufId` is not a registered terminal — non-terminal buffers
  ## must go through `deleteCurrentBuffer`/`removeBufferAt` instead.
  if not e.terminalStates.hasKey(bufId):
    return
  e.terminalStates[bufId].cleanup()
  e.terminalStates.del(bufId)

  # Snapshot which windows had this buffer active, plus their tab-list index,
  # before we mutate the lists.
  var followups: seq[tuple[winIdx: int, tabIdx: int]] = @[]
  for wi, w in e.windowManager.windows:
    if w.buffer != nil and w.buffer.id == bufId:
      var idx = -1
      for i, bid in w.bufferIds:
        if bid == bufId:
          idx = i
          break
      followups.add((wi, idx))

  e.pruneBufferIdFromAllWindows(bufId)
  let bidx = e.bufferIndexById(bufId)
  if bidx >= 0:
    # Mirror removeBufferAt: evict before delete so the buffer's pointer can't
    # alias a future buffer via a leftover cache entry.
    e.state.git.evictGitCacheForBuffer(e.buffers[bidx])
    e.deleteBufferAt(bidx)

  let prevActive = e.windowManager.activeWindowIndex
  for fu in followups:
    e.windowManager.activeWindowIndex = fu.winIdx
    let w = e.activeWindow
    if w.bufferIds.len > 0:
      # Prefer the tab that took the closed terminal's slot (formerly
      # tabIdx+1); fall back to the previous tab when the closed terminal
      # was the rightmost. Matches Vim's `:bd` "next-then-prev" preference.
      # The `tabIdx < 0` branch is defensive — it only triggers if the
      # window displayed the terminal without registering it in bufferIds,
      # which shouldn't happen but would otherwise leave `w.buffer`
      # dangling at the just-deleted buffer.
      let newIdx =
        if fu.tabIdx >= 0 and fu.tabIdx < w.bufferIds.len:
          fu.tabIdx
        else:
          w.bufferIds.len - 1
      e.switchToWindowBuffer(newIdx)
    else:
      let blank = newTextBuffer("")
      e.addBuffer(blank)
      e.addBufferToWindowList(blank)
      w.buffer = blank
      w.cursor = BufferPosition(line: 0, column: 0)
      w.viewport.resetViewportTop()
      w.viewport.leftColumn = 0
      w.modeState = ModeState(kind: mskNone)
      w.mode = EditorMode.Normal
      e.setMode(EditorMode.Normal)
      e.syncActiveWindow()
      e.setActiveWindowScreenCursor(w)
  e.windowManager.activeWindowIndex = prevActive
  # Followup loop may have re-synced `state.windowDisplay.currentBufferId`
  # to the last visited window. Re-anchor it to the (restored) active one.
  e.syncActiveWindow()

proc cleanupAllTerminals*(e: Editor) =
  ## Tear down every live Terminal session's PTY on editor exit/crash.
  ##
  ## `closeTerminalBuffer` only runs on an explicit tab close, so any shell
  ## spawned by `:terminal` and still open when moe quits or crashes would
  ## otherwise be reaped only via the kernel closing the master fd at process
  ## exit — which merely raises SIGHUP on the foreground process group. A shell
  ## (or foreground child) that ignores SIGHUP, was disowned, or sits in its
  ## own process group survives as an orphan, and the fd/zombie linger.
  ##
  ## `cleanup()` closes each PTY's master fd and sends SIGTERM to (and reaps)
  ## the shell deterministically. Unlike `closeTerminalBuffer` this does not
  ## rewire windows or buffer lists: the editor is exiting, so only the OS
  ## resources need releasing. Idempotent and safe on an empty map.
  for termState in e.terminalStates.values:
    termState.cleanup()
  e.terminalStates.clear()

proc switchToNextBuffer*(e: Editor) =
  ## Switch to the next buffer in the active window's tab list (:bnext).
  if e.activeWindow.bufferIds.len <= 1:
    e.state.statusMessage = "E88: There is only one buffer"
    return

  # If the active buffer isn't registered in this window's tab list (-1),
  # treat "next" as a jump to the first tab. Mirrors prev's wrap behavior for
  # the orphan (curIdx<0) case — prev wraps to last, next wraps to first.
  let curIdx = e.windowBufferIndex()
  let nextIdx =
    if curIdx < 0:
      0
    else:
      (curIdx + 1) mod e.activeWindow.bufferIds.len
  e.switchToWindowBuffer(nextIdx)
  e.state.statusMessage = ""

proc switchToPrevBuffer*(e: Editor) =
  ## Switch to the previous buffer in the active window's tab list (:bprev).
  if e.activeWindow.bufferIds.len <= 1:
    e.state.statusMessage = "E88: There is only one buffer"
    return

  # curIdx < 0 (active buffer not in tab list) also falls into this branch and
  # wraps to the last tab — symmetric with switchToNextBuffer's curIdx<0 path.
  let curIdx = e.windowBufferIndex()
  let prevIdx =
    if curIdx <= 0:
      e.activeWindow.bufferIds.len - 1
    else:
      curIdx - 1
  e.switchToWindowBuffer(prevIdx)
  e.state.statusMessage = ""

proc switchToFirstBuffer*(e: Editor) =
  ## Switch to the first buffer in the active window's tab list (:bfirst).
  if e.activeWindow.bufferIds.len <= 1:
    e.state.statusMessage = "Already at first buffer"
    return

  if e.windowBufferIndex() == 0:
    e.state.statusMessage = "Already at first buffer"
    return

  e.switchToWindowBuffer(0)
  e.state.statusMessage = ""

proc switchToLastBuffer*(e: Editor) =
  ## Switch to the last buffer in the active window's tab list (:blast).
  if e.activeWindow.bufferIds.len <= 1:
    e.state.statusMessage = "Already at last buffer"
    return

  let lastIdx = e.activeWindow.bufferIds.len - 1
  if e.windowBufferIndex() == lastIdx:
    e.state.statusMessage = "Already at last buffer"
    return

  e.switchToWindowBuffer(lastIdx)
  e.state.statusMessage = ""

proc switchToBuffer*(e: Editor, arg: string): bool =
  ## Switch to a buffer by number or name (:b N or :b name)
  ## Returns true if successful, false otherwise
  ## Uses the buffer list (not windows) like Vim

  logDebug("editor", "switchToBuffer called with arg: " & arg)
  logDebug("editor", "buffers.len: " & $e.buffers.len)
  # Log each buffer's path for debugging
  for i, buf in e.buffers:
    let path = if buf.filePath.isSome: buf.filePath.get else: "[No Name]"
    logDebug("editor", "  buffer[" & $i & "]: " & path)

  # Try to parse as a number first
  try:
    let bufNum = parseInt(arg)
    # Buffer numbers are 1-indexed in Vim
    let targetIndex = bufNum - 1

    logDebug(
      "editor", "Parsed buffer number: " & $bufNum & ", targetIndex: " & $targetIndex
    )

    if targetIndex < 0 or targetIndex >= e.buffers.len:
      e.state.statusMessage = "E86: Buffer " & $bufNum & " does not exist"
      logDebug("editor", "Buffer does not exist")
      return false

    let currentIdx = e.currentBufferIndex()
    logDebug("editor", "currentIdx: " & $currentIdx)
    if targetIndex == currentIdx:
      # Already at this buffer
      logDebug("editor", "Already at this buffer")
      return true

    # Switch to the buffer
    logDebug("editor", "Switching to buffer at index: " & $targetIndex)
    e.switchToBufferByIndex(targetIndex)
    e.state.statusMessage = ""
    return true
  except ValueError:
    discard # Not a number, try matching by name

  # Try to match by file name in buffer list
  for i, buf in e.buffers:
    if buf.filePath.isSome:
      let bufferPath = buf.filePath.get
      # Match against full path, file name, or partial match
      if bufferPath == arg or bufferPath.extractFilename == arg or
          bufferPath.contains(arg):
        let currentIdx = e.currentBufferIndex()
        if i == currentIdx:
          # Already at this buffer
          return true

        # Switch to the buffer
        e.switchToBufferByIndex(i)
        e.state.statusMessage = ""
        return true

  e.state.statusMessage = "E94: No matching buffer for " & arg
  return false

proc isBufferShared*(e: Editor, buffer: TextBuffer): bool =
  ## Check if the given buffer is shared across multiple windows
  ## Returns true if the buffer is open in more than one window
  for window in e.windowManager.windows:
    if window.buffer == buffer:
      if result:
        return true
      else:
        result = true

  # Buffer is not shared across multiple windows (0 or 1 window)
  return false

proc removeBufferAt*(e: Editor, idx: int): TextBuffer =
  ## Drop the buffer at `idx` from `e.buffers`, evict its git diff/branch cache
  ## entries, and prune its id from every window's per-window tab list. Returns
  ## the deleted `TextBuffer` ref so callers can still use it to identify which
  ## windows were displaying it.
  ##
  ## Caller is responsible for repointing those windows at a survivor buffer
  ## (see `redirectWindowsFromBuffer`); this proc does not touch
  ## `window.buffer`.
  result = e.buffers[idx]
  # Evict before removal so any in-flight async `git diff` is terminated and
  # the buffer's pointer can't alias a future buffer via leftover Table entries.
  e.state.git.evictGitCacheForBuffer(result)
  e.deleteBufferAt(idx)
  e.pruneBufferIdFromAllWindows(result.id)

proc redirectWindowsFromBuffer*(
    e: Editor, deletedBuffer: TextBuffer, newBuf: TextBuffer
) =
  ## Switch every window currently showing `deletedBuffer` to `newBuf`,
  ## register `newBuf.id` in those windows' tab lists, and reset their cursor
  ## and viewport.
  for window in e.windowManager.windows:
    if window.buffer == deletedBuffer:
      window.buffer = newBuf
      if newBuf.id notin window.bufferIds:
        window.bufferIds.add(newBuf.id)
      window.cursor = BufferPosition(line: 0, column: 0)
      window.viewport.resetViewportTop()
      window.viewport.leftColumn = 0

proc deleteCurrentBuffer*(e: Editor) =
  ## Delete the active buffer from the buffer list (Vim `:bd` semantics).
  ## Every window that was showing it switches to another buffer — windows
  ## themselves stay open. If this was the only buffer, a fresh empty
  ## `[No Name]` buffer takes its place.
  ##
  ## The modified-buffer check is the caller's responsibility (handled in
  ## `executeBufferDelete`).
  let activeBufId = e.activeBuffer().id
  if e.terminalStates.hasKey(activeBufId):
    # Terminal sessions need PTY cleanup; delegate to the dedicated path
    # so the state map stays in sync.
    e.closeTerminalBuffer(activeBufId)
    return

  let bufferIndex = e.bufferIndexById(activeBufId)
  if bufferIndex < 0:
    return
  let deletedBuffer = e.removeBufferAt(bufferIndex)

  let newBuf =
    if e.buffers.len == 0:
      # Last buffer just went away — give the active window a fresh `[No Name]`
      # buffer. If `enew` fails here we're past the irreversible removal:
      # windows keep their refs to the deleted buffer alive but it's no longer
      # reachable via id. Surface the error and bail; subsequent input will
      # operate on the orphan buffer until the user reloads.
      let enewResult = e.enew()
      if enewResult.isErr:
        logError("editor", "Enew failed after buffer delete: " & enewResult.error)
        e.state.statusMessage = "Error: " & enewResult.error
        return
      # `enew` has already pointed the active window at the new buffer, so the
      # redirect below is a no-op for it but still catches any other windows
      # that were on the deleted buffer.
      e.activeBuffer()
    else:
      # Same index now refers to what used to be the next buffer, clamped.
      e.buffers[min(bufferIndex, e.buffers.len - 1)]

  e.redirectWindowsFromBuffer(deletedBuffer, newBuf)
  # `syncActiveWindow` realigns `state.windowDisplay.currentBufferId` to the active window's
  # buffer, so no explicit currentBufferId reassignment is needed here.
  e.syncActiveWindow()
  e.setActiveWindowScreenCursor(e.activeWindow)

const MinNewWindowWidth* = 10
  ## Minimum width (in columns) required when spawning a new split window.

proc loadOrCreateBuffer*(e: Editor, path: string): Result[TextBuffer, string] =
  ## Return the buffer for `path`: reuse an existing one from the global
  ## buffer list, or create, initialise, and register a new buffer.
  ## New buffers are loaded from disk when the file exists, otherwise created
  ## empty with filePath preset (for saving later), then have EditorConfig and
  ## reserved-word highlighting applied.
  let existingIndex = e.findBufferByPath(path)
  if existingIndex >= 0:
    return ok(e.buffers[existingIndex])

  let newBuffer = newTextBuffer()
  # Seed the highlight cap before loadFile builds the first chunk, so the cap
  # is not changed afterwards (which would nil the progressive-load cache).
  newBuffer.applyHighlightCap(e.config)
  if fileExists(path):
    let loadResult = newBuffer.loadFile(path)
    if loadResult.isErr:
      return err(loadResult.error)
  else:
    newBuffer.filePath = some(path)
    newBuffer.language = detectLanguage(path)

  applyEditorConfigToBuffer(newBuffer, e.config)
  applyHighlightConfig(newBuffer, e.config)
  e.addBuffer(newBuffer)

  # Mirror loadFile's per-buffer initialisation (bookmarks, git diff, conflict
  # markers, LSP didOpen) so files reached via :e, the FileTree opener and
  # multi-file startup get the same setup as the first file. Shared with the
  # split startup path (registerSplitBuffer) so the file looks identical however
  # it is opened.
  e.initLoadedBuffer(newBuffer)
  ok(newBuffer)

proc editFile*(e: Editor, path: string): Result[(), string] =
  ## Load a file and switch to it (like :e in Vim)
  ## If the buffer already exists in the buffer list, switch to it
  ## If the file doesn't exist, create an empty buffer with the path set (new file)

  logDebug("editor", "editFile called with path: " & path)
  logDebug("editor", "Current buffers.len: " & $e.buffers.len)

  let bufferResult = e.loadOrCreateBuffer(path)
  if bufferResult.isErr:
    return err(bufferResult.error)

  let idx = e.findBufferByPath(path)
  e.switchToBufferByIndex(idx)
  logDebug("editor", "editFile completed, buffers.len: " & $e.buffers.len)
  ok(())

proc openFileInNewRightWindow*(e: Editor, path: string): Result[(), string] =
  ## Create a new editor window to the right of the currently active FileTree
  ## window and load the given file into it. Used when FileTree is the only
  ## window open.

  let ftWindow = e.activeWindow
  if ftWindow.mode != EditorMode.FileTree:
    return err("active window is not FileTree")

  let
    origWidth = ftWindow.viewport.width
    origX = ftWindow.viewport.x
    origY = ftWindow.viewport.y
    origHeight = ftWindow.viewport.height
    ftWidth =
      if ftWindow.fixedWidth.isSome:
        ftWindow.fixedWidth.get
      else:
        origWidth div 2
    newWidth = origWidth - ftWidth - WindowSeparatorWidth

  if newWidth < MinNewWindowWidth:
    return err("not enough space to open a new window")

  let bufferResult = e.loadOrCreateBuffer(path)
  if bufferResult.isErr:
    return err(bufferResult.error)
  let newBuffer = bufferResult.get

  # Shrink FileTree back to its fixed width and place the new window on its right
  ftWindow.viewport.width = ftWidth

  let newX = origX + ftWidth + WindowSeparatorWidth

  e.windowManager.deactivateAllWindows()

  let newWindow = EditorWindow(
    buffer: newBuffer,
    bufferIds: @[newBuffer.id],
    viewport: ViewPort(
      topLine: 0, leftColumn: 0, width: newWidth, height: origHeight, x: newX, y: origY
    ),
    cursor: BufferPosition(line: 0, column: 0),
    active: true,
    mode: EditorMode.Normal,
    wrapCountCache: WrapCountCache(),
  )

  let ftIndex = e.windowManager.activeWindowIndex
  e.windowManager.windows.insert(newWindow, ftIndex + 1)
  e.windowManager.activeWindowIndex = ftIndex + 1

  e.syncActiveWindow()
  e.setMode(EditorMode.Normal)
  e.state.previousMode = EditorMode.Normal

  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.setActiveWindowScreenCursor(e.activeWindow)

  ok(())

proc openAdditionalStartupFiles*(
    e: Editor, filePaths: openArray[string], readonly: bool
) =
  ## Open the extra command-line files (everything after the first, which
  ## loadFile already loaded into the active buffer). With auto-split each file
  ## opens in its own split window; otherwise each is registered as a separate
  ## buffer (like :badd) and joins the active window's tab list so :bnext/:bprev
  ## can reach it without switching away from the first file. Missing files are
  ## skipped. Sharing one loop keeps the split and no-split startup paths in sync.
  for i in 1 ..< filePaths.len:
    let filePath = filePaths[i]
    if not fileExists(filePath):
      continue

    if e.config.startUpFileOpen.autoSplit:
      let splitResult =
        case e.config.startUpFileOpen.splitType
        of stVertical:
          e.vsplit(some(filePath))
        of stHorizontal:
          e.hsplit(some(filePath))
      if splitResult.isErr:
        logError("moe", fmt"Failed to split for {filePath}: {splitResult.error}")
      elif readonly:
        e.activeBuffer().readOnly = true
    else:
      let bufResult = e.loadOrCreateBuffer(filePath)
      if bufResult.isErr:
        logError("moe", fmt"Failed to open {filePath}: {bufResult.error}")
      else:
        e.addBufferToWindowList(bufResult.get)
        if readonly:
          bufResult.get.readOnly = true
