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

import moepkg/lsp/progress {.all.}

suite "lsp: parseWindowWorkDnoneProgressCreateNotify":
  test "Invalid":
    check parseWindowWorkDnoneProgressCreateNotify(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": nil
    }).isErr

  test "Basic":
    check "token" == parseWindowWorkDnoneProgressCreateNotify(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "method": "window/workDoneProgress/create",
      "params": {
        "token":"token"
      }
    }).get

suite "lsp: parseWorkDoneProgressBegin":
  test "Invalid":
    check parseWorkDoneProgressBegin(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": nil
    }).isErr

  test "Basic":
    check WorkDoneProgressBegin(
      kind: "begin",
      title: "title",
      message: some("message"),
      cancellable: some(false),
      percentage: none(int))[] == parseWorkDoneProgressBegin(%*{
        "jsonrpc": "2.0",
        "method": "$/progress",
        "params": {
          "token": "token",
          "value": {
            "kind":"begin",
            "title":"title",
            "message": "message",
            "cancellable":false
          }
        }
      }).get[]

suite "lsp: parseWorkDoneProgressReport":
  test "Invalid":
    check parseWorkDoneProgressReport(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": nil
    }).isErr

  test "Basic":
    check WorkDoneProgressReport(
      kind: "report",
      message: some("message"),
      cancellable: some(false),
      percentage: some(50))[] == parseWorkDoneProgressReport(%*{
        "jsonrpc": "2.0",
        "method": "$/progress",
        "params": {
          "token": "token",
          "value": {
            "kind":"report",
            "message": "message",
            "cancellable":false,
            "percentage": 50
          }
        }
      }).get[]

suite "lsp: parseWorkDoneProgressEnd":
  test "Invalid":
    check parseWorkDoneProgressEnd(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": nil
    }).isErr

  test "Basic":
    check WorkDoneProgressEnd(
      kind: "end",
      message: some("message"))[] == parseWorkDoneProgressEnd(%*{
        "jsonrpc": "2.0",
        "method": "$/progress",
        "params": {
          "token": "token",
          "value": {
            "kind":"end",
            "message": "message",
          }
        }
      }).get[]
