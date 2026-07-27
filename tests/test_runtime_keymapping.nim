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

## Tests for runtime key mapping (:map, :nmap, etc.)

import std/[unittest, tables, strutils, options]

import
  ../src/moepkg/[
    keybind_config, key_router, modes, command_line, command_config, buffer,
    key_bindings, types, config, motion, command_registry, registers,
  ]
import
  ../src/moepkg/command_handlers/[
    command_handler, handler_result, handler_manager, result_processor, visual_handler,
    insert_handler,
  ]
from ../src/moepkg/types/editor_types import Editor

import editor_test_helper

suite "parseKeyString":
  test "Single character key":
    let keys = parseKeyString("a")
    check keys.len == 1
    check keys[0].isSpecial == false
    check keys[0].char == "a"

  test "Single modifier key":
    let keys = parseKeyString("C-s")
    check keys.len == 1
    check keys[0].isSpecial == false
    check keys[0].char == "s"
    check kmCtrl in keys[0].modifiers

  test "Multi-key sequence":
    let keys = parseKeyString("j j")
    check keys.len == 2
    check keys[0].char == "j"
    check keys[1].char == "j"

  test "Special key":
    let keys = parseKeyString("Escape")
    check keys.len == 1
    check keys[0].isSpecial == true
    check keys[0].special == skEscape

  test "Multi-key with special key":
    let keys = parseKeyString("g g")
    check keys.len == 2
    check keys[0].char == "g"
    check keys[1].char == "g"

  test "Invalid key returns empty":
    let keys = parseKeyString("C-1")
    check keys.len == 0

  test "Empty string returns empty":
    let keys = parseKeyString("")
    check keys.len == 0

  test "Space key":
    let keys = parseKeyString("Space")
    check keys.len == 1
    check keys[0].isSpecial == false
    check keys[0].char == " "

  test "Alt modifier":
    let keys = parseKeyString("M-x")
    check keys.len == 1
    check kmAlt in keys[0].modifiers

  test "Function key":
    let keys = parseKeyString("F1")
    check keys.len == 1
    check keys[0].isSpecial == true
    check keys[0].special == skFunction
    check keys[0].fnNum == 1

  test "Vim-style concatenated characters (jj)":
    let keys = parseKeyString("jj")
    check keys.len == 2
    check keys[0].char == "j"
    check keys[1].char == "j"

  test "Vim-style concatenated characters (gg)":
    let keys = parseKeyString("gg")
    check keys.len == 2
    check keys[0].char == "g"
    check keys[1].char == "g"

  test "Vim-style mixed characters (gd)":
    let keys = parseKeyString("gd")
    check keys.len == 2
    check keys[0].char == "g"
    check keys[1].char == "d"

  test "Vim-style three characters (abc)":
    let keys = parseKeyString("abc")
    check keys.len == 3
    check keys[0].char == "a"
    check keys[1].char == "b"
    check keys[2].char == "c"

  test "Vim-style concatenated followed by space-separated":
    let keys = parseKeyString("jj Escape")
    check keys.len == 3
    check keys[0].char == "j"
    check keys[1].char == "j"
    check keys[2].isSpecial == true
    check keys[2].special == skEscape

  test "Space-separated then Vim-style concatenated":
    let keys = parseKeyString("C-x jj")
    check keys.len == 3
    check keys[0].char == "x"
    check kmCtrl in keys[0].modifiers
    check keys[1].char == "j"
    check keys[2].char == "j"

  test "Modifier key is not treated as Vim-style":
    # "C-s" contains '-' so should be parsed as modifier, not Vim-style
    let keys = parseKeyString("C-s")
    check keys.len == 1
    check keys[0].char == "s"
    check kmCtrl in keys[0].modifiers

  test "Invalid modifier returns empty":
    # "C-1" is invalid modifier syntax
    let keys = parseKeyString("C-1")
    check keys.len == 0

  test "Uppercase modifier-letter run rejected (CC is typo for C-C)":
    check parseKeyString("CC").len == 0
    check parseKeyString("MM").len == 0
    check parseKeyString("SS").len == 0
    check parseKeyString("CM").len == 0
    check parseKeyString("SC").len == 0
    check parseKeyString("CMS").len == 0

  test "Lowercase Vim-style doubled letters still accepted":
    # "cc" (change line), "mm" (set mark m), "ss" — real Vim mappings.
    check parseKeyString("cc").len == 2
    check parseKeyString("mm").len == 2
    check parseKeyString("ss").len == 2

  test "Vim-style with uppercase non-modifier letter still accepted":
    # "gT" (previous tab), "zM" (foldlevel 0), etc.
    let gT = parseKeyString("gT")
    check gT.len == 2
    check gT[0].char == "g"
    check gT[1].char == "T"

  test "Whitespace only returns empty":
    let keys = parseKeyString("   ")
    check keys.len == 0

  test "Multiple spaces between tokens":
    let keys = parseKeyString("a   b")
    check keys.len == 2
    check keys[0].char == "a"
    check keys[1].char == "b"

  test "Vim-style same as space-separated equivalent":
    let vjj = parseKeyString("jj")
    let sjj = parseKeyString("j j")
    check vjj.len == sjj.len
    check vjj[0] == sjj[0]
    check vjj[1] == sjj[1]

  test "Shift+lowercase letter normalizes to uppercase without Shift (#2597)":
    # Terminals deliver Shift+j as bare 'J' without a Shift modifier, so the
    # parsed form has to match that representation.
    let keys = parseKeyString("S-j")
    check keys.len == 1
    check keys[0].isSpecial == false
    check keys[0].char == "J"
    check kmShift notin keys[0].modifiers

  test "Shift+uppercase letter equals uppercase letter alone (#2597)":
    let sj = parseKeyString("S-J")
    let j = parseKeyString("J")
    check sj.len == 1
    check sj[0] == j[0]

  test "Shift+lowercase equals Shift+uppercase equals uppercase (#2597)":
    let sLower = parseKeyString("S-k")
    let sUpper = parseKeyString("S-K")
    let upper = parseKeyString("K")
    check sLower[0] == sUpper[0]
    check sUpper[0] == upper[0]

suite "keySeqToDisplayString":
  test "Single key":
    let keys = parseKeyString("a")
    check keySeqToDisplayString(keys) == "a"

  test "Modifier key":
    let keys = parseKeyString("C-s")
    check keySeqToDisplayString(keys) == "C-s"

  test "Multi-key sequence":
    let keys = parseKeyString("g g")
    check keySeqToDisplayString(keys) == "g g"

  test "Special key":
    let keys = parseKeyString("Escape")
    check keySeqToDisplayString(keys) == "Escape"

  test "Space key":
    let keys = parseKeyString("Space")
    check keySeqToDisplayString(keys) == "Space"

  test "Vim-style concatenated displays as space-separated":
    let keys = parseKeyString("jj")
    check keySeqToDisplayString(keys) == "j j"

  test "Alt modifier key":
    let keys = parseKeyString("M-x")
    check keySeqToDisplayString(keys) == "M-x"

  test "Function key":
    let keys = parseKeyString("F5")
    check keySeqToDisplayString(keys) == "F5"

  test "Multi-key with special":
    let keys = parseKeyString("g g Enter")
    check keySeqToDisplayString(keys) == "g g Enter"

