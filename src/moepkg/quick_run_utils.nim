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

import std/[os, strformat, options, strutils]

import pkg/[results, chronos]

import syntax/tokenizer
import config, buffer/[core, file_io], background_process

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
  of SourceLanguage.langLua:
    Result[string, string].ok "lua"
  of SourceLanguage.langGo:
    Result[string, string].ok "go"
  else:
    Result[string, string].err "Unknown language"

proc isSh(buffer: TextBuffer): bool {.inline.} =
  if buffer.len > 0:
    let firstLine = buffer.getLine(0)
    return firstLine == "#!/bin/sh"
  return false

proc parseShebang(buffer: TextBuffer): Option[BackgroundProcessCommand] =
  ## Parse a shebang line and return the interpreter command (without
  ## appending the script path — the caller is responsible for that).
  ## Handles ``/usr/bin/env <cmd> [args...]`` and ``#!<cmd> [args...]``.
  if buffer.len == 0:
    return none(BackgroundProcessCommand)

  let firstLine = buffer.getLine(0)
  if not firstLine.startsWith("#!"):
    return none(BackgroundProcessCommand)

  let rest = firstLine[2 .. ^1].strip()
  if rest.len == 0:
    return none(BackgroundProcessCommand)

  let parts = rest.splitWhitespace()
  if parts.len == 0:
    return none(BackgroundProcessCommand)

  var cmd: string
  var args: seq[string]

  if parts[0].extractFilename == "env" and parts.len >= 2:
    # "#!/usr/bin/env python3 -u" → cmd="python3", args=["-u"]
    cmd = parts[1]
    if parts.len >= 3:
      args.add parts[2 .. ^1]
  else:
    cmd = parts[0]
    if parts.len >= 2:
      args.add parts[1 .. ^1]

  return some(BackgroundProcessCommand(cmd: cmd, args: args))

proc shebangQuickRunCommand(
    path: string, shebang: BackgroundProcessCommand
): BackgroundProcessCommand =
  var args = shebang.args
  args.add path
  BackgroundProcessCommand(cmd: shebang.cmd, args: args)

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
  let options =
    if settings.clangOptions.isSome:
      settings.clangOptions.get & " "
    else:
      ""
  # quoteShell the file-derived path so a malicious file/dir name cannot inject
  # shell commands into the `/bin/bash -c` string (e.g. `evil$(...).c`).
  BackgroundProcessCommand(
    cmd: "/bin/bash",
    args: @["-c", fmt"gcc {options}{quoteShell(path)} -o ./.out && ./.out"],
  )

