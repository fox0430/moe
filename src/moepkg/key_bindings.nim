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

import std/[tables, strutils, options, sequtils, hashes]

import pkg/celina

import types, modes, logger

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

  ## Registry for all key_bindings
  KeyBindingRegistry* = ref object
    bindings*: Table[EditorMode, seq[KeyBinding]]
    sequences*: Table[EditorMode, Table[seq[KeyCombo], Command]] ## Multi-key sequences
    commandRegistry*: Table[string, Command]
    sequenceState*: KeySequenceState ## Current sequence being built

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

  return some(combo)

proc keyComboToString*(keyCombo: KeyCombo): string =
  ## Convert a KeyCombo to a string representation for macro recording
  ## This is the inverse of stringToKeyCombo
  if keyCombo.isSpecial:
    case keyCombo.special
    of skEnter:
      return "<Enter>"
    of skTab:
      return "<Tab>"
    of skBackTab:
      return "<S-Tab>"
    of skBackspace:
      return "<Backspace>"
    of skDelete:
      return "<Delete>"
    of skEscape:
      return "<Escape>"
    of skUp:
      return "<Up>"
    of skDown:
      return "<Down>"
    of skLeft:
      return "<Left>"
    of skRight:
      return "<Right>"
    of skPageUp:
      return "<PageUp>"
    of skPageDown:
      return "<PageDown>"
    of skHome:
      return "<Home>"
    of skEnd:
      return "<End>"
    of skFunction:
      return "<F" & $keyCombo.fnNum & ">"
    of skNone:
      return ""
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

    # If we have modifiers, return a modified character key
    if modifiers != {}:
      return some(KeyCombo(isSpecial: false, char: key, modifiers: modifiers))

    # Handle special keys
    case key
    of "Enter":
      return some(KeyCombo(isSpecial: true, special: skEnter, fnNum: 0))
    of "Tab":
      return some(KeyCombo(isSpecial: true, special: skTab, fnNum: 0))
    of "Backspace":
      return some(KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0))
    of "Delete":
      return some(KeyCombo(isSpecial: true, special: skDelete, fnNum: 0))
    of "Escape":
      return some(KeyCombo(isSpecial: true, special: skEscape, fnNum: 0))
    of "Up":
      return some(KeyCombo(isSpecial: true, special: skUp, fnNum: 0))
    of "Down":
      return some(KeyCombo(isSpecial: true, special: skDown, fnNum: 0))
    of "Left":
      return some(KeyCombo(isSpecial: true, special: skLeft, fnNum: 0))
    of "Right":
      return some(KeyCombo(isSpecial: true, special: skRight, fnNum: 0))
    of "PageUp":
      return some(KeyCombo(isSpecial: true, special: skPageUp, fnNum: 0))
    of "PageDown":
      return some(KeyCombo(isSpecial: true, special: skPageDown, fnNum: 0))
    of "Home":
      return some(KeyCombo(isSpecial: true, special: skHome, fnNum: 0))
    of "End":
      return some(KeyCombo(isSpecial: true, special: skEnd, fnNum: 0))
    else:
      # Check for function keys
      if key.startsWith("F"):
        try:
          let num = parseInt(key[1 ..^ 1])
          return some(KeyCombo(isSpecial: true, special: skFunction, fnNum: num))
        except ValueError:
          return none(KeyCombo)
      else:
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
  )

  # Initialize empty binding lists for each mode
  for mode in EditorMode:
    result.bindings[mode] = @[]
    result.sequences[mode] = initTable[seq[KeyCombo], Command]()

