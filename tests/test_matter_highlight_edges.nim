import std/unittest

import ../src/moepkg/[buffer, config, highlight, highlight_config]
import ../src/moepkg/syntax/tokenizer
import pkg/celina

when defined(moe.matter):
  import std/[sequtils, strutils, tables]
  import ../src/moepkg/unicode_utils

  suite "Matter highlight edge cases":
    test "capped Unicode tails remain plain and reserved words use editor columns":
      let lines = @["# λTODO界abcdef", "let x = 1"]
      let (segments, states) = initHighlightIncremental(
        lines,
        0,
        lines.high,
        newTokenizerState(hbMatter, langNim),
        @[ReservedWord(word: "TODO", color: reservedWord)],
        langNim,
        8,
      )
      let h = Highlight(colorSegments: segments)
      check states.len == lines.len
      check h.getColorPair(0, 2) == comment
      check h.getColorPair(0, 3) == reservedWord
      check h.getColorPair(0, 6) == reservedWord
      check h.getColorPair(0, 7) == comment
      check h.getColorPair(0, 8) == EditorColorPairIndex.default
      for i in 1 ..< segments.len:
        check (segments[i - 1].firstRow, segments[i - 1].firstColumn) <=
          (segments[i].firstRow, segments[i].firstColumn)

    test "bare CR and malformed bytes do not shift rows or columns":
      let lines = @["# \xffλTODO\rtext", "", "let x = 1"]
      let (segments, states) = initHighlightIncremental(
        lines,
        0,
        lines.high,
        newTokenizerState(hbMatter, langNim),
        @[ReservedWord(word: "TODO", color: reservedWord)],
        langNim,
      )
      check states.len == 3
      let h = Highlight(colorSegments: segments)
      check h.getColorPair(0, 4) == reservedWord
      check h.getColorPair(0, 7) == reservedWord
      for segment in segments:
        check segment.firstRow in 0 .. 2
        check segment.lastColumn < lines[segment.firstRow].charLen

    test "empty reserved words do not stall comment parsing":
      let (_, states) = initHighlightIncremental(
        @["# TODO"],
        0,
        0,
        newTokenizerState(hbMatter, langNim),
        @[ReservedWord(word: "", color: reservedWord)],
        langNim,
      )
      check states.len == 1

    test "failed line states remain plain and keep capped tails":
      var seed = newTokenizerState(hbMatter, langNim)
      seed.matterState.failed = true
      let (segments, states) = initHighlightIncremental(
        @["let x = 1", "# comment"], 0, 1, seed, @[], langNim, 3
      )
      check states.len == 2
      check states.allIt(it.matterState.failed)
      check segments.allIt(it.color == EditorColorPairIndex.default)
      check segments.len == 4

    test "backend reload preserves semantic diagnostic and URI overlays":
      let text = "let x = 1 # https://example.com\nlet y = 2"
      let buffer = newTextBuffer(text)
      buffer.language = langNim
      buffer.setHighlightBackend(hbMatter)
      buffer.diagnostics = @[
        BufferDiagnostic(
          startLine: 1,
          startCol: 0,
          endLine: 1,
          endCol: 3,
          severity: bdsError,
          message: "diagnostic",
        )
      ]
      buffer.diagnosticsDirty = true
      discard buffer.updateHighlight()
      let original = buffer.highlight
      original.semantic[0] = SemanticOverlayLine(
        tokens: @[SemanticOverlayToken(firstColumn: 4, length: 1, color: functionName)]
      )
      original.semanticContentVersion = buffer.contentVersion
      let uriColumn = text.find("https")
      for backend in [hbBuiltin, hbMatter]:
        var config = newEditorConfig()
        config.highlight.backend = backend
        buffer.applyHighlightConfig(config)
        discard buffer.updateHighlight()
        check buffer.highlight == original
        check buffer.highlight.semanticContentVersion == buffer.contentVersion
        check buffer.highlight.getColorPair(0, 4) == functionName
        check buffer.highlight.getColorPair(1, 0) == syntaxCheckErr
        check Underline in buffer.highlight.getSegmentModifiers(0, uriColumn)
        check Undercurl in buffer.highlight.getSegmentModifiers(1, 0)
else:
  suite "Matter-disabled configuration":
    test "portable Matter config safely selects builtin":
      let buffer = newTextBuffer("let x = 1")
      buffer.language = langNim
      var config = newEditorConfig()
      config.highlight.backend = hbMatter
      buffer.applyHighlightConfig(config)
      discard buffer.updateHighlight()
      check buffer.highlightBackend == hbBuiltin
      check buffer.incrementalHighlight.backend == hbBuiltin
