import unittest, macros, strformat
import moepkg/[editorstatus, gapbuffer, bufferstatus, unicodetext]

include moepkg/configmode

suite "Config mode: Start configuration mode":
  test "Init configuration mode buffer":
    var status = initEditorStatus()
    status.addNewBuffer(Mode.config)

    currentBufStatus.buffer = initConfigModeBuffer(status.settings)

suite "Config mode: Init buffer":
  test "Init standard table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.initStandardTableBuffer

    const sample = @[ru "Standard",
                     ru "  theme                          dark",
                     ru "  number                         true",
                     ru "  currentNumber                  true",
                     ru "  cursorLine                     false",
                     ru "  statusLine                     true",
                     ru "  tabLine                        true",
                     ru "  syntax                         true",
                     ru "  indentationLines               true",
                     ru "  tabStop                        2",
                     ru "  autoCloseParen                 true",
                     ru "  autoIndent                     true",
                     ru "  ignorecase                     true",
                     ru "  smartcase                      true",
                     ru "  disableChangeCursor            false",
                     ru "  defaultCursor                  blinkBlock",
                     ru "  normalModeCursor               blinkBlock",
                     ru "  insertModeCursor               blinkIbeam",
                     ru "  autoSave                       false",
                     ru "  autoSaveInterval               5",
                     ru "  liveReloadOfConf               false",
                     ru "  incrementalSearch              true",
                     ru "  popUpWindowInExmode            true",
                     ru "  autoDeleteParen                true",
                     ru "  systemClipboard                true",
                     ru "  smoothScroll                   true",
                     ru "  smoothScrollSpeed              15"]

    for index, line in buffer:
      check sample[index] == line

  test "Init build on save table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.buildOnSave.initBuildOnSaveTableBuffer

    const sample = @[ru "BuildOnSave",
                     ru "  enable                         false",
                     ru "  workspaceRoot                  ",
                     ru "  command                        "]

    for index, line in buffer:
      check sample[index] == line

  test "Init tab line table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.initTabLineTableBuffer

    const sample = @[ru "TabLine",
                     ru "  allBuffer                      false"]

    for index, line in buffer:
      check sample[index] == line

  test "Init status line table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.statusLine.initStatusLineTableBuffer

    const sample = @[ru "StatusLine",
                     ru "  multipleStatusLine             true",
                     ru "  merge                          false",
                     ru "  mode                           true",
                     ru "  filename                       true",
                     ru "  chanedMark                     true",
                     ru "  line                           true",
                     ru "  column                         true",
                     ru "  encoding                       true",
                     ru "  language                       true",
                     ru "  directory                      true",
                     ru "  gitbranchName                  true",
                     ru "  showGitInactive                false",
                     ru "  showModeInactive               false"]

    for index, line in buffer:
      check sample[index] == line

  test "Init workspace table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.initWorkspaceTableBuffer

    const sample = @[ru "WorkSpace",
                     ru "  workSpaceLine                  false"]

    for index, line in buffer:
      check sample[index] == line

  test "Init highlight table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.initHighlightTableBuffer

    const sample = @[ru "Highlight",
                     ru "  currentLine                    false",
                     ru "  fullWidthSpace                 true",
                     ru "  trailingSpaces                 true",
                     ru "  currentWord                    true",
                     ru "  replaceText                    true",
                     ru "  reservedWord                   TODO WIP NOTE "]

    for index, line in buffer:
      check sample[index] == line

  test "Init auto backup table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.autoBackupSettings.initAutoBackupTableBuffer

    const sample = @[ru "AutoBackup",
                     ru "  enable                         true",
                     ru "  idleTime                       10",
                     ru "  interval                       5",
                     ru "  backupDir                      ",
                     ru "  dirToExclude                   /etc"]

    for index, line in buffer:
      check sample[index] == line

  test "Init QuickRun table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.quickRunSettings.initQuickRunTableBuffer

    const sample = @[ru "QuickRun",
                     ru "  saveBufferWhenQuickRun         true",
                     ru "  command                        ",
                     ru "  timeout                        30",
                     ru "  nimAdvancedCommand             c",
                     ru "  ClangOptions                   ",
                     ru "  CppOptions                     ",
                     ru "  NimOptions                     ",
                     ru "  shOptions                      ",
                     ru "  bashOptions                    "]

    for index, line in buffer:
      check sample[index] == line

  test "Init Notification table buffer":
    var status = initEditorStatus()
    let
      notificationSettings = status.settings.notificationSettings
      buffer = notificationSettings.initNotificationTableBuffer

    const sample = @[ru "Notification",
                     ru "  screenNotifications            true",
                     ru "  logNotifications               true",
                     ru "  autoBackupScreenNotify         true",
                     ru "  autoBackupLogNotify            true",
                     ru "  autoSaveScreenNotify           true",
                     ru "  autoSaveLogNotify              true",
                     ru "  yankScreenNotify               true",
                     ru "  yankLogNotify                  true",
                     ru "  deleteScreenNotify             true",
                     ru "  deleteLogNotify                true",
                     ru "  saveScreenNotify               true",
                     ru "  saveLogNotify                  true",
                     ru "  workspaceScreenNotify          true",
                     ru "  workspaceLogNotify             true",
                     ru "  quickRunScreenNotify           true",
                     ru "  quickRunLogNotify              true",
                     ru "  buildOnSaveScreenNotify        true",
                     ru "  buildOnSaveLogNotify           true",
                     ru "  filerScreenNotify              true",
                     ru "  filerLogNotify                 true",
                     ru "  restoreScreenNotify            true",
                     ru "  restoreLogNotify               true"]

    for index, line in buffer:
      check sample[index] == line

  test "Init Filer table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.initFilerTableBuffer

    const sample = @[ru "Filer",
                     ru "  showIcons                      true"]

    for index, line in buffer:
      check sample[index] == line

  test "Init Filer table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.initAutocompleteTableBuffer

    const sample = @[ru "Autocomplete",
                     ru "  enable                         true"]

    for index, line in buffer:
      check sample[index] == line

  test "Init Theme table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.initThemeTableBuffer

    const sample = @[ru "Theme",
                     ru "  editorBg",
                     ru "    background                   default",
                     ru "",
                     ru "  lineNum",
                     ru "    foreground                   gray54",
                     ru "    background                   default",
                     ru "",
                     ru "  currentLineNum",
                     ru "    foreground                   teal",
                     ru "    background                   default",
                     ru "",
                     ru "  statusLineNormalMode",
                     ru "    foreground                   white",
                     ru "    background                   blue",
                     ru "",
                     ru "  statusLineModeNormalMode",
                     ru "    foreground                   black",
                     ru "    background                   white",
                     ru "",
                     ru "  statusLineNormalModeInactive",
                     ru "    foreground                   blue",
                     ru "    background                   white",
                     ru "",
                     ru "  statusLineInsertMode",
                     ru "    foreground                   white",
                     ru "    background                   blue",
                     ru "",
                     ru "  statusLineModeInsertMode",
                     ru "    foreground                   black",
                     ru "    background                   white",
                     ru "",
                     ru "  statusLineInsertModeInactive",
                     ru "    foreground                   blue",
                     ru "    background                   white",
                     ru "",
                     ru "  statusLineVisualMode",
                     ru "    foreground                   white",
                     ru "    background                   blue",
                     ru "",
                     ru "  statusLineModeVisualMode",
                     ru "    foreground                   black",
                     ru "    background                   white",
                     ru "",
                     ru "  statusLineVisualModeInactive",
                     ru "    foreground                   blue",
                     ru "    background                   white",
                     ru "",
                     ru "  statusLineReplaceMode",
                     ru "    foreground                   white",
                     ru "    background                   blue",
                     ru "",
                     ru "  statusLineModeReplaceMode",
                     ru "    foreground                   black",
                     ru "    background                   white",
                     ru "",
                     ru "  statusLineReplaceModeInactive",
                     ru "    foreground                   blue",
                     ru "    background                   white",
                     ru "",
                     ru "  statusLineFilerMode",
                     ru "    foreground                   white",
                     ru "    background                   blue",
                     ru "",
                     ru "  statusLineModeFilerMode",
                     ru "    foreground                   black",
                     ru "    background                   white",
                     ru "",
                     ru "  statusLineFilerModeInactive",
                     ru "    foreground                   blue",
                     ru "    background                   white",
                     ru "",
                     ru "  statusLineExMode",
                     ru "    foreground                   white",
                     ru "    background                   blue",
                     ru "",
                     ru "  statusLineModeExMode",
                     ru "    foreground                   black",
                     ru "    background                   white",
                     ru "",
                     ru "  statusLineExModeInactive",
                     ru "    foreground                   blue",
                     ru "    background                   white",
                     ru "",
                     ru "  statusLineGitBranch",
                     ru "    foreground                   white",
                     ru "    background                   blue",
                     ru "",
                     ru "  tab",
                     ru "    foreground                   white",
                     ru "    background                   default",
                     ru "",
                     ru "  currentTab",
                     ru "    foreground                   white",
                     ru "    background                   blue",
                     ru "",
                     ru "  commandBar",
                     ru "    foreground                   gray100",
                     ru "    background                   default",
                     ru "",
                     ru "  errorMessage",
                     ru "    foreground                   red",
                     ru "    background                   default",
                     ru "",
                     ru "  searchResult",
                     ru "    foreground                   default",
                     ru "    background                   red",
                     ru "",
                     ru "  visualMode",
                     ru "    foreground                   gray100",
                     ru "    background                   purple_1",
                     ru "",
                     ru "  defaultChar",
                     ru "    foreground                   white",
                     ru "    background                   default",
                     ru "",
                     ru "  keyword",
                     ru "    foreground                   skyBlue1",
                     ru "    background                   default",
                     ru "",
                     ru "  functionName",
                     ru "    foreground                   gold1",
                     ru "    background                   default",
                     ru "",
                     ru "  boolean",
                     ru "    foreground                   yellow",
                     ru "    background                   default",
                     ru "",
                     ru "  specialVar",
                     ru "    foreground                   green",
                     ru "    background                   default",
                     ru "",
                     ru "  builtin",
                     ru "    foreground                   yellow",
                     ru "    background                   default",
                     ru "",
                     ru "  stringLit",
                     ru "    foreground                   yellow",
                     ru "    background                   default",
                     ru "",
                     ru "  decNumber",
                     ru "    foreground                   aqua",
                     ru "    background                   default",
                     ru "",
                     ru "  comment",
                     ru "    foreground                   gray",
                     ru "    background                   default",
                     ru "",
                     ru "  longComment",
                     ru "    foreground                   gray",
                     ru "    background                   default",
                     ru "",
                     ru "  whitespace",
                     ru "    foreground                   gray",
                     ru "    background                   default",
                     ru "",
                     ru "  preprocessor",
                     ru "    foreground                   green",
                     ru "    background                   default",
                     ru "",
                     ru "  currentFile",
                     ru "    foreground                   gray100",
                     ru "    background                   teal",
                     ru "",
                     ru "  file",
                     ru "    foreground                   gray100",
                     ru "    background                   default",
                     ru "",
                     ru "  dir",
                     ru "    foreground                   blue",
                     ru "    background                   default",
                     ru "",
                     ru "  pcLink",
                     ru "    foreground                   teal",
                     ru "    background                   default",
                     ru "",
                     ru "  popUpWindow",
                     ru "    foreground                   gray100",
                     ru "    background                   black",
                     ru "",
                     ru "  popUpWinCurrentLine",
                     ru "    foreground                   blue",
                     ru "    background                   black",
                     ru "",
                     ru "  replaceText",
                     ru "    foreground                   default",
                     ru "    background                   red",
                     ru "",
                     ru "  parenText",
                     ru "    foreground                   default",
                     ru "    background                   white",
                     ru "",
                     ru "  currentWord",
                     ru "    foreground                   default",
                     ru "    background                   white",
                     ru "",
                     ru "  highlightFullWidthSpace",
                     ru "    foreground                   default",
                     ru "    background                   white",
                     ru "",
                     ru "  highlightTrailingSpaces",
                     ru "    foreground                   red",
                     ru "    background                   red",
                     ru "",
                     ru "  workSpaceBar",
                     ru "    foreground                   white",
                     ru "    background                   blue",
                     ru "",
                     ru "  reservedWord",
                     ru "    foreground                   white",
                     ru "    background                   gray",
                     ru "",
                     ru "  currentSetting",
                     ru "    foreground                   gray100",
                     ru "    background                   teal",
                     ru ""]

    for index, line in buffer:
      check sample[index] == line

