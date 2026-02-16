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

import std/[algorithm, sequtils, strutils, unicode, sets, options, json]

import pkg/celina

import buffer, word_dictionary
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

  CompletionEntry* = object ## A single completion entry
    word*: string ## The word to insert
    matchScore*: int ## Score for sorting (higher = better match)
    source*: CompletionSource ## Where this entry came from
    kind*: Option[CompletionItemKind] ## LSP completion kind (function, variable, etc.)
    detail*: Option[string] ## LSP detail (e.g., type signature)
    documentation*: Option[string] ## LSP documentation

  CompletionMenu* = object ## Completion popup state
    entries*: seq[CompletionEntry]
    selectedIndex*: int ## Currently selected item (0-based)
    scrollOffset*: int ## For scrolling long lists
    maxVisible*: int ## Max items to show (default: 10)
    prefix*: string ## Current filter prefix
    triggerLine*: int ## Line where completion was triggered
    triggerCol*: int ## Column where completion was triggered
    hasSelection*: bool ## True after first Tab press (enables auto-insert)

  CompletionManager* = ref object ## Manages completion state and operations
    state*: CompletionState
    menu*: CompletionMenu
    allWords*: seq[string] ## All collected words from buffer
    wordDictionary*: WordDictionary
      ## Dictionary for language keywords and usage tracking
    currentLanguage*: SourceLanguage ## Current buffer's language
    lspRequestId*: Option[int] ## Pending LSP request ID
    lspItems*: seq[CompletionItem] ## Raw LSP completion items
    otherBuffers*: seq[TextBuffer]
      ## Other FileEditMode buffers for multi-buffer completion

const
  DefaultMaxVisible* = 10
  MinWordLength* = 2 ## Minimum word length to collect
  MinPrefixLength* = 1 ## Minimum prefix length to trigger (manual)
  AutoTriggerPrefixLength* = 1 ## Minimum prefix length for auto-trigger
  MinPopupWidth* = 15 ## Minimum popup width
  MaxPopupWidth* = 50 ## Maximum popup width
  PopupPadding* = 2 ## Padding inside popup (left + right)

# Word collection from buffer

proc isDigitRune(r: Rune): bool =
  ## Check if a rune is an ASCII digit (0-9)
  let code = int(r)
  code >= ord('0') and code <= ord('9')

proc isWordChar(r: Rune): bool =
  ## Check if a rune is part of a word (alphanumeric or underscore)
  r.isAlpha or r.isDigitRune or r == '_'.Rune

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

proc collectBufferWords*(
    buffer: TextBuffer, excludePos: BufferPosition, otherBuffers: seq[TextBuffer] = @[]
): seq[string] =
  ## Collect all unique words from the current buffer and other open buffers.
  ## Excludes the word at the current cursor position.
  var wordSet = initHashSet[string]()

  for lineIdx in 0 ..< buffer.len:
    let line = buffer.getLine(lineIdx)
    let words = extractWords(line)

    for word in words:
      wordSet.incl(word)

  # Collect words from other open FileEditMode buffers
  for otherBuf in otherBuffers:
    if otherBuf == buffer:
      continue
    for lineIdx in 0 ..< otherBuf.len:
      let line = otherBuf.getLine(lineIdx)
      let words = extractWords(line)
      for word in words:
        wordSet.incl(word)

  # Get the word at cursor position to exclude it
  let currentLine = buffer.getLine(excludePos.line)
  let currentWord = extractWordAtPosition(currentLine, excludePos.column)
  if currentWord.len > 0:
    wordSet.excl(currentWord)

  result = wordSet.toSeq
  result.sort()

# Fuzzy matching

proc fuzzyMatch*(pattern, text: string): bool =
  ## Simple fuzzy match - check if pattern chars appear in order in text
  if pattern.len == 0:
    return true
  if text.len == 0:
    return false

  let lowerPattern = pattern.toLowerAscii
  let lowerText = text.toLowerAscii

  var patternIdx = 0
  for c in lowerText:
    if patternIdx < lowerPattern.len and c == lowerPattern[patternIdx]:
      inc patternIdx
  return patternIdx >= lowerPattern.len

