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

## Tests for command_handlers/search_mode_handler.nim

import std/[unittest, options, unicode]

import pkg/celina

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/editor {.all.}
import ../src/moepkg/config {.all.}
import ../src/moepkg/help_viewer {.all.}
import ../src/moepkg/search_utils {.all.}
import ../src/moepkg/command_handlers/search_mode_handler {.all.}

proc setSearchText(e: Editor, text: string) =
  ## Test helper: set search text and position cursor at the end,
  ## matching the state after the user has typed the text.
  e.state.search.text = text
  e.state.search.cursor = text.runeLen

proc createTestEditorWithBuffer(content: string): Editor =
  let config = newEditorConfig()
  config.standard.mouse = true
  result = newEditor(config)
  result.textBuffer = newTextBuffer(content)
  result.windowManager.windows[0].buffer = result.textBuffer
  result.windowManager.windows[0].bufferIds = @[result.textBuffer.id]
  result.viewport =
    ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
  result.windowManager.windows[0].viewport = result.viewport
  result.executer.motionController.viewportManager.viewport = result.viewport
  result.state.mode = EditorMode.Normal

proc createTestEditorInHelpMode(): Editor =
  ## Create an editor in Help mode with helpViewerState set up.
  ## Uses help viewer content as the buffer.
  let helpState = newHelpViewerState()
  let helpBuffer = helpState.createHelpTextBuffer()
  result = createTestEditorWithBuffer("")
  result.textBuffer = helpBuffer
  result.windowManager.windows[0].buffer = helpBuffer
  result.windowManager.windows[0].bufferIds = @[helpBuffer.id]
  result.windowManager.windows[0].modeState = ModeState(kind: mskHelp, help: helpState)
  result.state.mode = EditorMode.Help

suite "handleSearchBackspace":
  test "Remove last ASCII character":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")

    handleSearchBackspace(e)

    check e.state.search.text == "ab"

  test "Remove last multibyte character (Japanese)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("検索")

    handleSearchBackspace(e)

    check e.state.search.text == "検"

  test "Remove last character from mixed ASCII and multibyte":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc日本語")

    handleSearchBackspace(e)

    check e.state.search.text == "abc日本"

  test "Backspace on single character leaves empty string":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("x")

    handleSearchBackspace(e)

    check e.state.search.text == ""

  test "Backspace on single multibyte character leaves empty string":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("あ")

    handleSearchBackspace(e)

    check e.state.search.text == ""

  test "Backspace on empty string does nothing":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("")

    handleSearchBackspace(e)

    check e.state.search.text == ""

  test "Backspace sets needsFullRedraw":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("test")
    e.state.windowDisplay.needsFullRedraw = false

    handleSearchBackspace(e)

    check e.state.windowDisplay.needsFullRedraw == true

suite "Search mode - Insert-Normal mode (Ctrl-O)":
  test "finalizeSearch returns to Insert when insertNormalMode is set":
    let e = createTestEditorWithBuffer("hello world")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = true
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("world")

    finalizeSearch(e)

    check e.state.mode == EditorMode.Insert
    check not e.state.insertNormalMode
    check not e.state.isSearchOverlay

  test "cancelSearch returns to Insert when insertNormalMode is set":
    let e = createTestEditorWithBuffer("hello world")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = true
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("world")

    cancelSearch(e)

    check e.state.mode == EditorMode.Insert
    check not e.state.insertNormalMode
    check not e.state.isSearchOverlay

  test "finalizeSearch stays in Normal when insertNormalMode is false":
    let e = createTestEditorWithBuffer("hello world")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = false
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("world")

    finalizeSearch(e)

    check e.state.mode == EditorMode.Normal
    check not e.state.insertNormalMode

  test "cancelSearch stays in Normal when insertNormalMode is false":
    let e = createTestEditorWithBuffer("hello world")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = false
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("world")

    cancelSearch(e)

    check e.state.mode == EditorMode.Normal
    check not e.state.insertNormalMode

  test "finalizeSearch with Backward direction returns to Insert when insertNormalMode":
    let e = createTestEditorWithBuffer("hello world")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = true
    e.state.enterSearchOverlay(Backward)
    e.setSearchText("hello")

    finalizeSearch(e)

    check e.state.mode == EditorMode.Insert
    check not e.state.insertNormalMode
    check not e.state.isSearchOverlay

  test "cancelSearch with Backward direction returns to Insert when insertNormalMode":
    let e = createTestEditorWithBuffer("hello world")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = true
    e.state.enterSearchOverlay(Backward)
    e.setSearchText("hello")

    cancelSearch(e)

    check e.state.mode == EditorMode.Insert
    check not e.state.insertNormalMode
    check not e.state.isSearchOverlay

