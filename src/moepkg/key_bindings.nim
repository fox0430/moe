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

## Keybinding management system
##
## Dispatch logic (`processKey`, runtime mappings, default-binding setup, and
## event-to-keycombo conversion). The underlying types and primitives
## (`Command`, `KeyBindingRegistry`, `registerCommand`, `bindKey`, ...) live
## in `key_bindings/registry.nim` and are re-exported below, so external
## importers can continue to `import key_bindings` unchanged.

import std/[tables, sets, strutils, options, sequtils]

import pkg/celina

import modes, logger
import key_bindings/registry
export registry

# Default `Command` definitions and the per-mode binding tables. Importing them
# here populates the registry side-effect-free at compile time; their entry
# procs (`registerAllCommands`, `bindNormalMode`, ...) are invoked from
# `setupDefaultBindings` below.
import key_bindings/[commands, normal_bindings, visual_bindings, insert_bindings]

proc unbindKey*(registry: KeyBindingRegistry, mode: EditorMode, combo: KeyCombo) =
  ## Remove a key binding
  if mode in registry.bindings:
    registry.bindings[mode].keepItIf(it.combo != combo)

proc clearSequence*(registry: KeyBindingRegistry) =
  ## Clear the current key sequence
  registry.sequenceState.keys = @[]
  registry.sequenceState.possibleSequences = @[]
  registry.sequenceState.pendingCommand = none(Command)
  registry.sequenceState.waitingForChar = false
  registry.sequenceState.numericPrefix = ""
  registry.sequenceState.hasNumericPrefix = false

proc hasActiveSequence*(registry: KeyBindingRegistry): bool =
  ## Check if there is an active key sequence in progress
  registry.sequenceState.keys.len > 0 or registry.sequenceState.waitingForChar or
    registry.sequenceState.hasNumericPrefix

proc clearAllPending*(registry: KeyBindingRegistry): bool {.discardable.} =
  ## Clear all key-dispatch pending state that Escape should cancel. Currently
  ## this only covers the built-in multi-key sequence accumulator; the runtime
  ## mapping accumulator is intentionally left untouched so that Escape inside
  ## a `:nmap` prefix retains today's behaviour (the timeout path flushes it).
  ## Returns true iff something was cleared. Centralising this call lets
  ## handler.nim stop reaching into registry internals; future phases extend
  ## the body without revisiting handler.nim.
  if registry.hasActiveSequence():
    registry.clearSequence()
    return true
  return false

proc parseKeyString*(s: string): seq[KeyCombo] =
  ## Parse a key string into a sequence of KeyCombos.
  ## Supports space-separated tokens (e.g., "C-s Enter", "g g") and
  ## Vim-style concatenated characters (e.g., "jj" = two j presses).
  ## Returns empty seq on parse error.
  let parts = s.strip().split(' ')
  for part in parts:
    if part.len == 0:
      continue
    let combo = parseKeyCombo(part)
    if combo.isSome:
      result.add(combo.get)
    elif part.len > 1 and '-' notin part:
      # Vim-style concatenated characters: "jj", "gg", "gd" etc.
      for ch in part:
        let charCombo = parseKeyCombo($ch)
        if charCombo.isNone:
          return @[]
        result.add(charCombo.get)
    else:
      return @[]

proc keySeqToDisplayString*(keys: seq[KeyCombo]): string =
  ## Convert a sequence of KeyCombos to a display string (space-separated)
  for i, k in keys:
    if i > 0:
      result.add(' ')
    if k.isSpecial:
      case k.special
      of skEnter:
        result.add("Enter")
      of skTab:
        result.add("Tab")
      of skBackTab:
        result.add("BackTab")
      of skBackspace:
        result.add("Backspace")
      of skDelete:
        result.add("Delete")
      of skEscape:
        result.add("Escape")
      of skUp:
        result.add("Up")
      of skDown:
        result.add("Down")
      of skLeft:
        result.add("Left")
      of skRight:
        result.add("Right")
      of skPageUp:
        result.add("PageUp")
      of skPageDown:
        result.add("PageDown")
      of skHome:
        result.add("Home")
      of skEnd:
        result.add("End")
      of skFunction:
        result.add("F" & $k.fnNum)
      of skNone:
        discard
    else:
      var prefix = ""
      if kmCtrl in k.modifiers:
        prefix.add("C-")
      if kmAlt in k.modifiers:
        prefix.add("M-")
      if kmShift in k.modifiers:
        prefix.add("S-")
      if k.char == " ":
        result.add(prefix & "Space")
      else:
        result.add(prefix & k.char)

