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

## Editor initialization helpers
##
## Builds the command/keybinding subsystem (CommandRegistry, KeyBindingRegistry,
## CommandConfig, CommandLineParser) from an `EditorConfig`. Extracted from
## `newEditor` (editor.nim) to keep the constructor focused.

import std/[options, tables]

import config, config_loader, command_registry, command_config, command_line, modes

import key_bindings except Command
import keybind_config

proc applyKeyMappings*(
    registry: KeyBindingRegistry, km: KeyMappingConfig, vr: var ValidationResult
) =
  ## Apply user-defined key mappings from the moerc.toml [KeyMapping] section.
  ## This is the single point where a mapping RHS is resolved against the real
  ## command registry; failures are recorded in `vr` and skipped, so one bad
  ## entry never aborts startup.
  ##
  ## Precedence (later wins): "All" (every mode but Command) < "VisualAll"
  ## (the three visual modes) < per-mode mappings. The application order below
  ## preserves that override behaviour.
  # `vr` is passed explicitly (not captured) since Nim cannot capture a `var`
  # param in a nested closure.
  proc apply(
      vr: var ValidationResult,
      mode: EditorMode,
      label: string,
      mappings: OrderedTable[string, KeyMappingEntry],
      multi = false,
  ) =
    for lhs, e in mappings:
      let
        err = registry.addRuntimeMappingExpanded(
          mode, lhs, e.rhs, e.noremap, e.args, e.forceKeySeq
        )
        # `km` is the merged keymap layer, so an entry's origin (moerc
        # [KeyMapping.<section>] vs the top-level [<section>] of keybindings.toml)
        # is unknown here. Label by the section name common to both files (no
        # "KeyMapping." prefix, which would be wrong for keybindings.toml).
        name =
          if multi:
            label & "." & $mode & "." & lhs
          else:
            label & "." & lhs
      if err.len > 0:
        vr.addError(name, e.rhs, err)
      elif not e.forceKeySeq and e.args.len == 0 and
          registry.looksLikeUnknownCommand(e.rhs):
        # Applied as a key sequence, but the RHS looks like a typo'd command.
        vr.addError(
          name, e.rhs,
          "a registered command name (treated as a key sequence; possible command typo)",
        )

  # "All" applies to every mode first (mode-specific mappings can override).
  for mode in EditorMode:
    if mode != EditorMode.Command:
      apply(vr, mode, "All", km.all, multi = true)

  # "VisualAll" applies to the three visual modes.
  for mode in [EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine]:
    apply(vr, mode, "VisualAll", km.visualAll, multi = true)

  # Per-mode mappings.
  for mode in EditorMode:
    apply(vr, mode, $mode, km.perMode[mode])

proc reapplyKeyMappings*(
    registry: KeyBindingRegistry, km: KeyMappingConfig, vr: var ValidationResult
) =
  ## Reset the user mapping layer to the configured state for a live config
  ## reload: clear all runtime mappings (including session `:nmap` ones, since
  ## the declarative TOML config is authoritative) and re-apply [KeyMapping].
  for mode in EditorMode:
    registry.clearRuntimeMappings(mode)
  registry.applyKeyMappings(km, vr)

proc applyCommandConfig*(
    cmdConfig: CommandConfig, editorConfig: EditorConfig, parser: CommandLineParser
) =
  ## (Re)build the runtime command configuration from `editorConfig` — default
  ## aliases minus [DisabledCommandAliases], then user [CommandAliases] on top
  ## (so a user alias may reuse a disabled default's name), plus
  ## [ShellCommands] — and apply it to `parser`. Mutates `cmdConfig` in place
  ## (it is shared with the command-mode handler) and resets session-level
  ## alias changes: the declarative TOML config is authoritative.
  cmdConfig.aliases.clear()
  cmdConfig.aliasDescriptions.clear()
  cmdConfig.shellCommands.clear()

  cmdConfig.loadDefaultConfig

  for alias in editorConfig.disabledCommandAliases:
    cmdConfig.removeAlias(alias)

  for alias, entry in editorConfig.commandAliases.pairs:
    let action = resolveCommandName(entry.command)
    if action.isSome:
      cmdConfig.addAlias(alias, action.get, entry.description)

  for name, entry in editorConfig.shellCommands.pairs:
    cmdConfig.addShellCommand(name, entry.command, entry.description)

  cmdConfig.applyToParser(parser)

proc newEditorRegistries*(
    editorConfig: EditorConfig, vr: var ValidationResult
): tuple[
  cmdRegistry: CommandRegistry,
  keyRegistry: KeyBindingRegistry,
  cmdConfig: CommandConfig,
  cmdLineParser: CommandLineParser,
] =
  ## Create and fully initialize the command/keybinding registries from config:
  ## built-in commands, default key bindings, user [KeyMapping] overrides,
  ## command aliases, and shell commands. Validation errors discovered while
  ## applying [KeyMapping] entries are accumulated into `vr`.
  let
    cmdRegistry = newCommandRegistry()
    keyRegistry = newKeyBindingRegistry()
    cmdConfig = newCommandConfig()
    cmdLineParser = newCommandLineParser()

  # Register built-in commands and default bindings.
  cmdRegistry.registerBuiltinCommands
  keyRegistry.setupDefaultBindings

  # Apply moerc.toml [KeyMapping] overrides on top of the default bindings.
  keyRegistry.applyKeyMappings(editorConfig.keyMapping, vr)

  # Load command configuration (default aliases minus disabled, user
  # [CommandAliases], [ShellCommands]) and apply it to the parser.
  cmdConfig.applyCommandConfig(editorConfig, cmdLineParser)

  result = (cmdRegistry, keyRegistry, cmdConfig, cmdLineParser)
