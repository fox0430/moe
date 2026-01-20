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

import std/[os, strformat, options]

import pkg/results

import syntax/highlite
import config, buffer, backgroundprocess

export SourceLanguage

type QuickRunProcess* = object
  command*: BackgroundProcessCommand
  filePath*: string
  isTempFile*: bool
  process*: BackgroundProcess

proc quickRunStartupMessage*(path: string): string =
  fmt"Start QuickRun: {path}..."

proc languageExtension(lang: SourceLanguage): Result[string, string] =
  case lang
  of SourceLanguage.langNim:
    Result[string, string].ok "nim"
  of SourceLanguage.langC:
    Result[string, string].ok "c"
  of SourceLanguage.langCpp:
    Result[string, string].ok "cpp"
  of SourceLanguage.langShell:
    # TODO: Add support for other shells.
    Result[string, string].ok "bash"
  of SourceLanguage.langPython:
    Result[string, string].ok "py"
  of SourceLanguage.langRust:
    Result[string, string].ok "rs"
  else:
    Result[string, string].err "Unknown language"

proc isSh(buffer: TextBuffer): bool {.inline.} =
  if buffer.len > 0:
    let firstLine = buffer.getLine(0)
    return firstLine == "#!/bin/sh"
  return false

proc nimQuickRunCommand(
    path: string, settings: QuickRunConfig
): BackgroundProcessCommand =
  const Cmd = "nim"
  var args: seq[string]

  if settings.nimAdvancedCommand.isSome:
    args.add settings.nimAdvancedCommand.get
  else:
    args.add "c" # Default to compile command

  args.add "-r"

  if settings.nimOptions.isSome:
    args.add settings.nimOptions.get

  args.add path

  return BackgroundProcessCommand(cmd: Cmd, args: args)

proc clangQuickRunCommand(
    path: string, settings: QuickRunConfig
): BackgroundProcessCommand {.inline.} =
  let
    options =
      if settings.clangOptions.isSome:
        settings.clangOptions.get & " "
      else:
        ""
    quotedPath = "\"" & path & "\""
  BackgroundProcessCommand(
    cmd: "/bin/bash", args: @["-c", fmt"gcc {options}{quotedPath} -o ./.out && ./.out"]
  )

proc cppQuickRunCommand(
    path: string, settings: QuickRunConfig
): BackgroundProcessCommand {.inline.} =
  let
    options =
      if settings.cppOptions.isSome:
        settings.cppOptions.get & " "
      else:
        ""
    quotedPath = "\"" & path & "\""
  BackgroundProcessCommand(
    cmd: "/bin/bash", args: @["-c", fmt"g++ {options}{quotedPath} -o ./.out && ./.out"]
  )

proc shQuickRunCommand(
    path: string, settings: QuickRunConfig
): BackgroundProcessCommand =
  var args: seq[string]

  if settings.shOptions.isSome:
    args.add settings.shOptions.get

  args.add path

  BackgroundProcessCommand(cmd: "/bin/sh", args: args)

proc bashQuickRunCommand(
    path: string, settings: QuickRunConfig
): BackgroundProcessCommand =
  var args: seq[string]

  if settings.bashOptions.isSome:
    args.add settings.bashOptions.get

  args.add path

  BackgroundProcessCommand(cmd: "/bin/bash", args: args)

proc pythonQuickRunCommand(
    path: string, settings: QuickRunConfig
): BackgroundProcessCommand =
  BackgroundProcessCommand(cmd: "python3", args: @[path])

proc rustQuickRunCommand(
    path: string, settings: QuickRunConfig
): BackgroundProcessCommand =
  # rustc <path> -o ./outName && ./outName
  let
    outName = path.splitFile.name
    quotedPath = "\"" & path & "\""
  BackgroundProcessCommand(
    cmd: "/bin/bash",
    args: @["-c", fmt"rustc {quotedPath} -o ./{outName} && ./{outName}"],
  )

proc quickRunCommand(
    path: string, lang: SourceLanguage, buffer: TextBuffer, settings: QuickRunConfig
): Result[BackgroundProcessCommand, string] =
  var command: BackgroundProcessCommand
  case lang
  of SourceLanguage.langNim:
    command = nimQuickRunCommand(path, settings)
  of SourceLanguage.langC:
    command = clangQuickRunCommand(path, settings)
  of SourceLanguage.langCpp:
    command = cppQuickRunCommand(path, settings)
  of SourceLanguage.langShell:
    if buffer.isSh:
      command = shQuickRunCommand(path, settings)
    else:
      command = bashQuickRunCommand(path, settings)
  of SourceLanguage.langPython:
    command = pythonQuickRunCommand(path, settings)
  of SourceLanguage.langRust:
    command = rustQuickRunCommand(path, settings)
  else:
    return
      Result[BackgroundProcessCommand, string].err "Unsupported language for QuickRun"

  return Result[BackgroundProcessCommand, string].ok command

