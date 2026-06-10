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

import std/[algorithm, sequtils, tables]

import pkg/parsetoml

import ../config

import base, save_base

# Top-level TOML section name handled by this module.
const LspSectionName* = "Lsp"

# Per-feature helpers

proc loadLspFeatureConfig*(
    table: TomlTableRef,
    config: var LspFeatureConfig,
    vr: var ValidationResult,
    section: string,
) =
  const validKeys = ["enable"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)

proc loadLspOpenWindowConfig*(
    table: TomlTableRef,
    config: var LspOpenWindowConfig,
    vr: var ValidationResult,
    section: string,
) =
  const validKeys = ["enable", "openWindow"]
  checkUnknownKeys(table, validKeys, section, vr)
  loadBool(table, "enable", config.enable, vr, section)
  loadBool(table, "openWindow", config.openWindow, vr, section)

proc loadLspServerConfig*(
    table: TomlTableRef, vr: var ValidationResult, section: string
): LspServerConfig =
  const validKeys = [
    "extensions", "command", "trace", "rustAnalyzerRunSingle", "rustAnalyzerDebugSingle"
  ]
  checkUnknownKeys(table, validKeys, section, vr)
  result = LspServerConfig(
    extensions: @[],
    command: "",
    trace: ltOff,
    rustAnalyzerRunSingle: false,
    rustAnalyzerDebugSingle: false,
  )
  loadStringArray(table, "extensions", result.extensions, vr, section)
  loadString(table, "command", result.command, vr, section)
  loadEnum(
    table, "trace", result.trace, vr, section, parseLspTraceLevel, ValidLspTraceLevels
  )
  loadBool(table, "rustAnalyzerRunSingle", result.rustAnalyzerRunSingle, vr, section)
  loadBool(
    table, "rustAnalyzerDebugSingle", result.rustAnalyzerDebugSingle, vr, section
  )

