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

import std/[tables, times, options, os]
import pkg/results
import syntax/highlite
import gapbuffer, unicodeext, fileutils, highlight, independentutils, git,
       syntaxcheck

type
  Mode* = enum
    normal
    insert
    visual
    visualBlock
    visualLine
    replace
    ex
    filer
    bufManager
    logViewer
    help
    recentFile
    quickRun
    backup
    diff
    config
    debug
    searchForward
    searchBackward

  BufferStatus* = object
    buffer*: GapBuffer[Runes]
    isUpdate*: bool
    characterEncoding*: CharacterEncoding
    language*: SourceLanguage
    selectedArea*: SelectedArea
    path*: Runes
    openDir*: Runes
    positionRecord*: Table[int, tuple[line, column, expandedColumn: int]]
    countChange*: int
    cmdLoop*: int
    mode* : Mode
    prevMode* : Mode
    lastSaveTime*: DateTime
    isReadonly*: bool
    filerStatusIndex*: Option[int]
    isTrackingByGit*: bool
    lastGitInfoCheckTime*: DateTime
    isGitUpdate*: bool
    changedLines*: seq[Diff]
    syntaxCheckResults*: seq[SyntaxError]

proc isExMode*(mode: Mode): bool {.inline.} = mode == Mode.ex

proc isExMode*(b: BufferStatus): bool {.inline.} = b.mode == Mode.ex

proc isFilerMode*(mode: Mode): bool = mode == Mode.filer

proc isFilerMode*(b: BufferStatus): bool {.inline.} =
  b.mode == Mode.filer or
  (b.isExMode and b.prevMode == Mode.filer)

proc isFilerMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.filer) or (mode == Mode.ex and prevMode == Mode.filer)

proc isBackupManagerMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.backup) or (mode == Mode.ex and prevMode == Mode.backup)

proc isBackupManagerMode*(bufStatus: BufferStatus): bool {.inline.} =
  (bufStatus.mode == Mode.backup) or
  (bufStatus.mode == Mode.ex and bufStatus.prevMode == Mode.backup)

proc isDiffViewerMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.diff) or (mode == Mode.ex and prevMode == Mode.diff)

proc isDiffViewerMode*(bufStatus: BufferStatus): bool {.inline.} =
  (bufStatus.mode == Mode.diff) or
  (bufStatus.mode == Mode.ex and bufStatus.prevMode == Mode.diff)

proc isConfigMode*(mode: Mode): bool {.inline.} = mode == Mode.config

proc isConfigMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.config) or (mode == Mode.ex and prevMode == Mode.config)

proc isConfigMode*(b: BufferStatus): bool {.inline.} =
  (b.mode == Mode.config) or
  (b.isExMode and b.prevMode == Mode.config)

proc isSearchForwardMode*(mode: Mode): bool {.inline.} =
  mode == Mode.searchForward

proc isSearchForwardMode*(b: BufferStatus): bool {.inline.} =
  b.mode == Mode.searchForward

proc isSearchBackwardMode*(mode: Mode): bool {.inline.} =
  mode == Mode.searchBackward

proc isSearchBackwardMode*(b: BufferStatus): bool {.inline.} =
  b.mode == Mode.searchBackward

proc isSearchMode*(mode: Mode): bool {.inline.} =
  isSearchForwardMode(mode) or isSearchBackwardMode(mode)

proc isSearchMode*(b: BufferStatus): bool {.inline.} =
  b.isSearchForwardMode or b.isSearchBackwardMode

proc isNormalMode*(mode: Mode): bool {.inline.} = mode == Mode.normal

proc isNormalMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.normal) or
  (mode.isExMode and prevMode == Mode.normal) or
  (mode.isSearchMode and prevMode == Mode.normal)

proc isNormalMode*(b: BufferStatus): bool {.inline.} =
  (b.mode == Mode.normal) or
  (b.isExMode and b.prevMode == Mode.normal) or
  (b.isSearchMode and b.prevMode == Mode.normal)

