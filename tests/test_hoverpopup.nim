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

## Tests for hover popup functionality

import std/unittest

import pkg/celina

import ../src/moepkg/hoverpopup {.all.}

suite "HoverPopup - newHoverPopupManager":
  test "Creates manager with idle state":
    let mgr = newHoverPopupManager()

    check mgr.state == hpsIdle
    check mgr.display.lines.len == 0
    check mgr.display.scrollOffset == 0
    check mgr.display.horizontalOffset == 0
    check mgr.display.maxVisibleLines == DefaultMaxVisibleLines
    check mgr.display.maxVisibleWidth == 0
    check mgr.display.cachedMaxLineWidth == 0
    check mgr.triggerLine == 0
    check mgr.triggerCol == 0

suite "HoverPopup - isActive":
  test "Returns false when idle":
    let mgr = newHoverPopupManager()

    check mgr.isActive == false

  test "Returns true when active":
    let mgr = newHoverPopupManager()
    mgr.show("test", 0, 0)

    check mgr.isActive == true

suite "HoverPopup - show":
  test "Shows popup with single line text":
    let mgr = newHoverPopupManager()

    mgr.show("Hello, world!", 5, 10)

    check mgr.state == hpsActive
    check mgr.display.lines.len == 1
    check mgr.display.lines[0] == "Hello, world!"
    check mgr.display.scrollOffset == 0
    check mgr.display.horizontalOffset == 0
    check mgr.triggerLine == 5
    check mgr.triggerCol == 10

  test "Shows popup with multiline text":
    let mgr = newHoverPopupManager()

    mgr.show("Line 1\nLine 2\nLine 3", 0, 0)

    check mgr.state == hpsActive
    check mgr.display.lines.len == 3
    check mgr.display.lines[0] == "Line 1"
    check mgr.display.lines[1] == "Line 2"
    check mgr.display.lines[2] == "Line 3"

  test "Caches max line width":
    let mgr = newHoverPopupManager()

    mgr.show("Short\nLonger line here\nMed", 0, 0)

    check mgr.display.cachedMaxLineWidth == 16 # "Longer line here".len

  test "Does not activate with empty text":
    let mgr = newHoverPopupManager()

    mgr.show("", 5, 10)

    check mgr.state == hpsIdle
    check mgr.display.lines.len == 0

  test "Resets scroll offsets on new show":
    let mgr = newHoverPopupManager()
    mgr.show(
      "Line1\nLine2\nLine3\nLine4\nLine5\nLine6\nLine7\nLine8\nLine9\nLine10\nLine11",
      0, 0,
    )
    mgr.display.maxVisibleLines = 5
    mgr.scrollDown()
    mgr.scrollDown()
    mgr.display.horizontalOffset = 5

    check mgr.display.scrollOffset == 2
    check mgr.display.horizontalOffset == 5

    # Show new content
    mgr.show("New text", 1, 1)

    check mgr.display.scrollOffset == 0
    check mgr.display.horizontalOffset == 0

suite "HoverPopup - hide":
  test "Hides active popup":
    let mgr = newHoverPopupManager()
    mgr.show("Test content", 0, 0)

    check mgr.state == hpsActive

    mgr.hide()

    check mgr.state == hpsIdle
    check mgr.display.lines.len == 0
    check mgr.display.scrollOffset == 0
    check mgr.display.horizontalOffset == 0
    check mgr.display.cachedMaxLineWidth == 0

  test "Hides idle popup (no-op)":
    let mgr = newHoverPopupManager()

    mgr.hide()

    check mgr.state == hpsIdle

