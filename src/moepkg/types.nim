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

import std/options

import cursor, modes

type
  ViewPort* = object
    topLine*: int
    leftColumn*: int
    width*: int
    height*: int

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

  EditorState* = ref object
    cursor*: CursorPosition # Actual cursor position
    mode*: EditorMode
    command*: string
    commandText*: string # Text being typed in command mode
    statusMessage*: string # Message to display in status line
    lastMotion*: Option[Motion]
    showStatusLine*: bool # Whether to show the status line
    showLineCount*: bool # Whether to show line count in status line
    showLinePercentage*: bool # Whether to show line percentage in status line
    showEncoding*: bool # Whether to show file encoding in status line
    needsFullRedraw*: bool # Whether a full screen redraw is needed
