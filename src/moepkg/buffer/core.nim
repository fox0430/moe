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

import std/[algorithm, deques, hashes, options, tables, times, unicode]

import ../[encoding, highlight, logger, primitives]
import ../buffer_backends/[gap_buffer, sqrt_decomp, rope, piece_table]
import cow_seq, seq_delta

export cow_seq, seq_delta

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

  FoldSource* = enum
    fsManual ## Created by the user (e.g. the `zf` command)
    fsLsp ## Provided by an LSP server (textDocument/foldingRange)

  Fold* = object ## Represents a foldable region of text (vim-like manual folding)
    startLine*: int # Fold start line (0-based, inclusive)
    endLine*: int # Fold end line (0-based, inclusive)
    collapsed*: bool # Whether the fold is currently collapsed
    collapsedText*: Option[string] # Custom text to display when collapsed (from LSP)
    source*: FoldSource # Origin of this fold (manual or LSP)

  FoldState* = object ## Manages all folds in a buffer
    folds*: seq[Fold] # List of all folds (sorted by startLine, outer-first on ties)

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
      ## Pre-mutation modifiedLines snapshot for undo/redo (non-PieceTable, 1 byte per line)
    savedLineMarkers*: CowSeq[Option[LineMarkerKind]]
      ## Pre-mutation lineMarkers snapshot for undo/redo (non-PieceTable)
    startSeq*: int
      ## changeSeq value BEFORE this entry was applied. undo() restores changeSeq
      ## to this so a transaction collapsing N mutations is reverted atomically.
    endSeq*: int
      ## changeSeq value AFTER this entry was applied. redo() restores to this.
    id*: int64
      ## Monotonic identity for this undo-tree node, assigned on push and
      ## preserved across undo/redo. Used by isModified to catch changeSeq
      ## collisions (undo -> different edit re-hitting savedSeq). Inner
      ## transaction changes carry 0; only the wrapper that lands on
      ## undoStack gets an id. 0 = initial state.
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
      deleteJoinedNextLine*: bool
        ## True when the range consumed `deleteEndPos.line + 1`. Subscribers
        ## shift side arrays by `(endLine - startLine + 1)` in that case.
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
      snapshotLineMarkers*: CowSeq[Option[LineMarkerKind]]
        ## COW-shared so a long undo history of snapshots that don't touch
        ## markers references one frozen array instead of a per-edit copy.
      modifiedLinesDelta*: SeqDelta[LineModificationKind]
        ## Bidirectional per-line delta vs the pre-mutation state, so the entry
        ## keeps O(changed lines) instead of a full O(lines) copy. The piece
        ## tree restore is absolute; only this side array is delta-encoded.
      snapshotFoldState*: FoldState
      snapshotBookmarks*: seq[int]
        ## Restored wholesale like snapshotLineMarkers / snapshotFoldState;
        ## the non-snapshot line-op branches shift via adjustBookmarksFor*.

  RowColRemapEventKind* = enum
    rrekSingleLine
    rrekMultiLine
    rrekClear

  RowColRemapEvent* = object
    case kind*: RowColRemapEventKind
    of rrekSingleLine:
      row*, editCol*, colDelta*, lineRuneLenAfter*: int
    of rrekMultiLine:
      firstAffectedRow*, lastAffectedRowBefore*, lastAffectedRowAfter*: int
      preservesFirstRow*: bool
        ## True when `firstAffectedRow` keeps its identity across the edit
        ## (ckInsertText with newlines, ckDeleteRange with a surviving merged
        ## first row). Per-line-array subscribers use it to shift at
        ## `firstAffectedRow + 1`; row-reference subscribers ignore it.
    of rrekClear:
      discard

  RowColRemapCallback* = proc(b: TextBuffer, event: RowColRemapEvent) {.closure.}

  BufferTransaction* = object ## Transaction for grouping multiple changes
    changes*: seq[BufferChange]
    description*: string
    startSeq*: int # changeSeq at the start of transaction
    cursorPos*: Option[BufferPosition] # Cursor position before the transaction

  BufferStorage* = object
    ## The text backend, held by value on TextBuffer. Keeping the variant
    ## discriminant here instead of directly on TextBuffer makes a backend swap a
    ## single whole-field reassignment (`b.storage = BufferStorage(kind: …)`) that
    ## resets only the backend branch — no FieldDefect, and no whole-object rebuild
    ## that would clobber every sibling field. Embedded by value, so
    ## `b.storage.gapBuffer` costs the same as a direct field access (no extra
    ## pointer chase on the insert/delete/charAt hot path).
    case kind*: BufferBackend
    of GapBuffer:
      gapBuffer*: GapBuffer
    of SqrtDecomp:
      sqrtDecomp*: sqrt_decomp.SqrtDecomp
    of Rope:
      rope*: rope.Rope
    of PieceTable:
      pieceTable*: piece_table.PieceTable

  TextBuffer* = ref object
    id*: BufferId # Unique buffer identifier
    filePath*: Option[string]
    displayName*: Option[string]
      # Overrides the tab label when set (used for Terminal buffers, etc.).
      # Skips the `[+]` modified mark.
    readOnly*: bool
    isUtilityBuffer*: bool # Utility buffers (jumplist, log, etc.) disable decorations
    lineEnding*: LineEnding
    encoding*: CharacterEncoding
    hasBom*: bool # BOM stripped on load, re-emitted on save (UTF-8/16/32)
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

    # Pre-mutation lineMarkers snapshot (for non-PieceTable undo/redo)
    pendingLineMarkersSnapshot*: CowSeq[Option[LineMarkerKind]]
    hasPendingLineMarkersSnapshot*: bool

    # Change sequence tracking for modified flag
    changeSeq*: int # Current change sequence number
    savedSeq*: int # Sequence number when file was last saved
    nextChangeId*: int64
      ## BufferChange.id counter. Monotonic; only reload resets. First id = 1.
    savedChangeId*: int64
      ## undoStack top id at last save (0 for initial state / empty stack).
      ## isModified uses this instead of savedSeq to defeat the collision.

    contentVersion*: int
      ## Monotonic content generation. Advanced via `advanceContentVersion` on
      ## every content-changing op (including the no-undo preview mutators that
      ## bypass `changeSeq`) and never reset or rolled back, so unlike `changeSeq`
      ## (which undo restores and reload resets to 0) it uniquely identifies a
      ## buffer's content across its lifetime. Use this, not `changeSeq`, as a
      ## cache-invalidation key.

    # Transaction support
    currentTransaction*: Option[BufferTransaction]
    inTransaction*: bool

    # PieceTable snapshot support for O(1) undo/redo
    pendingSnapshot*: Option[PieceTableSnapshot]
    pendingSnapshotMarkers*: CowSeq[Option[LineMarkerKind]]
    pendingSnapshotModifiedLines*: seq[LineModificationKind]
    pendingSnapshotFolds*: FoldState
    pendingSnapshotBookmarks*: seq[int]

    # Sidebar markers (line-based markers for git diff, syntax errors, etc.)
    lineMarkers*: CowSeq[Option[LineMarkerKind]] # Each line can have at most one marker

    # Git merge conflict ranges (populated by git_conflict.scanBufferForConflicts)
    conflictBlocks*: seq[ConflictBlock]

    # Modified line tracking (session-based, cleared on save)
    modifiedLines*: seq[LineModificationKind]
      # How each line was modified since last save

    # Row/col remap subscribers. `sideArrayCallbacks` are skipped on undo/redo
    # because savedLineMarkers / savedModifiedLines restore them wholesale.
    remapCallbacks: seq[RowColRemapCallback]
    sideArrayCallbacks: seq[RowColRemapCallback]

    # Syntax highlighting
    highlight*: Highlight # Syntax highlighting for this buffer
    language*: SourceLanguage # Programming language for syntax highlighting
    highlightNeedsUpdate*: bool # Flag to track if highlight needs regeneration
    incrementalHighlight*: IncrementalHighlight # Incremental highlighting cache
    lastChangedLines*: int # First changed line for incremental highlight
    reservedWords*: seq[ReservedWord] # Reserved words to highlight (TODO, NOTE, etc.)
    maxHighlightLineLength*: int
      # Per-line tokenization cap in runes (synmaxcol). 0 = unlimited.
    uriScanParsedUpTo*: int # Last line scanned for URIs during progressive init

    # Change list (tracks positions where changes were made, like Vim's changelist)
    changeList*: seq[BufferPosition]
    changeListIndex*: int

    # Line folding state (vim-like manual folding)
    foldState*: FoldState

    # Bookmarks (sorted list of bookmarked line numbers)
    bookmarks*: seq[int]

    # LSP diagnostics (full detail for hover display)
    diagnostics*: seq[BufferDiagnostic]
    diagnosticsDirty*: bool
      ## Set by writers of `diagnostics`; cleared by `updateHighlight` after it
      ## rebuilds `highlight.diagnosticOverlay`. Lets pure-edit ticks skip the
      ## overlay rebuild when diagnostics have not changed.

    # Per-buffer EditorConfig overrides
    editorConfig*: Option[BufferEditorConfig]

    # Backend storage. Reassigning this whole field swaps the backend in place
    # (see BufferStorage); read the active kind via the `backendKind` accessor.
    storage*: BufferStorage

