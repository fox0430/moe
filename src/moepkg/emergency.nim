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

## Emergency buffer save on crash
##
## When the editor crashes due to an unhandled exception, this module saves
## all modified (unsaved) buffers to ~/.cache/moe/crash_recovery/<timestamp>/.
## A recovery.json file maps recovery filenames to their original file paths.

import std/[os, times, json, options, strformat]

import types/editor_types, buffer/[core, file_io], backup

const DefaultCrashRecoveryDir* = "~/.cache/moe/crash_recovery"

proc getCrashRecoveryBaseDir*(): string =
  return expandBackupDir(DefaultCrashRecoveryDir)

proc hasCrashRecoveryFiles*(baseDir: string = getCrashRecoveryBaseDir()): bool =
  if not dirExists(baseDir):
    return false
  for _ in walkDirs(baseDir / "*"):
    return true
  return false

proc emergencySaveBuffers*(
    editor: Editor, baseDir: string = getCrashRecoveryBaseDir()
): seq[string] =
  ## Save all modified buffers to crash recovery directory.
  ## Returns list of saved file paths.

  let timestamp = now().format("yyyyMMdd'T'HHmmss")
  let recoveryDir = baseDir / timestamp

  try:
    createDir(recoveryDir)
  except CatchableError:
    return @[]

  var savedPaths: seq[string] = @[]
  var metadata = newJObject()

  # Iterate `e.buffers`, not windows: windows only expose the foreground tab,
  # so background-tab buffers would be lost.
  for buf in editor.buffers:
    if not buf.isModified:
      continue

    let recoveryName =
      if buf.filePath.isSome:
        extractFilename(buf.filePath.get)
      else:
        fmt"untitled_{buf.id}"

    # Handle duplicate filenames by appending buffer id
    var finalName = recoveryName
    if metadata.hasKey(finalName):
      finalName = fmt"{buf.id}_{recoveryName}"

    let recoveryPath = recoveryDir / finalName

    try:
      let content = buf.getFileContent()
      writeFile(recoveryPath, content)
      savedPaths.add(recoveryPath)

      let originalPath = if buf.filePath.isSome: buf.filePath.get else: ""
      metadata[finalName] = %*{"originalPath": originalPath}
    except CatchableError as e:
      stderr.writeLine "moe: emergency save failed for " & finalName & ": " & e.msg

  if savedPaths.len > 0:
    try:
      writeFile(recoveryDir / "recovery.json", $metadata)
    except CatchableError as e:
      stderr.writeLine "moe: failed to write recovery metadata: " & e.msg
  else:
    # No files saved, remove the empty directory
    try:
      removeDir(recoveryDir)
    except CatchableError:
      discard

  return savedPaths
