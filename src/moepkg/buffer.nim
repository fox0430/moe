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

## Main buffer interface

import std/[unicode, options, strutils, deques, os, times]

import pkg/results

import unicode_utils, encoding, highlight, logger, search_utils, primitives
import buffer_backends/[gap_buffer, sqrt_decomp, rope, piece_table]

export CharacterEncoding, encodingToString, detectCharacterEncoding, BufferPosition

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

  Fold* = object ## Represents a foldable region of text (vim-like manual folding)
    startLine*: int # Fold start line (0-based, inclusive)
    endLine*: int # Fold end line (0-based, inclusive)
    collapsed*: bool # Whether the fold is currently collapsed
    collapsedText*: Option[string] # Custom text to display when collapsed (from LSP)

  FoldState* = object ## Manages all folds in a buffer
    folds*: seq[Fold] # List of all folds (sorted by startLine)

  BufferEditorConfig* = object
    ## Per-buffer EditorConfig overrides (from .editorconfig files)
    tabStop*: Option[int]
    shiftWidth*: Option[int]
    expandTab*: Option[bool]
    trimTrailingWhitespace*: Option[bool]

  LineEnding* = enum
    LF
    CRLF
    CR

  BufferBackend* = enum
    GapBuffer # Best for small to medium files
    SqrtDecomp # Sqrt decomposition - O(√n) random access, good for large files
    Rope # B-tree rope - O(log n) operations
    PieceTable # Piece tree (Red-Black Tree) - O(log n) operations

  BufferChangeKind* = enum ## Undo/Redo system types
    ckInsertText
    ckDeleteText
    ckInsertLine
    ckDeleteLine
    ckDeleteRange
    ckReplaceLine # Line content replaced
    ckTransaction # Transaction containing multiple changes
    ckSnapshot # PieceTable O(1) snapshot undo/redo

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
    of ckReplaceLine:
      replaceLineIdx*: int
      replaceLineOldText*: string
      replaceLineNewText*: string
    of ckTransaction:
      transactionChanges*: seq[BufferChange]
      transactionDescription*: string
    of ckSnapshot:
      snapshotData*: PieceTableSnapshot
      snapshotCursorPos*: BufferPosition
      snapshotLineMarkers*: seq[Option[SidebarItemKind]]
      snapshotFoldState*: FoldState

  BufferTransaction* = object ## Transaction for grouping multiple changes
    changes*: seq[BufferChange]
    description*: string
    startSeq*: int # changeSeq at the start of transaction

  TextBuffer* = ref object
    id*: int # Unique buffer identifier
    backend*: BufferBackend
    filePath*: Option[string]
    readOnly*: bool
    isUtilityBuffer*: bool # Utility buffers (jumplist, log, etc.) disable decorations
    lineEnding*: LineEnding
    encoding*: CharacterEncoding
    endOfLine*: bool # Whether file should end with newline
    lastFileModTime*: Option[Time]
      # File modification time when loaded (for external change detection)
    externalModWarned*: bool
      # Whether the user has been warned about external modification (reset on load/save)

    # Undo/Redo stacks (using Deque for O(1) operations at both ends)
    undoStack*: Deque[BufferChange]
    redoStack*: Deque[BufferChange]

    # Change sequence tracking for modified flag
    changeSeq*: int # Current change sequence number
    savedSeq*: int # Sequence number when file was last saved

    # Transaction support
    currentTransaction*: Option[BufferTransaction]
    inTransaction*: bool

    # PieceTable snapshot support for O(1) undo/redo
    pendingSnapshot*: Option[PieceTableSnapshot]
    pendingSnapshotMarkers*: seq[Option[SidebarItemKind]]
    pendingSnapshotFolds*: FoldState

    # Sidebar markers (line-based markers for git diff, syntax errors, etc.)
    lineMarkers*: seq[Option[SidebarItemKind]] # Each line can have at most one marker

    # Syntax highlighting
    highlight*: Highlight # Syntax highlighting for this buffer
    language*: SourceLanguage # Programming language for syntax highlighting
    highlightNeedsUpdate*: bool # Flag to track if highlight needs regeneration
    incrementalHighlight*: IncrementalHighlight # Incremental highlighting cache
    lastChangedLines*: int # First changed line for incremental highlight
    reservedWords*: seq[ReservedWord] # Reserved words to highlight (TODO, NOTE, etc.)

    # Performance optimization
    cursorCache*: CursorPosCache # Cache for character-to-byte position conversions

    # Line folding state (vim-like manual folding)
    foldState*: FoldState

    # Per-buffer EditorConfig overrides
    editorConfig*: Option[BufferEditorConfig]

    # Backend storage
    case backendKind*: BufferBackend
    of GapBuffer:
      gapBuffer*: GapBuffer
    of SqrtDecomp:
      sqrtDecomp*: sqrt_decomp.SqrtDecomp
    of Rope:
      rope*: rope.Rope
    of PieceTable:
      pieceTable*: piece_table.PieceTable

var nextBufferId = 0

proc genBufferId(): int =
  result = nextBufferId
  inc nextBufferId

var configuredBackend: BufferBackend = GapBuffer
var autoBackendMode: bool = false

proc setConfiguredBackend*(backend: BufferBackend) =
  configuredBackend = backend

proc setAutoBackendMode*(enabled: bool) =
  autoBackendMode = enabled

proc chooseBackend(): BufferBackend =
  configuredBackend

proc initFoldState*(): FoldState =
  ## Initialize an empty fold state
  FoldState(folds: @[])

proc adjustFoldsAfterInsert*(state: var FoldState, insertLine: int, lineCount: int) =
  ## Adjust fold line numbers after lines are inserted
  for i in 0 ..< state.folds.len:
    if state.folds[i].startLine >= insertLine:
      state.folds[i].startLine += lineCount
      state.folds[i].endLine += lineCount
    elif state.folds[i].endLine >= insertLine:
      # Fold spans the insertion point - extend it
      state.folds[i].endLine += lineCount

proc adjustFoldsAfterDelete*(state: var FoldState, deleteLine: int, lineCount: int) =
  ## Adjust fold line numbers after lines are deleted
  var toRemove: seq[int] = @[]

  for i in 0 ..< state.folds.len:
    let deleteEnd = deleteLine + lineCount - 1

    if state.folds[i].endLine < deleteLine:
      # Fold entirely before deletion - no change
      discard
    elif state.folds[i].startLine > deleteEnd:
      # Fold entirely after deletion - shift down
      state.folds[i].startLine -= lineCount
      state.folds[i].endLine -= lineCount
    elif state.folds[i].startLine >= deleteLine and state.folds[i].endLine <= deleteEnd:
      # Fold entirely within deletion - remove it
      toRemove.add(i)
    else:
      # Fold partially overlaps - adjust
      if state.folds[i].startLine < deleteLine:
        # Fold starts before deletion
        state.folds[i].endLine =
          max(state.folds[i].startLine, state.folds[i].endLine - lineCount)
      else:
        # Fold starts within deletion range
        state.folds[i].startLine = deleteLine
        state.folds[i].endLine = max(deleteLine, state.folds[i].endLine - lineCount)

  # Remove folds marked for deletion (in reverse order to preserve indices)
  for i in countdown(toRemove.high, 0):
    state.folds.delete(toRemove[i])

proc isModified*(b: TextBuffer): bool {.inline.} =
  ## Check if buffer has unsaved changes
  b.changeSeq != b.savedSeq

proc markSaved*(b: TextBuffer) {.inline.} =
  ## Mark the buffer as unmodified by syncing savedSeq to changeSeq.
  b.savedSeq = b.changeSeq

