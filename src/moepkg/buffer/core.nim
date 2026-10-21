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

from std/strutils import contains, endsWith, find, startsWith

import std/[algorithm, deques, hashes, options, os, tables, times, unicode]

import
  ../[encoding, highlight, logger, path_key, primitives, setting_issue, unicode_utils]
import ../types/highlight_types
when defined(moe.matter) or defined(features.moe.matter):
  import ../syntax/matter_backend
import ../buffer_backends/[gap_buffer, sqrt_decomp, rope, piece_table]
import cow_seq, seq_delta, span_edit

export cow_seq, seq_delta, span_edit

export
  CharacterEncoding, encodingToString, detectCharacterEncoding, BufferPosition,
  ColumnRange, VisualSelectionKind

# `BufferNotice` carries a `SettingIssue`, so notice readers need it too.
export SettingIssue, SettingIssueKind, toMessage, sameSetting

# The character model buffer columns are indexed with. Exported so
# `line.charLen` and `line.charSubStr` resolve through the same import.
export runeSizeAt, charLen, charSubStr, charToBytePos, byteToCharPos
export mayAbsorbAtSeam

type
  BufferId* = distinct int
    ## Unique identifier for a TextBuffer.
    ## Stable for the lifetime of a process (not persisted across restarts).
    ## `BufferId(0)` is reserved as the "unassigned" sentinel — `genBufferId`
    ## starts handing out ids from 1 so that the zero-initialized default of
    ## `state.windowDisplay.currentBufferId` can't accidentally collide with a real buffer.

  UnusualContentKind* = enum
    ## Content kind for warning control; kind change triggers re-warning.
    ucOrdinary ## Decoded cleanly and holds no NUL bytes
    ucBinary ## Decoded, but holds NUL bytes near the start
    ucRaw ## No encoding could decode it; bytes kept verbatim
    ucRawBinary ## Undecodable and holding NUL bytes

  BufferNoticeKind* = enum
    ## What a notice is about.
    bnContent ## What moe did with bytes it could not treat as ordinary text
    bnSetting ## A `.editorconfig` value moe did not apply

  BufferNotice* = object
    ## Something the user should hear about a buffer. Holds the facts only;
    ## the wording belongs to whoever reports it.
    case kind*: BufferNoticeKind
    of bnContent:
      content*: UnusualContentKind
    of bnSetting:
      issue*: SettingIssue

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

  DiagnosticSource* = enum
    dsrcLsp ## The language server's publish
    dsrcSyntaxCheck ## The syntax checker run on save

  DiagnosticReport* = object ## One source's latest diagnostics, in start order.
    items*: seq[BufferDiagnostic]
    owner*: string ## Who made the report, such as the language server's id

  BufferDiagnostics* = array[DiagnosticSource, DiagnosticReport]

  AwaitedReport = object ## Edits since the text an in-flight report was made from.
    id: int ## 0 when none is awaited
    edits: seq[SpanEdit]

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
    ckReplaceLines # A span of lines swapped for another, as one change
    ckTransaction # Transaction containing multiple changes
    ckSnapshot # PieceTable O(1) snapshot undo/redo

  NamedMarks* = array['a' .. 'z', Option[BufferPosition]]

  NamedMarkChange* = object
    ## Sparse before/after state for one mark changed by a buffer edit.
    name*: char
    before*, after*: Option[BufferPosition]

  VisualArea* = object
    ## The last Visual selection, for `gv`. Like Vim's it follows lines
    ## inserted and deleted around it but keeps its columns.
    start*: BufferPosition ## The anchor
    cursor*: BufferPosition ## The end the cursor was on
    kind*: VisualSelectionKind
    wantedColumn*: int = -1
      ## The column vertical moves aimed for, as Vim's vi_curswant, or -1 for
      ## the cursor's. `LineEnd` keeps a block following each line's end.

  OpenLine* = enum
    ## How a multi-line insert meets its line; decides rows saved for undo, as
    ## in Vim.
    olNone ## It breaks that line or goes into it
    olBelow ## Whole lines opened below that line, which stays as it was: `o`, `p`
    olAbove ## Whole lines opened above it: `O`, `P`

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
    namedMarkChanges*: seq[NamedMarkChange]
    noChangeListPosition*: bool
      ## Skip `changeListIndex` on undo/redo: this entry recorded no position.
    isReload*: bool ## This entry is a reload that landed as an edit.
    changeListAcross*: Option[seq[BufferPosition]]
      ## `changeList` on the other side of this entry. A reload remaps the
      ## recorded positions; undo/redo swap this with the live list.
    changeListIndexAcross*: int
      ## Index for `changeListAcross`. Swapped with the list: an edit after
      ## this entry can evict the oldest position, so the two can differ in
      ## length.
    reloadChargeLines*: int
      ## Lines this entry holds against the undoable-reload budget, refunded
      ## when it leaves history. Non-zero only for a reload.
    reloadChargeBytes*: int ## Bytes this entry holds against the undoable-reload budget.
    visualAcross*: ref VisualArea
      ## `lastVisual` on the other side of this entry, nil for none; undo/redo
      ## swap the two as Vim does, so undoing an edit restores the area it was
      ## made with. Boxed because inner transaction changes never set it.
    case kind*: BufferChangeKind
    of ckInsertText:
      insertPos*: BufferPosition
      insertText*: string
      insertColDelta*: int
        ## Columns the line gained, recorded at edit time where the line before
        ## the insertion is in hand: a lead byte completed over the insertion
        ## cannot be re-derived from `insertText` alone. 0 for a multi-line
        ## insert, where subscribers move whole rows instead.
      insertByteOffset*: int
        ## Byte in the line the text was written at; after the insertion,
        ## walking `insertPos.column` characters no longer lands on it.
      insertSplitTailLen*: int
        ## Characters after `insertPos.column`, recorded at edit time: the
        ## mutated buffer cannot tell them from the inserted text.
      insertOpenLine*: OpenLine
    of ckDeleteText:
      deletePos*: BufferPosition
      deletedText*: string
      deleteColDelta*: int
        ## Columns the line lost, recorded at edit time where both the line
        ## before and after the deletion are in hand; `deletedText` alone
        ## cannot account for a lead byte that completed over the hole.
      deleteByteOffset*: int
        ## Byte in the line the text was removed from, recorded because the
        ## merged line may count its columns differently.
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
      deleteRangeByteOffset*: int
        ## Byte on `deleteStartPos.line` the range started at, recorded like
        ## `deleteByteOffset`: the deletion can change how columns count.
      deleteRangeColDelta*: int
        ## Columns lost by an intra-line deletion. Zero for multi-line ranges.
    of ckReplaceLine:
      replaceLineIdx*: int
      replaceLineOldText*: string
      replaceLineNewText*: string
    of ckReplaceLines:
      replaceLinesIdx*: int
      replaceLinesColumn*: int ## Where the rewrite starts on its first line
      replaceLinesOldText*: seq[string]
      replaceLinesNewText*: seq[string]
      replaceLinesKeepRows*: bool
        ## True when the rows both sides share keep their identity, so what is
        ## attached to them stays; false gives the old rows up with it.
      replaceLinesSavedFolds*: FoldState
        ## Folds as they stood before the span was rewritten. A row that leaves
        ## takes its folds with it and the reversed events only put blank rows
        ## back, so undo restores these wholesale.
      replaceLinesSavedBookmarks*: seq[int]
        ## Bookmarks before the rewrite; same reason as the folds above.
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
      snapshotEdits*: CowSeq[SpanEdit]
        ## Replaced text, in order, for diagnostics and `lastVisual` to follow
        ## across undo and redo. Shared with the inverse entry.
      snapshotRows*: CowSeq[RowSpan]
        ## Rows each change rewrote, in order, for `lastVisual`. Shared like
        ## `snapshotEdits`.

  InsertOutcome* = object ## What an insertion did to the line it landed on.
    insertEnd*: BufferPosition ## Just past everything that was written.
    cursor*: BufferPosition ## Where a cursor following the insertion belongs.
    colDelta*: int ## Columns the line gained (0 for a multi-line insert).
    byteOffset*: int ## Byte in the line the text was written at.

  EditFollower* = enum
    ## What sits on the text and follows it across edits.
    efSemantic ## The language server's semantic token overlay
    efFolds
    efBookmarks
    efNamedMarks
    efLastVisual
    efLineArrays ## `lineMarkers` and `modifiedLines`
    efDiagnostics
    efJumps ## The editor's jump list, through `rowsMovedHook`

  BufferFileReadHook* = proc(b: TextBuffer) {.closure.}
    ## Called whenever `lastLoadedContent` is taken from the file: the buffer
    ## just read it, or wrote it.

  BufferRowsMovedHook* = proc(b: TextBuffer, move: RowMove) {.closure, raises: [].}
    ## Called whenever an edit or undo/redo moves rows, so positions kept
    ## outside the buffer follow its text.

  BufferContentReplacedHook* = proc(b: TextBuffer) {.closure.}
    ## Called once whenever the buffer's contents are replaced wholesale from
    ## disk. Unlike the row/col remap stream, which describes edits, a
    ## replacement invalidates positions rather than remapping them.

  ContentFingerprint* = object
    ## Identity of the exact bytes last read from, or written to, the file.
    ## The size travels with the hash so a collision cannot pass as a match.
    size*: int
    hash*: Hash

  FileObservation* = enum
    ## Path lookup result. Only `fileObservedAbsent` treats a later file as a change.
    fileNeverObserved ## Never looked, or the look failed.
    fileObservedAbsent ## Looked, and nothing was there.
    fileObservedPresent ## Looked, and this is what was there.

  FileStamp* = object
    ## On-disk identity at one instant. A load stamps this before reading.
    case observed*: FileObservation
    of fileObservedPresent:
      modTime*: Time
      size*: int64 ## Same stat as `modTime`; catches sub-timestamp rewrites.
      dev*: uint64 ## With `ino`, a replacement that reuses mtime/size still differs.
      ino*: uint64 ## Zero when unresolvable; such stamps only match on the stat halves.
    else:
      discard

  DiskChange* = enum
    ## How the file at a buffer's path compares with its baseline.
    diskUnknown ## No usable baseline, or the file cannot be checked now.
    diskUnchanged
    diskChanged ## Present both times, but no longer the same file.
    diskAppeared ## Absent at baseline; something is there now.
    diskVanished ## Present at baseline; gone now.

  WriteRefusal* = enum
    ## Why a write to a path is refused.
    writeAllowed
    writeRefusedChangedOnDisk ## The file changed since the buffer read it.
    writeRefusedUnreadFile ## Own file, but nothing here has read it.
    writeRefusedUnverifiedFile
      ## Own file with content on disk that could not be checked.
    writeRefusedHeldByAnotherBuffer ## Another buffer in this session holds the file.
    writeRefusedTargetExists ## Another path, and a file is already there.

  BufferTransaction* = object ## Transaction for grouping multiple changes
    changes*: seq[BufferChange]
    description*: string
    startSeq*: int # changeSeq at the start of transaction
    cursorPos*: Option[BufferPosition] # Cursor position before the transaction
    namedMarksBefore*: NamedMarks
    lastVisualBefore*: Option[VisualArea]

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
    matchAliases*: seq[string] = @[]
      # Stable `:b` keys (e.g. a Terminal's command), independent of the
      # display label. Presentation must never define these.
    readOnly*: bool
    isUtilityBuffer*: bool
      # Rendered listings (filer, file tree, recent files): no decorations, and
      # never read or written as the file at `filePath`.
    lineEnding*: LineEnding
    encoding*: CharacterEncoding
    hasBom*: bool # BOM stripped on load, re-emitted on save (UTF-8/16/32)
    hasBinaryContent*: bool
      ## A NUL byte was found near the start of the file on load. The bytes
      ## are kept and saved back verbatim, but line-oriented editing will not
      ## do what the user expects, so the open is announced.
    endOfLine*: bool # Whether file should end with newline
    keepRaw*: bool
      ## Raw bytes no reading accepted (bad UTF-8, or a refused UTF-16/32
      ## decode); no transforms allowed. Volatile; re-derived on every load.
    fileBaseline*: FileStamp
      ## File state at last read/write; compared against a fresh lookup.
    lastLoadedContent*: Option[ContentFingerprint]
      ## Fingerprint of the bytes the buffer was last built from or saved as.
      ## `none` reads as "assume the file differs".
    externalModWarned*: bool
      ## Whether the reload watcher already reported the change (reset on load/save).
    autoSaveSkipWarned*: bool
      ## Whether auto save already reported skipping this buffer (reset on load/save).
    reloadDeferred*: bool
      ## An external change was detected while an edit group was open. The
      ## reload runs as soon as the group closes, not at the next poll.
    pendingNotices*: seq[BufferNotice]
      ## Not yet reported to the user. Filled where the fact appears, drained
      ## when a window first shows the buffer.
    settingIssues*: seq[SettingIssue]
      ## `.editorconfig` issues as of the last apply, to tell a new issue from
      ## an already reported one.
    reportedContentKind*: UnusualContentKind
      ## Content kind already queued (`ucOrdinary` = none). Re-queued when the
      ## kind changes.

    # Undo/Redo stacks (using Deque for O(1) operations at both ends)
    undoStack*: Deque[BufferChange]
    redoStack*: Deque[BufferChange]
    reloadUndoLines*: int
      ## Lines charged by reload undo entries since the history was last
      ## dropped (replaced + inserted). History is unbounded, so reloads have
      ## a budget of their own.
    reloadUndoBytes*: int
      ## Byte counterpart of `reloadUndoLines`, for files of a few very long
      ## lines.

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
      ## BufferChange.id counter. Never reset, so an id names one change for
      ## the buffer's whole life. First id = 1.
    historyResets*: int
      ## Times a wholesale load dropped the undo history. Tells a change-less
      ## state before one from the same state after.
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
    pendingSnapshotNamedMarks*: NamedMarks
    pendingSnapshotBookmarks*: seq[int]
    pendingSnapshotEdits*: seq[SpanEdit] ## Replaced text since the snapshot
    pendingSnapshotRows*: seq[RowSpan] ## Rewritten rows since the snapshot

    # Sidebar markers for git diff and conflicts
    lineMarkers*: CowSeq[Option[LineMarkerKind]]

    # Git merge conflict ranges (populated by git_conflict.scanBufferForConflicts)
    conflictBlocks*: seq[ConflictBlock]

    # Modified line tracking (session-based, cleared on save)
    modifiedLines*: seq[LineModificationKind]
      # How each line was modified since last save

    # Wholesale content replacement subscriber. A single slot, so registering
    # the buffer twice cannot accumulate duplicates.
    contentReplacedHook: BufferContentReplacedHook
    fileReadHook: BufferFileReadHook ## A single slot, like the one above.
    rowsMovedHook: BufferRowsMovedHook ## A single slot, like the one above.

    # Syntax highlighting
    highlight*: Highlight # Syntax highlighting for this buffer
    language*: SourceLanguage # Programming language for syntax highlighting
    highlightNeedsUpdate*: bool # Flag to track if highlight needs regeneration
    incrementalHighlight*: IncrementalHighlight # Incremental highlighting cache
    lastChangedLines*: int # First changed line for incremental highlight
    reservedWords*: seq[ReservedWord] # Reserved words to highlight (TODO, NOTE, etc.)
    maxHighlightLineLength*: int
      # Per-line tokenization cap in runes (synmaxcol). 0 = unlimited.
    highlightBackend*: HighlightBackend
      ## Requested syntax backend; unavailable optional backends fall back safely.
    when defined(moe.matter) or defined(features.moe.matter):
      matterGrammarSet*: MatterGrammarSet
        ## Explicit grammar collection shared with other buffers in the editor.
    uriScanParsedUpTo*: int # Last line scanned for URIs during progressive init

    # Change list (tracks positions where changes were made, like Vim's changelist)
    changeList*: seq[BufferPosition]
    changeListIndex*: int

    # Line folding state (vim-like manual folding)
    foldState*: FoldState

    # Bookmarks (sorted list of bookmarked line numbers)
    bookmarks*: seq[int]
    namedMarks*: NamedMarks
    lastVisual*: Option[VisualArea] ## Reselected by `gv`

    diagnostics*: BufferDiagnostics
    awaitedReports: array[DiagnosticSource, AwaitedReport]
    diagnosticsDirty*: bool
      ## Set when LSP diagnostics change or move; cleared by `updateHighlight`
      ## after rebuilding the overlay. Lets other ticks skip the rebuild.

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

