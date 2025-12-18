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

## Log viewer state management
##
## This module provides the data structures and operations for the log viewer mode.

import messagelog

type
  LogContentKind* = enum
    lckEditor # Editor messages
    lckLsp # LSP messages

  LogViewerState* = ref object
    lines*: seq[string] # Log lines to display
    selectedIndex*: int # Currently selected line index (cursor position)
    topLine*: int # Scroll position (first visible line)
    contentKind*: LogContentKind # Type of log content

proc newLogViewerState*(kind: LogContentKind = lckEditor): LogViewerState =
  ## Create a new log viewer state
  let lines =
    case kind
    of lckEditor:
      getMessageLog()
    of lckLsp:
      @["LSP log not yet implemented"]

  LogViewerState(lines: lines, selectedIndex: 0, topLine: 0, contentKind: kind)

proc refresh*(state: LogViewerState) =
  ## Refresh the log content
  state.lines =
    case state.contentKind
    of lckEditor:
      getMessageLog()
    of lckLsp:
      @["LSP log not yet implemented"]

  # Adjust selected index if necessary
  if state.lines.len == 0:
    state.selectedIndex = 0
  elif state.selectedIndex >= state.lines.len:
    state.selectedIndex = state.lines.high

proc lineCount*(state: LogViewerState): int =
  ## Get the number of lines in the log
  state.lines.len

proc getLine*(state: LogViewerState, index: int): string =
  ## Get a specific line from the log
  if index >= 0 and index < state.lines.len:
    state.lines[index]
  else:
    ""

proc moveUp*(state: LogViewerState) =
  ## Move selection up
  if state.selectedIndex > 0:
    state.selectedIndex.dec

proc moveDown*(state: LogViewerState) =
  ## Move selection down
  if state.selectedIndex < state.lines.high:
    state.selectedIndex.inc

proc moveToFirst*(state: LogViewerState) =
  ## Move to first line
  state.selectedIndex = 0

proc moveToLast*(state: LogViewerState) =
  ## Move to last line
  if state.lines.len > 0:
    state.selectedIndex = state.lines.high
  else:
    state.selectedIndex = 0

proc halfPageUp*(state: LogViewerState, viewportHeight: int) =
  ## Move up by half a page
  let halfPage = viewportHeight div 2
  state.selectedIndex = max(0, state.selectedIndex - halfPage)

proc halfPageDown*(state: LogViewerState, viewportHeight: int) =
  ## Move down by half a page
  let halfPage = viewportHeight div 2
  if state.lines.len > 0:
    state.selectedIndex = min(state.lines.high, state.selectedIndex + halfPage)

proc ensureSelectedVisible*(state: LogViewerState, viewportHeight: int) =
  ## Ensure the selected line is visible in the viewport
  # Adjust topLine to keep selected line visible
  if state.selectedIndex < state.topLine:
    state.topLine = state.selectedIndex
  elif state.selectedIndex >= state.topLine + viewportHeight:
    state.topLine = state.selectedIndex - viewportHeight + 1

  # Ensure topLine is not negative
  if state.topLine < 0:
    state.topLine = 0
