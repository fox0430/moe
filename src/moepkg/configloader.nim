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

## Configuration loader for TOML files
##
## This module handles loading configuration from TOML files and converting
## them into EditorConfig structures.

import std/[os, options, tables, strutils]

import pkg/[parsetoml, results]

import config, color, theme, vscodetheme

proc parseColorMode(s: string): ColorMode =
  case s
  of "8bit": cm8bit
  of "24bit": cm24bit
  of "none": cmNone
  else: cm24bit

proc parseCursorType(s: string): CursorType =
  case s
  of "terminalDefault": ctTerminalDefault
  of "blinkBlock": ctBlinkBlock
  of "blinkIbeam": ctBlinkIbeam
  of "nonBlinkBlock": ctNonBlinkBlock
  of "nonBlinkIbeam": ctNonBlinkIbeam
  else: ctTerminalDefault

proc parseThemeKind(s: string): ThemeKind =
  case s
  of "default": tkDefault
  of "config": tkConfig
  of "vscode": tkVscode
  else: tkConfig

proc parseClipboardTool(s: string): ClipboardTool =
  case s
  of "xsel": ctXsel
  of "xclip": ctXclip
  of "wl-clipboard": ctWlClipboard
  of "win32yank": ctWin32yank
  of "pbcopy": ctPbcopy
  else: ctXsel

proc parseSplitType(s: string): SplitType =
  case s
  of "horizontal": stHorizontal
  of "vertical": stVertical
  else: stVertical

proc loadStandardConfig(table: TomlTableRef, config: var StandardConfig) =
  if table.hasKey("number"):
    config.number = table["number"].getBool()
  if table.hasKey("currentNumber"):
    config.currentNumber = table["currentNumber"].getBool()
  if table.hasKey("cursorLine"):
    config.cursorLine = table["cursorLine"].getBool()
  if table.hasKey("statusLine"):
    config.statusLine = table["statusLine"].getBool()
  if table.hasKey("tabLine"):
    config.tabLine = table["tabLine"].getBool()
  if table.hasKey("syntax"):
    config.syntax = table["syntax"].getBool()
  if table.hasKey("indentationLines"):
    config.indentationLines = table["indentationLines"].getBool()
  if table.hasKey("tabStop"):
    config.tabStop = table["tabStop"].getInt()
  if table.hasKey("expandTab"):
    config.expandTab = table["expandTab"].getBool()
  if table.hasKey("sidebar"):
    config.sidebar = table["sidebar"].getBool()
  if table.hasKey("autoCloseParen"):
    config.autoCloseParen = table["autoCloseParen"].getBool()
  if table.hasKey("autoIndent"):
    config.autoIndent = table["autoIndent"].getBool()
  if table.hasKey("ignorecase"):
    config.ignorecase = table["ignorecase"].getBool()
  if table.hasKey("smartcase"):
    config.smartcase = table["smartcase"].getBool()
  if table.hasKey("disableChangeCursor"):
    config.disableChangeCursor = table["disableChangeCursor"].getBool()
  if table.hasKey("defaultCursor"):
    config.defaultCursor = parseCursorType(table["defaultCursor"].getStr())
  if table.hasKey("normalModeCursor"):
    config.normalModeCursor = parseCursorType(table["normalModeCursor"].getStr())
  if table.hasKey("insertModeCursor"):
    config.insertModeCursor = parseCursorType(table["insertModeCursor"].getStr())
  if table.hasKey("liveReloadOfConf"):
    config.liveReloadOfConf = table["liveReloadOfConf"].getBool()
  if table.hasKey("incrementalSearch"):
    config.incrementalSearch = table["incrementalSearch"].getBool()
  if table.hasKey("popupWindowInExmode"):
    config.popupWindowInExmode = table["popupWindowInExmode"].getBool()
  if table.hasKey("autoDeleteParen"):
    config.autoDeleteParen = table["autoDeleteParen"].getBool()
  if table.hasKey("liveReloadOfFile"):
    config.liveReloadOfFile = table["liveReloadOfFile"].getBool()
  if table.hasKey("colorMode"):
    config.colorMode = parseColorMode(table["colorMode"].getStr())

