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
## handleKeyCombo, macro playback and runtime mappings) lives in
## handler_manager.nim and result_processor.nim.
##
## dispatchSubStateMode is also kept here because it only forwards to the
## sub-state-mode dispatchers in this file.

import std/[options, strutils]

import pkg/results

when not defined(moe.embedded):
  import pkg/celina

import
  ../[
    types, buffer, modes, key_bindings, keybind_config, filer, filetree, diff_viewer,
    recent_file_mode, command_line, visual_selection, insert_record, wanted_column,
  ]

when not defined(moe.embedded):
  import ../terminal_mode
import ../lsp/protocol/types as lspTypes
import ../types/editor_types
# The per-mode key handlers this module forwards to come from handler_modules
# (the shared re-export surface). See handler_modules.nim for why the list is
# centralized there rather than duplicated per importer.
import handler_modules

proc commitInsertModeBoundary*(
    buffer: TextBuffer, state: EditorState
): Result[void, string] =
  ## Commit one Insert-mode undo group without leaving Insert mode: snippet and
  ## auto-indent state stay active, and what `.` repeats goes on.
  if buffer.inTransaction:
    let transactionResult = buffer.commitTransaction()
    if transactionResult.isErr:
      return err("Failed to commit transaction: " & transactionResult.error)

  ok()

func replicaColumn(ctx: types.VisualBlockInsertContext, lineLen: int): Option[int] =
  ## Where a line `lineLen` long takes the copied text, as Vim's block_insert
  ## and op_change: `I` and `c` leave a line that ends before the block alone,
  ## `A` pads it out to the block, and `A` after `<C-v>$` appends at each
  ## line's end.
  case ctx.kind
  of vbiInsert, vbiChange:
    if lineLen < ctx.insertColumn:
      none(int)
    else:
      some(ctx.insertColumn)
  of vbiAppend:
    some(if ctx.atLineEnd: lineLen else: ctx.insertColumn)

proc replicateBlockInsert*(buffer: TextBuffer, state: EditorState): string =
  ## End a Visual-block insert: copy what the first line gained, from the block
  ## column, onto the other lines, as Vim does. Nothing is copied when the
  ## cursor left the first line. Returns an error message, or "".
  if state.editState.visualBlockInsertContext.isNone:
    return ""
  let ctx = state.editState.visualBlockInsertContext.get
  state.editState.visualBlockInsertContext = none(types.VisualBlockInsertContext)
  if state.cursor.line != ctx.startLine or ctx.startLine >= buffer.len:
    return ""
  let
    firstLine = buffer.getLine(ctx.startLine)
    gained = firstLine.charLen - ctx.firstLineLen
  if gained <= 0:
    return ""
  let text = firstLine.charSubStr(min(ctx.insertColumn, ctx.firstLineLen), gained)

  for lineNum in (ctx.startLine + 1) .. min(ctx.endLine, buffer.len - 1):
    let lineCharLen = buffer.getLine(lineNum).charLen
    let column = ctx.replicaColumn(lineCharLen)
    if column.isNone:
      continue
    let col = column.get
    if col > lineCharLen:
      let padding = ' '.repeat(col - lineCharLen)
      let padResult =
        buffer.insertText(BufferPosition(line: lineNum, column: lineCharLen), padding)
      if padResult.isErr:
        return padResult.error
    let replayResult =
      buffer.insertText(BufferPosition(line: lineNum, column: col), text)
    if replayResult.isErr:
      return replayResult.error
  ""

proc finalizeInsertExit*(
    buffer: TextBuffer, state: EditorState
): Result[string, string] =
  ## Shared leaving-Insert cleanup: snippet/auto-indent teardown, the end of what
  ## `.` repeats, visual-block replication and transaction commit.
  ##
  ## ok carries a non-fatal warning to surface (empty when clean), which must
  ## not block the mode transition. err is a fatal commit failure.
  state.snippetSession.active = false
  state.endInsertRecord()

  clearAutoIndentIfUnedited(buffer, state)

  # Not typed, so `.` repeats what was typed, not the copies.
  let replicationError = replicateBlockInsert(buffer, state)

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

