#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[parseopt, os, strformat, terminal]

import settings, appinfo

type CmdParsedList* = object
  path*: seq[string]
  isReadonly*: bool
  isLogger*: bool

proc writeError(msg: string) {.inline.} =
  stderr.styledWriteLine(ForegroundColor.fgRed, "Error: " & msg)

proc generateVersionInfoMessage(): string =
  const
    VersionInfo = "moe v" & moeSemVersionStr()
    GitHash = "Git hash: " & gitHash()
    BuildType = "Build type: " & buildType()

  result =
    VersionInfo & "\n\n" &
    GitHash & "\n" &
    BuildType

proc writeVersion() =
  echo generateVersionInfoMessage()
  quit()

proc generateHelpMessage(): string =
  const HelpMessage = """
Usage:
  moe [file]       Edit file

Arguments:
  -R               Readonly mode
  --log            Start logger
  --init           Create/Overwrite the default configuration file
  -h, --help       Print this help
  -v, --version    Print version
"""

  result = generateVersionInfoMessage() & "\n\n" & HelpMessage

proc writeHelp() =
  echo generateHelpMessage()
  quit()

proc writeCmdLineError(kind: CmdLineKind, arg: string) =
  ## Short option or long option

  let optionStr = if kind == cmdShortOption: "-" else: "--"

  echo fmt"Unknown option argument: {optionStr}{arg}"
  echo """Please check "moe -h""""
  quit()

proc initDefaultConfigFile() =
  ## Create/Overwrite the default configuration file and quit.

  let
    configFileDir = getHomeDir() / ".config/moe/"
    configFilePath = configFileDir & "moerc.toml"

  if fileExists(configFilePath):
    # Back up the config if it already exists.

    let oldConfigFilePath = configFilePath & ".bac"

    try:
      moveFile(configFilePath, oldConfigFilePath)
    except CatchableError as e:
      writeError fmt"Failed to back up the current configuration file: {e.msg}"
      quit(1)

    echo fmt"The current configuration file has been backed up to {oldConfigFilePath}"

  let tomlStr = genDefaultTomlConfigStr()

  try:
    createDir(configFileDir)
    writeFile(configFilePath, tomlStr)
  except CatchableError as e:
    writeError fmt"Failed to init the default configuration file: {e.msg}"
    quit(1)

  echo fmt"The default configuration file has been created to {configFilePath}"

  quit()

proc parseCommandLineOption*(line: seq[string]): CmdParsedList =
  var
    parsedLine = initOptParser(line)
    index = 0
  for kind, key, val in parsedLine.getopt():
    case kind:
      of cmdArgument:
        result.path.add(key)
      of cmdShortOption:
        case key:
          of "v": writeVersion()
          of "h": writeHelp()
          of "R": result.isReadonly = true
          else: writeCmdLineError(kind, key)
      of cmdLongOption:
        case key:
          of "log": result.isLogger = true
          of "init": initDefaultConfigFile()
          of "version": writeVersion()
          of "help": writeHelp()
          else: writeCmdLineError(kind, key)
      of cmdEnd:
        assert(false)

    inc(index)
