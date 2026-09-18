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

type RecoveredFile* = object
  path*: string ## Copy inside the session directory.
  origin*: Option[string] ## None for an unnamed buffer.
  originStamp*: OriginStamp

type RecoverySession* = object
  dir*: string
  complete*: bool ## Manifest landed; without it the preserve died halfway.
  listed*: bool ## False: `files` may be incomplete, including empty.
  continuity*: ContinuityKind
  detail*: string
  savedAt*: Option[Time]
  files*: seq[RecoveredFile]

type PreservedCopy* = object
  file*: RecoveredFile
  session*: RecoverySession

type CopyVerdict* = enum
  cvNoOrigin ## No origin path.
  cvSame ## Original already holds the copy's bytes.
  cvDiffers ## Original exists and holds other bytes.
  cvOriginalGone ## Origin recorded, but no file is there.
  cvUnknown ## Copy or original could not be read.

type RecoveryStore* = object ## Binds listing and discard to one base directory.
  baseDir*: string

proc newRecoveryStore*(baseDir: string = getCrashRecoveryBaseDir()): RecoveryStore =
  RecoveryStore(baseDir: baseDir)

proc sessionDirs(baseDir: string): seq[string] =
  ## Session directories, sorted by name. Names carry no time order.
  try:
    for kind, path in walkDir(baseDir):
      if kind in {pcDir, pcLinkToDir}:
        result.add(path)
  except CatchableError:
    return @[]
  result.sort()

proc payloadDir(sessionDir: string): string =
  sessionDir / PayloadDirName

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
    var file = RecoveredFile(path: path)
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

proc sessionOrder(a, b: RecoverySession): int =
  ## Oldest first. Missing `savedAt` falls back to directory mtime.
  proc key(s: RecoverySession): int64 =
    if s.savedAt.isSome:
      return s.savedAt.get.toUnix
    try:
      return getLastModificationTime(s.dir).toUnix
    except CatchableError:
      return low(int64)

  result = cmp(key(a), key(b))
  if result == 0:
    result = cmp(a.dir, b.dir)

proc sessions*(store: RecoveryStore): seq[RecoverySession] =
  ## Newest first. Empty sessions are omitted unless their listing failed.
  for dir in sessionDirs(store.baseDir):
    let session = readSession(dir)
    if session.files.len > 0 or not session.listed:
      result.add(session)
  result.sort(sessionOrder)
  result.reverse()

proc payloadHasCopy(sessionDir: string): bool =
  try:
    for kind, path in walkDir(payloadDir(sessionDir), checkDir = true):
      if kind == pcFile and isPayloadFileName(path.lastPathPart):
        return true
  except CatchableError:
    # Could not look. Assume there is something rather than hide a preserve.
    return true
  false

proc legacyHasCopy(sessionDir: string): bool =
  try:
    for kind, path in walkDir(sessionDir, checkDir = true):
      if kind notin {pcFile, pcLinkToFile}:
        continue
      let name = path.lastPathPart
      if name != MetadataName and name != MetadataTempName:
        return true
  except CatchableError:
    return true
  false

proc hasPreservedCopies*(store: RecoveryStore): bool =
  ## Whether `sessions` would return anything. Stops at the first copy and
  ## reads no manifest.
  if store.baseDir.len == 0 or not dirExists(store.baseDir):
    return false
  try:
    for kind, path in walkDir(store.baseDir, checkDir = true):
      if kind notin {pcDir, pcLinkToDir}:
        continue
      if dirExists(payloadDir(path)):
        if payloadHasCopy(path):
          return true
      elif legacyHasCopy(path):
        return true
  except CatchableError:
    # Gone: empty. Unlistable: assume a preserve, same as an unlistable session.
    return dirExists(store.baseDir)
  false

proc copiesOf*(store: RecoveryStore, path: string): seq[PreservedCopy] =
  ## Copies of `path`, newest first. Compared via `pathKey`.
  if path.len == 0:
    return @[]
  for session in sessions(store):
    for f in session.files:
      if f.origin.isSome and samePath(f.origin.get, path):
        result.add(PreservedCopy(file: f, session: session))

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

proc verdict*(c: PreservedCopy): CopyVerdict =
  ## Whether the original already holds what was preserved.
  ##
  ## If the origin still carries the preserve-time stamp, `cvDiffers` without
  ## reading: the copy came from a modified buffer. Otherwise compare bytes.
  let file = c.file
  if file.origin.isNone or file.origin.get.len == 0:
    return cvNoOrigin
  if not fileExists(file.path):
    return cvUnknown
  let origin = file.origin.get
  try:
    if not fileExists(origin):
      return cvOriginalGone
    if stampHeld(file.originStamp, origin):
      return cvDiffers
    if getFileSize(origin) != getFileSize(file.path):
      return cvDiffers
    if readFile(origin) == readFile(file.path):
      return cvSame
    return cvDiffers
  except CatchableError:
    return cvUnknown

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

proc discardCopy*(
    store: RecoveryStore, copyPath, sessionDir: string, reason: var string
): bool =
  ## Remove one copy and drop it from the manifest. The session directory
  ## goes too once nothing is left in it; both must sit inside the store.
  if not isDirectChild(sessionDir, store.baseDir):
    reason = "it is outside the recovery directory"
    return false
  if symlinkExists(sessionDir):
    # copyPath would be outside the cache; dropping it would unlink the real file.
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
  try:
    removeFile(copyPath)
  except CatchableError as e:
    reason = sanitizeForDisplay(e.msg)
    return false
  dropManifestEntry(sessionDir, copyPath.lastPathPart)
  let session = readSession(sessionDir)
  if session.listed and session.files.len == 0:
    return discardSession(store, sessionDir, reason)
  true

proc discardCopy*(
    store: RecoveryStore, copyPath, sessionDir: string
): bool {.discardable.} =
  var reason: string
  discardCopy(store, copyPath, sessionDir, reason)
