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

## Per-buffer diffs and per-worktree asynchronous branch cache.
##
## Without caching every frame would spawn `git diff` (dumping the whole buffer
## to a tempfile, ~30ms on a 40k-line JSON) and `git rev-parse`, pegging idle
## j/k at ~30 FPS. Both refresh cycles run from the editor tick
## (`reapGitPipelines` / `scheduleGitRefresh` / `refreshGitBranch`); the render
## path only reads `gitDiffCounts` / `gitBranchName` / `isBufferGitTracked`.
##
## Diffs are refreshed when `changeSeq` moves, when `requestGitRefresh` marks
## the entry stale, or on a TTL in periodic mode. Embedding hosts may disable
## TTLs and notify repository changes themselves. Previous counts stay on
## screen until a current (not superseded) pipeline completes.

import std/[options, tables, monotimes, times, os, osproc, streams, strutils]

import pkg/results

import buffer/core, git_diff
import types/git_cache_types

export git_cache_types

const GitBranchTtlMs = 5000

proc canonicalDirectory(path: string): string =
  result = normalizedPath(absolutePath(path))
  try:
    result = expandFilename(result)
  except OSError:
    discard

proc repositoryForFile(path: string): string =
  # Worktrees and submodules have a .git file rather than a directory. Key by
  # worktree root, not common Git storage: linked worktrees have different HEADs.
  var directory = canonicalDirectory(path.parentDir())
  while directory.len > 0:
    if dirExists(directory / ".git") or fileExists(directory / ".git"):
      return directory
    let parent = directory.parentDir()
    if parent == directory:
      break
    directory = parent

proc bufferKey(b: TextBuffer): BufferId =
  ## Stable per-buffer key: BufferId survives buffer moves/GC, unlike a raw
  ## pointer (which could be reused after collection).
  b.id

proc refreshIntervalMs(gc: GitCacheState): int64 =
  if gc.diffRefreshIntervalMs > 0:
    gc.diffRefreshIntervalMs
  else:
    DefaultGitDiffRefreshIntervalMs

proc setGitDiffRefreshInterval*(gc: var GitCacheState, ms: int64) =
  ## Backs the `[git] updateInterval` toml setting.
  if ms > 0:
    gc.diffRefreshIntervalMs = ms

proc reapPendingDiff(entry: var GitDiffCacheEntry): bool =
  ## Advance a pending pipeline; on completion release its child, tempfiles and
  ## fds. On error/timeout keep the last known counts.
  if entry.pending.isNone:
    return
  let completion = checkGitDiffComplete(entry.pending.get)
  if completion.isNone:
    return
  entry.pending = none(GitDiffProcess)
  if entry.forced or (
    not entry.sourceBuffer.isNil and (
      entry.sourceBuffer.filePath.get("") != entry.pathAtRefresh or
      entry.sourceBuffer.changeSeq != entry.changeSeqAtRefresh
    )
  ):
    entry.forced = true
    entry.pendingDiffInfo = none(GitDiffInfo)
    return
  # The pipeline errors for files not in HEAD, so a successful run doubles as
  # the "git-tracked" probe for the sidebar.
  entry.gitTracked = completion.get.isOk
  if completion.get.isOk:
    let diffInfo = completion.get.get
    entry.counts = countGitChangedLines(diffInfo)
    entry.pendingDiffInfo = some(diffInfo)
  entry.lastRefresh = getMonoTime()
  entry.populated = true
  result = true

proc reapBranch(entry: var GitRepositoryCacheEntry): bool =
  if entry.pending.isNil:
    return
  try:
    let exitCode = entry.pending.peekExitCode()
    if exitCode == -1:
      if (getMonoTime() - entry.started).inSeconds < 5:
        return
      releaseGitProcess(entry.pending)
      entry.lastRefresh = getMonoTime()
      entry.populated = true
      return
    let output = entry.pending.outputStream().readAll()
    releaseGitProcess(entry.pending)
    if entry.pendingGeneration != entry.generation:
      return
    entry.name =
      if exitCode == 0:
        output.strip()
      else:
        ""
    entry.lastRefresh = getMonoTime()
    entry.populated = true
    result = true
  except CatchableError:
    releaseGitProcess(entry.pending)
    entry.lastRefresh = getMonoTime()
    entry.populated = true

proc reapGitPipelines*(gc: var GitCacheState) =
  ## Reap every buffer's pipeline, not just the visible ones — a buffer hidden
  ## mid-flight would otherwise leak its child, tempfiles and pipe fds.
  for entry in gc.diffEntries.mvalues:
    if reapPendingDiff(entry):
      inc gc.revision
  for entry in gc.repositories.mvalues:
    if reapBranch(entry):
      inc gc.revision

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
    entry.pathAtRefresh != b.filePath.get or (
      gc.refreshMode == grmPeriodic and
      (now - entry.lastRefresh).inMilliseconds >= gc.refreshIntervalMs
    )

  if not needsRefresh:
    return

  entry.forced = false
  entry.pendingDiffInfo = none(GitDiffInfo)
  entry.sourceBuffer = b
  entry.pathAtRefresh = b.filePath.get
  entry.repositoryPath = repositoryForFile(entry.pathAtRefresh)
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
  entry.pendingDiffInfo = none(GitDiffInfo)
  gc.diffEntries[key] = entry

