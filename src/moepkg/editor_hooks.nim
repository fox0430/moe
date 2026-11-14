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
## newer one asking for the same work: the same event, the same command lines
## once placeholders are expanded, and the same directory to run them in. So a
## command naming no file runs once for a `:wa` of files sharing a directory,
## and files in different directories each get a run of their own.
## `BufWritePost` jobs are owed: a quit waits for them, since a caller that ran
## moe as `$EDITOR` reads the file once moe exits.
##
## `BufWritePre` is the exception: the write waits for it where the write is,
## as Vim waits for its autocommands, so the keys after a `:w` in a mapping or
## a macro run once the file is written. Its output replaces the buffer. An
## entry may run a moe Ex command (`:s`, `:stripwhitespace`) instead, as an
## edit of the buffer rather than of a window: the cursor, the last search and
## the jump list stay as they were.

import std/[options, os, sequtils, strutils]

import pkg/[chronos, results]

import
  types/editor_types,
  command_handlers/command_handler,
  command_line,
  hook_ex_command,
  background_process,
  blocking_filter,
  buffer,
  editor_notify,
  hooks,
  job_lanes,
  motion,
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
  WritePreOutputFactor = 8
    ## How much larger than its input a `BufWritePre` answer may be: a
    ## formatter answers with about its input, and a file over the filter cap
    ## must still be formattable.
  WritePreNoticeDelay* = 300.milliseconds
    ## How long a `BufWritePre` command runs before the status line says so, so
    ## a fast formatter does not flash it.

proc owedOnExit(event: HookEvent): bool =
  ## Whether a quit waits for hooks of `event`: `BufWritePost` follows a write
  ## the user made, while a read is moot once the user leaves.
  event == heBufWritePost

proc matchingEntries(
    e: Editor, event: HookEvent, path: string, language: SourceLanguage
): tuple[absPath: string, entries: seq[HookEntry]] =
  ## The entries matching `event` for `path`, and the absolute path.
  # `hooksFor` checks `enable`; this spares the path work when nothing is set.
  if path.len == 0 or e.config.hooks.entries.len == 0:
    return
  let absPath = pathKey(path)
  # Matched first: the checks below stat the file.
  let entries = e.config.hooks.hooksFor(event, absPath, language)
  if entries.len == 0:
    return
  case event
  of heBufReadPost:
    # No file for a new unsaved path (Vim uses `BufNewFile`), nor a directory.
    if not fileExists(absPath):
      return
  of heBufWritePre, heBufWritePost:
    # Rejected here too: the buffer overload's `isUtilityBuffer` check does not
    # cover a path handed in directly.
    if dirExists(absPath):
      return
  (absPath, entries)

proc toHookCommand(
    entry: HookEntry, event: HookEvent, absPath: string, language: SourceLanguage
): Option[HookCommand] =
  ## A program entry resolved against `absPath`, ready to exec.
  let command = entry.toCommand(absPath, language)
  if command.cmd.len == 0:
    # Rejected by the loader; only code-built entries reach here.
    return none(HookCommand)
  some HookCommand(
    event: event,
    path: absPath,
    command: entry.command,
    cmd: command.cmd,
    args: command.args,
    workingDir: command.workingDir,
    timeout: entry.timeout,
    showOutput: entry.showOutput,
    onFail: entry.onFail,
  )

proc hookCommands(
    e: Editor, event: HookEvent, path: string, language: SourceLanguage
): seq[HookCommand] =
  ## Every program entry matching `event` for `path`, resolved and ready to
  ## exec. An Ex command runs only where a write waits; see `writePreSteps`.
  let (absPath, entries) = e.matchingEntries(event, path, language)
  for entry in entries:
    if not entry.isExHook:
      let command = entry.toHookCommand(event, absPath, language)
      if command.isSome:
        result.add command.get

type WritePreStep = object ## One `BufWritePre` entry for one write, in config order.
  case ex: bool
  of false:
    program: HookCommand
  of true:
    line: string ## As written, to label it.
    parsed: Result[HookExCommand, string]
      ## The loader refused what does not read; an entry built in code may not.

