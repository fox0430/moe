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

import moepkg/lsp/completion {.all.}

suite "lsp: parseTextDocumentCompletionResponse":
  test "Invalid":
    let res = %*{"jsonrpc": "2.0", "params": nil}
    check parseTextDocumentCompletionResponse(res).isErr

  test "lsp: Old specification":
    check %*parseTextDocumentCompletionResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
          "label": "a",
          "kind": 3,
          "detail": "detail1",
          "documentation": "documentation1",
          "deprecated": nil,
          "preselect": nil,
          "sortText": nil,
          "filterText": nil,
          "insertText": nil,
          "insertTextFormat": nil,
          "commitCharacters": nil,
          "command": nil,
          "data": nil
        },
        {
          "label": "b",
          "kind": 3,
          "detail": "detail2",
          "documentation": "documentation2",
          "deprecated": nil,
          "preselect": nil,
          "sortText": nil,
          "filterText": nil,
          "insertText": nil,
          "insertTextFormat": nil,
          "commitCharacters": nil,
          "command": nil,
          "data": nil
        }
      ]
    }).get == %*[{
      "label": "a",
      "labelDetails": nil,
      "kind":3 ,
      "tags": nil,
      "detail": "detail1",
      "documentation": "documentation1",
      "deprecated": nil,
      "preselect": nil,
      "sortText": nil,
      "filterText": nil,
      "insertText": nil,
      "insertTextFormat": nil,
      "textEdit": nil,
      "additionalTextEdits": nil,
      "commitCharacters": nil,
      "command": nil,
      "data": nil
    },
    {
      "label" : "b",
      "labelDetails": nil,
      "kind": 3,
      "tags": nil,
      "detail" :"detail2",
      "documentation": "documentation2",
      "deprecated": nil,
      "preselect" :nil,
      "sortText": nil,
      "filterText": nil,
      "insertText": nil,
      "insertTextFormat": nil,
      "textEdit": nil,
      "additionalTextEdits": nil,
      "commitCharacters": nil,
      "command":nil,
      "data":nil
    }]

  test "lsp: Basic":
    check %*parseTextDocumentCompletionResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": {
        "isIncomplete": true,
        "items": [
          {
            "label": "self::",
            "kind": 14,
            "deprecated": false,
            "preselect": true,
            "sortText": "ffffffef",
            "filterText": "self::",
            "textEdit": {
              "range": {
                "start": {
                  "line": 2,
                  "character": 4
                },
                "end": {
                  "line": 2,
                  "character": 5
                }
              },
              "newText": "self::"
            },
            "additionalTextEdits": []
          },
          {
            "label": "crate::",
            "kind": 14,
            "deprecated": false,
            "preselect": true,
            "sortText": "ffffffef",
            "filterText": "crate::",
            "textEdit": {
              "range": {
                "start": {
                  "line": 2,
                  "character": 4
                },
                "end": {
                  "line": 2,
                  "character": 5
                }
              },
              "newText": "crate::"
            },
            "additionalTextEdits": []
          }
        ]
      }}).get == %*[{
        "label": "self::",
        "labelDetails": nil,
        "kind": 14,
        "tags": nil,
        "detail": nil,
        "documentation": nil,
        "deprecated": false,
        "preselect": true,
        "sortText": "ffffffef",
        "filterText": "self::",
        "insertText": nil,
        "insertTextFormat": nil,
        "textEdit": {
          "range": {
            "start": {
              "line": 2,
              "character": 4
            },
            "end": {
              "line": 2,
              "character": 5
            }
          },
          "newText": "self::"
        },
        "additionalTextEdits": [],
        "commitCharacters": nil,
        "command": nil,
        "data": nil
      },
      {
        "label": "crate::",
        "labelDetails": nil,
        "kind": 14,
        "tags": nil,
        "detail": nil,
        "documentation": nil,
        "deprecated": false,
        "preselect": true,
        "sortText": "ffffffef",
        "filterText": "crate::",
        "insertText": nil,
        "insertTextFormat": nil,
        "textEdit": {
          "range": {
            "start": {
              "line": 2,
              "character": 4
            },
            "end": {
              "line": 2,
              "character": 5
            }
          },
          "newText": "crate::"
        },
        "additionalTextEdits": [],
        "commitCharacters": nil,
        "command": nil,
        "data": nil
      }]
