#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[unittest, options, importutils]

import pkg/[parsetoml, results]

import moepkg/lsp/protocol/enums
import moepkg/[unicodeext, ui, rgb, color]

import moepkg/settings {.all.}

const MoercStr = """
[Standard]
number = false
currentNumber = false
cursorLine = true
statusLine = false
tabLine = false
syntax = false
indentationLines = false
tabStop = 4
autoCloseParen = false
autoIndent = false
ignorecase = false
smartcase = false
disableChangeCursor = true
defaultCursor = "blinkIbeam"
normalModeCursor = "blinkIbeam"
insertModeCursor = "blinkBlock"
liveReloadOfConf = true
incrementalSearch = false
popupWindowInExmode = false
autoDeleteParen = false
colorMode = "none"

[Clipboard]
enable = false
tool = "xclip"

[BuildOnSave]
enable = true
workspaceRoot = "/home/fox/git/moe"
command = "cd /home/fox/git/moe && nimble build"

[TabLine]
allBuffer = true

[StatusLine]
multipleStatusLine = false
merge = true
mode = false
filename = false
chanedMark = false
directory = false
gitChangedLines = false
gitBranchName = false
showGitInactive = true
showModeInactive = true
setupText = "{lineNumber}/{totalLines}"

[Highlight]
currentLine = true
reservedWord = ["TEST", "TEST2"]
replaceText = false
pairOfParen = false
fullWidthSpace = false
trailingSpaces = false
currentWord = false

[AutoBackup]
enable = false
idleTime = 1
interval = 1
backupDir = "/tmp"
dirToExclude = ["/tmp"]

[QuickRun]
saveBufferWhenQuickRun = false
command = "nimble build"
timeout = 1
nimAdvancedCommand = "js"
clangOptions = "-Wall"
cppOptions = "-Wall"
nimOptions = "--debugger:native"
shOptions = "-c"
bashOptions = "-c"

[Notification]
screenNotifications = false
logNotifications = false
autoBackupScreenNotify = false
autoBackupLogNotify = false
autoSaveScreenNotify = false
autoSaveLogNotify = false
yankScreenNotify = false
yankLogNotify = false
deleteScreenNotify = false
deleteLogNotify = false
saveScreenNotify = false
saveLogNotify = false
quickRunScreenNotify = false
quickRunLogNotify = false
buildOnSaveScreenNotify = false
buildOnSaveLogNotify = false
filerScreenNotify = false
filerLogNotify = false
restoreScreenNotify = false
restoreLogNotify = false

[Filer]
showIcons = false

[Autocomplete]
enable = false

[AutoSave]
enable = false
interval = 1

[Persist]
exCommand = false
exCommandHistoryLimit = 1
search = false
searchHistoryLimit = 1
cursorPosition = false

[Git]
showChangedLine = false
updateInterval = 1

[SyntaxChecker]
enable = true

[SmoothScroll]
enable = false
minDelay = 1
maxDelay = 1

[StartUp.FileOpen]
autoSplit = false
splitType = "horizontal"

[Lsp]
enable = true

[Lsp.Completion]
enable = false

[Lsp.Definition]
enable = false

[Lsp.TypeDefinition]
enable = false

[Lsp.Diagnostics]
enable = false

[Lsp.Hover]
enable = false

[Lsp.InlayHint]
enable = false

[Lsp.References]
enable = false

[Lsp.Rename]
enable = false

[Lsp.SemanticTokens]
enable = false

[Lsp.nim]
extensions = ["nim"]
command = "nimlangserver"
trace = "verbose"

[Lsp.rust]
extensions = ["rs"]
command = "rust-analyzer"
trace = "verbose"

[Debug.WindowNode]
enable = false
currentWindow = false
index = false
windowIndex = false
bufferIndex = false
parentIndex = false
childLen = false
splitType = false
haveCursesWin = false
y = false
x = false
h = false
w = false
currentLine = false
currentColumn = false
expandedColumn = false
cursor = false

[Debug.BufferStatus]
enable = false
bufferIndex = false
path = false
openDir = false
currentMode = false
prevMode = false
language = false
encoding = false
countChange = false
cmdLoop = false
lastSaveTime = false
bufferLen = false

[Theme]
kind = "config"
path = "~/user/.config/moe/themes/my_theme.toml"
"""