proc writePreSteps(
    e: Editor, path: string, language: SourceLanguage
): seq[WritePreStep] =
  ## Every `BufWritePre` entry matching `path`, programs and Ex commands.
  let (absPath, entries) = e.matchingEntries(heBufWritePre, path, language)
  for entry in entries:
    if entry.isExHook:
      result.add WritePreStep(
        ex: true, line: entry.exCommand, parsed: parseHookExCommand(entry.exCommand)
      )
    else:
      let command = entry.toHookCommand(heBufWritePre, absPath, language)
      if command.isSome:
        result.add WritePreStep(ex: false, program: command.get)

proc hookLabel(hook: HookCommand): string =
  $hook.event & " hook (" & hook.cmd & ")"

proc exHookLabel(line: string): string =
  ## A `BufWritePre` Ex command, as written.
  $heBufWritePre & " hook (:" & line.exCommandText & ")"

proc label(step: WritePreStep): string =
  if step.ex: step.line.exHookLabel else: step.program.hookLabel

proc jobLabel(hooks: seq[HookCommand]): string =
  ## One job's hooks for `:jobs`: their event and programs.
  var programs: seq[string]
  for hook in hooks:
    programs.add hook.cmd
  $hooks[0].event & (if hooks.len > 1: " hooks (" else: " hook (") & programs.join(", ") &
    ")"

proc workKey(event: HookEvent, hooks: seq[HookCommand]): string =
  ## Equal for two firings asking for the same work, whichever file fired
  ## them: the event, the command lines once placeholders are expanded, and the
  ## directory they run in. The event is part of it, so a read never takes an
  ## owed write's place.
  $event & $hooks.mapIt((it.cmd, it.args, it.workingDir, it.timeout, it.showOutput))

proc exitMessage(
    label: string, exitCode: int, output: seq[string], fromEnd = true
): string =
  ## Message for a non-zero exit, with the last non-empty output line, or the
  ## first when not `fromEnd`.
  result = label & " exited with " & $exitCode
  for n in 0 .. output.high:
    let i =
      if fromEnd:
        output.high - n
      else:
        n
    if output[i].strip.len > 0 and output[i] != OutputDroppedMarker:
      let line =
        if output[i].len > ExitMessageQuoteLimit:
          output[i][0 ..< ExitMessageQuoteLimit] & "..."
        else:
          output[i]
      # The cut above may split an escape sequence or a rune.
      result &= ": " & line.forDisplay.strip
      break

proc firstNonBlankLine(text: string): seq[string] =
  ## The first line of `text` with more than blanks, without splitting the rest.
  for line in text.splitLines:
    if line.strip.len > 0:
      return @[line]

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

  let label = jobLabel(hooks)
  let submission = e.jobLanes.submit(
    HookLane,
    LaneJob(
      label: label,
      path: hooks[0].path,
      collapse: workKey(event, hooks),
      owed: event.owedOnExit,
      run: run,
    ),
  )
  # Refused once the editor winds down. A read is owed nothing by then, but a
  # write is: record it, so a caller that ran moe as `$EDITOR` learns the file
  # its hook never saw instead of reading it unaware.
  if submission == smRefused and event.owedOnExit:
    e.state.exitReports.add(("Not run: " & label & " on " & hooks[0].path).forDisplay)

proc queueHooks*(e: Editor, event: HookEvent, buf: TextBuffer) =
  ## Queue hooks for a buffer's own file; skip pathless and utility buffers.
  if buf.isNil:
    return
  if buf.isUtilityBuffer:
    return
  if buf.filePath.isSome:
    e.queueHooks(event, buf.filePath.get, buf.language)

type WritePreResult* = object ## What the `BufWritePre` hooks left a write.
  warnings*: seq[string]
    ## Failures the write goes past: a program's with `onFail = "write"`, and
    ## any Ex command's.
  refusal*: string ## Why the file is not to be written; empty to write it.
  interrupted*: bool ## Ctrl-C or a deadly signal stopped a command: write nothing more.

proc holdsNoText(buf: TextBuffer): bool =
  ## Whether every line of `buf` is blank: emptying it loses nothing, and a
  ## formatter answers such text with nothing.
  for line in buf.lines:
    if not line.isEmptyOrWhitespace:
      return false
  true

