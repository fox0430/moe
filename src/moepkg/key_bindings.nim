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
## This module provides a flexible keybinding system that allows
## mapping keys to commands through configuration files.

import std/[tables, sets, strutils, options, sequtils, hashes]

import pkg/celina

import types, modes, logger

const ExecCmdlinePrefix* = "exec.cmdline."
  ## commandId prefix for Command mode command alias bridge entries (see
  ## `keyMappableCommandModeAliases`). At dispatch time, a Command with
  ## `commandId = ExecCmdlinePrefix & <alias>` is rewritten into an
  ## `hrExecCommand` / `nmrExecCommand` carrying `<alias>` as the command-line
  ## text, so the full `:`-parser (and its safety checks) runs.

type
  ## Key modifiers that can be combined
  KeyModifier* = enum
    kmNone
    kmCtrl
    kmAlt
    kmShift
    kmMeta

  ## A key combination with potential modifiers
  ## We store the key as char and special key kind separately
  ## to avoid direct dependency on celina.Key type
  SpecialKey* = enum
    skNone
    skEnter
    skTab
    skBackTab
    skBackspace
    skDelete
    skEscape
    skUp
    skDown
    skLeft
    skRight
    skPageUp
    skPageDown
    skHome
    skEnd
    skFunction

  KeyCombo* = object
    case isSpecial*: bool
    of true:
      special*: SpecialKey
      fnNum*: int ## For function keys
    of false:
      char*: string
    modifiers*: set[KeyModifier]

  ## Types of commands that can be bound
  CommandType* = enum
    ctMotion ## Basic cursor movement
    ctAction ## Editor actions (save, quit, etc)
    ctModeSwitch ## Switch editor modes
    ctOverlaySwitch ## Switch to overlay modes (command, search, rename)
    ctTextObject ## Text object operations
    ctOperator ## Vim-style operators (delete, yank, etc)
    ctOperatorPending ## Operators that require additional input (f, t, r, etc)
    ctCustom ## User-defined commands

  ## A command that can be executed
  Command* = object
    name*: string
    description*: string
    count*: int ## Numeric prefix (e.g., 2 in "2w"), defaults to 1
    case kind*: CommandType
    of ctMotion:
      motion*: Motion
    of ctModeSwitch:
      targetMode*: EditorMode
    of ctOverlaySwitch:
      targetOverlay*: OverlayKind
    of ctOperatorPending:
      operatorType*: string ## "find", "till", "replace", etc
      reverse*: bool ## For F, T (backwards versions)
      targetChar*: string ## The character to find/till/replace
    of ctAction, ctTextObject, ctOperator, ctCustom:
      commandId*: string # Will be converted to CommandId in command_registry
      args*: seq[string]

  ## Keybinding maps keys to commands
  KeyBinding* = object
    combo*: KeyCombo
    command*: Command
    context*: EditorMode ## Which mode this binding is active in

  ## Key sequence state for tracking multi-key combinations
  KeySequenceState* = object
    keys*: seq[KeyCombo] ## Keys pressed so far
    possibleSequences*: seq[seq[KeyCombo]] ## Sequences that match current prefix
    pendingCommand*: Option[Command] ## Command waiting for additional input
    waitingForChar*: bool ## Whether we're waiting for an arbitrary character
    numericPrefix*: string ## For building numeric prefixes like "2", "23", etc
    hasNumericPrefix*: bool ## Whether we have a numeric prefix to apply

  ## Kind of runtime key mapping
  RuntimeMappingKind* = enum
    rmkCommand ## Maps to a command name (handled via existing bindings)
    rmkKeySequence ## Maps to a key sequence (replayed via playbackMacro)

  ## A runtime key mapping entry
  RuntimeKeyMapping* = object
    triggerKeys*: seq[KeyCombo] ## LHS (trigger key sequence)
    triggerStr*: string ## Display string for LHS
    targetStr*: string ## Display string for RHS
    case kind*: RuntimeMappingKind
    of rmkCommand:
      commandName*: string
    of rmkKeySequence:
      targetKeys*: seq[string] ## Key strings for playbackMacro

  ## State for accumulating keys for runtime key-seq mapping matching
  RuntimeMappingState* = object
    keys*: seq[KeyCombo] ## Keys accumulated so far

  ## Result of matching a single key against the runtime mapping table.
  ## `routeRuntimeMapping` returns this; the caller executes the decision.
  RuntimeMappingDecisionKind* = enum
    rmdExecuteCommand ## Exact match, rmkCommand: execute named command
    rmdExecuteKeySequence ## Exact match, rmkKeySequence: replay target keys
    rmdWaitForMore ## Prefix of one or more mappings; wait for next key
    rmdNoMatchPassThrough
      ## Either the table is empty, or the only key accumulated has no match.
      ## Caller should process the current key as if no mapping existed.
    rmdNoMatchFlush
      ## Two or more keys accumulated and none match. Caller must replay
      ## the accumulated keys (with `isReplayingMapping = true`); whether the
      ## current key is part of the replay or processed separately is up to
      ## the caller (base mode and Command overlay differ here historically).

  RuntimeMappingDecision* = object
    case kind*: RuntimeMappingDecisionKind
    of rmdExecuteCommand:
      commandName*: string
    of rmdExecuteKeySequence:
      targetKeys*: seq[string]
    of rmdWaitForMore, rmdNoMatchPassThrough:
      discard
    of rmdNoMatchFlush:
      accumulatedKeys*: seq[KeyCombo]

  ## Plan returned by `flushRuntimeMapping` when the key-mapping timeout fires
  ## with a non-empty accumulator. The caller is responsible for executing the
  ## plan (Command overlay and base mode use different executors).
  RuntimeMappingFlushKind* = enum
    rmfNothing ## Accumulator was already empty
    rmfExecuteCommand ## Exact match with rmkCommand
    rmfExecuteKeySequence ## Exact match with rmkKeySequence
    rmfReplayPerKey ## No exact match: replay each accumulated key individually

  RuntimeMappingFlushPlan* = object
    case kind*: RuntimeMappingFlushKind
    of rmfNothing:
      discard
    of rmfExecuteCommand:
      commandName*: string
    of rmfExecuteKeySequence:
      targetKeys*: seq[string]
    of rmfReplayPerKey:
      keysToReplay*: seq[KeyCombo]

  ## Registry for all key_bindings
  KeyBindingRegistry* = ref object
    bindings*: Table[EditorMode, seq[KeyBinding]]
    sequences*: Table[EditorMode, Table[seq[KeyCombo], Command]] ## Multi-key sequences
    commandRegistry*: Table[string, Command]
    sequenceState*: KeySequenceState ## Current sequence being built
    runtimeMappings*: Table[EditorMode, seq[RuntimeKeyMapping]]
    runtimeMappingState*: RuntimeMappingState ## Key-seq accumulator
    isReplayingMapping*: bool ## When true, skip mapping expansion (noremap)

