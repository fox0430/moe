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
import moepkg/lsp/signaturehelp {.all.}

suite "lsp: SignatureHelpResponse":
  test "Not found":
    check parseSignatureHelpResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": nil
    })
    .get
    .isNone

  test "Basic":
    let r = parseSignatureHelpResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": {
        "signatures": [
          {
            "label": "a",
            "documentation": {
              "kind": "markdown",
              "value": "b"
            },
            "parameters": [
              {
                "label": "c"
              }
            ],
            "activeParameter": 0
          }
        ],
        "activeSignature": 0,
        "activeParameter": 0
      }
    })
    .get
    .get

    check r.activeSignature.get == 0
    check r.activeParameter.get == 0
    check r.signatures.len == 1

    check r.signatures[0].label == "a"
    check r.signatures[0].documentation.get == %*{
      "kind": "markdown",
      "value": "b"
    }
    check r.signatures[0].parameters.get[0].label.get == %*"c"
