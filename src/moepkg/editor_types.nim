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

## Editor type definitions
## This module contains the core Editor type and related types used across editor modules.

import std/tables

import pkg/celina

import
  buffer, types, commands, command_registry, modes, command_line, command_config,
  window_manager, lsp_integration, config, persist, background_process
import key_bindings except Command
import command_handlers/handler_manager

export
  buffer, types, commands, command_registry, modes, command_line, command_config,
  window_manager, lsp_integration, config, persist, handler_manager, tables, celina,
  background_process

type
  ScreenSize* = object
    width*, height*: int
    prevWidth*, prevHeight*: int

  Editor* = ref object
    textBuffer*: TextBuffer
    state*: EditorState
    viewport*: ViewPort
    screenSize*: ScreenSize
    executer*: CommandExecutor
    commandRegistry*: CommandRegistry
    keyBindingRegistry*: KeyBindingRegistry
    commandLineParser*: CommandLineParser
    commandConfig*: CommandConfig
    handlerManager*: HandlerManager
    windowManager*: EditorWindowManager
    buffers*: seq[TextBuffer]
    config*: EditorConfig
    lsp*: LspIntegration
    lastLspChangeSeq*: int
    app*: AsyncApp
    cursorPositions*: Table[string, CursorPositionEntry]
    savedBookmarks*: Table[string, seq[int]]
    runningBackgroundProcesses*: seq[BackgroundProcess]

  RenderContext* = object
    ## Context for rendering operations to reduce parameter passing
    cursorLine*: int
    cursorCol*: int
    cursorDisplayCol*: int ## Screen column of cursor (accounting for tabs/wide chars)
    hasSelection*: bool
    selStart*: BufferPosition
    selEnd*: BufferPosition
    windowMode*: EditorMode ## Mode of the window being rendered
    windowRightEdge*: int ## Absolute screen X of window's right edge

  IndentInfo* = object
    ## Cached indentation analysis for a line to avoid O(n²) performance
    leadingWhitespaceEnd*: int
    hasContent*: bool

# Basic accessor procedures
proc buffer*(e: Editor): TextBuffer {.inline.} =
  e.textBuffer

proc activeBuffer*(e: Editor): TextBuffer {.inline.} =
  ## Get the currently active buffer (always from the active window since we always have at least one window)
  e.windowManager.windows[e.windowManager.activeWindowIndex].buffer

proc activeWindow*(e: Editor): EditorWindow {.inline.} =
  ## Get the currently active window
  e.windowManager.windows[e.windowManager.activeWindowIndex]

proc currentMode*(e: Editor): EditorMode {.inline.} =
  ## Get the current mode from the active window
  ## This is the authoritative source for the current mode
  e.activeWindow.mode

proc cursor*(e: Editor): BufferPosition {.inline.} =
  ## Get the cursor position from the active window
  ## This is the authoritative source for the cursor position
  ## Also syncs EditorState.cursor for handler compatibility
  e.activeWindow.cursor

proc `cursor=`*(e: Editor, pos: BufferPosition) {.inline.} =
  ## Set the cursor position in the active window and EditorState
  ## Both are kept in sync for handler compatibility
  e.activeWindow.cursor = pos
  e.state.cursor = pos

proc syncCursorToWindow*(e: Editor) {.inline.} =
  ## Sync EditorState.cursor to EditorWindow.cursor
  ## Call this after handler functions modify state.cursor
  e.activeWindow.cursor = e.state.cursor

proc syncCursorFromWindow*(e: Editor) {.inline.} =
  ## Sync EditorWindow.cursor to EditorState.cursor
  ## Call this before handler functions that read state.cursor
  e.state.cursor = e.activeWindow.cursor

proc setMode*(e: Editor, mode: EditorMode) {.inline.} =
  ## Set the current mode in the active window and EditorState
  ## Both are kept in sync for handler compatibility
  e.activeWindow.mode = mode
  e.state.mode = mode

proc syncModeToWindow*(e: Editor) {.inline.} =
  ## Sync EditorState.mode to EditorWindow.mode
  ## Call this after handler functions modify state.mode
  e.activeWindow.mode = e.state.mode

proc syncModeFromWindow*(e: Editor) {.inline.} =
  ## Sync EditorWindow.mode to EditorState.mode
  ## Call this before handler functions that read state.mode
  e.state.mode = e.activeWindow.mode

proc syncStateFromWindow*(e: Editor) {.inline.} =
  ## Sync all EditorState fields from EditorWindow
  ## Call this before handler functions
  e.state.cursor = e.activeWindow.cursor
  e.state.mode = e.activeWindow.mode

proc syncStateToWindow*(e: Editor) {.inline.} =
  ## Sync all EditorState fields to EditorWindow
  ## Call this after handler functions
  e.activeWindow.cursor = e.state.cursor
  e.activeWindow.mode = e.state.mode
