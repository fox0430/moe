#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

## Search utility functions for common search operations
##
## Provides helper functions for case-sensitive/insensitive matching,
## smartcase logic, and search history persistence

import std/[strutils, os, appdirs, paths, strformat]

import pkg/results

import logger

proc hasUpperCase*(s: string): bool =
  ## Check if string contains any uppercase ASCII characters
  ## Used for smartcase logic
  for c in s:
    if c >= 'A' and c <= 'Z':
      return true
  false

proc shouldIgnoreCase*(searchText: string, ignorecase: bool, smartcase: bool): bool =
  ## Determine if search should be case-insensitive
  ## Applies smartcase logic: if smartcase is enabled and search contains
  ## uppercase, override ignorecase and search case-sensitively
  if not ignorecase:
    return false

  if smartcase and searchText.hasUpperCase():
    return false

  true

proc prepareSearchString*(text: string, ignorecase: bool): string =
  ## Convert text to lowercase if case-insensitive search is needed
  ## Returns original text if case-sensitive
  if ignorecase:
    text.toLowerAscii()
  else:
    text

# Search history persistence

# TODO: Add MaxHistoryEntries to the editor config
const MaxHistoryEntries* = 50

proc getSearchHistoryPath*(): Result[Path, string] =
  ## Get the path to the search history file
  ## Returns: ~/$XDG_CACHE_HOME/moe/search_history
  let cacheDir = appdirs.getCacheDir()
  if len(cacheDir.string) == 0:
    return Result[Path, string].err "Failed to get history path"

  var p = cacheDir
  p.add Path("moe")
  p.add Path("search_history")

  return Result[Path, string].ok p

proc loadSearchHistory*(): seq[string] =
  ## Load search history from disk
  ## Returns: sequence of search patterns (most recent first)
  ## Returns empty sequence if file doesn't exist or on error
  let historyPath = getSearchHistoryPath()
  if historyPath.isErr:
    logError("search_utils", historyPath.error)
    return

  let historyPathStr = historyPath.get.string

  if not fileExists(historyPathStr):
    logDebug("search_utils", fmt"history file not found: {historyPathStr}")
    return

  try:
    let content = readFile(historyPathStr)
    for line in content.splitLines():
      let trimmed = line.strip()
      if trimmed.len > 0:
        result.add trimmed
        # Limit to max entries
        if result.len >= MaxHistoryEntries:
          break
  except CatchableError as e:
    # Silently ignore read errors and return empty history
    logError("search_utils", e.msg)
    return @[]

proc saveSearchHistory*(history: seq[string]): Result[(), string] =
  ## Save search history to disk
  ## Saves up to MaxHistoryEntries entries (most recent first)
  ## Silently ignores errors

  let historyPath = getSearchHistoryPath()
  if historyPath.isErr:
    logError("search_utils", historyPath.error)
    return

  let
    pathSplited = historyPath.get.splitPath
    pathHeadStr = pathSplited.head.string
  if not dirExists(pathHeadStr):
    try:
      createDir(pathHeadStr)
    except CatchableError as e:
      logError("search_utils", fmt"Failed to create dir: {e.msg}: {pathHeadStr}")

  let historyPathStr = historyPath.get.string

  if historyPathStr.len == 0:
    logDebug("search_utils", fmt"history file not found: {historyPathStr}")
    return

  try:
    # Take only the most recent MaxHistoryEntries entries
    let entriesToSave =
      if history.len > MaxHistoryEntries:
        history[0 ..< MaxHistoryEntries]
      else:
        history

    # Write each entry on a separate line
    var content = ""
    for i, entry in entriesToSave:
      # Skip empty entries
      if entry.len == 0:
        continue
      content.add entry
      # Add newline except for last entry
      if i < entriesToSave.high:
        content.add("\n")

    writeFile(historyPathStr, content)
  except CatchableError as e:
    return err(e.msg)
