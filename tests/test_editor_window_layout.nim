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

import std/[unittest, strutils]

import
  ../src/moepkg/[
    editor, editor_window, editor_window_layout, config, types, buffer, modes,
    render_utils, log_viewer, help_viewer,
  ]

# Helper to create a minimal Editor for testing
proc createTestEditor(): Editor =
  let config = newEditorConfig()
  result = newEditor(config)

suite "calculateTerminalAreaDimensions":
  test "single window, status line enabled":
    let e = createTestEditor()
    e.state.showStatusLine = true
    e.state.showTabLine = false
    let win = e.activeWindow
    # Default viewport: width=80, height=20
    let (cols, rows) = e.calculateTerminalAreaDimensions(win)
    check cols == 80
    # height(20) - steadyBottomAreaHeight()(1) - tabLineOffset(0)
    check rows == 19

  test "single window, status line disabled":
    let e = createTestEditor()
    e.state.showStatusLine = false
    e.state.showTabLine = false
    let win = e.activeWindow
    let (cols, rows) = e.calculateTerminalAreaDimensions(win)
    check cols == 80
    # height(20) - steadyBottomAreaHeight()(1) - tabLineOffset(0)
    check rows == 19

  test "single window, with tab line":
    let e = createTestEditor()
    e.state.showStatusLine = true
    e.state.showTabLine = true
    let win = e.activeWindow
    let (cols, rows) = e.calculateTerminalAreaDimensions(win)
    check cols == 80
    # height(20) - steadyBottomAreaHeight()(1) - TabLineHeight(1)
    check rows == 18

  test "hsplit, top window (non-bottom)":
    let e = createTestEditor()
    e.state.showStatusLine = true
    e.state.showTabLine = false
    discard e.hsplit()
    check e.windowManager.windows.len == 2
    # Top window (index 0) is non-bottom
    let topWin = e.windowManager.windows[0]
    let (cols, rows) = e.calculateTerminalAreaDimensions(topWin)
    check cols == topWin.viewport.width
    # Non-bottom window: no reserved lines, no tab line
    check rows == topWin.viewport.height

  test "hsplit, bottom window":
    let e = createTestEditor()
    e.state.showStatusLine = true
    e.state.showTabLine = false
    discard e.hsplit()
    check e.windowManager.windows.len == 2
    # Bottom window (index 1) is the active one after hsplit
    let bottomWin = e.windowManager.windows[1]
    let (cols, rows) = e.calculateTerminalAreaDimensions(bottomWin)
    check cols == bottomWin.viewport.width
    # Bottom window: height - steadyBottomAreaHeight()(1)
    check rows == bottomWin.viewport.height - 1

  test "minimum rows is 1":
    let e = createTestEditor()
    e.state.showStatusLine = true
    e.state.showTabLine = true
    let win = e.activeWindow
    # Set viewport height very small so rows would be <= 0
    win.viewport = ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 2, x: 0, y: 0)
    let (cols, rows) = e.calculateTerminalAreaDimensions(win)
    check cols == 80
    # height(2) - steadyBottomAreaHeight()(1) - TabLineHeight(1) = 0, clamped to 1
    check rows == 1