proc checkBoolSettingValue(default: bool, values: seq[seq[Rune]]) =
  if default:
    check values == @[ru "true", ru "false"]
  else:
    check values == @[ru "false", ru "true"]

suite "Config mode: Get standard table setting values":
  test "Get theme values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "theme"
    let values = settings.getStandardTableSettingValues(name)

    check values == @[ru "dark", ru "config", ru "vscode", ru "light", ru "vivid"]

  test "Get defaultCursor values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "defaultCursor"
    let values = settings.getStandardTableSettingValues(name)

    check values == @[ru "blinkBlock", ru "noneBlinkBlock", ru "blinkIbeam",
                      ru "noneBlinkIbeam"]

  test "Get normalModeCursor values":
    var status = initEditorStatus()
    let settings = status.settings

    const name ="normalModeCursor"
    let values = settings.getStandardTableSettingValues(name)

    check values == @[ru "blinkBlock", ru "noneBlinkBlock", ru "blinkIbeam",
                      ru "noneBlinkIbeam"]

  test "Get insertModeCursor values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "insertModeCursor"
    let values = settings.getStandardTableSettingValues(name)

    check values == @[ru "blinkIbeam", ru "blinkBlock", ru "noneBlinkBlock",
                      ru "noneBlinkIbeam"]

  test "Get number values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "number"
    let
      default = settings.view.lineNumber
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get currentNumber values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "currentNumber"
    let
      default = settings.view.currentLineNumber
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get cursorLine values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "cursorLine"
    let
      default = settings.view.cursorLine
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get statusLine values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "statusLine"
    let
      default = settings.statusLine.enable
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get tabLine values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "tabLine"
    let
      default = settings.tabLine.useTab
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get syntax values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "syntax"
    let
      default = settings.syntax
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get indentationLines values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "indentationLines"
    let
      default = settings.view.indentationLines
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get autoCloseParen values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "autoCloseParen"
    let
      default = settings.autoCloseParen
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get autoIndent values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "autoIndent"
    let
      default = settings.autoIndent
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get ignorecase values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "ignorecase"
    let
      default = settings.ignorecase
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get smartcase values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "smartcase"
    let
      default = settings.smartcase
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get disableChangeCursor values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "disableChangeCursor"
    let
      default = settings.disableChangeCursor
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get autoSave values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "autoSave"
    let
      default = settings.autoSave
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get liveReloadOfConfvalues":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "liveReloadOfConf"
    let
      default = settings.liveReloadOfConf
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get incrementalSearch values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "incrementalSearch"
    let
      default = settings.incrementalSearch
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get popUpWindowInExmode values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "popUpWindowInExmode"
    let
      default = settings.popUpWindowInExmode
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get autoDeleteParen values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "autoDeleteParen"
    let
      default = settings.autoDeleteParen
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get systemClipboard values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "systemClipboard"
    let
      default = settings.systemClipboard
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get smoothScroll values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "smoothScroll"
    let
      default = settings.smoothScroll
      values = settings.getStandardTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Set invalid name":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "test"
    let values = settings.getStandardTableSettingValues(name)

    check values.len == 0

