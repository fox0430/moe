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

import std/[unittest, options, tables]
import ../src/moepkg/config
import ../src/moepkg/highlight

suite "Config - ColorMode enum":
  test "ColorMode string values":
    check $cm8color == "8"
    check $cm16color == "16"
    check $cm256color == "256"
    check $cm24bit == "24bit"
    check $cmNone == "none"

suite "Config - CursorType enum":
  test "CursorType string values":
    check $ctTerminalDefault == "terminalDefault"
    check $ctBlinkBlock == "blinkBlock"
    check $ctBlinkIbeam == "blinkIbeam"
    check $ctNonBlinkBlock == "nonBlinkBlock"
    check $ctNonBlinkIbeam == "nonBlinkIbeam"

suite "Config - ThemeKind enum":
  test "ThemeKind string values":
    check $tkDefault == "default"
    check $tkConfig == "config"
    check $tkVscode == "vscode"

suite "Config - ClipboardTool enum":
  test "ClipboardTool string values":
    check $cbtXsel == "xsel"
    check $cbtXclip == "xclip"
    check $cbtWlClipboard == "wl-clipboard"
    check $cbtWin32yank == "win32yank"
    check $cbtPbcopy == "pbcopy"

suite "Config - SplitType enum":
  test "SplitType string values":
    check $stHorizontal == "horizontal"
    check $stVertical == "vertical"

suite "Config - HighlightBackend enum":
  test "HighlightBackend string values":
    check $hbBuiltin == "builtin"
    check $hbMatter == "matter"

suite "Config - LspTraceLevel enum":
  test "LspTraceLevel string values":
    check $ltOff == "off"
    check $ltMessages == "messages"
    check $ltVerbose == "verbose"

