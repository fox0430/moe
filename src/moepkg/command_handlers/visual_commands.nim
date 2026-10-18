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

## Visual mode command implementations
##
## This module provides Visual mode specific command implementations
## that are independent of CommandContext for better testability

import std/[options, strutils]

import pkg/results

import
  ../[cursor_util, types, registers, modes, config, unicode_utils, visual_selection]
import ../buffer/[core, edit, undo]
import insert_commands

template checkVisualEdit(state: EditorState, r: Result[(), string]) =
  ## For use inside a withTransaction body of a Visual command: on an edit
  ## failure surface the error, leave Visual mode and return from the enclosing
  ## proc. The return makes withTransaction roll back, so no partially applied
  ## edit is committed.
  let checkVisualEditResult = r
  if checkVisualEditResult.isErr:
    state.statusMessage = checkVisualEditResult.error
    state.leaveVisual()
    return

template checkVisualEditAt(
    state: EditorState, cursorBefore: BufferPosition, r: Result[(), string]
) =
  ## `checkVisualEdit` that restores cursor when loop aborts mid-selection.
  let checkVisualEditAtResult = r
  if checkVisualEditAtResult.isErr:
    state.cursor = cursorBefore
  checkVisualEdit(state, checkVisualEditAtResult)

template checkVisualEditErr(state: EditorState, r: Result[(), string]) =
  ## Like `checkVisualEdit` but returns error via Result for caller reporting.
  let checkVisualEditErrResult = r
  if checkVisualEditErrResult.isErr:
    state.leaveVisual()
    return Result[(), string].err(checkVisualEditErrResult.error)

proc getSelectionRange*(
    selection: VisualSelection
): tuple[start, endPos: BufferPosition] {.inline.} =
  ## Get the normalized selection range (start is always before end)
  ## Returns (start, end) where start <= end
  if not selection.active:
    return (selection.start, selection.start)

  # Normalize so start is always before end
  if selection.start.line < selection.current.line:
    return (selection.start, selection.current)
  elif selection.start.line > selection.current.line:
    return (selection.current, selection.start)
  else:
    # Same line - compare columns
    if selection.start.column <= selection.current.column:
      return (selection.start, selection.current)
    else:
      return (selection.current, selection.start)

proc getBlockText(buffer: TextBuffer, selection: VisualSelection): string =
  ## Get text from a block (rectangular) selection
  let
    startLine = min(selection.start.line, selection.current.line)
    endLine = max(selection.start.line, selection.current.line)
    startCol = min(selection.start.column, selection.current.column)
    endCol = max(selection.start.column, selection.current.column)

  var lines: seq[string]
  for lineNum in startLine .. endLine:
    let line = buffer.getLine(lineNum)
    let lineLen = line.charLen
    if startCol >= lineLen:
      # Line is shorter than start column, add empty string
      lines.add("")
    elif endCol >= lineLen:
      # Line is shorter than end column, take from start to end of line
      lines.add(line.charSubStr(startCol))
    else:
      # Normal case
      lines.add(line.charSubStr(startCol, endCol - startCol + 1))
  result = lines.join("\n")

proc getLineText(buffer: TextBuffer, selection: VisualSelection): string =
  ## Get text from a line-wise selection (entire lines)
  buffer.linewiseText(
    min(selection.start.line, selection.current.line),
    max(selection.start.line, selection.current.line),
  )

proc getVisualSelectionText*(buffer: TextBuffer, selection: VisualSelection): string =
  ## Get the selected text respecting the selection kind.
  ## Char selections return the char range; line selections return whole
  ## lines; block selections return the rectangle. Returns "" when inactive.
  if not selection.active:
    return ""
  case selection.kind
  of vskBlock:
    getBlockText(buffer, selection)
  of vskLine:
    getLineText(buffer, selection)
  of vskChar:
    let (selStart, selEnd) = selection.getSelectionRange()
    buffer.getTextInRange(selStart, selEnd)

