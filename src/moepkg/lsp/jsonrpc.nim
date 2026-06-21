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

## JSON-RPC 2.0 Implementation for LSP
## Handles message framing with Content-Length headers
## Uses chronos for async I/O

import std/[json, strutils, tables, options, parseutils]

import pkg/results
import pkg/stew/byteutils
import pkg/chronos

export chronos

type
  RequestId* = int

  JsonRpcError* = object
    code*: int
    message*: string
    data*: Option[JsonNode]

  JsonRpcMessageKind* = enum
    jrmkRequest
    jrmkResponse
    jrmkNotification
    jrmkError

  JsonRpcMessage* = object
    case kind*: JsonRpcMessageKind
    of jrmkRequest:
      reqId*: RequestId
      reqMethod*: string
      reqParams*: JsonNode
    of jrmkResponse:
      respId*: RequestId
      respResult*: JsonNode
    of jrmkNotification:
      notifyMethod*: string
      notifyParams*: JsonNode
    of jrmkError:
      errId*: Option[RequestId]
      error*: JsonRpcError

  PendingRequest* = object
    id*: RequestId
    methodName*: string
    sentAt*: int64 # Unix timestamp for timeout tracking

  JsonRpcState* = ref object
    nextId*: RequestId
    pending*: Table[RequestId, PendingRequest]

proc newJsonRpcState*(): JsonRpcState =
  JsonRpcState(nextId: 1, pending: initTable[RequestId, PendingRequest]())

proc getNextId*(state: JsonRpcState): RequestId =
  result = state.nextId
  inc state.nextId

proc addPending*(state: JsonRpcState, id: RequestId, methodName: string) =
  state.pending[id] = PendingRequest(id: id, methodName: methodName, sentAt: 0)

proc removePending*(state: JsonRpcState, id: RequestId): Option[PendingRequest] =
  if id in state.pending:
    result = some(state.pending[id])
    state.pending.del(id)
  else:
    result = none(PendingRequest)

proc hasPending*(state: JsonRpcState, id: RequestId): bool =
  id in state.pending

# Message encoding
proc encodeRequest*(id: RequestId, meth: string, params: JsonNode): string =
  ## Encode a JSON-RPC request with Content-Length header
  let request = %*{"jsonrpc": "2.0", "id": id, "method": meth, "params": params}
  let body = $request
  result = "Content-Length: " & $body.len & "\r\n\r\n" & body

proc encodeNotification*(meth: string, params: JsonNode): string =
  ## Encode a JSON-RPC notification with Content-Length header
  let notification = %*{"jsonrpc": "2.0", "method": meth, "params": params}
  let body = $notification
  result = "Content-Length: " & $body.len & "\r\n\r\n" & body

proc encodeResponse*(id: RequestId, resultNode: JsonNode): string =
  ## Encode a JSON-RPC response with Content-Length header
  let response = %*{"jsonrpc": "2.0", "id": id, "result": resultNode}
  let body = $response
  result = "Content-Length: " & $body.len & "\r\n\r\n" & body

proc encodeErrorResponse*(
    id: Option[RequestId],
    code: int,
    message: string,
    data: Option[JsonNode] = none(JsonNode),
): string =
  ## Encode a JSON-RPC error response with Content-Length header
  var response = %*{"jsonrpc": "2.0", "error": {"code": code, "message": message}}
  if id.isSome:
    response["id"] = %id.get
  else:
    response["id"] = newJNull()
  if data.isSome:
    response["error"]["data"] = data.get
  let body = $response
  result = "Content-Length: " & $body.len & "\r\n\r\n" & body

# Header parsing
proc parseHeaders*(headerBlock: string): Result[Table[string, string], string] =
  ## Parse all headers from header block
  var headers = initTable[string, string]()

  for line in headerBlock.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue

    let colonPos = trimmed.find(':')
    if colonPos < 0:
      return err("Invalid header line: " & trimmed)

    let
      key = trimmed[0 ..< colonPos].strip().toLowerAscii()
      value = trimmed[colonPos + 1 ..^ 1].strip()
    headers[key] = value

  return ok(headers)

# Message parsing
proc parseJsonRpcMessage*(body: string): Result[JsonRpcMessage, string] =
  ## Parse a JSON-RPC message from body string
  var jsonNode: JsonNode
  try:
    jsonNode = parseJson(body)
  except JsonParsingError as e:
    return err("JSON parse error: " & e.msg)

  # Check jsonrpc version
  if not jsonNode.hasKey("jsonrpc") or jsonNode["jsonrpc"].getStr != "2.0":
    return err("Invalid or missing jsonrpc version")

  # Determine message type
  let hasId = jsonNode.hasKey("id") and jsonNode["id"].kind != JNull
  let hasMethod = jsonNode.hasKey("method")
  let hasResult = jsonNode.hasKey("result")
  let hasError = jsonNode.hasKey("error")

  if hasError:
    # Error response
    let errNode = jsonNode["error"]
    var errId: Option[RequestId] = none(RequestId)
    if hasId:
      errId = some(jsonNode["id"].getInt)

    var data: Option[JsonNode] = none(JsonNode)
    if errNode.hasKey("data"):
      data = some(errNode["data"])

    return ok(
      JsonRpcMessage(
        kind: jrmkError,
        errId: errId,
        error: JsonRpcError(
          code: errNode["code"].getInt, message: errNode["message"].getStr, data: data
        ),
      )
    )
  elif hasResult and hasId:
    # Response
    return ok(
      JsonRpcMessage(
        kind: jrmkResponse,
        respId: jsonNode["id"].getInt,
        respResult: jsonNode["result"],
      )
    )
  elif hasMethod:
    let meth = jsonNode["method"].getStr
    let params =
      if jsonNode.hasKey("params"):
        jsonNode["params"]
      else:
        newJObject()

    if hasId:
      # Request
      return ok(
        JsonRpcMessage(
          kind: jrmkRequest,
          reqId: jsonNode["id"].getInt,
          reqMethod: meth,
          reqParams: params,
        )
      )
    else:
      # Notification
      return ok(
        JsonRpcMessage(kind: jrmkNotification, notifyMethod: meth, notifyParams: params)
      )
  else:
    return err("Invalid JSON-RPC message structure")

