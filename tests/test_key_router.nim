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

## Tests for KeyRouter (`src/moepkg/key_router.nim`).
##
## Phase 3 scope: feedKey/flushTimeout for runtime-mapping decisions. Built-in
## command resolution is still owned by mode-specific dispatchers via
## `KeyBindingRegistry.processKey` and is covered by `test_key_bindings.nim`.

import std/[unittest, options]

import ../src/moepkg/key_bindings {.all.}
import ../src/moepkg/key_router {.all.}
import ../src/moepkg/modes
import ../src/moepkg/types

proc newRouter(): KeyRouter =
  let reg = newKeyBindingRegistry()
  newKeyRouter(reg, TimeoutPolicy(timeoutlen: 100, enabled: true))

proc addKeySeqMapping(reg: KeyBindingRegistry, mode: EditorMode, lhs, rhs: string) =
  ## Register a runtime key-sequence mapping (lhs → rhs key string).
  discard reg.addRuntimeMapping(mode, lhs, rhs)

suite "KeyRouter - feedKey runtime key-sequence mapping":
  test "single-key trigger fires immediately (rrExecuteRuntimeKeySequence)":
    let router = newRouter()
    router.registry.addKeySeqMapping(EditorMode.Insert, "j", "Escape")

    let route = router.feedKey(EditorMode.Insert, toKeyCombo('j'))

    check route.kind == rrExecuteRuntimeKeySequence
    check route.targetKeys == @["<Escape>"]
    check router.hasRuntimeMappingPending() == false

  test "multi-key prefix waits, then fires on exact match":
    let router = newRouter()
    router.registry.addKeySeqMapping(EditorMode.Insert, "jj", "Escape")

    let first = router.feedKey(EditorMode.Insert, toKeyCombo('j'))
    check first.kind == rrWaiting
    check first.waitsForTimeout == true
    check router.hasRuntimeMappingPending() == true

    let second = router.feedKey(EditorMode.Insert, toKeyCombo('j'))
    check second.kind == rrExecuteRuntimeKeySequence
    check second.targetKeys == @["<Escape>"]
    check router.hasRuntimeMappingPending() == false

  test "non-prefix key in middle of sequence flushes accumulator":
    let router = newRouter()
    router.registry.addKeySeqMapping(EditorMode.Insert, "jj", "Escape")

    discard router.feedKey(EditorMode.Insert, toKeyCombo('j')) # rrWaiting
    let route = router.feedKey(EditorMode.Insert, toKeyCombo('k'))

    check route.kind == rrUnhandledBatch
    check route.keys.len == 2
    check route.keys[0] == toKeyCombo('j')
    check route.keys[1] == toKeyCombo('k')
    check router.hasRuntimeMappingPending() == false

  test "key with no mapping passes through (rrUnhandled)":
    let router = newRouter()
    # No mappings at all
    let route = router.feedKey(EditorMode.Insert, toKeyCombo('x'))
    check route.kind == rrUnhandled
    check route.key == toKeyCombo('x')

  test "single key matching no mapping after empty accumulator passes through":
    let router = newRouter()
    router.registry.addKeySeqMapping(EditorMode.Insert, "jj", "Escape")
    # 'x' is not a prefix of "jj" so it passes through with accumulator len==1
    let route = router.feedKey(EditorMode.Insert, toKeyCombo('x'))
    check route.kind == rrUnhandled
    check router.hasRuntimeMappingPending() == false

suite "KeyRouter - feedKey mode separation":
  test "Insert mode mapping does not fire in Normal mode":
    let router = newRouter()
    router.registry.addKeySeqMapping(EditorMode.Insert, "jj", "Escape")

    let route = router.feedKey(EditorMode.Normal, toKeyCombo('j'))
    check route.kind == rrUnhandled # no Insert mapping reaches Normal

  test "different mappings per mode resolve independently":
    let router = newRouter()
    router.registry.addKeySeqMapping(EditorMode.Insert, "jj", "Escape")
    router.registry.addKeySeqMapping(EditorMode.Normal, "kk", "i")

    let r1 = router.feedKey(EditorMode.Normal, toKeyCombo('k'))
    check r1.kind == rrWaiting
    let r2 = router.feedKey(EditorMode.Normal, toKeyCombo('k'))
    check r2.kind == rrExecuteRuntimeKeySequence
    check r2.targetKeys == @["i"]