proc visualYank*(buffer: TextBuffer, state: EditorState, register = none(char)) =
  ## Yank (copy) visual selection to `register` (else the yank register) and
  ## return to previous mode
  let sel = state.operandSelection(buffer)
  if sel.active:
    # Get normalized selection range
    let (selStart, _) = sel.getSelectionRange()

    let selectedText = getVisualSelectionText(buffer, sel)

    let isLine = sel.kind == vskLine

    state.registers.storeYanked(register, selectedText, isLine)

    # Move cursor to start of selection (Vim behavior)
    state.cursor = selStart
    # Clamp column to valid range for Normal mode (last char, not past end)
    let lineLen = buffer.getLine(state.cursor.line).charLen
    if lineLen > 0:
      state.cursor.column = min(state.cursor.column, lineLen - 1)
    else:
      state.cursor.column = 0

    state.statusMessage = ""
    state.leaveVisual()

proc deleteBlockSelection(
    buffer: TextBuffer,
    state: EditorState,
    sel: VisualSelection,
    deletedText: var string,
): Result[(), string] =
  ## Delete block selection; caller stores deletedText after commit.
  let
    startLine = min(sel.start.line, sel.current.line)
    endLine = max(sel.start.line, sel.current.line)
    startCol = min(sel.start.column, sel.current.column)
    endCol = max(sel.start.column, sel.current.column)

  # Get text to yank first
  deletedText = getBlockText(buffer, sel)

  # Delete from each line in reverse order to preserve line numbers
  for lineNum in countdown(endLine, startLine):
    let line = buffer.getLine(lineNum)
    let lineLen = line.charLen
    if startCol < lineLen:
      let actualEndCol = min(endCol, lineLen - 1)
      let startPos = BufferPosition(line: lineNum, column: startCol)
      let endPos = BufferPosition(line: lineNum, column: actualEndCol)
      let delResult = buffer.deleteRange(startPos, endPos)
      if delResult.isErr:
        return err(delResult.error)

  # Move cursor to start of deleted block, clamped to valid position
  state.cursor.line = startLine
  if buffer.len > 0:
    let line = buffer.getLine(startLine)
    if line.charLen > 0:
      state.cursor.column = min(startCol, line.charLen - 1)
    else:
      state.cursor.column = 0
  else:
    state.cursor.column = 0

  return ok(())

proc deleteLineSelection(
    buffer: TextBuffer,
    state: EditorState,
    sel: VisualSelection,
    deletedText: var string,
): Result[(), string] =
  ## Delete line-wise selection; caller stores deletedText after commit.
  let
    startLine = min(sel.start.line, sel.current.line)
    endLine = max(sel.start.line, sel.current.line)

  # Get text to yank first
  deletedText = getLineText(buffer, sel)

  # Delete lines from end to start to preserve line numbers. The last line is
  # deleted too, after an empty one is added below it: clearing it would keep
  # its marks and bookmarks, and the area then lands on the empty line.
  for lineNum in countdown(endLine, startLine):
    if buffer.len == 1:
      let insResult = buffer.insert(1, "")
      if insResult.isErr:
        return err(insResult.error)
    let delResult = buffer.deleteLine(lineNum)
    if delResult.isErr:
      return err(delResult.error)

  # Move cursor to start line (or last line if start was beyond buffer)
  let newLine = min(startLine, buffer.len - 1)
  state.cursor = BufferPosition(line: newLine, column: 0)

  return ok(())

