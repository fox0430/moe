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

## Editor helpers shared by the Command mode handler and result processor
## without a circular import.

import std/[options, os, times, strutils]

when not defined(moe.embedded):
  import std/tables

import pkg/results

import
  ../[
    editor, editor_window_state, modes, buffer, logger, types, filer, filetree,
    config_loader, window_manager, log_viewer, syntax_checker, motion, viewer_mode,
    editor_build_jobs, path_key, cursor_util,
  ]

when not defined(moe.embedded):
  import ../[editor_window_layout, editor_window_tab, terminal_mode]

import config_ops, handler_result

proc trySaveLogViewerBuffer*(e: Editor): Option[Result[string, string]] =
  ## Save the log viewer's content to a timestamped file in the current
  ## directory: the path written, or why nothing was. None outside LogViewer.
  let activeWin = e.activeWindow
  if e.state.mode != EditorMode.LogViewer or activeWin.modeState.kind != mskLogViewer:
    return none(Result[string, string])
  let
    kind = activeWin.modeState.logViewer.contentKind
    path = getCurrentDir() / logViewerSaveFileName(kind, now())
    writeRes = saveLogViewerContentToFile(activeWin.buffer.getTextString(), path)
  if writeRes.isOk:
    return some(Result[string, string].ok(path))
  some(Result[string, string].err(writeRes.error))

proc logViewerSaveMessage(saved: Result[string, string]): string =
  if saved.isOk:
    "Log saved: " & saved.get
  else:
    "Log save failed: " & saved.error

proc updateViewportForCursor*(e: Editor, pos: BufferPosition) =
  ## Update viewport to follow cursor position
  ## Common helper to avoid code duplication in search operations
  e.handlerManager.motionController.viewportManager.updateViewport(
    e.state, e.activeBuffer(), pos
  )

proc showFromView*(e: Editor, view: ViewState, pos: BufferPosition) =
  ## Scroll to `pos` from what the window showed in `view`, as Vim's
  ## incsearch restores the view before it moves to a match.
  e.activeWindow.viewport.restoreViewState(view)
  e.updateViewportForCursor(pos)

proc modifiedBufferCountExcept*(e: Editor, exclude: TextBuffer): int =
  ## Number of modified buffers other than `exclude`.
  for buf in e.buffers:
    if buf != exclude and buf.isModified:
      result.inc

proc hiddenChangesError*(e: Editor): string =
  ## Error for a forced close of the last window while a modified buffer no
  ## window shows would go with the session, as Vim's `:q!` (E162), or "".
  ## A window the session ends with, such as a Help window, holds nothing
  ## that survives it.
  for buf in e.buffers:
    if not buf.isModified:
      continue
    var held = false
    for win in e.windowManager.windows:
      if e.keepsSession(win) and e.holds(win, buf):
        held = true
        break
    if not held:
      return
        "No write since last change for buffer \"" & buf.displayName.get("[No Name]") &
        "\" (use :qa! to discard)"
  ""

proc closeLastWindowError*(e: Editor, visible: TextBuffer): string =
  ## Error for closing the last window, which ends the session, while any
  ## buffer is modified, or "" when none is. `visible` counts too: `C-w c`
  ## reaches the close without the check `:q` makes. The hint names `:qa!`
  ## where `:q!` would refuse too.
  var others = 0
  for buf in e.buffers:
    if buf != visible and buf.isModified:
      others.inc
  let hint =
    if e.hiddenChangesError().len > 0:
      " (use :qa! to discard)"
    else:
      " (use :q! to discard)"
  if visible.isModified:
    if others == 0:
      return "No write since last change" & hint
    return "No write since last change: " & $(others + 1) & " buffers modified" & hint
  if others == 0:
    return ""
  "No write since last change: " & $others & " other buffer" &
    (if others > 1: "s" else: "") & " modified" & hint

when not defined(moe.embedded):
  proc showJob(e: Editor, id: BufferId): Result[void, string] =
    ## As Vim's check_changed_any: go to a window that shows the job, else
    ## show it in the active one.
    for i, win in e.windowManager.windows:
      if e.isShowingTab(win, id):
        e.focusWindow(i)
        return ok()
    e.tryActivateBuffer(id)