suite "Config mode: Get BuildOnSave table setting values":
  test "Get enable values":
    var status = initEditorStatus()
    let buildOnSaveSettings = status.settings.buildOnSave

    const name = "enable"
    let
      default = buildOnSaveSettings.enable
      values = buildOnSaveSettings.getBuildOnSaveTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Set invalid name":
    var status = initEditorStatus()
    let buildOnSaveSettings = status.settings.buildOnSave

    const name = "test"
    let values = buildOnSaveSettings.getBuildOnSaveTableSettingValues(name)

    check values.len == 0

suite "Config mode: Get TabLine table setting values":
  test "Get allBuffer values":
    var status = initEditorStatus()
    let tablineSettings = status.settings.tabLine

    const name = "allBuffer"
    let
      default = tablineSettings.allBuffer
      values = tablineSettings.getTabLineTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Set invalid name":
    var status = initEditorStatus()
    let tablineSettings = status.settings.tabLine

    const name = "test"
    let values = tablineSettings.getTabLineTableSettingValues(name)

    check values.len == 0

suite "Config mode: Get StatusLine table setting values":
  test "Get multipleStatusLine values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const name = "multipleStatusLine"
    let
      default = statusLineSettings.multipleStatusLine
      values = statusLineSettings.getStatusLineTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get merge values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const name = "merge"
    let
      default = statusLineSettings.merge
      values = statusLineSettings.getStatusLineTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get mode values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const name = "mode"
    let
      default = statusLineSettings.mode
      values = statusLineSettings.getStatusLineTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get filename values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const name = "filename"
    let
      default = statusLineSettings.filename
      values = statusLineSettings.getStatusLineTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get chanedMark values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const name = "chanedMark"
    let
      default = statusLineSettings.chanedMark
      values = statusLineSettings.getStatusLineTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get line values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const name = "line"
    let
      default = statusLineSettings.line
      values = statusLineSettings.getStatusLineTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get column values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const name = "column"
    let
      default = statusLineSettings.column
      values = statusLineSettings.getStatusLineTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get encoding values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const name = "encoding"
    let
      default = statusLineSettings.characterEncoding
      values = statusLineSettings.getStatusLineTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get language values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const name = "language"
    let
      default = statusLineSettings.language
      values = statusLineSettings.getStatusLineTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get directory values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const name = "directory"
    let
      default = statusLineSettings.directory
      values = statusLineSettings.getStatusLineTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get gitbranchName values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const name = "gitbranchName"
    let
      default = statusLineSettings.gitbranchName
      values = statusLineSettings.getStatusLineTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get showGitInactive values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const name = "showGitInactive"
    let
      default = statusLineSettings.showGitInactive
      values = statusLineSettings.getStatusLineTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get showModeInactive values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const name = "showModeInactive"
    let
      default = statusLineSettings.showModeInactive
      values = statusLineSettings.getStatusLineTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Set invalid name":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const name = "test"
    let values = statusLineSettings.getStatusLineTableSettingValues(name)

    check values.len == 0

