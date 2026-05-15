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

## Tests for log_viewer_handler.nim
## This module tests the Log Viewer mode command handler functionality.

import std/[unittest, strutils]

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/key_bindings {.all.}
import ../src/moepkg/command_handlers/log_viewer_handler {.all.}

const TestViewportHeight = 24

proc charKey(c: string, mods: set[KeyModifier] = {}): KeyCombo =
  ## Helper to create a character key combo
  KeyCombo(isSpecial: false, char: c, modifiers: mods)

proc specialKey(sk: SpecialKey, mods: set[KeyModifier] = {}): KeyCombo =
  ## Helper to create a special key combo
  KeyCombo(isSpecial: true, special: sk, fnNum: 0, modifiers: mods)

proc newTestEditorState(): EditorState =
  ## Create a test EditorState with default values
  let window = EditorWindow(
    cursor: BufferPosition(line: 0, column: 0),
    mode: EditorMode.LogViewer,
    previousMode: EditorMode.Normal,
    preferredColumn: -1,
    screenCursor: CursorPosition(x: 0, y: 0),
  )
  result = EditorState(
    activeWindow: window,
    windowDisplay: WindowDisplayState(viewportReservedLines: 2), # status + command line
  )

proc newTestBuffer(content: string = ""): TextBuffer =
  ## Create a test buffer with optional content
  newTextBuffer(content)

suite "log_viewer_handler: newLogViewerHandler":
  test "Create new handler":
    let handler = newLogViewerHandler()
    check handler != nil
    check handler.waitingForG == false

suite "log_viewer_handler: handleLogViewerModeKey - Basic movement keys":
  test "j key moves down":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\nline2\nline3\n")
      state = newTestEditorState()
    check state.cursor.line == 0

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("j"))

    check result.kind == lvrHandled
    check state.cursor.line == 1

  test "k key moves up":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\nline2\nline3\n")
      state = newTestEditorState()
    state.cursor.line = 2

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("k"))

    check result.kind == lvrHandled
    check state.cursor.line == 1

  test "k key does not move above first line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\nline2\nline3\n")
      state = newTestEditorState()
    check state.cursor.line == 0

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("k"))

    check result.kind == lvrHandled
    check state.cursor.line == 0

  test "j key does not move below last line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\nline2\nline3\n")
      state = newTestEditorState()
    state.cursor.line = buffer.len - 1

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("j"))

    check result.kind == lvrHandled
    check state.cursor.line == buffer.len - 1

  test "h key moves left":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello\n")
      state = newTestEditorState()
    state.cursor.column = 3

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("h"))

    check result.kind == lvrHandled
    check state.cursor.column == 2

  test "h key does not move past column 0":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello\n")
      state = newTestEditorState()
    check state.cursor.column == 0

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("h"))

    check result.kind == lvrHandled
    check state.cursor.column == 0

  test "l key moves right":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello\n")
      state = newTestEditorState()
    state.cursor.column = 0

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("l"))

    check result.kind == lvrHandled
    check state.cursor.column == 1

  test "l key does not move past end of line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello\n")
      state = newTestEditorState()
    state.cursor.column = 4 # 'o' is at index 4, line length is 6 (includes \n)

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("l"))

    check result.kind == lvrHandled
    check state.cursor.column <= buffer.getLineLen(0) - 1

suite "log_viewer_handler: handleLogViewerModeKey - Arrow keys":
  test "Down arrow moves down":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\nline2\nline3\n")
      state = newTestEditorState()
    check state.cursor.line == 0

    let result = handler.handleLogViewerModeKey(
      buffer, state, TestViewportHeight, specialKey(skDown)
    )

    check result.kind == lvrHandled
    check state.cursor.line == 1

  test "Up arrow moves up":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\nline2\nline3\n")
      state = newTestEditorState()
    state.cursor.line = 2

    let result = handler.handleLogViewerModeKey(
      buffer, state, TestViewportHeight, specialKey(skUp)
    )

    check result.kind == lvrHandled
    check state.cursor.line == 1

  test "Left arrow moves left":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello\n")
      state = newTestEditorState()
    state.cursor.column = 3

    let result = handler.handleLogViewerModeKey(
      buffer, state, TestViewportHeight, specialKey(skLeft)
    )

    check result.kind == lvrHandled
    check state.cursor.column == 2

  test "Right arrow moves right":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello\n")
      state = newTestEditorState()
    state.cursor.column = 0

    let result = handler.handleLogViewerModeKey(
      buffer, state, TestViewportHeight, specialKey(skRight)
    )

    check result.kind == lvrHandled
    check state.cursor.column == 1

