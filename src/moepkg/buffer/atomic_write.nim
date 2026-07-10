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

## Atomic-ish file save: temp+rename with hardlink/symlink fallback to
## in-place-with-backup. fsyncs the file and (POSIX) the parent directory
## for durability across power loss.
##
## Strategy follows Vim's `bkc=auto` + `writebackup` semantics:
##   - New file → plain write + fsync + fsync(dir).
##   - Symlink or hardlinked target → in-place with `<path>~` backup so the
##     link relationship (target of the symlink, or the shared inode of a
##     hardlink group) is preserved.
##   - Otherwise → same-dir temp file + chmod/chown to match + rename over.
##
## Rename is atomic on POSIX when source and destination are on the same
## filesystem, which is why the temp is always created in the target's
## own directory.

import std/os

import pkg/results

import ../logger

when defined(posix):
  import std/posix

const
  TmpPrefix = ".moe.tmp."
  BackupSuffix = "~"

var tmpCounter {.threadvar.}: uint64

type TargetClass* = object
  ## Snapshot of the target's on-disk attributes used to decide the write
  ## strategy and to restore permissions/owner after a temp+rename.
  exists*: bool
  isSymlink*: bool
  linkCount*: int
  permissions*: set[FilePermission]
  when defined(posix):
    uid*: Uid
    gid*: Gid

proc classifyTarget*(path: string): TargetClass =
  ## Probe target metadata without following symlinks. Missing files return
  ## `exists: false` so callers pick the new-file path.
  when defined(posix):
    var st: Stat
    if lstat(path.cstring, st) != 0:
      return TargetClass(exists: false)
    result.exists = true
    result.isSymlink = S_ISLNK(st.st_mode)
    result.linkCount = int(st.st_nlink)
    result.uid = st.st_uid
    result.gid = st.st_gid

    try:
      # follow symlinks so we capture the permissions of the actual file we
      # will be overwriting in-place, not the symlink's own bits.
      let info = getFileInfo(path, followSymlink = true)
      result.permissions = info.permissions
    except OSError:
      result.permissions = {}
  else:
    if not (fileExists(path) or symlinkExists(path)):
      return TargetClass(exists: false)
    result.exists = true
    result.isSymlink = symlinkExists(path)
    try:
      let info = getFileInfo(path)
      result.permissions = info.permissions
      result.linkCount = int(info.linkCount)
    except OSError:
      discard

proc nextTmpPath(target: string): string =
  ## Same-directory temp path unique per process. Same-directory is required
  ## for rename() to be atomic on POSIX (rename across filesystems fails
  ## with EXDEV).
  inc tmpCounter
  let dir = if target.parentDir.len == 0: "." else: target.parentDir
  let base = target.extractFilename
  let pid =
    when defined(posix):
      $getpid()
    else:
      "0"
  dir / (TmpPrefix & base & "." & pid & "." & $tmpCounter)

proc writeAndFsync(path: string, content: string): Result[(), string] =
  ## Write `content` to `path` (truncating), flush userspace buffers, and
  ## fsync the descriptor before close. `path` must not exist as a directory.
  var f: File
  if not open(f, path, fmWrite):
    return Result[(), string].err("cannot open for writing: " & path)

  var msg = ""
  try:
    f.write(content)
    f.flushFile()
    when defined(posix):
      if fsync(f.getFileHandle) != 0:
        msg = "fsync failed: " & path
  except IOError as e:
    msg = e.msg
  except CatchableError as e:
    msg = e.msg
  close(f)

  if msg.len > 0:
    return Result[(), string].err(msg)

  Result[(), string].ok ()

proc fsyncDir(dir: string): bool =
  ## fsync a directory so a preceding rename is durable across power loss.
  ## No-op on non-POSIX platforms.
  when defined(posix):
    let d = if dir.len == 0: "." else: dir
    let fd = posix.open(d.cstring, O_RDONLY)
    if fd < 0:
      return false
    let rc = fsync(fd)
    discard posix.close(fd)
    rc == 0
  else:
    true

