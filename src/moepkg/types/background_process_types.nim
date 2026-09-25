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

## Lightweight type definitions for background processes.
##
## Split out from `background_process` so modules that only need the type
## surface (notably `types/editor_types` for the
## `Editor.runningBackgroundProcesses` field) do not import it. `ChildProcess`
## is defined in `child_process`, the one module that touches its fields.

import std/[monotimes, options]

import pkg/results

import ../child_process

type
  BackgroundProcessCommand* = object
    cmd*: string
    args*: seq[string]
    workingDir*: string

  BackgroundProcess* = ref object
    process*: ChildProcess ## Kept after the run: it is what knows how the command ended.

  ProcessRunOutcome* = enum
    ## How a run left the bounded wait. Cancellation and a stop are kept apart
    ## from a timeout: the editor asked for them, the command earned the other.
    proCompleted
    proTimedOut
    proCancelled
    proStopped

  RunningCommand* = object
    ## One external command the editor started, named and timed so a command
    ## holding a file's claim can be reported and stopped.
    process*: BackgroundProcess
    label*: string ## What it is, in words the user would recognise.
    path*: string ## The file it claimed, empty if it claimed none.
    startedAt*: MonoTime

  StartProcessResult* = Result[BackgroundProcess, string]

  ProcessOutputResult* = Result[seq[string], string]
    ## Output of a finished process, or the reason it produced none (start
    ## failure, timeout). Common return type of the bounded waits.

  FilterFailureKind* = enum
    ## Why a filter run produced no text to apply. Kept as a kind rather than
    ## only a message because callers branch on it: a timeout is worth
    ## offering to retry with a longer bound, a command that could not be
    ## started is not.
    ##
    ## A command that stops reading early is deliberately absent: it is how
    ## `head -1` and `sed 3q` work, and whether the writer even sees the short
    ## read depends on the size of a pipe buffer.
    ffStartFailed
    ffTimedOut
    ffCancelled
    ffOutputTooLarge
    ffReadFailed

  FilterProcessError* = object
    kind*: FilterFailureKind
    message*: string ## Ready to show to the user.

  FilterProcessOutput* = object
    ## What a command run as a text filter produced.
    ##
    ## `output` is the bytes it wrote, kept verbatim rather than split into
    ## lines: it becomes a buffer's contents, and how it ends is part of that.
    ## `diagnostics` is standard error, only commentary, kept apart so a
    ## warning is never spliced into the file.
    output*: string
    diagnostics*: seq[string]
    diagnosticsTruncated*: bool
      ## Standard error outran the limit and only its first lines were kept.
      ## Commentary is worth truncating; the output itself never is.
    exitCode*: Option[int]
      ## `none` only if the child could not be waited for. A filter that exits
      ## non-zero has still run, so the caller decides whether to apply its
      ## output.

  FilterProcessResult* = Result[FilterProcessOutput, FilterProcessError]

proc filterError*(kind: FilterFailureKind, message: string): FilterProcessError =
  FilterProcessError(kind: kind, message: message)
