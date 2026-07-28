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
    check state.items[^1].len > 0

suite "HelpViewer - Line access":
  test "getLine returns line at valid index":
    let state = newHelpViewerState()

    let line = state.getLine(0)
    check line == state.items[0]

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
    # state.items[0] is "# Exiting" — the first top-level section header.
    check state.items[0].startsWith("# ")
    check state.selectedIndex == 0

    state.moveToNextSection()
    check state.selectedIndex > 0
    check state.items[state.selectedIndex].startsWith("# ")
    check not state.items[state.selectedIndex].startsWith("## ")

  test "moveToNextSection skips '## ' sub-section headers":
    let state = newHelpViewerState()

    # Land on a "## " sub-section line and verify the next jump goes to a
    # top-level "# " section, not the next "## ".
    var subIdx = -1
    for i, line in state.items:
      if line.startsWith("## "):
        subIdx = i
        break
    check subIdx >= 0

    state.selectedIndex = subIdx
    state.moveToNextSection()

    if state.selectedIndex != subIdx:
      check state.items[state.selectedIndex].startsWith("# ")
      check not state.items[state.selectedIndex].startsWith("## ")

  test "moveToNextSection stays put when no further section exists":
    let state = newHelpViewerState()

    # Find the last top-level section, then move past it.
    var lastSectionIdx = -1
    for i, line in state.items:
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
    for i, line in state.items:
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
    for i, line in state.items:
      if line.startsWith("## "):
        subIdx = i
        break
    check subIdx >= 0

    state.selectedIndex = subIdx
    state.moveToPreviousSection()

    check state.selectedIndex < subIdx
    check state.items[state.selectedIndex].startsWith("# ")
    check not state.items[state.selectedIndex].startsWith("## ")

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
    for i, line in state.items:
      if "Normal mode" in line:
        foundIndex = i
        break

    check foundIndex >= 0
    check state.isLineMatched(foundIndex) == true

  test "isLineMatched is case insensitive":
    let state = newHelpViewerState()
    state.setSearchQuery("normal MODE")

    var foundIndex = -1
    for i, line in state.items:
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

    check state.isLineMatched(state.items.len) == false

