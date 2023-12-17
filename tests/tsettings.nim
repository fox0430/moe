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
import moepkg/[unicodeext, ui]

import moepkg/settings {.all.}

const TomlStr = """
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

  [Lsp.nim]
  extensions = ["nim"]
  command = "nimlangserver"

  [Lsp.rust]
  extensions = ["rs"]
  command = "rust-analyzer"

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

suite "Parse configuration file":
  test "Parse all settings":
    var settings = initEditorSettings()
    settings.applyTomlConfigs(parsetoml.parseString(TomlStr))

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
    check settings.lsp.languages["nim"] == LspLanguageSettings(
      extensions: @[ru"nim"],
      command: ru"nimlangserver")

    check settings.lsp.languages["rust"] == LspLanguageSettings(
      extensions: @[ru"rs"],
      command: ru"rust-analyzer")

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
