#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

## Main buffer interface

import std/[unicode, options, strutils, deques, os]

import pkg/results

import gapbuffer, cursor, unicode_utils, encoding, highlight, logger

export CharacterEncoding, encodingToString, detectCharacterEncoding

type
  SidebarItemKind* = enum
    ## Type of sidebar indicator
    GitAdded ## Line was added in git diff
    GitChanged ## Line was changed in git diff
    GitDeleted ## Line was deleted in git diff
    GitChangedAndDeleted ## Line was changed and deleted in git diff
    SyntaxError ## Syntax error indicator
    SyntaxWarning ## Syntax warning indicator
    Empty ## Empty sidebar cell

  LineEnding* = enum
    LF
    CRLF
    CR

  BufferBackend* = enum
    GapBuffer # Best for small to medium files

  # Undo/Redo system types
  BufferChangeKind* = enum
    ckInsertText
    ckDeleteText
    ckInsertLine
    ckDeleteLine
    ckDeleteRange
    ckTransaction # Transaction containing multiple changes

  BufferChange* = object
    case kind*: BufferChangeKind
    of ckInsertText:
      insertPos*: BufferPosition
      insertText*: string
    of ckDeleteText:
      deletePos*: BufferPosition
      deletedText*: string
    of ckInsertLine:
      insertLineIdx*: int
      insertLineText*: string
    of ckDeleteLine:
      deleteLineIdx*: int
      deletedLineText*: string
    of ckDeleteRange:
      deleteStartPos*: BufferPosition
      deleteEndPos*: BufferPosition
      deletedRangeText*: string
    of ckTransaction:
      transactionChanges*: seq[BufferChange]
      transactionDescription*: string

  # Transaction for grouping multiple changes
  BufferTransaction* = object
    changes*: seq[BufferChange]
    description*: string
    startSeq*: int # changeSeq at the start of transaction

  TextBuffer* = ref object
    backend*: BufferBackend
    filePath*: Option[string]
    readOnly*: bool
    lineEnding*: LineEnding
    encoding*: CharacterEncoding
    endOfLine*: bool # Whether file should end with newline

    # Undo/Redo stacks (using Deque for O(1) operations at both ends)
    undoStack*: Deque[BufferChange]
    redoStack*: Deque[BufferChange]

    # Change sequence tracking for modified flag
    changeSeq*: int # Current change sequence number
    savedSeq*: int # Sequence number when file was last saved

    # Transaction support
    currentTransaction*: Option[BufferTransaction]
    inTransaction*: bool

    # Sidebar markers (line-based markers for git diff, syntax errors, etc.)
    lineMarkers*: seq[Option[SidebarItemKind]] # Each line can have at most one marker

    # Syntax highlighting
    highlight*: Highlight # Syntax highlighting for this buffer
    language*: SourceLanguage # Programming language for syntax highlighting
    highlightNeedsUpdate*: bool # Flag to track if highlight needs regeneration
    incrementalHighlight*: IncrementalHighlight # Incremental highlighting cache
    lastChangedLines*: tuple[start, theEnd: int] # Last edit range for incremental update

    # Performance optimization
    cursorCache*: CursorPosCache # Cache for character-to-byte position conversions

    # Backend storage
    case backendKind*: BufferBackend
    of GapBuffer:
      gapBuffer*: GapBuffer

proc chooseBackend(): BufferBackend =
  GapBuffer

proc isModified*(b: TextBuffer): bool {.inline.} =
  ## Check if buffer has unsaved changes
  b.changeSeq != b.savedSeq

proc `modified=`*(
    b: TextBuffer, value: bool
) {.deprecated: "Use saveFile to mark as unmodified".} =
  ## Deprecated: modified flag is now managed automatically
  ## Set savedSeq to current changeSeq if value is false
  if not value:
    b.savedSeq = b.changeSeq

proc newTextBuffer*(
    content: string = "", filePath: Option[string] = none(string)
): TextBuffer =
  let backend = chooseBackend()

  case backend
  of GapBuffer:
    let gb = newGapBuffer(content)
    # Convert buffer to Runes sequence for highlighting
    var runesBuffer: seq[Runes] = @[]
    for i in 0 ..< gb.len:
      runesBuffer.add(gb.getLine(i).toRunes())

    TextBuffer(
      backendKind: GapBuffer,
      backend: backend,
      filePath: filePath,
      readOnly: false,
      lineEnding: LF,
      encoding: utf8,
      endOfLine: true, # Default to POSIX text file standard
      gapBuffer: gb,
      undoStack: initDeque[BufferChange](),
      redoStack: initDeque[BufferChange](),
      changeSeq: 0, # Initial sequence number
      savedSeq: 0, # Starts as saved (no changes)
      currentTransaction: none(BufferTransaction),
      inTransaction: false,
      lineMarkers: newSeq[Option[SidebarItemKind]](gb.len),
      # Initialize with plain text highlighting (no language)
      highlight: initHighlight(runesBuffer),
      language: SourceLanguage.langNone,
      highlightNeedsUpdate: false,
      incrementalHighlight: nil,
      lastChangedLines: (0, 0),
      # Initialize cursor position cache (invalid state)
      cursorCache: CursorPosCache(line: -1, charPos: 0, bytePos: 0, changeSeq: -1),
    )