proc allowsTextTransforms*(b: TextBuffer): bool =
  ## Whether text transforms are safe. False for raw buffers.
  ## Use this instead of checking `keepRaw` directly.
  not b.keepRaw

proc unusualContentKind*(b: TextBuffer): UnusualContentKind =
  ## Content kind of `b` derived from load result.
  if b.allowsTextTransforms:
    if b.hasBinaryContent: ucBinary else: ucOrdinary
  else:
    if b.hasBinaryContent: ucRawBinary else: ucRaw

proc presentStamp*(
    modTime: Time, size: int64, dev: uint64 = 0, ino: uint64 = 0
): FileStamp =
  ## Stamp for a present file. Entity defaults to unknown for time-only test baselines.
  FileStamp(
    observed: fileObservedPresent, modTime: modTime, size: size, dev: dev, ino: ino
  )

proc `==`*(a, b: FileStamp): bool =
  ## Structural equality for a case object. Present stamps include the entity.
  if a.observed != b.observed:
    return false
  if a.observed == fileObservedPresent:
    return
      a.modTime == b.modTime and a.size == b.size and a.dev == b.dev and a.ino == b.ino
  true

proc `==`*(a, b: BufferNotice): bool =
  ## Structural equality. Nim's generic `==` cannot compare a case object.
  if a.kind != b.kind:
    return false
  case a.kind
  of bnContent:
    a.content == b.content
  of bnSetting:
    a.issue == b.issue

