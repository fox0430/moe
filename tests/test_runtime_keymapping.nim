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

import ../src/moepkg/key_bindings {.all.}
import ../src/moepkg/modes
import ../src/moepkg/types {.all.}
import ../src/moepkg/motion {.all.}
import ../src/moepkg/command_line
import ../src/moepkg/command_config
import ../src/moepkg/command_registry {.all.}
import ../src/moepkg/registers {.all.}
import ../src/moepkg/buffer
import ../src/moepkg/command_handlers/command_handler
import ../src/moepkg/command_handlers/handler_manager {.all.}
import ../src/moepkg/command_handlers/visual_handler {.all.}
import ../src/moepkg/command_handlers/insert_handler {.all.}

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
    var registry = newKeyBindingRegistry()
    let j = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    registry.runtimeMappingState.keys.add(j)
    check registry.runtimeMappingState.keys.len == 1

    registry.clearRuntimeMappingState()
    check registry.runtimeMappingState.keys.len == 0

suite "Ex command parsing - map commands":
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

  test "Parse :vmap d visual.delete":
    let result = parser.parseAndExecute(":vmap d visual.delete")
    check result.kind == claVmap
    check result.mapLhs == "d"
    check result.mapRhs == "visual.delete"

  test "Parse :noremap C-s file.save (alias)":
    let result = parser.parseAndExecute(":noremap C-s file.save")
    check result.kind == claMap
    check result.mapLhs == "C-s"

  test "Parse :nnoremap C-s file.save (alias)":
    let result = parser.parseAndExecute(":nnoremap C-s file.save")
    check result.kind == claNmap
    check result.mapLhs == "C-s"

  test "Parse :nmap without args returns error":
    let result = parser.parseAndExecute(":nmap")
    check result.kind == claUnknown
    check "Usage" in result.errorMessage

  test "Parse :nmap with only LHS returns error":
    let result = parser.parseAndExecute(":nmap C-s")
    check result.kind == claUnknown
    check "Usage" in result.errorMessage

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

  test "Parse :inoremap (alias)":
    let result = parser.parseAndExecute(":inoremap jj Escape")
    check result.kind == claImap
    check result.mapLhs == "jj"
    check result.mapRhs == "Escape"

  test "Parse :vnoremap (alias)":
    let result = parser.parseAndExecute(":vnoremap d Escape")
    check result.kind == claVmap
    check result.mapLhs == "d"
    check result.mapRhs == "Escape"

suite "Ex command parsing - unmap commands":
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

suite "Ex command parsing - mapclear commands":
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

  test "handleCommandModeInput :nmap returns cmrMapAdd":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":nmap C-s file.save")
    check result.kind == cmrMapAdd
    check result.mapAddLhs == "C-s"
    check result.mapAddRhs == "file.save"
    check EditorMode.Normal in result.mapAddModes
    check result.mapAddModes.len == 1

  test "handleCommandModeInput :imap returns cmrMapAdd for Insert":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":imap j Escape")
    check result.kind == cmrMapAdd
    check EditorMode.Insert in result.mapAddModes

  test "handleCommandModeInput :vmap returns cmrMapAdd for Visual modes":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":vmap d visual.delete")
    check result.kind == cmrMapAdd
    check EditorMode.Visual in result.mapAddModes
    check EditorMode.VisualBlock in result.mapAddModes
    check EditorMode.VisualLine in result.mapAddModes

  test "handleCommandModeInput :map returns cmrMapAdd for all modes":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":map C-s file.save")
    check result.kind == cmrMapAdd
    check result.mapAddModes.len == 6

  test "handleCommandModeInput :nunmap returns cmrMapRemove":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":nunmap C-s")
    check result.kind == cmrMapRemove
    check result.mapRemoveLhs == "C-s"
    check EditorMode.Normal in result.mapRemoveModes

  test "handleCommandModeInput :nmapclear returns cmrMapClear":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":nmapclear")
    check result.kind == cmrMapClear
    check EditorMode.Normal in result.mapClearModes

  test "handleCommandModeInput :rmap returns cmrMapAdd for Replace":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":rmap C-a Escape")
    check result.kind == cmrMapAdd
    check EditorMode.Replace in result.mapAddModes
    check result.mapAddModes.len == 1

  test "handleCommandModeInput :unmap returns cmrMapRemove for all modes":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":unmap C-s")
    check result.kind == cmrMapRemove
    check result.mapRemoveLhs == "C-s"
    check result.mapRemoveModes.len == 6

  test "handleCommandModeInput :iunmap returns cmrMapRemove for Insert":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":iunmap C-a")
    check result.kind == cmrMapRemove
    check EditorMode.Insert in result.mapRemoveModes
    check result.mapRemoveModes.len == 1

  test "handleCommandModeInput :vunmap returns cmrMapRemove for Visual modes":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":vunmap d")
    check result.kind == cmrMapRemove
    check EditorMode.Visual in result.mapRemoveModes
    check EditorMode.VisualBlock in result.mapRemoveModes
    check EditorMode.VisualLine in result.mapRemoveModes

  test "handleCommandModeInput :mapclear returns cmrMapClear for all modes":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":mapclear")
    check result.kind == cmrMapClear
    check result.mapClearModes.len == 6

  test "handleCommandModeInput :imapclear returns cmrMapClear for Insert":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":imapclear")
    check result.kind == cmrMapClear
    check EditorMode.Insert in result.mapClearModes
    check result.mapClearModes.len == 1

  test "handleCommandModeInput :imap jj Escape (Vim-style)":
    let buffer = newTextBuffer()
    let result = handler.handleCommandModeInput(buffer, ":imap jj Escape")
    check result.kind == cmrMapAdd
    check result.mapAddLhs == "jj"
    check result.mapAddRhs == "Escape"
    check EditorMode.Insert in result.mapAddModes

