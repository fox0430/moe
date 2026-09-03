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

import std/options

import pkg/results

import config

type
  ClipboardOperation* {.pure.} = enum
    read
    write

  ClipboardError* = object of CatchableError

const
  WriteTimeoutMs = 10_000
  EmbeddedClipboardError =
    "System clipboard access is owned by the embedding frontend (-d:moe.embedded)"

proc getClipboardCommand*(
    tool: ClipboardTool, operation: ClipboardOperation
): Option[seq[string]] =
  case tool
  of cbtXclip:
    case operation
    of ClipboardOperation.read:
      some(@["xclip", "-selection", "clipboard", "-o"])
    of ClipboardOperation.write:
      some(@["xclip", "-selection", "clipboard", "-i"])
  of cbtXsel:
    case operation
    of ClipboardOperation.read:
      some(@["xsel", "--clipboard", "--output"])
    of ClipboardOperation.write:
      some(@["xsel", "--clipboard", "--input"])
  of cbtWlClipboard:
    case operation
    of ClipboardOperation.read:
      some(@["wl-paste", "-n"])
    of ClipboardOperation.write:
      some(@["wl-copy"])
  of cbtWin32yank:
    case operation
    of ClipboardOperation.read:
      some(@["win32yank.exe", "-o", "--lf"])
    of ClipboardOperation.write:
      some(@["win32yank.exe", "-i", "--crlf"])
  of cbtPbcopy:
    case operation
    of ClipboardOperation.read:
      some(@["pbpaste"])
    of ClipboardOperation.write:
      some(@["pbcopy"])

proc getPrimarySelectionReadCommand*(tool: ClipboardTool): Option[seq[string]] =
  case tool
  of cbtXclip:
    some(@["xclip", "-selection", "primary", "-o"])
  of cbtXsel:
    some(@["xsel", "--output"])
  of cbtWlClipboard:
    some(@["wl-paste", "-n", "--primary"])
  of cbtWin32yank, cbtPbcopy:
    getClipboardCommand(tool, ClipboardOperation.read)

proc getPrimarySelectionWriteCommand*(tool: ClipboardTool): Option[seq[string]] =
  case tool
  of cbtXclip:
    some(@["xclip", "-selection", "primary", "-i"])
  of cbtXsel:
    some(@["xsel", "--input"])
  of cbtWlClipboard:
    some(@["wl-copy", "--primary"])
  of cbtWin32yank, cbtPbcopy:
    getClipboardCommand(tool, ClipboardOperation.write)

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