suite "HelpViewer - Search forward":
  test "searchForward finds next matching line":
    let state = newHelpViewerState()
    state.setSearchQuery(":w")
    state.selectedIndex = 0

    let result = state.searchForward()
    check result.isSome
    check state.selectedIndex > 0
    check ":w" in state.items[state.selectedIndex].toLowerAscii or
      ":W" in state.items[state.selectedIndex]

  test "searchForward wraps around to beginning":
    let state = newHelpViewerState()
    state.setSearchQuery("Exiting")

    # Set selectedIndex to after the "Exiting" section
    state.selectedIndex = state.items.high

    let result = state.searchForward()
    check result.isSome
    # Should wrap around and find "Exiting" near the beginning
    check state.selectedIndex < state.items.high

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
    state.selectedIndex = state.items.high

    let result = state.searchBackward()
    check result.isSome
    check state.selectedIndex < state.items.high

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
    state.selectedIndex = state.items.high

    let result = state.searchFirst()
    check result.isSome
    # Should find "Exiting" near the beginning
    check state.selectedIndex < state.items.high

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
    check state.items.contains("# Command mode")

  test "head group 1 (jump/shell/bg/man) is aligned to width 15":
    let state = newHelpViewerState()
    check state.items.contains("number          - Jump to line number; e.g. :10")
    check state.items.contains("! shell command - Shell command execution")
    check state.items.contains(
      "bg              - Pause the editor and show the recent terminal output"
    )

  test "head group 2 (:e family) is aligned to width 11":
    let state = newHelpViewerState()
    check state.items.contains("e filename  - Open file")
    check state.items.contains(
      "e           - Reload current file (error if unsaved changes)"
    )
    check state.items.contains("e! filename - Open file (discard unsaved changes)")

  test "head group 3 (:delete family) is aligned to width 21":
    let state = newHelpViewerState()
    check state.items.contains(
      "%s/keyword1/keyword2/ - Replace text (normal mode only)"
    )
    check state.items.contains(
      "delete                - Delete current line and copy to register"
    )

  test "head group 4 (buffers/windows) is aligned to width 15":
    let state = newHelpViewerState()
    check state.items.contains("ls              - Display all buffers")
    check state.items.contains("bd or bd number - Delete buffer")
    check state.items.contains(
      "filetree path   - Toggle FileTree sidebar with specified root path"
    )

  test "head group 5 (theme/noh/stripwhitespace) is aligned to width 15":
    let state = newHelpViewerState()
    # `description` is a structured `Description` with inline-code
    # segments for the howtouse.md renderer; `toPlainText` strips the
    # code-span markers before the TUI sees the line, so the rendered
    # prose has no `` ` `` glyphs.
    check state.items.contains("theme themeName - Change color theme; e.g. theme dark")
    check state.items.contains("noh             - Turn off search highlights")
    check state.items.contains("stripwhitespace - Delete trailing spaces")

  test "bool set options block is aligned to the widest entry":
    let state = newHelpViewerState()
    # Short entry must be padded to match the longest entry
    # (`set highlightgitconflicttwocolor / set nohighlightgitconflicttwocolor (hgctc/nohgctc)`).
    check state.items.contains(
      "set number / set nonumber (nu/nonu)                                                   - Show/hide line numbers"
    )
    # `set wrap` / `set scrollbar` have no short alias and so render without parens.
    check state.items.contains(
      "set wrap / set nowrap                                                                 - Enable/disable line wrap"
    )
    check state.items.contains(
      "set scrollbar / set noscrollbar                                                       - Enable/disable scrollbar"
    )
    # Longest entry sets the width; only one space before the dash.
    check state.items.contains(
      "set highlightgitconflicttwocolor / set nohighlightgitconflicttwocolor (hgctc/nohgctc) - Use two-color (ours/theirs) conflict scheme; disable for single-color fallback"
    )

  test "value set options block is aligned to its own widest entry":
    let state = newHelpViewerState()
    # Example values now come from the canonical SetOptionTable (which also
    # feeds the executeSet error messages — so they say "scrollbarwidth=1" /
    # "tabstop=4" instead of the older help-only "=2").
    check state.items.contains(
      "set scrollbarwidth=number       - Change scrollbar width (0 = hidden); e.g. set scrollbarwidth=1"
    )
    check state.items.contains(
      "set tabstop=number (ts)         - Change tab stop width; e.g. set tabstop=4"
    )
    check state.items.contains(
      "set shiftwidth=number (sw)      - Change indent width; e.g. set shiftwidth=4"
    )
    check state.items.contains(
      "set softtabstop=number (sts)    - Change soft tab stop width; e.g. set softtabstop=4"
    )
    check state.items.contains(
      "set scrollairdrag=number (sad)  - Change smooth scroll air drag; e.g. set scrollairdrag=2.0"
    )

  test "trailing group (build/lspfold/lspformat) is aligned to width 9":
    let state = newHelpViewerState()
    check state.items.contains("build     - Build the current buffer")
    check state.items.contains("lspfold   - LSP Folding Range")
    check state.items.contains("lspformat - LSP Document Formatting")

  test "trailing group (lsprestart/lspcallhierarchy) is aligned to width 24":
    let state = newHelpViewerState()
    check state.items.contains(
      "lsprestart               - Restart the current LSP server"
    )
    check state.items.contains(
      "lspcallhierarchyincoming - Show incoming calls (callers) at cursor"
    )

  test "trailing group (terminal) is aligned to width 16":
    let state = newHelpViewerState()
    check state.items.contains(
      "terminal         - Open terminal emulator (default shell)"
    )
    check state.items.contains("terminal command - Run command in terminal emulator")

  test "trailing single-entry groups render without padding":
    let state = newHelpViewerState()
    check state.items.contains("help - Open this help")
    check state.items.contains("quickrun - Quick run")
    check state.items.contains(
      "conflictprev - Jump to previous git merge conflict block"
    )

  test "blank line separates Command mode section from Runtime Key Mapping":
    let state = newHelpViewerState()
    # The last Command-mode line, a blank line, then the next subsection header
    # must appear consecutively in the rendered output.
    let idx =
      state.items.find("conflictprev - Jump to previous git merge conflict block")
    check idx >= 0
    check state.items[idx + 1] == ""
    check state.items[idx + 2] == "## Runtime Key Mapping"