proc addRuntimeMapping*(
    registry: KeyBindingRegistry, mode: EditorMode, lhsStr: string, rhsStr: string
): string =
  ## Add a runtime key mapping. Returns empty string on success, error message on failure.
  ## If RHS is a known command name, registers as key→command.
  ## Otherwise, parses RHS as key sequence and registers as key→key-sequence.
  let lhsKeys = parseKeyString(lhsStr)
  if lhsKeys.len == 0:
    return "Invalid key: " & lhsStr

  # Check if RHS is a command name
  if rhsStr in registry.commandRegistry:
    # Key → command mapping: register directly via existing bindings infrastructure
    let command = registry.commandRegistry[rhsStr]
    if lhsKeys.len == 1:
      registry.bindKey(mode, lhsKeys[0], command)
    else:
      registry.bindSequence(mode, lhsKeys, command)

    # Also store in runtimeMappings for listing/removal
    let mapping = RuntimeKeyMapping(
      triggerKeys: lhsKeys,
      triggerStr: lhsStr,
      targetStr: rhsStr,
      kind: rmkCommand,
      commandName: rhsStr,
    )
    # Remove existing mapping for same trigger
    registry.runtimeMappings[mode].keepItIf(it.triggerKeys != lhsKeys)
    registry.runtimeMappings[mode].add(mapping)
    return ""

  # Otherwise, parse RHS as key sequence
  let rhsKeys = parseKeyString(rhsStr)
  if rhsKeys.len == 0:
    return "Invalid mapping target: " & rhsStr

  # Convert RHS keys to string representation for playbackMacro
  var targetKeyStrs: seq[string] = @[]
  for k in rhsKeys:
    targetKeyStrs.add(keyComboToString(k))

  let mapping = RuntimeKeyMapping(
    triggerKeys: lhsKeys,
    triggerStr: lhsStr,
    targetStr: rhsStr,
    kind: rmkKeySequence,
    targetKeys: targetKeyStrs,
  )

  # Remove existing mapping for same trigger
  registry.runtimeMappings[mode].keepItIf(it.triggerKeys != lhsKeys)
  registry.runtimeMappings[mode].add(mapping)
  return ""

proc removeRuntimeMapping*(
    registry: KeyBindingRegistry, mode: EditorMode, lhsStr: string
): string =
  ## Remove a runtime key mapping. Returns empty string on success, error message on failure.
  let lhsKeys = parseKeyString(lhsStr)
  if lhsKeys.len == 0:
    return "Invalid key: " & lhsStr

  if mode notin registry.runtimeMappings:
    return "No mapping found: " & lhsStr

  var removedMapping: Option[RuntimeKeyMapping] = none(RuntimeKeyMapping)

  for m in registry.runtimeMappings[mode]:
    if m.triggerKeys == lhsKeys:
      removedMapping = some(m)
      break

  if removedMapping.isNone:
    return "No mapping found: " & lhsStr

  registry.runtimeMappings[mode].keepItIf(it.triggerKeys != lhsKeys)

  # If it was a command mapping, also remove from bindings/sequences
  let m = removedMapping.get
  if m.kind == rmkCommand:
    if lhsKeys.len == 1:
      registry.unbindKey(mode, lhsKeys[0])
    else:
      if mode in registry.sequences:
        registry.sequences[mode].del(lhsKeys)

  return ""

proc clearRuntimeMappings*(registry: KeyBindingRegistry, mode: EditorMode) =
  ## Clear all runtime mappings for the given mode
  if mode in registry.runtimeMappings:
    # Remove command mappings from bindings/sequences
    for m in registry.runtimeMappings[mode]:
      if m.kind == rmkCommand:
        if m.triggerKeys.len == 1:
          registry.unbindKey(mode, m.triggerKeys[0])
        else:
          if mode in registry.sequences:
            registry.sequences[mode].del(m.triggerKeys)
    registry.runtimeMappings[mode] = @[]

proc listRuntimeMappings*(registry: KeyBindingRegistry, mode: EditorMode): seq[string] =
  ## List all runtime mappings for the given mode as human-readable strings
  if mode notin registry.runtimeMappings:
    return @[]
  for m in registry.runtimeMappings[mode]:
    result.add(m.triggerStr & " -> " & m.targetStr)

proc clearRuntimeMappingState*(state: var DispatchState) =
  ## Clear the runtime mapping key accumulator. The accumulator is owned by the
  ## `KeyRouter` (`dispatchState`) and passed in by the router.
  state.keys = @[]

