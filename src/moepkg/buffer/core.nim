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

## Core buffer types: TextBuffer, BufferChange, FoldState, and supporting enums.

import std/[algorithm, deques, hashes, options, times, unicode]

import ../[encoding, highlight, primitives, unicode_utils]
import ../buffer_backends/[gap_buffer, sqrt_decomp, rope, piece_table]

export
  CharacterEncoding, encodingToString, detectCharacterEncoding, BufferPosition,
  ColumnRange

type
  BufferId* = distinct int
    ## Unique identifier for a TextBuffer.
    ## Stable for the lifetime of a process (not persisted across restarts).
    ## `BufferId(0)` is reserved as the "unassigned" sentinel — `genBufferId`
    ## starts handing out ids from 1 so that the zero-initialized default of
    ## `state.windowDisplay.currentBufferId` can't accidentally collide with a real buffer.

  LineMarkerKind* = enum
    ## Per-line marker classification stored in `TextBuffer.lineMarkers`.
    ## Renderer-side "empty" is represented by Option[LineMarkerKind] = none.
    GitAdded ## Line was added in git diff
    GitChanged ## Line was changed in git diff
    GitDeleted ## Line was deleted in git diff
    GitChangedAndDeleted ## Line was changed and deleted in git diff
    GitConflict ## Line is inside a git merge conflict block
    SyntaxError ## Syntax error indicator
    SyntaxWarning ## Syntax warning indicator
    SessionModified ## Line was modified in current session (cleared on save)
    SessionInserted ## Line was inserted in current session (cleared on save)
    Bookmark ## Line has a bookmark

  ConflictMarkerKind* = enum
    ## Classification of a line with respect to a git merge conflict block
    cmkNone ## Line is outside any conflict block
    cmkStartMarker ## The `<<<<<<<` marker line
    cmkOurs ## Line between `<<<<<<<` and `=======` (or `|||||||`)
    cmkBaseMarker ## The `|||||||` marker line (diff3 style only)
    cmkBase ## Line between `|||||||` and `=======` (diff3 style only)
    cmkSeparator ## The `=======` marker line
    cmkTheirs ## Line between `=======` and `>>>>>>>`
    cmkEndMarker ## The `>>>>>>>` marker line

  ConflictBlock* = object
    ## A single git merge conflict block (from `<<<<<<<` through `>>>>>>>`)
    startLine*: int ## Line index of `<<<<<<<`
    baseMarkerLine*: Option[int] ## Line index of `|||||||` (diff3 only)
    separatorLine*: int ## Line index of `=======`
    endLine*: int ## Line index of `>>>>>>>`
    oursLabel*: string ## Label after `<<<<<<<` (e.g. "HEAD")
    theirsLabel*: string ## Label after `>>>>>>>` (e.g. branch name)

  BufferDiagnosticSeverity* = enum
    bdsError = 1
    bdsWarning = 2
    bdsInformation = 3
    bdsHint = 4

  BufferDiagnostic* = object
    startLine*, startCol*: int
    endLine*, endCol*: int
    severity*: BufferDiagnosticSeverity
    message*: string

  LineModificationKind* = enum
    lmkUnmodified ## Line has not been modified since last save
    lmkModified ## Line content was changed since last save
    lmkInserted ## Line was inserted since last save

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
    savedModifiedLines*: seq[LineModificationKind]
      ## Pre-mutation modifiedLines snapshot for undo/redo (1 byte per line)
    startSeq*: int
      ## changeSeq value BEFORE this entry was applied. undo() restores changeSeq
      ## to this so a transaction collapsing N mutations is reverted atomically.
    endSeq*: int
      ## changeSeq value AFTER this entry was applied. redo() restores to this.
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
      transactionCursorPos*: Option[BufferPosition]
    of ckSnapshot:
      snapshotData*: PieceTableSnapshot
      snapshotCursorPos*: BufferPosition
      snapshotLineMarkers*: seq[Option[LineMarkerKind]]
      snapshotModifiedLines*: seq[LineModificationKind]
      snapshotFoldState*: FoldState

  BufferTransaction* = object ## Transaction for grouping multiple changes
    changes*: seq[BufferChange]
    description*: string
    startSeq*: int # changeSeq at the start of transaction
    cursorPos*: Option[BufferPosition] # Cursor position before the transaction

  TextBuffer* = ref object
    id*: BufferId # Unique buffer identifier
    backend*: BufferBackend
    filePath*: Option[string]
    displayName*: Option[string]
      # Overrides the tab label when set (used for Terminal buffers, etc.).
      # Skips the `[+]` modified mark.
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

    # Pre-mutation modifiedLines snapshot (for non-PieceTable undo/redo)
    pendingModifiedLinesSnapshot*: seq[LineModificationKind]
    hasPendingModifiedLinesSnapshot*: bool

    # Change sequence tracking for modified flag
    changeSeq*: int # Current change sequence number
    savedSeq*: int # Sequence number when file was last saved

    # Transaction support
    currentTransaction*: Option[BufferTransaction]
    inTransaction*: bool

    # PieceTable snapshot support for O(1) undo/redo
    pendingSnapshot*: Option[PieceTableSnapshot]
    pendingSnapshotMarkers*: seq[Option[LineMarkerKind]]
    pendingSnapshotModifiedLines*: seq[LineModificationKind]
    pendingSnapshotFolds*: FoldState

    # Sidebar markers (line-based markers for git diff, syntax errors, etc.)
    lineMarkers*: seq[Option[LineMarkerKind]] # Each line can have at most one marker

    # Git merge conflict ranges (populated by git_conflict.scanBufferForConflicts)
    conflictBlocks*: seq[ConflictBlock]

    # Modified line tracking (session-based, cleared on save)
    modifiedLines*: seq[LineModificationKind]
      # How each line was modified since last save

    # Syntax highlighting
    highlight*: Highlight # Syntax highlighting for this buffer
    language*: SourceLanguage # Programming language for syntax highlighting
    highlightNeedsUpdate*: bool # Flag to track if highlight needs regeneration
    incrementalHighlight*: IncrementalHighlight # Incremental highlighting cache
    lastChangedLines*: int # First changed line for incremental highlight
    reservedWords*: seq[ReservedWord] # Reserved words to highlight (TODO, NOTE, etc.)
    uriScanParsedUpTo*: int # Last line scanned for URIs during progressive init

    # Performance optimization
    cursorCache*: CursorPosCache # Cache for character-to-byte position conversions

    # Change list (tracks positions where changes were made, like Vim's changelist)
    changeList*: seq[BufferPosition]
    changeListIndex*: int

    # Line folding state (vim-like manual folding)
    foldState*: FoldState

    # Bookmarks (sorted list of bookmarked line numbers)
    bookmarks*: seq[int]

    # LSP diagnostics (full detail for hover display)
    diagnostics*: seq[BufferDiagnostic]

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

