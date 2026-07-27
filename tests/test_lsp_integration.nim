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

import
  std/[
    unittest, json, options, os, tables, times, strutils, importutils, deques, random,
    unicode,
  ]

import pkg/results

import ../src/moepkg/[lsp_integration, buffer, message_log, unicode_utils]
import ../src/moepkg/lsp/protocol/types

let tmpDir = getTempDir()

suite "LspIntegration - UTF-16/UTF-8 Conversion":
  test "utf16OffsetToUtf8 with ASCII text":
    let line = "hello world"
    check utf16OffsetToUtf8(line, 0) == 0
    check utf16OffsetToUtf8(line, 5) == 5
    check utf16OffsetToUtf8(line, 11) == 11

  test "utf16OffsetToUtf8 with empty string":
    check utf16OffsetToUtf8("", 0) == 0
    check utf16OffsetToUtf8("", 5) == 0

  test "utf16OffsetToUtf8 with negative offset":
    check utf16OffsetToUtf8("hello", -1) == 0

  test "utf16OffsetToUtf8 with Japanese text (BMP characters)":
    # Japanese characters are in BMP, 1 UTF-16 code unit each
    # But 3 UTF-8 bytes each
    let line = "こんにちは" # 5 characters, 15 UTF-8 bytes
    check utf16OffsetToUtf8(line, 0) == 0
    check utf16OffsetToUtf8(line, 1) == 3 # After first character
    check utf16OffsetToUtf8(line, 2) == 6 # After second character
    check utf16OffsetToUtf8(line, 5) == 15 # After all characters

  test "utf16OffsetToUtf8 with mixed ASCII and Japanese":
    let line = "aあb" # 'a' (1 byte), 'あ' (3 bytes), 'b' (1 byte) = 5 bytes
    check utf16OffsetToUtf8(line, 0) == 0 # Start
    check utf16OffsetToUtf8(line, 1) == 1 # After 'a'
    check utf16OffsetToUtf8(line, 2) == 4 # After 'あ'
    check utf16OffsetToUtf8(line, 3) == 5 # After 'b'

  test "utf16OffsetToUtf8 with emoji (surrogate pairs)":
    # Emoji like 😀 (U+1F600) uses 2 UTF-16 code units (surrogate pair)
    # and 4 UTF-8 bytes
    let line = "a😀b" # 'a' (1), '😀' (4), 'b' (1) = 6 bytes
    check utf16OffsetToUtf8(line, 0) == 0 # Start
    check utf16OffsetToUtf8(line, 1) == 1 # After 'a'
    check utf16OffsetToUtf8(line, 3) == 5 # After emoji (2 UTF-16 units)
    check utf16OffsetToUtf8(line, 4) == 6 # After 'b'

  test "utf8OffsetToUtf16 with ASCII text":
    let line = "hello world"
    check utf8OffsetToUtf16(line, 0) == 0
    check utf8OffsetToUtf16(line, 5) == 5
    check utf8OffsetToUtf16(line, 11) == 11

  test "utf8OffsetToUtf16 with empty string":
    check utf8OffsetToUtf16("", 0) == 0
    check utf8OffsetToUtf16("", 5) == 0

  test "utf8OffsetToUtf16 with negative offset":
    check utf8OffsetToUtf16("hello", -1) == 0

  test "utf8OffsetToUtf16 with Japanese text":
    let line = "こんにちは" # 5 characters, 15 UTF-8 bytes, 5 UTF-16 units
    check utf8OffsetToUtf16(line, 0) == 0
    check utf8OffsetToUtf16(line, 3) == 1 # After first character (3 bytes)
    check utf8OffsetToUtf16(line, 6) == 2 # After second character
    check utf8OffsetToUtf16(line, 15) == 5 # After all

  test "utf8OffsetToUtf16 with emoji (surrogate pairs)":
    let line = "a😀b" # 'a' (1), '😀' (4), 'b' (1) = 6 bytes
    check utf8OffsetToUtf16(line, 0) == 0 # Start
    check utf8OffsetToUtf16(line, 1) == 1 # After 'a'
    check utf8OffsetToUtf16(line, 5) == 3 # After emoji (counts as 2 UTF-16 units)
    check utf8OffsetToUtf16(line, 6) == 4 # After 'b'

  test "roundtrip UTF-16 -> UTF-8 -> UTF-16 (ASCII only)":
    # Roundtrip only works correctly for non-surrogate-pair positions
    # For surrogate pairs, the middle position (odd offset) doesn't roundtrip
    let line = "hello"
    for utf16Pos in 0 .. 5:
      let utf8Pos = utf16OffsetToUtf8(line, utf16Pos)
      let backToUtf16 = utf8OffsetToUtf16(line, utf8Pos)
      check backToUtf16 == utf16Pos

  test "roundtrip UTF-16 -> UTF-8 -> UTF-16 (BMP characters)":
    # BMP characters (1 UTF-16 unit each) roundtrip correctly
    let line = "世界"
    for utf16Pos in 0 .. 2:
      let utf8Pos = utf16OffsetToUtf8(line, utf16Pos)
      let backToUtf16 = utf8OffsetToUtf16(line, utf8Pos)
      check backToUtf16 == utf16Pos

  test "roundtrip UTF-8 -> UTF-16 -> UTF-8 at valid byte boundaries":
    let line = "hello世界🌍end"
    # "hello" = 5 bytes, "世" = 3, "界" = 3, "🌍" = 4, "end" = 3.
    for utf8Offset in [0, 5, 8, 11, 15, 18]:
      let utf16 = utf8OffsetToUtf16(line, utf8Offset)
      check utf16OffsetToUtf8(line, utf16) == utf8Offset

  test "runeIndexToUtf16 with empty string":
    check runeIndexToUtf16("", 0) == 0
    check runeIndexToUtf16("", 5) == 0

  test "runeIndexToUtf16 with ASCII":
    let line = "hello world"
    check runeIndexToUtf16(line, 0) == 0
    check runeIndexToUtf16(line, 5) == 5
    check runeIndexToUtf16(line, 11) == 11

  test "runeIndexToUtf16 with BMP characters":
    # Each hiragana is 1 rune = 1 UTF-16 unit = 3 UTF-8 bytes.
    let line = "こんにちは"
    check runeIndexToUtf16(line, 0) == 0
    check runeIndexToUtf16(line, 1) == 1
    check runeIndexToUtf16(line, 5) == 5

  test "runeIndexToUtf16 with mixed ASCII and Japanese":
    let line = "ABCあいう"
    check runeIndexToUtf16(line, 3) == 3
    check runeIndexToUtf16(line, 4) == 4
    check runeIndexToUtf16(line, 6) == 6

  test "runeIndexToUtf16 with surrogate pairs":
    let line = "a😀b"
    check runeIndexToUtf16(line, 0) == 0
    check runeIndexToUtf16(line, 1) == 1
    check runeIndexToUtf16(line, 2) == 3 # After emoji (2 UTF-16 units)
    check runeIndexToUtf16(line, 3) == 4

  test "runeIndexToUtf16 clamps to line length":
    check runeIndexToUtf16("abc", 100) == 3
    check runeIndexToUtf16("a😀b", 100) == 4

  test "utf16ToRuneIndex with empty string":
    check utf16ToRuneIndex("", 0) == 0
    check utf16ToRuneIndex("", 5) == 0

  test "utf16ToRuneIndex with ASCII":
    let line = "hello"
    check utf16ToRuneIndex(line, 0) == 0
    check utf16ToRuneIndex(line, 3) == 3
    check utf16ToRuneIndex(line, 5) == 5

  test "utf16ToRuneIndex with BMP characters":
    let line = "こんにちは"
    check utf16ToRuneIndex(line, 0) == 0
    check utf16ToRuneIndex(line, 2) == 2
    check utf16ToRuneIndex(line, 5) == 5

  test "utf16ToRuneIndex with surrogate pairs":
    let line = "a😀b"
    check utf16ToRuneIndex(line, 0) == 0
    check utf16ToRuneIndex(line, 1) == 1
    check utf16ToRuneIndex(line, 3) == 2 # After emoji (2 UTF-16 units)
    check utf16ToRuneIndex(line, 4) == 3

  test "utf16ToRuneIndex clamps to rune count":
    check utf16ToRuneIndex("abc", 100) == 3
    check utf16ToRuneIndex("a😀b", 100) == 3

  test "rune/UTF-16 roundtrip":
    let line = "hello世界🌍end"
    # Rune indexes: h(0) e(1) l(2) l(3) o(4) 世(5) 界(6) 🌍(7) e(8) n(9) d(10).
    for runeIndex in [0, 3, 5, 6, 7, 8, 11]:
      let utf16 = runeIndexToUtf16(line, runeIndex)
      check utf16ToRuneIndex(line, utf16) == runeIndex

suite "LspIntegration - Status Text":
  test "getStatusText returns empty for ok and quiescent":
    let state = LspStatusState(health: shOk, quiescent: true, message: none(string))
    check getStatusText(state) == ""

  test "getStatusText returns Loading when not quiescent":
    let state = LspStatusState(health: shOk, quiescent: false, message: none(string))
    check getStatusText(state) == "Loading"

  test "getStatusText returns Warning for warning health":
    let state =
      LspStatusState(health: shWarning, quiescent: true, message: none(string))
    check getStatusText(state) == "Warning"

  test "getStatusText returns Error for error health":
    let state = LspStatusState(health: shError, quiescent: true, message: none(string))
    check getStatusText(state) == "Error"

  test "getStatusText includes message":
    let state = LspStatusState(
      health: shWarning, quiescent: true, message: some("Something wrong")
    )
    check getStatusText(state) == "Warning: Something wrong"

  test "getStatusText Loading with message":
    let state =
      LspStatusState(health: shOk, quiescent: false, message: some("Indexing..."))
    check getStatusText(state) == "Loading: Indexing..."

suite "LspIntegration - Progress Text":
  test "getProgressText with title only":
    let state = LspProgressState(
      token: "1",
      langId: "nim",
      title: "Indexing",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: 0.0,
    )
    check getProgressText(state) == "Indexing"

  test "getProgressText with message":
    let state = LspProgressState(
      token: "1",
      langId: "nim",
      title: "Indexing",
      message: some("src/main.nim"),
      percentage: none(int),
      cancellable: false,
      startTime: 0.0,
    )
    check getProgressText(state) == "Indexing: src/main.nim"

  test "getProgressText with percentage":
    let state = LspProgressState(
      token: "1",
      langId: "nim",
      title: "Indexing",
      message: none(string),
      percentage: some(50),
      cancellable: false,
      startTime: 0.0,
    )
    check getProgressText(state) == "Indexing (50%)"

  test "getProgressText with message and percentage":
    let state = LspProgressState(
      token: "1",
      langId: "nim",
      title: "Indexing",
      message: some("file.nim"),
      percentage: some(75),
      cancellable: false,
      startTime: 0.0,
    )
    check getProgressText(state) == "Indexing: file.nim (75%)"

  test "getProgressText truncates long text":
    let state = LspProgressState(
      token: "1",
      langId: "nim",
      title: "Very Long Title That Should Be Truncated",
      message: some("Even longer message that definitely exceeds the limit"),
      percentage: some(99),
      cancellable: false,
      startTime: 0.0,
    )
    let text = getProgressText(state)
    check text.len <= MaxProgressTextLen

  test "getProgressText truncates long full-width text by display width":
    let state = LspProgressState(
      token: "1",
      langId: "nim",
      title: "とても長いタイトルで切り詰められるはず",
      message: some(
        "これはさらに長いメッセージで上限を確実に超える内容です"
      ),
      percentage: some(99),
      cancellable: false,
      startTime: 0.0,
    )
    let text = getProgressText(state)
    check displayWidthUpTo(text, text.runeLen) <= MaxProgressTextLen

suite "LspIntegration - Hover Text":
  test "getHoverText with string content":
    let hover = Hover(contents: %"Simple hover text")
    check getHoverText(hover) == "Simple hover text"

  test "getHoverText with MarkupContent":
    let hover = Hover(contents: %*{"kind": "markdown", "value": "**bold** text"})
    check getHoverText(hover) == "**bold** text"

  test "getHoverText with array of strings":
    let hover = Hover(contents: %*["line1", "line2", "line3"])
    check getHoverText(hover) == "line1\nline2\nline3"

  test "getHoverText with array of MarkedString objects":
    let hover = Hover(
      contents:
        %*[{"language": "nim", "value": "proc foo()"}, {"value": "Documentation"}]
    )
    check "proc foo()" in getHoverText(hover)
    check "Documentation" in getHoverText(hover)

  test "getHoverText with empty content":
    let hover = Hover(contents: newJNull())
    check getHoverText(hover) == ""

