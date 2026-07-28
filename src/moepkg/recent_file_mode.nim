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

## Recent File Mode state management
##
## This module provides state management for the Recent File selection mode,
## which displays recently used files from ~/.local/share/recently-used.xbel

import std/[os, options, uri, strutils]

import pkg/results

import buffer/core, list_viewer
import types/recent_file_mode_types

export recent_file_mode_types
export list_viewer

proc newRecentFileModeState*(): RecentFileModeState =
  ## Create a new RecentFileModeState
  RecentFileModeState(items: @[], selectedIndex: 0)

proc getRecentUsedXbelPath*(): string =
  ## Return the path to the recently-used.xbel file
  getHomeDir() / ".local/share/recently-used.xbel"

proc getRecentUsedFiles*(xbelPath: string): Result[seq[string], string] =
  ## Return file paths from recently-used.xbel
  ##
  ## The xbel file is in freedesktop.org bookmark format:
  ## <bookmark href="file:///home/user/file.txt" ...>

  if not fileExists(xbelPath):
    return Result[seq[string], string].ok @[]

  var xbelBuffer: string
  try:
    xbelBuffer = readFile(xbelPath)
  except CatchableError:
    return Result[seq[string], string].ok @[]

  var files: seq[string]
  # Parse bookmark href attributes containing file:// URIs
  # Format: <bookmark href="file:///path/to/file" ...>
  const hrefPrefix = "href=\"file://"
  var pos = 0
  while true:
    pos = xbelBuffer.find(hrefPrefix, pos)
    if pos == -1:
      break
    pos += hrefPrefix.len
    let endPos = xbelBuffer.find('"', pos)
    if endPos == -1:
      break
    let rawPath = xbelBuffer[pos ..< endPos]
    # Decode URL-encoded characters (e.g., %20 -> space)
    files.add decodeUrl(rawPath)
    pos = endPos

  return Result[seq[string], string].ok files

proc loadRecentFiles*(state: RecentFileModeState): Result[void, string] =
  ## Load recent files into state
  let xbelPath = getRecentUsedXbelPath()
  let filesResult = getRecentUsedFiles(xbelPath)
  if filesResult.isErr:
    return Result[void, string].err filesResult.error

  state.items = @[]
  for path in filesResult.get:
    state.items.add RecentFileEntry(path: path)

  state.selectedIndex = 0

  return Result[void, string].ok()

proc len*(state: RecentFileModeState): int =
  ## Get number of files
  state.items.len

proc isEmpty*(state: RecentFileModeState): bool =
  ## Check if file list is empty
  state.items.len == 0

proc getSelectedPath*(state: RecentFileModeState): Option[string] =
  ## Get the currently selected file path. (The selected entry itself is
  ## available via the generic `getSelectedItem`.)
  if state.isEmpty or state.selectedIndex >= state.items.len:
    return none(string)
  return some(state.items[state.selectedIndex].path)

proc selectedFileExists*(state: RecentFileModeState): bool =
  ## Check if the currently selected file exists on disk
  let selected = state.getSelectedPath()
  if selected.isNone:
    return false
  return fileExists(selected.get)

proc createRecentFileTextBuffer*(state: RecentFileModeState): TextBuffer =
  ## Create a TextBuffer from recent files for rendering via the normal view path
  result = state.toListTextBuffer(
    "-- Recent Files --",
    proc(entry: RecentFileEntry): string =
      entry.path,
  )
  result.isUtilityBuffer = true
