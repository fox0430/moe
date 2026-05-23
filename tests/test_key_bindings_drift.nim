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

## Drift detection between per-mode binding tables (key → cmd-name) and the
## command tables in `key_bindings/commands.nim` (cmd-name → description).
##
## Every command name bound in any mode's bindings must be registered through
## `registerAllCommands`; otherwise the binding would resolve to nothing at
## runtime. This test catches accidental binding-of-typo'd-command-name
## regressions at CI time.
##
## Scope: this test only validates `bindings.cmd` ↔ `commands.name`. It does
## NOT validate `help_generator.nim`'s `syntax:` / `description:` strings,
## which are independent free-form text and need a separate cross-check
## (e.g. derive `syntax:` from `<mode>Bindings.key`).

import std/[unittest, sets]

import ../src/moepkg/command_config
import ../src/moepkg/key_bindings/normal_bindings {.all.}
import ../src/moepkg/key_bindings/insert_bindings {.all.}
import ../src/moepkg/key_bindings/visual_bindings {.all.}
import ../src/moepkg/key_bindings/commands {.all.}

suite "key bindings — command name drift detection":
  test "every binding cmd-name resolves to a known command":
    var registered: HashSet[string]
    for entry in MotionCommands:
      registered.incl entry.name
    for entry in ActionCommands:
      registered.incl entry.name
    for entry in CustomCommands:
      registered.incl entry.name
    for entry in ModeSwitchCommands:
      registered.incl entry.name
    for entry in OverlaySwitchCommands:
      registered.incl entry.name
    for entry in OperatorPendingCommands:
      registered.incl entry.name
    for alias in keyMappableCommandModeAliases:
      registered.incl alias.name

    let bindingGroups = {
      "Normal": @NormalBindings,
      "InsertReplace": @InsertReplaceBindings,
      "SharedVisual": @SharedVisualBindings,
      "VisualOnly": @VisualOnlyBindings,
      "VisualBlockOnly": @VisualBlockOnlyBindings,
    }

    var missing: seq[string]
    for (groupName, bindings) in bindingGroups:
      for (key, cmd) in bindings:
        if cmd notin registered:
          missing.add(groupName & ": " & key & " → " & cmd)

    for entry in missing:
      echo "  unregistered: ", entry
    check missing.len == 0