suite "LspIntegration - Signature Help":
  test "getSignatureHelpText with single signature":
    let sigHelp = SignatureHelp(
      signatures: @[
        SignatureInformation(
          label: "proc foo(a: int, b: string): bool",
          documentation: none(JsonNode),
          parameters: none(seq[ParameterInformation]),
          activeParameter: none(int),
        )
      ],
      activeSignature: some(0),
      activeParameter: none(int),
    )
    check getSignatureHelpText(sigHelp) == "proc foo(a: int, b: string): bool"

  test "getSignatureHelpText with documentation":
    let sigHelp = SignatureHelp(
      signatures: @[
        SignatureInformation(
          label: "proc bar()",
          documentation: some(%"This is the documentation"),
          parameters: none(seq[ParameterInformation]),
          activeParameter: none(int),
        )
      ],
      activeSignature: some(0),
      activeParameter: none(int),
    )
    let text = getSignatureHelpText(sigHelp)
    check "proc bar()" in text
    check "This is the documentation" in text

  test "getSignatureHelpText with no signatures":
    let sigHelp = SignatureHelp(
      signatures: @[], activeSignature: none(int), activeParameter: none(int)
    )
    check getSignatureHelpText(sigHelp) == ""

  test "getActiveParameterIndex from top level":
    let sigHelp = SignatureHelp(
      signatures: @[
        SignatureInformation(
          label: "foo(a, b, c)",
          documentation: none(JsonNode),
          parameters: none(seq[ParameterInformation]),
          activeParameter: none(int),
        )
      ],
      activeSignature: some(0),
      activeParameter: some(2),
    )
    check getActiveParameterIndex(sigHelp) == 2

  test "getActiveParameterIndex from signature":
    let sigHelp = SignatureHelp(
      signatures: @[
        SignatureInformation(
          label: "foo(a, b)",
          documentation: none(JsonNode),
          parameters: none(seq[ParameterInformation]),
          activeParameter: some(1),
        )
      ],
      activeSignature: some(0),
      activeParameter: none(int),
    )
    check getActiveParameterIndex(sigHelp) == 1

  test "getActiveParameterIndex defaults to 0":
    let sigHelp = SignatureHelp(
      signatures: @[
        SignatureInformation(
          label: "foo()",
          documentation: none(JsonNode),
          parameters: none(seq[ParameterInformation]),
          activeParameter: none(int),
        )
      ],
      activeSignature: some(0),
      activeParameter: none(int),
    )
    check getActiveParameterIndex(sigHelp) == 0

  test "getParameterInfo with parameters":
    let sigHelp = SignatureHelp(
      signatures: @[
        SignatureInformation(
          label: "foo(a: int, b: string)",
          documentation: none(JsonNode),
          parameters: some(
            @[
              ParameterInformation(label: "a: int", documentation: none(JsonNode)),
              ParameterInformation(label: "b: string", documentation: none(JsonNode)),
            ]
          ),
          activeParameter: none(int),
        )
      ],
      activeSignature: some(0),
      activeParameter: some(1),
    )
    let info = getParameterInfo(sigHelp)
    check info.label == "foo(a: int, b: string)"
    check info.start >= 0
    check info.stop > info.start

  test "getParameterInfo disambiguates substring-collision labels":
    let label = "sum(count: int, c: int)"
    let sigHelp = SignatureHelp(
      signatures: @[
        SignatureInformation(
          label: label,
          documentation: none(JsonNode),
          parameters: some(
            @[
              ParameterInformation(label: "count: int", documentation: none(JsonNode)),
              ParameterInformation(label: "c: int", documentation: none(JsonNode)),
            ]
          ),
          activeParameter: none(int),
        )
      ],
      activeSignature: some(0),
      activeParameter: some(1),
    )
    let info = getParameterInfo(sigHelp)
    check label[info.start ..< info.stop] == "c: int"
    check info.start == label.rfind("c: int")

  test "getParameterInfo honors labelOffsets when provided":
    let label = "foo(a: int, b: string)"
    let sigHelp = SignatureHelp(
      signatures: @[
        SignatureInformation(
          label: label,
          documentation: none(JsonNode),
          parameters: some(
            @[
              ParameterInformation(
                labelOffsets: some((start: 4, stop: 10)), documentation: none(JsonNode)
              ),
              ParameterInformation(
                labelOffsets: some((start: 12, stop: 21)), documentation: none(JsonNode)
              ),
            ]
          ),
          activeParameter: none(int),
        )
      ],
      activeSignature: some(0),
      activeParameter: some(1),
    )
    let info = getParameterInfo(sigHelp)
    check info.start == 12
    check info.stop == 21
    check label[info.start ..< info.stop] == "b: string"

suite "LspIntegration - newLspIntegration":
  privateAccess(LspIntegration)

  test "creates integration with default workspace":
    let lsp = newLspIntegration()
    check lsp.enabled
    check lsp.documents.len == 0
    check lsp.pendingMessages.len == 0
    check lsp.activeProgress.len == 0

  test "creates integration with custom workspace":
    let lsp = newLspIntegration(tmpDir / "test")
    check lsp.enabled

suite "LspIntegration - Message Management":
  privateAccess(LspIntegration)

  test "getAndClearMessages returns and clears messages":
    let lsp = newLspIntegration()
    lsp.pendingMessages = @["msg1", "msg2", "msg3"]

    let msgs = lsp.getAndClearMessages()
    check msgs == @["msg1", "msg2", "msg3"]
    check lsp.pendingMessages.len == 0

  test "getAndClearMessages with empty messages":
    let lsp = newLspIntegration()
    let msgs = lsp.getAndClearMessages()
    check msgs.len == 0

suite "LspIntegration - Progress Management":
  privateAccess(LspIntegration)

  test "hasActiveProgress with no progress":
    let lsp = newLspIntegration()
    check not lsp.hasActiveProgress()

  test "getActiveProgressList with no progress":
    let lsp = newLspIntegration()
    check lsp.getActiveProgressList().len == 0

  test "hasActiveProgress with progress":
    let lsp = newLspIntegration()
    lsp.activeProgress["token1"] = LspProgressState(
      token: "token1",
      langId: "nim",
      title: "Test",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: epochTime(),
    )
    check lsp.hasActiveProgress()

  test "getActiveProgressList returns all progress":
    let lsp = newLspIntegration()
    lsp.activeProgress["token1"] = LspProgressState(
      token: "token1",
      langId: "nim",
      title: "Task1",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: 1.0,
    )
    lsp.activeProgress["token2"] = LspProgressState(
      token: "token2",
      langId: "rust",
      title: "Task2",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: 2.0,
    )

    let list = lsp.getActiveProgressList()
    check list.len == 2

  test "getLatestActiveProgress returns most recent":
    let lsp = newLspIntegration()
    lsp.activeProgress["token1"] = LspProgressState(
      token: "token1",
      langId: "nim",
      title: "Old",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: 1.0,
    )
    lsp.activeProgress["token2"] = LspProgressState(
      token: "token2",
      langId: "rust",
      title: "New",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: 10.0,
    )

    let latest = lsp.getLatestActiveProgress()
    check latest.isSome
    check latest.get.title == "New"

  test "getLatestActiveProgress with no progress":
    let lsp = newLspIntegration()
    check lsp.getLatestActiveProgress().isNone

  test "clearProgressForLanguage removes matching progress":
    let lsp = newLspIntegration()
    lsp.activeProgress["token1"] = LspProgressState(
      token: "token1",
      langId: "nim",
      title: "Nim Task",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: 1.0,
    )
    lsp.activeProgress["token2"] = LspProgressState(
      token: "token2",
      langId: "rust",
      title: "Rust Task",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: 2.0,
    )

    lsp.clearProgressForLanguage("nim")
    check lsp.activeProgress.len == 1
    check "token2" in lsp.activeProgress

suite "LspIntegration - Server Status Management":
  privateAccess(LspIntegration)

  test "getServerStatus with no status":
    let lsp = newLspIntegration()
    check lsp.getServerStatus("nim").isNone

  test "getServerStatus with status":
    let lsp = newLspIntegration()
    lsp.serverStatus["nim"] =
      LspStatusState(health: shOk, quiescent: true, message: none(string))

    let status = lsp.getServerStatus("nim")
    check status.isSome
    check status.get.health == shOk
    check status.get.quiescent

  test "hasServerStatus":
    let lsp = newLspIntegration()
    check not lsp.hasServerStatus("nim")

    lsp.serverStatus["nim"] =
      LspStatusState(health: shOk, quiescent: true, message: none(string))
    check lsp.hasServerStatus("nim")

  test "isServerQuiescent defaults to true":
    let lsp = newLspIntegration()
    check lsp.isServerQuiescent("nim")

  test "isServerQuiescent with status":
    let lsp = newLspIntegration()
    lsp.serverStatus["nim"] =
      LspStatusState(health: shOk, quiescent: false, message: none(string))
    check not lsp.isServerQuiescent("nim")

  test "getServerHealth defaults to ok":
    let lsp = newLspIntegration()
    check lsp.getServerHealth("nim") == shOk

  test "getServerHealth with status":
    let lsp = newLspIntegration()
    lsp.serverStatus["nim"] =
      LspStatusState(health: shError, quiescent: true, message: none(string))
    check lsp.getServerHealth("nim") == shError

  test "clearStatusForLanguage":
    let lsp = newLspIntegration()
    lsp.serverStatus["nim"] =
      LspStatusState(health: shOk, quiescent: true, message: none(string))
    lsp.serverStatus["rust"] =
      LspStatusState(health: shOk, quiescent: true, message: none(string))

    lsp.clearStatusForLanguage("nim")
    check not lsp.hasServerStatus("nim")
    check lsp.hasServerStatus("rust")

suite "LspIntegration - Enable/Disable":
  test "isEnabled returns initial state":
    let lsp = newLspIntegration()
    check lsp.isEnabled()

  test "setEnabled changes state":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    check not lsp.isEnabled()

    lsp.setEnabled(true)
    check lsp.isEnabled()

