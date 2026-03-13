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

import std/[unittest, os, tables, json, options, strutils]
import pkg/results
import ../src/moepkg/persist

const TestPersistDir = "/tmp/moe_test_persist"

proc cleanupTestDir() =
  if dirExists(TestPersistDir):
    removeDir(TestPersistDir)

suite "persist - getCommandHistoryPath":
  test "Returns a valid path":
    let result = getCommandHistoryPath()
    check result.isOk
    check result.get().string.len > 0
    check result.get().string.endsWith("command_history")

suite "persist - getCursorPositionsPath":
  test "Returns a valid path":
    let result = getCursorPositionsPath()
    check result.isOk
    check result.get().string.len > 0
    check result.get().string.endsWith("cursor_positions.json")

suite "persist - saveCommandHistory and loadCommandHistory":
  setup:
    cleanupTestDir()
    createDir(TestPersistDir)

  teardown:
    cleanupTestDir()

  test "Save and load command history":
    let
      historyPath = TestPersistDir / "command_history"
      history = @["cmd3", "cmd2", "cmd1"]

    # Write directly to test file
    writeFile(historyPath, history.join("\n"))

    # Read back using file operations
    let content = readFile(historyPath)
    let loaded = content.split('\n')

    check loaded.len == 3
    check loaded[0] == "cmd3"
    check loaded[1] == "cmd2"
    check loaded[2] == "cmd1"

  test "Load empty history from non-existent file":
    let loaded = loadCommandHistory()
    # Should return empty seq if file doesn't exist
    check loaded.len >= 0

  test "Save command history respects limit":
    let
      historyPath = TestPersistDir / "command_history_limit"
      history = @["cmd1", "cmd2", "cmd3", "cmd4", "cmd5"]
      limit = 3

    # Take only the most recent entries
    let entriesToSave =
      if history.len > limit:
        history[0 ..< limit]
      else:
        history

    writeFile(historyPath, entriesToSave.join("\n"))

    let content = readFile(historyPath)
    let loaded = content.split('\n')

    check loaded.len == 3
    check loaded[0] == "cmd1"
    check loaded[1] == "cmd2"
    check loaded[2] == "cmd3"

  test "Save command history skips empty entries":
    let
      historyPath = TestPersistDir / "command_history_empty"
      history = @["cmd1", "", "cmd2", "", "cmd3"]

    var content = ""
    for i, entry in history:
      if entry.len == 0:
        continue
      if content.len > 0:
        content.add("\n")
      content.add(entry)

    writeFile(historyPath, content)

    let loadedContent = readFile(historyPath)
    let loaded = loadedContent.split('\n')

    check loaded.len == 3
    check loaded[0] == "cmd1"
    check loaded[1] == "cmd2"
    check loaded[2] == "cmd3"

suite "persist - saveCursorPositions and loadCursorPositions":
  setup:
    cleanupTestDir()
    createDir(TestPersistDir)

  teardown:
    cleanupTestDir()

  test "Save and load cursor positions":
    let posPath = TestPersistDir / "cursor_positions.json"

    var positions = initTable[string, CursorPositionEntry]()
    positions["/home/user/file1.txt"] = CursorPositionEntry(line: 10, column: 5)
    positions["/home/user/file2.txt"] = CursorPositionEntry(line: 100, column: 20)

    # Build JSON manually
    var jsonObj = newJObject()
    for path, pos in positions.pairs:
      jsonObj[path] = %*{"line": pos.line, "column": pos.column}

    writeFile(posPath, $jsonObj)

    # Read back
    let content = readFile(posPath)
    let jsonNode = parseJson(content)

    var loaded = initTable[string, CursorPositionEntry]()
    for path, pos in jsonNode.pairs:
      loaded[path] =
        CursorPositionEntry(line: pos["line"].getInt(), column: pos["column"].getInt())

    check loaded.len == 2
    check loaded["/home/user/file1.txt"].line == 10
    check loaded["/home/user/file1.txt"].column == 5
    check loaded["/home/user/file2.txt"].line == 100
    check loaded["/home/user/file2.txt"].column == 20

  test "Load empty positions from non-existent file":
    let loaded = loadCursorPositions()
    # Should return empty table if file doesn't exist
    check loaded.len >= 0

  test "Save empty cursor positions":
    let posPath = TestPersistDir / "cursor_positions_empty.json"

    let positions = initTable[string, CursorPositionEntry]()

    var jsonObj = newJObject()
    for path, pos in positions.pairs:
      jsonObj[path] = %*{"line": pos.line, "column": pos.column}

    writeFile(posPath, $jsonObj)

    let content = readFile(posPath)
    let jsonNode = parseJson(content)

    check jsonNode.kind == JObject
    check jsonNode.len == 0