proc finalizeInsertInterrupt*(
    buffer: TextBuffer, state: EditorState
): Result[void, string] =
  ## Finish Insert mode for Ctrl-C without the count's repeats or visual-block
  ## replication.
  state.snippetSession.active = false
  state.endInsertRecord()
  clearAutoIndentIfUnedited(buffer, state)

  state.editState.visualBlockInsertContext = none(types.VisualBlockInsertContext)
  commitInsertModeBoundary(buffer, state)

proc leaveInsertForCtrlO(state: EditorState, buffer: TextBuffer) =
  ## Vim's Ctrl-o keeps for vertical motions the column the cursor showed on
  ## in Insert, a tab's first cell. Past the end of the line, it puts the
  ## cursor on the last character for the Normal command, and Insert goes back
  ## past the end if it resumes there (ins_at_eol). Elsewhere the cursor stays
  ## where it is.
  let
    wanted = state.aimedColumn
    lineLen = buffer.getLine(state.cursor.line).charLen
  if state.cursor.column < lineLen:
    state.insertResumeLineEnd = none(int)
  else:
    state.insertResumeLineEnd = some(state.cursor.line)
    state.cursor.column = max(0, lineLen - 1)
  state.preferredColumn = wanted

proc leaveInsert*(
    manager: HandlerManager, editor: Editor, target = EditorMode.Normal, thenExec = ""
): HandlerResult =
  ## Leave Insert as Escape does, running the command line `thenExec` after if
  ## given. A count types the record again first (`3ifoo`, `2o`).
  let buffer = editor.activeBuffer
  let state = editor.state
  manager.insertHandler.closeInsertPopups()
  let times = state.editState.typing.repeatsLeft
  if target == EditorMode.Normal and state.editState.typing.open and times > 0:
    state.editState.typing.repeatsLeft = 0
    let record = state.editState.insertRecord
    return HandlerResult(
      kind: hrRepeatInsert,
      repeatTyped: record.typed,
      repeatTimes: times,
      repeatNewLine:
        if record.entry.kind in {ieOpenBelow, ieOpenAbove}:
          some(state.editState.typing.linesBelow)
        else:
          none(int),
      repeatLeave: true,
      repeatThenExec: thenExec,
    )
  let finalizeResult = finalizeInsertExit(buffer, state)
  if thenExec.len > 0:
    if finalizeResult.isErr:
      return HandlerResult(kind: hrError, errorMessage: finalizeResult.error)
    if finalizeResult.get.len > 0:
      # Committed with a partial-replication warning: surface it but run the
      # command anyway, the session being finalized already.
      state.statusMessage = finalizeResult.get
    return
      HandlerResult(kind: hrExecCommand, execCommandText: thenExec, execCommandCount: 1)
  # Even on failure, allow the mode transition so the user is not stuck in Insert.
  HandlerResult(
    kind: hrHandled,
    modeTransition: some(target),
    statusMessage:
      if finalizeResult.isErr: finalizeResult.error else: finalizeResult.get,
  )

proc typeText*(
    manager: HandlerManager, editor: Editor, typed: TypedInput
): HandlerResult =
  ## Put text in at the cursor as typed (a paste, or text `.` types again).
  let state = editor.state
  state.noteOutsideChange()
  let at = state.cursor
  let r = typeTextAgain(editor.activeBuffer, state, typed)
  if r.isErr:
    return HandlerResult(kind: hrError, errorMessage: r.error)
  state.noteTyped([typed], at)
  state.settleTyping()
  HandlerResult(kind: hrHandled, modeTransition: none(EditorMode), statusMessage: "")

