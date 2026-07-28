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

import std/[strutils, options]

import buffer/core, help_generator, list_viewer

import types/help_viewer_types
export help_viewer_types, list_viewer

const HelpSentences* =
  "# Exiting\n\n" & renderExitingSection() & "\n# Changing modes\n\n" &
  renderChangingModesSection() & "\n# Normal mode\n\n" & renderNormalModeSection() &
  "\n# Register\n\n" & renderRegisterSection() & "\n# Visual mode\n\n" &
  renderVisualModeSection() & "\n# Replace mode\n\n" & renderReplaceModeSection() &
  "\n# Insert mode\n\n" & renderInsertModeSection() & "\n# Backup mode\n\n" &
  renderBackupModeSection() & "\n# Diff mode\n\n" & renderDiffModeSection() &
  "\n# References mode\n\n" & renderReferencesModeSection() &
  "\n# Call hierarchy viewer mode\n\n" & renderCallHierarchyModeSection() &
  "\n# Filer mode\n\n" & renderFilerModeSection() & "\n# FileTree mode\n\n" &
  renderFileTreeModeSection() & "\n# Buffer manager mode\n\n" &
  renderBufferManagerModeSection() & "\n# Bookmark manager mode\n\n" &
  renderBookmarkManagerModeSection() & "\n# Document symbol viewer mode\n\n" &
  renderDocumentSymbolModeSection() & "\n# Log viewer mode\n\n" &
  renderLogViewerModeSection() & "\n# Recent file mode\n\n" &
  renderRecentFileModeSection() & "\n# Configuration mode\n\n" &
  renderConfigModeSection() & "\n# Debug mode\n\n" & renderDebugModeSection() & """

# Command mode

""" &
  renderCommandModeHead() & "\n" & renderSetOptionsSection() & renderCommandModeTail() &
  """

## Runtime Key Mapping

nmap {lhs} {rhs}  - Map keys in Normal mode
imap {lhs} {rhs}  - Map keys in Insert mode
vmap {lhs} {rhs}  - Map keys in Visual modes
rmap {lhs} {rhs}  - Map keys in Replace mode
cmap {lhs} {rhs}  - Map keys in Command mode
map {lhs} {rhs}   - Map keys in all modes

nmap              - List all Normal mode mappings
imap              - List all Insert mode mappings
vmap              - List all Visual mode mappings
rmap              - List all Replace mode mappings
cmap              - List all Command mode mappings
map               - List all mode mappings

nunmap {lhs}      - Remove key mapping in Normal mode
iunmap {lhs}      - Remove key mapping in Insert mode
vunmap {lhs}      - Remove key mapping in Visual modes
runmap {lhs}      - Remove key mapping in Replace mode
cunmap {lhs}      - Remove key mapping in Command mode
unmap {lhs}       - Remove key mapping in all modes

nmapclear         - Clear all mappings in Normal mode
imapclear         - Clear all mappings in Insert mode
vmapclear         - Clear all mappings in Visual modes
rmapclear         - Clear all mappings in Replace mode
cmapclear         - Clear all mappings in Command mode
mapclear          - Clear all mappings in all modes

noremap, nnoremap, inoremap, vnoremap, cnoremap are aliases (all mappings are non-recursive).

Key notation:
  a, j, 0           - Regular keys
  C-s, M-x, C-M-a   - Modifier keys (C=Ctrl, M=Alt)
  Escape, Enter, Tab - Special keys
  Up, Down, F1-F12   - Arrow and function keys
  Space              - Space key
  j j, g g           - Multi-key sequences (space-separated)
  jj, gg             - Vim-style concatenated keys (equivalent to j j, g g)

{rhs} can be a command name or a key sequence (e.g. Escape).
Use :help to see the list of available command names.

Examples:
  :nmap C-s save-and-quit      - Ctrl-S saves and quits (Normal mode)
  :imap jj Escape              - jj exits Insert mode
  :nmap C-a g g                - Ctrl-A goes to first line (Normal mode)
  :vmap C-c Escape             - Ctrl-C exits Visual mode
  :cmap C-a Home               - Ctrl-A moves to start (Command mode)
  :nmap                        - List all Normal mode mappings
  :map                         - List all mode mappings

# Terminal mode

## Terminal-Input sub-mode (default)

All keystrokes are forwarded to the running shell/command.

""" &
  renderTerminalInputSection() & """

## Terminal-Normal sub-mode

""" &
  renderTerminalNormalSection()

proc newHelpViewerState*(): HelpViewerState =
  ## Create a new help viewer state
  var lines: seq[string]
  for line in HelpSentences.splitLines:
    lines.add(line)

  while lines.len > 0 and lines[^1].len == 0:
    # Drop trailing empty lines so state.items.len matches buffer.len —
    # otherwise selectedIndex can scroll one row past the buffer end.
    lines.setLen(lines.len - 1)

  HelpViewerState(items: lines, selectedIndex: 0, searchQuery: "")

proc lineCount*(state: HelpViewerState): int =
  ## Get the number of lines in the help
  state.items.len

proc getLine*(state: HelpViewerState, index: int): string =
  ## Get a specific line from the help
  if index >= 0 and index < state.items.len:
    state.items[index]
  else:
    ""

proc isSectionHeader(line: string): bool {.inline.} =
  # Top-level section header in HelpSentences ("# Heading").
  # `##` sub-sections are intentionally excluded so [/] step through
  # the top-level structure only.
  line.startsWith("# ")

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

proc setSearchQuery*(state: HelpViewerState, query: string) =
  ## Set the search query
  state.searchQuery = query

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
  state.items[index].toLowerAscii.contains(state.searchQuery.toLowerAscii)

proc searchForward*(state: HelpViewerState): Option[int] =
  ## Search forward from current position.
  ## Returns the line index if found, none otherwise.
  if not state.hasSearchQuery:
    return none(int)

  let query = state.searchQuery.toLowerAscii
  # Search from next line to end
  for i in (state.selectedIndex + 1) ..< state.items.len:
    if state.items[i].toLowerAscii.contains(query):
      state.selectedIndex = i
      return some(i)

  # Wrap around: search from beginning to current position
  for i in 0 ..< state.selectedIndex:
    if state.items[i].toLowerAscii.contains(query):
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
    if state.items[i].toLowerAscii.contains(query):
      state.selectedIndex = i
      return some(i)

  # Wrap around: search from end to current position
  for i in countdown(state.items.high, state.selectedIndex + 1):
    if state.items[i].toLowerAscii.contains(query):
      state.selectedIndex = i
      return some(i)

  none(int)

proc searchFirst*(state: HelpViewerState): Option[int] =
  ## Search from the beginning of the document.
  ## Returns the line index if found, none otherwise.
  if not state.hasSearchQuery:
    return none(int)

  let query = state.searchQuery.toLowerAscii
  for i in 0 ..< state.items.len:
    if state.items[i].toLowerAscii.contains(query):
      state.selectedIndex = i
      return some(i)

  none(int)

proc createHelpTextBuffer*(state: HelpViewerState): TextBuffer =
  ## Create a TextBuffer from help lines for rendering via the normal view path
  var content = ""
  for i, line in state.items:
    if i > 0:
      content.add('\n')
    if line.len > 0:
      content.add(' ' & line)
    else:
      content.add("")
  result = newTextBuffer(content)
  result.readOnly = true
