import std/[terminal, times, strutils]
import gapbuffer, ui, editorstatus, unicodeext, window, movement, settings,
       bufferstatus, color, highlight, editor, search

type standardTableNames {.pure.} = enum
  theme
  number
  currentNumber
  cursorLine
  statusLine
  tabLine
  syntax
  indentationLines
  tabStop
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
  popUpWindowInExmode
  autoDeleteParen
  smoothScroll
  smoothScrollSpeed

type clipboardTableNames {.pure.} = enum
  enable
  toolOnLinux

type buildOnSaveTableNames {.pure.}= enum
  enable
  workspaceRoot
  command

type tabLineTableNames {.pure.} = enum
  allBuffer

type statusLineTableNames {.pure.} = enum
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
  gitbranchName
  showGitInactive
  showModeInactive

type highlightTableNames {.pure.} = enum
  currentLine
  fullWidthSpace
  trailingSpaces
  currentWord
  replaceText
  pairOfParen
  reservedWord

type autoBackupTableNames {.pure.} = enum
  enable
  idleTime
  interval
  backupDir
  dirToExclude

type quickRunTableNames {.pure.} = enum
  saveBufferWhenQuickRun
  command
  timeout
  nimAdvancedCommand
  ClangOptions
  CppOptions
  NimOptions
  shOptions
  bashOptions

type notificationTableNames {.pure.} = enum
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

type filerTableNames {.pure.} = enum
  showIcons

type autocompleteTableNames {.pure.} = enum
  enable

type persistTableSettings {.pure.} = enum
  exCommand
  search
  cursorPosition

type themeTableNames {.pure.} = enum
  editorBg
  lineNum
  currentLineNum
  statusLineNormalMode
  statusLineModeNormalMode
  statusLineNormalModeInactive
  statusLineInsertMode
  statusLineModeInsertMode
  statusLineInsertModeInactive
  statusLineVisualMode
  statusLineModeVisualMode
  statusLineVisualModeInactive
  statusLineReplaceMode
  statusLineModeReplaceMode
  statusLineReplaceModeInactive
  statusLineFilerMode
  statusLineModeFilerMode
  statusLineFilerModeInactive
  statusLineExMode
  statusLineModeExMode
  statusLineExModeInactive
  statusLineGitBranch
  tab
  currentTab
  commandBar
  errorMessage
  searchResult
  visualMode
  defaultChar
  keyword
  functionName
  typeName
  boolean
  specialVar
  builtin
  stringLit
  decNumber
  comment
  longComment
  whitespace
  preprocessor
  pragma
  currentFile
  file
  dir
  pcLink
  popUpWindow
  popUpWinCurrentLine
  replaceText
  parenText
  currentWord
  highlightFullWidthSpace
  highlightTrailingSpaces
  reservedWord
  currentSetting

type SettingType {.pure.} = enum
  None
  Bool
  Enum
  Number
  String
  Array

const numOfIndent = 2

proc calcPositionOfSettingValue(): int {.compileTime.} =
  var names: seq[string]

  for name in standardTableNames: names.add($name)
  for name in clipboardTableNames: names.add($name)
  for name in buildOnSaveTableNames: names.add($name)
  for name in tabLineTableNames: names.add($name)
  for name in highlightTableNames: names.add($name)
  for name in autoBackupTableNames: names.add($name)
  for name in quickRunTableNames: names.add($name)
  for name in notificationTableNames: names.add($name)
  for name in filerTableNames: names.add($name)
  for name in themeTableNames: names.add($name)

  for name in names:
    if result < name.len: result = name.len

  result += numOfIndent

const
  positionOfSetVal = calcPositionOfSettingValue()
  indent = "  "

proc getColorThemeSettingValues(currentVal: ColorTheme): seq[seq[Rune]] =
  result.add ru $currentVal
  for theme in ColorTheme:
    if theme != currentVal:
      result.add ru $theme

proc getCursorTypeSettingValues(currentVal: CursorType): seq[seq[Rune]] =
  result.add ru $currentVal
  for cursorType in CursorType:
    if $cursorType != $currentVal:
      result.add ru $cursorType

proc getStandardTableSettingValues(settings: EditorSettings,
                                   name: string): seq[seq[Rune]] =
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
      of "popUpWindowInExmode":
        currentVal = settings.popUpWindowInExmode
      of "autoDeleteParen":
        currentVal = settings.autoDeleteParen
      of "smoothScroll":
        currentVal = settings.smoothScroll
      else:
        return

    if currentVal:
      result = @[ru "true", ru "false"]
    else:
      result = @[ru "false", ru "true"]

proc getClipboardTableSettingsValues(settings: ClipBoardSettings,
                                     name: string): seq[seq[Rune]] =

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

proc getBuildOnSaveTableSettingValues(settings: BuildOnSaveSettings,
                                      name: string): seq[seq[Rune]] =

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

proc getTabLineTableSettingValues(settings: TabLineSettings,
                                  name: string): seq[seq[Rune]] =

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

proc getStatusLineTableSettingValues(settings: StatusLineSettings,
                                     name: string): seq[seq[Rune]] =

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
    of "line":
      currentVal = settings.line
    of "column":
      currentVal = settings.column
    of "encoding":
      currentVal = settings.characterEncoding
    of "language":
      currentVal = settings.language
    of "directory":
      currentVal = settings.directory
    of "gitbranchName":
      currentVal = settings.gitbranchName
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