suite "addRuntimeMapping - key to command":
  test "Map to known command":
    var registry = newKeyBindingRegistry()
    # Register a command so it can be mapped to
    let cmd = Command(
      name: "file.save",
      description: "Save file",
      count: 1,
      kind: ctAction,
      commandId: "file.save",
    )
    registry.registerCommand(cmd)

    let err = registry.addRuntimeMapping(Normal, "C-s", "file.save")
    check err == ""
    check registry.runtimeMappings[Normal].len == 1
    check registry.runtimeMappings[Normal][0].kind == rmkCommand
    check registry.runtimeMappings[Normal][0].commandName == "file.save"

  test "Map S-j to bnext resolves as command, not key sequence (#2597)":
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()

    let err = registry.addRuntimeMapping(Normal, "S-j", "bnext")
    check err == ""
    check registry.runtimeMappings[Normal].len == 1
    let m = registry.runtimeMappings[Normal][0]
    check m.kind == rmkCommand
    check m.commandName == "bnext"
    # S-j must normalize to 'J' (no Shift modifier) so it matches actual
    # terminal events for Shift+j.
    check m.triggerKeys.len == 1
    check m.triggerKeys[0].char == "J"
    check kmShift notin m.triggerKeys[0].modifiers

  test "Map J to bprev resolves as command (#2597)":
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()

    let err = registry.addRuntimeMapping(Normal, "K", "bprev")
    check err == ""
    let m = registry.runtimeMappings[Normal][^1]
    check m.kind == rmkCommand
    check m.commandName == "bprev"

  test "Map D to bdelete resolves as command (#2597)":
    # Issue #2597 follow-up: `bdelete` must be a registered alias so it stops
    # silently falling through to the Vim concat `b,d,e,l,e,t,e` sequence.
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()

    let err = registry.addRuntimeMapping(Normal, "D", "bdelete")
    check err == ""
    let m = registry.runtimeMappings[Normal][^1]
    check m.kind == rmkCommand
    check m.commandName == "bdelete"

  test "Map Q to q resolves as command (#2597)":
    # Single-letter alias `q` is registered so `Q = "q"` reaches the
    # command-line parser's modified-buffer safety check instead of being
    # recorded as a 1-key sequence target.
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()

    let err = registry.addRuntimeMapping(Normal, "Q", "q")
    check err == ""
    let m = registry.runtimeMappings[Normal][^1]
    check m.kind == rmkCommand
    check m.commandName == "q"

  test "Map F2 to wq resolves as command (#2597)":
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()

    let err = registry.addRuntimeMapping(Normal, "F2", "wq")
    check err == ""
    let m = registry.runtimeMappings[Normal][^1]
    check m.kind == rmkCommand
    check m.commandName == "wq"

  test "Map overwrites existing":
    var registry = newKeyBindingRegistry()
    let cmd1 = Command(
      name: "file.save",
      description: "Save file",
      count: 1,
      kind: ctAction,
      commandId: "file.save",
    )
    let cmd2 = Command(
      name: "file.quit",
      description: "Quit",
      count: 1,
      kind: ctAction,
      commandId: "file.quit",
    )
    registry.registerCommand(cmd1)
    registry.registerCommand(cmd2)

    discard registry.addRuntimeMapping(Normal, "C-s", "file.save")
    discard registry.addRuntimeMapping(Normal, "C-s", "file.quit")
    check registry.runtimeMappings[Normal].len == 1
    check registry.runtimeMappings[Normal][0].commandName == "file.quit"

suite "addRuntimeMapping - key to key sequence":
  test "Map key to Escape":
    var registry = newKeyBindingRegistry()
    let err = registry.addRuntimeMapping(Insert, "j j", "Escape")
    check err == ""
    check registry.runtimeMappings[Insert].len == 1
    check registry.runtimeMappings[Insert][0].kind == rmkKeySequence
    check registry.runtimeMappings[Insert][0].targetKeys.len == 1

  test "Map Vim-style jj to Escape":
    var registry = newKeyBindingRegistry()
    let err = registry.addRuntimeMapping(Insert, "jj", "Escape")
    check err == ""
    check registry.runtimeMappings[Insert].len == 1
    check registry.runtimeMappings[Insert][0].kind == rmkKeySequence
    check registry.runtimeMappings[Insert][0].triggerKeys.len == 2
    check registry.runtimeMappings[Insert][0].targetKeys.len == 1

  test "Map single key to key sequence":
    var registry = newKeyBindingRegistry()
    let err = registry.addRuntimeMapping(Normal, "C-a", "g g")
    check err == ""
    check registry.runtimeMappings[Normal].len == 1
    check registry.runtimeMappings[Normal][0].kind == rmkKeySequence
    check registry.runtimeMappings[Normal][0].targetKeys.len == 2

  test "Map to multi-key RHS":
    var registry = newKeyBindingRegistry()
    let err = registry.addRuntimeMapping(Normal, "C-a", "d d")
    check err == ""
    check registry.runtimeMappings[Normal][0].targetKeys.len == 2

  test "Mapping in different modes are independent":
    var registry = newKeyBindingRegistry()
    discard registry.addRuntimeMapping(Normal, "C-a", "Escape")
    discard registry.addRuntimeMapping(Insert, "C-a", "Enter")
    check registry.runtimeMappings[Normal].len == 1
    check registry.runtimeMappings[Insert].len == 1
    check registry.runtimeMappings[Normal][0].targetStr == "Escape"
    check registry.runtimeMappings[Insert][0].targetStr == "Enter"

  test "Invalid LHS returns error":
    var registry = newKeyBindingRegistry()
    let err = registry.addRuntimeMapping(Normal, "C-1", "Escape")
    check err.len > 0
    check "Invalid key" in err

  test "Invalid RHS returns error":
    var registry = newKeyBindingRegistry()
    let err = registry.addRuntimeMapping(Normal, "C-s", "C-1")
    check err.len > 0
    check "Invalid mapping target" in err

  test "Empty LHS returns error":
    var registry = newKeyBindingRegistry()
    let err = registry.addRuntimeMapping(Normal, "", "Escape")
    check err.len > 0
    check "Invalid key" in err

  test "Empty RHS returns error":
    var registry = newKeyBindingRegistry()
    let err = registry.addRuntimeMapping(Normal, "C-a", "")
    check err.len > 0
    check "Invalid mapping target" in err

suite "removeRuntimeMapping":
  test "Remove existing mapping":
    var registry = newKeyBindingRegistry()
    discard registry.addRuntimeMapping(Normal, "C-a", "g g")
    check registry.runtimeMappings[Normal].len == 1

    let err = registry.removeRuntimeMapping(Normal, "C-a")
    check err == ""
    check registry.runtimeMappings[Normal].len == 0

  test "Remove non-existing mapping returns error":
    var registry = newKeyBindingRegistry()
    let err = registry.removeRuntimeMapping(Normal, "C-a")
    check err.len > 0
    check "No mapping found" in err

  test "Remove command mapping also unbinds":
    var registry = newKeyBindingRegistry()
    let cmd = Command(
      name: "file.save",
      description: "Save file",
      count: 1,
      kind: ctAction,
      commandId: "file.save",
    )
    registry.registerCommand(cmd)
    discard registry.addRuntimeMapping(Normal, "C-s", "file.save")
    check registry.runtimeMappings[Normal].len == 1

    let err = registry.removeRuntimeMapping(Normal, "C-s")
    check err == ""
    check registry.runtimeMappings[Normal].len == 0

  test "Remove invalid LHS returns error":
    var registry = newKeyBindingRegistry()
    let err = registry.removeRuntimeMapping(Normal, "C-1")
    check err.len > 0
    check "Invalid key" in err

  test "Remove only affects specified mode":
    var registry = newKeyBindingRegistry()
    discard registry.addRuntimeMapping(Normal, "C-a", "Escape")
    discard registry.addRuntimeMapping(Insert, "C-a", "Escape")

    let err = registry.removeRuntimeMapping(Normal, "C-a")
    check err == ""
    check registry.runtimeMappings[Normal].len == 0
    check registry.runtimeMappings[Insert].len == 1

  test "Remove Vim-style mapping":
    var registry = newKeyBindingRegistry()
    discard registry.addRuntimeMapping(Insert, "jj", "Escape")
    check registry.runtimeMappings[Insert].len == 1

    let err = registry.removeRuntimeMapping(Insert, "jj")
    check err == ""
    check registry.runtimeMappings[Insert].len == 0

  test "Remove one mapping leaves others intact":
    var registry = newKeyBindingRegistry()
    discard registry.addRuntimeMapping(Normal, "C-a", "Escape")
    discard registry.addRuntimeMapping(Normal, "C-b", "Enter")
    check registry.runtimeMappings[Normal].len == 2

    discard registry.removeRuntimeMapping(Normal, "C-a")
    check registry.runtimeMappings[Normal].len == 1
    check registry.runtimeMappings[Normal][0].triggerStr == "C-b"

