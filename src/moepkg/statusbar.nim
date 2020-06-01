import ui, strutils, strformat, packages/docutils/highlite, os
import bufferstatus, color, unicodeext, settings, window, gapbuffer

type StatusBar* = object
  window*: Window
  windowIndex*: int
  bufferIndex*: int

proc writeStatusBarNormalModeInfo(bufStatus: var BufferStatus,
                                  statusBar: var StatusBar,
                                  windowNode: WindowNode,
                                  settings: EditorSettings) =
  let
    color = EditorColorPair.statusBarNormalMode
    currentMode = bufStatus.mode
    statusBarWidth = statusBar.window.width

  statusBar.window.append(ru" ", color)

  if settings.statusBar.filename:
    var filename = if bufStatus.filename.len > 0: bufStatus.filename
                   else: ru"No name"
    let homeDir = ru(getHomeDir())
    if (filename.len() >= homeDir.len() and
        filename[0..homeDir.len()-1] == homeDir):
      filename = filename[homeDir.len()-1..filename.len()-1]
      if filename[0] == ru'/':
        filename = ru"~" & filename
      else:
        filename = ru"~/" & filename
    statusBar.window.append(filename, color)

  if bufStatus.countChange > 0 and settings.statusBar.chanedMark:
    statusBar.window.append(ru" [+]", color)

  var modeNameLen = 0
  if bufStatus.mode == Mode.ex: modeNameLen = 2
  elif currentMode == Mode.normal or
       currentMode == Mode.insert or
       currentMode == Mode.visual or
       currentMode == Mode.visualBlock or
       currentMode == Mode.replace: modeNameLen = 6
  if statusBarWidth - modeNameLen < 0: return
  statusBar.window.append(ru " ".repeat(statusBarWidth - modeNameLen), color)

  let
    line = if settings.statusBar.line:
             fmt"{windowNode.currentLine + 1}/{bufStatus.buffer.len}"
           else: ""
    column = if settings.statusBar.column:
               fmt"{windowNode.currentColumn + 1}/{bufStatus.buffer[windowNode.currentLine].len}"
             else: ""
    encoding = if settings.statusBar.characterEncoding: $settings.characterEncoding
               else: ""
    language = if bufStatus.language == SourceLanguage.langNone: "Plain"
               else: sourceLanguageToStr[bufStatus.language]
    info = fmt"{line} {column} {encoding} {language} "
  statusBar.window.write(0, statusBarWidth - info.len, info, color)

proc writeStatusBarFilerModeInfo(bufStatus: var BufferStatus,
                                 statusBar: var StatusBar,
                                 windowNode: WindowNode,
                                 settings: EditorSettings) =
  let
    color = EditorColorPair.statusBarFilerMode
    statusBarWidth = statusBar.window.width

  if settings.statusBar.directory: statusBar.window.append(ru" ", color)
  statusBar.window.append(getCurrentDir().toRunes, color)
  statusBar.window.append(ru " ".repeat(statusBarWidth - 5), color)

proc writeStatusBarBufferManagerModeInfo(bufStatus: var BufferStatus,
                                         statusBar: var StatusBar,
                                         windowNode: WindowNode,
                                         settings: EditorSettings) =
  let
    color = EditorColorPair.statusBarNormalMode
    info = fmt"{windowNode.currentLine + 1}/{bufStatus.buffer.len - 1}"
    statusBarWidth = statusBar.window.width

  statusBar.window.append(ru " ".repeat(statusBarWidth - " BUFFER ".len), color)
  statusBar.window.write(0, statusBarWidth - info.len - 1, info, color)

proc writeStatusLogViewerModeInfo(bufStatus: var BufferStatus,
                                  statusBar: var StatusBar,
                                  windowNode: WindowNode,
                                  settings: EditorSettings) =
  let
    color = EditorColorPair.statusBarNormalMode
    info = fmt"{windowNode.currentLine + 1}/{bufStatus.buffer.len - 1}"
    statusBarWidth = statusBar.window.width

  statusBar.window.append(ru " ".repeat(statusBarWidth - " LOG ".len), color)
  statusBar.window.write(0, statusBarWidth - info.len - 1, info, color)

proc setModeStr(mode: Mode): string =
  case mode:
  of Mode.insert: result = " INSERT "
  of Mode.visual, Mode.visualBlock: result = " VISUAL "
  of Mode.replace: result = " REPLACE "
  of Mode.filer: result = " FILER "
  of Mode.bufManager: result = " BUFFER "
  of Mode.ex: result = " EX "
  of Mode.logViewer: result = " LOG "
  else: result = " NORMAL "

proc setModeStrColor(mode: Mode): EditorColorPair =
  case mode
    of Mode.insert: return EditorColorPair.statusBarModeInsertMode
    of Mode.visual: return EditorColorPair.statusBarModeVisualMode
    of Mode.replace: return EditorColorPair.statusBarModeReplaceMode
    of Mode.filer: return EditorColorPair.statusBarModeFilerMode
    of Mode.ex: return EditorColorPair.statusBarModeExMode
    else: return EditorColorPair.statusBarModeNormalMode

proc writeStatusBar*(bufStatus: var BufferStatus,
                     statusBar: var StatusBar,
                     windowNode: WindowNode,
                     settings: EditorSettings) =
  statusBar.window.erase

  let
    currentMode = bufStatus.mode
    prevMode = bufStatus.prevMode
    color = setModeStrColor(currentMode)
    modeStr = setModeStr(currentMode)

  ## Write current mode
  if settings.statusBar.mode: statusBar.window.write(0, 0, modeStr, color)

  if currentMode == Mode.ex and prevMode == Mode.filer:
    bufStatus.writeStatusBarFilerModeInfo(statusBar, windowNode, settings)
  elif currentMode == Mode.ex:
    bufStatus.writeStatusBarNormalModeInfo(statusBar, windowNode, settings)
  elif currentMode == Mode.visual or currentMode == Mode.visualBlock:
    bufStatus.writeStatusBarNormalModeInfo(statusBar, windowNode, settings)
  elif currentMode == Mode.replace:
    bufStatus.writeStatusBarNormalModeInfo(statusBar, windowNode, settings)
  elif currentMode == Mode.filer:
    bufStatus.writeStatusBarFilerModeInfo(statusBar, windowNode, settings)
  elif currentMode == Mode.bufManager:
    bufStatus.writeStatusBarBufferManagerModeInfo(statusBar, windowNode, settings)
  elif currentMode == Mode.logViewer:
    bufStatus.writeStatusLogViewerModeInfo(statusBar, windowNode, settings)
  else: bufStatus.writeStatusBarNormalModeInfo(statusBar, windowNode, settings)

  statusBar.window.refresh
