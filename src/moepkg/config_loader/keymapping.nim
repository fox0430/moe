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

## TOML loader and serializer for the [KeyMapping.*] section group. Each
## per-mode sub-table maps a key sequence (LHS) to either a command name or
## another key sequence (RHS); validation rejects bare identifiers that look
## like typo'd command names rather than letting them fall through to
## Vim-style concatenated parsing.

import std/[sets, tables, strutils]

import pkg/parsetoml

import ../[config, key_bindings]

import base, save_base

# Top-level TOML section name handled by this module.
const KeyMappingSectionName* = "KeyMapping"

proc loadKeyMappingModeConfig*(
    table: TomlTableRef,
    target: var OrderedTable[string, string],
    vr: var ValidationResult,
    section: string,
    validCommands: HashSet[string],
) =
  for key, value in table:
    if value.kind != TomlValueKind.String:
      vr.addError(fullKey(section, key), $value, "string")
      continue

    # LHS (key) validation
    let lhsKeys = parseKeyString(key)
    if lhsKeys.len == 0:
      vr.addError(
        fullKey(section, key), key, "valid key (e.g. \"C-s\", \"jj\", \"g d\")"
      )
      continue

    # RHS (target) validation: command name or key sequence.
    # An identifier-like token (e.g. "bnext") that is not a known command would
    # otherwise silently fall through to Vim-style concatenated parsing
    # (b,n,e,x,t). Reject that explicitly so the user notices the typo.
    let rhs = value.getStr()
    let rhsKeys = parseKeyString(rhs)
    if rhs in validCommands:
      discard
    elif rhsKeys.len == 0:
      vr.addError(fullKey(section, key), rhs, "valid command name or key sequence")
      continue
    elif rhsKeys.len == rhs.len and rhs.len >= 3 and
        rhs.allCharsInSet({'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}):
      # Vim-concat fallback was used: every char in rhs became its own KeyCombo.
      # For 3+ char identifier-like tokens this almost always means the user
      # typed an unknown command name rather than a multi-key sequence (2-char
      # Vim sequences like "jj"/"gd" fall below the len >= 3 gate and stay
      # accepted as key sequences).
      vr.addError(
        fullKey(section, key),
        rhs,
        "known command name (single identifier-like targets are treated as commands; " &
          "use space-separated keys like \"b n e x t\" for a key sequence)",
      )
      continue

    target[key] = rhs

proc loadKeyMappingConfig*(
    table: TomlTableRef, config: var KeyMappingConfig, vr: var ValidationResult
) =
  const section = "KeyMapping"
  const validKeys = [
    "All", "Normal", "Insert", "Visual", "VisualAll", "VisualLine", "VisualBlock",
    "Replace", "Command", "Filer", "LogViewer", "Help", "BufferManager",
    "BackupManager", "DiffViewer", "Config", "References", "DocumentSymbol",
    "CallHierarchy", "RecentFile", "Debug", "Terminal",
  ]
  checkUnknownKeys(table, validKeys, section, vr)

  let validCommands = getValidMappingCommands()

  if table.hasKey("All"):
    loadKeyMappingModeConfig(
      table["All"].getTable(), config.all, vr, "KeyMapping.All", validCommands
    )
  if table.hasKey("Normal"):
    loadKeyMappingModeConfig(
      table["Normal"].getTable(), config.normal, vr, "KeyMapping.Normal", validCommands
    )
  if table.hasKey("Insert"):
    loadKeyMappingModeConfig(
      table["Insert"].getTable(), config.insert, vr, "KeyMapping.Insert", validCommands
    )
  if table.hasKey("Visual"):
    loadKeyMappingModeConfig(
      table["Visual"].getTable(), config.visual, vr, "KeyMapping.Visual", validCommands
    )
  if table.hasKey("VisualAll"):
    loadKeyMappingModeConfig(
      table["VisualAll"].getTable(),
      config.visualAll,
      vr,
      "KeyMapping.VisualAll",
      validCommands,
    )
  if table.hasKey("VisualLine"):
    loadKeyMappingModeConfig(
      table["VisualLine"].getTable(),
      config.visualLine,
      vr,
      "KeyMapping.VisualLine",
      validCommands,
    )
  if table.hasKey("VisualBlock"):
    loadKeyMappingModeConfig(
      table["VisualBlock"].getTable(),
      config.visualBlock,
      vr,
      "KeyMapping.VisualBlock",
      validCommands,
    )
  if table.hasKey("Replace"):
    loadKeyMappingModeConfig(
      table["Replace"].getTable(),
      config.replace,
      vr,
      "KeyMapping.Replace",
      validCommands,
    )
  if table.hasKey("Command"):
    loadKeyMappingModeConfig(
      table["Command"].getTable(),
      config.command,
      vr,
      "KeyMapping.Command",
      validCommands,
    )
  if table.hasKey("Filer"):
    loadKeyMappingModeConfig(
      table["Filer"].getTable(), config.filer, vr, "KeyMapping.Filer", validCommands
    )
  if table.hasKey("LogViewer"):
    loadKeyMappingModeConfig(
      table["LogViewer"].getTable(),
      config.logViewer,
      vr,
      "KeyMapping.LogViewer",
      validCommands,
    )
  if table.hasKey("Help"):
    loadKeyMappingModeConfig(
      table["Help"].getTable(), config.help, vr, "KeyMapping.Help", validCommands
    )
  if table.hasKey("BufferManager"):
    loadKeyMappingModeConfig(
      table["BufferManager"].getTable(),
      config.bufferManager,
      vr,
      "KeyMapping.BufferManager",
      validCommands,
    )
  if table.hasKey("BackupManager"):
    loadKeyMappingModeConfig(
      table["BackupManager"].getTable(),
      config.backupManager,
      vr,
      "KeyMapping.BackupManager",
      validCommands,
    )
  if table.hasKey("DiffViewer"):
    loadKeyMappingModeConfig(
      table["DiffViewer"].getTable(),
      config.diffViewer,
      vr,
      "KeyMapping.DiffViewer",
      validCommands,
    )
  if table.hasKey("Config"):
    loadKeyMappingModeConfig(
      table["Config"].getTable(), config.config, vr, "KeyMapping.Config", validCommands
    )
  if table.hasKey("References"):
    loadKeyMappingModeConfig(
      table["References"].getTable(),
      config.references,
      vr,
      "KeyMapping.References",
      validCommands,
    )
  if table.hasKey("DocumentSymbol"):
    loadKeyMappingModeConfig(
      table["DocumentSymbol"].getTable(),
      config.documentSymbol,
      vr,
      "KeyMapping.DocumentSymbol",
      validCommands,
    )
  if table.hasKey("CallHierarchy"):
    loadKeyMappingModeConfig(
      table["CallHierarchy"].getTable(),
      config.callHierarchy,
      vr,
      "KeyMapping.CallHierarchy",
      validCommands,
    )
  if table.hasKey("RecentFile"):
    loadKeyMappingModeConfig(
      table["RecentFile"].getTable(),
      config.recentFile,
      vr,
      "KeyMapping.RecentFile",
      validCommands,
    )
  if table.hasKey("Debug"):
    loadKeyMappingModeConfig(
      table["Debug"].getTable(), config.debug, vr, "KeyMapping.Debug", validCommands
    )
  if table.hasKey("Terminal"):
    loadKeyMappingModeConfig(
      table["Terminal"].getTable(),
      config.terminal,
      vr,
      "KeyMapping.Terminal",
      validCommands,
    )

proc appendKeyMappingToml*(lines: var seq[string], cfg: KeyMappingConfig) =
  ## Only emit modes that contain at least one mapping (mirrors prior behavior).
  if cfg.all.len > 0:
    lines.add "[KeyMapping.All]"
    for lhs, rhs in cfg.all:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.normal.len > 0:
    lines.add "[KeyMapping.Normal]"
    for lhs, rhs in cfg.normal:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.insert.len > 0:
    lines.add "[KeyMapping.Insert]"
    for lhs, rhs in cfg.insert:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.visual.len > 0:
    lines.add "[KeyMapping.Visual]"
    for lhs, rhs in cfg.visual:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.visualAll.len > 0:
    lines.add "[KeyMapping.VisualAll]"
    for lhs, rhs in cfg.visualAll:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.visualLine.len > 0:
    lines.add "[KeyMapping.VisualLine]"
    for lhs, rhs in cfg.visualLine:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.visualBlock.len > 0:
    lines.add "[KeyMapping.VisualBlock]"
    for lhs, rhs in cfg.visualBlock:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.replace.len > 0:
    lines.add "[KeyMapping.Replace]"
    for lhs, rhs in cfg.replace:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.command.len > 0:
    lines.add "[KeyMapping.Command]"
    for lhs, rhs in cfg.command:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.filer.len > 0:
    lines.add "[KeyMapping.Filer]"
    for lhs, rhs in cfg.filer:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.logViewer.len > 0:
    lines.add "[KeyMapping.LogViewer]"
    for lhs, rhs in cfg.logViewer:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.help.len > 0:
    lines.add "[KeyMapping.Help]"
    for lhs, rhs in cfg.help:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.bufferManager.len > 0:
    lines.add "[KeyMapping.BufferManager]"
    for lhs, rhs in cfg.bufferManager:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.backupManager.len > 0:
    lines.add "[KeyMapping.BackupManager]"
    for lhs, rhs in cfg.backupManager:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.diffViewer.len > 0:
    lines.add "[KeyMapping.DiffViewer]"
    for lhs, rhs in cfg.diffViewer:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.config.len > 0:
    lines.add "[KeyMapping.Config]"
    for lhs, rhs in cfg.config:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.references.len > 0:
    lines.add "[KeyMapping.References]"
    for lhs, rhs in cfg.references:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.documentSymbol.len > 0:
    lines.add "[KeyMapping.DocumentSymbol]"
    for lhs, rhs in cfg.documentSymbol:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.callHierarchy.len > 0:
    lines.add "[KeyMapping.CallHierarchy]"
    for lhs, rhs in cfg.callHierarchy:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.recentFile.len > 0:
    lines.add "[KeyMapping.RecentFile]"
    for lhs, rhs in cfg.recentFile:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.debug.len > 0:
    lines.add "[KeyMapping.Debug]"
    for lhs, rhs in cfg.debug:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""

  if cfg.terminal.len > 0:
    lines.add "[KeyMapping.Terminal]"
    for lhs, rhs in cfg.terminal:
      lines.add toTomlString(lhs) & " = " & toTomlString(rhs)
    lines.add ""
