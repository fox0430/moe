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

## Types for the per-buffer git cache. Split out from `git_cache` so `types`
## can hold the cache on `EditorState` without pulling in the pipeline logic.

import std/[options, tables, monotimes]

import ../git_diff

const DefaultGitDiffRefreshIntervalMs*: int64 = 2000

type
  GitDiffCacheEntry* = object
    counts*: tuple[added, modified, deleted: int]
    changeSeqAtRefresh*: int
    lastRefresh*: MonoTime
    pending*: Option[GitDiffProcess]
    populated*: bool
    forced*: bool ## Invalidated by an event that doesn't bump `changeSeq`.
    gitTracked*: bool
      ## File exists in HEAD, per the last completed pipeline. Suppresses the
      ## session "modified lines" gutter fallback, which would otherwise draw
      ## the same glyphs from history rather than content.
    pendingDiffInfo*: Option[GitDiffInfo]
      ## Latest completed diff, consumed by the tick for the sidebar gutter.

  GitBranchCacheEntry* = object
    path*: string
    name*: string
    lastRefresh*: MonoTime
    populated*: bool

  GitCacheState* = object
    ## Per-buffer git status owned by `EditorState`. Both refresh cycles are
    ## driven from the editor tick; the render path only reads.
    diffEntries*: Table[pointer, GitDiffCacheEntry]
    branchEntries*: Table[pointer, GitBranchCacheEntry]
    diffRefreshIntervalMs*: int64
