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

## Help viewer state management
##
## This module provides the data structures and operations for the help viewer mode.

import std/[strutils, options, sequtils]

import celina_backend as celina

import
  buffer/core, color, help_generator, highlight, list_viewer, primitives, unicode_utils

import types/help_viewer_types
export help_viewer_types, list_viewer

func keyTable(
    pairs: openArray[(string, string)], width: int, indent = 0
): seq[HelpLine] =
  for (keys, description) in pairs:
    result.add entryLine(indent, keys, width, description)

func blank(): seq[HelpLine] =
  @[textLine("")]

func heading(title: string): seq[HelpLine] =
  @[section(title), textLine("")]

func subheading(title: string): seq[HelpLine] =
  @[subsection(title), textLine("")]

func withoutTrailingBlanks*(lines: seq[HelpLine]): seq[HelpLine] =
  ## `lines` up to the last one with text, so the cursor never goes past it.
  result = lines
  while result.len > 0 and result[^1].text.len == 0:
    result.setLen(result.len - 1)

const UntrimmedHelpLines =
  heading("Exiting") & renderExitingSection() & blank() & heading("Changing modes") &
  renderChangingModesSection() & blank() & heading("Normal mode") &
  renderNormalModeSection() & blank() & heading("Register") & renderRegisterSection() &
  blank() & heading("Visual mode") & renderVisualModeSection() & blank() &
  heading("Replace mode") & renderReplaceModeSection() & blank() & heading(
    "Insert mode"
  ) & renderInsertModeSection() & blank() & heading("Backup mode") &
  renderBackupModeSection() & blank() & heading("Recovery mode") &
  renderRecoveryModeSection() & blank() & heading("Diff mode") & renderDiffModeSection() &
  blank() & heading("References mode") & renderReferencesModeSection() & blank() &
  heading("Call hierarchy viewer mode") & renderCallHierarchyModeSection() & blank() &
  heading("Filer mode") & renderFilerModeSection() & blank() & heading("FileTree mode") &
  renderFileTreeModeSection() & blank() & heading("Buffer manager mode") &
  renderBufferManagerModeSection() & blank() & heading("Bookmark manager mode") &
  renderBookmarkManagerModeSection() & blank() & heading("Document symbol viewer mode") &
  renderDocumentSymbolModeSection() & blank() & heading("Log viewer mode") &
  renderLogViewerModeSection() & blank() & heading("Recent file mode") &
  renderRecentFileModeSection() & blank() & heading("Configuration mode") &
  renderConfigModeSection() & blank() & heading("Debug mode") & renderDebugModeSection() &
  blank() & heading("Command mode") & renderCommandModeHead() & blank() &
  renderSetOptionsSection() & renderCommandModeTail() & blank() &
  subheading("Editing the command line") & renderCommandLineEditingSection() & blank() &
  subheading("Runtime Key Mapping") &
  keyTable(
    {
      "nmap {lhs} {rhs}": "Map keys in Normal mode",
      "imap {lhs} {rhs}": "Map keys in Insert mode",
      "vmap {lhs} {rhs}": "Map keys in Visual modes",
      "rmap {lhs} {rhs}": "Map keys in Replace mode",
      "cmap {lhs} {rhs}": "Map keys in Command mode",
      "map {lhs} {rhs}": "Map keys in all modes",
    },
    17,
  ) & blank() &
  keyTable(
    {
      "nmap": "List all Normal mode mappings",
      "imap": "List all Insert mode mappings",
      "vmap": "List all Visual mode mappings",
      "rmap": "List all Replace mode mappings",
      "cmap": "List all Command mode mappings",
      "map": "List all mode mappings",
    },
    17,
  ) & blank() &
  keyTable(
    {
      "nunmap {lhs}": "Remove key mapping in Normal mode",
      "iunmap {lhs}": "Remove key mapping in Insert mode",
      "vunmap {lhs}": "Remove key mapping in Visual modes",
      "runmap {lhs}": "Remove key mapping in Replace mode",
      "cunmap {lhs}": "Remove key mapping in Command mode",
      "unmap {lhs}": "Remove key mapping in all modes",
    },
    17,
  ) & blank() &
  keyTable(
    {
      "nmapclear": "Clear all mappings in Normal mode",
      "imapclear": "Clear all mappings in Insert mode",
      "vmapclear": "Clear all mappings in Visual modes",
      "rmapclear": "Clear all mappings in Replace mode",
      "cmapclear": "Clear all mappings in Command mode",
      "mapclear": "Clear all mappings in all modes",
    },
    17,
  ) & blank() &
  prose(
    "noremap, nnoremap, inoremap, vnoremap, cnoremap are aliases (all mappings are non-recursive).\n"
  ) & blank() & prose("Key notation:\n") &
  keyTable(
    {
      "a, j, 0": "Regular keys",
      "C-s, M-x, C-M-a": "Modifier keys (C=Ctrl, M=Alt)",
      "Escape, Enter, Tab": "Special keys",
      "Up, Down, F1-F12": "Arrow and function keys",
      "Space": "Space key",
      "j j, g g": "Multi-key sequences (space-separated)",
      "jj, gg": "Vim-style concatenated keys (equivalent to j j, g g)",
    },
    18,
    indent = 2,
  ) & blank() &
  prose(
    "{rhs} can be a command name or a key sequence (e.g. Escape).\n" &
      "Use :help to see the list of available command names.\n"
  ) & blank() & prose("Examples:\n") &
  keyTable(
    {
      ":nmap C-s save-and-quit": "Ctrl-S saves and quits (Normal mode)",
      ":imap jj Escape": "jj exits Insert mode",
      ":nmap C-a g g": "Ctrl-A goes to first line (Normal mode)",
      ":vmap C-c Escape": "Ctrl-C exits Visual mode",
      ":cmap C-a Home": "Ctrl-A moves to start (Command mode)",
      ":nmap": "List all Normal mode mappings",
      ":map": "List all mode mappings",
    },
    28,
    indent = 2,
  ) & blank() & heading("Terminal mode") &
  subheading("Terminal-Input sub-mode (default)") &
  prose("All keystrokes are forwarded to the running shell/command.\n") & blank() &
  renderTerminalInputSection() & blank() & subheading("Terminal-Normal sub-mode") &
  renderTerminalNormalSection()

