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

## TOML loaders/serializers for sections whose load step is fully driven by
## `generateConfigLoader`. Each section exposes a `loadXxxConfig` (load + validate)
## and an `appendXxxToml` (re-serialize). Output formatting must stay byte-for-byte
## stable so the `saveConfigToToml round-trip completeness` test remains valid.

import std/[options, tables]

import pkg/parsetoml

import ../[config, config_macros]
import base, save_base

# Top-level TOML section names handled by this module's loaders.
const SimpleSectionNames* = [
  "Standard", "Clipboard", "BuildOnSave", "TabLine", "StatusLine", "Git",
  "SyntaxChecker", "AutoSave", "Notification", "QuickRun", "AutoBackup", "SmoothScroll",
  "Highlight", "Filer", "FileTree", "Autocomplete", "Persist", "Log", "EditorConfig",
]

# Loaders (auto-generated via generateConfigLoader)

proc loadStandardConfig*(
    table: TomlTableRef, config: var StandardConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, StandardConfig)

proc loadClipboardConfig*(
    table: TomlTableRef, config: var ClipboardConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, ClipboardConfig)

proc loadBuildOnSaveConfig*(
    table: TomlTableRef, config: var BuildOnSaveConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, BuildOnSaveConfig)

proc loadStatusLineConfig*(
    table: TomlTableRef, config: var StatusLineConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, StatusLineConfig)

proc loadGitConfig*(
    table: TomlTableRef, config: var GitConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, GitConfig)

proc loadSyntaxCheckerConfig*(
    table: TomlTableRef, config: var SyntaxCheckerConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, SyntaxCheckerConfig)

proc loadEditorConfigSettings*(
    table: TomlTableRef, config: var EditorConfigSettings, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, EditorConfigSettings)

proc loadAutoSaveConfig*(
    table: TomlTableRef, config: var AutoSaveConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, AutoSaveConfig)

proc loadNotificationConfig*(
    table: TomlTableRef, config: var NotificationConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, NotificationConfig)

proc loadAutoBackupConfig*(
    table: TomlTableRef, config: var AutoBackupConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, AutoBackupConfig)

proc loadSmoothScrollConfig*(
    table: TomlTableRef, config: var SmoothScrollConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, SmoothScrollConfig)

proc loadHighlightConfig*(
    table: TomlTableRef, config: var HighlightConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, HighlightConfig)

proc loadFilerConfig*(
    table: TomlTableRef, config: var FilerConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, FilerConfig)

proc loadFileTreeConfig*(
    table: TomlTableRef, config: var FileTreeConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, FileTreeConfig)

proc loadAutocompleteConfig*(
    table: TomlTableRef, config: var AutocompleteConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, AutocompleteConfig)

proc loadPersistConfig*(
    table: TomlTableRef, config: var PersistConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, PersistConfig)

proc loadQuickRunConfig*(
    table: TomlTableRef, config: var QuickRunConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, QuickRunConfig)

proc loadTabLineConfig*(
    table: TomlTableRef, config: var TabLineConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, TabLineConfig)

proc loadStartUpFileOpenConfig*(
    table: TomlTableRef, config: var StartUpFileOpenConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, StartUpFileOpenConfig)

proc loadStartUpFileTreeConfig*(
    table: TomlTableRef, config: var StartUpFileTreeConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, StartUpFileTreeConfig)

proc loadLogConfig*(
    table: TomlTableRef, config: var LogConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, LogConfig)

# Serializers