proc getHighlightTableSettingValues(settings: EditorSettings,
                                    name: string): seq[seq[Rune]] =

  var currentVal: bool
  case name:
    of "currentLine":
      currentVal = settings.view.highlightCurrentLine
    of "fullWidthSpace":
      currentVal = settings.highlightSettings.fullWidthSpace
    of "trailingSpaces":
      currentVal = settings.highlightSettings.trailingSpaces
    of "currentWord":
      currentVal = settings.highlightSettings.currentWord
    of "replaceText":
      currentVal = settings.highlightSettings.replaceText
    of "pairOfParen":
      currentVal = settings.highlightSettings.pairOfParen
    else:
      return

  if currentVal:
    result = @[ru "true", ru "false"]
  else:
    result = @[ru "false", ru "true"]

proc getAutoBackupTableSettingValues(settings: AutoBackupSettings,
                                     name: string,
                                     settingType: SettingType): seq[seq[Rune]] =

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

proc getQuickRunTableSettingValues(settings: QuickRunSettings,
                                   name: string,
                                   settingType: SettingType): seq[seq[Rune]] =

  case name:
    of "saveBufferWhenQuickRun":
      let currentVal = settings.saveBufferWhenQuickRun
      if currentVal:
        result = @[ru "true", ru "false"]
      else:
        result = @[ru "false", ru "true"]
    of "nimAdvancedCommand":
      result = @[ru settings.nimAdvancedCommand]
    of "ClangOptions":
      result = @[ru settings.ClangOptions]
    of "CppOptions":
      result = @[ru settings.CppOptions]
    of "NimOptions":
      result = @[ru settings.NimOptions]
    of "shOptions":
      result = @[ru settings.shOptions]
    of "bashOptions":
      result = @[ru settings.bashOptions]
    else:
      return

proc getNotificationTableSettingValues(settings: NotificationSettings,
                                       name: string): seq[seq[Rune]] =

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

proc getFilerTableSettingValues(settings: FilerSettings,
                                name: string): seq[seq[Rune]] =

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

proc getAutocompleteTableSettingValues(settings: AutocompleteSettings,
                                       name: string): seq[seq[Rune]] =

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

proc getPersistTableSettingsValues(settings: PersistSettings,
                                   name: string): seq[seq[Rune]] =

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

proc getThemeTableSettingValues(settings: EditorSettings,
                                name, position: string): seq[seq[Rune]] =

  proc getCurrentVal(theme: ColorTheme, name, position: string): Color =
    if name == "editorBg":
      result = ColorThemeTable[theme].editorBg
    else:
      let
        colorPair = parseEnum[EditorColorPair]($name)
        (fg, bg) = getColorFromEditorColorPair(theme, colorPair)
      result = if position == "foreground": fg else: bg

  if name != "" or position != "":
    let
      theme = settings.editorColorTheme
      currentVal = getCurrentVal(theme, name, position)

    result.add ru $currentVal
    for color in Color:
      if $color != $currentVal:
        result.add ru $color

proc getSettingValues(settings: EditorSettings,
                      settingType: SettingType,
                      table, name, position: string): seq[seq[Rune]] =

  case table:
    of "Standard":
      result = settings.getStandardTableSettingValues(name)
    of "ClipBoard":
      result = settings.clipboard.getClipboardTableSettingsValues(name)
    of "BuildOnSave":
      result = settings.buildOnSave.getBuildOnSaveTableSettingValues(name)
    of "TabLine":
      result = settings.tabline.getTabLineTableSettingValues(name)
    of "StatusLine":
      result = settings.statusLine.getStatusLineTableSettingValues(name)
    of "Highlight":
      result = settings.getHighlightTableSettingValues(name)
    of "AutoBackup":
      let settings = settings.autoBackupSettings
      result = settings.getAutoBackupTableSettingValues(name, settingType)
    of "QuickRun":
      let quickRunSettings = settings.quickRunSettings
      result = quickRunSettings.getQuickRunTableSettingValues(name, settingType)
    of "Notification":
      let notificationSettings = settings.notificationSettings
      result = notificationSettings.getNotificationTableSettingValues(name)
    of "Filer":
      result = settings.filerSettings.getFilerTableSettingValues(name)
    of "Autocomplete":
      let autocompleteSettings = settings.autocompleteSettings
      result = autocompleteSettings.getAutocompleteTableSettingValues(name)
    of "Persist":
      let persistSettings = settings.persist
      result = persistSettings.getPersistTableSettingsValues(name)
    of "Theme":
      result = settings.getThemeTableSettingValues(name, position)

proc maxLen(list: seq[seq[Rune]]): int =
  for r in list:
    if r.len > result:
      result = r.len + 2

proc getTableName(buffer: GapBuffer[seq[Rune]], line: int): string =
  # Search table name from configuration mode buffer
  for i in countDown(line, 0):
    if buffer[i].len > 0 and buffer[i][0] != ru ' ':
      return $buffer[i]

# return (start, end: int)
proc getCurrentArraySettingValueRange(reservedWords: seq[ReservedWord],
                                      arrayIndex: int): (int, int) =

  const spaceLengh = 1

  result[0] = positionOfSetVal + numOfIndent

  for i in 0 .. arrayIndex:
    # Add space length
    if i > 0:
      result[0] += reservedWords[i - 1].word.ru.len + spaceLengh

  result[1] = result[0] + reservedWords[arrayIndex].word.ru.high