suite "KeyRouter - flushTimeout":
  test "empty accumulator returns rrCancelled":
    let router = newRouter()
    let route = router.flushTimeout(EditorMode.Insert)
    check route.kind == rrCancelled

  test "exact match fires the mapping":
    let router = newRouter()
    router.registry.addKeySeqMapping(EditorMode.Insert, "jj", "Escape")
    discard router.feedKey(EditorMode.Insert, toKeyCombo('j')) # rrWaiting

    # Manually accumulate the second 'j' so timeout finds an exact match
    router.registry.runtimeMappingState.keys.add(toKeyCombo('j'))

    let route = router.flushTimeout(EditorMode.Insert)
    check route.kind == rrExecuteRuntimeKeySequence
    check route.targetKeys == @["<Escape>"]
    check router.hasRuntimeMappingPending() == false

  test "no exact match returns rrUnhandledBatch":
    let router = newRouter()
    router.registry.addKeySeqMapping(EditorMode.Insert, "jjk", "Escape")
    discard router.feedKey(EditorMode.Insert, toKeyCombo('j')) # rrWaiting

    let route = router.flushTimeout(EditorMode.Insert)
    check route.kind == rrUnhandledBatch
    check route.keys == @[toKeyCombo('j')]
    check router.hasRuntimeMappingPending() == false

suite "KeyRouter - cancel and accessors":
  test "cancel clears the built-in sequence accumulator":
    let router = newRouter()
    router.registry.sequenceState.keys = @[toKeyCombo('g')]
    check router.hasActiveBuiltinSequence() == true

    let cleared = router.cancel()
    check cleared == true
    check router.hasActiveBuiltinSequence() == false

  test "cancel returns false when nothing was pending":
    let router = newRouter()
    let cleared = router.cancel()
    check cleared == false

  test "nextTimeoutMs returns 0 when no mapping prefix pending":
    let router = newRouter()
    check router.nextTimeoutMs() == 0

  test "nextTimeoutMs returns timeoutlen while runtime mapping prefix pending":
    let router = newRouter()
    router.registry.addKeySeqMapping(EditorMode.Insert, "jj", "Escape")
    discard router.feedKey(EditorMode.Insert, toKeyCombo('j'))

    check router.nextTimeoutMs() == 100

  test "nextTimeoutMs returns 0 when policy disabled":
    let router = newRouter()
    router.updatePolicy(TimeoutPolicy(timeoutlen: 100, enabled: false))
    router.registry.addKeySeqMapping(EditorMode.Insert, "jj", "Escape")
    discard router.feedKey(EditorMode.Insert, toKeyCombo('j'))

    check router.nextTimeoutMs() == 0

  test "updatePolicy changes the timeoutlen reflected by nextTimeoutMs":
    let router = newRouter() # initial timeoutlen: 100
    router.registry.addKeySeqMapping(EditorMode.Insert, "jj", "Escape")
    discard router.feedKey(EditorMode.Insert, toKeyCombo('j'))

    check router.nextTimeoutMs() == 100
    router.updatePolicy(TimeoutPolicy(timeoutlen: 500, enabled: true))
    check router.nextTimeoutMs() == 500

proc registerRmkCommand(
    reg: KeyBindingRegistry, mode: EditorMode, lhs, rhs, commandId: string
) =
  ## Register a no-op `Command` and a runtime rmkCommand mapping `lhs -> rhs`.
  let cmd =
    Command(name: rhs, description: "", count: 1, kind: ctAction, commandId: commandId)
  reg.registerCommand(cmd)
  discard reg.addRuntimeMapping(mode, lhs, rhs)