suite "Config mode: Get WorkSpace table setting values":
  test "Get workSpaceLine values":
    var status = initEditorStatus()
    let workSpaceSettings = status.settings.workSpace

    const name = "workSpaceLine"
    let
      default = workSpaceSettings.workSpaceLine
      values = workSpaceSettings.getWorkSpaceTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Set invalid name":
    var status = initEditorStatus()
    let workSpaceSettings = status.settings.workSpace

    const name = "test"
    let values = workSpaceSettings.getWorkSpaceTableSettingValues(name)

    check values.len == 0

suite "Config mode: Get Highlight table setting values":
  test "Get currentLine values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "currentLine"
    let
      default = settings.view.highlightCurrentLine
      values = settings.getHighlightTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get fullWidthSpace values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "fullWidthSpace"
    let
      default = settings.highlightSettings.fullWidthSpace
      values = settings.getHighlightTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get trailingSpaces values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "trailingSpaces"
    let
      default = settings.highlightSettings.trailingSpaces
      values = settings.getHighlightTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get currentWord values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "currentWord"
    let
      default = settings.highlightSettings.currentWord
      values = settings.getHighlightTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get replaceText values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "replaceText"
    let
      default = settings.highlightSettings.replaceText
      values = settings.getHighlightTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get pairOfParen values":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "pairOfParen"
    let
      default = settings.highlightSettings.pairOfParen
      values = settings.getHighlightTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Set invalid name":
    var status = initEditorStatus()
    let settings = status.settings

    const name = "test"
    let values = settings.getHighlightTableSettingValues(name)

    check values.len == 0

