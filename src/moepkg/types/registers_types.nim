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
##
## Split out from `registers` so modules that only need the `Register` and
## `Registers` types (notably `types` and its ~60 importers) do not transitively
## pull in the full register implementation, which imports `clipboard` (and thus
## `osproc`, `streams`). The clipboard-syncing logic and the
## public accessor procs stay in `registers`.
##
## The `Registers` fields are exported so the procs in `registers` can operate
## on them from the implementation module; they are not part of the intended
## public API.

import std/[monotimes, options, tables]

import ../config

type
  Register* = object ## A single register containing text
    isLine*: bool ## Whether the content is linewise (vs characterwise)
    buffer*: seq[string] ## Content lines

  Registers* = ref object ## Container for all register types
    clipboardTool*: Option[ClipboardTool]

    lastClipboardWriteTime*: MonoTime
      ## Time of the last CLIPBOARD write; used to tolerate the wl-copy
      ## claim window. The zero value (no write yet) reads as expired.

    noNamed*: Register ## The unnamed register (") - latest yank/delete content

    smallDelete*: Register ## Small delete register (-) - deleted text less than one line

    number*: array[10, Register]
      ## Numbered registers (0-9)
      ## 0: Most recent yank
      ## 1-9: Delete history (1 is most recent, shifts on new delete).
      ## Only linewise/multiline deletes are recorded; shorter deletions
      ## go to the small delete register (-).

    named*: Table[char, Register]
      ## Named registers (a-z)
      ## Lowercase overwrites, uppercase appends

    primarySelection*: Register ## Primary selection register (*) - X11 PRIMARY
    clipboardSelection*: Register ## Clipboard selection register (+, ~) - CLIPBOARD