proc initConfigModeHighlight[T](buffer: T,
                                currentLine, arrayIndex: int,
                                reservedWords: seq[ReservedWord]): Highlight =

  for i in 0 ..< buffer.len:
    if i == currentLine:
        result.colorSegments.add(
          ColorSegment(
            firstRow: i,
            firstColumn: 0,
            lastRow: i,
            lastColumn: buffer[i].len,
            color: EditorColorPair.defaultChar))

        if buffer[currentLine].splitWhitespace.len > 1 and
           SettingType.Array == buffer.getSettingType(currentLine):
          let
            range = getCurrentArraySettingValueRange(reservedWords, arrayIndex)
            start = range[0]
            `end` = range[1]

          result.overwrite(
            ColorSegment(
              firstRow: i,
              firstColumn: start,
              lastRow: i,
              lastColumn: `end`,
              color: EditorColorPair.currentSetting))
        else:
          result.overwrite(
            ColorSegment(
              firstRow: i,
              firstColumn: numOfIndent + positionOfSetVal,
              lastRow: i,
              lastColumn: buffer[i].len,
              color: EditorColorPair.currentSetting))
    else:
      result.colorSegments.add(
        ColorSegment(
          firstRow: i,
          firstColumn: 0,
          lastRow: i,
          lastColumn: buffer[i].len,
          color: EditorColorPair.defaultChar))

