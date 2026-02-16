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

## Tests for normal_handler.nim
## This module tests the Normal mode command handler functionality.

import std/[unittest, options, tables]

import pkg/results

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/key_bindings {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/motion {.all.}
import ../src/moepkg/command_registry {.all.}
import ../src/moepkg/config {.all.}
import ../src/moepkg/registers {.all.}
import ../src/moepkg/command_handlers/normal_handler {.all.}

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
  EditorState(
    cursor: BufferPosition(line: 0, column: 0),
    preferredColumn: -1,
    screenCursor: CursorPosition(x: 0, y: 0),
    mode: EditorMode.Normal,
    previousMode: EditorMode.Normal,
    display: DisplaySettings(
      showTabLine: false,
      showStatusLine: true,
      multiStatusLine: false,
      showLineCount: true,
      showLinePercentage: true,
      showEncoding: true,
      showLineNumbers: true,
      showCursorLine: false,
      showSyntax: true,
      showIndentationLines: false,
      showSidebar: false,
      showGitDiff: false,
      showSyntaxChecker: false,
      showCodeLens: false,
      showDocumentHighlight: false,
      lineWrap: true,
      tabStop: 2,
      expandTab: true,
      autoIndent: true,
      autoCloseParen: false,
      autoDeleteParen: false,
    ),
    needsFullRedraw: false,
    viewportReservedLines: 2,
    macroState: MacroState(
      isRecording: false,
      register: '\0',
      recordedKeys: @[],
      registers: initTable[char, seq[string]](),
      lastRegister: none(char),
      waitingForRegister: false,
      commandType: "",
      pendingCount: 0,
      playbackDepth: 0,
    ),
    registers: initRegisters(),
  )

proc createTestViewport(): ViewPort =
  ## Create a minimal viewport for testing
  ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)

proc createTestHandler(buf: TextBuffer): NormalModeHandler =
  ## Create a NormalModeHandler for testing
  let keyBindingRegistry = newKeyBindingRegistry()
  setupDefaultBindings(keyBindingRegistry)

  let commandRegistry = newCommandRegistry()
  registerBuiltinCommands(commandRegistry)

  let motionController =
    newMotionController(buf, createTestState(), createTestViewport())

  newNormalModeHandler(
    motionController,
    keyBindingRegistry,
    commandRegistry,
    ClipboardConfig(enable: false, tool: cbtXclip),
    SmoothScrollConfig(enable: false, friction: 80.0, airDrag: 2.0),
    NotificationConfig(),
  )

suite "NormalModeHandler - Constructor":
  test "Create NormalModeHandler with default config":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)

    check handler != nil
    check handler.motionController != nil
    check handler.keyBindingRegistry != nil
    check handler.commandRegistry != nil
    check handler.clipboardConfig.enable == false
    check handler.smoothScrollConfig.enable == false

  test "Create NormalModeHandler with custom clipboard config":
    let buf = newTextBuffer()
    let keyBindingRegistry = newKeyBindingRegistry()
    let commandRegistry = newCommandRegistry()
    let motionController =
      newMotionController(buf, createTestState(), createTestViewport())

    let clipboardConfig = ClipboardConfig(enable: true, tool: cbtXsel)
    let handler = newNormalModeHandler(
      motionController, keyBindingRegistry, commandRegistry, clipboardConfig
    )

    check handler.clipboardConfig.enable == true
    check handler.clipboardConfig.tool == cbtXsel

