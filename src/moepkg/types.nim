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

import std/[options, monotimes]

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

  Motion* = enum
    Left
    Right
    Up
    Down
    PageUp
    PageDown
    Home
    End
    FirstLine
    LastLine
    FindChar
    FindCharBackward
    TillChar
    TillCharBackward

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

  VisualSelection* = object ## Represents a visual mode selection range
    start*: BufferPosition # Selection start position (anchor)
    current*: BufferPosition # Current cursor position (selection end)
    active*: bool # Whether selection is currently active

  ReplaceHistoryEntry* = object ## Replace mode history entry for undo with Backspace
    pos*: BufferPosition # Position where character was replaced
    originalChar*: string # Original character before replacement

  EditorState* = ref object
    cursor*: BufferPosition # Actual buffer cursor position (line/column)
    screenCursor*: CursorPosition # Screen cursor position (x/y)
    mode*: EditorMode
    previousMode*: EditorMode # Previous mode for ESC handling
    command*: string
    commandText*: string # Text being typed in command mode
    statusMessage*: string # Message to display in status line
    lastMotion*: Option[Motion]
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