suite "Config - newEditorConfig defaults":
  test "Standard config defaults":
    let config = newEditorConfig()

    check config.standard.number == true
    check config.standard.statusLine == true
    check config.standard.syntax == true
    check config.standard.indentationLines == true
    check config.standard.tabStop == 2
    check config.standard.shiftWidth == 0
    check config.standard.softTabStop == 0
    check config.standard.expandTab == false
    check config.standard.sidebar == true
    check config.standard.autoCloseParen == true
    check config.standard.autoIndent == true
    check config.standard.ignorecase == true
    check config.standard.smartcase == true
    check config.standard.disableChangeCursor == false
    check config.standard.defaultCursor == ctTerminalDefault
    check config.standard.normalModeCursor == ctBlinkBlock
    check config.standard.insertModeCursor == ctBlinkIbeam
    check config.standard.liveReloadOfConf == false
    check config.standard.incrementalSearch == true
    check config.standard.popupWindowInExmode == true
    check config.standard.autoDeleteParen == true
    check config.standard.liveReloadOfFile == true
    check config.standard.colorMode == cm256color
    check config.standard.mouse == false
    check config.standard.lineWrap == true
    check config.standard.forceInsertMode == false
    check config.standard.relativeNumber == false
    check config.standard.scrollbar == false
    check config.standard.scrollbarWidth == 1
    check config.standard.bookmarkMarker == "♥ "
    check config.standard.showModifiedLines == true
    check config.standard.smartIndent == false
    check config.standard.timeoutlen == 1000
    check config.standard.bracketSplit == bsmDisable

  test "Clipboard config defaults":
    let config = newEditorConfig()

    check config.clipboard.enable == true

  test "BuildOnSave config defaults":
    let config = newEditorConfig()

    check config.buildOnSave.enable == false
    check config.buildOnSave.workspaceRoot.isNone
    check config.buildOnSave.command.isNone

  test "TabLine config defaults":
    let config = newEditorConfig()

    check config.tabLine.enable == true

  test "StatusLine config defaults":
    let config = newEditorConfig()

    check config.statusLine.multipleStatusLine == true
    check config.statusLine.merge == false
    check config.statusLine.mode == true
    check config.statusLine.filename == true
    check config.statusLine.changedMark == true
    check config.statusLine.directory == true
    check config.statusLine.gitChangedLines == true
    check config.statusLine.gitBranchName == true
    check config.statusLine.showGitInactive == false
    check config.statusLine.showModeInactive == false
    check config.statusLine.setupText ==
      "{lineNumber}/{totalLines} {columnNumber}/{totalColumns} {encoding} {lineEnding} {fileType}"

  test "Highlight config defaults":
    let config = newEditorConfig()

    check config.highlight.backend == hbBuiltin
    check config.highlight.currentLine == true
    check config.highlight.currentColumn == false
    check config.highlight.reservedWord == @["TODO", "WIP", "NOTE"]
    check config.highlight.replaceText == true
    check config.highlight.pairOfParen == true
    check config.highlight.fullWidthSpace == true
    check config.highlight.trailingSpaces == true
    check config.highlight.currentWord == true
    check config.highlight.findCharHighlight == true
    check config.highlight.colorCodeHighlight == true
    check config.highlight.gitConflict == true
    check config.highlight.gitConflictTwoColor == true
    # Pin the config default to the buffer fail-safe. config.nim hardcodes the
    # literal 3000 because it must not import the highlight engine; this guards
    # the two from drifting (a drift would make even default-config buffers
    # nil their progressive-load cache on open — see applyHighlightCap).
    check config.highlight.maxHighlightLineLength == DefaultMaxHighlightLineLength

  test "AutoBackup config defaults":
    let config = newEditorConfig()

    check config.autoBackup.enable == false
    check config.autoBackup.backupDir.isNone
    check config.autoBackup.idleTime == 10
    check config.autoBackup.interval == 5
    check config.autoBackup.dirToExclude == @["/etc"]

  test "QuickRun config defaults":
    let config = newEditorConfig()

    check config.quickRun.saveBufferWhenQuickRun == true
    check config.quickRun.command.isNone
    check config.quickRun.timeout == 30
    check config.quickRun.nimAdvancedCommand.isNone
    check config.quickRun.clangOptions.isNone
    check config.quickRun.cppOptions.isNone
    check config.quickRun.nimOptions.isNone
    check config.quickRun.shOptions.isNone
    check config.quickRun.bashOptions.isNone

  test "Notification config defaults":
    let config = newEditorConfig()

    check config.notification.screenNotifications == true
    check config.notification.logNotifications == true
    check config.notification.autoBackupScreenNotify == true
    check config.notification.autoBackupLogNotify == true
    check config.notification.autoSaveScreenNotify == true
    check config.notification.autoSaveLogNotify == true
    check config.notification.yankScreenNotify == true
    check config.notification.yankLogNotify == true
    check config.notification.deleteScreenNotify == true
    check config.notification.deleteLogNotify == true
    check config.notification.saveScreenNotify == true
    check config.notification.saveLogNotify == true
    check config.notification.quickRunScreenNotify == true
    check config.notification.quickRunLogNotify == true
    check config.notification.buildOnSaveScreenNotify == true
    check config.notification.buildOnSaveLogNotify == true
    check config.notification.filerScreenNotify == true
    check config.notification.filerLogNotify == true
    check config.notification.restoreScreenNotify == true
    check config.notification.restoreLogNotify == true
    check config.notification.lspScreenNotify == true
    check config.notification.lspLogNotify == true
    check config.notification.lspForcePopup == true
    check config.notification.popupNotifications == false
    check config.notification.popupPosition == "bottomRight"
    check config.notification.popupTimeoutMs == 3000
    check config.notification.popupMaxVisible == 3
    check config.notification.popupMaxWidth == 60
    check config.notification.popupBorder == false

  test "Filer config defaults":
    let config = newEditorConfig()

    check config.filer.showIcons == true

  test "Autocomplete config defaults":
    let config = newEditorConfig()

    check config.autocomplete.enable == true
    check config.autocomplete.windowBorder == true

  test "AutoSave config defaults":
    let config = newEditorConfig()

    check config.autoSave.enable == true
    check config.autoSave.interval == 5

  test "Persist config defaults":
    let config = newEditorConfig()

    check config.persist.commandHistory == true
    check config.persist.commandHistoryLimit == 1000
    check config.persist.search == true
    check config.persist.searchHistoryLimit == 1000
    check config.persist.cursorPosition == true
    check config.persist.bookmarks == true

  test "Git config defaults":
    let config = newEditorConfig()

    check config.git.showChangedLine == true
    check config.git.updateInterval == 1000

  test "SyntaxChecker config defaults":
    let config = newEditorConfig()

    check config.syntaxChecker.enable == false

  test "SmoothScroll config defaults":
    let config = newEditorConfig()

    check config.smoothScroll.enable == true
    check config.smoothScroll.friction == 80.0
    check config.smoothScroll.airDrag == 2.0

  test "StartUpFileOpen config defaults":
    let config = newEditorConfig()

    check config.startUpFileOpen.autoSplit == true
    check config.startUpFileOpen.splitType == stVertical

  test "StartUpFileTree config defaults":
    let config = newEditorConfig()

    check config.startUpFileTree.enable == false

  test "Debug config defaults":
    let config = newEditorConfig()

    # WindowNode
    check config.debug.windowNode.enable == true
    check config.debug.windowNode.currentWindow == true
    check config.debug.windowNode.index == true
    check config.debug.windowNode.windowIndex == true
    check config.debug.windowNode.bufferIndex == true
    check config.debug.windowNode.parentIndex == true
    check config.debug.windowNode.childLen == true
    check config.debug.windowNode.splitType == true
    check config.debug.windowNode.haveCursesWin == true
    check config.debug.windowNode.y == true
    check config.debug.windowNode.x == true
    check config.debug.windowNode.h == true
    check config.debug.windowNode.w == true
    check config.debug.windowNode.currentLine == true
    check config.debug.windowNode.currentColumn == true
    check config.debug.windowNode.expandedColumn == true
    check config.debug.windowNode.cursor == true

    # EditorView
    check config.debug.editorView.enable == true
    check config.debug.editorView.widthOfLineNum == true
    check config.debug.editorView.height == true
    check config.debug.editorView.width == true
    check config.debug.editorView.originalLine == false
    check config.debug.editorView.start == false
    check config.debug.editorView.length == false

    # BufferStatus
    check config.debug.bufferStatus.enable == true
    check config.debug.bufferStatus.bufferIndex == true
    check config.debug.bufferStatus.path == true
    check config.debug.bufferStatus.openDir == true
    check config.debug.bufferStatus.currentMode == true
    check config.debug.bufferStatus.prevMode == true
    check config.debug.bufferStatus.language == true
    check config.debug.bufferStatus.encoding == true
    check config.debug.bufferStatus.countChange == true
    check config.debug.bufferStatus.cmdLoop == true
    check config.debug.bufferStatus.lastSaveTime == true
    check config.debug.bufferStatus.bufferLen == true

    # Other debug settings
    check config.debug.search.enable == true
    check config.debug.macroState.enable == true
    check config.debug.visual.enable == true
    check config.debug.jumpList.enable == true
    check config.debug.lsp.enable == true

  test "Theme config defaults":
    let config = newEditorConfig()

    check config.theme.kind == tkConfig
    check config.theme.path == "~/.config/moe/themes/dark.toml"

  test "LSP config defaults":
    let config = newEditorConfig()

    check config.lsp.enable == false
    check config.lsp.timeout == 30000

    # Feature configs
    check config.lsp.completion.enable == true
    check config.lsp.declaration.enable == true
    check config.lsp.declaration.openWindow == false
    check config.lsp.definition.enable == true
    check config.lsp.definition.openWindow == false
    check config.lsp.typeDefinition.enable == true
    check config.lsp.typeDefinition.openWindow == false
    check config.lsp.implementation.enable == true
    check config.lsp.implementation.openWindow == false
    check config.lsp.diagnostics.enable == true
    check config.lsp.diagnostics.autoHover == true
    check config.lsp.diagnostics.autoHoverDelay == 300
    check config.lsp.signatureHelp.enable == true
    check config.lsp.documentFormatting.enable == true
    check config.lsp.foldingRange.enable == true
    check config.lsp.selectionRange.enable == true
    check config.lsp.documentSymbol.enable == true
    check config.lsp.hover.enable == true
    check config.lsp.inlayHint.enable == true
    check config.lsp.references.enable == true
    check config.lsp.callHierarchy.enable == true
    check config.lsp.documentHighlight.enable == true
    check config.lsp.documentLink.enable == true
    check config.lsp.codeLens.enable == false
    check config.lsp.rename.enable == true
    check config.lsp.semanticTokens.enable == true
    check config.lsp.executeCommand.enable == true

    # Servers should be empty by default
    check config.lsp.servers.len == 0

  test "Top-level config defaults":
    let config = newEditorConfig()

    check config.bufferBackend.kind == bbcAuto
    check config.fileTree.width == 30
    check config.editorConfig.enable == true
    check config.log.clearOnStart == false
    check config.keyMapping.all.len == 0
    check config.keyMapping.visualAll.len == 0
    for t in config.keyMapping.perMode:
      check t.len == 0
    check config.shellCommands.len == 0
    check config.commandAliases.len == 0
    check config.disabledCommandAliases.len == 0