proc visualDelete*(
    buffer: TextBuffer, state: EditorState, sel: VisualSelection, register = none(char)
) =
  ## Delete `sel` into `register` (else the delete registers) and return to
  ## previous mode
  if sel.active:
    var deletedText = ""
    var deletedIsLine = false

    let txr = withTransaction(buffer, "Visual delete"):
      case sel.kind
      of vskBlock:
        checkVisualEdit(state, deleteBlockSelection(buffer, state, sel, deletedText))
      of vskLine:
        checkVisualEdit(state, deleteLineSelection(buffer, state, sel, deletedText))
        deletedIsLine = true
      of vskChar:
        let (selStart, selEnd) = sel.getSelectionRange()

        deletedText = buffer.getTextInRange(selStart, selEnd)

        checkVisualEdit(state, buffer.deleteRange(selStart, selEnd))
        state.cursor = selStart
    if txr.isErr:
      if state.statusMessage.len == 0:
        state.statusMessage = txr.error
      state.leaveVisual()
      return

    # Registers are outside the buffer transaction, so store after commit.
    state.registers.storeDeleted(register, deletedText, deletedIsLine)

    # Clamp cursor to valid position after deletion
    if state.cursor.line >= buffer.len:
      state.cursor.line = max(0, buffer.len - 1)
    if buffer.len > 0:
      let line = buffer.getLine(state.cursor.line)
      if line.charLen > 0:
        state.cursor.column = min(state.cursor.column, line.charLen - 1)
      else:
        state.cursor.column = 0

    state.statusMessage = ""
    state.leaveVisual()

proc visualDelete*(buffer: TextBuffer, state: EditorState, register = none(char)) =
  ## Delete visual selection and return to previous mode
  visualDelete(buffer, state, state.operandSelection(buffer), register)

proc visualIndent*(buffer: TextBuffer, state: EditorState, count: int = 1) =
  ## Indent all lines in visual selection and return to previous mode
  let sel = state.operandSelection(buffer)
  if sel.active:
    let
      startLine = min(sel.start.line, sel.current.line)
      endLine = max(sel.start.line, sel.current.line)

    # indentLine reads the line to act on from the cursor, so the loop walks it.
    let cursorBefore = state.cursor

    let txr = withTransaction(buffer, "Visual indent"):
      for lineNum in startLine .. endLine:
        state.cursor.line = lineNum
        state.cursor.column = 0
        checkVisualEditAt(state, cursorBefore, indentLine(buffer, state, count))

      state.cursor.line = startLine
      state.cursor.column = 0
    if txr.isErr:
      if state.statusMessage.len == 0:
        state.statusMessage = txr.error
      state.leaveVisual()
      return

    state.statusMessage = ""
    state.leaveVisual()

proc visualDedent*(buffer: TextBuffer, state: EditorState, count: int = 1) =
  ## Dedent all lines in visual selection and return to previous mode
  let sel = state.operandSelection(buffer)
  if sel.active:
    let
      startLine = min(sel.start.line, sel.current.line)
      endLine = max(sel.start.line, sel.current.line)

    # dedentLine reads the line to act on from the cursor, so the loop walks it.
    let cursorBefore = state.cursor

    let txr = withTransaction(buffer, "Visual dedent"):
      for lineNum in startLine .. endLine:
        state.cursor.line = lineNum
        state.cursor.column = 0
        checkVisualEditAt(state, cursorBefore, dedentLine(buffer, state, count))

      state.cursor.line = startLine
      state.cursor.column = 0
    if txr.isErr:
      if state.statusMessage.len == 0:
        state.statusMessage = txr.error
      state.leaveVisual()
      return

    state.statusMessage = ""
    state.leaveVisual()