const AutoBackendLargeFileThreshold* = 10 * 1024 * 1024
  # 10 MB
  ## In auto-backend mode, a file at or above this size loads into PieceTable
  ## instead of GapBuffer (`chooseBackendForFile`). Crossing it is the only thing
  ## that makes a reload change the backend; the swap reassigns only
  ## `TextBuffer.storage` (see `BufferStorage`), leaving every other field
  ## untouched, so a reload's result never depends on whether the size crossed it.

var nextBufferId = 1
  ## Starts at 1 so `BufferId(0)` is reserved as a sentinel for the
  ## zero-initialized default of `state.windowDisplay.currentBufferId`. See `BufferId`.

var configuredBackend: BufferBackend = GapBuffer
var autoBackendMode: bool = false

proc `==`*(a, b: BufferId): bool {.borrow.}
proc `$`*(id: BufferId): string {.borrow.}
proc hash*(id: BufferId): Hash {.borrow.}

template backendKind*(b: TextBuffer): BufferBackend =
  ## The active backend of `b`. Reads the discriminant out of `b.storage`, so the
  ## ~26 `case b.backendKind` dispatch sites keep their spelling after the backend
  ## variant moved off TextBuffer into the embedded `storage` field.
  b.storage.kind

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

proc clampFoldsToLineCount*(state: var FoldState, lineCount: int) =
  ## Drop folds that start past the content and clamp folds that extend past it.
  ## A reload preserves folds (identity) but can shrink the buffer, which would
  ## otherwise leave a fold referencing lines that no longer exist.
  if lineCount <= 0:
    state.folds.setLen(0)
    return
  var kept: seq[Fold]
  for fold in state.folds:
    if fold.startLine >= lineCount:
      continue # entirely past the new end
    var f = fold
    if f.endLine >= lineCount:
      f.endLine = lineCount - 1
    kept.add(f)
  state.folds = kept

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