const AutoBackendLargeFileThreshold* = 10 * 1024 * 1024 # 10 MB

var nextBufferId = 1
  ## Starts at 1 so `BufferId(0)` is reserved as a sentinel for the
  ## zero-initialized default of `state.windowDisplay.currentBufferId`. See `BufferId`.

var configuredBackend: BufferBackend = GapBuffer
var autoBackendMode: bool = false

proc `==`*(a, b: BufferId): bool {.borrow.}
proc `$`*(id: BufferId): string {.borrow.}
proc hash*(id: BufferId): Hash {.borrow.}

proc genBufferId(): BufferId =
  result = BufferId(nextBufferId)
  inc nextBufferId

proc resetBufferIdCounterForTests*() =
  ## Reset the global `nextBufferId` counter back to its initial value.
  ## Intended for tests that want deterministic ids across runs; production
  ## code must never call this — recycled ids would alias live buffers.
  nextBufferId = 1

proc setConfiguredBackend*(backend: BufferBackend) =
  configuredBackend = backend

proc setAutoBackendMode*(enabled: bool) =
  autoBackendMode = enabled

proc chooseBackendForFile*(fileSize: int64 = 0): BufferBackend =
  if autoBackendMode:
    if fileSize >= AutoBackendLargeFileThreshold: PieceTable else: GapBuffer
  else:
    configuredBackend

proc chooseBackend*(): BufferBackend =
  ## Choose a backend without file-size context. In auto mode this assumes a
  ## small (new / empty) buffer; callers that know the size should use
  ## `chooseBackendForFile` instead.
  chooseBackendForFile(0)

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