proc noteContent*(b: TextBuffer) =
  ## Queue what `b` did with content that is not ordinary text, unless the
  ## same kind was already reported.
  let kind = b.unusualContentKind
  if kind == b.reportedContentKind:
    return
  # Recorded even for ordinary content, so a file broken again is reported again.
  b.reportedContentKind = kind
  if kind != ucOrdinary:
    b.pendingNotices.add BufferNotice(kind: bnContent, content: kind)

proc noteSettingIssues*(b: TextBuffer, issues: seq[SettingIssue]) =
  ## Queue the `.editorconfig` issues that are new since the last apply, so
  ## that re-applying the same file on an auto-reload says nothing.
  for issue in issues:
    var known = false
    for old in b.settingIssues:
      if old.sameSetting(issue):
        known = true
        break
    if not known:
      # `settingIssues` is reset when editorconfig is off or unreadable, so
      # check what is still queued too.
      for pending in b.pendingNotices:
        if pending.kind == bnSetting and pending.issue.sameSetting(issue):
          known = true
          break
    if not known:
      b.pendingNotices.add BufferNotice(kind: bnSetting, issue: issue)
  b.settingIssues = issues

proc takeNotices*(b: TextBuffer): seq[BufferNotice] =
  ## Take the pending notices, clearing them.
  result = b.pendingNotices
  b.pendingNotices = @[]

proc clearNotices*(b: TextBuffer) =
  ## Drop pending and already reported notices, for a buffer taking on a
  ## different file.
  b.pendingNotices = @[]
  b.settingIssues = @[]
  b.reportedContentKind = ucOrdinary

proc rawBytesRejection*(action: string): string =
  ## Rejection message for `action` on a raw buffer.
  "Cannot " & action & ": buffer holds raw undecodable bytes"

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

proc holdsChange*(b: TextBuffer, id: int64): bool =
  ## Whether change `id` is applied: still on the undo stack, so neither undone
  ## nor dropped by a wholesale load. Ids only grow up the stack, so this is a
  ## search.
  if id <= 0:
    return false
  var
    lo = 0
    hi = b.undoStack.len - 1
  while lo <= hi:
    let mid = (lo + hi) div 2
    let at = b.undoStack[mid].id
    if at == id:
      return true
    if at < id:
      lo = mid + 1
    else:
      hi = mid - 1
  false

proc reloadedSince*(b: TextBuffer, id: int64): bool =
  ## Whether a reload that landed as an edit sits applied above change `id`
  ## (0: above the start of history).
  for i in countdown(b.undoStack.len - 1, 0):
    if b.undoStack[i].id <= id:
      return false
    if b.undoStack[i].isReload:
      return true
  false

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

proc displayLabel*(
    displayName, filePath: Option[string], baseNameOnly = false
): string =
  ## Display-label priority: displayName > filePath > "No Name". Raw; the
  ## display boundary sanitizes. `baseNameOnly` keeps only the last path
  ## component. The one definition every label surface goes through.
  if displayName.isSome:
    displayName.get
  elif filePath.isSome:
    if baseNameOnly: filePath.get.extractFilename else: filePath.get
  else:
    "No Name"

proc canonicalLabel*(b: TextBuffer, baseNameOnly = false): string {.inline.} =
  ## Full display label for `b`. See `displayLabel` for the priority.
  displayLabel(b.displayName, b.filePath, baseNameOnly)

