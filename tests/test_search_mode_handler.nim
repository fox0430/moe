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

import std/[options, strutils, unittest]

import ../src/moepkg/celina_backend

import
  ../src/moepkg/[
    buffer, types, modes, editor, config, config_mode, help_viewer, editor_reload,
    search_ops, search_utils, key_bindings, unicode_utils,
  ]
import ../src/moepkg/command_handlers/search_mode_handler {.all.}
import ../src/moepkg/command_handlers/result_processor
import ../src/moepkg/editor_render_window {.all.}

proc setSearchText(e: Editor, text: string) =
  ## Test helper: set search text and position cursor at the end,
  ## matching the state after the user has typed the text.
  e.state.input.line.text = text
  e.state.input.line.cursor = text.charLen

proc backspace(e: Editor) =
  discard e.handleSearchModeKeyCombo(KeyCombo(isSpecial: true, special: skBackspace))

proc typeInSearch(e: Editor, ch: string) =
  ## `ch` typed on the search prompt.
  discard e.handleSearchModeKeyCombo(KeyCombo(isSpecial: false, char: ch))

proc handleSearchModeEvent(e: Editor, event: Event): ReplayOutcome =
  ## `event` typed on the search prompt.
  let wasTyped = e.state.keyTyped
  e.state.keyTyped = true
  defer:
    e.state.keyTyped = wasTyped
  e.handleSearchModeKeyCombo(eventToKeyCombo(event).get)

proc createTestEditorWithBuffer(content: string): Editor =
  let config = newEditorConfig()
  config.standard.mouse = true
  result = newEditor(config)
  let buf = newTextBuffer(content)
  result.windowManager.windows[0].setTab(buf)
  result.windowManager.windows[0].bufferIds = @[buf.id]
  result.windowManager.windows[0].viewport =
    ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftCell: 0)
  result.motionController.viewportManager.viewport = result.viewport
  result.state.mode = EditorMode.Normal

proc createTestEditorInHelpMode(): Editor =
  ## Create an editor in Help mode with helpViewerState set up.
  ## Uses help viewer content as the buffer.
  let helpState = newHelpViewerState()
  let helpBuffer = helpState.createHelpTextBuffer()
  result = createTestEditorWithBuffer("")
  result.windowManager.windows[0].setTab(helpBuffer)
  result.windowManager.windows[0].bufferIds = @[helpBuffer.id]
  result.windowManager.windows[0].modeState = ModeState(kind: mskHelp, help: helpState)
  result.state.mode = EditorMode.Help

proc createTestEditorInConfigMode(): (Editor, ConfigModeState) =
  ## Create an editor in Config mode with a ConfigModeState window.
  ## Config mode searches an item list, so the search machinery routes through
  ## activeConfigState() instead of the text-buffer search path.
  let e = createTestEditorWithBuffer("")
  let configState = newConfigModeState(e.config)
  e.windowManager.windows[0].modeState = ModeState(kind: mskConfig, config: configState)
  e.state.mode = EditorMode.Config
  (e, configState)

proc firstEditableName(state: ConfigModeState): string =
  ## Display name of the first non-section item (a guaranteed match target).
  for item in state.items:
    if item.kind != cvkSection:
      return item.displayName
  ""

suite "Search prompt - Backspace":
  test "Remove last ASCII character":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")

    backspace(e)

    check e.state.input.line.text == "ab"

  test "Remove last multibyte character (Japanese)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("検索")

    backspace(e)

    check e.state.input.line.text == "検"

  test "Remove last character from mixed ASCII and multibyte":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc日本語")

    backspace(e)

    check e.state.input.line.text == "abc日本"

  test "Backspace on single character leaves empty string":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("x")

    backspace(e)

    check e.state.input.line.text == ""

  test "Backspace on single multibyte character leaves empty string":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("あ")

    backspace(e)

    check e.state.input.line.text == ""

  test "Backspace on an empty prompt leaves it, as Vim's":
    let e = createTestEditorWithBuffer("hello")
    e.state.input.search.history = @[]
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("")

    backspace(e)

    check not e.state.isSearchOverlay
    check e.state.input.search.history.len == 0

  test "Backspace at the start of a prompt with text keeps it":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("ab")
    e.state.input.line.cursor = 0

    backspace(e)

    check e.state.isSearchOverlay
    check e.state.input.line.text == "ab"

suite "Search prompt - invalid bytes use the buffer character model":
  test "Pasted truncated lead byte counts every byte as a character":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)

    e.insertPastedTextInSearch("\xF0abc")

    check e.state.input.line.text == "\xF0abc"
    check e.state.input.line.cursor == 4

  test "Backspace after invalid paste removes the last byte only":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)

    e.insertPastedTextInSearch("\xF0abc")
    backspace(e)

    check e.state.input.line.text == "\xF0ab"
    check e.state.input.line.cursor == 3

  test "Paste completing a truncated lead byte keeps cursor at insertion end":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)

    e.state.input.line.text = "\xE2"
    e.state.input.line.cursor = 1
    e.insertPastedTextInSearch("\x82\xAC")

    check e.state.input.line.text == "\xE2\x82\xAC"
    check e.state.input.line.cursor == 1

suite "Search mode - leaving the overlay":
  test "finalizeSearch returns to the base mode":
    let e = createTestEditorWithBuffer("hello world")
    e.state.mode = EditorMode.Normal
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("world")

    discard finalizeSearch(e)

    check e.state.mode == EditorMode.Normal
    check not e.state.isSearchOverlay

  test "cancelSearch returns to the base mode":
    let e = createTestEditorWithBuffer("hello world")
    e.state.mode = EditorMode.Normal
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("world")

    cancelSearch(e)

    check e.state.mode == EditorMode.Normal
    check not e.state.isSearchOverlay

