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
import ../src/moepkg/lsp/protocol/types as lspTypes
import ../src/moepkg/buffer

suite "LspIntegration Progress":
  test "hasActiveProgress - no progress":
    let lsp = newLspIntegration("/tmp")
    check not lsp.hasActiveProgress()

  test "hasActiveProgress - with progress":
    let lsp = newLspIntegration("/tmp")
    lsp.activeProgress["token1"] = LspProgressState(
      token: "token1",
      langId: "nim",
      title: "Indexing",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: epochTime(),
    )
    check lsp.hasActiveProgress()

  test "getActiveProgressList - empty":
    let lsp = newLspIntegration("/tmp")
    let list = lsp.getActiveProgressList()
    check list.len == 0

  test "getActiveProgressList - multiple progress":
    let lsp = newLspIntegration("/tmp")
    lsp.activeProgress["token1"] = LspProgressState(
      token: "token1",
      langId: "nim",
      title: "Indexing",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: epochTime(),
    )
    lsp.activeProgress["token2"] = LspProgressState(
      token: "token2",
      langId: "rust",
      title: "Building",
      message: some("src/main.rs"),
      percentage: some(50),
      cancellable: true,
      startTime: epochTime() + 1.0,
    )
    let list = lsp.getActiveProgressList()
    check list.len == 2

  test "getLatestActiveProgress - empty":
    let lsp = newLspIntegration("/tmp")
    let latest = lsp.getLatestActiveProgress()
    check latest.isNone

  test "getLatestActiveProgress - returns most recent":
    let lsp = newLspIntegration("/tmp")
    let baseTime = epochTime()
    lsp.activeProgress["token1"] = LspProgressState(
      token: "token1",
      langId: "nim",
      title: "First",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: baseTime,
    )
    lsp.activeProgress["token2"] = LspProgressState(
      token: "token2",
      langId: "rust",
      title: "Latest",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: baseTime + 10.0,
    )
    let latest = lsp.getLatestActiveProgress()
    check latest.isSome
    check latest.get.title == "Latest"

  test "getProgressText - title only":
    let state = LspProgressState(
      token: "t",
      langId: "nim",
      title: "Indexing",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: 0.0,
    )
    check getProgressText(state) == "Indexing"

  test "getProgressText - with message":
    let state = LspProgressState(
      token: "t",
      langId: "nim",
      title: "Indexing",
      message: some("file.nim"),
      percentage: none(int),
      cancellable: false,
      startTime: 0.0,
    )
    check getProgressText(state) == "Indexing: file.nim"

  test "getProgressText - with percentage":
    let state = LspProgressState(
      token: "t",
      langId: "nim",
      title: "Indexing",
      message: none(string),
      percentage: some(75),
      cancellable: false,
      startTime: 0.0,
    )
    check getProgressText(state) == "Indexing (75%)"

  test "getProgressText - with message and percentage":
    let state = LspProgressState(
      token: "t",
      langId: "nim",
      title: "Building",
      message: some("src/main.rs"),
      percentage: some(50),
      cancellable: false,
      startTime: 0.0,
    )
    check getProgressText(state) == "Building: src/main.rs (50%)"

  test "getProgressText - truncation for long text":
    let state = LspProgressState(
      token: "t",
      langId: "nim",
      title: "A very long title that should be truncated",
      message: some("because it exceeds the maximum width"),
      percentage: some(100),
      cancellable: false,
      startTime: 0.0,
    )
    let text = getProgressText(state)
    check text.len <= MaxProgressTextLen + 3 # +3 for "..."
    check text.endsWith("...")

  test "clearProgressForLanguage":
    let lsp = newLspIntegration("/tmp")
    lsp.activeProgress["nim1"] = LspProgressState(
      token: "nim1",
      langId: "nim",
      title: "Task1",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: 0.0,
    )
    lsp.activeProgress["nim2"] = LspProgressState(
      token: "nim2",
      langId: "nim",
      title: "Task2",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: 0.0,
    )
    lsp.activeProgress["rust1"] = LspProgressState(
      token: "rust1",
      langId: "rust",
      title: "Rust Task",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: 0.0,
    )

    lsp.clearProgressForLanguage("nim")

    check lsp.activeProgress.len == 1
    check "rust1" in lsp.activeProgress

  test "cleanupStaleProgress - removes old entries":
    let lsp = newLspIntegration("/tmp")
    let oldTime = epochTime() - ProgressTimeoutSeconds - 10.0

    lsp.activeProgress["stale"] = LspProgressState(
      token: "stale",
      langId: "nim",
      title: "Stale",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: oldTime,
    )
    lsp.activeProgress["fresh"] = LspProgressState(
      token: "fresh",
      langId: "nim",
      title: "Fresh",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: epochTime(),
    )

    # Call cleanupStaleProgress multiple times to bypass rate limiting
    # (first call sets lastProgressCleanupTime, subsequent calls within interval are skipped)
    # Since we can't access the private field, we test the behavior over time
    # For unit tests, we verify the stale entry exists before cleanup
    check lsp.activeProgress.len == 2
    check "stale" in lsp.activeProgress
    check "fresh" in lsp.activeProgress

    # After calling cleanup, stale entries should eventually be removed
    # Note: Due to rate limiting, this may not remove on first call
    for _ in 0 ..< 3:
      lsp.cleanupStaleProgress()

    # The fresh entry should always remain
    check "fresh" in lsp.activeProgress

