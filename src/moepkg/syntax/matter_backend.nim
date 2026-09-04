## Optional Matter TextMate adapter, with resources embedded from the pinned
## source package. Only Matter-enabled builds import this module. Grammar and
## resource caches belong to the editor thread; immutable line states belong to
## each buffer's incremental cache.

when not defined(moe.matter):
  {.error: "moepkg/syntax/matter_backend requires -d:moe.matter".}

import std/[macros, options, os, sets, streams, strutils, tables]
import matter/[engine, grammarloader, grammarpackages]
import zippy/ziparchives_v1

import tokenizer
import ../[logger, unicode_utils]

const matterGrammarRoot* {.strdefine.} = ""
  ## Optional full Matter source checkout containing data/grammars. Atlas
  ## checkouts are located automatically; Nimble 0.3.0 installs omit the assets.

const MatterTimeLimitMs* {.intdefine.} = 20
  ## Soft per-line deadline. Override with -d:matterTimeLimitMs=N; 0 disables
  ## timing for deterministic equivalence tests or intentionally unlimited builds.

static:
  doAssert MatterTimeLimitMs >= 0, "matterTimeLimitMs must be non-negative"

macro matterRoot(): untyped =
  if matterGrammarRoot.len > 0:
    result = newLit(matterGrammarRoot)
  else:
    let source = bindSym"findMoeGrammar".getImpl.lineInfoObj.filename
    result = newLit(source.parentDir.parentDir.parentDir)

const ResolvedMatterRoot = matterRoot()

static:
  doAssert dirExists(ResolvedMatterRoot / "data/grammars"),
    "Matter grammar assets are unavailable. Build with Atlas, or pass " &
      "-d:matterGrammarRoot=/full/matter-v0.3.0-source-checkout"

macro embedArchives(): untyped =
  # Use the pinned package catalog as the single source of archive names.
  result = newNimNode(nnkBracket)
  for package in knownPackages:
    result.add(
      newTree(
        nnkTupleConstr,
        newLit(package.dataArchivePath),
        newCall(
          bindSym"staticRead", newLit(ResolvedMatterRoot / package.dataArchivePath)
        ),
      )
    )

const EmbeddedArchives = embedArchives()

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

  MatterLineState* = object
    ## Completed state entering the next line. A failure is sticky so a slow
    ## or invalid grammar cannot be retried on every subsequent line/frame.
    stack*: StateStack
    failed*: bool

var
  grammarCache: Table[string, Grammar]
  unavailableScopes: HashSet[string]
  extractedArchives: Table[string, Table[string, string]]

proc `==`*(a, b: MatterLineState): bool =
  a.failed == b.failed and a.stack == b.stack

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

proc embeddedArchive(path: string): string =
  for archive in EmbeddedArchives:
    if archive[0] == path:
      return archive[1]

proc embeddedResource(contribution: GrammarContribution): Option[string] =
  let path = contribution.dataArchivePath
  if not extractedArchives.hasKey(path):
    let data = embeddedArchive(path)
    if data.len == 0:
      return none(string)
    var archive = ZipArchive()
    # Zippy's modern reader accepts file paths only. Keep the deprecated
    # in-memory stream API isolated until Zippy provides a bytes reader.
    {.push warning[Deprecated]: off.}
    archive.open(newStringStream(data))
    {.pop.}
    var members: Table[string, string]
    for grammar in knownGrammars:
      if grammar.dataArchivePath == path and
          archive.contents.hasKey(grammar.archiveMember):
        members[grammar.archiveMember] =
          archive.contents[grammar.archiveMember].contents
    extractedArchives[path] = members
  if extractedArchives[path].hasKey(contribution.archiveMember):
    some(extractedArchives[path][contribution.archiveMember])
  else:
    none(string)

proc scopeFor(language: SourceLanguage): string =
  if language in {langNone, langDiff, langLog}:
    return ""
  let mode = ($language)[4 .. ^1].toLowerAscii
  for mapping in moeGrammarMappings:
    if mapping.modeName.toLowerAscii == mode:
      return mapping.scopeName

proc matterSupports*(language: SourceLanguage): bool =
  ## Diff and Log deliberately retain Moe's specialised built-in highlighters.
  scopeFor(language).len > 0

proc grammarFor(language: SourceLanguage): Grammar =
  let scope = scopeFor(language)
  if scope.len == 0 or scope in unavailableScopes:
    return nil
  if grammarCache.hasKey(scope):
    return grammarCache[scope]
  try:
    let registry = newRegistry()
    # Optional external includes are common in TextMate packages. The loader
    # registers every available dependency; missing optional scopes are not a
    # reason to disable the root grammar.
    discard registry.loadGrammarPackage(embeddedResource, scope)
    result = registry.loadGrammar(scope)
    grammarCache[scope] = result
  except CatchableError as error:
    unavailableScopes.incl(scope)
    logWarn("highlight", "Matter grammar " & scope & " is unavailable: " & error.msg)

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
): tuple[spans: seq[MatterSpan], nextState: MatterLineState] =
  ## Tokenize one line with a soft deadline (0 disables it). Failed/partial
  ## parses return no spans and no partial stack. Subsequent lines stay plain
  ## until the caller restarts from an earlier successful or fresh state.
  if previous.failed:
    result.nextState = previous
    return
  let grammar = grammarFor(language)
  if grammar.isNil:
    result.nextState.failed = true
    return
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