suite "clearRuntimeMappings":
  test "Clear all mappings for mode":
    var registry = newKeyBindingRegistry()
    discard registry.addRuntimeMapping(Normal, "C-a", "g g")
    discard registry.addRuntimeMapping(Normal, "C-b", "Escape")
    check registry.runtimeMappings[Normal].len == 2

    registry.clearRuntimeMappings(Normal)
    check registry.runtimeMappings[Normal].len == 0

  test "Clear empty mode":
    var registry = newKeyBindingRegistry()
    registry.clearRuntimeMappings(Normal) # Should not raise

  test "Clear one mode does not affect another":
    var registry = newKeyBindingRegistry()
    discard registry.addRuntimeMapping(Normal, "C-a", "Escape")
    discard registry.addRuntimeMapping(Insert, "C-b", "Escape")

    registry.clearRuntimeMappings(Normal)
    check registry.runtimeMappings[Normal].len == 0
    check registry.runtimeMappings[Insert].len == 1

suite "Two-layer default restoration":
  test "removeRuntimeMapping restores the built-in single-key binding":
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    let xKey = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    # Built-in default: x -> delete-char
    let original = registry.findSingleBinding(Normal, xKey)
    check original.isSome
    check original.get.name == "delete-char"

    # User override shadows the default
    let cmd = Command(
      name: "test.cmd", description: "", count: 1, kind: ctAction, commandId: "test.cmd"
    )
    registry.registerCommand(cmd)
    discard registry.addRuntimeMapping(Normal, "x", "test.cmd")
    check registry.findSingleBinding(Normal, xKey).get.name == "test.cmd"

    # Removing the mapping falls back to the built-in default
    discard registry.removeRuntimeMapping(Normal, "x")
    let restored = registry.findSingleBinding(Normal, xKey)
    check restored.isSome
    check restored.get.name == "delete-char"

  test "overwriting a command mapping with a key sequence purges the stale binding":
    # Regression: the rmkKeySequence branch of addRuntimeMapping must rebuild so
    # an earlier rmkCommand binding for the same trigger does not linger in
    # bindings/sequences (it would surface during :noremap replay, when the
    # KeyRouter precheck is skipped).
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    let cmd = Command(
      name: "test.cmd", description: "", count: 1, kind: ctAction, commandId: "test.cmd"
    )
    registry.registerCommand(cmd)
    let xKey = KeyCombo(isSpecial: false, char: "x", modifiers: {})

    # 1) command mapping binds x -> test.cmd
    discard registry.addRuntimeMapping(Normal, "x", "test.cmd")
    check registry.findSingleBinding(Normal, xKey).get.name == "test.cmd"

    # 2) overwrite with a key-sequence mapping (rhs is not a command name)
    discard registry.addRuntimeMapping(Normal, "x", "j")
    check registry.runtimeMappings[Normal][^1].kind == rmkKeySequence
    # The stale command binding must be gone; the built-in default is restored in
    # bindings (the key sequence dispatches via the KeyRouter, not findBinding).
    check registry.findSingleBinding(Normal, xKey).get.name == "delete-char"

  test "clearRuntimeMappings restores all built-ins and keeps built-in sequences":
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    let gKey = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    let xKey = KeyCombo(isSpecial: false, char: "x", modifiers: {})

    # Built-in sequence: g g -> goto-first-line
    discard registry.processKey(Normal, gKey)
    let gg = registry.processKey(Normal, gKey)
    check gg.isSome
    check gg.get.name == "goto-first-line"

    let cmd = Command(
      name: "test.cmd", description: "", count: 1, kind: ctAction, commandId: "test.cmd"
    )
    registry.registerCommand(cmd)
    discard registry.addRuntimeMapping(Normal, "x", "test.cmd")
    check registry.findSingleBinding(Normal, xKey).get.name == "test.cmd"

    registry.clearRuntimeMappings(Normal)

    # Single-key default restored
    check registry.findSingleBinding(Normal, xKey).get.name == "delete-char"
    # Built-in sequence still resolves (mode was not wiped)
    discard registry.processKey(Normal, gKey)
    let gg2 = registry.processKey(Normal, gKey)
    check gg2.isSome
    check gg2.get.name == "goto-first-line"

suite "listRuntimeMappings":
  test "List mappings":
    var registry = newKeyBindingRegistry()
    discard registry.addRuntimeMapping(Normal, "C-a", "g g")
    discard registry.addRuntimeMapping(Normal, "C-b", "Escape")

    let listings = registry.listRuntimeMappings(Normal)
    check listings.len == 2
    check "C-a -> g g" in listings
    check "C-b -> Escape" in listings

  test "Empty mode returns empty list":
    var registry = newKeyBindingRegistry()
    let listings = registry.listRuntimeMappings(Normal)
    check listings.len == 0

  test "List Vim-style mapping":
    var registry = newKeyBindingRegistry()
    discard registry.addRuntimeMapping(Insert, "jj", "Escape")
    let listings = registry.listRuntimeMappings(Insert)
    check listings.len == 1
    check "jj -> Escape" in listings

  test "List does not include other modes":
    var registry = newKeyBindingRegistry()
    discard registry.addRuntimeMapping(Normal, "C-a", "Escape")
    discard registry.addRuntimeMapping(Insert, "C-b", "Enter")
    let normalList = registry.listRuntimeMappings(Normal)
    let insertList = registry.listRuntimeMappings(Insert)
    check normalList.len == 1
    check insertList.len == 1
    check "C-a -> Escape" in normalList
    check "C-b -> Enter" in insertList

  test "Prefix filter keeps only lhs that start with the prefix":
    var registry = newKeyBindingRegistry()
    discard registry.addRuntimeMapping(Normal, "<leader>ab", "Escape")
    discard registry.addRuntimeMapping(Normal, "<leader>ac", "Escape")
    discard registry.addRuntimeMapping(Normal, "C-b", "Escape")

    let filtered = registry.listRuntimeMappings(Normal, "<leader>a")
    check filtered.len == 2
    check "<leader>ab -> Escape" in filtered
    check "<leader>ac -> Escape" in filtered

    let miss = registry.listRuntimeMappings(Normal, "zz")
    check miss.len == 0

suite "getRuntimeKeySeqMappings":
  test "Returns only key-sequence mappings":
    var registry = newKeyBindingRegistry()
    let cmd = Command(
      name: "test.cmd",
      description: "Test",
      count: 1,
      kind: ctAction,
      commandId: "test.cmd",
    )
    registry.registerCommand(cmd)
    discard registry.addRuntimeMapping(Normal, "C-a", "test.cmd")
    discard registry.addRuntimeMapping(Normal, "C-b", "Escape")

    let keySeqMappings = registry.getRuntimeKeySeqMappings(Normal)
    check keySeqMappings.len == 1
    check keySeqMappings[0].triggerStr == "C-b"

  test "Returns empty for mode with no mappings":
    var registry = newKeyBindingRegistry()
    let mappings = registry.getRuntimeKeySeqMappings(Normal)
    check mappings.len == 0

suite "clearRuntimeMappingState":
  test "Clears accumulated keys":
    # The runtime-mapping accumulator is now a router-owned DispatchState.
    var state = DispatchState(keys: @[])
    let j = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    state.keys.add(j)
    check state.keys.len == 1

    clearRuntimeMappingState(state)
    check state.keys.len == 0

