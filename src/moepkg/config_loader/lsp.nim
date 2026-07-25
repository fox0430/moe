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

## TOML loader and serializer for the [Lsp] section (including per-feature
## sub-tables and dynamic per-language-server entries).
##
## `[Lsp]` is a section group: the parent keys and every `[Lsp.<Feature>]`
## sub-table are derived from `LspConfig`'s `{.cfg.}` / `{.cfgSubSection.}`
## fields, so declaring a feature on the type is all that is needed to load,
## validate, save and document it. Only the dynamic `[Lsp.<languageId>]`
## keyspace is hand-written — it has no fields to derive from.

import std/[algorithm, json, sequtils, strformat, tables]

import pkg/parsetoml

import ../[config, config_macros, logger]

import base, save_base

# Top-level TOML section name handled by this module, from the type itself.
const LspSectionName* = cfgGroupName(LspConfig)

# Keys accepted inside an `[Lsp.<languageId>]` table. Also the probe for
# telling a language server from a typo'd feature name.
const LspServerConfigKeys = [
  "extensions", "command", "trace", "settings", "rustAnalyzerRunSingle",
  "rustAnalyzerDebugSingle",
]

proc tomlValueToJson*(v: TomlValueRef): JsonNode =
  case v.kind
  of TomlValueKind.None:
    result = newJNull()
  of TomlValueKind.Int:
    result = newJInt(v.getInt())
  of TomlValueKind.Float:
    result = newJFloat(v.getFloat())
  of TomlValueKind.Bool:
    result = newJBool(v.getBool())
  of TomlValueKind.String:
    result = newJString(v.getStr())
  of TomlValueKind.Datetime, TomlValueKind.Date, TomlValueKind.Time:
    result = newJString($v)
  of TomlValueKind.Array:
    result = newJArray()
    for elem in v.getElems():
      result.add(tomlValueToJson(elem))
  of TomlValueKind.Table:
    result = newJObject()
    let t = v.getTable()
    for key, val in t.pairs:
      result[key] = tomlValueToJson(val)

proc loadLspServerConfig*(
    table: TomlTableRef, vr: var ValidationResult, section: string
): LspServerConfig =
  checkUnknownKeys(table, LspServerConfigKeys, section, vr)
  result = LspServerConfig(
    extensions: @[],
    command: "",
    trace: ltOff,
    settings: "",
    rustAnalyzerRunSingle: false,
    rustAnalyzerDebugSingle: false,
  )
  loadStringArray(table, "extensions", result.extensions, vr, section)
  loadString(table, "command", result.command, vr, section)
  loadEnum(
    table, "trace", result.trace, vr, section, parseLspTraceLevel, ValidLspTraceLevels
  )
  if table.hasKey("settings"):
    let val = table["settings"]
    if val.kind == TomlValueKind.Table:
      result.settings = $tomlValueToJson(val)
    else:
      vr.addError(fullKey(section, "settings"), $val, "table")
  loadBool(table, "rustAnalyzerRunSingle", result.rustAnalyzerRunSingle, vr, section)
  loadBool(
    table, "rustAnalyzerDebugSingle", result.rustAnalyzerDebugSingle, vr, section
  )

proc loadLspConfig*(
    table: TomlTableRef, config: var LspConfig, vr: var ValidationResult
) =
  const section = LspSectionName
  generateSectionGroupLoader(table, config, vr, LspConfig)

  # Language server configs (any key that's not a known feature is a language server)
  const knownKeys = generateSectionGroupKeys(LspConfig)
  for key, value in table:
    if key notin knownKeys:
      if value.kind == TomlValueKind.Table:
        let serverTable = value.getTable()
        # A language-server entry must declare at least one server config key.
        # Otherwise treat it as a typo'd feature name (e.g. `[Lsp.Completin]`)
        # rather than silently absorbing it as a server config.
        var isServerConfig = false
        for k in LspServerConfigKeys:
          if serverTable.hasKey(k):
            isServerConfig = true
            break
        if isServerConfig:
          config.servers[key] =
            loadLspServerConfig(serverTable, vr, fullKey(section, key))
        else:
          vr.addUnknownKey(fullKey(section, key))
      else:
        vr.addUnknownKey(fullKey(section, key))

# Serializer

proc jsonToTomlInline*(n: JsonNode): string =
  case n.kind
  of JObject:
    result = "{"
    var first = true
    for key, val in n:
      # TOML has no null literal; omit null-valued keys so they round-trip as
      # absent rather than being corrupted into an empty string.
      if val.kind == JNull:
        continue
      if not first:
        result.add ", "
      first = false
      result.add toTomlKey(key) & " = " & jsonToTomlInline(val)
    result.add "}"
  of JArray:
    result = "["
    var idx = 0
    for elem in n:
      if idx > 0:
        result.add ", "
      result.add jsonToTomlInline(elem)
      inc idx
    result.add "]"
  of JString:
    result = toTomlString(n.getStr)
  of JInt:
    result = $n.getInt
  of JFloat:
    result = $n.getFloat
  of JBool:
    result = toTomlBool(n.getBool)
  of JNull:
    result = "\"\""

proc appendLspToml*(lines: var seq[string], cfg: LspConfig) =
  generateSectionGroupSerializer(lines, cfg, LspConfig)

  # Lsp language server configs (sorted for deterministic output)
  for name in toSeq(cfg.servers.keys).sorted:
    let server = cfg.servers[name]
    lines.add "[Lsp." & name & "]"
    lines.add "extensions = " & toTomlStringArray(server.extensions)
    lines.add "command = " & toTomlString(server.command)
    lines.add "trace = " & toTomlString($server.trace)
    if server.settings.len > 0:
      try:
        lines.add "settings = " & jsonToTomlInline(parseJson(server.settings))
      except JsonParsingError as e:
        logWarn("config_loader/lsp", &"Invalid JSON in settings for '{name}': {e.msg}")
    lines.add "rustAnalyzerRunSingle = " & toTomlBool(server.rustAnalyzerRunSingle)
    lines.add "rustAnalyzerDebugSingle = " & toTomlBool(server.rustAnalyzerDebugSingle)
    lines.add ""
