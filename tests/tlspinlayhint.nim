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

import moepkg/inlayhint {.all.}

suite "lsp: parseTextDocumentInlayHint":
  test "Basic":
    let r = parseTextDocumentInlayHint(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "position": {
            "line": 4,
            "character": 5
          },
          "label": ": int",
          "kind": 1,
          "textEdits": [
            {
              "range": {
                "start":{
                  "line": 4,
                  "character": 5
                },
                "end": {
                  "line": 4,
                  "character": 5}
                },
                "newText": ": int"
              }
          ],
          "tooltip": "",
          "paddingLeft": false,
          "paddingRight": false
        },
        {
          "position": {
            "line": 6,
            "character": 5
          },
          "label": ": string",
          "kind": 1,
          "textEdits": [
            {
              "range": {
                "start": {
                  "line": 6,
                  "character": 5
                  },
                  "end": {
                    "line": 6,
                    "character": 5
                  }
              },
              "newText": ": string"
            }
          ],
          "tooltip": "",
          "paddingLeft": false,
          "paddingRight": false
        }
      ]
    }).get

    check r.len == 2

    check r[0].position[] == types.Position(line: 4, character: 5)[]
    check r[0].label == ": int"
    check r[0].kind == some(1)

    check r[0].textEdits.get.len == 1
    check r[0].textEdits.get[0].range.start[] == types.Position(line: 4, character: 5)[]
    check r[0].textEdits.get[0].range.`end`[] == types.Position(line: 4, character: 5)[]
    check r[0].textEdits.get[0].newText == ": int"

    check r[0].tooltip.get == ""
    check r[0].paddingLeft.get == false
    check r[0].paddingRight.get == false

    check r[1].position[] == types.Position(line: 6, character: 5)[]
    check r[1].label == ": string"
    check r[1].kind == some(1)

    check r[1].textEdits.get.len == 1
    check r[1].textEdits.get[0].range.start[] == types.Position(line: 6, character: 5)[]
    check r[1].textEdits.get[0].range.`end`[] == types.Position(line: 6, character: 5)[]
    check r[1].textEdits.get[0].newText == ": string"

    check r[1].tooltip.get == ""
    check r[1].paddingLeft.get == false
    check r[1].paddingRight.get == false