proc `==`*(a, b: KeyCombo): bool =
  if a.isSpecial != b.isSpecial:
    return false
  if a.isSpecial:
    result = a.special == b.special and a.fnNum == b.fnNum
  else:
    result = a.char == b.char
  result = result and a.modifiers == b.modifiers

proc hash*(k: KeyCombo): Hash =
  var h: Hash = 0
  if k.isSpecial:
    h = h !& hash(k.special)
    h = h !& hash(k.fnNum)
  else:
    h = h !& hash(k.char)
  h = h !& hash(k.modifiers)
  result = !$h

proc toKeyCombo*(
    ch: char, ctrl = false, alt = false, shift = false, meta = false
): KeyCombo =
  ## Create a key combination from a character and modifiers
  result = KeyCombo(isSpecial: false, char: $ch)
  if ctrl:
    result.modifiers.incl(kmCtrl)
  if alt:
    result.modifiers.incl(kmAlt)
  if shift:
    result.modifiers.incl(kmShift)
  if meta:
    result.modifiers.incl(kmMeta)

proc toSpecialKeyCombo*(
    special: SpecialKey,
    fnNum = 0,
    ctrl = false,
    alt = false,
    shift = false,
    meta = false,
): KeyCombo =
  ## Create a key combination from a special key and modifiers
  result = KeyCombo(isSpecial: true, special: special, fnNum: fnNum)
  if ctrl:
    result.modifiers.incl(kmCtrl)
  if alt:
    result.modifiers.incl(kmAlt)
  if shift:
    result.modifiers.incl(kmShift)
  if meta:
    result.modifiers.incl(kmMeta)

