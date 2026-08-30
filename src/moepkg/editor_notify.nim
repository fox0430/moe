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
## announcements that every file-open path shares.

import types/editor_types, message_log, notification_popup

proc notifyPopup*(e: Editor, msg: string, level: NotificationLevel = nlInfo) =
  ## Notify via popup, always logged to message log.
  e.state.notificationPopup.addNotification(msg, level)
  addMessageLog(msg)

proc notify*(e: Editor, msg: string, level: NotificationLevel = nlInfo) =
  ## Notify via popup or status line based on config. Always logged.
  if e.config.notification.popupNotifications:
    e.notifyPopup(msg, level)
  else:
    e.state.statusMessage = msg
    addMessageLog(msg)