suite "Search mode - Help mode incremental search sync":
  test "performIncrementalSearch syncs selectedIndex on match":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    e.state.input.search.startPos = BufferPosition(line: 0, column: 0)
    e.setSearchText("Visual")

    performIncrementalSearch(e)

    let helpState = e.activeWindow.modeState.help
    # selectedIndex should be updated to the matched line
    check helpState.selectedIndex == e.cursor.line
    check helpState.selectedIndex > 0

  test "performIncrementalSearch syncs selectedIndex to startPos on no match":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    e.state.input.search.startPos = BufferPosition(line: 5, column: 0)
    e.setSearchText("zzzzNonExistentPattern")

    performIncrementalSearch(e)

    let helpState = e.activeWindow.modeState.help
    # selectedIndex should be restored to startPos line
    check helpState.selectedIndex == 5

  test "typing syncs selectedIndex in the help viewer":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    e.state.input.search.startPos = BufferPosition(line: 0, column: 0)

    # Type "Replace" character by character
    for ch in "Replace":
      typeInSearch(e, $ch)

    let helpState = e.activeWindow.modeState.help
    # selectedIndex should match cursor
    check helpState.selectedIndex == e.cursor.line
    check helpState.selectedIndex > 0

  test "finalizeSearch syncs selectedIndex from cursor position":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    e.state.input.search.startPos = BufferPosition(line: 0, column: 0)
    e.setSearchText("Visual")

    # Perform incremental search first to move cursor
    performIncrementalSearch(e)
    let cursorLineAfterSearch = e.cursor.line

    check finalizeSearch(e)

    let helpState = e.activeWindow.modeState.help
    # selectedIndex should match cursor position, not reset to first match
    check helpState.selectedIndex == cursorLineAfterSearch
    check helpState.searchQuery == "Visual"

  test "finalizeSearch without incsearch syncs selectedIndex":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = false
    e.state.input.search.startPos = BufferPosition(line: 0, column: 0)
    e.setSearchText("Insert")

    check finalizeSearch(e)

    let helpState = e.activeWindow.modeState.help
    check helpState.selectedIndex == e.cursor.line
    check helpState.searchQuery == "Insert"

  test "Backspace syncs selectedIndex":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    e.state.input.search.startPos = BufferPosition(line: 0, column: 0)
    e.setSearchText("Visual")

    # First search to set position
    performIncrementalSearch(e)
    let firstMatchLine = e.cursor.line

    # Add more characters to narrow search
    typeInSearch(e, " ")
    typeInSearch(e, "m")

    # Backspace to widen search again
    backspace(e)
    backspace(e)

    let helpState = e.activeWindow.modeState.help
    # Should be back to same position as first match
    check helpState.selectedIndex == firstMatchLine

  test "cancelSearch restores selectedIndex to startPos":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    e.state.input.search.startPos = BufferPosition(line: 10, column: 0)
    e.cursor = BufferPosition(line: 10, column: 0)
    e.setSearchText("Visual")

    # Move selectedIndex away from startPos via incremental search
    performIncrementalSearch(e)
    let helpState = e.activeWindow.modeState.help
    check helpState.selectedIndex != 10

    # Cancel should restore selectedIndex to startPos
    cancelSearch(e)
    check helpState.selectedIndex == 10

  test "A search keeps the way it went with its query, for n":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Backward)
    e.setSearchText("Visual")

    discard finalizeSearch(e)

    let help = e.activeWindow.modeState.help
    check help.searchQuery == "Visual"
    check help.searchDirection == Backward

suite "Search mode - Config mode integration":
  test "performIncrementalSearch moves selection to a match from the anchor":
    let (e, cfg) = createTestEditorInConfigMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    cfg.searchStartIndex = 0
    cfg.selectedIndex = 0
    let name = cfg.firstEditableName
    e.setSearchText(name)

    performIncrementalSearch(e)

    # Selection lands on an item matching the live text (the committed
    # searchQuery is only set on finalize, so match against the live text).
    check cfg.items[cfg.selectedIndex].matchesSearchQuery(cfg.config, name)
    check cfg.selectedIndex > 0

  test "performIncrementalSearch with empty text restores the anchor selection":
    let (e, cfg) = createTestEditorInConfigMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    cfg.searchStartIndex = 0
    cfg.selectedIndex = cfg.items.high
    e.setSearchText("")

    performIncrementalSearch(e)

    check cfg.selectedIndex == 0

  test "typing live-updates the selection in Config mode":
    let (e, cfg) = createTestEditorInConfigMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    cfg.searchStartIndex = 0
    cfg.selectedIndex = 0
    let name = cfg.firstEditableName

    for ch in name:
      typeInSearch(e, $ch)

    check cfg.items[cfg.selectedIndex].matchesSearchQuery(cfg.config, name)

  test "Backspace re-searches from the anchor on the shorter text":
    let (e, cfg) = createTestEditorInConfigMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    cfg.searchStartIndex = 0
    cfg.selectedIndex = 0
    let name = cfg.firstEditableName

    for ch in name:
      typeInSearch(e, $ch)
    backspace(e)

    # The selection still rests on an item matching the (shortened) live text.
    check e.state.input.line.text == name[0 ..< name.high]
    check cfg.items[cfg.selectedIndex].matchesSearchQuery(
      cfg.config, e.state.input.line.text
    )

  test "finalizeSearch commits the query and selects the first match":
    let (e, cfg) = createTestEditorInConfigMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    cfg.searchStartIndex = 0
    cfg.selectedIndex = 0
    let name = cfg.firstEditableName
    e.setSearchText(name)

    check finalizeSearch(e)

    check cfg.searchQuery == name
    check cfg.isItemMatched(cfg.selectedIndex)
    # The overlay is exited back to the base Config mode.
    check not e.state.isSearchOverlay()

  test "finalizeSearch without incsearch still commits and selects":
    let (e, cfg) = createTestEditorInConfigMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = false
    cfg.searchStartIndex = 0
    cfg.selectedIndex = 0
    let name = cfg.firstEditableName
    e.setSearchText(name)

    check finalizeSearch(e)

    check cfg.searchQuery == name
    check cfg.isItemMatched(cfg.selectedIndex)

  test "cancelSearch restores the selection to the anchor":
    let (e, cfg) = createTestEditorInConfigMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    cfg.searchStartIndex = 0
    cfg.selectedIndex = 0
    e.setSearchText(cfg.firstEditableName)

    performIncrementalSearch(e)
    check cfg.selectedIndex != 0

    cancelSearch(e)
    check cfg.selectedIndex == 0
    # A cancelled search must not commit a query.
    check not cfg.hasSearchQuery

  test "A search keeps the way it went with its query, for n":
    let (e, cfg) = createTestEditorInConfigMode()
    e.state.enterSearchOverlay(Backward)
    e.state.input.search.incsearch = true
    let name = cfg.firstEditableName
    e.setSearchText(name)

    check finalizeSearch(e)

    check cfg.searchQuery == name
    check cfg.searchDirection == Backward

