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

import std/[options, unittest]

import pkg/celina

import ../src/moepkg/[buffer, sidebar, color, theme]

suite "Sidebar - initSidebar":
  test "Initialize sidebar with default width":
    let sidebar = initSidebar(10)

    check sidebar.width == DefaultSidebarWidth
    check sidebar.buffer.len == 10
    for y in 0 ..< 10:
      check sidebar.buffer[y].len == DefaultSidebarWidth
      for x in 0 ..< DefaultSidebarWidth:
        check sidebar.buffer[y][x].kind.isNone
        check sidebar.buffer[y][x].text == " "

  test "Initialize sidebar with custom width":
    let sidebar = initSidebar(5, 3)

    check sidebar.width == 3
    check sidebar.buffer.len == 5
    for y in 0 ..< 5:
      check sidebar.buffer[y].len == 3

  test "Initialize sidebar with zero height":
    let sidebar = initSidebar(0)

    check sidebar.buffer.len == 0
    check sidebar.width == DefaultSidebarWidth

suite "Sidebar - clearSidebar":
  test "Clear sidebar resets all cells to empty":
    var sidebar = initSidebar(5)
    sidebar.setSidebarLine(0, "+ ", GitAdded)
    sidebar.setSidebarLine(2, "~ ", GitChanged)

    sidebar.clearSidebar()

    for y in 0 ..< 5:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind.isNone
        check sidebar.buffer[y][x].text == " "

suite "Sidebar - resizeSidebar":
  test "Resize sidebar to larger height":
    var sidebar = initSidebar(3)
    sidebar.setSidebarLine(0, "+ ", GitAdded)

    sidebar.resizeSidebar(5)

    check sidebar.buffer.len == 5
    # Original content preserved
    check sidebar.buffer[0][0].kind == some(GitAdded)
    # New lines are empty
    check sidebar.buffer[3][0].kind.isNone
    check sidebar.buffer[4][0].kind.isNone

  test "Resize sidebar to smaller height":
    var sidebar = initSidebar(5)
    sidebar.setSidebarLine(0, "+ ", GitAdded)
    sidebar.setSidebarLine(4, "~ ", GitChanged)

    sidebar.resizeSidebar(3)

    check sidebar.buffer.len == 3
    # Original content preserved within bounds
    check sidebar.buffer[0][0].kind == some(GitAdded)

  test "Resize sidebar to same height":
    var sidebar = initSidebar(5)
    sidebar.setSidebarLine(2, "+ ", GitAdded)

    sidebar.resizeSidebar(5)

    check sidebar.buffer.len == 5
    check sidebar.buffer[2][0].kind == some(GitAdded)

suite "Sidebar - setSidebarItem":
  test "Set single sidebar item":
    var sidebar = initSidebar(5)

    sidebar.setSidebarItem(2, 0, "+", GitAdded)

    check sidebar.buffer[2][0].kind == some(GitAdded)
    check sidebar.buffer[2][0].text == "+"
    # Other cells unchanged
    check sidebar.buffer[2][1].kind.isNone
    check sidebar.buffer[0][0].kind.isNone

  test "Set item out of bounds (negative line) does nothing":
    var sidebar = initSidebar(5)

    sidebar.setSidebarItem(-1, 0, "+", GitAdded)

    # All cells should remain empty
    for y in 0 ..< 5:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind.isNone

  test "Set item out of bounds (line too large) does nothing":
    var sidebar = initSidebar(5)

    sidebar.setSidebarItem(10, 0, "+", GitAdded)

    # All cells should remain empty
    for y in 0 ..< 5:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind.isNone

  test "Set item out of bounds (negative col) does nothing":
    var sidebar = initSidebar(5)

    sidebar.setSidebarItem(2, -1, "+", GitAdded)

    for y in 0 ..< 5:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind.isNone

  test "Set item out of bounds (col too large) does nothing":
    var sidebar = initSidebar(5)

    sidebar.setSidebarItem(2, 10, "+", GitAdded)

    for y in 0 ..< 5:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind.isNone

