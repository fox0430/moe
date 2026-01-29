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

import std/unittest

import pkg/celina

import ../src/moepkg/[buffer, sidebar]

suite "Sidebar - initSidebar":
  test "Initialize sidebar with default width":
    let sidebar = initSidebar(10)

    check sidebar.width == DefaultSidebarWidth
    check sidebar.buffer.len == 10
    for y in 0 ..< 10:
      check sidebar.buffer[y].len == DefaultSidebarWidth
      for x in 0 ..< DefaultSidebarWidth:
        check sidebar.buffer[y][x].kind == Empty
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
        check sidebar.buffer[y][x].kind == Empty
        check sidebar.buffer[y][x].text == " "

suite "Sidebar - resizeSidebar":
  test "Resize sidebar to larger height":
    var sidebar = initSidebar(3)
    sidebar.setSidebarLine(0, "+ ", GitAdded)

    sidebar.resizeSidebar(5)

    check sidebar.buffer.len == 5
    # Original content preserved
    check sidebar.buffer[0][0].kind == GitAdded
    # New lines are empty
    check sidebar.buffer[3][0].kind == Empty
    check sidebar.buffer[4][0].kind == Empty

  test "Resize sidebar to smaller height":
    var sidebar = initSidebar(5)
    sidebar.setSidebarLine(0, "+ ", GitAdded)
    sidebar.setSidebarLine(4, "~ ", GitChanged)

    sidebar.resizeSidebar(3)

    check sidebar.buffer.len == 3
    # Original content preserved within bounds
    check sidebar.buffer[0][0].kind == GitAdded

  test "Resize sidebar to same height":
    var sidebar = initSidebar(5)
    sidebar.setSidebarLine(2, "+ ", GitAdded)

    sidebar.resizeSidebar(5)

    check sidebar.buffer.len == 5
    check sidebar.buffer[2][0].kind == GitAdded

suite "Sidebar - setSidebarItem":
  test "Set single sidebar item":
    var sidebar = initSidebar(5)

    sidebar.setSidebarItem(2, 0, "+", GitAdded)

    check sidebar.buffer[2][0].kind == GitAdded
    check sidebar.buffer[2][0].text == "+"
    # Other cells unchanged
    check sidebar.buffer[2][1].kind == Empty
    check sidebar.buffer[0][0].kind == Empty

  test "Set item out of bounds (negative line) does nothing":
    var sidebar = initSidebar(5)

    sidebar.setSidebarItem(-1, 0, "+", GitAdded)

    # All cells should remain empty
    for y in 0 ..< 5:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind == Empty

  test "Set item out of bounds (line too large) does nothing":
    var sidebar = initSidebar(5)

    sidebar.setSidebarItem(10, 0, "+", GitAdded)

    # All cells should remain empty
    for y in 0 ..< 5:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind == Empty

  test "Set item out of bounds (negative col) does nothing":
    var sidebar = initSidebar(5)

    sidebar.setSidebarItem(2, -1, "+", GitAdded)

    for y in 0 ..< 5:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind == Empty

  test "Set item out of bounds (col too large) does nothing":
    var sidebar = initSidebar(5)

    sidebar.setSidebarItem(2, 10, "+", GitAdded)

    for y in 0 ..< 5:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind == Empty

suite "Sidebar - setSidebarLine":
  test "Set entire sidebar line":
    var sidebar = initSidebar(5)

    sidebar.setSidebarLine(2, "+ ", GitAdded)

    check sidebar.buffer[2][0].kind == GitAdded
    check sidebar.buffer[2][0].text == "+"
    check sidebar.buffer[2][1].kind == GitAdded
    check sidebar.buffer[2][1].text == " "

  test "Set line with short text pads with spaces":
    var sidebar = initSidebar(5, 4)

    sidebar.setSidebarLine(1, "+", GitAdded)

    check sidebar.buffer[1][0].text == "+"
    check sidebar.buffer[1][1].text == " "
    check sidebar.buffer[1][2].text == " "
    check sidebar.buffer[1][3].text == " "
    for x in 0 ..< 4:
      check sidebar.buffer[1][x].kind == GitAdded

  test "Set line out of bounds (negative) does nothing":
    var sidebar = initSidebar(5)

    sidebar.setSidebarLine(-1, "+ ", GitAdded)

    for y in 0 ..< 5:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind == Empty

  test "Set line out of bounds (too large) does nothing":
    var sidebar = initSidebar(5)

    sidebar.setSidebarLine(10, "+ ", GitAdded)

    for y in 0 ..< 5:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind == Empty

suite "Sidebar - clearSidebarLine":
  test "Clear specific sidebar line":
    var sidebar = initSidebar(5)
    sidebar.setSidebarLine(0, "+ ", GitAdded)
    sidebar.setSidebarLine(2, "~ ", GitChanged)
    sidebar.setSidebarLine(4, ">>", SyntaxError)

    sidebar.clearSidebarLine(2)

    # Line 0 unchanged
    check sidebar.buffer[0][0].kind == GitAdded
    # Line 2 cleared
    check sidebar.buffer[2][0].kind == Empty
    check sidebar.buffer[2][1].kind == Empty
    # Line 4 unchanged
    check sidebar.buffer[4][0].kind == SyntaxError

  test "Clear line out of bounds does nothing":
    var sidebar = initSidebar(5)
    sidebar.setSidebarLine(2, "+ ", GitAdded)

    sidebar.clearSidebarLine(-1)
    sidebar.clearSidebarLine(10)

    # Original content preserved
    check sidebar.buffer[2][0].kind == GitAdded

