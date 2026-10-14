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

import std/[strutils, options]

import pkg/[results, chronos, regex]

import background_process, primitives, buffer/core
import syntax/tokenizer

import types/syntax_checker_types
export syntax_checker_types

type SyntaxCheckProcess* = object
  command*: BackgroundProcessCommand
  filePath*: string
  process*: BackgroundProcess

proc syntaxCheckCommand*(
    path: string, lang: SourceLanguage
): Result[BackgroundProcessCommand, string] =
  case lang
  of SourceLanguage.langNim:
    return Result[BackgroundProcessCommand, string].ok BackgroundProcessCommand(
      cmd: "nim", args: @["check", path], workingDir: ""
    )
  else:
    return Result[BackgroundProcessCommand, string].err(
      "Syntax check not supported for this language"
    )

let nimCheckPosPattern = re2(r"\((\d+), (\d+)\)")

proc parseNimCheckResult*(path: string, output: seq[string]): seq[SyntaxCheckError] =
  ## Parse `nim check` output into SyntaxCheckError objects.
  ## Format: path(line, col) MsgType: message
  for line in output:
    if line.len == 0:
      continue
    # Match lines containing the file path followed by '(' (position info)
    if not line.contains(path & "("):
      continue
    # Extract position
    var m = RegexMatch2()
    if not line.find(nimCheckPosPattern, m):
      continue
    let lineNum = parseInt(line[m.group(0)]) - 1 # 0-based
    let col = parseInt(line[m.group(1)])
    # Extract message type and message after the position
    let afterPos = m.boundaries.b + 1
    let rest = line[afterPos ..< line.len].strip()
    var msgType: SyntaxCheckMessageType
    var msg: string
    if rest.startsWith("Error:"):
      msgType = SyntaxCheckMessageType.error
      msg = rest["Error:".len ..< rest.len].strip()
    elif rest.startsWith("Warning:"):
      msgType = SyntaxCheckMessageType.warning
      msg = rest["Warning:".len ..< rest.len].strip()
    elif rest.startsWith("Hint:"):
      msgType = SyntaxCheckMessageType.hint
      msg = rest["Hint:".len ..< rest.len].strip()
    elif rest.startsWith("Info:"):
      msgType = SyntaxCheckMessageType.info
      msg = rest["Info:".len ..< rest.len].strip()
    else:
      continue
    result.add SyntaxCheckError(
      position: BufferPosition(line: lineNum, column: col),
      messageType: msgType,
      message: msg,
    )

proc startBackgroundSyntaxCheck*(
    path: string, lang: SourceLanguage
): Result[SyntaxCheckProcess, string] =
  let command = syntaxCheckCommand(path, lang)
  if command.isErr:
    return Result[SyntaxCheckProcess, string].err(command.error)

  let backgroundProcess = startBackgroundProcess(command.get)
  if backgroundProcess.isErr:
    return Result[SyntaxCheckProcess, string].err(
      "Failed to start syntax check: " & backgroundProcess.error
    )

  return Result[SyntaxCheckProcess, string].ok SyntaxCheckProcess(
    command: command.get, filePath: path, process: backgroundProcess.get
  )

proc waitForAsync*(
    bp: SyntaxCheckProcess, timeout: Duration, stop: JobStop = nil
): Future[ProcessOutputResult] {.async: (raises: []).} =
  ## Wait for the syntax check to complete and return its output. A check still
  ## running after `timeout`, or told to `stop`, is killed and reported as an
  ## error.
  return await bp.process.waitForAsync(timeout, stop)

proc applySyntaxCheckToBuffer*(b: TextBuffer, errors: seq[SyntaxCheckError]) =
  ## Replace the buffer's syntax check diagnostics with `errors`.
  var items: seq[BufferDiagnostic]
  for err in errors:
    if err.position.line >= 0 and err.position.line < b.len:
      let severity =
        case err.messageType
        of SyntaxCheckMessageType.error: bdsError
        of SyntaxCheckMessageType.warning: bdsWarning
        of SyntaxCheckMessageType.info: bdsInformation
        of SyntaxCheckMessageType.hint: bdsHint
      items.add BufferDiagnostic(
        startLine: err.position.line,
        startCol: err.position.column,
        endLine: err.position.line,
        endCol: err.position.column,
        severity: severity,
        message: err.message,
      )
  b.setDiagnostics(dsrcSyntaxCheck, items)

proc syntaxCheckMessage*(b: TextBuffer, line: int): Option[string] =
  ## The first syntax check message for `line`.
  for d in b.diagnostics[dsrcSyntaxCheck].items:
    if d.startLine == line:
      let prefix =
        case d.severity
        of bdsError: "Error"
        of bdsWarning: "Warning"
        of bdsInformation: "Info"
        of bdsHint: "Hint"
      return some(prefix & ": " & d.message)