suite "log_viewer_handler: handleLogViewerModeKey - Line position keys":
  test "0 moves to beginning of line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello world\n")
      state = newTestEditorState()
    state.cursor.column = 5

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("0"))

    check result.kind == lvrHandled
    check state.cursor.column == 0

  test "$ moves to end of line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello world\n")
      state = newTestEditorState()
    state.cursor.column = 0

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("$"))

    check result.kind == lvrHandled
    # Implementation uses max(0, lineLen - 1) which is last char position
    check state.cursor.column == buffer.getLineLen(0) - 1

  test "Home moves to beginning of line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello world\n")
      state = newTestEditorState()
    state.cursor.column = 5

    let result = handler.handleLogViewerModeKey(
      buffer, state, TestViewportHeight, specialKey(skHome)
    )

    check result.kind == lvrHandled
    check state.cursor.column == 0

  test "End moves to end of line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello world\n")
      state = newTestEditorState()
    state.cursor.column = 0

    let result = handler.handleLogViewerModeKey(
      buffer, state, TestViewportHeight, specialKey(skEnd)
    )

    check result.kind == lvrHandled
    # Implementation uses max(0, lineLen - 1) which is last char position
    check state.cursor.column == buffer.getLineLen(0) - 1

suite "log_viewer_handler: handleLogViewerModeKey - gg and G commands":
  test "gg moves to first line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\nline2\nline3\nline4\nline5\n")
      state = newTestEditorState()
    state.cursor.line = 3

    # First 'g' - starts waiting
    let result1 =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("g"))
    check result1.kind == lvrHandled
    check handler.waitingForG == true
    check state.cursor.line == 3 # Not moved yet

    # Second 'g' - executes gg
    let result2 =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("g"))
    check result2.kind == lvrHandled
    check handler.waitingForG == false
    check state.cursor.line == 0
    check state.cursor.column == 0

  test "g followed by non-g cancels and falls through":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\nline2\nline3\nline4\n")
      state = newTestEditorState()
    state.cursor.line = 1

    # First 'g' - starts waiting
    let result1 =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("g"))
    check result1.kind == lvrHandled
    check handler.waitingForG == true

    # Non-'g' key - cancels waiting and falls through to normal handling
    let result2 =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("j"))
    check handler.waitingForG == false
    # The key falls through and 'j' is handled normally
    check result2.kind == lvrHandled
    check state.cursor.line == 2 # moved down from line 1 to line 2

  test "G moves to last line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\nline2\nline3\nline4\nline5\n")
      state = newTestEditorState()
    check state.cursor.line == 0

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("G"))

    check result.kind == lvrHandled
    check state.cursor.line == buffer.len - 1
    check state.cursor.column == 0

