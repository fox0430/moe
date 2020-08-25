import terminal, times, typetraits, strutils, strformat
import gapbuffer, ui, editorstatus, unicodeext, window, movement, settings,
       bufferstatus, color

proc initStandardTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"Standard")
  result.add(ru"  theme " & ($settings.editorColorTheme).ru)
  result.add(ru"  number " & ($settings.view.lineNumber).ru)
  result.add(ru"  currentNumber " & ($settings.view.currentLineNumber).ru)
  result.add(ru"  cursorLine " & ($settings.view.cursorLine).ru)
  result.add(ru"  statusBar " & ($settings.statusBar.useBar).ru)
  result.add(ru"  tabLine " & ($settings.tabLine.useTab).ru)
  result.add(ru"  syntax " & ($settings.syntax).ru)
  result.add(ru"  indentationLines " & ($settings.view.indentationLines).ru)
  result.add(ru"  tabStop " & ($settings.view.tabStop).ru)
  result.add(ru"  autoCloseParen " & ($settings.autoCloseParen).ru)
  result.add(ru"  autoIndent " & ($settings.autoIndent).ru)
  result.add(ru"  disableChangeCursor " & ($settings.disableChangeCursor).ru)
  result.add(ru"  defaultCursor " & ($settings.defaultCursor).ru)
  result.add(ru"  normalModeCursor " & ($settings.normalModeCursor).ru)
  result.add(ru"  insertModeCursor " & ($settings.insertModeCursor).ru)
  result.add(ru"  autoSave " & ($settings.autoSave).ru)
  result.add(ru"  autoSaveInterval " & ($settings.autoSaveInterval).ru)
  result.add(ru"  liveReloadOfConf " & ($settings.liveReloadOfConf).ru)
  result.add(ru"  incrementalSearch " & ($settings.incrementalSearch).ru)
  result.add(ru"  popUpWindowInExmode " & ($settings.popUpWindowInExmode).ru)
  result.add(ru"  replaceTextHighlight " & ($settings.replaceTextHighlight).ru)
  result.add(ru"  highlightPairOfParen " & ($settings.highlightPairOfParen).ru)
  result.add(ru"  autoDeleteParen " & ($settings.autoDeleteParen).ru)
  result.add(ru"  systemClipboard " & ($settings.systemClipboard).ru)
  result.add(ru"  highlightFullWidthSpace " &
               ($settings.highlightFullWidthSpace).ru)
  result.add(ru"  highlightTrailingSpaces " &
               ($settings.highlightTrailingSpaces).ru)
  result.add(ru"  highlightCurrentWord " &
               ($settings.highlightOtherUsesCurrentWord).ru)

proc initBuildOnSaveTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"BuildOnSave")
  result.add(ru"  enable " & ($settings.buildOnSave.enable).ru)
  result.add(ru"  workspaceRoot " & ($settings.buildOnSave.workspaceRoot).ru)
  result.add(ru"  command " & ($settings.buildOnSave.command).ru)

proc initTabLineTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"TabLine")
  result.add(ru"  allBuffer " & ($settings.tabLine.allBuffer).ru)

proc initStatusBarTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"StatusBar")
  result.add(ru"  mode " & ($settings.statusBar.mode).ru)
  result.add(ru"  filename " & ($settings.statusBar.filename).ru)
  result.add(ru"  chanedMark " & ($settings.statusBar.chanedMark).ru)
  result.add(ru"  line " & ($settings.statusBar.line).ru)
  result.add(ru"  column " & ($settings.statusBar.column).ru)
  result.add(ru"  encoding " & ($settings.statusBar.characterEncoding).ru)
  result.add(ru"  language " & ($settings.statusBar.language).ru)
  result.add(ru"  directory " & ($settings.statusBar.directory).ru)
  result.add(ru"  multipleStatusBar " & ($settings.statusBar.multipleStatusBar).ru)
  result.add(ru"  gitbranchName " & ($settings.statusBar.gitbranchName).ru)
  result.add(ru"  showGitInactive " & ($settings.statusBar.showGitInactive).ru)
  result.add(ru"  showModeInactive " & ($settings.statusBar.showModeInactive ).ru)

proc initWorkspaceTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"WorkSpace")
  result.add(ru"  workSpaceLine " & ($settings.workSpace.workSpaceLine).ru)

proc initHighlightTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"Highlight")
  result.add(ru"  reservedWord " & ($settings.reservedWords).ru)

