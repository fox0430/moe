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

## Auto-completion system for Insert mode
##
## This module provides buffer word completion and LSP completion functionality.
## It collects words from the current buffer and/or LSP server and presents them
## in a popup menu for selection.

import
  std/
    [algorithm, sequtils, strutils, unicode, sets, options, json, os, monotimes, times]

import pkg/[celina, jsony]

import
  buffer, word_dictionary, command_completion, fuzzy_match, color, popup_render,
  unicode_utils
import syntax/tokenizer
import lsp/protocol/types as lspTypes

export lspTypes

type
  CompletionState* = enum
    csIdle ## No completion active
    csActive ## Popup visible, items available
    csPendingLsp ## Waiting for LSP response

  CompletionSource* = enum
    csBuffer ## From buffer words
    csLsp ## From LSP server
    csKeyword ## From language keywords
    csFilePath ## From file system paths

  CompletionEntry* = object ## A single completion entry
    word*: string ## The word to insert
    label*: string ## Text shown in the popup (falls back to `word` when empty)
    matchScore*: int ## Score for sorting (higher = better match)
    source*: CompletionSource ## Where this entry came from
    kind*: Option[CompletionItemKind] ## LSP completion kind (function, variable, etc.)
    detail*: Option[string] ## LSP detail (e.g., type signature)
    documentation*: Option[string] ## LSP documentation
    textEdit*: Option[TextEdit] ## LSP textEdit for range-based replacement
    additionalTextEdits*: Option[seq[TextEdit]] ## Additional edits to apply
    isSnippet*: bool ## True when the insert text is an LSP snippet (placeholders)
    filterText*: string ## LSP filterText for matching (falls back to label/word)
    sortText*: string ## LSP sortText for ordering (falls back to label/word)
    lspItemIndex*: int ## Index into lspItems (-1 = not from LSP)

  CompletionMenu* = object ## Completion popup state
    entries*: seq[CompletionEntry]
    selectedIndex*: int ## Currently selected item (0-based)
    scrollOffset*: int ## For scrolling long lists
    maxVisible*: int ## Max items to show (default: 10)
    prefix*: string ## Current filter prefix
    triggerLine*: int ## Line where completion was triggered
    triggerCol*: int ## Column where completion was triggered
    hasSelection*: bool ## True after first Tab press (enables auto-insert)

  DocPanel* = object ## Documentation panel display state
    lines*: seq[string] ## Text lines to display
    scrollOffset*: int ## Current vertical scroll offset
    visible*: bool ## Whether the panel is visible

  CompletionManager* = ref object ## Manages completion state and operations
    state*: CompletionState
    menu*: CompletionMenu
    docPanel*: DocPanel ## Documentation panel for selected item
    allWords*: seq[string] ## All collected words from buffer
    wordCache: HashSet[string]
      ## Buffer/other-buffer words from the last scan (no cursor exclusion,
      ## no keywords). Reused while `wordCacheSig` still matches the sources.
    wordCacheSig: seq[(BufferId, int)]
      ## (id, contentVersion) of every scanned buffer; empty until the first
      ## scan, so an unmodified buffer skips re-scanning on the next trigger.
    lspRequestId*: Option[int] ## Pending LSP request ID
    lspItems*: seq[CompletionItem] ## Raw LSP completion items
    otherBuffers*: seq[TextBuffer]
      ## Other FileEditMode buffers for multi-buffer completion
    isPathCompletion*: bool ## Whether currently in path completion mode
    pathBasePath*: string ## Base directory for resolving relative paths
    pathOriginalPrefix*: string ## Full path prefix typed so far (e.g. "./src/")
    lastLspRequestTime*: MonoTime ## Time of last LSP completion request
    isIncomplete*: bool ## Whether last LSP completion list was incomplete
    lastLspPrefix*: string ## Prefix used for last LSP request
    resolvedIndex*: int ## Index of item being resolved

  PopupPosition* = object
    x*, y*: int
    width*, height*: int

  SnippetStopOffset* = object ## A tabstop located inside the expanded snippet text.
    num*: int ## Tabstop number; 0 is the final stop.
    offset*: int ## Rune offset of the stop within the expanded text.
    len*: int ## Rune length of the placeholder default (0 for bare `$n`).

  SnippetParse = object
    text: string
    finalStop: int ## rune offset of `$0` (the final stop), or -1 if absent
    firstStopNum: int ## lowest tabstop number seen (>=1), high(int) if none
    firstStopOffset: int ## rune offset of that lowest-numbered stop, or -1
    stops: seq[SnippetStopOffset] ## every stop in source order (mirrors kept)

const
  DefaultMaxVisible* = 10
  MinWordLength* = 2 ## Minimum word length to collect
  MinPrefixLength* = 1 ## Minimum prefix length to trigger (manual)
  AutoTriggerPrefixLength* = 1 ## Minimum prefix length for auto-trigger
  MinPopupWidth* = 15 ## Minimum popup width
  MaxPopupWidth* = 80 ## Maximum popup width
  MaxDetailWidth* = 30 ## Maximum detail column width
  DetailSeparatorWidth* = 2 ## Gap between word and detail columns
  PopupPadding* = 2 ## Padding inside popup (left + right)
  LspDebounceMs* = 100 ## Debounce interval for LSP completion requests
  DocPanelMaxWidth* = 60 ## Maximum width of documentation panel
  DocPanelMinWidth* = 20 ## Minimum width of documentation panel
  DocPanelMaxVisibleLines* = 10 ## Maximum visible lines in doc panel

# Styles are derived from the current theme on each call so that theme changes
# (and the theme being loaded after this module is initialized) are reflected.

# Documentation panel
proc docPanelNormalStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.popupWindow)

proc docPanelBorderStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.popupWindowBorder)

proc docPanelScrollStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.popupWindowScrollBar)

proc popupNormalStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.popupWindow)

proc popupSelectedStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.popupWinCurrentLine)

proc popupDetailStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.popupWindowDetail)

proc popupSelectedDetailStyle*(): Style =
  ## Detail text on the selected row: detail foreground over the
  ## current-line background.
  Style(
    fg: getThemeStyle(EditorColorPairIndex.popupWindowDetail).fg,
    bg: getThemeStyle(EditorColorPairIndex.popupWinCurrentLine).bg,
    modifiers: {},
  )

proc popupBorderStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.popupWindowBorder)

# Forward declaration
proc cancelCompletion*(mgr: CompletionManager)

proc isDigitRune(r: Rune): bool =
  ## Check if a rune is an ASCII digit (0-9)
  let code = int(r)
  code >= ord('0') and code <= ord('9')

