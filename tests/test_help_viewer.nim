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

import std/[unittest, options, strutils]
import ../src/moepkg/[help_viewer, buffer]

suite "HelpViewer - State creation":
  test "newHelpViewerState creates state with lines":
    let state = newHelpViewerState()

    check state.lines.len > 0
    check state.selectedIndex == 0
    check state.topLine == 0
    check state.searchQuery == ""

  test "lineCount returns correct count":
    let state = newHelpViewerState()

    check state.lineCount == state.lines.len
    check state.lineCount > 0

  test "lines.len matches rendered buffer.len":
    # Regression: when state.lines has more lines than the buffer,
    # selectedIndex can scroll past the last buffer line into a blank row.
    let state = newHelpViewerState()
    let buf = state.createHelpTextBuffer()

    check state.lines.len == buf.len

  test "last line is non-empty":
    # Regression: a trailing empty entry in state.lines lets selectedIndex
    # land on a row that the buffer does not render.
    let state = newHelpViewerState()

    check state.lines.len > 0
    check state.lines[^1].len > 0

suite "HelpViewer - Line access":
  test "getLine returns line at valid index":
    let state = newHelpViewerState()

    let line = state.getLine(0)
    check line == state.lines[0]

  test "getLine returns empty string for negative index":
    let state = newHelpViewerState()

    check state.getLine(-1) == ""

  test "getLine returns empty string for out of range index":
    let state = newHelpViewerState()

    check state.getLine(state.lines.len) == ""
    check state.getLine(state.lines.len + 100) == ""

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
    state.selectedIndex = state.lines.high

    state.moveDown()
    check state.selectedIndex == state.lines.high

  test "moveToFirst sets selectedIndex to 0":
    let state = newHelpViewerState()
    state.selectedIndex = 10

    state.moveToFirst()
    check state.selectedIndex == 0

  test "moveToLast sets selectedIndex to last":
    let state = newHelpViewerState()
    state.selectedIndex = 0

    state.moveToLast()
    check state.selectedIndex == state.lines.high

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
    state.selectedIndex = state.lines.high - 2

    state.halfPageDown(10)
    check state.selectedIndex == state.lines.high

suite "HelpViewer - Viewport":
  test "ensureSelectedVisible scrolls up when selection above viewport":
    let state = newHelpViewerState()
    state.topLine = 10
    state.selectedIndex = 5

    state.ensureSelectedVisible(10)
    check state.topLine == 5

  test "ensureSelectedVisible scrolls down when selection below viewport":
    let state = newHelpViewerState()
    state.topLine = 0
    state.selectedIndex = 15

    state.ensureSelectedVisible(10)
    check state.topLine == 6

  test "ensureSelectedVisible does not change when selection is visible":
    let state = newHelpViewerState()
    state.topLine = 5
    state.selectedIndex = 10

    state.ensureSelectedVisible(10)
    check state.topLine == 5

  test "ensureSelectedVisible ensures topLine is not negative":
    let state = newHelpViewerState()
    state.topLine = -5
    state.selectedIndex = 0

    state.ensureSelectedVisible(10)
    check state.topLine == 0

  test "ensureSelectedVisible with selection at viewport boundary":
    let state = newHelpViewerState()
    state.topLine = 5
    state.selectedIndex = 14

    state.ensureSelectedVisible(10)
    check state.topLine == 5

  test "ensureSelectedVisible when selection just outside viewport":
    let state = newHelpViewerState()
    state.topLine = 5
    state.selectedIndex = 15

    state.ensureSelectedVisible(10)
    check state.topLine == 6

