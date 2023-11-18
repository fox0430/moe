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

import std/[os, times]
import pkg/results
import moepkg/[ui, bufferstatus, editorstatus, cmdlineoption, mainloop, git,
               editorview, theme, registers, settings, messages, logger]

proc loadPersistData(status: var EditorStatus) =
  ## Load persisted data (Ex command history, search history and cursor
  ## postion)

  if status.settings.persist.exCommand:
    let limit = status.settings.persist.exCommandHistoryLimit
    status.exCommandHistory = loadExCommandHistory(limit)

  if status.settings.persist.search:
    let limit = status.settings.persist.searchHistoryLimit
    status.searchHistory = loadSearchHistory(limit)

  if status.settings.persist.cursorPosition:
    status.lastPosition = loadLastCursorPosition()
    currentMainWindowNode.restoreCursorPostion(
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

proc initEditor(): EditorStatus =
  let parsedList = parseCommandLineOption(commandLineParams())

  startUi()

  result = initEditorStatus()
  result.loadConfigurationFile
  result.timeConfFileLastReloaded = now()

  if result.settings.lsp.enable:
    # Force enable logger if enabled LSP.
    initLogger()

  block initColors:
    # TODO: Show error messages when failing to the load VSCode theme.
    let r = result.settings.standard.editorColorTheme.initEditrorColor(
      result.settings.standard.colorMode)
    if r.isErr:
      exitUi()
      echo r.error
      # TODO: Fix raise
      raise

  setControlCHook(proc() {.noconv.} =
    exitUi()
    quit())

  if parsedList.isReadonly:
    result.isReadonly = true

  result.addBufferStatus(parsedList)

  result.loadPersistData

  result.initSidebar

  initOperationRegisters()

  disableControlC()

  setBlinkingBlockCursor()

proc main() =
  var status = initEditor()

  status.editorMainLoop

  status.exitEditor

when isMainModule: main()