# --- Integration test helpers ---

proc createTestState(mode: EditorMode = EditorMode.Normal): EditorState =
  result = EditorState(
    cursor: BufferPosition(line: 0, column: 0),
    mode: mode,
    previousMode: EditorMode.Normal,
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

  let insertHandler = newInsertModeHandler(
    keyBindingRegistry, motionController, commandRegistry, autocompleteEnabled = false
  )

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

    # First 'j' should be accumulated (waiting for more keys)
    let j1 = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let r1 = manager.handleKeyCombo(buffer, state, viewport, j1)
    check r1.kind == hrHandled
    check manager.keyBindingRegistry.runtimeMappingState.keys.len == 1

    # Second 'j' should trigger the mapping (Escape → Normal mode)
    let j2 = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let r2 = manager.handleKeyCombo(buffer, state, viewport, j2)
    check r2.kind == hrHandled
    # Accumulator should be cleared after match
    check manager.keyBindingRegistry.runtimeMappingState.keys.len == 0

  test "Non-matching key after accumulation flushes":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    # Map j j → Escape in Insert mode
    let err = manager.keyBindingRegistry.addRuntimeMapping(Insert, "j j", "Escape")
    check err == ""

    # First 'j' accumulates
    let j1 = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let r1 = manager.handleKeyCombo(buffer, state, viewport, j1)
    check r1.kind == hrHandled

    # 'k' does not match 'j j' → flush 'j' and process 'k' normally
    let k = KeyCombo(isSpecial: false, char: "k", modifiers: {})
    let r2 = manager.handleKeyCombo(buffer, state, viewport, k)
    # Accumulator should be cleared after flush
    check manager.keyBindingRegistry.runtimeMappingState.keys.len == 0

  test "No mappings registered passes through immediately":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

    # No runtime mappings registered. 'a' should pass through normally.
    let a = KeyCombo(isSpecial: false, char: "a", modifiers: {})
    let result = manager.handleKeyCombo(buffer, state, viewport, a)
    # Should be handled by insert mode handler, not blocked by mapping precheck
    check result.kind == hrHandled

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
    let result = manager.handleKeyCombo(buffer, state, viewport, keyCombo)
    check result.kind == hrHandled
    # Accumulator should be cleared
    check manager.keyBindingRegistry.runtimeMappingState.keys.len == 0

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
    let result = manager.handleKeyCombo(buffer, state, viewport, keyA)
    check result.kind == hrHandled
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
    let result = manager.handleKeyCombo(buffer, state, viewport, keyA)
    # The key should have been processed normally (not consumed by mapping)
    # Accumulator should remain empty
    check manager.keyBindingRegistry.runtimeMappingState.keys.len == 0
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
    let result = manager.handleKeyCombo(buffer, state, viewport, keyA)
    # Accumulator should be empty (no key-seq mappings registered for Insert)
    check manager.keyBindingRegistry.runtimeMappingState.keys.len == 0

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

    # First 'j' should accumulate
    let j1 = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let r1 = manager.handleKeyCombo(buffer, state, viewport, j1)
    check r1.kind == hrHandled
    check manager.keyBindingRegistry.runtimeMappingState.keys.len == 1

    # Second 'j' should trigger the mapping
    let j2 = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let r2 = manager.handleKeyCombo(buffer, state, viewport, j2)
    check r2.kind == hrHandled
    check manager.keyBindingRegistry.runtimeMappingState.keys.len == 0

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
    let result = manager.handleKeyCombo(buffer, state, viewport, keyCombo)
    check result.kind == hrHandled
    check manager.keyBindingRegistry.runtimeMappingState.keys.len == 0

  test "Normal mode multi-key mapping accumulates":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState(EditorMode.Normal)
    let viewport = createTestViewport()

    # Map z z → Escape in Normal mode
    let err = manager.keyBindingRegistry.addRuntimeMapping(Normal, "zz", "Escape")
    check err == ""

    # First 'z' should accumulate
    let z1 = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    let r1 = manager.handleKeyCombo(buffer, state, viewport, z1)
    check r1.kind == hrHandled
    check manager.keyBindingRegistry.runtimeMappingState.keys.len == 1

    # Second 'z' should trigger
    let z2 = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    let r2 = manager.handleKeyCombo(buffer, state, viewport, z2)
    check r2.kind == hrHandled
    check manager.keyBindingRegistry.runtimeMappingState.keys.len == 0

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
    let result = manager.handleKeyCombo(buffer, state, viewport, keyA)
    check manager.keyBindingRegistry.runtimeMappingState.keys.len == 0

  test "Cleared mappings no longer trigger":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState(EditorMode.Insert)
    let viewport = createTestViewport()

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
    let r = manager.handleKeyCombo(buffer, state, viewport, j)
    check r.kind == hrHandled
    check manager.keyBindingRegistry.runtimeMappingState.keys.len == 1

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

    # Simulate accumulated state (as if 'j' was pressed and we're waiting)
    let j = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    manager.keyBindingRegistry.runtimeMappingState.keys = @[j]

    # Simulate timeout flush logic: find exact match
    let accKeys = manager.keyBindingRegistry.runtimeMappingState.keys
    let mappings = manager.keyBindingRegistry.getRuntimeKeySeqMappings(state.mode)
    var exactMatch: Option[RuntimeKeyMapping] = none(RuntimeKeyMapping)
    for m in mappings:
      if m.triggerKeys == accKeys:
        exactMatch = some(m)
        break

    check exactMatch.isSome
    check exactMatch.get.targetKeys.len == 1
    check exactMatch.get.targetKeys[0] == "a"

    # Execute the exact match via playbackMacro
    manager.keyBindingRegistry.clearRuntimeMappingState()
    manager.keyBindingRegistry.isReplayingMapping = true
    let r = manager.playbackMacro(buffer, state, viewport, exactMatch.get.targetKeys)
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

    # Simulate accumulated state
    let j = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    manager.keyBindingRegistry.runtimeMappingState.keys = @[j]

    # Find exact match
    let accKeys = manager.keyBindingRegistry.runtimeMappingState.keys
    let mappings = manager.keyBindingRegistry.getRuntimeKeySeqMappings(state.mode)
    var exactMatch: Option[RuntimeKeyMapping] = none(RuntimeKeyMapping)
    for m in mappings:
      if m.triggerKeys == accKeys:
        exactMatch = some(m)
        break

    check exactMatch.isSome

    # Execute via playbackMacro (mirrors handleKeyMappingTimeout logic)
    manager.keyBindingRegistry.clearRuntimeMappingState()
    manager.keyBindingRegistry.isReplayingMapping = true
    let r = manager.playbackMacro(buffer, state, viewport, exactMatch.get.targetKeys)
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

    # Simulate accumulated state
    let j = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    manager.keyBindingRegistry.runtimeMappingState.keys = @[j]

    # Simulate timeout flush logic: find exact match
    let accKeys = manager.keyBindingRegistry.runtimeMappingState.keys
    let mappings = manager.keyBindingRegistry.getRuntimeKeySeqMappings(state.mode)
    var exactMatch: Option[RuntimeKeyMapping] = none(RuntimeKeyMapping)
    for m in mappings:
      if m.triggerKeys == accKeys:
        exactMatch = some(m)
        break

    check exactMatch.isNone

    # No exact match: replay keys individually
    manager.keyBindingRegistry.clearRuntimeMappingState()
    manager.keyBindingRegistry.isReplayingMapping = true
    for k in accKeys:
      let r = manager.handleKeyCombo(buffer, state, viewport, k)
      check r.kind == hrHandled
    manager.keyBindingRegistry.isReplayingMapping = false

    # Should still be in Insert mode (j was inserted as text, not expanded)
    check state.mode == EditorMode.Insert
    # 'j' should have been inserted into the buffer
    let line = buffer.getLine(0)
    check $line == "jhello"

  test "Empty accumulated keys: timeout flush is no-op":
    let manager = createTestManager()
    # No keys accumulated
    check manager.keyBindingRegistry.runtimeMappingState.keys.len == 0
    # Nothing to flush - this is the guard check in handleKeyMappingTimeout

suite "All mapping commands are valid":
  test "All BuiltinCommandId values are registered in CommandRegistry":
    # Commands dispatched by normal_handler/handler_manager at a higher level.
    # These require editor-level context (buffer switching, LSP client, etc.)
    # and are intentionally not registered in CommandRegistry.
    const dispatchedByHandler = [
      bcJumpBack, bcJumpForward, bcFileSave, bcFileOpen, bcFileNew, bcFileClose,
      bcFiler, bcLspGotoDefinition, bcLspFindReferences, bcLspCodeLensExecute,
      bcLspCallHierarchyIncoming, bcLspCallHierarchyOutgoing,
    ]

    let cmdRegistry = newCommandRegistry()
    cmdRegistry.registerBuiltinCommands()

    var missing: seq[string] = @[]
    for id in BuiltinCommandId:
      if id == bcNone or id in dispatchedByHandler:
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
