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
## per-mode sub-table maps a key sequence (LHS) to an RHS that is either a bare
## TOML string (command name / key sequence, like `jj = "Escape"`) or an inline
## table escape hatch (`x = { keys = "dd", noremap = false }`) carrying noremap,
## args, and a force-key-sequence flag. This is moe's single keymap surface;
## command-name validity is checked once at apply time against the real registry
## (see editor_init.applyKeyMappings), not here.

import std/[os, tables, strutils]

import pkg/parsetoml

import ../[config, key_bindings, modes]

import base, save_base

# Top-level TOML section name handled by this module.
const KeyMappingSectionName* = "KeyMapping"

# Allowed [KeyMapping.<key>] section names. "All"/"VisualAll" are meta sections;
# the rest are generated from EditorMode so a new mode is accepted automatically
# and a rename/removal is a compile error instead of a silent load-time drift.
const ValidKeyMappingSections = block:
  var s = @["All", "VisualAll"]
  for m in EditorMode:
    s.add($m)
  s

proc loadKeyMappingModeConfig*(
    table: TomlTableRef,
    target: var OrderedTable[string, KeyMappingEntry],
    vr: var ValidationResult,
    section: string,
) =
  ## Load one [KeyMapping.<mode>] sub-table. A string value is the terse form;
  ## an inline table is the structured escape hatch. Only structural validation
  ## happens here (key parse, types, mutual exclusion); command existence is
  ## validated at apply time against the real registry.
  for key, value in table:
    # LHS (key) validation.
    let lhsKeys = parseKeyString(key)
    if lhsKeys.len == 0:
      vr.addError(
        fullKey(section, key), key, "valid key (e.g. \"C-s\", \"jj\", \"g d\")"
      )
      continue

    case value.kind
    of TomlValueKind.String:
      let rhs = value.getStr()
      if rhs.len == 0:
        vr.addError(
          fullKey(section, key), rhs, "non-empty command name or key sequence"
        )
        continue
      target[key] = KeyMappingEntry(rhs: rhs, noremap: true)
    of TomlValueKind.Table:
      let t = value.getTable()
      let hasCommand = t.hasKey("command")
      let hasKeys = t.hasKey("keys")
      if hasCommand and hasKeys:
        vr.addError(
          fullKey(section, key), "command + keys", "exactly one of 'command' or 'keys'"
        )
        continue
      if not (hasCommand or hasKeys):
        vr.addError(
          fullKey(section, key), $value.kind, "inline table with 'command' or 'keys'"
        )
        continue

      var entry = KeyMappingEntry(noremap: true)

      # RHS: either a forced key sequence ('keys') or a command target ('command').
      if hasKeys:
        if t["keys"].kind != TomlValueKind.String:
          vr.addError(fullKey(section, key) & ".keys", $t["keys"].kind, "string")
          continue
        let keys = t["keys"].getStr()
        if parseKeyString(keys).len == 0:
          vr.addError(fullKey(section, key) & ".keys", keys, "valid key sequence")
          continue
        entry.rhs = keys
        entry.forceKeySeq = true
      else:
        if t["command"].kind != TomlValueKind.String:
          vr.addError(fullKey(section, key) & ".command", $t["command"].kind, "string")
          continue
        let cmd = t["command"].getStr()
        if cmd.len == 0:
          vr.addError(fullKey(section, key) & ".command", cmd, "non-empty command name")
          continue
        entry.rhs = cmd

      # args (only valid alongside 'command').
      if t.hasKey("args"):
        if hasKeys:
          vr.addError(
            fullKey(section, key), "keys + args", "'args' only with 'command'"
          )
          continue
        if t["args"].kind != TomlValueKind.Array:
          vr.addError(
            fullKey(section, key) & ".args", $t["args"].kind, "array of strings"
          )
          continue
        var args: seq[string] = @[]
        var ok = true
        for i, item in t["args"].getElems():
          if item.kind != TomlValueKind.String:
            vr.addError(
              fullKey(section, key) & ".args[" & $i & "]", $item.kind, "string"
            )
            ok = false
          else:
            args.add item.getStr()
        if not ok:
          continue
        entry.args = args

      # noremap (default true).
      if t.hasKey("noremap"):
        if t["noremap"].kind != TomlValueKind.Bool:
          vr.addError(
            fullKey(section, key) & ".noremap",
            $t["noremap"].kind,
            "boolean (true/false)",
          )
          continue
        entry.noremap = t["noremap"].getBool()

      target[key] = entry
    else:
      vr.addError(fullKey(section, key), $value.kind, "string or inline table")
      continue

