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
## This module handles loading keybindings from configuration files (TOML format).

import std/[os, strutils, tables, options]
import parsetoml
import keybindings, modes

type KeybindingConfig* = object ## Structure for keybinding configuration
  mode*: EditorMode
  key*: string
  command*: string
  commandType*: CommandType
  args*: seq[string]

proc parseMode(s: string): Option[EditorMode] =
  ## Parse mode string to EditorMode enum
  case s.toLowerAscii
  of "normal":
    some(EditorMode.Normal)
  of "insert":
    some(EditorMode.Insert)
  of "command":
    some(EditorMode.Command)
  of "visual":
    some(EditorMode.Visual)
  of "replace":
    some(EditorMode.Replace)
  else:
    none(EditorMode)

proc parseCommandType(s: string): CommandType =
  ## Parse command type string
  case s.toLowerAscii
  of "motion": ctMotion
  of "action": ctAction
  of "mode_switch", "modeswitch": ctModeSwitch
  of "text_object", "textobject": ctTextObject
  of "operator": ctOperator
  of "operator_pending", "operatorpending": ctOperatorPending
  of "custom": ctCustom
  else: ctAction
    # default to action

proc addKeybinding*(
    registry: KeyBindingRegistry, mode: EditorMode, keyStr: string, cmd: Command
) =
  ## Add a keybinding to the registry
  if not registry.bindings.hasKey(mode):
    registry.bindings[mode] = @[]

  let keyComboOpt = parseKeyCombo(keyStr)
  if keyComboOpt.isNone:
    # Invalid key combination, skip
    return

  let binding = KeyBinding(combo: keyComboOpt.get, command: cmd, context: mode)
  registry.bindings[mode].add(binding)

proc loadKeybindingsFromToml*(registry: KeyBindingRegistry, tomlPath: string) =
  ## Load keybindings from a TOML configuration file
  ##
  ## Example TOML structure:
  ## [[keybinding]]
  ## mode = "normal"
  ## key = "h"
  ## command_type = "action"
  ## command = "move.left"
  ##
  ## [[keybinding]]
  ## mode = "normal"
  ## key = "C-s"
  ## command_type = "action"
  ## command = "file.save"
  ##
  ## [[keybinding]]
  ## mode = "insert"
  ## key = "C-c"
  ## command_type = "mode_switch"
  ## target_mode = "normal"
  ##
  if not fileExists(tomlPath):
    return

  let toml = parseFile(tomlPath)
  let tomlTable = toml.getTable()

  # Check for keybinding array
  if not tomlTable.hasKey("keybinding"):
    return

  let bindings = tomlTable["keybinding"]
  if bindings.kind != TomlValueKind.Array:
    return

  for bindingVal in bindings.getElems():
    if bindingVal.kind != TomlValueKind.Table:
      continue

    let binding = bindingVal.getTable()

    # Parse required fields
    if not (binding.hasKey("mode") and binding.hasKey("key")):
      continue

    let modeStr = binding["mode"].getStr()
    let keyStr = binding["key"].getStr()

    let modeOpt = parseMode(modeStr)
    if modeOpt.isNone:
      continue

    let mode = modeOpt.get

    # Parse command type (default to action)
    let cmdType =
      if binding.hasKey("command_type"):
        parseCommandType(binding["command_type"].getStr())
      else:
        ctAction

    # Build command based on type
    var cmdOpt: Option[keybindings.Command] = none(keybindings.Command)

    case cmdType
    of ctModeSwitch:
      if binding.hasKey("target_mode"):
        let targetModeOpt = parseMode(binding["target_mode"].getStr())
        if targetModeOpt.isSome:
          let cmd = Command(
            kind: ctModeSwitch,
            name: "mode_switch",
            description: "Switch to " & binding["target_mode"].getStr(),
            targetMode: targetModeOpt.get,
          )
          cmdOpt = some(cmd)
    of ctAction, ctTextObject, ctOperator, ctCustom:
      if binding.hasKey("command"):
        let commandId = binding["command"].getStr()
        var args: seq[string] = @[]
        if binding.hasKey("args"):
          for arg in binding["args"].getElems():
            args.add(arg.getStr())
        let cmd = Command(
          kind: cmdType,
          name: commandId,
          description: commandId,
          commandId: commandId,
          args: args,
        )
        cmdOpt = some(cmd)
    of ctMotion, ctOperatorPending:
      # These command types require special handling not supported in TOML config yet
      discard

    # Add the keybinding if command was successfully created
    if cmdOpt.isSome:
      registry.addKeybinding(mode, keyStr, cmdOpt.get)

proc getKeybindingsPath*(): string =
  ## Get the path to the keybindings configuration file
  ## Searches in standard locations:
  ## 1. $XDG_CONFIG_HOME/moe/keybindings.toml
  ## 2. ~/.config/moe/keybindings.toml
  ## 3. ./keybindings.toml

  let configPaths = [
    getConfigDir() / "moe" / "keybindings.toml",
    getHomeDir() / ".config" / "moe" / "keybindings.toml",
    "keybindings.toml",
  ]

  for path in configPaths:
    if fileExists(path):
      return path

  # Return the default location even if it doesn't exist
  return getConfigDir() / "moe" / "keybindings.toml"

proc loadDefaultKeybindings*(registry: KeyBindingRegistry) =
  ## Load keybindings from the default location
  let keybindingsPath = getKeybindingsPath()
  if fileExists(keybindingsPath):
    registry.loadKeybindingsFromToml(keybindingsPath)
