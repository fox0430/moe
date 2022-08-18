import std/[unittest, macros, strformat]
import moepkg/[editorstatus, gapbuffer, bufferstatus, unicodeext]

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
                     ru "  autoDeleteParen                false",
                     ru "  smoothScroll                   true",
                     ru "  smoothScrollSpeed              15"]

    for index, line in buffer:
      check sample[index] == line

  test "Init ClipBoard table buffer":
    var status = initEditorStatus()
    status.settings.clipboard.enable = true
    status.settings.clipboard.toolOnLinux = ClipboardToolOnLinux.none
    let buffer = status.settings.clipboard.initClipBoardTableBuffer

    const sample = @[ru "ClipBoard",
                     ru "  enable                         true",
                     ru "  toolOnLinux                    none"]

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

  test "Init highlight table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.initHighlightTableBuffer

    const sample = @[ru "Highlight",
                     ru "  currentLine                    true",
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

  test "Init Autocomplete table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.initAutocompleteTableBuffer

    const sample = @[ru "Autocomplete",
                     ru "  enable                         true"]

    for index, line in buffer:
      check sample[index] == line

  test "Init Persist table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.persist.initPersistTableBuffer

    const sample = @[ru "Persist",
                     ru "  exCommand                      true",
                     ru "  search                         true",
                     ru "  cursorPosition                 true"]

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
                     ru "  typeName",
                     ru "    foreground                   green",
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
                     ru "  pragma",
                     ru "    foreground                   yellow",
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
                     ru "    background                   blue",
                     ru "",
                     ru "  currentWord",
                     ru "    foreground                   default",
                     ru "    background                   gray",
                     ru "",
                     ru "  highlightFullWidthSpace",
                     ru "    foreground                   red",
                     ru "    background                   red",
                     ru "",
                     ru "  highlightTrailingSpaces",
                     ru "    foreground                   red",
                     ru "    background                   red",
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

# TODO: Should return bool.
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
      default = settings.tabLine.enable
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

suite "Config mode: Get ClipBoard table setting values":
  test "Get enable value":
    var status = initEditorStatus()
    let clipboardSettings = status.settings.clipboard

    const name = "enable"
    let
      default = clipboardSettings.enable
      values = clipboardSettings.getClipboardTableSettingsValues(name)

    checkBoolSettingValue(default, values)

  test "Get toolOnLinux value":
    var status = initEditorStatus()
    status.settings.clipboard.toolOnLinux = ClipboardToolOnLinux.none
    let clipboardSettings = status.settings.clipboard

    const name = "toolOnLinux"
    let
      default = clipboardSettings.toolOnLinux
      values = clipboardSettings.getClipboardTableSettingsValues(name)

    check $default == $values[0]

suite "Config mode: Get BuildOnSave table setting values":
  test "Get enable values":
    var status = initEditorStatus()
    let buildOnSaveSettings = status.settings.buildOnSave

    const name = "enable"
    let
      default = buildOnSaveSettings.enable
      values = buildOnSaveSettings.getBuildOnSaveTableSettingValues(name)

    checkBoolSettingValue(default, values)

  test "Get workspaceRoot values":
    var status = initEditorStatus()
    let buildOnSaveSettings = status.settings.buildOnSave

    const name = "workspaceRoot"
    let
      default = buildOnSaveSettings.workspaceRoot
      values = buildOnSaveSettings.getBuildOnSaveTableSettingValues(name)

    check default == values[0]

  test "Get command values":
    var status = initEditorStatus()
    let buildOnSaveSettings = status.settings.buildOnSave

    const name = "command"
    let
      default = buildOnSaveSettings.command
      values = buildOnSaveSettings.getBuildOnSaveTableSettingValues(name)

    check default == values[0]

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

    const
      name = "enable"
      settingType = SettingType.Bool
    let
      default = autoBackupSettings.enable
      values = autoBackupSettings.getAutoBackupTableSettingValues(
        name,
        settingType)

    checkBoolSettingValue(default, values)

  test "Get backupDir values":
    var status = initEditorStatus()
    let autoBackupSettings = status.settings.autoBackupSettings

    const
      name = "backupDir"
      settingType = SettingType.String
    let
      default = autoBackupSettings.backupDir
      values = autoBackupSettings.getAutoBackupTableSettingValues(
        name,
        settingType)

    check default == values[0]

  test "Set invalid name":
    var status = initEditorStatus()
    let autoBackupSettings = status.settings.autoBackupSettings

    const
      name = "test"
      settingType = SettingType.None
    let values = autoBackupSettings.getAutoBackupTableSettingValues(
      name,
      settingType)

    check values.len == 0

suite "Config mode: Get QuickRun table setting values":
  test "Get saveBufferWhenQuickRun values":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRunSettings

    const
      name = "saveBufferWhenQuickRun"
      settingType = SettingType.Bool
    let
      default = quickRunSettings.saveBufferWhenQuickRun
      values = quickRunSettings.getQuickRunTableSettingValues(name, settingType)

    checkBoolSettingValue(default, values)

  test "Get nimAdvancedCommandvalues":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRunSettings

    const
      name = "nimAdvancedCommand"
      settingType = SettingType.String
    let
      default = ru quickRunSettings.nimAdvancedCommand
      values = quickRunSettings.getQuickRunTableSettingValues(name, settingType)

    check default == values[0]

  test "Get ClangOptions values":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRunSettings

    const
      name = "ClangOptions"
      settingType = SettingType.String
    let
      default = ru quickRunSettings.ClangOptions
      values = quickRunSettings.getQuickRunTableSettingValues(name, settingType)

    check default == values[0]

  test "Get CppOptions values":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRunSettings

    const
      name = "CppOptions"
      settingType = SettingType.String
    let
      default = ru quickRunSettings.CppOptions
      values = quickRunSettings.getQuickRunTableSettingValues(name, settingType)

    check default == values[0]

  test "Get NimOptions values":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRunSettings

    const
      name = "NimOptions"
      settingType = SettingType.String
    let
      default = ru quickRunSettings.NimOptions
      values = quickRunSettings.getQuickRunTableSettingValues(name, settingType)

    check default == values[0]

  test "Get shOptions values":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRunSettings

    const
      name = "shOptions"
      settingType = SettingType.String
    let
      default = ru quickRunSettings.shOptions
      values = quickRunSettings.getQuickRunTableSettingValues(name, settingType)

    check default == values[0]

  test "Get bashOptions values":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRunSettings

    const
      name = "bashOptions"
      settingType = SettingType.String
    let
      default = ru quickRunSettings.bashOptions
      values = quickRunSettings.getQuickRunTableSettingValues(name, settingType)

    check default == values[0]

  test "Set invalid name":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRunSettings

    const
      name = "test"
      settingType = SettingType.None
    let values = quickRunSettings.getQuickRunTableSettingValues(name, settingType)

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

suite "Config mode: Get Persist table setting values":
  test "Get exCommand values":
    var status = initEditorStatus()
    let persistSettings = status.settings.persist

    const name = "exCommand"
    let
      default = persistSettings.exCommand
      values = persistSettings.getPersistTableSettingsValues(name)

    checkBoolSettingValue(default, values)

  test "Get search values":
    var status = initEditorStatus()
    let persistSettings = status.settings.persist

    const name = "search"
    let
      default = persistSettings.exCommand
      values = persistSettings.getPersistTableSettingsValues(name)

    checkBoolSettingValue(default, values)

  test "Get cursorPosition values":
    var status = initEditorStatus()
    let persistSettings = status.settings.persist

    const name = "search"
    let
      default = persistSettings.cursorPosition
      values = persistSettings.getPersistTableSettingsValues(name)

    checkBoolSettingValue(default, values)

  test "Set invalid name":
    var status = initEditorStatus()
    let persistSettings = status.settings.persist

    const name = "test"
    let values = persistSettings.getPersistTableSettingsValues(name)

    check values.len == 0

suite "Config mode: Get Theme table setting values":
  # Generate test code
  macro checkColorValues(colorPair: EditorColorPair,
                         position: string): untyped =

    quote do:
      let testTitle = "Get " & $`colorPair` & "." & $`position`  & " values"
      test testTitle:
        let
          theme = settings.editorColorTheme
          (fg, bg) = theme.getColorFromEditorColorPair(`colorPair`)
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

  # Check Theme.editorBg
  test "Get editorBg.background values":
    let
      theme = settings.editorColorTheme
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

suite "Config mode: Chaging Standard table settings":
  test "Chaging theme":
    var settings = initEditorSettings()
    settings.changeStandardTableSetting("theme", "vivid")

    check settings.editorColorTheme == ColorTheme.vivid

  test "Chaging number":
    var settings = initEditorSettings()

    let val = not settings.view.lineNumber
    settings.changeStandardTableSetting("number", $val)

    check val == settings.view.lineNumber

  test "Chaging currentNumber":
    var settings = initEditorSettings()

    let val = not settings.view.currentLineNumber
    settings.changeStandardTableSetting("currentNumber", $val)

    check val == settings.view.currentLineNumber

  test "Chaging cursorLine":
    var settings = initEditorSettings()

    let val = not settings.view.cursorLine
    settings.changeStandardTableSetting("cursorLine", $val)

    check val == settings.view.cursorLine

  test "Chaging statusLine":
    var settings = initEditorSettings()

    let val = not settings.statusLine.enable
    settings.changeStandardTableSetting("statusLine", $val)

    check val == settings.statusLine.enable

  test "Chaging tabLine":
    var settings = initEditorSettings()

    let val = not settings.tabLine.enable
    settings.changeStandardTableSetting("tabLine", $val)

    check val == settings.tabLine.enable

  test "Chaging syntax":
    var settings = initEditorSettings()

    let val = not settings.syntax
    settings.changeStandardTableSetting("syntax", $val)

    check val == settings.syntax

  test "Chaging indentationLines":
    var settings = initEditorSettings()

    let val = not settings.view.indentationLines
    settings.changeStandardTableSetting("indentationLines", $val)

    check val == settings.view.indentationLines

  test "Chaging autoCloseParen":
    var settings = initEditorSettings()

    let val = not settings.autoCloseParen
    settings.changeStandardTableSetting("autoCloseParen", $val)

    check val == settings.autoCloseParen

  test "Chaging autoIndent":
    var settings = initEditorSettings()

    let val = not settings.autoIndent
    settings.changeStandardTableSetting("autoIndent", $val)

    check val == settings.autoIndent

  test "Chaging ignorecase":
    var settings = initEditorSettings()

    let val = not settings.ignorecase
    settings.changeStandardTableSetting("ignorecase", $val)

    check val == settings.ignorecase

  test "Chaging smartcase":
    var settings = initEditorSettings()

    let val = not settings.smartcase
    settings.changeStandardTableSetting("smartcase", $val)

    check val == settings.smartcase

  test "Chaging disableChangeCursor":
    var settings = initEditorSettings()

    let val = not settings.disableChangeCursor
    settings.changeStandardTableSetting("disableChangeCursor", $val)

    check val == settings.disableChangeCursor

  test "Chaging defaultCursor":
    var settings = initEditorSettings()

    let val = "noneBlinkIbeam"
    settings.changeStandardTableSetting("defaultCursor", val)

    check CursorType.noneBlinkIbeam == settings.defaultCursor

  test "Chaging normalModeCursor":
    var settings = initEditorSettings()

    let val = "noneBlinkIbeam"
    settings.changeStandardTableSetting("normalModeCursor", val)

    check CursorType.noneBlinkIbeam == settings.normalModeCursor

  test "Chaging insertModeCursor":
    var settings = initEditorSettings()

    let val = "noneBlinkIbeam"
    settings.changeStandardTableSetting("insertModeCursor", val)

    check CursorType.noneBlinkIbeam == settings.insertModeCursor

  test "Chaging autoSave":
    var settings = initEditorSettings()

    let val = not settings.autoSave
    settings.changeStandardTableSetting("autoSave", $val)

    check val == settings.autoSave

  test "Chaging liveReloadOfConf":
    var settings = initEditorSettings()

    let val = not settings.liveReloadOfConf
    settings.changeStandardTableSetting("liveReloadOfConf", $val)

    check val == settings.liveReloadOfConf

  test "Chaging incrementalSearch":
    var settings = initEditorSettings()

    let val = not settings.incrementalSearch
    settings.changeStandardTableSetting("incrementalSearch", $val)

    check val == settings.incrementalSearch

  test "Chaging popUpWindowInExmode":
    var settings = initEditorSettings()

    let val = not settings.popUpWindowInExmode
    settings.changeStandardTableSetting("popUpWindowInExmode", $val)

    check val == settings.popUpWindowInExmode

  test "Chaging autoDeleteParen":
    var settings = initEditorSettings()

    let val = not settings.autoDeleteParen
    settings.changeStandardTableSetting("autoDeleteParen", $val)

    check val == settings.autoDeleteParen

  test "Chaging smoothScroll":
    var settings = initEditorSettings()

    let val = not settings.smoothScroll
    settings.changeStandardTableSetting("smoothScroll", $val)

    check val == settings.smoothScroll

  test "Set invalid value":
    var settings = initEditorSettings()

    let beforeSettings = settings
    settings.changeStandardTableSetting("test", "test")

    check beforeSettings == settings

suite "Config mode: Chaging ClipBoard table settings":
  test "Chaging enable":
    var
      settings = initEditorSettings()
      clipboardSettings = settings.clipboard

    let val = not clipboardSettings.enable
    clipboardSettings.changeClipBoardTableSettings("enable", $val)

    check val == clipboardSettings.enable

  test "Change toolOnLinux":
    var
      settings = initEditorSettings()
      clipboardSettings = settings.clipboard

    let val = ClipboardToolOnLinux.xclip
    clipboardSettings.changeClipBoardTableSettings("toolOnLinux", $val)

    check val == clipboardSettings.toolOnLinux

  test "Set invalid value":
    var
      settings = initEditorSettings()
      clipboardSettings = settings.clipboard

    let beforeSettings = clipboardSettings
    clipboardSettings.changeClipBoardTableSettings("test", "test")

    check beforeSettings == clipboardSettings

suite "Config mode: Chaging BuildOnSave table settings":
  test "Chaging enable":
    var
      settings = initEditorSettings()
      buildOnSaveSettings = settings.buildOnSave

    let val = not buildOnSaveSettings.enable
    buildOnSaveSettings.changeBuildOnSaveTableSetting("enable", $val)

    check val == buildOnSaveSettings.enable

  test "Set invalid value":
    var
      settings = initEditorSettings()
      buildOnSaveSettings = settings.buildOnSave

    let beforeSettings = buildOnSaveSettings
    buildOnSaveSettings.changeBuildOnSaveTableSetting("test", "test")

    check beforeSettings == buildOnSaveSettings

suite "Config mode: Chaging TabLine table settings":
  test "Chaging allBuffer":

    var
      settings = initEditorSettings()
      tablineSettings = settings.tabline

    let val = not tablineSettings.allBuffer
    tablineSettings.changeTabLineTableSetting("allBuffer", $val)

    check val == tablineSettings.allBuffer

  test "Set invalid value":
    var
      settings = initEditorSettings()
      tablineSettings = settings.tabline

    let beforeSettings = tablineSettings
    tablineSettings.changeTabLineTableSetting("test", "test")

    check beforeSettings == tablineSettings

suite "Config mode: Chaging StatusLine table settings":
  test "Chaging ":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let val = not statusLineSettings.multipleStatusLine
    statusLineSettings.changeStatusLineTableSetting("multipleStatusLine", $val)

    check val == statusLineSettings.multipleStatusLine

  test "Chaging merge":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let val = not statusLineSettings.merge
    statusLineSettings.changeStatusLineTableSetting("merge", $val)

    check val == statusLineSettings.merge

  test "Chaging mode":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let val = not statusLineSettings.mode
    statusLineSettings.changeStatusLineTableSetting("mode", $val)

    check val == statusLineSettings.mode

  test "Chaging filename":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let val = not statusLineSettings.filename
    statusLineSettings.changeStatusLineTableSetting("filename", $val)

    check val == statusLineSettings.filename

  test "Chaging chanedMark":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let val = not statusLineSettings.chanedMark
    statusLineSettings.changeStatusLineTableSetting("chanedMark", $val)

    check val == statusLineSettings.chanedMark

  test "Chaging line":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let val = not statusLineSettings.line
    statusLineSettings.changeStatusLineTableSetting("line", $val)

    check val == statusLineSettings.line

  test "Chaging column":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let val = not statusLineSettings.column
    statusLineSettings.changeStatusLineTableSetting("column", $val)

    check val == statusLineSettings.column

  test "Chaging encoding":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let val = not statusLineSettings.characterEncoding
    statusLineSettings.changeStatusLineTableSetting("encoding", $val)

    check val == statusLineSettings.characterEncoding

  test "Chaging language":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let val = not statusLineSettings.language
    statusLineSettings.changeStatusLineTableSetting("language", $val)

    check val == statusLineSettings.language

  test "Chaging directory":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let val = not statusLineSettings.directory
    statusLineSettings.changeStatusLineTableSetting("directory", $val)

    check val == statusLineSettings.directory

  test "Chaging gitbranchName":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let val = not statusLineSettings.gitbranchName
    statusLineSettings.changeStatusLineTableSetting("gitbranchName", $val)

    check val == statusLineSettings.gitbranchName

  test "Chaging showGitInactive":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let val = not statusLineSettings.showGitInactive
    statusLineSettings.changeStatusLineTableSetting("showGitInactive", $val)

    check val == statusLineSettings.showGitInactive

  test "Chaging showModeInactive":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let val = not statusLineSettings.showModeInactive
    statusLineSettings.changeStatusLineTableSetting("showModeInactive", $val)

    check val == statusLineSettings.showModeInactive

  test "Set invalid value":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let beforeSettings = statusLineSettings
    statusLineSettings.changeStatusLineTableSetting("test", "test")

    check beforeSettings == statusLineSettings

suite "Config mode: Chaging Highlight table settings":
  test "Chaging currentLine":
    var settings = initEditorSettings()

    let val = not settings.view.highlightCurrentLine
    settings.changeHighlightTableSetting("currentLine", $val)

    check val == settings.view.highlightCurrentLine

  test "Chaging fullWidthSpace":
    var settings = initEditorSettings()

    let val = not settings.highlightSettings.fullWidthSpace
    settings.changeHighlightTableSetting("fullWidthSpace", $val)

    check val == settings.highlightSettings.fullWidthSpace

  test "Chaging trailingSpaces":
    var settings = initEditorSettings()

    let val = not settings.highlightSettings.trailingSpaces
    settings.changeHighlightTableSetting("trailingSpaces", $val)

    check val == settings.highlightSettings.trailingSpaces

  test "Chaging replaceText":
    var settings = initEditorSettings()

    let val = not settings.highlightSettings.replaceText
    settings.changeHighlightTableSetting("replaceText", $val)

    check val == settings.highlightSettings.replaceText

  test "Chaging pairOfParen":
    var settings = initEditorSettings()

    let val = not settings.highlightSettings.pairOfParen
    settings.changeHighlightTableSetting("pairOfParen", $val)

    check val == settings.highlightSettings.pairOfParen

  test "Chaging currentWord":
    var settings = initEditorSettings()

    let val = not settings.highlightSettings.currentWord
    settings.changeHighlightTableSetting("currentWord", $val)

    check val == settings.highlightSettings.currentWord

  test "Set invalid value":
    var settings = initEditorSettings()

    let beforeSettings = settings
    settings.changeHighlightTableSetting("test", "test")

    check beforeSettings == settings

suite "Config mode: Chaging AutoBackup table settings":
  test "Chaging enable":
    var
      settings = initEditorSettings()
      autoBackupSettings = settings.autoBackupSettings

    let val = not autoBackupSettings.enable
    autoBackupSettings.changeBackupTableSetting("enable", $val)

    check val == autoBackupSettings.enable

  test "Set invalid value":
    var
      settings = initEditorSettings()
      autoBackupSettings = settings.autoBackupSettings

    let beforeSettings = autoBackupSettings
    autoBackupSettings.changeBackupTableSetting("test", "test")

    check beforeSettings == autoBackupSettings

suite "Config mode: Chaging QuickRun table settings":
  test "Chaging saveBufferWhenQuickRun":
    var
      settings = initEditorSettings()
      quickRunSettings = settings.quickRunSettings

    let val = not quickRunSettings.saveBufferWhenQuickRun
    quickRunSettings.changeQuickRunTableSetting("saveBufferWhenQuickRun", $val)

    check val == quickRunSettings.saveBufferWhenQuickRun

  test "Set invalid value":
    var
      settings = initEditorSettings()
      quickRunSettings = settings.quickRunSettings

    let beforeSettings = quickRunSettings
    quickRunSettings.changeQuickRunTableSetting("test", "test")

    check beforeSettings == quickRunSettings

suite "Config mode: Chaging Notification table settings":
  test "Chaging screenNotifications":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.screenNotifications
    notificationSettings.changeNotificationTableSetting("screenNotifications", $val)

    check val == notificationSettings.screenNotifications

  test "Chaging logNotifications":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.logNotifications
    notificationSettings.changeNotificationTableSetting("logNotifications", $val)

    check val == notificationSettings.logNotifications

  test "Chaging autoBackupScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.autoBackupScreenNotify
    notificationSettings.changeNotificationTableSetting("autoBackupScreenNotify", $val)

    check val == notificationSettings.autoBackupScreenNotify

  test "Chaging autoBackupLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.autoBackupLogNotify
    notificationSettings.changeNotificationTableSetting("autoBackupLogNotify", $val)

    check val == notificationSettings.autoBackupLogNotify

  test "Chaging autoSaveScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.autoSaveScreenNotify
    notificationSettings.changeNotificationTableSetting("autoSaveScreenNotify", $val)

    check val == notificationSettings.autoSaveScreenNotify

  test "Chaging autoSaveLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.autoSaveLogNotify
    notificationSettings.changeNotificationTableSetting("autoSaveLogNotify", $val)

    check val == notificationSettings.autoSaveLogNotify

  test "Chaging yankScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.yankScreenNotify
    notificationSettings.changeNotificationTableSetting("yankScreenNotify", $val)

    check val == notificationSettings.yankScreenNotify

  test "Chaging yankLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.yankLogNotify
    notificationSettings.changeNotificationTableSetting("yankLogNotify", $val)

    check val == notificationSettings.yankLogNotify

  test "Chaging deleteScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.deleteScreenNotify
    notificationSettings.changeNotificationTableSetting("deleteScreenNotify", $val)

    check val == notificationSettings.deleteScreenNotify

  test "Chaging deleteLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.deleteLogNotify
    notificationSettings.changeNotificationTableSetting("deleteLogNotify", $val)

    check val == notificationSettings.deleteLogNotify

  test "Chaging saveScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.saveScreenNotify
    notificationSettings.changeNotificationTableSetting("saveScreenNotify", $val)

    check val == notificationSettings.saveScreenNotify

  test "Chaging saveLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.saveLogNotify
    notificationSettings.changeNotificationTableSetting("saveLogNotify", $val)

    check val == notificationSettings.saveLogNotify

  test "Chaging quickRunScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.quickRunScreenNotify
    notificationSettings.changeNotificationTableSetting("quickRunScreenNotify", $val)

    check val == notificationSettings.quickRunScreenNotify

  test "Chaging quickRunLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.quickRunLogNotify
    notificationSettings.changeNotificationTableSetting("quickRunLogNotify", $val)

    check val == notificationSettings.quickRunLogNotify

  test "Chaging buildOnSaveScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.buildOnSaveScreenNotify
    notificationSettings.changeNotificationTableSetting("buildOnSaveScreenNotify", $val)

    check val == notificationSettings.buildOnSaveScreenNotify

  test "Chaging buildOnSaveLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.buildOnSaveLogNotify
    notificationSettings.changeNotificationTableSetting("buildOnSaveLogNotify", $val)

    check val == notificationSettings.buildOnSaveLogNotify

  test "Chaging filerScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.filerScreenNotify
    notificationSettings.changeNotificationTableSetting("filerScreenNotify", $val)

    check val == notificationSettings.filerScreenNotify

  test "Chaging filerLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.filerLogNotify
    notificationSettings.changeNotificationTableSetting("filerLogNotify", $val)

    check val == notificationSettings.filerLogNotify

  test "Chaging restoreScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.restoreScreenNotify
    notificationSettings.changeNotificationTableSetting("restoreScreenNotify", $val)

    check val == notificationSettings.restoreScreenNotify

  test "Chaging restoreLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let val = not notificationSettings.restoreLogNotify
    notificationSettings.changeNotificationTableSetting("restoreLogNotify", $val)

    check val == notificationSettings.restoreLogNotify

  test "Set invalid value":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notificationSettings

    let beforeSettings = notificationSettings
    notificationSettings.changeNotificationTableSetting("test", "test")

    check beforeSettings == notificationSettings

suite "Config mode: Chaging Filer table settings":
  test "Chaging showIcons":
    var
      settings = initEditorSettings()
      filerSettings = settings.filerSettings

    let val = not filerSettings.showIcons
    filerSettings.changeFilerTableSetting("showIcons", $val)

    check val == filerSettings.showIcons

  test "Set invalid value":
    var
      settings = initEditorSettings()
      filerSettings = settings.filerSettings

    let beforeSettings = filerSettings
    filerSettings.changeFilerTableSetting("test", "test")

    check beforeSettings == filerSettings

suite "Config mode: Chaging Autocomplete table settings":
  test "Chaging enable":
    var
      settings = initEditorSettings()
      autocompleteSettings = settings.autocompleteSettings

    let val = not autocompleteSettings.enable
    autocompleteSettings.changeAutoCompleteTableSetting("enable", $val)

    check val == autocompleteSettings.enable

  test "Set invalid value":
    var
      settings = initEditorSettings()
      autocompleteSettings = settings.autocompleteSettings

    let beforeSettings = autocompleteSettings
    autocompleteSettings.changeAutoCompleteTableSetting("test", "test")

    check beforeSettings == autocompleteSettings

suite "Config mode: Chaging Persist table settings":
  test "Chaging exCommand":
    var
      settings = initEditorSettings()
      persistSettings = settings.persist

    let val = not persistSettings.exCommand
    persistSettings.changePerSistTableSettings("exCommand", $val)

    check val == persistSettings.exCommand

  test "Chaging search":
    var
      settings = initEditorSettings()
      persistSettings = settings.persist

    let val = not persistSettings.search
    persistSettings.changePerSistTableSettings("search", $val)

    check val == persistSettings.search

  test "Chaging cursorPosition":
    var
      settings = initEditorSettings()
      persistSettings = settings.persist

    let val = not persistSettings.cursorPosition
    persistSettings.changePerSistTableSettings("search", $val)

    check val == persistSettings.search

suite "Config mode: Chaging Theme table settings":
  # Generate test code
  macro checkChaingThemeSetting(theme: ColorTheme, editorColorName: string): untyped =
    let editorColor = ident(editorColorName.strVal)
    quote do:
      let
        name = $`editorColorName`
        testTitle = "Chaging " & name

      test testTitle:
        var settings = initEditorSettings()

        let
          position = if name[name.len - 2 .. ^1] == "Bg": "background"
                     else: "foreground"
          currentVal = ColorThemeTable[theme].`editorColor`
          n = if position == "background": name[0 .. name.high - 2]
              else: name
        var val = Color.default
        if currentVal == val: inc(val)
        settings.changeThemeTableSetting(n, position, $val)

        check ColorThemeTable[theme].`editorColor` == val

  let theme = ColorTheme.dark
  for name, _ in ColorThemeTable[theme].fieldPairs:
    checkChaingThemeSetting(theme, $name)

suite "Config mode: Get BuildOnSave table setting type":
  test "Get enable setting type":
    const
      table= "BuildOnSave"
      name = "enable"

    const settingType = getSettingType(table, name)
    check settingType == SettingType.Bool

  test "Get workspaceRoot setting type":
    const
      table = "BuildOnSave"
      name = "workspaceRoot"

    const settingType = getSettingType(table, name)
    check settingType == SettingType.String

  test "Get command setting type":
    const
      table = "BuildOnSave"
      name = "command"

    const settingType = getSettingType(table, name)
    check settingType == SettingType.String

  test "Set invalid name":
    const
      table = "BuildOnSave"
      name = "test"

    const settingType = getSettingType(table, name)
    check settingType == SettingType.None
