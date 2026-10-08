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
## - Bookmarks (per file)

import
  std/[
    algorithm, os, appdirs, paths, sequtils, strformat, strutils, tables, json, options
  ]

import pkg/results

import logger, path_key
import buffer/atomic_write
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

# Per-file records
#
# Several sessions share one file, so a save merges the entries this session
# changed into what the file holds now instead of writing a table read at
# startup. Keys are `pathKey`s.

const MaxRecordedFiles* = 100
  ## Files a per-file record file keeps, as Vim's viminfo default `'100`.

type RecordParser[T] = proc(node: JsonNode): Option[T] {.nimcall, raises: [].}

proc cacheFilePath(name: string): Result[Path, string] =
  let cacheDir = appdirs.getCacheDir()
  if len(cacheDir.string) == 0:
    return Result[Path, string].err "Failed to get cache directory"

  var p = cacheDir
  p.add Path("moe")
  p.add Path(name)

  return Result[Path, string].ok p

proc loadRecords[T](
    path: Result[Path, string], parse: RecordParser[T]
): Result[OrderedTable[string, T], string] {.raises: [].} =
  ## Entries in `path` in file order; empty when there is no file. A file that
  ## cannot be read or is not a JSON object is an error, never an empty table.
  if path.isErr:
    return err(path.error)
  let pathStr = path.get.string
  var records = initOrderedTable[string, T]()
  if not fileExists(pathStr):
    return ok(records)
  try:
    let node = parseJson(readFile(pathStr))
    if node.kind != JObject:
      return err(fmt"{pathStr}: not a JSON object")
    for key, value in node.pairs:
      let parsed = parse(value)
      if parsed.isSome:
        records[pathKey(key)] = parsed.get
  except CatchableError as e:
    return err(fmt"{pathStr}: {e.msg}")
  ok(records)

proc toTable[T](records: OrderedTable[string, T]): Table[string, T] =
  for key, value in records:
    result[key] = value

proc updateRecords[T](
    path: Result[Path, string],
    changes: Table[string, T],
    opened: openArray[string],
    parse: RecordParser[T],
    emit: proc(value: T): JsonNode {.nimcall, raises: [].},
    drop: proc(value: T): bool {.nimcall, raises: [].},
): Result[void, string] {.raises: [].} =
  ## Apply `changes` onto the entries in `path`, leaving the rest as they are.
  ## A change `drop` accepts removes its entry. Like Vim's viminfo, the file
  ## keeps the `MaxRecordedFiles` most recent files: this session's changes and
  ## `opened` files first, then the file's own order. Nothing is written when
  ## the current file cannot be read.
  if changes.len == 0:
    return ok()
  let current = ?loadRecords(path, parse)
  var records = initOrderedTable[string, T]()
  for key, value in changes:
    if not drop(value) and records.len < MaxRecordedFiles:
      records[key] = value
  for key in opened:
    if key notin changes and key notin records and key in current and
        records.len < MaxRecordedFiles:
      records[key] = current.getOrDefault(key)
  for key, value in current:
    if key notin changes and key notin records and records.len < MaxRecordedFiles:
      records[key] = value

  let pathStr = path.get.string
  if records.len == 0:
    try:
      if fileExists(pathStr):
        removeFile(pathStr)
    except CatchableError as e:
      return err(fmt"Failed to remove {pathStr}: {e.msg}")
    return ok()

  let dir = pathStr.parentDir
  try:
    createDir(dir)
  except CatchableError as e:
    return err(fmt"Failed to create dir: {e.msg}: {dir}")

  var obj = newJObject()
  for key, value in records:
    obj[key] = emit(value)
  try:
    # `copyFileWithPermissions` in the hardlink path is declared to raise
    # `Exception`; it raises only OS and I/O errors.
    {.cast(raises: [CatchableError]).}:
      let w = writeAtomic(pathStr, $obj, wpForce)
      if w.isErr:
        return err(fmt"{pathStr}: {w.error}")
  except CatchableError as e:
    return err(fmt"{pathStr}: {e.msg}")
  ok()

# Cursor Position Persistence

