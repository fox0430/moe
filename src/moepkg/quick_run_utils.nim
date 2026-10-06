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

import std/[monotimes, os, strformat, options, strutils]

when defined(posix):
  from std/posix import mkdtemp
else:
  import std/tempfiles

import pkg/[results, chronos]

import syntax/tokenizer
import config, buffer/[core, file_io], background_process

export SourceLanguage

type QuickRunProcess* = object
  command*: BackgroundProcessCommand
  filePath*: string
  workDir*: string
    ## Private dir holding everything this run wrote (temp source, built
    ## program); removed whole when the run ends. Empty when nothing was written.
  process*: BackgroundProcess
  startedAt*: MonoTime
    ## So a run holding a file can be listed, and timed, beside the others.

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
    # sh is handled by the caller (isSh), so a temp file for a sh script
    # never gets a bash extension. TODO: Add support for other shells.
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

proc isSh(buffer: TextBuffer): bool {.inline.} =
  ## Return true if the buffer's first line is an sh shebang, with or
  ## without interpreter arguments (``#!/bin/sh``, ``#!/bin/sh -e``,
  ## ``#!/usr/bin/env sh``, ...).
  let shebang = parseShebang(buffer)
  return shebang.isSome and shebang.get.cmd.extractFilename == "sh"

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
    path, program: string, settings: QuickRunConfig
): BackgroundProcessCommand {.inline.} =
  let options =
    if settings.clangOptions.isSome:
      settings.clangOptions.get & " "
    else:
      ""
  # quoteShell the file-derived paths so a malicious file/dir name cannot inject
  # shell commands into the `/bin/bash -c` string (e.g. `evil$(...).c`).
  let exe = quoteShell(program)
  BackgroundProcessCommand(
    cmd: "/bin/bash",
    args: @["-c", fmt"gcc {options}{quoteShell(path)} -o {exe} && {exe}"],
  )

proc cppQuickRunCommand(
    path, program: string, settings: QuickRunConfig
): BackgroundProcessCommand {.inline.} =
  let options =
    if settings.cppOptions.isSome:
      settings.cppOptions.get & " "
    else:
      ""
  # quoteShell the file-derived paths (see clangQuickRunCommand) to prevent
  # command injection via the source file name.
  let exe = quoteShell(program)
  BackgroundProcessCommand(
    cmd: "/bin/bash",
    args: @["-c", fmt"g++ {options}{quoteShell(path)} -o {exe} && {exe}"],
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
    path, program: string, settings: QuickRunConfig
): BackgroundProcessCommand =
  # quoteShell both paths so a malicious file name cannot inject shell
  # commands into the `/bin/bash -c` string.
  let exe = quoteShell(program)
  BackgroundProcessCommand(
    cmd: "/bin/bash", args: @["-c", fmt"rustc {quoteShell(path)} -o {exe} && {exe}"]
  )

proc buildsProgram(lang: SourceLanguage): bool =
  ## Whether QuickRun names the built program itself, so it needs a work dir to
  ## put it in. Nim leaves its program next to the source.
  lang in {SourceLanguage.langC, SourceLanguage.langCpp, SourceLanguage.langRust}

proc programPath(workDir, path: string): string =
  workDir / path.splitFile.name

proc quickRunCommand(
    path: string,
    lang: SourceLanguage,
    buffer: TextBuffer,
    settings: QuickRunConfig,
    workDir: string,
): Result[BackgroundProcessCommand, string] =
  var command: BackgroundProcessCommand
  case lang
  of SourceLanguage.langNim:
    command = nimQuickRunCommand(path, settings)
  of SourceLanguage.langC:
    command = clangQuickRunCommand(path, programPath(workDir, path), settings)
  of SourceLanguage.langCpp:
    command = cppQuickRunCommand(path, programPath(workDir, path), settings)
  of SourceLanguage.langShell:
    if buffer.isSh:
      command = shQuickRunCommand(path, settings)
    else:
      command = bashQuickRunCommand(path, settings)
  of SourceLanguage.langPython:
    command = pythonQuickRunCommand(path, settings)
  of SourceLanguage.langRust:
    command = rustQuickRunCommand(path, programPath(workDir, path), settings)
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

proc cancel*(p: QuickRunProcess) {.inline.} =
  p.process.cancel

proc kill*(p: QuickRunProcess) {.inline.} =
  p.process.kill

type QuickRunPrepareResult* = object
  command*: BackgroundProcessCommand
  filePath*: string
  workDir*: string ## See `QuickRunProcess.workDir`.
  didSave*: bool
    ## True when staging saved the buffer to its real file.
    ## The caller must then run `noteBufferSaved`.