proc newTextBuffer*(
    content: string = "",
    filePath: Option[string] = none(string),
    backend: BufferBackend = chooseBackend(),
): TextBuffer =
  case backend
  of GapBuffer:
    let gb = newGapBuffer(content)
    # Convert buffer to Runes sequence for highlighting
    var runesBuffer: seq[Runes] = @[]
    for i in 0 ..< gb.len:
      runesBuffer.add(gb.getLine(i).toRunes())

    TextBuffer(
      id: genBufferId(),
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
      lastChangedLines: 0,
      # Initialize cursor position cache (invalid state)
      cursorCache: CursorPosCache(line: -1, charPos: 0, bytePos: 0, changeSeq: -1),
      # Initialize empty fold state
      foldState: initFoldState(),
      editorConfig: none(BufferEditorConfig),
    )
  of SqrtDecomp:
    let sd = newSqrtDecomp(content)
    var runesBuffer: seq[Runes] = @[]
    for i in 0 ..< sd.len:
      runesBuffer.add(sd.getLine(i).toRunes())

    TextBuffer(
      id: genBufferId(),
      backendKind: BufferBackend.SqrtDecomp,
      backend: backend,
      filePath: filePath,
      readOnly: false,
      lineEnding: LF,
      encoding: utf8,
      endOfLine: true,
      sqrtDecomp: sd,
      undoStack: initDeque[BufferChange](),
      redoStack: initDeque[BufferChange](),
      changeSeq: 0,
      savedSeq: 0,
      currentTransaction: none(BufferTransaction),
      inTransaction: false,
      lineMarkers: newSeq[Option[SidebarItemKind]](sd.len),
      highlight: initHighlight(runesBuffer),
      language: SourceLanguage.langNone,
      highlightNeedsUpdate: false,
      incrementalHighlight: nil,
      lastChangedLines: 0,
      cursorCache: CursorPosCache(line: -1, charPos: 0, bytePos: 0, changeSeq: -1),
      foldState: initFoldState(),
      editorConfig: none(BufferEditorConfig),
    )
  of Rope:
    let rp = newRope(content)
    var runesBuffer: seq[Runes] = @[]
    for i in 0 ..< rp.len:
      runesBuffer.add(rp.getLine(i).toRunes())

    TextBuffer(
      id: genBufferId(),
      backendKind: BufferBackend.Rope,
      backend: backend,
      filePath: filePath,
      readOnly: false,
      lineEnding: LF,
      encoding: utf8,
      endOfLine: true,
      rope: rp,
      undoStack: initDeque[BufferChange](),
      redoStack: initDeque[BufferChange](),
      changeSeq: 0,
      savedSeq: 0,
      currentTransaction: none(BufferTransaction),
      inTransaction: false,
      lineMarkers: newSeq[Option[SidebarItemKind]](rp.len),
      highlight: initHighlight(runesBuffer),
      language: SourceLanguage.langNone,
      highlightNeedsUpdate: false,
      incrementalHighlight: nil,
      lastChangedLines: 0,
      cursorCache: CursorPosCache(line: -1, charPos: 0, bytePos: 0, changeSeq: -1),
      foldState: initFoldState(),
      editorConfig: none(BufferEditorConfig),
    )
  of PieceTable:
    let pt = newPieceTable(content)
    var runesBuffer: seq[Runes] = @[]
    for i in 0 ..< pt.len:
      runesBuffer.add(pt.getLine(i).toRunes())

    TextBuffer(
      id: genBufferId(),
      backendKind: BufferBackend.PieceTable,
      backend: backend,
      filePath: filePath,
      readOnly: false,
      lineEnding: LF,
      encoding: utf8,
      endOfLine: true,
      pieceTable: pt,
      undoStack: initDeque[BufferChange](),
      redoStack: initDeque[BufferChange](),
      changeSeq: 0,
      savedSeq: 0,
      currentTransaction: none(BufferTransaction),
      inTransaction: false,
      lineMarkers: newSeq[Option[SidebarItemKind]](pt.len),
      highlight: initHighlight(runesBuffer),
      language: SourceLanguage.langNone,
      highlightNeedsUpdate: false,
      incrementalHighlight: nil,
      lastChangedLines: 0,
      cursorCache: CursorPosCache(line: -1, charPos: 0, bytePos: 0, changeSeq: -1),
      foldState: initFoldState(),
      editorConfig: none(BufferEditorConfig),
    )

proc setReservedWords*(b: TextBuffer, words: seq[ReservedWord]) =
  ## Set reserved words for syntax highlighting (e.g., TODO, NOTE, FIXME)
  ## This will trigger a re-highlight on the next update
  b.reservedWords = words
  b.highlightNeedsUpdate = true

proc toReservedWords*(words: seq[string]): seq[ReservedWord] =
  ## Convert a sequence of strings to ReservedWord objects
  ## Uses the default reservedWord color from the theme
  for word in words:
    result.add(ReservedWord(word: word, color: EditorColorPairIndex.reservedWord))

# Core text operations
proc getTextString*(b: TextBuffer): string =
  case b.backendKind
  of GapBuffer:
    $b.gapBuffer
  of SqrtDecomp:
    $b.sqrtDecomp
  of Rope:
    $b.rope
  of PieceTable:
    $b.pieceTable

proc len*(b: TextBuffer): int =
  ## Get number of lines in buffer
  case b.backendKind
  of GapBuffer: b.gapBuffer.len
  of SqrtDecomp: b.sqrtDecomp.len
  of Rope: b.rope.len
  of PieceTable: b.pieceTable.len

proc charLen*(text: string): int =
  ## Get character length (not byte length)
  text.runeLen

proc getLine*(b: TextBuffer, lineIndex: int): string =
  case b.backendKind
  of GapBuffer:
    b.gapBuffer.getLine(lineIndex)
  of SqrtDecomp:
    b.sqrtDecomp.getLine(lineIndex)
  of Rope:
    b.rope.getLine(lineIndex)
  of PieceTable:
    b.pieceTable.getLine(lineIndex)

proc `[]`*(b: TextBuffer, lineIndex: int): string =
  ## Bracket operator for accessing lines by index
  b.getLine(lineIndex)

proc getLineLen*(b: TextBuffer, lineIndex: int): int =
  ## Get Unicode character count of line (not byte length).
  ## Use this for cursor/column position calculations.
  b.getLine(lineIndex).charLen

# Word detection helpers for currentWord highlighting
proc isWordChar(r: Rune): bool =
  ## Check if a character is part of a word (alphanumeric or underscore)
  let c = r.int32
  return
    (c >= 'a'.ord and c <= 'z'.ord) or (c >= 'A'.ord and c <= 'Z'.ord) or
    (c >= '0'.ord and c <= '9'.ord) or c == '_'.ord

proc getWordAtPosition*(b: TextBuffer, pos: BufferPosition): string =
  ## Get the word at the given buffer position
  ## Returns empty string if cursor is not on a word character
  if pos.line < 0 or pos.line >= b.len:
    return ""

  let line = b.getLine(pos.line)
  var runes: seq[Rune] = @[]
  for r in line.runes:
    runes.add(r)

  if runes.len == 0 or pos.column < 0 or pos.column >= runes.len:
    return ""

  # Check if cursor is on a word character
  if not isWordChar(runes[pos.column]):
    return ""

  # Find start of word
  var startCol = pos.column
  while startCol > 0 and isWordChar(runes[startCol - 1]):
    dec startCol

  # Find end of word
  var endCol = pos.column
  while endCol < runes.len - 1 and isWordChar(runes[endCol + 1]):
    inc endCol

  # Build the word string
  result = ""
  for i in startCol .. endCol:
    result.add($runes[i])

proc isPositionInWord*(b: TextBuffer, pos: BufferPosition, word: string): bool =
  ## Check if the position is part of a word that matches the given word
  ## Used for currentWord highlighting
  if word.len == 0:
    return false

  if pos.line < 0 or pos.line >= b.len:
    return false

  let line = b.getLine(pos.line)
  var runes: seq[Rune] = @[]
  for r in line.runes:
    runes.add(r)

  if runes.len == 0 or pos.column < 0 or pos.column >= runes.len:
    return false

  # Check if position is on a word character
  if not isWordChar(runes[pos.column]):
    return false

  # Find word boundaries at this position
  var startCol = pos.column
  while startCol > 0 and isWordChar(runes[startCol - 1]):
    dec startCol

  var endCol = pos.column
  while endCol < runes.len - 1 and isWordChar(runes[endCol + 1]):
    inc endCol

  # Build the word at this position
  var wordAtPos = ""
  for i in startCol .. endCol:
    wordAtPos.add($runes[i])

  # Check if it matches
  return wordAtPos == word

proc `[][]`*(b: TextBuffer, lineIndex, colIndex: int): char =
  ## Bracket operator for accessing character at (line, column)
  b[lineIndex][colIndex]

# Backend dispatch helpers for internal use (no undo recording)
proc backendInsertIntoLine(b: TextBuffer, line, col: int, text: string) =
  case b.backendKind
  of GapBuffer:
    b.gapBuffer.insertIntoLine(line, col, text)
  of SqrtDecomp:
    b.sqrtDecomp.insertIntoLine(line, col, text)
  of Rope:
    b.rope.insertIntoLine(line, col, text)
  of PieceTable:
    b.pieceTable.insertIntoLine(line, col, text)

