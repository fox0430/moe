import terminal, times, typetraits, strutils
import gapbuffer, ui, editorstatus, unicodetext, window, movement, settings,
       bufferstatus, color, highlight, search

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
  systemClipboard
  smoothScroll
  smoothScrollSpeed

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

type workSpaceTableNames {.pure.} = enum
  workSpaceLine

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

type autoBackupTableName {.pure.} = enum
  enable
  idleTime
  interval

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
  workspaceScreenNotify
  workspaceLogNotify
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
  boolean
  specialVar
  builtin
  stringLit
  decNumber
  comment
  longComment
  whitespace
  preprocessor
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
  workSpaceBar
  reservedWord
  currentSetting

proc calcPositionOfSettingValue(): int {.compileTime.} =
  var names: seq[string]

  for name in standardTableNames: names.add($name)
  for name in buildOnSaveTableNames: names.add($name)
  for name in tabLineTableNames: names.add($name)
  for name in workSpaceTableNames: names.add($name)
  for name in highlightTableNames: names.add($name)
  for name in autoBackupTableNames: names.add($name)
  for name in quickRunTableNames: names.add($name)
  for name in notificationTableNames: names.add($name)
  for name in filerTableNames: names.add($name)
  for name in themeTableNames: names.add($name)

  for name in names:
    if result < name.len: result = name.len

  const numOfIndent = 2
  result += numOfIndent

const
  positionOfSetVal = calcPositionOfSettingValue()
  indent = "  "

proc getSettingValues(editorSettings: EditorSettings,
                    table, setting: string): seq[seq[Rune]] =

  proc getColorThemeList(): seq[seq[Rune]] {.compileTime.} =
    for theme in ColorTheme:
      result.add ru $theme

  proc getCursorTypeList(): seq[seq[Rune]] {.compileTime.} =
    for cursorType in CursorType:
      result.add ru $cursorType

  proc getStandardTableList(setting: string): seq[seq[Rune]] {.inline.} =
    case setting:
      of "theme": result = getColorThemeList()
      of "defaultCursor",
         "normalModeCursor",
         "insertModeCursor": result = getCursorTypeList()
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
         "autoSaveInterval",
         "liveReloadOfConf",
         "incrementalSearch",
         "popUpWindowInExmode",
         "autoDeleteParen",
         "systemClipboard",
         "smoothScroll": result = @[ru"true", ru"false"]
      else: discard

  proc getBuildOnSaveTableList(setting: string): seq[seq[Rune]] {.inline.} =
    case setting:
      of "enable": result = @[ru"true", ru"false"]
      else: discard

  proc getTabLineTableList(setting: string): seq[seq[Rune]] {.inline.} =
    case setting:
      of "allBuffer": result = @[ru"true", ru"false"]
      else: discard

  proc getStatusLineTableList(setting: string): seq[seq[Rune]] {.inline.} =
    case setting:
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
         "showModeInactive": result = @[ru"true", ru"false"]
      else: discard

  proc getWorkSpaceTableList(setting: string): seq[seq[Rune]] {.inline.} =
    case setting:
      of "workSpaceLine": result = @[ru"true", ru"false"]
      else: discard

  proc getHighlightTableList(setting: string): seq[seq[Rune]] {.inline.} =
    case setting:
    of "currentLine",
       "fullWidthSpace",
       "trailingSpaces",
       "currentWord",
       "replaceText",
       "pairOfParen": result = @[ru"true", ru"false"]
    else: discard

  proc getAutoBackupTableList(setting: string): seq[seq[Rune]] {.inline.} =
    case setting:
      of "enable": result = @[ru"true", ru"false"]
      else: discard

  proc getQuickRunTableList(setting: string): seq[seq[Rune]] {.inline.} =
    case setting:
      of "saveBufferWhenQuickRun": result = @[ru"true", ru"false"]
      else: discard

  proc getNotificationTableList(setting: string): seq[seq[Rune]] {.inline.} =
    case setting:
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
         "workspaceScreenNotify",
         "workspaceLogNotify",
         "quickRunScreenNotify",
         "quickRunLogNotify",
         "buildOnSaveScreenNotify",
         "buildOnSaveLogNotify",
         "filerScreenNotify",
         "filerLogNotify",
         "restoreScreenNotify",
         "restoreLogNotify": result = @[ru"true", ru"false"]
      else: discard

  proc getFilerTableList(setting: string): seq[seq[Rune]] {.inline.} =
    case setting:
      of "showIcons": result = @[ru"true", ru"false"]
      else: discard

  proc getAutocompleteTableList(setting: string): seq[seq[Rune]] {.inline.} =
    case setting:
      of "enable": result = @[ru"true", ru"false"]
      else: discard

  proc getThemeTableList(): seq[seq[Rune]] {.compileTime.} =
    for color in Color:
      result.add ru $color

  case table:
    of "Standard":
      result = getStandardTableList(setting)
    of "BuildOnSave":
      result = getBuildOnSaveTableList(setting)
    of "TabLine":
      result = getTabLineTableList(setting)
    of "StatusLine":
      result = getStatusLineTableList(setting)
    of "WorkSpace":
      result = getWorkSpaceTableList(setting)
    of "Highlight":
      result = getHighlightTableList(setting)
    of "AutoBackup":
      result = getAutoBackupTableList(setting)
    of "QuickRun":
      result = getQuickRunTableList(setting)
    of "Notification":
      result = getNotificationTableList(setting)
    of "Filer":
      result = getFilerTableList(setting)
    of "Autocomplete":
      result = getAutocompleteTableList(setting)
    of "Theme":
      result = getThemeTableList()

