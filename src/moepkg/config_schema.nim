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

## Schema of `moerc.toml`, and the context analysis that drives its completion.
##
## The data is derived from the same `{.cfgSection.}` / `{.cfg.}` declarations
## the loader is built from, so a key that loads is a key that completes.
##
## `analyzeLine` classifies a cursor position (section header, key or value)
## and `candidates` turns it into insertable text. Both are pure string
## operations: the caller supplies the enclosing section.

import std/[options, sequtils, strutils]

import config_macros, unicode_utils

import syntax/tokenizer

import types/config_types

type
  ConfigValueType* = enum
    cvtBool
    cvtInt
    cvtFloat
    cvtString
    cvtEnum
    cvtStringArray

  ConfigSchemaKey* = object
    name*: string ## TOML key name
    valueType*: ConfigValueType
    typeLabel*: string ## Human-readable type, as used by the reference docs
    description*: string ## `{.cfgDocDescription.}` text ("" if undocumented)
    condition*: string
      ## When a `{.cfgOnlyWhen.}` key applies, in words: "only when kind is
      ## \"filter\"". Empty for a key that always applies; shown by the
      ## completion popup.
    values*: seq[string] ## Accepted values, if a closed set. Empty otherwise.

  ConfigSchemaSection* = object
    name*: string ## TOML section name, dotted for nested tables
    description*: string ## Sub-table subject, if the group supplied one
    keys*: seq[ConfigSchemaKey]
    isArrayOfTables*: bool
      ## Written `[[Name]]`, and repeatable. Offering such a name inside a
      ## single `[` would build an invalid header.

  ConfigContextKind* = enum
    cckNone ## Not a completable position (comment, inside a value, …)
    cckSection ## Inside a `[...]` header
    cckKey ## Key name position of a `key = value` line
    cckValue ## Value position of a `key = value` line

  ConfigCompletionContext* = object
    section*: string ## Enclosing section; unused for `cckSection`.
    case kind*: ConfigContextKind
    of cckSection:
      head*: string
        ## Dotted part already typed after `[` (e.g. "Lsp." in "[Lsp.Compl").
        ## The offered text must not repeat it.
      arrayOfTables*: bool ## The header opened with `[[`
    of cckValue:
      key*: string
      inQuotes*: bool ## Cursor is inside a string literal
      quote*: char ## The quote that opened it, 0 outside a string
      hasClosingQuote*: bool ## The closing quote already follows the cursor
      inArray*: bool ## Cursor is inside a `[...]` array value
    of cckNone, cckKey:
      discard

  ConfigCandidate* = object
    text*: string ## Text to insert in place of the typed word prefix
    matchText*: string ## Text the typed prefix is matched against
    label*: string ## Display text
    detail*: string ## Right-hand column of the popup
    documentation*: string
    kind*: ConfigContextKind ## Which of section/key/value this offers

const ThemeKindValues = block:
  # Derived from the enum the loader parses.
  var vals: seq[string] = @[]
  for k in ThemeKind:
    vals.add $k
  vals

const HandWrittenSections = [
  # Hand-loaded tables with caller-defined keys: only the header completes.
  ("KeyMapping", "Key mappings per mode"),
  ("CommandAliases", "User-defined command aliases"),
  ("ShellCommands", "User-defined shell commands"),
]

proc derivedSections(): seq[ConfigSchemaSection] =
  ## Every section the config type declarations produce, and nothing else.
  result = @[]
  generateConfigSchema(result, EditorConfig)
  generateConfigSchema(result, DebugConfig)
  generateSectionGroupSchema(result, LspConfig)
  generateSectionGroupSchema(result, HookConfig)

const DerivedSectionNames* = derivedSections().mapIt(it.name)
  ## Their names, pinned against the reference docs in the test suite: a
  ## generator that skips a section and a file that omits it otherwise agree.