proc backendDeleteLine(b: TextBuffer, lineNumber: int) =
  case b.backendKind
  of GapBuffer:
    b.gapBuffer.deleteLine(lineNumber)
  of SqrtDecomp:
    b.sqrtDecomp.deleteLine(lineNumber)
  of Rope:
    b.rope.deleteLine(lineNumber)
  of PieceTable:
    b.pieceTable.deleteLine(lineNumber)

proc backendInsertLine(b: TextBuffer, lineNumber: int, content: string) =
  case b.backendKind
  of GapBuffer:
    b.gapBuffer.insertLine(lineNumber, content)
  of SqrtDecomp:
    b.sqrtDecomp.insertLine(lineNumber, content)
  of Rope:
    b.rope.insertLine(lineNumber, content)
  of PieceTable:
    b.pieceTable.insertLine(lineNumber, content)

proc backendReplaceLine(b: TextBuffer, lineNumber: int, content: string) =
  case b.backendKind
  of GapBuffer:
    b.gapBuffer.replaceLine(lineNumber, content)
  of SqrtDecomp:
    b.sqrtDecomp.replaceLine(lineNumber, content)
  of Rope:
    b.rope.replaceLine(lineNumber, content)
  of PieceTable:
    b.pieceTable.replaceLine(lineNumber, content)

proc backendDeleteAtLineCol(b: TextBuffer, line, col, count: int) =
  case b.backendKind
  of GapBuffer:
    b.gapBuffer.deleteAtLineCol(line, col, count)
  of SqrtDecomp:
    b.sqrtDecomp.deleteAtLineCol(line, col, count)
  of Rope:
    b.rope.deleteAtLineCol(line, col, count)
  of PieceTable:
    b.pieceTable.deleteAtLineCol(line, col, count)

# Public NoUndo procs for external code that bypasses undo recording
proc replaceLineNoUndo*(b: TextBuffer, lineNumber: int, content: string) =
  ## Replace line content without recording undo. Used by substitute preview etc.
  b.backendReplaceLine(lineNumber, content)

proc deleteLineNoUndo*(b: TextBuffer, lineNumber: int) =
  ## Delete a line without recording undo. Used by substitute preview etc.
  b.backendDeleteLine(lineNumber)

proc insertLineNoUndo*(b: TextBuffer, lineNumber: int, content: string) =
  ## Insert a line without recording undo. Used by substitute preview etc.
  b.backendInsertLine(lineNumber, content)

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
  of ckReplaceLine:
    return BufferPosition(line: change.replaceLineIdx, column: 0)
  of ckTransaction:
    # For transactions, return the position of the first change
    if change.transactionChanges.len > 0:
      return getChangePosition(change.transactionChanges[0])
    else:
      return BufferPosition(line: 0, column: 0)
  of ckSnapshot:
    return change.snapshotCursorPos

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

proc captureSnapshotIfNeeded(b: TextBuffer) {.inline.} =
  ## Capture a PieceTable snapshot before mutation for O(1) undo/redo.
  ## Only captures once per undo entry (skips if pendingSnapshot already set).
  if b.backendKind == PieceTable and b.pendingSnapshot.isNone:
    b.pendingSnapshot = some(b.pieceTable.takeSnapshot())
    b.pendingSnapshotMarkers = b.lineMarkers
    b.pendingSnapshotFolds = b.foldState

proc pushUndoChange(b: TextBuffer, change: BufferChange) =
  ## Add a change to the undo stack (or current transaction)
  ## Always increments changeSeq to mark buffer as modified

  # Clear redo stack when new change is made
  b.redoStack.clear()

  # Increment change sequence number (marks as modified)
  b.changeSeq.inc

  # Mark highlight as needing update and track changed range
  b.highlightNeedsUpdate = true

  # Track the first changed line for incremental highlighting
  b.lastChangedLines = getChangePosition(change).line

  if b.inTransaction and b.currentTransaction.isSome:
    # Add to current transaction
    var transaction = b.currentTransaction.get
    transaction.changes.add(change)
    b.currentTransaction = some(transaction)
  elif b.pendingSnapshot.isSome:
    # PieceTable: convert to O(1) snapshot undo entry
    b.undoStack.addLast(
      BufferChange(
        kind: ckSnapshot,
        snapshotData: b.pendingSnapshot.get,
        snapshotCursorPos: getChangePosition(change),
        snapshotLineMarkers: b.pendingSnapshotMarkers,
        snapshotFoldState: b.pendingSnapshotFolds,
      )
    )
    b.pendingSnapshot = none(PieceTableSnapshot)
  else:
    # Add directly to undo stack
    b.undoStack.addLast(change)

proc replaceLine*(b: TextBuffer, lineNumber: int, content: string): Result[(), string] =
  ## Replace line content with undo recording.
  if lineNumber < 0 or lineNumber >= b.len:
    return err("Line index out of bounds: " & $lineNumber)
  let oldContent = b.getLine(lineNumber)
  b.captureSnapshotIfNeeded()
  b.backendReplaceLine(lineNumber, content)
  b.pushUndoChange(
    BufferChange(
      kind: ckReplaceLine,
      replaceLineIdx: lineNumber,
      replaceLineOldText: oldContent,
      replaceLineNewText: content,
    )
  )
  return ok(())

proc insertTextWithNewlines(b: TextBuffer, pos: BufferPosition, text: string) =
  ## Insert text that may contain newlines, properly splitting into multiple lines
  ## This is used internally for undo/redo operations
  if '\n' notin text:
    # Simple case: no newlines, just insert into current line
    let line = b.getLine(pos.line)
    let bytePos =
      charToBytePosCached(line, pos.column, b.cursorCache, pos.line, b.changeSeq)
    b.backendInsertIntoLine(pos.line, bytePos, text)
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
    b.backendDeleteLine(pos.line)
    for i, newLine in newLines:
      b.backendInsertLine(pos.line + i, newLine)

    # Adjust fold positions for newly inserted lines
    if newLines.len > 1:
      b.foldState.adjustFoldsAfterInsert(pos.line, newLines.len - 1)

  # Ensure lineMarkers stays in sync after backend operations
  b.ensureMarkersSize()

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

  b.captureSnapshotIfNeeded()

  case b.backendKind
  of GapBuffer, SqrtDecomp, Rope, PieceTable:
    try:
      # Use insertTextWithNewlines to handle newlines correctly
      b.insertTextWithNewlines(pos, text)
    except IndexDefect as e:
      b.pendingSnapshot = none(PieceTableSnapshot)
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

  b.captureSnapshotIfNeeded()

  case b.backendKind
  of GapBuffer, SqrtDecomp, Rope, PieceTable:
    let line = b.getLine(pos.line)
    if pos.column >= line.charLen:
      b.pendingSnapshot = none(PieceTableSnapshot)
      return err("Column position out of bounds: " & $pos.column)

    try:
      # Get the character that will be deleted for undo
      let
        deletedChar = line.runeAtPos(pos.column)
        charSize = len($deletedChar)
        bytePos =
          charToBytePosCached(line, pos.column, b.cursorCache, pos.line, b.changeSeq)

      # Delete character at byte position
      b.backendDeleteAtLineCol(pos.line, bytePos, charSize)

      # Record change for undo
      b.pushUndoChange(
        BufferChange(kind: ckDeleteText, deletePos: pos, deletedText: $deletedChar)
      )
    except IndexDefect as e:
      b.pendingSnapshot = none(PieceTableSnapshot)
      return err("Failed to delete character: " & e.msg)

  return ok(())

proc insert*(b: TextBuffer, lineIndex: int, content: string): Result[(), string] =
  ## Insert a new line at the specified index
  ## Returns error if lineIndex is out of valid range [0..len]
  if lineIndex < 0 or lineIndex > b.len:
    return err("Line index out of valid range [0.." & $b.len & "]: " & $lineIndex)

  b.captureSnapshotIfNeeded()

  case b.backendKind
  of GapBuffer, SqrtDecomp, Rope, PieceTable:
    try:
      b.backendInsertLine(lineIndex, content)
    except IndexDefect as e:
      b.pendingSnapshot = none(PieceTableSnapshot)
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

  # Adjust fold positions
  b.foldState.adjustFoldsAfterInsert(lineIndex, 1)

  return ok(())

