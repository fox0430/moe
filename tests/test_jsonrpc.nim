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

import std/[unittest, json, options, tables, strutils]

import ../src/moepkg/lsp/jsonrpc

suite "JsonRpcState - Basic Operations":
  test "newJsonRpcState creates state with initial values":
    let state = newJsonRpcState()
    check state.nextId == 1
    check state.pending.len == 0

  test "getNextId returns incrementing ids":
    let state = newJsonRpcState()
    check state.getNextId() == 1
    check state.getNextId() == 2
    check state.getNextId() == 3

  test "addPending adds request to pending table":
    let state = newJsonRpcState()
    state.addPending(1, "textDocument/completion")
    check state.pending.len == 1
    check state.pending[1].id == 1
    check state.pending[1].methodName == "textDocument/completion"

  test "addPending can add multiple requests":
    let state = newJsonRpcState()
    state.addPending(1, "method1")
    state.addPending(2, "method2")
    state.addPending(3, "method3")
    check state.pending.len == 3

  test "removePending removes and returns request":
    let state = newJsonRpcState()
    state.addPending(1, "test/method")
    let result = state.removePending(1)
    check result.isSome
    check result.get.id == 1
    check result.get.methodName == "test/method"
    check state.pending.len == 0

  test "removePending returns none for non-existent id":
    let state = newJsonRpcState()
    let result = state.removePending(999)
    check result.isNone

  test "hasPending returns true for existing request":
    let state = newJsonRpcState()
    state.addPending(1, "test")
    check state.hasPending(1)

  test "hasPending returns false for non-existent request":
    let state = newJsonRpcState()
    check not state.hasPending(1)

suite "Message Encoding - encodeRequest":
  test "encodes basic request":
    let encoded = encodeRequest(1, "initialize", %*{"rootUri": "file:///test"})
    check encoded.contains("Content-Length:")
    check encoded.contains("\r\n\r\n")
    check encoded.contains("\"jsonrpc\":\"2.0\"")
    check encoded.contains("\"id\":1")
    check encoded.contains("\"method\":\"initialize\"")
    check encoded.contains("\"params\"")

  test "encodes request with empty params":
    let encoded = encodeRequest(1, "shutdown", newJObject())
    check encoded.contains("\"method\":\"shutdown\"")
    check encoded.contains("\"params\":{}")

  test "content-length matches body length":
    let encoded = encodeRequest(1, "test", %*{"key": "value"})
    let parts = encoded.split("\r\n\r\n")
    check parts.len == 2
    let header = parts[0]
    let body = parts[1]
    let lengthStr = header.split(":")[1].strip()
    check parseInt(lengthStr) == body.len

suite "Message Encoding - encodeNotification":
  test "encodes notification without id":
    let encoded =
      encodeNotification("textDocument/didOpen", %*{"uri": "file:///test.nim"})
    check encoded.contains("Content-Length:")
    check encoded.contains("\"jsonrpc\":\"2.0\"")
    check encoded.contains("\"method\":\"textDocument/didOpen\"")
    check not encoded.contains("\"id\"")

  test "content-length matches body length":
    let encoded = encodeNotification("exit", newJObject())
    let parts = encoded.split("\r\n\r\n")
    let header = parts[0]
    let body = parts[1]
    let lengthStr = header.split(":")[1].strip()
    check parseInt(lengthStr) == body.len

suite "Message Encoding - encodeResponse":
  test "encodes success response":
    let encoded = encodeResponse(1, %*{"capabilities": {}})
    check encoded.contains("Content-Length:")
    check encoded.contains("\"jsonrpc\":\"2.0\"")
    check encoded.contains("\"id\":1")
    check encoded.contains("\"result\"")

  test "encodes response with null result":
    let encoded = encodeResponse(1, newJNull())
    check encoded.contains("\"result\":null")