proc changeStandardTableSetting(settings: var EditorSettings,
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
      settings.tabline.enable = parseBool(settingVal)
    of "syntax":
      settings.syntax = parseBool(settingVal)
    of "indentationLines":
      settings.view.indentationLines = parseBool(settingVal)
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
    of "popUpWindowInExmode":
      settings.popUpWindowInExmode = parseBool(settingVal)
    of "autoDeleteParen":
      settings.autoDeleteParen = parseBool(settingVal)
    of "smoothScroll":
      settings.smoothScroll = parseBool(settingVal)
    else:
      discard

proc changeClipBoardTableSettings(settings: var ClipBoardSettings,
                                  settingName, settingVal: string) =

  case settingName:
    of "enable":
      settings.enable = parseBool(settingVal)
    of "toolOnLinux":
      let name = if settingVal == "wl-clipboard": "wlClipboard" else: settingVal
      settings.toolOnLinux = parseEnum[ClipboardToolOnLinux](name)
    else:
      discard

proc changeBuildOnSaveTableSetting(settings: var BuildOnSaveSettings,
                                   settingName, settingVal: string) =

  case settingName:
    of "enable":
      settings.enable = parseBool(settingVal)
    else:
      discard

proc changeTabLineTableSetting(settings: var TabLineSettings,
                               settingName, settingVal: string) =

  case settingName:
    of "allBuffer":
      settings.allBuffer = parseBool(settingVal)
    else:
      discard

proc changeStatusLineTableSetting(settings: var StatusLineSettings,
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
  of "line":
    settings.line = parseBool(settingVal)
  of "column":
    settings.column = parseBool(settingVal)
  of "encoding":
    settings.characterEncoding = parseBool(settingVal)
  of "language":
    settings.language = parseBool(settingVal)
  of "directory":
    settings.directory = parseBool(settingVal)
  of "gitbranchName":
    settings.gitbranchName = parseBool(settingVal)
  of "showGitInactive":
    settings.showGitInactive = parseBool(settingVal)
  of "showModeInactive":
    settings.showModeInactive = parseBool(settingVal)
  else:
    discard

proc changeHighlightTableSetting(settings: var EditorSettings,
                                 settingName, settingVal: string) =

  case settingName:
    of "currentLine":
      settings.view.highlightCurrentLine = parseBool(settingVal)
    of "fullWidthSpace":
      settings.highlightSettings.fullWidthSpace = parseBool(settingVal)
    of "trailingSpaces":
      settings.highlightSettings.trailingSpaces = parseBool(settingVal)
    of "replaceText":
      settings.highlightSettings.replaceText = parseBool(settingVal)
    of "pairOfParen":
      settings.highlightSettings.pairOfParen = parseBool(settingVal)
    of "currentWord":
      settings.highlightSettings.currentWord = parseBool(settingVal)
    of "reservedWord":
      discard
    else:
      discard

proc changeBackupTableSetting(settings: var AutoBackupSettings,
                              settingName, settingVal: string) =

  case settingName:
    of "enable":
      settings.enable = parseBool(settingVal)
    else:
      discard

proc changeQuickRunTableSetting(settings: var QuickRunSettings,
                                settingName, settingVal: string) =

  case settingName:
    of "saveBufferWhenQuickRun":
      settings.saveBufferWhenQuickRun = parseBool(settingVal)
    else:
      discard

proc changeNotificationTableSetting(settings: var NotificationSettings,
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

proc changeFilerTableSetting(settings: var FilerSettings,
                             settingName, settingVal: string) =

  case settingName:
    of "showIcons":
      settings.showIcons = parseBool(settingVal)
    else:
      discard

proc changeAutoCompleteTableSetting(settings: var AutocompleteSettings,
                                    settingName, settingVal: string) =

  case settingName:
    of "enable":
      settings.enable = parseBool(settingVal)
    else:
      discard

proc changePerSistTableSettings(settings: var PersistSettings,
                                settingName, settingVal: string) =

  case settingName:
    of "exCommand":
      settings.exCommand = parseBool(settingVal)
    of "search":
      settings.search = parseBool(settingVal)
    of "cursorPosition":
      settings.cursorPosition = parseBool(settingVal)
    else:
      discard

proc changeThemeTableSetting(settings: var EditorSettings,
                             settingName, position, settingVal: string) =

  let theme = settings.editorColorTheme
  case settingName:
    of "editorBg":
      ColorThemeTable[theme].editorBg = parseEnum[Color](settingVal)
    else:
      let
        color = parseEnum[Color](settingVal)
        editoColor = if position == "background" and settingVal != "editorBg":
                       settingName & "Bg"
                     else:
                       settingName

      for name, _ in ColorThemeTable[theme].fieldPairs:
        if editoColor == name:
          setColor(theme, name, color)

proc changeEditorSettings(status: var EditorStatus,
                          table, settingName, position, settingVal: string) =

  template settings: var EditorSettings = status.settings

  template changeStandardTableSetting() =
    let currentTheme = status.settings.editorColorTheme

    status.settings.changeStandardTableSetting(settingName, settingVal)

    if status.settings.editorColorTheme != currentTheme:
      status.changeTheme

  template clipboardSettings: var ClipBoardSettings =
    status.settings.clipboard

  template buildOnSaveSettings: var BuildOnSaveSettings =
    status.settings.buildOnSave

  template tablineSettings: var TabLineSettings =
    status.settings.tabline

  template statusLineSettings: var StatusLineSettings =
    status.settings.statusLine

  template autoBackupSettings: var AutoBackupSettings =
    status.settings.autoBackupSettings

  template quickRunSettings: var QuickRunSettings =
    status.settings.quickRunSettings

  template notificationSettings: var NotificationSettings =
    status.settings.notificationSettings

  template filerSettings: var FilerSettings =
    status.settings.filerSettings

  template autocompleteSettings: var AutocompleteSettings =
    status.settings.autocompleteSettings

  template persistSettings: var PersistSettings =
    status.settings.persist

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
      notificationSettings.changeNotificationTableSetting(settingName,
                                                          settingVal)
    of "Filer":
      filerSettings.changeFilerTableSetting(settingName, settingVal)
    of "Autocomplete":
      autocompleteSettings.changeAutoCompleteTableSetting(settingName, settingVal)
    of "Persist":
      persistSettings.changePerSistTableSettings(settingName, settingVal)
    of "Theme":
      settings.changeThemeTableSetting(settingName, position, settingVal)
      status.changeTheme
    else:
      discard

proc getSettingType(table, name: string): SettingType =
  template standardTable() =
    case name:
      of "theme",
         "defaultCursor",
         "normalModeCursor",
         "insertModeCursor": result = SettingType.Enum
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
         "popUpWindowInExmode",
         "autoDeleteParen",
         "systemClipboard",
         "smoothScroll": result = SettingType.Bool
      of "tabStop",
         "autoSaveInterval",
         "smoothScrollSpeed": result = SettingType.Number
      else:
        result = SettingType.None

  template clipboardTable() =
    case name:
      of "enable":
        result = SettingType.Bool
      of "toolOnLinux":
        result = SettingType.Enum
      else:
        result = SettingType.None

  template buildOnSaveTable() =
    case name:
      of "enable":
        result = SettingType.Bool
      of "workspaceRoot",
         "command":
        result = SettingType.String
      else:
        result = SettingType.None

  template tablineTable() =
    case name:
      of "allBuffer":
        result = SettingType.Bool
      else:
        result = SettingType.None

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
         "gitbranchName",
         "showGitInactive",
         "showModeInactive": result = SettingType.Bool
      else:
        result = SettingType.None

  template highlightTable() =
    case name:
      of "currentLine",
         "fullWidthSpace",
         "trailingSpaces",
         "currentWord",
         "replaceText",
         "pairOfParen": result = SettingType.Bool
      of "reservedWord": result = SettingType.Array
      else:
        result = SettingType.None

  template autoBackupTable() =
    case name:
      of "enable":
        result = SettingType.Bool
      of "idleTime",
         "interval":
        result = SettingType.Number
      of "backupDir":
        result = SettingType.String
      else:
        result = SettingType.None

  template quickRunTable() =
    case name:
      of "saveBufferWhenQuickRun":
        result = SettingType.Bool
      of "timeout":
        result = SettingType.Number
      of "nimAdvancedCommand",
         "ClangOptions",
         "CppOptions",
         "NimOptions",
         "shOptions",
         "bashOptions":
           result = SettingType.String
      else:
        result = SettingType.None

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
         "restoreLogNotify": result = SettingType.Bool
      else:
        result = SettingType.None

  template filerTable() =
    case name:
      of "showIcons":
        result = SettingType.Bool
      else:
        result = SettingType.None

  template autocompleteTable() =
    case name:
      of "enable":
        result = SettingType.Bool
      else:
        result = SettingType.None

  template themeTable() =
    for color in Color:
      if name == $color:
        return SettingType.Enum
    result = SettingType.None

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
    of "Theme":
      themeTable()

proc getEditorColorPairStr(buffer: GapBuffer[seq[Rune]],
                             lineSplit: seq[seq[Rune]],
                             currentLine: int): string =

  if (lineSplit[0] == ru "foreground") or
     (buffer[currentLine - 2] == ru "Theme"):
    return $(buffer[currentLine - 1].splitWhitespace)[0]
  else:
    return $(buffer[currentLine - 2].splitWhitespace)[0]

proc getSettingType(buffer: GapBuffer[seq[Rune]],
                    currentLine: int): SettingType =

  let
    lineSplit = buffer[currentLine].splitWhitespace

    selectedTable = getTableName(buffer, currentLine)
    selectedSetting = if selectedTable == "Theme":
                        buffer.getEditorColorPairStr(lineSplit,currentLine)
                      else:
                        $lineSplit[0]

  return getSettingType(selectedTable, selectedSetting)

proc insertCharacter(bufStatus: var BufferStatus,
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

proc editFiguresSetting(status: var EditorStatus,
                        table, name: string,
                        arrayIndex: int) =

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
            of "smoothScrollSpeed": settings.smoothScrollSpeed
            else: 0

        of "AutoBackup":
          case name:
            of "idleTime": settings.autoBackupSettings.idleTime
            of "interval": settings.autoBackupSettings.interval
            else: 0

        of "QuickRun":
          case name:
            of "timeout": settings.quickRunSettings.timeout
            else: 0
        else: 0

    let
      val = getSettingVal()
      col = positionOfSetVal + numOfIndent + ($val).len
    currentMainWindowNode.currentColumn = col

  var
    numStr = ""
    isCancel = false
    isBreak = false
  while not isBreak and not isCancel:
    status.update

    var key = errorKey
    while key == errorKey:
      key = currentMainWindowNode.getKey

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEscKey(key):
      isCancel = true
    elif isEnterKey(key):
      isBreak = true

    elif isLeftKey(key):
      moveToLeft()
    elif isRightkey(key):
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
      let reservedWords = status.settings.highlightSettings.reservedWords
      currentMainWindowNode.highlight =
        currentBufStatus.buffer.initConfigModeHighlight(currentLine,
                                                        arrayIndex,
                                                        reservedWords)

  if not isCancel:
    let number = try: parseInt(numStr)
                 except ValueError: return

    template standardTable() =
      case name:
        of "tabStop":
          status.settings.tabStop = number
          status.settings.view.tabStop = number
        of "autoSaveInterval":
          status.settings.autoSaveInterval = number
        of "smoothScrollSpeed":
          status.settings.smoothScrollSpeed = number
        else:
          discard

    template autoBackupTable() =
      case name:
        of "idleTime":
          status.settings.autoBackupSettings.idleTime = number
        of "interval":
          status.settings.autoBackupSettings.interval = number
        else:
          discard

    template quickRunTable() =
      case name:
        of "timeout":
          status.settings.quickRunSettings.timeout = number
        else:
          discard

    # Change setting
    case table:
      of "Standard":
        standardTable()
      of "AutoBackup":
        autoBackupTable()
      of "QuickRun":
        quickRunTable()
      else:
        discard

  setCursor(false)
  currentMainWindowNode.currentColumn = 0
  if not status.settings.disableChangeCursor:
    changeCursorType(status.settings.normalModeCursor)

proc editStringSetting(status: var EditorStatus,
                       table, name: string,
                       arrayIndex: int) =

  setCursor(true)
  if not status.settings.disableChangeCursor:
    changeCursorType(status.settings.insertModeCursor)

  let
    currentLine = currentMainWindowNode.currentLine
    minColumn = numOfIndent + positionOfSetVal

  template moveToLeft() =
    if minColumn > currentMainWindowNode.currentColumn:
      currentMainWindowNode.keyLeft

  # Set currentColumn
  block:
    let settings = status.settings
    template getSettingVal: seq[Rune] =
      case table:
        of "BuildOnSave":
          case name:
            of "workspaceRoot":
              settings.buildOnSave.workspaceRoot
            of "command":
              settings.buildOnSave.command
            else: ru ""
        of "Highlight":
          case name:
            of "reservedWord":
              var val = ru ""
              for i in 0 .. arrayIndex:
                if i > 0: val &= ru " "
                val &= settings.highlightSettings.reservedWords[i].word.ru
              # return val
              val
            else: ru ""
        of "AutoBackup":
          case name:
            of "backupDir":
              settings.autoBackupSettings.backupDir
            else: ru ""
        of "QuickRun":
          case name:
            of "nimAdvancedCommand":
              ru settings.quickRunSettings.nimAdvancedCommand
            of "ClangOptions":
              ru settings.quickRunSettings.ClangOptions
            of "CppOptions":
              ru settings.quickRunSettings.CppOptions
            of "NimOptions":
              ru settings.quickRunSettings.NimOptions
            of "shOptions":
              ru settings.quickRunSettings.shOptions
            of "bashOptions":
              ru settings.quickRunSettings.bashOptions
            else: ru ""
        else: ru ""

    let
      val = getSettingVal()
      col = positionOfSetVal + numOfIndent + val.len
    currentMainWindowNode.currentColumn = col

  var
    buffer = ""
    isCancel = false
    isBreak = false
  while not isBreak and not isCancel:
    status.update

    var key = errorKey
    while key == errorKey:
      key = currentMainWindowNode.getKey

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEscKey(key):
      isCancel = true
    elif isEnterKey(key):
      isBreak = true

    elif isLeftKey(key):
      moveToLeft()
    elif isRightkey(key):
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
      buffer &= key
      currentBufStatus.insertCharacter(currentMainWindowNode, key)
      let reservedWords = status.settings.highlightSettings.reservedWords
      currentMainWindowNode.highlight =
        currentBufStatus.buffer.initConfigModeHighlight(currentLine, arrayIndex, reservedWords)

  if not isCancel:
    template buildOnSaveTable() =
      case name:
        of "workspaceRoot":
          status.settings.buildOnSave.workspaceRoot = buffer.toRunes
        of "command":
          status.settings.buildOnSave.command = buffer.toRunes
        else:
          discard

    template  highlightTable() =
      case name:
        of "reservedWord":
          status.settings.highlightSettings.reservedWords[arrayIndex].word = buffer
        else:
          discard

    template autoBackupTable() =
      case name:
        of "backupDir":
          status.settings.autoBackupSettings.backupDir = ru buffer
        else:
          discard

    template quickRunTable() =
      case name:
        of "nimAdvancedCommand":
          status.settings.quickRunSettings.nimAdvancedCommand = buffer
        of "ClangOptions":
          status.settings.quickRunSettings.ClangOptions = buffer
        of "CppOptions":
          status.settings.quickRunSettings.CppOptions = buffer
        of "NimOptions":
          status.settings.quickRunSettings.NimOptions = buffer
        of "shOptions":
          status.settings.quickRunSettings.shOptions = buffer
        of "bashOptions":
          status.settings.quickRunSettings.bashOptions = buffer
        else:
          discard

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
      else:
        discard

proc editEnumAndBoolSettings(status: var EditorStatus,
                             lineSplit: seq[seq[Rune]],
                             selectedTable, selectedSetting: string,
                             settingValues: seq[seq[Rune]]) =

  const
    margin = 1
  let
    h = min(currentMainWindowNode.h, settingValues.len)
    w = min(currentMainWindowNode.w, maxLen(settingValues))
    (absoluteY, absoluteX) = currentMainWindowNode.absolutePosition(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)
    y = absoluteY
    x = absoluteX + positionOfSetVal + numOfIndent - margin

  var
    popUpWindow = initWindow(h, w, y, x, EditorColorPair.popUpWindow)
    suggestIndex = 0

    key = errorKey

  while (isTabKey(key) or isShiftTab(key) or isDownKey(key) or isUpKey(key) or
         errorKey == key) and settingValues.len > 1:

    if (isTabKey(key) or isDownKey(key)) and
       suggestIndex < settingValues.high: inc(suggestIndex)
    elif (isShiftTab(key) or isUpKey(key)) and suggestIndex > 0:
      dec(suggestIndex)
    elif (isShiftTab(key) or isUpKey(key)) and suggestIndex == 0:
      suggestIndex = settingValues.high
    else:
      suggestIndex = 0

    popUpWindow.writePopUpWindow(h, w, y, x,
                                 terminalHeight(), terminalWidth(),
                                 suggestIndex,
                                 settingValues)

    key = currentMainWindowNode.getKey

  if isEnterKey(key):
    let
      settingVal = $settingValues[suggestIndex]
      # position is "foreground" or "background" or ""
      position = if selectedTable == "Theme": $lineSplit[0] else: ""
    status.changeEditorSettings(
      selectedTable, selectedSetting, position, settingVal)
  else:
    status.deletePopUpWindow

proc selectAndChangeEditorSettings(status: var EditorStatus, arrayIndex: int) =
  let
    currentLine = currentMainWindowNode.currentLine
    line = currentBufStatus.buffer[currentLine]
    lineSplit = line.splitWhitespace

  if lineSplit.len < 2: return

  let
    selectedTable = getTableName(currentBufStatus.buffer,
                                 currentMainWindowNode.currentLine)
    selectedSetting = if selectedTable == "Theme":
                        currentBufStatus.buffer.getEditorColorPairStr(
                          lineSplit,currentLine)
                      else:
                        $lineSplit[0]
    settingType = getSettingType(selectedTable, selectedSetting)

    # position is "foreground" or "background" or ""
    position = if selectedTable == "Theme": $lineSplit[0] else: ""
    settingValues = getSettingValues(status.settings,
                                     settingType,
                                     selectedTable,
                                     selectedSetting,
                                     position)

  case settingType:
    of SettingType.Number:
      status.editFiguresSetting(selectedTable, selectedSetting, arrayIndex)
    of SettingType.String, SettingType.Array:
      status.editStringSetting(selectedTable, selectedSetting, arrayIndex)
    else:
      status.editEnumAndBoolSettings(lineSplit,
                                     selectedTable,
                                     selectedSetting,
                                     settingValues)

proc initStandardTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"Standard")

  for name in standardTableNames:
    let
      nameStr = indent & $name
      space = " ".repeat(positionOfSetVal - len($name))
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
      of "popUpWindowInExmode":
        result.add(ru nameStr & space & $settings.popUpWindowInExmode)
      of "autoDeleteParen":
        result.add(ru nameStr & space & $settings.autoDeleteParen)
      of "smoothScroll":
        result.add(ru nameStr & space & $settings.smoothScroll)
      of "smoothScrollSpeed":
        result.add(ru nameStr & space & $settings.smoothScrollSpeed)

proc initClipBoardTableBuffer(settings: ClipBoardSettings): seq[seq[Rune]] =
  result.add(ru"ClipBoard")

  for name in clipboardTableNames:
    let
      nameStr = indent & $name
      space = " ".repeat(positionOfSetVal - len($name))
    case $name:
      of "enable":
        result.add(ru nameStr & space & $settings.enable)
      of "toolOnLinux":
        result.add(ru nameStr & space & $settings.toolOnLinux)

proc initBuildOnSaveTableBuffer(settings: BuildOnSaveSettings): seq[seq[Rune]] =
  result.add(ru"BuildOnSave")

  for name in buildOnSaveTableNames:
    let
      nameStr = indent & $name
      space = " ".repeat(positionOfSetVal - len($name))
    case $name:
      of "enable":
        result.add(ru nameStr & space & $settings.enable)
      of "workspaceRoot":
        result.add(ru nameStr & space & $settings.workspaceRoot)
      of "command":
        result.add(ru nameStr & space & $settings.command)

proc initTabLineTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"TabLine")

  for name in tabLineTableNames:
    let
      nameStr = indent & $name
      space = " ".repeat(positionOfSetVal - len($name))
    case $name:
      of "allBuffer":
        result.add(ru nameStr & space & $settings.tabLine.allBuffer)

proc initStatusLineTableBuffer(settings: StatusLineSettings): seq[seq[Rune]] =
  result.add(ru"StatusLine")

  for name in statusLineTableNames:
    let
      nameStr = indent & $name
      space = " ".repeat(positionOfSetVal - len($name))
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
      of "line":
        result.add(ru nameStr & space & $settings.line)
      of "column":
        result.add(ru nameStr & space & $settings.column)
      of "encoding":
        result.add(ru nameStr & space & $settings.characterEncoding)
      of "language":
        result.add(ru nameStr & space & $settings.language)
      of "directory":
        result.add(ru nameStr & space & $settings.directory)
      of "gitbranchName":
        result.add(ru nameStr & space & $settings.gitbranchName)
      of "showGitInactive":
        result.add(ru nameStr & space & $settings.showGitInactive)
      of "showModeInactive":
        result.add(ru nameStr & space & $settings.showModeInactive)

proc initHighlightTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"Highlight")

  for name in highlightTableNames:
    let
      nameStr = indent & $name
      space = " ".repeat(positionOfSetVal - len($name))
    case $name:
      of "currentLine":
        result.add(ru nameStr & space & $settings.view.highlightCurrentLine)
      of "replaceText":
        result.add(ru nameStr & space & $settings.highlightSettings.replaceText)
      of "highlightPairOfParen":
        result.add(ru nameStr & space & $settings.highlightSettings.pairOfParen)
      of "fullWidthSpace":
        result.add(ru nameStr & space & $settings.highlightSettings.fullWidthSpace)
      of "trailingSpaces":
        result.add(ru nameStr & space & $settings.highlightSettings.trailingSpaces)
      of "currentWord":
        result.add(ru nameStr & space & $settings.highlightSettings.currentWord)
      of "reservedWord":
        var line = ru nameStr & space
        for reservedWord in settings.highlightSettings.reservedWords:
          line &= ru reservedWord.word & " "

        result.add line

proc initAutoBackupTableBuffer(settings: AutoBackupSettings): seq[seq[Rune]] =
  result.add(ru"AutoBackup")

  for name in autoBackupTableNames:
    let
      nameStr = indent & $name
      space = " ".repeat(positionOfSetVal - len($name))
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

proc initQuickRunTableBuffer(settings: QuickRunSettings): seq[seq[Rune]] =
  result.add(ru"QuickRun")

  for name in quickRunTableNames:
    let
      nameStr = indent & $name
      space = " ".repeat(positionOfSetVal - len($name))
    case $name:
      of "saveBufferWhenQuickRun":
        result.add(ru nameStr & space & $settings.saveBufferWhenQuickRun)
      of "command":
        result.add(ru nameStr & space & $settings.command)
      of "timeout":
        result.add(ru nameStr & space & $settings.timeout)
      of "nimAdvancedCommand":
        result.add(ru nameStr & space & $settings.nimAdvancedCommand)
      of "ClangOptions":
        result.add(ru nameStr & space & $settings.ClangOptions)
      of "CppOptions":
        result.add(ru nameStr & space & $settings.CppOptions)
      of "NimOptions":
        result.add(ru nameStr & space & $settings.NimOptions)
      of "shOptions":
        result.add(ru nameStr & space & $settings.shOptions)
      of "bashOptions":
        result.add(ru nameStr & space & $settings.bashOptions)

proc initNotificationTableBuffer(
  settings: NotificationSettings): seq[seq[Rune]] =

  result.add(ru"Notification")

  for name in notificationTableNames:
    let
      nameStr = indent & $name
      space = " ".repeat(positionOfSetVal - len($name))
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

proc initFilerTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"Filer")

  for name in filerTableNames:
    let
      nameStr = indent & $name
      space = " ".repeat(positionOfSetVal - len($name))
    case $name:
      of "showIcons":
        result.add(ru nameStr & space & $settings.filerSettings.showIcons)