suite "Command mode command parsing - map commands":
  setup:
    let parser = newCommandLineParser()
    let config = newCommandConfig()
    config.loadDefaultConfig()
    config.applyToParser(parser)

  test "Parse :nmap C-s file.save":
    let result = parser.parseAndExecute(":nmap C-s file.save")
    check result.kind == claNmap
    check result.mapLhs == "C-s"
    check result.mapRhs == "file.save"

  test "Parse :imap j j Escape":
    let result = parser.parseAndExecute(":imap j j Escape")
    check result.kind == claImap
    check result.mapLhs == "j"
    check result.mapRhs == "j Escape"

  test "Parse :map C-s file.save":
    let result = parser.parseAndExecute(":map C-s file.save")
    check result.kind == claMap
    check result.mapLhs == "C-s"
    check result.mapRhs == "file.save"
    check result.noremap == false

  test "Parse :vmap d visual.delete":
    let result = parser.parseAndExecute(":vmap d visual.delete")
    check result.kind == claVmap
    check result.mapLhs == "d"
    check result.mapRhs == "visual.delete"

  test "Parse :noremap C-s file.save (folds to claMap, noremap=true)":
    let result = parser.parseAndExecute(":noremap C-s file.save")
    check result.kind == claMap
    check result.mapLhs == "C-s"
    check result.noremap == true

  test "Parse :nnoremap C-s file.save (folds to claNmap, noremap=true)":
    let result = parser.parseAndExecute(":nnoremap C-s file.save")
    check result.kind == claNmap
    check result.mapLhs == "C-s"
    check result.noremap == true

  test "Parse :nmap without args returns list request":
    let result = parser.parseAndExecute(":nmap")
    check result.kind == claNmap
    check result.mapLhs == ""
    check result.mapRhs == ""

  test "Parse :map without args returns list request":
    let result = parser.parseAndExecute(":map")
    check result.kind == claMap
    check result.mapLhs == ""
    check result.mapRhs == ""

  test "Parse :imap without args returns list request":
    let result = parser.parseAndExecute(":imap")
    check result.kind == claImap
    check result.mapLhs == ""
    check result.mapRhs == ""

  test "Parse :vmap without args returns list request":
    let result = parser.parseAndExecute(":vmap")
    check result.kind == claVmap
    check result.mapLhs == ""
    check result.mapRhs == ""

  test "Parse :rmap without args returns list request":
    let result = parser.parseAndExecute(":rmap")
    check result.kind == claRmap
    check result.mapLhs == ""
    check result.mapRhs == ""

  test "Parse :nmap with only LHS returns prefix list request":
    let result = parser.parseAndExecute(":nmap C-s")
    check result.kind == claNmap
    check result.mapLhs == "C-s"
    check result.mapRhs == ""

  test "Parse :rmap C-a Escape":
    let result = parser.parseAndExecute(":rmap C-a Escape")
    check result.kind == claRmap
    check result.mapLhs == "C-a"
    check result.mapRhs == "Escape"

  test "Parse :imap jj Escape (Vim-style LHS)":
    let result = parser.parseAndExecute(":imap jj Escape")
    check result.kind == claImap
    check result.mapLhs == "jj"
    check result.mapRhs == "Escape"

  test "Parse :nmap with multi-key RHS":
    let result = parser.parseAndExecute(":nmap C-a d d")
    check result.kind == claNmap
    check result.mapLhs == "C-a"
    check result.mapRhs == "d d"

  test "Parse :inoremap (folds to claImap, noremap=true)":
    let result = parser.parseAndExecute(":inoremap jj Escape")
    check result.kind == claImap
    check result.mapLhs == "jj"
    check result.mapRhs == "Escape"
    check result.noremap == true

  test "Parse :vnoremap (folds to claVmap, noremap=true)":
    let result = parser.parseAndExecute(":vnoremap d Escape")
    check result.kind == claVmap
    check result.mapLhs == "d"
    check result.mapRhs == "Escape"
    check result.noremap == true

  test "Parse :nmap preserves tab inside RHS":
    let result = parser.parseAndExecute(":nmap C-a foo\tbar")
    check result.kind == claNmap
    check result.mapLhs == "C-a"
    check result.mapRhs == "foo\tbar"

  test "Parse :nmap preserves multiple tabs and spaces inside RHS":
    let result = parser.parseAndExecute(":nmap C-a a\t\tb  c")
    check result.kind == claNmap
    check result.mapLhs == "C-a"
    check result.mapRhs == "a\t\tb  c"

suite "Command mode command parsing - unmap commands":
  setup:
    let parser = newCommandLineParser()
    let config = newCommandConfig()
    config.loadDefaultConfig()
    config.applyToParser(parser)

  test "Parse :nunmap C-s":
    let result = parser.parseAndExecute(":nunmap C-s")
    check result.kind == claNunmap
    check result.unmapLhs == "C-s"

  test "Parse :unmap C-s":
    let result = parser.parseAndExecute(":unmap C-s")
    check result.kind == claUnmap
    check result.unmapLhs == "C-s"

  test "Parse :nunmap without args returns error":
    let result = parser.parseAndExecute(":nunmap")
    check result.kind == claUnknown
    check "Usage" in result.errorMessage

  test "Parse :iunmap C-a":
    let result = parser.parseAndExecute(":iunmap C-a")
    check result.kind == claIunmap
    check result.unmapLhs == "C-a"

  test "Parse :vunmap d":
    let result = parser.parseAndExecute(":vunmap d")
    check result.kind == claVunmap
    check result.unmapLhs == "d"

  test "Parse :runmap C-a":
    let result = parser.parseAndExecute(":runmap C-a")
    check result.kind == claRunmap
    check result.unmapLhs == "C-a"

suite "Command mode command parsing - mapclear commands":
  setup:
    let parser = newCommandLineParser()
    let config = newCommandConfig()
    config.loadDefaultConfig()
    config.applyToParser(parser)

  test "Parse :nmapclear":
    let result = parser.parseAndExecute(":nmapclear")
    check result.kind == claNmapclear

  test "Parse :mapclear":
    let result = parser.parseAndExecute(":mapclear")
    check result.kind == claMapclear

  test "Parse :imapclear":
    let result = parser.parseAndExecute(":imapclear")
    check result.kind == claImapclear

  test "Parse :vmapclear":
    let result = parser.parseAndExecute(":vmapclear")
    check result.kind == claVmapclear

  test "Parse :rmapclear":
    let result = parser.parseAndExecute(":rmapclear")
    check result.kind == claRmapclear

suite "CommandModeHandler - map commands":
  setup:
    let parser = newCommandLineParser()
    let config = newCommandConfig()
    config.loadDefaultConfig()
    config.applyToParser(parser)
    let commandRegistry = newCommandRegistry()
    let handler = newCommandModeHandler(parser, config, commandRegistry)

  test "handleCommandModeInput :nmap returns hrMapAdd":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":nmap C-s file.save")
    check result.kind == hrMapAdd
    check result.mapAddLhs == "C-s"
    check result.mapAddRhs == "file.save"
    check EditorMode.Normal in result.mapAddModes
    check result.mapAddModes.len == 1
    check result.mapAddNoremap == false

  test "handleCommandModeInput :nnoremap returns hrMapAdd with noremap=true":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":nnoremap C-s file.save")
    check result.kind == hrMapAdd
    check EditorMode.Normal in result.mapAddModes
    check result.mapAddNoremap == true

  test "handleCommandModeInput :imap returns hrMapAdd for Insert":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":imap j Escape")
    check result.kind == hrMapAdd
    check EditorMode.Insert in result.mapAddModes

  test "handleCommandModeInput :vmap returns hrMapAdd for Visual modes":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":vmap d visual.delete")
    check result.kind == hrMapAdd
    check EditorMode.Visual in result.mapAddModes
    check EditorMode.VisualBlock in result.mapAddModes
    check EditorMode.VisualLine in result.mapAddModes

  test "handleCommandModeInput :map returns hrMapAdd for all modes":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":map C-s file.save")
    check result.kind == hrMapAdd
    check result.mapAddModes.len == 6

  test "handleCommandModeInput :nunmap returns hrMapRemove":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":nunmap C-s")
    check result.kind == hrMapRemove
    check result.mapRemoveLhs == "C-s"
    check EditorMode.Normal in result.mapRemoveModes

  test "handleCommandModeInput :nmapclear returns hrMapClear":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":nmapclear")
    check result.kind == hrMapClear
    check EditorMode.Normal in result.mapClearModes

  test "handleCommandModeInput :rmap returns hrMapAdd for Replace":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":rmap C-a Escape")
    check result.kind == hrMapAdd
    check EditorMode.Replace in result.mapAddModes
    check result.mapAddModes.len == 1

  test "handleCommandModeInput :unmap returns hrMapRemove for all modes":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":unmap C-s")
    check result.kind == hrMapRemove
    check result.mapRemoveLhs == "C-s"
    check result.mapRemoveModes.len == 6

  test "handleCommandModeInput :iunmap returns hrMapRemove for Insert":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":iunmap C-a")
    check result.kind == hrMapRemove
    check EditorMode.Insert in result.mapRemoveModes
    check result.mapRemoveModes.len == 1

  test "handleCommandModeInput :vunmap returns hrMapRemove for Visual modes":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":vunmap d")
    check result.kind == hrMapRemove
    check EditorMode.Visual in result.mapRemoveModes
    check EditorMode.VisualBlock in result.mapRemoveModes
    check EditorMode.VisualLine in result.mapRemoveModes

  test "handleCommandModeInput :mapclear returns hrMapClear for all modes":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":mapclear")
    check result.kind == hrMapClear
    check result.mapClearModes.len == 6

  test "handleCommandModeInput :imapclear returns hrMapClear for Insert":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":imapclear")
    check result.kind == hrMapClear
    check EditorMode.Insert in result.mapClearModes
    check result.mapClearModes.len == 1

  test "handleCommandModeInput :imap jj Escape (Vim-style)":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":imap jj Escape")
    check result.kind == hrMapAdd
    check result.mapAddLhs == "jj"
    check result.mapAddRhs == "Escape"
    check EditorMode.Insert in result.mapAddModes

