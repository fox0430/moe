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

import std/unittest

import ../src/moepkg/command_handlers/handler_result

const
  # Expected classification, mirrored from group(). A new kind belongs to
  # hrgExitAndResync unless added to one of these sets.
  AppExitKinds = {hrQuit, hrCquit}
  HandledGenericKinds = {hrHandled, hrUnhandled, hrError}
  ExitToNormalKinds = {
    hrQuickRun, hrBuild, hrSubstitute, hrDeleteLines, hrJumpList, hrChanges,
    hrConflictNext, hrConflictPrev, hrTheme, hrPutConfigFile, hrLspFormat, hrLspRestart,
    hrLspFold, hrLspExecuteCommand, hrLspCallHierarchyIncoming,
    hrLspCallHierarchyOutgoing,
  }
  ExitToNewModeKinds = {
    hrEnterFiler, hrEnterTerminal, hrEnterLogViewer, hrLspLog, hrEnterHelpViewer,
    hrEnterBufferManager, hrEnterBackupManager, hrRecentFile, hrDebug,
    hrEnterBookmarkManager, hrConfig,
  }
  NonResyncKinds =
    AppExitKinds + HandledGenericKinds + ExitToNormalKinds + ExitToNewModeKinds

suite "HandlerResult - group() classification":
  test "hrgAppExit covers hrQuit / hrCquit":
    for k in AppExitKinds:
      check group(k) == hrgAppExit

  test "hrgHandledGeneric covers hrHandled / hrUnhandled / hrError":
    for k in HandledGenericKinds:
      check group(k) == hrgHandledGeneric

  test "hrgExitToNormal covers Command-mode one-shot actions":
    for k in ExitToNormalKinds:
      check group(k) == hrgExitToNormal

  test "hrgExitToNewMode covers viewer entry kinds":
    for k in ExitToNewModeKinds:
      check group(k) == hrgExitToNewMode

  test "hrgExitAndResync is the default bucket for all other kinds":
    ## With the four membership tests above this pins every kind's group;
    ## NonResyncKinds is derived from the same sets, so the two halves
    ## cannot drift apart.
    for k in HandlerResultKind:
      if k notin NonResyncKinds:
        check group(k) == hrgExitAndResync

  test "group(HandlerResult) delegates to group(kind)":
    let r = HandlerResult(kind: hrQuit)
    check r.group == group(hrQuit)
    let r2 = HandlerResult(kind: hrEnterFiler)
    check r2.group == group(hrEnterFiler)
