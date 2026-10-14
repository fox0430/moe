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

import celina_backend as celina

import
  modes,
  buffer,
  types/registers_types,
  types/filer_types,
  types/filetree_types,
  types/log_viewer_types,
  types/help_viewer_types,
  types/command_completion_types,
  message_log,
  logger,
  types/buffer_manager_types,
  types/bookmark_manager_types,
  types/backup_manager_types,
  types/recovery_manager_types,
  types/diff_viewer_types,
  types/debug_viewer_types,
  types/config_mode_types,
  types/references_viewer_types,
  types/documentsymbol_viewer_types,
  types/callhierarchy_viewer_types,
  types/hover_popup_types,
  types/notification_popup_types,
  primitives,
  types/syntax_checker_types,
  types/recent_file_mode_types,
  types/git_cache_types,
  types/key_combo_types,
  config

when not defined(moe.embedded):
  import types/terminal_mode_types

from lsp/protocol/types import SemanticTokensLegend
from cursor_util import clampCursorToLastChar, adjustCursorAfterInsertExit

export
  buffer.LineMarkerKind, registers_types, command_completion_types, filer_types,
  filetree_types, log_viewer_types, help_viewer_types, buffer_manager_types,
  bookmark_manager_types, backup_manager_types, recovery_manager_types,
  diff_viewer_types, debug_viewer_types, config_mode_types, references_viewer_types,
  documentsymbol_viewer_types, callhierarchy_viewer_types, hover_popup_types,
  notification_popup_types, primitives, syntax_checker_types, recent_file_mode_types,
  key_combo_types, config.BracketSplitMode