proc keepCursorOnText(
    e: Editor, window: EditorWindow, buf: TextBuffer, wanted: WantedColumn
) =
  ## Keep the cursor of `window` on a character of `buf` after an edit that is
  ## not the user's.
  if window.buffer == buf:
    let clamped = e.motionController.cursorManager.clampPosition(
      CursorPosition(x: window.cursor.column, y: window.cursor.line),
      buf,
      some(window.mode),
    )
    window.cursor = BufferPosition(line: clamped.y, column: clamped.x)
    # Kept anew: the edit is not the write command's, so the column vertical
    # moves want outlasts it.
    window.wanted = wanted

template editOutside(e: Editor, buf: TextBuffer, body: untyped) =
  ## Run `body`, an edit of `buf` that is not the user's. Every window on the
  ## buffer, the current one too, follows its text, as Neovim moves them across
  ## an API edit. A `body` that returns early, having failed, leaves the
  ## cursor alone.
  let window = e.activeWindow
  let wanted = window.wanted
  e.asOutsideEdit:
    body
  e.keepCursorOnText(window, buf, wanted)

proc takeWritePreOutput(
    e: Editor, buf: TextBuffer, label, output: string
): Result[void, string] =
  ## Put a command's answer in the buffer as one undoable change, touching only
  ## the lines that differ, so marks and folds on the rest stay.
  let lines = ?buf.decodeTransformedContent(output)
  e.editOutside(buf):
    let replaced = buf.replaceAllLines(lines, description = label)
    if replaced.isErr:
      return err(replaced.error)
  ok()

proc runWritePreExCommand(
    e: Editor, buf: TextBuffer, line: string, ex: Result[HookExCommand, string]
): Result[void, string] =
  ## Run a `BufWritePre` entry's Ex command on `buf` as one undoable change.
  let ex = ex.valueOr:
    return err(line.exHookLabel & ": expected " & error)
  e.editOutside(buf):
    let ran =
      case ex.kind
      of hekStripWhitespace:
        # How many lines it changed says nothing to a hook.
        buf.stripTrailingWhitespace().map(
          proc(_: int) =
            discard
        )
      of hekSubstitute:
        # The case goes by 'ignorecase' and 'smartcase', as for a typed :s.
        let flags = e.commandLineParser.substituteFlags(ex.pattern, ex.flags, smRegex)
        buf.substituteInBuffer(ex.pattern, ex.replacement, flags, ex.range)
    if ran.isErr:
      return err(line.exHookLabel & " failed: " & ran.error)
  ok()