suite "Sidebar - Git markers":
  test "updateSidebarForGitAdded":
    var sidebar = initSidebar(5)

    sidebar.updateSidebarForGitAdded(2)

    check sidebar.buffer[2][0].kind == GitAdded
    check sidebar.buffer[2][0].text == "+"
    check sidebar.buffer[2][1].text == " "

  test "updateSidebarForGitChanged":
    var sidebar = initSidebar(5)

    sidebar.updateSidebarForGitChanged(3)

    check sidebar.buffer[3][0].kind == GitChanged
    check sidebar.buffer[3][0].text == "~"
    check sidebar.buffer[3][1].text == " "

  test "updateSidebarForGitDeleted":
    var sidebar = initSidebar(5)

    sidebar.updateSidebarForGitDeleted(1)

    check sidebar.buffer[1][0].kind == GitDeleted
    check sidebar.buffer[1][0].text == "_"
    check sidebar.buffer[1][1].text == " "

  test "updateSidebarForGitChangedAndDeleted":
    var sidebar = initSidebar(5)

    sidebar.updateSidebarForGitChangedAndDeleted(4)

    check sidebar.buffer[4][0].kind == GitChangedAndDeleted
    check sidebar.buffer[4][0].text == "~"
    check sidebar.buffer[4][1].text == "_"

suite "Sidebar - Syntax markers":
  test "updateSidebarForSyntaxError":
    var sidebar = initSidebar(5)

    sidebar.updateSidebarForSyntaxError(0)

    check sidebar.buffer[0][0].kind == SyntaxError
    check sidebar.buffer[0][0].text == ">"
    check sidebar.buffer[0][1].text == ">"

  test "updateSidebarForSyntaxWarning":
    var sidebar = initSidebar(5)

    sidebar.updateSidebarForSyntaxWarning(2)

    check sidebar.buffer[2][0].kind == SyntaxWarning

suite "Sidebar - generateSidebarFromBuffer":
  test "Generate sidebar from buffer with no markers":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3")

    let sidebar = generateSidebarFromBuffer(buf, 0, 3)

    check sidebar.buffer.len == 3
    for y in 0 ..< 3:
      for x in 0 ..< sidebar.width:
        check sidebar.buffer[y][x].kind == Empty

  test "Generate sidebar from buffer with GitAdded marker":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3")
    buf.setLineMarker(1, GitAdded)

    let sidebar = generateSidebarFromBuffer(buf, 0, 3)

    check sidebar.buffer[0][0].kind == Empty
    check sidebar.buffer[1][0].kind == GitAdded
    check sidebar.buffer[1][0].text == "+"
    check sidebar.buffer[2][0].kind == Empty

  test "Generate sidebar from buffer with multiple markers":
    let buf = newTextBuffer()
    discard buf.insertText(
      BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3\nLine 4\nLine 5"
    )
    buf.setLineMarker(0, GitAdded)
    buf.setLineMarker(2, GitChanged)
    buf.setLineMarker(4, SyntaxError)

    let sidebar = generateSidebarFromBuffer(buf, 0, 5)

    check sidebar.buffer[0][0].kind == GitAdded
    check sidebar.buffer[1][0].kind == Empty
    check sidebar.buffer[2][0].kind == GitChanged
    check sidebar.buffer[3][0].kind == Empty
    check sidebar.buffer[4][0].kind == SyntaxError

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
    check sidebar.buffer[0][0].kind == GitChanged
    # Screen line 1 = buffer line 3
    check sidebar.buffer[1][0].kind == Empty
    # Screen line 2 = buffer line 4
    check sidebar.buffer[2][0].kind == SyntaxError

  test "Generate sidebar with height larger than buffer":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2")
    buf.setLineMarker(0, GitAdded)

    let sidebar = generateSidebarFromBuffer(buf, 0, 5)

    check sidebar.buffer.len == 5
    check sidebar.buffer[0][0].kind == GitAdded
    check sidebar.buffer[1][0].kind == Empty
    # Lines beyond buffer remain empty
    check sidebar.buffer[2][0].kind == Empty
    check sidebar.buffer[3][0].kind == Empty
    check sidebar.buffer[4][0].kind == Empty

  test "Generate sidebar with custom width":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    buf.setLineMarker(0, GitAdded)

    let sidebar = generateSidebarFromBuffer(buf, 0, 1, 4)

    check sidebar.width == 4
    check sidebar.buffer[0].len == 4
    check sidebar.buffer[0][0].kind == GitAdded

suite "Sidebar - Style functions":
  test "gitAddedStyle has green foreground":
    let style = gitAddedStyle()
    check style.fg.kind == Indexed
    check style.fg.indexed == Color.Green

  test "gitChangedStyle has yellow foreground":
    let style = gitChangedStyle()
    check style.fg.kind == Indexed
    check style.fg.indexed == Color.Yellow

  test "gitDeletedStyle has red foreground":
    let style = gitDeletedStyle()
    check style.fg.kind == Indexed
    check style.fg.indexed == Color.Red

  test "syntaxErrorStyle has red foreground and bold modifier":
    let style = syntaxErrorStyle()
    check style.fg.kind == Indexed
    check style.fg.indexed == Color.Red
    check StyleModifier.Bold in style.modifiers

  test "syntaxWarningStyle has yellow foreground":
    let style = syntaxWarningStyle()
    check style.fg.kind == Indexed
    check style.fg.indexed == Color.Yellow

  test "emptyStyle has default foreground":
    let style = emptyStyle()
    check style.fg.kind == Default
