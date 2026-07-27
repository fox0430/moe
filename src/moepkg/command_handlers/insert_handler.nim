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

## Insert mode handler
##
## This module handles commands specific to Insert mode, including:
## - Character insertion
## - Backspace and delete
## - Navigation within insert mode
## - Mode switching (Escape)
## - Auto-completion (Ctrl+N/Ctrl+P to navigate, Tab to commit)
## - Macro recording support

import std/[options, unicode, strutils, monotimes, tables]

import pkg/results

import
  ../[
    types, buffer, config, modes, key_bindings, motion, command_registry, unicode_utils,
    completion, signature_help, lsp_integration, lsp_request_context, key_router,
  ]
import handler_types, insert_commands
import ../types/editor_types
export handler_types

type
  InsertModeResultKind* = enum
    imrHandled
    imrUnhandled
    imrExecCommand
      ## Command mode command alias bridge — run `:<alias>` via the
      ## command-line parser
    imrError

  InsertModeResult* = object ## Result of insert mode command execution
    case kind*: InsertModeResultKind
    of imrHandled:
      modeTransition*: Option[EditorMode]
      overlayTransition*: Option[OverlayKind]
    of imrUnhandled:
      discard
    of imrExecCommand:
      execCommandText*: string
        ## Insert mode has no count prefix, so the dispatcher always
        ## forwards count = 1 to the command-line parser.
    of imrError:
      errorMessage*: string

proc newInsertModeHandler*(
    keyBindingRegistry: KeyBindingRegistry,
    motionController: MotionController,
    commandRegistry: CommandRegistry,
    lsp: LspIntegration = nil,
): InsertModeHandler =
  ## NotificationConfig is pulled live from `state.config` via CommandContext getter.
  InsertModeHandler(
    keyBindingRegistry: keyBindingRegistry,
    motionController: motionController,
    commandRegistry: commandRegistry,
    completionManager: newCompletionManager(),
    signatureHelpManager: newSignatureHelpManager(),
    lsp: lsp,
  )

proc executeCommand*(
    handler: InsertModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    commandId: string,
    args: seq[string] = @[],
): InsertModeResult =
  ## Execute a command using the CommandRegistry
  let ctx = CommandContext(
    buffer: buffer,
    state: state,
    viewport: viewport,
    motionController: handler.motionController,
    keyBindingRegistry: handler.keyBindingRegistry,
  )

  let cmdResult = handler.commandRegistry.execute(ctx, commandId, args)
  if cmdResult.isOk:
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))
  else:
    return InsertModeResult(kind: imrError, errorMessage: cmdResult.error)

proc handleCharacterInsertion*(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState, text: string
): InsertModeResult =
  ## Handle regular character insertion with auto-close paren support
  let pos = state.cursor

  # Track paren depth for signature help
  if text.len == 1:
    if text[0] == '(':
      handler.signatureHelpManager.incrementParenDepth()
    elif text[0] == ')':
      handler.signatureHelpManager.decrementParenDepth()

  # Check if auto-close paren is enabled and text is a single character opening paren
  if state.autoCloseParen and text.len == 1 and isOpeningParen(text[0]):
    let openChar = text[0]
    let closeChar = getClosingChar(openChar)

    # Insert both opening and closing characters
    discard buffer.insertText(pos, text & $closeChar)

    # Move cursor to position between the pair (after opening char)
    state.cursor.column += 1
  else:
    # Normal insertion
    discard buffer.insertText(pos, text)

    # Move cursor right after insertion (by character count, not byte count)
    state.cursor.column += text.runeLen

  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc handleBackspace*(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState
): InsertModeResult =
  ## Handle backspace key with auto-delete paren support
  let pos = state.cursor

  if pos.column > 0:
    # Check if auto-delete paren is enabled
    if state.autoDeleteParen:
      let currentLine = buffer.getLine(pos.line)

      try:
        # Auto-delete adjacent pairs only: cursor must be between open and close
        # e.g., (|), [|], {|}, "|", '|'
        if isAdjacentPair(currentLine, pos.column - 1):
          state.cursor.column -= 1
          discard buffer.deleteChar(state.cursor) # Delete opening char
          discard buffer.deleteChar(state.cursor) # Delete closing char
          return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))
      except IndexDefect, CatchableError:
        # If accessing rune fails, fall through to normal backspace
        discard

    # softTabStop-aware backspace: delete to previous boundary in leading whitespace
    if state.expandTab:
      let currentLine = buffer.getLine(pos.line)
      # Check if cursor is within leading whitespace
      var allSpaces = true
      for i in 0 ..< pos.column:
        if i < currentLine.charLen:
          let ch = currentLine.runeAtPos(i)
          if ch != Rune(' ') and ch != Rune('\t'):
            allSpaces = false
            break
        else:
          allSpaces = false
          break
      if allSpaces and pos.column > 0:
        let sts = effectiveSoftTabStop(state)
        let tabWidth = max(1, sts)
        # Calculate how many chars to delete to reach previous boundary
        let remainder = pos.column mod tabWidth
        let deleteCount = if remainder == 0: tabWidth else: remainder
        let actualDelete = min(deleteCount, pos.column)
        for i in 0 ..< actualDelete:
          state.cursor.column -= 1
          discard buffer.deleteChar(state.cursor)
      else:
        # Normal backspace: move cursor back and delete
        state.cursor.column -= 1
        discard buffer.deleteChar(state.cursor)
    else:
      # Normal backspace: move cursor back and delete
      state.cursor.column -= 1
      discard buffer.deleteChar(state.cursor)
  elif pos.line > 0:
    # At start of line, join with previous line
    let prevLine = buffer.getLine(pos.line - 1)
    let currentLine = buffer.getLine(pos.line)
    let prevLineLen = prevLine.charLen

    # Delete the current line first
    discard buffer.deleteLine(pos.line)
    # Append current line content to previous line
    if currentLine.len > 0:
      discard buffer.insertText(
        BufferPosition(line: pos.line - 1, column: prevLineLen), currentLine
      )

    # Move cursor to the join point
    state.cursor.line -= 1
    state.cursor.column = prevLineLen

  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc handleDelete*(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState
): InsertModeResult =
  ## Handle delete key
  discard buffer.deleteChar(state.cursor)

  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc handleNewline*(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState
): InsertModeResult =
  ## Handle newline insertion with auto-indentation
  # Call the insert_commands implementation which has auto-indent logic
  insertNewline(buffer, state)

  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc handleTab*(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState
): InsertModeResult =
  ## Handle tab key insertion
  ## Inserts either a tab character or spaces based on expandTab setting
  ## When expandTab is true, aligns to the next softTabStop boundary
  let pos = state.cursor

  if state.expandTab:
    # Insert spaces to align to next softTabStop boundary
    let sts = effectiveSoftTabStop(state)
    let tabWidth = max(1, sts) # Ensure at least 1 space
    let spacesToInsert = tabWidth - (pos.column mod tabWidth)
    let spaces = " ".repeat(spacesToInsert)

    let insertResult = buffer.insertText(pos, spaces)
    if insertResult.isErr:
      return InsertModeResult(
        kind: imrError, errorMessage: "Failed to insert spaces: " & insertResult.error
      )

    # Move cursor right by number of spaces inserted
    state.cursor.column += spacesToInsert
  else:
    # Insert actual tab character
    let insertResult = buffer.insertText(pos, "\t")
    if insertResult.isErr:
      return InsertModeResult(
        kind: imrError, errorMessage: "Failed to insert tab: " & insertResult.error
      )

    # Move cursor right after tab (1 character)
    state.cursor.column += 1

  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc handleMotion*(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState, motion: Motion
): InsertModeResult =
  ## Handle motion commands in insert mode
  let motionCmd = MotionCommand(motion: motion, count: 1)

  let r = handler.motionController.executeMotion(motionCmd, state.cursor)
  if r.isErr:
    return InsertModeResult(kind: imrError, errorMessage: r.error)
  state.cursor = r.value
  # Cursor movement invalidates the [count]i/a/o replay range; cancel it.
  state.editState.insertReplayCount = 0
  state.editState.insertReplayLineEntry = false
  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc handleModeSwitch*(
    handler: InsertModeHandler, targetMode: EditorMode
): InsertModeResult =
  ## Handle mode switching from insert mode
  # Cancel completion and signature help when leaving insert mode
  handler.completionManager.cancelCompletion()
  handler.signatureHelpManager.hide()
  return InsertModeResult(kind: imrHandled, modeTransition: some(targetMode))

