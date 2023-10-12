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

import std/[strformat, strutils, json, parseutils, options, logging,
            asyncdispatch]
import pkg/results
import pkg/asynctools/asyncpipe
import ../messagelog

type
  ReadBufferResult = Result[string, string]
  ReadFrameResult = Result[string, string]
  JsonRpcResponseResult* = Result[JsonNode, string]

  MessageType = enum
    read
    write

  Pipes* = object
    input*, output*: AsyncPipe

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

proc readBuffer(output: AsyncPipe, timeout: int): ReadBufferResult =
  ## readBuffer with timeout.

  var
    buffer = newString(2048)
    res: Future[int]

  res = output.readInto(buffer[0].addr, buffer.len)

  waitFor res or sleepAsync(timeout)
  if res.finished:
    let len = waitFor res
    return Result[string, string].ok buffer[0 .. len - 1]
  else:
    return Result[string, string].err "timeout"

proc readFrame(output: AsyncPipe): ReadFrameResult =
  ## Read text from the stream and return json node.

  const Timeout = 3000
  let buffer = output.readBuffer(Timeout)
  if buffer.isErr:
    debugLog(MessageType.read, "readLine Error!: " & buffer.error)
    return ReadFrameResult.err buffer.error

  debugLog(MessageType.read, fmt"readFrame: {buffer.get}")

  let lines = buffer.get.splitLines

  var
    currentLine = 0
    contentLen = -1
    headerStarted = false

  while currentLine < lines.len:
    if lines[currentLine].len != 0:
      let sep = lines[currentLine].find(':')
      if sep == -1:
        # Skip line if not json.
        currentLine.inc
        continue

      headerStarted = true

      let valueStart = lines[currentLine].skipWhitespace(sep + 1)

      case lines[currentLine][0 ..< sep]
        of "Content-Type":
          if isInvalidContentType(lines[currentLine], valueStart):
            return ReadFrameResult.err "Only utf-8 is supported"
        of "Content-Length":
          if parseInt(lines[currentLine], contentLen, valueStart) == 0:
            return ReadFrameResult.err fmt"Invalid Content-Length: {lines[currentLine].substr(valueStart)}"
        else:
          # Unrecognized headers are ignored
          discard
    elif not headerStarted:
      continue
    else:
      if contentLen != -1:
        var response = ""
        for i in currentLine .. lines.high:
          for j in 0 .. lines[i].high:
            response &= lines[i][j]
        debugLog(MessageType.read, "Response: {response}")
        return ReadFrameResult.ok response
      else:
        return ReadFrameResult.err "Missing Content-Length header"

    currentLine.inc

proc read*(output: AsyncPipe): JsonRpcResponseResult =
  ## Return a json-rpc response from the stream.

  let r = output.readFrame
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

proc write(input: AsyncPipe, buffer: string) {.async.} =
  discard await input.write(cast[pointer](buffer[0].unsafeAddr), buffer.len)

proc send(
  input: AsyncPipe,
  frame: string): Result[(), string] =
    ## Write json-rpc message to the stream.

    let req = "Content-Length: " & $frame.len & "\r\n\r\n" & frame

    debugLog(MessageType.write, req)

    try:
      waitFor input.write req
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
  pipes: Pipes,
  id: int,
  methodName: string,
  params: JsonNode): JsonRpcResponseResult =
    ## Send a request and return a response.

    let req = newReqest(id, methodName, params)

    let err = pipes.input.send(req)
    if err.isErr:
      return JsonRpcResponseResult.err err.error

    let res = pipes.output.read
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
  input: AsyncPipe,
  methodName: string,
  params: JsonNode): Result[(), string] =
    ## Send a notification.
    ## No response to the notification. Also, no `id` is required in the request.

    let notify = newNotify(methodName, params)
    return input.send(notify)
