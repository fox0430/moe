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

## Preserve unsaved buffers when the editor cannot ask the user.
##
## Copies go under `<base>/<timestamp>_<pid>/payload/`, written then renamed
## so a visible name is complete (process death only; no fsync). No file a
## buffer came from is touched until every copy is written and described: it
## may sit on a mount that never answers. The manifest is then written again
## as that adds to it; a session without one still offers its copies.

import std/[json, options, os, strformat, times]

when defined(posix):
  from std/posix import mkdir, Mode

import
  types/editor_types, buffer/[core, file_io], path_key, recovery_format, unicode_utils

const MaxSessionDirAttempts = 64

proc createPrivateDir(dir: string): bool =
  ## Create `dir` with mode 0700. Fail if it already exists.
  try:
    createDir(dir.parentDir)
  except CatchableError:
    return false

  when defined(posix):
    return mkdir(dir.cstring, 0o700.Mode) == 0
  else:
    try:
      # createDir would succeed on an existing dir and skip collision retry.
      if existsOrCreateDir(dir):
        return false
      # chmod after create is racy; POSIX mkdir(0700) is unavailable here.
      setFilePermissions(dir, {fpUserRead, fpUserWrite, fpUserExec})
      return true
    except CatchableError:
      return false

proc removeQuietly(path: string) =
  try:
    removeFile(path)
  except CatchableError:
    discard

proc dirIsEmpty(dir: string): bool =
  ## False when `dir` holds anything or cannot be read.
  try:
    for _ in walkDir(dir, checkDir = true):
      return false
  except CatchableError:
    return false
  true

proc payloadBase(path: string): string =
  var base = extractFilename(path)
  if base.len == 0 or base in [".", ".."]:
    base = "untitled"
  result = truncateBytes(base, MaxPayloadBaseLen)
  if result.len == 0:
    # Every byte was a UTF-8 continuation byte; keep the name usable.
    result = "untitled"

proc payloadName(buf: TextBuffer, index: int): string =
  let base =
    if buf.filePath.isSome:
      payloadBase(buf.filePath.get)
    else:
      "untitled"
  payloadFileName(index, base)

proc originEntry(buf: TextBuffer, name: string): JsonNode =
  ## Stats and reads nothing.
  result = newJObject()
  result[ManifestNameKey] = %name
  if buf.filePath.isSome:
    # Absolute: relative names collide across directories.
    result[ManifestOriginKey] = %pathKey(buf.filePath.get)

proc addStamp(entry: JsonNode, path: string) =
  ## Tell unsaved work apart from later writes to the file.
  let stamp = captureFileStamp(path)
  if stamp.observed == fileObservedPresent:
    let mtimeNs = toUnixNano(stamp.modTime)
    if mtimeNs.isSome:
      entry[ManifestOriginMtimeNsKey] = %mtimeNs.get
    entry[ManifestOriginSizeKey] = %stamp.size

proc boundedDetail(detail: string): string =
  if detail.len <= MaxDetailBytes:
    return detail
  result = truncateBytes(detail, MaxDetailBytes)

type CopyCommit* = proc(scratchPath, finalPath: string): bool {.raises: [].}
  ## Commit a scratch copy under its final name. Tests inject a stub.

