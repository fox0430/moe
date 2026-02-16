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

import std/[unittest, json, options, tables, times, strutils, importutils]

import pkg/results

import ../src/moepkg/lsp_integration
import ../src/moepkg/buffer
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
    check lsp.openBuffers.len == 0
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

  test "hasInlineValueSupport returns false when disabled":
    let lsp = newLspIntegration()
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasInlineValueSupport(buffer)

suite "LspIntegration - Shutdown":
  privateAccess(LspIntegration)

  test "shutdown clears all state":
    let lsp = newLspIntegration()
    lsp.openBuffers = @["/tmp/test.nim"]
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

    check lsp.openBuffers.len == 0
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
    check result.get == 0

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
    check result.get == 1
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
    check buffer.getLineMarker(1) == some(SidebarItemKind.SyntaxError)

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
    check buffer.getLineMarker(0) == some(SidebarItemKind.SyntaxWarning)

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
    check buffer.getLineMarker(0) == some(SidebarItemKind.SyntaxError)

  test "applyDiagnosticsToBuffer clears existing markers":
    let buffer = newTextBuffer("line1\nline2")
    buffer.setLineMarker(0, SidebarItemKind.SyntaxError)
    buffer.setLineMarker(1, SidebarItemKind.SyntaxWarning)

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
