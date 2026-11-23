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

## Buffer / window switching and layout side effects, split out of
## result_processor.nim.

when not defined(moe.embedded):
  import std/[options, sequtils]

import pkg/results

import ../[editor, types, viewer_mode, window_manager, fold_open]

import editor_ops, handler_result

when not defined(moe.embedded):
  proc closeSessionOutOfView(e: Editor, id: BufferId, force: bool) =
    ## A Terminal session outlives its windows as a buffer does. As in Vim, one
    ## that has ended goes with the last of them, and `:q!` ends a running one.
    if not e.isTerminalBuffer(id) or (e.isJobRunning(id) and not force):
      return
    let buffer = e.bufferById(id)
    if buffer.isSome and e.holderCount(buffer.get) > 0:
      return
    e.closeTerminalBuffer(id)

proc applyClose*(e: Editor, force: bool): bool =
  ## Close the active window that `closeVerdict` lets close with the session
  ## going on. `force` is the `!` that ends the job the window shows. Returns
  ## true to continue.
  let activeWin = e.activeWindow
  when not defined(moe.embedded):
    # `:q!` ends the job its window shows, not one a viewer covers.
    let endsTabJob = force and e.isShowingTab(activeWin, activeWin.tabBufferId)
  # As a focus move, the mode ends with the window: Insert typed from with
  # Normal mode off leaves no popup or session behind.
  e.finalizeModeForFocusMove()
  e.closeLiveViewer()
  if e.activeWindow != activeWin:
    # A split viewer closed its own window as part of teardown.
    return true
  if e.state.mode in {EditorMode.Insert, EditorMode.Replace}:
    # An in-place viewer's teardown resumed the Insert it covered.
    e.finalizeModeForFocusMove()
  when not defined(moe.embedded):
    let tab = activeWin.tabBufferId
  if e.closeWindow():
    return false
  when not defined(moe.embedded):
    e.closeSessionOutOfView(tab, endsTabJob)
  true

proc processWindowResult*(e: Editor, r: HandlerResult, activeBuffer: TextBuffer): bool =
  ## Handle buffer / window switching and layout kinds. Returns true to continue.
  case r.kind
  of hrJumpToBuffer:
    # Handle jump to buffer with position (Ctrl-o/Ctrl-i across files)
    let targetLine = r.jumpLine
    let targetCol = r.jumpColumn
    let activated = e.tryActivateBuffer(r.jumpBufferId)
    if activated.isOk:
      # Update cursor position after buffer switch
      let buf = e.activeBuffer()
      if buf.len > 0:
        e.activeWindow.cursor.line = min(targetLine, buf.len - 1)
        let line = buf.getLine(e.activeWindow.cursor.line)
        let lineCharLen = line.charLen
        e.activeWindow.cursor.column =
          if lineCharLen == 0:
            0
          else:
            min(targetCol, max(0, lineCharLen - 1))
        e.state.openCursorFolds()
      e.updateViewportForCursor(e.cursor)
    else:
      e.state.statusMessage = activated.error
    return true
  of hrBufferNext:
    e.switchToNextBuffer()
    return true
  of hrBufferPrev:
    e.switchToPrevBuffer()
    return true
  of hrBufferFirst:
    e.switchToFirstBuffer()
    return true
  of hrBufferLast:
    e.switchToLastBuffer()
    return true
  of hrBufferNextTab:
    e.switchToNextTab()
    return true
  of hrBufferPrevTab:
    e.switchToPrevTab()
    return true
  of hrBuffer:
    discard e.switchToBuffer(r.bufferArg)
    return true
  of hrNextWindow:
    e.switchToNextWindow()
    return true
  of hrPrevWindow:
    e.switchToPrevWindow()
    return true
  of hrMoveWindowLeft:
    e.moveToWindowDirection(wdLeft)
    return true
  of hrMoveWindowDown:
    e.moveToWindowDirection(wdDown)
    return true
  of hrMoveWindowUp:
    e.moveToWindowDirection(wdUp)
    return true
  of hrMoveWindowRight:
    e.moveToWindowDirection(wdRight)
    return true
  of hrMaximizeWindowHeight:
    e.maximizeWindowHeight()
    return true
  of hrIncreaseWindowHeight:
    e.increaseWindowHeight()
    return true
  of hrDecreaseWindowHeight:
    e.decreaseWindowHeight()
    return true
  of hrIncreaseWindowWidth:
    e.increaseWindowWidth()
    return true
  of hrDecreaseWindowWidth:
    e.decreaseWindowWidth()
    return true
  of hrEqualizeWindows:
    e.equalizeWindowSizes()
    return true
  of hrSwapWindow:
    e.swapWindow()
    return true
  of hrOnlyWindow:
    when not defined(moe.embedded):
      let closedTabs =
        e.windowManager.windows.filterIt(it != e.activeWindow).mapIt(it.tabBufferId)
    for win in e.windowManager.windows:
      if win != e.activeWindow:
        e.releaseTabLines(win)
    e.windowManager.onlyWindow(e.screenSize.width, e.screenSize.height)
    e.syncActiveWindow()
    if e.windowManager.windows.len > 0:
      e.setActiveWindowScreenCursor(e.activeWindow)
    when not defined(moe.embedded):
      for tab in closedTabs:
        e.closeSessionOutOfView(tab, force = false)
    return true
  of hrBufferDelete:
    let deleteResult =
      if r.deleteBufferArg.len == 0:
        e.deleteCurrentBuffer(r.forceBufferDelete)
      else:
        e.deleteBufferByArg(r.deleteBufferArg, r.forceBufferDelete)
    if deleteResult.isErr:
      e.state.statusMessage = deleteResult.error
      # As a Vim error, the refusal ends the mapping that ran it.
      e.state.beep()
    return true
  of hrTerminalQuit:
    when defined(moe.embedded):
      e.state.statusMessage = "Terminal mode is unavailable in embedded builds"
    else:
      # Close the Terminal tab; closeTerminalBuffer picks a successor tab and
      # resets the window's mode to Normal.
      e.closeTerminalBuffer(e.activeWindow.tabBufferId)
    return true
  of hrFileTreeQuit:
    e.closeFileTree()
    return true
  else:
    return true # Not a window kind; caller misrouted (defensive)
