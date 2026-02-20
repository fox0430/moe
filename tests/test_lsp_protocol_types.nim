#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

import ../src/moepkg/lsp/protocol/types

suite "types - Position":
  test "newPosition":
    let pos = newPosition(10, 5)
    check pos.line == 10
    check pos.character == 5

  test "Position default values":
    let pos = Position()
    check pos.line == 0
    check pos.character == 0

  test "Position toJson":
    let pos = newPosition(1, 2)
    let j = pos.toJson
    check j["line"].getInt == 1
    check j["character"].getInt == 2

  test "parsePosition":
    let j = %*{"line": 3, "character": 7}
    let pos = parsePosition(j)
    check pos.line == 3
    check pos.character == 7

suite "types - Range":
  test "newRange with line and char args":
    let r = newRange(1, 2, 3, 4)
    check r.start.line == 1
    check r.start.character == 2
    check r.`end`.line == 3
    check r.`end`.character == 4

  test "newRange with Position args":
    let s = newPosition(0, 0)
    let e = newPosition(10, 20)
    let r = newRange(s, e)
    check r.start == s
    check r.`end` == e

  test "Range toJson":
    let r = newRange(1, 2, 3, 4)
    let j = r.toJson
    check j["start"]["line"].getInt == 1
    check j["start"]["character"].getInt == 2
    check j["end"]["line"].getInt == 3
    check j["end"]["character"].getInt == 4

  test "parseRange":
    let j =
      %*{"start": {"line": 0, "character": 5}, "end": {"line": 10, "character": 15}}
    let r = parseRange(j)
    check r.start.line == 0
    check r.start.character == 5
    check r.`end`.line == 10
    check r.`end`.character == 15

suite "types - Location":
  test "Location construction":
    let loc = Location(uri: "file:///test.nim", range: newRange(1, 0, 1, 10))
    check loc.uri == "file:///test.nim"
    check loc.range.start.line == 1

  test "Location toJson":
    let loc = Location(uri: "file:///test.nim", range: newRange(0, 0, 0, 5))
    let j = loc.toJson
    check j["uri"].getStr == "file:///test.nim"
    check j["range"]["start"]["line"].getInt == 0

  test "parseLocation":
    let j = %*{
      "uri": "file:///foo.nim",
      "range":
        {"start": {"line": 2, "character": 3}, "end": {"line": 2, "character": 10}},
    }
    let loc = parseLocation(j)
    check loc.uri == "file:///foo.nim"
    check loc.range.start.line == 2
    check loc.range.start.character == 3

suite "types - TextDocumentIdentifier":
  test "newTextDocumentIdentifier":
    let tdi = newTextDocumentIdentifier("file:///test.nim")
    check tdi.uri == "file:///test.nim"

  test "TextDocumentIdentifier toJson":
    let tdi = newTextDocumentIdentifier("file:///test.nim")
    let j = tdi.toJson
    check j["uri"].getStr == "file:///test.nim"

suite "types - VersionedTextDocumentIdentifier":
  test "newVersionedTextDocumentIdentifier":
    let vtdi = newVersionedTextDocumentIdentifier("file:///test.nim", 3)
    check vtdi.uri == "file:///test.nim"
    check vtdi.version == 3

  test "VersionedTextDocumentIdentifier toJson":
    let vtdi = newVersionedTextDocumentIdentifier("file:///test.nim", 5)
    let j = vtdi.toJson
    check j["uri"].getStr == "file:///test.nim"
    check j["version"].getInt == 5

suite "types - TextDocumentItem":
  test "newTextDocumentItem":
    let item = newTextDocumentItem("file:///test.nim", "nim", 1, "echo 1")
    check item.uri == "file:///test.nim"
    check item.languageId == "nim"
    check item.version == 1
    check item.text == "echo 1"

  test "TextDocumentItem toJson":
    let item = newTextDocumentItem("file:///t.nim", "nim", 2, "code")
    let j = item.toJson
    check j["uri"].getStr == "file:///t.nim"
    check j["languageId"].getStr == "nim"
    check j["version"].getInt == 2
    check j["text"].getStr == "code"

suite "types - TextEdit":
  test "TextEdit construction":
    let edit = TextEdit(range: newRange(0, 0, 0, 5), newText: "hello")
    check edit.newText == "hello"
    check edit.range.start.line == 0

  test "parseTextEdit":
    let j = %*{
      "range":
        {"start": {"line": 1, "character": 0}, "end": {"line": 1, "character": 3}},
      "newText": "world",
    }
    let edit = parseTextEdit(j)
    check edit.newText == "world"
    check edit.range.start.line == 1
    check edit.range.`end`.character == 3