proc initAutoBackupTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"AutoBackup")
  result.add(ru"  enable " & ($settings.autoBackupSettings.enable).ru)
  result.add(ru"  idolTime " & ($settings.autoBackupSettings.idolTime).ru)
  result.add(ru"  interval " & ($settings.autoBackupSettings.interval).ru)
  result.add(ru"  backupDir " & ($settings.autoBackupSettings.backupDir).ru)
  result.add(ru"  dirToExclude " &
               ($settings.autoBackupSettings.dirToExclude).ru)

proc initQuickRunTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"QuickRun")
  result.add(ru"  saveBufferWhenQuickRun " &
               ($settings.quickRunSettings.saveBufferWhenQuickRun).ru)
  result.add(ru"  command " & ($settings.quickRunSettings.command).ru)
  result.add(ru"  timeout " & ($settings.quickRunSettings.timeout).ru)
  result.add(ru"  nimAdvancedCommand " &
               ($settings.quickRunSettings.nimAdvancedCommand).ru)
  result.add(ru"  ClangOptions " & ($settings.quickRunSettings.ClangOptions).ru)
  result.add(ru"  CppOptions " & ($settings.quickRunSettings.CppOptions).ru)
  result.add(ru"  NimOptions " & ($settings.quickRunSettings.NimOptions).ru)
  result.add(ru"  shOptions " & ($settings.quickRunSettings.shOptions).ru)
  result.add(ru"  bashOptions " & ($settings.quickRunSettings.bashOptions).ru)

proc initNotificationTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"Notification")
  result.add(ru"  screenNotifications " & ($settings.notificationSettings.screenNotifications).ru)
  result.add(ru"  logNotifications " & ($settings.notificationSettings.logNotifications).ru)
  result.add(ru"  autoBackupScreenNotify " & ($settings.notificationSettings.autoBackupScreenNotify).ru)
  result.add(ru"  autoBackupLogNotify " & ($settings.notificationSettings.autoBackupLogNotify).ru)
  result.add(ru"  autoSaveScreenNotify " & ($settings.notificationSettings.autoSaveScreenNotify).ru)
  result.add(ru"  autoSaveLogNotify " & ($settings.notificationSettings.autoSaveLogNotify).ru)
  result.add(ru"  yankScreenNotify " & ($settings.notificationSettings.yankScreenNotify).ru)
  result.add(ru"  yankLogNotify " & ($settings.notificationSettings.yankLogNotify).ru)
  result.add(ru"  deleteScreenNotify " & ($settings.notificationSettings.deleteScreenNotify).ru)
  result.add(ru"  deleteLogNotify " & ($settings.notificationSettings.deleteLogNotify).ru)
  result.add(ru"  saveScreenNotify " & ($settings.notificationSettings.saveScreenNotify).ru)
  result.add(ru"  saveLogNotify " & ($settings.notificationSettings.saveLogNotify).ru)
  result.add(ru"  workspaceScreenNotify " & ($settings.notificationSettings.workspaceScreenNotify).ru)
  result.add(ru"  workspaceLogNotify " & ($settings.notificationSettings.workspaceLogNotify).ru)
  result.add(ru"  quickRunScreenNotify " & ($settings.notificationSettings.quickRunScreenNotify).ru)
  result.add(ru"  quickRunLogNotify " & ($settings.notificationSettings.quickRunLogNotify).ru)
  result.add(ru"  buildOnSaveScreenNotify " & ($settings.notificationSettings.buildOnSaveScreenNotify).ru)
  result.add(ru"  buildOnSaveLogNotify " & ($settings.notificationSettings.buildOnSaveLogNotify).ru)
  result.add(ru"  filerScreenNotify " & ($settings.notificationSettings.filerScreenNotify).ru)
  result.add(ru"  filerLogNotify " & ($settings.notificationSettings.filerLogNotify).ru)
  result.add(ru"  restoreScreenNotify " & ($settings.notificationSettings.restoreScreenNotify).ru)
  result.add(ru"  restoreLogNotify " & ($settings.notificationSettings.restoreLogNotify).ru)

proc initFilerTableBuffer(settings: EditorSettings): seq[seq[Rune]] =
  result.add(ru"Filer")
  result.add(ru"  showIcons " & ($settings.filerSettings.showIcons).ru)