proc createWorkDir(): Result[string, string] =
  ## A fresh dir only the user can enter, so nothing planted can redirect what
  ## a run writes. Under the user's cache, not the shared temp dir: compilers
  ## read config from every parent of a source (nim runs any `config.nims` up
  ## the tree), and anyone can put one in /tmp.
  var cache = getCacheDir()
  if cache.len == 0:
    # `getCacheDir` returns "" for a set-but-empty XDG_CACHE_HOME, which the
    # XDG spec treats as unset and expects to fall back to `$HOME/.cache`.
    let home = getHomeDir()
    if home.len > 0:
      cache = home / ".cache"
  if not cache.isAbsolute:
    return
      Result[string, string].err "no absolute cache directory (HOME or XDG_CACHE_HOME)"
  let base = cache / "moe" / "quickrun"
  try:
    createDir(base)
  except IOError, OSError:
    return Result[string, string].err getCurrentExceptionMsg()

  when defined(posix):
    var path = base / "run-XXXXXX"
    if mkdtemp(path.cstring).isNil:
      return Result[string, string].err osErrorMsg(osLastError())
    return Result[string, string].ok path
  else:
    try:
      return Result[string, string].ok createTempDir("run-", "", base)
    except OSError as e:
      return Result[string, string].err e.msg

proc removeQuickRunWorkDir*(workDir: string) =
  ## Remove a run's work dir with everything in it. Swallows OS errors so it
  ## can run from shutdown paths.
  if workDir.len == 0:
    return
  try:
    removeDir(workDir)
  except OSError:
    discard

proc prepareQuickRun*(
    buffer: TextBuffer, settings: EditorConfig
): Result[QuickRunPrepareResult, string] =
  ## Assemble the run command and stage its input.
  ## The buffer's file is written only once the command is built, and a
  ## failure removes the work dir, so failure leaves nothing behind.
  ## Staging writes bytes directly without trim or mode handling.

  when defined(moe.embedded) and defined(windows):
    discard buffer
    discard settings
    return Result[QuickRunPrepareResult, string].err(
      "QuickRun is unavailable in embedded mode on Windows"
    )

  let
    useTempFile = buffer.filePath.isNone or not fileExists(buffer.filePath.get)
    langExt =
      if buffer.language == SourceLanguage.langShell and buffer.isSh:
        Result[string, string].ok "sh"
      else:
        buffer.language.languageExtension
  if useTempFile and langExt.isErr:
    return Result[QuickRunPrepareResult, string].err langExt.error

  var workDir = ""
  if useTempFile or buffer.language.buildsProgram:
    let created = createWorkDir()
    if created.isErr:
      return Result[QuickRunPrepareResult, string].err fmt"Failed to create a directory for QuickRun: {created.error}"
    workDir = created.get

  var staged = false
  defer:
    if not staged:
      removeQuickRunWorkDir(workDir)

  let path =
    if useTempFile:
      workDir / ("quickruntemp." & langExt.get)
    else:
      buffer.filePath.get

  let command =
    quickRunCommand(path, buffer.language, buffer, settings.quickRun, workDir)
  if command.isErr:
    return
      Result[QuickRunPrepareResult, string].err fmt"QuickRun failed: {command.error}"

  var didSave = false
  if useTempFile:
    # Temp copy only — saveFile would bind the buffer to this path.
    try:
      writeFile(path, buffer.getFileContent)
    except IOError, OSError:
      return Result[QuickRunPrepareResult, string].err fmt"Failed to write the temporary file: {getCurrentExceptionMsg()}"
  elif settings.quickRun.saveBufferWhenQuickRun:
    # Real save; checkExternalMod refuses overwrite if the file changed externally.
    let saveResult = buffer.saveFile(path, checkExternalMod = true)
    if saveResult.isErr:
      return Result[QuickRunPrepareResult, string].err fmt"Failed to save the current code: {saveResult.error}"
    didSave = true

  staged = true
  return Result[QuickRunPrepareResult, string].ok QuickRunPrepareResult(
    command: command.get, filePath: path, workDir: workDir, didSave: didSave
  )

proc startBackgroundQuickRun*(
    prepared: QuickRunPrepareResult
): Result[QuickRunProcess, string] =
  ## Start a background process for build and run commands.
  ## On failure, removes the work dir `prepareQuickRun` may have made.

  let backgroundProcess = startBackgroundProcess(prepared.command)
  if backgroundProcess.isErr:
    removeQuickRunWorkDir(prepared.workDir)
    return Result[QuickRunProcess, string].err fmt"QuickRun failed: {backgroundProcess.error}"

  return Result[QuickRunProcess, string].ok QuickRunProcess(
    command: prepared.command,
    filePath: prepared.filePath,
    workDir: prepared.workDir,
    process: backgroundProcess.get,
    startedAt: getMonoTime(),
  )

proc abandonQuickRunProcess*(p: QuickRunProcess) =
  ## Kill a running QuickRun process and remove its work dir without waiting
  ## for completion. Used on editor shutdown/crash so an in-flight QuickRun
  ## never orphans its process or leaves files behind. Safe to call multiple
  ## times and with a nil process. Mirrors `git_diff.abandonGitDiffProcess`.
  if not p.process.isNil:
    p.kill()
  removeQuickRunWorkDir(p.workDir)

proc waitForResultAsync*(
    p: QuickRunProcess, timeout: Duration
): Future[ProcessOutputResult] {.async: (raises: []).} =
  ## Wait for the process to finish and return the output. A program still
  ## running after `timeout` (an infinite loop, or one waiting on stdin, which
  ## QuickRun never provides) is killed and reported as an error. The work dir
  ## is removed either way.

  let output = await p.process.waitForAsync(timeout)
  removeQuickRunWorkDir(p.workDir)

  return output