suite "Incremental search - case insensitive highlighting":
  test "Case-insensitive search highlights uppercase matches":
    let e = createTestEditorWithBuffer("Hello World hello")
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    e.state.input.search.ignorecase = true
    e.state.input.search.smartcase = true
    e.state.input.search.startPos = BufferPosition(line: 0, column: 0)

    # Type lowercase "hello"
    typeInSearch(e, "h")
    typeInSearch(e, "e")
    typeInSearch(e, "l")
    typeInSearch(e, "l")
    typeInSearch(e, "o")

    # Search should find "hello" at column 12 (next match after startPos)
    check e.cursor == BufferPosition(line: 0, column: 12)

    # Verify shouldIgnoreCase returns true for lowercase pattern
    let ignCase = shouldIgnoreCase(
      e.state.input.line.text, e.state.input.search.ignorecase,
      e.state.input.search.smartcase,
    )
    check ignCase == true
    check e.state.input.line.text == "hello"

    # Verify findSearchMatchRanges finds BOTH uppercase and lowercase matches
    # This is what the rendering uses for highlighting
    let ranges = e.activeBuffer.findSearchMatchRanges(
      0, e.state.input.line.text, ignCase, e.state.input.search.last.match
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
    e.state.input.search.incsearch = true
    e.state.input.search.ignorecase = true
    e.state.input.search.smartcase = true
    e.state.input.search.startPos = BufferPosition(line: 0, column: 0)

    typeInSearch(e, "h")
    typeInSearch(e, "e")
    typeInSearch(e, "l")
    typeInSearch(e, "l")
    typeInSearch(e, "o")

    # Should find "hello" on line 1 (next after startPos)
    check e.cursor.line == 1
    check e.cursor.column == 0

    let ignCase = shouldIgnoreCase(
      e.state.input.line.text, e.state.input.search.ignorecase,
      e.state.input.search.smartcase,
    )
    check ignCase == true

    # Verify highlighting on line 0 (uppercase "Hello")
    let ranges0 = e.activeBuffer.findSearchMatchRanges(
      0, e.state.input.line.text, ignCase, e.state.input.search.last.match
    )
    check ranges0.len == 1
    check ranges0[0].startCol == 0
    check ranges0[0].endCol == 5

    # Verify highlighting on line 1 (lowercase "hello")
    let ranges1 = e.activeBuffer.findSearchMatchRanges(
      1, e.state.input.line.text, ignCase, e.state.input.search.last.match
    )
    check ranges1.len == 1
    check ranges1[0].startCol == 0
    check ranges1[0].endCol == 5

    # Verify highlighting on line 2 (all-caps "HELLO")
    let ranges2 = e.activeBuffer.findSearchMatchRanges(
      2, e.state.input.line.text, ignCase, e.state.input.search.last.match
    )
    check ranges2.len == 1
    check ranges2[0].startCol == 0
    check ranges2[0].endCol == 5

  test "A pattern being typed is a substring search after a * search":
    ## Regression test: / and ? are substring searches, so a previous * must
    ## not make the pattern being typed match whole words only, for either
    ## cursor movement or highlighting.
    let e = createTestEditorWithBuffer("abc foobar foo baz")
    # Simulate * leaving a whole word search behind
    e.state.input.search.last = SearchSpec(pattern: "abc", match: smWord)

    e.state.enterSearchOverlay(Forward)
    # The overlay does not touch the last search
    check e.state.input.search.last == SearchSpec(pattern: "abc", match: smWord)

    e.state.input.search.incsearch = true
    e.state.input.search.ignorecase = true
    e.state.input.search.smartcase = true

    typeInSearch(e, "f")
    typeInSearch(e, "o")
    typeInSearch(e, "o")

    # findNext finds "foo" in "foobar" at col 4
    check e.cursor == BufferPosition(line: 0, column: 4)

    let ignCase = shouldIgnoreCase(
      e.state.input.line.text, e.state.input.search.ignorecase,
      e.state.input.search.smartcase,
    )

    # The highlight is a substring search too, so it finds both "foo" in
    # "foobar" (col 4) and standalone "foo" (col 11)
    let ranges =
      e.activeBuffer.findSearchMatchRanges(0, e.state.input.line.text, ignCase, smRegex)
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

    check e.state.input.line.cursor == 2

  test "Left arrow does not move past start":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")
    e.state.input.line.cursor = 0

    discard handleSearchModeEvent(e, makeLeftEvent())

    check e.state.input.line.cursor == 0

  test "Right arrow moves cursor right":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")
    e.state.input.line.cursor = 0

    discard handleSearchModeEvent(e, makeRightEvent())

    check e.state.input.line.cursor == 1

  test "Right arrow does not move past end":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")

    discard handleSearchModeEvent(e, makeRightEvent())

    check e.state.input.line.cursor == 3

  test "Left arrow steps over multibyte character":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("検索")

    discard handleSearchModeEvent(e, makeLeftEvent())

    check e.state.input.line.cursor == 1

  test "Home moves cursor to start":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")

    discard handleSearchModeEvent(e, makeHomeEvent())

    check e.state.input.line.cursor == 0

  test "End moves cursor to end":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")
    e.state.input.line.cursor = 0

    discard handleSearchModeEvent(e, makeEndEvent())

    check e.state.input.line.cursor == 3

suite "Search mode - character insertion at cursor":
  test "Insert character at cursor position":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("ac")
    e.state.input.line.cursor = 1

    discard handleSearchModeEvent(e, makeCharEvent("b"))

    check e.state.input.line.text == "abc"
    check e.state.input.line.cursor == 2

  test "Insert character at start":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("bc")
    e.state.input.line.cursor = 0

    discard handleSearchModeEvent(e, makeCharEvent("a"))

    check e.state.input.line.text == "abc"
    check e.state.input.line.cursor == 1

  test "Insert character at end (append)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("ab")

    discard handleSearchModeEvent(e, makeCharEvent("c"))

    check e.state.input.line.text == "abc"
    check e.state.input.line.cursor == 3

  test "Insert multibyte character at cursor":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("a検")
    e.state.input.line.cursor = 1

    discard handleSearchModeEvent(e, makeCharEvent("索"))

    check e.state.input.line.text == "a索検"
    check e.state.input.line.cursor == 2

suite "Search mode - Delete and Backspace at cursor":
  test "Delete removes character at cursor":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")
    e.state.input.line.cursor = 1

    discard handleSearchModeEvent(e, makeDeleteEvent())

    check e.state.input.line.text == "ac"
    check e.state.input.line.cursor == 1

  test "Delete at end erases the character before it, as Vim's":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")

    discard handleSearchModeEvent(e, makeDeleteEvent())

    check e.state.input.line.text == "ab"
    check e.state.input.line.cursor == 2

  test "Delete on an empty prompt leaves it":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)

    discard handleSearchModeEvent(e, makeDeleteEvent())

    check not e.state.isSearchOverlay

  test "Backspace removes character before cursor":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")
    e.state.input.line.cursor = 2

    discard handleSearchModeEvent(e, makeBackspaceEvent())

    check e.state.input.line.text == "ac"
    check e.state.input.line.cursor == 1

  test "Backspace at start does nothing":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("abc")
    e.state.input.line.cursor = 0

    discard handleSearchModeEvent(e, makeBackspaceEvent())

    check e.state.input.line.text == "abc"
    check e.state.input.line.cursor == 0

