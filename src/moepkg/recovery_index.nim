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

## What the running editor knows about preserved copies.
##
## A snapshot: read from the store at startup and after each change this
## editor makes to it, never per load or per frame. Which copies exist and
## which file each came from is settled in `refresh`; afterwards only the
## buffers are asked. A copy another process preserves or discards shows up at
## the next refresh.
##
## A copy is owed until the user deals with it for good: sets it aside, or
## saves the buffer it was restored into while the restore is still in it. In
## between, the restored text lives only in that buffer, so the copy is held
## back only while the restore is applied there, and is owed again if it dies.
## Each copy is dealt with on its own: restoring one says nothing about work
## only another holds. A copy its file is seen to hold, when the file is read
## or written, is marked dealt with then: what happens to the file afterwards
## is the user's doing, not the crash's.

import std/[options, sets, tables]

import buffer/[core, file_io], path_key, recovery_store

export recovery_store

proc refresh*(index: RecoveryIndex) =
  ## Re-read the store. Reads no copy. A base directory that cannot be read
  ## leaves the last listing in place: that work is still preserved.
  let listing = index.store.listSessions()
  index.listed = listing.listed
  if not listing.listed:
    return
  index.sessions = listing.sessions
  index.originKeys.clear()
  for session in index.sessions:
    for f in session.files:
      index.originKeys[f.path] =
        if f.origin.isSome:
          pathKey(f.origin.get)
        else:
          ""
  index.attributions.clear()
  # A session that could not be listed still has its copies, just unseen.
  var unlisted: HashSet[string]
  for session in index.sessions:
    if not session.listed:
      unlisted.incl session.dir
  var gone: seq[string]
  for copyPath, r in index.restored:
    if copyPath notin index.originKeys and r.sessionDir notin unlisted:
      gone.add copyPath
  for copyPath in gone:
    index.restored.del copyPath
  gone.setLen 0
  for copyPath, p in index.copyPrints:
    # One that could not be read is asked again.
    if copyPath notin index.originKeys or p.size < 0:
      gone.add copyPath
  for copyPath in gone:
    index.copyPrints.del copyPath

proc newRecoveryIndex*(baseDir: string): RecoveryIndex =
  result = RecoveryIndex(store: newRecoveryStore(baseDir))
  result.refresh()

proc copiesFrom(index: RecoveryIndex, path: string): HashSet[string] =
  ## Copies whose origin is the file at `path`: the same spelling, or the same
  ## file now. Both entities are looked at together, so a file gone since one
  ## was read cannot lend its inode to another.
  let key = pathKey(path)
  if key.len == 0 or index.originKeys.len == 0:
    return
  let entity = fileEntityId(path)
  for session in index.sessions:
    for f in session.files:
      let originKey = index.originKeys.getOrDefault(f.path)
      if originKey.len == 0:
        continue
      if originKey == key or (entity.isSome and fileEntityId(f.origin.get) == entity):
        result.incl f.path

proc seenBy(buf: TextBuffer): BufferSeen =
  (path: buf.filePath.get(""), observed: buf.fileBaseline.observed)

proc attribute(index: RecoveryIndex, buf: TextBuffer) =
  ## Work out which copies came from `buf`'s file, unless that is known for
  ## the file it has now.
  let seen = seenBy(buf)
  if buf.id in index.attributions and index.attributions[buf.id].seen == seen:
    return
  index.attributions[buf.id] =
    Attribution(seen: seen, copies: index.copiesFrom(seen.path))

proc cameFrom(index: RecoveryIndex, copyPath: string, buf: TextBuffer): bool =
  index.attribute(buf)
  copyPath in index.attributions[buf.id].copies

proc holderOf*(
    index: RecoveryIndex, file: RecoveredFile, buffers: openArray[TextBuffer]
): Option[TextBuffer] =
  ## The open buffer of the file `file` was preserved from.
  for b in buffers:
    if index.cameFrom(file.path, b):
      return some(b)
  none(TextBuffer)