suite "Message Encoding - encodeErrorResponse":
  test "encodes error response with id":
    let encoded = encodeErrorResponse(some(1), -32600, "Invalid Request")
    check encoded.contains("Content-Length:")
    check encoded.contains("\"jsonrpc\":\"2.0\"")
    check encoded.contains("\"id\":1")
    check encoded.contains("\"error\"")
    check encoded.contains("\"code\":-32600")
    check encoded.contains("\"message\":\"Invalid Request\"")

  test "encodes error response without id":
    let encoded = encodeErrorResponse(none(int), -32700, "Parse error")
    check encoded.contains("\"id\":null")
    check encoded.contains("\"code\":-32700")

  test "encodes error response with data":
    let encoded = encodeErrorResponse(
      some(1), -32602, "Invalid params", some(%*{"details": "missing field"})
    )
    check encoded.contains("\"data\"")
    check encoded.contains("\"details\"")

suite "Header Parsing - parseHeaders":
  test "parses single header":
    let result = parseHeaders("Content-Length: 100")
    check result.isOk
    check result.get["content-length"] == "100"

  test "parses multiple headers":
    let headerBlock = "Content-Length: 100\nContent-Type: application/json"
    let result = parseHeaders(headerBlock)
    check result.isOk
    check result.get["content-length"] == "100"
    check result.get["content-type"] == "application/json"

  test "handles empty lines":
    let headerBlock = "Content-Length: 100\n\nContent-Type: text/plain"
    let result = parseHeaders(headerBlock)
    check result.isOk
    check result.get.len == 2

  test "returns error for invalid header line":
    let result = parseHeaders("InvalidHeaderNoColon")
    check result.isErr

  test "parses headers with extra whitespace":
    let result = parseHeaders("  Content-Length  :  200  ")
    check result.isOk
    check result.get["content-length"] == "200"

suite "Header Parsing - parseFrameHeaders (readFrame block)":
  test "Content-Length only":
    let r = parseFrameHeaders("Content-Length: 42")
    check r.isOk
    check r.get == 42

  test "Content-Length after Content-Type (order independent)":
    let r = parseFrameHeaders(
      "Content-Type: application/vscode-jsonrpc; charset=utf-8\r\nContent-Length: 17"
    )
    check r.isOk
    check r.get == 17

  test "field names are case-insensitive":
    let r = parseFrameHeaders("content-length: 5")
    check r.isOk
    check r.get == 5

  test "unknown headers are ignored":
    let r =
      parseFrameHeaders("X-Custom: foo\r\nContent-Length: 8\r\nContent-Encoding: gzip")
    check r.isOk
    check r.get == 8

  test "missing Content-Length is an error":
    let r = parseFrameHeaders("X-Custom: foo")
    check r.isErr
    check r.error.contains("Missing Content-Length")

  test "non-utf-8 Content-Type is rejected":
    let r =
      parseFrameHeaders("Content-Type: text/plain; charset=ascii\r\nContent-Length: 3")
    check r.isErr
    check r.error.contains("utf-8")

  test "invalid Content-Length value is an error":
    let r = parseFrameHeaders("Content-Length: notanumber")
    check r.isErr
    check r.error.contains("Invalid Content-Length")

  test "overflowing Content-Length is rejected, not crashing":
    let r = parseFrameHeaders("Content-Length: 999999999999999999999999")
    check r.isErr
    check r.error.contains("Invalid Content-Length")

  test "Content-Length at the limit is accepted":
    let r = parseFrameHeaders("Content-Length: " & $MaxContentLength)
    check r.isOk
    check r.get == MaxContentLength

  test "Content-Length above the limit is rejected":
    let r = parseFrameHeaders("Content-Length: " & $(MaxContentLength + 1))
    check r.isErr
    check r.error.contains("exceeds limit")