suite "Search mode - enterSearchOverlay cursor init":
  test "enterSearchOverlay resets cursor to 0":
    let e = createTestEditorWithBuffer("hello")
    e.state.input.line.cursor = 5
    e.state.enterSearchOverlay(Forward)
    check e.state.input.line.cursor == 0

suite "Search mode - empty Enter repeats the last search":
  test "Empty input repeats the previous search with incsearch":
    let e = createTestEditorWithBuffer("alpha\ntarget\nbeta\ntarget\n")
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    e.setSearchText("target")
    performIncrementalSearch(e)
    check finalizeSearch(e)
    check e.cursor == BufferPosition(line: 1, column: 0)

    e.state.enterSearchOverlay(Forward)
    check finalizeSearch(e)

    check e.cursor == BufferPosition(line: 3, column: 0)
    check e.state.input.search.last.pattern == "target"

  test "Empty input repeats the previous search without incsearch":
    let e = createTestEditorWithBuffer("alpha\ntarget\nbeta\ntarget\n")
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = false
    e.setSearchText("target")
    check finalizeSearch(e)
    check e.cursor == BufferPosition(line: 1, column: 0)

    e.state.enterSearchOverlay(Forward)
    check finalizeSearch(e)

    check e.cursor == BufferPosition(line: 3, column: 0)

  test "Empty input repeats backward with ?":
    let e = createTestEditorWithBuffer("target\nalpha\ntarget\nbeta\n")
    e.cursor = BufferPosition(line: 3, column: 0)
    e.state.enterSearchOverlay(Backward)
    e.state.input.search.incsearch = true
    e.setSearchText("target")
    performIncrementalSearch(e)
    check finalizeSearch(e)
    check e.cursor == BufferPosition(line: 2, column: 0)

    e.state.enterSearchOverlay(Backward)
    check finalizeSearch(e)

    check e.cursor == BufferPosition(line: 0, column: 0)

  test "Empty input with no previous search reports E35":
    let e = createTestEditorWithBuffer("alpha\ntarget\n")
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true

    check not finalizeSearch(e)

    check e.cursor == BufferPosition(line: 0, column: 0)
    check e.state.input.search.last.pattern == ""
    check e.state.statusMessage == "E35: No previous regular expression"
    check not e.state.isSearchOverlay

  test "A repeat searches from the prompt anchor, not a stale incsearch match":
    let e = createTestEditorWithBuffer("target A\nbeta\ntarget B\nqqq\n")
    e.state.input.search.last.pattern = "target"
    e.cursor = BufferPosition(line: 3, column: 0)
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true

    # Type a pattern that matches elsewhere, then erase it again
    for ch in "beta":
      typeInSearch(e, $ch)
    for _ in 0 ..< "beta".len:
      backspace(e)

    check finalizeSearch(e)

    # Wraps from line 3, so the first match is line 0 - not line 2, which is
    # what searching from the erased "beta" match would have found.
    check e.cursor == BufferPosition(line: 0, column: 0)

  test "A search for the only match at the cursor finds it again":
    let e = createTestEditorWithBuffer("foo bar\n")
    e.state.input.search.incsearch = false
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("foo")

    check finalizeSearch(e)

    check e.cursor == BufferPosition(line: 0, column: 0)
    check "Pattern not found" notin e.state.statusMessage
    # It found something, so Vim records the jump.
    check e.state.jumpList.list.len == 1

  test "An incremental search for the only match at the cursor records a jump":
    let e = createTestEditorWithBuffer("foo bar\n")
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    e.setSearchText("foo")
    performIncrementalSearch(e)
    check finalizeSearch(e)

    check e.cursor == BufferPosition(line: 0, column: 0)
    check e.state.jumpList.list.len == 1

  test "A repeat keeps the whole word mode of a * search":
    let e = createTestEditorWithBuffer("target\ntargeted\ntarget\n")
    e.state.input.search.last = SearchSpec(pattern: "target", match: smWord)
    e.state.enterSearchOverlay(Forward)

    check finalizeSearch(e)

    check e.state.input.search.last == SearchSpec(pattern: "target", match: smWord)

  test "A cancelled search leaves the * search it was opened over":
    let e = createTestEditorWithBuffer("target\ntargeted\n")
    e.state.input.search.last = SearchSpec(pattern: "target", match: smWord)
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("targe")

    cancelSearch(e)

    check e.state.input.search.last == SearchSpec(pattern: "target", match: smWord)

  test "A repeat does not push a duplicate history entry":
    let e = createTestEditorWithBuffer("alpha\ntarget\nbeta\ntarget\n")
    e.state.enterSearchOverlay(Forward)
    e.setSearchText("target")
    discard finalizeSearch(e)
    let historyAfterSearch = e.state.input.search.history

    e.state.enterSearchOverlay(Forward)
    check finalizeSearch(e)

    check e.state.input.search.history == historyAfterSearch

  test "A repeat records the prompt anchor in the jump list":
    let e = createTestEditorWithBuffer("alpha\ntarget\nbeta\ntarget\n")
    e.state.input.search.last.pattern = "target"
    e.cursor = BufferPosition(line: 2, column: 0)
    e.state.enterSearchOverlay(Forward)

    check finalizeSearch(e)

    check e.cursor == BufferPosition(line: 3, column: 0)
    check e.state.jumpList.list.len == 1
    check e.state.jumpList.list[^1].line == 2

  test "Config mode: a repeat advances to the next match":
    let (e, cfg) = createTestEditorInConfigMode()
    e.state.enterSearchOverlay(Forward)
    cfg.searchStartIndex = 0
    cfg.selectedIndex = 0
    e.setSearchText("e")
    check finalizeSearch(e)
    let firstMatch = cfg.selectedIndex

    # Reopening the prompt re-anchors on the current selection, as the
    # dispatcher does when / is pressed.
    e.state.enterSearchOverlay(Forward)
    cfg.searchStartIndex = cfg.selectedIndex
    check finalizeSearch(e)

    check cfg.selectedIndex != firstMatch
    check cfg.items[cfg.selectedIndex].matchesSearchQuery(cfg.config, "e")

  test "Config mode: a backward repeat steps back to the previous match":
    let (e, cfg) = createTestEditorInConfigMode()
    e.state.enterSearchOverlay(Forward)
    cfg.searchStartIndex = 0
    cfg.selectedIndex = 0
    e.setSearchText("e")
    check finalizeSearch(e)
    let firstMatch = cfg.selectedIndex

    e.state.enterSearchOverlay(Forward)
    cfg.searchStartIndex = cfg.selectedIndex
    check finalizeSearch(e)
    let secondMatch = cfg.selectedIndex

    e.state.enterSearchOverlay(Backward)
    cfg.searchStartIndex = cfg.selectedIndex
    check finalizeSearch(e)

    check secondMatch != firstMatch
    check cfg.selectedIndex == firstMatch

