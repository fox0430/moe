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

## Unit tests for the pure rendering helpers in `help_markdown.nim`.
## The howtouse.md sync test in `test_howtouse_docs_sync.nim` already
## covers end-to-end regeneration; this file pins the behavior of the
## individual helpers (especially `tokenizeKey`'s `any` / modifier
## handling) so Phase 2 mode-key tables can rely on it.

import std/[strutils, unittest]

import ../src/moepkg/[help_generator, help_markdown]

suite "help_markdown.tokenizeKey":
  test "single character expands per-char":
    check tokenizeKey("h") == @["h"]
    check tokenizeKey("gg") == @["g", "g"]
    check tokenizeKey("ciw") == @["c", "i", "w"]

  test "colon-prefixed command splits the colon out":
    check tokenizeKey(":w") == @[":", "w"]
    check tokenizeKey(":cq") == @[":", "c", "q"]

  test "named modifier prefixes split on hyphen":
    check tokenizeKey("Ctrl-u") == @["Ctrl", "u"]
    check tokenizeKey("Alt-x") == @["Alt", "x"]
    check tokenizeKey("Shift-F4") == @["Shift", "F4"]

  test "multi-token sequences split on whitespace":
    check tokenizeKey("Ctrl-w k") == @["Ctrl", "w", "k"]
    check tokenizeKey("g e") == @["g", "e"]

  test "special tokens are preserved as a whole":
    check tokenizeKey("Page Up") == @["Page Up"]
    check tokenizeKey("Esc") == @["Esc"]
    check tokenizeKey("Backspace") == @["Backspace"]

  test "overlapping special tokens prefer the longest match":
    # `Esc` is a prefix of `Escape`; the greedy scan must pick the longer
    # whole-word match instead of consuming `Esc` and leaving `ape`.
    check tokenizeKey("Escape") == @["Escape"]
    check tokenizeKey("Escape Enter") == @["Escape", "Enter"]

  test "any placeholder normalizes to canonical 'Any key'":
    # Source-data variants used in `help_generator.nim` for Phase 2 tables:
    # `"q any"`, `"yt any"`, `"@ any"`. The standalone `"any"` form (no
    # other tokens) is also accepted.
    check tokenizeKey("any") == @["Any key"]
    check tokenizeKey("q any") == @["q", "Any key"]
    check tokenizeKey("yt any") == @["y", "t", "Any key"]
    check tokenizeKey("any key") == @["Any key"]

suite "help_markdown.renderKbdKeysCell":
  test "single key wraps in kbd with bold":
    check renderKbdKeysCell("h") == "<kbd>**h**</kbd>"

  test "concatenated keys join with space":
    check renderKbdKeysCell("gg") == "<kbd>**g**</kbd> <kbd>**g**</kbd>"

  test "' or ' alternations join with uppercase OR":
    check renderKbdKeysCell("h or Left") == "<kbd>**h**</kbd> OR <kbd>**Left**</kbd>"

suite "help_markdown.renderBacktickCell":
  test "wraps syntax in backticks":
    check renderBacktickCell("bd") == "`bd`"

  test "' or ' alternations wrap each side separately":
    check renderBacktickCell("bd or bd number") == "`bd` or `bd number`"

suite "help_markdown.escapeMdCell":
  test "pipe is escaped":
    check escapeMdCell("a|b") == "a\\|b"

  test "backslash is doubled":
    check escapeMdCell("a\\b") == "a\\\\b"

  test "newlines become spaces":
    check escapeMdCell("a\nb") == "a b"
    check escapeMdCell("a\r\nb") == "a  b"

  test "ordinary characters pass through":
    check escapeMdCell("Change scrollbar width (0 = hidden)") ==
      "Change scrollbar width (0 = hidden)"

suite "help_markdown.renderRegisterTable":
  test "starts with the kbd two-column header":
    let table = renderRegisterTable()
    check table.startsWith("| Keys | Description |\n|:---|:---|\n")

  test "first data row pairs the canonical yy pattern with its description":
    # `" any yy` must normalize the `any` placeholder to `Any key` (via
    # `tokenizeKey`) and emit the description column the source `HelpEntry`
    # carries, so markdown readers don't lose the description text that the
    # old single-column table dropped.
    let table = renderRegisterTable()
    let firstRow = table.splitLines()[2]
    check firstRow ==
      "| <kbd>**\"**</kbd> <kbd>**Any key**</kbd> <kbd>**y**</kbd> <kbd>**y**</kbd> | " &
      "Yank a line to a named register |"

  test "'di any' textobject keeps both 'Any key' tokens on the row":
    # `" any di any` is the one pattern with `any` appearing twice — once
    # for the register name and once for the textobject target. Both must
    # tokenize as the canonical `Any key` so neither side decays to per-char
    # expansion.
    let table = renderRegisterTable()
    check (
      "| <kbd>**\"**</kbd> <kbd>**Any key**</kbd> <kbd>**d**</kbd> <kbd>**i**</kbd> " &
      "<kbd>**Any key**</kbd> | Delete inside to a named register |"
    ) in table

  test "'cl or s' alternation joins with OR":
    # Both halves are register-name patterns sharing one description, so
    # they collapse into a single row via the ` or ` → ` OR ` split that
    # `renderKbdKeysCell` already handles for other modes.
    let table = renderRegisterTable()
    check (
      "| <kbd>**\"**</kbd> <kbd>**Any key**</kbd> <kbd>**c**</kbd> <kbd>**l**</kbd> OR " &
      "<kbd>**\"**</kbd> <kbd>**Any key**</kbd> <kbd>**s**</kbd> | " &
      "Change a character to a named register |"
    ) in table

suite "help_markdown.renderKbdHelpGroup":
  test "Visual mode 'd or x' alternation joins with OR":
    let table = renderKbdHelpGroup(VisualModeCommands)
    check table.startsWith("| Keys | Description |\n|:---|:---|\n")
    check "| <kbd>**d**</kbd> OR <kbd>**x**</kbd> | Delete text |" in table

  test "Insert mode 'Ctrl-h or Backspace' expands modifier and OR":
    let table = renderKbdHelpGroup(InsertModeCommands)
    check (
      "| <kbd>**Ctrl**</kbd> <kbd>**h**</kbd> OR <kbd>**Backspace**</kbd> | " &
      "Delete the character before the cursor |"
    ) in table

  test "Terminal-Input 'Ctrl-\\ Ctrl-n' splits modifiers and escapes backslash":
    # The backslash token must be emitted as `\\` inside the kbd cell so
    # markdown renders it as a literal `\`. Without the escape, `**\**`
    # is parsed as `*<em>*</em>` and the backslash is silently dropped.
    let table = renderKbdHelpGroup(TerminalInputCommands)
    check (
      "| <kbd>**Ctrl**</kbd> <kbd>**\\\\**</kbd> <kbd>**Ctrl**</kbd> <kbd>**n**</kbd> | " &
      "Switch to Terminal-Normal sub-mode |"
    ) in table

  test "row count equals header(2) + entries.len":
    # NormalModeCommands is the largest group — pin the row count so a
    # future addition without a regenerate is caught by the unit test
    # (the doc-sync test catches it too, but this layer fails faster).
    let lines = renderKbdHelpGroup(NormalModeCommands).splitLines()
    check lines.len == NormalModeCommands.entries.len + 2 + 1
    check lines[^1] == ""