proc buildSchema(): seq[ConfigSchemaSection] =
  result = derivedSections()

  # `[Theme]` is loaded by hand, so its keys are listed here.
  result.add ConfigSchemaSection(
    name: "Theme",
    keys: @[
      ConfigSchemaKey(
        name: "kind",
        valueType: cvtEnum,
        typeLabel: "string (enum: " & ThemeKindValues.join(", ") & ")",
        description: "Theme kind",
        values: ThemeKindValues,
      ),
      ConfigSchemaKey(
        name: "path",
        valueType: cvtString,
        typeLabel: "string",
        description: "Path to the theme file (used when kind is config)",
      ),
    ],
  )

  # `[DisabledCommandAliases]` takes a single hand-loaded key.
  result.add ConfigSchemaSection(
    name: "DisabledCommandAliases",
    description: "Built-in command aliases to disable",
    keys: @[
      ConfigSchemaKey(
        name: "aliases",
        valueType: cvtStringArray,
        typeLabel: "string array",
        description: "Names of the built-in aliases to disable",
      )
    ],
  )

  for (name, desc) in HandWrittenSections:
    result.add ConfigSchemaSection(name: name, description: desc)

const ConfigSchema* = buildSchema()
  ## Every section `moerc.toml` accepts, in declaration order.

func findSection*(name: string): Option[ConfigSchemaSection] =
  for s in ConfigSchema:
    if s.name == name:
      return some(s)

func sectionForHeader*(name: string, arrayOfTables: bool): string =
  ## The section a `[name]` / `[[name]]` header names, or "" when the two
  ## spellings disagree: `[Hook.entries]` and `[[Hook.entries]]` are different
  ## tables to the loader, and only one of them exists.
  let s = findSection(name)
  if s.isSome and s.get.isArrayOfTables != arrayOfTables: "" else: name

func findKey*(section, key: string): Option[ConfigSchemaKey] =
  let sec = findSection(section)
  if sec.isNone:
    return
  for k in sec.get.keys:
    if k.name == key:
      return some(k)

func isKnownSectionHeader*(name: string): bool =
  ## True when `name` should close an open multi-line array. Schema-known
  ## sections always do, as does a dotted child of a known parent, for dynamic
  ## keyspaces like `[Lsp.<languageId>]`. Array elements shaped like headers
  ## (`[1]`) stay unknown so they never close the array holding them.
  if findSection(name).isSome:
    return true
  let dot = name.find('.')
  if dot > 0:
    return findSection(name[0 ..< dot]).isSome
  false

type QuoteState = enum
  ## String state of a TOML line at a given point.
  qsNone
  qsBasic ## Inside `"..."`, where a backslash escapes the next character
  qsLiteral ## Inside `'...'`, which has no escapes

func scan(
    s: string, depth = 0
): tuple[state: QuoteState, comment: int, depth: int, assign: int, closed: bool] =
  ## Walk `s`, returning the string state at its end, the byte index of the `#`
  ## opening a comment (-1 if none), the `[`/`]` depth reached from `depth`,
  ## the byte index of the first `=` outside a string literal (-1 if none) and
  ## whether a string literal or a `[...]` array ended back at `depth`.
  ## Anything inside a string literal is literal text.
  var
    state = qsNone
    i = 0
    d = depth
    assign = -1
    closed = false
  while i < s.len:
    case state
    of qsNone:
      case s[i]
      of '"':
        state = qsBasic
      of '\'':
        state = qsLiteral
      of '#':
        return (qsNone, i, d, assign, closed)
      of '=':
        if assign < 0:
          assign = i
      of '[':
        inc d
      of ']':
        if d > 0:
          dec d
          if d == depth:
            closed = true
      else:
        discard
    of qsBasic:
      if s[i] == '\\':
        inc i
      elif s[i] == '"':
        state = qsNone
        closed = closed or d == depth
    of qsLiteral:
      if s[i] == '\'':
        state = qsNone
        closed = closed or d == depth
    inc i
  (state, -1, d, assign, closed)

func commentStart(s: string): int =
  s.scan.comment

func stripComment(line: string): string =
  let idx = commentStart(line)
  if idx >= 0:
    line[0 ..< idx]
  else:
    line

