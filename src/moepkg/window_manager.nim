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

## Window management for split window functionality

import std/[options, algorithm]

import pkg/results

import logger, modes, render_utils, types
import buffer/[core, file_io]

import types/window_manager_types
export window_manager_types

const
  WindowSeparatorWidth* = 1 ## Width of separator between vertically split windows
  WindowSeparatorHeight* = 1 ## Height of separator between horizontally split windows
  StatusLineHeight* = 1 ## Height of a status line

proc newEditorWindowManager*(): EditorWindowManager =
  ## Create a new window manager
  EditorWindowManager(windows: @[], activeWindowIndex: 0)

proc activeBuffer*(wm: EditorWindowManager): Option[TextBuffer] =
  ## Get the buffer of the active window
  if wm.windows.len > 0 and wm.activeWindowIndex < wm.windows.len:
    return some(wm.windows[wm.activeWindowIndex].buffer)

proc deactivateAllWindows*(wm: EditorWindowManager) =
  ## Deactivate all windows
  for window in wm.windows.mitems:
    window.active = false

proc activateWindow*(wm: EditorWindowManager, index: int) =
  ## Activate a specific window by index and update activeWindowIndex
  if index >= 0 and index < wm.windows.len:
    wm.deactivateAllWindows()
    wm.windows[index].active = true
    wm.activeWindowIndex = index

proc switchToNextWindow*(wm: EditorWindowManager) =
  ## Switch to the next window (Ctrl-w, k)
  if wm.windows.len <= 1:
    return

  let nextIndex = (wm.activeWindowIndex + 1) mod wm.windows.len
  wm.activateWindow(nextIndex)

proc switchToPrevWindow*(wm: EditorWindowManager) =
  ## Switch to the previous window (Ctrl-w, j)
  if wm.windows.len <= 1:
    return

  let prevIndex = (wm.activeWindowIndex - 1 + wm.windows.len) mod wm.windows.len
  wm.activateWindow(prevIndex)

proc groupWindowsByY*(wm: EditorWindowManager): seq[seq[int]] =
  ## Group windows by their Y coordinate (horizontal groups)
  var groups: seq[seq[int]] = @[]
  for i in 0 ..< wm.windows.len:
    var foundGroup = false
    for group in groups.mitems:
      if group.len > 0 and wm.windows[group[0]].viewport.y == wm.windows[i].viewport.y:
        group.add(i)
        foundGroup = true
        break
    if not foundGroup:
      groups.add(@[i])
  return groups

proc groupAdjacentWindowsHorizontally*(wm: EditorWindowManager): seq[seq[int]] =
  ## Group windows that are horizontally adjacent (same y and height, side by side)
  var groups: seq[seq[int]] = @[]
  for i in 0 ..< wm.windows.len:
    var foundGroup = false
    for group in groups.mitems:
      if group.len > 0:
        let
          groupFirst = wm.windows[group[0]]
          currentWin = wm.windows[i]
        if groupFirst.viewport.y == currentWin.viewport.y and
            groupFirst.viewport.height == currentWin.viewport.height:
          let
            lastIdx = group[^1]
            lastWin = wm.windows[lastIdx]
            lastEndX = lastWin.viewport.x + lastWin.viewport.width
          if abs(currentWin.viewport.x - lastEndX) <= 1:
            group.add(i)
            foundGroup = true
            break
    if not foundGroup:
      groups.add(@[i])
  return groups

proc groupAdjacentWindowsVertically*(wm: EditorWindowManager): seq[seq[int]] =
  ## Group windows that are vertically adjacent (same x and width, stacked)
  var groups: seq[seq[int]] = @[]
  for i in 0 ..< wm.windows.len:
    var foundGroup = false
    for group in groups.mitems:
      if group.len > 0:
        let
          groupFirst = wm.windows[group[0]]
          currentWin = wm.windows[i]
        if groupFirst.viewport.x == currentWin.viewport.x and
            groupFirst.viewport.width == currentWin.viewport.width:
          let
            lastIdx = group[^1]
            lastWin = wm.windows[lastIdx]
            lastEndY = lastWin.viewport.y + lastWin.viewport.height
          if abs(currentWin.viewport.y - lastEndY) <= 1:
            group.add(i)
            foundGroup = true
            break
    if not foundGroup:
      groups.add(@[i])
  return groups

proc groupWindowsByXAndWidth*(wm: EditorWindowManager): seq[seq[int]] =
  ## Group windows by their X coordinate and width (vertical groups)
  var groups: seq[seq[int]] = @[]
  for i in 0 ..< wm.windows.len:
    var foundGroup = false
    for group in groups.mitems:
      if group.len > 0 and wm.windows[group[0]].viewport.x == wm.windows[i].viewport.x and
          wm.windows[group[0]].viewport.width == wm.windows[i].viewport.width:
        group.add(i)
        foundGroup = true
        break
    if not foundGroup:
      groups.add(@[i])
  return groups

proc equalizeWidthsInGroup*(
    wm: EditorWindowManager, group: seq[int], totalWidth: int, startX: int
) =
  ## Equalize widths of windows in a horizontal group.
  ## Windows with fixedWidth are allocated their fixed size first;
  ## remaining space is distributed equally among flexible windows.
  if group.len <= 1:
    return

  var sortedGroup = group
  sortedGroup.sort(
    proc(a, b: int): int =
      cmp(wm.windows[a].viewport.x, wm.windows[b].viewport.x)
  )

  let numSeparators = sortedGroup.len - 1

  # Calculate fixed width consumption
  var fixedWidthTotal = 0
  var flexCount = 0
  for idx in sortedGroup:
    if wm.windows[idx].fixedWidth.isSome:
      fixedWidthTotal += wm.windows[idx].fixedWidth.get
    else:
      flexCount += 1

  let
    availableWidth = totalWidth - numSeparators * WindowSeparatorWidth
    flexWidth =
      if flexCount > 0:
        max(1, (availableWidth - fixedWidthTotal) div flexCount)
      else:
        0

  var currentX = startX
  for i, idx in sortedGroup:
    wm.windows[idx].viewport.x = currentX
    if i == sortedGroup.len - 1:
      # Last window gets remaining width; cap fixedWidth at the remaining
      # space and clamp positive so overflow cannot go negative (warn-log).
      let remaining = (startX + totalWidth) - currentX
      if remaining < 1:
        logWarn(
          "window_manager",
          "last window does not fit in the group: totalWidth=" & $totalWidth & " startX=" &
            $startX & " currentX=" & $currentX,
        )
      let width =
        if wm.windows[idx].fixedWidth.isSome:
          # Cap fixedWidth at the remaining space to stay inside the group.
          max(1, min(wm.windows[idx].fixedWidth.get, remaining))
        else:
          max(1, remaining)
      wm.windows[idx].viewport.width = width
      # Pull x back so the window ends at the group's right end.
      wm.windows[idx].viewport.x = min(currentX, startX + totalWidth - width)
    else:
      let w =
        if wm.windows[idx].fixedWidth.isSome:
          wm.windows[idx].fixedWidth.get
        else:
          flexWidth
      wm.windows[idx].viewport.width = w
      currentX += w + WindowSeparatorWidth

