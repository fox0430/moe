#
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

import moepkg/lsp/rename {.all.}

suite "lsp: parseTextDocumentRenameResponse":
  test "Not found":
    check parseTextDocumentRenameResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": nil
    }).get.len == 0

  test "Basic":
    check parseTextDocumentRenameResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": {
        "changes": {
          "file:///home/user/moe/src/moe.nim": [
            {
              "range": {
                "start": {
                  "line": 22,
                  "character": 5
                },
                "end": {
                  "line": 22,
                  "character": 9
                }
              },
              "newText": "abc"
            },
            {
              "range" :{
                "start": {
                  "line": 32,
                  "character": 19
                },
                "end": {
                  "line": 32,
                  "character": 23
                }
              },
              "newText": "abc"
            }
          ]
        },
        "documentChanges": nil
      }
    }).get == @[
      LspRename(
        path: "/home/user/moe/src/moe.nim",
        changes: @[
          RenameChange(
            range: BufferRange(
              first: BufferPosition(line: 22, column: 5),
              last: BufferPosition(line: 22, column: 9)),
            text: "abc"
          ),
          RenameChange(
            range: BufferRange(
              first: BufferPosition(line: 32, column: 19),
              last: BufferPosition(line: 32, column: 23)),
            text: "abc"
          )
        ]
      )
    ]

  test "Basic 2":
    check parseTextDocumentRenameResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": {
        "changes": {
          "file:///home/user/test.nim": [
            {
              "range": {
                "start": {
                  "line": 22,
                  "character": 5
                },
                "end": {
                  "line": 22,
                  "character": 9
                }
              },
              "newText": "abc"
            },
            {
              "range" :{
                "start": {
                  "line": 32,
                  "character": 19
                },
                "end": {
                  "line": 32,
                  "character": 23
                }
              },
              "newText": "abc"
            }
          ],
          "file:///home/user/test2.nim": [
            {
              "range": {
                "start": {
                  "line": 0,
                  "character": 0
                },
                "end": {
                  "line": 0,
                  "character": 4
                }
              },
              "newText": "abc"
            }
          ],
        },
        "documentChanges": nil,
      }
    }).get == @[
      LspRename(
        path: "/home/user/test.nim",
        changes: @[
          RenameChange(
            range: BufferRange(
              first: BufferPosition(line: 22, column: 5),
              last: BufferPosition(line: 22, column: 9)),
            text: "abc"
          ),
          RenameChange(
            range: BufferRange(
              first: BufferPosition(line: 32, column: 19),
              last: BufferPosition(line: 32, column: 23)),
            text: "abc"
          )
        ]
      ),
      LspRename(
        path: "/home/user/test2.nim",
        changes: @[
          RenameChange(
            range: BufferRange(
              first: BufferPosition(line: 0, column: 0),
              last: BufferPosition(line: 0, column: 4)),
            text: "abc"
          )
        ]
      )

    ]