proc runeOffsetToBufferPos(
    insertText: string, runeOffset: int, startLine, startCol: int
): BufferPosition =
  ## Translate a flat rune offset within `insertText` (inserted at
  ## (startLine, startCol)) into a buffer position, walking newlines.
  var lineDelta = 0
  var colInLine = 0
  var seen = 0
  for r in insertText.runes:
    if seen >= runeOffset:
      break
    if r == Rune('\n'):
      inc lineDelta
      colInLine = 0
    else:
      inc colInLine
    inc seen
  BufferPosition(
    line: startLine + lineDelta,
    column:
      if lineDelta == 0:
        startCol + colInLine
      else:
        colInLine,
  )

proc remapAfterEdit*(
    session: var SnippetSession, editStart, oldEnd, newEnd: BufferPosition
) =
  ## Shift the session's tabstop coordinates after a buffer edit that replaced
  ## the range [editStart, oldEnd) with text ending at newEnd (both ends
  ## exclusive). Stops before the edit are untouched, stops swallowed by it
  ## clamp to its start (this keeps the current stop anchored when its own
  ## default is replaced), and stops after it shift by the size delta (the
  ## column delta only applies to stops that shared the old end's line).
  for stop in session.stops.mitems:
    if stop.pos < editStart:
      continue
    if stop.pos < oldEnd:
      stop.pos = editStart
      # The content the stop covered was deleted or replaced by this edit; a
      # stale length would make a later Tab land past the real content and a
      # wholesale-replace delete unrelated text (e.g. the inner stop of a
      # nested `${1:${2:x}}` after the outer default is replaced).
      stop.len = 0
    else:
      if stop.pos.line == oldEnd.line:
        stop.pos.column += newEnd.column - oldEnd.column
      stop.pos.line += newEnd.line - oldEnd.line

proc deletePendingDefault(buffer: TextBuffer, state: EditorState) =
  ## Selection-delete the current stop's pending placeholder default: wipe the
  ## whole range, collapse the stop to zero length and clear the pending flag.
  ## A no-op when nothing is pending (the stop is already bare or was typed
  ## into). Shared by the typed-char, Backspace, Delete and Enter paths so they
  ## all honour the "a selected default is replaced wholesale" semantics.
  let cur = state.snippetSession.stops[state.snippetSession.index]
  if state.snippetSession.defaultPending and cur.len > 0:
    state.cursor = cur.pos
    for _ in 0 ..< cur.len:
      discard buffer.deleteChar(state.cursor)
    # The remap also collapses the stop itself to zero length: its range is
    # exactly the deleted one.
    remapAfterEdit(
      state.snippetSession,
      cur.pos,
      BufferPosition(line: cur.pos.line, column: cur.pos.column + cur.len),
      cur.pos,
    )
  state.snippetSession.defaultPending = false

