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

import moepkg/independentutils

import moepkg/lsp/references {.all.}

suite "lsp: parseTextDocumentReferencesResponse":
  test "Not found":
    check parseTextDocumentReferencesResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    }).get.len == 0

  test "Basic":
    check parseTextDocumentReferencesResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "uri":  "file:///home/user/text.txt",
          "range": {
            "start": {
              "line": 0,
              "character": 1,
            },
            "end": {
              "line": 0,
              "character": 2,
            }
          }
        }
      ]
    }).get == @[
      LspReference(
        path: "/home/user/text.txt",
        position: BufferPosition(line: 0, column: 1))
    ]