proc currentChangeId*(b: TextBuffer): int64 {.inline.} =
  ## Id of the undoStack top, or 0 for initial state (empty stack).
  if b.undoStack.len > 0: b.undoStack.peekLast.id else: 0

proc isAtSavedState*(b: TextBuffer): bool {.inline.} =
  ## Both signals must match. Id is authoritative; changeSeq compare kept as an
  ## AND so direct writes to changeSeq (test harnesses) still count as dirty.
  b.currentChangeId == b.savedChangeId and b.changeSeq == b.savedSeq

proc isModified*(b: TextBuffer): bool {.inline.} =
  ## In-flight transactions have not yet reached undoStack, so inner-change
  ## count is checked explicitly before the saved-state compare.
  if b.inTransaction and b.currentTransaction.isSome and
      b.currentTransaction.get.changes.len > 0:
    return true
  not b.isAtSavedState

proc markSaved*(b: TextBuffer) {.inline.} =
  b.savedSeq = b.changeSeq
  b.savedChangeId = b.currentChangeId
  for i in 0 ..< b.modifiedLines.len:
    b.modifiedLines[i] = lmkUnmodified

proc allocateChangeId*(b: TextBuffer): int64 {.inline.} =
  ## Preinc so 0 stays reserved for "initial state".
  b.nextChangeId.inc
  b.nextChangeId

# Core text operations
proc getTextString*(b: TextBuffer): string =
  case b.backendKind
  of GapBuffer:
    $b.storage.gapBuffer
  of SqrtDecomp:
    $b.storage.sqrtDecomp
  of Rope:
    $b.storage.rope
  of PieceTable:
    $b.storage.pieceTable

