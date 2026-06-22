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

## Tests for bookmark_manager.nim

import std/[unittest, options, strutils]
import ../src/moepkg/bookmark_manager {.all.}
import ../src/moepkg/buffer {.all.}

proc createTestBuffers(): seq[TextBuffer] =
  ## Create test buffers with bookmarks for testing
  var buf1 = newTextBuffer("line 0\nline 1\nline 2\nline 3\nline 4")
  buf1.filePath = some("/path/file1.nim")
  buf1.toggleBookmark(1)
  buf1.toggleBookmark(3)

  var buf2 = newTextBuffer("alpha\nbeta\ngamma")
  buf2.filePath = some("/path/file2.nim")
  buf2.toggleBookmark(0)

  var buf3 = newTextBuffer("no bookmarks here")
  buf3.filePath = some("/path/file3.nim")

  @[buf1, buf2, buf3]

suite "BookmarkManagerState - Constructor":
  test "newBookmarkManagerState creates empty state":
    let state = newBookmarkManagerState()

    check state.items.len == 0
    check state.selectedIndex == 0
    check state.previousWindowIndex == 0

suite "BookmarkManagerState - updateEntries":
  test "Update entries from buffers with bookmarks":
    let state = newBookmarkManagerState()
    let buffers = createTestBuffers()

    state.updateEntries(buffers)

    # buf1 has 2 bookmarks (lines 1, 3), buf2 has 1 (line 0), buf3 has 0
    check state.items.len == 3

    check state.items[0].bufferIndex == 0
    check state.items[0].filePath == "/path/file1.nim"
    check state.items[0].line == 1
    check state.items[0].text == "line 1"

    check state.items[1].bufferIndex == 0
    check state.items[1].filePath == "/path/file1.nim"
    check state.items[1].line == 3
    check state.items[1].text == "line 3"

    check state.items[2].bufferIndex == 1
    check state.items[2].filePath == "/path/file2.nim"
    check state.items[2].line == 0
    check state.items[2].text == "alpha"

  test "Update entries from buffers with no bookmarks":
    let state = newBookmarkManagerState()
    let buf = newTextBuffer("hello")
    let buffers = @[buf]

    state.updateEntries(buffers)

    check state.items.len == 0

  test "Update entries with buffer without filePath shows No Name":
    let state = newBookmarkManagerState()
    var buf = newTextBuffer("line 0\nline 1")
    buf.toggleBookmark(0)
    let buffers = @[buf]

    state.updateEntries(buffers)

    check state.items.len == 1
    check state.items[0].filePath == "No Name"

  test "Update clamps selectedIndex when entries shrink":
    let state = newBookmarkManagerState()
    let buffers = createTestBuffers()
    state.updateEntries(buffers)
    state.selectedIndex = 2

    # Remove all bookmarks by using empty buffers
    let emptyBuf = newTextBuffer("no bookmarks")
    state.updateEntries(@[emptyBuf])

    check state.items.len == 0
    check state.selectedIndex == 0

  test "Update preserves valid selectedIndex":
    let state = newBookmarkManagerState()
    let buffers = createTestBuffers()
    state.updateEntries(buffers)
    state.selectedIndex = 1

    # Re-update with same buffers
    state.updateEntries(buffers)

    check state.items.len == 3
    check state.selectedIndex == 1

  test "Text preview is truncated to 50 chars":
    let state = newBookmarkManagerState()
    let longLine = "a".repeat(60)
    var buf = newTextBuffer(longLine)
    buf.toggleBookmark(0)

    state.updateEntries(@[buf])

    check state.items.len == 1
    check state.items[0].text.len < 60
    check state.items[0].text.endsWith("...")

  test "Bookmark on line beyond buffer length gives empty text":
    let state = newBookmarkManagerState()
    var buf = newTextBuffer("short")
    # Manually add an out-of-range bookmark
    buf.bookmarks.add(999)

    state.updateEntries(@[buf])

    check state.items.len == 1
    check state.items[0].text == ""

  test "Update entries from empty buffer list":
    let state = newBookmarkManagerState()

    state.updateEntries(@[])

    check state.items.len == 0
    check state.selectedIndex == 0

