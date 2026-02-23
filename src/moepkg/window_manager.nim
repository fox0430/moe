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

import types, buffer, modes

type EditorWindowManager* = ref object ## Manages multiple split windows
  windows*: seq[EditorWindow]
  activeWindowIndex*: int

const
  WindowSeparatorWidth* = 1 ## Width of separator between split windows
  StatusLineHeight* = 1 ## Height of a status line
  CommandLineHeight* = 1 ## Height of the command line

proc newEditorWindowManager*(): EditorWindowManager =
  ## Create a new window manager
  EditorWindowManager(windows: @[], activeWindowIndex: 0)

proc activeBuffer*(wm: EditorWindowManager): Option[TextBuffer] =
  ## Get the buffer of the active window
  if wm.windows.len > 0 and wm.activeWindowIndex < wm.windows.len:
    return some(wm.windows[wm.activeWindowIndex].buffer)

proc deactivateAllWindows(wm: EditorWindowManager) =
  ## Deactivate all windows
  for window in wm.windows.mitems:
    window.active = false

proc activateWindow(wm: EditorWindowManager, index: int) =
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
  ## Equalize widths of windows in a horizontal group
  if group.len <= 1:
    return

  var sortedGroup = group
  sortedGroup.sort(
    proc(a, b: int): int =
      cmp(wm.windows[a].viewport.x, wm.windows[b].viewport.x)
  )

  let
    numSeparators = sortedGroup.len - 1
    availableWidth = totalWidth - numSeparators * WindowSeparatorWidth
    windowWidth = availableWidth div sortedGroup.len

  var currentX = startX
  for i, idx in sortedGroup:
    wm.windows[idx].viewport.x = currentX
    if i == sortedGroup.len - 1:
      # Last window gets remaining width
      wm.windows[idx].viewport.width = (startX + totalWidth) - currentX
    else:
      wm.windows[idx].viewport.width = windowWidth
      currentX += windowWidth + WindowSeparatorWidth

proc equalizeWidthsForResize*(wm: EditorWindowManager, group: seq[int], newWidth: int) =
  ## Equalize widths during window resize (handles single window case)
  if group.len == 1:
    let
      idx = group[0]
      minX = wm.windows[idx].viewport.x
    wm.windows[idx].viewport.width = newWidth - minX
    return

  var sortedGroup = group
  sortedGroup.sort(
    proc(a, b: int): int =
      cmp(wm.windows[a].viewport.x, wm.windows[b].viewport.x)
  )

  let
    firstWindow = wm.windows[sortedGroup[0]]
    minX = firstWindow.viewport.x
    availableWidth = newWidth - minX
    numSeparators = sortedGroup.len - 1
    totalWidth = availableWidth - numSeparators * WindowSeparatorWidth
    windowWidth = totalWidth div sortedGroup.len

  var currentX = minX
  for i, idx in sortedGroup:
    wm.windows[idx].viewport.x = currentX
    if i == sortedGroup.len - 1:
      wm.windows[idx].viewport.width = (minX + availableWidth) - currentX
    else:
      wm.windows[idx].viewport.width = windowWidth
      currentX += windowWidth + WindowSeparatorWidth

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
        (sortedGroup.len - 1) * WindowSeparatorWidth
    numStatusLines =
      if multiStatusLine:
        sortedGroup.len * StatusLineHeight
      else:
        StatusLineHeight
    totalContentHeight =
      totalHeight - numSeparators - numStatusLines - CommandLineHeight
    windowContentHeight = totalContentHeight div sortedGroup.len
    separatorOffset = if multiStatusLine: 0 else: WindowSeparatorWidth

  var currentY = startY
  for i, idx in sortedGroup:
    wm.windows[idx].viewport.y = currentY
    if i == sortedGroup.len - 1:
      # Last window: give it remaining height including status line and command line
      wm.windows[idx].viewport.height = (startY + totalHeight) - currentY
    else:
      # Non-last windows
      if multiStatusLine:
        # Each window has its own status line
        wm.windows[idx].viewport.height = windowContentHeight + StatusLineHeight
      else:
        # No status line for non-last windows
        wm.windows[idx].viewport.height = windowContentHeight
      currentY += wm.windows[idx].viewport.height + separatorOffset

