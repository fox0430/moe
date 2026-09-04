import std/[sequtils, unittest]

when defined(moe.matter):
  import ../src/moepkg/syntax/[matter_backend, tokenizer]

  suite "Matter syntax backend":
    test "embedded Nim grammar highlights without filesystem access":
      let first = tokenizeMatterLine("proc hello() = discard", SourceLanguage.langNim)
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
      let line = "# " & char(0xff) & char(0xc0) & " lambda"
      let result = tokenizeMatterLine(line, SourceLanguage.langNim)
      check not result.nextState.failed

    test "all catalogued editor languages except Diff and Log are available":
      for language in SourceLanguage:
        if language in {langNone, langDiff, langLog}:
          check not matterSupports(language)
        else:
          check matterSupports(language)
          let parsed = tokenizeMatterLine("", language, timeLimitMs = 0)
          check not parsed.nextState.failed

    test "multiline resume uses completed structurally equal states":
      let lines = ["#[ outer", "  #[ nested ]#", "still comment", "]#", "let x = true"]
      var first, repeated: MatterLineState
      for i, line in lines:
        let a = tokenizeMatterLine(line, langNim, first, timeLimitMs = 0)
        let b = tokenizeMatterLine(line, langNim, repeated, timeLimitMs = 0)
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
      let parsed = tokenizeMatterLine("// comment", langJsonc, timeLimitMs = 0)
      check not parsed.nextState.failed
      check parsed.spans.anyIt(it.category == mccComment)

    test "Markdown code block state covers opening and content but ends at fence":
      let opening = tokenizeMatterLine("~~~nim", langMarkdown, timeLimitMs = 0)
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
        let line = "# " & sample & " λ"
        let original = line
        let parsed = tokenizeMatterLine(line, langNim, timeLimitMs = 0)
        check not parsed.nextState.failed
        check line == original
        for span in parsed.spans:
          check span.firstByte >= 0
          check span.lastByte <= line.len
          check span.firstByte < span.lastByte
else:
  static:
    doAssert true