proc loadLspConfig*(
    table: TomlTableRef, config: var LspConfig, vr: var ValidationResult
) =
  const section = "Lsp"
  # Main LSP settings
  loadBool(table, "enable", config.enable, vr, section)
  loadInt(table, "timeout", config.timeout, vr, section, minVal = 1)

  # Feature configs
  if table.hasKey("Completion"):
    loadLspFeatureConfig(
      table["Completion"].getTable(), config.completion, vr, "Lsp.Completion"
    )
  if table.hasKey("Declaration"):
    loadLspOpenWindowConfig(
      table["Declaration"].getTable(), config.declaration, vr, "Lsp.Declaration"
    )
  if table.hasKey("Definition"):
    loadLspOpenWindowConfig(
      table["Definition"].getTable(), config.definition, vr, "Lsp.Definition"
    )
  if table.hasKey("TypeDefinition"):
    loadLspOpenWindowConfig(
      table["TypeDefinition"].getTable(),
      config.typeDefinition,
      vr,
      "Lsp.TypeDefinition",
    )
  if table.hasKey("Implementation"):
    loadLspOpenWindowConfig(
      table["Implementation"].getTable(),
      config.implementation,
      vr,
      "Lsp.Implementation",
    )
  if table.hasKey("Diagnostics"):
    let diagTable = table["Diagnostics"].getTable()
    const diagValidKeys = ["enable", "autoHover", "autoHoverDelay"]
    checkUnknownKeys(diagTable, diagValidKeys, "Lsp.Diagnostics", vr)
    loadBool(diagTable, "enable", config.diagnostics.enable, vr, "Lsp.Diagnostics")
    loadBool(
      diagTable, "autoHover", config.diagnostics.autoHover, vr, "Lsp.Diagnostics"
    )
    loadInt(
      diagTable,
      "autoHoverDelay",
      config.diagnostics.autoHoverDelay,
      vr,
      "Lsp.Diagnostics",
      minVal = 0,
    )
  if table.hasKey("SignatureHelp"):
    loadLspFeatureConfig(
      table["SignatureHelp"].getTable(), config.signatureHelp, vr, "Lsp.SignatureHelp"
    )
  if table.hasKey("DocumentFormatting"):
    loadLspFeatureConfig(
      table["DocumentFormatting"].getTable(),
      config.documentFormatting,
      vr,
      "Lsp.DocumentFormatting",
    )
  if table.hasKey("FoldingRange"):
    loadLspFeatureConfig(
      table["FoldingRange"].getTable(), config.foldingRange, vr, "Lsp.FoldingRange"
    )
  if table.hasKey("SelectionRange"):
    loadLspFeatureConfig(
      table["SelectionRange"].getTable(),
      config.selectionRange,
      vr,
      "Lsp.SelectionRange",
    )
  if table.hasKey("DocumentSymbol"):
    loadLspFeatureConfig(
      table["DocumentSymbol"].getTable(),
      config.documentSymbol,
      vr,
      "Lsp.DocumentSymbol",
    )
  if table.hasKey("Hover"):
    loadLspFeatureConfig(table["Hover"].getTable(), config.hover, vr, "Lsp.Hover")
  if table.hasKey("InlayHint"):
    loadLspFeatureConfig(
      table["InlayHint"].getTable(), config.inlayHint, vr, "Lsp.InlayHint"
    )
  if table.hasKey("References"):
    loadLspFeatureConfig(
      table["References"].getTable(), config.references, vr, "Lsp.References"
    )
  if table.hasKey("CallHierarchy"):
    loadLspFeatureConfig(
      table["CallHierarchy"].getTable(), config.callHierarchy, vr, "Lsp.CallHierarchy"
    )
  if table.hasKey("DocumentHighlight"):
    loadLspFeatureConfig(
      table["DocumentHighlight"].getTable(),
      config.documentHighlight,
      vr,
      "Lsp.DocumentHighlight",
    )
  if table.hasKey("DocumentLink"):
    loadLspFeatureConfig(
      table["DocumentLink"].getTable(), config.documentLink, vr, "Lsp.DocumentLink"
    )
  if table.hasKey("CodeLens"):
    loadLspFeatureConfig(
      table["CodeLens"].getTable(), config.codeLens, vr, "Lsp.CodeLens"
    )
  if table.hasKey("Rename"):
    loadLspFeatureConfig(table["Rename"].getTable(), config.rename, vr, "Lsp.Rename")
  if table.hasKey("SemanticTokens"):
    loadLspFeatureConfig(
      table["SemanticTokens"].getTable(),
      config.semanticTokens,
      vr,
      "Lsp.SemanticTokens",
    )
  if table.hasKey("ExecuteCommand"):
    loadLspFeatureConfig(
      table["ExecuteCommand"].getTable(),
      config.executeCommand,
      vr,
      "Lsp.ExecuteCommand",
    )

  # Language server configs (any key that's not a known feature is a language server)
  const knownKeys = [
    "enable", "timeout", "Completion", "Declaration", "Definition", "TypeDefinition",
    "Implementation", "Diagnostics", "SignatureHelp", "DocumentFormatting",
    "FoldingRange", "SelectionRange", "DocumentSymbol", "Hover", "InlayHint",
    "References", "CallHierarchy", "DocumentHighlight", "DocumentLink", "CodeLens",
    "Rename", "SemanticTokens", "ExecuteCommand",
  ]
  const serverConfigKeys = [
    "extensions", "command", "trace", "rustAnalyzerRunSingle", "rustAnalyzerDebugSingle"
  ]
  for key, value in table:
    if key notin knownKeys:
      if value.kind == TomlValueKind.Table:
        let serverTable = value.getTable()
        # A language-server entry must declare at least one server config key.
        # Otherwise treat it as a typo'd feature name (e.g. `[Lsp.Completin]`)
        # rather than silently absorbing it as a server config.
        var isServerConfig = false
        for k in serverConfigKeys:
          if serverTable.hasKey(k):
            isServerConfig = true
            break
        if isServerConfig:
          config.servers[key] = loadLspServerConfig(serverTable, vr, "Lsp." & key)
        else:
          vr.addUnknownKey(fullKey(section, key))
      else:
        vr.addUnknownKey(fullKey(section, key))

# Serializer

