import std/[unittest, options, strutils]
import moepkg/[color, ui, highlight, unicodeext]

include moepkg/settings

const tomlStr = """
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
  popUpWindowInExmode = false
  autoDeleteParen = false
  smoothScroll = false
  smoothScrollSpeed = 1

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
  line = false
  column = false
  encoding = false
  language = false
  directory = false
  gitbranchName = false
  showGitInactive = true
  showModeInactive = true

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
  ClangOptions = "-Wall"
  CppOptions = "-Wall"
  NimOptions = "--debugger:native"
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
  search = false
  cursorPosition = false

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

  editorBg = "pink1"
  lineNum = "pink1"
  lineNumBg = "pink1"
  currentLineNum = "pink1"
  currentLineNumBg = "pink1"
  # statsu bar
  statusLineNormalMode = "pink1"
  statusLineNormalModeBg = "pink1"
  statusLineModeNormalMode = "pink1"
  statusLineModeNormalModeBg = "pink1"
  statusLineNormalModeInactive = "pink1"
  statusLineNormalModeInactiveBg = "pink1"

  statusLineInsertMode = "pink1"
  statusLineInsertModeBg = "pink1"
  statusLineModeInsertMode = "pink1"
  statusLineModeInsertModeBg = "pink1"
  statusLineInsertModeInactive = "pink1"
  statusLineInsertModeInactiveBg = "pink1"

  statusLineVisualMode = "pink1"
  statusLineVisualModeBg = "pink1"
  statusLineModeVisualMode = "pink1"
  statusLineModeVisualModeBg = "pink1"
  statusLineVisualModeInactive = "pink1"
  statusLineVisualModeInactiveBg = "pink1"

  statusLineReplaceMode = "pink1"
  statusLineReplaceModeBg = "pink1"
  statusLineModeReplaceMode = "pink1"
  statusLineModeReplaceModeBg = "pink1"
  statusLineReplaceModeInactive = "pink1"
  statusLineReplaceModeInactiveBg = "pink1"

  statusLineFilerMode = "pink1"
  statusLineFilerModeBg = "pink1"
  statusLineModeFilerMode = "pink1"
  statusLineModeFilerModeBg = "pink1"
  statusLineFilerModeInactive = "pink1"
  statusLineFilerModeInactiveBg = "pink1"

  statusLineExMode = "pink1"
  statusLineExModeBg = "pink1"
  statusLineModeExMode = "pink1"
  statusLineModeExModeBg = "pink1"
  statusLineExModeInactive = "pink1"
  statusLineExModeInactiveBg = "pink1"

  statusLineGitBranch = "pink1"
  statusLineGitBranchBg = "pink1"
  tab = "pink1"
  tabBg = "pink1"
  currentTab = "pink1"
  currentTabBg = "pink1"
  commandBar = "pink1"
  commandBarBg = "pink1"
  errorMessage = "pink1"
  errorMessageBg = "pink1"
  searchResult = "pink1"
  searchResultBg = "pink1"
  visualMode = "pink1"
  visualModeBg = "pink1"
  defaultChar = "pink1"
  gtKeyword = "pink1"
  gtFunctionName = "pink1"
  gtBoolean = "pink1"
  gtSpecialVar = "pink1"
  gtBuiltin = "pink1"
  gtStringLit = "pink1"
  gtDecNumber = "pink1"
  gtComment = "pink1"
  gtLongComment = "pink1"
  gtWhitespace = "pink1"
  gtPreprocessor = "pink1"
  currentFile = "pink1"
  currentFileBg = "pink1"
  file = "pink1"
  fileBg = "pink1"
  dir = "pink1"
  dirBg = "pink1"
  pcLink = "pink1"
  pcLinkBg = "pink1"
  popUpWindow = "pink1"
  popUpWindowBg = "pink1"
  popUpWinCurrentLine = "pink1"
  popUpWinCurrentLineBg = "pink1"
  replaceText = "pink1"
  replaceTextBg = "pink1"
  parenText = "pink1"
  parenTextBg = "pink1"
  currentWord = "pink1"
  currentWordBg = "pink1"
  highlightFullWidthSpace = "pink1"
  highlightFullWidthSpaceBg = "pink1"
  highlightTrailingSpaces = "pink1"
  highlightTrailingSpacesBg = "pink1"
  reservedWord = "pink1"
  reservedWordBg = "pink1"
  currentHistory = "pink1"
  currentHistoryBg = "pink1"
  addedLine = "pink1"
  addedLineBg = "pink1"
  deletedLine = "pink1"
  deletedLineBg = "pink1"
  currentSetting = "pink1"
  currentSettingBg = "pink1"
  currentLineBg = "pink1"
"""