suite "Config mode: Get AutoBackup table setting values":
  test "Get enable values":
    var status = initEditorStatus()
    let autoBackupSettings = status.settings.autoBackupSettings

    const name = "enable"
    let
      default = autoBackupSettings.enable
      values = autoBackupSettings.getAutoBackupTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Set invalid name":
    var status = initEditorStatus()
    let autoBackupSettings = status.settings.autoBackupSettings

    const name = "test"
    let values = autoBackupSettings.getAutoBackupTableSettingValues(name)

    check values.len == 0

suite "Config mode: Get QuickRun table setting values":
  test "Get saveBufferWhenQuickRun values":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRunSettings

    const name = "saveBufferWhenQuickRun"
    let
      default = quickRunSettings.saveBufferWhenQuickRun
      values = quickRunSettings.getQuickRunTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Set invalid name":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRunSettings

    const name = "test"
    let values = quickRunSettings.getQuickRunTableSettingValues(name)

    check values.len == 0

suite "Config mode: Get Notification table setting values":
  test "Get screenNotifications values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "screenNotifications"
    let
      default = notificationSettings.screenNotifications
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get logNotifications values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "logNotifications"
    let
      default = notificationSettings.logNotifications
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get autoBackupScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "autoBackupScreenNotify"
    let
      default = notificationSettings.autoBackupScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get autoBackupLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "autoBackupLogNotify"
    let
      default = notificationSettings.autoBackupLogNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get autoSaveScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "autoSaveScreenNotify"
    let
      default = notificationSettings.autoSaveScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get autoSaveLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "autoSaveLogNotify"
    let
      default = notificationSettings.autoSaveLogNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get yankScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "yankScreenNotify"
    let
      default = notificationSettings.yankScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get yankLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "yankLogNotify"
    let
      default = notificationSettings.yankLogNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get deleteScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "deleteScreenNotify"
    let
      default = notificationSettings.deleteScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get deleteLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "deleteLogNotify"
    let
      default = notificationSettings.deleteLogNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get saveScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "saveScreenNotify"
    let
      default = notificationSettings.saveScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get saveLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "saveLogNotify"
    let
      default = notificationSettings.saveLogNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get workspaceScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "workspaceScreenNotify"
    let
      default = notificationSettings.workspaceScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get workspaceLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "workspaceLogNotify"
    let
      default = notificationSettings.workspaceLogNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get quickRunScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "quickRunScreenNotify"
    let
      default = notificationSettings.quickRunScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get quickRunLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "quickRunLogNotify"
    let
      default = notificationSettings.quickRunLogNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get buildOnSaveScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "buildOnSaveScreenNotify"
    let
      default = notificationSettings.buildOnSaveScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "buildOnSaveLogNotify"
    let
      default = notificationSettings.buildOnSaveLogNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get filerScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "filerScreenNotify"
    let
      default = notificationSettings.filerScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get filerLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "filerLogNotify"
    let
      default = notificationSettings.filerLogNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get restoreScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "restoreScreenNotify"
    let
      default = notificationSettings.restoreScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get restoreLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "restoreLogNotify"
    let
      default = notificationSettings.restoreLogNotify
      values = notificationSettings.getNotificationTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Set invalid name":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notificationSettings

    const name = "test"
    let values = notificationSettings.getNotificationTableSettingValues(name)

    check values.len == 0