proc restoreOwner(path: string, cls: TargetClass) =
  ## Best-effort chown to the original uid/gid. Non-root usually cannot chown
  ## and that is not an error condition — permission failures are silent.
  when defined(posix):
    if chown(path.cstring, cls.uid, cls.gid) != 0:
      let e = errno
      if e != EPERM and e != EACCES:
        logWarn("buffer", "atomic write: chown failed on " & path)

proc writeNewFile(path: string, content: string): Result[(), string] =
  ## Create-a-new-file path. No rename gain (nothing to swap), but still
  ## fsync file + parent dir so the new inode is durable.
  let wr = writeAndFsync(path, content)
  if wr.isErr:
    return wr
  if not fsyncDir(path.parentDir):
    logWarn("buffer", "atomic write: fsync(dir) failed for " & path)

  Result[(), string].ok ()

proc writeInPlace(path: string, content: string, cls: TargetClass): Result[(), string] =
  ## Vim `bkc=yes` + `writebackup`: copy current content to `<path>~`, write
  ## in place, fsync, drop backup on success. Preserves hardlinks and the
  ## symlink target since neither the inode nor the link itself is replaced.
  let backup = path & BackupSuffix
  try:
    # copy — not rename — so hardlinks stay linked and symlinks stay
    # pointing at the same target.
    copyFileWithPermissions(path, backup)
  except OSError as e:
    return Result[(), string].err("cannot create backup " & backup & ": " & e.msg)
  except CatchableError as e:
    return Result[(), string].err("cannot create backup " & backup & ": " & e.msg)

  let wr = writeAndFsync(path, content)
  if wr.isErr:
    # Try to put the pre-save content back so we do not leave a truncated
    # file. If that also fails, the `~` file remains for manual recovery.
    try:
      copyFileWithPermissions(backup, path)
    except CatchableError:
      logError("buffer", "atomic write: recovery from backup failed for " & path)
    return wr

  if not fsyncDir(path.parentDir):
    logWarn("buffer", "atomic write: fsync(dir) failed for " & path)

  try:
    removeFile(backup)
  except CatchableError:
    logWarn("buffer", "atomic write: could not remove backup " & backup)

  Result[(), string].ok ()

proc writeTempRename(
    path: string, content: string, cls: TargetClass
): Result[(), string] =
  ## Vim `bkc=no`: write same-dir temp with restored mode/owner, then rename
  ## over the target. Rename is atomic on POSIX within a filesystem.
  let tmp = nextTmpPath(path)

  let wr = writeAndFsync(tmp, content)
  if wr.isErr:
    try:
      removeFile(tmp)
    except CatchableError:
      discard
    return wr

  try:
    setFilePermissions(tmp, cls.permissions)
  except CatchableError as e:
    logWarn("buffer", "atomic write: chmod failed on tmp " & tmp & ": " & e.msg)
  restoreOwner(tmp, cls)

  try:
    moveFile(tmp, path)
  except OSError as e:
    try:
      removeFile(tmp)
    except CatchableError:
      discard
    return Result[(), string].err("rename failed: " & e.msg)
  except CatchableError as e:
    try:
      removeFile(tmp)
    except CatchableError:
      discard
    return Result[(), string].err("rename failed: " & e.msg)

  if not fsyncDir(path.parentDir):
    logWarn("buffer", "atomic write: fsync(dir) failed for " & path)

  Result[(), string].ok ()

proc writeAtomic*(path: string, content: string): Result[(), string] =
  ## Save `content` to `path` with crash/power-loss resistance. Picks the
  ## write strategy per Vim `bkc=auto`:
  ##   - No existing file → plain write + fsync + fsync(dir).
  ##   - Symlink or hardlinked → in-place with `<path>~` backup.
  ##   - Otherwise → same-dir temp + rename with permissions/owner restore.
  let cls = classifyTarget(path)
  if not cls.exists:
    return writeNewFile(path, content)
  if cls.isSymlink or cls.linkCount > 1:
    return writeInPlace(path, content, cls)
  writeTempRename(path, content, cls)