suite "Sidebar - setSidebarLine":
  test "Set entire sidebar line":
    var sidebar = initSidebar(5)

    sidebar.setSidebarLine(2, "+ ", GitAdded)

    check sidebar.buffer[2][0].kind == some(GitAdded)
    check sidebar.buffer[2][0].text == "+"
    check sidebar.buffer[2][1].kind == some(GitAdded)
    check sidebar.buffer[2][1].text == " "

  test "Set line with short text pads with spaces":
    var sidebar = initSidebar(5, 4)

    sidebar.setSidebarLine(1, "+", GitAdded)

    check sidebar.buffer[1][0].text == "+"
    check sidebar.buffer[1][1].text == " "
    check sidebar.buffer[1][2].text == " "
    check sidebar.buffer[1][3].text == " "
    for x in 0 ..< 4:
      check sidebar.buffer[1][x].kind == some(GitAdded)

  test "Set line out of bounds (negative) does nothing":
    var sidebar = initSidebar(5)

    sidebar.setSidebarLine(-1, "+ ", GitAdded)

    for y in 0 ..< 5:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind.isNone

  test "Set line out of bounds (too large) does nothing":
    var sidebar = initSidebar(5)

    sidebar.setSidebarLine(10, "+ ", GitAdded)

    for y in 0 ..< 5:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind.isNone

suite "Sidebar - clearSidebarLine":
  test "Clear specific sidebar line":
    var sidebar = initSidebar(5)
    sidebar.setSidebarLine(0, "+ ", GitAdded)
    sidebar.setSidebarLine(2, "~ ", GitChanged)
    sidebar.setSidebarLine(4, ">>", SyntaxError)

    sidebar.clearSidebarLine(2)

    # Line 0 unchanged
    check sidebar.buffer[0][0].kind == some(GitAdded)
    # Line 2 cleared
    check sidebar.buffer[2][0].kind.isNone
    check sidebar.buffer[2][1].kind.isNone
    # Line 4 unchanged
    check sidebar.buffer[4][0].kind == some(SyntaxError)

  test "Clear line out of bounds does nothing":
    var sidebar = initSidebar(5)
    sidebar.setSidebarLine(2, "+ ", GitAdded)

    sidebar.clearSidebarLine(-1)
    sidebar.clearSidebarLine(10)

    # Original content preserved
    check sidebar.buffer[2][0].kind == some(GitAdded)

suite "Sidebar - Git markers":
  test "updateSidebarForGitAdded":
    var sidebar = initSidebar(5)

    sidebar.updateSidebarForGitAdded(2)

    check sidebar.buffer[2][0].kind == some(GitAdded)
    check sidebar.buffer[2][0].text == "+"
    check sidebar.buffer[2][1].text == " "

  test "updateSidebarForGitChanged":
    var sidebar = initSidebar(5)

    sidebar.updateSidebarForGitChanged(3)

    check sidebar.buffer[3][0].kind == some(GitChanged)
    check sidebar.buffer[3][0].text == "~"
    check sidebar.buffer[3][1].text == " "

  test "updateSidebarForGitDeleted":
    var sidebar = initSidebar(5)

    sidebar.updateSidebarForGitDeleted(1)

    check sidebar.buffer[1][0].kind == some(GitDeleted)
    check sidebar.buffer[1][0].text == "_"
    check sidebar.buffer[1][1].text == " "

  test "updateSidebarForGitChangedAndDeleted":
    var sidebar = initSidebar(5)

    sidebar.updateSidebarForGitChangedAndDeleted(4)

    check sidebar.buffer[4][0].kind == some(GitChangedAndDeleted)
    check sidebar.buffer[4][0].text == "~"
    check sidebar.buffer[4][1].text == "_"

suite "Sidebar - Syntax markers":
  test "updateSidebarForSyntaxError":
    var sidebar = initSidebar(5)

    sidebar.updateSidebarForSyntaxError(0)

    check sidebar.buffer[0][0].kind == some(SyntaxError)
    check sidebar.buffer[0][0].text == ">"
    check sidebar.buffer[0][1].text == ">"

  test "updateSidebarForSyntaxWarning":
    var sidebar = initSidebar(5)

    sidebar.updateSidebarForSyntaxWarning(2)

    check sidebar.buffer[2][0].kind == some(SyntaxWarning)

