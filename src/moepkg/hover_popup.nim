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

## LSP Hover Popup display
##
## This module provides hover popup functionality for Normal mode.
## It displays hover information in a scrollable popup window
## when triggered by the K keybinding.

import std/[strutils, unicode]

import pkg/celina

import unicode_utils

type
  HoverPopupState* = enum
    hpsIdle ## No hover popup active
    hpsActive ## Hover popup is being displayed

  HoverPopupDisplay* = object ## Hover popup display state
    lines*: seq[string] ## Text lines to display (split by \n)
    scrollOffset*: int ## Current vertical scroll offset (first visible line)
    horizontalOffset*: int ## Current horizontal scroll offset (first visible column)
    maxVisibleLines*: int ## Maximum number of visible lines
    maxVisibleWidth*: int ## Maximum visible width (set during position calculation)
    cachedMaxLineWidth*: int ## Cached max line width (computed in show())

  HoverPopupManager* = ref object ## Manages hover popup state
    state*: HoverPopupState
    display*: HoverPopupDisplay
    triggerLine*: int ## Line where hover was triggered
    triggerCol*: int ## Column where hover was triggered
    isAutoHover*: bool ## true when triggered by auto-hover diagnostic

  HoverPopupPosition* = object
    x*, y*: int
    width*, height*: int

const
  DefaultMaxVisibleLines* = 10
  MinPopupWidth* = 20
  PopupPadding* = 2

proc newHoverPopupManager*(): HoverPopupManager =
  ## Create a new hover popup manager
  HoverPopupManager(
    state: hpsIdle,
    display: HoverPopupDisplay(
      lines: @[],
      scrollOffset: 0,
      horizontalOffset: 0,
      maxVisibleLines: DefaultMaxVisibleLines,
      maxVisibleWidth: 0,
      cachedMaxLineWidth: 0,
    ),
    triggerLine: 0,
    triggerCol: 0,
  )

proc isActive*(mgr: HoverPopupManager): bool =
  ## Check if hover popup is active
  mgr.state == hpsActive

proc show*(mgr: HoverPopupManager, hoverText: string, line, col: int) =
  ## Show hover popup with the given text
  if hoverText.len == 0:
    mgr.state = hpsIdle
    return

  mgr.display.lines = hoverText.splitLines()
  mgr.display.scrollOffset = 0
  mgr.display.horizontalOffset = 0
  mgr.triggerLine = line
  mgr.triggerCol = col
  mgr.isAutoHover = false
  mgr.state = hpsActive

  # Cache max line width
  mgr.display.cachedMaxLineWidth = 0
  for line in mgr.display.lines:
    mgr.display.cachedMaxLineWidth = max(mgr.display.cachedMaxLineWidth, line.runeLen)

proc hide*(mgr: HoverPopupManager) =
  ## Hide hover popup
  mgr.state = hpsIdle
  mgr.display.lines = @[]
  mgr.display.scrollOffset = 0
  mgr.display.horizontalOffset = 0
  mgr.display.cachedMaxLineWidth = 0

proc scrollDown*(mgr: HoverPopupManager) =
  ## Scroll popup content down (show more lines below)
  if mgr.state != hpsActive:
    return

  let maxOffset = max(0, mgr.display.lines.len - mgr.display.maxVisibleLines)
  if mgr.display.scrollOffset < maxOffset:
    inc mgr.display.scrollOffset

proc scrollUp*(mgr: HoverPopupManager) =
  ## Scroll popup content up (show more lines above)
  if mgr.state != hpsActive:
    return

  if mgr.display.scrollOffset > 0:
    dec mgr.display.scrollOffset

proc visibleLineCount*(mgr: HoverPopupManager): int =
  ## Get the number of visible lines in the popup
  min(mgr.display.lines.len, mgr.display.maxVisibleLines)

proc canScrollDown*(mgr: HoverPopupManager): bool =
  ## Check if popup can scroll down
  mgr.display.scrollOffset < max(0, mgr.display.lines.len - mgr.display.maxVisibleLines)

proc canScrollUp*(mgr: HoverPopupManager): bool =
  ## Check if popup can scroll up
  mgr.display.scrollOffset > 0

proc maxLineWidth*(mgr: HoverPopupManager): int =
  ## Get the maximum line width in the content (cached)
  mgr.display.cachedMaxLineWidth