proc runningJob*(e: Editor, spare = none(BufferId)): Option[BufferId] =
  ## The running Terminal job a quit would kill, found as Vim's E947 does:
  ## the jobs on screen first, the active window's before all. `spare` is the
  ## session a `:q!` ends along with its window.
  when defined(moe.embedded):
    none(BufferId)
  else:
    var ids: seq[BufferId]
    for win in @[e.activeWindow] & e.windowManager.windows:
      if e.isShowingTab(win, win.tabBufferId):
        ids.add win.tabBufferId
    for buf in e.buffers:
      ids.add buf.id
    for id in ids:
      if e.isJobRunning(id) and some(id) != spare:
        return some(id)
    none(BufferId)

proc refuseQuitFor*(
    e: Editor, job: BufferId, show: bool, wrote = "", endKeys = ":qa!"
) =
  ## Refuse the quit `job` would die with. Checked after any write the quit
  ## makes, so `:qa!` loses nothing more; `wrote` says what was written.
  ## `show` brings the job into view; `endKeys` is the command the hint names.
  ## The refusal fails the command, so a mapping stops there.
  when not defined(moe.embedded):
    let shown =
      if show:
        e.showJob(job)
      else:
        Result[void, string].ok()
    # The job is shown in its session's sub-mode; taking keys, a typed `:`
    # would reach it.
    let keys =
      if e.activeWindow.mode == EditorMode.Terminal:
        "Ctrl-\\ Ctrl-n, then " & endKeys
      else:
        endKeys
    let buffer = e.bufferById(job)
    let name =
      if buffer.isSome:
        buffer.get.displayName.get("")
      else:
        ""
    var message =
      "Job still running in buffer \"" & name & "\" (use " & keys & " to end it)"
    if wrote.len > 0:
      message = wrote & "; " & message
    if shown.isErr:
      message &= "; " & shown.error
    e.state.statusMessage = message
    e.state.beep()

proc refuseQuitForRunningJob*(e: Editor, show: bool, spare = none(BufferId)): bool =
  ## Whether a running Terminal job keeps the session from ending, as Vim's
  ## E947: the quit would kill it. See `runningJob` and `refuseQuitFor`.
  let job = e.runningJob(spare)
  if job.isSome:
    e.refuseQuitFor(job.get, show)
  job.isSome

type
  CloseVerdictKind* = enum
    cvClose ## The window closes and the session goes on.
    cvEndSession ## The window is the session's last, so the session ends.
    cvRefuse ## Changes keep the window; `message` says which.
    cvRefuseJob ## A running job, `job`, keeps the session from ending.

  CloseVerdict* = object
    ## What closing the active window comes to, decided before anything moves.
    case kind*: CloseVerdictKind
    of cvRefuse:
      message*: string
    of cvRefuseJob:
      job*: BufferId
    of cvClose, cvEndSession:
      discard

proc closeVerdict*(e: Editor, force, asQuit: bool): CloseVerdict =
  ## The checks of Vim's `:quit` (`asQuit`) or `:close`, in its order: the
  ## window's own changes, then those the session would lose, then a running
  ## job. Touches nothing. `force` ends the job the window shows.
  let win = e.activeWindow
  let shown = win.buffer
  if asQuit and not force:
    for held in e.heldBuffers(win):
      if held.isModified and e.holderCount(held) <= 1:
        return CloseVerdict(
          kind: cvRefuse, message: "No write since last change (add ! to override)"
        )
  let lastWindow =
    if asQuit:
      e.isLastSessionWindow()
    else:
      e.windowManager.windows.len <= 1
  if not lastWindow:
    return CloseVerdict(kind: cvClose)
  # `!` discards only what a window shows, as Vim's check_changed_any.
  let discardErr =
    if force:
      e.hiddenChangesError()
    else:
      e.closeLastWindowError(shown)
  if discardErr.len > 0:
    return CloseVerdict(kind: cvRefuse, message: discardErr)
  var spare = none(BufferId)
  when not defined(moe.embedded):
    if force and e.isShowingTab(win, win.tabBufferId):
      spare = some(win.tabBufferId)
  let job = e.runningJob(spare)
  if job.isSome:
    return CloseVerdict(kind: cvRefuseJob, job: job.get)
  CloseVerdict(kind: cvEndSession)

