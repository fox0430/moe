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

import std/[unittest, os]

import pkg/results

import ../src/moepkg/config_loader

const
  ExampleThemesDir = currentSourcePath().parentDir / ".." / "example" / "themes"
  ThemeFiles = ["dark.toml", "light.toml", "vivid.toml"]

suite "example/themes/*.toml":
  for name in ThemeFiles:
    let path = ExampleThemesDir / name

    test name & ": File exists":
      check fileExists(path)

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
          echo "  Validation error: ", e.toErrorMessage
      check vr.errors.len == 0
