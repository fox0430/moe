import std/[sequtils, unittest]

when defined(moe.matter):
  import ../src/moepkg/syntax/[matter_backend, tokenizer]
  import matter_test_grammars

  suite "Matter syntax backend":
    test "no grammar is available until the caller supplies one":
      check not matterSupports(SourceLanguage.langNim)
      let missing = tokenizeMatterLine("proc hello() = discard", langNim)
      check missing.nextState.failed

    test "caller-provided Nim grammar highlights without filesystem access":
      let grammars = newTestMatterGrammarSet()
      let first = tokenizeMatterLine(
        "proc hello() = discard", SourceLanguage.langNim, grammars = grammars
      )
      let second =
        tokenizeMatterLine("# comment", SourceLanguage.langNim, first.nextState)
      check not first.nextState.failed
      check not second.nextState.failed
      check first.spans.len > 0

    test "unsupported grammars fail safely":
      let result = tokenizeMatterLine("text", SourceLanguage.langNone)
      check result.nextState.failed
      check result.spans.len == 0

    test "failed state is sticky":
      let failed = tokenizeMatterLine("text", SourceLanguage.langNone).nextState
      let retry = tokenizeMatterLine("proc x = discard", SourceLanguage.langNim, failed)
      check retry.nextState == failed

    test "invalid UTF-8 bytes do not reach Matter regexes":
      let grammars = newTestMatterGrammarSet()
      let line = "# " & char(0xff) & char(0xc0) & " lambda"
      let result = tokenizeMatterLine(line, langNim, grammars = grammars)
      check not result.nextState.failed

    test "a grammar set opts in only its supplied languages":
      let grammars = newTestMatterGrammarSet()
      check grammars.matterSupports(langNim)
      check grammars.matterSupports(langJsonc)
      check grammars.matterSupports(langMarkdown)
      check not grammars.matterSupports(langRust)
      check not grammars.matterSupports(langDiff)
      check not grammars.matterSupports(langLog)

    test "multiline resume uses completed structurally equal states":
      let lines = ["#[ outer", "  #[ nested ]#", "still comment", "]#", "let x = true"]
      let grammars = newTestMatterGrammarSet()
      var first, repeated: MatterLineState
      for i, line in lines:
        let a =
          tokenizeMatterLine(line, langNim, first, timeLimitMs = 0, grammars = grammars)
        let b = tokenizeMatterLine(
          line, langNim, repeated, timeLimitMs = 0, grammars = grammars
        )
        check not a.nextState.failed
        check a == b
        if i in 1 .. 2:
          check a.spans.anyIt(it.category == mccComment)
        first = a.nextState
        repeated = b.nextState
      check tokenizeMatterLine("true", langNim, first, timeLimitMs = 0).spans.anyIt(
        it.category == mccBoolean
      )

    test "JSONC selects the comment-enabled grammar":
      let parsed = tokenizeMatterLine(
        "// comment", langJsonc, timeLimitMs = 0, grammars = newTestMatterGrammarSet()
      )
      check not parsed.nextState.failed
      check parsed.spans.anyIt(it.category == mccComment)

    test "Markdown code block state covers opening and content but ends at fence":
      let grammars = newTestMatterGrammarSet()
      let opening =
        tokenizeMatterLine("~~~nim", langMarkdown, timeLimitMs = 0, grammars = grammars)
      check isMatterCodeBlock(opening.nextState)
      let content = tokenizeMatterLine("let x = 1", langMarkdown, opening.nextState, 0)
      check isMatterCodeBlock(content.nextState)
      let closing = tokenizeMatterLine("~~~", langMarkdown, content.nextState, 0)
      check not isMatterCodeBlock(closing.nextState)

    test "malformed Unicode preserves input bytes and span bounds":
      var samples = @["\xed\xa0\x80", "\xf4\x90\x80\x80", "\xc0\xaf", "\xe2\x82"]
      for value in 128 .. 255:
        samples.add($char(value))
      for sample in samples:
        let grammars = newTestMatterGrammarSet()
        let line = "# " & sample & " λ"
        let original = line
        let parsed =
          tokenizeMatterLine(line, langNim, timeLimitMs = 0, grammars = grammars)
        check not parsed.nextState.failed
        check line == original
        for span in parsed.spans:
          check span.firstByte >= 0
          check span.lastByte <= line.len
          check span.firstByte < span.lastByte
else:
  static:
    doAssert true