proc emergencySaveBuffers*(
    editor: Editor,
    continuity: ContinuityKind,
    detail: string = "",
    baseDir: string = getCrashRecoveryBaseDir(),
    commit: CopyCommit = renameIntoPlace,
): seq[string] {.raises: [].} =
  ## Save modified buffers. Never raises: the caller may already be dying.

  # Timestamp + pid, with a numeric suffix if that directory already exists.
  let savedAt = now()
  let dirBase = fmt"""{savedAt.format("yyyyMMdd'T'HHmmss")}_{getCurrentProcessId()}"""

  var recoveryDir = baseDir / dirBase
  var attempt = 2
  while not createPrivateDir(recoveryDir):
    if not dirExists(recoveryDir) or attempt > MaxSessionDirAttempts:
      reportCrashNotice(
        "moe: could not create recovery directory " & sanitizeForDisplay(recoveryDir)
      )
      return @[]
    recoveryDir = baseDir / fmt"{dirBase}_{attempt}"
    inc attempt

  let payloadDir = recoveryDir / PayloadDirName
  if not createPrivateDir(payloadDir):
    reportCrashNotice(
      "moe: could not create the payload directory " & sanitizeForDisplay(payloadDir)
    )
    try:
      removeDir(recoveryDir)
    except CatchableError:
      discard
    return @[]

  var savedPaths: seq[string] = @[]
  var entries = newJArray()
  var unstamped: seq[(JsonNode, string)]
  var index = 0

  proc preserve(buf: TextBuffer, content: string, readFailure = ""): bool =
    ## Write `buf`'s copy, or report why there is none. True when it landed.
    var failure = readFailure
    # Keep the index on a failed write so nothing else reuses a half-written name.
    let finalName = buf.payloadName(index)
    inc index
    let finalPath = payloadDir / finalName
    # A scratch name is not a payload name, so nothing offers it as a copy.
    let scratchPath = payloadDir / ("." & finalName)

    var saved = false
    if failure.len == 0:
      try:
        writeFile(scratchPath, content)
        restrictToUser(scratchPath)
        if commit(scratchPath, finalPath):
          saved = true
        else:
          failure = "the copy could not be renamed into place"
      except CatchableError as e:
        failure = sanitizeForDisplay(e.msg)

    result = saved
    if saved:
      savedPaths.add(finalPath)
      try:
        let entry = buf.originEntry(finalName)
        entries.add entry
        if buf.filePath.isSome:
          unstamped.add (entry, buf.filePath.get)
      except CatchableError:
        # The origin is enrichment; the copy is preserved either way.
        discard
    else:
      reportCrashNotice(
        "moe: emergency save failed for " & sanitizeForDisplay(finalName) & ": " &
          failure
      )
      # Drop both so neither is offered as recoverable content.
      removeQuietly(scratchPath)
      removeQuietly(finalPath)

  proc describeSaved() =
    ## Write the manifest for every copy saved so far.
    if savedPaths.len == 0:
      return
    var metadata = newJObject()
    metadata[ManifestFormatKey] = %FormatName
    metadata[ManifestVersionKey] = %FormatVersion
    metadata[ManifestSavedAtKey] = %savedAt.toTime.toUnix
    metadata[ManifestContinuityKey] = %($continuity)
    metadata[ManifestDetailKey] = %boundedDetail(detail)
    metadata[ManifestFilesKey] = entries
    discard writeManifest(recoveryDir, metadata)

  proc stampSaved() =
    for (entry, path) in unstamped:
      try:
        entry.addStamp(path)
      except CatchableError:
        discard
    unstamped.setLen 0

  # Modified, but holding what it last read or wrote: only a copy the file no
  # longer holds is work to preserve, and a copy of the rest would be announced
  # with nothing to offer. Asking means reading the file, so it waits too.
  # Their text is taken again then, not held meanwhile.
  var unchanged: seq[TextBuffer]

  # Iterate `e.buffers`, not windows: windows only expose the foreground tab.
  for buf in editor.buffers:
    if not buf.isModified:
      continue

    var content = ""
    var failure = ""
    try:
      content = buf.getFileContent()
    except CatchableError as e:
      failure = sanitizeForDisplay(e.msg)
    if failure.len == 0 and buf.lastLoadedContent == some(fingerprint(content)) and
        buf.filePath.isSome:
      unchanged.add buf
    else:
      discard preserve(buf, content, failure)

  describeSaved()

  # From here on the files are touched, work first: whatever is described
  # stays so if one never answers.
  for buf in unchanged:
    var content = ""
    try:
      content = buf.getFileContent()
    except CatchableError as e:
      discard preserve(buf, "", sanitizeForDisplay(e.msg))
      continue
    # The file is read, not trusted: it may be gone.
    if not fileHolds(buf.filePath.get, content) and preserve(buf, content):
      describeSaved()

  # Stamps only add detail, so they come last.
  if unstamped.len > 0:
    stampSaved()
    describeSaved()

  if savedPaths.len == 0:
    # Remove empty dirs we created; never a directory that holds files.
    if dirIsEmpty(payloadDir):
      try:
        removeDir(payloadDir)
      except CatchableError:
        discard
    if dirIsEmpty(recoveryDir):
      try:
        removeDir(recoveryDir)
      except CatchableError:
        discard

  return savedPaths