proc extractWords*(line: string): seq[string] =
  ## Extract all words from a line
  result = @[]
  var currentWord = ""

  for r in line.runes:
    if r.isWordChar:
      currentWord.add($r)
    else:
      if currentWord.len >= MinWordLength:
        result.add(currentWord)
      currentWord = ""

  # Don't forget the last word
  if currentWord.len >= MinWordLength:
    result.add(currentWord)

proc extractWordAtPosition*(line: string, col: int): string =
  ## Extract the word at the given column position
  ## Returns the word that the cursor is on or just after
  if line.len == 0 or col < 0:
    return ""

  var runes: seq[Rune] = @[]
  for r in line.runes:
    runes.add(r)

  if col > runes.len:
    return ""

  # Find word start (go backwards from col)
  var startIdx = col
  while startIdx > 0 and startIdx <= runes.len and runes[startIdx - 1].isWordChar:
    dec startIdx

  # Find word end (go forward from col)
  var endIdx = col
  while endIdx < runes.len and runes[endIdx].isWordChar:
    inc endIdx

  # Build the word
  for i in startIdx ..< endIdx:
    result.add($runes[i])

proc extractPrefixBeforeCursor*(line: string, col: int): string =
  ## Extract the word prefix before the cursor
  ## This is used to filter completions
  if line.len == 0 or col <= 0:
    return ""

  var runes: seq[Rune] = @[]
  for r in line.runes:
    runes.add(r)

  if col > runes.len:
    return ""

  # Go backwards from cursor to find word start
  var startIdx = col
  while startIdx > 0 and runes[startIdx - 1].isWordChar:
    dec startIdx

  # Build prefix from start to cursor
  for i in startIdx ..< col:
    result.add($runes[i])

proc isPathChar*(r: Rune): bool =
  ## Check if a rune is part of a file path
  ## Includes alphanumeric, underscore, dash, dot, slash, tilde
  r.isAlpha or r.isDigitRune or r == '_'.Rune or r == '-'.Rune or r == '.'.Rune or
    r == '/'.Rune or r == '~'.Rune

proc extractPathPrefixBeforeCursor*(line: string, col: int): string =
  ## Extract the path prefix before the cursor position.
  ## Scans backwards from cursor collecting path characters.
  ## Returns the path prefix only if it contains a '/' character,
  ## otherwise returns empty string (not a path context).
  if line.len == 0 or col <= 0:
    return ""

  var runes: seq[Rune] = @[]
  for r in line.runes:
    runes.add(r)

  if col > runes.len:
    return ""

  # Go backwards from cursor to find path start
  var startIdx = col
  while startIdx > 0 and runes[startIdx - 1].isPathChar:
    dec startIdx

  # Build the prefix
  var prefix = ""
  for i in startIdx ..< col:
    prefix.add($runes[i])

  # Only return as path prefix if it contains a slash
  if '/' in prefix:
    return prefix
  else:
    return ""

proc collectWordSet(
    buffer: TextBuffer, otherBuffers: seq[TextBuffer]
): HashSet[string] =
  ## Unique words from `buffer` and every distinct buffer in `otherBuffers`.
  ## The word under the cursor is not excluded here — callers drop it from the
  ## returned set when they need to.
  result = initHashSet[string]()
  var seen = initHashSet[BufferId]()
  seen.incl(buffer.id)
  for lineIdx in 0 ..< buffer.len:
    for word in extractWords(buffer.getLine(lineIdx)):
      result.incl(word)

  # Collect words from other open FileEditMode buffers, scanning each distinct
  # buffer once (the same buffer can appear in multiple split windows).
  for otherBuf in otherBuffers:
    if otherBuf.id in seen:
      continue
    seen.incl(otherBuf.id)
    for lineIdx in 0 ..< otherBuf.len:
      for word in extractWords(otherBuf.getLine(lineIdx)):
        result.incl(word)

proc collectBufferWords*(
    buffer: TextBuffer, excludePos: BufferPosition, otherBuffers: seq[TextBuffer] = @[]
): seq[string] =
  ## Collect all unique words from the current buffer and other open buffers.
  ## Excludes the word at the current cursor position. Order is unspecified;
  ## callers rank the entries by match score downstream.
  var wordSet = collectWordSet(buffer, otherBuffers)

  let currentWord =
    extractWordAtPosition(buffer.getLine(excludePos.line), excludePos.column)
  if currentWord.len > 0:
    wordSet.excl(currentWord)

  result = wordSet.toSeq

# Completion menu operations

proc newCompletionManager*(): CompletionManager =
  ## Create a new completion manager
  CompletionManager(
    state: csIdle,
    menu: CompletionMenu(
      entries: @[],
      selectedIndex: 0,
      scrollOffset: 0,
      maxVisible: DefaultMaxVisible,
      prefix: "",
      triggerLine: 0,
      triggerCol: 0,
    ),
    allWords: @[],
    lspRequestId: none(int),
    lspItems: @[],
    isPathCompletion: false,
    pathBasePath: "",
    pathOriginalPrefix: "",
  )

proc getDocumentationText(doc: JsonNode): Option[string] =
  ## Extract documentation text from LSP documentation field
  if doc.isNil:
    return none(string)

  case doc.kind
  of JString:
    return some(doc.getStr)
  of JObject:
    # MarkupContent
    if doc.hasKey("value"):
      return some(doc["value"].getStr)
  else:
    discard
  return none(string)

proc matchingBrace(body: string, openIdx: int): int =
  ## Return the index of the '}' matching the '{' at openIdx, honoring nesting
  ## and `\}` escapes. Returns -1 if unbalanced.
  var depth = 0
  var j = openIdx
  while j < body.len:
    let ch = body[j]
    if ch == '\\' and j + 1 < body.len:
      j += 2
      continue
    if ch == '{':
      inc depth
    elif ch == '}':
      dec depth
      if depth == 0:
        return j
    inc j
  return -1

