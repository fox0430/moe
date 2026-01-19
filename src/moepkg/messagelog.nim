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

## Message log for editor messages displayed on the command line.
## These messages are stored for later viewing in the log viewer.

var messageLog {.threadvar.}: seq[string]
var lspMessageLog {.threadvar.}: seq[string]

proc addMessageLog*(message: string) =
  ## Add a message to the log.
  messageLog.add(message)

proc addMessageLog*(messages: seq[string]) =
  ## Add multiple messages to the log.
  for m in messages:
    messageLog.add(m)

proc getMessageLog*(): seq[string] =
  ## Return all messages in the log.
  messageLog

proc clearMessageLog*() =
  ## Clear all messages from the log.
  messageLog = @[]

proc messageLogLen*(): int =
  ## Returns the number of messages in the log.
  messageLog.len

# LSP message log functions

proc addLspMessageLog*(message: string) =
  ## Add a message to the LSP log.
  lspMessageLog.add(message)

proc addLspMessageLog*(messages: seq[string]) =
  ## Add multiple messages to the LSP log.
  for m in messages:
    lspMessageLog.add(m)

proc getLspMessageLog*(): seq[string] =
  ## Return all messages in the LSP log.
  lspMessageLog

proc clearLspMessageLog*() =
  ## Clear all messages from the LSP log.
  lspMessageLog = @[]

proc lspMessageLogLen*(): int =
  ## Returns the number of messages in the LSP log.
  lspMessageLog.len