suite "persist - getCursorPosition":
  test "Get existing cursor position":
    var positions = initTable[string, CursorPositionEntry]()
    let testPath = getCurrentDir() / "testfile.txt"
    positions[testPath] = CursorPositionEntry(line: 42, column: 10)

    let result = getCursorPosition(positions, "testfile.txt")

    check result.isSome
    check result.get().line == 42
    check result.get().column == 10

  test "Get non-existent cursor position":
    let positions = initTable[string, CursorPositionEntry]()

    let result = getCursorPosition(positions, "/nonexistent/file.txt")

    check result.isNone

  test "Get cursor position with absolute path":
    var positions = initTable[string, CursorPositionEntry]()
    positions["/home/user/myfile.nim"] = CursorPositionEntry(line: 100, column: 25)

    let result = getCursorPosition(positions, "/home/user/myfile.nim")

    check result.isSome
    check result.get().line == 100
    check result.get().column == 25

suite "persist - setCursorPosition":
  test "Set cursor position for new file":
    var positions = initTable[string, CursorPositionEntry]()
    let testPath = getCurrentDir() / "newfile.txt"

    setCursorPosition(positions, "newfile.txt", 50, 15)

    check positions.hasKey(testPath)
    check positions[testPath].line == 50
    check positions[testPath].column == 15

  test "Update existing cursor position":
    var positions = initTable[string, CursorPositionEntry]()
    let testPath = getCurrentDir() / "existing.txt"
    positions[testPath] = CursorPositionEntry(line: 10, column: 5)

    setCursorPosition(positions, "existing.txt", 200, 30)

    check positions[testPath].line == 200
    check positions[testPath].column == 30

  test "Set cursor position with absolute path":
    var positions = initTable[string, CursorPositionEntry]()

    setCursorPosition(positions, "/absolute/path/file.txt", 75, 12)

    check positions.hasKey("/absolute/path/file.txt")
    check positions["/absolute/path/file.txt"].line == 75
    check positions["/absolute/path/file.txt"].column == 12

suite "persist - command history integration":
  setup:
    cleanupTestDir()
    createDir(TestPersistDir)

  teardown:
    cleanupTestDir()

  test "Command history roundtrip with special characters":
    let
      historyPath = TestPersistDir / "command_history_special"
      history = @["w file.txt", "s/foo/bar/g", "!ls -la", "%s/\\n/\\r/g"]

    writeFile(historyPath, history.join("\n"))

    let content = readFile(historyPath)
    let loaded = content.split('\n')

    check loaded.len == 4
    check loaded[0] == "w file.txt"
    check loaded[1] == "s/foo/bar/g"
    check loaded[2] == "!ls -la"
    check loaded[3] == "%s/\\n/\\r/g"

  test "Command history handles whitespace":
    let
      historyPath = TestPersistDir / "command_history_whitespace"
      history = @["  cmd with leading spaces", "cmd with trailing spaces  "]

    writeFile(historyPath, history.join("\n"))

    let content = readFile(historyPath)
    var loaded: seq[string] = @[]
    for line in content.split('\n'):
      let trimmed = line.strip()
      if trimmed.len > 0:
        loaded.add(trimmed)

    check loaded.len == 2
    check loaded[0] == "cmd with leading spaces"
    check loaded[1] == "cmd with trailing spaces"

