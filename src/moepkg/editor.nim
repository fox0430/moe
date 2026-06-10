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

import std/[strutils, strformat, options, monotimes, times, os]

import pkg/[results, chronos]

import
  editor_types, editor_window, editor_window_state, editor_file, editor_lsp,
  editor_codelens, editor_selectionrange, editor_documentsymbol, editor_documentlink,
  editor_signaturehelp, editor_hover, editor_callhierarchy, editor_navigation,
  editor_render, editorconfig_helper, editor_init, emergency

import
  status_line, render_utils, git_diff, git_conflict, logger, config_loader,
  search_utils, completion, signature_help, hover_popup, command_completion, motion,
  color, debug_viewer, message_log, unicode_utils, highlight, sidebar, recent_file_mode

import command_handlers/handler_manager

export
  editor_types, editor_window, editor_file, editor_lsp, editor_codelens,
  editor_selectionrange, editor_documentsymbol, editor_documentlink,
  editor_signaturehelp, editor_hover, editor_callhierarchy, editor_navigation,
  editor_render

proc findBufferByPath*(e: Editor, path: string): int =
  ## Find a buffer in the buffer list by its file path
  ## Returns the buffer index (0-based) or -1 if not found
  let absPath = absolutePath(path)
  for i, buf in e.buffers:
    if buf.filePath.isSome and absolutePath(buf.filePath.get) == absPath:
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
  e.activeWindow.viewport.topLine = 0
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
      w.viewport.topLine = 0
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
  evictGitCacheForBuffer(result)
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
      window.viewport.topLine = 0
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

proc addCommandAlias*(
    e: Editor, alias: string, action: CommandLineAction
): Result[(), string] =
  ## Add a new command alias
  e.commandConfig.addAlias(alias, action)
  e.commandConfig.applyToParser(e.commandLineParser)
  ok(())

proc removeCommandAlias*(e: Editor, alias: string): Result[(), string] =
  ## Remove a command alias
  if e.commandLineParser.aliases.hasKey(alias):
    e.commandLineParser.removeAlias(alias)
    # Note: This doesn't remove from config until save is called
    ok(())
  else:
    err fmt"Alias not found: {alias}"

proc toggleStatusLine*(e: Editor) =
  ## Toggle the visibility of the status line
  e.state.toggleStatusLine()

proc setStatusLineVisible*(e: Editor, visible: bool) =
  ## Set the visibility of the status line
  e.state.setStatusLineVisible(visible)

proc toggleLineCount*(e: Editor) =
  ## Toggle the visibility of line count in status line
  e.state.toggleLineCount()

proc setLineCountVisible*(e: Editor, visible: bool) =
  ## Set the visibility of line count in status line
  e.state.setLineCountVisible(visible)

proc toggleLinePercentage*(e: Editor) =
  ## Toggle the visibility of line percentage in status line
  e.state.toggleLinePercentage()

proc setLinePercentageVisible*(e: Editor, visible: bool) =
  ## Set the visibility of line percentage in status line
  e.state.setLinePercentageVisible(visible)

proc toggleEncoding*(e: Editor) =
  ## Toggle the visibility of encoding in status line
  e.state.toggleEncoding()

proc setEncodingVisible*(e: Editor, visible: bool) =
  ## Set the visibility of encoding in status line
  e.state.setEncodingVisible(visible)

proc toggleLineWrap*(e: Editor) =
  ## Toggle line wrapping
  e.state.display.lineWrap = not e.state.display.lineWrap
  e.state.windowDisplay.needsFullRedraw = true

proc setLineWrap*(e: Editor, enabled: bool) =
  ## Set line wrapping
  e.state.display.lineWrap = enabled
  e.state.windowDisplay.needsFullRedraw = true

proc toggleMultiStatusLine*(e: Editor) =
  ## Toggle between single status line (at bottom) and multi status lines (per window)
  e.state.display.multiStatusLine = not e.state.display.multiStatusLine
  e.state.windowDisplay.needsFullRedraw = true

proc setMultiStatusLine*(e: Editor, enabled: bool) =
  ## Set multi status line mode
  e.state.display.multiStatusLine = enabled
  e.state.windowDisplay.needsFullRedraw = true

proc toggleSidebar*(e: Editor) =
  ## Toggle the visibility of the sidebar
  e.state.display.showSidebar = not e.state.display.showSidebar
  e.state.windowDisplay.needsFullRedraw = true

proc setSidebarVisible*(e: Editor, visible: bool) =
  ## Set the visibility of the sidebar
  e.state.display.showSidebar = visible
  e.state.windowDisplay.needsFullRedraw = true

proc toggleGitDiff*(e: Editor) =
  ## Toggle git diff indicators in sidebar
  e.state.display.showGitDiff = not e.state.display.showGitDiff

  # Update git diff information when enabled
  if e.state.display.showGitDiff:
    discard updateBufferWithGitDiff(e.textBuffer)

  e.state.windowDisplay.needsFullRedraw = true

proc setGitDiffVisible*(e: Editor, visible: bool) =
  ## Set git diff indicators visibility in sidebar
  e.state.display.showGitDiff = visible

  # Update git diff information when enabled
  if visible:
    discard updateBufferWithGitDiff(e.textBuffer)

  e.state.windowDisplay.needsFullRedraw = true

proc toggleSyntaxChecker*(e: Editor) =
  ## Toggle syntax checker results in sidebar
  e.state.display.showSyntaxChecker = not e.state.display.showSyntaxChecker
  e.state.windowDisplay.needsFullRedraw = true

proc setSyntaxCheckerVisible*(e: Editor, visible: bool) =
  ## Set syntax checker results visibility in sidebar
  e.state.display.showSyntaxChecker = visible
  e.state.windowDisplay.needsFullRedraw = true

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
  if fileExists(path):
    let loadResult = newBuffer.loadFile(path)
    if loadResult.isErr:
      return err(loadResult.error)
  else:
    newBuffer.filePath = some(path)
    newBuffer.language = detectLanguage(path)

  applyEditorConfigToBuffer(newBuffer, e.config)
  newBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))
  e.addBuffer(newBuffer)
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

  e.state.windowDisplay.needsFullRedraw = true
  ok(())

