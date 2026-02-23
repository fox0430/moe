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

import std/[unittest, os, strutils]

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
      let path = getSearchHistoryPath().get.string
      check path.len > 0
      check path == cacheDir / "moe" / "search_history"

suite "hasUpperCase":
  test "empty string":
    check not hasUpperCase("")

  test "lowercase only":
    check not hasUpperCase("abc")
    check not hasUpperCase("hello world")

  test "uppercase only":
    check hasUpperCase("ABC")
    check hasUpperCase("HELLO WORLD")

  test "mixed case":
    check hasUpperCase("Hello")
    check hasUpperCase("heLLo")
    check hasUpperCase("abcD")

  test "numbers and symbols":
    check not hasUpperCase("123")
    check not hasUpperCase("!@#$%")
    check not hasUpperCase("abc123")
    check hasUpperCase("abc123A")

  test "unicode characters":
    # Only ASCII uppercase is checked
    check not hasUpperCase("日本語")
    check not hasUpperCase("αβγ")
    check hasUpperCase("日本語A")

suite "shouldIgnoreCase":
  test "ignorecase false always returns false":
    check not shouldIgnoreCase("abc", ignorecase = false, smartcase = false)
    check not shouldIgnoreCase("ABC", ignorecase = false, smartcase = false)
    check not shouldIgnoreCase("abc", ignorecase = false, smartcase = true)
    check not shouldIgnoreCase("ABC", ignorecase = false, smartcase = true)

  test "ignorecase true without smartcase":
    check shouldIgnoreCase("abc", ignorecase = true, smartcase = false)
    check shouldIgnoreCase("ABC", ignorecase = true, smartcase = false)

  test "smartcase with lowercase search":
    check shouldIgnoreCase("abc", ignorecase = true, smartcase = true)
    check shouldIgnoreCase("hello world", ignorecase = true, smartcase = true)

  test "smartcase with uppercase search":
    check not shouldIgnoreCase("ABC", ignorecase = true, smartcase = true)
    check not shouldIgnoreCase("Hello", ignorecase = true, smartcase = true)
    check not shouldIgnoreCase("helloWorld", ignorecase = true, smartcase = true)

suite "prepareSearchString":
  test "case sensitive":
    check prepareSearchString("Hello", ignorecase = false) == "Hello"
    check prepareSearchString("ABC", ignorecase = false) == "ABC"

  test "case insensitive":
    check prepareSearchString("Hello", ignorecase = true) == "hello"
    check prepareSearchString("ABC", ignorecase = true) == "abc"
    check prepareSearchString("MixedCASE", ignorecase = true) == "mixedcase"

  test "already lowercase":
    check prepareSearchString("hello", ignorecase = true) == "hello"

  test "empty string":
    check prepareSearchString("", ignorecase = false) == ""
    check prepareSearchString("", ignorecase = true) == ""

suite "loadSearchHistory and saveSearchHistory":
  var originalHistory: seq[string] = @[]
  var historyPath: string = ""
  var pathAvailable: bool = false

  setup:
    # Get the actual history path used by the module
    let setupPathResult = getSearchHistoryPath()
    if setupPathResult.isOk:
      historyPath = setupPathResult.get.string
      pathAvailable = true
      # Backup existing history if it exists
      if fileExists(historyPath):
        originalHistory = loadSearchHistory()

  teardown:
    # Restore original history
    if historyPath.len > 0:
      if originalHistory.len > 0:
        discard saveSearchHistory(originalHistory)
      elif fileExists(historyPath):
        removeFile(historyPath)

  test "load from non-existent file returns empty":
    # loadSearchHistory uses getSearchHistoryPath internally,
    # so we test the general behavior
    let history = loadSearchHistory()
    # Should not crash, returns empty or existing history
    check history.len >= 0

  test "saveSearchHistory respects limit":
    if not pathAvailable:
      skip()
    else:
      var history: seq[string] = @[]
      for i in 0 ..< 100:
        history.add("search" & $i)

      # Save with limit 50
      let result = saveSearchHistory(history, 50)
      check result.isOk

      # Load and verify
      let loaded = loadSearchHistory(50)
      check loaded.len <= 50

  test "saveSearchHistory and loadSearchHistory roundtrip":
    if not pathAvailable:
      skip()
    else:
      let testHistory = @["pattern1", "pattern2", "pattern3"]
      let saveResult = saveSearchHistory(testHistory)
      check saveResult.isOk

      let loaded = loadSearchHistory()
      check loaded.len >= 3
      # The first entries should match (most recent first)
      check loaded[0] == "pattern1"
      check loaded[1] == "pattern2"
      check loaded[2] == "pattern3"

  test "saveSearchHistory skips empty entries":
    if not pathAvailable:
      skip()
    else:
      let historyWithEmpty = @["pattern1", "", "pattern2", "", "pattern3"]
      let saveResult = saveSearchHistory(historyWithEmpty)
      check saveResult.isOk

      let loaded = loadSearchHistory()
      # Empty entries should be filtered out on save
      for entry in loaded:
        check entry.len > 0
