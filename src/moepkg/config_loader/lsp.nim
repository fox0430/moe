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
import ../lsp/default_servers

import base, save_base

# Top-level TOML section name handled by this module, from the type itself.
const LspSectionName* = cfgGroupName(LspConfig)

# Deprecated bool keys, each standing for one `clientCommands` entry. Not
# `{.cfgDeprecated.}`: `[Lsp.<languageId>]` has no type to derive from. To drop
# them, delete this table and its uses.
const DeprecatedClientCommandKeys = [
  ("rustAnalyzerRunSingle", RunSingleCommand),
  ("rustAnalyzerDebugSingle", DebugSingleCommand),
]

# Documented server keys of an `[Lsp.<languageId>]` table.
const LspServerConfigKeys =
  ["extensions", "command", "trace", "settings", "clientCommands"]

# Server keys accepted inside an `[Lsp.<languageId>]` table.
const LspServerKeys = @LspServerConfigKeys & DeprecatedClientCommandKeys.mapIt(it[0])

# `[Lsp.<Feature>]` names, also accepted as `[Lsp.<languageId>.<Feature>]`.
const LspFeatureNames = generateSectionGroupChildNames(LspConfig)

# Keys accepted inside an `[Lsp.<languageId>]` table.
const LspLanguageKeys = LspServerKeys & @LspFeatureNames

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

proc loadDeprecatedClientCommands(
    table: TomlTableRef,
    commands: var seq[string],
    vr: var ValidationResult,
    section: string,
) =
  ## The deprecated keys apply only while `clientCommands` is not written.
  var keys, deprecatedCommands: seq[string]
  for (key, command) in DeprecatedClientCommandKeys:
    var enabled = false
    loadBool(table, key, enabled, vr, section)
    # Skips `false`, which `:putConfigFile` used to write for every language.
    if enabled:
      keys.add key
      deprecatedCommands.add command
  let overridden = table.hasKey("clientCommands")
  let msg =
    if overridden:
      "ignored because clientCommands is set"
    else:
      "use clientCommands = " & toTomlStringArray(deprecatedCommands) & " instead"
  for key in keys:
    vr.addDeprecated(fullKey(section, key), msg)
  if not overridden:
    commands = deprecatedCommands

proc loadLspServerConfig*(
    table: TomlTableRef, vr: var ValidationResult, section: string
): LspServerConfig =
  result = LspServerConfig(extensions: @[], command: "", trace: ltOff, settings: "")
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
  loadEnumStringArray(
    table, "clientCommands", result.clientCommands, RunnableCommands, vr, section
  )
  result.clientCommands = result.clientCommands.deduplicate
  loadDeprecatedClientCommands(table, result.clientCommands, vr, section)

proc loadLspLanguageFeatures(
    table: TomlTableRef, vr: var ValidationResult, section: string
): Table[string, bool] =
  ## The `[<section>.<Feature>]` tables of a language entry, by feature name.
  ## A table without a valid `enable` sets nothing.
  for name in LspFeatureNames:
    if not expectTable(table, name, vr, section):
      continue
    let
      featureSection = fullKey(section, name)
      featureTable = table[name].getTable()
    checkUnknownKeys(featureTable, [LspLanguageFeatureKey], featureSection, vr)
    if featureTable.hasKey(LspLanguageFeatureKey):
      var enable = false
      loadBool(featureTable, LspLanguageFeatureKey, enable, vr, featureSection)
      if featureTable[LspLanguageFeatureKey].kind == TomlValueKind.Bool:
        result[name] = enable

proc loadLspConfig*(
    table: TomlTableRef, config: var LspConfig, vr: var ValidationResult
) =
  const section = LspSectionName
  generateSectionGroupLoader(table, config, vr, LspConfig)

  # Any other key is a language entry: server keys and/or feature sub-tables.
  const knownKeys = generateSectionGroupKeys(LspConfig)
  for key, value in table:
    if key in knownKeys:
      continue
    let langSection = fullKey(section, key)
    if value.kind != TomlValueKind.Table:
      vr.addUnknownKey(langSection)
      continue
    let langTable = value.getTable()
    var hasServerKey, hasSubTable = false
    for k, v in langTable:
      if k in LspServerKeys:
        hasServerKey = true
      elif v.kind == TomlValueKind.Table:
        hasSubTable = true
    # Not a language: a typo'd feature name (e.g. `[Lsp.Completin]`), or
    # feature tables under a language with no server (e.g. `[Lsp.rsut.Hover]`).
    if not hasServerKey and not (hasSubTable and isDefaultLspLanguage(key)):
      vr.addUnknownKey(langSection)
      continue
    checkUnknownKeys(langTable, LspLanguageKeys, langSection, vr)
    if hasServerKey:
      config.servers[key] = loadLspServerConfig(langTable, vr, langSection)
    let features = loadLspLanguageFeatures(langTable, vr, langSection)
    if features.len > 0:
      config.languageFeatures[key] = features

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

proc appendLspServerToml(
    lines: var seq[string], name: string, server: LspServerConfig
) =
  lines.add "[Lsp." & name & "]"
  lines.add "extensions = " & toTomlStringArray(server.extensions)
  lines.add "command = " & toTomlString(server.command)
  lines.add "trace = " & toTomlString($server.trace)
  if server.settings.len > 0:
    try:
      lines.add "settings = " & jsonToTomlInline(parseJson(server.settings))
    except JsonParsingError as e:
      logWarn("config_loader/lsp", &"Invalid JSON in settings for '{name}': {e.msg}")
  if server.clientCommands.len > 0:
    lines.add "clientCommands = " & toTomlStringArray(server.clientCommands)
  lines.add ""

proc appendLspToml*(lines: var seq[string], cfg: LspConfig) =
  generateSectionGroupSerializer(lines, cfg, LspConfig)

  # Language entries, sorted for deterministic output
  var names = toSeq(cfg.servers.keys)
  for name in cfg.languageFeatures.keys:
    if name notin cfg.servers:
      names.add name
  for name in names.sorted:
    if name in cfg.servers:
      lines.appendLspServerToml(name, cfg.servers[name])
    if name in cfg.languageFeatures:
      let features = cfg.languageFeatures[name]
      for feature in toSeq(features.keys).sorted:
        lines.add "[Lsp." & name & "." & feature & "]"
        lines.add LspLanguageFeatureKey & " = " & toTomlBool(features[feature])
        lines.add ""