proc applyVisualTextTransform(
    buffer: TextBuffer,
    state: EditorState,
    label: string,
    action: string,
    transform: proc(text: string): string {.closure, gcsafe.},
) =
  ## Apply transform to selection; refused for raw buffers.
  let sel = state.operandSelection(buffer)
  if not sel.active:
    return

  let (selStart, selEnd) = sel.getSelectionRange()

  let txr = withTransaction(buffer, label):
    case sel.kind
    of vskBlock:
      let
        startLine = min(sel.start.line, sel.current.line)
        endLine = max(sel.start.line, sel.current.line)
        startCol = min(sel.start.column, sel.current.column)
        endCol = max(sel.start.column, sel.current.column)

      for lineNum in startLine .. endLine:
        let line = buffer.getLine(lineNum)
        let lineLen = line.charLen
        if startCol < lineLen:
          let actualEndCol = min(endCol, lineLen - 1)
          let startPos = BufferPosition(line: lineNum, column: startCol)
          let endPos = BufferPosition(line: lineNum, column: actualEndCol)
          checkVisualEdit(
            state, buffer.transformRange(startPos, endPos, action, transform)
          )
    of vskLine:
      let
        startLine = min(sel.start.line, sel.current.line)
        endLine = max(sel.start.line, sel.current.line)

      checkVisualEdit(
        state, buffer.replaceWholeLines(startLine, endLine, action, transform)
      )
    of vskChar:
      checkVisualEdit(state, buffer.transformRange(selStart, selEnd, action, transform))

    state.cursor = selStart
  if txr.isErr:
    if state.statusMessage.len == 0:
      state.statusMessage = txr.error
    state.leaveVisual()
    return

  state.statusMessage = ""
  state.leaveVisual()

proc visualLowercase*(buffer: TextBuffer, state: EditorState) =
  ## Convert visual selection to lowercase and return to previous mode
  applyVisualTextTransform(buffer, state, "Visual lowercase", "lowercase", toLowerAscii)

proc visualUppercase*(buffer: TextBuffer, state: EditorState) =
  ## Convert visual selection to uppercase and return to previous mode
  applyVisualTextTransform(buffer, state, "Visual uppercase", "uppercase", toUpperAscii)

proc visualToggleCase*(buffer: TextBuffer, state: EditorState) =
  ## Toggle case of visual selection and return to previous mode
  applyVisualTextTransform(
    buffer, state, "Visual toggle case", "toggle case", toggleAsciiCase
  )

proc visualReplace*(buffer: TextBuffer, state: EditorState, ch: string) =
  ## Replace selection with `ch` (one char). Refused for raw buffers.
  # Registry validates `ch`; this guard is for direct callers.
  if ch.charLen != 1:
    return

  # One `ch` per character; preserve newlines for multi-line selections.
  let fill = proc(text: string): string =
    var first = true
    for segment in text.split('\n'):
      if not first:
        result.add('\n')
      first = false
      result.add(ch.repeat(segment.charLen))

  applyVisualTextTransform(buffer, state, "Visual replace", "replace", fill)

proc visualJoinLines*(buffer: TextBuffer, state: EditorState) =
  ## Join all lines in visual selection into one line (J command)
  let sel = state.operandSelection(buffer)
  if sel.active:
    # Get line range
    let
      startLine = min(sel.start.line, sel.current.line)
      endLine = max(sel.start.line, sel.current.line)

    # Need at least 2 lines to join
    if startLine == endLine:
      # Only one line selected, nothing to join
      state.statusMessage = ""
      state.leaveVisual()
      return

    # Calculate number of joins needed (lines - 1)
    let joinCount = endLine - startLine

    # Use buffer's joinLines which handles the transaction
    let result = buffer.joinLines(startLine, joinCount)
    if result.isErr:
      state.statusMessage = result.error
    else:
      state.statusMessage = $joinCount & " lines joined"

    # Move cursor to the start line
    state.cursor.line = startLine
    state.cursor.column = 0

    state.leaveVisual()

proc visualToInsertMode*(buffer: TextBuffer, state: EditorState) =
  ## Switch from visual mode to insert mode (I command)
  ## For block mode: moves cursor to (startLine, startCol) and sets up
  ## VisualBlockInsertContext for text replication across all selected lines.
  ## For other modes: moves cursor to (startLine, 0).
  let sel = state.operandSelection(buffer)

  if sel.active:
    let startLine = min(sel.start.line, sel.current.line)

    if sel.kind == vskBlock:
      let startCol = min(sel.start.column, sel.current.column)
      let endLine = max(sel.start.line, sel.current.line)
      state.cursor.line = startLine
      state.cursor.column = startCol
      state.editState.visualBlockInsertContext = some(
        VisualBlockInsertContext(
          kind: vbiInsert,
          startLine: startLine,
          endLine: endLine,
          insertColumn: startCol,
          firstLineLen: buffer.getLine(startLine).charLen,
        )
      )
    else:
      state.cursor.line = startLine
      state.cursor.column = 0

  # Save current mode for returning with ESC
  state.previousMode = state.mode

  # Switch to insert mode
  state.mode = EditorMode.Insert