proc refuseClose*(e: Editor, verdict: CloseVerdict, wrote = "") =
  ## Report a refusing `verdict` as Vim's error, which ends a mapping. A job
  ## is brought into view. `wrote` says what a write before the close wrote.
  case verdict.kind
  of cvRefuse:
    e.state.statusMessage =
      if wrote.len > 0:
        wrote & "; " & verdict.message
      else:
        verdict.message
    e.state.beep()
  of cvRefuseJob:
    e.refuseQuitFor(verdict.job, show = true, wrote)
  of cvClose, cvEndSession:
    discard

proc showsRunningJob*(e: Editor, win: EditorWindow): bool =
  ## Whether `win` shows a Terminal job that is still running.
  when defined(moe.embedded):
    false
  else:
    e.isShowingTab(win, win.tabBufferId) and e.isJobRunning(win.tabBufferId)

proc refuseCloseForShownJob(e: Editor): bool =
  ## Whether `:wq`/`:x`/ZZ, `!` or not, keep a window showing a running job, as
  ## Vim's write of it under its own name fails (E382) before the window would
  ## close.
  when defined(moe.embedded):
    false
  else:
    let win = e.activeWindow
    let job = win.tabBufferId
    if not e.showsRunningJob(win):
      return false
    # `:q!` ends the job only with the last window holding it, and on the last
    # window it ends the session, which another job keeps.
    let jobBuffer = e.bufferById(job)
    let endKeys =
      if jobBuffer.isSome and e.holderCount(jobBuffer.get) > 1:
        ":bd!"
      elif e.isLastSessionWindow() and e.runningJob(spare = some(job)).isSome:
        ":qa!"
      else:
        ":q!"
    e.refuseQuitFor(job, show = false, endKeys = endKeys)
    true

proc logSave(e: Editor, path: string, isCopy: bool) =
  ## The log line a write by command leaves, if the settings ask for it.
  if e.config.notification.logNotifications and e.config.notification.saveLogNotify:
    logInfo(
      "handler",
      (if isCopy: "Copy written via command: " else: "File saved via command: ") & path,
    )

proc buildAndCheckOnSave(e: Editor, buffer: TextBuffer, savedPath: string) =
  ## The buildOnSave and syntaxCheckOnSave jobs a write of `buffer` starts.
  if e.config.buildOnSave.enable:
    let customCmd =
      if e.config.buildOnSave.command.isSome: e.config.buildOnSave.command.get else: ""
    let workspaceRoot =
      if e.config.buildOnSave.workspaceRoot.isSome:
        e.config.buildOnSave.workspaceRoot.get
      else:
        parentDir(savedPath)
    e.submitBuild(
      (
        path: savedPath,
        language: buffer.language.ord,
        customCmd: customCmd,
        workspaceRoot: workspaceRoot,
        automatic: true,
      )
    )
  if e.config.syntaxChecker.enable and
      syntaxCheckCommand(savedPath, buffer.language).isOk:
    e.submitSyntaxCheck(
      (
        path: savedPath,
        language: buffer.language.ord,
        buffer: buffer.id,
        awaited: buffer.awaitReport(dsrcSyntaxCheck),
        text: buffer.getTextString(),
      )
    )

const ConfigTakesNoFileName =
  "Error: Config saves its settings to the config file and takes no file name"
  ## Config's view is empty, so a copy of it would be too.

type
  QuitWrite* = object
    ## The write `:wq`, `:x` and `ZZ` make before the window or session goes.
    outcome: Option[WriteOutcome] ## The file write, none when there was none.
    wrote: string ## What the status line says was written, "" for nothing.
    buffer: TextBuffer ## What was written, which the close may take out of view.

  QuitWriteRefusal = object
    message: string

