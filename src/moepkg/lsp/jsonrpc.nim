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

import std/[streams, strformat, strutils, json, parseutils, options, logging,
            times, os]
import pkg/results
import ../messagelog

type
  ReadFrameResult = Result[string, string]
  JsonRpcResponseResult* = Result[JsonNode, string]

  MessageType = enum
    read
    write

  Streams* = object
    input*, output*: Stream

proc skipWhitespace(x: string, pos: int): int =
  result = pos
  while result < x.len and x[result] in Whitespace:
    inc result

proc isInvalidContentType(s: string, valueStart: int): bool {.inline.} =
  s.find("utf-8", valueStart) == -1 and s.find("utf8", valueStart) == -1

proc isValidJsonRpc(json: JsonNode): bool {.inline.} =
  json.contains("jsonrpc")

proc debugLog(messageType: MessageType, message: string) =
  let debugMessage =
    case messageType:
      of read:
        "lsp: Read messages: \n" & message & '\n'
      of write:
        "lsp: Write messages: \n" & message & '\n'

  debug debugMessage
  addMessageLog debugMessage

proc readLine(s: Stream, timeout: int): Result[string, string] =
  ## readLine with timeout.

  let
    d = initDuration(milliseconds = timeout)
    n = now()
  while now() - n < d:
    try:
      if not s.atEnd():
        return Result[string, string].ok s.readLine
    except CatchableError as e:
      return Result[string, string].err e.msg

    sleep 100

  return Result[string, string].err "timeout"

proc readFrame(s: Stream): ReadFrameResult =
  ## Read text from the stream and return json node.

  var
    contentLen = -1
    headerStarted = false

  while true:
    const Timeout = 1000
    var ln = s.readLine(Timeout)
    if ln.isErr:
      debugLog(MessageType.read, "readLine Error!: " & ln.error)
      return ReadFrameResult.err ln.error

    if ln.get.len != 0:
      debugLog(MessageType.read, fmt"readLine: {ln.get}")

      let sep = ln.get.find(':')
      if sep == -1:
        # Skip line if not json.
        continue

      headerStarted = true

      let valueStart = ln.get.skipWhitespace(sep + 1)

      case ln.get[0 ..< sep]
        of "Content-Type":
          if isInvalidContentType(ln.get, valueStart):
            return ReadFrameResult.err "Only utf-8 is supported"
        of "Content-Length":
          if parseInt(ln.get, contentLen, valueStart) == 0:
            return ReadFrameResult.err fmt"Invalid Content-Length: {ln.get.substr(valueStart)}"
        else:
          # Unrecognized headers are ignored
          discard
    elif not headerStarted:
      continue
    else:
      if contentLen != -1:
        let response = s.readStr(contentLen)
        debugLog(MessageType.read, "Response: {response}")
        return ReadFrameResult.ok response
      else:
        return ReadFrameResult.err "Missing Content-Length header"

proc read*(s: Stream): JsonRpcResponseResult =
  ## Return a json-rpc response from the stream.

  let r = s.readFrame
  if r.isErr:
    return JsonRpcResponseResult.err r.error

  var res: JsonNode
  try:
    res = r.get.parseJson
  except CatchableError as e:
    return JsonRpcResponseResult.err e.msg

  if res.isValidJsonRpc:
    return JsonRpcResponseResult.ok res
  else:
    return JsonRpcResponseResult.err fmt"Invalid jsonrpc: {$res}"

proc send(s: Stream, frame: string): Result[(), string] =
  ## Write json-rpc message to the stream.

  let req = "Content-Length: " & $frame.len & "\r\n\r\n" & frame

  debugLog(MessageType.write, req)

  try:
    s.write req
    s.flush
  except CatchableError as e:
    return Result[(), string].err e.msg

  return Result[(), string].ok ()

proc newReqest(id: int, methodName: string, params: JsonNode): string =
  result = newStringOfCap(1024)
  let req = %* {
    "jsonrpc": "2.0",
    "id": id,
    "method": methodName,
    "params": params
  }
  result.toUgly(req)

proc sendRequest*(
  s: Streams,
  id: int,
  methodName: string,
  params: JsonNode): JsonRpcResponseResult =
    ## Send a request and return a response.

    let req = newReqest(id, methodName, params)

    let err = s.input.send(req)
    if err.isErr:
      return JsonRpcResponseResult.err err.error

    let res = s.output.read
    if res.isOk:
      return JsonRpcResponseResult.ok res.get
    else:
      return JsonRpcResponseResult.err res.error

proc newNotify(methodName: string, params: JsonNode): string =
  result = newStringOfCap(1024)
  let req = %* {
    "jsonrpc": "2.0",
    "method": methodName,
    "params": params
  }
  result.toUgly(req)

proc sendNotify*(
  s: Streams,
  methodName: string,
  params: JsonNode): Result[(), string] =
    ## Send a notification.
    ## No response to the notification. Also, no `id` is required in the request.

    let notify = newNotify(methodName, params)
    return s.input.send(notify)
