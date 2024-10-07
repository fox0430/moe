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

import std/[strformat, strutils, json, parseutils, options, logging]

import pkg/stew/byteutils
import pkg/[results, jsony, chronos]

import ../messagelog

type
  ReadFrameResult = Result[string, string]
  JsonRpcResponseResult* = Result[JsonNode, string]
  JsonRpcSendResult* = Result[(), string]

  MessageType = enum
    read
    write

  FileHandles* = object
    input*, output*: FileHandle

  InputStream* = ref object
    stream*: AsyncStreamWriter

  OutputStream* = ref object
    stream*: AsyncStreamReader

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

proc readFrame(s: AsyncStreamReader): ReadFrameResult =
  ## Read text from the stream and return json node.

  var
    contentLen = -1
    headerStarted = false

  while true:
    let ln =
      try:
        let
          f = s.readLine(sep="\n")
          r = waitFor f.withTimeout(10.milliseconds)
        if not r: ""
        else: f.value
      except CatchableError as e:
        return ReadFrameResult.err fmt"readLine failed: {e.msg}"

    if ln.len == 0:
      return ReadFrameResult.err fmt"readLine: timeout"

    debugLog(MessageType.read, fmt"readLine: {ln}")

    let sep = ln.find(':')
    if sep == -1:
      # Skip line if not JSON-RPC.
      continue

    headerStarted = true

    let valueStart = ln.skipWhitespace(sep + 1)

    case ln[0 ..< sep]
      of "Content-Type":
        if isInvalidContentType(ln, valueStart):
          return ReadFrameResult.err "Only utf-8 is supported"
      of "Content-Length":
        if parseInt(ln, contentLen, valueStart) == 0:
          return ReadFrameResult.err fmt"Invalid Content-Length: {ln.substr(valueStart)}"
      else:
        # Unrecognized headers are ignored
        discard

    if not headerStarted:
      continue
    else:
      if contentLen != -1:
        let bytes =
          try:
            block removeCr:
              let f = s.read(1)
              discard waitFor f.withTimeout(10.milliseconds)
            let
              f = s.read(contentLen)
              r = waitFor f.withTimeout(10.milliseconds)
            if not r: @[]
            else: f.value
          except:
            return ReadFrameResult.err fmt"readStr failed"
        let str = string.fromBytes(bytes)
        debugLog(MessageType.read, fmt"Response: {str}")
        return ReadFrameResult.ok str
      else:
        return ReadFrameResult.err "Missing Content-Length header"

proc read*(s: AsyncStreamReader): JsonRpcResponseResult =
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

proc send(
  s: AsyncStreamWriter,
  frame: string): Result[(), string] =
    ## Write json-rpc message to the stream.

    let req = "Content-Length: " & $frame.len & "\r\n\r\n" & frame

    debugLog(MessageType.write, req)

    try:
      if not waitFor s.write(req).withTimeout(100.milliseconds):
        return Result[(), string].err "write: Timeout"
    except CatchableError as e:
      return Result[(), string].err e.msg

    return Result[(), string].ok ()

template newRequest*(id: int, methodName: string, params: JsonNode): JsonNode =
  %* {
    "jsonrpc": "2.0",
    "id": id,
    "method": methodName,
    "params": params
  }

proc sendRequest*(stream: AsyncStreamWriter, req: JsonNode): JsonRpcSendResult =
  ## Send a request and return a response.

  var s = newStringOfCap(1024)
  s.toUgly(req)
  let err = stream.send(s)
  if err.isErr:
    return JsonRpcSendResult.err err.error

  return JsonRpcSendResult.ok ()

template newNotify*(methodName: string, params: JsonNode): JsonNode =
  %* {
    "jsonrpc": "2.0",
    "method": methodName,
    "params": params
  }

proc sendNotify*(stream: AsyncStreamWriter, notify: JsonNode): Result[(), string] =
  ## Send a notification.
  ## No response to the notification. Also, no `id` is required in the
  ## request.

  var s = newStringOfCap(1024)
  s.toUgly(notify)
  return stream.send(s)
