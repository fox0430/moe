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

## TOML loader and serializer for the [Debug.*] section group.

import std/tables

import pkg/parsetoml

import ../[config, config_macros]

import base, save_base

# Top-level TOML section name handled by this module.
const DebugSectionName* = "Debug"

# Sub-section loaders (auto-generated)

proc loadDebugWindowNodeConfig*(
    table: TomlTableRef, config: var DebugWindowNodeConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, DebugWindowNodeConfig)

proc loadDebugEditorViewConfig*(
    table: TomlTableRef, config: var DebugEditorViewConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, DebugEditorViewConfig)

proc loadDebugBufferStatusConfig*(
    table: TomlTableRef, config: var DebugBufferStatusConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, DebugBufferStatusConfig)

proc loadDebugSearchConfig*(
    table: TomlTableRef, config: var DebugSearchConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, DebugSearchConfig)

proc loadDebugMacroConfig*(
    table: TomlTableRef, config: var DebugMacroConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, DebugMacroConfig)

proc loadDebugVisualConfig*(
    table: TomlTableRef, config: var DebugVisualConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, DebugVisualConfig)

proc loadDebugJumpListConfig*(
    table: TomlTableRef, config: var DebugJumpListConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, DebugJumpListConfig)

proc loadDebugLspConfig*(
    table: TomlTableRef, config: var DebugLspConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, DebugLspConfig)

proc loadDebugConfig*(
    table: TomlTableRef, config: var DebugConfig, vr: var ValidationResult
) =
  const validKeys = [
    "WindowNode", "EditorView", "BufferStatus", "Search", "MacroState", "Visual",
    "JumpList", "Lsp",
  ]
  checkUnknownKeys(table, validKeys, "Debug", vr)
  if table.hasKey("WindowNode"):
    loadDebugWindowNodeConfig(table["WindowNode"].getTable(), config.windowNode, vr)
  if table.hasKey("EditorView"):
    loadDebugEditorViewConfig(table["EditorView"].getTable(), config.editorView, vr)
  if table.hasKey("BufferStatus"):
    loadDebugBufferStatusConfig(
      table["BufferStatus"].getTable(), config.bufferStatus, vr
    )
  if table.hasKey("Search"):
    loadDebugSearchConfig(table["Search"].getTable(), config.search, vr)
  if table.hasKey("MacroState"):
    loadDebugMacroConfig(table["MacroState"].getTable(), config.macroState, vr)
  if table.hasKey("Visual"):
    loadDebugVisualConfig(table["Visual"].getTable(), config.visual, vr)
  if table.hasKey("JumpList"):
    loadDebugJumpListConfig(table["JumpList"].getTable(), config.jumpList, vr)
  if table.hasKey("Lsp"):
    loadDebugLspConfig(table["Lsp"].getTable(), config.lsp, vr)

# Serializer

proc appendDebugToml*(lines: var seq[string], cfg: DebugConfig) =
  lines.add "[Debug.WindowNode]"
  lines.add "enable = " & toTomlBool(cfg.windowNode.enable)
  lines.add "currentWindow = " & toTomlBool(cfg.windowNode.currentWindow)
  lines.add "index = " & toTomlBool(cfg.windowNode.index)
  lines.add "windowIndex = " & toTomlBool(cfg.windowNode.windowIndex)
  lines.add "bufferIndex = " & toTomlBool(cfg.windowNode.bufferIndex)
  lines.add "parentIndex = " & toTomlBool(cfg.windowNode.parentIndex)
  lines.add "childLen = " & toTomlBool(cfg.windowNode.childLen)
  lines.add "splitType = " & toTomlBool(cfg.windowNode.splitType)
  lines.add "haveCursesWin = " & toTomlBool(cfg.windowNode.haveCursesWin)
  lines.add "y = " & toTomlBool(cfg.windowNode.y)
  lines.add "x = " & toTomlBool(cfg.windowNode.x)
  lines.add "h = " & toTomlBool(cfg.windowNode.h)
  lines.add "w = " & toTomlBool(cfg.windowNode.w)
  lines.add "currentLine = " & toTomlBool(cfg.windowNode.currentLine)
  lines.add "currentColumn = " & toTomlBool(cfg.windowNode.currentColumn)
  lines.add "expandedColumn = " & toTomlBool(cfg.windowNode.expandedColumn)
  lines.add "cursor = " & toTomlBool(cfg.windowNode.cursor)
  lines.add ""

  lines.add "[Debug.EditorView]"
  lines.add "enable = " & toTomlBool(cfg.editorView.enable)
  lines.add "widthOfLineNum = " & toTomlBool(cfg.editorView.widthOfLineNum)
  lines.add "height = " & toTomlBool(cfg.editorView.height)
  lines.add "width = " & toTomlBool(cfg.editorView.width)
  lines.add "originalLine = " & toTomlBool(cfg.editorView.originalLine)
  lines.add "start = " & toTomlBool(cfg.editorView.start)
  lines.add "length = " & toTomlBool(cfg.editorView.length)
  lines.add ""

  lines.add "[Debug.BufferStatus]"
  lines.add "enable = " & toTomlBool(cfg.bufferStatus.enable)
  lines.add "bufferIndex = " & toTomlBool(cfg.bufferStatus.bufferIndex)
  lines.add "path = " & toTomlBool(cfg.bufferStatus.path)
  lines.add "openDir = " & toTomlBool(cfg.bufferStatus.openDir)
  lines.add "currentMode = " & toTomlBool(cfg.bufferStatus.currentMode)
  lines.add "prevMode = " & toTomlBool(cfg.bufferStatus.prevMode)
  lines.add "language = " & toTomlBool(cfg.bufferStatus.language)
  lines.add "encoding = " & toTomlBool(cfg.bufferStatus.encoding)
  lines.add "countChange = " & toTomlBool(cfg.bufferStatus.countChange)
  lines.add "cmdLoop = " & toTomlBool(cfg.bufferStatus.cmdLoop)
  lines.add "lastSaveTime = " & toTomlBool(cfg.bufferStatus.lastSaveTime)
  lines.add "bufferLen = " & toTomlBool(cfg.bufferStatus.bufferLen)
  lines.add ""

  lines.add "[Debug.Search]"
  lines.add "enable = " & toTomlBool(cfg.search.enable)
  lines.add ""

  lines.add "[Debug.MacroState]"
  lines.add "enable = " & toTomlBool(cfg.macroState.enable)
  lines.add ""

  lines.add "[Debug.Visual]"
  lines.add "enable = " & toTomlBool(cfg.visual.enable)
  lines.add ""

  lines.add "[Debug.JumpList]"
  lines.add "enable = " & toTomlBool(cfg.jumpList.enable)
  lines.add ""

  lines.add "[Debug.Lsp]"
  lines.add "enable = " & toTomlBool(cfg.lsp.enable)
  lines.add ""