suite "Config mode: Get Filer table setting values":
  test "Get showIcons values":
    var status = initEditorStatus()
    let filerSettings = status.settings.filerSettings

    const name = "showIcons"
    let
      default = filerSettings.showIcons
      values = filerSettings.getFilerTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Set invalid name":
    var status = initEditorStatus()
    let filerSettings = status.settings.filerSettings

    const name = "test"
    let values = filerSettings.getFilerTableSettingValues(name)

    check values.len == 0

suite "Config mode: Get Autocomplete table setting values":
  test "Get enable values":
    var status = initEditorStatus()
    let autocompleteSettings = status.settings.autocompleteSettings

    const name = "enable"
    let
      default = autocompleteSettings.enable
      values = autocompleteSettings.getAutocompleteTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Set invalid name":
    var status = initEditorStatus()
    let autocompleteSettings = status.settings.autocompleteSettings

    const name = "test"
    let values = autocompleteSettings.getAutocompleteTableSettingValues(name)

    check values.len == 0

suite "Config mode: Get Theme table setting values":
  # Generate test code
  macro checkColorValues(colorPair: EditorColorPair,
                         position: string): untyped =

    quote do:
      let testTitle = "Get " & $`colorPair` & "." & $`position`  & " values"
      test testTitle:
        let
          (fg, bg) = getColorFromEditorColorPair(theme, `colorPair`)
          values = settings.getThemeTableSettingValues($`colorPair`, $`position`)
          # values[0] should be current setting
          default = $values[0]

        if $`position` == "foreground":
          check default == $fg
        else:
          check default == $bg

        let colorLen = int(Color.high)
        var index = 0
        for c in Color:
          if index < colorLen and $c != default:
            inc(index)
            check $values[index] == $c

  let
    status = initEditorStatus()
    settings = status.settings
    theme = settings.editorColorTheme

  # Check Theme.editorBg
  test "Get editorBg.background values":
    let
      bg = ColorThemeTable[theme].editorBg
      values = settings.getThemeTableSettingValues("editorBg", "background")
      # values[0] should be current setting
      default = $values[0]

    check default == $bg

    let colorLen = int(Color.high)
    var index = 0
    for c in Color:
      if index < colorLen and $c != default:
        inc(index)
        check $values[index] == $c

  # Check other than Theme.editorBg by checkColorValues macro
  for pair in EditorColorPair:
    checkColorValues(pair, "foreground")
    checkColorValues(pair, "background")