suite "Config - detectClipboardTool":
  test "detectClipboardTool does not raise":
    discard detectClipboardTool()

suite "Config - Multiple config instances":
  test "newEditorConfig creates independent instances":
    let config1 = newEditorConfig()
    let config2 = newEditorConfig()

    # Modify config1
    config1.standard.tabStop = 4
    config1.highlight.reservedWord.add("HACK")

    # config2 should be unchanged
    check config2.standard.tabStop == 2
    check config2.highlight.reservedWord == @["TODO", "WIP", "NOTE"]

  test "Config is a ref object":
    let config1 = newEditorConfig()
    let config2 = config1 # Reference copy

    # Modify through config1
    config1.standard.tabStop = 8

    # config2 should see the change (same reference)
    check config2.standard.tabStop == 8

suite "Config - LspServerConfig defaults":
  test "LspServerConfig default values":
    # Create LspServerConfig directly to test its defaults
    let serverConfig = LspServerConfig()

    check serverConfig.extensions.len == 0
    check serverConfig.command == ""
    check serverConfig.trace == ltOff
    check serverConfig.settings == ""
    check serverConfig.rustAnalyzerRunSingle == false
    check serverConfig.rustAnalyzerDebugSingle == false

  test "LspServerConfig can be added to servers table":
    let config = newEditorConfig()

    config.lsp.servers["nim"] = LspServerConfig(
      extensions: @[".nim", ".nims"],
      command: "nimlsp",
      trace: ltVerbose,
      rustAnalyzerRunSingle: false,
      rustAnalyzerDebugSingle: false,
    )

    check config.lsp.servers.hasKey("nim")
    check config.lsp.servers["nim"].extensions == @[".nim", ".nims"]
    check config.lsp.servers["nim"].command == "nimlsp"
    check config.lsp.servers["nim"].trace == ltVerbose