proc parseSnippet(body: string): SnippetParse =
  ## Recursive worker for expandSnippet. Walks the snippet body once, building
  ## the plain text and recording cursor-stop offsets (the final `$0` and the
  ## lowest-numbered tabstop). Placeholder defaults are parsed recursively so a
  ## stop nested inside a `${n:...}` default is honored.
  result =
    SnippetParse(text: "", finalStop: -1, firstStopNum: high(int), firstStopOffset: -1)
  var i = 0
  let n = body.len

  template recordStop(num, pos: int) =
    if num == 0:
      if result.finalStop < 0:
        result.finalStop = pos
    elif num >= 1 and num < result.firstStopNum:
      result.firstStopNum = num
      result.firstStopOffset = pos

  while i < n:
    let c = body[i]
    if c == '\\' and i + 1 < n and body[i + 1] in {'$', '}', '\\'}:
      result.text.add(body[i + 1])
      i += 2
    elif c == '$' and i + 1 < n and body[i + 1] == '{':
      let closeIdx = matchingBrace(body, i + 1)
      if closeIdx < 0:
        result.text.add(c) # malformed — emit literally
        inc i
      else:
        let inner = body[i + 2 ..< closeIdx]
        var k = 0
        while k < inner.len and inner[k] in {'0' .. '9'}:
          inc k
        var default = ""
        let colonPos = inner.find(':')
        if colonPos >= 0:
          default = inner[colonPos + 1 ..^ 1]
        let pos = result.text.runeLen
        # Numbered tabstop / placeholder. Guard parseInt against an
        # overflowing digit run from a malformed snippet (-1 => ignore).
        let num =
          if k > 0:
            try:
              parseInt(inner[0 ..< k])
            except ValueError:
              -1
          else:
            -1
        if num >= 0:
          recordStop(num, pos)
        var defaultRuneLen = 0
        if default.len > 0:
          # Expand the default, lifting any stop nested inside it to our coords.
          let sub = parseSnippet(default)
          if sub.finalStop >= 0 and result.finalStop < 0:
            result.finalStop = pos + sub.finalStop
          if sub.firstStopOffset >= 0 and sub.firstStopNum < result.firstStopNum:
            result.firstStopNum = sub.firstStopNum
            result.firstStopOffset = pos + sub.firstStopOffset
          defaultRuneLen = sub.text.runeLen
          if num >= 0:
            result.stops.add(
              SnippetStopOffset(num: num, offset: pos, len: defaultRuneLen)
            )
          for s in sub.stops:
            result.stops.add(
              SnippetStopOffset(num: s.num, offset: pos + s.offset, len: s.len)
            )
          result.text.add(sub.text)
        elif num >= 0:
          result.stops.add(SnippetStopOffset(num: num, offset: pos, len: 0))
        i = closeIdx + 1
    elif c == '$' and i + 1 < n and body[i + 1] in {'0' .. '9'}:
      var k = i + 1
      while k < n and body[k] in {'0' .. '9'}:
        inc k
      let num =
        try:
          parseInt(body[i + 1 ..< k])
        except ValueError:
          -1
      if num >= 0:
        recordStop(num, result.text.runeLen)
        result.stops.add(
          SnippetStopOffset(num: num, offset: result.text.runeLen, len: 0)
        )
      i = k
    elif c == '$' and i + 1 < n and
        (body[i + 1] == '_' or body[i + 1] in {'a' .. 'z', 'A' .. 'Z'}):
      # Bare `$VAR` variable (e.g. $TM_FILENAME). We don't expand snippet
      # variables, so skip the name and drop it to empty — matching the
      # unknown-`${VAR}` handling above instead of leaking a literal `$VAR`.
      var k = i + 1
      while k < n and (
        body[k] == '_' or body[k] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9'}
      )
      :
        inc k
      i = k
    else:
      result.text.add(c)
      inc i

proc expandSnippet*(body: string): tuple[text: string, cursorOffset: int] =
  ## Expand an LSP snippet body (insertTextFormat == Snippet) into plain text
  ## plus the rune offset where the cursor should land.
  ##
  ## Minimal support — produces the resulting text and a single primary cursor
  ## position only; there is no multi-tabstop Tab navigation:
  ## - `\$`, `\}`, `\\` are unescaped to literal `$`, `}`, `\`.
  ## - `$0` / `${0}` / `${0:default}` is the final stop (cursor lands here).
  ## - `${n:default}` (n>=1) keeps `default`; `$n` / `${n}` become empty.
  ## - Cursor preference: `$0` if present, else the lowest-numbered stop, else
  ##   the end of the text. A stop nested inside a placeholder default counts.
  ## - Unknown `${VAR}` / `${VAR:default}` and bare `$VAR` drop to `default`
  ##   (or empty); variables are not expanded.
  let p = parseSnippet(body)
  let cursorOffset =
    if p.finalStop >= 0:
      p.finalStop
    elif p.firstStopOffset >= 0:
      p.firstStopOffset
    else:
      p.text.runeLen
  (p.text, cursorOffset)

proc expandSnippetWithStops*(
    body: string
): tuple[text: string, stops: seq[SnippetStopOffset]] =
  ## Expand an LSP snippet body into plain text plus the full tabstop list for
  ## Tab-cycling. Same expansion rules as expandSnippet, with stops normalized
  ## for navigation:
  ## - Sorted by tabstop number ascending; `$0` (the final stop) always last.
  ## - Mirror stops (same number appearing more than once) keep only the first
  ##   occurrence; later ones stay in the text as plain defaults but are not
  ##   cycled to.
  let p = parseSnippet(body)
  var stops: seq[SnippetStopOffset] = @[]
  var seen: seq[int] = @[]
  for s in p.stops:
    if s.num notin seen:
      seen.add(s.num)
      stops.add(s)
  stops.sort(
    proc(a, b: SnippetStopOffset): int =
      # $0 sorts after every numbered stop; ties keep source order (stable).
      let an =
        if a.num == 0:
          high(int)
        else:
          a.num
      let bn =
        if b.num == 0:
          high(int)
        else:
          b.num
      cmp(an, bn)
  )
  (p.text, stops)

proc lspItemToEntry*(
    item: CompletionItem, prefix: string, lspItemIndex: int = -1
): CompletionEntry =
  ## Convert an LSP CompletionItem to a CompletionEntry
  # clangd (and some other servers) pad the label with a leading space to align
  # an absent return type, e.g. " replace(int first, int second)". Strip leading
  # whitespace so the popup is not indented; interior spaces (argument
  # separators) are kept. filterText/sortText prefer the server's own fields and
  # only fall back to this trimmed label.
  let label = item.label.strip(trailing = false)
  let word =
    if item.insertText.isSome and item.insertText.get.len > 0:
      item.insertText.get
    else:
      label

  var docText: Option[string] = none(string)
  if item.documentation.isSome:
    docText = getDocumentationText(item.documentation.get)

  # Parse textEdit if present
  var textEditOpt: Option[TextEdit] = none(TextEdit)
  if item.textEdit.isSome:
    let te = item.textEdit.get
    if te.hasKey("range"):
      # Standard TextEdit
      textEditOpt = some(parseTextEdit(te))
    elif te.hasKey("replace"):
      # InsertReplaceEdit — use replace range
      textEditOpt =
        some(TextEdit(range: parseRange(te["replace"]), newText: te["newText"].getStr))

  # Per LSP, filterText/sortText default to the label (not insertText).
  let filterText =
    if item.filterText.isSome and item.filterText.get.len > 0:
      item.filterText.get
    else:
      label
  let sortText =
    if item.sortText.isSome and item.sortText.get.len > 0: item.sortText.get else: label
  let isSnippet = item.insertTextFormat == some(InsertTextFormat.itfSnippet)

  CompletionEntry(
    word: word,
    label: label,
    matchScore: matchScore(prefix, filterText),
    source: csLsp,
    kind: item.kind,
    detail: item.detail,
    documentation: docText,
    textEdit: textEditOpt,
    additionalTextEdits: item.additionalTextEdits,
    isSnippet: isSnippet,
    filterText: filterText,
    sortText: sortText,
    lspItemIndex: lspItemIndex,
  )

