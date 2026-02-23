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

import std/[unittest, os, strutils, sequtils]

import pkg/results

import ../src/moepkg/config_loader

const ExampleMoerc = currentSourcePath().parentDir / ".." / "example" / "moerc.toml"

suite "example/moerc.toml":
  test "File exists":
    check fileExists(ExampleMoerc)

  test "Parse without errors":
    let loadResult = loadConfigFromToml(ExampleMoerc)
    if loadResult.isErr:
      echo "  Parse error: ", loadResult.error
    check loadResult.isOk

  test "No validation errors":
    let loadResult = loadConfigFromToml(ExampleMoerc)
    require loadResult.isOk

    let (_, vr) = loadResult.get

    # Filter out Theme.path errors since the theme file may not exist in the
    # test environment.
    let errors = vr.errors.filterIt(
      not (it.name == "Theme.path" and "existing file path" in it.expected)
    )

    if errors.len > 0:
      for e in errors:
        echo "  Validation error: ", e.toErrorMessage
    check errors.len == 0
