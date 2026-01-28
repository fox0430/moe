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

import std/[unittest, options, strutils]

import pkg/results

import ../src/moepkg/[buffer, cursor, completion]
import ../src/moepkg/lsp/protocol/types as lspTypes

suite "Completion - extractWords":
  test "Extract words from simple line":
    let words = extractWords("hello world foo")
    check words == @["hello", "world", "foo"]

  test "Extract words with underscores":
    let words = extractWords("my_var another_name")
    check words == @["my_var", "another_name"]

  test "Extract words with numbers":
    let words = extractWords("var1 test123 foo99bar")
    check words == @["var1", "test123", "foo99bar"]

  test "Extract words ignores short words":
    let words = extractWords("a b c hello d")
    check words == @["hello"]

  test "Extract words with punctuation":
    let words = extractWords("hello, world! foo.bar")
    check words == @["hello", "world", "foo", "bar"]

  test "Extract words from empty line":
    let words = extractWords("")
    check words.len == 0

  test "Extract words preserves word at end":
    let words = extractWords("one two three")
    check words == @["one", "two", "three"]

suite "Completion - extractWordAtPosition":
  test "Extract word at start":
    let word = extractWordAtPosition("hello world", 0)
    check word == "hello"

  test "Extract word in middle":
    let word = extractWordAtPosition("hello world", 3)
    check word == "hello"

  test "Extract word at boundary":
    let word = extractWordAtPosition("hello world", 5)
    check word == "hello"

  test "Extract second word":
    let word = extractWordAtPosition("hello world", 7)
    check word == "world"

  test "Extract from empty line":
    let word = extractWordAtPosition("", 0)
    check word == ""

  test "Extract with underscore":
    let word = extractWordAtPosition("my_variable = 5", 5)
    check word == "my_variable"

suite "Completion - extractPrefixBeforeCursor":
  test "Extract prefix at word end":
    let prefix = extractPrefixBeforeCursor("hello world", 5)
    check prefix == "hello"

  test "Extract partial prefix":
    let prefix = extractPrefixBeforeCursor("hello world", 3)
    check prefix == "hel"

  test "Extract prefix after space":
    let prefix = extractPrefixBeforeCursor("hello world", 8)
    check prefix == "wo"

  test "Extract empty prefix at start":
    let prefix = extractPrefixBeforeCursor("hello", 0)
    check prefix == ""

  test "Extract empty prefix after space":
    let prefix = extractPrefixBeforeCursor("hello ", 6)
    check prefix == ""

  test "Extract from empty line":
    let prefix = extractPrefixBeforeCursor("", 0)
    check prefix == ""

suite "Completion - fuzzyMatch":
  test "Exact match":
    check fuzzyMatch("hello", "hello") == true

  test "Prefix match":
    check fuzzyMatch("hel", "hello") == true

  test "Fuzzy match with gaps":
    check fuzzyMatch("hlo", "hello") == true

  test "Case insensitive match":
    check fuzzyMatch("HEL", "hello") == true
    check fuzzyMatch("hel", "HELLO") == true

  test "No match":
    check fuzzyMatch("xyz", "hello") == false

  test "Empty pattern matches everything":
    check fuzzyMatch("", "hello") == true

  test "Empty text matches nothing (except empty pattern)":
    check fuzzyMatch("a", "") == false
    check fuzzyMatch("", "") == true

  test "Pattern longer than text":
    check fuzzyMatch("helloworld", "hello") == false

suite "Completion - matchScore":
  test "Exact prefix match has high score":
    let score = matchScore("hel", "hello")
    check score >= 1000

  test "Case sensitive prefix match has bonus":
    let score1 = matchScore("Hel", "Hello")
    let score2 = matchScore("hel", "Hello")
    check score1 > score2

  test "Fuzzy match has lower score than prefix":
    let prefixScore = matchScore("hel", "hello")
    let fuzzyScore = matchScore("hlo", "hello")
    check prefixScore > fuzzyScore

  test "Empty pattern has zero score":
    let score = matchScore("", "hello")
    check score == 0

  test "No match has zero score":
    let score = matchScore("xyz", "hello")
    check score == 0

  test "Shorter words preferred for prefix match":
    let shortScore = matchScore("he", "he")
    let longScore = matchScore("he", "helicopter")
    check shortScore > longScore

