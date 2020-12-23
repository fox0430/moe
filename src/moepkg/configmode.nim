import terminal, times, typetraits, strutils
import gapbuffer, ui, editorstatus, unicodetext, window, movement, settings,
       bufferstatus, color, highlight

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

proc getSettingValue(editorSettings: EditorSettings,
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
    of "standardTable":
      result = getStandardTableList(setting)
    of "buildOnSaveTable":
      result = getBuildOnSaveTableList(setting)
    of "tabLineTable":
      result = getTabLineTableList(setting)
    of "statusLineTable":
      result = getStandardTableList(setting)
    of "workSpaceTable":
      result = getWorkSpaceTableList(setting)
    of "highlightTable":
      result = getHighlightTableList(setting)
    of "autoBackupTable":
      result = getAutoBackupTableList(setting)
    of "quickRunTable":
      result = getAutoBackupTableList(setting)
    of "notificationTable":
      result = getNotificationTableList(setting)
    of "filerTable":
      result = getFilerTableList(setting)
    of "autocompleteTable":
      result = getAutocompleteTableList(setting)
    of "themeTableNames":
      result = getThemeTableList()

proc maxLen(list: seq[seq[Rune]]): int =
  for r in list:
    if r.len > result:
      result = r.len

proc changeEditorSettings(status: var EditorStatus) =
  let
    line = currentBufStatus.buffer[currentMainWindowNode.currentLine]
    lineSplit = line.splitWhitespace

  if lineSplit.len != 2 or lineSplit[0].len < 1 or lineSplit[1].len < 1: return

  var windowNode = currentMainWindowNode

  const
    numOfIndent = 2
  let
    selectedTable = $lineSplit[0]
    selectedSetting = $lineSplit[1]
    settingValue = getSettingValue(status.settings,
                                   selectedTable,
                                   selectedSetting)

    h = min(windowNode.h, settingValue.len)
    w = min(windowNode.w, maxLen(settingValue))
    (absoluteY, absoluteX) = windowNode.absolutePosition(
      windowNode.currentLine,
      windowNode.currentColumn)
    y = absoluteY
    margin = 1
    x = absoluteX + positionOfSetVal + numOfIndent - margin

  var popUpWindow = initWindow(h, w, y, x, EditorColorPair.popUpWindow)

  let currentLine = 0
  popUpWindow.writePopUpWindow(h, w, y, x,
                               terminalHeight(), terminalWidth(),
                               currentLine,
                               settingValue)

  var key = windowNode.getKey
  while not isEscKey(key) and not isEnterKey(key):
    key = windowNode.getKey

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

proc initNotificationTableBuffer(settings: NotificationSettings): seq[seq[Rune]] =
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

  for name in themeTableNames:
    let
      nameStr = indent & $name
      space = " ".repeat(positionOfSetVal - len($name))
    case $name:
      of "editorBg":
        let editorColor = ColorThemeTable[theme]
        result.add(ru nameStr & space & $editorColor.editorBg)
      of "lineNum":
        let
          colorPair = EditorColorPair.lineNum
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "currentLineNum":
        let
          colorPair = EditorColorPair.currentLineNum
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineNormalMode":
        let
          colorPair = EditorColorPair.statusLineNormalMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineModeNormalMode":
        let
          colorPair = EditorColorPair.statusLineModeNormalMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineNormalModeInactive":
        let
          colorPair = EditorColorPair.statusLineNormalModeInactive
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineInsertMode":
        let
          colorPair = EditorColorPair.statusLineInsertMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineModeInsertMode":
        let
          colorPair = EditorColorPair.statusLineModeInsertMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineInsertModeInactive":
        let
          colorPair = EditorColorPair.statusLineInsertModeInactive
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineVisualMode":
        let
          colorPair = EditorColorPair.statusLineVisualMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineModeVisualMode":
        let
          colorPair = EditorColorPair.statusLineModeVisualMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineVisualModeInactive":
        let
          colorPair = EditorColorPair.statusLineVisualModeInactive
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineReplaceMode":
        let
          colorPair = EditorColorPair.statusLineReplaceMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineModeReplaceMode":
        let
          colorPair = EditorColorPair.statusLineModeReplaceMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineReplaceModeInactive":
        let
          colorPair = EditorColorPair.statusLineReplaceModeInactive
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineFilerMode":
        let
          colorPair = EditorColorPair.statusLineFilerMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineModeFilerMode":
        let
          colorPair = EditorColorPair.statusLineModeFilerMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineFilerModeInactive":
        let
          colorPair = EditorColorPair.statusLineFilerModeInactive
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineExMode":
        let
          colorPair = EditorColorPair.statusLineExMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineModeExMode":
        let
          colorPair = EditorColorPair.statusLineModeExMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineExModeInactive":
        let
          colorPair = EditorColorPair.statusLineExModeInactive
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusLineGitBranch":
        let
          colorPair = EditorColorPair.statusLineGitBranch
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "tab":
        let
          colorPair = EditorColorPair.tab
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "currentTab":
        let
          colorPair = EditorColorPair.currentTab
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "commandBar":
        let
          colorPair = EditorColorPair.commandBar
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "errorMessage":
        let
          colorPair = EditorColorPair.errorMessage
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "searchResult":
        let
          colorPair = EditorColorPair.searchResult
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "visualMode":
        let
          colorPair = EditorColorPair.visualMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "defaultChar":
        let
          colorPair = EditorColorPair.defaultChar
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "keyword":
        let
          colorPair = EditorColorPair.keyword
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "functionName":
        let
          colorPair = EditorColorPair.functionName
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "boolean":
        let
          colorPair = EditorColorPair.boolean
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "specialVar":
        let
          colorPair = EditorColorPair.specialVar
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "builtin":
        let
          colorPair = EditorColorPair.builtin
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "stringLit":
        let
          colorPair = EditorColorPair.stringLit
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "decNumber":
        let
          colorPair = EditorColorPair.decNumber
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "comment":
        let
          colorPair = EditorColorPair.comment
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "longComment":
        let
          colorPair = EditorColorPair.longComment
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "whitespace":
        let
          colorPair = EditorColorPair.whitespace
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "preprocessor":
        let
          colorPair = EditorColorPair.preprocessor
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "currentFile":
        let
          colorPair = EditorColorPair.currentFile
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "file":
        let
          colorPair = EditorColorPair.file
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "dir":
        let
          colorPair = EditorColorPair.dir
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "pcLink":
        let
          colorPair = EditorColorPair.pcLink
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "popUpWindow":
        let
          colorPair = EditorColorPair.popUpWindow
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "popUpWinCurrentLine":
        let
          colorPair = EditorColorPair.popUpWinCurrentLine
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "replaceText":
        let
          colorPair = EditorColorPair.replaceText
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "parenText":
        let
          colorPair = EditorColorPair.parenText
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "currentWord":
        let
          colorPair = EditorColorPair.currentWord
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "highlightFullWidthSpace":
        let
          colorPair = EditorColorPair.highlightFullWidthSpace
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "highlightTrailingSpaces":
        let
          colorPair = EditorColorPair.highlightTrailingSpaces
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "workSpaceBar":
        let
          colorPair = EditorColorPair.workSpaceBar
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "reservedWord":
        let
          colorPair = EditorColorPair.reservedWord
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "currentSetting":
        let
          colorPair = EditorColorPair.currentSetting
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])

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