proc visualBlockAppend*(buffer: TextBuffer, state: EditorState) =
  ## Switch from visual block mode to insert mode at end of block (A command)
  ## Moves cursor to (startLine, endCol + 1) and sets up
  ## VisualBlockInsertContext for text replication across all selected lines.
  ## A selection a closed fold turned line-shaped has no block columns to
  ## replicate into, so it appends at the end of the last selected line.
  let sel = state.operandSelection(buffer)
  if not sel.active:
    return

  if sel.kind != vskBlock:
    let endLine = max(sel.start.line, sel.current.line)
    state.cursor.line = endLine
    state.cursor.column = buffer.getLine(endLine).charLen
    state.previousMode = state.mode
    state.mode = EditorMode.Insert
    return

  let startLine = min(sel.start.line, sel.current.line)
  let endLine = max(sel.start.line, sel.current.line)
  let endCol = max(sel.start.column, sel.current.column)

  state.cursor.line = startLine
  state.cursor.column = endCol + 1
  state.editState.visualBlockInsertContext = some(
    VisualBlockInsertContext(
      kind: vbiAppend,
      startLine: startLine,
      endLine: endLine,
      insertColumn: endCol + 1,
      firstLineLen: buffer.getLine(startLine).charLen,
    )
  )

  # Save current mode for returning with ESC
  state.previousMode = state.mode

  # Switch to insert mode
  state.mode = EditorMode.Insert

proc visualChange*(buffer: TextBuffer, state: EditorState, register = none(char)) =
  ## Delete visual selection into `register` (else the delete registers) and
  ## enter insert mode (c command)
  let sel = state.operandSelection(buffer)
  if sel.active:
    var deletedText = ""
    var deletedIsLine = false

    let txr = withTransaction(buffer, "Visual change"):
      case sel.kind
      of vskBlock:
        let startCol = min(sel.start.column, sel.current.column)
        let startLine = min(sel.start.line, sel.current.line)
        let endLine = max(sel.start.line, sel.current.line)
        checkVisualEdit(state, deleteBlockSelection(buffer, state, sel, deletedText))
        state.cursor.line = startLine
        state.cursor.column = startCol
        state.editState.visualBlockInsertContext = some(
          VisualBlockInsertContext(
            kind: vbiChange,
            startLine: startLine,
            endLine: endLine,
            insertColumn: startCol,
            firstLineLen: buffer.getLine(startLine).charLen,
          )
        )
      of vskLine:
        let
          startLine = min(sel.start.line, sel.current.line)
          endLine = max(sel.start.line, sel.current.line)

        deletedText = getLineText(buffer, sel)
        deletedIsLine = true

        # The first line stays with only its indent under autoindent, as `cc`.
        let indent =
          if state.autoIndent and buffer.allowsTextTransforms:
            getLineIndent(buffer.getLine(startLine))
          else:
            ""
        for _ in startLine + 1 .. endLine:
          checkVisualEdit(state, buffer.deleteLine(startLine + 1))
        checkVisualEdit(state, buffer.replaceLine(startLine, indent))
        state.cursor.line = startLine
        state.cursor.column = indent.len
      of vskChar:
        let (selStart, selEnd) = sel.getSelectionRange()

        deletedText = buffer.getTextInRange(selStart, selEnd)

        checkVisualEdit(state, buffer.deleteRange(selStart, selEnd))

        state.cursor = selStart
    if txr.isErr:
      if state.statusMessage.len == 0:
        state.statusMessage = txr.error
      state.leaveVisual()
      return

    # Registers are outside the buffer transaction, so store after commit.
    state.registers.storeDeleted(register, deletedText, deletedIsLine)

    state.previousMode = EditorMode.Normal # c always returns to Normal on ESC
    state.mode = EditorMode.Insert

