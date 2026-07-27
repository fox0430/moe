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

## Enter -> operate -> leave round-trips for the viewer modes, whose entry and
## exit sequences are repeated by hand per mode. Buffer-swapping viewers
## (Filer, BufferManager, BookmarkManager, References, DocumentSymbol,
## CallHierarchy) stash the origin cursor/viewport and restore it on exit;
## split-window viewers (LogViewer/LspLog, BackupManager, Config, Debug, Help,
## FileTree) open their own window over a scratch buffer and close it again.
##
## Coverage here is the paths test_editor.nim does not already have: the second
## entry copy in `processResult`'s modeTransition block, the non-quit exits, the
## LSP-driven viewers, the remaining split viewers, and nested entry.

import std/[unittest, os, options, json, importutils, tables]
from std/strutils import startsWith

import
  ../src/moepkg/[
    editor, config, config_loader, types, lsp_service, editor_navigation,
    editor_documentsymbol, editor_callhierarchy, window_manager, editor_window,
    editor_window_state, editor_buffers, diff_viewer, message_log,
  ]
import ../src/moepkg/command_handlers/[handler_result, result_processor]
import ../src/moepkg/buffer/core
import ../src/moepkg/lsp/protocol/types as lspTypes

const TestLines = "aaaa\nbbbb\ncccc\ndddd\neeee\nffff\ngggg\nhhhh\niiii\njjjj\n"

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc editorOnFile(name: string): tuple[e: Editor, path: string] =
  ## Editor with `name` (under the temp dir) opened in the active window.
  let path = getTempDir() / name
  writeFile(path, TestLines)
  let e = createTestEditor()
  discard e.editFile(path)
  (e, path)

proc placeOrigin(e: Editor, line, column, topLine, leftColumn: int) =
  ## The pre-viewer editing position that every exit path must bring back.
  let win = e.activeWindow
  win.cursor.line = line
  win.cursor.column = column
  win.viewport.topLine = topLine
  win.viewport.leftColumn = leftColumn

proc makeLocation(path: string, line: int): lspTypes.Location =
  lspTypes.Location(
    uri: "file://" & path,
    range: lspTypes.Range(
      start: lspTypes.Position(line: line, character: 0),
      `end`: lspTypes.Position(line: line, character: 1),
    ),
  )

proc makeCallHierarchyItem(name, uri: string, line: int): lspTypes.CallHierarchyItem =
  result.name = name
  result.kind = skFunction
  result.uri = uri
  result.range = lspTypes.Range(
    start: lspTypes.Position(line: line, character: 0),
    `end`: lspTypes.Position(line: line, character: name.len),
  )
  result.selectionRange = result.range