proc getRuntimeKeySeqMappings*(
    registry: KeyBindingRegistry, mode: EditorMode
): seq[RuntimeKeyMapping] =
  ## Get all key-sequence runtime mappings for the given mode
  if mode notin registry.runtimeMappings:
    return @[]
  for m in registry.runtimeMappings[mode]:
    if m.kind == rmkKeySequence:
      result.add(m)

proc getAllRuntimeMappings*(
    registry: KeyBindingRegistry, mode: EditorMode
): seq[RuntimeKeyMapping] =
  ## Get all runtime mappings for the given mode (both rmkCommand and rmkKeySequence)
  if mode notin registry.runtimeMappings:
    return @[]
  return registry.runtimeMappings[mode]

proc routeRuntimeMapping*(
    state: var DispatchState, keyCombo: KeyCombo, mappings: seq[RuntimeKeyMapping]
): RuntimeMappingDecision =
  ## Decide what to do with `keyCombo` given the runtime mapping table for the
  ## current mode. The accumulator (`state`, owned by the `KeyRouter`) is mutated
  ## as appropriate:
  ## - on exact match or no-match flush: cleared before returning
  ## - on prefix match: extended with `keyCombo`
  ## - on empty `mappings` with no prior accumulation: untouched
  ##
  ## This is a pure routing decision; the caller executes the result.
  ## Historically there are two execution styles — base mode (handler_manager)
  ## replays accumulatedKeys[0..^2] and re-processes the current key, while
  ## the Command overlay replays the full accumulatedKeys and stops. Both can
  ## be expressed from the same decision.

  if mappings.len == 0:
    if state.keys.len > 0:
      clearRuntimeMappingState(state)
    return RuntimeMappingDecision(kind: rmdNoMatchPassThrough)

  state.keys.add(keyCombo)
  let accKeys = state.keys

  var exactMatch: Option[RuntimeKeyMapping] = none(RuntimeKeyMapping)
  var hasLongerMatch = false
  for m in mappings:
    if m.triggerKeys == accKeys:
      exactMatch = some(m)
    elif m.triggerKeys.len > accKeys.len:
      var isPrefix = true
      for i in 0 ..< accKeys.len:
        if m.triggerKeys[i] != accKeys[i]:
          isPrefix = false
          break
      if isPrefix:
        hasLongerMatch = true

  if exactMatch.isSome and not hasLongerMatch:
    let matched = exactMatch.get
    clearRuntimeMappingState(state)
    case matched.kind
    of rmkCommand:
      return RuntimeMappingDecision(
        kind: rmdExecuteCommand, commandName: matched.commandName
      )
    of rmkKeySequence:
      return RuntimeMappingDecision(
        kind: rmdExecuteKeySequence, targetKeys: matched.targetKeys
      )

  if hasLongerMatch:
    # Both exact and longer match possible: wait for next key. If no key
    # arrives within timeoutlen, the timeout path will flush the accumulator
    # and execute the exact match.
    return RuntimeMappingDecision(kind: rmdWaitForMore)

  if accKeys.len == 1:
    clearRuntimeMappingState(state)
    return RuntimeMappingDecision(kind: rmdNoMatchPassThrough)

  let flushed = accKeys
  clearRuntimeMappingState(state)
  return RuntimeMappingDecision(kind: rmdNoMatchFlush, accumulatedKeys: flushed)

proc flushRuntimeMapping*(
    state: var DispatchState, mappings: seq[RuntimeKeyMapping]
): RuntimeMappingFlushPlan =
  ## When the key-mapping timeout fires, decide how to flush the accumulator.
  ## Caller passes the appropriate mappings table for the current mode/overlay.
  ## The accumulator (`state`, owned by the `KeyRouter`) is cleared before
  ## returning (unless it was already empty).
  if state.keys.len == 0:
    return RuntimeMappingFlushPlan(kind: rmfNothing)

  let accKeys = state.keys
  var exactMatch: Option[RuntimeKeyMapping] = none(RuntimeKeyMapping)
  for m in mappings:
    if m.triggerKeys == accKeys:
      exactMatch = some(m)
      break

  clearRuntimeMappingState(state)

  if exactMatch.isSome:
    let matched = exactMatch.get
    case matched.kind
    of rmkCommand:
      return RuntimeMappingFlushPlan(
        kind: rmfExecuteCommand, commandName: matched.commandName
      )
    of rmkKeySequence:
      return RuntimeMappingFlushPlan(
        kind: rmfExecuteKeySequence, targetKeys: matched.targetKeys
      )

  return RuntimeMappingFlushPlan(kind: rmfReplayPerKey, keysToReplay: accKeys)