suite "calculateReservedLines":
  test "status line enabled, multi status line, bottom window":
    let e = createTestEditor()
    e.state.showStatusLine = true
    e.state.multiStatusLine = true
    let reserved = e.calculateReservedLines(isBottomWindow = true)
    # steadyBottomAreaHeight() = 1 (status line and command line share the last row)
    check reserved == 1

  test "status line enabled, multi status line, non-bottom window":
    let e = createTestEditor()
    e.state.showStatusLine = true
    e.state.multiStatusLine = true
    let reserved = e.calculateReservedLines(isBottomWindow = false)
    # StatusLineReserve = 1
    check reserved == 1

  test "status line enabled, single status line, bottom window":
    let e = createTestEditor()
    e.state.showStatusLine = true
    e.state.multiStatusLine = false
    let reserved = e.calculateReservedLines(isBottomWindow = true)
    # steadyBottomAreaHeight() = 1 (status line and command line share the last row)
    check reserved == 1

  test "status line enabled, single status line, non-bottom window":
    let e = createTestEditor()
    e.state.showStatusLine = true
    e.state.multiStatusLine = false
    let reserved = e.calculateReservedLines(isBottomWindow = false)
    # No status line for non-bottom window in single status line mode
    check reserved == 0

  test "status line disabled, bottom window":
    let e = createTestEditor()
    e.state.showStatusLine = false
    let reserved = e.calculateReservedLines(isBottomWindow = true)
    # steadyBottomAreaHeight() = 1
    check reserved == 1

  test "status line disabled, non-bottom window":
    let e = createTestEditor()
    e.state.showStatusLine = false
    let reserved = e.calculateReservedLines(isBottomWindow = false)
    check reserved == 0

  test "multi-line status message grows the bottom reserve":
    let e = createTestEditor()
    e.screenSize.width = 80
    e.state.showStatusLine = true
    e.state.multiStatusLine = false
    e.state.setStatusQuiet("a\nb\nc")
    # 3 message rows + pushed-up status line row
    check e.calculateReservedLines(isBottomWindow = true) == 4
    # Non-bottom windows are unaffected
    check e.calculateReservedLines(isBottomWindow = false) == 0

  test "multi-line status message without status line":
    let e = createTestEditor()
    e.screenSize.width = 80
    e.state.showStatusLine = false
    e.state.setStatusQuiet("a\nb\nc")
    check e.calculateReservedLines(isBottomWindow = true) == 3

  test "wrapped command overlay grows the bottom reserve":
    let e = createTestEditor()
    e.screenSize.width = 80
    e.state.showStatusLine = true
    e.state.enterCommandOverlay()
    # ":" + 100 chars = 101 columns -> 2 rows at width 80, + status line row
    e.state.input.commandText = ":" & "a".repeat(100)
    e.state.input.commandCursor = 0
    check e.calculateReservedLines(isBottomWindow = true) == 3

  test "terminal dimensions stay steady under a multi-line message":
    let e = createTestEditor()
    e.screenSize.width = 80
    e.state.showStatusLine = true
    e.state.showTabLine = false
    e.state.setStatusQuiet("a\nb\nc")
    let win = e.activeWindow
    let (_, rows) = e.calculateTerminalAreaDimensions(win)
    # PTY size must not flap on transient messages: height(20) - steady(1)
    check rows == 19

suite "calculateSidebarWidth":
  test "sidebar enabled in file edit mode":
    let e = createTestEditor()
    e.state.showSidebar = true
    let win = e.activeWindow
    win.mode = EditorMode.Normal
    let width = e.calculateSidebarWidth(win)
    # DefaultSidebarWidth = 2
    check width == 2

  test "sidebar disabled":
    let e = createTestEditor()
    e.state.showSidebar = false
    let win = e.activeWindow
    win.mode = EditorMode.Normal
    let width = e.calculateSidebarWidth(win)
    check width == 0

  test "sidebar disabled for non-file-edit mode":
    let e = createTestEditor()
    e.state.showSidebar = true
    let win = e.activeWindow
    win.mode = EditorMode.RecentFile
    let width = e.calculateSidebarWidth(win)
    check width == 0