suite "HoverPopup - scrollDown":
  test "Scrolls down when more content below":
    let mgr = newHoverPopupManager()
    mgr.show(
      "Line1\nLine2\nLine3\nLine4\nLine5\nLine6\nLine7\nLine8\nLine9\nLine10\nLine11\nLine12",
      0, 0,
    )
    mgr.display.maxVisibleLines = 5

    check mgr.display.scrollOffset == 0

    mgr.scrollDown()

    check mgr.display.scrollOffset == 1

  test "Does not scroll past last line":
    let mgr = newHoverPopupManager()
    mgr.show("Line1\nLine2\nLine3\nLine4\nLine5\nLine6", 0, 0)
    mgr.display.maxVisibleLines = 5

    # Max offset should be 6 - 5 = 1
    mgr.scrollDown()
    mgr.scrollDown()
    mgr.scrollDown()

    check mgr.display.scrollOffset == 1

  test "Does nothing when not active":
    let mgr = newHoverPopupManager()

    mgr.scrollDown()

    check mgr.display.scrollOffset == 0

  test "Does nothing when all content visible":
    let mgr = newHoverPopupManager()
    mgr.show("Line1\nLine2", 0, 0)
    mgr.display.maxVisibleLines = 10

    mgr.scrollDown()

    check mgr.display.scrollOffset == 0

suite "HoverPopup - scrollUp":
  test "Scrolls up when content above":
    let mgr = newHoverPopupManager()
    mgr.show(
      "Line1\nLine2\nLine3\nLine4\nLine5\nLine6\nLine7\nLine8\nLine9\nLine10\nLine11\nLine12",
      0, 0,
    )
    mgr.display.maxVisibleLines = 5
    mgr.display.scrollOffset = 3

    mgr.scrollUp()

    check mgr.display.scrollOffset == 2

  test "Does not scroll above first line":
    let mgr = newHoverPopupManager()
    mgr.show("Line1\nLine2\nLine3", 0, 0)
    mgr.display.scrollOffset = 0

    mgr.scrollUp()

    check mgr.display.scrollOffset == 0

  test "Does nothing when not active":
    let mgr = newHoverPopupManager()
    mgr.display.scrollOffset = 5

    mgr.scrollUp()

    check mgr.display.scrollOffset == 5

suite "HoverPopup - visibleLineCount":
  test "Returns line count when less than maxVisibleLines":
    let mgr = newHoverPopupManager()
    mgr.show("Line1\nLine2\nLine3", 0, 0)
    mgr.display.maxVisibleLines = 10

    check mgr.visibleLineCount == 3

  test "Returns maxVisibleLines when more lines exist":
    let mgr = newHoverPopupManager()
    mgr.show(
      "Line1\nLine2\nLine3\nLine4\nLine5\nLine6\nLine7\nLine8\nLine9\nLine10\nLine11\nLine12",
      0, 0,
    )
    mgr.display.maxVisibleLines = 5

    check mgr.visibleLineCount == 5

suite "HoverPopup - canScrollDown":
  test "Returns true when more content below":
    let mgr = newHoverPopupManager()
    mgr.show(
      "Line1\nLine2\nLine3\nLine4\nLine5\nLine6\nLine7\nLine8\nLine9\nLine10\nLine11\nLine12",
      0, 0,
    )
    mgr.display.maxVisibleLines = 5
    mgr.display.scrollOffset = 0

    check mgr.canScrollDown == true

  test "Returns false when at bottom":
    let mgr = newHoverPopupManager()
    mgr.show("Line1\nLine2\nLine3\nLine4\nLine5\nLine6", 0, 0)
    mgr.display.maxVisibleLines = 5
    mgr.display.scrollOffset = 1 # 6 - 5 = 1

    check mgr.canScrollDown == false

  test "Returns false when all content visible":
    let mgr = newHoverPopupManager()
    mgr.show("Line1\nLine2", 0, 0)
    mgr.display.maxVisibleLines = 10

    check mgr.canScrollDown == false

