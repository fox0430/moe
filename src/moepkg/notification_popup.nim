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

## Notification Popup display
##
## This module provides floating popup notifications for editor messages.
## Notifications appear in a configurable screen corner and auto-dismiss
## after a timeout.

import std/[strutils, unicode, monotimes, times]

import pkg/celina

import color, popup_render, unicode_utils

import types/notification_popup_types
export notification_popup_types

const
  DefaultMaxVisible* = 3
  DefaultTimeoutMs*: int = 3000
  DefaultMaxWidth* = 60
  MaxQueueSize* = 10
  # Frame is either a border (2 cols) or space margins (2 cols) — always 2.
  PopupFrameSize* = 2
  ClampedRowsMarker* = "... (:messages)"
    ## Stands in for rows a popup had no room to draw, naming where the whole
    ## report can be read.

proc notificationInfoStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.notificationPopupInfo)

proc notificationInfoBorderStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.notificationPopupInfoBorder)

proc notificationWarningStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.notificationPopupWarning)

proc notificationWarningBorderStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.notificationPopupWarningBorder)

proc notificationErrorStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.notificationPopupError)

proc notificationErrorBorderStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.notificationPopupErrorBorder)

proc newNotificationPopupManager*(): NotificationPopupManager =
  NotificationPopupManager(
    queue: @[],
    maxVisible: DefaultMaxVisible,
    timeoutMs: DefaultTimeoutMs,
    position: nppBottomRight,
    maxWidth: DefaultMaxWidth,
    showBorder: false,
  )

proc wrapLine(line: string, maxWidth: int): seq[string] =
  ## Wrap a single line to fit within maxWidth (in rune width).
  if line.runeLen == 0:
    return @[""]

  if maxWidth <= 0:
    return @[line]

  var current = ""
  var currentWidth = 0

  for r in line.runes:
    let w = runeWidth(r)
    if currentWidth + w > maxWidth and currentWidth > 0:
      result.add(current)
      current = $r
      currentWidth = w
    else:
      current.add($r)
      currentWidth += w

  if current.len > 0:
    result.add(current)

proc wrapMessage(mgr: NotificationPopupManager, message: string): seq[string] =
  # `maxWidth` bounds the outer popup width, so reserve frame space for content.
  let contentMaxWidth = max(1, mgr.maxWidth - PopupFrameSize)
  for line in message.splitLines():
    result.add(wrapLine(line, contentMaxWidth))

proc wrappedRowCount*(mgr: NotificationPopupManager, message: string): int =
  ## How many rows `message` takes up in a popup once wrapped.
  mgr.wrapMessage(message).len

proc addNotification*(
    mgr: NotificationPopupManager, message: string, level: NotificationLevel = nlInfo
) =
  if message.len == 0:
    return

  let wrappedLines = mgr.wrapMessage(message)

  var item = NotificationItem(
    message: message, level: level, createdAt: getMonoTime(), lines: wrappedLines
  )

  mgr.queue.add(item)

  # Cap queue size
  while mgr.queue.len > MaxQueueSize:
    mgr.queue.delete(0)

proc tick*(mgr: NotificationPopupManager) =
  let now = getMonoTime()
  let timeout = initDuration(milliseconds = mgr.timeoutMs)
  var i = 0
  while i < mgr.queue.len:
    if now - mgr.queue[i].createdAt >= timeout:
      mgr.queue.delete(i)
    else:
      inc i

proc hasActiveNotifications*(mgr: NotificationPopupManager): bool =
  mgr.queue.len > 0

proc getContentStyle*(level: NotificationLevel): Style =
  case level
  of nlInfo:
    notificationInfoStyle()
  of nlWarning:
    notificationWarningStyle()
  of nlError:
    notificationErrorStyle()

proc getBorderStyle*(level: NotificationLevel): Style =
  case level
  of nlInfo:
    notificationInfoBorderStyle()
  of nlWarning:
    notificationWarningBorderStyle()
  of nlError:
    notificationErrorBorderStyle()

type NotificationRect* = object
  item*: NotificationItem
  x*, y*, width*, height*: int
  showBorder*: bool