proc refuse(e: Editor, refusal: QuitWriteRefusal) =
  ## As a Vim error, the refusal ends the mapping that ran it.
  e.state.statusMessage = refusal.message
  e.state.beep()

type QuitWriteTarget = enum
  qwNothing ## `:x` and ZZ with nothing to write.
  qwConfig ## The settings, from Config.
  qwLog ## The log, from the log viewer, as `:w` there.
  qwBuffer ## The buffer, to its file or the one named.

proc quitWriteTarget(e: Editor, r: HandlerResult, buffer: TextBuffer): QuitWriteTarget =
  ## What the write of :wq/:x/ZZ writes.
  if e.state.mode == EditorMode.Config:
    # Config keeps no modified state, so its `:x` writes as `:wq` does.
    return qwConfig
  # As Vim's bufIsChanged, a running job counts as a change.
  if r.writeOnlyIfModified and not buffer.isModified and
      not e.showsRunningJob(e.activeWindow):
    return qwNothing
  if e.state.mode == EditorMode.LogViewer and r.saveAndQuitFilename.isNone:
    # The log is never modified, so `:x` and ZZ write none: each write is a
    # new file.
    return qwLog
  qwBuffer

proc writeBuffer(
    e: Editor, r: HandlerResult, buffer: TextBuffer
): Result[QuitWrite, QuitWriteRefusal] =
  let saveResult = e.saveFile(buffer, r.saveAndQuitFilename, r.forceQuitAfterSave)
  if saveResult.isErr:
    logError("handler", "Write before quit failed: " & saveResult.error)
    return err(QuitWriteRefusal(message: "Error: " & saveResult.error))
  let saved = saveResult.get
  let isCopy = saved.kind == wkCopy
  e.logSave(saved.path, isCopy)
  let wrote = (if isCopy: "Saved a copy: " else: "Saved: ") & saved.path
  ok(QuitWrite(outcome: some(saved), wrote: wrote))

proc writeBeforeQuit(
    e: Editor, r: HandlerResult, buffer: TextBuffer
): Result[QuitWrite, QuitWriteRefusal] =
  case e.quitWriteTarget(r, buffer)
  of qwNothing:
    ok(QuitWrite())
  of qwConfig:
    let written = e.writeConfigFile()
    if written.isErr:
      return err(QuitWriteRefusal(message: written.error.saveFailedMessage))
    ok(QuitWrite(wrote: "Config saved: " & written.get))
  of qwLog:
    # Without a log in the window, it writes as any buffer does.
    let saved = e.trySaveLogViewerBuffer()
    if saved.isNone:
      return e.writeBuffer(r, buffer)
    let msg = logViewerSaveMessage(saved.get)
    if saved.get.isOk:
      return ok(QuitWrite(wrote: msg))
    err(QuitWriteRefusal(message: msg))
  of qwBuffer:
    e.writeBuffer(r, buffer)

proc refuseQuitBeforeWrite*(e: Editor, r: HandlerResult): bool =
  ## Whether :wq/:x/ZZ fail before anything is touched.
  if r.saveAndQuitFilename.isNone and e.refuseCloseForShownJob():
    return true
  if e.state.mode == EditorMode.Config and r.saveAndQuitFilename.isSome:
    e.refuse(QuitWriteRefusal(message: ConfigTakesNoFileName))
    return true
  false

proc writeForQuit*(e: Editor, r: HandlerResult): Option[QuitWrite] =
  ## The write :wq/:x/ZZ make before the :quit that follows, none when the
  ## command was refused. Nothing is reported until the close shows whether
  ## the editor stays: see `reportQuitWrite`.
  let buffer = e.activeBuffer()
  let written = e.writeBeforeQuit(r, buffer)
  if written.isErr:
    e.refuse(written.error)
    return none(QuitWrite)
  var quitWrite = written.get
  quitWrite.buffer = buffer
  some(quitWrite)

proc wrote*(written: QuitWrite): string =
  written.wrote

proc warnings*(written: QuitWrite): seq[string] =
  if written.outcome.isSome:
    written.outcome.get.warnings
  else:
    @[]

