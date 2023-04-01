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
import moepkg/[ui, bufferstatus, editorstatus, cmdlineoption, mainloop, git,
               editorview]

# Load persisted data (Ex command history, search history and cursor postion)
proc loadPersistData(status: var EditorStatus) =
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

proc addBufferStatus(status: var EditorStatus, parsedList: CmdParsedList) =
  if parsedList.path.len > 0:
    let isGitAvailable = isGitAvailable()

    for path in parsedList.path:
      if dirExists(path):
        status.addNewBufferInCurrentWin(path, Mode.filer)
      else:
        status.addNewBufferInCurrentWin(path)
        if isGitAvailable:
          status.bufStatus[^1].isTrackingByGit = isTrackingByGit($path)
  else:
    status.addNewBufferInCurrentWin

proc initSidebar(status: var EditorStatus) =
  currentMainWindowNode.view.initSidebar

  if status.settings.git.showChangedLine and currentBufStatus.isTrackingByGit:
     currentBufStatus.updateChangedLines

proc initEditor(): EditorStatus =
  let parsedList = parseCommandLineOption(commandLineParams())

  startUi()

  result = initEditorStatus()
  result.loadConfigurationFile
  result.timeConfFileLastReloaded = now()
  result.changeTheme

  setControlCHook(proc() {.noconv.} =
    exitUi()
    quit())

  if parsedList.isReadonly:
    result.isReadonly = true

  result.addBufferStatus(parsedList)

  result.loadPersistData

  result.initSidebar

  disableControlC()

proc main() =
  var status = initEditor()

  status.editorMainLoop

  status.exitEditor

when isMainModule: main()