const ColorsConfigStr = """
[Colors]

foreground = "#111111"
background = "#111111"

lineNum = "#111111"
lineNumBg = "#111111"

currentLineNum = "#111111"
currentLineNumBg = "#111111"

statusLineNormalMode = "#111111"
statusLineNormalModeBg = "#111111"
statusLineNormalModeLabel = "#111111"
statusLineNormalModeLabelBg = "#111111"
statusLineNormalModeInactive = "#111111"
statusLineNormalModeInactiveBg = "#111111"

statusLineInsertMode = "#111111"
statusLineInsertModeBg = "#111111"
statusLineInsertModeLabel = "#111111"
statusLineInsertModeLabelBg = "#111111"
statusLineInsertModeInactive = "#111111"
statusLineInsertModeInactiveBg = "#111111"

statusLineVisualMode = "#111111"
statusLineVisualModeBg = "#111111"
statusLineVisualModeLabel = "#111111"
statusLineVisualModeLabelBg = "#111111"
statusLineVisualModeInactive = "#111111"
statusLineVisualModeInactiveBg = "#111111"

statusLineReplaceMode = "#111111"
statusLineReplaceModeBg = "#111111"
statusLineReplaceModeLabel = "#111111"
statusLineReplaceModeLabelBg = "#111111"
statusLineReplaceModeInactive = "#111111"
statusLineReplaceModeInactiveBg = "#111111"

statusLineFilerMode = "#111111"
statusLineFilerModeBg = "#111111"
statusLineFilerModeLabel = "#111111"
statusLineFilerModeLabelBg = "#111111"
statusLineFilerModeInactive = "#111111"
statusLineFilerModeInactiveBg = "#111111"

statusLineExMode = "#111111"
statusLineExModeBg = "#111111"
statusLineExModeLabel = "#111111"
statusLineExModeLabelBg = "#111111"
statusLineExModeInactive = "#111111"
statusLineExModeInactiveBg = "#111111"

statusLineGitChangedLines = "#111111"
statusLineGitChangedLinesBg = "#111111"
statusLineGitBranch = "#111111"
statusLineGitBranchBg = "#111111"

tab = "#111111"
tabBg = "#111111"
currentTab = "#111111"
currentTabBg = "#111111"

commandLine = "#111111"
commandLineBg = "#111111"

errorMessage = "#111111"
errorMessageBg = "#111111"

warnMessage = "#111111"
warnMessageBg = "#111111"

searchResult = "#111111"
searchResultBg = "#111111"

selectArea = "#111111"
selectAreaBg = "#111111"

keyword = "#111111"
functionName = "#111111"
typeName = "#111111"
boolean = "#111111"
charLit = "#111111"
stringLit = "#111111"
specialVar = "#111111"
builtin = "#111111"
binNumber = "#111111"
decNumber = "#111111"
floatNumber = "#111111"
hexNumber = "#111111"
octNumber = "#111111"
comment = "#111111"
longComment = "#111111"
whitespace = "#111111"
preprocessor = "#111111"
pragma = "#111111"
identifier = "#111111"
table = "#111111"
date = "#111111"
operator = "#111111"
namespace = "#111111"
className = "#111111"
enumName = "#111111"
enumMember = "#111111"
interfaceName = "#111111"
typeParameter = "#111111"
parameter = "#111111"
variable = "#111111"
property = "#111111"
string = "#111111"
event = "#111111"
function = "#111111"
method = "#111111"
macro = "#111111"
regexp = "#111111"
decorator = "#111111"
angle = "#111111"
arithmetic = "#111111"
attribute = "#111111"
attributeBracket = "#111111"
bitwise = "#111111"
brace = "#111111"
bracket = "#111111"
builtinAttribute = "#111111"
builtinType = "#111111"
colon = "#111111"
comma = "#111111"
comparison = "#111111"
constParameter = "#111111"
derive = "#111111"
deriveHelper = "#111111"
dot = "#111111"
escapeSequence = "#111111"
invalidEscapeSequence = "#111111"
formatSpecifier = "#111111"
generic = "#111111"
label = "#111111"
lifetime = "#111111"
logical = "#111111"
macroBang = "#111111"
parenthesis = "#111111"
punctuation = "#111111"
selfKeyword = "#111111"
selfTypeKeyword = "#111111"
semicolon = "#111111"
typeAlias = "#111111"
toolModule = "#111111"
union = "#111111"
unresolvedReference = "#111111"

inlayHint = "#111111"

currentFile = "#111111"
currentFileBg = "#111111"
file = "#111111"
fileBg = "#111111"
dir = "#111111"
dirBg = "#111111"
pcLink = "#111111"
pcLinkBg = "#111111"

popupWindow = "#111111"
popupWindowBg = "#111111"
popupWinCurrentLine = "#111111"
popupWinCurrentLineBg = "#111111"

replaceText = "#111111"
replaceTextBg = "#111111"

parenPair = "#111111"
parenPairBg = "#111111"

currentWord = "#111111"
currentWordBg = "#111111"

highlightFullWidthSpace = "#111111"
highlightFullWidthSpaceBg = "#111111"

highlightTrailingSpaces = "#111111"
highlightTrailingSpacesBg = "#111111"

reservedWord = "#111111"
reservedWordBg = "#111111"

syntaxCheckInfo = "#111111"
syntaxCheckInfoBg = "#111111"
syntaxCheckHint = "#111111"
syntaxCheckHintBg = "#111111"
syntaxCheckWarn = "#111111"
syntaxCheckWarnBg = "#111111"
syntaxCheckErr = "#111111"
syntaxCheckErrBg = "#111111"

gitConflict = "#111111"
gitConflictBg = "#111111"

backupManagerCurrentLine = "#111111"
backupManagerCurrentLineBg = "#111111"

diffViewerAddedLine = "#111111"
diffViewerAddedLineBg = "#111111"
diffViewerDeletedLine = "#111111"
diffViewerDeletedLineBg = "#111111"

configModeCurrentLine = "#111111"
configModeCurrentLineBg = "#111111"

currentLineBg = "#111111"

sidebarGitAddedSign = "#111111"
sidebarGitAddedSignBg = "#111111"
sidebarGitDeletedSign = "#111111"
sidebarGitDeletedSignBg = "#111111"
sidebarGitChangedSign = "#111111"
sidebarGitChangedSignBg = "#111111"

sidebarSyntaxCheckInfoSign = "#111111"
sidebarSyntaxCheckInfoSignBg = "#111111"
sidebarSyntaxCheckHintSign = "#111111"
sidebarSyntaxCheckHintSignBg = "#111111"
sidebarSyntaxCheckWarnSign = "#111111"
sidebarSyntaxCheckWarnSignBg = "#111111"
sidebarSyntaxCheckErrSign = "#111111"
sidebarSyntaxCheckErrSignBg = "#111111"
"""