proc visualSwapSelection*(buffer: TextBuffer, state: EditorState) =
  ## Swap the cursor between the start and end of the selection (o command)
  let sel = state.activeWindow.visualSelection
  if sel.active:
    state.selectVisualRange(anchor = sel.current, focus = sel.start)

proc reselectVisual*(
    buffer: TextBuffer, state: EditorState
): Result[EditorMode, string] =
  ## `gv`: select the buffer's last Visual area again, in the mode it had, and
  ## return that mode. From Visual mode the current and last areas swap.
  if buffer.lastVisual.isNone or buffer.lastVisual.get.start.line >= buffer.len:
    return Result[EditorMode, string].err "No previous visual selection"

  let area = buffer.lastVisual.get
  if state.mode.isVisualAllMode:
    state.activeWindow.saveLastVisual()

  proc clamped(pos: BufferPosition): BufferPosition =
    # Visual mode lets the column rest one past the end of the line.
    let line = min(pos.line, buffer.len - 1)
    BufferPosition(line: line, column: min(pos.column, buffer.getLine(line).charLen))

  state.enterVisual(area.kind, clamped(area.start), clamped(area.cursor))
  state.preferredColumn = -1
  Result[EditorMode, string].ok area.kind.visualMode

proc visualPaste*(
    buffer: TextBuffer,
    state: EditorState,
    clipboardConfig: ClipboardConfig = ClipboardConfig(enable: false, tool: cbtXclip),
    cursorAfter: bool = false,
    register = none(char),
    keepRegisters = false,
    before = false,
): Result[(), string] =
  ## Delete selection and paste the content of `register` (else the unnamed
  ## one). The deleted text goes to the registers as a delete's does, unless
  ## `keepRegisters` (Vim's `v_P`). `before` is `P`/`gP`, which put lines
  ## above a block rather than below it.
  let sel = state.operandSelection(buffer)
  result = Result[(), string].ok ()
  if sel.active:
    let regName = register.get('"')
    let put = state.registers.textToPut(regName, clipboardConfig)
    if put.isErr:
      state.leaveVisual()
      return Result[(), string].err(put.error)
    let
      isFullLine = put.get.isLine
      pasteText = buffer.preparePastedText(put.get.getContent)

    # Like Vim, the selection goes even when there is nothing to put. The black
    # hole register puts an empty string, which over whole lines is a blank
    # line; an empty register puts nothing and reports it.
    let putsNothing =
      pasteText.len == 0 and not isFullLine and not regName.isBlackHoleRegisterName

    var deletedText = ""
    var deletedIsLine = false
    let cursorBeforePaste = state.cursor
    let selKind = sel.kind
    var pasteStart = BufferPosition()
    var pastedLineCount = 0

    template checkPasteErr(r: Result[(), string]) =
      ## Like checkVisualEditErr but also restores cursor for rollback.
      let checkPasteErrResult = r
      if checkPasteErrResult.isErr:
        state.cursor = cursorBeforePaste
        checkVisualEditErr(state, checkPasteErrResult)

    let txr = withTransaction(buffer, "Visual paste"):
      case sel.kind
      of vskBlock:
        checkPasteErr(deleteBlockSelection(buffer, state, sel, deletedText))
        let
          firstLine = min(sel.start.line, sel.current.line)
          startColumn = min(sel.start.column, sel.current.column)
        if isFullLine:
          # Like Vim, lines go below the line the cursor ended on (its
          # b_visual.vi_end, which can be the top one), or above the block
          # for `P`. `P` puts them below the first line when the block
          # reached its end, as the cursor then rests before where it was.
          let firstLen = buffer.getLine(firstLine).charLen
          if before and not (startColumn > 0 and startColumn >= firstLen):
            checkPasteErr(
              buffer.insertText(BufferPosition(line: firstLine, column: 0), pasteText)
            )
            pasteStart = BufferPosition(line: firstLine, column: 0)
          else:
            let afterLine = if before: firstLine else: sel.current.line
            checkPasteErr(
              buffer.insertText(
                BufferPosition(
                  line: afterLine, column: buffer.getLine(afterLine).charLen
                ),
                "\n" & pasteText.withoutLastLineBreak,
              )
            )
            pasteStart = BufferPosition(line: afterLine + 1, column: 0)
          pastedLineCount = pasteText.count('\n')
        else:
          pasteStart = BufferPosition(line: firstLine, column: startColumn)
          if pasteText.len > 0:
            checkPasteErr(buffer.insertText(pasteStart, pasteText))
        state.cursor = pasteStart
      of vskLine:
        let
          startLine = min(sel.start.line, sel.current.line)
          endLine = max(sel.start.line, sel.current.line)

        deletedText = getLineText(buffer, sel)
        deletedIsLine = true

        for _ in startLine .. endLine:
          checkPasteErr(buffer.deleteLine(startLine))

        var lines: seq[string]
        if not putsNothing:
          lines = pasteText.linewiseLines
        if lines.len == 0 and buffer.len == 0:
          # The selection was every line, and a buffer keeps one.
          lines.add ""
        pastedLineCount = lines.len
        for i, line in lines:
          checkPasteErr(buffer.insert(startLine + i, line))
        pasteStart = BufferPosition(line: min(startLine, buffer.len - 1), column: 0)
        state.cursor = pasteStart
      of vskChar:
        let (selStart, selEnd) = sel.getSelectionRange()

        deletedText = buffer.getTextInRange(selStart, selEnd)

        checkPasteErr(buffer.deleteRange(selStart, selEnd))

        if isFullLine:
          # Like Vim, lines go on lines of their own: the line splits where
          # the selection was, and they go between.
          checkPasteErr(buffer.insertText(selStart, "\n" & pasteText))
          pasteStart = BufferPosition(line: selStart.line + 1, column: 0)
          pastedLineCount = pasteText.count('\n')
        else:
          pasteStart = selStart
          if pasteText.len > 0:
            checkPasteErr(buffer.insertText(selStart, pasteText))
        state.cursor = pasteStart
    if txr.isErr:
      # The transaction rolled the buffer back, so the paste anchor is gone.
      state.cursor = cursorBeforePaste
      state.leaveVisual()
      return Result[(), string].err(txr.error)

    # Registers are not covered by the buffer transaction, so write the
    # replaced text only after the transaction committed.
    if not keepRegisters:
      state.registers.storeDeleted(none(char), deletedText, deletedIsLine)

    state.statusMessage = ""
    state.leaveVisual()
    if pasteText.len == 0:
      # The deletion may have left the cursor past the end of its line.
      clampCursorToLastChar(state.cursor, buffer.getLine(state.cursor.line).charLen)

    let
      lastPutLine = min(pasteStart.line + max(pastedLineCount, 1) - 1, buffer.len - 1)
      afterPut = pasteEndPos(pasteStart, pasteText)
      putLines = selKind == vskLine or isFullLine

    # Like Vim, the next `gv` selects the put text, in the mode the replaced
    # selection had.
    let putEnd =
      if putLines:
        BufferPosition(
          line: lastPutLine, column: max(0, buffer.getLine(lastPutLine).charLen - 1)
        )
      elif pasteText.len == 0:
        pasteStart
      elif afterPut.column > 0:
        BufferPosition(line: afterPut.line, column: afterPut.column - 1)
      else:
        BufferPosition(
          line: afterPut.line - 1, column: buffer.getLine(afterPut.line - 1).charLen
        )
    buffer.lastVisual =
      some(VisualArea(start: pasteStart, cursor: putEnd, kind: selKind))

    if putLines:
      # Like Vim's put of lines, the cursor goes to the first non-blank.
      state.cursor.column = firstNonBlankColumn(buffer.getLine(state.cursor.line))

    if cursorAfter and buffer.len > 0:
      if putLines:
        let afterLine = lastPutLine + 1
        if afterLine < buffer.len:
          state.cursor.line = afterLine
          state.cursor.column = 0
        else:
          # Unlike Normal gp: col 0 unless the put replaced the whole buffer
          # (then last char).
          state.cursor.line = lastPutLine
          if pasteStart.line == 0:
            let lineLen = buffer.getLine(state.cursor.line).charLen
            state.cursor.column = lineLen
            clampCursorToLastChar(state.cursor, lineLen)
          else:
            state.cursor.column = 0
      else:
        state.cursor = afterPut
        if buffer.len > 0:
          clampCursorToLastChar(state.cursor, buffer.getLine(state.cursor.line).charLen)

    if putsNothing:
      result = Result[(), string].err(nothingInRegister(regName))

