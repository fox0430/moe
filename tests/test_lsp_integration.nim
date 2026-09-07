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
    unicode, monotimes,
  ]

import pkg/results

import ../src/moepkg/lsp_integration {.all.}
import ../src/moepkg/[buffer, message_log, unicode_utils]
import ../src/moepkg/types
import ../src/moepkg/lsp_service {.all.}
import ../src/moepkg/types/config_types
import ../src/moepkg/buffer_backends/piece_table
import ../src/moepkg/lsp/protocol/types
import ../src/moepkg/types/lsp_integration_types {.all.}

privateAccess(LspDocumentState)

let tmpDir = getTempDir()

proc syncedStatus(lsp: LspIntegration, buffer: TextBuffer): SyncVerdict =
  ## Frame sync with verdict.
  lsp.syncAndJudge(buffer, ignoreRetryInterval = false, mayRestart = false)

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

  test "utf16OffsetToUtf8 steps by the bytes a character occupies":
    # 0xE9 is one source byte here (it advertises three, but only two remain)
    # yet re-encodes to two, so walking by `Rune.size` ran the offset past it.
    let line = "caf\xE9x"
    check line.charLen == 5
    check utf16OffsetToUtf8(line, 3) == 3 # Before the undecodable byte
    check utf16OffsetToUtf8(line, 4) == 4 # After it
    check utf16OffsetToUtf8(line, 5) == 5
    check utf16OffsetToUtf8(line, 99) == line.len

  test "utf8OffsetToUtf16 steps by the bytes a character occupies":
    let line = "caf\xE9x"
    check utf8OffsetToUtf16(line, 3) == 3
    check utf8OffsetToUtf16(line, 4) == 4
    check utf8OffsetToUtf16(line, line.len) == line.charLen

  test "utf16OffsetToUtf8 and utf8OffsetToUtf16 round-trip past a raw byte":
    let line = "caf\xE9x"
    for col in 0 .. line.charLen:
      check utf8OffsetToUtf16(line, utf16OffsetToUtf8(line, col)) == col

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

  test "charIndexToUtf16 with empty string":
    check charIndexToUtf16("", 0) == 0
    check charIndexToUtf16("", 5) == 0

  test "charIndexToUtf16 with ASCII":
    let line = "hello world"
    check charIndexToUtf16(line, 0) == 0
    check charIndexToUtf16(line, 5) == 5
    check charIndexToUtf16(line, 11) == 11

  test "charIndexToUtf16 with BMP characters":
    # Each hiragana is 1 character = 1 UTF-16 unit = 3 UTF-8 bytes.
    let line = "こんにちは"
    check charIndexToUtf16(line, 0) == 0
    check charIndexToUtf16(line, 1) == 1
    check charIndexToUtf16(line, 5) == 5

  test "charIndexToUtf16 with mixed ASCII and Japanese":
    let line = "ABCあいう"
    check charIndexToUtf16(line, 3) == 3
    check charIndexToUtf16(line, 4) == 4
    check charIndexToUtf16(line, 6) == 6

  test "charIndexToUtf16 with surrogate pairs":
    let line = "a😀b"
    check charIndexToUtf16(line, 0) == 0
    check charIndexToUtf16(line, 1) == 1
    check charIndexToUtf16(line, 2) == 3 # After emoji (2 UTF-16 units)
    check charIndexToUtf16(line, 3) == 4

  test "charIndexToUtf16 clamps to line length":
    check charIndexToUtf16("abc", 100) == 3
    check charIndexToUtf16("a😀b", 100) == 4

  test "the didChange prefix stops on a character boundary":
    # 0xE0 announces three bytes and the two after it are 'A' and 0xE3, so a
    # walk that trusts the announcement jumps from byte 0 to byte 3 -- into the
    # middle of the valid three-byte character that starts at byte 2. The
    # offset then handed to the server names a position no character starts at.
    let
      a = "\xE0\x41\xE3\x81\x82"
      b = "\xE0\x41\xE3\x81\x83"
    check a.charLen == 3

    var boundaries: seq[int] = @[]
    var i = 0
    while i <= a.len:
      boundaries.add(i)
      if i < a.len:
        i += a.runeSizeAt(i)
      else:
        break
    check boundaries == @[0, 1, 2, 5]

    # The lenient walk reaches byte 4, inside the character spanning 2..4.
    check commonRunePrefixBytes(a, b) == 2

  test "the didChange prefix stops where two lines first differ":
    check commonRunePrefixBytes("abc", "abd") == 2
    check commonRunePrefixBytes("日本語", "日本X") == 6
    check commonRunePrefixBytes("abc", "abc") == 3
    check commonRunePrefixBytes("", "abc") == 0
    # A truncated tail must stop the walk rather than read past either string.
    check commonRunePrefixBytes("ab\xE3", "ab\xE3\x81\x82") == 2

  test "utf16ToCharIndex with empty string":
    check utf16ToCharIndex("", 0) == 0
    check utf16ToCharIndex("", 5) == 0

  test "utf16ToCharIndex with ASCII":
    let line = "hello"
    check utf16ToCharIndex(line, 0) == 0
    check utf16ToCharIndex(line, 3) == 3
    check utf16ToCharIndex(line, 5) == 5

  test "utf16ToCharIndex with BMP characters":
    let line = "こんにちは"
    check utf16ToCharIndex(line, 0) == 0
    check utf16ToCharIndex(line, 2) == 2
    check utf16ToCharIndex(line, 5) == 5

  test "utf16ToCharIndex with surrogate pairs":
    let line = "a😀b"
    check utf16ToCharIndex(line, 0) == 0
    check utf16ToCharIndex(line, 1) == 1
    check utf16ToCharIndex(line, 3) == 2 # After emoji (2 UTF-16 units)
    check utf16ToCharIndex(line, 4) == 3

  test "utf16ToCharIndex clamps to character count":
    check utf16ToCharIndex("abc", 100) == 3
    check utf16ToCharIndex("a😀b", 100) == 3

  test "character/UTF-16 roundtrip":
    let line = "hello世界🌍end"
    # Rune indexes: h(0) e(1) l(2) l(3) o(4) 世(5) 界(6) 🌍(7) e(8) n(9) d(10).
    for charIndex in [0, 3, 5, 6, 7, 8, 11]:
      let utf16 = charIndexToUtf16(line, charIndex)
      check utf16ToCharIndex(line, utf16) == charIndex

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

  test "applyTextEdits refuses a raw buffer even with no edits":
    # The refusal is the gate for the server-to-buffer direction, so it cannot
    # depend on the edit list: a caller probing eligibility with an empty list
    # would otherwise read ok() as "this buffer accepts server edits".
    let buffer = newTextBuffer("hello world")
    buffer.keepRaw = true
    let edits: seq[TextEdit] = @[]

    let result = applyTextEdits(buffer, edits)

    check result.isErr
    check result.error == RawBufferLspRejection

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

  test "applyTextEdits failure rolls back its own transaction":
    # Edits apply back-to-front; the malformed one fails last, so the
    # transaction applyTextEdits opened must be rolled back to the pre-call
    # state.
    let buffer = newTextBuffer("hello world")
    let edits = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 5)
        ),
        newText: "hi",
      ),
      TextEdit(
        range: Range(
          start: Position(line: -1, character: 0),
          `end`: Position(line: -1, character: 0),
        ),
        newText: "x",
      ),
    ]
    let result = applyTextEdits(buffer, edits)
    check result.isErr
    check not buffer.inTransaction
    check buffer.getLine(0) == "hello world"

  test "applyTextEdits failure keeps partial edits in a joined session transaction":
    # In a live session transaction applyTextEdits joins it: edits before the
    # failing one stay in the session until its commit.
    let buffer = newTextBuffer("line1\nline2\nline3")
    check buffer.beginTransaction("Insert mode edit").isOk
    let edits = @[
      TextEdit(
        range: Range(
          start: Position(line: 2, character: 0), `end`: Position(line: 2, character: 2)
        ),
        newText: "AB",
      ),
      TextEdit(
        range: Range(
          start: Position(line: -1, character: 0),
          `end`: Position(line: -1, character: 0),
        ),
        newText: "x",
      ),
    ]
    let result = applyTextEdits(buffer, edits)
    check result.isErr
    check "joined transaction" in result.error
    check buffer.inTransaction
    check buffer.getLine(2) == "ABne3"
    check buffer.commitTransaction().isOk
    check buffer.getLine(2) == "ABne3"

  test "applyTextEdits failure reports the edits that remain applied":
    # In a joined session the lower-line edit applies first and stays; the
    # tracking list must report exactly that edit so callers can re-sync
    # their own coordinates against the partial application.
    let buffer = newTextBuffer("line1\nline2\nline3")
    check buffer.beginTransaction("Insert mode edit").isOk
    var applied: seq[TextEdit]
    let edits = @[
      TextEdit(
        range: Range(
          start: Position(line: 2, character: 0), `end`: Position(line: 2, character: 2)
        ),
        newText: "AB",
      ),
      TextEdit(
        range: Range(
          start: Position(line: -1, character: 0),
          `end`: Position(line: -1, character: 0),
        ),
        newText: "x",
      ),
    ]
    let result = applyTextEdits(buffer, edits, appliedEdits = applied)
    check result.isErr
    check applied.len == 1
    check applied[0].newText == "AB"
    check buffer.getLine(2) == "ABne3"
    check buffer.commitTransaction().isOk

  test "applyTextEdits clears appliedEdits when it rolls back its own transaction":
    # Self-managed failure rolls everything back, so nothing remains applied
    # and the tracking list must be empty.
    let buffer = newTextBuffer("abc")
    var applied: seq[TextEdit]
    let edits = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 1)
        ),
        newText: "A",
      ),
      TextEdit(
        range: Range(
          start: Position(line: -1, character: 0),
          `end`: Position(line: -1, character: 0),
        ),
        newText: "x",
      ),
    ]
    let result = applyTextEdits(buffer, edits, appliedEdits = applied)
    check result.isErr
    check applied.len == 0
    check not buffer.inTransaction
    check buffer.getLine(0) == "abc"

  test "applyTextEdits can suppress the joined-transaction note":
    # A caller that rolls the joined transaction back itself (withTransaction
    # scope) must not see the "may remain applied" note: the edits are
    # reverted by that scope, so the note would be wrong.
    let buffer = newTextBuffer("hello world")
    check buffer.beginTransaction("LSP TextEdits").isOk
    var applied: seq[TextEdit]
    let result = applyTextEdits(
      buffer,
      @[
        TextEdit(
          range: Range(
            start: Position(line: -1, character: 0),
            `end`: Position(line: -1, character: 0),
          ),
          newText: "x",
        )
      ],
      appliedEdits = applied,
      discloseJoined = false,
    )
    check result.isErr
    check "joined transaction" notin result.error
    check applied.len == 0
    check buffer.inTransaction
    check buffer.commitTransaction().isOk

  test "abortTextEditsOnException rolls back its own transaction":
    # Direct unit test of the exception tail.
    let buffer = newTextBuffer("hello world")
    check buffer.beginTransaction("LSP TextEdits").isOk
    check buffer.insertText(BufferPosition(line: 0, column: 5), "x").isOk
    var applied: seq[TextEdit]
    let result = abortTextEditsOnException(
      buffer, ownTransaction = true, excMsg = "boom", appliedEdits = applied
    )
    check result.isErr
    check "Failed to apply text edits: boom" in result.error
    check not buffer.inTransaction
    check buffer.getLine(0) == "hello world"
    # A successful rollback reverts everything: the tracking list is cleared.
    check applied.len == 0

  test "abortTextEditsOnException leaves a joined session transaction open":
    let buffer = newTextBuffer("hello world")
    check buffer.beginTransaction("Insert mode edit").isOk
    check buffer.insertText(BufferPosition(line: 0, column: 5), "x").isOk
    # The caller's tracking list already reports the applied edit: the tail
    # must leave it untouched when nothing was rolled back.
    var applied = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 0)
        ),
        newText: "x",
      )
    ]
    let result = abortTextEditsOnException(
      buffer, ownTransaction = false, excMsg = "boom", appliedEdits = applied
    )
    check result.isErr
    check "joined transaction" in result.error
    check "may remain applied" in result.error
    check buffer.inTransaction
    check buffer.getLine(0) == "hellox world"
    check applied.len == 1
    check buffer.commitTransaction().isOk
    check buffer.getLine(0) == "hellox world"

  test "abortTextEditsOnException can suppress the joined-transaction note":
    # A caller that rolls the joined transaction back itself (withTransaction
    # scope) suppresses the note on the exception path too, matching the
    # failEdit path's discloseJoined handling.
    let buffer = newTextBuffer("hello world")
    check buffer.beginTransaction("LSP TextEdits").isOk
    check buffer.insertText(BufferPosition(line: 0, column: 5), "x").isOk
    var applied = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 0)
        ),
        newText: "x",
      )
    ]
    let result = abortTextEditsOnException(
      buffer,
      ownTransaction = false,
      excMsg = "boom",
      appliedEdits = applied,
      discloseJoined = false,
    )
    check result.isErr
    check result.error == "Failed to apply text edits: boom"
    check "joined transaction" notin result.error
    check buffer.inTransaction
    check buffer.getLine(0) == "hellox world"
    check applied.len == 1
    check buffer.commitTransaction().isOk
    check buffer.getLine(0) == "hellox world"

  test "abortTextEditsOnException discloses a failed rollback and keeps the applied list":
    # A rollback that fails partway must disclose that edits may remain
    # applied and must NOT clear the tracking list: the buffer state can no
    # longer be trusted. A pending snapshot would give an O(1) rollback that
    # cannot fail, so clear it to force the per-change undo path.
    let buffer = newTextBuffer("hello world")
    check buffer.beginTransaction("LSP TextEdits").isOk
    check buffer.insertText(BufferPosition(line: 0, column: 5), "x").isOk
    buffer.currentTransaction.get.changes.add(
      BufferChange(
        startSeq: buffer.changeSeq,
        endSeq: buffer.changeSeq + 1,
        kind: ckInsertLine,
        insertLineIdx: 999,
        insertLineText: "x",
      )
    )
    buffer.pendingSnapshot = none(PieceTableSnapshot)
    var applied = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 0)
        ),
        newText: "x",
      )
    ]
    let result = abortTextEditsOnException(
      buffer, ownTransaction = true, excMsg = "boom", appliedEdits = applied
    )
    check result.isErr
    check "Failed to apply text edits: boom" in result.error
    check "rollback failed" in result.error
    check "some edits may remain applied" in result.error
    check applied.len == 1
    # The partial rollback cleaned up the transaction state.
    check not buffer.inTransaction

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

  test "applyTextEdits rejects start position past the end of its line":
    # A server position whose character exceeds the line's UTF-16 length
    # must fail instead of silently clamping to the end of line.
    let buffer = newTextBuffer("abc")
    let edit = TextEdit(range: newRange(0, 5, 0, 5), newText: "X")
    let result = applyTextEdits(buffer, @[edit])
    check result.isErr
    check "past the end of its line" in result.error
    check not buffer.inTransaction
    check buffer.getLine(0) == "abc"

  test "applyTextEdits rejects start past EOL after multibyte characters":
    # "あいう" is 3 UTF-16 units; character 4 exceeds the line.
    let buffer = newTextBuffer("あいう")
    let edit = TextEdit(range: newRange(0, 4, 0, 4), newText: "X")
    let result = applyTextEdits(buffer, @[edit])
    check result.isErr
    check "past the end of its line" in result.error
    check buffer.getLine(0) == "あいう"

  test "applyTextEdits rejects end position past the end of its line":
    # Same rejection for the delete end. "def" is 3 UTF-16 units, so
    # character 10 points past the end of line 1.
    let buffer = newTextBuffer("abc\ndef")
    let edit = TextEdit(range: newRange(0, 0, 1, 10), newText: "X")
    let result = applyTextEdits(buffer, @[edit])
    check result.isErr
    check "past the end of its line" in result.error
    check not buffer.inTransaction
    check buffer.getTextString() == "abc\ndef"

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

  test "onBufferClose tracks nothing when disabled":
    let lsp = newLspIntegration()
    lsp.enabled = false
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    lsp.onBufferClose(buffer)
    check lsp.documents.len == 0
    check lsp.openedPaths.len == 0

  test "a sync reports nothing to send when disabled":
    let lsp = newLspIntegration()
    lsp.enabled = false
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check lsp.syncedStatus(buffer).kind == svNotApplicable

  test "onBufferSave tracks nothing when disabled":
    let lsp = newLspIntegration()
    lsp.enabled = false
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    lsp.onBufferSave(buffer)
    check lsp.documents.len == 0
    check lsp.openedPaths.len == 0

  test "onBufferOpen returns ok for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    let result = lsp.onBufferOpen(buffer)
    check result.isOk

  test "onBufferClose tracks nothing for a buffer without a path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    lsp.onBufferClose(buffer)
    check lsp.documents.len == 0
    check lsp.openedPaths.len == 0

  test "onBufferSave tracks nothing for a buffer without a path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    lsp.onBufferSave(buffer)
    check lsp.documents.len == 0
    check lsp.openedPaths.len == 0

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
    ## Pretend a server receives the change.
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
      check lsp.syncedStatus(buffer).kind == svSynced
      check lsp.sentDocumentVersion(tmpDir / "test.nim") == some(expected)

  test "version does not regress when changeSeq rolls back":
    # Undo rolls buffer.changeSeq back; the version sent to the server must
    # keep increasing regardless.
    lsp.markReady()
    let buffer = newTextBuffer("hello", some(tmpDir / "test.nim"))
    check lsp.onBufferOpen(buffer).isOk
    check buffer.insertText(BufferPosition(line: 0, column: 0), "x").isOk
    check lsp.syncedStatus(buffer).kind == svSynced
    let versionBeforeUndo = lsp.sentDocumentVersion(tmpDir / "test.nim").get
    check buffer.undo().isOk # changeSeq rolls back here
    check lsp.syncedStatus(buffer).kind == svSynced
    check lsp.sentDocumentVersion(tmpDir / "test.nim").get > versionBeforeUndo

  test "per-document tracking":
    lsp.markReady()
    let bufferA = newTextBuffer("a", some(tmpDir / "a.nim"))
    let bufferB = newTextBuffer("b", some(tmpDir / "b.nim"))
    check lsp.onBufferOpen(bufferA).isOk
    check lsp.onBufferOpen(bufferB).isOk
    check bufferA.insertText(BufferPosition(line: 0, column: 0), "x").isOk
    check lsp.syncedStatus(bufferA).kind == svSynced
    check bufferA.insertText(BufferPosition(line: 0, column: 0), "y").isOk
    check lsp.syncedStatus(bufferA).kind == svSynced
    check lsp.sentDocumentVersion(tmpDir / "a.nim") == some(3)
    check lsp.sentDocumentVersion(tmpDir / "b.nim") == some(1)

  test "version cleared on close":
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check lsp.onBufferOpen(buffer).isOk
    lsp.onBufferClose(buffer)
    check lsp.sentDocumentVersion(tmpDir / "test.nim").isNone

  test "change without open sends didOpen with version 1":
    # Frame does not open; request opens at version 1.
    let buffer = newTextBuffer("test", some(tmpDir / "test.nim"))
    check lsp.syncedStatus(buffer).kind == svBehind
    check lsp.requestSyncGate(buffer, lrfDefinition, lrtUserAction).isNone
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
      check lsp.syncedStatus(buffer).kind == svSynced
    check lsp.sentDocumentVersion(tmpDir / "reopen.nim") == some(4)

    check lsp.onBufferOpen(buffer).isOk
    check lsp.sentDocumentVersion(tmpDir / "reopen.nim") == some(1)

    check buffer.insertText(BufferPosition(line: 0, column: 0), "y").isOk
    check lsp.syncedStatus(buffer).kind == svSynced
    check lsp.sentDocumentVersion(tmpDir / "reopen.nim") == some(2)

  test "serverIsFresh skips defensive didClose on restart re-open":
    lsp.markReady()
    let buffer = newTextBuffer("hi", some(tmpDir / "restart.nim"))
    check lsp.onBufferOpen(buffer).isOk
    check buffer.insertText(BufferPosition(line: 0, column: 0), "x").isOk
    check lsp.syncedStatus(buffer).kind == svSynced
    check lsp.sentDocumentVersion(tmpDir / "restart.nim") == some(2)

    # Server is gone; ledger was told before re-open.
    lsp.forgetServerDocuments("nim")
    check lsp.onBufferOpen(buffer, serverIsFresh = true).isOk
    check lsp.sentDocumentVersion(tmpDir / "restart.nim") == some(1)

  test "a document the replacement server already holds is not re-opened":
    # Already re-opened by the restarting request; skip duplicate didOpen.
    lsp.markReady()
    let buffer = newTextBuffer("hi", some(tmpDir / "held.nim"))
    check lsp.onBufferOpen(buffer).isOk
    check buffer.insertText(BufferPosition(line: 0, column: 0), "x").isOk
    check lsp.syncedStatus(buffer).kind == svSynced
    check lsp.sentDocumentVersion(tmpDir / "held.nim") == some(2)

    check lsp.onBufferOpen(buffer, serverIsFresh = true).isOk
    check lsp.sentDocumentVersion(tmpDir / "held.nim") == some(2)

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

  test "a cwd that is gone is reported as an outage, not as an internal error":
    # Gone cwd is an outage, reported once.
    let gone = tmpDir / "lsp_sync_vanished_cwd"
    removeDir(gone)
    createDir(gone)
    setCurrentDir(gone)
    removeDir(gone)

    clearLspMessageLog()
    let buf = newTextBuffer("hi", some("vanished.nim"))
    let status = lsp.syncedStatus(buf)

    setCurrentDir(tmpDir)

    check status.kind == svBehind
    check getLspMessageLog().len == 1

  test "onBufferSave with a gone cwd returns instead of raising":
    # Same outage through save; void proc returns via verdict.
    let gone = tmpDir / "lsp_save_vanished_cwd"
    removeDir(gone)
    createDir(gone)
    setCurrentDir(gone)
    removeDir(gone)

    clearLspMessageLog()
    let buf = newTextBuffer("hi", some("vanished_save.nim"))
    lsp.onBufferSave(buf)

    setCurrentDir(tmpDir)

    check getLspMessageLog().len == 1

  test "onBufferClose with a gone cwd returns instead of raising":
    # Close does no I/O, so nothing shields it.
    let gone = tmpDir / "lsp_close_vanished_cwd"
    removeDir(gone)
    createDir(gone)
    setCurrentDir(gone)
    removeDir(gone)

    clearLspMessageLog()
    let buf = newTextBuffer("hi", some("vanished_close.nim"))
    lsp.onBufferClose(buf)

    setCurrentDir(tmpDir)

    check getLspMessageLog().len == 0

  test "onBufferOpen with a gone cwd reports an error instead of raising":
    let gone = tmpDir / "lsp_open_vanished_cwd"
    removeDir(gone)
    createDir(gone)
    setCurrentDir(gone)
    removeDir(gone)

    clearLspMessageLog()
    let buf = newTextBuffer("hi", some("vanished_open.nim"))
    check lsp.onBufferOpen(buf).isErr

    setCurrentDir(tmpDir)

    check getLspMessageLog().len == 1

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
    check lsp.syncedStatus(relBuf).kind == svSynced
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

    # No claim stands; close is named by path alone.
    lsp.openedPaths.clear()
    let closeBuf = newTextBuffer("hi", some("canonical_close.nim"))
    lsp.onBufferClose(closeBuf)
    check lsp.documents.len == 0