proc isInsertMode*(mode: Mode): bool {.inline.} = mode == Mode.insert

proc isInsertMode*(b: BufferStatus): bool {.inline.} = b.mode == Mode.insert

proc isReplaceMode*(mode: Mode): bool {.inline.} = mode == Mode.replace

proc isReplaceMode*(b: BufferStatus): bool {.inline.} = b.mode == Mode.replace

proc isDebugMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.debug) or
  (mode == Mode.ex and prevMode == Mode.debug)

proc isDebugMode*(b: BufferStatus): bool {.inline.} =
  (b.mode == Mode.debug) or (b.isExMode and b.prevMode == Mode.debug)

proc isQuickRunMode*(mode: Mode): bool = mode == Mode.quickRun

proc isQuickRunMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.quickRun) or
  (mode == Mode.ex and prevMode == Mode.quickRun)

proc isQuickRunMode*(b: BufferStatus): bool {.inline.} =
  isQuickRunMode(b.mode, b.prevMode)

proc isLogViewerMode*(mode: Mode): bool {.inline.} = mode == Mode.logViewer

proc isLogViewerMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.logViewer) or
  (mode == Mode.ex and prevMode == Mode.logViewer)

proc isLogViewerMode*(b: BufferStatus): bool {.inline.} =
  isLogViewerMode(b.mode, b.prevMode)

proc isBufferManagerMode*(mode: Mode): bool {.inline.} = mode == Mode.bufManager

proc isBufferManagerMode*(b: BufferStatus): bool {.inline.} =
  b.mode == Mode.bufManager

proc isVisualMode*(mode: Mode): bool {.inline.} =
  mode == Mode.visual or mode == Mode.visualBlock or mode == Mode.visualLine

proc isVisualMode*(b: BufferStatus): bool {.inline.} =
  b.mode == Mode.visual or b.mode == Mode.visualBlock  or b.mode == Mode.visualLine

proc isVisualBlockMode*(mode: Mode): bool {.inline.} =
  mode == Mode.visualBlock

proc isVisualBlockMode*(b: BufferStatus): bool {.inline.} =
  b.mode == Mode.visualBlock

proc isVisualLineMode*(mode: Mode): bool {.inline.} = mode == Mode.visualLine

proc isVisualLineMode*(b: BufferStatus): bool {.inline.} =
  b.mode == Mode.visualLine

proc isHelpMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.help) or
  (mode == Mode.ex and prevMode == Mode.help)

proc isHelpMode*(b: BufferStatus): bool {.inline.} =
  isHelpMode(b.mode, b.prevMode)

proc isRecentFileMode*(mode, prevMode: Mode): bool {.inline.} =
  (mode == Mode.recentFile) or
  (mode == Mode.ex and prevMode == Mode.recentFile)

proc isRecentFileMode*(b: BufferStatus): bool {.inline.} =
  isRecentFileMode(b.mode, b.prevMode)

proc isEditMode*(mode, prevMode: Mode): bool {.inline.} =
  ## Modes for editing text

  isNormalMode(mode, prevMode) or
  isInsertMode(mode) or
  isVisualMode(mode) or
  isReplaceMode(mode)

proc isEditMode*(mode: Mode): bool {.inline.} =
  isNormalMode(mode) or
  isInsertMode(mode) or
  isVisualMode(mode) or
  isReplaceMode(mode)

proc isEditMode*(b: BufferStatus): bool {.inline.} =
  b.isNormalMode or
  b.isInsertMode or
  b.isVisualMode or
  b.isReplaceMode

proc isExpandableMode*(bufStatus: BufferStatus): bool {.inline.} =
  ## Can move up to the line.high + 1 in these modes.

  bufStatus.isInsertMode or
  bufStatus.isReplaceMode or
  bufStatus.isVisualMode

proc isCommandLineMode*(bufStatus: BufferStatus): bool {.inline.} =
  ## Returns true if the mode uses the command line.

  bufStatus.isExMode or bufStatus.isSearchMode