suite "HelpViewer - Section navigation":
  test "moveToNextSection jumps to next '# ' header":
    let state = newHelpViewerState()
    # state.lines[0] is "# Exiting" — the first top-level section header.
    check state.lines[0].startsWith("# ")
    check state.selectedIndex == 0

    state.moveToNextSection()
    check state.selectedIndex > 0
    check state.lines[state.selectedIndex].startsWith("# ")
    check not state.lines[state.selectedIndex].startsWith("## ")

  test "moveToNextSection skips '## ' sub-section headers":
    let state = newHelpViewerState()

    # Land on a "## " sub-section line and verify the next jump goes to a
    # top-level "# " section, not the next "## ".
    var subIdx = -1
    for i, line in state.lines:
      if line.startsWith("## "):
        subIdx = i
        break
    check subIdx >= 0

    state.selectedIndex = subIdx
    state.moveToNextSection()

    if state.selectedIndex != subIdx:
      check state.lines[state.selectedIndex].startsWith("# ")
      check not state.lines[state.selectedIndex].startsWith("## ")

  test "moveToNextSection stays put when no further section exists":
    let state = newHelpViewerState()

    # Find the last top-level section, then move past it.
    var lastSectionIdx = -1
    for i, line in state.lines:
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
    for i, line in state.lines:
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
    for i, line in state.lines:
      if line.startsWith("## "):
        subIdx = i
        break
    check subIdx >= 0

    state.selectedIndex = subIdx
    state.moveToPreviousSection()

    check state.selectedIndex < subIdx
    check state.lines[state.selectedIndex].startsWith("# ")
    check not state.lines[state.selectedIndex].startsWith("## ")

suite "HelpViewer - Search query":
  test "setSearchQuery sets the query":
    let state = newHelpViewerState()

    state.setSearchQuery("test")
    check state.searchQuery == "test"

  test "clearSearch clears the query":
    let state = newHelpViewerState()
    state.setSearchQuery("test")

    state.clearSearch()
    check state.searchQuery == ""

  test "hasSearchQuery returns true when query exists":
    let state = newHelpViewerState()
    state.setSearchQuery("test")

    check state.hasSearchQuery == true

  test "hasSearchQuery returns false when query is empty":
    let state = newHelpViewerState()

    check state.hasSearchQuery == false

  test "hasSearchQuery returns false after clearSearch":
    let state = newHelpViewerState()
    state.setSearchQuery("test")
    state.clearSearch()

    check state.hasSearchQuery == false

suite "HelpViewer - Line matching":
  test "isLineMatched returns true for matching line":
    let state = newHelpViewerState()
    state.setSearchQuery("Normal mode")

    # Find a line containing "Normal mode"
    var foundIndex = -1
    for i, line in state.lines:
      if "Normal mode" in line:
        foundIndex = i
        break

    check foundIndex >= 0
    check state.isLineMatched(foundIndex) == true

  test "isLineMatched is case insensitive":
    let state = newHelpViewerState()
    state.setSearchQuery("normal MODE")

    var foundIndex = -1
    for i, line in state.lines:
      if "Normal mode" in line:
        foundIndex = i
        break

    check foundIndex >= 0
    check state.isLineMatched(foundIndex) == true

  test "isLineMatched returns false for non-matching line":
    let state = newHelpViewerState()
    state.setSearchQuery("xyznonexistent123")

    check state.isLineMatched(0) == false

  test "isLineMatched returns false when no search query":
    let state = newHelpViewerState()

    check state.isLineMatched(0) == false

  test "isLineMatched returns false for negative index":
    let state = newHelpViewerState()
    state.setSearchQuery("test")

    check state.isLineMatched(-1) == false

  test "isLineMatched returns false for out of range index":
    let state = newHelpViewerState()
    state.setSearchQuery("test")

    check state.isLineMatched(state.lines.len) == false

