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

## Keybinding type definitions and registry primitives.
##
## Holds the bare minimum that the default-binding tables in this directory
## (`commands.nim`, `normal_bindings.nim`, ...) need so they don't have to
## import the full `key_bindings.nim` and create a cycle. Higher-level dispatch
## logic (`processKey`, runtime mappings, `setupDefaultBindings`, ...) lives
## in the parent module.

import std/[tables, strutils, options, sequtils, hashes]

import ../[types, modes, logger, unicode_utils]

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
    hasCount*: bool ## True iff the user typed a numeric prefix; lets `1G` mean line 1.
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
    numericPrefix*: string
      ## For building numeric prefixes like "2", "23", etc.
      ## Non-empty iff a count prefix is active — there is deliberately no
      ## separate bool; "0" alone is never accumulated (vim treats it as a
      ## command), so `len > 0` is the single source of truth.

  ## Kind of runtime key mapping
  RuntimeMappingKind* = enum
    rmkCommand ## Maps to a command name (handled via existing bindings)
    rmkKeySequence ## Maps to a key sequence (replayed via playbackMacro)

  ## A runtime key mapping entry
  RuntimeKeyMapping* = object
    triggerKeys*: seq[KeyCombo] ## LHS (trigger key sequence)
    triggerStr*: string ## Display string for LHS
    targetStr*: string ## Display string for RHS
    noremap*: bool
      ## When true, the RHS keys are replayed non-recursively (`:noremap`); when
      ## false the RHS is re-expanded through the mapping table (`:map`). Only
      ## meaningful for rmkKeySequence; rmkCommand is terminal.
    case kind*: RuntimeMappingKind
    of rmkCommand:
      command*: Command
        ## Resolved command, stored so `rebuildEffectiveBindings` can re-bind it
        ## verbatim. `commandName` cannot round-trip synthetic commands
        ## (mode_switch / overlay_switch are absent from commandRegistry, and
        ## custom-with-args entries differ from the bare registry version).
      commandName*: string
    of rmkKeySequence:
      targetKeys*: seq[KeyCombo] ## Parsed RHS keys, ready for replay

  ## Runtime key-sequence mapping accumulator. Owned by the `KeyRouter`
  ## (`KeyRouter.dispatchState`), *not* by the registry — runtime-mapping
  ## dispatch is the router's concern. The separate built-in sequence
  ## accumulator (`KeySequenceState` / `sequenceState`) remains registry-owned
  ## because `processKey`'s sequence FSM lives here. The type is defined in this
  ## low-level module so both the router and the routing helpers can name it
  ## without an import cycle.
  DispatchState* = object
    keys*: seq[KeyCombo] ## Runtime-mapping keys accumulated so far

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
      targetKeys*: seq[KeyCombo]
      noremap*: bool
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
      targetKeys*: seq[KeyCombo]
      noremap*: bool
    of rmfReplayPerKey:
      keysToReplay*: seq[KeyCombo]

  ## Registry for all key_bindings
  KeyBindingRegistry* = ref object
    bindings*: Table[EditorMode, seq[KeyBinding]]
    sequences*: Table[EditorMode, Table[seq[KeyCombo], Command]] ## Multi-key sequences
    defaultBindings*: Table[EditorMode, seq[KeyBinding]]
      ## Pristine snapshot of `bindings`/`sequences` taken at the end of
      ## `setupDefaultBindings`, before any TOML or runtime mapping is applied.
      ## `rebuildEffectiveBindings` restores the effective tables from these so
      ## `:unmap`/`:mapclear` fall back to built-in defaults. Snapshotting relies
      ## on `KeyBinding`/`Command`/`KeyCombo` being value types (table assignment
      ## deep-copies); adding a ref field to any of them would break it.
    defaultSequences*: Table[EditorMode, Table[seq[KeyCombo], Command]]
    commandRegistry*: Table[string, Command]
    sequenceState*: KeySequenceState ## Current built-in sequence being built
    runtimeMappings*: Table[EditorMode, seq[RuntimeKeyMapping]]
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

  # Single character (incl. "-" and multi-byte) stays as one combo.
  if s.charLen == 1:
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

  if keyStr.charLen == 1:
    combo = KeyCombo(isSpecial: false, char: keyStr)
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

  # Ctrl + non-letter is undetectable; multi-byte counts as non-letter.
  if kmCtrl in combo.modifiers and not combo.isSpecial:
    let ch = combo.char.asciiChar
    if ch.isNone or ch.get notin {'a' .. 'z', 'A' .. 'Z'}:
      return none(KeyCombo)

  # Shift+letter: terminals send uppercase without Shift (see eventToKeyCombo).
  if kmShift in combo.modifiers and not combo.isSpecial:
    let ch = combo.char.asciiChar
    if ch.isSome and ch.get in {'a' .. 'z', 'A' .. 'Z'}:
      combo.char = combo.char.toUpperAscii
      combo.modifiers.excl(kmShift)
    else:
      # Shift+non-letter (incl. multi-byte) has no shifted form; reject so
      # caller uses the literal char (e.g. "!" not "S-1").
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
    defaultBindings: initTable[EditorMode, seq[KeyBinding]](),
    defaultSequences: initTable[EditorMode, Table[seq[KeyCombo], Command]](),
    commandRegistry: initTable[string, Command](),
    sequenceState: KeySequenceState(
      keys: @[],
      possibleSequences: @[],
      pendingCommand: none(Command),
      waitingForChar: false,
      numericPrefix: "",
    ),
    runtimeMappings: initTable[EditorMode, seq[RuntimeKeyMapping]](),
    isReplayingMapping: false,
  )

  # Initialize empty binding lists for each mode
  for mode in EditorMode:
    result.bindings[mode] = @[]
    result.sequences[mode] = initTable[seq[KeyCombo], Command]()
    result.defaultBindings[mode] = @[]
    result.defaultSequences[mode] = initTable[seq[KeyCombo], Command]()
    result.runtimeMappings[mode] = @[]

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