when not defined(moe.embedded):
  export terminal_mode_types

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
      ## Leading wrap segments of `topLine` skipped (wrap mode only, else 0).
    detachedFromCursor*: bool
      ## True while pointer scrolling controls the viewport independently of
      ## the logical cursor. Cursor or programmatic viewport movement clears it.
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
    viewportReservedLines*: int = -1
      ## Reserved rows outside text area. `-1` is unset; `0` is valid. Use `motionReservedLines`.
    scrollAnimation*: ScrollAnimation # Current scroll animation state

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
    mskRecoveryManager
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
    of mskRecoveryManager: recoveryManager*: RecoveryManagerState
    of mskDiffViewer:
      diffViewer*: DiffViewerState
      diffReturn*: BackupManagerState
        ## The backup manager the diff was opened from, resumed on quit. Held
        ## here so tearing down the window's state drops it too.
    of mskDebug: debug*: DebugViewerState
    of mskConfig: config*: ConfigModeState
    of mskReferences: references*: ReferencesViewerState
    of mskDocumentSymbol: documentSymbol*: DocumentSymbolViewerState
    of mskCallHierarchy: callHierarchy*: CallHierarchyViewerState
    of mskRecentFile: recentFile*: RecentFileModeState
    of mskTerminal:
      when defined(moe.embedded):
        discard
      else:
        terminal*: TerminalState
        scrollbackSnapshot*: TextBuffer
          ## This window's Terminal-Normal copy of the session; nil while its
          ## keys go to the session. Leaving the tab drops it with the variant.

  ViewerPlacement* = enum
    ## Where a viewer's listing goes. Either way it covers a window's tab in
    ## place; a split opens that window for it and closes it on exit.
    vpInPlace ## Covered the active window
    vpVSplit
    vpHSplit

  ViewerEntry* = object
    ## What a viewer entry has to undo on exit. `mode` makes the record
    ## self-identifying so an unrelated teardown cannot consume it.
    mode*: EditorMode
    placement*: ViewerPlacement
    returnMode*: EditorMode
    returnState*: ModeState
      ## `returnMode`'s variant (a Terminal session, a FileTree), taken with it
      ## so the two resume as one unit. The view is derived from it and the
      ## tab on exit, so no buffer the viewer covered is kept here.
    returnTab*: BufferId
      ## The tab the viewer covered. What it covered resumes only while the
      ## window is still on it.
    originCursor*: BufferPosition
    originTopLine*: int
    originTopWrapOffset*: int
    originLeftColumn*: int

  EditorWindow* = ref object
    ## Represents a split window with its own buffer and viewport
    viewBuffer*: TextBuffer
      # What the window draws; a mode may swap in an unregistered view
      # (Terminal-Normal snapshot, Filer listing). Read it as `win.buffer`.
    tabBufferId*: BufferId
      # The tab the window is parked on. Changes on a tab switch only.
    bufferIds*: seq[BufferId]
      # Window-local tab list, stored as stable BufferIds.
      # Resolve via Editor.bufferById; entries pointing at deleted buffers
      # are pruned in the bdelete path.
    viewport*: ViewPort
    cursor*: BufferPosition # Window-local cursor position
    visualAnchor*: BufferPosition
      # Where the window's Visual selection started; the cursor is its other end.
    holdLastVisual: bool
      # Set from `saveLastVisualAhead` to `settleLastVisual`. The area was saved
      # for `gv` before the edit moved it, so leaving Visual keeps it.
    active*: bool # Whether this is the active window
    mode*: EditorMode
      # Current mode for this window. Enter a Visual mode through `setMode`,
      # which puts the anchor on the cursor.
    previousMode*: EditorMode # Previous mode for ESC handling
    wantedColumn: Option[int] # Read through `preferredColumn`
    wantedColumnSince: WindowSpot
      # Where the window stood when its command began or it last kept a column.
    screenCursor*: CursorPosition # Screen cursor position (x/y)
    modeState*: ModeState # Per-window mode-specific state (variant)
    viewerEntry*: Option[ViewerEntry]
      # Set by enterViewerMode, consumed by leaveViewerMode.
    fixedWidth*: Option[int] # Fixed width for sidebar windows (skips equalize)
    wrapCountCache*: WrapCountCache

  WindowSpot = object
    cursor: BufferPosition
    buffer: TextBuffer
    version: int

  SearchDirection* = enum
    Forward # Search forward (/)
    Backward # Search backward (?)

  SearchSpec* = object
    ## One executed search: the pattern and the options it ran with. n/N, gn,
    ## an empty `/` and the highlighter all replay this value, so they cannot
    ## disagree about what counts as a match.
    pattern*: string
    wholeWord*: bool # Match whole words only (* and #); matches literally

  SearchState* = object ## Search-related state grouped together for better organization
    text*: string # Text being typed in search mode
    cursor*: int # Cursor position within text (0-based character index)
    last*: SearchSpec # Last executed search, replayed by n/N and an empty `/`
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

  CommandState* = object ## Command mode (ex-mode) state grouped together
    history*: seq[string] # Command history (most recent first)
    historyIndex*: int # Current position in command history (-1 when not navigating)
    historyPrefix*: string
      # Prefix captured when history navigation started; only entries starting
      # with this prefix are surfaced by Up/Down. Empty means "match any".

  MacroRecording* = object ## One `q<reg>...q` session
    register*: char # Register (a-z) being recorded to
    keys*: seq[string] # Typed keys so far

  MacroState* = object ## Macro recording and playback state grouped together
    recording*: Option[MacroRecording]
    registers*: Table[char, seq[string]] # Saved macros by register
    lastRegister*: Option[char] # Last executed macro register for @@
    playbackDepth*: int # Current macro recursion depth
    executingDepth*: int # Registers (`@x`) being run, like Vim's reg_executing

  LastFindChar* = object
    ## Last f/F/t/T motion, replayed by ; (same direction) and , (reversed)
    motion*: Motion # FindChar / FindCharBackward / TillChar / TillCharBackward
    targetChar*: string

  EditState* = object ## Edit operation state grouped together
    lastEditCommand*: Option[LastEditCommand] # Last change command for . (repeat)
    insertRecord*: InsertRecord # What `.` repeats for lecInsert
    changeBefore*: tuple[command: Option[LastEditCommand], record: InsertRecord]
      # What `.` repeated before the Insert record started, which Ctrl-o reads
    lastInserted*: Option[seq[TypedInput]]
      # What Ctrl-A and Ctrl-@ type again, none before any insert
    typing*: InsertTyping # The recorder of the Insert session under way
    lastFindChar*: Option[LastFindChar] # Last f/F/t/T for ; and , repeat
    replaceHistory*: seq[ReplaceHistoryEntry] # Replace mode undo history
    visualBlockInsertContext*: Option[VisualBlockInsertContext]
      # Context for visual block insert/append/change replication
    autoIndentedLine*: Option[AutoIndentedLine]

  PendingSemanticTokensRequest* = object
    ## Semantic-tokens-specific extras (legend, viewport, range) captured at
    ## request-send time. The generic stale-guard snapshot (request-id,
    ## file-path, change-seq, content-version) lives in
    ## `LspCacheState.pending[lrfSemanticTokens]` as of Phase D.
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

  LspRequestFeature* = enum
    ## All LSP request kinds.
    lrfHover
    lrfSignatureHelp
    lrfCompletion
    lrfCompletionResolve
    lrfSelectionRange
    lrfDocumentSymbol
    lrfDocumentLink
    lrfDocumentLinkResolve
    lrfDefinition
    lrfDeclaration
    lrfReferences
    lrfTypeDefinition
    lrfImplementation
    lrfCodeLens
    lrfInlayHint
    lrfDocumentHighlight
    lrfSemanticTokens
    lrfCallHierarchyPrepareIncoming
    lrfCallHierarchyPrepareOutgoing
    lrfCallHierarchyIncoming
    lrfCallHierarchyOutgoing
    lrfFormatting
    lrfRename
    lrfFoldingRange
    lrfCodeLensResolve
    lrfExecuteCommand

  LspRequestContext* = object ## Snapshot of the world at request-send time.
    requestId*: int
    feature*: LspRequestFeature
    bufferId*: BufferId
    contentVersion*: int
    path*: string
    generation*: int
    cursorLine*: int # -1 = not cursor-anchored
    cursorCol*: int # -1 = not cursor-anchored
    validModes*: set[EditorMode] # empty = any mode
    isItemDriven*: bool
      # Item-driven requests target an LSP item (e.g. CallHierarchyItem) rather
      # than the active buffer's cursor. classifyResponse skips the
      # buffer/version guard for these; the caller supplies its own guard.
    ignoreContentVersion*: bool
      # Skip the contentVersion drift check; for features whose response
      # stays meaningful across in-flight edits (e.g. signature help).
    blockedByOverlay*: bool
      # Applying the response takes over the screen (popup, mode switch, jump),
      # so an open overlay (Command/Search/Rename) must drop it. False for
      # background caches, which only feed the buffer painted under the overlay.

  LspResponseState* = enum
    lrsFresh # buffer/version/mode all match
    lrsStale # contentVersion drifted since send
    lrsGone # bufferId no longer exists
    lrsHijack # mode outside validModes
    lrsOverlay # an overlay owns the screen and would be painted over

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
    signatureHelpPoll*: DebouncedLspPoll
      # Debounce / backoff / request-target snapshot for auto signature help.
    autoHoverPoll*: DebouncedLspPoll
      # Debounce / cursor snapshot for the diagnostic auto-hover popup. The
      # interval is pulled from config on every check (Lsp.Diagnostics
      # autoHoverDelay) and no request is sent, so the backoff never engages.
    # Selection range expansion chain (innermost -> outermost), rune indexes.
    # Lets repeated Ctrl-s walk the parent chain without re-querying the server.
    selectionRangeChain*: seq[tuple[first, last: BufferPosition]]
    selectionRangeIndex*: int # Current level in the chain (0 = innermost)
    # Consolidated stale-guard registry; migrated to per-feature entries as
    # each feature moves off the pending* fields above.
    pending*: Table[LspRequestFeature, LspRequestContext]
    featureGeneration*: array[LspRequestFeature, int]

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
    gitDiffUpdateInterval*: int64
      # Minimum milliseconds between git diff refresh cycles. Consumed by
      # EditorState.git via setGitDiffRefreshInterval.
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
    useRegOne*: bool # A delete goes to "1 even within a line (Vim's use_reg_one)

  PendingOperator* = object
    ## Represents an operator waiting for a motion or text object
    operatorType*: OperatorType
    operatorCount*: int # Count before operator (2d3w の "2")
    countGiven*: bool # A count was typed before the operator (`3dG`)
    startPos*: BufferPosition # Position where operator was invoked
    register*: Option[char] # Register named by `"x` before the operator
    topLine*: int # The viewport's top line then, which the change puts back

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
    exclusive*: bool
      ## `endPos` is where the object stops, not its last character: an
      ## operator takes the text before it by the `:h exclusive` rules (an
      ## inner block whose closing bracket starts its line)

  PendingTextObject* = object
    ## Represents a text object selection waiting for the object type
    modifier*: TextObjectModifier # i or a
    count*: int # Count typed on the modifier (`d2iw`), 1 if none
    countGiven*: bool

  OperandKind* = enum
    odMotion ## A cursor motion, f/F/t/T with their character
    odMark ## ' or ` to a named mark
    odCommand ## A registered command that finds a place (n, *, gn)
    odTextObject

  Operand* = object ## What a waiting operator acts over, kept so `.` finds it again
    count*: int ## The operator's and the motion's counts multiplied (`2d3w`: 6)
    countGiven*: bool
      ## Either was typed (`dG` goes to the last line, `1dG` to the first)
    case kind*: OperandKind
    of odMotion:
      motion*: Motion
      targetChar*: string
    of odMark:
      markName*: char
      markLinewise*: bool
    of odCommand:
      commandId*: string
    of odTextObject:
      textObjectModifier*: TextObjectModifier
      textObjectKind*: TextObjectKind

  AutoIndentedLine* = object ## A line Insert mode indented by itself
    line*: int
    version*: int
      # contentVersion once the indent went in: while it holds, nothing was
      # typed there, and Escape, Enter or a move takes the indent off

  InsertEntryKind* = enum
    ## The command a change entered Insert mode with, which `.` runs again
    ieInsert # i, and the plain insert a move before typing starts
    ieAppend # a
    ieAppendEnd # A
    ieInsertNonBlank # I
    ieOpenBelow # o
    ieOpenAbove # O
    ieSubstitute # s
    ieSubstituteLine # S, cc
    ieChangeToEnd # C
    ieChange # c{motion}

  InsertEntry* = object
    case kind*: InsertEntryKind
    of ieChange:
      operand*: Operand
    else:
      discard

  InsertRecord* = object
    ## The Insert-mode change `.` repeats: the entry command, its count and
    ## what was typed.
    entry*: InsertEntry
    count*: int
    typed*: seq[TypedInput]

  InsertTyping* = object ## The recorder of the Insert session under way
    open*: bool # What is typed now goes on `insertRecord`
    repeatsLeft*: int # Times Escape types the record again ([count]i)
    repeating*: bool # Those repeats run, and their keys are not typing
    linesBelow*: int # Lines below where typing started, which it leaves as they are
    lastCursor*: BufferPosition # Where the last key left the cursor
    lastVersion*: int # and the buffer's contentVersion

  LastEditCommandKind* = enum
    ## Types of repeatable edit commands
    lecOperatorMotion # Operator + motion (e.g., dw, d2w, y$)
    lecInsert # A change made in Insert mode, kept in EditState.insertRecord
    lecReplaceChar # Character replacement with r command
    lecVisualReplace # Visual-mode replace (r) with recorded selection shape
    lecDeleteChar # Character deletion with x/X
    lecDeleteLine # Delete line(s) with dd
    lecPaste # Paste operation (p/P/gp/gP)
    lecToggleCase # Toggle case with ~
    lecJoinLines # Join lines with J
    lecOperatorLines # Doubled linewise operator (>>, <<, guu, gUU)

  LastEditCommand* = object
    ## Represents the last change command that can be repeated with "."
    register*: Option[char] ## Register named by `"x` for the change
    case kind*: LastEditCommandKind
    of lecOperatorMotion:
      operator*: OperatorType # d, c, y, >, <, ~, gu, gU
      operand*: Operand
    of lecInsert:
      discard
    of lecReplaceChar:
      replaceChar*: string # Character used for replacement
      replaceCount*: int # Number of characters to replace
    of lecVisualReplace:
      visualReplaceChar*: string # Replacement character
      visualReplaceKind*: VisualSelectionKind # Recorded selection shape
      visualReplaceRows*: int # Line/row span (1 for single-line charwise)
      visualReplaceCols*: int
        # Single-line charwise: width from cursor;
        # multi-line charwise: last-line width from col 0; linewise: unused;
        # blockwise: block width.
    of lecDeleteChar:
      deleteCount*: int # Number of characters to delete
      deleteForward*: bool # true for x, false for X
    of lecDeleteLine:
      deleteLineCount*: int # Number of lines to delete
    of lecPaste:
      pasteCount*: int # Number of times to paste
      pasteBefore*: bool # true for P/gP (before), false for p/gp (after)
      pasteCursorAfter*: bool # true for gp/gP
    of lecToggleCase:
      toggleCaseCount*: int # Number of characters to toggle
    of lecJoinLines:
      joinLinesCount*: int # Number of lines to join
    of lecOperatorLines:
      linesOperator*: OperatorType # OpIndent, OpOutdent, OpLowerCase, OpUpperCase
      operatorLineCount*: int # Number of lines the operator was applied to

  VisualSelection* = object
    ## A window's Visual selection, derived from its anchor, cursor and mode.
    start*: BufferPosition # Anchor
    current*: BufferPosition # Cursor
    active*: bool # False outside the Visual modes
    kind*: VisualSelectionKind # Follows the Visual mode

  PointerSelectionGranularity* = enum
    ## Unit established by the primary-button press for the rest of a gesture.
    psgCharacter
    psgWord
    psgLine
    psgBlock

  PointerSelectionGesture* = object
    ## Transient pointer-selection state. The buffer identity prevents a drag
    ## from applying an anchor to another split or a newly switched tab.
    active*: bool
    windowIndex*: int
    bufferId*: BufferId
    anchorFirst*: BufferPosition
    anchorLast*: BufferPosition
    granularity*: PointerSelectionGranularity
    extendMode*: bool
    selectionStarted*: bool

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

  InsertResume* = enum
    ## Insert to resume after the Normal command Ctrl-o runs (Vim's restart_edit).
    irNone # Nothing to resume
    irWaiting # Set by Ctrl-o; the command it waits for has not started
    irArmed # That command has started; Insert resumes once it is done
    irHeld # Kept through a mapping that started in Visual mode (old_mapped_len)

  ReplaceHistoryEntryKind* = enum
    rheReplace # Character replacement (or end-of-line insertion)
    rheNewline # Line split via Enter

  ReplaceHistoryEntry* = object ## Replace mode history entry for undo with Backspace
    pos*: BufferPosition # Position anchoring the operation
    case kind*: ReplaceHistoryEntryKind
    of rheReplace:
      originalChar*: string # Original char (empty when it was an end-of-line insert)
    of rheNewline:
      discard

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
    firstLineLen*: int ## Characters on the first line when the insert began

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
    contentVersion*: int # Buffer contentVersion when cache was last updated
    filePath*: string # Path of the buffer this cache belongs to
    bufferId*: BufferId
      ## Buffer this cache was built from; `BufferId(0)` while unpopulated.
      ## Held beside `filePath`, which is reused across loads and empty for a
      ## buffer without a file.
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
    bufferId*: BufferId # Buffer this cache was built from (see CodeLensCache)
    cursorLine*: int # Cursor line when highlights were requested
    cursorColumn*: int # Cursor column when highlights were requested
    contentVersion*: int # Buffer contentVersion when cache was last updated
    isValid*: bool # Whether the cache is valid

  SemanticTokensCache* = object
    ## Cache state for semantic tokens (LSP-based syntax highlighting)
    ## Actual SemanticTokens data is applied directly to buffer.highlight
    changeSeq*: int # Buffer changeSeq when semantic tokens were last applied
    filePath*: string # Path of the buffer this cache belongs to
    bufferId*: BufferId # Buffer this cache was built from (see CodeLensCache)
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
    bufferId*: BufferId # Buffer this cache was built from (see CodeLensCache)
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

  BuildInfo* =
    tuple
      path: string
      language: int
      customCmd: string
      workspaceRoot: string
      # `automatic` marks a `buildOnSave` run, which keeps the user's focus
      # and mode.
      automatic: bool
  QuickRunInfo* =
    tuple[cmd: string, args: seq[string], filePath: string, workDir: string]
  SyntaxCheckInfo* = tuple[path: string, language: int]
  FilterInfo* =
    tuple[
      bufferId: BufferId,
      windowIndex: int,
      command: string,
      first: int,
      last: int,
      contentVersion: int,
    ]
    ## A buffer range to hand to a command. The run is asynchronous, so the
    ## lines fed in and the output put back are gated on `contentVersion`.
    ##
    ## `windowIndex` is the window the command was typed in, the only one that
    ## follows the output. It is a hint: splits can come and go meanwhile.

  PendingAsyncOpKind* = enum
    paoTerminalCommand
    paoShellCommand
    paoManPage
    paoBackground
    paoQuickRun
    paoFilter

  PendingAsyncOp* = object
    ## One entry of `EditorState.pending`. Queue an op here when it needs the
    ## TUI suspended, or when its runner lives above the enqueue site in the
    ## import graph (handler.nim owns the runners). Fire-and-forget work whose
    ## runner is importable uses `asyncSpawn` at the call site instead.
    epoch*: uint64
      # Command epoch captured when the op was queued. QuickRun checks it, so a
      # `:jobs!` between queueing and spawning still stops the run.
    case kind*: PendingAsyncOpKind
    of paoTerminalCommand, paoShellCommand, paoManPage:
      command*: string
    of paoBackground:
      discard
    of paoQuickRun:
      quickRun*: QuickRunInfo
    of paoFilter:
      filter*: FilterInfo

  FrontendRequests* = object
    ## Frontend-side effects requested by editor-core state changes.
    ## Frontends drain these requests from their own event/render loop.
    mouseCapture*: Option[bool]

  FrontendSubscriptions* = object
    ## Optional editor data maintained for an embedding frontend.
    gitStatus*: bool

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

  PendingInputState* = object
    ## Pending-input FSMs cleared together on Escape. KeyRouter's built-in
    ## sequence accumulator stays registry-owned; isActive/cancelAll composes both.
    macroState*: MacroState
    pendingOperator*: Option[PendingOperator]
    pendingTextObject*: Option[PendingTextObject]
    pendingCommand*: PendingCommand # Ctrl-W etc.

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
    statusMessageStr: string # Internal - use statusMessage getter/setter
    editState*: EditState # Edit operation state (motions, repeat, etc.)
    pointerSelection*: PointerSelectionGesture
      ## Primary-button gesture currently owned by the editor.
    snippetSession*: SnippetSession # Snippet tabstop cycling state (Insert mode)
    config*: EditorConfig ## Aliases `Editor.config`; never reassigned.
    timing*: TimingState
    git*: GitCacheState # Per-buffer git diff/branch cache (see git_cache.nim)
    lastKeyWasEscape*: bool
      # Track if last key was Escape (for double-Escape to clear highlight)
    # Full register system (vim-style)
    registers*: Registers # All registers (", 0-9, a-z, -, *, +)
    pendingInput*: PendingInputState # See pending_input.nim for isActive/cancelAll.
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
    # Set by Ctrl-o until Insert resumes or is given up (settleInsertResume)
    insertResume*: InsertResume
    # Line Ctrl-o was typed past the end of (Vim's ins_at_eol)
    insertResumeLineEnd*: Option[int]
    # Ctrl-o came while the Insert change was still being typed, so `.`
    # repeats the change before it
    insertResumeInChange*: bool
    # Startup window actions completed (runs once on first render)
    startUpWindowsDone*: bool
    # Notification popup manager
    notificationPopup*: NotificationPopupManager
    # Exit code (non-zero for :cq)
    exitCode*: int
    quitDecided*: bool
      ## Once set, a signal or crash no longer preserves buffers, and the loop
      ## only waits for the hooks the quit owes.
    # --- Sub-state groups (Phase 4 refactor) ---
    input*: InputState # Command-line/search input state (text, cursor, history)
    jumpList*: JumpListState # Jump list navigation state (Ctrl-o / Ctrl-i)
    pending*: seq[PendingAsyncOp] # Async ops drained by the main event loop
    commandEpoch*: uint64
      # Bumped when the user stops the external commands. Each command captures
      # it when queued and re-checks after every await, so work in flight stops
      # at its next step; emptying the queues cannot reach that work.
    exitReports*: seq[string]
      # What went wrong while the quit waited, written to stderr once the
      # screen is gone.
    exitWaitStartedAt*: Option[MonoTime]
      # When the quit began waiting for the hooks it owes, so `exitWaitTimeout`
      # measures the wait rather than the frames that notice it.
    commandOutputBufferId*: BufferId
      # Buffer a background command last wrote its output into; reused while a
      # window shows it, so frequent runs do not add a split each time.
    frontend*: FrontendRequests # Frontend-side effect requests
    frontendSubscriptionsState: FrontendSubscriptions
    ui*: UiState # Transient UI display state (preview, progress, find char)
    windowDisplay*: WindowDisplayState
      # Window/buffer/redraw bookkeeping (current buf id, scroll, full-redraw)
    inactiveHighlightScanIndex*: int
      # Round-robin start index for `updateForFrame`'s inactive-buffer
      # highlight budget, so a buffer with sustained work cannot starve the
      # buffers behind it.

  DebouncedLspPoll* = object
    ## Debounce + exponential backoff timer for a single LSP poll feature.
    ## Shared across semantic tokens, inlay hints, code lens, document
    ## highlight, signature help and diagnostic auto-hover so every feature
    ## gets the same rate-limiting: exponential backoff on persistent reject
    ## (#2880).
    ##
    ## "Debounce" is a minimum-interval gate measured from the last issued
    ## request, not a reset-on-change timer.
    ##
    ## The per-request stale-guard snapshot (request id, buffer id, content
    ## version, generation) lives in `LspCacheState.pending`.
    lastUpdate*: MonoTime
    interval*: int64
    rejectStreak*: int
    cursorLine*: int
    cursorColumn*: int
    contentVersion*: int
      # Target the last request was issued for, for the features that need
      # change detection on top of the timer (signature help, auto-hover).
      # Sentinel -1 means "no request issued yet".