suite "Config - Enum value assignments":
  test "ColorMode all values can be assigned":
    let config = newEditorConfig()

    config.standard.colorMode = cm8color
    check config.standard.colorMode == cm8color

    config.standard.colorMode = cm16color
    check config.standard.colorMode == cm16color

    config.standard.colorMode = cm256color
    check config.standard.colorMode == cm256color

    config.standard.colorMode = cm24bit
    check config.standard.colorMode == cm24bit

    config.standard.colorMode = cmNone
    check config.standard.colorMode == cmNone

  test "CursorType all values can be assigned":
    let config = newEditorConfig()

    for cursor in CursorType:
      config.standard.defaultCursor = cursor
      check config.standard.defaultCursor == cursor

  test "ThemeKind all values can be assigned":
    let config = newEditorConfig()

    for kind in ThemeKind:
      config.theme.kind = kind
      check config.theme.kind == kind

  test "ClipboardTool all values can be assigned":
    let config = newEditorConfig()

    for tool in ClipboardTool:
      config.clipboard.tool = tool
      check config.clipboard.tool == tool

  test "SplitType all values can be assigned":
    let config = newEditorConfig()

    config.startUpFileOpen.splitType = stHorizontal
    check config.startUpFileOpen.splitType == stHorizontal

    config.startUpFileOpen.splitType = stVertical
    check config.startUpFileOpen.splitType == stVertical

  test "LspTraceLevel all values can be assigned":
    var serverConfig = LspServerConfig()

    for level in LspTraceLevel:
      serverConfig.trace = level
      check serverConfig.trace == level