proc toggleBookmark*(b: TextBuffer, line: int) =
  ## Toggle a bookmark on the given line
  let idx = b.bookmarks.binarySearch(line)
  if idx >= 0:
    b.bookmarks.delete(idx)
  else:
    let insertIdx = b.bookmarks.lowerBound(line)
    b.bookmarks.insert(line, insertIdx)

proc hasBookmark*(b: TextBuffer, line: int): bool =
  ## Check if a line has a bookmark
  b.bookmarks.binarySearch(line) >= 0

proc clearBookmarks*(b: TextBuffer) =
  ## Clear all bookmarks in this buffer
  b.bookmarks.setLen(0)

proc findNextBookmark*(b: TextBuffer, currentLine: int): Option[int] =
  ## Find the next bookmark after currentLine (wraps around)
  if b.bookmarks.len == 0:
    return none(int)
  # Find the first bookmark after currentLine
  let idx = b.bookmarks.lowerBound(currentLine + 1)
  if idx < b.bookmarks.len:
    return some(b.bookmarks[idx])
  # Wrap around to the first bookmark
  return some(b.bookmarks[0])

proc findPrevBookmark*(b: TextBuffer, currentLine: int): Option[int] =
  ## Find the previous bookmark before currentLine (wraps around)
  if b.bookmarks.len == 0:
    return none(int)
  # Find the last bookmark before currentLine
  let idx = b.bookmarks.lowerBound(currentLine)
  if idx > 0:
    return some(b.bookmarks[idx - 1])
  # Wrap around to the last bookmark
  return some(b.bookmarks[^1])

proc adjustBookmarksForInsert*(b: TextBuffer, line: int, count: int = 1) =
  ## Adjust bookmark line numbers after lines are inserted at `line`
  for i in 0 ..< b.bookmarks.len:
    if b.bookmarks[i] >= line:
      b.bookmarks[i] += count

proc adjustBookmarksForDelete*(b: TextBuffer, line: int, count: int = 1) =
  ## Adjust bookmark line numbers after `count` lines are deleted starting at `line`
  var toRemove: seq[int] = @[]
  let deleteEnd = line + count - 1
  for i in 0 ..< b.bookmarks.len:
    if b.bookmarks[i] >= line and b.bookmarks[i] <= deleteEnd:
      toRemove.add(i)
    elif b.bookmarks[i] > deleteEnd:
      b.bookmarks[i] -= count
  for i in countdown(toRemove.high, 0):
    b.bookmarks.delete(toRemove[i])

proc isModified*(b: TextBuffer): bool {.inline.} =
  ## Check if buffer has unsaved changes
  b.changeSeq != b.savedSeq

proc markSaved*(b: TextBuffer) {.inline.} =
  ## Mark the buffer as unmodified by syncing savedSeq to changeSeq.
  b.savedSeq = b.changeSeq
  for i in 0 ..< b.modifiedLines.len:
    b.modifiedLines[i] = lmkUnmodified

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

proc newTextBuffer*(
    content: sink string = "",
    filePath: Option[string] = none(string),
    backend: BufferBackend = chooseBackend(),
    skipHighlightInit: bool = false,
): TextBuffer =
  var c = move content

  # Construct the object variant. Only the discriminant and the matching
  # backend-storage field can be set here; all other fields are populated
  # below in a single block to avoid per-backend duplication.
  result =
    case backend
    of GapBuffer:
      TextBuffer(backendKind: GapBuffer, gapBuffer: newGapBuffer(move c))
    of SqrtDecomp:
      TextBuffer(backendKind: SqrtDecomp, sqrtDecomp: newSqrtDecomp(move c))
    of Rope:
      TextBuffer(backendKind: Rope, rope: newRope(move c))
    of PieceTable:
      TextBuffer(backendKind: PieceTable, pieceTable: newPieceTable(move c))

  let lineCount = result.len
  result.id = genBufferId()
  result.backend = backend
  result.filePath = filePath
  result.lineEnding = LF
  result.encoding = utf8
  result.endOfLine = true # Default to POSIX text file standard
  result.undoStack = initDeque[BufferChange]()
  result.redoStack = initDeque[BufferChange]()
  result.lineMarkers = newSeq[Option[LineMarkerKind]](lineCount)
  result.modifiedLines = newSeq[LineModificationKind](lineCount)
  result.language = SourceLanguage.langNone
  # Invalid-state cache (line=-1 forces a recompute on first lookup)
  result.cursorCache = CursorPosCache(line: -1, charPos: 0, bytePos: 0, changeSeq: -1)
  result.foldState = initFoldState()
  result.editorConfig = none(BufferEditorConfig)

  # Build initial plain-text highlight. Callers like loadFile pass
  # skipHighlightInit=true because they'll rebuild highlighting themselves;
  # skipping avoids an O(n) runesBuffer construction that would be thrown away.
  if skipHighlightInit:
    result.highlight = initHighlight()
  else:
    var runesBuffer = newSeq[Runes](lineCount)
    for i in 0 ..< lineCount:
      runesBuffer[i] = result.getLine(i).toRunes()
    result.highlight = initHighlight(runesBuffer)