suite "LspIntegration - applyTextEdits":
  test "applyTextEdits with empty edits":
    let buffer = newTextBuffer("hello world")
    let edits: seq[TextEdit] = @[]
    let result = applyTextEdits(buffer, edits)
    check result.isOk
    check buffer.getLine(0) == "hello world"

  test "applyTextEdits insert at beginning":
    let buffer = newTextBuffer("world")
    let edits = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 0)
        ),
        newText: "hello ",
      )
    ]
    let result = applyTextEdits(buffer, edits)
    check result.isOk
    check buffer.getLine(0) == "hello world"

  test "applyTextEdits replace text":
    let buffer = newTextBuffer("hello world")
    let edits = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 5)
        ),
        newText: "hi",
      )
    ]
    let result = applyTextEdits(buffer, edits)
    check result.isOk
    check buffer.getLine(0) == "hi world"

  test "applyTextEdits delete text":
    let buffer = newTextBuffer("hello world")
    let edits = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 5),
          `end`: Position(line: 0, character: 11),
        ),
        newText: "",
      )
    ]
    let result = applyTextEdits(buffer, edits)
    check result.isOk
    check buffer.getLine(0) == "hello"

  test "applyTextEdits skips malformed range where end=(0,0) and start>end":
    let buffer = newTextBuffer("hello world")
    let edits = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 5), `end`: Position(line: 0, character: 0)
        ),
        newText: "",
      )
    ]
    let result = applyTextEdits(buffer, edits)
    check result.isOk
    check buffer.getLine(0) == "hello world"

  test "applyTextEdits multiple edits in reverse order":
    let buffer = newTextBuffer("abc")
    let edits = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 1)
        ),
        newText: "A",
      ),
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 2), `end`: Position(line: 0, character: 3)
        ),
        newText: "C",
      ),
    ]
    let result = applyTextEdits(buffer, edits)
    check result.isOk
    check buffer.getLine(0) == "AbC"

  test "applyTextEdits with multiline buffer":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let edits = @[
      TextEdit(
        range: Range(
          start: Position(line: 1, character: 0), `end`: Position(line: 1, character: 5)
        ),
        newText: "modified",
      )
    ]
    let result = applyTextEdits(buffer, edits)
    check result.isOk
    check buffer.getLine(1) == "modified"

  test "applyTextEdits insert at end":
    let buffer = newTextBuffer("hello")
    let edits = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 5), `end`: Position(line: 0, character: 5)
        ),
        newText: " world",
      )
    ]
    let result = applyTextEdits(buffer, edits)
    check result.isOk
    check buffer.getLine(0) == "hello world"

  test "applyTextEdits creates single undo entry when called standalone":
    # Regression: applyTextEdits used to push one undo entry per inner edit when
    # invoked outside an existing transaction. A standalone caller (e.g. format
    # on save) had to press Ctrl-r/u once per edit to revert a single format.
    let buffer = newTextBuffer("abc")
    let edits = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 1)
        ),
        newText: "A",
      ),
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 2), `end`: Position(line: 0, character: 3)
        ),
        newText: "C",
      ),
    ]
    let preStackLen = buffer.undoStack.len
    let r = applyTextEdits(buffer, edits)
    check r.isOk
    check buffer.getLine(0) == "AbC"
    check buffer.undoStack.len == preStackLen + 1

    let u = buffer.undo()
    check u.isOk
    check buffer.getLine(0) == "abc"
    check not buffer.isModified

  test "applyTextEdits joins existing outer transaction":
    # When the caller has already begun a transaction (Insert-mode completion,
    # workspace edit), applyTextEdits must not open its own and instead share
    # the outer one. The whole group still collapses to a single undo entry.
    let buffer = newTextBuffer("abc")
    discard buffer.beginTransaction("outer")
    let edits = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 1)
        ),
        newText: "A",
      )
    ]
    let r = applyTextEdits(buffer, edits)
    check r.isOk
    discard buffer.commitTransaction()
    check buffer.undoStack.len == 1
    check buffer.getLine(0) == "Abc"

  test "applyTextEdits rolls back on failure when self-managed":
    # An invalid TextEdit must leave the buffer at its pre-call state when
    # applyTextEdits owned the transaction.
    let buffer = newTextBuffer("abc")
    let edits = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 1)
        ),
        newText: "A",
      ),
      TextEdit(
        range: Range(
          start: Position(line: 99, character: 0),
          `end`: Position(line: 99, character: 1),
        ),
        newText: "X",
      ),
    ]
    let preLine = buffer.getLine(0)
    let r = applyTextEdits(buffer, edits)
    check r.isErr
    check buffer.getLine(0) == preLine
    check not buffer.isModified
    check buffer.undoStack.len == 0

  test "applyTextEdits same-position inserts keep array order":
    # Per LSP spec, multiple edits at the same position appear in the
    # document in array order: A then B => "AB", not "BA".
    let buffer = newTextBuffer("xy")
    let edits = @[
      TextEdit(range: newRange(0, 1, 0, 1), newText: "A"),
      TextEdit(range: newRange(0, 1, 0, 1), newText: "B"),
    ]
    let result = applyTextEdits(buffer, edits)
    check result.isOk
    check buffer.getTextString() == "xABy"

  test "applyTextEdits three same-position inserts keep array order":
    let buffer = newTextBuffer("()")
    let edits = @[
      TextEdit(range: newRange(0, 1, 0, 1), newText: "1"),
      TextEdit(range: newRange(0, 1, 0, 1), newText: "2"),
      TextEdit(range: newRange(0, 1, 0, 1), newText: "3"),
    ]
    let result = applyTextEdits(buffer, edits)
    check result.isOk
    check buffer.getTextString() == "(123)"

  test "applyTextEdits insert newline":
    let buffer = newTextBuffer("hello world")
    let edit = TextEdit(range: newRange(0, 5, 0, 5), newText: "\n")
    let result = applyTextEdits(buffer, @[edit])
    check result.isOk
    check buffer.len == 2
    check buffer.getLine(0) == "hello"
    check buffer.getLine(1) == " world"

  test "applyTextEdits with UTF-16 position handling":
    # "abc日本" - "abc" = 3 UTF-16 units, "日本" = 2 UTF-16 units.
    let buffer = newTextBuffer("abc日本")
    let edit = TextEdit(range: newRange(0, 3, 0, 5), newText: "XY")
    let result = applyTextEdits(buffer, @[edit])
    check result.isOk
    check buffer.getTextString() == "abcXY"

  test "applyTextEdits multibyte prefix (rune vs byte columns)":
    # Regression: treating UTF-16 offsets as byte offsets fails when the
    # rune index (1) differs from the UTF-8 byte offset (3).
    let buffer = newTextBuffer("あいうえお")
    let edit = TextEdit(range: newRange(0, 1, 0, 3), newText: "X")
    let result = applyTextEdits(buffer, @[edit])
    check result.isOk
    check buffer.getTextString() == "あXえお"

  test "applyTextEdits insertion after multibyte characters":
    let buffer = newTextBuffer("日本語abc")
    let edit = TextEdit(range: newRange(0, 3, 0, 3), newText: "X")
    let result = applyTextEdits(buffer, @[edit])
    check result.isOk
    check buffer.getTextString() == "日本語Xabc"

  test "applyTextEdits surrogate pair handling":
    # 😀 is 2 UTF-16 units but 1 rune.
    let buffer = newTextBuffer("a😀bc")
    let edit = TextEdit(range: newRange(0, 1, 0, 3), newText: "Z")
    let result = applyTextEdits(buffer, @[edit])
    check result.isOk
    check buffer.getTextString() == "aZbc"

  test "applyTextEdits end past EOF with character > 0":
    # Regression: server-reported end line past the last buffer line combined
    # with character > 0 used to pass buffer.len as an end line to deleteRange.
    let buffer = newTextBuffer("abc\ndef")
    let edit = TextEdit(range: newRange(0, 0, 5, 3), newText: "XYZ")
    let result = applyTextEdits(buffer, @[edit])
    check result.isOk
    check buffer.getTextString() == "XYZ"

  test "applyTextEdits end past EOF with character == 0":
    # Regression: end.line strictly greater than buffer.len also used to feed
    # an out-of-bounds line into deleteRange via the else branch.
    let buffer = newTextBuffer("abc\ndef")
    let edit = TextEdit(range: newRange(0, 0, 9, 0), newText: "Q")
    let result = applyTextEdits(buffer, @[edit])
    check result.isOk
    check buffer.getTextString() == "Q"

suite "LspIntegration - applyLspFoldingRanges":
  test "applyLspFoldingRanges with empty ranges":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ranges: seq[FoldingRange] = @[]
    let count = buffer.applyLspFoldingRanges(ranges)
    check count == 0

  test "applyLspFoldingRanges with single range":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    let ranges = @[
      FoldingRange(
        startLine: 0,
        startCharacter: none(int),
        endLine: 2,
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: none(string),
      )
    ]
    let count = buffer.applyLspFoldingRanges(ranges)
    check count == 1

  test "applyLspFoldingRanges skips invalid ranges":
    let buffer = newTextBuffer("line1\nline2")
    let ranges = @[
      FoldingRange(
        startLine: 5, # Out of bounds
        startCharacter: none(int),
        endLine: 10,
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: none(string),
      )
    ]
    let count = buffer.applyLspFoldingRanges(ranges)
    check count == 0

  test "applyLspFoldingRanges with startCollapsed":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    let ranges = @[
      FoldingRange(
        startLine: 0,
        startCharacter: none(int),
        endLine: 2,
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: none(string),
      )
    ]
    let count = buffer.applyLspFoldingRanges(ranges, startCollapsed = true)
    check count == 1
    check buffer.foldState.folds[0].collapsed

  test "applyLspFoldingRanges with multiple non-overlapping folds":
    let buffer = newTextBuffer("0\n1\n2\n3\n4\n5\n6\n7\n8\n9")
    let ranges = @[
      FoldingRange(
        startLine: 1,
        endLine: 2,
        startCharacter: none(int),
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: none(string),
      ),
      FoldingRange(
        startLine: 5,
        endLine: 7,
        startCharacter: none(int),
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: none(string),
      ),
    ]
    let count = buffer.applyLspFoldingRanges(ranges)
    check count == 2
    check buffer.foldState.folds.len == 2

  test "applyLspFoldingRanges preserves collapsedText":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    let ranges = @[
      FoldingRange(
        startLine: 1,
        endLine: 2,
        startCharacter: none(int),
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: some("{ ... }"),
      )
    ]
    let count = buffer.applyLspFoldingRanges(ranges)
    check count == 1
    check buffer.foldState.folds[0].collapsedText == some("{ ... }")

  test "applyLspFoldingRanges with clearExisting = false keeps prior folds":
    let buffer = newTextBuffer("0\n1\n2\n3\n4\n5\n6\n7")
    let ranges1 = @[
      FoldingRange(
        startLine: 0,
        endLine: 1,
        startCharacter: none(int),
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: none(string),
      )
    ]
    discard buffer.applyLspFoldingRanges(ranges1)
    check buffer.foldState.folds.len == 1

    let ranges2 = @[
      FoldingRange(
        startLine: 4,
        endLine: 6,
        startCharacter: none(int),
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: none(string),
      )
    ]
    let count = buffer.applyLspFoldingRanges(ranges2, clearExisting = false)
    check count == 1
    check buffer.foldState.folds.len == 2

  test "applyLspFoldingRanges preserves nested ranges":
    let buffer = newTextBuffer("0\n1\n2\n3\n4\n5")
    let ranges = @[
      FoldingRange(
        startLine: 0,
        endLine: 5,
        startCharacter: none(int),
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: none(string),
      ),
      FoldingRange(
        startLine: 1,
        endLine: 3,
        startCharacter: none(int),
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: none(string),
      ),
    ]
    let count = buffer.applyLspFoldingRanges(ranges)
    check count == 2
    check buffer.foldState.folds.len == 2

  test "applyLspFoldingRanges skips degenerate single-line ranges":
    let buffer = newTextBuffer("0\n1\n2\n3")
    let ranges = @[
      FoldingRange(
        startLine: 2,
        endLine: 2,
        startCharacter: none(int),
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: none(string),
      )
    ]
    let count = buffer.applyLspFoldingRanges(ranges)
    check count == 0
    check buffer.foldState.folds.len == 0

  test "applyLspFoldingRanges keeps manual folds, replaces lsp folds":
    let buffer = newTextBuffer("0\n1\n2\n3\n4\n5\n6\n7")
    check buffer.foldState.addFold(6, 7, source = fsManual) == true

    let rangesA = @[
      FoldingRange(
        startLine: 0,
        endLine: 2,
        startCharacter: none(int),
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: none(string),
      )
    ]
    check buffer.applyLspFoldingRanges(rangesA) == 1
    check buffer.foldState.folds.len == 2

    let rangesB = @[
      FoldingRange(
        startLine: 3,
        endLine: 4,
        startCharacter: none(int),
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: none(string),
      )
    ]
    check buffer.applyLspFoldingRanges(rangesB) == 1
    check buffer.foldState.folds.len == 2

    let manual = buffer.foldState.getFoldAt(6)
    check manual.isSome
    check manual.get.source == fsManual
    check buffer.foldState.getFoldAt(0).isNone
    check buffer.foldState.getFoldAt(3).isSome

suite "LspIntegration - Buffer Operations (disabled)":
  privateAccess(LspIntegration)

  test "onBufferOpen returns ok when disabled":
    let lsp = newLspIntegration()
    lsp.enabled = false
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.onBufferOpen(buffer)
    check result.isOk

  test "onBufferClose returns ok when disabled":
    let lsp = newLspIntegration()
    lsp.enabled = false
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.onBufferClose(buffer)
    check result.isOk

  test "onBufferChange returns ok when disabled":
    let lsp = newLspIntegration()
    lsp.enabled = false
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.onBufferChange(buffer)
    check result.isOk

  test "onBufferSave returns ok when disabled":
    let lsp = newLspIntegration()
    lsp.enabled = false
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.onBufferSave(buffer)
    check result.isOk

  test "onBufferOpen returns ok for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    let result = lsp.onBufferOpen(buffer)
    check result.isOk

  test "onBufferClose returns ok for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    let result = lsp.onBufferClose(buffer)
    check result.isOk

  test "onBufferSave returns ok for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    let result = lsp.onBufferSave(buffer)
    check result.isOk