const MaxLspDebounceBackoffShift* = 6
  ## Max exponent for the reject-streak backoff (interval << 6).

# There is no `buffer=` on purpose: every write picks one of these three, so
# the call site says whether it is a tab switch or a view swap.

proc buffer*(win: EditorWindow): TextBuffer {.inline.} =
  win.viewBuffer

proc setTab*(win: EditorWindow, buf: TextBuffer) {.inline.} =
  ## Move the window to another tab: view and identity change together.
  win.viewBuffer = buf
  win.tabBufferId = buf.id

proc retabTo*(win: EditorWindow, buf: TextBuffer) {.inline.} =
  ## Move the tab while a mode holds a view up, for a tab deleted underneath
  ## one. The mode restores `buf` when it exits.
  win.tabBufferId = buf.id

proc setView*(win: EditorWindow, buf: TextBuffer) {.inline.} =
  ## Swap what the window draws without moving it off its tab.
  win.viewBuffer = buf

# State-based config pull-type accessors. Editor-based versions live in
# types/editor_types.nim.

template flag2(name: untyped, T: typedesc, s1, f: untyped) =
  proc name*(s: EditorState): T =
    s.config.s1.f

  proc `name=`*(s: EditorState, v: T) =
    s.config.s1.f = v

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

# Search flags: write both `config.standard.*` and the `input.search.*` mirror.
# Skipping the config write lets the next `applyConfigSettings` push undo the toggle.
proc ignorecase*(s: EditorState): bool =
  s.input.search.ignorecase