proc matchScore*(pattern, text: string): int =
  ## Calculate match score (higher = better)
  ## Prefers: exact prefix match > fuzzy match > length similarity
  if pattern.len == 0:
    return 0

  let lowerPattern = pattern.toLowerAscii
  let lowerText = text.toLowerAscii

  # Exact prefix match gets highest score
  if lowerText.startsWith(lowerPattern):
    result = 1000 + (100 - min(text.len, 100)) # Prefer shorter words
    # Bonus for case-sensitive match
    if text.startsWith(pattern):
      result += 50
  else:
    # Fuzzy match score based on character positions
    var score = 0
    var patternIdx = 0
    var lastMatchPos = -1

    for i, c in lowerText:
      if patternIdx < lowerPattern.len and c == lowerPattern[patternIdx]:
        # Bonus for consecutive matches
        if lastMatchPos == i - 1:
          score += 20
        else:
          score += 10
        lastMatchPos = i
        inc patternIdx

    if patternIdx >= lowerPattern.len:
      result = score
    else:
      result = 0 # No match

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
    wordDictionary: WordDictionary(),
    currentLanguage: langNone,
    lspRequestId: none(int),
    lspItems: @[],
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

proc lspItemToEntry*(item: CompletionItem, prefix: string): CompletionEntry =
  ## Convert an LSP CompletionItem to a CompletionEntry
  let word =
    if item.insertText.isSome and item.insertText.get.len > 0:
      item.insertText.get
    else:
      item.label

  var docText: Option[string] = none(string)
  if item.documentation.isSome:
    docText = getDocumentationText(item.documentation.get)

  CompletionEntry(
    word: word,
    matchScore: matchScore(prefix, word),
    source: csLsp,
    kind: item.kind,
    detail: item.detail,
    documentation: docText,
  )

proc filterAndSortEntries*(
    mgr: CompletionManager, prefix: string
): seq[CompletionEntry] =
  ## Filter words by prefix and sort by match score
  ## When LSP items are available, show only LSP items (switch from buffer)
  ## When no LSP items, show buffer words as fallback
  result = @[]

  # If LSP items are available, use only LSP items
  if mgr.lspItems.len > 0:
    for item in mgr.lspItems:
      let entry = lspItemToEntry(item, prefix)
      if prefix.len == 0 or entry.matchScore > 0:
        result.add(entry)

    # Sort LSP items by score (descending)
    result.sort do(a, b: CompletionEntry) -> int:
      b.matchScore - a.matchScore
  else:
    # Fall back to buffer words
    if prefix.len == 0:
      # Show all words sorted alphabetically
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
      # Filter and score buffer words
      for word in mgr.allWords:
        if fuzzyMatch(prefix, word):
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

    # Sort buffer words by score (descending)
    result.sort do(a, b: CompletionEntry) -> int:
      b.matchScore - a.matchScore

proc updateFilter*(mgr: CompletionManager, prefix: string) =
  ## Update the completion filter with new prefix
  mgr.menu.prefix = prefix
  mgr.menu.entries = mgr.filterAndSortEntries(prefix)
  mgr.menu.selectedIndex = 0
  mgr.menu.scrollOffset = 0

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

  # Clear any previous LSP items (start fresh with buffer completions)
  mgr.lspItems = @[]
  mgr.lspRequestId = none(int)

  # Collect words from current buffer and other open buffers
  mgr.allWords = collectBufferWords(
    buffer, BufferPosition(line: cursorLine, column: cursorCol), mgr.otherBuffers
  )

  # Update word dictionary with buffer content and language keywords
  mgr.currentLanguage = language
  mgr.wordDictionary.clear()
  mgr.wordDictionary.update(buffer.getTextString(), prefix, language)

  # Add language keywords to allWords if not already present
  var wordSet = mgr.allWords.toHashSet
  for keyword in getLanguageKeywords(language):
    if keyword notin wordSet:
      mgr.allWords.add(keyword)
      wordSet.incl(keyword)

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

proc isActive*(mgr: CompletionManager): bool =
  ## Check if completion popup is active
  mgr.state == csActive

# Popup rendering

type PopupPosition* = object
  x*, y*: int
  width*, height*: int

let
  popupNormalStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.White),
    bg: ColorValue(kind: Indexed, indexed: Color.Black),
    modifiers: {},
  )
  popupSelectedStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.Black),
    bg: ColorValue(kind: Indexed, indexed: Color.Cyan),
    modifiers: {},
  )
  popupBorderStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.BrightBlack),
    bg: ColorValue(kind: Indexed, indexed: Color.Black),
    modifiers: {},
  )

proc calculateMaxWordWidth*(entries: seq[CompletionEntry]): int =
  ## Calculate the maximum word width in the entries
  result = 0
  for entry in entries:
    let width = entry.word.runeLen
    if width > result:
      result = width