suite "Message Parsing - parseJsonRpcMessage":
  test "parses request message":
    let body = """{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"""
    let result = parseJsonRpcMessage(body)
    check result.isOk
    check result.get.kind == jrmkRequest
    check result.get.reqId == 1
    check result.get.reqMethod == "initialize"

  test "parses response message":
    let body = """{"jsonrpc":"2.0","id":1,"result":{"key":"value"}}"""
    let result = parseJsonRpcMessage(body)
    check result.isOk
    check result.get.kind == jrmkResponse
    check result.get.respId == 1
    check result.get.respResult["key"].getStr == "value"

  test "parses notification message":
    let body =
      """{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"uri":"file:///test"}}"""
    let result = parseJsonRpcMessage(body)
    check result.isOk
    check result.get.kind == jrmkNotification
    check result.get.notifyMethod == "textDocument/didOpen"

  test "parses error message with id":
    let body =
      """{"jsonrpc":"2.0","id":1,"error":{"code":-32600,"message":"Invalid Request"}}"""
    let result = parseJsonRpcMessage(body)
    check result.isOk
    check result.get.kind == jrmkError
    check result.get.errId.isSome
    check result.get.errId.get == 1
    check result.get.error.code == -32600
    check result.get.error.message == "Invalid Request"

  test "parses error message without id":
    let body =
      """{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error"}}"""
    let result = parseJsonRpcMessage(body)
    check result.isOk
    check result.get.kind == jrmkError
    check result.get.errId.isNone

  test "parses error message with data":
    let body =
      """{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"Invalid params","data":{"field":"name"}}}"""
    let result = parseJsonRpcMessage(body)
    check result.isOk
    check result.get.kind == jrmkError
    check result.get.error.data.isSome
    check result.get.error.data.get["field"].getStr == "name"

  test "parses request without params":
    let body = """{"jsonrpc":"2.0","id":1,"method":"shutdown"}"""
    let result = parseJsonRpcMessage(body)
    check result.isOk
    check result.get.kind == jrmkRequest
    check result.get.reqParams.kind == JObject

  test "returns error for invalid json":
    let result = parseJsonRpcMessage("not json")
    check result.isErr
    check result.error.contains("JSON parse error")

  test "returns error for missing jsonrpc version":
    let body = """{"id":1,"method":"test"}"""
    let result = parseJsonRpcMessage(body)
    check result.isErr
    check result.error.contains("jsonrpc version")

  test "returns error for wrong jsonrpc version":
    let body = """{"jsonrpc":"1.0","id":1,"method":"test"}"""
    let result = parseJsonRpcMessage(body)
    check result.isErr

  test "returns error for invalid message structure":
    let body = """{"jsonrpc":"2.0"}"""
    let result = parseJsonRpcMessage(body)
    check result.isErr
    check result.error.contains("Invalid")

suite "Integration - Round-trip Encoding and Parsing":
  test "request round-trip":
    let original = encodeRequest(42, "test/method", %*{"param1": "value1"})
    let parts = original.split("\r\n\r\n")
    let body = parts[1]
    let parsed = parseJsonRpcMessage(body)
    check parsed.isOk
    check parsed.get.kind == jrmkRequest
    check parsed.get.reqId == 42
    check parsed.get.reqMethod == "test/method"

  test "notification round-trip":
    let original = encodeNotification("notify/event", %*{"data": 123})
    let parts = original.split("\r\n\r\n")
    let body = parts[1]
    let parsed = parseJsonRpcMessage(body)
    check parsed.isOk
    check parsed.get.kind == jrmkNotification
    check parsed.get.notifyMethod == "notify/event"

  test "response round-trip":
    let original = encodeResponse(99, %*{"result": "success"})
    let parts = original.split("\r\n\r\n")
    let body = parts[1]
    let parsed = parseJsonRpcMessage(body)
    check parsed.isOk
    check parsed.get.kind == jrmkResponse
    check parsed.get.respId == 99

  test "error response round-trip":
    let original = encodeErrorResponse(some(5), -32600, "Error occurred")
    let parts = original.split("\r\n\r\n")
    let body = parts[1]
    let parsed = parseJsonRpcMessage(body)
    check parsed.isOk
    check parsed.get.kind == jrmkError
    check parsed.get.errId.get == 5
    check parsed.get.error.code == -32600
