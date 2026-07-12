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

import std/[options, monotimes, times, tables, strutils]

import pkg/celina

import
  modes,
  buffer,
  types/registers_types,
  types/filer_types,
  types/filetree_types,
  log_viewer,
  types/help_viewer_types,
  types/command_completion_types,
  message_log,
  logger,
  types/buffer_manager_types,
  types/bookmark_manager_types,
  types/backup_manager_types,
  types/diff_viewer_types,
  types/debug_viewer_types,
  types/config_mode_types,
  types/references_viewer_types,
  types/documentsymbol_viewer_types,
  types/callhierarchy_viewer_types,
  hover_popup,
  notification_popup,
  primitives,
  types/syntax_checker_types,
  types/recent_file_mode_types,
  terminal_mode,
  config

from lsp/protocol/types import SemanticTokensLegend

export
  buffer.LineMarkerKind, registers_types, command_completion_types, filer_types,
  filetree_types, log_viewer, help_viewer_types, buffer_manager_types,
  bookmark_manager_types, backup_manager_types, diff_viewer_types, debug_viewer_types,
  config_mode_types, references_viewer_types, documentsymbol_viewer_types,
  callhierarchy_viewer_types, hover_popup, notification_popup, primitives,
  syntax_checker_types, recent_file_mode_types, terminal_mode, config.BracketSplitMode

