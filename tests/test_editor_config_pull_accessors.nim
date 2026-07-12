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

## Tests for pull-type display/edit-flag accessors on `Editor` (Phase 1 of the
## config→runtime state push removal). Each accessor must reflect the current
## value of the corresponding `e.config` field at the moment of the call —
## flipping the config value must be visible via the accessor immediately, with
## no separate sync step.

import std/[unittest, options]

import
  ../src/moepkg/[editor, config, config_loader, buffer, editor_window, window_manager]
import ../src/moepkg/buffer/core
import ../src/moepkg/types/editor_types

proc mkEditor(): Editor =
  let cfg = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(cfg, vr)

suite "Editor - config pull accessors (Phase 1)":
  test "showTabLine reads tabLine.enable":
    let e = mkEditor()
    e.config.tabLine.enable = false
    check e.showTabLine == false
    e.config.tabLine.enable = true
    check e.showTabLine == true

  test "showStatusLine reads standard.statusLine":
    let e = mkEditor()
    e.config.standard.statusLine = false
    check e.showStatusLine == false
    e.config.standard.statusLine = true
    check e.showStatusLine == true

  test "multiStatusLine reads statusLine.multipleStatusLine":
    let e = mkEditor()
    e.config.statusLine.multipleStatusLine = false
    check e.multiStatusLine == false
    e.config.statusLine.multipleStatusLine = true
    check e.multiStatusLine == true

  test "showLineNumbers reads standard.number":
    let e = mkEditor()
    e.config.standard.number = false
    check e.showLineNumbers == false
    e.config.standard.number = true
    check e.showLineNumbers == true

  test "relativeLineNumbers reads standard.relativeNumber":
    let e = mkEditor()
    e.config.standard.relativeNumber = false
    check e.relativeLineNumbers == false
    e.config.standard.relativeNumber = true
    check e.relativeLineNumbers == true

  test "showCursorLine reads highlight.currentLine":
    let e = mkEditor()
    e.config.highlight.currentLine = false
    check e.showCursorLine == false
    e.config.highlight.currentLine = true
    check e.showCursorLine == true

  test "showCursorColumn reads highlight.currentColumn":
    let e = mkEditor()
    e.config.highlight.currentColumn = false
    check e.showCursorColumn == false
    e.config.highlight.currentColumn = true
    check e.showCursorColumn == true

  test "showSyntax reads standard.syntax":
    let e = mkEditor()
    e.config.standard.syntax = false
    check e.showSyntax == false
    e.config.standard.syntax = true
    check e.showSyntax == true

  test "showIndentationLines reads standard.indentationLines":
    let e = mkEditor()
    e.config.standard.indentationLines = false
    check e.showIndentationLines == false
    e.config.standard.indentationLines = true
    check e.showIndentationLines == true

  test "showSidebar reads standard.sidebar":
    let e = mkEditor()
    e.config.standard.sidebar = false
    check e.showSidebar == false
    e.config.standard.sidebar = true
    check e.showSidebar == true

  test "scrollbar reads standard.scrollbar":
    let e = mkEditor()
    e.config.standard.scrollbar = false
    check e.scrollbar == false
    e.config.standard.scrollbar = true
    check e.scrollbar == true

  test "scrollbarWidth reads standard.scrollbarWidth":
    let e = mkEditor()
    e.config.standard.scrollbarWidth = 1
    check e.scrollbarWidth == 1
    e.config.standard.scrollbarWidth = 3
    check e.scrollbarWidth == 3

  test "showModifiedLines reads standard.showModifiedLines":
    let e = mkEditor()
    e.config.standard.showModifiedLines = false
    check e.showModifiedLines == false
    e.config.standard.showModifiedLines = true
    check e.showModifiedLines == true

  test "showGitDiff reads git.showChangedLine":
    let e = mkEditor()
    e.config.git.showChangedLine = false
    check e.showGitDiff == false
    e.config.git.showChangedLine = true
    check e.showGitDiff == true

  test "showSyntaxChecker reads syntaxChecker.enable":
    let e = mkEditor()
    e.config.syntaxChecker.enable = false
    check e.showSyntaxChecker == false
    e.config.syntaxChecker.enable = true
    check e.showSyntaxChecker == true

  test "showCodeLens reads lsp.codeLens.enable":
    let e = mkEditor()
    e.config.lsp.codeLens.enable = false
    check e.showCodeLens == false
    e.config.lsp.codeLens.enable = true
    check e.showCodeLens == true

  test "showDocumentHighlight reads lsp.documentHighlight.enable":
    let e = mkEditor()
    e.config.lsp.documentHighlight.enable = false
    check e.showDocumentHighlight == false
    e.config.lsp.documentHighlight.enable = true
    check e.showDocumentHighlight == true

  test "showInlayHint reads lsp.inlayHint.enable":
    let e = mkEditor()
    e.config.lsp.inlayHint.enable = false
    check e.showInlayHint == false
    e.config.lsp.inlayHint.enable = true
    check e.showInlayHint == true

  test "lineWrap reads standard.lineWrap":
    let e = mkEditor()
    e.config.standard.lineWrap = false
    check e.lineWrap == false
    e.config.standard.lineWrap = true
    check e.lineWrap == true

  test "tabStop reads standard.tabStop":
    let e = mkEditor()
    e.config.standard.tabStop = 2
    check e.tabStop == 2
    e.config.standard.tabStop = 8
    check e.tabStop == 8

  test "shiftWidth reads standard.shiftWidth":
    let e = mkEditor()
    e.config.standard.shiftWidth = 0
    check e.shiftWidth == 0
    e.config.standard.shiftWidth = 4
    check e.shiftWidth == 4

  test "softTabStop reads standard.softTabStop":
    let e = mkEditor()
    e.config.standard.softTabStop = 0
    check e.softTabStop == 0
    e.config.standard.softTabStop = 4
    check e.softTabStop == 4

  test "expandTab reads standard.expandTab":
    let e = mkEditor()
    e.config.standard.expandTab = false
    check e.expandTab == false
    e.config.standard.expandTab = true
    check e.expandTab == true

  test "autoIndent reads standard.autoIndent":
    let e = mkEditor()
    e.config.standard.autoIndent = false
    check e.autoIndent == false
    e.config.standard.autoIndent = true
    check e.autoIndent == true

  test "smartIndent reads standard.smartIndent":
    let e = mkEditor()
    e.config.standard.smartIndent = false
    check e.smartIndent == false
    e.config.standard.smartIndent = true
    check e.smartIndent == true

  test "autoCloseParen reads standard.autoCloseParen":
    let e = mkEditor()
    e.config.standard.autoCloseParen = false
    check e.autoCloseParen == false
    e.config.standard.autoCloseParen = true
    check e.autoCloseParen == true

  test "autoDeleteParen reads standard.autoDeleteParen":
    let e = mkEditor()
    e.config.standard.autoDeleteParen = false
    check e.autoDeleteParen == false
    e.config.standard.autoDeleteParen = true
    check e.autoDeleteParen == true

  test "bracketSplit reads standard.bracketSplit":
    let e = mkEditor()
    e.config.standard.bracketSplit = bsmDisable
    check e.bracketSplit == bsmDisable
    e.config.standard.bracketSplit = bsmIndent
    check e.bracketSplit == bsmIndent
    e.config.standard.bracketSplit = bsmNoIndent
    check e.bracketSplit == bsmNoIndent