proc startQuitWriteBuild(e: Editor, written: QuitWrite) =
  ## What a `:w` of the file starts. A copy starts nothing.
  let outcome = written.outcome
  if outcome.isSome and outcome.get.kind != wkCopy:
    e.buildAndCheckOnSave(written.buffer, outcome.get.path)

proc reportQuitWrite*(e: Editor, written: QuitWrite) =
  ## Report the write of :wq/:x/ZZ when the window closed and the editor stays.
  # Config and the log viewer report their write as `:w` does there.
  let notify =
    written.outcome.isNone or (
      e.config.notification.screenNotifications and
      e.config.notification.saveScreenNotify
    )
  if notify and written.wrote.len > 0:
    e.state.statusMessage = written.wrote
  # After the write's message, which a build announcing itself replaces.
  e.startQuitWriteBuild(written)
  for warning in written.warnings:
    e.appendStatus(warning)

proc reportRefusedQuitWrite*(e: Editor, written: QuitWrite, verdict: CloseVerdict) =
  ## Report the write of :wq/:x/ZZ and the refusal of the :quit after it.
  # Before the refusal, which a build announcing itself would hide.
  e.startQuitWriteBuild(written)
  e.refuseClose(verdict, written.wrote)
  for warning in written.warnings:
    e.appendStatus(warning)

proc skippedSummary(skipped: seq[SkippedSave]): string =
  ## Batch skip reasons, counted per reason.
  var counts: array[WriteRefusal, int]
  for (_, _, reason) in skipped:
    counts[reason] += 1
  var parts: seq[string]
  for reason, count in counts.pairs:
    if count == 0:
      continue
    let what =
      case reason
      of writeAllowed: ""
      of writeRefusedChangedOnDisk: "changed on disk"
      of writeRefusedUnreadFile: "appeared on disk unread"
      of writeRefusedUnverifiedFile: "could not be checked on disk"
      of writeRefusedHeldByAnotherBuffer: "open in another modified buffer"
      of writeRefusedTargetExists: "already exists"
    parts.add $count & " " & what
  parts.join(", ")

proc saveAllStatusMessage(saveResult: SaveAllBuffersResult): string =
  ## Build a status message summarising a saveAllBuffers result.
  if saveResult.failures.len > 0:
    let first = saveResult.failures[0]
    if saveResult.failures.len == 1:
      return "Save failed: " & first.path & ": " & first.error
    return
      "Save failed for " & $saveResult.failures.len & " files; first: " & first.path &
      ": " & first.error
  if saveResult.savedCount == 0:
    if saveResult.skippedExternal.len > 0:
      return
        "No files saved (" & skippedSummary(saveResult.skippedExternal) &
        ", use :wa! to override)"
    return "No modified files to save"
  let leftUnsaved =
    if saveResult.unwritten.len > 0:
      # Loser's edits remain in its buffer.
      "; " & $saveResult.unwritten.len & " left unsaved (another buffer holds the file)"
    else:
      ""
  var msg =
    if saveResult.savedCount == 1:
      "Saved: " & saveResult.savedPaths[0]
    else:
      "Saved " & $saveResult.savedCount & " files"
  if saveResult.skippedExternal.len > 0:
    msg.add(
      " (skipped: " & skippedSummary(saveResult.skippedExternal) &
        ", use :wa! to override)"
    )
  msg & leftUnsaved

proc logSaveAll(e: Editor, saveResult: SaveAllBuffersResult) =
  ## The log line `:wa` leaves, if the settings ask for it.
  if e.config.notification.logNotifications and e.config.notification.saveLogNotify and
      saveResult.savedCount > 0:
    if saveResult.savedCount == 1:
      logInfo("handler", "Saved file via :wa: " & saveResult.savedPaths[0])
    else:
      logInfo("handler", "Saved " & $saveResult.savedCount & " files via :wa")

