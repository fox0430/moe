#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import types, modes

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
    ctTextObject ## Text object operations
    ctOperator ## Vim-style operators (delete, yank, etc)
    ctOperatorPending ## Operators that require additional input (f, t, r, etc)
    ctCustom ## User-defined commands

  ## A command that can be executed
  Command* = object
    name*: string
    description*: string
    case kind*: CommandType
    of ctMotion:
      motion*: Motion
    of ctModeSwitch:
      targetMode*: EditorMode
    of ctOperatorPending:
      operatorType*: string ## "find", "till", "replace", etc
      reverse*: bool ## For F, T (backwards versions)
      targetChar*: string ## The character to find/till/replace
    of ctAction, ctTextObject, ctOperator, ctCustom:
      commandId*: string # Will be converted to CommandId in commandregistry
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

  ## Registry for all keybindings
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
  return some(combo)

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
  if registry.sequenceState.hasNumericPrefix and
      registry.sequenceState.numericPrefix.len > 0:
    try:
      let num = parseInt(registry.sequenceState.numericPrefix)
      return if num > 0: num else: 1
    except ValueError:
      return 1
  else:
    return 1

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

  # Check if we're waiting for an arbitrary character (f, t, r commands)
  if registry.sequenceState.waitingForChar and
      registry.sequenceState.pendingCommand.isSome:
    let pendingCmd = registry.sequenceState.pendingCommand.get

    # Create the final command with the character
    if not combo.isSpecial and combo.modifiers == {}:
      # Set the target character
      var finalCommand = pendingCmd
      finalCommand.targetChar = combo.char
      registry.clearSequence()
      return some(finalCommand)
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
    if registry.sequenceState.keys.len > 0 or registry.sequenceState.waitingForChar:
      registry.clearSequence()
      return none(Command) # Sequence cancelled
    # If no sequence active, treat ESC as normal key

  # Add current key to sequence
  registry.sequenceState.keys.add(combo)

  # Update possible sequences based on current keys
  registry.updatePossibleSequences(mode)

  # Check if this completes a sequence
  if mode in registry.sequences:
    if registry.sequenceState.keys in registry.sequences[mode]:
      let command = registry.sequences[mode][registry.sequenceState.keys]

      # Check if this command requires additional input
      if command.kind == ctOperatorPending:
        registry.sequenceState.pendingCommand = some(command)
        registry.sequenceState.waitingForChar = true
        registry.sequenceState.keys = @[] # Clear keys but keep pending state
        return none(Command) # Wait for next key
      else:
        # Don't clear sequence here - let the command execution handle numeric prefix clearing
        return some(command)

  # Check if we have any possible sequences that could continue
  if registry.sequenceState.possibleSequences.len > 0:
    # Check if any sequence exactly matches current length + still continuing
    var hasLongerSequence = false
    for seq in registry.sequenceState.possibleSequences:
      if seq.len > registry.sequenceState.keys.len:
        hasLongerSequence = true
        break

    if hasLongerSequence:
      # Wait for more keys
      return none(Command)

  # No valid sequence continuation, try single key binding
  if registry.sequenceState.keys.len == 1:
    let singleKeyResult = registry.findSingleBinding(mode, combo)

    # Check if this command requires additional input
    if singleKeyResult.isSome and singleKeyResult.get.kind == ctOperatorPending:
      registry.sequenceState.pendingCommand = singleKeyResult
      registry.sequenceState.waitingForChar = true
      registry.sequenceState.keys = @[] # Clear keys but keep pending state
      return none(Command) # Wait for next key
    else:
      # Clear only keys but keep numeric prefix for command execution
      registry.sequenceState.keys = @[]
      registry.sequenceState.possibleSequences = @[]
      # Don't clear numeric prefix - let command execution handle it
      return singleKeyResult

  # Invalid sequence
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
      name: "line-home",
      description: "Move to beginning of line",
      kind: ctMotion,
      motion: Motion.Home,
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

  # Normal mode default bindings
  registry.bindKey(EditorMode.Normal, "h", "move-left")
  registry.bindKey(EditorMode.Normal, "j", "move-down")
  registry.bindKey(EditorMode.Normal, "k", "move-up")
  registry.bindKey(EditorMode.Normal, "l", "move-right")
  registry.bindKey(EditorMode.Normal, "C-u", "page-up")
  registry.bindKey(EditorMode.Normal, "C-d", "page-down")
  registry.bindKey(EditorMode.Normal, "u", "undo")
  registry.bindKey(EditorMode.Normal, "C-r", "redo")

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

  # Sequence bindings - Vim-style
  registry.bindKey(EditorMode.Normal, "g g", "goto-first-line") # Go to first line
  registry.bindKey(EditorMode.Normal, "G", "goto-last-line") # Go to last line
  registry.bindKey(EditorMode.Normal, "d d", "delete-line") # Delete line
  registry.bindKey(EditorMode.Normal, "d w", "delete-word") # Delete word
  registry.bindKey(EditorMode.Normal, "c w", "change-word") # Change word

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

  # Normal mode to Insert mode transitions
  registry.bindKey(EditorMode.Normal, "i", "switch-to-insert") # Enter insert mode
  registry.bindKey(EditorMode.Normal, "a", "append") # Enter insert mode after cursor
  registry.bindKey(EditorMode.Normal, "I", "switch-to-insert")
    # Enter insert mode at line start
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
      kind: ctModeSwitch,
      targetMode: EditorMode.Command,
    )
  )
  registry.bindKey(EditorMode.Normal, ":", "switch-to-command")
  registry.bindKey(EditorMode.Normal, "v", "switch-to-visual") # Enter visual mode
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

  # Visual mode key bindings
  registry.bindKey(EditorMode.Visual, "h", "visual-move-left")
  registry.bindKey(EditorMode.Visual, "l", "visual-move-right")
  registry.bindKey(EditorMode.Visual, "j", "visual-move-down")
  registry.bindKey(EditorMode.Visual, "k", "visual-move-up")
  registry.bindKey(EditorMode.Visual, "d", "visual-delete")
  registry.bindKey(EditorMode.Visual, "x", "visual-delete")
  registry.bindKey(EditorMode.Visual, "Escape", "switch-to-normal") # Exit to normal mode

  # Insert mode key bindings
  registry.bindKey(EditorMode.Insert, "Escape", "switch-to-normal") # Exit to normal mode

  # Replace mode key bindings
  registry.bindKey(EditorMode.Replace, "Escape", "switch-to-normal")
    # Exit to normal mode

proc eventToKeyCombo*(event: celina.Event): Option[KeyCombo] =
  ## Convert a Celina event to a key combination
  if event.kind != celina.EventKind.Key:
    return none(KeyCombo)

  var combo: KeyCombo

  # Check if it's a character key
  if event.key.code == celina.KeyCode.Char:
    combo = KeyCombo(isSpecial: false, char: event.key.char)
  else:
    # Map special keys
    case event.key.code
    of celina.KeyCode.Enter:
      combo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0)
    of celina.KeyCode.Tab, celina.KeyCode.BackTab:
      combo = KeyCombo(isSpecial: true, special: skTab, fnNum: 0)
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
    combo.modifiers.incl(kmShift)

  return some(combo)
