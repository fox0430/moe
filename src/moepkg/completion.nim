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

import pkg/celina

import buffer, word_dictionary, command_completion, fuzzy_match, unicode_utils
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
    matchScore*: int ## Score for sorting (higher = better match)
    source*: CompletionSource ## Where this entry came from
    kind*: Option[CompletionItemKind] ## LSP completion kind (function, variable, etc.)
    detail*: Option[string] ## LSP detail (e.g., type signature)
    documentation*: Option[string] ## LSP documentation
    textEdit*: Option[TextEdit] ## LSP textEdit for range-based replacement
    additionalTextEdits*: Option[seq[TextEdit]] ## Additional edits to apply
    lspItemIndex*: int ## Index into lspItems/lspRawJsonItems (-1 = not from LSP)

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
    wordDictionary*: WordDictionary
      ## Dictionary for language keywords and usage tracking
    currentLanguage*: SourceLanguage ## Current buffer's language
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
    lspRawJsonItems*: seq[JsonNode] ## Raw JSON for resolve requests
    resolveRequestId*: Option[int] ## Pending resolve request ID
    resolvedIndex*: int ## Index of item being resolved

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

# Forward declaration
proc cancelCompletion*(mgr: CompletionManager)

# Word collection from buffer

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

proc lspItemToEntry*(
    item: CompletionItem, prefix: string, lspItemIndex: int = -1
): CompletionEntry =
  ## Convert an LSP CompletionItem to a CompletionEntry
  let word =
    if item.insertText.isSome and item.insertText.get.len > 0:
      item.insertText.get
    else:
      item.label

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

  CompletionEntry(
    word: word,
    matchScore: matchScore(prefix, word),
    source: csLsp,
    kind: item.kind,
    detail: item.detail,
    documentation: docText,
    textEdit: textEditOpt,
    additionalTextEdits: item.additionalTextEdits,
    lspItemIndex: lspItemIndex,
  )

proc filterAndSortEntries*(
    mgr: CompletionManager, prefix: string
): seq[CompletionEntry] =
  ## Filter words by prefix and sort by match score
  ## When LSP items are available, show only LSP items (switch from buffer)
  ## When no LSP items, show buffer words as fallback
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

  # If LSP items are available, use only LSP items
  if mgr.lspItems.len > 0:
    for i, item in mgr.lspItems:
      let entry = lspItemToEntry(item, prefix, i)
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
  popupDetailStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.BrightBlack),
    bg: ColorValue(kind: Indexed, indexed: Color.Black),
    modifiers: {},
  )
  popupSelectedDetailStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.BrightBlack),
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

proc calculateMaxDetailWidth*(entries: seq[CompletionEntry]): int =
  ## Calculate the maximum detail width in the entries
  result = 0
  for entry in entries:
    if entry.detail.isSome:
      let width = entry.detail.get.runeLen
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
  let maxWordW = calculateMaxWordWidth(menu.entries)
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
        if displayWord.runeLen > contentWidth:
          displayWord = $displayWord.toRunes[0 ..< contentWidth - 1] & "…"

        # Draw word
        var x = contentX
        for r in displayWord.runes:
          if x < contentX + contentWidth and x < termBuffer.area.width:
            x += setRuneCell(termBuffer, x, y, r, style)

        # Draw detail after the word (if available)
        let detailStyle = if isSelected: popupSelectedDetailStyle else: popupDetailStyle
        if entry.detail.isSome and entry.detail.get.len > 0:
          # Fill gap between word and detail
          let detailStartX = contentX + maxWordW + DetailSeparatorWidth
          while x < detailStartX and x < contentX + contentWidth and
              x < termBuffer.area.width:
            termBuffer[x, y] = cell(" ", style)
            inc x

          # Render detail text
          var displayDetail = entry.detail.get
          let availableDetailWidth = contentX + contentWidth - x
          if displayDetail.runeLen > availableDetailWidth:
            if availableDetailWidth > 1:
              displayDetail = displayDetail[0 ..< availableDetailWidth - 1] & "…"
            else:
              displayDetail = ""

          for r in displayDetail.runes:
            if x < contentX + contentWidth and x < termBuffer.area.width:
              x += setRuneCell(termBuffer, x, y, r, detailStyle)

        # Fill remaining space with background
        while x < contentX + contentWidth and x < termBuffer.area.width:
          termBuffer[x, y] = cell(" ", style)
          inc x

# Documentation panel

