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

import std/[options, monotimes, times, tables, strutils, json]

import pkg/celina

import
  modes, buffer, registers, filer, filetree, log_viewer, help_viewer,
  command_completion, message_log, logger, buffer_manager, bookmark_manager,
  backup_manager, diff_viewer, debug_viewer, config_mode, references_viewer,
  documentsymbol_viewer, callhierarchy_viewer, hover_popup, notification_popup,
  primitives, syntax_checker, recent_file_mode, terminal_mode

export
  buffer.SidebarItemKind, registers, command_completion, filer, filetree, log_viewer,
  help_viewer, buffer_manager, bookmark_manager, backup_manager, diff_viewer,
  debug_viewer, config_mode, references_viewer, documentsymbol_viewer,
  callhierarchy_viewer, hover_popup, notification_popup, primitives, syntax_checker,
  recent_file_mode, terminal_mode

type
  SidebarItem* = object ## Single cell in the sidebar
    text*: string ## Display text (e.g., "+", "~", ">>")
    kind*: SidebarItemKind
    style*: Style ## Rendering style

  Sidebar* = object
    ## Sidebar displayed on the left side of editor window
    ## Used for git diff, syntax errors, etc.
    width*: int ## Width of sidebar in characters
    buffer*: seq[seq[SidebarItem]] ## Per-line sidebar content [y][x]

  ViewPort* = ref object
    topLine*: int
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

  CursorPosition* = object
    x*: int
    y*: int

  EditorWindow* = ref object
    ## Represents a split window with its own buffer and viewport
    buffer*: TextBuffer
    bufferList*: seq[TextBuffer] # Window-local buffer list
    viewport*: ViewPort
    cursor*: BufferPosition # Window-local cursor position
    active*: bool # Whether this is the active window
    mode*: EditorMode # Current mode for this window
    previousMode*: EditorMode # Previous mode for ESC handling
    preferredColumn*: int # Preferred column for vertical movement (vim's $ behavior)
    screenCursor*: CursorPosition # Screen cursor position (x/y)
    filerState*: Option[FilerState] # File explorer state
    logViewerState*: Option[LogViewerState] # Log viewer state
    helpViewerState*: Option[HelpViewerState] # Help viewer state
    bufferManagerState*: Option[BufferManagerState] # Buffer manager state
    bookmarkManagerState*: Option[BookmarkManagerState] # Bookmark manager state
    backupManagerState*: Option[BackupManagerState] # Backup manager state
    diffViewerState*: Option[DiffViewerState] # Diff viewer state
    debugViewerState*: Option[DebugViewerState] # Debug viewer state
    configModeState*: Option[ConfigModeState] # Configuration mode state
    referencesViewerState*: Option[ReferencesViewerState] # References viewer state
    documentSymbolViewerState*: Option[DocumentSymbolViewerState]
      # Document symbol viewer state
    callHierarchyViewerState*: Option[CallHierarchyViewerState]
      # Call hierarchy viewer state
    recentFileModeState*: Option[RecentFileModeState] # Recent file mode state
    terminalState*: Option[TerminalState] # Terminal mode state
    fileTreeState*: Option[FileTreeState] # File tree sidebar state
    fixedWidth*: Option[int] # Fixed width for sidebar windows (skips equalize)

  SearchDirection* = enum
    Forward # Search forward (/)
    Backward # Search backward (?)

  OverlayState* = object
    ## State for overlay modes (Command, Search, Rename)
    ## These are transient modes that sit on top of a base mode
    case kind*: OverlayKind
    of okCommand:
      commandText*: string # Text being typed (includes ":" prefix)
      commandCursor*: int # Cursor position within text (0-based after ":")
    of okSearch:
      searchDirection*: SearchDirection # / or ?
    of okRename:
      renameText*: string # New name being typed
      renameOriginalWord*: string # Original word being renamed
      renameCursorLine*: int # Line where rename was initiated
      renameCursorColumn*: int # Column where rename was initiated

  SearchState* = object ## Search-related state grouped together for better organization
    text*: string # Text being typed in search mode (was: searchText)
    lastText*: string # Last executed search text for n/N commands (was: lastSearchText)
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

  MacroState* = object ## Macro recording and playback state grouped together
    isRecording*: bool # Whether currently recording a macro (was: isRecordingMacro)
    register*: char # Which register (a-z) is being recorded to (was: macroRegister)
    recordedKeys*: seq[string] # Keys being recorded in current macro session
    registers*: Table[char, seq[string]] # Saved macros by register (was: macroRegisters)
    lastRegister*: Option[char]
      # Last executed macro register for @@ (was: lastMacroRegister)
    waitingForRegister*: bool # Waiting for register name after q or @
    commandType*: string # "record" or "playback" (was: macroCommandType)
    recordStartKey*: string # Key string that started recording (for stop detection)
    pendingCount*: int # Numeric prefix for macro playback (was: pendingMacroCount)
    playbackDepth*: int # Current macro recursion depth (was: macroPlaybackDepth)

  EditState* = object ## Edit operation state grouped together
    lastMotion*: Option[Motion] # Last motion for repeat
    lastEditCommand*: Option[LastEditCommand] # Last change command for . (repeat)
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

  DisplaySettings* = object ## Display and UI settings grouped together
    showTabLine*: bool # Whether to show the tab line
    showStatusLine*: bool # Whether to show the status line
    multiStatusLine*: bool
      # Status line for each window (true) or only one at bottom (false)
    showLineCount*: bool # Whether to show line count in status line
    showLinePercentage*: bool # Whether to show line percentage in status line
    showEncoding*: bool # Whether to show file encoding in status line
    showLineEnding*: bool # Whether to show line ending (LF/CRLF/CR) in status line
    showLineNumbers*: bool # Whether to show line numbers
    relativeLineNumbers*: bool # Whether to show relative line numbers
    showCurrentLineNumber*: bool # Whether to highlight current line number
    showCursorLine*: bool # Whether to highlight the cursor line
    showCursorColumn*: bool # Whether to highlight the cursor column
    showSyntax*: bool # Whether to apply syntax highlighting
    showIndentationLines*: bool # Whether to show indentation guide lines
    showSidebar*: bool # Whether to show the sidebar
    scrollbar*: bool # Whether to show the scrollbar
    scrollbarWidth*: int # Scrollbar width in characters
    showModifiedLines*: bool # Whether to highlight modified line numbers
    showGitDiff*: bool # Whether to show git diff indicators in sidebar
    showSyntaxChecker*: bool # Whether to show syntax checker results in sidebar
    showCodeLens*: bool # Whether to show CodeLens
    showDocumentHighlight*: bool # Whether to show document highlights
    lineWrap*: bool # Whether to wrap long lines
    tabStop*: int # Tab width (number of spaces per tab character)
    shiftWidth*: int # Indent width, 0 = use tabStop
    softTabStop*: int # Tab/Backspace width in insert mode, 0 = use tabStop
    expandTab*: bool # Insert spaces instead of tab character
    autoIndent*: bool # Automatically indent new lines
    autoCloseParen*: bool # Automatically insert closing parenthesis/bracket/quote
    autoDeleteParen*: bool # Automatically delete matching parenthesis

  LspCacheState* = object ## LSP cache and picker state grouped together
    codeLensCache*: CodeLensCache # Cached CodeLens items for current buffer
    codeLensPicker*: CodeLensPicker # CodeLens selection UI state
    documentHighlightCache*: DocumentHighlightCache # Cached document highlights
    semanticTokensCache*: SemanticTokensCache # Semantic tokens cache state
    hoverPopup*: HoverPopupManager # Hover popup manager
    locations*: Option[LspLocationsResult]
      # LSP locations for references/definitions picker
    lastCodeLensUpdate*: MonoTime # Timestamp of last CodeLens update
    codeLensUpdateInterval*: int64 # Debounce interval for CodeLens updates
    lastDocumentHighlightUpdate*: MonoTime # Timestamp of last document highlight update
    documentHighlightUpdateInterval*: int64
      # Debounce interval for document highlight updates
    lastSemanticTokensUpdate*: MonoTime # Timestamp of last semantic tokens update
    semanticTokensUpdateInterval*: int64 # Debounce interval for semantic tokens updates
    # Pending async request IDs for non-blocking LSP operations
    pendingSignatureHelpRequestId*: int
      # Request ID for pending signature help request (0 = none)
    pendingDocumentHighlightRequestId*: int
      # Request ID for pending document highlight request (0 = none)
    pendingCodeLensRequestId*: int # Request ID for pending code lens request (0 = none)
    pendingSemanticTokensRequestId*: int
      # Request ID for pending semantic tokens request (0 = none)
    pendingHoverRequestId*: int # Request ID for pending hover request (0 = none)
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
    # Pending call hierarchy request (2-stage: prepare -> incoming/outgoing)
    pendingCallHierarchyRequestId*: int # Request ID (0 = none)
    pendingCallHierarchyKind*: CallHierarchyRequestKind # incoming or outgoing
    pendingCallHierarchyPrepareResult*: Option[JsonNode]
      # Cached prepare result for 2nd stage
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
    lastGitDiffUpdate*: MonoTime # Timestamp of last git diff update
    lastGitDiffChangeSeq*: int # Buffer changeSeq at last git diff update
    gitDiffUpdateInterval*: int64 # Minimum milliseconds between git diff updates
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

  JumpPosition* = object ## Represents a position in the jump list
    bufferIndex*: int # Buffer index in the buffer list
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
      operatorCount*: int # Count for operator (2 in "2dd")
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

  SubstitutePreview* = object
    ## State for live substitute preview (like Vim's inccommand)
    isActive*: bool # Whether preview is currently active
    originalLines*: seq[string] # Snapshot of original buffer content
    lastPattern*: string # Last pattern used for preview
    lastReplacement*: string # Last replacement used for preview

  PendingCommand* = enum
    PendingNone
    PendingWindowCmd # Ctrl-W prefix: waiting for window subcommand

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
    commandText*: string # Text being typed in command mode
    commandCursor*: int
      # Cursor position within commandText (0-based, after the : prefix)
    search*: SearchState # Search-related state (text, history, settings)
    commandState*: CommandState # Command mode (ex-mode) state (history)
    statusMessageStr: string # Internal - use statusMessage getter/setter
    editState*: EditState # Edit operation state (operators, motions, repeat, etc.)
    savedViewportTopLine*: int # Viewport position saved when operator starts
    visualSelection*: VisualSelection # Visual mode selection state
    display*: DisplaySettings # Display and UI settings
    needsFullRedraw*: bool # Whether a full screen redraw is needed
    viewportReservedLines*: int
      # Reserved lines for viewport calculations (for split windows)
    timing*: TimingState # Timing and debounce state
    lastKeyWasEscape*: bool
      # Track if last key was Escape (for double-Escape to clear highlight)
    # Yank register (internal clipboard) - DEPRECATED: use registers instead
    yankRegister*: string # Content yanked with yy, y, etc.
    yankIsLine*: bool # Whether the yank was linewise (yy) or characterwise
    # Full register system (vim-style)
    registers*: Registers # All registers (", 0-9, a-z, -, *, +)
    pendingRegister*: Option[char]
      # Register selected with " prefix (e.g., "a for register a)
    # Macro state (grouped in MacroState)
    macroState*: MacroState # Macro recording and playback state
    # Jump list (Ctrl-o / Ctrl-i)
    jumpList*: seq[JumpPosition] # List of jump positions
    jumpListIndex*: int # Current position in jump list (-1 when not navigating)
    currentBufferIndex*: int # Index of the current buffer (for jump list)
    # Debug buffer tracking for auto-refresh
    debugBuffer*: TextBuffer
      # Reference to the debug buffer for auto-refresh (nil if none)
    # QuickRun request flag
    requestQuickRun*: bool # Set by keybinding to request QuickRun execution
    # Command mode completion
    commandCompletionManager*: CommandCompletionManager
      # Command mode auto-completion manager
    # Smooth scroll animation
    scrollAnimation*: ScrollAnimation # Current scroll animation state
    # LSP cache state (grouped in LspCacheState)
    lspCache*: LspCacheState # LSP cache and picker state
    # LSP progress display
    lspProgressText*: string # Current LSP progress text for status line
    # Temporary message display (like Vim's :jumps output)
    tempMessages*: seq[string] # Lines to display temporarily in command area
    # Substitute preview state (live preview like Vim's inccommand)
    substitutePreview*: SubstitutePreview
    # Pending async operations (for shell commands that need TUI suspend)
    pendingShellCommand*: string # Shell command to execute after suspend
    pendingBackground*: bool # Whether to suspend for background (:bg)
    pendingManPage*: string # Man page to show after suspend (:man)
    # Pending build/quickrun info (for async background processes)
    pendingBuildOnSave*:
      tuple[path: string, language: int, customCmd: string, workspaceRoot: string]
    pendingQuickRun*:
      tuple[cmd: string, args: seq[string], filePath: string, isTempFile: bool]
    # Pending syntax check info (for async background processes)
    pendingSyntaxCheck*: tuple[path: string, language: int]
    # Active syntax check results (for status message display)
    syntaxCheckResults*: tuple[path: string, errors: seq[SyntaxCheckError]]
    # LSP Rename state
    renameState*: RenameState # State for LSP rename mode
    # Overlay state for transient modes (Command, Search, Rename)
    # When set, the editor displays an overlay on top of the base mode
    overlay*: Option[OverlayState]
    # f/F/t/T command match highlight
    findCharMatches*: seq[int] # Matched column positions on cursor line
    findCharMatchLine*: int # Line number of the matches
    # Insert-Normal mode (Ctrl-o): execute one Normal command then return to Insert
    insertNormalMode*: bool
    # Startup window actions completed (runs once on first render)
    startUpWindowsDone*: bool
    # Notification popup manager
    notificationPopup*: NotificationPopupManager
    # Exit code (non-zero for :cq)
    exitCode*: int