proc len*(b: TextBuffer): int =
  ## Get number of lines in buffer
  case b.backendKind
  of GapBuffer: b.storage.gapBuffer.len
  of SqrtDecomp: b.storage.sqrtDecomp.len
  of Rope: b.storage.rope.len
  of PieceTable: b.storage.pieceTable.len

proc charLen*(text: string): int =
  ## Get character length (not byte length)
  text.runeLen

proc getLine*(b: TextBuffer, lineIndex: int): string =
  case b.backendKind
  of GapBuffer:
    b.storage.gapBuffer.getLine(lineIndex)
  of SqrtDecomp:
    b.storage.sqrtDecomp.getLine(lineIndex)
  of Rope:
    b.storage.rope.getLine(lineIndex)
  of PieceTable:
    b.storage.pieceTable.getLine(lineIndex)

iterator lines*(b: TextBuffer): string =
  ## Yield every line in order with a single backend traversal.
  ## Prefer this over `for i in 0 ..< b.len: b.getLine(i)`, which is O(n log n)
  ## for tree-based backends (Rope/PieceTable).
  case b.backendKind
  of GapBuffer:
    for line in b.storage.gapBuffer.lines:
      yield line
  of SqrtDecomp:
    for line in b.storage.sqrtDecomp.lines:
      yield line
  of Rope:
    for line in b.storage.rope.lines:
      yield line
  of PieceTable:
    for line in b.storage.pieceTable.lines:
      yield line

# Forward declarations for the built-in remap callbacks, registered in
# newTextBuffer and driven by emitRowColRemapEvents below.
proc semanticRemapCallback(b: TextBuffer, event: RowColRemapEvent)
proc foldShiftCallback(b: TextBuffer, event: RowColRemapEvent)
proc bookmarkShiftCallback(b: TextBuffer, event: RowColRemapEvent)
proc lineMarkerShiftCallback(b: TextBuffer, event: RowColRemapEvent)
proc modifiedLinesShiftCallback(b: TextBuffer, event: RowColRemapEvent)

proc newBufferStorage*(backend: BufferBackend, content: sink string): BufferStorage =
  ## Build a fresh backend value of `backend` from `content` (consumed exactly
  ## once). Assigning the whole result to `TextBuffer.storage` both constructs a
  ## new buffer's backend and swaps an existing one in place — the single
  ## construction shared by `newTextBuffer` and `loadFile`.
  case backend
  of GapBuffer:
    BufferStorage(kind: GapBuffer, gapBuffer: newGapBuffer(move content))
  of SqrtDecomp:
    BufferStorage(kind: SqrtDecomp, sqrtDecomp: newSqrtDecomp(move content))
  of Rope:
    BufferStorage(kind: Rope, rope: newRope(move content))
  of PieceTable:
    BufferStorage(kind: PieceTable, pieceTable: newPieceTable(move content))

proc newTextBuffer*(
    content: sink string = "",
    filePath: Option[string] = none(string),
    backend: BufferBackend = chooseBackend(),
): TextBuffer =
  result = TextBuffer(storage: newBufferStorage(backend, move content))

  let lineCount = result.len
  result.id = genBufferId()
  result.filePath = filePath
  result.lineEnding = LF
  result.encoding = utf8
  result.endOfLine = true # Default to POSIX text file standard
  result.undoStack = initDeque[BufferChange]()
  result.redoStack = initDeque[BufferChange]()
  result.lineMarkers = initCowSeq[Option[LineMarkerKind]](lineCount)
  result.modifiedLines = newSeq[LineModificationKind](lineCount)
  result.language = SourceLanguage.langNone
  result.maxHighlightLineLength = DefaultMaxHighlightLineLength
  result.foldState = initFoldState()
  result.editorConfig = none(BufferEditorConfig)

  # Build initial plain-text highlight from the freshly constructed backend.
  var runesBuffer = newSeqOfCap[Runes](lineCount)
  for line in result.lines:
    runesBuffer.add(line.toRunes())
  result.highlight = initHighlight(runesBuffer)

  result.remapCallbacks = @[]
  result.remapCallbacks.add(semanticRemapCallback)
  result.remapCallbacks.add(foldShiftCallback)
  result.remapCallbacks.add(bookmarkShiftCallback)
  result.sideArrayCallbacks = @[]
  result.sideArrayCallbacks.add(lineMarkerShiftCallback)
  result.sideArrayCallbacks.add(modifiedLinesShiftCallback)

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