const HelpLines* = UntrimmedHelpLines.withoutTrailingBlanks

proc newHelpViewerState*(): HelpViewerState =
  ## Create a new help viewer state
  HelpViewerState(items: HelpLines, selectedIndex: 0, searchQuery: "")

proc lineCount*(state: HelpViewerState): int =
  ## Get the number of lines in the help
  state.items.len

proc getLine*(state: HelpViewerState, index: int): string =
  ## Get a specific line from the help
  if index >= 0 and index < state.items.len:
    state.items[index].text
  else:
    ""

func isSectionHeader(line: HelpLine): bool =
  # `##` sub-sections are left out so [/] step through the top level only.
  line.kind == hlkSection

proc moveToNextSection*(state: HelpViewerState) =
  ## Jump to the next top-level "# " section header.
  ## Stays put if no further section exists.
  for i in (state.selectedIndex + 1) ..< state.items.len:
    if state.items[i].isSectionHeader:
      state.selectedIndex = i
      return

proc moveToPreviousSection*(state: HelpViewerState) =
  ## Jump to the previous top-level "# " section header.
  ## Stays put if no earlier section exists.
  for i in countdown(state.selectedIndex - 1, 0):
    if state.items[i].isSectionHeader:
      state.selectedIndex = i
      return

proc setSearchQuery*(
    state: HelpViewerState, query: string, direction: SearchDirection
) =
  ## Set the search query and the way its search went, which n goes too
  state.searchQuery = query
  state.searchDirection = direction

proc clearSearch*(state: HelpViewerState) =
  ## Clear the search query
  state.searchQuery = ""

proc hasSearchQuery*(state: HelpViewerState): bool =
  ## Check if there is an active search query
  state.searchQuery.len > 0

proc isLineMatched*(state: HelpViewerState, index: int): bool =
  ## Check if a line matches the current search query (case-insensitive)
  if not state.hasSearchQuery:
    return false
  if index < 0 or index >= state.items.len:
    return false
  state.items[index].text.toLowerAscii.contains(state.searchQuery.toLowerAscii)