proc `[]`*(b: TextBuffer, lineIndex: int): string =
  ## Bracket operator for accessing lines by index
  b.getLine(lineIndex)

proc getLineLen*(b: TextBuffer, lineIndex: int): int =
  ## Get Unicode character count of line (not byte length).
  ## Use this for cursor/column position calculations.
  b.getLine(lineIndex).charLen

# Word detection helpers for currentWord highlighting
proc isWordChar*(r: Rune): bool =
  ## Check if a character is part of a word (alphanumeric or underscore).
  ## Uses Unicode-aware `isAlpha` so non-ASCII letters (CJK, accented Latin,
  ## Cyrillic, Greek, etc.) are treated as word characters. Digits are kept
  ## ASCII-only to match common source-code conventions.
  let c = r.int32
  return r.isAlpha or (c >= '0'.ord and c <= '9'.ord) or c == '_'.ord

proc getWordAtPosition*(b: TextBuffer, pos: BufferPosition): string =
  ## Get the word at the given buffer position.
  ## A "word" follows `isWordChar` semantics, so CJK and other Unicode letters
  ## are included alongside ASCII alphanumerics and underscore.
  ## Returns empty string if cursor is not on a word character.
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
  ## Check if the position is part of a word that matches the given word.
  ## Word boundaries are determined by `isWordChar`, which treats Unicode
  ## letters (CJK, accented Latin, etc.) as word characters.
  ## Used for currentWord highlighting.
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

proc getChangePosition*(change: BufferChange): BufferPosition =
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
    # For transactions, return the saved cursor position if available,
    # otherwise fall back to the position of the first change
    if change.transactionCursorPos.isSome:
      return change.transactionCursorPos.get
    elif change.transactionChanges.len > 0:
      return getChangePosition(change.transactionChanges[0])
    else:
      return BufferPosition(line: 0, column: 0)
  of ckSnapshot:
    return change.snapshotCursorPos

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

const ChangeListMaxLen* = 100

proc recordChangePosition*(b: TextBuffer, pos: BufferPosition) =
  ## Add a position to the changelist, keeping it within the max limit.
  b.changeList.add(pos)
  b.changeListIndex = b.changeList.len - 1

  if b.changeList.len > ChangeListMaxLen:
    b.changeList.delete(0)
    b.changeListIndex = b.changeList.len - 1

proc ensureMarkersSize*(b: TextBuffer) =
  ## Ensure lineMarkers array matches buffer length
  let bufferLen = b.len
  if b.lineMarkers.len < bufferLen:
    # Extend with none values
    for i in b.lineMarkers.len ..< bufferLen:
      b.lineMarkers.add(none(LineMarkerKind))
  elif b.lineMarkers.len > bufferLen:
    # Truncate
    b.lineMarkers.setLen(bufferLen)

proc ensureModifiedLinesSize*(b: TextBuffer) =
  ## Ensure modifiedLines array matches buffer length
  let bufferLen = b.len
  if b.modifiedLines.len < bufferLen:
    for i in b.modifiedLines.len ..< bufferLen:
      b.modifiedLines.add(lmkUnmodified)
  elif b.modifiedLines.len > bufferLen:
    b.modifiedLines.setLen(bufferLen)