func displayText*(entry: CompletionEntry): string =
  ## Text rendered for the entry in the popup. LSP items carry the user-facing
  ## label here; buffer/path/keyword entries leave it empty and fall back to the
  ## inserted word.
  if entry.label.len > 0: entry.label else: entry.word

proc bufferWordEntries(mgr: CompletionManager, prefix: string): seq[CompletionEntry] =
  ## Buffer/keyword completion entries for `prefix`, sorted by match score
  ## (descending) and then alphabetically. With an empty prefix every collected
  ## word is offered (alphabetically, since all scores tie at 0); otherwise only
  ## words that match are kept.
  result = @[]
  if prefix.len == 0:
    for word in mgr.allWords:
      result.add(
        CompletionEntry(
          word: word,
          matchScore: 0,
          source: csBuffer,
          kind: none(CompletionItemKind),
          detail: none(string),
          documentation: none(string),
        )
      )
  else:
    for word in mgr.allWords:
      let score = matchScore(prefix, word)
      if score > 0:
        result.add(
          CompletionEntry(
            word: word,
            matchScore: score,
            source: csBuffer,
            kind: none(CompletionItemKind),
            detail: none(string),
            documentation: none(string),
          )
        )

  result.sort do(a, b: CompletionEntry) -> int:
    if a.matchScore != b.matchScore:
      b.matchScore - a.matchScore
    else:
      cmp(a.word, b.word)

func prefixMatchTier(entry: CompletionEntry, prefix: string): int =
  ## Ranking tier by how well the entry matches the typed prefix, so prefix
  ## matches outrank loose fuzzy (subsequence) matches regardless of source:
  ##   0 = case-sensitive prefix, 1 = case-insensitive prefix, 2 = fuzzy only.
  ## The text tested is the same one used to admit the entry (LSP filterText,
  ## otherwise the inserted word).
  if prefix.len == 0:
    return 0
  let text = if entry.filterText.len > 0: entry.filterText else: entry.word
  if text.startsWith(prefix):
    return 0
  if text.toLowerAscii.startsWith(prefix.toLowerAscii):
    return 1
  return 2

proc filterAndSortEntries*(
    mgr: CompletionManager, prefix: string
): seq[CompletionEntry] =
  ## Filter words by prefix and sort by match score.
  ## When LSP items are available the two sources are merged: prefix matches rank
  ## above loose fuzzy matches across both, and within the same match tier the
  ## LSP items (server sortText order) come before the buffer/keyword words
  ## (match-score order). With no LSP items the buffer words stand alone.
  result = @[]

  # Path completion mode: re-collect file paths with updated prefix
  if mgr.isPathCompletion:
    let fullPrefix = mgr.pathOriginalPrefix & prefix
    let fileEntries = collectFilePaths(mgr.pathBasePath, fullPrefix)
    for entry in fileEntries:
      let kind =
        if entry.command.endsWith("/"):
          some(CompletionItemKind.cikFolder)
        else:
          some(CompletionItemKind.cikFile)
      result.add(
        CompletionEntry(
          word: entry.command,
          matchScore: entry.matchScore,
          source: csFilePath,
          kind: kind,
          detail: some(entry.description),
          documentation: none(string),
        )
      )
    return

  if mgr.lspItems.len > 0:
    # Collect the LSP items, dropping any whose filterText no longer fuzzy-matches
    # the typed prefix (the server already ranked/filtered them for us).
    for i, item in mgr.lspItems:
      let entry = lspItemToEntry(item, prefix, i)
      if prefix.len == 0 or fuzzyMatch(prefix, entry.filterText):
        result.add(entry)

    # Order the LSP block by the server's sortText (ascending), tie-broken by the
    # word. std/algorithm.sort is a stable merge sort, so equal keys keep the
    # server's original order.
    result.sort do(a, b: CompletionEntry) -> int:
      result = cmp(a.sortText, b.sortText)
      if result == 0:
        result = cmp(a.word, b.word)

    # Merge buffer/keyword words in below the LSP block, in their own score
    # order. The LSP entry for a name is more informative (kind/detail/textEdit),
    # so drop any buffer word an LSP item already offers. Key the dedup on both
    # the LSP item's inserted word and its display label: the label often carries
    # extra detail (e.g. "foo(): int") that would not equal the bare buffer word,
    # so matching either one identifies the same name and avoids a duplicate row.
    var lspShown = initHashSet[string]()
    for e in result:
      lspShown.incl(e.word)
      lspShown.incl(e.displayText)
    for e in mgr.bufferWordEntries(prefix):
      if e.word notin lspShown:
        result.add(e)

    # Promote prefix matches above loose fuzzy matches across BOTH sources, so an
    # exact-prefix keyword (e.g. "if" for "i") is not buried under a fuzzy LSP
    # symbol (e.g. "tokenizer"). The sort is stable, so within a tier the order
    # built above is preserved (LSP sortText first, then buffer score); the
    # server's sortText is thus honored only among same-tier items.
    result.sort do(a, b: CompletionEntry) -> int:
      prefixMatchTier(a, prefix) - prefixMatchTier(b, prefix)
  else:
    # No LSP items: buffer words stand alone (already prefix-before-fuzzy via
    # their match score).
    result = mgr.bufferWordEntries(prefix)

proc updateFilter*(mgr: CompletionManager, prefix: string) =
  ## Update the completion filter with new prefix.
  ## Re-filtering rebuilds the entry list and resets the highlight, so any prior
  ## selection is invalidated: clear hasSelection so a stale highlight cannot be
  ## committed by the next keystroke (e.g. Tab then Backspace then a letter).
  mgr.menu.prefix = prefix
  mgr.menu.entries = mgr.filterAndSortEntries(prefix)
  mgr.menu.selectedIndex = 0
  mgr.menu.scrollOffset = 0
  mgr.menu.hasSelection = false