suite "Sidebar - generateSidebarFromBuffer":
  test "Generate sidebar from buffer with no markers":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3")

    let sidebar = generateSidebarFromBuffer(buf, 0, 3)

    check sidebar.buffer.len == 3
    for y in 0 ..< 3:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind.isNone

  test "Generate sidebar from buffer with GitAdded marker":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3")
    buf.setLineMarker(1, GitAdded)

    let sidebar = generateSidebarFromBuffer(buf, 0, 3)

    check sidebar.buffer[0][0].kind.isNone
    check sidebar.buffer[1][0].kind == some(GitAdded)
    check sidebar.buffer[1][0].text == "+"
    check sidebar.buffer[2][0].kind.isNone

  test "Generate sidebar from buffer with multiple markers":
    let buf = newTextBuffer()
    discard buf.insertText(
      BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3\nLine 4\nLine 5"
    )
    buf.setLineMarker(0, GitAdded)
    buf.setLineMarker(2, GitChanged)
    buf.setLineMarker(4, SyntaxError)

    let sidebar = generateSidebarFromBuffer(buf, 0, 5)

    check sidebar.buffer[0][0].kind == some(GitAdded)
    check sidebar.buffer[1][0].kind.isNone
    check sidebar.buffer[2][0].kind == some(GitChanged)
    check sidebar.buffer[3][0].kind.isNone
    check sidebar.buffer[4][0].kind == some(SyntaxError)

  test "Generate sidebar with topLine offset":
    let buf = newTextBuffer()
    discard buf.insertText(
      BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3\nLine 4\nLine 5"
    )
    buf.setLineMarker(0, GitAdded)
    buf.setLineMarker(2, GitChanged)
    buf.setLineMarker(4, SyntaxError)

    # View starting from line 2
    let sidebar = generateSidebarFromBuffer(buf, 2, 3)

    check sidebar.buffer.len == 3
    # Screen line 0 = buffer line 2
    check sidebar.buffer[0][0].kind == some(GitChanged)
    # Screen line 1 = buffer line 3
    check sidebar.buffer[1][0].kind.isNone
    # Screen line 2 = buffer line 4
    check sidebar.buffer[2][0].kind == some(SyntaxError)

  test "Generate sidebar with height larger than buffer":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2")
    buf.setLineMarker(0, GitAdded)

    let sidebar = generateSidebarFromBuffer(buf, 0, 5)

    check sidebar.buffer.len == 5
    check sidebar.buffer[0][0].kind == some(GitAdded)
    check sidebar.buffer[1][0].kind.isNone
    # Lines beyond buffer remain empty
    check sidebar.buffer[2][0].kind.isNone
    check sidebar.buffer[3][0].kind.isNone
    check sidebar.buffer[4][0].kind.isNone

  test "Generate sidebar with custom width":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    buf.setLineMarker(0, GitAdded)

    let sidebar = generateSidebarFromBuffer(buf, 0, 1, 4)

    check sidebar.width == 4
    check sidebar.buffer[0].len == 4
    check sidebar.buffer[0][0].kind == some(GitAdded)

suite "Sidebar - Style functions":
  test "gitAddedStyle uses the sidebarGitAddedSign theme color":
    initDefaultTheme()
    check gitAddedStyle() == getThemeStyle(EditorColorPairIndex.sidebarGitAddedSign)

  test "gitChangedStyle uses the sidebarGitChangedSign theme color":
    initDefaultTheme()
    check gitChangedStyle() == getThemeStyle(EditorColorPairIndex.sidebarGitChangedSign)

  test "gitDeletedStyle uses the sidebarGitDeletedSign theme color":
    initDefaultTheme()
    check gitDeletedStyle() == getThemeStyle(EditorColorPairIndex.sidebarGitDeletedSign)

  test "syntaxErrorStyle uses the sidebarSyntaxCheckErrSign theme color with bold":
    initDefaultTheme()
    check syntaxErrorStyle() ==
      getThemeStyle(
        EditorColorPairIndex.sidebarSyntaxCheckErrSign, {StyleModifier.Bold}
      )

  test "syntaxWarningStyle uses the sidebarSyntaxCheckWarnSign theme color":
    initDefaultTheme()
    check syntaxWarningStyle() ==
      getThemeStyle(EditorColorPairIndex.sidebarSyntaxCheckWarnSign)

  test "emptyStyle has default foreground":
    let style = emptyStyle()
    check style.fg.kind == Default