proc isConfigMode(status: Editorstatus): bool =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    index = status.workspace[workspaceIndex].currentMainWindowNode.bufferIndex
    mode = status.bufStatus[index].mode
    prevMode = status.bufStatus[index].prevMode
  (mode == Mode.config) or (prevMode == Mode.ex and mode == Mode.config)

proc configMode*(status: var Editorstatus) =
  status.resize(terminalHeight(), terminalWidth())

  currentBufStatus.buffer = initConfigModeBuffer(
    status.settings)

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    currentWorkSpace = status.currentWorkSpaceIndex

  while status.isConfigMode and
        currentWorkSpace == status.currentWorkSpaceIndex and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    let
      currentLine = currentMainWindowNode.currentLine
      highlight = currentBufStatus.buffer.initConfigModeHighlight(currentLine)

    currentMainWindowNode.highlight = highlight

    status.update
    setCursor(false)

    var key: Rune = ru'\0'
    while key == ru'\0':
      status.eventLoopTask
      key = getKey(currentMainWindowNode)

    status.lastOperatingTime = now()

    if isResizekey(key): status.resize(terminalHeight(), terminalWidth())
    elif isControlK(key): status.moveNextWindow
    elif isControlJ(key): status.movePrevWindow
    elif key == ord(':'): status.changeMode(Mode.ex)

    elif isEnterKey(key):
      status.changeEditorSettings
    elif key == ord('k') or isUpKey(key):
      status.bufStatus[currentBufferIndex].keyUp(currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      currentBufStatus.keyDown(currentMainWindowNode)
    elif key == ord('g'):
      let secondKey = getKey(currentMainWindowNode)
      if secondKey == 'g': status.moveToFirstLine
    elif key == ord('G'):
      status.moveToLastLine
