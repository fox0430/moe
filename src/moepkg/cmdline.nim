#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

## Command line argument parsing
##
## This module handles parsing of command line arguments and provides
## configuration for the editor startup.

import std/[os, strutils, terminal]

import appinfo

type CmdLineConfig* = object ## Command line configuration
  debugEnabled*: bool ## Enable debug logging
  isReadonly*: bool ## Open files in readonly mode
  filePaths*: seq[string] ## File paths to open (supports multiple files)

proc generateVersionInfoMessage(): string =
  const
    VersionInfo = "moe v" & moeSemVersionStr()
    GitHash = "Git hash: " & gitHash()
    BuildType = "Build type: " & buildType()

  result = VersionInfo & "\n\n" & GitHash & "\n" & BuildType

proc showVersion() =
  ## Display version info and exit
  echo generateVersionInfoMessage()
  quit(0)

proc showHelp() =
  ## Display help message and exit
  const HelpMessage =
    """
Usage:
  moe [file]       Edit file

Arguments:
  -R               Readonly mode
  -d, --debug      Enable debug logging
  -h, --help       Print this help
  -v, --version    Print version
"""

  echo generateVersionInfoMessage() & "\n\n" & HelpMessage
  quit(0)

proc showUnknownArgsError(arg: string) =
  stderr.styledWriteLine(
    ForegroundColor.fgRed, "Error: Unknown argument: \"" & arg & "\""
  )
  echo """Please check "moe -h""""
  quit(1)

proc parseCmdLine*(): CmdLineConfig =
  ## Parse command line arguments and return configuration
  ##
  ## Returns:
  ##   CmdLineConfig with parsed settings
  ##
  ## Example:
  ##   let config = parseCmdLine()
  ##   if config.debugEnabled:
  ##     echo "Debug mode enabled"
  result = CmdLineConfig(debugEnabled: false, isReadonly: false, filePaths: @[])

  for i in 1 .. paramCount():
    let arg = paramStr(i)
    case arg
    of "-v", "--version":
      showVersion()
    of "-h", "--help":
      showHelp()
    of "-d", "--debug":
      result.debugEnabled = true
    of "-R":
      result.isReadonly = true
    else:
      if not arg.startsWith("-"):
        result.filePaths.add(arg)
      else:
        showUnknownArgsError(arg)
