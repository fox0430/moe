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

## Tests for git_cache.nim - the per-buffer git diff/branch cache.

import std/[unittest, options, os, osproc, tables, monotimes]

import pkg/results

import ../src/moepkg/[buffer, git_cache]

proc bufferAt(path: string): TextBuffer =
  ## A buffer whose file path is outside any repository, so scheduling fails
  ## immediately and no subprocess is spawned.
  result = newTextBuffer("line")
  result.filePath = some(path)

const NoRepoDir = "moe_git_cache_absent"

suite "GitCache - entry lifecycle":
  test "scheduleGitRefresh creates a cache entry":
    var gc: GitCacheState
    let buf = bufferAt(getTempDir() / NoRepoDir / "a.txt")

    gc.scheduleGitRefresh(buf)

    check gc.diffEntries.len == 1
    check gc.gitDiffPendingCount() == 0

  test "scheduleGitRefresh ignores a buffer with no file path":
    var gc: GitCacheState

    gc.scheduleGitRefresh(newTextBuffer("line"))

    check gc.diffEntries.len == 0

  test "reading the cache never creates an entry":
    var gc: GitCacheState
    let buf = bufferAt(getTempDir() / NoRepoDir / "a.txt")

    check gc.gitDiffCounts(buf) == (added: 0, modified: 0, deleted: 0)
    check gc.gitBranchName(buf) == ""
    check not gc.isBufferGitTracked(buf)

    check gc.diffEntries.len == 0
    check gc.branchEntries.len == 0

  test "a populated entry is not rescheduled until it goes stale":
    var gc: GitCacheState
    let buf = bufferAt(getTempDir() / NoRepoDir / "a.txt")

    gc.scheduleGitRefresh(buf)
    let firstRefresh = gc.diffEntries[cast[pointer](buf)].lastRefresh

    gc.scheduleGitRefresh(buf)

    check gc.diffEntries[cast[pointer](buf)].lastRefresh == firstRefresh

  test "requestGitRefresh forces a reschedule without a buffer change":
    var gc: GitCacheState
    let buf = bufferAt(getTempDir() / NoRepoDir / "a.txt")

    gc.scheduleGitRefresh(buf)
    let firstRefresh = gc.diffEntries[cast[pointer](buf)].lastRefresh

    gc.requestGitRefresh(buf)
    check gc.diffEntries[cast[pointer](buf)].forced
    gc.scheduleGitRefresh(buf)

    check not gc.diffEntries[cast[pointer](buf)].forced
    check gc.diffEntries[cast[pointer](buf)].lastRefresh >= firstRefresh

  test "a buffer edit reschedules on the next tick":
    var gc: GitCacheState
    let buf = bufferAt(getTempDir() / NoRepoDir / "a.txt")

    gc.scheduleGitRefresh(buf)
    check gc.diffEntries[cast[pointer](buf)].changeSeqAtRefresh == buf.changeSeq

    buf.changeSeq = buf.changeSeq + 1
    gc.scheduleGitRefresh(buf)

    check gc.diffEntries[cast[pointer](buf)].changeSeqAtRefresh == buf.changeSeq