suite "HelpViewer - Search forward":
  test "searchForward finds next matching line":
    let state = newHelpViewerState()
    state.setSearchQuery(":w")
    state.selectedIndex = 0

    let result = state.searchForward()
    check result.isSome
    check state.selectedIndex > 0
    check ":w" in state.lines[state.selectedIndex].toLowerAscii or
      ":W" in state.lines[state.selectedIndex]

  test "searchForward wraps around to beginning":
    let state = newHelpViewerState()
    state.setSearchQuery("Exiting")

    # Set selectedIndex to after the "Exiting" section
    state.selectedIndex = state.lines.high

    let result = state.searchForward()
    check result.isSome
    # Should wrap around and find "Exiting" near the beginning
    check state.selectedIndex < state.lines.high

  test "searchForward returns none when no match":
    let state = newHelpViewerState()
    state.setSearchQuery("xyznonexistent123456")
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
    state.setSearchQuery("mode")
    state.selectedIndex = state.lines.high

    let result = state.searchBackward()
    check result.isSome
    check state.selectedIndex < state.lines.high

  test "searchBackward wraps around to end":
    let state = newHelpViewerState()
    state.setSearchQuery("backup")
    state.selectedIndex = 0

    let result = state.searchBackward()
    check result.isSome
    # Should wrap around and find "jumps" near the end
    check state.selectedIndex > 0

  test "searchBackward returns none when no match":
    let state = newHelpViewerState()
    state.setSearchQuery("xyznonexistent123456")
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
    state.setSearchQuery("Exiting")
    state.selectedIndex = state.lines.high

    let result = state.searchFirst()
    check result.isSome
    # Should find "Exiting" near the beginning
    check state.selectedIndex < state.lines.high

  test "searchFirst returns none when no match":
    let state = newHelpViewerState()
    state.setSearchQuery("xyznonexistent123456")
    state.selectedIndex = 0

    let result = state.searchFirst()
    check result.isNone

  test "searchFirst returns none when no search query":
    let state = newHelpViewerState()

    let result = state.searchFirst()
    check result.isNone

  test "searchFirst always starts from line 0":
    let state = newHelpViewerState()
    state.setSearchQuery("# Exiting")
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
    check state.lines.contains("# Command mode")

  test "head group 1 (jump/shell/bg/man) is aligned to width 15":
    let state = newHelpViewerState()
    check state.lines.contains("number          - Jump to line number; e.g. :10")
    check state.lines.contains("! shell command - Shell command execution")
    check state.lines.contains(
      "bg              - Pause the editor and show the recent terminal output"
    )

  test "head group 2 (:e family) is aligned to width 11":
    let state = newHelpViewerState()
    check state.lines.contains("e filename  - Open file")
    check state.lines.contains(
      "e           - Reload current file (error if unsaved changes)"
    )
    check state.lines.contains("e! filename - Open file (discard unsaved changes)")

  test "head group 3 (:delete family) is aligned to width 21":
    let state = newHelpViewerState()
    check state.lines.contains(
      "%s/keyword1/keyword2/ - Replace text (normal mode only)"
    )
    check state.lines.contains(
      "delete                - Delete current line and copy to register"
    )

  test "head group 4 (buffers/windows) is aligned to width 15":
    let state = newHelpViewerState()
    check state.lines.contains("ls              - Display all buffers")
    check state.lines.contains("bd or bd number - Delete buffer")
    check state.lines.contains(
      "filetree path   - Toggle FileTree sidebar with specified root path"
    )

  test "head group 5 (theme/noh/stripwhitespace) is aligned to width 15":
    let state = newHelpViewerState()
    check state.lines.contains(
      "theme themeName - Change color theme; for example theme dark"
    )
    check state.lines.contains("noh             - Turn off search highlights")
    check state.lines.contains("stripwhitespace - Delete trailing spaces")

  test "bool set options block is aligned to the widest entry":
    let state = newHelpViewerState()
    # Short entry must be padded to match the longest entry
    # (`set highlightgitconflicttwocolor / set nohighlightgitconflicttwocolor (hgctc/nohgctc)`).
    check state.lines.contains(
      "set number / set nonumber (nu/nonu)                                                   - Show/hide line numbers"
    )
    # `set wrap` / `set scrollbar` have no short alias and so render without parens.
    check state.lines.contains(
      "set wrap / set nowrap                                                                 - Enable/disable line wrap"
    )
    check state.lines.contains(
      "set scrollbar / set noscrollbar                                                       - Enable/disable scrollbar"
    )
    # Longest entry sets the width; only one space before the dash.
    check state.lines.contains(
      "set highlightgitconflicttwocolor / set nohighlightgitconflicttwocolor (hgctc/nohgctc) - Use two-color (ours/theirs) conflict scheme"
    )

  test "value set options block is aligned to its own widest entry":
    let state = newHelpViewerState()
    # Example values now come from the canonical SetOptionTable (which also
    # feeds the executeSet error messages — so they say "scrollbarwidth=1" /
    # "tabstop=4" instead of the older help-only "=2").
    check state.lines.contains(
      "set scrollbarwidth=number       - Change scrollbar width; e.g. set scrollbarwidth=1"
    )
    check state.lines.contains(
      "set tabstop=number (ts)         - Change tab stop width; e.g. set tabstop=4"
    )
    check state.lines.contains(
      "set shiftwidth=number (sw)      - Change indent width; e.g. set shiftwidth=4"
    )
    check state.lines.contains(
      "set softtabstop=number (sts)    - Change soft tab stop width; e.g. set softtabstop=4"
    )
    check state.lines.contains(
      "set scrollairdrag=number (sad)  - Change smooth scroll air drag; e.g. set scrollairdrag=2.0"
    )

  test "trailing group (build/lspfold/lspformat) is aligned to width 9":
    let state = newHelpViewerState()
    check state.lines.contains("build     - Build the current buffer")
    check state.lines.contains("lspfold   - LSP Folding Range")
    check state.lines.contains("lspformat - LSP Document Formatting")

  test "trailing group (lsprestart/lspcallhierarchy) is aligned to width 24":
    let state = newHelpViewerState()
    check state.lines.contains(
      "lsprestart               - Restart the current LSP server"
    )
    check state.lines.contains(
      "lspcallhierarchyincoming - Show incoming calls (callers) at cursor"
    )

  test "trailing group (terminal) is aligned to width 16":
    let state = newHelpViewerState()
    check state.lines.contains(
      "terminal         - Open terminal emulator (default shell)"
    )
    check state.lines.contains("terminal command - Run command in terminal emulator")

  test "trailing single-entry groups render without padding":
    let state = newHelpViewerState()
    check state.lines.contains("help - Open this help")
    check state.lines.contains("quickrun - Quick run")
    check state.lines.contains(
      "conflictprev - Jump to previous git merge conflict block"
    )

  test "blank line separates Command mode section from Runtime Key Mapping":
    let state = newHelpViewerState()
    # The last Command-mode line, a blank line, then the next subsection header
    # must appear consecutively in the rendered output.
    let idx =
      state.lines.find("conflictprev - Jump to previous git merge conflict block")
    check idx >= 0
    check state.lines[idx + 1] == ""
    check state.lines[idx + 2] == "## Runtime Key Mapping"