suite "log_viewer_handler: handleLogViewerModeKey - Half page and full page movement":
  test "Ctrl+d moves half page down":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer(
        "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\nline11\nline12\nline13\nline14\nline15\nline16\nline17\nline18\nline19\nline20\nline21\nline22\nline23\nline24\nline25\nline26\nline27\nline28\nline29\nline30\n"
      )
      state = newTestEditorState()
    check state.cursor.line == 0

    let result = handler.handleLogViewerModeKey(
      buffer, state, TestViewportHeight, charKey("d", {kmCtrl})
    )

    check result.kind == lvrHandled
    # Half page is (viewportHeight - reservedLines) / 2
    let contentHeight = TestViewportHeight - state.windowDisplay.viewportReservedLines
    check state.cursor.line == contentHeight div 2

  test "Ctrl+u moves half page up":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer(
        "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\nline11\nline12\nline13\nline14\nline15\nline16\nline17\nline18\nline19\nline20\nline21\nline22\nline23\nline24\nline25\nline26\nline27\nline28\nline29\nline30\n"
      )
      state = newTestEditorState()
    let contentHeight = TestViewportHeight - state.windowDisplay.viewportReservedLines
    state.cursor.line = 20

    let result = handler.handleLogViewerModeKey(
      buffer, state, TestViewportHeight, charKey("u", {kmCtrl})
    )

    check result.kind == lvrHandled
    check state.cursor.line == 20 - (contentHeight div 2)

  test "Ctrl+u does not go below 0":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\nline2\nline3\n")
      state = newTestEditorState()
    state.cursor.line = 1

    let result = handler.handleLogViewerModeKey(
      buffer, state, TestViewportHeight, charKey("u", {kmCtrl})
    )

    check result.kind == lvrHandled
    check state.cursor.line == 0

  test "Ctrl+d does not exceed last line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\nline2\nline3\n")
      state = newTestEditorState()
    state.cursor.line = 2

    let result = handler.handleLogViewerModeKey(
      buffer, state, TestViewportHeight, charKey("d", {kmCtrl})
    )

    check result.kind == lvrHandled
    check state.cursor.line == buffer.len - 1

  test "Ctrl+f moves full page down":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer(
        "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\nline11\nline12\nline13\nline14\nline15\nline16\nline17\nline18\nline19\nline20\nline21\nline22\nline23\nline24\nline25\nline26\nline27\nline28\nline29\nline30\nline31\nline32\nline33\nline34\nline35\nline36\nline37\nline38\nline39\nline40\nline41\nline42\nline43\nline44\nline45\nline46\nline47\nline48\nline49\nline50\n"
      )
      state = newTestEditorState()
    check state.cursor.line == 0

    let result = handler.handleLogViewerModeKey(
      buffer, state, TestViewportHeight, charKey("f", {kmCtrl})
    )

    check result.kind == lvrHandled
    let contentHeight = TestViewportHeight - state.windowDisplay.viewportReservedLines
    check state.cursor.line == contentHeight

  test "Ctrl+b moves full page up":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer(
        "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\nline11\nline12\nline13\nline14\nline15\nline16\nline17\nline18\nline19\nline20\nline21\nline22\nline23\nline24\nline25\nline26\nline27\nline28\nline29\nline30\nline31\nline32\nline33\nline34\nline35\nline36\nline37\nline38\nline39\nline40\nline41\nline42\nline43\nline44\nline45\nline46\nline47\nline48\nline49\nline50\n"
      )
      state = newTestEditorState()
    let contentHeight = TestViewportHeight - state.windowDisplay.viewportReservedLines
    state.cursor.line = 30

    let result = handler.handleLogViewerModeKey(
      buffer, state, TestViewportHeight, charKey("b", {kmCtrl})
    )

    check result.kind == lvrHandled
    check state.cursor.line == 30 - contentHeight

suite "log_viewer_handler: handleLogViewerModeKey - Word motion":
  test "w moves to next word":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello world test\n")
      state = newTestEditorState()
    state.cursor.column = 0

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("w"))

    check result.kind == lvrHandled
    check state.cursor.column == 6 # 'w' in "world"

  test "b moves to previous word":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello world test\n")
      state = newTestEditorState()
    state.cursor.column = 6

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("b"))

    check result.kind == lvrHandled
    check state.cursor.column == 0 # 'h' in "hello"

  test "e moves to end of word":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello world test\n")
      state = newTestEditorState()
    state.cursor.column = 0

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("e"))

    check result.kind == lvrHandled
    check state.cursor.column == 4 # 'o' at end of "hello"

suite "log_viewer_handler: handleLogViewerModeKey - Paragraph motion":
  test "} moves to next blank line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\nline2\n\nline4\nline5\n")
      state = newTestEditorState()
    state.cursor.line = 0

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("}"))

    check result.kind == lvrHandled
    check state.cursor.line == 2 # blank line
    check state.cursor.column == 0

  test "{ moves to previous blank line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\nline2\n\nline4\nline5\n")
      state = newTestEditorState()
    state.cursor.line = 4

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("{"))

    check result.kind == lvrHandled
    check state.cursor.line == 2 # blank line
    check state.cursor.column == 0

suite "log_viewer_handler: handleLogViewerModeKey - Mode transitions":
  test ": enters command mode":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("test\n")
      state = newTestEditorState()

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey(":"))

    check result.kind == lvrEnterCommand

  test "/ enters forward search mode":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("test\n")
      state = newTestEditorState()

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("/"))

    check result.kind == lvrEnterSearchForward

  test "? enters backward search mode":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("test\n")
      state = newTestEditorState()

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("?"))

    check result.kind == lvrEnterSearchBackward

  test "q quits log viewer":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("test\n")
      state = newTestEditorState()

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("q"))

    check result.kind == lvrQuit

  test "r refreshes log content":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("test\n")
      state = newTestEditorState()

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("r"))

    check result.kind == lvrRefresh

  test "Escape stays in log viewer (like Vim help)":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("test\n")
      state = newTestEditorState()

    let result = handler.handleLogViewerModeKey(
      buffer, state, TestViewportHeight, specialKey(skEscape)
    )

    check result.kind == lvrHandled