suite "Search mode - Help mode incremental search sync":
  test "performIncrementalSearch syncs selectedIndex on match":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.search.incsearch = true
    e.state.search.startPos = BufferPosition(line: 0, column: 0)
    e.setSearchText("Visual")

    performIncrementalSearch(e)

    let helpState = e.activeWindow.modeState.help
    # selectedIndex should be updated to the matched line
    check helpState.selectedIndex == e.cursor.line
    check helpState.selectedIndex > 0

  test "performIncrementalSearch syncs selectedIndex to startPos on no match":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.search.incsearch = true
    e.state.search.startPos = BufferPosition(line: 5, column: 0)
    e.setSearchText("zzzzNonExistentPattern")

    performIncrementalSearch(e)

    let helpState = e.activeWindow.modeState.help
    # selectedIndex should be restored to startPos line
    check helpState.selectedIndex == 5

  test "handleSearchCharacterInput syncs selectedIndex during typing":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.search.incsearch = true
    e.state.search.startPos = BufferPosition(line: 0, column: 0)

    # Type "Replace" character by character
    for ch in "Replace":
      handleSearchCharacterInput(e, $ch)

    let helpState = e.activeWindow.modeState.help
    # selectedIndex should match cursor
    check helpState.selectedIndex == e.cursor.line
    check helpState.selectedIndex > 0

  test "finalizeSearch syncs selectedIndex from cursor position":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.search.incsearch = true
    e.state.search.startPos = BufferPosition(line: 0, column: 0)
    e.setSearchText("Visual")

    # Perform incremental search first to move cursor
    performIncrementalSearch(e)
    let cursorLineAfterSearch = e.cursor.line

    finalizeSearch(e)

    let helpState = e.activeWindow.modeState.help
    # selectedIndex should match cursor position, not reset to first match
    check helpState.selectedIndex == cursorLineAfterSearch
    check helpState.searchQuery == "Visual"

  test "finalizeSearch without incsearch syncs selectedIndex":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.search.incsearch = false
    e.state.search.startPos = BufferPosition(line: 0, column: 0)
    e.setSearchText("Insert")

    finalizeSearch(e)

    let helpState = e.activeWindow.modeState.help
    check helpState.selectedIndex == e.cursor.line
    check helpState.searchQuery == "Insert"

  test "handleSearchBackspace syncs selectedIndex":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.search.incsearch = true
    e.state.search.startPos = BufferPosition(line: 0, column: 0)
    e.setSearchText("Visual")

    # First search to set position
    performIncrementalSearch(e)
    let firstMatchLine = e.cursor.line

    # Add more characters to narrow search
    handleSearchCharacterInput(e, " ")
    handleSearchCharacterInput(e, "m")

    let narrowedLine = e.cursor.line

    # Backspace to widen search again
    handleSearchBackspace(e)
    handleSearchBackspace(e)

    let helpState = e.activeWindow.modeState.help
    # Should be back to same position as first match
    check helpState.selectedIndex == firstMatchLine

  test "cancelSearch restores selectedIndex to startPos":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.search.incsearch = true
    e.state.search.startPos = BufferPosition(line: 10, column: 0)
    e.cursor = BufferPosition(line: 10, column: 0)
    e.setSearchText("Visual")

    # Move selectedIndex away from startPos via incremental search
    performIncrementalSearch(e)
    let helpState = e.activeWindow.modeState.help
    check helpState.selectedIndex != 10

    # Cancel should restore selectedIndex to startPos
    cancelSearch(e)
    check helpState.selectedIndex == 10