proc newEditor*(editorConfig: EditorConfig, vr: ValidationResult): Editor =
  ## Create a new Editor with the given configuration and validation result.
  ## If validation errors exist, they will be displayed in the status message.
  # Set color mode from configuration with fallback
  let requestedColorMode =
    case editorConfig.standard.colorMode
    of cm8color: cmk8color
    of cm16color: cmk16color
    of cm256color: cmk256color
    of cm24bit: cmk24bit
    of cmNone: cmkNone
  globalColorMode = applyColorModeFallback(requestedColorMode)

  if requestedColorMode != globalColorMode:
    editorConfig.standard.colorMode =
      case globalColorMode
      of cmk8color: cm8color
      of cmk16color: cm16color
      of cmk256color: cm256color
      of cmk24bit: cm24bit
      of cmkNone: cmNone

  # Accumulator for validation errors discovered during initialization.
  var configVr = vr

  # Initialize theme from configuration. Invalid keys/values in the user theme
  # file are recorded in configVr so they surface in the startup status message.
  initTheme(editorConfig, configVr)

  # Create the command/keybinding registries and load all config-driven
  # built-in commands, default bindings, [KeyMapping] overrides, command
  # aliases, and shell commands (see editor_init.nim).
  let (cmdRegistry, keyRegistry, cmdConfig, cmdLineParser) =
    newEditorRegistries(editorConfig, configVr)

  # Set buffer backend from configuration
  case editorConfig.standard.bufferBackend
  of bbcAuto:
    setAutoBackendMode(true)
    setConfiguredBackend(GapBuffer)
  of bbcGapBuffer:
    setAutoBackendMode(false)
    setConfiguredBackend(GapBuffer)
  of bbcSqrtDecomp:
    setAutoBackendMode(false)
    setConfiguredBackend(SqrtDecomp)
  of bbcRope:
    setAutoBackendMode(false)
    setConfiguredBackend(Rope)
  of bbcPieceTable:
    setAutoBackendMode(false)
    setConfiguredBackend(PieceTable)
  logDebug("editor", "Buffer backend: " & $editorConfig.standard.bufferBackend)

  # Initialize LSP integration with current working directory as workspace root
  let lspIntegration = newLspIntegration(getCurrentDir())

  result = Editor(
    textBuffer: newTextBuffer(),
    lsp: lspIntegration,
    lastLspChangeSeqs: initTable[BufferId, int](),
    state: EditorState(
      # activeWindow will be set after window creation below
      cursorVisible: true,
      # Display settings (grouped in DisplaySettings)
      display: DisplaySettings(
        showTabLine: editorConfig.tabLine.enable,
        showStatusLine: editorConfig.standard.statusLine,
        multiStatusLine: editorConfig.statusLine.multipleStatusLine,
        showLineCount: true,
        showLinePercentage: true,
        showEncoding: true,
        showLineEnding: true,
        showLineNumbers: editorConfig.standard.number,
        relativeLineNumbers: editorConfig.standard.relativeNumber,
        showCursorLine: editorConfig.highlight.currentLine,
        showCursorColumn: editorConfig.highlight.currentColumn,
        showSyntax: editorConfig.standard.syntax,
        showIndentationLines: editorConfig.standard.indentationLines,
        showSidebar: editorConfig.standard.sidebar,
        scrollbar: editorConfig.standard.scrollbar,
        scrollbarWidth: editorConfig.standard.scrollbarWidth,
        showModifiedLines: editorConfig.standard.showModifiedLines,
        showGitDiff: editorConfig.git.showChangedLine,
        showSyntaxChecker: editorConfig.syntaxChecker.enable,
        showCodeLens: editorConfig.lsp.codeLens.enable,
        showDocumentHighlight: editorConfig.lsp.documentHighlight.enable,
        showInlayHint: editorConfig.lsp.inlayHint.enable,
        lineWrap: editorConfig.standard.lineWrap,
        tabStop: editorConfig.standard.tabStop,
        shiftWidth: editorConfig.standard.shiftWidth,
        softTabStop: editorConfig.standard.softTabStop,
        expandTab: editorConfig.standard.expandTab,
        autoIndent: editorConfig.standard.autoIndent,
        smartIndent: editorConfig.standard.smartIndent,
        autoCloseParen: editorConfig.standard.autoCloseParen,
        autoDeleteParen: editorConfig.standard.autoDeleteParen,
        bracketSplit: editorConfig.standard.bracketSplit,
      ),
      windowDisplay: WindowDisplayState(
        needsFullRedraw: true, # Initial render needs full draw
        viewportReservedLines: steadyBottomAreaHeight(), # Status+command share same row
        savedViewportTopLine: 0, # Saved viewport position for operators
      ),
      # Timing state (grouped in TimingState)
      timing: TimingState(
        lastResizeTime: getMonoTime(),
        gitDiffUpdateInterval: editorConfig.git.updateInterval,
        lastConflictScan: getMonoTime(),
        lastConflictScanSeq: -1,
        conflictScanInterval: DefaultConflictScanIntervalMs,
        lastAutoSave: getMonoTime(),
        lastAutoBackup: getMonoTime(),
        lastInputTime: getMonoTime(),
        lastFileModCheck: getMonoTime(),
        fileModCheckInterval: 1000, # Check file modification every 1 second
        lastConfigCheck: getMonoTime(),
        lastConfigModTime: times.Time(), # Will be set properly after initialization
        configCheckInterval: 2000, # Check config modification every 2 seconds
      ),
      # Search state (grouped in SearchState)
      search: SearchState(
        text: "",
        lastText: "",
        direction: Forward,
        history:
          if editorConfig.persist.search:
            loadSearchHistory(editorConfig.persist.searchHistoryLimit)
          else:
            @[],
        historyIndex: -1,
        startPos: BufferPosition(line: 0, column: 0),
        ignorecase: editorConfig.standard.ignorecase,
        smartcase: editorConfig.standard.smartcase,
        incsearch: editorConfig.standard.incrementalSearch,
        hlsearch: true,
        hlsearchTempDisabled: false,
      ),
      # Command state (grouped in CommandState)
      commandState: CommandState(
        history:
          if editorConfig.persist.commandHistory:
            loadCommandHistory(editorConfig.persist.commandHistoryLimit)
          else:
            @[],
        historyIndex: -1,
      ),
      # Macro state (grouped in MacroState)
      macroState: MacroState(
        isRecording: false,
        register: '\0',
        recordedKeys: @[],
        registers: initTable[char, seq[string]](),
        lastRegister: none(char),
        waitingForRegister: false,
        commandType: "",
        pendingCount: 1,
        playbackDepth: 0,
      ),
      lastKeyWasEscape: false, # Track double-Escape for clearing highlight
      # Edit operation state (grouped in EditState)
      editState: EditState(
        lastMotion: none(Motion),
        lastEditCommand: none(LastEditCommand),
        pendingOperator: none(PendingOperator),
        pendingTextObject: none(PendingTextObject),
        substituteContext: none(SubstituteContext),
        replaceHistory: @[],
        insertModeStartPos: none(BufferPosition),
        visualBlockInsertContext: none(VisualBlockInsertContext),
      ),
      # Full register system
      registers: initRegisters(),
      pendingRegister: none(char),
      # Jump list
      jumpList: @[], # Empty jump list initially
      jumpListIndex: -1, # Not navigating jump list initially
      # Command mode completion
      commandCompletionManager: newCommandCompletionManager(),
      # LSP cache state (grouped in LspCacheState)
      lspCache: LspCacheState(
        codeLensCache: CodeLensCache(isValid: false),
        codeLensPicker: CodeLensPicker(isActive: false),
        documentHighlightCache: DocumentHighlightCache(isValid: false),
        semanticTokensCache: SemanticTokensCache(isValid: false),
        hoverPopup: newHoverPopupManager(),
        locations: none(LspLocationsResult),
        lastCodeLensUpdate: getMonoTime(),
        codeLensUpdateInterval: 1000, # 1 second debounce
        lastDocumentHighlightUpdate: getMonoTime(),
        documentHighlightUpdateInterval: 200, # 200ms debounce
        lastSemanticTokensUpdate: getMonoTime(),
        semanticTokensUpdateInterval: 500, # 500ms debounce for semantic tokens
        inlayHintCache: InlayHintCache(isValid: false),
        lastInlayHintUpdate: getMonoTime(),
        inlayHintUpdateInterval: 500, # 500ms debounce for inlay hints
        signatureHelp: SignatureHelpRequestState(
          lastUpdate: getMonoTime(),
          interval: 100, # 100ms debounce for signature help
          cursorLine: -1,
          cursorColumn: -1,
          changeSeq: -1,
          consecutiveErrors: 0,
        ),
      ),
      notificationPopup: newNotificationPopupManager(),
    ),
    viewport: ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 20, x: 0, y: 0),
    screenSize: ScreenSize(width: 80, height: 20),
    commandRegistry: cmdRegistry,
    keyBindingRegistry: keyRegistry,
    keyRouter: newKeyRouter(
      keyRegistry,
      TimeoutPolicy(timeoutlen: editorConfig.standard.timeoutlen, enabled: true),
    ),
    commandLineParser: cmdLineParser,
    commandConfig: cmdConfig,
    handlerManager: nil, # Will be set after executer is created
    windowManager: newEditorWindowManager(),
    buffers: @[], # Will be initialized below
    config: editorConfig, # Store configuration
    cursorPositions:
      if editorConfig.persist.cursorPosition:
        loadCursorPositions()
      else:
        initTable[string, CursorPositionEntry](),
    savedBookmarks:
      if editorConfig.persist.bookmarks:
        loadBookmarks()
      else:
        initTable[string, seq[int]](),
  )

  # Apply sidebar bookmark marker from config
  setBookmarkMarker(editorConfig.standard.bookmarkMarker)

  # Sync notification popup settings from config
  result.state.notificationPopup.timeoutMs = editorConfig.notification.popupTimeoutMs
  result.state.notificationPopup.maxVisible = editorConfig.notification.popupMaxVisible
  result.state.notificationPopup.maxWidth = editorConfig.notification.popupMaxWidth
  result.state.notificationPopup.showBorder = editorConfig.notification.popupBorder
  case editorConfig.notification.popupPosition
  of "topRight":
    result.state.notificationPopup.position = nppTopRight
  of "topLeft":
    result.state.notificationPopup.position = nppTopLeft
  of "bottomLeft":
    result.state.notificationPopup.position = nppBottomLeft
  else:
    result.state.notificationPopup.position = nppBottomRight

  # Add initial buffer to buffer list
  result.addBuffer(result.textBuffer)
  logDebug("editor", "Initial buffer added, buffers.len: " & $result.buffers.len)

  # Set reserved words for syntax highlighting on initial buffer
  result.textBuffer.setReservedWords(
    toReservedWords(editorConfig.highlight.reservedWord)
  )

  # Create default window (always have at least one window)
  result.windowManager.windows.add(
    EditorWindow(
      buffer: result.textBuffer,
      bufferIds: @[result.textBuffer.id],
        # Initialize per-window tabs with the initial buffer
      viewport: result.viewport,
      cursor: BufferPosition(line: 0, column: 0),
      mode: EditorMode.Normal,
      previousMode: EditorMode.Normal,
      preferredColumn: -1,
      screenCursor: CursorPosition(x: 0, y: 0),
      active: true,
      wrapCountCache: WrapCountCache(),
    )
  )
  result.windowManager.activeWindowIndex = 0
  result.state.activeWindow = result.windowManager.windows[0]
  result.state.windowDisplay.currentBufferId = result.textBuffer.id
  logDebug(
    "editor",
    "Default window created, windows.len: " & $result.windowManager.windows.len,
  )

  result.executer = newCommandExecutor(
    result.textBuffer,
    result.state,
    result.viewport,
    result.config.clipboard,
    result.config.notification,
    some(cmdRegistry),
    some(keyRegistry),
  )

  # Create handler manager after executer (which creates motion controller)
  result.handlerManager = newHandlerManager(
    result.executer.motionController, keyRegistry, cmdLineParser, cmdConfig,
    cmdRegistry, result.config.clipboard, result.config.smoothScroll,
    result.config.notification, result.lsp, result.config.autocomplete.enable,
    result.config.lsp.completion.enable,
  )

  # Set clipboard tool for register system
  if result.config.clipboard.enable:
    result.state.registers.setClipboardTool(result.config.clipboard.tool)

  # Apply LSP enable setting from config
  result.lsp.setEnabled(result.config.lsp.enable)

  # Propagate per-language server settings from the config ([Lsp.<lang>])
  # into the LSP service. Without this, user overrides for command,
  # extensions, or trace were ignored and only the hardcoded defaults ran.
  # The command string may include arguments; the worker splits it, so args
  # is cleared when a custom command is given. trace=verbose enables raw
  # JSON-RPC logging (off by default to avoid the per-keystroke cost).
  for langId, serverCfg in result.config.lsp.servers:
    let existing = result.lsp.service.getConfig(langId)
    if existing.isSome:
      var c = existing.get
      if serverCfg.command.len > 0:
        c.command = serverCfg.command
        c.args = @[]
      if serverCfg.extensions.len > 0:
        c.extensions = serverCfg.extensions
      if serverCfg.trace == LspTraceLevel.ltVerbose:
        c.rawJsonLog = true
      if langId == "rust":
        # Drive rust-analyzer's run/debug CodeLenses from the user settings.
        # Sent explicitly (including false) so the lenses are suppressed when
        # disabled, instead of relying on rust-analyzer's on-by-default lens.
        c.initializationOptions =
          "{\"lens\":{\"run\":{\"enable\":" & $serverCfg.rustAnalyzerRunSingle &
          "},\"debug\":{\"enable\":" & $serverCfg.rustAnalyzerDebugSingle & "}}}"
      result.lsp.service.setConfig(langId, c)
    elif serverCfg.command.len > 0:
      # A language with no built-in default: register it from the user config
      result.lsp.service.setConfig(
        langId,
        LanguageServerConfig(
          command: serverCfg.command,
          args: @[],
          extensions: serverCfg.extensions,
          enabled: true,
          rawJsonLog: serverCfg.trace == LspTraceLevel.ltVerbose,
        ),
      )

  # Initialize config file modification time for liveReloadOfConf
  let configPath = getConfigPath()
  if fileExists(configPath):
    try:
      result.state.timing.lastConfigModTime = getFileInfo(configPath).lastWriteTime
    except OSError:
      discard

  # Display validation errors in status message if any
  if configVr.hasErrors:
    let errorMessages = configVr.toErrorMessages
    result.state.statusMessage = "Config error: " & errorMessages[0]
    # Log all errors
    for msg in errorMessages:
      addMessageLog("Config error: " & msg)

  # Check for crash recovery files from a previous crash
  if hasCrashRecoveryFiles():
    let msg = "Crash recovery files found. See " & getCrashRecoveryBaseDir()
    if result.state.statusMessage.len == 0:
      result.state.statusMessage = msg
    addMessageLog(msg)

  # Propagate the configured git diff refresh cadence into the status-line
  # cache's module global. applyConfigSettings does this on config reload;
  # without an initial call here the cache would run at the hardcoded
  # default until the first reload.
  setGitDiffRefreshInterval(editorConfig.git.updateInterval.int64)