# --- Integration test helpers ---

proc createTestState(mode: EditorMode = EditorMode.Normal): EditorState =
  result = EditorState(
    activeWindow: EditorWindow(
      cursor: BufferPosition(line: 0, column: 0),
      mode: mode,
      previousMode: EditorMode.Normal,
    ),
    config: newEditorConfig(),
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

proc createTestViewport(): ViewPort =
  ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80)

proc createTestManager(): HandlerManager =
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

# --- Integration tests ---

suite "Integration - handleKeyCombo with runtime key-seq mapping":
  test "Multi-key mapping accumulates then triggers":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    # Map j j → Escape in Insert mode
    let err = manager.keyBindingRegistry.addRuntimeMapping(Insert, "j j", "Escape")
    check err == ""

    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    # First 'j' should be accumulated (waiting for more keys)
    let j1 = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let r1 = manager.runKeyCombo(editor, j1)
    check r1.kind == hrHandled
    check editor.keyRouter.dispatchState.keys.len == 1

    # Second 'j' should trigger the mapping (Escape → Normal mode)
    let j2 = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let r2 = manager.runKeyCombo(editor, j2)
    check r2.kind == hrHandled
    # Accumulator should be cleared after match
    check editor.keyRouter.dispatchState.keys.len == 0

  test "Non-matching key after accumulation flushes":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    # Map j j → Escape in Insert mode
    let err = manager.keyBindingRegistry.addRuntimeMapping(Insert, "j j", "Escape")
    check err == ""

    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    # First 'j' accumulates
    let j1 = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let r1 = manager.runKeyCombo(editor, j1)
    check r1.kind == hrHandled

    # 'k' does not match 'j j' → flush 'j' and process 'k' normally
    let k = KeyCombo(isSpecial: false, char: "k", modifiers: {})
    discard manager.runKeyCombo(editor, k)
    # Accumulator should be cleared after flush
    check editor.keyRouter.dispatchState.keys.len == 0

  test "No mappings registered passes through immediately":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    # No runtime mappings registered. 'a' should pass through normally.
    let a = KeyCombo(isSpecial: false, char: "a", modifiers: {})
    let r = manager.runKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager), a
    )
    # Should be handled by insert mode handler, not blocked by mapping precheck
    check r.kind == hrHandled

  test "Single-key mapping in Insert mode triggers":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    # Map C-a → Escape in Insert mode
    let err = manager.keyBindingRegistry.addRuntimeMapping(Insert, "C-a", "Escape")
    check err == ""

    # Pressing C-a should be consumed by the mapping and Escape replayed
    let keyCombo = KeyCombo(isSpecial: false, char: "a", modifiers: {kmCtrl})
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)
    let r = manager.runKeyCombo(editor, keyCombo)
    check r.kind == hrHandled
    # Accumulator should be cleared
    check editor.keyRouter.dispatchState.keys.len == 0

suite "Integration - noremap verification":
  test "Mapping A→B does not recursively expand B→C":
    ## Register two key-seq mappings in Insert mode:
    ##   C-a → C-b, C-b → Escape
    ## Pressing C-a should replay C-b literally (as if typed),
    ## but since isReplayingMapping is true during the replay,
    ## C-b should NOT be expanded to Escape.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    # Map C-a → C-b (key sequence) in Insert mode
    let err1 = manager.keyBindingRegistry.addRuntimeMapping(Insert, "C-a", "C-b")
    check err1 == ""

    # Map C-b → Escape (key sequence) in Insert mode
    let err2 = manager.keyBindingRegistry.addRuntimeMapping(Insert, "C-b", "Escape")
    check err2 == ""

    # Press C-a: should expand to C-b only, NOT further to Escape
    let keyA = KeyCombo(isSpecial: false, char: "a", modifiers: {kmCtrl})
    let r = manager.runKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager),
      keyA,
    )
    check r.kind == hrHandled
    # isReplayingMapping should be false after completion
    check manager.keyBindingRegistry.isReplayingMapping == false
    # If C-b were recursively expanded to Escape, mode would have switched to Normal.
    # Since noremap prevents that, we should still be in Insert mode.
    check state.mode == EditorMode.Insert

  test "isReplayingMapping prevents expansion during playback":
    ## Directly verify that when isReplayingMapping is set,
    ## handleKeyCombo skips the mapping precheck
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    # Register a mapping in Insert mode
    let err = manager.keyBindingRegistry.addRuntimeMapping(Insert, "C-a", "Escape")
    check err == ""

    # With isReplayingMapping = true, handleKeyCombo should skip mapping precheck
    manager.keyBindingRegistry.isReplayingMapping = true
    let keyA = KeyCombo(isSpecial: false, char: "a", modifiers: {kmCtrl})
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)
    discard manager.runKeyCombo(editor, keyA)
    # The key should have been processed normally (not consumed by mapping)
    # Accumulator should remain empty
    check editor.keyRouter.dispatchState.keys.len == 0
    manager.keyBindingRegistry.isReplayingMapping = false

  test "Mapping does not expand in wrong mode":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    # Map C-a → Escape only in Normal mode (not Insert)
    let err = manager.keyBindingRegistry.addRuntimeMapping(Normal, "C-a", "Escape")
    check err == ""

    # Press C-a in Insert mode: should NOT trigger the Normal mapping
    let keyA = KeyCombo(isSpecial: false, char: "a", modifiers: {kmCtrl})
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)
    discard manager.runKeyCombo(editor, keyA)
    # Accumulator should be empty (no key-seq mappings registered for Insert)
    check editor.keyRouter.dispatchState.keys.len == 0

suite "Integration - recursive map (noremap=false)":
  test "Mapping A→B→Escape recursively expands when noremap=false":
    ## Counterpart to the noremap test above: with noremap=false the replayed
    ## C-b *is* re-expanded to Escape, switching Insert→Normal.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    check manager.keyBindingRegistry.addRuntimeMapping(
      Insert, "C-a", "C-b", noremap = false
    ) == ""
    check manager.keyBindingRegistry.addRuntimeMapping(
      Insert, "C-b", "Escape", noremap = false
    ) == ""

    let keyA = KeyCombo(isSpecial: false, char: "a", modifiers: {kmCtrl})
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)
    let r = manager.runKeyCombo(editor, keyA)
    check r.kind == hrHandled
    # C-a → C-b → Escape: recursion reaches Escape, so we land in Normal mode.
    check state.mode == EditorMode.Normal
    check editor.keyRouter.mapExpandDepth == 0
    check manager.keyBindingRegistry.isReplayingMapping == false

  test "Cyclic mapping A→A errors at the depth limit without hanging":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    check manager.keyBindingRegistry.addRuntimeMapping(
      Insert, "C-a", "C-a", noremap = false
    ) == ""

    let keyA = KeyCombo(isSpecial: false, char: "a", modifiers: {kmCtrl})
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)
    let r = manager.runKeyCombo(editor, keyA)
    check r.kind == hrError
    check "recursive mapping" in r.errorMessage
    # The depth counter must unwind to zero even on the error path.
    check editor.keyRouter.mapExpandDepth == 0