suite "Incremental search - case insensitive highlighting":
  test "Case-insensitive search highlights uppercase matches":
    let e = createTestEditorWithBuffer("Hello World hello")
    e.state.enterSearchOverlay(Forward)
    e.state.search.incsearch = true
    e.state.search.ignorecase = true
    e.state.search.smartcase = true
    e.state.search.startPos = BufferPosition(line: 0, column: 0)

    # Type lowercase "hello"
    handleSearchCharacterInput(e, "h")
    handleSearchCharacterInput(e, "e")
    handleSearchCharacterInput(e, "l")
    handleSearchCharacterInput(e, "l")
    handleSearchCharacterInput(e, "o")

    # Search should find "hello" at column 12 (next match after startPos)
    check e.cursor == BufferPosition(line: 0, column: 12)

    # Verify shouldIgnoreCase returns true for lowercase pattern
    let ignCase = shouldIgnoreCase(
      e.state.search.text, e.state.search.ignorecase, e.state.search.smartcase
    )
    check ignCase == true
    check e.state.search.text == "hello"

    # Verify findSearchMatchRanges finds BOTH uppercase and lowercase matches
    # This is what the rendering uses for highlighting
    let ranges = e.activeBuffer.findSearchMatchRanges(
      0, e.state.search.text, ignCase, e.state.search.wholeWord
    )
    # Should find both "Hello" (col 0-5) and "hello" (col 12-17)
    check ranges.len == 2
    check ranges[0].startCol == 0
    check ranges[0].endCol == 5
    check ranges[1].startCol == 12
    check ranges[1].endCol == 17

  test "Case-insensitive search highlights on different lines":
    # Multi-line: uppercase on line 0, lowercase on line 1
    let e = createTestEditorWithBuffer("Hello World\nhello world\nHELLO WORLD")
    e.state.enterSearchOverlay(Forward)
    e.state.search.incsearch = true
    e.state.search.ignorecase = true
    e.state.search.smartcase = true
    e.state.search.startPos = BufferPosition(line: 0, column: 0)

    handleSearchCharacterInput(e, "h")
    handleSearchCharacterInput(e, "e")
    handleSearchCharacterInput(e, "l")
    handleSearchCharacterInput(e, "l")
    handleSearchCharacterInput(e, "o")

    # Should find "hello" on line 1 (next after startPos)
    check e.cursor.line == 1
    check e.cursor.column == 0

    let ignCase = shouldIgnoreCase(
      e.state.search.text, e.state.search.ignorecase, e.state.search.smartcase
    )
    check ignCase == true

    # Verify highlighting on line 0 (uppercase "Hello")
    let ranges0 = e.activeBuffer.findSearchMatchRanges(
      0, e.state.search.text, ignCase, e.state.search.wholeWord
    )
    check ranges0.len == 1
    check ranges0[0].startCol == 0
    check ranges0[0].endCol == 5

    # Verify highlighting on line 1 (lowercase "hello")
    let ranges1 = e.activeBuffer.findSearchMatchRanges(
      1, e.state.search.text, ignCase, e.state.search.wholeWord
    )
    check ranges1.len == 1
    check ranges1[0].startCol == 0
    check ranges1[0].endCol == 5

    # Verify highlighting on line 2 (all-caps "HELLO")
    let ranges2 = e.activeBuffer.findSearchMatchRanges(
      2, e.state.search.text, ignCase, e.state.search.wholeWord
    )
    check ranges2.len == 1
    check ranges2[0].startCol == 0
    check ranges2[0].endCol == 5

  test "enterSearchOverlay resets wholeWord":
    ## Regression test: wholeWord must be reset when entering search overlay
    ## so that / and ? searches use consistent regex matching for both
    ## cursor movement and highlighting.
    let e = createTestEditorWithBuffer("abc foobar foo baz")
    # Simulate * command setting wholeWord=true
    e.state.search.wholeWord = true

    # Enter search overlay - should reset wholeWord
    e.state.enterSearchOverlay(Forward)
    check e.state.search.wholeWord == false

    e.state.search.incsearch = true
    e.state.search.ignorecase = true
    e.state.search.smartcase = true

    handleSearchCharacterInput(e, "f")
    handleSearchCharacterInput(e, "o")
    handleSearchCharacterInput(e, "o")

    # findNext finds "foo" in "foobar" at col 4
    check e.cursor == BufferPosition(line: 0, column: 4)

    let ignCase = shouldIgnoreCase(
      e.state.search.text, e.state.search.ignorecase, e.state.search.smartcase
    )

    # With wholeWord=false (reset by enterSearchOverlay), highlight also uses regex
    # and finds both "foo" in "foobar" (col 4) and standalone "foo" (col 11)
    let ranges = e.activeBuffer.findSearchMatchRanges(
      0, e.state.search.text, ignCase, e.state.search.wholeWord
    )
    check ranges.len == 2
    check ranges[0].startCol == 4
    check ranges[0].endCol == 7
    check ranges[1].startCol == 11
    check ranges[1].endCol == 14