# Core text operations
proc getTextString*(b: TextBuffer): string =
  case b.backendKind
  of GapBuffer:
    $b.gapBuffer

proc len*(b: TextBuffer): int =
  ## Get number of lines in buffer
  case b.backendKind
  of GapBuffer: b.gapBuffer.len

proc charLen*(text: string): int =
  ## Get character length (not byte length)
  text.runeLen

proc getLine*(b: TextBuffer, lineIndex: int): string =
  case b.backendKind
  of GapBuffer:
    b.gapBuffer.getLine(lineIndex)

proc `[]`*(b: TextBuffer, lineIndex: int): string =
  ## Bracket operator for accessing lines by index
  b.getLine(lineIndex)

proc getLineLen*(b: TextBuffer, lineIndex: int): int =
  b.getLine(lineIndex).len

proc `[][]`*(b: TextBuffer, lineIndex, colIndex: int): char =
  ## Bracket operator for accessing character at (line, column)
  b[lineIndex][colIndex]

# Forward declarations for undo system
proc getChangePosition(change: BufferChange): BufferPosition
proc pushUndoChange(b: TextBuffer, change: BufferChange)
proc undoChange(b: TextBuffer, change: BufferChange): Result[(), string]
# Forward declaration for sidebar marker management
proc ensureMarkersSize(b: TextBuffer)
# Forward declaration for text insertion with newlines
proc insertTextWithNewlines(b: TextBuffer, pos: BufferPosition, text: string)

# Editing operations
proc insertText*(b: TextBuffer, pos: BufferPosition, text: string): Result[(), string] =
  ## Insert text at the specified position
  ## Handles newlines by splitting lines as needed
  ## Returns error if position is out of bounds
  if text.len == 0:
    return ok(())

  if pos.line < 0 or pos.line >= b.len:
    return err("Line position out of bounds: " & $pos.line)

  if pos.column < 0:
    return err("Column position cannot be negative: " & $pos.column)

  case b.backendKind
  of GapBuffer:
    try:
      # Use insertTextWithNewlines to handle newlines correctly
      b.insertTextWithNewlines(pos, text)
    except IndexDefect as e:
      return err("Failed to insert text: " & e.msg)

  # Record change for undo
  b.pushUndoChange(BufferChange(kind: ckInsertText, insertPos: pos, insertText: text))

  return ok(())

proc deleteChar*(b: TextBuffer, pos: BufferPosition): Result[(), string] =
  ## Delete a single Unicode character at the specified position
  ## Returns error if position is out of bounds
  if pos.line < 0 or pos.line >= b.len:
    return err("Line position out of bounds: " & $pos.line)

  if pos.column < 0:
    return err("Column position cannot be negative: " & $pos.column)

  case b.backendKind
  of GapBuffer:
    let line = b.getLine(pos.line)
    if pos.column >= line.charLen:
      return err("Column position out of bounds: " & $pos.column)

    try:
      # Get the character that will be deleted for undo
      let
        deletedChar = line.runeAtPos(pos.column)
        charSize = len($deletedChar)
        bytePos =
          charToBytePosCached(line, pos.column, b.cursorCache, pos.line, b.changeSeq)

      # Delete character at byte position
      b.gapBuffer.deleteAtLineCol(pos.line, bytePos, charSize)

      # Record change for undo
      b.pushUndoChange(
        BufferChange(kind: ckDeleteText, deletePos: pos, deletedText: $deletedChar)
      )
    except IndexDefect as e:
      return err("Failed to delete character: " & e.msg)

  return ok(())

proc insert*(b: TextBuffer, lineIndex: int, content: string): Result[(), string] =
  ## Insert a new line at the specified index
  ## Returns error if lineIndex is out of valid range [0..len]
  if lineIndex < 0 or lineIndex > b.len:
    return err("Line index out of valid range [0.." & $b.len & "]: " & $lineIndex)

  case b.backendKind
  of GapBuffer:
    try:
      b.gapBuffer.insertLine(lineIndex, content)
    except IndexDefect as e:
      return err("Failed to insert line: " & e.msg)

  # Insert marker entry (none by default)
  if lineIndex < b.lineMarkers.len:
    b.lineMarkers.insert(none(SidebarItemKind), lineIndex)
  elif lineIndex == b.lineMarkers.len:
    b.lineMarkers.add(none(SidebarItemKind))

  # Record change for undo
  b.pushUndoChange(
    BufferChange(kind: ckInsertLine, insertLineIdx: lineIndex, insertLineText: content)
  )

  return ok(())

proc deleteLine*(b: TextBuffer, lineIndex: int): Result[(), string] =
  ## Delete the line at the specified index
  ## Returns error if lineIndex is out of bounds
  if lineIndex < 0 or lineIndex >= b.len:
    return err("Line index out of bounds: " & $lineIndex)

  # Save line content before deleting for undo
  let deletedContent = b.getLine(lineIndex)

  case b.backendKind
  of GapBuffer:
    try:
      b.gapBuffer.deleteLine(lineIndex)
    except IndexDefect as e:
      return err("Failed to delete line: " & e.msg)

  # Delete corresponding marker entry
  if lineIndex < b.lineMarkers.len:
    b.lineMarkers.delete(lineIndex)

  # Record change for undo
  b.pushUndoChange(
    BufferChange(
      kind: ckDeleteLine, deleteLineIdx: lineIndex, deletedLineText: deletedContent
    )
  )

  return ok(())

