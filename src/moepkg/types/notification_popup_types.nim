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

## Lightweight type definitions for the notification popup.
##
## Split out from `notification_popup` so modules that only need its manager
## type (notably `types` and its importers) do not transitively pull in the
## popup rendering procs.

import std/monotimes

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