proc equalizeWidthsForResize*(wm: EditorWindowManager, group: seq[int], newWidth: int) =
  ## Equalize widths during window resize (handles single window case).
  ## Windows with fixedWidth keep their size; remaining space is distributed.
  if group.len == 1:
    let idx = group[0]
    if wm.windows[idx].fixedWidth.isSome:
      wm.windows[idx].viewport.width = wm.windows[idx].fixedWidth.get
    else:
      # A single-element horizontal group can still have vertically-overlapping
      # right neighbors (grouper requires matching y AND height); stop at them.
      let
        win = wm.windows[idx]
        minX = win.viewport.x
        winTop = win.viewport.y
        # A zero-height window bounds as one row so it cannot swallow the width.
        winBottom = win.viewport.y + max(1, win.viewport.height)
      var
        rightBoundary = newWidth
        # A scaled x inside a left neighbor (e.g. wide fixed-width sidebar)
        # would overlap it; shift right of it.
        leftLimit = minX
      for i in 0 ..< wm.windows.len:
        if i == idx:
          continue
        let
          other = wm.windows[i]
          otherTop = other.viewport.y
          # Zero-height/boundary-touching neighbors still bound the width.
          otherBottom = other.viewport.y + max(1, other.viewport.height)
        let boundsWidth =
          (otherTop < winBottom and winTop < otherBottom) or (
            winTop <= otherBottom and otherTop < winBottom and
            win.viewport.x < other.viewport.x + other.viewport.width and
            other.viewport.x < win.viewport.x + win.viewport.width
          )
        if boundsWidth:
          if other.viewport.x > minX and other.viewport.x < rightBoundary:
            rightBoundary = other.viewport.x
          elif other.viewport.x <= minX and
              minX < other.viewport.x + other.viewport.width and
              other.viewport.x + other.viewport.width > leftLimit:
            # An x coinciding with the left neighbor is still an overlap.
            leftLimit = other.viewport.x + other.viewport.width
      if leftLimit > minX:
        # A squeezed gap would push the window past the right boundary; pull it back.
        let width = max(
          1, rightBoundary - WindowSeparatorWidth - (leftLimit + WindowSeparatorWidth)
        )
        wm.windows[idx].viewport.x =
          min(leftLimit + WindowSeparatorWidth, rightBoundary - width)
        wm.windows[idx].viewport.width = width
      else:
        let width =
          if rightBoundary < newWidth:
            rightBoundary - WindowSeparatorWidth - minX
          else:
            newWidth - minX
        wm.windows[idx].viewport.width = max(1, width)
    return

  var sortedGroup = group
  sortedGroup.sort(
    proc(a, b: int): int =
      cmp(wm.windows[a].viewport.x, wm.windows[b].viewport.x)
  )

  let
    firstWindow = wm.windows[sortedGroup[0]]
    firstTop = firstWindow.viewport.y
    # A zero-height window bounds as one row so the cover test still works.
    firstBottom = firstWindow.viewport.y + max(1, firstWindow.viewport.height)
  # A scaled group x may land inside a left neighbor (e.g. a fixed-width
  # sidebar wider than the new screen); shift right of it, and stop the
  # extension at a differently-sized right neighbor (T-junction) so the
  # last window is not drawn over it.
  var
    minX = firstWindow.viewport.x
    rightBoundary = newWidth
  for i in 0 ..< wm.windows.len:
    if sortedGroup.contains(i):
      continue
    let other = wm.windows[i]
    # Neighbors touching the group's top still bound its extension (T-junction).
    let boundsGroup =
      (
        firstTop < other.viewport.y + other.viewport.height and
        other.viewport.y < firstBottom
      ) or (
        firstTop <= other.viewport.y + max(1, other.viewport.height) and
        other.viewport.y < firstBottom and
        firstWindow.viewport.x < other.viewport.x + other.viewport.width and
        other.viewport.x < firstWindow.viewport.x + firstWindow.viewport.width
      )
    if boundsGroup:
      if other.viewport.x < minX and minX < other.viewport.x + other.viewport.width:
        minX = max(minX, other.viewport.x + other.viewport.width + WindowSeparatorWidth)
      elif other.viewport.x > minX and other.viewport.x < rightBoundary:
        rightBoundary = other.viewport.x
  let
    availableWidth =
      if rightBoundary < newWidth:
        rightBoundary - WindowSeparatorWidth - minX
      else:
        newWidth - minX
    numSeparators = sortedGroup.len - 1

  # Calculate fixed width consumption
  var fixedWidthTotal = 0
  var flexCount = 0
  for idx in sortedGroup:
    if wm.windows[idx].fixedWidth.isSome:
      fixedWidthTotal += wm.windows[idx].fixedWidth.get
    else:
      flexCount += 1

  let
    totalFlexWidth =
      availableWidth - numSeparators * WindowSeparatorWidth - fixedWidthTotal
    windowWidth =
      if flexCount > 0:
        max(1, totalFlexWidth div flexCount)
      else:
        0

  var currentX = minX
  for i, idx in sortedGroup:
    if i == sortedGroup.len - 1:
      # Last window: clamp positive so a fixed-width overflow cannot go
      # negative (warn-log).
      let remaining = (minX + availableWidth) - currentX
      if remaining < 1:
        logWarn(
          "window_manager",
          "last window does not fit in the group: availableWidth=" & $availableWidth &
            " minX=" & $minX & " currentX=" & $currentX,
        )
      let width =
        if wm.windows[idx].fixedWidth.isSome:
          max(wm.windows[idx].fixedWidth.get, remaining)
        else:
          max(1, remaining)
      wm.windows[idx].viewport.width = width
      # An overflow past the right boundary would cover a group member;
      # slide the window left to the rightmost free column.
      if currentX + width > rightBoundary:
        var newX = rightBoundary - width
        var slid = false
        while newX > minX:
          var blocked = false
          for k in 0 ..< sortedGroup.len - 1:
            let member = wm.windows[sortedGroup[k]]
            if newX < member.viewport.x + member.viewport.width and
                member.viewport.x < newX + width:
              blocked = true
              break
          if not blocked:
            slid = true
            break
          dec newX
        if slid:
          wm.windows[idx].viewport.x = newX
        else:
          # No free position: shrink the window into the gap after the
          # previous member.
          let prevRight =
            wm.windows[sortedGroup[^2]].viewport.x +
            wm.windows[sortedGroup[^2]].viewport.width
          let gapX =
            min(prevRight + WindowSeparatorWidth, rightBoundary - WindowSeparatorWidth)
          wm.windows[idx].viewport.x = gapX
          wm.windows[idx].viewport.width =
            max(1, rightBoundary - WindowSeparatorWidth - gapX)
      else:
        wm.windows[idx].viewport.x = currentX
    else:
      # Cap fixedWidth members at the space left for the remaining windows.
      let space = (minX + availableWidth) - currentX
      let maxAllowed = space - 2 * (sortedGroup.len - 1 - i)
      let w =
        if wm.windows[idx].fixedWidth.isSome:
          max(1, min(wm.windows[idx].fixedWidth.get, maxAllowed))
        else:
          windowWidth
      wm.windows[idx].viewport.x = currentX
      wm.windows[idx].viewport.width = w
      currentX += w + WindowSeparatorWidth

proc equalizeAllHorizontalGroups*(wm: EditorWindowManager) =
  ## Equalize widths across all horizontal window groups, respecting fixedWidth.
  let windowGroups = wm.groupWindowsByY()
  for group in windowGroups:
    if group.len > 1:
      var sortedGroup = group
      sortedGroup.sort(
        proc(a, b: int): int =
          cmp(wm.windows[a].viewport.x, wm.windows[b].viewport.x)
      )
      let
        firstWindow = wm.windows[sortedGroup[0]]
        lastWindow = wm.windows[sortedGroup[^1]]
        totalWidth =
          (lastWindow.viewport.x + lastWindow.viewport.width) - firstWindow.viewport.x
        startX = firstWindow.viewport.x
      wm.equalizeWidthsInGroup(sortedGroup, totalWidth, startX)