proc getTextInRange*(b: TextBuffer, startPos, endPos: BufferPosition): string =
  ## Get text from startPos to endPos (inclusive)
  ## Both positions use character indices (not byte indices)
  ## If positions are out of bounds, they are clamped to valid range
  if startPos.line == endPos.line:
    # Single line case
    let line = b[startPos.line]
    let lineLen = line.charLen

    # Clamp positions to valid range
    let
      startCol = min(startPos.column, lineLen)
      endCol = min(endPos.column, lineLen)

    if endCol >= lineLen:
      # Selection extends to/past line end - include newline
      if startCol >= lineLen:
        result = "\n"
      else:
        result = line.runeSubStr(startCol) & "\n"
    else:
      # Selection within line
      if startCol >= lineLen:
        result = ""
      elif startCol == endCol:
        # Single character
        result = $line.runeAtPos(startCol)
      else:
        result = line.runeSubStr(startCol, endCol - startCol + 1)
  else:
    # Multi-line range
    for lineIdx in startPos.line .. endPos.line:
      let line = b.getLine(lineIdx)
      let lineLen = line.charLen

      if lineIdx == startPos.line:
        # First line: from startPos.column to end
        let startCol = min(startPos.column, lineLen)
        if startCol >= lineLen:
          result &= "\n"
        else:
          result &= line.runeSubStr(startCol) & "\n"
      elif lineIdx == endPos.line:
        # Last line: from beginning to endPos.column
        let endCol = min(endPos.column, lineLen)
        if endCol >= lineLen:
          result &= line & "\n"
        else:
          result &= line.runeSubStr(0, endCol + 1)
      else:
        # Middle lines: entire line
        result &= line & "\n"

proc buildMergedLine(prefix: string, suffix: string): string {.inline.} =
  ## Helper to build a merged line from prefix and suffix
  prefix & suffix

proc deleteRangeSingleLine(
    b: TextBuffer, line: string, startPos, endPos: BufferPosition
) =
  ## Handle single-line deletion
  let lineLen = line.charLen

  # Check if selection extends to or past line end (includes newline)
  if endPos.column >= lineLen:
    # Delete from startPos to end of line, then join with next line
    if endPos.line < b.len - 1:
      # Multi-line: join with next line
      let nextLine = b.getLine(endPos.line + 1)
      let prefix =
        if startPos.column < lineLen:
          line.runeSubStr(0, startPos.column)
        else:
          ""
      let newLine = buildMergedLine(prefix, nextLine)

      # Delete current and next line, insert combined
      b.gapBuffer.deleteLine(endPos.line + 1)
      b.gapBuffer.deleteLine(startPos.line)
      b.gapBuffer.insertLine(startPos.line, newLine)
    else:
      # Last line: just delete to end
      let newLine =
        if startPos.column < lineLen:
          line.runeSubStr(0, startPos.column)
        else:
          ""
      b.gapBuffer.deleteLine(startPos.line)
      b.gapBuffer.insertLine(startPos.line, newLine)
  elif startPos.column < lineLen and endPos.column < lineLen:
    # Normal single-line deletion within bounds
    # Build new line by concatenating prefix and suffix using Unicode-safe substring
    let prefix = line.runeSubStr(0, startPos.column)
    let suffix = line.runeSubStr(endPos.column + 1)
    let newLine = buildMergedLine(prefix, suffix)

    b.gapBuffer.deleteLine(startPos.line)
    b.gapBuffer.insertLine(startPos.line, newLine)

  # Ensure lineMarkers stays in sync after direct gapBuffer operations
  b.ensureMarkersSize()

proc deleteRangeMultiLine(b: TextBuffer, startPos, endPos: BufferPosition) =
  ## Handle multi-line deletion
  let
    startLine = b.getLine(startPos.line)
    endLine = b.getLine(endPos.line)
    endLineLen = endLine.charLen

  # Build prefix (chars before selection start)
  let prefix =
    if startPos.column <= startLine.charLen:
      startLine.runeSubStr(0, startPos.column)
    else:
      ""

  # Build suffix (chars after selection end)
  var suffix = ""
  var extraLineToDelete = -1

  if endPos.column < endLineLen:
    # Selection ends within the line - keep remaining chars
    suffix = endLine.runeSubStr(endPos.column + 1)
  elif endPos.line < b.len - 1:
    # Selection extends to/past line end - join with next line instead
    suffix = b.getLine(endPos.line + 1)
    extraLineToDelete = endPos.line + 1

  # Delete extra line if needed
  if extraLineToDelete >= 0:
    b.gapBuffer.deleteLine(extraLineToDelete)

  # Replace startPos.line with the merged line
  b.gapBuffer.deleteLine(startPos.line)
  b.gapBuffer.insertLine(startPos.line, buildMergedLine(prefix, suffix))

  # Delete lines between startPos and endPos (if any)
  if endPos.line > startPos.line:
    for i in countdown(endPos.line, startPos.line + 1):
      b.gapBuffer.deleteLine(i)

  # Ensure lineMarkers stays in sync after direct gapBuffer operations
  b.ensureMarkersSize()

