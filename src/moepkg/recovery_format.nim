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

## Shared names, grammar and manifest schema for crash recovery.

import std/[json, math, options, os, strformat, times]

when defined(posix):
  proc cRename(source, dest: cstring): cint {.importc: "rename", header: "<stdio.h>".}
    ## rename(2): atomic in-directory; reports failure instead of raising.

import backup, unicode_utils

const DefaultCrashRecoveryDir* = "~/.cache/moe/crash_recovery"

const PayloadDirName* = "payload"
  ## Session copies live only here; presence marks the current shape.

const MetadataName* = "recovery.json"

const MetadataTempName* = "recovery.json.tmp"

# Manifest keys. An older shape spells the origin `LegacyOriginPathKey`.
const ManifestFormatKey* = "format"

const ManifestVersionKey* = "version"

const ManifestSavedAtKey* = "savedAt"

const ManifestContinuityKey* = "continuity"

const ManifestDetailKey* = "detail"

const ManifestFilesKey* = "files"

const ManifestNameKey* = "name"

const ManifestOriginKey* = "origin"

const ManifestOriginMtimeNsKey* = "originMtimeNs"

const ManifestOriginSizeKey* = "originSize"

const LegacyOriginPathKey* = "originalPath"

const FormatName* = "moe-recovery"

const FormatVersion* = 3
  ## Current shape. Older files have no `format`: a flat name→origin map
  ## (v0), optionally with `version`, `cause`, `detail`, `savedAt` and stamps
  ## (v1). This shape uses `format` = "moe-recovery". A newer `version` is
  ## not interpreted; origins stay unknown.

const MaxDetailBytes* = 4096 ## Bound on free text from a dying process.

const MaxPayloadBaseLen* = 80
  ## Truncated so the indexed copy still fits in one path component.

type ContinuityKind* = enum
  ckCrash = "crash"
  ckSignal = "signal"
  ckUnknown = "unknown" ## Unrecorded, or a value this version does not know.

type OriginStamp* = object
  ## Original file at preserve time; both fields optional, from one stat.
  mtime*: Option[Time]
  size*: Option[int64]

proc getCrashRecoveryBaseDir*(): string =
  expandBackupDir(DefaultCrashRecoveryDir)

proc toContinuityKind*(s: string): ContinuityKind =
  case s
  of "crash": ckCrash
  of "signal": ckSignal
  else: ckUnknown

proc isPayloadFileName*(name: string): bool =
  ## Digits, a dash, then the origin base. Index width is a minimum, not a bound.
  if name.len < 3 or name != name.lastPathPart:
    return false
  var i = 0
  while i < name.len and name[i] in {'0' .. '9'}:
    inc i
  result = i > 0 and i < name.len - 1 and name[i] == '-'

proc payloadFileName*(index: int, base: string): string =
  ## Index plus origin base. The index only disambiguates; width is a minimum.
  fmt"{index:04}-{base}"

proc truncateBytes*(s: string, maxBytes: int): string =
  ## Longest prefix of `s` that is at most `maxBytes` bytes and does not split
  ## a UTF-8 sequence.
  if maxBytes <= 0:
    return ""
  if s.len <= maxBytes:
    return s
  # Walk back over continuation bytes (10xxxxxx) left by the cut.
  var cut = maxBytes
  while cut > 0 and (s[cut].ord and 0xC0) == 0x80:
    dec cut
  s[0 ..< cut]

const MaxStampSeconds = high(int64) div 1_000_000_000 - 1
  ## Last whole second whose nanoseconds always fit in an int64. The exact
  ## edge also depends on the nanosecond part, so this stays a second clear.

const MinStampSeconds = low(int64) div 1_000_000_000
  ## First whole second (negative) whose nanoseconds always fit in an int64.

proc toUnixNano*(t: Time): Option[int64] =
  ## Nanoseconds since the Unix epoch, or none if the stamp does not fit in
  ## int64 (before 1678 or after 2262).
  if t.toUnix > MaxStampSeconds or t.toUnix < MinStampSeconds:
    return none(int64)
  return some(t.toUnix * 1_000_000_000 + t.nanosecond.int64)

proc fromUnixNano*(v: int64): Time =
  initTime(floorDiv(v, 1_000_000_000), floorMod(v, 1_000_000_000).int)

proc restrictToUser*(path: string) =
  ## Best-effort 0600. The directory mode is the real barrier.
  try:
    setFilePermissions(path, {fpUserRead, fpUserWrite})
  except CatchableError:
    discard

proc reportCrashNotice*(line: string) {.raises: [].} =
  ## Best-effort stderr notice from a dying process.
  try:
    stderr.writeLine line
  except CatchableError:
    discard

proc renameIntoPlace*(source, dest: string): bool {.raises: [].} =
  ## Rename over `dest` without raising. Nim's `moveFile` carries `Exception`
  ## in its effect set, which the crash path cannot.
  when defined(posix):
    result = cRename(source.cstring, dest.cstring) == 0
  else:
    {.cast(raises: []).}:
      try:
        moveFile(source, dest)
        result = true
      except CatchableError:
        result = false

proc writeManifest*(dir: string, metadata: JsonNode): bool =
  ## Write `metadata` beside the manifest, then rename it into place.
  let tmp = dir / MetadataTempName
  try:
    writeFile(tmp, $metadata)
    restrictToUser(tmp)
  except CatchableError as e:
    reportCrashNotice(
      "moe: failed to write recovery metadata: " & sanitizeForDisplay(e.msg)
    )
    # Drop a partial temp file so it is never read as the manifest.
    try:
      removeFile(tmp)
    except CatchableError:
      discard
    return false
  if renameIntoPlace(tmp, dir / MetadataName):
    return true
  reportCrashNotice(
    "moe: failed to rename recovery metadata in " & sanitizeForDisplay(dir)
  )
  try:
    removeFile(tmp)
  except CatchableError:
    discard
  false