suite "Editor - applyConfigSettings live-reload (S1 regression)":
  test "lineWrap flip propagates via ref swap":
    let e = mkEditor()
    e.config.standard.lineWrap = true
    check e.lineWrap == true

    let newCfg = newEditorConfig()
    newCfg.standard.lineWrap = false
    e.applyConfigSettings(newCfg)
    check e.lineWrap == false
    check e.config == newCfg
    check e.state.config == newCfg

  test "showTabLine flip propagates via ref swap":
    let e = mkEditor()
    e.config.tabLine.enable = true
    check e.showTabLine == true

    let newCfg = newEditorConfig()
    newCfg.tabLine.enable = false
    e.applyConfigSettings(newCfg)
    check e.showTabLine == false

  test "state-scoped accessor also sees the swapped config":
    let e = mkEditor()
    e.config.standard.tabStop = 4
    check e.state.tabStop == 4

    let newCfg = newEditorConfig()
    newCfg.standard.tabStop = 8
    e.applyConfigSettings(newCfg)
    check e.state.tabStop == 8

  test "setter routes through config, ignoring stale mirror":
    let e = mkEditor()
    e.lineWrap = false
    check e.config.standard.lineWrap == false
    check e.lineWrap == false
    e.lineWrap = true
    check e.config.standard.lineWrap == true
    check e.lineWrap == true

