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

import std/[unittest, strformat, os]
import pkg/results
import moepkg/[unicodeext, editorstatus, bufferstatus, color, ui, rgb]

import moepkg/settings {.all.}
import moepkg/configmode {.all.}

suite "Config mode: Start configuration mode":
  test "Init configuration mode buffer":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin(Mode.config)

    currentBufStatus.buffer = initConfigModeBuffer(status.settings)

suite "Config mode: Init buffer":
  test "Init standard table buffer":
    var status = initEditorStatus()
    status.settings.colorMode = ColorMode.c24bit

    let buffer = status.settings.initStandardTableBuffer

    const Sample = @[
      "Standard",
      "  theme                          dark",
      "  number                         true",
      "  currentNumber                  true",
      "  cursorLine                     false",
      "  statusLine                     true",
      "  tabLine                        true",
      "  syntax                         true",
      "  indentationLines               true",
      "  tabStop                        2",
      "  sidebar                        true",
      "  autoCloseParen                 true",
      "  autoIndent                     true",
      "  ignorecase                     true",
      "  smartcase                      true",
      "  disableChangeCursor            false",
      "  defaultCursor                  terminalDefault",
      "  normalModeCursor               blinkBlock",
      "  insertModeCursor               blinkIbeam",
      "  autoSave                       false",
      "  autoSaveInterval               5",
      "  liveReloadOfConf               false",
      "  incrementalSearch              true",
      "  popupWindowInExmode            true",
      "  autoDeleteParen                false",
      "  smoothScroll                   true",
      "  smoothScrollSpeed              15",
      "  liveReloadOfFile               false",
      "  colorMode                      24bit"].toSeqRunes

    for index, line in buffer:
      check Sample[index] == line

  test "Init ClipBoard table buffer":
    var status = initEditorStatus()
    status.settings.clipboard.enable = true
    status.settings.clipboard.toolOnLinux = ClipboardToolOnLinux.none
    let buffer = status.settings.clipboard.initClipBoardTableBuffer

    const Sample = @[
      "ClipBoard",
      "  enable                         true",
      "  toolOnLinux                    none"].toSeqRunes

    for index, line in buffer:
      check Sample[index] == line

  test "Init build on save table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.buildOnSave.initBuildOnSaveTableBuffer

    const Sample = @[
      "BuildOnSave",
      "  enable                         false",
      "  workspaceRoot                  ",
      "  command                        "].toSeqRunes

    for index, line in buffer:
      check Sample[index] == line

  test "Init tab line table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.initTabLineTableBuffer

    const Sample = @[
      "TabLine",
      "  allBuffer                      false"].toSeqRunes

    for index, line in buffer:
      check Sample[index] == line

  test "Init status line table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.statusLine.initStatusLineTableBuffer

    const Sample = @[
      "StatusLine",
      "  multipleStatusLine             true",
      "  merge                          false",
      "  mode                           true",
      "  filename                       true",
      "  chanedMark                     true",
      "  line                           true",
      "  column                         true",
      "  encoding                       true",
      "  language                       true",
      "  directory                      true",
      "  gitChangedLines                true",
      "  gitBranchName                  true",
      "  showGitInactive                false",
      "  showModeInactive               false"].toSeqRunes

    for index, line in buffer:
      check Sample[index] == line

  test "Init highlight table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.initHighlightTableBuffer

    const Sample = @[
      "Highlight",
      "  currentLine                    true",
      "  fullWidthSpace                 true",
      "  trailingSpaces                 true",
      "  currentWord                    true",
      "  replaceText                    true",
      "  reservedWord                   TODO WIP NOTE "].toSeqRunes

    for index, line in buffer:
      check Sample[index] == line

  test "Init auto backup table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.autoBackup.initAutoBackupTableBuffer

    const Sample = @[
      "AutoBackup",
      "  enable                         false",
      "  idleTime                       10",
      "  interval                       5",
      "  backupDir                      {getCacheDir()}/moe/backups".fmt,
      "  dirToExclude                   /etc"].toSeqRunes

    for index, line in buffer:
      check Sample[index] == line

  test "Init QuickRun table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.quickRun.initQuickRunTableBuffer

    const Sample = @[
      "QuickRun",
      "  saveBufferWhenQuickRun         true",
      "  command                        ",
      "  timeout                        30",
      "  nimAdvancedCommand             c",
      "  clangOptions                   ",
      "  cppOptions                     ",
      "  nimOptions                     ",
      "  shOptions                      ",
      "  bashOptions                    "].toSeqRunes

    for index, line in buffer:
      check Sample[index] == line

  test "Init Notification table buffer":
    var status = initEditorStatus()
    let
      notificationSettings = status.settings.notification
      buffer = notificationSettings.initNotificationTableBuffer

    const Sample = @[
      "Notification",
      "  screenNotifications            true",
      "  logNotifications               true",
      "  autoBackupScreenNotify         true",
      "  autoBackupLogNotify            true",
      "  autoSaveScreenNotify           true",
      "  autoSaveLogNotify              true",
      "  yankScreenNotify               true",
      "  yankLogNotify                  true",
      "  deleteScreenNotify             true",
      "  deleteLogNotify                true",
      "  saveScreenNotify               true",
      "  saveLogNotify                  true",
      "  quickRunScreenNotify           true",
      "  quickRunLogNotify              true",
      "  buildOnSaveScreenNotify        true",
      "  buildOnSaveLogNotify           true",
      "  filerScreenNotify              true",
      "  filerLogNotify                 true",
      "  restoreScreenNotify            true",
      "  restoreLogNotify               true"].toSeqRunes

    for index, line in buffer:
      check Sample[index] == line

  test "Init Filer table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.initFilerTableBuffer

    const Sample = @[
      ru"Filer",
      ru"  showIcons                      true"]

    for index, line in buffer:
      check Sample[index] == line

  test "Init Autocomplete table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.initAutocompleteTableBuffer

    const Sample = @[
      ru"Autocomplete",
      ru"  enable                         true"]

    for index, line in buffer:
      check Sample[index] == line

  test "Init Persist table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.persist.initPersistTableBuffer

    const Sample = @[
      "Persist",
      "  exCommand                      true",
      "  exCommandHistoryLimit          1000",
      "  search                         true",
      "  searchHistoryLimit             1000",
      "  cursorPosition                 true"].toSeqRunes

    for index, line in buffer:
      check Sample[index] == line

  test "init GitTableBuffer":
    var status = initEditorStatus()
    let buffer = status.settings.git.initGitTableBuffer

    const Sample = @[
      "Git",
      "  showChangedLine                true",
      "  updateInterval                 1000"].toSeqRunes

    for index, line in buffer:
      check Sample[index] == line

  test "Init Theme table buffer":
    var status = initEditorStatus()
    let buffer = status.settings.initThemeTableBuffer

    const Sample = @[
      "Theme",
      "  default",
      "    foreground                   #f8f5e3",
      "    background                   #000000",
      "",
      "  lineNum",
      "    foreground                   #8a8a8a",
      "    background                   #000000",
      "",
      "  currentLineNum",
      "    foreground                   #008080",
      "    background                   #000000",
      "",
      "  statusLineNormalMode",
      "    foreground                   #ffffff",
      "    background                   #09aefa",
      "",
      "  statusLineModeNormalMode",
      "    foreground                   #000000",
      "    background                   #ffffff",
      "",
      "  statusLineNormalModeInactive",
      "    foreground                   #09aefa",
      "    background                   #ffffff",
      "",
      "  statusLineInsertMode",
      "    foreground                   #ffffff",
      "    background                   #09aefa",
      "",
      "  statusLineModeInsertMode",
      "    foreground                   #000000",
      "    background                   #ffffff",
      "",
      "  statusLineInsertModeInactive",
      "    foreground                   #09aefa",
      "    background                   #ffffff",
      "",
      "  statusLineVisualMode",
      "    foreground                   #ffffff",
      "    background                   #09aefa",
      "",
      "  statusLineModeVisualMode",
      "    foreground                   #000000",
      "    background                   #ffffff",
      "",
      "  statusLineVisualModeInactive",
      "    foreground                   #09aefa",
      "    background                   #ffffff",
      "",
      "  statusLineReplaceMode",
      "    foreground                   #ffffff",
      "    background                   #09aefa",
      "",
      "  statusLineModeReplaceMode",
      "    foreground                   #000000",
      "    background                   #ffffff",
      "",
      "  statusLineReplaceModeInactive",
      "    foreground                   #09aefa",
      "    background                   #ffffff",
      "",
      "  statusLineFilerMode",
      "    foreground                   #ffffff",
      "    background                   #09aefa",
      "",
      "  statusLineModeFilerMode",
      "    foreground                   #000000",
      "    background                   #ffffff",
      "",
      "  statusLineFilerModeInactive",
      "    foreground                   #09aefa",
      "    background                   #ffffff",
      "",
      "  statusLineExMode",
      "    foreground                   #ffffff",
      "    background                   #09aefa",
      "",
      "  statusLineModeExMode",
      "    foreground                   #000000",
      "    background                   #ffffff",
      "",
      "  statusLineExModeInactive",
      "    foreground                   #09aefa",
      "    background                   #ffffff",
      "",
      "  statusLineGitChangedLines",
      "    foreground                   #ffffff",
      "    background                   #0040ff",
      "",
      "  statusLineGitBranch",
      "    foreground                   #ffffff",
      "    background                   #0040ff",
      "",
      "  tab",
      "    foreground                   #ffffff",
      "    background                   #000000",
      "",
      "  currentTab",
      "    foreground                   #ffffff",
      "    background                   #09aefa",
      "",
      "  commandLine",
      "    foreground                   #ffffff",
      "    background                   #000000",
      "",
      "  errorMessage",
      "    foreground                   #ff0000",
      "    background                   #000000",
      "",
      "  searchResult",
      "    foreground                   #ffffff",
      "    background                   #ff0000",
      "",
      "  visualMode",
      "    foreground                   #ffffff",
      "    background                   #800080",
      "",
      "  keyword",
      "    foreground                   #87d7ff",
      "    background                   #000000",
      "",
      "  functionName",
      "    foreground                   #00b7ce",
      "    background                   #000000",
      "",
      "  typeName",
      "    foreground                   #00ffff",
      "    background                   #000000",
      "",
      "  boolean",
      "    foreground                   #add8e6",
      "    background                   #000000",
      "",
      "  specialVar",
      "    foreground                   #0090a8",
      "    background                   #000000",
      "",
      "  builtin",
      "    foreground                   #add8e6",
      "    background                   #000000",
      "",
      "  stringLit",
      "    foreground                   #add8e6",
      "    background                   #000000",
      "",
      "  binNumber",
      "    foreground                   #add8e6",
      "    background                   #000000",
      "",
      "  decNumber",
      "    foreground                   #add8e6",
      "    background                   #000000",
      "",
      "  floatNumber",
      "    foreground                   #add8e6",
      "    background                   #000000",
      "",
      "  hexNumber",
      "    foreground                   #add8e6",
      "    background                   #000000",
      "",
      "  octNumber",
      "    foreground                   #add8e6",
      "    background                   #000000",
      "",
      "  comment",
      "    foreground                   #808080",
      "    background                   #000000",
      "",
      "  longComment",
      "    foreground                   #808080",
      "    background                   #000000",
      "",
      "  whitespace",
      "    foreground                   #808080",
      "    background                   #000000",
      "",
      "  preprocessor",
      "    foreground                   #0090a8",
      "    background                   #000000",
      "",
      "  pragma",
      "    foreground                   #0090a8",
      "    background                   #000000",
      "",
      "  currentFile",
      "    foreground                   #ffffff",
      "    background                   #09aefa",
      "",
      "  file",
      "    foreground                   #ffffff",
      "    background                   #000000",
      "",
      "  dir",
      "    foreground                   #09aefa",
      "    background                   #000000",
      "",
      "  pcLink",
      "    foreground                   #008080",
      "    background                   #000000",
      "",
      "  popupWindow",
      "    foreground                   #ffffff",
      "    background                   #000000",
      "",
      "  popupWinCurrentLine",
      "    foreground                   #09aefa",
      "    background                   #000000",
      "",
      "  replaceText",
      "    foreground                   #ffffff",
      "    background                   #ff0000",
      "",
      "  parenPair",
      "    foreground                   #ffffff",
      "    background                   #09aefa",
      "",
      "  currentWord",
      "    foreground                   #ffffff",
      "    background                   #808080",
      "",
      "  highlightFullWidthSpace",
      "    foreground                   #ff0000",
      "    background                   #ff0000",
      "",
      "  highlightTrailingSpaces",
      "    foreground                   #ff0000",
      "    background                   #ff0000",
      "",
      "  reservedWord",
      "    foreground                   #ffffff",
      "    background                   #808080",
      "",
      "  syntaxCheckInfo",
      "    foreground                   #ffff00",
      "    background                   #000000",
      "",
      "  syntaxCheckHint",
      "    foreground                   #ffff00",
      "    background                   #000000",
      "",
      "  syntaxCheckWarn",
      "    foreground                   #ffff00",
      "    background                   #000000",
      "",
      "  syntaxCheckErr",
      "    foreground                   #ff0000",
      "    background                   #000000",
      "",
      "  gitConflict",
      "    foreground                   #00ff00",
      "    background                   #000000",
      "",
      "  backupManagerCurrentLine",
      "    foreground                   #ffffff",
      "    background                   #008080",
      "",
      "  diffViewerAddedLine",
      "    foreground                   #008000",
      "    background                   #000000",
      "",
      "  diffViewerDeletedLine",
      "    foreground                   #ff0000",
      "    background                   #000000",
      "",
      "  configModeCurrentLine",
      "    foreground                   #ffffff",
      "    background                   #008080",
      "",
      "  currentLineBg",
      "    foreground                   termDefautFg",
      "    background                   #444444",
      "",
      "  sidebarGitAddedSign",
      "    foreground                   #008000",
      "    background                   #000000",
      "",
      "  sidebarGitDeletedSign",
      "    foreground                   #ff0000",
      "    background                   #000000",
      "",
      "  sidebarGitChangedSign",
      "    foreground                   #ffff00",
      "    background                   #000000",
      "",
      "  sidebarSyntaxCheckInfoSign",
      "    foreground                   #ffff00",
      "    background                   #000000",
      "",
      "  sidebarSyntaxCheckHintSign",
      "    foreground                   #ffff00",
      "    background                   #000000",
      "",
      "  sidebarSyntaxCheckWarnSign",
      "    foreground                   #ffff00",
      "    background                   #000000",
      "",
      "  sidebarSyntaxCheckErrSign",
      "    foreground                   #ff0000",
      "    background                   #000000",
      ""
    ].toSeqRunes

    for index, line in buffer:
      check Sample[index] == line

