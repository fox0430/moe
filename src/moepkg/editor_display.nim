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

import std/options

import types/editor_types, status_line, git_cache

type
  ActiveGitStatus* = object
    ## Cached Git information for the active editor buffer.
    branch*: string
    added*, modified*, deleted*: int

  FrontendStatus* = object
    ## Frontend-neutral status values for an embedding host to display.
    modeLabel*: string
    message*: string
    git*: ActiveGitStatus

proc statusModeLabel*(e: Editor): string =
  ## Return the mode label displayed by the status line.
  ## An active command, search, or rename overlay takes precedence over the
  ## editor's underlying mode.
  if e.state.overlay.isSome:
    overlayLabel(e.state.overlay.get)
  else:
    modeLabel(e.currentMode, e.state.insertNormalMode)

proc currentStatusMessage*(e: Editor): string =
  ## Return the current transient status message.
  e.state.statusMessage

proc activeGitStatus*(e: Editor): ActiveGitStatus =
  ## Return cached Git information for the active buffer without refreshing it.
  let
    buffer = e.activeBuffer
    counts = e.state.git.gitDiffCounts(buffer)
  ActiveGitStatus(
    branch: e.state.git.gitBranchName(buffer),
    added: counts.added,
    modified: counts.modified,
    deleted: counts.deleted,
  )

proc frontendStatus*(e: Editor): FrontendStatus =
  ## Return one consistent snapshot of the active editor status.
  FrontendStatus(
    modeLabel: e.statusModeLabel,
    message: e.currentStatusMessage,
    git: e.activeGitStatus,
  )

proc frontendGitStatusEnabled*(e: Editor): bool =
  ## Whether the editor maintains Git status for an embedding frontend.
  e.state.frontendSubscriptions.gitStatus

proc setFrontendGitStatusEnabled*(e: Editor, enabled: bool) =
  ## Enable or disable active-buffer Git status maintenance for a frontend.
  ## Enabling forces the diff cache stale so the next frame refreshes it.
  var subscriptions = e.state.frontendSubscriptions
  if subscriptions.gitStatus == enabled:
    return

  subscriptions.gitStatus = enabled
  e.state.frontendSubscriptions = subscriptions
  if enabled:
    e.state.git.requestGitRefresh(e.activeBuffer)

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
