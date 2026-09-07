## Event-driven embedding, repository sharing and stale-result regressions.
import std/[options, os, osproc, streams, tables, tempfiles, monotimes, times]
import pkg/results
import ../src/moepkg/[buffer, git_cache]

proc git(root: string, args: openArray[string]): string =
  let child = startProcess(
    "git", workingDir = root, args = args, options = {poUsePath, poStdErrToStdOut}
  )
  try:
    result = child.outputStream.readAll()
    doAssert child.waitForExit() == 0, result
  finally:
    child.close()

proc repository(): string =
  result = expandFilename(createTempDir("moe-refresh-events-", ""))
  discard git(result, ["init", "-q"])
  discard git(result, ["symbolic-ref", "HEAD", "refs/heads/main"])
  writeFile(result / "a.txt", "one\n")
  createDir(result / "sub")
  writeFile(result / "sub/b.txt", "two\n")
  discard git(result, ["add", "."])
  discard git(
    result,
    [
      "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm",
      "initial",
    ],
  )

proc load(path: string): TextBuffer =
  result = newTextBuffer()
  doAssert result.loadFile(path).isOk

proc pending(gc: GitCacheState): bool =
  if gc.gitDiffPendingCount() > 0:
    return true
  for entry in gc.repositories.values:
    if not entry.pending.isNil:
      return true

proc drain(gc: var GitCacheState) =
  let deadline = getMonoTime() + initDuration(seconds = 10)
  while gc.pending() and getMonoTime() < deadline:
    gc.reapGitPipelines()
    if gc.pending():
      sleep(1)
  doAssert not gc.pending()

block event_mode_suppresses_ttl_but_keeps_edits_and_requests:
  let root = repository()
  var gc: GitCacheState
  defer:
    gc.clearGitCache()
    removeDir(root)
  let b = load(root / "a.txt")
  gc.setGitRefreshMode(grmEventDriven)
  gc.scheduleGitRefresh(b)
  gc.refreshGitBranch(b)
  gc.drain()
  doAssert gc.gitBranchName(b) == "main"
  doAssert gc.gitDiffCacheCounts(b).isSome
  doAssert gc.revision > 0
  gc.diffEntries[b.id].lastRefresh = getMonoTime() - initDuration(hours = 1)
  gc.repositories[root].lastRefresh = getMonoTime() - initDuration(hours = 1)
  let revision = gc.revision
  gc.scheduleGitRefresh(b)
  gc.refreshGitBranch(b)
  doAssert not gc.pending()
  doAssert gc.revision == revision
  inc b.changeSeq
  gc.scheduleGitRefresh(b)
  doAssert gc.gitDiffPendingCount() == 1
  gc.drain()
  gc.requestGitRefresh(b)
  gc.scheduleGitRefresh(b)
  doAssert gc.gitDiffPendingCount() == 1
  gc.drain()
  gc.setGitRefreshMode(grmPeriodic)
  gc.diffEntries[b.id].lastRefresh = getMonoTime() - initDuration(hours = 1)
  gc.scheduleGitRefresh(b)
  gc.refreshGitBranch(b)
  doAssert gc.gitDiffPendingCount() == 1
  doAssert not gc.repositories[root].pending.isNil

block branch_query_is_shared_and_notifications_are_scoped:
  let root = repository()
  let otherRoot = repository()
  var gc: GitCacheState
  defer:
    gc.clearGitCache()
    removeDir(root)
    removeDir(otherRoot)
  gc.setGitRefreshMode(grmEventDriven)
  let a = load(root / "a.txt")
  let b = load(root / "sub/b.txt")
  let other = load(otherRoot / "a.txt")
  gc.refreshGitBranch(a)
  let child = gc.repositories[root].pending
  gc.refreshGitBranch(b)
  doAssert gc.repositories.len == 1
  doAssert gc.repositories[root].pending == child
  gc.refreshGitBranch(other)
  gc.scheduleGitRefresh(a)
  gc.scheduleGitRefresh(other)
  gc.drain()
  discard git(root, ["checkout", "-qb", "updated"])
  gc.notifyGitRepositoryChanged(root)
  doAssert gc.diffEntries[a.id].forced
  doAssert not gc.diffEntries[other.id].forced
  doAssert gc.repositories[root].forced
  doAssert not gc.repositories[otherRoot].forced
  doAssert not gc.pending() # notification does not launch work
  gc.refreshGitBranch(b)
  gc.drain()
  doAssert gc.gitBranchName(a) == "updated"
  doAssert gc.gitBranchName(b) == "updated"
  doAssert gc.gitBranchName(other) == "main"
  gc.evictGitCacheForBuffer(a)
  doAssert root in gc.repositories
  gc.evictGitCacheForBuffer(b)
  doAssert root notin gc.repositories

