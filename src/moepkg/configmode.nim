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

import std/[times, strutils, options, strformat, sequtils]
import pkg/results
import gapbuffer, ui, editorstatus, unicodeext, windownode, movement, settings,
       bufferstatus, color, highlight, editor, commandline, popupwindow, rgb,
       theme, independentutils

type
  StandardTableNames {.pure.} = enum
    theme
    number
    currentNumber
    cursorLine
    statusLine
    tabLine
    syntax
    indentationLines
    tabStop
    sidebar
    autoCloseParen
    autoIndent
    ignorecase
    smartcase
    disableChangeCursor
    defaultCursor
    normalModeCursor
    insertModeCursor
    autoSave
    autoSaveInterval
    liveReloadOfConf
    incrementalSearch
    popupWindowInExmode
    autoDeleteParen
    liveReloadOfFile
    colorMode

  ClipboardTableNames {.pure.} = enum
    enable
    toolOnLinux

  BuildOnSaveTableNames {.pure.}= enum
    enable
    workspaceRoot
    command

  TabLineTableNames {.pure.} = enum
    allBuffer

  StatusLineTableNames {.pure.} = enum
    multipleStatusLine
    merge
    mode
    filename
    chanedMark
    line
    column
    encoding
    language
    directory
    gitChangedLines
    gitBranchName
    showGitInactive
    showModeInactive
    setupText

  HighlightTableNames {.pure.} = enum
    currentLine
    fullWidthSpace
    trailingSpaces
    currentWord
    replaceText
    pairOfParen
    reservedWords

  AutoBackupTableNames {.pure.} = enum
    enable
    idleTime
    interval
    backupDir
    dirToExclude

  QuickRunTableNames {.pure.} = enum
    saveBufferWhenQuickRun
    command
    timeout
    nimAdvancedCommand
    clangOptions
    cppOptions
    nimOptions
    shOptions
    bashOptions

  NotificationTableNames {.pure.} = enum
    screenNotifications
    logNotifications
    autoBackupScreenNotify
    autoBackupLogNotify
    autoSaveScreenNotify
    autoSaveLogNotify
    yankScreenNotify
    yankLogNotify
    deleteScreenNotify
    deleteLogNotify
    saveScreenNotify
    saveLogNotify
    quickRunScreenNotify
    quickRunLogNotify
    buildOnSaveScreenNotify
    buildOnSaveLogNotify
    filerScreenNotify
    filerLogNotify
    restoreScreenNotify
    restoreLogNotify

  FilerTableNames {.pure.} = enum
    showIcons

  AutocompleteTableNames {.pure.} = enum
    enable

  PersistTableNames {.pure.} = enum
    exCommand
    exCommandHistoryLimit
    search
    searchHistoryLimit
    cursorPosition

  GitTableNames {.pure.} = enum
    showChangedLine
    updateInterval

  SyntaxCheckerTableNames {.pure.} = enum
    enable

  SmoothScrollTableNames {.pure.} = enum
    enable
    minDelay
    maxDelay

  StartUpFileOpenSettingsTableNames {.pure.} = enum
    autoSplit
    splitType

  SettingType {.pure.} = enum
    none
    bool
    enums
    number
    text

const
  NumOfIndent = 2
  Indent = "  "

proc positionOfSetVal(): int {.compileTime.} =
  ## A start position of a setting value in the line.
  ## All start positions are same.

  var names: seq[string]

  for name in StandardTableNames: names.add $name
  for name in ClipboardTableNames: names.add $name
  for name in BuildOnSaveTableNames: names.add $name
  for name in TabLineTableNames: names.add $name
  for name in StatusLineTableNames: names.add $name
  for name in HighlightTableNames: names.add $name
  for name in AutoBackupTableNames: names.add $name
  for name in QuickRunTableNames: names.add $name
  for name in NotificationTableNames: names.add $name
  for name in FilerTableNames: names.add $name
  for name in AutocompleteTableNames: names.add $name
  for name in PersistTableNames: names.add $name
  for name in GitTableNames: names.add $name
  for name in SyntaxCheckerTableNames: names.add $name
  for name in SmoothScrollTableNames: names.add $name
  for name in StartUpFileOpenSettingsTableNames: names.add $name
  for name in EditorColorPairIndex: names.add $name

  for name in names:
    if result < name.len: result = name.len

  result += NumOfIndent

proc getColorThemeSettingValues(currentVal: ColorTheme): seq[Runes] =
  result.add ru $currentVal
  for theme in ColorTheme:
    if theme != currentVal:
      result.add ru $theme

proc getCursorTypeSettingValues(currentVal: CursorType): seq[Runes] =
  result.add ru $currentVal
  for cursorType in CursorType:
    if $cursorType != $currentVal:
      result.add ru $cursorType

proc getColorModeSettingValues(currentVal: ColorMode): seq[Runes] =
  result.add toRunes(currentVal.toConfigStr)
  const ConfigVals = @["none", "8", "16", "256", "24bit"]
  for c in ConfigVals:
    if c != currentVal.toConfigStr:
      result.add c.toRunes

proc getStandardTableSettingValues(
  settings: EditorSettings,
  name: string): seq[Runes] =

    if name == "theme":
      let theme = settings.editorColorTheme
      result = getColorThemeSettingValues(theme)
    elif name == "defaultCursor":
      let currentCursorType = settings.defaultCursor
      result = getCursorTypeSettingValues(currentCursorType)
    elif name == "normalModeCursor":
      let currentCursorType = settings.normalModeCursor
      result = getCursorTypeSettingValues(currentCursorType)
    elif name == "insertModeCursor":
      let currentCursorType = settings.insertModeCursor
      result = getCursorTypeSettingValues(currentCursorType)
    elif name == "colorMode":
      result = settings.colorMode.getColorModeSettingValues
    else:
      var currentVal: bool

      case name:
        of "number":
          currentVal = settings.view.lineNumber
        of "currentNumber":
          currentVal = settings.view.currentLineNumber
        of "cursorLine":
          currentVal = settings.view.cursorLine
        of "statusLine":
          currentVal = settings.statusLine.enable
        of "tabLine":
          currentVal = settings.tabLine.enable
        of "syntax":
          currentVal = settings.syntax
        of "indentationLines":
          currentVal = settings.view.indentationLines
        of "sidebar":
          currentVal = settings.view.sidebar
        of "autoCloseParen":
          currentVal = settings.autoCloseParen
        of "autoIndent":
          currentVal = settings.autoIndent
        of "ignorecase":
          currentVal = settings.ignorecase
        of "smartcase":
          currentVal = settings.smartcase
        of "disableChangeCursor":
          currentVal = settings.disableChangeCursor
        of "autoSave":
          currentVal = settings.autoSave
        of "liveReloadOfConf":
          currentVal = settings.liveReloadOfConf
        of "incrementalSearch":
          currentVal = settings.incrementalSearch
        of "popupWindowInExmode":
          currentVal = settings.popupWindowInExmode
        of "autoDeleteParen":
          currentVal = settings.autoDeleteParen
        of "liveReloadOfFile":
          currentVal = settings.liveReloadOfFile
        else:
          return

      if currentVal:
        result = @[ru "true", ru "false"]
      else:
        result = @[ru "false", ru "true"]

proc getClipboardTableSettingsValues(
  settings: ClipboardSettings,
  name: string): seq[Runes] =

    case name:
      of "enable":
        let currentVal = settings.enable
        if currentVal:
          result = @[ru "true", ru "false"]
        else:
          result = @[ru "false", ru "true"]
      of "toolOnLinux":
        for toolName in ClipboardToolOnLinux:
          if $toolName == "wlClipboard":
            result.add ru "wl-clipboard"
          else:
            result.add ($toolName).ru
      else:
        return

proc getBuildOnSaveTableSettingValues(
  settings: BuildOnSaveSettings,
  name: string): seq[Runes] =

    case name:
      of "enable":
        let currentVal = settings.enable
        if currentVal:
          result = @[ru "true", ru "false"]
        else:
          result = @[ru "false", ru "true"]
      of "workspaceRoot":
        result = @[settings.workspaceRoot]
      of "command":
        result = @[settings.command]
      else:
        return

proc getTabLineTableSettingValues(
  settings: TabLineSettings,
  name: string): seq[Runes] =

    var currentVal: bool
    case name:
      of "allBuffer":
        currentVal = settings.allBuffer
      else:
        return

    if currentVal:
      result = @[ru "true", ru "false"]
    else:
      result = @[ru "false", ru "true"]