proc calculateNotificationPositions*(
    mgr: NotificationPopupManager, termWidth, termHeight: int, bottomReserve: int = 0
): seq[NotificationRect] =
  ## Calculate positions for visible notifications.
  ## `bottomReserve` is the number of rows reserved at the bottom
  ## (e.g. status line + command line).
  if mgr.queue.len == 0:
    return @[]

  let visibleCount = min(mgr.queue.len, mgr.maxVisible)
  # Show newest notifications (end of queue)
  let startIdx = mgr.queue.len - visibleCount

  result = @[]
  var stackOffset = 0

  for i in countdown(mgr.queue.len - 1, startIdx):
    let item = mgr.queue[i]

    let corner =
      case mgr.position
      of nppBottomRight: pcBottomRight
      of nppBottomLeft: pcBottomLeft
      of nppTopRight: pcTopRight
      of nppTopLeft: pcTopLeft
    # Bottom corners want a single-row padding gap above the reserved area;
    # fold it into bottomReserve so placeCorner can stay generic.
    let effectiveReserve =
      case mgr.position
      of nppBottomRight, nppBottomLeft:
        bottomReserve + 1
      of nppTopRight, nppTopLeft:
        0

    # A popup taller than the rows left to it would cover the editor. A top
    # corner ignores the reserved rows when placing, but not when sizing.
    let
      heightReserve = max(effectiveReserve, bottomReserve)
      available = termHeight - heightReserve - stackOffset

    # On a short screen the border is dropped first, since it can be what
    # leaves no room for the message.
    var
      showBorder = mgr.showBorder
      borderSize = if mgr.showBorder: 2 else: 0
    if available < borderSize + 1:
      showBorder = false
      borderSize = 0

    # A popup with no rows left would be pinned to the screen edge on top of
    # the ones already placed, so it is left to the message log. Later entries
    # are older and stacked further, so none of them fit either.
    if available < 1:
      break

    let
      popupHeight = min(item.lines.len + borderSize, available)
      shownLines = popupHeight - borderSize
      # The last row of a clamped popup goes to the marker, not to content.
      isClamped = shownLines < item.lines.len

    # Width comes from the rows drawn, not the ones the item holds: sizing to a
    # line the clamp drops leaves a band of empty background across the editor.
    var maxLineWidth = 0
    for j in 0 ..< (if isClamped: shownLines - 1 else: shownLines):
      maxLineWidth = max(maxLineWidth, item.lines[j].displayWidth)
    if isClamped:
      maxLineWidth = max(maxLineWidth, ClampedRowsMarker.displayWidth)

    # When border is off, add left and right space margins.
    let margin = if showBorder: 0 else: 2
    # Clamp outer width so popup never exceeds `maxWidth` on screen.
    let popupWidth = min(maxLineWidth + borderSize + margin, mgr.maxWidth)

    let rect = placeCorner(
      corner,
      popupWidth,
      popupHeight,
      initScreen(termWidth, termHeight, effectiveReserve),
      stackOffset = stackOffset,
    )

    result.add(
      NotificationRect(
        item: item,
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
        showBorder: showBorder,
      )
    )

    stackOffset += popupHeight + 1 # +1 for gap between popups

proc renderNotificationPopup*(termBuffer: var Buffer, rect: NotificationRect) =
  let item = rect.item
  let pos = rect
  let contentStyle = getContentStyle(item.level)
  let borderStyle = getBorderStyle(item.level)

  let borderOffset = if pos.showBorder: 1 else: 0
  let margin = if pos.showBorder: 0 else: 1
  let contentX = pos.x + borderOffset + margin
  let contentY = pos.y + borderOffset
  let contentWidth = pos.width - borderOffset * 2 - margin * 2

  # Top border
  if pos.showBorder and pos.y >= 0 and pos.y < termBuffer.area.height:
    if pos.x >= 0 and pos.x < termBuffer.area.width:
      termBuffer[pos.x, pos.y] = cell("┌", borderStyle)
    for x in pos.x + 1 ..< min(pos.x + pos.width - 1, termBuffer.area.width):
      if x >= 0:
        termBuffer[x, pos.y] = cell("─", borderStyle)
    if pos.x + pos.width - 1 >= 0 and pos.x + pos.width - 1 < termBuffer.area.width:
      termBuffer[pos.x + pos.width - 1, pos.y] = cell("┐", borderStyle)

  # Content lines. The rect is what fits on screen; the item may hold more.
  let shownLines = max(0, min(item.lines.len, pos.height - borderOffset * 2))
  # A clamp can drop the line saying the report was shortened, so the last row
  # drawn says so itself.
  let marker =
    if ClampedRowsMarker.displayWidth <= contentWidth: ClampedRowsMarker else: "..."
  let ellipsisRow =
    if shownLines < item.lines.len:
      shownLines - 1
    else:
      -1
  for i in 0 ..< shownLines:
    let lineY = contentY + i
    if lineY < 0 or lineY >= termBuffer.area.height:
      continue

    let lineText =
      if i == ellipsisRow:
        marker
      else:
        item.lines[i]

    # Left border or space margin
    if pos.x >= 0 and pos.x < termBuffer.area.width:
      if pos.showBorder:
        termBuffer[pos.x, lineY] = cell("│", borderStyle)
      else:
        termBuffer[pos.x, lineY] = cell(" ", contentStyle)

    # Content
    var x = contentX
    for r in lineText.runes:
      if x >= contentX + contentWidth or x >= termBuffer.area.width:
        break
      if x >= 0:
        x += setRuneCell(termBuffer, x, lineY, r, contentStyle)
      else:
        x += runeWidth(r)

    # Fill remaining space with background
    while x < contentX + contentWidth and x < termBuffer.area.width:
      if x >= 0:
        termBuffer[x, lineY] = cell(" ", contentStyle)
      inc x

    # Right border / margin
    if pos.x + pos.width - 1 >= 0 and pos.x + pos.width - 1 < termBuffer.area.width:
      if pos.showBorder:
        termBuffer[pos.x + pos.width - 1, lineY] = cell("│", borderStyle)
      else:
        termBuffer[pos.x + pos.width - 1, lineY] = cell(" ", contentStyle)

  # Bottom border
  if pos.showBorder:
    let bottomY = contentY + shownLines
    if bottomY >= 0 and bottomY < termBuffer.area.height:
      if pos.x >= 0 and pos.x < termBuffer.area.width:
        termBuffer[pos.x, bottomY] = cell("└", borderStyle)
      for x in pos.x + 1 ..< min(pos.x + pos.width - 1, termBuffer.area.width):
        if x >= 0:
          termBuffer[x, bottomY] = cell("─", borderStyle)
      if pos.x + pos.width - 1 >= 0 and pos.x + pos.width - 1 < termBuffer.area.width:
        termBuffer[pos.x + pos.width - 1, bottomY] = cell("┘", borderStyle)