block superseded_diffs_never_publish:
  let root = repository()
  var gc: GitCacheState
  defer:
    gc.clearGitCache()
    removeDir(root)
  gc.setGitRefreshMode(grmEventDriven)
  let b = load(root / "a.txt")
  for reason in 0 .. 2:
    gc.scheduleGitRefresh(b)
    doAssert gc.gitDiffPendingCount() == 1
    case reason
    of 0:
      inc b.changeSeq
    of 1:
      b.filePath = some(root / "sub/b.txt")
    else:
      gc.notifyGitRepositoryChanged(root)
    let revision = gc.revision
    gc.drain()
    doAssert gc.diffEntries[b.id].forced
    doAssert gc.diffEntries[b.id].pendingDiffInfo.isNone
    doAssert gc.revision == revision
  gc.scheduleGitRefresh(b)
  gc.drain()
  doAssert not gc.diffEntries[b.id].forced
  doAssert gc.gitDiffCacheCounts(b).isSome

block in_flight_branch_notification_discards_old_result:
  let root = repository()
  var gc: GitCacheState
  defer:
    gc.clearGitCache()
    removeDir(root)
  gc.setGitRefreshMode(grmEventDriven)
  let b = load(root / "a.txt")
  gc.refreshGitBranch(b)
  gc.notifyGitRepositoryChanged(root)
  gc.drain()
  doAssert gc.gitBranchName(b) == ""
  doAssert gc.revision == 0
  doAssert gc.repositories[root].forced
  gc.refreshGitBranch(b)
  gc.drain()
  doAssert gc.gitBranchName(b) == "main"

block linked_worktrees_have_separate_branch_entries:
  let root = repository()
  let container = expandFilename(createTempDir("moe-refresh-worktree-", ""))
  let worktree = container / "linked"
  var gc: GitCacheState
  defer:
    gc.clearGitCache()
    removeDir(container)
    removeDir(root)
  discard git(root, ["worktree", "add", "-qb", "linked", worktree])
  let a = load(root / "a.txt")
  let b = load(worktree / "a.txt")
  gc.refreshGitBranch(a)
  gc.refreshGitBranch(b)
  gc.drain()
  doAssert gc.repositories.len == 2
  doAssert gc.gitBranchName(a) == "main"
  doAssert gc.gitBranchName(b) == "linked"

block notification_discovers_a_new_repository:
  let root = expandFilename(createTempDir("moe-refresh-init-", ""))
  var gc: GitCacheState
  defer:
    gc.clearGitCache()
    removeDir(root)
  writeFile(root / "a.txt", "one\n")
  let b = load(root / "a.txt")
  gc.setGitRefreshMode(grmEventDriven)
  gc.refreshGitBranch(b)
  gc.scheduleGitRefresh(b)
  gc.drain()
  doAssert gc.repositories.len == 0
  discard git(root, ["init", "-q"])
  discard git(root, ["add", "."])
  discard git(
    root,
    [
      "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm",
      "initial",
    ],
  )
  gc.notifyGitRepositoryChanged(root)
  gc.refreshGitBranch(b)
  gc.scheduleGitRefresh(b)
  gc.drain()
  doAssert gc.repositories.len == 1
  doAssert gc.isBufferGitTracked(b)

echo "Git refresh event regressions passed"