suite "Config - Option field assignments":
  test "BuildOnSave Option fields":
    let config = newEditorConfig()

    # Set values
    config.buildOnSave.workspaceRoot = some("/path/to/workspace")
    config.buildOnSave.command = some("make build")

    check config.buildOnSave.workspaceRoot.isSome
    check config.buildOnSave.workspaceRoot.get == "/path/to/workspace"
    check config.buildOnSave.command.isSome
    check config.buildOnSave.command.get == "make build"

    # Clear values
    config.buildOnSave.workspaceRoot = none(string)
    config.buildOnSave.command = none(string)

    check config.buildOnSave.workspaceRoot.isNone
    check config.buildOnSave.command.isNone

  test "AutoBackup backupDir Option field":
    let config = newEditorConfig()

    config.autoBackup.backupDir = some("~/.moe/backup")
    check config.autoBackup.backupDir.isSome
    check config.autoBackup.backupDir.get == "~/.moe/backup"

  test "QuickRun Option fields":
    let config = newEditorConfig()

    config.quickRun.command = some("./run.sh")
    config.quickRun.nimAdvancedCommand = some("nim c -r")
    config.quickRun.clangOptions = some("-Wall")
    config.quickRun.cppOptions = some("-std=c++17")
    config.quickRun.nimOptions = some("--hints:off")
    config.quickRun.shOptions = some("-e")
    config.quickRun.bashOptions = some("-x")

    check config.quickRun.command.get == "./run.sh"
    check config.quickRun.nimAdvancedCommand.get == "nim c -r"
    check config.quickRun.clangOptions.get == "-Wall"
    check config.quickRun.cppOptions.get == "-std=c++17"
    check config.quickRun.nimOptions.get == "--hints:off"
    check config.quickRun.shOptions.get == "-e"
    check config.quickRun.bashOptions.get == "-x"

suite "Config - Seq field modifications":
  test "Highlight reservedWord can be modified":
    let config = newEditorConfig()

    # Add items
    config.highlight.reservedWord.add("FIXME")
    config.highlight.reservedWord.add("HACK")

    check config.highlight.reservedWord.len == 5
    check "FIXME" in config.highlight.reservedWord
    check "HACK" in config.highlight.reservedWord

    # Replace entirely
    config.highlight.reservedWord = @["BUG", "XXX"]
    check config.highlight.reservedWord == @["BUG", "XXX"]

    # Clear
    config.highlight.reservedWord = @[]
    check config.highlight.reservedWord.len == 0

  test "AutoBackup dirToExclude can be modified":
    let config = newEditorConfig()

    config.autoBackup.dirToExclude.add("/var")
    config.autoBackup.dirToExclude.add("/tmp")

    check "/etc" in config.autoBackup.dirToExclude
    check "/var" in config.autoBackup.dirToExclude
    check "/tmp" in config.autoBackup.dirToExclude

  test "LspServerConfig extensions can be modified":
    var serverConfig = LspServerConfig()

    serverConfig.extensions = @[".rs"]
    check serverConfig.extensions == @[".rs"]

    serverConfig.extensions.add(".rlib")
    check serverConfig.extensions == @[".rs", ".rlib"]