proc insertCharInSession(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState, text: string
): InsertModeResult =
  ## Insert a typed character during a snippet session. A pending placeholder
  ## default is replaced wholesale by the first keystroke (selection
  ## semantics), and the remaining tabstop coordinates are remapped across
  ## both edits. Auto-close paren applies as in handleCharacterInsertion: the
  ## pair is still a single insertion at the cursor, so the remap covers both
  ## characters while the cursor lands between them.
  deletePendingDefault(buffer, state)

  # Track paren depth for signature help (same as handleCharacterInsertion).
  if text.len == 1:
    if text[0] == '(':
      handler.signatureHelpManager.incrementParenDepth()
    elif text[0] == ')':
      handler.signatureHelpManager.decrementParenDepth()

  let autoClose = state.autoCloseParen and text.len == 1 and isOpeningParen(text[0])
  let toInsert =
    if autoClose:
      text & $getClosingChar(text[0])
    else:
      text

  let idx = state.snippetSession.index
  let before = state.cursor
  # The current stop grows to cover the inserted text instead of being pushed
  # ahead of it: when it starts at the insertion point the generic remap would
  # shift it along with the later stops, so restore its start and extend its
  # length. Cycling back to it then re-selects exactly what was typed.
  let stopStartsHere = state.snippetSession.stops[idx].pos == before
  discard buffer.insertText(before, toInsert)
  let inserted = toInsert.runeLen
  let insertEnd = BufferPosition(line: before.line, column: before.column + inserted)
  # The cursor sits between an auto-closed pair, after the text otherwise; the
  # remap's new end is always the insertion end, not the cursor.
  state.cursor.column += (if autoClose: 1 else: inserted)
  remapAfterEdit(state.snippetSession, before, before, insertEnd)
  if stopStartsHere:
    state.snippetSession.stops[idx].pos = before
  state.snippetSession.stops[idx].len += inserted
  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc backspaceInSession(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState
): InsertModeResult =
  ## Backspace during a snippet session: a pending placeholder default is
  ## wiped wholesale (selection semantics); otherwise a plain backspace with
  ## the stop coordinates remapped. An adjacent-pair auto-delete also removes
  ## the closing character after the cursor, which the backward-delete shape
  ## [newCursor, before) cannot describe, so the pair case is detected up
  ## front and remapped as the two-column range it really deletes. Shared by
  ## the session key handling and the completion popup's Backspace path,
  ## which runs before it.
  template session(): untyped =
    state.snippetSession

  let cur = session.stops[session.index]
  if session.defaultPending and cur.len > 0:
    deletePendingDefault(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))
  let before = state.cursor
  # Mirrors handleBackspace's own pair check so the remap knows the deleted
  # range in advance.
  let pairDeleted =
    state.autoDeleteParen and before.column > 0 and (
      try:
        isAdjacentPair(buffer.getLine(before.line), before.column - 1)
      except IndexDefect, CatchableError:
        false
    )
  let res = handler.handleBackspace(buffer, state)
  let oldEnd =
    if pairDeleted:
      BufferPosition(line: before.line, column: before.column + 1)
    else:
      before
  remapAfterEdit(session, state.cursor, oldEnd, state.cursor)
  # The generic remap shifts later stops but never resizes the stop the edit
  # happened inside: shrink the current stop by however many of the deleted
  # columns sat within its typed content, so its recorded length stays in
  # sync (Shift-Tab re-selection / highlight). Deleting at the stop's start
  # lands in the remap's swallowed-stop branch, which already zeroed the
  # length: the len > 0 guard keeps this from shrinking it again.
  if before.line == state.cursor.line and cur.pos.line == state.cursor.line and
      cur.pos.column <= state.cursor.column and session.stops[session.index].len > 0:
    let overlap = min(oldEnd.column, cur.pos.column + cur.len) - state.cursor.column
    if overlap > 0:
      session.stops[session.index].len =
        max(0, session.stops[session.index].len - overlap)
  return res

proc landOnCurrentStop(state: EditorState) =
  ## Place the cursor at the end of the current stop's content (selection-end
  ## semantics) and re-select the content when there is any: its placeholder
  ## default, or whatever was typed into it, so the next keystroke replaces
  ## the whole range (VSCode-style). Bare stops (len 0) just place the cursor.
  let stop = state.snippetSession.stops[state.snippetSession.index]
  state.cursor = BufferPosition(line: stop.pos.line, column: stop.pos.column + stop.len)
  state.snippetSession.defaultPending = stop.len > 0