suite "BookmarkManagerState - Navigation":
  test "moveDown on empty state does not crash":
    let state = newBookmarkManagerState()
    # entries.len is 0, so entries.len - 1 is -1 (int)
    state.moveDown()

    check state.selectedIndex == 0

  test "moveUp on empty state does not crash":
    let state = newBookmarkManagerState()

    state.moveUp()

    check state.selectedIndex == 0

  test "moveUp decreases selectedIndex":
    let state = newBookmarkManagerState()
    let buffers = createTestBuffers()
    state.updateEntries(buffers)
    state.selectedIndex = 1

    state.moveUp()

    check state.selectedIndex == 0

  test "moveUp at top stays at top":
    let state = newBookmarkManagerState()
    let buffers = createTestBuffers()
    state.updateEntries(buffers)
    state.selectedIndex = 0

    state.moveUp()

    check state.selectedIndex == 0

  test "moveDown increases selectedIndex":
    let state = newBookmarkManagerState()
    let buffers = createTestBuffers()
    state.updateEntries(buffers)
    state.selectedIndex = 0

    state.moveDown()

    check state.selectedIndex == 1

  test "moveDown at bottom stays at bottom":
    let state = newBookmarkManagerState()
    let buffers = createTestBuffers()
    state.updateEntries(buffers)
    state.selectedIndex = 2

    state.moveDown()

    check state.selectedIndex == 2

  test "moveDown multiple times":
    let state = newBookmarkManagerState()
    let buffers = createTestBuffers()
    state.updateEntries(buffers)
    state.selectedIndex = 0

    state.moveDown()
    state.moveDown()

    check state.selectedIndex == 2

    # Should not go beyond last entry
    state.moveDown()
    check state.selectedIndex == 2

suite "BookmarkManagerState - getSelectedItem":
  test "Get selected entry returns correct entry":
    let state = newBookmarkManagerState()
    let buffers = createTestBuffers()
    state.updateEntries(buffers)
    state.selectedIndex = 1

    let entry = state.getSelectedItem()

    check entry.isSome
    check entry.get.filePath == "/path/file1.nim"
    check entry.get.line == 3

  test "Get selected entry from empty state returns none":
    let state = newBookmarkManagerState()

    let entry = state.getSelectedItem()

    check entry.isNone

  test "Get selected entry with invalid index returns none":
    let state = newBookmarkManagerState()
    let buffers = createTestBuffers()
    state.updateEntries(buffers)
    state.selectedIndex = 10

    let entry = state.getSelectedItem()

    check entry.isNone

  test "Get selected entry with negative index returns none":
    let state = newBookmarkManagerState()
    let buffers = createTestBuffers()
    state.updateEntries(buffers)
    state.selectedIndex = -1

    let entry = state.getSelectedItem()

    check entry.isNone

suite "BookmarkEntry - formatLine":
  test "Format entry with file path and line":
    let entry = BookmarkEntry(
      bufferIndex: 0, filePath: "/path/file.nim", line: 41, text: "proc hello"
    )

    let formatted = formatLine(entry)

    check formatted == "  /path/file.nim:42  proc hello"

  test "Format entry with No Name":
    let entry =
      BookmarkEntry(bufferIndex: 0, filePath: "No Name", line: 0, text: "first line")

    let formatted = formatLine(entry)

    check formatted == "  No Name:1  first line"

  test "Format entry with empty text":
    let entry = BookmarkEntry(bufferIndex: 0, filePath: "/file.nim", line: 5, text: "")

    let formatted = formatLine(entry)

    check formatted == "  /file.nim:6  "

suite "BookmarkManagerState - createBookmarkManagerTextBuffer":
  test "Create text buffer with entries":
    let state = newBookmarkManagerState()
    let buffers = createTestBuffers()
    state.updateEntries(buffers)

    let buf = state.createBookmarkManagerTextBuffer()

    check buf.readOnly == true
    # Header + 3 entries = 4 lines
    check buf.len == 4
    check buf.getLine(0) == "-- Bookmark Manager --"

  test "Create text buffer content matches formatLine":
    let state = newBookmarkManagerState()
    var buf = newTextBuffer("hello\nworld")
    buf.filePath = some("test.nim")
    buf.toggleBookmark(0)
    buf.toggleBookmark(1)
    state.updateEntries(@[buf])

    let textBuf = state.createBookmarkManagerTextBuffer()

    check textBuf.len == 3
    check textBuf.getLine(1) == formatLine(state.items[0])
    check textBuf.getLine(2) == formatLine(state.items[1])

  test "Create text buffer with no entries":
    let state = newBookmarkManagerState()

    let buf = state.createBookmarkManagerTextBuffer()

    check buf.readOnly == true
    check buf.len == 2
    check buf.getLine(0) == "-- Bookmark Manager --"
    check buf.getLine(1) == "  No bookmarks"

