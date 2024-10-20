#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import unicodeext

## Log messages displayed on the command line.
var messageLog {.threadvar.}: seq[Runes]

proc addMessageLog*(message: Runes) =
  ## Add messages to `logger.messageLog`.

  messageLog.add message

proc addMessageLog*(messages: seq[Runes]) =
  ## Add messages to `logger.messageLog`.

  for l in messages: messageLog.add l

proc addMessageLog*(message: string) =
  ## Add messages to `logger.messageLog`.

  messageLog.add message.toRunes

proc getMessageLog*(): seq[Runes] =
  ## Return `logger.messageLog`.
  messageLog

proc clearMessageLog*() =
  ## Clear all message.
  messageLog = @[]

proc messageLogLen*(): int =
  ## Returns the number of lines in the log.

  messageLog.len
