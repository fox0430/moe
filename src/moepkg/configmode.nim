import terminal, times, typetraits, strutils
import gapbuffer, ui, editorstatus, unicodeext, window, movement, settings,
       bufferstatus, color, highlight

const
  # Settings names
  standardTableNames = [
    "theme",
    "number",
    "currentNumber",
    "cursorLine",
    "statusBar",
    "tabLine",
    "syntax",
    "indentationLines",
    "tabStop",
    "autoCloseParen",
    "autoIndent",
    "disableChangeCursor",
    "defaultCursor",
    "normalModeCursor",
    "insertModeCursor",
    "autoSave",
    "autoSaveInterval",
    "liveReloadOfConf",
    "incrementalSearch",
    "popUpWindowInExmode",
    "replaceTextHighlight",
    "highlightPairOfParen",
    "autoDeleteParen",
    "systemClipboard",
    "highlightFullWidthSpace",
    "highlightTrailingSpaces",
    "highlightCurrentWord"
  ]
  buildOnSaveTableNames = [
    "enable",
    "workspaceRoot",
    "command"
  ]
  tabLineTableNames = [
    "allBuffer"
  ]
  statusBarTableNames = [
    "mode",
    "filename",
    "chanedMark",
    "line",
    "column",
    "encoding",
    "language",
    "directory",
    "multipleStatusBar",
    "gitbranchName",
    "showGitInactive",
    "showModeInactive"
  ]
  workSpaceTableNames = [
    "workSpaceLine"
  ]
  highlightTableNames = [
    "reservedWord"
  ]
  autoBackupTableNames = [
    "enable",
    "idolTime",
    "interval",
    "backupDir",
    "dirToExclude"
  ]
  quickRunTableNames = [
    "saveBufferWhenQuickRun",
    "command",
    "timeout",
    "nimAdvancedCommand",
    "ClangOptions",
    "CppOptions",
    "NimOptions",
    "shOptions",
    "bashOptions"
  ]
  notificationTableNames = [
    "screenNotifications",
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
    "restoreLogNotify"
  ]
  filerTableNames = [
    "showIcons"
  ]
  themeTableNames = [
    "editorBg",
    "lineNum",
    "currentLineNum",
    "statusBarNormalMode",
    "statusBarModeNormalMode",
    "statusBarNormalModeInactive",
    "statusBarInsertMode",
    "statusBarModeInsertMode",
    "statusBarInsertModeInactive",
    "statusBarVisualMode",
    "statusBarModeVisualMode",
    "statusBarVisualModeInactive",
    "statusBarReplaceMode",
    "statusBarModeReplaceMode",
    "statusBarReplaceModeInactive",
    "statusBarFilerMode",
    "statusBarModeFilerMode",
    "statusBarFilerModeInactive",
    "statusBarExMode",
    "statusBarModeExMode",
    "statusBarExModeInactive",
    "statusBarGitBranch",
    "tab",
    "currentTab",
    "commandBar",
    "errorMessage",
    "searchResult",
    "visualMode",
    "defaultChar",
    "gtKeyword",
    "gtStringLit",
    "gtDecNumber",
    "gtComment",
    "gtLongComment",
    "gtWhitespace",
    "gtPreprocessor",
    "currentFile",
    "file",
    "dir",
    "pcLink",
    "popUpWindow",
    "popUpWinCurrentLine",
    "replaceText",
    "parenText",
    "currentWord",
    "highlightFullWidthSpace",
    "highlightTrailingSpaces",
    "workSpaceBar",
    "reservedWord",
    "currentSetting"
  ]

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

proc calcPositionOfSettingValue(): int {.compileTime.} =
  var names: seq[string]

  for name in standardTableNames: names.add(name)
  for name in buildOnSaveTableNames: names.add(name)
  for name in tabLineTableNames: names.add(name)
  for name in workSpaceTableNames: names.add(name)
  for name in highlightTableNames: names.add(name)
  for name in autoBackupTableNames: names.add(name)
  for name in quickRunTableNames: names.add(name)
  for name in notificationTableNames: names.add(name)
  for name in filerTableNames: names.add(name)
  for name in themeTableNames: names.add(name)

  for name in names:
    if result < name.len: result = name.len

  const numOfIndent = 2
  result += numOfIndent

const
  positionOfSetVal = calcPositionOfSettingValue()
  indent = "  "

proc initStandardTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"Standard")

  for name in standardTableNames:
    let
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
      of "theme":
        result.add(ru nameStr & space & $settings.editorColorTheme)
      of "number":
        result.add(ru nameStr & space & $settings.view.lineNumber)
      of "currentNumber":
        result.add(ru nameStr & space & $settings.view.currentLineNumber)
      of "cursorLine":
        result.add(ru nameStr & space & $settings.view.cursorLine)
      of "statusBar":
        result.add(ru nameStr & space & $settings.statusBar.useBar)
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
      of "replaceTextHighlight":
        result.add(ru nameStr & space & $settings.replaceTextHighlight)
      of "highlightPairOfParen":
        result.add(ru nameStr & space & $settings.highlightPairOfParen)
      of "autoDeleteParen":
        result.add(ru nameStr & space & $settings.autoDeleteParen)
      of "systemClipboard":
        result.add(ru nameStr & space & $settings.systemClipboard)
      of "highlightFullWidthSpace":
        result.add(ru nameStr & space & $settings.highlightFullWidthSpace)
      of "highlightTrailingSpaces":
        result.add(ru nameStr & space & $settings.highlightTrailingSpaces)
      of "highlightCurrentWord":
        result.add(ru nameStr & space & $settings.highlightOtherUsesCurrentWord)

