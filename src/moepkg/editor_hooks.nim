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

## Running user hooks when an editor event happens.
##
## Every hook runs in one lane of `jobLanes`, one at a time: what a command
## touches besides its file (a build directory, git's index) cannot be known,
## so no two may overlap. The hooks one event matches run as one job, in
## config order. A job still waiting to start is replaced, in its place, by a
## newer one asking for the same work, whichever file asked: a command naming
## no file runs once for a `:wa` of many. `BufWritePost` jobs are owed: a quit
## waits for them, since a caller that ran moe as `$EDITOR` reads the file once
## moe exits.

import std/[options, os, sequtils, strutils]

import pkg/[chronos, results]

import
  types/editor_types,
  background_process,
  buffer,
  editor_notify,
  hooks,
  job_lanes,
  path_key,
  unicode_utils
import syntax/tokenizer

type HookOutputPresenter* = proc(e: Editor, output: seq[string]) {.closure.}

var hookOutputPresenter*: HookOutputPresenter = nil
  ## Shows the output of a `showOutput` hook, keeping the user's focus. Set by
  ## `editor_command_output`, which opens windows and so sits above the modules
  ## firing hooks.

const
  HookLane = "hook"
  HookOutputLimit = 1024 * 1024
    ## Bytes of a hook's output kept, from the end: its last line is the one a
    ## failure quotes.
  ExitMessageQuoteLimit = 200
    ## Bytes of the last output line a failure quotes: a minified JSON error is
    ## one line too.

proc owedOnExit(event: HookEvent): bool =
  ## Whether a quit waits for hooks of `event`: `BufWritePost` follows a write
  ## the user made, while a read is moot once the user leaves.
  event == heBufWritePost

proc hookCommands(
    e: Editor, event: HookEvent, path: string, language: SourceLanguage
): seq[HookCommand] =
  ## Every entry matching `event` for `path`, resolved and ready to exec.
  # `hooksFor` checks `enable`; this spares the path work when nothing is set.
  if path.len == 0 or e.config.hooks.entries.len == 0:
    return @[]

  let absPath = pathKey(path)
  # Matched first: the checks below stat the file.
  let entries = e.config.hooks.hooksFor(event, absPath, language)
  if entries.len == 0:
    return @[]
  case event
  of heBufReadPost:
    # No file for a new unsaved path (Vim uses `BufNewFile`), nor a directory.
    if not fileExists(absPath):
      return @[]
  of heBufWritePost:
    # Rejected here too: the buffer overload's `isUtilityBuffer` check does not
    # cover a path handed in directly.
    if dirExists(absPath):
      return @[]

  for entry in entries:
    let command = entry.toCommand(absPath, language)
    if command.cmd.len == 0:
      # Rejected by the loader; only code-built entries reach here.
      continue
    result.add HookCommand(
      event: event,
      path: absPath,
      command: entry.command,
      cmd: command.cmd,
      args: command.args,
      workingDir: command.workingDir,
      timeout: entry.timeout,
      showOutput: entry.showOutput,
    )

proc hookLabel(hook: HookCommand): string =
  $hook.event & " hook (" & hook.cmd & ")"

proc jobLabel(hooks: seq[HookCommand]): string =
  ## One job's hooks for `:jobs`: their event and programs.
  var programs: seq[string]
  for hook in hooks:
    programs.add hook.cmd
  $hooks[0].event & (if hooks.len > 1: " hooks (" else: " hook (") & programs.join(", ") &
    ")"

proc workKey(event: HookEvent, hooks: seq[HookCommand]): string =
  ## Equal for two firings asking for the same work, whichever file fired
  ## them. The event is part of it, so a read never takes an owed write's place.
  $event & $hooks.mapIt((it.cmd, it.args, it.workingDir, it.timeout, it.showOutput))

proc exitMessage(label: string, exitCode: int, output: seq[string]): string =
  ## Message for a non-zero exit, with the last non-empty output line.
  result = label & " exited with " & $exitCode
  for i in countdown(output.high, 0):
    if output[i].strip.len > 0 and output[i] != OutputDroppedMarker:
      let line =
        if output[i].len > ExitMessageQuoteLimit:
          output[i][0 ..< ExitMessageQuoteLimit] & "..."
        else:
          output[i]
      # The cut above may split an escape sequence or a rune.
      result &= ": " & line.forDisplay.strip
      break

