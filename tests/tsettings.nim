import unittest, options
import moepkg/[color, ui, highlight, unicodeext]

include moepkg/settings

const tomlStr = """
  [Standard]
  theme = "config"
  number = false
  currentNumber = false
  cursorLine = true
  statusBar = false
  tabLine = false
  syntax = false
  indentationLines = false
  tabStop = 4
  autoCloseParen = false
  autoIndent = false
  disableChangeCursor = true
  defaultCursor = "blinkIbeam"
  normalModeCursor = "blinkIbeam"
  insertModeCursor = "blinkBlock"
  autoSave = true
  autoSaveInterval = 1
  liveReloadOfConf = true
  realtimeSearch = false
  popUpWindowInExmode = false
  replaceTextHighlight = false
  highlightPairOfParen = false
  autoDeleteParen = false
  systemClipboard = false
  highlightFullWidthSpace = false
  highlightTrailingSpaces = false
  highlightCurrentWord = false

  [TabLine]
  allBuffer = true

  [StatusBar]
  mode = false
  filename = false
  chanedMark = false
  line = false
  column = false
  encoding = false
  language = false
  directory = false
  multipleStatusBar = false
  gitbranchName = false
  showGitInactive = true
  showModeInactive = true

  [WorkSpace]
  useBar = true

  [Highlight]
  reservedWord = ["TEST", "TEST2"]

  [AutoBackup]
  enable = false
  idolTime = 1
  interval = 1
  backupDir = "/tmp"

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
  workspaceScreenNotify = false
  workspaceLogNotify = false
  quickRunScreenNotify = false
  quickRunLogNotify = false
  buildOnSaveScreenNotify = false
  buildOnSaveLogNotify = false
  filerScreenNotify = false
  filerLogNotify = false

  [Filer]
  showIcons = false

  [Theme]

  baseTheme = "dark"

  editorBg = "pink1"
  lineNum = "pink1"
  lineNumBg = "pink1"
  currentLineNum = "pink1"
  currentLineNumBg = "pink1"
  # statsu bar
  statusBarNormalMode = "pink1"
  statusBarNormalModeBg = "pink1"
  statusBarModeNormalMode = "pink1"
  statusBarModeNormalModeBg = "pink1"
  statusBarNormalModeInactive = "pink1"
  statusBarNormalModeInactiveBg = "pink1"

  statusBarInsertMode = "pink1"
  statusBarInsertModeBg = "pink1"
  statusBarModeInsertMode = "pink1"
  statusBarModeInsertModeBg = "pink1"
  statusBarInsertModeInactive = "pink1"
  statusBarInsertModeInactiveBg = "pink1"

  statusBarVisualMode = "pink1"
  statusBarVisualModeBg = "pink1"
  statusBarModeVisualMode = "pink1"
  statusBarModeVisualModeBg = "pink1"
  statusBarVisualModeInactive = "pink1"
  statusBarVisualModeInactiveBg = "pink1"

  statusBarReplaceMode = "pink1"
  statusBarReplaceModeBg = "pink1"
  statusBarModeReplaceMode = "pink1"
  statusBarModeReplaceModeBg = "pink1"
  statusBarReplaceModeInactive = "pink1"
  statusBarReplaceModeInactiveBg = "pink1"

  statusBarFilerMode = "pink1"
  statusBarFilerModeBg = "pink1"
  statusBarModeFilerMode = "pink1"
  statusBarModeFilerModeBg = "pink1"
  statusBarFilerModeInactive = "pink1"
  statusBarFilerModeInactiveBg = "pink1"

  statusBarExMode = "pink1"
  statusBarExModeBg = "pink1"
  statusBarModeExMode = "pink1"
  statusBarModeExModeBg = "pink1"
  statusBarExModeInactive = "pink1"
  statusBarExModeInactiveBg = "pink1"

  statusBarGitBranch = "pink1"
  statusBarGitBranchBg = "pink1"
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
  workSpaceBar = "pink1"
  workSpaceBarBg = "pink1"
  reservedWord = "pink1"
  reservedWordBg = "pink1"
"""



