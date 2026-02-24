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

## Configuration file loading for key_bindings
##
## This module handles loading key_bindings from configuration files (TOML format).

import std/[os, strutils, tables, options]

import pkg/parsetoml

import key_bindings, modes, config_loader

type KeybindingConfig* = object ## Structure for keybinding configuration
  mode*: EditorMode
  key*: string
  command*: string
  commandType*: CommandType
  args*: seq[string]

const allModeChoices* =
  "one of: normal, insert, visual, visualline, visualblock, replace, " &
  "command, filer, quickrun, logviewer, help, buffermanager, " &
  "backupmanager, diffviewer, recentfile, debug, config, references, " &
  "documentsymbol, callhierarchy, terminal, all, visualall"

proc parseModes(s: string): seq[EditorMode] =
  ## Parse mode string to seq of EditorMode enums.
  ## Supports all 21 editor modes plus meta modes:
  ## - "all": all modes except CommandLine
  ## - "visualall": Visual, VisualLine, VisualBlock
  ## Returns empty seq for unknown modes.
  case s.toLowerAscii
  of "normal":
    @[EditorMode.Normal]
  of "insert":
    @[EditorMode.Insert]
  of "visual":
    @[EditorMode.Visual]
  of "visualline":
    @[EditorMode.VisualLine]
  of "visualblock":
    @[EditorMode.VisualBlock]
  of "replace":
    @[EditorMode.Replace]
  of "command":
    @[EditorMode.CommandLine]
  of "filer":
    @[EditorMode.Filer]
  of "quickrun":
    @[EditorMode.QuickRun]
  of "logviewer":
    @[EditorMode.LogViewer]
  of "help":
    @[EditorMode.Help]
  of "buffermanager":
    @[EditorMode.BufferManager]
  of "backupmanager":
    @[EditorMode.BackupManager]
  of "diffviewer":
    @[EditorMode.DiffViewer]
  of "recentfile":
    @[EditorMode.RecentFile]
  of "debug":
    @[EditorMode.Debug]
  of "config":
    @[EditorMode.Config]
  of "references":
    @[EditorMode.References]
  of "documentsymbol":
    @[EditorMode.DocumentSymbol]
  of "callhierarchy":
    @[EditorMode.CallHierarchy]
  of "terminal":
    @[EditorMode.Terminal]
  of "all":
    var modes: seq[EditorMode] = @[]
    for m in EditorMode:
      if m != EditorMode.CommandLine:
        modes.add(m)
    modes
  of "visualall":
    @[EditorMode.Visual, EditorMode.VisualLine, EditorMode.VisualBlock]
  else:
    @[]

proc parseOverlay(s: string): Option[OverlayKind] =
  ## Parse overlay string to OverlayKind enum
  case s.toLowerAscii
  of "command":
    some(okCommand)
  of "search":
    some(okSearch)
  of "rename":
    some(okRename)
  else:
    none(OverlayKind)

proc parseCommandType(s: string): CommandType =
  ## Parse command type string.
  ## Note: "key_sequence" is handled by an early branch in loadKeybindingsFromToml
  ## before this proc is called, so it is intentionally absent here.
  case s.toLowerAscii
  of "motion": ctMotion
  of "action": ctAction
  of "mode_switch", "modeswitch": ctModeSwitch
  of "overlay_switch", "overlayswitch": ctOverlaySwitch
  of "text_object", "textobject": ctTextObject
  of "operator": ctOperator
  of "operator_pending", "operatorpending": ctOperatorPending
  of "custom": ctCustom
  else: ctAction
    # default to action

proc addKeySequenceMapping*(
    registry: KeyBindingRegistry, mode: EditorMode, keyStr: string, targetKeyStr: string
) =
  ## Add a key→key_sequence mapping to the registry (runtimeMappings only).
  ## Unlike addKeybinding, this does NOT register in bindings/sequences tables.
  ## The mapping is replayed via playbackMacro at runtime.
  let triggerKeys = parseKeyString(keyStr)
  if triggerKeys.len == 0:
    return

  let targetKeys = parseKeyString(targetKeyStr)
  if targetKeys.len == 0:
    return

  var targetKeyStrs: seq[string] = @[]
  for k in targetKeys:
    targetKeyStrs.add(keyComboToString(k))

  if not registry.runtimeMappings.hasKey(mode):
    registry.runtimeMappings[mode] = @[]

  registry.runtimeMappings[mode].add(
    RuntimeKeyMapping(
      kind: rmkKeySequence,
      triggerKeys: triggerKeys,
      triggerStr: keyStr,
      targetStr: targetKeyStr,
      targetKeys: targetKeyStrs,
    )
  )

proc addKeybinding*(
    registry: KeyBindingRegistry, mode: EditorMode, keyStr: string, cmd: Command
) =
  ## Add a keybinding to the registry (supports multi-key sequences)
  let keys = parseKeyString(keyStr)
  if keys.len == 0:
    return

  if keys.len == 1:
    registry.bindKey(mode, keys[0], cmd)
  else:
    registry.bindSequence(mode, keys, cmd)

  # Register in runtimeMappings for replay protection (isReplayingMapping)
  if not registry.runtimeMappings.hasKey(mode):
    registry.runtimeMappings[mode] = @[]

  registry.runtimeMappings[mode].add(
    RuntimeKeyMapping(
      kind: rmkCommand,
      triggerKeys: keys,
      triggerStr: keyStr,
      targetStr: cmd.name,
      commandName: cmd.name,
    )
  )