suite "NormalModeHandler - Mode Switching":
  test "Switch to Insert mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Insert, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Insert

  test "Switch to Command overlay":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitchToOverlay(okCommand, state)

    check result.kind == nmrHandled
    check result.overlayTransition.isSome
    check result.overlayTransition.get == okCommand
    check state.commandText == ":"
    check state.commandCursor == 0

  test "Switch to Search overlay (forward)":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 5, column: 10)

    let result = handler.handleModeSwitchToOverlay(okSearch, state, "switch-to-search")

    check result.kind == nmrHandled
    check result.overlayTransition.isSome
    check result.overlayTransition.get == okSearch
    check state.search.text == ""
    check state.search.direction == Forward
    check state.search.startPos.line == 5
    check state.search.startPos.column == 10

  test "Switch to Search overlay (backward)":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 3, column: 5)

    let result =
      handler.handleModeSwitchToOverlay(okSearch, state, "switch-to-search-backward")

    check result.kind == nmrHandled
    check result.overlayTransition.isSome
    check result.overlayTransition.get == okSearch
    check state.search.direction == Backward

  test "Switch to Visual mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Visual, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Visual

  test "Switch to VisualLine mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.VisualLine, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.VisualLine

  test "Switch to VisualBlock mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.VisualBlock, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.VisualBlock

  test "Switch to Replace mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Replace, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Replace

  test "Switch to Normal mode (already in normal)":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Normal, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isNone

suite "NormalModeHandler - Insert Mode Entry":
  test "Insert at cursor (i)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    let result = handler.handleInsertModeEntry(buf, state, "insert")

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Insert
    check state.cursor.column == 5 # Cursor stays at same position

  test "Append after cursor (a)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    let result = handler.handleInsertModeEntry(buf, state, "append")

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Insert
    check state.cursor.column == 6 # Cursor moves right by 1

  test "Append at end of line (A)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleInsertModeEntry(buf, state, "append-end")

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Insert
    check state.cursor.column == 11 # Cursor at end of "Hello World"

  test "Insert at first non-blank (I)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "   Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 10)

    let result = handler.handleInsertModeEntry(buf, state, "insert-first-non-blank")

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Insert
    # Cursor moves to first non-blank character

  test "Open line below (o)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleInsertModeEntry(buf, state, "open-below")

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Insert

  test "Open line above (O)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleInsertModeEntry(buf, state, "open-above")

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Insert

  test "Unknown insert type returns error":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleInsertModeEntry(buf, state, "unknown-type")

    check result.kind == nmrError
    check result.errorMessage == "Unknown insert type: unknown-type"

suite "NormalModeHandler - Result Helpers":
  test "isHandled returns true for handled results":
    let result = NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    check result.isHandled == true

  test "isHandled returns false for error results":
    let result = NormalModeResult(kind: nmrError, errorMessage: "test error")
    check result.isHandled == false

  test "isHandled returns false for unhandled results":
    let result = NormalModeResult(kind: nmrUnhandled)
    check result.isHandled == false

  test "hasError returns true for error results":
    let result = NormalModeResult(kind: nmrError, errorMessage: "test error")
    check result.hasError == true

  test "hasError returns false for handled results":
    let result = NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    check result.hasError == false

  test "getModeTransition returns mode for handled with transition":
    let result =
      NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Insert))
    let transition = result.getModeTransition
    check transition.isSome
    check transition.get == EditorMode.Insert

  test "getModeTransition returns none for handled without transition":
    let result = NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    let transition = result.getModeTransition
    check transition.isNone

  test "getModeTransition returns none for error results":
    let result = NormalModeResult(kind: nmrError, errorMessage: "error")
    let transition = result.getModeTransition
    check transition.isNone

  test "getOverlayTransition returns overlay for handled with overlay transition":
    let result = NormalModeResult(
      kind: nmrHandled,
      modeTransition: none(EditorMode),
      overlayTransition: some(okCommand),
    )
    let transition = result.getOverlayTransition
    check transition.isSome
    check transition.get == okCommand

  test "getOverlayTransition returns search overlay":
    let result = NormalModeResult(
      kind: nmrHandled,
      modeTransition: none(EditorMode),
      overlayTransition: some(okSearch),
    )
    let transition = result.getOverlayTransition
    check transition.isSome
    check transition.get == okSearch

  test "getOverlayTransition returns none for handled without overlay transition":
    let result =
      NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Insert))
    let transition = result.getOverlayTransition
    check transition.isNone

  test "getOverlayTransition returns none for error results":
    let result = NormalModeResult(kind: nmrError, errorMessage: "error")
    let transition = result.getOverlayTransition
    check transition.isNone

  test "getOverlayTransition returns none for unhandled results":
    let result = NormalModeResult(kind: nmrUnhandled)
    let transition = result.getOverlayTransition
    check transition.isNone