proc deleteRange*(b: TextBuffer, startPos, endPos: BufferPosition): Result[(), string] =
  ## Delete text from startPos to endPos (inclusive)
  ## Assumes startPos <= endPos (normalized range)
  ## If selection extends to/past line end, includes the newline
  ## Returns error if positions are out of bounds

  if startPos.line < 0 or startPos.line >= b.len:
    return err("Start line position out of bounds: " & $startPos.line)

  if endPos.line < 0 or endPos.line >= b.len:
    return err("End line position out of bounds: " & $endPos.line)

  if startPos.column < 0 or endPos.column < 0:
    return err("Column positions cannot be negative")

  # Save deleted text for undo
  let deletedText = b.getTextInRange(startPos, endPos)

  case b.backendKind
  of GapBuffer:
    try:
      if startPos.line == endPos.line:
        b.deleteRangeSingleLine(b.getLine(startPos.line), startPos, endPos)
      else:
        b.deleteRangeMultiLine(startPos, endPos)
    except IndexDefect as e:
      return err("Failed to delete range: " & e.msg)

  # Record change for undo
  b.pushUndoChange(
    BufferChange(
      kind: ckDeleteRange,
      deleteStartPos: startPos,
      deleteEndPos: endPos,
      deletedRangeText: deletedText,
    )
  )

  return ok(())

proc splitLine*(b: TextBuffer, pos: BufferPosition): Result[(), string] =
  ## Split line at the specified position by inserting a newline
  ## Returns error if position is out of bounds
  b.insertText(pos, "\n")

# Undo/Redo system

proc pushUndoChange(b: TextBuffer, change: BufferChange) =
  ## Add a change to the undo stack (or current transaction)
  ## Always increments changeSeq to mark buffer as modified

  # Clear redo stack when new change is made
  b.redoStack.clear()

  # Increment change sequence number (marks as modified)
  b.changeSeq.inc

  # Mark highlight as needing update and track changed range
  b.highlightNeedsUpdate = true

  # Track the range of changed lines for incremental highlighting
  case change.kind
  of ckInsertText:
    let numNewlines = change.insertText.count('\n')
    b.lastChangedLines = (change.insertPos.line, change.insertPos.line + numNewlines)
  of ckDeleteText:
    b.lastChangedLines = (change.deletePos.line, change.deletePos.line)
  of ckInsertLine:
    b.lastChangedLines = (change.insertLineIdx, change.insertLineIdx)
  of ckDeleteLine:
    b.lastChangedLines = (change.deleteLineIdx, change.deleteLineIdx)
  of ckDeleteRange:
    b.lastChangedLines = (change.deleteStartPos.line, change.deleteEndPos.line)
  of ckTransaction:
    # For transactions, compute the range of all changes
    var minLine = int.high
    var maxLine = 0
    for ch in change.transactionChanges:
      let pos = getChangePosition(ch)
      minLine = min(minLine, pos.line)
      # Estimate end line based on change type
      case ch.kind
      of ckInsertText:
        let numLines = ch.insertText.count('\n')
        maxLine = max(maxLine, pos.line + numLines)
      of ckDeleteRange:
        maxLine = max(maxLine, ch.deleteEndPos.line)
      else:
        maxLine = max(maxLine, pos.line)
    if minLine != int.high:
      b.lastChangedLines = (minLine, maxLine)

  if b.inTransaction and b.currentTransaction.isSome:
    # Add to current transaction
    var transaction = b.currentTransaction.get
    transaction.changes.add(change)
    b.currentTransaction = some(transaction)
  else:
    # Add directly to undo stack
    b.undoStack.addLast(change)

proc beginTransaction*(b: TextBuffer, description: string = ""): Result[(), string] =
  ## Begin a transaction to group multiple changes
  ## Returns error if a transaction is already in progress
  if b.inTransaction:
    let currentDesc =
      if b.currentTransaction.isSome:
        b.currentTransaction.get.description
      else:
        "(unknown)"
    return err("Transaction already in progress: " & currentDesc)

  b.inTransaction = true
  b.currentTransaction = some(
    BufferTransaction(changes: @[], description: description, startSeq: b.changeSeq)
  )
  return ok(())

proc commitTransaction*(b: TextBuffer): Result[(), string] =
  ## Commit the current transaction
  ## Returns error if no transaction is in progress
  if not b.inTransaction or b.currentTransaction.isNone:
    return err("No transaction in progress")

  let transaction = b.currentTransaction.get
  b.inTransaction = false
  b.currentTransaction = none(BufferTransaction)

  # Add transaction as a single undo entry if it has changes
  if transaction.changes.len > 0:
    b.undoStack.addLast(
      BufferChange(
        kind: ckTransaction,
        transactionChanges: transaction.changes,
        transactionDescription: transaction.description,
      )
    )
    # Note: changeSeq was already incremented by each change in pushUndoChange
    # Note: redoStack was already cleared by the first change in pushUndoChange

  return ok(())

