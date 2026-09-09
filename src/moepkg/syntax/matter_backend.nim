## Optional Matter TextMate adapter. Moe does not bundle grammars: callers add
## grammar source explicitly, either through the public editor/buffer API or
## through files named by the user's configuration.

when not (defined(moe.matter) or defined(features.moe.matter)):
  {.error: "moepkg/syntax/matter_backend requires the Matter feature".}

import std/[sets, strutils, tables]
import matter/[engine, grammarpackages, rawgrammar]

import tokenizer
import ../[logger, unicode_utils]
import ../types/highlight_types

const MatterTimeLimitMs* {.intdefine.} = 20
  ## Soft per-line deadline. Override with -d:matterTimeLimitMs=N; 0 disables
  ## timing for deterministic equivalence tests or intentionally unlimited builds.

static:
  doAssert MatterTimeLimitMs >= 0, "matterTimeLimitMs must be non-negative"

type
  MatterColorCategory* = enum
    mccDefault
    mccComment
    mccString
    mccNumber
    mccBoolean
    mccKeyword
    mccOperator
    mccPreprocessor
    mccFunction
    mccType
    mccBuiltin
    mccIdentifier
    mccProperty

  MatterSpan* = object ## Half-open UTF-8 byte range in the original input line.
    firstByte*, lastByte*: int
    scopes*: seq[string]
    category*: MatterColorCategory

  MatterGrammarSource* = object
    ## One caller-owned TextMate grammar. `path` selects JSON (`.json`) versus
    ## XML plist parsing and is used in diagnostics; Moe never reads it here.
    content*: string
    path*: string
    language*: SourceLanguage
      ## `langNone` lets Moe infer the language from the grammar's scope name.

  MatterGrammarSet* = ref object
    ## An immutable-by-convention collection shared by an editor's buffers.
    ## Use `withMatterGrammar` to derive a set with a programmatic override.
    sources: seq[MatterGrammarSource]
    registry: Registry
    scopes: HashSet[string]
    languageScopes: Table[SourceLanguage, string]
    grammarCache: Table[SourceLanguage, Grammar]
    unavailableLanguages: HashSet[SourceLanguage]

  MatterLineState* = object
    ## Completed state entering the next line. A failure is sticky so a slow
    ## or invalid grammar cannot be retried on every subsequent line/frame.
    grammar: Grammar
    stack*: StateStack
    failed*: bool

proc `==`*(a, b: MatterLineState): bool =
  a.failed == b.failed and a.grammar == b.grammar and a.stack == b.stack

proc `==`*(a, b: MatterGrammarSet): bool =
  ## Runtime caches do not participate in configuration value equality.
  if cast[pointer](a) == cast[pointer](b):
    return true
  if a.isNil:
    return b.sources.len == 0
  if b.isNil:
    return a.sources.len == 0
  a.sources == b.sources

func scopeMatches(scope, prefix: string): bool =
  scope == prefix or scope.startsWith(prefix & ".")

proc isMatterCodeBlock*(state: MatterLineState): bool =
  ## Whether a completed Markdown state is inside a fenced or indented block.
  not state.failed and (
    state.stack.hasActiveScope("markup.fenced_code.block") or
    state.stack.hasActiveScope("markup.raw.block")
  )

proc category(scopes: openArray[string]): MatterColorCategory =
  # Keep comment captures in the comment channel so Moe can apply its own
  # configurable reserved words, even when a grammar marks TODO specially.
  for scope in scopes:
    if scope.scopeMatches("comment"):
      return mccComment
  # Prefer the most specific scope, including interpolated expressions inside
  # strings. Match scope components, not substrings in language names.
  for i in countdown(scopes.high, 0):
    let scope = scopes[i]
    if scope.scopeMatches("comment"):
      return mccComment
    if scope.scopeMatches("constant.numeric"):
      return mccNumber
    if scope.scopeMatches("constant.language") or scope.scopeMatches("constant.boolean"):
      return mccBoolean
    if scope.scopeMatches("entity.name.function"):
      return mccFunction
    if scope.scopeMatches("variable.other.property") or
        scope.scopeMatches("support.type.property-name") or
        scope.scopeMatches("string.quoted.double.json") and
        "meta.structure.dictionary.key.json" in scopes:
      return mccProperty
    if scope.scopeMatches("entity.name.type") or scope.scopeMatches("support.type"):
      return mccType
    if scope.scopeMatches("keyword.operator"):
      return mccOperator
    if scope.scopeMatches("meta.preprocessor") or
        scope.scopeMatches("keyword.control.directive"):
      return mccPreprocessor
    if scope.scopeMatches("keyword") or scope.scopeMatches("storage"):
      return mccKeyword
    if scope.scopeMatches("support.function") or scope.scopeMatches("support.class"):
      return mccBuiltin
    if scope.scopeMatches("variable"):
      return mccIdentifier
    if scope.scopeMatches("string") or scope.scopeMatches("markup.inline.raw"):
      return mccString
  mccDefault

proc scopeFor(language: SourceLanguage): string =
  if language in {langNone, langDiff, langLog}:
    return ""
  let mode = ($language)[4 .. ^1].toLowerAscii
  for mapping in moeGrammarMappings:
    if mapping.modeName.toLowerAscii == mode:
      return mapping.scopeName

proc newMatterGrammarSet*(): MatterGrammarSet =
  ## Create an empty set. An empty set cannot select Matter highlighting.
  MatterGrammarSet(
    registry: newRegistry(),
    scopes: initHashSet[string](),
    languageScopes: initTable[SourceLanguage, string](),
    grammarCache: initTable[SourceLanguage, Grammar](),
    unavailableLanguages: initHashSet[SourceLanguage](),
  )

