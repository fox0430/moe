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
## flagged). See `status_line.isBufferGitTracked` / `editor_render_window`.

import std/[os, osproc, options, unittest]

import pkg/results

import ../src/moepkg/[buffer, git_diff, sidebar]
import ../src/moepkg/status_line {.all.}

proc setupRepo(dir: string) =
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  discard execCmdEx("git init", workingDir = dir)
  discard execCmdEx("git config user.email 'test@test.com'", workingDir = dir)
  discard execCmdEx("git config user.name 'Test'", workingDir = dir)

proc waitTracked(b: TextBuffer): bool =
  ## Drive the (status-line) diff scheduler until the async diff finishes and the
  ## git-tracked flag is populated, or give up after a timeout.
  for _ in 0 ..< 200:
    discard cachedGitDiffCounts(b)
    if isBufferGitTracked(b):
      return true
    sleep(10)
  isBufferGitTracked(b)

suite "Sidebar git-tracked detection":
  test "isBufferGitTracked is false before the cache is populated":
    let b = newTextBuffer("a\nb\n")
    check not isBufferGitTracked(b)

  test "tracked (committed) file -> isBufferGitTracked true":
    let dir = getTempDir() / "moe_track_committed"
    setupRepo(dir)
    let f = dir / "a.txt"
    writeFile(f, "line 1\nline 2\nline 3\n")
    discard execCmdEx("git add a.txt", workingDir = dir)
    discard execCmdEx("git commit -m init", workingDir = dir)

    setConfiguredBackend(GapBuffer)
    let b = newTextBuffer()
    check b.loadFile(f).isOk
    check b.waitTracked()
    evictGitCacheForBuffer(b)
    removeDir(dir)

  test "untracked file inside a repo -> isBufferGitTracked false":
    let dir = getTempDir() / "moe_track_untracked"
    setupRepo(dir)
    let f = dir / "new.txt"
    writeFile(f, "line 1\nline 2\n") # never `git add`ed

    setConfiguredBackend(GapBuffer)
    let b = newTextBuffer()
    check b.loadFile(f).isOk
    # err-on-schedule populates immediately, so a single drive is enough.
    discard cachedGitDiffCounts(b)
    check not isBufferGitTracked(b)
    evictGitCacheForBuffer(b)
    removeDir(dir)

  test "file outside any git repo -> isBufferGitTracked false":
    let dir = getTempDir() / "moe_track_nogit"
    if dirExists(dir):
      removeDir(dir)
    createDir(dir)
    let f = dir / "a.txt"
    writeFile(f, "line 1\n")

    setConfiguredBackend(GapBuffer)
    let b = newTextBuffer()
    check b.loadFile(f).isOk
    discard cachedGitDiffCounts(b)
    check not isBufferGitTracked(b)
    evictGitCacheForBuffer(b)
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
    let b = newTextBuffer()
    check b.loadFile(f).isOk
    check b.waitTracked()

    # Insert a line, then delete it again so the content matches HEAD.
    discard b.insert(1, "inserted")
    discard b.deleteLine(1)
    check b.getFileContent() == "line 1\nline 2\nline 3\n"

    # git diff is now empty -> git markers all cleared.
    let diff = getGitDiffFromBuffer(b)
    check diff.isOk
    check diff.get.lines.len == 0
    applyGitDiffToBuffer(b, diff.get)
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
    check isBufferGitTracked(b)

    evictGitCacheForBuffer(b)
    removeDir(dir)