proc deleteLine*(b: TextBuffer, lineIndex: int): Result[(), string] =
  ## Delete the line at the specified index
  ## Returns error if lineIndex is out of bounds
  if lineIndex < 0 or lineIndex >= b.len:
    return err("Line index out of bounds: " & $lineIndex)

  # Save line content before deleting for undo
  let deletedContent = b.getLine(lineIndex)

  b.captureSnapshotIfNeeded()

  case b.backendKind
  of GapBuffer, SqrtDecomp, Rope, PieceTable:
    try:
      b.backendDeleteLine(lineIndex)
    except IndexDefect as e:
      b.pendingSnapshot = none(PieceTableSnapshot)
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

  # Adjust fold positions
  b.foldState.adjustFoldsAfterDelete(lineIndex, 1)

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
      b.backendDeleteLine(endPos.line + 1)
      b.backendDeleteLine(startPos.line)
      b.backendInsertLine(startPos.line, newLine)
    else:
      # Last line: just delete to end
      let newLine =
        if startPos.column < lineLen:
          line.runeSubStr(0, startPos.column)
        else:
          ""
      b.backendDeleteLine(startPos.line)
      b.backendInsertLine(startPos.line, newLine)
  elif startPos.column < lineLen and endPos.column < lineLen:
    # Normal single-line deletion within bounds
    # Build new line by concatenating prefix and suffix using Unicode-safe substring
    let prefix = line.runeSubStr(0, startPos.column)
    let suffix = line.runeSubStr(endPos.column + 1)
    let newLine = buildMergedLine(prefix, suffix)

    b.backendDeleteLine(startPos.line)
    b.backendInsertLine(startPos.line, newLine)

  # Ensure lineMarkers stays in sync after backend operations
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
    b.backendDeleteLine(extraLineToDelete)

  # Replace startPos.line with the merged line
  b.backendDeleteLine(startPos.line)
  b.backendInsertLine(startPos.line, buildMergedLine(prefix, suffix))

  # Delete lines between startPos and endPos (if any)
  if endPos.line > startPos.line:
    for i in countdown(endPos.line, startPos.line + 1):
      b.backendDeleteLine(i)

  # Ensure lineMarkers stays in sync after backend operations
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

  b.captureSnapshotIfNeeded()

  case b.backendKind
  of GapBuffer, SqrtDecomp, Rope, PieceTable:
    try:
      if startPos.line == endPos.line:
        b.deleteRangeSingleLine(b.getLine(startPos.line), startPos, endPos)
      else:
        b.deleteRangeMultiLine(startPos, endPos)
    except IndexDefect as e:
      b.pendingSnapshot = none(PieceTableSnapshot)
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

  # Adjust fold positions if multiple lines were deleted
  if endPos.line > startPos.line:
    b.foldState.adjustFoldsAfterDelete(startPos.line, endPos.line - startPos.line)

  return ok(())

proc splitLine*(b: TextBuffer, pos: BufferPosition): Result[(), string] =
  ## Split line at the specified position by inserting a newline
  ## Returns error if position is out of bounds
  b.insertText(pos, "\n")

# Undo/Redo system

proc undoChange(b: TextBuffer, change: BufferChange): Result[(), string] =
  ## Apply the inverse of a single change (internal helper)
  ## Returns error if the operation fails
  try:
    case change.kind
    of ckInsertText:
      # Undo insert by deleting the inserted text (all bytes at once)
      let line = b.getLine(change.insertPos.line)
      let bytePos = charToBytePosCached(
        line, change.insertPos.column, b.cursorCache, change.insertPos.line, b.changeSeq
      )
      b.backendDeleteAtLineCol(change.insertPos.line, bytePos, change.insertText.len)
    of ckDeleteText:
      # Undo delete by inserting the deleted text
      let line = b.getLine(change.deletePos.line)
      let bytePos = charToBytePosCached(
        line, change.deletePos.column, b.cursorCache, change.deletePos.line, b.changeSeq
      )
      b.backendInsertIntoLine(change.deletePos.line, bytePos, change.deletedText)
    of ckInsertLine:
      # Undo insert line by deleting it
      b.backendDeleteLine(change.insertLineIdx)
      b.foldState.adjustFoldsAfterDelete(change.insertLineIdx, 1)
    of ckDeleteLine:
      # Undo delete line by inserting it
      b.backendInsertLine(change.deleteLineIdx, change.deletedLineText)
      b.foldState.adjustFoldsAfterInsert(change.deleteLineIdx, 1)
    of ckDeleteRange:
      # Undo delete range by inserting the deleted text
      # Handle both single-line and multi-line deletions correctly
      b.insertTextWithNewlines(change.deleteStartPos, change.deletedRangeText)
    of ckReplaceLine:
      b.backendReplaceLine(change.replaceLineIdx, change.replaceLineOldText)
    of ckTransaction:
      # Undo all changes in transaction in reverse order
      for i in countdown(change.transactionChanges.len - 1, 0):
        let r = b.undoChange(change.transactionChanges[i])
        if r.isErr:
          return r
    of ckSnapshot:
      b.pieceTable.restoreSnapshot(change.snapshotData)
      b.lineMarkers = change.snapshotLineMarkers
      b.foldState = change.snapshotFoldState
      b.lastChangedLines = 0

    # Ensure lineMarkers stays in sync after undo operations
    b.ensureMarkersSize()
    return ok(())
  except CatchableError as e:
    logError("buffer", "Undo operation failed: " & e.msg)
    return err("Failed to undo change: " & e.msg)

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

  b.captureSnapshotIfNeeded()
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
    if b.pendingSnapshot.isSome:
      # PieceTable: single O(1) snapshot undo entry for entire transaction
      b.undoStack.addLast(
        BufferChange(
          kind: ckSnapshot,
          snapshotData: b.pendingSnapshot.get,
          snapshotCursorPos: getChangePosition(transaction.changes[0]),
          snapshotLineMarkers: b.pendingSnapshotMarkers,
          snapshotFoldState: b.pendingSnapshotFolds,
        )
      )
      b.pendingSnapshot = none(PieceTableSnapshot)
    else:
      let transactionChange = BufferChange(
        kind: ckTransaction,
        transactionChanges: transaction.changes,
        transactionDescription: transaction.description,
      )
      b.undoStack.addLast(transactionChange)
    # Note: changeSeq was already incremented by each change in pushUndoChange
    # Note: redoStack was already cleared by the first change in pushUndoChange

    # Recompute lastChangedLines as the minimum across all changes.
    # Each individual change in pushUndoChange overwrites lastChangedLines,
    # so after the transaction only the last change's line remains.
    var minLine = int.high
    for ch in transaction.changes:
      minLine = min(minLine, getChangePosition(ch).line)
    if minLine != int.high:
      b.lastChangedLines = minLine

  return ok(())

proc rollbackTransaction*(b: TextBuffer): Result[(), string] =
  ## Rollback the current transaction by undoing all changes
  ## Restores changeSeq to its value at transaction start
  ## Returns error if no transaction is in progress
  if not b.inTransaction or b.currentTransaction.isNone:
    return err("No transaction in progress")

  # Undo all changes in transaction in reverse order
  let transaction = b.currentTransaction.get

  if b.pendingSnapshot.isSome:
    # PieceTable: O(1) restore from snapshot
    b.pieceTable.restoreSnapshot(b.pendingSnapshot.get)
    b.lineMarkers = b.pendingSnapshotMarkers
    b.foldState = b.pendingSnapshotFolds
    b.pendingSnapshot = none(PieceTableSnapshot)
  else:
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
    var minLine = int.high
    for change in transaction.changes:
      minLine = min(minLine, getChangePosition(change).line)
    if minLine != int.high:
      b.lastChangedLines = minLine

  b.inTransaction = false
  b.currentTransaction = none(BufferTransaction)
  return ok(())

