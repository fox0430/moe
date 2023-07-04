#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[strutils, strformat, os, osproc]
import syntax/highlite
import ui, bufferstatus, color, unicodeext, settings, windownode, gapbuffer

type StatusLine* = object
  window*: Window
  windowIndex*: int
  bufferIndex*: int

proc initStatusLine*(): StatusLine {.inline.} =
  const
    h = 1
    w = 1
    t = 1
    l = 1
    color = EditorColorPairIndex.default

  result.window = initWindow(h, w, t, l, color.int16)

proc showFilename(mode, prevMode: Mode): bool {.inline.} =
  not isBackupManagerMode(mode, prevMode) and
  not isConfigMode(mode, prevMode)

proc appendFileName(
  statusLineBuffer: var seq[Rune],
  bufStatus: BufferStatus,
  statusLineWindow: var Window,
  color: EditorColorPairIndex) =

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
    statusLineWindow.append(filename, color.int16)

proc statusLineColor(mode: Mode, isActiveWindow: bool): EditorColorPairIndex =
  case mode:
    of Mode.insert:
      if isActiveWindow: return EditorColorPairIndex.statusLineInsertMode
      else: return EditorColorPairIndex.statusLineInsertModeInactive
    of Mode.visual, Mode.visualBlock, Mode.visualLine:
      if isActiveWindow: return EditorColorPairIndex.statusLineVisualMode
      else: return EditorColorPairIndex.statusLineVisualModeInactive
    of Mode.replace:
      if isActiveWindow: return EditorColorPairIndex.statusLineReplaceMode
      else: return EditorColorPairIndex.statusLineReplaceModeInactive
    of Mode.ex:
      if isActiveWindow: return EditorColorPairIndex.statusLineExMode
      else: return EditorColorPairIndex.statusLineExModeInactive
    else:
      if isActiveWindow: return EditorColorPairIndex.statusLineNormalMode
      else: return EditorColorPairIndex.statusLineNormalModeInactive

