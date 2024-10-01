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

import moepkg/lsp/formatting {.all.}

suite "lsp: parseDocumentFormattingResponse":
  test "Not found":
    check parseDocumentFormattingResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    })
    .get
    .len == 0

  test "Not found 2":
    check parseDocumentFormattingResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": nil
    })
    .get
    .len == 0

  test "Basic":
    let r = parseDocumentFormattingResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "range": {
            "start": {
              "line": 1,
              "character": 0
            },
            "end": {
              "line": 1,
              "character": 0
            }
          },
          "newText": "a"
        }
      ]
    })
    .get

    check r.len == 1

    check %*r[0] == %*{
      "range": {
        "start": {
          "line": 1,
          "character": 0
        },
        "end": {
          "line": 1,
          "character": 0
        }
      },
      "newText": "a"
    }