type BufferMatchAttempt* = enum
  ## How `:b` compares an argument with a buffer's names, strictest first. Each
  ## looser attempt holds every buffer a stricter one does, so taking the first
  ## attempt that leaves a single buffer picks what Vim's `buflist_findpat`
  ## (loosest first, stop on a single match) does.
  bmaWhole
  bmaPrefix
  bmaSuffix
  bmaSubstring

proc fileMatchNames*(b: TextBuffer, cwd: string): seq[string] =
  ## The file names `:b` matches: the path relative to `cwd` when it lies under
  ## it (Vim's short name) or else the filename, the path as stored, and the
  ## full path. Session names are `matchAliases`; the display label is never a
  ## key, so relabelling cannot change what `:b` takes.
  if b.filePath.isNone:
    return @[]
  let
    stored = b.filePath.get
    full = pathKey(stored)
    base =
      if cwd.len == 0 or cwd.endsWith(DirSep):
        cwd
      else:
        cwd & DirSep
  if base.len > 0 and full.startsWith(base) and full.len > base.len:
    result.add full[base.len .. ^1]
  else:
    result.add full.extractFilename
  for name in [stored, full]:
    if name notin result:
      result.add name

proc matchesAt*(
    names: openArray[string], arg: string, attempt: BufferMatchAttempt
): bool =
  if arg.len == 0:
    return false
  for name in names:
    let hit =
      case attempt
      of bmaSubstring:
        name.contains(arg)
      of bmaPrefix:
        name.startsWith(arg)
      of bmaSuffix:
        name.endsWith(arg)
      of bmaWhole:
        name == arg
    if hit:
      return true
  false

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
  # Lines are handed over as strings: `initHighlight` counts columns with
  # `charLen`, the same rule the renderer steps cells with.
  var initialLines = newSeqOfCap[string](lineCount)
  for line in result.lines:
    initialLines.add(line)
  result.highlight = initHighlight(initialLines)

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

proc isSpaceOrBreak*(r: Rune): bool =
  ## A space, a tab or a line break, which ends a word.
  let c = r.int32
  c == ' '.ord or c == '\t'.ord or c == '\n'.ord or c == '\r'.ord

proc getWordAtPosition*(b: TextBuffer, pos: BufferPosition): string =
  ## Get the word at the given buffer position.
  ## A "word" follows `isWordChar` semantics, so CJK and other Unicode letters
  ## are included alongside ASCII alphanumerics and underscore.
  ## Returns empty string if cursor is not on a word character.
  if pos.line < 0 or pos.line >= b.len:
    return ""

  let line = b.getLine(pos.line)
  # `pos.column` is a `charLen` column, so the characters have to be indexed in
  # the same model; `runes` steps by a different rule.
  let runes = line.toCharRunes()

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

  # Slice the source bytes rather than re-encoding the runes: a byte that does
  # not decode would come back as the replacement character, and the byte-wise
  # comparison in `findWordMatchRanges` would then never match it.
  line.charSubStr(startCol, endCol - startCol + 1)

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
  let runes = line.toCharRunes()

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

  # Compared byte for byte against the word the cursor produced, so the slice
  # must keep the source bytes rather than re-encode them.
  return line.charSubStr(startCol, endCol - startCol + 1) == word

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
  of ckReplaceLines:
    return
      BufferPosition(line: change.replaceLinesIdx, column: change.replaceLinesColumn)
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

iterator modifiedLinesOf(change: BufferChange): int =
  ## The lines a change leaves marked modified in the sidebar. Every kind but
  ## ckReplaceLines touches one line; that one marks what the insert/delete/
  ## replace sequence it stands for would have, the rows overwritten in place
  ## plus the row a shrinking span closed over, but leaves a row given back
  ## its own text unmarked.
  let pos = getChangePosition(change).line
  if change.kind != ckReplaceLines:
    yield pos
  else:
    let
      oldCount = change.replaceLinesOldText.len
      newCount = change.replaceLinesNewText.len
    if change.replaceLinesKeepRows:
      let overlap = min(oldCount, newCount)
      for i in 0 ..< overlap:
        if change.replaceLinesOldText[i] != change.replaceLinesNewText[i]:
          yield pos + i
      if oldCount > newCount:
        yield pos + overlap
    elif oldCount > 0:
      # Nothing was overwritten in place: the old rows left and the
      # replacement arrived as fresh ones, so the only mark is the one the
      # departing rows leave on the row below them, as deleting them line by
      # line would.
      yield pos + newCount

proc countNewlines(s: string): int {.inline.} =
  for c in s:
    if c == '\n':
      inc result

proc diffNamedMarks*(
    before, after: NamedMarks, touched: set[char] = {}
): seq[NamedMarkChange] =
  ## Keep only marks whose state changed, avoiding a full mark array in every
  ## undo entry. `touched` includes marks temporarily moved by a transaction
  ## even when their final position equals their initial one.
  for name in 'a' .. 'z':
    if before[name] != after[name] or name in touched:
      result.add(NamedMarkChange(name: name, before: before[name], after: after[name]))

proc applyNamedMarkChanges*(
    marks: var NamedMarks, changes: seq[NamedMarkChange], useAfter: bool
) =
  ## Apply one side of a sparse named-mark delta without disturbing marks set
  ## after the edit on names the edit did not affect.
  for change in changes:
    marks[change.name] = if useAfter: change.after else: change.before

proc moveNamedMarks(b: TextBuffer, edit: SpanEdit) =
  ## Vim's mark_adjust: drop marks on deleted rows, move the rest with the text.
  if edit.inLine:
    var lastColumn = -1
    for mark in b.namedMarks.mitems:
      if mark.isSome and mark.get.line == edit.start.line and
          mark.get.column >= edit.start.column:
        if lastColumn < 0:
          lastColumn = max(0, b.getLine(edit.start.line).charLen - 1)
        var pos = mark.get
        pos.column = min(
          max(edit.start.column, pos.column + edit.newEnd.column - edit.oldEnd.column),
          lastColumn,
        )
        mark = some(pos)
    return
  let rows = edit.rows
  if rows.isNone:
    return
  for mark in b.namedMarks.mitems:
    if mark.isSome:
      var pos = mark.get
      if pos.line >= rows.get.start + rows.get.before:
        pos.line += rows.get.after - rows.get.before
        mark = some(pos)
      elif pos.line >= rows.get.start:
        mark = none(BufferPosition)

func boxed*(area: Option[VisualArea]): ref VisualArea =
  if area.isSome:
    result = new VisualArea
    result[] = area.get

proc moveLastVisual(b: TextBuffer, move: RowMove) =
  ## Move the last Visual area's ends across `move`.
  if b.lastVisual.isSome:
    b.lastVisual.get.start.line = b.lastVisual.get.start.line.moved(move)
    b.lastVisual.get.cursor.line = b.lastVisual.get.cursor.line.moved(move)

