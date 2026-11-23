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

import std/[options, tables, monotimes, osproc]

import git_diff_types
import ../buffer/core

const DefaultGitDiffRefreshIntervalMs*: int64 = 2000

type
  GitRefreshMode* = enum
    grmPeriodic ## Refresh on edits, explicit requests and elapsed intervals.
    grmEventDriven ## Refresh on edits and requests; retry failures after a delay.

  GitDiffCacheEntry* = object
    counts*: tuple[added, modified, deleted: int]
    contentVersionAtRefresh*: int
      ## The buffer's `contentVersion` when the last pipeline started; a diff
      ## reads the buffer then. Unlike `changeSeq` it is never restored by
      ## undo nor left alone by the no-undo preview, so it names the text.
    lastRefresh*: MonoTime
    retryAfter*: Option[MonoTime] ## Failed starts retry in either refresh mode.
    pending*: Option[GitDiffProcess]
    sourceBuffer*: TextBuffer
    pathAtRefresh*: string
    repositoryPath*: string
    populated*: bool
    forced*: bool
      ## Run again on the next tick: invalidated by an event that doesn't
      ## change the content, or a probe found the file tracked.
    gitTracked*: bool
      ## File exists in HEAD, per the last pipeline git answered. Picks a full
      ## diff over a probe, and suppresses the session "modified lines" gutter
      ## fallback, which would otherwise draw the same glyphs from history
      ## rather than content.
    resolvedOutsideRepo*: bool
      ## A tracked symlink pointing outside the repo, per the same answer.
      ## HEAD holds only the link text, so it stays on probes.
    pendingDiffInfo*: Option[GitDiffInfo]
      ## Latest completed diff, consumed by the tick for the sidebar gutter.

  GitBranchCacheEntry* = object
    path*: string
    repositoryPath*: string
    lastRefresh*: MonoTime
    populated*: bool

  GitRepositoryCacheEntry* = object
    name*: string
    lastRefresh*: MonoTime
    retryAfter*: Option[MonoTime] ## Failed queries retry in either refresh mode.
    populated*: bool
    generation*: uint64
    pendingGeneration*: uint64
    forced*: bool
    pending*: Process
    started*: MonoTime

  GitCacheState* = object
    ## Git state owned by EditorState: buffer diffs and shared worktree branches.
    ## Both refresh cycles are driven from the editor tick; rendering only reads.
    diffEntries*: Table[BufferId, GitDiffCacheEntry]
    branchEntries*: Table[BufferId, GitBranchCacheEntry]
    repositories*: Table[string, GitRepositoryCacheEntry]
    diffRefreshIntervalMs*: int64
    refreshMode*: GitRefreshMode
    revision*: uint64 ## Advances when a completed result is published.
