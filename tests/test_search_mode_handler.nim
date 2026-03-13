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

import std/unittest

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/editor {.all.}
import ../src/moepkg/config {.all.}
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