proc moveLastVisualEnds*(b: TextBuffer, start, cursor: Option[BufferPosition]) =
  ## Place each re-placed end of the last Visual area.
  if b.lastVisual.isSome:
    if start.isSome:
      b.lastVisual.get.start = start.get
    if cursor.isSome:
      b.lastVisual.get.cursor = cursor.get

type JoinSpan = object
  first: BufferPosition ## where the join starts
  joinedLine: int ## the line pulled up onto `first.line`

func joinSpan(change: BufferChange): Option[JoinSpan] =
  ## Lines `change` joins, if any; splits move no column, as in Vim.
  if change.kind == ckDeleteRange:
    let joinedLine = change.deleteEndPos.line + ord(change.deleteJoinedNextLine)
    if joinedLine > change.deleteStartPos.line:
      return some(JoinSpan(first: change.deleteStartPos, joinedLine: joinedLine))

func acrossJoin(
    span: JoinSpan, pos: BufferPosition, keepDropped: bool
): Option[BufferPosition] =
  ## Where `pos` lands across the join (Vim's mark_col_adjust), unclamped;
  ## none when outside it.
  if pos < span.first or pos.line > span.joinedLine:
    return
  if pos.line == span.first.line:
    return some(pos)
  if pos.line == span.joinedLine or keepDropped:
    return some(
      BufferPosition(line: span.first.line, column: span.first.column + pos.column)
    )

proc insert[T](x: var seq[T], v: T, i, count: int) =
  ## `count` copies of `v` at `i`, tail moved once. Plain-seq twin of the
  ## CowSeq overload.
  if count <= 0:
    return
  let oldLen = x.len
  x.setLen(oldLen + count)
  for j in countdown(oldLen - 1, i):
    x[j + count] = x[j]
  for j in 0 ..< count:
    x[i + j] = v

proc delete[T](x: var seq[T], i, count: int) =
  ## `count` elements dropped from `i`, tail moved once. Stops at the end
  ## rather than raising if `count` overruns.
  if count <= 0:
    return
  let
    oldLen = x.len
    removable = min(count, oldLen - i)
  if removable <= 0:
    return
  for j in i ..< oldLen - removable:
    x[j] = x[j + removable]
  x.setLen(oldLen - removable)

template shiftPerLineArray(arr: untyped, freshValue: untyped, rows: RowSpan) =
  ## Shift a per-line side array across `rows`; clamps to `arr.len` so a short
  ## NoUndo array degrades gracefully instead of raising IndexDefect.
  if rows.start < 0 or rows.start > arr.len:
    logDebug(
      "buffer",
      "shiftPerLineArray clamp: " & astToStr(arr) & " idx=" & $rows.start & " len=" &
        $arr.len,
    )
  else:
    arr.delete(rows.start, rows.before)
    arr.insert(freshValue, rows.start, rows.after)

func span*(d: BufferDiagnostic): Span =
  Span(
    first: BufferPosition(line: d.startLine, column: d.startCol),
    last: BufferPosition(line: d.endLine, column: d.endCol),
  )

proc setSpan*(d: var BufferDiagnostic, span: Span) =
  d.startLine = span.first.line
  d.startCol = span.first.column
  d.endLine = span.last.line
  d.endCol = span.last.column

iterator startingOn*(
    report: DiagnosticReport, lines: Slice[int]
): lent BufferDiagnostic =
  ## Diagnostics of `report` starting on `lines`, in start order.
  var i = report.items.lowerBound(
    lines.a,
    proc(d: BufferDiagnostic, line: int): int =
      cmp(d.startLine, line),
  )
  while i < report.items.len and report.items[i].startLine <= lines.b:
    yield report.items[i]
    inc i

func rowEdit(row, before, after: int): SpanEdit =
  ## Replace `before` whole rows at `row` with `after` rows.
  SpanEdit(
    start: BufferPosition(line: row),
    oldEnd: BufferPosition(line: row + before),
    newEnd: BufferPosition(line: row + after),
    rowsAtStart: true,
  )

func tailColumns(text: string): int =
  ## Columns of `text` after its last line break.
  var i = text.high
  while i >= 0 and text[i] != '\n':
    dec i
  text[i + 1 .. ^1].charLen

proc lineEdit(row: int, old, new: string): Option[SpanEdit] =
  ## Diff of rewriting line `row` from `old` to `new`; none when equal.
  if old == new:
    return
  let shorter = min(old.len, new.len)
  var head = 0
  while head < shorter and old[head] == new[head]:
    inc head
  var tail = 0
  while tail < shorter - head and old[old.high - tail] == new[new.high - tail]:
    inc tail
  while head > 0 and (
    (head < old.len and old[head].isContinuationByte) or
    (head < new.len and new[head].isContinuationByte)
  )
  :
    dec head
  while tail > 0 and
      (old[old.len - tail].isContinuationByte or new[new.len - tail].isContinuationByte):
    dec tail
  some(
    SpanEdit(
      start: BufferPosition(line: row, column: old.byteToCharPos(head)),
      oldEnd: BufferPosition(line: row, column: old.byteToCharPos(old.len - tail)),
      newEnd: BufferPosition(line: row, column: new.byteToCharPos(new.len - tail)),
      atLineEnd: tail == 0,
      guessed: true,
    )
  )

func seamLine(change: BufferChange): int =
  ## Line whose columns a seam broke, -1 when none.
  case change.kind
  of ckInsertText:
    if countNewlines(change.insertText) == 0 and
        change.insertColDelta != change.insertText.charLen:
      return change.insertPos.line
  of ckDeleteText:
    if countNewlines(change.deletedText) == 0 and
        change.deleteColDelta != -change.deletedText.charLen:
      return change.deletePos.line
  of ckDeleteRange:
    if change.deleteStartPos.line == change.deleteEndPos.line and
        not change.deleteJoinedNextLine and
        -change.deleteRangeColDelta != change.deletedRangeText.charLen:
      return change.deleteStartPos.line
  else:
    discard
  -1