# TODO: Should return bool.
proc checkBoolSettingValue(default: bool, values: seq[Runes]) =
  if default:
    check values == @[ru "true", ru "false"]
  else:
    check values == @[ru "false", ru "true"]

suite "Config mode: Get standard table setting values":
  test "Get theme values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "theme"
    let values = settings.getStandardTableSettingValues(Name)

    check values == @[ru"dark", ru"light",ru "vivid", ru"config", ru"vscode"]

  test "Get defaultCursor values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "defaultCursor"
    let values = settings.getStandardTableSettingValues(Name)

    check values == @[
      ru"terminalDefault",
      ru"blinkBlock",
      ru"noneBlinkBlock",
      ru"blinkIbeam",
      ru"noneBlinkIbeam"]

  test "Get normalModeCursor values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name ="normalModeCursor"
    let values = settings.getStandardTableSettingValues(Name)

    check values == @[
      ru"blinkBlock",
      ru"terminalDefault",
      ru"noneBlinkBlock",
      ru"blinkIbeam",
      ru"noneBlinkIbeam"]

  test "Get insertModeCursor values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "insertModeCursor"
    let values = settings.getStandardTableSettingValues(Name)

    check values == @[
      ru"blinkIbeam",
      ru"terminalDefault",
      ru"blinkBlock",
      ru"noneBlinkBlock",
      ru"noneBlinkIbeam"]

  test "Get number values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "number"
    let
      default = settings.view.lineNumber
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get currentNumber values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "currentNumber"
    let
      default = settings.view.currentLineNumber
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get cursorLine values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "cursorLine"
    let
      default = settings.view.cursorLine
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get statusLine values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "statusLine"
    let
      default = settings.statusLine.enable
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get tabLine values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "tabLine"
    let
      default = settings.tabLine.enable
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get syntax values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "syntax"
    let
      default = settings.syntax
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get indentationLines values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "indentationLines"
    let
      default = settings.view.indentationLines
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get autoCloseParen values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "autoCloseParen"
    let
      default = settings.autoCloseParen
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get autoIndent values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "autoIndent"
    let
      default = settings.autoIndent
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get ignorecase values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "ignorecase"
    let
      default = settings.ignorecase
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get smartcase values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "smartcase"
    let
      default = settings.smartcase
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get disableChangeCursor values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "disableChangeCursor"
    let
      default = settings.disableChangeCursor
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get autoSave values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "autoSave"
    let
      default = settings.autoSave
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get liveReloadOfConfvalues":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "liveReloadOfConf"
    let
      default = settings.liveReloadOfConf
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get incrementalSearch values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "incrementalSearch"
    let
      default = settings.incrementalSearch
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get popupWindowInExmode values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "popupWindowInExmode"
    let
      default = settings.popupWindowInExmode
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get autoDeleteParen values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "autoDeleteParen"
    let
      default = settings.autoDeleteParen
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get smoothScroll values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "smoothScroll"
    let
      default = settings.smoothScroll
      values = settings.getStandardTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get colorMode values":
    var status = initEditorStatus()

    var settings = status.settings
    settings.colorMode = ColorMode.c24bit

    const Name = "colorMode"
    let values = settings.getStandardTableSettingValues(Name)

    check values == @[ru"24bit", ru"none", ru"8", ru"16", ru"256"]

  test "Set invalid Name":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "test"
    let values = settings.getStandardTableSettingValues(Name)

    check values.len == 0

