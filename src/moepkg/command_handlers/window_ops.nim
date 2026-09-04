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

import std/tables

import pkg/results

import ../[editor, editor_window_state, logger, types, window_manager]

import editor_ops, handler_result

proc processWindowResult*(e: Editor, r: HandlerResult, activeBuffer: TextBuffer): bool =
  ## Handle buffer / window switching and layout kinds. Returns true to continue.
  case r.kind
  of hrJumpToBuffer:
    # Handle jump to buffer with position (Ctrl-o/Ctrl-i across files)
    let targetIdx = e.bufferIndexById(r.jumpBufferId)
    let targetLine = r.jumpLine
    let targetCol = r.jumpColumn
    if targetIdx >= 0:
      e.switchToBufferByIndex(targetIdx)
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
      e.updateViewportForCursor(e.cursor)
    else:
      # Buffer was deleted since the jump was recorded
      e.state.statusMessage = "Buffer no longer available"
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
  of hrBuffer:
    discard e.switchToBuffer(r.bufferArg)
    return true
  of hrCloseWindow:
    let activeWin = e.activeWindow
    if not r.forceClose and e.windowManager.windows.len <= 1:
      # Closing the last window quits the editor, other buffers included.
      let discardErr = e.quitDiscardsBuffersError(activeWin.buffer)
      if discardErr.len > 0:
        e.state.statusMessage = discardErr
        return true
    if e.terminalStates.hasKey(activeWin.buffer.id):
      e.closeTerminalBuffer(activeWin.buffer.id)
    let shouldQuit = e.closeWindow()
    if shouldQuit:
      return false
    return true
  of hrNextWindow:
    e.switchToNextWindow()
    return true
  of hrPrevWindow:
    e.switchToPrevWindow()
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
    e.windowManager.onlyWindow(e.screenSize.width, e.screenSize.height)
    e.syncActiveWindow()
    if e.windowManager.windows.len > 0:
      e.setActiveWindowScreenCursor(e.activeWindow)
    return true
  of hrBufferDelete:
    e.deleteCurrentBuffer()
    return true
  of hrTerminalQuit:
    # Close the Terminal tab; closeTerminalBuffer picks a successor tab and
    # resets the window's mode to Normal.
    e.closeTerminalBuffer(e.activeWindow.buffer.id)
    return true
  of hrFileTreeQuit:
    # Close file tree window
    e.activeWindow.clearModeState(EditorMode.FileTree)
    # Remove file tree window and redistribute space
    let shouldQuit = e.closeWindow()
    if shouldQuit:
      let enewResult = e.enew()
      if enewResult.isErr:
        logError("handler", "Enew failed after file tree quit: " & enewResult.error)
        e.state.statusMessage = "Error: " & enewResult.error
    return true
  else:
    return true # Not a window kind; caller misrouted (defensive)