suite "Parse configuration file":
  test "Parse all settings":
    let toml = parsetoml.parseString(tomlStr)
    var settings = parseSettingsFile(toml)

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
    check not settings.popUpWindowInExmode
    check not settings.autoDeleteParen
    check not settings.smoothScroll
    check settings.smoothScrollSpeed == 1

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
    check not settings.statusLine.line
    check not settings.statusLine.column
    check not settings.statusLine.characterEncoding
    check not settings.statusLine.language
    check not settings.statusLine.directory
    check not settings.statusLine.gitbranchName
    check settings.statusLine.showGitInactive
    check settings.statusLine.showModeInactive

    check settings.view.highlightCurrentLine
    check not settings.highlightSettings.replaceText
    check not settings.highlightSettings.pairOfParen
    check not settings.highlightSettings.fullWidthSpace
    check not settings.highlightSettings.trailingSpaces
    check not settings.highlightSettings.currentWord
    check settings.highlightSettings.reservedWords[3].word == "TEST"
    check settings.highlightSettings.reservedWords[4].word == "TEST2"

    check not settings.autoBackupSettings.enable
    check settings.autoBackupSettings.idleTime == 1
    check settings.autoBackupSettings.interval == 1
    check settings.autoBackupSettings.backupDir == ru"/tmp"
    check settings.autoBackupSettings.dirToExclude  == @[ru"/tmp"]

    check not settings.quickRunSettings.saveBufferWhenQuickRun
    check settings.quickRunSettings.command == "nimble build"
    check settings.quickRunSettings.timeout == 1
    check settings.quickRunSettings.nimAdvancedCommand == "js"
    check settings.quickRunSettings.ClangOptions == "-Wall"
    check settings.quickRunSettings.CppOptions == "-Wall"
    check settings.quickRunSettings.NimOptions == "--debugger:native"
    check settings.quickRunSettings.shOptions == "-c"
    check settings.quickRunSettings.bashOptions == "-c"

    check not settings.notificationSettings.screenNotifications
    check not settings.notificationSettings.logNotifications
    check not settings.notificationSettings.autoBackupScreenNotify
    check not settings.notificationSettings.autoBackupLogNotify
    check not settings.notificationSettings.autoSaveScreenNotify
    check not settings.notificationSettings.autoSaveLogNotify
    check not settings.notificationSettings.yankScreenNotify
    check not settings.notificationSettings.yankLogNotify
    check not settings.notificationSettings.deleteScreenNotify
    check not settings.notificationSettings.deleteLogNotify
    check not settings.notificationSettings.saveScreenNotify
    check not settings.notificationSettings.saveLogNotify
    check not settings.notificationSettings.quickRunScreenNotify
    check not settings.notificationSettings.quickRunLogNotify
    check not settings.notificationSettings.buildOnSaveScreenNotify
    check not settings.notificationSettings.buildOnSaveLogNotify
    check not settings.notificationSettings.filerScreenNotify
    check not settings.notificationSettings.filerLogNotify
    check not settings.notificationSettings.restoreScreenNotify
    check not settings.notificationSettings.restoreLogNotify

    check not settings.filerSettings.showIcons

    check settings.autocompleteSettings.enable

    check not settings.persist.exCommand
    check not settings.persist.search
    check not settings.persist.cursorPosition

    check not settings.debugModeSettings.windowNode.enable
    check not settings.debugModeSettings.windowNode.currentWindow
    check not settings.debugModeSettings.windowNode.index
    check not settings.debugModeSettings.windowNode.windowIndex
    check not settings.debugModeSettings.windowNode.bufferIndex
    check not settings.debugModeSettings.windowNode.parentIndex
    check not settings.debugModeSettings.windowNode.childLen
    check not settings.debugModeSettings.windowNode.splitType
    check not settings.debugModeSettings.windowNode.haveCursesWin
    check not settings.debugModeSettings.windowNode.y
    check not settings.debugModeSettings.windowNode.x
    check not settings.debugModeSettings.windowNode.h
    check not settings.debugModeSettings.windowNode.w
    check not settings.debugModeSettings.windowNode.currentLine
    check not settings.debugModeSettings.windowNode.currentColumn
    check not settings.debugModeSettings.windowNode.expandedColumn
    check not settings.debugModeSettings.windowNode.cursor

    check not settings.debugModeSettings.bufStatus.enable
    check not settings.debugModeSettings.bufStatus.bufferIndex
    check not settings.debugModeSettings.bufStatus.path
    check not settings.debugModeSettings.bufStatus.openDir
    check not settings.debugModeSettings.bufStatus.currentMode
    check not settings.debugModeSettings.bufStatus.prevMode
    check not settings.debugModeSettings.bufStatus.language
    check not settings.debugModeSettings.bufStatus.encoding
    check not settings.debugModeSettings.bufStatus.countChange
    check not settings.debugModeSettings.bufStatus.cmdLoop
    check not settings.debugModeSettings.bufStatus.lastSaveTime
    check not settings.debugModeSettings.bufStatus.bufferLen

    let theme = ColorTheme.config
    check ColorThemeTable[theme].editorBg == Color.pink1
    check ColorThemeTable[theme].lineNum == Color.pink1
    check ColorThemeTable[theme].lineNumBg == Color.pink1
    check ColorThemeTable[theme].currentLineNum == Color.pink1
    check ColorThemeTable[theme].currentLineNumBg == Color.pink1
    check ColorThemeTable[theme].statusLineNormalMode == Color.pink1
    check ColorThemeTable[theme].statusLineNormalModeBg == Color.pink1
    check ColorThemeTable[theme].statusLineModeNormalMode == Color.pink1
    check ColorThemeTable[theme].statusLineModeNormalModeBg == Color.pink1
    check ColorThemeTable[theme].statusLineNormalModeInactive == Color.pink1
    check ColorThemeTable[theme].statusLineNormalModeInactiveBg == Color.pink1
    check ColorThemeTable[theme].statusLineInsertMode == Color.pink1
    check ColorThemeTable[theme].statusLineInsertModeBg == Color.pink1
    check ColorThemeTable[theme].statusLineModeInsertMode == Color.pink1
    check ColorThemeTable[theme].statusLineModeInsertModeBg == Color.pink1
    check ColorThemeTable[theme].statusLineInsertModeInactive == Color.pink1
    check ColorThemeTable[theme].statusLineInsertModeInactiveBg == Color.pink1
    check ColorThemeTable[theme].statusLineVisualMode == Color.pink1
    check ColorThemeTable[theme].statusLineVisualModeBg == Color.pink1
    check ColorThemeTable[theme].statusLineModeVisualMode == Color.pink1
    check ColorThemeTable[theme].statusLineModeVisualModeBg == Color.pink1
    check ColorThemeTable[theme].statusLineVisualModeInactive == Color.pink1
    check ColorThemeTable[theme].statusLineVisualModeInactiveBg == Color.pink1
    check ColorThemeTable[theme].statusLineReplaceMode == Color.pink1
    check ColorThemeTable[theme].statusLineReplaceModeBg == Color.pink1
    check ColorThemeTable[theme].statusLineModeReplaceMode == Color.pink1
    check ColorThemeTable[theme].statusLineModeReplaceModeBg == Color.pink1
    check ColorThemeTable[theme].statusLineReplaceModeInactive == Color.pink1
    check ColorThemeTable[theme].statusLineReplaceModeInactiveBg == Color.pink1
    check ColorThemeTable[theme].statusLineFilerMode == Color.pink1
    check ColorThemeTable[theme].statusLineFilerModeBg == Color.pink1
    check ColorThemeTable[theme].statusLineModeFilerMode == Color.pink1
    check ColorThemeTable[theme].statusLineModeFilerModeBg == Color.pink1
    check ColorThemeTable[theme].statusLineFilerModeInactive == Color.pink1
    check ColorThemeTable[theme].statusLineFilerModeInactiveBg == Color.pink1
    check ColorThemeTable[theme].statusLineExMode == Color.pink1
    check ColorThemeTable[theme].statusLineExModeBg == Color.pink1
    check ColorThemeTable[theme].statusLineModeExMode == Color.pink1
    check ColorThemeTable[theme].statusLineModeExModeBg == Color.pink1
    check ColorThemeTable[theme].statusLineExModeInactive == Color.pink1
    check ColorThemeTable[theme].statusLineExModeInactiveBg == Color.pink1
    check ColorThemeTable[theme].statusLineGitBranch == Color.pink1
    check ColorThemeTable[theme].statusLineGitBranchBg == Color.pink1
    check ColorThemeTable[theme].tab == Color.pink1
    check ColorThemeTable[theme].tabBg == Color.pink1
    check ColorThemeTable[theme].currentTab == Color.pink1
    check ColorThemeTable[theme].currentTabBg == Color.pink1
    check ColorThemeTable[theme].commandBar == Color.pink1
    check ColorThemeTable[theme].commandBarBg == Color.pink1
    check ColorThemeTable[theme].errorMessage == Color.pink1
    check ColorThemeTable[theme].errorMessageBg == Color.pink1
    check ColorThemeTable[theme].searchResult == Color.pink1
    check ColorThemeTable[theme].searchResultBg == Color.pink1
    check ColorThemeTable[theme].visualMode == Color.pink1
    check ColorThemeTable[theme].visualModeBg == Color.pink1
    check ColorThemeTable[theme].defaultChar == Color.pink1
    check ColorThemeTable[theme].gtKeyword == Color.pink1
    check ColorThemeTable[theme].gtFunctionName == Color.pink1
    check ColorThemeTable[theme].gtBoolean == Color.pink1
    check ColorThemeTable[theme].gtSpecialVar == Color.pink1
    check ColorThemeTable[theme].gtBuiltin == Color.pink1
    check ColorThemeTable[theme].gtStringLit == Color.pink1
    check ColorThemeTable[theme].gtDecNumber == Color.pink1
    check ColorThemeTable[theme].gtComment == Color.pink1
    check ColorThemeTable[theme].gtLongComment == Color.pink1
    check ColorThemeTable[theme].gtWhitespace == Color.pink1
    check ColorThemeTable[theme].gtPreprocessor == Color.pink1
    check ColorThemeTable[theme].currentFile == Color.pink1
    check ColorThemeTable[theme].currentFileBg == Color.pink1
    check ColorThemeTable[theme].file == Color.pink1
    check ColorThemeTable[theme].fileBg == Color.pink1
    check ColorThemeTable[theme].dir == Color.pink1
    check ColorThemeTable[theme].dirBg == Color.pink1
    check ColorThemeTable[theme].pcLink == Color.pink1
    check ColorThemeTable[theme].pcLinkBg == Color.pink1
    check ColorThemeTable[theme].popUpWindow == Color.pink1
    check ColorThemeTable[theme].popUpWindowBg == Color.pink1
    check ColorThemeTable[theme].popUpWinCurrentLine == Color.pink1
    check ColorThemeTable[theme].popUpWinCurrentLineBg == Color.pink1
    check ColorThemeTable[theme].replaceText == Color.pink1
    check ColorThemeTable[theme].replaceTextBg == Color.pink1
    check ColorThemeTable[theme].parenText == Color.pink1
    check ColorThemeTable[theme].parenTextBg == Color.pink1
    check ColorThemeTable[theme].currentWordBg == Color.pink1
    check ColorThemeTable[theme].highlightFullWidthSpace == Color.pink1
    check ColorThemeTable[theme].highlightFullWidthSpaceBg == Color.pink1
    check ColorThemeTable[theme].highlightTrailingSpaces == Color.pink1
    check ColorThemeTable[theme].highlightTrailingSpacesBg == Color.pink1
    check ColorThemeTable[theme].reservedWord == Color.pink1
    check ColorThemeTable[theme].reservedWordBg == Color.pink1
    check ColorThemeTable[theme].currentHistory == Color.pink1
    check ColorThemeTable[theme].currentHistoryBg == Color.pink1
    check ColorThemeTable[theme].addedLine == Color.pink1
    check ColorThemeTable[theme].addedLineBg == Color.pink1
    check ColorThemeTable[theme].deletedLine == Color.pink1
    check ColorThemeTable[theme].deletedLineBg == Color.pink1
    check ColorThemeTable[theme].currentSetting == Color.pink1
    check ColorThemeTable[theme].currentSettingBg == Color.pink1
    check ColorThemeTable[theme].currentLineBg == Color.pink1

  test "Parse Clipboard setting 1":
    const str = """
      [Clipboard]
      enable = true
      toolOnLinux = "xclip""""

    let toml = parsetoml.parseString(str)
    let settings = parseSettingsFile(toml)

    check settings.clipboard.enable
    check settings.clipboard.toolOnLinux == ClipboardToolOnLinux.xclip

  test "Parse Clipboard setting 2":
    const str = """
      [Clipboard]
      enable = true
      toolOnLinux = "xsel""""

    let toml = parsetoml.parseString(str)
    let settings = parseSettingsFile(toml)

    check settings.clipboard.enable
    check settings.clipboard.toolOnLinux == ClipboardToolOnLinux.xsel

  test "Parse Clipboard setting 3":
    const str = """
      [Clipboard]
      enable = true
      toolOnLinux = "wl-clipboard""""

    let toml = parsetoml.parseString(str)
    let settings = parseSettingsFile(toml)

    check settings.clipboard.enable
    check settings.clipboard.toolOnLinux == ClipboardToolOnLinux.wlClipboard