proc calculatePopupPosition*(
    cursorX, cursorY: int,
    termWidth, termHeight: int,
    entries: seq[CompletionEntry],
    maxVisible: int = DefaultMaxVisible,
    showBorder: bool = true,
): PopupPosition =
  ## Calculate popup position and size based on content
  ## Width is determined by longest word (with min/max constraints)
  ## Prefers below cursor, falls back to above if not enough space
  let visibleItems = min(entries.len, maxVisible)
  let borderSize = if showBorder: 2 else: 0
  let popupHeight = visibleItems + borderSize

  # Calculate width based on longest word
  let maxWordWidth = calculateMaxWordWidth(entries)
  let contentWidth = max(MinPopupWidth, min(maxWordWidth + PopupPadding, MaxPopupWidth))
  let popupWidth = contentWidth + borderSize

  var x = cursorX
  var y = cursorY + 1 # Below cursor

  # Adjust X if popup would extend past right edge
  if x + popupWidth > termWidth:
    x = max(0, termWidth - popupWidth)

  # Check if popup fits below cursor
  if y + popupHeight > termHeight - 2: # -2 for status/command lines
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

  # Draw border if enabled
  if showBorder:
    # Top border
    if pos.y >= 0 and pos.y < termBuffer.area.height:
      if pos.x >= 0 and pos.x < termBuffer.area.width:
        termBuffer[pos.x, pos.y] = cell("┌", popupBorderStyle)
      for x in pos.x + 1 ..< min(pos.x + pos.width - 1, termBuffer.area.width):
        if x >= 0:
          termBuffer[x, pos.y] = cell("─", popupBorderStyle)
      if pos.x + pos.width - 1 >= 0 and pos.x + pos.width - 1 < termBuffer.area.width:
        termBuffer[pos.x + pos.width - 1, pos.y] = cell("┐", popupBorderStyle)

    # Side borders
    for i in 0 ..< contentHeight:
      let y = contentY + i
      if y >= 0 and y < termBuffer.area.height:
        # Left border
        if pos.x >= 0 and pos.x < termBuffer.area.width:
          termBuffer[pos.x, y] = cell("│", popupBorderStyle)
        # Right border
        if pos.x + pos.width - 1 >= 0 and pos.x + pos.width - 1 < termBuffer.area.width:
          termBuffer[pos.x + pos.width - 1, y] = cell("│", popupBorderStyle)

    # Bottom border
    let bottomY = contentY + contentHeight
    if bottomY >= 0 and bottomY < termBuffer.area.height:
      if pos.x >= 0 and pos.x < termBuffer.area.width:
        termBuffer[pos.x, bottomY] = cell("└", popupBorderStyle)
      for x in pos.x + 1 ..< min(pos.x + pos.width - 1, termBuffer.area.width):
        if x >= 0:
          termBuffer[x, bottomY] = cell("─", popupBorderStyle)
      if pos.x + pos.width - 1 >= 0 and pos.x + pos.width - 1 < termBuffer.area.width:
        termBuffer[pos.x + pos.width - 1, bottomY] = cell("┘", popupBorderStyle)

  # Content (always rendered)
  for i in 0 ..< contentHeight:
    let y = contentY + i
    if y >= 0 and y < termBuffer.area.height:
      let entryIdx = menu.scrollOffset + i
      if entryIdx < menu.entries.len:
        let entry = menu.entries[entryIdx]
        # Only highlight if selection mode is active
        let isSelected = menu.hasSelection and entryIdx == menu.selectedIndex
        let style = if isSelected: popupSelectedStyle else: popupNormalStyle

        # Truncate word to fit
        var displayWord = entry.word
        if displayWord.len > contentWidth:
          displayWord = displayWord[0 ..< contentWidth - 1] & "…"

        # Draw word
        var x = contentX
        for r in displayWord.runes:
          if x < contentX + contentWidth and x < termBuffer.area.width:
            termBuffer[x, y] = cell($r, style)
            x += runeWidth(r)

        # Fill remaining space with background
        while x < contentX + contentWidth and x < termBuffer.area.width:
          termBuffer[x, y] = cell(" ", style)
          inc x

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

proc setLspItems*(mgr: CompletionManager, items: seq[CompletionItem]) =
  ## Set LSP completion items and update the menu
  mgr.lspItems = items
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

  # Collect words from current buffer and other open buffers as fallback
  mgr.allWords = collectBufferWords(
    buffer, BufferPosition(line: cursorLine, column: cursorCol), mgr.otherBuffers
  )

  # Update word dictionary with buffer content and language keywords
  mgr.currentLanguage = language
  mgr.wordDictionary.clear()
  mgr.wordDictionary.update(buffer.getTextString(), prefix, language)

  # Add language keywords to allWords if not already present
  var wordSet = mgr.allWords.toHashSet
  for keyword in getLanguageKeywords(language):
    if keyword notin wordSet:
      mgr.allWords.add(keyword)
      wordSet.incl(keyword)

  # Clear previous LSP items
  mgr.lspItems = @[]

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
