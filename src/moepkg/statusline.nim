import std/[strformat, os, osproc, strutils]
import syntax/highlite
import ui, bufferstatus, color, unicodeext, settings, window, gapbuffer

type
  StatusLineBuffer = object
    withColor: seq[Rune]
    withoutColor: seq[Rune]

  StatusLine* = object
    # Absolute position
    x: int
    y: int

    # Status line size
    w: int
    h: int

    # TODO: Rename
    windowIndex*: int

    bufferIndex*: int

proc initStatusLine*(): StatusLine {.inline.} =
  result.x = 1
  result.y = 1
  result.w = 1
  result.h = 1
  #color = EditorColorPair.defaultChar

proc resize*(statusLine: var StatusLine, height, width, y, x: int) =
  statusLine.h = height
  statusLine.w = width
  statusLine.y = y
  statusLine.x = x

proc showFilename(mode, prevMode: Mode): bool {.inline.} =
  not isHistoryManagerMode(mode, prevMode) and
  not isConfigMode(mode, prevMode)

proc add(
  statusLineBuffer: var StatusLineBuffer,
  buffer: seq[Rune],
  color: ColorPair) {.inline.} =

  statusLineBuffer.withoutColor.add buffer
  statusLineBuffer.withColor.add buffer.withColor(color)

proc len(statusLineBuffer: StatusLineBuffer): int {.inline.} =
  statusLineBuffer.withoutColor.len

proc `$`(statusLineBuffer: StatusLineBuffer): string =
  $statusLineBuffer.withColor

proc appendFileName(
  statusLineBuffer: var StatusLineBuffer,
  bufStatus: BufferStatus,
  color: ColorPair) =

  let
    mode = bufStatus.mode
    prevMode = bufStatus.prevMode
  var filename = if not showFilename(mode, prevMode): ru""
                 elif bufStatus.path.len > 0: bufStatus.path
                 else: ru"No name"
  let homeDir = ru(getHomeDir())
  if (filename.len() >= homeDir.len() and
      filename[0..homeDir.len()-1] == homeDir):
    filename = filename[homeDir.len()-1..filename.len()-1]
    if filename[0] == ru'/':
      filename = ru"~" & filename
    else:
      filename = ru"~/" & filename
  statusLineBuffer.add filename, color

proc setStatusLineColor(
  theme: ColorTheme,
  mode: Mode,
  isActiveWindow: bool): ColorPair =

  case mode:
    of Mode.insert:
      if isActiveWindow:
        return ColorThemeTable[theme].EditorColorPair.statusLineInsertMode
      else:
        return ColorThemeTable[theme].EditorColorPair.statusLineInsertModeInactive
    of Mode.visual:
      if isActiveWindow:
        return ColorThemeTable[theme].EditorColorPair.statusLineVisualMode
      else:
        return ColorThemeTable[theme].EditorColorPair.statusLineVisualModeInactive
    of Mode.replace:
      if isActiveWindow:
        return ColorThemeTable[theme].EditorColorPair.statusLineReplaceMode
      else:
        return ColorThemeTable[theme].EditorColorPair.statusLineReplaceModeInactive
    of Mode.ex:
      if isActiveWindow:
        return ColorThemeTable[theme].EditorColorPair.statusLineExMode
      else:
        return ColorThemeTable[theme].EditorColorPair.statusLineExModeInactive
    else:
      if isActiveWindow:
        return ColorThemeTable[theme].EditorColorPair.statusLineNormalMode
      else:
        return ColorThemeTable[theme].EditorColorPair.statusLineNormalModeInactive

