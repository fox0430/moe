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

## Read side of the crash recovery store.
##
## The listing decides what exists; a missing, damaged or newer manifest only
## costs origins. Sessions and copies can disappear between reads.

import std/[algorithm, json, options, os, sets, tables, times]

import buffer/[core, file_io], path_key, recovery_format, unicode_utils
import types/recovery_index_types

export recovery_index_types

proc newRecoveryStore*(baseDir: string = getCrashRecoveryBaseDir()): RecoveryStore =
  RecoveryStore(baseDir: baseDir)

proc sessionDirs(baseDir: string): tuple[dirs: seq[string], listed: bool] =
  ## Session directories, sorted by name. Names carry no time order.
  ## A missing base directory is an empty listing; one that is there but could
  ## not be read leaves `listed` false.
  try:
    for kind, path in walkDir(baseDir, checkDir = true):
      if kind in {pcDir, pcLinkToDir}:
        result.dirs.add(path)
  except CatchableError:
    return (dirs: @[], listed: not dirExists(baseDir))
  result.dirs.sort()
  result.listed = true

proc payloadDir(sessionDir: string): string =
  sessionDir / PayloadDirName

proc reviewedMark(sessionDir, copyPath: string): string =
  sessionDir / ReviewedDirName / copyPath.lastPathPart

proc reviewedDirLinked(sessionDir: string): bool =
  ## Whether the marks would be reached through a link: then they are not the
  ## store's, so none is read, written or removed.
  symlinkExists(sessionDir / ReviewedDirName)

proc payloadFiles(sessionDir: string): tuple[files: seq[string], listed: bool] =
  ## Sorted payload copies. Scratch names and links are ignored.
  ## Unreadable: `listed` is false and `files` is empty.
  try:
    for kind, path in walkDir(payloadDir(sessionDir), checkDir = true):
      if kind != pcFile or not isPayloadFileName(path.lastPathPart):
        continue
      result.files.add(path)
  except CatchableError:
    return (files: @[], listed: false)
  result.files.sort()
  result.listed = true

proc legacyFiles(sessionDir: string): tuple[files: seq[string], listed: bool] =
  ## Sorted copies at the session root. Metadata names are not copies.
  ## Unreadable: `listed` is false and `files` is empty.
  try:
    for kind, path in walkDir(sessionDir, checkDir = true):
      if kind notin {pcFile, pcLinkToFile}:
        continue
      let name = path.lastPathPart
      if name == MetadataName or name == MetadataTempName:
        continue
      result.files.add(path)
  except CatchableError:
    return (files: @[], listed: false)
  result.files.sort()
  result.listed = true

proc isLegacyPayloadName(name: string): bool =
  ## A name an older manifest may claim. Metadata names are excluded: the old
  ## writer overwrote a same-named copy with the manifest.
  name.len > 0 and name != "." and name != ".." and name == name.lastPathPart and
    name != MetadataName and name != MetadataTempName

proc readOriginEntry(file: var RecoveredFile, entry: JsonNode, originKey: string) =
  ## Fill origin fields. `originKey` is how that shape spelled the path.
  if entry.kind != JObject:
    return
  if entry.hasKey(originKey) and entry[originKey].kind == JString:
    let origin = entry[originKey].getStr
    if origin.len > 0:
      file.origin = some(origin)
  if entry.hasKey(ManifestOriginMtimeNsKey) and
      entry[ManifestOriginMtimeNsKey].kind == JInt:
    file.originStamp.mtime =
      some(fromUnixNano(entry[ManifestOriginMtimeNsKey].getBiggestInt))
  if entry.hasKey(ManifestOriginSizeKey) and entry[ManifestOriginSizeKey].kind == JInt:
    file.originStamp.size = some(entry[ManifestOriginSizeKey].getBiggestInt.int64)

proc toSavedAt(node: JsonNode): Option[Time] =
  if node.kind == JInt:
    return some(fromUnix(node.getBiggestInt))
  none(Time)

