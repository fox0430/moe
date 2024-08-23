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

import std/[os, times, strformat]

import pkg/results

import ui, bufferstatus, editorstatus, cmdlineoption, git, editorview, theme,
       settings, messages, logger, registers

type
  InitError* = CatchableError

proc loadPersistData(status: var EditorStatus) =
  ## Load persisted data (Ex command history, search history and cursor
  ## position)

  if status.settings.persist.exCommand:
    let limit = status.settings.persist.exCommandHistoryLimit
    status.exCommandHistory = loadExCommandHistory(limit)

  if status.settings.persist.search:
    let limit = status.settings.persist.searchHistoryLimit
    status.searchHistory = loadSearchHistory(limit)

  if status.settings.persist.cursorPosition:
    status.lastPosition = loadLastCursorPosition()
    currentMainWindowNode.restoreCursorPosition(
      currentBufStatus,
      status.lastPosition)

proc initCurrentMainWindowView(status: var EditorStatus) {.inline.} =
  currentMainWindowNode.view = currentBufStatus.buffer.initEditorView(1, 1)

proc addBufferStatus(status: var EditorStatus, parsedList: CmdParsedList) =
  ## Open files or dirs at received paths and initialize views and windows.
  ## If paths don't exist, add an empty buffer.

  if parsedList.path.len == 0:
    # Add a new empty buffer
    discard status.addNewBufferInCurrentWin
  else:
    # Check git command.
    let isGitAvailable = isGitAvailable()

    # Open all files for dirs at received paths.
    for path in parsedList.path:
      if dirExists(path):
        if status.addNewBuffer(path, Mode.filer).isErr:
          status.commandLine.writeFileOpenError(path)
        else:
          status.addFilerStatus
      else:
        if status.addNewBuffer(path, Mode.normal).isErr:
          status.commandLine.writeFileOpenError(path)
          continue

        if isGitAvailable:
          status.bufStatus[^1].isTrackingByGit = isTrackingByGit($path)

    if status.settings.startUp.fileOpen.autoSplit and status.bufStatus.len > 1:
      # Display all added buffers in split view.

      for i in 0 .. status.bufStatus.high:
        status.initCurrentMainWindowView

        if i == status.bufStatus.high:
          # Set the buffer to the latest window.
          status.changeCurrentBuffer(i)
        else:
          # Split the window and set the buffer to the window and move to the
          # latest window.
          case status.settings.startUp.fileOpen.splitType:
            of WindowSplitType.vertical: status.verticalSplitWindow
            of WindowSplitType.horizontal: status.horizontalSplitWindow
          status.changeCurrentBuffer(i)
          status.moveNextWindow
    else:
      # Display only a single buffer.

      if status.bufStatus.len == 0:
        # Add a new empty buffer if files couldn't be read due to some error.
        discard status.addNewBufferInCurrentWin
      else:
        status.initCurrentMainWindowView
        status.changeCurrentBuffer(status.bufStatus.high)

proc initSidebar(status: var EditorStatus) =
  if status.settings.view.sidebar:
    currentMainWindowNode.view.initSidebar

proc checkNcurses(): Result[(), string] =
  let v = getNcursesVersion()
  if not checkRequireNcursesVersion():
    let errorMsg =
      "Error: This Ncurses version is not supported\n\n" &
      fmt"Current version: v{$v}" & '\n' &
      "Require: v6.2 or higher\n"

    return Result[(), string].err errorMsg

  return Result[(), string].ok ()

proc initEditor*(): Result[EditorStatus, string] =
  block:
    let r = checkNcurses()
    if r.isErr:
      echo r.error
      quit()

  let parsedList = parseCommandLineOption(commandLineParams())

  startUi()

  var s = initEditorStatus()

  s.loadConfigurationFile
  s.timeConfFileLastReloaded = now()

  if s.settings.lsp.enable:
    # Force enable logger if enabled LSP.
    initLogger()

  block initColors:
    let r = s.settings.theme.colors.initEditrorColor(
      s.settings.standard.colorMode)
    if r.isErr: return Result[EditorStatus, string].err r.error

  setControlCHook(proc() {.noconv.} =
    exitUi()
    quit())

  if parsedList.isReadonly:
    s.isReadonly = true

  s.addBufferStatus(parsedList)

  s.loadPersistData

  s.initSidebar

  if s.settings.clipboard.enable:
    s.registers.setClipBoardTool(s.settings.clipboard.tool)

  disableControlC()
  catchTerminalResize()

  showCursor()
  setBlinkingBlockCursor()

  return Result[EditorStatus, string].ok s