proc newEditor*(editorConfig: EditorConfig): Editor =
  ## Create a new Editor with the given configuration.
  result = newEditor(editorConfig, newValidationResult())

proc newEditor*(): Editor =
  ## Create a new Editor, loading configuration from default path.
  # Load TOML configuration
  let loadResult = loadConfig()
  var
    editorConfig: EditorConfig
    vr = newValidationResult()
  if loadResult.isOk:
    (editorConfig, vr) = loadResult.get
  else:
    vr.addError("config", loadResult.error, "valid TOML file")
    editorConfig = newEditorConfig()

  result = newEditor(editorConfig, vr)

proc maybeReloadExternallyModifiedFile*(e: Editor) =
  ## Check if files were modified externally and reload them if:
  ##   - liveReloadOfFile is enabled in config
  ##   - Buffer has no unsaved changes (if modified, just show a message)
  ##   - Enough time has passed since last check (debouncing)

  if not e.config.standard.liveReloadOfFile:
    return

  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastFileModCheck
  let threshold = initDuration(milliseconds = e.state.timing.fileModCheckInterval)

  if elapsed < threshold:
    return

  e.state.timing.lastFileModCheck = now

  # Check the active buffer
  let activeBuffer = e.activeBuffer()
  if not activeBuffer.isExternallyModified():
    return

  let filePath =
    if activeBuffer.filePath.isSome:
      activeBuffer.filePath.get
    else:
      return

  # If buffer has unsaved changes, warn the user instead of reloading
  if activeBuffer.isModified:
    if not activeBuffer.externalModWarned:
      e.state.statusMessage =
        "Warning: " & filePath & " changed on disk (buffer has unsaved changes)"
      activeBuffer.externalModWarned = true
    return

  # Reload the file
  logInfo("editor", "File externally modified, reloading: " & filePath)
  let reloadResult = activeBuffer.reloadFile()
  if reloadResult.isOk:
    e.state.statusMessage = "File reloaded: " & filePath
    e.state.windowDisplay.needsFullRedraw = true
    # Update git diff after reload
    e.refreshGitDiff(useBuffer = false)
    # Rescan conflict markers against the newly loaded content
    activeBuffer.refreshConflicts()
    e.state.timing.lastConflictScan = getMonoTime()
    e.state.timing.lastConflictScanSeq = activeBuffer.changeSeq
  else:
    e.state.statusMessage = "Failed to reload file: " & reloadResult.error