let
  docPanelNormalStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.White),
    bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 50, g: 50, b: 50)),
    modifiers: {},
  )
  docPanelBorderStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.BrightBlack),
    bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 50, g: 50, b: 50)),
    modifiers: {},
  )
  docPanelScrollStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.Yellow),
    bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 50, g: 50, b: 50)),
    modifiers: {},
  )

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
): PopupPosition =
  ## Calculate documentation panel position relative to completion popup
  ## Prefers right side, falls back to left
  ## bottomReserve: rows at the bottom the panel must not cross — the
  ## (possibly grown) command-line/status area plus one padding row

  # Calculate content dimensions
  var maxLineLen = 0
  for line in docPanel.lines:
    maxLineLen = max(maxLineLen, line.runeLen)

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

  # Align vertically with completion popup
  var y = completionPos.y
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

  # Top border
  if pos.y >= 0 and pos.y < termBuffer.area.height:
    if pos.x >= 0 and pos.x < termBuffer.area.width:
      termBuffer[pos.x, pos.y] = cell("┌", docPanelBorderStyle)
    for x in pos.x + 1 ..< min(pos.x + pos.width - 1, termBuffer.area.width):
      if x >= 0:
        termBuffer[x, pos.y] = cell("─", docPanelBorderStyle)
    if pos.x + pos.width - 1 >= 0 and pos.x + pos.width - 1 < termBuffer.area.width:
      if canScrollUp:
        termBuffer[pos.x + pos.width - 1, pos.y] = cell("▲", docPanelScrollStyle)
      else:
        termBuffer[pos.x + pos.width - 1, pos.y] = cell("┐", docPanelBorderStyle)

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

    # Left border
    if pos.x >= 0 and pos.x < termBuffer.area.width:
      termBuffer[pos.x, lineY] = cell("│", docPanelBorderStyle)

    # Content
    var x = contentX
    for r in lineText.runes:
      if x >= contentX + contentWidth or x >= termBuffer.area.width:
        break
      if x >= 0:
        x += setRuneCell(termBuffer, x, lineY, r, docPanelNormalStyle)
      else:
        x += runeWidth(r)

    # Fill remaining space
    while x < contentX + contentWidth and x < termBuffer.area.width:
      if x >= 0:
        termBuffer[x, lineY] = cell(" ", docPanelNormalStyle)
      inc x

    # Right border
    if pos.x + pos.width - 1 >= 0 and pos.x + pos.width - 1 < termBuffer.area.width:
      termBuffer[pos.x + pos.width - 1, lineY] = cell("│", docPanelBorderStyle)

  # Bottom border
  let bottomY = contentY + visibleLines
  if bottomY >= 0 and bottomY < termBuffer.area.height:
    if pos.x >= 0 and pos.x < termBuffer.area.width:
      termBuffer[pos.x, bottomY] = cell("└", docPanelBorderStyle)
    for x in pos.x + 1 ..< min(pos.x + pos.width - 1, termBuffer.area.width):
      if x >= 0:
        termBuffer[x, bottomY] = cell("─", docPanelBorderStyle)
    if pos.x + pos.width - 1 >= 0 and pos.x + pos.width - 1 < termBuffer.area.width:
      if canScrollDown:
        termBuffer[pos.x + pos.width - 1, bottomY] = cell("▼", docPanelScrollStyle)
      else:
        termBuffer[pos.x + pos.width - 1, bottomY] = cell("┘", docPanelBorderStyle)

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
    mgr: CompletionManager,
    items: seq[CompletionItem],
    rawJsonItems: seq[JsonNode] = @[],
    isIncomplete: bool = false,
) =
  ## Set LSP completion items and update the menu
  mgr.lspItems = items
  mgr.lspRawJsonItems = rawJsonItems
  mgr.isIncomplete = isIncomplete
  mgr.lspRequestId = none(int)
  mgr.resolveRequestId = none(int)

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
  ## Get the raw JSON for the selected LSP item (for resolve requests)
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
  if lspIdx >= 0 and lspIdx < mgr.lspRawJsonItems.len:
    return some(mgr.lspRawJsonItems[lspIdx])

  return none(JsonNode)

proc updateResolvedEntry*(mgr: CompletionManager, resolved: CompletionItem) =
  ## Update the selected entry with resolved data from completionItem/resolve
  if mgr.menu.entries.len == 0:
    return
  let idx = mgr.resolvedIndex
  if idx >= mgr.menu.entries.len:
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