proc commitCompletion*(
    handler: InsertModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    keepPopupOpen: bool = false,
): InsertModeResult =
  ## Commit the currently selected completion item.
  ##
  ## Replaces the range [start, cursor) in one edit: `start` is the LSP textEdit
  ## start (else the trigger column) and the end is always widened to the cursor,
  ## so re-committing after a cycling preview cleanly removes the previous insert.
  ##
  ## `keepPopupOpen` = cycling preview: insert the candidate as plain text with
  ## the cursor at its end, skip additionalTextEdits, and leave the popup open.
  ## The final commit (Enter / typing) instead expands snippets to $0 and applies
  ## additionalTextEdits (e.g. auto-imports). All edits join the Insert-mode
  ## transaction and undo together.
  let entryOpt = handler.completionManager.getSelectedEntry()
  if entryOpt.isNone or entryOpt.get.word.len == 0:
    if not keepPopupOpen:
      handler.completionManager.cancelCompletion()
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  let entry = entryOpt.get
  let menu = handler.completionManager.menu

  # Resolve the replacement range (rune coords) and the raw text to insert. The
  # range is [(startLine, startCol), (endLine, endCol)): both ends come from the
  # LSP textEdit when present (otherwise the word the popup was triggered on),
  # and the end is later widened to the current cursor so we also swallow any
  # characters typed after the request was sent. Honoring the textEdit end keeps
  # replace-mode completions (whose range extends past the cursor, e.g.
  # completing in the middle of an identifier) from leaving a dangling suffix,
  # and multi-line ranges are deleted wholesale rather than leaving a tail.
  var startLine: int
  var startCol: int
  var endLine: int
  var endCol: int
  var rawText: string
  if entry.textEdit.isSome:
    let edit = entry.textEdit.get
    startLine = edit.range.start.line
    startCol = utf16ToRuneIndex(buffer.getLine(startLine), edit.range.start.character)
    endLine = edit.range.`end`.line
    endCol = utf16ToRuneIndex(buffer.getLine(endLine), edit.range.`end`.character)
    rawText = edit.newText
  else:
    startLine = menu.triggerLine
    startCol = menu.triggerCol
    endLine = startLine
    endCol = startCol
    # For path completion, strip the trailing '/' from directories so the user
    # can explicitly type '/' to drill in.
    rawText =
      if handler.completionManager.isPathCompletion and entry.word.endsWith("/"):
        entry.word[0 ..^ 2]
      else:
        entry.word

  # Expand snippets to plain text plus the in-text cursor offset (in runes). A
  # cycling preview forces the cursor to the end (not $0) so the next cycle's
  # widen-to-cursor deletion swallows the whole preview. A final commit keeps
  # the full tabstop list: when there is something to cycle to or a default to
  # replace, a snippet session starts and the cursor lands at the end of the
  # first stop's default (selection-end semantics); otherwise the cursor falls
  # back to $0 / the lowest stop / the end, matching expandSnippet.
  var snippetStops: seq[SnippetStopOffset] = @[]
  let (insertText, cursorRuneOffset) =
    if entry.isSnippet:
      if keepPopupOpen:
        let (text, _) = expandSnippet(rawText)
        (text, text.runeLen)
      else:
        let (text, stops) = expandSnippetWithStops(rawText)
        snippetStops = stops
        let offset =
          if stops.len > 0 and stops[0].num >= 1 and (
            stops.len >= 2 or stops[0].len > 0
          ):
            stops[0].offset + stops[0].len
          elif stops.len > 0 and stops[^1].num == 0:
            stops[^1].offset
          elif stops.len > 0:
            stops[0].offset
          else:
            text.runeLen
        (text, offset)
    else:
      (rawText, rawText.runeLen)

  if entry.additionalTextEdits.isSome and not keepPopupOpen:
    # Apply additionalTextEdits (auto-imports etc.) FIRST, while the buffer still
    # matches the coordinates the server computed them against. Edits inserted at
    # or above the completion site push it down, so shift the start/end lines and
    # the live cursor (which tracks the same text) by the net lines they add.
    # Only line shifts are compensated: real servers emit whole-line insertions
    # (imports), never edits that change columns on the completion's own line, so
    # an intra-line column shift is intentionally not handled here.
    let adds = entry.additionalTextEdits.get
    if buffer.applyTextEdits(adds).isOk:
      var lineShift = 0
      for e in adds:
        if e.range.start.line <= startLine:
          lineShift += e.newText.count('\n') - (e.range.`end`.line - e.range.start.line)
      startLine += lineShift
      endLine += lineShift
      state.cursor.line += lineShift
      if state.snippetSession.active:
        # Session stops live at the completion site, below whole-line imports,
        # so they shift down with it.
        for stop in state.snippetSession.stops.mitems:
          stop.pos.line += lineShift

  # Widen the deletion end to the cursor when it sits past the textEdit end
  # (characters typed after the request was sent). Positions are compared as
  # (line, column) so this also covers the cursor trailing onto a later line.
  var delEndLine = endLine
  var delEndCol = endCol
  if state.cursor.line > delEndLine or
      (state.cursor.line == delEndLine and state.cursor.column > delEndCol):
    delEndLine = state.cursor.line
    delEndCol = state.cursor.column

  let startNotAfterEnd =
    startLine < delEndLine or (startLine == delEndLine and startCol <= delEndCol)
  let cursorSane =
    not (startLine == state.cursor.line and state.cursor.column < startCol)
  # The replaced range's old exclusive end, for remapping an active snippet
  # session's stops across this edit (set per delete path below).
  var oldEditEnd = BufferPosition(line: delEndLine, column: delEndCol)
  if startNotAfterEnd and cursorSane:
    # Delete the replaced range [(startLine, startCol), (delEndLine, delEndCol)).
    if delEndLine == startLine:
      state.cursor = BufferPosition(line: startLine, column: startCol)
      for _ in 0 ..< delEndCol - startCol:
        discard buffer.deleteChar(state.cursor)
    else:
      # Multi-line range: deleteRange's end is inclusive, so step the exclusive
      # end back one position (wrapping to the prior line's end, which also pulls
      # in the joining newline).
      var incLine = delEndLine
      var incCol = delEndCol
      if incCol > 0:
        dec incCol
      else:
        dec incLine
        incCol = buffer.getLine(incLine).runeLen
      discard buffer.deleteRange(
        BufferPosition(line: startLine, column: startCol),
        BufferPosition(line: incLine, column: incCol),
      )
      state.cursor = BufferPosition(line: startLine, column: startCol)
  else:
    # Inconsistent state (cursor before the start, or start past the end): fall
    # back to deleting the tracked prefix backward from the cursor.
    oldEditEnd = state.cursor
    let prefixLen = menu.prefix.runeLen
    for _ in 0 ..< prefixLen:
      if state.cursor.column == 0:
        break
      state.cursor.column -= 1
      discard buffer.deleteChar(state.cursor)
    startLine = state.cursor.line
    startCol = state.cursor.column

  # Insert the (expanded) text at the start position.
  discard buffer.insertText(state.cursor, insertText)

  # Place the cursor at cursorRuneOffset within the inserted text, translating
  # the flat rune offset into a (line, column) delta to support multi-line text.
  state.cursor =
    runeOffsetToBufferPos(insertText, cursorRuneOffset, startLine, startCol)

  if state.snippetSession.active:
    # This commit landed inside an active session (e.g. completing a word in a
    # placeholder, or a cycling preview): remap the stops across the
    # replacement. The current default can no longer be pending.
    let editStart = BufferPosition(line: startLine, column: startCol)
    let newEnd =
      runeOffsetToBufferPos(insertText, insertText.runeLen, startLine, startCol)
    let curBefore = state.snippetSession.stops[state.snippetSession.index]
    remapAfterEdit(state.snippetSession, editStart, oldEditEnd, newEnd)
    # The generic remap clamps swallowed stops and shifts later ones, but
    # never resizes the stop the edit happened inside. When the replaced
    # range sat within the current stop's content (completing the word typed
    # into a placeholder), restore the stop over the inserted text so
    # Shift-Tab re-selection and the highlight match the buffer.
    if curBefore.pos.line == editStart.line and oldEditEnd.line == editStart.line and
        newEnd.line == editStart.line and curBefore.pos.column <= editStart.column and
        oldEditEnd.column <= curBefore.pos.column + curBefore.len:
      state.snippetSession.stops[state.snippetSession.index] = SnippetStop(
        num: curBefore.num,
        pos: curBefore.pos,
        len: curBefore.len + newEnd.column - oldEditEnd.column,
      )
    state.snippetSession.defaultPending = false

  # Start a snippet session when the commit expanded tabstops worth cycling:
  # more than one stop, or a single placeholder whose default should be
  # replaced by typing. A lone bare `$n` / `$0` adds nothing over the plain
  # cursor placement above.
  if snippetStops.len > 0 and snippetStops[0].num >= 1 and
      (snippetStops.len >= 2 or snippetStops[0].len > 0):
    var resolved = newSeq[SnippetStop](snippetStops.len)
    for i, s in snippetStops:
      let pos = runeOffsetToBufferPos(insertText, s.offset, startLine, startCol)
      # `len` is a single-line column span. A default that wraps across lines
      # cannot be represented that way (pos.column + len would overshoot), so
      # treat it as a bare stop with no selectable default: the cursor still
      # lands at its end, but it is not highlighted or replaced wholesale.
      let endPos =
        runeOffsetToBufferPos(insertText, s.offset + s.len, startLine, startCol)
      let lineLen = if endPos.line == pos.line: s.len else: 0
      resolved[i] = SnippetStop(num: s.num, pos: pos, len: lineLen)
    state.snippetSession = SnippetSession(
      active: true, stops: resolved, index: 0, defaultPending: resolved[0].len > 0
    )

  if keepPopupOpen:
    # Cycling preview: keep the popup open and track the inserted text as the
    # prefix for the fallback delete path and popup rendering. Multi-line inserts
    # are left untracked (the single-line fallback cannot represent them; the
    # main range-delete path is what actually runs during cycling).
    if '\n' notin insertText:
      handler.completionManager.menu.prefix = insertText
  else:
    handler.completionManager.cancelCompletion()
  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc triggerLspCompletionRequest*(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState
) =
  ## Trigger completion with LSP support
  ## Shows buffer completions immediately, then switches to LSP when response arrives

  # Skip if autocomplete is disabled
  if not state.config.autocomplete.enable:
    return

  # Extract prefix for debounce/skip check
  let line = buffer.getLine(state.cursor.line)
  let prefix = extractPrefixBeforeCursor(line, state.cursor.column)

  if not handler.lsp.isNil and handler.lsp.isEnabled and
      state.config.lsp.completion.enable:
    # If LSP completion is available, check whether we can skip the request and
    # filter client-side. The skip check must run BEFORE the fallback
    # triggerCompletion below, which recollects buffer words. When
    # lsp.completion.enable is off we fall through to buffer completions only,
    # without touching LSP.
    if handler.completionManager.shouldSkipLspRequest(prefix):
      if handler.completionManager.lspItems.len > 0:
        # Filter existing LSP items client-side without clearing them
        handler.completionManager.menu.prefix = prefix
        handler.completionManager.menu.entries =
          handler.completionManager.filterAndSortEntries(prefix)
        handler.completionManager.menu.selectedIndex = 0
        handler.completionManager.menu.scrollOffset = 0
        handler.completionManager.menu.hasSelection = false
        if handler.completionManager.menu.entries.len > 0:
          handler.completionManager.state = csActive
      else:
        # LSP response not yet arrived; refresh buffer completions in place so
        # menu.prefix, the trigger position and the visible entries stay in sync
        # with the cursor while we wait.
        handler.completionManager.triggerCompletion(
          buffer, state.cursor.line, state.cursor.column, buffer.language
        )
      return

  # First, show buffer completions immediately for instant feedback
  handler.completionManager.triggerCompletion(
    buffer, state.cursor.line, state.cursor.column, buffer.language
  )

  if not handler.lsp.isNil and handler.lsp.isEnabled and
      state.config.lsp.completion.enable and
      # If LSP completion is available and the server advertises completion support,
      # start an async request in background. The capability gate lives here (not in
      # the skip branch above) because that branch only filters already-received
      # lspItems client-side and never issues a fresh request.
      handler.lsp.hasCompletionSupport(buffer):
    # Cancel any pending LSP completion request to avoid orphaned responses
    let oldReqId = handler.completionManager.getLspRequestId
    if oldReqId.isSome:
      handler.lsp.cancelRequest(oldReqId.get)

    # Flush pending didChange so the request lands on post-edit text.
    handler.lsp.flushPendingBufferChange(buffer)

    let reqResult =
      handler.lsp.startCompletionRequest(buffer, state.cursor.line, state.cursor.column)

    if reqResult.isOk:
      handler.completionManager.lastLspRequestTime = getMonoTime()
      handler.completionManager.lastLspPrefix = prefix
      handler.completionManager.setLspRequestPending(reqResult.get)

