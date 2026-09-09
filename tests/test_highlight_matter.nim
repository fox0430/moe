import std/[sequtils, unittest]

import pkg/results

import ../src/moepkg/[config, highlight, highlight_config, syntax/tokenizer]
import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types/highlight_types

when defined(moe.matter) or defined(features.moe.matter):
  import pkg/celina
  import matter_test_grammars

  suite "Matter incremental highlight":
    test "Matter seed produces one state per line":
      let grammars = newTestMatterGrammarSet()
      let lines = @["proc hello() =", "  discard", "# note"]
      let (segments, states) = initHighlightIncremental(
        lines,
        0,
        lines.high,
        newTokenizerState(hbMatter, SourceLanguage.langNim, grammars),
        @[],
        SourceLanguage.langNim,
      )
      check states.len == lines.len
      check states.allIt(it.backend == hbMatter)
      check segments.len > 0

    test "trailing empty line keeps a state":
      let grammars = newTestMatterGrammarSet()
      let (segments, states) = initHighlightIncrementalFromStr(
        "# one\n",
        0,
        1,
        newTokenizerState(hbMatter, SourceLanguage.langNim, grammars),
        @[],
        SourceLanguage.langNim,
      )
      discard segments
      check states.len == 2

    test "Diff and Log fall back to builtin":
      let grammars = newTestMatterGrammarSet()
      check newTokenizerState(hbMatter, langDiff, grammars).backend == hbBuiltin
      check newTokenizerState(hbMatter, langLog, grammars).backend == hbBuiltin

    test "Markdown fences use Matter state":
      var buffer = newTextBuffer("```nim\nproc x() = discard\n```\n")
      buffer.language = SourceLanguage.langMarkdown
      buffer.setMatterGrammar(
        langMarkdown, MarkdownMatterGrammar, "markdown.tmLanguage.json"
      )
      buffer.highlightNeedsUpdate = true
      discard buffer.updateHighlight()
      check buffer.isCodeBlockLine(0)
      check buffer.isCodeBlockLine(1)
      check buffer.isCodeBlockLine(2)

    test "switching backends invalidates incremental state":
      var buffer = newTextBuffer("proc x() = discard")
      buffer.language = SourceLanguage.langNim
      buffer.setMatterGrammar(langNim, NimMatterGrammar, "nim.tmLanguage.json")
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
      let seed = newTokenizerState(hbMatter, langNim, newTestMatterGrammarSet())
      let (oldSegments, oldStates) = initHighlightIncremental(
        lines, 0, lines.high, seed, @[], SourceLanguage.langNim
      )
      var incremental = IncrementalHighlight(
        backend: hbMatter,
        initialState: seed,
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
        lines, 0, lines.high, seed, @[], SourceLanguage.langNim
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
      config.highlight.matterGrammarSet = newTestMatterGrammarSet()
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
        newTokenizerState(hbMatter, langNim, config.highlight.matterGrammarSet),
        @[],
        SourceLanguage.langNim,
      )
      check buffer.incrementalHighlight.segments == freshSegments
      check buffer.incrementalHighlight.lineStates.states == freshStates

    test "default config preserves a progressive builtin load cache":
      var content = ""
      for i in 0 ..< 1600:
        content.add("let value" & $i & " = " & $i & "\n")
      let buffer = newTextBuffer()
      check buffer.loadFileWithContent("builtin-progressive.nim", content).isOk
      check buffer.incrementalHighlight.parsedUpTo == 999
      let initialCache = buffer.incrementalHighlight
      buffer.applyHighlightConfig(newEditorConfig())
      check buffer.incrementalHighlight == initialCache
      check buffer.incrementalHighlight.parsedUpTo == 999

    test "Matter reparse rejects a default state from a cache gap":
      var lines = newSeq[string](220)
      for i in 0 ..< lines.len:
        lines[i] = "let value" & $i & " = " & $i
      let seed = newTokenizerState(hbMatter, langNim, newTestMatterGrammarSet())
      let (segments, states) = initHighlightIncremental(
        lines, 0, lines.high, seed, @[], SourceLanguage.langNim
      )
      var incremental = IncrementalHighlight(
        backend: hbMatter,
        initialState: seed,
        segments: segments,
        lineStates: LineStateCache(states: states),
        parsedUpTo: lines.high,
      )
      incremental.lineStates.states[147] = TokenizerState()
      lines[150] = "# edited"
      var parsed: int
      while updateHighlightIncremental(
        lines.len,
        proc(i: int): string =
          lines[i],
        incremental,
        150,
        @[],
        SourceLanguage.langNim,
        0,
        25,
        1,
        parsed,
      )
      :
        discard
      check incremental.lineStates.states[148 .. ^1].allIt(it.backend == hbMatter)

    test "a fresh Matter reparse retries a cached failed state":
      var lines = newSeq[string](20)
      for i in 0 ..< lines.len:
        lines[i] = "let value" & $i & " = " & $i
      let seed = newTokenizerState(hbMatter, langNim, newTestMatterGrammarSet())
      let (segments, states) = initHighlightIncremental(
        lines, 0, lines.high, seed, @[], SourceLanguage.langNim
      )
      var incremental = IncrementalHighlight(
        backend: hbMatter,
        initialState: seed,
        segments: segments,
        lineStates: LineStateCache(states: states),
        parsedUpTo: lines.high,
      )
      for i in 2 ..< incremental.lineStates.states.len:
        incremental.lineStates.states[i].matterState.failed = true
      lines[5] = "# edited"
      var parsed: int
      while updateHighlightIncremental(
        lines.len,
        proc(i: int): string =
          lines[i],
        incremental,
        5,
        @[],
        SourceLanguage.langNim,
        0,
        5,
        1,
        parsed,
      )
      :
        discard
      check incremental.lineStates.states[3 .. ^1].allIt(not it.matterState.failed)
else:
  static:
    doAssert true
