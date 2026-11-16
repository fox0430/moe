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

## TOML loader and serializer for `[QuickRun]` and `[[QuickRun.entries]]`.
##
## Keys are derived from the type; only the required key, the command lines,
## file types and the filter are checked here.

import std/options

import pkg/[parsetoml, results]

import ../[command_string, config, file_command]
import ../syntax/tokenizer

import base, file_command as fileCommandLoader, save_base

const QuickRunSectionName* = cfgGroupName(QuickRunConfig)

proc checkQuickRunEntry*(
    t: TomlTableRef, entry: var QuickRunEntry, label: string, vr: var ValidationResult
): bool =
  ## `{.cfgEntryRules.}` for `QuickRunConfig.entries`: a runnable command and
  ## compilable patterns. Invalid entries are dropped whole.
  if t.hasKey("command"):
    checkCommandLine(t, entry.command, label, vr)
  else:
    vr.addError(label, "missing 'command' key", "table with 'command'")

  checkFileMatch(entry, label, vr)

  not vr.hasEntryErrors(label)

proc checkOptionsLine(
    value: var Option[string], key: string, vr: var ValidationResult
) =
  ## An options key that is split into arguments: every quote closed, else the
  ## value is dropped like any invalid one rather than failing every run.
  if value.isSome and splitCommandLine(value.get).isErr:
    vr.addError(
      fullKey(QuickRunSectionName, key), value.get, "options with every quote closed"
    )
    value = none(string)

proc loadQuickRunConfig*(
    table: TomlTableRef, quickRun: var QuickRunConfig, vr: var ValidationResult
) =
  ## Load `[QuickRun]` and every `[[QuickRun.entries]]` table under it.
  const knownKeys = generateSectionGroupKeys(QuickRunConfig)
  checkUnknownKeys(table, knownKeys, QuickRunSectionName, vr)
  generateSectionGroupLoader(table, quickRun, vr, QuickRunConfig)
  checkOptionsLine(quickRun.nimAdvancedCommand, "nimAdvancedCommand", vr)
  checkOptionsLine(quickRun.nimOptions, "NimOptions", vr)
  checkOptionsLine(quickRun.shOptions, "shOptions", vr)
  checkOptionsLine(quickRun.bashOptions, "bashOptions", vr)

proc appendQuickRunToml*(lines: var seq[string], quickRun: QuickRunConfig) =
  ## `[QuickRun]` plus one `[[QuickRun.entries]]` block per entry, in field
  ## order. Empty keys are written too, like every generated section.
  generateSectionGroupSerializer(lines, quickRun, QuickRunConfig)