suite "calculateScrollbarWidth":
  test "scrollbar width 1 in file edit mode":
    let e = createTestEditor()
    e.state.scrollbar = true
    e.state.scrollbarWidth = 1
    let win = e.activeWindow
    win.mode = EditorMode.Normal
    let width = e.calculateScrollbarWidth(win)
    check width == 1

  test "scrollbar width 2 in file edit mode":
    let e = createTestEditor()
    e.state.scrollbar = true
    e.state.scrollbarWidth = 2
    let win = e.activeWindow
    win.mode = EditorMode.Normal
    let width = e.calculateScrollbarWidth(win)
    check width == 2

  test "scrollbar disabled (width 0)":
    let e = createTestEditor()
    e.state.scrollbar = true
    e.state.scrollbarWidth = 0
    let win = e.activeWindow
    win.mode = EditorMode.Normal
    let width = e.calculateScrollbarWidth(win)
    check width == 0

  test "scrollbar bool disabled":
    let e = createTestEditor()
    e.state.scrollbar = false
    e.state.scrollbarWidth = 2
    let win = e.activeWindow
    win.mode = EditorMode.Normal
    let width = e.calculateScrollbarWidth(win)
    check width == 0

  test "scrollbar disabled for non-file-edit mode":
    let e = createTestEditor()
    e.state.scrollbar = true
    e.state.scrollbarWidth = 1
    let win = e.activeWindow
    win.mode = EditorMode.RecentFile
    let width = e.calculateScrollbarWidth(win)
    check width == 0

  test "scrollbar disabled for Filer mode":
    let e = createTestEditor()
    e.state.scrollbar = true
    e.state.scrollbarWidth = 1
    let win = e.activeWindow
    win.mode = EditorMode.Filer
    let width = e.calculateScrollbarWidth(win)
    check width == 0

  test "scrollbar enabled in Insert mode":
    let e = createTestEditor()
    e.state.scrollbar = true
    e.state.scrollbarWidth = 1
    let win = e.activeWindow
    win.mode = EditorMode.Insert
    let width = e.calculateScrollbarWidth(win)
    check width == 1

  test "scrollbar enabled in Visual mode":
    let e = createTestEditor()
    e.state.scrollbar = true
    e.state.scrollbarWidth = 1
    let win = e.activeWindow
    win.mode = EditorMode.Visual
    let width = e.calculateScrollbarWidth(win)
    check width == 1

  test "scrollbar width 3 in Normal mode":
    let e = createTestEditor()
    e.state.scrollbar = true
    e.state.scrollbarWidth = 3
    let win = e.activeWindow
    win.mode = EditorMode.Normal
    let width = e.calculateScrollbarWidth(win)
    check width == 3

  test "scrollbar disabled for Help mode":
    let e = createTestEditor()
    e.state.scrollbar = true
    e.state.scrollbarWidth = 1
    let win = e.activeWindow
    win.mode = EditorMode.Help
    let width = e.calculateScrollbarWidth(win)
    check width == 0

  test "scrollbar disabled for BufferManager mode":
    let e = createTestEditor()
    e.state.scrollbar = true
    e.state.scrollbarWidth = 1
    let win = e.activeWindow
    win.mode = EditorMode.BufferManager
    let width = e.calculateScrollbarWidth(win)
    check width == 0

  test "scrollbar enabled in Replace mode":
    let e = createTestEditor()
    e.state.scrollbar = true
    e.state.scrollbarWidth = 2
    let win = e.activeWindow
    win.mode = EditorMode.Replace
    let width = e.calculateScrollbarWidth(win)
    check width == 2

suite "calculateWindowCursor":
  test "cursor at buffer start, no wrap":
    let e = createTestEditor()
    e.state.lineWrap = false
    let buffer = newTextBuffer("Hello world")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 0, column: 0)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    check pos.x == 4 # gutterWidth
    check pos.y == 0