proc reportHookFailure(e: Editor, msg: string) =
  ## Once the user quit, report on stderr: a status message would go unread.
  if e.state.quitDecided:
    e.state.exitReports.add msg.forDisplay
  else:
    e.notify(msg.forDisplay, nlError)

type JobOutput = ref object
  ## What the `showOutput` hooks of one job printed so far. They share the one
  ## output window, so each adds to it rather than replacing the one before.
  lines: seq[string]
  headed: bool ## More than one hook shows, so each part names its command.

proc showHookOutput(
    e: Editor, hook: HookCommand, output: seq[string], shown: JobOutput
) =
  ## `showOutput`, in a split below what the job's earlier hooks showed; once
  ## the user quit, the split goes with the screen, so on stderr instead.
  if e.state.quitDecided:
    var report = (hook.hookLabel & " output for " & hook.path & ":").forDisplay
    for line in output:
      report.add "\n" & line.forDisplay
    e.state.exitReports.add report
  elif not hookOutputPresenter.isNil:
    if shown.headed:
      # Headed the way `tail` heads each file it prints.
      if shown.lines.len > 0:
        shown.lines.add ""
      shown.lines.add "==> " & hook.command & " <=="
    shown.lines.add output
    hookOutputPresenter(e, shown.lines)

proc runHook(
    e: Editor, hook: HookCommand, stop: JobStop, shown: JobOutput
): Future[void] {.async: (raises: []).} =
  ## Run one hook. Success stays silent unless `showOutput`; failure always
  ## reports, but a hook that was stopped did not fail.
  {.cast(gcsafe).}:
    try:
      let label = hook.hookLabel
      let process = startBackgroundProcess(
        BackgroundProcessCommand(
          cmd: hook.cmd, args: hook.args, workingDir: hook.workingDir
        )
      ).valueOr:
        e.reportHookFailure(label & " failed: " & error)
        return
      let outputResult = await process.waitForAsync(
        timeoutFromSeconds(hook.timeout), stop, outputLimit = HookOutputLimit
      )
      if stop.requested:
        return
      if outputResult.isErr:
        e.reportHookFailure(label & " failed: " & outputResult.error)
        return

      let output = outputResult.get
      # Shown before judging the exit: linters exit non-zero with findings.
      if hook.showOutput and output.len > 0:
        e.showHookOutput(hook, output, shown)

      let status = process.exitCode
      if status.isNone:
        e.reportHookFailure(label & " ran but its exit status is unknown")
      elif status.get != 0:
        e.reportHookFailure(exitMessage(label, status.get, output))
    except Exception as ex:
      e.reportHookFailure($hook.event & " hook error: " & ex.msg)

proc queueHooks*(e: Editor, event: HookEvent, path: string, language: SourceLanguage) =
  ## Run the hooks `event` matches for `path` once the hooks ahead are done.
  let hooks = e.hookCommands(event, path, language)
  if hooks.len == 0:
    return

  proc run(stop: JobStop) {.async: (raises: []).} =
    let shown = JobOutput(headed: hooks.countIt(it.showOutput) > 1)
    for hook in hooks:
      if stop.requested:
        return
      await e.runHook(hook, stop, shown)

  # Refused only once the editor winds down, when a new event is owed nothing.
  discard e.jobLanes.submit(
    HookLane,
    LaneJob(
      label: jobLabel(hooks),
      path: hooks[0].path,
      collapse: workKey(event, hooks),
      owed: event.owedOnExit,
      run: run,
    ),
  )

proc queueHooks*(e: Editor, event: HookEvent, buf: TextBuffer) =
  ## Queue hooks for a buffer's own file; skip pathless and utility buffers.
  if buf.isNil:
    return
  if buf.isUtilityBuffer:
    return
  if buf.filePath.isSome:
    e.queueHooks(event, buf.filePath.get, buf.language)