suite "Config - Numeric field boundaries":
  test "tabStop accepts various positive values":
    let config = newEditorConfig()

    config.standard.tabStop = 1
    check config.standard.tabStop == 1

    config.standard.tabStop = 8
    check config.standard.tabStop == 8

    config.standard.tabStop = 100
    check config.standard.tabStop == 100

  test "SmoothScroll float fields":
    let config = newEditorConfig()

    config.smoothScroll.friction = 0.0
    check config.smoothScroll.friction == 0.0

    config.smoothScroll.friction = 100.5
    check config.smoothScroll.friction == 100.5

    config.smoothScroll.airDrag = 0.1
    check config.smoothScroll.airDrag == 0.1

  test "LSP timeout values":
    let config = newEditorConfig()

    config.lsp.timeout = 1000
    check config.lsp.timeout == 1000

    config.lsp.timeout = 60000
    check config.lsp.timeout == 60000

  test "Persist history limits":
    let config = newEditorConfig()

    config.persist.commandHistoryLimit = 100
    check config.persist.commandHistoryLimit == 100

    config.persist.searchHistoryLimit = 500
    check config.persist.searchHistoryLimit == 500

suite "Config - Boolean field toggles":
  test "Standard config booleans can be toggled":
    let config = newEditorConfig()

    # Toggle number
    config.standard.number = not config.standard.number
    check config.standard.number == false

    # Toggle syntax
    config.standard.syntax = false
    check config.standard.syntax == false

    # Toggle mouse
    config.standard.mouse = true
    check config.standard.mouse == true

    # Toggle lineWrap
    config.standard.lineWrap = false
    check config.standard.lineWrap == false

  test "All notification booleans can be disabled":
    let config = newEditorConfig()

    config.notification.screenNotifications = false
    config.notification.logNotifications = false
    config.notification.autoBackupScreenNotify = false
    config.notification.autoBackupLogNotify = false

    check config.notification.screenNotifications == false
    check config.notification.logNotifications == false
    check config.notification.autoBackupScreenNotify == false
    check config.notification.autoBackupLogNotify == false

  test "Debug config can be completely disabled":
    let config = newEditorConfig()

    config.debug.windowNode.enable = false
    config.debug.editorView.enable = false
    config.debug.bufferStatus.enable = false
    config.debug.search.enable = false
    config.debug.macroState.enable = false
    config.debug.visual.enable = false
    config.debug.jumpList.enable = false
    config.debug.lsp.enable = false

    check config.debug.windowNode.enable == false
    check config.debug.editorView.enable == false
    check config.debug.bufferStatus.enable == false
    check config.debug.search.enable == false
    check config.debug.macroState.enable == false
    check config.debug.visual.enable == false
    check config.debug.jumpList.enable == false
    check config.debug.lsp.enable == false

suite "Config - String field assignments":
  test "StatusLine setupText can be customized":
    let config = newEditorConfig()

    config.statusLine.setupText = "{filename} - {mode}"
    check config.statusLine.setupText == "{filename} - {mode}"

    config.statusLine.setupText = ""
    check config.statusLine.setupText == ""

  test "Theme path can be changed":
    let config = newEditorConfig()

    config.theme.path = "/custom/theme.toml"
    check config.theme.path == "/custom/theme.toml"

  test "LspServerConfig command can be set":
    var serverConfig = LspServerConfig()

    serverConfig.command = "rust-analyzer"
    check serverConfig.command == "rust-analyzer"