proc reloadCurrentFile*(e: Editor): Result[void, string] =
  ## Reload the current buffer from disk (for :e! command)
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return err("No file name")

  let filePath = activeBuffer.filePath.get
  let reloadResult = activeBuffer.reloadFile()
  if reloadResult.isErr:
    return err(reloadResult.error)

  e.state.statusMessage = "File reloaded: " & filePath
  e.state.windowDisplay.needsFullRedraw = true
  e.refreshGitDiff(useBuffer = false)
  activeBuffer.refreshConflicts()
  e.state.timing.lastConflictScan = getMonoTime()
  e.state.timing.lastConflictScanSeq = activeBuffer.changeSeq
  return ok()

proc applyConfigSettings*(e: Editor, newConfig: EditorConfig) =
  ## Apply configuration settings to the editor
  ## Updates display settings, search settings, and other runtime state
  ## Note: Some settings require editor restart to take effect

  # Update display settings from config
  e.state.display.showTabLine = newConfig.tabLine.enable
  e.state.display.showStatusLine = newConfig.standard.statusLine
  e.state.display.multiStatusLine = newConfig.statusLine.multipleStatusLine
  e.state.display.showLineNumbers = newConfig.standard.number
  e.state.display.relativeLineNumbers = newConfig.standard.relativeNumber
  e.state.display.showCursorLine = newConfig.highlight.currentLine
  e.state.display.showCursorColumn = newConfig.highlight.currentColumn
  e.state.display.showSyntax = newConfig.standard.syntax
  e.state.display.showIndentationLines = newConfig.standard.indentationLines
  e.state.display.showSidebar = newConfig.standard.sidebar
  e.state.display.scrollbar = newConfig.standard.scrollbar
  e.state.display.scrollbarWidth = newConfig.standard.scrollbarWidth
  e.state.display.showModifiedLines = newConfig.standard.showModifiedLines
  e.state.display.showGitDiff = newConfig.git.showChangedLine
  e.state.display.showSyntaxChecker = newConfig.syntaxChecker.enable
  e.state.display.showCodeLens = newConfig.lsp.codeLens.enable
  e.state.display.showDocumentHighlight = newConfig.lsp.documentHighlight.enable
  e.state.display.showInlayHint = newConfig.lsp.inlayHint.enable

  # The insert handler caches lsp.completion.enable as a flag (it has no access
  # to e.config), so re-sync it on reload like the display flags above.
  e.handlerManager.insertHandler.lspCompletionEnabled = newConfig.lsp.completion.enable

  if not newConfig.lsp.diagnostics.enable:
    # Diagnostics are server-push; when disabled, incoming publishDiagnostics are
    # dropped in applyDiagnosticsForUri. Clear what was already applied so
    # existing markers and hover content disappear on reload too.
    e.clearAllDiagnostics()

  e.state.display.tabStop = newConfig.standard.tabStop
  e.state.display.shiftWidth = newConfig.standard.shiftWidth
  e.state.display.softTabStop = newConfig.standard.softTabStop
  e.state.display.expandTab = newConfig.standard.expandTab
  e.state.display.autoIndent = newConfig.standard.autoIndent
  e.state.display.smartIndent = newConfig.standard.smartIndent
  e.state.display.autoCloseParen = newConfig.standard.autoCloseParen
  e.state.display.autoDeleteParen = newConfig.standard.autoDeleteParen
  e.state.display.bracketSplit = newConfig.standard.bracketSplit

  # Update search settings
  e.state.search.ignorecase = newConfig.standard.ignorecase
  e.state.search.smartcase = newConfig.standard.smartcase
  e.state.search.incsearch = newConfig.standard.incrementalSearch

  # Update timing intervals
  e.state.timing.gitDiffUpdateInterval = newConfig.git.updateInterval
  setGitDiffRefreshInterval(newConfig.git.updateInterval.int64)

  # Update color mode with fallback
  let requestedColorMode =
    case newConfig.standard.colorMode
    of cm8color: cmk8color
    of cm16color: cmk16color
    of cm256color: cmk256color
    of cm24bit: cmk24bit
    of cmNone: cmkNone
  globalColorMode = applyColorModeFallback(requestedColorMode)

  # Update clipboard tool if enabled
  if newConfig.clipboard.enable:
    e.state.registers.setClipboardTool(newConfig.clipboard.tool)

  # Update reserved words on all buffers
  let reservedWords = toReservedWords(newConfig.highlight.reservedWord)
  for buf in e.buffers:
    buf.setReservedWords(reservedWords)

  # Reload theme if configured
  initTheme(newConfig)

  # Update sidebar bookmark marker
  setBookmarkMarker(newConfig.standard.bookmarkMarker)

  # Update LSP enable/disable
  e.lsp.setEnabled(newConfig.lsp.enable)

  # Update mouse capture
  if not e.app.isNil:
    if newConfig.standard.mouse:
      e.app.enableMouse()
    else:
      e.app.disableMouse()

  # Update notification popup settings
  e.state.notificationPopup.timeoutMs = newConfig.notification.popupTimeoutMs
  e.state.notificationPopup.maxVisible = newConfig.notification.popupMaxVisible
  e.state.notificationPopup.maxWidth = newConfig.notification.popupMaxWidth
  e.state.notificationPopup.showBorder = newConfig.notification.popupBorder
  case newConfig.notification.popupPosition
  of "topRight":
    e.state.notificationPopup.position = nppTopRight
  of "topLeft":
    e.state.notificationPopup.position = nppTopLeft
  of "bottomLeft":
    e.state.notificationPopup.position = nppBottomLeft
  else:
    e.state.notificationPopup.position = nppBottomRight

  # Propagate timeout policy to the key router so live reload and
  # config-mode edits take effect for runtime-mapping timeouts.
  e.keyRouter.updatePolicy(
    TimeoutPolicy(timeoutlen: newConfig.standard.timeoutlen, enabled: true)
  )

  # Store the new config
  e.config = newConfig