proc getStatusLineTableSettingValues(
  settings: StatusLineSettings,
  name: string): seq[Runes] =

    if name == "setupText":
      return @[settings.setupText]
    else:
      var currentVal: bool
      case name:
        of "multipleStatusLine":
          currentVal = settings.multipleStatusLine
        of "merge":
          currentVal = settings.merge
        of "mode":
          currentVal = settings.mode
        of "filename":
          currentVal = settings.filename
        of "chanedMark":
          currentVal = settings.chanedMark
        of "directory":
          currentVal = settings.directory
        of "gitChangedLines":
          currentVal = settings.gitChangedLines
        of "gitBranchName":
          currentVal = settings.gitBranchName
        of "showGitInactive":
          currentVal = settings.showGitInactive
        of "showModeInactive":
          currentVal = settings.showModeInactive
        else:
          return

      if currentVal:
        result = @[ru "true", ru "false"]
      else:
        result = @[ru "false", ru "true"]

proc getHighlightTableSettingValues(
  settings: EditorSettings,
  name: string): seq[Runes] =

    var currentVal: bool
    case name:
      of "currentLine":
        currentVal = settings.view.highlightCurrentLine
      of "fullWidthSpace":
        currentVal = settings.highlight.fullWidthSpace
      of "trailingSpaces":
        currentVal = settings.highlight.trailingSpaces
      of "currentWord":
        currentVal = settings.highlight.currentWord
      of "replaceText":
        currentVal = settings.highlight.replaceText
      of "pairOfParen":
        currentVal = settings.highlight.pairOfParen
      else:
        return

    if currentVal:
      result = @[ru "true", ru "false"]
    else:
      result = @[ru "false", ru "true"]

proc getAutoBackupTableSettingValues(
  settings: AutoBackupSettings,
  name: string,
  settingType: SettingType): seq[Runes] =

    case name:
      of "enable":
        let currentVal = settings.enable
        if currentVal:
          result = @[ru "true", ru "false"]
        else:
          result = @[ru "false", ru "true"]
      of "backupDir":
        result = @[settings.backupDir]
      else:
        return

proc getQuickRunTableSettingValues(
  settings: QuickRunSettings,
  name: string,
  settingType: SettingType): seq[Runes] =

    case name:
      of "saveBufferWhenQuickRun":
        let currentVal = settings.saveBufferWhenQuickRun
        if currentVal:
          result = @[ru "true", ru "false"]
        else:
          result = @[ru "false", ru "true"]
      of "nimAdvancedCommand":
        result = @[ru settings.nimAdvancedCommand]
      of "clangOptions":
        result = @[ru settings.clangOptions]
      of "cppOptions":
        result = @[ru settings.cppOptions]
      of "nimOptions":
        result = @[ru settings.nimOptions]
      of "shOptions":
        result = @[ru settings.shOptions]
      of "bashOptions":
        result = @[ru settings.bashOptions]
      else:
        return

proc getNotificationTableSettingValues(
  settings: NotificationSettings,
  name: string): seq[Runes] =

    var currentVal: bool
    case name:
      of "screenNotifications":
        currentVal = settings.screenNotifications
      of "logNotifications":
        currentVal = settings.logNotifications
      of "autoBackupScreenNotify":
        currentVal = settings.autoBackupScreenNotify
      of "autoBackupLogNotify":
        currentVal = settings.autoBackupLogNotify
      of "autoSaveScreenNotify":
        currentVal = settings.autoSaveScreenNotify
      of "autoSaveLogNotify":
        currentVal = settings.autoSaveLogNotify
      of "yankScreenNotify":
        currentVal = settings.yankScreenNotify
      of "yankLogNotify":
        currentVal = settings.yankLogNotify
      of "deleteScreenNotify":
        currentVal = settings.deleteScreenNotify
      of "deleteLogNotify":
        currentVal = settings.deleteLogNotify
      of "saveScreenNotify":
        currentVal = settings.saveScreenNotify
      of "saveLogNotify":
        currentVal = settings.saveLogNotify
      of "quickRunScreenNotify":
        currentVal = settings.quickRunScreenNotify
      of "quickRunLogNotify":
        currentVal = settings.quickRunLogNotify
      of "buildOnSaveScreenNotify":
        currentVal = settings.buildOnSaveScreenNotify
      of "buildOnSaveLogNotify":
        currentVal = settings.buildOnSaveLogNotify
      of "filerScreenNotify":
        currentVal = settings.filerScreenNotify
      of "filerLogNotify":
        currentVal = settings.filerLogNotify
      of "restoreScreenNotify":
        currentVal = settings.restoreScreenNotify
      of "restoreLogNotify":
        currentVal = settings.restoreLogNotify
      else:
        return

    if currentVal:
      result = @[ru "true", ru "false"]
    else:
      result = @[ru "false", ru "true"]

proc getFilerTableSettingValues(
  settings: FilerSettings,
  name: string): seq[Runes] =

    var currentVal: bool
    case name:
      of "showIcons":
        currentVal = settings.showIcons
      else:
        return

    if currentVal:
      result = @[ru "true", ru "false"]
    else:
      result = @[ru "false", ru "true"]

proc getAutocompleteTableSettingValues(
  settings: AutocompleteSettings,
  name: string): seq[Runes] =

    var currentVal: bool
    case name:
      of "enable":
        currentVal = settings.enable
      else:
        return

    if currentVal:
      result = @[ru "true", ru "false"]
    else:
      result = @[ru "false", ru "true"]

proc getPersistTableSettingsValues(
  settings: PersistSettings,
  name: string): seq[Runes] =

    case name:
      of "exCommand", "search", "cursorPosition":
        var currentVal: bool
        case name:
          of "exCommand":
            currentVal = settings.exCommand
          of "search":
            currentVal = settings.search
          of "cursorPosition":
            currentVal = settings.cursorPosition
          else:
            return
        if currentVal:
          result = @[ru "true", ru "false"]
        else:
          result = @[ru "false", ru "true"]
      of "exCommandHistoryLimit", "searchHistoryLimit":
        case name:
          of "exCommandHistoryLimit":
            result = @[settings.exCommandHistoryLimit.toRunes]
          of "searchHistoryLimit":
            result = @[settings.searchHistoryLimit.toRunes]
          else:
            return

proc getGitTableSettingsValues(
  s: GitSettings,
  name: string): seq[Runes] =

    case name
      of "showChangedLine":
        var currentVal: bool
        case name:
          of "showChangedLine":
            currentVal = s.showChangedLine
        if currentVal:
          result = @[ru "true", ru "false"]
        else:
          result = @[ru "false", ru "true"]
      of "updateInterval":
        return @[s.updateInterval.toRunes]

proc getSyntaxCheckerTableSettingsValues(
  s: SyntaxCheckerSettings,
  name: string): seq[Runes] =

    case name
      of "enable":
        if s.enable:
          result = @[ru "true", ru "false"]
        else:
          result = @[ru "false", ru "true"]

proc getSmoothScrollTableSettingsValues(
  s: SmoothScrollSettings,
  name: string): seq[Runes] =

    case name
      of "enable":
        if s.enable:
          result = @[ru "true", ru "false"]
        else:
          result = @[ru "false", ru "true"]
      of "minDelay":
        result = @[toRunes($s.minDelay)]
      of "maxDelay":
        result = @[toRunes($s.maxDelay)]

proc getStartUpFileOpenSettingsValues(
  s: StartUpFileOpenSettings,
  name: string): seq[Runes] =

    case name
      of "autoSplit":
        if s.autoSplit:
          result = @[ru "true", ru "false"]
        else:
          result = @[ru "false", ru "true"]
      of "splitType":
        if s.splitType == WindowSplitType.vertical:
          result = @[ru "vertical", ru "horizontal"]
        else:
          result = @[ru "horizontal", ru "vertical"]

proc getSettingValues(
  settings: EditorSettings,
  settingType: SettingType,
  table, name, position: string): seq[Runes] =

    case table:
      of "Standard":
        result = settings.getStandardTableSettingValues(name)
      of "ClipBoard":
        result = settings.clipboard.getClipboardTableSettingsValues(name)
      of "BuildOnSave":
        result = settings.buildOnSave.getBuildOnSaveTableSettingValues(name)
      of "TabLine":
        result = settings.tabLine.getTabLineTableSettingValues(name)
      of "StatusLine":
        result = settings.statusLine.getStatusLineTableSettingValues(name)
      of "Highlight":
        result = settings.getHighlightTableSettingValues(name)
      of "AutoBackup":
        let settings = settings.autoBackup
        result = settings.getAutoBackupTableSettingValues(name, settingType)
      of "QuickRun":
        let quickRunSettings = settings.quickRun
        result = quickRunSettings.getQuickRunTableSettingValues(name, settingType)
      of "Notification":
        let notificationSettings = settings.notification
        result = notificationSettings.getNotificationTableSettingValues(name)
      of "Filer":
        result = settings.filer.getFilerTableSettingValues(name)
      of "Autocomplete":
        let autocompleteSettings = settings.autocomplete
        result = autocompleteSettings.getAutocompleteTableSettingValues(name)
      of "Persist":
        let persistSettings = settings.persist
        result = persistSettings.getPersistTableSettingsValues(name)
      of "Git":
        let gitSettings = settings.git
        result = gitSettings.getGitTableSettingsValues(name)
      of "SyntaxChecker":
        result = settings.syntaxChecker.getSyntaxCheckerTableSettingsValues(name)
      of "SmoothScroll":
        result = settings.smoothScroll.getSmoothScrollTableSettingsValues(name)
      of "StartUp.FileOpen":
        result = settings.startUp.fileOpen.getStartUpFileOpenSettingsValues(name)
      of "Theme":
        discard
      else:
        discard

