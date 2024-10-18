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

let Timeout = 1000.milliseconds

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

  while true:
    let buf =
      try:
        let f = s.readLine
        if waitFor f.withTimeout(Timeout):
          f.value
        else:
          return ReadFrameResult.err fmt"readLine: timeout"
      except CatchableError as e:
        return ReadFrameResult.err fmt"readLine failed: {e.msg}"

    if buf.len == 0:
      return ReadFrameResult.err fmt"readLine: empty"

    debugLog(MessageType.read, fmt"readLine: {buf}")

    var header: Option[tuple[ln: string, sep: int]]
    for ln in buf.splitLines:
      if ln.startsWith("Content-"):
        let sep = ln.find(':')
        if sep > -1:
          header = some((ln, sep))
          break

    if header.isNone:
      # Skip line if not JSON-RPC.
      continue

    let valueStart = header.get.ln.skipWhitespace(header.get.sep + 1)

    var contentLen = -1
    case header.get.ln[0 ..< header.get.sep]
      of "Content-Type":
        if isInvalidContentType(header.get.ln, valueStart):
          return ReadFrameResult.err "Only utf-8 is supported"
      of "Content-Length":
        if parseInt(header.get.ln, contentLen, valueStart) == 0:
          return
            ReadFrameResult.err fmt"Invalid Content-Length: {header.get.ln.substr(valueStart)}"
      else:
        # Unrecognized headers are ignored
        continue

    if contentLen != -1:
      let buf=
        try:
          let f = s.read(contentLen + 1)
          if waitFor f.withTimeout(Timeout):
            string.fromBytes(f.value)
          else:
            return ReadFrameResult.err fmt"readStr failed"
        except:
          return ReadFrameResult.err fmt"readStr failed"
      debugLog(MessageType.read, fmt"Response: {buf}")
      return ReadFrameResult.ok buf
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
      if not waitFor s.write(req).withTimeout(Timeout):
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
