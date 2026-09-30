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

import std/[strutils, strformat, options, os]

when not defined(moe.embedded):
  import std/tables

import pkg/results

import
  types/editor_types,
  editor_mode,
  editor_window,
  editor_window_tab,
  viewer_mode,
  git_cache,
  editorconfig_helper,
  highlight,
  highlight_config,
  logger,
  buffer,
  lsp_integration

when not defined(moe.embedded):
  import terminal_mode

type OpenBufferInfo* = object
  ## Frontend-neutral information about a buffer in the active window.
  id*: BufferId
  title*: string
  filePath*: Option[string]
  modified*: bool
  readOnly*: bool
  active*: bool

proc bufferTitle(buffer: TextBuffer): string =
  ## Title for a tab line: the last path component when the buffer has a path.
  buffer.canonicalLabel(baseNameOnly = true)

proc toOpenBufferInfo(buffer, activeBuffer: TextBuffer): OpenBufferInfo =
  OpenBufferInfo(
    id: buffer.id,
    title: buffer.bufferTitle,
    filePath: buffer.filePath,
    modified: buffer.isModified,
    readOnly: buffer.readOnly,
    active: buffer == activeBuffer,
  )

proc activeWindowBuffers*(e: Editor): seq[OpenBufferInfo] =
  ## Return ordered buffer snapshots for the active window.
  ## Stale ids are ignored. The active buffer is appended when it has not yet
  ## been registered in the window's buffer list.
  let activeBuffer = e.activeBuffer
  var includesActiveBuffer = false
  for id in e.activeWindow.bufferIds:
    let buffer = e.bufferById(id)
    if buffer.isSome:
      includesActiveBuffer = includesActiveBuffer or buffer.get == activeBuffer
      result.add buffer.get.toOpenBufferInfo(activeBuffer)
  if not includesActiveBuffer:
    result.add activeBuffer.toOpenBufferInfo(activeBuffer)

proc deleteBufferAt*(e: Editor, idx: int) =
  ## Remove the buffer at `idx` from `e.buffers` and drop it from
  ## `bufferIdIndex`. Use this instead of `e.buffers.delete`.
  ## Also sends LSP didClose so a later re-open doesn't collide with stale
  ## server state (no-op for non-file buffers and untracked paths).
  if e.lsp != nil:
    e.lsp.onBufferClose(e.buffers[idx])
  e.deleteBufferAtNoLsp(idx)

proc findBufferByPath*(e: Editor, path: string): int =
  ## Buffer index for `path`, or -1 if not found.
  indexOfBufferHoldingPath(e.buffers, path)

proc addBufferToWindowList*(e: Editor, buffer: TextBuffer) =
  ## Append `buffer.id` to the active window's per-window tab list if absent.
  if buffer.id notin e.activeWindow.bufferIds:
    e.activeWindow.bufferIds.add(buffer.id)

proc activateBufferInWindow(e: Editor, targetBuffer: TextBuffer) =
  ## Point the active window at `targetBuffer`, resetting viewport/cursor.
  ## No-op when already on this tab (preserves position).
  if not e.moveWindowToTab(e.activeWindow, targetBuffer):
    return

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

proc activateBuffer*(e: Editor, id: BufferId): bool =
  ## Activate a buffer by stable id and register it with the active window.
  let index = e.bufferIndexById(id)
  if index < 0:
    return false
  e.switchToBufferByIndex(index)
  true

proc currentBufferIndex*(e: Editor): int =
  ## Get the position of the active buffer in e.buffers.
  ## Returns -1 if not found.
  e.bufferIndexById(e.activeBuffer().id)

proc windowBufferIndex*(e: Editor): int =
  ## Index of the active buffer inside the active window's tab list.
  ## Returns -1 if the active buffer is not registered with this window.
  let id = e.activeWindow.tabBufferId
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

