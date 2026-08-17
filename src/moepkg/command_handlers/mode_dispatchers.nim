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

## Mode-specific dispatchers
##
## Houses the per-mode dispatchers that translate sub-handler results into
## HandlerResult values. These are the non-recursive part of the dispatcher
## layer: each proc here calls into a single sub-handler and converts its
## result kind to a HandlerResult. The recursive cluster (Normal mode +
## handleKeyCombo + playbackMacro + checkRuntimeKeySeqMapping) lives in
## handler_manager.nim.
##
## dispatchSubStateMode is also kept here because it only forwards to the
## sub-state-mode dispatchers in this file.

import std/[options, strutils, unicode]

import pkg/[results, celina]

import
  ../[
    types, buffer, modes, key_bindings, keybind_config, string_builder, filer, filetree,
    diff_viewer, recent_file_mode, terminal_mode,
  ]
import ../lsp/protocol/types as lspTypes
import ../types/editor_types
# The per-mode key handlers this module forwards to come from handler_modules
# (the shared re-export surface). See handler_modules.nim for why the list is
# centralized there rather than duplicated per importer.
import handler_modules

proc extractInsertedText*(transaction: buffer.BufferTransaction): string =
  ## Extract net inserted text from a transaction
  ## Handles insertions and deletions (backspace during insert mode)
  ## Optimized with StringBuilder for O(n) instead of O(n²) performance
  ##
  ## Insert-mode backspace at a line start decomposes into ckDeleteLine plus
  ## ckInsertText, where the insert payload is the pre-existing content of the
  ## joined line — not user input. Skip that paired re-attach so it does not
  ## leak into lastEditCommand and get replayed by `.` (dot-repeat).
  var sb = newStringBuilder()
  var skipNextInsertText = false
  for change in transaction.changes:
    case change.kind
    of buffer.ckInsertText:
      if skipNextInsertText:
        skipNextInsertText = false
      else:
        sb.add(change.insertText)
    of buffer.ckDeleteText:
      # Backspace - remove from end of accumulated text
      sb.removeLast(change.deletedText.len)
      skipNextInsertText = false
    of buffer.ckInsertLine:
      # Line insertion - add the line text
      sb.add(change.insertLineText)
      # Ensure it ends with newline if it doesn't already
      if change.insertLineText.len == 0 or change.insertLineText[^1] != '\n':
        sb.add("\n")
      skipNextInsertText = false
    of buffer.ckDeleteLine:
      # Line deletion during insert mode: the paired ckInsertText that follows
      # is a line-join re-attach, not user input. Clear accumulated text and
      # arm the skip for the immediate next ckInsertText — but only when the
      # deleted line had content, since joining an empty line omits the
      # re-attach entirely (insertText no-ops on ""), and the next
      # ckInsertText would then be real typing.
      sb.clear()
      skipNextInsertText = change.deletedLineText.len > 0
    of buffer.ckDeleteRange:
      # Range deletion - remove from end of accumulated text
      sb.removeLast(change.deletedRangeText.len)
      skipNextInsertText = false
    of buffer.ckReplaceLine:
      discard # Line replacement doesn't contribute to inserted text tracking
      skipNextInsertText = false
    of buffer.ckSnapshot:
      discard # Snapshots don't contribute to inserted text tracking
      skipNextInsertText = false
    of buffer.ckTransaction:
      # Nested transaction - recursively extract text
      let nestedTransaction = buffer.BufferTransaction(
        changes: change.transactionChanges,
        description: change.transactionDescription,
        startSeq: 0,
      )
      sb.add(extractInsertedText(nestedTransaction))
      skipNextInsertText = false
  return sb.toString()

proc typedTextInRange(buffer: TextBuffer, startPos, endPos: BufferPosition): string =
  ## Text typed in the half-open range [startPos, endPos), where endPos is the
  ## cursor sitting one rune past the last inserted character. Returns "" when
  ## the cursor is not strictly ahead of startPos (e.g. everything backspaced).
  if endPos.line < startPos.line or
      (endPos.line == startPos.line and endPos.column <= startPos.column):
    return ""
  # getTextInRange is inclusive on both ends, so step the end back one rune.
  let endIncl =
    if endPos.column > 0:
      BufferPosition(line: endPos.line, column: endPos.column - 1)
    else:
      # Cursor at column 0: the last typed rune is the newline that ended the
      # previous line; getTextInRange includes it when endCol reaches line end.
      BufferPosition(
        line: endPos.line - 1, column: buffer.getLine(endPos.line - 1).charLen
      )
  buffer.getTextInRange(startPos, endIncl)