# Forwarding procs: EditorState delegates cursor/mode/etc. to activeWindow.
# This eliminates the dual-state sync problem — EditorWindow is the single source of truth.

proc cursor*(s: EditorState): var BufferPosition {.inline.} =
  ## Get cursor position from the active window (returns var for in-place mutation)
  s.activeWindow.cursor

proc `cursor=`*(s: EditorState, pos: BufferPosition) {.inline.} =
  ## Set cursor position on the active window
  s.activeWindow.cursor = pos

proc mode*(s: EditorState): EditorMode {.inline.} =
  ## Get current mode from the active window
  s.activeWindow.mode

proc `mode=`*(s: EditorState, m: EditorMode) {.inline.} =
  ## Set current mode on the active window
  s.activeWindow.mode = m

proc previousMode*(s: EditorState): EditorMode {.inline.} =
  ## Get previous mode from the active window
  s.activeWindow.previousMode

proc `previousMode=`*(s: EditorState, m: EditorMode) {.inline.} =
  ## Set previous mode on the active window
  s.activeWindow.previousMode = m

proc preferredColumn*(s: EditorState): int {.inline.} =
  ## Get preferred column from the active window
  s.activeWindow.preferredColumn

proc `preferredColumn=`*(s: EditorState, v: int) {.inline.} =
  ## Set preferred column on the active window
  s.activeWindow.preferredColumn = v