proc cppQuickRunCommand(
    path: string, settings: QuickRunConfig
): BackgroundProcessCommand {.inline.} =
  let options =
    if settings.cppOptions.isSome:
      settings.cppOptions.get & " "
    else:
      ""
  # quoteShell the file-derived path (see clangQuickRunCommand) to prevent
  # command injection via the source file name.
  BackgroundProcessCommand(
    cmd: "/bin/bash",
    args: @["-c", fmt"g++ {options}{quoteShell(path)} -o ./.out && ./.out"],
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

proc luaQuickRunCommand(
    path: string, settings: QuickRunConfig
): BackgroundProcessCommand =
  BackgroundProcessCommand(cmd: "lua", args: @[path])

proc goQuickRunCommand(
    path: string, settings: QuickRunConfig
): BackgroundProcessCommand =
  BackgroundProcessCommand(cmd: "go", args: @["run", path])

proc rustQuickRunCommand(
    path: string, settings: QuickRunConfig
): BackgroundProcessCommand =
  # rustc <path> -o ./outName && ./outName
  # quoteShell both the path and the derived output name so a malicious file
  # name cannot inject shell commands into the `/bin/bash -c` string.
  let
    outName = path.splitFile.name
    quotedOut = quoteShell(outName)
  BackgroundProcessCommand(
    cmd: "/bin/bash",
    args: @["-c", fmt"rustc {quoteShell(path)} -o ./{quotedOut} && ./{quotedOut}"],
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
  of SourceLanguage.langLua:
    command = luaQuickRunCommand(path, settings)
  of SourceLanguage.langGo:
    command = goQuickRunCommand(path, settings)
  else:
    let shebang = parseShebang(buffer)
    if shebang.isSome:
      command = shebangQuickRunCommand(path, shebang.get)
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

type QuickRunPrepareResult* = object
  command*: BackgroundProcessCommand
  filePath*: string
  isTempFile*: bool

proc prepareQuickRun*(
    buffer: TextBuffer, settings: EditorConfig
): Result[QuickRunPrepareResult, string] =
  ## Prepare QuickRun by saving file and creating command (sync).

  let
    useTempFile = buffer.filePath.isNone or not fileExists(buffer.filePath.get)
    langExt = buffer.language.languageExtension
    path =
      if useTempFile:
        # A temporary file name.
        if langExt.isErr:
          return Result[QuickRunPrepareResult, string].err langExt.error
        "quickruntemp." & langExt.get
      else:
        buffer.filePath.get

  if settings.quickRun.saveBufferWhenQuickRun and not useTempFile:
    try:
      let lastModificationTime = getLastModificationTime(path)
      # TODO: Compare with buffer's last save time
      discard lastModificationTime
    except OSError:
      discard

  if settings.quickRun.saveBufferWhenQuickRun or useTempFile:
    # Create and use a temporary file if the source code file does not exist.
    let saveResult = buffer.saveFile(path)
    if saveResult.isErr:
      return Result[QuickRunPrepareResult, string].err fmt"Failed to save the current code: {saveResult.error}"

  let command = quickRunCommand(path, buffer.language, buffer, settings.quickRun)
  if command.isErr:
    return
      Result[QuickRunPrepareResult, string].err fmt"QuickRun failed: {command.error}"

  return Result[QuickRunPrepareResult, string].ok QuickRunPrepareResult(
    command: command.get, filePath: path, isTempFile: useTempFile
  )

proc cleanupTempFiles(filePath: string, isTempFile: bool) =
  ## Cleanup temporary files created by QuickRun.
  if not isTempFile:
    return
  try:
    # Cleanup temporary a source code file.
    if filePath.fileExists:
      removeFile(filePath)
    # Cleanup temporary a executable.
    let baseName = filePath.splitFile.name
    if baseName.fileExists:
      removeFile(baseName)
    # Also cleanup .out files for C/C++
    if ".out".fileExists:
      removeFile(".out")
  except OSError:
    discard

proc cleanupTempFiles(p: QuickRunProcess) =
  cleanupTempFiles(p.filePath, p.isTempFile)

proc startBackgroundQuickRun*(
    prepared: QuickRunPrepareResult
): Future[Result[QuickRunProcess, string]] {.async: (raises: []).} =
  ## Start a background process for build and run commands (async).
  ## On failure, cleans up the temp source file that `prepareQuickRun`
  ## may have written, so a failed start never leaves `quickruntemp.<ext>`
  ## behind.

  let backgroundProcess = await startBackgroundProcess(prepared.command)
  if backgroundProcess.isErr:
    cleanupTempFiles(prepared.filePath, prepared.isTempFile)
    return Result[QuickRunProcess, string].err fmt"QuickRun failed: {backgroundProcess.error}"

  return Result[QuickRunProcess, string].ok QuickRunProcess(
    command: prepared.command,
    filePath: prepared.filePath,
    isTempFile: prepared.isTempFile,
    process: backgroundProcess.get,
  )

proc abandonQuickRunProcess*(p: QuickRunProcess) =
  ## Kill a running QuickRun process and remove its temporary files (temp
  ## source + build artifacts) without waiting for completion. Used on editor
  ## shutdown/crash so an in-flight QuickRun never orphans its process or
  ## leaves temp files behind. Safe to call multiple times and with a nil
  ## process; `cleanupTempFiles` swallows OS errors so it can run from
  ## shutdown paths. Mirrors `git_diff.abandonGitDiffProcess`.
  if not p.process.isNil:
    p.kill()
  p.cleanupTempFiles()

proc waitForResultAsync*(
    p: QuickRunProcess, timeout: Duration
): Future[ProcessOutputResult] {.async: (raises: []).} =
  ## Wait for the process to finish and return the output. A program still
  ## running after `timeout` (an infinite loop, or one waiting on stdin, which
  ## QuickRun never provides) is killed and reported as an error. Temporary
  ## files are removed either way.

  let output = await p.process.waitForAsync(timeout)
  p.cleanupTempFiles()

  return output
