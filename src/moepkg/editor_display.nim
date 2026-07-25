#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

## Display toggle commands. Config-backed read accessors live in
## types/editor_types.nim.

import types/editor_types, status_line, git_cache

proc toggleStatusLine*(e: Editor) =
  e.showStatusLine = not e.showStatusLine

proc setStatusLineVisible*(e: Editor, visible: bool) =
  e.showStatusLine = visible

proc toggleLineCount*(e: Editor) =
  ## Toggle the visibility of line count in status line
  e.state.toggleLineCount()

proc setLineCountVisible*(e: Editor, visible: bool) =
  ## Set the visibility of line count in status line
  e.state.setLineCountVisible(visible)

proc toggleLinePercentage*(e: Editor) =
  ## Toggle the visibility of line percentage in status line
  e.state.toggleLinePercentage()

proc setLinePercentageVisible*(e: Editor, visible: bool) =
  ## Set the visibility of line percentage in status line
  e.state.setLinePercentageVisible(visible)

proc toggleEncoding*(e: Editor) =
  ## Toggle the visibility of encoding in status line
  e.state.toggleEncoding()

proc setEncodingVisible*(e: Editor, visible: bool) =
  ## Set the visibility of encoding in status line
  e.state.setEncodingVisible(visible)

proc toggleLineWrap*(e: Editor) =
  e.lineWrap = not e.lineWrap

proc setLineWrap*(e: Editor, enabled: bool) =
  e.lineWrap = enabled

proc toggleMultiStatusLine*(e: Editor) =
  e.multiStatusLine = not e.multiStatusLine

proc setMultiStatusLine*(e: Editor, enabled: bool) =
  e.multiStatusLine = enabled

proc toggleSidebar*(e: Editor) =
  e.showSidebar = not e.showSidebar

proc setSidebarVisible*(e: Editor, visible: bool) =
  e.showSidebar = visible

proc toggleGitDiff*(e: Editor) =
  e.showGitDiff = not e.showGitDiff
  if e.showGitDiff:
    e.state.git.requestGitRefresh(e.activeBuffer)

proc setGitDiffVisible*(e: Editor, visible: bool) =
  e.showGitDiff = visible
  if visible:
    e.state.git.requestGitRefresh(e.activeBuffer)

proc toggleSyntaxChecker*(e: Editor) =
  e.showSyntaxChecker = not e.showSyntaxChecker

proc setSyntaxCheckerVisible*(e: Editor, visible: bool) =
  e.showSyntaxChecker = visible