suite "calculateSidebarWidth - modeState gating":
  test "sidebar width is non-zero in Normal mode with mskNone":
    let e = createTestEditor()
    e.state.showSidebar = true
    let win = e.activeWindow
    win.mode = EditorMode.Normal
    win.modeState = ModeState(kind: mskNone)
    check e.calculateSidebarWidth(win) > 0

  test "sidebar width is 0 in Visual mode with mskLogViewer":
    let e = createTestEditor()
    e.state.showSidebar = true
    let win = e.activeWindow
    win.mode = EditorMode.Visual
    win.modeState = ModeState(kind: mskLogViewer, logViewer: newLogViewerState())
    check e.calculateSidebarWidth(win) == 0

  test "sidebar width is 0 in Visual mode with mskHelp":
    let e = createTestEditor()
    e.state.showSidebar = true
    let win = e.activeWindow
    win.mode = EditorMode.Visual
    win.modeState = ModeState(kind: mskHelp, help: newHelpViewerState())
    check e.calculateSidebarWidth(win) == 0

  test "scrollbar width is 0 in Visual mode with mskLogViewer":
    let e = createTestEditor()
    e.state.scrollbar = true
    e.state.scrollbarWidth = 1
    let win = e.activeWindow
    win.mode = EditorMode.Visual
    win.modeState = ModeState(kind: mskLogViewer, logViewer: newLogViewerState())
    check e.calculateScrollbarWidth(win) == 0

  test "cursor in middle of line, no wrap":
    let e = createTestEditor()
    e.state.lineWrap = false
    let buffer = newTextBuffer("Hello world")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 0, column: 5)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    check pos.x == 9 # gutterWidth + 5
    check pos.y == 0

  test "cursor on second line, no wrap":
    let e = createTestEditor()
    e.state.lineWrap = false
    let buffer = newTextBuffer("Line 1\nLine 2")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 1, column: 0)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    check pos.x == 4 # gutterWidth
    check pos.y == 1 # second line

  test "cursor below a collapsed fold uses visible-row offset, no wrap":
    let e = createTestEditor()
    e.state.lineWrap = false
    let buffer = newTextBuffer("0\n1\n2\n3\n4\n5\n6\n7\n8\n9")
    # Collapse lines 1..5: interior lines 2..5 are hidden, line 1 shows a marker.
    check buffer.foldState.addFold(1, 5, collapsed = true)
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 7, column: 0)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    # Visible rows above the cursor are lines 0, 1 (marker) and 6 -> y == 3,
    # not the raw line distance of 7.
    check pos.x == 4
    check pos.y == 3

  test "cursor below a collapsed fold uses visible-row offset, wrap mode":
    let e = createTestEditor()
    e.state.lineWrap = true
    let buffer = newTextBuffer("0\n1\n2\n3\n4\n5\n6\n7\n8\n9")
    check buffer.foldState.addFold(1, 5, collapsed = true)
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 7, column: 0)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    # Each short line is one wrapped row; the folded interior contributes 0 and
    # the marker 1, so visible rows above the cursor (0, 1, 6) give y == 3.
    check pos.y == 3

  test "cursor above visible area returns (0, 0)":
    let e = createTestEditor()
    e.state.lineWrap = false
    let buffer = newTextBuffer("Line 1\nLine 2\nLine 3")
    let viewport =
      ViewPort(topLine: 2, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 0, column: 0) # Above visible area

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    check pos.x == 0
    check pos.y == 0

  test "cursor with horizontal scroll, no wrap":
    let e = createTestEditor()
    e.state.lineWrap = false
    let buffer = newTextBuffer("0123456789ABCDEFGHIJ")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 5, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 0, column: 10)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    check pos.x == 9 # gutterWidth + (10 - 5) = 4 + 5 = 9
    check pos.y == 0

  test "cursor after a tab, no wrap":
    let e = createTestEditor()
    e.state.lineWrap = false
    e.tabStop = 4
    let buffer = newTextBuffer("\tabc")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 0, column: 1)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    check pos.x == 8 # gutterWidth + tab expanded to 4 cells
    check pos.y == 0

  test "cursor with horizontal scroll past a tab restarts tab stops":
    # The renderer slices the line at leftColumn, so the tab is expanded from the
    # slice start; subtracting two line-start widths would place the cursor at 6.
    let e = createTestEditor()
    e.state.lineWrap = false
    e.tabStop = 4
    let buffer = newTextBuffer("ab\tcd")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 2, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 0, column: 3) # 'c'

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    check pos.x == 8 # gutterWidth + tab expanded from the slice start = 4 + 4
    check pos.y == 0

  test "cursor with horizontal scroll and full width characters":
    let e = createTestEditor()
    e.state.lineWrap = false
    e.tabStop = 4
    let buffer = newTextBuffer("あいうえお")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 2, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 0, column: 3) # え

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    check pos.x == 6 # gutterWidth + う takes 2 cells
    check pos.y == 0

  test "cursor left of leftColumn clamps to the text start":
    let e = createTestEditor()
    e.state.lineWrap = false
    e.tabStop = 4
    let buffer = newTextBuffer("0123456789")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 5, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 0, column: 2)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    check pos.x == 4
    check pos.y == 0

  test "cursor out of buffer bounds returns (0, 0)":
    let e = createTestEditor()
    e.state.lineWrap = false
    let buffer = newTextBuffer("Hello")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 10, column: 0) # Beyond buffer

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    check pos.x == 0
    check pos.y == 0

  test "cursor at buffer start, with wrap":
    let e = createTestEditor()
    e.state.lineWrap = true
    let buffer = newTextBuffer("Hello world")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 0, column: 0)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    check pos.x == 4
    check pos.y == 0

  test "cursor with scrollbar, wrap mode":
    let e = createTestEditor()
    e.state.lineWrap = true
    # 20 chars wrapping at maxWidth = 10 - 0 - 1 = 9
    let buffer = newTextBuffer("abcdefghijklmnopqrst")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 10, height: 24, x: 0, y: 0)
    # Cursor at char 10 => wrap segment 1 (9 chars per segment), col 1
    let cursor = BufferPosition(line: 0, column: 10)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 0,
      reservedLines = steadyBottomAreaHeight(),
      scrollbarWidth = 1,
    )
    # maxWidth = 10 - 0 - 1 = 9
    # char 10 is on wrap segment 1, display col 1
    check pos.x == 1
    check pos.y == 1

  test "cursor with scrollbar, no wrap":
    let e = createTestEditor()
    e.state.lineWrap = false
    let buffer = newTextBuffer("Hello world")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 0, column: 5)

    # scrollbarWidth doesn't affect no-wrap cursor X position
    # (it affects textAreaWidth for horizontal scroll, not cursor offset)
    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
      scrollbarWidth = 1,
    )
    check pos.x == 9 # gutterWidth + 5
    check pos.y == 0

  test "cursor with scrollbar width 2, wrap mode":
    let e = createTestEditor()
    e.state.lineWrap = true
    # 20 chars, maxWidth = 10 - 0 - 2 = 8
    let buffer = newTextBuffer("abcdefghijklmnopqrst")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 10, height: 24, x: 0, y: 0)
    # Cursor at char 9 => wrap segment 1 (8 chars per segment), col 1
    let cursor = BufferPosition(line: 0, column: 9)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 0,
      reservedLines = steadyBottomAreaHeight(),
      scrollbarWidth = 2,
    )
    # maxWidth = 10 - 0 - 2 = 8
    # char 9 is on segment 1, display col 1
    check pos.x == 1
    check pos.y == 1

  test "cursor with scrollbar width 0, wrap mode (no scrollbar)":
    let e = createTestEditor()
    e.state.lineWrap = true
    # 20 chars, maxWidth = 10 - 0 - 0 = 10
    let buffer = newTextBuffer("abcdefghijklmnopqrst")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 10, height: 24, x: 0, y: 0)
    # Cursor at char 10 => wrap segment 1 (10 chars per segment), col 0
    let cursor = BufferPosition(line: 0, column: 10)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 0,
      reservedLines = steadyBottomAreaHeight(),
      scrollbarWidth = 0,
    )
    check pos.x == 0
    check pos.y == 1

  test "cursor with scrollbar and gutterWidth, wrap mode":
    let e = createTestEditor()
    e.state.lineWrap = true
    # maxWidth = 20 - 4 - 1 = 15
    let buffer = newTextBuffer("abcdefghijklmnopqrstuvwxyz0123456789")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 20, height: 24, x: 0, y: 0)
    # Cursor at char 16 => segment 1 (15 chars per segment), display col 1
    let cursor = BufferPosition(line: 0, column: 16)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
      scrollbarWidth = 1,
    )
    # segment 1, display col = 1, x = viewport.x + gutterWidth + 1 = 0 + 4 + 1
    check pos.x == 5
    check pos.y == 1

  test "cursor with scrollbar on multiline buffer, wrap mode":
    let e = createTestEditor()
    e.state.lineWrap = true
    # maxWidth = 10 - 0 - 1 = 9
    # Line 0: "abcdefghij" (10 chars) => 2 screen rows (9+1)
    # Line 1: "klm" => 1 screen row
    let buffer = newTextBuffer("abcdefghij\nklm")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 10, height: 24, x: 0, y: 0)
    # Cursor at line 1, col 2 => screen row 2
    let cursor = BufferPosition(line: 1, column: 2)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 0,
      reservedLines = steadyBottomAreaHeight(),
      scrollbarWidth = 1,
    )
    check pos.x == 2
    check pos.y == 2 # row 0: "abcdefghi", row 1: "j", row 2: "klm"

  test "topWrapOffset shifts the wrapped cursor up by the skipped segments":
    let e = createTestEditor()
    e.state.lineWrap = true
    # maxWidth = 10 - 0 - 1 = 9 => segments 0-8, 9-17, 18-26, 27-29
    let buffer = newTextBuffer("abcdefghijklmnopqrstuvwxyz0123")
    # Start the view one wrap segment down (segment 0 of the top line is hidden).
    let viewport = ViewPort(
      topLine: 0, topWrapOffset: 1, leftColumn: 0, width: 10, height: 24, x: 0, y: 0
    )
    # Cursor at char 20 => wrap segment 2, display col 2 (chars 18,19,20).
    let cursor = BufferPosition(line: 0, column: 20)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 0,
      reservedLines = steadyBottomAreaHeight(),
      scrollbarWidth = 1,
    )
    check pos.x == 2
    check pos.y == 1 # segment 2 minus the skipped leading segment 1

  test "cursor on a segment hidden above topWrapOffset returns (0, 0)":
    let e = createTestEditor()
    e.state.lineWrap = true
    let buffer = newTextBuffer("abcdefghijklmnopqrstuvwxyz0123")
    # Skip the first two segments of the top line.
    let viewport = ViewPort(
      topLine: 0, topWrapOffset: 2, leftColumn: 0, width: 10, height: 24, x: 0, y: 0
    )
    # Cursor at char 5 => segment 0, which is scrolled off the top.
    let cursor = BufferPosition(line: 0, column: 5)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 0,
      reservedLines = steadyBottomAreaHeight(),
      scrollbarWidth = 1,
    )
    check pos.x == 0
    check pos.y == 0