proc loadKeybindingsFromToml*(
    registry: KeyBindingRegistry, tomlPath: string, vr: var ValidationResult
) =
  ## Load key_bindings from a TOML configuration file
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
  ## [[keybinding]]
  ## mode = "insert"
  ## key = "jj"
  ## command_type = "key_sequence"
  ## target_keys = "Escape"
  ##
  if not fileExists(tomlPath):
    return

  var toml: TomlValueRef
  try:
    toml = parseFile(tomlPath)
  except CatchableError:
    let e = getCurrentException()
    vr.addError("keybindings", e.msg, "valid TOML file")
    return

  let tomlTable = toml.getTable()

  # Check for keybinding array
  if not tomlTable.hasKey("keybinding"):
    return

  let bindings = tomlTable["keybinding"]
  if bindings.kind != TomlValueKind.Array:
    vr.addError("keybinding", $bindings.kind, "Array")
    return

  let elems = bindings.getElems()
  for i, bindingVal in elems:
    let entryName = "keybinding[" & $i & "]"

    if bindingVal.kind != TomlValueKind.Table:
      vr.addError(entryName, $bindingVal.kind, "Table")
      continue

    let binding = bindingVal.getTable()

    # Parse required fields
    if not binding.hasKey("mode"):
      vr.addError(entryName & ".mode", "(missing)", allModeChoices)
      continue
    if not binding.hasKey("key"):
      vr.addError(entryName & ".key", "(missing)", "key string (e.g. \"C-s\", \"h\")")
      continue

    let modeStr = binding["mode"].getStr()
    let keyStr = binding["key"].getStr()

    let modes = parseModes(modeStr)
    if modes.len == 0:
      vr.addError(entryName & ".mode", modeStr, allModeChoices)
      continue

    # Validate key string
    let keys = parseKeyString(keyStr)
    if keys.len == 0:
      vr.addError(
        entryName & ".key", keyStr, "valid key string (e.g. \"C-s\", \"g d\")"
      )
      continue

    # Handle key_sequence type separately (no Command object)
    if binding.hasKey("command_type") and
        binding["command_type"].getStr().toLowerAscii in ["key_sequence", "keysequence"]:
      if not binding.hasKey("target_keys"):
        vr.addError(
          entryName & ".target_keys",
          "(missing)",
          "key string (e.g. \"Escape\", \"C-c\")",
        )
      else:
        let targetKeyStr = binding["target_keys"].getStr()
        let targetKeys = parseKeyString(targetKeyStr)
        if targetKeys.len == 0:
          vr.addError(
            entryName & ".target_keys",
            targetKeyStr,
            "valid key string (e.g. \"Escape\", \"C-c\")",
          )
        else:
          for mode in modes:
            registry.addKeySequenceMapping(mode, keyStr, targetKeyStr)
      continue

    # Parse command type (default to action)
    let cmdType =
      if binding.hasKey("command_type"):
        parseCommandType(binding["command_type"].getStr())
      else:
        ctAction

    # Build command based on type
    var cmdOpt: Option[key_bindings.Command] = none(key_bindings.Command)

    case cmdType
    of ctModeSwitch:
      if not binding.hasKey("target_mode"):
        vr.addError(entryName & ".target_mode", "(missing)", allModeChoices)
      else:
        let targetModes = parseModes(binding["target_mode"].getStr())
        if targetModes.len == 0:
          vr.addError(
            entryName & ".target_mode", binding["target_mode"].getStr(), allModeChoices
          )
        else:
          let cmd = Command(
            kind: ctModeSwitch,
            name: "mode_switch",
            description: "Switch to " & binding["target_mode"].getStr(),
            targetMode: targetModes[0],
          )
          cmdOpt = some(cmd)
    of ctOverlaySwitch:
      if not binding.hasKey("target_overlay"):
        vr.addError(
          entryName & ".target_overlay", "(missing)", "one of: command, search, rename"
        )
      else:
        let targetOverlayOpt = parseOverlay(binding["target_overlay"].getStr())
        if targetOverlayOpt.isNone:
          vr.addError(
            entryName & ".target_overlay",
            binding["target_overlay"].getStr(),
            "one of: command, search, rename",
          )
        else:
          let cmd = Command(
            kind: ctOverlaySwitch,
            name: "overlay_switch",
            description: "Switch to " & binding["target_overlay"].getStr() & " overlay",
            targetOverlay: targetOverlayOpt.get,
          )
          cmdOpt = some(cmd)
    of ctAction, ctTextObject, ctOperator, ctCustom:
      if not binding.hasKey("command"):
        vr.addError(
          entryName & ".command", "(missing)", "command string (e.g. \"file.save\")"
        )
      else:
        let commandId = binding["command"].getStr()
        # Check command existence when registry has been populated
        if registry.commandRegistry.len > 0 and commandId notin registry.commandRegistry:
          vr.addError(entryName & ".command", commandId, "registered command name")
        else:
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
      vr.addError(
        entryName & ".command_type",
        binding["command_type"].getStr(),
        "one of: action, mode_switch, overlay_switch, text_object, operator, custom, key_sequence",
      )

    # Add the keybinding to each mode if command was successfully created
    if cmdOpt.isSome:
      for mode in modes:
        registry.addKeybinding(mode, keyStr, cmdOpt.get)

proc getKeybindingsPath*(): string =
  ## Get the path to the key bindings configuration file
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

proc loadDefaultKeybindings*(registry: KeyBindingRegistry, vr: var ValidationResult) =
  ## Load key bindings from the default location
  let keybindingsPath = getKeybindingsPath()
  if fileExists(keybindingsPath):
    registry.loadKeybindingsFromToml(keybindingsPath, vr)