proc maxLen(list: seq[Runes]): int =
  for r in list:
    if r.len > result:
      result = r.len + 2

proc getTableName(buffer: GapBuffer[Runes], line: int): string =
  # Search table name from configuration mode buffer
  for i in countdown(line, 0):
    if buffer[i].len > 0 and buffer[i][0] != ru ' ':
      return $buffer[i]

proc initConfigModeHighlight[T](
  buffer: T,
  currentLine: int,
  reservedWords: seq[ReservedWord]): Highlight =

    for i in 0 ..< buffer.len:
      if i == currentLine:
        result.colorSegments.add(
          ColorSegment(
            firstRow: i,
            firstColumn: 0,
            lastRow: i,
            lastColumn: buffer[i].len,
            color: EditorColorPairIndex.default))

proc changeStandardTableSetting(
  settings: var EditorSettings,
  settingName, settingVal: string) =

    case settingName:
      of "theme":
        settings.editorColorTheme = parseEnum[ColorTheme](settingVal)
      of "number":
        settings.view.lineNumber = parseBool(settingVal)
      of "currentNumber":
        settings.view.currentLineNumber = parseBool(settingVal)
      of "cursorLine":
        settings.view.cursorLine = parseBool(settingVal)
      of "statusLine":
        settings.statusLine.enable = parseBool(settingVal)
      of "tabLine":
        settings.tabLine.enable = parseBool(settingVal)
      of "syntax":
        settings.syntax = parseBool(settingVal)
      of "indentationLines":
        settings.view.indentationLines = parseBool(settingVal)
      of "sidebar":
        settings.view.sidebar = parseBool(settingVal)
      of "autoCloseParen":
        settings.autoCloseParen = parseBool(settingVal)
      of "autoIndent":
        settings.autoIndent = parseBool(settingVal)
      of "ignorecase":
        settings.ignorecase = parseBool(settingVal)
      of "smartcase":
        settings.smartcase = parseBool(settingVal)
      of "disableChangeCursor":
        settings.disableChangeCursor = parseBool(settingVal)
      of "defaultCursor":
        settings.defaultCursor = parseEnum[CursorType](settingVal)
      of "normalModeCursor":
        settings.normalModeCursor = parseEnum[CursorType](settingVal)
      of "insertModeCursor":
        settings.insertModeCursor = parseEnum[CursorType](settingVal)
      of "autoSave":
        settings.autoSave = parseBool(settingVal)
      of "liveReloadOfConf":
        settings.liveReloadOfConf = parseBool(settingVal)
      of "incrementalSearch":
        settings.incrementalSearch = parseBool(settingVal)
      of "popupWindowInExmode":
        settings.popupWindowInExmode = parseBool(settingVal)
      of "autoDeleteParen":
        settings.autoDeleteParen = parseBool(settingVal)
      of "liveReloadOfFile":
        settings.liveReloadOfFile = parseBool(settingVal)
      of "colorMode":
        settings.colorMode = parseColorMode(settingVal).get
      else:
        discard

proc changeClipBoardTableSettings(
  settings: var ClipboardSettings,
  settingName, settingVal: string) =

    case settingName:
      of "enable":
        settings.enable = parseBool(settingVal)
      of "toolOnLinux":
        let name = if settingVal == "wl-clipboard": "wlClipboard" else: settingVal
        settings.toolOnLinux = parseEnum[ClipboardToolOnLinux](name)
      else:
        discard

proc changeBuildOnSaveTableSetting(
  settings: var BuildOnSaveSettings,
  settingName, settingVal: string) =

    case settingName:
      of "enable":
        settings.enable = parseBool(settingVal)
      else:
        discard

proc changeTabLineTableSetting(
  settings: var TabLineSettings,
  settingName, settingVal: string) =

    case settingName:
      of "allBuffer":
        settings.allBuffer = parseBool(settingVal)
      else:
        discard

proc changeStatusLineTableSetting(
  settings: var StatusLineSettings,
  settingName, settingVal: string) =

    case settingName:
      of "multipleStatusLine":
        settings.multipleStatusLine = parseBool(settingVal)
      of "merge":
        settings.merge = parseBool(settingVal)
      of "mode":
        settings.mode = parseBool(settingVal)
      of "filename":
        settings.filename = parseBool(settingVal)
      of "chanedMark":
        settings.chanedMark = parseBool(settingVal)
      of "directory":
        settings.directory = parseBool(settingVal)
      of "gitChangedLines":
        settings.gitChangedLines = parseBool(settingVal)
      of "gitBranchName":
        settings.gitBranchName = parseBool(settingVal)
      of "showGitInactive":
        settings.showGitInactive = parseBool(settingVal)
      of "showModeInactive":
        settings.showModeInactive = parseBool(settingVal)
      of "setupText":
        settings.setupText = settingVal.toRunes
      else:
        discard

proc changeHighlightTableSetting(
  settings: var EditorSettings,
  settingName, settingVal: string) =

    case settingName:
      of "currentLine":
        settings.view.highlightCurrentLine = parseBool(settingVal)
      of "fullWidthSpace":
        settings.highlight.fullWidthSpace = parseBool(settingVal)
      of "trailingSpaces":
        settings.highlight.trailingSpaces = parseBool(settingVal)
      of "replaceText":
        settings.highlight.replaceText = parseBool(settingVal)
      of "pairOfParen":
        settings.highlight.pairOfParen = parseBool(settingVal)
      of "currentWord":
        settings.highlight.currentWord = parseBool(settingVal)
      of "reservedWords":
        discard
      else:
        discard

proc changeBackupTableSetting(
  settings: var AutoBackupSettings,
  settingName, settingVal: string) =

    case settingName:
      of "enable":
        settings.enable = parseBool(settingVal)
      else:
        discard

proc changeQuickRunTableSetting(
  settings: var QuickRunSettings,
  settingName, settingVal: string) =

    case settingName:
      of "saveBufferWhenQuickRun":
        settings.saveBufferWhenQuickRun = parseBool(settingVal)
      else:
        discard

proc changeNotificationTableSetting(
  settings: var NotificationSettings,
  settingName, settingVal: string) =

    case settingName:
      of "screenNotifications":
        settings.screenNotifications = parseBool(settingVal)
      of "logNotifications":
        settings.logNotifications = parseBool(settingVal)
      of "autoBackupScreenNotify":
        settings.autoBackupScreenNotify = parseBool(settingVal)
      of "autoBackupLogNotify":
        settings.autoBackupLogNotify = parseBool(settingVal)
      of "autoSaveScreenNotify":
        settings.autoSaveScreenNotify = parseBool(settingVal)
      of "autoSaveLogNotify":
        settings.autoSaveLogNotify = parseBool(settingVal)
      of "yankScreenNotify":
        settings.yankScreenNotify = parseBool(settingVal)
      of "yankLogNotify":
        settings.yankLogNotify = parseBool(settingVal)
      of "deleteScreenNotify":
        settings.deleteScreenNotify = parseBool(settingVal)
      of "deleteLogNotify":
        settings.deleteLogNotify = parseBool(settingVal)
      of "saveScreenNotify":
        settings.saveScreenNotify = parseBool(settingVal)
      of "saveLogNotify":
        settings.saveLogNotify = parseBool(settingVal)
      of "quickRunScreenNotify":
        settings.quickRunScreenNotify = parseBool(settingVal)
      of "quickRunLogNotify":
        settings.quickRunLogNotify = parseBool(settingVal)
      of "buildOnSaveScreenNotify":
        settings.buildOnSaveScreenNotify = parseBool(settingVal)
      of "buildOnSaveLogNotify":
        settings.buildOnSaveLogNotify = parseBool(settingVal)
      of "filerScreenNotify":
        settings.filerScreenNotify = parseBool(settingVal)
      of "filerLogNotify":
        settings.filerLogNotify = parseBool(settingVal)
      of "restoreScreenNotify":
        settings.restoreScreenNotify = parseBool(settingVal)
      of "restoreLogNotify":
        settings.restoreLogNotify = parseBool(settingVal)

proc changeFilerTableSetting(
  settings: var FilerSettings,
  settingName, settingVal: string) =

    case settingName:
      of "showIcons":
        settings.showIcons = parseBool(settingVal)
      else:
        discard

proc changeAutoCompleteTableSetting(
  settings: var AutocompleteSettings,
  settingName, settingVal: string) =

    case settingName:
      of "enable":
        settings.enable = parseBool(settingVal)
      else:
        discard