proc loadClipboardConfig(table: TomlTableRef, config: var ClipboardConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()
  if table.hasKey("tool"):
    config.tool = parseClipboardTool(table["tool"].getStr())

proc loadBuildOnSaveConfig(table: TomlTableRef, config: var BuildOnSaveConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()
  if table.hasKey("workspaceRoot"):
    config.workspaceRoot = some(table["workspaceRoot"].getStr())
  if table.hasKey("command"):
    config.command = some(table["command"].getStr())

proc loadTabLineConfig(table: TomlTableRef, config: var TabLineConfig) =
  if table.hasKey("allBuffer"):
    config.allBuffer = table["allBuffer"].getBool()

proc loadStatusLineConfig(table: TomlTableRef, config: var StatusLineConfig) =
  if table.hasKey("multipleStatusLine"):
    config.multipleStatusLine = table["multipleStatusLine"].getBool()
  if table.hasKey("merge"):
    config.merge = table["merge"].getBool()
  if table.hasKey("mode"):
    config.mode = table["mode"].getBool()
  if table.hasKey("filename"):
    config.filename = table["filename"].getBool()
  if table.hasKey("chanedMark"):
    config.chanedMark = table["chanedMark"].getBool()
  if table.hasKey("directory"):
    config.directory = table["directory"].getBool()
  if table.hasKey("gitChangedLines"):
    config.gitChangedLines = table["gitChangedLines"].getBool()
  if table.hasKey("gitBranchName"):
    config.gitBranchName = table["gitBranchName"].getBool()
  if table.hasKey("showGitInactive"):
    config.showGitInactive = table["showGitInactive"].getBool()
  if table.hasKey("showModeInactive"):
    config.showModeInactive = table["showModeInactive"].getBool()
  if table.hasKey("setupText"):
    config.setupText = table["setupText"].getStr()

proc loadGitConfig(table: TomlTableRef, config: var GitConfig) =
  if table.hasKey("showChangedLine"):
    config.showChangedLine = table["showChangedLine"].getBool()
  if table.hasKey("updateInterval"):
    config.updateInterval = table["updateInterval"].getInt()

proc loadSyntaxCheckerConfig(table: TomlTableRef, config: var SyntaxCheckerConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()

proc loadThemeConfig(table: TomlTableRef, config: var ThemeConfig) =
  if table.hasKey("kind"):
    config.kind = parseThemeKind(table["kind"].getStr())
  if table.hasKey("path"):
    config.path = table["path"].getStr()

proc loadAutoSaveConfig(table: TomlTableRef, config: var AutoSaveConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()
  if table.hasKey("interval"):
    config.interval = table["interval"].getInt()

proc loadNotificationConfig(table: TomlTableRef, config: var NotificationConfig) =
  if table.hasKey("screenNotifications"):
    config.screenNotifications = table["screenNotifications"].getBool()
  if table.hasKey("logNotifications"):
    config.logNotifications = table["logNotifications"].getBool()
  if table.hasKey("autoBackupScreenNotify"):
    config.autoBackupScreenNotify = table["autoBackupScreenNotify"].getBool()
  if table.hasKey("autoBackupLogNotify"):
    config.autoBackupLogNotify = table["autoBackupLogNotify"].getBool()
  if table.hasKey("autoSaveScreenNotify"):
    config.autoSaveScreenNotify = table["autoSaveScreenNotify"].getBool()
  if table.hasKey("autoSaveLogNotify"):
    config.autoSaveLogNotify = table["autoSaveLogNotify"].getBool()
  if table.hasKey("yankScreenNotify"):
    config.yankScreenNotify = table["yankScreenNotify"].getBool()
  if table.hasKey("yankLogNotify"):
    config.yankLogNotify = table["yankLogNotify"].getBool()
  if table.hasKey("deleteScreenNotify"):
    config.deleteScreenNotify = table["deleteScreenNotify"].getBool()
  if table.hasKey("deleteLogNotify"):
    config.deleteLogNotify = table["deleteLogNotify"].getBool()
  if table.hasKey("saveScreenNotify"):
    config.saveScreenNotify = table["saveScreenNotify"].getBool()
  if table.hasKey("saveLogNotify"):
    config.saveLogNotify = table["saveLogNotify"].getBool()
  if table.hasKey("quickRunScreenNotify"):
    config.quickRunScreenNotify = table["quickRunScreenNotify"].getBool()
  if table.hasKey("quickRunLogNotify"):
    config.quickRunLogNotify = table["quickRunLogNotify"].getBool()
  if table.hasKey("buildOnSaveScreenNotify"):
    config.buildOnSaveScreenNotify = table["buildOnSaveScreenNotify"].getBool()
  if table.hasKey("buildOnSaveLogNotify"):
    config.buildOnSaveLogNotify = table["buildOnSaveLogNotify"].getBool()
  if table.hasKey("filerScreenNotify"):
    config.filerScreenNotify = table["filerScreenNotify"].getBool()
  if table.hasKey("filerLogNotify"):
    config.filerLogNotify = table["filerLogNotify"].getBool()
  if table.hasKey("restoreScreenNotify"):
    config.restoreScreenNotify = table["restoreScreenNotify"].getBool()
  if table.hasKey("restoreLogNotify"):
    config.restoreLogNotify = table["restoreLogNotify"].getBool()
  if table.hasKey("lspScreenNotify"):
    config.lspScreenNotify = table["lspScreenNotify"].getBool()
  if table.hasKey("lspLogNotify"):
    config.lspLogNotify = table["lspLogNotify"].getBool()

proc loadAutoBackupConfig(table: TomlTableRef, config: var AutoBackupConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()
  if table.hasKey("backupDir"):
    config.backupDir = some(table["backupDir"].getStr())
  if table.hasKey("idleTime"):
    config.idleTime = table["idleTime"].getInt()
  if table.hasKey("interval"):
    config.interval = table["interval"].getInt()
  if table.hasKey("dirToExclude"):
    config.dirToExclude = @[]
    for item in table["dirToExclude"].getElems():
      config.dirToExclude.add(item.getStr())

proc loadSmoothScrollConfig(table: TomlTableRef, config: var SmoothScrollConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()
  if table.hasKey("minDelay"):
    # Map minDelay (ms) to baseDurationMs
    config.baseDurationMs = table["minDelay"].getInt()
  if table.hasKey("maxDelay"):
    # Map maxDelay (ms) to maxDurationMs
    config.maxDurationMs = table["maxDelay"].getInt()

proc loadHighlightConfig(table: TomlTableRef, config: var HighlightConfig) =
  if table.hasKey("currentLine"):
    config.currentLine = table["currentLine"].getBool()
  if table.hasKey("reservedWord"):
    config.reservedWord = @[]
    for item in table["reservedWord"].getElems():
      config.reservedWord.add(item.getStr())
  if table.hasKey("replaceText"):
    config.replaceText = table["replaceText"].getBool()
  if table.hasKey("pairOfParen"):
    config.pairOfParen = table["pairOfParen"].getBool()
  if table.hasKey("fullWidthSpace"):
    config.fullWidthSpace = table["fullWidthSpace"].getBool()
  if table.hasKey("trailingSpaces"):
    config.trailingSpaces = table["trailingSpaces"].getBool()
  if table.hasKey("currentWord"):
    config.currentWord = table["currentWord"].getBool()

proc loadFilerConfig(table: TomlTableRef, config: var FilerConfig) =
  if table.hasKey("showIcons"):
    config.showIcons = table["showIcons"].getBool()

proc loadAutocompleteConfig(table: TomlTableRef, config: var AutocompleteConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()
  if table.hasKey("windowBorder"):
    config.windowBorder = table["windowBorder"].getBool()

proc loadPersistConfig(table: TomlTableRef, config: var PersistConfig) =
  if table.hasKey("exCommand"):
    config.exCommand = table["exCommand"].getBool()
  if table.hasKey("exCommandHistoryLimit"):
    config.exCommandHistoryLimit = table["exCommandHistoryLimit"].getInt()
  if table.hasKey("search"):
    config.search = table["search"].getBool()
  if table.hasKey("searchHistoryLimit"):
    config.searchHistoryLimit = table["searchHistoryLimit"].getInt()
  if table.hasKey("cursorPosition"):
    config.cursorPosition = table["cursorPosition"].getBool()

proc loadQuickRunConfig(table: TomlTableRef, config: var QuickRunConfig) =
  if table.hasKey("saveBufferWhenQuickRun"):
    config.saveBufferWhenQuickRun = table["saveBufferWhenQuickRun"].getBool()
  if table.hasKey("command"):
    config.command = some(table["command"].getStr())
  if table.hasKey("timeout"):
    config.timeout = table["timeout"].getInt()
  if table.hasKey("nimAdvancedCommand"):
    config.nimAdvancedCommand = some(table["nimAdvancedCommand"].getStr())
  if table.hasKey("ClangOptions"):
    config.clangOptions = some(table["ClangOptions"].getStr())
  if table.hasKey("CppOptions"):
    config.cppOptions = some(table["CppOptions"].getStr())
  if table.hasKey("NimOptions"):
    config.nimOptions = some(table["NimOptions"].getStr())
  if table.hasKey("shOptions"):
    config.shOptions = some(table["shOptions"].getStr())
  if table.hasKey("bashOptions"):
    config.bashOptions = some(table["bashOptions"].getStr())

proc loadStartUpFileOpenConfig(table: TomlTableRef, config: var StartUpFileOpenConfig) =
  if table.hasKey("autoSplit"):
    config.autoSplit = table["autoSplit"].getBool()
  if table.hasKey("splitType"):
    config.splitType = parseSplitType(table["splitType"].getStr())

proc loadDebugWindowNodeConfig(table: TomlTableRef, config: var DebugWindowNodeConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()
  if table.hasKey("currentWindow"):
    config.currentWindow = table["currentWindow"].getBool()
  if table.hasKey("index"):
    config.index = table["index"].getBool()
  if table.hasKey("windowIndex"):
    config.windowIndex = table["windowIndex"].getBool()
  if table.hasKey("bufferIndex"):
    config.bufferIndex = table["bufferIndex"].getBool()
  if table.hasKey("parentIndex"):
    config.parentIndex = table["parentIndex"].getBool()
  if table.hasKey("childLen"):
    config.childLen = table["childLen"].getBool()
  if table.hasKey("splitType"):
    config.splitType = table["splitType"].getBool()
  if table.hasKey("haveCursesWin"):
    config.haveCursesWin = table["haveCursesWin"].getBool()
  if table.hasKey("y"):
    config.y = table["y"].getBool()
  if table.hasKey("x"):
    config.x = table["x"].getBool()
  if table.hasKey("h"):
    config.h = table["h"].getBool()
  if table.hasKey("w"):
    config.w = table["w"].getBool()
  if table.hasKey("currentLine"):
    config.currentLine = table["currentLine"].getBool()
  if table.hasKey("currentColumn"):
    config.currentColumn = table["currentColumn"].getBool()
  if table.hasKey("expandedColumn"):
    config.expandedColumn = table["expandedColumn"].getBool()
  if table.hasKey("cursor"):
    config.cursor = table["cursor"].getBool()

proc loadDebugEditorViewConfig(table: TomlTableRef, config: var DebugEditorViewConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()
  if table.hasKey("widthOfLineNum"):
    config.widthOfLineNum = table["widthOfLineNum"].getBool()
  if table.hasKey("height"):
    config.height = table["height"].getBool()
  if table.hasKey("width"):
    config.width = table["width"].getBool()
  if table.hasKey("originalLine"):
    config.originalLine = table["originalLine"].getBool()
  if table.hasKey("start"):
    config.start = table["start"].getBool()
  if table.hasKey("length"):
    config.length = table["length"].getBool()

proc loadDebugBufferStatusConfig(
    table: TomlTableRef, config: var DebugBufferStatusConfig
) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()
  if table.hasKey("bufferIndex"):
    config.bufferIndex = table["bufferIndex"].getBool()
  if table.hasKey("path"):
    config.path = table["path"].getBool()
  if table.hasKey("openDir"):
    config.openDir = table["openDir"].getBool()
  if table.hasKey("currentMode"):
    config.currentMode = table["currentMode"].getBool()
  if table.hasKey("prevMode"):
    config.prevMode = table["prevMode"].getBool()
  if table.hasKey("language"):
    config.language = table["language"].getBool()
  if table.hasKey("encoding"):
    config.encoding = table["encoding"].getBool()
  if table.hasKey("countChange"):
    config.countChange = table["countChange"].getBool()
  if table.hasKey("cmdLoop"):
    config.cmdLoop = table["cmdLoop"].getBool()
  if table.hasKey("lastSaveTime"):
    config.lastSaveTime = table["lastSaveTime"].getBool()
  if table.hasKey("bufferLen"):
    config.bufferLen = table["bufferLen"].getBool()

proc loadDebugSearchConfig(table: TomlTableRef, config: var DebugSearchConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()

proc loadDebugMacroConfig(table: TomlTableRef, config: var DebugMacroConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()

proc loadDebugVisualConfig(table: TomlTableRef, config: var DebugVisualConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()

proc loadDebugJumpListConfig(table: TomlTableRef, config: var DebugJumpListConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()

proc loadDebugLspConfig(table: TomlTableRef, config: var DebugLspConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()

proc loadDebugConfig(table: TomlTableRef, config: var DebugConfig) =
  if table.hasKey("WindowNode"):
    loadDebugWindowNodeConfig(table["WindowNode"].getTable(), config.windowNode)
  if table.hasKey("EditorView"):
    loadDebugEditorViewConfig(table["EditorView"].getTable(), config.editorView)
  if table.hasKey("BufferStatus"):
    loadDebugBufferStatusConfig(table["BufferStatus"].getTable(), config.bufferStatus)
  if table.hasKey("Search"):
    loadDebugSearchConfig(table["Search"].getTable(), config.search)
  if table.hasKey("MacroState"):
    loadDebugMacroConfig(table["MacroState"].getTable(), config.macroState)
  if table.hasKey("Visual"):
    loadDebugVisualConfig(table["Visual"].getTable(), config.visual)
  if table.hasKey("JumpList"):
    loadDebugJumpListConfig(table["JumpList"].getTable(), config.jumpList)
  if table.hasKey("Lsp"):
    loadDebugLspConfig(table["Lsp"].getTable(), config.lsp)

proc parseLspTraceLevel(s: string): LspTraceLevel =
  case s
  of "off": ltOff
  of "messages": ltMessages
  of "verbose": ltVerbose
  else: ltOff

proc loadLspFeatureConfig(table: TomlTableRef, config: var LspFeatureConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()

proc loadLspOpenWindowConfig(table: TomlTableRef, config: var LspOpenWindowConfig) =
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()
  if table.hasKey("openWindow"):
    config.openWindow = table["openWindow"].getBool()

proc loadLspServerConfig(table: TomlTableRef): LspServerConfig =
  result = LspServerConfig(
    extensions: @[],
    command: "",
    trace: ltOff,
    rustAnalyzerRunSingle: false,
    rustAnalyzerDebugSingle: false,
  )
  if table.hasKey("extensions"):
    for item in table["extensions"].getElems():
      result.extensions.add(item.getStr())
  if table.hasKey("command"):
    result.command = table["command"].getStr()
  if table.hasKey("trace"):
    result.trace = parseLspTraceLevel(table["trace"].getStr())
  if table.hasKey("rustAnalyzerRunSingle"):
    result.rustAnalyzerRunSingle = table["rustAnalyzerRunSingle"].getBool()
  if table.hasKey("rustAnalyzerDebugSingle"):
    result.rustAnalyzerDebugSingle = table["rustAnalyzerDebugSingle"].getBool()

proc loadLspConfig(table: TomlTableRef, config: var LspConfig) =
  # Main LSP settings
  if table.hasKey("enable"):
    config.enable = table["enable"].getBool()
  if table.hasKey("timeout"):
    config.timeout = table["timeout"].getInt()

  # Feature configs
  if table.hasKey("Completion"):
    loadLspFeatureConfig(table["Completion"].getTable(), config.completion)
  if table.hasKey("Declaration"):
    loadLspOpenWindowConfig(table["Declaration"].getTable(), config.declaration)
  if table.hasKey("Definition"):
    loadLspOpenWindowConfig(table["Definition"].getTable(), config.definition)
  if table.hasKey("TypeDefinition"):
    loadLspOpenWindowConfig(table["TypeDefinition"].getTable(), config.typeDefinition)
  if table.hasKey("Implementation"):
    loadLspOpenWindowConfig(table["Implementation"].getTable(), config.implementation)
  if table.hasKey("Diagnostics"):
    loadLspFeatureConfig(table["Diagnostics"].getTable(), config.diagnostics)
  if table.hasKey("SignatureHelp"):
    loadLspFeatureConfig(table["SignatureHelp"].getTable(), config.signatureHelp)
  if table.hasKey("DocumentFormatting"):
    loadLspFeatureConfig(
      table["DocumentFormatting"].getTable(), config.documentFormatting
    )
  if table.hasKey("FoldingRange"):
    loadLspFeatureConfig(table["FoldingRange"].getTable(), config.foldingRange)
  if table.hasKey("SelectionRange"):
    loadLspFeatureConfig(table["SelectionRange"].getTable(), config.selectionRange)
  if table.hasKey("DocumentSymbol"):
    loadLspFeatureConfig(table["DocumentSymbol"].getTable(), config.documentSymbol)
  if table.hasKey("Hover"):
    loadLspFeatureConfig(table["Hover"].getTable(), config.hover)
  if table.hasKey("InlayHint"):
    loadLspFeatureConfig(table["InlayHint"].getTable(), config.inlayHint)
  if table.hasKey("InlineValue"):
    loadLspFeatureConfig(table["InlineValue"].getTable(), config.inlineValue)
  if table.hasKey("References"):
    loadLspFeatureConfig(table["References"].getTable(), config.references)
  if table.hasKey("CallHierarchy"):
    loadLspFeatureConfig(table["CallHierarchy"].getTable(), config.callHierarchy)
  if table.hasKey("DocumentHighlight"):
    loadLspFeatureConfig(
      table["DocumentHighlight"].getTable(), config.documentHighlight
    )
  if table.hasKey("DocumentLink"):
    loadLspFeatureConfig(table["DocumentLink"].getTable(), config.documentLink)
  if table.hasKey("CodeLens"):
    loadLspFeatureConfig(table["CodeLens"].getTable(), config.codeLens)
  if table.hasKey("Rename"):
    loadLspFeatureConfig(table["Rename"].getTable(), config.rename)
  if table.hasKey("SemanticTokens"):
    loadLspFeatureConfig(table["SemanticTokens"].getTable(), config.semanticTokens)
  if table.hasKey("ExecuteCommand"):
    loadLspFeatureConfig(table["ExecuteCommand"].getTable(), config.executeCommand)

  # Language server configs (any key that's not a known feature is a language server)
  let knownKeys = [
    "enable", "timeout", "Completion", "Declaration", "Definition", "TypeDefinition",
    "Implementation", "Diagnostics", "SignatureHelp", "DocumentFormatting",
    "FoldingRange", "SelectionRange", "DocumentSymbol", "Hover", "InlayHint",
    "InlineValue", "References", "CallHierarchy", "DocumentHighlight", "DocumentLink",
    "CodeLens", "Rename", "SemanticTokens", "ExecuteCommand",
  ]
  for key, value in table:
    if key notin knownKeys and value.kind == TomlValueKind.Table:
      config.servers[key] = loadLspServerConfig(value.getTable())

proc loadConfigFromToml*(path: string): EditorConfig =
  ## Load configuration from a TOML file
  ## Returns a new EditorConfig with values loaded from the file
  ## Falls back to defaults for any missing values

  if not fileExists(path):
    return newEditorConfig()

  let toml = parseFile(path)
  result = newEditorConfig()

  # Load each section
  if toml.hasKey("Standard"):
    loadStandardConfig(toml["Standard"].getTable(), result.standard)

  if toml.hasKey("Clipboard"):
    loadClipboardConfig(toml["Clipboard"].getTable(), result.clipboard)

  if toml.hasKey("BuildOnSave"):
    loadBuildOnSaveConfig(toml["BuildOnSave"].getTable(), result.buildOnSave)

  if toml.hasKey("TabLine"):
    loadTabLineConfig(toml["TabLine"].getTable(), result.tabLine)

  if toml.hasKey("StatusLine"):
    loadStatusLineConfig(toml["StatusLine"].getTable(), result.statusLine)

  if toml.hasKey("Git"):
    loadGitConfig(toml["Git"].getTable(), result.git)

  if toml.hasKey("SyntaxChecker"):
    loadSyntaxCheckerConfig(toml["SyntaxChecker"].getTable(), result.syntaxChecker)

  if toml.hasKey("Theme"):
    loadThemeConfig(toml["Theme"].getTable(), result.theme)

  if toml.hasKey("AutoSave"):
    loadAutoSaveConfig(toml["AutoSave"].getTable(), result.autoSave)

  if toml.hasKey("Notification"):
    loadNotificationConfig(toml["Notification"].getTable(), result.notification)

  if toml.hasKey("QuickRun"):
    loadQuickRunConfig(toml["QuickRun"].getTable(), result.quickRun)

  if toml.hasKey("AutoBackup"):
    loadAutoBackupConfig(toml["AutoBackup"].getTable(), result.autoBackup)

  if toml.hasKey("SmoothScroll"):
    loadSmoothScrollConfig(toml["SmoothScroll"].getTable(), result.smoothScroll)

  if toml.hasKey("Highlight"):
    loadHighlightConfig(toml["Highlight"].getTable(), result.highlight)

  if toml.hasKey("Filer"):
    loadFilerConfig(toml["Filer"].getTable(), result.filer)

  if toml.hasKey("Autocomplete"):
    loadAutocompleteConfig(toml["Autocomplete"].getTable(), result.autocomplete)

  if toml.hasKey("Persist"):
    loadPersistConfig(toml["Persist"].getTable(), result.persist)

  if toml.hasKey("StartUp.FileOpen"):
    loadStartUpFileOpenConfig(
      toml["StartUp.FileOpen"].getTable(), result.startUpFileOpen
    )

  if toml.hasKey("Lsp"):
    loadLspConfig(toml["Lsp"].getTable(), result.lsp)

  if toml.hasKey("Debug"):
    loadDebugConfig(toml["Debug"].getTable(), result.debug)

proc getConfigPath*(): string =
  ## Get the path to the configuration file
  ## Searches in standard locations:
  ## 1. $XDG_CONFIG_HOME/moe/moerc.toml
  ## 2. ~/.config/moe/moerc.toml

  let configPaths = [
    getConfigDir() / "moe" / "moerc.toml",
    getHomeDir() / ".config" / "moe" / "moerc.toml",
  ]

  for path in configPaths:
    if fileExists(path):
      return path

  # Return the default location even if it doesn't exist
  return getConfigDir() / "moe" / "moerc.toml"

proc loadConfig*(): EditorConfig =
  ## Load configuration from the default location
  let configPath = getConfigPath()
  return loadConfigFromToml(configPath)

# Theme loading functions

proc toEditorColorPairIndex(key: string): Option[EditorColorPairIndex] =
  ## Convert a TOML key to EditorColorPairIndex
  ## Keys ending with "Bg" are treated as background colors
  ## Returns none if the key doesn't match any color index

  # Remove "Bg" suffix if present for lookup
  let lookupKey =
    if key.endsWith("Bg"):
      key[0 ..< key.len - 2]
    else:
      key

  case lookupKey
  of "foreground", "default":
    return some(EditorColorPairIndex.default)
  of "lineNum":
    return some(EditorColorPairIndex.lineNum)
  of "currentLineNum":
    return some(EditorColorPairIndex.currentLineNum)
  of "statusLineNormalMode":
    return some(EditorColorPairIndex.statusLineNormalMode)
  of "statusLineNormalModeLabel":
    return some(EditorColorPairIndex.statusLineNormalModeLabel)
  of "statusLineNormalModeInactive":
    return some(EditorColorPairIndex.statusLineNormalModeInactive)
  of "statusLineInsertMode":
    return some(EditorColorPairIndex.statusLineInsertMode)
  of "statusLineInsertModeLabel":
    return some(EditorColorPairIndex.statusLineInsertModeLabel)
  of "statusLineInsertModeInactive":
    return some(EditorColorPairIndex.statusLineInsertModeInactive)
  of "statusLineVisualMode":
    return some(EditorColorPairIndex.statusLineVisualMode)
  of "statusLineVisualModeLabel":
    return some(EditorColorPairIndex.statusLineVisualModeLabel)
  of "statusLineVisualModeInactive":
    return some(EditorColorPairIndex.statusLineVisualModeInactive)
  of "statusLineReplaceMode":
    return some(EditorColorPairIndex.statusLineReplaceMode)
  of "statusLineReplaceModeLabel":
    return some(EditorColorPairIndex.statusLineReplaceModeLabel)
  of "statusLineReplaceModeInactive":
    return some(EditorColorPairIndex.statusLineReplaceModeInactive)
  of "statusLineFilerMode":
    return some(EditorColorPairIndex.statusLineFilerMode)
  of "statusLineFilerModeLabel":
    return some(EditorColorPairIndex.statusLineFilerModeLabel)
  of "statusLineFilerModeInactive":
    return some(EditorColorPairIndex.statusLineFilerModeInactive)
  of "statusLineExMode":
    return some(EditorColorPairIndex.statusLineExMode)
  of "statusLineExModeLabel":
    return some(EditorColorPairIndex.statusLineExModeLabel)
  of "statusLineExModeInactive":
    return some(EditorColorPairIndex.statusLineExModeInactive)
  of "statusLineGitChangedLines":
    return some(EditorColorPairIndex.statusLineGitChangedLines)
  of "statusLineGitBranch":
    return some(EditorColorPairIndex.statusLineGitBranch)
  of "tab":
    return some(EditorColorPairIndex.tab)
  of "currentTab":
    return some(EditorColorPairIndex.currentTab)
  of "commandLine":
    return some(EditorColorPairIndex.commandLine)
  of "errorMessage":
    return some(EditorColorPairIndex.errorMessage)
  of "warnMessage":
    return some(EditorColorPairIndex.warnMessage)
  of "searchResult":
    return some(EditorColorPairIndex.searchResult)
  of "selectArea":
    return some(EditorColorPairIndex.selectArea)
  of "keyword":
    return some(EditorColorPairIndex.keyword)
  of "functionName":
    return some(EditorColorPairIndex.functionName)
  of "typeName":
    return some(EditorColorPairIndex.typeName)
  of "boolean":
    return some(EditorColorPairIndex.boolean)
  of "specialVar":
    return some(EditorColorPairIndex.specialVar)
  of "builtin":
    return some(EditorColorPairIndex.builtin)
  of "charLit":
    return some(EditorColorPairIndex.charLit)
  of "stringLit":
    return some(EditorColorPairIndex.stringLit)
  of "binNumber":
    return some(EditorColorPairIndex.binNumber)
  of "decNumber":
    return some(EditorColorPairIndex.decNumber)
  of "floatNumber":
    return some(EditorColorPairIndex.floatNumber)
  of "hexNumber":
    return some(EditorColorPairIndex.hexNumber)
  of "octNumber":
    return some(EditorColorPairIndex.octNumber)
  of "comment":
    return some(EditorColorPairIndex.comment)
  of "longComment":
    return some(EditorColorPairIndex.longComment)
  of "whitespace":
    return some(EditorColorPairIndex.whitespace)
  of "preprocessor":
    return some(EditorColorPairIndex.preprocessor)
  of "pragma":
    return some(EditorColorPairIndex.pragma)
  of "identifier":
    return some(EditorColorPairIndex.identifier)
  of "table":
    return some(EditorColorPairIndex.table)
  of "date":
    return some(EditorColorPairIndex.date)
  of "operator":
    return some(EditorColorPairIndex.operator)
  of "property":
    return some(EditorColorPairIndex.property)
  of "namespace":
    return some(EditorColorPairIndex.namespace)
  of "className":
    return some(EditorColorPairIndex.className)
  of "enumName":
    return some(EditorColorPairIndex.enumName)
  of "enumMember":
    return some(EditorColorPairIndex.enumMember)
  of "interfaceName":
    return some(EditorColorPairIndex.interfaceName)
  of "typeParameter":
    return some(EditorColorPairIndex.typeParameter)
  of "parameter":
    return some(EditorColorPairIndex.parameter)
  of "variable":
    return some(EditorColorPairIndex.variable)
  of "string":
    return some(EditorColorPairIndex.lspString)
  of "event":
    return some(EditorColorPairIndex.event)
  of "function":
    return some(EditorColorPairIndex.function)
  of "method":
    return some(EditorColorPairIndex.`method`)
  of "macro":
    return some(EditorColorPairIndex.`macro`)
  of "regexp":
    return some(EditorColorPairIndex.regexp)
  of "decorator":
    return some(EditorColorPairIndex.decorator)
  of "angle":
    return some(EditorColorPairIndex.angle)
  of "arithmetic":
    return some(EditorColorPairIndex.arithmetic)
  of "attribute":
    return some(EditorColorPairIndex.attribute)
  of "attributeBracket":
    return some(EditorColorPairIndex.attributeBracket)
  of "bitwise":
    return some(EditorColorPairIndex.bitwise)
  of "brace":
    return some(EditorColorPairIndex.brace)
  of "bracket":
    return some(EditorColorPairIndex.bracket)
  of "builtinAttribute":
    return some(EditorColorPairIndex.builtinAttribute)
  of "builtinType":
    return some(EditorColorPairIndex.builtinType)
  of "colon":
    return some(EditorColorPairIndex.colon)
  of "comma":
    return some(EditorColorPairIndex.comma)
  of "comparison":
    return some(EditorColorPairIndex.comparison)
  of "constParameter":
    return some(EditorColorPairIndex.constParameter)
  of "derive":
    return some(EditorColorPairIndex.derive)
  of "deriveHelper":
    return some(EditorColorPairIndex.deriveHelper)
  of "dot":
    return some(EditorColorPairIndex.dot)
  of "escapeSequence":
    return some(EditorColorPairIndex.escapeSequence)
  of "invalidEscapeSequence":
    return some(EditorColorPairIndex.invalidEscapeSequence)
  of "formatSpecifier":
    return some(EditorColorPairIndex.formatSpecifier)
  of "generic":
    return some(EditorColorPairIndex.generic)
  of "label":
    return some(EditorColorPairIndex.label)
  of "lifetime":
    return some(EditorColorPairIndex.lifetime)
  of "logical":
    return some(EditorColorPairIndex.logical)
  of "macroBang":
    return some(EditorColorPairIndex.macroBang)
  of "parenthesis":
    return some(EditorColorPairIndex.parenthesis)
  of "punctuation":
    return some(EditorColorPairIndex.punctuation)
  of "selfKeyword":
    return some(EditorColorPairIndex.selfKeyword)
  of "selfTypeKeyword":
    return some(EditorColorPairIndex.selfTypeKeyword)
  of "semicolon":
    return some(EditorColorPairIndex.semicolon)
  of "typeAlias":
    return some(EditorColorPairIndex.typeAlias)
  of "toolModule":
    return some(EditorColorPairIndex.toolModule)
  of "union":
    return some(EditorColorPairIndex.union)
  of "unresolvedReference":
    return some(EditorColorPairIndex.unresolvedReference)
  of "inlayHint":
    return some(EditorColorPairIndex.inlayHint)
  of "inlineValue":
    return some(EditorColorPairIndex.inlineValue)
  of "codeLens":
    return some(EditorColorPairIndex.codeLens)
  of "currentFile":
    return some(EditorColorPairIndex.currentFile)
  of "file":
    return some(EditorColorPairIndex.file)
  of "dir":
    return some(EditorColorPairIndex.dir)
  of "pcLink":
    return some(EditorColorPairIndex.pcLink)
  of "popupWindow":
    return some(EditorColorPairIndex.popupWindow)
  of "popupWinCurrentLine":
    return some(EditorColorPairIndex.popupWinCurrentLine)
  of "replaceText":
    return some(EditorColorPairIndex.replaceText)
  of "parenPair":
    return some(EditorColorPairIndex.parenPair)
  of "currentWord":
    return some(EditorColorPairIndex.currentWord)
  of "highlightFullWidthSpace":
    return some(EditorColorPairIndex.highlightFullWidthSpace)
  of "highlightTrailingSpaces":
    return some(EditorColorPairIndex.highlightTrailingSpaces)
  of "reservedWord":
    return some(EditorColorPairIndex.reservedWord)
  of "syntaxCheckInfo":
    return some(EditorColorPairIndex.syntaxCheckInfo)
  of "syntaxCheckHint":
    return some(EditorColorPairIndex.syntaxCheckHint)
  of "syntaxCheckWarn":
    return some(EditorColorPairIndex.syntaxCheckWarn)
  of "syntaxCheckErr":
    return some(EditorColorPairIndex.syntaxCheckErr)
  of "gitConflict":
    return some(EditorColorPairIndex.gitConflict)
  of "backupManagerCurrentLine":
    return some(EditorColorPairIndex.backupManagerCurrentLine)
  of "diffViewerAddedLine":
    return some(EditorColorPairIndex.diffViewerAddedLine)
  of "diffViewerDeletedLine":
    return some(EditorColorPairIndex.diffViewerDeletedLine)
  of "configModeCurrentLine":
    return some(EditorColorPairIndex.configModeCurrentLine)
  of "currentLineBg":
    return some(EditorColorPairIndex.currentLineBg)
  of "foldingLine":
    return some(EditorColorPairIndex.foldingLine)
  of "sidebarGitAddedSign":
    return some(EditorColorPairIndex.sidebarGitAddedSign)
  of "sidebarGitDeletedSign":
    return some(EditorColorPairIndex.sidebarGitDeletedSign)
  of "sidebarGitChangedSign":
    return some(EditorColorPairIndex.sidebarGitChangedSign)
  of "sidebarSyntaxCheckInfoSign":
    return some(EditorColorPairIndex.sidebarSyntaxCheckInfoSign)
  of "sidebarSyntaxCheckHintSign":
    return some(EditorColorPairIndex.sidebarSyntaxCheckHintSign)
  of "sidebarSyntaxCheckWarnSign":
    return some(EditorColorPairIndex.sidebarSyntaxCheckWarnSign)
  of "sidebarSyntaxCheckErrSign":
    return some(EditorColorPairIndex.sidebarSyntaxCheckErrSign)
  else:
    return none(EditorColorPairIndex)

proc loadThemeFromToml*(path: string): Result[ThemeColors, string] =
  ## Load theme colors from a TOML file
  ## Returns ThemeColors based on DefaultColors with overrides from the file

  let expandedPath = path.expandTilde
  if not fileExists(expandedPath):
    return Result[ThemeColors, string].err("Theme file not found: " & expandedPath)

  var toml: TomlValueRef
  try:
    toml = parseFile(expandedPath)
  except CatchableError as e:
    return Result[ThemeColors, string].err("Failed to parse theme file: " & e.msg)

  # Start with default colors
  var colors = DefaultColors

  # Check for Colors section
  if not toml.hasKey("Colors"):
    return Result[ThemeColors, string].err("Theme file missing [Colors] section")

  let colorsTable = toml["Colors"].getTable()

  # Get default foreground/background for syntax colors
  var defaultFg = colors[EditorColorPairIndex.default].foreground.rgb
  var defaultBg = colors[EditorColorPairIndex.default].background.rgb

  if colorsTable.hasKey("foreground"):
    let fgResult = hexToRgb(colorsTable["foreground"].getStr())
    if fgResult.isOk:
      defaultFg = fgResult.get

  if colorsTable.hasKey("background"):
    let bgResult = hexToRgb(colorsTable["background"].getStr())
    if bgResult.isOk:
      defaultBg = bgResult.get

  # Update default color pair
  colors[EditorColorPairIndex.default] = ColorPair(
    foreground: ThemeColor(rgb: defaultFg), background: ThemeColor(rgb: defaultBg)
  )

  # Process all color entries
  for key, value in colorsTable:
    if key == "foreground" or key == "background":
      continue

    let colorStr = value.getStr()
    let rgbResult = hexToRgb(colorStr)
    if rgbResult.isErr:
      continue

    let rgb = rgbResult.get
    let isBackground = key.endsWith("Bg")
    let indexOpt = toEditorColorPairIndex(key)

    if indexOpt.isNone:
      continue

    let index = indexOpt.get

    if isBackground:
      colors[index].background = ThemeColor(rgb: rgb)
    else:
      colors[index].foreground = ThemeColor(rgb: rgb)
      # For syntax colors without explicit background, use default background
      if not colorsTable.hasKey(key & "Bg"):
        colors[index].background = ThemeColor(rgb: defaultBg)

  return Result[ThemeColors, string].ok(colors)

proc loadTheme*(config: EditorConfig): Result[ThemeColors, string] =
  ## Load theme based on config settings

  case config.theme.kind
  of tkDefault:
    return Result[ThemeColors, string].ok(DefaultColors)
  of tkConfig:
    return loadThemeFromToml(config.theme.path)
  of tkVscode:
    return loadVSCodeTheme()

proc initTheme*(config: EditorConfig) =
  ## Initialize the theme based on configuration
  ## Falls back to default theme on error

  let themeResult = loadTheme(config)
  if themeResult.isOk:
    setThemeColors(themeResult.get)
  else:
    # Log error and use default
    initDefaultTheme()

# ============================================================================
# Configuration saving
# ============================================================================

proc toTomlBool(val: bool): string =
  if val: "true" else: "false"

proc toTomlString(val: string): string =
  "\"" & val & "\""

proc saveConfigToToml*(config: EditorConfig, path: string): Result[void, string] =
  ## Save configuration to a TOML file
  ## This saves only the settings that are editable in Configuration mode
  var lines: seq[string] = @[]

  # Standard section
  lines.add "[Standard]"
  lines.add "number = " & toTomlBool(config.standard.number)
  lines.add "currentNumber = " & toTomlBool(config.standard.currentNumber)
  lines.add "cursorLine = " & toTomlBool(config.standard.cursorLine)
  lines.add "statusLine = " & toTomlBool(config.standard.statusLine)
  lines.add "tabLine = " & toTomlBool(config.standard.tabLine)
  lines.add "syntax = " & toTomlBool(config.standard.syntax)
  lines.add "indentationLines = " & toTomlBool(config.standard.indentationLines)
  lines.add "tabStop = " & $config.standard.tabStop
  lines.add "expandTab = " & toTomlBool(config.standard.expandTab)
  lines.add "sidebar = " & toTomlBool(config.standard.sidebar)
  lines.add "autoCloseParen = " & toTomlBool(config.standard.autoCloseParen)
  lines.add "autoIndent = " & toTomlBool(config.standard.autoIndent)
  lines.add "ignorecase = " & toTomlBool(config.standard.ignorecase)
  lines.add "smartcase = " & toTomlBool(config.standard.smartcase)
  lines.add "disableChangeCursor = " & toTomlBool(config.standard.disableChangeCursor)
  lines.add "defaultCursor = " & toTomlString($config.standard.defaultCursor)
  lines.add "normalModeCursor = " & toTomlString($config.standard.normalModeCursor)
  lines.add "insertModeCursor = " & toTomlString($config.standard.insertModeCursor)
  lines.add "liveReloadOfConf = " & toTomlBool(config.standard.liveReloadOfConf)
  lines.add "incrementalSearch = " & toTomlBool(config.standard.incrementalSearch)
  lines.add "popupWindowInExmode = " & toTomlBool(config.standard.popupWindowInExmode)
  lines.add "autoDeleteParen = " & toTomlBool(config.standard.autoDeleteParen)
  lines.add "liveReloadOfFile = " & toTomlBool(config.standard.liveReloadOfFile)
  lines.add "colorMode = " & toTomlString($config.standard.colorMode)
  lines.add ""

  # Clipboard section
  lines.add "[Clipboard]"
  lines.add "enable = " & toTomlBool(config.clipboard.enable)
  lines.add "tool = " & toTomlString($config.clipboard.tool)
  lines.add ""

  # TabLine section
  lines.add "[TabLine]"
  lines.add "allBuffer = " & toTomlBool(config.tabLine.allBuffer)
  lines.add ""

  # StatusLine section
  lines.add "[StatusLine]"
  lines.add "multipleStatusLine = " & toTomlBool(config.statusLine.multipleStatusLine)
  lines.add "merge = " & toTomlBool(config.statusLine.merge)
  lines.add "mode = " & toTomlBool(config.statusLine.mode)
  lines.add "filename = " & toTomlBool(config.statusLine.filename)
  lines.add "chanedMark = " & toTomlBool(config.statusLine.chanedMark)
  lines.add "directory = " & toTomlBool(config.statusLine.directory)
  lines.add "gitChangedLines = " & toTomlBool(config.statusLine.gitChangedLines)
  lines.add "gitBranchName = " & toTomlBool(config.statusLine.gitBranchName)
  lines.add "showGitInactive = " & toTomlBool(config.statusLine.showGitInactive)
  lines.add "showModeInactive = " & toTomlBool(config.statusLine.showModeInactive)
  lines.add ""

  # Highlight section
  lines.add "[Highlight]"
  lines.add "currentLine = " & toTomlBool(config.highlight.currentLine)
  lines.add "replaceText = " & toTomlBool(config.highlight.replaceText)
  lines.add "pairOfParen = " & toTomlBool(config.highlight.pairOfParen)
  lines.add "fullWidthSpace = " & toTomlBool(config.highlight.fullWidthSpace)
  lines.add "trailingSpaces = " & toTomlBool(config.highlight.trailingSpaces)
  lines.add "currentWord = " & toTomlBool(config.highlight.currentWord)
  lines.add ""

  # AutoBackup section
  lines.add "[AutoBackup]"
  lines.add "enable = " & toTomlBool(config.autoBackup.enable)
  lines.add "idleTime = " & $config.autoBackup.idleTime
  lines.add "interval = " & $config.autoBackup.interval
  lines.add ""

  # Notification section
  lines.add "[Notification]"
  lines.add "screenNotifications = " &
    toTomlBool(config.notification.screenNotifications)
  lines.add "logNotifications = " & toTomlBool(config.notification.logNotifications)
  lines.add "autoBackupScreenNotify = " &
    toTomlBool(config.notification.autoBackupScreenNotify)
  lines.add "autoBackupLogNotify = " &
    toTomlBool(config.notification.autoBackupLogNotify)
  lines.add "autoSaveScreenNotify = " &
    toTomlBool(config.notification.autoSaveScreenNotify)
  lines.add "autoSaveLogNotify = " & toTomlBool(config.notification.autoSaveLogNotify)
  lines.add "yankScreenNotify = " & toTomlBool(config.notification.yankScreenNotify)
  lines.add "yankLogNotify = " & toTomlBool(config.notification.yankLogNotify)
  lines.add "deleteScreenNotify = " & toTomlBool(config.notification.deleteScreenNotify)
  lines.add "deleteLogNotify = " & toTomlBool(config.notification.deleteLogNotify)
  lines.add "saveScreenNotify = " & toTomlBool(config.notification.saveScreenNotify)
  lines.add "saveLogNotify = " & toTomlBool(config.notification.saveLogNotify)
  lines.add ""

  # Filer section
  lines.add "[Filer]"
  lines.add "showIcons = " & toTomlBool(config.filer.showIcons)
  lines.add ""

  # Autocomplete section
  lines.add "[Autocomplete]"
  lines.add "enable = " & toTomlBool(config.autocomplete.enable)
  lines.add "windowBorder = " & toTomlBool(config.autocomplete.windowBorder)
  lines.add ""

  # AutoSave section
  lines.add "[AutoSave]"
  lines.add "enable = " & toTomlBool(config.autoSave.enable)
  lines.add "interval = " & $config.autoSave.interval
  lines.add ""

  # Git section
  lines.add "[Git]"
  lines.add "showChangedLine = " & toTomlBool(config.git.showChangedLine)
  lines.add "updateInterval = " & $config.git.updateInterval
  lines.add ""

  # SyntaxChecker section
  lines.add "[SyntaxChecker]"
  lines.add "enable = " & toTomlBool(config.syntaxChecker.enable)
  lines.add ""

  # SmoothScroll section
  lines.add "[SmoothScroll]"
  lines.add "enable = " & toTomlBool(config.smoothScroll.enable)
  lines.add "baseDurationMs = " & $config.smoothScroll.baseDurationMs
  lines.add "maxDurationMs = " & $config.smoothScroll.maxDurationMs
  lines.add ""

  # Lsp section
  lines.add "[Lsp]"
  lines.add "enable = " & toTomlBool(config.lsp.enable)
  lines.add "timeout = " & $config.lsp.timeout
  lines.add ""

  # Ensure directory exists
  let dir = parentDir(path)
  if not dirExists(dir):
    try:
      createDir(dir)
    except CatchableError as e:
      return Result[void, string].err("Failed to create directory: " & e.msg)

  # Write to file
  try:
    writeFile(path, lines.join("\n"))
    return Result[void, string].ok()
  except CatchableError as e:
    return Result[void, string].err("Failed to write config file: " & e.msg)

proc saveConfig*(config: EditorConfig): Result[void, string] =
  ## Save configuration to the default location
  let configPath = getConfigPath()
  return saveConfigToToml(config, configPath)