proc setGitRefreshMode*(gc: var GitCacheState, mode: GitRefreshMode) =
  ## Select how elapsed time affects scheduling. Explicit requests and edits
  ## continue to refresh in either mode; pending children are still reaped.
  gc.refreshMode = mode

proc notifyGitRepositoryChanged*(gc: var GitCacheState, rootPath: string) =
  ## Invalidate a worktree after a host-observed Git or filesystem change.
  ## Pass the worktree root (not its .git directory). Empty invalidates all.
  ## Call on the owning editor thread; this never launches a process.
  let root =
    if rootPath.len > 0:
      canonicalDirectory(rootPath)
    else:
      ""
  for path, entry in gc.repositories.mpairs:
    if root.len == 0 or path == root:
      inc entry.generation
      entry.forced = true
  for entry in gc.diffEntries.mvalues:
    if root.len == 0 or entry.repositoryPath == root or (
      entry.repositoryPath.len == 0 and not entry.sourceBuffer.isNil and
      repositoryForFile(entry.sourceBuffer.filePath.get("")) == root
    ):
      entry.forced = true
      entry.pendingDiffInfo = none(GitDiffInfo)
  # Re-discover previously non-repository files after git init, or a moved root.
  for entry in gc.branchEntries.mvalues:
    if root.len == 0 or entry.repositoryPath == root or entry.repositoryPath.len == 0:
      entry.populated = false

proc refreshGitBranch*(gc: var GitCacheState, b: TextBuffer) =
  ## Schedule a branch lookup shared by all buffers in the same worktree.
  ## Completion is delivered by reapGitPipelines; no Git command blocks here.
  if b.filePath.isNone:
    return

  let filePath = b.filePath.get
  let key = bufferKey(b)
  var entry = gc.branchEntries.getOrDefault(key)

  let now = getMonoTime()
  if not entry.populated or entry.path != filePath or (
    gc.refreshMode == grmPeriodic and
    (now - entry.lastRefresh).inMilliseconds >= GitBranchTtlMs
  ):
    entry.path = filePath
    entry.repositoryPath = repositoryForFile(filePath)
    entry.lastRefresh = now
    entry.populated = true
    gc.branchEntries[key] = entry
  if entry.repositoryPath.len == 0:
    return
  var repository = gc.repositories.getOrDefault(entry.repositoryPath)
  let expired =
    repository.forced or not repository.populated or (
      gc.refreshMode == grmPeriodic and
      (now - repository.lastRefresh).inMilliseconds >= GitBranchTtlMs
    )
  if repository.pending.isNil and expired:
    repository.forced = false
    repository.pendingGeneration = repository.generation
    repository.started = now
    try:
      repository.pending = startProcess(
        "git",
        args = [
          "-C", entry.repositoryPath, "--no-optional-locks", "rev-parse",
          "--abbrev-ref", "HEAD",
        ],
        options = {poUsePath, poStdErrToStdOut},
      )
    except CatchableError:
      repository.lastRefresh = now
      repository.populated = true
    gc.repositories[entry.repositoryPath] = repository

proc gitDiffCounts*(
    gc: GitCacheState, b: TextBuffer
): tuple[added, modified, deleted: int] =
  gc.diffEntries.getOrDefault(bufferKey(b)).counts

proc gitBranchName*(gc: GitCacheState, b: TextBuffer): string =
  let entry = gc.branchEntries.getOrDefault(bufferKey(b))
  if entry.repositoryPath in gc.repositories:
    gc.repositories[entry.repositoryPath].name
  else:
    entry.name

proc isBufferGitTracked*(gc: GitCacheState, b: TextBuffer): bool =
  ## Whether `b`'s file is present in HEAD, per the most recent scheduling
  ## attempt. False until the cache has been populated for this buffer.
  let entry = gc.diffEntries.getOrDefault(bufferKey(b))
  entry.populated and entry.gitTracked

proc applyPendingGitMarkers*(gc: var GitCacheState, b: TextBuffer) =
  ## Apply the most recent completed diff to the sidebar gutter. No-op if
  ## nothing new has arrived since the last call.
  gc.diffEntries.withValue(bufferKey(b), entry):
    if entry[].pendingDiffInfo.isSome and not entry[].forced and
        entry[].changeSeqAtRefresh == b.changeSeq and
        entry[].pathAtRefresh == b.filePath.get(""):
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
  var unused: seq[string]
  for root in gc.repositories.keys:
    var used = false
    for entry in gc.branchEntries.values:
      if entry.repositoryPath == root:
        used = true
    if not used:
      unused.add root
  for root in unused:
    releaseGitProcess(gc.repositories[root].pending)
    gc.repositories.del(root)

proc clearGitCache*(gc: var GitCacheState) =
  ## Terminate every pending pipeline and discard all entries. Called once from
  ## the shutdown path so children and tempfiles do not outlive moe.
  for entry in gc.diffEntries.mvalues:
    if entry.pending.isSome:
      abandonGitDiffProcess(entry.pending.get)
      entry.pending = none(GitDiffProcess)
  gc.diffEntries.clear()
  gc.branchEntries.clear()
  for entry in gc.repositories.mvalues:
    releaseGitProcess(entry.pending)
  gc.repositories.clear()

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