proc changePerSistTableSettings(
  settings: var PersistSettings,
  settingName, settingVal: string) =

    case settingName:
      of "exCommand":
        settings.exCommand = parseBool(settingVal)
      of "exCommandHistoryLimit":
        settings.exCommandHistoryLimit = parseInt(settingVal)
      of "search":
        settings.search = parseBool(settingVal)
      of "searchHistoryLimit":
        settings.searchHistoryLimit = parseInt(settingVal)
      of "cursorPosition":
        settings.cursorPosition = parseBool(settingVal)
      else:
        discard

proc changeGitTableSettings(
  s: var GitSettings,
  settingName, settingVal: string) =

    case settingName:
      of "showChangedLine":
        s.showChangedLine = settingVal.parseBool
      of "updateInterval":
        s.updateInterval = settingVal.parseInt
      else:
        discard

proc changeSyntaxCheckerTableSettings(
  s: var SyntaxCheckerSettings,
  settingName, settingVal: string) =

    case settingName:
      of "enable":
        s.enable= settingVal.parseBool
      else:
        discard

proc changeSmoothScrollTableSettings(
  s: var SmoothScrollSettings,
  settingName, settingVal: string) =

    case settingName:
      of "enable":
        s.enable = settingVal.parseBool
      of "minDelay":
        s.minDelay = settingVal.parseInt
      of "maxDelay":
        s.maxDelay = settingVal.parseInt
      else:
        discard

proc changeStartUpFileOpenSettingsTableSettings(
  s: var StartUpFileOpenSettings,
  settingName, settingVal: string) =

    case settingName:
      of "autoSplit":
        s.autoSplit = settingVal.parseBool
      of "splitType":
        s.splitType = settingVal.parseWindowSplitType.get

proc toColorLayer(s: string): Result[ColorLayer, string] =
  var cl: ColorLayer
  try:
    cl = parseEnum[ColorLayer](s)
  except ValueError as e:
    return Result[ColorLayer, string].err fmt"Invalid value: {s}: {e.msg}"

  return Result[ColorLayer, string].ok cl

proc changeThemeTableSetting(
  settings: EditorSettings,
  colorLayer: ColorLayer,
  settingName, settingVal: string): Result[(), string] =

    if settingName.isEditorColorPairIndex and settingVal.isHexColor(false):
      let
        pairIndex = parseEnum[EditorColorPairIndex](settingName)
        rgb = settingVal.hexToRgb.get

      case colorLayer:
        of ColorLayer.foreground:
          settings.editorColorTheme.setForegroundRgb(pairIndex, rgb)
        of ColorLayer.background:
          settings.editorColorTheme.setBackgroundRgb(pairIndex, rgb)

      return Result[(), string].ok ()

proc changeEditorSettings(
  status: var EditorStatus,
  table, settingName, position, settingVal: string) =

    template settings: var EditorSettings = status.settings

    template changeStandardTableSetting() =
      let currentTheme = status.settings.editorColorTheme

      status.settings.changeStandardTableSetting(settingName, settingVal)

      if status.settings.editorColorTheme != currentTheme:
        # TODO: Add error handling
        discard status.changeTheme

    template clipboardSettings: var ClipboardSettings =
      status.settings.clipboard

    template buildOnSaveSettings: var BuildOnSaveSettings =
      status.settings.buildOnSave

    template tablineSettings: var TabLineSettings =
      status.settings.tabLine

    template statusLineSettings: var StatusLineSettings =
      status.settings.statusLine

    template autoBackupSettings: var AutoBackupSettings =
      status.settings.autoBackup

    template quickRunSettings: var QuickRunSettings =
      status.settings.quickRun

    template notificationSettings: var NotificationSettings =
      status.settings.notification

    template filerSettings: var FilerSettings =
      status.settings.filer

    template autocompleteSettings: var AutocompleteSettings =
      status.settings.autocomplete

    template persistSettings: var PersistSettings =
      status.settings.persist

    template gitSettings: var GitSettings =
      status.settings.git

    template SyntaxCheckerSettings: var SyntaxCheckerSettings =
      status.settings.syntaxChecker

    template SmoothScrollSettings: var SmoothScrollSettings =
      status.settings.smoothScroll

    template StartUpFileOpenSettings: var StartUpFileOpenSettings =
      status.settings.startUp.fileOpen

    case table:
      of "Standard":
        changeStandardTableSetting()
      of "ClipBoard":
        clipboardSettings.changeClipBoardTableSettings(settingName, settingVal)
      of "BuildOnSave":
        buildOnSaveSettings.changeBuildOnSaveTableSetting(settingName, settingVal)
      of "TabLine":
        tablineSettings.changeTabLineTableSetting(settingName, settingVal)
      of "StatusLine":
        statusLineSettings.changeStatusLineTableSetting(settingName, settingVal)
      of "Highlight":
        settings.changeHighlightTableSetting(settingName, settingVal)
      of "AutoBackup":
        autoBackupSettings.changeBackupTableSetting(settingName, settingVal)
      of "QuickRun":
        quickRunSettings.changeQuickRunTableSetting(settingName, settingVal)
      of "Notification":
        notificationSettings.changeNotificationTableSetting(
          settingName,
          settingVal)
      of "Filer":
        filerSettings.changeFilerTableSetting(settingName, settingVal)
      of "Autocomplete":
        autocompleteSettings.changeAutoCompleteTableSetting(settingName, settingVal)
      of "Persist":
        persistSettings.changePerSistTableSettings(settingName, settingVal)
      of "Git":
        gitSettings.changeGitTableSettings(settingName, settingVal)
      of "SyntaxChecker":
        SyntaxCheckerSettings.changeSyntaxCheckerTableSettings(settingName, settingVal)
      of "SmoothScroll":
        SmoothScrollSettings.changeSmoothScrollTableSettings(settingName, settingVal)
      of "StartUp.FileOpen":
        StartUpFileOpenSettings.changeStartUpFileOpenSettingsTableSettings(
          settingName,
          settingVal)
      else:
        discard

proc getSettingType(table, name: string): SettingType =
  template standardTable() =
    case name:
      of "theme",
         "defaultCursor",
         "normalModeCursor",
         "insertModeCursor": result = SettingType.enums
      of "number",
         "currentNumber",
         "cursorLine",
         "statusLine",
         "tabLine",
         "syntax",
         "indentationLines",
         "autoCloseParen",
         "autoIndent",
         "ignorecase",
         "smartcase",
         "disableChangeCursor",
         "autoSave",
         "liveReloadOfConf",
         "incrementalSearch",
         "popupWindowInExmode",
         "autoDeleteParen",
         "systemClipboard",
         "smoothScroll",
         "liveReloadOfFile",
         "sidebar": result = SettingType.bool
      of "tabStop",
         "autoSaveInterval",
         "smoothScrollMaxDelay": result = SettingType.number
      else:
        result = SettingType.none

  template clipboardTable() =
    case name:
      of "enable":
        result = SettingType.bool
      of "toolOnLinux":
        result = SettingType.enums
      else:
        result = SettingType.none

  template buildOnSaveTable() =
    case name:
      of "enable":
        result = SettingType.bool
      of "workspaceRoot",
         "command":
        result = SettingType.text
      else:
        result = SettingType.none

  template tablineTable() =
    case name:
      of "allBuffer":
        result = SettingType.bool
      else:
        result = SettingType.none

  template statusLineTable() =
    case name:
      of "multipleStatusLine",
         "merge",
         "mode",
         "filename",
         "chanedMark",
         "line",
         "column",
         "encoding",
         "language",
         "directory",
         "gitChangedLines",
         "gitBranchName",
         "showGitInactive",
         "showModeInactive":
           result = SettingType.bool
      of "setupText":
        result = SettingType.text
      else:
        result = SettingType.none

  template highlightTable() =
    case name:
      of "currentLine",
         "fullWidthSpace",
         "trailingSpaces",
         "currentWord",
         "replaceText",
         "pairOfParen": result = SettingType.bool
      of "reservedWords": result = SettingType.text
      else:
        result = SettingType.none

  template autoBackupTable() =
    case name:
      of "enable":
        result = SettingType.bool
      of "idleTime",
         "interval":
        result = SettingType.number
      of "backupDir":
        result = SettingType.text
      else:
        result = SettingType.none

  template quickRunTable() =
    case name:
      of "saveBufferWhenQuickRun":
        result = SettingType.bool
      of "timeout":
        result = SettingType.number
      of "nimAdvancedCommand",
         "ClangOptions",
         "CppOptions",
         "NimOptions",
         "shOptions",
         "bashOptions":
           result = SettingType.text
      else:
        result = SettingType.none

  template notificationTable() =
    case name:
      of "screenNotifications",
         "logNotifications",
         "autoBackupScreenNotify",
         "autoBackupLogNotify",
         "autoSaveScreenNotify",
         "autoSaveLogNotify",
         "yankScreenNotify",
         "yankLogNotify",
         "deleteScreenNotify",
         "deleteLogNotify",
         "saveScreenNotify",
         "saveLogNotify",
         "quickRunScreenNotify",
         "quickRunLogNotify",
         "buildOnSaveScreenNotify",
         "buildOnSaveLogNotify",
         "filerScreenNotify",
         "filerLogNotify",
         "restoreScreenNotify",
         "restoreLogNotify": result = SettingType.bool
      else:
        result = SettingType.none

  template filerTable() =
    case name:
      of "showIcons":
        result = SettingType.bool
      else:
        result = SettingType.none

  template autocompleteTable() =
    case name:
      of "enable":
        result = SettingType.bool
      else:
        result = SettingType.none

  template gitTable() =
    case name:
      of "showChangedLine":
        result = SettingType.bool
      of "updateInterval":
        result = SettingType.number
      else:
        result = SettingType.none

  template syntaxCheckerTable() =
    case name:
      of "enable":
        result = SettingType.bool
      else:
        result = SettingType.none

  template smoothScrollTable() =
    case name:
      of "enable":
        result = SettingType.bool
      of "minDelay", "maxDelay":
        result = SettingType.number
      else:
        result = SettingType.none

  template startUpFileOpenTable() =
    case name:
      of "autoSplit":
        result = SettingType.bool
      of "splitType":
        result = SettingType.enums

  case table:
    of "Standard":
      standardTable()
    of "ClipBoard":
      clipboardTable()
    of "BuildOnSave":
      buildOnSaveTable()
    of "TabLine":
      tablineTable()
    of "StatusLine":
      statusLineTable()
    of "Highlight":
      highlightTable()
    of "AutoBackup":
      autoBackupTable()
    of "QuickRun":
      quickRunTable()
    of "Notification":
      notificationTable()
    of "Filer":
      filerTable()
    of "Autocomplete":
      autocompleteTable()
    of "Git":
      gitTable()
    of "SyntaxChecker":
      syntaxCheckerTable()
    of "SmoothScroll":
      smoothScrollTable()
    of "StartUp.FileOpen":
      startUpFileOpenTable()
    of "Theme":
      return SettingType.text