suite "Config mode: Get ClipBoard table setting values":
  test "Get enable value":
    var status = initEditorStatus()
    let clipboardSettings = status.settings.clipboard

    const Name = "enable"
    let
      default = clipboardSettings.enable
      values = clipboardSettings.getClipboardTableSettingsValues(Name)

    checkBoolSettingValue(default, values)

  test "Get toolOnLinux value":
    var status = initEditorStatus()
    status.settings.clipboard.toolOnLinux = ClipboardToolOnLinux.none
    let clipboardSettings = status.settings.clipboard

    const Name = "toolOnLinux"
    let
      default = clipboardSettings.toolOnLinux
      values = clipboardSettings.getClipboardTableSettingsValues(Name)

    check $default == $values[0]

suite "Config mode: Get BuildOnSave table setting values":
  test "Get enable values":
    var status = initEditorStatus()
    let buildOnSaveSettings = status.settings.buildOnSave

    const Name = "enable"
    let
      default = buildOnSaveSettings.enable
      values = buildOnSaveSettings.getBuildOnSaveTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get workspaceRoot values":
    var status = initEditorStatus()
    let buildOnSaveSettings = status.settings.buildOnSave

    const Name = "workspaceRoot"
    let
      default = buildOnSaveSettings.workspaceRoot
      values = buildOnSaveSettings.getBuildOnSaveTableSettingValues(Name)

    check default == values[0]

  test "Get command values":
    var status = initEditorStatus()
    let buildOnSaveSettings = status.settings.buildOnSave

    const Name = "command"
    let
      default = buildOnSaveSettings.command
      values = buildOnSaveSettings.getBuildOnSaveTableSettingValues(Name)

    check default == values[0]

  test "Set invalid Name":
    var status = initEditorStatus()
    let buildOnSaveSettings = status.settings.buildOnSave

    const Name = "test"
    let values = buildOnSaveSettings.getBuildOnSaveTableSettingValues(Name)

    check values.len == 0