proc rollbackTransaction*(b: TextBuffer): Result[(), string] =
  ## Rollback the current transaction by undoing all changes
  ## Restores changeSeq to its value at transaction start
  ## Returns error if no transaction is in progress
  if not b.inTransaction or b.currentTransaction.isNone:
    return err("No transaction in progress")

  # Undo all changes in transaction in reverse order
  let transaction = b.currentTransaction.get
  for i in countdown(transaction.changes.len - 1, 0):
    let r = b.undoChange(transaction.changes[i])
    if r.isErr:
      # Clean up transaction state even if rollback partially fails
      b.inTransaction = false
      b.currentTransaction = none(BufferTransaction)
      return err("Failed to rollback transaction: " & r.error)

  # Restore changeSeq to its value at transaction start
  b.changeSeq = transaction.startSeq

  # Mark highlight as needing update after rollback
  if transaction.changes.len > 0:
    b.highlightNeedsUpdate = true
    # Compute changed range from rolled back changes
    var minLine = int.high
    var maxLine = 0
    for change in transaction.changes:
      let pos = getChangePosition(change)
      minLine = min(minLine, pos.line)
      # Estimate end line based on change type (inverse operation)
      case change.kind
      of ckInsertText:
        # Rolling back insert = delete
        maxLine = max(maxLine, pos.line)
      of ckDeleteText, ckInsertLine, ckDeleteLine:
        maxLine = max(maxLine, pos.line)
      of ckDeleteRange:
        # Rolling back delete = insert
        let numNewlines = change.deletedRangeText.count('\n')
        maxLine = max(maxLine, pos.line + numNewlines)
      of ckTransaction:
        maxLine = max(maxLine, b.len - 1)
    if minLine != int.high:
      b.lastChangedLines = (minLine, maxLine)

  b.inTransaction = false
  b.currentTransaction = none(BufferTransaction)
  return ok(())

proc getChangePosition(change: BufferChange): BufferPosition =
  ## Get the starting position of a change
  case change.kind
  of ckInsertText:
    return change.insertPos
  of ckDeleteText:
    return change.deletePos
  of ckInsertLine:
    return BufferPosition(line: change.insertLineIdx, column: 0)
  of ckDeleteLine:
    return BufferPosition(line: change.deleteLineIdx, column: 0)
  of ckDeleteRange:
    return change.deleteStartPos
  of ckTransaction:
    # For transactions, return the position of the first change
    if change.transactionChanges.len > 0:
      return getChangePosition(change.transactionChanges[0])
    else:
      return BufferPosition(line: 0, column: 0)

proc insertTextWithNewlines(b: TextBuffer, pos: BufferPosition, text: string) =
  ## Insert text that may contain newlines, properly splitting into multiple lines
  ## This is used internally for undo/redo operations
  if '\n' notin text:
    # Simple case: no newlines, just insert into current line
    let line = b.getLine(pos.line)
    let bytePos =
      charToBytePosCached(line, pos.column, b.cursorCache, pos.line, b.changeSeq)
    b.gapBuffer.insertIntoLine(pos.line, bytePos, text)
  else:
    # Complex case: text contains newlines, need to split current line and insert multiple lines
    let
      currentLine = b.getLine(pos.line)
      currentLineLen = currentLine.charLen

    # Split current line at insertion position
    let
      prefix =
        if pos.column < currentLineLen:
          currentLine.runeSubStr(0, pos.column)
        else:
          currentLine
      suffix =
        if pos.column < currentLineLen:
          currentLine.runeSubStr(pos.column)
        else:
          ""

    # Split text to insert by newlines
    let insertedLines = text.split('\n')

    # Build new lines
    var newLines: seq[string] = @[]

    if insertedLines.len == 1:
      # Should not happen (we checked for \n above), but handle it
      newLines.add(prefix & insertedLines[0] & suffix)
    else:
      # First line: prefix + first inserted line
      newLines.add(prefix & insertedLines[0])

      # Middle lines: just the inserted lines
      for i in 1 ..< insertedLines.len - 1:
        newLines.add(insertedLines[i])

      # Last line: last inserted line + suffix
      newLines.add(insertedLines[^1] & suffix)

    # Replace current line with new lines
    b.gapBuffer.deleteLine(pos.line)
    for i, newLine in newLines:
      b.gapBuffer.insertLine(pos.line + i, newLine)

  # Ensure lineMarkers stays in sync after direct gapBuffer operations
  b.ensureMarkersSize()

proc undoChange(b: TextBuffer, change: BufferChange): Result[(), string] =
  ## Apply the inverse of a single change (internal helper)
  ## Returns error if the operation fails
  try:
    case change.kind
    of ckInsertText:
      # Undo insert by deleting the inserted text (all bytes at once)
      case b.backendKind
      of GapBuffer:
        let line = b.getLine(change.insertPos.line)
        let bytePos = charToBytePosCached(
          line, change.insertPos.column, b.cursorCache, change.insertPos.line,
          b.changeSeq,
        )
        b.gapBuffer.deleteAtLineCol(
          change.insertPos.line, bytePos, change.insertText.len
        )
    of ckDeleteText:
      # Undo delete by inserting the deleted text
      case b.backendKind
      of GapBuffer:
        let line = b.getLine(change.deletePos.line)
        let bytePos = charToBytePosCached(
          line, change.deletePos.column, b.cursorCache, change.deletePos.line,
          b.changeSeq,
        )
        b.gapBuffer.insertIntoLine(change.deletePos.line, bytePos, change.deletedText)
    of ckInsertLine:
      # Undo insert line by deleting it
      case b.backendKind
      of GapBuffer:
        b.gapBuffer.deleteLine(change.insertLineIdx)
    of ckDeleteLine:
      # Undo delete line by inserting it
      case b.backendKind
      of GapBuffer:
        b.gapBuffer.insertLine(change.deleteLineIdx, change.deletedLineText)
    of ckDeleteRange:
      # Undo delete range by inserting the deleted text
      # Handle both single-line and multi-line deletions correctly
      case b.backendKind
      of GapBuffer:
        b.insertTextWithNewlines(change.deleteStartPos, change.deletedRangeText)
    of ckTransaction:
      # Undo all changes in transaction in reverse order
      for i in countdown(change.transactionChanges.len - 1, 0):
        let r = b.undoChange(change.transactionChanges[i])
        if r.isErr:
          return r

    # Ensure lineMarkers stays in sync after undo operations
    b.ensureMarkersSize()
    return ok(())
  except CatchableError as e:
    logError("buffer", "Undo operation failed: " & e.msg)
    return err("Failed to undo change: " & e.msg)