proc equalizeHeightsInGroup*(
    wm: EditorWindowManager,
    group: seq[int],
    totalHeight: int,
    startY: int,
    multiStatusLine: bool,
) =
  ## Equalize heights of windows in a vertical group
  if group.len <= 1:
    return

  var sortedGroup = group
  sortedGroup.sort(
    proc(a, b: int): int =
      cmp(wm.windows[a].viewport.y, wm.windows[b].viewport.y)
  )

  let
    numSeparators =
      if multiStatusLine:
        0
      else:
        (sortedGroup.len - 1) * WindowSeparatorHeight
    numStatusLines =
      if multiStatusLine:
        sortedGroup.len * StatusLineHeight
      else:
        StatusLineHeight
    totalContentHeight =
      totalHeight - numSeparators - numStatusLines - steadyBottomAreaHeight()
    # Clamp positive: a tiny totalHeight used to give non-last windows height 0.
    windowContentHeight = max(1, totalContentHeight div sortedGroup.len)
    separatorOffset = if multiStatusLine: 0 else: WindowSeparatorHeight

  # Draw a separator only while the last window's 1-row floor still fits
  # below it; otherwise it would push the last window past the box end.
  let separatorBudget =
    max(0, totalHeight - 1 - (sortedGroup.len - 1) * windowContentHeight)
  var separatorsDrawn = 0

  var currentY = startY
  for i, idx in sortedGroup:
    wm.windows[idx].viewport.y = currentY
    if i == sortedGroup.len - 1:
      # Last window: remaining height incl. status/command line, clamped
      # positive (warn-log).
      let remaining = (startY + totalHeight) - currentY
      if remaining < 1:
        logWarn(
          "window_manager",
          "last window does not fit in the group: totalHeight=" & $totalHeight &
            " startY=" & $startY & " currentY=" & $currentY,
        )
      wm.windows[idx].viewport.height = max(1, remaining)
    else:
      # Non-last windows
      if multiStatusLine:
        # Each window has its own status line: cap the height so the last
        # window's 1-row floor still fits below.
        let maxFit = max(1, (totalHeight - 1) div (sortedGroup.len - 1))
        wm.windows[idx].viewport.height =
          min(windowContentHeight + StatusLineHeight, maxFit)
      else:
        # No status line for non-last windows
        wm.windows[idx].viewport.height = windowContentHeight
      currentY += wm.windows[idx].viewport.height
      if separatorOffset > 0 and separatorsDrawn < separatorBudget:
        currentY += separatorOffset
        inc separatorsDrawn

proc equalizeHeightsForResize*(
    wm: EditorWindowManager, group: seq[int], newHeight: int, multiStatusLine: bool
) =
  ## Equalize heights during window resize (handles single window case and bottom detection)
  if group.len == 1:
    let
      idx = group[0]
      window = wm.windows[idx]
      minY = window.viewport.y
    # A single-element vertical group is not necessarily the only window in
    # its column: a gap wider than the adjacency tolerance (or a zero-height
    # neighbor) can leave another window below. Stop the fill there instead
    # of covering it with the full column height.
    var bottomLimit = newHeight
    for i in 0 ..< wm.windows.len:
      if i == idx:
        continue
      let other = wm.windows[i]
      if other.viewport.y > minY and other.viewport.y < bottomLimit and
          window.viewport.x < other.viewport.x + other.viewport.width and
          other.viewport.x < window.viewport.x + window.viewport.width:
        bottomLimit = other.viewport.y
    let
      # Check if this is the bottom window
      isBottomWindow = (window.viewport.y + window.viewport.height >= newHeight - 1)
      # Reserve line for command line if this is the bottom window
      commandLineReserve = steadyReservedBottom(isBottomWindow)
    wm.windows[idx].viewport.height = max(1, bottomLimit - minY - commandLineReserve)
    return

  var sortedGroup = group
  sortedGroup.sort(
    proc(a, b: int): int =
      cmp(wm.windows[a].viewport.y, wm.windows[b].viewport.y)
  )

  let
    firstWindow = wm.windows[sortedGroup[0]]
    lastWindowIdx = sortedGroup[^1]
    lastWindow = wm.windows[lastWindowIdx]
    minY = firstWindow.viewport.y
    # Check if this is the bottom group (last window reaches screen bottom)
    isBottomGroup =
      (lastWindow.viewport.y + lastWindow.viewport.height >= newHeight - 1)
    # Reserve line for command line if this is the bottom group
    commandLineReserve = steadyReservedBottom(isBottomGroup)
    availableHeight = newHeight - minY - commandLineReserve
    numSeparators =
      if multiStatusLine:
        0
      else:
        (sortedGroup.len - 1) * WindowSeparatorHeight
    # Calculate total content height (excluding status lines)
    numStatusLines =
      if multiStatusLine:
        sortedGroup.len * StatusLineHeight
      else:
        StatusLineHeight
    totalContentHeight = availableHeight - numSeparators - numStatusLines
    # Clamp positive: a tiny availableHeight used to give non-last windows height 0.
    windowContentHeight = max(1, totalContentHeight div sortedGroup.len)
    separatorOffset = if multiStatusLine: 0 else: WindowSeparatorHeight

  # Draw a separator only while the last window's 1-row floor still fits
  # below it; otherwise it would push the last window past the box end.
  let separatorBudget =
    max(0, availableHeight - 1 - (sortedGroup.len - 1) * windowContentHeight)
  var separatorsDrawn = 0

  var currentY = minY
  for i, idx in sortedGroup:
    wm.windows[idx].viewport.y = currentY
    if i == sortedGroup.len - 1:
      # Last window: remaining height incl. status line, clamped positive (warn-log).
      let remaining = (minY + availableHeight) - currentY
      if remaining < 1:
        logWarn(
          "window_manager",
          "last window does not fit in the group: availableHeight=" & $availableHeight &
            " minY=" & $minY & " currentY=" & $currentY,
        )
      wm.windows[idx].viewport.height = max(1, remaining)
    else:
      # Non-last windows
      if multiStatusLine:
        # Each window has its own status line: cap the height so the last
        # window's 1-row floor still fits below.
        let maxFit = max(1, (availableHeight - 1) div (sortedGroup.len - 1))
        wm.windows[idx].viewport.height =
          min(windowContentHeight + StatusLineHeight, maxFit)
      else:
        # No status line for non-last windows
        wm.windows[idx].viewport.height = windowContentHeight
      currentY += wm.windows[idx].viewport.height
      if separatorOffset > 0 and separatorsDrawn < separatorBudget:
        currentY += separatorOffset
        inc separatorsDrawn