proc `ignorecase=`*(s: EditorState, v: bool) =
  s.config.standard.ignorecase = v
  s.input.search.ignorecase = v

proc smartcase*(s: EditorState): bool =
  s.input.search.smartcase

proc `smartcase=`*(s: EditorState, v: bool) =
  s.config.standard.smartcase = v
  s.input.search.smartcase = v

proc incsearch*(s: EditorState): bool =
  s.input.search.incsearch

proc `incsearch=`*(s: EditorState, v: bool) =
  s.config.standard.incrementalSearch = v
  s.input.search.incsearch = v

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

proc clampedAnchor*(win: EditorWindow): BufferPosition =
  ## The anchor, pulled back onto the last line when lines under it went away.
  result = win.visualAnchor
  let buf = win.buffer
  if buf.isNil or buf.len == 0 or result.line < buf.len:
    return
  result.line = buf.len - 1
  result.column = min(result.column, buf.getLineLen(result.line))

proc saveLastVisual*(win: EditorWindow) =
  ## Remember the window's selection on its buffer for `gv`.
  if win.mode.isVisualAllMode and not win.buffer.isNil:
    win.buffer.lastVisual = some(
      VisualArea(
        start: win.clampedAnchor, cursor: win.cursor, kind: win.mode.visualKind
      )
    )