when not defined(moe.embedded):
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
      if w.buffer != nil and w.tabBufferId == bufId:
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
      let w = e.windowManager.windows[fu.winIdx]
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
        let target = e.bufferById(w.bufferIds[newIdx])
        if w.viewerEntry.isNone and fu.winIdx == prevActive:
          # Shared transition finalizes Insert and reapplies forceInsertMode.
          e.switchToWindowBuffer(newIdx)
        elif target.isSome:
          e.moveTabUnder(w, target.get)
        else:
          w.bufferIds.delete(newIdx)
      else:
        # No tabs left: adopt a global survivor, else a blank.
        let target =
          if e.buffers.len > 0:
            e.buffers[min(max(bidx, 0), e.buffers.len - 1)]
          else:
            let blank = newTextBuffer("")
            e.addBuffer(blank)
            blank
        w.bufferIds.add(target.id)
        e.moveTabUnder(w, target)
    # Re-anchor to the active window and refresh its cursor.
    e.syncActiveWindow()
    e.setActiveWindowScreenCursor(e.activeWindow)

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
    ## the shell's process group deterministically. Unlike `closeTerminalBuffer`,
    ## this does not rewire windows or buffer lists: the editor is exiting, so
    ## only the OS resources need releasing. Idempotent and safe on an empty map.
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

  if e.isShowingTab(e.activeWindow, e.activeWindow.bufferIds[0]):
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
  if e.isShowingTab(e.activeWindow, e.activeWindow.bufferIds[lastIdx]):
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
    logDebug("editor", "  buffer[" & $i & "]: " & buf.canonicalLabel)

  if arg.len == 0:
    e.state.statusMessage = "E94: No matching buffer for " & arg
    return false

  # Try to parse as a number first: a stable buffer number (`BufferId`, as
  # shown by `:ls`), not a position in the list — deleting a buffer never
  # renumbers the others.
  try:
    let bufNum = parseInt(arg)
    var matchedId: Option[BufferId] = none(BufferId)
    for buf in e.buffers:
      if buf.id.int == bufNum:
        matchedId = some(buf.id)
        break

    logDebug("editor", "Parsed buffer number: " & $bufNum)

    if matchedId.isNone:
      e.state.statusMessage = "E86: Buffer " & $bufNum & " does not exist"
      logDebug("editor", "Buffer does not exist")
      return false

    let targetId = matchedId.get
    if e.isShowingTab(e.activeWindow, targetId):
      # An overlay covering the tab does not count as showing it
      logDebug("editor", "Already showing this buffer")
      return true

    # Switch to the buffer
    logDebug("editor", "Switching to buffer id: " & $bufNum)
    discard e.activateBuffer(targetId)
    e.state.statusMessage = ""
    return true
  except ValueError:
    discard # Not a number, try matching by name

  # Pick the best-ranked buffer in one scan. `matchRank` owns the precedence,
  # and strict `>` keeps the earliest buffer on a tie.
  let win = e.activeWindow
  var
    bestIndex = -1
    bestRank = bmrNone
  for i, buf in e.buffers:
    let rank = buf.matchRank(arg)
    if rank > bestRank:
      bestRank = rank
      bestIndex = i

  if bestIndex >= 0:
    if e.isShowingTab(win, e.buffers[bestIndex].id):
      logDebug("editor", "Already showing this buffer")
      return true
    e.switchToBufferByIndex(bestIndex)
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
  ## Move every window parked on `deletedBuffer` to `newBuf` and register
  ## `newBuf.id` in its tab list. Only tabs move: a view other than the tab is
  ## never a registered buffer (a listing, a Terminal snapshot), and a viewer
  ## derives the tab's view again when it ends.
  for window in e.windowManager.windows:
    if window.tabBufferId != deletedBuffer.id:
      continue
    e.moveTabUnder(window, newBuf)
    if newBuf.id notin window.bufferIds:
      window.bufferIds.add(newBuf.id)

proc deleteBufferById*(e: Editor, id: BufferId): Result[(), string] =
  when not defined(moe.embedded):
    if e.terminalStates.hasKey(id):
      # Terminal sessions need PTY cleanup; delegate to the dedicated path
      # so the state map stays in sync.
      e.closeTerminalBuffer(id)
      return ok(())

  let bufferIndex = e.bufferIndexById(id)
  if bufferIndex < 0:
    return err("Buffer does not exist")
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
        return err(enewResult.error)
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
  ok(())