suite "HelpViewer - Mode sections (snapshot)":
  ## Snapshot assertions for the per-mode `render*Section` procs in
  ## `help_generator`. Each suite test pins the section header plus a few
  ## representative entries (first/last/longest) so accidental drops, reorders,
  ## or column-width changes in the underlying `*Commands` tables fail the
  ## build. Update literals deliberately when content is intentionally changed.

  test "# Exiting section is aligned to width 5":
    let state = newHelpViewerState()
    check state.lines.contains("# Exiting")
    check state.lines.contains(":w    - Write file")
    check state.lines.contains(":q    - Quit")
    check state.lines.contains(":wqa! - Force quit all windows")
    check state.lines.contains(":cq   - Quit with non-zero exit code")

  test "# Changing modes section is aligned to width 6":
    let state = newHelpViewerState()
    check state.lines.contains("# Changing modes")
    check state.lines.contains("v      - Visual mode")
    check state.lines.contains("Ctrl-v - Visual block mode")
    check state.lines.contains("A      - Same as $a")

  test "# Normal mode section preserves representative entries":
    let state = newHelpViewerState()
    check state.lines.contains("# Normal mode")
    check state.lines.contains("h          - Go left")
    check state.lines.contains("gg         - Go to the first line")
    check state.lines.contains("dgN        - Delete previous search match")
    check state.lines.contains(
      "ca{ or ca} - Delete around curly brackets and enter insert mode"
    )

  test "# Visual mode section uses minWidth=7 padding":
    let state = newHelpViewerState()
    check state.lines.contains("# Visual mode")
    # natural max is 6 ("Ctrl-a"/"Ctrl-x"/"Ctrl-s"); minWidth pads to 7
    check state.lines.contains("d or x  - Delete text")
    check state.lines.contains("Ctrl-a  - Increase number under cursor")
    check state.lines.contains("Esc     - Go to Normal mode")

  test "# Replace mode section is aligned to width 9":
    let state = newHelpViewerState()
    check state.lines.contains("# Replace mode")
    check state.lines.contains("Esc       - Go to Normal mode")
    check state.lines.contains("Backspace - Undo")

  test "# Insert mode section is aligned to widest entry":
    let state = newHelpViewerState()
    check state.lines.contains("# Insert mode")
    check state.lines.contains(
      "Ctrl-e              - Insert the character which is below the cursor"
    )
    check state.lines.contains(
      "Ctrl-h or Backspace - Delete the character before the cursor"
    )
    check state.lines.contains("Esc                 - Go to Normal mode")

  test "# Backup mode section is aligned to width 5":
    let state = newHelpViewerState()
    check state.lines.contains("# Backup mode")
    check state.lines.contains("j     - Go down")
    check state.lines.contains("Enter - Open diff")
    check state.lines.contains("R     - Restore backup file")

  test "# Diff mode section is aligned to width 2":
    let state = newHelpViewerState()
    check state.lines.contains("# Diff mode")
    check state.lines.contains("j  - Go down")
    check state.lines.contains("gg - Go to the first line")
    check state.lines.contains("G  - Go to the last line")

  test "# References mode section is aligned to width 5":
    let state = newHelpViewerState()
    check state.lines.contains("# References mode")
    check state.lines.contains("Enter - Jump to the destination")
    check state.lines.contains("Esc   - Quit References mode")

  test "# Call hierarchy viewer mode section is aligned to width 5":
    let state = newHelpViewerState()
    check state.lines.contains("# Call hierarchy viewer mode")
    check state.lines.contains("Enter - Jump to the destination")
    check state.lines.contains("i     - Incoming call")
    check state.lines.contains("o     - Outgoing call")

  test "# Filer mode section is aligned to width 2":
    let state = newHelpViewerState()
    check state.lines.contains("# Filer mode")
    check state.lines.contains("j  - Go down")
    check state.lines.contains("D  - Delete file")
    check state.lines.contains("v  - Split window and open file or directory")

  test "# Register section lists patterns verbatim (no key/desc form)":
    let state = newHelpViewerState()
    check state.lines.contains("# Register")
    check state.lines.contains("\"-any key-yy")
    check state.lines.contains("\"-any key-di-any key")
    check state.lines.contains("\"-any key-ci-any key")

  test "# Terminal mode section has both sub-mode headers":
    let state = newHelpViewerState()
    check state.lines.contains("# Terminal mode")
    check state.lines.contains("## Terminal-Input sub-mode (default)")
    check state.lines.contains("## Terminal-Normal sub-mode")

  test "Terminal-Input sub-mode body lists Ctrl-\\ Ctrl-n switch":
    let state = newHelpViewerState()
    check state.lines.contains(
      "All keystrokes are forwarded to the running shell/command."
    )
    check state.lines.contains("Ctrl-\\ Ctrl-n - Switch to Terminal-Normal sub-mode")

  test "Terminal-Normal sub-mode body uses minWidth=2":
    let state = newHelpViewerState()
    check state.lines.contains("i  - Return to Terminal-Input sub-mode")
    check state.lines.contains("a  - Return to Terminal-Input sub-mode")
    check state.lines.contains(":  - Enter command mode")
