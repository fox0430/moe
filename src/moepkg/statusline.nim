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
import ui, bufferstatus, color, unicodeext, settings, windownode, gapbuffer, git

type StatusLine* = object
  window*: Window
  windowIndex*: int
  bufferIndex*: int

proc initStatusLine*(): StatusLine {.inline.} =
  const
    H = 1
    W = 1
    T = 1
    L = 1
    Color = EditorColorPairIndex.default

  result.window = initWindow(H, W, T, L, Color.int16)

proc showFilename(mode, prevMode: Mode): bool {.inline.} =
  not isBackupManagerMode(mode, prevMode) and
  not isConfigMode(mode, prevMode)

proc appendFileName(
  statusLineBuffer: var Runes,
  bufStatus: BufferStatus,
  statusLineWindow: var Window,
  color: EditorColorPairIndex) =

    let
      mode = bufStatus.mode
      prevMode = bufStatus.prevMode
    var filename =
      if not showFilename(mode, prevMode): ru""
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
  statusLineBuffer: var Runes,
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
      line =
        if settings.statusLine.line:
          fmt"{windowNode.currentLine + 1}/{bufStatus.buffer.len}"
        else:
        ""
      column =
        if settings.statusLine.column:
          fmt"{windowNode.currentColumn + 1}/{bufStatus.buffer[windowNode.currentLine].len}"
        else:
        ""
      encoding =
        if settings.statusLine.characterEncoding: $bufStatus.characterEncoding
        else:
        ""
      language =
        if bufStatus.language == SourceLanguage.langNone: "Plain"
         else: sourceLanguageToStr[bufStatus.language]
      info = fmt"{line} {column} {encoding} {language} "

    statusLine.window.write(0, statusLineWidth - info.len, info, color.int16)