type
  SidebarItem* = object ## Single cell in the sidebar
    text*: string ## Display text (e.g., "+", "~", ">>")
    kind*: Option[LineMarkerKind] ## none = empty cell
    style*: Style ## Rendering style

  Sidebar* = object
    ## Sidebar displayed on the left side of editor window
    ## Used for git diff, syntax errors, etc.
    width*: int ## Width of sidebar in characters
    buffer*: seq[seq[SidebarItem]] ## Per-line sidebar content [y][x]

  ViewPort* = ref object
    topLine*: int
    topWrapOffset*: int
      ## Leading wrap segments of `topLine` skipped so the view can start
      ## mid logical line (wrap mode only; always 0 in no-wrap mode). Invariant:
      ## `0 <= topWrapOffset < wrapCount(topLine)`. The authoritative
      ## `adjustViewportForCursor` recomputes it every frame; every other writer
      ## just resets it to 0 via `resetViewportTop` (next frame re-derives it).
    leftColumn*: int
    width*: int
    height*: int
    x*: int # Screen position X
    y*: int # Screen position Y

  ScrollAnimation* = object
    # Physics-based smooth scrolling (comfortable-motion compatible)
    active*: bool
    velocity*: float # Current scroll velocity (lines per second)
    currentCursorLine*: float # Current cursor line (fractional for smooth animation)
    targetCursorLine*: int # Target cursor line
    lastUpdateTime*: MonoTime # Last physics update time

  WindowDisplayState* = object
    ## Editor-wide window/buffer display & redraw bookkeeping.
    currentBufferId*: BufferId # BufferId of the current buffer (for jump list)
    debugBuffer*: TextBuffer # Debug buffer for auto-refresh (nil if none)
    viewportReservedLines*: int
      # Reserved lines for viewport calculations (for split windows)
    scrollAnimation*: ScrollAnimation # Current scroll animation state
    savedViewportTopLine*: int # Viewport position saved when operator starts

  CursorPosition* = object
    x*: int
    y*: int

  ModeStateKind* {.pure.} = enum
    ## Discriminator for `ModeState`. `mskNone` covers all modes that do not
    ## carry per-window state (Normal/Insert/Visual/... and overlays).
    mskNone
    mskFiler
    mskFileTree
    mskLogViewer
    mskHelp
    mskBufferManager
    mskBookmarkManager
    mskBackupManager
    mskDiffViewer
    mskDebug
    mskConfig
    mskReferences
    mskDocumentSymbol
    mskCallHierarchy
    mskRecentFile
    mskTerminal

  WrapCountCache* = ref object
    ## Per-window memoization of `calculateWrapCount` results. Bumping
    ## `currentGen` on any key-field mismatch gives O(1) invalidation —
    ## an entry is fresh iff `gens[line] == currentGen`.
    counts*: seq[int]
    gens*: seq[int]
    currentGen*: int
    bufferId*: BufferId
    bufferContentVersion*: int
    viewportWidth*: int
    tabStop*: int

  ModeState* = object
    ## Per-window mode-specific state, replacing the previous bundle of
    ## `Option[XxxState]` fields on `EditorWindow`. At most one mode owns the
    ## window at a time, so a tagged union enforces the exclusivity that was
    ## previously a convention.
    case kind*: ModeStateKind
    of mskNone: discard
    of mskFiler: filer*: FilerState
    of mskFileTree: fileTree*: FileTreeState
    of mskLogViewer: logViewer*: LogViewerState
    of mskHelp: help*: HelpViewerState
    of mskBufferManager: bufferManager*: BufferManagerState
    of mskBookmarkManager: bookmarkManager*: BookmarkManagerState
    of mskBackupManager: backupManager*: BackupManagerState
    of mskDiffViewer: diffViewer*: DiffViewerState
    of mskDebug: debug*: DebugViewerState
    of mskConfig: config*: ConfigModeState
    of mskReferences: references*: ReferencesViewerState
    of mskDocumentSymbol: documentSymbol*: DocumentSymbolViewerState
    of mskCallHierarchy: callHierarchy*: CallHierarchyViewerState
    of mskRecentFile: recentFile*: RecentFileModeState
    of mskTerminal: terminal*: TerminalState

  SuspendedMode* = object
    ## The (mode, modeState) a window held before a transient overlay (the
    ## DiffViewer opened from the BackupManager) replaced it. Captured on
    ## overlay entry and restored as one consistent unit on exit, so the
    ## restored mode and its variant can never desync.
    mode*: EditorMode
    modeState*: ModeState

  EditorWindow* = ref object
    ## Represents a split window with its own buffer and viewport
    buffer*: TextBuffer
    bufferIds*: seq[BufferId]
      # Window-local tab list, stored as stable BufferIds.
      # Resolve via Editor.bufferById; entries pointing at deleted buffers
      # are pruned in the bdelete path.
    viewport*: ViewPort
    cursor*: BufferPosition # Window-local cursor position
    active*: bool # Whether this is the active window
    mode*: EditorMode # Current mode for this window
    previousMode*: EditorMode # Previous mode for ESC handling
    preferredColumn*: int # Preferred column for vertical movement (vim's $ behavior)
    screenCursor*: CursorPosition # Screen cursor position (x/y)
    modeState*: ModeState # Per-window mode-specific state (variant)
    originalBuffer*: TextBuffer
      # Saved buffer for modes that swap the window buffer (Filer, Terminal,
      # BufferManager, ...). Set on mode entry, restored and cleared on exit.
    suspendedMode*: Option[SuspendedMode]
      # The mode suspended by a transient overlay opened from another mode
      # (DiffViewer opened from BackupManager). Set on overlay entry, restored
      # and cleared on overlay exit. `none` when no overlay is active.
    fixedWidth*: Option[int] # Fixed width for sidebar windows (skips equalize)
    wrapCountCache*: WrapCountCache

  SearchDirection* = enum
    Forward # Search forward (/)
    Backward # Search backward (?)

  SearchState* = object ## Search-related state grouped together for better organization
    text*: string # Text being typed in search mode
    cursor*: int # Cursor position within text (0-based character index)
    lastText*: string # Last executed search text for n/N commands
    direction*: SearchDirection # Direction of current search (/ or ?)
    history*: seq[string] # Search history (most recent first)
    historyIndex*: int # Current position in search history (-1 when not navigating)
    startPos*: BufferPosition # Cursor position when search mode started (for incsearch)
    # Search behavior settings
    ignorecase*: bool # Ignore case in search patterns
    smartcase*: bool # Override ignorecase if pattern contains uppercase
    incsearch*: bool # Show search matches as you type
    hlsearch*: bool # Highlight all search matches in the buffer
    hlsearchTempDisabled*: bool # Temporarily disable highlight (like :nohlsearch)
    wholeWord*: bool # Search for whole words only (* and # commands)

  CommandState* = object ## Command mode (ex-mode) state grouped together
    history*: seq[string] # Command history (most recent first)
    historyIndex*: int # Current position in command history (-1 when not navigating)
    historyPrefix*: string
      # Prefix captured when history navigation started; only entries starting
      # with this prefix are surfaced by Up/Down. Empty means "match any".

  MacroState* = object ## Macro recording and playback state grouped together
    isRecording*: bool # Whether currently recording a macro
    register*: char # Which register (a-z) is being recorded to
    recordedKeys*: seq[string] # Keys being recorded in current macro session
    registers*: Table[char, seq[string]] # Saved macros by register
    lastRegister*: Option[char] # Last executed macro register for @@
    waitingForRegister*: bool # Waiting for register name after q or @
    commandType*: string # "record" or "playback"
    recordStartKey*: string # Key string that started recording (for stop detection)
    pendingCount*: int # Numeric prefix for macro playback
    playbackDepth*: int # Current macro recursion depth

  LastFindChar* = object
    ## Last f/F/t/T motion, replayed by ; (same direction) and , (reversed)
    motion*: Motion # FindChar / FindCharBackward / TillChar / TillCharBackward
    targetChar*: string

  EditState* = object ## Edit operation state grouped together
    lastEditCommand*: Option[LastEditCommand] # Last change command for . (repeat)
    lastFindChar*: Option[LastFindChar] # Last f/F/t/T for ; and , repeat
    pendingOperator*: Option[PendingOperator] # Operator waiting for motion/text object
    pendingTextObject*: Option[PendingTextObject]
      # Text object modifier waiting for object kind
    substituteContext*: Option[SubstituteContext]
      # Context for substitute commands (s/S/cc)
    replaceHistory*: seq[ReplaceHistoryEntry] # Replace mode undo history
    insertModeStartPos*: Option[BufferPosition] # Position where Insert mode started
    visualBlockInsertContext*: Option[VisualBlockInsertContext]
      # Context for visual block insert/append/change replication
    autoIndentedLine*: Option[tuple[line: int, indent: string]]
    insertReplayCount*: int
      # [count] prefix for [count]i/a/I/A/o/O. On Insert-mode exit the typed
      # text is replayed (count - 1) more times to match Vim. <= 1 means none.
    insertReplayLineEntry*: bool
      # True when Insert was entered via o/O, so each replay opens a fresh line
      # (newline + the entry line's indent) instead of inserting inline.

  DisplaySettings* = object
    ## Session-only display overrides; config-derived flags are pull accessors.
    showLineCount*: bool
    showLinePercentage*: bool
    showEncoding*: bool
    showLineEnding*: bool

  SignatureHelpRequestState* = object
    ## Debounce + change-detection state for auto signature help requests.
    ## "Debounce" here is a minimum-interval gate measured from the last issued
    ## request (same shape as documentHighlight/semanticTokens), not a
    ## reset-on-change timer. Sentinel -1 for the cursor/changeSeq fields means
    ## "no request issued yet".
    lastUpdate*: MonoTime # Timestamp of last signature help request
    interval*: int64 # Base debounce interval (milliseconds)
    cursorLine*: int # Cursor line of last request
    cursorColumn*: int # Cursor column of last request
    changeSeq*: int # Buffer changeSeq of last request
    consecutiveErrors*: int
      # Failed/timed-out requests since the last success. Widens the effective
      # interval (exponential backoff) so a persistently failing server is not
      # retried every base interval.

  PendingSemanticTokensRequest* = object
    ## Snapshot of the in-flight `textDocument/semanticTokens` request.
    ## Request-id, file-path, change-seq and content-version live in
    ## `DebouncedLspPoll` (`LspCacheState.semanticTokensPoll`); the fields
    ## here are semantic-tokens-specific extras that the generic poll type
    ## does not model.
    rangeFirst*: int
    rangeLast*: int
      # Inclusive row bounds of a range-scoped request. Both `-1` for a
      # full-document request. Bound the overlay row-set the response is
      # authoritative over; rows outside are preserved from prior responses.
    legend*: SemanticTokensLegend
      # Legend snapshot at request-send time. A dynamic
      # `client/registerCapability` between send and receive would leave the
      # response's tokenType indices pointing at THIS legend, not the
      # current one -- rejecting on mismatch avoids decoding against the
      # wrong table.
    viewportTopLine*: int
    viewportBottomLine*: int
      # Viewport at request-send time. Stamped into `semanticTokensCache`
      # instead of the response-time viewport so a scroll in flight does
      # not falsely validate the current viewport against tokens computed
      # for the prior viewport. `-1` when no pending.

  LspCacheState* = object ## LSP cache and picker state grouped together
    codeLensCache*: CodeLensCache # Cached CodeLens items for current buffer
    codeLensPicker*: CodeLensPicker # CodeLens selection UI state
    documentHighlightCache*: DocumentHighlightCache # Cached document highlights
    semanticTokensCache*: SemanticTokensCache # Semantic tokens cache state
    hoverPopup*: HoverPopupManager # Hover popup manager
    locations*: Option[LspLocationsResult]
      # LSP locations for references/definitions picker
    codeLensPoll*: DebouncedLspPoll
      # Debounce / backoff / request-time snapshot for `textDocument/codeLens`.
    documentHighlightPoll*: DebouncedLspPoll
      # Debounce / backoff / request-time snapshot for `textDocument/documentHighlight`.
    semanticTokensPoll*: DebouncedLspPoll
      # Debounce / backoff / request-time snapshot for `textDocument/semanticTokens`.
    semanticTokensPendingExtras*: PendingSemanticTokensRequest
      # Semantic-tokens-specific extras (legend, viewport, range) that the
      # generic `DebouncedLspPoll` does not model.
    inlayHintPoll*: DebouncedLspPoll
      # Debounce / backoff / request-time snapshot for `textDocument/inlayHint`.
    inlayHintCache*: InlayHintCache # Cached inlay hints for current viewport
    signatureHelp*: SignatureHelpRequestState # Auto signature help request tracking
    pendingSignatureHelpRequestId*: int
      # Request ID for pending signature help request (0 = none)
    pendingHoverRequestId*: int # Request ID for pending hover request (0 = none)
    pendingHoverBufferId*: BufferId # BufferId the pending hover request was made for
    pendingHoverCursorLine*: int # Cursor line when the hover request was made
    pendingHoverCursorCol*: int # Cursor column when the hover request was made
    autoHoverCursorLine*: int # Last cursor line for auto-hover debounce
    autoHoverCursorCol*: int # Last cursor column for auto-hover debounce
    lastAutoHoverUpdate*: MonoTime # Timestamp of last auto-hover request
    # Pending location request (definition, references, etc.)
    pendingLocationRequestId*: int # Request ID (0 = none)
    pendingLocationRequestKind*: LspLocationRequestKind # Type of location request
    # Pending document symbols request
    pendingDocumentSymbolsRequestId*: int # Request ID (0 = none)
    # Pending selection range request
    pendingSelectionRangeRequestId*: int # Request ID (0 = none)
    pendingSelectionRangeBufferId*: BufferId # BufferId the request was made for
    pendingSelectionRangeContentVersion*: int # contentVersion at request time
    # Selection range expansion chain (innermost -> outermost), rune indexes.
    # Lets repeated Ctrl-s walk the parent chain without re-querying the server.
    selectionRangeChain*: seq[tuple[first, last: BufferPosition]]
    selectionRangeIndex*: int # Current level in the chain (0 = innermost)
    # Pending call hierarchy request (2-stage: prepare -> incoming/outgoing)
    pendingCallHierarchyRequestId*: int # Request ID (0 = none)
    pendingCallHierarchyKind*: CallHierarchyRequestKind # incoming or outgoing
    # Pending code action request
    pendingCodeActionRequestId*: int # Request ID (0 = none)
    # Pending document link request
    pendingDocumentLinkRequestId*: int # Request ID (0 = none)
    pendingDocumentLinkCursorLine*: int # Cursor line when request was made
    pendingDocumentLinkCursorCol*: int # Cursor column (UTF-16) when request was made
    # Pending document link resolve request (2nd stage)
    pendingDocumentLinkResolveRequestId*: int # Request ID (0 = none)

  RenameState* = object ## State for LSP rename mode
    text*: string # New name being typed
    cursorLine*: int # Line where rename was initiated
    cursorColumn*: int # Column where rename was initiated
    originalWord*: string # Original word being renamed

  CallHierarchyRequestKind* = enum
    chrkNone
    chrkPrepareIncoming # Preparing for incoming calls
    chrkPrepareOutgoing # Preparing for outgoing calls
    chrkIncomingCalls # Getting incoming calls
    chrkOutgoingCalls # Getting outgoing calls

  LspLocationRequestKind* = enum
    lrkNone
    lrkDefinition
    lrkDeclaration
    lrkReferences
    lrkTypeDefinition
    lrkImplementation

  TimingState* = object ## Timing and debounce state grouped together
    lastResizeTime*: MonoTime # Timestamp of last processed resize event
    gitDiffUpdateInterval*: int64
      # Minimum milliseconds between git diff
      # refresh cycles. Consumed by status_line's async cache via
      # setGitDiffRefreshInterval; the historical debounce timestamps
      # (lastGitDiffUpdate/ChangeSeq) were removed along with
      # maybeUpdateGitDiff when the async cache took over.
    lastConflictScan*: MonoTime # Timestamp of last conflict marker scan
    lastConflictScanSeq*: int # Buffer changeSeq at last conflict scan
    conflictScanInterval*: int64 # Minimum milliseconds between conflict scans
    lastAutoSave*: MonoTime # Timestamp of last auto save
    lastAutoBackup*: MonoTime # Timestamp of last auto backup
    lastInputTime*: MonoTime # Timestamp of last user input (for idle detection)
    lastFileModCheck*: MonoTime # Timestamp of last file modification check
    fileModCheckInterval*: int64
      # Minimum milliseconds between file mod checks (default: 1000)
    lastConfigCheck*: MonoTime # Timestamp of last config file modification check
    lastConfigModTime*: times.Time # Last known modification time of config file
    configCheckInterval*: int64
      # Minimum milliseconds between config mod checks (default: 2000)
    lastDebugUpdate*: MonoTime # Timestamp of last debug buffer update
    debugUpdateInterval*: int64
      # Minimum milliseconds between debug buffer updates (default: 500)
    lastLspCleanup*: MonoTime # Timestamp of last LSP timed-out request cleanup
    lspCleanupInterval*: int64
      # Minimum milliseconds between LSP timed-out request cleanups (default: 1000)

  JumpPosition* = object ## Represents a position in the jump list
    bufferId*: BufferId # BufferId of the target buffer (stable across buffer deletes)
    line*: int # Line number
    column*: int # Column position

  Motion* = enum
    Left
    Right
    Up
    Down
    PageUp
    PageDown
    HalfPageUp # Ctrl-u - scroll half page up
    HalfPageDown # Ctrl-d - scroll half page down
    Home
    FirstNonBlank # ^ - move to first non-whitespace character
    LastNonBlank # g_ - move to last non-whitespace character
    End
    FirstLine
    LastLine
    FindChar
    FindCharBackward
    TillChar
    TillCharBackward
    RepeatFind # ; - repeat last f/F/t/T
    RepeatFindReverse # , - repeat last f/F/t/T in the opposite direction
    WordForward # w - move to start of next word
    WordBackward # b - move to start of previous word
    WordEnd # e - move to end of next word
    WordEndBackward # ge - move to end of previous word
    ParagraphForward # } - move to next paragraph (next blank line)
    ParagraphBackward # { - move to previous paragraph (previous blank line)
    ViewportHigh # H - move to top of viewport
    ViewportMiddle # M - move to middle of viewport
    ViewportLow # L - move to bottom of viewport
    NextLineFirstNonBlank # Enter/+ - move to next line's first non-whitespace character
    PreviousLineFirstNonBlank
      # - - move to previous line's first non-whitespace character
    MatchBracket # % - move to matching bracket

  TypedCommandKind* = enum
    MovementCommand
    OperatorCommand
    SimpleCommand

  TypedCommand* = object
    case kind*: TypedCommandKind
    of MovementCommand:
      motion*: Motion
      count*: int
    of OperatorCommand:
      operator*: string # Keep as string for now
      target*: string # Keep as string for now
    of SimpleCommand:
      command*: string # Keep as string for now

  OperatorType* = enum
    ## Types of operators that can be combined with motions
    OpDelete # d - delete
    OpChange # c - change (delete and enter insert mode)
    OpYank # y - yank (copy)
    OpIndent # > - indent
    OpOutdent # < - outdent
    OpSwapCase # ~ - swap case
    OpLowerCase # gu - lowercase
    OpUpperCase # gU - uppercase

  OperatorRange* = object ## Range affected by an operator
    start*: BufferPosition
    endPos*: BufferPosition
    isLinewise*: bool # Whether the operation affects entire lines
    isEmpty*: bool # No-op range (e.g. inner of an empty tag): delete/yank affect nothing

  PendingOperator* = object
    ## Represents an operator waiting for a motion or text object
    operatorType*: OperatorType
    operatorCount*: int # Count before operator (2d3w の "2")
    startPos*: BufferPosition # Position where operator was invoked

  TextObjectKind* = enum
    ## Types of text objects
    toWord # w - word
    toWideWord # W - WORD (space-separated)
    toSentence # s - sentence
    toParagraph # p - paragraph
    toQuotedDouble # " - double quoted string
    toQuotedSingle # ' - single quoted string
    toQuotedBacktick # ` - backtick quoted string
    toParenthesis # ( or ) - parentheses
    toBracket # [ or ] - square brackets
    toBrace # { or } - curly braces
    toAngleBracket # < or > - angle brackets
    toTag # t - HTML/XML tag

  TextObjectModifier* = enum
    ## Modifiers for text objects
    tomInner # i - inner (excludes delimiters)
    tomAround # a - around (includes delimiters)

  TextObjectRange* = object ## Range of a text object
    start*: BufferPosition
    endPos*: BufferPosition
    isLinewise*: bool # Whether this is a linewise text object
    isEmpty*: bool
      # Empty object (e.g. inner of <a></a>): operators are no-ops, but `cit` still inserts

  PendingTextObject* = object
    ## Represents a text object selection waiting for the object type
    modifier*: TextObjectModifier # i or a
    operatorCount*: int # Count before operator (if any)

  LastEditCommandKind* = enum
    ## Types of repeatable edit commands
    lecOperatorMotion # Operator + motion (e.g., dw, c2w, y$)
    lecInsertText # Text inserted in insert mode
    lecReplaceChar # Character replacement with r command
    lecDeleteChar # Character deletion with x/X
    lecSubstitute # Substitute command (s/S)
    lecDeleteLine # Delete line(s) with dd
    lecChangeLine # Change line(s) with cc
    lecPaste # Paste operation (p/P)
    lecToggleCase # Toggle case with ~
    lecJoinLines # Join lines with J
    lecIndent # Indent line(s) with >>
    lecDedent # Dedent line(s) with <<

  LastEditCommand* = object
    ## Represents the last change command that can be repeated with "."
    case kind*: LastEditCommandKind
    of lecOperatorMotion:
      operator*: OperatorType # d, c, y, >, <, ~, gu, gU
      motion*: Motion # h, j, k, l, w, b, e, etc.
      motionCount*: int # Count for motion (3 in "d3w")
      motionHasCount*: bool # Explicit motion prefix? (dG vs d1G for `.`)
      operatorCount*: int # Count for operator (2 in "2dd")
      targetChar*: string # Target char for f/F/t/T motions (empty otherwise)
    of lecInsertText:
      insertedText*: string # Text that was inserted
      insertPosition*: BufferPosition # Where insertion started
    of lecReplaceChar:
      replaceChar*: string # Character used for replacement
      replaceCount*: int # Number of characters to replace
    of lecDeleteChar:
      deleteCount*: int # Number of characters to delete
      deleteForward*: bool # true for x, false for X
    of lecSubstitute:
      substituteText*: string # Text substituted
      substituteCount*: int # Number of characters or lines substituted
      substituteKind*: SubstituteKind # Whether it was s (char) or S/cc (line)
    of lecDeleteLine:
      deleteLineCount*: int # Number of lines to delete
    of lecChangeLine:
      changeLineCount*: int # Number of lines to change
    of lecPaste:
      pasteCount*: int # Number of times to paste
      pasteBefore*: bool # true for P (before), false for p (after)
    of lecToggleCase:
      toggleCaseCount*: int # Number of characters to toggle
    of lecJoinLines:
      joinLinesCount*: int # Number of lines to join
    of lecIndent:
      indentCount*: int # Number of indent levels
    of lecDedent:
      dedentCount*: int # Number of dedent levels

  VisualSelectionKind* = enum
    ## Type of visual selection
    vskChar # Character-wise selection (v)
    vskBlock # Block (column) selection (Ctrl-V)
    vskLine # Line-wise selection (V)

  VisualSelection* = object ## Represents a visual mode selection range
    start*: BufferPosition # Selection start position (anchor)
    current*: BufferPosition # Current cursor position (selection end)
    active*: bool # Whether selection is currently active
    kind*: VisualSelectionKind # Type of selection (char, block, line)

  SnippetStop* = object ## A tabstop of an active snippet, in buffer coordinates
    num*: int # Tabstop number; 0 is the final stop
    pos*: BufferPosition # Start of the placeholder default range
    len*: int # Rune length of the default (0 for bare `$n`)

  SnippetSession* = object ## Tab-cycling state for a committed snippet completion
    active*: bool # Whether a snippet session is in progress
    stops*: seq[SnippetStop] # Stops in cycle order (number ascending, $0 last)
    index*: int # Index of the current stop in stops
    defaultPending*: bool
      # Current stop's default is untouched (= selected); the next typed
      # character or Backspace replaces/deletes the whole default range

  ReplaceHistoryEntry* = object ## Replace mode history entry for undo with Backspace
    pos*: BufferPosition # Position where character was replaced
    originalChar*: string # Original character before replacement

  SubstituteKind* = enum
    ## Kind of substitute operation that led to Insert mode
    skChar # s command - substitute character(s)
    skLine # S or cc command - substitute line(s)

  SubstituteContext* = object
    ## Tracks context when Insert mode was entered via substitute command
    ## Used to properly record the command for repeat (.)
    kind*: SubstituteKind # Type of substitute operation
    deleteCount*: int # Number of characters or lines deleted

  VisualBlockInsertKind* = enum
    ## Kind of visual block insert operation
    vbiInsert # I — insert at block start column
    vbiAppend # A — append after block end column
    vbiChange # c — insert after block deletion

  VisualBlockInsertContext* = object
    ## Context for replicating inserted text across block-selected lines
    kind*: VisualBlockInsertKind
    startLine*: int # First line of the block selection
    endLine*: int # Last line of the block selection
    insertColumn*: int # Column where text should be inserted/replicated

  LspLocationItem* = object ## Single location item for LSP results display
    uri*: string # File URI
    path*: string # File path (extracted from URI)
    line*: int # Line number (0-indexed)
    column*: int # Column number (0-indexed)
    text*: string # Optional context text from the line

  LspLocationsResult* = object
    ## Collection of LSP location results (used for references, definitions, etc.)
    items*: seq[LspLocationItem]
    selectedIndex*: int # Currently selected item index
    title*: string # Title for the list (e.g., "References", "Definitions")

  CodeLensItem* = object ## Cached CodeLens item with display information
    line*: int # Line number (0-indexed)
    column*: int # Rune index in the line (UTF-16 already converted)
    title*: string # Display title (e.g., "5 references")
    command*: string # Command identifier
    arguments*: seq[string] # Command arguments (JSON strings)

  CodeLensCache* = object
    ## Cache for CodeLens items per buffer
    ## Uses Table for O(1) line lookup instead of O(n) sequential search
    itemsByLine*: Table[int, seq[CodeLensItem]] # Line number -> CodeLens items
    changeSeq*: int # Buffer changeSeq when cache was last updated
    filePath*: string # Path of the buffer this cache belongs to
    isValid*: bool # Whether the cache is valid

  CodeLensPicker* = object
    ## State for CodeLens selection UI when multiple items exist on a line
    items*: seq[CodeLensItem] # Items to choose from
    selectedIndex*: int # Currently selected index
    scrollOffset*: int # Scroll offset for displaying items (first visible item index)
    maxVisibleItems*: int # Maximum number of visible items (for scroll calculation)
    isActive*: bool # Whether the picker is currently shown

  DocumentHighlightItem* = object ## A single document highlight range
    line*: int # Line number (0-indexed)
    startColumn*: int # Start column (0-indexed)
    endColumn*: int # End column (0-indexed, exclusive)
    kind*: int # 1=Text, 2=Read, 3=Write (matches DocumentHighlightKind)

  DocumentHighlightCache* = object
    ## Cache for document highlights
    ## Uses Table for O(1) line lookup instead of O(n) sequential search
    itemsByLine*: Table[int, seq[DocumentHighlightItem]] # Line number -> items
    cursorLine*: int # Cursor line when highlights were requested
    cursorColumn*: int # Cursor column when highlights were requested
    changeSeq*: int # Buffer changeSeq when cache was last updated
    isValid*: bool # Whether the cache is valid

  SemanticTokensCache* = object
    ## Cache state for semantic tokens (LSP-based syntax highlighting)
    ## Actual SemanticTokens data is applied directly to buffer.highlight
    changeSeq*: int # Buffer changeSeq when semantic tokens were last applied
    filePath*: string # Path of the buffer this cache belongs to
    isValid*: bool # Whether semantic tokens have been applied to current highlight
    topLine*: int # Top visible line when tokens were requested
    bottomLine*: int # Bottom visible line when tokens were requested

  InlayHintItem* = object ## Cached inlay hint for a single position
    line*: int # Line number (0-indexed)
    column*: int # Rune index in the line (UTF-16 already converted)
    label*: string # Concatenated label text (from getInlayHintLabel)
    kind*: int # InlayHintKind: 1=Type, 2=Parameter, 0=unset
    paddingLeft*: bool # Whether to render a space before the label
    paddingRight*: bool # Whether to render a space after the label

  InlayHintCache* = object
    ## Cache for inlay hints over a viewport range
    ## Uses Table for O(1) line lookup instead of O(n) sequential search
    itemsByLine*: Table[int, seq[InlayHintItem]] # Line number -> inlay hints
    changeSeq*: int # Buffer changeSeq when cache was last updated
    filePath*: string # Path of the buffer this cache belongs to
    topLine*: int # Top visible line when hints were requested
    bottomLine*: int # Bottom visible line when hints were requested
    isValid*: bool # Whether the cache is valid

  SubstitutePreview* = object
    ## State for live substitute preview (like Vim's inccommand)
    isActive*: bool # Whether preview is currently active
    originalLines*: seq[string] # Snapshot of original buffer content
    lastPattern*: string # Last pattern used for preview
    lastReplacement*: string # Last replacement used for preview
    originalCursor*: BufferPosition # Cursor position when preview started
    originalTopLine*: int # Viewport top line when preview started
    originalLeftColumn*: int # Viewport left column when preview started

  PendingAsyncOps* = object
    ## Pending async operations queued from command/key handlers, drained by
    ## handler.handlePendingAsyncOperationsImpl in the main event loop.
    ## Empty-value semantics: `len == 0` / `false` means "no work pending".
    shellCommand*: string # Shell command to execute after suspend
    terminalCommand*: string # Command to run in a new embedded terminal tab
    background*: bool # Whether to suspend for background (:bg)
    manPage*: string # Man page to show after suspend (:man)
    buildOnSave*:
      tuple[path: string, language: int, customCmd: string, workspaceRoot: string]
    quickRun*: tuple[cmd: string, args: seq[string], filePath: string, isTempFile: bool]
    syntaxCheck*: tuple[path: string, language: int]

  UiState* = object ## Transient UI display state, refreshed by render/key events.
    substitutePreview*: SubstitutePreview
      # Live substitute preview (like Vim's inccommand)
    tempMessages*: seq[string] # Lines to display temporarily in command area
    lspProgressText*: string # Current LSP progress text for status line
    findCharMatches*: seq[int] # f/F/t/T match columns on the cursor line
    findCharMatchLine*: int # Line number of the matches

  PendingCommand* = enum
    PendingNone
    PendingWindowCmd # Ctrl-W prefix: waiting for window subcommand

  InputState* = object ## Command-line / search input state grouped together.
    commandText*: string # Text being typed in command mode
    commandCursor*: int
      # Cursor position within commandText (0-based, after the : prefix)
    search*: SearchState # Search-related state (text, history, settings)
    commandState*: CommandState # Command mode (ex-mode) state (history)

  JumpListState* = object ## Jump list navigation state (Ctrl-o / Ctrl-i).
    list*: seq[JumpPosition] # List of jump positions
    index*: int # Current position in jump list (-1 when not navigating)

  EditorState* = ref object
    activeWindow*: EditorWindow
      ## Reference to the currently active EditorWindow.
      ## cursor, mode, previousMode, preferredColumn, screenCursor are
      ## forwarded to this window via procs defined after the type block.
    cursorVisible*: bool # Whether the terminal cursor should be visible
    matchingParenPos*: Option[BufferPosition]
      # Position of matching paren (for highlighting)
    currentWord*: string # Word under cursor (for currentWord highlighting)
    pendingCommand*: PendingCommand
    statusMessageStr: string # Internal - use statusMessage getter/setter
    editState*: EditState # Edit operation state (operators, motions, repeat, etc.)
    visualSelection*: VisualSelection # Visual mode selection state
    snippetSession*: SnippetSession # Snippet tabstop cycling state (Insert mode)
    display*: DisplaySettings
    config*: EditorConfig
      ## Aliases `Editor.config`; kept in sync on swap in applyConfigSettings.
    timing*: TimingState
    lastKeyWasEscape*: bool
      # Track if last key was Escape (for double-Escape to clear highlight)
    # Full register system (vim-style)
    registers*: Registers # All registers (", 0-9, a-z, -, *, +)
    pendingRegister*: Option[char]
      # Register selected with " prefix (e.g., "a for register a)
    # Macro state (grouped in MacroState)
    macroState*: MacroState # Macro recording and playback state
    # QuickRun request flag
    requestQuickRun*: bool # Set by keybinding to request QuickRun execution
    # Command mode completion
    commandCompletionManager*: CommandCompletionManager
      # Command mode auto-completion manager
    # LSP cache state (grouped in LspCacheState)
    lspCache*: LspCacheState # LSP cache and picker state
    # Active syntax check results (for status message display)
    syntaxCheckResults*: tuple[path: string, errors: seq[SyntaxCheckError]]
    # LSP Rename state
    renameState*: RenameState # State for LSP rename mode
    # Overlay state for transient modes (Command, Search, Rename)
    # When set, the editor displays an overlay on top of the base mode
    overlay*: Option[OverlayKind]
    # Insert-Normal mode (Ctrl-o): execute one Normal command then return to Insert
    insertNormalMode*: bool
    # Startup window actions completed (runs once on first render)
    startUpWindowsDone*: bool
    # Notification popup manager
    notificationPopup*: NotificationPopupManager
    # Exit code (non-zero for :cq)
    exitCode*: int
    # --- Sub-state groups (Phase 4 refactor) ---
    input*: InputState # Command-line/search input state (text, cursor, history)
    jumpList*: JumpListState # Jump list navigation state (Ctrl-o / Ctrl-i)
    pending*: PendingAsyncOps # Pending async operations queued for the main event loop
    ui*: UiState # Transient UI display state (preview, progress, find char)
    windowDisplay*: WindowDisplayState
      # Window/buffer/redraw bookkeeping (current buf id, scroll, full-redraw)

  DebouncedLspPoll* = object
    ## Debounce + exponential backoff + request-time snapshot for a single LSP
    ## poll feature.  Shared across semantic tokens, inlay hints, code lens,
    ## and document highlight so every feature gets the same robustness:
    ## exponential backoff on persistent reject (#2880) and contentVersion
    ## stale-response drop (#2875).
    lastUpdate*: MonoTime
    interval*: int64
    rejectStreak*: int
    pendingRequestId*: int
    pendingFilePath*: string
    pendingChangeSeq*: int
    pendingContentVersion*: int
    generation*: int