proc isDigitKey*(combo: KeyCombo): bool =
  ## Check if the key combination is a digit (0-9)
  not combo.isSpecial and combo.modifiers == {} and combo.char.len == 1 and
    combo.char[0] >= '0' and combo.char[0] <= '9'

proc getNumericPrefix*(registry: KeyBindingRegistry): int =
  ## Get the numeric prefix as integer, defaulting to 1
  logDebug(
    "keybind",
    "getNumericPrefix: hasPrefix=" & $registry.sequenceState.hasNumericPrefix &
      ", prefix='" & registry.sequenceState.numericPrefix & "'",
  )
  if registry.sequenceState.hasNumericPrefix and
      registry.sequenceState.numericPrefix.len > 0:
    try:
      let num = parseInt(registry.sequenceState.numericPrefix)
      let prefixValue = if num > 0: num else: 1
      logDebug("keybind", "getNumericPrefix returning: " & $prefixValue)
      return prefixValue
    except ValueError:
      logDebug("keybind", "getNumericPrefix returning 1 (parse error)")
      return 1
  else:
    logDebug("keybind", "getNumericPrefix returning 1 (no prefix)")
    return 1

proc applyCountToCommand(registry: KeyBindingRegistry, cmd: Command): Command =
  ## Apply numeric prefix count to a command and clear the prefix
  result = cmd
  result.count = registry.getNumericPrefix()
  # Clear numeric prefix after applying
  registry.sequenceState.numericPrefix = ""
  registry.sequenceState.hasNumericPrefix = false
  logDebug("keybind", "Applied count=" & $result.count & " to command: " & cmd.name)

proc updatePossibleSequences*(registry: KeyBindingRegistry, mode: EditorMode) =
  ## Update the list of possible sequences based on current keys
  registry.sequenceState.possibleSequences = @[]

  if mode in registry.sequences:
    for seq, _ in registry.sequences[mode]:
      if seq.len >= registry.sequenceState.keys.len:
        # Check if current keys match the beginning of this sequence
        var matches = true
        for i, key in registry.sequenceState.keys:
          if i >= seq.len or seq[i] != key:
            matches = false
            break
        if matches:
          registry.sequenceState.possibleSequences.add(seq)

proc findSingleBinding*(
    registry: KeyBindingRegistry, mode: EditorMode, combo: KeyCombo
): Option[Command] =
  ## Find the command bound to a single key combination
  if mode notin registry.bindings:
    return none(Command)

  for binding in registry.bindings[mode]:
    if binding.combo == combo:
      return some(binding.command)

  return none(Command)

