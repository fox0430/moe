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

## Tests for notification popup functionality

import std/[unittest, monotimes, times]

import pkg/celina

import ../src/moepkg/notification_popup {.all.}
import ../src/moepkg/color {.all.}
import ../src/moepkg/theme {.all.}

# Initialize theme colors for tests
setThemeColors(DefaultColors)

suite "NotificationPopup - newNotificationPopupManager":
  test "Creates manager with defaults":
    let mgr = newNotificationPopupManager()

    check mgr.queue.len == 0
    check mgr.maxVisible == DefaultMaxVisible
    check mgr.timeoutMs == DefaultTimeoutMs
    check mgr.position == nppBottomRight
    check mgr.maxWidth == DefaultMaxWidth

suite "NotificationPopup - addNotification":
  test "Add single notification":
    let mgr = newNotificationPopupManager()
    mgr.addNotification("Test message")

    check mgr.queue.len == 1
    check mgr.queue[0].message == "Test message"
    check mgr.queue[0].level == nlInfo
    check mgr.queue[0].lines == @["Test message"]

  test "Add notification with level":
    let mgr = newNotificationPopupManager()
    mgr.addNotification("Error!", nlError)

    check mgr.queue.len == 1
    check mgr.queue[0].level == nlError

  test "Add multi-line notification":
    let mgr = newNotificationPopupManager()
    mgr.addNotification("Line 1\nLine 2\nLine 3")

    check mgr.queue.len == 1
    check mgr.queue[0].lines.len == 3
    check mgr.queue[0].lines[0] == "Line 1"
    check mgr.queue[0].lines[1] == "Line 2"
    check mgr.queue[0].lines[2] == "Line 3"

  test "Long message is wrapped":
    let mgr = newNotificationPopupManager()
    mgr.maxWidth = 20
    mgr.addNotification("This is a long message that should be wrapped")

    check mgr.queue.len == 1
    check mgr.queue[0].lines.len > 1
    for line in mgr.queue[0].lines:
      check line.runeLen <= 20

  test "Empty message is ignored":
    let mgr = newNotificationPopupManager()
    mgr.addNotification("")

    check mgr.queue.len == 0

  test "Queue caps at MaxQueueSize":
    let mgr = newNotificationPopupManager()
    for i in 0 ..< MaxQueueSize + 5:
      mgr.addNotification("Message " & $i)

    check mgr.queue.len == MaxQueueSize
    # Oldest messages should be removed
    check mgr.queue[0].message == "Message 5"

suite "NotificationPopup - tick":
  test "Removes expired notifications":
    let mgr = newNotificationPopupManager()
    mgr.timeoutMs = 100 # 100ms timeout

    # Add a notification with a past creation time
    var item = NotificationItem(
      message: "Old",
      level: nlInfo,
      createdAt: getMonoTime() - initDuration(milliseconds = 200),
      lines: @["Old"],
    )
    mgr.queue.add(item)

    mgr.tick()
    check mgr.queue.len == 0

  test "Keeps non-expired notifications":
    let mgr = newNotificationPopupManager()
    mgr.timeoutMs = 5000

    mgr.addNotification("Recent")

    mgr.tick()
    check mgr.queue.len == 1

  test "Mixed expired and non-expired":
    let mgr = newNotificationPopupManager()
    mgr.timeoutMs = 100

    # Add expired notification
    var oldItem = NotificationItem(
      message: "Old",
      level: nlInfo,
      createdAt: getMonoTime() - initDuration(milliseconds = 200),
      lines: @["Old"],
    )
    mgr.queue.add(oldItem)

    # Add fresh notification
    mgr.addNotification("Fresh")

    mgr.tick()
    check mgr.queue.len == 1
    check mgr.queue[0].message == "Fresh"

suite "NotificationPopup - hasActiveNotifications":
  test "Returns false when empty":
    let mgr = newNotificationPopupManager()
    check mgr.hasActiveNotifications() == false

  test "Returns true when has notifications":
    let mgr = newNotificationPopupManager()
    mgr.addNotification("Test")
    check mgr.hasActiveNotifications() == true