proc countNewlines(s: string): int {.inline.} =
  for c in s:
    if c == '\n':
      inc result

proc semanticRemapCallback(b: TextBuffer, event: RowColRemapEvent) =
  ## Shift the LSP semantic overlay to stay approximately in sync with edits.
  ## `semanticContentVersion` is stamped even on an empty overlay so
  ## updateHighlight's mismatch guard does not fire an unnecessary re-request.
  if b.highlight.isNil:
    return
  case event.kind
  of rrekSingleLine:
    b.highlight.semanticShiftForSingleLineEdit(
      event.row, event.editCol, event.colDelta, event.lineRuneLenAfter
    )
  of rrekMultiLine:
    b.highlight.semanticShiftForMultiLineEdit(
      event.firstAffectedRow, event.lastAffectedRowBefore, event.lastAffectedRowAfter
    )
  of rrekClear:
    b.highlight.semantic.clear()
    b.highlight.semanticContentVersion = -1
    return
  b.highlight.semanticContentVersion = b.contentVersion

template shiftRowRefsForMultiLine(
    event: RowColRemapEvent, onInsert, onDelete: untyped
) =
  ## Shared skeleton for row-referring subscribers (folds, bookmarks). Ignores
  ## `preservesFirstRow`: the shift procs use the row range directly.
  case event.kind
  of rrekSingleLine, rrekClear:
    return
  of rrekMultiLine:
    let delta = event.lastAffectedRowAfter - event.lastAffectedRowBefore
    if delta > 0:
      onInsert(event.firstAffectedRow, delta)
    elif delta < 0:
      onDelete(event.firstAffectedRow, -delta)

proc foldShiftCallback(b: TextBuffer, event: RowColRemapEvent) =
  ## Shift folds to follow their rows across line-count-changing edits.
  shiftRowRefsForMultiLine(
    event, b.foldState.adjustFoldsAfterInsert, b.foldState.adjustFoldsAfterDelete
  )

proc bookmarkShiftCallback(b: TextBuffer, event: RowColRemapEvent) =
  ## Shift bookmarks to follow their rows across line-count-changing edits.
  shiftRowRefsForMultiLine(
    event, b.adjustBookmarksForInsert, b.adjustBookmarksForDelete
  )

template shiftPerLineArray(arr: untyped, freshValue: untyped, event: RowColRemapEvent) =
  ## Shift a per-line side array to match a line-count-changing edit. When
  ## `preservesFirstRow` is set, `firstAffectedRow` keeps its slot and the
  ## insert/delete happens at `firstAffectedRow + 1`. Both branches clamp `idx`
  ## against `arr.len` so a NoUndo path that leaves the array shorter than the
  ## buffer degrades gracefully instead of raising IndexDefect.
  case event.kind
  of rrekSingleLine, rrekClear:
    return
  of rrekMultiLine:
    let delta = event.lastAffectedRowAfter - event.lastAffectedRowBefore
    let idx =
      if event.preservesFirstRow:
        event.firstAffectedRow + 1
      else:
        event.firstAffectedRow
    if idx < 0 or idx > arr.len:
      logDebug(
        "buffer",
        "shiftPerLineArray clamp: " & astToStr(arr) & " idx=" & $idx & " len=" & $arr.len,
      )
      return
    if delta > 0:
      for _ in 0 ..< delta:
        arr.insert(freshValue, idx)
    elif delta < 0:
      let removable = min(-delta, arr.len - idx)
      for _ in 0 ..< removable:
        arr.delete(idx)

proc lineMarkerShiftCallback(b: TextBuffer, event: RowColRemapEvent) =
  ## Shift per-line markers to follow their row across insert/delete edits.
  shiftPerLineArray(b.lineMarkers, none(LineMarkerKind), event)

proc modifiedLinesShiftCallback(b: TextBuffer, event: RowColRemapEvent) =
  ## Twin of lineMarkerShiftCallback. New slots default to `lmkInserted` so
  ## pushUndoChange's "mark changePos as modified" step sees the right state.
  shiftPerLineArray(b.modifiedLines, lmkInserted, event)