proc initAutocompleteTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"Autocomplete")

  for name in autocompleteTableNames:
    let
      nameStr = indent & $name
      space = " ".repeat(positionOfSetVal - len($name))
    case $name:
      of "enable":
        result.add(ru nameStr & space & $settings.autocompleteSettings.enable)

proc initPersistTableBuffer(persistSettings: PersistSettings): seq[seq[Rune]] =
  result.add(ru"Persist")

  for name in persistTableSettings:
    let
      nameStr = indent & $name
      space = " ".repeat(positionOfSetVal - len($name))
    case $name:
      of "exCommand":
        result.add(ru nameStr & space & $persistSettings.exCommand)
      of "search":
        result.add(ru nameStr & space & $persistSettings.search)
      of "cursorPosition":
        result.add(ru nameStr & space & $persistSettings.cursorPosition)

proc initThemeTableBuffer*(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"Theme")

  let theme = settings.editorColorTheme

  template addColorPairSettingLine() =
    let
      # 11 is "foreground " and "background " length
      space = " ".repeat(positionOfSetVal - indent.len - 11)
      (fg, bg) = getColorFromEditorColorPair(theme, colorPair)

    result.add(ru indent & nameStr)
    result.add(ru indent.repeat(2) & "foreground " & space & $fg)
    result.add(ru indent.repeat(2) & "background " & space & $bg)

    result.add(ru "")

  for name in themeTableNames:
    let nameStr = $name
    case $name:
      of "editorBg":
        let
          # 11 is "background " length
          space = " ".repeat(positionOfSetVal - indent.len - 11)
          editorBg = $ColorThemeTable[theme].editorBg

        result.add(ru indent & nameStr)
        result.add(ru indent.repeat(2) & "background " & space & editorBg)

        result.add(ru "")
      else:
        let colorPair = parseEnum[EditorColorPair]($name)
        addColorPairSettingLine()

