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

## Unit tests for the structured `Description` type and its renderers.
## Existing call-site tests (`test_command_completion.nim`,
## `test_help_viewer.nim`) cover end-to-end behavior; this file pins the
## escape grammar (`\\` / `` \` ``) and the round-trip between
## `parseDescription` and `toMarkdownCell`.

import std/unittest

import ../src/moepkg/help_description

suite "help_description.parseDescription":
  test "plain text becomes a single dskText segment":
    let d = parseDescription("Show line numbers")
    check d.len == 1
    check d[0].kind == dskText
    check d[0].text == "Show line numbers"

  test "paired backticks become a dskCode segment":
    let d = parseDescription("Use `:q!` to force quit")
    check d.len == 3
    check d[0] == DescSegment(kind: dskText, text: "Use ")
    check d[1] == DescSegment(kind: dskCode, text: ":q!")
    check d[2] == DescSegment(kind: dskText, text: " to force quit")

  test "unmatched trailing backtick is kept as literal text":
    let d = parseDescription("a `b")
    check d.len == 1
    check d[0].kind == dskText
    check d[0].text == "a `b"

  test "\\\\ escapes to a single backslash in text":
    let d = parseDescription("path\\\\to\\\\file")
    check d.len == 1
    check d[0] == DescSegment(kind: dskText, text: "path\\to\\file")

  test "\\` escapes to a literal backtick in text (no code span opened)":
    let d = parseDescription("literal \\` here")
    check d.len == 1
    check d[0] == DescSegment(kind: dskText, text: "literal ` here")

  test "unrecognized \\X passes both characters through":
    # Defensive: existing data has no `\` chars, but if any appear with
    # a non-escape follower they should round-trip rather than vanish.
    let d = parseDescription("a\\nb")
    check d.len == 1
    check d[0].text == "a\\nb"

  test "escape inside text segment does not interfere with adjacent code":
    let d = parseDescription("pre \\` mid `code` post")
    check d.len == 3
    check d[0] == DescSegment(kind: dskText, text: "pre ` mid ")
    check d[1] == DescSegment(kind: dskCode, text: "code")
    check d[2] == DescSegment(kind: dskText, text: " post")

suite "help_description.toPlainText":
  test "drops code-span markers, keeps segment text":
    let d = parseDescription("Highlight (`#RRGGBB`, `#RGB`)")
    check toPlainText(d) == "Highlight (#RRGGBB, #RGB)"

  test "escaped backtick survives as a literal":
    let d = parseDescription("a \\` b")
    check toPlainText(d) == "a ` b"

suite "help_description.toMarkdownCell":
  test "code segments are re-wrapped in backticks":
    let d = parseDescription("Highlight (`#RRGGBB`)")
    check toMarkdownCell(d) == "Highlight (`#RRGGBB`)"

  test "literal backtick in text is escaped as \\`":
    let d = parseDescription("a \\` b")
    check toMarkdownCell(d) == "a \\` b"

  test "pipe in text is escaped":
    let d = parseDescription("left|right")
    check toMarkdownCell(d) == "left\\|right"

  test "backslash in text is doubled":
    let d = parseDescription("a\\\\b")
    check toMarkdownCell(d) == "a\\\\b"

  test "newline in text flattens to space":
    let d = parseDescription("a\nb")
    check toMarkdownCell(d) == "a b"

suite "help_description.escapeMdCell":
  test "shares per-char rules with toMarkdownCell text branch":
    check escapeMdCell("a|b") == "a\\|b"
    check escapeMdCell("a\\b") == "a\\\\b"
    check escapeMdCell("a\nb") == "a b"
    check escapeMdCell("plain") == "plain"

  test "leaves backticks alone (kbd tokens render them as code spans)":
    check escapeMdCell("`") == "`"

suite "help_description.addStr":
  test "appends parsed segments preserving code spans":
    var d = parseDescription("base")
    d.addStr " (alias: `x`)"
    check d.len == 4
    check d[0] == DescSegment(kind: dskText, text: "base")
    check d[1] == DescSegment(kind: dskText, text: " (alias: ")
    check d[2] == DescSegment(kind: dskCode, text: "x")
    check d[3] == DescSegment(kind: dskText, text: ")")
