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

import moepkg/folding

import moepkg/lsp/foldingrange {.all.}

suite "lsp: parseFoldingRangeResponse":
  test "Not found":
    check parseTextDocumentFoldingRangeResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    }).get.len == 0

  test "Not found 2":
    check parseTextDocumentFoldingRangeResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": nil
    }).get.len == 0

  test "Basic":
    check parseTextDocumentFoldingRangeResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "startLine": 0,
          "startCharacter": 1,
          "endLine": 2,
          "endCharacter": 3
        },
        {
          "startLine": 4,
          "startCharacter": 5,
          "endLine": 6,
          "endCharacter": 7
        }
      ]
    }).get == @[
      folding.FoldingRange(first: 0, last: 2),
      folding.FoldingRange(first: 4, last: 6),
    ]