proc reversed(event: RowColRemapEvent): RowColRemapEvent =
  ## Flip a forward event into its inverse. `lineRuneLenAfter` is preserved:
  ## emitRowColRemapEvents recomputes it via `getLine` at reverse dispatch time
  ## (after the backend undo), so it already matches the post-reverse state.
  case event.kind
  of rrekMultiLine:
    RowColRemapEvent(
      kind: rrekMultiLine,
      firstAffectedRow: event.firstAffectedRow,
      lastAffectedRowBefore: event.lastAffectedRowAfter,
      lastAffectedRowAfter: event.lastAffectedRowBefore,
      preservesFirstRow: event.preservesFirstRow,
    )
  of rrekSingleLine:
    RowColRemapEvent(
      kind: rrekSingleLine,
      row: event.row,
      editCol: event.editCol,
      colDelta: -event.colDelta,
      lineRuneLenAfter: event.lineRuneLenAfter,
    )
  of rrekClear:
    event

proc emitRowColRemapEvents*(
    b: TextBuffer,
    change: BufferChange,
    reverse: bool = false,
    includeSideArrays: bool = true,
) =
  ## Notify subscribers of a buffer edit so they can keep row/col-keyed
  ## decorations in sync. `reverse=true` flips the event for undo dispatch;
  ## `includeSideArrays=false` skips lineMarkers/modifiedLines when a wholesale
  ## restore will overwrite them anyway (undo/redo path).
  template dispatch(ev: RowColRemapEvent) =
    # Each callback is isolated: one raising must not skip later shifts,
    # otherwise side arrays drift silently against the backend. Errors are
    # logged so drift is diagnosable instead of invisible.
    let toFire =
      if reverse:
        reversed(ev)
      else:
        ev
    for cb in b.remapCallbacks:
      try:
        cb(b, toFire)
      except CatchableError as e:
        logError("buffer", "remapCallback raised: " & e.msg)
    if includeSideArrays:
      for cb in b.sideArrayCallbacks:
        try:
          cb(b, toFire)
        except CatchableError as e:
          logError("buffer", "sideArrayCallback raised: " & e.msg)

  case change.kind
  of ckTransaction:
    if reverse:
      for j in countdown(change.transactionChanges.high, 0):
        b.emitRowColRemapEvents(
          change.transactionChanges[j],
          reverse = true,
          includeSideArrays = includeSideArrays,
        )
    else:
      for inner in change.transactionChanges:
        b.emitRowColRemapEvents(inner, includeSideArrays = includeSideArrays)
    return
  of ckSnapshot:
    dispatch(RowColRemapEvent(kind: rrekClear))
    return
  of ckInsertText:
    let nl = countNewlines(change.insertText)
    if nl == 0:
      let colDelta = change.insertText.runeLen
      let newLen = b.getLine(change.insertPos.line).charLen
      dispatch(
        RowColRemapEvent(
          kind: rrekSingleLine,
          row: change.insertPos.line,
          editCol: change.insertPos.column,
          colDelta: colDelta,
          lineRuneLenAfter: newLen,
        )
      )
    else:
      dispatch(
        RowColRemapEvent(
          kind: rrekMultiLine,
          firstAffectedRow: change.insertPos.line,
          lastAffectedRowBefore: change.insertPos.line,
          lastAffectedRowAfter: change.insertPos.line + nl,
          preservesFirstRow: true,
        )
      )
  of ckDeleteText:
    let nl = countNewlines(change.deletedText)
    if nl == 0:
      let colDelta = -change.deletedText.runeLen
      let newLen = b.getLine(change.deletePos.line).charLen
      dispatch(
        RowColRemapEvent(
          kind: rrekSingleLine,
          row: change.deletePos.line,
          editCol: change.deletePos.column,
          colDelta: colDelta,
          lineRuneLenAfter: newLen,
        )
      )
    else:
      dispatch(
        RowColRemapEvent(
          kind: rrekMultiLine,
          firstAffectedRow: change.deletePos.line,
          lastAffectedRowBefore: change.deletePos.line + nl,
          lastAffectedRowAfter: change.deletePos.line,
          preservesFirstRow: true,
        )
      )
  of ckInsertLine:
    dispatch(
      RowColRemapEvent(
        kind: rrekMultiLine,
        firstAffectedRow: change.insertLineIdx,
        lastAffectedRowBefore: change.insertLineIdx - 1,
        lastAffectedRowAfter: change.insertLineIdx,
      )
    )
  of ckDeleteLine:
    dispatch(
      RowColRemapEvent(
        kind: rrekMultiLine,
        firstAffectedRow: change.deleteLineIdx,
        lastAffectedRowBefore: change.deleteLineIdx,
        lastAffectedRowAfter: change.deleteLineIdx - 1,
      )
    )
  of ckDeleteRange:
    # Single-line-join: emit as a drop of `startLine + 1` alone, so
    # folds/bookmarks/markers at startLine survive (semantic tokens on that
    # line go stale until the LSP repaints — self-healing).
    # Other paths: startLine's row identity survives with merged content, so
    # `preservesFirstRow=true` and drops happen at startLine + 1..
    let startLine = change.deleteStartPos.line
    let endLine = change.deleteEndPos.line
    let event =
      if startLine == endLine and change.deleteJoinedNextLine:
        RowColRemapEvent(
          kind: rrekMultiLine,
          firstAffectedRow: startLine + 1,
          lastAffectedRowBefore: startLine + 1,
          lastAffectedRowAfter: startLine,
        )
      else:
        let lastBefore = endLine + (if change.deleteJoinedNextLine: 1 else: 0)
        RowColRemapEvent(
          kind: rrekMultiLine,
          firstAffectedRow: startLine,
          lastAffectedRowBefore: lastBefore,
          lastAffectedRowAfter: startLine,
          preservesFirstRow: true,
        )
    dispatch(event)
  of ckReplaceLine:
    dispatch(
      RowColRemapEvent(
        kind: rrekMultiLine,
        firstAffectedRow: change.replaceLineIdx,
        lastAffectedRowBefore: change.replaceLineIdx,
        lastAffectedRowAfter: change.replaceLineIdx,
      )
    )