proc maybeReloadConfig*(e: Editor) =
  ## Check if config file was modified and reload if:
  ##   - liveReloadOfConf is enabled in config
  ##   - Enough time has passed since last check (debouncing)
  ##   - Config file modification time has changed

  if not e.config.standard.liveReloadOfConf:
    return

  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastConfigCheck
  let threshold = initDuration(milliseconds = e.state.timing.configCheckInterval)

  if elapsed < threshold:
    return

  e.state.timing.lastConfigCheck = now

  # Check if config file exists and has been modified
  let configPath = getConfigPath()
  if not fileExists(configPath):
    return

  var currentModTime: times.Time
  try:
    currentModTime = getFileInfo(configPath).lastWriteTime
  except OSError:
    return

  # Compare modification times
  if currentModTime == e.state.timing.lastConfigModTime:
    return

  # Config file was modified, reload it
  logInfo("editor", "Config file modified, reloading: " & configPath)
  let loadResult = loadConfigFromToml(configPath)
  if loadResult.isErr:
    logError("editor", "Failed to reload config: " & loadResult.error)
    return

  let (newConfig, vr) = loadResult.get
  if vr.hasErrors:
    for msg in vr.toErrorMessages:
      logWarn("editor", "Config warning: " & msg)

  # Apply the new settings
  e.applyConfigSettings(newConfig)

  # Update last known modification time
  e.state.timing.lastConfigModTime = currentModTime

  e.state.statusMessage = "Configuration reloaded"
  e.state.windowDisplay.needsFullRedraw = true

proc maybeUpdateConflicts*(e: Editor) =
  ## Rescan the active buffer for git conflict markers when it has been
  ## modified since the last scan. Debounced by `conflictScanInterval` to
  ## keep editing responsive on very large files.
  let activeBuffer = e.activeBuffer()
  if activeBuffer.changeSeq == e.state.timing.lastConflictScanSeq:
    return
  let now = getMonoTime()
  let threshold = initDuration(milliseconds = e.state.timing.conflictScanInterval)
  if now - e.state.timing.lastConflictScan < threshold:
    return
  let prevBlocks = activeBuffer.conflictBlocks
  activeBuffer.refreshConflicts()
  e.state.timing.lastConflictScan = now
  e.state.timing.lastConflictScanSeq = activeBuffer.changeSeq
  # Only force a full redraw when the block structure actually changed —
  # per-line edits already trigger their own redraws.
  if activeBuffer.conflictBlocks != prevBlocks:
    e.state.windowDisplay.needsFullRedraw = true

proc enterRecentFileMode*(e: Editor): Result[void, string] =
  ## Enter Recent File mode in a vertical split window
  let state = newRecentFileModeState()
  let loadResult = state.loadRecentFiles()
  if loadResult.isErr:
    return err(loadResult.error)
  let recentBuffer = state.createRecentFileTextBuffer()
  let splitResult = e.vsplitWithBuffer(recentBuffer)
  if splitResult.isErr:
    return err(splitResult.error)
  e.activeWindow.modeState = ModeState(kind: mskRecentFile, recentFile: state)
  ok()

proc startSubstitutePreview*(e: Editor) =
  ## Start substitute preview by saving the current buffer content
  if e.state.ui.substitutePreview.isActive:
    return

  let buffer = e.activeBuffer()
  e.state.ui.substitutePreview.originalLines = @[]
  for i in 0 ..< buffer.len:
    e.state.ui.substitutePreview.originalLines.add(buffer.getLine(i))
  e.state.ui.substitutePreview.isActive = true
  e.state.ui.substitutePreview.lastPattern = ""
  e.state.ui.substitutePreview.lastReplacement = ""
  e.state.ui.substitutePreview.originalCursor = e.cursor
  e.state.ui.substitutePreview.originalTopLine = e.activeWindow.viewport.topLine
  e.state.ui.substitutePreview.originalLeftColumn = e.activeWindow.viewport.leftColumn

