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

## Persistence utilities for moe editor
##
## Handles saving and loading of:
## - Command history (ex-mode commands)
## - Cursor positions (per file)

import std/[os, appdirs, paths, strformat, strutils, tables, json, options]

import pkg/results

import logger
import types/persist_types
export persist_types

# Default limits (can be overridden by config)
const
  DefaultCommandHistoryLimit* = 1000
  DefaultSearchHistoryLimit* = 1000

# Command History

proc getCommandHistoryPath*(): Result[Path, string] =
  ## Get the path to the command history file
  ## Returns: ~/$XDG_CACHE_HOME/moe/command_history
  let cacheDir = appdirs.getCacheDir()
  if len(cacheDir.string) == 0:
    return Result[Path, string].err "Failed to get cache directory"

  var p = cacheDir
  p.add Path("moe")
  p.add Path("command_history")

  return Result[Path, string].ok p

proc loadCommandHistory*(limit: int = DefaultCommandHistoryLimit): seq[string] =
  ## Load command history from disk
  ## Returns: sequence of commands (most recent first)
  ## Returns empty sequence if file doesn't exist or on error
  let historyPath = getCommandHistoryPath()
  if historyPath.isErr:
    logError("persist", historyPath.error)
    return @[]

  let historyPathStr = historyPath.get.string

  if not fileExists(historyPathStr):
    logDebug("persist", fmt"command history file not found: {historyPathStr}")
    return @[]

  try:
    let content = readFile(historyPathStr)
    for line in content.splitLines():
      let trimmed = line.strip()
      if trimmed.len > 0:
        result.add trimmed
        if result.len >= limit:
          break
  except CatchableError as e:
    logError("persist", fmt"Failed to load command history: {e.msg}")
    return @[]

proc saveCommandHistory*(
    history: seq[string], limit: int = DefaultCommandHistoryLimit
): Result[void, string] =
  ## Save command history to disk
  ## Saves up to `limit` entries (most recent first)

  let historyPath = getCommandHistoryPath()
  if historyPath.isErr:
    return err(historyPath.error)

  let
    pathSplited = historyPath.get.splitPath
    pathHeadStr = pathSplited.head.string

  if not dirExists(pathHeadStr):
    try:
      createDir(pathHeadStr)
    except CatchableError as e:
      return err(fmt"Failed to create dir: {e.msg}: {pathHeadStr}")

  let historyPathStr = historyPath.get.string

  try:
    # Take only the most recent entries
    let entriesToSave =
      if history.len > limit:
        history[0 ..< limit]
      else:
        history

    var content = ""
    for i, entry in entriesToSave:
      if entry.len == 0:
        continue
      content.add entry
      if i < entriesToSave.high:
        content.add("\n")

    writeFile(historyPathStr, content)
    return ok()
  except CatchableError as e:
    return err(fmt"Failed to save command history: {e.msg}")

# Cursor Position Persistence

proc getCursorPositionsPath*(): Result[Path, string] =
  ## Get the path to the cursor positions file
  ## Returns: ~/$XDG_CACHE_HOME/moe/cursor_positions.json
  let cacheDir = appdirs.getCacheDir()
  if len(cacheDir.string) == 0:
    return Result[Path, string].err "Failed to get cache directory"

  var p = cacheDir
  p.add Path("moe")
  p.add Path("cursor_positions.json")

  return Result[Path, string].ok p

proc loadCursorPositions*(): Table[string, CursorPositionEntry] =
  ## Load cursor positions from disk
  ## Returns: table mapping absolute file paths to cursor positions
  ## Returns empty table if file doesn't exist or on error
  result = initTable[string, CursorPositionEntry]()

  let posPath = getCursorPositionsPath()
  if posPath.isErr:
    logError("persist", posPath.error)
    return

  let posPathStr = posPath.get.string

  if not fileExists(posPathStr):
    logDebug("persist", fmt"cursor positions file not found: {posPathStr}")
    return

  try:
    let content = readFile(posPathStr)
    let jsonNode = parseJson(content)

    if jsonNode.kind == JObject:
      for path, pos in jsonNode.pairs:
        if pos.kind == JObject and pos.hasKey("line") and pos.hasKey("column"):
          result[path] = CursorPositionEntry(
            line: pos["line"].getInt(), column: pos["column"].getInt()
          )
  except CatchableError as e:
    logError("persist", fmt"Failed to load cursor positions: {e.msg}")
    return initTable[string, CursorPositionEntry]()