proc registerRowColRemapCallback*(b: TextBuffer, cb: RowColRemapCallback) =
  ## Register a callback to receive row/col remap events. All registered
  ## callbacks are invoked on every forward edit, before the frame repaints.
  b.remapCallbacks.add(cb)

# Memory usage monitoring
proc estimateMemoryUsage*(buffer: TextBuffer): int =
  result = sizeof(TextBuffer)

  case buffer.backendKind
  of GapBuffer:
    result += buffer.storage.gapBuffer.estimateMemoryUsage()
  of SqrtDecomp:
    result += buffer.storage.sqrtDecomp.estimateMemoryUsage()
  of Rope:
    result += buffer.storage.rope.estimateMemoryUsage()
  of PieceTable:
    result += buffer.storage.pieceTable.estimateMemoryUsage()

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
  ## Ensure lineMarkers length matches buffer length; grown slots default to none.
  ## One setLen clones a frozen/shared node at most once (vs an add-loop that also
  ## reallocates per element).
  if b.lineMarkers.len != b.len:
    b.lineMarkers.setLen(b.len)

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
    b.pendingSnapshot = some(b.storage.pieceTable.takeSnapshot())
    # COW-share markers: snapshots that don't touch lineMarkers reference one
    # frozen array (O(1)). A line-count-changing edit resizes lineMarkers right
    # after this and clones once; same-line edits never clone.
    b.pendingSnapshotMarkers = b.lineMarkers
    b.pendingSnapshotModifiedLines = b.modifiedLines
    b.pendingSnapshotFolds = b.foldState
    b.pendingSnapshotBookmarks = b.bookmarks
  # Capture modifiedLines snapshot for non-PieceTable backends (once per undo entry).
  # PieceTable diffs pendingSnapshotModifiedLines into a ckSnapshot delta instead.
  if b.backendKind != PieceTable and not b.hasPendingModifiedLinesSnapshot:
    b.pendingModifiedLinesSnapshot = b.modifiedLines
    b.hasPendingModifiedLinesSnapshot = true
  if b.backendKind != PieceTable and not b.hasPendingLineMarkersSnapshot:
    b.pendingLineMarkersSnapshot = b.lineMarkers
    b.hasPendingLineMarkersSnapshot = true

