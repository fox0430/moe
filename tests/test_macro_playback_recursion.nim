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

## Tests for `playbackMacro` (handler_manager.nim) around outer built-in
## sequence-FSM state preservation and nested `@X` recursion.
##
## The pre/post `clearBuiltinSequence` calls that used to bracket the
## iteration were removed because they wiped legitimate outer state on the
## runtime `:map` expansion path (a `numericPrefix` typed before the trigger
## disappeared) without adding safety to the `@X` path (where dispatch had
## already cleared the FSM). These tests lock the new invariant down.

import std/[unittest, tables, options]

import
  ../src/moepkg/[
    key_router, modes, buffer, motion, command_registry, registers, key_bindings, types
  ]
import
  ../src/moepkg/command_handlers/[
    handler_manager, result_processor, normal_handler, visual_handler, insert_handler,
    replace_handler,
  ]
from ../src/moepkg/types/editor_types import Editor

import editor_test_helper

proc newTestState(mode = EditorMode.Normal): EditorState =
  EditorState(
    activeWindow: EditorWindow(
      cursor: BufferPosition(line: 0, column: 0),
      mode: mode,
      previousMode: EditorMode.Normal,
    ),
    pendingInput: PendingInputState(
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
      )
    ),
    registers: initRegisters(),
  )

proc newTestViewport(): ViewPort =
  ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80)

proc newTestManager(): HandlerManager =
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

  let insertHandler =
    newInsertModeHandler(keyBindingRegistry, motionController, commandRegistry)

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

suite "playbackMacro - outer FSM state preservation":
  test "outer numericPrefix survives an empty playbackMacro invocation":
    ## Directly asserts the removed L474 entry-clear. An outer `2` parked in
    ## `numericPrefix` (as it would be during `:map` runtime expansion after
    ## a count key) must not be wiped by entering `playbackMacro`.
    let manager = newTestManager()
    let buffer = newTextBuffer()
    let state = newTestState()
    let viewport = newTestViewport()
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    manager.keyBindingRegistry.sequenceState.numericPrefix = "2"
    check manager.keyBindingRegistry.hasActiveSequence()

    discard playbackMacro(editor, @[])

    check manager.keyBindingRegistry.sequenceState.numericPrefix == "2"
    check manager.keyBindingRegistry.hasActiveSequence()

  test "tail waitingForChar survives so a follow-up key applies as operand":
    ## Directly asserts the removed L498 exit-clear. A macro ending on an
    ## operand-taking key (`f`/`t`/`r`) should leave the FSM in
    ## `waitingForChar`; the next user keystroke then completes the operator
    ## rather than being interpreted as a fresh command.
    let manager = newTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "abcdef")
    let state = newTestState()
    let viewport = newTestViewport()
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    discard playbackMacro(editor, @["f"])

    check manager.keyBindingRegistry.isWaitingForChar()
    check manager.keyBindingRegistry.hasActiveSequence()

  test "playbackMacro does not touch an unrelated pending sequence prefix":
    ## Extra belt-and-suspenders: pre-seed `keys` (a partial sequence being
    ## built) plus a `numericPrefix`, run an empty playbackMacro, both
    ## should survive verbatim.
    let manager = newTestManager()
    let buffer = newTextBuffer()
    let state = newTestState()
    let viewport = newTestViewport()
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    let gKey = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    manager.keyBindingRegistry.sequenceState.keys = @[gKey]
    manager.keyBindingRegistry.sequenceState.numericPrefix = "3"

    discard playbackMacro(editor, @[])

    check manager.keyBindingRegistry.sequenceState.keys == @[gKey]
    check manager.keyBindingRegistry.sequenceState.numericPrefix == "3"

suite "playbackMacro - runtime `:noremap` mid-count invariants":
  test "count typed before a mapping trigger reaches the RHS unclobbered":
    ## Regression for the concrete bug the L474 removal fixes: with
    ## `:noremap j @a` and register `a` defined, typing `2j` used to
    ## silently drop the `2` because the mapping fired via
    ## `replayRuntimeKeySequence`→`playbackMacro`, and the entry-clear
    ## wiped `numericPrefix` before `a`'s `waitingForChar` completion could
    ## consume it via `applyCountToCommand`.
    ##
    ## Post-fix: `applyCountToCommand` sees the outer count when `a`
    ## completes `@a`, so the mapping's RHS runs with count=2. Because the
    ## registered macro body is empty, the count observation is indirect —
    ## we check that `numericPrefix` is consumed (to `""`) rather than
    ## discarded silently at entry, and that the inner `@a` dispatch fired
    ## (visible via `lastRegister`).
    let manager = newTestManager()
    let buffer = newTextBuffer()
    let state = newTestState()
    let viewport = newTestViewport()
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    state.pendingInput.macroState.registers['a'] = @[]

    let err =
      manager.keyBindingRegistry.addRuntimeMapping(Normal, "j", "@ a", noremap = true)
    check err == ""

    let two = KeyCombo(isSpecial: false, char: "2", modifiers: {})
    let j = KeyCombo(isSpecial: false, char: "j", modifiers: {})

    discard manager.runKeyCombo(editor, two)
    check manager.keyBindingRegistry.sequenceState.numericPrefix == "2"

    discard manager.runKeyCombo(editor, j)

    # `a` completing `@a` inside the noremap replay consumed the outer `2`
    # via applyCountToCommand — numericPrefix is now empty (not because the
    # entry-clear ran, but because the count was legitimately used).
    check manager.keyBindingRegistry.sequenceState.numericPrefix == ""
    check state.pendingInput.macroState.lastRegister == some('a')
    check state.pendingInput.macroState.playbackDepth == 0
    check not manager.keyBindingRegistry.hasActiveSequence()