proc advancePastText(pos: BufferPosition, text: string): BufferPosition =
  ## Cursor position after inserting `text` at `pos` (column is a rune index).
  result = pos
  for r in text.runes:
    if r == Rune('\n'):
      result.line.inc
      result.column = 0
    else:
      result.column.inc

proc replayCountedInsert(buffer: TextBuffer, state: EditorState) =
  ## Replay the just-typed text (count - 1) more times for [count]i/a/I/A/o/O,
  ## matching Vim. Runs while the Insert transaction is still open so every
  ## repeat shares one undo group, and before the cursor is pulled back into
  ## Normal mode. No-op for substitute inserts (s/S/cc), which use the count to
  ## drive their own delete and never set insertReplayCount. Visual-block insert
  ## likewise never carries a replay count, and its context is already cleared by
  ## the caller before we run, so no guard for it is needed here.
  let count = state.editState.insertReplayCount
  if count <= 1 or state.editState.insertModeStartPos.isNone or
      state.editState.substituteContext.isSome:
    return

  let startPos = state.editState.insertModeStartPos.get
  var cursor = state.cursor
  let typed = typedTextInRange(buffer, startPos, cursor)
  if typed.len == 0:
    return

  var unit = typed
  if state.editState.insertReplayLineEntry:
    # o/O opened the first line already; each repeat opens another line that
    # carries the entry line's indentation.
    let entryLine = buffer.getLine(startPos.line)
    let indentLen = min(startPos.column, entryLine.charLen)
    unit = "\n" & entryLine.runeSubStr(0, indentLen) & typed

  for _ in 1 ..< count:
    if buffer.insertText(cursor, unit).isErr:
      break
    cursor = advancePastText(cursor, unit)
  state.cursor = cursor

proc finalizeInsertExit(
    buffer: TextBuffer, state: EditorState
): Result[string, string] =
  ## Shared leaving-Insert cleanup: snippet/auto-indent teardown, `.`-repeat +
  ## `[count]i` bookkeeping, visual-block replication, insert-state reset, and
  ## transaction commit. Called by both the Escape path and the imap ->
  ## Command-mode alias bridge so the bridge does not skip the cleanup.
  ##
  ## ok carries a non-fatal warning to surface (empty when clean): the
  ## transaction is committed at that point, so the message must not block the
  ## mode transition or a pending aliased command. err is a fatal commit
  ## failure.
  state.snippetSession.active = false

  clearAutoIndentIfUnedited(buffer, state)

  var replicationError = ""

  if buffer.currentTransaction.isSome and state.editState.insertModeStartPos.isSome:
    let transaction = buffer.currentTransaction.get
    let insertedText = extractInsertedText(transaction)

    if state.editState.visualBlockInsertContext.isSome:
      if insertedText.len > 0:
        let ctx = state.editState.visualBlockInsertContext.get
        for lineNum in (ctx.startLine + 1) .. min(ctx.endLine, buffer.len - 1):
          let lineCharLen = buffer.getLine(lineNum).runeLen
          let col = ctx.insertColumn
          if col > lineCharLen:
            let padding = ' '.repeat(col - lineCharLen)
            let padResult = buffer.insertText(
              BufferPosition(line: lineNum, column: lineCharLen), padding
            )
            if padResult.isErr:
              replicationError = padResult.error
              break
          let replayResult =
            buffer.insertText(BufferPosition(line: lineNum, column: col), insertedText)
          if replayResult.isErr:
            replicationError = replayResult.error
            break
      state.editState.visualBlockInsertContext = none(types.VisualBlockInsertContext)

    if insertedText.len > 0:
      if state.editState.substituteContext.isSome:
        let subCtx = state.editState.substituteContext.get
        state.editState.lastEditCommand = some(
          types.LastEditCommand(
            kind: types.lecSubstitute,
            substituteText: insertedText,
            substituteCount: subCtx.deleteCount,
            substituteKind: subCtx.kind,
          )
        )
      else:
        state.editState.lastEditCommand = some(
          types.LastEditCommand(
            kind: types.lecInsertText,
            insertedText: insertedText,
            insertPosition: state.editState.insertModeStartPos.get,
          )
        )

    # Replay before commit so [count]i repeats share the same undo group.
    replayCountedInsert(buffer, state)

    state.editState.insertModeStartPos = none(BufferPosition)
    state.editState.insertReplayCount = 0
    state.editState.insertReplayLineEntry = false
    state.editState.substituteContext = none(types.SubstituteContext)

  if buffer.inTransaction:
    let transactionResult = buffer.commitTransaction()
    if transactionResult.isErr:
      return err("Failed to commit transaction: " & transactionResult.error)

  if replicationError.len > 0:
    # A replication edit failed partway; the transaction was still committed
    # above (rolling the session back would also lose the user's typed text),
    # so report the partial replication after the commit as a warning only.
    return ok("Failed to replicate visual block insert: " & replicationError)

  ok("")