proc discardPendingSnapshot*(b: TextBuffer) {.inline.} =
  ## Drop every pending snapshot artifact captured for a mutation that ended up
  ## not happening (e.g. backend raised after captureSnapshotIfNeeded). Symmetric
  ## inverse of captureSnapshotIfNeeded; keeps the next pushUndoChange from
  ## attaching stale data.
  b.pendingSnapshot = none(PieceTableSnapshot)
  b.pendingSnapshotMarkers.clear()
  b.pendingSnapshotModifiedLines.setLen(0)
  b.pendingSnapshotFolds = initFoldState()
  b.pendingSnapshotBookmarks.setLen(0)
  b.hasPendingModifiedLinesSnapshot = false
  b.pendingModifiedLinesSnapshot.setLen(0)
  b.hasPendingLineMarkersSnapshot = false
  b.pendingLineMarkersSnapshot.clear()

proc clearUndoRedoState*(b: TextBuffer) =
  ## Drop all undo/redo history, the in-flight transaction and any pending
  ## snapshot. A reload replaces the content wholesale, so every recorded change
  ## (and the positions it stores) is invalid against the new content; loadFile
  ## calls this on its single reload path regardless of the backend swap.
  b.undoStack.clear()
  b.redoStack.clear()
  b.inTransaction = false
  b.currentTransaction = none(BufferTransaction)
  b.discardPendingSnapshot()
  # Reset id state too so post-reload isModified starts clean (0 == 0).
  b.nextChangeId = 0
  b.savedChangeId = 0

proc advanceContentVersion*(b: TextBuffer) {.inline.} =
  ## Advance the monotonic content version. Call from EVERY content-mutating
  ## path: alongside each `changeSeq` write, and from the no-undo preview
  ## mutators that bypass `changeSeq`. It only ever increases, so it stays a
  ## safe cache-invalidation key. See the `contentVersion` field doc.
  b.contentVersion.inc

proc markLineChanged*(b: TextBuffer, line: int) =
  ## Merge `line` into the pending incremental-highlight re-parse anchor.
  ## While an update is pending (not yet consumed by updateHighlight), keep
  ## the minimum so a later change further down cannot move the anchor past
  ## an earlier change higher up, leaving it stale-highlighted.
  if b.highlightNeedsUpdate:
    b.lastChangedLines = min(b.lastChangedLines, line)
  else:
    b.lastChangedLines = line
    b.highlightNeedsUpdate = true

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
  b.advanceContentVersion()
  let postSeq = b.changeSeq

  # Shift the semantic overlay to match the new content BEFORE the frame
  # reaches updateHighlight; without this the version bump above would trip
  # updateHighlight's mismatch guard and wipe the overlay every keystroke.
  b.emitRowColRemapEvents(change)

  # Mark highlight as needing update and track the first changed line for
  # incremental highlighting
  let changePos = getChangePosition(change)
  b.markLineChanged(changePos.line)

  # Mark the changed line as modified
  b.ensureMarkersSize()
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
  if b.hasPendingLineMarkersSnapshot:
    changeWithSnapshot.savedLineMarkers = b.pendingLineMarkersSnapshot
    b.hasPendingLineMarkersSnapshot = false

  if b.inTransaction and b.currentTransaction.isSome:
    # Inner changes carry id 0; the wrapper committed later gets the id.
    var transaction = b.currentTransaction.get
    transaction.changes.add(changeWithSnapshot)
    b.currentTransaction = some(transaction)
  elif b.pendingSnapshot.isSome:
    # PieceTable: convert to O(1) snapshot undo entry
    b.undoStack.addLast(
      BufferChange(
        startSeq: preSeq,
        endSeq: postSeq,
        id: b.allocateChangeId(),
        kind: ckSnapshot,
        snapshotData: b.pendingSnapshot.get,
        snapshotCursorPos: getChangePosition(change),
        snapshotLineMarkers: b.pendingSnapshotMarkers,
        modifiedLinesDelta:
          computeDelta(b.pendingSnapshotModifiedLines, b.modifiedLines),
        snapshotFoldState: b.pendingSnapshotFolds,
        snapshotBookmarks: b.pendingSnapshotBookmarks,
      )
    )
    # Pending snapshot state is now consumed into the entry; reset it all.
    b.discardPendingSnapshot()
  else:
    # Add directly to undo stack
    changeWithSnapshot.id = b.allocateChangeId()
    b.undoStack.addLast(changeWithSnapshot)
