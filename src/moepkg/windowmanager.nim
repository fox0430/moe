#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import types, buffer, cursor

type EditorWindowManager* = ref object ## Manages multiple split windows
  windows*: seq[EditorWindow]
  activeWindowIndex*: int

proc newEditorWindowManager*(): EditorWindowManager =
  ## Create a new window manager
  EditorWindowManager(windows: @[], activeWindowIndex: 0)

proc activeBuffer*(wm: EditorWindowManager): Option[TextBuffer] =
  ## Get the buffer of the active window
  if wm.windows.len > 0 and wm.activeWindowIndex < wm.windows.len:
    return some(wm.windows[wm.activeWindowIndex].buffer)

proc switchToNextWindow*(wm: EditorWindowManager) =
  ## Switch to the next window (Ctrl-w, k)
  if wm.windows.len <= 1:
    return

  # Deactivate all windows
  for i in 0 ..< wm.windows.len:
    wm.windows[i].active = false

  wm.activeWindowIndex = (wm.activeWindowIndex + 1) mod wm.windows.len

  # Activate the new window
  wm.windows[wm.activeWindowIndex].active = true

proc switchToPrevWindow*(wm: EditorWindowManager) =
  ## Switch to the previous window (Ctrl-w, j)
  if wm.windows.len <= 1:
    return

  # Deactivate all windows
  for i in 0 ..< wm.windows.len:
    wm.windows[i].active = false

  wm.activeWindowIndex = (wm.activeWindowIndex - 1 + wm.windows.len) mod wm.windows.len

  # Activate the new window
  wm.windows[wm.activeWindowIndex].active = true

proc closeWindow*(wm: EditorWindowManager): bool =
  ## Close the active window and redistribute space to remaining windows
  ## Returns true if this was the last window (editor should quit)

  # If no windows or only one window, indicate should quit
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

  # Redistribute the closed window's space to adjacent windows
  # Find windows that were adjacent to the closed window
  for window in wm.windows.mitems:
    # Check if window was to the right of closed window (vertical split case)
    if window.viewport.x == closedX + closedWidth + 1 and window.viewport.y == closedY and
        window.viewport.height == closedHeight:
      # Expand this window to the left
      window.viewport.x = closedX
      window.viewport.width += closedWidth + 1 # +1 for separator

    # Check if window was to the left of closed window
    elif window.viewport.x + window.viewport.width + 1 == closedX and
        window.viewport.y == closedY and window.viewport.height == closedHeight:
      # Expand this window to the right
      window.viewport.width += closedWidth + 1

    # Check if window was below closed window (horizontal split case)
    elif window.viewport.y == closedY + closedHeight + 1 and window.viewport.x == closedX and
        window.viewport.width == closedWidth:
      # Expand this window upward
      window.viewport.y = closedY
      window.viewport.height += closedHeight + 1

    # Check if window was above closed window
    elif window.viewport.y + window.viewport.height + 1 == closedY and
        window.viewport.x == closedX and window.viewport.width == closedWidth:
      # Expand this window downward
      window.viewport.height += closedHeight + 1

  # Activate the new active window
  if wm.windows.len > 0:
    # Deactivate all
    for i in 0 ..< wm.windows.len:
      wm.windows[i].active = false
    # Activate current
    wm.windows[wm.activeWindowIndex].active = true

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

  # If no windows exist yet, create first window from current state
  if wm.windows.len == 0:
    wm.windows.add(
      EditorWindow(
        buffer: currentBuffer,
        viewport: currentViewport,
        cursor: cursorPosition,
        active: false,
      )
    )

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
    # Split the active window vertically (side by side)
    originalViewport = wm.windows[wm.activeWindowIndex].viewport

    # Calculate new dimensions - split the active window's width
    splitWidth = originalViewport.width div 2

  # Update the active window to use left half
  wm.windows[wm.activeWindowIndex].viewport.width = splitWidth
  wm.windows[wm.activeWindowIndex].active = false

  # Create new window for right half
  let newWindow = EditorWindow(
    buffer: newBuffer,
    viewport: ViewPort(
      topLine: 0,
      leftColumn: 0,
      width: originalViewport.width - splitWidth - 1,
      height: originalViewport.height,
      x: originalViewport.x + splitWidth + 1,
      y: originalViewport.y,
    ),
    cursor: BufferPosition(line: 0, column: 0),
    active: true,
  )

  # Insert new window right after the active window
  wm.windows.insert(newWindow, wm.activeWindowIndex + 1)
  wm.activeWindowIndex = wm.activeWindowIndex + 1

  # Equalize widths of all windows at the same vertical position
  var windowGroups: seq[seq[int]] = @[]
  for i in 0 ..< wm.windows.len:
    var foundGroup = false
    for group in windowGroups.mitems:
      if group.len > 0 and wm.windows[group[0]].viewport.y == wm.windows[i].viewport.y:
        group.add(i)
        foundGroup = true
        break
    if not foundGroup:
      windowGroups.add(@[i])

  # Equalize widths within each horizontal group
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
        numSeparators = sortedGroup.len - 1
        availableWidth = totalWidth - numSeparators
        windowWidth = availableWidth div sortedGroup.len

      var currentX = firstWindow.viewport.x
      for i, idx in sortedGroup:
        wm.windows[idx].viewport.x = currentX
        if i == sortedGroup.len - 1:
          wm.windows[idx].viewport.width =
            (firstWindow.viewport.x + totalWidth) - currentX
        else:
          wm.windows[idx].viewport.width = windowWidth
          currentX += windowWidth + 1

  return ok(newBuffer)