proc heldBy(index: RecoveryIndex, file: RecoveredFile, holder: TextBuffer): bool =
  ## Whether `holder`'s file, as it last read or wrote it, is the copy's bytes.
  ## Each copy is read at most once, and only when the sizes match. One that
  ## is not a regular file, or cannot be read, matches nothing until the next
  ## refresh.
  let last = holder.lastLoadedContent
  if last.isNone:
    return false
  if file.path notin index.copyPrints:
    index.copyPrints[file.path] = CopyPrint(size: regularFileSize(file.path))
  if index.copyPrints[file.path].size != last.get.size:
    return false
  if index.copyPrints[file.path].print.isNone:
    try:
      index.copyPrints[file.path].print = some(fingerprint(readFile(file.path)))
    except CatchableError:
      index.copyPrints[file.path].size = -1
      return false
  index.copyPrints[file.path].print.get == last.get

proc holds*(
    index: RecoveryIndex, file: RecoveredFile, buffers: openArray[TextBuffer]
): bool =
  ## Whether `file`'s origin already has what was preserved. An open file is
  ## what its buffer last read or wrote; a file nobody has open is what is on
  ## disk, which is read every time.
  let holder = index.holderOf(file, buffers)
  if holder.isNone:
    return file.originHolds()
  index.heldBy(file, holder.get)

proc heldIn(index: RecoveryIndex, copyPath: string, r: Restored, b: TextBuffer): bool =
  ## Whether `b` still holds the restore of `copyPath` for the copy's file:
  ## not undone, not replaced by a reload or a later restore, and the buffer
  ## still of that file. Edits on top keep it; they are the user's.
  if r.settled or r.buffer != b.id or b.historyResets != r.resets:
    return false
  if r.change > 0 and not b.holdsChange(r.change):
    return false
  if b.reloadedSince(r.change):
    return false
  for other, later in index.restored:
    if other != copyPath and later.buffer == b.id and later.change > r.change and
        b.holdsChange(later.change):
      return false
  index.originKeys.getOrDefault(copyPath).len == 0 or index.cameFrom(copyPath, b)

proc restoring*(
    index: RecoveryIndex, copyPath: string, buffers: openArray[TextBuffer]
): bool =
  ## Whether a buffer of the copy's file holds its restored text, not yet
  ## saved. Undoing the restore, restoring another copy over it, reloading,
  ## saving the buffer elsewhere or closing it lets it go again.
  if copyPath notin index.restored:
    return false
  let r = index.restored[copyPath]
  for b in buffers:
    if b.id == r.buffer:
      return index.heldIn(copyPath, r, b)
  false

proc restoring*(
    index: RecoveryIndex, file: RecoveredFile, buffers: openArray[TextBuffer]
): bool =
  index.restoring(file.path, buffers)

proc owed*(
    index: RecoveryIndex, file: RecoveredFile, buffers: openArray[TextBuffer]
): bool =
  ## Whether `file` holds work nobody has dealt with. Reads no file.
  not file.reviewed and not index.restoring(file, buffers)

proc owes*(
    index: RecoveryIndex, buf: TextBuffer, buffers: openArray[TextBuffer]
): bool =
  ## Whether a copy of `buf`'s file is owed. Called per frame.
  if buf.filePath.isNone or index.originKeys.len == 0:
    # Only a file's buffer is attributed; skip the entry for the others.
    return false
  index.attribute(buf)
  if index.attributions[buf.id].copies.len == 0:
    return false
  for session in index.sessions:
    for f in session.files:
      if f.path in index.attributions[buf.id].copies and index.owed(f, buffers):
        return true
  false

proc sameOrigin*(index: RecoveryIndex, a, b: RecoveredFile): bool =
  ## Whether two copies came from one file.
  let key = index.originKeys.getOrDefault(a.path)
  key.len > 0 and index.originKeys.getOrDefault(b.path).len > 0 and (
    key == index.originKeys.getOrDefault(b.path) or
    sameFileEntity(a.origin.get, b.origin.get)
  )