proc isTerminalBuffer*(e: Editor, id: BufferId): bool =
  ## Whether `id` names a live Terminal session rather than editable text.
  ## Its buffer is an empty placeholder, so the session table is the only
  ## record.
  when defined(moe.embedded):
    false
  else:
    id in e.terminalStates

proc closeBuffer*(e: Editor, id: BufferId): Result[(), string] =
  ## Close a buffer by stable id while preserving editor lifecycle invariants.
  ## Modified buffers are rejected; terminal buffers use terminal teardown.
  let buffer = e.bufferById(id)
  if buffer.isNone:
    return err("Buffer does not exist")
  if not e.isTerminalBuffer(id) and buffer.get.isModified:
    return err("No write since last change (add ! to override)")
  e.deleteBufferById(id)

proc moveBuffer*(e: Editor, id: BufferId, destination: Natural): bool =
  ## Move a buffer to a zero-based position in the active window's ordering.
  ## Returns false when the id or destination is not in that ordering.
  let destinationIndex = destination.int
  if destinationIndex >= e.activeWindow.bufferIds.len:
    return false

  var source = -1
  for index, bufferId in e.activeWindow.bufferIds:
    if bufferId == id:
      source = index
      break
  if source < 0:
    return false
  if source == destinationIndex:
    return true

  e.activeWindow.bufferIds.delete(source)
  e.activeWindow.bufferIds.insert(id, destinationIndex)
  true

proc deleteCurrentBuffer*(e: Editor, force: bool = false): Result[(), string] =
  ## Delete the buffer the active window is parked on (Vim `:bd` semantics).
  ## Every window that was showing it switches to another buffer — windows
  ## themselves stay open. If this was the only buffer, a fresh empty
  ## `[No Name]` buffer takes its place.
  ##
  ## The target is the window's tab, not `activeBuffer()` — they differ in
  ## Terminal-Normal and the viewer modes. `force` skips the modified check as
  ## `:bd!` does.
  ##
  ## Refusals come back as `err`, not a status message, so an embedding caller
  ## can tell a refusal from a deletion.
  ##
  ## A split viewer's window exists for its listing, so there the listing goes
  ## and the window with it, as Vim closes the windows on a deleted buffer; the
  ## last window instead goes back to the tab it covered.
  let win = e.activeWindow
  if win.viewerEntry.isSome and win.viewerEntry.get.placement != vpInPlace:
    e.closeLiveViewer()
    return ok(())
  let target = e.tabBuffer(win)
  if force:
    return e.deleteBufferById(target.id)
  e.closeBuffer(target.id)

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
  # Register before loading so the load announces itself through the hook
  # `addBuffer` installs. A failed load is unregistered again.
  e.addBuffer(newBuffer)
  # Stamp before the existence check, as loadFile does.
  var stamp = captureFileStamp(path)
  if fileExists(path):
    let loadResult = newBuffer.loadFile(path)
    if loadResult.isErr:
      e.unregisterBufferNoLsp(newBuffer)
      return err(loadResult.error)
  else:
    newBuffer.filePath = some(path)
    newBuffer.language = detectLanguage(path)
    if stamp.observed == fileObservedPresent:
      # File vanished between stat and check; fail closed so unread bytes are not truncated.
      let again = captureFileStamp(path)
      stamp =
        if again.observed == fileObservedPresent:
          FileStamp(observed: fileNeverObserved)
        else:
          again
    # Baseline absent so a later appearing file reads as created externally.
    newBuffer.applyFileStamp(stamp)

  applyEditorConfigToBuffer(newBuffer, e.config)
  applyHighlightConfig(newBuffer, e.config)

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
  # Check the room first so a refused open loads nothing.
  discard ?e.roomBesideSidebar()
  let bufferResult = e.loadOrCreateBuffer(path)
  if bufferResult.isErr:
    return err(bufferResult.error)
  ?e.openWindowBesideSidebar(bufferResult.get)
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
        e.enforceModePolicy()
    else:
      let bufResult = e.loadOrCreateBuffer(filePath)
      if bufResult.isErr:
        logError("moe", fmt"Failed to open {filePath}: {bufResult.error}")
      else:
        e.addBufferToWindowList(bufResult.get)
        if readonly:
          bufResult.get.readOnly = true