proc undo*(b: TextBuffer, count: int = 1): Result[BufferPosition, string] =
  ## Undo the last 'count' changes (or all changes in a transaction group)
  ## Returns the suggested cursor position for the first undone change
  ## Returns error if nothing to undo or if the undo operation fails
  if b.undoStack.len == 0:
    return Result[BufferPosition, string].err "Nothing to undo"

  var undoneChanges: seq[BufferChange] = @[]

  # Undo 'count' changes
  for i in 0 ..< count:
    if b.undoStack.len == 0:
      break

    let change = b.undoStack.popLast()
    let r = b.undoChange(change)
    if r.isErr:
      # Restore the change to undo stack if undo failed
      b.undoStack.addLast(change)
      # Restore previously undone changes to undo stack
      for j in countdown(undoneChanges.len - 1, 0):
        b.undoStack.addLast(undoneChanges[j])
      return err("Undo failed: " & r.error)

    undoneChanges.add(change)

    # Decrement change sequence for each undo
    b.changeSeq.dec

  # Add all undone changes to redo stack in the order they were undone
  # This ensures redo applies them in the correct reverse order
  for change in undoneChanges:
    b.redoStack.addLast(change)

  # Mark highlight as needing update after undo
  if undoneChanges.len > 0:
    b.highlightNeedsUpdate = true

    # Compute changed range from undone changes for incremental highlighting
    var minLine = int.high
    var maxLine = 0
    for change in undoneChanges:
      let pos = getChangePosition(change)
      minLine = min(minLine, pos.line)
      # Estimate end line based on change type (inverse operation)
      case change.kind
      of ckInsertText:
        # Undoing insert = delete, affects only the start line
        maxLine = max(maxLine, pos.line)
      of ckDeleteText, ckInsertLine, ckDeleteLine:
        # Undoing these affects the target line
        maxLine = max(maxLine, pos.line)
      of ckDeleteRange:
        # Undoing delete = insert, may span multiple lines
        let numNewlines = change.deletedRangeText.count('\n')
        maxLine = max(maxLine, pos.line + numNewlines)
      of ckTransaction:
        # Transactions may affect wide range
        maxLine = max(maxLine, b.len - 1)
    if minLine != int.high:
      b.lastChangedLines = (minLine, maxLine)

  # Return suggested cursor position for the first change
  if undoneChanges.len > 0:
    return ok(getChangePosition(undoneChanges[0]))
  else:
    return ok(BufferPosition(line: 0, column: 0))

proc redoChange(b: TextBuffer, change: BufferChange): Result[(), string] =
  ## Re-apply a single change (internal helper)
  ## Returns error if the operation fails
  try:
    case change.kind
    of ckInsertText:
      case b.backendKind
      of GapBuffer:
        let line = b.getLine(change.insertPos.line)
        let bytePos = charToBytePosCached(
          line, change.insertPos.column, b.cursorCache, change.insertPos.line,
          b.changeSeq,
        )
        b.gapBuffer.insertIntoLine(change.insertPos.line, bytePos, change.insertText)
    of ckDeleteText:
      case b.backendKind
      of GapBuffer:
        let line = b.getLine(change.deletePos.line)
        let bytePos = charToBytePosCached(
          line, change.deletePos.column, b.cursorCache, change.deletePos.line,
          b.changeSeq,
        )
        b.gapBuffer.deleteAtLineCol(
          change.deletePos.line, bytePos, change.deletedText.len
        )
    of ckInsertLine:
      case b.backendKind
      of GapBuffer:
        b.gapBuffer.insertLine(change.insertLineIdx, change.insertLineText)
    of ckDeleteLine:
      case b.backendKind
      of GapBuffer:
        b.gapBuffer.deleteLine(change.deleteLineIdx)
    of ckDeleteRange:
      # Re-apply delete range using the same logic as the original deleteRange
      # Handle both single-line and multi-line deletions correctly
      case b.backendKind
      of GapBuffer:
        let startPos = change.deleteStartPos
        let endPos = change.deleteEndPos

        if startPos.line == endPos.line:
          b.deleteRangeSingleLine(b.getLine(startPos.line), startPos, endPos)
        else:
          b.deleteRangeMultiLine(startPos, endPos)
    of ckTransaction:
      # Redo all changes in transaction in forward order
      for change in change.transactionChanges:
        let r = b.redoChange(change)
        if r.isErr:
          return r

    # Ensure lineMarkers stays in sync after redo operations
    b.ensureMarkersSize()
    return ok(())
  except CatchableError as e:
    logError("buffer", "Redo operation failed: " & e.msg)
    return err("Failed to redo change: " & e.msg)