proc maxLen(list: seq[seq[Rune]]): int =
  const mergen = 2
  for r in list:
    if r.len > result:
      result = r.len + 2

proc getTableName(buffer: GapBuffer[seq[Rune]], line: int): string =
  const
    spaceLineLen = 1
    tableNameLineLen = 1
  var total = tableNameLineLen

  # Search table name from configuration mode buffer
  for i in countDown(line, 0):
    if buffer[i].len > 0 and buffer[i][0] != ru ' ':
      return $buffer[i]

proc changeStandardTableSetting(status: var EditorStatus,
                                settingName, settingVal: string) =

  case settingName:
    of "theme":
      status.settings.editorColorTheme = parseEnum[ColorTheme](settingVal)
      status.changeTheme
    of "number":
      status.settings.view.lineNumber = parseBool(settingVal)
    of "currentNumber":
      status.settings.view.currentLineNumber = parseBool(settingVal)
    of "cursorLine":
      status.settings.view.cursorLine = parseBool(settingVal)
    of "statusLine":
      status.settings.statusLine.enable = parseBool(settingVal)
    of "tabLine":
      status.settings.tabline.useTab = parseBool(settingVal)
    of "syntax":
      status.settings.syntax = parseBool(settingVal)
    of "indentationLines":
      status.settings.view.indentationLines = parseBool(settingVal)
    of "autoCloseParen":
      status.settings.autoCloseParen = parseBool(settingVal)
    of "autoIndent":
      status.settings.autoIndent = parseBool(settingVal)
    of "ignorecase":
      status.settings.ignorecase = parseBool(settingVal)
    of "smartcase":
      status.settings.smartcase = parseBool(settingVal)
    of "disableChangeCursor":
      status.settings.disableChangeCursor = parseBool(settingVal)
    of "autoSave":
      status.settings.autoSave = parseBool(settingVal)
    of "liveReloadOfConf":
      status.settings.liveReloadOfConf = parseBool(settingVal)
    of "incrementalSearch":
      status.settings.incrementalSearch = parseBool(settingVal)
    of "popUpWindowInExmode":
      status.settings.popUpWindowInExmode = parseBool(settingVal)
    of "autoDeleteParen":
      status.settings.autoDeleteParen = parseBool(settingVal)
    of "systemClipboard":
      status.settings.systemClipboard = parseBool(settingVal)
    of "smoothScroll":
      status.settings.smoothScroll = parseBool(settingVal)
    else:
      # TODO: Add other settings
      discard

proc changeBuildOnSaveTableSetting(settings: var EditorSettings,
                                   settingName, settingVal: string) =

  case settingName:
    of "enable":
      settings.buildOnSave.enable = parseBool(settingVal)
    else:
      # TODO: Add other settings
      discard

proc changeTabLineTableSetting(settings: var EditorSettings,
                               settingName, settingVal: string) =

  case settingName:
    of "allBuffer":
      settings.tabLine.allBuffer = parseBool(settingVal)
    else:
      discard

proc changeStatusLineTableSetting(settings: var EditorSettings,
                                  settingName, settingVal: string) =

  case settingName:
  of "multipleStatusLine":
    settings.statusLine.multipleStatusLine = parseBool(settingVal)
  of "merge":
    settings.statusLine.merge = parseBool(settingVal)
  of "mode":
    settings.statusLine.mode = parseBool(settingVal)
  of "filename":
    settings.statusLine.filename = parseBool(settingVal)
  of "chanedMark":
    settings.statusLine.chanedMark = parseBool(settingVal)
  of "line":
    settings.statusLine.line = parseBool(settingVal)
  of "column":
    settings.statusLine.column = parseBool(settingVal)
  of "encoding":
    settings.statusLine.characterEncoding = parseBool(settingVal)
  of "language":
    settings.statusLine.language = parseBool(settingVal)
  of "directory":
    settings.statusLine.directory = parseBool(settingVal)
  of "gitbranchName":
    settings.statusLine.gitbranchName = parseBool(settingVal)
  of "showGitInactive":
    settings.statusLine.showGitInactive = parseBool(settingVal)
  of "showModeInactive":
    settings.statusLine.showModeInactive = parseBool(settingVal)
  else:
    discard