suite "calculateWindowCursor - wrap mode edge cases":
  test "wrap mode with empty line":
    let e = createTestEditor()
    e.state.lineWrap = true
    let buffer = newTextBuffer("Line 1\n\nLine 3") # Middle line is empty
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 2, column: 0)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    check pos.x == 4
    check pos.y == 2 # Line 0, empty line 1, Line 2

  test "wrap mode with long line that wraps":
    let e = createTestEditor()
    e.state.lineWrap = true
    # Create a line that will wrap (wider than viewport)
    let longLine = "A".repeat(100)
    let buffer = newTextBuffer(longLine & "\nLine 2")
    # Viewport width 20, minus gutterWidth 4 = 16 chars per wrapped line
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 20, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 1, column: 0)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    check pos.x == 4
    # Line 0 wraps to multiple screen lines, then Line 2
    check pos.y > 1

  test "cursor on wrapped portion of line":
    let e = createTestEditor()
    e.state.lineWrap = true
    let longLine = "ABCDEFGHIJ" & "KLMNOPQRST" # 20 chars
    let buffer = newTextBuffer(longLine)
    # Viewport width 14, minus gutterWidth 4 = 10 chars per wrapped line
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 14, height: 24, x: 0, y: 0)
    # Cursor at column 15 (in the wrapped portion)
    let cursor = BufferPosition(line: 0, column: 15)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    # Should be on wrapped line (y=1) at column 5 (15 - 10 = 5)
    check pos.y == 1
    check pos.x == 4 + 5 # gutterWidth + column within wrapped line

  test "negative line returns (0, 0)":
    let e = createTestEditor()
    e.state.lineWrap = false
    let buffer = newTextBuffer("Hello")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: -1, column: 0)

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    check pos.x == 0
    check pos.y == 0

  test "cursor below visible area, no wrap":
    let e = createTestEditor()
    e.state.lineWrap = false
    let buffer = newTextBuffer("Line 1\nLine 2\nLine 3\nLine 4\nLine 5")
    # Small viewport height of 3, with reserved 2 = only 1 visible line
    let viewport = ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 3, x: 0, y: 0)
    let cursor = BufferPosition(line: 4, column: 0) # Beyond visible area

    let pos = e.calculateWindowCursor(
      buffer,
      viewport,
      cursor,
      gutterWidth = 4,
      reservedLines = steadyBottomAreaHeight(),
    )
    check pos.x == 0
    check pos.y == 0