proc pollLspCompletion*(handler: InsertModeHandler, state: EditorState) =
  ## Poll for pending LSP completion response
  if handler.lsp.isNil or not handler.lsp.isEnabled:
    return

  if not handler.completionManager.isPendingLsp:
    return

  let reqIdOpt = handler.completionManager.getLspRequestId
  if reqIdOpt.isNone:
    return

  # Responses were already drained by the single per-frame poll at the top of
  # tick(); this only reads them.
  #
  # Check for response. The raw result string is parsed directly into typed
  # CompletionItems with jsony (parseCompletionResponse), avoiding an
  # intermediate JsonNode tree for what can be a very large completion list.
  let (status, rawOpt, errorOpt) = handler.lsp.checkResponseRaw(reqIdOpt.get)

  case status
  of lrsPending:
    discard # Still waiting
  of lrsSuccess:
    if rawOpt.isSome:
      let (items, isIncomplete) = parseCompletionResponse(rawOpt.get)
      # A fresh completion list obsoletes any resolve targeted at the previous
      # list's selection: without this cancel, a slow resolve response could
      # be applied to whatever entry now occupies `resolvedIndex`.
      cancelPendingRequest(handler.lsp, state.lspCache, lrfCompletionResolve)
      handler.completionManager.setLspItems(items, isIncomplete)
  of lrsError, lrsTimeout:
    # Clear pending state on error/timeout
    logLspDegraded("Completion", status, errorOpt.get(""))
    cancelPendingRequest(handler.lsp, state.lspCache, lrfCompletionResolve)
    handler.completionManager.setLspItems(@[])

proc triggerResolveRequest*(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState
) =
  ## Trigger a completionItem/resolve request for the selected item
  if handler.lsp.isNil or not handler.lsp.isEnabled:
    return
  if not handler.completionManager.needsResolve():
    return

  let rawJsonOpt = handler.completionManager.getSelectedRawJson()
  if rawJsonOpt.isNone:
    return

  let ctxRes = startContextualRequestOnCache(
    handler.lsp,
    state.lspCache,
    lrfCompletionResolve,
    buffer,
    proc(): Result[int, string] =
      handler.lsp.startCompletionResolveRequest(buffer, rawJsonOpt.get),
    validModes = {EditorMode.Insert},
  )
  if ctxRes.isOk:
    handler.completionManager.resolvedIndex =
      handler.completionManager.menu.selectedIndex

proc pollLspResolve*(handler: InsertModeHandler, state: EditorState) =
  ## Poll for pending completionItem/resolve response
  if handler.lsp.isNil or not handler.lsp.isEnabled:
    return

  if not state.lspCache.pending.hasKey(lrfCompletionResolve):
    return

  let ctx = state.lspCache.pending[lrfCompletionResolve]

  # Responses were already drained by the single per-frame poll at the top of
  # tick(); this only reads them.
  let (status, resultOpt, errorOpt) = handler.lsp.checkResponse(ctx.requestId)

  case status
  of lrsPending:
    discard
  of lrsSuccess:
    state.lspCache.pending.del(lrfCompletionResolve)
    # updateResolvedEntry gates on entry identity (menu word == resolved word);
    # a version drift while resolve is in flight doesn't invalidate that item.
    let buf = state.activeWindow.buffer
    if buf.isNil or buf.id != ctx.bufferId:
      return
    if state.mode != EditorMode.Insert:
      return
    if resultOpt.isSome:
      let resolved = parseCompletionItem(resultOpt.get)
      handler.completionManager.updateResolvedEntry(resolved)
      handler.completionManager.updateDocPanel()
  of lrsError, lrsTimeout:
    state.lspCache.pending.del(lrfCompletionResolve)
    logLspDegraded("Completion resolve", status, errorOpt.get(""))