proc triggerPathCompletion*(
    mgr: CompletionManager, buffer: TextBuffer, cursorLine, cursorCol: int
) =
  ## Trigger file path completion at the current cursor position.
  ## Uses collectFilePaths from command_completion to gather entries.
  let line = buffer.getLine(cursorLine)
  let fullPathPrefix = extractPathPrefixBeforeCursor(line, cursorCol)

  if fullPathPrefix.len == 0:
    mgr.cancelCompletion()
    return

  # Determine base path from buffer's file path or current dir
  let basePath =
    if buffer.filePath.isSome:
      parentDir(buffer.filePath.get)
    else:
      getCurrentDir()

  mgr.isPathCompletion = true
  mgr.pathBasePath = basePath

  # Split the path prefix into directory part and filename part
  # e.g. "./src/foo" -> dirPart = "./src/", filenamePart = "foo"
  let lastSlash = fullPathPrefix.rfind('/')
  let dirPart =
    if lastSlash >= 0:
      fullPathPrefix[0 .. lastSlash] # includes the trailing /
    else:
      ""
  let filenamePart =
    if lastSlash >= 0 and lastSlash + 1 < fullPathPrefix.len:
      fullPathPrefix[lastSlash + 1 ..^ 1]
    else:
      ""

  mgr.pathOriginalPrefix = dirPart
  mgr.menu.prefix = filenamePart
  mgr.menu.triggerLine = cursorLine
  mgr.menu.triggerCol = cursorCol - filenamePart.runeLen
  mgr.menu.hasSelection = false

  # Clear LSP state
  mgr.lspItems = @[]
  mgr.lspRequestId = none(int)

  # Collect and filter entries
  mgr.menu.entries = mgr.filterAndSortEntries(filenamePart)
  mgr.menu.selectedIndex = 0
  mgr.menu.scrollOffset = 0

  if mgr.menu.entries.len > 0:
    mgr.state = csActive
  else:
    mgr.state = csIdle

proc wordCacheSignature(
    buffer: TextBuffer, otherBuffers: seq[TextBuffer]
): seq[(BufferId, int)] =
  ## Identity + content version of every distinct buffer the word scan reads, so
  ## an edit/undo/reload of any of them invalidates the cache. `contentVersion`
  ## (not `changeSeq`) is the key: it is monotonic, so it never collides across
  ## an undo+re-edit or a reload that resets `changeSeq`. The result is deduped
  ## by id and sorted, so a pure window reorder does not force a needless rescan.
  var seen = initHashSet[BufferId]()
  result = @[(buffer.id, buffer.contentVersion)]
  seen.incl(buffer.id)
  for ob in otherBuffers:
    if ob.id notin seen:
      result.add((ob.id, ob.contentVersion))
      seen.incl(ob.id)
  # Sort so a pure window reorder does not force a rescan. Skip it for the common
  # single-buffer case, where there is nothing to reorder.
  if result.len > 1:
    result.sort do(a, b: (BufferId, int)) -> int:
      cmp(a[0].int, b[0].int)

proc refreshBufferWords(
    mgr: CompletionManager,
    buffer: TextBuffer,
    cursorLine, cursorCol: int,
    language: SourceLanguage,
) =
  ## Rebuild `mgr.allWords` (buffer/other-buffer words plus language keywords)
  ## for the cursor position. The buffer scan is cached against the source
  ## buffers' content versions, so an unmodified buffer reuses the prior scan.
  let sig = wordCacheSignature(buffer, mgr.otherBuffers)
  if mgr.wordCacheSig != sig:
    mgr.wordCache = collectWordSet(buffer, mgr.otherBuffers)
    mgr.wordCacheSig = sig

  # Build allWords straight from the cached set (no full-set copy on a cache
  # hit): drop the word under the cursor, then append language keywords that are
  # not already offered as a buffer word.
  let currentWord = extractWordAtPosition(buffer.getLine(cursorLine), cursorCol)
  mgr.allWords = newSeqOfCap[string](mgr.wordCache.len)
  for word in mgr.wordCache:
    if word != currentWord:
      mgr.allWords.add(word)

  var addedKeywords = initHashSet[string]()
  for keyword in getLanguageKeywords(language):
    # The excluded cursor word is re-admitted if it is also a keyword; otherwise
    # skip keywords already present as buffer words. Dedup the keyword list too.
    if keyword != currentWord and keyword in mgr.wordCache:
      continue
    if keyword in addedKeywords:
      continue
    mgr.allWords.add(keyword)
    addedKeywords.incl(keyword)

proc triggerCompletion*(
    mgr: CompletionManager,
    buffer: TextBuffer,
    cursorLine, cursorCol: int,
    language: SourceLanguage = langNone,
) =
  ## Trigger completion at current cursor position
  ## Optionally includes language-specific keywords
  let line = buffer.getLine(cursorLine)
  let prefix = extractPrefixBeforeCursor(line, cursorCol)

  # Collect words (cached against the source buffers' change sequences)
  mgr.refreshBufferWords(buffer, cursorLine, cursorCol, language)

  # Set trigger position
  mgr.menu.triggerLine = cursorLine
  mgr.menu.triggerCol = cursorCol - prefix.runeLen

  # Reset selection state so popup starts with no selection
  mgr.menu.hasSelection = false

  # Filter entries
  mgr.updateFilter(prefix)

  # Only show if we have entries
  if mgr.menu.entries.len > 0:
    mgr.state = csActive
  else:
    mgr.state = csIdle

proc cancelCompletion*(mgr: CompletionManager) =
  ## Cancel/close the completion popup
  mgr.state = csIdle
  mgr.menu.entries = @[]
  mgr.menu.selectedIndex = 0
  mgr.menu.scrollOffset = 0
  mgr.menu.prefix = ""
  mgr.menu.hasSelection = false
  mgr.lspRequestId = none(int)
  mgr.lspItems = @[]
  mgr.isPathCompletion = false
  mgr.pathBasePath = ""
  mgr.pathOriginalPrefix = ""