proc saveLastVisualAhead*(win: EditorWindow): Option[VisualArea] =
  ## Save the selection for `gv` before acting on it, so the edit moves the
  ## saved area, and keep leaving Visual from saving it again. Returns the area
  ## it replaced, for `settleLastVisual`.
  if not win.buffer.isNil:
    result = win.buffer.lastVisual
  win.saveLastVisual()
  win.holdLastVisual = true

proc settleLastVisual*(win: EditorWindow, replaced: Option[VisualArea]) =
  ## End `saveLastVisualAhead`. Like Vim, only an ended selection is saved, so
  ## one still active gets the replaced area back.
  win.holdLastVisual = false
  if win.mode.isVisualAllMode and not win.buffer.isNil:
    win.buffer.lastVisual = replaced

proc spot(win: EditorWindow): WindowSpot =
  WindowSpot(
    cursor: win.cursor,
    buffer: win.buffer,
    version: if win.buffer.isNil: 0 else: win.buffer.contentVersion,
  )

proc preferredColumn*(win: EditorWindow): int =
  ## The column vertical moves aim for (Vim's curswant), or -1 to take the
  ## cursor's.
  win.wantedColumn.get(-1)

proc `preferredColumn=`*(win: EditorWindow, column: int) =
  ## Keep `column` for vertical moves; -1 drops it.
  if column < 0:
    win.wantedColumn = none(int)
  else:
    win.wantedColumn = some(column)
    win.wantedColumnSince = win.spot