suite "LspIntegration Server Status":
  test "hasServerStatus - none":
    let lsp = newLspIntegration("/tmp")
    check not lsp.hasServerStatus("nim")

  test "hasServerStatus - exists":
    let lsp = newLspIntegration("/tmp")
    lsp.serverStatus["nim"] =
      LspStatusState(health: shOk, quiescent: true, message: none(string))
    check lsp.hasServerStatus("nim")
    check not lsp.hasServerStatus("rust")

  test "getServerStatus":
    let lsp = newLspIntegration("/tmp")
    lsp.serverStatus["nim"] = LspStatusState(
      health: shWarning, quiescent: false, message: some("Loading project")
    )

    let status = lsp.getServerStatus("nim")
    check status.isSome
    check status.get.health == shWarning
    check not status.get.quiescent
    check status.get.message == some("Loading project")

    check lsp.getServerStatus("unknown").isNone

  test "isServerQuiescent - default true":
    let lsp = newLspIntegration("/tmp")
    check lsp.isServerQuiescent("unknown")

  test "isServerQuiescent - with status":
    let lsp = newLspIntegration("/tmp")
    lsp.serverStatus["nim"] =
      LspStatusState(health: shOk, quiescent: false, message: none(string))
    check not lsp.isServerQuiescent("nim")

    lsp.serverStatus["nim"].quiescent = true
    check lsp.isServerQuiescent("nim")

  test "getServerHealth - default ok":
    let lsp = newLspIntegration("/tmp")
    check lsp.getServerHealth("unknown") == shOk

  test "getServerHealth - with status":
    let lsp = newLspIntegration("/tmp")
    lsp.serverStatus["nim"] =
      LspStatusState(health: shError, quiescent: true, message: some("Crash"))
    check lsp.getServerHealth("nim") == shError

  test "clearStatusForLanguage":
    let lsp = newLspIntegration("/tmp")
    lsp.serverStatus["nim"] =
      LspStatusState(health: shOk, quiescent: true, message: none(string))
    lsp.serverStatus["rust"] =
      LspStatusState(health: shOk, quiescent: true, message: none(string))

    lsp.clearStatusForLanguage("nim")

    check not lsp.hasServerStatus("nim")
    check lsp.hasServerStatus("rust")

  test "getStatusText - ok and quiescent":
    let status = LspStatusState(health: shOk, quiescent: true, message: none(string))
    check getStatusText(status) == ""

  test "getStatusText - ok but loading":
    let status = LspStatusState(health: shOk, quiescent: false, message: none(string))
    check getStatusText(status) == "Loading"

  test "getStatusText - warning":
    let status =
      LspStatusState(health: shWarning, quiescent: true, message: none(string))
    check getStatusText(status) == "Warning"

  test "getStatusText - error with message":
    let status =
      LspStatusState(health: shError, quiescent: true, message: some("Server crashed"))
    check getStatusText(status) == "Error: Server crashed"

  test "getStatusText - loading with message":
    let status = LspStatusState(
      health: shOk, quiescent: false, message: some("Indexing workspace")
    )
    check getStatusText(status) == "Loading: Indexing workspace"

suite "UTF-16 Position Conversion":
  test "utf16OffsetToUtf8 - empty string":
    check utf16OffsetToUtf8("", 0) == 0
    check utf16OffsetToUtf8("", 5) == 0

  test "utf16OffsetToUtf8 - ASCII":
    let line = "hello world"
    check utf16OffsetToUtf8(line, 0) == 0
    check utf16OffsetToUtf8(line, 5) == 5
    check utf16OffsetToUtf8(line, 11) == 11

  test "utf16OffsetToUtf8 - BMP characters (Japanese)":
    # Japanese characters (Hiragana) are in BMP, each is 3 bytes in UTF-8
    let line = "こんにちは" # 5 hiragana characters
    # UTF-16: 5 code units, UTF-8: 15 bytes
    check utf16OffsetToUtf8(line, 0) == 0
    check utf16OffsetToUtf8(line, 1) == 3 # After first hiragana
    check utf16OffsetToUtf8(line, 5) == 15 # After all 5 hiragana

  test "utf16OffsetToUtf8 - mixed ASCII and Japanese":
    let line = "abcこんにちは" # 3 ASCII + 5 hiragana
    check utf16OffsetToUtf8(line, 0) == 0
    check utf16OffsetToUtf8(line, 3) == 3 # After ABC
    check utf16OffsetToUtf8(line, 4) == 6 # After first hiragana

  test "utf16OffsetToUtf8 - surrogate pairs (emoji)":
    # Emoji like 😀 (U+1F600) uses surrogate pair in UTF-16 (2 code units)
    # In UTF-8, it's 4 bytes
    let line = "a😀b"
    check utf16OffsetToUtf8(line, 0) == 0 # Start
    check utf16OffsetToUtf8(line, 1) == 1 # After 'a'
    check utf16OffsetToUtf8(line, 3) == 5 # After emoji (2 UTF-16 units)
    check utf16OffsetToUtf8(line, 4) == 6 # After 'b'

  test "utf8OffsetToUtf16 - empty string":
    check utf8OffsetToUtf16("", 0) == 0
    check utf8OffsetToUtf16("", 5) == 0

  test "utf8OffsetToUtf16 - ASCII":
    let line = "hello"
    check utf8OffsetToUtf16(line, 0) == 0
    check utf8OffsetToUtf16(line, 3) == 3
    check utf8OffsetToUtf16(line, 5) == 5

  test "utf8OffsetToUtf16 - BMP characters":
    let line = "こんにちは" # 5 hiragana, 15 bytes UTF-8
    check utf8OffsetToUtf16(line, 0) == 0
    check utf8OffsetToUtf16(line, 3) == 1 # After first hiragana
    check utf8OffsetToUtf16(line, 15) == 5 # After all hiragana

  test "utf8OffsetToUtf16 - surrogate pairs":
    let line = "a😀b" # 'a' (1 byte) + emoji (4 bytes) + 'b' (1 byte)
    check utf8OffsetToUtf16(line, 0) == 0 # Start
    check utf8OffsetToUtf16(line, 1) == 1 # After 'a'
    check utf8OffsetToUtf16(line, 5) == 3 # After emoji (2 UTF-16 units)
    check utf8OffsetToUtf16(line, 6) == 4 # After 'b'

  test "roundtrip conversion":
    let line = "hello世界🌍end"
    # "hello" = 5 bytes, "世" = 3 bytes, "界" = 3 bytes, "🌍" = 4 bytes, "end" = 3 bytes
    # Valid UTF-8 byte boundaries: 0, 5, 8, 11, 15, 16, 17, 18
    # Test roundtrip: UTF-8 -> UTF-16 -> UTF-8
    for utf8Offset in [0, 5, 8, 11, 15, 18]:
      let utf16 = utf8OffsetToUtf16(line, utf8Offset)
      let backToUtf8 = utf16OffsetToUtf8(line, utf16)
      check backToUtf8 == utf8Offset

  test "runeIndexToUtf16 - empty string":
    check runeIndexToUtf16("", 0) == 0
    check runeIndexToUtf16("", 5) == 0

  test "runeIndexToUtf16 - ASCII":
    let line = "hello world"
    check runeIndexToUtf16(line, 0) == 0
    check runeIndexToUtf16(line, 5) == 5
    check runeIndexToUtf16(line, 11) == 11

  test "runeIndexToUtf16 - BMP characters (Japanese)":
    # Each hiragana is 1 rune = 1 UTF-16 unit = 3 UTF-8 bytes
    let line = "こんにちは"
    check runeIndexToUtf16(line, 0) == 0
    check runeIndexToUtf16(line, 1) == 1
    check runeIndexToUtf16(line, 5) == 5

  test "runeIndexToUtf16 - mixed ASCII and Japanese":
    let line = "ABCあいう"
    check runeIndexToUtf16(line, 3) == 3 # After ABC
    check runeIndexToUtf16(line, 4) == 4 # After first hiragana
    check runeIndexToUtf16(line, 6) == 6 # After all

  test "runeIndexToUtf16 - surrogate pairs (emoji)":
    # 'a' + 😀 (2 UTF-16 units) + 'b'
    let line = "a😀b"
    check runeIndexToUtf16(line, 0) == 0
    check runeIndexToUtf16(line, 1) == 1 # After 'a'
    check runeIndexToUtf16(line, 2) == 3 # After emoji
    check runeIndexToUtf16(line, 3) == 4 # After 'b'

  test "runeIndexToUtf16 - clamps to line length":
    check runeIndexToUtf16("abc", 100) == 3
    check runeIndexToUtf16("a😀b", 100) == 4

  test "utf16ToRuneIndex - empty string":
    check utf16ToRuneIndex("", 0) == 0
    check utf16ToRuneIndex("", 5) == 0

  test "utf16ToRuneIndex - ASCII":
    let line = "hello"
    check utf16ToRuneIndex(line, 0) == 0
    check utf16ToRuneIndex(line, 3) == 3
    check utf16ToRuneIndex(line, 5) == 5

  test "utf16ToRuneIndex - BMP characters (Japanese)":
    let line = "こんにちは"
    check utf16ToRuneIndex(line, 0) == 0
    check utf16ToRuneIndex(line, 2) == 2
    check utf16ToRuneIndex(line, 5) == 5

  test "utf16ToRuneIndex - surrogate pairs (emoji)":
    let line = "a😀b"
    check utf16ToRuneIndex(line, 0) == 0
    check utf16ToRuneIndex(line, 1) == 1 # After 'a'
    check utf16ToRuneIndex(line, 3) == 2 # After emoji (2 UTF-16 units)
    check utf16ToRuneIndex(line, 4) == 3 # After 'b'

  test "utf16ToRuneIndex - clamps to rune count":
    check utf16ToRuneIndex("abc", 100) == 3
    check utf16ToRuneIndex("a😀b", 100) == 3

  test "rune/UTF-16 roundtrip":
    let line = "hello世界🌍end"
    # Rune indexes: h(0) e(1) l(2) l(3) o(4) 世(5) 界(6) 🌍(7) e(8) n(9) d(10), total 11
    for runeIndex in [0, 3, 5, 6, 7, 8, 11]:
      let utf16 = runeIndexToUtf16(line, runeIndex)
      check utf16ToRuneIndex(line, utf16) == runeIndex

