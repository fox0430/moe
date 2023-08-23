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

import std/[os, strformat, strutils, options]
import pkg/[regex, results]
import syntax/highlite
import independentutils, unicodeext, backgroundprocess

type
  SyntaxCheckMessageType* = enum
    info
    hint
    warning
    error

  MessageTypeResult = Result[SyntaxCheckMessageType, string]

  SyntaxError* = object
    position*: BufferPosition
    messageType*: SyntaxCheckMessageType
    message*: Runes

  SyntaxErrorsResult* = Result[seq[SyntaxError], string]

  SyntaxCheckProcess* = object
    command*: BackgroundProcessCommand
    filePath*: Runes
    process*: BackgroundProcess

proc isSyntaxCheckFormatedMessage*(m: string | Runes): bool {.inline.} =
  startsWith($m, "SyntaxError: ")

proc formatedMessage*(
  syntaxErrors: seq[SyntaxError],
  line: int): Option[Runes] =
    ## Return a formated syntax error message with the position for
    ## the specified line, if it exists.
    ## Message exmaple: "SyntaxError: (1, 2) Syntax error!"

    for se in syntaxErrors:
      if line == se.position.line:
        return fmt"SyntaxError: ({$se.position.line}, {$se.position.column}) {$se.message}"
          .toRunes
          .some

proc syntaxCheckCommand(
  path: string,
  lang: SourceLanguage): Result[BackgroundProcessCommand, string] =

    case lang:
      of SourceLanguage.langNim:
        # Checks the code for syntax and semantics using "nim check" command.
        return Result[BackgroundProcessCommand, string].ok BackgroundProcessCommand(
          cmd: "nim",
          args: @["check", path])
      else:
        return Result[BackgroundProcessCommand, string].err "Unknown language"

proc toSyntaxCheckMessageType(s: string): MessageTypeResult =
  case s.toLowerAscii:
    of "error":
      return MessageTypeResult.ok SyntaxCheckMessageType.error
    of "warning":
      return MessageTypeResult.ok SyntaxCheckMessageType.warning
    of "info":
      return MessageTypeResult.ok SyntaxCheckMessageType.info
    of "hint":
      return MessageTypeResult.ok SyntaxCheckMessageType.hint
    else:
      MessageTypeResult.err fmt"Invalid value: {s}"

# Parse a message type (Error, Warning, etc...) from the line of nim check result.
proc parseNimSyntaxCheckMessageType(line: string): MessageTypeResult =
  let messageTypeStr =
    try:
      strutils.splitWhitespace(line)[2].split(":")[0]
    except IndexDefect:
      return MessageTypeResult.err "Failed to parse error message type"

  return messageTypeStr.toSyntaxCheckMessageType

# Parse a message from the line of nim check result.
proc parseNimSyntaxCheckMessage(line: string): Result[string, string] =
  try:
    # TODO: Refactor
    return Result[string, string].ok line[line.find(") ") + 2 .. ^1]
  except IndexDefect:
    return Result[string, string].err "Failed to parse error message"

## Parse results of "nim check" command.
proc parseNimCheckResult*(path: string, cmdResult: seq[string]): SyntaxErrorsResult =
  var syntaxErrors: seq[SyntaxError]

  if not path.isAbsolute:
    return SyntaxErrorsResult.err fmt"Need to an absolute path: {path}"

  for line in cmdResult:
    if line.startsWith(path):
      # Find a buffer position
      var m: RegexMatch2
      if line.find(re2"\((\d+), (\d+)\)", m):
        let
          position = BufferPosition(
            line: line[m.captures[0]].parseInt - 1,
            column: line[m.captures[1]].parseInt - 1)

          messageType = ?line.parseNimSyntaxCheckMessageType
          message = ?line.parseNimSyntaxCheckMessage

        syntaxErrors.add SyntaxError(
          position: position,
          messageType: messageType,
          message: message.toRunes)

  return SyntaxErrorsResult.ok syntaxErrors

proc isRunning*(p: SyntaxCheckProcess): bool {.inline.} = p.process.isRunning

proc result*(
  bp: var SyntaxCheckProcess): Result[seq[string], string] {.inline.} =

    bp.process.result

proc startBackgroundSyntaxCheck*(
  path: string, lang: SourceLanguage): Result[SyntaxCheckProcess, string] =
    ## Start the syntax check on a background process.
    ## Use commands to check syntax (semantics) of a source code.

    let command = syntaxCheckCommand(path.absolutePath, lang)
    if command.isErr:
      return Result[SyntaxCheckProcess, string].err fmt"Syntax check failed: {command.error}"

    let backgroundProcess = startBackgroundProcess(command.get)
    if backgroundProcess.isErr:
      return Result[SyntaxCheckProcess, string].err fmt"Failed to exec build commands: {backgroundProcess.error}"

    return Result[SyntaxCheckProcess, string].ok SyntaxCheckProcess(
      command: command.get,
      filePath: path.toRunes,
      process: backgroundProcess.get)