proc incomingCallsResponseJson(items: seq[lspTypes.CallHierarchyItem]): JsonNode =
  result = newJArray()
  for it in items:
    result.add(
      %*{
        "from": it.toJson,
        "fromRanges":
          [%*{"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 1}}],
      }
    )

proc outgoingCallsResponseJson(items: seq[lspTypes.CallHierarchyItem]): JsonNode =
  result = newJArray()
  for it in items:
    result.add(
      %*{
        "to": it.toJson,
        "fromRanges":
          [%*{"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 1}}],
      }
    )

proc documentSymbolsResponseJson(names: seq[string]): JsonNode =
  ## DocumentSymbol[] (hierarchical) wire response.
  result = newJArray()
  for i, name in names:
    let r = %*{
      "start": {"line": i, "character": 0}, "end": {"line": i, "character": name.len}
    }
    result.add(
      %*{"name": name, "kind": 12, "range": r, "selectionRange": r, "children": []}
    )

proc injectPending(
    e: Editor, feature: LspRequestFeature, requestId: int, isItemDriven = false
) =
  ## Seed lspCache.pending as if the request had just been sent, pinned to the
  ## active buffer so classifyResponse accepts. `isItemDriven` mirrors requests
  ## issued from inside a viewer, whose synthetic buffer is not in the list.
  let buf = e.activeBuffer
  e.state.lspCache.pending[feature] = LspRequestContext(
    requestId: requestId,
    feature: feature,
    bufferId: buf.id,
    contentVersion: buf.contentVersion,
    path: buf.filePath.get(""),
    generation: 1,
    cursorLine: -1,
    cursorCol: -1,
    validModes: {},
    blockedByOverlay: true,
    isItemDriven: isItemDriven,
  )

proc injectLspResponse(e: Editor, requestId: int, resp: JsonNode) =
  privateAccess(LspService)
  e.lsp.service.pendingResponses[requestId] = (result: some($resp), error: none(string))

suite "Viewer round-trip - Filer":
  test "hrEnterFiler + hrFilerQuit restores cursor/viewport/buffer":
    let (e, path) = editorOnFile("moe_rt_filer_transition.txt")
    defer:
      removeFile(path)
    let win = e.activeWindow
    let origBuf = win.buffer
    e.placeOrigin(line = 5, column = 2, topLine = 4, leftColumn = 3)

    discard e.processResult(HandlerResult(kind: hrEnterFiler), e.activeBuffer())
    check win.mode == EditorMode.Filer
    check win.modeState.kind == mskFiler
    check win.buffer != origBuf
    check win.cursor.line == 0
    check win.cursor.column == 0
    check win.viewport.topLine == 0
    check win.viewport.leftColumn == 0

    # Operate inside the filer.
    win.cursor.line = 2
    win.viewport.topLine = 1

    discard e.processResult(HandlerResult(kind: hrFilerQuit), e.activeBuffer())
    check win.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.buffer == origBuf
    check win.cursor.line == 5
    check win.cursor.column == 2
    check win.viewport.topLine == 4
    check win.viewport.leftColumn == 3

  test "a bare modeTransition enters the viewer through its real entry":
    # `mode_switch` keybindings (`:nmap <key> mode_switch filer`) reach the
    # modeTransition block with nothing but a target mode. It must build the
    # listing and mode state, or the window lands in a mode its dispatcher
    # cannot serve and no key — not even `:` — gets through.
    let (e, path) = editorOnFile("moe_rt_mode_switch_entry.txt")
    defer:
      removeFile(path)
    let win = e.activeWindow
    let origBuf = win.buffer
    e.placeOrigin(line = 5, column = 2, topLine = 4, leftColumn = 3)

    for (mode, stateKind, quitResult) in [
      (EditorMode.Filer, mskFiler, hrFilerQuit),
      (EditorMode.BufferManager, mskBufferManager, hrBufferManagerQuit),
      (EditorMode.BookmarkManager, mskBookmarkManager, hrBookmarkManagerQuit),
    ]:
      discard e.processResult(
        HandlerResult(kind: hrHandled, modeTransition: some(mode)), e.activeBuffer()
      )
      check win.mode == mode
      check win.modeState.kind == stateKind
      check win.buffer != origBuf
      check win.originalBuffer == origBuf

      discard e.processResult(HandlerResult(kind: quitResult), e.activeBuffer())
      check win.mode == EditorMode.Normal
      check win.modeState.kind == mskNone
      check win.buffer == origBuf
      check win.originalBuffer == nil
      check win.cursor.line == 5
      check win.viewport.leftColumn == 3

  test "returning to a live viewer through previousMode does not re-enter it":
    # `v` inside a viewer sets previousMode to it, and Escape transitions back.
    # The window still holds the viewer's state, so that transition needs the
    # mode flipped — replaying the entry would open a second listing each time.
    let (e, path) = editorOnFile("moe_rt_previous_mode_reentry.txt")
    defer:
      removeFile(path)

    discard e.processResult(HandlerResult(kind: hrEnterLogViewer), e.activeBuffer())
    let viewerWin = e.activeWindow
    let windowsWithViewer = e.windowManager.windows.len

    for _ in 0 .. 1:
      discard e.processResult(
        HandlerResult(kind: hrHandled, modeTransition: some(EditorMode.Visual)),
        e.activeBuffer(),
      )
      check e.state.mode == EditorMode.Visual
      check e.state.previousMode == EditorMode.LogViewer

      discard e.processResult(
        HandlerResult(kind: hrHandled, modeTransition: some(EditorMode.LogViewer)),
        e.activeBuffer(),
      )
      check e.windowManager.windows.len == windowsWithViewer
      check e.activeWindow == viewerWin
      check e.state.mode == EditorMode.LogViewer
      check viewerWin.modeState.kind == mskLogViewer

  test "returning to a live payload-only viewer through previousMode is allowed":
    # Escape from Visual made inside References produces the same modeTransition
    # as a bare mode_switch. The window still holds the state, so it must flip
    # back, not error with "Cannot switch to X directly".
    let (e, path) = editorOnFile("moe_rt_payload_reentry.txt")
    defer:
      removeFile(path)
    let win = e.activeWindow

    check e.handleLspLocations(
      @[makeLocation(path, 1), makeLocation(path, 3)], "References", "Reference"
    )
    check win.mode == EditorMode.References
    let refsBuf = win.buffer
    let statusBefore = e.state.statusMessage

    discard e.processResult(
      HandlerResult(kind: hrHandled, modeTransition: some(EditorMode.Visual)),
      e.activeBuffer(),
    )
    check e.state.mode == EditorMode.Visual
    check e.state.previousMode == EditorMode.References

    discard e.processResult(
      HandlerResult(kind: hrHandled, modeTransition: some(EditorMode.References)),
      e.activeBuffer(),
    )
    check e.state.mode == EditorMode.References
    check win.modeState.kind == mskReferences
    check win.buffer == refsBuf
    check e.state.statusMessage == statusBefore

  test "a mode_switch to a payload-only mode is rejected, not entered":
    # References/DocumentSymbol/CallHierarchy/DiffViewer have nothing to list
    # without an LSP response or a file pair. Entering them bare would leave
    # the window mode-set with mskNone state.
    let (e, path) = editorOnFile("moe_rt_mode_switch_reject.txt")
    defer:
      removeFile(path)
    let win = e.activeWindow

    for mode in [
      EditorMode.References, EditorMode.DocumentSymbol, EditorMode.CallHierarchy,
      EditorMode.DiffViewer,
    ]:
      discard e.processResult(
        HandlerResult(kind: hrHandled, modeTransition: some(mode)), e.activeBuffer()
      )
      check win.mode == EditorMode.Normal
      check win.modeState.kind == mskNone

  test "hrFilerOpenFile leaves the listing buffer behind":
    # Opening a file is an exit too. The origin cursor is deliberately not
    # restored (the new file owns it), but the listing buffer must not survive.
    let (e, path) = editorOnFile("moe_rt_filer_open.txt")
    let target = getTempDir() / "moe_rt_filer_target.txt"
    writeFile(target, "target 0\ntarget 1\n")
    defer:
      removeFile(path)
      removeFile(target)
    let win = e.activeWindow
    e.placeOrigin(line = 5, column = 2, topLine = 4, leftColumn = 3)

    discard e.processResult(HandlerResult(kind: hrEnterFiler), e.activeBuffer())
    let filerBuf = win.buffer
    check win.modeState.kind == mskFiler

    discard e.processResult(
      HandlerResult(kind: hrFilerOpenFile, filerFilePath: target), e.activeBuffer()
    )
    check win.mode == EditorMode.Normal
    check e.state.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.buffer != filerBuf
    check win.buffer.filePath.get == target

suite "Viewer round-trip - BufferManager":
  test "hrBufferManagerSelectBuffer leaves the listing buffer behind":
    let (e, path) = editorOnFile("moe_rt_bm_select_a.txt")
    let other = getTempDir() / "moe_rt_bm_select_b.txt"
    writeFile(other, "other\n")
    defer:
      removeFile(path)
      removeFile(other)
    discard e.editFile(other)
    let win = e.activeWindow
    e.placeOrigin(line = 0, column = 0, topLine = 0, leftColumn = 0)

    var targetIndex = -1
    for i, buf in e.buffers:
      if buf.filePath == some(path):
        targetIndex = i
    check targetIndex >= 0

    discard e.processResult(HandlerResult(kind: hrEnterBufferManager), e.activeBuffer())
    let listingBuf = win.buffer
    check win.modeState.kind == mskBufferManager

    discard e.processResult(
      HandlerResult(kind: hrBufferManagerSelectBuffer, selectBufferIndex: targetIndex),
      e.activeBuffer(),
    )
    check win.mode == EditorMode.Normal
    check e.state.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.buffer != listingBuf
    check win.buffer.filePath.get == path

suite "Viewer round-trip - BookmarkManager":
  test "hrEnterBookmarkManager resets leftColumn on entry":
    # The dead second entry copy omitted `viewport.leftColumn = 0`, so a
    # horizontally scrolled window kept its offset while showing the listing.
    # The single entry point resets it and restores it on quit.
    let (e, path) = editorOnFile("moe_rt_bkm_transition.txt")
    defer:
      removeFile(path)
    let win = e.activeWindow
    let origBuf = win.buffer
    e.placeOrigin(line = 7, column = 3, topLine = 6, leftColumn = 1)

    discard
      e.processResult(HandlerResult(kind: hrEnterBookmarkManager), e.activeBuffer())
    check win.mode == EditorMode.BookmarkManager
    check win.modeState.kind == mskBookmarkManager
    check win.buffer != origBuf
    check win.cursor.line == 0
    check win.cursor.column == 0
    check win.viewport.topLine == 0
    check win.viewport.leftColumn == 0

    discard
      e.processResult(HandlerResult(kind: hrBookmarkManagerQuit), e.activeBuffer())
    check win.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.buffer == origBuf
    check win.cursor.line == 7
    check win.cursor.column == 3
    check win.viewport.topLine == 6
    check win.viewport.leftColumn == 1

  test "hrBookmarkManagerJump leaves the listing buffer behind":
    let (e, path) = editorOnFile("moe_rt_bkm_jump.txt")
    defer:
      removeFile(path)
    let win = e.activeWindow
    let origBuf = win.buffer
    origBuf.toggleBookmark(8)
    e.placeOrigin(line = 0, column = 0, topLine = 0, leftColumn = 0)

    discard
      e.processResult(HandlerResult(kind: hrEnterBookmarkManager), e.activeBuffer())
    let listingBuf = win.buffer
    check win.modeState.kind == mskBookmarkManager

    discard e.processResult(
      HandlerResult(
        kind: hrBookmarkManagerJump,
        bookmarkJumpBufferId: origBuf.id,
        bookmarkJumpLine: 8,
      ),
      e.activeBuffer(),
    )
    check win.mode == EditorMode.Normal
    check e.state.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.buffer == origBuf
    check win.buffer != listingBuf
    check win.cursor.line == 8

suite "Viewer round-trip - References":
  test "handleLspLocations entry + hrReferencesQuit restores cursor/viewport/buffer":
    let (e, path) = editorOnFile("moe_rt_refs_quit.txt")
    defer:
      removeFile(path)
    let win = e.activeWindow
    let origBuf = win.buffer
    e.placeOrigin(line = 6, column = 1, topLine = 5, leftColumn = 2)

    check e.handleLspLocations(
      @[makeLocation(path, 1), makeLocation(path, 3)], "References", "Reference"
    )
    check win.mode == EditorMode.References
    check win.modeState.kind == mskReferences
    check win.buffer != origBuf
    check win.cursor.line == 0
    check win.cursor.column == 0
    check win.viewport.topLine == 0
    check win.viewport.leftColumn == 0

    # Operate inside the viewer.
    win.cursor.line = 1
    win.viewport.topLine = 1

    discard e.processResult(HandlerResult(kind: hrReferencesQuit), e.activeBuffer())
    check win.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.buffer == origBuf
    check win.cursor.line == 6
    check win.cursor.column == 1
    check win.viewport.topLine == 5
    check win.viewport.leftColumn == 2

  test "hrReferencesJumpTo anchors the jump list at the origin cursor":
    # Recorded from the pre-viewer position, not the listing selection, so
    # Ctrl-o returns to the editing spot.
    let (e, path) = editorOnFile("moe_rt_refs_jump.txt")
    defer:
      removeFile(path)
    let win = e.activeWindow
    let origBuf = win.buffer
    e.placeOrigin(line = 6, column = 1, topLine = 5, leftColumn = 2)

    check e.handleLspLocations(
      @[makeLocation(path, 1), makeLocation(path, 3)], "References", "Reference"
    )
    win.cursor.line = 1

    discard e.processResult(
      HandlerResult(kind: hrReferencesJumpTo, jumpToPath: path, jumpToLine: 3),
      e.activeBuffer(),
    )
    check win.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.buffer == origBuf
    check win.cursor.line == 3
    check e.state.jumpList.list.len > 0
    check e.state.jumpList.list[^1].line == 6
    check e.state.jumpList.list[^1].column == 1

suite "Viewer round-trip - DocumentSymbol":
  test "poll entry + hrDocumentSymbolQuit restores cursor/viewport/buffer":
    let (e, path) = editorOnFile("moe_rt_symbols_quit.nim")
    defer:
      removeFile(path)
    e.lsp.enabled = true
    let win = e.activeWindow
    let origBuf = win.buffer
    e.placeOrigin(line = 4, column = 2, topLine = 3, leftColumn = 1)

    let reqId = 7001
    e.injectPending(lrfDocumentSymbol, reqId)
    e.injectLspResponse(reqId, documentSymbolsResponseJson(@["alpha", "beta"]))
    e.pollLspDocumentSymbols()

    check win.mode == EditorMode.DocumentSymbol
    check win.modeState.kind == mskDocumentSymbol
    check win.buffer != origBuf
    check win.cursor.line == 0
    check win.viewport.topLine == 0
    check win.viewport.leftColumn == 0

    # Operate inside the viewer.
    win.cursor.line = 1
    win.viewport.topLine = 1

    discard e.processResult(HandlerResult(kind: hrDocumentSymbolQuit), e.activeBuffer())
    check win.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.buffer == origBuf
    check win.cursor.line == 4
    check win.cursor.column == 2
    check win.viewport.topLine == 3
    check win.viewport.leftColumn == 1

  test "hrDocumentSymbolJumpTo anchors the jump list at the origin cursor":
    let (e, path) = editorOnFile("moe_rt_symbols_jump.nim")
    defer:
      removeFile(path)
    e.lsp.enabled = true
    let win = e.activeWindow
    let origBuf = win.buffer
    e.placeOrigin(line = 4, column = 2, topLine = 3, leftColumn = 1)

    let reqId = 7002
    e.injectPending(lrfDocumentSymbol, reqId)
    e.injectLspResponse(reqId, documentSymbolsResponseJson(@["alpha", "beta"]))
    e.pollLspDocumentSymbols()
    check win.modeState.kind == mskDocumentSymbol
    win.cursor.line = 1

    discard e.processResult(
      HandlerResult(kind: hrDocumentSymbolJumpTo, symbolLine: 7, symbolColumn: 0),
      e.activeBuffer(),
    )
    check win.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.buffer == origBuf
    check win.cursor.line == 7
    check e.state.jumpList.list.len > 0
    check e.state.jumpList.list[^1].line == 4
    check e.state.jumpList.list[^1].column == 2

suite "Viewer round-trip - CallHierarchy":
  test "poll entry + hrCallHierarchyQuit restores cursor/viewport/buffer":
    let (e, path) = editorOnFile("moe_rt_ch_quit.nim")
    defer:
      removeFile(path)
    e.lsp.enabled = true
    let win = e.activeWindow
    let origBuf = win.buffer
    e.placeOrigin(line = 5, column = 3, topLine = 4, leftColumn = 2)

    let reqId = 7101
    e.injectPending(lrfCallHierarchyIncoming, reqId)
    e.injectLspResponse(
      reqId,
      incomingCallsResponseJson(@[makeCallHierarchyItem("caller", "file://" & path, 2)]),
    )
    e.pollLspCallHierarchy()

    check win.mode == EditorMode.CallHierarchy
    check win.modeState.kind == mskCallHierarchy
    check win.buffer != origBuf
    check win.cursor.line == 0
    check win.viewport.topLine == 0
    check win.viewport.leftColumn == 0

    discard e.processResult(HandlerResult(kind: hrCallHierarchyQuit), e.activeBuffer())
    check win.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.buffer == origBuf
    check win.cursor.line == 5
    check win.cursor.column == 3
    check win.viewport.topLine == 4
    check win.viewport.leftColumn == 2

  test "incoming -> outgoing re-entry keeps the first origin for the quit":
    # Switching the view kind re-enters the mode: the second entry must carry
    # the origin over instead of snapshotting the listing position.
    let (e, path) = editorOnFile("moe_rt_ch_reenter.nim")
    defer:
      removeFile(path)
    e.lsp.enabled = true
    let win = e.activeWindow
    let origBuf = win.buffer
    e.placeOrigin(line = 5, column = 3, topLine = 4, leftColumn = 2)

    let incomingId = 7102
    e.injectPending(lrfCallHierarchyIncoming, incomingId)
    e.injectLspResponse(
      incomingId,
      incomingCallsResponseJson(@[makeCallHierarchyItem("caller", "file://" & path, 2)]),
    )
    e.pollLspCallHierarchy()
    check win.modeState.kind == mskCallHierarchy
    win.cursor.line = 1

    let outgoingId = 7103
    e.injectPending(lrfCallHierarchyOutgoing, outgoingId, isItemDriven = true)
    e.injectLspResponse(
      outgoingId,
      outgoingCallsResponseJson(@[makeCallHierarchyItem("callee", "file://" & path, 4)]),
    )
    e.pollLspCallHierarchy()
    check win.modeState.kind == mskCallHierarchy
    check win.modeState.callHierarchy.viewKind == chvkOutgoing
    check win.originalBuffer == origBuf

    discard e.processResult(HandlerResult(kind: hrCallHierarchyQuit), e.activeBuffer())
    check win.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.buffer == origBuf
    check win.cursor.line == 5
    check win.cursor.column == 3
    check win.viewport.topLine == 4
    check win.viewport.leftColumn == 2

suite "Viewer round-trip - split-window viewers":
  # These modes do not swap the window buffer, so the round-trip contract is
  # about the window list: the split disappears, its scratch buffer is evicted,
  # and the origin window is active again with buffer and cursor untouched.
  proc checkSplitClosed(
      e: Editor, origWin: EditorWindow, origBuf: TextBuffer, windowsBefore: int
  ) =
    check e.windowManager.windows.len == windowsBefore
    check e.activeWindow == origWin
    check e.activeWindow.buffer == origBuf
    check e.activeWindow.cursor.line == 5
    check e.activeWindow.cursor.column == 2
    check e.activeWindow.modeState.kind == mskNone

  test "hrEnterLogViewer + hrLogViewerQuit closes the split":
    let (e, path) = editorOnFile("moe_rt_logviewer.txt")
    defer:
      removeFile(path)
    let origWin = e.activeWindow
    let origBuf = origWin.buffer
    let windowsBefore = e.windowManager.windows.len
    e.placeOrigin(line = 5, column = 2, topLine = 4, leftColumn = 3)

    discard e.processResult(HandlerResult(kind: hrEnterLogViewer), e.activeBuffer())
    check e.windowManager.windows.len == windowsBefore + 1
    check e.state.mode == EditorMode.LogViewer
    check e.activeWindow.mode == EditorMode.LogViewer
    check e.activeWindow.modeState.kind == mskLogViewer
    check e.activeWindow.modeState.logViewer.contentKind == lckEditor
    let scratchId = e.activeWindow.buffer.id

    discard e.processResult(HandlerResult(kind: hrLogViewerQuit), e.activeBuffer())
    check e.state.mode == EditorMode.Normal
    e.checkSplitClosed(origWin, origBuf, windowsBefore)
    check e.bufferById(scratchId).isNone

  test "hrLspLog opens the same viewer with the LSP content kind":
    let (e, path) = editorOnFile("moe_rt_lsplog.txt")
    defer:
      removeFile(path)
    let origWin = e.activeWindow
    let origBuf = origWin.buffer
    let windowsBefore = e.windowManager.windows.len
    e.placeOrigin(line = 5, column = 2, topLine = 4, leftColumn = 3)

    discard e.processResult(HandlerResult(kind: hrLspLog), e.activeBuffer())
    check e.activeWindow.modeState.kind == mskLogViewer
    check e.activeWindow.modeState.logViewer.contentKind == lckLsp

    discard e.processResult(HandlerResult(kind: hrLogViewerQuit), e.activeBuffer())
    e.checkSplitClosed(origWin, origBuf, windowsBefore)

  test "hrEnterBackupManager + hrBackupManagerQuit closes the split":
    let (e, path) = editorOnFile("moe_rt_backupmanager.txt")
    defer:
      removeFile(path)
    let origWin = e.activeWindow
    let origBuf = origWin.buffer
    let windowsBefore = e.windowManager.windows.len
    e.placeOrigin(line = 5, column = 2, topLine = 4, leftColumn = 3)

    discard e.processResult(HandlerResult(kind: hrEnterBackupManager), e.activeBuffer())
    check e.windowManager.windows.len == windowsBefore + 1
    check e.state.mode == EditorMode.BackupManager
    check e.activeWindow.mode == EditorMode.BackupManager
    check e.activeWindow.modeState.kind == mskBackupManager
    let scratchId = e.activeWindow.buffer.id

    discard e.processResult(HandlerResult(kind: hrBackupManagerQuit), e.activeBuffer())
    check e.state.mode == EditorMode.Normal
    e.checkSplitClosed(origWin, origBuf, windowsBefore)
    check e.bufferById(scratchId).isNone

  test "hrConfig + hrConfigQuit restores the mode Config was opened from":
    # Config is the one split viewer whose exit restores the mode it was opened
    # from instead of Normal. The return mode is captured on the origin window
    # before the vsplit, so it is the real prior mode and not the fresh split
    # window's (always Normal).
    let (e, path) = editorOnFile("moe_rt_config.txt")
    defer:
      removeFile(path)
    let origWin = e.activeWindow
    let origBuf = origWin.buffer
    let windowsBefore = e.windowManager.windows.len
    e.placeOrigin(line = 5, column = 2, topLine = 4, leftColumn = 3)
    e.setMode(EditorMode.Visual)

    discard e.processResult(HandlerResult(kind: hrConfig), e.activeBuffer())
    check e.windowManager.windows.len == windowsBefore + 1
    check e.state.mode == EditorMode.Config
    check e.activeWindow != origWin
    check e.activeWindow.modeState.kind == mskConfig
    check e.state.previousMode == EditorMode.Visual
    check origWin.mode == EditorMode.Visual

    discard e.processResult(HandlerResult(kind: hrConfigQuit), e.activeBuffer())
    check e.state.mode == EditorMode.Visual
    check e.windowManager.windows.len == windowsBefore
    check e.activeWindow == origWin
    check e.activeWindow.buffer == origBuf
    check e.activeWindow.modeState.kind == mskNone

  test "hrDebug opens the debug split and registers its auto-refresh buffer":
    # Debug has no live quit result (hrDebugViewerQuit only reaches
    # processResult defensively), so only the entry half is pinned.
    let (e, path) = editorOnFile("moe_rt_debug.txt")
    defer:
      removeFile(path)
    let windowsBefore = e.windowManager.windows.len

    discard e.processResult(HandlerResult(kind: hrDebug), e.activeBuffer())
    check e.windowManager.windows.len == windowsBefore + 1
    check e.state.mode == EditorMode.Debug
    check e.activeWindow.modeState.kind == mskDebug
    check e.state.windowDisplay.debugBuffer == e.activeWindow.buffer
    check e.state.timing.debugUpdateInterval > 0

suite "Viewer round-trip - FileTree":
  test "hrEnterFileTree + hrFileTreeQuit drops the window and its fixed width":
    # clearModeState releases the window's fixedWidth for FileTree; a shared
    # exit helper must keep doing it or the layout reserves the column forever.
    let (e, path) = editorOnFile("moe_rt_filetree_quit.txt")
    defer:
      removeFile(path)
    let origWin = e.activeWindow
    let origBuf = origWin.buffer
    let windowsBefore = e.windowManager.windows.len

    discard e.processResult(HandlerResult(kind: hrEnterFileTree), e.activeBuffer())
    check e.windowManager.windows.len == windowsBefore + 1
    # The sidebar opens without stealing focus.
    var treeIdx = -1
    for i, win in e.windowManager.windows:
      if win.mode == EditorMode.FileTree:
        treeIdx = i
    check treeIdx >= 0
    let treeWin = e.windowManager.windows[treeIdx]
    check treeWin.modeState.kind == mskFileTree
    check treeWin.fixedWidth.isSome

    # hrFileTreeQuit acts on the active window, and is only produced while the
    # sidebar has focus.
    e.windowManager.activateWindow(treeIdx)
    e.syncActiveWindow()

    discard e.processResult(HandlerResult(kind: hrFileTreeQuit), e.activeBuffer())
    check e.windowManager.windows.len == windowsBefore
    check treeWin.modeState.kind == mskNone
    check treeWin.fixedWidth.isNone
    check e.activeWindow == origWin
    check e.activeWindow.buffer == origBuf

  test "hrEnterFileTree twice toggles the sidebar back off":
    let (e, path) = editorOnFile("moe_rt_filetree_toggle.txt")
    defer:
      removeFile(path)
    let windowsBefore = e.windowManager.windows.len

    discard e.processResult(HandlerResult(kind: hrEnterFileTree), e.activeBuffer())
    check e.windowManager.windows.len == windowsBefore + 1

    discard e.processResult(HandlerResult(kind: hrEnterFileTree), e.activeBuffer())
    check e.windowManager.windows.len == windowsBefore
    for win in e.windowManager.windows:
      check win.mode != EditorMode.FileTree
      check win.modeState.kind != mskFileTree

suite "Viewer round-trip - nested entry":
  test "entering a second viewer from inside one keeps the editing buffer":
    # enterViewerMode tears a live viewer down before taking its own snapshot,
    # so the stashed original is the file buffer and never the outer listing.
    let (e, path) = editorOnFile("moe_rt_nested_entry.txt")
    defer:
      removeFile(path)
    let win = e.activeWindow
    let origBuf = win.buffer
    e.placeOrigin(line = 5, column = 2, topLine = 4, leftColumn = 3)
    clearMessageLog()

    discard e.processResult(HandlerResult(kind: hrEnterFiler), e.activeBuffer())
    let filerBuf = win.buffer
    check filerBuf != origBuf

    discard e.processResult(HandlerResult(kind: hrEnterBufferManager), e.activeBuffer())
    check win.modeState.kind == mskBufferManager
    check win.originalBuffer == origBuf

    discard e.processResult(HandlerResult(kind: hrBufferManagerQuit), e.activeBuffer())
    check win.mode == EditorMode.Normal
    check win.modeState.kind == mskNone
    check win.buffer == origBuf
    # The origin captured by the outer viewer survives the hand-off.
    check win.cursor.line == 5
    check win.cursor.column == 2
    check win.viewport.topLine == 4
    check win.viewport.leftColumn == 3

    for m in getMessageLog():
      check not m.startsWith("saveOriginalBuffer: overwriting existing originalBuffer")

  test "a split viewer opened from inside one leaves the origin window usable":
    # A split takes a *new* window, so the viewer live in the origin window is
    # none of its business. Tearing that one down would reset its mode state
    # while its mode stayed put, and every key afterwards would be rejected.
    let (e, path) = editorOnFile("moe_rt_split_over_inplace.txt")
    defer:
      removeFile(path)
    let originWin = e.activeWindow

    discard e.processResult(HandlerResult(kind: hrEnterFiler), e.activeBuffer())
    check originWin.modeState.kind == mskFiler
    let filerBuf = originWin.buffer

    discard e.processResult(HandlerResult(kind: hrEnterHelpViewer), e.activeBuffer())
    check e.activeWindow != originWin
    check originWin.mode == EditorMode.Filer
    check originWin.modeState.kind == mskFiler
    check originWin.buffer == filerBuf

    discard e.processResult(HandlerResult(kind: hrHelpViewerQuit), e.activeBuffer())
    check e.activeWindow == originWin
    check e.state.mode == EditorMode.Filer
    check e.activeWindow.modeState.kind == mskFiler

  test "a viewer entered in place restores the wrap sub-line it displaced":
    let (e, path) = editorOnFile("moe_rt_wrap_offset.txt")
    defer:
      removeFile(path)
    let win = e.activeWindow
    e.placeOrigin(line = 5, column = 2, topLine = 4, leftColumn = 3)
    win.viewport.topWrapOffset = 2

    discard e.processResult(HandlerResult(kind: hrEnterFiler), e.activeBuffer())
    check win.viewport.topWrapOffset == 0

    discard e.processResult(HandlerResult(kind: hrFilerQuit), e.activeBuffer())
    check win.viewport.topLine == 4
    check win.viewport.topWrapOffset == 2

  test "the filer resolves its directory from the file, not the outer listing":
    # The buffer live in the window is the outer viewer's generated listing and
    # has no file path; the directory must come from the file underneath it.
    let (e, path) = editorOnFile("moe_rt_filer_start_path.txt")
    defer:
      removeFile(path)
    let win = e.activeWindow

    discard e.processResult(HandlerResult(kind: hrEnterBufferManager), e.activeBuffer())
    check win.buffer.filePath.isNone

    discard e.processResult(HandlerResult(kind: hrEnterFiler), e.activeBuffer())
    check win.modeState.kind == mskFiler
    check win.modeState.filer.currentPath == parentDir(path)

  test "an in-place viewer opened from a split one takes over the window left":
    # Tearing the split viewer down closes the window it was showing in, so the
    # in-place entry has to land on the window that survived. Writing it to the
    # closed one leaves the survivor mode-set with mskNone state, and every key
    # afterwards — `:` included — is rejected.
    let (e, path) = editorOnFile("moe_rt_inplace_over_split.txt")
    defer:
      removeFile(path)
    let originWin = e.activeWindow

    discard e.processResult(HandlerResult(kind: hrEnterHelpViewer), e.activeBuffer())
    check e.windowManager.windows.len == 2
    check e.activeWindow != originWin

    discard e.processResult(HandlerResult(kind: hrEnterFiler), e.activeBuffer())
    check e.windowManager.windows.len == 1
    check e.activeWindow == originWin
    check e.state.mode == EditorMode.Filer
    check originWin.mode == EditorMode.Filer
    check originWin.modeState.kind == mskFiler
    # Resolved from the file under the split, not from the help listing.
    check originWin.modeState.filer.currentPath == parentDir(path)

  test "hrEnterTerminal from an in-place viewer tears the viewer down first":
    # Otherwise the stranded viewerEntry/originalBuffer leak into the next
    # viewer entry as its origin, losing the file underneath.
    let (e, path) = editorOnFile("moe_rt_terminal_over_filer.txt")
    defer:
      removeFile(path)
    let win = e.activeWindow
    let originBuf = win.buffer

    discard e.processResult(HandlerResult(kind: hrEnterFiler), e.activeBuffer())
    check win.modeState.kind == mskFiler
    check win.viewerEntry.isSome
    check win.originalBuffer == originBuf

    discard e.processResult(
      HandlerResult(kind: hrEnterTerminal, enterTerminalCommand: "true"),
      e.activeBuffer(),
    )
    check win.viewerEntry.isNone
    # nil if PTY failed, terminal buffer if it started — never the file.
    check (win.originalBuffer == nil or win.originalBuffer != originBuf)

suite "Viewer round-trip - teardown records":
  test "an overlay over a split viewer keeps that viewer's placement record":
    # The DiffViewer suspends the BackupManager underneath it. Its own teardown
    # must not consume the backup manager's placement record, or the split can
    # never be closed and its scratch buffer is orphaned.
    let (e, path) = editorOnFile("moe_rt_overlay_record.txt")
    defer:
      removeFile(path)
    let origWin = e.activeWindow
    let origBuf = origWin.buffer
    let windowsBefore = e.windowManager.windows.len
    let buffersBefore = e.buffers.len
    e.placeOrigin(line = 5, column = 2, topLine = 4, leftColumn = 3)

    discard e.processResult(HandlerResult(kind: hrEnterBackupManager), e.activeBuffer())
    let viewerWin = e.activeWindow
    check viewerWin.viewerEntry.isSome

    # Same overlay entry hrBackupManagerOpenDiff performs, without needing a
    # real backup on disk.
    viewerWin.saveOriginalBuffer()
    viewerWin.suspendMode()
    viewerWin.buffer = newTextBuffer("diff")
    viewerWin.modeState =
      ModeState(kind: mskDiffViewer, diffViewer: initDiffViewerState(path, path))
    viewerWin.mode = EditorMode.DiffViewer
    e.setMode(EditorMode.DiffViewer)

    discard e.processResult(HandlerResult(kind: hrDiffViewerQuit), e.activeBuffer())
    check e.activeWindow.mode == EditorMode.BackupManager
    check viewerWin.viewerEntry.isSome

    discard e.processResult(HandlerResult(kind: hrBackupManagerQuit), e.activeBuffer())
    check e.windowManager.windows.len == windowsBefore
    check e.activeWindow == origWin
    check e.activeWindow.buffer == origBuf
    check e.buffers.len == buffersBefore

  test "a regenerated listing does not orphan the buffer the split registered":
    # Refreshing swaps in a buffer that was never registered in Editor.buffers.
    # Exit must delete the one entry recorded on the way in.
    let (e, path) = editorOnFile("moe_rt_refresh_orphan.txt")
    defer:
      removeFile(path)
    let windowsBefore = e.windowManager.windows.len
    let buffersBefore = e.buffers.len

    discard e.processResult(HandlerResult(kind: hrEnterLogViewer), e.activeBuffer())
    let scratchId = e.activeWindow.buffer.id
    check e.bufferById(scratchId).isSome

    discard e.processResult(HandlerResult(kind: hrLogViewerRefresh), e.activeBuffer())
    check e.activeWindow.buffer.id != scratchId

    discard e.processResult(HandlerResult(kind: hrLogViewerQuit), e.activeBuffer())
    check e.windowManager.windows.len == windowsBefore
    check e.bufferById(scratchId).isNone
    check e.buffers.len == buffersBefore

  test "hrDebugViewerQuit closes the debug split":
    let (e, path) = editorOnFile("moe_rt_debug_quit.txt")
    defer:
      removeFile(path)
    let origWin = e.activeWindow
    let windowsBefore = e.windowManager.windows.len
    let buffersBefore = e.buffers.len

    discard e.processResult(HandlerResult(kind: hrDebug), e.activeBuffer())
    check e.activeWindow.modeState.kind == mskDebug
    let scratchId = e.activeWindow.buffer.id

    discard e.processResult(HandlerResult(kind: hrDebugViewerQuit), e.activeBuffer())
    check e.windowManager.windows.len == windowsBefore
    check e.activeWindow == origWin
    check e.state.mode == EditorMode.Normal
    check e.bufferById(scratchId).isNone
    check e.buffers.len == buffersBefore
