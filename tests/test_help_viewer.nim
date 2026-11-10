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

import std/[unittest, options, sequtils, strutils, tables]
from std/unicode import runeLen
import ../src/moepkg/[help_viewer, buffer, primitives, color, highlight]
import pkg/celina

proc texts(state: HelpViewerState): seq[string] =
  state.items.mapIt(it.text)

suite "HelpViewer - State creation":
  test "newHelpViewerState creates state with lines":
    let state = newHelpViewerState()

    check state.items.len > 0
    check state.selectedIndex == 0
    check state.searchQuery == ""

  test "lineCount returns correct count":
    let state = newHelpViewerState()

    check state.lineCount == state.items.len
    check state.lineCount > 0

  test "lines.len matches rendered buffer.len":
    # Regression: when state.items has more lines than the buffer,
    # selectedIndex can scroll past the last buffer line into a blank row.
    let state = newHelpViewerState()
    let buf = state.createHelpTextBuffer()

    check state.items.len == buf.len

  test "last line is non-empty":
    # Regression: a trailing empty entry in state.items lets selectedIndex
    # land on a row that the buffer does not render.
    let state = newHelpViewerState()

    check state.items.len > 0
    check state.texts[^1].len > 0

  test "no help line spans rows":
    check HelpLines.allIt('\n' notin it.text)

  test "a help line with a newline in it is refused":
    expect AssertionDefect:
      discard textLine("a\nb")
    expect AssertionDefect:
      discard section("a\nb")
    expect AssertionDefect:
      discard subsection("a\nb")
    expect AssertionDefect:
      discard entryLine(0, "k", 1, "a\nb")

  test "prose splits its text into one line per row":
    check prose("a\nb\n").mapIt(it.text) == @["a", "b"]

  test "withoutTrailingBlanks drops only the blanks at the end":
    let lines = @[textLine(""), textLine("a"), textLine(""), textLine("")]
    check lines.withoutTrailingBlanks.mapIt(it.text) == @["", "a"]
    check @[textLine("")].withoutTrailingBlanks.len == 0

suite "HelpViewer - Highlight":
  proc colorsOf(items: seq[HelpLine]): seq[seq[EditorColorPairIndex]] =
    ## Color of each column of each rendered line.
    let buf = HelpViewerState(items: items).createHelpTextBuffer()
    for row in 0 ..< buf.len:
      var cols: seq[EditorColorPairIndex]
      for col in 0 ..< buf.getLine(row).runeLen:
        cols.add buf.highlight.getColorPair(row, col)
      result.add cols

  const
    K = EditorColorPairIndex.keyword
    D = EditorColorPairIndex.default
    H = EditorColorPairIndex.helpViewerSectionHeader

  test "a section heading is colored as a whole, after the margin":
    check colorsOf(@[section("Exit"), subsection("Sub")]) ==
      @[@[D] & H.repeat(6), @[D] & H.repeat(6)]

  test "the key column of an entry is a keyword":
    check colorsOf(@[entryLine(0, "gg", 2, "Top")]) ==
      @[@[D] & K.repeat(2) & D.repeat(6)]

  test "a key ending in a dash stays in the key column":
    check colorsOf(@[entryLine(0, "Ctrl-w -", 8, "Down")]) ==
      @[@[D] & K.repeat(8) & D.repeat(7)]

  test "an indented key is colored from its first character":
    check colorsOf(@[entryLine(2, "a, j", 4, "Keys")]) ==
      @[D.repeat(3) & K.repeat(4) & D.repeat(7)]

  test "a # key is an entry, not a heading":
    check colorsOf(@[entryLine(0, "#", 2, "Back")]) == @[@[D, K] & D.repeat(8)]

  test "prose with a dash in it stays plain":
    check colorsOf(@[textLine("Note - see :help")]) == @[D.repeat(17)]

  test "columns count characters, not bytes":
    check colorsOf(@[entryLine(0, "é", 1, "ü")]) == @[@[D, K] & D.repeat(4)]

  test "colors leave the background to the theme":
    # A background taken from the theme now would outlive a theme change.
    let buf = HelpViewerState(items: @[section("Exit")]).createHelpTextBuffer()
    for seg in buf.highlight.colorSegments:
      check seg.style.bg.kind == Default

  test "segments tile every line in order":
    # The lookup takes the last segment starting at or before a column, so a
    # gap would take the color before it.
    let buf = newHelpViewerState().createHelpTextBuffer()
    var nextColumn: Table[int, int]
    for seg in buf.highlight.colorSegments:
      check seg.firstRow == seg.lastRow
      check seg.firstColumn == nextColumn.getOrDefault(seg.firstRow, 0)
      nextColumn[seg.firstRow] = seg.lastColumn + 1
    for row in 0 ..< buf.len:
      check nextColumn.getOrDefault(row, 0) == buf.getLine(row).runeLen

  test "the help buffer has no line numbers, as Vim's help window":
    check newHelpViewerState().createHelpTextBuffer().isUtilityBuffer