proc joinLines*(b: TextBuffer, startLine: int, count: int = 1): Result[(), string] =
  ## Join lines starting from startLine
  ## count: number of lines to join (default: 1, meaning join current line with next)
  ## Example: count=1 joins 2 lines, count=2 joins 3 lines, etc.
  ## Returns error if there aren't enough lines to join

  if startLine < 0 or startLine >= b.len:
    return err("Line index out of bounds: " & $startLine)

  # Need at least one more line to join with
  if startLine + 1 >= b.len:
    return err("No line to join with")

  # Calculate actual number of lines to join
  let linesToJoin = min(count + 1, b.len - startLine)
  if linesToJoin < 2:
    return err("Not enough lines to join")

  # Begin transaction for multiple operations
  let txnResult = b.beginTransaction("join " & $linesToJoin & " lines")
  if txnResult.isErr:
    return err(txnResult.error)

  # Join lines one by one
  for i in 1 ..< linesToJoin:
    # Always join with the line at startLine (since we delete lines as we go)
    let currentLine = b.getLine(startLine)
    let nextLine = b.getLine(startLine + 1)

    # Trim trailing whitespace from current line
    var trimmedCurrent = currentLine.strip(leading = false, trailing = true)

    # Trim leading whitespace from next line
    let trimmedNext = nextLine.strip(leading = true, trailing = false)

    # Add a space between lines if current line doesn't end with whitespace
    # and next line is not empty
    if trimmedCurrent.len > 0 and trimmedNext.len > 0:
      # Don't add space if current line ends with certain punctuation
      let lastChar = trimmedCurrent[^1]
      if lastChar notin {' ', '\t', '\n'}:
        trimmedCurrent.add(' ')

    # Build the joined line
    let joinedLine = trimmedCurrent & trimmedNext

    # Delete the current line and insert the joined line
    let deleteResult = b.deleteLine(startLine)
    if deleteResult.isErr:
      discard b.commitTransaction()
      return err(deleteResult.error)

    # Delete the next line (which is now at startLine position)
    let deleteNextResult = b.deleteLine(startLine)
    if deleteNextResult.isErr:
      discard b.commitTransaction()
      return err(deleteNextResult.error)

    # Insert the joined line
    let insertResult = b.insert(startLine, joinedLine)
    if insertResult.isErr:
      discard b.commitTransaction()
      return err(insertResult.error)

  # Commit transaction
  let commitResult = b.commitTransaction()
  if commitResult.isErr:
    return err(commitResult.error)

  return ok(())

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

    # For snapshot undo: capture current state before restoring
    let redoEntry =
      if change.kind == ckSnapshot:
        BufferChange(
          kind: ckSnapshot,
          snapshotData: b.pieceTable.takeSnapshot(),
          snapshotCursorPos: change.snapshotCursorPos,
          snapshotLineMarkers: b.lineMarkers,
          snapshotFoldState: b.foldState,
        )
      else:
        change

    let r = b.undoChange(change)
    if r.isErr:
      # Restore the change to undo stack if undo failed
      b.undoStack.addLast(change)
      # Restore previously undone changes to undo stack
      for j in countdown(undoneChanges.len - 1, 0):
        b.undoStack.addLast(undoneChanges[j])
      return err("Undo failed: " & r.error)

    undoneChanges.add(redoEntry)

    # Decrement change sequence for each undo
    b.changeSeq.dec

  # Add all undone changes to redo stack in the order they were undone
  # This ensures redo applies them in the correct reverse order
  for change in undoneChanges:
    b.redoStack.addLast(change)

  # Mark highlight as needing update after undo
  if undoneChanges.len > 0:
    b.highlightNeedsUpdate = true

    # Compute first changed line from undone changes for incremental highlighting
    var minLine = int.high

    proc findMinLine(change: BufferChange) =
      case change.kind
      of ckTransaction:
        for innerChange in change.transactionChanges:
          findMinLine(innerChange)
      else:
        minLine = min(minLine, getChangePosition(change).line)

    for change in undoneChanges:
      findMinLine(change)

    if minLine != int.high:
      b.lastChangedLines = minLine

  # Return suggested cursor position for the last undone change (Vim behavior)
  if undoneChanges.len > 0:
    return ok(getChangePosition(undoneChanges[^1]))
  else:
    return ok(BufferPosition(line: 0, column: 0))

proc redoChange(b: TextBuffer, change: BufferChange): Result[(), string] =
  ## Re-apply a single change (internal helper)
  ## Returns error if the operation fails
  try:
    case change.kind
    of ckInsertText:
      # Use insertTextWithNewlines to handle newlines correctly during redo
      b.insertTextWithNewlines(change.insertPos, change.insertText)
    of ckDeleteText:
      let line = b.getLine(change.deletePos.line)
      let bytePos = charToBytePosCached(
        line, change.deletePos.column, b.cursorCache, change.deletePos.line, b.changeSeq
      )
      b.backendDeleteAtLineCol(change.deletePos.line, bytePos, change.deletedText.len)
    of ckInsertLine:
      b.backendInsertLine(change.insertLineIdx, change.insertLineText)
      b.foldState.adjustFoldsAfterInsert(change.insertLineIdx, 1)
    of ckDeleteLine:
      b.backendDeleteLine(change.deleteLineIdx)
      b.foldState.adjustFoldsAfterDelete(change.deleteLineIdx, 1)
    of ckDeleteRange:
      # Re-apply delete range using the same logic as the original deleteRange
      # Handle both single-line and multi-line deletions correctly
      let startPos = change.deleteStartPos
      let endPos = change.deleteEndPos

      if startPos.line == endPos.line:
        b.deleteRangeSingleLine(b.getLine(startPos.line), startPos, endPos)
      else:
        b.deleteRangeMultiLine(startPos, endPos)
        # Adjust fold positions for multi-line delete
        b.foldState.adjustFoldsAfterDelete(startPos.line, endPos.line - startPos.line)
    of ckReplaceLine:
      b.backendReplaceLine(change.replaceLineIdx, change.replaceLineNewText)
    of ckTransaction:
      # Redo all changes in transaction in forward order
      for change in change.transactionChanges:
        let r = b.redoChange(change)
        if r.isErr:
          return r
    of ckSnapshot:
      b.pieceTable.restoreSnapshot(change.snapshotData)
      b.lineMarkers = change.snapshotLineMarkers
      b.foldState = change.snapshotFoldState
      b.lastChangedLines = 0

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

    # For snapshot redo: capture current state before restoring
    let undoEntry =
      if change.kind == ckSnapshot:
        BufferChange(
          kind: ckSnapshot,
          snapshotData: b.pieceTable.takeSnapshot(),
          snapshotCursorPos: change.snapshotCursorPos,
          snapshotLineMarkers: b.lineMarkers,
          snapshotFoldState: b.foldState,
        )
      else:
        change

    let r = b.redoChange(change)
    if r.isErr:
      # Restore the change to redo stack if redo failed
      b.redoStack.addLast(change)
      # Restore previously redone changes to redo stack
      for j in countdown(redoneChanges.len - 1, 0):
        b.redoStack.addLast(redoneChanges[j])
      return err("Redo failed: " & r.error)

    redoneChanges.add(undoEntry)

    # Increment change sequence for each redo
    b.changeSeq.inc

  # Add redone changes back to undo stack in reverse order
  # This restores the original undo stack order after redo
  for i in countdown(redoneChanges.len - 1, 0):
    b.undoStack.addLast(redoneChanges[i])

  # Mark highlight as needing update after redo
  if redoneChanges.len > 0:
    b.highlightNeedsUpdate = true

    # Compute first changed line from redone changes for incremental highlighting
    var minLine = int.high

    proc findMinLine(change: BufferChange) =
      case change.kind
      of ckTransaction:
        for innerChange in change.transactionChanges:
          findMinLine(innerChange)
      else:
        minLine = min(minLine, getChangePosition(change).line)

    for change in redoneChanges:
      findMinLine(change)
    if minLine != int.high:
      b.lastChangedLines = minLine

  # Return suggested cursor position for the last redone change (Vim behavior)
  if redoneChanges.len > 0:
    return ok(getChangePosition(redoneChanges[^1]))
  else:
    return ok(BufferPosition(line: 0, column: 0))

# File operations

const AutoBackendLargeFileThreshold* = 10 * 1024 * 1024 # 10 MB

proc chooseBackendForFile(fileSize: int64 = 0): BufferBackend =
  if autoBackendMode:
    if fileSize >= AutoBackendLargeFileThreshold: PieceTable else: GapBuffer
  else:
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
  var content: string
  var fileSize: int64 = 0

  # Check if file exists; if not, start with empty content
  if fileExists(path):
    # File exists, read its content
    try:
      fileSize = getFileSize(path)
      content = readFile(path)
    except IOError as e:
      logError("buffer", "Failed to read file " & path & ": " & e.msg)
      return Result[(), string].err e.msg
  else:
    # File doesn't exist, start with empty content
    logDebug("buffer", "File does not exist, creating new: " & path)
    content = ""

  let newBackend = chooseBackendForFile(fileSize)

  # Reinitialize with new backend if needed
  if b.backendKind != newBackend:
    let newBuffer = newTextBuffer(content, some(path), backend = newBackend)
    b[] = newBuffer[]
  else:
    case b.backendKind
    of GapBuffer:
      b.gapBuffer = newGapBuffer(content)
    of SqrtDecomp:
      b.sqrtDecomp = newSqrtDecomp(content)
    of Rope:
      b.rope = newRope(content)
    of PieceTable:
      b.pieceTable = newPieceTable(content)

  b.detectLineEnding(content)
  b.encoding = detectCharacterEncoding(content)

  b.filePath = some(path)

  # Record file modification time for external change detection
  if fileExists(path):
    try:
      b.lastFileModTime = some(getFileInfo(path).lastWriteTime)
    except OSError:
      b.lastFileModTime = none(Time)
  else:
    b.lastFileModTime = none(Time)
  b.externalModWarned = false

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

