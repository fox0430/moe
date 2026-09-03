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

## Terminal stub for embedding frontends.
##
## Embedded applications provide their own terminal UI and process backend.

import std/options

import pkg/results

type PtyHandle* = ref object
  closed*: bool
  writeBuffer*: string

const
  maxPtyWriteBufferBytes* = 64 * 1024
  maxPtyReadBytesPerPoll* = 256 * 1024
  EmbeddedTerminalError = "Terminal mode is unavailable when built with -d:moe.embedded"

proc openPtyAndSpawn*(
    command: string = "", cols: int = 80, rows: int = 24
): Result[PtyHandle, string] =
  discard command
  discard cols
  discard rows
  Result[PtyHandle, string].err(EmbeddedTerminalError)

proc drainWriteBuffer*(pty: PtyHandle): Result[void, string] =
  discard pty
  Result[void, string].err(EmbeddedTerminalError)

proc writeToPty*(pty: PtyHandle, data: string): Result[void, string] =
  discard pty
  discard data
  Result[void, string].err(EmbeddedTerminalError)

proc readFromPty*(pty: PtyHandle, maxBytes: int = 4096): string =
  discard pty
  discard maxBytes

proc resizePty*(pty: PtyHandle, cols, rows: int) =
  discard pty
  discard cols
  discard rows

proc isAlive*(pty: PtyHandle): bool =
  discard pty

proc waitForExit*(pty: PtyHandle): int =
  discard pty
  -1

proc checkExitStatus*(pty: PtyHandle): Option[int] =
  discard pty
  some(-1)

proc closePty*(pty: PtyHandle) =
  if not pty.isNil:
    pty.closed = true
