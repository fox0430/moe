#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import std/[json, options]

import pkg/results

type
  LspMessageType* = enum
    error
    warn
    info
    log
    debug

  ServerMessage* = object
    messageType*: LspMessageType
    message*: string

  parseLspMessageTypeResult* = Result[LspMessageType, string]
  LspWindowShowMessageResult* = Result[ServerMessage, string]
  LspWindowLogMessageResult* = Result[ServerMessage, string]

proc parseLspMessageType*(num: int): parseLspMessageTypeResult =
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#messageType

  case num:
    of 1: parseLspMessageTypeResult.ok LspMessageType.error
    of 2: parseLspMessageTypeResult.ok LspMessageType.warn
    of 3: parseLspMessageTypeResult.ok LspMessageType.info
    of 4: parseLspMessageTypeResult.ok LspMessageType.log
    of 5: parseLspMessageTypeResult.ok LspMessageType.debug
    else: parseLspMessageTypeResult.err "Invalid value"

proc parseWindowShowMessageNotify*(n: JsonNode): LspWindowShowMessageResult =
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#window_showMessageRequest

  # TODO: Add "ShowMessageRequestParams.actions" support.
  if n.contains("params") and
     n["params"].contains("type") and n["params"]["type"].kind == JInt and
     n["params"].contains("message") and n["params"]["message"].kind == JString:
       let messageType = n["params"]["type"].getInt.parseLspMessageType
       if messageType.isErr:
         return LspWindowShowMessageResult.err messageType.error

       return LspWindowShowMessageResult.ok ServerMessage(
         messageType: messageType.get,
         message: n["params"]["message"].getStr)

  return LspWindowShowMessageResult.err "Invalid notify"

proc parseWindowLogMessageNotify*(n: JsonNode): LspWindowLogMessageResult =
  ## https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#window_logMessage

  if n.contains("params") and
     n["params"].contains("type") and n["params"]["type"].kind == JInt and
     n["params"].contains("message") and n["params"]["message"].kind == JString:
       let messageType = n["params"]["type"].getInt.parseLspMessageType
       if messageType.isErr:
         return LspWindowLogMessageResult.err messageType.error

       return LspWindowLogMessageResult.ok ServerMessage(
         messageType: messageType.get,
         message: n["params"]["message"].getStr)

  return LspWindowLogMessageResult.err "Invalid notify"