proc getFileContent*(buffer: TextBuffer): string =
  ## Get the buffer content as it would be written to a file,
  ## with proper trailing newline handling based on endOfLine setting.
  result = buffer.getTextString

  if buffer.endOfLine:
    # Ensure content ends with newline
    if result.len == 0 or
        not (result.endsWith("\n") or result.endsWith("\r\n") or result.endsWith("\r")):
      case buffer.lineEnding
      of LF:
        result.add('\n')
      of CRLF:
        result.add("\r\n")
      of CR:
        result.add('\r')
  else:
    # Remove ONE trailing newline if present (endOfLine=false)
    if result.len > 0:
      if result.endsWith("\r\n"):
        result.setLen(result.len - 2)
      elif result.endsWith("\n") or result.endsWith("\r"):
        result.setLen(result.len - 1)

proc saveFile*(buffer: TextBuffer, path: string): Result[(), string] =
  case buffer.backendKind
  of GapBuffer, SqrtDecomp, Rope, PieceTable:
    let content = buffer.getFileContent

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

    # Update file modification time after saving
    try:
      buffer.lastFileModTime = some(getFileInfo(path).lastWriteTime)
    except OSError:
      buffer.lastFileModTime = none(Time)
    buffer.externalModWarned = false

  return Result[(), string].ok ()

proc isExternallyModified*(b: TextBuffer): bool =
  ## Check if the file was modified externally (outside the editor)
  ## Returns true if:
  ##   - Buffer has a file path
  ##   - File exists on disk
  ##   - File's modification time is newer than when we last loaded/saved it
  if b.filePath.isNone:
    return false

  let path = b.filePath.get
  if not fileExists(path):
    return false

  if b.lastFileModTime.isNone:
    return false

  try:
    let currentModTime = getFileInfo(path).lastWriteTime
    return currentModTime > b.lastFileModTime.get
  except OSError:
    return false

proc reloadFile*(b: TextBuffer): Result[(), string] =
  ## Reload file from disk, preserving the file path
  ## Call this when external modification is detected
  if b.filePath.isNone:
    return err("Buffer has no file path")

  let path = b.filePath.get
  b.loadFile(path)

# Memory usage monitoring
proc estimateMemoryUsage*(buffer: TextBuffer): int =
  result = sizeof(TextBuffer)

  case buffer.backendKind
  of GapBuffer:
    result += buffer.gapBuffer.estimateMemoryUsage()
  of SqrtDecomp:
    result += buffer.sqrtDecomp.estimateMemoryUsage()
  of Rope:
    result += buffer.rope.estimateMemoryUsage()
  of PieceTable:
    result += buffer.pieceTable.estimateMemoryUsage()

proc getPerformanceStats*(
    buffer: TextBuffer
): tuple[backend: string, memoryUsage: int, length: int] =
  let backendName =
    case buffer.backendKind
    of GapBuffer: "GapBuffer"
    of SqrtDecomp: "SqrtDecomp"
    of Rope: "Rope"
    of PieceTable: "PieceTable"

  (backend: backendName, memoryUsage: buffer.estimateMemoryUsage(), length: buffer.len)