proc parseKeyCombo*(s: string): Option[KeyCombo] =
  ## Parse a string like "C-x" or "M-w" into a KeyCombo
  ## C = Ctrl, M = Meta/Alt, S = Shift

  # Handle single-character strings directly (including "-" itself)
  if s.len == 1:
    return some(KeyCombo(isSpecial: false, char: s, modifiers: {}))

  var parts = s.split('-')
  if parts.len == 0:
    return none(KeyCombo)

  var modifiers: set[KeyModifier] = {}

  # Process modifiers (all parts except the last one)
  for i in 0 ..< parts.len - 1:
    case parts[i].toUpperAscii
    of "C", "CTRL":
      modifiers.incl(kmCtrl)
    of "M", "META", "ALT":
      modifiers.incl(kmAlt)
    of "S", "SHIFT":
      modifiers.incl(kmShift)
    else:
      return none(KeyCombo)

  # Process the key (last part)
  let keyStr = parts[^1]
  var combo: KeyCombo

  if keyStr.len == 1:
    combo = KeyCombo(isSpecial: false, char: $keyStr[0])
  else:
    # Handle special keys
    case keyStr.toUpperAscii
    of "SPACE":
      combo = KeyCombo(isSpecial: false, char: " ")
    of "ENTER", "RETURN":
      combo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0)
    of "TAB":
      combo = KeyCombo(isSpecial: true, special: skTab, fnNum: 0)
    of "BACKSPACE":
      combo = KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0)
    of "DELETE":
      combo = KeyCombo(isSpecial: true, special: skDelete, fnNum: 0)
    of "ESC", "ESCAPE":
      combo = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0)
    of "UP":
      combo = KeyCombo(isSpecial: true, special: skUp, fnNum: 0)
    of "DOWN":
      combo = KeyCombo(isSpecial: true, special: skDown, fnNum: 0)
    of "LEFT":
      combo = KeyCombo(isSpecial: true, special: skLeft, fnNum: 0)
    of "RIGHT":
      combo = KeyCombo(isSpecial: true, special: skRight, fnNum: 0)
    of "PAGEUP":
      combo = KeyCombo(isSpecial: true, special: skPageUp, fnNum: 0)
    of "PAGEDOWN":
      combo = KeyCombo(isSpecial: true, special: skPageDown, fnNum: 0)
    of "HOME":
      combo = KeyCombo(isSpecial: true, special: skHome, fnNum: 0)
    of "END":
      combo = KeyCombo(isSpecial: true, special: skEnd, fnNum: 0)
    else:
      # Try function keys
      if keyStr.startsWith("F") and keyStr.len > 1:
        try:
          let num = parseInt(keyStr[1 ..^ 1])
          if num >= 1 and num <= 12:
            combo = KeyCombo(isSpecial: true, special: skFunction, fnNum: num)
          else:
            return none(KeyCombo)
        except ValueError:
          return none(KeyCombo)
      else:
        return none(KeyCombo)

  # Set the modifiers once
  combo.modifiers = modifiers

  # Ctrl + non-letter character is not detectable in terminals
  if kmCtrl in combo.modifiers and not combo.isSpecial and combo.char.len == 1:
    if combo.char[0] notin {'a' .. 'z', 'A' .. 'Z'}:
      return none(KeyCombo)

  # Normalize Shift+<letter>: terminals deliver the uppercase character without
  # a separate Shift modifier (see `eventToKeyCombo`).
  if kmShift in combo.modifiers and not combo.isSpecial and combo.char.len == 1:
    if combo.char[0] in {'a' .. 'z', 'A' .. 'Z'}:
      combo.char = combo.char.toUpperAscii
      combo.modifiers.excl(kmShift)
    else:
      # Shift+<digit/symbol> is layout-dependent — terminals deliver the
      # shifted character without a Shift modifier (e.g. Shift+1 -> '!').
      # Accepting "S-1" here would silently never match. Reject so the user
      # writes the literal shifted character.
      return none(KeyCombo)

  # Normalize Shift+Tab: terminals report it as the dedicated BackTab keycode
  # (see `eventToKeyCombo`), so "S-Tab" must map to skBackTab without Shift.
  if kmShift in combo.modifiers and combo.isSpecial and combo.special == skTab:
    combo.special = skBackTab
    combo.modifiers.excl(kmShift)

  # Note: `S-<other special>` (e.g. `S-Enter`, `S-Backspace`, `S-Up`) is
  # accepted here, but most terminals do *not* distinguish the shifted form
  # from the unshifted one (only Shift+Arrow and Shift+Function keys are
  # widely reported with the Shift modifier). Such bindings may silently never
  # fire depending on the terminal. We accept them rather than rejecting like
  # `S-<digit/symbol>` because for arrows/function keys the Shift modifier
  # *is* genuinely available via `eventToKeyCombo`.

  return some(combo)

