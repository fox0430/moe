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
import moepkg/lsp/selectionrange {.all.}

suite "lsp: parseTextDocumentSelectionRangeResponse":
  test "Not found":
    check parseTextDocumentSelectionRangeResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    })
    .get
    .len == 0

  test "Not found 2":
    check parseTextDocumentSelectionRangeResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": nil
    })
    .get
    .len == 0

  test "Basic":
    let selectionRanges = parseTextDocumentSelectionRangeResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "range": {
            "start": {
              "line": 5,
              "character": 0
            },
            "end": {
              "line": 5,
              "character": 0
            }
          },
          "parent": {
            "range": {
              "start": {
                "line": 5,
                "character": 0
              },
              "end": {
                "line": 6,
                "character": 0
              }
            },
            "parent": {
              "range": {
                "start": {
                  "line": 4,
                  "character": 10
                },
                "end": {
                  "line": 7,
                  "character": 1
                }
              }
            }
          }
        }
      ]
    })
    .get

    check selectionRanges.len == 1

    var r = selectionRanges[0]
    check r.range.start.line == 5
    check r.range.start.character == 0
    check r.range.`end`.line == 5
    check r.range.`end`.character == 0

    r = r.parent.get
    check r.range.start.line == 5
    check r.range.start.character == 0
    check r.range.`end`.line == 6
    check r.range.`end`.character == 0

    r = r.parent.get
    check r.range.start.line == 4
    check r.range.start.character == 10
    check r.range.`end`.line == 7
    check r.range.`end`.character == 1

    check r.parent.isNone