suite "Config mode: Get TabLine table setting values":
  test "Get allBuffer values":
    var status = initEditorStatus()
    let tablineSettings = status.settings.tabLine

    const Name = "allBuffer"
    let
      default = tablineSettings.allBuffer
      values = tablineSettings.getTabLineTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Set invalid Name":
    var status = initEditorStatus()
    let tablineSettings = status.settings.tabLine

    const Name = "test"
    let values = tablineSettings.getTabLineTableSettingValues(Name)

    check values.len == 0

suite "Config mode: Get StatusLine table setting values":
  test "Get multipleStatusLine values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const Name = "multipleStatusLine"
    let
      default = statusLineSettings.multipleStatusLine
      values = statusLineSettings.getStatusLineTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get merge values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const Name = "merge"
    let
      default = statusLineSettings.merge
      values = statusLineSettings.getStatusLineTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get mode values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const Name = "mode"
    let
      default = statusLineSettings.mode
      values = statusLineSettings.getStatusLineTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get fileName values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const Name = "filename"
    let
      default = statusLineSettings.fileName
      values = statusLineSettings.getStatusLineTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get chanedMark values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const Name = "chanedMark"
    let
      default = statusLineSettings.chanedMark
      values = statusLineSettings.getStatusLineTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get line values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const Name = "line"
    let
      default = statusLineSettings.line
      values = statusLineSettings.getStatusLineTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get column values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const Name = "column"
    let
      default = statusLineSettings.column
      values = statusLineSettings.getStatusLineTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get encoding values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const Name = "encoding"
    let
      default = statusLineSettings.characterEncoding
      values = statusLineSettings.getStatusLineTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get language values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const Name = "language"
    let
      default = statusLineSettings.language
      values = statusLineSettings.getStatusLineTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get directory values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const Name = "directory"
    let
      default = statusLineSettings.directory
      values = statusLineSettings.getStatusLineTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get gitChangedLines values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const Name = "gitChangedLines"
    let
      default = statusLineSettings.gitChangedLines
      values = statusLineSettings.getStatusLineTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get gitBranchName values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const Name = "gitBranchName"
    let
      default = statusLineSettings.gitBranchName
      values = statusLineSettings.getStatusLineTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get showGitInactive values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const Name = "showGitInactive"
    let
      default = statusLineSettings.showGitInactive
      values = statusLineSettings.getStatusLineTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get showModeInactive values":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const Name = "showModeInactive"
    let
      default = statusLineSettings.showModeInactive
      values = statusLineSettings.getStatusLineTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Set invalid Name":
    var status = initEditorStatus()
    let statusLineSettings = status.settings.statusLine

    const Name = "test"
    let values = statusLineSettings.getStatusLineTableSettingValues(Name)

    check values.len == 0

