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

## Listing and jump side effects (jump list, change list, git conflicts),
## split out of result_processor.nim.

import std/[os, unicode]

import ../[buffer, editor, git_conflict, types, unicode_utils]

import editor_ops, handler_result

proc processJumpResult*(e: Editor, r: HandlerResult): bool =
  ## Show the jump list in a temp message. Returns true to continue.
  case r.kind
  of hrJumpList:
    if e.state.jumpList.list.len == 0:
      e.state.statusMessage = "Jump list is empty"
    else:
      e.state.ui.tempMessages = @[]
      e.state.ui.tempMessages.add(" jump  line  col  file")
      for i, pos in e.state.jumpList.list:
        let marker = if i == e.state.jumpList.index: ">" else: " "
        let jumpNum = e.state.jumpList.list.len - i
        let lineNum = pos.line + 1
        let colNum = pos.column + 1
        let bufOpt = e.bufferById(pos.bufferId)
        let fileName =
          if bufOpt.isSome:
            let buf = bufOpt.get
            if buf.filePath.isSome: buf.filePath.get.extractFilename else: "[No Name]"
          else:
            "[Invalid]"
        e.state.ui.tempMessages.add(
          marker & ($jumpNum).align(4) & " " & ($lineNum).align(5) & " " &
            ($colNum).align(4) & "  " & fileName
        )
    return true
  else:
    return true # Not the jump-list kind; caller misrouted (defensive)

proc processChangeResult*(e: Editor, r: HandlerResult): bool =
  ## Show the active buffer's change list in a temp message.
  ## Returns true to continue.
  case r.kind
  of hrChanges:
    let buf = e.activeBuffer()
    if buf.changeList.len == 0:
      e.state.statusMessage = "No changes"
    else:
      e.state.ui.tempMessages = @[]
      e.state.ui.tempMessages.add("change  line  col  text")
      for i in 0 ..< buf.changeList.len:
        let pos = buf.changeList[i]
        let lineNum = pos.line + 1
        let colNum = pos.column + 1
        let marker = if i == buf.changeListIndex + 1: ">" else: " "
        let text =
          if pos.line < buf.len:
            buf.getLine(pos.line).truncateToCharsWithSuffix(40)
          else:
            ""
        let changeNum = buf.changeList.len - i
        e.state.ui.tempMessages.add(
          marker & ($changeNum).align(4) & " " & ($lineNum).align(5) & " " &
            ($colNum).align(4) & "  " & text
        )
      let w = e.activeWindow
      let curMarker = if buf.changeListIndex == buf.changeList.len - 1: ">" else: " "
      e.state.ui.tempMessages.add(
        curMarker & "0".align(4) & " " & ($(w.cursor.line + 1)).align(5) & " " &
          ($(w.cursor.column + 1)).align(4) & "  "
      )
    return true
  else:
    return true # Not the change-list kind; caller misrouted (defensive)

proc processConflictJumpResult*(e: Editor, r: HandlerResult): bool =
  ## Jump to the next or previous git conflict marker. Returns true to continue.
  case r.kind
  of hrConflictNext:
    let buf = e.activeBuffer()
    let fromLine = e.activeWindow.cursor.line
    let nxt = buf.findNextConflict(fromLine)
    if nxt.isSome:
      e.activeWindow.cursor.line = nxt.get.startLine
      e.activeWindow.cursor.column = 0
      e.updateViewportForCursor(e.cursor)
    else:
      e.state.statusMessage = "No next git conflict"
    return true
  of hrConflictPrev:
    let buf = e.activeBuffer()
    let fromLine = e.activeWindow.cursor.line
    let prv = buf.findPrevConflict(fromLine)
    if prv.isSome:
      e.activeWindow.cursor.line = prv.get.startLine
      e.activeWindow.cursor.column = 0
      e.updateViewportForCursor(e.cursor)
    else:
      e.state.statusMessage = "No previous git conflict"
    return true
  else:
    return true # Not a conflict-jump kind; caller misrouted (defensive)