suite "Search mode - jump list and viewport on a failed or erased search":
  test "A failed search does not record a jump":
    let e = createTestEditorWithBuffer("alpha\nbeta\n")
    e.cursor = BufferPosition(line: 1, column: 0)
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    e.setSearchText("zzzz")
    performIncrementalSearch(e)
    check not finalizeSearch(e)

    check e.cursor == BufferPosition(line: 1, column: 0)
    check e.state.jumpList.list.len == 0

  test "An invalid pattern brings the cursor back to the anchor":
    let e = createTestEditorWithBuffer("foo\nabc\nxyz\nabc\nend\n")
    e.cursor = BufferPosition(line: 1, column: 0)
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    for ch in ["a", "b"]:
      typeInSearch(e, ch)
    check e.cursor == BufferPosition(line: 3, column: 0)

    typeInSearch(e, "(")
    check e.cursor == BufferPosition(line: 1, column: 0)
    check e.state.statusMessage == ""

    check not finalizeSearch(e)
    check e.cursor == BufferPosition(line: 1, column: 0)
    check e.state.jumpList.list.len == 0
    check e.state.statusMessage == "Invalid regex: ab("
    check e.state.input.search.last.pattern == "ab("

  test "A valid pattern that matches nothing reports it on Enter only":
    let e = createTestEditorWithBuffer("alpha\nbeta\n")
    e.cursor = BufferPosition(line: 1, column: 0)
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    for ch in "zzz":
      typeInSearch(e, $ch)
    check e.state.statusMessage == ""

    check not finalizeSearch(e)
    check e.cursor == BufferPosition(line: 1, column: 0)
    check e.state.statusMessage == "Pattern not found: zzz"

  test "Help mode: an invalid pattern still becomes the help search query":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    for ch in "ab(":
      typeInSearch(e, $ch)
    check not finalizeSearch(e)

    check e.state.statusMessage == "Invalid regex: ab("
    check e.activeWindow.modeState.help.searchQuery == "ab("

  test "A reload that drops the incsearch match searches again from the anchor":
    let e = createTestEditorWithBuffer("x\nfoo\nfoo\nfoo\n")
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    for ch in "foo":
      typeInSearch(e, $ch)
    check e.cursor == BufferPosition(line: 1, column: 0)

    e.invalidatePositionStateForBuffer(e.activeBuffer)

    check finalizeSearch(e)
    check e.cursor == BufferPosition(line: 1, column: 0)
    check e.state.statusMessage == "Found: foo"

  test "Config mode: a query that matches nothing reports it on Enter":
    let (e, cfg) = createTestEditorInConfigMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    cfg.searchStartIndex = 0
    cfg.selectedIndex = 0
    for ch in "zzzzNoSuchItem":
      typeInSearch(e, $ch)
    check not finalizeSearch(e)

    check cfg.selectedIndex == 0
    check e.state.statusMessage == "Pattern not found: zzzzNoSuchItem"

  test "An invalid pattern brings the viewport back to the anchor in a backward search":
    var content = ""
    for i in 0 ..< 200:
      content.add(if i == 150: "needle\n" else: "aaaa\n")
    let e = createTestEditorWithBuffer(content)
    e.state.enterSearchOverlay(Backward)
    e.state.input.search.incsearch = true

    for ch in "needle":
      typeInSearch(e, $ch)
    check e.cursor.line == 150
    check e.viewport.topLine > 0

    typeInSearch(e, "(")
    check e.cursor.line == 0
    check e.viewport.topLine == 0

  test "Config mode: a pattern that stops matching brings the selection back":
    let (e, cfg) = createTestEditorInConfigMode()
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    cfg.searchStartIndex = 0
    cfg.selectedIndex = 0
    for ch in cfg.firstEditableName:
      typeInSearch(e, $ch)
    check cfg.selectedIndex > 0

    typeInSearch(e, "\x01")
    check cfg.selectedIndex == 0

  test "Enter wraps back to the only match under the cursor":
    for incsearch in [true, false]:
      let e = createTestEditorWithBuffer("foo\nbar\n")
      e.state.enterSearchOverlay(Forward)
      e.state.input.search.incsearch = incsearch
      for ch in "foo":
        typeInSearch(e, $ch)
      check finalizeSearch(e)

      check e.cursor == BufferPosition(line: 0, column: 0)
      check e.state.statusMessage == "Found: foo"
      check e.state.jumpList.list.len == 1

  test "A failed search leaves the cursor alone without incsearch":
    let e = createTestEditorWithBuffer("alpha\nbeta\n")
    e.cursor = BufferPosition(line: 1, column: 2)
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = false
    e.state.input.search.startPos = BufferPosition(line: 0, column: 0)
    e.setSearchText("zzzz")
    check not finalizeSearch(e)

    check e.cursor == BufferPosition(line: 1, column: 2)
    check e.state.jumpList.list.len == 0

  test "Without incsearch Enter scrolls from the current view":
    var content = ""
    for i in 0 ..< 200:
      content.add(if i == 150: "needle\n" else: "aaaa\n")
    let e = createTestEditorWithBuffer(content)
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = false
    e.viewport.topLine = 140
    e.setSearchText("needle")
    check finalizeSearch(e)

    check e.cursor.line == 150
    check e.viewport.topLine == 140

  test "The prompt takes the message line until Enter":
    for typed in ["b", "zz", ""]:
      let e = createTestEditorWithBuffer("abc\nbcd\n")
      e.state.statusMessage = "written"
      e.state.enterSearchOverlay(Forward)
      e.state.input.search.incsearch = true
      check e.state.statusMessage == ""

      for ch in typed:
        typeInSearch(e, $ch)
      backspace(e)
      check e.state.statusMessage == ""

      cancelSearch(e)
      check e.state.statusMessage == ""

  test "Config mode: a new search drops the last one's message":
    let (e, cfg) = createTestEditorInConfigMode()
    e.state.statusMessage = "Pattern not found: zzz"
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true
    check e.state.statusMessage == ""

    cfg.searchStartIndex = 0
    cfg.selectedIndex = 0
    let name = cfg.firstEditableName
    for ch in name:
      typeInSearch(e, $ch)
    check e.state.statusMessage == ""

    check finalizeSearch(e)
    check e.state.statusMessage == "Found: " & name

  test "A failed search does not record a jump without incsearch":
    let e = createTestEditorWithBuffer("alpha\nbeta\n")
    e.cursor = BufferPosition(line: 1, column: 0)
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = false
    e.setSearchText("zzzz")
    check not finalizeSearch(e)

    check e.state.jumpList.list.len == 0

  test "Erasing the pattern brings the viewport back to the anchor":
    var content = ""
    for i in 0 ..< 200:
      content.add(if i == 150: "needle\n" else: "aaaa\n")
    let e = createTestEditorWithBuffer(content)
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true

    for ch in "needle":
      typeInSearch(e, $ch)
    check e.cursor.line == 150
    check e.viewport.topLine > 0

    for _ in 0 ..< "needle".len:
      backspace(e)

    check e.cursor.line == 0
    check e.viewport.topLine == 0

  test "A cancelled search brings the viewport back to the anchor":
    var content = ""
    for i in 0 ..< 200:
      content.add(if i == 150: "needle\n" else: "aaaa\n")
    let e = createTestEditorWithBuffer(content)
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true

    for ch in "needle":
      typeInSearch(e, $ch)
    cancelSearch(e)

    check e.cursor.line == 0
    check e.viewport.topLine == 0

  test "Clearing the prompt past the newest history entry restores the viewport":
    var content = ""
    for i in 0 ..< 200:
      content.add(if i == 150: "needle\n" else: "aaaa\n")
    let e = createTestEditorWithBuffer(content)
    e.state.input.search.history = @["needle"]
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true

    check handleSearchModeKeyCombo(
      e, KeyCombo(isSpecial: true, special: skUp, fnNum: 0, modifiers: {})
    ) == roContinue
    check e.cursor.line == 150
    check e.viewport.topLine > 0

    check handleSearchModeKeyCombo(
      e, KeyCombo(isSpecial: true, special: skDown, fnNum: 0, modifiers: {})
    ) == roContinue

    check e.state.input.line.text == ""
    check e.cursor.line == 0
    check e.viewport.topLine == 0

  test "A cancelled search puts back what the window showed":
    var content = ""
    for i in 0 ..< 200:
      content.add(if i == 150: "needle\n" else: "aaaa\n")
    let e = createTestEditorWithBuffer(content)
    e.viewport.topLine = 40
    e.cursor = BufferPosition(line: 45, column: 0)
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.incsearch = true

    for ch in "needle":
      typeInSearch(e, $ch)
    check e.viewport.topLine > 100
    cancelSearch(e)

    check e.cursor.line == 45
    check e.viewport.topLine == 40

  test "Each match scrolls from what the window showed as the search began":
    var content = ""
    for i in 0 ..< 200:
      content.add(
        case i
        of 38: "a\n"
        of 33: "ab\n"
        of 28: "abc\n"
        else: "zzzz\n"
      )
    let e = createTestEditorWithBuffer(content)
    e.viewport.topLine = 41
    e.cursor = BufferPosition(line: 49, column: 0)
    e.state.enterSearchOverlay(Backward)
    e.state.input.search.incsearch = true

    typeInSearch(e, "a")
    check e.viewport.topLine == 38
    typeInSearch(e, "b")
    check e.viewport.topLine == 33
    # Far above the window as the search began, the match comes to the middle.
    typeInSearch(e, "c")
    check e.cursor.line == 28
    check e.viewport.topLine < 28

  test "A search begun with no window to show keeps no earlier view":
    let e = createTestEditorWithBuffer("a\nb\n")
    e.state.noteSearchStart()
    check e.state.input.search.startView.isSome
    let viewport = e.state.activeWindow.viewport
    e.state.activeWindow.viewport = nil
    e.state.noteSearchStart()
    e.state.activeWindow.viewport = viewport
    check e.state.input.search.startView.isNone

  test "A repeat of a * search keeps the word boundaries":
    let e = createTestEditorWithBuffer("target\ntargeted\ntarget\n")
    e.state.input.search.last = SearchSpec(pattern: "target", match: smWord)
    e.state.enterSearchOverlay(Forward)

    check finalizeSearch(e)

    check e.cursor == BufferPosition(line: 2, column: 0)

