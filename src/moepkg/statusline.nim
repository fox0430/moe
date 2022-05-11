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
                    color: EditorColorPair) =

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

proc writeStatusLineNormalModeInfo(bufStatus: var BufferStatus,
                                   statusLine: var StatusLine,
                                   statusLineBuffer: var seq[Rune],
                                   windowNode: WindowNode,
                                   isActiveWindow: bool,
                                   settings: EditorSettings) =

  proc setStatusLineColor(mode: Mode): EditorColorPair =
    case mode:
      of Mode.insert:
        if isActiveWindow: return EditorColorPair.statusLineInsertMode
        else: return EditorColorPair.statusLineInsertModeInactive
      of Mode.visual:
        if isActiveWindow: return EditorColorPair.statusLineVisualMode
        else: return EditorColorPair.statusLineVisualModeInactive
      of Mode.replace:
        if isActiveWindow: return EditorColorPair.statusLineReplaceMode
        else: return EditorColorPair.statusLineReplaceModeInactive
      of Mode.ex:
        if isActiveWindow: return EditorColorPair.statusLineExMode
        else: return EditorColorPair.statusLineExModeInactive
      else:
        if isActiveWindow: return EditorColorPair.statusLineNormalMode
        else: return EditorColorPair.statusLineNormalModeInactive

  let
    color = setStatusLineColor(bufStatus.mode)
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
  let x = statusLineWidth - info.len
  write(x, statusLine.y, info)

proc writeStatusLineFilerModeInfo(bufStatus: var BufferStatus,
                                 statusLine: var StatusLine,
                                 statusLineBuffer: var seq[Rune],
                                 windowNode: WindowNode,
                                 isActiveWindow: bool,
                                 settings: EditorSettings) =

  let
    color = if isActiveWindow: EditorColorPair.statusLineFilerMode
            else: EditorColorPair.statusLineFilerModeInactive
    statusLineWidth = statusLine.w

  if settings.statusLine.directory:
    discard
    # TODO: Fix
    #statusLine.window.append(ru" ", color)
    #statusLine.window.append(bufStatus.path, color)

  # TODO: Fix
  #statusLine.window.append(ru " ".repeat(statusLineWidth - 5), color)

proc writeStatusLineBufferManagerModeInfo(bufStatus: var BufferStatus,
                                         statusLine: var StatusLine,
                                         statusLineBuffer: var seq[Rune],
                                         windowNode: WindowNode,
                                         isActiveWindow: bool,
                                         settings: EditorSettings) =

  let
    color = if isActiveWindow: EditorColorPair.statusLineNormalMode
            else: EditorColorPair.statusLineNormalModeInactive
    info = fmt"{windowNode.currentLine + 1}/{bufStatus.buffer.len - 1}"
    statusLineWidth = statusLine.w

  # TODO: Fix
  #statusLine.window.append(ru " ".repeat(statusLineWidth - statusLineBuffer.len),
                                        #color)
  #statusLine.window.write(0, statusLineWidth - info.len - 1, info, color)
  write(0, statusLineWidth - info.len - 1, info)

proc writeStatusLineLogViewerModeInfo(bufStatus: var BufferStatus,
                                  statusLine: var StatusLine,
                                  statusLineBuffer: var seq[Rune],
                                  windowNode: WindowNode,
                                  isActiveWindow: bool,
                                  settings: EditorSettings) =

  let
    color = if isActiveWindow: EditorColorPair.statusLineNormalMode
            else: EditorColorPair.statusLineNormalModeInactive
    info = fmt"{windowNode.currentLine + 1}/{bufStatus.buffer.len - 1}"
    statusLineWidth = statusLine.w

  # TODO: Fix
  #statusLine.window.append(ru " ".repeat(statusLineWidth - statusLineBuffer.len),
                          #color)
  #statusLine.window.write(0, statusLineWidth - info.len - 1, info, color)
  write(0, statusLineWidth - info.len - 1, info)

proc writeStatusLineCurrentGitBranchName(statusLine: var StatusLine,
                                        statusLineBuffer: var seq[Rune],
                                        isActiveWindow: bool) =

  # Get current git branch name
  let cmdResult = execCmdEx("git rev-parse --abbrev-ref HEAD")
  if cmdResult.exitCode != 0: return

  let
    branchName = cmdResult.output
    ## Add symbol and delete newline
    buffer = ru"  " & branchName[0 .. branchName.high - 1].toRunes & ru" "
    color = EditorColorPair.statusLineGitBranch

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

proc setModeStrColor(mode: Mode): EditorColorPair =
  case mode
    of Mode.insert: return EditorColorPair.statusLineModeInsertMode
    of Mode.visual: return EditorColorPair.statusLineModeVisualMode
    of Mode.replace: return EditorColorPair.statusLineModeReplaceMode
    of Mode.filer: return EditorColorPair.statusLineModeFilerMode
    of Mode.ex: return EditorColorPair.statusLineModeExMode
    else: return EditorColorPair.statusLineModeNormalMode

proc isShowGitBranchName(mode, prevMode: Mode,
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

proc writeStatusLine*(bufStatus: var BufferStatus,
                     statusLine: var StatusLine,
                     windowNode: WindowNode,
                     isActiveWindow: bool,
                     settings: EditorSettings) =

  let
    currentMode = bufStatus.mode
    prevMode = bufStatus.prevMode
    color = setModeStrColor(currentMode)
    modeStr = setModeStr(currentMode,
                         isActiveWindow,
                         settings.statusLine.showModeInactive)

  var statusLineBuffer = if windowNode.x > 0: ru" " & modeStr.toRunes
                         else: modeStr.toRunes

  ## Write current mode
  if settings.statusLine.mode:
    # TODO: Enable color
    #statusLine.window.write(0, 0, statusLineBuffer, color)
    write(statusLine.x, statusLine.y, $statusLineBuffer)

  if isShowGitBranchName(currentMode, prevMode, isActiveWindow, settings):
    statusLine.writeStatusLineCurrentGitBranchName(
      statusLineBuffer,
      isActiveWindow)

  if isFilerMode(currentMode, prevMode):
    bufStatus.writeStatusLineFilerModeInfo(
      statusLine,
      statusLineBuffer,
      windowNode,
      isActiveWindow,
      settings)
  elif currentMode == Mode.bufManager:
    bufStatus.writeStatusLineBufferManagerModeInfo(
      statusLine,
      statusLineBuffer,
      windowNode,
      isActiveWindow,
      settings)
  elif currentMode == Mode.logViewer:
    bufStatus.writeStatusLineLogViewerModeInfo(
      statusLine,
      statusLineBuffer,
      windowNode,
      isActiveWindow,
      settings)
  else:
    bufStatus.writeStatusLineNormalModeInfo(
      statusLine,
      statusLineBuffer,
      windowNode,
      isActiveWindow,
      settings)
