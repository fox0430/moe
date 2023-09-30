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
import moepkg/[color, unicodeext, ui, rgb, theme]

import moepkg/settings {.all.}

const TomlStr = """
  [Standard]
  theme = "config"
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
  autoSave = true
  autoSaveInterval = 1
  liveReloadOfConf = true
  incrementalSearch = false
  popupWindowInExmode = false
  autoDeleteParen = false
  colorMode = "none"

  [Clipboard]
  enable = false
  toolOnLinux = "xclip"

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
  enable = true

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
  baseTheme = "dark"

  background = "#000000"
  foreground = "#000000"

  lineNum = "#000000"
  lineNumBg = "#000000"

  currentLineNum = "#000000"
  currentLineNumBg = "#000000"

  statusLineNormalMode = "#000000"
  statusLineNormalModeBg = "#000000"
  statusLineNormalModeLabel = "#000000"
  statusLineNormalModeLabelBg = "#000000"
  statusLineNormalModeInactive = "#000000"
  statusLineNormalModeInactiveBg = "#000000"

  statusLineInsertMode = "#000000"
  statusLineInsertModeBg = "#000000"
  statusLineInsertModeLabel = "#000000"
  statusLineInsertModeLabelBg = "#000000"
  statusLineInsertModeInactive = "#000000"
  statusLineInsertModeInactiveBg = "#000000"

  statusLineVisualMode = "#000000"
  statusLineVisualModeBg = "#000000"
  statusLineVisualModeLabel = "#000000"
  statusLineVisualModeLabelBg = "#000000"
  statusLineVisualModeInactive = "#000000"
  statusLineVisualModeInactiveBg = "#000000"

  statusLineReplaceMode = "#000000"
  statusLineReplaceModeBg = "#000000"
  statusLineReplaceModeLabel = "#000000"
  statusLineReplaceModeLabelBg = "#000000"
  statusLineReplaceModeInactive = "#000000"
  statusLineReplaceModeInactiveBg = "#000000"

  statusLineFilerMode = "#000000"
  statusLineFilerModeBg = "#000000"
  statusLineFilerModeLabel = "#000000"
  statusLineFilerModeLabelBg = "#000000"
  statusLineFilerModeInactive = "#000000"
  statusLineFilerModeInactiveBg = "#000000"

  statusLineExMode = "#000000"
  statusLineExModeBg = "#000000"
  statusLineExModeLabel = "#000000"
  statusLineExModeLabelBg = "#000000"
  statusLineExModeInactive = "#000000"
  statusLineExModeInactiveBg = "#000000"

  statusLineGitChangedLines = "#000000"
  statusLineGitChangedLinesBg = "#000000"
  statusLineGitBranch = "#000000"
  statusLineGitBranchBg = "#000000"

  tab = "#000000"
  tabBg = "#000000"
  currentTab = "#000000"
  currentTabBg = "#000000"

  commandLine = "#000000"
  commandLineBg = "#000000"

  errorMessage = "#000000"
  errorMessageBg = "#000000"

  searchResult = "#000000"
  searchResultBg = "#000000"

  visualMode = "#000000"
  visualModeBg = "#000000"

  keyword = "#000000"
  functionName = "#000000"
  typeName = "#000000"
  boolean = "#000000"
  stringLit = "#000000"
  specialVar = "#000000"
  builtin = "#000000"
  binNumber = "#000000"
  decNumber = "#000000"
  floatNumber = "#000000"
  hexNumber = "#000000"
  octNumber = "#000000"
  comment = "#000000"
  longComment = "#000000"
  whitespace = "#000000"
  preprocessor = "#000000"
  pragma = "#000000"

  currentFile = "#000000"
  currentFileBg = "#000000"
  file = "#000000"
  fileBg = "#000000"
  dir = "#000000"
  dirBg = "#000000"
  pcLink = "#000000"
  pcLinkBg = "#000000"

  popupWindow = "#000000"
  popupWindowBg = "#000000"
  popupWinCurrentLine = "#000000"
  popupWinCurrentLineBg = "#000000"

  replaceText = "#000000"
  replaceTextBg = "#000000"

  parenPair = "#000000"
  parenPairBg = "#000000"

  currentWord = "#000000"
  currentWordBg = "#000000"

  highlightFullWidthSpace = "#000000"
  highlightFullWidthSpaceBg = "#000000"

  highlightTrailingSpaces = "#000000"
  highlightTrailingSpacesBg = "#000000"

  reservedWord = "#000000"
  reservedWordBg = "#000000"

  syntaxCheckInfo = "#000000"
  syntaxCheckInfoBg = "#000000"
  syntaxCheckHint = "#000000"
  syntaxCheckHintBg = "#000000"
  syntaxCheckWarn = "#000000"
  syntaxCheckWarnBg = "#000000"
  syntaxCheckErr = "#000000"
  syntaxCheckErrBg = "#000000"

  gitConflict = "#000000"
  gitConflictBg = "#000000"

  backupManagerCurrentLine = "#000000"
  backupManagerCurrentLineBg = "#000000"

  diffViewerAddedLine = "#000000"
  diffViewerAddedLineBg = "#000000"
  diffViewerDeletedLine = "#000000"
  diffViewerDeletedLineBg = "#000000"

  configModeCurrentLine = "#000000"
  configModeCurrentLineBg = "#000000"

  currentLineBg = "#000000"

  sidebarGitAddedSign = "#000000"
  sidebarGitAddedSignBg = "#000000"
  sidebarGitDeletedSign = "#000000"
  sidebarGitDeletedSignBg = "#000000"
  sidebarGitChangedSign = "#000000"
  sidebarGitChangedSignBg = "#000000"

  sidebarSyntaxCheckInfoSign = "#000000"
  sidebarSyntaxCheckInfoSignBg = "#000000"
  sidebarSyntaxCheckHintSign = "#000000"
  sidebarSyntaxCheckHintSignBg = "#000000"
  sidebarSyntaxCheckWarnSign = "#000000"
  sidebarSyntaxCheckWarnSignBg = "#000000"
  sidebarSyntaxCheckErrSign = "#000000"
  sidebarSyntaxCheckErrSignBg = "#000000"
"""

