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

import std/[unittest, options, os, sequtils, strutils]

import pkg/results

import ../src/moepkg/[config_loader, config]

var testFileCounter {.global.} = 0

proc loadFromTomlString(tomlStr: string): (EditorConfig, ValidationResult) =
  inc testFileCounter
  let testFile =
    getTempDir() / "moe_test_quick_run_config_" & $testFileCounter & ".toml"
  writeFile(testFile, tomlStr)
  defer:
    removeFile(testFile)

  let loadResult = loadConfigFromToml(testFile)
  check loadResult.isOk
  return loadResult.get

suite "QuickRun config - entries":
  test "No entries by default":
    let (config, vr) = loadFromTomlString("")
    check not vr.hasErrors
    check config.quickRun.entries.len == 0

  test "A full entry":
    let (config, vr) = loadFromTomlString(
      """
[QuickRun]
timeout = 10

[[QuickRun.entries]]
filetype = ["nim"]
filter = "/scratch/"
command = "nimbang ${file}"
workingDir = "~/src"
"""
    )
    check not vr.hasErrors
    check config.quickRun.timeout == 10
    check config.quickRun.entries.len == 1
    let entry = config.quickRun.entries[0]
    check entry.filetype == @["nim"]
    check entry.filter == "/scratch/"
    check entry.command == "nimbang ${file}"
    check entry.workingDir == "~/src"
    # Compiled once at load.
    check entry.filterRegex.regex.isSome

  test "Entries keep their order":
    let (config, vr) = loadFromTomlString(
      """
[[QuickRun.entries]]
filter = "/scratch/"
command = "first"

[[QuickRun.entries]]
command = "second"
"""
    )
    check not vr.hasErrors
    check config.quickRun.entries.mapIt(it.command) == @["first", "second"]

  test "The built-in keys still load beside entries":
    let (config, vr) = loadFromTomlString(
      """
[QuickRun]
saveBufferWhenQuickRun = false
NimOptions = "-d:release"

[[QuickRun.entries]]
command = "make run"
"""
    )
    check not vr.hasErrors
    check not config.quickRun.saveBufferWhenQuickRun
    check config.quickRun.nimOptions == some("-d:release")
    check config.quickRun.entries.len == 1

suite "QuickRun config - entry validation":
  # An entry is dropped whole rather than run half-configured.
  # A template, not a proc: `check` must expand inside the test to fail it.
  template checkRejected(toml: string, badKey: string) =
    let (config, vr) = loadFromTomlString(toml)
    check vr.hasErrors
    check vr.errors.anyIt(it.name.startsWith(badKey))
    check config.quickRun.entries.len == 0

  test "Missing command":
    checkRejected("[[QuickRun.entries]]\nfiletype = [\"nim\"]\n", "QuickRun.entries[0]")

  test "Empty command":
    checkRejected(
      "[[QuickRun.entries]]\ncommand = \"  \"\n", "QuickRun.entries[0].command"
    )

  test "Command with a quote left open":
    checkRejected(
      "[[QuickRun.entries]]\ncommand = \"nimbang '${file}\"\n",
      "QuickRun.entries[0].command",
    )

  test "Command naming no program":
    checkRejected(
      "[[QuickRun.entries]]\ncommand = \"'' ${file}\"\n", "QuickRun.entries[0].command"
    )

  test "Command of the wrong type":
    checkRejected("[[QuickRun.entries]]\ncommand = 1\n", "QuickRun.entries[0].command")

  test "Unknown filetype":
    checkRejected(
      "[[QuickRun.entries]]\ncommand = \"true\"\nfiletype = [\"nimrod\"]\n",
      "QuickRun.entries[0].filetype",
    )

  test "Unparsable filter":
    checkRejected(
      "[[QuickRun.entries]]\ncommand = \"true\"\nfilter = \"(\"\n",
      "QuickRun.entries[0].filter",
    )

  test "A bad entry does not take the good ones with it":
    let (config, vr) = loadFromTomlString(
      """
[[QuickRun.entries]]
command = "first"

[[QuickRun.entries]]
filetype = ["nim"]

[[QuickRun.entries]]
command = "third"
"""
    )
    check vr.hasErrors
    check config.quickRun.entries.mapIt(it.command) == @["first", "third"]

  test "An unknown key in an entry is reported but keeps the entry":
    let (config, vr) =
      loadFromTomlString("[[QuickRun.entries]]\ncommand = \"make\"\ntypo = 1\n")
    check config.quickRun.entries.len == 1
    check vr.errors.anyIt(it.kind == sikUnknownKey and "typo" in it.name)

  test "An unknown key in [QuickRun] is reported":
    # A group does not check its own table; the loader has to.
    let (_, vr) = loadFromTomlString("[QuickRun]\ntypo = 1\n")
    check vr.errors.anyIt(it.kind == sikUnknownKey and it.name == "QuickRun.typo")

  test "entries that is not an array of tables is reported":
    let (config, vr) = loadFromTomlString("[QuickRun]\nentries = \"make\"\n")
    check vr.hasErrors
    check config.quickRun.entries.len == 0