suite "HelpViewer - Line access":
  test "getLine returns line at valid index":
    let state = newHelpViewerState()

    let line = state.getLine(0)
    check line == state.texts[0]

  test "getLine returns empty string for negative index":
    let state = newHelpViewerState()

    check state.getLine(-1) == ""

  test "getLine returns empty string for out of range index":
    let state = newHelpViewerState()

    check state.getLine(state.items.len) == ""
    check state.getLine(state.items.len + 100) == ""

suite "HelpViewer - Navigation":
  test "moveUp decreases selectedIndex":
    let state = newHelpViewerState()
    state.selectedIndex = 5

    state.moveUp()
    check state.selectedIndex == 4

    state.moveUp()
    check state.selectedIndex == 3

  test "moveUp does nothing at index 0":
    let state = newHelpViewerState()
    state.selectedIndex = 0

    state.moveUp()
    check state.selectedIndex == 0

  test "moveDown increases selectedIndex":
    let state = newHelpViewerState()
    state.selectedIndex = 0

    state.moveDown()
    check state.selectedIndex == 1

    state.moveDown()
    check state.selectedIndex == 2

  test "moveDown does nothing at last index":
    let state = newHelpViewerState()
    state.selectedIndex = state.items.high

    state.moveDown()
    check state.selectedIndex == state.items.high

  test "moveToFirst sets selectedIndex to 0":
    let state = newHelpViewerState()
    state.selectedIndex = 10

    state.moveToFirst()
    check state.selectedIndex == 0

  test "moveToLast sets selectedIndex to last":
    let state = newHelpViewerState()
    state.selectedIndex = 0

    state.moveToLast()
    check state.selectedIndex == state.items.high

suite "HelpViewer - Half page navigation":
  test "halfPageUp moves up by half viewport":
    let state = newHelpViewerState()
    state.selectedIndex = 20

    state.halfPageUp(10)
    check state.selectedIndex == 15

  test "halfPageUp clamps to 0":
    let state = newHelpViewerState()
    state.selectedIndex = 2

    state.halfPageUp(10)
    check state.selectedIndex == 0

  test "halfPageDown moves down by half viewport":
    let state = newHelpViewerState()
    state.selectedIndex = 5

    state.halfPageDown(10)
    check state.selectedIndex == 10

  test "halfPageDown clamps to last line":
    let state = newHelpViewerState()
    state.selectedIndex = state.items.high - 2

    state.halfPageDown(10)
    check state.selectedIndex == state.items.high

