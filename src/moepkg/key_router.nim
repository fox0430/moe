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

## KeyRouter: single owner of the key-dispatch decision pipeline.
##
## The router handles runtime-mapping dispatch decisions (the `feedKey` entry
## point and the `flushTimeout` follow-up). Built-in command resolution
## (multi-key sequences, single bindings, numeric prefix, f/t/r operand waits)
## lives in `KeyBindingRegistry.processKey`; `resolveBuiltin` (below) wraps it
## into a `RouteResult` via the `rrCommand` variant and is invoked from the
## Normal-mode dispatcher (the only mode that uses sequence resolution).
##
## The router does *not* own the accumulator storage — it borrows
## `KeyBindingRegistry.runtimeMappingState`. Moving the physical storage into
## a `DispatchState` here is a follow-up refactor whose only benefit is API
## hygiene; the current code path is unaffected.

import key_router/types
import key_bindings except Command
import modes

export types

type KeyRouter* = ref object
  registry*: KeyBindingRegistry
  policy*: TimeoutPolicy

proc newKeyRouter*(registry: KeyBindingRegistry, policy: TimeoutPolicy): KeyRouter =
  KeyRouter(registry: registry, policy: policy)

proc updatePolicy*(router: KeyRouter, policy: TimeoutPolicy) {.inline.} =
  ## Update the timeout policy (call when config reloads).
  router.policy = policy

proc nextTimeoutMs*(router: KeyRouter): int =
  ## Return the milliseconds the main loop should arm an application timeout
  ## for. Zero means no timeout is needed.
  if not router.policy.enabled or router.policy.timeoutlen <= 0:
    return 0
  if router.registry.runtimeMappingState.keys.len > 0:
    return router.policy.timeoutlen
  return 0

proc hasRuntimeMappingPending*(router: KeyRouter): bool {.inline.} =
  ## True while a runtime mapping prefix is being accumulated.
  router.registry.runtimeMappingState.keys.len > 0

proc cancel*(router: KeyRouter): bool {.discardable.} =
  ## Cancel pending dispatch state that Escape should clear. Currently this
  ## is the built-in multi-key sequence accumulator only; the runtime mapping
  ## accumulator is left for the timeout path (matches today's behaviour).
  ## Returns true iff something was cleared.
  router.registry.clearAllPending()

proc clearBuiltinSequence*(router: KeyRouter): bool {.discardable.} =
  ## Clear only the built-in sequence accumulator. Returns true iff something
  ## was cleared. Used by handlers that need to reset operator-pending state
  ## after dispatching a command without going through Escape.
  if router.registry.hasActiveSequence():
    router.registry.clearSequence()
    return true
  return false

proc hasActiveBuiltinSequence*(router: KeyRouter): bool {.inline.} =
  ## True iff a built-in multi-key sequence, numeric prefix, or operand wait
  ## (f/t/r) is currently in progress.
  router.registry.hasActiveSequence()

template withReplay*(router: KeyRouter, body: untyped) =
  ## Execute `body` with `isReplayingMapping` set to true, guaranteeing the
  ## flag is restored on exit even if `body` raises or returns from the
  ## enclosing proc. Callers replaying buffered keys must wrap the loop in
  ## this template so re-entrant feedKey calls see the flag and skip mapping
  ## expansion (noremap behaviour).
  router.registry.isReplayingMapping = true
  try:
    body
  finally:
    router.registry.isReplayingMapping = false

proc mappingsFor(router: KeyRouter, mode: EditorMode): seq[RuntimeKeyMapping] =
  ## Pick the appropriate mapping table for `mode`. File-edit modes and the
  ## Command overlay only consider key-sequence mappings (rmkCommand bindings
  ## are reached through the normal `findBinding` path in those modes);
  ## special modes also expose rmkCommand mappings so users can `nmap` editor
  ## commands while a viewer is focused.
  if mode.isFileEditMode or mode == EditorMode.Command:
    router.registry.getRuntimeKeySeqMappings(mode)
  else:
    router.registry.getAllRuntimeMappings(mode)

proc flushPendingAccumulator*(router: KeyRouter, mode: EditorMode): seq[KeyCombo] =
  ## If the mappings table for `mode` is empty but the accumulator still has
  ## leftover keys (e.g. mappings were unbound mid-sequence), drain and return
  ## them so the caller can replay them before continuing. Returns `@[]`
  ## otherwise and leaves the accumulator untouched.
  ##
  ## The caller is expected to wrap the replay in `withReplay` so re-entrant
  ## feedKey calls observe `isReplayingMapping = true`.
  let mappings = router.mappingsFor(mode)
  if mappings.len == 0 and router.registry.runtimeMappingState.keys.len > 0:
    result = router.registry.runtimeMappingState.keys
    router.registry.clearRuntimeMappingState()