proc redo*(b: TextBuffer, count: int = 1): Result[BufferPosition, string] =
  ## Redo the last 'count' undone changes
  ## Returns the suggested cursor position for the first redone change
  ## Returns error if nothing to redo or if the redo operation fails
  if b.redoStack.len == 0:
    return Result[BufferPosition, string].err "Nothing to redo"

  var redoneChanges: seq[BufferChange] = @[]

  # Redo 'count' changes
  for i in 0 ..< count:
    if b.redoStack.len == 0:
      break

    let change = b.redoStack.popLast()
    let r = b.redoChange(change)
    if r.isErr:
      # Restore the change to redo stack if redo failed
      b.redoStack.addLast(change)
      # Restore previously redone changes to redo stack
      for j in countdown(redoneChanges.len - 1, 0):
        b.redoStack.addLast(redoneChanges[j])
      return err("Redo failed: " & r.error)

    redoneChanges.add(change)

    # Increment change sequence for each redo
    b.changeSeq.inc

  # Add redone changes back to undo stack in reverse order
  # This restores the original undo stack order after redo
  for i in countdown(redoneChanges.len - 1, 0):
    b.undoStack.addLast(redoneChanges[i])

  # Mark highlight as needing update after redo
  if redoneChanges.len > 0:
    b.highlightNeedsUpdate = true

    # Compute changed range from redone changes for incremental highlighting
    var minLine = int.high
    var maxLine = 0
    for change in redoneChanges:
      let pos = getChangePosition(change)
      minLine = min(minLine, pos.line)
      # Estimate end line based on change type
      case change.kind
      of ckInsertText:
        let numNewlines = change.insertText.count('\n')
        maxLine = max(maxLine, pos.line + numNewlines)
      of ckDeleteText, ckInsertLine, ckDeleteLine:
        maxLine = max(maxLine, pos.line)
      of ckDeleteRange:
        maxLine = max(maxLine, change.deleteEndPos.line)
      of ckTransaction:
        # Transactions may affect wide range
        maxLine = max(maxLine, b.len - 1)
    if minLine != int.high:
      b.lastChangedLines = (minLine, maxLine)

  # Return suggested cursor position for the first change
  if redoneChanges.len > 0:
    return ok(getChangePosition(redoneChanges[0]))
  else:
    return ok(BufferPosition(line: 0, column: 0))

# File operations
proc chooseBackendForFile(): BufferBackend =
  # TODO: Choose appropriate backend based on file size
  chooseBackend()

template detectLineEnding(b: TextBuffer, content: lent string) =
  ## Detect line ending and trailing newline
  if content.contains("\r\n"):
    b.lineEnding = CRLF
  elif content.contains("\r"):
    b.lineEnding = CR
  else:
    b.lineEnding = LF

  # Detect if file ends with newline
  # For empty files (new files), keep the default endOfLine=true (POSIX standard)
  if content.len > 0:
    b.endOfLine =
      content.endsWith("\n") or content.endsWith("\r\n") or content.endsWith("\r")
  # else: keep the default endOfLine value (true for new files)

proc loadFile*(b: TextBuffer, path: string): Result[(), string] =
  let newBackend = chooseBackendForFile()
  var content: string

  # Check if file exists; if not, start with empty content
  if fileExists(path):
    # File exists, read its content
    try:
      content = readFile(path)
    except IOError as e:
      logError("buffer", "Failed to read file " & path & ": " & e.msg)
      return Result[(), string].err e.msg
  else:
    # File doesn't exist, start with empty content
    logDebug("buffer", "File does not exist, creating new: " & path)
    content = ""

  # Reinitialize with new backend if needed
  if b.backendKind != newBackend:
    let newBuffer = newTextBuffer(content, some(path))
    b[] = newBuffer[]
  else:
    case b.backendKind
    of GapBuffer:
      b.gapBuffer = newGapBuffer(content)

  b.detectLineEnding(content)
  b.encoding = detectCharacterEncoding(content)

  b.filePath = some(path)

  # Reset change tracking - file was just loaded
  b.changeSeq = 0
  b.savedSeq = 0

  # Reset markers for new file content
  b.lineMarkers = newSeq[Option[SidebarItemKind]](b.len)

  # Initialize syntax highlighting based on file extension
  b.language = detectLanguage(path)
  var runesBuffer: seq[Runes] = @[]
  for i in 0 ..< b.len:
    runesBuffer.add(b.getLine(i).toRunes())

  if b.language != SourceLanguage.langNone:
    b.highlight = initHighlight(runesBuffer, @[], b.language)

    # Build initial incremental cache for future edits
    if runesBuffer.len > 0:
      let (segments, lineStates) = initHighlightIncremental(
        runesBuffer,
        0,
        runesBuffer.high,
        TokenizerState(), # Default initial state
        @[],
        b.language,
      )

      b.incrementalHighlight = IncrementalHighlight(
        segments: segments,
        lineStates: LineStateCache(states: lineStates, version: b.changeSeq),
      )
    else:
      b.incrementalHighlight = nil
  else:
    b.highlight = initHighlight(runesBuffer)
    b.incrementalHighlight = nil

  b.highlightNeedsUpdate = false

  return Result[(), string].ok ()