proc buildStatusLineNormalModeInfo(
  bufStatus: var BufferStatus,
  statusLine: var StatusLine,
  statusLineBuffer: var StatusLineBuffer,
  windowNode: WindowNode,
  theme: ColorTheme,
  isActiveWindow: bool,
  settings: EditorSettings) =

  let
    color = setStatusLineColor(theme, bufStatus.mode, isActiveWindow)
    statusLineWidth = statusLine.w

  statusLineBuffer.add ru " ", color

  if settings.statusLine.filename:
    statusLineBuffer.appendFileName(bufStatus, color)

  if bufStatus.countChange > 0 and settings.statusLine.chanedMark:
    statusLineBuffer.add ru " [+]", color
    statusLineBuffer.add ru " [+]", color

  if statusLineWidth - statusLineBuffer.len < 0: return

  let
    line = if settings.statusLine.line:
             fmt"{windowNode.currentLine + 1}/{bufStatus.buffer.len}"
           else: ""
    column = if settings.statusLine.column:
               fmt"{windowNode.currentColumn + 1}/{bufStatus.buffer[windowNode.currentLine].len}"
             else: ""
    encoding = if settings.statusLine.characterEncoding: $bufStatus.characterEncoding
               else: ""
    language = if bufStatus.language == SourceLanguage.langNone: "Plain"
               else: sourceLanguageToStr[bufStatus.language]
    info = fmt"{line} {column} {encoding} {language} "

  block:
    let spaces = " ".repeat(statusLineWidth - (statusLineBuffer.len + info.len))
    statusLineBuffer.add spaces.toRunes, color

  statusLineBuffer.add info.toRunes, color

proc buildStatusLineFilerModeInfo(
  bufStatus: var BufferStatus,
  statusLine: var StatusLine,
  statusLineBuffer: var StatusLineBuffer,
  windowNode: WindowNode,
  theme: ColorTheme,
  isActiveWindow: bool,
  settings: EditorSettings) =

  let
    color =
      if isActiveWindow:
        ColorThemeTable[theme].EditorColorPair.statusLineFilerMode
      else:
        ColorThemeTable[theme].EditorColorPair.statusLineFilerModeInactive
    statusLineWidth = statusLine.w

  if settings.statusLine.directory:
    statusLineBuffer.add (fmt " {bufStatus.path}").toRunes, color

  let spaces = " ".repeat(statusLineWidth - 5)
  statusLineBuffer.add spaces.toRunes, color

proc buildStatusLineBufferManagerModeInfo(
  bufStatus: var BufferStatus,
  statusLine: var StatusLine,
  statusLineBuffer: var StatusLineBuffer,
  windowNode: WindowNode,
  theme: ColorTheme,
  isActiveWindow: bool,
  settings: EditorSettings) =

  let
    color =
      if isActiveWindow:
        ColorThemeTable[theme].EditorColorPair.statusLineNormalMode
      else:
        ColorThemeTable[theme].EditorColorPair.statusLineNormalModeInactive
    info = fmt"{windowNode.currentLine + 1}/{bufStatus.buffer.len - 1}"
    statusLineWidth = statusLine.w

  block:
    let spaces = " ".repeat(statusLineWidth - statusLineBuffer.len)
    statusLineBuffer.add spaces.toRunes, color

  statusLineBuffer.add info.toRunes, color

proc buildStatusLineLogViewerModeInfo(
  bufStatus: var BufferStatus,
  statusLine: var StatusLine,
  statusLineBuffer: var StatusLineBuffer,
  windowNode: WindowNode,
  theme: ColorTheme,
  isActiveWindow: bool,
  settings: EditorSettings) =

  let
    color =
      if isActiveWindow:
        ColorThemeTable[theme].EditorColorPair.statusLineNormalMode
      else:
        ColorThemeTable[theme].EditorColorPair.statusLineNormalModeInactive
    info = fmt"{windowNode.currentLine + 1}/{bufStatus.buffer.len - 1}"
    statusLineWidth = statusLine.w

  statusLineBuffer.add info.toRunes, color

proc buildStatusLineCurrentGitBranchName(
  statusLine: var StatusLine,
  statusLineBuffer: var StatusLineBuffer,
  theme: ColorTheme,
  isActiveWindow: bool) =

  # Get current git branch name
  let cmdResult = execCmdEx("git rev-parse --abbrev-ref HEAD")
  if cmdResult.exitCode != 0: return

  let
    branchName = cmdResult.output
    ## Add symbol and delete newline
    buffer = ru"  " & branchName[0 .. branchName.high - 1].toRunes & ru" "
    color = ColorThemeTable[theme].EditorColorPair.statusLineGitBranch

  statusLineBuffer.add buffer, color