proc copiesOf*(index: RecoveryIndex, path: string): seq[PreservedCopy] =
  ## Copies preserved from the file at `path`, newest session first.
  let copies = index.copiesFrom(path)
  for session in index.sessions:
    for f in session.files:
      if f.path in copies:
        result.add PreservedCopy(file: f, session: session)

proc setReviewed*(
    index: RecoveryIndex,
    copyPath, sessionDir: string,
    reviewed: bool,
    reason: var string,
): bool =
  ## Mark a copy dealt with, or not. The listing keeps its shape.
  if not index.store.setReviewed(copyPath, sessionDir, reviewed, reason):
    return false
  for session in index.sessions.mitems:
    for file in session.files.mitems:
      if file.path == copyPath:
        file.reviewed = reviewed
  true

proc noteRestored*(
    index: RecoveryIndex, copyPath, sessionDir: string, buf: TextBuffer, settled: bool
) =
  ## `buf` now holds the copy's text as the top of its undo history. Any
  ## earlier restore into it is no longer what it holds. `settled`: its file
  ## already has the text and the copy is marked.
  index.restored[copyPath] = Restored(
    buffer: buf.id,
    sessionDir: sessionDir,
    change: buf.currentChangeId,
    resets: buf.historyResets,
    settled: settled,
  )

proc reportUnmarked(index: RecoveryIndex, failed: seq[(string, string)]): seq[string] =
  ## Why each copy in `failed` could not be marked, for those still there.
  if failed.len == 0:
    return
  # Another editor may have discarded the copy first: re-read, so neither the
  # marks nor the report go by a copy that is gone.
  index.refresh()
  for (copyPath, reason) in failed:
    if copyPath in index.originKeys:
      result.add reason

proc noteSaved*(index: RecoveryIndex, buf: TextBuffer): seq[string] =
  ## `buf` was written to its file: the copy whose restore is still in it is
  ## dealt with. One undone, restored over or reloaded away stays owed, and so
  ## does one whose file a save-as left behind. Returns why each copy that
  ## could not be marked, and is still there, was not.
  var settled: seq[(string, string)]
  for copyPath, r in index.restored:
    if index.heldIn(copyPath, r, buf):
      settled.add (copyPath, r.sessionDir)
  var failed: seq[(string, string)]
  for (copyPath, sessionDir) in settled:
    var reason = ""
    if index.setReviewed(copyPath, sessionDir, true, reason):
      index.restored[copyPath].settled = true
    else:
      # Still held, so the next save tries again.
      failed.add (copyPath, reason)
  index.reportUnmarked(failed)

proc noteObserved*(index: RecoveryIndex, buf: TextBuffer): seq[string] =
  ## `buf` just read or wrote its file: every copy of exactly what the file
  ## holds now is dealt with. The fingerprint only picks the candidates; the
  ## mark is for good, so the bytes decide. Returns why each copy that could
  ## not be marked, and is still there, was not.
  if buf.filePath.isNone or index.originKeys.len == 0:
    return
  index.attribute(buf)
  if index.attributions[buf.id].copies.len == 0:
    return
  var failed: seq[(string, string)]
  for session in index.sessions:
    for f in session.files:
      if f.reviewed or f.path notin index.attributions[buf.id].copies or
          not index.heldBy(f, buf) or not filesHoldSame(buf.filePath.get, f.path):
        continue
      var reason = ""
      if not index.setReviewed(f.path, session.dir, true, reason):
        failed.add (f.path, reason)
  index.reportUnmarked(failed)

proc noteObservedOnDisk*(
    index: RecoveryIndex, buffers: openArray[TextBuffer]
): seq[string] =
  ## Mark every copy whose file nobody has open and already holds its bytes.
  ## Reads those files, so it is for startup, not for every frame.
  var failed: seq[(string, string)]
  for session in index.sessions:
    for f in session.files:
      if f.reviewed or index.holderOf(f, buffers).isSome or not f.originHolds():
        continue
      var reason = ""
      if not index.setReviewed(f.path, session.dir, true, reason):
        failed.add (f.path, reason)
  index.reportUnmarked(failed)