proc readNamedEntries(
    sessionDir: string, session: var RecoverySession
): Table[string, JsonNode] =
  ## Named copies from this format's manifest. Empty if missing, foreign, or newer.
  result = initTable[string, JsonNode]()
  if not fileExists(sessionDir / MetadataName):
    return
  session.complete = true

  var meta: JsonNode
  try:
    meta = parseFile(sessionDir / MetadataName)
  except CatchableError:
    return
  if meta.kind != JObject:
    return
  if not (
    meta.hasKey(ManifestFormatKey) and meta[ManifestFormatKey].kind == JString and
    meta[ManifestFormatKey].getStr == FormatName
  ):
    return
  if not (
    meta.hasKey(ManifestVersionKey) and meta[ManifestVersionKey].kind == JInt and
    meta[ManifestVersionKey].getBiggestInt <= FormatVersion
  ):
    return

  if meta.hasKey(ManifestSavedAtKey):
    session.savedAt = toSavedAt(meta[ManifestSavedAtKey])
  if meta.hasKey(ManifestContinuityKey) and meta[ManifestContinuityKey].kind == JString:
    session.continuity = toContinuityKind(meta[ManifestContinuityKey].getStr)
  if meta.hasKey(ManifestDetailKey) and meta[ManifestDetailKey].kind == JString:
    session.detail = meta[ManifestDetailKey].getStr
  if not (meta.hasKey(ManifestFilesKey) and meta[ManifestFilesKey].kind == JArray):
    return
  for entry in meta[ManifestFilesKey]:
    if entry.kind != JObject:
      continue
    if not (entry.hasKey(ManifestNameKey) and entry[ManifestNameKey].kind == JString):
      continue
    let name = entry[ManifestNameKey].getStr
    if not isPayloadFileName(name):
      continue
    result[name] = entry

proc readLegacyEntries(
    sessionDir: string, session: var RecoverySession, claimed: var HashSet[string]
): seq[RecoveredFile] =
  ## Older flat map of copy name to `{originalPath}`. Names are checked against
  ## the directory.
  if not fileExists(sessionDir / MetadataName):
    return @[]
  session.complete = true

  var meta: JsonNode
  try:
    meta = parseFile(sessionDir / MetadataName)
  except CatchableError:
    return @[]
  if meta.kind != JObject:
    return @[]

  for name, entry in meta:
    if not isLegacyPayloadName(name):
      continue
    let path = sessionDir / name
    if not fileExists(path):
      continue
    var file = RecoveredFile(path: path, described: true)
    file.readOriginEntry(entry, LegacyOriginPathKey)
    claimed.incl name
    result.add(file)

proc readSession(dir: string): RecoverySession =
  ## Manifest first, then the copies it did not name.
  result = RecoverySession(dir: dir, continuity: ckUnknown)

  if dirExists(payloadDir(dir)):
    let (copies, listed) = payloadFiles(dir)
    result.listed = listed
    let named = readNamedEntries(dir, result)
    for path in copies:
      var file = RecoveredFile(path: path)
      let name = path.lastPathPart
      if named.hasKey(name):
        file.described = true
        file.readOriginEntry(named[name], ManifestOriginKey)
      result.files.add(file)
  else:
    let (copies, listed) = legacyFiles(dir)
    result.listed = listed
    var claimed = initHashSet[string]()
    result.files = readLegacyEntries(dir, result, claimed)
    for path in copies:
      if path.lastPathPart notin claimed:
        result.files.add(RecoveredFile(path: path))

  result.files.sort(
    proc(a, b: RecoveredFile): int =
      cmp(a.path, b.path)
  )
  let linked = reviewedDirLinked(dir)
  for file in result.files.mitems:
    file.reviewed = not linked and fileExists(reviewedMark(dir, file.path))