proc aimedColumn*(win: EditorWindow): int =
  ## The column vertical moves and scrolls aim for: the one kept, else the
  ## cursor's, as Vim's update_curswant.
  let wanted = win.preferredColumn
  if wanted < 0: win.cursor.column else: wanted

proc scrollCursor*(win: EditorWindow, to: BufferPosition) =
  ## Move the cursor as a scroll does, which keeps the column it aimed for as
  ## the one vertical moves want, as Vim keeps curswant.
  if to == win.cursor:
    return
  let aimed = win.aimedColumn
  win.cursor = to
  win.preferredColumn = aimed

proc scrollCursor*(win: EditorWindow, line: int) =
  ## Move the cursor to `line` as a scroll does: onto the column it aims for,
  ## as Vim's coladvance(curswant).
  let lineLen =
    if win.buffer.isNil or line < 0 or line >= win.buffer.len:
      0
    else:
      win.buffer.getLineLen(line)
  win.scrollCursor(
    BufferPosition(
      line: line, column: min(win.aimedColumn, maxCursorColumn(lineLen, win.mode))
    )
  )

proc takeWantedColumn*(win, src: EditorWindow) =
  ## Start with the column `src` wants, as Vim's win_init copies curswant into
  ## a new window, and from where `src` stood when its command began.
  win.wantedColumn = src.wantedColumn
  win.wantedColumnSince = src.wantedColumnSince

