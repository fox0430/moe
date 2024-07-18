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
import moepkg/lsp/codelens {.all.}

suite "lsp: parseCodeLensResponse":
  test "Not found":
    check parseCodeLensResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": []
    }).get.len == 0

  test "Not found 2":
    check parseCodeLensResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": nil
    }).get.len == 0


  test "Basic":
    let r = parseCodeLensResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": [
        {
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
          "command": {
            "title": "title",
            "command": "command",
            "arguments": [
              {
                "label": "label1",
                "location": {
                  "targetUri": "file:///test",
                  "targetRange": {
                    "start": {
                      "line": 0,
                      "character":1
                    },
                    "end": {
                      "line":2,
                      "character":3
                    }
                  },
                  "targetSelectionRange": {
                    "start": {
                      "line": 0,
                      "character": 1
                    },
                    "end": {
                      "line": 2,
                      "character": 3
                    }
                  }
                },
                "kind": "kind",
                "args": {
                  "arg1": "1",
                  "arg2": "2",
                }
              }
            ]
          }
        }
      ]
    }).get

    check r.len == 1
    check r[0].range.start[] == Position(line: 0, character: 1)[]
    check r[0].range.`end`[] == Position(line: 2, character: 3)[]

    check r[0].command.get.title == "title"
    check r[0].command.get.command == "command"
    check r[0].command.get.arguments.get == %*[
      {
        "label": "label1",
        "location": {
          "targetUri": "file:///test",
          "targetRange": {
            "start": {
              "line": 0,
              "character": 1
            },
            "end": {
              "line": 2,
              "character": 3
            }
          },
          "targetSelectionRange": {
            "start": {
              "line": 0,
              "character": 1
            },
            "end": {
              "line": 2,
              "character": 3
            }
          }
        },
        "kind": "kind",
        "args": {
          "arg1": "1",
          "arg2": "2"
        }
      }
    ]

suite "lsp: parseCodeLensResolveResponse":
  test "Basic":
    let r = parseCodeLensResolveResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": {
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
        "command": {
          "title": "title",
          "command": "command",
          "arguments": [
            {
              "label": "label1",
              "location": {
                "targetUri": "file:///test",
                "targetRange": {
                  "start": {
                    "line": 0,
                    "character":1
                  },
                  "end": {
                    "line":2,
                    "character":3
                  }
                },
                "targetSelectionRange": {
                  "start": {
                    "line": 0,
                    "character": 1
                  },
                  "end": {
                    "line": 2,
                    "character": 3
                  }
                }
              },
              "kind": "kind",
              "args": {
                "arg1": "1",
                "arg2": "2",
              }
            }
          ]
        }
      }
    }).get

    check r.range.start[] == Position(line: 0, character: 1)[]
    check r.range.`end`[] == Position(line: 2, character: 3)[]

    check r.command.get.title == "title"
    check r.command.get.command == "command"
    check r.command.get.arguments.get == %*[
      {
        "label": "label1",
        "location": {
          "targetUri": "file:///test",
          "targetRange": {
            "start": {
              "line": 0,
              "character": 1
            },
            "end": {
              "line": 2,
              "character": 3
            }
          },
          "targetSelectionRange": {
            "start": {
              "line": 0,
              "character": 1
            },
            "end": {
              "line": 2,
              "character": 3
            }
          }
        },
        "kind": "kind",
        "args": {
          "arg1": "1",
          "arg2": "2"
        }
      }
    ]