suite "NotificationPopup - calculateNotificationPositions":
  test "Empty queue returns empty positions":
    let mgr = newNotificationPopupManager()
    let rects = mgr.calculateNotificationPositions(80, 24)
    check rects.len == 0

  test "Single notification bottom-right":
    let mgr = newNotificationPopupManager()
    mgr.position = nppBottomRight
    mgr.addNotification("Hello")

    let rects = mgr.calculateNotificationPositions(80, 24, bottomReserve = 2)
    check rects.len == 1
    # Should be positioned at bottom-right, above status line
    check rects[0].x + rects[0].width <= 80
    check rects[0].y + rects[0].height <= 24 - 2

  test "Bottom-right with bottomReserve for status line":
    let mgr = newNotificationPopupManager()
    mgr.position = nppBottomRight
    mgr.addNotification("Hello")

    # Without status line: bottomReserve=1 (command line only)
    let withoutStatus = mgr.calculateNotificationPositions(80, 24, bottomReserve = 1)
    # With status line: bottomReserve=2 (status line + command line)
    let withStatus = mgr.calculateNotificationPositions(80, 24, bottomReserve = 2)
    check withoutStatus.len == 1
    check withStatus.len == 1
    # With status line, popup should be 1 row higher
    check withStatus[0].y == withoutStatus[0].y - 1
    # Popup should not overlap the reserved area
    check withStatus[0].y + withStatus[0].height <= 24 - 2

  test "Single notification top-right":
    let mgr = newNotificationPopupManager()
    mgr.position = nppTopRight
    mgr.addNotification("Hello")

    let rects = mgr.calculateNotificationPositions(80, 24)
    check rects.len == 1
    check rects[0].y == 0 # Top position

  test "Single notification bottom-left":
    let mgr = newNotificationPopupManager()
    mgr.position = nppBottomLeft
    mgr.addNotification("Hello")

    let rects = mgr.calculateNotificationPositions(80, 24, bottomReserve = 2)
    check rects.len == 1
    check rects[0].x == 0 # Left position
    check rects[0].y + rects[0].height <= 24 - 2

  test "Single notification top-left":
    let mgr = newNotificationPopupManager()
    mgr.position = nppTopLeft
    mgr.addNotification("Hello")

    let rects = mgr.calculateNotificationPositions(80, 24)
    check rects.len == 1
    check rects[0].x == 0
    check rects[0].y == 0

  test "Without border has space margins (left and right)":
    let withBorder = newNotificationPopupManager()
    withBorder.showBorder = true
    withBorder.addNotification("Hello")

    let withoutBorder = newNotificationPopupManager()
    withoutBorder.showBorder = false
    withoutBorder.addNotification("Hello")

    let rectsB = withBorder.calculateNotificationPositions(80, 24)
    let rectsNB = withoutBorder.calculateNotificationPositions(80, 24)
    check rectsB.len == 1
    check rectsNB.len == 1
    # Same width (border +2 vs margin +2)
    check rectsNB[0].width == rectsB[0].width
    # No top/bottom margin
    check rectsNB[0].height == rectsB[0].height - 2

  test "Stacked without border has gap":
    let mgr = newNotificationPopupManager()
    mgr.showBorder = false
    mgr.position = nppBottomRight
    mgr.addNotification("First")
    mgr.addNotification("Second")

    let rects = mgr.calculateNotificationPositions(80, 24, bottomReserve = 2)
    check rects.len == 2
    # Newest should be lower (closer to corner)
    check rects[0].y > rects[1].y
    # 1-row gap between popups
    check rects[1].y + rects[1].height < rects[0].y

  test "Respects maxVisible":
    let mgr = newNotificationPopupManager()
    mgr.maxVisible = 2
    for i in 0 ..< 5:
      mgr.addNotification("Message " & $i)

    let rects = mgr.calculateNotificationPositions(80, 24)
    check rects.len == 2

  test "Notifications are stacked with gap":
    let mgr = newNotificationPopupManager()
    mgr.position = nppBottomRight
    mgr.addNotification("First")
    mgr.addNotification("Second")

    let rects = mgr.calculateNotificationPositions(80, 24, bottomReserve = 2)
    check rects.len == 2
    # Newest should be lower (closer to corner)
    check rects[0].y > rects[1].y
    # 1-row gap between popups
    check rects[1].y + rects[1].height < rects[0].y
    # All popups should be above status line
    for r in rects:
      check r.y + r.height <= 24 - 2

suite "NotificationPopup - getContentStyle":
  test "Info level returns info style":
    let style = getContentStyle(nlInfo)
    check style == notificationInfoStyle()

  test "Warning level returns warning style":
    let style = getContentStyle(nlWarning)
    check style == notificationWarningStyle()

  test "Error level returns error style":
    let style = getContentStyle(nlError)
    check style == notificationErrorStyle()

suite "NotificationPopup - getBorderStyle":
  test "Info level returns info border style":
    let style = getBorderStyle(nlInfo)
    check style == notificationInfoBorderStyle()

  test "Warning level returns warning border style":
    let style = getBorderStyle(nlWarning)
    check style == notificationWarningBorderStyle()

  test "Error level returns error border style":
    let style = getBorderStyle(nlError)
    check style == notificationErrorBorderStyle()

suite "NotificationPopup - renderNotificationPopup":
  test "Render single-line notification with border":
    var buf = newBuffer(80, 24)
    let mgr = newNotificationPopupManager()
    mgr.showBorder = true
    mgr.addNotification("Test")

    let rects = mgr.calculateNotificationPositions(80, 24)
    check rects.len == 1

    renderNotificationPopup(buf, rects[0])
    # Verify border corners are rendered
    let r = rects[0]
    check buf[r.x, r.y].symbol == "┌"
    check buf[r.x + r.width - 1, r.y].symbol == "┐"
    check buf[r.x, r.y + r.height - 1].symbol == "└"
    check buf[r.x + r.width - 1, r.y + r.height - 1].symbol == "┘"

  test "Render single-line notification without border":
    var buf = newBuffer(80, 24)
    let mgr = newNotificationPopupManager()
    mgr.showBorder = false
    mgr.addNotification("Test")

    let rects = mgr.calculateNotificationPositions(80, 24)
    check rects.len == 1

    renderNotificationPopup(buf, rects[0])
    let r = rects[0]
    # No top/bottom margin, height is content only
    check r.height == 1
    # Left space margin
    check buf[r.x, r.y].symbol == " "
    # Content starts at r.x + 1
    check buf[r.x + 1, r.y].symbol == "T"
    # Right space margin
    check buf[r.x + r.width - 1, r.y].symbol == " "

  test "Render notification with warning level":
    var buf = newBuffer(80, 24)
    let mgr = newNotificationPopupManager()
    mgr.showBorder = true
    mgr.addNotification("Warning!", nlWarning)

    let rects = mgr.calculateNotificationPositions(80, 24)
    renderNotificationPopup(buf, rects[0])

    let r = rects[0]
    # Border should use warning style (yellow)
    check buf[r.x, r.y].style == notificationWarningBorderStyle()