suite "Config mode: Get Highlight table setting values":
  test "Get currentLine values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "currentLine"
    let
      default = settings.view.highlightCurrentLine
      values = settings.getHighlightTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get fullWidthSpace values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "fullWidthSpace"
    let
      default = settings.highlight.fullWidthSpace
      values = settings.getHighlightTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get trailingSpaces values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "trailingSpaces"
    let
      default = settings.highlight.trailingSpaces
      values = settings.getHighlightTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get currentWord values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "currentWord"
    let
      default = settings.highlight.currentWord
      values = settings.getHighlightTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get replaceText values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "replaceText"
    let
      default = settings.highlight.replaceText
      values = settings.getHighlightTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get pairOfParen values":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "pairOfParen"
    let
      default = settings.highlight.pairOfParen
      values = settings.getHighlightTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Set invalid Name":
    var status = initEditorStatus()
    let settings = status.settings

    const Name = "test"
    let values = settings.getHighlightTableSettingValues(Name)

    check values.len == 0

suite "Config mode: Get AutoBackup table setting values":
  test "Get enable values":
    var status = initEditorStatus()
    let autoBackupSettings = status.settings.autoBackup

    const
      Name = "enable"
      SettingType = SettingType.Bool
    let
      default = autoBackupSettings.enable
      values = autoBackupSettings.getAutoBackupTableSettingValues(
        Name,
        SettingType)

    checkBoolSettingValue(default, values)

  test "Get backupDir values":
    var status = initEditorStatus()
    let autoBackupSettings = status.settings.autoBackup

    const
      Name = "backupDir"
      SettingType = SettingType.String
    let
      default = autoBackupSettings.backupDir
      values = autoBackupSettings.getAutoBackupTableSettingValues(
        Name,
        SettingType)

    check default == values[0]

  test "Set invalid Name":
    var status = initEditorStatus()
    let autoBackupSettings = status.settings.autoBackup

    const
      Name = "test"
      SettingType = SettingType.None
    let values = autoBackupSettings.getAutoBackupTableSettingValues(
      Name,
      SettingType)

    check values.len == 0

suite "Config mode: Get QuickRun table setting values":
  test "Get saveBufferWhenQuickRun values":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRun

    const
      Name = "saveBufferWhenQuickRun"
      SettingType = SettingType.Bool
    let
      default = quickRunSettings.saveBufferWhenQuickRun
      values = quickRunSettings.getQuickRunTableSettingValues(Name, SettingType)

    checkBoolSettingValue(default, values)

  test "Get nimAdvancedCommandvalues":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRun

    const
      Name = "nimAdvancedCommand"
      SettingType = SettingType.String
    let
      default = ru quickRunSettings.nimAdvancedCommand
      values = quickRunSettings.getQuickRunTableSettingValues(Name, SettingType)

    check default == values[0]

  test "Get clangOptions values":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRun

    const
      Name = "clangOptions"
      SettingType = SettingType.String
    let
      default = ru quickRunSettings.clangOptions
      values = quickRunSettings.getQuickRunTableSettingValues(Name, SettingType)

    check default == values[0]

  test "Get cppOptions values":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRun

    const
      Name = "cppOptions"
      SettingType = SettingType.String
    let
      default = ru quickRunSettings.cppOptions
      values = quickRunSettings.getQuickRunTableSettingValues(Name, SettingType)

    check default == values[0]

  test "Get nimOptions values":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRun

    const
      Name = "nimOptions"
      SettingType = SettingType.String
    let
      default = ru quickRunSettings.nimOptions
      values = quickRunSettings.getQuickRunTableSettingValues(Name, SettingType)

    check default == values[0]

  test "Get shOptions values":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRun

    const
      Name = "shOptions"
      SettingType = SettingType.String
    let
      default = ru quickRunSettings.shOptions
      values = quickRunSettings.getQuickRunTableSettingValues(Name, SettingType)

    check default == values[0]

  test "Get bashOptions values":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRun

    const
      Name = "bashOptions"
      SettingType = SettingType.String
    let
      default = ru quickRunSettings.bashOptions
      values = quickRunSettings.getQuickRunTableSettingValues(Name, SettingType)

    check default == values[0]

  test "Set invalid Name":
    var status = initEditorStatus()
    let quickRunSettings = status.settings.quickRun

    const
      Name = "test"
      SettingType = SettingType.None
    let values = quickRunSettings.getQuickRunTableSettingValues(Name, SettingType)

    check values.len == 0

suite "Config mode: Get Notification table setting values":
  test "Get screenNotifications values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "screenNotifications"
    let
      default = notificationSettings.screenNotifications
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get logNotifications values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "logNotifications"
    let
      default = notificationSettings.logNotifications
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get autoBackupScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "autoBackupScreenNotify"
    let
      default = notificationSettings.autoBackupScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get autoBackupLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "autoBackupLogNotify"
    let
      default = notificationSettings.autoBackupLogNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get autoSaveScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "autoSaveScreenNotify"
    let
      default = notificationSettings.autoSaveScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get autoSaveLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "autoSaveLogNotify"
    let
      default = notificationSettings.autoSaveLogNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get yankScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "yankScreenNotify"
    let
      default = notificationSettings.yankScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get yankLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "yankLogNotify"
    let
      default = notificationSettings.yankLogNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get deleteScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "deleteScreenNotify"
    let
      default = notificationSettings.deleteScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get deleteLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "deleteLogNotify"
    let
      default = notificationSettings.deleteLogNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get saveScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "saveScreenNotify"
    let
      default = notificationSettings.saveScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get saveLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "saveLogNotify"
    let
      default = notificationSettings.saveLogNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get quickRunScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "quickRunScreenNotify"
    let
      default = notificationSettings.quickRunScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get quickRunLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "quickRunLogNotify"
    let
      default = notificationSettings.quickRunLogNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get buildOnSaveScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "buildOnSaveScreenNotify"
    let
      default = notificationSettings.buildOnSaveScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "buildOnSaveLogNotify"
    let
      default = notificationSettings.buildOnSaveLogNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get filerScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "filerScreenNotify"
    let
      default = notificationSettings.filerScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get filerLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "filerLogNotify"
    let
      default = notificationSettings.filerLogNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get restoreScreenNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "restoreScreenNotify"
    let
      default = notificationSettings.restoreScreenNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Get restoreLogNotify values":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "restoreLogNotify"
    let
      default = notificationSettings.restoreLogNotify
      values = notificationSettings.getNotificationTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Set invalid Name":
    var status = initEditorStatus()
    let notificationSettings = status.settings.notification

    const Name = "test"
    let values = notificationSettings.getNotificationTableSettingValues(Name)

    check values.len == 0