suite "settings: Parse configuration file":
  test "Parse all settings":
    var settings = initEditorSettings()
    settings.applyTomlConfigs(parsetoml.parseString(MoercStr))

    check not settings.view.lineNumber
    check not settings.view.currentLineNumber
    check settings.view.cursorLine
    check not settings.statusLine.enable
    check not settings.tabLine.enable
    check not settings.standard.syntax
    check not settings.view.indentationLines
    check settings.view.tabStop == 4
    check not settings.standard.autoCloseParen
    check not settings.standard.autoIndent
    check not settings.standard.ignorecase
    check not settings.standard.smartcase
    check settings.standard.disableChangeCursor
    check settings.standard.defaultCursor == CursorType.blinkIbeam
    check settings.standard.normalModeCursor == CursorType.blinkIbeam
    check settings.standard.insertModeCursor == CursorType.blinkBlock
    check settings.standard.liveReloadOfConf
    check not settings.standard.incrementalSearch
    check not settings.standard.popupWindowInExmode
    check not settings.standard.autoDeleteParen
    check settings.standard.colorMode == ColorMode.none

    check not settings.clipboard.enable
    check settings.clipboard.tool == ClipboardTool.xclip

    check settings.buildOnSave.enable
    check settings.buildOnSave.workspaceRoot == ru"/home/fox/git/moe"
    check settings.buildOnSave.command == ru"cd /home/fox/git/moe && nimble build"

    check settings.tabLine.allbuffer

    check not settings.statusLine.multipleStatusLine
    check settings.statusLine.merge
    check not settings.statusLine.mode
    check not settings.statusLine.filename
    check not settings.statusLine.chanedMark
    check not settings.statusLine.directory
    check not settings.statusLine.gitChangedLines
    check not settings.statusLine.gitBranchName
    check settings.statusLine.showGitInactive
    check settings.statusLine.showModeInactive
    check settings.statusLine.setupText == ru"{lineNumber}/{totalLines}"

    check settings.view.highlightCurrentLine
    check not settings.highlight.replaceText
    check not settings.highlight.pairOfParen
    check not settings.highlight.fullWidthSpace
    check not settings.highlight.trailingSpaces
    check not settings.highlight.currentWord
    check settings.highlight.reservedWords[3].word == "TEST"
    check settings.highlight.reservedWords[4].word == "TEST2"

    check not settings.autoBackup.enable
    check settings.autoBackup.idleTime == 1
    check settings.autoBackup.interval == 1
    check settings.autoBackup.backupDir == ru"/tmp"
    check settings.autoBackup.dirToExclude  == @[ru"/tmp"]

    check not settings.quickRun.saveBufferWhenQuickRun
    check settings.quickRun.command == "nimble build"
    check settings.quickRun.timeout == 1
    check settings.quickRun.nimAdvancedCommand == "js"
    check settings.quickRun.clangOptions == "-Wall"
    check settings.quickRun.cppOptions == "-Wall"
    check settings.quickRun.nimOptions == "--debugger:native"
    check settings.quickRun.shOptions == "-c"
    check settings.quickRun.bashOptions == "-c"

    check not settings.notification.screenNotifications
    check not settings.notification.logNotifications
    check not settings.notification.autoBackupScreenNotify
    check not settings.notification.autoBackupLogNotify
    check not settings.notification.autoSaveScreenNotify
    check not settings.notification.autoSaveLogNotify
    check not settings.notification.yankScreenNotify
    check not settings.notification.yankLogNotify
    check not settings.notification.deleteScreenNotify
    check not settings.notification.deleteLogNotify
    check not settings.notification.saveScreenNotify
    check not settings.notification.saveLogNotify
    check not settings.notification.quickRunScreenNotify
    check not settings.notification.quickRunLogNotify
    check not settings.notification.buildOnSaveScreenNotify
    check not settings.notification.buildOnSaveLogNotify
    check not settings.notification.filerScreenNotify
    check not settings.notification.filerLogNotify
    check not settings.notification.restoreScreenNotify
    check not settings.notification.restoreLogNotify

    check not settings.filer.showIcons

    check not settings.autocomplete.enable

    check not settings.autoSave.enable
    check settings.autoSave.interval == 1

    check not settings.persist.exCommand
    check settings.persist.exCommandHistoryLimit == 1
    check not settings.persist.search
    check settings.persist.searchHistoryLimit == 1
    check not settings.persist.cursorPosition

    check not settings.git.showChangedLine
    check settings.git.updateInterval == 1

    check settings.syntaxChecker.enable

    check not settings.smoothScroll.enable
    check settings.smoothScroll.minDelay == 1
    check settings.smoothScroll.maxDelay == 1

    check not settings.startUp.fileOpen.autoSplit
    check settings.startUp.fileOpen.splitType == WindowSplitType.horizontal

    check settings.lsp.enable

    check not settings.lsp.features.completion.enable

    check not settings.lsp.features.definition.enable

    check not settings.lsp.features.typeDefinition.enable

    check not settings.lsp.features.diagnostics.enable

    check not settings.lsp.features.hover.enable

    check not settings.lsp.features.inlayHint.enable

    check not settings.lsp.features.references.enable

    check not settings.lsp.features.rename.enable

    check not settings.lsp.features.semanticTokens.enable

    check settings.lsp.languages["nim"] == LspLanguageSettings(
      extensions: @[ru"nim"],
      command: ru"nimlangserver",
      trace: TraceValue.verbose)

    check settings.lsp.languages["rust"] == LspLanguageSettings(
      extensions: @[ru"rs"],
      command: ru"rust-analyzer",
      trace: TraceValue.verbose)

    check not settings.debugMode.windowNode.enable
    check not settings.debugMode.windowNode.currentWindow
    check not settings.debugMode.windowNode.index
    check not settings.debugMode.windowNode.windowIndex
    check not settings.debugMode.windowNode.bufferIndex
    check not settings.debugMode.windowNode.parentIndex
    check not settings.debugMode.windowNode.childLen
    check not settings.debugMode.windowNode.splitType
    check not settings.debugMode.windowNode.haveCursesWin
    check not settings.debugMode.windowNode.y
    check not settings.debugMode.windowNode.x
    check not settings.debugMode.windowNode.h
    check not settings.debugMode.windowNode.w
    check not settings.debugMode.windowNode.currentLine
    check not settings.debugMode.windowNode.currentColumn
    check not settings.debugMode.windowNode.expandedColumn
    check not settings.debugMode.windowNode.cursor

    check not settings.debugMode.bufStatus.enable
    check not settings.debugMode.bufStatus.bufferIndex
    check not settings.debugMode.bufStatus.path
    check not settings.debugMode.bufStatus.openDir
    check not settings.debugMode.bufStatus.currentMode
    check not settings.debugMode.bufStatus.prevMode
    check not settings.debugMode.bufStatus.language
    check not settings.debugMode.bufStatus.encoding
    check not settings.debugMode.bufStatus.countChange
    check not settings.debugMode.bufStatus.cmdLoop
    check not settings.debugMode.bufStatus.lastSaveTime
    check not settings.debugMode.bufStatus.bufferLen

    check not settings.git.showChangedLine
    check settings.git.updateInterval == 1

    check settings.theme.kind == ColorThemeKind.config
    check settings.theme.path == "~/user/.config/moe/themes/my_theme.toml"

  test "Parse Clipboard setting 1":
    const Str = """
      [Clipboard]
      enable = true
      tool = "xclip""""

    var settings = initEditorSettings()
    settings.applyTomlConfigs(parsetoml.parseString(Str))

    check settings.clipboard.enable
    check settings.clipboard.tool == ClipboardTool.xclip

  test "Parse Clipboard setting 2":
    const Str = """
      [Clipboard]
      enable = true
      tool = "xsel""""

    var settings = initEditorSettings()
    settings.applyTomlConfigs(parsetoml.parseString(Str))

    check settings.clipboard.enable
    check settings.clipboard.tool == ClipboardTool.xsel

  test "Parse Clipboard setting 3":
    const Str = """
      [Clipboard]
      enable = true
      tool = "wl-clipboard""""

    var settings = initEditorSettings()
    settings.applyTomlConfigs(parsetoml.parseString(Str))

    check settings.clipboard.enable
    check settings.clipboard.tool == ClipboardTool.wlClipboard

  test "Parse Clipboard setting 4":
    const Str = """
      [Clipboard]
      enable = true
      tool = "wsl-default""""

    var settings = initEditorSettings()
    settings.applyTomlConfigs(parsetoml.parseString(Str))

    check settings.clipboard.enable
    check settings.clipboard.tool == ClipboardTool.wslDefault

  test "Parse Clipboard setting 5":
    const Str = """
      [Clipboard]
      enable = true
      tool = "macOS-default""""

    var settings = initEditorSettings()
    settings.applyTomlConfigs(parsetoml.parseString(Str))

    check settings.clipboard.enable
    check settings.clipboard.tool == ClipboardTool.macOsDefault

  test "Parse color Mode setting 1":
    const Str = """
      [Standard]
      colorMode = "none"
    """

    var settings = initEditorSettings()
    settings.applyTomlConfigs(parsetoml.parseString(Str))

    check ColorMode.none == settings.standard.colorMode

  test "Parse color Mode setting 2":
    const Str = """
      [Standard]
      colorMode = "8"
    """

    var settings = initEditorSettings()
    settings.applyTomlConfigs(parsetoml.parseString(Str))

    check ColorMode.c8 == settings.standard.colorMode

  test "Parse color Mode setting 3":
    const Str = """
      [Standard]
      colorMode = "256"
    """

    var settings = initEditorSettings()
    settings.applyTomlConfigs(parsetoml.parseString(Str))

    check ColorMode.c256  == settings.standard.colorMode

  test "Parse color Mode setting 4":
    const Str = """
      [Standard]
      colorMode = "24bit"
    """

    var settings = initEditorSettings()
    settings.applyTomlConfigs(parsetoml.parseString(Str))

    check ColorMode.c24bit == settings.standard.colorMode