proc getEditorColorPairIndexStr(
  buffer: GapBuffer[Runes],
  lineSplit: seq[Runes],
  currentLine: int): string =

    if (lineSplit[0] == ru "foreground") or
       (buffer[currentLine - 2] == ru "Theme"):
      return $(buffer[currentLine - 1].splitWhitespace)[0]
    else:
      return $(buffer[currentLine - 2].splitWhitespace)[0]

proc getSettingType(
  buffer: GapBuffer[Runes],
  currentLine: int): SettingType =

    let
      lineSplit = buffer[currentLine].splitWhitespace

      selectedTable = getTableName(buffer, currentLine)

      selectedSetting =
        if selectedTable == "Theme":
          buffer.getEditorColorPairIndexStr(lineSplit,currentLine)
        else:
          $lineSplit[0]

    return getSettingType(selectedTable, selectedSetting)

proc insertCharacter(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  c: Rune) =

    let oldLine = bufStatus.buffer[windowNode.currentLine]
    var newLine = bufStatus.buffer[windowNode.currentLine]

    # Insert character to newLine
    newLine.insert(c, windowNode.currentColumn)
    # Move to the right
    inc(windowNode.currentColumn)

    # Update buffer
    if oldLine != newLine:
      bufStatus.buffer[windowNode.currentLine] = newLine

proc editFiguresSetting(status: var EditorStatus, table, name: string) =
  setCursor(true)
  if not status.settings.disableChangeCursor:
    changeCursorType(status.settings.insertModeCursor)

  let
    currentLine = currentMainWindowNode.currentLine
    minColumn = currentBufStatus.buffer[currentLine].high

  template moveToLeft() =
    if minColumn > currentMainWindowNode.currentColumn:
      currentMainWindowNode.keyLeft

  # Set currentColumn
  block:
    let settings = status.settings
    template getSettingVal: int =
      case table:
        of "Standard":
          case name:
            of "tabStop": settings.tabStop
            of "autoSaveInterval": settings.autoSaveInterval
            else: 0

        of "AutoBackup":
          case name:
            of "idleTime": settings.autoBackup.idleTime
            of "interval": settings.autoBackup.interval
            else: 0

        of "QuickRun":
          case name:
            of "timeout": settings.quickRun.timeout
            else: 0
        of "SmoothScroll":
          case name:
            of "minDelay": settings.smoothScroll.minDelay
            of "maxDelay": settings.smoothScroll.maxDelay
            else: 0
        else: 0

    let
      val = getSettingVal()
      col = positionOfSetVal() + NumOfIndent + ($val).len
    currentMainWindowNode.currentColumn = col

  var
    numStr = ""
    isCancel = false
    isBreak = false
  while not isBreak and not isCancel:
    status.update

    var key = ERR_KEY
    while key == ERR_KEY:
      key = currentMainWindowNode.getKey

    if isResizeKey(key):
      status.resize
    elif isEscKey(key):
      isCancel = true
    elif isEnterKey(key):
      isBreak = true

    elif isLeftKey(key):
      moveToLeft()
    elif isRightKey(key):
      currentBufStatus.keyRight(currentMainWindowNode)

    elif isBackspaceKey(key):
      let
        autoDeleteParen = false

      if currentMainWindowNode.currentColumn > minColumn:
        currentBufStatus.keyBackspace(
          currentMainWindowNode,
          autoDeleteParen,
          status.settings.tabStop)

    else:
      numStr &= key
      currentBufStatus.insertCharacter(currentMainWindowNode, key)
      let reservedWords = status.settings.highlight.reservedWords
      currentMainWindowNode.highlight =
        currentBufStatus.buffer.initConfigModeHighlight(
          currentLine,
          reservedWords)

  if not isCancel:
    let number =
      try: parseInt(numStr)
      except ValueError: return

    template standardTable() =
      case name:
        of "tabStop":
          status.settings.tabStop = number
          status.settings.view.tabStop = number
        of "autoSaveInterval":
          status.settings.autoSaveInterval = number
        else:
          discard

    template autoBackupTable() =
      case name:
        of "idleTime":
          status.settings.autoBackup.idleTime = number
        of "interval":
          status.settings.autoBackup.interval = number
        else:
          discard

    template quickRunTable() =
      case name:
        of "timeout":
          status.settings.quickRun.timeout = number
        else:
          discard

    template smoothScrollTable() =
      case name:
        of "minDelay":
          status.settings.smoothScroll.minDelay = number
        of "maxDelay":
          status.settings.smoothScroll.maxDelay = number

    # Change setting
    case table:
      of "Standard":
        standardTable()
      of "AutoBackup":
        autoBackupTable()
      of "QuickRun":
        quickRunTable()
      of "SmoothScroll":
        smoothScrollTable()
      else:
        discard

  setCursor(false)
  currentMainWindowNode.currentColumn = 0
  if not status.settings.disableChangeCursor:
    changeCursorType(status.settings.normalModeCursor)

## Return a hex color string
proc getCurrentColorVal(s: EditorSettings, name, position: string): string =
  let
    pairIndex = parseEnum[EditorColorPairIndex](name)
  case parseEnum[ColorLayer](position):
    of ColorLayer.foreground:
      let fgHex = s.editorColorTheme.foregroundRgb(pairIndex).toHex
      if fgHex.isSome: return fgHex.get
      else: return "termDefautFg"
    of ColorLayer.background:
      let bgHex = s.editorColorTheme.backgroundRgb(pairIndex).toHex
      if bgHex.isSome: return bgHex.get
      else: return "termDefautBg"

proc getTextSettingVal(
  s: EditorSettings,
  table, name, position: string): Runes =

    case table:
      of "BuildOnSave":
        case name:
          of "workspaceRoot":
            return s.buildOnSave.workspaceRoot
          of "command":
            return s.buildOnSave.command
      of "Highlight":
        case name:
          of "reservedWords":
            for i, reservedWord in s.highlight.reservedWords:
              result &= reservedWord.word.toRunes & ru" "
      of "AutoBackup":
        case name:
          of "backupDir":
            return s.autoBackup.backupDir
      of "QuickRun":
        case name:
          of "nimAdvancedCommand":
            return s.quickRun.nimAdvancedCommand.toRunes
          of "ClangOptions":
            return s.quickRun.clangOptions.toRunes
          of "CppOptions":
            return s.quickRun.cppOptions.toRunes
          of "NimOptions":
            return s.quickRun.nimOptions.toRunes
          of "shOptions":
            return s.quickRun.shOptions.toRunes
          of "bashOptions":
            return s.quickRun.bashOptions.toRunes
      of "Theme":
        return s.getCurrentColorVal(name, position).toRunes

