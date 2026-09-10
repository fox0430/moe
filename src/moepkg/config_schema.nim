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

import std/[options, strutils]

import config_macros, unicode_utils

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
    values*: seq[string] ## Accepted values, if a closed set. Empty otherwise.

  ConfigSchemaSection* = object
    name*: string ## TOML section name, dotted for nested tables
    description*: string ## Sub-table subject, if the group supplied one
    keys*: seq[ConfigSchemaKey]

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
    of cckValue:
      key*: string
      inQuotes*: bool ## Cursor is inside a string literal
      quote*: char ## The quote that opened it, 0 outside a string
      hasClosingQuote*: bool ## The closing quote already follows the cursor
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

proc buildSchema(): seq[ConfigSchemaSection] =
  result = @[]
  generateConfigSchema(result, EditorConfig)
  generateConfigSchema(result, DebugConfig)
  generateSectionGroupSchema(result, LspConfig)

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

func findKey*(section, key: string): Option[ConfigSchemaKey] =
  let sec = findSection(section)
  if sec.isNone:
    return
  for k in sec.get.keys:
    if k.name == key:
      return some(k)

type QuoteState = enum
  ## String state of a TOML line at a given point.
  qsNone
  qsBasic ## Inside `"..."`, where a backslash escapes the next character
  qsLiteral ## Inside `'...'`, which has no escapes

func scan(s: string, depth = 0): tuple[state: QuoteState, comment: int, depth: int] =
  ## Walk `s`, returning the string state at its end, the byte index of the `#`
  ## opening a comment (-1 if none) and the `[`/`]` depth reached from `depth`.
  ## Anything inside a string literal is literal text.
  var
    state = qsNone
    i = 0
    d = depth
  while i < s.len:
    case state
    of qsNone:
      case s[i]
      of '"':
        state = qsBasic
      of '\'':
        state = qsLiteral
      of '#':
        return (qsNone, i, d)
      of '[':
        inc d
      of ']':
        if d > 0:
          dec d
      else:
        discard
    of qsBasic:
      if s[i] == '\\':
        inc i
      elif s[i] == '"':
        state = qsNone
    of qsLiteral:
      if s[i] == '\'':
        state = qsNone
    inc i
  (state, -1, d)

func commentStart(s: string): int =
  s.scan.comment

func stripComment(line: string): string =
  let idx = commentStart(line)
  if idx >= 0:
    line[0 ..< idx]
  else:
    line

func parseSectionHeader*(line: string): Option[string] =
  ## The section name of a `[Section]` header line, or none for any other
  ## line. A trailing comment is allowed.
  let s = line.stripComment.strip
  if s.len >= 2 and s[0] == '[' and s[^1] == ']':
    let name = s[1 ..^ 2].strip
    if name.len > 0:
      return some(name)

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

  let eq = before.find('=')
  if eq < 0:
    let bracket = before.rfind('[')
    if bracket >= 0:
      if before[0 ..< bracket].strip.len > 0:
        # Not a header: an array value or a bracketed key.
        return ConfigCompletionContext(kind: cckNone)
      # `head` is the dotted part only: the trailing word is the prefix the
      # offered text replaces.
      let typed = before[bracket + 1 ..^ 1]
      if ']' in typed:
        # The header is already closed before the cursor.
        return ConfigCompletionContext(kind: cckNone)
      let dot = typed.rfind('.')
      return ConfigCompletionContext(
        kind: cckSection, head: (if dot >= 0: typed[0 .. dot] else: "")
      )
    if section.len == 0:
      return ConfigCompletionContext(kind: cckNone)
    return ConfigCompletionContext(kind: cckKey, section: section)

  if section.len == 0:
    return ConfigCompletionContext(kind: cckNone)

  let
    after = line.charSubStr(col, line.charLen - col)
    state = before[eq + 1 ..^ 1].scan.state
  ConfigCompletionContext(
    kind: cckValue,
    section: section,
    key: before[0 ..< eq].strip,
    inQuotes: state != qsNone,
    quote: state.quoteChar,
    hasClosingQuote: state != qsNone and after.closesQuote(state),
  )

func sectionCandidates(head: string): seq[ConfigCandidate] =
  ## Section headers continuing `head`. The offered text drops `head`, so
  ## `[Lsp.Compl` completes to `[Lsp.Completion`.
  for s in ConfigSchema:
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

func keyCandidates(section: string): seq[ConfigCandidate] =
  let sec = findSection(section)
  if sec.isNone:
    return
  for k in sec.get.keys:
    result.add ConfigCandidate(
      text: k.name,
      matchText: k.name,
      label: k.name,
      detail: k.typeLabel,
      documentation: k.description,
      kind: cckKey,
    )

func valueCandidates(ctx: ConfigCompletionContext): seq[ConfigCandidate] =
  ## The closed set of values for the key being assigned. Enum values are TOML
  ## strings, so they carry their own quotes unless the cursor is already
  ## inside a literal, which they then close.
  let key = findKey(ctx.section, ctx.key)
  if key.isNone or key.get.values.len == 0:
    return
  let quoted = key.get.valueType == cvtEnum
  for v in key.get.values:
    let text =
      if not quoted:
        v
      elif ctx.inQuotes:
        if ctx.hasClosingQuote:
          v
        else:
          v & ctx.quote
      else:
        "\"" & v & "\""
    result.add ConfigCandidate(
      text: text,
      matchText: v,
      label: v,
      detail: key.get.typeLabel,
      documentation: key.get.description,
      kind: cckValue,
    )

func candidates*(ctx: ConfigCompletionContext): seq[ConfigCandidate] =
  ## Everything offerable at `ctx`, unfiltered by the typed prefix.
  case ctx.kind
  of cckNone:
    @[]
  of cckSection:
    sectionCandidates(ctx.head)
  of cckKey:
    keyCandidates(ctx.section)
  of cckValue:
    valueCandidates(ctx)
