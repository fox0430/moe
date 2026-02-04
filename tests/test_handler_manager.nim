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

## Tests for handler_manager.nim
## This module tests the unified handler manager functionality.

import std/[unittest, options]

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/key_bindings {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/motion {.all.}
import ../src/moepkg/command_registry {.all.}
import ../src/moepkg/registers {.all.}
import ../src/moepkg/command_handlers/handler_manager {.all.}

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
  result = EditorState(
    cursor: BufferPosition(line: 0, column: 0),
    mode: EditorMode.Normal,
    previousMode: EditorMode.Normal,
  )
  result.registers = initRegisters()

proc createTestViewport(): ViewPort =
  ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80)

proc createTestManager(): HandlerManager =
  ## Create a HandlerManager for testing
  let keyBindingRegistry = newKeyBindingRegistry()
  keyBindingRegistry.setupDefaultBindings()

  let commandRegistry = newCommandRegistry()
  commandRegistry.registerBuiltinCommands()

  let motionController = MotionController()

  let normalHandler = NormalModeHandler(
    keyBindingRegistry: keyBindingRegistry,
    commandRegistry: commandRegistry,
    motionController: motionController,
  )

  let insertHandler = InsertModeHandler(keyBindingRegistry: keyBindingRegistry)

  let visualHandler = VisualModeHandler(
    keyBindingRegistry: keyBindingRegistry,
    commandRegistry: commandRegistry,
    motionController: motionController,
  )

  let replaceHandler = ReplaceModeHandler(keyBindingRegistry: keyBindingRegistry)

  HandlerManager(
    keyBindingRegistry: keyBindingRegistry,
    commandRegistry: commandRegistry,
    motionController: motionController,
    normalHandler: normalHandler,
    insertHandler: insertHandler,
    visualHandler: visualHandler,
    replaceHandler: replaceHandler,
  )

suite "HandlerManager - Overlay Transitions":
  test "Colon key returns overlayTransition for command overlay":
    ## This test ensures that pressing ':' in Normal mode returns
    ## an overlayTransition to okCommand, not just a modeTransition.
    ## This was a bug where overlayTransition was not propagated.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    let state = createTestState()
    let viewport = createTestViewport()

    # Create ':' key combo
    let keyCombo = KeyCombo(isSpecial: false, char: ":", modifiers: {})

    let result = manager.handleNormalMode(buffer, state, viewport, keyCombo)

    check result.kind == hrHandled
    check result.overlayTransition.isSome
    check result.overlayTransition.get == okCommand

  test "Forward slash key returns overlayTransition for search overlay":
    ## This test ensures that pressing '/' in Normal mode returns
    ## an overlayTransition to okSearch.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    let state = createTestState()
    let viewport = createTestViewport()

    # Create '/' key combo
    let keyCombo = KeyCombo(isSpecial: false, char: "/", modifiers: {})

    let result = manager.handleNormalMode(buffer, state, viewport, keyCombo)

    check result.kind == hrHandled
    check result.overlayTransition.isSome
    check result.overlayTransition.get == okSearch

  test "Question mark key returns overlayTransition for backward search overlay":
    ## This test ensures that pressing '?' in Normal mode returns
    ## an overlayTransition to okSearch (backward direction).
    let manager = createTestManager()
    let buffer = newTextBuffer()
    let state = createTestState()
    let viewport = createTestViewport()

    # Create '?' key combo
    let keyCombo = KeyCombo(isSpecial: false, char: "?", modifiers: {})

    let result = manager.handleNormalMode(buffer, state, viewport, keyCombo)

    check result.kind == hrHandled
    check result.overlayTransition.isSome
    check result.overlayTransition.get == okSearch

suite "HandlerManager - getOverlayTransition helper":
  test "getOverlayTransition returns overlay from hrHandled result":
    let result = HandlerResult(
      kind: hrHandled,
      modeTransition: none(EditorMode),
      overlayTransition: some(okCommand),
      statusMessage: "",
    )
    let transition = result.getOverlayTransition
    check transition.isSome
    check transition.get == okCommand

  test "getOverlayTransition returns none for hrHandled without overlay":
    let result = HandlerResult(
      kind: hrHandled,
      modeTransition: some(EditorMode.Insert),
      overlayTransition: none(OverlayKind),
      statusMessage: "",
    )
    let transition = result.getOverlayTransition
    check transition.isNone

  test "getOverlayTransition returns none for non-hrHandled results":
    let result = HandlerResult(kind: hrUnhandled)
    let transition = result.getOverlayTransition
    check transition.isNone

  test "getOverlayTransition returns none for hrQuit":
    let result = HandlerResult(kind: hrQuit, shouldQuit: true)
    let transition = result.getOverlayTransition
    check transition.isNone

  test "getOverlayTransition returns none for hrError":
    let result = HandlerResult(kind: hrError, errorMessage: "test error")
    let transition = result.getOverlayTransition
    check transition.isNone