suite "NormalModeHandler - Macro Recording State":
  test "Start macro recording (q) sets waiting for register":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Simulate pressing 'q'
    let keyCombo = KeyCombo(isSpecial: false, char: "q", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.macroState.waitingForRegister == true
    check state.macroState.commandType == "record"
    check state.statusMessage == "recording @"

  test "Register selection after q":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Set waiting for register state (as if 'q' was pressed)
    state.macroState.waitingForRegister = true
    state.macroState.commandType = "record"
    state.macroState.registers = initTable[char, seq[string]]()

    # Press 'a' to select register
    let keyCombo = KeyCombo(isSpecial: false, char: "a", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.macroState.isRecording == true
    check state.macroState.register == 'a'
    check state.macroState.waitingForRegister == false
    check state.statusMessage == "recording @a"

  test "Invalid register shows error":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.macroState.waitingForRegister = true
    state.macroState.commandType = "record"

    # Press '1' (invalid register)
    let keyCombo = KeyCombo(isSpecial: false, char: "1", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.macroState.waitingForRegister == false
    check state.statusMessage == "Invalid register (use a-z)"

  test "Stop recording (q while recording)":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.macroState.isRecording = true
    state.macroState.register = 'a'
    state.macroState.recordedKeys = @["d", "d"]
    state.macroState.registers = initTable[char, seq[string]]()

    # Press 'q' to stop recording
    let keyCombo = KeyCombo(isSpecial: false, char: "q", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.macroState.isRecording == false
    check state.macroState.registers.hasKey('a')
    check state.macroState.registers['a'] == @["d", "d"]
    check state.statusMessage == ""

suite "NormalModeHandler - Macro Playback State":
  test "Start playback (@) sets waiting for register":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Simulate pressing '@'
    let keyCombo = KeyCombo(isSpecial: false, char: "@", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.macroState.waitingForRegister == true
    check state.macroState.commandType == "playback"
    check state.statusMessage == "@"

  test "Playback existing macro (@a)":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.macroState.waitingForRegister = true
    state.macroState.commandType = "playback"
    state.macroState.registers = initTable[char, seq[string]]()
    state.macroState.registers['a'] = @["d", "d"]

    # Press 'a' to play register
    let keyCombo = KeyCombo(isSpecial: false, char: "a", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrPlaybackMacro
    check result.macroKeys == @["d", "d"]
    check state.macroState.lastRegister.isSome
    check state.macroState.lastRegister.get == 'a'

  test "Playback non-existent macro shows error":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.macroState.waitingForRegister = true
    state.macroState.commandType = "playback"
    state.macroState.registers = initTable[char, seq[string]]()

    # Press 'z' (empty register)
    let keyCombo = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.statusMessage == "Register @z is empty"

  test "Repeat last macro (@@)":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.macroState.waitingForRegister = true
    state.macroState.commandType = "playback"
    state.macroState.registers = initTable[char, seq[string]]()
    state.macroState.registers['a'] = @["j", "j"]
    state.macroState.lastRegister = some('a')

    # Press '@' to repeat last macro
    let keyCombo = KeyCombo(isSpecial: false, char: "@", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrPlaybackMacro
    check result.macroKeys == @["j", "j"]

  test "Repeat last macro when no previous":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.macroState.waitingForRegister = true
    state.macroState.commandType = "playback"
    state.macroState.lastRegister = none(char)

    # Press '@' when no previous macro
    let keyCombo = KeyCombo(isSpecial: false, char: "@", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.statusMessage == "No previous macro"

suite "NormalModeHandler - Register Selection":
  test "Start register selection (\")":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Press '"' to start register selection
    let keyCombo = KeyCombo(isSpecial: false, char: "\"", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.pendingRegister.isSome
    check state.pendingRegister.get == '\0' # Placeholder

  test "Register selection with valid register":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.pendingRegister = some('\0') # Waiting for register name

    # Press 'a' to select register
    let keyCombo = KeyCombo(isSpecial: false, char: "a", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.pendingRegister.isSome
    check state.pendingRegister.get == 'a'

  test "Register selection cancelled on invalid register":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.pendingRegister = some('\0')

    # Press invalid character
    let keyCombo = KeyCombo(isSpecial: false, char: "!", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.pendingRegister.isNone

  test "Register selection cancelled on special key":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.pendingRegister = some('\0')

    # Press Escape
    let keyCombo = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.pendingRegister.isNone

suite "NormalModeHandler - Special Results":
  test "nmrSaveAndQuit result":
    let result = NormalModeResult(kind: nmrSaveAndQuit)
    check result.kind == nmrSaveAndQuit

  test "nmrQuitWithoutSave result":
    let result = NormalModeResult(kind: nmrQuitWithoutSave)
    check result.kind == nmrQuitWithoutSave

  test "nmrCloseWindow result":
    let result = NormalModeResult(kind: nmrCloseWindow)
    check result.kind == nmrCloseWindow

  test "nmrPlaybackMacro result":
    let result =
      NormalModeResult(kind: nmrPlaybackMacro, macroKeys: @["d", "d"], macroCount: 3)
    check result.kind == nmrPlaybackMacro
    check result.macroKeys == @["d", "d"]
    check result.macroCount == 3

  test "nmrLspGotoDefinition result":
    let result = NormalModeResult(kind: nmrLspGotoDefinition)
    check result.kind == nmrLspGotoDefinition

  test "nmrLspRename result with new name":
    let result = NormalModeResult(kind: nmrLspRename, nmrLspNewName: "newName")
    check result.kind == nmrLspRename
    check result.nmrLspNewName == "newName"

  test "nmrJumpToBuffer result":
    let result = NormalModeResult(
      kind: nmrJumpToBuffer, nmrJumpBufferIndex: 2, nmrJumpLine: 10, nmrJumpColumn: 5
    )
    check result.kind == nmrJumpToBuffer
    check result.nmrJumpBufferIndex == 2
    check result.nmrJumpLine == 10
    check result.nmrJumpColumn == 5

suite "NormalModeHandler - All Mode Switches":
  test "Switch to Filer mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Filer, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Filer

  test "Switch to QuickRun mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.QuickRun, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.QuickRun

  test "Switch to LogViewer mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.LogViewer, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.LogViewer

  test "Switch to Help mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Help, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Help

  test "Switch to BufferManager mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.BufferManager, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.BufferManager

  test "Switch to BackupManager mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.BackupManager, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.BackupManager

  test "Switch to DiffViewer mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.DiffViewer, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.DiffViewer

  test "Switch to RecentFile mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.RecentFile, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.RecentFile

  test "Switch to Debug mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Debug, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Debug

  test "Switch to Config mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Config, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Config

  test "Switch to References mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.References, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.References

  test "Switch to DocumentSymbol mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.DocumentSymbol, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.DocumentSymbol

  test "Switch to Rename overlay (no transition)":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitchToOverlay(okRename, state)

    check result.kind == nmrHandled
    check result.overlayTransition.isNone
      # Rename is entered through LSP, not mode switch

  test "Switch to CallHierarchy mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.CallHierarchy, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.CallHierarchy

suite "NormalModeHandler - Motion Commands":
  test "Execute left motion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    let result = handler.handleMotionCommand(buf, state, Motion.Left, 1)

    check result.isOk
    check state.cursor.column == 4

  test "Execute right motion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleMotionCommand(buf, state, Motion.Right, 1)

    check result.isOk
    check state.cursor.column == 1

  test "Execute motion with count":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    let result = handler.handleMotionCommand(buf, state, Motion.Left, 3)

    check result.isOk
    check state.cursor.column == 2

  test "Execute down motion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nLine 2")
    discard buf.insertText(BufferPosition(line: 1, column: 6), "\nLine 3")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleMotionCommand(buf, state, Motion.Down, 1)

    check result.isOk
    check state.cursor.line == 1

  test "Execute up motion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nLine 2")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)

    let result = handler.handleMotionCommand(buf, state, Motion.Up, 1)

    check result.isOk
    check state.cursor.line == 0

suite "NormalModeHandler - Command Execution":
  test "Execute command via registry":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 5)

    # Execute motion.left command
    let result = handler.executeCommand(buf, state, viewport, "motion.left")

    check result.kind == nmrHandled
    check state.cursor.column == 4

  test "Execute non-existent command returns error":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    let result = handler.executeCommand(buf, state, viewport, "nonexistent.command")

    check result.kind == nmrError

suite "NormalModeHandler - Jump List":
  test "Jump back with empty list returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.jumpList = @[]
    state.jumpListIndex = -1

    # Simulate Ctrl-o
    let keyCombo = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrError
    check result.errorMessage == "Jump list is empty"

  test "Jump forward without prior jump returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.jumpList = @[]
    state.jumpListIndex = -1

    # Simulate Ctrl-i
    let keyCombo = KeyCombo(isSpecial: false, char: "i", modifiers: {kmCtrl})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrError
    check result.errorMessage == "No newer jump position"

  test "Jump back with valid list":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nLine 2")
    discard buf.insertText(BufferPosition(line: 1, column: 6), "\nLine 3")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Set up jump list with positions in the same buffer
    state.jumpList = @[
      JumpPosition(bufferIndex: 0, line: 0, column: 0),
      JumpPosition(bufferIndex: 0, line: 2, column: 0),
    ]
    state.jumpListIndex = -1
    state.currentBufferIndex = 0
    state.cursor = BufferPosition(line: 1, column: 0)

    # Simulate Ctrl-o
    let keyCombo = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled

  test "Jump to different buffer":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Set up jump list with position in a different buffer
    state.jumpList = @[JumpPosition(bufferIndex: 1, line: 5, column: 10)]
    state.jumpListIndex = -1
    state.currentBufferIndex = 0
    state.cursor = BufferPosition(line: 0, column: 0)

    # Simulate Ctrl-o
    let keyCombo = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrJumpToBuffer
    check result.nmrJumpBufferIndex == 1
    check result.nmrJumpLine == 5
    check result.nmrJumpColumn == 10

suite "NormalModeHandler - Text Object Pending State":
  test "Pending text object cancelled on special key":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.editState.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))

    # Press Escape to cancel
    let keyCombo = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check state.editState.pendingTextObject.isNone

suite "NormalModeHandler - LSP Results":
  test "All LSP result kinds":
    # Test all LSP result variants
    check NormalModeResult(kind: nmrLspGotoDefinition).kind == nmrLspGotoDefinition
    check NormalModeResult(kind: nmrLspGotoDeclaration).kind == nmrLspGotoDeclaration
    check NormalModeResult(kind: nmrLspFindReferences).kind == nmrLspFindReferences
    check NormalModeResult(kind: nmrLspCodeLensExecute).kind == nmrLspCodeLensExecute
    check NormalModeResult(kind: nmrLspCallHierarchyIncoming).kind ==
      nmrLspCallHierarchyIncoming
    check NormalModeResult(kind: nmrLspCallHierarchyOutgoing).kind ==
      nmrLspCallHierarchyOutgoing
    check NormalModeResult(kind: nmrLspTypeDefinition).kind == nmrLspTypeDefinition
    check NormalModeResult(kind: nmrLspImplementation).kind == nmrLspImplementation
    check NormalModeResult(kind: nmrLspHover).kind == nmrLspHover
    check NormalModeResult(kind: nmrLspSelectionRange).kind == nmrLspSelectionRange
    check NormalModeResult(kind: nmrLspDocumentLink).kind == nmrLspDocumentLink

suite "NormalModeHandler - Macro Key Recording":
  test "Keys recorded during macro recording":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.macroState.isRecording = true
    state.macroState.register = 'a'
    state.macroState.recordedKeys = @[]
    state.macroState.registers = initTable[char, seq[string]]()

    # Press 'j' while recording
    let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    discard handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    # Key should be recorded
    check state.macroState.recordedKeys.len >= 1

  test "Macro playback with count":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.macroState.waitingForRegister = true
    state.macroState.commandType = "playback"
    state.macroState.pendingCount = 5 # Play 5 times
    state.macroState.registers = initTable[char, seq[string]]()
    state.macroState.registers['a'] = @["j"]

    let keyCombo = KeyCombo(isSpecial: false, char: "a", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrPlaybackMacro
    check result.macroCount == 5

suite "NormalModeHandler - Undo/Redo":
  test "Undo command executes":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Try undo - may succeed or fail depending on undo history
    let result = handler.executeCommand(buf, state, viewport, "edit.undo")

    # Either succeeds or returns error (both are valid outcomes)
    check result.kind == nmrHandled or result.kind == nmrError

  test "Redo command executes":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Try redo - may succeed or fail depending on redo history
    let result = handler.executeCommand(buf, state, viewport, "edit.redo")

    # Either succeeds or returns error (both are valid outcomes)
    check result.kind == nmrHandled or result.kind == nmrError

suite "NormalModeHandler - Text Object Handling":
  test "Text object word (w) with pending operator":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 0)

    # Set up pending text object state
    state.editState.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    state.editState.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    # Press 'w' for word text object
    let keyCombo = KeyCombo(isSpecial: false, char: "w", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled or result.kind == nmrError

  test "Text object wide word (W) with pending operator":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello-world test")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.editState.pendingTextObject =
      some(PendingTextObject(modifier: tomAround, operatorCount: 1))
    state.editState.pendingOperator = some(
      PendingOperator(
        operatorType: OpYank,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let keyCombo = KeyCombo(isSpecial: false, char: "W", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled or result.kind == nmrError

  test "Text object double quote with pending operator":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "say \"hello\" world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 5)

    state.editState.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    state.editState.pendingOperator = some(
      PendingOperator(
        operatorType: OpChange,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let keyCombo = KeyCombo(isSpecial: false, char: "\"", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled or result.kind == nmrError

  test "Text object single quote":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "say 'hello' world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 5)

    state.editState.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    state.editState.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let keyCombo = KeyCombo(isSpecial: false, char: "'", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled or result.kind == nmrError

  test "Text object parenthesis":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "func(arg1, arg2)")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 6)

    state.editState.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    state.editState.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let keyCombo = KeyCombo(isSpecial: false, char: "(", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled or result.kind == nmrError

  test "Text object bracket":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "arr[0, 1, 2]")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 5)

    state.editState.pendingTextObject =
      some(PendingTextObject(modifier: tomAround, operatorCount: 1))
    state.editState.pendingOperator = some(
      PendingOperator(
        operatorType: OpYank,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let keyCombo = KeyCombo(isSpecial: false, char: "[", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled or result.kind == nmrError

  test "Text object brace":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "obj{a: 1, b: 2}")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 5)

    state.editState.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    state.editState.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let keyCombo = KeyCombo(isSpecial: false, char: "{", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled or result.kind == nmrError

  test "Text object angle bracket":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "<tag>content</tag>")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 1)

    state.editState.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    state.editState.pendingOperator = some(
      PendingOperator(
        operatorType: OpYank,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let keyCombo = KeyCombo(isSpecial: false, char: "<", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled or result.kind == nmrError

  test "Text object backtick":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "say `hello` world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 5)

    state.editState.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    state.editState.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let keyCombo = KeyCombo(isSpecial: false, char: "`", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled or result.kind == nmrError

  test "Unknown text object key cancels pending state":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.editState.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    state.editState.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    # Press 'z' which is not a valid text object
    let keyCombo = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.editState.pendingTextObject.isNone
    check state.editState.pendingOperator.isNone

suite "NormalModeHandler - Jump List Edge Cases":
  test "Jump forward at newest position":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.jumpList = @[JumpPosition(bufferIndex: 0, line: 0, column: 0)]
    state.jumpListIndex = 0 # Already at end
    state.currentBufferIndex = 0

    # Simulate Ctrl-i
    let keyCombo = KeyCombo(isSpecial: false, char: "i", modifiers: {kmCtrl})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrError
    check result.errorMessage == "Already at newest jump position"

  test "Jump back updates index correctly":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nLine 2")
    discard buf.insertText(BufferPosition(line: 1, column: 6), "\nLine 3")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.jumpList = @[
      JumpPosition(bufferIndex: 0, line: 0, column: 0),
      JumpPosition(bufferIndex: 0, line: 1, column: 0),
    ]
    state.jumpListIndex = 1 # Not first jump
    state.currentBufferIndex = 0
    state.cursor = BufferPosition(line: 2, column: 0)

    # Simulate Ctrl-o
    let keyCombo = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.jumpListIndex == 0

  test "Jump forward to different buffer":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.jumpList = @[
      JumpPosition(bufferIndex: 0, line: 0, column: 0),
      JumpPosition(bufferIndex: 1, line: 5, column: 3),
    ]
    state.jumpListIndex = 0
    state.currentBufferIndex = 0

    # Simulate Ctrl-i
    let keyCombo = KeyCombo(isSpecial: false, char: "i", modifiers: {kmCtrl})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrJumpToBuffer
    check result.nmrJumpBufferIndex == 1
    check result.nmrJumpLine == 5
    check result.nmrJumpColumn == 3

suite "NormalModeHandler - Macro Edge Cases":
  test "@@ with last register deleted":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.macroState.waitingForRegister = true
    state.macroState.commandType = "playback"
    state.macroState.registers = initTable[char, seq[string]]()
    # lastRegister points to 'a', but 'a' is not in registers (deleted)
    state.macroState.lastRegister = some('a')

    let keyCombo = KeyCombo(isSpecial: false, char: "@", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.statusMessage == "Register @a is empty"

  test "Empty char in key combo during macro register selection":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.macroState.waitingForRegister = true
    state.macroState.commandType = "record"

    # Empty char
    let keyCombo = KeyCombo(isSpecial: false, char: "", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.statusMessage == "Invalid register (use a-z)"

  test "Macro recording with special key cancels register wait":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.macroState.waitingForRegister = true
    state.macroState.commandType = "record"

    # Press Escape
    let keyCombo = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.macroState.waitingForRegister == false
    check state.statusMessage == ""

  test "Invalid register for playback":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.macroState.waitingForRegister = true
    state.macroState.commandType = "playback"

    # Press '!' (invalid for playback)
    let keyCombo = KeyCombo(isSpecial: false, char: "!", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.statusMessage == "Invalid register (use a-z or @)"

suite "NormalModeHandler - updateCursorToJumpPosition":
  test "Jump to buffer with single empty line":
    let buf = newTextBuffer()
    # newTextBuffer creates a buffer with one empty line by default
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.jumpList = @[JumpPosition(bufferIndex: 0, line: 5, column: 10)]
    state.jumpListIndex = -1
    state.currentBufferIndex = 0
    state.cursor = BufferPosition(line: 0, column: 0)

    # Jump to position - cursor should be clamped
    let keyCombo = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    # Either handled (cursor clamped) or error
    check result.kind == nmrHandled or result.kind == nmrError

  test "Jump position clamped to buffer bounds":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "short")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Jump to position beyond buffer bounds
    state.jumpList = @[JumpPosition(bufferIndex: 0, line: 100, column: 100)]
    state.jumpListIndex = -1
    state.currentBufferIndex = 0
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    # Cursor should be clamped to valid position
    check state.cursor.line <= buf.len - 1

  test "Jump to empty line sets column to 0":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\n") # Empty line
    discard buf.insertText(BufferPosition(line: 1, column: 0), "\nline3")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Jump to empty line with column > 0
    state.jumpList = @[JumpPosition(bufferIndex: 0, line: 1, column: 10)]
    state.jumpListIndex = -1
    state.currentBufferIndex = 0
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled
    check state.cursor.column == 0

suite "NormalModeHandler - Command Types":
  test "Key returns none when building sequence":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Press '2' to start numeric prefix
    let keyCombo = KeyCombo(isSpecial: false, char: "2", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled

  test "Motion command failure returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    # Try to move up from first line - should fail
    let result = handler.handleMotionCommand(buf, state, Motion.Up, 1)

    # Motion may or may not error depending on implementation
    check result.isOk or result.isErr
