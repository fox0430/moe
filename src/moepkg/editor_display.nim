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

## Display/view toggle commands for the editor: status line, line count,
## encoding, line wrap, sidebar, git diff, syntax checker, etc.

import types/editor_types, status_line, git_diff

proc toggleStatusLine*(e: Editor) =
  ## Toggle the visibility of the status line
  e.state.toggleStatusLine()

proc setStatusLineVisible*(e: Editor, visible: bool) =
  ## Set the visibility of the status line
  e.state.setStatusLineVisible(visible)

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
  ## Toggle line wrapping
  e.state.display.lineWrap = not e.state.display.lineWrap

proc setLineWrap*(e: Editor, enabled: bool) =
  ## Set line wrapping
  e.state.display.lineWrap = enabled

proc toggleMultiStatusLine*(e: Editor) =
  ## Toggle between single status line (at bottom) and multi status lines (per window)
  e.state.display.multiStatusLine = not e.state.display.multiStatusLine

proc setMultiStatusLine*(e: Editor, enabled: bool) =
  ## Set multi status line mode
  e.state.display.multiStatusLine = enabled

proc toggleSidebar*(e: Editor) =
  ## Toggle the visibility of the sidebar
  e.state.display.showSidebar = not e.state.display.showSidebar

proc setSidebarVisible*(e: Editor, visible: bool) =
  ## Set the visibility of the sidebar
  e.state.display.showSidebar = visible

proc toggleGitDiff*(e: Editor) =
  ## Toggle git diff indicators in sidebar
  e.state.display.showGitDiff = not e.state.display.showGitDiff

  # Update git diff information when enabled
  if e.state.display.showGitDiff:
    discard updateBufferWithGitDiff(e.activeBuffer)

proc setGitDiffVisible*(e: Editor, visible: bool) =
  ## Set git diff indicators visibility in sidebar
  e.state.display.showGitDiff = visible

  # Update git diff information when enabled
  if visible:
    discard updateBufferWithGitDiff(e.activeBuffer)

proc toggleSyntaxChecker*(e: Editor) =
  ## Toggle syntax checker results in sidebar
  e.state.display.showSyntaxChecker = not e.state.display.showSyntaxChecker

proc setSyntaxCheckerVisible*(e: Editor, visible: bool) =
  ## Set syntax checker results visibility in sidebar
  e.state.display.showSyntaxChecker = visible