iterator spanEdits(change: BufferChange): SpanEdit =
  ## Text `change` replaced; skips a seam-broken line so its followers stay.
  case change.kind
  of ckInsertText:
    let
      pos = change.insertPos
      rows = countNewlines(change.insertText)
    if rows > 0 and change.insertOpenLine != olNone:
      yield rowEdit(pos.line + ord(change.insertOpenLine == olBelow), 0, rows)
    elif rows > 0 and change.insertSplitTailLen <= 0:
      # A break at end of line splits like `o`: the head stays as text, the
      # rest arrives as whole rows below.
      let head = change.insertText.find('\n')
      if head > 0:
        yield SpanEdit(
          start: pos,
          oldEnd: pos,
          newEnd: BufferPosition(
            line: pos.line, column: pos.column + change.insertText[0 ..< head].charLen
          ),
          atLineEnd: true,
        )
      yield rowEdit(pos.line + 1, 0, rows)
    elif rows > 0 or (change.seamLine < 0 and change.insertColDelta > 0):
      yield SpanEdit(
        start: pos,
        oldEnd: pos,
        newEnd:
          if rows > 0:
            BufferPosition(line: pos.line + rows, column: change.insertText.tailColumns)
          else:
            BufferPosition(line: pos.line, column: pos.column + change.insertColDelta),
        atLineEnd: change.insertSplitTailLen <= 0,
        rowsAtStart: pos.column == 0 and rows > 0,
      )
  of ckDeleteText:
    let
      pos = change.deletePos
      rows = countNewlines(change.deletedText)
    if rows > 0 or (change.seamLine < 0 and change.deleteColDelta < 0):
      yield SpanEdit(
        start: pos,
        oldEnd:
          if rows > 0:
            BufferPosition(
              line: pos.line + rows, column: change.deletedText.tailColumns
            )
          else:
            BufferPosition(line: pos.line, column: pos.column - change.deleteColDelta),
        newEnd: pos,
      )
  of ckInsertLine:
    yield rowEdit(change.insertLineIdx, 0, 1)
  of ckDeleteLine:
    yield rowEdit(change.deleteLineIdx, 1, 0)
  of ckDeleteRange:
    let
      start = change.deleteStartPos
      last = change.deleteEndPos
      inLine = start.line == last.line and not change.deleteJoinedNextLine
    if change.seamLine < 0:
      let oldEnd =
        if change.deleteJoinedNextLine:
          BufferPosition(line: last.line + 1)
        elif inLine:
          BufferPosition(
            line: start.line, column: start.column - change.deleteRangeColDelta
          )
        else:
          BufferPosition(
            line: start.line + countNewlines(change.deletedRangeText),
            column: change.deletedRangeText.tailColumns,
          )
      if start < oldEnd:
        yield SpanEdit(start: start, oldEnd: oldEnd, newEnd: start)
  of ckReplaceLine:
    let edit = lineEdit(
      change.replaceLineIdx, change.replaceLineOldText, change.replaceLineNewText
    )
    if edit.isSome:
      yield edit.get
  of ckReplaceLines:
    let
      row = change.replaceLinesIdx
      oldCount = change.replaceLinesOldText.len
      newCount = change.replaceLinesNewText.len
    if change.replaceLinesKeepRows:
      let overlap = min(oldCount, newCount)
      for i in 0 ..< overlap:
        let edit = lineEdit(
          row + i, change.replaceLinesOldText[i], change.replaceLinesNewText[i]
        )
        if edit.isSome:
          yield edit.get
      if oldCount != newCount:
        yield rowEdit(row + overlap, oldCount - overlap, newCount - overlap)
    elif oldCount > 0 or newCount > 0:
      yield rowEdit(row, oldCount, newCount)
  of ckSnapshot:
    for i in 0 ..< change.snapshotEdits.len:
      yield change.snapshotEdits[i]
  of ckTransaction:
    discard

iterator savedRows(change: BufferChange): RowSpan =
  ## Rows `change` rewrote, as Vim's undo saves them. Skipped when it added or
  ## dropped none.
  case change.kind
  of ckInsertText:
    let added = countNewlines(change.insertText)
    if added > 0:
      let pos = change.insertPos
      yield (
        case change.insertOpenLine
        of olNone: RowSpan(start: pos.line, before: 1, after: added + 1)
        of olBelow: RowSpan(start: pos.line + 1, after: added)
        of olAbove: RowSpan(start: pos.line, after: added)
      )
  of ckDeleteText:
    let dropped = countNewlines(change.deletedText)
    if dropped > 0:
      yield RowSpan(start: change.deletePos.line, before: dropped + 1, after: 1)
  of ckInsertLine:
    yield RowSpan(start: change.insertLineIdx, after: 1)
  of ckDeleteLine:
    yield RowSpan(start: change.deleteLineIdx, before: 1)
  of ckDeleteRange:
    let dropped =
      change.deleteEndPos.line - change.deleteStartPos.line +
      ord(change.deleteJoinedNextLine)
    if dropped > 0:
      yield RowSpan(start: change.deleteStartPos.line, before: dropped + 1, after: 1)
  of ckReplaceLines:
    if change.replaceLinesOldText.len != change.replaceLinesNewText.len:
      yield RowSpan(
        start: change.replaceLinesIdx,
        before: change.replaceLinesOldText.len,
        after: change.replaceLinesNewText.len,
      )
  of ckSnapshot:
    for i in 0 ..< change.snapshotRows.len:
      yield change.snapshotRows[i]
  of ckReplaceLine, ckTransaction:
    discard

proc wantsSnapshotRows(b: TextBuffer): bool =
  ## Whether an entry needs its rows replayed: for the jump list, or for a
  ## Visual area it was not made with.
  if b.rowsMovedHook != nil:
    true
  elif b.inTransaction and b.currentTransaction.isSome:
    b.currentTransaction.get.lastVisualBefore.isNone
  else:
    b.lastVisual.isNone

proc notifyRowsMoved(b: TextBuffer, move: RowMove) =
  if b.rowsMovedHook != nil:
    b.rowsMovedHook(b, move)

proc restoreRows*(
    b: TextBuffer, rows: openArray[RowSpan], undone: bool, visual = false
) =
  ## Move the jump list, and the last Visual area when `visual`, across undo
  ## (`undone`) or redo of edits to `rows`, as Vim's u_undoredo does.
  template restore(r: RowSpan) =
    let move = RowMove(rows: r, restoring: true)
    if visual:
      b.moveLastVisual(move)
    b.notifyRowsMoved(move)

  if undone:
    for i in countdown(rows.high, 0):
      restore(
        RowSpan(start: rows[i].start, before: rows[i].after, after: rows[i].before)
      )
  else:
    for r in rows:
      restore(r)

proc rowsAcrossUndo*(b: TextBuffer, change: BufferChange, undone: bool) =
  ## Move the last Visual area, unless `change` restores it, and the jump list
  ## across undo/redo of `change`.
  let visual = change.visualAcross == nil and b.lastVisual.isSome
  if not visual and b.rowsMovedHook == nil:
    return
  var rows: seq[RowSpan]
  for r in change.savedRows:
    rows.add r
  b.restoreRows(rows, undone, visual)

proc moveDiagnostics(b: TextBuffer, edit: SpanEdit) =
  ## Move diagnostics across `edit`; drop those it deleted.
  for source in DiagnosticSource:
    template items(): untyped =
      b.diagnostics[source].items

    var
      kept = 0
      changed = false
    for i in 0 ..< items.len:
      let span = items[i].span
      if not (span.last < edit.start):
        if edit.deletes(span):
          changed = true
          continue
        let after = span.moved(edit)
        if after != span:
          items[i].setSpan(after)
          changed = true
      if kept != i:
        items[kept] = move(items[i])
      inc kept
    items.setLen(kept)
    if changed and source == dsrcLsp:
      b.diagnosticsDirty = true
    if b.awaitedReports[source].id != 0:
      b.awaitedReports[source].edits.record(edit)

const AllFollowers* = {EditFollower.low .. EditFollower.high}