suite "HoverPopup - canScrollUp":
  test "Returns true when scrolled down":
    let mgr = newHoverPopupManager()
    mgr.show("Line1\nLine2\nLine3", 0, 0)
    mgr.display.scrollOffset = 1

    check mgr.canScrollUp == true

  test "Returns false when at top":
    let mgr = newHoverPopupManager()
    mgr.show("Line1\nLine2\nLine3", 0, 0)
    mgr.display.scrollOffset = 0

    check mgr.canScrollUp == false

suite "HoverPopup - maxLineWidth":
  test "Returns cached max line width":
    let mgr = newHoverPopupManager()
    mgr.show("Short\nThis is a longer line\nMed", 0, 0)

    check mgr.maxLineWidth == 21 # "This is a longer line".len

  test "Returns 0 when no content":
    let mgr = newHoverPopupManager()

    check mgr.maxLineWidth == 0

suite "HoverPopup - scrollRight":
  test "Scrolls right when content extends beyond visible width":
    let mgr = newHoverPopupManager()
    mgr.show("This is a very long line that extends beyond the popup width", 0, 0)
    mgr.display.maxVisibleWidth = 20
    mgr.display.cachedMaxLineWidth = 60

    check mgr.display.horizontalOffset == 0

    mgr.scrollRight()

    check mgr.display.horizontalOffset == 4 # Default amount

  test "Does not scroll past content end":
    let mgr = newHoverPopupManager()
    mgr.show("Short line", 0, 0)
    mgr.display.maxVisibleWidth = 20

    mgr.scrollRight()
    mgr.scrollRight()
    mgr.scrollRight()

    # Should not go negative (maxLineWidth - maxVisibleWidth = 10 - 20 = -10 -> max(0, -10) = 0)
    check mgr.display.horizontalOffset == 0

  test "Does nothing when not active":
    let mgr = newHoverPopupManager()

    mgr.scrollRight()

    check mgr.display.horizontalOffset == 0

  test "Scrolls by custom amount":
    let mgr = newHoverPopupManager()
    mgr.show("This is a very long line that extends beyond the popup width", 0, 0)
    mgr.display.maxVisibleWidth = 20
    mgr.display.cachedMaxLineWidth = 60

    mgr.scrollRight(10)

    check mgr.display.horizontalOffset == 10

suite "HoverPopup - scrollLeft":
  test "Scrolls left when scrolled right":
    let mgr = newHoverPopupManager()
    mgr.show("Test", 0, 0)
    mgr.display.horizontalOffset = 10

    mgr.scrollLeft()

    check mgr.display.horizontalOffset == 6 # 10 - 4

  test "Does not scroll past left edge":
    let mgr = newHoverPopupManager()
    mgr.show("Test", 0, 0)
    mgr.display.horizontalOffset = 2

    mgr.scrollLeft()

    check mgr.display.horizontalOffset == 0

  test "Does nothing when not active":
    let mgr = newHoverPopupManager()
    mgr.display.horizontalOffset = 5

    mgr.scrollLeft()

    check mgr.display.horizontalOffset == 5

  test "Scrolls by custom amount":
    let mgr = newHoverPopupManager()
    mgr.show("Test", 0, 0)
    mgr.display.horizontalOffset = 20

    mgr.scrollLeft(8)

    check mgr.display.horizontalOffset == 12

suite "HoverPopup - canScrollRight":
  test "Returns true when content extends beyond visible width":
    let mgr = newHoverPopupManager()
    mgr.show("This is a long line", 0, 0)
    mgr.display.maxVisibleWidth = 10
    mgr.display.horizontalOffset = 0

    check mgr.canScrollRight == true

  test "Returns false when at right edge":
    let mgr = newHoverPopupManager()
    mgr.show("Short", 0, 0)
    mgr.display.maxVisibleWidth = 10
    mgr.display.horizontalOffset = 0

    check mgr.canScrollRight == false

  test "Returns false when scrolled to end":
    let mgr = newHoverPopupManager()
    mgr.show("This is a long line", 0, 0) # 19 chars
    mgr.display.maxVisibleWidth = 10
    mgr.display.horizontalOffset = 9 # maxLineWidth(19) - maxVisibleWidth(10) = 9

    check mgr.canScrollRight == false