suite "addRuntimeMappingExpanded - complex command targets":
  test "mode_switch resolves to a ctModeSwitch command binding":
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    let err = registry.addRuntimeMappingExpanded(Normal, "C-y", "mode_switch insert")
    check err == ""
    let m = registry.runtimeMappings[Normal][^1]
    check m.kind == rmkCommand
    check m.command.kind == ctModeSwitch
    check m.command.targetMode == EditorMode.Insert
    # Effective binding resolves to the synthetic command.
    let combo = KeyCombo(isSpecial: false, char: "y", modifiers: {kmCtrl})
    let b = registry.findSingleBinding(Normal, combo)
    check b.isSome
    check b.get.kind == ctModeSwitch
    check b.get.targetMode == EditorMode.Insert

  test "overlay_switch resolves to a ctOverlaySwitch command":
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    let err =
      registry.addRuntimeMappingExpanded(Normal, "C-y", "overlay_switch command")
    check err == ""
    let m = registry.runtimeMappings[Normal][^1]
    check m.command.kind == ctOverlaySwitch
    check m.command.targetOverlay == okCommand

  test "command with args attaches the arguments":
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    let cmd = Command(
      name: "test.args",
      description: "",
      count: 1,
      kind: ctCustom,
      commandId: "test.args",
      args: @[],
    )
    registry.registerCommand(cmd)
    let err = registry.addRuntimeMappingExpanded(Normal, "C-y", "test.args foo bar")
    check err == ""
    let m = registry.runtimeMappings[Normal][^1]
    check m.command.kind == ctCustom
    check m.command.args == @["foo", "bar"]

  test "complex mapping survives a rebuild triggered by another mapping":
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    discard registry.addRuntimeMappingExpanded(Normal, "C-y", "mode_switch insert")
    # A second runtime mapping forces rebuildEffectiveBindings to re-apply all.
    discard registry.addRuntimeMappingExpanded(Normal, "C-u", "delete-char")
    let combo = KeyCombo(isSpecial: false, char: "y", modifiers: {kmCtrl})
    let b = registry.findSingleBinding(Normal, combo)
    check b.isSome
    check b.get.kind == ctModeSwitch
    check b.get.targetMode == EditorMode.Insert

  test "invalid target mode returns an error":
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    let err = registry.addRuntimeMappingExpanded(Normal, "C-y", "mode_switch bogus")
    check err.len > 0
    check registry.runtimeMappings[Normal].len == 0

  test "invalid overlay returns an error":
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    let err = registry.addRuntimeMappingExpanded(Normal, "C-y", "overlay_switch bogus")
    check err.len > 0

  test "bare command name still falls back to addRuntimeMapping":
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    let err = registry.addRuntimeMappingExpanded(Normal, "C-y", "delete-char")
    check err == ""
    let m = registry.runtimeMappings[Normal][^1]
    check m.kind == rmkCommand
    check m.commandName == "delete-char"

  test "non-command multi-key RHS still falls back to a key sequence":
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    let err = registry.addRuntimeMappingExpanded(Insert, "C-y", "g g")
    check err == ""
    let m = registry.runtimeMappings[Insert][^1]
    check m.kind == rmkKeySequence

suite "Integration - Vim-style jj mapping":
  test "Vim-style jj accumulates then triggers":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    # Map jj → Escape in Insert mode (Vim-style notation)
    let err = manager.keyBindingRegistry.addRuntimeMapping(Insert, "jj", "Escape")
    check err == ""

    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    # First 'j' should accumulate
    let j1 = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let r1 = manager.runKeyCombo(editor, j1)
    check r1.kind == hrHandled
    check editor.keyRouter.dispatchState.keys.len == 1

    # Second 'j' should trigger the mapping
    let j2 = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let r2 = manager.runKeyCombo(editor, j2)
    check r2.kind == hrHandled
    check editor.keyRouter.dispatchState.keys.len == 0

  test "Vim-style jj and space-separated j j produce same trigger":
    ## Both notations should create mappings with identical trigger keys
    var reg1 = newKeyBindingRegistry()
    var reg2 = newKeyBindingRegistry()
    discard reg1.addRuntimeMapping(Insert, "jj", "Escape")
    discard reg2.addRuntimeMapping(Insert, "j j", "Escape")
    check reg1.runtimeMappings[Insert][0].triggerKeys ==
      reg2.runtimeMappings[Insert][0].triggerKeys

suite "Integration - Normal mode key-seq mapping":
  test "Normal mode single-key mapping matches immediately":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState(EditorMode.Normal)
    let viewport = createTestViewport()

    # Map C-a → Escape in Normal mode (simple key that won't cause nil access)
    let err = manager.keyBindingRegistry.addRuntimeMapping(Normal, "C-a", "Escape")
    check err == ""

    let keyCombo = KeyCombo(isSpecial: false, char: "a", modifiers: {kmCtrl})
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)
    let r = manager.runKeyCombo(editor, keyCombo)
    check r.kind == hrHandled
    check editor.keyRouter.dispatchState.keys.len == 0

  test "Normal mode multi-key mapping accumulates":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState(EditorMode.Normal)
    let viewport = createTestViewport()

    # Map z z → Escape in Normal mode
    let err = manager.keyBindingRegistry.addRuntimeMapping(Normal, "zz", "Escape")
    check err == ""

    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    # First 'z' should accumulate
    let z1 = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    let r1 = manager.runKeyCombo(editor, z1)
    check r1.kind == hrHandled
    check editor.keyRouter.dispatchState.keys.len == 1

    # Second 'z' should trigger
    let z2 = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    let r2 = manager.runKeyCombo(editor, z2)
    check r2.kind == hrHandled
    check editor.keyRouter.dispatchState.keys.len == 0

suite "Integration - mapping removal and clear":
  test "Removed mapping no longer triggers":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    # Add and then remove mapping
    discard manager.keyBindingRegistry.addRuntimeMapping(Insert, "C-a", "Escape")
    discard manager.keyBindingRegistry.removeRuntimeMapping(Insert, "C-a")

    # Verify no key-seq mappings remain
    let mappings = manager.keyBindingRegistry.getRuntimeKeySeqMappings(Insert)
    check mappings.len == 0

    # Key should pass through to normal insert handler
    let keyA = KeyCombo(isSpecial: false, char: "a", modifiers: {kmCtrl})
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)
    discard manager.runKeyCombo(editor, keyA)
    check editor.keyRouter.dispatchState.keys.len == 0

  test "Cleared mappings no longer trigger":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")

    # Add mappings then clear
    discard manager.keyBindingRegistry.addRuntimeMapping(Insert, "C-a", "Escape")
    discard manager.keyBindingRegistry.addRuntimeMapping(Insert, "C-b", "Enter")
    manager.keyBindingRegistry.clearRuntimeMappings(Insert)

    # Verify no key-seq mappings remain
    let mappings = manager.keyBindingRegistry.getRuntimeKeySeqMappings(Insert)
    check mappings.len == 0

  test "Clear one mode leaves other modes intact":
    let manager = createTestManager()
    discard manager.keyBindingRegistry.addRuntimeMapping(Normal, "C-a", "Escape")
    discard manager.keyBindingRegistry.addRuntimeMapping(Insert, "C-b", "Escape")

    manager.keyBindingRegistry.clearRuntimeMappings(Normal)

    check manager.keyBindingRegistry.getRuntimeKeySeqMappings(Normal).len == 0
    check manager.keyBindingRegistry.getRuntimeKeySeqMappings(Insert).len == 1

  test "Mappings cleared mid-sequence: accumulator flushed, no input lost":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    discard manager.keyBindingRegistry.addRuntimeMapping(Insert, "jk", "Escape")
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    let j = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    discard manager.runKeyCombo(editor, j)
    check editor.keyRouter.dispatchState.keys.len == 1

    manager.keyBindingRegistry.clearRuntimeMappings(Insert)

    let x = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    let r = manager.runKeyCombo(editor, x)
    check r.kind == hrHandled
    check editor.keyRouter.dispatchState.keys.len == 0