proc selectNext*(mgr: CompletionManager) =
  ## Select the next completion item
  if mgr.menu.entries.len == 0:
    return

  mgr.menu.selectedIndex = (mgr.menu.selectedIndex + 1) mod mgr.menu.entries.len

  # Adjust scroll offset if needed
  if mgr.menu.selectedIndex >= mgr.menu.scrollOffset + mgr.menu.maxVisible:
    mgr.menu.scrollOffset = mgr.menu.selectedIndex - mgr.menu.maxVisible + 1
  elif mgr.menu.selectedIndex < mgr.menu.scrollOffset:
    mgr.menu.scrollOffset = mgr.menu.selectedIndex

proc selectPrevious*(mgr: CompletionManager) =
  ## Select the previous completion item
  if mgr.menu.entries.len == 0:
    return

  if mgr.menu.selectedIndex == 0:
    mgr.menu.selectedIndex = mgr.menu.entries.len - 1
  else:
    dec mgr.menu.selectedIndex

  # Adjust scroll offset if needed
  if mgr.menu.selectedIndex < mgr.menu.scrollOffset:
    mgr.menu.scrollOffset = mgr.menu.selectedIndex
  elif mgr.menu.selectedIndex >= mgr.menu.scrollOffset + mgr.menu.maxVisible:
    mgr.menu.scrollOffset = mgr.menu.selectedIndex - mgr.menu.maxVisible + 1

proc getSelectedWord*(mgr: CompletionManager): string =
  ## Get the currently selected completion word
  if mgr.menu.entries.len == 0 or mgr.menu.selectedIndex >= mgr.menu.entries.len:
    return ""
  return mgr.menu.entries[mgr.menu.selectedIndex].word

proc getSelectedEntry*(mgr: CompletionManager): Option[CompletionEntry] =
  ## Get the currently selected completion entry
  if mgr.menu.entries.len == 0 or mgr.menu.selectedIndex >= mgr.menu.entries.len:
    return none(CompletionEntry)
  return some(mgr.menu.entries[mgr.menu.selectedIndex])

proc isActive*(mgr: CompletionManager): bool =
  ## Check if completion popup is active (including while waiting for LSP)
  mgr.state in {csActive, csPendingLsp}

proc calculateMaxWordWidth*(entries: seq[CompletionEntry]): int =
  ## Calculate the maximum displayed word width (in terminal columns) in the entries
  result = 0
  for entry in entries:
    let width = entry.displayText.displayWidth
    if width > result:
      result = width

proc calculateMaxDetailWidth*(entries: seq[CompletionEntry]): int =
  ## Calculate the maximum detail width (in terminal columns) in the entries
  result = 0
  for entry in entries:
    if entry.detail.isSome:
      let width = entry.detail.get.displayWidth
      if width > result:
        result = width

proc calculatePopupPosition*(
    cursorX, cursorY: int,
    termWidth, termHeight: int,
    entries: seq[CompletionEntry],
    maxVisible: int = DefaultMaxVisible,
    showBorder: bool = true,
    bottomReserve: int = 2,
): PopupPosition =
  ## Calculate popup position and size based on content
  ## Width is determined by longest word (with min/max constraints)
  ## Prefers below cursor, falls back to above if not enough space
  ## bottomReserve: rows at the bottom the popup must not cross — the
  ## (possibly grown) command-line/status area plus one padding row
  let visibleItems = min(entries.len, maxVisible)
  let borderSize = if showBorder: 2 else: 0
  let popupHeight = visibleItems + borderSize

  # Calculate width based on longest word and detail
  let maxWordWidth = calculateMaxWordWidth(entries)
  let maxDetailWidth = calculateMaxDetailWidth(entries)
  let detailSpace =
    if maxDetailWidth > 0:
      min(maxDetailWidth, MaxDetailWidth) + DetailSeparatorWidth
    else:
      0
  let contentWidth =
    max(MinPopupWidth, min(maxWordWidth + detailSpace + PopupPadding, MaxPopupWidth))
  let popupWidth = contentWidth + borderSize

  var x = cursorX
  var y = cursorY + 1 # Below cursor

  # Adjust X if popup would extend past right edge
  if x + popupWidth > termWidth:
    x = max(0, termWidth - popupWidth)

  # Check if popup fits below cursor
  if y + popupHeight > termHeight - bottomReserve:
    # Try above cursor
    y = cursorY - popupHeight
    if y < 0:
      y = 0

  PopupPosition(x: x, y: y, width: popupWidth, height: popupHeight)

proc renderCompletionPopup*(
    termBuffer: var Buffer,
    menu: CompletionMenu,
    pos: PopupPosition,
    showBorder: bool = true,
) =
  ## Render completion popup to terminal buffer
  if menu.entries.len == 0:
    return

  let visibleItems = min(menu.entries.len, menu.maxVisible)

  # Calculate content area (inside border)
  let contentX =
    if showBorder:
      pos.x + 1
    else:
      pos.x
  let contentY =
    if showBorder:
      pos.y + 1
    else:
      pos.y
  let contentWidth =
    if showBorder:
      pos.width - 2
    else:
      pos.width
  let contentHeight = visibleItems

  if showBorder:
    # Draw border if enabled
    drawBorder(termBuffer, pos.x, pos.y, pos.width, pos.height, popupBorderStyle())

  # Content (always rendered)
  let maxWordW = calculateMaxWordWidth(menu.entries)
  let contentLimit = contentX + contentWidth
  for i in 0 ..< contentHeight:
    let y = contentY + i
    if y >= 0 and y < termBuffer.area.height:
      let entryIdx = menu.scrollOffset + i
      if entryIdx < menu.entries.len:
        let entry = menu.entries[entryIdx]
        # Only highlight if selection mode is active
        let isSelected = menu.hasSelection and entryIdx == menu.selectedIndex
        let style =
          if isSelected:
            popupSelectedStyle()
          else:
            popupNormalStyle()

        # Truncate word by display width (CJK/wide-char safe, contentWidth <= 0 safe)
        var displayWord = entry.displayText
        if displayWord.displayWidth > contentWidth:
          displayWord = truncateToWidthWithSuffix(displayWord, contentWidth, "…")

        # Draw word
        var x =
          drawClippedRunes(termBuffer, contentX, y, contentLimit, displayWord, style)

        # Draw detail after the word (if available)
        let detailStyle =
          if isSelected:
            popupSelectedDetailStyle()
          else:
            popupDetailStyle()
        if entry.detail.isSome and entry.detail.get.len > 0:
          # Fill gap between word and detail
          let detailStartX = contentX + maxWordW + DetailSeparatorWidth
          x = fillCells(termBuffer, x, y, min(detailStartX, contentLimit), style)

          # Render detail by display width (CJK/wide-char safe, availableDetailWidth <= 0 safe)
          let availableDetailWidth = contentLimit - x
          var displayDetail = entry.detail.get
          if displayDetail.displayWidth > availableDetailWidth:
            displayDetail =
              truncateToWidthWithSuffix(displayDetail, availableDetailWidth, "…")
          x =
            drawClippedRunes(termBuffer, x, y, contentLimit, displayDetail, detailStyle)

        # Fill remaining space with background
        x = fillCells(termBuffer, x, y, contentLimit, style)