suite "Config mode: Get Filer table setting values":
  test "Get showIcons values":
    var status = initEditorStatus()
    let filerSettings = status.settings.filer

    const Name = "showIcons"
    let
      default = filerSettings.showIcons
      values = filerSettings.getFilerTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Set invalid Name":
    var status = initEditorStatus()
    let filerSettings = status.settings.filer

    const Name = "test"
    let values = filerSettings.getFilerTableSettingValues(Name)

    check values.len == 0

suite "Config mode: Get Autocomplete table setting values":
  test "Get enable values":
    var status = initEditorStatus()
    let autocompleteSettings = status.settings.autocomplete

    const Name = "enable"
    let
      default = autocompleteSettings.enable
      values = autocompleteSettings.getAutocompleteTableSettingValues(Name)

    checkBoolSettingValue(default, values)

  test "Set invalid Name":
    var status = initEditorStatus()
    let autocompleteSettings = status.settings.autocomplete

    const Name = "test"
    let values = autocompleteSettings.getAutocompleteTableSettingValues(Name)

    check values.len == 0

suite "Config mode: Get Persist table setting values":
  test "Get exCommand values":
    var status = initEditorStatus()
    let persistSettings = status.settings.persist

    const Name = "exCommand"
    let
      default = persistSettings.exCommand
      values = persistSettings.getPersistTableSettingsValues(Name)

    checkBoolSettingValue(default, values)

  test "Get exCommandHistoryLimit values":
    var status = initEditorStatus()
    let persistSettings = status.settings.persist

    const Name = "exCommandHistoryLimit"
    let
      default = persistSettings.exCommandHistoryLimit
      values = persistSettings.getPersistTableSettingsValues(Name)

    check default == values[0].parseInt

  test "Get search values":
    var status = initEditorStatus()
    let persistSettings = status.settings.persist

    const Name = "search"
    let
      default = persistSettings.exCommand
      values = persistSettings.getPersistTableSettingsValues(Name)

    checkBoolSettingValue(default, values)

  test "Get searchHistoryLimit values":
    var status = initEditorStatus()
    let persistSettings = status.settings.persist

    const Name = "searchHistoryLimit"
    let
      default = persistSettings.searchHistoryLimit
      values = persistSettings.getPersistTableSettingsValues(Name)

    check default == values[0].parseInt

  test "Get cursorPosition values":
    var status = initEditorStatus()
    let persistSettings = status.settings.persist

    const Name = "cursorPosition"
    let
      default = persistSettings.cursorPosition
      values = persistSettings.getPersistTableSettingsValues(Name)

    checkBoolSettingValue(default, values)

  test "Set invalid Name":
    var status = initEditorStatus()
    let persistSettings = status.settings.persist

    const Name = "test"
    let values = persistSettings.getPersistTableSettingsValues(Name)

    check values.len == 0

suite "Config mode: Get Git table setting values":
  test "showChangedLine":
    let s = initGitSettings()

    const Name = "showChangedLine"
    let
      default = s.showChangedLine
      values = s.getGitTableSettingsValues(Name)

    checkBoolSettingValue(default, values)

  test "updateInterval":
    let s = initGitSettings()

    const Name = "updateInterval"
    let values = s.getGitTableSettingsValues(Name)

    check @[ru"1000"] == values

  test "Invalid Name":
    let s = initGitSettings()

    const Name = "test"
    check s.getGitTableSettingsValues(Name).len == 0

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

  test "Chaging popupWindowInExmode":
    var settings = initEditorSettings()

    let val = not settings.popupWindowInExmode
    settings.changeStandardTableSetting("popupWindowInExmode", $val)

    check val == settings.popupWindowInExmode

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

  test "Chaging colorMode":
    var settings = initEditorSettings()

    settings.colorMode = ColorMode.c24bit
    settings.changeStandardTableSetting("colorMode", "none")
    check ColorMode.none == settings.colorMode

    settings.colorMode = ColorMode.c24bit
    settings.changeStandardTableSetting("colorMode", "8")
    check ColorMode.c8 == settings.colorMode

    settings.colorMode = ColorMode.c24bit
    settings.changeStandardTableSetting("colorMode", "16")
    check ColorMode.c16 == settings.colorMode

    settings.colorMode = ColorMode.c24bit
    settings.changeStandardTableSetting("colorMode", "256")
    check ColorMode.c256 == settings.colorMode

    settings.colorMode = ColorMode.none
    settings.changeStandardTableSetting("colorMode", "24bit")
    check ColorMode.c24bit == settings.colorMode

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

  test "Chaging fileName":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let val = not statusLineSettings.fileName
    statusLineSettings.changeStatusLineTableSetting("filename", $val)

    check val == statusLineSettings.fileName

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

  test "Chaging gitChangedLines":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let val = not statusLineSettings.gitChangedLines
    statusLineSettings.changeStatusLineTableSetting("gitChangedLines", $val)

    check val == statusLineSettings.gitChangedLines

  test "Chaging gitBranchName":
    var
      settings = initEditorSettings()
      statusLineSettings = settings.statusLine

    let val = not statusLineSettings.gitBranchName
    statusLineSettings.changeStatusLineTableSetting("gitBranchName", $val)

    check val == statusLineSettings.gitBranchName

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

    let val = not settings.highlight.fullWidthSpace
    settings.changeHighlightTableSetting("fullWidthSpace", $val)

    check val == settings.highlight.fullWidthSpace

  test "Chaging trailingSpaces":
    var settings = initEditorSettings()

    let val = not settings.highlight.trailingSpaces
    settings.changeHighlightTableSetting("trailingSpaces", $val)

    check val == settings.highlight.trailingSpaces

  test "Chaging replaceText":
    var settings = initEditorSettings()

    let val = not settings.highlight.replaceText
    settings.changeHighlightTableSetting("replaceText", $val)

    check val == settings.highlight.replaceText

  test "Chaging pairOfParen":
    var settings = initEditorSettings()

    let val = not settings.highlight.pairOfParen
    settings.changeHighlightTableSetting("pairOfParen", $val)

    check val == settings.highlight.pairOfParen

  test "Chaging currentWord":
    var settings = initEditorSettings()

    let val = not settings.highlight.currentWord
    settings.changeHighlightTableSetting("currentWord", $val)

    check val == settings.highlight.currentWord

  test "Set invalid value":
    var settings = initEditorSettings()

    let beforeSettings = settings
    settings.changeHighlightTableSetting("test", "test")

    check beforeSettings == settings