proc writePreTurn(
    e: Editor, label: string, interrupted: ref bool, shown: ref string
): proc(): bool {.gcsafe, raises: [].} =
  ## The frontend's turn while a `BufWritePre` command runs: Ctrl-C stops it,
  ## and one that runs long says so on the status line. `shown` is the
  ## command the status line names, if any.
  let startedAt = Moment.now()
  result = proc(): bool {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      let wait = e.blockingWait
      if shown[] != label and not wait.render.isNil and
          Moment.now() - startedAt >= WritePreNoticeDelay:
        e.state.ui.waitNotice = label & " is running (Ctrl-C to stop)"
        if wait.render():
          shown[] = label
      if not wait.interrupted.isNil and wait.interrupted():
        interrupted[] = true
      interrupted[]

proc runWritePreHook(
    e: Editor,
    buf: TextBuffer,
    hook: HookCommand,
    interrupted: ref bool,
    shown: ref string,
): Result[void, string] =
  ## Run one `BufWritePre` command on `buf`; the error says why its answer was
  ## not taken.
  var input = buf.getFilterInput
  let
    label = hook.hookLabel
    blank = buf.holdsNoText
    maxOutput = e.config.filter.maxOutputSize
    limit =
      if maxOutput <= 0:
        0 # No limit.
      else:
        max(maxOutput, input.len * WritePreOutputFactor)
    filtered = runFilterBlocking(
      BackgroundProcessCommand(
        cmd: hook.cmd, args: hook.args, workingDir: hook.workingDir
      ),
      move input,
      timeoutFromSeconds(hook.timeout),
      limit,
      e.writePreTurn(label, interrupted, shown),
    )
  if filtered.isErr:
    if filtered.error.kind == ffCancelled:
      # Stopped by Ctrl-C, or by a deadly signal the loop is about to answer.
      interrupted[] = true
    return err(label & " failed: " & filtered.error.message)
  if interrupted[]:
    # Ctrl-C came as the command ended: the write is off, so its answer is too.
    return err(label & " interrupted")
  let status = filtered.get.exitCode
  if status.isNone:
    return err(label & " ran but its exit status is unknown")
  if status.get != 0:
    # The first line of stderr says what went wrong; the rest is context. A
    # tool that reports on stdout leaves stderr empty.
    var said = filtered.get.diagnostics
    if not said.anyIt(it.strip.len > 0):
      said = filtered.get.output.firstNonBlankLine
    return err(exitMessage(label, status.get, said, fromEnd = false))
  let output = filtered.get.output
  if output.len == 0 and not blank:
    # A command that answers on a file, or ignored its input: not an emptied file.
    return err(label & " wrote nothing back")
  let taken = e.takeWritePreOutput(buf, label, output)
  if taken.isErr:
    return err(label & " failed: " & taken.error)
  ok()

proc runWritePreHooks*(
    e: Editor, buf: TextBuffer, path: string, language: SourceLanguage
): WritePreResult =
  ## Run the `BufWritePre` hooks matching `buf` written to `path`, in config
  ## order, and wait for them here, as Vim waits for its autocommands. Each
  ## output replaces the buffer. The first failure of a program ends the
  ## chain: the commands after it were to describe text it never changed.
  let steps = e.writePreSteps(path, language)
  if steps.len == 0:
    return
  if buf.inTransaction:
    # An open change (`<C-o>:w` in Insert) takes no other change. It ends when
    # Insert does, so a program whose failure stops the write stops it here.
    let why = "BufWritePre hooks not run: a change is in progress"
    if steps.anyIt(not it.ex and it.program.onFail == hfaAbort):
      result.refusal = (why & "; not written").forDisplay
    else:
      result.warnings.add why.forDisplay
    return
  if buf.readOnly or not buf.allowsTextTransforms:
    # The user's text goes to disk as it is: refusing it would leave the file
    # unsavable.
    let why =
      if buf.readOnly:
        "the buffer is read-only"
      else:
        rawBytesRejection("transform")
    result.warnings.add ("BufWritePre hooks not run: " & why).forDisplay
    return

  let
    interrupted = new bool
    shown = new string
    wasWaiting = e.waitingInPlace
    # An Ex command waits on no process.
    waits = steps.anyIt(not it.ex)
  if waits:
    e.waitingInPlace = true
  defer:
    if waits:
      e.waitingInPlace = wasWaiting
      e.state.ui.waitNotice = ""
      if not e.blockingWait.finish.isNil:
        e.blockingWait.finish()
  for step in steps:
    let ran =
      try:
        if step.ex:
          e.runWritePreExCommand(buf, step.line, step.parsed)
        else:
          e.runWritePreHook(buf, step.program, interrupted, shown)
      except TransactionRollbackError as exc:
        # The buffer is in a state nothing vouches for: it is not to be written.
        result.refusal =
          (step.label & " failed: " & exc.msg & "; not written").forDisplay
        return
    if step.ex:
      # Over in an instant, and a failure leaves the text as it was, as finding
      # nothing does: the write and the entries after it go on, as in Vim.
      if ran.isErr:
        result.warnings.add ran.error.forDisplay
      continue
    let hook = step.program
    if interrupted[]:
      # As Vim's got_int: the rest of the mapping or register that wrote goes too.
      e.state.beep()
      result.interrupted = true
      result.refusal = ("Interrupted: " & hook.hookLabel & "; not written").forDisplay
      return
    if ran.isErr:
      if hook.onFail == hfaAbort:
        result.refusal = (ran.error & "; not written").forDisplay
      else:
        result.warnings.add ran.error.forDisplay
      return

type ReadOrigin* = enum
  ## Why a buffer was read from disk. `noteBufferRead` is the one place this
  ## is turned into a `BufReadPost`, so a read path names the situation rather
  ## than deciding for itself.
  roUser ## The user asked for the file: an open, a split, `:e!`, a restored backup.
  roInternal
    ## The editor read it on its own account, not a keystroke's asking: an LSP
    ## rename's background copy, a reload made without the user asking.
  roExternal
    ## A change on disk was picked up and reloaded. A read hook that rewrites
    ## its file would retrigger itself, so this is not a read.

proc noteBufferRead*(e: Editor, buf: TextBuffer, origin: ReadOrigin) =
  ## The one way a read announces itself, whatever path performed it.
  if origin == roUser:
    e.queueHooks(heBufReadPost, buf)