suite "Completion - CompletionManager":
  test "newCompletionManager creates idle manager":
    let mgr = newCompletionManager()
    check mgr.state == csIdle
    check mgr.menu.entries.len == 0
    check mgr.menu.selectedIndex == 0
    check mgr.isActive == false

  test "selectNext cycles through entries":
    let mgr = newCompletionManager()
    mgr.menu.entries =
      @[
        CompletionEntry(word: "apple", matchScore: 100, source: csBuffer),
        CompletionEntry(word: "banana", matchScore: 90, source: csBuffer),
        CompletionEntry(word: "cherry", matchScore: 80, source: csBuffer),
      ]

    check mgr.menu.selectedIndex == 0
    mgr.selectNext()
    check mgr.menu.selectedIndex == 1
    mgr.selectNext()
    check mgr.menu.selectedIndex == 2
    mgr.selectNext()
    check mgr.menu.selectedIndex == 0 # Wrap around

  test "selectPrevious cycles through entries":
    let mgr = newCompletionManager()
    mgr.menu.entries =
      @[
        CompletionEntry(word: "apple", matchScore: 100, source: csBuffer),
        CompletionEntry(word: "banana", matchScore: 90, source: csBuffer),
        CompletionEntry(word: "cherry", matchScore: 80, source: csBuffer),
      ]

    check mgr.menu.selectedIndex == 0
    mgr.selectPrevious()
    check mgr.menu.selectedIndex == 2 # Wrap to end
    mgr.selectPrevious()
    check mgr.menu.selectedIndex == 1
    mgr.selectPrevious()
    check mgr.menu.selectedIndex == 0

  test "getSelectedWord returns correct word":
    let mgr = newCompletionManager()
    mgr.menu.entries =
      @[
        CompletionEntry(word: "apple", matchScore: 100, source: csBuffer),
        CompletionEntry(word: "banana", matchScore: 90, source: csBuffer),
      ]

    check mgr.getSelectedWord() == "apple"
    mgr.selectNext()
    check mgr.getSelectedWord() == "banana"

  test "getSelectedWord returns empty for empty menu":
    let mgr = newCompletionManager()
    check mgr.getSelectedWord() == ""

  test "cancelCompletion resets state":
    let mgr = newCompletionManager()
    mgr.state = csActive
    mgr.menu.entries =
      @[CompletionEntry(word: "test", matchScore: 100, source: csBuffer)]
    mgr.menu.selectedIndex = 5
    mgr.menu.prefix = "tes"

    mgr.cancelCompletion()

    check mgr.state == csIdle
    check mgr.menu.entries.len == 0
    check mgr.menu.selectedIndex == 0
    check mgr.menu.prefix == ""

suite "Completion - collectBufferWords":
  test "Collect words from buffer":
    let buf = newTextBuffer()
    discard
      buf.insertText(BufferPosition(line: 0, column: 0), "hello world\nfoo bar baz")

    # Position at "baz" excludes only "baz"
    let words = collectBufferWords(buf, BufferPosition(line: 1, column: 8))

    check "hello" in words
    check "world" in words
    check "foo" in words
    check "bar" in words
    check "baz" notin words # Excluded (cursor position)

  test "Excludes word at cursor position":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let words = collectBufferWords(buf, BufferPosition(line: 0, column: 3))

    check "hello" notin words # Excluded
    check "world" in words

  test "Returns sorted unique words":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world hello foo")

    let words = collectBufferWords(buf, BufferPosition(line: 0, column: 100))

    check words.len == 3 # hello, world, foo (unique)
    check words[0] == "foo" # Sorted alphabetically
    check words[1] == "hello"
    check words[2] == "world"

suite "Completion - triggerCompletion":
  test "Trigger completion with prefix":
    let mgr = newCompletionManager()
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello hel")

    mgr.triggerCompletion(buf, 0, 9)

    check mgr.state == csActive
    check mgr.menu.prefix == "hel"
    check mgr.menu.entries.len > 0

  test "Trigger completion without matches stays idle":
    let mgr = newCompletionManager()
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "abc def")

    mgr.triggerCompletion(buf, 0, 3)

    # No matches for "abc" against other words
    check mgr.state == csIdle or mgr.menu.entries.len == 0

suite "Completion - calculatePopupPosition":
  test "Popup below cursor":
    let entries = @[CompletionEntry(word: "test", matchScore: 100, source: csBuffer)]
    let pos = calculatePopupPosition(10, 5, 80, 24, entries)

    check pos.y == 6 # Below cursor
    check pos.x == 10

  test "Popup adjusts for right edge":
    let entries = @[CompletionEntry(word: "test", matchScore: 100, source: csBuffer)]
    let pos = calculatePopupPosition(75, 5, 80, 24, entries)

    check pos.x < 75 # Adjusted to fit

  test "Popup goes above if no space below":
    let entries = @[CompletionEntry(word: "test", matchScore: 100, source: csBuffer)]
    let pos = calculatePopupPosition(10, 20, 80, 24, entries)

    check pos.y < 20 # Above cursor

suite "Completion - calculateMaxWordWidth":
  test "Calculate max width":
    let entries =
      @[
        CompletionEntry(word: "short", matchScore: 100, source: csBuffer),
        CompletionEntry(word: "verylongword", matchScore: 90, source: csBuffer),
        CompletionEntry(word: "medium", matchScore: 80, source: csBuffer),
      ]

    let width = calculateMaxWordWidth(entries)
    check width == 12 # "verylongword".len

  test "Empty entries returns zero":
    let entries: seq[CompletionEntry] = @[]
    let width = calculateMaxWordWidth(entries)
    check width == 0

