import std/[strformat, os, osproc]
import syntax/highlite
import ui, bufferstatus, color, unicodeext, settings, window, gapbuffer

type StatusLine* = object
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

proc appendFileName(statusLineBuffer: var seq[Rune],
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
  statusLineBuffer.add(filename)
  # TODO: Fix
  #statusLineWindow.append(filename, color)

proc writeStatusLineNormalModeInfo(
  bufStatus: var BufferStatus,
  statusLine: var StatusLine,
  statusLineBuffer: var seq[Rune],
  windowNode: WindowNode,
  theme: ColorTheme,
  isActiveWindow: bool,
  settings: EditorSettings) =

  proc setStatusLineColor(theme: ColorTheme, mode: Mode): ColorPair =
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

  let
    color = setStatusLineColor(theme, bufStatus.mode)
    statusLineWidth = statusLine.w

  statusLineBuffer.add(ru" ")
  # TODO: Fix
  #statusLine.window.append(ru" ", color)

  if settings.statusLine.filename:
    statusLineBuffer.appendFileName(bufStatus, color)

  if bufStatus.countChange > 0 and settings.statusLine.chanedMark:
    statusLineBuffer.add(ru" [+]")
    # TODO: Fix
    #statusLine.window.append(ru" [+]", color)

  if statusLineWidth - statusLineBuffer.len < 0: return
  # TODO: Fix
  #statusLine.window.append(ru " ".repeat(statusLineWidth - statusLineBuffer.len), color)

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
  #statusLine.window.write(0, statusLineWidth - info.len, info, color)
  # TODO: Enable color
  let
    buf = info.withColor(color)
    x = statusLineWidth - info.len
  write(x, statusLine.y, info)

proc writeStatusLineFilerModeInfo(
  bufStatus: var BufferStatus,
  statusLine: var StatusLine,
  statusLineBuffer: var seq[Rune],
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
    discard
    # TODO: Fix
    #statusLine.window.append(ru" ", color)
    #statusLine.window.append(bufStatus.path, color)

  # TODO: Fix
  #statusLine.window.append(ru " ".repeat(statusLineWidth - 5), color)

proc writeStatusLineBufferManagerModeInfo(
  bufStatus: var BufferStatus,
  statusLine: var StatusLine,
  statusLineBuffer: var seq[Rune],
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

  # TODO: Fix
  #statusLine.window.append(ru " ".repeat(statusLineWidth - statusLineBuffer.len),
                                        #color)
  #statusLine.window.write(0, statusLineWidth - info.len - 1, info, color)
  write(0, statusLineWidth - info.len - 1, info)

proc writeStatusLineLogViewerModeInfo(
  bufStatus: var BufferStatus,
  statusLine: var StatusLine,
  statusLineBuffer: var seq[Rune],
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

  # TODO: Fix
  #statusLine.window.append(ru " ".repeat(statusLineWidth - statusLineBuffer.len),
                          #color)
  #statusLine.window.write(0, statusLineWidth - info.len - 1, info, color)
  write(0, statusLineWidth - info.len - 1, info)

proc writeStatusLineCurrentGitBranchName(
  statusLine: var StatusLine,
  statusLineBuffer: var seq[Rune],
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

  statusLineBuffer.add(buffer)
  # TODO: Fix
  #statusLine.window.append(buffer, color)

proc setModeStr(mode: Mode, isActiveWindow, showModeInactive: bool): string =
  if not isActiveWindow and not showModeInactive: result = ""
  else:
    case mode:
    of Mode.insert: result = " INSERT "
    of Mode.visual, Mode.visualBlock: result = " VISUAL "
    of Mode.replace: result = " REPLACE "
    of Mode.filer: result = " FILER "
    of Mode.bufManager: result = " BUFFER "
    of Mode.ex: result = " EX "
    of Mode.logViewer: result = " LOG "
    of Mode.recentFile: result = " RECENT "
    of Mode.quickRun: result = " QUICKRUN "
    of Mode.history: result = " HISTORY "
    of Mode.diff: result = "DIFF "
    of Mode.config: result = " CONFIG "
    of Mode.debug: result = " DEBUG "
    else: result = " NORMAL "

proc setModeStrColor(theme: ColorTheme, mode: Mode): ColorPair =
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

proc writeStatusLine*(
  bufStatus: var BufferStatus,
  statusLine: var StatusLine,
  windowNode: WindowNode,
  theme: ColorTheme,
  isActiveWindow: bool,
  settings: EditorSettings) =

  let
    currentMode = bufStatus.mode
    prevMode = bufStatus.prevMode
    color = setModeStrColor(theme, currentMode)
    modeStr = setModeStr(
      currentMode,
      isActiveWindow,
      settings.statusLine.showModeInactive)

  var statusLineBuffer = if windowNode.x > 0: ru" " & modeStr.toRunes
                         else: modeStr.toRunes

  ## Write current mode
  if settings.statusLine.mode:
    write(statusLine.x, statusLine.y, statusLineBuffer.withColor(color))

  if isShowGitBranchName(currentMode, prevMode, isActiveWindow, settings):
    statusLine.writeStatusLineCurrentGitBranchName(
      statusLineBuffer,
      theme,
      isActiveWindow)

  if isFilerMode(currentMode, prevMode):
    bufStatus.writeStatusLineFilerModeInfo(
      statusLine,
      statusLineBuffer,
      windowNode,
      theme,
      isActiveWindow,
      settings)
  elif currentMode == Mode.bufManager:
    bufStatus.writeStatusLineBufferManagerModeInfo(
      statusLine,
      statusLineBuffer,
      windowNode,
      theme,
      isActiveWindow,
      settings)
  elif currentMode == Mode.logViewer:
    bufStatus.writeStatusLineLogViewerModeInfo(
      statusLine,
      statusLineBuffer,
      windowNode,
      theme,
      isActiveWindow,
      settings)
  else:
    bufStatus.writeStatusLineNormalModeInfo(
      statusLine,
      statusLineBuffer,
      windowNode,
      theme,
      isActiveWindow,
      settings)