proc changeWorkSpaceTableSetting(settings: var EditorSettings,
                                 settingName, settingVal: string) =

  case settingName:
    of "workSpaceLine":
      settings.workSpace.workSpaceLine = parseBool(settingVal)
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
     else:
      discard

proc changeBackupTableSetting(settings: var EditorSettings,
                              settingName, settingVal: string) =

  case settingName:
    of "enable":
      settings.autoBackupSettings.enable = parseBool(settingVal)
    else:
      discard

proc changeQuickRunTableSetting(settings: var EditorSettings,
                              settingName, settingVal: string) =

  case settingName:
    of "saveBufferWhenQuickRun":
      settings.quickRunSettings.saveBufferWhenQuickRun = parseBool(settingVal)
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
    of "workspaceScreenNotify":
      settings.workspaceScreenNotify = parseBool(settingVal)
    of "workspaceLogNotify":
      settings.workspaceLogNotify = parseBool(settingVal)
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

proc changeFilerTableSetting(settings: var EditorSettings,
                             settingName, settingVal: string) =

  case settingName:
    of "showIcons":
      settings.filerSettings.showIcons = parseBool(settingVal)
    else:
      discard

proc changeAutoCompleteTableSetting(settings: var EditorSettings,
                                    settingName, settingVal: string) =

  case settingName:
    of "enable":
      settings.autocompleteSettings.enable = parseBool(settingVal)
    else:
      discard

proc changeeThemeTableSetting(settings: var EditorSettings,
                              settingName, position, settingVal: string) =

  let theme = settings.editorColorTheme
  case settingName:
    of "editorBg":
      ColorThemeTable[theme].editorBg = parseEnum[Color](settingVal)
    else:
      var colorPair = parseEnum[EditorColorPair](settingName)
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

  case table:
    of "Standard":
      status.changeStandardTableSetting(settingName, settingVal)
    of "BuildOnSave":
      status.settings.changeBuildOnSaveTableSetting(settingName, settingVal)
    of "TabLine":
      status.settings.changeTabLineTableSetting(settingName, settingVal)
    of "StatusLine":
      status.settings.changeStatusLineTableSetting(settingName, settingVal)
    of "WorkSpace":
      status.settings.changeWorkSpaceTableSetting(settingName, settingVal)
    of "Highlight":
      status.settings.changeHighlightTableSetting(settingName, settingVal)
    of "AutoBackup":
      status.settings.changeBackupTableSetting(settingName, settingVal)
    of "QuickRun":
      status.settings.changeQuickRunTableSetting(settingName, settingVal)
    of "Notification":
      status.settings.notificationSettings.changeNotificationTableSetting(
        settingName,
        settingVal)
    of "Filer":
      status.settings.changeFilerTableSetting(settingName, settingVal)
    of "Autocomplete":
      status.settings.changeAutoCompleteTableSetting(settingName, settingVal)
    of "Theme":
      status.settings.changeeThemeTableSetting(
        settingName,
        position,
        settingVal)
      status.changeTheme
    else:
      discard

proc selectAndChangeEditorSettings(status: var EditorStatus) =
  let
    currentLine = currentMainWindowNode.currentLine
    line = currentBufStatus.buffer[currentLine]
    lineSplit = line.splitWhitespace

  if lineSplit.len == 1 or lineSplit[0].len < 1 or lineSplit[1].len < 1: return

  # TODO: Refactor
  proc getEditorColorPairStr(buffer: GapBuffer[seq[Rune]],
                             lineSplit: seq[seq[Rune]],
                             currentLine: int): string =

    if (lineSplit[0] == ru "foreground") or
       (buffer[currentLine - 2] == ru "Theme"):
      return $(buffer[currentLine - 1].splitWhitespace)[0]
    else:
      return $(buffer[currentLine - 2].splitWhitespace)[0]

  const
    numOfIndent = 2
    margin = 1
  let
    selectedTable = getTableName(currentBufStatus.buffer,
                                 currentMainWindowNode.currentLine)
    selectedSetting = if selectedTable == "Theme":
                        currentBufStatus.buffer.getEditorColorPairStr(
                          lineSplit,currentLine)
                      else:
                        $lineSplit[0]
    settingValues = getSettingValues(status.settings,
                                     selectedTable,
                                     selectedSetting)

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

    if (isTabKey(key) or isDownKey(key)) and suggestIndex < settingValues.high:
      inc(suggestIndex)
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