proc specialKeyBodyString(keyCombo: KeyCombo): string =
  ## Body portion of `keyComboToString` for special keys (without modifier
  ## prefix or angle brackets). `skNone` returns the empty string.
  ## Note: skBackTab returns "Tab" here; the caller (`keyComboToString`) adds
  ## the `S-` prefix to distinguish it from skTab.
  case keyCombo.special
  of skEnter:
    "Enter"
  of skTab:
    "Tab"
  of skBackTab:
    "Tab"
  of skBackspace:
    "Backspace"
  of skDelete:
    "Delete"
  of skEscape:
    "Escape"
  of skUp:
    "Up"
  of skDown:
    "Down"
  of skLeft:
    "Left"
  of skRight:
    "Right"
  of skPageUp:
    "PageUp"
  of skPageDown:
    "PageDown"
  of skHome:
    "Home"
  of skEnd:
    "End"
  of skFunction:
    "F" & $keyCombo.fnNum
  of skNone:
    ""

proc keyComboToString*(keyCombo: KeyCombo): string =
  ## Convert a KeyCombo to a string representation for macro recording
  ## This is the inverse of stringToKeyCombo
  if keyCombo.isSpecial:
    if keyCombo.special == skNone:
      return ""
    var prefix = ""
    if kmCtrl in keyCombo.modifiers:
      prefix.add("C-")
    if kmAlt in keyCombo.modifiers:
      prefix.add("M-")
    # skBackTab serializes as `<S-Tab>` regardless of explicit kmShift; for the
    # other specials kmShift is preserved (e.g. shift+arrow).
    if keyCombo.special == skBackTab:
      prefix.add("S-")
    elif kmShift in keyCombo.modifiers:
      prefix.add("S-")
    return "<" & prefix & specialKeyBodyString(keyCombo) & ">"
  else:
    # Handle modifiers
    var prefix = ""
    if kmCtrl in keyCombo.modifiers:
      prefix.add("C-")
    if kmAlt in keyCombo.modifiers:
      prefix.add("M-")
    if kmShift in keyCombo.modifiers:
      prefix.add("S-")
    if prefix.len > 0:
      return "<" & prefix & keyCombo.char & ">"
    else:
      return keyCombo.char

proc parseAngleBracketBody(key: string): Option[KeyCombo] =
  ## Parse the body inside `<...>` (modifier prefix already stripped) into a
  ## KeyCombo. Most names map to special keys (`Enter`, `Tab`, `F3`...), but
  ## `Space` is intentionally returned as a non-special char-combo so the
  ## resulting KeyCombo equals a literal space keypress. Returns `none` for
  ## unknown names.
  ##
  ## Kept in sync with the special-key table in `parseKeyCombo`: function key
  ## range is `F1..F12`, and `Space` round-trips with `keyComboToString`/event
  ## paths that emit the same form. Note: BackTab is intentionally NOT accepted
  ## here — write `<S-Tab>` instead, which `parseKeyCombo` also handles and
  ## which is what `keyComboToString(skBackTab)` emits.
  case key
  of "Space":
    some(KeyCombo(isSpecial: false, char: " ", modifiers: {}))
  of "Enter":
    some(KeyCombo(isSpecial: true, special: skEnter, fnNum: 0))
  of "Tab":
    some(KeyCombo(isSpecial: true, special: skTab, fnNum: 0))
  of "Backspace":
    some(KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0))
  of "Delete":
    some(KeyCombo(isSpecial: true, special: skDelete, fnNum: 0))
  of "Escape":
    some(KeyCombo(isSpecial: true, special: skEscape, fnNum: 0))
  of "Up":
    some(KeyCombo(isSpecial: true, special: skUp, fnNum: 0))
  of "Down":
    some(KeyCombo(isSpecial: true, special: skDown, fnNum: 0))
  of "Left":
    some(KeyCombo(isSpecial: true, special: skLeft, fnNum: 0))
  of "Right":
    some(KeyCombo(isSpecial: true, special: skRight, fnNum: 0))
  of "PageUp":
    some(KeyCombo(isSpecial: true, special: skPageUp, fnNum: 0))
  of "PageDown":
    some(KeyCombo(isSpecial: true, special: skPageDown, fnNum: 0))
  of "Home":
    some(KeyCombo(isSpecial: true, special: skHome, fnNum: 0))
  of "End":
    some(KeyCombo(isSpecial: true, special: skEnd, fnNum: 0))
  else:
    if key.len >= 2 and key.startsWith("F"):
      try:
        let num = parseInt(key[1 ..^ 1])
        if num >= 1 and num <= 12:
          some(KeyCombo(isSpecial: true, special: skFunction, fnNum: num))
        else:
          none(KeyCombo)
      except ValueError:
        none(KeyCombo)
    else:
      none(KeyCombo)