suite "Timeout flush - exact match with longer match pending":
  test "Exact match and longer match: keys accumulate (wait state)":
    ## When both "j" (exact) and "jj" (longer) are mapped,
    ## pressing 'j' should accumulate (hasLongerMatch = true)
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    # Map both "j" → "a" and "jj" → Escape in Insert mode
    let err1 = manager.keyBindingRegistry.addRuntimeMapping(Insert, "j", "a")
    check err1 == ""
    let err2 = manager.keyBindingRegistry.addRuntimeMapping(Insert, "jj", "Escape")
    check err2 == ""

    # Press 'j': should accumulate because both exact and longer match exist
    let j = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)
    let r = manager.runKeyCombo(editor, j)
    check r.kind == hrHandled
    check editor.keyRouter.dispatchState.keys.len == 1

  test "Timeout flush finds exact match for accumulated keys":
    ## Simulate what handleKeyMappingTimeout does:
    ## accumulated keys = ["j"], mappings include "j" → "a"
    ## → exact match should be found and executed
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    let err1 = manager.keyBindingRegistry.addRuntimeMapping(Insert, "j", "a")
    check err1 == ""
    let err2 = manager.keyBindingRegistry.addRuntimeMapping(Insert, "jj", "Escape")
    check err2 == ""

    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    # Simulate accumulated state (as if 'j' was pressed and we're waiting)
    let j = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    editor.keyRouter.dispatchState.keys = @[j]

    # Simulate timeout flush logic: find exact match
    let accKeys = editor.keyRouter.dispatchState.keys
    let mappings = manager.keyBindingRegistry.getRuntimeKeySeqMappings(state.mode)
    var exactMatch: Option[RuntimeKeyMapping] = none(RuntimeKeyMapping)
    for m in mappings:
      if m.triggerKeys == accKeys:
        exactMatch = some(m)
        break

    check exactMatch.isSome
    check exactMatch.get.targetKeys.len == 1
    check exactMatch.get.targetKeys[0] == toKeyCombo('a')

    # Execute the exact match via playbackKeyCombos
    clearRuntimeMappingState(editor.keyRouter.dispatchState)
    manager.keyBindingRegistry.isReplayingMapping = true
    let r = playbackKeyCombos(editor, exactMatch.get.targetKeys)
    manager.keyBindingRegistry.isReplayingMapping = false
    check r.kind == hrHandled
    # Should still be in Insert mode (mapping target was 'a', not Escape)
    check state.mode == EditorMode.Insert

  test "Timeout flush executes exact match that causes mode transition":
    ## accumulated keys = ["j"], mappings include "j" → Escape
    ## → exact match executes Escape, causing Insert → Normal transition
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    let err1 = manager.keyBindingRegistry.addRuntimeMapping(Insert, "j", "Escape")
    check err1 == ""
    let err2 = manager.keyBindingRegistry.addRuntimeMapping(Insert, "jj", "a")
    check err2 == ""

    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    # Simulate accumulated state
    let j = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    editor.keyRouter.dispatchState.keys = @[j]

    # Find exact match
    let accKeys = editor.keyRouter.dispatchState.keys
    let mappings = manager.keyBindingRegistry.getRuntimeKeySeqMappings(state.mode)
    var exactMatch: Option[RuntimeKeyMapping] = none(RuntimeKeyMapping)
    for m in mappings:
      if m.triggerKeys == accKeys:
        exactMatch = some(m)
        break

    check exactMatch.isSome

    # Execute via playbackKeyCombos (mirrors handleKeyMappingTimeout logic)
    clearRuntimeMappingState(editor.keyRouter.dispatchState)
    manager.keyBindingRegistry.isReplayingMapping = true
    discard playbackKeyCombos(editor, exactMatch.get.targetKeys)
    manager.keyBindingRegistry.isReplayingMapping = false

    # playbackMacro applies mode transitions internally
    check state.mode == EditorMode.Normal

  test "Timeout flush replays keys when no exact match":
    ## accumulated keys = ["j"], but only "jj" → Escape is mapped (no "j" mapping)
    ## → no exact match, replay 'j' as literal key
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    let err = manager.keyBindingRegistry.addRuntimeMapping(Insert, "jj", "Escape")
    check err == ""

    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    # Simulate accumulated state
    let j = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    editor.keyRouter.dispatchState.keys = @[j]

    # Simulate timeout flush logic: find exact match
    let accKeys = editor.keyRouter.dispatchState.keys
    let mappings = manager.keyBindingRegistry.getRuntimeKeySeqMappings(state.mode)
    var exactMatch: Option[RuntimeKeyMapping] = none(RuntimeKeyMapping)
    for m in mappings:
      if m.triggerKeys == accKeys:
        exactMatch = some(m)
        break

    check exactMatch.isNone

    # No exact match: replay keys individually
    clearRuntimeMappingState(editor.keyRouter.dispatchState)
    manager.keyBindingRegistry.isReplayingMapping = true
    for k in accKeys:
      let r = manager.runKeyCombo(editor, k)
      check r.kind == hrHandled
    manager.keyBindingRegistry.isReplayingMapping = false

    # Should still be in Insert mode (j was inserted as text, not expanded)
    check state.mode == EditorMode.Insert
    # 'j' should have been inserted into the buffer
    let line = buffer.getLine(0)
    check $line == "jhello"

  test "Empty accumulated keys: timeout flush is no-op":
    let manager = createTestManager()
    let router = newKeyRouter(
      manager.keyBindingRegistry, TimeoutPolicy(timeoutlen: 1000, enabled: true)
    )
    # No keys accumulated
    check router.dispatchState.keys.len == 0
    # Nothing to flush - this is the guard check in handleKeyMappingTimeout

suite "Nested playback mini processor":
  test "processReplayedResult on hrError sets statusMessage and returns roAbort":
    # Pre-fix, rrUnhandledBatch broke on hrError but never routed
    # errorMessage onto state.statusMessage; the user saw no diagnostic.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    let state = createTestState(EditorMode.Normal)
    let viewport = createTestViewport()
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    let r = HandlerResult(kind: hrError, errorMessage: "boom")
    let outcome = processReplayedResult(editor, r, buffer)
    check outcome == roAbort
    check state.statusMessage == "boom"

  test "processReplayedResult on hrQuit returns roQuit":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    let state = createTestState(EditorMode.Normal)
    let viewport = createTestViewport()
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    let outcome = processReplayedResult(editor, HandlerResult(kind: hrQuit), buffer)
    check outcome == roQuit

  test "processReplayedResult on hrHandled returns roContinue":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    let state = createTestState(EditorMode.Normal)
    let viewport = createTestViewport()
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    let r = HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
    check processReplayedResult(editor, r, buffer) == roContinue

  test "playbackMacroImpl invalid key aborts and records statusMessage":
    # Pre-fix, playbackMacro dropped the invalid-key hrError silently past the
    # replay boundary; post-fix, the mini processor routes it to statusMessage.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    let state = createTestState(EditorMode.Normal)
    let viewport = createTestViewport()
    let editor =
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry, manager)

    let r = playbackMacro(editor, @["<not-a-real-key>"])
    check r.kind == hrError
    check state.statusMessage.startsWith("Invalid key in macro")