suite "LspIntegration - Buffer Version Tracking":
  privateAccess(LspIntegration)

  # onBufferOpen below spawns a real worker thread (nim is configured by
  # default), so each test tears the integration down to join that thread and
  # avoid leaking worker threads / nimlangserver processes.
  var lsp: LspIntegration
  setup:
    lsp = newLspIntegration(tmpDir)
  teardown:
    lsp.shutdown()

  proc markReady(lsp: LspIntegration) =
    ## Pretend a server would receive the change so onBufferChange advances
    ## the version/shadow without a live worker.
    lsp.service.liveWorkerOverride = proc(path: string): bool =
      true

  test "didOpen starts at version 1":
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check lsp.onBufferOpen(buffer).isOk
    check lsp.sentDocumentVersion(tmpDir / "test.nim") == some(1)

  test "version increases monotonically on every change":
    lsp.markReady()
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check lsp.onBufferOpen(buffer).isOk
    for expected in [2, 3, 4]:
      # Mutate the content: an unchanged buffer is skipped as a no-op.
      check buffer.insertText(BufferPosition(line: 0, column: 0), "x").isOk
      check lsp.onBufferChange(buffer).isOk
      check lsp.sentDocumentVersion(tmpDir / "test.nim") == some(expected)

  test "version does not regress when changeSeq rolls back":
    # Undo rolls buffer.changeSeq back; the version sent to the server must
    # keep increasing regardless.
    lsp.markReady()
    let buffer = newTextBuffer("hello", some(tmpDir / "test.nim"))
    check lsp.onBufferOpen(buffer).isOk
    check buffer.insertText(BufferPosition(line: 0, column: 0), "x").isOk
    check lsp.onBufferChange(buffer).isOk
    let versionBeforeUndo = lsp.sentDocumentVersion(tmpDir / "test.nim").get
    check buffer.undo().isOk # changeSeq rolls back here
    check lsp.onBufferChange(buffer).isOk
    check lsp.sentDocumentVersion(tmpDir / "test.nim").get > versionBeforeUndo

  test "per-document tracking":
    lsp.markReady()
    let bufferA = newTextBuffer("a", some(tmpDir / "a.nim"))
    let bufferB = newTextBuffer("b", some(tmpDir / "b.nim"))
    check lsp.onBufferOpen(bufferA).isOk
    check lsp.onBufferOpen(bufferB).isOk
    check bufferA.insertText(BufferPosition(line: 0, column: 0), "x").isOk
    check lsp.onBufferChange(bufferA).isOk
    check bufferA.insertText(BufferPosition(line: 0, column: 0), "y").isOk
    check lsp.onBufferChange(bufferA).isOk
    check lsp.sentDocumentVersion(tmpDir / "a.nim") == some(3)
    check lsp.sentDocumentVersion(tmpDir / "b.nim") == some(1)

  test "version cleared on close":
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check lsp.onBufferOpen(buffer).isOk
    check lsp.onBufferClose(buffer).isOk
    check lsp.sentDocumentVersion(tmpDir / "test.nim").isNone

  test "change without open sends didOpen with version 1":
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check lsp.onBufferChange(buffer).isOk
    check lsp.sentDocumentVersion(tmpDir / "test.nim") == some(1)

  test "re-open on tracked path resets version (implicit didClose)":
    # Regression: :bdelete used to leave the path tracked, so a subsequent
    # onBufferOpen for the same path was a duplicate didOpen at version 1
    # while the server still held the previous higher version, causing later
    # didChange notifications to be dropped as stale.
    lsp.markReady()
    let buffer = newTextBuffer("hi", some(tmpDir / "reopen.nim"))
    check lsp.onBufferOpen(buffer).isOk
    for _ in 0 ..< 3:
      check buffer.insertText(BufferPosition(line: 0, column: 0), "x").isOk
      check lsp.onBufferChange(buffer).isOk
    check lsp.sentDocumentVersion(tmpDir / "reopen.nim") == some(4)

    check lsp.onBufferOpen(buffer).isOk
    check lsp.sentDocumentVersion(tmpDir / "reopen.nim") == some(1)

    check buffer.insertText(BufferPosition(line: 0, column: 0), "y").isOk
    check lsp.onBufferChange(buffer).isOk
    check lsp.sentDocumentVersion(tmpDir / "reopen.nim") == some(2)

  test "serverIsFresh skips defensive didClose on restart re-open":
    lsp.markReady()
    let buffer = newTextBuffer("hi", some(tmpDir / "restart.nim"))
    check lsp.onBufferOpen(buffer).isOk
    check buffer.insertText(BufferPosition(line: 0, column: 0), "x").isOk
    check lsp.onBufferChange(buffer).isOk
    check lsp.sentDocumentVersion(tmpDir / "restart.nim") == some(2)

    check lsp.onBufferOpen(buffer, serverIsFresh = true).isOk
    check lsp.sentDocumentVersion(tmpDir / "restart.nim") == some(1)

suite "LspIntegration - Path canonicalization":
  # Relative and absolute textual paths for the same file used to occupy
  # two `lsp.documents` entries with independent version counters, while
  # pathToUri collapsed both to one URI — later didChange got dropped.
  privateAccess(LspIntegration)

  var lsp: LspIntegration
  var origCwd: string
  setup:
    lsp = newLspIntegration(tmpDir)
    lsp.service.liveWorkerOverride = proc(path: string): bool =
      true
    origCwd = getCurrentDir()
    setCurrentDir(tmpDir)
  teardown:
    setCurrentDir(origCwd)
    lsp.shutdown()

  test "same file via relative and absolute path collapses to one document":
    let cwd = getCurrentDir()
    let relBuf = newTextBuffer("hi", some("canonical_rel.nim"))
    let absBuf = newTextBuffer("hi", some(cwd / "canonical_rel.nim"))
    check lsp.onBufferOpen(relBuf).isOk
    check lsp.onBufferOpen(absBuf).isOk
    check lsp.documents.len == 1

  test "sentDocumentVersion accepts either textual form of the same path":
    let cwd = getCurrentDir()
    let buffer = newTextBuffer("hi", some(cwd / "canonical_lookup.nim"))
    check lsp.onBufferOpen(buffer).isOk
    check lsp.sentDocumentVersion(cwd / "canonical_lookup.nim") == some(1)
    check lsp.sentDocumentVersion("canonical_lookup.nim") == some(1)

  test "version counter stays consistent across relative/absolute re-open":
    let cwd = getCurrentDir()
    let relBuf = newTextBuffer("hi", some("canonical_mono.nim"))
    check lsp.onBufferOpen(relBuf).isOk
    check relBuf.insertText(BufferPosition(line: 0, column: 0), "x").isOk
    check lsp.onBufferChange(relBuf).isOk
    check lsp.sentDocumentVersion(cwd / "canonical_mono.nim") == some(2)

    # Re-open via absolute path hits the same entry (didClose + reset to 1).
    let absBuf = newTextBuffer("hi", some(cwd / "canonical_mono.nim"))
    check lsp.onBufferOpen(absBuf).isOk
    check lsp.sentDocumentVersion("canonical_mono.nim") == some(1)
    check lsp.documents.len == 1

  test "onBufferClose via relative path clears entry opened via absolute":
    let cwd = getCurrentDir()
    let openBuf = newTextBuffer("hi", some(cwd / "canonical_close.nim"))
    check lsp.onBufferOpen(openBuf).isOk
    check lsp.documents.len == 1
    let closeBuf = newTextBuffer("hi", some("canonical_close.nim"))
    check lsp.onBufferClose(closeBuf).isOk
    check lsp.documents.len == 0

suite "LspIntegration - flushPendingBufferChange":
  privateAccess(LspIntegration)

  var lsp: LspIntegration
  setup:
    lsp = newLspIntegration(tmpDir)
    lsp.service.liveWorkerOverride = proc(path: string): bool =
      true
  teardown:
    lsp.shutdown()

  test "flush advances wire version when buffer drifted since last sync":
    # Regression: an out-of-band request (completion, hover) put a positional
    # request on the wire before the edit that produced its coordinates. The
    # explicit flush must bring the server up to date first.
    let path = tmpDir / "flush_drift.nim"
    let buffer = newTextBuffer("hi", some(path))
    check lsp.onBufferOpen(buffer).isOk
    check lsp.sentDocumentVersion(path) == some(1)

    check buffer.insertText(BufferPosition(line: 0, column: 0), "x").isOk
    lsp.flushPendingBufferChange(buffer)
    check lsp.sentDocumentVersion(path) == some(2)

  test "flush is a no-op when server shadow already matches":
    let path = tmpDir / "flush_insync.nim"
    let buffer = newTextBuffer("hi", some(path))
    check lsp.onBufferOpen(buffer).isOk
    check lsp.sentDocumentVersion(path) == some(1)

    lsp.flushPendingBufferChange(buffer)
    check lsp.sentDocumentVersion(path) == some(1)

  test "flush is safe when LSP is disabled":
    lsp.setEnabled(false)
    let buffer = newTextBuffer("hi", some(tmpDir / "flush_disabled.nim"))
    lsp.flushPendingBufferChange(buffer) # must not raise

  test "flush is safe when buffer has no path":
    let buffer = newTextBuffer("hi")
    lsp.flushPendingBufferChange(buffer) # must not raise

suite "LspIntegration - Request Methods (disabled)":
  test "startCompletionRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.startCompletionRequest(buffer, 0, 0)
    check result.isErr
    check "disabled" in result.error

  test "startHoverRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.startHoverRequest(buffer, 0, 0)
    check result.isErr

  test "startDefinitionRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.startDefinitionRequest(buffer, 0, 0)
    check result.isErr

  test "startReferencesRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.startReferencesRequest(buffer, 0, 0)
    check result.isErr

  test "startCompletionRequest returns error for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    let result = lsp.startCompletionRequest(buffer, 0, 0)
    check result.isErr
    check "file path" in result.error

  test "startDefinitionRequest returns error for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    let result = lsp.startDefinitionRequest(buffer, 0, 0)
    check result.isErr

  test "startDocumentSymbolsRequest returns error for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    let result = lsp.startDocumentSymbolsRequest(buffer)
    check result.isErr

  test "startSemanticTokensRequest returns error for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test\nline2")
    let result = lsp.startSemanticTokensRequest(buffer, 0, 1)
    check result.isErr

  test "startSemanticTokensRequest returns error for empty buffer":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("", some(tmpDir / "test.nim"))
    let result = lsp.startSemanticTokensRequest(buffer, 0, 0)
    check result.isErr
    # Error can be "Buffer is empty" or "Semantic tokens not supported"
    # depending on check order.
    check "empty" in result.error or "not supported" in result.error

suite "LspIntegration - Feature Support Checks (disabled)":
  test "hasCodeLensSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check not lsp.hasCodeLensSupport(buffer)

  test "hasDocumentHighlightSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check not lsp.hasDocumentHighlightSupport(buffer)

  test "hasDocumentSymbolSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check not lsp.hasDocumentSymbolSupport(buffer)

  test "hasFoldingRangeSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check not lsp.hasFoldingRangeSupport(buffer)

  test "hasRenameSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check not lsp.hasRenameSupport(buffer)

  test "hasCallHierarchySupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check not lsp.hasCallHierarchySupport(buffer)

  test "hasDocumentLinkSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check not lsp.hasDocumentLinkSupport(buffer)

  test "hasFormattingSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check not lsp.hasFormattingSupport(buffer)

  test "hasSelectionRangeSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check not lsp.hasSelectionRangeSupport(buffer)

  test "hasExecuteCommandSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check not lsp.hasExecuteCommandSupport(buffer)

  test "hasDocumentLinkSupport returns false for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    check not lsp.hasDocumentLinkSupport(buffer)

  test "hasCallHierarchySupport returns false for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    check not lsp.hasCallHierarchySupport(buffer)

  test "hasExecuteCommandSupport returns false for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    check not lsp.hasExecuteCommandSupport(buffer)

suite "LspIntegration - Completion/SignatureHelp capability gating":
  privateAccess(LspService)

  test "hasCompletionSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check not lsp.hasCompletionSupport(buffer)

  test "hasCompletionSupport reflects the advertised server capability":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    # Enabled (the default) but the server has not advertised completion yet.
    check not lsp.hasCompletionSupport(buffer)
    lsp.service.capabilities["nim"] =
      ServerCapabilities(completionProvider: some(CompletionOptions()))
    check lsp.hasCompletionSupport(buffer)

  test "hasSignatureHelpSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check not lsp.hasSignatureHelpSupport(buffer)

  test "hasSignatureHelpSupport reflects the advertised server capability":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check not lsp.hasSignatureHelpSupport(buffer)
    lsp.service.capabilities["nim"] =
      ServerCapabilities(signatureHelpProvider: some(SignatureHelpOptions()))
    check lsp.hasSignatureHelpSupport(buffer)

