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

import std/[options, monotimes, tables]

import pkg/celina

import cursor, modes, buffer

# Re-export SidebarItemKind from buffer module
export buffer.SidebarItemKind

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

  EditorWindow* = ref object
    ## Represents a split window with its own buffer and viewport
    buffer*: TextBuffer
    viewport*: ViewPort
    cursor*: BufferPosition # Window-local cursor position
    active*: bool # Whether this is the active window

  SearchDirection* = enum
    Forward # Search forward (/)
    Backward # Search backward (?)

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

  VisualSelection* = object ## Represents a visual mode selection range
    start*: BufferPosition # Selection start position (anchor)
    current*: BufferPosition # Current cursor position (selection end)
    active*: bool # Whether selection is currently active

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

  EditorState* = ref object
    cursor*: BufferPosition # Actual buffer cursor position (line/column)
    screenCursor*: CursorPosition # Screen cursor position (x/y)
    mode*: EditorMode
    previousMode*: EditorMode # Previous mode for ESC handling
    command*: string
    commandText*: string # Text being typed in command mode
    searchText*: string # Text being typed in search mode
    lastSearchText*: string # Last executed search text for n/N commands
    statusMessage*: string # Message to display in status line
    lastMotion*: Option[Motion]
    lastEditCommand*: Option[LastEditCommand] # Last change command for . (repeat)
    insertModeStartPos*: Option[BufferPosition]
      # Position where Insert mode started (for text tracking)
    substituteContext*: Option[SubstituteContext]
      # Context when Insert mode was entered via substitute (s/S/cc)
    pendingOperator*: Option[PendingOperator] # Operator waiting for motion/text object
    pendingTextObject*: Option[PendingTextObject]
      # Text object modifier waiting for object kind
    savedViewportTopLine*: int # Viewport position saved when operator starts
    visualSelection*: VisualSelection # Visual mode selection state
    replaceHistory*: seq[ReplaceHistoryEntry] # Replace mode undo history
    showStatusLine*: bool # Whether to show the status line
    multiStatusLine*: bool
      # Whether to show status line for each window (true) or only one at bottom (false)
    showLineCount*: bool # Whether to show line count in status line
    showLinePercentage*: bool # Whether to show line percentage in status line
    showEncoding*: bool # Whether to show file encoding in status line
    needsFullRedraw*: bool # Whether a full screen redraw is needed
    viewportReservedLines*: int
      # Reserved lines for viewport calculations (for split windows)
    lineWrap*: bool # Whether to wrap long lines
    lastResizeTime*: MonoTime # Timestamp of last processed resize event
    # Sidebar settings
    showSidebar*: bool # Whether to show the sidebar
    showGitDiff*: bool # Whether to show git diff indicators in sidebar
    showSyntaxChecker*: bool # Whether to show syntax checker results in sidebar
    lastGitDiffUpdate*: MonoTime # Timestamp of last git diff update
    lastGitDiffChangeSeq*: int # Buffer changeSeq at last git diff update
    gitDiffUpdateInterval*: int64
      # Minimum milliseconds between git diff updates (debounce)
    # Editor behavior settings
    tabStop*: int # Tab width (number of spaces per tab character)
    expandTab*: bool # Insert spaces instead of tab character when Tab key is pressed
    autoIndent*: bool # Automatically indent new lines based on previous line
    autoCloseParen*: bool # Automatically insert closing parenthesis/bracket/quote
    autoDeleteParen*: bool
      # Automatically delete matching closing paren when opening is deleted
    showLineNumbers*: bool # Whether to show line numbers
    showCurrentLineNumber*: bool # Whether to highlight current line number
    showCursorLine*: bool # Whether to highlight the cursor line
    showSyntax*: bool # Whether to apply syntax highlighting
    showIndentationLines*: bool # Whether to show indentation guide lines
    # Search behavior settings
    ignorecase*: bool # Ignore case in search patterns
    smartcase*: bool # Override ignorecase if search pattern contains uppercase letters
    incsearch*: bool # Show search matches as you type
    hlsearch*: bool # Highlight all search matches in the buffer
    hlsearchTempDisabled*: bool # Temporarily disable highlight (like :nohlsearch in Vim)
    lastKeyWasEscape*: bool
      # Track if last key was Escape (for double-Escape to clear highlight)
    searchStartPos*: BufferPosition
      # Cursor position when search mode started (for incsearch cancellation)
    searchDirection*: SearchDirection # Direction of current search (/ or ?)
    searchHistory*: seq[string] # Search history (most recent first)
    searchHistoryIndex*: int
      # Current position in search history (-1 when not navigating history)
    # Yank register (internal clipboard)
    yankRegister*: string # Content yanked with yy, y, etc.
    yankIsLine*: bool # Whether the yank was linewise (yy) or characterwise
    # Macro recording (q command)
    isRecordingMacro*: bool # Whether currently recording a macro
    macroRegister*: char # Which register (a-z) is being recorded to
    recordedKeys*: seq[string] # Keys being recorded in current macro session
    macroRegisters*: Table[char, seq[string]] # Saved macros by register (a-z)
    lastMacroRegister*: Option[char] # Last executed macro register (for @@ repeat)
    waitingForMacroRegister*: bool # Waiting for register name after q or @
    macroCommandType*: string # "record" or "playback" - what we're waiting to do
