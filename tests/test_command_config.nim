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

## Tests for command configuration

import std/[unittest, tables, options]

import ../src/moepkg/command_config {.all.}
import ../src/moepkg/command_line {.all.}

suite "CommandConfig - newCommandConfig":
  test "Creates config with empty aliases":
    let config = newCommandConfig()

    check config.aliases.len == 0

  test "Creates config with empty shell commands":
    let config = newCommandConfig()

    check config.shellCommands.len == 0

  test "Creates config with empty disabled commands":
    let config = newCommandConfig()

    check config.disabledCommands.len == 0

suite "CommandConfig - addAlias":
  test "Adds a single alias":
    let config = newCommandConfig()

    config.addAlias("q", claQuit)

    check config.aliases.len == 1
    check config.aliases["q"] == claQuit

  test "Adds multiple aliases for same action":
    let config = newCommandConfig()

    config.addAlias("q", claQuit)
    config.addAlias("quit", claQuit)

    check config.aliases.len == 2
    check config.aliases["q"] == claQuit
    check config.aliases["quit"] == claQuit

  test "Overwrites existing alias":
    let config = newCommandConfig()

    config.addAlias("x", claQuit)
    config.addAlias("x", claSaveAndQuit)

    check config.aliases.len == 1
    check config.aliases["x"] == claSaveAndQuit

suite "CommandConfig - removeAlias":
  test "Removes an existing alias":
    let config = newCommandConfig()

    config.addAlias("x", claQuit)
    config.removeAlias("x")

    check config.aliases.len == 0
    check "x" notin config.aliases

  test "Removes the alias description too":
    let config = newCommandConfig()

    config.addAlias("x", claQuit, "Quit editor")
    config.removeAlias("x")

    check "x" notin config.aliases
    check "x" notin config.aliasDescriptions

  test "Normalises alias to lowercase":
    let config = newCommandConfig()

    config.addAlias("x", claQuit)
    config.removeAlias("X")

    check "x" notin config.aliases

  test "Removing an unknown alias is a no-op":
    let config = newCommandConfig()

    config.addAlias("x", claQuit)
    config.removeAlias("unknown")

    check config.aliases.len == 1
    check config.aliases["x"] == claQuit

suite "CommandConfig - canonicalCommandName":
  test "Returns the canonical long-form name":
    check canonicalCommandName(claQuit) == some("quit")

  test "Round-trips with resolveCommandName":
    let name = canonicalCommandName(claSaveAndQuit)

    check name.isSome
    check resolveCommandName(name.get) == some(claSaveAndQuit)

suite "CommandConfig - addShellCommand":
  test "Adds a shell command":
    let config = newCommandConfig()

    config.addShellCommand("mycmd", "echo hello")

    check config.shellCommands.len == 1
    check config.shellCommands["mycmd"].command == "echo hello"

  test "Normalises shell command name to lowercase":
    let config = newCommandConfig()
    let parser = newCommandLineParser()

    config.addShellCommand("GitStatus", "git status")
    config.applyToParser(parser)

    check "gitstatus" in parser.shellCommands
    let parsed = parser.parseCommandLine(":GitStatus")
    check parsed.action == claShellCommand
    check parsed.args == @["git status"]

  test "Adds multiple shell commands":
    let config = newCommandConfig()

    config.addShellCommand("cmd1", "def1")
    config.addShellCommand("cmd2", "def2")

    check config.shellCommands.len == 2
    check config.shellCommands["cmd1"].command == "def1"
    check config.shellCommands["cmd2"].command == "def2"

  test "Overwrites existing shell command":
    let config = newCommandConfig()

    config.addShellCommand("cmd", "old")
    config.addShellCommand("cmd", "new")

    check config.shellCommands.len == 1
    check config.shellCommands["cmd"].command == "new"

suite "CommandConfig - disableCommand":
  test "Disables a command":
    let config = newCommandConfig()

    config.disableCommand(claQuit)

    check config.disabledCommands.len == 1
    check claQuit in config.disabledCommands

  test "Does not duplicate disabled command":
    let config = newCommandConfig()

    config.disableCommand(claQuit)
    config.disableCommand(claQuit)

    check config.disabledCommands.len == 1

  test "Disables multiple commands":
    let config = newCommandConfig()

    config.disableCommand(claQuit)
    config.disableCommand(claSave)

    check config.disabledCommands.len == 2
    check claQuit in config.disabledCommands
    check claSave in config.disabledCommands