suite "Config mode: Chaging AutoBackup table settings":
  test "Chaging enable":
    var
      settings = initEditorSettings()
      autoBackupSettings = settings.autoBackup

    let val = not autoBackupSettings.enable
    autoBackupSettings.changeBackupTableSetting("enable", $val)

    check val == autoBackupSettings.enable

  test "Set invalid value":
    var
      settings = initEditorSettings()
      autoBackupSettings = settings.autoBackup

    let beforeSettings = autoBackupSettings
    autoBackupSettings.changeBackupTableSetting("test", "test")

    check beforeSettings == autoBackupSettings

suite "Config mode: Chaging QuickRun table settings":
  test "Chaging saveBufferWhenQuickRun":
    var
      settings = initEditorSettings()
      quickRunSettings = settings.quickRun

    let val = not quickRunSettings.saveBufferWhenQuickRun
    quickRunSettings.changeQuickRunTableSetting("saveBufferWhenQuickRun", $val)

    check val == quickRunSettings.saveBufferWhenQuickRun

  test "Set invalid value":
    var
      settings = initEditorSettings()
      quickRunSettings = settings.quickRun

    let beforeSettings = quickRunSettings
    quickRunSettings.changeQuickRunTableSetting("test", "test")

    check beforeSettings == quickRunSettings

suite "Config mode: Chaging Notification table settings":
  test "Chaging screenNotifications":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.screenNotifications
    notificationSettings.changeNotificationTableSetting("screenNotifications", $val)

    check val == notificationSettings.screenNotifications

  test "Chaging logNotifications":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.logNotifications
    notificationSettings.changeNotificationTableSetting("logNotifications", $val)

    check val == notificationSettings.logNotifications

  test "Chaging autoBackupScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.autoBackupScreenNotify
    notificationSettings.changeNotificationTableSetting("autoBackupScreenNotify", $val)

    check val == notificationSettings.autoBackupScreenNotify

  test "Chaging autoBackupLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.autoBackupLogNotify
    notificationSettings.changeNotificationTableSetting("autoBackupLogNotify", $val)

    check val == notificationSettings.autoBackupLogNotify

  test "Chaging autoSaveScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.autoSaveScreenNotify
    notificationSettings.changeNotificationTableSetting("autoSaveScreenNotify", $val)

    check val == notificationSettings.autoSaveScreenNotify

  test "Chaging autoSaveLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.autoSaveLogNotify
    notificationSettings.changeNotificationTableSetting("autoSaveLogNotify", $val)

    check val == notificationSettings.autoSaveLogNotify

  test "Chaging yankScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.yankScreenNotify
    notificationSettings.changeNotificationTableSetting("yankScreenNotify", $val)

    check val == notificationSettings.yankScreenNotify

  test "Chaging yankLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.yankLogNotify
    notificationSettings.changeNotificationTableSetting("yankLogNotify", $val)

    check val == notificationSettings.yankLogNotify

  test "Chaging deleteScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.deleteScreenNotify
    notificationSettings.changeNotificationTableSetting("deleteScreenNotify", $val)

    check val == notificationSettings.deleteScreenNotify

  test "Chaging deleteLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.deleteLogNotify
    notificationSettings.changeNotificationTableSetting("deleteLogNotify", $val)

    check val == notificationSettings.deleteLogNotify

  test "Chaging saveScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.saveScreenNotify
    notificationSettings.changeNotificationTableSetting("saveScreenNotify", $val)

    check val == notificationSettings.saveScreenNotify

  test "Chaging saveLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.saveLogNotify
    notificationSettings.changeNotificationTableSetting("saveLogNotify", $val)

    check val == notificationSettings.saveLogNotify

  test "Chaging quickRunScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.quickRunScreenNotify
    notificationSettings.changeNotificationTableSetting("quickRunScreenNotify", $val)

    check val == notificationSettings.quickRunScreenNotify

  test "Chaging quickRunLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.quickRunLogNotify
    notificationSettings.changeNotificationTableSetting("quickRunLogNotify", $val)

    check val == notificationSettings.quickRunLogNotify

  test "Chaging buildOnSaveScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.buildOnSaveScreenNotify
    notificationSettings.changeNotificationTableSetting("buildOnSaveScreenNotify", $val)

    check val == notificationSettings.buildOnSaveScreenNotify

  test "Chaging buildOnSaveLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.buildOnSaveLogNotify
    notificationSettings.changeNotificationTableSetting("buildOnSaveLogNotify", $val)

    check val == notificationSettings.buildOnSaveLogNotify

  test "Chaging filerScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.filerScreenNotify
    notificationSettings.changeNotificationTableSetting("filerScreenNotify", $val)

    check val == notificationSettings.filerScreenNotify

  test "Chaging filerLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.filerLogNotify
    notificationSettings.changeNotificationTableSetting("filerLogNotify", $val)

    check val == notificationSettings.filerLogNotify

  test "Chaging restoreScreenNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.restoreScreenNotify
    notificationSettings.changeNotificationTableSetting("restoreScreenNotify", $val)

    check val == notificationSettings.restoreScreenNotify

  test "Chaging restoreLogNotify":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let val = not notificationSettings.restoreLogNotify
    notificationSettings.changeNotificationTableSetting("restoreLogNotify", $val)

    check val == notificationSettings.restoreLogNotify

  test "Set invalid value":
    var
      settings = initEditorSettings()
      notificationSettings = settings.notification

    let beforeSettings = notificationSettings
    notificationSettings.changeNotificationTableSetting("test", "test")

    check beforeSettings == notificationSettings

