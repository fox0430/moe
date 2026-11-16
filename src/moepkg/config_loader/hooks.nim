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
## the Ex command, and contradicting values are checked here.

import std/strutils

import pkg/[parsetoml, results]

import ../[config, hook_ex_command, hooks]
import ../syntax/tokenizer

import base, file_command, save_base

const HookSectionName* = "Hook"

proc checkHookEntry*(
    t: TomlTableRef, entry: var HookEntry, label: string, vr: var ValidationResult
): bool =
  ## `{.cfgEntryRules.}` for `HookConfig.entries`: required keys and compilable
  ## patterns. Invalid entries are dropped whole.
  if not t.hasKey("event"):
    vr.addError(label, "missing 'event' key", "table with 'event'")
  let exRefused =
    t.hasKey("exCommand") and
    (t["exCommand"].kind != TomlValueKind.String or not entry.isWritePreHook)
  if exRefused and not t.hasKey("command"):
    # Meant as an Ex hook: its refusal (wrong type, or not BufWritePre) is
    # reported already, and a missing `command` would only mislead.
    discard
  elif entry.isWritePreHook and t.hasKey("exCommand") and not t.hasKey("command") and
      entry.exCommand.strip.len == 0:
    vr.addError(fullKey(label, "exCommand"), "empty string", ExCommandExpected)
  elif entry.isExHook:
    # `cfgOnlyWhen` refuses a `command` and the keys only a program takes.
    let parsed = parseHookExCommand(entry.exCommand)
    if parsed.isErr:
      vr.addError(fullKey(label, "exCommand"), entry.exCommand, parsed.error)
  elif not t.hasKey("command"):
    vr.addError(
      label, "missing 'command' key",
      "table with 'command' (or BufWritePre 'exCommand')",
    )
  else:
    checkCommandLine(t, entry.command, label, vr)

  checkFileMatch(entry, label, vr)

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
