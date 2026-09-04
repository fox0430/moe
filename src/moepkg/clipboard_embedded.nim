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

## Clipboard API for embedding frontends.
##
## An embedding frontend owns clipboard access and keeps Moe's clipboard
## integration disabled. These routines remain available so editor modules have
## one stable interface, but report a clear error if called.

import pkg/results

import config

type ClipboardError* = object of CatchableError

const
  WriteTimeoutMs = 10_000
  EmbeddedClipboardError =
    "System clipboard access is owned by the embedding frontend (-d:moe.embedded)"

proc readFromClipboardSync*(tool: ClipboardTool): Result[string, string] =
  discard tool
  Result[string, string].err(EmbeddedClipboardError)

proc readFromPrimarySelectionSync*(tool: ClipboardTool): Result[string, string] =
  discard tool
  Result[string, string].err(EmbeddedClipboardError)

proc writeToClipboardSync*(
    tool: ClipboardTool, text: string, timeoutMs: int = WriteTimeoutMs
): Result[bool, string] =
  discard tool
  discard text
  discard timeoutMs
  Result[bool, string].err(EmbeddedClipboardError)

proc writeToPrimarySelectionSync*(
    tool: ClipboardTool, text: string, timeoutMs: int = WriteTimeoutMs
): Result[bool, string] =
  discard tool
  discard text
  discard timeoutMs
  Result[bool, string].err(EmbeddedClipboardError)