suite "KeyRouter - rmkCommand routing":
  test "feedKey single-key rmkCommand fires immediately in Filer mode":
    let router = newRouter()
    router.registry.registerRmkCommand(
      EditorMode.Filer, "C-j", "window-prev", "window.prev"
    )

    let r = router.feedKey(EditorMode.Filer, toKeyCombo('j', ctrl = true))
    check r.kind == rrExecuteRuntimeCommand
    check r.commandName == "window-prev"

  test "feedKey multi-key rmkCommand waits then fires on exact match":
    let router = newRouter()
    router.registry.registerRmkCommand(
      EditorMode.Filer, "g d", "go-to-definition", "lsp.goto-definition"
    )

    let waiting = router.feedKey(EditorMode.Filer, toKeyCombo('g'))
    check waiting.kind == rrWaiting

    let fired = router.feedKey(EditorMode.Filer, toKeyCombo('d'))
    check fired.kind == rrExecuteRuntimeCommand
    check fired.commandName == "go-to-definition"

  test "flushTimeout fires exact-match rmkCommand (prefix becomes exact)":
    let router = newRouter()
    # Two mappings: "g" alone is a prefix of "g d"; flushing at "g" matches it.
    router.registry.registerRmkCommand(
      EditorMode.Filer, "g", "go-back", "navigate.back"
    )
    router.registry.registerRmkCommand(
      EditorMode.Filer, "g d", "go-to-definition", "lsp.goto-definition"
    )
    let waiting = router.feedKey(EditorMode.Filer, toKeyCombo('g'))
    check waiting.kind == rrWaiting

    let r = router.flushTimeout(EditorMode.Filer)
    check r.kind == rrExecuteRuntimeCommand
    check r.commandName == "go-back"

  test "rmkCommand in Normal mode is invisible to KeyRouter (file-edit mode)":
    # File-edit modes use getRuntimeKeySeqMappings, which filters out
    # rmkCommand. The command is reached via the normal findBinding path,
    # so the router reports rrUnhandled here.
    let router = newRouter()
    router.registry.registerRmkCommand(
      EditorMode.Normal, "C-j", "window-prev", "window.prev"
    )

    let r = router.feedKey(EditorMode.Normal, toKeyCombo('j', ctrl = true))
    check r.kind == rrUnhandled

  test "rmkCommand in Command overlay is invisible to KeyRouter":
    let router = newRouter()
    router.registry.registerRmkCommand(
      EditorMode.Command, "C-j", "window-prev", "window.prev"
    )

    let r = router.feedKey(EditorMode.Command, toKeyCombo('j', ctrl = true))
    check r.kind == rrUnhandled

suite "KeyRouter - withReplay and flushPendingAccumulator":
  test "withReplay sets and clears isReplayingMapping":
    let router = newRouter()
    check router.registry.isReplayingMapping == false
    router.withReplay:
      check router.registry.isReplayingMapping == true
    check router.registry.isReplayingMapping == false

  test "withReplay restores the flag even when the body raises":
    let router = newRouter()
    var raised = false
    try:
      router.withReplay:
        check router.registry.isReplayingMapping == true
        raise newException(ValueError, "boom")
    except ValueError:
      raised = true
    check raised == true
    check router.registry.isReplayingMapping == false

  test "flushPendingAccumulator returns @[] when mappings table is non-empty":
    let router = newRouter()
    router.registry.addKeySeqMapping(EditorMode.Insert, "jj", "Escape")
    discard router.feedKey(EditorMode.Insert, toKeyCombo('j'))
    # Accumulator now holds one key, mappings table is non-empty.
    let drained = router.flushPendingAccumulator(EditorMode.Insert)
    check drained.len == 0
    check router.registry.runtimeMappingState.keys.len == 1 # untouched

  test "flushPendingAccumulator drains accumulator when mappings table is empty":
    let router = newRouter()
    # Seed leftover keys directly without registering any mappings.
    router.registry.runtimeMappingState.keys = @[toKeyCombo('j'), toKeyCombo('k')]
    let drained = router.flushPendingAccumulator(EditorMode.Command)
    check drained.len == 2
    check drained[0] == toKeyCombo('j')
    check drained[1] == toKeyCombo('k')
    check router.registry.runtimeMappingState.keys.len == 0

  test "flushPendingAccumulator returns @[] on empty accumulator":
    let router = newRouter()
    check router.flushPendingAccumulator(EditorMode.Command).len == 0

