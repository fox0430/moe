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

## Drift detection around the command tables in `key_bindings/commands.nim`
## (cmd-name → description), in two directions:
##
## * per-mode binding tables (key → cmd-name) — every command name bound in any
##   mode must be registered through `registerAllCommands`, or the binding
##   resolves to nothing at runtime.
## * the hand-written `#### Available commands` tables in `documents/
##   configfile.md` — a command absent from them cannot be discovered by anyone
##   writing `[KeyBindings]`, and a description that no longer matches sends
##   readers after the wrong behaviour. Nothing else guards those tables: they
##   sit outside the `AUTO-GEN` regions checked by `test_configfile_docs_sync`.
##
## Scope: command names and their descriptions. Which `#####` section a
## command is listed under is not checked, and neither is
## `help_generator.nim`'s `syntax:` / `description:` text — that pairing has
## its own cross-check in `test_help_keybinding_sync`.

import std/[algorithm, sequtils, sets, strutils, tables, unittest]

import ../tools/gen_config_docs
import ../src/moepkg/command_config
import ../src/moepkg/key_bindings/normal_bindings {.all.}
import ../src/moepkg/key_bindings/insert_bindings {.all.}
import ../src/moepkg/key_bindings/visual_bindings {.all.}
import ../src/moepkg/key_bindings/commands {.all.}

proc registeredCommands(): Table[string, string] =
  ## Every name `[KeyBindings]` can bind, mapped to its description.
  for entry in MotionCommands:
    result[entry.name] = entry.desc
  for entry in ActionCommands:
    result[entry.name] = entry.desc
  for entry in CustomCommands:
    result[entry.name] = entry.desc
  for entry in ModeSwitchCommands:
    result[entry.name] = entry.desc
  for entry in OverlaySwitchCommands:
    result[entry.name] = entry.desc
  for entry in OperatorPendingCommands:
    result[entry.name] = entry.desc
  for alias in keyMappableCommandModeAliases:
    # `registerCommandModeAliases` skips an alias whose name is already a
    # registered command, so that command keeps the name (e.g. "save").
    if result.hasKey(alias.name):
      continue
    # The generated description ends in " (:<name>)"; the docs table drops it
    # because its own heading already says these are Command mode names.
    var description = alias.description
    description.removeSuffix(" (:" & alias.name & ")")
    result[alias.name] = description

iterator documentedRows(): tuple[name, description: string] =
  ## Rows of the `#### Available commands` tables in configfile.md. The region
  ## runs to the next heading of any other level; one cell may hold several
  ## aliases for the same command ("q / quit"), each yielded separately.
  const
    HeaderCells = ["Command", "Alias"]
    Region = "#### Available commands"
    SubHeading = "#####"
  var inRegion = false
  for line in readFile(DocsPath).splitLines():
    if not inRegion:
      inRegion = line.startsWith(Region)
      continue
    if line.startsWith("#") and not line.startsWith(SubHeading):
      break
    if not line.startsWith("| "):
      continue
    let columns = line.split('|')
    if columns.len < 3:
      continue
    let cell = columns[1].strip()
    # Skip the header row and the `|:----|` alignment row.
    if cell.len == 0 or cell in HeaderCells or cell.startsWith("-") or
        cell.startsWith(":"):
      continue
    for name in cell.split('/'):
      yield (name.strip(), columns[2].strip())

proc documentedCommands(): Table[string, string] =
  for row in documentedRows():
    result[row.name] = row.description

proc names(commands: Table[string, string]): HashSet[string] =
  for name in commands.keys:
    result.incl name

proc report(label: string, entries: HashSet[string]): int =
  var sorted = toSeq(entries)
  sort(sorted)
  for entry in sorted:
    echo "  ", label, ": ", entry
  sorted.len

suite "key bindings — command name drift detection":
  test "every binding cmd-name resolves to a known command":
    let registered = registeredCommands().names

    let bindingGroups = {
      "Normal": @NormalBindings,
      "InsertReplace": @InsertReplaceBindings,
      "SharedVisual": @SharedVisualBindings,
      "VisualOnly": @VisualOnlyBindings,
      "VisualBlockOnly": @VisualBlockOnlyBindings,
    }

    var missing: seq[string]
    for (groupName, bindings) in bindingGroups:
      for (key, cmd) in bindings:
        if cmd notin registered:
          missing.add(groupName & ": " & key & " → " & cmd)

    for entry in missing:
      echo "  unregistered: ", entry
    check missing.len == 0

  test "every command name is documented in configfile.md":
    let
      registered = registeredCommands().names
      documented = documentedCommands().names

    # Both directions: an undocumented command is undiscoverable, and a
    # documented one that no longer exists sends readers after a dead name.
    let
      undocumented = report("missing from configfile.md", registered - documented)
      unknown = report("documented but not registered", documented - registered)
    check undocumented == 0
    check unknown == 0

  test "no command is listed twice in configfile.md":
    # A name in two sections silently keeps only the last description, which
    # would hide real drift from the check below.
    var
      seen: HashSet[string]
      duplicated: HashSet[string]
    for row in documentedRows():
      if row.name in seen:
        duplicated.incl row.name
      seen.incl row.name
    check report("listed more than once", duplicated) == 0

  test "every documented description matches the command table":
    let
      registered = registeredCommands()
      documented = documentedCommands()

    var mismatched: HashSet[string]
    for name, description in documented:
      if registered.hasKey(name) and registered[name] != description:
        mismatched.incl name & " — code: " & registered[name] & " / doc: " &
          description
    check report("description drift", mismatched) == 0
