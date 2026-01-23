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
  cursor, modes, buffer, registers, filer, logviewer, helpviewer, command_completion,
  messagelog, buffermanager, backupmanager, diffviewer, debugviewer, configmode,
  references_viewer, documentsymbol_viewer, hoverpopup

export
  buffer.SidebarItemKind, registers, command_completion, logviewer, helpviewer,
  buffermanager, backupmanager, diffviewer, debugviewer, configmode, references_viewer,
  documentsymbol_viewer, hoverpopup

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

  ViewPort* = object
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

  EditorWindow* = ref object
    ## Represents a split window with its own buffer and viewport
    buffer*: TextBuffer
    viewport*: ViewPort
    cursor*: BufferPosition # Window-local cursor position
    active*: bool # Whether this is the active window

  SearchDirection* = enum
    Forward # Search forward (/)
    Backward # Search backward (?)

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

  DisplaySettings* = object ## Display and UI settings grouped together
    showTabLine*: bool # Whether to show the tab line
    showStatusLine*: bool # Whether to show the status line
    multiStatusLine*: bool
      # Status line for each window (true) or only one at bottom (false)
    showLineCount*: bool # Whether to show line count in status line
    showLinePercentage*: bool # Whether to show line percentage in status line
    showEncoding*: bool # Whether to show file encoding in status line
    showLineNumbers*: bool # Whether to show line numbers
    showCurrentLineNumber*: bool # Whether to highlight current line number
    showCursorLine*: bool # Whether to highlight the cursor line
    showSyntax*: bool # Whether to apply syntax highlighting
    showIndentationLines*: bool # Whether to show indentation guide lines
    showSidebar*: bool # Whether to show the sidebar
    showGitDiff*: bool # Whether to show git diff indicators in sidebar
    showSyntaxChecker*: bool # Whether to show syntax checker results in sidebar
    showCodeLens*: bool # Whether to show CodeLens
    showDocumentHighlight*: bool # Whether to show document highlights
    lineWrap*: bool # Whether to wrap long lines
    tabStop*: int # Tab width (number of spaces per tab character)
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

  EditorState* = ref object
    cursor*: BufferPosition # Actual buffer cursor position (line/column)
    preferredColumn*: int # Preferred column for vertical movement (vim's $ behavior)
    screenCursor*: CursorPosition # Screen cursor position (x/y)
    matchingParenPos*: Option[BufferPosition]
      # Position of matching paren (for highlighting)
    currentWord*: string # Word under cursor (for currentWord highlighting)
    mode*: EditorMode
    previousMode*: EditorMode # Previous mode for ESC handling
    command*: string
    commandText*: string # Text being typed in command mode
    commandCursor*: int
      # Cursor position within commandText (0-based, after the : prefix)
    search*: SearchState # Search-related state (text, history, settings)
    commandState*: CommandState # Command mode (ex-mode) state (history)
    statusMessage*: string # Message to display in status line
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
    # Filer state
    filerState*: Option[FilerState] # File explorer state (when in Filer mode)
    # Log viewer state
    logViewerState*: Option[LogViewerState] # Log viewer state (when in LogViewer mode)
    # Help viewer state
    helpViewerState*: Option[HelpViewerState] # Help viewer state (when in Help mode)
    # References viewer state
    referencesViewerState*: Option[ReferencesViewerState]
      # References viewer state (when in References mode)
    # Document symbol viewer state
    documentSymbolViewerState*: Option[DocumentSymbolViewerState]
      # Document symbol viewer state (when in DocumentSymbol mode)
    # Buffer manager state
    bufferManagerState*: Option[BufferManagerState]
      # Buffer manager state (when in BufferManager mode)
    # Backup manager state
    backupManagerState*: Option[BackupManagerState]
      # Backup manager state (when in BackupManager mode)
    # Diff viewer state
    diffViewerState*: Option[DiffViewerState]
      # Diff viewer state (when in DiffViewer mode)
    # Debug viewer state
    debugViewerState*: Option[DebugViewerState] # Debug viewer state (when in Debug mode)
    # Configuration mode state
    configModeState*: Option[ConfigModeState]
      # Configuration mode state (when in Config mode)
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

proc setStatusMessage*(state: EditorState, msg: string) =
  ## Set status message and log it to message log
  state.statusMessage = msg
  if msg.len > 0:
    addMessageLog(msg)

const MaxStatusMessageLines* = 10
  ## Maximum lines for multi-line status messages to prevent viewport from disappearing

proc statusMessageLineCount*(state: EditorState): int =
  ## Count the number of lines in the status message
  ## Returns 0 if empty, otherwise count of lines (newlines + 1)
  if state.statusMessage.len == 0:
    0
  else:
    min(state.statusMessage.count('\n') + 1, MaxStatusMessageLines)

proc statusMessageExtraLines*(state: EditorState): int =
  ## Get extra lines needed beyond the default command line
  ## Returns 0 for single-line or empty messages
  let lineCount = state.statusMessageLineCount()
  if lineCount > 1:
    lineCount - 1
  else:
    0