proc saveCursorPositions*(
    positions: Table[string, CursorPositionEntry]
): Result[void, string] =
  ## Save cursor positions to disk as JSON

  let posPath = getCursorPositionsPath()
  if posPath.isErr:
    return err(posPath.error)

  let
    pathSplited = posPath.get.splitPath
    pathHeadStr = pathSplited.head.string

  if not dirExists(pathHeadStr):
    try:
      createDir(pathHeadStr)
    except CatchableError as e:
      return err(fmt"Failed to create dir: {e.msg}: {pathHeadStr}")

  let posPathStr = posPath.get.string

  try:
    var jsonObj = newJObject()
    for path, pos in positions.pairs:
      jsonObj[path] = %*{"line": pos.line, "column": pos.column}

    writeFile(posPathStr, $jsonObj)
    return ok()
  except CatchableError as e:
    return err(fmt"Failed to save cursor positions: {e.msg}")

proc getCursorPosition*(
    positions: Table[string, CursorPositionEntry], filePath: string
): Option[CursorPositionEntry] =
  ## Get cursor position for a specific file
  ## Returns none if not found
  let absPath = absolutePath(filePath)
  if positions.hasKey(absPath):
    return some(positions[absPath])
  return none(CursorPositionEntry)

proc setCursorPosition*(
    positions: var Table[string, CursorPositionEntry],
    filePath: string,
    line: int,
    column: int,
) =
  ## Set cursor position for a specific file
  let absPath = absolutePath(filePath)
  positions[absPath] = CursorPositionEntry(line: line, column: column)

# Bookmark Persistence

proc getBookmarksPath*(): Result[Path, string] =
  ## Get the path to the bookmarks file
  ## Returns: ~/$XDG_CACHE_HOME/moe/bookmarks.json
  let cacheDir = appdirs.getCacheDir()
  if len(cacheDir.string) == 0:
    return Result[Path, string].err "Failed to get cache directory"

  var p = cacheDir
  p.add Path("moe")
  p.add Path("bookmarks.json")

  return Result[Path, string].ok p

proc loadBookmarks*(): Table[string, seq[int]] =
  ## Load bookmarks from disk
  ## Returns: table mapping absolute file paths to sorted bookmark line numbers
  result = initTable[string, seq[int]]()

  let bmPath = getBookmarksPath()
  if bmPath.isErr:
    logError("persist", bmPath.error)
    return

  let bmPathStr = bmPath.get.string

  if not fileExists(bmPathStr):
    logDebug("persist", fmt"bookmarks file not found: {bmPathStr}")
    return

  try:
    let content = readFile(bmPathStr)
    let jsonNode = parseJson(content)

    if jsonNode.kind == JObject:
      for path, lines in jsonNode.pairs:
        if lines.kind == JArray:
          var bookmarks: seq[int] = @[]
          for lineNode in lines:
            if lineNode.kind == JInt:
              let lineNum = lineNode.getInt()
              if lineNum >= 0:
                bookmarks.add(lineNum)
          if bookmarks.len > 0:
            result[path] = bookmarks
  except CatchableError as e:
    logError("persist", fmt"Failed to load bookmarks: {e.msg}")
    return initTable[string, seq[int]]()

proc saveBookmarks*(bookmarks: Table[string, seq[int]]): Result[void, string] =
  ## Save bookmarks to disk as JSON

  let bmPath = getBookmarksPath()
  if bmPath.isErr:
    return err(bmPath.error)

  let
    pathSplited = bmPath.get.splitPath
    pathHeadStr = pathSplited.head.string

  if not dirExists(pathHeadStr):
    try:
      createDir(pathHeadStr)
    except CatchableError as e:
      return err(fmt"Failed to create dir: {e.msg}: {pathHeadStr}")

  let bmPathStr = bmPath.get.string

  try:
    var jsonObj = newJObject()
    for path, lines in bookmarks.pairs:
      if lines.len > 0:
        jsonObj[path] = %lines

    writeFile(bmPathStr, $jsonObj)
    return ok()
  except CatchableError as e:
    return err(fmt"Failed to save bookmarks: {e.msg}")
