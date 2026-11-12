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

import std/[unittest, os, algorithm, sequtils]

import pkg/[results, parsetoml]

import ../src/moepkg/[config_loader, color, theme]

const ExampleThemesDir = currentSourcePath().parentDir / ".." / "example" / "themes"

proc missingColors(colors: TomlTableRef): seq[string] =
  ## Theme keys whose omission leaves a color at the bundled dark default.
  ## Leaving out a `#000000` default bg is fine (it takes `background`), as
  ## is leaving out the fg of a bg-only or terminal-default-fg entry.
  for key in ["foreground", "background"]:
    if not colors.hasKey(key):
      result.add key

  for index in EditorColorPairIndex:
    if index == EditorColorPairIndex.default:
      continue

    let
      key = toTomlColorKey(index)
      default = DefaultColors[index]
      needsFg =
        index notin ColorBgOnlyEntries and not default.foreground.rgb.isTermDefaultColor
      needsBg = default.background.rgb != rgb("#000000")

    for (side, needed) in [("fg", needsFg), ("bg", needsBg)]:
      let isSet =
        colors.hasKey(key) and colors[key].kind == TomlValueKind.Table and
        colors[key].getTable.hasKey(side)
      if needed and not isSet:
        result.add key & "." & side

suite "example/themes/*.toml":
  test "Bundled themes exist":
    for name in ["dark.toml", "light.toml", "vivid.toml"]:
      check fileExists(ExampleThemesDir / name)

  for path in toSeq(walkFiles(ExampleThemesDir / "*.toml")).sorted:
    let name = path.extractFilename

    test name & ": Parse without errors":
      var vr = newValidationResult()
      let loadResult = loadThemeFromToml(path, vr)
      if loadResult.isErr:
        echo "  Parse error: ", loadResult.error
      check loadResult.isOk

    test name & ": No validation errors":
      var vr = newValidationResult()
      let loadResult = loadThemeFromToml(path, vr)
      require loadResult.isOk

      if vr.errors.len > 0:
        for e in vr.errors:
          echo "  Validation error: ", e.toMessage
      check vr.errors.len == 0

    test name & ": Sets every color":
      let toml = parseFile(path)
      require toml.hasKey("Colors") and toml["Colors"].kind == TomlValueKind.Table

      let missing = missingColors(toml["Colors"].getTable)
      if missing.len > 0:
        echo "  Missing: ", missing
      check missing.len == 0

suite "example/themes/light.toml as the bundled light theme":
  test "loads to LightColors":
    var vr = newValidationResult()
    let loaded = loadThemeFromToml(ExampleThemesDir / "light.toml", vr)
    require loaded.isOk
    check vr.errors.len == 0
    for index in EditorColorPairIndex:
      checkpoint $index
      check loaded.get[index] == LightColors[index]