proc stringToKeyCombo*(s: string): Option[KeyCombo] =
  ## Convert a string back to a KeyCombo for macro playback
  ## This is the inverse of keyComboToString
  if s.len == 0:
    return none(KeyCombo)

  if s.startsWith("<") and s.endsWith(">"):
    # Special key or modifier key combination
    var key = s[1 ..< s.len - 1]

    # Parse modifiers (C-, M-, S-)
    var modifiers: set[KeyModifier] = {}
    while true:
      if key.startsWith("C-"):
        modifiers.incl(kmCtrl)
        key = key[2 ..^ 1]
      elif key.startsWith("M-"):
        modifiers.incl(kmAlt)
        key = key[2 ..^ 1]
      elif key.startsWith("S-"):
        modifiers.incl(kmShift)
        key = key[2 ..^ 1]
      else:
        break

    # Try special key names first so `<C-Up>` / `<S-Tab>` round-trip with the
    # right keycode rather than collapsing to a `char: "Up"` text combo.
    # Note: `parseAngleBracketBody("Space")` returns a non-special combo
    # (`char: " "`), so guard `.special` access with `isSpecial`.
    let specialOpt = parseAngleBracketBody(key)
    if specialOpt.isSome:
      var combo = specialOpt.get
      combo.modifiers = modifiers
      # `<S-Tab>` (and the redundant `<Tab>` + Shift) collapses to skBackTab to
      # match `parseKeyCombo` and `eventToKeyCombo`.
      if combo.isSpecial and combo.special == skTab and kmShift in combo.modifiers:
        combo.special = skBackTab
        combo.modifiers.excl(kmShift)
      # Reject unreliable Space combinations to stay aligned with
      # `parseKeyCombo`:
      # - `<S-Space>` is layout-dependent — terminals deliver shifted space
      #   as plain space without a Shift modifier.
      # - `<C-Space>` is not detectable in terminals at all (Ctrl + non-letter
      #   collapses to NUL or similar).
      # `<M-Space>` is fine because Alt+Space is reliably reported.
      if not combo.isSpecial and combo.char == " " and
          (kmShift in combo.modifiers or kmCtrl in combo.modifiers):
        return none(KeyCombo)
      return some(combo)

    # Fall back to modifier + character key (e.g. `<C-a>`, `<M-w>`).
    if modifiers != {}:
      return some(KeyCombo(isSpecial: false, char: key, modifiers: modifiers))
    return none(KeyCombo)
  else:
    # Regular character
    return some(KeyCombo(isSpecial: false, char: s, modifiers: {}))

proc newKeyBindingRegistry*(): KeyBindingRegistry =
  ## Create a new keybinding registry with default bindings
  result = KeyBindingRegistry(
    bindings: initTable[EditorMode, seq[KeyBinding]](),
    sequences: initTable[EditorMode, Table[seq[KeyCombo], Command]](),
    commandRegistry: initTable[string, Command](),
    sequenceState: KeySequenceState(
      keys: @[],
      possibleSequences: @[],
      pendingCommand: none(Command),
      waitingForChar: false,
      numericPrefix: "",
      hasNumericPrefix: false,
    ),
    runtimeMappings: initTable[EditorMode, seq[RuntimeKeyMapping]](),
    runtimeMappingState: RuntimeMappingState(keys: @[]),
    isReplayingMapping: false,
  )

  # Initialize empty binding lists for each mode
  for mode in EditorMode:
    result.bindings[mode] = @[]
    result.sequences[mode] = initTable[seq[KeyCombo], Command]()
    result.runtimeMappings[mode] = @[]

proc registerCommand*(registry: KeyBindingRegistry, command: Command) =
  ## Register a command that can be bound to keys
  registry.commandRegistry[command.name] = command

# Imported here (not at the top) because these sub-modules import this module
# for `Command`, `KeyBindingRegistry`, `ExecCmdlinePrefix`, `registerCommand`,
# and `bindKey` (string form, declared below) — the cycle resolves only after
# those symbols are declared.
import key_bindings/commands