const SurroundPairs = [
  ("(", ")"),
  ("[", "]"),
  ("{", "}"),
  ("<", ">"),
  ("「", "」"),
  ("『", "』"),
  ("（", "）"),
  ("［", "］"),
  ("｛", "｝"),
  ("〈", "〉"),
  ("《", "》"),
  ("【", "】"),
  ("〔", "〕"),
  ("“", "”"),
  ("‘", "’"),
] ## Paired brackets with distinct open/close; either side selects the pair.

proc getSurroundPair(ch: string): tuple[open, close: string] =
  ## Get the open/close pair for a surround character.
  for pair in SurroundPairs:
    if ch == pair[0] or ch == pair[1]:
      return pair
  # Quotes and other characters: same for open and close
  return (ch, ch)

proc visualSurround*(buffer: TextBuffer, state: EditorState, ch: string) =
  ## Surround selection with `ch`'s pair; multi-byte brackets stay intact.
  let sel = state.operandSelection(buffer)
  # Registry validates `ch`; this guard is for direct callers (see visualReplace).
  if ch.charLen != 1:
    return

  if sel.active:
    let (openChar, closeChar) = getSurroundPair(ch)
    let (selStart, selEnd) = sel.getSelectionRange()

    let txr = withTransaction(buffer, "Visual surround"):
      case sel.kind
      of vskChar:
        let afterEnd = BufferPosition(line: selEnd.line, column: selEnd.column + 1)
        checkVisualEdit(state, buffer.insertText(afterEnd, closeChar))
        checkVisualEdit(state, buffer.insertText(selStart, openChar))
      of vskLine:
        let
          startLine = min(sel.start.line, sel.current.line)
          endLine = max(sel.start.line, sel.current.line)
        for lineNum in countdown(endLine, startLine):
          let lineLen = buffer.getLine(lineNum).charLen
          let lineEnd = BufferPosition(line: lineNum, column: lineLen)
          checkVisualEdit(state, buffer.insertText(lineEnd, closeChar))
          let lineStart = BufferPosition(line: lineNum, column: 0)
          checkVisualEdit(state, buffer.insertText(lineStart, openChar))
      of vskBlock:
        let
          startLine = min(sel.start.line, sel.current.line)
          endLine = max(sel.start.line, sel.current.line)
          startCol = min(sel.start.column, sel.current.column)
          endCol = max(sel.start.column, sel.current.column)
        for lineNum in countdown(endLine, startLine):
          let lineLen = buffer.getLine(lineNum).charLen
          if startCol < lineLen:
            let actualEndCol = min(endCol, lineLen - 1)
            let afterEnd = BufferPosition(line: lineNum, column: actualEndCol + 1)
            checkVisualEdit(state, buffer.insertText(afterEnd, closeChar))
            let colStart = BufferPosition(line: lineNum, column: startCol)
            checkVisualEdit(state, buffer.insertText(colStart, openChar))

      state.cursor = selStart
    if txr.isErr:
      if state.statusMessage.len == 0:
        state.statusMessage = txr.error
      state.leaveVisual()
      return

    state.statusMessage = ""
    state.leaveVisual()