suite "renderedCellPos":
  proc plainEditor(): Editor =
    result = createTestEditor()
    result.state.showLineNumbers = false
    result.state.showSidebar = false
    result.state.scrollbar = false
    result.tabStop = 4

  test "no wrap, no horizontal scroll":
    let e = plainEditor()
    e.state.lineWrap = false
    let win = e.activeWindow
    win.viewport.leftColumn = 0

    let pos = e.renderedCellPos(win, "ab\tcd", 3) # 'c'
    check pos.row == 0
    check pos.cellX == 4 # "ab" + tab filling the stop

  test "no wrap, horizontal scroll restarts tab stops":
    let e = plainEditor()
    e.state.lineWrap = false
    let win = e.activeWindow
    win.viewport.leftColumn = 2

    let pos = e.renderedCellPos(win, "ab\tcd", 3) # 'c'
    check pos.row == 0
    check pos.cellX == 4 # the tab is expanded from the slice start

  test "no wrap, horizontal scroll with full width characters":
    let e = plainEditor()
    e.state.lineWrap = false
    let win = e.activeWindow
    win.viewport.leftColumn = 2

    let pos = e.renderedCellPos(win, "あいうえお", 3) # え
    check pos.row == 0
    check pos.cellX == 2 # う takes 2 cells

  test "no wrap, column before leftColumn clamps to zero":
    let e = plainEditor()
    e.state.lineWrap = false
    let win = e.activeWindow
    win.viewport.leftColumn = 5

    let pos = e.renderedCellPos(win, "0123456789", 2)
    check pos.row == 0
    check pos.cellX == 0

  test "wrap mode reports the segment row and column":
    let e = plainEditor()
    e.state.lineWrap = true
    let win = e.activeWindow
    win.viewport.width = 4 # no gutter, so wrapWidth == 4

    check e.wrapWidth(win) == 4
    check e.renderedCellPos(win, "ab\tcd", 1) == (row: 0, cellX: 1) # 'b'
    check e.renderedCellPos(win, "ab\tcd", 3) == (row: 1, cellX: 0) # 'c' wrapped

  test "wrap mode ignores leftColumn":
    let e = plainEditor()
    e.state.lineWrap = true
    let win = e.activeWindow
    win.viewport.width = 4
    win.viewport.leftColumn = 2

    check e.renderedCellPos(win, "ab\tcd", 1) == (row: 0, cellX: 1)