proc loadKeyMappingConfig*(
    table: TomlTableRef,
    config: var KeyMappingConfig,
    vr: var ValidationResult,
    section = KeyMappingSectionName,
) =
  ## `section` is the error-label prefix: "KeyMapping" for moerc.toml's
  ## [KeyMapping.*] sections, or "" for a dedicated keymap file whose mode
  ## tables sit at the top level (so labels read "Normal.jj", not the
  ## non-existent "KeyMapping.Normal.jj").
  checkUnknownKeys(table, ValidKeyMappingSections, section, vr)

  for key in ValidKeyMappingSections:
    if not table.hasKey(key):
      continue
    if table[key].kind != TomlValueKind.Table:
      vr.addError(fullKey(section, key), $table[key].kind, "table")
      continue
    let
      sub = table[key].getTable()
      secName = fullKey(section, key)
    case key
    of "All":
      loadKeyMappingModeConfig(sub, config.all, vr, secName)
    of "VisualAll":
      loadKeyMappingModeConfig(sub, config.visualAll, vr, secName)
    else:
      # All remaining section names match EditorMode members exactly.
      let mode = parseEnum[EditorMode](key)
      loadKeyMappingModeConfig(sub, config.perMode[mode], vr, secName)

proc getKeyMappingFilePath*(): string =
  ## Standard search locations for the optional dedicated keymap file. Returns
  ## "" when none exists.
  ## 1. $XDG_CONFIG_HOME/moe/keybindings.toml
  ## 2. ~/.config/moe/keybindings.toml
  ## 3. ./keybindings.toml
  let paths = [
    getConfigDir() / "moe" / "keybindings.toml",
    getHomeDir() / ".config" / "moe" / "keybindings.toml",
    "keybindings.toml",
  ]
  for p in paths:
    if fileExists(p):
      return p

proc loadKeyMappingFile*(config: var KeyMappingConfig, vr: var ValidationResult) =
  ## Merge the optional dedicated keymap file into `config`. The file uses the
  ## same per-mode entry format as moerc.toml's [KeyMapping] section, but with
  ## the mode tables at the top level (`[Normal]`, `[Insert]`, `[All]`, …) since
  ## the whole file is keymaps. Entries here override moerc.toml [KeyMapping]
  ## entries for the same key in the same mode (it is loaded last).
  let path = getKeyMappingFilePath()
  if path.len == 0:
    return
  var toml: TomlValueRef
  try:
    toml = parseFile(path)
  except CatchableError:
    vr.addError("keybindings", getCurrentExceptionMsg(), "valid TOML file")
    return
  # Top-level mode sections (no "KeyMapping" prefix) → empty error-label prefix.
  loadKeyMappingConfig(toml.getTable(), config, vr, section = "")

proc isTerseEntry(e: KeyMappingEntry): bool =
  ## A fully-default entry serializes back to the terse `lhs = "rhs"` string.
  e.args.len == 0 and not e.forceKeySeq and e.noremap

proc entryToToml(e: KeyMappingEntry): string =
  if e.isTerseEntry:
    return toTomlString(e.rhs)
  var parts: seq[string]
  if e.forceKeySeq:
    parts.add "keys = " & toTomlString(e.rhs)
  else:
    parts.add "command = " & toTomlString(e.rhs)
  if e.args.len > 0:
    var arr = "["
    for i, a in e.args:
      if i > 0:
        arr.add ", "
      arr.add toTomlString(a)
    arr.add "]"
    parts.add "args = " & arr
  if not e.noremap:
    parts.add "noremap = false"
  "{ " & parts.join(", ") & " }"

proc emitKeyMappingSection(
    lines: var seq[string], name: string, t: OrderedTable[string, KeyMappingEntry]
) =
  ## Emit a section only when it holds at least one mapping (mirrors prior
  ## behavior). Terse entries stay terse; structured ones become inline tables.
  if t.len == 0:
    return
  lines.add "[" & KeyMappingSectionName & "." & name & "]"
  for lhs, e in t:
    lines.add toTomlString(lhs) & " = " & entryToToml(e)
  lines.add ""

proc appendKeyMappingToml*(lines: var seq[string], cfg: KeyMappingConfig) =
  emitKeyMappingSection(lines, "All", cfg.all)
  emitKeyMappingSection(lines, "VisualAll", cfg.visualAll)
  for mode in EditorMode:
    emitKeyMappingSection(lines, $mode, cfg.perMode[mode])