proc screenCursor*(s: EditorState): var CursorPosition {.inline.} =
  ## Get screen cursor from the active window (returns var for in-place mutation)
  s.activeWindow.screenCursor

proc `screenCursor=`*(s: EditorState, v: CursorPosition) {.inline.} =
  ## Set screen cursor on the active window
  s.activeWindow.screenCursor = v

proc `==`*(a, b: ViewPort): bool =
  ## Structural equality for ViewPort (ref object defaults to pointer comparison)
  if a.isNil and b.isNil:
    return true
  if a.isNil or b.isNil:
    return false
  a.topLine == b.topLine and a.leftColumn == b.leftColumn and a.width == b.width and
    a.height == b.height and a.x == b.x and a.y == b.y

proc statusMessage*(state: EditorState): string =
  ## Get the current status message
  state.statusMessageStr

proc `statusMessage=`*(state: EditorState, msg: string) =
  ## Set status message and automatically log non-empty messages
  state.statusMessageStr = msg
  if msg.len > 0:
    addMessageLog(msg)
    logDebug("editorMessage", msg)

const MaxStatusMessageLines* = 10
  ## Maximum lines for multi-line status messages to prevent viewport from disappearing

proc statusMessageLineCount*(state: EditorState): int =
  ## Count the number of lines in the status message
  ## Returns 0 if empty, otherwise count of lines (newlines + 1)
  if state.statusMessageStr.len == 0:
    0
  else:
    min(state.statusMessageStr.count('\n') + 1, MaxStatusMessageLines)