suite "settings: Validate editor config":
  test "Except for success":
    let toml = parsetoml.parseString(MoercStr)
    let result = toml.validateTomlConfig

    privateAccess InvalidItem
    check result == none(InvalidItem)

  test "Except to fail":
    const TomlThemeConfig ="""
      [Persist]
      a = "a"
    """

    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    check isSome(result)

suite "settings: Validate Standard.theme":
  test "Invalid value":
    const TomlThemeConfig ="""
      [Standard]
      theme = "a"
    """

    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    privateAccess InvalidItem
    check result == some(InvalidItem(name: "theme", val: "a"))

suite "settings: Validate theme table":
  test "Invalid":
    const TomlThemeConfig ="""
      [Theme]
      kind = "abc"
    """
    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    check result.isSome

  test "Theme.kind: default":
    const TomlThemeConfig ="""
      [Theme]
      kind = "default"
    """
    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    check result.isNone

  test "Theme.kind: config":
    const TomlThemeConfig ="""
      [Theme]
      kind = "config"
    """
    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    check result.isNone

  test "Theme.kind: vscode":
    const TomlThemeConfig ="""
      [Theme]
      kind = "config"
    """
    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    check result.isNone

  test "Theme.path":
    const TomlThemeConfig ="""
      [Theme]
      kind = "config"
      path = "./theme.toml"
    """
    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    check result.isNone