suite "playbackMacro - depth and recursion guards":
  test "playbackDepth returns to 0 after successful playback":
    let manager = newTestManager()
    let buffer = newTextBuffer()
    let state = newTestState()
    let viewport = newTestViewport()
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    check state.pendingInput.macroState.playbackDepth == 0
    discard playbackMacro(editor, @[])
    check state.pendingInput.macroState.playbackDepth == 0

  test "playbackDepth returns to 0 after an invalid-key error":
    let manager = newTestManager()
    let buffer = newTextBuffer()
    let state = newTestState()
    let viewport = newTestViewport()
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    let r = playbackMacro(editor, @["<not-a-real-key>"])
    check r.kind == hrError
    check state.pendingInput.macroState.playbackDepth == 0

  test "MaxMacroRecursionDepth guard refuses playback at the limit":
    let manager = newTestManager()
    let buffer = newTextBuffer()
    let state = newTestState()
    let viewport = newTestViewport()
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    # MaxMacroRecursionDepth = 100.
    state.pendingInput.macroState.playbackDepth = 100
    let r = playbackMacro(editor, @[])
    check r.kind == hrError
    # Guard rejects without touching the counter — caller retains its depth.
    check state.pendingInput.macroState.playbackDepth == 100

suite "playbackMacro - nested `@X` recursion":
  test "nested @a inside @b sets lastRegister to the inner register":
    ## Regression protection for the pure @-in-macro path. When `@b`'s body
    ## contains `@a`, the inner @a dispatch overwrites `lastRegister` set by
    ## the outer @b. Confirms the recursive `playbackMacro` invocation
    ## actually reached the inner register.
    let manager = newTestManager()
    let buffer = newTextBuffer()
    let state = newTestState()
    let viewport = newTestViewport()
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    # qa = empty (dispatches macro-play, sets lastRegister, no side effects).
    # qb = @a (recorded as the two keystrokes `@`, `a`).
    state.pendingInput.macroState.registers['a'] = @[]
    state.pendingInput.macroState.registers['b'] = @["@", "a"]

    let at = KeyCombo(isSpecial: false, char: "@", modifiers: {})
    let b = KeyCombo(isSpecial: false, char: "b", modifiers: {})
    discard manager.runKeyCombo(editor, at)
    discard manager.runKeyCombo(editor, b)

    # Outer @b sets lastRegister='b', inner @a overwrites it to 'a'.
    check state.pendingInput.macroState.lastRegister == some('a')
    check state.pendingInput.macroState.playbackDepth == 0
    check not manager.keyBindingRegistry.hasActiveSequence()

  test "`2@b` consumes the count via `@b`'s completion before recursing":
    ## The `@X` completion path threads count via `applyCountToCommand`
    ## *before* emitting `nmrPlaybackMacro`, so the outer FSM is already
    ## clean when the recursive `playbackMacro` enters. This test also
    ## survives the removed entry-clear because it was a no-op on this
    ## code path.
    let manager = newTestManager()
    let buffer = newTextBuffer()
    let state = newTestState()
    let viewport = newTestViewport()
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    state.pendingInput.macroState.registers['a'] = @[]
    state.pendingInput.macroState.registers['b'] = @["@", "a"]

    let two = KeyCombo(isSpecial: false, char: "2", modifiers: {})
    let at = KeyCombo(isSpecial: false, char: "@", modifiers: {})
    let b = KeyCombo(isSpecial: false, char: "b", modifiers: {})
    discard manager.runKeyCombo(editor, two)
    check manager.keyBindingRegistry.sequenceState.numericPrefix == "2"

    discard manager.runKeyCombo(editor, at)
    discard manager.runKeyCombo(editor, b)

    check manager.keyBindingRegistry.sequenceState.numericPrefix == ""
    check not manager.keyBindingRegistry.hasActiveSequence()
    check state.pendingInput.macroState.playbackDepth == 0
    check state.pendingInput.macroState.lastRegister == some('a')

suite "playbackMacro - insert-normal (Ctrl-O) return-to-Insert":
  test "empty macro in insert-normal returns to Insert mode":
    # Regression: Ctrl-O followed by @a where `a` is empty must fold the
    # temporary Normal-mode step back into Insert, matching the pre-refactor
    # behaviour where playbackMacro ran inline inside handleNormalMode.
    let manager = newTestManager()
    let buffer = newTextBuffer()
    let state = newTestState(EditorMode.Normal)
    state.insertNormalMode = true
    let viewport = newTestViewport()
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    state.pendingInput.macroState.registers['a'] = @[]

    let at = KeyCombo(isSpecial: false, char: "@", modifiers: {})
    let a = KeyCombo(isSpecial: false, char: "a", modifiers: {})
    discard manager.runKeyCombo(editor, at)
    discard manager.runKeyCombo(editor, a)

    check state.mode == EditorMode.Insert
    check not state.insertNormalMode

  test "pending-operand macro key leaves insert-normal intact":
    # A macro whose only key parks the FSM in waiting-for-operand (`f`
    # awaiting a char) is a legitimate mid-command state — insert-normal
    # must not be finalized until the operand actually arrives.
    let manager = newTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "abcdef")
    let state = newTestState(EditorMode.Normal)
    state.insertNormalMode = true
    let viewport = newTestViewport()
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    state.pendingInput.macroState.registers['a'] = @["f"]

    let at = KeyCombo(isSpecial: false, char: "@", modifiers: {})
    let a = KeyCombo(isSpecial: false, char: "a", modifiers: {})
    discard manager.runKeyCombo(editor, at)
    discard manager.runKeyCombo(editor, a)

    check state.mode == EditorMode.Normal
    check state.insertNormalMode
    check manager.keyBindingRegistry.isWaitingForChar()
