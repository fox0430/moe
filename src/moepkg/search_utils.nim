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

## Search utility functions for common search operations
##
## Provides helper functions for case-sensitive/insensitive matching,
## smartcase logic, and search history / last search persistence

import std/[strutils, os, appdirs, paths, strformat, options, json]

import pkg/results

import logger, persist, regex_syntax, buffer/[search, atomic_write]

var upperCache: tuple[pattern: string, hasUpper: bool]

proc hasUpperCase*(s: string): bool =
  ## Whether regex `s` has an upper case letter, for 'smartcase'. Unlike Vim's
  ## pat_has_uppercase, which skips every escape, an escape that nim-regex
  ## reads as a letter counts. The last answer is kept: the renderer asks once
  ## per line.
  if s != upperCache.pattern:
    upperCache = (s, s.hasUpperLiteral)
  upperCache.hasUpper

proc shouldIgnoreCase*(searchText: string, ignorecase: bool, smartcase: bool): bool =
  ## Determine if search should be case-insensitive
  ## Applies smartcase logic: if smartcase is enabled and search contains
  ## uppercase, override ignorecase and search case-sensitively
  if not ignorecase:
    return false

  if smartcase and searchText.hasUpperCase():
    return false

  true

# Search history persistence

const DefaultSearchHistoryLimit* = 1000

# Last search persistence

type LastSearch* = object
  ## The last search, kept for the next session as Vim's viminfo keeps `@/`.
  ## Its direction is not kept: as in Vim, a new session searches forward.
  pattern*: string
  match*: SearchMatch

proc getLastSearchPath*(): Result[Path, string] =
  ## Returns: ~/$XDG_CACHE_HOME/moe/last_search
  cacheFilePath("last_search")

proc parseMatch(s: string): SearchMatch =
  ## What `s` names for a match, `smRegex` for anything else.
  try:
    parseEnum[SearchMatch](s)
  except ValueError:
    smRegex

proc loadLastSearch*(): Option[LastSearch] =
  ## The last search the previous session saved, if any.
  let path = getLastSearchPath()
  if path.isErr:
    logError("search_utils", path.error)
    return none(LastSearch)

  let file = path.get.string
  if not fileExists(file):
    return none(LastSearch)

  try:
    let node = parseFile(file)
    if node.kind != JObject:
      return none(LastSearch)
    let pattern =
      if node.hasKey("pattern"):
        node["pattern"].getStr
      else:
        ""
    if pattern.len == 0:
      return none(LastSearch)
    some(
      LastSearch(
        pattern: pattern,
        match: parseMatch(
          if node.hasKey("match"):
            node["match"].getStr
          else:
            ""
        ),
      )
    )
  except CatchableError as e:
    logError("search_utils", "Failed to load the last search: " & e.msg)
    none(LastSearch)

proc saveLastSearch*(last: LastSearch): Result[void, string] =
  ## Save `last` for the next session.
  let path = getLastSearchPath()
  if path.isErr:
    return err(path.error)

  let pathStr = path.get.string
  let dir = pathStr.parentDir
  try:
    createDir(dir)
  except CatchableError as e:
    return err(fmt"Failed to create dir: {e.msg}: {dir}")

  try:
    # `copyFileWithPermissions` in the hardlink path is declared to raise
    # `Exception`; it raises only OS and I/O errors.
    {.cast(raises: [CatchableError]).}:
      let w = writeAtomic(
        pathStr, $(%*{"pattern": last.pattern, "match": $last.match}), wpForce
      )
      if w.isErr:
        return err(fmt"{pathStr}: {w.error}")
  except CatchableError as e:
    return err(fmt"{pathStr}: {e.msg}")
  ok()

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

proc loadSearchHistory*(limit: int = DefaultSearchHistoryLimit): seq[string] =
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
        if result.len >= limit:
          break
  except CatchableError as e:
    # Silently ignore read errors and return empty history
    logError("search_utils", e.msg)
    return @[]

proc saveSearchHistory*(
    history: seq[string], limit: int = DefaultSearchHistoryLimit
): Result[(), string] =
  ## Save search history to disk
  ## Saves up to `limit` entries (most recent first)

  let historyPath = getSearchHistoryPath()
  if historyPath.isErr:
    logError("search_utils", historyPath.error)
    return Result[(), string].err(historyPath.error)

  let
    pathSplited = historyPath.get.splitPath
    pathHeadStr = pathSplited.head.string
  if not dirExists(pathHeadStr):
    try:
      createDir(pathHeadStr)
    except CatchableError as e:
      let errMsg = fmt"Failed to create dir: {e.msg}: {pathHeadStr}"
      logError("search_utils", errMsg)
      return Result[(), string].err(errMsg)

  let historyPathStr = historyPath.get.string

  if historyPathStr.len == 0:
    let errMsg = "History path is empty"
    logDebug("search_utils", errMsg)
    return Result[(), string].err(errMsg)

  try:
    # Take only the most recent entries
    let entriesToSave =
      if history.len > limit:
        history[0 ..< limit]
      else:
        history

    # Write each entry on a separate line
    var content = ""
    for i, entry in entriesToSave:
      # Skip empty entries, and ones a line break would make two when read
      if entry.len == 0 or entry.contains({'\r', '\n'}):
        continue
      content.add entry
      # Add newline except for last entry
      if i < entriesToSave.high:
        content.add("\n")

    writeFile(historyPathStr, content)
    return Result[(), string].ok(())
  except CatchableError as e:
    return Result[(), string].err(e.msg)