suite "LspIntegration - Goto/References/Hover capability gating":
  privateAccess(LspService)

  let path = getTempDir() / "test.nim"

  test "hasHoverSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(path))
    check not lsp.hasHoverSupport(buffer)

  test "hasHoverSupport reflects the advertised server capability":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test", some(path))
    # Enabled (the default) but the server has not advertised hover yet.
    check not lsp.hasHoverSupport(buffer)
    lsp.service.capabilities["nim"] =
      ServerCapabilities(hoverProvider: some(newJBool(true)))
    check lsp.hasHoverSupport(buffer)

  test "hasDefinitionSupport reflects the advertised server capability":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test", some(path))
    check not lsp.hasDefinitionSupport(buffer)
    lsp.service.capabilities["nim"] =
      ServerCapabilities(definitionProvider: some(newJBool(true)))
    check lsp.hasDefinitionSupport(buffer)

  test "hasDeclarationSupport reflects the advertised server capability":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test", some(path))
    check not lsp.hasDeclarationSupport(buffer)
    lsp.service.capabilities["nim"] =
      ServerCapabilities(declarationProvider: some(newJBool(true)))
    check lsp.hasDeclarationSupport(buffer)

  test "hasReferencesSupport reflects the advertised server capability":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test", some(path))
    check not lsp.hasReferencesSupport(buffer)
    lsp.service.capabilities["nim"] =
      ServerCapabilities(referencesProvider: some(newJBool(true)))
    check lsp.hasReferencesSupport(buffer)

  test "hasTypeDefinitionSupport reflects the advertised server capability":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test", some(path))
    check not lsp.hasTypeDefinitionSupport(buffer)
    lsp.service.capabilities["nim"] =
      ServerCapabilities(typeDefinitionProvider: some(newJBool(true)))
    check lsp.hasTypeDefinitionSupport(buffer)

  test "hasImplementationSupport reflects the advertised server capability":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test", some(path))
    check not lsp.hasImplementationSupport(buffer)
    lsp.service.capabilities["nim"] =
      ServerCapabilities(implementationProvider: some(newJBool(true)))
    check lsp.hasImplementationSupport(buffer)

  test "hasFormattingSupport reflects the advertised server capability":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test", some(path))
    check not lsp.hasFormattingSupport(buffer)
    lsp.service.capabilities["nim"] =
      ServerCapabilities(documentFormattingProvider: some(newJBool(true)))
    check lsp.hasFormattingSupport(buffer)

  test "hasSelectionRangeSupport reflects the advertised server capability":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test", some(path))
    check not lsp.hasSelectionRangeSupport(buffer)
    lsp.service.capabilities["nim"] =
      ServerCapabilities(selectionRangeProvider: some(newJBool(true)))
    check lsp.hasSelectionRangeSupport(buffer)

  test "a literal `false` provider counts as unsupported":
    # A server may advertise `"definitionProvider": false` to disable the
    # feature; the gate must report it unsupported so we never fire a request
    # that only fails after the response timeout.
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test", some(path))
    lsp.service.capabilities["nim"] =
      ServerCapabilities(definitionProvider: some(newJBool(false)))
    check not lsp.hasDefinitionSupport(buffer)

suite "LspIntegration - Shutdown":
  privateAccess(LspIntegration)

  test "shutdown clears all state":
    let lsp = newLspIntegration()
    lsp.documents[tmpDir / "test.nim"] = (version: 1, shadow: "code")
    lsp.activeProgress["token1"] = LspProgressState(
      token: "token1",
      langId: "nim",
      title: "Test",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: 1.0,
    )
    lsp.serverStatus["nim"] =
      LspStatusState(health: shOk, quiescent: true, message: none(string))

    lsp.shutdown()

    check lsp.documents.len == 0
    check lsp.activeProgress.len == 0
    check lsp.serverStatus.len == 0

suite "LspIntegration - cleanupStaleProgress":
  privateAccess(LspIntegration)

  test "cleanupStaleProgress removes old progress":
    let lsp = newLspIntegration()
    # Add a very old progress entry (older than ProgressTimeoutSeconds)
    lsp.activeProgress["old"] = LspProgressState(
      token: "old",
      langId: "nim",
      title: "Old Task",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: epochTime() - ProgressTimeoutSeconds - 100.0,
    )
    # Add a recent progress entry
    lsp.activeProgress["new"] = LspProgressState(
      token: "new",
      langId: "nim",
      title: "New Task",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: epochTime(),
    )

    # Force cleanup by setting lastProgressCleanupTime to old value
    lsp.lastProgressCleanupTime = 0.0
    lsp.cleanupStaleProgress()

    check "old" notin lsp.activeProgress
    check "new" in lsp.activeProgress

  test "cleanupStaleProgress rate limits cleanup":
    let lsp = newLspIntegration()
    lsp.activeProgress["old"] = LspProgressState(
      token: "old",
      langId: "nim",
      title: "Old Task",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: epochTime() - ProgressTimeoutSeconds - 100.0,
    )

    # Set recent cleanup time
    lsp.lastProgressCleanupTime = epochTime()
    lsp.cleanupStaleProgress()

    # Should NOT have cleaned up due to rate limiting
    check "old" in lsp.activeProgress

suite "LspIntegration - applyWorkspaceEdit":
  test "applyWorkspaceEdit with empty edit":
    var buffers: seq[TextBuffer] = @[]
    let edit = WorkspaceEdit(
      changes: none(Table[string, seq[TextEdit]]),
      documentChanges: none(seq[TextDocumentEdit]),
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isOk
    check result.get.modifiedCount == 0

  test "applyWorkspaceEdit with changes field":
    var buffers = @[newTextBuffer("hello", some(tmpDir / "test.txt"))]
    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(tmpDir / "test.txt")] = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 5)
        ),
        newText: "world",
      )
    ]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isOk
    check result.get.modifiedCount == 1
    check buffers[0].getLine(0) == "world"

  test "applyWorkspaceEdit documentChanges takes precedence":
    var buffers = @[newTextBuffer("aaa", some(tmpDir / "test.txt"))]

    # Create changes that would modify to "bbb"
    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(tmpDir / "test.txt")] = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 3)
        ),
        newText: "bbb",
      )
    ]

    # Create documentChanges that would modify to "ccc"
    let docChanges = @[
      TextDocumentEdit(
        textDocument: OptionalVersionedTextDocumentIdentifier(
          uri: pathToUri(tmpDir / "test.txt"), version: some(1)
        ),
        edits: @[
          TextEdit(
            range: Range(
              start: Position(line: 0, character: 0),
              `end`: Position(line: 0, character: 3),
            ),
            newText: "ccc",
          )
        ],
      )
    ]

    let edit = WorkspaceEdit(changes: some(changes), documentChanges: some(docChanges))
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isOk
    # documentChanges should take precedence
    check buffers[0].getLine(0) == "ccc"

  test "applyWorkspaceEdit with multiple buffers":
    var buffers: seq[TextBuffer] = @[
      newTextBuffer("aaa", some(tmpDir / "a.txt")),
      newTextBuffer("bbb", some(tmpDir / "b.txt")),
    ]
    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(tmpDir / "a.txt")] =
      @[TextEdit(range: newRange(0, 0, 0, 3), newText: "AAA")]
    changes[pathToUri(tmpDir / "b.txt")] =
      @[TextEdit(range: newRange(0, 0, 0, 3), newText: "BBB")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isOk
    check result.get.modifiedCount == 2
    check buffers[0].getTextString() == "AAA"
    check buffers[1].getTextString() == "BBB"

  test "applyWorkspaceEdit matches a relative-path buffer against an absolute URI":
    # A buffer opened with a relative path (e.g. `moe foo.nim`) stores the path
    # verbatim, but WorkspaceEdit URIs always decode to an absolute path. The
    # open buffer must still be matched and edited in memory, not mistaken for
    # an unopened file and written straight to disk.
    let relPath = "rel_rename_target.nim"
    var buffers: seq[TextBuffer] = @[newTextBuffer("foo bar", some(relPath))]
    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(relPath)] =
      @[TextEdit(range: newRange(0, 0, 0, 3), newText: "baz")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isOk
    check result.get.modifiedCount == 1
    check result.get.modifiedBufferIndexes == @[0]
    check result.get.modifiedFilePaths.len == 0
    check buffers[0].getTextString() == "baz bar"

  test "applyWorkspaceEdit matches a relative-path buffer via documentChanges":
    let relPath = "rel_rename_doc.nim"
    var buffers: seq[TextBuffer] = @[newTextBuffer("foo bar", some(relPath))]
    let docEdit = TextDocumentEdit(
      textDocument: OptionalVersionedTextDocumentIdentifier(
        uri: pathToUri(relPath), version: some(1)
      ),
      edits: @[TextEdit(range: newRange(0, 4, 0, 7), newText: "baz")],
    )
    let edit = WorkspaceEdit(
      changes: none(Table[string, seq[TextEdit]]), documentChanges: some(@[docEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isOk
    check result.get.modifiedBufferIndexes == @[0]
    check result.get.modifiedFilePaths.len == 0
    check buffers[0].getTextString() == "foo baz"

  test "applyWorkspaceEdit with custom transaction name":
    var buffers: seq[TextBuffer] =
      @[newTextBuffer("old text", some(tmpDir / "custom.txt"))]
    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(tmpDir / "custom.txt")] =
      @[TextEdit(range: newRange(0, 0, 0, 3), newText: "new")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit, "CustomRename")
    check result.isOk
    check result.get.modifiedCount == 1
    check buffers[0].getTextString() == "new text"

  test "applyWorkspaceEdit refuses file operations without applying edits":
    var buffers: seq[TextBuffer] = @[newTextBuffer("hello", some(tmpDir / "ro.txt"))]
    let edit = WorkspaceEdit(
      changes: none(Table[string, seq[TextEdit]]),
      documentChanges: some(newSeq[TextDocumentEdit]()),
      resourceOperations: @["rename"],
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check result.error.contains("file operations")
    check result.error.contains("rename")
    check buffers[0].getTextString() == "hello"

  test "parseWorkspaceEdit records resource operations":
    let node = %*{
      "documentChanges": [
        {
          "textDocument": {"uri": pathToUri(tmpDir / "a.txt"), "version": 1},
          "edits": [
            {
              "range": {
                "start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 0}
              },
              "newText": "x",
            }
          ],
        },
        {"kind": "create", "uri": pathToUri(tmpDir / "new.txt")},
        {
          "kind": "rename",
          "oldUri": pathToUri(tmpDir / "a.txt"),
          "newUri": pathToUri(tmpDir / "b.txt"),
        },
      ]
    }
    let edit = parseWorkspaceEdit(node)
    check edit.documentChanges.isSome
    check edit.documentChanges.get.len == 1 # only the textDocument edit
    check edit.resourceOperations == @["create", "rename"]

  test "applyWorkspaceEdit reports modified buffer indexes":
    var buffers: seq[TextBuffer] = @[
      newTextBuffer("aaa", some(tmpDir / "a.txt")),
      newTextBuffer("bbb", some(tmpDir / "b.txt")),
      newTextBuffer("ccc", some(tmpDir / "c.txt")),
    ]
    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(tmpDir / "a.txt")] =
      @[TextEdit(range: newRange(0, 0, 0, 3), newText: "AAA")]
    changes[pathToUri(tmpDir / "c.txt")] =
      @[TextEdit(range: newRange(0, 0, 0, 3), newText: "CCC")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isOk
    check result.get.modifiedCount == 2
    check result.get.modifiedBufferIndexes.len == 2
    check 0 in result.get.modifiedBufferIndexes
    check 2 in result.get.modifiedBufferIndexes
    check 1 notin result.get.modifiedBufferIndexes
    check result.get.modifiedFilePaths.len == 0

  test "collectWorkspaceEditPaths from changes field":
    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(tmpDir / "a.txt")] = @[]
    changes[pathToUri(tmpDir / "b.txt")] = @[]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let paths = collectWorkspaceEditPaths(edit)
    check paths.len == 2
    check tmpDir / "a.txt" in paths
    check tmpDir / "b.txt" in paths

  test "collectWorkspaceEditPaths: documentChanges takes precedence":
    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(tmpDir / "from_changes.txt")] = @[]
    let docEdit = TextDocumentEdit(
      textDocument: OptionalVersionedTextDocumentIdentifier(
        uri: pathToUri(tmpDir / "from_doc.txt"), version: some(1)
      ),
      edits: @[],
    )
    let edit = WorkspaceEdit(changes: some(changes), documentChanges: some(@[docEdit]))
    let paths = collectWorkspaceEditPaths(edit)
    check paths == @[tmpDir / "from_doc.txt"]

  test "collectWorkspaceEditPaths with an empty edit":
    let edit = WorkspaceEdit(
      changes: none(Table[string, seq[TextEdit]]),
      documentChanges: none(seq[TextDocumentEdit]),
    )
    check collectWorkspaceEditPaths(edit).len == 0

suite "LspIntegration - applyDiagnosticsToBuffer":
  test "applyDiagnosticsToBuffer sets error markers":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let diagnostics = @[
      Diagnostic(
        range: Range(
          start: Position(line: 1, character: 0), `end`: Position(line: 1, character: 5)
        ),
        severity: some(dsError),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "Error message",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      )
    ]
    applyDiagnosticsToBuffer(buffer, diagnostics)
    check buffer.getLineMarker(1) == some(LineMarkerKind.SyntaxError)

  test "applyDiagnosticsToBuffer sets warning markers":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let diagnostics = @[
      Diagnostic(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 5)
        ),
        severity: some(dsWarning),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "Warning message",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      )
    ]
    applyDiagnosticsToBuffer(buffer, diagnostics)
    check buffer.getLineMarker(0) == some(LineMarkerKind.SyntaxWarning)

  test "applyDiagnosticsToBuffer error takes precedence over warning":
    let buffer = newTextBuffer("line1\nline2")
    let diagnostics = @[
      Diagnostic(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 5)
        ),
        severity: some(dsWarning),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "Warning",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      ),
      Diagnostic(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 5)
        ),
        severity: some(dsError),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "Error",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      ),
    ]
    applyDiagnosticsToBuffer(buffer, diagnostics)
    check buffer.getLineMarker(0) == some(LineMarkerKind.SyntaxError)

  test "applyDiagnosticsToBuffer clears existing markers":
    let buffer = newTextBuffer("line1\nline2")
    buffer.setLineMarker(0, LineMarkerKind.SyntaxError)
    buffer.setLineMarker(1, LineMarkerKind.SyntaxWarning)

    let diagnostics: seq[Diagnostic] = @[]
    applyDiagnosticsToBuffer(buffer, diagnostics)

    check buffer.getLineMarker(0).isNone
    check buffer.getLineMarker(1).isNone

  test "applyDiagnosticsToBuffer ignores out of range lines":
    let buffer = newTextBuffer("line1")
    let diagnostics = @[
      Diagnostic(
        range: Range(
          start: Position(line: 100, character: 0),
          `end`: Position(line: 100, character: 5),
        ),
        severity: some(dsError),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "Error",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      )
    ]
    applyDiagnosticsToBuffer(buffer, diagnostics)
    # Should not crash, line 0 should have no marker
    check buffer.getLineMarker(0).isNone

  test "applyDiagnosticsToBuffer stores BufferDiagnostics":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let diagnostics = @[
      Diagnostic(
        range: newRange(1, 2, 1, 8),
        severity: some(dsError),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "undeclared identifier",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      ),
      Diagnostic(
        range: newRange(0, 0, 0, 5),
        severity: some(dsWarning),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "unused variable",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      ),
    ]
    applyDiagnosticsToBuffer(buffer, diagnostics)
    check buffer.diagnostics.len == 2
    check buffer.diagnostics[0].startLine == 1
    check buffer.diagnostics[0].startCol == 2
    check buffer.diagnostics[0].endLine == 1
    # endCol 8 exceeds "line2" (5 runes) and is clamped to the line length.
    check buffer.diagnostics[0].endCol == 5
    check buffer.diagnostics[0].severity == bdsError
    check buffer.diagnostics[0].message == "undeclared identifier"
    check buffer.diagnostics[1].severity == bdsWarning
    check buffer.diagnostics[1].message == "unused variable"

  test "applyDiagnosticsToBuffer converts UTF-16 columns to rune indexes":
    # "あいう abc": each hiragana is 1 UTF-16 unit = 1 rune, so a diagnostic
    # on "abc" starts at UTF-16 column 4 = rune index 4 (byte offset 10).
    # For an emoji, UTF-16 units (2) differ from runes (1).
    let buffer = newTextBuffer("あいう abc\na😀bc")
    let diagnostics = @[
      Diagnostic(
        range: newRange(0, 4, 0, 7),
        severity: some(dsError),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "error on abc",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      ),
      Diagnostic(
        range: newRange(1, 3, 1, 5),
        severity: some(dsWarning),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "warning on bc",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      ),
    ]
    applyDiagnosticsToBuffer(buffer, diagnostics)
    check buffer.diagnostics.len == 2
    check buffer.diagnostics[0].startCol == 4
    check buffer.diagnostics[0].endCol == 7
    check buffer.diagnostics[1].startCol == 2 # a(0) 😀(1) b(2)
    check buffer.diagnostics[1].endCol == 4

