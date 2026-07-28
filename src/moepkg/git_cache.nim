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

## Per-buffer git diff/branch cache.
##
## Without caching every frame would spawn `git diff` (dumping the whole buffer
## to a tempfile, ~30ms on a 40k-line JSON) and `git rev-parse`, pegging idle
## j/k at ~30 FPS. Both refresh cycles run from the editor tick
## (`reapGitPipelines` / `scheduleGitRefresh` / `refreshGitBranch`); the render
## path only reads `gitDiffCounts` / `gitBranchName` / `isBufferGitTracked`.
##
## Diffs are refreshed when `changeSeq` moves, when `requestGitRefresh` marks
## the entry stale, or on a TTL — the TTL is what picks up external commits and
## checkouts without an edit. The previous counts stay on screen until the new
## pipeline completes.

import std/[options, tables, monotimes, times]

import pkg/results

import buffer/core, git_diff
import types/git_cache_types

export git_cache_types

const GitBranchTtlMs = 5000

proc bufferKey(b: TextBuffer): pointer =
  cast[pointer](b)

proc refreshIntervalMs(gc: GitCacheState): int64 =
  if gc.diffRefreshIntervalMs > 0:
    gc.diffRefreshIntervalMs
  else:
    DefaultGitDiffRefreshIntervalMs

proc setGitDiffRefreshInterval*(gc: var GitCacheState, ms: int64) =
  ## Backs the `[git] updateInterval` toml setting.
  if ms > 0:
    gc.diffRefreshIntervalMs = ms

proc reapPendingDiff(entry: var GitDiffCacheEntry) =
  ## Advance a pending pipeline; on completion release its child, tempfiles and
  ## fds. On error/timeout keep the last known counts.
  if entry.pending.isNone:
    return
  let completion = checkGitDiffComplete(entry.pending.get)
  if completion.isNone:
    return
  # The pipeline errors for files not in HEAD, so a successful run doubles as
  # the "git-tracked" probe for the sidebar.
  entry.gitTracked = completion.get.isOk
  if completion.get.isOk:
    let diffInfo = completion.get.get
    entry.counts = countGitChangedLines(diffInfo)
    entry.pendingDiffInfo = some(diffInfo)
  entry.pending = none(GitDiffProcess)
  entry.lastRefresh = getMonoTime()
  entry.populated = true

proc reapGitPipelines*(gc: var GitCacheState) =
  ## Reap every buffer's pipeline, not just the visible ones — a buffer hidden
  ## mid-flight would otherwise leak its child, tempfiles and pipe fds.
  for entry in gc.diffEntries.mvalues:
    reapPendingDiff(entry)

proc scheduleGitRefresh*(gc: var GitCacheState, b: TextBuffer) =
  ## Start a diff pipeline for `b` if the cached entry is due for a refresh.
  if b.filePath.isNone:
    return

  let key = bufferKey(b)
  var entry = gc.diffEntries.getOrDefault(key)
  if entry.pending.isSome:
    return

  let now = getMonoTime()
  let needsRefresh =
    entry.forced or not entry.populated or entry.changeSeqAtRefresh != b.changeSeq or
    (now - entry.lastRefresh).inMilliseconds >= gc.refreshIntervalMs

  if not needsRefresh:
    return

  entry.forced = false
  entry.changeSeqAtRefresh = b.changeSeq
  let startResult = startGitDiffFromBufferAsync(b)
  if startResult.isOk:
    entry.pending = some(startResult.get)
  else:
    entry.gitTracked = false
    # Count the failed start as an attempt so we don't retry every tick.
    entry.lastRefresh = now
    entry.populated = true

  gc.diffEntries[key] = entry

proc requestGitRefresh*(gc: var GitCacheState, b: TextBuffer) =
  ## Mark `b`'s diff stale so the next tick re-runs the pipeline. Used by the
  ## events that change the git state without touching the buffer: save,
  ## reload, `:e!`, and toggling the gutter on.
  if b.filePath.isNone:
    return
  let key = bufferKey(b)
  var entry = gc.diffEntries.getOrDefault(key)
  entry.forced = true
  gc.diffEntries[key] = entry

proc refreshGitBranch*(gc: var GitCacheState, b: TextBuffer) =
  ## Re-read the branch name on a TTL. Still synchronous: `git rev-parse` is
  ## ~5ms and runs at most once per buffer per `GitBranchTtlMs`.
  if b.filePath.isNone:
    return

  let filePath = b.filePath.get
  let key = bufferKey(b)
  var entry = gc.branchEntries.getOrDefault(key)

  let now = getMonoTime()
  let expired =
    not entry.populated or entry.path != filePath or
    (now - entry.lastRefresh).inMilliseconds >= GitBranchTtlMs
  if not expired:
    return

  let branchResult = getGitBranch(filePath)
  entry.path = filePath
  entry.lastRefresh = now
  entry.populated = true
  entry.name = if branchResult.isErr: "" else: branchResult.get
  gc.branchEntries[key] = entry

proc gitDiffCounts*(
    gc: GitCacheState, b: TextBuffer
): tuple[added, modified, deleted: int] =
  gc.diffEntries.getOrDefault(bufferKey(b)).counts

proc gitBranchName*(gc: GitCacheState, b: TextBuffer): string =
  gc.branchEntries.getOrDefault(bufferKey(b)).name

proc isBufferGitTracked*(gc: GitCacheState, b: TextBuffer): bool =
  ## Whether `b`'s file is present in HEAD, per the most recent scheduling
  ## attempt. False until the cache has been populated for this buffer.
  let entry = gc.diffEntries.getOrDefault(bufferKey(b))
  entry.populated and entry.gitTracked

proc applyPendingGitMarkers*(gc: var GitCacheState, b: TextBuffer) =
  ## Apply the most recent completed diff to the sidebar gutter. No-op if
  ## nothing new has arrived since the last call.
  gc.diffEntries.withValue(bufferKey(b), entry):
    if entry[].pendingDiffInfo.isSome:
      applyGitDiffToBuffer(b, entry[].pendingDiffInfo.get)
      entry[].pendingDiffInfo = none(GitDiffInfo)

proc evictGitCacheForBuffer*(gc: var GitCacheState, b: TextBuffer) =
  ## Drop `b`'s entries. Call before removing a buffer so its pending diff is
  ## terminated and its address can't alias a future buffer.
  let key = bufferKey(b)
  gc.diffEntries.withValue(key, entry):
    if entry[].pending.isSome:
      abandonGitDiffProcess(entry[].pending.get)
      entry[].pending = none(GitDiffProcess)
  gc.diffEntries.del(key)
  gc.branchEntries.del(key)

proc clearGitCache*(gc: var GitCacheState) =
  ## Terminate every pending pipeline and discard all entries. Called once from
  ## the shutdown path so children and tempfiles do not outlive moe.
  for entry in gc.diffEntries.mvalues:
    if entry.pending.isSome:
      abandonGitDiffProcess(entry.pending.get)
      entry.pending = none(GitDiffProcess)
  gc.diffEntries.clear()
  gc.branchEntries.clear()

proc gitDiffPendingCount*(gc: GitCacheState): int =
  for entry in gc.diffEntries.values:
    if entry.pending.isSome:
      inc result

proc gitDiffCacheCounts*(
    gc: GitCacheState, b: TextBuffer
): Option[tuple[added, modified, deleted: int]] =
  let entry = gc.diffEntries.getOrDefault(bufferKey(b))
  if entry.populated:
    some(entry.counts)
  else:
    none(tuple[added, modified, deleted: int])