suite "QuickRun config - the removed command key":
  test "It is reported as an unknown key":
    let (config, vr) = loadFromTomlString("[QuickRun]\ncommand = \"make\"\n")
    check vr.errors.anyIt(it.kind == sikUnknownKey and it.name == "QuickRun.command")
    check config.quickRun.entries.len == 0

suite "QuickRun config - options split into arguments":
  # Split as a command line is, so a quote left open is caught at startup
  # rather than failing every run.
  for key in ["nimAdvancedCommand", "NimOptions", "shOptions", "bashOptions"]:
    test key & " with a quote left open is reported and dropped":
      let (config, vr) =
        loadFromTomlString("[QuickRun]\n" & key & " = \"-d:msg='hi\"\n")
      check vr.errors.anyIt(it.kind == sikInvalidValue and it.name == "QuickRun." & key)
      let q = config.quickRun
      check q.nimAdvancedCommand.isNone and q.nimOptions.isNone and q.shOptions.isNone and
        q.bashOptions.isNone

  test "Closed quotes load as written":
    let (config, vr) =
      loadFromTomlString("[QuickRun]\nNimOptions = \"-d:msg='a b' --opt:speed\"\n")
    check not vr.hasErrors
    check config.quickRun.nimOptions == some("-d:msg='a b' --opt:speed")

suite "QuickRun config - round trip":
  test "Saving and reloading preserves every entry":
    var config = newEditorConfig()
    config.quickRun.timeout = 5
    config.quickRun.nimOptions = some("-d:release")
    config.quickRun.entries = @[
      QuickRunEntry(
        filetype: @["nim"],
        filter: r"\.nim$",
        command: "nimbang ${file}",
        workingDir: "/src",
      ),
      QuickRunEntry(command: "make run"),
    ]

    let path = getTempDir() / "moe_test_quick_run_config_roundtrip.toml"
    defer:
      removeFile(path)
    check saveConfigToToml(config, path).isOk

    let loaded = loadConfigFromToml(path)
    check loaded.isOk
    let (reloaded, vr) = loaded.get
    check not vr.hasErrors
    check reloaded.quickRun == config.quickRun

  test "Saving with no entries writes an empty array":
    var lines: seq[string]
    appendQuickRunToml(lines, newEditorConfig().quickRun)
    check "entries = []" in lines
    check not lines.anyIt(it.startsWith("command = "))

  test "Saving writes every key of an entry":
    var config = newEditorConfig()
    config.quickRun.entries = @[QuickRunEntry(command: "make")]

    var lines: seq[string]
    appendQuickRunToml(lines, config.quickRun)

    check "[[QuickRun.entries]]" in lines
    for key in ["command", "filetype", "filter", "workingDir"]:
      check lines.anyIt(it.startsWith(key & " = "))