proc restoreFromPreview*(e: Editor) =
  ## Restore buffer content from preview snapshot without cancelling the preview.
  ## Callers that want to cancel preview entirely should use cancelSubstitutePreview.
  if not e.state.ui.substitutePreview.isActive:
    return

  let buffer = e.activeBuffer()
  # Restore all lines from snapshot
  for i in 0 ..< e.state.ui.substitutePreview.originalLines.len:
    if i < buffer.len:
      buffer.replaceLineNoUndo(i, e.state.ui.substitutePreview.originalLines[i])

  # Handle line count differences
  while buffer.len > e.state.ui.substitutePreview.originalLines.len:
    buffer.deleteLineNoUndo(buffer.len - 1)
  while buffer.len < e.state.ui.substitutePreview.originalLines.len:
    buffer.insertLineNoUndo(
      buffer.len, e.state.ui.substitutePreview.originalLines[buffer.len]
    )

  buffer.highlightNeedsUpdate = true
  # Clear last-applied pattern/replacement so the next updateSubstitutePreview
  # call does not skip work when identical values are reapplied.
  e.state.ui.substitutePreview.lastPattern = ""
  e.state.ui.substitutePreview.lastReplacement = ""

proc cancelSubstitutePreview*(e: Editor) =
  ## Cancel substitute preview and restore original content
  if not e.state.ui.substitutePreview.isActive:
    return

  e.restoreFromPreview()
  e.cursor = e.state.ui.substitutePreview.originalCursor
  e.activeWindow.viewport.topLine = e.state.ui.substitutePreview.originalTopLine
  e.activeWindow.viewport.leftColumn = e.state.ui.substitutePreview.originalLeftColumn
  e.state.ui.substitutePreview.isActive = false
  e.state.ui.substitutePreview.originalLines = @[]
  e.state.windowDisplay.needsFullRedraw = true

proc commitSubstitutePreview*(e: Editor) =
  ## Commit substitute preview (discard snapshot, keep current changes)
  e.state.ui.substitutePreview.isActive = false
  e.state.ui.substitutePreview.originalLines = @[]

proc updateSubstitutePreview*(
    e: Editor, pattern: string, replacement: string, isGlobalFlag: bool = true
) =
  ## Update substitute preview with new pattern and replacement
  ## isGlobalFlag: if true, replace all occurrences per line; if false, only first occurrence
  if not e.state.ui.substitutePreview.isActive:
    return

  # Skip if nothing changed
  if pattern == e.state.ui.substitutePreview.lastPattern and
      replacement == e.state.ui.substitutePreview.lastReplacement:
    return

  # Restore from snapshot first (this clears lastPattern/lastReplacement, so
  # cache the new values *after* restoring).
  e.restoreFromPreview()

  e.state.ui.substitutePreview.lastPattern = pattern
  e.state.ui.substitutePreview.lastReplacement = replacement

  if pattern.len == 0:
    e.state.windowDisplay.needsFullRedraw = true
    return

  # Process escape sequences in replacement using common utility
  let processedReplacement = processEscapeSequences(replacement)

  # Apply substitute to buffer
  let buffer = e.activeBuffer()
  for lineIdx in 0 ..< buffer.len:
    var line = buffer.getLine(lineIdx)
    var newLine = ""
    var searchPos = 0
    var modified = false

    while searchPos <= line.len:
      let idx = line.find(pattern, searchPos)
      if idx < 0:
        newLine.add(line[searchPos ..^ 1])
        break

      if idx > searchPos:
        newLine.add(line[searchPos ..< idx])

      newLine.add(processedReplacement)
      modified = true
      searchPos = idx + pattern.len

      # If not global flag, only replace first occurrence per line
      if not isGlobalFlag:
        newLine.add(line[searchPos ..^ 1])
        break

    if modified:
      buffer.replaceLineNoUndo(lineIdx, newLine)

  buffer.highlightNeedsUpdate = true
  e.state.windowDisplay.needsFullRedraw = true

proc shutdown*(e: Editor) =
  ## Shutdown editor and clean up resources (including LSP servers)
  e.lsp.shutdown()

proc maybeUpdateDebugBuffer*(e: Editor) =
  ## Update debug buffer content periodically if it's displayed in a window
  ## This provides auto-refresh functionality for the debug viewer
  if e.state.windowDisplay.debugBuffer == nil:
    return

  # Check if the debug buffer is still displayed in a window
  var foundWindow: EditorWindow = nil
  for window in e.windowManager.windows:
    if window.buffer == e.state.windowDisplay.debugBuffer:
      foundWindow = window
      break

  if foundWindow == nil:
    # Debug buffer is no longer displayed, clear the reference
    e.state.windowDisplay.debugBuffer = nil
    return

  # Check if enough time has passed since last update
  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastDebugUpdate
  let threshold = initDuration(milliseconds = e.state.timing.debugUpdateInterval)

  if elapsed < threshold:
    return

  # Generate fresh debug info based on config settings
  var debugLines: seq[string] = @[]
  let debugConfig = e.config.debug

  for i, window in e.windowManager.windows:
    generateWindowInfo(
      debugLines,
      i,
      i == e.windowManager.activeWindowIndex,
      e.bufferIndexById(window.buffer.id),
      window.viewport.x,
      window.viewport.y,
      window.viewport.width,
      window.viewport.height,
      window.viewport.topLine,
      window.viewport.leftColumn,
      window.cursor.line,
      window.cursor.column,
      debugConfig.windowNode.enable,
    )

  for i, buf in e.buffers:
    generateBufferInfo(
      debugLines,
      i,
      buf.filePath,
      buf.isModified,
      buf.readOnly,
      $buf.language,
      $buf.encoding,
      buf.len,
      buf.changeSeq,
      debugConfig.bufferStatus.enable,
    )

  generateEditorStateInfo(
    debugLines, e.state.mode, e.state.previousMode, e.activeWindow.cursor.line,
    e.cursor.column, e.state.commandText, e.state.statusMessage,
    debugConfig.editorView.enable,
  )

  generateSearchInfo(
    debugLines,
    e.state.search.text,
    e.state.search.lastText,
    $e.state.search.direction,
    e.state.search.history.len,
    e.state.search.ignorecase,
    e.state.search.smartcase,
    e.state.search.incsearch,
    e.state.search.hlsearch,
    debugConfig.search.enable,
  )

  generateDisplayInfo(
    debugLines, e.state.display.showStatusLine, e.state.display.multiStatusLine,
    e.state.display.showLineNumbers, e.state.display.showCursorLine,
    e.state.display.showSyntax, e.state.display.showIndentationLines,
    e.state.display.showSidebar, e.state.display.scrollbarWidth,
    e.state.display.showModifiedLines, e.state.display.lineWrap,
    e.state.display.tabStop, debugConfig.editorView.enable,
  )

  generateMacroInfo(
    debugLines, e.state.macroState.isRecording, e.state.macroState.register,
    e.state.macroState.registers.len, e.state.macroState.playbackDepth,
    debugConfig.macroState.enable,
  )

  generateVisualInfo(
    debugLines,
    e.state.visualSelection.active,
    $e.state.visualSelection.kind,
    e.state.visualSelection.start.line,
    e.state.visualSelection.start.column,
    e.state.visualSelection.current.line,
    e.state.visualSelection.current.column,
    debugConfig.visual.enable,
  )

  generateJumpListInfo(
    debugLines, e.state.jumpList.len, e.state.jumpListIndex, debugConfig.jumpList.enable
  )

  generateLspInfo(
    debugLines, e.state.lspCache.codeLensCache.itemsByLine.len,
    e.state.lspCache.locations.isSome, e.state.lspCache.codeLensCache.isValid,
    debugConfig.lsp.enable,
  )

  # Update debug viewer state and create new buffer
  if foundWindow.modeState.kind == mskDebug:
    let debugState = foundWindow.modeState.debug
    debugState.lines = debugLines
    let newDebugBuffer = debugState.createDebugTextBuffer()

    # Preserve scroll position
    let savedTopLine = foundWindow.viewport.topLine
    let savedLeftColumn = foundWindow.viewport.leftColumn

    # Replace buffer in the window
    foundWindow.buffer = newDebugBuffer

    # Restore scroll position (clamped to valid range)
    foundWindow.viewport.topLine = min(savedTopLine, max(0, newDebugBuffer.len - 1))
    foundWindow.viewport.leftColumn = savedLeftColumn

    # Update the reference in state
    e.state.windowDisplay.debugBuffer = newDebugBuffer
  e.state.timing.lastDebugUpdate = now
  e.state.windowDisplay.needsFullRedraw = true