proc follow(
    b: TextBuffer, edit: SpanEdit, followers: set[EditFollower]
) {.raises: [].} =
  ## Move `followers` across `edit`.
  if efSemantic in followers:
    b.highlight.semanticMoveAcross(edit)
  let rows = edit.rows
  if rows.isSome:
    let rows = rows.get
    template shift(onDelete, onInsert: untyped) =
      if rows.before > 0:
        onDelete(rows.start, rows.before)
      if rows.after > 0:
        onInsert(rows.start, rows.after)

    if efFolds in followers:
      shift(b.foldState.adjustFoldsAfterDelete, b.foldState.adjustFoldsAfterInsert)
    if efBookmarks in followers:
      shift(b.adjustBookmarksForDelete, b.adjustBookmarksForInsert)
    if efLastVisual in followers:
      b.moveLastVisual(RowMove(rows: rows))
    if efJumps in followers:
      b.notifyRowsMoved(RowMove(rows: rows))
    if efLineArrays in followers:
      shiftPerLineArray(b.lineMarkers, none(LineMarkerKind), rows)
      shiftPerLineArray(b.modifiedLines, lmkInserted, rows)
  if efNamedMarks in followers:
    b.moveNamedMarks(edit)
  if efDiagnostics in followers:
    b.moveDiagnostics(edit)

proc followBack*(
    b: TextBuffer, edits: openArray[SpanEdit], followers: set[EditFollower]
) =
  ## Move `followers` back across `edits` being undone.
  for i in countdown(edits.high, 0):
    b.follow(edits[i].reversed, followers)

proc followChange*(
    b: TextBuffer,
    change: BufferChange,
    followers: set[EditFollower] = AllFollowers,
    undone = false,
    recording = false,
) =
  ## Move `followers` across `change` (or back when `undone`). `recording`
  ## saves replaced text for the snapshot entry. Marks the semantic overlay up
  ## to date.
  if undone:
    var edits: seq[SpanEdit]
    for edit in change.spanEdits:
      edits.add edit
    b.followBack(edits, followers)
  else:
    for edit in change.spanEdits:
      b.follow(edit, followers)
      if recording and b.pendingSnapshot.isSome:
        b.pendingSnapshotEdits.record(edit)
    if recording and b.pendingSnapshot.isSome and b.wantsSnapshotRows:
      for rows in change.savedRows:
        b.pendingSnapshotRows.add rows
  if efSemantic in followers and not b.highlight.isNil:
    let seam = change.seamLine
    if seam >= 0:
      # Its columns are stale.
      b.highlight.semantic.del(seam)
    b.highlight.semanticContentVersion = b.contentVersion

var awaitedReportIds = 0

proc awaitReport*(b: TextBuffer, source: DiagnosticSource): int =
  ## Watch edits from now on for a `source` report on current text; return its
  ## id for `setDiagnostics`. Replaces any earlier wait.
  inc awaitedReportIds
  b.awaitedReports[source] = AwaitedReport(id: awaitedReportIds)
  awaitedReportIds

proc stopAwaiting*(b: TextBuffer, source: DiagnosticSource, awaited: int) =
  ## Drop the wait for `awaited`, if still pending.
  if b.awaitedReports[source].id == awaited:
    b.awaitedReports[source] = AwaitedReport()

proc setDiagnostics*(
    b: TextBuffer,
    source: DiagnosticSource,
    items: sink seq[BufferDiagnostic],
    awaited = 0,
    owner = "",
): bool {.discardable.} =
  ## Replace `source` diagnostics with `owner`'s, saying whether taken. Moves
  ## the `awaited` report across edits since; drops it after. Empty ranges collapse.
  var
    items = items
    edits: seq[SpanEdit]
  if awaited != 0:
    if b.awaitedReports[source].id != awaited:
      return false
    edits = move(b.awaitedReports[source].edits)
    b.awaitedReports[source] = AwaitedReport()
  # Sort first; edits preserve order.
  items.sort(
    proc(x, y: BufferDiagnostic): int =
      cmp((x.startLine, x.startCol), (y.startLine, y.startCol))
  )
  var kept = 0
  for i in 0 ..< items.len:
    var
      span = items[i].span
      deleted = false
    if span.last < span.first:
      span.last = span.first
    for edit in edits:
      if edit.deletes(span):
        deleted = true
        break
      span = span.moved(edit)
    if not deleted and span.first.line < b.len:
      items[i].setSpan(span)
      if kept != i:
        items[kept] = move(items[i])
      inc kept
  items.setLen(kept)
  b.diagnostics[source] = DiagnosticReport(items: move(items), owner: owner)
  if source == dsrcLsp:
    b.highlightNeedsUpdate = true
    b.diagnosticsDirty = true
  true

proc clearDiagnostics*(
    b: TextBuffer,
    sources: set[DiagnosticSource] = {DiagnosticSource.low .. DiagnosticSource.high},
) =
  ## Drop `sources` diagnostics (all by default) and their awaited reports.
  for source in sources:
    if source == dsrcLsp and b.diagnostics[source].items.len > 0:
      b.highlightNeedsUpdate = true
      b.diagnosticsDirty = true
    b.diagnostics[source] = DiagnosticReport()
    b.awaitedReports[source] = AwaitedReport()

proc setContentReplacedHook*(b: TextBuffer, cb: BufferContentReplacedHook) =
  ## Install the hook run after a wholesale content replacement. Replaces any
  ## previous one.
  b.contentReplacedHook = cb

proc setRowsMovedHook*(b: TextBuffer, cb: BufferRowsMovedHook) =
  ## Install the hook run whenever rows move. Replaces any previous one.
  b.rowsMovedHook = cb

proc setFileReadHook*(b: TextBuffer, cb: BufferFileReadHook) =
  ## Install the hook run whenever `lastLoadedContent` is taken from the file.
  ## Replaces any previous one.
  b.fileReadHook = cb

proc emitFileRead*(b: TextBuffer) =
  ## Announce that `lastLoadedContent` is what the file held just now.
  if b.fileReadHook == nil:
    return
  try:
    b.fileReadHook(b)
  except CatchableError as e:
    logError("buffer", "fileReadHook raised: " & e.msg)

proc emitContentReplaced*(b: TextBuffer) =
  ## Announce that `b` now holds different contents, invalidating every
  ## position taken before this point. Called at the end of every load.
  if b.contentReplacedHook == nil:
    return
  try:
    b.contentReplacedHook(b)
  except CatchableError as e:
    logError("buffer", "contentReplacedHook raised: " & e.msg)

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
    b.pendingSnapshotNamedMarks = b.namedMarks
    b.pendingSnapshotBookmarks = b.bookmarks
  # Capture modifiedLines snapshot for non-PieceTable backends (once per undo entry).
  # PieceTable diffs pendingSnapshotModifiedLines into a ckSnapshot delta instead.
  # A transaction is one undo entry whose first recorded change carries the
  # pre-transaction arrays, so re-capturing would copy them per inner change.
  let alreadyRecorded =
    b.inTransaction and b.currentTransaction.isSome and
    b.currentTransaction.get.changes.len > 0
  if b.backendKind != PieceTable and not alreadyRecorded:
    if not b.hasPendingModifiedLinesSnapshot:
      b.pendingModifiedLinesSnapshot = b.modifiedLines
      b.hasPendingModifiedLinesSnapshot = true
    if not b.hasPendingLineMarkersSnapshot:
      b.pendingLineMarkersSnapshot = b.lineMarkers
      b.hasPendingLineMarkersSnapshot = true