suite "HelpViewer - Mode sections (snapshot)":
  ## Snapshot assertions for the per-mode `render*Section` procs in
  ## `help_generator`. Each suite test pins the section header plus a few
  ## representative entries (first/last/longest) so accidental drops, reorders,
  ## or column-width changes in the underlying `*Commands` tables fail the
  ## build. Update literals deliberately when content is intentionally changed.

  test "# Exiting section is aligned to width 5":
    let state = newHelpViewerState()
    check state.items.contains("# Exiting")
    check state.items.contains(":w    - Write file")
    check state.items.contains(":q    - Quit")
    check state.items.contains(":wqa! - Force write and quit all windows")
    check state.items.contains(":cq   - Quit with non-zero exit code")

  test "# Changing modes section is aligned to width 6":
    let state = newHelpViewerState()
    check state.items.contains("# Changing modes")
    check state.items.contains("v      - Visual mode")
    check state.items.contains("Ctrl-v - Visual block mode")
    check state.items.contains("A      - Same as $a")

  test "# Normal mode section preserves representative entries":
    let state = newHelpViewerState()
    check state.items.contains("# Normal mode")
    check state.items.contains("h          - Go left")
    check state.items.contains("gg         - Go to the first line")
    check state.items.contains("dgN        - Delete previous search match")
    check state.items.contains(
      "ca{ or ca} - Delete around curly brackets and enter insert mode"
    )

  test "# Visual mode section uses minWidth=7 padding":
    let state = newHelpViewerState()
    check state.items.contains("# Visual mode")
    # natural max is 6 ("Ctrl-a"/"Ctrl-x"/"Ctrl-s"); minWidth pads to 7
    check state.items.contains("d or x  - Delete text")
    check state.items.contains("Ctrl-a  - Increase number under cursor")
    check state.items.contains("Esc     - Go to Normal mode")

  test "# Replace mode section is aligned to width 9":
    let state = newHelpViewerState()
    check state.items.contains("# Replace mode")
    check state.items.contains("Esc       - Go to Normal mode")
    check state.items.contains("Backspace - Undo")

  test "# Insert mode section is aligned to widest entry":
    let state = newHelpViewerState()
    check state.items.contains("# Insert mode")
    check state.items.contains(
      "Ctrl-e              - Insert the character which is below the cursor"
    )
    check state.items.contains(
      "Ctrl-h or Backspace - Delete the character before the cursor"
    )
    check state.items.contains("Esc                 - Go to Normal mode")

  test "# Backup mode section is aligned to width 5":
    let state = newHelpViewerState()
    check state.items.contains("# Backup mode")
    check state.items.contains("j     - Go down")
    check state.items.contains("Enter - Open diff")
    check state.items.contains("R     - Restore backup file")

  test "# Diff mode section is aligned to width 2":
    let state = newHelpViewerState()
    check state.items.contains("# Diff mode")
    check state.items.contains("j  - Go down")
    check state.items.contains("gg - Go to the first line")
    check state.items.contains("G  - Go to the last line")

  test "# References mode section is aligned to width 5":
    let state = newHelpViewerState()
    check state.items.contains("# References mode")
    check state.items.contains("Enter - Jump to the destination")
    check state.items.contains("Esc   - Quit References mode")

  test "# Call hierarchy viewer mode section is aligned to width 5":
    let state = newHelpViewerState()
    check state.items.contains("# Call hierarchy viewer mode")
    check state.items.contains("Enter - Jump to the destination")
    check state.items.contains("i     - Incoming call")
    check state.items.contains("o     - Outgoing call")

  test "# Filer mode section is aligned to width 2":
    let state = newHelpViewerState()
    check state.items.contains("# Filer mode")
    check state.items.contains("j  - Go down")
    check state.items.contains("D  - Delete file")
    check state.items.contains("v  - Split window and open file or directory")

  test "# Register section uses the kbd-group syntax + description form":
    # The widest entry is `" any cl or " any s` (19 chars), which sets the
    # alignment for the entire group. Switching from the old hyphen-only
    # `seq[string]` to a `HelpGroup` means each row now renders as
    # `syntax  - description`, consistent with every other mode section.
    let state = newHelpViewerState()
    check state.items.contains("# Register")
    check state.items.contains(
      "\" any yy".alignLeft(19) & " - Yank a line to a named register"
    )
    check state.items.contains(
      "\" any di any".alignLeft(19) & " - Delete inside to a named register"
    )
    check state.items.contains(
      "\" any cl or \" any s - Change a character to a named register"
    )

  test "# Terminal mode section has both sub-mode headers":
    let state = newHelpViewerState()
    check state.items.contains("# Terminal mode")
    check state.items.contains("## Terminal-Input sub-mode (default)")
    check state.items.contains("## Terminal-Normal sub-mode")

  test "Terminal-Input sub-mode body lists Ctrl-\\ Ctrl-n switch":
    let state = newHelpViewerState()
    check state.items.contains(
      "All keystrokes are forwarded to the running shell/command."
    )
    check state.items.contains("Ctrl-\\ Ctrl-n - Switch to Terminal-Normal sub-mode")

  test "Terminal-Normal sub-mode body uses minWidth=2":
    let state = newHelpViewerState()
    check state.items.contains("i  - Return to Terminal-Input sub-mode")
    check state.items.contains("a  - Return to Terminal-Input sub-mode")
    check state.items.contains(":  - Enter command mode")
