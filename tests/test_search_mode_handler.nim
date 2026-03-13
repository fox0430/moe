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

import std/[unittest, options]

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/editor {.all.}
import ../src/moepkg/config {.all.}
import ../src/moepkg/help_viewer {.all.}
import ../src/moepkg/command_handlers/search_mode_handler {.all.}

proc createTestEditorWithBuffer(content: string): Editor =
  let config = newEditorConfig()
  config.standard.mouse = true
  result = newEditor(config)
  result.textBuffer = newTextBuffer(content)
  result.windowManager.windows[0].buffer = result.textBuffer
  result.windowManager.windows[0].bufferList = @[result.textBuffer]
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
  result.windowManager.windows[0].bufferList = @[helpBuffer]
  result.windowManager.windows[0].helpViewerState = some(helpState)
  result.state.mode = EditorMode.Help

suite "handleSearchBackspace":
  test "Remove last ASCII character":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "abc"

    handleSearchBackspace(e)

    check e.state.search.text == "ab"

  test "Remove last multibyte character (Japanese)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "検索"

    handleSearchBackspace(e)

    check e.state.search.text == "検"

  test "Remove last character from mixed ASCII and multibyte":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "abc日本語"

    handleSearchBackspace(e)

    check e.state.search.text == "abc日本"

  test "Backspace on single character leaves empty string":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "x"

    handleSearchBackspace(e)

    check e.state.search.text == ""

  test "Backspace on single multibyte character leaves empty string":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "あ"

    handleSearchBackspace(e)

    check e.state.search.text == ""

  test "Backspace on empty string does nothing":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = ""

    handleSearchBackspace(e)

    check e.state.search.text == ""

  test "Backspace sets needsFullRedraw":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "test"
    e.state.needsFullRedraw = false

    handleSearchBackspace(e)

    check e.state.needsFullRedraw == true

suite "Search mode - Insert-Normal mode (Ctrl-O)":
  test "finalizeSearch returns to Insert when insertNormalMode is set":
    let e = createTestEditorWithBuffer("hello world")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = true
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "world"

    finalizeSearch(e)

    check e.state.mode == EditorMode.Insert
    check not e.state.insertNormalMode
    check not e.state.isSearchOverlay

  test "cancelSearch returns to Insert when insertNormalMode is set":
    let e = createTestEditorWithBuffer("hello world")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = true
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "world"

    cancelSearch(e)

    check e.state.mode == EditorMode.Insert
    check not e.state.insertNormalMode
    check not e.state.isSearchOverlay

  test "finalizeSearch stays in Normal when insertNormalMode is false":
    let e = createTestEditorWithBuffer("hello world")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = false
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "world"

    finalizeSearch(e)

    check e.state.mode == EditorMode.Normal
    check not e.state.insertNormalMode

  test "cancelSearch stays in Normal when insertNormalMode is false":
    let e = createTestEditorWithBuffer("hello world")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = false
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "world"

    cancelSearch(e)

    check e.state.mode == EditorMode.Normal
    check not e.state.insertNormalMode

  test "finalizeSearch with Backward direction returns to Insert when insertNormalMode":
    let e = createTestEditorWithBuffer("hello world")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = true
    e.state.enterSearchOverlay(Backward)
    e.state.search.text = "hello"

    finalizeSearch(e)

    check e.state.mode == EditorMode.Insert
    check not e.state.insertNormalMode
    check not e.state.isSearchOverlay

  test "cancelSearch with Backward direction returns to Insert when insertNormalMode":
    let e = createTestEditorWithBuffer("hello world")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = true
    e.state.enterSearchOverlay(Backward)
    e.state.search.text = "hello"

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
    e.state.search.text = "Visual"

    performIncrementalSearch(e)

    let helpState = e.activeWindow.helpViewerState.get
    # selectedIndex should be updated to the matched line
    check helpState.selectedIndex == e.cursor.line
    check helpState.selectedIndex > 0

  test "performIncrementalSearch syncs selectedIndex to startPos on no match":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.search.incsearch = true
    e.state.search.startPos = BufferPosition(line: 5, column: 0)
    e.state.search.text = "zzzzNonExistentPattern"

    performIncrementalSearch(e)

    let helpState = e.activeWindow.helpViewerState.get
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

    let helpState = e.activeWindow.helpViewerState.get
    # selectedIndex should match cursor
    check helpState.selectedIndex == e.cursor.line
    check helpState.selectedIndex > 0

  test "finalizeSearch syncs selectedIndex from cursor position":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.search.incsearch = true
    e.state.search.startPos = BufferPosition(line: 0, column: 0)
    e.state.search.text = "Visual"

    # Perform incremental search first to move cursor
    performIncrementalSearch(e)
    let cursorLineAfterSearch = e.cursor.line

    finalizeSearch(e)

    let helpState = e.activeWindow.helpViewerState.get
    # selectedIndex should match cursor position, not reset to first match
    check helpState.selectedIndex == cursorLineAfterSearch
    check helpState.searchQuery == "Visual"

  test "finalizeSearch without incsearch syncs selectedIndex":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.search.incsearch = false
    e.state.search.startPos = BufferPosition(line: 0, column: 0)
    e.state.search.text = "Insert"

    finalizeSearch(e)

    let helpState = e.activeWindow.helpViewerState.get
    check helpState.selectedIndex == e.cursor.line
    check helpState.searchQuery == "Insert"

  test "handleSearchBackspace syncs selectedIndex":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.search.incsearch = true
    e.state.search.startPos = BufferPosition(line: 0, column: 0)
    e.state.search.text = "Visual"

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

    let helpState = e.activeWindow.helpViewerState.get
    # Should be back to same position as first match
    check helpState.selectedIndex == firstMatchLine

  test "cancelSearch restores selectedIndex to startPos":
    let e = createTestEditorInHelpMode()
    e.state.enterSearchOverlay(Forward)
    e.state.search.incsearch = true
    e.state.search.startPos = BufferPosition(line: 10, column: 0)
    e.cursor = BufferPosition(line: 10, column: 0)
    e.state.search.text = "Visual"

    # Move selectedIndex away from startPos via incremental search
    performIncrementalSearch(e)
    let helpState = e.activeWindow.helpViewerState.get
    check helpState.selectedIndex != 10

    # Cancel should restore selectedIndex to startPos
    cancelSearch(e)
    check helpState.selectedIndex == 10