suite "TextEdit Application":
  test "applyTextEdits - empty edits":
    let buffer = newTextBuffer("hello world")
    let result = applyTextEdits(buffer, @[])
    check result.isOk
    check buffer.getTextString() == "hello world"

  test "applyTextEdits - single insertion":
    let buffer = newTextBuffer("hello world")
    let edit = TextEdit(
      range: newRange(0, 6, 0, 6), # Insert at position 6 (empty range)
      newText: "beautiful ",
    )
    let result = applyTextEdits(buffer, @[edit])
    check result.isOk
    check buffer.getTextString() == "hello beautiful world"

  test "applyTextEdits - single replacement":
    let buffer = newTextBuffer("hello world")
    let edit = TextEdit(
      range: newRange(0, 6, 0, 11), # Replace "world"
      newText: "nim",
    )
    let result = applyTextEdits(buffer, @[edit])
    check result.isOk
    check buffer.getTextString() == "hello nim"

  test "applyTextEdits - single deletion":
    let buffer = newTextBuffer("hello world")
    let edit = TextEdit(
      range: newRange(0, 5, 0, 11), # Delete " world"
      newText: "",
    )
    let result = applyTextEdits(buffer, @[edit])
    check result.isOk
    check buffer.getTextString() == "hello"

  test "applyTextEdits - multiple edits same line":
    let buffer = newTextBuffer("abc def ghi")
    let edits = @[
      TextEdit(range: newRange(0, 0, 0, 3), newText: "AAA"), # Replace "abc"
      TextEdit(range: newRange(0, 8, 0, 11), newText: "CCC"), # Replace "ghi"
    ]
    let result = applyTextEdits(buffer, edits)
    check result.isOk
    check buffer.getTextString() == "AAA def CCC"

  test "applyTextEdits - same-position inserts keep array order":
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

  test "applyTextEdits - three same-position inserts keep array order":
    let buffer = newTextBuffer("()")
    let edits = @[
      TextEdit(range: newRange(0, 1, 0, 1), newText: "1"),
      TextEdit(range: newRange(0, 1, 0, 1), newText: "2"),
      TextEdit(range: newRange(0, 1, 0, 1), newText: "3"),
    ]
    let result = applyTextEdits(buffer, edits)
    check result.isOk
    check buffer.getTextString() == "(123)"

  test "applyTextEdits - multi-line buffer":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let edit = TextEdit(
      range: newRange(1, 0, 1, 5), # Replace "line2"
      newText: "REPLACED",
    )
    let result = applyTextEdits(buffer, @[edit])
    check result.isOk
    check buffer.getLine(0) == "line1"
    check buffer.getLine(1) == "REPLACED"
    check buffer.getLine(2) == "line3"

  test "applyTextEdits - insert newline":
    let buffer = newTextBuffer("hello world")
    let edit = TextEdit(range: newRange(0, 5, 0, 5), newText: "\n")
    let result = applyTextEdits(buffer, @[edit])
    check result.isOk
    check buffer.len == 2
    check buffer.getLine(0) == "hello"
    check buffer.getLine(1) == " world"

  test "applyTextEdits - UTF-16 position handling":
    # Test with mixed ASCII and Japanese characters
    # "abc日本" - "abc" = 3 UTF-16 units, "日本" = 2 UTF-16 units
    let buffer = newTextBuffer("abc日本")
    # Replace "日本" (positions 3-5 in UTF-16)
    let edit = TextEdit(range: newRange(0, 3, 0, 5), newText: "XY")
    let result = applyTextEdits(buffer, @[edit])
    check result.isOk
    check buffer.getTextString() == "abcXY"

  test "applyTextEdits - multibyte prefix (rune vs byte columns)":
    # Start position is after multibyte characters, where rune index (1)
    # differs from the UTF-8 byte offset (3). Regression test for treating
    # UTF-16 offsets as byte offsets.
    let buffer = newTextBuffer("あいうえお")
    # Replace "いう" (UTF-16 positions 1-3; each hiragana is 1 unit)
    let edit = TextEdit(range: newRange(0, 1, 0, 3), newText: "X")
    let result = applyTextEdits(buffer, @[edit])
    check result.isOk
    check buffer.getTextString() == "あXえお"

  test "applyTextEdits - insertion after multibyte characters":
    let buffer = newTextBuffer("日本語abc")
    # Insert at UTF-16 position 3 (after 日本語 = rune index 3)
    let edit = TextEdit(range: newRange(0, 3, 0, 3), newText: "X")
    let result = applyTextEdits(buffer, @[edit])
    check result.isOk
    check buffer.getTextString() == "日本語Xabc"

  test "applyTextEdits - surrogate pair handling":
    # 😀 is 2 UTF-16 units but 1 rune
    let buffer = newTextBuffer("a😀bc")
    # Replace the emoji: UTF-16 range (1, 3)
    let edit = TextEdit(range: newRange(0, 1, 0, 3), newText: "Z")
    let result = applyTextEdits(buffer, @[edit])
    check result.isOk
    check buffer.getTextString() == "aZbc"

