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

## Two identities for a path, used in different questions:
##
##   - Spelling (`pathKey` / `samePath`): how it was typed, the LSP URI, a
##     recovery manifest. Display and the wire.
##   - Entity (`fileEntityId` / `sameFileEntity`): the file a path resolves to
##     (device + inode, following symlinks). Overwrite, holder lookup, "already
##     open?".
##
## "Is this the same file?" is always the entity. Do not mix in spelling.

import std/[options, os]

type FileEntityId* = tuple[dev: uint64, ino: uint64]
  ## Device + inode the path resolves to. Same entity = one file.

proc pathKey*(path: string): string {.raises: [].} =
  ## Tilde-expanded, absolute, normalized form of `path`. Never raises.
  if path.len == 0:
    return ""
  try:
    normalizedPath(absolutePath(expandTilde(path)))
  except ValueError, OSError:
    # Fall back to the raw spelling when there is nothing to resolve against.
    normalizedPath(path)

proc samePath*(a, b: string): bool {.raises: [].} =
  ## Canonicalized spelling equality. Empty paths match nothing.
  if a.len == 0 or b.len == 0:
    return false
  pathKey(a) == pathKey(b)

proc fileEntityId*(path: string): Option[FileEntityId] {.raises: [].} =
  ## File identity `path` resolves to, or none. Follows symlinks.
  if path.len == 0:
    return none(FileEntityId)
  try:
    let info = getFileInfo(path, followSymlink = true)
    if info.kind notin {pcFile, pcLinkToFile}:
      return none(FileEntityId)
    some((dev: info.id.device.uint64, ino: info.id.file.uint64))
  except CatchableError:
    none(FileEntityId)

proc sameFileEntity*(a, b: string): bool {.raises: [].} =
  ## True only when both paths resolve to the same entity. Failures never match.
  if a.len == 0 or b.len == 0:
    return false
  let ida = fileEntityId(a)
  let idb = fileEntityId(b)
  ida.isSome and idb.isSome and ida.get == idb.get
