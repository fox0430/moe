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
  std/[unittest, json, options, tables, times, strutils, importutils, deques, random]

import pkg/results

import ../src/moepkg/[lsp_integration, buffer, message_log]
import ../src/moepkg/lsp/protocol/types

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
    check text.len <= MaxProgressTextLen + 10 # Allow some margin for UTF-8

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

suite "LspIntegration - newLspIntegration":
  privateAccess(LspIntegration)

  test "creates integration with default workspace":
    let lsp = newLspIntegration()
    check lsp.enabled
    check lsp.documents.len == 0
    check lsp.pendingMessages.len == 0
    check lsp.activeProgress.len == 0

  test "creates integration with custom workspace":
    let lsp = newLspIntegration("/tmp/test")
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

suite "LspIntegration - Buffer Operations (disabled)":
  privateAccess(LspIntegration)

  test "onBufferOpen returns ok when disabled":
    let lsp = newLspIntegration()
    lsp.enabled = false
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.onBufferOpen(buffer)
    check result.isOk

  test "onBufferClose returns ok when disabled":
    let lsp = newLspIntegration()
    lsp.enabled = false
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.onBufferClose(buffer)
    check result.isOk

  test "onBufferChange returns ok when disabled":
    let lsp = newLspIntegration()
    lsp.enabled = false
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.onBufferChange(buffer)
    check result.isOk

  test "onBufferSave returns ok when disabled":
    let lsp = newLspIntegration()
    lsp.enabled = false
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.onBufferSave(buffer)
    check result.isOk

  test "onBufferOpen returns ok for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    let result = lsp.onBufferOpen(buffer)
    check result.isOk

suite "LspIntegration - Request Methods (disabled)":
  test "startCompletionRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startCompletionRequest(buffer, 0, 0)
    check result.isErr
    check "disabled" in result.error

  test "startHoverRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startHoverRequest(buffer, 0, 0)
    check result.isErr

  test "startDefinitionRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startDefinitionRequest(buffer, 0, 0)
    check result.isErr

  test "startReferencesRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startReferencesRequest(buffer, 0, 0)
    check result.isErr

  test "startCompletionRequest returns error for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    let result = lsp.startCompletionRequest(buffer, 0, 0)
    check result.isErr
    check "file path" in result.error

suite "LspIntegration - Feature Support Checks (disabled)":
  test "hasCodeLensSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasCodeLensSupport(buffer)

  test "hasDocumentHighlightSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasDocumentHighlightSupport(buffer)

  test "hasDocumentSymbolSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasDocumentSymbolSupport(buffer)

  test "hasFoldingRangeSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasFoldingRangeSupport(buffer)

  test "hasRenameSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasRenameSupport(buffer)

  test "hasCallHierarchySupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasCallHierarchySupport(buffer)

  test "hasDocumentLinkSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasDocumentLinkSupport(buffer)

suite "LspIntegration - Completion/SignatureHelp capability gating":
  privateAccess(LspService)

  test "hasCompletionSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasCompletionSupport(buffer)

  test "hasCompletionSupport reflects the advertised server capability":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    # Enabled (the default) but the server has not advertised completion yet.
    check not lsp.hasCompletionSupport(buffer)
    lsp.service.capabilities["nim"] =
      ServerCapabilities(completionProvider: some(CompletionOptions()))
    check lsp.hasCompletionSupport(buffer)

  test "hasSignatureHelpSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasSignatureHelpSupport(buffer)

  test "hasSignatureHelpSupport reflects the advertised server capability":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasSignatureHelpSupport(buffer)
    lsp.service.capabilities["nim"] =
      ServerCapabilities(signatureHelpProvider: some(SignatureHelpOptions()))
    check lsp.hasSignatureHelpSupport(buffer)

suite "LspIntegration - Shutdown":
  privateAccess(LspIntegration)

  test "shutdown clears all state":
    let lsp = newLspIntegration()
    lsp.documents["/tmp/test.nim"] = (version: 1, shadow: "code")
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
    var buffers = @[newTextBuffer("hello", some("/tmp/test.txt"))]
    var changes = initTable[string, seq[TextEdit]]()
    changes["file:///tmp/test.txt"] = @[
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
    var buffers = @[newTextBuffer("aaa", some("/tmp/test.txt"))]

    # Create changes that would modify to "bbb"
    var changes = initTable[string, seq[TextEdit]]()
    changes["file:///tmp/test.txt"] = @[
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
          uri: "file:///tmp/test.txt", version: some(1)
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

suite "LspIntegration - Additional Request Methods (disabled)":
  test "startDeclarationRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startDeclarationRequest(buffer, 0, 0)
    check result.isErr

  test "startTypeDefinitionRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startTypeDefinitionRequest(buffer, 0, 0)
    check result.isErr

  test "startImplementationRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startImplementationRequest(buffer, 0, 0)
    check result.isErr

  test "startSignatureHelpRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startSignatureHelpRequest(buffer, 0, 0)
    check result.isErr

  test "startDocumentHighlightRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startDocumentHighlightRequest(buffer, 0, 0)
    check result.isErr

  test "startCodeLensRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startCodeLensRequest(buffer)
    check result.isErr

  test "startDocumentSymbolsRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startDocumentSymbolsRequest(buffer)
    check result.isErr

  test "startDocumentLinkRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startDocumentLinkRequest(buffer)
    check result.isErr

  test "startSelectionRangeRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startSelectionRangeRequest(buffer, 0, 0)
    check result.isErr

  test "startSemanticTokensRequest returns error when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startSemanticTokensRequest(buffer, 0, 10)
    check result.isErr

suite "LspIntegration - Additional Feature Support Checks":
  test "hasCodeLensResolveSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasCodeLensResolveSupport(buffer)

  test "hasDocumentLinkResolveSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasDocumentLinkResolveSupport(buffer)

  test "hasExecuteCommandSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
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
    check lsp.hasServerForPath("/tmp/test.nim")
    check lsp.hasServerForPath("/tmp/test.py")
    check lsp.hasServerForPath("/tmp/test.rs")

  test "hasServerForPath with unknown extension":
    let lsp = newLspIntegration()
    check not lsp.hasServerForPath("/tmp/test.xyz")
    check not lsp.hasServerForPath("/tmp/noextension")

  test "isServerRunningForPath returns false when no server running":
    let lsp = newLspIntegration()
    check not lsp.isServerRunningForPath("/tmp/test.nim")

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
      proc(uri: string, diagnostics: seq[Diagnostic]) {.gcsafe.} =
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

suite "LspIntegration - getSemanticTokensLegend":
  test "getSemanticTokensLegend returns none when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check lsp.getSemanticTokensLegend(buffer).isNone

  test "getSemanticTokensLegend returns none for buffer without path":
    let lsp = newLspIntegration()
    let buffer = newTextBuffer("test")
    check lsp.getSemanticTokensLegend(buffer).isNone

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

  const Path = "/tmp/test.nim"

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
