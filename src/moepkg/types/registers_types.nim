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

  RegisterKind* = enum ## How a register's text goes in, as Vim's y_type
    rkChars ## Within and across lines (MCHAR)
    rkLines ## As whole lines (MLINE)
    rkBlock ## As a block, a row to a line (MBLOCK)

  Register* = object ## A single register containing text
    kind*: RegisterKind
    buffer*: seq[string]
      ## The text for `rkChars`, its lines for `rkLines`, its rows for `rkBlock`
    width*: int ## The cells a block put pads its rows to (Vim's y_width + 1)

  Registers* = ref object ## Container for all register types
    clipboardTool*: Option[ClipboardTool]

    clipboardReadOutcome*: ClipboardReadOutcome ## Outcome of last CLIPBOARD read.
    clipboardReadError*: string ## Error when `croFailed`.
    clipboardReadValue*: string ## Content when `croSucceeded`.

    primaryReadOutcome*: ClipboardReadOutcome ## Outcome of last PRIMARY read.
    primaryReadError*: string ## Error when `croFailed`.
    primaryReadValue*: string ## Content when `croSucceeded`.

    lastClipboardWriteTime*: MonoTime
      ## Last CLIPBOARD write time, for the wl-copy claim window.
      ## The zero value means "never written" and must not open the window.

    noNamed*: Register ## The unnamed register (") - latest yank/delete content

    smallDelete*: Register ## Small delete register (-) - deleted text less than one line

    number*: array[10, Register]
      ## Numbered registers. 0 is the latest yank; 1-9 are the delete history,
      ## newest first. Deletes over lines, or over `%`, `}`, `n` and the like,
      ## enter 1 (shifting 1-8 down); others within a line go to `smallDelete`.

    named*: Table[char, Register] ## Named registers (a-z).

    primarySelection*: Register ## Primary selection register (*) - X11 PRIMARY
    clipboardSelection*: Register ## Clipboard selection register (+, ~) - CLIPBOARD

proc blockRegister*(rows: seq[string], width: int): Register =
  ## A block of `rows`, put padded to `width` cells (Vim's MBLOCK).
  Register(kind: rkBlock, buffer: rows, width: width)