proc scrollRight*(mgr: HoverPopupManager, amount: int = 4) =
  ## Scroll popup content right (show more content to the right)
  if mgr.state != hpsActive:
    return

  let maxOffset = max(0, mgr.maxLineWidth() - mgr.display.maxVisibleWidth)
  mgr.display.horizontalOffset = min(mgr.display.horizontalOffset + amount, maxOffset)

proc scrollLeft*(mgr: HoverPopupManager, amount: int = 4) =
  ## Scroll popup content left (show more content to the left)
  if mgr.state != hpsActive:
    return

  mgr.display.horizontalOffset = max(0, mgr.display.horizontalOffset - amount)

proc canScrollRight*(mgr: HoverPopupManager): bool =
  ## Check if popup can scroll right
  mgr.display.horizontalOffset < max(
    0, mgr.maxLineWidth() - mgr.display.maxVisibleWidth
  )

proc canScrollLeft*(mgr: HoverPopupManager): bool =
  ## Check if popup can scroll left
  mgr.display.horizontalOffset > 0

# Popup rendering

let
  hoverPopupNormalStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.White),
    bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 50, g: 50, b: 50)),
    modifiers: {},
  )
  hoverPopupBorderStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.BrightBlack),
    bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 50, g: 50, b: 50)),
    modifiers: {},
  )
  hoverPopupScrollIndicatorStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.Yellow),
    bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 50, g: 50, b: 50)),
    modifiers: {},
  )

proc calculateHoverPopupPosition*(
    cursorX, cursorY: int, termWidth, termHeight: int, mgr: HoverPopupManager
): HoverPopupPosition =
  ## Calculate popup position and size
  ## Hover popup appears above the cursor line if possible
  ## When scrolling is needed, maximize the popup size to fit available space

  # Calculate content width (max line length)
  var maxLineLen = 0
  for line in mgr.display.lines:
    maxLineLen = max(maxLineLen, line.runeLen)

  # Use screen width as max, leaving some margin
  let maxWidth = termWidth - 2 # -2 for some margin
  let contentWidth = min(max(maxLineLen + PopupPadding, MinPopupWidth), maxWidth)
  let popupWidth = contentWidth + 2 # +2 for border

  # Calculate available space above and below cursor
  let spaceAbove = cursorY # Lines available above cursor
  let spaceBelow = termHeight - cursorY - 1
    # Lines available below cursor (excluding cursor line)

  # Determine optimal visible lines: maximize if scrolling would be needed
  let totalLines = mgr.display.lines.len
  var optimalVisibleLines: int

  if totalLines <= DefaultMaxVisibleLines:
    # No scrolling needed, use actual line count
    optimalVisibleLines = totalLines
  else:
    # Scrolling needed - maximize popup size
    # Use whichever space (above or below) can show more lines
    let maxAbove = spaceAbove - 2 # -2 for border
    let maxBelow = spaceBelow - 2 # -2 for border
    let maxAvailable = max(maxAbove, maxBelow)
    # Use as much space as possible, but cap at total lines
    optimalVisibleLines = min(totalLines, max(maxAvailable, DefaultMaxVisibleLines))

  # Update manager's maxVisibleLines and maxVisibleWidth for rendering
  mgr.display.maxVisibleLines = optimalVisibleLines
  mgr.display.maxVisibleWidth = contentWidth

  let popupHeight = optimalVisibleLines + 2 # +2 for border

  var x = cursorX
  var y = cursorY - popupHeight # Above cursor

  # Adjust X if popup would extend past right edge
  if x + popupWidth > termWidth:
    x = max(0, termWidth - popupWidth)

  # If not enough space above, try below
  if y < 0:
    y = cursorY + 1

  # If still doesn't fit, just position at top
  if y + popupHeight > termHeight:
    y = max(0, termHeight - popupHeight)

  HoverPopupPosition(x: x, y: y, width: popupWidth, height: popupHeight)

