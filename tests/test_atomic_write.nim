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

import std/[unittest, os, strutils, options]

import pkg/results

import ../src/moepkg/buffer/atomic_write

when defined(posix):
  import std/posix

proc mkTmpDir(tag: string): string =
  ## Unique scratch directory under the system temp dir.
  var i = 0
  while true:
    let p =
      getTempDir() / ("moe_atomic_" & tag & "_" & $getCurrentProcessId() & "_" & $i)
    if not dirExists(p) and not fileExists(p):
      createDir(p)
      return p
    inc i

proc rmTree(path: string) =
  try:
    removeDir(path)
  except CatchableError:
    discard

suite "atomic_write - new file":
  test "creates a fresh file with exact content":
    let dir = mkTmpDir("new")
    defer:
      rmTree(dir)
    let path = dir / "hello.txt"

    let r = writeAtomic(path, "hello world\n")
    check r.isOk
    check readFile(path) == "hello world\n"

  test "no leftover temp files in the directory":
    let dir = mkTmpDir("newlean")
    defer:
      rmTree(dir)
    let path = dir / "a.txt"

    discard writeAtomic(path, "x")

    var leftovers: seq[string]
    for kind, p in walkDir(dir):
      let name = p.extractFilename
      if name != "a.txt":
        leftovers.add(name)
    check leftovers.len == 0

suite "atomic_write - overwrite":
  test "overwrites existing content atomically":
    let dir = mkTmpDir("over")
    defer:
      rmTree(dir)
    let path = dir / "a.txt"
    writeFile(path, "before")

    let r = writeAtomic(path, "after")
    check r.isOk
    check readFile(path) == "after"

  test "no `~` backup remains after successful overwrite":
    let dir = mkTmpDir("nobk")
    defer:
      rmTree(dir)
    let path = dir / "a.txt"
    writeFile(path, "before")

    discard writeAtomic(path, "after")

    check not fileExists(path & "~")

  test "leaves no `.moe.tmp.*` behind on success":
    let dir = mkTmpDir("notmp")
    defer:
      rmTree(dir)
    let path = dir / "a.txt"
    writeFile(path, "before")

    discard writeAtomic(path, "after")

    var tmpFiles: seq[string]
    for kind, p in walkDir(dir):
      if p.extractFilename.startsWith(".moe.tmp."):
        tmpFiles.add(p)
    check tmpFiles.len == 0

when defined(posix):
  suite "atomic_write - temp symlink attack resistance":
    test "pre-planted temp symlinks are never followed":
      let dir = mkTmpDir("plant")
      defer:
        rmTree(dir)
      let target = dir / "a.txt"
      let victim = dir / "victim.txt"
      writeFile(target, "before")
      writeFile(victim, "do not touch")

      # Plant symlinks at the names the old predictable scheme could use
      # (`.moe.tmp.<base>.<pid>.<n>`), plus a defensive bare `<n>` variant
      # that the old code never generated, all pointing at the victim.
      let pid = $getCurrentProcessId()
      for i in 0 .. 32:
        createSymlink(victim, dir / (".moe.tmp.a.txt." & pid & "." & $i))
        createSymlink(victim, dir / (".moe.tmp.a.txt." & $i))

      let r = writeAtomic(target, "after")
      check r.isOk
      check readFile(target) == "after"
      # The temp write must never have resolved one of the planted links.
      check readFile(victim) == "do not touch"

  suite "atomic_write - symlink preservation":
    test "writing through a symlink keeps the symlink":
      let dir = mkTmpDir("sym")
      defer:
        rmTree(dir)
      let real = dir / "real.txt"
      let link = dir / "link.txt"
      writeFile(real, "initial")
      createSymlink(real, link)

      let r = writeAtomic(link, "updated")
      check r.isOk

      check symlinkExists(link)
      # Writing through the link must update the real target, not replace
      # the link with a regular file.
      check readFile(real) == "updated"
      check readFile(link) == "updated"

  suite "atomic_write - hardlink preservation":
    test "hardlinks stay linked after write":
      let dir = mkTmpDir("hard")
      defer:
        rmTree(dir)
      let a = dir / "a.txt"
      let b = dir / "b.txt"
      writeFile(a, "initial")
      # posix.link creates a hardlink b -> a
      check link(a.cstring, b.cstring) == 0

      var stA, stB: Stat
      check stat(a.cstring, stA) == 0
      check stat(b.cstring, stB) == 0
      check stA.st_ino == stB.st_ino
      check stA.st_nlink >= 2

      let r = writeAtomic(a, "updated")
      check r.isOk

      # Both names must still refer to the same inode with the new content.
      var stA2, stB2: Stat
      check stat(a.cstring, stA2) == 0
      check stat(b.cstring, stB2) == 0
      check stA2.st_ino == stB2.st_ino
      check readFile(a) == "updated"
      check readFile(b) == "updated"

  suite "atomic_write - permissions preserved":
    test "temp+rename keeps the original mode":
      let dir = mkTmpDir("perm")
      defer:
        rmTree(dir)
      let path = dir / "a.txt"
      writeFile(path, "initial")

      # Set a distinctive mode (0640) — group-readable, no world.
      check chmod(path.cstring, Mode(0o640)) == 0

      let r = writeAtomic(path, "updated")
      check r.isOk

      var st: Stat
      check stat(path.cstring, st) == 0
      check (st.st_mode.int and 0o777) == 0o640

