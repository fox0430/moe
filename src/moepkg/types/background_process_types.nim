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
## `Editor.runningBackgroundProcesses` field) do not transitively pull in the
## async runtime procs. The async spawn/wait/kill procs stay in
## `background_process`.

import std/options

import pkg/results
import pkg/chronos/asyncproc

type
  BackgroundProcessCommand* = object
    cmd*: string
    args*: seq[string]
    workingDir*: string

  BackgroundProcess* = ref object
    process*: AsyncProcessRef
      ## The live handle, released once the run is over. `isNil` only means
      ## the handle is gone - it is `reaped` that says whether the pid is.
    reaped*: bool
      ## The child has been waited for, so its pid may already be somebody
      ## else's and nothing may signal it again. A field rather than a question
      ## asked of the handle: the reap and the release of the handle are
      ## separated by suspension points, and the editor can kill a registered
      ## job in between. Every place that reaps sets it; `kill` and `cancel`
      ## are the only readers.
    exitCode*: Option[int]
      ## Exit status, filled in once the process is reaped. `none` covers both
      ## "not waited for yet" and "could not be determined": neither is a
      ## status, and an `int` sentinel for them is indistinguishable from a
      ## command that really exited with that code.

  ProcessRunOutcome* = enum
    ## How a run left the bounded wait. Cancellation is kept apart from a
    ## timeout: the editor asked for one, the command earned the other.
    proCompleted
    proTimedOut
    proCancelled

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