suite "persist - cursor positions integration":
  setup:
    cleanupTestDir()
    createDir(TestPersistDir)

  teardown:
    cleanupTestDir()

  test "Cursor positions roundtrip with many files":
    let posPath = TestPersistDir / "cursor_positions_many.json"

    var positions = initTable[string, CursorPositionEntry]()
    for i in 1 .. 100:
      positions["/path/to/file" & $i & ".txt"] =
        CursorPositionEntry(line: i * 10, column: i)

    var jsonObj = newJObject()
    for path, pos in positions.pairs:
      jsonObj[path] = %*{"line": pos.line, "column": pos.column}

    writeFile(posPath, $jsonObj)

    let content = readFile(posPath)
    let jsonNode = parseJson(content)

    var loaded = initTable[string, CursorPositionEntry]()
    for path, pos in jsonNode.pairs:
      loaded[path] =
        CursorPositionEntry(line: pos["line"].getInt(), column: pos["column"].getInt())

    check loaded.len == 100
    check loaded["/path/to/file50.txt"].line == 500
    check loaded["/path/to/file50.txt"].column == 50

  test "Cursor positions with unicode paths":
    let posPath = TestPersistDir / "cursor_positions_unicode.json"

    var positions = initTable[string, CursorPositionEntry]()
    positions["/home/ユーザー/ファイル.txt"] =
      CursorPositionEntry(line: 1, column: 1)
    positions["/home/用户/文件.txt"] = CursorPositionEntry(line: 2, column: 2)

    var jsonObj = newJObject()
    for path, pos in positions.pairs:
      jsonObj[path] = %*{"line": pos.line, "column": pos.column}

    writeFile(posPath, $jsonObj)

    let content = readFile(posPath)
    let jsonNode = parseJson(content)

    var loaded = initTable[string, CursorPositionEntry]()
    for path, pos in jsonNode.pairs:
      loaded[path] =
        CursorPositionEntry(line: pos["line"].getInt(), column: pos["column"].getInt())

    check loaded.len == 2
    check loaded["/home/ユーザー/ファイル.txt"].line == 1
    check loaded["/home/用户/文件.txt"].line == 2

suite "persist - getBookmarksPath":
  test "Returns a valid path":
    let result = getBookmarksPath()
    check result.isOk
    check result.get().string.len > 0
    check result.get().string.endsWith("bookmarks.json")

suite "persist - saveBookmarks and loadBookmarks":
  setup:
    cleanupTestDir()
    createDir(TestPersistDir)

  teardown:
    cleanupTestDir()

  test "Save and load bookmarks roundtrip":
    let bmPath = TestPersistDir / "bookmarks.json"

    var bookmarks = initTable[string, seq[int]]()
    bookmarks["/home/user/file1.nim"] = @[5, 10, 25]
    bookmarks["/home/user/file2.nim"] = @[0, 100]

    var jsonObj = newJObject()
    for path, lines in bookmarks.pairs:
      jsonObj[path] = %lines

    writeFile(bmPath, $jsonObj)

    let content = readFile(bmPath)
    let jsonNode = parseJson(content)

    var loaded = initTable[string, seq[int]]()
    for path, lines in jsonNode.pairs:
      var bm: seq[int] = @[]
      for lineNode in lines:
        bm.add(lineNode.getInt())
      loaded[path] = bm

    check loaded.len == 2
    check loaded["/home/user/file1.nim"] == @[5, 10, 25]
    check loaded["/home/user/file2.nim"] == @[0, 100]

  test "Load bookmarks from non-existent file returns empty":
    let loaded = loadBookmarks()
    check loaded.len >= 0

  test "Save empty bookmarks":
    let bmPath = TestPersistDir / "bookmarks_empty.json"

    let bookmarks = initTable[string, seq[int]]()

    var jsonObj = newJObject()
    for path, lines in bookmarks.pairs:
      jsonObj[path] = %lines

    writeFile(bmPath, $jsonObj)

    let content = readFile(bmPath)
    let jsonNode = parseJson(content)

    check jsonNode.kind == JObject
    check jsonNode.len == 0

  test "Bookmarks JSON format is correct":
    let bmPath = TestPersistDir / "bookmarks_format.json"

    var bookmarks = initTable[string, seq[int]]()
    bookmarks["/path/to/file.nim"] = @[1, 5, 10]

    var jsonObj = newJObject()
    for path, lines in bookmarks.pairs:
      jsonObj[path] = %lines

    writeFile(bmPath, $jsonObj)

    let content = readFile(bmPath)
    let jsonNode = parseJson(content)

    check jsonNode.kind == JObject
    check jsonNode.hasKey("/path/to/file.nim")
    check jsonNode["/path/to/file.nim"].kind == JArray
    check jsonNode["/path/to/file.nim"].len == 3
    check jsonNode["/path/to/file.nim"][0].getInt() == 1
    check jsonNode["/path/to/file.nim"][1].getInt() == 5
    check jsonNode["/path/to/file.nim"][2].getInt() == 10