proc statusMessageExtraLines*(state: EditorState): int =
  ## Get extra lines needed beyond the default command line
  ## Returns 0 for single-line or empty messages
  let lineCount = state.statusMessageLineCount()
  if lineCount > 1:
    lineCount - 1
  else:
    0

# Overlay accessors

proc hasOverlay*(state: EditorState): bool =
  ## Check if an overlay is currently active
  state.overlay.isSome

proc overlayKind*(state: EditorState): Option[OverlayKind] =
  ## Get the kind of active overlay, if any
  if state.overlay.isSome:
    some(state.overlay.get.kind)
  else:
    none(OverlayKind)

proc isCommandOverlay*(state: EditorState): bool =
  ## Check if command overlay is active
  state.overlay.isSome and state.overlay.get.kind == okCommand

proc isSearchOverlay*(state: EditorState): bool =
  ## Check if search overlay is active
  state.overlay.isSome and state.overlay.get.kind == okSearch

proc isRenameOverlay*(state: EditorState): bool =
  ## Check if rename overlay is active
  state.overlay.isSome and state.overlay.get.kind == okRename

proc enterCommandOverlay*(state: EditorState) =
  ## Enter command mode overlay
  ## The base mode (Normal, Filer, etc.) is preserved
  state.overlay =
    some(OverlayState(kind: okCommand, commandText: ":", commandCursor: 0))
  # Initialize command text (legacy field)
  state.commandText = ":"
  state.commandCursor = 0
  state.commandState.historyIndex = -1