suite "LspIntegration - Additional Request Methods (disabled)":
  test "startDeclarationRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.startDeclarationRequest(buffer, 0, 0)
    check result.isErr

  test "startTypeDefinitionRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.startTypeDefinitionRequest(buffer, 0, 0)
    check result.isErr

  test "startImplementationRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.startImplementationRequest(buffer, 0, 0)
    check result.isErr

  test "startSignatureHelpRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.startSignatureHelpRequest(buffer, 0, 0)
    check result.isErr

  test "startDocumentHighlightRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.startDocumentHighlightRequest(buffer, 0, 0)
    check result.isErr

  test "startCodeLensRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.startCodeLensRequest(buffer)
    check result.isErr

  test "startDocumentSymbolsRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.startDocumentSymbolsRequest(buffer)
    check result.isErr

  test "startDocumentLinkRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.startDocumentLinkRequest(buffer)
    check result.isErr

  test "startSelectionRangeRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.startSelectionRangeRequest(buffer, 0, 0)
    check result.isErr

  test "startSemanticTokensRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.startSemanticTokensRequest(buffer, 0, 10)
    check result.isErr

  test "startCompletionResolveRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let result = lsp.startCompletionResolveRequest(buffer, %*{"label": "x"})
    check result.isErr
    check "disabled" in result.error

  test "startCompletionResolveRequest returns error for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    let result = lsp.startCompletionResolveRequest(buffer, %*{"label": "x"})
    check result.isErr
    check "file path" in result.error

  test "startDocumentLinkResolveRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    let link = DocumentLink(
      range: Range(
        start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 1)
      )
    )
    let result = lsp.startDocumentLinkResolveRequest(buffer, link)
    check result.isErr
    check "disabled" in result.error

  test "startDocumentLinkResolveRequest returns error for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    let link = DocumentLink(
      range: Range(
        start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 1)
      )
    )
    let result = lsp.startDocumentLinkResolveRequest(buffer, link)
    check result.isErr
    check "file path" in result.error

suite "LspIntegration - Additional Feature Support Checks":
  test "hasCodeLensResolveSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check not lsp.hasCodeLensResolveSupport(buffer)

  test "hasDocumentLinkResolveSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check not lsp.hasDocumentLinkResolveSupport(buffer)

  test "hasExecuteCommandSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check not lsp.hasExecuteCommandSupport(buffer)

  test "feature checks return false for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    check not lsp.hasCodeLensSupport(buffer)
    check not lsp.hasDocumentSymbolSupport(buffer)
    check not lsp.hasFoldingRangeSupport(buffer)
    check not lsp.hasRenameSupport(buffer)

suite "LspIntegration - Server Path Checks":
  test "hasServerForPath with known extension":
    let lsp = newLspIntegration()
    check lsp.hasServerForPath(tmpDir / "test.nim")
    check lsp.hasServerForPath(tmpDir / "test.py")
    check lsp.hasServerForPath(tmpDir / "test.rs")

  test "hasServerForPath with unknown extension":
    let lsp = newLspIntegration()
    check not lsp.hasServerForPath(tmpDir / "test.xyz")
    check not lsp.hasServerForPath(tmpDir / "noextension")

  test "isServerRunningForPath returns false when no server running":
    let lsp = newLspIntegration()
    check not lsp.isServerRunningForPath(tmpDir / "test.nim")

  test "getRunningServers returns empty when no servers":
    let lsp = newLspIntegration()
    check lsp.getRunningServers().len == 0

suite "LspIntegration - Pending Requests":
  test "hasPendingRequests returns false initially":
    let lsp = newLspIntegration()
    check not lsp.hasPendingRequests()

  test "cleanupTimedOutRequests does not crash":
    let lsp = newLspIntegration()
    lsp.cleanupTimedOutRequests()
    # Just verify it doesn't crash

suite "LspIntegration - Callbacks":
  test "setDiagnosticsCallback sets callback":
    let lsp = newLspIntegration()
    var called = false
    lsp.setDiagnosticsCallback(
      proc(uri: string, diagnostics: seq[Diagnostic], version: Option[int]) {.gcsafe.} =
        called = true
    )
    # Callback is set but won't be called without actual LSP events
    check not called

  test "setLogCallback sets callback":
    let lsp = newLspIntegration()
    var called = false
    lsp.setLogCallback(
      proc(langId: string, msgType: MessageType, message: string) {.gcsafe.} =
        called = true
    )
    check not called

  test "setServerRestartCallback sets callback":
    let lsp = newLspIntegration()
    var called = false
    lsp.setServerRestartCallback(
      proc(langId: string) {.gcsafe.} =
        called = true
    )
    check not called
    check lsp.service.onServerRestart != nil

  test "setApplyEditCallback sets callback":
    let lsp = newLspIntegration()
    var called = false
    lsp.setApplyEditCallback(
      proc(edit: WorkspaceEdit): ApplyWorkspaceEditResult {.gcsafe.} =
        called = true
        (applied: true, failureReason: none(string))
    )
    check not called
    check lsp.service.onApplyWorkspaceEdit != nil

suite "LspIntegration - getSemanticTokensLegend":
  test "getSemanticTokensLegend returns none when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check lsp.getSemanticTokensLegend(buffer).isNone

  test "getSemanticTokensLegend returns none for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    check lsp.getSemanticTokensLegend(buffer).isNone

suite "LspIntegration - getSemanticTypeColorTable":
  test "getSemanticTypeColorTable returns none when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check lsp.getSemanticTypeColorTable(buffer).isNone

  test "getSemanticTypeColorTable returns none for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    check lsp.getSemanticTypeColorTable(buffer).isNone

  test "getSemanticTypeColorTable returns none when server has no legend":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    # No server is running, so the legend lookup misses and no cache is built.
    check lsp.getSemanticTypeColorTable(buffer).isNone
    check lsp.semanticTypeColorTables.len == 0

suite "LspIntegration - logLspDegraded":
  setup:
    clearLspMessageLog()

  test "lspDegradeReason describes a timeout":
    check lspDegradeReason(lrsTimeout) == "timed out"

  test "lspDegradeReason describes an error with detail":
    check lspDegradeReason(lrsError, "boom") == "failed: boom"

  test "lspDegradeReason describes an error without detail":
    check lspDegradeReason(lrsError) == "failed"

  test "logLspDegraded records a feature failure to the LSP message log":
    logLspDegraded("CodeLens", "failed")
    let log = getLspMessageLog()
    check log.len == 1
    check log[0] == "[LSP] CodeLens: failed"

  test "logLspDegraded status overload formats reason from the status":
    logLspDegraded("Completion", lrsTimeout)
    let log = getLspMessageLog()
    check log.len == 1
    check log[0] == "[LSP] Completion: timed out"

  test "logLspDegraded status overload includes error detail":
    logLspDegraded("Semantic tokens", lrsError, "parse failed")
    let log = getLspMessageLog()
    check log.len == 1
    check log[0] == "[LSP] Semantic tokens: failed: parse failed"

  test "logLspDegraded does not touch the general message log":
    clearMessageLog()
    logLspDegraded("CodeLens", "failed")
    check getMessageLog().len == 0
    check getLspMessageLog().len == 1