proc isCtrlN(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+N
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "n"

proc isCtrlP(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+P
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "p"

proc isCtrlSpace(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+Space (manual completion trigger)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and keyCombo.char == " "

proc isCtrlW(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+W (delete word backward)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "w"

proc isCtrlU(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+U (delete to line start)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "u"

proc isCtrlT(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+T (indent line)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "t"

proc isCtrlD(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+D (dedent line)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "d"

proc isCtrlE(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+E (insert char from below)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "e"

proc isCtrlY(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+Y (insert char from above)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "y"

proc isCtrlR(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+R (signature help)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "r"

proc isCtrlO(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+O (one-shot normal mode)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "o"

proc isCtrlI(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+I (insert tab)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "i"

proc shouldTriggerSignatureHelp*(keyCombo: KeyCombo): bool =
  ## Check if the typed character should trigger signature help
  not keyCombo.isSpecial and keyCombo.modifiers == {} and keyCombo.char.len == 1 and
    isTriggerChar(keyCombo.char[0])

proc shouldRetriggerSignatureHelp*(keyCombo: KeyCombo): bool =
  ## Check if the typed character should retrigger signature help
  not keyCombo.isSpecial and keyCombo.modifiers == {} and keyCombo.char.len == 1 and
    isRetriggerChar(keyCombo.char[0])

proc handleInsertModeKey*(
    handler: InsertModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    keyCombo: KeyCombo,
): InsertModeResult =
  ## Main entry point for handling Insert mode key presses.
  ## Macro recording is captured centrally in `handler.handleKeyCombo`.

  let completionActive = handler.completionManager.isActive()

  # Handle completion-specific keys when completion is active
  if completionActive:
    # Ctrl+N, Down, or Tab - highlight the next item and preview it into the
    # buffer (replacing any previous preview). The final commit (Enter / typing)
    # re-applies the textEdit range and additionalTextEdits.
    if keyCombo.isCtrlN or (keyCombo.isSpecial and keyCombo.special == skDown) or (
      keyCombo.isSpecial and keyCombo.special == skTab and
      kmShift notin keyCombo.modifiers
    ):
      # First Tab activates selection mode (highlights item 0)
      if not handler.completionManager.menu.hasSelection:
        handler.completionManager.menu.hasSelection = true
      else:
        handler.completionManager.selectNext()
      let res = handler.commitCompletion(buffer, state, keepPopupOpen = true)
      handler.completionManager.updateDocPanel()
      handler.triggerResolveRequest(buffer, state)
      return res

    if keyCombo.isCtrlP or (keyCombo.isSpecial and keyCombo.special == skUp) or (
      keyCombo.isSpecial and keyCombo.special == skTab and kmShift in keyCombo.modifiers
    ) or (keyCombo.isSpecial and keyCombo.special == skBackTab):
      # Ctrl+P, Up, or Shift+Tab/BackTab - highlight the previous item and preview
      # it into the buffer (same as forward cycling).
      # First Shift+Tab activates selection mode (highlights item 0)
      if not handler.completionManager.menu.hasSelection:
        handler.completionManager.menu.hasSelection = true
      else:
        handler.completionManager.selectPrevious()
      let res = handler.commitCompletion(buffer, state, keepPopupOpen = true)
      handler.completionManager.updateDocPanel()
      handler.triggerResolveRequest(buffer, state)
      return res

    if keyCombo.isSpecial and keyCombo.special == skEnter:
      # Enter - confirm the highlighted item (if any), otherwise just dismiss the
      # popup without inserting a newline (press Enter again for a newline).
      if handler.completionManager.menu.hasSelection:
        return handler.commitCompletion(buffer, state)
      handler.completionManager.cancelCompletion()
      return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

    if keyCombo.isSpecial and keyCombo.special == skEscape:
      # Escape - cancel completion and leave insert mode
      handler.completionManager.cancelCompletion()
      return handler.handleModeSwitch(EditorMode.Normal)

    if keyCombo.isSpecial and keyCombo.special == skBackspace:
      # Backspace - update filter or cancel if prefix is empty. This popup
      # branch runs before the snippet session block below, so an active
      # session must remap its stop coordinates across the edit here too
      # (typing into a placeholder re-opens the popup, making this the
      # common in-session Backspace path).
      let backspaceResult =
        if state.snippetSession.active:
          handler.backspaceInSession(buffer, state)
        else:
          handler.handleBackspace(buffer, state)
      if handler.completionManager.isPathCompletion:
        # Re-check path context after backspace
        let line = buffer.getLine(state.cursor.line)
        let pathPrefix = extractPathPrefixBeforeCursor(line, state.cursor.column)
        if pathPrefix.len > 0:
          handler.completionManager.triggerPathCompletion(
            buffer, state.cursor.line, state.cursor.column
          )
        else:
          handler.completionManager.cancelCompletion()
      else:
        # Update completion filter with new prefix
        let line = buffer.getLine(state.cursor.line)
        let newPrefix = extractPrefixBeforeCursor(line, state.cursor.column)
        if newPrefix.len >= MinPrefixLength:
          handler.completionManager.updateFilter(newPrefix)
        else:
          handler.completionManager.cancelCompletion()
      return backspaceResult

    if not keyCombo.isSpecial and keyCombo.modifiers == {}:
      # Regular character input while completion is active
      let hasSelection = handler.completionManager.menu.hasSelection
      let wasPathCompletion = handler.completionManager.isPathCompletion

      if hasSelection and not wasPathCompletion:
        # Confirm the highlighted item, then type the new character after it.
        # Path completion keeps filtering as you type, so it is not committed.
        discard handler.commitCompletion(buffer, state)

      # Insert the new character. When a snippet session is active (possibly
      # just started by the commit above), the session insert replaces a
      # pending placeholder default and keeps the stops remapped.
      if state.snippetSession.active:
        discard handler.insertCharInSession(buffer, state, keyCombo.char)
      else:
        discard handler.handleCharacterInsertion(buffer, state, keyCombo.char)

      # Re-trigger completion with new prefix
      let line = buffer.getLine(state.cursor.line)
      let pathPrefix = extractPathPrefixBeforeCursor(line, state.cursor.column)
      if pathPrefix.len > 0:
        handler.completionManager.triggerPathCompletion(
          buffer, state.cursor.line, state.cursor.column
        )
      else:
        let newPrefix = extractPrefixBeforeCursor(line, state.cursor.column)
        if newPrefix.len >= AutoTriggerPrefixLength:
          # Show buffer completions immediately, LSP will update when ready
          handler.triggerLspCompletionRequest(buffer, state)
        else:
          handler.completionManager.cancelCompletion()
      return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  if state.snippetSession.active:
    # Snippet tabstop session. The completion popup's keys above take
    # precedence while it is open; here Tab/Shift-Tab navigate the stops,
    # typed characters replace a pending placeholder default, and remappable
    # edits (Backspace, Delete, Enter) keep the stop coordinates in sync. Any
    # other key ends the session and falls through to the normal handling.
    template session(): untyped =
      state.snippetSession

    if keyCombo.isSpecial and keyCombo.special == skTab and
        kmShift notin keyCombo.modifiers:
      if session.index + 1 < session.stops.len:
        inc session.index
        landOnCurrentStop(state)
        # Landing on the last stop with nothing left to replace (typically
        # $0) finishes the snippet; with a default the session stays alive so
        # the next keystroke can still replace it.
        if session.index == session.stops.high and session.stops[session.index].len == 0:
          session.active = false
        return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))
      # No stop left to jump to: end the session and fall through to the
      # normal Tab handling (indentation), the "jumpable ? jump : tab"
      # fallback convention of vsnip/LuaSnip-style snippet plugins.
      session.active = false

    if keyCombo.isSpecial and (
      keyCombo.special == skBackTab or
      (keyCombo.special == skTab and kmShift in keyCombo.modifiers)
    ):
      if session.index > 0:
        dec session.index
        landOnCurrentStop(state)
      return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

    if not keyCombo.isSpecial and keyCombo.modifiers == {}:
      discard handler.insertCharInSession(buffer, state, keyCombo.char)
      # Mirror the normal character path's auto-completion trigger so the
      # popup keeps working inside placeholders.
      if state.config.autocomplete.enable:
        let line = buffer.getLine(state.cursor.line)
        let pathPrefix = extractPathPrefixBeforeCursor(line, state.cursor.column)
        if pathPrefix.len > 0:
          handler.completionManager.triggerPathCompletion(
            buffer, state.cursor.line, state.cursor.column
          )
        else:
          let prefix = extractPrefixBeforeCursor(line, state.cursor.column)
          if prefix.len >= AutoTriggerPrefixLength:
            handler.triggerLspCompletionRequest(buffer, state)
      return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

    if keyCombo.isSpecial and keyCombo.special == skBackspace:
      return handler.backspaceInSession(buffer, state)

    if keyCombo.isSpecial and keyCombo.special == skDelete:
      if session.defaultPending and session.stops[session.index].len > 0:
        # Selection-delete semantics: Delete on a pending default wipes it,
        # matching Backspace and the typed-char path.
        deletePendingDefault(buffer, state)
        return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))
      let oldEnd =
        if state.cursor.column < buffer.getLine(state.cursor.line).runeLen:
          BufferPosition(line: state.cursor.line, column: state.cursor.column + 1)
        else:
          # Deleting at end of line joins the next line up.
          BufferPosition(line: state.cursor.line + 1, column: 0)
      let curBefore = session.stops[session.index]
      let res = handler.handleDelete(buffer, state)
      remapAfterEdit(session, state.cursor, oldEnd, state.cursor)
      # Shrink the current stop if the deleted character sat inside it (see the
      # backspace path). handleDelete leaves the cursor in place, so the deleted
      # column is the cursor column itself. The len > 0 guard skips the case
      # where the remap's swallowed-stop branch already zeroed the length
      # (deleting at the stop's start).
      if oldEnd.line == state.cursor.line and oldEnd.column == state.cursor.column + 1 and
          curBefore.pos.line == state.cursor.line and
          curBefore.pos.column <= state.cursor.column and
          state.cursor.column < curBefore.pos.column + curBefore.len and
          session.stops[session.index].len > 0:
        dec session.stops[session.index].len
      return res

    if keyCombo.isSpecial and keyCombo.special == skEnter:
      # A pending default is selected, so Enter replaces it before splitting
      # the line (same selection semantics as typing or Backspace).
      deletePendingDefault(buffer, state)
      let before = state.cursor
      let curBefore = session.stops[session.index]
      # Bracket-pair splitting inserts a second newline past the cursor plus
      # reindentation on both lines, an edit shape the [before, cursor) remap
      # below cannot represent: suppress it for this newline.
      let savedBracketSplit = state.bracketSplit
      state.bracketSplit = bsmDisable
      let res = handler.handleNewline(buffer, state)
      state.bracketSplit = savedBracketSplit
      remapAfterEdit(session, before, before, state.cursor)
      # A newline struck inside the current stop's typed content splits it
      # across lines, which the single-line `len` cannot represent: collapse it
      # to a bare stop (the same treatment a multi-line default gets at commit).
      if curBefore.pos.line == before.line and curBefore.pos.column < before.column and
          before.column < curBefore.pos.column + curBefore.len:
        session.stops[session.index].len = 0
      return res

    if keyCombo.isCtrlN:
      # Manual completion trigger: keep the session alive, matching the
      # auto-trigger in the typed-char path above — committing the result
      # remaps the stops. (The popup is not open here: open-popup keys are
      # handled before this block.)
      handler.triggerLspCompletionRequest(buffer, state)
      return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

    # Anything else (Escape, motions, edit commands, mode switches) ends the
    # session and is handled normally below.
    session.active = false

  if keyCombo.isCtrlN and not completionActive:
    # Ctrl+N - trigger completion (when not active)
    # Show buffer completions immediately, LSP will update when ready
    handler.triggerLspCompletionRequest(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  if keyCombo.isCtrlSpace and not completionActive:
    # Ctrl+Space - also trigger completion
    # Show buffer completions immediately, LSP will update when ready
    handler.triggerLspCompletionRequest(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  if keyCombo.isCtrlW:
    # Ctrl+W - delete word backward
    handler.completionManager.cancelCompletion()
    deleteWordBackward(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  if keyCombo.isCtrlU:
    # Ctrl+U - delete to line start
    handler.completionManager.cancelCompletion()
    deleteToLineStart(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  if keyCombo.isCtrlT:
    # Ctrl+T - indent line
    handler.completionManager.cancelCompletion()
    indentLine(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  if keyCombo.isCtrlD:
    # Ctrl+D - dedent line
    handler.completionManager.cancelCompletion()
    dedentLine(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  if keyCombo.isCtrlE:
    # Ctrl+E - insert character from line below
    handler.completionManager.cancelCompletion()
    discard insertCharFromBelow(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  if keyCombo.isCtrlY:
    # Ctrl+Y - insert character from line above
    handler.completionManager.cancelCompletion()
    discard insertCharFromAbove(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  if keyCombo.isCtrlR:
    # Ctrl+R - trigger signature help (LSP)
    handler.completionManager.cancelCompletion()
    if not handler.lsp.isNil and handler.lsp.isEnabled:
      let cursorLine = state.cursor.line
      let cursorCol = state.cursor.column
      let ctxRes = startContextualRequestOnCache(
        handler.lsp,
        state.lspCache,
        lrfSignatureHelp,
        buffer,
        proc(): Result[int, string] =
          handler.lsp.startSignatureHelpRequest(buffer, cursorLine, cursorCol),
        validModes = {EditorMode.Insert},
        cursor = some(BufferPosition(line: cursorLine, column: cursorCol)),
        ignoreContentVersion = true,
      )
      if ctxRes.isOk:
        # Sync the auto-poll tracker so requestSignatureHelpFromLsp does not
        # fire a redundant follow-up request for the same position/contentVersion
        # once this response arrives.
        state.lspCache.signatureHelpPoll.markRequestIssued(
          cursorLine, cursorCol, buffer.contentVersion, getMonoTime()
        )
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  if keyCombo.isCtrlO:
    # Ctrl+O - execute one Normal mode command then return to Insert mode
    handler.completionManager.cancelCompletion()
    handler.signatureHelpManager.hide()
    state.insertNormalMode = true
    return InsertModeResult(kind: imrHandled, modeTransition: some(EditorMode.Normal))

  if keyCombo.isCtrlI:
    # Ctrl+I - insert tab
    return handler.handleTab(buffer, state)

  # Resolve through the shared built-in decode entry (`resolveBuiltin`), the
  # same path Normal/Visual/Replace use. Insert has no built-in sequences, but a
  # user `:imap` may bind a multi-key command, so the FSM-backed entry (not a
  # plain single-key lookup) is still required. Only `rrCommand` carries a
  # binding to dispatch; every other result falls through to character insert,
  # matching the previous `findBinding` `none` path exactly.
  let route = handler.keyBindingRegistry.resolveBuiltin(EditorMode.Insert, keyCombo)
  if route.kind == rrCommand:
    let cmd = route.command
    case cmd.kind
    of ctModeSwitch:
      return handler.handleModeSwitch(cmd.targetMode)
    of ctOverlaySwitch:
      # Overlay switches not supported in insert mode
      return InsertModeResult(kind: imrUnhandled)
    of ctMotion:
      # Cancel completion on motion
      handler.completionManager.cancelCompletion()
      return handler.handleMotion(buffer, state, cmd.motion)
    of ctAction, ctCustom:
      # Handle action commands (e.g., from :imap)
      handler.completionManager.cancelCompletion()
      # Command mode command alias bridge: `exec.cmdline.<alias>` runs
      # `:<alias>` via the full command-line parser, so safety checks
      # (modified-buffer guard etc.) fire. Caller
      # (`mode_dispatchers.handleInsertMode`) is responsible for committing
      # the in-progress insert transaction before dispatching.
      if cmd.commandId.startsWith(ExecCmdlinePrefix):
        let aliasText = cmd.commandId[ExecCmdlinePrefix.len ..^ 1]
        return InsertModeResult(kind: imrExecCommand, execCommandText: aliasText)
      case cmd.commandId
      of "insert.backspace":
        return handler.handleBackspace(buffer, state)
      of "insert.delete":
        return handler.handleDelete(buffer, state)
      of "insert.newline":
        return handler.handleNewline(buffer, state)
      else:
        return InsertModeResult(kind: imrUnhandled)
    else:
      # Other command types not supported in insert mode
      return InsertModeResult(kind: imrUnhandled)

  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    # Handle regular character insertion with auto-completion trigger
    discard handler.handleCharacterInsertion(buffer, state, keyCombo.char)
    # All auto-triggering (path and word completion alike) is gated on
    # autocomplete.enable so the flag governs both consistently.
    if state.config.autocomplete.enable:
      # Check for path completion first
      let line = buffer.getLine(state.cursor.line)
      let pathPrefix = extractPathPrefixBeforeCursor(line, state.cursor.column)
      if pathPrefix.len > 0:
        handler.completionManager.triggerPathCompletion(
          buffer, state.cursor.line, state.cursor.column
        )
      else:
        # Auto-trigger word completion after typing (when prefix is long enough)
        let prefix = extractPrefixBeforeCursor(line, state.cursor.column)
        if prefix.len >= AutoTriggerPrefixLength:
          # Show buffer completions immediately, LSP will update when ready
          handler.triggerLspCompletionRequest(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  # Handle special keys
  if keyCombo.isSpecial:
    case keyCombo.special
    of skBackspace:
      return handler.handleBackspace(buffer, state)
    of skDelete:
      return handler.handleDelete(buffer, state)
    of skEnter:
      return handler.handleNewline(buffer, state)
    of skTab:
      return handler.handleTab(buffer, state)
    of skLeft:
      handler.completionManager.cancelCompletion()
      return handler.handleMotion(buffer, state, Motion.Left)
    of skRight:
      handler.completionManager.cancelCompletion()
      return handler.handleMotion(buffer, state, Motion.Right)
    of skUp:
      return handler.handleMotion(buffer, state, Motion.Up)
    of skDown:
      return handler.handleMotion(buffer, state, Motion.Down)
    of skHome:
      handler.completionManager.cancelCompletion()
      return handler.handleMotion(buffer, state, Motion.Home)
    of skEnd:
      handler.completionManager.cancelCompletion()
      return handler.handleMotion(buffer, state, Motion.End)
    of skPageUp:
      handler.completionManager.cancelCompletion()
      return handler.handleMotion(buffer, state, Motion.PageUp)
    of skPageDown:
      handler.completionManager.cancelCompletion()
      return handler.handleMotion(buffer, state, Motion.PageDown)
    else:
      return InsertModeResult(kind: imrUnhandled)

  # Unhandled key combination
  return InsertModeResult(kind: imrUnhandled)

proc isHandled*(imResult: InsertModeResult): bool =
  ## Check if the command was handled
  imResult.kind == imrHandled

proc hasError*(imResult: InsertModeResult): bool =
  ## Check if there was an error
  imResult.kind == imrError

proc getModeTransition*(imResult: InsertModeResult): Option[EditorMode] =
  ## Get the mode transition if any
  if imResult.kind == imrHandled:
    imResult.modeTransition
  else:
    none(EditorMode)

proc getOverlayTransition*(imResult: InsertModeResult): Option[OverlayKind] =
  ## Get the overlay transition if any
  if imResult.kind == imrHandled:
    imResult.overlayTransition
  else:
    none(OverlayKind)