suite "Search highlight after :noh":
  const
    Esc = KeyCombo(isSpecial: true, special: skEscape)
    Enter = KeyCombo(isSpecial: true, special: skEnter)

  proc matchesOnFirstLine(e: Editor): int =
    let ctx = RenderContext(windowMode: EditorMode.Normal)
    e.newLineStyleContext(e.activeBuffer, 0, e.activeBuffer.getLine(0), ctx).searchRanges.len

  proc openSearch(e: Editor, typed = "") =
    e.state.enterSearchOverlay(Forward)
    for ch in typed:
      e.typeInSearch($ch)

  proc run(e: Editor, typed: string) =
    e.openSearch(typed)
    discard e.handleSearchModeKeyCombo(Enter)

  template nohAfterSearch(content = "foo bar foo"): Editor =
    let
      text = content
      noh = createTestEditorWithBuffer(text)
    noh.state.keyTyped = true
    noh.state.input.search.hlsearch = true
    noh.state.input.search.incsearch = true
    noh.run("foo")
    check noh.matchesOnFirstLine == text.toLowerAscii.count("foo")
    check noh.executeCommandOverlay(":noh") == roContinue
    check noh.matchesOnFirstLine == 0
    noh

  test "The next search shows matches again":
    let e = nohAfterSearch()
    e.run("bar")
    check e.matchesOnFirstLine == 1

  test "Repeating the search with an empty prompt shows them again":
    let e = nohAfterSearch()
    e.run("")
    check e.matchesOnFirstLine == 2

  test "An empty prompt keeps them hidden, and so does leaving it":
    let e = nohAfterSearch()
    e.openSearch()
    check e.matchesOnFirstLine == 0
    discard e.handleSearchModeKeyCombo(Esc)
    check e.matchesOnFirstLine == 0

  test "Typed text shows its matches, and leaving hides them again":
    let e = nohAfterSearch()
    e.openSearch("fo")
    check e.matchesOnFirstLine == 2
    discard e.handleSearchModeKeyCombo(Esc)
    check e.matchesOnFirstLine == 0

  test "A search an operator cancels stays hidden":
    let e = nohAfterSearch()
    e.state.pendingInput.pendingOperator = some(PendingOperator())
    e.openSearch("fo")
    discard e.handleSearchModeKeyCombo(Esc)
    check e.state.pendingInput.pendingOperator.isNone
    check e.matchesOnFirstLine == 0

  test ":set hlsearch shows them again":
    let e = nohAfterSearch()
    check e.executeCommandOverlay(":set hlsearch") == roContinue
    check e.matchesOnFirstLine == 2

  test ":noh with 'hlsearch' off does not outlast turning it on":
    let e = nohAfterSearch()
    check e.executeCommandOverlay(":set nohlsearch") == roContinue
    check e.executeCommandOverlay(":noh") == roContinue
    check e.executeCommandOverlay(":set hlsearch") == roContinue
    check e.matchesOnFirstLine == 2

  test "n after :s keeps going the way the last search went":
    let e = createTestEditorWithBuffer("bar\nx\nbar\nx\nbar\nx")
    e.cursor = BufferPosition(line: 3, column: 0)
    e.state.enterSearchOverlay(Backward)
    e.setSearchText("bar")
    discard e.handleSearchModeKeyCombo(Enter)
    check e.cursor.line == 2
    check e.executeCommandOverlay(":s/bar/x/") == roContinue
    check e.state.searchLast(e.activeBuffer, e.cursor, false, 1).get.line == 0

  test "A :s being typed shows its pattern, and leaving hides it again":
    let e = nohAfterSearch()
    e.state.enterCommandOverlay()
    e.state.input.line.text = "s/bar"
    check e.matchesOnFirstLine == 1
    e.state.exitOverlay()
    check e.matchesOnFirstLine == 0

  test "A :s being typed with an empty pattern shows the last search":
    let e = nohAfterSearch()
    e.state.enterCommandOverlay()
    e.state.input.line.text = "s/"
    check e.matchesOnFirstLine == 0
    # As its cursor jump does, once the delimiter ends the empty pattern.
    e.state.input.line.text = "s//"
    check e.matchesOnFirstLine == 2

  test "Without 'incsearch' a pattern typed after :noh stays hidden":
    let e = nohAfterSearch()
    e.state.input.search.incsearch = false
    e.openSearch("fo")
    check e.matchesOnFirstLine == 0
    discard e.handleSearchModeKeyCombo(Esc)

    e.state.enterCommandOverlay()
    e.state.input.line.text = "s/fo"
    check e.matchesOnFirstLine == 0

  test "A :s being typed highlights the plain string it replaces":
    let e = nohAfterSearch("foo abc a.c foo(")
    e.state.enterCommandOverlay()
    e.state.input.line.text = "s/a.c"
    check e.matchesOnFirstLine == 1
    e.state.input.line.text = "s/foo("
    check e.matchesOnFirstLine == 1

  test "'smartcase' holds for the :s being typed":
    let e = nohAfterSearch("Foo foo")
    e.state.input.search.ignorecase = true
    e.state.input.search.smartcase = true
    e.state.enterCommandOverlay()
    e.state.input.line.text = "s/Foo"
    check e.matchesOnFirstLine == 1
    e.state.input.line.text = "s/foo"
    check e.matchesOnFirstLine == 2

  test "An executed :s ends :noh and shows the matches it made the last search":
    let e = nohAfterSearch()
    check e.executeCommandOverlay(":s/foo/X/") == roContinue
    check not e.state.input.search.hlsearchTempDisabled
    check e.state.input.search.last ==
      SearchSpec(pattern: "foo", match: smPlain, direction: Forward)
    check e.matchesOnFirstLine == 1

  test "An executed :s replaces the last search, not just ends the hide":
    let e = nohAfterSearch()
    check e.executeCommandOverlay(":s/bar/baz/") == roContinue
    check e.state.input.search.last.pattern == "bar"
    check e.state.input.search.last.match == smPlain
    check e.matchesOnFirstLine == 0

  test "A :s that finds nothing still ends :noh, as Vim does":
    let e = nohAfterSearch()
    check e.executeCommandOverlay(":s/zzz/x/") == roAbort
    check not e.state.input.search.hlsearchTempDisabled
    check e.state.input.search.last.pattern == "zzz"
    check e.state.input.search.history[0] == "zzz"

  test "An executed :s goes into the search history":
    let e = nohAfterSearch()
    check e.executeCommandOverlay(":s/bar/baz/") == roContinue
    check e.state.input.search.history[0] == "bar"

  test "A :s refused for its range leaves the last search and :noh":
    let e = nohAfterSearch()
    check e.executeCommandOverlay(":999s/bar/x/") == roAbort
    check e.state.input.search.last.pattern == "foo"
    check e.state.input.search.history[0] == "foo"
    check e.state.input.search.hlsearchTempDisabled

  test "A :s refused for a read-only buffer leaves the last search and :noh":
    let e = nohAfterSearch()
    e.activeBuffer.readOnly = true
    check e.executeCommandOverlay(":s/bar/x/") == roAbort
    check e.state.input.search.last.pattern == "foo"
    check e.state.input.search.hlsearchTempDisabled

  test "An escaped delimiter in a :s is the character itself":
    let e = nohAfterSearch("foo a/b")
    e.state.enterCommandOverlay()
    e.state.input.line.text = "s/a\\/b"
    check e.matchesOnFirstLine == 1
    e.state.exitOverlay()
    check e.executeCommandOverlay(":s/a\\/b/x/") == roContinue
    check e.activeBuffer.getLine(0) == "foo x"
    check e.state.input.search.last.pattern == "a/b"

  test "An escaped backslash in a :s is the character itself":
    let e = nohAfterSearch("foo C:\\")
    check e.executeCommandOverlay(":s/C:\\\\/x/") == roContinue
    check e.activeBuffer.getLine(0) == "foo x"
    check e.state.input.search.last.pattern == "C:\\"

  test "Without 'incsearch' a typed pattern leaves the last search drawn":
    let e = nohAfterSearch()
    check e.executeCommandOverlay(":set hlsearch") == roContinue
    e.state.input.search.incsearch = false
    e.openSearch("bar")
    check e.matchesOnFirstLine == 2
    discard e.handleSearchModeKeyCombo(Esc)

    e.state.enterCommandOverlay()
    e.state.input.line.text = "s/bar"
    check e.matchesOnFirstLine == 2

  test ":s replaces what the last search it leaves shows":
    let e = nohAfterSearch("Foo Foo foo")
    check e.executeCommandOverlay(":s/foo/x/") == roContinue
    check e.activeBuffer.getLine(0) == "x Foo foo"
    check e.matchesOnFirstLine == 2

  test "An upper case letter in :s makes it and its last search exact":
    let e = nohAfterSearch("foo Foo Foo")
    check e.executeCommandOverlay(":s/Foo/x/") == roContinue
    check e.activeBuffer.getLine(0) == "foo x Foo"
    check e.matchesOnFirstLine == 1

  test "The last of the `i` and `I` flags decides for the :s alone":
    let e = nohAfterSearch("foo Foo Foo")
    check e.executeCommandOverlay(":s/Foo/x/i") == roContinue
    check e.activeBuffer.getLine(0) == "x Foo Foo"
    check e.matchesOnFirstLine == 2
    check e.executeCommandOverlay(":s/Foo/y/iI") == roContinue
    check e.activeBuffer.getLine(0) == "x y Foo"
    check e.executeCommandOverlay(":s/foo/z/I") == roAbort
    check e.activeBuffer.getLine(0) == "x y Foo"

  test "A capital beyond ASCII makes :s exact":
    let e = nohAfterSearch("foo \u00c9a \u00e9a")
    check e.executeCommandOverlay(":s/\u00c9a/Y/g") == roContinue
    check e.activeBuffer.getLine(0) == "foo Y \u00e9a"

  test "A :s refused for its trailing characters leaves the last search":
    let e = nohAfterSearch("foo Foo")
    check e.executeCommandOverlay(":s/Foo/Y/gxi") == roAbort
    check e.activeBuffer.getLine(0) == "foo Foo"
    check e.state.input.search.last.pattern == "foo"

  test ":s with `n` counts, and makes its pattern the last search":
    let e = nohAfterSearch("foo Foo")
    check e.executeCommandOverlay(":%s/foo/x/gn") == roContinue
    check e.state.statusMessage == "2 matches on 1 line"
    check e.activeBuffer.getLine(0) == "foo Foo"
    check e.state.input.search.last.pattern == "foo"
    check e.matchesOnFirstLine == 2

  test ":s with `n` keeps the last search it can run on a read-only buffer":
    let e = nohAfterSearch("foo bar")
    e.activeBuffer.readOnly = true
    check e.executeCommandOverlay(":s/bar/x/n") == roContinue
    check e.state.input.search.last.pattern == "bar"

  test "A :s refused for `c` leaves the buffer and the last search":
    let e = nohAfterSearch("foo foo")
    check e.executeCommandOverlay(":s/oo/x/gc") == roAbort
    check e.activeBuffer.getLine(0) == "foo foo"
    check e.state.input.search.last.pattern == "foo"

  test "An empty :s pattern is the last search's":
    let e = nohAfterSearch("foo bar foo")
    check e.executeCommandOverlay(":s//X/") == roContinue
    check e.activeBuffer.getLine(0) == "X bar foo"
    check e.state.input.search.last.pattern == "foo"
    check e.state.input.search.last.match == smRegex

  test "An empty :%s pattern replaces every match of the last search":
    let e = nohAfterSearch("foo bar foo")
    check e.executeCommandOverlay(":%s//X/g") == roContinue
    check e.activeBuffer.getLine(0) == "X bar X"

  test "'smartcase' holds on the reused :s pattern":
    let e = createTestEditorWithBuffer("Foo foo FOO")
    e.state.keyTyped = true
    e.state.input.search.ignorecase = true
    e.state.input.search.smartcase = true
    e.state.setLastSearch(SearchSpec(pattern: "Foo", match: smPlain))
    check e.executeCommandOverlay(":%s//X/g") == roContinue
    check e.activeBuffer.getLine(0) == "X foo FOO"

  test "An empty :s pattern matches as the last search did":
    let e = createTestEditorWithBuffer("foobar foo")
    e.state.keyTyped = true
    e.state.setLastSearch(SearchSpec(pattern: "foo", match: smWord))
    check e.executeCommandOverlay(":%s//X/g") == roContinue
    check e.activeBuffer.getLine(0) == "foobar X"
    # `n` after it still finds words, as Vim keeps the pattern it reused.
    check e.state.input.search.last.match == smWord

  test "Only a typed :s pattern goes into the search history":
    let e = createTestEditorWithBuffer("foo bar")
    e.state.keyTyped = true
    e.state.input.search.history = @["older", "foo"]
    e.state.setLastSearch(SearchSpec(pattern: "foo", match: smWord))
    check e.executeCommandOverlay(":s//X/") == roContinue
    check e.state.input.search.history == @["older", "foo"]
    check e.executeCommandOverlay(":s/bar/Y/") == roContinue
    check e.state.input.search.history[0] == "bar"

  test "An empty :s pattern runs a regex the last search ran":
    let e = createTestEditorWithBuffer("fao f.o fzo")
    e.state.keyTyped = true
    e.state.setLastSearch(SearchSpec(pattern: "f.o", match: smRegex))
    check e.executeCommandOverlay(":s//X/g") == roContinue
    check e.activeBuffer.getLine(0) == "X X X"

  test "An empty :s pattern with no last search is E35":
    let e = createTestEditorWithBuffer("foo")
    e.state.keyTyped = true
    check e.executeCommandOverlay(":s//X/") == roAbort
    check e.activeBuffer.getLine(0) == "foo"
    check e.state.statusMessage == "E35: No previous regular expression"