suite "Parse configuration file":
  test "Parse all settings":
    let toml = parsetoml.parseString(TomlStr)
    var settings = parseTomlConfigs(toml)

    check settings.editorColorTheme == ColorTheme.config
    check not settings.view.lineNumber
    check not settings.view.currentLineNumber
    check settings.view.cursorLine
    check not settings.statusLine.enable
    check not settings.tabLine.enable
    check not settings.syntax
    check not settings.view.indentationLines
    check settings.view.tabStop == 4
    check not settings.autoCloseParen
    check not settings.autoIndent
    check not settings.ignorecase
    check not settings.smartcase
    check settings.disableChangeCursor
    check settings.defaultCursor == CursorType.blinkIbeam
    check settings.normalModeCursor == CursorType.blinkIbeam
    check settings.insertModeCursor == CursorType.blinkBlock
    check settings.autoSave
    check settings.autoSaveInterval == 1
    check settings.liveReloadOfConf
    check not settings.incrementalSearch
    check not settings.popupWindowInExmode
    check not settings.autoDeleteParen
    check settings.colorMode == ColorMode.none

    check not settings.clipboard.enable
    check settings.clipboard.toolOnLinux == ClipboardToolOnLinux.xclip

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

    check settings.autocomplete.enable

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

    for pair in ColorThemeTable[ColorTheme.config]:
      check pair.foreground.rgb == "#000000".hexToRgb.get
      check pair.background.rgb == "#000000".hexToRgb.get

  test "Parse Clipboard setting 1":
    const Str = """
      [Clipboard]
      enable = true
      toolOnLinux = "xclip""""

    let toml = parsetoml.parseString(Str)
    let settings = parseTomlConfigs(toml)

    check settings.clipboard.enable
    check settings.clipboard.toolOnLinux == ClipboardToolOnLinux.xclip

  test "Parse Clipboard setting 2":
    const Str = """
      [Clipboard]
      enable = true
      toolOnLinux = "xsel""""

    let toml = parsetoml.parseString(Str)
    let settings = parseTomlConfigs(toml)

    check settings.clipboard.enable
    check settings.clipboard.toolOnLinux == ClipboardToolOnLinux.xsel

  test "Parse Clipboard setting 3":
    const Str = """
      [Clipboard]
      enable = true
      toolOnLinux = "wl-clipboard""""

    let toml = parsetoml.parseString(Str)
    let settings = parseTomlConfigs(toml)

    check settings.clipboard.enable
    check settings.clipboard.toolOnLinux == ClipboardToolOnLinux.wlClipboard

  test "Parse color Mode setting 1":
    const Str = """
      [Standard]
      colorMode = "none"
    """

    let toml = parsetoml.parseString(Str)
    let settings = parseTomlConfigs(toml)

    check ColorMode.none == settings.colorMode

  test "Parse color Mode setting 2":
    const Str = """
      [Standard]
      colorMode = "8"
    """

    let toml = parsetoml.parseString(Str)
    let settings = parseTomlConfigs(toml)

    check ColorMode.c8 == settings.colorMode

  test "Parse color Mode setting 3":
    const Str = """
      [Standard]
      colorMode = "256"
    """

    let toml = parsetoml.parseString(Str)
    let settings = parseTomlConfigs(toml)

    check ColorMode.c256  == settings.colorMode

  test "Parse color Mode setting 4":
    const Str = """
      [Standard]
      colorMode = "24bit"
    """

    let toml = parsetoml.parseString(Str)
    let settings = parseTomlConfigs(toml)

    check ColorMode.c24bit == settings.colorMode

