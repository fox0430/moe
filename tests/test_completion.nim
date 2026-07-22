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

import std/[unittest, options, strutils, monotimes, times, json, os]

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

  test "Returns unique words":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world hello foo")

    let words = collectBufferWords(buf, BufferPosition(line: 0, column: 100))

    # Deduplicated; order is unspecified (callers rank by match score).
    check words.len == 3
    check "hello" in words
    check "world" in words
    check "foo" in words

suite "Completion - word cache invalidation":
  # The buffer-word scan is cached against each source buffer's monotonic
  # contentVersion. These guard the cases a changeSeq-based key would miss:
  # undo+re-edit and reload both reuse old changeSeq values for new content.

  test "Empty-prefix completion lists words alphabetically":
    let mgr = newCompletionManager()
    let buf = newTextBuffer()
    discard
      buf.insertText(BufferPosition(line: 0, column: 0), "delta alpha charlie bravo\n")

    # Cursor on the empty trailing line -> empty prefix -> every word offered.
    mgr.triggerCompletion(buf, 1, 0)

    check mgr.menu.prefix == ""
    var words: seq[string] = @[]
    for e in mgr.menu.entries:
      words.add(e.word)
    check words == @["alpha", "bravo", "charlie", "delta"]

  test "Undo then a new edit does not serve stale cached words":
    let mgr = newCompletionManager()
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "alpha\n")

    mgr.triggerCompletion(buf, 1, 0)
    check "alpha" in mgr.allWords
    let cachedSeq = buf.changeSeq

    # Roll the edit back, then make a different edit. insertText of an equal-shape
    # string from the same start lands changeSeq on the cached value (the ABA a
    # changeSeq key cannot tell apart); contentVersion still advances.
    discard buf.undo(100)
    discard buf.insertText(BufferPosition(line: 0, column: 0), "gamma\n")
    check buf.changeSeq == cachedSeq # same changeSeq, different content

    mgr.triggerCompletion(buf, 1, 0)
    check "gamma" in mgr.allWords
    check "alpha" notin mgr.allWords

  test "Reloading a file does not serve stale cached words":
    let mgr = newCompletionManager()
    let path = getTempDir() / "moe_test_completion_reload.txt"
    writeFile(path, "alpha beta\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    check buf.loadFile(path).isOk
    let seqAfterLoad = buf.changeSeq
    mgr.triggerCompletion(buf, 1, 0)
    check "alpha" in mgr.allWords

    # Replace the file and reload into the SAME buffer: loadFile resets changeSeq
    # back to its post-load value, so a changeSeq key would collide.
    writeFile(path, "gamma delta\n")
    check buf.reloadFile().isOk
    check buf.changeSeq == seqAfterLoad # both loads reset changeSeq identically

    mgr.triggerCompletion(buf, 1, 0)
    check "gamma" in mgr.allWords
    check "alpha" notin mgr.allWords

  test "Editing an other-buffer is reflected on the next trigger":
    let mgr = newCompletionManager()
    let active = newTextBuffer()
    discard active.insertText(BufferPosition(line: 0, column: 0), "mainword\n")
    let other = newTextBuffer()
    discard other.insertText(BufferPosition(line: 0, column: 0), "firstother")
    mgr.otherBuffers = @[other]

    mgr.triggerCompletion(active, 1, 0)
    check "firstother" in mgr.allWords
    check "secondother" notin mgr.allWords

    discard other.insertText(BufferPosition(line: 0, column: 10), " secondother")
    mgr.triggerCompletion(active, 1, 0)
    check "secondother" in mgr.allWords

  test "Same buffer in two windows is scanned once":
    let mgr = newCompletionManager()
    let active = newTextBuffer()
    discard active.insertText(BufferPosition(line: 0, column: 0), "mainword\n")
    let other = newTextBuffer()
    discard other.insertText(BufferPosition(line: 0, column: 0), "otherword")
    # The same buffer object listed twice (split windows) must not break the scan.
    mgr.otherBuffers = @[other, other]

    mgr.triggerCompletion(active, 1, 0)
    check "otherword" in mgr.allWords
    check "mainword" in mgr.allWords

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

  test "Grown bottom reserve flips the popup above the cursor":
    let entries = @[CompletionEntry(word: "test", matchScore: 100, source: csBuffer)]
    # Cursor at y=15: fits below with the steady reserve (2) ...
    let steady = calculatePopupPosition(10, 15, 80, 24, entries)
    check steady.y == 16
    # ... but a grown bottom area (e.g. 5-line message + status + padding)
    # leaves no room below, so the popup must flip above the cursor
    let grown = calculatePopupPosition(10, 15, 80, 24, entries, bottomReserve = 7)
    check grown.y < 15

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

  test "lspItemToEntry strips the leading space clangd pads onto labels":
    # clangd indents labels with a leading space to align an absent return type.
    # The popup must not show that indent; interior spaces are preserved.
    let item = CompletionItem(
      label: " replace(int first, int second)",
      insertText: some("replace(${1:int first}, ${2:int second})"),
      insertTextFormat: some(InsertTextFormat.itfSnippet),
    )

    let entry = lspItemToEntry(item, "rep")

    check entry.label == "replace(int first, int second)"
    check entry.displayText == "replace(int first, int second)"
    # filterText/sortText fall back to the trimmed label here (item has none).
    check entry.filterText == "replace(int first, int second)"

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

  test "Within a tier the LSP item leads; buffer words merge in below":
    let mgr = newCompletionManager()
    # All three are prefix matches for "hel" (same tier), so the LSP item leads
    # and the buffer words follow (merged, not replaced).
    mgr.allWords = @["hello", "help"]
    mgr.lspItems = @[CompletionItem(label: "helper", kind: some(cikFunction))]

    let entries = mgr.filterAndSortEntries("hel")

    check entries.len == 3
    check entries[0].source == csLsp
    check entries[0].word == "helper"
    var bufferWords: seq[string]
    for e in entries[1 .. ^1]:
      check e.source == csBuffer
      bufferWords.add(e.word)
    check "hello" in bufferWords
    check "help" in bufferWords

  test "A prefix-matching buffer word outranks a fuzzy-only LSP item":
    let mgr = newCompletionManager()
    # Regression for the "i" → tokenizer-above-if/in report: "if" is an exact
    # prefix match for "i" (a keyword/buffer word); "tokenizer" only fuzzy-matches
    # ("i" is the 6th letter). Prefix matches must rank above fuzzy ones even
    # though the fuzzy one is the (normally higher-priority) LSP item.
    mgr.allWords = @["if", "in"]
    mgr.lspItems = @[CompletionItem(label: "tokenizer", kind: some(cikFunction))]

    let entries = mgr.filterAndSortEntries("i")

    # "if" and "in" (prefix matches) come before "tokenizer" (fuzzy only)
    let words = block:
      var acc: seq[string]
      for e in entries:
        acc.add(e.word)
      acc
    check "if" in words
    check "in" in words
    check "tokenizer" in words
    check words.find("tokenizer") > words.find("if")
    check words.find("tokenizer") > words.find("in")

  test "A buffer word an LSP item already offers is dropped from the merge":
    let mgr = newCompletionManager()
    # "lspHelp" is offered by both the buffer and the LSP item; it must appear
    # once (the richer LSP entry), with the unique buffer word kept.
    mgr.allWords = @["lspHelp", "hello"]
    mgr.lspItems = @[CompletionItem(label: "lspHelp", kind: some(cikFunction))]

    let entries = mgr.filterAndSortEntries("")

    var lspHelpCount = 0
    var sawHello = false
    for e in entries:
      if e.word == "lspHelp":
        inc lspHelpCount
      elif e.word == "hello":
        sawHello = true
    check lspHelpCount == 1
    check entries[0].source == csLsp
    check sawHello

  test "A buffer word is dropped even when the LSP label carries extra detail":
    let mgr = newCompletionManager()
    # The LSP item inserts "lspHelp" but displays the richer label
    # "lspHelp(): int". The dedup keys on the inserted word as well as the label,
    # so the buffer's plain "lspHelp" is still recognized as the same name and
    # dropped (it would survive if only the display label were compared).
    mgr.allWords = @["lspHelp", "hello"]
    mgr.lspItems = @[
      CompletionItem(
        label: "lspHelp(): int", insertText: some("lspHelp"), kind: some(cikFunction)
      )
    ]

    let entries = mgr.filterAndSortEntries("")

    var lspHelpWordCount = 0
    for e in entries:
      if e.word == "lspHelp":
        inc lspHelpWordCount
    check lspHelpWordCount == 1
    check entries[0].source == csLsp
    check entries[0].displayText == "lspHelp(): int"

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
    check termBuffer[0, 0].style == popupNormalStyle()

    # Second entry (selected): selected style
    check termBuffer[0, 1].style == popupSelectedStyle()

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
    check termBuffer[5, 0].style == popupDetailStyle()

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
    check termBuffer[5, 0].style == popupSelectedDetailStyle()

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
    # getSelectedRawJson re-serializes the selected typed item; the opaque `data`
    # token round-trips verbatim.
    mgr.lspItems = @[
      CompletionItem(label: "foo", data: some(%*1)),
      CompletionItem(label: "bar", data: some(%*2)),
    ]
    mgr.menu.entries = @[
      CompletionEntry(word: "foo", matchScore: 100, source: csLsp, lspItemIndex: 0),
      CompletionEntry(word: "bar", matchScore: 90, source: csLsp, lspItemIndex: 1),
    ]
    mgr.menu.selectedIndex = 1
    mgr.menu.hasSelection = true
    let rawJson = mgr.getSelectedRawJson()
    check rawJson.isSome
    check rawJson.get["label"].getStr == "bar"
    check rawJson.get["data"].getInt == 2

  test "getSelectedRawJson serializes kind as an integer (resolve wire format)":
    # The re-serialized item is echoed back to the server on a resolve request,
    # so enum fields must be LSP integers, not jsony's default symbol names.
    let mgr = newCompletionManager()
    mgr.lspItems = @[
      CompletionItem(
        label: "foo",
        kind: some(cikFunction),
        insertTextFormat: some(InsertTextFormat.itfSnippet),
        data: some(%*{"tok": 1}),
      )
    ]
    mgr.menu.entries =
      @[CompletionEntry(word: "foo", matchScore: 100, source: csLsp, lspItemIndex: 0)]
    mgr.menu.selectedIndex = 0
    mgr.menu.hasSelection = true
    let rawJson = mgr.getSelectedRawJson()
    check rawJson.isSome
    check rawJson.get["kind"].getInt == 3
    check rawJson.get["insertTextFormat"].getInt == 2
    check rawJson.get["data"]["tok"].getInt == 1

  test "getSelectedRawJson handles overloaded items with same word":
    let mgr = newCompletionManager()
    # Two overloaded functions with the same name but different details
    mgr.lspItems = @[
      CompletionItem(label: "foo", detail: some("fn(int)"), data: some(%*1)),
      CompletionItem(label: "foo", detail: some("fn(string)"), data: some(%*2)),
    ]
    mgr.menu.entries = @[
      CompletionEntry(
        word: "foo",
        matchScore: 100,
        source: csLsp,
        detail: some("fn(int)"),
        lspItemIndex: 0,
      ),
      CompletionEntry(
        word: "foo",
        matchScore: 100,
        source: csLsp,
        detail: some("fn(string)"),
        lspItemIndex: 1,
      ),
    ]
    # Select the second overload
    mgr.menu.selectedIndex = 1
    mgr.menu.hasSelection = true
    let rawJson = mgr.getSelectedRawJson()
    check rawJson.isSome
    check rawJson.get["data"].getInt == 2
    check rawJson.get["detail"].getStr == "fn(string)"

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

  test "updateResolvedEntry is dropped when the entry no longer matches":
    # The entries were rebuilt between the request and its response, so the item
    # at resolvedIndex is now a different word. The stale result must be ignored.
    let mgr = newCompletionManager()
    mgr.menu.entries = @[CompletionEntry(word: "other", matchScore: 100, source: csLsp)]
    mgr.resolvedIndex = 0

    let resolved = CompletionItem(label: "test", detail: some("fn() -> int"))
    mgr.updateResolvedEntry(resolved)

    check mgr.menu.entries[0].detail.isNone

  test "updateResolvedEntry matches entries built from a padded label":
    # Regression: lspItemToEntry trims the leading space clangd pads onto
    # labels when building `word`, so the identity check must trim the
    # resolve response's raw label the same way or the resolved data is
    # silently dropped for items without insertText.
    let mgr = newCompletionManager()
    let item = CompletionItem(label: " replace(int first, int second)")
    mgr.menu.entries = @[lspItemToEntry(item, "rep")]
    mgr.resolvedIndex = 0

    let resolved = CompletionItem(
      label: " replace(int first, int second)", detail: some("std::string &")
    )
    mgr.updateResolvedEntry(resolved)

    check mgr.menu.entries[0].detail == some("std::string &")

  test "setLspItems stores typed items for resolve re-serialization":
    let mgr = newCompletionManager()
    mgr.menu.prefix = "te"
    mgr.state = csPendingLsp

    let items = @[CompletionItem(label: "test", data: some(%*42))]
    mgr.setLspItems(items)

    check mgr.lspItems.len == 1
    mgr.menu.entries =
      @[CompletionEntry(word: "test", matchScore: 100, source: csLsp, lspItemIndex: 0)]
    mgr.menu.selectedIndex = 0
    mgr.menu.hasSelection = true
    let rawJson = mgr.getSelectedRawJson()
    check rawJson.isSome
    check rawJson.get["data"].getInt == 42

suite "Completion - DocPanel":
  test "updateDocPanel shows panel when documentation present":
    let mgr = newCompletionManager()
    mgr.menu.entries = @[
      CompletionEntry(
        word: "test",
        matchScore: 100,
        source: csLsp,
        documentation: some("Line 1\nLine 2\nLine 3"),
      )
    ]
    mgr.menu.selectedIndex = 0
    mgr.menu.hasSelection = true
    mgr.updateDocPanel()

    check mgr.docPanel.visible == true
    check mgr.docPanel.lines.len == 3
    check mgr.docPanel.lines[0] == "Line 1"
    check mgr.docPanel.scrollOffset == 0

  test "updateDocPanel hides panel when no documentation":
    let mgr = newCompletionManager()
    mgr.menu.entries =
      @[CompletionEntry(word: "test", matchScore: 100, source: csBuffer)]
    mgr.menu.selectedIndex = 0
    mgr.menu.hasSelection = true
    mgr.updateDocPanel()

    check mgr.docPanel.visible == false

  test "updateDocPanel hides panel without selection":
    let mgr = newCompletionManager()
    mgr.menu.entries = @[
      CompletionEntry(
        word: "test", matchScore: 100, source: csLsp, documentation: some("doc")
      )
    ]
    mgr.menu.hasSelection = false
    mgr.updateDocPanel()

    check mgr.docPanel.visible == false

  test "calculateDocPanelPosition places right of completion popup":
    let completionPos = PopupPosition(x: 0, y: 0, width: 20, height: 5)
    let docPanel = DocPanel(lines: @["short doc"], scrollOffset: 0, visible: true)
    let pos = calculateDocPanelPosition(completionPos, 80, 24, docPanel)
    check pos.x == 20 # Right of completion popup

  test "calculateDocPanelPosition falls back to left when no space right":
    let completionPos = PopupPosition(x: 55, y: 0, width: 20, height: 5)
    let docPanel = DocPanel(lines: @["short doc"], scrollOffset: 0, visible: true)
    let pos = calculateDocPanelPosition(completionPos, 80, 24, docPanel)
    check pos.x < completionPos.x # Should be left of completion

  test "calculateDocPanelPosition tracks the highlighted candidate's row":
    # selectedRowOffset pushes the panel top down to the highlighted row instead
    # of pinning it to the popup's first row.
    let completionPos = PopupPosition(x: 0, y: 0, width: 20, height: 12)
    let docPanel = DocPanel(lines: @["short doc"], scrollOffset: 0, visible: true)
    let pos =
      calculateDocPanelPosition(completionPos, 80, 24, docPanel, selectedRowOffset = 3)
    check pos.y == 3

  test "calculateDocPanelPosition clamps upward when the row would overflow":
    # A row near the bottom would push the panel past the bottom reserve, so it
    # is clamped up to stay fully on screen.
    let completionPos = PopupPosition(x: 0, y: 0, width: 20, height: 12)
    let docPanel = DocPanel(lines: @["short doc"], scrollOffset: 0, visible: true)
    # popupHeight = 1 visible line + 2 border = 3; termHeight 10, reserve 2.
    let pos = calculateDocPanelPosition(
      completionPos, 80, 10, docPanel, bottomReserve = 2, selectedRowOffset = 8
    )
    check pos.y == 5 # max(0, 10 - 2 - 3)

  test "renderDocPanel renders content":
    let docPanel = DocPanel(lines: @["Hello", "World"], scrollOffset: 0, visible: true)
    let pos = PopupPosition(x: 0, y: 0, width: 12, height: 4)

    var termBuffer = newBuffer(80, 24)
    renderDocPanel(termBuffer, docPanel, pos)

    # Border
    check termBuffer[0, 0].symbol == "┌"
    check termBuffer[11, 0].symbol == "┐"
    # Content
    check termBuffer[1, 1].symbol == "H"
    check termBuffer[1, 2].symbol == "W"
    # Bottom border
    check termBuffer[0, 3].symbol == "└"
    check termBuffer[11, 3].symbol == "┘"

  test "renderDocPanel shows scroll indicators":
    let docPanel = DocPanel(
      lines:
        @["L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "L10", "L11", "L12"],
      scrollOffset: 1,
      visible: true,
    )
    let pos = PopupPosition(x: 0, y: 0, width: 12, height: 12)

    var termBuffer = newBuffer(80, 24)
    renderDocPanel(termBuffer, docPanel, pos)

    # Scroll up indicator at top-right
    check termBuffer[11, 0].symbol == "▲"
    # Scroll down indicator at bottom-right
    check termBuffer[11, 11].symbol == "▼"

suite "Completion - triggerCompletion preserves lspItems":
  test "triggerCompletion does not clear existing lspItems":
    let mgr = newCompletionManager()
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello hel")

    # Simulate LSP items already present
    mgr.lspItems = @[
      CompletionItem(label: "hello", kind: some(cikFunction)),
      CompletionItem(label: "help", kind: some(cikVariable)),
    ]

    mgr.triggerCompletion(buf, 0, 9)

    # lspItems should be preserved, not cleared
    check mgr.lspItems.len == 2
    check mgr.lspItems[0].label == "hello"

  test "triggerCompletion uses lspItems for filtering when present":
    let mgr = newCompletionManager()
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "tes")

    # Set LSP items first
    mgr.lspItems = @[
      CompletionItem(label: "test", kind: some(cikFunction), detail: some("fn()")),
      CompletionItem(label: "testing", kind: some(cikVariable)),
    ]

    mgr.triggerCompletion(buf, 0, 3)

    # Should show LSP items since lspItems is not empty
    check mgr.state == csActive
    check mgr.menu.entries.len == 2
    check mgr.menu.entries[0].source == csLsp

suite "Completion - renderCompletionPopup with multibyte characters":
  test "Multibyte word truncated correctly by display width":
    # contentWidth=5 cells, "日本語テスト" is 6 CJK runes × 2 cells = 12 cells.
    # Truncation must be display-width aware: fit as many wide clusters as
    # possible followed by "…". Two "日本" clusters (4 cells) + "…" (1 cell)
    # = 5 cells fits exactly. Slicing by rune index would keep 4 CJK runes and
    # overflow to 9 cells.
    let menu = CompletionMenu(
      entries: @[
        CompletionEntry(word: "日本語テスト", matchScore: 100, source: csBuffer)
      ],
      selectedIndex: 0,
      hasSelection: false,
      scrollOffset: 0,
      maxVisible: 10,
    )
    let pos = PopupPosition(x: 0, y: 0, width: 5, height: 1)

    var termBuffer = newBuffer(80, 24)
    renderCompletionPopup(termBuffer, menu, pos, showBorder = false)

    check termBuffer[0, 0].symbol == "日"
    check termBuffer[2, 0].symbol == "本"
    check termBuffer[4, 0].symbol == "…"

  test "ASCII word truncates on display width":
    let menu = CompletionMenu(
      entries: @[CompletionEntry(word: "longword", matchScore: 100, source: csBuffer)],
      selectedIndex: 0,
      hasSelection: false,
      scrollOffset: 0,
      maxVisible: 10,
    )
    # contentWidth=5: "longword" (8 cells > 5) → "long…"
    let pos = PopupPosition(x: 0, y: 0, width: 5, height: 1)

    var termBuffer = newBuffer(80, 24)
    renderCompletionPopup(termBuffer, menu, pos, showBorder = false)

    check termBuffer[0, 0].symbol == "l"
    check termBuffer[1, 0].symbol == "o"
    check termBuffer[2, 0].symbol == "n"
    check termBuffer[3, 0].symbol == "g"
    check termBuffer[4, 0].symbol == "…"

  test "Wide char word writes continuation cell to prevent ghost":
    # When the popup contains wide (2-col) characters, the cell at x+1 must
    # be an empty continuation cell — otherwise celina's diff can't detect
    # that column when the popup closes, leaving a half-character residual
    # on terminal.
    let menu = CompletionMenu(
      entries: @[CompletionEntry(word: "日本語", matchScore: 100, source: csBuffer)],
      selectedIndex: 0,
      hasSelection: false,
      scrollOffset: 0,
      maxVisible: 10,
    )
    let pos = PopupPosition(x: 0, y: 0, width: 10, height: 1)

    var termBuffer = newBuffer(80, 24)
    renderCompletionPopup(termBuffer, menu, pos, showBorder = false)

    # Main cells hold the wide char symbol
    check termBuffer[0, 0].symbol == "日"
    check termBuffer[2, 0].symbol == "本"
    check termBuffer[4, 0].symbol == "語"
    # Continuation cells are empty strings with the same style as the main cell
    check termBuffer[1, 0].symbol == ""
    check termBuffer[1, 0].style == termBuffer[0, 0].style
    check termBuffer[3, 0].symbol == ""
    check termBuffer[3, 0].style == termBuffer[2, 0].style
    check termBuffer[5, 0].symbol == ""
    check termBuffer[5, 0].style == termBuffer[4, 0].style

  test "Wide char detail writes continuation cell":
    let menu = CompletionMenu(
      entries: @[
        CompletionEntry(
          word: "abc", detail: some("日本"), matchScore: 100, source: csBuffer
        )
      ],
      selectedIndex: 0,
      hasSelection: false,
      scrollOffset: 0,
      maxVisible: 10,
    )
    # Wide popup so detail fits: word "abc" (3) + gap (3) + detail "日本" (4) = 10
    let pos = PopupPosition(x: 0, y: 0, width: 12, height: 1)

    var termBuffer = newBuffer(80, 24)
    renderCompletionPopup(termBuffer, menu, pos, showBorder = false)

    # Find the detail chars — they come after the word and the separator gap.
    # The exact column depends on layout, but continuation cells must exist
    # wherever wide chars are placed.
    for x in 0 ..< pos.width:
      if termBuffer[x, 0].symbol == "日":
        check termBuffer[x + 1, 0].symbol == ""
        check termBuffer[x + 1, 0].style == termBuffer[x, 0].style
      elif termBuffer[x, 0].symbol == "本":
        check termBuffer[x + 1, 0].symbol == ""
        check termBuffer[x + 1, 0].style == termBuffer[x, 0].style

  test "renderDocPanel wide char writes continuation cell":
    let docPanel = DocPanel(visible: true, lines: @["日本語"], scrollOffset: 0)
    let pos = PopupPosition(x: 0, y: 0, width: 10, height: 3)

    var termBuffer = newBuffer(80, 24)
    renderDocPanel(termBuffer, docPanel, pos)

    # Content starts at (1, 1) because of border
    check termBuffer[1, 1].symbol == "日"
    check termBuffer[2, 1].symbol == ""
    check termBuffer[2, 1].style == termBuffer[1, 1].style
    check termBuffer[3, 1].symbol == "本"
    check termBuffer[4, 1].symbol == ""
    check termBuffer[4, 1].style == termBuffer[3, 1].style

suite "Completion - expandSnippet":
  test "Plain text passes through with cursor at end":
    let (text, offset) = expandSnippet("hello")
    check text == "hello"
    check offset == 5

  test "$0 marks the final cursor stop":
    let (text, offset) = expandSnippet("vec![$0]")
    check text == "vec![]"
    check offset == 5

  test "${0} braces form of the final stop":
    let (text, offset) = expandSnippet("a${0}b")
    check text == "ab"
    check offset == 1

  test "Numbered placeholder keeps its default text":
    let (text, offset) = expandSnippet("foo(${1:bar})")
    check text == "foo(bar)"
    # No $0, so cursor goes to the lowest-numbered stop ($1 = start of "bar")
    check offset == 4

  test "Bare $n becomes empty":
    let (text, offset) = expandSnippet("if $1:")
    check text == "if :"
    check offset == 3

  test "$0 preferred over numbered stops":
    let (text, offset) = expandSnippet("${1:a}$0${2:b}")
    check text == "ab"
    check offset == 1

  test "Escapes are unescaped":
    let (text, offset) = expandSnippet("price: \\$5")
    check text == "price: $5"
    check offset == 9

  test "Nested placeholder defaults are expanded":
    let (text, _) = expandSnippet("${1:${2:inner}}")
    check text == "inner"

  test "No stops puts cursor at end":
    let (text, offset) = expandSnippet("abc")
    check text == "abc"
    check offset == 3

  test "A $0 nested inside a placeholder default wins the cursor":
    # The $0 lives inside the ${1:...} default; the cursor must land on it
    # (between "foo" and "bar"), not at the start of the placeholder.
    let (text, offset) = expandSnippet("${1:foo$0bar}")
    check text == "foobar"
    check offset == 3

  test "An overflowing tabstop number is ignored, not a crash":
    # A pathological digit run would overflow parseInt; it must be swallowed and
    # treated as no stop rather than raising out of the commit path.
    let (text, offset) = expandSnippet("${999999999999999999999:x}")
    check text == "x"
    check offset == 1

  test "A bare $VAR variable drops to empty, not a literal $name":
    # We don't expand snippet variables; $TM_FILENAME must vanish rather than
    # leaking a stray "$TM_FILENAME" into the buffer.
    let (text, offset) = expandSnippet("log($TM_FILENAME)")
    check text == "log()"
    check offset == 5

  test "An unknown ${VAR} drops to its default or empty":
    check expandSnippet("${TM_SELECTED_TEXT}").text == ""
    check expandSnippet("name: ${UNKNOWN:fallback}").text == "name: fallback"

suite "Completion - expandSnippetWithStops":
  test "clangd-style multi-parameter placeholders":
    let (text, stops) = expandSnippetWithStops(
      "replace(${1:size_type pos}, ${2:size_type n1}, ${3:const char *s})"
    )
    check text == "replace(size_type pos, size_type n1, const char *s)"
    check stops.len == 3
    check stops[0] == SnippetStopOffset(num: 1, offset: 8, len: 13)
    check stops[1] == SnippetStopOffset(num: 2, offset: 23, len: 12)
    check stops[2] == SnippetStopOffset(num: 3, offset: 37, len: 13)

  test "rust-analyzer-style placeholder plus final stop":
    let (text, stops) = expandSnippetWithStops("push(${1:ch});$0")
    check text == "push(ch);"
    check stops ==
      @[
        SnippetStopOffset(num: 1, offset: 5, len: 2),
        SnippetStopOffset(num: 0, offset: 9, len: 0),
      ]

  test "$0 sorts last even when written first":
    let (text, stops) = expandSnippetWithStops("$0${2:b}${1:a}")
    check text == "ba"
    check stops.len == 3
    check stops[0].num == 1
    check stops[1].num == 2
    check stops[2].num == 0

  test "Bare $n records a zero-length stop":
    let (text, stops) = expandSnippetWithStops("if $1:")
    check text == "if :"
    check stops == @[SnippetStopOffset(num: 1, offset: 3, len: 0)]

  test "Mirror stops keep only the first occurrence":
    let (text, stops) = expandSnippetWithStops("${1:a} $1 ${1:b}")
    check text == "a  b"
    check stops == @[SnippetStopOffset(num: 1, offset: 0, len: 1)]

  test "Nested placeholder stops are lifted to outer coordinates":
    let (text, stops) = expandSnippetWithStops("${1:${2:inner}}")
    check text == "inner"
    check stops ==
      @[
        SnippetStopOffset(num: 1, offset: 0, len: 5),
        SnippetStopOffset(num: 2, offset: 0, len: 5),
      ]

  test "Multi-line body offsets count the newline as one rune":
    let (text, stops) = expandSnippetWithStops("for ${1:x} {\n\t$0\n}")
    check text == "for x {\n\t\n}"
    check stops ==
      @[
        SnippetStopOffset(num: 1, offset: 4, len: 1),
        SnippetStopOffset(num: 0, offset: 9, len: 0),
      ]

  test "Wide-rune defaults use rune offsets and lengths":
    let (text, stops) = expandSnippetWithStops("名前(${1:値})")
    check text == "名前(値)"
    check stops == @[SnippetStopOffset(num: 1, offset: 3, len: 1)]

  test "No stops yields an empty list":
    let (text, stops) = expandSnippetWithStops("abc")
    check text == "abc"
    check stops.len == 0

  test "${n} brace form without default records a zero-length stop":
    let (text, stops) = expandSnippetWithStops("a${1}b")
    check text == "ab"
    check stops == @[SnippetStopOffset(num: 1, offset: 1, len: 0)]

suite "Completion - LSP filterText/sortText":
  test "Items are kept by filterText, not insertText":
    let mgr = newCompletionManager()
    # label/filterText match the prefix but insertText does not.
    mgr.lspItems = @[
      CompletionItem(
        label: "myField", filterText: some("myField"), insertText: some("this.myField")
      )
    ]
    let entries = mgr.filterAndSortEntries("myF")
    check entries.len == 1
    check entries[0].word == "this.myField"

  test "Ordering follows sortText, not client matchScore":
    let mgr = newCompletionManager()
    # "alpha" is a better prefix match, but sortText ranks "beta" first.
    mgr.lspItems = @[
      CompletionItem(label: "alpha", sortText: some("zzz")),
      CompletionItem(label: "beta", sortText: some("aaa")),
    ]
    let entries = mgr.filterAndSortEntries("")
    check entries.len == 2
    check entries[0].word == "beta"
    check entries[1].word == "alpha"

suite "Completion - snippet display label":
  test "Snippet items display the label, not the raw snippet body":
    # With snippetSupport enabled the server returns the snippet body in
    # insertText; `word` keeps it for insertion but the popup must show the clean
    # label instead of placeholder syntax like `println!($0)`.
    let item = CompletionItem(
      label: "println!",
      insertText: some("println!($0)"),
      insertTextFormat: some(InsertTextFormat.itfSnippet),
    )
    let entry = lspItemToEntry(item, "pr")
    check entry.isSnippet
    check entry.word == "println!($0)" # raw body, used for insertion
    check entry.label == "println!"
    check entry.displayText == "println!" # what the popup renders

  test "Buffer entries with no label fall back to the word for display":
    let entry = CompletionEntry(word: "template", source: csBuffer)
    check entry.displayText == "template"

suite "Completion - renderCompletionPopup narrow width":
  test "Narrow popup width does not crash (word only)":
    let menu = CompletionMenu(
      entries: @[CompletionEntry(word: "println", matchScore: 100, source: csBuffer)],
      selectedIndex: 0,
      hasSelection: true,
      scrollOffset: 0,
      maxVisible: 10,
    )
    var termBuffer = newBuffer(80, 24)
    for w in [0, 1, 2, 3, 4]:
      let pos = PopupPosition(x: 0, y: 0, width: w, height: 3)
      renderCompletionPopup(termBuffer, menu, pos, showBorder = true)
      renderCompletionPopup(termBuffer, menu, pos, showBorder = false)

  test "Narrow popup width does not crash (word + detail)":
    let menu = CompletionMenu(
      entries: @[
        CompletionEntry(
          word: "println", matchScore: 100, source: csLsp, detail: some("fn(args)")
        )
      ],
      selectedIndex: 0,
      hasSelection: true,
      scrollOffset: 0,
      maxVisible: 10,
    )
    var termBuffer = newBuffer(80, 24)
    for w in [0, 1, 2, 3, 4, 8]:
      let pos = PopupPosition(x: 0, y: 0, width: w, height: 3)
      renderCompletionPopup(termBuffer, menu, pos, showBorder = true)

  test "Multibyte word/detail truncate without crashing":
    let menu = CompletionMenu(
      entries: @[
        CompletionEntry(
          word: "あいうえおかき",
          matchScore: 100,
          source: csLsp,
          detail: some("さしすせそ"),
        )
      ],
      selectedIndex: 0,
      hasSelection: true,
      scrollOffset: 0,
      maxVisible: 10,
    )
    var termBuffer = newBuffer(80, 24)
    for w in [4, 6, 8, 10]:
      let pos = PopupPosition(x: 0, y: 0, width: w, height: 3)
      renderCompletionPopup(termBuffer, menu, pos, showBorder = true)

suite "Completion - display-width sizing (CJK/wide chars)":
  test "calculateMaxWordWidth reports display cells for CJK words":
    # "テスト" = 3 CJK runes × 2 cells = 6 cells; "abc" = 3 cells.
    let entries = @[
      CompletionEntry(word: "abc", matchScore: 100, source: csBuffer),
      CompletionEntry(word: "テスト", matchScore: 90, source: csBuffer),
    ]
    check calculateMaxWordWidth(entries) == 6

  test "calculateMaxWordWidth mixes ASCII and CJK by display width":
    # "hello世界" = 5 ASCII + 2 CJK × 2 = 9 cells; "abcdefgh" = 8 cells.
    let entries = @[
      CompletionEntry(word: "abcdefgh", matchScore: 100, source: csBuffer),
      CompletionEntry(word: "hello世界", matchScore: 90, source: csBuffer),
    ]
    check calculateMaxWordWidth(entries) == 9

  test "calculateMaxDetailWidth reports display cells for CJK details":
    # "文字列" = 6 cells; "int" = 3 cells.
    let entries = @[
      CompletionEntry(word: "a", matchScore: 100, source: csLsp, detail: some("int")),
      CompletionEntry(
        word: "b", matchScore: 90, source: csLsp, detail: some("文字列")
      ),
    ]
    check calculateMaxDetailWidth(entries) == 6

  test "calculateDocPanelPosition sizes contentWidth by display cells":
    # Two lines; widest is 20 CJK runes × 2 = 40 cells. Below DocPanelMaxWidth (60).
    var wide = ""
    for _ in 0 ..< 20:
      wide.add("あ")
    let docPanel = DocPanel(lines: @["short", wide], scrollOffset: 0, visible: true)
    let completionPos = PopupPosition(x: 0, y: 0, width: 20, height: 5)
    let pos = calculateDocPanelPosition(completionPos, 200, 24, docPanel)

    # popupWidth = contentWidth + 2 (border); contentWidth = 40 + PopupPadding.
    check pos.width == 40 + PopupPadding + 2

  test "calculateDocPanelPosition clamps CJK content at DocPanelMaxWidth":
    # 40 CJK runes × 2 = 80 cells + padding would exceed DocPanelMaxWidth (60).
    var wide = ""
    for _ in 0 ..< 40:
      wide.add("あ")
    let docPanel = DocPanel(lines: @[wide], scrollOffset: 0, visible: true)
    let completionPos = PopupPosition(x: 0, y: 0, width: 20, height: 5)
    let pos = calculateDocPanelPosition(completionPos, 200, 24, docPanel)

    check pos.width == DocPanelMaxWidth + 2

suite "Completion - truncation display-width boundaries":
  test "CJK word that exactly fits is not truncated":
    # "日本" = 4 cells; contentWidth = 4 → no truncation, no ellipsis.
    let menu = CompletionMenu(
      entries: @[CompletionEntry(word: "日本", matchScore: 100, source: csBuffer)],
      selectedIndex: 0,
      hasSelection: false,
      scrollOffset: 0,
      maxVisible: 10,
    )
    let pos = PopupPosition(x: 0, y: 0, width: 4, height: 1)

    var termBuffer = newBuffer(80, 24)
    renderCompletionPopup(termBuffer, menu, pos, showBorder = false)

    check termBuffer[0, 0].symbol == "日"
    check termBuffer[2, 0].symbol == "本"

  test "CJK word one cell over the limit becomes ellipsis-terminated":
    # "日本語" = 6 cells; contentWidth = 5 → "日" (2) + "…" (1) fits in 3 cells,
    # but "日本" (4) + "…" would be 5 cells which fits exactly.
    let menu = CompletionMenu(
      entries: @[CompletionEntry(word: "日本語", matchScore: 100, source: csBuffer)],
      selectedIndex: 0,
      hasSelection: false,
      scrollOffset: 0,
      maxVisible: 10,
    )
    let pos = PopupPosition(x: 0, y: 0, width: 5, height: 1)

    var termBuffer = newBuffer(80, 24)
    renderCompletionPopup(termBuffer, menu, pos, showBorder = false)

    check termBuffer[0, 0].symbol == "日"
    check termBuffer[2, 0].symbol == "本"
    check termBuffer[4, 0].symbol == "…"

  test "CJK word truncates before overflowing wide cluster":
    # contentWidth = 3, wide next cluster (2 cells) + ellipsis (1) = 3 fits but
    # only "日" (2) + "…" (1) is placeable without splitting a wide char.
    let menu = CompletionMenu(
      entries: @[CompletionEntry(word: "日本語", matchScore: 100, source: csBuffer)],
      selectedIndex: 0,
      hasSelection: false,
      scrollOffset: 0,
      maxVisible: 10,
    )
    let pos = PopupPosition(x: 0, y: 0, width: 3, height: 1)

    var termBuffer = newBuffer(80, 24)
    renderCompletionPopup(termBuffer, menu, pos, showBorder = false)

    check termBuffer[0, 0].symbol == "日"
    check termBuffer[2, 0].symbol == "…"

  test "CJK detail truncates by display width, not rune count":
    # Word "a" (1 cell) + gap DetailSeparator; detail "型情報表示" = 10 cells.
    # Popup wide enough for word, gap, then a small detail slot forces truncation.
    let menu = CompletionMenu(
      entries: @[
        CompletionEntry(
          word: "a", matchScore: 100, source: csLsp, detail: some("型情報表示")
        )
      ],
      selectedIndex: 0,
      hasSelection: false,
      scrollOffset: 0,
      maxVisible: 10,
    )
    # word 1 + gap 2 + detail slot 5 = 8 cells total content
    let pos = PopupPosition(x: 0, y: 0, width: 8, height: 1)

    var termBuffer = newBuffer(80, 24)
    renderCompletionPopup(termBuffer, menu, pos, showBorder = false)

    # Word at col 0, gap fills cols 1..2, detail begins at col 3.
    check termBuffer[0, 0].symbol == "a"
    # First CJK detail cluster occupies cols 3-4 (wide), second at 5-6, "…" at 7.
    check termBuffer[3, 0].symbol == "型"
    check termBuffer[5, 0].symbol == "情"
    check termBuffer[7, 0].symbol == "…"