suite "Completion - LSP support":
  test "setLspRequestPending sets state":
    let mgr = newCompletionManager()
    mgr.setLspRequestPending(42)

    check mgr.state == csPendingLsp
    check mgr.isPendingLsp == true
    check mgr.getLspRequestId().get() == 42

  test "setLspItems updates menu":
    let mgr = newCompletionManager()
    mgr.menu.prefix = "tes"
    mgr.state = csPendingLsp

    let items =
      @[
        CompletionItem(label: "test", kind: some(cikFunction)),
        CompletionItem(label: "testing", kind: some(cikVariable)),
      ]
    mgr.setLspItems(items)

    check mgr.state == csActive
    check mgr.menu.entries.len == 2
    check mgr.lspRequestId.isNone

  test "lspItemToEntry converts correctly":
    let item =
      CompletionItem(label: "testFunc", kind: some(cikFunction), detail: some("func()"))

    let entry = lspItemToEntry(item, "test")

    check entry.word == "testFunc"
    check entry.source == csLsp
    check entry.kind.get() == cikFunction
    check entry.detail.get() == "func()"

  test "lspItemToEntry uses insertText if available":
    let item = CompletionItem(
      label: "displayLabel", insertText: some("actualInsert"), kind: some(cikMethod)
    )

    let entry = lspItemToEntry(item, "")

    check entry.word == "actualInsert"

suite "Completion - completionItemKindToString":
  test "Converts common kinds":
    check completionItemKindToString(cikFunction) == "Func"
    check completionItemKindToString(cikVariable) == "Var"
    check completionItemKindToString(cikClass) == "Class"
    check completionItemKindToString(cikMethod) == "Method"
    check completionItemKindToString(cikKeyword) == "Keyw"

suite "Completion - filterAndSortEntries":
  test "Filter buffer words by prefix":
    let mgr = newCompletionManager()
    mgr.allWords = @["hello", "help", "world", "helicopter"]

    let entries = mgr.filterAndSortEntries("hel")

    check entries.len == 3
    # All should start with "hel"
    for e in entries:
      check e.word.toLowerAscii.startsWith("hel")

  test "LSP items take priority over buffer words":
    let mgr = newCompletionManager()
    mgr.allWords = @["hello", "help"]
    mgr.lspItems = @[CompletionItem(label: "lspHelp", kind: some(cikFunction))]

    let entries = mgr.filterAndSortEntries("hel")

    # Should only contain LSP items when available
    check entries.len == 1
    check entries[0].source == csLsp

  test "Empty prefix returns all words":
    let mgr = newCompletionManager()
    mgr.allWords = @["apple", "banana", "cherry"]

    let entries = mgr.filterAndSortEntries("")

    check entries.len == 3

suite "Completion - scroll offset":
  test "selectNext adjusts scroll offset":
    let mgr = newCompletionManager()
    mgr.menu.maxVisible = 3
    mgr.menu.entries =
      @[
        CompletionEntry(word: "a", matchScore: 100, source: csBuffer),
        CompletionEntry(word: "b", matchScore: 90, source: csBuffer),
        CompletionEntry(word: "c", matchScore: 80, source: csBuffer),
        CompletionEntry(word: "d", matchScore: 70, source: csBuffer),
        CompletionEntry(word: "e", matchScore: 60, source: csBuffer),
      ]

    check mgr.menu.scrollOffset == 0
    mgr.selectNext() # index 1
    mgr.selectNext() # index 2
    check mgr.menu.scrollOffset == 0
    mgr.selectNext() # index 3, should scroll
    check mgr.menu.scrollOffset == 1

  test "selectPrevious adjusts scroll offset":
    let mgr = newCompletionManager()
    mgr.menu.maxVisible = 3
    mgr.menu.entries =
      @[
        CompletionEntry(word: "a", matchScore: 100, source: csBuffer),
        CompletionEntry(word: "b", matchScore: 90, source: csBuffer),
        CompletionEntry(word: "c", matchScore: 80, source: csBuffer),
        CompletionEntry(word: "d", matchScore: 70, source: csBuffer),
        CompletionEntry(word: "e", matchScore: 60, source: csBuffer),
      ]
    mgr.menu.selectedIndex = 4
    mgr.menu.scrollOffset = 2

    mgr.selectPrevious() # index 3
    check mgr.menu.scrollOffset == 2
    mgr.selectPrevious() # index 2
    check mgr.menu.scrollOffset == 2
    mgr.selectPrevious() # index 1, should scroll up
    check mgr.menu.scrollOffset == 1