proc registerCommand*(registry: KeyBindingRegistry, command: Command) =
  ## Register a command that can be bound to keys
  registry.commandRegistry[command.name] = command

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
  if registry.sequenceState.keys.len == 0 and not registry.sequenceState.waitingForChar and
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

  # Register basic motion commands
  registry.registerCommand(
    Command(
      name: "move-left",
      description: "Move cursor left",
      kind: ctMotion,
      motion: Motion.Left,
    )
  )

  registry.registerCommand(
    Command(
      name: "move-right",
      description: "Move cursor right",
      kind: ctMotion,
      motion: Motion.Right,
    )
  )

  registry.registerCommand(
    Command(
      name: "move-up", description: "Move cursor up", kind: ctMotion, motion: Motion.Up
    )
  )

  registry.registerCommand(
    Command(
      name: "move-down",
      description: "Move cursor down",
      kind: ctMotion,
      motion: Motion.Down,
    )
  )

  registry.registerCommand(
    Command(
      name: "page-up",
      description: "Scroll page up",
      kind: ctMotion,
      motion: Motion.PageUp,
    )
  )

  registry.registerCommand(
    Command(
      name: "page-down",
      description: "Scroll page down",
      kind: ctMotion,
      motion: Motion.PageDown,
    )
  )

  registry.registerCommand(
    Command(
      name: "half-page-up",
      description: "Scroll half page up",
      kind: ctMotion,
      motion: Motion.HalfPageUp,
    )
  )

  registry.registerCommand(
    Command(
      name: "half-page-down",
      description: "Scroll half page down",
      kind: ctMotion,
      motion: Motion.HalfPageDown,
    )
  )

  registry.registerCommand(
    Command(
      name: "line-home",
      description: "Move to beginning of line",
      kind: ctMotion,
      motion: Motion.Home,
    )
  )

  registry.registerCommand(
    Command(
      name: "line-first-non-blank",
      description: "Move to first non-whitespace character",
      kind: ctMotion,
      motion: Motion.FirstNonBlank,
    )
  )

  registry.registerCommand(
    Command(
      name: "line-last-non-blank",
      description: "Move to last non-whitespace character",
      kind: ctMotion,
      motion: Motion.LastNonBlank,
    )
  )

  registry.registerCommand(
    Command(
      name: "line-end",
      description: "Move to end of line",
      kind: ctMotion,
      motion: Motion.End,
    )
  )

  # Register sequence commands (mock for now)
  registry.registerCommand(
    Command(
      name: "goto-first-line",
      description: "Go to first line",
      kind: ctMotion,
      motion: Motion.FirstLine,
    )
  )

  registry.registerCommand(
    Command(
      name: "goto-last-line",
      description: "Go to last line",
      kind: ctMotion,
      motion: Motion.LastLine,
    )
  )

  # Viewport motion commands
  registry.registerCommand(
    Command(
      name: "viewport-high",
      description: "Move to top of viewport",
      kind: ctMotion,
      motion: Motion.ViewportHigh,
    )
  )

  registry.registerCommand(
    Command(
      name: "viewport-middle",
      description: "Move to middle of viewport",
      kind: ctMotion,
      motion: Motion.ViewportMiddle,
    )
  )

  registry.registerCommand(
    Command(
      name: "viewport-low",
      description: "Move to bottom of viewport",
      kind: ctMotion,
      motion: Motion.ViewportLow,
    )
  )

  registry.registerCommand(
    Command(
      name: "next-line-first-non-blank",
      description: "Move to next line's first non-whitespace character",
      kind: ctMotion,
      motion: Motion.NextLineFirstNonBlank,
    )
  )

  registry.registerCommand(
    Command(
      name: "previous-line-first-non-blank",
      description: "Move to previous line's first non-whitespace character",
      kind: ctMotion,
      motion: Motion.PreviousLineFirstNonBlank,
    )
  )

  # Word motion commands
  registry.registerCommand(
    Command(
      name: "word-forward",
      description: "Move to start of next word",
      kind: ctMotion,
      motion: Motion.WordForward,
    )
  )

  registry.registerCommand(
    Command(
      name: "word-backward",
      description: "Move to start of previous word",
      kind: ctMotion,
      motion: Motion.WordBackward,
    )
  )

  registry.registerCommand(
    Command(
      name: "word-end",
      description: "Move to end of next word",
      kind: ctMotion,
      motion: Motion.WordEnd,
    )
  )

  # Paragraph motion commands
  registry.registerCommand(
    Command(
      name: "paragraph-forward",
      description: "Move to next paragraph",
      kind: ctMotion,
      motion: Motion.ParagraphForward,
    )
  )

  registry.registerCommand(
    Command(
      name: "paragraph-backward",
      description: "Move to previous paragraph",
      kind: ctMotion,
      motion: Motion.ParagraphBackward,
    )
  )

  # Register undo/redo commands
  registry.registerCommand(
    Command(
      name: "undo",
      description: "Undo last change",
      kind: ctAction,
      commandId: "edit.undo",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "redo",
      description: "Redo last undone change",
      kind: ctAction,
      commandId: "edit.redo",
      args: @[],
    )
  )

  # Register increment/decrement number commands
  registry.registerCommand(
    Command(
      name: "increment-number",
      description: "Increment number at or after cursor",
      kind: ctAction,
      commandId: "edit.increment",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "decrement-number",
      description: "Decrement number at or after cursor",
      kind: ctAction,
      commandId: "edit.decrement",
      args: @[],
    )
  )

  # Register jump list commands
  registry.registerCommand(
    Command(
      name: "jump-back",
      description: "Jump to previous position in jump list",
      kind: ctAction,
      commandId: "jump.back",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "jump-forward",
      description: "Jump to next position in jump list",
      kind: ctAction,
      commandId: "jump.forward",
      args: @[],
    )
  )

  # Register search navigation commands
  registry.registerCommand(
    Command(
      name: "search-next",
      description: "Find next search result",
      kind: ctAction,
      commandId: "search.next",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "search-prev",
      description: "Find previous search result",
      kind: ctAction,
      commandId: "search.prev",
      args: @[],
    )
  )

  # Register additional search commands
  registry.registerCommand(
    Command(
      name: "search-word-forward",
      description: "Search for word under cursor forward (*)",
      kind: ctAction,
      commandId: "search.word.forward",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "search-word-backward",
      description: "Search for word under cursor backward (#)",
      kind: ctAction,
      commandId: "search.word.backward",
      args: @[],
    )
  )

  # Register bracket matching command
  registry.registerCommand(
    Command(
      name: "match-bracket",
      description: "Jump to matching bracket (%)",
      kind: ctMotion,
      motion: Motion.MatchBracket,
    )
  )

  # Normal mode default bindings
  registry.bindKey(EditorMode.Normal, "h", "move-left")
  registry.bindKey(EditorMode.Normal, "j", "move-down")
  registry.bindKey(EditorMode.Normal, "k", "move-up")
  registry.bindKey(EditorMode.Normal, "l", "move-right")
  registry.bindKey(EditorMode.Normal, "C-b", "page-up")
  registry.bindKey(EditorMode.Normal, "C-u", "half-page-up")
  registry.bindKey(EditorMode.Normal, "C-d", "half-page-down")
  registry.bindKey(EditorMode.Normal, "C-f", "page-down")
  registry.bindKey(EditorMode.Normal, "u", "undo")
  registry.bindKey(EditorMode.Normal, "C-r", "redo")
  registry.bindKey(EditorMode.Normal, "C-a", "increment-number")
  registry.bindKey(EditorMode.Normal, "C-x", "decrement-number")
  registry.bindKey(EditorMode.Normal, "C-o", "jump-back")
  registry.bindKey(EditorMode.Normal, "C-i", "jump-forward")
  registry.bindKey(EditorMode.Normal, "Tab", "jump-forward") # Tab = Ctrl-I in terminal
  registry.bindKey(EditorMode.Normal, "n", "search-next")
  registry.bindKey(EditorMode.Normal, "N", "search-prev")
  registry.bindKey(EditorMode.Normal, "*", "search-word-forward")
  registry.bindKey(EditorMode.Normal, "#", "search-word-backward")
  registry.bindKey(EditorMode.Normal, "%", "match-bracket")
  # Viewport motion bindings
  registry.bindKey(EditorMode.Normal, "H", "viewport-high")
  registry.bindKey(EditorMode.Normal, "M", "viewport-middle")
  registry.bindKey(EditorMode.Normal, "L", "viewport-low")
  # Word motion bindings
  registry.bindKey(EditorMode.Normal, "w", "word-forward")
  registry.bindKey(EditorMode.Normal, "b", "word-backward")
  registry.bindKey(EditorMode.Normal, "e", "word-end")

  # Paragraph motion bindings
  registry.bindKey(EditorMode.Normal, "}", "paragraph-forward")
  registry.bindKey(EditorMode.Normal, "{", "paragraph-backward")

  registry.bindKey(EditorMode.Normal, "0", "line-home")
  registry.bindKey(EditorMode.Normal, "^", "line-first-non-blank")
  registry.bindKey(EditorMode.Normal, "_", "line-first-non-blank")
  registry.bindKey(EditorMode.Normal, "$", "line-end")

  # Arrow key bindings for Normal mode
  registry.bindKey(
    EditorMode.Normal,
    KeyCombo(isSpecial: true, special: skLeft, fnNum: 0),
    registry.commandRegistry["move-left"],
  )
  registry.bindKey(
    EditorMode.Normal,
    KeyCombo(isSpecial: true, special: skRight, fnNum: 0),
    registry.commandRegistry["move-right"],
  )
  registry.bindKey(
    EditorMode.Normal,
    KeyCombo(isSpecial: true, special: skUp, fnNum: 0),
    registry.commandRegistry["move-up"],
  )
  registry.bindKey(
    EditorMode.Normal,
    KeyCombo(isSpecial: true, special: skDown, fnNum: 0),
    registry.commandRegistry["move-down"],
  )

  # Additional navigation keys for Normal mode
  registry.bindKey(
    EditorMode.Normal,
    KeyCombo(isSpecial: true, special: skHome, fnNum: 0),
    registry.commandRegistry["line-home"],
  )
  registry.bindKey(
    EditorMode.Normal,
    KeyCombo(isSpecial: true, special: skEnd, fnNum: 0),
    registry.commandRegistry["line-end"],
  )
  registry.bindKey(
    EditorMode.Normal,
    KeyCombo(isSpecial: true, special: skPageUp, fnNum: 0),
    registry.commandRegistry["page-up"],
  )
  registry.bindKey(
    EditorMode.Normal,
    KeyCombo(isSpecial: true, special: skPageDown, fnNum: 0),
    registry.commandRegistry["page-down"],
  )
  registry.bindKey(
    EditorMode.Normal,
    KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0),
    registry.commandRegistry["move-left"],
  )
  registry.bindKey(
    EditorMode.Normal,
    KeyCombo(isSpecial: true, special: skEnter, fnNum: 0),
    registry.commandRegistry["next-line-first-non-blank"],
  )
  registry.bindKey(
    EditorMode.Normal,
    KeyCombo(isSpecial: false, char: "+"),
    registry.commandRegistry["next-line-first-non-blank"],
  )
  registry.bindKey(
    EditorMode.Normal,
    KeyCombo(isSpecial: false, char: "-"),
    registry.commandRegistry["previous-line-first-non-blank"],
  )

  # Register additional commands for sequences
  registry.registerCommand(
    Command(
      name: "delete-word",
      description: "Delete word",
      kind: ctCustom,
      commandId: "delete.word",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "delete-line",
      description: "Delete line",
      kind: ctCustom,
      commandId: "delete.line",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "yank-line",
      description: "Yank (copy) line",
      kind: ctCustom,
      commandId: "yank.line",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "paste-after",
      description: "Paste after cursor",
      kind: ctCustom,
      commandId: "paste.after",
      args: @[],
    )
  )
  # Bind p key to paste-after (must be after registerCommand)
  registry.bindKey(EditorMode.Normal, "p", "paste-after")

  registry.registerCommand(
    Command(
      name: "paste-before",
      description: "Paste before cursor",
      kind: ctCustom,
      commandId: "paste.before",
      args: @[],
    )
  )
  # Bind P key to paste-before (must be after registerCommand)
  registry.bindKey(EditorMode.Normal, "P", "paste-before")

  registry.registerCommand(
    Command(
      name: "join-lines",
      description: "Join current line with next line",
      kind: ctCustom,
      commandId: "join.lines",
      args: @[],
    )
  )
  # Bind J key to join-lines (must be after registerCommand)
  registry.bindKey(EditorMode.Normal, "J", "join-lines")

  registry.registerCommand(
    Command(
      name: "show-char-info",
      description: "Show ASCII/Unicode value of character under cursor",
      kind: ctCustom,
      commandId: "show.char.info",
      args: @[],
    )
  )
  # Bind ga key sequence to show-char-info (must be after registerCommand)
  registry.bindKey(EditorMode.Normal, "g a", "show-char-info")

  # LSP - Go to definition (gd)
  registry.registerCommand(
    Command(
      name: "lsp-goto-definition",
      description: "Go to definition (LSP)",
      kind: ctCustom,
      commandId: "lsp.goto.definition",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "g d", "lsp-goto-definition")

  # LSP - Find references (gr)
  registry.registerCommand(
    Command(
      name: "lsp-find-references",
      description: "Find all references (LSP)",
      kind: ctCustom,
      commandId: "lsp.find.references",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "g r", "lsp-find-references")

  # LSP - Execute CodeLens (gL)
  registry.registerCommand(
    Command(
      name: "lsp-codelens-execute",
      description: "Execute CodeLens on current line (LSP)",
      kind: ctCustom,
      commandId: "lsp.codelens.execute",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "g L", "lsp-codelens-execute")

  # LSP - Go to declaration (gc)
  registry.registerCommand(
    Command(
      name: "lsp-goto-declaration",
      description: "Go to declaration (LSP)",
      kind: ctCustom,
      commandId: "lsp.goto.declaration",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "g c", "lsp-goto-declaration")

  # LSP - Go to type definition (gy)
  registry.registerCommand(
    Command(
      name: "lsp-goto-type-definition",
      description: "Go to type definition (LSP)",
      kind: ctCustom,
      commandId: "lsp.goto.type.definition",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "g y", "lsp-goto-type-definition")

  # LSP - Go to implementation (gi)
  registry.registerCommand(
    Command(
      name: "lsp-goto-implementation",
      description: "Go to implementation (LSP)",
      kind: ctCustom,
      commandId: "lsp.goto.implementation",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "g i", "lsp-goto-implementation")

  # LSP - Call hierarchy (gh)
  registry.registerCommand(
    Command(
      name: "lsp-call-hierarchy",
      description: "Show call hierarchy (LSP)",
      kind: ctCustom,
      commandId: "lsp.callhierarchy.incoming",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "g h", "lsp-call-hierarchy")

  # LSP - Hover (K)
  registry.registerCommand(
    Command(
      name: "lsp-hover",
      description: "Show hover information (LSP)",
      kind: ctCustom,
      commandId: "lsp.hover",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "K", "lsp-hover")

  # LSP - Rename (Space r)
  registry.registerCommand(
    Command(
      name: "lsp-rename",
      description: "Rename symbol (LSP)",
      kind: ctCustom,
      commandId: "lsp.rename",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "Space r", "lsp-rename")

  # LSP - Document symbol (Space o)
  registry.registerCommand(
    Command(
      name: "lsp-document-symbol",
      description: "Show document symbols (LSP)",
      kind: ctCustom,
      commandId: "lsp.document.symbol",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "Space o", "lsp-document-symbol")

  # LSP - Selection range (Ctrl-S)
  registry.registerCommand(
    Command(
      name: "lsp-selection-range",
      description: "Expand selection range (LSP)",
      kind: ctCustom,
      commandId: "lsp.selection.range",
      args: @[],
    )
  )
  registry.bindKey(
    EditorMode.Normal,
    KeyCombo(isSpecial: false, char: "s", modifiers: {kmCtrl}),
    registry.commandRegistry["lsp-selection-range"],
  )

  # LSP - Document link (g l)
  registry.registerCommand(
    Command(
      name: "lsp-document-link",
      description: "Follow document link at cursor (LSP)",
      kind: ctCustom,
      commandId: "lsp.document.link",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "g l", "lsp-document-link")

  # ZZ - Save and quit
  registry.registerCommand(
    Command(
      name: "save-and-quit",
      description: "Save file and quit",
      kind: ctAction,
      commandId: "file.save.and.quit",
      args: @[],
    )
  )
  # Bind ZZ key sequence to save-and-quit
  registry.bindKey(EditorMode.Normal, "Z Z", "save-and-quit")

  # ZQ - Quit without saving
  registry.registerCommand(
    Command(
      name: "quit-force",
      description: "Quit without saving",
      kind: ctAction,
      commandId: "file.quit.force",
      args: @[],
    )
  )
  # Bind ZQ key sequence to quit-force
  registry.bindKey(EditorMode.Normal, "Z Q", "quit-force")

  # Ctrl-W c - Close current window
  registry.registerCommand(
    Command(
      name: "close-window",
      description: "Close current window",
      kind: ctAction,
      commandId: "window.close",
      args: @[],
    )
  )
  # Bind Ctrl-W c key sequence to close-window
  registry.bindKey(EditorMode.Normal, "C-w c", "close-window")

  # Indent/dedent commands
  registry.registerCommand(
    Command(
      name: "indent-line",
      description: "Indent current line",
      kind: ctCustom,
      commandId: "indent.line",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "dedent-line",
      description: "Dedent current line",
      kind: ctCustom,
      commandId: "dedent.line",
      args: @[],
    )
  )

  # Bind >> and << sequences for indent/dedent
  registry.bindKey(EditorMode.Normal, "> >", "indent-line")
  registry.bindKey(EditorMode.Normal, "< <", "dedent-line")

  # Auto indent command (==)
  registry.registerCommand(
    Command(
      name: "autoindent-line",
      description: "Auto indent current line",
      kind: ctCustom,
      commandId: "autoindent.line",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "= =", "autoindent-line")

  # Scroll commands
  registry.registerCommand(
    Command(
      name: "scroll-cursor-top",
      description: "Scroll cursor to top of screen",
      kind: ctCustom,
      commandId: "scroll.cursor.top",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "scroll-cursor-center",
      description: "Scroll cursor to center of screen",
      kind: ctCustom,
      commandId: "scroll.cursor.center",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "scroll-cursor-bottom",
      description: "Scroll cursor to bottom of screen",
      kind: ctCustom,
      commandId: "scroll.cursor.bottom",
      args: @[],
    )
  )

  # Bind z commands (scroll)
  registry.bindKey(EditorMode.Normal, "z t", "scroll-cursor-top")
  registry.bindKey(EditorMode.Normal, "z z", "scroll-cursor-center")
  registry.bindKey(EditorMode.Normal, "z .", "scroll-cursor-center")
  registry.bindKey(EditorMode.Normal, "z b", "scroll-cursor-bottom")

  # Fold commands
  registry.registerCommand(
    Command(
      name: "fold-open",
      description: "Open fold at cursor",
      kind: ctCustom,
      commandId: "fold.open",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "fold-close",
      description: "Close fold at cursor",
      kind: ctCustom,
      commandId: "fold.close",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "fold-toggle",
      description: "Toggle fold at cursor",
      kind: ctCustom,
      commandId: "fold.toggle",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "fold-open-all",
      description: "Open all folds",
      kind: ctCustom,
      commandId: "fold.open.all",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "fold-close-all",
      description: "Close all folds",
      kind: ctCustom,
      commandId: "fold.close.all",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "fold-create",
      description: "Create fold from selection",
      kind: ctCustom,
      commandId: "fold.create",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "fold-delete",
      description: "Delete fold at cursor",
      kind: ctCustom,
      commandId: "fold.delete",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "fold-delete-all",
      description: "Delete all folds",
      kind: ctCustom,
      commandId: "fold.delete.all",
      args: @[],
    )
  )

  # Bind z commands (fold)
  registry.bindKey(EditorMode.Normal, "z o", "fold-open")
  registry.bindKey(EditorMode.Normal, "z c", "fold-close")
  registry.bindKey(EditorMode.Normal, "z a", "fold-toggle")
  registry.bindKey(EditorMode.Normal, "z d", "fold-delete")
  registry.bindKey(EditorMode.Normal, "z D", "fold-delete-all")
  registry.bindKey(EditorMode.Normal, "z R", "fold-open-all")
  registry.bindKey(EditorMode.Normal, "z M", "fold-close-all")
  # zf is bound in visual mode below

  # QuickRun command
  registry.registerCommand(
    Command(
      name: "quickrun",
      description: "Run current buffer",
      kind: ctCustom,
      commandId: "quickrun",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "\\ r", "quickrun")

  # Operator commands
  registry.registerCommand(
    Command(
      name: "operator-delete",
      description: "Delete operator",
      kind: ctCustom,
      commandId: "operator.delete",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "d", "operator-delete")

  registry.registerCommand(
    Command(
      name: "operator-change",
      description: "Change operator",
      kind: ctCustom,
      commandId: "operator.change",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "c", "operator-change")

  registry.registerCommand(
    Command(
      name: "operator-yank",
      description: "Yank operator",
      kind: ctCustom,
      commandId: "operator.yank",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "y", "operator-yank")

  # D - Delete to end of line
  registry.registerCommand(
    Command(
      name: "delete-to-end",
      description: "Delete to end of line",
      kind: ctCustom,
      commandId: "operator.delete.to.end",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "D", "delete-to-end")

  # C - Change to end of line
  registry.registerCommand(
    Command(
      name: "change-to-end",
      description: "Change to end of line",
      kind: ctCustom,
      commandId: "operator.change.to.end",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "C", "change-to-end")

  # x - Delete character at cursor
  registry.registerCommand(
    Command(
      name: "delete-char",
      description: "Delete character at cursor",
      kind: ctCustom,
      commandId: "delete.char",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "x", "delete-char")

  # X - Delete character before cursor
  registry.registerCommand(
    Command(
      name: "delete-char-before",
      description: "Delete character before cursor",
      kind: ctCustom,
      commandId: "delete.char.before",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "X", "delete-char-before")

  # s - Substitute character at cursor
  registry.registerCommand(
    Command(
      name: "substitute-char",
      description: "Substitute character at cursor",
      kind: ctCustom,
      commandId: "substitute.char",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "s", "substitute-char")
  # Note: "c u" sequence removed because it conflicts with operator+motion
  # In Vim, "cu" is change operator + u motion, not substitute-char

  # S - Substitute line
  registry.registerCommand(
    Command(
      name: "substitute-line",
      description: "Substitute line",
      kind: ctCustom,
      commandId: "substitute.line",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "S", "substitute-line")

  # ~ - Toggle case
  registry.registerCommand(
    Command(
      name: "toggle-case",
      description: "Toggle case of character at cursor",
      kind: ctCustom,
      commandId: "toggle.case",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "~", "toggle-case")

  # . - Repeat last change
  registry.registerCommand(
    Command(
      name: "repeat-last-change",
      description: "Repeat last change",
      kind: ctAction,
      commandId: "edit.repeat",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, ".", "repeat-last-change")

  # Text object commands
  registry.registerCommand(
    Command(
      name: "textobject-inner",
      description: "Inner text object",
      kind: ctCustom,
      commandId: "textobject.inner",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "i", "textobject-inner")

  registry.registerCommand(
    Command(
      name: "textobject-around",
      description: "Around text object",
      kind: ctCustom,
      commandId: "textobject.around",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "a", "textobject-around")

  # Text object kinds
  # Note: w, b, e are now motion commands, not text objects
  # Text objects are triggered by i/a modifiers (iw, aw, etc.)
  registry.registerCommand(
    Command(
      name: "textobject-word",
      description: "Word text object",
      kind: ctCustom,
      commandId: "textobject.word",
      args: @[],
    )
  )
  # registry.bindKey(EditorMode.Normal, "w", "textobject-word")  # Removed - w is a motion

  registry.registerCommand(
    Command(
      name: "textobject-quote-double",
      description: "Double quote text object",
      kind: ctCustom,
      commandId: "textobject.quote.double",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "\"", "textobject-quote-double")

  registry.registerCommand(
    Command(
      name: "textobject-quote-single",
      description: "Single quote text object",
      kind: ctCustom,
      commandId: "textobject.quote.single",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "'", "textobject-quote-single")

  registry.registerCommand(
    Command(
      name: "textobject-paren",
      description: "Parenthesis text object",
      kind: ctCustom,
      commandId: "textobject.paren",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "(", "textobject-paren")
  registry.bindKey(EditorMode.Normal, ")", "textobject-paren")

  registry.registerCommand(
    Command(
      name: "textobject-bracket",
      description: "Bracket text object",
      kind: ctCustom,
      commandId: "textobject.bracket",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "[", "textobject-bracket")
  registry.bindKey(EditorMode.Normal, "]", "textobject-bracket")

  registry.registerCommand(
    Command(
      name: "textobject-brace",
      description: "Brace text object",
      kind: ctCustom,
      commandId: "textobject.brace",
      args: @[],
    )
  )
  # Note: { and } are bound to paragraph motion in Normal mode (see above)
  # They are used as text objects only in operator-pending mode (e.g., di{)

  registry.registerCommand(
    Command(
      name: "change-word",
      description: "Change word",
      kind: ctCustom,
      commandId: "change.word",
      args: @[],
    )
  )

  # Register find/till commands that require character input
  registry.registerCommand(
    Command(
      name: "find-char",
      description: "Find character forward",
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: false,
      targetChar: "", # Will be filled when user presses a key
    )
  )

  registry.registerCommand(
    Command(
      name: "find-char-backward",
      description: "Find character backward",
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: true,
      targetChar: "", # Will be filled when user presses a key
    )
  )

  registry.registerCommand(
    Command(
      name: "till-char",
      description: "Till character forward",
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: false,
      targetChar: "", # Will be filled when user presses a key
    )
  )

  registry.registerCommand(
    Command(
      name: "till-char-backward",
      description: "Till character backward",
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: true,
      targetChar: "", # Will be filled when user presses a key
    )
  )

  registry.registerCommand(
    Command(
      name: "replace-char",
      description: "Replace character",
      kind: ctOperatorPending,
      operatorType: "replace",
      reverse: false,
      targetChar: "", # Will be filled when user presses a key
    )
  )

  # Bind find/till commands
  registry.bindKey(EditorMode.Normal, "f", "find-char")
  registry.bindKey(EditorMode.Normal, "F", "find-char-backward")
  registry.bindKey(EditorMode.Normal, "t", "till-char")
  registry.bindKey(EditorMode.Normal, "T", "till-char-backward")
  registry.bindKey(EditorMode.Normal, "r", "replace-char")

  # Buffer switching commands (gt, gT)
  registry.registerCommand(
    Command(
      name: "buffer-next-tab",
      description: "Switch to next buffer tab",
      kind: ctAction,
      commandId: "buffer.next.tab",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "buffer-prev-tab",
      description: "Switch to previous buffer tab",
      kind: ctAction,
      commandId: "buffer.prev.tab",
      args: @[],
    )
  )
  registry.bindKey(EditorMode.Normal, "g t", "buffer-next-tab")
  registry.bindKey(EditorMode.Normal, "g T", "buffer-prev-tab")

  # Sequence bindings - Vim-style
  registry.bindKey(EditorMode.Normal, "g g", "goto-first-line") # Go to first line
  registry.bindKey(EditorMode.Normal, "g _", "line-last-non-blank")
    # Go to last non-blank character
  registry.bindKey(EditorMode.Normal, "G", "goto-last-line") # Go to last line
  # Note: dd, yy, cc are handled by operator doubling in handleOperatorDelete/Yank/Change
  # When 'd' is pressed twice, the operator handler detects it and executes line operation
  # This allows d+motion (like dw, d2w) to work via operator+motion system

  # Register mode switching commands
  registry.registerCommand(
    Command(
      name: "switch-to-insert",
      description: "Switch to insert mode",
      kind: ctModeSwitch,
      targetMode: EditorMode.Insert,
    )
  )

  registry.registerCommand(
    Command(
      name: "switch-to-normal",
      description: "Switch to normal mode",
      kind: ctModeSwitch,
      targetMode: EditorMode.Normal,
    )
  )

  registry.registerCommand(
    Command(
      name: "switch-to-visual",
      description: "Switch to visual mode",
      kind: ctModeSwitch,
      targetMode: EditorMode.Visual,
    )
  )

  registry.registerCommand(
    Command(
      name: "switch-to-replace",
      description: "Switch to replace mode",
      kind: ctModeSwitch,
      targetMode: EditorMode.Replace,
    )
  )

  # Register o and O commands
  registry.registerCommand(
    Command(
      name: "open-line-below",
      description: "Open new line below and enter insert mode",
      kind: ctAction,
      commandId: "insert.line.below",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "open-line-above",
      description: "Open new line above and enter insert mode",
      kind: ctAction,
      commandId: "insert.line.above",
      args: @[],
    )
  )

  # Register a and A commands
  registry.registerCommand(
    Command(
      name: "append",
      description: "Append after cursor",
      kind: ctAction,
      commandId: "insert.append",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "append-end",
      description: "Append at end of line",
      kind: ctAction,
      commandId: "insert.append.end",
      args: @[],
    )
  )

  # Register I command
  registry.registerCommand(
    Command(
      name: "insert-first-non-blank",
      description: "Insert at first non-blank character",
      kind: ctAction,
      commandId: "insert.first.non.blank",
      args: @[],
    )
  )

  # Normal mode to Insert mode transitions
  # Note: 'i' and 'a' are bound to textobject-inner and textobject-around above
  # Those handlers check for pending operator and either:
  # - Set text object modifier (when operator is pending, e.g., after 'd')
  # - Enter Insert/Append mode (when no operator is pending)
  registry.bindKey(EditorMode.Normal, "I", "insert-first-non-blank")
    # Enter insert mode at first non-blank character
  registry.bindKey(EditorMode.Normal, "A", "append-end") # Enter insert mode at line end
  registry.bindKey(EditorMode.Normal, "o", "open-line-below")
    # Enter insert mode on new line below
  registry.bindKey(EditorMode.Normal, "O", "open-line-above")
    # Enter insert mode on new line above

  # Add binding for Command mode
  registry.registerCommand(
    Command(
      name: "switch-to-command",
      description: "Switch to command mode",
      kind: ctOverlaySwitch,
      targetOverlay: okCommand,
    )
  )
  registry.bindKey(EditorMode.Normal, ":", "switch-to-command")

  # Add binding for Search mode (forward)
  registry.registerCommand(
    Command(
      name: "switch-to-search",
      description: "Switch to search mode (forward)",
      kind: ctOverlaySwitch,
      targetOverlay: okSearch,
    )
  )
  registry.bindKey(EditorMode.Normal, "/", "switch-to-search")

  # Add binding for Search mode (backward)
  registry.registerCommand(
    Command(
      name: "switch-to-search-backward",
      description: "Switch to search mode (backward)",
      kind: ctOverlaySwitch,
      targetOverlay: okSearch,
    )
  )
  registry.bindKey(EditorMode.Normal, "?", "switch-to-search-backward")

  # Visual mode switches
  registry.registerCommand(
    Command(
      name: "switch-to-visual-block",
      description: "Switch to visual block mode",
      kind: ctModeSwitch,
      targetMode: EditorMode.VisualBlock,
    )
  )
  registry.registerCommand(
    Command(
      name: "switch-to-visual-line",
      description: "Switch to visual line mode",
      kind: ctModeSwitch,
      targetMode: EditorMode.VisualLine,
    )
  )
  registry.bindKey(EditorMode.Normal, "v", "switch-to-visual")
    # Enter visual mode (character-wise)
  registry.bindKey(EditorMode.Normal, "V", "switch-to-visual-line")
    # Enter visual line mode
  registry.bindKey(EditorMode.Normal, "C-v", "switch-to-visual-block")
    # Enter visual block mode
  registry.bindKey(EditorMode.Normal, "R", "switch-to-replace") # Enter replace mode

  # Visual mode commands
  registry.registerCommand(
    Command(
      name: "visual-move-left",
      description: "Move left in visual mode",
      kind: ctAction,
      commandId: "visual.move.left",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-move-right",
      description: "Move right in visual mode",
      kind: ctAction,
      commandId: "visual.move.right",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-move-up",
      description: "Move up in visual mode",
      kind: ctAction,
      commandId: "visual.move.up",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-move-down",
      description: "Move down in visual mode",
      kind: ctAction,
      commandId: "visual.move.down",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-delete",
      description: "Delete visual selection",
      kind: ctAction,
      commandId: "visual.delete",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-yank",
      description: "Yank visual selection",
      kind: ctAction,
      commandId: "visual.yank",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-indent",
      description: "Indent visual selection",
      kind: ctAction,
      commandId: "visual.indent",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-dedent",
      description: "Dedent visual selection",
      kind: ctAction,
      commandId: "visual.dedent",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-lowercase",
      description: "Convert visual selection to lowercase",
      kind: ctAction,
      commandId: "visual.lowercase",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-uppercase",
      description: "Convert visual selection to uppercase",
      kind: ctAction,
      commandId: "visual.uppercase",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "visual-toggle-case",
      description: "Toggle case of visual selection",
      kind: ctAction,
      commandId: "visual.togglecase",
      args: @[],
    )
  )

  registry.registerCommand(
    Command(
      name: "visual-replace-char",
      description: "Replace visual selection with character",
      kind: ctOperatorPending,
      operatorType: "visual-replace",
      reverse: false,
      targetChar: "", # Will be filled when user presses a key
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-joinlines",
      description: "Join lines in visual selection",
      kind: ctAction,
      commandId: "visual.joinlines",
      args: @[],
    )
  )

  # Visual mode motion commands
  registry.registerCommand(
    Command(
      name: "visual-move-home",
      description: "Move to beginning of line in visual mode",
      kind: ctAction,
      commandId: "visual.move.home",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-move-end",
      description: "Move to end of line in visual mode",
      kind: ctAction,
      commandId: "visual.move.end",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-move-firstnonblank",
      description: "Move to first non-blank character in visual mode",
      kind: ctAction,
      commandId: "visual.move.firstnonblank",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-move-firstline",
      description: "Move to first line in visual mode",
      kind: ctAction,
      commandId: "visual.move.firstline",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-move-lastline",
      description: "Move to last line in visual mode",
      kind: ctAction,
      commandId: "visual.move.lastline",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-move-word",
      description: "Move to next word in visual mode",
      kind: ctAction,
      commandId: "visual.move.word",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-move-word-back",
      description: "Move to previous word in visual mode",
      kind: ctAction,
      commandId: "visual.move.word.back",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-move-word-end",
      description: "Move to end of word in visual mode",
      kind: ctAction,
      commandId: "visual.move.word.end",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-move-paragraph-forward",
      description: "Move to next paragraph in visual mode",
      kind: ctAction,
      commandId: "visual.move.paragraph.forward",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-move-paragraph-backward",
      description: "Move to previous paragraph in visual mode",
      kind: ctAction,
      commandId: "visual.move.paragraph.backward",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-swap-selection",
      description: "Swap cursor to other end of selection",
      kind: ctAction,
      commandId: "visual.swap.selection",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-to-insert",
      description: "Enter insert mode from visual selection",
      kind: ctAction,
      commandId: "visual.to.insert",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-change",
      description: "Delete selection and enter insert mode",
      kind: ctAction,
      commandId: "visual.change",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-block-append",
      description: "Append after visual block selection",
      kind: ctAction,
      commandId: "visual.block.append",
      args: @[],
    )
  )
  registry.registerCommand(
    Command(
      name: "visual-paste",
      description: "Delete selection and paste register content",
      kind: ctAction,
      commandId: "visual.paste",
      args: @[],
    )
  )

  # Visual mode key bindings (character-wise)
  registry.bindKey(EditorMode.Visual, "h", "visual-move-left")
  registry.bindKey(EditorMode.Visual, "l", "visual-move-right")
  registry.bindKey(EditorMode.Visual, "j", "visual-move-down")
  registry.bindKey(EditorMode.Visual, "k", "visual-move-up")
  registry.bindKey(EditorMode.Visual, "0", "visual-move-home")
  registry.bindKey(EditorMode.Visual, "$", "visual-move-end")
  registry.bindKey(EditorMode.Visual, "^", "visual-move-firstnonblank")
  registry.bindKey(EditorMode.Visual, "g g", "visual-move-firstline")
  registry.bindKey(EditorMode.Visual, "G", "visual-move-lastline")
  registry.bindKey(EditorMode.Visual, "w", "visual-move-word")
  registry.bindKey(EditorMode.Visual, "b", "visual-move-word-back")
  registry.bindKey(EditorMode.Visual, "e", "visual-move-word-end")
  registry.bindKey(EditorMode.Visual, "}", "visual-move-paragraph-forward")
  registry.bindKey(EditorMode.Visual, "{", "visual-move-paragraph-backward")
  registry.bindKey(EditorMode.Visual, "I", "visual-to-insert")
  registry.bindKey(EditorMode.Visual, "d", "visual-delete")
  registry.bindKey(EditorMode.Visual, "x", "visual-delete")
  registry.bindKey(EditorMode.Visual, "y", "visual-yank")
  registry.bindKey(EditorMode.Visual, ">", "visual-indent")
  registry.bindKey(EditorMode.Visual, "<", "visual-dedent")
  registry.bindKey(EditorMode.Visual, "u", "visual-lowercase")
  registry.bindKey(EditorMode.Visual, "U", "visual-uppercase")
  registry.bindKey(EditorMode.Visual, "~", "visual-toggle-case")
  registry.bindKey(EditorMode.Visual, "r", "visual-replace-char")
  registry.bindKey(EditorMode.Visual, "J", "visual-joinlines")
  registry.bindKey(EditorMode.Visual, "c", "visual-change")
  registry.bindKey(EditorMode.Visual, "o", "visual-swap-selection")
  registry.bindKey(EditorMode.Visual, "p", "visual-paste")
  registry.bindKey(EditorMode.Visual, "P", "visual-paste")
  registry.bindKey(EditorMode.Visual, "z f", "fold-create") # Create fold from selection
  registry.bindKey(EditorMode.Visual, "Escape", "switch-to-normal") # Exit to normal mode
  registry.bindKey(EditorMode.Visual, "C-c", "switch-to-normal") # Exit to normal mode
  registry.bindKey(EditorMode.Visual, "C-a", "increment-number") # Increase number
  registry.bindKey(EditorMode.Visual, "C-x", "decrement-number") # Decrease number
  registry.bindKey(
    EditorMode.Visual,
    KeyCombo(isSpecial: false, char: "s", modifiers: {kmCtrl}),
    registry.commandRegistry["lsp-selection-range"],
  ) # LSP selection range
  # Arrow keys and other navigation aliases
  registry.bindKey(EditorMode.Visual, "Left", "visual-move-left")
  registry.bindKey(EditorMode.Visual, "Right", "visual-move-right")
  registry.bindKey(EditorMode.Visual, "Up", "visual-move-up")
  registry.bindKey(EditorMode.Visual, "Down", "visual-move-down")
  registry.bindKey(EditorMode.Visual, "Home", "visual-move-home")
  registry.bindKey(EditorMode.Visual, "End", "visual-move-end")
  registry.bindKey(EditorMode.Visual, "Backspace", "visual-move-left")
  registry.bindKey(EditorMode.Visual, "Enter", "visual-move-down")

  # Visual block mode key bindings (share most bindings with Visual mode via fallback)
  registry.bindKey(EditorMode.VisualBlock, "h", "visual-move-left")
  registry.bindKey(EditorMode.VisualBlock, "l", "visual-move-right")
  registry.bindKey(EditorMode.VisualBlock, "j", "visual-move-down")
  registry.bindKey(EditorMode.VisualBlock, "k", "visual-move-up")
  registry.bindKey(EditorMode.VisualBlock, "0", "visual-move-home")
  registry.bindKey(EditorMode.VisualBlock, "$", "visual-move-end")
  registry.bindKey(EditorMode.VisualBlock, "^", "visual-move-firstnonblank")
  registry.bindKey(EditorMode.VisualBlock, "g g", "visual-move-firstline")
  registry.bindKey(EditorMode.VisualBlock, "G", "visual-move-lastline")
  registry.bindKey(EditorMode.VisualBlock, "w", "visual-move-word")
  registry.bindKey(EditorMode.VisualBlock, "b", "visual-move-word-back")
  registry.bindKey(EditorMode.VisualBlock, "e", "visual-move-word-end")
  registry.bindKey(EditorMode.VisualBlock, "}", "visual-move-paragraph-forward")
  registry.bindKey(EditorMode.VisualBlock, "{", "visual-move-paragraph-backward")
  registry.bindKey(EditorMode.VisualBlock, "I", "visual-to-insert")
  registry.bindKey(EditorMode.VisualBlock, "A", "visual-block-append")
  registry.bindKey(EditorMode.VisualBlock, "d", "visual-delete")
  registry.bindKey(EditorMode.VisualBlock, "x", "visual-delete")
  registry.bindKey(EditorMode.VisualBlock, "y", "visual-yank")
  registry.bindKey(EditorMode.VisualBlock, ">", "visual-indent")
  registry.bindKey(EditorMode.VisualBlock, "<", "visual-dedent")
  registry.bindKey(EditorMode.VisualBlock, "u", "visual-lowercase")
  registry.bindKey(EditorMode.VisualBlock, "U", "visual-uppercase")
  registry.bindKey(EditorMode.VisualBlock, "~", "visual-toggle-case")
  registry.bindKey(EditorMode.VisualBlock, "r", "visual-replace-char")
  registry.bindKey(EditorMode.VisualBlock, "J", "visual-joinlines")
  registry.bindKey(EditorMode.VisualBlock, "c", "visual-change")
  registry.bindKey(EditorMode.VisualBlock, "o", "visual-swap-selection")
  registry.bindKey(EditorMode.VisualBlock, "p", "visual-paste")
  registry.bindKey(EditorMode.VisualBlock, "P", "visual-paste")
  registry.bindKey(EditorMode.VisualBlock, "z f", "fold-create")
    # Create fold from selection
  registry.bindKey(EditorMode.VisualBlock, "Escape", "switch-to-normal")
  registry.bindKey(EditorMode.VisualBlock, "C-c", "switch-to-normal")
  registry.bindKey(EditorMode.VisualBlock, "C-a", "increment-number") # Increase number
  registry.bindKey(EditorMode.VisualBlock, "C-x", "decrement-number") # Decrease number
  registry.bindKey(
    EditorMode.VisualBlock,
    KeyCombo(isSpecial: false, char: "s", modifiers: {kmCtrl}),
    registry.commandRegistry["lsp-selection-range"],
  ) # LSP selection range
  # Arrow keys and other navigation aliases
  registry.bindKey(EditorMode.VisualBlock, "Left", "visual-move-left")
  registry.bindKey(EditorMode.VisualBlock, "Right", "visual-move-right")
  registry.bindKey(EditorMode.VisualBlock, "Up", "visual-move-up")
  registry.bindKey(EditorMode.VisualBlock, "Down", "visual-move-down")
  registry.bindKey(EditorMode.VisualBlock, "Home", "visual-move-home")
  registry.bindKey(EditorMode.VisualBlock, "End", "visual-move-end")
  registry.bindKey(EditorMode.VisualBlock, "Backspace", "visual-move-left")
  registry.bindKey(EditorMode.VisualBlock, "Enter", "visual-move-down")

  # Visual line mode key bindings
  registry.bindKey(EditorMode.VisualLine, "h", "visual-move-left")
  registry.bindKey(EditorMode.VisualLine, "l", "visual-move-right")
  registry.bindKey(EditorMode.VisualLine, "j", "visual-move-down")
  registry.bindKey(EditorMode.VisualLine, "k", "visual-move-up")
  registry.bindKey(EditorMode.VisualLine, "0", "visual-move-home")
  registry.bindKey(EditorMode.VisualLine, "$", "visual-move-end")
  registry.bindKey(EditorMode.VisualLine, "^", "visual-move-firstnonblank")
  registry.bindKey(EditorMode.VisualLine, "g g", "visual-move-firstline")
  registry.bindKey(EditorMode.VisualLine, "G", "visual-move-lastline")
  registry.bindKey(EditorMode.VisualLine, "w", "visual-move-word")
  registry.bindKey(EditorMode.VisualLine, "b", "visual-move-word-back")
  registry.bindKey(EditorMode.VisualLine, "e", "visual-move-word-end")
  registry.bindKey(EditorMode.VisualLine, "}", "visual-move-paragraph-forward")
  registry.bindKey(EditorMode.VisualLine, "{", "visual-move-paragraph-backward")
  registry.bindKey(EditorMode.VisualLine, "I", "visual-to-insert")
  registry.bindKey(EditorMode.VisualLine, "d", "visual-delete")
  registry.bindKey(EditorMode.VisualLine, "x", "visual-delete")
  registry.bindKey(EditorMode.VisualLine, "y", "visual-yank")
  registry.bindKey(EditorMode.VisualLine, ">", "visual-indent")
  registry.bindKey(EditorMode.VisualLine, "<", "visual-dedent")
  registry.bindKey(EditorMode.VisualLine, "u", "visual-lowercase")
  registry.bindKey(EditorMode.VisualLine, "U", "visual-uppercase")
  registry.bindKey(EditorMode.VisualLine, "~", "visual-toggle-case")
  registry.bindKey(EditorMode.VisualLine, "r", "visual-replace-char")
  registry.bindKey(EditorMode.VisualLine, "J", "visual-joinlines")
  registry.bindKey(EditorMode.VisualLine, "c", "visual-change")
  registry.bindKey(EditorMode.VisualLine, "o", "visual-swap-selection")
  registry.bindKey(EditorMode.VisualLine, "p", "visual-paste")
  registry.bindKey(EditorMode.VisualLine, "P", "visual-paste")
  registry.bindKey(EditorMode.VisualLine, "z f", "fold-create")
    # Create fold from selection
  registry.bindKey(EditorMode.VisualLine, "Escape", "switch-to-normal")
  registry.bindKey(EditorMode.VisualLine, "C-c", "switch-to-normal")
  registry.bindKey(EditorMode.VisualLine, "C-a", "increment-number") # Increase number
  registry.bindKey(EditorMode.VisualLine, "C-x", "decrement-number") # Decrease number
  registry.bindKey(
    EditorMode.VisualLine,
    KeyCombo(isSpecial: false, char: "s", modifiers: {kmCtrl}),
    registry.commandRegistry["lsp-selection-range"],
  ) # LSP selection range
  # Arrow keys and other navigation aliases
  registry.bindKey(EditorMode.VisualLine, "Left", "visual-move-left")
  registry.bindKey(EditorMode.VisualLine, "Right", "visual-move-right")
  registry.bindKey(EditorMode.VisualLine, "Up", "visual-move-up")
  registry.bindKey(EditorMode.VisualLine, "Down", "visual-move-down")
  registry.bindKey(EditorMode.VisualLine, "Home", "visual-move-home")
  registry.bindKey(EditorMode.VisualLine, "End", "visual-move-end")
  registry.bindKey(EditorMode.VisualLine, "Backspace", "visual-move-left")
  registry.bindKey(EditorMode.VisualLine, "Enter", "visual-move-down")

  # Insert mode key bindings
  registry.bindKey(EditorMode.Insert, "Escape", "switch-to-normal") # Exit to normal mode
  registry.bindKey(EditorMode.Insert, "C-c", "switch-to-normal") # Exit to normal mode

  # Replace mode key bindings
  registry.bindKey(EditorMode.Replace, "Escape", "switch-to-normal")
    # Exit to normal mode
  registry.bindKey(EditorMode.Replace, "C-c", "switch-to-normal") # Exit to normal mode

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
    if combo.isSpecial:
      combo.modifiers.incl(kmShift)

  logDebug(
    "keybind",
    "eventToKeyCombo: isSpecial=" & $combo.isSpecial & " char=" &
      (if not combo.isSpecial: combo.char else: "<special>") & " modifiers=" &
      $combo.modifiers & " event.key.modifiers=" & $event.key.modifiers,
  )

  return some(combo)