proc processSaveAllResult*(e: Editor, r: HandlerResult) =
  ## Save all modified buffers and report the outcome.
  ## buildOnSave / syntaxCheckOnSave are skipped: :wa is a batch operation.
  let saveResult = e.saveAllBuffers(r.forceSaveAll)
  let msg = saveAllStatusMessage(saveResult)
  # Surface failures / skips / no-op; gate the success summary on saveScreenNotify.
  if saveResult.failures.len > 0 or saveResult.skippedExternal.len > 0 or
      saveResult.unwritten.len > 0 or saveResult.savedCount == 0:
    e.state.statusMessage = msg
  elif e.config.notification.screenNotifications and
      e.config.notification.saveScreenNotify:
    e.state.statusMessage = msg
  for warning in saveResult.warnings:
    e.appendStatus(warning)
  e.logSaveAll(saveResult)

proc processSaveAllAndQuitResult*(e: Editor, r: HandlerResult): bool =
  ## Save all and quit: false on full success, true if any save failed or
  ## was skipped for external modification without force, or a job runs.
  let saveResult = e.saveAllBuffers(r.forceSaveAllAndQuitAfter)
  # Quitting discards unwritten buffers, so stay without `!` and say why.
  if saveResult.failures.len > 0 or saveResult.skippedExternal.len > 0:
    e.state.statusMessage = saveAllStatusMessage(saveResult)
    logError("handler", "Save all and quit aborted: " & e.state.statusMessage)
    # The editor stays, so the files that were written say what went wrong here.
    for warning in saveResult.warnings:
      e.appendStatus(warning)
    return true
  # As Vim's E948, after the writes and without bringing the job into view.
  let job =
    if r.forceSaveAllAndQuitAfter:
      none(BufferId)
    else:
      e.runningJob()
  if job.isSome:
    e.logSaveAll(saveResult)
    let wrote =
      if saveResult.savedCount > 0:
        saveAllStatusMessage(saveResult)
      else:
        ""
    e.refuseQuitFor(job.get, show = false, wrote)
    for warning in saveResult.warnings:
      e.appendStatus(warning)
    return true
  if saveResult.unwritten.len > 0:
    # Forced quit discards the edits that lost the race; leave a trace.
    logWarn(
      "handler",
      "Quitting with " & $saveResult.unwritten.len &
        " buffer(s) left unsaved on files another buffer wrote",
    )
  for warning in saveResult.warnings:
    e.state.exitReports.add warning
  logInfo("handler", "All files saved, quitting editor")
  false

proc processSaveResult*(e: Editor, r: HandlerResult, activeBuffer: TextBuffer) =
  ## Save the active buffer (or LogViewer/Config content) and run the
  ## buildOnSave / syntaxCheckOnSave side effects.
  if e.state.mode == EditorMode.LogViewer and r.saveFilename.isNone:
    let saved = e.trySaveLogViewerBuffer()
    if saved.isSome:
      e.state.statusMessage = logViewerSaveMessage(saved.get)
      return
    # Without a log in the window, it writes as any buffer does, as `:wq`.
  if e.state.mode == EditorMode.Config and r.saveFilename.isSome:
    e.state.statusMessage = ConfigTakesNoFileName
  elif e.state.mode == EditorMode.Config:
    let written = e.writeConfigFile()
    if written.isOk:
      e.state.statusMessage = "Config saved: " & written.get
      logInfo("config", "Config saved: " & written.get)
    else:
      e.state.statusMessage = written.error.saveFailedMessage
  else:
    let saveResult =
      e.saveFile(activeBuffer, r.saveFilename, r.forceSave, saveAs = r.saveAs)
    if saveResult.isErr:
      logError("handler", "Save command failed: " & saveResult.error)
      e.state.statusMessage = "Error: " & saveResult.error
    else:
      let
        savedPath = saveResult.get.path
        isCopy = saveResult.get.kind == wkCopy
      e.logSave(savedPath, isCopy)
      if e.config.notification.screenNotifications and
          e.config.notification.saveScreenNotify:
        e.state.statusMessage =
          (if isCopy: "Saved a copy: " else: "Saved: ") & savedPath
      for warning in saveResult.get.warnings:
        e.appendStatus(warning)
      if isCopy:
        # Not a save of the buffer, so nothing runs on save.
        return
      e.buildAndCheckOnSave(activeBuffer, savedPath)