suite "CommandConfig - enableCommand":
  test "Enables a disabled command":
    let config = newCommandConfig()
    config.disableCommand(claQuit)

    config.enableCommand(claQuit)

    check config.disabledCommands.len == 0

  test "Does nothing when enabling non-disabled command":
    let config = newCommandConfig()

    config.enableCommand(claQuit)

    check config.disabledCommands.len == 0

  test "Only enables specified command":
    let config = newCommandConfig()
    config.disableCommand(claQuit)
    config.disableCommand(claSave)

    config.enableCommand(claQuit)

    check config.disabledCommands.len == 1
    check claQuit notin config.disabledCommands
    check claSave in config.disabledCommands

suite "CommandConfig - isCommandEnabled":
  test "Returns true for enabled command":
    let config = newCommandConfig()

    check config.isCommandEnabled(claQuit) == true

  test "Returns false for disabled command":
    let config = newCommandConfig()
    config.disableCommand(claQuit)

    check config.isCommandEnabled(claQuit) == false

  test "Returns true after re-enabling command":
    let config = newCommandConfig()
    config.disableCommand(claQuit)
    config.enableCommand(claQuit)

    check config.isCommandEnabled(claQuit) == true

suite "CommandConfig - loadDefaultConfig":
  test "Loads buffer navigation aliases":
    let config = newCommandConfig()

    config.loadDefaultConfig()

    check config.aliases["b"] == claBuffer
    check config.aliases["bn"] == claBufferNext
    check config.aliases["bp"] == claBufferPrev
    check config.aliases["bf"] == claBufferFirst
    check config.aliases["bl"] == claBufferLast
    check config.aliases["bd"] == claBufferDelete

  test "Loads LSP command aliases":
    let config = newCommandConfig()

    config.loadDefaultConfig()

    check config.aliases["lsplog"] == claLspLog
    check config.aliases["lspformat"] == claLspFormat
    check config.aliases["lsprestart"] == claLspRestart

suite "CommandConfig - applyToParser":
  test "Applies aliases to parser":
    let config = newCommandConfig()
    let parser = newCommandLineParser()
    config.addAlias("q", claQuit)
    config.addAlias("w", claSave)

    config.applyToParser(parser)

    check parser.aliases.len == 2
    check parser.aliases["q"] == claQuit
    check parser.aliases["w"] == claSave

  test "Clears existing parser aliases":
    let config = newCommandConfig()
    let parser = newCommandLineParser()
    parser.addAlias("old", claHelp)
    config.addAlias("new", claQuit)

    config.applyToParser(parser)

    check parser.aliases.len == 1
    check "old" notin parser.aliases
    check parser.aliases["new"] == claQuit

  test "Does not apply disabled command aliases":
    let config = newCommandConfig()
    let parser = newCommandLineParser()
    config.addAlias("q", claQuit)
    config.addAlias("w", claSave)
    config.disableCommand(claQuit)

    config.applyToParser(parser)

    check parser.aliases.len == 1
    check "q" notin parser.aliases
    check parser.aliases["w"] == claSave

  test "Applies full default config to parser":
    let config = newCommandConfig()
    let parser = newCommandLineParser()
    config.loadDefaultConfig()

    config.applyToParser(parser)

    check parser.aliases.len > 0
    check parser.aliases["q"] == claQuit
    check parser.aliases["w"] == claSave
    check parser.aliases["wq"] == claSaveAndQuit

  test "Applies shell commands to parser":
    let config = newCommandConfig()
    let parser = newCommandLineParser()
    config.addShellCommand("nimbuild", "nimble build")

    config.applyToParser(parser)

    check parser.shellCommands.len == 1
    check parser.shellCommands["nimbuild"].command == "nimble build"

  test "Clears existing shell commands on apply":
    let config = newCommandConfig()
    let parser = newCommandLineParser()
    parser.shellCommands["old"] = ShellCommandEntry(command: "old command")
    config.addShellCommand("new", "new command")

    config.applyToParser(parser)

    check parser.shellCommands.len == 1
    check "old" notin parser.shellCommands
    check parser.shellCommands["new"].command == "new command"

suite "Shell commands - parseCommandLine":
  test "Shell command resolves as claShellCommand":
    let parser = newCommandLineParser()
    parser.shellCommands["nimbuild"] = ShellCommandEntry(command: "nimble build")

    let parsed = parser.parseCommandLine(":nimbuild")

    check parsed.action == claShellCommand
    check parsed.args == @["nimble build"]

  test "Shell command with extra arguments":
    let parser = newCommandLineParser()
    parser.shellCommands["nimbuild"] = ShellCommandEntry(command: "nimble build")

    let parsed = parser.parseCommandLine(":nimbuild --release")

    check parsed.action == claShellCommand
    check parsed.args == @["nimble build --release"]

  test "Built-in alias takes priority over shell command":
    let parser = newCommandLineParser()
    parser.addAlias("q", claQuit)
    parser.shellCommands["q"] = ShellCommandEntry(command: "echo quit")

    let parsed = parser.parseCommandLine(":q")

    check parsed.action == claQuit

  test "Shell command is case-insensitive":
    let parser = newCommandLineParser()
    parser.shellCommands["nimbuild"] = ShellCommandEntry(command: "nimble build")

    let parsed = parser.parseCommandLine(":NimBuild")

    check parsed.action == claShellCommand
    check parsed.args == @["nimble build"]