func parseSectionHeader*(
    line: string
): Option[tuple[name: string, arrayOfTables: bool]] =
  ## The section name of a `[Section]` or `[[Section]]` header line, or none.
  ## An array-of-tables header names a section like any other, so its keys
  ## complete inside it. A trailing comment is allowed. An element of a
  ## multi-line array (`["a", "b"]`) also looks bracketed, so a name holding a
  ## bracket, comma or quote is rejected.
  ##
  ## `[1]` and `[[1]]` are a section by these rules and an array element in
  ## TOML; only the lines above say which. The caller decides, by asking only
  ## where no multi-line array is open (`arrayDepthAfter`).
  let text = line.stripComment.strip
  if text.len >= 2 and text[0] == '[' and text[^1] == ']':
    # The inner brackets of `[[Name]]` sit against the outer ones; `[ [a] ]`
    # is no header.
    var
      inner = text[1 ..^ 2]
      arrayOfTables = false
    if inner.len >= 2 and inner[0] == '[' and inner[^1] == ']':
      inner = inner[1 ..^ 2]
      arrayOfTables = true
    let name = inner.strip
    if name.len > 0 and name.find({'[', ']', ',', '"', '\''}) < 0:
      return some((name, arrayOfTables))

func quoteChar(state: QuoteState): char =
  case state
  of qsNone: '\0'
  of qsBasic: '"'
  of qsLiteral: '\''

func closesQuote(s: string, state: QuoteState): bool =
  ## True when `s`, the text after a cursor sitting inside a `state` literal,
  ## holds that literal's closing quote.
  let q = state.quoteChar
  var i = 0
  while i < s.len:
    if state == qsBasic and s[i] == '\\':
      inc i
    elif s[i] == q:
      return true
    inc i
  false

func arrayDepthAfter*(line: string, depth: int): int =
  ## The `[`/`]` depth at the end of `line`, starting from `depth`. A section
  ## header nets zero, so scanning a section from 0 leaves the depth positive
  ## exactly while a multi-line array is open.
  scan(line, depth).depth

func opensArrayValue*(line: string): bool =
  ## Whether `line`, read where no array is open yet, can open a multi-line
  ## one. Only a value can: `key = [`.
  ##
  ## This keeps a half-typed header (`[Hook`) from being read as an open array,
  ## which would hide every section below it until the `]` is typed. Only a `=`
  ## outside a string counts, so `[KeyMapping."a=b"` is still a header.
  line.scan.assign >= 0

func analyzeLine*(
    line: string, col: int, section: string, inOpenArray = false
): ConfigCompletionContext =
  ## Classify the cursor position at character column `col` of `line`.
  ## `section` is the enclosing `[Section]` (empty above the first header).
  ## `inOpenArray` means the lines above left a multi-line array unclosed, so
  ## everything on this line is array content.
  if col <= 0 or inOpenArray:
    return ConfigCompletionContext(kind: cckNone)

  let before = line.charSubStr(0, col)
  if commentStart(before) >= 0:
    return ConfigCompletionContext(kind: cckNone)

  # A `=` inside a quoted key or section name is literal text, not an
  # assignment: `[KeyMapping."a=b"` is still a header being typed.
  let eq = before.scan.assign
  if eq < 0:
    let bracket = before.rfind('[')
    if bracket >= 0:
      # A second, adjacent `[` opens an array-of-tables header
      # (`[[Hook.entries]]`); TOML rejects a gap between the two brackets.
      # Anything else before it is an array value or a bracketed key.
      let arrayOfTables =
        bracket > 0 and before[bracket - 1] == '[' and
        before[0 ..< bracket - 1].strip.len == 0
      if before[0 ..< bracket].strip.len > 0 and not arrayOfTables:
        return ConfigCompletionContext(kind: cckNone)
      # `head` is the dotted part only: the trailing word is the prefix the
      # offered text replaces.
      # Leading space after `[` is legal TOML, and `head` must line up with
      # the schema names, so drop it.
      let typed = before[bracket + 1 ..^ 1].strip(trailing = false)
      if ']' in typed:
        # The header is already closed before the cursor.
        return ConfigCompletionContext(kind: cckNone)
      let dot = typed.rfind('.')
      return ConfigCompletionContext(
        kind: cckSection,
        head: (if dot >= 0: typed[0 .. dot] else: ""),
        arrayOfTables: arrayOfTables,
      )
    if section.len == 0:
      return ConfigCompletionContext(kind: cckNone)
    return ConfigCompletionContext(kind: cckKey, section: section)

  if section.len == 0:
    return ConfigCompletionContext(kind: cckNone)

  let
    after = line.charSubStr(col, line.charLen - col)
    value = before[eq + 1 ..^ 1].scan
    state = value.state
  if value.closed:
    # The value is already written: a literal or an array closed before the
    # cursor. A candidate replaces only the word before the cursor, so it
    # would append to it (`tags = ["a"]["b"]`) instead of replacing it.
    return ConfigCompletionContext(kind: cckNone)
  ConfigCompletionContext(
    kind: cckValue,
    section: section,
    key: before[0 ..< eq].strip,
    inQuotes: state != qsNone,
    quote: state.quoteChar,
    hasClosingQuote: state != qsNone and after.closesQuote(state),
    inArray: value.depth > 0,
  )