proc getCursorPositionsPath*(): Result[Path, string] =
  ## Get the path to the cursor positions file
  ## Returns: ~/$XDG_CACHE_HOME/moe/cursor_positions.json
  cacheFilePath("cursor_positions.json")

proc parseCursorPosition(node: JsonNode): Option[CursorPositionEntry] =
  if node.kind != JObject:
    return
  let line = node{"line"}
  let column = node{"column"}
  if line != nil and line.kind == JInt and line.getInt() >= 0 and column != nil and
      column.kind == JInt and column.getInt() >= 0:
    return some(CursorPositionEntry(line: line.getInt(), column: column.getInt()))

proc emitCursorPosition(pos: CursorPositionEntry): JsonNode =
  %*{"line": pos.line, "column": pos.column}

proc neverDrop(pos: CursorPositionEntry): bool =
  false

proc loadCursorPositions*(): Result[Table[string, CursorPositionEntry], string] =
  ## Cursor positions by `pathKey`; empty when there is no file.
  loadRecords(getCursorPositionsPath(), parseCursorPosition).map(toTable)

proc updateCursorPositions*(
    changes: Table[string, CursorPositionEntry], opened: openArray[string] = []
): Result[void, string] =
  ## Merge `changes` into the cursor positions file. `opened` are files this
  ## session opened, kept ahead of older entries.
  updateRecords(
    getCursorPositionsPath(),
    changes,
    opened,
    parseCursorPosition,
    emitCursorPosition,
    neverDrop,
  )

# Bookmark Persistence

proc getBookmarksPath*(): Result[Path, string] =
  ## Get the path to the bookmarks file
  ## Returns: ~/$XDG_CACHE_HOME/moe/bookmarks.json
  cacheFilePath("bookmarks.json")

proc parseBookmarks(node: JsonNode): Option[seq[int]] =
  if node.kind != JArray:
    return
  var lines: seq[int]
  for lineNode in node:
    if lineNode.kind == JInt and lineNode.getInt() >= 0:
      lines.add lineNode.getInt()
  lines.sort()
  lines = lines.deduplicate(isSorted = true)
  if lines.len > 0:
    return some(lines)

proc emitBookmarks(lines: seq[int]): JsonNode =
  %lines

proc noBookmarks(lines: seq[int]): bool =
  lines.len == 0

proc loadBookmarks*(): Result[Table[string, seq[int]], string] =
  ## Bookmarked lines by `pathKey`; empty when there is no file.
  loadRecords(getBookmarksPath(), parseBookmarks).map(toTable)

proc updateBookmarks*(
    changes: Table[string, seq[int]], opened: openArray[string] = []
): Result[void, string] =
  ## Merge `changes` into the bookmarks file. An empty list removes the entry,
  ## and the file goes away with its last entry. `opened` are files this
  ## session opened, kept ahead of older entries.
  updateRecords(
    getBookmarksPath(), changes, opened, parseBookmarks, emitBookmarks, noBookmarks
  )

# Session state

proc lookup[T](
    records: PersistedRecords[T],
    key: string,
    path: Result[Path, string],
    parse: RecordParser[T],
): Result[Option[T], string] =
  ## This session's record for `key`, else the file's as it is now.
  if key in records.changes:
    return ok(some(records.changes[key]))
  let loaded = ?loadRecords(path, parse)
  if key in loaded:
    return ok(some(loaded[key]))
  ok(none(T))

proc lookupCursorPosition*(
    records: PersistedRecords[CursorPositionEntry], key: string
): Result[Option[CursorPositionEntry], string] =
  records.lookup(key, getCursorPositionsPath(), parseCursorPosition)

proc lookupBookmarks*(
    records: PersistedRecords[seq[int]], key: string
): Result[Option[seq[int]], string] =
  records.lookup(key, getBookmarksPath(), parseBookmarks)

proc markRestored*[T](records: var PersistedRecords[T], key: string, value: T) =
  ## Note that the file at `key` was opened with `value`.
  records.restored[key] = value

proc record*[T](records: var PersistedRecords[T], key: string, value: T) =
  ## Record `value` for the next save unless it is what `key` was opened with.
  ## A file never opened counts as opened with the default value.
  if key in records.changes or records.restored.getOrDefault(key) != value:
    records.changes[key] = value