proc updateDocPanel*(mgr: CompletionManager) =
  ## Update the documentation panel based on the selected entry
  if not mgr.menu.hasSelection or mgr.menu.entries.len == 0:
    mgr.docPanel.visible = false
    return

  let idx = mgr.menu.selectedIndex
  if idx >= mgr.menu.entries.len:
    mgr.docPanel.visible = false
    return

  let entry = mgr.menu.entries[idx]
  if entry.documentation.isNone or entry.documentation.get.len == 0:
    mgr.docPanel.visible = false
    return

  mgr.docPanel.lines = entry.documentation.get.splitLines()
  mgr.docPanel.scrollOffset = 0
  mgr.docPanel.visible = true

proc calculateDocPanelPosition*(
    completionPos: PopupPosition,
    termWidth, termHeight: int,
    docPanel: DocPanel,
    bottomReserve: int = 2,
    selectedRowOffset: int = 0,
): PopupPosition =
  ## Calculate documentation panel position relative to completion popup
  ## Prefers right side, falls back to left
  ## bottomReserve: rows at the bottom the panel must not cross — the
  ## (possibly grown) command-line/status area plus one padding row
  ## selectedRowOffset: rows from the completion popup's top down to the
  ## highlighted candidate's row (border + selectedIndex - scrollOffset), so the
  ## panel tracks the selection instead of pinning to the popup's first row.

  # Calculate content dimensions (max line display width, CJK-aware)
  var maxLineLen = 0
  for line in docPanel.lines:
    maxLineLen = max(maxLineLen, line.displayWidth)

  let contentWidth =
    min(max(maxLineLen + PopupPadding, DocPanelMinWidth), DocPanelMaxWidth)
  let popupWidth = contentWidth + 2 # +2 for border
  let visibleLines = min(docPanel.lines.len, DocPanelMaxVisibleLines)
  let popupHeight = visibleLines + 2 # +2 for border

  # Try right side of completion popup
  let rightX = completionPos.x + completionPos.width
  var x =
    if rightX + popupWidth <= termWidth:
      rightX
    else:
      # Try left side
      let leftX = completionPos.x - popupWidth
      if leftX >= 0:
        leftX
      else:
        # Fall back to right, even if it clips
        max(0, termWidth - popupWidth)

  # Align the panel's top with the highlighted candidate's row. Clamp upward if
  # the panel would cross the bottom reserve, and never start above the popup.
  var y = max(completionPos.y, completionPos.y + selectedRowOffset)
  if y + popupHeight > termHeight - bottomReserve:
    y = max(0, termHeight - bottomReserve - popupHeight)

  PopupPosition(x: x, y: y, width: popupWidth, height: popupHeight)

proc renderDocPanel*(termBuffer: var Buffer, docPanel: DocPanel, pos: PopupPosition) =
  ## Render documentation panel to terminal buffer
  if not docPanel.visible or docPanel.lines.len == 0:
    return

  let contentX = pos.x + 1
  let contentY = pos.y + 1
  let contentWidth = pos.width - 2
  let visibleLines = min(docPanel.lines.len, DocPanelMaxVisibleLines)
  let canScrollUp = docPanel.scrollOffset > 0
  let canScrollDown = docPanel.scrollOffset + visibleLines < docPanel.lines.len
  let rightX = pos.x + pos.width - 1
  let contentLimit = contentX + contentWidth

  # Border box; scroll indicators replace the right-hand corners when scrollable
  drawBorder(termBuffer, pos.x, pos.y, pos.width, pos.height, docPanelBorderStyle())
  if canScrollUp and pos.y >= 0 and pos.y < termBuffer.area.height and rightX >= 0 and
      rightX < termBuffer.area.width:
    termBuffer[rightX, pos.y] = cell("▲", docPanelScrollStyle())

  # Content lines
  for i in 0 ..< visibleLines:
    let lineY = contentY + i
    if lineY < 0 or lineY >= termBuffer.area.height:
      continue

    let lineIdx = docPanel.scrollOffset + i
    let lineText =
      if lineIdx < docPanel.lines.len:
        docPanel.lines[lineIdx]
      else:
        ""

    let afterText = drawClippedRunes(
      termBuffer, contentX, lineY, contentLimit, lineText, docPanelNormalStyle()
    )
    discard fillCells(termBuffer, afterText, lineY, contentLimit, docPanelNormalStyle())

  # Bottom scroll indicator (the border itself was drawn above)
  let bottomY = contentY + visibleLines
  if canScrollDown and bottomY >= 0 and bottomY < termBuffer.area.height and rightX >= 0 and
      rightX < termBuffer.area.width:
    termBuffer[rightX, bottomY] = cell("▼", docPanelScrollStyle())

# LSP completion support

proc setLspRequestPending*(mgr: CompletionManager, requestId: int) =
  ## Set the pending LSP request ID
  mgr.lspRequestId = some(requestId)
  mgr.state = csPendingLsp

proc isPendingLsp*(mgr: CompletionManager): bool =
  ## Check if waiting for LSP response
  mgr.state == csPendingLsp and mgr.lspRequestId.isSome

proc getLspRequestId*(mgr: CompletionManager): Option[int] =
  ## Get the pending LSP request ID
  mgr.lspRequestId

proc shouldSkipLspRequest*(mgr: CompletionManager, newPrefix: string): bool =
  ## Check if LSP request can be skipped (debounce + client-side filtering)
  ## Returns true if we should skip the request and filter client-side instead
  let now = getMonoTime()
  let elapsed = now - mgr.lastLspRequestTime

  # If last response was complete and new prefix extends the old one,
  # we can filter client-side without a new request
  if not mgr.isIncomplete and mgr.lspItems.len > 0 and mgr.lastLspPrefix.len > 0 and
      newPrefix.startsWith(mgr.lastLspPrefix):
    return true

  # Debounce: skip if too soon since last request
  if elapsed < initDuration(milliseconds = LspDebounceMs):
    return true

  return false