# Sidebar marker management
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
  if b.highlightNeedsUpdate and not b.isUtilityBuffer:
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
          runesBuffer, b.incrementalHighlight, b.lastChangedLines, b.changeSeq,
          b.reservedWords, b.language,
        )

        # Convert IncrementalHighlight segments to Highlight
        b.highlight = Highlight(colorSegments: b.incrementalHighlight.segments)
      else:
        # Cache invalid or first time - do full parse
        b.highlight = initHighlight(runesBuffer, b.reservedWords, b.language)

        # Build initial incremental cache for next time
        if runesBuffer.len > 0:
          # Parse entire buffer with default initial state
          let (segments, lineStates) = initHighlightIncremental(
            runesBuffer,
            0,
            runesBuffer.high,
            TokenizerState(), # Default initial state
            b.reservedWords,
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

proc findNext*(
    b: TextBuffer, searchText: string, startPos: BufferPosition, ignorecase = false
): Option[BufferPosition] =
  ## Find the next occurrence of searchText starting from startPos
  ## Returns the position of the match or none if not found
  ##
  ## The search wraps around from the beginning if not found after startPos
  ##
  ## Unicode-aware: All positions are in character (rune) indices, not byte indices
  if searchText.len == 0:
    return none(BufferPosition)

  let lineCount = b.len
  if lineCount == 0:
    return none(BufferPosition)

  # Validate startPos - clamp to valid range
  if startPos.line < 0 or startPos.line >= lineCount:
    return none(BufferPosition)

  # Prepare search string once (optimization: avoid repeated toLowerAscii calls)
  let searchTextPrepared = prepareSearchString(searchText, ignorecase)

  # Helper proc to search a line (Unicode-aware)
  # Takes and returns character positions, not byte positions
  # Returns -1 if no match found or if line is empty
  proc searchLine(line: string, startCharCol = 0): int =
    # Early exit for empty lines
    if line.len == 0:
      return -1

    # Prepare search string (case-insensitive if needed)
    let linePrepared = prepareSearchString(line, ignorecase)

    # Defensive check: ensure search pattern isn't longer than remaining line
    let lineCharLen = line.charLen
    if startCharCol >= lineCharLen:
      return -1

    # Clamp startCharCol to valid range [0, lineCharLen]
    let clampedStartCol = max(0, min(startCharCol, lineCharLen))

    # Convert character position to byte position for find()
    # This conversion is safe because clampedStartCol is within valid range
    let startByteCol = charToBytePos(line, clampedStartCol)

    # Defensive check: ensure startByteCol is within string bounds
    if startByteCol > line.len:
      return -1

    # Search using byte position
    let byteIdx = linePrepared.find(searchTextPrepared, startByteCol)

    if byteIdx < 0:
      return -1

    # Convert byte position back to character position
    # This conversion is safe because byteIdx comes from a valid find() result
    return byteToCharPos(line, byteIdx)

  # Start searching from the current position
  # First, search the rest of the current line
  let currentLine = b.getLine(startPos.line)
  let currentLineCharLen = currentLine.charLen

  # Handle negative column: start from beginning of line
  # Otherwise, start from after the current position
  let searchStartCol =
    if startPos.column < 0:
      0
    else:
      min(startPos.column + 1, currentLineCharLen)

  let idx = searchLine(currentLine, searchStartCol)

  # Only return if we found something after the current position
  # For negative startPos.column, any match is valid
  if idx >= 0 and (startPos.column < 0 or idx > startPos.column):
    return some(BufferPosition(line: startPos.line, column: idx))

  # Search remaining lines after current line
  for lineIdx in (startPos.line + 1) ..< lineCount:
    let line = b.getLine(lineIdx)
    if line.len == 0:
      continue # Skip empty lines
    let idx = searchLine(line)
    if idx >= 0:
      return some(BufferPosition(line: lineIdx, column: idx))

  # Wrap around: search from beginning to current line
  for lineIdx in 0 .. startPos.line:
    let line = b.getLine(lineIdx)
    if line.len == 0:
      continue # Skip empty lines

    if lineIdx == startPos.line:
      # On current line, only search up to current position (excluding current position)
      # For negative column, we already searched the whole line, so skip it
      if startPos.column < 0:
        continue
      let idx = searchLine(line, 0)
      if idx >= 0 and idx < startPos.column:
        return some(BufferPosition(line: lineIdx, column: idx))
    else:
      let idx = searchLine(line)
      if idx >= 0:
        return some(BufferPosition(line: lineIdx, column: idx))

  return none(BufferPosition)

proc findPrev*(
    b: TextBuffer, searchText: string, startPos: BufferPosition, ignorecase = false
): Option[BufferPosition] =
  ## Find the previous occurrence of searchText starting from startPos
  ## Returns the position of the match or none if not found
  ##
  ## The search wraps around from the end if not found before startPos
  ##
  ## Unicode-aware: All positions are in character (rune) indices, not byte indices
  if searchText.len == 0:
    return none(BufferPosition)

  let lineCount = b.len
  if lineCount == 0:
    return none(BufferPosition)

  # Validate startPos - clamp to valid range
  if startPos.line < 0 or startPos.line >= lineCount:
    return none(BufferPosition)

  # Prepare search string once (optimization: avoid repeated toLowerAscii calls)
  let searchTextPrepared = prepareSearchString(searchText, ignorecase)

  # Helper proc to find last occurrence in a line (Unicode-aware)
  # Takes and returns character positions, not byte positions
  # Returns -1 if no match found or if line is empty
  proc findLastInLine(line: string, maxCharCol = -1): int =
    # Early exit for empty lines
    if line.len == 0:
      return -1

    # Prepare search string (case-insensitive if needed)
    let linePrepared = prepareSearchString(line, ignorecase)
    let lineCharLen = line.charLen

    var lastCharIdx = -1
    var searchCharPos = 0

    # Clamp maxCharCol to valid range
    let searchCharLimit =
      if maxCharCol < 0:
        lineCharLen
      elif maxCharCol == 0:
        0 # Don't search if maxCharCol is 0
      else:
        min(maxCharCol, lineCharLen)

    # Iterate through all matches up to searchCharLimit
    while searchCharPos < searchCharLimit:
      # Convert character position to byte position
      # This conversion is safe because searchCharPos < searchCharLimit <= lineCharLen
      let searchBytePos = charToBytePos(line, searchCharPos)

      # Defensive check: ensure byte position is within bounds
      if searchBytePos > line.len:
        break

      # Search using byte position
      let byteIdx = linePrepared.find(searchTextPrepared, searchBytePos)

      if byteIdx < 0:
        break

      # Convert byte position back to character position
      # This conversion is safe because byteIdx comes from a valid find() result
      let charIdx = byteToCharPos(line, byteIdx)

      # Update last match if within limit
      if maxCharCol < 0 or charIdx < maxCharCol:
        lastCharIdx = charIdx
        searchCharPos = charIdx + 1
      else:
        break

    lastCharIdx

  # Start searching backwards from the current position
  # First, search backwards in the current line
  let currentLine = b.getLine(startPos.line)
  let currentLineCharLen = currentLine.charLen

  # Handle negative column: skip current line and start from previous lines
  # Otherwise, search up to the current position
  if startPos.column >= 0:
    let clampedColumn = min(startPos.column, currentLineCharLen)
    let lastIdx = findLastInLine(currentLine, clampedColumn)

    if lastIdx >= 0 and lastIdx < clampedColumn:
      return some(BufferPosition(line: startPos.line, column: lastIdx))

  # Search lines before current line (backwards)
  for lineIdx in countdown(startPos.line - 1, 0):
    let line = b.getLine(lineIdx)
    if line.len == 0:
      continue # Skip empty lines

    let lastIdx = findLastInLine(line)
    if lastIdx >= 0:
      return some(BufferPosition(line: lineIdx, column: lastIdx))

  # Wrap around: search from end to current line
  for lineIdx in countdown(lineCount - 1, startPos.line):
    let line = b.getLine(lineIdx)
    if line.len == 0:
      continue # Skip empty lines

    if lineIdx == startPos.line:
      # On current line after wrap, find last occurrence after current position
      let lineCharLen = line.charLen

      # For negative column, search the whole line
      let searchStartCharCol =
        if startPos.column < 0:
          0
        else:
          min(startPos.column + 1, lineCharLen)

      if searchStartCharCol >= lineCharLen:
        continue

      var lastCharIdx = -1
      var searchCharPos = searchStartCharCol
      let linePrepared = prepareSearchString(line, ignorecase)

      # Iterate through all matches after searchStartCharCol
      while searchCharPos < lineCharLen:
        # Convert character position to byte position
        # This conversion is safe because searchCharPos < lineCharLen
        let searchBytePos = charToBytePos(line, searchCharPos)

        # Defensive check: ensure byte position is within bounds
        if searchBytePos > line.len:
          break

        # Search using byte position
        let byteIdx = linePrepared.find(searchTextPrepared, searchBytePos)

        if byteIdx < 0:
          break

        # Convert byte position back to character position
        # This conversion is safe because byteIdx comes from a valid find() result
        let charIdx = byteToCharPos(line, byteIdx)
        lastCharIdx = charIdx
        searchCharPos = charIdx + 1

      # For negative column, any match is valid
      # Otherwise, only return if after current position
      if lastCharIdx >= 0 and (startPos.column < 0 or lastCharIdx > startPos.column):
        return some(BufferPosition(line: lineIdx, column: lastCharIdx))
    else:
      let lastIdx = findLastInLine(line)
      if lastIdx >= 0:
        return some(BufferPosition(line: lineIdx, column: lastIdx))

  return none(BufferPosition)

proc isPositionInSearchMatch*(
    b: TextBuffer,
    pos: BufferPosition,
    searchText: string,
    ignorecase = false,
    wholeWord = false,
): bool =
  ## Check if the given position is within a search match
  ## Returns true if pos is at the start of a match or within a match
  ##
  ## If wholeWord is true, only matches that are at word boundaries are considered
  ##
  ## Optimized: only converts strings to lowercase once
  ##
  ## Unicode-aware: All positions are in character (rune) indices, not byte indices
  ##
  ## Returns false for invalid positions or empty search text

  # Validate search text
  if searchText.len == 0:
    return false

  # Validate line number
  if pos.line < 0 or pos.line >= b.len:
    return false

  # Get line and validate it's not empty
  let line = b.getLine(pos.line)
  if line.len == 0:
    return false

  # Validate column position
  let lineCharLen = line.charLen
  if pos.column < 0 or pos.column >= lineCharLen:
    return false

  # Prepare search strings once (optimization: avoid repeated toLowerAscii calls)
  let searchTextPrepared = prepareSearchString(searchText, ignorecase)
  let linePrepared = prepareSearchString(line, ignorecase)
  let searchTextCharLen = searchText.charLen

  # Early exit: if search text is longer than line, no match possible
  if searchTextCharLen > lineCharLen:
    return false

  # Early exit: if position is before the first possible match
  let firstPossibleMatchByte = linePrepared.find(searchTextPrepared)
  if firstPossibleMatchByte < 0:
    return false

  # Convert first match byte position to character position
  # This conversion is safe because firstPossibleMatchByte comes from valid find()
  let firstPossibleMatchChar = byteToCharPos(line, firstPossibleMatchByte)
  if pos.column < firstPossibleMatchChar:
    return false

  # Helper proc to check if a rune is a word character
  proc isWordChar(r: Rune): bool =
    let code = int(r)
    r.isAlpha or (code >= ord('0') and code <= ord('9')) or r == Rune('_')

  # Helper to check word boundary at a match position
  proc isWholeWordMatch(runes: seq[Rune], matchCol: int, matchLen: int): bool =
    # Check character before match (must not be word char or at start)
    if matchCol > 0:
      if isWordChar(runes[matchCol - 1]):
        return false
    # Check character after match (must not be word char or at end)
    let endCol = matchCol + matchLen
    if endCol < runes.len:
      if isWordChar(runes[endCol]):
        return false
    return true

  let runes =
    if wholeWord:
      line.toRunes()
    else:
      @[]

  # Find all matches in the line and check if pos is within any match
  var searchCharPos = 0
  while searchCharPos <= lineCharLen:
    # Convert character position to byte position
    # This conversion is safe because searchCharPos <= lineCharLen
    let searchBytePos = charToBytePos(line, searchCharPos)

    # Defensive check: ensure byte position is within bounds
    if searchBytePos > line.len:
      break

    # Search using byte position
    let byteIdx = linePrepared.find(searchTextPrepared, searchBytePos)

    if byteIdx < 0:
      break

    # Convert byte position back to character position
    # This conversion is safe because byteIdx comes from a valid find() result
    let charIdx = byteToCharPos(line, byteIdx)

    # Check if pos.column is within this match [charIdx, charIdx + searchTextCharLen)
    if pos.column >= charIdx and pos.column < charIdx + searchTextCharLen:
      # If whole word matching, check word boundaries
      if wholeWord:
        if isWholeWordMatch(runes, charIdx, searchTextCharLen):
          return true
        # Not a whole word match, continue searching
      else:
        return true

    # Early exit: if we've passed the position, no need to continue
    if charIdx > pos.column:
      return false

    searchCharPos = charIdx + 1

  return false

# Matching Paren/Bracket Highlight

const
  openBrackets = ['(', '[', '{', '<']
  closeBrackets = [')', ']', '}', '>']

proc findMatchingParenPosition*(
    b: TextBuffer, cursor: BufferPosition
): Option[BufferPosition] =
  ## Find the position of the matching parenthesis/bracket/brace
  ## Searches across multiple lines. Returns none if cursor is not on a bracket
  ## or no matching bracket is found.

  if cursor.line < 0 or cursor.line >= b.len:
    return none(BufferPosition)

  let line = b.getLine(cursor.line)
  let runes = line.toRunes()

  if runes.len == 0 or cursor.column >= runes.len:
    return none(BufferPosition)

  let charAtCursor = ($runes[cursor.column])[0]

  var openChar, closeChar: char
  var searchForward = false

  # Check if cursor is on a bracket
  if charAtCursor in openBrackets:
    openChar = charAtCursor
    closeChar = closeBrackets[openBrackets.find(charAtCursor)]
    searchForward = true
  elif charAtCursor in closeBrackets:
    closeChar = charAtCursor
    openChar = openBrackets[closeBrackets.find(charAtCursor)]
    searchForward = false
  else:
    return none(BufferPosition)

  if searchForward:
    # Search forward for closing bracket
    var depth = 1
    var searchLine = cursor.line
    var searchCol = cursor.column + 1

    while searchLine < b.len:
      let curLine = b.getLine(searchLine)
      let curRunes = curLine.toRunes()

      while searchCol < curRunes.len:
        let ch = ($curRunes[searchCol])[0]
        if ch == openChar:
          depth.inc
        elif ch == closeChar:
          depth.dec
          if depth == 0:
            return some(BufferPosition(line: searchLine, column: searchCol))
        searchCol.inc

      searchLine.inc
      searchCol = 0
  else:
    # Search backward for opening bracket
    var depth = 1
    var searchLine = cursor.line
    var searchCol = cursor.column - 1

    while searchLine >= 0:
      if searchCol < 0:
        searchLine.dec
        if searchLine >= 0:
          let prevLine = b.getLine(searchLine)
          searchCol = prevLine.toRunes().len - 1
        continue

      let curLine = b.getLine(searchLine)
      let curRunes = curLine.toRunes()

      while searchCol >= 0:
        let ch = ($curRunes[searchCol])[0]
        if ch == closeChar:
          depth.inc
        elif ch == openChar:
          depth.dec
          if depth == 0:
            return some(BufferPosition(line: searchLine, column: searchCol))
        searchCol.dec

      searchLine.dec
      if searchLine >= 0:
        let prevLine = b.getLine(searchLine)
        searchCol = prevLine.toRunes().len - 1

  return none(BufferPosition)

proc addFold*(
    state: var FoldState,
    startLine, endLine: int,
    collapsed: bool = true,
    collapsedText: Option[string] = none(string),
): bool =
  ## Add a new fold. Returns true if successful, false if overlapping with existing fold.
  ## Folds are kept sorted by startLine. Single-line folds (startLine == endLine) are allowed.
  ## collapsed: Whether the fold starts collapsed (default: true)
  ## collapsedText: Custom text to display when collapsed (from LSP)
  if startLine > endLine or startLine < 0:
    return false

  # Check for overlapping folds
  for fold in state.folds:
    # Check if new fold overlaps with existing fold
    if not (endLine < fold.startLine or startLine > fold.endLine):
      return false

  # Insert in sorted order by startLine
  var insertIdx = state.folds.len
  for i, fold in state.folds:
    if startLine < fold.startLine:
      insertIdx = i
      break

  state.folds.insert(
    Fold(
      startLine: startLine,
      endLine: endLine,
      collapsed: collapsed,
      collapsedText: collapsedText,
    ),
    insertIdx,
  )
  return true

proc getFoldAt*(state: FoldState, line: int): Option[ptr Fold] =
  ## Get the fold containing the given line (if any)
  ## Returns a pointer to allow modification
  for i in 0 ..< state.folds.len:
    let fold = state.folds[i]
    if line >= fold.startLine and line <= fold.endLine:
      return some(unsafeAddr state.folds[i])
  return none(ptr Fold)

proc getFoldAtStartLine*(state: FoldState, line: int): Option[ptr Fold] =
  ## Get the fold that starts at the given line (if any)
  for i in 0 ..< state.folds.len:
    if state.folds[i].startLine == line:
      return some(unsafeAddr state.folds[i])
  return none(ptr Fold)

proc isLineInCollapsedFold*(state: FoldState, line: int): bool =
  ## Check if a line is inside a collapsed fold (but not the start line)
  for fold in state.folds:
    if fold.collapsed and line > fold.startLine and line <= fold.endLine:
      return true
  return false

proc getCollapsedFoldAt*(state: FoldState, line: int): Option[Fold] =
  ## Get the collapsed fold that contains this line (for rendering the fold marker)
  for fold in state.folds:
    if fold.collapsed and line >= fold.startLine and line <= fold.endLine:
      return some(fold)
  return none(Fold)

proc openFold*(state: var FoldState, line: int): bool =
  ## Open the fold at the given line. Returns true if a fold was opened.
  let foldOpt = state.getFoldAt(line)
  if foldOpt.isSome:
    foldOpt.get[].collapsed = false
    return true
  return false

proc closeFold*(state: var FoldState, line: int): bool =
  ## Close the fold at the given line. Returns true if a fold was closed.
  let foldOpt = state.getFoldAt(line)
  if foldOpt.isSome:
    foldOpt.get[].collapsed = true
    return true
  return false

proc toggleFold*(state: var FoldState, line: int): bool =
  ## Toggle the fold at the given line. Returns true if a fold was toggled.
  let foldOpt = state.getFoldAt(line)
  if foldOpt.isSome:
    foldOpt.get[].collapsed = not foldOpt.get[].collapsed
    return true
  return false

proc deleteFold*(state: var FoldState, line: int): bool =
  ## Delete the fold containing the given line. Returns true if a fold was deleted.
  for i in 0 ..< state.folds.len:
    let fold = state.folds[i]
    if line >= fold.startLine and line <= fold.endLine:
      state.folds.delete(i)
      return true
  return false

proc openAllFolds*(state: var FoldState) =
  ## Open all folds
  for i in 0 ..< state.folds.len:
    state.folds[i].collapsed = false

proc closeAllFolds*(state: var FoldState) =
  ## Close all folds
  for i in 0 ..< state.folds.len:
    state.folds[i].collapsed = true

proc deleteAllFolds*(state: var FoldState) =
  ## Delete all folds (zD command)
  state.folds = @[]

proc getNextVisibleLine*(state: FoldState, line: int, maxLine: int): int =
  ## Get the next visible line after a folded region
  ## If line is inside a collapsed fold, skip to the line after the fold
  for fold in state.folds:
    if fold.collapsed and line >= fold.startLine and line <= fold.endLine:
      return min(fold.endLine + 1, maxLine)
  return line

proc getPrevVisibleLine*(state: FoldState, line: int): int =
  ## Get the previous visible line (skip over collapsed folds)
  ## If line is at the end of a collapsed fold, jump to the start line
  for fold in state.folds:
    if fold.collapsed and line > fold.startLine and line <= fold.endLine:
      return fold.startLine
  return line

proc formatFoldText*(b: TextBuffer, fold: Fold): string =
  ## Format the display text for a collapsed fold (vim-style)
  ## Example: "+-- 10 lines: func foo() {...}"
  ## If LSP provided collapsedText, use it instead of generating preview
  let lineCount = fold.endLine - fold.startLine + 1

  # Use LSP-provided collapsedText if available
  if fold.collapsedText.isSome and fold.collapsedText.get.len > 0:
    result = "+-- " & $lineCount & " lines: " & fold.collapsedText.get
  else:
    let firstLine = b.getLine(fold.startLine)
    # Use character-based slicing for UTF-8 safety
    let firstLineCharLen = firstLine.charLen
    let preview =
      if firstLineCharLen > 40:
        firstLine.runeSubStr(0, 40) & "..."
      else:
        firstLine
    result = "+-- " & $lineCount & " lines: " & preview
