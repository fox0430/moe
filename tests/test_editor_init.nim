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

import std/[unittest, tables]

import
  ../src/moepkg/
    [key_bindings, modes, config, config_loader, command_config, editor_init]

suite "editor_init: applyKeyMappings":
  test "\"All\" applies to every mode except Command":
    let registry = newKeyBindingRegistry()
    var km = newEditorConfig().keyMapping
    km.all["a"] = "b"
    registry.applyKeyMappings(km)

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
    km.visualAll["x"] = "y"
    registry.applyKeyMappings(km)

    check registry.runtimeMappings[Visual].len == 1
    check registry.runtimeMappings[VisualBlock].len == 1
    check registry.runtimeMappings[VisualLine].len == 1
    check registry.runtimeMappings[Normal].len == 0

  test "per-mode mapping overrides VisualAll for that mode":
    let registry = newKeyBindingRegistry()
    var km = newEditorConfig().keyMapping
    km.visualAll["g"] = "0" # g -> 0 in every visual mode
    km.visual["g"] = "$" # g -> $ only in Visual (applied later, wins)
    registry.applyKeyMappings(km)

    # Visual: the per-mode mapping replaced the VisualAll one.
    check registry.runtimeMappings[Visual].len == 1
    check registry.runtimeMappings[Visual][0].targetStr == "$"
    # VisualBlock / VisualLine: only the VisualAll mapping remains.
    check registry.runtimeMappings[VisualBlock].len == 1
    check registry.runtimeMappings[VisualBlock][0].targetStr == "0"
    check registry.runtimeMappings[VisualLine][0].targetStr == "0"

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
    cfg.keyMapping.normal["a"] = "b"
    var vr = newValidationResult()
    let (_, keyRegistry, _, _) = newEditorRegistries(cfg, vr)

    var found = false
    for m in keyRegistry.runtimeMappings[Normal]:
      if m.triggerStr == "a":
        found = true
        break
    check found