proc writeStatusLineNormalModeInfo(
  statusLine: var StatusLine,
  statusLineBuffer: var seq[Rune],
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =

    let
      color = bufStatus.mode.statusLineColor(isActiveWindow)
      statusLineWidth = statusLine.window.width

    statusLineBuffer.add(ru" ")
    statusLine.window.append(ru" ", color.int16)

    if settings.statusLine.filename:
      statusLineBuffer.appendFileName(bufStatus, statusLine.window, color)

    if bufStatus.countChange > 0 and settings.statusLine.chanedMark:
      statusLineBuffer.add(ru" [+]")
      statusLine.window.append(ru" [+]", color.int16)

    if statusLineWidth - statusLineBuffer.len < 0: return
    statusLine.window.append(ru " ".repeat(statusLineWidth - statusLineBuffer.len), color.int16)

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
    statusLine.window.write(0, statusLineWidth - info.len, info, color.int16)

proc writeStatusLineFilerModeInfo(
  statusLine: var StatusLine,
  statusLineBuffer: var seq[Rune],
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =

    let
      color = if isActiveWindow: EditorColorPairIndex.statusLineFilerMode
              else: EditorColorPairIndex.statusLineFilerModeInactive
      statusLineWidth = statusLine.window.width

    if settings.statusLine.directory:
      statusLine.window.append(ru" ", color.int16)
      statusLine.window.append(bufStatus.path, color.int16)

    statusLine.window.append(ru " ".repeat(statusLineWidth - 5), color.int16)

proc writeStatusLineBufferManagerModeInfo(
  statusLine: var StatusLine,
  statusLineBuffer: var seq[Rune],
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =

    let
      color = if isActiveWindow: EditorColorPairIndex.statusLineNormalMode
              else: EditorColorPairIndex.statusLineNormalModeInactive
      info = fmt"{windowNode.currentLine + 1}/{bufStatus.buffer.len - 1}"
      statusLineWidth = statusLine.window.width

    statusLine.window.append(
      ru " ".repeat(statusLineWidth - statusLineBuffer.len),
      color.int16)
    statusLine.window.write(0, statusLineWidth - info.len - 1, info, color.int16)

proc writeStatusLineLogViewerModeInfo(
  statusLine: var StatusLine,
  statusLineBuffer: var seq[Rune],
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =

    let
      color = if isActiveWindow: EditorColorPairIndex.statusLineNormalMode
              else: EditorColorPairIndex.statusLineNormalModeInactive
      info = fmt"{windowNode.currentLine + 1}/{bufStatus.buffer.len - 1}"
      statusLineWidth = statusLine.window.width

    statusLine.window.append(
      ru " ".repeat(statusLineWidth - statusLineBuffer.len),
      color.int16)
    statusLine.window.write(0, statusLineWidth - info.len - 1, info, color.int16)

proc writeStatusLineCurrentGitBranchName(
  statusLine: var StatusLine,
  statusLineBuffer: var seq[Rune],
  isActiveWindow: bool) =

    # Get current git branch name
    let cmdResult = execCmdEx("git rev-parse --abbrev-ref HEAD")
    if cmdResult.exitCode != 0: return

    let
      branchName = cmdResult.output
      ## Add symbol and delete newline
      buffer = ru"  " & branchName[0 .. branchName.high - 1].toRunes & ru" "
      color = EditorColorPairIndex.statusLineGitBranch

    statusLineBuffer.add(buffer)
    statusLine.window.append(buffer, color.int16)

proc modeLablel(mode: Mode, isActiveWindow, showModeInactive: bool): string =
  if not isActiveWindow and not showModeInactive:
    result = ""
  else:
    case mode:
      of Mode.insert:
        result = "INSERT"
      of Mode.visual:
        result = "VISUAL"
      of Mode.visualBlock:
        result = "VISUAL BLOCK"
      of Mode.visualLine:
        result = "VISUAL LINE"
      of Mode.replace:
        result = "REPLACE"
      of Mode.filer:
        result = "FILER"
      of Mode.bufManager:
        result = "BUFFER"
      of Mode.ex:
        result = "EX"
      of Mode.logViewer:
        result = "LOG"
      of Mode.recentFile:
        result = "RECENT"
      of Mode.quickRun:
        result = "QUICKRUN"
      of Mode.backup:
        result = "BACKUP"
      of Mode.diff:
        result = "DIFF"
      of Mode.config:
        result = "CONFIG"
      of Mode.debug:
        result = "DEBUG"
      else:
        result = "NORMAL"

proc setModeStrColor(mode: Mode): EditorColorPairIndex =
  case mode
    of Mode.insert: EditorColorPairIndex.statusLineModeInsertMode
    of Mode.visual: EditorColorPairIndex.statusLineModeVisualMode
    of Mode.replace: EditorColorPairIndex.statusLineModeReplaceMode
    of Mode.filer: EditorColorPairIndex.statusLineModeFilerMode
    of Mode.ex: EditorColorPairIndex.statusLineModeExMode
    else: EditorColorPairIndex.statusLineModeNormalMode

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
  statusLine: var StatusLine,
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =

    statusLine.window.erase

    let
      currentMode = bufStatus.mode
      prevMode = bufStatus.prevMode
      color = setModeStrColor(currentMode)
      modeLabel = currentMode.modeLablel(
        isActiveWindow,
        settings.statusLine.showModeInactive)

    var statusLineBuffer =
      if windowNode.x > 0: fmt"  {modeLabel} ".toRunes
      else: fmt" {modeLabel} ".toRunes

    ## Write current mode
    if settings.statusLine.mode:
      statusLine.window.write(0, 0, statusLineBuffer, color.int16)

    if isShowGitBranchName(currentMode, prevMode, isActiveWindow, settings):
      statusLine.writeStatusLineCurrentGitBranchName(
        statusLineBuffer,
        isActiveWindow)

    if isFilerMode(currentMode, prevMode):
      statusLine.writeStatusLineFilerModeInfo(
        statusLineBuffer,
        bufStatus,
        windowNode,
        isActiveWindow,
        settings)
    elif currentMode == Mode.bufManager:
      statusLine.writeStatusLineBufferManagerModeInfo(
        statusLineBuffer,
        bufStatus,
        windowNode,
        isActiveWindow,
        settings)
    elif currentMode == Mode.logViewer:
      statusLine.writeStatusLineLogViewerModeInfo(
        statusLineBuffer,
        bufStatus,
        windowNode,
        isActiveWindow,
        settings)
    else:
      statusLine.writeStatusLineNormalModeInfo(
        statusLineBuffer,
        bufStatus,
        windowNode,
        isActiveWindow,
        settings)

    statusLine.window.refresh