proc bindKey*(
    registry: KeyBindingRegistry, mode: EditorMode, combo: KeyCombo, command: Command
) =
  ## Bind a key combination to a command in a specific mode
  let binding = KeyBinding(combo: combo, command: command, context: mode)

  if mode notin registry.bindings:
    registry.bindings[mode] = @[]

  # Remove any existing binding for this key combo
  registry.bindings[mode].keepItIf(it.combo != combo)

  # Add new binding
  registry.bindings[mode].add(binding)

proc bindSequence*(
    registry: KeyBindingRegistry,
    mode: EditorMode,
    sequence: seq[KeyCombo],
    command: Command,
) =
  ## Bind a key sequence to a command in a specific mode
  if mode notin registry.sequences:
    registry.sequences[mode] = initTable[seq[KeyCombo], Command]()

  var seqStr = ""
  for i, k in sequence:
    if i > 0:
      seqStr.add(", ")
    seqStr.add(
      if k.isSpecial:
        "<special>"
      else:
        "'" & k.char & "'" & " mods=" & $k.modifiers
    )
  logDebug(
    "keybind",
    "bindSequence: mode=" & $mode & " seq=[" & seqStr & "] cmd=" & command.name,
  )

  registry.sequences[mode][sequence] = command

proc bindKey*(
    registry: KeyBindingRegistry, mode: EditorMode, keyStr: string, commandName: string
) =
  ## Convenience method to bind using string representations
  ## Supports both single keys and sequences (e.g., "g g" for goto first line)

  # Check if this is a key sequence (contains spaces)
  if ' ' in keyStr:
    # Parse as sequence
    let parts = keyStr.split(' ')
    var sequence: seq[KeyCombo] = @[]

    for part in parts:
      let combo = parseKeyCombo(part)
      if combo.isNone:
        return # Invalid key in sequence
      sequence.add(combo.get)

    if commandName in registry.commandRegistry:
      let command = registry.commandRegistry[commandName]
      registry.bindSequence(mode, sequence, command)
  else:
    # Parse as single key
    let combo = parseKeyCombo(keyStr)
    if combo.isNone:
      return

    if commandName in registry.commandRegistry:
      let command = registry.commandRegistry[commandName]
      registry.bindKey(mode, combo.get, command)

# Imported here so the binding tables can call the string-form `bindKey`
# declared above.
import key_bindings/[normal_bindings, visual_bindings, insert_bindings]

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

proc clearRuntimeMappingState*(registry: KeyBindingRegistry) =
  ## Clear the runtime mapping key accumulator
  registry.runtimeMappingState.keys = @[]

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
    registry: KeyBindingRegistry, keyCombo: KeyCombo, mappings: seq[RuntimeKeyMapping]
): RuntimeMappingDecision =
  ## Decide what to do with `keyCombo` given the runtime mapping table for the
  ## current mode. The accumulator (`registry.runtimeMappingState`) is mutated
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
    if registry.runtimeMappingState.keys.len > 0:
      registry.clearRuntimeMappingState()
    return RuntimeMappingDecision(kind: rmdNoMatchPassThrough)

  registry.runtimeMappingState.keys.add(keyCombo)
  let accKeys = registry.runtimeMappingState.keys

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
    registry.clearRuntimeMappingState()
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
    registry.clearRuntimeMappingState()
    return RuntimeMappingDecision(kind: rmdNoMatchPassThrough)

  let flushed = accKeys
  registry.clearRuntimeMappingState()
  return RuntimeMappingDecision(kind: rmdNoMatchFlush, accumulatedKeys: flushed)

proc flushRuntimeMapping*(
    registry: KeyBindingRegistry, mappings: seq[RuntimeKeyMapping]
): RuntimeMappingFlushPlan =
  ## When the key-mapping timeout fires, decide how to flush the accumulator.
  ## Caller passes the appropriate mappings table for the current mode/overlay.
  ## The accumulator is cleared before returning (unless it was already empty).
  if registry.runtimeMappingState.keys.len == 0:
    return RuntimeMappingFlushPlan(kind: rmfNothing)

  let accKeys = registry.runtimeMappingState.keys
  var exactMatch: Option[RuntimeKeyMapping] = none(RuntimeKeyMapping)
  for m in mappings:
    if m.triggerKeys == accKeys:
      exactMatch = some(m)
      break

  registry.clearRuntimeMappingState()

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