proc makeLeftEvent(): Event =
  Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.ArrowLeft))

proc makeRightEvent(): Event =
  Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.ArrowRight))

proc makeHomeEvent(): Event =
  Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Home))

proc makeEndEvent(): Event =
  Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.End))

proc makeDeleteEvent(): Event =
  Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Delete))

proc makeCharEvent(c: string): Event =
  Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Char, char: c))

proc makeBackspaceEvent(): Event =
  Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Backspace))

suite "Search mode - cursor movement":
  test "Left arrow moves cursor left":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")

    discard handleSearchModeEvent(e, makeLeftEvent())

    check e.state.search.cursor == 2

  test "Left arrow does not move past start":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")
    e.state.search.cursor = 0

    discard handleSearchModeEvent(e, makeLeftEvent())

    check e.state.search.cursor == 0

  test "Right arrow moves cursor right":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")
    e.state.search.cursor = 0

    discard handleSearchModeEvent(e, makeRightEvent())

    check e.state.search.cursor == 1

  test "Right arrow does not move past end":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")

    discard handleSearchModeEvent(e, makeRightEvent())

    check e.state.search.cursor == 3

  test "Left arrow steps over multibyte character":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("検索")

    discard handleSearchModeEvent(e, makeLeftEvent())

    check e.state.search.cursor == 1

  test "Home moves cursor to start":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")

    discard handleSearchModeEvent(e, makeHomeEvent())

    check e.state.search.cursor == 0

  test "End moves cursor to end":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")
    e.state.search.cursor = 0

    discard handleSearchModeEvent(e, makeEndEvent())

    check e.state.search.cursor == 3

suite "Search mode - character insertion at cursor":
  test "Insert character at cursor position":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("ac")
    e.state.search.cursor = 1

    discard handleSearchModeEvent(e, makeCharEvent("b"))

    check e.state.search.text == "abc"
    check e.state.search.cursor == 2

  test "Insert character at start":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("bc")
    e.state.search.cursor = 0

    discard handleSearchModeEvent(e, makeCharEvent("a"))

    check e.state.search.text == "abc"
    check e.state.search.cursor == 1

  test "Insert character at end (append)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("ab")

    discard handleSearchModeEvent(e, makeCharEvent("c"))

    check e.state.search.text == "abc"
    check e.state.search.cursor == 3

  test "Insert multibyte character at cursor":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("a検")
    e.state.search.cursor = 1

    discard handleSearchModeEvent(e, makeCharEvent("索"))

    check e.state.search.text == "a索検"
    check e.state.search.cursor == 2

suite "Search mode - Delete and Backspace at cursor":
  test "Delete removes character at cursor":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")
    e.state.search.cursor = 1

    discard handleSearchModeEvent(e, makeDeleteEvent())

    check e.state.search.text == "ac"
    check e.state.search.cursor == 1

  test "Delete at end does nothing":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")

    discard handleSearchModeEvent(e, makeDeleteEvent())

    check e.state.search.text == "abc"
    check e.state.search.cursor == 3

  test "Backspace removes character before cursor":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")
    e.state.search.cursor = 2

    discard handleSearchModeEvent(e, makeBackspaceEvent())

    check e.state.search.text == "ac"
    check e.state.search.cursor == 1

  test "Backspace at start does nothing":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")
    e.state.search.cursor = 0

    discard handleSearchModeEvent(e, makeBackspaceEvent())

    check e.state.search.text == "abc"
    check e.state.search.cursor == 0

suite "Search mode - enterSearchOverlay cursor init":
  test "enterSearchOverlay resets cursor to 0":
    let e = createTestEditorWithBuffer("hello")
    e.state.search.cursor = 5
    e.state.enterSearchOverlay(Forward)
    check e.state.search.cursor == 0