proc sessionAge(s: RecoverySession): int64 =
  ## `savedAt`, or else when the newest copy was written, which nothing
  ## changes afterwards. The directory's own mtime moves whenever a mark or a
  ## discard touches it, so it is only the last resort.
  if s.savedAt.isSome:
    return s.savedAt.get.toUnix
  result = low(int64)
  for f in s.files:
    try:
      result = max(result, getLastModificationTime(f.path).toUnix)
    except CatchableError:
      discard
  if result == low(int64):
    try:
      result = getLastModificationTime(s.dir).toUnix
    except CatchableError:
      discard

proc listSessions*(
    store: RecoveryStore
): tuple[sessions: seq[RecoverySession], listed: bool] =
  ## Newest first. Empty sessions are omitted unless their listing failed.
  ## `listed` is false when the store itself could not be read.
  if store.baseDir.len == 0:
    return (sessions: @[], listed: true)
  let found = sessionDirs(store.baseDir)
  result.listed = found.listed
  var aged: seq[(int64, RecoverySession)]
  for dir in found.dirs:
    let session = readSession(dir)
    if session.files.len > 0 or not session.listed:
      aged.add (session.sessionAge, session)
  aged.sort(
    proc(a, b: (int64, RecoverySession)): int =
      result = cmp(b[0], a[0])
      if result == 0:
        result = cmp(b[1].dir, a[1].dir)
  )
  for (_, session) in aged:
    result.sessions.add session

proc sessions*(store: RecoveryStore): seq[RecoverySession] =
  ## Newest first. Empty sessions are omitted unless their listing failed.
  store.listSessions().sessions

proc stampHeld(stamp: OriginStamp, origin: string): bool =
  if stamp.mtime.isNone and stamp.size.isNone:
    return false
  let current = captureFileStamp(origin)
  if current.observed != fileObservedPresent:
    return false
  if stamp.mtime.isSome and current.modTime != stamp.mtime.get:
    return false
  if stamp.size.isSome and current.size != stamp.size.get:
    return false
  return true

proc originalChangedSince*(c: PreservedCopy): bool =
  ## Whether the original moved on disk after the copy was preserved, so a
  ## row can say the copy is not simply the newer of the two. True when there
  ## is no stamp to compare against: unknown is not the same as unchanged.
  if c.file.origin.isNone or c.file.origin.get.len == 0:
    return false
  not stampHeld(c.file.originStamp, c.file.origin.get)

proc originHolds*(file: RecoveredFile): bool =
  ## Whether the origin holds exactly the copy's bytes. The bytes decide: an
  ## unchanged stamp does not rule a match out, since the buffer may have been
  ## out of step with its file when it was preserved. Sizes go first, so most
  ## answers read neither file. Anything unreadable holds nothing.
  if file.origin.isNone or file.origin.get.len == 0:
    return false
  filesHoldSame(file.origin.get, file.path)

proc isDirectChild(path, dir: string): bool =
  ## Direct child of `dir` after normalizing `..` and relative paths.
  path.len > 0 and dir.len > 0 and samePath(parentDir(path), dir)

proc discardSession*(store: RecoveryStore, dir: string, reason: var string): bool =
  ## Remove one session directory; it must sit directly inside the store.
  ## On failure, set `reason` and return false.
  if not isDirectChild(dir, store.baseDir):
    reason = "it is outside the recovery directory"
    return false
  try:
    if symlinkExists(dir):
      # removeDir follows the link and empties the target. Unlink only.
      removeFile(dir)
    else:
      removeDir(dir)
    return true
  except CatchableError as e:
    reason = sanitizeForDisplay(e.msg)
    return false

proc discardSession*(store: RecoveryStore, dir: string): bool {.discardable.} =
  var reason: string
  discardSession(store, dir, reason)

