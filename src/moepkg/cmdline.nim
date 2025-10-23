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

import std/[os, strutils]

type CmdLineConfig* = object ## Command line configuration
  debugEnabled*: bool ## Enable debug logging
  filePath*: string ## File path to open

proc showHelp() =
  ## Display help message and exit
  echo """
  Usage: moe [OPTIONS] [FILE]

  Options:"
    -d, --debug    Enable debug logging to ./moe-debug.log"
    -h, --help     Show this help message"
  """

  quit(0)

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
  result = CmdLineConfig(debugEnabled: false, filePath: "")

  # TODO: Add version
  for i in 1 .. paramCount():
    let arg = paramStr(i)
    case arg
    of "--debug", "-d":
      result.debugEnabled = true
    of "--help", "-h":
      showHelp()
    else:
      if not arg.startsWith("-"):
        result.filePath = arg