proc decisionToRoute(decision: RuntimeMappingDecision, key: KeyCombo): RouteResult =
  case decision.kind
  of rmdExecuteCommand:
    RouteResult(kind: rrExecuteRuntimeCommand, commandName: decision.commandName)
  of rmdExecuteKeySequence:
    RouteResult(kind: rrExecuteRuntimeKeySequence, targetKeys: decision.targetKeys)
  of rmdWaitForMore:
    RouteResult(kind: rrWaiting, waitsForTimeout: true)
  of rmdNoMatchPassThrough:
    RouteResult(kind: rrUnhandled, key: key)
  of rmdNoMatchFlush:
    RouteResult(kind: rrUnhandledBatch, keys: decision.accumulatedKeys)

proc feedKey*(router: KeyRouter, mode: EditorMode, keyCombo: KeyCombo): RouteResult =
  ## Hand `keyCombo` to the router for runtime-mapping resolution. The result
  ## tells the caller what to do next: execute a runtime mapping, wait for
  ## more keys, replay the accumulator, or fall through to normal handling.
  let mappings = router.mappingsFor(mode)
  let decision = routeRuntimeMapping(router.registry, keyCombo, mappings)
  result = decisionToRoute(decision, keyCombo)

proc flushTimeout*(router: KeyRouter, mode: EditorMode): RouteResult =
  ## Called when the key-mapping timeout fires. Inspect the accumulated keys
  ## against `mode`'s runtime mappings: if there is an exact match, fire the
  ## mapping; otherwise the caller must replay the accumulator one key at a
  ## time (mode dispatch differs between base mode and Command overlay).
  let mappings = router.mappingsFor(mode)
  let plan = flushRuntimeMapping(router.registry, mappings)
  case plan.kind
  of rmfNothing:
    RouteResult(kind: rrCancelled)
  of rmfExecuteCommand:
    RouteResult(kind: rrExecuteRuntimeCommand, commandName: plan.commandName)
  of rmfExecuteKeySequence:
    RouteResult(kind: rrExecuteRuntimeKeySequence, targetKeys: plan.targetKeys)
  of rmfReplayPerKey:
    RouteResult(kind: rrUnhandledBatch, keys: plan.keysToReplay)

proc resolveBuiltin*(
    registry: KeyBindingRegistry, mode: EditorMode, combo: KeyCombo
): RouteResult =
  ## Resolve a built-in binding/sequence/operand to a `RouteResult`. Thin
  ## wrapper over `KeyBindingRegistry.processKey`: a resolved command becomes
  ## `rrCommand`; the `none` cases are classified by observing the registry's
  ## sequence state — an active sequence means "still accumulating" (`rrWaiting`),
  ## an Escape that consumed an active sequence is `rrCancelled`, and anything
  ## else is `rrUnhandled`.
  ##
  ## Built-in sequence prefixes never time out (Vim spec), so `rrWaiting`
  ## carries `waitsForTimeout = false` — unlike runtime-mapping prefixes.
  ##
  ## NOTE: `rrUnhandled` here is *not* a pure pass-through. `combo` may already
  ## have been consumed by `processKey` as the terminator of an invalid sequence
  ## (e.g. `z` after `g` when only `gg` is bound) or as bad operand input. The
  ## current Normal-mode caller collapses every non-`rrCommand` result to
  ## "handled, no re-processing", so this is harmless today; a future caller
  ## must NOT feed `route.key` back into built-in processing or it would
  ## double-handle the terminator key.
  ##
  ## Lives in the router module (not `key_bindings`) because it returns the
  ## router-owned `RouteResult`; moving it into `key_bindings` would require
  ## that module to import `key_router/types`, which already imports
  ## `key_bindings` — a cycle. It takes a `KeyBindingRegistry` only because the
  ## built-in accumulator state still lives there.
  let wasEscapeOnActive =
    combo.isSpecial and combo.special == skEscape and registry.hasActiveSequence()
  let cmdOpt = registry.processKey(mode, combo)
  if cmdOpt.isSome:
    return RouteResult(kind: rrCommand, command: cmdOpt.get)
  if wasEscapeOnActive:
    return RouteResult(kind: rrCancelled)
  if registry.hasActiveSequence():
    return RouteResult(kind: rrWaiting, waitsForTimeout: false)
  return RouteResult(kind: rrUnhandled, key: combo)
