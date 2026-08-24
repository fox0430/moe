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

## Lightweight type definitions for terminal mode.
##
## Split out from `terminal_mode` so modules that only need its State type
## (notably `types` and its importers) do not transitively pull in the
## PTY/ANSI pipeline procs.

import std/options

import ../terminal/[pty, ansi_parser]
import ../buffer/core

type
  TerminalSubMode* = enum
    tsmInput # All keystrokes forwarded to PTY (default)
    tsmNormal # Vim-like scrollback navigation

  TerminalState* = ref object
    pty*: PtyHandle
    grid*: TerminalGrid
    subMode*: TerminalSubMode
    scrollbackSnapshot*: TextBuffer # Snapshot for Terminal-Normal mode
    exitCode*: Option[int]
    waitingForCtrlN*: bool # Waiting for Ctrl-N after Ctrl-\
    needsBufferRefresh*: bool