# Async I/O types and functions using chronos

type
  JsonRpcResponseResult* = Result[JsonNode, string]
  JsonRpcSendResult* = Result[void, string]

  InputStream* = ref object
    stream*: AsyncStreamWriter

  OutputStream* = ref object
    stream*: AsyncStreamReader

  Streams* = ref object
    input*: InputStream
    output*: OutputStream

const
  ## Sanity limits on incoming frames. A malicious or buggy server can
  ## otherwise force unbounded allocation: an endless header block with no
  ## "\r\n\r\n" terminator, or a huge Content-Length that `read` would try to
  ## allocate up front. Both ceilings sit far above any legitimate LSP message.
  MaxHeaderBlockLen* = 8 * 1024 # 8 KiB of headers is already absurd
  MaxContentLength* = 256 * 1024 * 1024 # 256 MiB body ceiling

proc isInvalidContentType(s: string, valueStart: int): bool {.inline.} =
  s.find("utf-8", valueStart) == -1 and s.find("utf8", valueStart) == -1

proc isValidJsonRpc(json: JsonNode): bool {.inline.} =
  json.contains("jsonrpc")

proc parseFrameHeaders*(headerBlock: string): Result[int, string] =
  ## Parse a JSON-RPC header block and return the Content-Length.
  ## Headers may arrive in any order and field names are case-insensitive,
  ## so every line is scanned (stopping at the first Content-* line missed
  ## Content-Length when Content-Type came first). Unknown headers are
  ## ignored. Exposed for testing.
  var contentLen = -1
  for ln in headerBlock.splitLines:
    if ln.len == 0:
      continue
    let sep = ln.find(':')
    if sep < 0:
      continue
    let name = ln[0 ..< sep]
    let valueStart = sep + 1 + ln.skipWhitespace(sep + 1)
    if name.cmpIgnoreCase("Content-Length") == 0:
      # parseInt raises ValueError on overflow; treat that as invalid too
      let parsed =
        try:
          parseInt(ln, contentLen, valueStart)
        except ValueError:
          0
      if parsed == 0:
        return
          Result[int, string].err("Invalid Content-Length: " & ln.substr(valueStart))
    elif name.cmpIgnoreCase("Content-Type") == 0:
      if isInvalidContentType(ln, valueStart):
        return Result[int, string].err("Only utf-8 is supported")
    # Any other header is ignored

  if contentLen < 0:
    return Result[int, string].err("Missing Content-Length header")
  if contentLen > MaxContentLength:
    return Result[int, string].err(
      "Content-Length exceeds limit: " & $contentLen & " > " & $MaxContentLength
    )
  Result[int, string].ok(contentLen)

proc readFrame(s: AsyncStreamReader): Future[Result[string, string]] {.async.} =
  ## Read a JSON-RPC frame from the stream

  let buf =
    try:
      await s.readLine(limit = MaxHeaderBlockLen, sep = "\r\n\r\n")
    except CatchableError as e:
      return Result[string, string].err("readLine failed: " & e.msg)

  if buf.len == 0:
    return Result[string, string].err("readLine: empty")

  if buf.len >= MaxHeaderBlockLen:
    # readLine stopped at the limit without finding the header terminator.
    return Result[string, string].err("LSP header block exceeds limit")

  # `buf` is the whole header block (readLine consumed up to the blank line)
  let headers = parseFrameHeaders(buf)
  if headers.isErr:
    return Result[string, string].err(headers.error)
  let contentLen = headers.get

  let body =
    try:
      let bytes = await s.read(contentLen)
      string.fromBytes(bytes)
    except CatchableError:
      return Result[string, string].err("readStr failed")
  return Result[string, string].ok(body)

proc read*(s: OutputStream): Future[JsonRpcResponseResult] {.async.} =
  ## Return a JSON-RPC response from the stream

  let r = await s.stream.readFrame()
  if r.isErr:
    return JsonRpcResponseResult.err(r.error)

  var res: JsonNode
  try:
    res = parseJson(r.get)
  except CatchableError as e:
    return JsonRpcResponseResult.err(e.msg)

  if res.isValidJsonRpc:
    return JsonRpcResponseResult.ok(res)
  else:
    return JsonRpcResponseResult.err("Invalid jsonrpc: " & $res)

proc send(s: InputStream, frame: string): Future[JsonRpcSendResult] {.async.} =
  ## Write JSON-RPC message to the stream
  let req = "Content-Length: " & $frame.len & "\r\n\r\n" & frame
  try:
    await s.stream.write(req)
    return JsonRpcSendResult.ok()
  except CatchableError as e:
    return JsonRpcSendResult.err("Write failed: " & e.msg)

proc sendRequest*(s: InputStream, req: JsonNode): Future[JsonRpcSendResult] {.async.} =
  ## Send a request

  let str = $req
  let err = await s.send(str)
  if err.isErr:
    return JsonRpcSendResult.err(err.error)
  return JsonRpcSendResult.ok()

proc sendNotify*(
    s: InputStream, notify: JsonNode
): Future[JsonRpcSendResult] {.async.} =
  ## Send a notification
  ## No response to the notification. Also, no `id` is required in the request.

  let str = $notify
  return await s.send(str)
