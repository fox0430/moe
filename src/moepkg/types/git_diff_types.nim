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

## Lightweight type definitions for git diff.
##
## Split out from `git_diff` so modules that only need the diff/cache types
## (notably `types/git_cache_types`) do not transitively pull in the pipeline
## implementation (tempfiles, buffer I/O, logger, ...).

import std/osproc

type
  GitDiffLineKind* = enum
    ## Type of change in git diff
    Added ## Line was added
    Modified ## Line was modified
    Deleted ## Line was deleted

  GitDiffLine* = object ## Represents a single line change in git diff
    lineNumber*: int ## Line number in the current file (0-based)
    kind*: GitDiffLineKind ## Type of change

  GitDiffInfo* = object ## Git diff information for a file
    lines*: seq[GitDiffLine] ## Changed lines

  GitDiffStage* = enum
    ## Buffer-diff pipeline stage; advances on each `checkGitDiffComplete`.
    gdsGitRoot ## `git rev-parse --show-toplevel`
    gdsGitShow ## `git show HEAD:<relpath>`, or `git cat-file -e` when no diff follows
    gdsGitDiff ## `git diff --no-index <orig> <mod>`

  GitHeadAnswer* = enum
    ## What a pipeline learned about the file being in HEAD.
    ghUnknown ## It ended before git answered (a timeout, a failed start)
    ghTracked ## git found the file in HEAD
    ghUntracked ## Not in a repository, or not in HEAD

  GitDiffProcess* = ref object ## Background git diff pipeline
    process*: Process
    stage*: GitDiffStage
    startTime*: float ## Overall pipeline start (for timeout)
    filePath*: string
    workingDir*: string
    probe*: bool
      ## Stop once git answers whether the file is in HEAD. A probe reads
      ## neither the buffer nor HEAD's copy.
    head*: GitHeadAnswer
    tempOriginal*: string
    tempModified*: string
      ## The buffer, written before the first child starts so the copy is
      ## released at once. Empty for a probe.
    tempDiffOut*: string ## `git diff` stdout is redirected here (avoids pipe deadlock)
    resolvedOutsideRepo*: bool ## Buffer's canonical path escapes the repo root