proc initBuildOnSaveTableBuffer(settings: BuildOnSaveSettings): seq[seq[Rune]] =
  result.add(ru"BuildOnSave")

  for name in buildOnSaveTableNames:
    let
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
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
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
      of "allBuffer":
        result.add(ru nameStr & space & $settings.tabLine.allBuffer)

proc initStatusBarTableBuffer(settings: StatusBarSettings): seq[seq[Rune]] =
  result.add(ru"StatusBar")

  for name in statusBarTableNames:
    let
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
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
      of "multipleStatusBar":
        result.add(ru nameStr & space & $settings.multipleStatusBar)
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
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
      of "workSpaceLine":
        result.add(ru nameStr & space & $settings.workSpace.workSpaceLine)

proc initHighlightTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"Highlight")

  for name in highlightTableNames:
    case name:
      of "reservedWord":
        result.add(ru indent & name)
        let space = " ".repeat(positionOfSetVal)
        for reservedWord in settings.reservedWords:
          result.add(ru indent & space & reservedWord.word)

proc initAutoBackupTableBuffer(settings: AutoBackupSettings): seq[seq[Rune]] =
  result.add(ru"AutoBackup")

  for name in autoBackupTableNames:
    let
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
      of "enable":
        result.add(ru nameStr & space & $settings.enable)
      of "idolTime":
        result.add(ru nameStr & space & $settings.idolTime)
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
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
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
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
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
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
      of "showIcons":
        result.add(ru nameStr & space & $settings.filerSettings.showIcons)

proc calcPositionOfThemeSettingValue(theme: ColorTheme): int =
  for colorPair in EditorColorPair:
    let
      colors = getColorFromEditorColorPair(theme, colorPair)
      color = $colors[0]

    if result < color.len: result = color.len

proc initThemeTableBuffer*(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"Theme")

  let theme = settings.editorColorTheme

  for name in themeTableNames:
    let
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
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
      of "statusBarNormalMode":
        let
          colorPair = EditorColorPair.statusBarNormalMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarModeNormalMode":
        let
          colorPair = EditorColorPair.statusBarModeNormalMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarNormalModeInactive":
        let
          colorPair = EditorColorPair.statusBarNormalModeInactive
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarInsertMode":
        let
          colorPair = EditorColorPair.statusBarInsertMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarModeInsertMode":
        let
          colorPair = EditorColorPair.statusBarModeInsertMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarInsertModeInactive":
        let
          colorPair = EditorColorPair.statusBarInsertModeInactive
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarVisualMode":
        let
          colorPair = EditorColorPair.statusBarVisualMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarModeVisualMode":
        let
          colorPair = EditorColorPair.statusBarModeVisualMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarVisualModeInactive":
        let
          colorPair = EditorColorPair.statusBarVisualModeInactive
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarReplaceMode":
        let
          colorPair = EditorColorPair.statusBarReplaceMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarModeReplaceMode":
        let
          colorPair = EditorColorPair.statusBarModeReplaceMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarReplaceModeInactive":
        let
          colorPair = EditorColorPair.statusBarReplaceModeInactive
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarFilerMode":
        let
          colorPair = EditorColorPair.statusBarFilerMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarModeFilerMode":
        let
          colorPair = EditorColorPair.statusBarModeFilerMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarFilerModeInactive":
        let
          colorPair = EditorColorPair.statusBarFilerModeInactive
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarExMode":
        let
          colorPair = EditorColorPair.statusBarExMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarModeExMode":
        let
          colorPair = EditorColorPair.statusBarModeExMode
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarExModeInactive":
        let
          colorPair = EditorColorPair.statusBarExModeInactive
          colors = getColorFromEditorColorPair(theme, colorPair)
          secondSpaceLen = calcPositionOfThemeSettingValue(theme)
          secondSpace = " ".repeat(secondSpaceLen - ($colors[0]).len)
        result.add(ru nameStr & space & $colors[0] & secondSpace & $colors[1])
      of "statusBarGitBranch":
        let
          colorPair = EditorColorPair.statusBarGitBranch
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
  buffer.add(initTabLineTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initStatusBarTableBuffer(settings.statusBar))

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

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    currentWorkSpace = status.currentWorkSpaceIndex

  status.bufStatus[currentBufferIndex].buffer = initConfigModeBuffer(
    status.settings)

  while status.isConfigMode and
        currentWorkSpace == status.currentWorkSpaceIndex and
        currentBufferIndex == status.bufferIndexInCurrentWindow:
        
    let
      currentBufferIndex = status.bufferIndexInCurrentWindow
      workspaceIndex = status.currentWorkSpaceIndex
      node = status.workspace[workspaceIndex].currentMainWindowNode
      buffer = status.bufStatus[currentBufferIndex].buffer
      highlight = buffer.initConfigModeHighlight(node.currentLine)

    status.workspace[workspaceIndex].currentMainWindowNode.highlight = highlight

    status.update
    setCursor(false)

    var key: Rune = ru'\0'
    while key == ru'\0':
      status.eventLoopTask
      let index = status.currentWorkSpaceIndex
      key = getKey(status.workSpace[index].currentMainWindowNode.window)

    status.lastOperatingTime = now()

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase
    elif isControlK(key): status.moveNextWindow
    elif isControlJ(key): status.movePrevWindow
    elif key == ord(':'): status.changeMode(Mode.ex)

    elif key == ord('k') or isUpKey(key):
      status.bufStatus[currentBufferIndex].keyUp(
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      status.bufStatus[currentBufferIndex].keyDown(
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    elif key == ord('g'):
      let
        index = status.currentWorkSpaceIndex
        secondKey = getKey(
          status.workSpace[index].currentMainWindowNode.window)
      if secondKey == 'g': status.moveToFirstLine
    elif key == ord('G'): status.moveToLastLine