suite "Sidebar - resizeSidebar edge cases":
  test "Resize sidebar to zero height":
    var sidebar = initSidebar(5)
    sidebar.setSidebarLine(0, "+ ", GitAdded)

    sidebar.resizeSidebar(0)

    check sidebar.buffer.len == 0

  test "Resize from zero height to positive":
    var sidebar = initSidebar(0)

    sidebar.resizeSidebar(3)

    check sidebar.buffer.len == 3
    for y in 0 ..< 3:
      check sidebar.buffer[y].len == sidebar.width
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind.isNone

suite "Sidebar - globalMarkerConfig":
  test "Custom marker config affects git markers":
    let originalConfig = globalMarkerConfig

    globalMarkerConfig.gitAdded = "A "
    globalMarkerConfig.gitChanged = "M "

    var sidebar = initSidebar(3)
    sidebar.updateSidebarForGitAdded(0)
    sidebar.updateSidebarForGitChanged(1)

    check sidebar.buffer[0][0].text == "A"
    check sidebar.buffer[0][1].text == " "
    check sidebar.buffer[1][0].text == "M"
    check sidebar.buffer[1][1].text == " "

    globalMarkerConfig = originalConfig

  test "Custom marker config affects syntax markers":
    let originalConfig = globalMarkerConfig

    globalMarkerConfig.syntaxError = "EE"
    globalMarkerConfig.syntaxWarning = "WW"

    var sidebar = initSidebar(2)
    sidebar.updateSidebarForSyntaxError(0)
    sidebar.updateSidebarForSyntaxWarning(1)

    check sidebar.buffer[0][0].text == "E"
    check sidebar.buffer[0][1].text == "E"
    check sidebar.buffer[1][0].text == "W"
    check sidebar.buffer[1][1].text == "W"

    globalMarkerConfig = originalConfig

suite "Sidebar - generateSidebarFromBuffer edge cases":
  test "Generate sidebar from empty buffer":
    let buf = newTextBuffer()

    let sidebar = generateSidebarFromBuffer(buf, 0, 3)

    check sidebar.buffer.len == 3
    for y in 0 ..< 3:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind.isNone

  test "Generate sidebar with GitDeleted marker":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2")
    buf.setLineMarker(0, GitDeleted)

    let sidebar = generateSidebarFromBuffer(buf, 0, 2)

    check sidebar.buffer[0][0].kind == some(GitDeleted)
    check sidebar.buffer[0][0].text == "_"
    check sidebar.buffer[1][0].kind.isNone

  test "Generate sidebar with GitChangedAndDeleted marker":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    buf.setLineMarker(0, GitChangedAndDeleted)

    let sidebar = generateSidebarFromBuffer(buf, 0, 1)

    check sidebar.buffer[0][0].kind == some(GitChangedAndDeleted)
    check sidebar.buffer[0][0].text == "~"
    check sidebar.buffer[0][1].text == "_"

  test "Generate sidebar with SyntaxWarning marker":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    buf.setLineMarker(0, SyntaxWarning)

    let sidebar = generateSidebarFromBuffer(buf, 0, 1)

    check sidebar.buffer[0][0].kind == some(SyntaxWarning)

  test "Generate sidebar with topLine beyond buffer":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2")
    buf.setLineMarker(0, GitAdded)

    let sidebar = generateSidebarFromBuffer(buf, 10, 3)

    check sidebar.buffer.len == 3
    for y in 0 ..< 3:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind.isNone

  test "Generate sidebar with zero height":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")

    let sidebar = generateSidebarFromBuffer(buf, 0, 0)

    check sidebar.buffer.len == 0

  test "Generate sidebar with all marker kinds":
    let buf = newTextBuffer()
    discard buf.insertText(
      BufferPosition(line: 0, column: 0),
      "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6",
    )
    buf.setLineMarker(0, GitAdded)
    buf.setLineMarker(1, GitChanged)
    buf.setLineMarker(2, GitDeleted)
    buf.setLineMarker(3, GitChangedAndDeleted)
    buf.setLineMarker(4, SyntaxError)
    buf.setLineMarker(5, SyntaxWarning)

    let sidebar = generateSidebarFromBuffer(buf, 0, 6)

    check sidebar.buffer[0][0].kind == some(GitAdded)
    check sidebar.buffer[1][0].kind == some(GitChanged)
    check sidebar.buffer[2][0].kind == some(GitDeleted)
    check sidebar.buffer[3][0].kind == some(GitChangedAndDeleted)
    check sidebar.buffer[4][0].kind == some(SyntaxError)
    check sidebar.buffer[5][0].kind == some(SyntaxWarning)