proc enterSearchOverlay*(state: EditorState, direction: SearchDirection) =
  ## Enter search mode overlay
  ## The base mode (Normal, LogViewer, etc.) is preserved
  state.overlay = some(OverlayState(kind: okSearch, searchDirection: direction))
  # Initialize search state
  state.search.direction = direction
  state.search.text = ""
  state.search.startPos = state.cursor
  state.search.historyIndex = -1
  # Re-enable search highlight so incremental search results are visible
  state.search.hlsearchTempDisabled = false
  # Reset whole word mode so / and ? use regex matching consistently
  # (wholeWord may be true from a previous * or # command)
  state.search.wholeWord = false

proc enterRenameOverlay*(state: EditorState, word: string, line, col: int) =
  ## Enter rename mode overlay
  ## The base mode (Normal) is preserved
  state.overlay = some(
    OverlayState(
      kind: okRename,
      renameText: word,
      renameOriginalWord: word,
      renameCursorLine: line,
      renameCursorColumn: col,
    )
  )
  # Initialize rename state (legacy field)
  state.renameState.text = word
  state.renameState.originalWord = word
  state.renameState.cursorLine = line
  state.renameState.cursorColumn = col

proc exitOverlay*(state: EditorState) =
  ## Exit the current overlay and return to the base mode
  if state.overlay.isSome:
    state.overlay = none(OverlayState)
    # Clear overlay-specific state
    state.commandText = ""
    state.commandCursor = 0
    state.commandState.historyIndex = -1
    state.search.text = ""
    state.search.historyIndex = -1

proc baseMode*(state: EditorState): EditorMode =
  ## Get the base mode (the mode under the overlay)
  ## With overlays, state.mode always holds the base mode
  state.mode

proc effectiveMode*(state: EditorState): EditorMode =
  ## Get the effective mode for display purposes
  ## Returns the overlay mode if active, otherwise the base mode
  ## This is for backward compatibility with code that checks state.mode
  state.mode