proc adjustCursorAfterInsertExit*(win: EditorWindow) =
  ## Put the cursor where leaving Insert leaves it, and take the column
  ## vertical moves want from it again, as Vim's ins_esc.
  if win.buffer.isNil or win.cursor.line >= win.buffer.len:
    return
  win.cursor.adjustCursorAfterInsertExit(win.buffer.getLineLen(win.cursor.line))
  win.preferredColumn = -1

proc noteCommandStart*(win: EditorWindow) =
  ## Note where `win` stands as a command, or the rest of one, begins.
  win.wantedColumnSince = win.spot

proc settleWantedColumn*(win: EditorWindow, ranIn: bool) =
  ## End a command for `win`. As Vim's commands drop curswant, one that moved
  ## the cursor or put another buffer in the window drops the column vertical
  ## moves want, and so does an edit by a command run in it (`ranIn`). What
  ## happened before the command last kept a column does not count.
  let since = win.wantedColumnSince
  let edited =
    ranIn and not win.buffer.isNil and win.buffer.contentVersion != since.version
  if edited or win.cursor != since.cursor or win.buffer != since.buffer:
    win.preferredColumn = -1

proc setMode*(win: EditorWindow, m: EditorMode) =
  ## Set the window's mode. Entering a Visual mode from outside starts the
  ## selection at the cursor, so no entry path can resume a stale anchor.
  ## Entering Insert or Replace and leaving Visual take the column vertical
  ## moves want from the cursor again, as Vim's edit() and Esc do. Leaving
  ## Visual saves the selection for `gv`, as Vim does, and for a mode other
  ## than Insert or Replace brings the cursor back onto the line, off the end
  ## `$` left it at.
  let leavingVisual = win.mode.isVisualAllMode and not m.isVisualAllMode
  if m.isVisualAllMode and not win.mode.isVisualAllMode:
    win.visualAnchor = win.cursor
  if leavingVisual or (
    m in {EditorMode.Insert, EditorMode.Replace} and
    win.mode notin {EditorMode.Insert, EditorMode.Replace}
  ):
    win.preferredColumn = -1
  if leavingVisual and not win.holdLastVisual:
    win.saveLastVisual()
  win.mode = m
  if leavingVisual and m notin {EditorMode.Insert, EditorMode.Replace} and
      not win.buffer.isNil and win.cursor.line < win.buffer.len:
    win.cursor.clampCursorToLastChar(win.buffer.getLineLen(win.cursor.line))

func modeAfterVisual(win: EditorWindow): EditorMode =
  ## The mode Visual was entered from. Never another Visual mode, which would
  ## resume this selection instead of ending it, and never Insert or Replace:
  ## their session ended on entering Visual.
  if win.previousMode.isVisualAllMode or
      win.previousMode in {EditorMode.Insert, EditorMode.Replace}:
    EditorMode.Normal
  else:
    win.previousMode

proc leaveVisual*(win: EditorWindow) =
  ## Return to the mode Visual was entered from, which ends the selection.
  if win.mode.isVisualAllMode:
    win.setMode(win.modeAfterVisual)

proc `mode=`*(s: EditorState, m: EditorMode) =
  ## Set current mode on the active window
  s.activeWindow.setMode(m)

proc leaveVisual*(s: EditorState) =
  s.activeWindow.leaveVisual()

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

proc aimedColumn*(s: EditorState): int =
  s.activeWindow.aimedColumn

proc screenCursor*(s: EditorState): var CursorPosition =
  ## Get screen cursor from the active window (returns var for in-place mutation)
  s.activeWindow.screenCursor

proc `screenCursor=`*(s: EditorState, v: CursorPosition) =
  ## Set screen cursor on the active window
  s.activeWindow.screenCursor = v

proc requestMouseCapture*(s: EditorState, enabled: bool) =
  ## Queue a frontend request to enable or disable mouse capture.
  s.frontend.mouseCapture = some(enabled)

proc takeMouseCaptureRequest*(s: EditorState): Option[bool] =
  ## Return and clear the pending mouse-capture frontend request.
  result = s.frontend.mouseCapture
  s.frontend.mouseCapture = none(bool)