proc isRunning*(p: QuickRunProcess): bool {.inline.} =
  p.process.isRunning

proc cancel*(p: QuickRunProcess) {.inline.} =
  p.process.cancel

proc kill*(p: QuickRunProcess) {.inline.} =
  p.process.kill

proc close*(p: QuickRunProcess) {.inline.} =
  p.process.close

proc isFinish*(p: QuickRunProcess): bool {.inline.} =
  p.process.isFinish

proc quickRunBufferExists*(buffers: seq[TextBuffer], path: string): bool =
  ## Return true if already exists a buffer for the quickrun.
  # TODO: Implement QuickRun mode detection
  false

proc quickRunBufferIndex*(buffers: seq[TextBuffer], path: string): Option[int] =
  ## Return a buffer index if exists a buffer for the quickrun.
  # TODO: Implement QuickRun mode detection
  none(int)

proc startBackgroundQuickRun*(
    buffer: TextBuffer, settings: EditorConfig
): Result[QuickRunProcess, string] =
  ## Start a background process for build and run commands.

  let
    useTempFile = buffer.filePath.isNone or not fileExists(buffer.filePath.get)
    langExt = buffer.language.languageExtension
    path =
      if useTempFile:
        # A temporary file name.
        if langExt.isErr:
          return Result[QuickRunProcess, string].err langExt.error
        "quickruntemp." & langExt.get
      else:
        buffer.filePath.get

  if settings.quickRun.saveBufferWhenQuickRun and not useTempFile:
    let lastModificationTime = getLastModificationTime(path)
    # TODO: Compare with buffer's last save time
    discard lastModificationTime

  if settings.quickRun.saveBufferWhenQuickRun or useTempFile:
    # Create and use a temporary file if the source code file does not exist.
    let saveResult = buffer.saveFile(path)
    if saveResult.isErr:
      return Result[QuickRunProcess, string].err fmt"Failed to save the current code: {saveResult.error}"

  let command = quickRunCommand(path, buffer.language, buffer, settings.quickRun)
  if command.isErr:
    return Result[QuickRunProcess, string].err fmt"QuickRun failed: {command.error}"

  let backgroundProcess = startBackgroundProcess(command.get)
  if backgroundProcess.isErr:
    return Result[QuickRunProcess, string].err fmt"QuickRun failed: {backgroundProcess.error}"

  return Result[QuickRunProcess, string].ok QuickRunProcess(
    command: command.get,
    filePath: path,
    isTempFile: useTempFile,
    process: backgroundProcess.get,
  )

proc waitForResult*(p: var QuickRunProcess): Result[seq[string], string] =
  ## Wait for the process to finish and return the output.
  ## This is a blocking call.

  let output = p.process.waitFor()

  if p.isTempFile:
    # Cleanup temporary a source code file.
    if p.filePath.fileExists:
      removeFile(p.filePath)
    # Cleanup temporary a executable.
    let baseName = p.filePath.splitFile.name
    if baseName.fileExists:
      removeFile(baseName)
    # Also cleanup .out files for C/C++
    if ".out".fileExists:
      removeFile(".out")

  return Result[seq[string], string].ok output

proc result*(p: var QuickRunProcess): Result[seq[string], string] =
  ## Return an output of execution result.
  ## Note: This will fail if the process is still running.
  ## Use waitForResult() instead for blocking behavior.

  if p.isTempFile:
    # Cleanup temporary a source code file.
    if p.filePath.fileExists:
      removeFile(p.filePath)
    # Cleanup temporary a executable.
    let baseName = p.filePath.splitFile.name
    if baseName.fileExists:
      removeFile(baseName)
    # Also cleanup .out files for C/C++
    if ".out".fileExists:
      removeFile(".out")

  let r = p.process.result
  if r.isOk:
    return Result[seq[string], string].ok r.get
  else:
    return
      Result[seq[string], string].err fmt"QuickRun failed: {$p.filePath}: {r.error}"