proc editTextSetting(status: var EditorStatus, table, name, position: string) =
  const MinColumn = NumOfIndent + positionOfSetVal()

  currentMainWindowNode.currentColumn =
    positionOfSetVal() +
    NumOfIndent +
    getTextSettingVal(status.settings, table, name, position).len

  if not status.settings.disableChangeCursor:
    changeCursorType(status.settings.insertModeCursor)

  var
    buffer = getTextSettingVal(status.settings, table, name, position)
    isCancel = false
    isBreak = false
  while not isBreak and not isCancel:
    # Edit text settings

    status.update

    # status.update clears the cursor, so enable it every time.
    setCursor(true)

    var key = ERR_KEY
    while key == ERR_KEY:
      key = currentMainWindowNode.getKey

    if isResizeKey(key):
      status.resize
    elif isEscKey(key):
      isCancel = true
    elif isEnterKey(key):
      isBreak = true

    elif isLeftKey(key):
      if MinColumn < currentMainWindowNode.currentColumn:
        currentMainWindowNode.keyLeft
    elif isRightKey(key):
      currentBufStatus.keyRight(currentMainWindowNode)

    elif isBackspaceKey(key):
      let
        autoDeleteParen = false

      if currentMainWindowNode.currentColumn > MinColumn:
        currentBufStatus.keyBackspace(
          currentMainWindowNode,
          autoDeleteParen,
          status.settings.tabStop)

    else:
      buffer &= key
      currentBufStatus.insertCharacter(currentMainWindowNode, key)
      let reservedWords = status.settings.highlight.reservedWords
      currentMainWindowNode.highlight =
        currentBufStatus.buffer.initConfigModeHighlight(
          currentMainWindowNode.currentLine,
          reservedWords)

  currentMainWindowNode.currentColumn = 0

  if isCancel:
    setCursor(false)
  else:
    template buildOnSaveTable() =
      case name:
        of "workspaceRoot":
          status.settings.buildOnSave.workspaceRoot = buffer
        of "command":
          status.settings.buildOnSave.command = buffer
        else:
          discard

    template  highlightTable() =
      case name:
        of "reservedWords":
          status.settings.highlight.reservedWords =
            buffer.splitWhitespace.mapIt(
              ReservedWord(word: $it, color: EditorColorPairIndex.reservedWord))
        else:
          discard

    template autoBackupTable() =
      case name:
        of "backupDir":
          status.settings.autoBackup.backupDir = buffer
        else:
          discard

    template quickRunTable() =
      case name:
        of "nimAdvancedCommand":
          status.settings.quickRun.nimAdvancedCommand = $buffer
        of "ClangOptions":
          status.settings.quickRun.clangOptions = $buffer
        of "CppOptions":
          status.settings.quickRun.cppOptions = $buffer
        of "NimOptions":
          status.settings.quickRun.nimOptions = $buffer
        of "shOptions":
          status.settings.quickRun.shOptions = $buffer
        of "bashOptions":
          status.settings.quickRun.bashOptions = $buffer
        else:
          discard

    template themeTable() =
      let r = status.settings.changeThemeTableSetting(
        position.toColorLayer.get,
        name,
        $buffer)
      if r.isOk:
        # TODO: Add error handling
        discard status.changeTheme
      else:
        status.commandLine.writeError(ru"Invalid value")

    # Change setting
    case table:
      of "BuildOnSave":
        buildOnSaveTable()
      of "Highlight":
        highlightTable()
      of "AutoBackup":
        autoBackupTable()
      of "QuickRun":
        quickRunTable()
      of "Theme":
        themeTable()
      else:
        discard

proc editEnumAndBoolSettings(
  status: var EditorStatus,
  lineSplit: seq[Runes],
  selectedTable, selectedSetting: string,
  settingValues: seq[Runes]) =

    const
      Margin = 1
    let
      h = min(currentMainWindowNode.h, settingValues.len)
      w = min(currentMainWindowNode.w, maxLen(settingValues) + (Margin * 2))
      (absoluteY, absoluteX) = currentMainWindowNode.absolutePosition(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)
      y = absoluteY
      x = absoluteX + positionOfSetVal() + NumOfIndent - Margin

    var
      popupWindow = initPopupWindow(Position(y: y, x: x), Size(h: h, w: w))
      suggestIndex = 0

    while settingValues.len > 1:
      popupWindow.currentLine = some(suggestIndex)
      popupWindow.buffer = settingValues

      popupWindow.update

      let key = currentMainWindowNode.getKey

      if isTabKey(key) or isDownKey(key) or key == ord('j'):
        if suggestIndex == settingValues.high: suggestIndex = 0
        else: suggestIndex.inc
      elif isShiftTab(key) or isUpKey(key) or key == ord('k'):
        if suggestIndex == 0: suggestIndex = settingValues.high
        else: suggestIndex.dec
      elif isEnterKey(key):
        let
          settingVal = $settingValues[suggestIndex]
          # position is "foreground" or "background" or ""
          position = if selectedTable == "Theme": $lineSplit[0] else: ""
        status.changeEditorSettings(
          selectedTable, selectedSetting, position, settingVal)
        break
      elif isEscKey(key):
        break

    if not status.popupWindow.isNil:
      status.popupWindow.deleteWindow

proc selectAndChangeEditorSettings(status: var EditorStatus, arrayIndex: int) =
  let
    currentLine = currentMainWindowNode.currentLine
    line = currentBufStatus.buffer[currentLine]
    lineSplit = line.splitWhitespace

  if lineSplit.len < 2: return

  let
    selectedTable = getTableName(
      currentBufStatus.buffer,
      currentMainWindowNode.currentLine)

    selectedSetting =
      if selectedTable == "Theme":
        currentBufStatus.buffer.getEditorColorPairIndexStr(
          lineSplit,currentLine)
       else:
        $lineSplit[0]

    settingType = getSettingType(selectedTable, selectedSetting)

    # position is "foreground" or "background" or ""
    position = if selectedTable == "Theme": $lineSplit[0] else: ""
    settingValues = getSettingValues(
      status.settings,
      settingType,
      selectedTable,
      selectedSetting,
      position)

  case settingType:
    of SettingType.number:
      status.editFiguresSetting(selectedTable, selectedSetting)
    of SettingType.text:
      status.editTextSetting(selectedTable, selectedSetting, position)
    else:
      status.editEnumAndBoolSettings(
        lineSplit,
        selectedTable,
        selectedSetting,
        settingValues)

proc initStandardTableBuffer(settings: EditorSettings): seq[Runes] =
  result.add(ru"Standard")

  for name in StandardTableNames:
    let
      nameStr = Indent & $name
      space = " ".repeat(positionOfSetVal() - len($name))
    case $name:
      of "theme":
        result.add(ru nameStr & space & $settings.editorColorTheme)
      of "number":
        result.add(ru nameStr & space & $settings.view.lineNumber)
      of "currentNumber":
        result.add(ru nameStr & space & $settings.view.currentLineNumber)
      of "cursorLine":
        result.add(ru nameStr & space & $settings.view.cursorLine)
      of "statusLine":
        result.add(ru nameStr & space & $settings.statusLine.enable)
      of "tabLine":
        result.add(ru nameStr & space & $settings.tabLine.enable)
      of "syntax":
        result.add(ru nameStr & space & $settings.syntax)
      of "indentationLines":
        result.add(ru nameStr & space & $settings.view.indentationLines)
      of "tabStop":
        result.add(ru nameStr & space & $settings.tabStop)
      of "sidebar":
        result.add(ru nameStr & space & $settings.view.sidebar)
      of "autoCloseParen":
        result.add(ru nameStr & space & $settings.autoCloseParen)
      of "autoIndent":
        result.add(ru nameStr & space & $settings.autoIndent)
      of "ignorecase":
        result.add(ru nameStr & space & $settings.ignorecase)
      of "smartcase":
        result.add(ru nameStr & space & $settings.smartcase)
      of "disableChangeCursor":
        result.add(ru nameStr & space & $settings.disableChangeCursor)
      of "defaultCursor":
        result.add(ru nameStr & space & $settings.defaultCursor)
      of "normalModeCursor":
        result.add(ru nameStr & space & $settings.normalModeCursor)
      of "insertModeCursor":
        result.add(ru nameStr & space & $settings.insertModeCursor)
      of "autoSave":
        result.add(ru nameStr & space & $settings.autoSave)
      of "autoSaveInterval":
        result.add(ru nameStr & space & $settings.autoSaveInterval)
      of "liveReloadOfConf":
        result.add(ru nameStr & space & $settings.liveReloadOfConf)
      of "incrementalSearch":
        result.add(ru nameStr & space & $settings.incrementalSearch)
      of "popupWindowInExmode":
        result.add(ru nameStr & space & $settings.popupWindowInExmode)
      of "autoDeleteParen":
        result.add(ru nameStr & space & $settings.autoDeleteParen)
      of "liveReloadOfFile":
        result.add(ru nameStr & space & $settings.liveReloadOfFile)
      of "colorMode":
        result.add(ru nameStr & space & settings.colorMode.toConfigStr)