suite "atomic_write - gate premise":
  test "refuses when the gate expected nothing but something is there":
    let dir = mkTmpDir("premise")
    defer:
      rmTree(dir)
    let path = dir / "a.txt"
    writeFile(path, "before")

    let r = writeAtomic(path, "after", wpCreateExclusive)
    check r.isErr
    check r.error == FileAppearedErrorMsg
    check readFile(path) == "before"

  test "creates when the gate expected nothing and nothing is there":
    let dir = mkTmpDir("premiseabsent")
    defer:
      rmTree(dir)
    let path = dir / "fresh.txt"

    let r = writeAtomic(path, "hello", wpCreateExclusive)
    check r.isOk
    check readFile(path) == "hello"

  test "forced save ignores the gate premise":
    let dir = mkTmpDir("premiseforce")
    defer:
      rmTree(dir)
    let path = dir / "a.txt"
    writeFile(path, "before")

    let r = writeAtomic(path, "after", wpForce)
    check r.isOk
    check readFile(path) == "after"

suite "atomic_write - strategy premise":
  test "a chmod changes the re-check premise":
    # chmod changes restore strategy, so it must count as a different target.
    when defined(posix):
      let dir = mkTmpDir("premisechmod")
      defer:
        rmTree(dir)
      let path = dir / "a.txt"
      writeFile(path, "content")
      setFilePermissions(path, {fpUserRead, fpUserWrite, fpGroupRead, fpOthersRead})

      let expected = snapshotTarget(path)
      let before = classifyTarget(path)
      setFilePermissions(path, {fpUserRead, fpUserWrite})

      check writeTargetMoved(expected, before, path)
    else:
      skip()

  test "a new hardlink changes the re-check premise":
    # Same bytes and inode; only the link count says rename would split the group.
    when defined(posix):
      let dir = mkTmpDir("premiselink")
      defer:
        rmTree(dir)
      let path = dir / "a.txt"
      let alias = dir / "b.txt"
      writeFile(path, "content")

      let expected = snapshotTarget(path)
      let before = classifyTarget(path)
      createHardlink(path, alias)
      defer:
        removeFile(alias)

      check writeTargetMoved(expected, before, path)
    else:
      skip()

  test "an untouched file keeps the same premise":
    let dir = mkTmpDir("premisestable")
    defer:
      rmTree(dir)
    let path = dir / "a.txt"
    writeFile(path, "content")

    let expected = snapshotTarget(path)
    let cls = classifyTarget(path)
    check not writeTargetMoved(expected, cls, path)
    check classifyTarget(path) == classifyTarget(path)

  test "a missing initial snapshot is a moved target":
    check writeTargetMoved(none(TargetSnapshot), TargetClass(exists: true), "unused")

  test "writing through a dangling symlink is refused":
    # lstat sees a link so the in-place path is chosen; follow-stat cannot
    # name a file. Fail closed so the dangling link is not replaced.
    when defined(posix):
      let dir = mkTmpDir("premisedangle")
      defer:
        rmTree(dir)
      let path = dir / "link"
      createSymlink(dir / "missing", path)

      let r = writeAtomic(path, "after")
      check r.isErr
      check r.error == TargetChangedErrorMsg
      check symlinkExists(path)
      check not fileExists(path)
    else:
      skip()

  test "a save after an external chmod keeps the new mode":
    # Strategy is chosen at save time, so a prior chmod is restored, not reverted.
    when defined(posix):
      let dir = mkTmpDir("premisechmodsave")
      defer:
        rmTree(dir)
      let path = dir / "a.txt"
      writeFile(path, "before")
      setFilePermissions(path, {fpUserRead, fpUserWrite})

      let r = writeAtomic(path, "after")
      check r.isOk
      check readFile(path) == "after"
      check getFilePermissions(path) == {fpUserRead, fpUserWrite}
    else:
      skip()

suite "atomic_write - error paths":
  test "returns err when parent directory does not exist":
    let dir = mkTmpDir("noparent")
    defer:
      rmTree(dir)
    let path = dir / "missing_subdir" / "a.txt"

    let r = writeAtomic(path, "x")
    check r.isErr

  test "existing file is not truncated when write fails":
    # Point at a path whose parent is a regular file — opening `a.txt/foo`
    # for write must fail without touching anything.
    let dir = mkTmpDir("blocked")
    defer:
      rmTree(dir)
    let blocker = dir / "not_a_dir"
    writeFile(blocker, "content")
    let bogus = blocker / "child.txt"

    let r = writeAtomic(bogus, "x")
    check r.isErr
    # The blocker file must be untouched.
    check readFile(blocker) == "content"

suite "atomic_write - createExclusively":
  test "refuses a path that is already there without touching it":
    # Pins createExclusively; `writeAtomic` hits the gate check first.
    let dir = mkTmpDir("excl")
    defer:
      rmTree(dir)
    let path = dir / "taken.txt"
    writeFile(path, "before")

    let r = createExclusively(path, "after")
    check r.isErr
    check r.error == FileAppearedErrorMsg
    check readFile(path) == "before"

  test "creates a fresh path":
    let dir = mkTmpDir("exclfresh")
    defer:
      rmTree(dir)
    let path = dir / "fresh.txt"

    let r = createExclusively(path, "hello")
    check r.isOk
    check readFile(path) == "hello"