proc newMatterGrammarSet*(sources: openArray[MatterGrammarSource]): MatterGrammarSet =
  ## Parse and register caller-provided grammar text. All sources are added
  ## before any root is compiled, so they may provide external includes for
  ## one another. Parse errors are reported to the caller.
  result = newMatterGrammarSet()
  for source in sources:
    let path = if source.path.len > 0: source.path else: "grammar.tmLanguage.json"
    let raw =
      try:
        parseRawGrammar(source.content, path)
      except CatchableError as error:
        raise newException(TextMateGrammarError, error.msg)
    try:
      result.registry.addGrammar(raw)
    except CatchableError as error:
      raise newException(TextMateGrammarError, error.msg)
    result.scopes.incl(raw.scopeName)
    result.sources.add(
      MatterGrammarSource(
        content: source.content, path: path, language: source.language
      )
    )
    if source.language != langNone:
      result.languageScopes[source.language] = raw.scopeName

proc grammarFor(grammars: MatterGrammarSet, language: SourceLanguage): Grammar =
  if grammars.isNil or language in {langNone, langDiff, langLog} or
      language in grammars.unavailableLanguages:
    return nil
  let scope =
    if grammars.languageScopes.hasKey(language):
      grammars.languageScopes[language]
    else:
      scopeFor(language)
  if scope.len == 0 or scope notin grammars.scopes:
    return nil
  if grammars.grammarCache.hasKey(language):
    return grammars.grammarCache[language]
  try:
    result = grammars.registry.loadGrammar(scope)
    grammars.grammarCache[language] = result
  except CatchableError as error:
    grammars.unavailableLanguages.incl(language)
    logWarn("highlight", "Matter grammar " & scope & " is unavailable: " & error.msg)

proc matterSupports*(grammars: MatterGrammarSet, language: SourceLanguage): bool =
  ## Matter is available only after this set received a valid root grammar.
  ## Diff and Log deliberately retain Moe's specialised built-in highlighters.
  not grammars.grammarFor(language).isNil

proc matterSupports*(language: SourceLanguage): bool =
  ## The compatibility query has no implicit global grammar registry. Callers
  ## must pass the grammar set they opted into.
  discard language
  false

proc withMatterGrammar*(
    grammars: MatterGrammarSet,
    language: SourceLanguage,
    content: string,
    path = "grammar.tmLanguage.json",
): MatterGrammarSet =
  ## Return a grammar set with one programmatic root for `language`. Existing
  ## inferred/config-file grammars and roots for other languages are retained.
  ## The new root is compiled before return, so malformed regexes fail at the
  ## API boundary instead of silently degrading on the first rendered line.
  if language in {langNone, langDiff, langLog}:
    raise newException(
      TextMateGrammarError,
      "Matter highlighting requires a concrete non-Diff/Log language",
    )
  var sources: seq[MatterGrammarSource]
  if not grammars.isNil:
    for source in grammars.sources:
      if source.language != language:
        sources.add(source)
  sources.add(MatterGrammarSource(content: content, path: path, language: language))
  result = newMatterGrammarSet(sources)
  if result.grammarFor(language).isNil:
    raise newException(
      TextMateGrammarError, "TextMate grammar could not be compiled for " & $language
    )

proc initialMatterState*(
    grammars: MatterGrammarSet, language: SourceLanguage
): MatterLineState =
  ## Create a fresh line state for a grammar set/language pair.
  MatterLineState(grammar: grammars.grammarFor(language))

proc sanitizeInvalidUtf8(line: string): string =
  ## Replace only malformed high bytes with spaces, preserving byte positions
  ## for returned spans. The buffer's original contents are never modified.
  result = line
  var pos = 0
  while pos < result.len:
    let size = result.runeSizeAt(pos)
    if size == 1 and uint8(result[pos]) >= 0x80:
      result[pos] = ' '
    pos += size

proc tokenizeMatterLine*(
    line: string,
    language: SourceLanguage,
    previous = MatterLineState(),
    timeLimitMs = MatterTimeLimitMs,
    grammars: MatterGrammarSet = nil,
): tuple[spans: seq[MatterSpan], nextState: MatterLineState] =
  ## Tokenize one line with a soft deadline (0 disables it). Failed/partial
  ## parses return no spans and no partial stack. Subsequent lines stay plain
  ## until the caller restarts from an earlier successful or fresh state.
  if previous.failed:
    result.nextState = previous
    return
  let grammar =
    if previous.grammar.isNil:
      grammars.grammarFor(language)
    else:
      previous.grammar
  if grammar.isNil:
    result.nextState.failed = true
    return
  result.nextState.grammar = grammar
  try:
    let parsed =
      grammar.tokenizeLine(sanitizeInvalidUtf8(line), previous.stack, timeLimitMs)
    if parsed.stoppedEarly:
      result.nextState.failed = true
      logWarn(
        "highlight",
        "Matter tokenization exceeded its soft line budget for " & $language,
      )
      return
    result.nextState.grammar = grammar
    result.nextState.stack = parsed.completedRuleStack
    for token in parsed.tokens:
      if token.endIndex > token.startIndex:
        result.spans.add(
          MatterSpan(
            firstByte: token.startIndex,
            lastByte: token.endIndex,
            scopes: token.scopes,
            category: category(token.scopes),
          )
        )
  except CatchableError as error:
    result.nextState.failed = true
    logWarn(
      "highlight", "Matter tokenization failed for " & $language & ": " & error.msg
    )