proc initConfigModeHighlight[T](buffer: T, currentLine: int): Highlight =
  for i in 0 ..< buffer.len:
    let color = if i == currentLine: EditorColorPair.currentSetting
                else: EditorColorPair.defaultChar

    let colorSegment = ColorSegment(
      firstRow: i,
      firstColumn: 0,
      lastRow: i,
      lastColumn: buffer[i].len,
      color: color)

    result.colorSegments.add(colorSegment)

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
        result.add(ru nameStr & space & $settings.tabLine.useTab)
      of "syntax":
        result.add(ru nameStr & space & $settings.syntax)
      of "indentationLines":
        result.add(ru nameStr & space & $settings.view.indentationLines)
      of "tabStop":
        result.add(ru nameStr & space & $settings.view.tabStop)
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
      of "systemClipboard":
        result.add(ru nameStr & space & $settings.systemClipboard)
      of "smoothScroll":
        result.add(ru nameStr & space & $settings.smoothScroll)
      of "smoothScrollSpeed":
        result.add(ru nameStr & space & $settings.smoothScrollSpeed)

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

proc initWorkspaceTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"WorkSpace")

  for name in workSpaceTableNames:
    let
      nameStr = indent & $name
      space = " ".repeat(positionOfSetVal - len($name))
    case $name:
      of "workSpaceLine":
        result.add(ru nameStr & space & $settings.workSpace.workSpaceLine)

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
      of "workspaceScreenNotify":
        result.add(ru nameStr & space & $settings.workspaceScreenNotify)
      of "workspaceLogNotify":
        result.add(ru nameStr & space & $settings.workspaceLogNotify)
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

proc calcPositionOfThemeSettingValue(theme: ColorTheme): int =
  for colorPair in EditorColorPair:
    let
      colors = getColorFromEditorColorPair(theme, colorPair)
      color = $colors[0]

    if result < color.len: result = color.len + 1

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
  buffer.add(initBuildOnSaveTableBuffer(settings.buildOnSave))

  buffer.add(ru"")
  buffer.add(initTabLineTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initStatusLineTableBuffer(settings.statusLine))

  buffer.add(ru"")
  buffer.add(initWorkspaceTableBuffer(settings))

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
  buffer.add(initThemeTableBuffer(settings))

  result = initGapBuffer(buffer)

proc isConfigMode(status: Editorstatus): bool {.inline.} =
  let
    mode = currentBufStatus.mode
    prevMode = currentBufStatus.prevMode
  (mode == Mode.config) or (prevMode == Mode.ex and mode == Mode.config)

proc configMode*(status: var Editorstatus) =
  status.resize(terminalHeight(), terminalWidth())

  currentBufStatus.buffer = initConfigModeBuffer(status.settings)
  currentMainWindowNode.currentLine = 1

  let
    currentBufferIndex = currentMainWindowNode.bufferIndex
    currentWorkSpace = status.currentWorkSpaceIndex

  template keyUp() =
    if currentLine > 1:
      currentBufStatus.keyUp(windowNode)

      # Skip empty line and table name line
      while currentBufStatus.buffer[windowNode.currentLine].len == 0 or
            currentBufStatus.buffer[windowNode.currentLine][0] != ' ':
        currentBufStatus.keyUp(windowNode)

  template keyDown() =
    if currentLine < currentBufStatus.buffer.high - 1:
      currentBufStatus.keyDown(windowNode)

      # Skip empty line and table name line
      while currentBufStatus.buffer[windowNode.currentLine].len == 0 or
            currentBufStatus.buffer[windowNode.currentLine][0] != ' ':
        currentBufStatus.keyDown(windowNode)

  while status.isConfigMode and
        currentWorkSpace == status.currentWorkSpaceIndex and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    let
      currentLine = currentMainWindowNode.currentLine
      highlight = currentBufStatus.buffer.initConfigModeHighlight(currentLine)

    if currentLine == 0:
      currentMainWindowNode.currentLine = 1
    elif currentLine > currentBufStatus.buffer.high - 1:
      currentMainWindowNode.currentLine = currentBufStatus.buffer.high - 1

    currentMainWindowNode.highlight = highlight

    status.update
    setCursor(false)

    var
      windowNode = currentMainWindowNode

      key: Rune = ru'\0'
    while key == ru'\0':
      status.eventLoopTask
      key = getKey(currentMainWindowNode)

    status.lastOperatingTime = now()

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow
    elif key == ord(':'):
      status.changeMode(Mode.ex)

    elif isEnterKey(key):
      status.selectAndChangeEditorSettings
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
      keyUp()
    elif key == ord('j') or isDownKey(key):
      keyDown()
    elif key == ord('g'):
      let secondKey = getKey(currentMainWindowNode)
      if secondKey == 'g': status.moveToFirstLine
    elif key == ord('G'):
      status.moveToLastLine

    elif key == ord('/'):
      status.searchFordwards
    elif key == ord('?'):
      status.searchBackwards