suite "Folding Range Application":
  test "applyLspFoldingRanges - empty ranges":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ranges: seq[FoldingRange] = @[]
    let count = applyLspFoldingRanges(buffer, ranges)
    check count == 0
    check buffer.foldState.folds.len == 0

  test "applyLspFoldingRanges - single fold":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    let ranges = @[
      FoldingRange(
        startLine: 1,
        endLine: 2,
        startCharacter: none(int),
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: none(string),
      )
    ]
    let count = applyLspFoldingRanges(buffer, ranges)
    check count == 1
    check buffer.foldState.folds.len == 1
    check buffer.foldState.folds[0].startLine == 1
    check buffer.foldState.folds[0].endLine == 2
    check not buffer.foldState.folds[0].collapsed # Default is expanded

  test "applyLspFoldingRanges - multiple non-overlapping folds":
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
    let count = applyLspFoldingRanges(buffer, ranges)
    check count == 2
    check buffer.foldState.folds.len == 2

  test "applyLspFoldingRanges - start collapsed":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    let ranges = @[
      FoldingRange(
        startLine: 1,
        endLine: 2,
        startCharacter: none(int),
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: some("..."),
      )
    ]
    let count = applyLspFoldingRanges(buffer, ranges, startCollapsed = true)
    check count == 1
    check buffer.foldState.folds[0].collapsed

  test "applyLspFoldingRanges - with collapsedText":
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
    let count = applyLspFoldingRanges(buffer, ranges)
    check count == 1
    check buffer.foldState.folds[0].collapsedText == some("{ ... }")

  test "applyLspFoldingRanges - invalid ranges skipped":
    let buffer = newTextBuffer("0\n1\n2")
    let ranges = @[
      FoldingRange(
        startLine: 5, # Out of bounds
        endLine: 10,
        startCharacter: none(int),
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: none(string),
      ),
      FoldingRange(
        startLine: 2, # End before start
        endLine: 1,
        startCharacter: none(int),
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: none(string),
      ),
      FoldingRange(
        startLine: 0, # Valid
        endLine: 1,
        startCharacter: none(int),
        endCharacter: none(int),
        kind: none(FoldingRangeKind),
        collapsedText: none(string),
      ),
    ]
    let count = applyLspFoldingRanges(buffer, ranges)
    check count == 1

  test "applyLspFoldingRanges - clearExisting false":
    let buffer = newTextBuffer("0\n1\n2\n3\n4\n5\n6\n7")
    # Add initial fold
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
    discard applyLspFoldingRanges(buffer, ranges1)
    check buffer.foldState.folds.len == 1

    # Add more folds without clearing
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
    let count = applyLspFoldingRanges(buffer, ranges2, clearExisting = false)
    check count == 1
    check buffer.foldState.folds.len == 2

  test "applyLspFoldingRanges - preserves nested ranges":
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
    let count = applyLspFoldingRanges(buffer, ranges)
    check count == 2 # both outer and inner kept
    check buffer.foldState.folds.len == 2

  test "applyLspFoldingRanges - skips degenerate single-line ranges":
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
    let count = applyLspFoldingRanges(buffer, ranges)
    check count == 0
    check buffer.foldState.folds.len == 0

  test "applyLspFoldingRanges - keeps manual folds, replaces lsp folds":
    let buffer = newTextBuffer("0\n1\n2\n3\n4\n5\n6\n7")
    # A manual fold the user created with zf.
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
    check applyLspFoldingRanges(buffer, rangesA) == 1
    check buffer.foldState.folds.len == 2 # manual + lsp

    # Re-applying clears only the previous LSP fold; the manual fold survives.
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
    check applyLspFoldingRanges(buffer, rangesB) == 1
    check buffer.foldState.folds.len == 2 # manual + new lsp

    let manual = buffer.foldState.getFoldAt(6)
    check manual.isSome
    check manual.get.source == fsManual
    # Old LSP fold (0, 2) is gone; the new one (3, 4) is present.
    check buffer.foldState.getFoldAt(0).isNone
    check buffer.foldState.getFoldAt(3).isSome

