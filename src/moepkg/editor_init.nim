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

import
  config, config_loader, command_registry, command_config, command_line, logger, modes

import key_bindings except Command
import keybind_config

proc applyKeyMappings*(registry: KeyBindingRegistry, km: KeyMappingConfig) =
  ## Apply user-defined key mappings from the moerc.toml [KeyMapping] section.
  ## Individual mapping failures are logged (logWarn) and skipped; they are
  ## non-fatal so a single bad entry never aborts startup.
  ##
  ## Precedence (later wins): "All" (every mode but Command) < "VisualAll"
  ## (the three visual modes) < per-mode mappings. The application order below
  ## preserves that override behaviour.
  proc apply(
      mode: EditorMode,
      label: string,
      mappings: OrderedTable[string, string],
      multi = false,
  ) =
    for lhs, rhs in mappings:
      let err = registry.addRuntimeMapping(mode, lhs, rhs)
      if err.len > 0:
        let msg =
          if multi:
            "KeyMapping." & label & " error (" & $mode & "): " & err
          else:
            "KeyMapping." & label & " error: " & err
        logWarn("editor", msg)

  # "All" applies to every mode first (mode-specific mappings can override).
  for mode in EditorMode:
    if mode != EditorMode.Command:
      apply(mode, "All", km.all, multi = true)

  # "VisualAll" applies to the three visual modes.
  for mode in [EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine]:
    apply(mode, "VisualAll", km.visualAll, multi = true)

  # Per-mode mappings.
  apply(EditorMode.Normal, "Normal", km.normal)
  apply(EditorMode.Insert, "Insert", km.insert)
  apply(EditorMode.Visual, "Visual", km.visual)
  apply(EditorMode.VisualLine, "VisualLine", km.visualLine)
  apply(EditorMode.VisualBlock, "VisualBlock", km.visualBlock)
  apply(EditorMode.Replace, "Replace", km.replace)
  apply(EditorMode.Command, "Command", km.command)
  apply(EditorMode.Filer, "Filer", km.filer)
  apply(EditorMode.LogViewer, "LogViewer", km.logViewer)
  apply(EditorMode.Help, "Help", km.help)
  apply(EditorMode.BufferManager, "BufferManager", km.bufferManager)
  apply(EditorMode.BackupManager, "BackupManager", km.backupManager)
  apply(EditorMode.DiffViewer, "DiffViewer", km.diffViewer)
  apply(EditorMode.Config, "Config", km.config)
  apply(EditorMode.References, "References", km.references)
  apply(EditorMode.DocumentSymbol, "DocumentSymbol", km.documentSymbol)
  apply(EditorMode.CallHierarchy, "CallHierarchy", km.callHierarchy)
  apply(EditorMode.RecentFile, "RecentFile", km.recentFile)
  apply(EditorMode.Debug, "Debug", km.debug)
  apply(EditorMode.Terminal, "Terminal", km.terminal)

proc newEditorRegistries*(
    editorConfig: EditorConfig, vr: var ValidationResult
): tuple[
  cmdRegistry: CommandRegistry,
  keyRegistry: KeyBindingRegistry,
  cmdConfig: CommandConfig,
  cmdLineParser: CommandLineParser,
] =
  ## Create and fully initialize the command/keybinding registries from config:
  ## built-in commands, default key bindings, the default keybindings file, user
  ## [KeyMapping] overrides, command aliases, and shell commands. Validation
  ## errors discovered while loading keybindings are accumulated into `vr`.
  let
    cmdRegistry = newCommandRegistry()
    keyRegistry = newKeyBindingRegistry()
    cmdConfig = newCommandConfig()
    cmdLineParser = newCommandLineParser()

  # Register built-in commands and default bindings.
  cmdRegistry.registerBuiltinCommands
  keyRegistry.setupDefaultBindings

  # Load custom key_bindings from TOML, then apply moerc.toml [KeyMapping].
  keyRegistry.loadDefaultKeybindings(vr)
  keyRegistry.applyKeyMappings(editorConfig.keyMapping)

  # Load command configuration.
  cmdConfig.loadDefaultConfig

  # Load user-defined command aliases from editor config.
  for alias, entry in editorConfig.commandAliases.pairs:
    let action = resolveCommandName(entry.command)
    if action.isSome:
      cmdConfig.addAlias(alias, action.get, entry.description)

  # Load shell commands from editor config.
  for name, entry in editorConfig.shellCommands.pairs:
    cmdConfig.addShellCommand(name, entry.command, entry.description)

  # Apply configuration to parser.
  cmdConfig.applyToParser(cmdLineParser)

  result = (cmdRegistry, keyRegistry, cmdConfig, cmdLineParser)
