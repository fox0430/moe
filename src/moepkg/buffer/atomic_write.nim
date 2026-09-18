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
##   - New file → exclusive create + fsync + fsync(dir).
##   - Symlink or hardlinked target → in-place with `<path>~` backup so the
##     link relationship (target of the symlink, or the shared inode of a
##     hardlink group) is preserved.
##   - Otherwise → same-dir temp file + chmod/chown to match + rename over.
##
## Rename is atomic on POSIX when source and destination are on the same
## filesystem, which is why the temp is always created in the target's
## own directory.

import std/[options, os, times]

import pkg/results

import ../logger

when defined(posix):
  import std/posix

const
  TmpPrefix = ".moe.tmp."
  BackupSuffix = "~"

const FileAppearedErrorMsg* =
  "A file appeared at this path while saving. Use :w! to overwrite it."

const TargetChangedErrorMsg* =
  "File changed during save; please retry (use :w! to force save, or :e! to reload)."

type WritePremise* = enum
  ## What the gate approved, carried to the writer. No default fail-open.
  wpOverwrite ## Existing file. A disappearance still exclusive-creates.
  wpCreateExclusive ## Nothing was there; refuse if something is there now.
  wpForce ## `:w!` — write even if a file appeared.

proc writePremise*(expectAbsent: bool, force: bool): WritePremise =
  ## Gate flags → the premise `writeAtomic` requires.
  if force:
    wpForce
  elif expectAbsent:
    wpCreateExclusive
  else:
    wpOverwrite

when not defined(posix):
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

type TargetSnapshot* = tuple[modTime: times.Time, size: int64, dev: uint64, ino: uint64]
  ## Follow-stat identity of the write target. Re-checked with `classifyTarget`
  ## just before the write so a moved target does not get a stale strategy.

proc snapshotTarget*(path: string): Option[TargetSnapshot] =
  ## Follow-stat snapshot of `path`, or none when it cannot be resolved.
  try:
    let info = getFileInfo(path, followSymlink = true)
    if info.kind notin {pcFile, pcLinkToFile}:
      return none(TargetSnapshot)
    some(
      (
        modTime: info.lastWriteTime,
        size: info.size.int64,
        dev: info.id.device.uint64,
        ino: info.id.file.uint64,
      )
    )
  except CatchableError:
    none(TargetSnapshot)

proc writeTargetMoved*(
    expected: Option[TargetSnapshot], expectedCls: TargetClass, path: string
): bool =
  ## True when `path` is no longer the file the write strategy was chosen for.
  ## Fail closed if the initial snapshot could not be taken: proceeding would
  ## apply a stale decision to whatever is there now.
  expected.isNone or snapshotTarget(path) != expected or
    classifyTarget(path) != expectedCls

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

when defined(posix):
  proc writeFdAndFsync(fd: cint, content: string): Result[(), string] =
    ## Write `content` to `fd` and fsync. Leaves `fd` open.
    var written = 0
    while written < content.len:
      let n = posix.write(
        fd, cast[pointer](unsafeAddr content[written]), content.len - written
      )
      if n < 0:
        let e = errno
        if e == EINTR:
          continue
        return Result[(), string].err("cannot write: " & $posix.strerror(e))
      if n == 0:
        return Result[(), string].err("cannot write: no progress")
      written += n

    var rc = posix.fsync(fd)
    while rc != 0 and errno == EINTR:
      rc = posix.fsync(fd)
    if rc != 0:
      return Result[(), string].err("fsync failed: " & $posix.strerror(errno))

    Result[(), string].ok ()

  proc writeTempExclusive(
      dir: string, base: string, content: string, tmpPath: var string
  ): Result[(), string] =
    ## Same-dir temp via mkstemp (kernel-random, O_EXCL). A planted symlink
    ## cannot redirect the write. On error no temp file remains.
    var tmpl = dir / (TmpPrefix & base & ".XXXXXX")
    let fd = posix.mkstemp(tmpl.cstring)
    if fd < 0:
      let e = errno
      return
        Result[(), string].err("cannot create temporary file: " & $posix.strerror(e))
    tmpPath = tmpl

    let wr = writeFdAndFsync(fd, content)
    discard posix.close(fd)
    if wr.isErr:
      try:
        removeFile(tmpPath)
      except CatchableError:
        discard
      return Result[(), string].err(wr.error & ": " & tmpPath)

    Result[(), string].ok ()

else:
  proc writeTempExclusive(
      dir: string, base: string, content: string, tmpPath: var string
  ): Result[(), string] =
    ## Non-POSIX fallback: predictable name without O_EXCL, so a planted
    ## symlink could redirect the write in shared directories. moe targets
    ## POSIX and this mirrors the killProcessGroup stance: documented
    ## limitation on other platforms.
    inc tmpCounter
    tmpPath = dir / (TmpPrefix & base & "." & $tmpCounter)
    let wr = writeAndFsync(tmpPath, content)
    if wr.isErr:
      try:
        removeFile(tmpPath)
      except CatchableError:
        discard
      return wr
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