proc saveFile*(buffer: TextBuffer, path: string): Result[(), string] =
  case buffer.backendKind
  of GapBuffer:
    # Get full content
    var content = buffer.getTextString

    # Handle trailing newline according to endOfLine setting (vim behavior)
    if buffer.endOfLine:
      # Ensure file ends with newline
      if content.len == 0 or
          not (
            content.endsWith("\n") or content.endsWith("\r\n") or content.endsWith("\r")
          ):
        case buffer.lineEnding
        of LF:
          content.add('\n')
        of CRLF:
          content.add("\r\n")
        of CR:
          content.add('\r')
    else:
      # Remove trailing newline if present
      while content.len > 0 and
          (content.endsWith("\n") or content.endsWith("\r\n") or content.endsWith("\r")):
        if content.endsWith("\r\n"):
          content.setLen(content.len - 2)
        else:
          content.setLen(content.len - 1)

    # Write to file
    try:
      writeFile(path, content)
      logDebug("buffer", "File written successfully: " & path)
    except IOError as e:
      logError("buffer", "Failed to write file " & path & ": " & e.msg)
      return Result[(), string].err e.msg

    # Mark buffer as saved at current sequence
    buffer.savedSeq = buffer.changeSeq
    buffer.filePath = some(path)

  return Result[(), string].ok ()

# Memory usage monitoring
proc estimateMemoryUsage*(buffer: TextBuffer): int =
  result = sizeof(TextBuffer)

  case buffer.backendKind
  of GapBuffer:
    result += buffer.gapBuffer.estimateMemoryUsage()

proc getPerformanceStats*(
    buffer: TextBuffer
): tuple[backend: string, memoryUsage: int, length: int] =
  let backendName =
    case buffer.backendKind
    of GapBuffer: "GapBuffer"

  (backend: backendName, memoryUsage: buffer.estimateMemoryUsage(), length: buffer.len)

# Sidebar marker management
proc ensureMarkersSize(b: TextBuffer) =
  ## Ensure lineMarkers array matches buffer length
  let bufferLen = b.len
  if b.lineMarkers.len < bufferLen:
    # Extend with none values
    for i in b.lineMarkers.len ..< bufferLen:
      b.lineMarkers.add(none(SidebarItemKind))
  elif b.lineMarkers.len > bufferLen:
    # Truncate
    b.lineMarkers.setLen(bufferLen)

proc setLineMarker*(b: TextBuffer, line: int, kind: SidebarItemKind) =
  ## Set a sidebar marker for a specific line
  ## Automatically resizes the marker array if needed
  b.ensureMarkersSize()
  if line >= 0 and line < b.lineMarkers.len:
    b.lineMarkers[line] = some(kind)

proc clearLineMarker*(b: TextBuffer, line: int) =
  ## Clear the sidebar marker for a specific line
  if line >= 0 and line < b.lineMarkers.len:
    b.lineMarkers[line] = none(SidebarItemKind)

proc getLineMarker*(b: TextBuffer, line: int): Option[SidebarItemKind] =
  ## Get the sidebar marker for a specific line
  ## Returns none if no marker is set or line is out of bounds
  if line >= 0 and line < b.lineMarkers.len:
    return b.lineMarkers[line]
  else:
    return none(SidebarItemKind)

proc clearAllMarkers*(b: TextBuffer) =
  ## Clear all sidebar markers
  for i in 0 ..< b.lineMarkers.len:
    b.lineMarkers[i] = none(SidebarItemKind)

# Syntax highlighting management
proc updateHighlight*(b: TextBuffer) =
  ## Update syntax highlighting if needed
  ## This should be called before rendering
  if b.highlightNeedsUpdate:
    var runesBuffer: seq[Runes] = @[]
    for i in 0 ..< b.len:
      runesBuffer.add(b.getLine(i).toRunes())

    if b.language != SourceLanguage.langNone:
      # Check if incremental cache is valid
      let cacheValid =
        b.incrementalHighlight != nil and
        b.incrementalHighlight.lineStates.states.len > 0 and
        b.incrementalHighlight.segments.len > 0

      if cacheValid:
        # Use incremental highlighting for better performance
        updateHighlightIncremental(
          runesBuffer,
          b.incrementalHighlight,
          b.lastChangedLines.start,
          b.lastChangedLines.theEnd,
          b.changeSeq,
          @[], # reservedWords - empty for now
          b.language,
        )

        # Convert IncrementalHighlight segments to Highlight
        b.highlight = Highlight(colorSegments: b.incrementalHighlight.segments)
      else:
        # Cache invalid or first time - do full parse
        b.highlight = initHighlight(runesBuffer, @[], b.language)

        # Build initial incremental cache for next time
        if runesBuffer.len > 0:
          # Parse entire buffer with default initial state
          let (segments, lineStates) = initHighlightIncremental(
            runesBuffer,
            0,
            runesBuffer.high,
            TokenizerState(), # Default initial state
            @[],
            b.language,
          )

          b.incrementalHighlight = IncrementalHighlight(
            segments: segments,
            lineStates: LineStateCache(states: lineStates, version: b.changeSeq),
          )
        else:
          b.incrementalHighlight = nil
    else:
      # Plain text - use simple highlighting
      b.highlight = initHighlight(runesBuffer)

    b.highlightNeedsUpdate = false
