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

## Command configuration system
##
## This module handles configuration of command line commands, allowing users
## to customize command aliases and behavior through configuration files.

import std/[tables, sequtils]

import command_line

type CommandConfig* = ref object ## Configuration for command line commands
  aliases*: Table[string, CommandLineAction]
  customCommands*: Table[string, string] ## Custom command definitions
  disabledCommands*: seq[CommandLineAction] ## Disabled built-in commands

proc newCommandConfig*(): CommandConfig =
  ## Create a new command configuration with defaults
  CommandConfig(
    aliases: initTable[string, CommandLineAction](),
    customCommands: initTable[string, string](),
  )

proc addAlias*(config: CommandConfig, alias: string, action: CommandLineAction) =
  ## Add a command alias
  config.aliases[alias] = action

proc addCustomCommand*(config: CommandConfig, name: string, definition: string) =
  ## Add a custom command definition
  config.customCommands[name] = definition

proc disableCommand*(config: CommandConfig, action: CommandLineAction) =
  ## Disable a built-in command
  if action notin config.disabledCommands:
    config.disabledCommands.add(action)

proc enableCommand*(config: CommandConfig, action: CommandLineAction) =
  ## Re-enable a previously disabled command
  config.disabledCommands.keepItIf(it != action)

proc isCommandEnabled*(config: CommandConfig, action: CommandLineAction): bool =
  ## Check if a command is enabled
  action notin config.disabledCommands

proc loadDefaultConfig*(config: CommandConfig) =
  ## Load default command configuration.
  ## This is the single source of truth for all command aliases.
  ## When adding a new command, add its aliases here.

  # Standard quit commands
  config.addAlias("q", claQuit)
  config.addAlias("quit", claQuit)
  config.addAlias("qa", claQuitAll)
  config.addAlias("qall", claQuitAll)

  # Save commands
  config.addAlias("w", claSave)
  config.addAlias("write", claSave)
  config.addAlias("wa", claSaveAll)
  config.addAlias("wall", claSaveAll)

  # Combined commands
  config.addAlias("wq", claSaveAndQuit)
  config.addAlias("x", claSaveAndQuit)
  config.addAlias("xit", claSaveAndQuit)
  config.addAlias("wqa", claSaveAllAndQuit)
  config.addAlias("xa", claSaveAllAndQuit)

  # Edit commands
  config.addAlias("e", claEdit)
  config.addAlias("edit", claEdit)
  config.addAlias("ene", claEnew)
  config.addAlias("enew", claEnew)

  # Settings
  config.addAlias("set", claSet)
  config.addAlias("se", claSet)

  # Help
  config.addAlias("help", claHelp)

  # Substitute
  config.addAlias("s", claSubstitute)
  config.addAlias("substitute", claSubstitute)

  # Window split
  config.addAlias("vs", claVSplit)
  config.addAlias("vsplit", claVSplit)
  config.addAlias("sp", claHSplit)
  config.addAlias("sv", claHSplit)
  config.addAlias("split", claHSplit)
  config.addAlias("new", claNew)
  config.addAlias("vnew", claVnew)

  # Buffer navigation
  config.addAlias("b", claBuffer)
  config.addAlias("buffer", claBuffer)
  config.addAlias("bn", claBufferNext)
  config.addAlias("bnext", claBufferNext)
  config.addAlias("bp", claBufferPrev)
  config.addAlias("bprev", claBufferPrev)
  config.addAlias("bprevious", claBufferPrev)
  config.addAlias("bf", claBufferFirst)
  config.addAlias("bfirst", claBufferFirst)
  config.addAlias("brewind", claBufferFirst)
  config.addAlias("bl", claBufferLast)
  config.addAlias("blast", claBufferLast)
  config.addAlias("bd", claBufferDelete)
  config.addAlias("bdelete", claBufferDelete)

  # Strip whitespace
  config.addAlias("stripwhitespace", claStripWhitespace)
  config.addAlias("stripws", claStripWhitespace)
  config.addAlias("deletetrailingspaces", claStripWhitespace)

  # Filer (file explorer)
  config.addAlias("filer", claFiler)
  config.addAlias("ex", claFiler)
  config.addAlias("explore", claFiler)

  # Log viewer
  config.addAlias("log", claLogViewer)
  config.addAlias("messages", claLogViewer)

  # QuickRun
  config.addAlias("run", claQuickRun)
  config.addAlias("quickrun", claQuickRun)
  config.addAlias("qr", claQuickRun)

  # Buffer manager
  config.addAlias("buffers", claBufferManager)
  config.addAlias("buf", claBufferManager)
  config.addAlias("ls", claBufferManager)
  config.addAlias("files", claBufferManager)

  # Backup manager
  config.addAlias("backup", claBackupManager)

  # Recent file
  config.addAlias("recent", claRecentFile)

  # Clear search highlight
  config.addAlias("nohlsearch", claClearSearchHighlight)

  # Background (pause editor and show terminal)
  config.addAlias("bg", claBackground)

  # Jump list
  config.addAlias("jump", claJumpList)

  # Build
  config.addAlias("build", claBuild)

  # Debug mode
  config.addAlias("debug", claDebug)

  # Configuration mode
  config.addAlias("config", claConfig)

  # Put config file
  config.addAlias("putconfigfile", claPutConfigFile)

  # Manual
  config.addAlias("man", claMan)

  # Theme
  config.addAlias("theme", claTheme)

  # LSP commands (lowercase - parser converts input to lowercase)
  config.addAlias("lsplog", claLspLog)
  config.addAlias("lspformat", claLspFormat)
  config.addAlias("lsprestart", claLspRestart)
  config.addAlias("lspfold", claLspFold)
  config.addAlias("lspexecommand", claLspExecuteCommand)
  config.addAlias("lspcallhierarchyincoming", claLspCallHierarchyIncoming)
  config.addAlias("lspcallhierarchyoutgoing", claLspCallHierarchyOutgoing)

proc applyToParser*(config: CommandConfig, parser: CommandLineParser) =
  ## Apply configuration to a command line parser
  # Clear existing aliases
  parser.aliases.clear()

  # Apply configured aliases (only for enabled commands)
  for alias, action in config.aliases.pairs:
    if config.isCommandEnabled(action):
      parser.aliases[alias] = action