suite "Validate toml config":
  test "Except for success":
    let toml = parsetoml.parseString(tomlStr)
    let result = toml.validateTomlConfig

    check result == none(InvalidItem)

  test "Validate vscode theme":
    const tomlThemeConfig ="""
      [Standard]
      theme = "vscode"
    """
    let toml = parsetoml.parseString(tomlThemeConfig)
    let result = toml.validateTomlConfig

    check result == none(InvalidItem)

  test "Except to fail":
    const tomlThemeConfig ="""
      [Persist]
      a = "a"
    """
    let toml = parsetoml.parseString(tomlThemeConfig)
    let result = toml.validateTomlConfig

    check isSome(result)

suite "Configuration example":
  test "Check moerc.toml":
    let
      filename = "./example/moerc.toml"
      toml = parsetoml.parseFile(filename)

    check toml.validateTomlConfig == none(InvalidItem)

suite "Generate toml config":
  test "Generate current config":
    let
      settings = initEditorSettings()
      str = settings.generateTomlConfigStr

      toml = parsetoml.parseString(str)
      result = toml.validateTomlConfig

    check result == none(InvalidItem)

suite "Error message":
  test "Single line":
    const TOML_STR = """
      [test]
      test = "test"
    """

    let
      toml = parseString(TOML_STR)
      result = toml.validateTomlConfig
      errorMessage = result.get.toValidateErrorMessage

    check errorMessage == """(name: test, val: test = "test")"""

  test "Single line 2":
    const TOML_STR = """
      [Standard]
      test = "test"
    """

    let
      toml = parseString(TOML_STR)
      result = toml.validateTomlConfig
      errorMessage = result.get.toValidateErrorMessage

    check errorMessage == """(name: test, val: test)"""

  test "Multiple lines":
    const TOML_STR = """
      [test]
      test1 = "test1"
      test2 = "test2"
    """

    let
      toml = parseString(TOML_STR)
      result = toml.validateTomlConfig
      errorMessage = result.get.toValidateErrorMessage

    check errorMessage == """(name: test, val: test1 = "test1" test2 = "test2")"""