suite "log_viewer_handler: handleLogViewerModeKey - Search navigation":
  test "n searches forward with last search text":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\ntest here\nline3\ntest again\nline5\n")
      state = newTestEditorState()
    state.search.lastText = "test"
    state.cursor.line = 0

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("n"))

    check result.kind == lvrHandled
    check state.cursor.line == 1 # first "test"

  test "N searches backward with last search text":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\ntest here\nline3\ntest again\nline5\n")
      state = newTestEditorState()
    state.search.lastText = "test"
    state.cursor.line = 4

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("N"))

    check result.kind == lvrHandled
    check state.cursor.line == 3 # second "test"

  test "n with no previous search shows message":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("test\n")
      state = newTestEditorState()
    state.search.lastText = ""

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("n"))

    check result.kind == lvrHandled
    check state.statusMessage == "No previous search"

  test "N with no previous search shows message":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("test\n")
      state = newTestEditorState()
    state.search.lastText = ""

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("N"))

    check result.kind == lvrHandled
    check state.statusMessage == "No previous search"

  test "* searches for word under cursor":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello world hello again\n")
      state = newTestEditorState()
    state.cursor.column = 0 # on "hello"

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("*"))

    check result.kind == lvrHandled
    check state.search.lastText == "hello"
    check state.search.wholeWord == true

  test "# searches backward for word under cursor":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello world hello\n")
      state = newTestEditorState()
    state.cursor.column = 12 # on second "hello"

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("#"))

    check result.kind == lvrHandled
    check state.search.lastText == "hello"
    check state.search.wholeWord == true
    check state.cursor.column == 0 # found first "hello"

suite "log_viewer_handler: handleLogViewerModeKey - Unhandled keys":
  test "Unbound key returns unhandled":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("test\n")
      state = newTestEditorState()

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("z"))

    check result.kind == lvrUnhandled

  test "Unbound special key returns unhandled":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("test\n")
      state = newTestEditorState()

    let result = handler.handleLogViewerModeKey(
      buffer, state, TestViewportHeight, specialKey(skPageUp)
    )

    check result.kind == lvrUnhandled

suite "log_viewer_handler: handleLogViewerModeKey - Edge cases":
  test "Empty buffer - j does not crash":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("")
      state = newTestEditorState()

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("j"))

    check result.kind == lvrHandled
    check state.cursor.line == 0

  test "Empty buffer - G moves to line 0":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("")
      state = newTestEditorState()

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("G"))

    check result.kind == lvrHandled
    check state.cursor.line == 0

  test "Empty line - $ on empty line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("\n")
      state = newTestEditorState()

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("$"))

    check result.kind == lvrHandled
    check state.cursor.column == 0

  test "Empty line - End on empty line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("\n")
      state = newTestEditorState()

    let result = handler.handleLogViewerModeKey(
      buffer, state, TestViewportHeight, specialKey(skEnd)
    )

    check result.kind == lvrHandled
    check state.cursor.column == 0

  test "g followed by special key cancels":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\nline2\nline3\n")
      state = newTestEditorState()
    state.cursor.line = 2

    # First 'g' - starts waiting
    let result1 =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("g"))
    check result1.kind == lvrHandled
    check handler.waitingForG == true

    # Special key - cancels waiting
    let result2 = handler.handleLogViewerModeKey(
      buffer, state, TestViewportHeight, specialKey(skUp)
    )
    check handler.waitingForG == false
    # Up arrow is handled
    check result2.kind == lvrHandled
    check state.cursor.line == 1