proc notify*(e: Editor, msg: string, level: NotificationLevel = nlInfo) =
  ## Send a notification. Routes to popup or status line based on config.
  if e.config.notification.popupNotifications:
    e.state.notificationPopup.addNotification(msg, level)
  else:
    e.state.statusMessage = msg

proc tickLsp(e: Editor) =
  ## Per-frame LSP processing: poll the server, surface its messages, push
  ## buffer changes, then drain all response caches/pollers.
  ##
  ## Ordering within this phase matters: `maybeUpdateLsp` notifies the server of
  ## the latest buffer state, and the `pollLsp*` helpers below read the resulting
  ## responses, so the update must run before the polls.

  # Poll LSP for messages (non-blocking). This is the single per-frame poll:
  # the pollLspXxx helpers below rely on this and must not poll again themselves.
  e.lsp.poll(0)

  # Cleanup stale progress entries (handles missing 'end' notifications)
  e.lsp.cleanupStaleProgress()

  # Update LSP progress display
  let progressOpt = e.lsp.getLatestActiveProgress()
  if progressOpt.isSome:
    e.state.ui.lspProgressText = getProgressText(progressOpt.get)
  else:
    e.state.ui.lspProgressText = ""

  # Display any pending LSP status messages
  let lspMessages = e.lsp.getAndClearMessages()
  if lspMessages.len > 0:
    # Store LSP messages for the log viewer
    addLspMessageLog(lspMessages)
    if e.config.notification.lspForcePopup:
      # Force all LSP messages to popup notifications
      for msg in lspMessages:
        let level =
          if msg.startsWith("[LSP Error]"):
            nlError
          elif msg.startsWith("[LSP Warning]"):
            nlWarning
          else:
            nlInfo
        e.state.notificationPopup.addNotification(msg, level)
    elif e.config.notification.screenNotifications and
        e.config.notification.lspScreenNotify:
      e.notify(lspMessages[^1])
    if e.config.notification.logNotifications and e.config.notification.lspLogNotify:
      for msg in lspMessages:
        logInfo("lsp", msg)

  # Update LSP if buffer was modified
  e.maybeUpdateLsp()

  # Update LSP caches
  e.updateCodeLensCache()
  e.updateDocumentHighlightCache()
  e.updateInlayHintCache()
  # Note: updateSemanticTokensCache is called in prepareFrame after updateHighlight
  e.requestSignatureHelpFromLsp()
  e.pollLspCompletion()
  e.pollLspHover()
  e.maybeAutoHoverDiagnostic()
  e.pollLspLocationRequest()
  e.pollLspCallHierarchy()
  e.pollLspSelectionRange()
  e.pollLspDocumentSymbols()
  e.pollLspDocumentLinks()
  e.pollLspDocumentLinkResolve()

proc tickFileAndConfig(e: Editor) =
  ## Detect external edits and config changes and reload them.
  ## `maybeReloadExternallyModifiedFile` refreshes the conflict scan state that
  ## `tickGitAndDebug` later consumes, and `maybeReloadConfig` may rewrite
  ## `e.config`, which `tickAutoSave` reads — so this phase must run before both.
  e.maybeReloadExternallyModifiedFile()
  e.maybeReloadConfig()

proc tickGitAndDebug(e: Editor) =
  ## Git and debug updates. The diff subprocess itself is scheduled lazily
  ## from status_line.cachedGitDiffCounts (called during status-line
  ## rendering); here we just consume the most recent diff result for the
  ## sidebar gutter, gated on the user's showGitDiff flag.
  ## Depends on `tickFileAndConfig` having refreshed the conflict scan first.
  if e.state.display.showGitDiff:
    maybeApplyGitMarkers(e.activeBuffer())
  e.maybeUpdateConflicts()
  e.maybeUpdateDebugBuffer()

proc tickAutoSave(e: Editor) =
  ## Auto save/backup. Reads `e.config`, so it must run after
  ## `tickFileAndConfig` has applied any reloaded config.
  e.autoSave()
  e.autoBackup()

proc tickNotifications(e: Editor) =
  ## Dismiss expired popup notifications.
  e.state.notificationPopup.tick()

proc tick*(e: Editor) =
  ## Background processing: LSP, file watching, autosave, etc.
  ## Should be called each frame before rendering.
  ##
  ## Each phase is a self-contained proc; the call order below is significant
  ## (see the per-phase docs for the dependencies between them) and must match
  ## the original sequence.
  e.tickLsp()
  e.tickFileAndConfig()
  e.tickGitAndDebug()
  e.tickAutoSave()
  e.tickNotifications()