suite "types - parseLocations":
  test "parse single location object":
    let j = %*{
      "uri": "file:///a.nim",
      "range":
        {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 5}},
    }
    let locs = parseLocations(j)
    check locs.len == 1
    check locs[0].uri == "file:///a.nim"

  test "parse location array":
    let j = %*[
      {
        "uri": "file:///a.nim",
        "range":
          {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 5}},
      },
      {
        "uri": "file:///b.nim",
        "range":
          {"start": {"line": 1, "character": 0}, "end": {"line": 1, "character": 3}},
      },
    ]
    let locs = parseLocations(j)
    check locs.len == 2
    check locs[0].uri == "file:///a.nim"
    check locs[1].uri == "file:///b.nim"

  test "parse non-object non-array returns empty":
    let j = newJString("not a location")
    let locs = parseLocations(j)
    check locs.len == 0

suite "types - LocationLink":
  test "parseLocationLink":
    let j = %*{
      "targetUri": "file:///target.nim",
      "targetRange":
        {"start": {"line": 5, "character": 0}, "end": {"line": 10, "character": 0}},
      "targetSelectionRange":
        {"start": {"line": 5, "character": 4}, "end": {"line": 5, "character": 10}},
    }
    let link = parseLocationLink(j)
    check link.targetUri == "file:///target.nim"
    check link.targetRange.start.line == 5
    check link.targetSelectionRange.start.character == 4
    check link.originSelectionRange.isNone

  test "locationLinkToLocation":
    let link = LocationLink(
      targetUri: "file:///t.nim",
      targetRange: newRange(0, 0, 10, 0),
      targetSelectionRange: newRange(5, 4, 5, 10),
    )
    let loc = locationLinkToLocation(link)
    check loc.uri == "file:///t.nim"
    check loc.range == link.targetSelectionRange

suite "types - Diagnostic parsing":
  test "parseDiagnostic basic":
    let j = %*{
      "range":
        {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 5}},
      "message": "error here",
    }
    let diag = parseDiagnostic(j)
    check diag.message == "error here"
    check diag.range.start.line == 0
    check diag.severity.isNone

  test "parseDiagnostic with severity":
    let j = %*{
      "range":
        {"start": {"line": 1, "character": 0}, "end": {"line": 1, "character": 10}},
      "message": "warning",
      "severity": 2,
    }
    let diag = parseDiagnostic(j)
    check diag.severity.isSome
    check diag.severity.get == dsWarning

suite "types - SemanticTokens":
  test "decodeSemanticTokens":
    # Encoded: deltaLine=0, deltaStart=0, length=5, tokenType=0, tokenModifiers=0
    #          deltaLine=0, deltaStart=10, length=3, tokenType=1, tokenModifiers=1
    let tokens = SemanticTokens(data: @[0, 0, 5, 0, 0, 0, 10, 3, 1, 1])
    let decoded = decodeSemanticTokens(tokens)
    check decoded.len == 2
    check decoded[0].line == 0
    check decoded[0].startChar == 0
    check decoded[0].length == 5
    check decoded[0].tokenType == 0
    check decoded[1].line == 0
    check decoded[1].startChar == 10
    check decoded[1].length == 3
    check decoded[1].tokenType == 1
    check decoded[1].tokenModifiers == 1

  test "decodeSemanticTokens with line change":
    # deltaLine=1 means next line
    let tokens = SemanticTokens(data: @[0, 0, 5, 0, 0, 1, 3, 2, 1, 0])
    let decoded = decodeSemanticTokens(tokens)
    check decoded.len == 2
    check decoded[0].line == 0
    check decoded[1].line == 1
    check decoded[1].startChar == 3

  test "decodeSemanticTokens empty":
    let tokens = SemanticTokens(data: @[])
    let decoded = decodeSemanticTokens(tokens)
    check decoded.len == 0

  test "decodeSemanticTokens invalid length":
    let tokens = SemanticTokens(data: @[1, 2, 3])
    let decoded = decodeSemanticTokens(tokens)
    check decoded.len == 0

suite "types - toSemanticTokenType":
  test "known type name":
    let result = toSemanticTokenType("function")
    check result.isSome
    check result.get == sttFunction

  test "unknown type name":
    let result = toSemanticTokenType("unknown_type")
    check result.isNone

suite "types - toSemanticTokenModifier":
  test "known modifier name":
    let result = toSemanticTokenModifier("readonly")
    check result.isSome
    check result.get == stmReadonly

  test "unknown modifier name":
    let result = toSemanticTokenModifier("not_a_modifier")
    check result.isNone

suite "types - FoldingRange parsing":
  test "parseFoldingRange basic":
    let j = %*{"startLine": 5, "endLine": 10}
    let fr = parseFoldingRange(j)
    check fr.startLine == 5
    check fr.endLine == 10
    check fr.kind.isNone

  test "parseFoldingRange with kind":
    let j = %*{"startLine": 0, "endLine": 3, "kind": "comment"}
    let fr = parseFoldingRange(j)
    check fr.kind.isSome
    check fr.kind.get == frkComment

  test "parseFoldingRangeKind":
    check parseFoldingRangeKind("comment").get == frkComment
    check parseFoldingRangeKind("imports").get == frkImports
    check parseFoldingRangeKind("region").get == frkRegion
    check parseFoldingRangeKind("unknown").isNone