suite "HoverPopup - canScrollLeft":
  test "Returns true when scrolled right":
    let mgr = newHoverPopupManager()
    mgr.show("Test", 0, 0)
    mgr.display.horizontalOffset = 5

    check mgr.canScrollLeft == true

  test "Returns false when at left edge":
    let mgr = newHoverPopupManager()
    mgr.show("Test", 0, 0)
    mgr.display.horizontalOffset = 0

    check mgr.canScrollLeft == false

suite "HoverPopup - calculateHoverPopupPosition":
  test "Positions popup above cursor":
    let mgr = newHoverPopupManager()
    mgr.show("Line 1\nLine 2\nLine 3", 0, 0)

    let pos = calculateHoverPopupPosition(
      cursorX = 10, cursorY = 20, termWidth = 80, termHeight = 24, mgr = mgr
    )

    # Popup should be above cursor (y < cursorY)
    check pos.y < 20
    check pos.x == 10
    check pos.height == 5 # 3 lines + 2 for border

  test "Positions popup below cursor when no space above":
    let mgr = newHoverPopupManager()
    mgr.show("Line 1\nLine 2\nLine 3", 0, 0)

    let pos = calculateHoverPopupPosition(
      cursorX = 10,
      cursorY = 2, # Not enough space above (need 5 lines for popup)
      termWidth = 80,
      termHeight = 24,
      mgr = mgr,
    )

    # Popup should be below cursor
    check pos.y == 3 # cursorY + 1

  test "Adjusts X when popup would extend past right edge":
    let mgr = newHoverPopupManager()
    mgr.show("This is a longer line for testing", 0, 0)

    let pos = calculateHoverPopupPosition(
      cursorX = 70, cursorY = 12, termWidth = 80, termHeight = 24, mgr = mgr
    )

    # Popup should be shifted left
    check pos.x + pos.width <= 80

  test "Uses minimum width when content is short":
    let mgr = newHoverPopupManager()
    mgr.show("Hi", 0, 0)

    let pos = calculateHoverPopupPosition(
      cursorX = 10, cursorY = 12, termWidth = 80, termHeight = 24, mgr = mgr
    )

    # Width should be at least MinPopupWidth + 2 (for border)
    check pos.width >= MinPopupWidth + 2

  test "Updates maxVisibleLines in manager":
    let mgr = newHoverPopupManager()
    mgr.show("L1\nL2\nL3\nL4\nL5", 0, 0)

    discard calculateHoverPopupPosition(
      cursorX = 10, cursorY = 12, termWidth = 80, termHeight = 24, mgr = mgr
    )

    check mgr.display.maxVisibleLines == 5

  test "Updates maxVisibleWidth in manager":
    let mgr = newHoverPopupManager()
    mgr.show("Test content", 0, 0)

    discard calculateHoverPopupPosition(
      cursorX = 10, cursorY = 12, termWidth = 80, termHeight = 24, mgr = mgr
    )

    check mgr.display.maxVisibleWidth > 0

  test "Maximizes popup height for scrollable content":
    let mgr = newHoverPopupManager()
    # Create content that needs scrolling
    var lines: string
    for i in 1 .. 30:
      lines.add("Line " & $i & "\n")
    mgr.show(lines, 0, 0)

    discard calculateHoverPopupPosition(
      cursorX = 10, cursorY = 12, termWidth = 80, termHeight = 24, mgr = mgr
    )

    # Should use maximum available space
    check mgr.display.maxVisibleLines >= DefaultMaxVisibleLines

