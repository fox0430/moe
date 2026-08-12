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

## Verify that `documents/howtouse.md` is in sync with the auto-gen output
## produced by `tools/gen_howtouse_docs.nim`. Calls the generator in-process
## (no subprocess, no file mutation) and compares the result with the
## checked-in file; any diff means a command-line command, set option, or
## help entry changed without running `nimble gendocs`.

import std/[options, sets, unittest]

import ../tools/gen_howtouse_docs
import ../src/moepkg/[command_line_commands, help_generator]
import ../src/moepkg/help_markdown {.all.}

suite "howtouse.md auto-gen sync":
  test "regenerating produces no diff":
    let original = readFile(DocsPath)
    var regenerated = ""
    var regenOk = false
    try:
      regenerated = regenerateHowtouseDocs(original)
      regenOk = true
    except CatchableError as e:
      # Most common cause: someone hand-edited howtouse.md and removed or
      # typo'd one of the `<!-- AUTO-GEN:start … -->` / `:end` markers.
      # Surface a readable hint instead of a bare traceback.
      echo "documents/howtouse.md has malformed AUTO-GEN markers:"
      echo "  ", e.msg
      echo "Restore the marker pair, then run `nimble gendocs` to regenerate."

    check regenOk
    if regenOk:
      if original != regenerated:
        echo "documents/howtouse.md is out of sync with its source data."
        echo "Run `nimble gendocs` and commit the result."
      check original == regenerated

  test "every helpEntries-bearing spec is rendered in some section":
    # If a new `CommandLineCommandSpec` ships with `helpEntries` but isn't
    # added to any of the section name lists in `help_markdown.nim`, the
    # diff test above won't catch it — both the regen and the on-disk
    # markdown would be equally missing the new command. Verify here that
    # the union of section name lists covers every spec with non-empty
    # `helpEntries`, regardless of `isCanonicalLong` (the Exiting block
    # uses alias names like `q!` / `wqa` — non-canonical-long entries with
    # helpEntries are first-class citizens of howtouse.md).
    let covered = AllHowtouseHelpNames.toHashSet
    var missing: seq[string] = @[]
    for spec in CommandLineCommandTable:
      if spec.helpEntries.len == 0:
        continue
      if spec.name notin covered:
        missing.add spec.name
    if missing.len > 0:
      echo "These specs have helpEntries but aren't listed in any howtouse.md"
      echo "section (Exiting/CommandMode*/RuntimeKeyMap):"
      for n in missing:
        echo "  - ", n
      echo "Add each name to the appropriate list in help_markdown.nim."
    check missing.len == 0

  test "every name in howtouse.md section lists matches a real spec":
    # Reverse direction of the previous test. The section name lists in
    # `help_markdown.nim` are hand-curated; a typo (`"bnxet"` instead of
    # `"bnext"`) makes `lookupHelpEntries` return `@[]` silently, dropping
    # that row from the markdown. The diff test wouldn't catch this either
    # — both regenerated output and on-disk file would be equally missing
    # the row — so verify here that every name in `AllHowtouseHelpNames`
    # resolves to a spec carrying at least one help entry.
    var unresolved: seq[string] = @[]
    var empty: seq[string] = @[]
    for name in AllHowtouseHelpNames:
      let spec = findCommandLineCommand(name)
      if spec.isNone:
        unresolved.add name
      elif spec.get.helpEntries.len == 0:
        empty.add name
    if unresolved.len > 0:
      echo "These names in help_markdown.nim section lists don't match any"
      echo "spec in CommandLineCommandTable (likely a typo):"
      for n in unresolved:
        echo "  - ", n
    if empty.len > 0:
      echo "These names resolve to a spec but its helpEntries is empty"
      echo "(the row would silently vanish from howtouse.md):"
      for n in empty:
        echo "  - ", n
    check unresolved.len == 0
    check empty.len == 0

  test "TUI help and howtouse.md cover the same set of Exiting commands":
    # The two lists may order commands differently, but the covered command
    # set must match. An omission in one (e.g. `:qa` was previously absent
    # from TUI help) would silently drop the command from that doc, and
    # neither the diff test nor the coverage tests catch it.
    check toHashSet(help_generator.ExitingHelpNames) ==
      toHashSet(help_markdown.ExitingHelpNames)