proc validateViewportInvariants*(
    wm: EditorWindowManager, screenWidth: int = -1, screenHeight: int = -1
) =
  ## Check viewport invariants: positive dimensions, no pairwise overlap,
  ## and placement within the screen. Violations assert in non-release
  ## builds and are warn-logged (logWarn only writes when file logging is
  ## enabled).
  ## The within-screen check is a warning only: a fixed-width sidebar may
  ## exceed a narrower screen.
  for i in 0 ..< wm.windows.len:
    let v = wm.windows[i].viewport
    if v.width <= 0 or v.height <= 0:
      let msg =
        "window " & $i & " has non-positive dimensions: width=" & $v.width & " height=" &
        $v.height
      logWarn("window_manager", msg)

      when not defined(release):
        assert false, msg

    for j in i + 1 ..< wm.windows.len:
      let o = wm.windows[j].viewport
      if v.x < o.x + o.width and o.x < v.x + v.width and v.y < o.y + o.height and
          o.y < v.y + v.height:
        let msg = "windows " & $i & " and " & $j & " overlap"
        logWarn("window_manager", msg)

        # An overlap involving a 1-cell-floor window is the expected
        # degradation on a tiny terminal; only fully-sized overlaps assert.
        when not defined(release):
          if v.width > 1 and v.height > 1 and o.width > 1 and o.height > 1:
            assert false, msg

    if screenWidth > 0 and (v.x < 0 or v.x + v.width > screenWidth):
      logWarn(
        "window_manager",
        "window " & $i & " is outside the screen width: x=" & $v.x & " width=" & $v.width &
          " screenWidth=" & $screenWidth,
      )
    if screenHeight > 0 and (v.y < 0 or v.y + v.height > screenHeight):
      logWarn(
        "window_manager",
        "window " & $i & " is outside the screen height: y=" & $v.y & " height=" &
          $v.height & " screenHeight=" & $screenHeight,
      )

proc closeWindow*(
    wm: EditorWindowManager,
    multiStatusLine: bool,
    screenWidth: int = -1,
    screenHeight: int = -1,
): bool =
  ## Close the active window and redistribute space to remaining windows
  ## Returns true if this was the last window (editor should quit)
  ## Note: The last window is never actually deleted - only the quit flag is returned

  # If only one window left, indicate should quit but don't delete the window
  # This ensures windows.len >= 1 invariant is maintained
  if wm.windows.len <= 1:
    return true

  # Store the viewport of the window being closed
  let
    closedWindow = wm.windows[wm.activeWindowIndex]
    closedX = closedWindow.viewport.x
    closedY = closedWindow.viewport.y
    closedWidth = closedWindow.viewport.width
    closedHeight = closedWindow.viewport.height

  # Remove the active window
  wm.windows.delete(wm.activeWindowIndex)

  # Adjust active index if needed
  if wm.activeWindowIndex >= wm.windows.len:
    wm.activeWindowIndex = wm.windows.len - 1

  # Redistribute the closed window's space by re-equalizing the group it belonged to.
  # This correctly handles 3+ windows where the old per-window approach would cause
  # multiple windows to absorb the same space, resulting in overlapping viewports.

  # Check for horizontal split group (same x and width, stacked vertically)
  var hSplitGroup: seq[int] = @[]
  for i in 0 ..< wm.windows.len:
    if wm.windows[i].viewport.x == closedX and
        wm.windows[i].viewport.width == closedWidth:
      hSplitGroup.add(i)

  # Check for vertical split group (same y and height, side by side)
  var vSplitGroup: seq[int] = @[]
  for i in 0 ..< wm.windows.len:
    if wm.windows[i].viewport.y == closedY and
        wm.windows[i].viewport.height == closedHeight:
      vSplitGroup.add(i)

  if hSplitGroup.len > 0:
    # Horizontal split: re-equalize heights in the group
    var sortedGroup = hSplitGroup
    sortedGroup.sort(
      proc(a, b: int): int =
        cmp(wm.windows[a].viewport.y, wm.windows[b].viewport.y)
    )
    let
      firstY = min(wm.windows[sortedGroup[0]].viewport.y, closedY)
      lastWin = wm.windows[sortedGroup[^1]]
      lastEnd =
        max(lastWin.viewport.y + lastWin.viewport.height, closedY + closedHeight)
      totalHeight = lastEnd - firstY
    if sortedGroup.len > 1:
      wm.equalizeHeightsInGroup(sortedGroup, totalHeight, firstY, multiStatusLine)
    else:
      # Single remaining window: expand to cover the closed window's space
      wm.windows[sortedGroup[0]].viewport.y = firstY
      # Clamp positive: degenerate neighbors could yield a zero totalHeight.
      wm.windows[sortedGroup[0]].viewport.height = max(1, totalHeight)
  elif vSplitGroup.len > 0:
    # Vertical split: re-equalize widths in the group
    var sortedGroup = vSplitGroup
    sortedGroup.sort(
      proc(a, b: int): int =
        cmp(wm.windows[a].viewport.x, wm.windows[b].viewport.x)
    )
    let
      firstX = min(wm.windows[sortedGroup[0]].viewport.x, closedX)
      lastWin = wm.windows[sortedGroup[^1]]
      lastEnd = max(lastWin.viewport.x + lastWin.viewport.width, closedX + closedWidth)
      totalWidth = lastEnd - firstX
    if sortedGroup.len > 1:
      wm.equalizeWidthsInGroup(sortedGroup, totalWidth, firstX)
    else:
      # Single remaining window: expand to cover the closed window's space
      wm.windows[sortedGroup[0]].viewport.x = firstX
      # Clamp positive: degenerate neighbors could yield a zero totalWidth.
      wm.windows[sortedGroup[0]].viewport.width = max(1, totalWidth)
  else:
    # No group matched: re-tile the remaining windows over the bounding box
    # that also covers the closed window so its space is reclaimed.
    var
      boxX = closedX
      boxY = closedY
      boxRight = closedX + closedWidth
      boxBottom = closedY + closedHeight
    for window in wm.windows:
      boxX = min(boxX, window.viewport.x)
      boxY = min(boxY, window.viewport.y)
      boxRight = max(boxRight, window.viewport.x + window.viewport.width)
      boxBottom = max(boxBottom, window.viewport.y + window.viewport.height)
    let
      boxWidth = boxRight - boxX
      boxHeight = boxBottom - boxY

    if wm.windows.len == 1:
      # Single remaining window: expand to the full bounding box.
      wm.windows[0].viewport.x = boxX
      wm.windows[0].viewport.y = boxY
      # Clamp positive: degenerate neighbors could yield a zero box.
      wm.windows[0].viewport.width = max(1, boxWidth)
      wm.windows[0].viewport.height = max(1, boxHeight)
    else:
      # A single column of remaining windows (all share x and width):
      # expand to the full box width and re-equalize heights. The width
      # override ignores fixedWidth: no window keeps its fixed slot here.
      let columns = wm.groupWindowsByXAndWidth()
      if columns.len == 1 and columns[0].len == wm.windows.len:
        for idx in columns[0]:
          wm.windows[idx].viewport.x = boxX
          wm.windows[idx].viewport.width = boxWidth
        wm.equalizeHeightsInGroup(columns[0], boxHeight, boxY, multiStatusLine)
      else:
        # A single row (all share y and height): expand to the box height
        # and re-equalize widths.
        let rows = wm.groupAdjacentWindowsHorizontally()
        if rows.len == 1 and rows[0].len == wm.windows.len:
          for idx in rows[0]:
            wm.windows[idx].viewport.y = boxY
            wm.windows[idx].viewport.height = boxHeight
          wm.equalizeWidthsInGroup(rows[0], boxWidth, boxX)
        else:
          # Complex layout: stack all remaining windows vertically over the box.
          var allIdx: seq[int] = @[]
          for i in 0 ..< wm.windows.len:
            allIdx.add(i)
          for idx in allIdx:
            wm.windows[idx].viewport.x = boxX
            wm.windows[idx].viewport.width = boxWidth
          wm.equalizeHeightsInGroup(allIdx, boxHeight, boxY, multiStatusLine)

  # Activate the new active window
  if wm.windows.len > 0:
    wm.activateWindow(wm.activeWindowIndex)

  # Normalize degenerate dimensions so the redistribution cannot violate
  # the positive-dimension invariant.
  for win in wm.windows:
    win.viewport.width = max(1, win.viewport.width)
    win.viewport.height = max(1, win.viewport.height)

  wm.validateViewportInvariants(screenWidth, screenHeight)

  return false # Not the last window, don't quit

