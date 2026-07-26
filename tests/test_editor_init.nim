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

import std/[unittest, tables, os, strutils]

import pkg/parsetoml

import
  ../src/moepkg/[
    key_bindings, modes, config, config_loader, command_config, command_line,
    editor_init,
  ]

proc entry(rhs: string): KeyMappingEntry =
  KeyMappingEntry(rhs: rhs, noremap: true)

suite "editor_init: applyKeyMappings":
  test "\"All\" applies to every mode except Command":
    let registry = newKeyBindingRegistry()
    var km = newEditorConfig().keyMapping
    km.all["a"] = entry("b")
    var vr = newValidationResult()
    registry.applyKeyMappings(km, vr)

    # Registered for ordinary modes ...
    check registry.runtimeMappings[Normal].len == 1
    check registry.runtimeMappings[Normal][0].kind == rmkKeySequence
    check registry.runtimeMappings[Insert].len == 1
    check registry.runtimeMappings[Filer].len == 1
    # ... but explicitly skipped for Command.
    check registry.runtimeMappings[EditorMode.Command].len == 0

  test "\"VisualAll\" applies to the three visual modes only":
    let registry = newKeyBindingRegistry()
    var km = newEditorConfig().keyMapping
    km.visualAll["x"] = entry("y")
    var vr = newValidationResult()
    registry.applyKeyMappings(km, vr)

    check registry.runtimeMappings[Visual].len == 1
    check registry.runtimeMappings[VisualBlock].len == 1
    check registry.runtimeMappings[VisualLine].len == 1
    check registry.runtimeMappings[Normal].len == 0

  test "per-mode mapping overrides VisualAll for that mode":
    let registry = newKeyBindingRegistry()
    var km = newEditorConfig().keyMapping
    km.visualAll["g"] = entry("0") # g -> 0 in every visual mode
    km.perMode[Visual]["g"] = entry("$") # g -> $ only in Visual (applied later, wins)
    var vr = newValidationResult()
    registry.applyKeyMappings(km, vr)

    # Visual: the per-mode mapping replaced the VisualAll one.
    check registry.runtimeMappings[Visual].len == 1
    check registry.runtimeMappings[Visual][0].targetStr == "$"
    # VisualBlock / VisualLine: only the VisualAll mapping remains.
    check registry.runtimeMappings[VisualBlock].len == 1
    check registry.runtimeMappings[VisualBlock][0].targetStr == "0"
    check registry.runtimeMappings[VisualLine][0].targetStr == "0"

  test "per-mode section overrides All for the same key (documented precedence)":
    # Mirrors the configfile.md "Application order" example: [All] x = commandA
    # and [Normal] x = commandB resolve to commandB in Normal, because the
    # per-mode section (step 4) overrides All (step 2) — independent of origin.
    let registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    var km = newEditorConfig().keyMapping
    km.all["x"] = entry("save") # commandA via [KeyMapping.All]
    km.perMode[Normal]["x"] = entry("undo") # commandB via [Normal]
    var vr = newValidationResult()
    registry.applyKeyMappings(km, vr)

    var target = ""
    for m in registry.runtimeMappings[Normal]:
      if m.triggerStr == "x":
        target = m.targetStr
    check target == "undo" # per-mode wins over All

suite "editor_init: newEditorRegistries":
  test "creates and initializes all four registries":
    let cfg = newEditorConfig()
    var vr = newValidationResult()
    let (cmdRegistry, keyRegistry, cmdConfig, cmdLineParser) =
      newEditorRegistries(cfg, vr)

    check not cmdRegistry.isNil
    check not keyRegistry.isNil
    check not cmdConfig.isNil
    check not cmdLineParser.isNil

    # setupDefaultBindings populated default bindings and the command registry.
    check keyRegistry.bindings[Normal].len > 0
    check keyRegistry.commandRegistry.len > 0
    # loadDefaultConfig registered command aliases.
    check cmdConfig.aliases.len > 0

  test "applies [KeyMapping] overrides from config":
    # The full pipeline may also load the user's keybindings file, so assert the
    # configured mapping is present rather than that it is the only one.
    let cfg = newEditorConfig()
    cfg.keyMapping.perMode[Normal]["a"] = entry("b")
    var vr = newValidationResult()
    let (_, keyRegistry, _, _) = newEditorRegistries(cfg, vr)

    var found = false
    for m in keyRegistry.runtimeMappings[Normal]:
      if m.triggerStr == "a":
        found = true
        break
    check found

