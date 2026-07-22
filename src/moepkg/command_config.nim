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

## Command configuration system
##
## This module handles configuration of command line commands, allowing users
## to customize command aliases and behavior through configuration files.
##
## Also re-exports `keyMappableCommandModeAliases` — the curated set of
## Command mode command aliases (`:bd`, `:q`, `:w`, ...) that may appear as
## RHS targets in a keymap config. `key_bindings.setupDefaultBindings`
## registers each entry as a Command with commandId `exec.cmdline.<alias>` so
## the keymap loader can resolve it; at dispatch time the bridge in
## `command_handlers/*_handler.nim` rewrites the commandId back into
## `:<alias>` so the full command-line parser (and its modified-buffer safety
## checks) runs.

import std/[tables, sequtils, options, strutils]

import command_line, command_line_commands
import types/command_config_types
export command_config_types

# Mapping from canonical command names to CommandLineAction. Used for
# resolving user-defined aliases in `[CommandAliases]` config. Derived from
# the canonical `CommandLineCommandTable` filtered for entries flagged
# `isCanonicalLong` (the long form intended for TOML user config).
const CommandNameTable*: Table[string, CommandLineAction] = block:
  var t: Table[string, CommandLineAction]
  for spec in CommandLineCommandTable:
    if spec.isCanonicalLong and spec.action.isSome:
      t[spec.name] = spec.action.get
  t

# Command mode command aliases registrable as keymap RHS targets. Each is
# dispatched at runtime through `hrExecCommand` / `nmrExecCommand`, so the
# full command-line parser runs (inheriting modified-buffer safety checks
# like `:bd` / `:q`). Curated to argumentless Command mode commands — `:vs`,
# `:e`, `:ls`, `:set` etc. need arguments to be useful and are intentionally
# excluded.
#
# Derived from the canonical `CommandLineCommandTable`: any spec carrying a
# non-empty `keymapBaseDescription` becomes an entry here, with the full
# description built as `<base> (:<name>)`. The set of registered Command-
# mode handlers is computed from this list in `setupDefaultBindings`, and
# names that collide with a pre-existing Command (e.g. "save") are skipped
# there so the original handler keeps its real `commandId`.
const keyMappableCommandModeAliases*: seq[KeyMappableCommandAlias] = block:
  var s: seq[KeyMappableCommandAlias]
  for spec in CommandLineCommandTable:
    if spec.keymapBaseDescription.len > 0:
      s.add((spec.name, spec.keymapBaseDescription & " (:" & spec.name & ")"))
  s

proc resolveCommandName*(name: string): Option[CommandLineAction] =
  ## Resolve a command name string to a CommandLineAction.
  ## Returns none if the name is not recognized.
  let lower = name.toLowerAscii()
  if lower in CommandNameTable:
    return some(CommandNameTable[lower])
  return none(CommandLineAction)

proc canonicalCommandName*(action: CommandLineAction): Option[string] =
  ## Reverse lookup of `CommandNameTable`: return the canonical long-form
  ## command name for `action` (the name used in TOML `[CommandAliases]`
  ## config), or none if the action has no canonical name.
  for name, a in CommandNameTable.pairs:
    if a == action:
      return some(name)
  return none(string)

proc isDefaultCommandAlias*(alias: string): bool =
  ## True if `alias` names a built-in default command alias — the set
  ## registered by `loadDefaultConfig` (specs with a non-empty
  ## `completionDescription`).
  let key = alias.toLowerAscii()
  for spec in CommandLineCommandTable:
    if spec.action.isSome and spec.completionDescription.len > 0 and spec.name == key:
      return true
  return false

proc newCommandConfig*(): CommandConfig =
  ## Create a new command configuration with defaults
  CommandConfig(
    aliases: initTable[string, CommandLineAction](),
    aliasDescriptions: initTable[string, string](),
    shellCommands: initTable[string, ShellCommandEntry](),
  )

proc addAlias*(
    config: CommandConfig, alias: string, action: CommandLineAction, description = ""
) =
  ## Add a command alias with optional description
  let key = alias.toLowerAscii()
  config.aliases[key] = action
  if description.len > 0:
    config.aliasDescriptions[key] = description
  else:
    config.aliasDescriptions.del(key)

proc removeAlias*(config: CommandConfig, alias: string) =
  ## Remove a command alias and its description
  let key = alias.toLowerAscii()
  config.aliases.del(key)
  config.aliasDescriptions.del(key)

proc addShellCommand*(
    config: CommandConfig, name: string, command: string, description = ""
) =
  ## Add a shell command definition with optional description
  config.shellCommands[name.toLowerAscii()] =
    ShellCommandEntry(command: command, description: description)

proc disableCommand*(config: CommandConfig, action: CommandLineAction) =
  ## Disable a built-in command
  if action notin config.disabledCommands:
    config.disabledCommands.add(action)

proc enableCommand*(config: CommandConfig, action: CommandLineAction) =
  ## Re-enable a previously disabled command
  config.disabledCommands.keepItIf(it != action)

proc isCommandEnabled*(config: CommandConfig, action: CommandLineAction): bool =
  ## Check if a command is enabled
  action notin config.disabledCommands

proc loadDefaultConfig*(config: CommandConfig) =
  ## Load default command configuration. Registers every alias defined in
  ## `CommandLineCommandTable` that's intended as a runtime command (i.e.,
  ## has a non-empty `completionDescription`). Long forms reserved purely
  ## for TOML `[CommandAliases]` resolution (e.g. `quit`, `save`,
  ## `buffermanager`) carry an empty `completionDescription` and are
  ## skipped here — they are exposed via `CommandNameTable` instead.
  for spec in CommandLineCommandTable:
    if spec.action.isSome and spec.completionDescription.len > 0:
      config.addAlias(spec.name, spec.action.get)

proc applyToParser*(config: CommandConfig, parser: CommandLineParser) =
  ## Apply configuration to a command line parser
  # Clear existing aliases
  parser.aliases.clear()
  parser.aliasDescriptions.clear()

  # Apply configured aliases (only for enabled commands)
  for alias, action in config.aliases.pairs:
    if config.isCommandEnabled(action):
      parser.aliases[alias] = action
      if alias in config.aliasDescriptions:
        parser.aliasDescriptions[alias] = config.aliasDescriptions[alias]

  # Apply shell commands
  parser.shellCommands.clear()
  for name, entry in config.shellCommands.pairs:
    parser.shellCommands[name] = entry