suite "textAreaWidth / wrapWidth - single derivation":
  proc gutterEditor(): Editor =
    result = createTestEditor()
    result.state.showLineNumbers = true
    result.state.showSidebar = true
    result.state.scrollbar = true
    result.state.scrollbarWidth = 1

  test "text area is the viewport minus line number, sidebar and scrollbar":
    let e = gutterEditor()
    let win = e.activeWindow
    win.mode = EditorMode.Normal
    win.viewport.width = 40
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "abc")

    # 1 line -> 1 digit + LineNumberSpacer(1) = 2, sidebar 2, scrollbar 1.
    check e.viewportOffsetFor(win) == 5
    check e.textAreaWidth(win) == 35
    check e.wrapWidth(win) == 35

  test "gutter plus text area plus scrollbar covers the whole viewport":
    let e = gutterEditor()
    let win = e.activeWindow
    win.mode = EditorMode.Normal
    win.viewport.width = 40
    check e.gutterWidth(win) + e.textAreaWidth(win) + e.calculateScrollbarWidth(win) ==
      win.viewport.width

  test "explicit lineNumOffset overrides the window's own gutter":
    # The render pass threads the offset it draws with; the width must follow it
    # rather than re-deriving a different one.
    let e = gutterEditor()
    let win = e.activeWindow
    win.mode = EditorMode.Normal
    win.viewport.width = 40
    check e.textAreaWidth(win, 0) == 37 # sidebar 2 + scrollbar 1 only
    check e.wrapWidth(win, 10) == 27

  test "wrap width clamps to one cell when the gutters exceed the viewport":
    let e = gutterEditor()
    let win = e.activeWindow
    win.mode = EditorMode.Normal
    win.viewport.width = 3
    check e.textAreaWidth(win) == 0
    check e.wrapWidth(win) == 1

  test "a window holding a mode state drops sidebar and scrollbar":
    let e = gutterEditor()
    let win = e.activeWindow
    win.mode = EditorMode.Visual
    win.modeState = ModeState(kind: mskLogViewer, logViewer: newLogViewerState())
    win.viewport.width = 40
    check e.viewportOffsetFor(win) == 2 # line numbers only
    check e.textAreaWidth(win) == 38

  test "state-based and window-based offsets agree for the active window":
    # The motion / mouse paths pull the offset from EditorState, the render pass
    # from the window. A disagreement mis-keys the wrap-count cache.
    let e = gutterEditor()
    let win = e.activeWindow
    win.viewport.width = 40
    for mode in [EditorMode.Normal, EditorMode.Insert, EditorMode.Visual]:
      win.mode = mode
      check viewportOffsetFor(e.activeBuffer, e.state) == e.viewportOffsetFor(win)

    win.mode = EditorMode.Visual
    win.modeState = ModeState(kind: mskHelp, help: newHelpViewerState())
    check viewportOffsetFor(e.activeBuffer, e.state) == e.viewportOffsetFor(win)
