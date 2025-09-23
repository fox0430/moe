#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

## Configuration file loading for keybindings
##
## This module handles loading keybindings from configuration files.
## The actual implementation is deferred - this just shows the structure.

import std/[json, os, strutils]
import keybindings, modes, commandregistry

type KeybindingConfig* = object ## Structure for keybinding configuration
  mode*: string
  key*: string
  command*: string
  args*: seq[string]

proc loadKeybindingsFromJson*(
    registry: KeyBindingRegistry, cmdRegistry: CommandRegistry, jsonPath: string
) =
  ## Load keybindings from a JSON configuration file
  ##
  ## Example JSON structure:
  ## {
  ##   "keybindings": [
  ##     {"mode": "normal", "key": "h", "command": "motion.left"},
  ##     {"mode": "normal", "key": "C-s", "command": "file.save"},
  ##     {"mode": "normal", "key": "g g", "command": "motion.firstline"}
  ##   ]
  ## }
  ##
  ## This is a placeholder implementation
  if not fileExists(jsonPath):
    return

  # TODO: Implement actual JSON parsing and loading
  # let json = parseFile(jsonPath)
  # for binding in json["keybindings"]:
  #   let mode = parseEnum[EditorMode](binding["mode"].getStr)
  #   let key = binding["key"].getStr
  #   let command = binding["command"].getStr
  #   registry.bindKey(mode, key, command)

proc loadKeybindingsFromToml*(
    registry: KeyBindingRegistry, cmdRegistry: CommandRegistry, tomlPath: string
) =
  ## Load keybindings from a TOML configuration file
  ##
  ## Example TOML structure:
  ## [[keybinding]]
  ## mode = "normal"
  ## key = "h"
  ## command = "motion.left"
  ##
  ## [[keybinding]]
  ## mode = "normal"
  ## key = "C-s"
  ## command = "file.save"
  ##
  ## This is a placeholder implementation
  if not fileExists(tomlPath):
    return

  # TODO: Implement actual TOML parsing and loading
  # Would require a TOML parser library

proc loadKeybindingsFromNim*(
    registry: KeyBindingRegistry, cmdRegistry: CommandRegistry, nimPath: string
) =
  ## Load keybindings from a Nim configuration file
  ##
  ## Example Nim structure:
  ## # config.nim
  ## import moepkg/[keybindings, modes]
  ##
  ## proc configureKeybindings*(registry: KeyBindingRegistry) =
  ##   registry.bindKey(Normal, "h", "motion.left")
  ##   registry.bindKey(Normal, parseKeyCombo("C-s").get,
  ##                    Command(name: "save", kind: ctAction, commandId: "file.save"))
  ##
  ## This would allow for maximum flexibility and type safety
  ##
  ## This is a placeholder implementation
  if not fileExists(nimPath):
    return

  # TODO: Implement actual Nim config loading
  # This would require dynamic compilation or a plugin system

proc loadDefaultKeybindings*(
    registry: KeyBindingRegistry, cmdRegistry: CommandRegistry
) =
  ## Load keybindings from default configuration locations
  ##
  ## Searches in order:
  ## 1. $XDG_CONFIG_HOME/moe/keybindings.json
  ## 2. ~/.config/moe/keybindings.json
  ## 3. ./keybindings.json
  ##
  ## Falls back to built-in defaults if no config found

  let configPaths = [
    getConfigDir() / "moe" / "keybindings.json",
    getHomeDir() / ".config" / "moe" / "keybindings.json",
    "keybindings.json",
  ]

  for path in configPaths:
    if fileExists(path):
      registry.loadKeybindingsFromJson(cmdRegistry, path)
      return

  # No config found, use built-in defaults
  registry.setupDefaultBindings()

proc saveKeybindings*(registry: KeyBindingRegistry, jsonPath: string) =
  ## Save current keybindings to a JSON file
  ##
  ## This allows users to export their current configuration
  ##
  ## This is a placeholder implementation

  # TODO: Implement saving keybindings to JSON
  # var json = newJObject()
  # var bindings = newJArray()
  # for mode, modeBindings in registry.bindings:
  #   for binding in modeBindings:
  #     bindings.add(%*{
  #       "mode": $mode,
  #       "key": formatKeyCombo(binding.combo),
  #       "command": binding.command.name
  #     })
  # json["keybindings"] = bindings
  # writeFile(jsonPath, json.pretty)
  discard