suite "LspIntegration - computeIncrementalChange":
  # Returns Option[JsonNode]: some([change]) or none (full-sync fallback).
  proc only(r: Option[JsonNode]): tuple[sl, sc, el, ec: int, text: string] =
    check r.isSome
    let c = r.get[0]
    (
      c["range"]["start"]["line"].getInt,
      c["range"]["start"]["character"].getInt,
      c["range"]["end"]["line"].getInt,
      c["range"]["end"]["character"].getInt,
      c["text"].getStr,
    )

  proc applyChange(oldText: string, sl, sc, el, ec: int, text: string): string =
    ## Apply an LSP range content change to oldText with the semantics a server
    ## uses: character offsets are UTF-16 code units, and a line index past the
    ## last line clamps to end-of-document. Lets a change be checked for actually
    ## reconstructing newText.
    let lines = oldText.split('\n')
    proc off(line, col: int): int =
      if line >= lines.len:
        return oldText.len
      for k in 0 ..< line:
        result += lines[k].len + 1
      result += utf16OffsetToUtf8(lines[line], col)

    oldText[0 ..< off(sl, sc)] & text & oldText[off(el, ec) ..< oldText.len]

  proc roundTrip(oldText, newText: string) =
    ## A produced change must transform oldText into exactly newText. `none`
    ## (full-sync fallback) is acceptable and not asserted here.
    let r = computeIncrementalChange(oldText, newText)
    if r.isSome:
      let c = only(r)
      check applyChange(oldText, c.sl, c.sc, c.el, c.ec, c.text) == newText

  test "in-line single char insert":
    # Single-line edit: only the inserted run is sent, at a UTF-16 column range.
    let c = only(computeIncrementalChange("abc", "abXc"))
    check (c.sl, c.sc, c.el, c.ec) == (0, 2, 0, 2)
    check c.text == "X"

  test "in-line single char delete":
    let c = only(computeIncrementalChange("abXc", "abc"))
    check (c.sl, c.sc, c.el, c.ec) == (0, 2, 0, 3)
    check c.text == ""

  test "whole-line insert in the middle":
    let c = only(computeIncrementalChange("a\nb", "a\nX\nb"))
    check (c.sl, c.el) == (1, 1)
    check c.text == "X\n"

  test "whole-line delete":
    let c = only(computeIncrementalChange("a\nX\nb", "a\nb"))
    check (c.sl, c.el) == (1, 2)
    check c.text == ""

  test "multi-line block replace":
    let c = only(computeIncrementalChange("a\nb\nc\nd", "a\nY\nZ\nd"))
    check (c.sl, c.el) == (1, 3)
    check c.text == "Y\nZ\n"

  test "prepend at start":
    let c = only(computeIncrementalChange("b\nc", "a\nb\nc"))
    check (c.sl, c.el) == (0, 0)
    check c.text == "a\n"

  test "empty -> non-empty":
    let c = only(computeIncrementalChange("", "hello"))
    check (c.sl, c.sc, c.el, c.ec) == (0, 0, 0, 0)
    check c.text == "hello"

  test "non-empty -> empty":
    let c = only(computeIncrementalChange("hello", ""))
    check (c.sl, c.sc, c.el, c.ec) == (0, 0, 0, 5)
    check c.text == ""

  test "surrogate pair line edited with utf-16 column anchors":
    # The unchanged surrogate-pair prefix/suffix is excluded; columns count
    # UTF-16 code units (a😀 == 3 units), and only the changed run is sent.
    let c = only(computeIncrementalChange("a😀b", "a😀X😀b"))
    check (c.sl, c.sc, c.el, c.ec) == (0, 3, 0, 3)
    check c.text == "X😀"

  test "single-line edit uses a utf-16 column range":
    let c = only(computeIncrementalChange("a\nb\nc", "a\nZ\nc"))
    check (c.sl, c.sc, c.el, c.ec) == (1, 0, 1, 1)
    check c.text == "Z"

  test "EOF append emits an end-of-document insertion":
    # oldText is a byte-prefix of newText: insert at the real last position
    # {lastLine, its UTF-16 length}, empty range, text = the appended tail.
    let c = only(computeIncrementalChange("a\nb", "a\nb\nc"))
    check (c.sl, c.sc, c.el, c.ec) == (1, 1, 1, 1)
    check c.text == "\nc"
    roundTrip("a\nb", "a\nb\nc")

  test "trailing newline add emits an end-of-document insertion":
    let c = only(computeIncrementalChange("a", "a\n"))
    check (c.sl, c.sc, c.el, c.ec) == (0, 1, 0, 1)
    check c.text == "\n"
    roundTrip("a", "a\n")

  test "EOF append onto an empty document":
    let c = only(computeIncrementalChange("", "x\ny"))
    check (c.sl, c.sc, c.el, c.ec) == (0, 0, 0, 0)
    check c.text == "x\ny"
    roundTrip("", "x\ny")

  test "EOF append after a multibyte last line uses utf-16 column":
    # Last line "café" is 5 UTF-8 bytes but 4 UTF-16 units; the insertion column
    # must be 4, not 5.
    let c = only(computeIncrementalChange("a\ncafé", "a\ncafé\nx"))
    check (c.sl, c.sc, c.el, c.ec) == (1, 4, 1, 4)
    check c.text == "\nx"
    roundTrip("a\ncafé", "a\ncafé\nx")

  test "trailing newline remove produces a last-line replace":
    # Backs the start anchor up one line so the preceding newline is consumed.
    # The end anchor is the real last position (line 1, the empty trailing line),
    # not the out-of-range {lineCount, 0}.
    let c = only(computeIncrementalChange("a\n", "a"))
    check (c.sl, c.sc, c.el, c.ec) == (0, 0, 1, 0)
    check c.text == "a"

  test "tail deletion anchors end inside the document, not one past it":
    # Regression: deleting the last line(s) must not emit end.line == lineCount
    # (one past the last valid index), which strict servers reject. oldText has
    # lines 0..2, so the end line must be <= 2.
    let c = only(computeIncrementalChange("a\nb\nc", "a\nb"))
    check c.el == 2
    check (c.sl, c.sc, c.ec) == (1, 0, 1)
    check c.text == "b"

  test "no-op returns none":
    check computeIncrementalChange("abc", "abc").isNone

  test "produced changes round-trip to newText":
    # Trailing-line deletion (no final newline = the normal buffer state) is the
    # regression these guard against: the produced change must reconstruct
    # newText exactly, not merely look internally consistent.
    for pair in [
      ("a\nb", "a"),
      ("a\nb\nc", "a\nb"),
      ("a\nb\nc", "a"),
      ("foo\nbar", "foo"),
      ("a\nb\nc\nd", "a\nb"),
      ("a\na\na", "a\na"),
      ("a\nb\nb", "a\nb"),
      ("a\nb", "a\nc"),
      ("a\n你", "a\n好"),
      ("a\n", "a"),
      ("a\nX\nb", "a\nb"),
      ("a\nb", "a\nX\nb"),
      ("abc", "abXc"),
      ("hello", ""),
      ("", "hello"),
      ("b\nc", "a\nb\nc"),
      ("a😀b", "a😀X😀b"), # surrogate pairs around an in-line edit
      ("héllo", "héXllo"), # 2-byte rune in the common prefix
      ("café", "cafés"), # multibyte at the line tail
      ("a\n😀b\nc", "a\n😀Xb\nc"), # in-line edit on a middle multibyte line
      ("a\nb", "a\nb\nc"), # EOF append
      ("a", "a\n"), # add a trailing newline
      ("a\nb", "a\nb\nc\nd"), # multi-line EOF append
      ("", "x\ny"), # append onto an empty document
      ("a\ncafé", "a\ncafé\nx"), # EOF append after a multibyte last line
    ]:
      roundTrip(pair[0], pair[1])

  test "fuzz: editor-like mutations always round-trip":
    # Re-verify the diff (including the new EOF-append branch) by applying random
    # insert/delete/replace/append edits at rune boundaries and checking that any
    # produced change reconstructs newText exactly. Fixed seed = reproducible.
    # Built from whole-rune chunks with seq slicing so the generator itself never
    # splits a multibyte sequence or relies on uncertain seq mutate APIs.
    var rng = initRand(20260614)
    const runes = ["a", "b", "c", "\n", "é", "你", "😀"]

    proc randRunes(maxRunes: int): seq[string] =
      for _ in 0 ..< rng.rand(0 .. maxRunes):
        result.add(runes[rng.rand(runes.high)])

    for _ in 0 ..< 20000:
      let old = randRunes(24)
      let oldText = old.join("")
      var rs = old
      case rng.rand(0 .. 4)
      of 0: # insert at a random rune boundary
        let a = rng.rand(0 .. rs.len)
        rs = rs[0 ..< a] & randRunes(4) & rs[a .. ^1]
      of 1: # delete a random rune span
        if rs.len > 0:
          let a = rng.rand(0 ..< rs.len)
          let b = min(a + rng.rand(0 .. 3), rs.high)
          rs = rs[0 ..< a] & rs[b + 1 .. ^1]
      of 2: # replace a random rune span
        if rs.len > 0:
          let a = rng.rand(0 ..< rs.len)
          let b = min(a + rng.rand(0 .. 3), rs.high)
          rs = rs[0 ..< a] & randRunes(4) & rs[b + 1 .. ^1]
      of 3: # append at end-of-document (exercises the EOF-append branch)
        rs = rs & randRunes(6)
      else: # toggle a trailing newline
        if rs.len > 0 and rs[^1] == "\n":
          rs = rs[0 ..< rs.high]
        else:
          rs = rs & @["\n"]
      roundTrip(oldText, rs.join(""))

suite "LspIntegration - incremental didChange":
  privateAccess(LspIntegration)

  let Path = tmpDir / "test.nim"

  # onBufferOpen below spawns a real worker thread (nim is configured by
  # default), so each test tears the integration down to join that thread and
  # avoid leaking worker threads / nimlangserver processes across the suite.
  var lsp: LspIntegration
  setup:
    lsp = newLspIntegration()
  teardown:
    lsp.shutdown()

  proc setKind(lsp: LspIntegration, syncKind: int) =
    lsp.service.processEvent(
      "nim",
      LspEvent(
        kind: levCapabilities, capabilitiesJson: $(%*{"textDocumentSync": syncKind})
      ),
    )

  proc markReady(lsp: LspIntegration) =
    ## Force the liveness checks to report a running server so onBufferChange
    ## sends incremental changes deterministically, independent of the real
    ## worker onBufferOpen spawned.
    lsp.service.liveWorkerOverride = proc(path: string): bool =
      true
    lsp.service.runningWorkerOverride = proc(path: string): bool =
      true

  proc markStarting(lsp: LspIntegration) =
    ## Force "has a worker but not yet lwsRunning" so onBufferChange falls back
    ## to full sync to coalesce into the pending didOpen.
    lsp.service.liveWorkerOverride = proc(path: string): bool =
      true
    lsp.service.runningWorkerOverride = proc(path: string): bool =
      false

  proc markNoWorker(lsp: LspIntegration) =
    ## Force the liveness checks to report no deliverable worker so onBufferChange
    ## deterministically skips. Without this the real worker onBufferOpen spawned
    ## could race into lwsStarting and flip the gate, making the test flaky.
    lsp.service.liveWorkerOverride = proc(path: string): bool =
      false

  test "onBufferOpen seeds shadow and version 1":
    check lsp.onBufferOpen(newTextBuffer("abc", some(Path))).isOk
    check lsp.documents[Path].shadow == "abc"
    check lsp.documents[Path].version == 1

  test "no-op change leaves version and shadow untouched":
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    check lsp.onBufferChange(newTextBuffer("abc", some(Path))).isOk
    check lsp.documents[Path].version == 1
    check lsp.documents[Path].shadow == "abc"

  test "incremental change bumps version and updates shadow":
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markReady()
    check lsp.onBufferChange(newTextBuffer("abXc", some(Path))).isOk
    check lsp.documents[Path].version == 2
    check lsp.documents[Path].shadow == "abXc"

  test "starting worker falls back to full sync; version and shadow advance":
    # A starting worker cannot receive incremental changes (the worker drops
    # them), so the integration must send full sync to coalesce into the
    # pending didOpen. The shadow still advances to the latest text.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markStarting()
    check lsp.onBufferChange(newTextBuffer("abXc", some(Path))).isOk
    check lsp.documents[Path].version == 2
    check lsp.documents[Path].shadow == "abXc"

  test "no ready worker: change is skipped, version and shadow unchanged":
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2) # incremental advertised, but no server is ready
    lsp.markNoWorker() # deterministic: ignore the worker onBufferOpen spawned
    check lsp.onBufferChange(newTextBuffer("abXc", some(Path))).isOk
    check lsp.documents[Path].version == 1
    check lsp.documents[Path].shadow == "abc"

  test "tdskNone skips: no version bump, shadow unchanged":
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(0)
    check lsp.onBufferChange(newTextBuffer("abXc", some(Path))).isOk
    check lsp.documents[Path].version == 1
    check lsp.documents[Path].shadow == "abc"

  test "onBufferClose removes shadow":
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    check lsp.onBufferClose(newTextBuffer("abc", some(Path))).isOk
    check Path notin lsp.documents

  test "shadow tracks server text across consecutive edits":
    discard lsp.onBufferOpen(newTextBuffer("a\nb\nc", some(Path)))
    lsp.setKind(2)
    lsp.markReady()
    # The invariant is shadow == buffer.getTextString() (the text actually sent),
    # not the raw input string, since the buffer normalizes its content.
    for raw in ["a\nb\nX\nc", "a\nc", "a\nc\nd\ne", "done"]:
      let buf = newTextBuffer(raw, some(Path))
      check lsp.onBufferChange(buf).isOk
      check lsp.documents[Path].shadow == buf.getTextString()