proc isCursor*(mode: Mode): bool {.inline.} =
  ## Return true if a mode in which it uses the cursor.

  case mode:
    of filer, bufManager, recentFile, backup, config, debug:
      # Don't use the cursor.
      return false
    else:
      return true

proc isCursor*(bufStatus: BufferStatus): bool {.inline.} =
  ## Return true if a mode in which it uses the cursor.

  bufStatus.mode.isCursor

proc isUpdate*(bufStatuses: seq[BufferStatus]): bool =
  ## Return true if at least one bufStatus.isUpdate is true.

  for b in bufStatuses:
    if b.isUpdate: return true

proc checkBufferExist*(bufStatus: seq[BufferStatus], path: Runes): Option[int] =
  for index, buf in bufStatus:
    if buf.path == path:
      return some(index)

proc absolutePath*(bufStatus: BufferStatus): Runes =
  if isAbsolute($bufStatus.path):
    bufStatus.path
  else:
    bufStatus.openDir / bufStatus.path

proc initBufferStatus*(
  path: string,
  mode: Mode): BufferStatus =
    ## Open a file or dir and return a new BufferStatus.
    # TODO: Return Result type

    result.isUpdate = true
    result.openDir = getCurrentDir().toRunes
    result.prevMode = mode
    result.mode = mode
    result.lastSaveTime = now()
    result.lastGitInfoCheckTime = now()

    if isFilerMode(result.mode):
      result.path = absolutePath(path).toRunes
      result.buffer = initGapBuffer(@[ru ""])
    else:
      result.path = path.toRunes

      if not fileExists($result.path):
        result.buffer = newFile()
      else:
        let textAndEncoding = openFile(result.path)
        result.buffer = textAndEncoding.text.toGapBuffer
        result.characterEncoding = textAndEncoding.encoding

        result.isTrackingByGit = isTrackingByGit(path)

      result.language = detectLanguage($result.path)

proc initBufferStatus*(
  mode: Mode): BufferStatus =
    ## Return a BufferStatus for a new empty buffer.
    # TODO: Return an error if open a dir.
    # TODO: Return Result type

    result.isUpdate = true
    result.openDir = getCurrentDir().toRunes
    result.prevMode = mode
    result.mode = mode
    result.lastSaveTime = now()
    result.lastGitInfoCheckTime = now()

    if mode.isFilerMode:
      result.buffer = initGapBuffer(@[ru ""])
    else:
      result.buffer = newFile()

proc initBufferStatus*(
  path: string): BufferStatus {.inline.} =
    # TODO: Return an error if open a dir.
    # TODO: Return Result type

    initBufferStatus(path, Mode.normal)

proc changeMode*(bufStatus: var BufferStatus, mode: Mode) =
  let currentMode = bufStatus.mode

  bufStatus.prevMode = currentMode
  bufStatus.mode = mode

proc positionEndOfBuffer*(bufStatus: BufferStatus): BufferPosition {.inline.} =
  ## Return the BufferPosition of the end of the buffer.

  BufferPosition(
    line: bufStatus.buffer.high,
    column: bufStatus.buffer[bufStatus.buffer.high].high)

proc updateLastGitInfoCheckTime*(bufStatus: var BufferStatus) {.inline.} =
  bufStatus.lastGitInfoCheckTime = now()

proc updateChangedLines*(bufStatus: var BufferStatus, diffs: seq[Diff]) =
  ## Update changedLines and lastGitInfoCheckTime.

  bufStatus.changedLines = diffs
  bufStatus.updateLastGitInfoCheckTime

proc updateSyntaxCheckerResults*(
  bufStatus: var BufferStatus,
  output: seq[string]): Result[(), string]=
    ## Update BufferStatus.syntaxCheckResults

    let r = parseNimCheckResult($bufStatus.path.absolutePath, output)
    if r.isErr:
      return Result[(), string].err r.error

    bufStatus.syntaxCheckResults = r.get

    return Result[(), string].ok ()