proc initConfigModeBuffer*(settings: EditorSettings): GapBuffer[seq[Rune]] =
  var buffer: seq[seq[Rune]]
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
  buffer.add(initAutoBackupTableBuffer(settings.autoBackupSettings))

  buffer.add(ru"")
  buffer.add(initQuickRunTableBuffer(settings.quickRunSettings))

  buffer.add(ru"")
  buffer.add(initNotificationTableBuffer(settings.notificationSettings))

  buffer.add(ru"")
  buffer.add(initFilerTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initAutocompleteTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initPersistTableBuffer(settings.persist))

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
proc getNumOfValueOfArraySetting(line: seq[Rune]): int =
  # 1 is the name of the setting
  line.splitWhitespace.len - 1

proc isConfigMode(mode: Mode): bool {.inline.} =
  mode == Mode.config

proc configMode*(status: var Editorstatus) =

  status.resize(terminalHeight(), terminalWidth())

  currentBufStatus.buffer = initConfigModeBuffer(status.settings)
  currentMainWindowNode.currentLine = 1

  let currentBufferIndex = currentMainWindowNode.bufferIndex

  # For SettingType.Array
  var arrayIndex = 0

  while isConfigMode(currentBufStatus.mode) and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    let
      currentLine = currentMainWindowNode.currentLine
      reservedWords = status.settings.highlightSettings.reservedWords
      highlight = currentBufStatus.buffer.initConfigModeHighlight(
        currentLine,
        arrayIndex,
        reservedWords)

    if currentLine == 0:
      currentMainWindowNode.currentLine = 1
    elif currentLine > currentBufStatus.buffer.high - 1:
      currentMainWindowNode.currentLine = currentBufStatus.buffer.high - 1

    currentMainWindowNode.highlight = highlight

    status.update
    setCursor(false)

    template getSettingType(): SettingType =
      let buffer = currentBufStatus.buffer
      buffer.getSettingType(currentMainWindowNode.currentLine)

    template getNumOfValueOfArraySetting(): int =
      let
        currentLine = currentMainWindowNode.currentLine
        line = currentBufStatus.buffer[currentLine]
      getNumOfValueOfArraySetting(line)

    var key: Rune = ru'\0'
    while key == ru'\0':
      status.eventLoopTask
      key = getKey(currentMainWindowNode)

    status.lastOperatingTime = now()

    # Adjust arrayIndex
    block:
      let line = currentBufStatus.buffer[currentMainWindowNode.currentLine]
      if line.splitWhitespace.len > 1 and
         getSettingType() == SettingType.Array and
         arrayIndex > getNumOfValueOfArraySetting():
        arrayIndex = getNumOfValueOfArraySetting() - 1

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow
    elif key == ord(':'):
      status.changeMode(Mode.ex)

    elif key == ord('h') or isLeftKey(key):
      if getSettingType() == SettingType.Array and arrayIndex > 0:
        arrayIndex.dec
    elif key == ord('l') or isRightKey(key):
      let numOfValue = getNumOfValueOfArraySetting()
      if getSettingType() == SettingType.Array and numOfValue - 1 > arrayIndex:
        arrayIndex.inc

    elif isEnterKey(key):
      status.selectAndChangeEditorSettings(arrayIndex)
      currentBufStatus.buffer = initConfigModeBuffer(status.settings)
    elif isControlU(key):
      status.halfPageUp
    elif isControlD(key):
      status.halfPageDown
    elif isPageUpkey(key):
      status.pageUp
    elif isPageDownKey(key): ## Page down and Ctrl - F
      status.pageDown
    elif key == ord('k') or isUpKey(key):
      currentBufStatus.keyUp(currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      currentBufStatus.keyDown(currentMainWindowNode)
    elif key == ord('g'):
      let secondKey = getKey(currentMainWindowNode)
      if secondKey == 'g':
        currentBufStatus.moveToFirstLine(currentMainWindowNode)
    elif key == ord('G'):
      currentBufStatus.moveToLastLine(currentMainWindowNode)

    elif key == ord('/'):
      status.searchFordwards
    elif key == ord('?'):
      status.searchBackwards
    else:
      discard