suite "All mapping commands are valid":
  test "All BuiltinCommandId values are registered in CommandRegistry":
    let cmdRegistry = newCommandRegistry()
    cmdRegistry.registerBuiltinCommands()

    var missing: seq[string] = @[]
    for id in BuiltinCommandId:
      if id == bcNone:
        continue
      let cmd = cmdRegistry.findCommand(builtin(id))
      if cmd.isNone or cmd.get.handler.isNil:
        missing.add($id)

    if missing.len > 0:
      echo "Missing commands: ", missing
    check missing.len == 0

  test "All commands from setupDefaultBindings are valid mapping targets":
    var registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()

    for commandName in registry.commandRegistry.keys:
      let err = registry.addRuntimeMapping(Normal, "C-t", commandName)
      check err == ""
      # Clean up by removing the mapping for the next iteration
      discard registry.removeRuntimeMapping(Normal, "C-t")

suite "Command mode command parsing - cmap commands":
  setup:
    let parser = newCommandLineParser()
    let config = newCommandConfig()
    config.loadDefaultConfig()
    config.applyToParser(parser)

  test "Parse :cmap C-a Home":
    let result = parser.parseAndExecute(":cmap C-a Home")
    check result.kind == claCmap
    check result.mapLhs == "C-a"
    check result.mapRhs == "Home"

  test "Parse :cnoremap C-a Home (alias)":
    let result = parser.parseAndExecute(":cnoremap C-a Home")
    check result.kind == claCmap
    check result.mapLhs == "C-a"
    check result.mapRhs == "Home"

  test "Parse :cmap without args returns list request":
    let result = parser.parseAndExecute(":cmap")
    check result.kind == claCmap
    check result.mapLhs == ""
    check result.mapRhs == ""

  test "Parse :cmap with only LHS returns prefix list request":
    let result = parser.parseAndExecute(":cmap C-a")
    check result.kind == claCmap
    check result.mapLhs == "C-a"
    check result.mapRhs == ""

  test "Parse :cunmap C-a":
    let result = parser.parseAndExecute(":cunmap C-a")
    check result.kind == claCunmap
    check result.unmapLhs == "C-a"

  test "Parse :cunmap without args returns error":
    let result = parser.parseAndExecute(":cunmap")
    check result.kind == claUnknown
    check "Usage" in result.errorMessage

  test "Parse :cmapclear":
    let result = parser.parseAndExecute(":cmapclear")
    check result.kind == claCmapclear

suite "CommandModeHandler - cmap commands":
  setup:
    let parser = newCommandLineParser()
    let config = newCommandConfig()
    config.loadDefaultConfig()
    config.applyToParser(parser)
    let commandRegistry = newCommandRegistry()
    let handler = newCommandModeHandler(parser, config, commandRegistry)

  test "handleCommandModeInput :cmap returns hrMapAdd with CommandLine mode":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":cmap C-a Home")
    check result.kind == hrMapAdd
    check result.mapAddLhs == "C-a"
    check result.mapAddRhs == "Home"
    check EditorMode.Command in result.mapAddModes
    check result.mapAddModes.len == 1

  test "handleCommandModeInput :cmap without args returns hrMapList":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":cmap")
    check result.kind == hrMapList
    check EditorMode.Command in result.mapListModes

  test "handleCommandModeInput :cunmap returns hrMapRemove with CommandLine mode":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":cunmap C-a")
    check result.kind == hrMapRemove
    check result.mapRemoveLhs == "C-a"
    check EditorMode.Command in result.mapRemoveModes
    check result.mapRemoveModes.len == 1

  test "handleCommandModeInput :cmapclear returns hrMapClear with CommandLine mode":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":cmapclear")
    check result.kind == hrMapClear
    check EditorMode.Command in result.mapClearModes
    check result.mapClearModes.len == 1

suite "addRuntimeMapping - CommandLine mode":
  test "Add mapping for CommandLine mode":
    var registry = newKeyBindingRegistry()
    let err = registry.addRuntimeMapping(EditorMode.Command, "C-a", "Home")
    check err == ""
    check registry.runtimeMappings[EditorMode.Command].len == 1

  test "CommandLine mapping is independent from Normal":
    var registry = newKeyBindingRegistry()
    discard registry.addRuntimeMapping(EditorMode.Command, "C-a", "Home")
    discard registry.addRuntimeMapping(EditorMode.Normal, "C-a", "Escape")
    check registry.runtimeMappings[EditorMode.Command].len == 1
    check registry.runtimeMappings[EditorMode.Normal].len == 1

  test "Remove CommandLine mapping":
    var registry = newKeyBindingRegistry()
    discard registry.addRuntimeMapping(EditorMode.Command, "C-a", "Home")
    let err = registry.removeRuntimeMapping(EditorMode.Command, "C-a")
    check err == ""
    check registry.runtimeMappings[EditorMode.Command].len == 0

  test "Clear CommandLine mappings":
    var registry = newKeyBindingRegistry()
    discard registry.addRuntimeMapping(EditorMode.Command, "C-a", "Home")
    discard registry.addRuntimeMapping(EditorMode.Command, "C-b", "End")
    registry.clearRuntimeMappings(EditorMode.Command)
    check registry.runtimeMappings[EditorMode.Command].len == 0

  test "List CommandLine mappings":
    var registry = newKeyBindingRegistry()
    discard registry.addRuntimeMapping(EditorMode.Command, "C-a", "Home")
    let listings = registry.listRuntimeMappings(EditorMode.Command)
    check listings.len == 1
    check "C-a -> Home" in listings

  test "getRuntimeKeySeqMappings for CommandLine mode":
    var registry = newKeyBindingRegistry()
    discard registry.addRuntimeMapping(EditorMode.Command, "C-a", "Home")
    let mappings = registry.getRuntimeKeySeqMappings(EditorMode.Command)
    check mappings.len == 1
    check mappings[0].triggerStr == "C-a"

suite "rmkCommand mapping - findBinding integration":
  test "C-j rmkCommand mapping found by processKey in Normal mode":
    var registry = newKeyBindingRegistry()
    # Register the command
    let cmd = Command(
      name: "window-prev",
      description: "Switch to previous window",
      count: 1,
      kind: ctAction,
      commandId: "window.prev",
    )
    registry.registerCommand(cmd)

    # Add runtime mapping: C-j -> window-prev
    let err = registry.addRuntimeMapping(EditorMode.Normal, "C-j", "window-prev")
    check err == ""

    # Verify it's in runtimeMappings as rmkCommand
    check registry.runtimeMappings[EditorMode.Normal].len == 1
    check registry.runtimeMappings[EditorMode.Normal][0].kind == rmkCommand

    # Verify it's also in bindings (via bindKey)
    let ctrlJ = KeyCombo(isSpecial: false, char: "j", modifiers: {kmCtrl})
    let binding = registry.findSingleBinding(EditorMode.Normal, ctrlJ)
    check binding.isSome
    check binding.get.name == "window-prev"
    check binding.get.commandId == "window.prev"

    # Verify processKey finds it too
    let cmdResult = registry.processKey(EditorMode.Normal, ctrlJ)
    check cmdResult.isSome
    check cmdResult.get.name == "window-prev"

  test "C-j rmkCommand mapping found by getAllRuntimeMappings for Filer mode":
    var registry = newKeyBindingRegistry()
    let cmd = Command(
      name: "window-prev",
      description: "Switch to previous window",
      count: 1,
      kind: ctAction,
      commandId: "window.prev",
    )
    registry.registerCommand(cmd)

    let err = registry.addRuntimeMapping(EditorMode.Filer, "C-j", "window-prev")
    check err == ""

    # getRuntimeKeySeqMappings should NOT include rmkCommand
    let seqMappings = registry.getRuntimeKeySeqMappings(EditorMode.Filer)
    check seqMappings.len == 0

    # getAllRuntimeMappings SHOULD include rmkCommand
    let allMappings = registry.getAllRuntimeMappings(EditorMode.Filer)
    check allMappings.len == 1
    check allMappings[0].kind == rmkCommand
    check allMappings[0].commandName == "window-prev"