proc setLspItems*(
    mgr: CompletionManager, items: seq[CompletionItem], isIncomplete: bool = false
) =
  ## Set LSP completion items and update the menu
  mgr.lspItems = items
  mgr.isIncomplete = isIncomplete
  mgr.lspRequestId = none(int)

  # Update entries with the new LSP items
  mgr.menu.entries = mgr.filterAndSortEntries(mgr.menu.prefix)
  mgr.menu.selectedIndex = 0
  mgr.menu.scrollOffset = 0
  mgr.menu.hasSelection = false

  if mgr.menu.entries.len > 0:
    mgr.state = csActive
  else:
    mgr.state = csIdle

proc needsResolve*(mgr: CompletionManager): bool =
  ## Check if the selected item needs resolve (missing detail or documentation)
  if not mgr.menu.hasSelection or mgr.menu.entries.len == 0:
    return false
  let idx = mgr.menu.selectedIndex
  if idx >= mgr.menu.entries.len:
    return false
  let entry = mgr.menu.entries[idx]
  if entry.source != csLsp:
    return false
  return entry.detail.isNone or entry.documentation.isNone

proc getSelectedRawJson*(mgr: CompletionManager): Option[JsonNode] =
  ## Get the JSON for the selected LSP item to echo back on a resolve request.
  ## The original list is no longer kept as JsonNode (it is parsed straight into
  ## typed CompletionItems), so the selected item is re-serialized on demand with
  ## jsony. The opaque `data` resolve token is an Option[JsonNode] and round-trips
  ## verbatim, which is the field servers rely on for completionItem/resolve.
  if not mgr.menu.hasSelection or mgr.menu.entries.len == 0:
    return none(JsonNode)
  let idx = mgr.menu.selectedIndex
  if idx >= mgr.menu.entries.len:
    return none(JsonNode)
  let entry = mgr.menu.entries[idx]
  if entry.source != csLsp:
    return none(JsonNode)

  # Use the stored index for direct lookup (avoids overload ambiguity)
  let lspIdx = entry.lspItemIndex
  if lspIdx >= 0 and lspIdx < mgr.lspItems.len:
    return some(parseJson(mgr.lspItems[lspIdx].toJson))

  return none(JsonNode)

proc updateResolvedEntry*(mgr: CompletionManager, resolved: CompletionItem) =
  ## Update the selected entry with resolved data from completionItem/resolve
  if mgr.menu.entries.len == 0:
    return
  let idx = mgr.resolvedIndex
  if idx < 0 or idx >= mgr.menu.entries.len:
    return

  # The entries may have been rebuilt (refilter / new LSP response) between the
  # resolve request and its response. Drop the result unless the entry at the
  # captured index is still the same item we asked to resolve.
  let resolvedWord =
    if resolved.insertText.isSome and resolved.insertText.get.len > 0:
      resolved.insertText.get
    else:
      # Match how lspItemToEntry builds `word`: the label is trimmed of the
      # leading padding some servers (clangd) add, so the resolve response's
      # raw label must be trimmed the same way or this check always fails
      # for those items and the resolved data is silently dropped.
      resolved.label.strip(trailing = false)
  if mgr.menu.entries[idx].word != resolvedWord:
    return

  if resolved.detail.isSome:
    mgr.menu.entries[idx].detail = resolved.detail
  if resolved.documentation.isSome:
    mgr.menu.entries[idx].documentation =
      getDocumentationText(resolved.documentation.get)
  if resolved.additionalTextEdits.isSome:
    mgr.menu.entries[idx].additionalTextEdits = resolved.additionalTextEdits
  if resolved.textEdit.isSome:
    let te = resolved.textEdit.get
    if te.hasKey("range"):
      mgr.menu.entries[idx].textEdit = some(parseTextEdit(te))
    elif te.hasKey("replace"):
      mgr.menu.entries[idx].textEdit =
        some(TextEdit(range: parseRange(te["replace"]), newText: te["newText"].getStr))

proc triggerLspCompletion*(
    mgr: CompletionManager,
    buffer: TextBuffer,
    cursorLine, cursorCol: int,
    language: SourceLanguage = langNone,
) =
  ## Initialize completion state for LSP request
  ## Call this before starting the LSP request
  let line = buffer.getLine(cursorLine)
  let prefix = extractPrefixBeforeCursor(line, cursorCol)

  # Collect words as fallback (cached against the source buffers' change seqs)
  mgr.refreshBufferWords(buffer, cursorLine, cursorCol, language)

  # Set trigger position
  mgr.menu.triggerLine = cursorLine
  mgr.menu.triggerCol = cursorCol - prefix.runeLen
  mgr.menu.prefix = prefix
  mgr.menu.hasSelection = false

  # Filter entries (will only show buffer words until LSP responds)
  mgr.menu.entries = mgr.filterAndSortEntries(prefix)
  mgr.menu.selectedIndex = 0
  mgr.menu.scrollOffset = 0

  # Show popup with buffer words while waiting for LSP
  if mgr.menu.entries.len > 0:
    mgr.state = csActive

proc completionItemKindToString*(kind: CompletionItemKind): string =
  ## Convert CompletionItemKind to display string
  case kind
  of cikText: "Text"
  of cikMethod: "Method"
  of cikFunction: "Func"
  of cikConstructor: "Constr"
  of cikField: "Field"
  of cikVariable: "Var"
  of cikClass: "Class"
  of cikInterface: "Iface"
  of cikModule: "Module"
  of cikProperty: "Prop"
  of cikUnit: "Unit"
  of cikValue: "Value"
  of cikEnum: "Enum"
  of cikKeyword: "Keyw"
  of cikSnippet: "Snip"
  of cikColor: "Color"
  of cikFile: "File"
  of cikReference: "Ref"
  of cikFolder: "Folder"
  of cikEnumMember: "EnumM"
  of cikConstant: "Const"
  of cikStruct: "Struct"
  of cikEvent: "Event"
  of cikOperator: "Oper"
  of cikTypeParameter: "TypeP"

proc completionItemKindToIcon*(kind: CompletionItemKind): string =
  ## Convert CompletionItemKind to icon character
  case kind
  of cikText: "󰊄"
  of cikMethod: "󰊕"
  of cikFunction: "󰊕"
  of cikConstructor: ""
  of cikField: ""
  of cikVariable: "󰀫"
  of cikClass: ""
  of cikInterface: ""
  of cikModule: ""
  of cikProperty: ""
  of cikUnit: ""
  of cikValue: ""
  of cikEnum: ""
  of cikKeyword: ""
  of cikSnippet: ""
  of cikColor: ""
  of cikFile: ""
  of cikReference: ""
  of cikFolder: ""
  of cikEnumMember: ""
  of cikConstant: ""
  of cikStruct: ""
  of cikEvent: ""
  of cikOperator: ""
  of cikTypeParameter: ""
