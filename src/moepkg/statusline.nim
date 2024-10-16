#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import std/[strutils, strformat, os, options]
import pkg/results
import syntax/highlite
import ui, bufferstatus, color, unicodeext, settings, windownode, gapbuffer,
       git, fileutils

type
  StatusLineColorSegment = object
    first, last: int
    color: EditorColorPairIndex

  StatusLineHighlight = object
    segments: seq[StatusLineColorSegment]

  StatusLine* = object
    window*: Window
    buffer: Runes
    highlight: StatusLineHighlight
    windowIndex*: int
    bufferIndex*: int
    message*: Runes

proc initStatusLine*(): StatusLine {.inline.} =
  const
    Height = 1
    Width = 1
    Y = 1
    X = 1
    Color = EditorColorPairIndex.default
  result.window = initWindow(Height, Width, X, Y, Color.int16)

proc displayPath(bufStatus: BufferStatus): Runes =
  ## Return text of the path for display in the status line.

  if bufStatus.isEditMode or bufStatus.isFilerMode:
    let homeDir = getHomeDir().toRunes

    if bufStatus.path.len == 0:
      result = ru"No name"
    elif bufStatus.path.startsWith(homeDir) and bufStatus.path.len > homeDir.len:
      # Replace a home dir to `~`.
      result = ru"~" /  bufStatus.path[homeDir.len .. ^1]
    else:
      result = bufStatus.path

proc statusLineColor(mode: Mode, isActiveWindow: bool): EditorColorPairIndex =
  case mode:
    of Mode.insert, Mode.insertMulti:
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
    of Mode.filer:
      if isActiveWindow: return EditorColorPairIndex.statusLineFilerMode
      else: return EditorColorPairIndex.statusLineFilerModeInactive
    else:
      if isActiveWindow: return EditorColorPairIndex.statusLineNormalMode
      else: return EditorColorPairIndex.statusLineNormalModeInactive

proc currentLineNumber(node: WindowNode): int {.inline.} =
  node.currentLine + 1

proc totalLines(b: BufferStatus): int {.inline.} = b.buffer.len

proc currentColumnNumber(node: WindowNode): int {.inline.} =
  node.currentColumn + 1

proc totalColumns(b: BufferStatus, node: WindowNode): int {.inline.} =
  b.buffer[node.currentLine].len

proc lineInPercent(b: BufferStatus, node: WindowNode): int {.inline.} =
  int(node.currentLine / b.buffer.len) * 100

proc columnInPercent(b: BufferStatus, node: WindowNode): int {.inline.} =
  if b.buffer[node.currentLine].len > 0:
    return int(node.currentColumn / b.buffer[node.currentLine].len) * 100

proc encoding(b: BufferStatus): CharacterEncoding {.inline.} =
  b.characterEncoding

proc getFileType(b: BufferStatus): Runes =
  if b.isEditMode:
    if b.language == SourceLanguage.langNone:
      return ru"Plain"
    else:
      return sourceLanguageToStr[b.language].toRunes

proc getFileTypeIcon(b: BufferStatus): Runes =
  if b.isEditMode:
    return fileTypeIcon(b.fileType)

proc statusLineWidth(s: StatusLine): int {.inline.} = s.window.width

proc statusLineInfoBuffer(
  b: BufferStatus,
  node: WindowNode,
  setupText: Runes): Runes =
    ## Built and returns a buffer based on the setupText.
    ## Also see settings.StatusLineItem.
    ## Text example: "{lineNumber}/{totalLines} {columnNumber}/{totalColumns} {encoding} {fileType}"

    result = setupText

    # StatusLineItem.lineNumber
    result = result.replace(ru"{lineNumber}", currentLineNumber(node).toRunes)
    # StatusLineItem.lineInPercent
    result = result.replace(ru"{lineInPercent}", lineInPercent(b, node).toRunes)
    # StatusLineItem.totalLines
    result = result.replace(ru"{totalLines}", totalLines(b).toRunes)
    # StatusLineItem.columnNumber
    result = result.replace(
      ru"{columnNumber}",
      currentColumnNumber(node).toRunes)
    # StatusLineItem.columnInPercent
    result = result.replace(
      ru"{columnInPercent}",
      columnInPercent(b, node).toRunes)
    # StatusLineItem.totalColumns
    result = result.replace(ru"{totalColumns}", totalColumns(b, node).toRunes)
    # StatusLineItem.encoding
    result = result.replace(ru"{encoding}", toRunes($encoding(b)))
    # StatusLineItem.fileType
    result = result.replace(ru"{fileType}", getFileType(b))
    # StatusLineItem.fileTypeIcon
    result = result.replace(ru"{fileTypeIcon}", getFileTypeIcon(b))

    if result.len > 0: result.add ru' '

