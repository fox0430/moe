import std/[sequtils, unittest]

import pkg/results

import ../src/moepkg/[config, highlight, highlight_config, syntax/tokenizer]
import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types/highlight_types

when defined(moe.matter):
  import pkg/celina

  suite "Matter incremental highlight":
    test "Matter seed produces one state per line":
      let lines = @["proc hello() =", "  discard", "# note"]
      let (segments, states) = initHighlightIncremental(
        lines,
        0,
        lines.high,
        newTokenizerState(hbMatter, SourceLanguage.langNim),
        @[],
        SourceLanguage.langNim,
      )
      check states.len == lines.len
      check states.allIt(it.backend == hbMatter)
      check segments.len > 0

    test "trailing empty line keeps a state":
      let (segments, states) = initHighlightIncrementalFromStr(
        "# one\n",
        0,
        1,
        newTokenizerState(hbMatter, SourceLanguage.langNim),
        @[],
        SourceLanguage.langNim,
      )
      discard segments
      check states.len == 2

    test "Diff and Log fall back to builtin":
      check newTokenizerState(hbMatter, SourceLanguage.langDiff).backend == hbBuiltin
      check newTokenizerState(hbMatter, SourceLanguage.langLog).backend == hbBuiltin

    test "Markdown fences use Matter state":
      var buffer = newTextBuffer("```nim\nproc x() = discard\n```\n")
      buffer.language = SourceLanguage.langMarkdown
      buffer.highlightBackend = hbMatter
      buffer.highlightNeedsUpdate = true
      discard buffer.updateHighlight()
      check buffer.isCodeBlockLine(0)
      check buffer.isCodeBlockLine(1)
      check buffer.isCodeBlockLine(2)

    test "switching backends invalidates incremental state":
      var buffer = newTextBuffer("proc x() = discard")
      buffer.language = SourceLanguage.langNim
      buffer.setHighlightBackend(hbMatter)
      buffer.highlightNeedsUpdate = true
      discard buffer.updateHighlight()
      check buffer.incrementalHighlight.backend == hbMatter
      buffer.setHighlightBackend(hbBuiltin)
      check buffer.incrementalHighlight.isNil
      check buffer.uriScanParsedUpTo == -1

    test "budgeted multiline edit converges to a fresh Matter parse":
      var lines = @["#["]
      for i in 0 ..< 350:
        lines.add("comment line " & $i)
      lines.add("]#")
      lines.add("proc tail() = discard")
      let seed = newTokenizerState(hbMatter, SourceLanguage.langNim)
      let (oldSegments, oldStates) = initHighlightIncremental(
        lines, 0, lines.high, seed, @[], SourceLanguage.langNim
      )
      var incremental = IncrementalHighlight(
        backend: hbMatter,
        segments: oldSegments,
        lineStates: LineStateCache(states: oldStates),
        parsedUpTo: lines.high,
      )
      lines[0] = "# ordinary comment"
      var parsed: int
      var ongoing = updateHighlightIncremental(
        lines.len,
        proc(i: int): string =
          lines[i],
        incremental,
        0,
        @[],
        SourceLanguage.langNim,
        0,
        25,
        1,
        parsed,
      )
      check ongoing
      check parsed <= 100
      while ongoing:
        ongoing = updateHighlightIncremental(
          lines.len,
          proc(i: int): string =
            lines[i],
          incremental,
          0,
          @[],
          SourceLanguage.langNim,
          0,
          25,
          1,
          parsed,
        )
      let (freshSegments, freshStates) = initHighlightIncremental(
        lines,
        0,
        lines.high,
        newTokenizerState(hbMatter, SourceLanguage.langNim),
        @[],
        SourceLanguage.langNim,
      )
      check incremental.segments == freshSegments
      check incremental.lineStates.states == freshStates

    test "progressive Matter load survives an edit before completion":
      var content = ""
      for i in 0 ..< 1600:
        content.add("let value" & $i & " = " & $i & "\n")
      var buffer = newTextBuffer()
      var config = newEditorConfig()
      config.highlight.backend = hbMatter
      buffer.applyHighlightCap(config)
      check buffer.loadFileWithContent("matter-progressive.nim", content).isOk
      check buffer.incrementalHighlight.backend == hbMatter
      check buffer.incrementalHighlight.parsedUpTo == 999
      let initialCache = buffer.incrementalHighlight
      buffer.applyHighlightConfig(config)
      check buffer.incrementalHighlight == initialCache
      check buffer.incrementalHighlight.parsedUpTo == 999
      discard buffer.beginTransaction()
      discard buffer.insert(500, "let edited = 42")
      discard buffer.commitTransaction()
      var parsed: int
      discard buffer.updateHighlight(100, parsed)
      while buffer.continueIncrementalHighlight(100, parsed):
        discard
      while buffer.continueInitialHighlight(100, parsed):
        discard
      check buffer.incrementalHighlight.parsedUpTo == buffer.len - 1
      var lines = newSeq[string](buffer.len)
      for i in 0 ..< buffer.len:
        lines[i] = buffer.getLine(i)
      let (freshSegments, freshStates) = initHighlightIncremental(
        lines,
        0,
        lines.high,
        newTokenizerState(hbMatter, SourceLanguage.langNim),
        @[],
        SourceLanguage.langNim,
      )
      check buffer.incrementalHighlight.segments == freshSegments
      check buffer.incrementalHighlight.lineStates.states == freshStates
else:
  static:
    doAssert true