proc processGotoLineResult*(e: Editor, r: HandlerResult, activeBuffer: TextBuffer) =
  ## Move the cursor to the first non-blank of the line, as Vim's
  ## 'startofline' does.
  if activeBuffer.len == 0:
    return
  let line = r.lineNumber - 1
  e.activeWindow.cursor.line = line
  e.activeWindow.cursor.column = firstNonBlankColumn(activeBuffer.getLine(line))
  e.state.preferredColumn = -1
  e.updateViewportForCursor(e.cursor)

proc enterFilerInActiveWindow*(e: Editor, path: string) =
  ## Open the filer on `path`, starting on the current file when it is there.
  let filerState = newFilerState(path)
  let current = e.commandTab().filePath
  if current.isSome:
    let file = pathKey(current.get)
    if file.parentDir == filerState.currentPath:
      filerState.selectEntry(file.extractFilename)
  let entered = e.enterViewerMode(
    EditorMode.Filer,
    ModeState(kind: mskFiler, filer: filerState),
    filerState.createFilerTextBuffer(e.config.filer.showIcons),
    vpInPlace,
  )
  if entered.isErr:
    e.state.statusMessage = "Failed to open filer: " & entered.error

proc focusFileTreeWindow*(e: Editor): bool =
  ## Focus the fileTree sidebar, or return false if none is open. Unlike
  ## `toggleFileTree`, it never closes the sidebar.
  for i, win in e.windowManager.windows:
    if win.isSidebar:
      e.windowManager.activateWindow(i)
      e.syncActiveWindow()
      return true
  false

proc toggleFileTree*(e: Editor, pathOpt: Option[string], activeBuffer: TextBuffer) =
  ## Toggle the fileTree sidebar (open if absent, close if present).
  var existingIdx = -1
  for i, win in e.windowManager.windows:
    if win.isSidebar:
      existingIdx = i
      break

  if existingIdx >= 0:
    e.windowManager.activateWindow(existingIdx)
    e.syncActiveWindow()
    e.closeFileTree()
    return

  # Create fileTree window as left-side vsplit (follows vsplit pattern)
  let rootPath =
    if pathOpt.isSome:
      pathOpt.get
    elif activeBuffer.filePath.isSome:
      parentDir(activeBuffer.filePath.get)
    else:
      getCurrentDir()

  let ftState = newFileTreeState(rootPath, e.config.fileTree.width)
  let ftBuffer = ftState.createFileTreeTextBuffer(e.config.filer.showIcons)
  let ftWidth = ftState.width

  # Compute full extent across ALL windows for filetree's full-height span
  var minX = int.high
  var maxXEnd = 0
  var minY = int.high
  var maxYEnd = 0
  for win in e.windowManager.windows:
    minX = min(minX, win.viewport.x)
    maxXEnd = max(maxXEnd, win.viewport.x + win.viewport.width)
    minY = min(minY, win.viewport.y)
    maxYEnd = max(maxYEnd, win.viewport.y + win.viewport.height)

  let
    totalWidth = maxXEnd - minX
    startX = minX
    fullHeight = maxYEnd - minY

  e.windowManager.deactivateAllWindows()

  let ftWindow = EditorWindow(
    viewBuffer: ftBuffer,
    tabBufferId: ftBuffer.id,
    bufferIds: @[ftBuffer.id], # FileTree pane has its own single-tab list
    viewport: ViewPort(
      topLine: 0, leftCell: 0, width: ftWidth, height: fullHeight, x: startX, y: minY
    ),
    cursor: BufferPosition(line: 0, column: 0),
    active: false,
    mode: EditorMode.FileTree,
    modeState: ModeState(kind: mskFileTree, fileTree: ftState),
    fixedWidth: some(ftWidth),
    wrapCountCache: WrapCountCache(),
  )

  e.windowManager.windows.insert(ftWindow, 0)
  e.windowManager.activeWindowIndex += 1
  e.windowManager.windows[e.windowManager.activeWindowIndex].active = true

  # Group by Y-row and equalize each row's widths
  var yRows: seq[int] = @[]
  for i in 1 ..< e.windowManager.windows.len:
    let y = e.windowManager.windows[i].viewport.y
    if y notin yRows:
      yRows.add(y)

  for y in yRows:
    var group: seq[int] = @[0] # filetree spans all rows (fullHeight)
    for i in 1 ..< e.windowManager.windows.len:
      if e.windowManager.windows[i].viewport.y == y:
        group.add(i)
    e.windowManager.equalizeWidthsInGroup(group, totalWidth, startX)

  e.syncActiveWindow()

