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

## Invariant tests for `CommandLineCommandTable`. These guard the conventions
## that other modules (loadDefaultConfig / CommandNameTable / CommandDescriptions
## / help rendering) silently depend on.

import std/[unittest, tables, options]

import ../src/moepkg/command_line_commands
import ../src/moepkg/command_line/types

suite "CommandLineCommandTable invariants":
  test "exactly one canonical-long spec per action":
    var counts: Table[CommandLineAction, int]
    for spec in CommandLineCommandTable:
      if spec.isCanonicalLong and spec.action.isSome:
        counts.mgetOrPut(spec.action.get, 0).inc
        counts[spec.action.get] = counts[spec.action.get]
    for action, n in counts.pairs:
      check n == 1

  test "every action used in the table has a canonical-long spec":
    var seen: Table[CommandLineAction, bool]
    var canonical: Table[CommandLineAction, bool]
    for spec in CommandLineCommandTable:
      if spec.action.isSome:
        seen[spec.action.get] = true
        if spec.isCanonicalLong:
          canonical[spec.action.get] = true
    for action in seen.keys:
      check action in canonical

  test "action.isNone entries have empty completionDescription":
    ## Otherwise the loadDefaultConfig / CommandDescriptions key sets would
    ## diverge (loadDefaultConfig filters on `action.isSome and desc.len > 0`,
    ## CommandDescriptions filters on `desc.len > 0` only).
    for spec in CommandLineCommandTable:
      if spec.action.isNone:
        check spec.completionDescription.len == 0

  test "isCanonicalLong=false action.isNone has at most a help entry":
    ## Display-only `q!` / `wqa!` etc. variants must not be flagged as the
    ## canonical-long target — they're not real aliases.
    for spec in CommandLineCommandTable:
      if spec.action.isNone:
        check not spec.isCanonicalLong

  test "names are unique":
    var seen: Table[string, int]
    for spec in CommandLineCommandTable:
      check spec.name notin seen
      seen[spec.name] = 1

  test "findCommandLineCommand returns each spec by name":
    for spec in CommandLineCommandTable:
      let found = findCommandLineCommand(spec.name)
      check found.isSome
      check found.get.name == spec.name

  test "findCommandLineCommand returns none for unknown name":
    check findCommandLineCommand("definitely-not-a-real-command").isNone

  test "completionDescription matches the primary helpEntry wording":
    ## The first helpEntry is the canonical primary-usage line shown in the
    ## help viewer. When the spec also surfaces a completionDescription
    ## (i.e. shows up in the completion popup), the two must use the same
    ## wording so users see one consistent description for the command.
    ## Extended-usage variants (helpEntries[1..]) — e.g. `e filename` vs `e`
    ## — are allowed to carry their own descriptions.
    for spec in CommandLineCommandTable:
      if spec.completionDescription.len == 0:
        continue
      if spec.helpEntries.len == 0:
        continue
      check spec.helpEntries[0].description == spec.completionDescription