proc appendStandardToml*(lines: var seq[string], cfg: StandardConfig) =
  lines.add "[Standard]"
  lines.add "number = " & toTomlBool(cfg.number)
  lines.add "relativeNumber = " & toTomlBool(cfg.relativeNumber)
  lines.add "statusLine = " & toTomlBool(cfg.statusLine)
  lines.add "syntax = " & toTomlBool(cfg.syntax)
  lines.add "indentationLines = " & toTomlBool(cfg.indentationLines)
  lines.add "tabStop = " & $cfg.tabStop
  lines.add "shiftWidth = " & $cfg.shiftWidth
  lines.add "softTabStop = " & $cfg.softTabStop
  lines.add "expandTab = " & toTomlBool(cfg.expandTab)
  lines.add "sidebar = " & toTomlBool(cfg.sidebar)
  lines.add "scrollbar = " & toTomlBool(cfg.scrollbar)
  lines.add "scrollbarWidth = " & $cfg.scrollbarWidth
  lines.add "bookmarkMarker = \"" & cfg.bookmarkMarker & "\""
  lines.add "showModifiedLines = " & toTomlBool(cfg.showModifiedLines)
  lines.add "autoCloseParen = " & toTomlBool(cfg.autoCloseParen)
  lines.add "autoIndent = " & toTomlBool(cfg.autoIndent)
  lines.add "smartIndent = " & toTomlBool(cfg.smartIndent)
  lines.add "ignorecase = " & toTomlBool(cfg.ignorecase)
  lines.add "smartcase = " & toTomlBool(cfg.smartcase)
  lines.add "disableChangeCursor = " & toTomlBool(cfg.disableChangeCursor)
  lines.add "defaultCursor = " & toTomlString($cfg.defaultCursor)
  lines.add "normalModeCursor = " & toTomlString($cfg.normalModeCursor)
  lines.add "insertModeCursor = " & toTomlString($cfg.insertModeCursor)
  lines.add "liveReloadOfConf = " & toTomlBool(cfg.liveReloadOfConf)
  lines.add "incrementalSearch = " & toTomlBool(cfg.incrementalSearch)
  lines.add "popupWindowInExmode = " & toTomlBool(cfg.popupWindowInExmode)
  lines.add "autoDeleteParen = " & toTomlBool(cfg.autoDeleteParen)
  lines.add "liveReloadOfFile = " & toTomlBool(cfg.liveReloadOfFile)
  lines.add "colorMode = " & toTomlString($cfg.colorMode)
  lines.add "mouse = " & toTomlBool(cfg.mouse)
  lines.add "lineWrap = " & toTomlBool(cfg.lineWrap)
  lines.add "timeoutlen = " & $cfg.timeoutlen
  lines.add "bufferBackend = " & toTomlString($cfg.bufferBackend)
  lines.add "bracketSplit = " & toTomlString($cfg.bracketSplit)
  lines.add ""

proc appendClipboardToml*(lines: var seq[string], cfg: ClipboardConfig) =
  lines.add "[Clipboard]"
  lines.add "enable = " & toTomlBool(cfg.enable)
  lines.add "tool = " & toTomlString($cfg.tool)
  lines.add ""

proc appendBuildOnSaveToml*(lines: var seq[string], cfg: BuildOnSaveConfig) =
  lines.add "[BuildOnSave]"
  lines.add "enable = " & toTomlBool(cfg.enable)
  if cfg.workspaceRoot.isSome:
    lines.add "workspaceRoot = " & toTomlString(cfg.workspaceRoot.get)
  if cfg.command.isSome:
    lines.add "command = " & toTomlString(cfg.command.get)
  lines.add ""

proc appendTabLineToml*(lines: var seq[string], cfg: TabLineConfig) =
  lines.add "[TabLine]"
  lines.add "enable = " & toTomlBool(cfg.enable)
  lines.add ""

proc appendStatusLineToml*(lines: var seq[string], cfg: StatusLineConfig) =
  lines.add "[StatusLine]"
  lines.add "multipleStatusLine = " & toTomlBool(cfg.multipleStatusLine)
  lines.add "merge = " & toTomlBool(cfg.merge)
  lines.add "mode = " & toTomlBool(cfg.mode)
  lines.add "filename = " & toTomlBool(cfg.filename)
  lines.add "changedMark = " & toTomlBool(cfg.changedMark)
  lines.add "directory = " & toTomlBool(cfg.directory)
  lines.add "gitChangedLines = " & toTomlBool(cfg.gitChangedLines)
  lines.add "gitBranchName = " & toTomlBool(cfg.gitBranchName)
  lines.add "showGitInactive = " & toTomlBool(cfg.showGitInactive)
  lines.add "showModeInactive = " & toTomlBool(cfg.showModeInactive)
  lines.add "setupText = " & toTomlString(cfg.setupText)
  lines.add ""