proc appendLspToml*(lines: var seq[string], cfg: LspConfig) =
  lines.add "[Lsp]"
  lines.add "enable = " & toTomlBool(cfg.enable)
  lines.add "timeout = " & $cfg.timeout
  lines.add ""

  # Lsp feature configs
  lines.add "[Lsp.Completion]"
  lines.add "enable = " & toTomlBool(cfg.completion.enable)
  lines.add ""

  lines.add "[Lsp.Declaration]"
  lines.add "enable = " & toTomlBool(cfg.declaration.enable)
  lines.add "openWindow = " & toTomlBool(cfg.declaration.openWindow)
  lines.add ""

  lines.add "[Lsp.Definition]"
  lines.add "enable = " & toTomlBool(cfg.definition.enable)
  lines.add "openWindow = " & toTomlBool(cfg.definition.openWindow)
  lines.add ""

  lines.add "[Lsp.TypeDefinition]"
  lines.add "enable = " & toTomlBool(cfg.typeDefinition.enable)
  lines.add "openWindow = " & toTomlBool(cfg.typeDefinition.openWindow)
  lines.add ""

  lines.add "[Lsp.Implementation]"
  lines.add "enable = " & toTomlBool(cfg.implementation.enable)
  lines.add "openWindow = " & toTomlBool(cfg.implementation.openWindow)
  lines.add ""

  lines.add "[Lsp.Diagnostics]"
  lines.add "enable = " & toTomlBool(cfg.diagnostics.enable)
  lines.add "autoHover = " & toTomlBool(cfg.diagnostics.autoHover)
  lines.add "autoHoverDelay = " & $cfg.diagnostics.autoHoverDelay
  lines.add ""

  lines.add "[Lsp.SignatureHelp]"
  lines.add "enable = " & toTomlBool(cfg.signatureHelp.enable)
  lines.add ""

  lines.add "[Lsp.DocumentFormatting]"
  lines.add "enable = " & toTomlBool(cfg.documentFormatting.enable)
  lines.add ""

  lines.add "[Lsp.FoldingRange]"
  lines.add "enable = " & toTomlBool(cfg.foldingRange.enable)
  lines.add ""

  lines.add "[Lsp.SelectionRange]"
  lines.add "enable = " & toTomlBool(cfg.selectionRange.enable)
  lines.add ""

  lines.add "[Lsp.DocumentSymbol]"
  lines.add "enable = " & toTomlBool(cfg.documentSymbol.enable)
  lines.add ""

  lines.add "[Lsp.Hover]"
  lines.add "enable = " & toTomlBool(cfg.hover.enable)
  lines.add ""

  lines.add "[Lsp.InlayHint]"
  lines.add "enable = " & toTomlBool(cfg.inlayHint.enable)
  lines.add ""

  lines.add "[Lsp.References]"
  lines.add "enable = " & toTomlBool(cfg.references.enable)
  lines.add ""

  lines.add "[Lsp.CallHierarchy]"
  lines.add "enable = " & toTomlBool(cfg.callHierarchy.enable)
  lines.add ""

  lines.add "[Lsp.DocumentHighlight]"
  lines.add "enable = " & toTomlBool(cfg.documentHighlight.enable)
  lines.add ""

  lines.add "[Lsp.DocumentLink]"
  lines.add "enable = " & toTomlBool(cfg.documentLink.enable)
  lines.add ""

  lines.add "[Lsp.CodeLens]"
  lines.add "enable = " & toTomlBool(cfg.codeLens.enable)
  lines.add ""

  lines.add "[Lsp.Rename]"
  lines.add "enable = " & toTomlBool(cfg.rename.enable)
  lines.add ""

  lines.add "[Lsp.SemanticTokens]"
  lines.add "enable = " & toTomlBool(cfg.semanticTokens.enable)
  lines.add ""

  lines.add "[Lsp.ExecuteCommand]"
  lines.add "enable = " & toTomlBool(cfg.executeCommand.enable)
  lines.add ""

  # Lsp language server configs (sorted for deterministic output)
  for name in toSeq(cfg.servers.keys).sorted:
    let server = cfg.servers[name]
    lines.add "[Lsp." & name & "]"
    lines.add "extensions = " & toTomlStringArray(server.extensions)
    lines.add "command = " & toTomlString(server.command)
    lines.add "trace = " & toTomlString($server.trace)
    lines.add "rustAnalyzerRunSingle = " & toTomlBool(server.rustAnalyzerRunSingle)
    lines.add "rustAnalyzerDebugSingle = " & toTomlBool(server.rustAnalyzerDebugSingle)
    lines.add ""
