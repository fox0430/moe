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

## TOML loader and serializer for [CommandAliases] and [ShellCommands]:
## free-form user-defined entries that map an alias name to a command
## (and an optional description).

import std/[algorithm, options, sequtils, tables, strutils]

import pkg/parsetoml

import ../[config, command_config]

import base, save_base

# Top-level TOML section names handled by this module.
const UserCommandsSectionNames* = ["CommandAliases", "ShellCommands"]

proc loadCommandAliasesConfig*(
    table: TomlTableRef,
    commandAliases: var Table[string, UserCommandEntry],
    vr: var ValidationResult,
) =
  ## Load user-defined command aliases from [CommandAliases] section.
  ## Value format: { command = "quit", description = "Exit editor" }
  ## description is optional.
  const section = "CommandAliases"
  for key, value in table.pairs:
    if value.kind != TomlValueKind.Table:
      vr.addError(section & "." & key, $value.kind, "table")
      continue
    let t = value.getTable()
    if not t.hasKey("command"):
      vr.addError(section & "." & key, "missing 'command' key", "table with 'command'")
      continue
    if t["command"].kind != TomlValueKind.String:
      vr.addError(section & "." & key & ".command", $t["command"].kind, "string")
      continue
    let cmdName = t["command"].getStr().toLowerAscii()
    if resolveCommandName(cmdName).isNone:
      vr.addError(section & "." & key, cmdName, "valid command name")
      continue
    var description = ""
    if t.hasKey("description"):
      if t["description"].kind == TomlValueKind.String:
        description = t["description"].getStr()
      else:
        vr.addError(
          section & "." & key & ".description", $t["description"].kind, "string"
        )
    commandAliases[key.toLowerAscii()] =
      UserCommandEntry(command: cmdName, description: description)

proc loadShellCommandsConfig*(
    table: TomlTableRef,
    shellCommands: var Table[string, UserCommandEntry],
    vr: var ValidationResult,
) =
  ## Load shell command definitions from [ShellCommands] section.
  ## Value format: { command = "nimble build", description = "Build project" }
  ## description is optional.
  const section = "ShellCommands"
  for key, value in table.pairs:
    if value.kind != TomlValueKind.Table:
      vr.addError(section & "." & key, $value.kind, "table")
      continue
    let t = value.getTable()
    if not t.hasKey("command"):
      vr.addError(section & "." & key, "missing 'command' key", "table with 'command'")
      continue
    if t["command"].kind != TomlValueKind.String:
      vr.addError(section & "." & key & ".command", $t["command"].kind, "string")
      continue
    let cmd = t["command"].getStr()
    if cmd.len == 0:
      vr.addError(section & "." & key & ".command", "empty string", "non-empty string")
      continue
    var description = ""
    if t.hasKey("description"):
      if t["description"].kind == TomlValueKind.String:
        description = t["description"].getStr()
      else:
        vr.addError(
          section & "." & key & ".description", $t["description"].kind, "string"
        )
    shellCommands[key.toLowerAscii()] =
      UserCommandEntry(command: cmd, description: description)

proc appendCommandAliasesToml*(
    lines: var seq[string], commandAliases: Table[string, UserCommandEntry]
) =
  if commandAliases.len > 0:
    lines.add "[CommandAliases]"
    for alias in toSeq(commandAliases.keys).sorted:
      let entry = commandAliases[alias]
      var val = "{ command = " & toTomlString(entry.command)
      if entry.description.len > 0:
        val &= ", description = " & toTomlString(entry.description)
      val &= " }"
      lines.add toTomlString(alias) & " = " & val
    lines.add ""

proc appendShellCommandsToml*(
    lines: var seq[string], shellCommands: Table[string, UserCommandEntry]
) =
  if shellCommands.len > 0:
    lines.add "[ShellCommands]"
    for name in toSeq(shellCommands.keys).sorted:
      let entry = shellCommands[name]
      var val = "{ command = " & toTomlString(entry.command)
      if entry.description.len > 0:
        val &= ", description = " & toTomlString(entry.description)
      val &= " }"
      lines.add toTomlString(name) & " = " & val
    lines.add ""
