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

# This file is included by editor.nim - do not import directly
# Contains window split and buffer management procedures

proc vsplit*(e: Editor, filename: Option[string] = none(string)): Result[(), string] =
  ## Create a vertical split window
  # Save current window state before splitting (if windows already exist)
  if e.windowManager.windows.len > 0:
    e.saveActiveWindowState()

  let bufferResult =
    e.windowManager.vsplit(e.textBuffer, e.viewport, e.state.cursor, filename)
  if bufferResult.isErr:
    return err(bufferResult.error)

  let newBuffer = bufferResult.get

  # Add the new buffer to the buffer list if it's not already there
  var found = false
  for buf in e.buffers:
    if buf == newBuffer:
      found = true
      break
  if not found:
    e.buffers.add(newBuffer)
    # Set reserved words for syntax highlighting on new buffer
    newBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))
    logDebug("editor", "vsplit: buffer added, buffers.len: " & $e.buffers.len)

  # Sync active window state (buffer, viewport, cursor) with executor
  e.syncActiveWindow()

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

  ok(())

proc vsplitWithBuffer*(e: Editor, buffer: TextBuffer): Result[(), string] =
  ## Create a vertical split window with a specific buffer
  # Save current window state before splitting (if windows already exist)
  if e.windowManager.windows.len > 0:
    e.saveActiveWindowState()

  let bufferResult =
    e.windowManager.vsplitWithBuffer(e.textBuffer, e.viewport, e.state.cursor, buffer)
  if bufferResult.isErr:
    return err(bufferResult.error)

  let newBuffer = bufferResult.get

  # Add the new buffer to the buffer list if it's not already there
  var found = false
  for buf in e.buffers:
    if buf == newBuffer:
      found = true
      break
  if not found:
    e.buffers.add(newBuffer)
    # Set reserved words for syntax highlighting on new buffer
    newBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))
    logDebug("editor", "vsplitWithBuffer: buffer added, buffers.len: " & $e.buffers.len)

  # Sync active window state (buffer, viewport, cursor) with executor
  e.syncActiveWindow()

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

  ok(())

proc hsplit*(e: Editor, filename: Option[string] = none(string)): Result[(), string] =
  ## Create a horizontal split window (top and bottom)
  # Save current window state before splitting (if windows already exist)
  if e.windowManager.windows.len > 0:
    e.saveActiveWindowState()

  let bufferResult = e.windowManager.hsplit(
    e.textBuffer, e.viewport, e.state.cursor, e.state.display.multiStatusLine, filename
  )
  if bufferResult.isErr:
    return err(bufferResult.error)

  let newBuffer = bufferResult.get

  # Add the new buffer to the buffer list if it's not already there
  var found = false
  for buf in e.buffers:
    if buf == newBuffer:
      found = true
      break
  if not found:
    e.buffers.add(newBuffer)
    # Set reserved words for syntax highlighting on new buffer
    newBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))
    logDebug("editor", "hsplit: buffer added, buffers.len: " & $e.buffers.len)

  # Sync active window state (buffer, viewport, cursor) with executor
  e.syncActiveWindow()

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

  ok(())

proc hsplitWithBuffer*(e: Editor, buffer: TextBuffer): Result[(), string] =
  ## Create a horizontal split window with a specific buffer
  # Save current window state before splitting (if windows already exist)
  if e.windowManager.windows.len > 0:
    e.saveActiveWindowState()

  let bufferResult = e.windowManager.hsplitWithBuffer(
    e.textBuffer, e.viewport, e.state.cursor, e.state.display.multiStatusLine, buffer
  )
  if bufferResult.isErr:
    return err(bufferResult.error)

  logDebug(
    "editor",
    "hsplitWithBuffer: after wm.hsplitWithBuffer, activeWindowIndex=" &
      $e.windowManager.activeWindowIndex & " windows.len=" & $e.windowManager.windows.len,
  )

  let newBuffer = bufferResult.get

  # Add the new buffer to the buffer list if it's not already there
  var found = false
  for buf in e.buffers:
    if buf == newBuffer:
      found = true
      break
  if not found:
    e.buffers.add(newBuffer)
    # Set reserved words for syntax highlighting on new buffer
    newBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))
    logDebug("editor", "hsplitWithBuffer: buffer added, buffers.len: " & $e.buffers.len)

  # Sync active window state (buffer, viewport, cursor) with executor
  e.syncActiveWindow()

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

  ok(())

proc enew*(e: Editor): Result[(), string] =
  ## Create a new empty buffer and add it to the buffer list
  let newBuffer = newTextBuffer()

  # Add the new buffer to the buffer list
  e.buffers.add(newBuffer)
  # Set reserved words for syntax highlighting on new buffer
  newBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))
  logDebug("editor", "enew: buffer added, buffers.len: " & $e.buffers.len)

  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    # Replace the buffer in the active window
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    activeWindow.buffer = newBuffer
    activeWindow.cursor = BufferPosition(line: 0, column: 0)
    activeWindow.viewport.topLine = 0
    activeWindow.viewport.leftColumn = 0

    # Update executor and motion controller references
    e.executer.buffer = newBuffer
    e.executer.motionController.executor.buffer = newBuffer
    e.executer.motionController.viewportManager.viewport = activeWindow.viewport

    # Reset cursor
    e.state.cursor = BufferPosition(line: 0, column: 0)
  else:
    # No windows, replace the main buffer
    e.textBuffer = newBuffer
    e.executer.buffer = newBuffer
    e.executer.motionController.executor.buffer = newBuffer
    e.state.cursor = BufferPosition(line: 0, column: 0)
    e.viewport.topLine = 0
    e.viewport.leftColumn = 0

  e.state.needsFullRedraw = true
  ok(())

proc new*(e: Editor): Result[(), string] =
  ## Create a new empty buffer in a horizontal split (like :new in Vim)
  let newBuffer = newTextBuffer()
  return e.hsplitWithBuffer(newBuffer)

proc vnew*(e: Editor): Result[(), string] =
  ## Create a new empty buffer in a vertical split (like :vnew in Vim)
  let newBuffer = newTextBuffer()
  return e.vsplitWithBuffer(newBuffer)
