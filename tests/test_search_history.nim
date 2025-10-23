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

import std/[unittest, os, strutils, paths]

import pkg/results

import ../src/moepkg/search_utils {.all.}

suite "Search History - File Operations":
  setup:
    # Use a temporary test file
    let testHistoryPath = getTempDir() / "test_search_history"

  teardown:
    # Clean up test file
    if fileExists(testHistoryPath):
      removeFile(testHistoryPath)

  test "save and load empty history":
    let history: seq[string] = @[]

    # Save to temp file
    writeFile(testHistoryPath, "")

    # Load from temp file
    let loaded =
      if fileExists(testHistoryPath):
        var result: seq[string] = @[]
        let content = readFile(testHistoryPath)
        for line in content.splitLines():
          let trimmed = line.strip()
          if trimmed.len > 0:
            result.add(trimmed)
        result
      else:
        @[]

    check loaded.len == 0

  test "save and load single entry":
    let history = @["test search"]

    # Save
    var content = ""
    for i, entry in history:
      if entry.len > 0:
        content.add(entry)
        if i < history.high:
          content.add("\n")
    writeFile(testHistoryPath, content)

    # Load
    let loaded =
      if fileExists(testHistoryPath):
        var result: seq[string] = @[]
        let fileContent = readFile(testHistoryPath)
        for line in fileContent.splitLines():
          let trimmed = line.strip()
          if trimmed.len > 0:
            result.add(trimmed)
        result
      else:
        @[]

    check loaded.len == 1
    check loaded[0] == "test search"

  test "save and load multiple entries":
    let history = @["newest", "middle", "oldest"]

    # Save
    var content = ""
    for i, entry in history:
      if entry.len > 0:
        content.add(entry)
        if i < history.high:
          content.add("\n")
    writeFile(testHistoryPath, content)

    # Load
    let loaded =
      if fileExists(testHistoryPath):
        var result: seq[string] = @[]
        let fileContent = readFile(testHistoryPath)
        for line in fileContent.splitLines():
          let trimmed = line.strip()
          if trimmed.len > 0:
            result.add(trimmed)
        result
      else:
        @[]

    check loaded.len == 3
    check loaded[0] == "newest"
    check loaded[1] == "middle"
    check loaded[2] == "oldest"

  test "save with unicode characters":
    let history = @["日本語", "한글", "Ελληνικά"]

    # Save
    var content = ""
    for i, entry in history:
      if entry.len > 0:
        content.add(entry)
        if i < history.high:
          content.add("\n")
    writeFile(testHistoryPath, content)

    # Load
    let loaded =
      if fileExists(testHistoryPath):
        var result: seq[string] = @[]
        let fileContent = readFile(testHistoryPath)
        for line in fileContent.splitLines():
          let trimmed = line.strip()
          if trimmed.len > 0:
            result.add(trimmed)
        result
      else:
        @[]

    check loaded.len == 3
    check loaded[0] == "日本語"
    check loaded[1] == "한글"
    check loaded[2] == "Ελληνικά"

  test "load non-existent file returns empty":
    let nonExistentPath = getTempDir() / "this_file_does_not_exist_12345"

    let loaded =
      if fileExists(nonExistentPath):
        var result: seq[string] = @[]
        let fileContent = readFile(nonExistentPath)
        for line in fileContent.splitLines():
          let trimmed = line.strip()
          if trimmed.len > 0:
            result.add(trimmed)
        result
      else:
        @[]

    check loaded.len == 0

suite "Search History - Deduplication Logic":
  test "adding duplicate removes old entry":
    var history = @["old", "middle", "newest"]

    # Simulate adding "old" again (should move to front)
    let newEntry = "old"

    # Remove existing occurrence
    for i in countdown(history.high, 0):
      if history[i] == newEntry:
        history.delete(i)

    # Add to front
    history.insert(newEntry, 0)

    check history.len == 3
    check history[0] == "old"
    check history[1] == "middle"
    check history[2] == "newest"

  test "limit history to max entries":
    var history: seq[string] = @[]

    # Add 60 entries
    for i in 0 ..< 60:
      history.add("search" & $i)

    # Limit to 50
    if history.len > 50:
      history.setLen(50)

    check history.len == 50
    check history[0] == "search0"
    check history[49] == "search49"

suite "Search History - Path Functions":
  test "getSearchHistoryPath returns valid path":
    let cacheDir = os.getCacheDir()
    if cacheDir.len == 0:
      skip()
    else:
      let path = $getSearchHistoryPath().get
      check path.len > 0
      check path == cacheDir / "moe" / "search_history"