proc captureSnapshotIfNeeded*(b: TextBuffer) {.inline.} =
  ## Capture snapshots before mutation for undo/redo.
  ## For PieceTable: captures full snapshot for O(1) undo/redo.
  ## For all backends: captures modifiedLines once per undo entry.
  if b.backendKind == PieceTable and b.pendingSnapshot.isNone:
    b.pendingSnapshot = some(b.pieceTable.takeSnapshot())
    b.pendingSnapshotMarkers = b.lineMarkers
    b.pendingSnapshotModifiedLines = b.modifiedLines
    b.pendingSnapshotFolds = b.foldState
  # Capture modifiedLines snapshot for non-PieceTable backends (once per undo entry)
  # PieceTable uses snapshotModifiedLines in ckSnapshot instead
  if b.backendKind != PieceTable and not b.hasPendingModifiedLinesSnapshot:
    b.pendingModifiedLinesSnapshot = b.modifiedLines
    b.hasPendingModifiedLinesSnapshot = true

proc discardPendingSnapshot*(b: TextBuffer) {.inline.} =
  ## Drop every pending snapshot artifact captured for a mutation that ended up
  ## not happening (e.g. backend raised after captureSnapshotIfNeeded). Symmetric
  ## inverse of captureSnapshotIfNeeded; keeps the next pushUndoChange from
  ## attaching stale data.
  b.pendingSnapshot = none(PieceTableSnapshot)
  b.pendingSnapshotMarkers.setLen(0)
  b.pendingSnapshotModifiedLines.setLen(0)
  b.pendingSnapshotFolds = initFoldState()
  b.hasPendingModifiedLinesSnapshot = false
  b.pendingModifiedLinesSnapshot.setLen(0)

proc pushUndoChange*(b: TextBuffer, change: BufferChange) =
  ## Add a change to the undo stack (or current transaction)
  ## Always increments changeSeq to mark buffer as modified

  # Clear redo stack when new change is made
  b.redoStack.clear()

  # New edit invalidates any "future" changeList entries that an earlier undo
  # left behind. Without this, g; / g, can navigate to positions that no longer
  # correspond to any undoable change.
  if b.changeList.len > 0 and b.changeListIndex < b.changeList.len - 1:
    b.changeList.setLen(b.changeListIndex + 1)

  # Snapshot changeSeq before and after this mutation so undo()/redo() can
  # restore it by direct assignment instead of inc/dec. Required for transactions
  # which collapse N inc'd changes into a single undo entry.
  let preSeq = b.changeSeq
  b.changeSeq.inc
  let postSeq = b.changeSeq

  # Mark highlight as needing update and track changed range
  b.highlightNeedsUpdate = true

  # Track the first changed line for incremental highlighting
  let changePos = getChangePosition(change)
  b.lastChangedLines = changePos.line

  # Mark the changed line as modified
  b.ensureModifiedLinesSize()
  if changePos.line >= 0 and changePos.line < b.modifiedLines.len:
    # Only upgrade to lmkModified if not already marked as inserted
    if b.modifiedLines[changePos.line] != lmkInserted:
      b.modifiedLines[changePos.line] = lmkModified

  # Record change position in changelist
  if not b.inTransaction:
    b.recordChangePosition(changePos)

  # Attach pre-mutation modifiedLines snapshot to the change
  var changeWithSnapshot = change
  changeWithSnapshot.startSeq = preSeq
  changeWithSnapshot.endSeq = postSeq
  if b.hasPendingModifiedLinesSnapshot:
    changeWithSnapshot.savedModifiedLines = b.pendingModifiedLinesSnapshot
    b.hasPendingModifiedLinesSnapshot = false

  if b.inTransaction and b.currentTransaction.isSome:
    # Add to current transaction
    var transaction = b.currentTransaction.get
    transaction.changes.add(changeWithSnapshot)
    b.currentTransaction = some(transaction)
  elif b.pendingSnapshot.isSome:
    # PieceTable: convert to O(1) snapshot undo entry
    b.undoStack.addLast(
      BufferChange(
        startSeq: preSeq,
        endSeq: postSeq,
        kind: ckSnapshot,
        snapshotData: b.pendingSnapshot.get,
        snapshotCursorPos: getChangePosition(change),
        snapshotLineMarkers: b.pendingSnapshotMarkers,
        snapshotModifiedLines: b.pendingSnapshotModifiedLines,
        snapshotFoldState: b.pendingSnapshotFolds,
      )
    )
    b.pendingSnapshot = none(PieceTableSnapshot)
    b.hasPendingModifiedLinesSnapshot = false
  else:
    # Add directly to undo stack
    b.undoStack.addLast(changeWithSnapshot)