suite "Sidebar - Bookmark display":
  test "bookmarkStyle uses the sidebarBookmarkSign theme color with bold":
    initDefaultTheme()
    check bookmarkStyle() ==
      getThemeStyle(EditorColorPairIndex.sidebarBookmarkSign, {StyleModifier.Bold})

  test "Bookmark shown on line with no marker":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3")
    buf.toggleBookmark(1)

    let sidebar = generateSidebarFromBuffer(buf, 0, 3, bookmarks = buf.bookmarks)

    check sidebar.buffer[0][0].kind.isNone
    check sidebar.buffer[1][0].kind == some(Bookmark)
    check sidebar.buffer[2][0].kind.isNone

  test "Bookmark overrides git marker":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3")
    buf.setLineMarker(1, GitAdded)
    buf.toggleBookmark(1)

    let sidebar = generateSidebarFromBuffer(buf, 0, 3, bookmarks = buf.bookmarks)

    check sidebar.buffer[1][0].kind == some(Bookmark)

  test "SyntaxError overrides bookmark":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3")
    buf.setLineMarker(1, SyntaxError)
    buf.toggleBookmark(1)

    let sidebar = generateSidebarFromBuffer(buf, 0, 3, bookmarks = buf.bookmarks)

    check sidebar.buffer[1][0].kind == some(SyntaxError)

  test "SyntaxWarning overrides bookmark":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2")
    buf.setLineMarker(0, SyntaxWarning)
    buf.toggleBookmark(0)

    let sidebar = generateSidebarFromBuffer(buf, 0, 2, bookmarks = buf.bookmarks)

    check sidebar.buffer[0][0].kind == some(SyntaxWarning)

  test "Multiple bookmarks displayed correctly":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\nd\ne")
    buf.toggleBookmark(0)
    buf.toggleBookmark(2)
    buf.toggleBookmark(4)

    let sidebar = generateSidebarFromBuffer(buf, 0, 5, bookmarks = buf.bookmarks)

    check sidebar.buffer[0][0].kind == some(Bookmark)
    check sidebar.buffer[1][0].kind.isNone
    check sidebar.buffer[2][0].kind == some(Bookmark)
    check sidebar.buffer[3][0].kind.isNone
    check sidebar.buffer[4][0].kind == some(Bookmark)

  test "Bookmark with topLine offset":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\nd\ne")
    buf.toggleBookmark(3)

    let sidebar = generateSidebarFromBuffer(buf, 2, 3, bookmarks = buf.bookmarks)

    # Screen line 0 = buffer line 2 (no bookmark)
    check sidebar.buffer[0][0].kind.isNone
    # Screen line 1 = buffer line 3 (bookmarked)
    check sidebar.buffer[1][0].kind == some(Bookmark)
    # Screen line 2 = buffer line 4 (no bookmark)
    check sidebar.buffer[2][0].kind.isNone

  test "Bookmark uses default marker text":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    buf.toggleBookmark(0)

    let sidebar = generateSidebarFromBuffer(buf, 0, 1, bookmarks = buf.bookmarks)

    # Default bookmark marker is "♥ " (multi-byte, first char is ♥)
    check sidebar.buffer[0][0].kind == some(Bookmark)

  test "setBookmarkMarker changes marker text":
    # Use ASCII marker to avoid multi-byte splitting issues in sidebar cells
    setBookmarkMarker("B ")

    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    buf.toggleBookmark(0)

    let sidebar = generateSidebarFromBuffer(buf, 0, 1, bookmarks = buf.bookmarks)

    check sidebar.buffer[0][0].kind == some(Bookmark)
    check sidebar.buffer[0][0].text == "B"
    check sidebar.buffer[0][1].text == " "

    # Restore default
    setBookmarkMarker("♥ ")
