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

## Regression tests for the sidebar marker fix: when the git-diff gutter is
## active for a git-tracked file, the session "modified lines" fallback is
## suppressed so the two don't draw overlapping `~`/`+` markers. The lingering
## session marker (history-based) used to look like a stuck git marker after a
## buffer was edited back to match HEAD (git diff goes empty, but the line stays
## flagged). See `git_cache.isBufferGitTracked` / `editor_render_window`.

import std/[os, osproc, options, unittest]

import pkg/results

import ../src/moepkg/[buffer, git_cache, sidebar]

proc setupRepo(dir: string) =
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  discard execCmdEx("git init", workingDir = dir)
  discard execCmdEx("git config user.email 'test@test.com'", workingDir = dir)
  discard execCmdEx("git config user.name 'Test'", workingDir = dir)

proc runDiff(gc: var GitCacheState, b: TextBuffer) =
  ## Drive one full diff cycle the way the editor tick does, then wait for the
  ## pipeline to finish.
  gc.requestGitRefresh(b)
  gc.scheduleGitRefresh(b)
  for _ in 0 ..< 200:
    gc.reapGitPipelines()
    if gc.gitDiffPendingCount() == 0:
      return
    sleep(10)

proc waitTracked(gc: var GitCacheState, b: TextBuffer): bool =
  gc.runDiff(b)
  gc.isBufferGitTracked(b)

suite "Sidebar git-tracked detection":
  test "isBufferGitTracked is false before the cache is populated":
    var gc: GitCacheState
    let b = newTextBuffer("a\nb\n")
    check not gc.isBufferGitTracked(b)

  test "tracked (committed) file -> isBufferGitTracked true":
    let dir = getTempDir() / "moe_track_committed"
    setupRepo(dir)
    let f = dir / "a.txt"
    writeFile(f, "line 1\nline 2\nline 3\n")
    discard execCmdEx("git add a.txt", workingDir = dir)
    discard execCmdEx("git commit -m init", workingDir = dir)

    setConfiguredBackend(GapBuffer)
    var gc: GitCacheState
    let b = newTextBuffer()
    check b.loadFile(f).isOk
    check gc.waitTracked(b)
    gc.evictGitCacheForBuffer(b)
    removeDir(dir)

  test "untracked file inside a repo -> isBufferGitTracked false":
    let dir = getTempDir() / "moe_track_untracked"
    setupRepo(dir)
    let f = dir / "new.txt"
    writeFile(f, "line 1\nline 2\n") # never `git add`ed

    setConfiguredBackend(GapBuffer)
    var gc: GitCacheState
    let b = newTextBuffer()
    check b.loadFile(f).isOk
    # err-on-schedule populates immediately, so a single drive is enough.
    gc.runDiff(b)
    check not gc.isBufferGitTracked(b)
    gc.evictGitCacheForBuffer(b)
    removeDir(dir)

  test "file outside any git repo -> isBufferGitTracked false":
    let dir = getTempDir() / "moe_track_nogit"
    if dirExists(dir):
      removeDir(dir)
    createDir(dir)
    let f = dir / "a.txt"
    writeFile(f, "line 1\n")

    setConfiguredBackend(GapBuffer)
    var gc: GitCacheState
    let b = newTextBuffer()
    check b.loadFile(f).isOk
    gc.runDiff(b)
    check not gc.isBufferGitTracked(b)
    gc.evictGitCacheForBuffer(b)
    removeDir(dir)

suite "Sidebar marker overlap after edit-back-to-original":
  test "git markers clear but session markers linger (the bug), suppression hides them":
    let dir = getTempDir() / "moe_track_editback"
    setupRepo(dir)
    let f = dir / "a.txt"
    writeFile(f, "line 1\nline 2\nline 3\n")
    discard execCmdEx("git add a.txt", workingDir = dir)
    discard execCmdEx("git commit -m init", workingDir = dir)

    setConfiguredBackend(GapBuffer)
    var gc: GitCacheState
    let b = newTextBuffer()
    check b.loadFile(f).isOk
    check gc.waitTracked(b)

    # Insert a line, then delete it again so the content matches HEAD.
    discard b.insert(1, "inserted")
    discard b.deleteLine(1)
    check b.getFileContent() == "line 1\nline 2\nline 3\n"

    # git diff is now empty -> git markers all cleared.
    gc.runDiff(b)
    check gc.gitDiffCounts(b) == (added: 0, modified: 0, deleted: 0)
    gc.applyPendingGitMarkers(b)
    for ln in 0 ..< b.len:
      check b.getLineMarker(ln).isNone

    # ...but a session modifiedLines flag lingers (reached via edit, not undo,
    # so changeSeq never returned to savedSeq).
    var anySession = false
    for m in b.modifiedLines:
      if m != lmkUnmodified:
        anySession = true
    check anySession

    # With showModifiedLines suppressed (what the renderer does for a tracked
    # file when showGitDiff is on), the sidebar shows nothing.
    let suppressed = generateSidebarFromBuffer(
      b,
      0,
      b.len,
      modifiedLines = b.modifiedLines,
      showModifiedLines = false,
      bookmarks = b.bookmarks,
    )
    for ln in 0 ..< b.len:
      check suppressed.buffer[ln][0].kind.isNone

    # Sanity: without suppression the lingering session marker would still show,
    # which is exactly the stuck-`~`/`+` the user reported.
    let notSuppressed = generateSidebarFromBuffer(
      b,
      0,
      b.len,
      modifiedLines = b.modifiedLines,
      showModifiedLines = true,
      bookmarks = b.bookmarks,
    )
    var shown = false
    for ln in 0 ..< b.len:
      if notSuppressed.buffer[ln][0].kind.isSome:
        shown = true
    check shown

    # And the gate the renderer uses is satisfied for this buffer.
    check gc.isBufferGitTracked(b)

    gc.evictGitCacheForBuffer(b)
    removeDir(dir)
