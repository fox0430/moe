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

## Jumping to a file: the LSP jumps, the list viewers, document links, `gx`
## and a picker all go through `jumpToFile`, which opens the file as `:e`
## does, or `jumpTo`, which takes a buffer too.

import std/[options, os]

import pkg/results

import
  types/editor_types, editor_window, editor_buffers, viewer_mode, buffer, unicode_utils

type
  ColumnUnit* = enum
    cuChar ## Characters, as the cursor counts them.
    cuUtf16 ## UTF-16 code units, as LSP positions count them.

  TargetPosition* = object
    ## Where a jump puts the cursor. The column is read in the opened buffer,
    ## since a UTF-16 offset needs the line's text.
    line*, column*: int
    unit*: ColumnUnit

  OpenOutcome* = enum
    ## How `jumpToFile` ended.
    ooOpened ## The window shows another buffer now.
    ooMoved ## The cursor moved in the buffer the window already showed.
    ooStayed
      ## No position, and the window showed the file already: no jump is
      ## recorded. A window opened for the jump stays, as Vim's `:sb` on the
      ## current buffer still splits.

proc jumpOrigin*(e: Editor): JumpPosition =
  ## The cursor position, for a jump list entry once a jump from it lands.
  JumpPosition(
    bufferId: e.state.windowDisplay.currentBufferId,
    line: e.activeWindow.cursor.line,
    column: e.activeWindow.cursor.column,
  )

proc addToJumpList*(e: Editor, jumpPos: JumpPosition) =
  ## Add `jumpPos`, where a jump started, to the jump list.
  # Don't add if same as last position (same buffer, line, and column), but
  # stop navigating the list as any jump does (Vim's setpcmark)
  if e.state.jumpList.list.len > 0:
    let lastPos = e.state.jumpList.list[^1]
    if lastPos.bufferId == jumpPos.bufferId and lastPos.line == jumpPos.line and
        lastPos.column == jumpPos.column:
      e.state.jumpList.index = -1
      return

  e.state.jumpList.list.add(jumpPos)
  # Keep jump list at reasonable size (max 100 entries)
  if e.state.jumpList.list.len > 100:
    e.state.jumpList.list.delete(0)
  # Reset jump list index when adding new position
  e.state.jumpList.index = -1

proc placeCursor(e: Editor, at: TargetPosition) =
  ## Put the active window's cursor at `at`, clamped to its buffer.
  let buffer = e.activeBuffer()
  let line = clamp(at.line, 0, max(0, buffer.len - 1))
  let text =
    if buffer.len > 0:
      buffer.getLine(line)
    else:
      ""
  let column =
    case at.unit
    of cuChar:
      at.column
    of cuUtf16:
      utf16ToCharIndex(text, at.column)
  # Insert mode allows the cursor at charLen (append position)
  let last =
    if e.state.mode == EditorMode.Insert:
      text.charLen
    else:
      max(0, text.charLen - 1)
  e.activeWindow.cursor = BufferPosition(line: line, column: clamp(column, 0, last))

proc splitForJump(e: Editor, placement: ViewerPlacement): Result[bool, string] =
  ## Make the window a jump lands in: from the FileTree sidebar the one it
  ## serves (opened beside it when it is alone), then a `placement` split of
  ## it. True when a window was opened for the jump.
  let opened = ?e.leaveSidebar()
  if opened:
    # That window is new already: jump into it rather than split it again.
    return ok(true)
  case placement
  of vpInPlace:
    return ok(false)
  of vpVSplit:
    discard ?e.vsplit()
  of vpHSplit:
    discard ?e.hsplit()
  ok(true)

type JumpSubject* = object ## What a jump shows: a file, or a buffer of the editor.
  case isBuffer*: bool
  of false:
    path*: string
  of true:
    id*: BufferId

proc shows(e: Editor, subject: JumpSubject): bool =
  if subject.isBuffer:
    e.activeBuffer().id == subject.id
  else:
    e.activeBuffer().bufferHoldsFile(subject.path)

proc show(e: Editor, subject: JumpSubject): Result[void, string] =
  if subject.isBuffer:
    e.tryActivateBuffer(subject.id)
  else:
    let opened = e.openFileInActiveWindow(subject.path)
    if opened.isErr:
      return err("Failed to open file: " & opened.error)
    ok()

proc jumpTo*(
    e: Editor,
    subject: JumpSubject,
    at: Option[TargetPosition],
    placement: ViewerPlacement,
): Result[OpenOutcome, string] =
  ## `jumpToFile` for a file or a buffer of the editor, a buffer shown as `:b`
  ## shows it. Unlike moe's `:b`, and as Vim's, going to another buffer is a
  ## jump.
  let
    side = e.activeWindow
    previous = e.windowManager.previousWindow
  let split = e.splitForJump(placement)
  if split.isErr:
    e.restoreSidebarFocus(side, previous)
    return err("Failed to open window: " & split.error)

  # Taken in the window the jump lands in: a jump from the sidebar starts on
  # the file it serves, not the listing.
  let origin = e.jumpOrigin()
  var outcome = ooMoved
  if not e.shows(subject):
    let shown = e.show(subject)
    if shown.isErr:
      if split.get:
        # Don't leave the window opened for the jump behind
        discard e.closeWindow()
      e.restoreSidebarFocus(side, previous)
      return err(shown.error)
    outcome = ooOpened
  elif at.isNone:
    return ok(ooStayed)

  if at.isSome:
    e.placeCursor(at.get)
  e.addToJumpList(origin)
  ok(outcome)

proc jumpToFile*(
    e: Editor,
    path: string,
    at = none(TargetPosition),
    placement: ViewerPlacement = vpInPlace,
): Result[OpenOutcome, string] =
  ## Show `path` in the active window, or in a `placement` split of it, with the
  ## cursor `at` a position, or where `:e` puts it without one. A jump that
  ## lands joins the jump list. With no position and the file shown there
  ## already, no jump is recorded, as with Vim's `:b` and `:sb` on the current
  ## buffer; a split asked for still opens. On failure the focus goes back
  ## where it was.
  e.jumpTo(JumpSubject(isBuffer: false, path: path), at, placement)

proc followFileLink*(e: Editor, path: string): bool =
  ## Jump to `path`, the target of a link, as `gx` and an LSP document link do,
  ## and say in the status line how it went. False when it failed.
  let jumped = e.jumpToFile(path)
  if jumped.isErr:
    e.state.statusMessage = jumped.error
    return false
  e.state.statusMessage =
    if jumped.get == ooStayed:
      "Already in this file"
    else:
      "Opened: " & path.extractFilename
  true