const MaxLspDebounceBackoffShift* = 6
  ## Max exponent for the reject-streak backoff (interval << 6).

# State-based config pull-type accessors. Editor-based versions live in
# types/editor_types.nim. See docs/config_runtime_push_removal_design.md.

template flag2(name: untyped, T: typedesc, s1, f: untyped) =
  proc name*(s: EditorState): T =
    s.config.s1.f

  proc `name=`*(s: EditorState, v: T) =
    s.config.s1.f = v

template flag3(name: untyped, T: typedesc, s1, s2, f: untyped) =
  proc name*(s: EditorState): T =
    s.config.s1.s2.f

  proc `name=`*(s: EditorState, v: T) =
    s.config.s1.s2.f = v

flag2(showTabLine, bool, tabLine, enable)
flag2(showStatusLine, bool, standard, statusLine)
flag2(multiStatusLine, bool, statusLine, multipleStatusLine)
flag2(showLineNumbers, bool, standard, number)
flag2(relativeLineNumbers, bool, standard, relativeNumber)
flag2(showCursorLine, bool, highlight, currentLine)
flag2(showCursorColumn, bool, highlight, currentColumn)
flag2(showSyntax, bool, standard, syntax)
flag2(showIndentationLines, bool, standard, indentationLines)
flag2(showSidebar, bool, standard, sidebar)
flag2(scrollbar, bool, standard, scrollbar)
flag2(scrollbarWidth, int, standard, scrollbarWidth)
flag2(showModifiedLines, bool, standard, showModifiedLines)
flag2(showGitDiff, bool, git, showChangedLine)
flag2(showSyntaxChecker, bool, syntaxChecker, enable)
flag3(showCodeLens, bool, lsp, codeLens, enable)
flag3(showDocumentHighlight, bool, lsp, documentHighlight, enable)
flag3(showInlayHint, bool, lsp, inlayHint, enable)
flag2(lineWrap, bool, standard, lineWrap)
flag2(softTabStop, int, standard, softTabStop)

