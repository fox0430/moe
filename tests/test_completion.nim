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

import std/[unittest, options, strutils, monotimes, times, os, json]

import pkg/celina

import ../src/moepkg/[buffer, completion, unicode_utils]
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
    mgr.menu.entries = @[
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
    mgr.menu.entries = @[
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
    mgr.menu.entries = @[
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
    let entries = @[
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

  test "isActive returns true when pending LSP":
    let mgr = newCompletionManager()
    check mgr.isActive == false

    mgr.state = csActive
    check mgr.isActive == true

    mgr.setLspRequestPending(1)
    check mgr.state == csPendingLsp
    check mgr.isActive == true

  test "setLspItems updates menu":
    let mgr = newCompletionManager()
    mgr.menu.prefix = "tes"
    mgr.state = csPendingLsp

    let items = @[
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
    mgr.menu.entries = @[
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
    mgr.menu.entries = @[
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

suite "Completion - calculatePopupPosition with showBorder=false":
  test "No border size added to dimensions":
    let entries = @[CompletionEntry(word: "test", matchScore: 100, source: csBuffer)]
    let withBorder = calculatePopupPosition(10, 5, 80, 24, entries, showBorder = true)
    let noBorder = calculatePopupPosition(10, 5, 80, 24, entries, showBorder = false)

    check noBorder.width == withBorder.width - 2
    check noBorder.height == withBorder.height - 2

  test "Popup below cursor":
    let entries = @[CompletionEntry(word: "test", matchScore: 100, source: csBuffer)]
    let pos = calculatePopupPosition(10, 5, 80, 24, entries, showBorder = false)

    check pos.y == 6 # cursorY + 1
    check pos.x == 10

  test "Popup adjusts for right edge":
    let entries = @[CompletionEntry(word: "test", matchScore: 100, source: csBuffer)]
    let pos = calculatePopupPosition(75, 5, 80, 24, entries, showBorder = false)

    check pos.x + pos.width <= 80

  test "Popup goes above if no space below":
    var entries: seq[CompletionEntry]
    for i in 0 ..< 5:
      entries.add CompletionEntry(word: "word" & $i, matchScore: 100, source: csBuffer)
    let pos = calculatePopupPosition(10, 20, 80, 24, entries, showBorder = false)

    check pos.y < 20

  test "No extra gap between cursor and popup below":
    let entries = @[
      CompletionEntry(word: "hello", matchScore: 100, source: csBuffer),
      CompletionEntry(word: "world", matchScore: 90, source: csBuffer),
    ]
    let bordered = calculatePopupPosition(10, 5, 80, 24, entries, showBorder = true)
    let borderless = calculatePopupPosition(10, 5, 80, 24, entries, showBorder = false)

    # Bordered: popup (border) starts at cursorY+1
    check bordered.y == 6

    # Borderless: content starts at cursorY+1 (same row, no 1-row gap)
    check borderless.y == 6

  test "No extra gap between cursor and popup above":
    var entries: seq[CompletionEntry]
    for i in 0 ..< 10:
      entries.add CompletionEntry(word: "item" & $i, matchScore: 100, source: csBuffer)

    let bordered = calculatePopupPosition(10, 20, 80, 24, entries, showBorder = true)
    let borderless = calculatePopupPosition(10, 20, 80, 24, entries, showBorder = false)

    # Bordered: bottom border sits at cursorY-1
    check bordered.y + bordered.height == 20

    # Borderless: bottom content sits at cursorY-1
    check borderless.y + borderless.height == 20

suite "Completion - renderCompletionPopup":
  test "Renders border and content with showBorder=true":
    let menu = CompletionMenu(
      entries: @[
        CompletionEntry(word: "hello", matchScore: 100, source: csBuffer),
        CompletionEntry(word: "world", matchScore: 90, source: csBuffer),
      ],
      selectedIndex: 0,
      hasSelection: true,
      scrollOffset: 0,
      maxVisible: 10,
    )
    let pos = PopupPosition(x: 2, y: 2, width: 19, height: 4)

    var termBuffer = newBuffer(80, 24)
    renderCompletionPopup(termBuffer, menu, pos, showBorder = true)

    # Check border corners
    check termBuffer[2, 2].symbol == "┌"
    check termBuffer[20, 2].symbol == "┐"
    check termBuffer[2, 5].symbol == "└"
    check termBuffer[20, 5].symbol == "┘"

    # Check side borders
    check termBuffer[2, 3].symbol == "│"
    check termBuffer[20, 3].symbol == "│"
    check termBuffer[2, 4].symbol == "│"
    check termBuffer[20, 4].symbol == "│"

    # Check content is rendered (first char of "hello" at contentX=3, contentY=3)
    check termBuffer[3, 3].symbol == "h"
    check termBuffer[3, 4].symbol == "w"

  test "Renders content without border with showBorder=false":
    let menu = CompletionMenu(
      entries: @[
        CompletionEntry(word: "hello", matchScore: 100, source: csBuffer),
        CompletionEntry(word: "world", matchScore: 90, source: csBuffer),
      ],
      selectedIndex: 0,
      hasSelection: true,
      scrollOffset: 0,
      maxVisible: 10,
    )
    # Borderless: content starts directly at pos.x, pos.y
    let pos = PopupPosition(x: 2, y: 2, width: 17, height: 2)

    var termBuffer = newBuffer(80, 24)
    renderCompletionPopup(termBuffer, menu, pos, showBorder = false)

    # Content at (2,2) directly
    check termBuffer[2, 2].symbol == "h"
    check termBuffer[3, 2].symbol == "e"
    check termBuffer[2, 3].symbol == "w"
    check termBuffer[3, 3].symbol == "o"

    # No border characters
    check termBuffer[1, 1].symbol != "┌"
    check termBuffer[1, 2].symbol != "│"

  test "Selected item highlighted correctly without border":
    let menu = CompletionMenu(
      entries: @[
        CompletionEntry(word: "apple", matchScore: 100, source: csBuffer),
        CompletionEntry(word: "banana", matchScore: 90, source: csBuffer),
      ],
      selectedIndex: 1,
      hasSelection: true,
      scrollOffset: 0,
      maxVisible: 10,
    )
    let pos = PopupPosition(x: 0, y: 0, width: 15, height: 2)

    var termBuffer = newBuffer(80, 24)
    renderCompletionPopup(termBuffer, menu, pos, showBorder = false)

    # First entry: normal style
    check termBuffer[0, 0].style == popupNormalStyle

    # Second entry (selected): selected style
    check termBuffer[0, 1].style == popupSelectedStyle

  test "Does nothing with empty entries":
    let menu =
      CompletionMenu(entries: @[], selectedIndex: 0, scrollOffset: 0, maxVisible: 10)
    let pos = PopupPosition(x: 0, y: 0, width: 10, height: 3)

    var termBuffer = newBuffer(80, 24)

    # Should not crash
    renderCompletionPopup(termBuffer, menu, pos, showBorder = true)
    renderCompletionPopup(termBuffer, menu, pos, showBorder = false)

suite "Completion - popup anchor position":
  ## Tests for the anchor calculation used in editor.nim:
  ##   anchorX = screenCursor.x - displayWidth(menu.prefix)
  ## This ensures the popup stays fixed when cycling through candidates.

  test "Anchor is stable across different word lengths":
    # Simulate: trigger at column 10, prefix "hel"
    # After selecting different candidates, cursor moves but anchor stays at 10.
    let triggerX = 10

    # Cycle 1: selected "hello" (len 5), cursor at 15
    let cursor1 = triggerX + displayWidth("hello")
    let anchor1 = cursor1 - displayWidth("hello")

    # Cycle 2: selected "helicopter" (len 10), cursor at 20
    let cursor2 = triggerX + displayWidth("helicopter")
    let anchor2 = cursor2 - displayWidth("helicopter")

    # Cycle 3: selected "help" (len 4), cursor at 14
    let cursor3 = triggerX + displayWidth("help")
    let anchor3 = cursor3 - displayWidth("help")

    check anchor1 == triggerX
    check anchor2 == triggerX
    check anchor3 == triggerX

  test "Anchor is stable with CJK characters":
    let triggerX = 10

    # "変数" has display width 4 (2 wide chars)
    let word1 = "変数"
    let cursor1 = triggerX + displayWidth(word1)
    let anchor1 = cursor1 - displayWidth(word1)

    # "変数名" has display width 6
    let word2 = "変数名"
    let cursor2 = triggerX + displayWidth(word2)
    let anchor2 = cursor2 - displayWidth(word2)

    check anchor1 == triggerX
    check anchor2 == triggerX

  test "Popup position is constant for different candidates":
    let entries = @[
      CompletionEntry(word: "hello", matchScore: 100, source: csBuffer),
      CompletionEntry(word: "helicopter", matchScore: 90, source: csBuffer),
      CompletionEntry(word: "help", matchScore: 80, source: csBuffer),
    ]
    let triggerX = 10

    # Simulate cycling: each candidate has different length but anchor stays fixed
    for entry in entries:
      let cursorX = triggerX + displayWidth(entry.word)
      let anchorX = cursorX - displayWidth(entry.word)
      let pos = calculatePopupPosition(anchorX, 5, 80, 24, entries)

      check pos.x == triggerX
      check pos.y == 6

suite "Completion - hasSelection reset":
  ## hasSelection must be false when the popup is freshly shown so that
  ## no candidate appears pre-selected.  Previously, re-triggering
  ## completion after a first cycle left hasSelection = true.

  test "triggerCompletion resets hasSelection":
    let mgr = newCompletionManager()
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello hel")

    # First trigger and simulate selection
    mgr.triggerCompletion(buf, 0, 9)
    mgr.menu.hasSelection = true

    # Re-trigger — should start with no selection
    mgr.triggerCompletion(buf, 0, 9)

    check mgr.menu.hasSelection == false

  test "cancelCompletion resets hasSelection":
    let mgr = newCompletionManager()
    mgr.state = csActive
    mgr.menu.entries =
      @[CompletionEntry(word: "test", matchScore: 100, source: csBuffer)]
    mgr.menu.hasSelection = true

    mgr.cancelCompletion()

    check mgr.menu.hasSelection == false

  test "setLspItems resets hasSelection":
    let mgr = newCompletionManager()
    mgr.menu.prefix = "tes"
    mgr.state = csPendingLsp
    mgr.menu.hasSelection = true

    let items = @[
      CompletionItem(label: "test", kind: some(cikFunction)),
      CompletionItem(label: "testing", kind: some(cikVariable)),
    ]
    mgr.setLspItems(items)

    check mgr.menu.hasSelection == false

  test "triggerLspCompletion resets hasSelection":
    let mgr = newCompletionManager()
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello hel")

    mgr.menu.hasSelection = true

    mgr.triggerLspCompletion(buf, 0, 9)

    check mgr.menu.hasSelection == false

  test "Re-trigger after selection cycle starts unselected":
    ## Simulates the full workflow: trigger → select → cancel → re-trigger.
    let mgr = newCompletionManager()
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello help hel")

    # First completion cycle
    mgr.triggerCompletion(buf, 0, 14)
    check mgr.menu.hasSelection == false

    # Simulate Tab press (first press activates selection)
    mgr.menu.hasSelection = true
    mgr.selectNext()

    # Cancel
    mgr.cancelCompletion()
    check mgr.menu.hasSelection == false

    # Second completion cycle — must start unselected
    mgr.triggerCompletion(buf, 0, 14)
    check mgr.menu.hasSelection == false
    check mgr.menu.selectedIndex == 0

suite "Completion - multi-buffer word collection":
  test "collectBufferWords includes words from other buffers":
    let buf1 = newTextBuffer()
    discard buf1.insertText(BufferPosition(line: 0, column: 0), "hello world\n")
    let buf2 = newTextBuffer()
    discard buf2.insertText(BufferPosition(line: 0, column: 0), "foo bar")

    # excludePos on empty line 1 to not exclude any word
    let words = collectBufferWords(buf1, BufferPosition(line: 1, column: 0), @[buf2])
    check "foo" in words
    check "bar" in words
    check "hello" in words
    check "world" in words

  test "collectBufferWords deduplicates across buffers":
    let buf1 = newTextBuffer()
    discard buf1.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let buf2 = newTextBuffer()
    discard buf2.insertText(BufferPosition(line: 0, column: 0), "hello other")

    let words = collectBufferWords(buf1, BufferPosition(line: 0, column: 11), @[buf2])
    var helloCount = 0
    for w in words:
      if w == "hello":
        inc helloCount
    check helloCount == 1

  test "collectBufferWords skips same buffer in otherBuffers":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")

    # Passing the same buffer as both current and other should not duplicate
    let words = collectBufferWords(buf, BufferPosition(line: 0, column: 11), @[buf])
    var helloCount = 0
    for w in words:
      if w == "hello":
        inc helloCount
    check helloCount == 1

  test "triggerCompletion uses otherBuffers":
    let mgr = newCompletionManager()
    let buf1 = newTextBuffer()
    discard buf1.insertText(BufferPosition(line: 0, column: 0), "apple app")
    let buf2 = newTextBuffer()
    discard buf2.insertText(BufferPosition(line: 0, column: 0), "application approve")

    mgr.otherBuffers = @[buf2]
    mgr.triggerCompletion(buf1, 0, 9) # prefix = "app"

    # Should have candidates from both buffers
    var foundApplication = false
    var foundApprove = false
    var foundApple = false
    for entry in mgr.menu.entries:
      if entry.word == "application":
        foundApplication = true
      if entry.word == "approve":
        foundApprove = true
      if entry.word == "apple":
        foundApple = true
    check foundApplication
    check foundApprove
    check foundApple

  test "triggerLspCompletion uses otherBuffers":
    let mgr = newCompletionManager()
    let buf1 = newTextBuffer()
    discard buf1.insertText(BufferPosition(line: 0, column: 0), "alpha alp")
    let buf2 = newTextBuffer()
    discard buf2.insertText(BufferPosition(line: 0, column: 0), "alpine alphabet")

    mgr.otherBuffers = @[buf2]
    mgr.triggerLspCompletion(buf1, 0, 9) # prefix = "alp"

    var foundAlpine = false
    var foundAlphabet = false
    var foundAlpha = false
    for entry in mgr.menu.entries:
      if entry.word == "alpine":
        foundAlpine = true
      if entry.word == "alphabet":
        foundAlphabet = true
      if entry.word == "alpha":
        foundAlpha = true
    check foundAlpine
    check foundAlphabet
    check foundAlpha

suite "Completion - extractPathPrefixBeforeCursor":
  test "Absolute path":
    check extractPathPrefixBeforeCursor("/usr/lo", 7) == "/usr/lo"

  test "Relative path":
    check extractPathPrefixBeforeCursor("x ./src/m", 9) == "./src/m"

  test "No path (plain word)":
    check extractPathPrefixBeforeCursor("hello", 5) == ""

  test "Just slash":
    check extractPathPrefixBeforeCursor("/", 1) == "/"

  test "Dot-slash":
    check extractPathPrefixBeforeCursor("./", 2) == "./"

  test "Home-relative":
    check extractPathPrefixBeforeCursor("~/doc", 5) == "~/doc"

  test "Path after space":
    check extractPathPrefixBeforeCursor("include /etc/pa", 15) == "/etc/pa"

  test "Parent dir":
    check extractPathPrefixBeforeCursor("../foo", 6) == "../foo"

  test "Empty line":
    check extractPathPrefixBeforeCursor("", 0) == ""

  test "Col at 0":
    check extractPathPrefixBeforeCursor("/usr", 0) == ""

  test "No slash - just dots":
    check extractPathPrefixBeforeCursor("foo.bar", 7) == ""

suite "Completion - isPathChar":
  test "Slash is path char":
    check isPathChar('/'.Rune)

  test "Dot is path char":
    check isPathChar('.'.Rune)

  test "Tilde is path char":
    check isPathChar('~'.Rune)

  test "Dash is path char":
    check isPathChar('-'.Rune)

  test "Underscore is path char":
    check isPathChar('_'.Rune)

  test "Alpha is path char":
    check isPathChar('a'.Rune)

  test "Space is not path char":
    check not isPathChar(' '.Rune)

  test "Colon is not path char":
    check not isPathChar(':'.Rune)

suite "Completion - calculateMaxDetailWidth":
  test "Returns max detail width":
    let entries = @[
      CompletionEntry(word: "foo", matchScore: 100, source: csLsp, detail: some("int")),
      CompletionEntry(
        word: "bar", matchScore: 90, source: csLsp, detail: some("string")
      ),
    ]
    check calculateMaxDetailWidth(entries) == 6 # "string".len

  test "Returns zero when no detail":
    let entries = @[
      CompletionEntry(word: "foo", matchScore: 100, source: csBuffer),
      CompletionEntry(word: "bar", matchScore: 90, source: csBuffer),
    ]
    check calculateMaxDetailWidth(entries) == 0

  test "Ignores entries without detail":
    let entries = @[
      CompletionEntry(word: "foo", matchScore: 100, source: csBuffer),
      CompletionEntry(word: "bar", matchScore: 90, source: csLsp, detail: some("i32")),
    ]
    check calculateMaxDetailWidth(entries) == 3

suite "Completion - calculatePopupPosition with detail":
  test "Width includes detail column":
    let entries = @[
      CompletionEntry(
        word: "test", matchScore: 100, source: csLsp, detail: some("fn() -> bool")
      )
    ]
    let pos = calculatePopupPosition(0, 0, 80, 24, entries)

    # Without detail: contentWidth = max(15, min(4+2, 80)) = 15, popupWidth = 17
    # With detail: contentWidth = max(15, min(4+12+2+2, 80)) = 20, popupWidth = 22
    let posNoDetail = calculatePopupPosition(
      0, 0, 80, 24, @[CompletionEntry(word: "test", matchScore: 100, source: csBuffer)]
    )
    check pos.width > posNoDetail.width

suite "Completion - renderCompletionPopup with detail":
  test "Detail is rendered after word":
    let menu = CompletionMenu(
      entries: @[
        CompletionEntry(
          word: "hello", matchScore: 100, source: csLsp, detail: some("fn()")
        )
      ],
      selectedIndex: 0,
      hasSelection: false,
      scrollOffset: 0,
      maxVisible: 10,
    )
    # Use explicit PopupPosition to avoid y offset from calculatePopupPosition
    let pos = PopupPosition(x: 0, y: 0, width: 15, height: 1)

    var termBuffer = newBuffer(80, 24)
    renderCompletionPopup(termBuffer, menu, pos, showBorder = false)

    # Word starts at x=0
    check termBuffer[0, 0].symbol == "h"
    check termBuffer[1, 0].symbol == "e"

    # Detail "fn()" should appear after word + separator gap
    # maxWordWidth=5, DetailSeparatorWidth=2, so detail starts at x=7
    check termBuffer[7, 0].symbol == "f"
    check termBuffer[8, 0].symbol == "n"
    check termBuffer[9, 0].symbol == "("
    check termBuffer[10, 0].symbol == ")"

  test "Detail uses dim style":
    let menu = CompletionMenu(
      entries: @[
        CompletionEntry(
          word: "foo", matchScore: 100, source: csLsp, detail: some("int")
        )
      ],
      selectedIndex: 0,
      hasSelection: false,
      scrollOffset: 0,
      maxVisible: 10,
    )
    let pos = PopupPosition(x: 0, y: 0, width: 15, height: 1)

    var termBuffer = newBuffer(80, 24)
    renderCompletionPopup(termBuffer, menu, pos, showBorder = false)

    # Detail starts at x = maxWordWidth(3) + DetailSeparatorWidth(2) = 5
    check termBuffer[5, 0].style == popupDetailStyle

  test "Selected item detail uses selected detail style":
    let menu = CompletionMenu(
      entries: @[
        CompletionEntry(
          word: "foo", matchScore: 100, source: csLsp, detail: some("int")
        )
      ],
      selectedIndex: 0,
      hasSelection: true,
      scrollOffset: 0,
      maxVisible: 10,
    )
    let pos = PopupPosition(x: 0, y: 0, width: 15, height: 1)

    var termBuffer = newBuffer(80, 24)
    renderCompletionPopup(termBuffer, menu, pos, showBorder = false)

    # Detail starts at x=5
    check termBuffer[5, 0].style == popupSelectedDetailStyle

  test "Entry without detail renders normally":
    let menu = CompletionMenu(
      entries: @[
        CompletionEntry(
          word: "hello", matchScore: 100, source: csLsp, detail: some("fn()")
        ),
        CompletionEntry(word: "world", matchScore: 90, source: csBuffer),
      ],
      selectedIndex: 0,
      hasSelection: false,
      scrollOffset: 0,
      maxVisible: 10,
    )
    let pos = PopupPosition(x: 0, y: 0, width: 15, height: 2)

    var termBuffer = newBuffer(80, 24)
    renderCompletionPopup(termBuffer, menu, pos, showBorder = false)

    # Second entry "world" at y=1 should render word normally
    check termBuffer[0, 1].symbol == "w"
    check termBuffer[1, 1].symbol == "o"

suite "Completion - shouldSkipLspRequest":
  test "Skip when prefix extends previous complete result":
    let mgr = newCompletionManager()
    mgr.isIncomplete = false
    mgr.lastLspPrefix = "te"
    mgr.lspItems = @[CompletionItem(label: "test")]
    # Set time far in the past so debounce doesn't trigger
    mgr.lastLspRequestTime = getMonoTime() - initDuration(seconds = 10)

    check mgr.shouldSkipLspRequest("tes") == true
    check mgr.shouldSkipLspRequest("test") == true

  test "Do not skip when result was incomplete":
    let mgr = newCompletionManager()
    mgr.isIncomplete = true
    mgr.lastLspPrefix = "te"
    mgr.lspItems = @[CompletionItem(label: "test")]
    mgr.lastLspRequestTime = getMonoTime() - initDuration(seconds = 10)

    check mgr.shouldSkipLspRequest("tes") == false

  test "Do not skip when prefix does not extend previous":
    let mgr = newCompletionManager()
    mgr.isIncomplete = false
    mgr.lastLspPrefix = "te"
    mgr.lspItems = @[CompletionItem(label: "test")]
    mgr.lastLspRequestTime = getMonoTime() - initDuration(seconds = 10)

    check mgr.shouldSkipLspRequest("fo") == false

  test "Skip when within debounce interval":
    let mgr = newCompletionManager()
    mgr.lastLspRequestTime = getMonoTime()

    check mgr.shouldSkipLspRequest("foo") == true

  test "Do not skip when debounce interval has passed and no prior items":
    let mgr = newCompletionManager()
    mgr.lastLspRequestTime = getMonoTime() - initDuration(seconds = 10)

    check mgr.shouldSkipLspRequest("foo") == false

suite "Completion - setLspItems with isIncomplete":
  test "setLspItems stores isIncomplete flag":
    let mgr = newCompletionManager()
    mgr.menu.prefix = "te"
    mgr.state = csPendingLsp

    let items = @[CompletionItem(label: "test")]
    mgr.setLspItems(items, isIncomplete = true)

    check mgr.isIncomplete == true
    check mgr.state == csActive

  test "setLspItems defaults isIncomplete to false":
    let mgr = newCompletionManager()
    mgr.menu.prefix = "te"
    mgr.state = csPendingLsp

    let items = @[CompletionItem(label: "test")]
    mgr.setLspItems(items)

    check mgr.isIncomplete == false

suite "Completion - lspItemToEntry with textEdit":
  test "Parses standard TextEdit":
    let item = CompletionItem(
      label: "testFunc",
      kind: some(cikFunction),
      textEdit: some(
        %*{
          "range":
            {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 4}},
          "newText": "testFunc",
        }
      ),
    )
    let entry = lspItemToEntry(item, "test")
    check entry.textEdit.isSome
    check entry.textEdit.get.newText == "testFunc"
    check entry.textEdit.get.range.start.line == 0
    check entry.textEdit.get.range.start.character == 0
    check entry.textEdit.get.range.`end`.character == 4

  test "Parses InsertReplaceEdit using replace range":
    let item = CompletionItem(
      label: "hello",
      textEdit: some(
        %*{
          "insert":
            {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 2}},
          "replace":
            {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 5}},
          "newText": "hello",
        }
      ),
    )
    let entry = lspItemToEntry(item, "he")
    check entry.textEdit.isSome
    check entry.textEdit.get.range.`end`.character == 5
    check entry.textEdit.get.newText == "hello"

  test "No textEdit when not provided":
    let item = CompletionItem(label: "simple")
    let entry = lspItemToEntry(item, "si")
    check entry.textEdit.isNone

  test "Parses additionalTextEdits":
    let item = CompletionItem(
      label: "MyClass",
      additionalTextEdits: some(
        @[
          TextEdit(
            range: Range(
              start: lspTypes.Position(line: 0, character: 0),
              `end`: lspTypes.Position(line: 0, character: 0),
            ),
            newText: "import MyModule\n",
          )
        ]
      ),
    )
    let entry = lspItemToEntry(item, "My")
    check entry.additionalTextEdits.isSome
    check entry.additionalTextEdits.get.len == 1
    check entry.additionalTextEdits.get[0].newText == "import MyModule\n"

suite "Completion - getSelectedEntry":
  test "Returns selected entry":
    let mgr = newCompletionManager()
    mgr.menu.entries = @[
      CompletionEntry(word: "foo", matchScore: 100, source: csBuffer),
      CompletionEntry(word: "bar", matchScore: 90, source: csBuffer),
    ]
    mgr.menu.selectedIndex = 1
    let entry = mgr.getSelectedEntry()
    check entry.isSome
    check entry.get.word == "bar"

  test "Returns none when no entries":
    let mgr = newCompletionManager()
    check mgr.getSelectedEntry().isNone

suite "Completion - resolve support":
  test "needsResolve returns true when detail is missing":
    let mgr = newCompletionManager()
    mgr.menu.entries = @[CompletionEntry(word: "test", matchScore: 100, source: csLsp)]
    mgr.menu.selectedIndex = 0
    mgr.menu.hasSelection = true
    check mgr.needsResolve() == true

  test "needsResolve returns false when detail and doc present":
    let mgr = newCompletionManager()
    mgr.menu.entries = @[
      CompletionEntry(
        word: "test",
        matchScore: 100,
        source: csLsp,
        detail: some("int"),
        documentation: some("A test"),
      )
    ]
    mgr.menu.selectedIndex = 0
    mgr.menu.hasSelection = true
    check mgr.needsResolve() == false

  test "needsResolve returns false for buffer entries":
    let mgr = newCompletionManager()
    mgr.menu.entries =
      @[CompletionEntry(word: "test", matchScore: 100, source: csBuffer)]
    mgr.menu.selectedIndex = 0
    mgr.menu.hasSelection = true
    check mgr.needsResolve() == false

  test "needsResolve returns false without selection":
    let mgr = newCompletionManager()
    mgr.menu.entries = @[CompletionEntry(word: "test", matchScore: 100, source: csLsp)]
    mgr.menu.hasSelection = false
    check mgr.needsResolve() == false

  test "getSelectedRawJson returns matching JSON":
    let mgr = newCompletionManager()
    mgr.lspItems = @[CompletionItem(label: "foo"), CompletionItem(label: "bar")]
    mgr.lspRawJsonItems =
      @[%*{"label": "foo", "data": 1}, %*{"label": "bar", "data": 2}]
    mgr.menu.entries = @[
      CompletionEntry(word: "foo", matchScore: 100, source: csLsp),
      CompletionEntry(word: "bar", matchScore: 90, source: csLsp),
    ]
    mgr.menu.selectedIndex = 1
    mgr.menu.hasSelection = true
    let rawJson = mgr.getSelectedRawJson()
    check rawJson.isSome
    check rawJson.get["label"].getStr == "bar"
    check rawJson.get["data"].getInt == 2

  test "updateResolvedEntry updates detail and documentation":
    let mgr = newCompletionManager()
    mgr.menu.entries = @[CompletionEntry(word: "test", matchScore: 100, source: csLsp)]
    mgr.resolvedIndex = 0

    let resolved = CompletionItem(
      label: "test",
      detail: some("fn() -> int"),
      documentation: some(%*"Documentation text"),
    )
    mgr.updateResolvedEntry(resolved)

    check mgr.menu.entries[0].detail == some("fn() -> int")
    check mgr.menu.entries[0].documentation == some("Documentation text")

  test "setLspItems stores raw JSON items":
    let mgr = newCompletionManager()
    mgr.menu.prefix = "te"
    mgr.state = csPendingLsp

    let items = @[CompletionItem(label: "test")]
    let rawJson = @[%*{"label": "test", "data": 42}]
    mgr.setLspItems(items, rawJson)

    check mgr.lspRawJsonItems.len == 1
    check mgr.lspRawJsonItems[0]["data"].getInt == 42