suite "Editor - applyConfigSettings LSP server configs":
  test "live reload re-applies [Lsp.<lang>] command overrides":
    let e = mkEditor()
    let originalNim = e.lsp.service.getConfig("nim")
    check originalNim.isSome

    let newCfg = newEditorConfig()
    newCfg.lsp.servers["nim"] =
      LspServerConfig(command: "custom-nimlangserver --foo", extensions: @["nim"])
    e.applyConfigSettings(newCfg)

    let after = e.lsp.service.getConfig("nim")
    check after.isSome
    check after.get.command == "custom-nimlangserver --foo"
    check after.get.args.len == 0

  test "live reload registers a language not in built-in defaults":
    let e = mkEditor()
    check e.lsp.service.getConfig("mylang").isNone

    let newCfg = newEditorConfig()
    newCfg.lsp.servers["mylang"] =
      LspServerConfig(command: "mylang-lsp", extensions: @["mylang"])
    e.applyConfigSettings(newCfg)

    let after = e.lsp.service.getConfig("mylang")
    check after.isSome
    check after.get.command == "mylang-lsp"
    check after.get.enabled == true

  test "live reload disables raw JSON-RPC logging when trace flips off":
    let e = mkEditor()

    let onCfg = newEditorConfig()
    onCfg.lsp.servers["nim"] =
      LspServerConfig(command: "custom-nim", extensions: @["nim"], trace: ltVerbose)
    e.applyConfigSettings(onCfg)
    check e.lsp.service.getConfig("nim").get.rawJsonLog == true

    let offCfg = newEditorConfig()
    offCfg.lsp.servers["nim"] =
      LspServerConfig(command: "custom-nim", extensions: @["nim"], trace: ltOff)
    e.applyConfigSettings(offCfg)
    check e.lsp.service.getConfig("nim").get.rawJsonLog == false

  test "live reload reverts a removed [Lsp.<lang>] section to defaults":
    let e = mkEditor()
    let originalCommand = e.lsp.service.getConfig("nim").get.command

    let overrideCfg = newEditorConfig()
    overrideCfg.lsp.servers["nim"] =
      LspServerConfig(command: "custom-nim", extensions: @["nim"])
    e.applyConfigSettings(overrideCfg)
    check e.lsp.service.getConfig("nim").get.command == "custom-nim"

    # User removes the [Lsp.nim] section — service should revert to default.
    let emptyCfg = newEditorConfig()
    e.applyConfigSettings(emptyCfg)
    check e.lsp.service.getConfig("nim").get.command == originalCommand

  test "live reload drops a user-registered language when its section is removed":
    let e = mkEditor()
    check e.lsp.service.getConfig("mylang").isNone

    let addCfg = newEditorConfig()
    addCfg.lsp.servers["mylang"] =
      LspServerConfig(command: "mylang-lsp", extensions: @["mylang"])
    e.applyConfigSettings(addCfg)
    check e.lsp.service.getConfig("mylang").isSome

    let removeCfg = newEditorConfig()
    e.applyConfigSettings(removeCfg)
    check e.lsp.service.getConfig("mylang").isNone