# tabStop / shiftWidth / expandTab: read prefers per-buffer .editorconfig
# overrides, write updates both the global config and the active buffer's
# override so `:set tabstop=N` is immediately visible even under an
# .editorconfig override (vim-compatible buffer-local `:set`). activeWindow
# may be nil in transient states (early init, teardown, test harnesses), so
# guard before dereferencing its buffer.
proc tabStop*(s: EditorState): int =
  if not s.activeWindow.isNil:
    let buf = s.activeWindow.buffer
    if not buf.isNil and buf.editorConfig.isSome and buf.editorConfig.get.tabStop.isSome:
      return buf.editorConfig.get.tabStop.get
  s.config.standard.tabStop

proc `tabStop=`*(s: EditorState, v: int) =
  s.config.standard.tabStop = v
  if not s.activeWindow.isNil:
    let buf = s.activeWindow.buffer
    if not buf.isNil and buf.editorConfig.isSome:
      buf.editorConfig.get.tabStop = some(v)

proc shiftWidth*(s: EditorState): int =
  if not s.activeWindow.isNil:
    let buf = s.activeWindow.buffer
    if not buf.isNil and buf.editorConfig.isSome and
        buf.editorConfig.get.shiftWidth.isSome:
      return buf.editorConfig.get.shiftWidth.get
  s.config.standard.shiftWidth