suite "HelpViewer - Section navigation":
  test "moveToNextSection jumps to next '# ' header":
    let state = newHelpViewerState()
    # state.texts[0] is "# Exiting" — the first top-level section header.
    check state.texts[0].startsWith("# ")
    check state.selectedIndex == 0

    state.moveToNextSection()
    check state.selectedIndex > 0
    check state.texts[state.selectedIndex].startsWith("# ")
    check not state.texts[state.selectedIndex].startsWith("## ")

  test "moveToNextSection skips '## ' sub-section headers":
    let state = newHelpViewerState()

    # Land on a "## " sub-section line and verify the next jump goes to a
    # top-level "# " section, not the next "## ".
    var subIdx = -1
    for i, line in state.texts:
      if line.startsWith("## "):
        subIdx = i
        break
    check subIdx >= 0

    state.selectedIndex = subIdx
    state.moveToNextSection()

    if state.selectedIndex != subIdx:
      check state.texts[state.selectedIndex].startsWith("# ")
      check not state.texts[state.selectedIndex].startsWith("## ")

  test "moveToNextSection does not stop at the # key of Normal mode":
    let state = newHelpViewerState()
    let key = state.items.findIt(it.kind == hlkEntry and it.text.startsWith("# "))
    check key >= 0
    state.selectedIndex = key - 1
    state.moveToNextSection()
    check state.selectedIndex != key
    check state.items[state.selectedIndex].kind == hlkSection

  test "moveToNextSection stays put when no further section exists":
    let state = newHelpViewerState()

    # Find the last top-level section, then move past it.
    var lastSectionIdx = -1
    for i, line in state.texts:
      if line.startsWith("# ") and not line.startsWith("## "):
        lastSectionIdx = i
    check lastSectionIdx >= 0

    state.selectedIndex = lastSectionIdx
    state.moveToNextSection()
    check state.selectedIndex == lastSectionIdx

  test "moveToPreviousSection jumps to previous '# ' header":
    let state = newHelpViewerState()

    # Find the second top-level section and jump back from it.
    var firstIdx = -1
    var secondIdx = -1
    for i, line in state.texts:
      if line.startsWith("# ") and not line.startsWith("## "):
        if firstIdx == -1:
          firstIdx = i
        else:
          secondIdx = i
          break
    check firstIdx >= 0
    check secondIdx > firstIdx

    state.selectedIndex = secondIdx
    state.moveToPreviousSection()
    check state.selectedIndex == firstIdx

  test "moveToPreviousSection stays put when no earlier section exists":
    let state = newHelpViewerState()
    state.selectedIndex = 0

    state.moveToPreviousSection()
    check state.selectedIndex == 0

  test "moveToPreviousSection skips '## ' sub-section headers":
    let state = newHelpViewerState()

    var subIdx = -1
    for i, line in state.texts:
      if line.startsWith("## "):
        subIdx = i
        break
    check subIdx >= 0

    state.selectedIndex = subIdx
    state.moveToPreviousSection()

    check state.selectedIndex < subIdx
    check state.texts[state.selectedIndex].startsWith("# ")
    check not state.texts[state.selectedIndex].startsWith("## ")

suite "HelpViewer - Search query":
  test "setSearchQuery sets the query":
    let state = newHelpViewerState()

    state.setSearchQuery("test", Forward)
    check state.searchQuery == "test"

  test "clearSearch clears the query":
    let state = newHelpViewerState()
    state.setSearchQuery("test", Forward)

    state.clearSearch()
    check state.searchQuery == ""

  test "hasSearchQuery returns true when query exists":
    let state = newHelpViewerState()
    state.setSearchQuery("test", Forward)

    check state.hasSearchQuery == true

  test "hasSearchQuery returns false when query is empty":
    let state = newHelpViewerState()

    check state.hasSearchQuery == false

  test "hasSearchQuery returns false after clearSearch":
    let state = newHelpViewerState()
    state.setSearchQuery("test", Forward)
    state.clearSearch()

    check state.hasSearchQuery == false

suite "HelpViewer - Line matching":
  test "isLineMatched returns true for matching line":
    let state = newHelpViewerState()
    state.setSearchQuery("Normal mode", Forward)

    # Find a line containing "Normal mode"
    var foundIndex = -1
    for i, line in state.texts:
      if "Normal mode" in line:
        foundIndex = i
        break

    check foundIndex >= 0
    check state.isLineMatched(foundIndex) == true

  test "isLineMatched is case insensitive":
    let state = newHelpViewerState()
    state.setSearchQuery("normal MODE", Forward)

    var foundIndex = -1
    for i, line in state.texts:
      if "Normal mode" in line:
        foundIndex = i
        break

    check foundIndex >= 0
    check state.isLineMatched(foundIndex) == true

  test "isLineMatched returns false for non-matching line":
    let state = newHelpViewerState()
    state.setSearchQuery("xyznonexistent123", Forward)

    check state.isLineMatched(0) == false

  test "isLineMatched returns false when no search query":
    let state = newHelpViewerState()

    check state.isLineMatched(0) == false

  test "isLineMatched returns false for negative index":
    let state = newHelpViewerState()
    state.setSearchQuery("test", Forward)

    check state.isLineMatched(-1) == false

  test "isLineMatched returns false for out of range index":
    let state = newHelpViewerState()
    state.setSearchQuery("test", Forward)

    check state.isLineMatched(state.items.len) == false