suite "settings: validateLspTable":
  test "Invalid":
    const Toml ="""
[Lsp]
a = "b"
"""
    check parsetoml.parseString(Toml).validateTomlConfig.isSome

  test "Invalid 2":
    const Toml ="""
[Lsp]
enable = "true"
"""
    check parsetoml.parseString(Toml).validateTomlConfig.isSome

  test "Invalid 3":
    const Toml ="""
[Lsp]
enable = true
a = "b"
"""
    check parsetoml.parseString(Toml).validateTomlConfig.isSome

  test "Invalid 4":
    const Toml ="""
[Lsp]
enable = true
[Lsp.nim]
a = "b"
"""
    check parsetoml.parseString(Toml).validateTomlConfig.isSome

  test "Invalid 5":
    const Toml ="""
[Lsp]
enable = true
[Lsp.nim]
extensions = "nim"
"""
    check parsetoml.parseString(Toml).validateTomlConfig.isSome

  test "Basic":
    const Toml ="""
[Lsp]
enable = true
"""
    check parsetoml.parseString(Toml).validateTomlConfig.isNone

  test "Basic 2":
    const Toml ="""
[Lsp]
enable = true

[Lsp.nim]
extensions = ["nim"]
command = "nimlsp"
trace = "verbose"
"""
    check parsetoml.parseString(Toml).validateTomlConfig.isNone

