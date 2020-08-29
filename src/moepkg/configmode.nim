import terminal, times, typetraits, strutils, strformat
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
    let color =
      if i == currentLine: EditorColorPair.currentSetting
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

proc initBuildOnSaveTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"BuildOnSave")

  for name in buildOnSaveTableNames:
    let
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
      of "enable":
        result.add(ru nameStr & space & $settings.buildOnSave.enable)
      of "workspaceRoot":
        result.add(ru nameStr & space & $settings.buildOnSave.workspaceRoot)
      of "command":
        result.add(ru nameStr & space & $settings.buildOnSave.command)

proc initTabLineTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"TabLine")

  for name in tabLineTableNames:
    let
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
      of "allBuffer":
        result.add(ru nameStr & space & $settings.tabLine.allBuffer)

proc initStatusBarTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"StatusBar")

  for name in statusBarTableNames:
    let
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
      of "mode":
        result.add(ru nameStr & space & $settings.statusBar.mode)
      of "filename":
        result.add(ru nameStr & space & $settings.statusBar.filename)
      of "chanedMark":
        result.add(ru nameStr & space & $settings.statusBar.chanedMark)
      of "line":
        result.add(ru nameStr & space & $settings.statusBar.line)
      of "column":
        result.add(ru nameStr & space & $settings.statusBar.column)
      of "encoding":
        result.add(ru nameStr & space & $settings.statusBar.characterEncoding)
      of "language":
        result.add(ru nameStr & space & $settings.statusBar.language)
      of "directory":
        result.add(ru nameStr & space & $settings.statusBar.directory)
      of "multipleStatusBar":
        result.add(ru nameStr & space & $settings.statusBar.multipleStatusBar)
      of "gitbranchName":
        result.add(ru nameStr & space & $settings.statusBar.gitbranchName)
      of "showGitInactive":
        result.add(ru nameStr & space & $settings.statusBar.showGitInactive)
      of "showModeInactive":
        result.add(ru nameStr & space & $settings.statusBar.showModeInactive)

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

proc initAutoBackupTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"AutoBackup")

  for name in autoBackupTableNames:
    let
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
      of "enable":
        result.add(ru nameStr & space & $settings.autoBackupSettings.enable)
      of "idolTime":
        result.add(ru nameStr & space & $settings.autoBackupSettings.idolTime)
      of "interval":
        result.add(ru nameStr & space & $settings.autoBackupSettings.interval)
      of "backupDir":
        result.add(ru nameStr & space & $settings.autoBackupSettings.backupDir)
      of "dirToExclude":
        result.add(ru nameStr & space & $settings.autoBackupSettings.dirToExclude)

proc initQuickRunTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"QuickRun")

  let quickRunSettings = settings.quickRunSettings
  for name in quickRunTableNames:
    let
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
      of "saveBufferWhenQuickRun":
        result.add(ru nameStr & space & $quickRunSettings.saveBufferWhenQuickRun)
      of "command":
        result.add(ru nameStr & space & $quickRunSettings.command)
      of "timeout":
        result.add(ru nameStr & space & $quickRunSettings.timeout)
      of "nimAdvancedCommand":
        result.add(ru nameStr & space & $quickRunSettings.nimAdvancedCommand)
      of "ClangOptions":
        result.add(ru nameStr & space & $quickRunSettings.ClangOptions)
      of "CppOptions":
        result.add(ru nameStr & space & $quickRunSettings.CppOptions)
      of "NimOptions":
        result.add(ru nameStr & space & $quickRunSettings.NimOptions)
      of "shOptions":
        result.add(ru nameStr & space & $quickRunSettings.shOptions)
      of "bashOptions":
        result.add(ru nameStr & space & $quickRunSettings.bashOptions)