suite "editor_init: applyCommandConfig":
  test "DisabledCommandAliases removes built-in default aliases":
    let cfg = newEditorConfig()
    cfg.disabledCommandAliases = @["q", "w"]
    var vr = newValidationResult()
    let (_, _, cmdConfig, cmdLineParser) = newEditorRegistries(cfg, vr)

    check "q" notin cmdConfig.aliases
    check "w" notin cmdConfig.aliases
    check "q" notin cmdLineParser.aliases
    check "w" notin cmdLineParser.aliases
    # Other defaults are untouched.
    check "wq" in cmdLineParser.aliases

  test "User alias may reuse a disabled default's name":
    let cfg = newEditorConfig()
    cfg.disabledCommandAliases = @["q"]
    cfg.commandAliases["q"] = UserCommandEntry(command: "quitall")
    var vr = newValidationResult()
    let (_, _, cmdConfig, cmdLineParser) = newEditorRegistries(cfg, vr)

    check cmdLineParser.aliases["q"] == claQuitAll

  test "Rebuild resets session-level alias changes":
    let cfg = newEditorConfig()
    var vr = newValidationResult()
    let (_, _, cmdConfig, cmdLineParser) = newEditorRegistries(cfg, vr)

    # Session-level changes: add a custom alias, remove a default one.
    cmdConfig.addAlias("zz", claQuit)
    cmdConfig.removeAlias("q")
    cmdConfig.applyToParser(cmdLineParser)
    check "zz" in cmdLineParser.aliases
    check "q" notin cmdLineParser.aliases

    # A reload-style rebuild from the same config restores the declared state.
    cmdConfig.applyCommandConfig(cfg, cmdLineParser)
    check "zz" notin cmdLineParser.aliases
    check "zz" notin cmdConfig.aliases
    check "q" in cmdLineParser.aliases

  test "Rebuild picks up config edits (live reload path)":
    let cfg = newEditorConfig()
    var vr = newValidationResult()
    let (_, _, cmdConfig, cmdLineParser) = newEditorRegistries(cfg, vr)

    # Simulate a live reload with edited aliases/shell commands.
    cfg.commandAliases["zz"] = UserCommandEntry(command: "quit")
    cfg.shellCommands["gitlog"] = UserCommandEntry(command: "git log")
    cfg.disabledCommandAliases = @["q"]
    cmdConfig.applyCommandConfig(cfg, cmdLineParser)

    check cmdLineParser.aliases["zz"] == claQuit
    check "q" notin cmdLineParser.aliases
    check "gitlog" in cmdLineParser.shellCommands