suite "LspIntegration - syncBuffer":
  privateAccess(LspIntegration)

  var lsp: LspIntegration
  setup:
    lsp = newLspIntegration(tmpDir)
    lsp.service.liveWorkerOverride = proc(path: string): bool =
      true
  teardown:
    lsp.shutdown()

  test "flush advances wire version when buffer drifted since last sync":
    # Regression: explicit flush catches up before positional request.
    let path = tmpDir / "flush_drift.nim"
    let buffer = newTextBuffer("hi", some(path))
    check lsp.onBufferOpen(buffer).isOk
    check lsp.sentDocumentVersion(path) == some(1)

    check buffer.insertText(BufferPosition(line: 0, column: 0), "x").isOk
    check lsp.syncedStatus(buffer).kind == svSynced
    check lsp.sentDocumentVersion(path) == some(2)

  test "flush is a no-op when server shadow already matches":
    let path = tmpDir / "flush_insync.nim"
    let buffer = newTextBuffer("hi", some(path))
    check lsp.onBufferOpen(buffer).isOk
    check lsp.sentDocumentVersion(path) == some(1)

    check lsp.syncedStatus(buffer).kind == svSynced
    check lsp.sentDocumentVersion(path) == some(1)

  test "a worker lost at enqueue time is Behind, not Synced":
    # Regression: enqueue race must read as Behind.
    var calls = 0
    var freezeAt = high(int)
    lsp.service.liveWorkerOverride = proc(path: string): bool =
      inc calls
      # Live for open and pre-checks, gone at enqueue.
      calls <= freezeAt
    let path = tmpDir / "enqueue_race.nim"
    let buffer = newTextBuffer("hi", some(path))
    check lsp.onBufferOpen(buffer).isOk
    check lsp.sentDocumentVersion(path) == some(1)
    # Short-circuit leaves one pre-check before enqueue.
    freezeAt = calls + 1

    check buffer.insertText(BufferPosition(line: 0, column: 0), "x").isOk
    let verdict = lsp.syncedStatus(buffer)
    check verdict.kind == svBehind
    check verdict.blocker == sbNoServer
    # Nothing handed over; shadow and version unchanged.
    check lsp.documents[canonicalPath(path)].shadow == "hi"
    check lsp.sentDocumentVersion(path) == some(1)

  test "flush is safe when LSP is disabled":
    lsp.setEnabled(false)
    let buffer = newTextBuffer("hi", some(tmpDir / "flush_disabled.nim"))
    check lsp.syncedStatus(buffer).kind == svNotApplicable

  test "flush is safe when buffer has no path":
    let buffer = newTextBuffer("hi")
    check lsp.syncedStatus(buffer).kind == svNotApplicable

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
    lsp.documents[tmpDir / "test.nim"] =
      initLspDocumentState(1, "code", delivered = true)
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

  test "applyWorkspaceEdit surfaces an apply failure as an err":
    # Regression: a failing edit (here an out-of-bounds line) must come back
    # as an err through the raise-and-convert layer, not as an exception, and
    # the transaction must be rolled back. The
    # "(buffer state may be inconsistent)" suffix is reserved for the
    # failed-rollback case, so it must not appear here.
    let buffer = newTextBuffer("hello", some(tmpDir / "fail.txt"))
    var buffers = @[buffer]
    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(tmpDir / "fail.txt")] = @[
      TextEdit(
        range: Range(
          start: Position(line: -1, character: 0),
          `end`: Position(line: -1, character: 0),
        ),
        newText: "x",
      )
    ]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check "Failed to apply edits" in result.error
    check "Failed to insert text" in result.error
    check "buffer state may be inconsistent" notin result.error
    check not buffer.inTransaction
    check buffer.getLine(0) == "hello"

  test "applyWorkspaceEdit failure reports already-modified buffers":
    # The first target is edited, then the second fails to apply: the err must
    # disclose that an earlier buffer was already modified (the warning path
    # rewritten to raise-and-convert). documentChanges fixes the order.
    let okBuffer = newTextBuffer("hello", some(tmpDir / "ok_modify.txt"))
    let failBuffer = newTextBuffer("world", some(tmpDir / "fail_modify.txt"))
    var buffers = @[okBuffer, failBuffer]
    let edit = WorkspaceEdit(
      changes: none(Table[string, seq[TextEdit]]),
      documentChanges: some(
        @[
          TextDocumentEdit(
            textDocument: OptionalVersionedTextDocumentIdentifier(
              uri: pathToUri(tmpDir / "ok_modify.txt"), version: some(1)
            ),
            edits: @[TextEdit(range: newRange(0, 0, 0, 5), newText: "HELLO")],
          ),
          TextDocumentEdit(
            textDocument: OptionalVersionedTextDocumentIdentifier(
              uri: pathToUri(tmpDir / "fail_modify.txt"), version: some(1)
            ),
            edits: @[
              TextEdit(
                range: Range(
                  start: Position(line: -1, character: 0),
                  `end`: Position(line: -1, character: 0),
                ),
                newText: "x",
              )
            ],
          ),
        ]
      ),
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check "Failed to apply edits" in result.error
    check "1 buffer(s) already modified" in result.error
    check "ok_modify.txt" in result.error
    check okBuffer.getLine(0) == "HELLO"
    check failBuffer.getLine(0) == "world"

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

  test "applyWorkspaceEdit refuses before writing when an open target is raw":
    let bufferA = newTextBuffer("hello", some(tmpDir / "raw_open_peer.txt"))
    let bufferB = newTextBuffer("world", some(tmpDir / "raw_open_target.txt"))
    bufferB.keepRaw = true
    var buffers = @[bufferA, bufferB]

    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(tmpDir / "raw_open_peer.txt")] =
      @[TextEdit(range: newRange(0, 0, 0, 5), newText: "HELLO")]
    changes[pathToUri(tmpDir / "raw_open_target.txt")] =
      @[TextEdit(range: newRange(0, 0, 0, 5), newText: "WORLD")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )

    let result = applyWorkspaceEdit(buffers, edit)

    check result.isErr
    check "no edits applied" in result.error
    check bufferA.getLine(0) == "hello"
    check bufferB.getLine(0) == "world"

  test "applyWorkspaceEdit refuses two overlapping edit groups aimed at one file":
    # Overlapping groups have no defined combined result: merging them would
    # apply both to the same text and silently corrupt the buffer.
    # Distinct URI spellings of one file collapse here the same way.
    let targetPath = tmpDir / "dup_target.txt"
    let buffer = newTextBuffer("hello", some(targetPath))
    var buffers = @[buffer]
    let edit = WorkspaceEdit(
      changes: none(Table[string, seq[TextEdit]]),
      documentChanges: some(
        @[
          TextDocumentEdit(
            textDocument: OptionalVersionedTextDocumentIdentifier(
              uri: pathToUri(targetPath), version: some(1)
            ),
            edits: @[TextEdit(range: newRange(0, 0, 0, 5), newText: "world")],
          ),
          TextDocumentEdit(
            textDocument: OptionalVersionedTextDocumentIdentifier(
              uri: pathToUri(tmpDir / "." / "dup_target.txt"), version: some(2)
            ),
            edits: @[TextEdit(range: newRange(0, 0, 0, 5), newText: "other")],
          ),
        ]
      ),
    )

    let result = applyWorkspaceEdit(buffers, edit)

    check result.isErr
    check "more than once" in result.error
    check "no edits applied" in result.error
    check buffer.getLine(0) == "hello"

  test "applyWorkspaceEdit merges two disjoint edit groups aimed at one file":
    # The spec lets a server split one file's edits across documentChanges
    # entries. Both groups are positioned against the same starting text, so
    # they are one set of edits applied back-to-front.
    let targetPath = tmpDir / "merge_target.txt"
    let buffer = newTextBuffer("hello world", some(targetPath))
    var buffers = @[buffer]
    let edit = WorkspaceEdit(
      changes: none(Table[string, seq[TextEdit]]),
      documentChanges: some(
        @[
          TextDocumentEdit(
            textDocument: OptionalVersionedTextDocumentIdentifier(
              uri: pathToUri(targetPath), version: some(1)
            ),
            edits: @[TextEdit(range: newRange(0, 0, 0, 5), newText: "HI")],
          ),
          TextDocumentEdit(
            textDocument: OptionalVersionedTextDocumentIdentifier(
              uri: pathToUri(tmpDir / "." / "merge_target.txt"), version: some(1)
            ),
            edits: @[TextEdit(range: newRange(0, 6, 0, 11), newText: "THERE")],
          ),
        ]
      ),
    )

    let result = applyWorkspaceEdit(buffers, edit)

    check result.isOk
    # One target, so one modified file even though two groups named it.
    check result.get.modifiedCount == 1
    check buffer.getLine(0) == "HI THERE"

  test "applyWorkspaceEdit refuses a file no buffer holds":
    # Nothing is rewritten on disk: a target no buffer holds refuses the whole
    # edit, and nothing is modified.
    var buffers: seq[TextBuffer] = @[]
    let targetPath = tmpDir / "unopened_disallowed.txt"
    writeFile(targetPath, "hello")
    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(targetPath)] =
      @[TextEdit(range: newRange(0, 0, 0, 5), newText: "world")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check result.error.contains("not open in the editor")
    check result.error.contains(targetPath)
    check readFile(targetPath) == "hello"

  test "applyWorkspaceEdit refuses mixed targets, nothing half-applied":
    # An edit targeting both an open buffer and an unopened file must be
    # refused whole: the open buffer is left untouched and the unopened file
    # is not written.
    let openPath = tmpDir / "mixed_open.txt"
    let closedPath = tmpDir / "mixed_closed.txt"
    writeFile(openPath, "aaa")
    writeFile(closedPath, "bbb")
    var buffers: seq[TextBuffer] = @[newTextBuffer("aaa", some(openPath))]
    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(openPath)] =
      @[TextEdit(range: newRange(0, 0, 0, 3), newText: "xxx")]
    changes[pathToUri(closedPath)] =
      @[TextEdit(range: newRange(0, 0, 0, 3), newText: "yyy")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check result.error.contains(closedPath)
    check buffers[0].getTextString() == "aaa"
    check readFile(closedPath) == "bbb"

  test "applyWorkspaceEdit refuses a file no buffer holds via documentChanges":
    # The documentChanges branch must refuse an unopened target just like the
    # changes branch: the whole edit is discarded and nothing is written.
    var buffers: seq[TextBuffer] = @[]
    let targetPath = tmpDir / "unopened_doc_disallowed.txt"
    writeFile(targetPath, "hello")
    let docEdit = TextDocumentEdit(
      textDocument: OptionalVersionedTextDocumentIdentifier(
        uri: pathToUri(targetPath), version: some(1)
      ),
      edits: @[TextEdit(range: newRange(0, 0, 0, 5), newText: "world")],
    )
    let edit = WorkspaceEdit(
      changes: none(Table[string, seq[TextEdit]]), documentChanges: some(@[docEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check result.error.contains("not open in the editor")
    check result.error.contains(targetPath)
    check readFile(targetPath) == "hello"

  test "applyWorkspaceEdit refuses mixed documentChanges targets, nothing half-applied":
    # An edit via documentChanges targeting both an open buffer and an unopened
    # file must be refused whole: the open buffer is left untouched and the
    # unopened file is not written.
    let openPath = tmpDir / "mixed_doc_open.txt"
    let closedPath = tmpDir / "mixed_doc_closed.txt"
    writeFile(openPath, "aaa")
    writeFile(closedPath, "bbb")
    var buffers: seq[TextBuffer] = @[newTextBuffer("aaa", some(openPath))]
    let docChanges = @[
      TextDocumentEdit(
        textDocument: OptionalVersionedTextDocumentIdentifier(
          uri: pathToUri(openPath), version: some(1)
        ),
        edits: @[TextEdit(range: newRange(0, 0, 0, 3), newText: "xxx")],
      ),
      TextDocumentEdit(
        textDocument: OptionalVersionedTextDocumentIdentifier(
          uri: pathToUri(closedPath), version: some(1)
        ),
        edits: @[TextEdit(range: newRange(0, 0, 0, 3), newText: "yyy")],
      ),
    ]
    let edit = WorkspaceEdit(
      changes: none(Table[string, seq[TextEdit]]), documentChanges: some(docChanges)
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check result.error.contains(closedPath)
    check buffers[0].getTextString() == "aaa"
    check readFile(closedPath) == "bbb"

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

  test "applyWorkspaceEdit refuses a non-file URI":
    var buffers: seq[TextBuffer] = @[]
    var changes = initTable[string, seq[TextEdit]]()
    changes["http://example.com/file.txt"] =
      @[TextEdit(range: newRange(0, 0, 0, 0), newText: "x")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check result.error.contains("only file:/// is allowed")
    check result.error.contains("http://example.com/file.txt")

  test "applyWorkspaceEdit refuses a file:// URI with a non-empty authority":
    var buffers: seq[TextBuffer] = @[]
    var changes = initTable[string, seq[TextEdit]]()
    changes["file://server/share/file.txt"] =
      @[TextEdit(range: newRange(0, 0, 0, 0), newText: "x")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check result.error.contains("only file:/// is allowed")
    check result.error.contains("file://server/share/file.txt")

  test "applyWorkspaceEdit refuses a URI with a raw query or fragment":
    var buffers: seq[TextBuffer] = @[]
    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(tmpDir / "a.txt") & "?query=1"] =
      @[TextEdit(range: newRange(0, 0, 0, 0), newText: "x")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check result.error.contains("unsupported character")
    check result.error.contains("?query=1")

  test "applyWorkspaceEdit refuses an empty file:/// path":
    var buffers: seq[TextBuffer] = @[]
    var changes = initTable[string, seq[TextEdit]]()
    changes["file:///"] = @[TextEdit(range: newRange(0, 0, 0, 0), newText: "x")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check result.error.contains("empty path")

  test "applyWorkspaceEdit refuses a URI with an encoded NUL":
    var buffers: seq[TextBuffer] = @[]
    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(tmpDir / "a.txt").replace("a.txt", "a%00.txt")] =
      @[TextEdit(range: newRange(0, 0, 0, 0), newText: "x")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check result.error.contains("unsupported character")
    check result.error.contains("%00.txt")

  test "applyWorkspaceEdit refuses a file:// URI with an extra leading slash":
    var buffers: seq[TextBuffer] = @[]
    var changes = initTable[string, seq[TextEdit]]()
    changes["file:////tmp/x.txt"] =
      @[TextEdit(range: newRange(0, 0, 0, 0), newText: "x")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check result.error.contains("extra leading slash")

  test "applyWorkspaceEdit refuses an encoded extra leading slash":
    var buffers: seq[TextBuffer] = @[]
    var changes = initTable[string, seq[TextEdit]]()
    changes["file:///%2Ftmp/x.txt"] =
      @[TextEdit(range: newRange(0, 0, 0, 0), newText: "x")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check result.error.contains("extra leading slash")

  test "applyWorkspaceEdit refuses a decoded empty path":
    # "file:///%2F" decodes to "//", which is not a usable single-root path
    var buffers: seq[TextBuffer] = @[]
    var changes = initTable[string, seq[TextEdit]]()
    changes["file:///%2F"] = @[TextEdit(range: newRange(0, 0, 0, 0), newText: "x")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check result.error.contains("extra leading slash")

  test "applyWorkspaceEdit refuses short file:// URIs":
    for uri in ["file://", "file://a"]:
      var buffers: seq[TextBuffer] = @[]
      var changes = initTable[string, seq[TextEdit]]()
      changes[uri] = @[TextEdit(range: newRange(0, 0, 0, 0), newText: "x")]
      let edit = WorkspaceEdit(
        changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
      )
      let result = applyWorkspaceEdit(buffers, edit)
      check result.isErr
      check result.error.contains("only file:/// is allowed")

  test "applyWorkspaceEdit refuses the whole documentChanges edit when a target is invalid":
    var buffers = @[newTextBuffer("aaa", some(tmpDir / "ok.txt"))]
    let docChanges = @[
      TextDocumentEdit(
        textDocument: OptionalVersionedTextDocumentIdentifier(
          uri: pathToUri(tmpDir / "ok.txt"), version: some(1)
        ),
        edits: @[TextEdit(range: newRange(0, 0, 0, 3), newText: "AAA")],
      ),
      TextDocumentEdit(
        textDocument: OptionalVersionedTextDocumentIdentifier(
          uri: "file:///tmp/bad%00.txt", version: some(1)
        ),
        edits: @[TextEdit(range: newRange(0, 0, 0, 0), newText: "x")],
      ),
    ]
    let edit = WorkspaceEdit(
      changes: none(Table[string, seq[TextEdit]]), documentChanges: some(docChanges)
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check buffers[0].getTextString() == "aaa"

  test "applyWorkspaceEdit applies an edit to a URI with an encoded space":
    var buffers = @[newTextBuffer("aaa", some(tmpDir / "my file.txt"))]
    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(tmpDir / "my file.txt")] =
      @[TextEdit(range: newRange(0, 0, 0, 3), newText: "AAA")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isOk
    check result.get.modifiedCount == 1
    check buffers[0].getTextString() == "AAA"

  test "applyWorkspaceEdit refuses the whole edit when one of several targets is invalid":
    var buffers: seq[TextBuffer] = @[newTextBuffer("aaa", some(tmpDir / "ok.txt"))]
    var changes = initTable[string, seq[TextEdit]]()
    changes[pathToUri(tmpDir / "ok.txt")] =
      @[TextEdit(range: newRange(0, 0, 0, 3), newText: "AAA")]
    changes["ftp://example.com/other.txt"] =
      @[TextEdit(range: newRange(0, 0, 0, 0), newText: "x")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check buffers[0].getTextString() == "aaa"

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

  test "applyDiagnosticsToBuffer does not store out-of-range start lines":
    let buffer = newTextBuffer("line1\nline2")
    let diagnostics = @[
      Diagnostic(
        range: newRange(5, 0, 5, 3),
        severity: some(dsError),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "past EOF",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      ),
      Diagnostic(
        range: newRange(-1, 0, -1, 3),
        severity: some(dsWarning),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "negative line",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      ),
      Diagnostic(
        range: newRange(0, 0, 0, 3),
        severity: some(dsError),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "valid",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      ),
    ]
    applyDiagnosticsToBuffer(buffer, diagnostics)
    # Storage must match the marker pass: out-of-range start lines are skipped.
    check buffer.diagnostics.len == 1
    check buffer.diagnostics[0].startLine == 0
    check buffer.diagnostics[0].message == "valid"

  test "applyDiagnosticsToBuffer clamps an out-of-range end line":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let diagnostics = @[
      Diagnostic(
        range: newRange(1, 0, 100, 3),
        severity: some(dsError),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "runs to EOF",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      )
    ]
    applyDiagnosticsToBuffer(buffer, diagnostics)
    check buffer.diagnostics.len == 1
    check buffer.diagnostics[0].startLine == 1
    check buffer.diagnostics[0].endLine == buffer.len - 1

  test "applyDiagnosticsToBuffer degenerates a reversed range":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let diagnostics = @[
      Diagnostic(
        range: newRange(2, 0, 0, 3),
        severity: some(dsError),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "reversed",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      )
    ]
    applyDiagnosticsToBuffer(buffer, diagnostics)
    check buffer.diagnostics.len == 1
    check buffer.diagnostics[0].startLine == 2
    check buffer.diagnostics[0].endLine == 2

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

  test "stamping NoServer does not clear other failure streaks":
    # Only landed sync clears unrelated streaks.
    var doc = initLspDocumentState(1, "x", delivered = true)
    let id = BufferId(424242)
    doc.recordSyncAttempt(
      id,
      1,
      SyncVerdict(kind: svBehind, blocker: sbTransport, detail: "boom"),
      "document sync test",
    )
    check getLspMessageLog().len == 1

    doc.recordSyncAttempt(id, 1, SyncVerdict(kind: svNoServer), "document sync test")

    # Streak survived iff re-stamping stays silent.
    doc.recordSyncAttempt(
      id,
      1,
      SyncVerdict(kind: svBehind, blocker: sbTransport, detail: "boom"),
      "document sync test",
    )
    check getLspMessageLog().len == 1

  test "stamping Synced clears failure streaks":
    var doc = initLspDocumentState(1, "x", delivered = true)
    let id = BufferId(424243)
    doc.recordSyncAttempt(
      id,
      1,
      SyncVerdict(kind: svBehind, blocker: sbTransport, detail: "boom"),
      "document sync test",
    )
    check getLspMessageLog().len == 1

    doc.recordSyncAttempt(id, 1, SyncVerdict(kind: svSynced), "document sync test")

    doc.recordSyncAttempt(
      id,
      1,
      SyncVerdict(kind: svBehind, blocker: sbTransport, detail: "boom"),
      "document sync test",
    )
    check getLspMessageLog().len == 2

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

suite "LspIntegration - a worker coming up retires the memos waiting on it":
  privateAccess(LspIntegration)

  test "A stale memo is retired when its language server initializes":
    # Init retires the waiting memo.
    let lsp = newLspIntegration()
    defer:
      lsp.shutdown()

    let path = canonicalPath(tmpDir / "waiting.nim")
    lsp.documents[path] = initLspDocumentState(1, "old", delivered = true)
    lsp.documents[path].attempt = some(
      LspSyncAttempt(
        bufferId: BufferId(1),
        contentVersion: 1,
        verdict: SyncVerdict(kind: svBehind, blocker: sbNoServer),
      )
    )

    lsp.service.processEvent("nim", LspEvent(kind: levInitialized))

    check lsp.documents[path].attempt.isNone

  test "A memo that landed is left alone, and other languages are untouched":
    let lsp = newLspIntegration()
    defer:
      lsp.shutdown()

    let synced = canonicalPath(tmpDir / "landed.nim")
    lsp.documents[synced] = initLspDocumentState(1, "x", delivered = true)
    lsp.documents[synced].attempt = some(
      LspSyncAttempt(
        bufferId: BufferId(1), contentVersion: 1, verdict: SyncVerdict(kind: svSynced)
      )
    )

    let otherLang = canonicalPath(tmpDir / "waiting.rs")
    lsp.documents[otherLang] = initLspDocumentState(1, "y", delivered = true)
    lsp.documents[otherLang].attempt = some(
      LspSyncAttempt(
        bufferId: BufferId(2), contentVersion: 1, verdict: SyncVerdict(kind: svBehind)
      )
    )

    lsp.service.processEvent("nim", LspEvent(kind: levInitialized))

    check lsp.documents[synced].attempt.isSome
    check lsp.documents[otherLang].attempt.isSome

suite "LspIntegration - incremental didChange":
  privateAccess(LspIntegration)

  let Path = tmpDir / "test.nim"

  # onBufferOpen spawns a real worker; teardown joins it.
  var lsp: LspIntegration
  setup:
    lsp = newLspIntegration()
  teardown:
    lsp.shutdown()

  proc setKind(lsp: LspIntegration, syncKind: int, saveIncludesText = true) =
    lsp.service.processEvent(
      "nim",
      LspEvent(
        kind: levCapabilities,
        capabilitiesJson: $(
          %*{
            "textDocumentSync":
              {"change": syncKind, "save": {"includeText": saveIncludesText}}
          }
        ),
      ),
    )

  proc markReady(lsp: LspIntegration) =
    ## Force running server for deterministic sync.
    lsp.service.liveWorkerOverride = proc(path: string): bool =
      true
    lsp.service.runningWorkerOverride = proc(path: string): bool =
      true

  proc markStarting(lsp: LspIntegration) =
    ## Force starting worker to fall back to full sync.
    lsp.service.liveWorkerOverride = proc(path: string): bool =
      true
    lsp.service.runningWorkerOverride = proc(path: string): bool =
      false

  proc markNoWorker(lsp: LspIntegration) =
    ## Force no worker for deterministic skip.
    lsp.service.liveWorkerOverride = proc(path: string): bool =
      false
    lsp.service.runningWorkerOverride = proc(path: string): bool =
      false

  test "raw buffer is never announced to the server":
    # The wire is JSON; bytes that are not valid UTF-8 cannot ride on it.
    let raw = newTextBuffer("abc", some(Path))
    raw.keepRaw = true
    check not raw.isLspEligible

    check lsp.onBufferOpen(raw).isOk

    check Path notin lsp.documents

  test "a buffer that turns raw on reload is dropped":
    # Reload rewrites in place; raw buffer drops its document.
    let buf = newTextBuffer("abc", some(Path))
    discard lsp.onBufferOpen(buf)
    check Path in lsp.documents

    buf.keepRaw = true
    check lsp.onBufferOpen(buf).isOk

    check Path notin lsp.documents

  test "a sync of a file no server claims forgets the record left behind":
    # Stale record without a server is forgotten.
    let unclaimed = tmpDir / "test.unclaimed"
    lsp.documents[unclaimed] = initLspDocumentState(1, "abc", delivered = true)
    lsp.markReady()

    let buffer = newTextBuffer("abcd", some(unclaimed))

    check lsp.syncedStatus(buffer).kind == svNoServer

    check unclaimed notin lsp.documents

  test "editing a raw buffer does not open it through the change path":
    # Sync needs the same gate as open.
    let raw = newTextBuffer("abcd", some(Path))
    raw.keepRaw = true
    lsp.markReady()

    check lsp.syncedStatus(raw).kind == svNotApplicable

    check Path notin lsp.documents

  test "saving a raw buffer does not ship its bytes":
    # didSave needs the same gate as didChange.
    let buf = newTextBuffer("abc", some(Path))
    discard lsp.onBufferOpen(buf)
    check Path in lsp.documents

    buf.keepRaw = true
    lsp.onBufferSave(buf)

    check Path notin lsp.documents

  test "a save is not sent for a document the server no longer holds":
    # No didOpen means no didSave.
    var saved: seq[string]
    lsp.service.documentSavedObserver = proc(path: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        saved.add(path)

    let buf = newTextBuffer("abc", some(Path))
    lsp.documents[Path] = initLspDocumentState(1, buf.getTextString(), delivered = true)
    lsp.markNoWorker()

    lsp.onBufferSave(buf)

    check saved.len == 0
    check not lsp.documents[Path].delivered

  test "a save is sent while the server still holds the document":
    var saved: seq[string]
    lsp.service.documentSavedObserver = proc(path: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        saved.add(path)

    let buf = newTextBuffer("abc", some(Path))
    lsp.documents[Path] = initLspDocumentState(1, buf.getTextString(), delivered = true)
    lsp.markReady()

    lsp.onBufferSave(buf)

    check saved == @[Path]

  test "a change-less server still gets the save that catches it up":
    # Save is the only catch-up for tdskNone.
    var saved: seq[string]
    lsp.service.documentSavedObserver = proc(path: string) {.gcsafe.} =
      {.cast(gcsafe).}:
        saved.add(path)

    lsp.documents[Path] = initLspDocumentState(1, "stale", delivered = true)
    lsp.setKind(0)
    lsp.markReady()

    lsp.onBufferSave(newTextBuffer("abc", some(Path)))

    check saved == @[Path]

  test "requests against a raw buffer are refused":
    let raw = newTextBuffer("abc", some(Path))
    raw.keepRaw = true

    let r = lsp.startHoverRequest(raw, 0, 0)

    check r.isErr
    check r.error == RawBufferLspRejection

  test "server-computed edits are never applied to a raw buffer":
    # The edit positions are UTF-16 offsets into text the server decoded; they
    # do not address the bytes a raw buffer holds.
    let raw = newTextBuffer("abc", some(Path))
    raw.keepRaw = true
    let edits = @[
      TextEdit(
        range: Range(
          start: Position(line: 0, character: 0), `end`: Position(line: 0, character: 1)
        ),
        newText: "X",
      )
    ]

    let r = applyTextEdits(raw, edits)

    check r.isErr
    check r.error == RawBufferLspRejection
    check raw.getLine(0) == "abc"

  test "onBufferOpen seeds shadow and version 1":
    check lsp.onBufferOpen(newTextBuffer("abc", some(Path))).isOk
    check lsp.documents[Path].shadow == "abc"
    check lsp.documents[Path].version == 1

  test "no-op change leaves version and shadow untouched":
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    check lsp.syncedStatus(newTextBuffer("abc", some(Path))).kind == svSynced
    check lsp.documents[Path].version == 1
    check lsp.documents[Path].shadow == "abc"

  test "incremental change bumps version and updates shadow":
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markReady()
    check lsp.syncedStatus(newTextBuffer("abXc", some(Path))).kind == svSynced
    check lsp.documents[Path].version == 2
    check lsp.documents[Path].shadow == "abXc"

  test "starting worker falls back to full sync; version and shadow advance":
    # A starting worker cannot receive incremental changes (the worker drops
    # them), so the integration must send full sync to coalesce into the
    # pending didOpen. The shadow still advances to the latest text.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markStarting()
    check lsp.syncedStatus(newTextBuffer("abXc", some(Path))).kind == svSynced
    check lsp.documents[Path].version == 2
    check lsp.documents[Path].shadow == "abXc"

  test "no ready worker: change is skipped and the copy is reported stale":
    # Gone server holds nothing; request would be uninformed.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2) # incremental advertised, but no server is ready
    lsp.markNoWorker() # deterministic: ignore the worker onBufferOpen spawned
    let status = lsp.syncedStatus(newTextBuffer("abXc", some(Path)))
    check status.kind == svBehind
    check status.reason.len > 0
    check lsp.documents[Path].version == 1
    # Gone copy owes didOpen, not didChange.
    check not lsp.documents[Path].delivered
    check lsp.documents[Path].shadow == ""

  test "a matching shadow does not prove the server is still there":
    # Shadow records sent text, not who holds it.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markReady()
    check lsp.syncedStatus(newTextBuffer("abXc", some(Path))).kind == svSynced
    check lsp.documents[Path].version == 2
    check lsp.documents[Path].shadow == "abXc"

    lsp.markNoWorker()
    # Same text but different buffer, so sync runs.
    let buf = newTextBuffer("abXc", some(Path))

    check lsp.requestSyncGate(buf, lrfDefinition, lrtUserAction).isNone
    # Retracted and re-opened, not diffed.
    check lsp.documents[Path].version == 1

  test "a timer's request waits out the retry interval; a key press does not":
    # Refused sync retries on budget; key press retries at once.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markNoWorker()

    let buf = newTextBuffer("abXc", some(Path))
    check lsp.requestSyncGate(buf, lrfDocumentHighlight).isNone
    let firstAttempt = lsp.documents[Path].attempt.get.at

    check lsp.requestSyncGate(buf, lrfDocumentHighlight).isNone
    check lsp.documents[Path].attempt.get.at == firstAttempt

    discard lsp.requestSyncGate(buf, lrfDefinition, lrtUserAction)
    check lsp.documents[Path].attempt.get.at != firstAttempt

  test "initialization retires the wait so the next frame sync retries at once":
    # Init retires the memo so frame sync retries.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markNoWorker()

    let buf = newTextBuffer("abXc", some(Path))
    check lsp.syncedStatus(buf).kind == svBehind
    let firstAttempt = lsp.documents[Path].attempt.get.at

    # Still inside retry interval; answered from memo.
    check lsp.syncedStatus(buf).kind == svBehind
    check lsp.documents[Path].attempt.get.at == firstAttempt

    # Server coming up retires the wait...
    lsp.service.processEvent("nim", LspEvent(kind: levInitialized))
    lsp.markReady()

    # ...so next frame sync retries at once.
    check lsp.syncedStatus(buf).kind == svSynced

  test "a recovered sync clears the streak so the next outage is reported":
    # Recovered sync clears streak so next outage logs.
    clearLspMessageLog()
    let buf = newTextBuffer("abc", some(Path))
    discard lsp.onBufferOpen(buf)
    lsp.setKind(2)

    lsp.markNoWorker()
    check buf.insertText(BufferPosition(line: 0, column: 2), "X").isOk
    check lsp.syncedStatus(buf).kind == svBehind
    check buf.insertText(BufferPosition(line: 0, column: 2), "Y").isOk
    check lsp.syncedStatus(buf).kind == svBehind
    check getLspMessageLog().len == 1

    lsp.markReady()
    check buf.insertText(BufferPosition(line: 0, column: 2), "Z").isOk
    check lsp.syncedStatus(buf).kind == svSynced

    lsp.markNoWorker()
    check buf.insertText(BufferPosition(line: 0, column: 2), "W").isOk
    check lsp.syncedStatus(buf).kind == svBehind
    check getLspMessageLog().len == 2

  test "syncBuffer reports an unusable path instead of raising":
    # Gone cwd must return, not take down the frame.
    clearLspMessageLog()
    let originalDir = getCurrentDir()
    let doomed = tmpDir / "moe_sync_doomed_cwd"
    createDir(doomed)
    setCurrentDir(doomed)
    defer:
      setCurrentDir(originalDir)
    removeDir(doomed)

    let buf = newTextBuffer("abc", some("relative.nim"))
    lsp.syncBuffer(buf)

    check lsp.syncedStatus(buf).kind == svBehind
    check getLspMessageLog().len == 1

  test "a buffer reopened after an outage can report its next one":
    # Re-open clears streak so next outage logs.
    clearLspMessageLog()
    let buf = newTextBuffer("abc", some(Path))
    discard lsp.onBufferOpen(buf)
    lsp.setKind(2)

    lsp.markNoWorker()
    check buf.insertText(BufferPosition(line: 0, column: 2), "X").isOk
    check lsp.syncedStatus(buf).kind == svBehind
    check getLspMessageLog().len == 1

    lsp.markReady()
    check lsp.onBufferOpen(buf).isOk

    lsp.markNoWorker()
    check buf.insertText(BufferPosition(line: 0, column: 2), "Y").isOk
    check lsp.syncedStatus(buf).kind == svBehind
    check getLspMessageLog().len == 2

  test "tdskNone leaves the copy behind, and says so":
    # Declined sync leaves old copy; requests see old text.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(0)
    lsp.markReady() # a server that is there and refuses, not one that is gone
    let status = lsp.syncedStatus(newTextBuffer("abXc", some(Path)))
    check status.kind == svUnsyncable
    check not status.syncSettled
    check lsp.documents[Path].version == 1
    check lsp.documents[Path].shadow == "abc"

  test "tdskNone with a matching copy is in sync":
    # Unedited copy is current despite no updates.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(0)
    lsp.markReady()
    check lsp.syncedStatus(newTextBuffer("abc", some(Path))).kind == svSynced

  test "saving catches up the copy a tdskNone server was left with":
    # didSave is the only catch-up for such a server.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(0)
    lsp.markReady()
    let buf = newTextBuffer("abXc", some(Path))
    check lsp.syncedStatus(buf).kind == svUnsyncable

    lsp.onBufferSave(buf)

    check lsp.documents[Path].shadow == "abXc"
    check lsp.syncedStatus(buf).kind == svSynced

  test "a request is refused when the server accepts no changes":
    # Disk-based copy has stale coordinates.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(0)
    lsp.markReady()
    let buf = newTextBuffer("abXc", some(Path))

    check lsp.requestSyncGate(buf, lrfDefinition, lrtUserAction).isSome
    check lsp.requestSyncGate(buf, lrfFormatting, lrtUserAction).isSome
    check lsp.documents[Path].attempt.get.verdict.kind == svUnsyncable

    # Decorations still run.
    check lsp.requestSyncGate(buf, lrfHover).isNone

    # Refusal names the act that lifts it.
    check "save the file" in lsp.requestSyncGate(buf, lrfFormatting, lrtUserAction).get

  test "a refusal no act of the user could lift is not a refusal":
    # No user act can move this copy; do not refuse.
    clearLspMessageLog()
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(0, saveIncludesText = false)
    lsp.markReady()
    let buf = newTextBuffer("abXc", some(Path))

    check lsp.syncedStatus(buf).kind == svUnsyncable
    check lsp.requestSyncGate(buf, lrfDefinition, lrtUserAction).isNone
    check lsp.requestSyncGate(buf, lrfFormatting, lrtUserAction).isNone

    # Still a degradation, logged once.
    check getLspMessageLog().len == 1

  test "a rename off a served extension closes the document it left behind":
    # Record is named by buffer, not current path.
    let buf = newTextBuffer("abc", some(Path))
    check lsp.onBufferOpen(buf).isOk
    check Path in lsp.documents

    buf.filePath = some(tmpDir / "test.unclaimed")
    lsp.markReady()

    check lsp.syncedStatus(buf).kind == svNoServer
    check Path notin lsp.documents
    check buf.id notin lsp.openedPaths

  test "a rename between served extensions moves the document, not copies it":
    let buf = newTextBuffer("abc", some(Path))
    check lsp.onBufferOpen(buf).isOk
    lsp.setKind(2)
    lsp.markReady()

    let renamed = tmpDir / "renamed.nim"
    buf.filePath = some(renamed)

    check lsp.syncedStatus(buf).kind == svSynced
    check Path notin lsp.documents
    check renamed in lsp.documents
    check lsp.openedPaths[buf.id] == renamed

  test "closing a renamed buffer closes the URI it actually opened":
    let buf = newTextBuffer("abc", some(Path))
    check lsp.onBufferOpen(buf).isOk

    buf.filePath = some(tmpDir / "closed_elsewhere.nim")

    lsp.onBufferClose(buf)
    check Path notin lsp.documents
    check buf.id notin lsp.openedPaths

  test "the shared request helper passes the caller's trigger to the gate":
    # Helper must pass trigger; default grades user press as timer.
    privateAccess(LspService)
    privateAccess(LspDocumentState)

    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markNoWorker()
    check lsp.service.stopWorker("nim").isOk
    # Both refused; only trigger decides fresh attempt.
    lsp.service.enabled = false

    let buf = newTextBuffer("abXc", some(Path))
    check lsp.syncedStatus(buf).kind == svBehind
    let stampedAt = lsp.documents[Path].attempt.get.at

    # Shared helper without the await.
    check resolveLspPathForRequest(lsp, buf, lrfFormatting).isErr
    check lsp.documents[Path].attempt.get.at == stampedAt

    check resolveLspPathForRequest(lsp, buf, lrfFormatting, lrtUserAction).isErr
    check lsp.documents[Path].attempt.get.at > stampedAt

  test "a shared path stays open for the buffer that did not move":
    # One URI, two buffers; closing one keeps the other.
    let stays = newTextBuffer("abc", some(Path))
    let moves = newTextBuffer("abc", some(Path))
    check lsp.onBufferOpen(stays).isOk
    check lsp.onBufferOpen(moves).isOk
    lsp.markReady()

    moves.filePath = some(tmpDir / "moved_away.unclaimed")
    check lsp.syncedStatus(moves).kind == svNoServer

    check Path in lsp.documents
    check lsp.openedPaths[stays.id] == Path
    check moves.id notin lsp.openedPaths

  test "closing one of two buffers on a path leaves the other one open":
    # One URI; closing one buffer keeps the other.
    let stays = newTextBuffer("abc", some(Path))
    let closes = newTextBuffer("abc", some(Path))
    check lsp.onBufferOpen(stays).isOk
    check lsp.onBufferOpen(closes).isOk

    lsp.onBufferClose(closes)

    check Path in lsp.documents
    check lsp.openedPaths[stays.id] == Path
    check closes.id notin lsp.openedPaths

    # Last claim closes it.
    lsp.onBufferClose(stays)
    check Path notin lsp.documents

  test "a buffer closed with LSP off still gives up its claim":
    # Closed buffer must not read as live holder.
    let buf = newTextBuffer("abc", some(Path))
    check lsp.onBufferOpen(buf).isOk
    check lsp.openedPaths[buf.id] == Path

    lsp.setEnabled(false)
    lsp.onBufferClose(buf)
    check buf.id notin lsp.openedPaths

    lsp.setEnabled(true)
    let reopened = newTextBuffer("abc", some(Path))
    check lsp.onBufferOpen(reopened).isOk
    lsp.onBufferClose(reopened)
    check Path notin lsp.documents

  test "a restart forgets the document a renamed buffer opened":
    # Unreachable record after restart must go.
    let buf = newTextBuffer("abc", some(Path))
    check lsp.onBufferOpen(buf).isOk
    check Path in lsp.documents

    buf.filePath = some(tmpDir / "restarted_away.unclaimed")
    check lsp.onBufferOpen(buf, serverIsFresh = true).isOk

    check Path notin lsp.documents
    check buf.id notin lsp.openedPaths

  test "a restart moves the claim of a buffer renamed across served extensions":
    # Claim follows buffer; fresh server holds one document.
    let buf = newTextBuffer("abc", some(Path))
    check lsp.onBufferOpen(buf).isOk
    lsp.markReady()

    let renamed = tmpDir / "restarted_renamed.nim"
    buf.filePath = some(renamed)
    check lsp.onBufferOpen(buf, serverIsFresh = true).isOk

    check Path notin lsp.documents
    check lsp.openedPaths[buf.id] == renamed

  test "a missing server reads the same whether one was configured or not":
    # No one to ask; both refuse alike.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markNoWorker()
    # Gone worker with no restart still refuses.
    check lsp.service.stopWorker("nim").isOk
    lsp.service.enabled = false

    let dead = newTextBuffer("abXc", some(Path))
    let unclaimed = newTextBuffer("abc", some(tmpDir / "plain.unclaimed"))

    let deadRefusal = lsp.requestSyncGate(dead, lrfDefinition, lrtUserAction)
    let unclaimedRefusal = lsp.requestSyncGate(unclaimed, lrfDefinition, lrtUserAction)
    check deadRefusal.isSome
    check unclaimedRefusal.isSome
    check "no running language server" in deadRefusal.get
    check "no running language server" in unclaimedRefusal.get

  test "a save clears the refusal a change-less server earned":
    # Save hands server the same bytes.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(0)
    lsp.markReady()
    let buf = newTextBuffer("abXc", some(Path))
    check lsp.requestSyncGate(buf, lrfDefinition, lrtUserAction).isSome

    lsp.onBufferSave(buf)

    check lsp.requestSyncGate(buf, lrfDefinition, lrtUserAction).isNone

  test "a refusal a save cannot lift is not raised at all":
    # Dead worker has no save; request fails on its own.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(0)
    lsp.markReady()

    let buf = newTextBuffer("abXc", some(Path))
    check "save the file" in lsp.requestSyncGate(buf, lrfDefinition, lrtUserAction).get

    lsp.markNoWorker()
    check lsp.requestSyncGate(buf, lrfDefinition, lrtUserAction).isNone

  test "a starting server still earns the refusal a save will lift":
    # Save has not moved shadow yet; refusal stands.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(0)
    lsp.markStarting()

    let buf = newTextBuffer("abXc", some(Path))
    check lsp.syncedStatus(buf).kind == svUnsyncable
    check "save the file" in lsp.requestSyncGate(buf, lrfRename, lrtUserAction).get

    # Decorations tolerate stale copy.
    check lsp.requestSyncGate(buf, lrfHover).isNone

  test "a save delivers the edit the save itself made":
    # Save-time rewrite is an edit; didChange carries it.
    discard lsp.onBufferOpen(newTextBuffer("abc ", some(Path)))
    lsp.setKind(2)
    lsp.markReady()

    let trimmed = newTextBuffer("abc", some(Path))
    lsp.onBufferSave(trimmed)

    check lsp.documents[Path].shadow == "abc"
    # didChange carried the trim; save records nothing.
    check lsp.documents[Path].version == 2
    check lsp.syncedStatus(trimmed).kind == svSynced

  test "a save cannot stand in for a didChange no server received":
    # Save never makes a didChange server look synced.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markNoWorker()

    let buf = newTextBuffer("abXc", some(Path))
    lsp.onBufferSave(buf)

    check lsp.documents[Path].shadow == ""
    check not lsp.documents[Path].delivered
    check lsp.syncedStatus(buf).kind == svBehind

  test "a save whose text the server discards is not recorded as one":
    # Discarded save text leaves shadow unchanged.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(0, saveIncludesText = false)
    lsp.markReady()
    let unsaved = newTextBuffer("abXc", some(Path))
    check lsp.syncedStatus(unsaved).kind == svUnsyncable

    lsp.onBufferSave(unsaved)

    check lsp.documents[Path].shadow == "abc"
    check lsp.syncedStatus(unsaved).kind == svUnsyncable

  test "a save while the server is starting is held until initialization":
    # Starting worker holds didSave until didOpen flushes.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(0)
    lsp.markReady()
    let buf = newTextBuffer("abXc", some(Path))
    check lsp.syncedStatus(buf).kind == svUnsyncable

    lsp.markStarting()
    lsp.onBufferSave(buf)

    check lsp.documents[Path].shadow == "abXc"
    check lsp.syncedStatus(buf).kind == svSynced

  test "a wire ack confirms the queued version":
    # Ack advances confirmed version only.
    lsp.documents[Path] = initLspDocumentState(1, "", delivered = false)
    lsp.documents[Path].version = 2
    lsp.documents[Path].noteServerHolds("new")
    check lsp.documents[Path].ackedVersion == 0

    lsp.applySyncAck(pathToUri(Path), 2, 0, true)

    check lsp.documents[Path].ackedVersion == 2
    check lsp.documents[Path].delivered
    check lsp.documents[Path].shadow == "new"

  test "a nack for unacked work retracts the delivery":
    # Enqueue-then-crash leaves unseen shadow; nack re-opens.
    lsp.documents[Path] = initLspDocumentState(1, "", delivered = false)
    lsp.documents[Path].version = 2
    lsp.documents[Path].noteServerHolds("new")

    lsp.applySyncAck(pathToUri(Path), 2, 0, false)

    check not lsp.documents[Path].delivered
    check lsp.documents[Path].shadow == ""
    check lsp.documents[Path].syncAttempt.isNone

  test "a nack for already-acked work is ignored":
    lsp.documents[Path] = initLspDocumentState(2, "new", delivered = true)
    check lsp.documents[Path].ackedVersion == 2

    lsp.applySyncAck(pathToUri(Path), 1, 0, false)

    check lsp.documents[Path].delivered
    check lsp.documents[Path].shadow == "new"

  test "a nack retraction makes the next sync re-open":
    lsp.documents[Path] = initLspDocumentState(1, "", delivered = false)
    lsp.documents[Path].version = 2
    lsp.documents[Path].noteServerHolds("new")
    lsp.applySyncAck(pathToUri(Path), 2, 0, false)
    lsp.markReady()

    let buf = newTextBuffer("new", some(Path))
    check lsp.syncedStatus(buf).kind == svSynced
    check lsp.documents[Path].shadow == "new"
    check lsp.documents[Path].delivered

  test "an ack from an older epoch is dropped":
    # Dead server ack confirms nothing.
    lsp.documents[Path] = initLspDocumentState(1, "", delivered = false)
    lsp.documents[Path].version = 2
    lsp.documents[Path].noteServerHolds("new")
    lsp.documents[Path].nextGeneration()
    lsp.documents[Path].version = 1
    lsp.documents[Path].noteServerHolds("new")

    lsp.applySyncAck(pathToUri(Path), 2, 0, true)

    check lsp.documents[Path].ackedVersion == 0
    check lsp.documents[Path].delivered
    check lsp.documents[Path].shadow == "new"

  test "a nack from an older epoch does not retract the fresh document":
    lsp.documents[Path] = initLspDocumentState(1, "", delivered = false)
    lsp.documents[Path].version = 2
    lsp.documents[Path].noteServerHolds("new")
    lsp.documents[Path].nextGeneration()
    lsp.documents[Path].version = 1
    lsp.documents[Path].noteServerHolds("new")

    lsp.applySyncAck(pathToUri(Path), 2, 0, false)

    check lsp.documents[Path].delivered
    check lsp.documents[Path].shadow == "new"

  test "a new epoch unblocks nacks the old confirmed version shadowed":
    # Regression: new epoch must unblock fresh nacks.
    lsp.documents[Path] = initLspDocumentState(1, "", delivered = false)
    lsp.documents[Path].version = 5
    lsp.documents[Path].noteServerHolds("old")
    lsp.applySyncAck(pathToUri(Path), 5, 0, true)
    check lsp.documents[Path].ackedVersion == 5

    lsp.documents[Path].nextGeneration()
    lsp.documents[Path].version = 2
    lsp.documents[Path].noteServerHolds("new")

    lsp.applySyncAck(pathToUri(Path), 2, 1, false)

    check not lsp.documents[Path].delivered
    check lsp.documents[Path].shadow == ""

  test "a nack for the confirmed version retracts the sharing save":
    # Shared-version nack retracts the save.
    lsp.documents[Path] = initLspDocumentState(2, "new", delivered = true)
    check lsp.documents[Path].ackedVersion == 2

    lsp.applySyncAck(pathToUri(Path), 2, 0, false)

    check not lsp.documents[Path].delivered
    check lsp.documents[Path].shadow == ""

  test "a same-generation re-open clears the stale confirmed version":
    # Regression: re-open clears stale acked version.
    lsp.documents[Path] = initLspDocumentState(1, "", delivered = false)
    lsp.documents[Path].version = 5
    lsp.documents[Path].noteServerHolds("old")
    lsp.applySyncAck(pathToUri(Path), 5, 0, true)
    check lsp.documents[Path].ackedVersion == 5

    lsp.documents[Path].version = 6
    lsp.documents[Path].noteServerHolds("new")
    lsp.applySyncAck(pathToUri(Path), 6, 0, false)
    check not lsp.documents[Path].delivered

    lsp.markReady()
    let buf = newTextBuffer("new", some(Path))
    check lsp.syncedStatus(buf).kind == svSynced
    check lsp.documents[Path].ackedVersion == 0
    check lsp.documents[Path].version == 1

    lsp.applySyncAck(pathToUri(Path), 1, 0, false)

    check not lsp.documents[Path].delivered
    check lsp.documents[Path].shadow == ""

  test "a sync ack arriving as a worker event is routed to the document":
    lsp.documents[Path] = initLspDocumentState(1, "", delivered = false)
    lsp.documents[Path].version = 2
    lsp.documents[Path].noteServerHolds("new")

    lsp.service.processEvent(
      "nim",
      LspEvent(
        kind: levSyncAck,
        ackUri: pathToUri(Path),
        ackVersion: 2,
        ackOk: true,
        ackGeneration: 0,
      ),
    )

    check lsp.documents[Path].ackedVersion == 2
    check lsp.documents[Path].delivered

  test "reopening a file no server claims forgets the record left behind":
    # Outlived record without a server is forgotten.
    let unclaimed = tmpDir / "notes.unclaimedext"
    let unclaimedPath = canonicalPath(unclaimed)
    lsp.documents[unclaimedPath] = initLspDocumentState(1, "old", delivered = true)

    check lsp.onBufferOpen(newTextBuffer("new", some(unclaimed))).isOk

    check unclaimedPath notin lsp.documents

  test "an unsyncable document is retried once the server accepts changes":
    # Capability change re-derives the memo.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(0)
    lsp.markReady()
    let buf = newTextBuffer("abXc", some(Path))
    check lsp.syncedStatus(buf).kind == svUnsyncable

    # Same content: memo answers.
    check lsp.syncedStatus(buf).kind == svUnsyncable

    lsp.setKind(2)
    lsp.markReady()

    check lsp.syncedStatus(buf).kind == svSynced
    check lsp.documents[Path].shadow == "abXc"

  test "an idle unsyncable document is not re-materialized on a timer":
    # Idle unsyncable document never retries on timer.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(0)
    lsp.markReady()
    let buf = newTextBuffer("abXc", some(Path))
    check lsp.syncedStatus(buf).kind == svUnsyncable

    let stampedAt = lsp.documents[Path].attempt.get.at
    lsp.documents[Path].attempt.get.at =
      getMonoTime() - initDuration(seconds = int(StaleSyncRetryIntervalSeconds) + 1)

    lsp.syncBuffer(buf)

    # Fresh attempt would stamp a new memo.
    check lsp.documents[Path].attempt.get.at < stampedAt

  test "a request with no worker asks for one so a crashed server can come back":
    # Refused request asks for restart; frame does not.
    privateAccess(LspService)

    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markNoWorker()

    # Crash stand-in: only fresh start brings it back.
    check lsp.service.stopWorker("nim").isOk
    check "nim" notin lsp.service.workers

    let buf = newTextBuffer("abXc", some(Path))
    discard lsp.requestSyncGate(buf, lrfDefinition, lrtUserAction)

    check "nim" in lsp.service.workers

  test "a request the editor fires on a timer leaves a crashed server alone":
    # Timer-driven decorating requests must not respawn.
    privateAccess(LspService)

    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markNoWorker()

    check lsp.service.stopWorker("nim").isOk
    check "nim" notin lsp.service.workers

    let buf = newTextBuffer("abXc", some(Path))
    for feature in [lrfSemanticTokens, lrfInlayHint, lrfCodeLens, lrfDocumentHighlight]:
      # Decorating request asks but never respawns.
      check lsp.requestSyncGate(buf, feature).isNone
      check "nim" notin lsp.service.workers

  test "starting a timer-driven request does not respawn a crashed server":
    # Start resolves existing worker only.
    privateAccess(LspService)

    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markNoWorker()

    check lsp.service.stopWorker("nim").isOk
    check "nim" notin lsp.service.workers

    let buf = newTextBuffer("abXc", some(Path))
    check lsp.requestSyncGate(buf, lrfCodeLens).isNone

    check lsp.service.startCodeLensRequest(Path).isErr
    check lsp.service.startDocumentHighlightRequest(Path, 0, 0).isErr
    check lsp.service.startSemanticTokensFullRequest(Path).isErr
    check lsp.service.startInlayHintRequest(Path, 0, 0, 0, 1).isErr
    check "nim" notin lsp.service.workers

  test "a gate asked without a trigger neither respawns nor jumps the interval":
    # Respawn authority belongs to call site, not feature.
    privateAccess(LspService)

    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markNoWorker()

    check lsp.service.stopWorker("nim").isOk
    check "nim" notin lsp.service.workers

    let buf = newTextBuffer("abXc", some(Path))

    # Same buffer; only trigger differs.
    check lsp.requestSyncGate(buf, lrfDefinition).isSome
    check "nim" notin lsp.service.workers

    # User request reaches server and lands document.
    check lsp.requestSyncGate(buf, lrfDefinition, lrtUserAction).isNone
    check "nim" in lsp.service.workers

  test "a per-keystroke request does not respawn a crashed server":
    # Per-keystroke requests must not respawn.
    privateAccess(LspService)

    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markNoWorker()

    check lsp.service.stopWorker("nim").isOk
    check "nim" notin lsp.service.workers

    let buf = newTextBuffer("abXc", some(Path))
    for feature in [lrfCompletion, lrfSignatureHelp]:
      discard lsp.requestSyncGate(buf, feature)
      check "nim" notin lsp.service.workers

  test "the frame path leaves a crashed server alone":
    # Frame path never respawns crash-looping server.
    privateAccess(LspService)

    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markNoWorker()

    check lsp.service.stopWorker("nim").isOk
    check "nim" notin lsp.service.workers

    let status = lsp.syncedStatus(newTextBuffer("abXc", some(Path)))

    check status.kind == svBehind
    check "nim" notin lsp.service.workers

  test "one outage is logged once however the sync path reached it":
    # Same outage from any path logs once.
    clearLspMessageLog()

    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markNoWorker()

    # Gone worker fails inside startWorker.
    check lsp.service.stopWorker("nim").isOk
    lsp.service.enabled = false

    let buf = newTextBuffer("abXc", some(Path))
    let framed = lsp.syncedStatus(buf)
    check framed.kind == svBehind
    check getLspMessageLog().len == 1

    # Request fails for its own reason.
    check lsp.requestSyncGate(buf, lrfDefinition, lrtUserAction).isSome
    check getLspMessageLog().len == 1

  test "a request re-attempts a sync the retry interval would have skipped":
    # Request must not inherit stale memo.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    lsp.setKind(2)
    lsp.markNoWorker()

    let buf = newTextBuffer("abXc", some(Path))
    check lsp.syncedStatus(buf).kind == svBehind

    lsp.markReady()

    # Young memo: frame stands by it.
    check lsp.syncedStatus(buf).kind == svBehind

    # The request does not.
    check lsp.requestSyncGate(buf, lrfDefinition, lrtUserAction).isNone
    check lsp.documents[Path].shadow == "abXc"

  test "onBufferClose removes shadow":
    let buf = newTextBuffer("abc", some(Path))
    discard lsp.onBufferOpen(buf)
    lsp.onBufferClose(buf)
    check Path notin lsp.documents

  test "shadow tracks server text across consecutive edits":
    discard lsp.onBufferOpen(newTextBuffer("a\nb\nc", some(Path)))
    lsp.setKind(2)
    lsp.markReady()
    # The invariant is shadow == buffer.getTextString() (the text actually sent),
    # not the raw input string, since the buffer normalizes its content.
    for raw in ["a\nb\nX\nc", "a\nc", "a\nc\nd\ne", "done"]:
      let buf = newTextBuffer(raw, some(Path))
      check lsp.syncedStatus(buf).kind == svSynced
      check lsp.documents[Path].shadow == buf.getTextString()

  test "undelivered didOpen is retried on next change":
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    # Simulate failed delivery.
    lsp.documents[Path].delivered = false
    lsp.markReady()
    check lsp.syncedStatus(newTextBuffer("abcd", some(Path))).kind == svSynced
    check lsp.documents[Path].delivered
    check lsp.documents[Path].version == 1
    check lsp.documents[Path].shadow == "abcd"

  test "an open that never lands leaves no shadow to mistake for sent text":
    # Failed open leaves empty shadow.
    lsp.service.enabled = false

    check lsp.syncedStatus(newTextBuffer("abc", some(Path))).kind == svBehind
    check not lsp.documents[Path].delivered
    check lsp.documents[Path].shadow.len == 0

  test "onBufferOpen keeps the shadow empty when the didOpen fails":
    lsp.service.enabled = false

    check lsp.onBufferOpen(newTextBuffer("abc", some(Path))).isErr
    check not lsp.documents[Path].delivered
    check lsp.documents[Path].shadow.len == 0

  test "a stopped server takes the record of what it held with it":
    # Server death empties holdings, keeps entry.
    discard lsp.onBufferOpen(newTextBuffer("abc", some(Path)))
    check lsp.documents[Path].delivered
    check lsp.documents[Path].shadow == "abc"

    check lsp.service.stopWorker("nim").isOk

    check not lsp.documents[Path].delivered
    check lsp.documents[Path].shadow.len == 0
    check lsp.documents[Path].syncAttempt.isNone

    # Entry stays; next sync re-opens.
    check Path in lsp.documents

  test "onBufferClose is no-op when not tracked":
    # didClose gate: a buffer the server never saw must not send didClose.
    let untracked = tmpDir / "untracked.nim"
    check untracked notin lsp.documents
    lsp.onBufferClose(newTextBuffer("x", some(untracked)))
    check untracked notin lsp.documents

  test "onBufferClose drops an undelivered entry without sending didClose":
    # Undelivered document needs no didClose.
    let undelivered = canonicalPath(tmpDir / "undelivered.nim")
    lsp.documents[undelivered] = initLspDocumentState(1, "hi", delivered = false)
    lsp.onBufferClose(newTextBuffer("hi", some(undelivered)))
    check undelivered notin lsp.documents

  test "an extension no server claims is left untracked, not failed":
    # Unclaimed file leaves nothing tracked.
    let badPath = tmpDir / "no_lsp.unknownlspext"
    let buf = newTextBuffer("hi", some(badPath))
    check lsp.lspParticipation(buf) == lpNoServer
    check lsp.onBufferOpen(buf).isOk
    check canonicalPath(badPath) notin lsp.documents

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

  proc noteAttempt(lsp: LspIntegration, buf: TextBuffer, attempt: LspSyncAttempt) =
    ## Memo an attempt onto its document record.
    let path = canonicalPath(buf.filePath.get)
    if path notin lsp.documents:
      lsp.documents[path] = initLspDocumentState(1, "", delivered = true)
    lsp.documents[path].attempt = some(attempt)

  proc noteSynced(lsp: LspIntegration, buf: TextBuffer) =
    ## Baseline server as holding current buffer text.
    lsp.noteAttempt(
      buf,
      LspSyncAttempt(
        bufferId: buf.id,
        contentVersion: buf.contentVersion,
        verdict: SyncVerdict(kind: svSynced),
      ),
    )

  proc noteStale(lsp: LspIntegration, buf: TextBuffer) =
    ## Record a covering attempt that never landed.
    lsp.noteAttempt(
      buf,
      LspSyncAttempt(
        bufferId: buf.id,
        contentVersion: buf.contentVersion,
        verdict: SyncVerdict(kind: svBehind, blocker: sbNoServer),
      ),
    )

  test "server-held buffer in sync is not stale":
    lsp.setLiveWorkers(true)
    let buf = newTextBuffer("aaa", some(tmpDir / "a.nim"))
    lsp.noteSynced(buf)

    check not lsp.hasStaleServerEditTarget(@[buf], editFor(tmpDir / "a.nim"))

  test "server-held buffer edited since the last sync is stale":
    lsp.setLiveWorkers(true)
    let buf = newTextBuffer("aaa", some(tmpDir / "a.nim"))
    lsp.noteSynced(buf)
    discard buf.insertText(BufferPosition(line: 0, column: 3), "!")

    check lsp.hasStaleServerEditTarget(@[buf], editFor(tmpDir / "a.nim"))

  test "buffer the server never received is stale when it has unsaved changes":
    # Regression: bad baseline must still read as stale.
    lsp.setLiveWorkers(false)
    let buf = newTextBuffer("aaa", some(tmpDir / "Cargo.toml"))
    discard buf.insertText(BufferPosition(line: 0, column: 3), "!")
    lsp.noteSynced(buf)

    check lsp.hasStaleServerEditTarget(@[buf], editFor(tmpDir / "Cargo.toml"))

  test "buffer the server never received is not stale when it matches disk":
    lsp.setLiveWorkers(false)
    let buf = newTextBuffer("aaa", some(tmpDir / "Cargo.toml"))
    lsp.noteSynced(buf)

    check not lsp.hasStaleServerEditTarget(@[buf], editFor(tmpDir / "Cargo.toml"))

  test "an attempt that never landed falls back to the disk comparison":
    # Covering attempt still falls back to disk text.
    lsp.setLiveWorkers(true)
    let buf = newTextBuffer("aaa", some(tmpDir / "a.nim"))
    lsp.documents[canonicalPath(tmpDir / "a.nim")] =
      initLspDocumentState(1, "aaa", delivered = true)
    discard buf.insertText(BufferPosition(line: 0, column: 3), "!")
    lsp.noteStale(buf)

    check lsp.hasStaleServerEditTarget(@[buf], editFor(tmpDir / "a.nim"))

  test "live worker but no sync baseline falls back to the disk comparison":
    # didOpen never succeeded, so the server has no copy of this document.
    lsp.setLiveWorkers(true)
    let buf = newTextBuffer("aaa", some(tmpDir / "a.nim"))

    check not lsp.hasStaleServerEditTarget(@[buf], editFor(tmpDir / "a.nim"))

    discard buf.insertText(BufferPosition(line: 0, column: 3), "!")
    check lsp.hasStaleServerEditTarget(@[buf], editFor(tmpDir / "a.nim"))

  test "undelivered didOpen falls back to the disk comparison despite a baseline":
    # Delivered flag decides, not baseline alone.
    lsp.setLiveWorkers(true)
    let buf = newTextBuffer("aaa", some(tmpDir / "a.nim"))
    lsp.noteSynced(buf)
    lsp.documents[canonicalPath(tmpDir / "a.nim")] =
      initLspDocumentState(1, "aaa", delivered = false)

    check not lsp.hasStaleServerEditTarget(@[buf], editFor(tmpDir / "a.nim"))

    discard buf.insertText(BufferPosition(line: 0, column: 3), "!")
    check lsp.hasStaleServerEditTarget(@[buf], editFor(tmpDir / "a.nim"))

  test "a buffer outside the edit's targets is ignored":
    lsp.setLiveWorkers(false)
    let target = newTextBuffer("aaa", some(tmpDir / "a.nim"))
    let other = newTextBuffer("bbb", some(tmpDir / "b.nim"))
    discard other.insertText(BufferPosition(line: 0, column: 3), "!")
    lsp.noteSynced(target)

    check not lsp.hasStaleServerEditTarget(@[target, other], editFor(tmpDir / "a.nim"))