suite "BookmarkManagerState - deleteSelectedBookmark":
  test "Delete selected bookmark removes it from buffer":
    let state = newBookmarkManagerState()
    let buffers = createTestBuffers()
    state.updateEntries(buffers)
    state.selectedIndex = 0 # First bookmark: file1.nim line 1

    check state.items.len == 3
    check buffers[0].hasBookmark(1) == true

    state.deleteSelectedBookmark(buffers)

    # Bookmark should be removed from buffer
    check buffers[0].hasBookmark(1) == false
    # Entries should be refreshed (now 2 entries)
    check state.items.len == 2

  test "Delete last remaining bookmark":
    let state = newBookmarkManagerState()
    var buf = newTextBuffer("only line")
    buf.toggleBookmark(0)
    let buffers = @[buf]
    state.updateEntries(buffers)
    state.selectedIndex = 0

    state.deleteSelectedBookmark(buffers)

    check state.items.len == 0
    check state.selectedIndex == 0
    check buf.hasBookmark(0) == false

  test "Delete with empty state does nothing":
    let state = newBookmarkManagerState()
    let buf = newTextBuffer("no bookmarks")
    let buffers = @[buf]

    state.deleteSelectedBookmark(buffers)

    check state.items.len == 0

  test "Delete middle entry preserves correct remaining entries":
    let state = newBookmarkManagerState()
    var buf1 = newTextBuffer("a\nb\nc")
    buf1.filePath = some("buf1.nim")
    buf1.toggleBookmark(0) # entry 0
    buf1.toggleBookmark(2) # entry 1

    var buf2 = newTextBuffer("x\ny")
    buf2.filePath = some("buf2.nim")
    buf2.toggleBookmark(1) # entry 2

    let buffers = @[buf1, buf2]
    state.updateEntries(buffers)
    check state.items.len == 3
    state.selectedIndex = 1 # buf1 line 2

    state.deleteSelectedBookmark(buffers)

    check state.items.len == 2
    # Remaining: buf1 line 0, buf2 line 1
    check state.items[0].bufferIndex == 0
    check state.items[0].line == 0
    check state.items[1].bufferIndex == 1
    check state.items[1].line == 1

  test "Delete consecutively removes bookmarks one by one":
    let state = newBookmarkManagerState()
    var buf = newTextBuffer("a\nb\nc")
    buf.toggleBookmark(0)
    buf.toggleBookmark(1)
    buf.toggleBookmark(2)
    let buffers = @[buf]
    state.updateEntries(buffers)
    check state.items.len == 3

    # Delete first
    state.selectedIndex = 0
    state.deleteSelectedBookmark(buffers)
    check state.items.len == 2

    # Delete first again (was second)
    state.selectedIndex = 0
    state.deleteSelectedBookmark(buffers)
    check state.items.len == 1

    # Delete last
    state.selectedIndex = 0
    state.deleteSelectedBookmark(buffers)
    check state.items.len == 0
    check buf.bookmarks.len == 0

  test "Delete clamps selectedIndex":
    let state = newBookmarkManagerState()
    var buf = newTextBuffer("line 0\nline 1")
    buf.toggleBookmark(0)
    buf.toggleBookmark(1)
    let buffers = @[buf]
    state.updateEntries(buffers)
    state.selectedIndex = 1 # Last entry

    state.deleteSelectedBookmark(buffers)

    # After deleting line 1 bookmark, only line 0 bookmark remains
    check state.items.len == 1
    check state.selectedIndex == 0 # Clamped

suite "BookmarkManagerState - Integration":
  test "Full workflow: create, update, navigate, delete, select":
    let state = newBookmarkManagerState()
    let buffers = createTestBuffers()

    # Initial state
    check state.items.len == 0

    # Update entries
    state.updateEntries(buffers)
    check state.items.len == 3
    check state.selectedIndex == 0

    # Navigate down
    state.moveDown()
    check state.selectedIndex == 1

    # Get selected entry
    let entry = state.getSelectedItem()
    check entry.isSome
    check entry.get.line == 3

    # Delete the selected bookmark
    state.deleteSelectedBookmark(buffers)
    check state.items.len == 2
    # file1.nim line 1 + file2.nim line 0
    check state.items[0].line == 1
    check state.items[1].line == 0

    # Navigate to end
    state.moveDown()
    check state.selectedIndex == 1

    # Try to go past end
    state.moveDown()
    check state.selectedIndex == 1

    # Navigate back to top
    state.moveUp()
    check state.selectedIndex == 0

    # Try to go before start
    state.moveUp()
    check state.selectedIndex == 0

  test "Multiple buffers with bookmarks across all":
    let state = newBookmarkManagerState()
    var buf1 = newTextBuffer("a\nb\nc")
    buf1.filePath = some("buf1.nim")
    buf1.toggleBookmark(0)
    buf1.toggleBookmark(2)

    var buf2 = newTextBuffer("x\ny\nz")
    buf2.filePath = some("buf2.nim")
    buf2.toggleBookmark(1)

    state.updateEntries(@[buf1, buf2])

    check state.items.len == 3
    check state.items[0].bufferIndex == 0
    check state.items[0].line == 0
    check state.items[1].bufferIndex == 0
    check state.items[1].line == 2
    check state.items[2].bufferIndex == 1
    check state.items[2].line == 1