suite "editor_init: applyKeyMappings inline entries":
  test "forceKeySeq with noremap=false records a recursive key sequence":
    let registry = newKeyBindingRegistry()
    var km = newEditorConfig().keyMapping
    km.perMode[Normal]["x"] =
      KeyMappingEntry(rhs: "dd", forceKeySeq: true, noremap: false)
    var vr = newValidationResult()
    registry.applyKeyMappings(km, vr)

    check not vr.hasErrors
    check registry.runtimeMappings[Normal].len == 1
    let m = registry.runtimeMappings[Normal][0]
    check m.kind == rmkKeySequence
    check m.targetStr == "dd"
    check m.noremap == false

  test "command with spaced args attaches them verbatim (not split)":
    let registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    registry.registerCommand(
      Command(
        name: "test.args",
        description: "",
        count: 1,
        kind: ctCustom,
        commandId: "test.args",
        args: @[],
      )
    )
    var km = newEditorConfig().keyMapping
    km.perMode[Normal]["C-p"] =
      KeyMappingEntry(rhs: "test.args", args: @["foo bar"], noremap: true)
    var vr = newValidationResult()
    registry.applyKeyMappings(km, vr)

    check not vr.hasErrors
    var cmd: RuntimeKeyMapping
    var found = false
    for m in registry.runtimeMappings[Normal]:
      if m.triggerStr == "C-p":
        cmd = m
        found = true
    check found
    check cmd.kind == rmkCommand
    # The whitespace-bearing arg stays a single element (no re-tokenization).
    check cmd.command.args == @["foo bar"]

  test "unknown command with args is reported in vr":
    let registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    var km = newEditorConfig().keyMapping
    km.perMode[Normal]["C-p"] =
      KeyMappingEntry(rhs: "no-such-command", args: @["x"], noremap: true)
    var vr = newValidationResult()
    registry.applyKeyMappings(km, vr)

    check vr.hasErrors

suite "editor_init: reapplyKeyMappings (config reload)":
  test "resets to the configured state, dropping session :nmap and removed entries":
    let registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()

    # A session-style runtime mapping (as if added via :nmap) ...
    discard registry.addRuntimeMapping(Normal, "Z", "save")
    # ... plus an initial config mapping.
    var km1 = newEditorConfig().keyMapping
    km1.perMode[Normal]["C-s"] = entry("save")
    var vr1 = newValidationResult()
    registry.applyKeyMappings(km1, vr1)

    # Reload with a different config: C-s removed, C-q added.
    var km2 = newEditorConfig().keyMapping
    km2.perMode[Normal]["C-q"] = entry("quit-force")
    var vr2 = newValidationResult()
    registry.reapplyKeyMappings(km2, vr2)
    check not vr2.hasErrors

    var hasCq, hasCs, hasZ = false
    for m in registry.runtimeMappings[Normal]:
      if m.triggerStr == "C-q":
        hasCq = true
      if m.triggerStr == "C-s":
        hasCs = true
      if m.triggerStr == "Z":
        hasZ = true
    check hasCq # newly configured mapping is present
    check not hasCs # removed from config -> gone after reload
    check not hasZ # session :nmap -> reset to configured state

suite "editor_init: bare RHS command-typo warning":
  test "identifier-like unknown RHS warns but is still applied as a key sequence":
    let registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    var km = newEditorConfig().keyMapping
    km.perMode[Normal]["S-j"] = entry("bnxt") # looks like a command, unregistered
    var vr = newValidationResult()
    registry.applyKeyMappings(km, vr)

    check vr.hasErrors # warning surfaced
    # ... but the mapping is still applied (as a key sequence), not dropped.
    var found = false
    for m in registry.runtimeMappings[Normal]:
      if m.triggerStr == "S-j":
        found = true
        check m.kind == rmkKeySequence
    check found

  test "special-key RHS does not warn":
    let registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    var km = newEditorConfig().keyMapping
    km.perMode[Normal]["C-x"] = entry("Escape")
    var vr = newValidationResult()
    registry.applyKeyMappings(km, vr)

    check not vr.hasErrors

  test "registered command RHS does not warn":
    let registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    var km = newEditorConfig().keyMapping
    km.perMode[Normal]["C-x"] = entry("save")
    var vr = newValidationResult()
    registry.applyKeyMappings(km, vr)

    check not vr.hasErrors

  test "apply error labels use the section name, not a KeyMapping prefix":
    let registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    var km = newEditorConfig().keyMapping
    km.perMode[Normal]["S-j"] = entry("bnxt") # per-mode -> label "Normal.S-j"
    km.all["S-k"] = entry("bnyt") # All section -> label "All.<mode>.S-k"
    var vr = newValidationResult()
    registry.applyKeyMappings(km, vr)

    check vr.hasErrors
    var hasNormalLabel, hasAllLabel = false
    for e in vr.errors:
      check not e.name.startsWith("KeyMapping") # no phantom prefix
      if e.name == "Normal.S-j":
        hasNormalLabel = true
      if e.name.startsWith("All.") and e.name.endsWith(".S-k"):
        hasAllLabel = true
    check hasNormalLabel
    check hasAllLabel