proc writeStatusLineFilerModeInfo(
  statusLine: var StatusLine,
  statusLineBuffer: var Runes,
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =

    let
      color =
        if isActiveWindow: EditorColorPairIndex.statusLineFilerMode
        else: EditorColorPairIndex.statusLineFilerModeInactive
      statusLineWidth = statusLine.window.width

    if settings.statusLine.directory:
      statusLine.window.append(ru" ", color.int16)
      statusLine.window.append(bufStatus.path, color.int16)

    statusLine.window.append(ru " ".repeat(statusLineWidth - 5), color.int16)

proc writeStatusLineBufferManagerModeInfo(
  statusLine: var StatusLine,
  statusLineBuffer: var Runes,
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =

    let
      color =
        if isActiveWindow: EditorColorPairIndex.statusLineNormalMode
        else: EditorColorPairIndex.statusLineNormalModeInactive
      info = fmt"{windowNode.currentLine + 1}/{bufStatus.buffer.len - 1}"
      statusLineWidth = statusLine.window.width

    statusLine.window.append(
      ru " ".repeat(statusLineWidth - statusLineBuffer.len),
      color.int16)
    statusLine.window.write(0, statusLineWidth - info.len - 1, info, color.int16)

proc writeStatusLineLogViewerModeInfo(
  statusLine: var StatusLine,
  statusLineBuffer: var Runes,
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =

    let
      color =
        if isActiveWindow: EditorColorPairIndex.statusLineNormalMode
        else: EditorColorPairIndex.statusLineNormalModeInactive
      info = fmt"{windowNode.currentLine + 1}/{bufStatus.buffer.len - 1}"
      statusLineWidth = statusLine.window.width

    statusLine.window.append(
      ru " ".repeat(statusLineWidth - statusLineBuffer.len),
      color.int16)
    statusLine.window.write(0, statusLineWidth - info.len - 1, info, color.int16)

proc writeStatusLineQuickRunModeInfo(
  statusLine: var StatusLine,
  statusLineBuffer: var Runes,
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =

    let
      color =
        if isActiveWindow: EditorColorPairIndex.statusLineNormalMode
        else: EditorColorPairIndex.statusLineNormalModeInactive
      info = fmt"{windowNode.currentLine + 1}/{bufStatus.buffer.len - 1}"
      statusLineWidth = statusLine.window.width

    statusLine.window.append(
      ru " ".repeat(statusLineWidth - statusLineBuffer.len),
      color.int16)
    statusLine.window.write(0, statusLineWidth - info.len - 1, info, color.int16)

proc isGitBranchName(
  bufStatus: BufferStatus,
  isActiveWindow: bool,
  settings: EditorSettings): bool =

    if settings.statusLine.gitBranchName:
      if settings.statusLine.showGitInactive or
      (not settings.statusLine.showGitInactive and isActiveWindow):
        return bufStatus.isEditMode

proc isGitChangedLine(
  bufStatus: BufferStatus,
  isActiveWindow: bool,
  settings: EditorSettings): bool =

    if settings.statusLine.gitchangedLines:
      if settings.statusLine.showGitInactive or
      (not settings.statusLine.showGitInactive and isActiveWindow):
        return bufStatus.isEditMode

proc gitBranchNameBuffer(
  statusLine: var StatusLine,
  statusLineBuffer: var Runes): Runes =
    ## Return a buffer for the git branch name.

    const GitBranchSymbol = ""

    # Get current git branch name
    let cmdResult = execCmdEx("git rev-parse --abbrev-ref HEAD")
    if cmdResult.exitCode != 0: return

    let
      branchName = (cmdResult.output)[0 .. cmdResult.output.high - 1]
      buffer = fmt"{GitBranchSymbol} {branchName} ".toRunes

    return buffer

proc changedLinesBuffer(
  statusLine: var StatusLine,
  statusLineBuffer: var Runes,
  changedLines: seq[Diff],
  isActiveWindow: bool): Runes =
    ## Return a buffer for the number of lines changed using git.

    if isActiveWindow and changedLines.len > 0:
      let (added, changed, deleted) = changedLines.countChangedLines
      return fmt" +{added} ~{changed} -{deleted}".toRunes

proc writeGitInfo(
  statusLine: var StatusLine,
  statusLineBuffer: var Runes,
  bufStatus: BufferStatus,
  settings: EditorSettings,
  isActiveWindow: bool) =
    ## Write git info to the status line. (changed lines, branch name, etc)

    var changedLinesBuffer: Runes
    if isGitChangedLine(bufStatus, isActiveWindow, settings):
      let changedLinesBuffer = statusLine.changedLinesBuffer(
        statusLineBuffer,
        bufStatus.changedLines,
        isActiveWindow)

      if changedLinesBuffer.len > 0:
        statusLineBuffer.add changedLinesBuffer
        statusLine.window.append(
          changedLinesBuffer,
          EditorColorPairIndex.statusLineGitBranch.int16)

    if isGitBranchName(bufStatus, isActiveWindow, settings):
      let branchNameBuffer = statusLine.gitBranchNameBuffer(statusLineBuffer)

      if branchNameBuffer.len > 0 and changedLinesBuffer.len == 0:
        # Add the single space if no changedLines.
        statusLineBuffer.add ru" "
        statusLine.window.append(
          ru" ",
          EditorColorPairIndex.statusLineGitBranch.int16)

        statusLineBuffer.add branchNameBuffer
        statusLine.window.append(
          branchNameBuffer,
          EditorColorPairIndex.statusLineGitBranch.int16)

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

proc modeStrColor(mode: Mode): EditorColorPairIndex =
  case mode
    of Mode.insert: EditorColorPairIndex.statusLineModeInsertMode
    of Mode.visual: EditorColorPairIndex.statusLineModeVisualMode
    of Mode.replace: EditorColorPairIndex.statusLineModeReplaceMode
    of Mode.filer: EditorColorPairIndex.statusLineModeFilerMode
    of Mode.ex: EditorColorPairIndex.statusLineModeExMode
    else: EditorColorPairIndex.statusLineModeNormalMode

proc writeStatusLine*(
  statusLine: var StatusLine,
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =

    statusLine.window.erase

    let
      modeLabel = bufStatus.mode.modeLablel(
        isActiveWindow,
        settings.statusLine.showModeInactive)

    var statusLineBuffer =
      if windowNode.x > 0: fmt"  {modeLabel} ".toRunes
      else: fmt" {modeLabel} ".toRunes

    ## Write current mode
    if settings.statusLine.mode:
      statusLine.window.write(0, 0, statusLineBuffer, modeStrColor(bufStatus.mode).int16)

    statusLine.writeGitinfo(
      statusLineBuffer,
      bufStatus,
      settings,
      isActiveWindow)

    if bufStatus.isFilerMode:
      statusLine.writeStatusLineFilerModeInfo(
        statusLineBuffer,
        bufStatus,
        windowNode,
        isActiveWindow,
        settings)
    elif bufStatus.isBufferManagerMode:
      statusLine.writeStatusLineBufferManagerModeInfo(
        statusLineBuffer,
        bufStatus,
        windowNode,
        isActiveWindow,
        settings)
    elif bufStatus.isLogViewerMode:
      statusLine.writeStatusLineLogViewerModeInfo(
        statusLineBuffer,
        bufStatus,
        windowNode,
        isActiveWindow,
        settings)
    elif bufStatus.isQuickRunMode:
      statusLine.writeStatusLineQuickRunModeInfo(
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