proc handleInsertMode*(
    manager: HandlerManager, editor: Editor, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Insert mode input
  let buffer = editor.activeBuffer
  let state = editor.state
  let r = manager.insertHandler.handleInsertModeKey(buffer, state, keyCombo)
  case r.kind
  of imrHandled:
    # Check if we're leaving Insert mode
    if r.modeTransition.isSome and r.modeTransition.get != EditorMode.Insert:
      # Ctrl-o (insert-normal mode): skip transaction commit/cleanup,
      # keep insert state intact so we can resume after one Normal command
      if state.insertNormalMode:
        return HandlerResult(
          kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
        )

      let finalizeResult = finalizeInsertExit(buffer, state)
      # Even on failure, allow mode transition so user isn't stuck in Insert
      # mode. A committed replication warning (ok with a message) surfaces the
      # same way.
      return HandlerResult(
        kind: hrHandled,
        modeTransition: r.modeTransition,
        statusMessage:
          if finalizeResult.isErr: finalizeResult.error else: finalizeResult.get,
      )
    return HandlerResult(
      kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
    )
  of imrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of imrExecCommand:
    # `imap K = "bdelete"` bridge: run the full leaving-Insert finalize so
    # `.` repeat, `[count]i` replay, and substituteContext / block-insert
    # cleanup all fire before the aliased command runs.
    let finalizeResult = finalizeInsertExit(buffer, state)
    if finalizeResult.isErr:
      return HandlerResult(kind: hrError, errorMessage: finalizeResult.error)
    if finalizeResult.get.len > 0:
      # Committed with a partial-replication warning: surface it but run the
      # alias anyway. The session is already finalized, and aborting here would
      # leave Insert mode without a transaction.
      state.statusMessage = finalizeResult.get
    return HandlerResult(
      kind: hrExecCommand, execCommandText: r.execCommandText, execCommandCount: 1
    )
  of imrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleCommandMode*(
    manager: HandlerManager,
    buffer: TextBuffer,
    commandText: string,
    isSharedBuffer: bool = false,
    currentLine: int = 0,
    otherModifiedCount: int = 0,
): HandlerResult =
  ## Handle Command mode input (when Enter is pressed).
  ## isSharedBuffer: true if the buffer is shared across multiple windows.
  ## currentLine: 0-based cursor line, used for range substitution with '.'.
  ## otherModifiedCount: modified buffers other than `buffer` (for :qa).
  ## Map ops (hrMap*) need access to `manager.keyBindingRegistry`, so they are
  ## executed here and folded onto hrHandled/hrError; every other kind is
  ## returned as-is to the caller.
  let r = manager.commandHandler.handleCommandModeInput(
    buffer, commandText, isSharedBuffer, currentLine, otherModifiedCount
  )
  case r.kind
  of hrMapAdd:
    var firstError = ""
    var modeNames: seq[string] = @[]
    for mode in r.mapAddModes:
      let err = manager.keyBindingRegistry.addRuntimeMappingExpanded(
        mode, r.mapAddLhs, r.mapAddRhs, noremap = r.mapAddNoremap
      )
      if err.len > 0:
        if firstError.len == 0:
          firstError = err
      else:
        modeNames.add(modeLabel(mode))
    if firstError.len > 0:
      return HandlerResult(kind: hrError, errorMessage: firstError)
    let msg =
      "Mapped in " & modeNames.join(", ") & ": " & r.mapAddLhs & " -> " & r.mapAddRhs
    return HandlerResult(
      kind: hrHandled, modeTransition: some(EditorMode.Normal), statusMessage: msg
    )
  of hrMapRemove:
    var firstError = ""
    var modeNames: seq[string] = @[]
    for mode in r.mapRemoveModes:
      let err = manager.keyBindingRegistry.removeRuntimeMapping(mode, r.mapRemoveLhs)
      if err.len > 0:
        if firstError.len == 0:
          firstError = err
      else:
        modeNames.add(modeLabel(mode))
    if firstError.len > 0:
      return HandlerResult(kind: hrError, errorMessage: firstError)
    let msg = "Unmapped in " & modeNames.join(", ") & ": " & r.mapRemoveLhs
    return HandlerResult(
      kind: hrHandled, modeTransition: some(EditorMode.Normal), statusMessage: msg
    )
  of hrMapClear:
    var modeNames: seq[string] = @[]
    for mode in r.mapClearModes:
      manager.keyBindingRegistry.clearRuntimeMappings(mode)
      modeNames.add(modeLabel(mode))
    let msg = "Cleared " & modeNames.join(", ") & " mode mappings"
    return HandlerResult(
      kind: hrHandled, modeTransition: some(EditorMode.Normal), statusMessage: msg
    )
  of hrMapList:
    var lines: seq[string] = @[]
    for mode in r.mapListModes:
      let label = modeLabel(mode)
      for m in manager.keyBindingRegistry.listRuntimeMappings(mode, r.mapListPrefix):
        lines.add(label & "  " & m)
    let msg =
      if lines.len > 0:
        lines.join("\n")
      elif r.mapListPrefix.len > 0:
        "No mapping found: " & r.mapListPrefix
      else:
        "No mapping"
    return HandlerResult(
      kind: hrHandled, modeTransition: some(EditorMode.Normal), statusMessage: msg
    )
  else:
    return r

proc handleVisualMode*(
    manager: HandlerManager, editor: Editor, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Visual mode input
  let buffer = editor.activeBuffer
  let state = editor.state
  let r =
    manager.visualHandler.handleVisualModeKey(buffer, state, editor.viewport, keyCombo)
  case r.kind
  of vmrHandled:
    # Check if we're entering Insert mode (e.g., visual block I command)
    if r.modeTransition.isSome and r.modeTransition.get == EditorMode.Insert:
      # Begin a transaction so commitTransaction() succeeds when leaving Insert mode
      # Guard: visualChange already commits its delete transaction, so don't double-begin
      if not buffer.inTransaction:
        let transactionResult = buffer.beginTransaction(
          "Visual to insert mode", cursorPos = some(state.cursor)
        )
        if transactionResult.isErr:
          return HandlerResult(
            kind: hrError,
            errorMessage: "Failed to begin transaction: " & transactionResult.error,
          )
      state.editState.insertModeStartPos = some(state.cursor)
    return HandlerResult(
      kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
    )
  of vmrWaitingForInput:
    # Waiting for additional character input (e.g., visual replace char)
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of vmrLspSelectionRange:
    # Execute LSP selection range
    return HandlerResult(kind: hrLspSelectionRange)
  of vmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of vmrExecCommand:
    # Command mode command alias bridge fired from a Visual mode
    # (`xnoremap K = "bdelete"`). Visual mode has no buffer transaction; just
    # forward the alias.
    return HandlerResult(
      kind: hrExecCommand, execCommandText: r.execCommandText, execCommandCount: 1
    )
  of vmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleReplaceMode*(
    manager: HandlerManager, editor: Editor, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Replace mode input
  let buffer = editor.activeBuffer
  let r = manager.replaceHandler.handleReplaceModeKey(buffer, editor.state, keyCombo)
  case r.kind
  of rmrHandled:
    # Check if we're leaving Replace mode
    if r.modeTransition.isSome and r.modeTransition.get != EditorMode.Replace:
      # Commit the transaction when leaving Replace mode
      let transactionResult = buffer.commitTransaction()
      if transactionResult.isErr:
        # Even if commit fails, allow mode transition so user isn't stuck in Replace mode
        return HandlerResult(
          kind: hrHandled,
          modeTransition: r.modeTransition,
          statusMessage: "Failed to commit transaction: " & transactionResult.error,
        )
    return HandlerResult(
      kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
    )
  of rmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of rmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleFilerMode*(
    manager: HandlerManager,
    filerState: FilerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Filer mode input
  let r = handleFilerModeKey(filerState, viewportHeight, keyCombo)
  case r.kind
  of frHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of frOpenFile:
    return HandlerResult(kind: hrFilerOpenFile, filerFilePath: r.filePath)
  of frOpenFileVSplit:
    return HandlerResult(kind: hrFilerOpenFileVSplit, filerFilePath: r.filePath)
  of frOpenFileHSplit:
    return HandlerResult(kind: hrFilerOpenFileHSplit, filerFilePath: r.filePath)
  of frOpenDirectory:
    # Directory navigation is handled within the filer state
    discard filerState.enterDirectory(r.dirPath)
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of frEnterCommand:
    # Enter command mode from filer
    state.input.commandText = ":"
    state.input.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of frDeleteFile:
    return HandlerResult(kind: hrFilerDeleteFile, filerDeletePath: r.deletePath)
  of frShowInfo:
    return HandlerResult(kind: hrFilerShowInfo, filerFileInfo: r.fileInfo)
  of frUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of frError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleFileTreeMode*(
    manager: HandlerManager,
    fileTreeState: FileTreeState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle FileTree mode input
  let r = handleFileTreeModeKey(fileTreeState, viewportHeight, keyCombo)

  # Transfer any error from fileTree operations to the status message
  if fileTreeState.lastError.len > 0:
    state.statusMessage = fileTreeState.lastError
    fileTreeState.lastError = ""
  elif fileTreeState.isSearching:
    # Display search prompt when there is no operation error to report.
    state.statusMessage = "/" & fileTreeState.searchText
  else:
    state.statusMessage = r.statusMessage

  case r.kind
  of ftrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of ftrOpenFile:
    return HandlerResult(kind: hrFileTreeOpenFile, fileTreeFilePath: r.filePath)
  of ftrEnterCommand:
    state.input.commandText = ":"
    state.input.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of ftrNextWindow:
    return HandlerResult(kind: hrNextWindow)
  of ftrPrevWindow:
    return HandlerResult(kind: hrPrevWindow)
  of ftrIncreaseWindowWidth:
    return HandlerResult(kind: hrIncreaseWindowWidth)
  of ftrDecreaseWindowWidth:
    return HandlerResult(kind: hrDecreaseWindowWidth)
  of ftrClearSearchHighlight:
    # Double-Escape: clear the persisted search highlight. FileTree search is
    # self-contained (its own match list, not the global hlsearch gate), so the
    # clear is applied here rather than through state.input.search.
    fileTreeState.clearSearch()
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of ftrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of ftrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleLogViewerMode*(
    manager: HandlerManager,
    logState: LogViewerState,
    buffer: TextBuffer,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Log Viewer mode input
  let r = handleLogViewerModeKey(logState, buffer, state, viewportHeight, keyCombo)
  case r.kind
  of lvrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of lvrEnterCommand:
    # Enter command mode from log viewer
    state.input.commandText = ":"
    state.input.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of lvrEnterSearchForward:
    # Enter search overlay (forward) from log viewer
    state.enterSearchOverlay(Forward)
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of lvrEnterSearchBackward:
    # Enter search overlay (backward) from log viewer
    state.enterSearchOverlay(Backward)
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of lvrEnterVisual:
    # Start a visual selection at the cursor and enter the requested Visual
    # variant. The log buffer stays readOnly, so destructive commands are
    # blocked in the command registry. `y` / Esc return via
    # `state.mode = state.previousMode` in the shared visual commands, which
    # falls back to LogViewer because processResult sets previousMode here.
    let targetMode =
      case r.visualKind
      of vskChar: EditorMode.Visual
      of vskLine: EditorMode.VisualLine
      of vskBlock: EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: state.cursor, current: state.cursor, active: true, kind: r.visualKind
    )
    return HandlerResult(
      kind: hrHandled, modeTransition: some(targetMode), statusMessage: ""
    )
  of lvrQuit:
    return HandlerResult(kind: hrLogViewerQuit)
  of lvrRefresh:
    return HandlerResult(kind: hrLogViewerRefresh)
  of lvrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of lvrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleReferencesMode*(
    manager: HandlerManager,
    refState: ReferencesViewerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle References Viewer mode input
  let r = handleReferencesModeKey(refState, viewportHeight, keyCombo)
  case r.kind
  of rvrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of rvrEnterCommand:
    # Enter command mode from references viewer
    state.input.commandText = ":"
    state.input.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of rvrJumpToReference:
    return HandlerResult(
      kind: hrReferencesJumpTo,
      jumpToPath: r.targetItem.path,
      jumpToLine: r.targetItem.line,
      jumpToColumn: r.targetItem.column,
    )
  of rvrQuit:
    return HandlerResult(kind: hrReferencesQuit)
  of rvrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of rvrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleDocumentSymbolMode*(
    manager: HandlerManager,
    symState: DocumentSymbolViewerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Document Symbol Viewer mode input
  let r = handleDocumentSymbolModeKey(symState, viewportHeight, keyCombo)
  case r.kind
  of dsvrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of dsvrEnterCommand:
    # Enter command mode from document symbol viewer
    state.input.commandText = ":"
    state.input.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of dsvrQuit:
    return HandlerResult(kind: hrDocumentSymbolQuit)
  of dsvrJumpToSymbol:
    return HandlerResult(
      kind: hrDocumentSymbolJumpTo,
      symbolLine: r.targetItem.line,
      symbolColumn: r.targetItem.column,
    )
  of dsvrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of dsvrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleCallHierarchyMode*(
    manager: HandlerManager,
    chState: CallHierarchyViewerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Call Hierarchy Viewer mode input
  let r = handleCallHierarchyModeKey(chState, viewportHeight, keyCombo)
  case r.kind
  of chvrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of chvrEnterCommand:
    # Enter command mode from call hierarchy viewer
    state.input.commandText = ":"
    state.input.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of chvrQuit:
    return HandlerResult(kind: hrCallHierarchyQuit)
  of chvrJumpToItem:
    return HandlerResult(
      kind: hrCallHierarchyJumpTo,
      callHierarchyJumpUri: r.targetItem.uri,
      callHierarchyJumpLine: r.targetItem.selectionRange.start.line,
      callHierarchyJumpColumn: r.targetItem.selectionRange.start.character,
    )
  of chvrRequestIncoming:
    return HandlerResult(
      kind: hrCallHierarchyRequestIncoming, callHierarchyIncomingItem: r.targetItem
    )
  of chvrRequestOutgoing:
    return HandlerResult(
      kind: hrCallHierarchyRequestOutgoing, callHierarchyOutgoingItem: r.targetItem
    )
  of chvrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of chvrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleHelpViewerMode*(
    manager: HandlerManager,
    helpState: HelpViewerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Help Viewer mode input
  let r = handleHelpViewerModeKey(helpState, viewportHeight, keyCombo)
  case r.kind
  of hvrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of hvrEnterCommand:
    # Enter command mode from help viewer
    state.input.commandText = ":"
    state.input.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of hvrEnterSearch:
    # Enter search mode (forward) from help viewer.
    # historyIndex/text/etc. are reset by enterSearchOverlay on transition.
    state.input.search.direction = Forward
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okSearch), statusMessage: ""
    )
  of hvrEnterSearchBackward:
    # Enter search mode (backward) from help viewer
    state.input.search.direction = Backward
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okSearch), statusMessage: ""
    )
  of hvrRepeatSearch:
    # n/N jumped to a match: re-enable the global hlsearch gate (like Vim's n
    # after :noh) so the highlight comes back across all windows/modes.
    state.input.search.hlsearchTempDisabled = false
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of hvrClearSearchHighlight:
    # Double-Escape: clear search highlight in help viewer
    state.input.search.hlsearchTempDisabled = true
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of hvrQuit:
    return HandlerResult(kind: hrHelpViewerQuit)
  of hvrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of hvrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleBufferManagerMode*(
    manager: HandlerManager,
    bmState: BufferManagerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Buffer Manager mode input
  let r = handleBufferManagerModeKey(bmState, viewportHeight, keyCombo)
  case r.kind
  of bmrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of bmrSelectBuffer:
    return
      HandlerResult(kind: hrBufferManagerSelectBuffer, selectBufferIndex: r.bufferIndex)
  of bmrDeleteBuffer:
    return HandlerResult(
      kind: hrBufferManagerDeleteBuffer, deleteBufferIdx: r.deleteBufferIndex
    )
  of bmrEnterCommand:
    # Enter command mode from buffer manager
    state.input.commandText = ":"
    state.input.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of bmrQuit:
    return HandlerResult(kind: hrBufferManagerQuit)
  of bmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of bmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleBookmarkManagerMode*(
    manager: HandlerManager,
    bmState: BookmarkManagerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Bookmark Manager mode input
  let r = handleBookmarkManagerModeKey(bmState, viewportHeight, keyCombo)
  case r.kind
  of bkmrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of bkmrJumpToBookmark:
    return HandlerResult(
      kind: hrBookmarkManagerJump,
      bookmarkJumpBufferId: r.jumpBufferId,
      bookmarkJumpLine: r.jumpLine,
    )
  of bkmrDeleteBookmark:
    return HandlerResult(
      kind: hrBookmarkManagerDelete, bookmarkDeleteEntryIndex: r.deleteEntryIndex
    )
  of bkmrEnterCommand:
    state.input.commandText = ":"
    state.input.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of bkmrQuit:
    return HandlerResult(kind: hrBookmarkManagerQuit)
  of bkmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of bkmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleBackupManagerMode*(
    manager: HandlerManager,
    bkState: BackupManagerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Backup Manager mode input
  let r = handleBackupManagerModeKey(bkState, viewportHeight, keyCombo)
  case r.kind
  of bkmrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of bkmrRestore:
    return
      HandlerResult(kind: hrBackupManagerRestore, restoreBackupIndex: r.restoreIndex)
  of bkmrDelete:
    return HandlerResult(kind: hrBackupManagerDelete, deleteBackupIndex: r.deleteIndex)
  of bkmrOpenDiff:
    return HandlerResult(kind: hrBackupManagerOpenDiff, diffBackupIndex: r.diffIndex)
  of bkmrRefresh:
    return HandlerResult(kind: hrBackupManagerRefresh)
  of bkmrEnterCommand:
    # Enter command mode from backup manager
    state.input.commandText = ":"
    state.input.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of bkmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of bkmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleDiffViewerMode*(
    manager: HandlerManager,
    diffState: DiffViewerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Diff Viewer mode input
  let r = handleDiffViewerModeKey(diffState, viewportHeight, keyCombo)
  case r.kind
  of dvrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of dvrEnterCommand:
    # Enter command mode from diff viewer
    state.input.commandText = ":"
    state.input.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of dvrQuit:
    return HandlerResult(kind: hrDiffViewerQuit)
  of dvrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of dvrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleConfigMode*(
    manager: HandlerManager,
    configState: ConfigModeState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Configuration mode input
  let r = handleConfigModeKey(configState, state, viewportHeight, keyCombo)
  case r.kind
  of cmrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of cmrEnterCommand:
    # Enter command mode from config mode
    state.input.commandText = ":"
    state.input.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of cmrEnterSearch:
    # Enter search mode (forward) from config mode.
    # historyIndex/text/etc. are reset by enterSearchOverlay on transition;
    # searchStartIndex is the config-specific anchor for the upcoming search.
    state.input.search.direction = Forward
    configState.searchStartIndex = configState.selectedIndex
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okSearch), statusMessage: ""
    )
  of cmrEnterSearchBackward:
    # Enter search mode (backward) from config mode
    state.input.search.direction = Backward
    configState.searchStartIndex = configState.selectedIndex
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okSearch), statusMessage: ""
    )
  of cmrRepeatSearch:
    # n/N jumped to a match: re-enable the global hlsearch gate (like Vim's n
    # after :noh) so the highlight comes back across all windows/modes.
    state.input.search.hlsearchTempDisabled = false
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of cmrClearSearchHighlight:
    # Double-Escape: clear search highlight. Disable the global hlsearch gate
    # so every window/mode (buffers, Help, other Config windows) hides matches.
    state.input.search.hlsearchTempDisabled = true
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of cmrSaveConfig:
    return HandlerResult(kind: hrConfigSaveConfig)
  of cmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of cmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleRecentFileMode*(
    manager: HandlerManager,
    state: RecentFileModeState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Recent File mode input
  let r = handleRecentFileModeKey(state, viewportHeight, keyCombo)
  case r.kind
  of rfmrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
    )
  of rfmrOpenFile:
    return HandlerResult(kind: hrRecentFileOpenFile, recentFilePath: r.filePath)
  of rfmrEnterCommand:
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of rfmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of rfmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleTerminalMode*(
    manager: HandlerManager,
    termState: TerminalState,
    state: EditorState,
    keyCombo: KeyCombo,
    window: EditorWindow,
): HandlerResult =
  ## Handle Terminal mode input
  let r = handleTerminalModeKey(termState, keyCombo)
  case r.kind
  of trHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of trSwitchToNormal:
    # Switch to Terminal-Normal sub-mode: snapshot grid to TextBuffer
    let snapshotBuffer = termState.enterNormalSubMode()
    window.buffer = snapshotBuffer
    window.cursor = BufferPosition(line: max(0, snapshotBuffer.len - 1), column: 0)
    window.viewport.resetViewportTop(
      max(0, snapshotBuffer.len - window.viewport.height)
    )
    return HandlerResult(
      kind: hrHandled,
      modeTransition: none(EditorMode),
      statusMessage: "-- TERMINAL NORMAL --",
    )
  of trReturnToInput:
    # Return to Terminal-Input sub-mode: restore placeholder buffer
    termState.exitNormalSubMode()
    window.buffer = newTextBuffer("")
    window.cursor = BufferPosition(line: 0, column: 0)
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of trEnterCommand:
    state.input.commandText = ":"
    state.input.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of trQuit:
    return HandlerResult(kind: hrTerminalQuit)
  of trUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of trError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

template dispatchSubState(
    variantKind: ModeStateKind,
    variantField: untyped,
    handlerProc: untyped,
    modeName: string,
): untyped {.dirty.} =
  ## Sub-state mode dispatcher helper. Expands to an early-return in the
  ## caller: forwards to `manager.handlerProc(...)` when the active
  ## window's ModeState variant matches `variantKind`, otherwise returns
  ## an `hrError` HandlerResult with the message
  ## "<modeName> state not initialized".
  ## Requires `manager`, `activeWindow`, `state`, `viewport`, `keyCombo`
  ## to be bound in the caller's scope. Marked `{.dirty.}` so that those
  ## names are resolved at the call site (avoids clashes with same-named
  ## procs such as `editor_types.activeWindow` and `worker.state`).
  if activeWindow.modeState.kind == variantKind:
    return manager.handlerProc(
      activeWindow.modeState.variantField, state, viewport.height, keyCombo
    )
  else:
    return
      HandlerResult(kind: hrError, errorMessage: modeName & " state not initialized")

proc dispatchSubStateMode*(
    manager: HandlerManager, editor: Editor, keyCombo: KeyCombo
): HandlerResult =
  ## Dispatch sub-state modes — modes that carry their own per-window state
  ## object on `EditorWindow` (via the `modeState` variant). Called from the
  ## Editor-based handleKeyCombo for any mode it does not handle directly.
  ##
  ## 11 sub-state modes (Filer, FileTree, Help, BufferManager, BookmarkManager,
  ## BackupManager, DiffViewer, Config, References, DocumentSymbol,
  ## CallHierarchy) share the same dispatch shape and use the
  ## `dispatchSubState` template. LogViewer and Terminal have non-standard
  ## handler signatures and remain as explicit branches.
  let buffer = editor.activeBuffer
  let state = editor.state
  let viewport = editor.viewport
  let activeWindow = editor.activeWindow

  case state.mode
  of EditorMode.Normal, EditorMode.Insert, EditorMode.Visual, EditorMode.VisualBlock,
      EditorMode.VisualLine, EditorMode.Replace:
    # Migrated modes are handled by the Editor-based handleKeyCombo and
    # never reach this dispatcher.
    return HandlerResult(kind: hrUnhandled)
  of EditorMode.Filer:
    dispatchSubState(mskFiler, filer, handleFilerMode, "Filer")
  of EditorMode.FileTree:
    dispatchSubState(mskFileTree, fileTree, handleFileTreeMode, "FileTree")
  of EditorMode.LogViewer:
    # Non-standard handler signature: takes the buffer directly because log
    # content lives in the TextBuffer. LogViewerState is threaded for the
    # per-window key-sequence flags (waitingForG).
    if activeWindow.modeState.kind == mskLogViewer:
      return manager.handleLogViewerMode(
        activeWindow.modeState.logViewer, buffer, state, viewport.height, keyCombo
      )
    else:
      return
        HandlerResult(kind: hrError, errorMessage: "Log viewer state not initialized")
  of EditorMode.Help:
    dispatchSubState(mskHelp, help, handleHelpViewerMode, "Help viewer")
  of EditorMode.BufferManager:
    dispatchSubState(
      mskBufferManager, bufferManager, handleBufferManagerMode, "Buffer manager"
    )
  of EditorMode.BookmarkManager:
    dispatchSubState(
      mskBookmarkManager, bookmarkManager, handleBookmarkManagerMode, "Bookmark manager"
    )
  of EditorMode.BackupManager:
    dispatchSubState(
      mskBackupManager, backupManager, handleBackupManagerMode, "Backup manager"
    )
  of EditorMode.DiffViewer:
    dispatchSubState(mskDiffViewer, diffViewer, handleDiffViewerMode, "Diff viewer")
  of EditorMode.Config:
    dispatchSubState(mskConfig, config, handleConfigMode, "Config mode")
  of EditorMode.References:
    dispatchSubState(
      mskReferences, references, handleReferencesMode, "References viewer"
    )
  of EditorMode.DocumentSymbol:
    dispatchSubState(
      mskDocumentSymbol, documentSymbol, handleDocumentSymbolMode,
      "Document symbol viewer",
    )
  of EditorMode.CallHierarchy:
    dispatchSubState(
      mskCallHierarchy, callHierarchy, handleCallHierarchyMode, "Call hierarchy viewer"
    )
  of EditorMode.Terminal:
    # Non-standard handler signature: takes `window` instead of viewport height.
    if activeWindow.modeState.kind == mskTerminal:
      return manager.handleTerminalMode(
        activeWindow.modeState.terminal, state, keyCombo, activeWindow
      )
    else:
      return
        HandlerResult(kind: hrError, errorMessage: "Terminal state not initialized")
  of EditorMode.Command, EditorMode.RecentFile, EditorMode.Debug:
    # Command: handled via overlay in handler.nim.
    # RecentFile: requires its own state, handled at a higher level.
    # Debug: handled at a higher level in handler.nim.
    return HandlerResult(kind: hrUnhandled)