proc `shiftWidth=`*(s: EditorState, v: int) =
  s.config.standard.shiftWidth = v
  if not s.activeWindow.isNil:
    let buf = s.activeWindow.buffer
    if not buf.isNil and buf.editorConfig.isSome:
      buf.editorConfig.get.shiftWidth = some(v)

proc expandTab*(s: EditorState): bool =
  if not s.activeWindow.isNil:
    let buf = s.activeWindow.buffer
    if not buf.isNil and buf.editorConfig.isSome and
        buf.editorConfig.get.expandTab.isSome:
      return buf.editorConfig.get.expandTab.get
  s.config.standard.expandTab

proc `expandTab=`*(s: EditorState, v: bool) =
  s.config.standard.expandTab = v
  if not s.activeWindow.isNil:
    let buf = s.activeWindow.buffer
    if not buf.isNil and buf.editorConfig.isSome:
      buf.editorConfig.get.expandTab = some(v)

flag2(autoIndent, bool, standard, autoIndent)
flag2(smartIndent, bool, standard, smartIndent)
flag2(autoCloseParen, bool, standard, autoCloseParen)
flag2(autoDeleteParen, bool, standard, autoDeleteParen)
flag2(bracketSplit, BracketSplitMode, standard, bracketSplit)

# Forwarding procs: EditorState delegates cursor/mode/etc. to activeWindow.
# This eliminates the dual-state sync problem — EditorWindow is the single source of truth.