proc equalizeHeightsForResize*(
    wm: EditorWindowManager, group: seq[int], newHeight: int, multiStatusLine: bool
) =
  ## Equalize heights during window resize (handles single window case and bottom detection)
  if group.len == 1:
    let
      idx = group[0]
      window = wm.windows[idx]
      minY = window.viewport.y
      # Check if this is the bottom window
      isBottomWindow = (window.viewport.y + window.viewport.height >= newHeight - 1)
      # Reserve line for command line if this is the bottom window
      commandLineReserve = if isBottomWindow: CommandLineHeight else: 0
    wm.windows[idx].viewport.height = newHeight - minY - commandLineReserve
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
    commandLineReserve = if isBottomGroup: CommandLineHeight else: 0
    availableHeight = newHeight - minY - commandLineReserve
    numSeparators =
      if multiStatusLine:
        0
      else:
        (sortedGroup.len - 1) * WindowSeparatorWidth
    # Calculate total content height (excluding status lines)
    numStatusLines =
      if multiStatusLine:
        sortedGroup.len * StatusLineHeight
      else:
        StatusLineHeight
    totalContentHeight = availableHeight - numSeparators - numStatusLines
    windowContentHeight = totalContentHeight div sortedGroup.len
    separatorOffset = if multiStatusLine: 0 else: WindowSeparatorWidth

  var currentY = minY
  for i, idx in sortedGroup:
    wm.windows[idx].viewport.y = currentY
    if i == sortedGroup.len - 1:
      # Last window: give it remaining height including status line
      wm.windows[idx].viewport.height = (minY + availableHeight) - currentY
    else:
      # Non-last windows
      if multiStatusLine:
        # Each window has its own status line
        wm.windows[idx].viewport.height = windowContentHeight + StatusLineHeight
      else:
        # No status line for non-last windows
        wm.windows[idx].viewport.height = windowContentHeight
      currentY += wm.windows[idx].viewport.height + separatorOffset

proc closeWindow*(wm: EditorWindowManager, multiStatusLine: bool): bool =
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
      wm.windows[sortedGroup[0]].viewport.height = totalHeight
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
      wm.windows[sortedGroup[0]].viewport.width = totalWidth

  # Activate the new active window
  if wm.windows.len > 0:
    wm.activateWindow(wm.activeWindowIndex)

  return false # Not the last window, don't quit

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
    bufferList: @[newBuffer], # Initialize with current buffer only
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
    bufferList: @[newBuffer], # Initialize with current buffer only
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

    # Separator offset (WindowSeparatorWidth for single status line, 0 for multi status line)
    separatorOffset = if multiStatusLine: 0 else: WindowSeparatorWidth

    # Calculate available content height:
    # origHeight includes command line for bottom window
    # - Subtract status lines (2 for multi, 1 for single) + command line (1)
    # - Subtract separator if needed
    numReservedLines =
      if multiStatusLine:
        2 * StatusLineHeight + CommandLineHeight
      else:
        StatusLineHeight + CommandLineHeight
    availableContentHeight = origHeight - numReservedLines - separatorOffset

    # Split content area: favor top window (round up) to preserve scroll position
    topContentHeight = (availableContentHeight + 1) div 2 # round up
    bottomContentHeight = availableContentHeight - topContentHeight

  # Move the active window to the bottom half
  # Bottom window has status line + command line
  wm.windows[wm.activeWindowIndex].viewport.height =
    bottomContentHeight + StatusLineHeight + CommandLineHeight
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
    bufferList: @[newBuffer], # Initialize with current buffer only
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

    # Separator offset (WindowSeparatorWidth for single status line, 0 for multi status line)
    separatorOffset = if multiStatusLine: 0 else: WindowSeparatorWidth

    numReservedLines =
      if multiStatusLine:
        2 * StatusLineHeight + CommandLineHeight
      else:
        StatusLineHeight + CommandLineHeight
    availableContentHeight = origHeight - numReservedLines - separatorOffset

    # Split content area: favor top window (round up) to preserve scroll position
    topContentHeight = (availableContentHeight + 1) div 2 # round up
    bottomContentHeight = availableContentHeight - topContentHeight

  # Move the active window to the bottom half
  wm.windows[wm.activeWindowIndex].viewport.height =
    bottomContentHeight + StatusLineHeight + CommandLineHeight
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
    bufferList: @[newBuffer], # Initialize with current buffer only
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
      window.viewport.topLine = max(0, window.buffer.len - 1)
    if window.cursor.line < window.viewport.topLine:
      window.viewport.topLine = window.cursor.line

  # Horizontal groups (same y coordinate AND height, horizontally adjacent)
  let horizontalGroups = wm.groupAdjacentWindowsHorizontally()
  for group in horizontalGroups:
    wm.equalizeWidthsForResize(group, newWidth)

  # Vertical groups (same x and width, vertically adjacent)
  let verticalGroups = wm.groupAdjacentWindowsVertically()
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

    # Calculate reserved lines based on window position and status line mode
    # Status line and command line share the same row
    let reservedLines =
      if isBottomWindow:
        StatusLineHeight # Status + command share same row
      else:
        if multiStatusLine: StatusLineHeight else: 0

    let visibleHeight = max(1, window.viewport.height - reservedLines)

    # If cursor is now below the visible area, adjust topLine
    if window.cursor.line >= window.viewport.topLine + visibleHeight:
      window.viewport.topLine = max(0, window.cursor.line - visibleHeight + 1)
    # If cursor is above the visible area
    elif window.cursor.line < window.viewport.topLine:
      window.viewport.topLine = window.cursor.line
