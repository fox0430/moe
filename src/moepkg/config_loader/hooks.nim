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

## TOML loader and serializer for `[Hook]` and `[[Hook.entries]]`.
##
## Keys are derived from the type; only required keys, regex compilation,
## and contradicting values are checked here.

import std/strutils

import pkg/parsetoml

import ../[command_string, config, hooks]
import ../syntax/tokenizer

import base, save_base

const HookSectionName* = "Hook"

proc hasEntryErrors(vr: ValidationResult, label: string): bool =
  ## Whether a value under `label` was rejected (unknown keys excluded),
  ## so half-built entries are dropped.
  for issue in vr.errors:
    if issue.kind != sikUnknownKey and
        (issue.name == label or issue.name.startsWith(label & ".")):
      return true
  false

proc checkHookEntry*(
    t: TomlTableRef, entry: var HookEntry, label: string, vr: var ValidationResult
): bool =
  ## `{.cfgEntryRules.}` for `HookConfig.entries`: required keys and compilable
  ## patterns. Invalid entries are dropped whole.
  if not t.hasKey("event"):
    vr.addError(label, "missing 'event' key", "table with 'event'")
  if not t.hasKey("command"):
    vr.addError(label, "missing 'command' key", "table with 'command'")
  elif entry.command.strip.len == 0 and t["command"].kind == TomlValueKind.String:
    vr.addError(fullKey(label, "command"), "empty string", "non-empty command line")
  elif hasUnterminatedQuote(entry.command):
    # Otherwise the quote runs to the end of the line, and a placeholder meant
    # as an argument to `sh -c` lands in its script.
    vr.addError(
      fullKey(label, "command"), entry.command, "command line with every quote closed"
    )
  elif entry.command.len > 0 and parseCommandString(entry.command).cmd.len == 0:
    # Quoted-but-empty program (`'' fmt`); report at load, not at exec.
    vr.addError(
      fullKey(label, "command"), entry.command, "command line naming a program"
    )

  for i, name in entry.filetype:
    if not isValidFiletype(name):
      vr.addError(label & ".filetype[" & $i & "]", name, "known file type")

  # Compile once here, not per matched event.
  let filterError = entry.compileFilter()
  if filterError.len > 0:
    vr.addError(fullKey(label, "filter"), entry.filter, "regex: " & filterError)

  not vr.hasEntryErrors(label)

proc loadHookConfig*(
    table: TomlTableRef, hooks: var HookConfig, vr: var ValidationResult
) =
  ## Load `[Hook]` and every `[[Hook.entries]]` table under it.
  const knownKeys = generateSectionGroupKeys(HookConfig)
  checkUnknownKeys(table, knownKeys, HookSectionName, vr)
  generateSectionGroupLoader(table, hooks, vr, HookConfig)

proc appendHookToml*(lines: var seq[string], hooks: HookConfig) =
  ## `[Hook]` plus one `[[Hook.entries]]` block per entry, in field order.
  ## Empty keys are written too, like every generated section.
  generateSectionGroupSerializer(lines, hooks, HookConfig)