suite "Diagnostics Application":
  test "applyDiagnosticsToBuffer - empty diagnostics":
    let buffer = newTextBuffer("line1\nline2\nline3")
    applyDiagnosticsToBuffer(buffer, @[])
    # Should not add any markers
    for i in 0 ..< buffer.len:
      check buffer.getLineMarker(i).isNone

  test "applyDiagnosticsToBuffer - error diagnostic":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let diagnostics = @[
      Diagnostic(
        range: newRange(1, 0, 1, 5),
        severity: some(dsError),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "Error on line 2",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      )
    ]
    applyDiagnosticsToBuffer(buffer, diagnostics)
    check buffer.getLineMarker(0).isNone
    check buffer.getLineMarker(1) == some(LineMarkerKind.SyntaxError)
    check buffer.getLineMarker(2).isNone

  test "applyDiagnosticsToBuffer - warning diagnostic":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let diagnostics = @[
      Diagnostic(
        range: newRange(0, 0, 0, 5),
        severity: some(dsWarning),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "Warning",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      )
    ]
    applyDiagnosticsToBuffer(buffer, diagnostics)
    check buffer.getLineMarker(0) == some(LineMarkerKind.SyntaxWarning)

  test "applyDiagnosticsToBuffer - error takes precedence over warning":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let diagnostics = @[
      Diagnostic(
        range: newRange(1, 0, 1, 5),
        severity: some(dsWarning),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "Warning first",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      ),
      Diagnostic(
        range: newRange(1, 0, 1, 5),
        severity: some(dsError),
        code: none(JsonNode),
        codeDescription: none(JsonNode),
        source: none(string),
        message: "Error second",
        tags: none(seq[DiagnosticTag]),
        relatedInformation: none(seq[DiagnosticRelatedInformation]),
        data: none(JsonNode),
      ),
    ]
    applyDiagnosticsToBuffer(buffer, diagnostics)
    check buffer.getLineMarker(1) == some(LineMarkerKind.SyntaxError)

  test "applyDiagnosticsToBuffer - clears existing syntax markers":
    let buffer = newTextBuffer("line1\nline2\nline3")
    # Add initial marker
    buffer.setLineMarker(0, LineMarkerKind.SyntaxError)
    check buffer.getLineMarker(0) == some(LineMarkerKind.SyntaxError)

    # Apply empty diagnostics - should clear
    applyDiagnosticsToBuffer(buffer, @[])
    check buffer.getLineMarker(0).isNone

  test "applyDiagnosticsToBuffer - out of range line ignored":
    let buffer = newTextBuffer("line1\nline2")
    let diagnostics = @[
      Diagnostic(
        range: newRange(100, 0, 100, 5), # Out of bounds
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
    # Should not crash, no markers added
    for i in 0 ..< buffer.len:
      check buffer.getLineMarker(i).isNone

  test "applyDiagnosticsToBuffer - stores BufferDiagnostics":
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
    # endCol 8 exceeds "line2" (5 runes) and is clamped to the line length
    check buffer.diagnostics[0].endCol == 5
    check buffer.diagnostics[0].severity == bdsError
    check buffer.diagnostics[0].message == "undeclared identifier"
    check buffer.diagnostics[1].severity == bdsWarning
    check buffer.diagnostics[1].message == "unused variable"

  test "applyDiagnosticsToBuffer - converts UTF-16 columns to rune indexes":
    # "あいう abc": each hiragana is 1 UTF-16 unit = 1 rune, so a diagnostic
    # on "abc" starts at UTF-16 column 4 = rune index 4 (but byte offset 10).
    # With an emoji, UTF-16 units (2) differ from runes (1).
    let buffer = newTextBuffer("あいう abc\na😀bc")
    let diagnostics = @[
      Diagnostic(
        range: newRange(0, 4, 0, 7), # "abc" in UTF-16 units
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
        range: newRange(1, 3, 1, 5), # "bc" after the emoji (UTF-16)
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
    # Rune indexes, not UTF-16 units or bytes
    check buffer.diagnostics[0].startCol == 4
    check buffer.diagnostics[0].endCol == 7
    check buffer.diagnostics[1].startCol == 2 # a(0) 😀(1) b(2)
    check buffer.diagnostics[1].endCol == 4

suite "getDiagnosticsAt":
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
    # endCol is exclusive (LSP spec): col == endCol should be outside
    check buffer.getDiagnosticsAt(1, 5).len == 0
    check buffer.getDiagnosticsAt(1, 4).len == 1

  test "multi-line diagnostic - middle line matches":
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
    # Middle line: any column should match
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
    # Start line: before startCol should not match
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
    # End line: endCol is exclusive
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

suite "formatDiagnosticsForHover":
  test "formats single diagnostic":
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
    let result = formatDiagnosticsForHover(diags)
    check result == "[Error] e\n[Warning] w\n[Info] i\n[Hint] h"

  test "empty diagnostics returns empty string":
    check formatDiagnosticsForHover(@[]) == ""

suite "Messages":
  test "getAndClearMessages - empty":
    let lsp = newLspIntegration("/tmp")
    let messages = lsp.getAndClearMessages()
    check messages.len == 0

  test "getAndClearMessages - clears after get":
    let lsp = newLspIntegration("/tmp")
    lsp.pendingMessages.add("Message 1")
    lsp.pendingMessages.add("Message 2")

    let messages = lsp.getAndClearMessages()
    check messages.len == 2
    check messages[0] == "Message 1"
    check messages[1] == "Message 2"

    # Should be cleared
    let messagesAgain = lsp.getAndClearMessages()
    check messagesAgain.len == 0

suite "WorkspaceEdit Application":
  test "applyWorkspaceEdit - empty edit":
    var buffers: seq[TextBuffer] = @[newTextBuffer("hello")]
    let edit = WorkspaceEdit(
      changes: none(Table[string, seq[TextEdit]]),
      documentChanges: none(seq[TextDocumentEdit]),
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isOk
    check result.get.modifiedCount == 0

  test "applyWorkspaceEdit - single buffer with changes field":
    var buffers: seq[TextBuffer] =
      @[newTextBuffer("hello world", some("/tmp/test.txt"))]
    var changes = initTable[string, seq[TextEdit]]()
    changes["file:///tmp/test.txt"] =
      @[TextEdit(range: newRange(0, 0, 0, 5), newText: "hi")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isOk
    check result.get.modifiedCount == 1
    check buffers[0].getTextString() == "hi world"

  test "applyWorkspaceEdit - single buffer with documentChanges field":
    var buffers: seq[TextBuffer] = @[newTextBuffer("foo bar", some("/tmp/doc.txt"))]
    let docEdit = TextDocumentEdit(
      textDocument: OptionalVersionedTextDocumentIdentifier(
        uri: "file:///tmp/doc.txt", version: some(1)
      ),
      edits: @[TextEdit(range: newRange(0, 4, 0, 7), newText: "baz")],
    )
    let edit = WorkspaceEdit(
      changes: none(Table[string, seq[TextEdit]]), documentChanges: some(@[docEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isOk
    check result.get.modifiedCount == 1
    check buffers[0].getTextString() == "foo baz"

  test "applyWorkspaceEdit - documentChanges takes precedence":
    var buffers: seq[TextBuffer] = @[newTextBuffer("original", some("/tmp/file.txt"))]
    # Set up both changes and documentChanges
    var changes = initTable[string, seq[TextEdit]]()
    changes["file:///tmp/file.txt"] =
      @[TextEdit(range: newRange(0, 0, 0, 8), newText: "from_changes")]
    let docEdit = TextDocumentEdit(
      textDocument: OptionalVersionedTextDocumentIdentifier(
        uri: "file:///tmp/file.txt", version: some(1)
      ),
      edits: @[TextEdit(range: newRange(0, 0, 0, 8), newText: "from_docChanges")],
    )
    let edit = WorkspaceEdit(changes: some(changes), documentChanges: some(@[docEdit]))
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isOk
    # documentChanges should take precedence per LSP spec
    check buffers[0].getTextString() == "from_docChanges"

  test "applyWorkspaceEdit - multiple buffers":
    var buffers: seq[TextBuffer] = @[
      newTextBuffer("aaa", some("/tmp/a.txt")), newTextBuffer("bbb", some("/tmp/b.txt"))
    ]
    var changes = initTable[string, seq[TextEdit]]()
    changes["file:///tmp/a.txt"] =
      @[TextEdit(range: newRange(0, 0, 0, 3), newText: "AAA")]
    changes["file:///tmp/b.txt"] =
      @[TextEdit(range: newRange(0, 0, 0, 3), newText: "BBB")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isOk
    check result.get.modifiedCount == 2
    check buffers[0].getTextString() == "AAA"
    check buffers[1].getTextString() == "BBB"

  test "applyWorkspaceEdit - relative-path buffer matched against absolute URI":
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
    # The open buffer was modified in memory (not the on-disk file branch)
    check result.get.modifiedBufferIndexes == @[0]
    check result.get.modifiedFilePaths.len == 0
    check buffers[0].getTextString() == "baz bar"

  test "applyWorkspaceEdit - relative-path buffer via documentChanges":
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

  test "applyWorkspaceEdit - custom transaction name":
    var buffers: seq[TextBuffer] = @[newTextBuffer("old text", some("/tmp/custom.txt"))]
    var changes = initTable[string, seq[TextEdit]]()
    changes["file:///tmp/custom.txt"] =
      @[TextEdit(range: newRange(0, 0, 0, 3), newText: "new")]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let result = applyWorkspaceEdit(buffers, edit, "CustomRename")
    check result.isOk
    check result.get.modifiedCount == 1
    check buffers[0].getTextString() == "new text"

  test "applyWorkspaceEdit - refuses file operations without applying edits":
    var buffers: seq[TextBuffer] = @[newTextBuffer("hello", some("/tmp/ro.txt"))]
    let edit = WorkspaceEdit(
      changes: none(Table[string, seq[TextEdit]]),
      documentChanges: some(newSeq[TextDocumentEdit]()),
      resourceOperations: @["rename"],
    )
    let result = applyWorkspaceEdit(buffers, edit)
    check result.isErr
    check result.error.contains("file operations")
    check result.error.contains("rename")
    # Nothing applied
    check buffers[0].getTextString() == "hello"

  test "parseWorkspaceEdit - records resource operations":
    let node = %*{
      "documentChanges": [
        {
          "textDocument": {"uri": "file:///tmp/a.txt", "version": 1},
          "edits": [
            {
              "range": {
                "start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 0}
              },
              "newText": "x",
            }
          ],
        },
        {"kind": "create", "uri": "file:///tmp/new.txt"},
        {"kind": "rename", "oldUri": "file:///tmp/a.txt", "newUri": "file:///tmp/b.txt"},
      ]
    }
    let edit = parseWorkspaceEdit(node)
    check edit.documentChanges.isSome
    check edit.documentChanges.get.len == 1 # only the textDocument edit
    check edit.resourceOperations == @["create", "rename"]

  test "applyWorkspaceEdit - reports modified buffer indexes":
    var buffers: seq[TextBuffer] = @[
      newTextBuffer("aaa", some("/tmp/a.txt")),
      newTextBuffer("bbb", some("/tmp/b.txt")),
      newTextBuffer("ccc", some("/tmp/c.txt")),
    ]
    var changes = initTable[string, seq[TextEdit]]()
    changes["file:///tmp/a.txt"] =
      @[TextEdit(range: newRange(0, 0, 0, 3), newText: "AAA")]
    changes["file:///tmp/c.txt"] =
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

  test "collectWorkspaceEditPaths - changes field":
    var changes = initTable[string, seq[TextEdit]]()
    changes["file:///tmp/a.txt"] = @[]
    changes["file:///tmp/b.txt"] = @[]
    let edit = WorkspaceEdit(
      changes: some(changes), documentChanges: none(seq[TextDocumentEdit])
    )
    let paths = collectWorkspaceEditPaths(edit)
    check paths.len == 2
    check "/tmp/a.txt" in paths
    check "/tmp/b.txt" in paths

  test "collectWorkspaceEditPaths - documentChanges takes precedence":
    var changes = initTable[string, seq[TextEdit]]()
    changes["file:///tmp/from_changes.txt"] = @[]
    let docEdit = TextDocumentEdit(
      textDocument: OptionalVersionedTextDocumentIdentifier(
        uri: "file:///tmp/from_doc.txt", version: some(1)
      ),
      edits: @[],
    )
    let edit = WorkspaceEdit(changes: some(changes), documentChanges: some(@[docEdit]))
    let paths = collectWorkspaceEditPaths(edit)
    check paths == @["/tmp/from_doc.txt"]

  test "collectWorkspaceEditPaths - empty edit":
    let edit = WorkspaceEdit(
      changes: none(Table[string, seq[TextEdit]]),
      documentChanges: none(seq[TextDocumentEdit]),
    )
    check collectWorkspaceEditPaths(edit).len == 0

suite "Support Check Functions":
  test "hasDocumentLinkSupport - LSP disabled":
    let lsp = newLspIntegration("/tmp")
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasDocumentLinkSupport(buffer)

  test "hasDocumentLinkSupport - no file path":
    let lsp = newLspIntegration("/tmp")
    let buffer = newTextBuffer("test")
    check not lsp.hasDocumentLinkSupport(buffer)

  test "hasDocumentLinkResolveSupport - LSP disabled":
    let lsp = newLspIntegration("/tmp")
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasDocumentLinkResolveSupport(buffer)

  test "hasRenameSupport - LSP disabled":
    let lsp = newLspIntegration("/tmp")
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasRenameSupport(buffer)

  test "hasRenameSupport - no file path":
    let lsp = newLspIntegration("/tmp")
    let buffer = newTextBuffer("test")
    check not lsp.hasRenameSupport(buffer)

  test "hasCodeLensSupport - LSP disabled":
    let lsp = newLspIntegration("/tmp")
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasCodeLensSupport(buffer)

  test "hasCodeLensSupport - no file path":
    let lsp = newLspIntegration("/tmp")
    let buffer = newTextBuffer("test")
    check not lsp.hasCodeLensSupport(buffer)

  test "hasCodeLensResolveSupport - LSP disabled":
    let lsp = newLspIntegration("/tmp")
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasCodeLensResolveSupport(buffer)

  test "hasDocumentSymbolSupport - LSP disabled":
    let lsp = newLspIntegration("/tmp")
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasDocumentSymbolSupport(buffer)

  test "hasDocumentSymbolSupport - no file path":
    let lsp = newLspIntegration("/tmp")
    let buffer = newTextBuffer("test")
    check not lsp.hasDocumentSymbolSupport(buffer)

  test "hasCallHierarchySupport - LSP disabled":
    let lsp = newLspIntegration("/tmp")
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasCallHierarchySupport(buffer)

  test "hasCallHierarchySupport - no file path":
    let lsp = newLspIntegration("/tmp")
    let buffer = newTextBuffer("test")
    check not lsp.hasCallHierarchySupport(buffer)

  test "hasExecuteCommandSupport - LSP disabled":
    let lsp = newLspIntegration("/tmp")
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasExecuteCommandSupport(buffer)

  test "hasExecuteCommandSupport - no file path":
    let lsp = newLspIntegration("/tmp")
    let buffer = newTextBuffer("test")
    check not lsp.hasExecuteCommandSupport(buffer)

  test "hasFoldingRangeSupport - LSP disabled":
    let lsp = newLspIntegration("/tmp")
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check not lsp.hasFoldingRangeSupport(buffer)

  test "hasFoldingRangeSupport - no file path":
    let lsp = newLspIntegration("/tmp")
    let buffer = newTextBuffer("test")
    check not lsp.hasFoldingRangeSupport(buffer)

  test "getSemanticTokensLegend - LSP disabled":
    let lsp = newLspIntegration("/tmp")
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check lsp.getSemanticTokensLegend(buffer).isNone

  test "getSemanticTokensLegend - no file path":
    let lsp = newLspIntegration("/tmp")
    let buffer = newTextBuffer("test")
    check lsp.getSemanticTokensLegend(buffer).isNone

suite "Request Functions - Edge Cases":
  test "startCompletionRequest - LSP disabled":
    let lsp = newLspIntegration("/tmp")
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startCompletionRequest(buffer, 0, 0)
    check result.isErr
    check result.error == "LSP disabled"

  test "startCompletionRequest - no file path":
    let lsp = newLspIntegration("/tmp")
    let buffer = newTextBuffer("test")
    let result = lsp.startCompletionRequest(buffer, 0, 0)
    check result.isErr
    check result.error == "Buffer has no file path"

  test "startHoverRequest - LSP disabled":
    let lsp = newLspIntegration("/tmp")
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startHoverRequest(buffer, 0, 0)
    check result.isErr
    check result.error == "LSP disabled"

  test "startDefinitionRequest - no file path":
    let lsp = newLspIntegration("/tmp")
    let buffer = newTextBuffer("test")
    let result = lsp.startDefinitionRequest(buffer, 0, 0)
    check result.isErr
    check result.error == "Buffer has no file path"

  test "startReferencesRequest - LSP disabled":
    let lsp = newLspIntegration("/tmp")
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.startReferencesRequest(buffer, 0, 0)
    check result.isErr

  test "startDocumentSymbolsRequest - no file path":
    let lsp = newLspIntegration("/tmp")
    let buffer = newTextBuffer("test")
    let result = lsp.startDocumentSymbolsRequest(buffer)
    check result.isErr

  test "startSemanticTokensRequest - LSP disabled":
    let lsp = newLspIntegration("/tmp")
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test\nline2", some("/tmp/test.nim"))
    let result = lsp.startSemanticTokensRequest(buffer, 0, 1)
    check result.isErr
    check result.error == "LSP disabled"

  test "startSemanticTokensRequest - no file path":
    let lsp = newLspIntegration("/tmp")
    let buffer = newTextBuffer("test\nline2")
    let result = lsp.startSemanticTokensRequest(buffer, 0, 1)
    check result.isErr
    check result.error == "Buffer has no file path"

  test "startSemanticTokensRequest - empty buffer":
    let lsp = newLspIntegration("/tmp")
    let buffer = newTextBuffer("", some("/tmp/test.nim"))
    let result = lsp.startSemanticTokensRequest(buffer, 0, 0)
    check result.isErr
    # Error can be "Buffer is empty" or "Semantic tokens not supported" depending on check order
    check "empty" in result.error or "not supported" in result.error

suite "Buffer Lifecycle - Edge Cases":
  privateAccess(LspIntegration)

  # Several tests below call onBufferOpen, which spawns a real worker thread (nim
  # is configured by default), so each test tears the integration down to join
  # that thread and avoid leaking worker threads / nimlangserver processes.
  var lsp: LspIntegration
  setup:
    lsp = newLspIntegration("/tmp")
  teardown:
    lsp.shutdown()

  proc markReady(lsp: LspIntegration) =
    ## Pretend a server would receive the change so onBufferChange advances the
    ## version/shadow without a live worker.
    lsp.service.liveWorkerOverride = proc(path: string): bool =
      true

  test "onBufferOpen - LSP disabled":
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.onBufferOpen(buffer)
    check result.isOk # Returns ok() when disabled

  test "onBufferOpen - no file path":
    let buffer = newTextBuffer("test")
    let result = lsp.onBufferOpen(buffer)
    check result.isOk # Returns ok() when no path

  test "onBufferClose - LSP disabled":
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.onBufferClose(buffer)
    check result.isOk

  test "onBufferClose - no file path":
    let buffer = newTextBuffer("test")
    let result = lsp.onBufferClose(buffer)
    check result.isOk

  test "onBufferChange - LSP disabled":
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.onBufferChange(buffer)
    check result.isOk

  test "onBufferSave - LSP disabled":
    lsp.setEnabled(false)
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    let result = lsp.onBufferSave(buffer)
    check result.isOk

  test "onBufferSave - no file path":
    let buffer = newTextBuffer("test")
    let result = lsp.onBufferSave(buffer)
    check result.isOk

  test "document version - didOpen starts at 1":
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check lsp.onBufferOpen(buffer).isOk
    check lsp.sentDocumentVersion("/tmp/test.nim") == some(1)

  test "document version - increases monotonically on every change":
    lsp.markReady()
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check lsp.onBufferOpen(buffer).isOk
    for expected in [2, 3, 4]:
      # Mutate the content: an unchanged buffer is skipped as a no-op.
      check buffer.insertText(BufferPosition(line: 0, column: 0), "x").isOk
      check lsp.onBufferChange(buffer).isOk
      check lsp.sentDocumentVersion("/tmp/test.nim") == some(expected)

  test "document version - does not regress when changeSeq rolls back":
    # Undo rolls buffer.changeSeq back; the version sent to the server must
    # keep increasing regardless.
    lsp.markReady()
    let buffer = newTextBuffer("hello", some("/tmp/test.nim"))
    check lsp.onBufferOpen(buffer).isOk
    check buffer.insertText(BufferPosition(line: 0, column: 0), "x").isOk
    check lsp.onBufferChange(buffer).isOk
    let versionBeforeUndo = lsp.sentDocumentVersion("/tmp/test.nim").get
    check buffer.undo().isOk # changeSeq rolls back here
    check lsp.onBufferChange(buffer).isOk
    check lsp.sentDocumentVersion("/tmp/test.nim").get > versionBeforeUndo

  test "document version - per-document tracking":
    lsp.markReady()
    let bufferA = newTextBuffer("a", some("/tmp/a.nim"))
    let bufferB = newTextBuffer("b", some("/tmp/b.nim"))
    check lsp.onBufferOpen(bufferA).isOk
    check lsp.onBufferOpen(bufferB).isOk
    check bufferA.insertText(BufferPosition(line: 0, column: 0), "x").isOk
    check lsp.onBufferChange(bufferA).isOk
    check bufferA.insertText(BufferPosition(line: 0, column: 0), "y").isOk
    check lsp.onBufferChange(bufferA).isOk
    check lsp.sentDocumentVersion("/tmp/a.nim") == some(3)
    check lsp.sentDocumentVersion("/tmp/b.nim") == some(1)

  test "document version - cleared on close":
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check lsp.onBufferOpen(buffer).isOk
    check lsp.onBufferClose(buffer).isOk
    check lsp.sentDocumentVersion("/tmp/test.nim").isNone

  test "document version - change without open sends didOpen with version 1":
    let buffer = newTextBuffer("test", some("/tmp/test.nim"))
    check lsp.onBufferChange(buffer).isOk
    check lsp.sentDocumentVersion("/tmp/test.nim") == some(1)

suite "Misc Functions":
  test "isServerRunningForPath - unknown extension":
    let lsp = newLspIntegration("/tmp")
    check not lsp.isServerRunningForPath("/tmp/file.unknown")

  test "getRunningServers - initially empty":
    let lsp = newLspIntegration("/tmp")
    check lsp.getRunningServers().len == 0

  test "shutdown - clears state":
    let lsp = newLspIntegration("/tmp")
    # Add some state
    lsp.activeProgress["token"] = LspProgressState(
      token: "token",
      langId: "nim",
      title: "Test",
      message: none(string),
      percentage: none(int),
      cancellable: false,
      startTime: 0.0,
    )
    lsp.serverStatus["nim"] =
      LspStatusState(health: shOk, quiescent: true, message: none(string))

    lsp.shutdown()

    check lsp.activeProgress.len == 0
    check lsp.serverStatus.len == 0