suite "LspIntegration - getDiagnosticsAt":
  test "returns diagnostics at cursor position":
    let buffer = newTextBuffer("line1\nline2\nline3")
    buffer.diagnostics = @[
      BufferDiagnostic(
        startLine: 1,
        startCol: 0,
        endLine: 1,
        endCol: 5,
        severity: bdsError,
        message: "error here",
      )
    ]
    let diags = buffer.getDiagnosticsAt(1, 3)
    check diags.len == 1
    check diags[0].message == "error here"

  test "returns empty for position outside diagnostic range":
    let buffer = newTextBuffer("line1\nline2\nline3")
    buffer.diagnostics = @[
      BufferDiagnostic(
        startLine: 1,
        startCol: 0,
        endLine: 1,
        endCol: 5,
        severity: bdsError,
        message: "error here",
      )
    ]
    check buffer.getDiagnosticsAt(0, 0).len == 0
    check buffer.getDiagnosticsAt(2, 0).len == 0
    # endCol is exclusive (LSP spec): col == endCol should be outside.
    check buffer.getDiagnosticsAt(1, 5).len == 0
    check buffer.getDiagnosticsAt(1, 4).len == 1

  test "multi-line diagnostic - middle line matches at any column":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    buffer.diagnostics = @[
      BufferDiagnostic(
        startLine: 1,
        startCol: 3,
        endLine: 3,
        endCol: 2,
        severity: bdsError,
        message: "multi-line error",
      )
    ]
    check buffer.getDiagnosticsAt(2, 0).len == 1
    check buffer.getDiagnosticsAt(2, 99).len == 1

  test "multi-line diagnostic - start line respects startCol":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    buffer.diagnostics = @[
      BufferDiagnostic(
        startLine: 1,
        startCol: 3,
        endLine: 3,
        endCol: 2,
        severity: bdsError,
        message: "multi-line error",
      )
    ]
    check buffer.getDiagnosticsAt(1, 2).len == 0
    check buffer.getDiagnosticsAt(1, 3).len == 1
    check buffer.getDiagnosticsAt(1, 10).len == 1

  test "multi-line diagnostic - end line respects exclusive endCol":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    buffer.diagnostics = @[
      BufferDiagnostic(
        startLine: 1,
        startCol: 3,
        endLine: 3,
        endCol: 2,
        severity: bdsError,
        message: "multi-line error",
      )
    ]
    check buffer.getDiagnosticsAt(3, 0).len == 1
    check buffer.getDiagnosticsAt(3, 1).len == 1
    check buffer.getDiagnosticsAt(3, 2).len == 0 # exclusive

  test "returns multiple diagnostics at same position":
    let buffer = newTextBuffer("line1\nline2\nline3")
    buffer.diagnostics = @[
      BufferDiagnostic(
        startLine: 1,
        startCol: 0,
        endLine: 1,
        endCol: 10,
        severity: bdsError,
        message: "error",
      ),
      BufferDiagnostic(
        startLine: 1,
        startCol: 2,
        endLine: 1,
        endCol: 8,
        severity: bdsWarning,
        message: "warning",
      ),
    ]
    let diags = buffer.getDiagnosticsAt(1, 3)
    check diags.len == 2

suite "LspIntegration - formatDiagnosticsForHover":
  test "formats a single diagnostic":
    let diags = @[
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 5,
        severity: bdsError,
        message: "undeclared identifier",
      )
    ]
    check formatDiagnosticsForHover(diags) == "[Error] undeclared identifier"

  test "formats multiple diagnostics":
    let diags = @[
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 5,
        severity: bdsError,
        message: "error msg",
      ),
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 5,
        severity: bdsWarning,
        message: "warning msg",
      ),
    ]
    check formatDiagnosticsForHover(diags) == "[Error] error msg\n[Warning] warning msg"

  test "formats all severity levels":
    let diags = @[
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 1,
        severity: bdsError,
        message: "e",
      ),
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 1,
        severity: bdsWarning,
        message: "w",
      ),
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 1,
        severity: bdsInformation,
        message: "i",
      ),
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 1,
        severity: bdsHint,
        message: "h",
      ),
    ]
    check formatDiagnosticsForHover(diags) ==
      "[Error] e\n[Warning] w\n[Info] i\n[Hint] h"

  test "empty diagnostics returns empty string":
    check formatDiagnosticsForHover(@[]) == ""

suite "LspIntegration - hasStaleTargetBuffer":
  proc snapshotOf(buffers: seq[TextBuffer]): Table[BufferId, int] =
    for buf in buffers:
      result[buf.id] = buf.contentVersion

  proc editFor(paths: varargs[string]): WorkspaceEdit =
    var changes = initTable[string, seq[TextEdit]]()
    for path in paths:
      changes[pathToUri(path)] =
        @[TextEdit(range: newRange(0, 0, 0, 3), newText: "xxx")]
    WorkspaceEdit(changes: some(changes), documentChanges: none(seq[TextDocumentEdit]))

  test "unchanged target buffers are not stale":
    let buffers = @[
      newTextBuffer("aaa", some(tmpDir / "a.txt")),
      newTextBuffer("bbb", some(tmpDir / "b.txt")),
    ]
    check not hasStaleTargetBuffer(
      buffers, editFor(tmpDir / "a.txt", tmpDir / "b.txt"), snapshotOf(buffers)
    )

  test "a target buffer whose contentVersion advanced is stale":
    let buffers = @[newTextBuffer("aaa", some(tmpDir / "a.txt"))]
    let snapshot = snapshotOf(buffers)
    buffers[0].contentVersion.inc

    check hasStaleTargetBuffer(buffers, editFor(tmpDir / "a.txt"), snapshot)

  test "a target buffer missing from the snapshot is stale":
    # Regression: a buffer opened *while* the rename request was in flight has
    # no snapshot entry, so nothing pins it to the text the server saw.
    # Defaulting the lookup to the buffer's own contentVersion compared the
    # value against itself and let it through unverified.
    let opened = @[newTextBuffer("aaa", some(tmpDir / "a.txt"))]
    let snapshot = snapshotOf(opened)

    let buffers = opened & @[newTextBuffer("bbb", some(tmpDir / "b.txt"))]
    check hasStaleTargetBuffer(buffers, editFor(tmpDir / "b.txt"), snapshot)

  test "a buffer outside the edit's targets is ignored":
    let opened = @[newTextBuffer("aaa", some(tmpDir / "a.txt"))]
    let snapshot = snapshotOf(opened)

    # Opened mid-request, but the edit does not touch it.
    let buffers = opened & @[newTextBuffer("bbb", some(tmpDir / "b.txt"))]
    check not hasStaleTargetBuffer(buffers, editFor(tmpDir / "a.txt"), snapshot)

  test "two buffers on the same file are tracked by id, not path":
    # Same file opened twice (relative and absolute). A path-keyed baseline
    # would let one buffer's version shadow the other's.
    let relPath = "stale_target.txt"
    let buffers = @[
      newTextBuffer("aaa", some(relPath)),
      newTextBuffer("aaa", some(absolutePath(relPath))),
    ]
    let snapshot = snapshotOf(buffers)

    check not hasStaleTargetBuffer(buffers, editFor(relPath), snapshot)

    buffers[1].contentVersion.inc
    check hasStaleTargetBuffer(buffers, editFor(relPath), snapshot)

suite "LspIntegration - hasStaleServerEditTarget":
  var lsp: LspIntegration
  setup:
    lsp = newLspIntegration(tmpDir)
  teardown:
    lsp.shutdown()

  proc setLiveWorkers(lsp: LspIntegration, live: bool) =
    lsp.service.liveWorkerOverride = proc(path: string): bool =
      live

  proc editFor(path: string): WorkspaceEdit =
    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(path)] = @[TextEdit(range: newRange(0, 0, 0, 3), newText: "xxx")]
    WorkspaceEdit(changes: some(changes), documentChanges: none(seq[TextDocumentEdit]))

  proc syncedAt(buf: TextBuffer): Table[BufferId, int] =
    result[buf.id] = buf.contentVersion

  test "server-held buffer in sync is not stale":
    lsp.setLiveWorkers(true)
    let buf = newTextBuffer("aaa", some(tmpDir / "a.nim"))

    check not lsp.hasStaleServerEditTarget(
      @[buf], editFor(tmpDir / "a.nim"), syncedAt(buf)
    )

  test "server-held buffer edited since the last sync is stale":
    lsp.setLiveWorkers(true)
    let buf = newTextBuffer("aaa", some(tmpDir / "a.nim"))
    let synced = syncedAt(buf)
    discard buf.insertText(BufferPosition(line: 0, column: 3), "!")

    check lsp.hasStaleServerEditTarget(@[buf], editFor(tmpDir / "a.nim"), synced)

  test "buffer the server never received is stale when it has unsaved changes":
    # Regression: maybeUpdateLsp records a sync baseline even when the
    # notification is dropped for want of a worker (e.g. Cargo.toml in a Rust
    # project). contentVersion then matches while the buffer diverges from the
    # disk text the server actually read, so the edit was let through and
    # applied at the wrong coordinates.
    lsp.setLiveWorkers(false)
    let buf = newTextBuffer("aaa", some(tmpDir / "Cargo.toml"))
    discard buf.insertText(BufferPosition(line: 0, column: 3), "!")

    check lsp.hasStaleServerEditTarget(
      @[buf], editFor(tmpDir / "Cargo.toml"), syncedAt(buf)
    )

  test "buffer the server never received is not stale when it matches disk":
    lsp.setLiveWorkers(false)
    let buf = newTextBuffer("aaa", some(tmpDir / "Cargo.toml"))

    check not lsp.hasStaleServerEditTarget(
      @[buf], editFor(tmpDir / "Cargo.toml"), syncedAt(buf)
    )

  test "live worker but no sync baseline falls back to the disk comparison":
    # didOpen never succeeded, so the server has no copy of this document.
    lsp.setLiveWorkers(true)
    let buf = newTextBuffer("aaa", some(tmpDir / "a.nim"))
    let noBaseline = initTable[BufferId, int]()

    check not lsp.hasStaleServerEditTarget(
      @[buf], editFor(tmpDir / "a.nim"), noBaseline
    )

    discard buf.insertText(BufferPosition(line: 0, column: 3), "!")
    check lsp.hasStaleServerEditTarget(@[buf], editFor(tmpDir / "a.nim"), noBaseline)

  test "a buffer outside the edit's targets is ignored":
    lsp.setLiveWorkers(false)
    let target = newTextBuffer("aaa", some(tmpDir / "a.nim"))
    let other = newTextBuffer("bbb", some(tmpDir / "b.nim"))
    discard other.insertText(BufferPosition(line: 0, column: 3), "!")

    check not lsp.hasStaleServerEditTarget(
      @[target, other], editFor(tmpDir / "a.nim"), syncedAt(target)
    )