proc createExclusively*(path: string, content: string): Result[(), string] =
  ## Create `path` with `content`; fail if it already exists (O_EXCL).
  when defined(posix):
    let fd = posix.open(path.cstring, O_WRONLY or O_CREAT or O_EXCL, 0o666.Mode)
    if fd < 0:
      let e = errno
      if e == EEXIST:
        return Result[(), string].err(FileAppearedErrorMsg)
      return Result[(), string].err("cannot create " & path & ": " & $strerror(e))
    let wr = writeFdAndFsync(fd, content)
    discard posix.close(fd)
    if wr.isErr:
      try:
        removeFile(path)
      except CatchableError:
        discard
      return Result[(), string].err(wr.error & ": " & path)
    Result[(), string].ok ()
  else:
    # No O_EXCL outside POSIX; check-then-create only.
    if fileExists(path) or symlinkExists(path):
      return Result[(), string].err(FileAppearedErrorMsg)
    writeAndFsync(path, content)

proc writeNewFile(
    path: string, content: string, refuseIfAppeared: bool
): Result[(), string] =
  ## Create-a-new-file path. No rename gain (nothing to swap), but still
  ## fsync file + parent dir so the new inode is durable.
  let wr =
    if refuseIfAppeared:
      createExclusively(path, content)
    else:
      # Forced overwrite; existing file may go.
      writeAndFsync(path, content)
  if wr.isErr:
    return wr
  if not fsyncDir(path.parentDir):
    logWarn("buffer", "atomic write: fsync(dir) failed for " & path)

  Result[(), string].ok ()

proc writeInPlace(path: string, content: string, cls: TargetClass): Result[(), string] =
  ## Vim `bkc=yes` + `writebackup`: copy current content to `<path>~`, write
  ## in place, fsync, drop backup on success. Preserves hardlinks and the
  ## symlink target since neither the inode nor the link itself is replaced.
  let expected = snapshotTarget(path)
  let expectedCls = classifyTarget(path)
  if expected.isNone:
    return Result[(), string].err(TargetChangedErrorMsg)
  let backup = path & BackupSuffix
  try:
    # copy — not rename — so hardlinks stay linked and symlinks stay
    # pointing at the same target.
    copyFileWithPermissions(path, backup)
  except OSError as e:
    return Result[(), string].err("cannot create backup " & backup & ": " & e.msg)
  except CatchableError as e:
    return Result[(), string].err("cannot create backup " & backup & ": " & e.msg)

  if writeTargetMoved(expected, expectedCls, path):
    # Target changed after the strategy was chosen; drop the backup of the new content.
    try:
      removeFile(backup)
    except CatchableError:
      discard
    return Result[(), string].err(TargetChangedErrorMsg)

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
  let expected = snapshotTarget(path)
  let expectedCls = classifyTarget(path)
  if expected.isNone:
    return Result[(), string].err(TargetChangedErrorMsg)
  let dir = if path.parentDir.len == 0: "." else: path.parentDir
  let base = path.extractFilename
  var tmp: string
  let wr = writeTempExclusive(dir, base, content, tmp)
  if wr.isErr:
    return wr

  try:
    setFilePermissions(tmp, cls.permissions)
  except CatchableError as e:
    logWarn("buffer", "atomic write: chmod failed on tmp " & tmp & ": " & e.msg)
  restoreOwner(tmp, cls)

  if writeTargetMoved(expected, expectedCls, path):
    # Target changed after the strategy was chosen. classifyTarget also catches
    # chmod/chown/hardlink, which the byte snapshot cannot.
    try:
      removeFile(tmp)
    except CatchableError:
      discard
    return Result[(), string].err(TargetChangedErrorMsg)

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

proc writeAtomic*(
    path: string, content: string, premise = wpOverwrite
): Result[(), string] =
  ## Save `content` to `path` with crash/power-loss resistance. Picks the
  ## write strategy per Vim `bkc=auto`:
  ##   - No existing file → exclusive create + fsync + fsync(dir).
  ##   - Symlink or hardlinked → in-place with `<path>~` backup.
  ##   - Otherwise → same-dir temp + rename with permissions/owner restore.
  ##
  ## `premise` is what the gate approved and must be passed explicitly;
  ## omitting it is overwrite of an existing file, not "nothing was there".
  let cls = classifyTarget(path)
  case premise
  of wpForce:
    if not cls.exists:
      return writeNewFile(path, content, refuseIfAppeared = false)
  of wpCreateExclusive:
    if cls.exists:
      return Result[(), string].err(FileAppearedErrorMsg)
    return writeNewFile(path, content, refuseIfAppeared = true)
  of wpOverwrite:
    if not cls.exists:
      return writeNewFile(path, content, refuseIfAppeared = true)
  if cls.isSymlink or cls.linkCount > 1:
    return writeInPlace(path, content, cls)
  writeTempRename(path, content, cls)