proc processKey*(
    registry: KeyBindingRegistry, mode: EditorMode, combo: KeyCombo
): Option[Command] =
  ## Process a key press, handling both single keys and sequences

  logDebug(
    "keybind",
    "processKey: mode=" & $mode & " combo.isSpecial=" & $combo.isSpecial & " combo.char=" &
      (if not combo.isSpecial: combo.char else: "<special>") & " combo.modifiers=" &
      $combo.modifiers & " seqKeys.len=" & $registry.sequenceState.keys.len,
  )

  # Check if we're waiting for an arbitrary character (f, t, r commands)
  if registry.sequenceState.waitingForChar and
      registry.sequenceState.pendingCommand.isSome:
    let pendingCmd = registry.sequenceState.pendingCommand.get

    # Create the final command with the character
    if not combo.isSpecial and combo.modifiers == {}:
      # Set the target character
      var finalCommand = pendingCmd
      finalCommand.targetChar = combo.char
      # Apply numeric prefix count before clearing
      let cmdWithCount = registry.applyCountToCommand(finalCommand)
      registry.clearSequence()
      return some(cmdWithCount)
    else:
      # Invalid input for character-waiting commands
      registry.clearSequence()
      return none(Command)

  # Handle numeric prefix input (only when no keys are in sequence and not waiting for char)
  # Skip numeric prefix accumulation in Insert/Replace modes where digits are text input
  if mode notin {EditorMode.Insert, EditorMode.Replace} and
      registry.sequenceState.keys.len == 0 and not registry.sequenceState.waitingForChar and
      isDigitKey(combo):
    # Special case: ignore leading zero unless it's standalone
    if combo.char == "0" and registry.sequenceState.numericPrefix.len == 0:
      # Standalone 0 is not allowed as count prefix in vim, treat as regular key
      discard
    else:
      # Add digit to numeric prefix
      registry.sequenceState.numericPrefix.add(combo.char)
      registry.sequenceState.hasNumericPrefix = true
      return none(Command) # Wait for command key

  # Check for ESC key - cancel any current sequence
  if combo.isSpecial and combo.special == skEscape:
    if registry.sequenceState.keys.len > 0 or registry.sequenceState.waitingForChar or
        registry.sequenceState.hasNumericPrefix:
      registry.clearSequence()
      return none(Command) # Sequence cancelled
    # If no sequence active, treat ESC as normal key

  # Add current key to sequence
  registry.sequenceState.keys.add(combo)

  # Update possible sequences based on current keys
  registry.updatePossibleSequences(mode)

  logDebug(
    "keybind",
    "processKey: after update, seqKeys.len=" & $registry.sequenceState.keys.len &
      " possibleSequences.len=" & $registry.sequenceState.possibleSequences.len,
  )

  # Log current keys in sequence for debugging
  var keysStr = ""
  for i, k in registry.sequenceState.keys:
    if i > 0:
      keysStr.add(", ")
    keysStr.add(
      if k.isSpecial:
        "<special>"
      else:
        "'" & k.char & "'" & " mods=" & $k.modifiers
    )
  logDebug("keybind", "processKey: current keys=[" & keysStr & "]")

  # Check if this completes a sequence
  if mode in registry.sequences:
    logDebug(
      "keybind",
      "processKey: checking sequences for mode, numSequences=" &
        $registry.sequences[mode].len,
    )
    if registry.sequenceState.keys in registry.sequences[mode]:
      let command = registry.sequences[mode][registry.sequenceState.keys]

      # Check if this command requires additional input
      if command.kind == ctOperatorPending:
        registry.sequenceState.pendingCommand = some(command)
        registry.sequenceState.waitingForChar = true
        registry.sequenceState.keys = @[] # Clear keys but keep pending state
        return none(Command) # Wait for next key
      else:
        # Apply count and clear sequence
        let cmdWithCount = registry.applyCountToCommand(command)
        registry.sequenceState.keys = @[]
        registry.sequenceState.possibleSequences = @[]
        return some(cmdWithCount)

  # Check if we have any possible sequences that could continue
  if registry.sequenceState.possibleSequences.len > 0:
    # Check if any sequence exactly matches current length + still continuing
    var hasLongerSequence = false
    for seq in registry.sequenceState.possibleSequences:
      if seq.len > registry.sequenceState.keys.len:
        hasLongerSequence = true
        break

    if hasLongerSequence:
      logDebug("keybind", "processKey: waiting for more keys (hasLongerSequence)")
      # Wait for more keys
      return none(Command)

  logDebug(
    "keybind",
    "processKey: no sequence match, possibleSequences=" &
      $registry.sequenceState.possibleSequences.len,
  )

  # No valid sequence continuation, try single key binding
  if registry.sequenceState.keys.len == 1:
    let singleKeyResult = registry.findSingleBinding(mode, combo)
    logDebug(
      "keybind", "processKey: single key lookup, found=" & $singleKeyResult.isSome
    )

    # Check if this command requires additional input
    if singleKeyResult.isSome and singleKeyResult.get.kind == ctOperatorPending:
      registry.sequenceState.pendingCommand = singleKeyResult
      registry.sequenceState.waitingForChar = true
      registry.sequenceState.keys = @[] # Clear keys but keep pending state
      return none(Command) # Wait for next key
    elif singleKeyResult.isSome:
      # Apply count and clear sequence
      let cmdWithCount = registry.applyCountToCommand(singleKeyResult.get)
      registry.sequenceState.keys = @[]
      registry.sequenceState.possibleSequences = @[]
      return some(cmdWithCount)
    else:
      # No binding found
      logDebug("keybind", "processKey: no single binding found for key")
      registry.sequenceState.keys = @[]
      registry.sequenceState.possibleSequences = @[]
      return none(Command)

  # Invalid sequence
  logDebug(
    "keybind",
    "processKey: invalid sequence, clearing. seqKeys.len=" &
      $registry.sequenceState.keys.len,
  )
  registry.clearSequence()
  return none(Command)

proc findBinding*(
    registry: KeyBindingRegistry, mode: EditorMode, combo: KeyCombo
): Option[Command] =
  ## Find the command bound to a key combination (delegates to processKey)
  return registry.processKey(mode, combo)