when not defined(moe.embedded):
  proc installTerminalSession*(
      e: Editor, termState: TerminalState, command: string
  ): TextBuffer =
    ## Register `termState` as a new tab and hand the active window over to it.
    ## The PTY is tracked in `e.terminalStates` by buffer id, so the session
    ## survives view swaps and tab switches. Returns the session's buffer.
    let activeWin = e.activeWindow
    # A session with no command still needs a name, so it takes the shell it
    # runs. The spawn command itself stays empty (an interactive shell).
    let base =
      if command.len > 0:
        command
      else:
        defaultShellName()
    # A second session of the same command gets its own name, as in Vim, so
    # `:b` can still tell them apart. The suffix only grows, so a new session
    # never takes a number that sorts before a live one.
    var last = -1
    for buf in e.buffers:
      for alias in buf.matchAliases:
        if alias == base:
          last = max(last, 0)
        elif alias.startsWith(base & " (") and alias.endsWith(")"):
          try:
            last = max(last, parseInt(alias[base.len + 2 .. ^2]))
          except ValueError:
            discard
    let name =
      if last < 0:
        base
      else:
        base & " (" & $(last + 1) & ")"
    result = newTextBuffer("")
    result.displayName = some("[Terminal: " & name & "]")
    # The name is the session's stable `:b` key; the label is presentation
    # only, so matching survives label changes.
    result.matchAliases = @[name]
    # Input goes to the PTY; a window that reaches this buffer in a text mode
    # must not be able to edit, save or preserve it.
    result.readOnly = true

    e.addBuffer(result)
    e.addBufferToWindowList(result)
    e.terminalStates[result.id] = termState

    # Shared tab transition drops viewer bookkeeping and derives Terminal mode.
    discard e.moveWindowToTab(activeWin, result)

proc enterTerminalInActiveWindow*(e: Editor, command: string) =
  when defined(moe.embedded):
    e.state.statusMessage = "Terminal mode is unavailable in embedded builds"
  else:
    ## Open a new Terminal session as a tab in the active window.
    let switchable = e.activeWindow.checkTabSwitch()
    if switchable.isErr:
      # Before the PTY starts.
      e.state.statusMessage = switchable.error
      return
    let (cols, rows) = e.calculateTerminalAreaDimensions(e.activeWindow)
    let termResult = newTerminalState(command, cols, rows)
    if termResult.isErr:
      e.state.statusMessage = "Terminal error: " & termResult.error
      return

    discard e.installTerminalSession(termResult.get, command)

proc applyThemeCommand*(e: Editor, themeName: string) =
  ## Apply a `:theme` selection via `initTheme` so `config.theme` and
  ## `themeColors` stay in sync before saveConfigToToml.
  if themeName == "default":
    e.config.theme.kind = tkDefault
    e.config.theme.path = ""
    initTheme(e.config)
    e.state.statusMessage = "Theme changed to: default"
    return

  let themePath = getHomeDir() / ".config" / "moe" / "themes" / (themeName & ".toml")
  if not fileExists(themePath):
    e.state.statusMessage = "Theme not found: " & themeName
    return

  let previousTheme = e.config.theme
  e.config.theme.kind = tkConfig
  e.config.theme.path = themePath
  var vr = newValidationResult()
  initTheme(e.config, vr)
  if vr.hasErrors:
    e.config.theme = previousTheme
    initTheme(e.config)
    e.state.statusMessage = "Failed to load theme: " & vr.toErrorMessages.join("; ")
  else:
    e.state.statusMessage = "Theme changed to: " & themeName