proc appendHighlightToml*(lines: var seq[string], cfg: HighlightConfig) =
  lines.add "[Highlight]"
  lines.add "currentLine = " & toTomlBool(cfg.currentLine)
  lines.add "currentColumn = " & toTomlBool(cfg.currentColumn)
  lines.add "reservedWord = " & toTomlStringArray(cfg.reservedWord)
  lines.add "replaceText = " & toTomlBool(cfg.replaceText)
  lines.add "pairOfParen = " & toTomlBool(cfg.pairOfParen)
  lines.add "fullWidthSpace = " & toTomlBool(cfg.fullWidthSpace)
  lines.add "trailingSpaces = " & toTomlBool(cfg.trailingSpaces)
  lines.add "currentWord = " & toTomlBool(cfg.currentWord)
  lines.add "findCharHighlight = " & toTomlBool(cfg.findCharHighlight)
  lines.add "colorCodeHighlight = " & toTomlBool(cfg.colorCodeHighlight)
  lines.add "gitConflict = " & toTomlBool(cfg.gitConflict)
  lines.add "gitConflictTwoColor = " & toTomlBool(cfg.gitConflictTwoColor)
  lines.add ""

proc appendAutoBackupToml*(lines: var seq[string], cfg: AutoBackupConfig) =
  lines.add "[AutoBackup]"
  lines.add "enable = " & toTomlBool(cfg.enable)
  if cfg.backupDir.isSome:
    lines.add "backupDir = " & toTomlString(cfg.backupDir.get)
  lines.add "idleTime = " & $cfg.idleTime
  lines.add "interval = " & $cfg.interval
  if cfg.dirToExclude.len > 0:
    lines.add "dirToExclude = " & toTomlStringArray(cfg.dirToExclude)
  lines.add ""

proc appendNotificationToml*(lines: var seq[string], cfg: NotificationConfig) =
  lines.add "[Notification]"
  lines.add "screenNotifications = " & toTomlBool(cfg.screenNotifications)
  lines.add "logNotifications = " & toTomlBool(cfg.logNotifications)
  lines.add "autoBackupScreenNotify = " & toTomlBool(cfg.autoBackupScreenNotify)
  lines.add "autoBackupLogNotify = " & toTomlBool(cfg.autoBackupLogNotify)
  lines.add "autoSaveScreenNotify = " & toTomlBool(cfg.autoSaveScreenNotify)
  lines.add "autoSaveLogNotify = " & toTomlBool(cfg.autoSaveLogNotify)
  lines.add "yankScreenNotify = " & toTomlBool(cfg.yankScreenNotify)
  lines.add "yankLogNotify = " & toTomlBool(cfg.yankLogNotify)
  lines.add "deleteScreenNotify = " & toTomlBool(cfg.deleteScreenNotify)
  lines.add "deleteLogNotify = " & toTomlBool(cfg.deleteLogNotify)
  lines.add "saveScreenNotify = " & toTomlBool(cfg.saveScreenNotify)
  lines.add "saveLogNotify = " & toTomlBool(cfg.saveLogNotify)
  lines.add "quickRunScreenNotify = " & toTomlBool(cfg.quickRunScreenNotify)
  lines.add "quickRunLogNotify = " & toTomlBool(cfg.quickRunLogNotify)
  lines.add "buildOnSaveScreenNotify = " & toTomlBool(cfg.buildOnSaveScreenNotify)
  lines.add "buildOnSaveLogNotify = " & toTomlBool(cfg.buildOnSaveLogNotify)
  lines.add "filerScreenNotify = " & toTomlBool(cfg.filerScreenNotify)
  lines.add "filerLogNotify = " & toTomlBool(cfg.filerLogNotify)
  lines.add "restoreScreenNotify = " & toTomlBool(cfg.restoreScreenNotify)
  lines.add "restoreLogNotify = " & toTomlBool(cfg.restoreLogNotify)
  lines.add "lspScreenNotify = " & toTomlBool(cfg.lspScreenNotify)
  lines.add "lspLogNotify = " & toTomlBool(cfg.lspLogNotify)
  lines.add "lspForcePopup = " & toTomlBool(cfg.lspForcePopup)
  lines.add "popupNotifications = " & toTomlBool(cfg.popupNotifications)
  lines.add "popupPosition = \"" & cfg.popupPosition & "\""
  lines.add "popupTimeoutMs = " & $cfg.popupTimeoutMs
  lines.add "popupMaxVisible = " & $cfg.popupMaxVisible
  lines.add "popupMaxWidth = " & $cfg.popupMaxWidth
  lines.add "popupBorder = " & toTomlBool(cfg.popupBorder)
  lines.add ""

proc appendFilerToml*(lines: var seq[string], cfg: FilerConfig) =
  lines.add "[Filer]"
  lines.add "showIcons = " & toTomlBool(cfg.showIcons)
  lines.add ""