suite "EditorState - per-buffer .editorconfig overrides for tabStop/shiftWidth/expandTab":
  test "tabStop reads buf.editorConfig override when set":
    let e = mkEditor()
    e.config.standard.tabStop = 2
    e.activeBuffer.editorConfig = some(BufferEditorConfig(tabStop: some(4)))
    check e.state.tabStop == 4
    check e.tabStop == 4

  test "shiftWidth reads buf.editorConfig override when set":
    let e = mkEditor()
    e.config.standard.shiftWidth = 2
    e.activeBuffer.editorConfig = some(BufferEditorConfig(shiftWidth: some(8)))
    check e.state.shiftWidth == 8
    check e.shiftWidth == 8

  test "expandTab reads buf.editorConfig override when set":
    let e = mkEditor()
    e.config.standard.expandTab = false
    e.activeBuffer.editorConfig = some(BufferEditorConfig(expandTab: some(true)))
    check e.state.expandTab == true
    check e.expandTab == true

  test "getter falls back to global config when buf.editorConfig is none":
    let e = mkEditor()
    e.config.standard.tabStop = 2
    e.config.standard.shiftWidth = 3
    e.config.standard.expandTab = false
    e.activeBuffer.editorConfig = none(BufferEditorConfig)
    check e.state.tabStop == 2
    check e.state.shiftWidth == 3
    check e.state.expandTab == false

  test "getter falls back per-field when only some overrides are set":
    let e = mkEditor()
    e.config.standard.tabStop = 2
    e.config.standard.shiftWidth = 3
    e.config.standard.expandTab = false
    # Only tabStop is overridden; shiftWidth/expandTab must fall back.
    e.activeBuffer.editorConfig = some(BufferEditorConfig(tabStop: some(8)))
    check e.state.tabStop == 8
    check e.state.shiftWidth == 3
    check e.state.expandTab == false

  test "setter writes through override so getter returns the new value":
    let e = mkEditor()
    e.config.standard.tabStop = 2
    e.config.standard.shiftWidth = 2
    e.config.standard.expandTab = false
    e.activeBuffer.editorConfig = some(
      BufferEditorConfig(tabStop: some(4), shiftWidth: some(4), expandTab: some(true))
    )
    e.state.tabStop = 8
    e.state.shiftWidth = 6
    e.state.expandTab = false
    check e.config.standard.tabStop == 8
    check e.config.standard.shiftWidth == 6
    check e.config.standard.expandTab == false
    check e.state.tabStop == 8
    check e.state.shiftWidth == 6
    check e.state.expandTab == false
    check e.activeBuffer.editorConfig.get.tabStop == some(8)
    check e.activeBuffer.editorConfig.get.shiftWidth == some(6)
    check e.activeBuffer.editorConfig.get.expandTab == some(false)

  test "state.tabStop is safe when activeWindow is nil":
    let s = EditorState(config: newEditorConfig())
    s.config.standard.tabStop = 6
    s.config.standard.shiftWidth = 3
    s.config.standard.expandTab = true
    check s.tabStop == 6
    check s.shiftWidth == 3
    check s.expandTab == true

suite "EditorState - buffer switch flips state.tabStop":
  test "activeWindow swap changes the effective tabStop/shiftWidth/expandTab":
    let e = mkEditor()
    e.config.standard.tabStop = 2
    e.config.standard.shiftWidth = 2
    e.config.standard.expandTab = false

    # Buffer A: editorconfig sets tabStop=4, expandTab=true.
    let bufA = e.activeBuffer
    bufA.editorConfig =
      some(BufferEditorConfig(tabStop: some(4), expandTab: some(true)))
    check e.state.tabStop == 4
    check e.state.expandTab == true

    # Buffer B: editorconfig sets tabStop=8 (shiftWidth override too), no expandTab override.
    let bufB = newTextBuffer()
    bufB.editorConfig = some(BufferEditorConfig(tabStop: some(8), shiftWidth: some(6)))
    e.addBuffer(bufB)
    e.windowManager.windows[0].buffer = bufB
    e.state.activeWindow = e.windowManager.windows[0]

    check e.state.tabStop == 8
    check e.state.shiftWidth == 6
    # No expandTab override on B → falls back to global.
    check e.state.expandTab == false