proc newBuiltinRegistry(): KeyBindingRegistry =
  ## Registry seeded with a few Normal-mode built-in bindings so resolveBuiltin
  ## can be exercised: 'j' (single binding), 'gg' (sequence), 'f' (operand wait).
  result = newKeyBindingRegistry()

  let down =
    Command(name: "move-down", description: "", kind: ctMotion, motion: Motion.Down)
  result.registerCommand(down)
  result.bindKey(EditorMode.Normal, toKeyCombo('j'), down)

  let gotoStart = Command(
    name: "goto-start", description: "", kind: ctMotion, motion: Motion.FirstLine
  )
  result.registerCommand(gotoStart)
  result.bindSequence(EditorMode.Normal, @[toKeyCombo('g'), toKeyCombo('g')], gotoStart)

  let findChar = Command(
    name: "find-char",
    description: "",
    kind: ctOperatorPending,
    operatorType: "find",
    reverse: false,
    targetChar: "",
  )
  result.registerCommand(findChar)
  result.bindKey(EditorMode.Normal, toKeyCombo('f'), findChar)

suite "KeyRouter - resolveBuiltin":
  test "single-key binding resolves to rrCommand":
    let reg = newBuiltinRegistry()
    let route = reg.resolveBuiltin(EditorMode.Normal, toKeyCombo('j'))
    check route.kind == rrCommand
    check route.command.name == "move-down"

  test "two-key sequence waits (no timeout) then resolves":
    let reg = newBuiltinRegistry()
    let first = reg.resolveBuiltin(EditorMode.Normal, toKeyCombo('g'))
    check first.kind == rrWaiting
    # Built-in sequences never time out (Vim spec), unlike runtime mappings.
    check first.waitsForTimeout == false

    let second = reg.resolveBuiltin(EditorMode.Normal, toKeyCombo('g'))
    check second.kind == rrCommand
    check second.command.name == "goto-start"

  test "numeric prefix is carried into the resolved command's count":
    let reg = newBuiltinRegistry()
    check reg.resolveBuiltin(EditorMode.Normal, toKeyCombo('2')).kind == rrWaiting
    check reg.resolveBuiltin(EditorMode.Normal, toKeyCombo('3')).kind == rrWaiting
    let route = reg.resolveBuiltin(EditorMode.Normal, toKeyCombo('j'))
    check route.kind == rrCommand
    check route.command.count == 23

  test "operator-pending waits then resolves with the operand char":
    let reg = newBuiltinRegistry()
    let waiting = reg.resolveBuiltin(EditorMode.Normal, toKeyCombo('f'))
    check waiting.kind == rrWaiting
    check waiting.waitsForTimeout == false

    let fired = reg.resolveBuiltin(EditorMode.Normal, toKeyCombo('x'))
    check fired.kind == rrCommand
    check fired.command.targetChar == "x"

  test "Escape on an active sequence resolves to rrCancelled":
    let reg = newBuiltinRegistry()
    check reg.resolveBuiltin(EditorMode.Normal, toKeyCombo('g')).kind == rrWaiting
    let route = reg.resolveBuiltin(EditorMode.Normal, toSpecialKeyCombo(skEscape))
    check route.kind == rrCancelled

  test "unbound single key resolves to rrUnhandled":
    let reg = newBuiltinRegistry()
    let route = reg.resolveBuiltin(EditorMode.Normal, toKeyCombo('z'))
    check route.kind == rrUnhandled
    check route.key == toKeyCombo('z')

  test "invalid second key terminates the sequence as rrUnhandled":
    # Only `gg` is bound, so `gz` is invalid. processKey consumes `z` as the
    # sequence terminator and returns none; resolveBuiltin reports rrUnhandled
    # even though `z` was *consumed* (not a pure pass-through — see its note).
    let reg = newBuiltinRegistry()
    check reg.resolveBuiltin(EditorMode.Normal, toKeyCombo('g')).kind == rrWaiting
    let route = reg.resolveBuiltin(EditorMode.Normal, toKeyCombo('z'))
    check route.kind == rrUnhandled
    check route.key == toKeyCombo('z')

  test "Escape with no active sequence is rrUnhandled, not rrCancelled":
    # rrCancelled is reserved for an Escape that consumed pending state; a bare
    # Escape with nothing accumulated falls through as rrUnhandled.
    let reg = newBuiltinRegistry()
    let route = reg.resolveBuiltin(EditorMode.Normal, toSpecialKeyCombo(skEscape))
    check route.kind == rrUnhandled
    check route.key == toSpecialKeyCombo(skEscape)
