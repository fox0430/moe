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

## Notification routing: popup or status line depending on config, plus the
## pending buffer notices, reported when a window first shows the buffer.

import std/[options, strutils]

import types/editor_types, logger, message_log, notification_popup, buffer

proc notifyPopup*(e: Editor, msg: string, level: NotificationLevel = nlInfo) =
  ## Notify via popup, always logged to message log.
  if msg.len == 0:
    return
  e.state.notificationPopup.addNotification(msg, level)
  addMessageLog(msg)

proc notify*(e: Editor, msg: string, level: NotificationLevel = nlInfo) =
  ## Notify via popup or status line based on config. Always logged.
  if e.config.notification.popupNotifications:
    e.notifyPopup(msg, level)
  else:
    e.state.statusMessage = msg

const MaxNotifiedLines* = 8
  ## Rows one report may spend on screen. The first message is always kept,
  ## however tall it is.

proc droppedLine(count: int): string =
  "... and " & $count & " more (:messages)"

proc boundedReport(
    msgs: openArray[string], rows: proc(s: string): int, maxRows = MaxNotifiedLines
): string =
  ## As much of `msgs` as fits in `maxRows` rows, with a last line naming what
  ## was left out. `rows` measures a message on its route (status line clips,
  ## popup wraps).
  var
    shown: seq[string]
    used = 0
  for i, msg in msgs:
    # Every message but the last must leave room for the "and N more" line.
    let budget =
      if i == msgs.len - 1:
        maxRows
      else:
        maxRows - rows(droppedLine(msgs.len - i))
    let cost = rows(msg)
    if shown.len > 0 and used + cost > budget:
      break
    shown.add msg
    used += cost

  if shown.len == msgs.len:
    return shown.join("\n")

  shown.add droppedLine(msgs.len - shown.len)
  shown.join("\n")

proc notifyAll*(e: Editor, msgs: openArray[string], level: NotificationLevel = nlInfo) =
  ## Notify about several things as one multi-line message; separate reports
  ## would overwrite each other. The log keeps them apart.
  if msgs.len == 0:
    return

  # Logged first and in full, so a line the screen drops is still readable.
  # Both paths below stay quiet to avoid logging the joined form on top.
  for msg in msgs:
    addMessageLog(msg)

  if e.config.notification.popupNotifications:
    let mgr = e.state.notificationPopup
    mgr.addNotification(
      msgs.boundedReport(
        proc(s: string): int =
          mgr.wrappedRowCount(s)
      ),
      level,
    )
  else:
    # A report taller than the screen would lose its head, since the status
    # line area grows upward and the renderer keeps its last rows. Height 0
    # means nothing has been rendered yet.
    let screenRows =
      if e.screenSize.height > 0:
        max(1, e.screenSize.height - 1)
      else:
        MaxNotifiedLines
    e.state.setStatusQuiet(
      msgs.boundedReport(
        proc(s: string): int =
          s.count('\n') + 1,
        maxRows = min(MaxNotifiedLines, screenRows),
      )
    )

proc render(buf: TextBuffer, notice: BufferNotice): string =
  ## The sentence for a notice, kept apart from where the notice is made.
  let where = buf.filePath.get("(unnamed)")
  case notice.kind
  of bnContent:
    let isRaw = notice.content in {ucRaw, ucRawBinary}
    let what =
      if not isRaw:
        "binary content (NUL bytes)"
      elif notice.content == ucRawBinary:
        "undecodable bytes and NUL bytes"
      else:
        "undecodable bytes"
    let fate =
      if isRaw: "held raw and saved back unchanged" else: "bytes are preserved on save"
    where & ": " & what & "; " & fate
  of bnSetting:
    where & ": " & notice.issue.toMessage

proc drainNotices*(e: Editor, bufs: openArray[TextBuffer]) =
  ## Report and clear the pending notices of `bufs` as one report, so that two
  ## buffers coming into view together do not overwrite each other.
  var msgs: seq[string]
  for buf in bufs:
    for notice in buf.takeNotices:
      let msg = buf.render(notice)
      logWarn("buffer", msg)
      msgs.add msg
  e.notifyAll(msgs, nlWarning)