proc searchForward*(state: HelpViewerState): Option[int] =
  ## Search forward from current position.
  ## Returns the line index if found, none otherwise.
  if not state.hasSearchQuery:
    return none(int)

  let query = state.searchQuery.toLowerAscii
  # Search from next line to end
  for i in (state.selectedIndex + 1) ..< state.items.len:
    if state.items[i].text.toLowerAscii.contains(query):
      state.selectedIndex = i
      return some(i)

  # Wrap around: search from beginning to current position
  for i in 0 ..< state.selectedIndex:
    if state.items[i].text.toLowerAscii.contains(query):
      state.selectedIndex = i
      return some(i)

  none(int)

proc searchBackward*(state: HelpViewerState): Option[int] =
  ## Search backward from current position.
  ## Returns the line index if found, none otherwise.
  if not state.hasSearchQuery:
    return none(int)

  let query = state.searchQuery.toLowerAscii
  # Search from previous line to beginning
  for i in countdown(state.selectedIndex - 1, 0):
    if state.items[i].text.toLowerAscii.contains(query):
      state.selectedIndex = i
      return some(i)

  # Wrap around: search from end to current position
  for i in countdown(state.items.high, state.selectedIndex + 1):
    if state.items[i].text.toLowerAscii.contains(query):
      state.selectedIndex = i
      return some(i)

  none(int)

proc repeatSearch*(state: HelpViewerState, reverse: bool): Option[int] =
  ## n, or N when `reverse`: the next match the way the search went.
  if repeatDirection(state.searchDirection, reverse) == Forward:
    state.searchForward()
  else:
    state.searchBackward()

proc searchFirst*(state: HelpViewerState): Option[int] =
  ## Search from the beginning of the document.
  ## Returns the line index if found, none otherwise.
  if not state.hasSearchQuery:
    return none(int)

  let query = state.searchQuery.toLowerAscii
  for i in 0 ..< state.items.len:
    if state.items[i].text.toLowerAscii.contains(query):
      state.selectedIndex = i
      return some(i)

  none(int)

proc helpHighlight(lines: openArray[HelpLine]): Highlight =
  ## Section headings and the keys of entries in their colors, the rest plain.
  ## `lines` as shown, with the one-column margin already in front.
  var texts = newSeqOfCap[string](lines.len)
  for line in lines:
    texts.add line.text
  result = initHighlight(texts)
  for row, line in lines:
    let (first, last, color, modifiers) =
      case line.kind
      of hlkText:
        continue
      of hlkSection, hlkSubsection:
        (
          1, # Past the margin, which stays plain as on the other lines
          line.text.charLen - 1,
          EditorColorPairIndex.helpViewerSectionHeader,
          {StyleModifier.Bold},
        )
      of hlkEntry:
        (
          line.text[0 ..< line.keyFirst].charLen,
          line.text[0 ..< line.keyEnd].charLen - 1,
          EditorColorPairIndex.keyword,
          set[StyleModifier]({}),
        )
    if first <= last:
      var style = highlight.defaultStyle
      style.modifiers = modifiers
      result.overwrite ColorSegment(
        firstRow: row,
        firstColumn: first,
        lastRow: row,
        lastColumn: last,
        color: color,
        style: style,
      )

proc createHelpTextBuffer*(state: HelpViewerState): TextBuffer =
  ## Create a TextBuffer from help lines for rendering via the normal view path
  var lines = newSeqOfCap[HelpLine](state.items.len)
  for line in state.items:
    var shown = line
    if shown.text.len > 0:
      # A column of margin, as before the first character of Vim's help.
      shown.text = ' ' & shown.text
      shown.keyFirst.inc
      shown.keyEnd.inc
    lines.add shown
  result = newTextBuffer(lines.mapIt(it.text).join("\n"))
  result.readOnly = true
  # As Vim's help window: no line numbers, colors of its own.
  result.isUtilityBuffer = true
  result.highlightNeedsUpdate = false
  result.highlight = helpHighlight(lines)