proc getModeText(mode: Mode, isActiveWindow, showModeInactive: bool): seq[Rune] =
  if not isActiveWindow and not showModeInactive:
    result = ru ""
  else:
    case mode:
      of Mode.insert: result = ru " INSERT "
      of Mode.visual, Mode.visualBlock: result = ru " VISUAL "
      of Mode.replace: result = ru " REPLACE "
      of Mode.filer: result = ru " FILER "
      of Mode.bufManager: result = ru " BUFFER "
      of Mode.ex: result = ru " EX "
      of Mode.logViewer: result = ru " LOG "
      of Mode.recentFile: result = ru " RECENT "
      of Mode.quickRun: result = ru " QUICKRUN "
      of Mode.history: result = ru " HISTORY "
      of Mode.diff: result = ru "DIFF "
      of Mode.config: result = ru " CONFIG "
      of Mode.debug: result = ru " DEBUG "
      else: result = ru " NORMAL "

proc getModeTextColor(theme: ColorTheme, mode: Mode): ColorPair =
  case mode
    of Mode.insert:
      return ColorThemeTable[theme].EditorColorPair.statusLineModeInsertMode
    of Mode.visual:
      return ColorThemeTable[theme].EditorColorPair.statusLineModeVisualMode
    of Mode.replace:
      return ColorThemeTable[theme].EditorColorPair.statusLineModeReplaceMode
    of Mode.filer:
      return ColorThemeTable[theme].EditorColorPair.statusLineModeFilerMode
    of Mode.ex:
      return ColorThemeTable[theme].EditorColorPair.statusLineModeExMode
    else:
      return ColorThemeTable[theme].EditorColorPair.statusLineModeNormalMode

proc isShowGitBranchName(
  mode, prevMode: Mode,
  isActiveWindow: bool,
  settings: EditorSettings): bool =

  if settings.statusLine.gitbranchName:
    let showGitInactive = settings.statusLine.showGitInactive

    if showGitInactive or
    (not showGitInactive and isActiveWindow): result = true

  if mode == Mode.normal or
     mode == Mode.insert or
     mode == Mode.visual or
     mode == Mode.replace: result = true
  elif mode == Mode.ex:
    if prevMode == Mode.normal or
       prevMode == Mode.insert or
       prevMode == Mode.visual or
       prevMode == Mode.replace: result = true
  else:
    result = false

proc buildStatusLine*(
  bufStatus: var BufferStatus,
  statusLine: var StatusLine,
  windowNode: WindowNode,
  theme: ColorTheme,
  isActiveWindow: bool,
  settings: EditorSettings) =

  let
    currentMode = bufStatus.mode
    prevMode = bufStatus.prevMode
    color = getModeTextColor(theme, currentMode)
    modeText = getModeText(
      currentMode,
      isActiveWindow,
      settings.statusLine.showModeInactive)

  var statusLineBuffer: StatusLineBuffer

  if settings.statusLine.mode:
    ## Add current mode text
    if windowNode.x > 0:
      statusLineBuffer.add (ru" " & modeText), color
    else:
      statusLineBuffer.add modeText, color

  if isShowGitBranchName(currentMode, prevMode, isActiveWindow, settings):
    statusLine.buildStatusLineCurrentGitBranchName(
      statusLineBuffer,
      theme,
      isActiveWindow)

  if isFilerMode(currentMode, prevMode):
    bufStatus.buildStatusLineFilerModeInfo(
      statusLine,
      statusLineBuffer,
      windowNode,
      theme,
      isActiveWindow,
      settings)
  elif currentMode == Mode.bufManager:
    bufStatus.buildStatusLineBufferManagerModeInfo(
      statusLine,
      statusLineBuffer,
      windowNode,
      theme,
      isActiveWindow,
      settings)
  elif currentMode == Mode.logViewer:
    bufStatus.buildStatusLineLogViewerModeInfo(
      statusLine,
      statusLineBuffer,
      windowNode,
      theme,
      isActiveWindow,
      settings)
  else:
    bufStatus.buildStatusLineNormalModeInfo(
      statusLine,
      statusLineBuffer,
      windowNode,
      theme,
      isActiveWindow,
      settings)

  displayBuffer.add $statusLineBuffer
