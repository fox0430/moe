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

proc looksLikeKey(line: string): bool =
  ## Whether `line` is a `key = value` rather than a sentence that happens to
  ## contain an equals sign.
  let eq = line.find('=')
  if eq <= 0:
    return false
  let name = line[0 ..< eq].strip
  if name.len == 0:
    return false
  for c in name:
    if not (c.isAlphaNumeric or c == '_'):
      return false
  true

proc uncommentedHookSection(): string =
  ## The `[Hook]` example as TOML the loader can read.
  ##
  ## The block ships commented out, so nothing else here checks that what it
  ## shows is a config moe would actually accept: the rules about which event
  ## takes which key live on the field declarations, and an example written
  ## from memory drifts from them silently.
  ##
  ## Headers and `key = value` lines are taken and the prose between them is
  ## left behind. A sentence written to look like a key is the one thing this
  ## cannot tell apart, and then the load fails and says so.
  var inHook = false
  for line in readFile(ExampleMoerc).splitLines:
    let bare =
      if line.startsWith("# "):
        line[2 ..^ 1]
      elif line == "#":
        ""
      else:
        line
    if bare.startsWith("[Hook") or bare.startsWith("[[Hook"):
      inHook = true
    elif inHook and bare.startsWith("["):
      break
    if not inHook:
      continue
    if bare.startsWith("[") or bare.looksLikeKey:
      result.add bare & "\n"

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
        echo "  Validation error: ", e.toMessage
    check errors.len == 0

  test "The [Hook] example is a config the loader accepts":
    let toml = uncommentedHookSection()
    check "[Hook]" in toml
    check toml.count("[[Hook.entries]]") == 2

    let path = getTempDir() / "moe_test_moerc_hook_example.toml"
    defer:
      removeFile(path)
    writeFile(path, toml)

    let loadResult = loadConfigFromToml(path)
    require loadResult.isOk
    let (config, vr) = loadResult.get
    for e in vr.errors:
      echo "  Validation error: ", e.toMessage
    check vr.errors.len == 0
    # Both entries survived: a rejected one is dropped whole.
    check config.hooks.entries.len == 2