suite "config_loader: shipped example keybindings.toml":
  test "example/keybindings.toml loads and applies cleanly":
    # The dedicated keymap file format example must stay valid (no load errors,
    # no unknown commands / typos at apply time). Replaces the deleted #2851
    # check for the old [[keybinding]] example.
    let path = currentSourcePath().parentDir.parentDir / "example" / "keybindings.toml"
    check fileExists(path)

    var km = newEditorConfig().keyMapping
    var vr = newValidationResult()
    # A dedicated keymap file is the whole top-level table (mode sections).
    loadKeyMappingConfig(parseFile(path).getTable(), km, vr)
    check not vr.hasErrors

    let registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()
    registry.applyKeyMappings(km, vr)
    check not vr.hasErrors

suite "config_loader: dedicated keymap file":
  test "loadKeyMappingFile merges top-level mode sections from the XDG path":
    let tmp = getTempDir() / "moe_keymap_file_test"
    removeDir(tmp)
    createDir(tmp / "moe")
    writeFile(
      tmp / "moe" / "keybindings.toml",
      "[Normal]\njj = \"Escape\"\nx = { keys = \"dd\", noremap = false }\n",
    )
    let
      hadXdg = existsEnv("XDG_CONFIG_HOME")
      oldXdg = getEnv("XDG_CONFIG_HOME")
    putEnv("XDG_CONFIG_HOME", tmp)
    try:
      var km = newEditorConfig().keyMapping
      var vr = newValidationResult()
      loadKeyMappingFile(km, vr)
      check not vr.hasErrors
      check km.perMode[Normal]["jj"].rhs == "Escape"
      check km.perMode[Normal]["x"].forceKeySeq == true
      check km.perMode[Normal]["x"].noremap == false
    finally:
      if hadXdg:
        putEnv("XDG_CONFIG_HOME", oldXdg)
      else:
        delEnv("XDG_CONFIG_HOME")
      removeDir(tmp)

  test "dedicated-file error labels match top-level sections (no KeyMapping prefix)":
    let toml = parseString(
      """
[Normal]
"C-1" = "save"

[Bogus]
"x" = "y"
"""
    )
    var km = newEditorConfig().keyMapping
    var vr = newValidationResult()
    loadKeyMappingConfig(toml.getTable(), km, vr, section = "")

    check vr.hasErrors
    var foundBogus, foundNormalC1 = false
    for e in vr.errors:
      check not e.name.startsWith("KeyMapping") # no phantom prefix
      if e.name == "Bogus":
        foundBogus = true
      if e.name == "Normal.C-1":
        foundNormalC1 = true
    check foundBogus # unknown top-level section
    check foundNormalC1 # bad LHS reported at its real path

  test "every EditorMode member is accepted as a [KeyMapping.<mode>] section":
    # Guards against the pre-refactor drift where the section allowlist was
    # a hand-written array parallel to EditorMode: a new enum member had to be
    # mirrored into the allowlist or its section would be silently rejected as
    # an unknown key.
    var lines: seq[string]
    for m in EditorMode:
      lines.add "[" & $m & "]"
      lines.add "\"j\" = \"down\""
    let toml = parseString(lines.join("\n"))
    var km = newEditorConfig().keyMapping
    var vr = newValidationResult()
    loadKeyMappingConfig(toml.getTable(), km, vr, section = "")

    check not vr.hasErrors
    for m in EditorMode:
      check km.perMode[m].getOrDefault("j").rhs == "down"
