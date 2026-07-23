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

## Shared directory scanning primitive used by both `filer` and `filetree`.
##
## Wraps `walkDir` with the common bits both callers previously duplicated:
## hidden-file filtering, `PathComponent -> FileEntryKind` classification,
## symlink target kind resolution, an executable-permission probe, and the
## "directories first, then alphabetical" sort. Results are returned as
## `seq[FileEntry]` so `filer` can use them directly; `filetree` maps to
## `FileTreeNode`.

import std/[algorithm, os, strutils, times]

import types/filer_types
import logger

proc isHiddenName*(name: string): bool {.inline.} =
  name.len > 0 and name[0] == '.'

proc isDirectoryLike*(kind, targetKind: FileEntryKind): bool {.inline.} =
  kind == fekDirectory or (kind == fekSymlink and targetKind == fekDirectory)

proc classifyPathComponent(pc: PathComponent): tuple[k, target: FileEntryKind] =
  case pc
  of pcDir:
    (fekDirectory, fekDirectory)
  of pcLinkToDir:
    (fekSymlink, fekDirectory)
  of pcLinkToFile:
    (fekSymlink, fekFile)
  of pcFile:
    (fekFile, fekFile)

proc compareEntries*(a, b: FileEntry): int =
  ## Directories (including symlinks-to-dir) first, then alphabetical.
  let aDir = isDirectoryLike(a.kind, a.targetKind)
  let bDir = isDirectoryLike(b.kind, b.targetKind)
  if aDir and not bDir:
    -1
  elif not aDir and bDir:
    1
  else:
    cmpIgnoreCase(a.name, b.name)

proc scanDirectory*(
    path: string,
    showHidden: bool,
    skipOnStatError: bool = false,
    logModule: string = "",
    error: var string,
): seq[FileEntry] =
  ## Read `path` and return filtered, sorted children.
  ##
  ## `skipOnStatError=true` drops entries whose `getFileInfo` call fails
  ## (matches the historical filer behavior). Otherwise the entry is kept
  ## with default size/mtime/exec flag (matches the historical filetree
  ## behavior).
  ##
  ## If `logModule` is non-empty, per-entry and directory-level `OSError`s
  ## are reported via `logger.logWarn`. The directory-level message is also
  ## written to `error`.
  result = @[]
  try:
    for pc, childPath in walkDir(path):
      try:
        let name = extractFilename(childPath)
        let hidden = isHiddenName(name)
        if not showHidden and hidden:
          continue

        let (nodeKind, tgtKind) = classifyPathComponent(pc)
        var size: int64 = 0
        var modified: Time
        var isExec = false
        var statOk = true
        try:
          let info = getFileInfo(childPath, followSymlink = false)
          size = info.size
          modified = info.lastWriteTime
          if nodeKind == fekFile:
            isExec = fpUserExec in info.permissions or fpGroupExec in info.permissions
        except OSError:
          statOk = false

        if not statOk and skipOnStatError:
          continue

        result.add(
          FileEntry(
            name: name,
            kind: nodeKind,
            size: size,
            modified: modified,
            isHidden: hidden,
            isExecutable: isExec,
            targetKind: tgtKind,
          )
        )
      except OSError as e:
        if logModule.len > 0:
          logWarn(logModule, "Cannot access: " & childPath & " (" & e.msg & ")")
  except OSError as e:
    let msg = "Cannot scan directory: " & path & " (" & e.msg & ")"
    if logModule.len > 0:
      logWarn(logModule, msg)
    error = msg

  result.sort(compareEntries)

proc scanDirectory*(
    path: string,
    showHidden: bool,
    skipOnStatError: bool = false,
    logModule: string = "",
): seq[FileEntry] =
  ## Overload for callers that do not need the directory-level error message.
  var err = ""
  scanDirectory(path, showHidden, skipOnStatError, logModule, err)
