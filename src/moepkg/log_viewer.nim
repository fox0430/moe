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

## Log viewer state management
##
## This module provides the data structures for the log viewer mode.
## The actual log content is stored in a TextBuffer.

type
  LogContentKind* = enum
    lckEditor # Editor messages
    lckLsp # LSP messages

  LogViewerState* = ref object
    contentKind*: LogContentKind # Type of log content (for refresh)

proc newLogViewerState*(kind: LogContentKind = lckEditor): LogViewerState =
  ## Create a new log viewer state
  LogViewerState(contentKind: kind)