proc prepareFrame(e: Editor, buffer: var Buffer): bool =
  ## Prepare for rendering: clear buffer, update animations, prepare highlights.
  ## Returns true if viewport was resized.

  clearBuffer(buffer)

  # Update smooth scroll animation
  if e.state.windowDisplay.scrollAnimation.active:
    let reservedLines = steadyBottomAreaHeight()
    let bufferLen = e.activeBuffer().len
    let (_, cursorLine) = e.executer.motionController.viewportManager.updateScrollAnimation(
      e.state.windowDisplay.scrollAnimation, e.config.smoothScroll, reservedLines,
      bufferLen,
    )
    e.activeWindow.cursor.line = cursorLine

  # Keep the active cursor off lines hidden inside a collapsed fold. Many cursor
  # moves (search, :N, LSP jumps, mouse clicks, cursor restore on open) bypass
  # the motion clamp; normalize here so the cursor always sits on a visible line.
  # Non-file buffers have no folds, so this is a no-op for them.
  if not e.state.windowDisplay.scrollAnimation.active:
    let buf = e.activeBuffer()
    let collapsedFold = buf.foldState.getCollapsedFoldAt(e.activeWindow.cursor.line)
    if collapsedFold.isSome:
      # Pin the cursor to the fold's start line at column 0 (the fold is a single
      # unit; the cursor must not roam its hidden content).
      e.activeWindow.cursor.line = collapsedFold.get.startLine
      e.activeWindow.cursor.column = 0

  if e.state.windowDisplay.needsFullRedraw:
    e.state.windowDisplay.needsFullRedraw = false

  # Update highlight state (skip for debug buffer)
  let isDebugBuffer =
    e.state.windowDisplay.debugBuffer != nil and
    e.activeBuffer() == e.state.windowDisplay.debugBuffer

  if e.config.highlight.pairOfParen and not isDebugBuffer:
    e.state.matchingParenPos = findMatchingParenPosition(e.activeBuffer(), e.cursor)
  else:
    e.state.matchingParenPos = none(BufferPosition)

  if e.config.highlight.currentWord and not isDebugBuffer:
    e.state.currentWord = getWordAtPosition(e.activeBuffer(), e.cursor)
  else:
    e.state.currentWord = ""

  # Update syntax highlight before rendering (so semantic tokens can be applied on top)
  if not isDebugBuffer:
    let activeBuffer = e.activeBuffer()
    var highlightChanged = activeBuffer.highlightNeedsUpdate
    activeBuffer.updateHighlight()
    # Continue progressive initial highlighting if not yet complete
    if activeBuffer.continueInitialHighlight():
      highlightChanged = true
    # Continue progressive URI scanning for all file types
    if activeBuffer.continueUriScan():
      highlightChanged = true
    # If highlight was modified, we need to re-apply semantic tokens
    if highlightChanged:
      invalidateSemanticTokensCache(e.lsp, e.state.lspCache)
      # Inlay hints are keyed by absolute line number and rendered straight from
      # the cache, so an edit (highlightChanged) would otherwise leave stale
      # hints on now-shifted lines until the next debounced response. Drop the
      # cache and cancel any in-flight request, matching semantic tokens.
      invalidateInlayHintCache(e.lsp, e.state.lspCache)
    # Apply semantic tokens after local highlight is ready
    e.updateSemanticTokensCache()

  result = e.updateViewportSize(buffer)

proc renderMainContent(e: Editor, buffer: var Buffer, wasResized: bool) =
  ## Render the main editor view (always uses split view since we always have at least one window).
  e.renderSplitView(buffer, wasResized)
  e.renderBottomLines(buffer)
  e.renderTempMessages(buffer)

proc renderOverlays(e: Editor, buffer: var Buffer) =
  ## Render overlay popups (completion, signature help, CodeLens picker, hover popup).

  if e.state.mode == EditorMode.Insert:
    let completionMgr = e.handlerManager.insertHandler.completionManager
    if completionMgr.isActive():
      # Anchor the popup to the start of the word being completed, not the
      # current cursor position. This prevents the popup from shifting when
      # cycling through candidates of different lengths.
      let anchorX = e.state.screenCursor.x - displayWidth(completionMgr.menu.prefix)
      # Stay above the (possibly grown) command-line area, plus one padding
      # row — matches the steady-state default of 2
      let bottomReserve = e.state.bottomAreaHeight(buffer.area.width) + 1
      let popupPos = calculatePopupPosition(
        anchorX, e.state.screenCursor.y, buffer.area.width, buffer.area.height,
        completionMgr.menu.entries, completionMgr.menu.maxVisible,
        e.config.autocomplete.windowBorder, bottomReserve,
      )
      renderCompletionPopup(
        buffer, completionMgr.menu, popupPos, e.config.autocomplete.windowBorder
      )

      # Render documentation panel next to completion popup
      if completionMgr.docPanel.visible:
        let docPos = calculateDocPanelPosition(
          popupPos, buffer.area.width, buffer.area.height, completionMgr.docPanel,
          bottomReserve,
        )
        renderDocPanel(buffer, completionMgr.docPanel, docPos)

    let sigHelpMgr = e.handlerManager.insertHandler.signatureHelpManager
    if sigHelpMgr.isActive():
      let popupPos = calculateSignatureHelpPosition(
        e.state.screenCursor.x, e.state.screenCursor.y, buffer.area.width,
        buffer.area.height, sigHelpMgr.display.signature.len,
      )
      renderSignatureHelpPopup(buffer, sigHelpMgr.display, popupPos, true)

  if e.state.lspCache.codeLensPicker.isActive:
    e.renderCodeLensPicker(buffer)

  # Render hover popup (Normal mode)
  if e.state.lspCache.hoverPopup.isActive():
    let hoverMgr = e.state.lspCache.hoverPopup
    let popupPos = calculateHoverPopupPosition(
      e.state.screenCursor.x, e.state.screenCursor.y, buffer.area.width,
      buffer.area.height, hoverMgr,
    )
    renderHoverPopup(buffer, hoverMgr, popupPos, true)

  # Render notification popups: float above the (possibly grown)
  # command-line area, plus one padding row when the status line is shown
  if e.state.notificationPopup.hasActiveNotifications():
    let bottomReserve =
      e.state.bottomAreaHeight(buffer.area.width) +
      (if e.state.display.showStatusLine: 1 else: 0)
    let rects = e.state.notificationPopup.calculateNotificationPositions(
      buffer.area.width, buffer.area.height, bottomReserve
    )
    for rect in rects:
      renderNotificationPopup(buffer, rect)

proc render*(e: Editor, buffer: var Buffer) =
  ## Main render procedure - orchestrates the rendering of all editor components.
  if buffer.area.width <= 0 or buffer.area.height <= 0:
    return

  e.tick()
  let wasResized = e.prepareFrame(buffer)

  # Always use split view rendering - each window renders based on its own mode
  e.renderMainContent(buffer, wasResized)

  e.renderOverlays(buffer)
