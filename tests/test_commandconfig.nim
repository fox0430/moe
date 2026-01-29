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

import std/[unittest, tables]

import ../src/moepkg/commandconfig {.all.}
import ../src/moepkg/commandline {.all.}

suite "CommandConfig - newCommandConfig":
  test "Creates config with empty aliases":
    let config = newCommandConfig()

    check config.aliases.len == 0

  test "Creates config with empty custom commands":
    let config = newCommandConfig()

    check config.customCommands.len == 0

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

suite "CommandConfig - addCustomCommand":
  test "Adds a custom command":
    let config = newCommandConfig()

    config.addCustomCommand("myCmd", "echo hello")

    check config.customCommands.len == 1
    check config.customCommands["myCmd"] == "echo hello"

  test "Adds multiple custom commands":
    let config = newCommandConfig()

    config.addCustomCommand("cmd1", "def1")
    config.addCustomCommand("cmd2", "def2")

    check config.customCommands.len == 2
    check config.customCommands["cmd1"] == "def1"
    check config.customCommands["cmd2"] == "def2"

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
  test "Loads quit command aliases":
    let config = newCommandConfig()

    config.loadDefaultConfig()

    check config.aliases["q"] == claQuit
    check config.aliases["quit"] == claQuit
    check config.aliases["qa"] == claQuitAll
    check config.aliases["qall"] == claQuitAll

  test "Loads save command aliases":
    let config = newCommandConfig()

    config.loadDefaultConfig()

    check config.aliases["w"] == claSave
    check config.aliases["write"] == claSave
    check config.aliases["wa"] == claSaveAll
    check config.aliases["wall"] == claSaveAll

  test "Loads combined command aliases":
    let config = newCommandConfig()

    config.loadDefaultConfig()

    check config.aliases["wq"] == claSaveAndQuit
    check config.aliases["x"] == claSaveAndQuit
    check config.aliases["xit"] == claSaveAndQuit
    check config.aliases["wqa"] == claSaveAllAndQuit
    check config.aliases["xa"] == claSaveAllAndQuit

  test "Loads edit command aliases":
    let config = newCommandConfig()

    config.loadDefaultConfig()

    check config.aliases["e"] == claEdit
    check config.aliases["edit"] == claEdit
    check config.aliases["ene"] == claEnew
    check config.aliases["enew"] == claEnew

  test "Loads buffer navigation aliases":
    let config = newCommandConfig()

    config.loadDefaultConfig()

    check config.aliases["b"] == claBuffer
    check config.aliases["bn"] == claBufferNext
    check config.aliases["bp"] == claBufferPrev
    check config.aliases["bf"] == claBufferFirst
    check config.aliases["bl"] == claBufferLast
    check config.aliases["bd"] == claBufferDelete

  test "Loads window split aliases":
    let config = newCommandConfig()

    config.loadDefaultConfig()

    check config.aliases["vs"] == claVSplit
    check config.aliases["vsplit"] == claVSplit
    check config.aliases["sp"] == claHSplit
    check config.aliases["split"] == claHSplit
    check config.aliases["new"] == claNew
    check config.aliases["vnew"] == claVnew

  test "Loads LSP command aliases":
    let config = newCommandConfig()

    config.loadDefaultConfig()

    check config.aliases["lspLog"] == claLspLog
    check config.aliases["lspFormat"] == claLspFormat
    check config.aliases["lspRestart"] == claLspRestart

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
