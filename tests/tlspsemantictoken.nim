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

import moepkg/lsp/semantictoken

suite "lsp: parseTextDocumentSemanticTokensResponse":
  test "Not found":
    let legend = SemanticTokensLegend()
    check parseTextDocumentSemanticTokensResponse(
      %*{
        "jsonrpc": "2.0",
        "id": 0,
        "result": nil
      },
      legend
    )
    .get
    .len == 0

  test "Basic":
    let legend = SemanticTokensLegend(
      tokenTypes: @[
        "comment", "decorator", "enumMember", "enum", "function", "interface",
        "keyword", "macro", "method", "namespace", "number", "operator",
        "parameter", "property", "string", "struct", "typeParameter",
        "variable", "angle", "arithmetic", "attribute", "attributeBracket",
        "bitwise", "boolean", "brace", "bracket", "builtinAttribute",
        "builtinType", "character", "colon", "comma", "comparison",
        "constParameter", "derive", "deriveHelper", "dot", "escapeSequence",
        "invalidEscapeSequence", "formatSpecifier", "generic", "label",
        "lifetime", "logical", "macroBang", "parenthesis", "punctuation",
        "selfKeyword", "selfTypeKeyword", "semicolon", "typeAlias",
        "toolModule", "union", "unresolvedReference"],
      tokenModifiers: @[
        "documentation", "declaration", "static", "defaultLibrary", "async",
        "attribute", "callable", "constant", "consuming", "controlFlow",
        "crateRoot", "injected", "intraDocLink", "library", "macro", "mutable",
        "public", "reference", "trait", "unsafe"])

    check parseTextDocumentSemanticTokensResponse(%*{
      "jsonrpc": "2.0",
      "id": 0,
      "result": {
        "resultId": "1",
        "data": [0,0,2,6,0,0,3,4,4,2,1,4,7,7,8200,0,7,1,7,0,0,2,15,14,16384]
      }
    },
    legend).get == @[
      LspSemanticToken(
        line: 0,
        column: 0,
        length: 2,
        tokenType: 6,
        tokenModifiers: @[]),
      LspSemanticToken(
        line: 0,
        column: 3,
        length: 4,
        tokenType: 4,
        tokenModifiers: @[1]),
      LspSemanticToken(
        line: 1,
        column: 4,
        length: 7,
        tokenType: 7,
        tokenModifiers: @[3, 13]),
      LspSemanticToken(
        line: 1,
        column: 11,
        length: 1,
        tokenType: 7,
        tokenModifiers: @[]),
      LspSemanticToken(
        line: 1,
        column: 13,
        length: 15,
        tokenType: 14,
        tokenModifiers: @[14])
    ]