proc onlyWindow*(wm: EditorWindowManager, screenWidth: int, screenHeight: int) =
  ## Close all windows except the active one and resize it to fill the screen.

  if wm.windows.len <= 1:
    return

  let activeWin = wm.windows[wm.activeWindowIndex]

  # Keep only the active window
  wm.windows = @[activeWin]
  wm.activeWindowIndex = 0
  wm.activateWindow(0)

  # Resize viewport to fill the full screen
  activeWin.viewport.x = 0
  activeWin.viewport.y = 0
  activeWin.viewport.width = screenWidth
  activeWin.viewport.height = screenHeight - steadyBottomAreaHeight()

proc vsplit*(
    wm: EditorWindowManager,
    currentBuffer: TextBuffer,
    currentViewport: ViewPort,
    cursorPosition: BufferPosition,
    filename: Option[string] = none(string),
): Result[TextBuffer, string] =
  ## Create a vertical split window (side by side)
  ## Returns the new buffer that should be used

  # Create new buffer for the split
  let newBuffer =
    if filename.isSome:
      let buf = newTextBuffer()
      # Inherit the highlight cap from the current buffer BEFORE loadFile builds
      # the first chunk; otherwise the post-split applyHighlightConfig nils the
      # progressive cache when the cap differs, forcing a full reparse on open
      # (mirrors the :e seed-before-load).
      buf.maxHighlightLineLength = currentBuffer.maxHighlightLineLength

      let loadResult = buf.loadFile(filename.get)
      if loadResult.isErr:
        return err(loadResult.error)

      buf
    else:
      currentBuffer

  let
    # Save original viewport dimensions before modification (ViewPort is ref object)
    origWidth = wm.windows[wm.activeWindowIndex].viewport.width
    origHeight = wm.windows[wm.activeWindowIndex].viewport.height
    origX = wm.windows[wm.activeWindowIndex].viewport.x
    origY = wm.windows[wm.activeWindowIndex].viewport.y

    # Calculate new dimensions - split the active window's width
    splitWidth = origWidth div 2

  # Move the active window to the right half
  wm.windows[wm.activeWindowIndex].viewport.width =
    origWidth - splitWidth - WindowSeparatorWidth
  wm.windows[wm.activeWindowIndex].viewport.x =
    origX + splitWidth + WindowSeparatorWidth
  wm.deactivateAllWindows()

  # When opening the same buffer, inherit cursor position and viewport scroll
  let isSameBuffer = newBuffer == currentBuffer
  let newCursor =
    if isSameBuffer:
      cursorPosition
    else:
      BufferPosition(line: 0, column: 0)
  let newTopLine = if isSameBuffer: currentViewport.topLine else: 0
  let newLeftColumn = if isSameBuffer: currentViewport.leftColumn else: 0

  # Create new window for left half
  let newWindow = EditorWindow(
    buffer: newBuffer,
    bufferIds: @[newBuffer.id], # Per-window tabs start with the split buffer only
    viewport: ViewPort(
      topLine: newTopLine,
      leftColumn: newLeftColumn,
      width: splitWidth,
      height: origHeight,
      x: origX,
      y: origY,
    ),
    cursor: newCursor,
    active: true,
    mode: EditorMode.Normal, # New windows start in Normal mode
    wrapCountCache: WrapCountCache(),
  )

  # Insert new window before the active window (left position)
  wm.windows.insert(newWindow, wm.activeWindowIndex)

  # Equalize widths of all windows at the same vertical position
  let windowGroups = wm.groupWindowsByY()
  for group in windowGroups:
    if group.len > 1:
      var sortedGroup = group
      sortedGroup.sort(
        proc(a, b: int): int =
          cmp(wm.windows[a].viewport.x, wm.windows[b].viewport.x)
      )
      let
        firstWindow = wm.windows[sortedGroup[0]]
        lastWindow = wm.windows[sortedGroup[^1]]
        totalWidth =
          (lastWindow.viewport.x + lastWindow.viewport.width) - firstWindow.viewport.x
        startX = firstWindow.viewport.x
      wm.equalizeWidthsInGroup(sortedGroup, totalWidth, startX)

  return ok(newBuffer)

proc vsplitWithBuffer*(
    wm: EditorWindowManager,
    currentBuffer: TextBuffer,
    currentViewport: ViewPort,
    cursorPosition: BufferPosition,
    newBuffer: TextBuffer,
): Result[TextBuffer, string] =
  ## Create a vertical split window with a specific buffer
  ## Returns the new buffer that should be used

  let
    # Save original viewport dimensions before modification (ViewPort is ref object)
    origWidth = wm.windows[wm.activeWindowIndex].viewport.width
    origHeight = wm.windows[wm.activeWindowIndex].viewport.height
    origX = wm.windows[wm.activeWindowIndex].viewport.x
    origY = wm.windows[wm.activeWindowIndex].viewport.y

    # Calculate new dimensions - split the active window's width
    splitWidth = origWidth div 2

  # Move the active window to the right half
  wm.windows[wm.activeWindowIndex].viewport.width =
    origWidth - splitWidth - WindowSeparatorWidth
  wm.windows[wm.activeWindowIndex].viewport.x =
    origX + splitWidth + WindowSeparatorWidth
  wm.deactivateAllWindows()

  # When opening the same buffer, inherit cursor position and viewport scroll
  let isSameBuffer = newBuffer == currentBuffer
  let newCursor =
    if isSameBuffer:
      cursorPosition
    else:
      BufferPosition(line: 0, column: 0)
  let newTopLine = if isSameBuffer: currentViewport.topLine else: 0
  let newLeftColumn = if isSameBuffer: currentViewport.leftColumn else: 0

  # Create new window for left half with the provided buffer
  let newWindow = EditorWindow(
    buffer: newBuffer,
    bufferIds: @[newBuffer.id], # Per-window tabs start with the provided buffer only
    viewport: ViewPort(
      topLine: newTopLine,
      leftColumn: newLeftColumn,
      width: splitWidth,
      height: origHeight,
      x: origX,
      y: origY,
    ),
    cursor: newCursor,
    active: true,
    mode: EditorMode.Normal, # New windows start in Normal mode
    wrapCountCache: WrapCountCache(),
  )

  # Insert new window before the active window (left position)
  wm.windows.insert(newWindow, wm.activeWindowIndex)

  # Equalize widths of all windows at the same vertical position
  let windowGroups = wm.groupWindowsByY()
  for group in windowGroups:
    if group.len > 1:
      var sortedGroup = group
      sortedGroup.sort(
        proc(a, b: int): int =
          cmp(wm.windows[a].viewport.x, wm.windows[b].viewport.x)
      )
      let
        firstWindow = wm.windows[sortedGroup[0]]
        lastWindow = wm.windows[sortedGroup[^1]]
        totalWidth =
          (lastWindow.viewport.x + lastWindow.viewport.width) - firstWindow.viewport.x
        startX = firstWindow.viewport.x
      wm.equalizeWidthsInGroup(sortedGroup, totalWidth, startX)

  return ok(newBuffer)

