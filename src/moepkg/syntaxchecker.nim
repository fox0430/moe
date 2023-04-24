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

import std/[os, osproc, strformat, strutils]
import pkg/[regex, results]
import syntax/highlite
import independentutils, unicodeext

type
  SyntaxCheckMessageType* = enum
    error
    warning
    info
    hint

  MessageTypeResult = Result[SyntaxCheckMessageType, string]

  SyntaxError* = object
    position*: BufferPosition
    messageType*: SyntaxCheckMessageType
    message*: Runes

  SyntaxErrorsResult* = Result[seq[SyntaxError], string]

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

## Parse results of "nim check" command.
proc parseNimCheckResult(path: string, cmdResult: string): SyntaxErrorsResult =
  var syntaxErrors: seq[SyntaxError]

  if not path.isAbsolute:
    return SyntaxErrorsResult.err fmt"Need to an absolute path: {path}"

  for line in cmdResult.splitLines:
    if line.startsWith(path):
      # Find a buffer position
      var m: RegexMatch
      if line.find(re"\((\d+), (\d+)\)", m):
        let
          position = BufferPosition(
            line: line[m.captures[0][0]].parseInt - 1,
            column: line[m.captures[1][0]].parseInt - 1)

          # TODO: Refactor
          messageType = ?toSyntaxCheckMessageType(
            strutils.splitWhitespace(line)[2].split(":")[0])
          message = line[line.find(") ") + 2 .. ^1].toRunes

        syntaxErrors.add SyntaxError(
          position: position,
          messageType: messageType,
          message: message)

  return SyntaxErrorsResult.ok syntaxErrors

## Use commands to check syntax (semantics) of a source code.
proc execSyntaxCheck*(path: string, lang: SourceLanguage): SyntaxErrorsResult =
  case lang:
    of SourceLanguage.langNim:
      # Checks the code for syntax and semantics using "nim check" command.
      let cmdResult = execCmdEx(fmt"nim check {path}")
      if cmdResult.output.len > 0:
        return path.parseNimCheckResult(cmdResult.output)
      else:
        return SyntaxErrorsResult.err fmt"`nim check` command failed: (exitCode: {cmdResult.exitCode})"
    else:
      return SyntaxErrorsResult.err fmt"{lang} does not yet support"