proc initClipBoardTableBuffer(settings: ClipboardSettings): seq[Runes] =
  result.add(ru"ClipBoard")

  for name in ClipboardTableNames:
    let
      nameStr = Indent & $name
      space = " ".repeat(positionOfSetVal() - len($name))
    case $name:
      of "enable":
        result.add(ru nameStr & space & $settings.enable)
      of "toolOnLinux":
        result.add(ru nameStr & space & $settings.toolOnLinux)

proc initBuildOnSaveTableBuffer(settings: BuildOnSaveSettings): seq[Runes] =
  result.add(ru"BuildOnSave")

  for name in BuildOnSaveTableNames:
    let
      nameStr = Indent & $name
      space = " ".repeat(positionOfSetVal() - len($name))
    case $name:
      of "enable":
        result.add(ru nameStr & space & $settings.enable)
      of "workspaceRoot":
        result.add(ru nameStr & space & $settings.workspaceRoot)
      of "command":
        result.add(ru nameStr & space & $settings.command)

proc initTabLineTableBuffer(settings: EditorSettings): seq[Runes] =
  result.add(ru"TabLine")

  for name in TabLineTableNames:
    let
      nameStr = Indent & $name
      space = " ".repeat(positionOfSetVal() - len($name))
    case $name:
      of "allBuffer":
        result.add(ru nameStr & space & $settings.tabLine.allBuffer)

proc initStatusLineTableBuffer(settings: StatusLineSettings): seq[Runes] =
  result.add(ru"StatusLine")

  for name in StatusLineTableNames:
    let
      nameStr = Indent & $name
      space = " ".repeat(positionOfSetVal() - len($name))
    case $name:
      of "multipleStatusLine":
        result.add(ru nameStr & space & $settings.multipleStatusLine)
      of "merge":
        result.add(ru nameStr & space & $settings.merge)
      of "mode":
        result.add(ru nameStr & space & $settings.mode)
      of "filename":
        result.add(ru nameStr & space & $settings.filename)
      of "chanedMark":
        result.add(ru nameStr & space & $settings.chanedMark)
      of "directory":
        result.add(ru nameStr & space & $settings.directory)
      of "gitChangedLines":
        result.add(ru nameStr & space & $settings.gitChangedLines)
      of "gitBranchName":
        result.add(ru nameStr & space & $settings.gitBranchName)
      of "showGitInactive":
        result.add(ru nameStr & space & $settings.showGitInactive)
      of "showModeInactive":
        result.add(ru nameStr & space & $settings.showModeInactive)
      of "setupText":
        result.add(ru nameStr & space & $settings.setupText)

proc initHighlightTableBuffer(settings: EditorSettings): seq[Runes] =
  result.add(ru"Highlight")

  for name in HighlightTableNames:
    let
      nameStr = Indent & $name
      space = " ".repeat(positionOfSetVal() - len($name))
    case $name:
      of "currentLine":
        result.add(ru nameStr & space & $settings.view.highlightCurrentLine)
      of "replaceText":
        result.add(ru nameStr & space & $settings.highlight.replaceText)
      of "highlightPairOfParen":
        result.add(ru nameStr & space & $settings.highlight.pairOfParen)
      of "fullWidthSpace":
        result.add(ru nameStr & space & $settings.highlight.fullWidthSpace)
      of "trailingSpaces":
        result.add(ru nameStr & space & $settings.highlight.trailingSpaces)
      of "currentWord":
        result.add(ru nameStr & space & $settings.highlight.currentWord)
      of "reservedWords":
        var line = ru nameStr & space
        for reservedWord in settings.highlight.reservedWords:
          line &= ru reservedWord.word & " "

        result.add line

proc initAutoBackupTableBuffer(settings: AutoBackupSettings): seq[Runes] =
  result.add(ru"AutoBackup")

  for name in AutoBackupTableNames:
    let
      nameStr = Indent & $name
      space = " ".repeat(positionOfSetVal() - len($name))
    case $name:
      of "enable":
        result.add(ru nameStr & space & $settings.enable)
      of "idleTime":
        result.add(ru nameStr & space & $settings.idleTime)
      of "interval":
        result.add(ru nameStr & space & $settings.interval)
      of "backupDir":
        result.add(ru nameStr & space & $settings.backupDir)
      of "dirToExclude":
        result.add(ru nameStr & space & $settings.dirToExclude)

proc initQuickRunTableBuffer(settings: QuickRunSettings): seq[Runes] =
  result.add(ru"QuickRun")

  for name in QuickRunTableNames:
    let
      nameStr = Indent & $name
      space = " ".repeat(positionOfSetVal() - len($name))
    case $name:
      of "saveBufferWhenQuickRun":
        result.add(ru nameStr & space & $settings.saveBufferWhenQuickRun)
      of "command":
        result.add(ru nameStr & space & $settings.command)
      of "timeout":
        result.add(ru nameStr & space & $settings.timeout)
      of "nimAdvancedCommand":
        result.add(ru nameStr & space & $settings.nimAdvancedCommand)
      of "clangOptions":
        result.add(ru nameStr & space & $settings.clangOptions)
      of "cppOptions":
        result.add(ru nameStr & space & $settings.cppOptions)
      of "nimOptions":
        result.add(ru nameStr & space & $settings.nimOptions)
      of "shOptions":
        result.add(ru nameStr & space & $settings.shOptions)
      of "bashOptions":
        result.add(ru nameStr & space & $settings.bashOptions)

proc initNotificationTableBuffer(
  settings: NotificationSettings): seq[Runes] =

  result.add(ru"Notification")

  for name in NotificationTableNames:
    let
      nameStr = Indent & $name
      space = " ".repeat(positionOfSetVal() - len($name))
    case $name:
      of "screenNotifications":
        result.add(ru nameStr & space & $settings.screenNotifications)
      of "logNotifications":
        result.add(ru nameStr & space & $settings.logNotifications)
      of "autoBackupScreenNotify":
        result.add(ru nameStr & space & $settings.autoBackupScreenNotify)
      of "autoBackupLogNotify":
        result.add(ru nameStr & space & $settings.autoBackupLogNotify)
      of "autoSaveScreenNotify":
        result.add(ru nameStr & space & $settings.autoSaveScreenNotify)
      of "autoSaveLogNotify":
        result.add(ru nameStr & space & $settings.autoSaveLogNotify)
      of "yankScreenNotify":
        result.add(ru nameStr & space & $settings.yankScreenNotify)
      of "yankLogNotify":
        result.add(ru nameStr & space & $settings.yankLogNotify)
      of "deleteScreenNotify":
        result.add(ru nameStr & space & $settings.deleteScreenNotify)
      of "deleteLogNotify":
        result.add(ru nameStr & space & $settings.deleteLogNotify)
      of "saveScreenNotify":
        result.add(ru nameStr & space & $settings.saveScreenNotify)
      of "saveLogNotify":
        result.add(ru nameStr & space & $settings.saveLogNotify)
      of "quickRunScreenNotify":
        result.add(ru nameStr & space & $settings.quickRunScreenNotify)
      of "quickRunLogNotify":
        result.add(ru nameStr & space & $settings.quickRunLogNotify)
      of "buildOnSaveScreenNotify":
        result.add(ru nameStr & space & $settings.buildOnSaveScreenNotify)
      of "buildOnSaveLogNotify":
        result.add(ru nameStr & space & $settings.buildOnSaveLogNotify)
      of "filerScreenNotify":
        result.add(ru nameStr & space & $settings.filerScreenNotify)
      of "filerLogNotify":
        result.add(ru nameStr & space & $settings.filerLogNotify)
      of "restoreScreenNotify":
        result.add(ru nameStr & space & $settings.restoreScreenNotify)
      of "restoreLogNotify":
        result.add(ru nameStr & space & $settings.restoreLogNotify)

proc initFilerTableBuffer(settings: EditorSettings): seq[Runes] =
  result.add(ru"Filer")

  for name in FilerTableNames:
    let
      nameStr = Indent & $name
      space = " ".repeat(positionOfSetVal() - len($name))
    case $name:
      of "showIcons":
        result.add(ru nameStr & space & $settings.filer.showIcons)

proc initAutocompleteTableBuffer(settings: EditorSettings): seq[Runes] =
  result.add(ru"Autocomplete")

  for name in AutocompleteTableNames:
    let
      nameStr = Indent & $name
      space = " ".repeat(positionOfSetVal() - len($name))
    case $name:
      of "enable":
        result.add(ru nameStr & space & $settings.autocomplete.enable)

proc initPersistTableBuffer(persistSettings: PersistSettings): seq[Runes] =
  result.add(ru"Persist")

  for name in PersistTableNames:
    let
      nameStr = Indent & $name
      space = " ".repeat(positionOfSetVal() - len($name))
    case $name:
      of "exCommand":
        result.add(ru nameStr & space & $persistSettings.exCommand)
      of "exCommandHistoryLimit":
        result.add(ru nameStr & space & $persistSettings.exCommandHistoryLimit)
      of "search":
        result.add(ru nameStr & space & $persistSettings.search)
      of "searchHistoryLimit":
        result.add(ru nameStr & space & $persistSettings.searchHistoryLimit)
      of "cursorPosition":
        result.add(ru nameStr & space & $persistSettings.cursorPosition)