suite "GitCache - eviction":
  test "evictGitCacheForBuffer removes both diff and branch entries":
    var gc: GitCacheState
    let buf = bufferAt(getTempDir() / NoRepoDir / "a.txt")

    gc.scheduleGitRefresh(buf)
    gc.refreshGitBranch(buf)
    check gc.diffEntries.len == 1
    check gc.branchEntries.len == 1

    gc.evictGitCacheForBuffer(buf)

    check gc.diffEntries.len == 0
    check gc.branchEntries.len == 0

  test "evictGitCacheForBuffer is safe when the entry is absent":
    var gc: GitCacheState

    gc.evictGitCacheForBuffer(bufferAt(getTempDir() / NoRepoDir / "a.txt"))

    check gc.diffEntries.len == 0

  test "evictGitCacheForBuffer only drops the targeted buffer":
    var gc: GitCacheState
    let buf1 = bufferAt(getTempDir() / NoRepoDir / "a.txt")
    let buf2 = bufferAt(getTempDir() / NoRepoDir / "b.txt")

    gc.scheduleGitRefresh(buf1)
    gc.scheduleGitRefresh(buf2)
    check gc.diffEntries.len == 2

    gc.evictGitCacheForBuffer(buf1)

    check gc.diffEntries.len == 1

  test "clearGitCache clears all entries":
    var gc: GitCacheState
    let buf1 = bufferAt(getTempDir() / NoRepoDir / "a.txt")
    let buf2 = bufferAt(getTempDir() / NoRepoDir / "b.txt")

    gc.scheduleGitRefresh(buf1)
    gc.scheduleGitRefresh(buf2)
    gc.refreshGitBranch(buf1)

    gc.clearGitCache()

    check gc.diffEntries.len == 0
    check gc.branchEntries.len == 0

  test "clearGitCache is idempotent on an empty cache":
    var gc: GitCacheState

    gc.clearGitCache()
    gc.clearGitCache()

    check gc.diffEntries.len == 0

suite "GitCache - refresh interval":
  test "setGitDiffRefreshInterval accepts positive values":
    var gc: GitCacheState

    gc.setGitDiffRefreshInterval(777)

    check gc.diffRefreshIntervalMs == 777

  test "setGitDiffRefreshInterval ignores zero and negative values":
    var gc: GitCacheState
    gc.setGitDiffRefreshInterval(500)

    gc.setGitDiffRefreshInterval(0)
    check gc.diffRefreshIntervalMs == 500

    gc.setGitDiffRefreshInterval(-1)
    check gc.diffRefreshIntervalMs == 500

suite "GitCache - pipeline reaping":
  # Real repo so `scheduleGitRefresh` actually spawns a pipeline. Once
  # scheduled it is never rescheduled — the point is that a hidden buffer
  # (whose status line is not drawn) still gets its pipeline reaped.
  setup:
    let testDir = getTempDir() / "moe_git_cache_tick_test"
    if dirExists(testDir):
      removeDir(testDir)
    createDir(testDir)
    discard execCmdEx("git init", workingDir = testDir)
    discard execCmdEx("git config user.email 'test@test.com'", workingDir = testDir)
    discard execCmdEx("git config user.name 'Test'", workingDir = testDir)
    let testFile = testDir / "test.txt"
    writeFile(testFile, "line 1\nline 2\nline 3\n")
    discard execCmdEx("git add test.txt", workingDir = testDir)
    discard execCmdEx("git commit -m init", workingDir = testDir)

  teardown:
    if dirExists(testDir):
      removeDir(testDir)

  test "reapGitPipelines reaps a hidden buffer's pending pipeline":
    var gc: GitCacheState
    let buf = newTextBuffer()
    check buf.loadFile(testFile).isOk

    gc.scheduleGitRefresh(buf)
    check gc.gitDiffPendingCount() == 1

    var reaped = false
    for _ in 0 ..< 200:
      gc.reapGitPipelines()
      if gc.gitDiffPendingCount() == 0:
        reaped = true
        break
      sleep(50)

    check reaped
    let counts = gc.gitDiffCacheCounts(buf)
    check counts.isSome
    # File is unchanged from HEAD so counts must be zero.
    check counts.get == (added: 0, modified: 0, deleted: 0)
    check gc.isBufferGitTracked(buf)

    gc.clearGitCache()

  test "reapGitPipelines is a no-op when no pipeline is pending":
    var gc: GitCacheState
    gc.reapGitPipelines()
    check gc.diffEntries.len == 0

    let buf = bufferAt(getTempDir() / NoRepoDir / "a.txt")
    gc.scheduleGitRefresh(buf)
    check gc.gitDiffPendingCount() == 0
    let before = gc.gitDiffCacheCounts(buf)

    gc.reapGitPipelines()

    check gc.gitDiffPendingCount() == 0
    check gc.gitDiffCacheCounts(buf) == before