proc initThemeTableBuffer*(settings: EditorSettings): seq[Rune] =
  let theme = settings.editorColorTheme

  result.add(ru"Theme")
  #block:
  #  let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.editorBg)
  #  buffer.add(ru fmt"  lineNum {$colorPair[0]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.lineNum)
    result.add(ru fmt"  lineNum {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.currentLineNum)
    result.add(ru fmt"  currentLineNum {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarNormalMode)
    result.add(ru fmt"  statusBarNormalMode {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarModeNormalMode)
    result.add(ru fmt"  statusBarModeNormalMode {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarNormalModeInactive)
    result.add(ru fmt"  statusBarNormalModeInactive {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarInsertMode)
    result.add(ru fmt"  statusBarInsertMode {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarModeInsertMode)
    result.add(ru fmt"  statusBarModeInsertMode {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarInsertModeInactive)
    result.add(ru fmt"  statusBarInsertModeInactive {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarVisualMode)
    result.add(ru fmt"  statusBarVisualMode {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarModeVisualMode)
    result.add(ru fmt"  statusBarModeVisualMode {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarVisualModeInactive)
    result.add(ru fmt"  statusBarVisualModeInactive {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarReplaceMode)
    result.add(ru fmt"  statusBarReplaceMode {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarModeReplaceMode)
    result.add(ru fmt"  statusBarModeReplaceMode {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarReplaceModeInactive)
    result.add(ru fmt"  statusBarReplaceModeInactive {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarFilerMode)
    result.add(ru fmt"  statusBarFilerMode {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarModeFilerMode)
    result.add(ru fmt"  statusBarModeFilerMode {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarFilerModeInactive)
    result.add(ru fmt"  statusBarFilerModeInactive {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarExMode)
    result.add(ru fmt"  statusBarExMode {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarModeExMode)
    result.add(ru fmt"  statusBarModeExMode {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarExModeInactive)
    result.add(ru fmt"  statusBarExModeInactive {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.statusBarGitBranch)
    result.add(ru fmt"  statusBarGitBranch {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.tab)
    result.add(ru fmt"  tab {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.currentTab)
    result.add(ru fmt"  currentTab {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.commandBar)
    result.add(ru fmt"  commandBar {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.errorMessage)
    result.add(ru fmt"  errorMessage {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.searchResult)
    result.add(ru fmt"  searchResult {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.visualMode)
    result.add(ru fmt"  visualMode {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.defaultChar)
    result.add(ru fmt"  defaultChar {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.keyword)
    result.add(ru fmt"  gtKeyword {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.stringLit)
    result.add(ru fmt"  gtStringLit {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.decNumber)
    result.add(ru fmt"  gtDecNumber {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.comment)
    result.add(ru fmt"  gtComment {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.longComment)
    result.add(ru fmt"  gtLongComment {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.whitespace)
    result.add(ru fmt"  gtWhitespace {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.preprocessor)
    result.add(ru fmt"  gtPreprocessor {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.currentFile)
    result.add(ru fmt"  currentFile {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.file)
    result.add(ru fmt" file  {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.dir)
    result.add(ru fmt"  dir {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.pcLink)
    result.add(ru fmt"  pcLink {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.popUpWindow)
    result.add(ru fmt"  popUpWindow {$colorPair[0]} {$colorPair[1]}")
  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.popUpWinCurrentLine)
    result.add(ru fmt"  popUpWinCurrentLine {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.replaceText)
    result.add(ru fmt"  replaceText {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.parenText)
    result.add(ru fmt"  parenText {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.currentWord)
    result.add(ru fmt"  currentWord {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.highlightFullWidthSpace)
    result.add(ru fmt"  highlightFullWidthSpace {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.highlightTrailingSpaces)
    result.add(ru fmt"  highlightTrailingSpaces {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.workSpaceBar)
    result.add(ru fmt"  workSpaceBar {$colorPair[0]} {$colorPair[1]}")

  block:
    let colorPair = getColorFromEditorColorPair(theme, EditorColorPair.reservedWord)
    result.add(ru fmt"  reservedWord {$colorPair[0]} {$colorPair[1]}")

proc initConfigModeBuffer*(settings: EditorSettings): GapBuffer[seq[Rune]] =
  var buffer: seq[seq[Rune]]
  buffer.add(initStandardTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initnotificationTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initTabLineTableBuffer(settings))

  buffer.add(ru"")
  buffer.add(initStandardTableBuffer(settings))

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
  status.bufStatus[index].mode == Mode.config

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
        
    let currentBufferIndex = status.bufferIndexInCurrentWindow
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