suite "Validate toml config":
  test "Except for success":
    let toml = parsetoml.parseString(TomlStr)
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

suite "Validate Standard.theme":
  test "Dark":
    const TomlThemeConfig ="""
      [Standard]
      theme = "dark"
    """

    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    check result == none(InvalidItem)

  test "light":
    const TomlThemeConfig ="""
      [Standard]
      theme = "light"
    """

    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    check result == none(InvalidItem)

  test "vivid":
    const TomlThemeConfig ="""
      [Standard]
      theme = "vivid"
    """

    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    check result == none(InvalidItem)

  test "config":
    const TomlThemeConfig ="""
      [Standard]
      theme = "config"
    """

    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    check result == none(InvalidItem)

  test "vscode":
    const TomlThemeConfig ="""
      [Standard]
      theme = "vscode"
    """

    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    check result == none(InvalidItem)

  test "Invalid value":
    const TomlThemeConfig ="""
      [Standard]
      theme = "a"
    """

    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    privateAccess InvalidItem
    check result == some(InvalidItem(name: "theme", val: "a"))

suite "Validate theme tables":
  test "Color code":
    const TomlThemeConfig ="""
      [Standard]
      theme = "config"

      [Theme]
      baseTheme = "dark"
      foreground = "#000000"
    """
    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    check result.isNone

  test "termDefaultFg":
    const TomlThemeConfig ="""
      [Standard]
      theme = "config"

      [Theme]
      baseTheme = "dark"
      foreground = "termDefaultFg"
    """
    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    check result.isNone

  test "termDefaultBg":
    const TomlThemeConfig ="""
      [Standard]
      theme = "config"

      [Theme]
      baseTheme = "dark"
      background = "termDefaultBg"
    """
    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    check result.isNone

  test "Invalid key":
    const TomlThemeConfig ="""
      [Standard]
      theme = "config"

      [Theme]
      a = "dark"
    """
    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    privateAccess InvalidItem
    check result == some(InvalidItem(name: "a", val: "dark"))

  test "Invalid value 1":
    const TomlThemeConfig ="""
      [Standard]
      theme = "config"

      [Theme]
      baseTheme = "a"
    """
    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    privateAccess InvalidItem
    check result == some(InvalidItem(name: "baseTheme", val: "a"))

  test "Invalid value 2":
    const TomlThemeConfig ="""
      [Standard]
      theme = "config"

      [Theme]
      baseTheme = "dark"
      foreground = "0"
    """
    let toml = parsetoml.parseString(TomlThemeConfig)
    let result = toml.validateTomlConfig

    privateAccess InvalidItem
    check result == some(InvalidItem(name: "foreground", val: "0"))

suite "Configuration example":
  test "Check moerc.toml":
    let
      filename = "./example/moerc.toml"
      toml = parsetoml.parseFile(filename)

    check toml.validateTomlConfig == none(InvalidItem)

suite "Generate toml current config":
  test "Generate current config":
    let
      settings = initEditorSettings()
      str = settings.genTomlConfigStr

      toml = parsetoml.parseString(str)
      result = toml.validateTomlConfig

    check result == none(InvalidItem)

suite "Generate toml default config":
  test "Generate current config":
    let
      str = genDefaultTomlConfigStr()

      toml = parsetoml.parseString(str)
      result = toml.validateTomlConfig

    check result == none(InvalidItem)

suite "Error message":
  test "Single line":
    const TomlStr = """
      [test]
      test = "test"
    """

    let
      toml = parseString(TomlStr)
      result = toml.validateTomlConfig
      errorMessage = result.get.toValidateErrorMessage

    check errorMessage == """(name: test, val: test = "test")"""

  test "Single line 2":
    const TomlStr = """
      [Standard]
      test = "test"
    """

    let
      toml = parseString(TomlStr)
      result = toml.validateTomlConfig
      errorMessage = result.get.toValidateErrorMessage

    check errorMessage == """(name: test, val: test)"""

  test "Multiple lines":
    const TomlStr = """
      [test]
      test1 = "test1"
      test2 = "test2"
    """

    let
      toml = parseString(TomlStr)
      result = toml.validateTomlConfig
      errorMessage = result.get.toValidateErrorMessage

    check errorMessage == """(name: test, val: test1 = "test1" test2 = "test2")"""

suite "ColorMode to string for the config file":
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