proc cursor*(s: EditorState): var BufferPosition =
  ## Get cursor position from the active window (returns var for in-place mutation)
  s.activeWindow.cursor

proc `cursor=`*(s: EditorState, pos: BufferPosition) =
  ## Set cursor position on the active window
  s.activeWindow.cursor = pos

proc mode*(s: EditorState): EditorMode =
  ## Get current mode from the active window
  s.activeWindow.mode

proc `mode=`*(s: EditorState, m: EditorMode) =
  ## Set current mode on the active window
  s.activeWindow.mode = m

proc previousMode*(s: EditorState): EditorMode =
  ## Get previous mode from the active window
  s.activeWindow.previousMode

proc `previousMode=`*(s: EditorState, m: EditorMode) =
  ## Set previous mode on the active window
  s.activeWindow.previousMode = m

proc preferredColumn*(s: EditorState): int =
  ## Get preferred column from the active window
  s.activeWindow.preferredColumn

proc `preferredColumn=`*(s: EditorState, v: int) =
  ## Set preferred column on the active window
  s.activeWindow.preferredColumn = v

proc screenCursor*(s: EditorState): var CursorPosition =
  ## Get screen cursor from the active window (returns var for in-place mutation)
  s.activeWindow.screenCursor

proc `screenCursor=`*(s: EditorState, v: CursorPosition) =
  ## Set screen cursor on the active window
  s.activeWindow.screenCursor = v