suite "HelpViewer - Search forward":
  test "searchForward finds next matching line":
    let state = newHelpViewerState()
    state.setSearchQuery(":w", Forward)
    state.selectedIndex = 0

    let result = state.searchForward()
    check result.isSome
    check state.selectedIndex > 0
    check ":w" in state.texts[state.selectedIndex].toLowerAscii or
      ":W" in state.texts[state.selectedIndex]

  test "searchForward wraps around to beginning":
    let state = newHelpViewerState()
    state.setSearchQuery("Exiting", Forward)

    # Set selectedIndex to after the "Exiting" section
    state.selectedIndex = state.items.high

    let result = state.searchForward()
    check result.isSome
    # Should wrap around and find "Exiting" near the beginning
    check state.selectedIndex < state.items.high

  test "searchForward returns none when no match":
    let state = newHelpViewerState()
    state.setSearchQuery("xyznonexistent123456", Forward)
    state.selectedIndex = 0

    let result = state.searchForward()
    check result.isNone

  test "searchForward returns none when no search query":
    let state = newHelpViewerState()
    state.selectedIndex = 0

    let result = state.searchForward()
    check result.isNone

suite "HelpViewer - Search backward":
  test "searchBackward finds previous matching line":
    let state = newHelpViewerState()
    state.setSearchQuery("mode", Forward)
    state.selectedIndex = state.items.high

    let result = state.searchBackward()
    check result.isSome
    check state.selectedIndex < state.items.high

  test "searchBackward wraps around to end":
    let state = newHelpViewerState()
    state.setSearchQuery("backup", Forward)
    state.selectedIndex = 0

    let result = state.searchBackward()
    check result.isSome
    # Should wrap around and find "jumps" near the end
    check state.selectedIndex > 0

  test "searchBackward returns none when no match":
    let state = newHelpViewerState()
    state.setSearchQuery("xyznonexistent123456", Forward)
    state.selectedIndex = 10

    let result = state.searchBackward()
    check result.isNone

  test "searchBackward returns none when no search query":
    let state = newHelpViewerState()
    state.selectedIndex = 10

    let result = state.searchBackward()
    check result.isNone

suite "HelpViewer - Search first":
  test "searchFirst finds first matching line from beginning":
    let state = newHelpViewerState()
    state.setSearchQuery("Exiting", Forward)
    state.selectedIndex = state.items.high

    let result = state.searchFirst()
    check result.isSome
    # Should find "Exiting" near the beginning
    check state.selectedIndex < state.items.high

  test "searchFirst returns none when no match":
    let state = newHelpViewerState()
    state.setSearchQuery("xyznonexistent123456", Forward)
    state.selectedIndex = 0

    let result = state.searchFirst()
    check result.isNone

  test "searchFirst returns none when no search query":
    let state = newHelpViewerState()

    let result = state.searchFirst()
    check result.isNone

  test "searchFirst always starts from line 0":
    let state = newHelpViewerState()
    state.setSearchQuery("# Exiting", Forward)
    state.selectedIndex = 50

    let result = state.searchFirst()
    check result.isSome
    # The first match should be the "# Exiting" header near the beginning
    check state.selectedIndex < 10