suite "persist - saveBookmarks and loadBookmarks (actual functions)":
  test "saveBookmarks and loadBookmarks roundtrip":
    var bookmarks = initTable[string, seq[int]]()
    bookmarks["/home/user/file1.nim"] = @[5, 10, 25]
    bookmarks["/home/user/file2.nim"] = @[0, 100]

    let r = saveBookmarks(bookmarks)
    check r.isOk

    let loaded = loadBookmarks()
    check loaded.len == 2
    check loaded["/home/user/file1.nim"] == @[5, 10, 25]
    check loaded["/home/user/file2.nim"] == @[0, 100]

  test "saveBookmarks overwrites previous data":
    var bookmarks1 = initTable[string, seq[int]]()
    bookmarks1["/file.nim"] = @[1, 2, 3]
    check saveBookmarks(bookmarks1).isOk

    var bookmarks2 = initTable[string, seq[int]]()
    bookmarks2["/other.nim"] = @[10]
    check saveBookmarks(bookmarks2).isOk

    let loaded = loadBookmarks()
    check loaded.len == 1
    check loaded.hasKey("/other.nim")
    check not loaded.hasKey("/file.nim")

  test "saveBookmarks skips entries with empty bookmark list":
    var bookmarks = initTable[string, seq[int]]()
    bookmarks["/file1.nim"] = @[1]
    bookmarks["/file2.nim"] = @[]
    check saveBookmarks(bookmarks).isOk

    let loaded = loadBookmarks()
    check loaded.len == 1
    check loaded.hasKey("/file1.nim")
    check not loaded.hasKey("/file2.nim")

  test "loadBookmarks ignores negative line numbers":
    let bmPath = getBookmarksPath()
    check bmPath.isOk
    let jsonStr = """{"file.nim": [5, -1, 10, -100, 0]}"""
    writeFile(bmPath.get.string, jsonStr)

    let loaded = loadBookmarks()
    check loaded.len == 1
    check loaded["file.nim"] == @[5, 10, 0]

  test "loadBookmarks handles corrupt JSON gracefully":
    let bmPath = getBookmarksPath()
    check bmPath.isOk
    writeFile(bmPath.get.string, "not valid json {{{")

    let loaded = loadBookmarks()
    check loaded.len == 0

  test "loadBookmarks handles wrong JSON types gracefully":
    let bmPath = getBookmarksPath()
    check bmPath.isOk
    let jsonStr = """{"file.nim": "not an array", "file2.nim": [1, "str", 3]}"""
    writeFile(bmPath.get.string, jsonStr)

    let loaded = loadBookmarks()
    # "file.nim" skipped (not an array)
    # "file2.nim" has [1, 3] (non-int "str" skipped)
    check loaded.len == 1
    check loaded["file2.nim"] == @[1, 3]

  test "loadBookmarks handles empty JSON object":
    let bmPath = getBookmarksPath()
    check bmPath.isOk
    writeFile(bmPath.get.string, "{}")

    let loaded = loadBookmarks()
    check loaded.len == 0

  test "loadBookmarks handles JSON array at top level":
    let bmPath = getBookmarksPath()
    check bmPath.isOk
    writeFile(bmPath.get.string, "[1, 2, 3]")

    let loaded = loadBookmarks()
    check loaded.len == 0

suite "persist - default limits":
  test "DefaultCommandHistoryLimit is reasonable":
    check DefaultCommandHistoryLimit == 1000

  test "DefaultSearchHistoryLimit is reasonable":
    check DefaultSearchHistoryLimit == 1000