proc `==`*(a, b: ViewPort): bool =
  ## Structural equality for ViewPort (ref object defaults to pointer comparison)
  if a.isNil and b.isNil:
    return true
  if a.isNil or b.isNil:
    return false
  a.topLine == b.topLine and a.topWrapOffset == b.topWrapOffset and
    a.leftColumn == b.leftColumn and a.width == b.width and a.height == b.height and
    a.x == b.x and a.y == b.y

proc resetViewportTop*(v: ViewPort, line = 0) =
  ## Move the viewport to `line` and clear the wrap-segment offset. Used by
  ## every non-authoritative topLine writer (scroll commands, buffer/file
  ## switches, restores): the offset is recomputed next frame by the
  ## authoritative `adjustViewportForCursor`, so resetting it to 0 here is
  ## enough to avoid starting a fresh top line mid wrap segment.
  v.topLine = line
  v.topWrapOffset = 0

proc statusMessage*(state: EditorState): string =
  ## Get the current status message
  state.statusMessageStr

proc `statusMessage=`*(state: EditorState, msg: string) =
  ## Set status message and automatically log non-empty messages
  state.statusMessageStr = msg
  if msg.len > 0:
    addMessageLog(msg)
    logDebug("editorMessage", msg)

proc setStatusQuiet*(state: EditorState, msg: string) =
  ## Set the status message *without* the logging side effects of the
  ## `statusMessage=` setter (no addMessageLog / logDebug). Use this in tests
  ## and hot paths where the message should not be appended to the message log
  ## or the debug log.
  state.statusMessageStr = msg