proc appendFileTreeToml*(lines: var seq[string], cfg: FileTreeConfig) =
  lines.add "[FileTree]"
  lines.add "width = " & $cfg.width
  lines.add ""

proc appendAutocompleteToml*(lines: var seq[string], cfg: AutocompleteConfig) =
  lines.add "[Autocomplete]"
  lines.add "enable = " & toTomlBool(cfg.enable)
  lines.add "windowBorder = " & toTomlBool(cfg.windowBorder)
  lines.add ""

proc appendAutoSaveToml*(lines: var seq[string], cfg: AutoSaveConfig) =
  lines.add "[AutoSave]"
  lines.add "enable = " & toTomlBool(cfg.enable)
  lines.add "interval = " & $cfg.interval
  lines.add ""

proc appendLogToml*(lines: var seq[string], cfg: LogConfig) =
  lines.add "[Log]"
  lines.add "clearOnStart = " & toTomlBool(cfg.clearOnStart)
  lines.add ""

proc appendPersistToml*(lines: var seq[string], cfg: PersistConfig) =
  lines.add "[Persist]"
  lines.add "commandHistory = " & toTomlBool(cfg.commandHistory)
  lines.add "commandHistoryLimit = " & $cfg.commandHistoryLimit
  lines.add "search = " & toTomlBool(cfg.search)
  lines.add "searchHistoryLimit = " & $cfg.searchHistoryLimit
  lines.add "cursorPosition = " & toTomlBool(cfg.cursorPosition)
  lines.add "bookmarks = " & toTomlBool(cfg.bookmarks)
  lines.add ""

proc appendGitToml*(lines: var seq[string], cfg: GitConfig) =
  lines.add "[Git]"
  lines.add "showChangedLine = " & toTomlBool(cfg.showChangedLine)
  lines.add "updateInterval = " & $cfg.updateInterval
  lines.add ""

proc appendSyntaxCheckerToml*(lines: var seq[string], cfg: SyntaxCheckerConfig) =
  lines.add "[SyntaxChecker]"
  lines.add "enable = " & toTomlBool(cfg.enable)
  lines.add ""

proc appendSmoothScrollToml*(lines: var seq[string], cfg: SmoothScrollConfig) =
  lines.add "[SmoothScroll]"
  lines.add "enable = " & toTomlBool(cfg.enable)
  lines.add "friction = " & $cfg.friction
  lines.add "airDrag = " & $cfg.airDrag
  lines.add ""

proc appendStartUpFileOpenToml*(lines: var seq[string], cfg: StartUpFileOpenConfig) =
  lines.add "[StartUp.FileOpen]"
  lines.add "autoSplit = " & toTomlBool(cfg.autoSplit)
  lines.add "splitType = " & toTomlString($cfg.splitType)
  lines.add ""

proc appendStartUpFileTreeToml*(lines: var seq[string], cfg: StartUpFileTreeConfig) =
  lines.add "[StartUp.FileTree]"
  lines.add "enable = " & toTomlBool(cfg.enable)
  lines.add ""

proc appendEditorConfigToml*(lines: var seq[string], cfg: EditorConfigSettings) =
  lines.add "[EditorConfig]"
  lines.add "enable = " & toTomlBool(cfg.enable)
  lines.add ""

proc appendQuickRunToml*(lines: var seq[string], cfg: QuickRunConfig) =
  lines.add "[QuickRun]"
  lines.add "saveBufferWhenQuickRun = " & toTomlBool(cfg.saveBufferWhenQuickRun)
  if cfg.command.isSome:
    lines.add "command = " & toTomlString(cfg.command.get)
  lines.add "timeout = " & $cfg.timeout
  if cfg.nimAdvancedCommand.isSome:
    lines.add "nimAdvancedCommand = " & toTomlString(cfg.nimAdvancedCommand.get)
  if cfg.clangOptions.isSome:
    lines.add "ClangOptions = " & toTomlString(cfg.clangOptions.get)
  if cfg.cppOptions.isSome:
    lines.add "CppOptions = " & toTomlString(cfg.cppOptions.get)
  if cfg.nimOptions.isSome:
    lines.add "NimOptions = " & toTomlString(cfg.nimOptions.get)
  if cfg.shOptions.isSome:
    lines.add "shOptions = " & toTomlString(cfg.shOptions.get)
  if cfg.bashOptions.isSome:
    lines.add "bashOptions = " & toTomlString(cfg.bashOptions.get)
  lines.add ""