proc initNotificationTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"Notification")

  let notificationSettings = settings.notificationSettings
  for name in notificationTableNames:
    let
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
      of "screenNotifications":
        result.add(ru nameStr & space & $notificationSettings.screenNotifications)
      of "logNotifications":
        result.add(ru nameStr & space & $notificationSettings.logNotifications)
      of "autoBackupScreenNotify":
        result.add(ru nameStr & space & $notificationSettings.autoBackupScreenNotify)
      of "autoBackupLogNotify":
        result.add(ru nameStr & space & $notificationSettings.autoBackupLogNotify)
      of "autoSaveScreenNotify":
        result.add(ru nameStr & space & $notificationSettings.autoSaveScreenNotify)
      of "autoSaveLogNotify":
        result.add(ru nameStr & space & $notificationSettings.autoSaveLogNotify)
      of "yankScreenNotify":
        result.add(ru nameStr & space & $notificationSettings.yankScreenNotify)
      of "yankLogNotify":
        result.add(ru nameStr & space & $notificationSettings.yankLogNotify)
      of "deleteScreenNotify":
        result.add(ru nameStr & space & $notificationSettings.deleteScreenNotify)
      of "deleteLogNotify":
        result.add(ru nameStr & space & $notificationSettings.deleteLogNotify)
      of "saveScreenNotify":
        result.add(ru nameStr & space & $notificationSettings.saveScreenNotify)
      of "saveLogNotify":
        result.add(ru nameStr & space & $notificationSettings.saveLogNotify)
      of "workspaceScreenNotify":
        result.add(ru nameStr & space & $notificationSettings.workspaceScreenNotify)
      of "workspaceLogNotify":
        result.add(ru nameStr & space & $notificationSettings.workspaceLogNotify)
      of "quickRunScreenNotify":
        result.add(ru nameStr & space & $notificationSettings.quickRunScreenNotify)
      of "quickRunLogNotify":
        result.add(ru nameStr & space & $notificationSettings.quickRunLogNotify)
      of "buildOnSaveScreenNotify":
        result.add(ru nameStr & space & $notificationSettings.buildOnSaveScreenNotify)
      of "buildOnSaveLogNotify":
        result.add(ru nameStr & space & $notificationSettings.buildOnSaveLogNotify)
      of "filerScreenNotify":
        result.add(ru nameStr & space & $notificationSettings.filerScreenNotify)
      of "filerLogNotify":
        result.add(ru nameStr & space & $notificationSettings.filerLogNotify)
      of "restoreScreenNotify":
        result.add(ru nameStr & space & $notificationSettings.restoreScreenNotify)
      of "restoreLogNotify":
        result.add(ru nameStr & space & $notificationSettings.restoreLogNotify)

proc initFilerTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"Filer")

  for name in filerTableNames:
    let
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
      of "showIcons":
        result.add(ru nameStr & space & $settings.filerSettings.showIcons)

proc initThemeTableBuffer*(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"Theme")

  let theme = settings.editorColorTheme
  for name in themeTableNames:
    let
      nameStr = indent & name
      space = " ".repeat(positionOfSetVal - name.len)
    case name:
      #of "editorBg":
      #  let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.editorBg)
      #  result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "lineNum":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.lineNum)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "currentLineNum":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.currentLineNum)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarNormalMode":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarNormalMode)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarModeNormalMode":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarModeNormalMode)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarNormalModeInactive":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarNormalModeInactive)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarInsertMode":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarInsertMode)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarModeInsertMode":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarModeInsertMode)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarInsertModeInactive":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarInsertModeInactive)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarVisualMode":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarVisualMode)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarModeVisualMode":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarModeVisualMode)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarVisualModeInactive":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarVisualModeInactive)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarReplaceMode":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarReplaceMode)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarModeReplaceMode":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarModeReplaceMode)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarReplaceModeInactive":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarReplaceModeInactive)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarFilerMode":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarFilerMode)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarModeFilerMode":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarModeFilerMode)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarFilerModeInactive":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarFilerModeInactive)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarExMode":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarExMode)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarModeExMode":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarModeExMode)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarExModeInactive":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarExModeInactive)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "statusBarGitBranch":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarGitBranch)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "tab":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.tab)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "currentTab":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.currentTab)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "commandBar":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.commandBar)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "errorMessage":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.errorMessage)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "searchResult":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.searchResult)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "visualMode":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.visualMode)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "defaultChar":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.defaultChar)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "keyword":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.keyword)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "stringLit":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.stringLit)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "decNumber":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.decNumber)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "comment":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.comment)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "longComment":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.longComment)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "whitespace":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.whitespace)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "preprocessor":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.preprocessor)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "currentFile":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.currentFile)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "file":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.file)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "dir":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.dir)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "pcLink":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.pcLink)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "popUpWindow":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.popUpWindow)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "popUpWinCurrentLine":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.popUpWinCurrentLine)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "replaceText":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.replaceText)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "parenText":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.parenText)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "currentWord":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.currentWord)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "highlightFullWidthSpace":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.highlightFullWidthSpace)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "highlightTrailingSpaces":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.highlightTrailingSpaces)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "workSpaceBar":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.workSpaceBar)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "reservedWord":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.reservedWord)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])
      of "currentSetting":
        let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.currentSetting)
        result.add(ru nameStr & space & $colorPair[0] & " " & $colorPair[1])

proc initConfigModeBuffer*(settings: EditorSettings): GapBuffer[seq[Rune]] =
  var buffer: seq[seq[Rune]]
  buffer.add(initStandardTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initTabLineTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initStatusBarTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initWorkspaceTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initHighlightTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initAutoBackupTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initQuickRunTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initNotificationTableBuffer(settings))

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
      currentLine = status.workspace[workspaceIndex].currentMainWindowNode.currentLine
      highlight = status.bufStatus[currentBufferIndex].buffer.initConfigModeHighlight(currentLine)

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
      if getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window) == 'g':
        status.moveToFirstLine
    elif key == ord('G'): status.moveToLastLine
