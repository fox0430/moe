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

import std/[tables, sequtils, options, strutils]

import command_line

# Mapping from canonical command names to CommandLineAction.
# Used for resolving user-defined aliases in [CommandAliases] config.
const CommandNameTable* = {
  "quit": claQuit,
  "quitall": claQuitAll,
  "save": claSave,
  "saveall": claSaveAll,
  "saveandquit": claSaveAndQuit,
  "saveallandquit": claSaveAllAndQuit,
  "edit": claEdit,
  "enew": claEnew,
  "set": claSet,
  "help": claHelp,
  "substitute": claSubstitute,
  "vsplit": claVSplit,
  "hsplit": claHSplit,
  "new": claNew,
  "vnew": claVnew,
  "buffernext": claBufferNext,
  "bufferprev": claBufferPrev,
  "bufferfirst": claBufferFirst,
  "bufferlast": claBufferLast,
  "bufferdelete": claBufferDelete,
  "buffer": claBuffer,
  "stripwhitespace": claStripWhitespace,
  "filer": claFiler,
  "log": claLogViewer,
  "quickrun": claQuickRun,
  "buffermanager": claBufferManager,
  "backup": claBackupManager,
  "recent": claRecentFile,
  "noh": claClearSearchHighlight,
  "shell": claShellCommand,
  "background": claBackground,
  "jumplist": claJumpList,
  "changes": claChanges,
  "bookmarks": claBookmarks,
  "build": claBuild,
  "debug": claDebug,
  "config": claConfig,
  "putconfigfile": claPutConfigFile,
  "man": claMan,
  "theme": claTheme,
  "lsplog": claLspLog,
  "lspformat": claLspFormat,
  "lsprestart": claLspRestart,
  "lspfold": claLspFold,
  "lspexecommand": claLspExecuteCommand,
  "lspcallhierarchyincoming": claLspCallHierarchyIncoming,
  "lspcallhierarchyoutgoing": claLspCallHierarchyOutgoing,
  "terminal": claTerminal,
  "only": claOnlyWindow,
  "editconfigfile": claEditConfigFile,
  "filetree": claFileTree,
}.toTable

proc resolveCommandName*(name: string): Option[CommandLineAction] =
  ## Resolve a command name string to a CommandLineAction.
  ## Returns none if the name is not recognized.
  let lower = name.toLowerAscii()
  if lower in CommandNameTable:
    return some(CommandNameTable[lower])
  return none(CommandLineAction)

type CommandConfig* = ref object ## Configuration for command line commands
  aliases*: Table[string, CommandLineAction]
  aliasDescriptions*: Table[string, string] ## Custom descriptions for aliases
  shellCommands*: Table[string, ShellCommandEntry] ## Shell command definitions
  disabledCommands*: seq[CommandLineAction] ## Disabled built-in commands

proc newCommandConfig*(): CommandConfig =
  ## Create a new command configuration with defaults
  CommandConfig(
    aliases: initTable[string, CommandLineAction](),
    aliasDescriptions: initTable[string, string](),
    shellCommands: initTable[string, ShellCommandEntry](),
  )

proc addAlias*(
    config: CommandConfig, alias: string, action: CommandLineAction, description = ""
) =
  ## Add a command alias with optional description
  config.aliases[alias] = action
  if description.len > 0:
    config.aliasDescriptions[alias] = description
  else:
    config.aliasDescriptions.del(alias)

proc addShellCommand*(
    config: CommandConfig, name: string, command: string, description = ""
) =
  ## Add a shell command definition with optional description
  config.shellCommands[name] =
    ShellCommandEntry(command: command, description: description)

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
  config.addAlias("qa", claQuitAll)

  # Save commands
  config.addAlias("w", claSave)
  config.addAlias("wa", claSaveAll)

  # Combined commands
  config.addAlias("wq", claSaveAndQuit)
  config.addAlias("wqa", claSaveAllAndQuit)

  # Edit commands
  config.addAlias("e", claEdit)
  config.addAlias("ene", claEnew)

  # Settings
  config.addAlias("set", claSet)

  # Help
  config.addAlias("help", claHelp)

  # Substitute
  config.addAlias("s", claSubstitute)

  # Window split
  config.addAlias("vs", claVSplit)
  config.addAlias("sp", claHSplit)
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

  # Log viewer
  config.addAlias("log", claLogViewer)
  config.addAlias("messages", claLogViewer)

  # QuickRun
  config.addAlias("quickrun", claQuickRun)

  # Buffer manager
  config.addAlias("ls", claBufferManager)

  # Backup manager
  config.addAlias("backup", claBackupManager)

  # Recent file
  config.addAlias("recent", claRecentFile)

  # Clear search highlight
  config.addAlias("noh", claClearSearchHighlight)

  # Background (pause editor and show terminal)
  config.addAlias("bg", claBackground)

  # Jump list
  config.addAlias("jump", claJumpList)

  # Change list
  config.addAlias("changes", claChanges)

  # Bookmarks
  config.addAlias("bookmarks", claBookmarks)

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

  # LSP commands
  config.addAlias("lsplog", claLspLog)
  config.addAlias("lspformat", claLspFormat)
  config.addAlias("lsprestart", claLspRestart)
  config.addAlias("lspfold", claLspFold)
  config.addAlias("lspexecommand", claLspExecuteCommand)
  config.addAlias("lspcallhierarchyincoming", claLspCallHierarchyIncoming)
  config.addAlias("lspcallhierarchyoutgoing", claLspCallHierarchyOutgoing)

  # Terminal
  config.addAlias("terminal", claTerminal)

  # Key mapping commands
  config.addAlias("map", claMap)
  config.addAlias("noremap", claMap)
  config.addAlias("nmap", claNmap)
  config.addAlias("nnoremap", claNmap)
  config.addAlias("imap", claImap)
  config.addAlias("inoremap", claImap)
  config.addAlias("vmap", claVmap)
  config.addAlias("vnoremap", claVmap)
  config.addAlias("rmap", claRmap)
  config.addAlias("cmap", claCmap)
  config.addAlias("cnoremap", claCmap)

  # Key unmapping commands
  config.addAlias("unmap", claUnmap)
  config.addAlias("nunmap", claNunmap)
  config.addAlias("iunmap", claIunmap)
  config.addAlias("vunmap", claVunmap)
  config.addAlias("runmap", claRunmap)
  config.addAlias("cunmap", claCunmap)

  # File tree sidebar
  config.addAlias("filetree", claFileTree)

  # Only window (close all other windows)
  config.addAlias("only", claOnlyWindow)

  # Edit config file
  config.addAlias("moerc", claEditConfigFile)

  # Key mapping clear commands
  config.addAlias("mapclear", claMapclear)
  config.addAlias("nmapclear", claNmapclear)
  config.addAlias("imapclear", claImapclear)
  config.addAlias("vmapclear", claVmapclear)
  config.addAlias("rmapclear", claRmapclear)
  config.addAlias("cmapclear", claCmapclear)

proc applyToParser*(config: CommandConfig, parser: CommandLineParser) =
  ## Apply configuration to a command line parser
  # Clear existing aliases
  parser.aliases.clear()
  parser.aliasDescriptions.clear()

  # Apply configured aliases (only for enabled commands)
  for alias, action in config.aliases.pairs:
    if config.isCommandEnabled(action):
      parser.aliases[alias] = action
      if alias in config.aliasDescriptions:
        parser.aliasDescriptions[alias] = config.aliasDescriptions[alias]

  # Apply shell commands
  parser.shellCommands.clear()
  for name, entry in config.shellCommands.pairs:
    parser.shellCommands[name] = entry