func sectionCandidates*(
    head: string, arrayOfTables: bool, schema: seq[ConfigSchemaSection]
): seq[ConfigCandidate] =
  ## Section headers continuing `head`. The offered text drops `head`, so
  ## `[Lsp.Compl` completes to `[Lsp.Completion`. Only names spelled the way
  ## the header was opened are offered. The schema to search is explicit so
  ## tests can cover array-of-tables filtering without a global array section.
  for s in schema:
    if s.isArrayOfTables != arrayOfTables:
      continue
    if head.len > 0 and not s.name.startsWith(head):
      continue
    let rest = s.name[head.len ..^ 1]
    if rest.len == 0:
      continue
    result.add ConfigCandidate(
      text: rest,
      matchText: rest,
      label: s.name,
      detail: "section",
      documentation: s.description,
      kind: cckSection,
    )

func keyCandidate*(k: ConfigSchemaKey): ConfigCandidate =
  ## One key of a section, as the popup offers it. A conditional key is still
  ## offered -- whether it applies depends on the other keys of the entry,
  ## which completion cannot know -- but it carries its condition.
  ConfigCandidate(
    text: k.name,
    matchText: k.name,
    label: k.name,
    detail:
      if k.condition.len > 0:
        k.typeLabel & ", " & k.condition
      else:
        k.typeLabel,
    documentation:
      if k.condition.len == 0:
        k.description
      elif k.description.len > 0:
        k.description & " (" & k.condition & ")"
      else:
        k.condition,
    kind: cckKey,
  )

func keyCandidates(section: string): seq[ConfigCandidate] =
  let sec = findSection(section)
  if sec.isNone:
    return
  for k in sec.get.keys:
    result.add keyCandidate(k)

func valueCandidatesFor*(
    key: ConfigSchemaKey, ctx: ConfigCompletionContext
): seq[ConfigCandidate] =
  ## The closed set of values for `key`, written the way the loader reads it
  ## back at the cursor: a bare member inside a literal the candidate closes, a
  ## quoted one outside it, and a one-element array for an array-typed key with
  ## neither an array nor a literal open yet.
  ##
  ## An open literal comes first because the candidate replaces only the word
  ## before the cursor: it cannot reach back past the opening quote to bracket
  ## the value, so a quote typed for an array-typed key is the user's to finish.
  ##
  ## A context that is not a value position answers with nothing, rather than
  ## reading `cckValue` fields that do not exist.
  if ctx.kind != cckValue or key.values.len == 0:
    return
  # A closed set that is neither numeric nor boolean is a set of TOML strings.
  let quoted = key.valueType notin {cvtBool, cvtInt, cvtFloat}
  let wrapInArray = key.valueType == cvtStringArray and not ctx.inArray
  for v in key.values:
    let text =
      if not quoted:
        v
      elif ctx.inQuotes:
        if ctx.hasClosingQuote:
          v
        else:
          v & ctx.quote
      elif wrapInArray:
        "[\"" & v & "\"]"
      else:
        "\"" & v & "\""
    result.add ConfigCandidate(
      text: text,
      matchText: v,
      label: v,
      detail: key.typeLabel,
      documentation: key.description,
      kind: cckValue,
    )

func valueCandidates(ctx: ConfigCompletionContext): seq[ConfigCandidate] =
  let key = findKey(ctx.section, ctx.key)
  if key.isNone:
    return
  valueCandidatesFor(key.get, ctx)

func candidates*(ctx: ConfigCompletionContext): seq[ConfigCandidate] =
  ## Everything offerable at `ctx`, unfiltered by the typed prefix.
  case ctx.kind
  of cckNone:
    @[]
  of cckSection:
    sectionCandidates(ctx.head, ctx.arrayOfTables, ConfigSchema)
  of cckKey:
    keyCandidates(ctx.section)
  of cckValue:
    valueCandidates(ctx)