proc hsplit*(
    wm: EditorWindowManager,
    currentBuffer: TextBuffer,
    currentViewport: ViewPort,
    cursorPosition: BufferPosition,
    multiStatusLine: bool,
    filename: Option[string] = none(string),
): Result[TextBuffer, string] =
  ## Create a horizontal split window (top and bottom)
  ## Returns the new buffer that should be used

  # Create new buffer for the split
  let newBuffer =
    if filename.isSome:
      let buf = newTextBuffer()
      # Inherit the highlight cap from the current buffer BEFORE loadFile builds
      # the first chunk; otherwise the post-split applyHighlightConfig nils the
      # progressive cache when the cap differs, forcing a full reparse on open
      # (mirrors the :e seed-before-load).
      buf.maxHighlightLineLength = currentBuffer.maxHighlightLineLength

      let loadResult = buf.loadFile(filename.get)
      if loadResult.isErr:
        return err(loadResult.error)

      buf
    else:
      currentBuffer

  let
    # Save original viewport dimensions before modification (ViewPort is ref object)
    origWidth = wm.windows[wm.activeWindowIndex].viewport.width
    origHeight = wm.windows[wm.activeWindowIndex].viewport.height
    origX = wm.windows[wm.activeWindowIndex].viewport.x
    origY = wm.windows[wm.activeWindowIndex].viewport.y

    # Separator offset (WindowSeparatorHeight for single status line, 0 for multi status line)
    separatorOffset = if multiStatusLine: 0 else: WindowSeparatorHeight

    # Calculate available content height:
    # origHeight includes command line for bottom window
    # - Subtract status lines (2 for multi, 1 for single) + command line (1)
    # - Subtract separator if needed
    numReservedLines =
      if multiStatusLine:
        2 * StatusLineHeight + steadyBottomAreaHeight()
      else:
        StatusLineHeight + steadyBottomAreaHeight()
    availableContentHeight = max(0, origHeight - numReservedLines - separatorOffset)

    # Split content area: favor top window (round up) to preserve scroll position
    topContentHeight = (availableContentHeight + 1) div 2 # round up
    bottomContentHeight = availableContentHeight - topContentHeight

  # Move the active window to the bottom half
  # Bottom window has status line + command line
  wm.windows[wm.activeWindowIndex].viewport.height =
    bottomContentHeight + StatusLineHeight + steadyBottomAreaHeight()
  wm.windows[wm.activeWindowIndex].viewport.y =
    origY + topContentHeight + (if multiStatusLine: StatusLineHeight else: 0) +
    separatorOffset
  wm.deactivateAllWindows()

  # When opening the same buffer, inherit cursor position and viewport scroll
  let isSameBuffer = newBuffer == currentBuffer
  let newCursor =
    if isSameBuffer:
      cursorPosition
    else:
      BufferPosition(line: 0, column: 0)
  let newTopLine = if isSameBuffer: currentViewport.topLine else: 0
  let newLeftColumn = if isSameBuffer: currentViewport.leftColumn else: 0

  # Create new window for top half
  # In multi status line mode, top window gets its own status line
  # In single status line mode, top window has no status line
  let newWindow = EditorWindow(
    buffer: newBuffer,
    bufferIds: @[newBuffer.id], # Per-window tabs start with the split buffer only
    viewport: ViewPort(
      topLine: newTopLine,
      leftColumn: newLeftColumn,
      width: origWidth,
      height: topContentHeight + (if multiStatusLine: StatusLineHeight else: 0),
      x: origX,
      y: origY,
    ),
    cursor: newCursor,
    active: true,
    mode: EditorMode.Normal, # New windows start in Normal mode
    wrapCountCache: WrapCountCache(),
  )

  # Insert new window before the active window (top position)
  wm.windows.insert(newWindow, wm.activeWindowIndex)

  # Equalize heights of all windows at the same horizontal position
  let windowGroups = wm.groupWindowsByXAndWidth()
  for group in windowGroups:
    if group.len > 1:
      var sortedGroup = group
      sortedGroup.sort(
        proc(a, b: int): int =
          cmp(wm.windows[a].viewport.y, wm.windows[b].viewport.y)
      )
      let
        firstWindow = wm.windows[sortedGroup[0]]
        lastWindow = wm.windows[sortedGroup[^1]]
        totalHeight =
          (lastWindow.viewport.y + lastWindow.viewport.height) - firstWindow.viewport.y
        startY = firstWindow.viewport.y
      wm.equalizeHeightsInGroup(sortedGroup, totalHeight, startY, multiStatusLine)

  return ok(newBuffer)

proc hsplitWithBuffer*(
    wm: EditorWindowManager,
    currentBuffer: TextBuffer,
    currentViewport: ViewPort,
    cursorPosition: BufferPosition,
    multiStatusLine: bool,
    newBuffer: TextBuffer,
): Result[TextBuffer, string] =
  ## Create a horizontal split window with a specific buffer
  ## Returns the new buffer that should be used

  let
    # Save original viewport dimensions before modification (ViewPort is ref object)
    origWidth = wm.windows[wm.activeWindowIndex].viewport.width
    origHeight = wm.windows[wm.activeWindowIndex].viewport.height
    origX = wm.windows[wm.activeWindowIndex].viewport.x
    origY = wm.windows[wm.activeWindowIndex].viewport.y

    # Separator offset (WindowSeparatorHeight for single status line, 0 for multi status line)
    separatorOffset = if multiStatusLine: 0 else: WindowSeparatorHeight

    numReservedLines =
      if multiStatusLine:
        2 * StatusLineHeight + steadyBottomAreaHeight()
      else:
        StatusLineHeight + steadyBottomAreaHeight()
    availableContentHeight = max(0, origHeight - numReservedLines - separatorOffset)

    # Split content area: favor top window (round up) to preserve scroll position
    topContentHeight = (availableContentHeight + 1) div 2 # round up
    bottomContentHeight = availableContentHeight - topContentHeight

  # Move the active window to the bottom half
  wm.windows[wm.activeWindowIndex].viewport.height =
    bottomContentHeight + StatusLineHeight + steadyBottomAreaHeight()
  wm.windows[wm.activeWindowIndex].viewport.y =
    origY + topContentHeight + (if multiStatusLine: StatusLineHeight else: 0) +
    separatorOffset
  wm.deactivateAllWindows()

  # When opening the same buffer, inherit cursor position and viewport scroll
  let isSameBuffer = newBuffer == currentBuffer
  let newCursor =
    if isSameBuffer:
      cursorPosition
    else:
      BufferPosition(line: 0, column: 0)
  let newTopLine = if isSameBuffer: currentViewport.topLine else: 0
  let newLeftColumn = if isSameBuffer: currentViewport.leftColumn else: 0

  # Create new window for top half with the provided buffer
  let newWindow = EditorWindow(
    buffer: newBuffer,
    bufferIds: @[newBuffer.id], # Per-window tabs start with the provided buffer only
    viewport: ViewPort(
      topLine: newTopLine,
      leftColumn: newLeftColumn,
      width: origWidth,
      height: topContentHeight + (if multiStatusLine: StatusLineHeight else: 0),
      x: origX,
      y: origY,
    ),
    cursor: newCursor,
    active: true,
    mode: EditorMode.Normal, # New windows start in Normal mode
    wrapCountCache: WrapCountCache(),
  )

  # Insert new window before the active window (top position)
  wm.windows.insert(newWindow, wm.activeWindowIndex)

  # Equalize heights of all windows at the same horizontal position
  let windowGroups = wm.groupWindowsByXAndWidth()
  for group in windowGroups:
    if group.len > 1:
      var sortedGroup = group
      sortedGroup.sort(
        proc(a, b: int): int =
          cmp(wm.windows[a].viewport.y, wm.windows[b].viewport.y)
      )
      let
        firstWindow = wm.windows[sortedGroup[0]]
        lastWindow = wm.windows[sortedGroup[^1]]
        totalHeight =
          (lastWindow.viewport.y + lastWindow.viewport.height) - firstWindow.viewport.y
        startY = firstWindow.viewport.y
      wm.equalizeHeightsInGroup(sortedGroup, totalHeight, startY, multiStatusLine)

  return ok(newBuffer)

