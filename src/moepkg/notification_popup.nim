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

import color

type
  NotificationLevel* = enum
    nlInfo
    nlWarning
    nlError

  NotificationItem* = object
    message*: string
    level*: NotificationLevel
    createdAt*: MonoTime
    lines*: seq[string]

  NotificationPopupPosition* = enum
    nppTopRight
    nppTopLeft
    nppBottomRight
    nppBottomLeft

  NotificationPopupManager* = ref object
    queue*: seq[NotificationItem]
    maxVisible*: int
    timeoutMs*: int
    position*: NotificationPopupPosition
    maxWidth*: int
    showBorder*: bool

const
  DefaultMaxVisible* = 3
  DefaultTimeoutMs*: int = 3000
  DefaultMaxWidth* = 60
  MaxQueueSize* = 10

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

proc addNotification*(
    mgr: NotificationPopupManager, message: string, level: NotificationLevel = nlInfo
) =
  if message.len == 0:
    return

  var wrappedLines: seq[string] = @[]
  for line in message.splitLines():
    wrappedLines.add(wrapLine(line, mgr.maxWidth))

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

    # Calculate popup width based on content
    var maxLineWidth = 0
    for line in item.lines:
      maxLineWidth = max(maxLineWidth, line.runeLen)
    let contentWidth = min(maxLineWidth, mgr.maxWidth)
    let borderSize = if mgr.showBorder: 2 else: 0
    # When border is off, add left and right space margins.
    let margin = if mgr.showBorder: 0 else: 2
    let popupWidth = contentWidth + borderSize + margin
    let popupHeight = item.lines.len + borderSize

    # Calculate position based on corner
    var x, y: int
    case mgr.position
    of nppBottomRight:
      x = termWidth - popupWidth
      y = termHeight - popupHeight - stackOffset - bottomReserve - 1
    of nppBottomLeft:
      x = 0
      y = termHeight - popupHeight - stackOffset - bottomReserve - 1
    of nppTopRight:
      x = termWidth - popupWidth
      y = stackOffset
    of nppTopLeft:
      x = 0
      y = stackOffset

    # Clamp to screen bounds
    x = max(0, x)
    y = max(0, y)

    result.add(
      NotificationRect(
        item: item,
        x: x,
        y: y,
        width: popupWidth,
        height: popupHeight,
        showBorder: mgr.showBorder,
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

  # Content lines
  for i in 0 ..< item.lines.len:
    let lineY = contentY + i
    if lineY < 0 or lineY >= termBuffer.area.height:
      continue

    let lineText = item.lines[i]

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
        termBuffer[x, lineY] = cell($r, contentStyle)
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
    let bottomY = contentY + item.lines.len
    if bottomY >= 0 and bottomY < termBuffer.area.height:
      if pos.x >= 0 and pos.x < termBuffer.area.width:
        termBuffer[pos.x, bottomY] = cell("└", borderStyle)
      for x in pos.x + 1 ..< min(pos.x + pos.width - 1, termBuffer.area.width):
        if x >= 0:
          termBuffer[x, bottomY] = cell("─", borderStyle)
      if pos.x + pos.width - 1 >= 0 and pos.x + pos.width - 1 < termBuffer.area.width:
        termBuffer[pos.x + pos.width - 1, bottomY] = cell("┘", borderStyle)