suite "resolveCommandName":
  test "Resolves known command names":
    check resolveCommandName("quit") == some(claQuit)
    check resolveCommandName("save") == some(claSave)
    check resolveCommandName("saveandquit") == some(claSaveAndQuit)
    check resolveCommandName("terminal") == some(claTerminal)

  test "Case-insensitive resolution":
    check resolveCommandName("Quit") == some(claQuit)
    check resolveCommandName("SAVE") == some(claSave)
    check resolveCommandName("SaveAndQuit") == some(claSaveAndQuit)

  test "Returns none for unknown command":
    check resolveCommandName("nonexistent").isNone
    check resolveCommandName("").isNone

suite "CommandAliases - applyToParser":
  test "User-defined alias resolves to editor command":
    let config = newCommandConfig()
    let parser = newCommandLineParser()
    config.loadDefaultConfig()
    config.addAlias("x", claQuit)

    config.applyToParser(parser)

    let parsed = parser.parseCommandLine(":x")
    check parsed.action == claQuit

  test "User alias overrides default alias":
    let config = newCommandConfig()
    let parser = newCommandLineParser()
    config.loadDefaultConfig()
    # Override "q" from quit to saveAndQuit
    config.addAlias("q", claSaveAndQuit)

    config.applyToParser(parser)

    let parsed = parser.parseCommandLine(":q")
    check parsed.action == claSaveAndQuit

  test "User alias takes priority over shell command":
    let config = newCommandConfig()
    let parser = newCommandLineParser()
    config.addAlias("build", claBuild)
    config.addShellCommand("build", "make build")

    config.applyToParser(parser)

    let parsed = parser.parseCommandLine(":build")
    check parsed.action == claBuild

suite "Shell commands - isNoArgumentAction":
  test "Shell command returns false (accepts arguments)":
    let parser = newCommandLineParser()
    parser.shellCommands["nimbuild"] = ShellCommandEntry(command: "nimble build")

    check parser.isNoArgumentAction("nimbuild") == false

  test "Alias for no-argument action returns true":
    let parser = newCommandLineParser()
    parser.addAlias("q", claQuit)

    check parser.isNoArgumentAction("q") == true

suite "Shell commands - disabled shell command alias":
  test "Disabled command alias is not applied but shell command still works":
    let config = newCommandConfig()
    let parser = newCommandLineParser()
    config.addAlias("q", claQuit)
    config.addShellCommand("mycmd", "echo hello")
    config.disableCommand(claQuit)

    config.applyToParser(parser)

    # Disabled alias should not be in parser
    check "q" notin parser.aliases
    # Shell command should still be available
    check parser.shellCommands["mycmd"].command == "echo hello"

    let parsed = parser.parseCommandLine(":mycmd")
    check parsed.action == claShellCommand
    check parsed.args == @["echo hello"]

suite "Shell commands - multiple extra arguments":
  test "Shell command with multiple extra arguments":
    let parser = newCommandLineParser()
    parser.shellCommands["git"] = ShellCommandEntry(command: "git")

    let parsed = parser.parseCommandLine(":git log --oneline -20")

    check parsed.action == claShellCommand
    check parsed.args == @["git log --oneline -20"]

suite "Description support":
  test "Alias with description is propagated to parser":
    let config = newCommandConfig()
    let parser = newCommandLineParser()
    config.addAlias("x", claQuit, "Exit editor")

    config.applyToParser(parser)

    check parser.aliasDescriptions["x"] == "Exit editor"

  test "Alias without description has no entry in aliasDescriptions":
    let config = newCommandConfig()
    let parser = newCommandLineParser()
    config.addAlias("x", claQuit)

    config.applyToParser(parser)

    check "x" notin parser.aliasDescriptions

  test "Shell command with description":
    let config = newCommandConfig()
    config.addShellCommand("nimbuild", "nimble build", "Build project")

    check config.shellCommands["nimbuild"].description == "Build project"

  test "Shell command without description has empty description":
    let config = newCommandConfig()
    config.addShellCommand("nimbuild", "nimble build")

    check config.shellCommands["nimbuild"].description == ""

  test "Disabled alias description is not propagated":
    let config = newCommandConfig()
    let parser = newCommandLineParser()
    config.addAlias("x", claQuit, "Exit editor")
    config.disableCommand(claQuit)

    config.applyToParser(parser)

    check "x" notin parser.aliases
    check "x" notin parser.aliasDescriptions