suite "HoverPopup - renderHoverPopup":
  test "Renders popup content to buffer":
    let mgr = newHoverPopupManager()
    mgr.show("Hello", 0, 0)

    let pos = HoverPopupPosition(x: 5, y: 5, width: 10, height: 3)
    mgr.display.maxVisibleLines = 1
    mgr.display.maxVisibleWidth = 20 # Wide enough so no horizontal scroll indicator

    var termBuffer = newBuffer(80, 24)

    renderHoverPopup(termBuffer, mgr, pos, showBorder = true)

    # Check top border
    check termBuffer[5, 5].symbol == "┌"
    check termBuffer[14, 5].symbol == "┐"
    # Check content area exists
    check termBuffer[5, 6].symbol == "│"
    check termBuffer[14, 6].symbol == "│"
    # Check bottom border
    check termBuffer[5, 7].symbol == "└"
    check termBuffer[14, 7].symbol == "┘"

  test "Shows scroll up indicator when scrolled down":
    let mgr = newHoverPopupManager()
    mgr.show("Line1\nLine2\nLine3\nLine4\nLine5", 0, 0)
    mgr.display.maxVisibleLines = 2
    mgr.display.scrollOffset = 2 # Scrolled down

    let pos = HoverPopupPosition(x: 0, y: 0, width: 15, height: 4)

    var termBuffer = newBuffer(80, 24)

    renderHoverPopup(termBuffer, mgr, pos, showBorder = true)

    # Top-right corner should show scroll up indicator
    check termBuffer[14, 0].symbol == "▲"

  test "Shows scroll down indicator when more content below":
    let mgr = newHoverPopupManager()
    mgr.show("Line1\nLine2\nLine3\nLine4\nLine5", 0, 0)
    mgr.display.maxVisibleLines = 2
    mgr.display.scrollOffset = 0 # At top

    let pos = HoverPopupPosition(x: 0, y: 0, width: 15, height: 4)

    var termBuffer = newBuffer(80, 24)

    renderHoverPopup(termBuffer, mgr, pos, showBorder = true)

    # Bottom-right corner should show scroll down indicator
    check termBuffer[14, 3].symbol == "▼"

  test "Does nothing with empty lines":
    let mgr = newHoverPopupManager()
    mgr.display.lines = @[]

    let pos = HoverPopupPosition(x: 0, y: 0, width: 10, height: 5)

    var termBuffer = newBuffer(80, 24)

    # Should not crash
    renderHoverPopup(termBuffer, mgr, pos, showBorder = true)

suite "HoverPopup - styles":
  test "hoverPopupNormalStyle has white foreground and dark background":
    check hoverPopupNormalStyle.fg.kind == Indexed
    check hoverPopupNormalStyle.fg.indexed == Color.White
    check hoverPopupNormalStyle.bg.kind == Rgb

  test "hoverPopupBorderStyle has bright black foreground":
    check hoverPopupBorderStyle.fg.kind == Indexed
    check hoverPopupBorderStyle.fg.indexed == Color.BrightBlack

  test "hoverPopupScrollIndicatorStyle has yellow foreground":
    check hoverPopupScrollIndicatorStyle.fg.kind == Indexed
    check hoverPopupScrollIndicatorStyle.fg.indexed == Color.Yellow

suite "HoverPopup - constants":
  test "DefaultMaxVisibleLines is 10":
    check DefaultMaxVisibleLines == 10

  test "MinPopupWidth is 20":
    check MinPopupWidth == 20

  test "PopupPadding is 2":
    check PopupPadding == 2

suite "HoverPopup - Unicode support":
  test "Correctly calculates max width with Unicode characters":
    let mgr = newHoverPopupManager()
    mgr.show("こんにちは", 0, 0) # 5 Unicode characters

    check mgr.maxLineWidth == 5

  test "Correctly calculates max width with mixed content":
    let mgr = newHoverPopupManager()
    mgr.show("Hello 世界!", 0, 0) # 6 ASCII + 2 CJK + 1 ASCII = 9 runes

    check mgr.maxLineWidth == 9