suite "Parse configuration file":
  test "Parse toml configuration file":
    let toml = parsetoml.parseString(tomlStr)
    var settings = parseSettingsFile(toml)

    check settings.editorColorTheme == ColorTheme.config
    check not settings.view.lineNumber
    check not settings.view.currentLineNumber
    check settings.view.cursorLine
    check not settings.statusBar.useBar
    check not settings.tabLine.useTab
    check not settings.syntax
    check not settings.view.indentationLines
    check settings.view.tabStop == 4
    check not settings.autoCloseParen
    check not settings.autoIndent
    check settings.disableChangeCursor
    check settings.defaultCursor == CursorType.blinkIbeam
    check settings.normalModeCursor == CursorType.blinkIbeam
    check settings.insertModeCursor == CursorType.blinkBlock
    check settings.autoSave
    check settings.autoSaveInterval == 1
    check settings.liveReloadOfConf
    check not settings.realtimeSearch
    check not settings.popUpWindowInExmode
    check not settings.replaceTextHighlight
    check not settings.highlightPairOfParen
    check not settings.autoDeleteParen
    check not settings.systemClipboard
    check not settings.highlightFullWidthSpace
    check not settings.highlightTrailingSpaces
    check not settings.highlightOtherUsesCurrentWord

    check settings.tabLine.allbuffer

    check not settings.statusBar.useBar
    check not settings.statusBar.mode
    check not settings.statusBar.filename
    check not settings.statusBar.chanedMark
    check not settings.statusBar.line
    check not settings.statusBar.column
    check not settings.statusBar.characterEncoding
    check not settings.statusBar.language
    check not settings.statusBar.directory
    check not settings.statusBar.multipleStatusBar
    check not settings.statusBar.gitbranchName
    check settings.statusBar.showGitInactive
    check settings.statusBar.showModeInactive

    check settings.workSpace.useBar

    check settings.reservedWords[3].word == "TEST"
    check settings.reservedWords[4].word == "TEST2"

    check not settings.autoBackupSettings.enable
    check settings.autoBackupSettings.idolTime == 1
    check settings.autoBackupSettings.interval == 1
    check settings.autoBackupSettings.backupDir == ru"/tmp"

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
    check not settings.notificationSettings.workspaceScreenNotify
    check not settings.notificationSettings.workspaceLogNotify
    check not settings.notificationSettings.quickRunScreenNotify
    check not settings.notificationSettings.quickRunLogNotify
    check not settings.notificationSettings.buildOnSaveScreenNotify
    check not settings.notificationSettings.buildOnSaveLogNotify
    check not settings.notificationSettings.filerScreenNotify
    check not settings.notificationSettings.filerLogNotify

    check not settings.filerSettings.showIcons

    let theme = ColorTheme.config
    check ColorThemeTable[theme].editorBg == Color.pink1
    check ColorThemeTable[theme].lineNum == Color.pink1
    check ColorThemeTable[theme].lineNumBg == Color.pink1
    check ColorThemeTable[theme].currentLineNum == Color.pink1
    check ColorThemeTable[theme].currentLineNumBg == Color.pink1
    check ColorThemeTable[theme].statusBarNormalMode == Color.pink1
    check ColorThemeTable[theme].statusBarNormalModeBg == Color.pink1
    check ColorThemeTable[theme].statusBarModeNormalMode == Color.pink1
    check ColorThemeTable[theme].statusBarModeNormalModeBg == Color.pink1
    check ColorThemeTable[theme].statusBarNormalModeInactive == Color.pink1
    check ColorThemeTable[theme].statusBarNormalModeInactiveBg == Color.pink1
    check ColorThemeTable[theme].statusBarInsertMode == Color.pink1
    check ColorThemeTable[theme].statusBarInsertModeBg == Color.pink1
    check ColorThemeTable[theme].statusBarModeInsertMode == Color.pink1
    check ColorThemeTable[theme].statusBarModeInsertModeBg == Color.pink1
    check ColorThemeTable[theme].statusBarInsertModeInactive == Color.pink1
    check ColorThemeTable[theme].statusBarInsertModeInactiveBg == Color.pink1
    check ColorThemeTable[theme].statusBarVisualMode == Color.pink1
    check ColorThemeTable[theme].statusBarVisualModeBg == Color.pink1
    check ColorThemeTable[theme].statusBarModeVisualMode == Color.pink1
    check ColorThemeTable[theme].statusBarModeVisualModeBg == Color.pink1
    check ColorThemeTable[theme].statusBarVisualModeInactive == Color.pink1
    check ColorThemeTable[theme].statusBarVisualModeInactiveBg == Color.pink1
    check ColorThemeTable[theme].statusBarReplaceMode == Color.pink1
    check ColorThemeTable[theme].statusBarReplaceModeBg == Color.pink1
    check ColorThemeTable[theme].statusBarModeReplaceMode == Color.pink1
    check ColorThemeTable[theme].statusBarModeReplaceModeBg == Color.pink1
    check ColorThemeTable[theme].statusBarReplaceModeInactive == Color.pink1
    check ColorThemeTable[theme].statusBarReplaceModeInactiveBg == Color.pink1
    check ColorThemeTable[theme].statusBarFilerMode == Color.pink1
    check ColorThemeTable[theme].statusBarFilerModeBg == Color.pink1
    check ColorThemeTable[theme].statusBarModeFilerMode == Color.pink1
    check ColorThemeTable[theme].statusBarModeFilerModeBg == Color.pink1
    check ColorThemeTable[theme].statusBarFilerModeInactive == Color.pink1
    check ColorThemeTable[theme].statusBarFilerModeInactiveBg == Color.pink1
    check ColorThemeTable[theme].statusBarExMode == Color.pink1
    check ColorThemeTable[theme].statusBarExModeBg == Color.pink1
    check ColorThemeTable[theme].statusBarModeExMode == Color.pink1
    check ColorThemeTable[theme].statusBarModeExModeBg == Color.pink1
    check ColorThemeTable[theme].statusBarExModeInactive == Color.pink1
    check ColorThemeTable[theme].statusBarExModeInactiveBg == Color.pink1
    check ColorThemeTable[theme].statusBarGitBranch == Color.pink1
    check ColorThemeTable[theme].statusBarGitBranchBg == Color.pink1
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
    check ColorThemeTable[theme].workSpaceBar == Color.pink1
    check ColorThemeTable[theme].workSpaceBarBg == Color.pink1
    check ColorThemeTable[theme].reservedWord == Color.pink1
    check ColorThemeTable[theme].reservedWordBg == Color.pink1

suite "Validate toml config":
  test "Except for success":
    let toml = parsetoml.parseString(tomlStr)
    let result = toml.validateTomlConfig

    check result == none(string)

  test "Validate vscode theme":
    const tomlThemeConfig ="""
      [Standard]
      theme = "vscode"
    """
    let toml = parsetoml.parseString(tomlThemeConfig)
    let result = toml.validateTomlConfig

    check result == none(string)
