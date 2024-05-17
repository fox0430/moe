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

import moepkg/lsp/diagnostics {.all.}

suite "lsp: parseTextDocumentPublishDiagnosticsNotify":
  test "Invalid":
    let res = %*{"jsonrpc": "2.0", "params": nil}
    check parseTextDocumentPublishDiagnosticsNotify(res).isErr

  test "Basic":
    check %*parseTextDocumentPublishDiagnosticsNotify(%*{
      "jsonrpc": "2.0",
      "method": "textDocument/publishDiagnostics",
      "params": {
        "uri": "file:///tmp/test.nim",
        "diagnostics": [
          {
            "range": {
              "start": {
                "line": 0,
                "character": 0
              },
              "end": {
                "line": 0,
                "character": 2
              }
            },
            "severity": 1,
            "code": "nimsuggest chk",
            "source": "nim",
            "message": "undeclared identifier: 'cho'",
            "relatedInformation": nil
          }
        ]
      }
    }).get.get == %*{
      "path": "/tmp/test.nim",
      "diagnostics": [
        {
          "range": {
            "start": {
              "line": 0,
              "character": 0
            },
            "end": {
              "line": 0,
              "character": 2
            }
          },
          "severity": 1,
          "code": "nimsuggest chk",
          "source": "nim",
          "message": "undeclared identifier: 'cho'",
          "relatedInformation": nil
        }
      ]
    }
