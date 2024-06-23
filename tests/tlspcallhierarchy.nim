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

import std/[unittest, json, options]

import pkg/results

import moepkg/lsp/protocol/types
import moepkg/lsp/callhierarchy {.all.}

suite "lsp: parseTextDocumentPrepareCallHierarchyResponse":
  test "Not found":
    check parseTextDocumentPrepareCallHierarchyResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    }).get.len == 0

  test "Basic":
    let r = parseTextDocumentPrepareCallHierarchyResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "name": "f",
          "kind": 0,
          "detail": "pub fn f()",
          "uri": "file:///home/user/app/src/test.rs",
          "range": {
            "start": {
              "line": 0,
              "character": 1
            },
            "end": {
              "line": 2,
              "character": 3
            }
          },
          "selectionRange": {
            "start": {
              "line": 4,
              "character": 5
            },
            "end": {
              "line": 6,
              "character": 7
            }
          }
        }
    ]
    }).get

    check r.len == 1
    check r[0].name == "f"
    check r[0].kind == 0
    check r[0].detail.get == "pub fn f()"
    check r[0].range.start[] == Position(line: 0, character: 1)[]
    check r[0].range.`end`[] == Position(line: 2, character: 3)[]
    check r[0].selectionRange.start[] == Position(line: 4, character: 5)[]
    check r[0].selectionRange.`end`[] == Position(line: 6, character: 7)[]

suite "lsp: parseCallhierarchyIncomingCallsResponse":
  test "Not found":
    check parseCallhierarchyIncomingCallsResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    }).get.len == 0

  test "Basic":
    let r = parseCallhierarchyIncomingCallsResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "from": {
            "name": "name0",
            "kind": 12,
            "detail": "detail0",
            "uri": "file:///home/user/app/src/test0.rs",
            "range": {
              "start": {
                "line": 0,
                "character": 1
              },
              "end": {
                "line": 2,
                "character": 3
              }
            },
            "selectionRange": {
              "start": {
                "line": 4,
                "character": 5
              },
              "end": {
                "line": 6,
                "character": 7
              }
            }
          },
          "fromRanges": [
            {
              "start": {
                "line": 8,
                "character": 9
              },
              "end": {
                "line": 10,
                "character": 11
              }
            }
          ]
        },
        {
          "from": {
            "name": "name1",
            "kind": 12,
            "detail": "detail1",
            "uri": "file:///home/user/app/src/test1.rs",
            "range": {
              "start": {
                "line": 0,
                "character": 1
              },
              "end": {
                "line": 2,
                "character": 3
              }
            },
            "selectionRange": {
              "start": {
                "line": 4,
                "character": 5
              },
              "end": {
                "line": 6,
                "character": 7
              }
            }
          },
          "fromRanges": [
            {
              "start": {
                "line": 8,
                "character": 9
              },
              "end": {
                "line": 10,
                "character": 11
              }
            }
          ]
        }
      ]}).get

    check r.len == 2

    check r[0].from.name == "name0"
    check r[0].from.kind == 12
    check r[0].from.detail.get == "detail0"
    check r[0].from.uri == "file:///home/user/app/src/test0.rs"
    check r[0].from.range.start[] == Position(line: 0, character: 1)[]
    check r[0].from.range.`end`[] == Position(line: 2, character: 3)[]
    check r[0].from.selectionRange.start[] == Position(line: 4, character: 5)[]
    check r[0].from.selectionRange.`end`[] == Position(line: 6, character: 7)[]

    check r[1].from.name == "name1"
    check r[1].from.kind == 12
    check r[1].from.detail.get == "detail1"
    check r[1].from.uri == "file:///home/user/app/src/test1.rs"
    check r[1].from.range.start[] == Position(line: 0, character: 1)[]
    check r[1].from.range.`end`[] == Position(line: 2, character: 3)[]
    check r[1].from.selectionRange.start[] == Position(line: 4, character: 5)[]
    check r[1].from.selectionRange.`end`[] == Position(line: 6, character: 7)[]

suite "lsp: parseCallhierarchyOutgoingCallsResponse":
  test "Not found":
    check parseCallhierarchyOutgoingCallsResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    }).get.len == 0

  test "Basic":
    let r = parseCallhierarchyOutgoingCallsResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "to": {
            "name": "name0",
            "kind": 12,
            "detail": "detail0",
            "uri": "file:///home/user/app/src/test0.rs",
            "range": {
              "start": {
                "line": 0,
                "character": 1
              },
              "end": {
                "line": 2,
                "character": 3
              }
            },
            "selectionRange": {
              "start": {
                "line": 4,
                "character": 5
              },
              "end": {
                "line": 6,
                "character": 7
              }
            }
          },
          "fromRanges": [
            {
              "start": {
                "line": 8,
                "character": 9
              },
              "end": {
                "line": 10,
                "character": 11
              }
            }
          ]
        },
        {
          "to": {
            "name": "name1",
            "kind": 12,
            "detail": "detail1",
            "uri": "file:///home/user/app/src/test1.rs",
            "range": {
              "start": {
                "line": 0,
                "character": 1
              },
              "end": {
                "line": 2,
                "character": 3
              }
            },
            "selectionRange": {
              "start": {
                "line": 4,
                "character": 5
              },
              "end": {
                "line": 6,
                "character": 7
              }
            }
          },
          "fromRanges": [
            {
              "start": {
                "line": 8,
                "character": 9
              },
              "end": {
                "line": 10,
                "character": 11
              }
            }
          ]
        }
      ]}).get

    check r.len == 2

    check r[0].to.name == "name0"
    check r[0].to.kind == 12
    check r[0].to.detail.get == "detail0"
    check r[0].to.uri == "file:///home/user/app/src/test0.rs"
    check r[0].to.range.start[] == Position(line: 0, character: 1)[]
    check r[0].to.range.`end`[] == Position(line: 2, character: 3)[]
    check r[0].to.selectionRange.start[] == Position(line: 4, character: 5)[]
    check r[0].to.selectionRange.`end`[] == Position(line: 6, character: 7)[]

    check r[1].to.name == "name1"
    check r[1].to.kind == 12
    check r[1].to.detail.get == "detail1"
    check r[1].to.uri == "file:///home/user/app/src/test1.rs"
    check r[1].to.range.start[] == Position(line: 0, character: 1)[]
    check r[1].to.range.`end`[] == Position(line: 2, character: 3)[]
    check r[1].to.selectionRange.start[] == Position(line: 4, character: 5)[]
    check r[1].to.selectionRange.`end`[] == Position(line: 6, character: 7)[]