const MaxStatusMessageLines* = 10
  ## Maximum lines for multi-line status messages to prevent viewport from disappearing

proc statusMessageLineCount*(state: EditorState): int =
  ## Count the number of lines in the status message
  ## Returns 0 if empty, otherwise count of lines (newlines + 1)
  if state.statusMessageStr.len == 0:
    0
  else:
    min(state.statusMessageStr.count('\n') + 1, MaxStatusMessageLines)

# Overlay accessors

proc hasOverlay*(state: EditorState): bool =
  ## Check if an overlay is currently active
  state.overlay.isSome

proc isCommandOverlay*(state: EditorState): bool =
  ## Check if command overlay is active
  state.overlay == some(okCommand)

proc isSearchOverlay*(state: EditorState): bool =
  ## Check if search overlay is active
  state.overlay == some(okSearch)

proc isRenameOverlay*(state: EditorState): bool =
  ## Check if rename overlay is active
  state.overlay == some(okRename)

proc enterCommandOverlay*(state: EditorState) =
  ## Enter command mode overlay
  ## The base mode (Normal, Filer, etc.) is preserved
  state.overlay = some(okCommand)
  state.input.commandText = ":"
  state.input.commandCursor = 0
  state.input.commandState.historyIndex = -1
  state.input.commandState.historyPrefix = ""

proc enterSearchOverlay*(state: EditorState, direction: SearchDirection) =
  ## Enter search mode overlay
  ## The base mode (Normal, LogViewer, etc.) is preserved
  state.overlay = some(okSearch)
  state.input.search.direction = direction
  state.input.search.text = ""
  state.input.search.cursor = 0
  state.input.search.startPos = state.cursor
  state.input.search.historyIndex = -1
  # Re-enable search highlight so incremental search results are visible
  state.input.search.hlsearchTempDisabled = false
  # Reset whole word mode so / and ? use regex matching consistently
  # (wholeWord may be true from a previous * or # command)
  state.input.search.wholeWord = false

proc enterRenameOverlay*(state: EditorState, word: string, line, col: int) =
  ## Enter rename mode overlay
  ## The base mode (Normal) is preserved
  state.overlay = some(okRename)
  state.renameState.text = word
  state.renameState.originalWord = word
  state.renameState.cursorLine = line
  state.renameState.cursorColumn = col

proc exitOverlay*(state: EditorState) =
  ## Exit the current overlay and return to the base mode
  if state.overlay.isSome:
    state.overlay = none(OverlayKind)
    # Clear overlay-specific state
    state.input.commandText = ""
    state.input.commandCursor = 0
    state.input.commandState.historyIndex = -1
    state.input.commandState.historyPrefix = ""
    state.input.search.text = ""
    state.input.search.cursor = 0
    state.input.search.historyIndex = -1

proc baseMode*(state: EditorState): EditorMode =
  ## Get the base mode (the mode under the overlay)
  ## With overlays, state.mode always holds the base mode
  state.mode

proc modeStateKind*(mode: EditorMode): ModeStateKind =
  ## Map an `EditorMode` to the `ModeStateKind` it expects on `EditorWindow`.
  ## Modes that do not own per-window state (Normal/Insert/Visual/... and
  ## the QuickRun/Command/Replace/Replace/Search overlay modes) return
  ## `mskNone`.
  case mode
  of EditorMode.Filer: mskFiler
  of EditorMode.FileTree: mskFileTree
  of EditorMode.LogViewer: mskLogViewer
  of EditorMode.Help: mskHelp
  of EditorMode.BufferManager: mskBufferManager
  of EditorMode.BookmarkManager: mskBookmarkManager
  of EditorMode.BackupManager: mskBackupManager
  of EditorMode.DiffViewer: mskDiffViewer
  of EditorMode.Debug: mskDebug
  of EditorMode.Config: mskConfig
  of EditorMode.References: mskReferences
  of EditorMode.DocumentSymbol: mskDocumentSymbol
  of EditorMode.CallHierarchy: mskCallHierarchy
  of EditorMode.RecentFile: mskRecentFile
  of EditorMode.Terminal: mskTerminal
  else: mskNone

proc resetPending*(poll: var DebouncedLspPoll) =
  poll.pendingRequestId = 0
  poll.pendingFilePath = ""
  poll.pendingChangeSeq = -1
  poll.pendingContentVersion = -1

proc debounceThreshold*(poll: DebouncedLspPoll): times.Duration =
  let shift = min(poll.rejectStreak, MaxLspDebounceBackoffShift)
  initDuration(milliseconds = poll.interval shl shift)

proc initDebouncedLspPoll*(interval: int64): DebouncedLspPoll =
  result = DebouncedLspPoll(lastUpdate: getMonoTime(), interval: interval)
  result.resetPending()
