when defined(moe.matter) or defined(features.moe.matter):
  import std/[sequtils, strutils, unittest]
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
      check grammars.matterSupports(langHtml)
      check not grammars.matterSupports(langRust)
      check not grammars.matterSupports(langDiff)
      check not grammars.matterSupports(langLog)

    test "HTML tags, attributes, values, and text retain distinct categories":
      let line =
        "<nk-window id=\"main\"><span class='muted'>Plain text</span></nk-window>"
      let parsed = tokenizeMatterLine(
        line, langHtml, timeLimitMs = 0, grammars = newTestMatterGrammarSet()
      )
      require not parsed.nextState.failed
      for (fragment, expected) in [
        ("nk-window", mccBuiltin),
        ("id", mccProperty),
        ("main", mccString),
        ("span", mccBuiltin),
        ("class", mccProperty),
        ("muted", mccString),
        ("Plain text", mccDefault),
      ]:
        checkpoint(fragment)
        let offset = line.find(fragment)
        let spans =
          parsed.spans.filterIt(it.firstByte <= offset and offset < it.lastByte)
        require spans.len == 1
        check spans[0].category == expected

    test "common semantic scopes use the existing theme categories":
      # Vocabulary from Matter's bundled grammar catalog, including embedded
      # CSS and NIF roots that hosts can associate with a Moe language explicitly.
      for (scope, expected) in [
        ("entity.name.tag.html", mccBuiltin),
        ("entity.name.tag.localname.xml", mccBuiltin),
        ("entity.name.tag.tsx", mccBuiltin),
        ("entity.name.tag.css", mccBuiltin),
        ("entity.name.tag.nif", mccBuiltin),
        ("entity.other.attribute-name.html", mccProperty),
        ("entity.other.attribute-name.localname.xml", mccProperty),
        ("entity.other.attribute-name.tsx", mccProperty),
        ("entity.other.attribute-name.pseudo-class.css", mccProperty),
        ("entity.name.tag.yaml", mccProperty),
        ("support.type.vendored.property-name.css", mccProperty),
        ("support.variable.property.js", mccProperty),
        ("variable.object.property.ts", mccProperty),
        ("variable.other.object.property.java", mccProperty),
        ("variable.other.constant.property.js", mccProperty),
        ("variable.other.constant.object.property.ts", mccProperty),
        ("variable.other.member.hcl", mccProperty),
        ("entity.name.variable.property.cs", mccProperty),
        ("entity.name.variable.field.cs", mccProperty),
        ("variable.property.name.tcl", mccProperty),
        ("entity.function.property.name.tcl", mccProperty),
        ("entity.name.class.lua", mccType),
        ("entity.other.inherited-class.python", mccType),
        ("entity.name.namespace.cpp", mccType),
        ("entity.name.module.rust", mccType),
        ("entity.name.package.haskell", mccType),
        ("entity.name.scope-resolution.cpp", mccType),
        ("variable.other.generic-type.haskell", mccType),
        ("entity.name.command.shell", mccFunction),
        ("entity.name.operator.cpp", mccOperator),
        ("constant.other.operator.haskell", mccOperator),
        ("entity.name.other.preprocessor.macro.predefined.cpp", mccPreprocessor),
        ("entity.name.function.preprocessor.cpp", mccPreprocessor),
        ("support.constant.property-value.css", mccBuiltin),
        ("support.variable.magic.python", mccBuiltin),
        ("variable.language.this.js", mccBuiltin),
        ("variable.parameter.function.language.special.self.python", mccBuiltin),
        ("variable.legacy.builtin.python", mccBuiltin),
        ("variable.other.constant.cs", mccBuiltin),
        ("variable.other.enummember.ts", mccBuiltin),
        ("entity.name.variable.enum-member.cs", mccBuiltin),
        ("constant.other.caps.rust", mccBuiltin),
        ("constant.other.haskell", mccBuiltin),
        ("constant.other.color.rgb-value.hex.css", mccNumber),
        ("constant.other.time.datetime.offset.toml", mccNumber),
        ("constant.other.timestamp.yaml", mccNumber),
        ("constant.other.location.nif", mccNumber),
        ("constant.language.infinity.js", mccNumber),
        ("constant.language.nan.ts", mccNumber),
        ("constant.language.null.js", mccBuiltin),
        ("constant.language.undefined.ts", mccBuiltin),
        ("constant.language.empty.nif", mccBuiltin),
        ("constant.language.symbol.commonlisp", mccBuiltin),
        ("constant.character.entity.named.amp.html", mccString),
        ("constant.character.escape.python", mccString),
        ("constant.other.rune.go", mccString),
        ("entity.name.variable.local.cs", mccIdentifier),
        ("entity.name.symbol.nif", mccIdentifier),
        ("markup.heading.markdown", mccBuiltin),
        ("entity.name.section.markdown", mccBuiltin),
      ]:
        checkpoint(scope)
        let parsed = tokenizeMatterLine(
          "token",
          langNim,
          timeLimitMs = 0,
          grammars = newScopedTestMatterGrammarSet([scope]),
        )
        require not parsed.nextState.failed
        require parsed.spans.len == 1
        check parsed.spans[0].scopes[^1] == scope
        check parsed.spans[0].category == expected

    test "mapping keys preserve more specific embedded expressions":
      for (scopes, expected) in [
        (
          @["meta.structure.dictionary.key.json", "string.quoted.double.json"],
          mccProperty,
        ),
        (@["meta.mapping.key.hcl", "variable.other.readwrite.hcl"], mccProperty),
        (@["meta.mapping.key.hcl", "string.quoted.double.hcl"], mccProperty),
        (@["variable.declaration.hcl", "variable.other.readwrite.hcl"], mccProperty),
        (
          @[
            "meta.mapping.key.hcl", "string.quoted.double.hcl",
            "variable.other.readwrite.hcl",
          ],
          mccIdentifier,
        ),
        (@["string.quoted.double.js", "support.variable.property.js"], mccProperty),
        (@["string.quoted.double.cs", "entity.name.variable.local.cs"], mccIdentifier),
        (@["markup.heading.markdown", "markup.inline.raw.string.markdown"], mccString),
        (
          @["comment.block.documentation.java", "entity.name.type.class.java"],
          mccComment,
        ),
      ]:
        checkpoint(scopes.join(" > "))
        let parsed = tokenizeMatterLine(
          "token",
          langNim,
          timeLimitMs = 0,
          grammars = newScopedTestMatterGrammarSet(scopes),
        )
        require not parsed.nextState.failed
        require parsed.spans.len == 1
        check parsed.spans[0].category == expected

    test "pragma captures retain their surrounding preprocessor category":
      for language in ["c", "cpp"]:
        for capture in [
          "entity.other.attribute-name.pragma.preprocessor.",
          "entity.name.tag.pragma-mark.",
        ]:
          let scopes = @["meta.preprocessor.pragma." & language, capture & language]
          checkpoint(scopes.join(" > "))
          let parsed = tokenizeMatterLine(
            "token",
            langNim,
            timeLimitMs = 0,
            grammars = newScopedTestMatterGrammarSet(scopes),
          )
          require not parsed.nextState.failed
          require parsed.spans.len == 1
          check parsed.spans[0].category == mccPreprocessor

    test "regexp captures and format placeholders retain surrounding string colors":
      for capture in [
        "constant.other.character-class.regexp",
        "constant.other.character-class.set.regexp",
        "constant.other.character-class.range.regexp", "constant.other.set.regexp",
        "entity.name.tag.named.group.regexp",
        "entity.name.tag.named.backreference.regexp",
        "entity.name.tag.backreference.regexp", "constant.other.placeholder",
        "constant.other.placeholder.c", "constant.other.placeholder.go",
      ]:
        checkpoint(capture)
        for outer in ["string.regexp.js", "string.quoted.double.c"]:
          let parsed = tokenizeMatterLine(
            "token",
            langNim,
            timeLimitMs = 0,
            grammars = newScopedTestMatterGrammarSet([outer, capture]),
          )
          require not parsed.nextState.failed
          require parsed.spans.len == 1
          check parsed.spans[0].category == mccString

    test "scope matching respects component boundaries and unknown metadata":
      for (scope, expected) in [
        ("entity.name.tagged.html", mccDefault),
        ("entity.other.attribute-names.html", mccDefault),
        ("entity.name.classification.lua", mccDefault),
        ("entity.name.namespaceish.cpp", mccDefault),
        ("constant.otherwise.css", mccDefault),
        ("support.constantish.css", mccDefault),
        ("meta.tag.html", mccDefault),
        ("punctuation.definition.tag.begin.html", mccDefault),
        ("source.string.language", mccDefault),
        ("variable.languageish.js", mccIdentifier),
        ("keyword.operatorish.cpp", mccKeyword),
        ("entity.other.attribute-name.pragmaish.c", mccProperty),
        ("entity.name.tag.pragma-marked.c", mccBuiltin),
        ("constant.other.placeholderish.c", mccBuiltin),
        ("constant.other.character-class.regexpish", mccBuiltin),
        ("constant.other.character-class.regexp.js", mccDefault),
      ]:
        checkpoint(scope)
        let parsed = tokenizeMatterLine(
          "token",
          langNim,
          timeLimitMs = 0,
          grammars = newScopedTestMatterGrammarSet([scope]),
        )
        require not parsed.nextState.failed
        require parsed.spans.len == 1
        check parsed.spans[0].category == expected

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
