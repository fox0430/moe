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

## JSON-RPC 2.0 Implementation for LSP
## Handles message framing with Content-Length headers

import std/[json, strutils, tables, options]

import pkg/results

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
proc parseContentLength*(header: string): Result[int, string] =
  ## Parse Content-Length from header line
  let trimmed = header.strip()
  if not trimmed.toLowerAscii.startsWith("content-length:"):
    return err("Not a Content-Length header")

  let valueStr = trimmed[15 ..^ 1].strip()
  try:
    let length = parseInt(valueStr)
    if length < 0:
      return err("Content-Length cannot be negative")
    return ok(length)
  except ValueError:
    return err("Invalid Content-Length value: " & valueStr)

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

# Streaming message reader state machine
type
  ReaderState* = enum
    rsReadingHeaders
    rsReadingBody

  MessageReader* = ref object
    state*: ReaderState
    headerBuffer*: string
    bodyBuffer*: string
    contentLength*: int
    bytesRead*: int

proc newMessageReader*(): MessageReader =
  MessageReader(
    state: rsReadingHeaders,
    headerBuffer: "",
    bodyBuffer: "",
    contentLength: 0,
    bytesRead: 0,
  )

proc reset*(reader: MessageReader) =
  reader.state = rsReadingHeaders
  reader.headerBuffer = ""
  reader.bodyBuffer = ""
  reader.contentLength = 0
  reader.bytesRead = 0

proc feedLine*(reader: MessageReader, line: string): Result[Option[string], string] =
  ## Feed a line to the reader (for header parsing)
  ## Returns Some(body) when a complete message is ready
  case reader.state
  of rsReadingHeaders:
    if line == "" or line == "\r\n" or line == "\r":
      # End of headers
      if reader.contentLength <= 0:
        return err("No Content-Length header found")
      reader.state = rsReadingBody
      reader.bodyBuffer = ""
      reader.bytesRead = 0
      return ok(none(string))
    else:
      reader.headerBuffer.add(line & "\n")
      let lengthResult = parseContentLength(line)
      if lengthResult.isOk:
        reader.contentLength = lengthResult.get
      return ok(none(string))
  of rsReadingBody:
    return err("Use feedBytes for body reading")

proc feedBytes*(reader: MessageReader, data: string): Result[Option[string], string] =
  ## Feed bytes to the reader (for body parsing)
  ## Returns Some(body) when a complete message is ready
  if reader.state != rsReadingBody:
    return err("Not in body reading state")

  reader.bodyBuffer.add(data)
  reader.bytesRead += data.len

  if reader.bytesRead >= reader.contentLength:
    let body = reader.bodyBuffer[0 ..< reader.contentLength]
    reader.reset()
    return ok(some(body))
  else:
    return ok(none(string))

proc remainingBytes*(reader: MessageReader): int =
  ## Get remaining bytes needed for current message
  if reader.state == rsReadingBody:
    return reader.contentLength - reader.bytesRead
  else:
    return 0