suite "HelpViewer - Command mode rendering (snapshot)":
  ## These assertions pin the exact output of `help_generator` so that any
  ## change to the structured `ExCommandGroups` or to the canonical
  ## `SetOptionTable` (in `setting_options`) — or to the per-group alignment
  ## width — is caught as a test failure. Update the literals deliberately
  ## when the help text is intentionally changed.

  test "Command mode header is present":
    let state = newHelpViewerState()
    check state.texts.contains("# Command mode")

  test "head group 1 (jump/shell/bg/man) is aligned to width 18":
    let state = newHelpViewerState()
    check state.texts.contains("number             - Jump to line number; e.g. :10")
    check state.texts.contains(
      "$ or . or +N or -N - Jump to an address: $ last line, . current line, +N / -N relative; e.g. :.+3"
    )
    check state.texts.contains("! shell command    - Shell command execution")
    check state.texts.contains(
      "bg                 - Pause the editor and show the recent terminal output"
    )

  test "head group 2 (:e family) is aligned to width 16":
    let state = newHelpViewerState()
    check state.texts.contains("e filename       - Open file")
    check state.texts.contains(
      "e                - Reload current file (error if unsaved changes)"
    )
    check state.texts.contains("e! filename      - Open file (discard unsaved changes)")
    check state.texts.contains("saveas filename  - Write to filename and edit it")
    check state.texts.contains(
      "saveas! filename - Write to filename even if it exists, and edit it"
    )
    check state.texts.contains(
      "w filename       - Write a copy to filename; a buffer without a name takes it"
    )

  test "head group 3 (:delete family) is aligned to width 21":
    let state = newHelpViewerState()
    check state.texts.anyIt(
      it.startsWith("%s/keyword1/keyword2/ - Replace regex matches")
    )
    check state.texts.contains(
      "delete                - Delete current line and copy to register"
    )

  test "head group 4 (buffers/windows) is aligned to width 17":
    let state = newHelpViewerState()
    check state.texts.contains("ls                - Display all buffers")
    check state.texts.contains("bd [number|name]  - Delete buffer")
    check state.texts.contains(
      "bd! [number|name] - Delete buffer, discarding unsaved changes"
    )
    check state.texts.contains(
      "filetree path     - Toggle FileTree sidebar with specified root path"
    )

  test "head group 5 (theme/noh/stripwhitespace) is aligned to width 15":
    let state = newHelpViewerState()
    # `description` is a structured `Description` with inline-code
    # segments for the howtouse.md renderer; `toPlainText` strips the
    # code-span markers before the TUI sees the line, so the rendered
    # prose has no `` ` `` glyphs.
    check state.texts.contains("theme themeName - Change color theme; e.g. theme dark")
    check state.texts.contains(
      "noh             - Hide search highlights until the next search"
    )
    check state.texts.contains("stripwhitespace - Delete trailing spaces")

  test "bool set options block is aligned to the widest entry":
    let state = newHelpViewerState()
    # Short entry must be padded to match the longest entry
    # (`set highlightgitconflicttwocolor / set nohighlightgitconflicttwocolor (hgctc/nohgctc)`).
    check state.texts.contains(
      "set number / set nonumber (nu/nonu)                                                   - Show/hide line numbers"
    )
    # `set wrap` / `set scrollbar` have no short alias and so render without parens.
    check state.texts.contains(
      "set wrap / set nowrap                                                                 - Enable/disable line wrap"
    )
    check state.texts.contains(
      "set scrollbar / set noscrollbar                                                       - Enable/disable scrollbar"
    )
    # Longest entry sets the width; only one space before the dash.
    check state.texts.contains(
      "set highlightgitconflicttwocolor / set nohighlightgitconflicttwocolor (hgctc/nohgctc) - Use two-color (ours/theirs) conflict scheme; disable for single-color fallback"
    )

  test "value set options block is aligned to its own widest entry":
    let state = newHelpViewerState()
    # Example values now come from the canonical SetOptionTable (which also
    # feeds the executeSet error messages — so they say "scrollbarwidth=1" /
    # "tabstop=4" instead of the older help-only "=2").
    check state.texts.contains(
      "set scrollbarwidth=number       - Change scrollbar width (0 = hidden); e.g. set scrollbarwidth=1"
    )
    check state.texts.contains(
      "set tabstop=number (ts)         - Change tab stop width; e.g. set tabstop=4"
    )
    check state.texts.contains(
      "set shiftwidth=number (sw)      - Change indent width; e.g. set shiftwidth=4"
    )
    check state.texts.contains(
      "set softtabstop=number (sts)    - Change soft tab stop width; e.g. set softtabstop=4"
    )
    check state.texts.contains(
      "set scrollairdrag=number (sad)  - Change smooth scroll air drag; e.g. set scrollairdrag=2.0"
    )

  test "trailing group (build/lspfold/lspformat) is aligned to width 9":
    let state = newHelpViewerState()
    check state.texts.contains("build     - Build the current buffer")
    check state.texts.contains("lspfold   - LSP Folding Range")
    check state.texts.contains("lspformat - LSP Document Formatting")

  test "trailing group (lsprestart/lspcallhierarchy) is aligned to width 24":
    let state = newHelpViewerState()
    check state.texts.contains(
      "lsprestart               - Restart the current LSP server"
    )
    check state.texts.contains(
      "lspcallhierarchyincoming - Show incoming calls (callers) at cursor"
    )

  test "trailing group (terminal) is aligned to width 16":
    let state = newHelpViewerState()
    check state.texts.contains(
      "terminal         - Open terminal emulator (default shell)"
    )
    check state.texts.contains("terminal command - Run command in terminal emulator")

  test "trailing single-entry groups render without padding":
    let state = newHelpViewerState()
    check state.texts.contains("help - Open this help")
    check state.texts.contains("quickrun - Quick run")
    check state.texts.contains(
      "conflictprev - Jump to previous git merge conflict block"
    )

  test "blank lines separate Command mode, its editing keys and Runtime Key Mapping":
    let state = newHelpViewerState()
    # The last line of a section, a blank line, then the next subsection header
    # must appear consecutively in the rendered output.
    let idx =
      state.texts.find("conflictprev - Jump to previous git merge conflict block")
    check idx >= 0
    check state.texts[idx + 1] == ""
    check state.texts[idx + 2] == "## Editing the command line"
    let last = state.texts.find(
      "Ctrl-p                    - Select the previous completion, or recall the next older history entry"
    )
    check last > idx
    check state.texts[last + 1] == ""
    check state.texts[last + 2] == "## Runtime Key Mapping"