proc handleInsertMode*(
    manager: HandlerManager, editor: Editor, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Insert mode input
  let buffer = editor.activeBuffer
  let state = editor.state
  state.noteOutsideChange()
  let
    cursorBefore = state.cursor
    versionBefore = buffer.contentVersion
  let r = manager.insertHandler.handleInsertModeKey(buffer, state, keyCombo)
  case r.kind
  of imrHandled:
    # Check if we're leaving Insert mode
    if r.modeTransition.isSome and r.modeTransition.get != EditorMode.Insert:
      # Forced Insert mode uses Ctrl-o as its built-in route to Command mode.
      # It ends a Visual-block insert, as in Vim.
      if state.config.standard.forceInsertMode and r.isCtrlOExit:
        state.closeInsertRecord()
        # Insert goes on after the command line, as Ctrl-o resumes it.
        state.resumeTyping(state.cursor)
        let replicationError = replicateBlockInsert(buffer, state)
        return HandlerResult(
          kind: hrHandled,
          modeTransition: none(EditorMode),
          overlayTransition: some(OverlayKind.okCommand),
          statusMessage:
            if replicationError.len > 0:
              "Failed to replicate visual block insert: " & replicationError
            else:
              "",
        )

      # Ctrl-o ends Insert for one Normal command, as Vim's does, and Insert
      # resumes with a new session once it is done (settleInsertResume). A
      # session that cannot commit leaves Insert as Escape does, cursor and
      # all, without the wait, so Insert does not resume over the open
      # transaction. The count is not typed again.
      if r.isCtrlOExit:
        let inChange = state.editState.typing.open
        let finalizeResult = finalizeInsertExit(buffer, state)
        if finalizeResult.isOk:
          state.leaveInsertForCtrlO(buffer)
          state.insertResume = irWaiting
          state.insertResumeInChange = inChange
        return HandlerResult(
          kind: hrHandled,
          modeTransition: r.modeTransition,
          statusMessage:
            if finalizeResult.isErr: finalizeResult.error else: finalizeResult.get,
        )

      # Resolve the keybinding before applying Ctrl-C's interrupt semantics so
      # :iunmap and Insert-mode remaps remain authoritative.
      if r.isInterruptExit:
        let interruptResult = finalizeInsertInterrupt(buffer, state)
        return HandlerResult(
          kind: hrHandled,
          modeTransition: r.modeTransition,
          statusMessage: if interruptResult.isErr: interruptResult.error else: "",
        )

      return manager.leaveInsert(editor, r.modeTransition.get)
    state.noteKey(
      buffer, keyCombo, r.typedBefore, r.keyConsumed, r.moves, cursorBefore,
      versionBefore,
    )
    state.settleTyping()
    return HandlerResult(
      kind: hrHandled,
      modeTransition: r.modeTransition,
      overlayTransition: r.overlayTransition,
      statusMessage: "",
    )
  of imrTypeAgain:
    if state.editState.lastInserted.isNone:
      # Vim's E29; Ctrl-@ still leaves Insert.
      const noneYet = "E29: No inserted text yet"
      if not r.thenLeave:
        return HandlerResult(kind: hrError, errorMessage: noneYet)
      state.statusMessage = noneYet
      return manager.leaveInsert(editor)
    return HandlerResult(
      kind: hrRepeatInsert,
      repeatTyped: state.editState.lastInserted.get,
      repeatTimes: 1,
      repeatAsTyping: true,
      repeatLeave: r.thenLeave,
    )
  of imrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of imrExecCommand:
    # `imap K = "bdelete"` bridge: leave Insert as `<Esc>:bdelete<CR>` would,
    # cleanup and all, before the aliased command runs.
    return manager.leaveInsert(editor, thenExec = r.execCommandText)
  of imrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleCommandMode*(
    manager: HandlerManager,
    buffer: TextBuffer,
    cmdResult: CommandLineResult,
    isSharedBuffer: bool = false,
    currentLine: int = 0,
    otherModifiedCount: int = 0,
): HandlerResult =
  ## Handle an already parsed Command mode input.
  ## isSharedBuffer: true if the buffer is shared across multiple windows.
  ## currentLine: 0-based cursor line, used for range substitution with '.'.
  ## otherModifiedCount: modified buffers other than `buffer` (for :qa).
  ## Map ops (hrMap*) need access to `manager.keyBindingRegistry`, so they are
  ## executed here and folded onto hrHandled/hrError; every other kind is
  ## returned as-is to the caller.
  let r = manager.commandHandler.handleCommandModeInput(
    buffer, cmdResult, isSharedBuffer, currentLine, otherModifiedCount
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

proc handleCommandMode*(
    manager: HandlerManager,
    buffer: TextBuffer,
    commandText: string,
    isSharedBuffer: bool = false,
    currentLine: int = 0,
    otherModifiedCount: int = 0,
): HandlerResult =
  ## Parse and dispatch Command mode text, including an empty `:` overlay.
  if commandText.len <= 1:
    return manager.commandHandler.handleCommandModeInput(
      buffer, commandText, isSharedBuffer, currentLine, otherModifiedCount
    )
  manager.handleCommandMode(
    buffer,
    manager.commandHandler.parser.parseAndExecute(commandText),
    isSharedBuffer,
    currentLine,
    otherModifiedCount,
  )

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
      # `.` inserts what is typed at the cursor; it does not take a selection.
      state.startInsertRecord(InsertEntry(kind: ieInsert), 1)
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
    # Enter the requested Visual variant, which starts the selection at the
    # cursor. The log buffer stays readOnly, so destructive commands are
    # blocked in the command registry. `y` / Esc / Ctrl-C return through
    # `leaveVisual`, which lands on LogViewer because processResult sets
    # previousMode here.
    return HandlerResult(
      kind: hrHandled, modeTransition: some(r.visualKind.visualMode), statusMessage: ""
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
      HandlerResult(kind: hrBufferManagerSelectBuffer, selectBufferId: r.bufferNumber)
  of bmrDeleteBuffer:
    return HandlerResult(
      kind: hrBufferManagerDeleteBuffer, deleteBufferId: r.deleteBufferNumber
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

proc handleRecoveryManagerMode*(
    manager: HandlerManager,
    rcState: RecoveryManagerState,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Recovery Manager mode input
  let r = handleRecoveryManagerModeKey(rcState, viewportHeight, keyCombo)
  case r.kind
  of rcmrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of rcmrRestore:
    return HandlerResult(
      kind: hrRecoveryManagerRestore, restoreRecoveryIndex: r.restoreIndex
    )
  of rcmrToggleReviewed:
    return HandlerResult(
      kind: hrRecoveryManagerToggleReviewed, reviewRecoveryIndex: r.reviewIndex
    )
  of rcmrDiscard:
    return HandlerResult(
      kind: hrRecoveryManagerDiscard, discardRecoveryIndex: r.discardIndex
    )
  of rcmrArmDiscard:
    return HandlerResult(
      kind: hrHandled,
      modeTransition: none(EditorMode),
      statusMessage:
        "Discard this preserved copy? It is unsaved work. Press D again to confirm",
    )
  of rcmrRefresh:
    return HandlerResult(kind: hrRecoveryManagerRefresh)
  of rcmrEnterCommand:
    state.input.commandText = ":"
    state.input.commandCursor = 0
    return HandlerResult(
      kind: hrHandled, overlayTransition: some(okCommand), statusMessage: ""
    )
  of rcmrUnhandled:
    return HandlerResult(kind: hrUnhandled)

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
  of dvrToggleView:
    return HandlerResult(kind: hrDiffViewerToggleView)
  of dvrToggleWord:
    return HandlerResult(kind: hrDiffViewerToggleWord)
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

when not defined(moe.embedded):
  proc handleTerminalMode*(
      manager: HandlerManager,
      termState: TerminalState,
      state: EditorState,
      keyCombo: KeyCombo,
      window: EditorWindow,
  ): HandlerResult =
    ## Handle Terminal mode input
    let r = handleTerminalModeKey(termState, window.modeState.terminalSubMode, keyCombo)
    case r.kind
    of trHandled:
      return HandlerResult(
        kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
      )
    of trSwitchToNormal:
      # Switch to Terminal-Normal sub-mode: snapshot grid to TextBuffer.
      # Terminal windows hold no Insert session, so no finalization is needed.
      # Sub-mode and placement only; `syncTerminalView` derives the view.
      let snapshotBuffer = termState.snapshotScrollback()
      window.modeState.scrollbackSnapshot = snapshotBuffer
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
      # `syncTerminalView` puts the session's tab buffer back under the grid.
      window.modeState.scrollbackSnapshot = nil
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
  ## 12 sub-state modes (Filer, FileTree, Help, BufferManager, BookmarkManager,
  ## BackupManager, RecoveryManager, DiffViewer, Config, References,
  ## DocumentSymbol, CallHierarchy) share the same dispatch shape and use the
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
  of EditorMode.RecoveryManager:
    dispatchSubState(
      mskRecoveryManager, recoveryManager, handleRecoveryManagerMode, "Recovery manager"
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
    when defined(moe.embedded):
      return HandlerResult(
        kind: hrError, errorMessage: "Terminal mode is unavailable in embedded builds"
      )
    else:
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