suite "Config mode: Chaging Filer table settings":
  test "Chaging showIcons":
    var
      settings = initEditorSettings()
      filerSettings = settings.filer

    let val = not filerSettings.showIcons
    filerSettings.changeFilerTableSetting("showIcons", $val)

    check val == filerSettings.showIcons

  test "Set invalid value":
    var
      settings = initEditorSettings()
      filerSettings = settings.filer

    let beforeSettings = filerSettings
    filerSettings.changeFilerTableSetting("test", "test")

    check beforeSettings == filerSettings

suite "Config mode: Chaging Autocomplete table settings":
  test "Chaging enable":
    var
      settings = initEditorSettings()
      autocompleteSettings = settings.autocomplete

    let val = not autocompleteSettings.enable
    autocompleteSettings.changeAutoCompleteTableSetting("enable", $val)

    check val == autocompleteSettings.enable

  test "Set invalid value":
    var
      settings = initEditorSettings()
      autocompleteSettings = settings.autocomplete

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

  test "Chaging exCommandHistoryLimit":
    var
      settings = initEditorSettings()
      persistSettings = settings.persist

    let val = not persistSettings.exCommandHistoryLimit
    persistSettings.changePerSistTableSettings("exCommandHistoryLimit", $val)

    check val == persistSettings.exCommandHistoryLimit

  test "Chaging search":
    var
      settings = initEditorSettings()
      persistSettings = settings.persist

    let val = not persistSettings.search
    persistSettings.changePerSistTableSettings("search", $val)

    check val == persistSettings.search

  test "Chaging searchHistoryLimit":
    var
      settings = initEditorSettings()
      persistSettings = settings.persist

    let val = not persistSettings.searchHistoryLimit
    persistSettings.changePerSistTableSettings("searchHistoryLimit", $val)

    check val == persistSettings.searchHistoryLimit

  test "Chaging cursorPosition":
    var
      settings = initEditorSettings()
      persistSettings = settings.persist

    let val = not persistSettings.cursorPosition
    persistSettings.changePerSistTableSettings("search", $val)

    check val == persistSettings.search

suite "Config mode: Change Git table sttings":
  test "showChangedLine":
    var s = initGitSettings()

    let val = not s.showChangedLine
    s.changeGitTableSettings("showChangedLine", $val)

    check val == s.showChangedLine

  test "updateInterval":
    var s = initGitSettings()

    let val = 1
    s.changeGitTableSettings("updateInterval", $val)

    check 1 == s.updateInterval

suite "Config mode: Change Theme table settings":
  test "change foreground":
    var settings = initEditorSettings()

    for pairIndex in EditorColorPairIndex:
      assert settings.changeThemeTableSetting(
        ColorLayer.foreground,
        $pairIndex,
        "#000000").isOk

      assert "#000000".hexToRgb.get ==
        settings.editorColorTheme.foregroundRgb(pairIndex)

  test "change background":
    var settings = initEditorSettings()

    for pairIndex in EditorColorPairIndex:
      assert settings.changeThemeTableSetting(
        ColorLayer.background,
        $pairIndex,
        "#000000").isOk

      assert "#000000".hexToRgb.get ==
        settings.editorColorTheme.backgroundRgb(pairIndex)

suite "Config mode: Get BuildOnSave table setting type":
  test "Get enable setting type":
    const
      Table = "BuildOnSave"
      Name = "enable"

    let settingType = getSettingType(Table, Name)
    check settingType == SettingType.Bool

  test "Get workspaceRoot setting type":
    const
      Table = "BuildOnSave"
      Name = "workspaceRoot"

    let settingType = getSettingType(Table, Name)
    check settingType == SettingType.String

  test "Get command setting type":
    const
      Table = "BuildOnSave"
      Name = "command"

    let settingType = getSettingType(Table, Name)
    check settingType == SettingType.String

  test "Set invalid Name":
    const
      Table = "BuildOnSave"
      Name = "test"

    let settingType = getSettingType(Table, Name)
    check settingType == SettingType.None

suite "Config mode: getColorModeSettingValues":
  test "Current mode is ColorMode.none":
    check @[ru"none", ru"8", ru"16", ru"256", ru"24bit"] ==
      ColorMode.none.getColorModeSettingValues

  test "Current mode is ColorMode.c8":
    check @[ru"8", ru"none", ru"16", ru"256", ru"24bit"] ==
      ColorMode.c8.getColorModeSettingValues

  test "Current mode is ColorMode.c16":
    check @[ru"16", ru"none", ru"8", ru"256", ru"24bit"] ==
      ColorMode.c16.getColorModeSettingValues

  test "Current mode is ColorMode.c256":
    check @[ru"256", ru"none", ru"8", ru"16", ru"24bit"] ==
      ColorMode.c256.getColorModeSettingValues

  test "Current mode is ColorMode.c24bit":
    check @[ru"24bit", ru"none", ru"8", ru"16", ru"256"] ==
      ColorMode.c24bit.getColorModeSettingValues