suite "HelpViewer - Mode sections (snapshot)":
  ## Snapshot assertions for the per-mode `render*Section` procs in
  ## `help_generator`. Each suite test pins the section header plus a few
  ## representative entries (first/last/longest) so accidental drops, reorders,
  ## or column-width changes in the underlying `*Commands` tables fail the
  ## build. Update literals deliberately when content is intentionally changed.

  test "# Exiting section is aligned to width 10":
    let state = newHelpViewerState()
    check state.texts.contains("# Exiting")
    check state.texts.contains(":w         - Write file")
    check state.texts.contains(":q         - Quit")
    check state.texts.contains(":x or :xit - Write if modified and quit")
    check state.texts.contains(":wqa!      - Force write and quit all windows")
    check state.texts.contains(":cq        - Quit with non-zero exit code")

  test "# Changing modes section is aligned to width 6":
    let state = newHelpViewerState()
    check state.texts.contains("# Changing modes")
    check state.texts.contains("v      - Visual mode")
    check state.texts.contains("Ctrl-v - Visual block mode")
    check state.texts.contains("A      - Same as $a")

  test "# Normal mode section preserves representative entries":
    let state = newHelpViewerState()
    check state.texts.contains("# Normal mode")
    check state.texts.contains("h          - Go left")
    check state.texts.contains("gg         - Go to the first line")
    check state.texts.contains("dgN        - Delete previous search match")
    check state.texts.contains(
      "ca{ or ca} - Delete around curly brackets and enter insert mode"
    )

  test "# Visual mode section uses minWidth=9 padding":
    let state = newHelpViewerState()
    check state.texts.contains("# Visual mode")
    # natural max is 8 ("gp or gP"); minWidth pads to 9
    check state.texts.contains("d or x    - Delete text")
    check state.texts.contains(
      "Ctrl-a    - Increase the first number on each selected line"
    )
    check state.texts.contains("Esc       - Go to Normal mode")
    check state.texts.contains(
      "gp or gP  - Paste over the selection and leave the cursor after the pasted text (replacing the whole buffer parks on the last pasted character)"
    )

  test "# Replace mode section is aligned to width 9":
    let state = newHelpViewerState()
    check state.texts.contains("# Replace mode")
    check state.texts.contains("Esc       - Go to Normal mode")
    check state.texts.contains("Backspace - Undo")

  test "# Insert mode section is aligned to widest entry":
    let state = newHelpViewerState()
    check state.texts.contains("# Insert mode")
    check state.texts.contains(
      "Ctrl-e               - Insert the character which is below the cursor"
    )
    check state.texts.contains(
      "Ctrl-h or Backspace  - Delete the character before the cursor"
    )
    check state.texts.contains("Esc                  - Go to Normal mode")

  test "# Backup mode section is aligned to width 5":
    let state = newHelpViewerState()
    check state.texts.contains("# Backup mode")
    check state.texts.contains("j     - Go down")
    check state.texts.contains("Enter - Open diff")
    check state.texts.contains("R     - Restore backup file")

  test "# Diff mode section is aligned to width 2":
    let state = newHelpViewerState()
    check state.texts.contains("# Diff mode")
    check state.texts.contains("j  - Go down")
    check state.texts.contains("gg - Go to the first line")
    check state.texts.contains("G  - Go to the last line")

  test "# References mode section is aligned to width 5":
    let state = newHelpViewerState()
    check state.texts.contains("# References mode")
    check state.texts.contains("Enter - Jump to the destination")
    check state.texts.contains("Esc   - Quit References mode")

  test "# Call hierarchy viewer mode section is aligned to width 5":
    let state = newHelpViewerState()
    check state.texts.contains("# Call hierarchy viewer mode")
    check state.texts.contains("Enter - Jump to the destination")
    check state.texts.contains("i     - Incoming call")
    check state.texts.contains("o     - Outgoing call")

  test "# Filer mode section is aligned to width 2":
    let state = newHelpViewerState()
    check state.texts.contains("# Filer mode")
    check state.texts.contains("j  - Go down")
    check state.texts.contains("D  - Delete file")
    check state.texts.contains("v  - Split window and open file or directory")

  test "# Register section uses the kbd-group syntax + description form":
    # The widest entry is `" any cl or " any s` (19 chars), which sets the
    # alignment for the entire group. Switching from the old hyphen-only
    # `seq[string]` to a `HelpGroup` means each row now renders as
    # `syntax  - description`, consistent with every other mode section.
    let state = newHelpViewerState()
    check state.texts.contains("# Register")
    check state.texts.contains(
      "\" any yy".alignLeft(19) & " - Yank a line to a named register"
    )
    check state.texts.contains(
      "\" any di any".alignLeft(19) & " - Delete inside to a named register"
    )
    check state.texts.contains(
      "\" any cl or \" any s - Change a character to a named register"
    )

  test "# Terminal mode section has both sub-mode headers":
    let state = newHelpViewerState()
    check state.texts.contains("# Terminal mode")
    check state.texts.contains("## Terminal-Input sub-mode (default)")
    check state.texts.contains("## Terminal-Normal sub-mode")

  test "Terminal-Input sub-mode body lists Ctrl-\\ Ctrl-n switch":
    let state = newHelpViewerState()
    check state.texts.contains(
      "All keystrokes are forwarded to the running shell/command."
    )
    check state.texts.contains("Ctrl-\\ Ctrl-n - Switch to Terminal-Normal sub-mode")

  test "Terminal-Normal sub-mode body uses minWidth=2":
    let state = newHelpViewerState()
    check state.texts.contains("i  - Return to Terminal-Input sub-mode")
    check state.texts.contains("a  - Return to Terminal-Input sub-mode")
    check state.texts.contains(":  - Enter command mode")