suite "settings: Validate theme colors":
  test "Invalid table":
    const Toml ="""
      [A]
      background = "#ffffff"
    """
    check parsetoml.parseString(Toml).validateThemeColorsConfig.isSome

  test "Invalid item":
    const Toml ="""
      [Colors]
      background = "#ffffff"
      invalidItem = "#ffffff"
    """
    check parsetoml.parseString(Toml).validateThemeColorsConfig.isSome

  test "Valid":
    check parsetoml.parseString(ColorsConfigStr)
      .validateThemeColorsConfig.isNone

suite "settings: toThemeColors":
  test "All #111111":
    let
      toml = parsetoml.parseString(ColorsConfigStr)
      themeColors = toml.toThemeColors

    for color in themeColors:
      check color.foreground.rgb == "#111111".hexToRgb.get
      check color.background.rgb == "#111111".hexToRgb.get

suite "settings: Validate configuration examples":
  test "Check moerc.toml":
    let
      path = "./example/moerc.toml"
      toml = parsetoml.parseFile(path)

    check validateTomlConfig(toml).isNone

  test "Check themes/dark.toml":
    let
      path = "./example/themes/dark.toml"
      toml = parsetoml.parseFile(path)

    check validateThemeColorsConfig(toml).isNone

  test "Check themes/light.toml":
    let
      path = "./example/themes/light.toml"
      toml = parsetoml.parseFile(path)

    check validateThemeColorsConfig(toml).isNone

  test "Check themes/vivid.toml":
    let
      path = "./example/themes/vivid.toml"
      toml = parsetoml.parseFile(path)

    check validateThemeColorsConfig(toml).isNone

