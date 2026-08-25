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

## Lightweight type definitions for the register system.
## Split from `registers` to avoid pulling clipboard dependencies into many importers.

import std/[monotimes, options, tables]

import ../config

type
  ClipboardReadOutcome* = enum
    ## Result of last CLIPBOARD read.
    croNotAttempted
    croSucceeded
    croFailed

  Register* = object ## A single register containing text
    isLine*: bool ## Whether the content is linewise (vs characterwise)
    buffer*: seq[string] ## Content lines

  Registers* = ref object ## Container for all register types
    clipboardTool*: Option[ClipboardTool]

    clipboardReadOutcome*: ClipboardReadOutcome ## Outcome of last CLIPBOARD read.
    clipboardReadError*: string ## Error when `croFailed`.
    clipboardReadValue*: string ## Content when `croSucceeded`.

    primaryReadOutcome*: ClipboardReadOutcome ## Outcome of last PRIMARY read.
    primaryReadError*: string ## Error when `croFailed`.
    primaryReadValue*: string ## Content when `croSucceeded`.

    lastClipboardWriteTime*: MonoTime ## Last CLIPBOARD write time, for wl-copy window.

    noNamed*: Register ## The unnamed register (") - latest yank/delete content

    smallDelete*: Register ## Small delete register (-) - deleted text less than one line

    number*: array[10, Register] ## Numbered registers (0-9).

    named*: Table[char, Register] ## Named registers (a-z).

    primarySelection*: Register ## Primary selection register (*) - X11 PRIMARY
    clipboardSelection*: Register ## Clipboard selection register (+, ~) - CLIPBOARD