proc takePendingSnapshotEdits*(b: TextBuffer): CowSeq[SpanEdit] =
  ## Move replaced text since the snapshot into its undo entry; nil when none.
  if b.pendingSnapshotEdits.len > 0:
    result = initCowSeq(move(b.pendingSnapshotEdits))

proc takePendingSnapshotRows*(b: TextBuffer): CowSeq[RowSpan] =
  ## Move rewritten rows since the snapshot into its undo entry; nil when none.
  if b.pendingSnapshotRows.len > 0:
    result = initCowSeq(move(b.pendingSnapshotRows))

proc discardPendingSnapshot*(b: TextBuffer) {.inline.} =
  ## Drop every pending snapshot artifact captured for a mutation that ended up
  ## not happening (e.g. backend raised after captureSnapshotIfNeeded). Symmetric
  ## inverse of captureSnapshotIfNeeded; keeps the next pushUndoChange from
  ## attaching stale data.
  b.pendingSnapshot = none(PieceTableSnapshot)
  b.pendingSnapshotMarkers.clear()
  b.pendingSnapshotModifiedLines.setLen(0)
  b.pendingSnapshotFolds = initFoldState()
  b.pendingSnapshotNamedMarks = default(NamedMarks)
  b.pendingSnapshotBookmarks.setLen(0)
  # Released, not truncated: one large edit would otherwise leave its capacity
  # on the buffer for good.
  b.pendingSnapshotEdits = @[]
  b.pendingSnapshotRows = @[]
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
  b.reloadUndoLines = 0
  b.reloadUndoBytes = 0
  b.inTransaction = false
  b.currentTransaction = none(BufferTransaction)
  b.discardPendingSnapshot()
  # The empty stack reads as id 0, so this is a clean post-reload state. The
  # counter keeps going: an id names one change for the buffer's whole life.
  b.savedChangeId = 0
  b.historyResets.inc

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

proc dropChangeListFuture*(b: TextBuffer) =
  ## Drop `changeList` entries past the index (left by undo). Once the redo
  ## stack is gone they name nothing, but `g;` / `g,` would still visit them.
  if b.changeList.len > 0 and b.changeListIndex < b.changeList.len - 1:
    b.changeList.setLen(b.changeListIndex + 1)

proc detachLastEntryFromChangeList*(
    b: TextBuffer, changeListAcross: seq[BufferPosition], changeListIndexAcross: int
) =
  ## Mark the newest undo entry as having no changelist position and store the
  ## pre-entry list for undo/redo to swap back.
  if b.undoStack.len > 0:
    b.undoStack[^1].noChangeListPosition = true
    b.undoStack[^1].changeListAcross = some(changeListAcross)
    b.undoStack[^1].changeListIndexAcross = changeListIndexAcross

proc markLastEntryReload*(b: TextBuffer) =
  ## Mark the newest undo entry as a reload, for `reloadedSince`.
  if b.undoStack.len > 0:
    b.undoStack[^1].isReload = true

proc chargeReloadUndoBudget*(b: TextBuffer, lines, bytes: int) =
  ## Charge the newest undo entry against the reload budget so it can be
  ## refunded when the entry leaves history. No-op if there is no entry.
  if b.undoStack.len == 0:
    return
  b.reloadUndoLines += lines
  b.reloadUndoBytes += bytes
  b.undoStack[^1].reloadChargeLines = lines
  b.undoStack[^1].reloadChargeBytes = bytes

proc refundReloadUndoBudget*(b: TextBuffer, entry: BufferChange) =
  ## Refund `entry`'s reload-budget charge as it leaves history. Call on every
  ## path that drops an entry without replaying it.
  b.reloadUndoLines -= entry.reloadChargeLines
  b.reloadUndoBytes -= entry.reloadChargeBytes

proc pushUndoChange*(b: TextBuffer, change: BufferChange) =
  ## Add a change to the undo stack (or current transaction)
  ## Always increments changeSeq to mark buffer as modified

  # Clear redo; refund reload-budget charges those entries still held.
  for dropped in b.redoStack:
    b.refundReloadUndoBudget(dropped)
  b.redoStack.clear()

  b.dropChangeListFuture()

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
  let marksBefore = b.namedMarks
  let visualBefore = b.lastVisual
  # Dropped rows take folds/bookmarks for good, so save them with the change.
  let needsFoldBookmarkRestore =
    change.kind == ckReplaceLines and (
      not change.replaceLinesKeepRows or
      change.replaceLinesOldText.len > change.replaceLinesNewText.len
    )
  var
    foldsBefore: FoldState
    bookmarksBefore: seq[int]
  if needsFoldBookmarkRestore:
    foldsBefore = b.foldState
    bookmarksBefore = b.bookmarks
  b.followChange(change, recording = true)
  let join = change.joinSpan
  if join.isSome:
    for name in 'a' .. 'z':
      if marksBefore[name].isSome:
        let moved = join.get.acrossJoin(marksBefore[name].get, keepDropped = false)
        if moved.isSome:
          b.namedMarks[name] = moved
    if visualBefore.isSome:
      b.moveLastVisualEnds(
        join.get.acrossJoin(visualBefore.get.start, keepDropped = true),
        join.get.acrossJoin(visualBefore.get.cursor, keepDropped = true),
      )

  let namedMarkChanges = diffNamedMarks(marksBefore, b.namedMarks)

  # Mark highlight as needing update and track the first changed line for
  # incremental highlighting
  let changePos = getChangePosition(change)
  b.markLineChanged(changePos.line)

  # Mark the changed lines as modified
  b.ensureMarkersSize()
  b.ensureModifiedLinesSize()
  for line in modifiedLinesOf(change):
    # Only upgrade to lmkModified if not already marked as inserted
    if line in 0 ..< b.modifiedLines.len and b.modifiedLines[line] != lmkInserted:
      b.modifiedLines[line] = lmkModified

  # Record change position in changelist
  if not b.inTransaction:
    b.recordChangePosition(changePos)

  # Attach pre-mutation modifiedLines snapshot to the change
  var changeWithSnapshot = change
  if needsFoldBookmarkRestore:
    changeWithSnapshot.replaceLinesSavedFolds = foldsBefore
    changeWithSnapshot.replaceLinesSavedBookmarks = bookmarksBefore
  changeWithSnapshot.namedMarkChanges = namedMarkChanges
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
    # Appended in place: copying the transaction out and back would re-copy
    # every change already in it, which is quadratic once an edit records one
    # change per line.
    b.currentTransaction.get.changes.add(changeWithSnapshot)
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
        snapshotEdits: b.takePendingSnapshotEdits(),
        snapshotRows: b.takePendingSnapshotRows(),
        namedMarkChanges: diffNamedMarks(b.pendingSnapshotNamedMarks, b.namedMarks),
        visualAcross: visualBefore.boxed,
      )
    )
    # Pending snapshot state is now consumed into the entry; reset it all.
    b.discardPendingSnapshot()
  else:
    # Add directly to undo stack
    changeWithSnapshot.id = b.allocateChangeId()
    changeWithSnapshot.visualAcross = visualBefore.boxed
    b.undoStack.addLast(changeWithSnapshot)