proc increaseWindowWidth*(wm: EditorWindowManager, delta: int = 1) =
  ## Increase active window width by delta, shrinking adjacent window
  if wm.windows.len <= 1:
    return

  let activeIdx = wm.activeWindowIndex

  # Find horizontal group (same y and height)
  let groups = wm.groupAdjacentWindowsHorizontally()
  var myGroup: seq[int] = @[]
  for group in groups:
    for idx in group:
      if idx == activeIdx:
        myGroup = group
        break
    if myGroup.len > 0:
      break

  if myGroup.len <= 1:
    return

  # Sort by x position
  var sortedGroup = myGroup
  sortedGroup.sort(
    proc(a, b: int): int =
      cmp(wm.windows[a].viewport.x, wm.windows[b].viewport.x)
  )

  # Find position of active window in sorted group
  var activePos = -1
  for i, idx in sortedGroup:
    if idx == activeIdx:
      activePos = i
      break

  # Find neighbor to steal space from (prefer right, fallback to left)
  var neighborPos = -1
  if activePos < sortedGroup.len - 1:
    neighborPos = activePos + 1
  elif activePos > 0:
    neighborPos = activePos - 1

  if neighborPos < 0:
    return

  let neighborIdx = sortedGroup[neighborPos]

  # Check minimum width constraint
  if wm.windows[neighborIdx].viewport.width <= delta:
    return

  # Adjust widths
  wm.windows[activeIdx].viewport.width += delta
  wm.windows[neighborIdx].viewport.width -= delta

  # Adjust x positions for all windows to the right of the change
  if neighborPos > activePos:
    # Neighbor is to the right, shift it right
    wm.windows[neighborIdx].viewport.x += delta
  else:
    # Neighbor is to the left, shift active left
    wm.windows[activeIdx].viewport.x -= delta

proc decreaseWindowWidth*(wm: EditorWindowManager, delta: int = 1) =
  ## Decrease active window width by delta, expanding adjacent window
  if wm.windows.len <= 1:
    return

  let activeIdx = wm.activeWindowIndex
  let activeWin = wm.windows[activeIdx]

  # Check minimum width constraint for active window
  if activeWin.viewport.width <= delta:
    return

  # Find horizontal group (same y and height)
  let groups = wm.groupAdjacentWindowsHorizontally()
  var myGroup: seq[int] = @[]
  for group in groups:
    for idx in group:
      if idx == activeIdx:
        myGroup = group
        break
    if myGroup.len > 0:
      break

  if myGroup.len <= 1:
    return

  # Sort by x position
  var sortedGroup = myGroup
  sortedGroup.sort(
    proc(a, b: int): int =
      cmp(wm.windows[a].viewport.x, wm.windows[b].viewport.x)
  )

  # Find position of active window in sorted group
  var activePos = -1
  for i, idx in sortedGroup:
    if idx == activeIdx:
      activePos = i
      break

  # Find neighbor to give space to (prefer right, fallback to left)
  var neighborPos = -1
  if activePos < sortedGroup.len - 1:
    neighborPos = activePos + 1
  elif activePos > 0:
    neighborPos = activePos - 1

  if neighborPos < 0:
    return

  let neighborIdx = sortedGroup[neighborPos]

  # Adjust widths
  wm.windows[activeIdx].viewport.width -= delta
  wm.windows[neighborIdx].viewport.width += delta

  # Adjust x positions
  if neighborPos > activePos:
    # Neighbor is to the right, shift it left
    wm.windows[neighborIdx].viewport.x -= delta
  else:
    # Neighbor is to the left, shift active right
    wm.windows[activeIdx].viewport.x += delta

proc increaseWindowHeight*(wm: EditorWindowManager, delta: int = 1) =
  ## Increase active window height by delta, shrinking adjacent window
  if wm.windows.len <= 1:
    return

  let activeIdx = wm.activeWindowIndex

  # Find vertical group (same x and width, stacked vertically)
  let groups = wm.groupAdjacentWindowsVertically()
  var myGroup: seq[int] = @[]
  for group in groups:
    for idx in group:
      if idx == activeIdx:
        myGroup = group
        break
    if myGroup.len > 0:
      break

  if myGroup.len <= 1:
    return

  # Sort by y position
  var sortedGroup = myGroup
  sortedGroup.sort(
    proc(a, b: int): int =
      cmp(wm.windows[a].viewport.y, wm.windows[b].viewport.y)
  )

  # Find position of active window in sorted group
  var activePos = -1
  for i, idx in sortedGroup:
    if idx == activeIdx:
      activePos = i
      break

  # Find neighbor to steal space from (prefer below, fallback to above)
  var neighborPos = -1
  if activePos < sortedGroup.len - 1:
    neighborPos = activePos + 1
  elif activePos > 0:
    neighborPos = activePos - 1

  if neighborPos < 0:
    return

  let neighborIdx = sortedGroup[neighborPos]

  # Check minimum height constraint
  if wm.windows[neighborIdx].viewport.height <= delta:
    return

  # Adjust heights
  wm.windows[activeIdx].viewport.height += delta
  wm.windows[neighborIdx].viewport.height -= delta

  # Adjust y positions
  if neighborPos > activePos:
    # Neighbor is below, shift it down
    wm.windows[neighborIdx].viewport.y += delta
  else:
    # Neighbor is above, shift active up
    wm.windows[activeIdx].viewport.y -= delta

proc decreaseWindowHeight*(wm: EditorWindowManager, delta: int = 1) =
  ## Decrease active window height by delta, expanding adjacent window
  if wm.windows.len <= 1:
    return

  let activeIdx = wm.activeWindowIndex
  let activeWin = wm.windows[activeIdx]

  # Check minimum height constraint for active window
  if activeWin.viewport.height <= delta:
    return

  # Find vertical group (same x and width, stacked vertically)
  let groups = wm.groupAdjacentWindowsVertically()
  var myGroup: seq[int] = @[]
  for group in groups:
    for idx in group:
      if idx == activeIdx:
        myGroup = group
        break
    if myGroup.len > 0:
      break

  if myGroup.len <= 1:
    return

  # Sort by y position
  var sortedGroup = myGroup
  sortedGroup.sort(
    proc(a, b: int): int =
      cmp(wm.windows[a].viewport.y, wm.windows[b].viewport.y)
  )

  # Find position of active window in sorted group
  var activePos = -1
  for i, idx in sortedGroup:
    if idx == activeIdx:
      activePos = i
      break

  # Find neighbor to give space to (prefer below, fallback to above)
  var neighborPos = -1
  if activePos < sortedGroup.len - 1:
    neighborPos = activePos + 1
  elif activePos > 0:
    neighborPos = activePos - 1

  if neighborPos < 0:
    return

  let neighborIdx = sortedGroup[neighborPos]

  # Adjust heights
  wm.windows[activeIdx].viewport.height -= delta
  wm.windows[neighborIdx].viewport.height += delta

  # Adjust y positions
  if neighborPos > activePos:
    # Neighbor is below, shift it up
    wm.windows[neighborIdx].viewport.y -= delta
  else:
    # Neighbor is above, shift active down
    wm.windows[activeIdx].viewport.y += delta