proc hsplit*(
    wm: EditorWindowManager,
    currentBuffer: TextBuffer,
    currentViewport: ViewPort,
    cursorPosition: BufferPosition,
    filename: Option[string] = none(string),
): Result[TextBuffer, string] =
  ## Create a horizontal split window (top and bottom)
  ## Returns the new buffer that should be used

  # If no windows exist yet, create first window from current state
  if wm.windows.len == 0:
    wm.windows.add(
      EditorWindow(
        buffer: currentBuffer,
        viewport: currentViewport,
        cursor: cursorPosition,
        active: false,
      )
    )

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
    # Split the active window horizontally (top and bottom)
    originalViewport = wm.windows[wm.activeWindowIndex].viewport

    # Calculate new dimensions - split the active window's height
    splitHeight = originalViewport.height div 2

  # Update the active window to use top half
  wm.windows[wm.activeWindowIndex].viewport.height = splitHeight
  wm.windows[wm.activeWindowIndex].active = false

  # Create new window for bottom half
  let newWindow = EditorWindow(
    buffer: newBuffer,
    viewport: ViewPort(
      topLine: 0,
      leftColumn: 0,
      width: originalViewport.width,
      height: originalViewport.height - splitHeight - 1,
      x: originalViewport.x,
      y: originalViewport.y + splitHeight + 1,
    ),
    cursor: BufferPosition(line: 0, column: 0),
    active: true,
  )

  # Insert new window right after the active window
  wm.windows.insert(newWindow, wm.activeWindowIndex + 1)
  wm.activeWindowIndex = wm.activeWindowIndex + 1

  # Equalize heights of all windows at the same horizontal position
  var windowGroups: seq[seq[int]] = @[]
  for i in 0 ..< wm.windows.len:
    var foundGroup = false
    for group in windowGroups.mitems:
      if group.len > 0 and wm.windows[group[0]].viewport.x == wm.windows[i].viewport.x and
          wm.windows[group[0]].viewport.width == wm.windows[i].viewport.width:
        group.add(i)
        foundGroup = true
        break
    if not foundGroup:
      windowGroups.add(@[i])

  # Equalize heights within each vertical group
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
        numSeparators = sortedGroup.len - 1
        availableHeight = totalHeight - numSeparators
        windowHeight = availableHeight div sortedGroup.len

      var currentY = firstWindow.viewport.y
      for i, idx in sortedGroup:
        wm.windows[idx].viewport.y = currentY
        if i == sortedGroup.len - 1:
          wm.windows[idx].viewport.height =
            (firstWindow.viewport.y + totalHeight) - currentY
        else:
          wm.windows[idx].viewport.height = windowHeight
          currentY += windowHeight + 1

  return ok(newBuffer)

proc resizeWindows*(
    wm: EditorWindowManager,
    newWidth: int,
    newHeight: int,
    oldWidth: int,
    oldHeight: int,
) =
  ## Adjust all window viewports when terminal is resized

  if wm.windows.len == 0:
    return

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
  var horizontalGroups: seq[seq[int]] = @[]
  for i in 0 ..< wm.windows.len:
    var foundGroup = false
    for group in horizontalGroups.mitems:
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
      horizontalGroups.add(@[i])

  # Equalize widths within horizontal groups
  for group in horizontalGroups:
    if group.len > 1:
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
        totalWidth = availableWidth - numSeparators
        windowWidth = totalWidth div sortedGroup.len

      var currentX = minX
      for i, idx in sortedGroup:
        wm.windows[idx].viewport.x = currentX
        if i == sortedGroup.len - 1:
          wm.windows[idx].viewport.width = (minX + availableWidth) - currentX
        else:
          wm.windows[idx].viewport.width = windowWidth
          currentX += windowWidth + 1
    elif group.len == 1:
      let
        idx = group[0]
        minX = wm.windows[idx].viewport.x
      wm.windows[idx].viewport.width = newWidth - minX

  # Vertical groups (same x and width, vertically adjacent)
  var verticalGroups: seq[seq[int]] = @[]
  for i in 0 ..< wm.windows.len:
    var foundGroup = false
    for group in verticalGroups.mitems:
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
      verticalGroups.add(@[i])

  # Equalize heights within vertical groups
  for group in verticalGroups:
    if group.len > 1:
      var sortedGroup = group
      sortedGroup.sort(
        proc(a, b: int): int =
          cmp(wm.windows[a].viewport.y, wm.windows[b].viewport.y)
      )

      let
        firstWindow = wm.windows[sortedGroup[0]]
        minY = firstWindow.viewport.y
        availableHeight = newHeight - minY
        numSeparators = sortedGroup.len - 1
        totalHeight = availableHeight - numSeparators
        windowHeight = totalHeight div sortedGroup.len

      var currentY = minY
      for i, idx in sortedGroup:
        wm.windows[idx].viewport.y = currentY
        if i == sortedGroup.len - 1:
          wm.windows[idx].viewport.height = (minY + availableHeight) - currentY
        else:
          wm.windows[idx].viewport.height = windowHeight
          currentY += windowHeight + 1
    elif group.len == 1:
      let
        idx = group[0]
        minY = wm.windows[idx].viewport.y
      wm.windows[idx].viewport.height = newHeight - minY