proc dropManifestEntry(sessionDir, name: string) =
  ## Drop `name` from this format's manifest. Other shapes are left alone.
  var meta: JsonNode
  try:
    meta = parseFile(sessionDir / MetadataName)
  except CatchableError:
    return
  if meta.kind != JObject or not meta.hasKey(ManifestFormatKey) or
      meta[ManifestFormatKey].kind != JString:
    return
  if not (
    meta.hasKey(ManifestVersionKey) and meta[ManifestVersionKey].kind == JInt and
    meta[ManifestVersionKey].getBiggestInt <= FormatVersion
  ):
    return
  if not (meta.hasKey(ManifestFilesKey) and meta[ManifestFilesKey].kind == JArray):
    return
  var kept = newJArray()
  for entry in meta[ManifestFilesKey]:
    if entry.kind == JObject and entry.hasKey(ManifestNameKey) and
        entry[ManifestNameKey].kind == JString and entry[ManifestNameKey].getStr == name:
      continue
    kept.add entry
  meta[ManifestFilesKey] = kept
  discard writeManifest(sessionDir, meta)

proc insideStore(
    store: RecoveryStore, copyPath, sessionDir: string, reason: var string
): bool =
  ## Whether `copyPath` is a copy this store may change, reached without a link.
  if not isDirectChild(sessionDir, store.baseDir):
    reason = "it is outside the recovery directory"
    return false
  if symlinkExists(sessionDir):
    # copyPath would be outside the cache; changing it would touch the real file.
    reason = "it is reached through a linked session directory"
    return false
  if symlinkExists(payloadDir(sessionDir)):
    reason = "it is reached through a linked payload directory"
    return false
  if not (
    isDirectChild(copyPath, sessionDir) or
    isDirectChild(copyPath, payloadDir(sessionDir))
  ):
    reason = "it is outside the session directory"
    return false
  true

proc discardCopy*(
    store: RecoveryStore, copyPath, sessionDir: string, reason: var string
): bool =
  ## Remove one copy and drop it from the manifest. The session directory
  ## goes too once nothing is left in it; both must sit inside the store.
  if not store.insideStore(copyPath, sessionDir, reason):
    return false
  try:
    removeFile(copyPath)
  except CatchableError as e:
    reason = sanitizeForDisplay(e.msg)
    return false
  dropManifestEntry(sessionDir, copyPath.lastPathPart)
  if not reviewedDirLinked(sessionDir):
    # Through a link the mark would be a file outside the store.
    discard tryRemoveFile(reviewedMark(sessionDir, copyPath))
  let session = readSession(sessionDir)
  if session.listed and session.files.len == 0:
    return discardSession(store, sessionDir, reason)
  true

proc discardCopy*(
    store: RecoveryStore, copyPath, sessionDir: string
): bool {.discardable.} =
  var reason: string
  discardCopy(store, copyPath, sessionDir, reason)

proc setReviewed*(
    store: RecoveryStore,
    copyPath, sessionDir: string,
    reviewed: bool,
    reason: var string,
): bool =
  ## Record whether the user has dealt with this copy. Any session can carry
  ## the mark: it is a file of its own, not a manifest entry.
  if not store.insideStore(copyPath, sessionDir, reason):
    return false
  if not fileExists(copyPath):
    reason = "the copy is gone"
    return false
  let dir = sessionDir / ReviewedDirName
  if reviewedDirLinked(sessionDir):
    reason = "it is reached through a linked reviewed directory"
    return false
  let mark = reviewedMark(sessionDir, copyPath)
  try:
    if reviewed:
      if symlinkExists(mark):
        # Writing through it would truncate whatever it points at.
        reason = "its mark is a link"
        return false
      if not fileExists(mark):
        # Never the session itself: a discard racing this one may have taken
        # it, and bringing it back would leave a directory nothing lists.
        discard existsOrCreateDir(dir)
        writeFile(mark, "")
    else:
      removeFile(mark)
  except CatchableError as e:
    reason = sanitizeForDisplay(e.msg)
    return false
  true