proc initGitTableBuffer(settings: GitSettings): seq[Runes] =
  result.add(ru"Git")

  for name in GitTableNames:
    let
      nameStr = Indent & $name
      space = " ".repeat(positionOfSetVal() - len($name))
    case $name:
      of "showChangedLine":
        result.add(ru nameStr & space & $settings.showChangedLine)
      of "updateInterval":
        result.add(ru nameStr & space & $settings.updateInterval)

proc initSyntaxCheckerTableBuffer(settings: SyntaxCheckerSettings): seq[Runes] =
  result.add(ru"SyntaxChecker")

  for name in SyntaxCheckerTableNames:
    let
      nameStr = Indent & $name
      space = " ".repeat(positionOfSetVal() - len($name))
    case $name:
      of "enable":
        result.add(ru nameStr & space & $settings.enable)

proc initSmoothScrollTableBuffer(settings: SmoothScrollSettings): seq[Runes] =
  result.add(ru"SmoothScroll")

  for name in SmoothScrollTableNames:
    let
      nameStr = Indent & $name
      space = " ".repeat(positionOfSetVal() - len($name))
    case $name:
      of "enable":
        result.add(ru nameStr & space & $settings.enable)
      of "minDelay":
        result.add(ru nameStr & space & $settings.minDelay)
      of "maxDelay":
        result.add(ru nameStr & space & $settings.maxDelay)

proc initStartUpFileOpenTableBuffer(
  settings: StartUpFileOpenSettings): seq[Runes] =
    result.add(ru"StartUp.FileOpen")

    for name in StartUpFileOpenSettingsTableNames:
      let
        nameStr = Indent & $name
        space = " ".repeat(positionOfSetVal() - len($name))
      case name:
        of StartUpFileOpenSettingsTableNames.autoSplit:
          result.add(ru nameStr & space & $settings.autoSplit)
        of StartUpFileOpenSettingsTableNames.splitType:
          result.add(ru nameStr & space & $settings.splitType)

proc initThemeTableBuffer*(s: EditorSettings): seq[Runes] =
  result.add(ru"Theme")

  for pairIndex in EditorColorPairIndex:
    let
      # 10 is "foreground " and "background " length.
      space = " ".repeat(positionOfSetVal() - Indent.len - 10)

      fgHex = s.editorColorTheme.foregroundRgb(pairIndex).toHex
      bgHex = s.editorColorTheme.backgroundRgb(pairIndex).toHex

      fgColorText =
        if fgHex.isSome: fgHex.get
        else: "termDefautFg"

      bgColorText =
        if bgHex.isSome: bgHex.get
        else: "termDefautBg"

    result.add(ru fmt"{Indent}{$pairIndex}")
    result.add(ru fmt"{Indent.repeat(2)}foreground{space}{fgColorText}")
    result.add(ru fmt"{Indent.repeat(2)}background{space}{bgColorText}")

    result.add(ru "")

proc initConfigModeBuffer*(settings: EditorSettings): GapBuffer[Runes] =
  var buffer: seq[Runes]
  buffer.add(initStandardTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initClipBoardTableBuffer(settings.clipboard))

  buffer.add(ru"")
  buffer.add(initBuildOnSaveTableBuffer(settings.buildOnSave))

  buffer.add(ru"")
  buffer.add(initTabLineTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initStatusLineTableBuffer(settings.statusLine))

  buffer.add(ru"")
  buffer.add(initHighlightTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initAutoBackupTableBuffer(settings.autoBackup))

  buffer.add(ru"")
  buffer.add(initQuickRunTableBuffer(settings.quickRun))

  buffer.add(ru"")
  buffer.add(initNotificationTableBuffer(settings.notification))

  buffer.add(ru"")
  buffer.add(initFilerTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initAutocompleteTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initPersistTableBuffer(settings.persist))

  buffer.add(ru"")
  buffer.add(initGitTableBuffer(settings.git))

  buffer.add ru""
  buffer.add initSyntaxCheckerTableBuffer(settings.syntaxChecker)

  buffer.add ru""
  buffer.add initSmoothScrollTableBuffer(settings.smoothScroll)

  buffer.add ru""
  buffer.add initStartUpFileOpenTableBuffer(settings.startUp.fileOpen)

  buffer.add(ru"")
  buffer.add(initThemeTableBuffer(settings))

  result = initGapBuffer(buffer)

proc keyUp(bufStatus: BufferStatus, windowNode: var WindowNode) =
  let currentLine = windowNode.currentLine
  if currentLine > 1:
    bufStatus.keyUp(windowNode)

    # Skip empty line and table name line
    while bufStatus.buffer[windowNode.currentLine].len == 0 or
          bufStatus.buffer[windowNode.currentLine][0] != ' ':
      bufStatus.keyUp(windowNode)

proc keyDown(bufStatus: BufferStatus, windowNode: var WindowNode) =
  let currentLine = windowNode.currentLine
  if currentLine < bufStatus.buffer.high - 1:
    bufStatus.keyDown(windowNode)

    # Skip empty line and table name line
    while bufStatus.buffer[windowNode.currentLine].len == 0 or
          bufStatus.buffer[windowNode.currentLine][0] != ' ':
      bufStatus.keyDown(windowNode)

# Count number of values in the array setting.
proc getNumOfValueOfArraySetting(line: Runes): int =
  # 1 is the name of the setting
  line.splitWhitespace.len - 1

proc changeModeToSearchForwardMode(
  bufStatus: var BufferStatus,
  commandLine: var CommandLine) =

    bufStatus.changeMode(Mode.searchForward)
    commandLine.clear
    commandLine.setPrompt(SearchForwardModePrompt)

proc changeModeToSearchBackwardMode(
  bufStatus: var BufferStatus,
  commandLine: var CommandLine) =

    bufStatus.changeMode(Mode.searchBackward)
    commandLine.clear
    commandLine.setPrompt(SearchBackwardModePrompt)

proc isConfigModeCommand*(command: Runes): InputState =
  result = InputState.Invalid

  if command.len == 1:
    let key = command[0]
    if isControlK(key) or
       isControlJ(key) or
       key == ord(':') or
       key == ord('h') or isLeftKey(key) or
       key == ord('l') or isRightKey(key) or
       isEnterKey(key) or
       isControlU(key) or
       isControlD(key) or
       isPageUpKey(key) or
       isPageDownKey(key) or ## Page down and Ctrl - F
       key == ord('k') or isUpKey(key) or
       key == ord('j') or isDownKey(key) or
       key == ord('G') or
       key == ord('/') or
       key == ord('?'):
         return InputState.Valid
    elif key == ord('g'):
      return InputState.Continue
  elif command.len == 2:
    if command[0] == ord('g'):
      if command[1] == ord('g'):
        return InputState.Valid

proc execConfigCommand*(status: var EditorStatus, command: Runes) =

  # TODO: Move or Remove
  template getSettingType(): SettingType =
    let buffer = currentBufStatus.buffer
    buffer.getSettingType(currentMainWindowNode.currentLine)

  # TODO: Move or Remove
  template getNumOfValueOfArraySetting(): int =
    let
      currentLine = currentMainWindowNode.currentLine
      line = currentBufStatus.buffer[currentLine]
    getNumOfValueOfArraySetting(line)

  # TODO: Fix or Remove
  # For SettingType.Array
  var arrayIndex = 0

  if command.len == 1:
    let key = command[0]
    if isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow
    elif key == ord(':'):
      status.changeMode(Mode.ex)

    elif isEnterKey(key):
      status.selectAndChangeEditorSettings(arrayIndex)
      currentBufStatus.buffer = initConfigModeBuffer(status.settings)
      currentBufStatus.isUpdate = true
    elif isControlU(key):
      status.halfPageUp
    elif isControlD(key):
      status.halfPageDown
    elif isPageUpKey(key):
      status.pageUp
    elif isPageDownKey(key): ## Page down and Ctrl - F
      status.pageDown
    elif key == ord('k') or isUpKey(key):
      currentBufStatus.keyUp(currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      currentBufStatus.keyDown(currentMainWindowNode)
    elif key == ord('G'):
      currentBufStatus.moveToLastLine(currentMainWindowNode)
    elif key == ord('/'):
      currentBufStatus.changeModeToSearchForwardMode(status.commandLine)
    elif key == ord('?'):
      currentBufStatus.changeModeToSearchBackwardMode(status.commandLine)
  elif command.len == 2:
    if command[0] == ord('g'):
      if command[1] == ord('g'):
        currentBufStatus.moveToFirstLine(currentMainWindowNode)
