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

import std/[strformat, strutils, json, parseutils, options, logging, streams]

import pkg/[results, jsony]

import ../messagelog

type
  ReadResult = Result[string, string]
  ReadFrameResult = Result[string, string]
  JsonRpcResponseResult* = Result[JsonNode, string]
  JsonRpcSendResult* = Result[(), string]

  MessageType = enum
    read
    write

  FileHandles* = object
    input*, output*: FileHandle

  InputStream* = ref object
    stream*: Stream

  OutputStream* = ref object
    stream*: Stream

  Streams* = ref object
    input*: InputStream
    output*: OutputStream

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

proc readStr(s: OutputStream, len: int): ReadResult =
  try:
    return ReadResult.ok s.stream.readStr(len)
  except CatchableError as e:
    return ReadResult.err e.msg

proc readLine(s: OutputStream): ReadResult =
  try:
    return ReadResult.ok s.stream.readLine
  except CatchableError as e:
    return ReadResult.err e.msg

proc readFrame(s: OutputStream): ReadFrameResult =
  ## Read text from the stream and return json node.

  var
    contentLen = -1
    headerStarted = false

  while true:
    let ln = s.readLine
    if ln.isErr:
      debug ln.error
      return ReadFrameResult.err fmt"readLine failed: {ln.error}"

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
        let str = s.readStr(contentLen)
        if str.isErr:
          return ReadFrameResult.err fmt"readStr failed: {str.error}"
        debugLog(MessageType.read, "Response: {str.get}")
        return ReadFrameResult.ok str.get
      else:
        return ReadFrameResult.err "Missing Content-Length header"

proc read*(s: OutputStream): JsonRpcResponseResult =
  ## Return a json-rpc response from the stream.

  let r = s.readFrame
  if r.isErr:
    return JsonRpcResponseResult.err r.error

  var res: JsonNode
  try:
    res = r.get.fromJson
  except CatchableError as e:
    return JsonRpcResponseResult.err e.msg

  if res.isValidJsonRpc:
    return JsonRpcResponseResult.ok res
  else:
    return JsonRpcResponseResult.err fmt"Invalid jsonrpc: {$res}"

proc write(s: InputStream, buffer: string) {.inline.} =
  s.stream.write(buffer)
  s.stream.flush

proc send(
  s: InputStream,
  frame: string): Result[(), string] =
    ## Write json-rpc message to the stream.

    let req = "Content-Length: " & $frame.len & "\r\n\r\n" & frame

    debugLog(MessageType.write, req)

    try:
      s.write req
    except CatchableError as e:
      return Result[(), string].err e.msg

    return Result[(), string].ok ()

template newReqest*(id: int, methodName: string, params: JsonNode): JsonNode =
  %* {
    "jsonrpc": "2.0",
    "id": id,
    "method": methodName,
    "params": params
  }

proc sendRequest*(streams: Streams, req: JsonNode): JsonRpcSendResult =
  ## Send a request and return a response.

  var s = newStringOfCap(1024)
  s.toUgly(req)
  let err = streams.input.send(s)
  if err.isErr:
    return JsonRpcSendResult.err err.error

  return JsonRpcSendResult.ok ()

template newNotify*(methodName: string, params: JsonNode): JsonNode =
  %* {
    "jsonrpc": "2.0",
    "method": methodName,
    "params": params
  }

proc sendNotify*(streams: Streams, notify: JsonNode): Result[(), string] =
  ## Send a notification.
  ## No response to the notification. Also, no `id` is required in the
  ## request.

  var s = newStringOfCap(1024)
  s.toUgly(notify)
  return streams.input.send(s)