template addMessage(b: var Runes, statusLine: StatusLine) =
  if s.message.len > 0: b.add ru" " & s.message

proc statusLineFilerInfoBuffer(
  b: BufferStatus,
  node: WindowNode): Runes {.inline.} =
    ## Return status buffer for Filer mode.

    result.add fmt"{currentLineNumber(node)}/{totalLines(b)} ".toRunes

proc addFilerModeInfo(
  s: var StatusLine,
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =

    var buffer: Runes

    if settings.statusLine.directory:
      buffer.add ru" " & bufStatus.path

    buffer.addMessage(s)

    let info = statusLineFilerInfoBuffer(bufStatus, windowNode)

    if s.statusLineWidth > s.buffer.len + buffer.len + info.len:
      # Add spaces before info.
      buffer.add ru " ".repeat(
        s.statusLineWidth - s.buffer.len - buffer.len - info.len)

    buffer.add info

    s.highlight.segments.add StatusLineColorSegment(
      first: s.buffer.len,
      last: s.buffer.len + buffer.high,
      color: statusLineColor(bufStatus.mode, isActiveWindow))
    s.buffer.add buffer

proc statusLineBufManagerInfoBuffer(
  b: BufferStatus,
  node: WindowNode): Runes {.inline.} =
    ## Return status buffer for Buffer manager mode.

    result.add fmt"{currentLineNumber(node)}/{totalLines(b)} ".toRunes

proc addBufManagerModeInfo(
  s: var StatusLine,
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =

    var buffer: Runes

    buffer.addMessage(s)

    let info = statusLineBufManagerInfoBuffer(bufStatus, windowNode)

    if s.statusLineWidth > buffer.len + s.buffer.len + info.len:
      # Add spaces before info.
      buffer.add  ' '.repeat(
        s.statusLineWidth - buffer.len - s.buffer.len - info.len).toRunes

    buffer.add info

    s.highlight.segments.add StatusLineColorSegment(
      first: s.buffer.len,
      last: s.buffer.len + buffer.high,
      color: statusLineColor(bufStatus.mode, isActiveWindow))
    s.buffer.add buffer

proc statusLineLogViewerModeInfoBuffer(
  b: BufferStatus,
  node: WindowNode): Runes {.inline.} =
    ## Return status buffer for Log viewer mode.

    result.add fmt"{currentLineNumber(node)}/{totalLines(b)} ".toRunes

proc addLogViewerModeInfo(
  s: var StatusLine,
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =

    var buffer: Runes

    buffer.addMessage(s)

    let info = statusLineLogViewerModeInfoBuffer(bufStatus, windowNode)

    if s.statusLineWidth > buffer.len + s.buffer.len + info.len:
      # Add spaces before info.
      buffer.add  ' '.repeat(
        s.statusLineWidth - buffer.len - s.buffer.len - info.len).toRunes

    buffer.add info

    s.highlight.segments.add StatusLineColorSegment(
      first: s.buffer.len,
      last: s.buffer.len + buffer.high,
      color: statusLineColor(bufStatus.mode, isActiveWindow))
    s.buffer.add buffer

proc statusLineQuickRunModeInfoBuffer(
  b: BufferStatus,
  node: WindowNode): Runes {.inline.} =
    ## Return status buffer for Quickrun mode.

    result.add fmt"{currentLineNumber(node)}/{totalLines(b)} ".toRunes

proc addQuickRunModeInfo(
  s: var StatusLine,
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =

    var buffer: Runes

    buffer.addMessage(s)

    let info = statusLineQuickRunModeInfoBuffer(bufStatus, windowNode)

    if s.statusLineWidth > buffer.len + s.buffer.len + info.len:
      # Add spaces before info.
      buffer.add  ' '.repeat(
        s.statusLineWidth - buffer.len - s.buffer.len - info.len).toRunes

    buffer.add info

    s.highlight.segments.add StatusLineColorSegment(
      first: s.buffer.len,
      last: s.buffer.len + buffer.high,
      color: statusLineColor(bufStatus.mode, isActiveWindow))
    s.buffer.add buffer

proc addNormalModeInfo(
  s: var StatusLine,
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =

    var buffer = ru" "

    if settings.statusLine.filename:
      buffer.add displayPath(bufStatus)

    if bufStatus.countChange > 0 and settings.statusLine.chanedMark:
      const ChangedMark = ru"[+]"
      buffer.add ru" " & ChangedMark

    buffer.addMessage(s)

    let info = statusLineInfoBuffer(
      bufStatus,
      windowNode,
      settings.statusLine.setupText)

    if s.statusLineWidth > buffer.len + s.buffer.len + info.len:
      # Add spaces before info.
      buffer.add  ' '.repeat(
        s.statusLineWidth - buffer.len - s.buffer.len - info.len).toRunes

    buffer.add info

    s.highlight.segments.add StatusLineColorSegment(
      first: s.buffer.len,
      last: s.buffer.len + buffer.high,
      color: statusLineColor(bufStatus.mode, isActiveWindow))
    s.buffer.add buffer

proc isGitBranchName(
  bufStatus: BufferStatus,
  isActiveWindow: bool,
  settings: EditorSettings): bool {.inline.} =

    if settings.statusLine.gitBranchName:
      if settings.statusLine.showGitInactive or
      (not settings.statusLine.showGitInactive and isActiveWindow):
        return bufStatus.isEditMode

proc isGitChangedLine(
  bufStatus: BufferStatus,
  isActiveWindow: bool,
  settings: EditorSettings): bool {.inline.} =

    if settings.statusLine.gitchangedLines:
      if settings.statusLine.showGitInactive or
      (not settings.statusLine.showGitInactive and isActiveWindow):
        return bufStatus.changedLines.len > 0 and bufStatus.isEditMode

proc isGitInfo(
  bufStatus: BufferStatus,
  isActiveWindow: bool,
  settings: EditorSettings): bool {.inline.} =

    isGitBranchName(bufStatus, isActiveWindow, settings) or
    isGitChangedLine(bufStatus, isActiveWindow, settings)

proc gitBranchNameBuffer(
  branchName: Runes,
  withGitChangedLine: bool): Runes =
    ## Return a buffer for the git branch name.

    const GitBranchSymbol = ""
    if withGitChangedLine:
      return fmt"{GitBranchSymbol} {branchName} ".toRunes
    else:
      # Add the single space if no changedLines.
      return fmt" {GitBranchSymbol} {branchName} ".toRunes

proc changedLinesBuffer(
  changedLines: seq[Diff],
  withGitBranch: bool): Runes =
    ## Return a buffer for the number of lines changed using git.

    let (added, changed, deleted) = changedLines.countChangedLines
    if withGitBranch:
      return fmt" +{added} ~{changed} -{deleted}".toRunes
    else:
      return fmt" +{added} ~{changed} -{deleted} ".toRunes

proc addGitInfo(
  s: var StatusLine,
  bufStatus: BufferStatus,
  isActiveWindow: bool,
  settings: EditorSettings) =
    ## Add git info to the status line. (changed lines, branch name, etc)

    var branchName: Option[Runes]
    if isGitBranchName(bufStatus, isActiveWindow, settings):
      let name = getCurrentGitBranchName()
      if name.isOk: branchName = some(name.get)

    var changedLinesBuffer: Runes
    if isGitChangedLine(bufStatus, isActiveWindow, settings):
      let changedLinesBuffer = changedLinesBuffer(
        bufStatus.changedLines,
        branchName.isSome)

      if changedLinesBuffer.len > 0:
        s.highlight.segments.add StatusLineColorSegment(
          first: s.buffer.len,
          last: s.buffer.len + changedLinesBuffer.high,
          color: EditorColorPairIndex.statusLineGitChangedLines)
        s.buffer.add changedLinesBuffer

    if branchName.isSome:
      let
        withChangedLine = changedLinesBuffer.len > 0
        branchNameBuffer = gitBranchNameBuffer(
          branchName.get,
          withChangedLine)

      s.highlight.segments.add StatusLineColorSegment(
        first: s.buffer.len,
        last: s.buffer.len + branchNameBuffer.high,
        color: EditorColorPairIndex.statusLineGitBranch)
      s.buffer.add branchNameBuffer

proc modeLabel(mode: Mode): string =
  case mode:
    of Mode.insert:
      "INSERT"
    of Mode.insertMulti:
      "INSERT MULTI"
    of Mode.visual:
      "VISUAL"
    of Mode.visualBlock:
      "VISUAL BLOCK"
    of Mode.visualLine:
      "VISUAL LINE"
    of Mode.replace:
      "REPLACE"
    of Mode.filer:
      "FILER"
    of Mode.bufManager:
      "BUFFER"
    of Mode.ex:
      "EX"
    of Mode.logViewer:
      "LOG"
    of Mode.recentFile:
      "RECENT"
    of Mode.quickRun:
      "QUICKRUN"
    of Mode.backup:
      "BACKUP"
    of Mode.diff:
      "DIFF"
    of Mode.config:
      "CONFIG"
    of Mode.debug:
      "DEBUG"
    of Mode.references:
      "REFERENCES"
    of Mode.callhierarchyViewer:
      "CALL HIERARCHY"
    else:
      "NORMAL"

proc modeLabelColor(mode: Mode): EditorColorPairIndex =
  case mode
    of Mode.insert, Mode.insertMulti:
      EditorColorPairIndex.statusLineInsertModeLabel
    of Mode.visual, Mode.visualBlock, Mode.visualLine:
      EditorColorPairIndex.statusLineVisualModeLabel
    of Mode.replace:
      EditorColorPairIndex.statusLineReplaceModeLabel
    of Mode.filer:
      EditorColorPairIndex.statusLineFilerModeLabel
    of Mode.ex:
      EditorColorPairIndex.statusLineExModeLabel
    else:
      EditorColorPairIndex.statusLineNormalModeLabel

proc addModeLabel(
  s: var StatusLine,
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: StatusLineSettings) =
    ## Add the mode label to the status line buffer.

    let
      modeLabel =
        if not isActiveWindow and not settings.showModeInactive:
          none(string)
        else:
          some(modeLabel(bufStatus.mode))

    if modeLabel.isSome:
      let
        buffer =
          if windowNode.x > 0: fmt"  {modeLabel.get} ".toRunes
          else: fmt" {modeLabel.get} ".toRunes

      s.highlight.segments.add StatusLineColorSegment(
        first: 0,
        last: buffer.high,
        color: modeLabelColor(bufStatus.mode))
      s.buffer.add buffer

proc clear(s: var StatusLine) =
  ## Clear status line buffer and highlight.

  s.buffer = @[]
  s.highlight.segments = @[]

proc updateStatusLineBuffer(
  s: var StatusLine,
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =
    ## Update buffer and highlight for the status line.

    s.clear

    if settings.statusLine.mode:
      s.addModeLabel(
        bufStatus,
        windowNode,
        isActiveWindow,
        settings.statusLine)

    if isGitInfo(bufStatus, isActiveWindow, settings):
      s.addGitinfo(bufStatus, isActiveWindow, settings)

    if bufStatus.isFilerMode:
      s.addFilerModeInfo(bufStatus, windowNode, isActiveWindow, settings)
    elif bufStatus.isBufferManagerMode:
      s.addBufManagerModeInfo(bufStatus, windowNode, isActiveWindow, settings)
    elif bufStatus.isLogViewerMode:
      s.addLogViewerModeInfo(bufStatus, windowNode, isActiveWindow, settings)
    elif bufStatus.isQuickRunMode:
      s.addQuickRunModeInfo(bufStatus, windowNode, isActiveWindow, settings)
    else:
      s.addNormalModeInfo(bufStatus, windowNode, isActiveWindow, settings)

proc write(s: var StatusLine) =
  ## Write buffer to the terminal.

  const Y = 0
  for cs in s.highlight.segments:
    let
      x = cs.first
      buffer = s.buffer[cs.first .. cs.last]
    s.window.write(Y, x, buffer, cs.color.int16)

proc updateStatusLine*(
  s: var StatusLine,
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  isActiveWindow: bool,
  settings: EditorSettings) =

    s.updateStatusLineBuffer(bufStatus, windowNode, isActiveWindow, settings)

    s.window.erase
    s.write
    s.window.refresh

proc updateMessage*(s: var StatusLine, message: Runes) {.inline.} =
  s.message = message
