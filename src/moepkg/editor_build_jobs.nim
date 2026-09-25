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

## Builds and syntax checks, run in `jobLanes`.
##
## All builds share one lane: what a command writes is unknown, and two writing
## one output break each other's link. A check only reads and only the newest
## save's markers matter, so a newer check of a file replaces the running one.

import std/[sequtils, strutils]

import pkg/[results, chronos]

import
  editor, editor_notify, editor_command_output, build, syntax_checker, job_lanes,
  path_key, types
import syntax/tokenizer

const BuildLane = "build"

proc buildCollapse(info: BuildInfo, command: BackgroundProcessCommand): string =
  ## One command in one directory is the same build, whichever file asked.
  ## `:build` is kept apart from saves since it moves the focus.
  (if info.automatic: "save" else: "explicit") & "\0" & pathKey(command.workingDir) &
    "\0" & command.cmd & "\0" & command.args.join("\0")

proc announcesBuild(editor: Editor, info: BuildInfo): bool =
  ## `:build` always announces itself; a build on save only if configured to.
  not info.automatic or (
    editor.config.notification.screenNotifications and
    editor.config.notification.buildOnSaveScreenNotify
  )

proc runSyntaxCheckJob(
    editor: Editor, info: SyntaxCheckInfo, stop: JobStop
): Future[void] {.async: (raises: []).} =
  ## Check the file and apply the result to its buffer.
  {.cast(gcsafe).}:
    try:
      let checkProcess = startBackgroundSyntaxCheck(
        info.path, SourceLanguage(info.language)
      ).valueOr:
        editor.notify("Syntax check error: " & error, nlError)
        return
      let outputResult = await checkProcess.waitForAsync(
        timeoutFromSeconds(editor.config.syntaxChecker.timeout), stop
      )
      # Superseded by a newer check or stopped by `:jobs!`.
      if stop.requested:
        return
      if outputResult.isErr:
        editor.notify("Syntax check error: " & outputResult.error, nlError)
        return
      let errors = parseNimCheckResult(info.path, outputResult.get)
      let bufIdx = editor.findBufferByPath(info.path)
      if bufIdx >= 0:
        applySyntaxCheckToBuffer(editor.buffers[bufIdx], errors)
      # Kept for the status line.
      editor.state.syntaxCheckResults = (path: info.path, errors: errors)
      let errorCount = errors.countIt(it.messageType == SyntaxCheckMessageType.error)
      let warnCount = errors.countIt(it.messageType == SyntaxCheckMessageType.warning)
      if errorCount > 0 or warnCount > 0:
        editor.state.statusMessage =
          "Syntax check: " & $errorCount & " error(s), " & $warnCount & " warning(s)"
      else:
        editor.state.statusMessage = "Syntax check: OK"
    except Exception as ex:
      editor.notify("Syntax check error: " & ex.msg, nlError)

proc runBuildJob(
    editor: Editor, info: BuildInfo, command: BackgroundProcessCommand, stop: JobStop
): Future[void] {.async: (raises: []).} =
  ## Run the build and show its output.
  {.cast(gcsafe).}:
    try:
      # Set before starting so a start failure overwrites it.
      if editor.announcesBuild(info):
        editor.state.statusMessage = "Building: " & info.path
      let buildProcess = startBackgroundBuild(command, info.path).valueOr:
        editor.notify("Build error: " & error, nlError)
        return
      let outputResult = await buildProcess.waitForAsync(
        timeoutFromSeconds(editor.config.buildOnSave.timeout), stop
      )
      # Stopped by `:jobs!` or on quit: nothing to show or report.
      if stop.requested:
        return
      if outputResult.isErr:
        editor.notify("Build error: " & outputResult.error, nlError)
        return
      let shown = editor.showCommandOutput(outputResult.get, keepFocus = info.automatic)
      # Only if shown: otherwise this would hide why the window failed to open.
      if shown and editor.config.notification.screenNotifications and
          editor.config.notification.buildOnSaveScreenNotify:
        editor.notify("Build completed: " & info.path)
    except Exception as ex:
      editor.notify("Build error: " & ex.msg, nlError)

proc submitBuild*(editor: Editor, info: BuildInfo) =
  ## Queue the build behind any running one.
  let command = buildOnSaveCommand(
    info.path, SourceLanguage(info.language), info.customCmd, info.workspaceRoot
  ).valueOr:
    editor.notify("Build error: " & error, nlError)
    return

  proc run(stop: JobStop) {.async: (raises: []).} =
    await runBuildJob(editor, info, command, stop)

  let submitted = editor.jobLanes.submit(
    BuildLane,
    LaneJob(
      label: "Build", path: info.path, collapse: buildCollapse(info, command), run: run
    ),
  )
  # A build that starts next announces itself in `runBuildJob`.
  if submitted in {smQueued, smMerged} and editor.announcesBuild(info):
    editor.state.statusMessage = "Build queued: " & info.path

proc submitSyntaxCheck*(editor: Editor, info: SyntaxCheckInfo) =
  ## Check the file, replacing a running check of it whose markers would be
  ## stale.
  proc run(stop: JobStop) {.async: (raises: []).} =
    await runSyntaxCheckJob(editor, info, stop)

  # Refused only at shutdown, where a lost check does not matter.
  discard editor.jobLanes.submit(
    "syntax check\0" & pathKey(info.path),
    LaneJob(label: "Syntax check", path: info.path, run: run),
    adRestart,
  )