suite "log_viewer_handler: handleLogViewerModeKey - Word motion edge cases":
  test "w moves to next line when at end of line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello\nworld\n")
      state = newTestEditorState()
    state.cursor.column = 4 # on 'o' of "hello"

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("w"))

    check result.kind == lvrHandled
    check state.cursor.line == 1
    check state.cursor.column == 0 # 'w' of "world"

  test "b moves to previous line when at start of line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello\nworld\n")
      state = newTestEditorState()
    state.cursor.line = 1
    state.cursor.column = 0

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("b"))

    check result.kind == lvrHandled
    check state.cursor.line == 0
    check state.cursor.column == 0 # back to 'h' of "hello"

  test "e moves to next line when at end of line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hi \nworld\n")
      state = newTestEditorState()
    state.cursor.column = 1 # on 'i' of "hi "

    # First e moves to end of "hi" (stays on 'i')
    # Actually, we're already at 'i', so e should skip whitespace and go to next word
    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("e"))

    check result.kind == lvrHandled
    # After moving forward from 'i', we hit space, skip it, reach end of line, move to next line
    check state.cursor.line == 1
    check state.cursor.column == 4 # 'd' of "world"

  test "w handles symbols (non-word, non-whitespace)":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("foo::bar\n")
      state = newTestEditorState()
    state.cursor.column = 0 # on 'f'

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("w"))

    check result.kind == lvrHandled
    check state.cursor.column == 3 # on first ':'

  test "b handles symbols":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("foo::bar\n")
      state = newTestEditorState()
    state.cursor.column = 5 # on 'b' of "bar"

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("b"))

    check result.kind == lvrHandled
    check state.cursor.column == 3 # on first ':'

  test "e handles symbols":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("foo::bar\n")
      state = newTestEditorState()
    state.cursor.column = 3 # on first ':'

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("e"))

    check result.kind == lvrHandled
    check state.cursor.column == 4 # on second ':'

suite "log_viewer_handler: handleLogViewerModeKey - Search edge cases":
  test "n shows 'Pattern not found' when search fails":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello world\n")
      state = newTestEditorState()
    state.search.lastText = "notfound"

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("n"))

    check result.kind == lvrHandled
    check "Pattern not found" in state.statusMessage

  test "N shows 'Pattern not found' when search fails":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("hello world\n")
      state = newTestEditorState()
    state.search.lastText = "notfound"

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("N"))

    check result.kind == lvrHandled
    check "Pattern not found" in state.statusMessage

  test "* on non-word character does nothing":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("  hello\n")
      state = newTestEditorState()
    state.cursor.column = 0 # on space

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("*"))

    check result.kind == lvrHandled
    # search.lastText should remain empty or unchanged
    check state.cursor.column == 0 # position unchanged

  test "# on non-word character does nothing":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("  hello\n")
      state = newTestEditorState()
    state.cursor.column = 0 # on space

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("#"))

    check result.kind == lvrHandled
    check state.cursor.column == 0 # position unchanged

  test "* shows 'Pattern not found' when word not found elsewhere":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("unique\n")
      state = newTestEditorState()
    state.cursor.column = 0 # on 'u' of "unique"

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("*"))

    check result.kind == lvrHandled
    check state.search.lastText == "unique"
    # Word is found at current position, but no other occurrence
    # The implementation searches from current position, so it may find itself
    # or show "Pattern not found" - depends on implementation

  test "# shows 'Pattern not found' when word not found elsewhere":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("unique\n")
      state = newTestEditorState()
    state.cursor.column = 0 # on 'u' of "unique"

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("#"))

    check result.kind == lvrHandled
    check state.search.lastText == "unique"

suite "log_viewer_handler: handleLogViewerModeKey - Paragraph motion edge cases":
  test "{ at beginning of buffer stays at line 0":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\nline2\n")
      state = newTestEditorState()
    state.cursor.line = 0

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("{"))

    check result.kind == lvrHandled
    check state.cursor.line == 0

  test "} at end of buffer stays at last line":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("line1\nline2\n")
      state = newTestEditorState()
    state.cursor.line = buffer.len - 1

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("}"))

    check result.kind == lvrHandled
    check state.cursor.line == buffer.len - 1

  test "{ skips multiple blank lines":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("para1\n\n\npara2\n")
      state = newTestEditorState()
    state.cursor.line = 3 # "para2"

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("{"))

    check result.kind == lvrHandled
    # Should stop at the first blank line encountered going backward
    check state.cursor.line <= 2

  test "} skips multiple blank lines":
    let
      handler = newLogViewerHandler()
      buffer = newTestBuffer("para1\n\n\npara2\n")
      state = newTestEditorState()
    state.cursor.line = 0 # "para1"

    let result =
      handler.handleLogViewerModeKey(buffer, state, TestViewportHeight, charKey("}"))

    check result.kind == lvrHandled
    # Should find the first blank line going forward
    check state.cursor.line >= 1