proc setupDefaultBindings*(registry: KeyBindingRegistry) =
  ## Set up default key bindings (can be overridden by config)

  registry.registerAllCommands()

  registry.bindNormalMode()

  registry.bindVisualModes()

  registry.bindInsertAndReplaceModes()

proc eventToKeyCombo*(event: celina.Event): Option[KeyCombo] =
  ## Convert a Celina event to a key combination
  if event.kind != celina.EventKind.Key:
    return none(KeyCombo)

  var combo: KeyCombo

  # Check if it's a character key
  if event.key.code == celina.KeyCode.Char:
    combo = KeyCombo(isSpecial: false, char: $event.key.char)
  else:
    # Map special keys
    case event.key.code
    of celina.KeyCode.Enter:
      combo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0)
    of celina.KeyCode.Tab:
      combo = KeyCombo(isSpecial: true, special: skTab, fnNum: 0)
    of celina.KeyCode.BackTab:
      combo = KeyCombo(isSpecial: true, special: skBackTab, fnNum: 0)
    of celina.KeyCode.Backspace:
      combo = KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0)
    of celina.KeyCode.Delete:
      combo = KeyCombo(isSpecial: true, special: skDelete, fnNum: 0)
    of celina.KeyCode.Escape:
      combo = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0)
    of celina.KeyCode.ArrowUp:
      combo = KeyCombo(isSpecial: true, special: skUp, fnNum: 0)
    of celina.KeyCode.ArrowDown:
      combo = KeyCombo(isSpecial: true, special: skDown, fnNum: 0)
    of celina.KeyCode.ArrowLeft:
      combo = KeyCombo(isSpecial: true, special: skLeft, fnNum: 0)
    of celina.KeyCode.ArrowRight:
      combo = KeyCombo(isSpecial: true, special: skRight, fnNum: 0)
    of celina.KeyCode.PageUp:
      combo = KeyCombo(isSpecial: true, special: skPageUp, fnNum: 0)
    of celina.KeyCode.PageDown:
      combo = KeyCombo(isSpecial: true, special: skPageDown, fnNum: 0)
    of celina.KeyCode.Home:
      combo = KeyCombo(isSpecial: true, special: skHome, fnNum: 0)
    of celina.KeyCode.End:
      combo = KeyCombo(isSpecial: true, special: skEnd, fnNum: 0)
    of celina.KeyCode.Space:
      combo = KeyCombo(isSpecial: false, char: " ")
    else:
      # Function keys are handled differently in celina
      return none(KeyCombo)

  # Extract modifiers from event
  combo.modifiers = {}
  if celina.KeyModifier.Ctrl in event.key.modifiers:
    combo.modifiers.incl(kmCtrl)
  if celina.KeyModifier.Alt in event.key.modifiers:
    combo.modifiers.incl(kmAlt)
  if celina.KeyModifier.Shift in event.key.modifiers:
    # For character keys, the shift state is already reflected in the character
    # itself (e.g., 'T' vs 't', '!' vs '1'). Only include Shift modifier for
    # special keys (arrows, function keys, etc.) where shift changes behavior.
    # skBackTab already encodes Shift+Tab in the keycode, so suppress the
    # redundant kmShift to match `parseKeyCombo("S-Tab")` -> skBackTab.
    if combo.isSpecial and combo.special != skBackTab:
      combo.modifiers.incl(kmShift)

  # Some terminals deliver Shift+Tab as `KeyCode.Tab + Shift modifier` instead
  # of the dedicated `KeyCode.BackTab`. Normalize that to skBackTab here so it
  # matches `parseKeyCombo("S-Tab")`, which already collapses to skBackTab.
  if combo.isSpecial and combo.special == skTab and kmShift in combo.modifiers:
    combo.special = skBackTab
    combo.modifiers.excl(kmShift)

  logDebug(
    "keybind",
    "eventToKeyCombo: isSpecial=" & $combo.isSpecial & " char=" &
      (if not combo.isSpecial: combo.char else: "<special>") & " modifiers=" &
      $combo.modifiers & " event.key.modifiers=" & $event.key.modifiers,
  )

  return some(combo)

proc getValidMappingCommands*(): HashSet[string] =
  ## Returns a set of valid command names for key mapping validation.
  var registry = newKeyBindingRegistry()
  registry.setupDefaultBindings()
  for name in registry.commandRegistry.keys:
    result.incl(name)
