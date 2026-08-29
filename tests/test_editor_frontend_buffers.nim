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

## Tests for the frontend-neutral buffer-session API.

import std/[options, sequtils, strutils, unittest]

import pkg/results

import ../src/moepkg/[buffer, config, editor]

proc createTestEditor(): Editor =
  newEditor(newEditorConfig())

proc addWindowBuffer(e: Editor, title: string): TextBuffer =
  result = newTextBuffer()
  result.displayName = some(title)
  e.addBuffer(result)
  e.addBufferToWindowList(result)

suite "Editor frontend buffers":
  test "activeWindowBuffers returns ordered value snapshots":
    let
      e = createTestEditor()
      second = newTextBuffer()
    second.filePath = some("/tmp/second.nim")
    second.readOnly = true
    second.changeSeq = 1
    e.addBuffer(second)
    e.addBufferToWindowList(second)
    check e.activateBuffer(second.id)

    let buffers = e.activeWindowBuffers()

    check buffers.len == 2
    check buffers[0].title == "No Name"
    check buffers[1] ==
      OpenBufferInfo(
        id: second.id,
        title: "second.nim",
        filePath: some("/tmp/second.nim"),
        modified: true,
        readOnly: true,
        active: true,
      )

  test "activeWindowBuffers uses a display name and ignores stale ids":
    let
      e = createTestEditor()
      named = e.addWindowBuffer("Terminal 1")
    e.activeWindow.bufferIds.insert(BufferId(99999), 0)

    let buffers = e.activeWindowBuffers()

    check buffers.len == 2
    check buffers[1].id == named.id
    check buffers[1].title == "Terminal 1"

  test "activeWindowBuffers appends an unregistered active buffer":
    let
      e = createTestEditor()
      registered = e.addWindowBuffer("Registered")
      active = newTextBuffer()
    e.addBuffer(active)
    e.activeWindow.buffer = active

    let buffers = e.activeWindowBuffers()

    check buffers.len == 3
    check buffers[1].id == registered.id
    check buffers[2].id == active.id
    check buffers[2].active

  test "activateBuffer resolves a stable id and registers it in the window":
    let
      e = createTestEditor()
      target = newTextBuffer()
    e.addBuffer(target)

    check target.id notin e.activeWindow.bufferIds
    check e.activateBuffer(target.id)
    check e.activeBuffer == target
    check target.id in e.activeWindow.bufferIds
    check not e.activateBuffer(BufferId(99999))

  test "moveBuffer reorders the active window":
    let
      e = createTestEditor()
      second = e.addWindowBuffer("Second")
      third = e.addWindowBuffer("Third")

    check e.moveBuffer(third.id, 0)
    check e.activeWindowBuffers().mapIt(it.id) == @[
      third.id, e.buffers[0].id, second.id
    ]
    check e.moveBuffer(third.id, 0)
    check not e.moveBuffer(BufferId(99999), 0)
    check not e.moveBuffer(third.id, 3)

  test "closeBuffer rejects modified buffers":
    let
      e = createTestEditor()
      target = e.addWindowBuffer("Modified")
    target.changeSeq = 1

    let closeResult = e.closeBuffer(target.id)

    check closeResult.isErr
    check "No write since last change" in closeResult.error
    check e.bufferById(target.id).isSome

  test "closeBuffer removes an inactive buffer without changing selection":
    let
      e = createTestEditor()
      target = e.addWindowBuffer("Inactive")
      activeId = e.activeBuffer.id

    check e.closeBuffer(target.id).isOk
    check e.bufferById(target.id).isNone
    check e.activeBuffer.id == activeId
    check target.id notin e.activeWindow.bufferIds

  test "closeBuffer redirects windows displaying the buffer":
    let
      e = createTestEditor()
      target = e.addWindowBuffer("Active")
    check e.activateBuffer(target.id)

    check e.closeBuffer(target.id).isOk
    check e.bufferById(target.id).isNone
    check e.activeBuffer.id != target.id

  test "closeBuffer redirects a buffer displayed by another window":
    let
      e = createTestEditor()
      initial = e.activeBuffer
      target = e.addWindowBuffer("Other window")
    check e.activateBuffer(target.id)
    check e.vsplit().isOk
    check e.activateBuffer(initial.id)
    check e.activeBuffer == initial
    check e.windowManager.windows.anyIt(it.buffer == target)

    check e.closeBuffer(target.id).isOk
    check e.activeBuffer == initial
    check e.windowManager.windows.allIt(it.buffer != target)

  test "closeBuffer replaces the final buffer and reports an unknown id":
    let e = createTestEditor()
    let originalId = e.activeBuffer.id

    check e.closeBuffer(originalId).isOk
    check e.buffers.len == 1
    check e.activeBuffer.id != originalId
    check e.activeBuffer.filePath.isNone

    let missingResult = e.closeBuffer(originalId)
    check missingResult.isErr
    check missingResult.error == "Buffer does not exist"