suite "settings: LoadConfigFile":
  test "Load example/moerc.toml":
    var s = initEditorSettings()
    s.theme.path = "before"

    s.applyTomlConfigs(loadConfigFile("./example/moerc.toml").get)

    check s.theme.path != "before"

suite "settings: Generate toml current config":
  test "Generate current config":
    let
      settings = initEditorSettings()
      str = settings.genTomlConfigStr

      toml = parsetoml.parseString(str)
      result = toml.validateTomlConfig

    check result == none(InvalidItem)

suite "settings: Generate toml default config":
  test "Generate current config":
    let
      str = genDefaultTomlConfigStr()

      toml = parsetoml.parseString(str)
      result = toml.validateTomlConfig

    check result == none(InvalidItem)

suite "settings: Error message":
  test "Single line":
    const MoercStr = """
      [test]
      test = "test"
    """

    let
      toml = parseString(MoercStr)
      result = toml.validateTomlConfig
      errorMessage = result.get.toValidateErrorMessage

    check errorMessage == """(name: test, val: test = "test")"""

  test "Single line 2":
    const MoercStr = """
      [Standard]
      test = "test"
    """

    let
      toml = parseString(MoercStr)
      result = toml.validateTomlConfig
      errorMessage = result.get.toValidateErrorMessage

    check errorMessage == """(name: test, val: test)"""

  test "Multiple lines":
    const MoercStr = """
      [test]
      test1 = "test1"
      test2 = "test2"
    """

    let
      toml = parseString(MoercStr)
      result = toml.validateTomlConfig
      errorMessage = result.get.toValidateErrorMessage

    check errorMessage == """(name: test, val: test1 = "test1" test2 = "test2")"""

suite "settings: ColorMode to string for the config file":
  test "from ColorMode.none":
    check "none" == ColorMode.none.toConfigStr

  test "from ColorMode.c8":
    check "8" == ColorMode.c8.toConfigStr

  test "from ColorMode.c16":
    check "16" == ColorMode.c16.toConfigStr

  test "from ColorMode.c256":
    check "256" == ColorMode.c256.toConfigStr

  test "from ColorMode.c24bit":
    check "24bit" == ColorMode.c24bit.toConfigStr