proc frontendSubscriptions*(s: EditorState): FrontendSubscriptions =
  ## Return the data subscriptions requested by an embedding frontend.
  s.frontendSubscriptionsState

proc `frontendSubscriptions=`*(s: EditorState, subscriptions: FrontendSubscriptions) =
  ## Replace the data subscriptions requested by an embedding frontend.
  s.frontendSubscriptionsState = subscriptions

proc `==`*(a, b: ViewPort): bool =
  ## Structural equality for ViewPort (ref object defaults to pointer comparison)
  if a.isNil and b.isNil:
    return true
  if a.isNil or b.isNil:
    return false
  a.topLine == b.topLine and a.topWrapOffset == b.topWrapOffset and
    a.detachedFromCursor == b.detachedFromCursor and a.leftColumn == b.leftColumn and
    a.width == b.width and a.height == b.height and a.x == b.x and a.y == b.y

proc resetViewportTop*(v: ViewPort, line = 0) =
  ## Move viewport to `line` and clear wrap offset (recomputed next frame).
  v.topLine = line
  v.topWrapOffset = 0
  v.detachedFromCursor = false

proc restoreViewportTop*(v: ViewPort, line, wrapOffset: int) =
  ## Restore viewport top with wrap offset.
  v.topLine = line
  v.topWrapOffset = wrapOffset
  v.detachedFromCursor = false

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

proc resumesInsert*(state: EditorState): bool =
  ## True while Insert waits to resume after Ctrl-o.
  state.insertResume != irNone

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
  ## The base mode (Normal, Filer, etc.) is preserved; Visual ends first, as
  ## in Vim.
  state.leaveVisual()
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

when not defined(moe.embedded):
  func terminalSubMode*(state: ModeState): TerminalSubMode =
    ## Only for an `mskTerminal` state.
    if state.scrollbackSnapshot == nil: tsmInput else: tsmNormal

proc modeStateKind*(mode: EditorMode): ModeStateKind =
  ## Map an `EditorMode` to the `ModeStateKind` it expects on `EditorWindow`.
  ## Modes that do not own per-window state (Normal/Insert/Visual/... and
  ## the Command/Replace/Search overlay modes) return
  ## `mskNone`.
  case mode
  of EditorMode.Filer: mskFiler
  of EditorMode.FileTree: mskFileTree
  of EditorMode.LogViewer: mskLogViewer
  of EditorMode.Help: mskHelp
  of EditorMode.BufferManager: mskBufferManager
  of EditorMode.BookmarkManager: mskBookmarkManager
  of EditorMode.BackupManager: mskBackupManager
  of EditorMode.RecoveryManager: mskRecoveryManager
  of EditorMode.DiffViewer: mskDiffViewer
  of EditorMode.Debug: mskDebug
  of EditorMode.Config: mskConfig
  of EditorMode.References: mskReferences
  of EditorMode.DocumentSymbol: mskDocumentSymbol
  of EditorMode.CallHierarchy: mskCallHierarchy
  of EditorMode.RecentFile: mskRecentFile
  of EditorMode.Terminal: mskTerminal
  else: mskNone

proc debounceThreshold*(poll: DebouncedLspPoll): times.Duration =
  let shift = min(poll.rejectStreak, MaxLspDebounceBackoffShift)
  initDuration(milliseconds = poll.interval shl shift)

proc initDebouncedLspPoll*(interval: int64): DebouncedLspPoll =
  DebouncedLspPoll(
    lastUpdate: getMonoTime(),
    interval: interval,
    cursorLine: -1,
    cursorColumn: -1,
    contentVersion: -1,
  )

proc debounceElapsed*(poll: DebouncedLspPoll, now: MonoTime): bool =
  ## True once the (backoff-widened) debounce window since the last request
  ## has passed.
  now - poll.lastUpdate >= poll.debounceThreshold()

proc requestTargetChanged*(
    poll: DebouncedLspPoll, cursorLine, cursorColumn, contentVersion: int
): bool =
  ## True when the cursor or buffer content moved away from the target the
  ## last request was issued for.
  poll.cursorLine != cursorLine or poll.cursorColumn != cursorColumn or
    poll.contentVersion != contentVersion

proc shouldFireDebouncedPoll*(
    poll: DebouncedLspPoll, cursorLine, cursorColumn, contentVersion: int, now: MonoTime
): bool =
  ## Decide whether to fire a new request: something must have changed since
  ## the last one (change detection) and the debounce window must have passed.
  ## On consecutive rejects the window widens (exponential backoff) so a
  ## persistently failing server is retried at a slower cadence. Pure so it can
  ## be unit-tested without driving a live LSP server.
  poll.requestTargetChanged(cursorLine, cursorColumn, contentVersion) and
    poll.debounceElapsed(now)

proc markRequestIssued*(
    poll: var DebouncedLspPoll,
    cursorLine, cursorColumn, contentVersion: int,
    now: MonoTime,
) =
  ## Record the target and time of a request just sent, so change detection and
  ## the debounce window measure from it.
  poll.cursorLine = cursorLine
  poll.cursorColumn = cursorColumn
  poll.contentVersion = contentVersion
  poll.lastUpdate = now