proc swapWindows*(wm: EditorWindowManager) =
  ## Swap the active window with the next window (Ctrl-w x)
  ## Swaps viewport positions while keeping buffer/cursor state with each window.
  if wm.windows.len <= 1:
    return

  let
    activeIdx = wm.activeWindowIndex
    nextIdx = (activeIdx + 1) mod wm.windows.len

  # Swap viewports between the two windows
  let tempViewport = ViewPort(
    x: wm.windows[activeIdx].viewport.x,
    y: wm.windows[activeIdx].viewport.y,
    width: wm.windows[activeIdx].viewport.width,
    height: wm.windows[activeIdx].viewport.height,
    topLine: wm.windows[activeIdx].viewport.topLine,
    leftColumn: wm.windows[activeIdx].viewport.leftColumn,
  )

  wm.windows[activeIdx].viewport.x = wm.windows[nextIdx].viewport.x
  wm.windows[activeIdx].viewport.y = wm.windows[nextIdx].viewport.y
  wm.windows[activeIdx].viewport.width = wm.windows[nextIdx].viewport.width
  wm.windows[activeIdx].viewport.height = wm.windows[nextIdx].viewport.height

  wm.windows[nextIdx].viewport.x = tempViewport.x
  wm.windows[nextIdx].viewport.y = tempViewport.y
  wm.windows[nextIdx].viewport.width = tempViewport.width
  wm.windows[nextIdx].viewport.height = tempViewport.height

  # Swap positions in the sequence so index order matches screen order
  swap(wm.windows[activeIdx], wm.windows[nextIdx])

  # Update active index to follow the active window
  wm.activeWindowIndex = nextIdx

proc equalizeAllWindows*(wm: EditorWindowManager, multiStatusLine: bool) =
  ## Equalize all window sizes
  if wm.windows.len <= 1:
    return

  # Equalize widths in horizontal groups
  let hGroups = wm.groupWindowsByY()
  for group in hGroups:
    if group.len > 1:
      var sortedGroup = group
      sortedGroup.sort(
        proc(a, b: int): int =
          cmp(wm.windows[a].viewport.x, wm.windows[b].viewport.x)
      )
      let
        firstWindow = wm.windows[sortedGroup[0]]
        lastWindow = wm.windows[sortedGroup[^1]]
        totalWidth =
          (lastWindow.viewport.x + lastWindow.viewport.width) - firstWindow.viewport.x
        startX = firstWindow.viewport.x
      wm.equalizeWidthsInGroup(sortedGroup, totalWidth, startX)

  # Equalize heights in vertical groups
  let vGroups = wm.groupWindowsByXAndWidth()
  for group in vGroups:
    if group.len > 1:
      var sortedGroup = group
      sortedGroup.sort(
        proc(a, b: int): int =
          cmp(wm.windows[a].viewport.y, wm.windows[b].viewport.y)
      )
      let
        firstWindow = wm.windows[sortedGroup[0]]
        lastWindow = wm.windows[sortedGroup[^1]]
        totalHeight =
          (lastWindow.viewport.y + lastWindow.viewport.height) - firstWindow.viewport.y
        startY = firstWindow.viewport.y
      wm.equalizeHeightsInGroup(sortedGroup, totalHeight, startY, multiStatusLine)

proc resizeWindows*(
    wm: EditorWindowManager,
    newWidth: int,
    newHeight: int,
    oldWidth: int,
    oldHeight: int,
    multiStatusLine: bool,
) =
  ## Adjust all window viewports when terminal is resized

  if oldWidth <= 0 or oldHeight <= 0 or newWidth <= 0 or newHeight <= 0:
    return

  # Compute adjacency groups BEFORE scaling: the pre-resize layout tiles
  # exactly, while integer truncation during ratio-scaling can widen the
  # gaps between windows beyond the ±1 adjacency tolerance (e.g. scaling
  # the startup 80x20 layout up to the real terminal size), which would
  # split each window into its own group and make them overlap.
  let
    horizontalGroups = wm.groupAdjacentWindowsHorizontally()
    verticalGroups = wm.groupAdjacentWindowsVertically()

  let
    widthRatio = newWidth.float / oldWidth.float
    heightRatio = newHeight.float / oldHeight.float

  # Scale all windows proportionally
  for window in wm.windows.mitems:
    window.viewport.width = int(window.viewport.width.float * widthRatio)
    window.viewport.height = int(window.viewport.height.float * heightRatio)
    window.viewport.x = int(window.viewport.x.float * widthRatio)
    window.viewport.y = int(window.viewport.y.float * heightRatio)

    # Clamp viewport scroll positions
    if window.viewport.topLine >= window.buffer.len:
      window.viewport.resetViewportTop(max(0, window.buffer.len - 1))
    if window.cursor.line < window.viewport.topLine:
      window.viewport.resetViewportTop(window.cursor.line)

  # Horizontal groups (same y coordinate AND height, horizontally adjacent)
  for group in horizontalGroups:
    wm.equalizeWidthsForResize(group, newWidth)

  # The horizontal pass can shift one member of a column (T-junction
  # corner): re-align each vertical group to its topmost member so the
  # vertical pass re-tiles a straight column.
  for group in verticalGroups:
    if group.len > 1:
      var sortedGroup = group
      sortedGroup.sort(
        proc(a, b: int): int =
          cmp(wm.windows[a].viewport.y, wm.windows[b].viewport.y)
      )
      let head = wm.windows[sortedGroup[0]]
      for idx in sortedGroup:
        let member = wm.windows[idx]
        let rightEdge = member.viewport.x + member.viewport.width
        wm.windows[idx].viewport.x = head.viewport.x
        # Align width to the head's, but never past the member's own row's
        # right edge: a row split further than the head's cannot spare the
        # head's width without covering its row-mates.
        wm.windows[idx].viewport.width =
          max(1, min(head.viewport.width, rightEdge - head.viewport.x))

  # Vertical groups (same x and width, vertically adjacent)
  for group in verticalGroups:
    wm.equalizeHeightsForResize(group, newHeight, multiStatusLine)

  # After all resize operations, adjust viewport to keep cursor visible
  # This must be done AFTER equalizeHeightsForResize since that changes viewport.height

  # Find max bottom Y to determine which windows are bottom windows
  var maxBottomY = 0
  for window in wm.windows:
    let bottomY = window.viewport.y + window.viewport.height
    if bottomY > maxBottomY:
      maxBottomY = bottomY

  for window in wm.windows.mitems:
    # Determine if this is a bottom window
    let
      windowBottomY = window.viewport.y + window.viewport.height
      isBottomWindow = (windowBottomY == maxBottomY)

    # Calculate reserved lines based on window position and status line mode.
    # Status line and command line share the same row.
    # Deliberately steady: transient command-line growth (wrapped input,
    # multi-line messages) is excluded from persistent geometry, matching
    # the steady reserve adjustViewportForCursor scrolls with.
    let reservedLines =
      if isBottomWindow:
        steadyBottomAreaHeight() # Status + command share same row
      else:
        if multiStatusLine: StatusLineHeight else: 0

    let visibleHeight = max(1, window.viewport.height - reservedLines)

    # If cursor is now below the visible area, adjust topLine
    if window.cursor.line >= window.viewport.topLine + visibleHeight:
      window.viewport.resetViewportTop(max(0, window.cursor.line - visibleHeight + 1))
    # If cursor is above the visible area
    elif window.cursor.line < window.viewport.topLine:
      window.viewport.resetViewportTop(window.cursor.line)

  wm.validateViewportInvariants(newWidth, newHeight)
