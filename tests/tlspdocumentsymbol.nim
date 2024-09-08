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

import std/[unittest, json]

import pkg/results

import moepkg/lsp/documentsymbol {.all.}

suite "lsp: parseTextDocumentDocumentSymbolsResponse":
  test "Not found":
    check parseTextDocumentDocumentSymbolsResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    })
    .get
    .len == 0

  test "Parse DocumentSymbol[]":
    check parseTextDocumentDocumentSymbolsResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "name": "1a",
          "detail": "1b",
          "kind": 1,
          "deprecated": false,
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
        {
          "name": "2a",
          "detail": "2b",
          "kind": 2,
          "deprecated": true,
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
    })
    .get
    .len == 2

  test "Parse SymbolInformation[]":
    check parseTextDocumentDocumentSymbolsResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "name": "1a",
          "kind": 1,
          "deprecated": false,
          "location": {
            "uri": "file:///test.txt",
            "range": {
              "start": {
                "line": 0,
                "character": 1
              },
              "end": {
                "line": 2,
                "character": 3
              }
            }
          }
        },
        {
          "name": "2a",
          "kind": 2,
          "deprecated": false,
          "location": {
            "uri": "file:///test.txt",
            "range": {
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
        }
      ]
    })
    .get
    .len == 2