proc renderHoverPopup*(
    termBuffer: var Buffer,
    mgr: HoverPopupManager,
    pos: HoverPopupPosition,
    showBorder: bool = true,
) =
  ## Render hover popup to terminal buffer
  if mgr.display.lines.len == 0:
    return

  # Calculate content area (inside border)
  let contentX =
    if showBorder:
      pos.x + 1
    else:
      pos.x
  let contentY =
    if showBorder:
      pos.y + 1
    else:
      pos.y
  let contentWidth =
    if showBorder:
      pos.width - 2
    else:
      pos.width
  let contentHeight = mgr.visibleLineCount()

  # Draw border if enabled
  if showBorder:
    # Top border
    if pos.y >= 0 and pos.y < termBuffer.area.height:
      if pos.x >= 0 and pos.x < termBuffer.area.width:
        termBuffer[pos.x, pos.y] = cell("┌", hoverPopupBorderStyle)
      for x in pos.x + 1 ..< min(pos.x + pos.width - 1, termBuffer.area.width):
        if x >= 0:
          termBuffer[x, pos.y] = cell("─", hoverPopupBorderStyle)
      if pos.x + pos.width - 1 >= 0 and pos.x + pos.width - 1 < termBuffer.area.width:
        # Show scroll up indicator if scrollable
        if mgr.canScrollUp():
          termBuffer[pos.x + pos.width - 1, pos.y] =
            cell("▲", hoverPopupScrollIndicatorStyle)
        else:
          termBuffer[pos.x + pos.width - 1, pos.y] = cell("┐", hoverPopupBorderStyle)

    # Content lines
    for i in 0 ..< contentHeight:
      let lineY = contentY + i
      if lineY < 0 or lineY >= termBuffer.area.height:
        continue

      let lineIdx = mgr.display.scrollOffset + i
      let lineText =
        if lineIdx < mgr.display.lines.len:
          mgr.display.lines[lineIdx]
        else:
          ""

      # Left border - show horizontal scroll left indicator if scrollable
      if pos.x >= 0 and pos.x < termBuffer.area.width:
        if i == contentHeight div 2 and mgr.canScrollLeft():
          termBuffer[pos.x, lineY] = cell("◀", hoverPopupScrollIndicatorStyle)
        else:
          termBuffer[pos.x, lineY] = cell("│", hoverPopupBorderStyle)

      # Content - with horizontal scroll offset
      var x = contentX
      var charIdx = 0
      for r in lineText.runes:
        # Skip characters before horizontal offset
        if charIdx < mgr.display.horizontalOffset:
          inc charIdx
          continue

        if x >= contentX + contentWidth or x >= termBuffer.area.width:
          break
        if x >= 0:
          x += setRuneCell(termBuffer, x, lineY, r, hoverPopupNormalStyle)
        else:
          x += runeWidth(r)
        inc charIdx

      # Fill remaining space with background
      while x < contentX + contentWidth and x < termBuffer.area.width:
        if x >= 0:
          termBuffer[x, lineY] = cell(" ", hoverPopupNormalStyle)
        inc x

      # Right border - show horizontal scroll right indicator if scrollable
      if pos.x + pos.width - 1 >= 0 and pos.x + pos.width - 1 < termBuffer.area.width:
        if i == contentHeight div 2 and mgr.canScrollRight():
          termBuffer[pos.x + pos.width - 1, lineY] =
            cell("▶", hoverPopupScrollIndicatorStyle)
        else:
          termBuffer[pos.x + pos.width - 1, lineY] = cell("│", hoverPopupBorderStyle)

    # Bottom border
    let bottomY = contentY + contentHeight
    if bottomY >= 0 and bottomY < termBuffer.area.height:
      if pos.x >= 0 and pos.x < termBuffer.area.width:
        termBuffer[pos.x, bottomY] = cell("└", hoverPopupBorderStyle)
      for x in pos.x + 1 ..< min(pos.x + pos.width - 1, termBuffer.area.width):
        if x >= 0:
          termBuffer[x, bottomY] = cell("─", hoverPopupBorderStyle)
      if pos.x + pos.width - 1 >= 0 and pos.x + pos.width - 1 < termBuffer.area.width:
        # Show scroll down indicator if scrollable
        if mgr.canScrollDown():
          termBuffer[pos.x + pos.width - 1, bottomY] =
            cell("▼", hoverPopupScrollIndicatorStyle)
        else:
          termBuffer[pos.x + pos.width - 1, bottomY] =
            cell("┘", hoverPopupBorderStyle)
