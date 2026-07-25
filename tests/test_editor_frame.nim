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

## Tests for editor_frame.nim

import std/unittest

import ../src/moepkg/[types, editor, config, message_log]
import ../src/moepkg/editor_frame

suite "notify - routing and logging":
  test "status line route sets the status message":
    let config = newEditorConfig()
    let e = newEditor(config)
    e.config.notification.popupNotifications = false
    clearMessageLog()

    e.notify("hello")

    check e.state.statusMessage == "hello"
    check e.state.notificationPopup.queue.len == 0

  test "popup route queues the message with its level":
    let config = newEditorConfig()
    let e = newEditor(config)
    e.config.notification.popupNotifications = true
    e.state.setStatusQuiet("")
    clearMessageLog()

    e.notify("Build error: boom", nlError)

    check e.state.notificationPopup.queue.len == 1
    check e.state.notificationPopup.queue[0].message == "Build error: boom"
    check e.state.notificationPopup.queue[0].level == nlError
    check e.state.statusMessage.len == 0

  test "both routes record to the message log":
    # What the log holds must not depend on a display preference: with popups
    # on, the status-line setter (which logs) is bypassed.
    for popups in [false, true]:
      let config = newEditorConfig()
      let e = newEditor(config)
      e.config.notification.popupNotifications = popups
      clearMessageLog()

      e.notify("QuickRun error: boom", nlError)

      check getMessageLog().len == 1
      check getMessageLog()[0] == "QuickRun error: boom"

  test "empty message is not logged":
    let config = newEditorConfig()
    let e = newEditor(config)
    e.config.notification.popupNotifications = false
    clearMessageLog()

    e.notify("")

    check getMessageLog().len == 0
